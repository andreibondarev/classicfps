import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { OutputGuard, runCheckedCommand, SUITES } from "./run-game-tests.mjs";

test("the full gate checks fresh settings, restart persistence and profile isolation", () => {
  assert.ok(SUITES.includes("game:test:settings"));
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.equal(config.scripts["game:test:settings"], "node scripts/test-settings-persistence.mjs");
});

test("the full gate validates the headless ten-slot Dust2 server", () => {
  assert.ok(SUITES.includes("game:test:dedicated"));
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.match(config.scripts["game:test:dedicated"],
    /--headless --audio-driver Dummy .*dedicated_server_test\.gd -- --dedicated --port=27549$/);
});

test("HUD gate clicks Quit and requires silent process exit offline and while hosting", () => {
  assert.ok(SUITES.includes("game:test:hud"));
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  const commands = config.scripts["game:test:hud"].split(" && ");
  for (const suffix of ["", " -- --host-session", " -- --pending-lookup"]) {
    assert.ok(commands.some(command => command.includes("--headless --audio-driver Dummy")
      && command.endsWith(`--script res://tests/menu_quit_test.gd${suffix}`)));
  }
});

test("network gate requires the Dust2 direct connection menu and offline recovery", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:network"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/network_menu_test.gd -- --map=de_dust2")));
});

test("network gate requires silent owner movement prediction and reconciliation", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:network"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/network_movement_prediction_test.gd")));
});

test("network gate requires bounded, deduplicated combat presentation events", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:network"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/network_combat_events_test.gd")));
});

test("network gate requires silent grenade, smoke and objective feedback regression", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:network"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/network_grenade_feedback_test.gd")));
});

test("weapon gate requires silent swept drop motion and landing regression", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:weapons"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/weapon_drop_motion_test.gd")));
});

test("weapon gate covers macOS translated Ctrl-click and genuine right-click independently", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:weapons"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/crouch_mouse_input_test.gd")));
});

test("weapon gate requires silent Glock left/right click regression", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:weapons"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/glock_mouse_input_test.gd")));
});

test("the full gate validates packets and real loopback RPC sessions silently", () => {
  assert.ok(SUITES.includes("game:test:network"));
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.match(config.scripts["game:test:network"], /--headless --audio-driver Dummy .*res:\/\/tests\/network_packet_test.gd/);
  assert.ok(config.scripts["game:test:network"].split(" && ").includes("node scripts/test-network-transport.mjs"));
});

test("chat gate validates UI, authority and real two-process delivery", () => {
  assert.ok(SUITES.includes("game:test:chat"));
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  const commands = config.scripts["game:test:chat"].split(" && ");
  assert.ok(commands.some(command => command.endsWith("--script res://tests/network_chat_test.gd")));
  assert.ok(commands.some(command => command.endsWith("--script res://tests/chat_ui_test.gd")));
  assert.ok(commands.includes("node scripts/test-network-transport.mjs --chat"));
});

test("network coverage exercises remote commands through real human physics and weapons", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  const command = config.scripts["game:test:network"];
  assert.match(command, /--headless --audio-driver Dummy .*res:\/\/tests\/network_human_controller_test.gd/);
  assert.match(command, /--headless --audio-driver Dummy .*res:\/\/tests\/network_human_ownership_test.gd/);
  assert.ok(command.split(" && ").includes("node scripts/test-network-transport.mjs --human-simulation"));
});

test("network coverage binds real peers to the actual Game roster on both maps", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  const commands = config.scripts["game:test:network"].split(" && ");
  for (const map of ["de_dust2", "cs_assault"]) {
    assert.ok(commands.includes(`node scripts/test-network-transport.mjs --game-roster --map=${map}`));
  }
});

test("network coverage validates reliable actions and real client team/class admission on both maps", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  const commands = config.scripts["game:test:network"].split(" && ");
  assert.ok(commands.some(command => command.includes("--headless --audio-driver Dummy")
    && command.endsWith("--script res://tests/network_action_test.gd")));
  for (const map of ["de_dust2", "cs_assault"]) {
    assert.ok(commands.includes(`node scripts/test-network-transport.mjs --game-admission --map=${map}`));
  }
});

