#!/usr/bin/env python3
"""Load every bundled demo and exercise deterministic seeks in Chromium."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import time

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]


def audit_demo(page, demo: Path, index: int, args, errors: list[str]) -> dict[str, object]:
    with page.expect_file_chooser() as chooser:
        page.locator(".drop-zone").click()
    chooser.value.set_files(str(demo))
    page.wait_for_function(
        "() => window.demoPlayer?.verificationReport?.status",
        timeout=120_000,
    )
    state = page.evaluate(
        """() => {
          const p = window.demoPlayer;
          const samples = [0.1, 0.5, 0.9].map(fraction => {
            p.seekToTime(p.duration * fraction);
            return {
              time: p.currentTime,
              camera: p.camera.position.toArray(),
              effects: p.fx.length,
            };
          });
          return {
            map: p.mapName,
            duration: p.duration,
            verification: p.verificationReport,
            samples,
            finite: samples.every(sample => sample.camera.every(Number.isFinite)),
            effectCap: samples.every(sample => sample.effects <= p.maxLiveEffects),
          };
        }"""
    )
    expected_invalid = "known-bad" in demo.parts
    valid = (
        state["verification"]["status"] != "fail"
        and state["finite"]
        and state["effectCap"]
        and not errors
    )
    if args.screenshots:
        page.screenshot(
            path=str(ROOT / "artifacts" / "corpus-regression" / f"{index:02d}-{demo.stem}.png"),
            full_page=True,
        )
    return {
        "demo": str(demo.relative_to(ROOT)),
        "ok": (not valid) if expected_invalid else valid,
        "expectedInvalid": expected_invalid,
        "state": state,
        "errors": list(errors),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0, help="Only test the first N demos")
    parser.add_argument("--match", default="", help="Only test paths containing this text")
    parser.add_argument("--port", type=int, default=5217)
    parser.add_argument("--screenshots", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--shard-index", type=int, default=0)
    parser.add_argument("--shard-count", type=int, default=1)
    args = parser.parse_args()

    demos = sorted((ROOT / "demos").rglob("*.dem"))
    if args.match:
        demos = [demo for demo in demos if args.match.lower() in str(demo).lower()]
    if args.limit:
        demos = demos[: args.limit]
    if args.shard_count < 1 or not 0 <= args.shard_index < args.shard_count:
        parser.error("--shard-index must be between 0 and --shard-count - 1")
    if args.shard_count > 1:
        demos = [
            demo for index, demo in enumerate(demos)
            if index % args.shard_count == args.shard_index
        ]
    if not demos:
        print("No demos found.")
        return 1

    artifacts = ROOT / "artifacts" / "corpus-regression"
    if args.screenshots:
        artifacts.mkdir(parents=True, exist_ok=True)
    server = subprocess.Popen(
        ["npm", "run", "dev", "--", "--host", "127.0.0.1", "--port", str(args.port)],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    results: list[dict[str, object]] = []
    try:
        time.sleep(1)
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            page = browser.new_page(viewport={"width": 1440, "height": 900})
            error_bucket: dict[str, list[str]] = {"value": []}
            page.on("pageerror", lambda error: error_bucket["value"].append(str(error)))
            page.goto(f"http://127.0.0.1:{args.port}", wait_until="networkidle")
            for index, demo in enumerate(demos):
                for attempt in range(2):
                    error_bucket["value"] = []
                    try:
                        results.append(audit_demo(
                            page, demo, index, args, error_bucket["value"],
                        ))
                        break
                    except Exception as error:  # retry transient browser/load failures once
                        if attempt == 1:
                            results.append({
                                "demo": str(demo.relative_to(ROOT)),
                                "ok": False,
                                "error": str(error),
                                "errors": list(error_bucket["value"]),
                            })
                        else:
                            page.reload(wait_until="networkidle")
                page.reload(wait_until="networkidle")
            browser.close()
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()

    output = results if args.verbose else [{
        "demo": result["demo"],
        "ok": result["ok"],
        "expectedInvalid": result.get("expectedInvalid", False),
        "status": result.get("state", {}).get("verification", {}).get("status"),
        "checksum": result.get("state", {}).get("verification", {}).get("checksum"),
        "error": result.get("error"),
        "errors": result.get("errors", []),
    } for result in results]
    print(json.dumps(output, indent=2))
    passed = sum(bool(result["ok"]) for result in results)
    print(f"\nCorpus regression: {passed}/{len(results)} passed")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
