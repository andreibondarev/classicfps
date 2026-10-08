#!/usr/bin/env python3
"""Measure rendered EXE HLTV playback cadence and per-frame replay work."""

from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import subprocess
import time

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]
PORT = 5247
DEMO = ROOT / "demos" / "exe_vs_mc-1.dem"


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0
    return ordered[min(len(ordered) - 1, round((len(ordered) - 1) * fraction))]


def main() -> int:
    server = subprocess.Popen(
        ["npm", "run", "dev", "--", "--host", "127.0.0.1", "--port", str(PORT)],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
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
                """() => {
                  const p = window.demoPlayer;
                  return p?.verificationReport?.status && p?.mapMesh && p?.assetPreflight;
                }""",
                timeout=120_000,
            )
            page.evaluate(
                """() => {
                  const p = window.demoPlayer;
                  p.setRenderQuality('performance', false);
                  p.setPlaybackMode('cinematic', false);
                  p.seekToTime(p.duration * .45);
                  const living = p.livingFollowTargets();
                  p.setFollowTarget(living[0] ?? null, false);
                  p.seekToTime(p.currentTime + .05);
                }"""
            )
            page.wait_for_timeout(1_500)
            result = page.evaluate(
                """async () => {
                  const p = window.demoPlayer;
                  const updateDurations = [];
                  const renderDurations = [];
                  const longTasks = [];
                  const originalUpdate = p.updatePlayback.bind(p);
                  const originalRender = p.renderer.render.bind(p.renderer);
                  p.updatePlayback = () => {
                    const started = performance.now();
                    try { return originalUpdate(); }
                    finally { updateDurations.push(performance.now() - started); }
                  };
                  p.renderer.render = (...args) => {
                    const started = performance.now();
                    try { return originalRender(...args); }
                    finally { renderDurations.push(performance.now() - started); }
                  };

                  if (!p.isPlaying) p.togglePlayback();
                  await new Promise(resolve => setTimeout(resolve, 750));
                  updateDurations.length = 0;
                  renderDurations.length = 0;
                  const longTaskObserver = new PerformanceObserver(list => {
                    for (const entry of list.getEntries()) longTasks.push(entry.duration);
                  });
                  longTaskObserver.observe({type: 'longtask'});
                  const frameIntervals = [];
                  const startedAt = performance.now();
                  const demoStartedAt = p.currentTime;
                  let previous = startedAt;
                  await new Promise(resolve => {
                    const sample = now => {
                      frameIntervals.push(now - previous);
                      previous = now;
                      if (now - startedAt >= 4_000) resolve();
                      else requestAnimationFrame(sample);
                    };
                    requestAnimationFrame(sample);
                  });
                  const elapsed = performance.now() - startedAt;
                  const demoElapsed = p.currentTime - demoStartedAt;
                  if (p.isPlaying) p.togglePlayback();
                  longTaskObserver.disconnect();
                  return {
                    elapsed,
                    demoElapsed,
                    frameIntervals,
                    updateDurations,
                    renderDurations,
                    longTasks,
                    renderScale: p.renderScale,
                    target: p.followTarget,
                    drawCalls: p.renderer.info.render.calls,
                    triangles: p.renderer.info.render.triangles,
                    worldGroups: p.mapMesh?.getObjectByName('worldspawn')?.geometry?.groups?.length ?? 0,
                  };
                }"""
            )
            browser.close()
    finally:
        try:
            os.killpg(server.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(server.pid, signal.SIGKILL)
            server.wait(timeout=10)

    frames = result.pop("frameIntervals")
    updates = result.pop("updateDurations")
    renders = result.pop("renderDurations")
    long_tasks = result.pop("longTasks")
    report = {
        **result,
        "frames": len(frames),
        "frameAverageMs": sum(frames) / len(frames),
        "frameP95Ms": percentile(frames, .95),
        "frameP99Ms": percentile(frames, .99),
        "framesOver25Ms": sum(value > 25 for value in frames),
        "framesOver50Ms": sum(value > 50 for value in frames),
        "updates": len(updates),
        "updateAverageMs": sum(updates) / len(updates),
        "updateP95Ms": percentile(updates, .95),
        "updateMaxMs": max(updates),
        "renderAverageMs": sum(renders) / len(renders),
        "renderP95Ms": percentile(renders, .95),
        "renderMaxMs": max(renders),
        "longTasks": len(long_tasks),
        "longTaskMaxMs": max(long_tasks, default=0),
    }
    print(json.dumps(report, indent=2))

    # Headless WebGL cadence varies substantially by host. Keep hard limits on
    # main-thread replay/render submission, demo-clock drift, and the share of
    # genuinely long frames instead of pretending CI provides desktop vsync.
    ok = (
        report["frames"] >= 45
        and report["frameP95Ms"] < 150
        and report["framesOver50Ms"] <= max(10, report["frames"] * .4)
        and report["updateP95Ms"] < 8
        and report["renderP95Ms"] < 8
        and abs(report["demoElapsed"] - report["elapsed"] / 1000) < .2
    )
    print(f"\nPlayback smoothness regression: {'passed' if ok else 'failed'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