test("network coverage requires bounded world state and real client Game views on both maps", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  const commands = config.scripts["game:test:network"].split(" && ");
  assert.ok(commands.some(command => command.includes("--headless --audio-driver Dummy")
    && command.endsWith("--script res://tests/network_world_state_test.gd")));
  assert.ok(commands.some(command => command.includes("--headless --audio-driver Dummy")
    && command.endsWith("--script res://tests/network_world_chunks_test.gd")));
  for (const map of ["de_dust2", "cs_assault"]) {
    assert.ok(commands.includes(`node scripts/test-network-transport.mjs --world --map=${map}`));
  }
});

test("network coverage exercises remote human C4 ownership, input and objective lifecycle silently", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:network"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/network_human_objective_test.gd")));
});

test("network coverage requires silent Dust2 weapon action ownership and scope-state regression", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:network"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/network_weapon_action_test.gd -- --map=de_dust2")));
});

test("network coverage requires silent Dust2 per-human buying regression", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:network"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/network_buy_test.gd -- --map=de_dust2")));
});

test("network coverage requires silent Dust2 local-menu versus world-pause regression", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:network"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/network_pause_test.gd -- --map=de_dust2")));
});

test("network coverage exercises per-human world use, brush contacts and camera ownership silently", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:network"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/network_human_world_use_test.gd")));
});

test("network coverage exercises remote gun ownership, death and pickup arbitration silently", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:network"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/network_human_inventory_test.gd")));
});

test("network coverage requires real-map team/class admission and human round lifecycle on both maps", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  const commands = config.scripts["game:test:network"].split(" && ");
  for (const map of ["de_dust2", "cs_assault"]) {
    assert.ok(commands.some(command => command.includes("--headless --audio-driver Dummy")
      && command.endsWith(`--script res://tests/network_human_admission_test.gd -- --map=${map}`)));
  }
});

test("weapon coverage retains local input drop, bot death drops and empty-slot pickup", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:weapons"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/weapon_drop_pickup_test.gd")));
});

test("map coverage retains the local Assault camera origin, aim and return deadline", () => {
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:map"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/hostage_floor_camera_integration_test.gd")));
});

test("the full gate includes from-spawn Assault rescue, not only staged objectives", () => {
  assert.ok(SUITES.includes("game:test:assault-traversal"));
});

test("bot coverage requires bounded door waiting and normal-combat entrance progress", () => {
  assert.ok(SUITES.includes("game:test:bots"));
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  const commands = config.scripts["game:test:bots"].split(" && ");
  assert.ok(commands.some(command => command.includes("--audio-driver Dummy")
    && command.includes("--script res://tests/bot_door_wait_test.gd")));
  assert.ok(commands.some(command => command.includes("--headless --fixed-fps 60 --audio-driver Dummy")
    && command.includes("--script res://tests/hostage_combat_probe.gd")
    && command.includes("--ticks=10000 --require-door-progress")));
});

test("audio coverage includes active-camera attenuation on both maps with muted playback", () => {
  assert.ok(SUITES.includes("game:test:audio"));
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  const commands = config.scripts["game:test:audio"].split(" && ");
  for (const map of ["de_dust2", "cs_assault"]) {
    assert.ok(commands.some(command => command.includes("--headless --audio-driver Dummy")
      && command.includes("--script res://tests/camera_audio_listener_test.gd")
      && command.endsWith(`--map=${map}`)));
  }
});

test("the full gate verifies the benchmark driver's physical warehouse traversal silently", () => {
  assert.ok(SUITES.includes("game:test:match-driver"));
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  const command = config.scripts["game:test:match-driver"];
  assert.ok(command.includes("--headless --fixed-fps 30 --audio-driver Dummy"));
  assert.ok(command.includes("--script res://tests/match_driver_traversal_test.gd"));
  assert.ok(command.includes("--script res://tests/match_driver_solo_test.gd"));
  assert.ok(command.includes("--headless --fixed-fps 60 --audio-driver Dummy"));
  assert.ok(command.includes("--team=CT --ticks=24000 --require-driver-progress"));
  assert.ok(command.includes("node scripts/test-full-match-probe.mjs"));
});

