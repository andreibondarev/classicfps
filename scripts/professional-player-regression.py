#!/usr/bin/env python3
"""Exercise spectator controls, broadcast HUD, BSP dynamics, and event seeks."""

from __future__ import annotations

from pathlib import Path
import json
import subprocess
import time

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT / "demos" / "pro-2004-m19-vs-virtuspro-de_aztec.dem"
PORT = 5241


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
            page = browser.new_page(viewport={"width": 1600, "height": 900})
            page.goto(f"http://127.0.0.1:{PORT}", wait_until="networkidle")
            with page.expect_file_chooser() as chooser:
                page.locator(".drop-zone").click()
            chooser.value.set_files(str(DEMO))
            page.wait_for_function(
                "() => window.demoPlayer?.verificationReport?.status && window.demoPlayer?.mapMesh",
                timeout=120_000,
            )
            result = page.evaluate(
                """() => {
                  const p = window.demoPlayer;
                  p.seekToTime(35);
                  const living = p.livingFollowTargets();
                  p.setFollowTarget(living[0]);
                  const first = p.followTarget;
                  p.cycleFollowTarget(1);
                  const second = p.followTarget;
                  p.restorePreviousCamera();
                  const restored = p.followTarget;
                  p.setHudMode('broadcast', false);
                  p.updatePlayback();

                  const snapshot = (time) => {
                    p.setFollowTarget(null, false);
                    p.seekToTime(time);
                    return JSON.stringify({
                      time: p.currentTime,
                      follow: p.followTarget,
                      deaths: [...p.computeDeaths(time)].sort(),
                      players: [...p.playerMeshes].map(([name, mesh]) => [
                        name,
                        mesh.visible,
                        mesh.position.toArray().map((value) => +value.toFixed(6)),
                      ]).sort(),
                      score: [p.scoreCT, p.scoreT],
                    });
                  };
                  const boundaries = p.timeline.events
                    .filter((event) => ['Kill', 'BombPlanted', 'BombDefused', 'RoundStart'].includes(event.event_type))
                    .slice(0, 5)
                    .flatMap((event) => [Math.max(0, event.time - .01), event.time, event.time + .01]);
                  const firstPass = boundaries.map(snapshot);
                  const secondPass = boundaries.map(snapshot);
                  return {
                    living: living.length,
                    first,
                    second,
                    restored,
                    controls: ['prev-player-btn', 'next-player-btn', 'camera-back-btn', 'skip-select']
                      .every((id) => !!document.getElementById(id)),
                    compactRoster: document.querySelectorAll('#spectator-roster .spectator-player').length,
                    broadcastCards: document.querySelectorAll('#broadcast-overlay .broadcast-card').length,
                    dynamicBrushes: p.dynamicBrushes.length,
                    hasWorld: !!p.mapMesh.getObjectByName('worldspawn'),
                    deterministicSeeks: firstPass.every((value, index) => value === secondPass[index]),
                    assetPreflight: p.assetPreflight,
                  };
                }"""
            )
            browser.close()
    finally:
        server.terminate()
        server.wait(timeout=10)

    print(json.dumps(result, indent=2))
    valid = (
        result["living"] >= 2
        and result["first"] != result["second"]
        and result["restored"] == result["first"]
        and result["controls"]
        and result["broadcastCards"] >= 8
        and result["dynamicBrushes"] > 0
        and result["hasWorld"]
        and result["deterministicSeeks"]
    )
    print("Professional player regression:", "PASS" if valid else "FAIL")
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
