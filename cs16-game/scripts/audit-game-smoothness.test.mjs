import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync, utimesSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { auditGameSmoothness, SMOOTHNESS_LIMITS } from "./audit-game-smoothness.mjs";
import { auditPerformanceRun } from "./run-game-perf.mjs";

// Synthetic metadata only tests the auditor, never game performance itself.
function fixture() {
  const metrics = { frames: 100, median_ms: 5, p95_ms: 10, p99_ms: 15, max_ms: 20, frames_over_33ms: 0 };
  return {
    ...metrics, frames: 200, rendered_frames: 199, physics_ticks: 199,
    gpu_measured: true, audio_muted: true, full_match_required: true, match_completed: true,
    mr15_completion_verified: true, local_combat_covered: true, local_combat_required: true,
    instrumented: false, diagnostic_render_exclusions: "", viewport: "(1280, 720)",
    renderer: "gl_compatibility", map: "cs_assault", local_team_start: "CT",
    initial_freeze_skipped: false, initial_phase: "freeze", starting_equipment: "normal_team_pistol",
    freeze_control_violations: 0, sample_mode: "physics_ticks", local_shot_events: [{}],
    desktop_input_isolated: true, pause_observations: 0, maximum_clock_gap: 0, kernel_ticks: 199,
    effect_events: 20, actors_final: Array.from({ length: 10 }, () => ({})),
    round_end_events: Array.from({ length: 16 }, () => ({})), halftime_events: [{}], match_end_events: [{}],
    loading_ms: 6000, frame_window_ticks: 100, frame_window_assignment: "frame_end_tick",
    frame_windows: [0, 100].map(start => ({ ...metrics, start_tick: start, end_tick_exclusive: start + 100,
      first_sample_tick: start, last_sample_tick: start + 99 })),
  };
}

test("clean recorded timing passes only its explicitly limited scope", () => {
  const result = auditGameSmoothness(fixture());
  assert.equal(result.ok, true, result.failures.join("\n"));
  assert.match(result.scope, /not release readiness or process-exit verification/);
  assert.deepEqual(result.limits, { p95_ms: 16.7, p99_ms: 25, max_ms: 50 });
  assert.ok(Object.isFrozen(SMOOTHNESS_LIMITS));
});

test("a passing overall percentile cannot hide one slow active window", () => {
  const report = fixture();
  Object.assign(report.frame_windows[0], { p95_ms: 18, p99_ms: 19 });
  const result = auditGameSmoothness(report);
  assert.equal(result.ok, false);
  assert.ok(result.failures.some(message => /Window 0.*p95_ms 18 exceeds 16.7/.test(message)));
  assert.ok(!result.failures.some(message => message.startsWith("Overall:")));
});

test("desktop interruption or lost authoritative ticks invalidate otherwise smooth timing", () => {
  for (const [key, value] of [["desktop_input_isolated", false], ["pause_observations", 1],
    ["pause_observations", false], ["maximum_clock_gap", 1], ["maximum_clock_gap", false],
    ["kernel_ticks", 0], ["kernel_ticks", "199"]]) {
    const report = { ...fixture(), [key]: value };
    assert.equal(auditGameSmoothness(report).ok, false, key);
  }
});

test("an isolated hitch fails even if the slow-frame detail list omitted it", () => {
  const report = fixture();
  Object.assign(report, { max_ms: 225.333, frames_over_33ms: 1, slow_frames: [] });
  Object.assign(report.frame_windows[1], { max_ms: 225.333, frames_over_33ms: 1 });
  const result = auditGameSmoothness(report);
  assert.equal(result.ok, false);
  assert.ok(result.failures.some(message => /Overall: max_ms 225.333 exceeds 50/.test(message)));
});

test("limits are inclusive, with no rounded-down near misses", () => {
  const report = fixture();
  for (const row of [report, ...report.frame_windows]) Object.assign(row, SMOOTHNESS_LIMITS, { frames_over_33ms: 1 });
  report.frames_over_33ms = 2;
  assert.equal(auditGameSmoothness(report).ok, true);
  for (const key of Object.keys(SMOOTHNESS_LIMITS)) {
    const changed = structuredClone(report);
    changed.frame_windows[0][key] += 0.001;
    assert.equal(auditGameSmoothness(changed).ok, false, key);
  }
});

test("all required full-match/render metadata is fail-closed", () => {
  for (const key of Object.keys(fixture())) {
    const report = fixture();
    delete report[key];
    assert.equal(auditGameSmoothness(report).ok, false, `missing ${key}`);
  }
  for (const [key, value] of Object.entries({ gpu_measured: false, audio_muted: false, full_match_required: false,
    instrumented: true, diagnostic_render_exclusions: "effect_lights", viewport: "(64, 64)",
    rendered_frames: 120, initial_freeze_skipped: true, local_shot_events: [], actors_final: [],
    round_end_events: [], halftime_events: [], match_end_events: [], sample_mode: "render_frames",
    local_team_start: "observer", freeze_control_violations: 1 })) {
    assert.equal(auditGameSmoothness({ ...fixture(), [key]: value }).ok, false, key);
  }
});

