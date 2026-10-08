#!/usr/bin/env python3
"""Verify thrown grenades interpolate smoothly between demo samples."""

from __future__ import annotations

from pathlib import Path
import subprocess
import time

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT / "demos" / "pro-2004-m19-vs-virtuspro-de_aztec.dem"
PORT = 5238


def main() -> int:
    server = subprocess.Popen(
        ["npm", "run", "dev", "--", "--host", "127.0.0.1", "--port", str(PORT)],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(1)
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            page = browser.new_page(viewport={"width": 1280, "height": 800})
            page.goto(f"http://127.0.0.1:{PORT}", wait_until="networkidle")
            with page.expect_file_chooser() as chooser:
                page.locator(".drop-zone").click()
            chooser.value.set_files(str(DEMO))
            page.wait_for_function(
                "() => window.demoPlayer?.verificationReport?.status",
                timeout=120_000,
            )
            result = page.evaluate(
                """() => {
                  const p = window.demoPlayer;
                  const d = p.timeline;
                  const previousByEntity = new Map();
                  let pair = null;
                  for (let i = 0; i < d.objTimes.length; i++) {
                    const ent = d.objEnts[i];
                    const kind = d.objKinds[i];
                    const offset = i * 3;
                    const point = {
                      index: i,
                      ent,
                      kind,
                      time: d.objTimes[i],
                      raw: [d.objPositions[offset], d.objPositions[offset + 1], d.objPositions[offset + 2]],
                    };
                    const previous = previousByEntity.get(ent);
                    if (previous && previous.kind === kind && kind >= 1 && kind <= 3) {
                      const gap = point.time - previous.time;
                      const distance = Math.hypot(
                        point.raw[0] - previous.raw[0],
                        point.raw[1] - previous.raw[1],
                        point.raw[2] - previous.raw[2],
                      );
                      if (gap >= 0.035 && gap <= 0.15 && distance >= 12) {
                        pair = { previous, next: point, gap, distance };
                        break;
                      }
                    }
                    previousByEntity.set(ent, point);
                  }
                  if (!pair) return null;

                  const samples = [];
                  for (const fraction of [0, 0.25, 0.5, 0.75, 0.99]) {
                    p.currentTime = pair.previous.time + pair.gap * fraction;
                    p.updateObjects();
                    const object = p.objectMeshes.get(pair.previous.ent);
                    samples.push({
                      fraction,
                      position: object
                        ? [object.group.position.x, object.group.position.y, object.group.position.z]
                        : null,
                      rotation: object
                        ? [object.group.rotation.x, object.group.rotation.y, object.group.rotation.z]
                        : null,
                    });
                  }
                  return { pair, samples };
                }"""
            )
            browser.close()
    finally:
        server.terminate()
        server.wait(timeout=10)

    print(f"Grenade interpolation: {result}")
    if result is None:
        print("Grenade motion regression: FAIL (no moving sample pair)")
        return 1

    previous = result["pair"]["previous"]["raw"]
    following = result["pair"]["next"]["raw"]
    expected_start = [previous[0] * 0.01, previous[2] * 0.01, -previous[1] * 0.01]
    expected_end = [following[0] * 0.01, following[2] * 0.01, -following[1] * 0.01]
    positions = [sample["position"] for sample in result["samples"]]
    rotations = [sample["rotation"] for sample in result["samples"]]
    max_error = 0.0
    for sample, position in zip(result["samples"], positions):
        if position is None:
            max_error = float("inf")
            break
        fraction = sample["fraction"]
        expected = [
            start + (end - start) * fraction
            for start, end in zip(expected_start, expected_end)
        ]
        max_error = max(max_error, *(abs(actual - target) for actual, target in zip(position, expected)))
    step_distances = [
        sum((right - left) ** 2 for left, right in zip(a, b)) ** 0.5
        for a, b in zip(positions, positions[1:])
        if a is not None and b is not None
    ]
    rotation_changed = rotations[0] is not None and rotations[-1] is not None and any(
        abs(end - start) > 0.01 for start, end in zip(rotations[0], rotations[-1])
    )
    valid = (
        max_error < 1e-5
        and len(step_distances) == 4
        and all(distance > 0.001 for distance in step_distances)
        and rotation_changed
    )
    print(f"Max interpolation error: {max_error:.8f}; steps: {step_distances}")
    print("Grenade motion regression:", "PASS" if valid else "FAIL")
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
