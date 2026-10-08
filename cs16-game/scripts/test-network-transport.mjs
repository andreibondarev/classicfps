import { createSocket } from "node:dgram";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { once } from "node:events";
import { runCheckedCommand } from "./run-game-tests.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const options = process.argv.slice(2);
const human = options.includes("--human-simulation");
const roster = options.includes("--game-roster");
const admission = options.includes("--game-admission");
const world = options.includes("--world");
const chat = options.includes("--chat");
const renderClient = options.includes("--render-client");
const maps = options.filter(option => option.startsWith("--map="));
const map = maps[0]?.slice("--map=".length) ?? "de_dust2";
if (new Set(options).size !== options.length || [human, roster, admission, world, chat].filter(Boolean).length > 1 || maps.length > 1
  || (maps.length && !roster && !admission && !world) || !["de_dust2", "cs_assault"].includes(map)
  || (renderClient && !world)
	|| options.some(option => !["--human-simulation", "--game-roster", "--game-admission", "--world", "--chat", "--render-client"].includes(option) && !option.startsWith("--map="))) {
	throw new Error("Use --human-simulation, --game-roster, --game-admission, --chat or --world [--map=de_dust2|cs_assault]");
}
const marker = chat ? "CHAT_TRANSPORT" : world ? "WORLD" : admission ? "GAME_ADMISSION" : roster ? "GAME_ROSTER" : human ? "HUMAN_SIMULATION" : "TRANSPORT";
const artifacts = mkdtempSync(join(tmpdir(), "protocol47-network-"));
const reservation = createSocket("udp4");
reservation.bind(0, "127.0.0.1");
await once(reservation, "listening");
const port = reservation.address().port;
await new Promise(resolve => reservation.close(resolve));
// The engine opens its own socket; a port race is reported as failure, not hidden.
const args = role => [
  ...(renderClient && role === "client" ? [] : ["--headless"]), "--audio-driver", "Dummy", "--log-file", join(artifacts, `${role}.log`),
  "--path", resolve(root, "game"), "--script", chat ? "res://tests/network_chat_transport_test.gd" : world ? "res://tests/network_world_transport_test.gd" : admission ? "res://tests/network_admission_transport_test.gd" : roster ? "res://tests/network_game_roster_test.gd" : "res://tests/network_transport_test.gd",
  "--", `--role=${role}`, `--port=${port}`, ...(human ? ["--human-simulation"] : []), ...(roster || admission || world ? [`--map=${map}`] : []),
  ...(renderClient && role === "client" ? [`--capture=${join(artifacts, "client.png")}`] : []),
];
let ready;
let hostOutput = "";
const readiness = new Promise(resolve => { ready = resolve; });
const host = runCheckedCommand("godot", args("host"), {
  cwd: root, timeoutMs: roster || admission || world || chat ? 120_000 : 30_000,
  env: { ...process.env, PROTOCOL47_SETTINGS_PATH: join(artifacts, "host.cfg") },
  onOutput(stream, chunk) {
    process[stream].write(chunk);
    hostOutput += chunk;
    if (hostOutput.includes("NETWORK_TRANSPORT_READY")) ready();
  },
});
let readinessTimer;
try {
  await Promise.race([
    readiness,
    host.then(result => { throw new Error(`Host exited before readiness: ${JSON.stringify(result)}`); }),
    new Promise((_, reject) => { readinessTimer = setTimeout(() => reject(new Error("Host readiness timeout")), 10_000); }),
  ]);
  clearTimeout(readinessTimer);
  const client = runCheckedCommand("godot", args("client"), {
    cwd: root, timeoutMs: roster || admission || world || chat ? 120_000 : 30_000,
    env: { ...process.env, PROTOCOL47_SETTINGS_PATH: join(artifacts, "client.cfg") },
  });
  const results = await Promise.all([host, client]);
  if (results.some(result => !result.ok)) throw new Error(JSON.stringify(results));
  console.log(`GAME_NETWORK_${marker}_PASS artifacts=${artifacts}`);
} catch (error) {
  // Keep ownership of the bounded host job even when startup or the client fails.
  await host;
  console.error(`GAME_NETWORK_${marker}_FAIL ${error.message} artifacts=${artifacts}`);
  process.exitCode = 1;
} finally {
  clearTimeout(readinessTimer);
}
