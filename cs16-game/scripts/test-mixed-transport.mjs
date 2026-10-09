// Starts a local dedicated server and joins it with one desktop (ENet/UDP)
// probe and one browser-transport (WebSocket) probe at the same time. Each
// probe must see both humans in the same authoritative Dust2 world.
import { createSocket } from "node:dgram";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { once } from "node:events";
import { spawn } from "node:child_process";
import { runCheckedCommand } from "./run-game-tests.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const artifacts = mkdtempSync(join(tmpdir(), "protocol47-mixed-transport-"));
const reservation = createSocket("udp4");
reservation.bind(0, "127.0.0.1");
await once(reservation, "listening");
const port = reservation.address().port;
await new Promise(done => reservation.close(done));
// The server listens for WebSockets on its UDP port + 1.
const webSocketPort = port + 1;

const server = spawn("godot", [
  "--headless", "--audio-driver", "Dummy", "--log-file", join(artifacts, "server.log"),
  "--path", resolve(root, "game"), "--", "--dedicated", `--port=${port}`,
], { cwd: root, env: { ...process.env, PROTOCOL47_SETTINGS_PATH: join(artifacts, "server.cfg") } });
let serverOutput = "";
const listening = new Promise((ready, fail) => {
  server.stdout.on("data", chunk => {
    serverOutput += chunk;
    if (serverOutput.includes(`WebSocket ${webSocketPort}`)) ready();
  });
  server.on("exit", code => fail(new Error(`server exited early (${code}): ${serverOutput}`)));
  setTimeout(() => fail(new Error("server readiness timeout")), 30_000);
});

try {
  await listening;
  const probe = (name, ...target) => runCheckedCommand("godot", [
    "--headless", "--audio-driver", "Dummy", "--log-file", join(artifacts, `${name}.log`),
    "--path", resolve(root, "game"), "--script", "res://tests/mixed_transport_probe.gd",
    "--", ...target, "--expect-actors=13", "--linger-ms=3000",
  ], { cwd: root, timeoutMs: 60_000, env: { ...process.env, PROTOCOL47_SETTINGS_PATH: join(artifacts, `${name}.cfg`) } });
  const results = await Promise.all([
    probe("udp", "--join=127.0.0.1", `--port=${port}`).then(result => ({ name: "udp", result })),
    probe("websocket", `--join=ws://127.0.0.1:${webSocketPort}`).then(result => ({ name: "websocket", result })),
  ]);
  const failed = results.filter(({ result }) => !result.ok);
  if (failed.length) throw new Error(`probe failure: ${JSON.stringify(failed)}`);
  console.log(`GAME_NETWORK_MIXED_TRANSPORT_PASS udp=${port} websocket=${webSocketPort} artifacts=${artifacts}`);
} finally {
  server.kill();
}