test("the full gate exercises both maps/teams and both MR15 endings through rematch", () => {
  assert.ok(SUITES.includes("game:test:matches"));
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  const commands = config.scripts["game:test:matches"].split(" && ");
  assert.equal(commands.length, 8);
  for (const map of ["de_dust2", "cs_assault"]) for (const team of ["T", "CT"]) {
    const cases = commands.filter(command => command.includes(`--map=${map} --team=${team}`));
    assert.equal(cases.length, 2);
    assert.equal(cases.filter(command => command.endsWith("--tie")).length, 1);
    assert.ok(cases.every(command => command.includes("--audio-driver Dummy") && command.includes("--script res://tests/match_lifecycle_test.gd")));
  }
});

test("round coverage includes silent disconnection and spawnable-team elimination rules", () => {
  assert.ok(SUITES.includes("game:test:rounds"));
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  assert.ok(config.scripts["game:test:rounds"].split(" && ").some(command =>
    command.includes("--headless --audio-driver Dummy")
      && command.endsWith("--script res://tests/round_disconnect_test.gd")));
});

test("the full gate covers join rules and the real team/class menu on both maps silently", () => {
  assert.ok(SUITES.includes("game:test:joins"));
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  const commands = config.scripts["game:test:joins"].split(" && ");
  assert.equal(commands.length, 3);
  assert.ok(commands.every(command => command.includes("--headless --audio-driver Dummy")));
  assert.ok(commands.some(command => command.includes("res://tests/team_join_rules_test.gd")));
  for (const map of ["de_dust2", "cs_assault"]) {
    assert.ok(commands.some(command => command.includes("res://tests/team_selection_lifecycle_test.gd") && command.endsWith(`--map=${map}`)));
  }
});

test("the full gate tests intentional observers on both maps and participant death spectating", () => {
  assert.ok(SUITES.includes("game:test:observers"));
  const config = JSON.parse(readFileSync(new URL("../package.json", import.meta.url)));
  const commands = config.scripts["game:test:observers"].split(" && ");
  assert.equal(commands.length, 3);
  assert.ok(commands.every(command => command.includes("--headless --audio-driver Dummy")));
  assert.ok(commands.some(command => command.includes("res://tests/spectator_camera_test.gd")));
  for (const map of ["de_dust2", "cs_assault"]) {
    assert.ok(commands.some(command => command.includes("res://tests/observer_match_test.gd") && command.endsWith(`--map=${map}`)));
  }
});

test("detects split error lines and an unterminated final error", () => {
  const guard = new OutputGuard();
  guard.feed("stderr", "SCRIPT ER");
  guard.feed("stdout", "GAME_EXAMPLE_TEST_PASS\n");
  guard.feed("stderr", "ROR: Invalid call\nERROR: Failed to load script");
  guard.finish();
  assert.equal(guard.passes, 1);
  assert.equal(guard.errors.length, 2);
});

const run = (source, options = {}) => runCheckedCommand(process.execPath, ["-e", source], {
  onOutput: () => {}, ...options,
});

test("zero exit plus Godot error is failure even with a pass marker", async () => {
  const result = await run("console.error('SCRIPT ERROR: Parse Error'); console.log('GAME_TEST_PASS')");
  assert.equal(result.code, 0);
  assert.equal(result.ok, false);
});

test("shutdown leaks fail the gate even when Godot only prints a warning", async () => {
  const result = await run("console.warn('WARNING: 14 ObjectDB instances were leaked at exit'); console.log('GAME_TEST_PASS')");
  assert.equal(result.ok, false);
});

test("rejects silent exit, missing pass markers, and nonzero exit", async () => {
  assert.equal((await run("")).ok, false);
  assert.equal((await run("console.log('GAME_TEST_PASS')", { minimumPasses: 2 })).ok, false);
  assert.equal((await run("console.log('GAME_TEST_PASS'); process.exit(1)")).ok, false);
});

test("accepts successful assertions from every expected script", async () => {
  assert.equal((await run("console.log('GAME_ONE_PASS\nGAME_TWO_PASS')".replace(/\n/g, "\\n"), {
    minimumPasses: 2,
  })).ok, true);
});

test("terminates a hung test instead of leaving the gate running forever", async () => {
  const result = await run("setInterval(() => {}, 1000)", { timeoutMs: 300 });
  assert.equal(result.timedOut, true);
  assert.equal(result.ok, false);
});

test("a missing executable is recorded as failure", async () => {
  const result = await runCheckedCommand("/nonexistent/protocol47-test-runner", [], { onOutput: () => {} });
  assert.equal(result.ok, false);
  assert.ok(result.launchError);
});
