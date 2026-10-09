// Admin moderation end to end: starts a dedicated server with --admin-log and
// --moderation, then plays the admin service's part by rewriting the
// moderation file while real clients (tests/moderation_probe.gd) are joined:
//   a muted player's chat is logged but not delivered, a kick drops the player
//   with the admin's reason, a tag ban drops a connected player and refuses
//   them on rejoin, and an address ban refuses a player with a new tag.
import assert from "node:assert/strict";
import { createSocket } from "node:dgram";
import { mkdtempSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { once } from "node:events";
import { spawn } from "node:child_process";
import { runCheckedCommand } from "./run-game-tests.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const artifacts = mkdtempSync(join(tmpdir(), "protocol47-moderation-"));
const events = join(artifacts, "events.jsonl");
const moderationPath = join(artifacts, "moderation.json");
const reservation = createSocket("udp4");
reservation.bind(0, "127.0.0.1");
await once(reservation, "listening");
const port = reservation.address().port;
await new Promise(done => reservation.close(done));

const MUTED = "a".repeat(32);
const BANNED = "b".repeat(32);
const FRESH = "c".repeat(32);
let moderation = { bans: [], mutes: [{ tag: MUTED, until: 0, reason: "" }], kicks: [] };
function writeModeration() {
  // Atomic like the admin service, and a new mtime for the game's poll.
  writeFileSync(moderationPath + ".tmp", JSON.stringify(moderation));
  renameSync(moderationPath + ".tmp", moderationPath);
}
writeModeration();

function readEvents() {
  return readFileSync(events, "utf8").split("\n").filter(Boolean).map(line => JSON.parse(line));
}

const server = spawn("godot", [
  "--headless", "--audio-driver", "Dummy", "--log-file", join(artifacts, "server.log"),
  "--path", resolve(root, "game"), "--", "--dedicated", `--port=${port}`,
  `--admin-log=${events}`, `--moderation=${moderationPath}`,
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

// Runs one probe; onReady (after it joined and chatted) plays the admin's move.
async function probe(name, tag, extra, onReady = () => {}) {
  const settings = join(artifacts, `${name}.cfg`);
  writeFileSync(settings, `[identity]\n\nclient_tag="${tag}"\n`);
  let readyHandled = false;
  const result = await runCheckedCommand("godot", [
    "--headless", "--audio-driver", "Dummy", "--log-file", join(artifacts, `${name}.log`),
    "--path", resolve(root, "game"), "--script", "res://tests/moderation_probe.gd",
    "--", "--join=127.0.0.1", `--port=${port}`, ...extra,
  ], {
    cwd: root, timeoutMs: 90_000, env: { ...process.env, PROTOCOL47_SETTINGS_PATH: settings },
    onOutput: (stream, chunk) => {
      process[stream].write(chunk);
      if (!readyHandled && chunk.includes("MODERATION_PROBE_READY")) {
        readyHandled = true;
        // Give the host a moment to log the identify and chat events.
        setTimeout(onReady, 2500);
      }
    },
  });
  assert.ok(result.ok, `${name}: ${JSON.stringify(result)}`);
}

function peerFor(tag) {
  const identify = readEvents().filter(event => event.type === "identify" && event.tag === tag).at(-1);
  assert.ok(identify, `the host logged ${tag.slice(0, 4)}'s identity`);
  return identify.peer;
}

try {
  await listening;
  await probe("muted", MUTED, ["--team=T", "--chat=muted line", "--expect-status=KICKED BY ADMIN: SPAM"], () => {
    const chat = readEvents().filter(event => event.type === "chat");
    assert.deepEqual(chat.map(event => [event.text, event.blocked, event.tag]), [["muted line", true, MUTED]],
      "a muted player's chat is logged as blocked");
    moderation.kicks.push({ id: "kick-1", peer: peerFor(MUTED), tag: MUTED, reason: "spam", ts: Date.now() / 1000 });
    writeModeration();
  });
  await probe("banned", BANNED, ["--team=CT", "--chat=hello", "--expect-status=BANNED FROM THIS SERVER: CHEATING"], () => {
    const hello = readEvents().find(event => event.type === "chat" && event.text === "hello");
    assert.equal(hello?.blocked, false, "an unmuted player's chat is delivered and logged");
    moderation.bans.push({ tag: BANNED, address: "", until: 0, reason: "cheating" });
    writeModeration();
  });
  await probe("banned-rejoin", BANNED, ["--expect-refused", "--expect-status=BANNED FROM THIS SERVER"]);
  moderation.bans.push({ tag: "", address: "127.0.0.1", until: Date.now() / 1000 + 3600, reason: "" });
  writeModeration();
  await new Promise(done => setTimeout(done, 1500));
  await probe("address-ban", FRESH, ["--expect-refused", "--expect-status=BANNED FROM THIS SERVER"]);
  const outcomes = readEvents().filter(event => event.type.endsWith("_enforced")).map(event => event.type);
  assert.ok(outcomes.includes("kick_enforced") && outcomes.filter(type => type === "ban_enforced").length >= 3,
    `moderation outcomes are logged: ${outcomes}`);
  console.log(`GAME_MODERATION_PASS artifacts=${artifacts}`);
} finally {
  server.kill();
}
