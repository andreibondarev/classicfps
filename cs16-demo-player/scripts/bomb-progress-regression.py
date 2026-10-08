#!/usr/bin/env python3
"""Verify plant/defuse progress HUD behavior against a real bundled demo."""

from __future__ import annotations

from pathlib import Path
import subprocess
import time

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT / "demos" / "pro-2004-m19-vs-virtuspro-de_aztec.dem"
PORT = 5231


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
            page = browser.new_page(viewport={"width": 1440, "height": 900})
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
                  const panel = document.getElementById('hud-action-progress');
                  const label = document.getElementById('hud-action-label');
                  const percent = document.getElementById('hud-action-percent');

                  const probe = (eventType, secondsBefore, expectedLabel) => {
                    const events = p.timeline.events.filter(event =>
                      event.event_type === eventType && event.time > secondsBefore);
                    for (const event of events) {
                      for (const name of p.timeline.slot_names) {
                        p.setFollowTarget(null);
                        p.seekToTime(event.time - secondsBefore);
                        p.setFollowTarget(name);
                        p.seekToTime(event.time - secondsBefore + 0.01);
                        if (!panel.classList.contains('hidden')
                            && label.textContent === expectedLabel) {
                          return {
                            eventTime: event.time,
                            player: name,
                            label: label.textContent,
                            percent: percent.textContent,
                            value: Number(panel.getAttribute('aria-valuenow')),
                          };
                        }
                      }
                    }
                    return null;
                  };

                  return {
                    plant: probe('BombPlanted', 1.5, 'PLANTING C4'),
                    defuse: probe('BombDefused', 2.5, 'DEFUSING BOMB'),
                    defuseEvents: p.timeline.events.filter(event =>
                      event.event_type === 'BombDefused').length,
                    c4Samples: [...p.timeline.objKinds].filter(kind => kind === 4).length,
                  };
                }"""
            )
            browser.close()
    finally:
        server.terminate()
        server.wait(timeout=10)

    plant = result["plant"]
    defuse = result["defuse"]
    print(f"Plant: {plant}")
    print(f"Defuse: {defuse}")
    print(f"Defuse events: {result['defuseEvents']}; C4 samples: {result['c4Samples']}")
    valid = (
        plant is not None
        and plant["label"] == "PLANTING C4"
        and 35 <= plant["value"] <= 65
        and defuse is not None
        and defuse["label"] == "DEFUSING BOMB"
        and 70 <= defuse["value"] <= 80
    )
    print("Bomb progress regression:", "PASS" if valid else "FAIL")
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