test("malformed metrics cannot coerce their way through a threshold", () => {
  for (const value of [null, [], "", 3]) assert.equal(auditGameSmoothness(value).ok, false);
  for (const value of [null, "1", NaN, Infinity, -1]) for (const key of ["median_ms", "p95_ms", "p99_ms", "max_ms"]) {
    const report = fixture();
    report[key] = value;
    assert.equal(auditGameSmoothness(report).ok, false, `${key}=${value}`);
    const windowReport = fixture();
    windowReport.frame_windows[0][key] = value;
    assert.equal(auditGameSmoothness(windowReport).ok, false, `window ${key}=${value}`);
  }
});

test("window coverage, totals, ordering and intact maxima are required", () => {
  const changes = [
    report => { report.frame_windows = []; },
    report => { report.frame_windows = [null]; },
    report => { report.frame_windows.pop(); },
    report => { report.frame_windows.reverse(); },
    report => { report.frame_windows[1].start_tick = 0; },
    report => { report.frame_windows[0].last_sample_tick = 100; },
    report => { report.frame_windows.shift(); report.frames = 100; report.rendered_frames = 99; },
    report => { report.frame_windows[1].last_sample_tick = 198; },
    report => { report.frame_windows[0].frames = 0; },
    report => { report.frame_windows[0].frames = 99.5; },
    report => { report.frame_windows[0].p95_ms = 2; },
    report => { report.max_ms = 21; },
    report => { report.frames_over_33ms = 1; },
    report => { report.frame_windows[0].frames_over_33ms = 101; },
  ];
  for (const change of changes) {
    const report = fixture();
    change(report);
    assert.equal(auditGameSmoothness(report).ok, false, String(change));
  }
});

test("a first render boundary after tick zero is a valid intact interval", () => {
  const report = fixture();
  report.frame_windows[0].first_sample_tick = 1;
  assert.equal(auditGameSmoothness(report).ok, true);
});

test("artifact CLI uses nonzero exit for failed, missing or invalid evidence", () => {
  const directory = mkdtempSync(join(tmpdir(), "protocol47-smoothness-audit-"));
  const path = join(directory, "report.json");
  const script = new URL("./audit-game-smoothness.mjs", import.meta.url);
  const run = (...args) => spawnSync(process.execPath, [fileURLToPath(script), ...args], { encoding: "utf8", timeout: 5000 });
  writeFileSync(path, JSON.stringify(fixture()));
  let result = run(path);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /GAME_RECORDED_SMOOTHNESS_PASS/);
  const report = fixture();
  report.instrumented = true;
  writeFileSync(path, JSON.stringify(report));
  result = run(path);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /GAME_RECORDED_SMOOTHNESS_FAIL/);
  writeFileSync(path, "{");
  assert.equal(run(path).status, 1);
  assert.equal(run(join(directory, "missing.json")).status, 1);
  assert.equal(run().status, 1);
  assert.equal(run(path, path).status, 1);
});

test("the release command enables clean full-match timing and the regular gate tests the auditor", () => {
  const { scripts } = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.equal(scripts["game:perf:full-match"], "node scripts/run-game-perf.mjs --live-match --full-match --require-smoothness");
  assert.equal(scripts["game:perf:audit"], "node scripts/audit-game-smoothness.mjs");
  assert.ok(scripts["game:test"].includes("scripts/audit-game-smoothness.test.mjs"));
});

test("the integrated gate requires clean process completion and a report from this run", () => {
  const directory = mkdtempSync(join(tmpdir(), "protocol47-smoothness-freshness-"));
  const path = join(directory, "report.json");
  const startedAt = Date.now() - 1000;
  writeFileSync(path, JSON.stringify(fixture()));
  assert.equal(auditPerformanceRun({ ok: true }, path, startedAt).ok, true);
  for (const result of [null, {}, { ok: false }]) {
    assert.throws(() => auditPerformanceRun(result, path, startedAt), /unsuccessful checked process/);
  }
  assert.throws(() => auditPerformanceRun({ ok: true }, path, NaN), /run start time/);
  utimesSync(path, new Date(0), new Date(0));
  assert.throws(() => auditPerformanceRun({ ok: true }, path, startedAt), /predates this run/);
  assert.throws(() => auditPerformanceRun({ ok: true }, join(directory, "missing.json"), startedAt), /ENOENT/);
});
