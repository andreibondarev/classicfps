#!/usr/bin/env python3
"""Verify TeamInfo wins over transient HLTV model/slot inference in the roster."""

from __future__ import annotations

from pathlib import Path
import subprocess
import time

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT / "demos" / "corpus" / "WBSF_DIVvsHYBRID-0709082135-de_train.dem"
PORT = 5232


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
            roster = page.evaluate(
                """() => {
                  const p = window.demoPlayer;
                  p.seekToTime(201);
                  p.renderPlayerList(p.computeDeaths(p.currentTime));
                  let team = '';
                  const result = {};
                  for (const element of document.getElementById('players').children) {
                    const heading = element.querySelector?.('.team-header');
                    if (heading) team = heading.textContent;
                    if (element.classList.contains('player-entry')) {
                      result[element.dataset.name] = team;
                    }
                  }
                  return result;
                }"""
            )
            browser.close()
    finally:
        server.terminate()
        server.wait(timeout=10)

    rico_name = next((name for name in roster if "ricozaitsev" in name.lower()), None)
    rico_team = roster.get(rico_name) if rico_name else None
    print(f"{rico_name or 'ricoZaitsev'}: {rico_team}")
    if not rico_name:
        print(f"Roster names: {', '.join(roster)}")
    valid = rico_team == "COUNTER-TERRORISTS"
    print("Team roster regression:", "PASS" if valid else "FAIL")
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
