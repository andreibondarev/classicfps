import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { statSync } from "node:fs";
import { runCheckedCommand } from "./run-game-tests.mjs";
import { auditGameSmoothnessFile } from "./audit-game-smoothness.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
// MR15's legal upper bound: freeze + full round + late C4 + post-round,
// with one transition-tick allowance per round. The native negative-control
// test checks this against the running game's configuration, not a test preset.
export const FULL_MATCH_TICK_LIMIT = 30 * ((6 + 300 + 45 + 5) * 100 + 1);

export function performanceArgs(options, projectRoot = root) {
  const cpuOnly = options.includes("--cpu-only");
  const liveMatch = options.includes("--live-match");
  const fullMatch = options.includes("--full-match");
  const smoothness = options.includes("--require-smoothness");
  if (options.some(value => value.startsWith("--require-smoothness="))) throw new Error("Use --require-smoothness without a value");
  if (smoothness && (!fullMatch || !liveMatch || cpuOnly)) throw new Error("--require-smoothness requires a rendered --live-match --full-match");
  if (smoothness && options.some(value => value === "--instrumented" || value === "--profile-phases" || value.startsWith("--diagnostic-hide"))) {
    throw new Error("--require-smoothness cannot use instrumentation or render exclusions");
  }
  if (smoothness && options.some(value => !["--live-match", "--full-match", "--require-smoothness"].includes(value)
    && !/^--(map|team|ticks|report|capture|renderer|driver)=/.test(value))) {
    throw new Error("--require-smoothness accepts only map/team/ticks/report/capture/renderer/driver options");
  }
  const reports = options.filter(value => value.startsWith("--report="));
  if (options.includes("--report") || reports.length > 1 || reports.some(value => value.length === 9)) {
    throw new Error("Use one nonempty --report=path");
  }
  if (options.some(value => value.startsWith("--full-match="))) throw new Error("Use --full-match without a value");
  if (fullMatch && !liveMatch) throw new Error("--full-match requires --live-match");
  if (fullMatch && options.some(value => value.startsWith("--frames="))) throw new Error("--full-match uses a physics-tick limit, not --frames");
  if (fullMatch && options.some(value => value.startsWith("--diagnostic-hide"))) throw new Error("--full-match cannot exclude rendered effects");
  if (options.includes("--require-local-combat") && !liveMatch) throw new Error("--require-local-combat requires --live-match");
  if (options.includes("--profile-phases") && !liveMatch) throw new Error("--profile-phases requires --live-match");
  const ticks = options.filter((value) => value.startsWith("--ticks="));
  if (ticks.length) {
    if (!liveMatch) throw new Error("--ticks requires --live-match");
    const count = Number(ticks[0].slice(8));
    const maximum = fullMatch ? FULL_MATCH_TICK_LIMIT : 12000;
    if (ticks.length !== 1 || !/^--ticks=[0-9]+$/.test(ticks[0]) || !Number.isInteger(count) || count < 300 || count > maximum) {
      throw new Error(`--ticks must be an integer from 300 to ${maximum}`);
    }
    if (options.some((value) => value.startsWith("--frames="))) {
      throw new Error("Choose --ticks or --frames, not both");
    }
  }
  if (options.includes("--ticks")) throw new Error("Use --ticks=value");
  if (options.includes("--renderer") || options.includes("--driver")) {
    throw new Error("Use --renderer=value and --driver=value for renderer overrides");
  }
  function choice(name, allowed) {
    const values = options.filter((value) => value.startsWith(`--${name}=`));
    if (!values.length) return null;
    const value = values[0].slice(name.length + 3);
    if (values.length !== 1 || !allowed.includes(value)) {
      throw new Error(`--${name} must be one of: ${allowed.join(", ")}`);
    }
    return value;
  }
  const renderer = choice("renderer", ["gl_compatibility", "mobile", "forward_plus"]);
  const driver = choice("driver", ["metal", "vulkan", "opengl3", "opengl3_angle"]);
  if (options.includes("--map") || options.includes("--team")) throw new Error("Use --map=value and --team=value");
  choice("map", ["de_dust2", "cs_assault", "de_inferno"]);
  const team = choice("team", ["T", "CT"]);
  if (team && !liveMatch) throw new Error("--team requires --live-match");
  if (options.includes("--diagnostic-hide")) throw new Error("Use --diagnostic-hide=value");
  const diagnosticHide = choice("diagnostic-hide", ["world_drops", "corpse_models", "viewmodel", "effect_lights", "muzzle_smoke", "map"]);
  if (diagnosticHide && !liveMatch && diagnosticHide !== "effect_lights") {
    throw new Error("This --diagnostic-hide category requires --live-match; stationary diagnostics support effect_lights only");
  }
  if (cpuOnly && (renderer || driver)) throw new Error("GPU renderer options cannot be used with --cpu-only");
  if (driver && !renderer) throw new Error("--driver requires an explicit --renderer");
  const fixtureOptions = options.filter((value) => !value.startsWith("--renderer=") && !value.startsWith("--driver=") && value !== "--require-smoothness")
    // Godot's project path must not make the writer and auditor resolve a
    // relative report differently. Both use the wrapper's project root.
    .map(value => value.startsWith("--report=") ? `--report=${resolve(projectRoot, value.slice(9))}` : value);
  return [
    // macOS stops rendering fully occluded windows while simulation continues.
    // Keep only the benchmark window on top; the fixture also checks draw counts.
    ...(cpuOnly ? ["--headless", "--fixed-fps", "60"] : ["--always-on-top"]),
    "--audio-driver", "Dummy", "--log-file",
    `/tmp/protocol47-firefight-${cpuOnly ? "cpu" : "rendered"}.log`,
    ...(renderer ? ["--rendering-method", renderer] : []),
    ...(driver ? ["--rendering-driver", driver] : []),
    "--path", resolve(projectRoot, "game"),
    "--script", `res://tests/${liveMatch ? "live_match" : "firefight"}_performance_test.gd`, "--", ...fixtureOptions,
  ];
}

