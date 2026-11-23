import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { performanceArgs, performanceTimeoutMs, FULL_MATCH_TICK_LIMIT } from "./run-game-perf.mjs";

test("smoothness acceptance requires a clean rendered full match and stays outside the fixture", () => {
  const base = ["--live-match", "--full-match", "--require-smoothness"];
  const args = performanceArgs(base);
  assert.ok(!args.includes("--require-smoothness"));
  assert.ok(args.includes("--full-match"));
  assert.equal(args[args.indexOf("--audio-driver") + 1], "Dummy");
  for (const options of [["--require-smoothness"], ["--live-match", "--require-smoothness"],
    [...base, "--cpu-only"], [...base, "--profile-phases"], [...base, "--instrumented"],
    [...base, "--diagnostic-hide=effect_lights"], [...base, "--require-smoothness=true"],
    [...base, "--procedural-test"], [...base, "--host"], [...base, "--join=127.0.0.1"]]) {
    assert.throws(() => performanceArgs(options), /smoothness/);
  }
});

test("the report path is unambiguous so the timing gate cannot read a different output", () => {
  for (const options of [["--report"], ["--report="], ["--report=a.json", "--report=b.json"]]) {
    assert.throws(() => performanceArgs(options), /one nonempty --report/);
  }
  assert.ok(performanceArgs(["--report=a.json"], "/example/project").includes("--report=/example/project/a.json"));
});

test("rendered benchmarks always mute audio and keep the drawing window visible", () => {
  const args = performanceArgs([]);
  assert.ok(args.includes("--always-on-top"));
  assert.equal(args[args.indexOf("--audio-driver") + 1], "Dummy");
  assert.ok(!args.includes("--rendering-method"));
});

test("live timing isolates desktop input and retains interruption and clock evidence", () => {
  const source = readFileSync(new URL("../game/tests/live_match_performance_test.gd", import.meta.url), "utf8");
  for (const expected of ["game.set_process_unhandled_input(false)", "game.player.set_process_input(false)",
    "game.spectator_camera.set_process_unhandled_input(false)", "root.gui_disable_input = true",
    "Input.mouse_mode = Input.MOUSE_MODE_VISIBLE", '"pause_observations": pause_observations',
    '"maximum_clock_gap": maximum_clock_gap', "pause_observations > 0 or maximum_clock_gap > 0"]) {
    assert.ok(source.includes(expected), expected);
  }
});

test("full-match probes explicitly opt into longer bounded runs and preserve effects", () => {
  assert.throws(() => performanceArgs(["--full-match"]), /requires --live-match/);
  assert.throws(() => performanceArgs(["--live-match", "--full-match=true"]), /without a value/);
  assert.throws(() => performanceArgs(["--live-match", "--full-match", "--frames=1800"]), /physics-tick limit/);
  assert.throws(() => performanceArgs(["--live-match", "--full-match", "--diagnostic-hide=map"]), /cannot exclude/);
  assert.equal(FULL_MATCH_TICK_LIMIT, 1068030);
  assert.throws(() => performanceArgs(["--live-match", "--full-match", "--ticks=1068031"]), /1068030/);
  assert.ok(performanceArgs(["--live-match", "--full-match", "--ticks=1068030"]).includes("--ticks=1068030"));
  const options = ["--live-match", "--full-match", "--ticks=120000"];
  assert.ok(performanceArgs(options).includes("--full-match"));
  assert.equal(performanceTimeoutMs(options), 1290000);
  assert.equal(performanceTimeoutMs(["--live-match", "--full-match"]), 10770300);
  assert.equal(performanceTimeoutMs(["--live-match", "--full-match", "--ticks=300"]), 180000);
  assert.equal(performanceTimeoutMs(["--live-match", "--ticks=12000"]), 180000);
});

test("CPU-only benchmarks cannot be mistaken for GPU probes", () => {
  const args = performanceArgs(["--cpu-only"]);
  assert.ok(args.includes("--headless"));
  assert.ok(!args.includes("--always-on-top"));
  assert.equal(args[args.indexOf("--audio-driver") + 1], "Dummy");
  assert.throws(() => performanceArgs(["--cpu-only", "--renderer=mobile"]), /GPU renderer/);
});

test("renderer probes pass engine options before the fixture argument separator", () => {
  const args = performanceArgs(["--live-match", "--renderer=mobile", "--driver=metal", "--report=/tmp/probe.json"]);
  const engine = args.slice(0, args.indexOf("--"));
  const fixture = args.slice(args.indexOf("--") + 1);
  assert.equal(engine[engine.indexOf("--rendering-method") + 1], "mobile");
  assert.equal(engine[engine.indexOf("--rendering-driver") + 1], "metal");
  assert.ok(engine.includes("res://tests/live_match_performance_test.gd"));
  assert.deepEqual(fixture, ["--live-match", "--report=/tmp/probe.json"]);
});

