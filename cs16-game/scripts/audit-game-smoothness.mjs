import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

// A timing pass applies to one recorded full match, not to the release matrix.
// Keep every live interval, including freeze, transitions and isolated hitches.
export const SMOOTHNESS_LIMITS = Object.freeze({ p95_ms: 16.7, p99_ms: 25, max_ms: 50 });

export function auditGameSmoothness(report) {
  const failures = [];
  const require = (condition, message) => { if (!condition) failures.push(message); };
  const object = value => value !== null && typeof value === "object" && !Array.isArray(value);
  const number = value => typeof value === "number" && Number.isFinite(value) && value >= 0;
  const integer = value => Number.isSafeInteger(value) && value >= 0;
  const result = () => ({
    ok: failures.length === 0,
    scope: "Recorded full-match timing only; not release readiness or process-exit verification",
    limits: SMOOTHNESS_LIMITS,
    failures,
  });
  if (!object(report)) {
    failures.push("Report must be an object");
    return result();
  }
  for (const key of ["gpu_measured", "audio_muted", "full_match_required", "match_completed",
    "mr15_completion_verified", "local_combat_covered", "local_combat_required"]) {
    require(report[key] === true, `${key} must be true`);
  }
  require(report.instrumented === false, "Instrumented measurements are not clean timing evidence");
  require(report.diagnostic_render_exclusions === "", "Rendered content must not be excluded");
  require(report.viewport === "(1280, 720)", "This timing target requires a 1280x720 viewport");
  require(["gl_compatibility", "mobile", "forward_plus"].includes(report.renderer), "Missing or unknown renderer");
  require(["de_dust2", "cs_assault", "de_inferno"].includes(report.map), "Missing or unknown map");
  require(["T", "CT"].includes(report.local_team_start), "Missing or unknown starting team");
  require(report.initial_freeze_skipped === false && report.initial_phase === "freeze"
    && report.starting_equipment === "normal_team_pistol", "Full matches must use normal starting rules/equipment");
  require(report.freeze_control_violations === 0, "Freeze-control violations or missing coverage");
  require(report.desktop_input_isolated === true && report.pause_observations === 0,
    "Benchmark desktop input must be isolated with no pause observations");
  require(report.maximum_clock_gap === 0 && integer(report.kernel_ticks) && report.kernel_ticks > 0,
    "Missing authoritative-clock coverage or lost simulation ticks");
  require(integer(report.frames) && report.frames > 0, "Frame count must be a positive integer");
  require(integer(report.rendered_frames) && report.rendered_frames >= report.frames - 2
    && report.rendered_frames <= report.frames + 2, "Missing or incomplete draw coverage");
  require(report.sample_mode === "physics_ticks" && integer(report.physics_ticks) && report.physics_ticks > 0,
    "Missing physics-tick sampling coverage");
  require(Array.isArray(report.local_shot_events) && report.local_shot_events.length > 0, "No recorded local shots");
  require(integer(report.effect_events) && report.effect_events > 0, "No recorded combat effects");
  require(Array.isArray(report.actors_final) && report.actors_final.length === 10, "Expected ten match actors");
  require(Array.isArray(report.round_end_events) && report.round_end_events.length >= 16
    && report.round_end_events.length <= 30, "Missing full-match round trace");
  require(Array.isArray(report.halftime_events) && report.halftime_events.length === 1, "Expected one halftime");
  require(Array.isArray(report.match_end_events) && report.match_end_events.length === 1, "Expected one match ending");
  require(number(report.loading_ms), "Loading time must be reported separately");
  require(report.frame_window_ticks === 100 && report.frame_window_assignment === "frame_end_tick",
    "Expected intact frame-end-tick windows of 100 physics ticks");

  function timing(row, label) {
    if (!object(row)) { failures.push(`${label}: malformed metrics`); return; }
    for (const key of ["median_ms", "p95_ms", "p99_ms", "max_ms"]) {
      require(number(row[key]), `${label}: ${key} must be a finite nonnegative number`);
    }
    require(row.median_ms <= row.p95_ms && row.p95_ms <= row.p99_ms && row.p99_ms <= row.max_ms,
      `${label}: inconsistent percentile ordering`);
    require(integer(row.frames_over_33ms) && row.frames_over_33ms <= row.frames,
      `${label}: invalid slow-frame count`);
    require((row.max_ms > 33.333) === (row.frames_over_33ms > 0), `${label}: maximum/slow-frame count disagree`);
    for (const [key, limit] of Object.entries(SMOOTHNESS_LIMITS)) {
      if (number(row[key]) && row[key] > limit) failures.push(`${label}: ${key} ${row[key]} exceeds ${limit}`);
    }
  }
  timing(report, "Overall");
  if (!Array.isArray(report.frame_windows) || report.frame_windows.length === 0) {
    failures.push("Missing per-window frame times; overall percentiles alone are insufficient");
    return result();
  }
  let frames = 0, slowFrames = 0, maximum = 0, previousEnd = -1;
  for (const [index, window] of report.frame_windows.entries()) {
    const label = `Window ${index} (tick ${window?.start_tick})`;
    timing(window, label);
    if (!object(window)) continue;
    require(integer(window.start_tick) && window.start_tick % 100 === 0
      && window.end_tick_exclusive === window.start_tick + 100 && window.start_tick >= previousEnd,
      `${label}: invalid or overlapping tick bounds`);
    require(integer(window.first_sample_tick) && integer(window.last_sample_tick)
      && window.first_sample_tick >= window.start_tick && window.first_sample_tick <= window.last_sample_tick
      && window.last_sample_tick < window.end_tick_exclusive && window.last_sample_tick <= report.physics_ticks,
      `${label}: invalid sample tick bounds`);
    require(integer(window.frames) && window.frames > 0, `${label}: empty or invalid frame count`);
    frames += window.frames;
    slowFrames += window.frames_over_33ms;
    maximum = Math.max(maximum, window.max_ms);
    previousEnd = window.end_tick_exclusive;
  }
  require(frames === report.frames, "Window frame totals do not cover all reported intervals");
  require(slowFrames === report.frames_over_33ms, "Window slow-frame totals do not match the full report");
  require(maximum === report.max_ms, "Window maximum does not match the full report");
  // The first render boundary can occur after tick zero. Requiring its end
  // tick to be zero would reject a legitimate interval that includes startup.
  require(report.frame_windows[0]?.start_tick === 0,
    "Frame windows must retain the initial measurement window");
  require(report.frame_windows.at(-1)?.last_sample_tick === report.physics_ticks,
    "Frame windows must reach the recorded end of measurement");
  return result();
}

export function auditGameSmoothnessFile(path) {
  return auditGameSmoothness(JSON.parse(readFileSync(path, "utf8")));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.length !== 3) throw new Error("Usage: node scripts/audit-game-smoothness.mjs <full-match-report.json>");
    const result = auditGameSmoothnessFile(process.argv[2]);
    console.log(`GAME_RECORDED_SMOOTHNESS_${result.ok ? "PASS" : "FAIL"} ${JSON.stringify(result)}`);
    process.exitCode = result.ok ? 0 : 1;
  } catch (error) {
    console.error(`GAME_RECORDED_SMOOTHNESS_FAIL ${error.message}`);
    process.exitCode = 1;
  }
}
