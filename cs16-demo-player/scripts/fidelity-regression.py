#!/usr/bin/env python3
"""Render stable replay checkpoints and compare low-resolution visual signatures."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import time

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]
BASELINES = ROOT / "scripts" / "fidelity-baselines.json"
CASES = [
    ("nuke-hltv", "demos/corpus/GFinal2 (LZucpro_vs_Hybrid) de_nuke.dem", 43.0),
    ("aztec-pro", "demos/pro-2004-m19-vs-virtuspro-de_aztec.dem", 272.0),
    ("inferno-pov", "demos/col-3d-inf-finals-ct.dem", 120.0),
]


def snapshot(page, path: Path, demo_time: float) -> dict[str, object]:
    with page.expect_file_chooser() as chooser:
        page.locator(".drop-zone").click()
    chooser.value.set_files(str(path))
    page.wait_for_function(
        "() => window.demoPlayer?.verificationReport?.status",
        timeout=120_000,
    )
    page.wait_for_function("() => !!window.demoPlayer?.mapMesh", timeout=30_000)
    state = page.evaluate(
        """({time}) => {
          const p = window.demoPlayer;
          p.seekToTime(Math.min(time, p.duration * 0.8));
          const recorded = p.timeline.povTimes.length > 0;
          let target = recorded ? 'Spectator Camera' : null;
          if (!target) {
            const dead = p.computeDeaths(p.currentTime);
            target = p.timeline.slot_names.find(name => !dead.has(name)) ?? null;
          }
          p.setFollowTarget(target);
          p.seekToTime(p.currentTime + 0.05);
          return { target, recorded, time: p.currentTime };
        }""",
        {"time": demo_time},
    )
    page.wait_for_timeout(1_200)
    result = page.evaluate(
        """() => {
          const p = window.demoPlayer;
          p.renderer.render(p.scene, p.camera);
          const thumb = document.createElement('canvas');
          thumb.width = 64;
          thumb.height = 36;
          const context = thumb.getContext('2d', { willReadFrequently: true });
          context.drawImage(p.renderer.domElement, 0, 0, thumb.width, thumb.height);
          const rgba = context.getImageData(0, 0, thumb.width, thumb.height).data;
          const luma = [];
          for (let i = 0; i < rgba.length; i += 4) {
            luma.push(Math.round((rgba[i] * 3 + rgba[i + 1] * 6 + rgba[i + 2]) / 160));
          }
          let cones = 0;
          let visibleBodies = 0;
          let finiteMeshes = true;
          p.scene.traverse(object => {
            if (object.name === 'viewCone') cones++;
            if (object.name === 'body' && object.visible) visibleBodies++;
            const v = object.position;
            finiteMeshes &&= Number.isFinite(v.x) && Number.isFinite(v.y) && Number.isFinite(v.z);
          });
          return {
            map: p.mapName,
            duration: p.duration,
            target: p.followTarget,
            source: document.getElementById('hud-source')?.textContent ?? '',
            camera: p.camera.position.toArray(),
            cones,
            visibleBodies,
            finiteMeshes,
            viewModelVisible: !!p.viewModel?.visible,
            verification: p.verificationReport?.status,
            screenFades: [...p.timeline.hudKinds].filter(kind => kind === 9).length,
            luma,
          };
        }"""
    )
    result.update(state)
    return result


def mean_absolute_difference(left: list[int], right: list[int]) -> float:
    if len(left) != len(right) or not left:
        return float("inf")
    return sum(abs(a - b) for a, b in zip(left, right)) / len(left)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--update", action="store_true", help="Replace visual baselines")
    parser.add_argument("--screenshots", action="store_true")
    parser.add_argument("--port", type=int, default=5228)
    args = parser.parse_args()

    expected = json.loads(BASELINES.read_text()) if BASELINES.exists() else {}
    actual: dict[str, dict[str, object]] = {}
    artifacts = ROOT / "artifacts" / "fidelity-regression"
    if args.screenshots:
        artifacts.mkdir(parents=True, exist_ok=True)

    server = subprocess.Popen(
        ["npm", "run", "dev", "--", "--host", "127.0.0.1", "--port", str(args.port)],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(1)
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            page = browser.new_page(viewport={"width": 1440, "height": 900})
            page.goto(f"http://127.0.0.1:{args.port}", wait_until="networkidle")
            for name, relative_path, demo_time in CASES:
                result = snapshot(page, ROOT / relative_path, demo_time)
                actual[name] = result
                if args.screenshots:
                    page.screenshot(path=str(artifacts / f"{name}.png"), full_page=True)
                page.reload(wait_until="networkidle")
            browser.close()
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()

    if args.update or not expected:
        BASELINES.write_text(json.dumps(actual, indent=2) + "\n")
        print(f"Updated {BASELINES.relative_to(ROOT)} with {len(actual)} checkpoints.")
        return 0

    failures: list[str] = []
    summary: list[dict[str, object]] = []
    for name, result in actual.items():
        baseline = expected.get(name)
        if not baseline:
            failures.append(f"{name}: missing baseline")
            continue
        difference = mean_absolute_difference(baseline["luma"], result["luma"])
        structural = (
            result["verification"] == "pass"
            and result["finiteMeshes"]
            and all(isinstance(value, (int, float)) for value in result["camera"])
            and result["cones"] == 0
            and result["visibleBodies"] == 0
            and result["map"] == baseline["map"]
            and result["source"] == baseline["source"]
            and result["screenFades"] == baseline["screenFades"]
        )
        if not structural or difference > 2.5:
            failures.append(f"{name}: structural={structural}, visual MAD={difference:.3f}")
        summary.append({
            "case": name,
            "map": result["map"],
            "source": result["source"],
            "visualMad": round(difference, 3),
            "ok": structural and difference <= 2.5,
        })

    print(json.dumps(summary, indent=2))
    if failures:
        print("\nFidelity regression failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print(f"\nFidelity regression: {len(summary)}/{len(summary)} passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
