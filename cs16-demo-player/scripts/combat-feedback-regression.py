#!/usr/bin/env python3
"""Verify first-person shot feedback and headshot kill-feed treatment."""

from __future__ import annotations

from pathlib import Path
import subprocess
import time

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT / "demos" / "pro-2004-m19-vs-virtuspro-de_aztec.dem"
PORT = 5233


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
            page.wait_for_function("() => !!window.demoPlayer?.mapMesh", timeout=30_000)

            setup = page.evaluate(
                """() => {
                  const p = window.demoPlayer;
                  const headshot = p.timeline.events.find(event =>
                    event.event_type === 'Kill' && event.data.headshot);
                  p.seekToTime(headshot.time);
                  const marker = document.querySelector('.kill-entry .hs');

                  let shot = null;
                  for (let index = 0; index < p.timeline.shotTimes.length; index++) {
                    const time = p.timeline.shotTimes[index];
                    const slot = p.timeline.shotSlots[index];
                    const player = p.players.find(candidate => candidate.index === slot);
                    if (!player || time < 20 || p.computeDeaths(time).has(player.name)) continue;
                    if (!p.hasUsableNetworkGunshotAt(time, slot)) {
                      shot = { time, slot, player: player.name };
                      break;
                    }
                  }
                  if (shot) {
                    p.seekToTime(shot.time - 0.03);
                    p.setFollowTarget(shot.player);
                  }
                  return {
                    headshot: {
                      present: !!marker,
                      label: marker?.getAttribute('aria-label') ?? '',
                      text: marker?.textContent ?? '',
                    },
                    shot,
                  };
                }"""
            )
            page.wait_for_timeout(500)
            playback = page.evaluate(
                """({shot}) => {
                  if (!shot) return { fallbackCalls: -1, followedMeshHidden: false };
                  const p = window.demoPlayer;
                  let fallbackCalls = 0;
                  p.playShotSound = () => { fallbackCalls++; };
                  const mesh = p.playerMeshes.get(shot.player);
                  const followedMeshHidden = !!mesh && !mesh.visible;
                  p.lastShotT = shot.time - 0.01;
                  p.currentTime = shot.time + 0.01;
                  p.updatePlayback();
                  return { fallbackCalls, followedMeshHidden };
                }""",
                {"shot": setup["shot"]},
            )
            browser.close()
    finally:
        server.terminate()
        server.wait(timeout=10)

    print(f"Headshot marker: {setup['headshot']}")
    print(f"First-person shot: {setup['shot']}; playback: {playback}")
    valid = (
        setup["headshot"]["present"]
        and setup["headshot"]["label"] == "Headshot"
        and "HS" in setup["headshot"]["text"]
        and setup["shot"] is not None
        and playback["followedMeshHidden"]
        and playback["fallbackCalls"] == 1
    )
    print("Combat feedback regression:", "PASS" if valid else "FAIL")
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
