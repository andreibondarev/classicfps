#!/usr/bin/env python3
"""Verify a newly supported stock dropped weapon renders in a real demo."""

from __future__ import annotations

from pathlib import Path
import subprocess
import time

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT / "demos" / "R1_TNTvsEMV.NX-0709081213-de_dust2.dem"
PORT = 5234


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
            target = page.evaluate(
                """() => {
                  const p = window.demoPlayer;
                  const index = p.timeline.objKinds.findIndex(kind => kind > 21);
                  if (index < 0) return null;
                  const target = {
                    kind: p.timeline.objKinds[index],
                    time: p.timeline.objTimes[index],
                  };
                  p.seekToTime(target.time);
                  return target;
                }"""
            )
            if target:
                page.wait_for_function(
                    """kind => [...window.demoPlayer.objectMeshes.values()].some(object =>
                      object.kind === kind && object.group.visible && object.group.children.length > 0)
                    """,
                    arg=target["kind"],
                    timeout=30_000,
                )
            state = page.evaluate(
                """target => {
                  const p = window.demoPlayer;
                  const object = target
                    ? [...p.objectMeshes.values()].find(candidate => candidate.kind === target.kind)
                    : null;
                  return {
                    target,
                    visible: !!object?.group.visible,
                    children: object?.group.children.length ?? 0,
                    missingAssets: [...p.missingAssets],
                  };
                }""",
                target,
            )
            browser.close()
    finally:
        server.terminate()
        server.wait(timeout=10)

    print(f"Dropped model: {state}")
    valid = (
        state["target"] is not None
        and state["target"]["kind"] > 21
        and state["visible"]
        and state["children"] > 0
        and not state["missingAssets"]
    )
    print("Dropped model regression:", "PASS" if valid else "FAIL")
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
