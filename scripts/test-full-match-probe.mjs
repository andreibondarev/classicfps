import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { performanceArgs, FULL_MATCH_TICK_LIMIT } from "./run-game-perf.mjs";
import { runCheckedCommand } from "./run-game-tests.mjs";

// An intentionally incomplete native run must fail for the expected reasons,
// while still proving that full-match mode preserves the starting rules.
const directory = mkdtempSync(join(tmpdir(), "protocol47-full-match-negative-"));
const reportPath = join(directory, "report.json");
const args = performanceArgs(["--cpu-only", "--live-match", "--full-match",
  "--ticks=300", "--map=cs_assault", "--team=CT", `--report=${reportPath}`]);
args[args.indexOf("--log-file") + 1] = join(directory, "godot.log");
let output = "";
try {
  const result = await runCheckedCommand("godot", args, {
    timeoutMs: 30_000, onOutput: (_stream, chunk) => { output += chunk; },
  });
  assert.equal(result.code, 1);
  assert.equal(result.timedOut, false);
  assert.equal(result.signal, null);
  assert.ok(result.errors.some(error => error.includes("Required full MR15 match did not finish")));
  assert.ok(result.errors.some(error => error.includes("Required local combat was not covered")));
  assert.ok(result.errors.every(error => error.includes("Required full MR15 match did not finish")
    || error.includes("Required local combat was not covered") || error === "GAME_LIVE_MATCH_PERFORMANCE_FAIL"));
  const report = JSON.parse(readFileSync(reportPath, "utf8"));
  assert.equal(report.full_match_required, true);
  assert.equal(report.full_match_tick_limit, FULL_MATCH_TICK_LIMIT);
  assert.equal(report.round_rules.max_rounds, 30);
  assert.equal(report.round_rules.win_limit, 16);
  assert.equal(report.round_rules.halftime, true);
  assert.equal(report.full_match_tick_limit, report.round_rules.max_rounds * (
    report.round_rules.freeze_ticks + report.round_rules.round_ticks
    + report.round_rules.c4_ticks + report.round_rules.restart_ticks + 1));
  assert.equal(report.mr15_completion_verified, false);
  assert.equal(report.match_completed, false);
  assert.deepEqual(report.match_end_events, []);
  assert.equal(report.initial_local_weapon, "usp");
  assert.equal(report.initial_local_inventory.usp, true);
  assert.ok(!report.initial_local_inventory.ak47);
  assert.equal(report.initial_phase, "freeze");
  assert.equal(report.initial_freeze_skipped, false);
  assert.equal(report.physics_ticks, 300);
  assert.equal(report.local_combat_required, true);
  assert.deepEqual(report.local_shot_events, []);
  assert.equal(report.audio_muted, true);
  assert.equal(report.gpu_measured, false);
  assert.equal(report.diagnostic_render_exclusions, "");
  assert.ok(report.freeze_observations > 0);
  assert.equal(report.freeze_control_violations, 0);
  console.log(`GAME_FULL_MATCH_NEGATIVE_CONTROL_PASS artifacts=${directory}`);
} catch (error) {
  process.stderr.write(output);
  console.error(error);
  process.exitCode = 1;
}
