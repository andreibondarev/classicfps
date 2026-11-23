// Join/leave notices end to end: a watcher stays connected to a dedicated
// server while a second named player joins and leaves; the watcher must get
// "<name> has joined the game" then "has left the game" in its chat area, and
// the joining player sees its own arrival.
import assert from "node:assert/strict";
import { createSocket } from "node:dgram";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { once } from "node:events";
import { spawn } from "node:child_process";
import { runCheckedCommand } from "./run-game-tests.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const artifacts = mkdtempSync(join(tmpdir(), "protocol47-notices-"));
const reservation = createSocket("udp4");
reservation.bind(0, "127.0.0.1");
await once(reservation, "listening");
const port = reservation.address().port;
await new Promise(done => reservation.close(done));

const server = spawn("godot", [
  "--headless", "--audio-driver", "Dummy", "--log-file", join(artifacts, "server.log"),
  "--path", resolve(root, "game"), "--", "--dedicated", `--port=${port}`,
], { cwd: root, env: { ...process.env, PROTOCOL47_SETTINGS_PATH: join(artifacts, "server.cfg") } });
let serverOutput = "";
const listening = new Promise((ready, fail) => {
  server.stdout.on("data", chunk => {
    serverOutput += chunk;
    if (serverOutput.includes("listening on UDP")) ready();
  });
  server.on("exit", code => fail(new Error(`server exited early (${code}): ${serverOutput}`)));
  setTimeout(() => fail(new Error("server readiness timeout")), 30_000);
});

function probe(name, playerName, extra, onOutput = () => {}) {
  const settings = join(artifacts, `${name}.cfg`);
  writeFileSync(settings, `[multiplayer]\n\nplayer_name="${playerName}"\n`);
  return runCheckedCommand("godot", [
    "--headless", "--audio-driver", "Dummy", "--log-file", join(artifacts, `${name}.log`),
    "--path", resolve(root, "game"), "--script", "res://tests/notice_probe.gd",
    "--", "--join=127.0.0.1", `--port=${port}`, ...extra,
  ], {
    cwd: root, timeoutMs: 90_000, env: { ...process.env, PROTOCOL47_SETTINGS_PATH: settings },
    onOutput: (stream, chunk) => { process[stream].write(chunk); onOutput(chunk); },
  });
}

try {
  await listening;
  let visitor;
  const watcher = probe("watcher", "Watcher", ["--with-game", "--expect=joined:Visitor,left:Visitor"], chunk => {
    if (!visitor && chunk.includes("NOTICE_PROBE_ONLINE")) {
      visitor = probe("visitor", "Visitor", ["--leave-after-ms=4000"]);
    }
  });
  const watched = await watcher;
  assert.ok(watched.ok, `watcher: ${JSON.stringify(watched)}`);
  const visited = await visitor;
  assert.ok(visited.ok, `visitor: ${JSON.stringify(visited)}`);
  console.log(`GAME_JOIN_LEAVE_NOTICES_PASS artifacts=${artifacts}`);
} finally {
  server.kill();
}