export function performanceTimeoutMs(options) {
  performanceArgs(options); // Apply the same validation before deriving a deadline.
  if (!options.includes("--full-match")) return 180_000;
  const ticks = options.find(value => value.startsWith("--ticks="));
  return Math.max(180_000, Number(ticks?.slice(8) ?? FULL_MATCH_TICK_LIMIT) * 10 + 90_000);
}

export function auditPerformanceRun(result, reportPath, startedAt) {
  if (result?.ok !== true) throw new Error("Cannot accept timing from an unsuccessful checked process");
  if (!Number.isFinite(startedAt) || startedAt <= 0) throw new Error("Missing run start time");
  if (statSync(reportPath).mtimeMs < startedAt - 1) throw new Error("Full-match report predates this run");
  return auditGameSmoothnessFile(reportPath);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const options = process.argv.slice(2);
  const args = performanceArgs(options);
  const metrics = await runCheckedCommand("godot", [
    "--headless", "--audio-driver", "Dummy", "--log-file", "/tmp/protocol47-frame-window-metrics.log",
    "--path", resolve(root, "game"), "--script", "res://tests/frame_window_metrics_test.gd",
  ], { cwd: root, timeoutMs: 30_000 });
  const startedAt = Date.now();
  const result = metrics.ok
    ? await runCheckedCommand("godot", args, { cwd: root, timeoutMs: performanceTimeoutMs(options) })
    : metrics;
  if (!result.ok) {
    console.error(`GAME_PERFORMANCE_GATE_FAIL ${JSON.stringify(result)}`);
    process.exitCode = 1;
  } else if (options.includes("--require-smoothness")) {
    try {
      const reportPath = resolve(root, options.find(value => value.startsWith("--report="))?.slice(9)
        ?? "/tmp/protocol47-live-match-performance.json");
      const audit = auditPerformanceRun(result, reportPath, startedAt);
      console.log(`GAME_FULL_MATCH_SMOOTHNESS_${audit.ok ? "PASS" : "FAIL"} ${JSON.stringify(audit)}`);
      if (!audit.ok) process.exitCode = 1;
    } catch (error) {
      console.error(`GAME_FULL_MATCH_SMOOTHNESS_FAIL ${error.message}`);
      process.exitCode = 1;
    }
  }
}
