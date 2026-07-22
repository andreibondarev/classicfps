#!/usr/bin/env python3
"""Verify exact POV and reconstructed HLTV weapon inventory HUD behavior."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import time

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]
POV_DEMO = ROOT / "demos" / "col-3d-inf-finals-ct.dem"
HLTV_DEMO = ROOT / "demos" / "pro-2004-m19-vs-virtuspro-de_aztec.dem"
PORT = 5237


def load_demo(page, path: Path) -> None:
    page.goto(f"http://127.0.0.1:{PORT}", wait_until="networkidle")
    with page.expect_file_chooser() as chooser:
        page.locator(".drop-zone").click()
    chooser.value.set_files(str(path))
    page.wait_for_function(
        "() => window.demoPlayer?.verificationReport?.status",
        timeout=120_000,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--screenshot", type=Path)
    args = parser.parse_args()
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

            load_demo(page, POV_DEMO)
            exact = page.evaluate(
                """() => {
                  const p = window.demoPlayer;
                  let best = null;
                  for (let i = 0; i < p.timeline.povTimes.length; i++) {
                    const bits = p.timeline.povWeaponBits[i] | 0;
                    const ids = [];
                    for (let id = 1; id <= 30; id++) {
                      if ((bits & (1 << id)) !== 0) ids.push(id);
                    }
                    const active = p.hudTrackAt(4, p.timeline.povTimes[i]);
                    if (active && ids.includes(active.a)
                        && (!best || ids.length > best.ids.length)) {
                      best = { time: p.timeline.povTimes[i], ids, active: active.a };
                    }
                  }
                  if (!best) return null;
                  p.setFollowTarget('Spectator Camera');
                  p.seekToTime(best.time + 0.001);
                  const items = [...document.querySelectorAll('#hud-inventory .hud-inventory-item')];
                  const activeItems = items.filter(item => item.classList.contains('active'));
                  return {
                    ...best,
                    labels: items.map(item => item.querySelector('.inventory-name')?.textContent),
                    slots: items.map(item => Number(item.querySelector('.inventory-slot')?.textContent)),
                    activeCount: activeItems.length,
                    activeTitle: activeItems[0]?.getAttribute('title') ?? '',
                    source: document.getElementById('hud-source')?.textContent ?? '',
                  };
                }"""
            )
            if args.screenshot:
                page.locator(".hud-weapon").screenshot(path=str(args.screenshot))

            load_demo(page, HLTV_DEMO)
            reconstructed = page.evaluate(
                """() => {
                  const p = window.demoPlayer;
                  let best = null;
                  const cells = p.timeline.slot_names.length;
                  for (let sample = 0; sample < p.timeline.times.length; sample += 20) {
                    const time = p.timeline.times[sample];
                    for (let slot = 0; slot < cells; slot++) {
                      const cell = sample * cells + slot;
                      if (!p.timeline.presence[cell]) continue;
                      const name = p.timeline.slot_names[slot];
                      if (p.computeDeaths(time).has(name)) continue;
                      const active = p.weaponIdForModel(
                        p.weaponModelName(p.timeline.weapons[cell] ?? 0));
                      if (!active) continue;
                      const ids = p.reconstructedInventoryAt(name, time, active);
                      if (!best || ids.length > best.ids.length) {
                        best = { time, name, ids, active };
                      }
                    }
                  }
                  if (!best) return null;
                  p.seekToTime(best.time);
                  p.setFollowTarget(best.name);
                  p.seekToTime(best.time + 0.001);
                  const items = [...document.querySelectorAll('#hud-inventory .hud-inventory-item')];
                  const activeItems = items.filter(item => item.classList.contains('active'));
                  return {
                    ...best,
                    labels: items.map(item => item.querySelector('.inventory-name')?.textContent),
                    slots: items.map(item => Number(item.querySelector('.inventory-slot')?.textContent)),
                    activeCount: activeItems.length,
                    activeTitle: activeItems[0]?.getAttribute('title') ?? '',
                    source: document.getElementById('hud-source')?.textContent ?? '',
                  };
                }"""
            )
            browser.close()
    finally:
        server.terminate()
        server.wait(timeout=10)

    print(f"Exact POV inventory: {exact}")
    print(f"Reconstructed inventory: {reconstructed}")
    exact_valid = (
        exact is not None
        and len(exact["labels"]) >= 3
        and exact["activeCount"] == 1
        and exact["activeTitle"].endswith("(active)")
        and exact["slots"] == sorted(exact["slots"])
        and exact["source"].startswith("RECORDED POV")
    )
    reconstructed_valid = (
        reconstructed is not None
        and len(reconstructed["labels"]) >= 2
        and "KNIFE" in reconstructed["labels"]
        and "C4" in reconstructed["labels"]
        and reconstructed["slots"][-1] == 5
        and reconstructed["activeCount"] == 1
        and reconstructed["activeTitle"].endswith("(active)")
        and reconstructed["slots"] == sorted(reconstructed["slots"])
        and reconstructed["source"] == "RECONSTRUCTED POV"
    )
    valid = exact_valid and reconstructed_valid
    print("Inventory HUD regression:", "PASS" if valid else "FAIL")
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
