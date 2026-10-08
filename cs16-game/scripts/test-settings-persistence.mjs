import assert from "node:assert/strict";
import { mkdtempSync, existsSync, readFileSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, resolve } from "node:path";
import { runCheckedCommand } from "./run-game-tests.mjs";

const directory = mkdtempSync(join(tmpdir(), "protocol47-settings-"));
const path = join(directory, "protocol47.cfg");
// The macOS release check must not modify the installed player's profile.
const normalPath = process.platform === "darwin"
  ? join(homedir(), "Library/Application Support/Godot/app_userdata/Protocol 47/protocol47.cfg") : null;
const normalBefore = normalPath && existsSync(normalPath) ? readFileSync(normalPath) : null;
const args = ["--headless", "--audio-driver", "Dummy", "--path", resolve("game"),
  "--script", "res://tests/settings_persistence_test.gd"];
try {
  for (const mode of ["write", "read"]) {
    const result = await runCheckedCommand("godot", [...args, "--log-file", join(directory, `${mode}.log`), "--", `--${mode}`], {
      timeoutMs: 30_000, env: { ...process.env, PROTOCOL47_SETTINGS_PATH: path },
    });
    assert.ok(result.ok, JSON.stringify(result));
  }
  const nameTest = await runCheckedCommand("godot", ["--headless", "--audio-driver", "Dummy", "--path", resolve("game"),
    "--script", "res://tests/player_name_test.gd"], {
    timeoutMs: 60_000, env: { ...process.env, PROTOCOL47_SETTINGS_PATH: join(directory, "name-test.cfg") },
  });
  assert.ok(nameTest.ok, JSON.stringify(nameTest));
  for (const [index, invalidPath] of ["relative/profile.cfg", "res://profile.cfg", "user://profile.cfg",
    join(directory, "absent", "profile.cfg"), directory].entries()) {
    const invalid = await runCheckedCommand("godot", [...args, "--log-file", join(directory, `invalid-${index}.log`)], {
      timeoutMs: 30_000, env: { ...process.env, PROTOCOL47_SETTINGS_PATH: invalidPath }, onOutput: () => {},
    });
    assert.equal(invalid.code, 2, invalidPath);
    assert.equal(invalid.timedOut, false);
    assert.ok(invalid.errors.some(line => line.includes("Invalid PROTOCOL47_SETTINGS_PATH")));
  }
  if (normalPath) {
    const normalAfter = existsSync(normalPath) ? readFileSync(normalPath) : null;
    assert.deepEqual(normalAfter, normalBefore, "installed user settings must remain unchanged");
  }
  console.log(`GAME_SETTINGS_ISOLATION_PASS artifacts=${directory}`);
} catch (error) {
  console.error(error);
  process.exitCode = 1;
}