test("invalid or ambiguous renderer overrides fail rather than silently benchmark defaults", () => {
  assert.throws(() => performanceArgs(["--renderer", "mobile"]), /--renderer=value/);
  assert.throws(() => performanceArgs(["--renderer=moblie"]), /--renderer/);
  assert.throws(() => performanceArgs(["--renderer=mobile", "--renderer=forward_plus"]), /--renderer/);
  assert.throws(() => performanceArgs(["--driver=invalid"]), /--driver/);
  assert.throws(() => performanceArgs(["--driver=metal"]), /explicit --renderer/);
});

test("live comparisons can use matched simulation duration without overriding the renderer", () => {
  const args = performanceArgs(["--live-match", "--ticks=3000"]);
  assert.ok(args.includes("--ticks=3000"));
  assert.ok(!args.includes("--fixed-fps"));
  assert.throws(() => performanceArgs(["--ticks=3000"]), /--live-match/);
  assert.throws(() => performanceArgs(["--live-match", "--ticks=0"]), /integer/);
  assert.throws(() => performanceArgs(["--live-match", "--ticks=15000"]), /integer/);
  assert.throws(() => performanceArgs(["--live-match", "--ticks=3000.5"]), /integer/);
  assert.throws(() => performanceArgs(["--live-match", "--ticks=3e3"]), /integer/);
  assert.throws(() => performanceArgs(["--live-match", "--ticks=3000", "--frames=1800"]), /not both/);
  assert.throws(() => performanceArgs(["--live-match", "--ticks", "3000"]), /--ticks=value/);
});

test("render exclusions are explicit diagnostics, never a default optimization", () => {
  assert.ok(!performanceArgs([]).some((value) => value.startsWith("--diagnostic-hide")));
  assert.ok(performanceArgs(["--live-match", "--diagnostic-hide=world_drops"]).includes("--diagnostic-hide=world_drops"));
  assert.throws(() => performanceArgs(["--diagnostic-hide=world_drops"]), /--live-match/);
  assert.ok(performanceArgs(["--diagnostic-hide=effect_lights"]).includes("--diagnostic-hide=effect_lights"));
  assert.throws(() => performanceArgs(["--diagnostic-hide=viewmodel"]), /--live-match/);
  assert.throws(() => performanceArgs(["--live-match", "--diagnostic-hide=everything"]), /--diagnostic-hide/);
  assert.throws(() => performanceArgs(["--live-match", "--diagnostic-hide"]), /--diagnostic-hide=value/);
  for (const kind of ["viewmodel", "effect_lights", "muzzle_smoke", "map"]) {
    assert.ok(performanceArgs(["--live-match", `--diagnostic-hide=${kind}`]).includes(`--diagnostic-hide=${kind}`));
  }
});

test("phase profiling is explicit and restricted to the live-match fixture", () => {
  assert.throws(() => performanceArgs(["--profile-phases"]), /--live-match/);
  assert.ok(performanceArgs(["--live-match", "--profile-phases"]).includes("--profile-phases"));
  assert.ok(!performanceArgs(["--live-match"]).includes("--profile-phases"));
  const fixture = readFileSync(new URL("../game/tests/live_match_performance_test.gd", import.meta.url), "utf8");
  assert.match(fixture, /profile_script == null or not profile_script.can_instantiate\(\)/);
  const adapter = readFileSync(new URL("../game/tests/profiled_match_game.gd", import.meta.url), "utf8");
  assert.match(adapter, /func _reset_combatants_for_round\(keep_surviving_loadouts := true\)/);
  assert.match(adapter, /super\._reset_combatants_for_round\(keep_surviving_loadouts\)/);
});

test("combat coverage can be required without turning short navigation probes into combat claims", () => {
  assert.throws(() => performanceArgs(["--require-local-combat"]), /--live-match/);
  assert.ok(performanceArgs(["--live-match", "--require-local-combat"]).includes("--require-local-combat"));
  assert.ok(!performanceArgs(["--live-match"]).includes("--require-local-combat"));
});

test("map and team selection cannot silently benchmark a fallback scenario", () => {
  const args = performanceArgs(["--live-match", "--map=cs_assault", "--team=CT"]);
  assert.ok(args.includes("--map=cs_assault"));
  assert.ok(args.includes("--team=CT"));
  assert.ok(!performanceArgs(["--live-match"]).some(value => value.startsWith("--team=")));
  assert.throws(() => performanceArgs(["--map=cs_assualt"]), /--map/);
  assert.throws(() => performanceArgs(["--map=de_dust2", "--map=cs_assault"]), /--map/);
  assert.throws(() => performanceArgs(["--map", "cs_assault"]), /--map=value/);
  assert.throws(() => performanceArgs(["--team=CT"]), /--live-match/);
  assert.throws(() => performanceArgs(["--live-match", "--team=ct"]), /--team/);
  assert.throws(() => performanceArgs(["--live-match", "--team=T", "--team=CT"]), /--team/);
  assert.throws(() => performanceArgs(["--live-match", "--team", "CT"]), /--team=value/);
});
