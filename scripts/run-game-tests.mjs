import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const SUITES = [
  "settings", "network", "dedicated", "chat", "assets", "audio", "hud", "viewmodels", "characters", "movement",
  "collision", "ballistics", "weapons", "timing", "vfx", "rounds", "matches", "observers", "joins", "smoke",
  "map", "lighting", "bots", "bot-determinism", "hostage-bot-determinism", "assault-traversal", "match-driver",
].map((name) => `game:test:${name}`);

export class OutputGuard {
  constructor() {
    this.pending = { stdout: "", stderr: "" };
    this.errors = [];
    this.passes = 0;
  }

  line(text) {
    // Godot sometimes exits successfully after GDScript parse/runtime errors.
    // Never infer success solely from the child process's exit code.
    const line = text.replace(/\u001b\[[0-9;]*m/g, "");
    if (/^(?:SCRIPT ERROR:|ERROR:)|ObjectDB instances? (?:were |was )?leaked|\b[A-Z][A-Z0-9_]*_FAIL\b/.test(line.trim())) {
      this.errors.push(line);
    }
    if (/\b[A-Z][A-Z0-9_]*_PASS\b/.test(line)) this.passes += 1;
  }

  feed(stream, chunk) {
    const lines = (this.pending[stream] + chunk).split(/\r?\n/);
    this.pending[stream] = lines.pop();
    for (const line of lines) this.line(line);
  }

  finish() {
    for (const stream of Object.keys(this.pending)) {
      this.line(this.pending[stream]);
      this.pending[stream] = "";
    }
  }
}

export function runCheckedCommand(command, args, {
  cwd = process.cwd(), timeoutMs = 600_000, minimumPasses = 1,
  env = process.env,
  onOutput = (stream, chunk) => process[stream].write(chunk),
} = {}) {
  return new Promise((done) => {
    const started = performance.now();
    const guard = new OutputGuard();
    const child = spawn(command, args, {
      cwd, env, detached: process.platform !== "win32", stdio: ["ignore", "pipe", "pipe"],
    });
    let timedOut = false;
    let launchError = null;
    let killTimer;
    function stop(signal) {
      if (!child.pid) return;
      try {
        // Only the process group created for this specific test command.
        if (process.platform !== "win32") process.kill(-child.pid, signal);
        else child.kill(signal);
      } catch (error) {
        if (error.code !== "ESRCH") launchError = error.message;
      }
    }
    const interrupt = () => stop("SIGTERM");
    process.on("SIGINT", interrupt);
    process.on("SIGTERM", interrupt);
    const timer = setTimeout(() => {
      timedOut = true;
      stop("SIGTERM");
      killTimer = setTimeout(() => stop("SIGKILL"), 5_000);
    }, timeoutMs);
    for (const stream of ["stdout", "stderr"]) {
      child[stream].setEncoding("utf8");
      child[stream].on("data", (chunk) => {
        guard.feed(stream, chunk);
        onOutput(stream, chunk);
      });
    }
    child.on("error", (error) => { launchError = error.message; });
    child.on("close", (code, signal) => {
      clearTimeout(timer);
      clearTimeout(killTimer);
      process.off("SIGINT", interrupt);
      process.off("SIGTERM", interrupt);
      guard.finish();
      done({
        command, args, code, signal, timedOut, launchError,
        elapsedMs: Math.round(performance.now() - started),
        passes: guard.passes, minimumPasses, errors: guard.errors,
        ok: code === 0 && !signal && !timedOut && !launchError
          && guard.errors.length === 0 && guard.passes >= minimumPasses,
      });
    });
  });
}

async function main() {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  const config = JSON.parse(readFileSync(resolve(root, "package.json"), "utf8"));
  const selected = process.argv.slice(2);
  const suites = selected.length ? selected : SUITES;
  if (suites.some((suite) => !SUITES.includes(suite))) throw new Error("Unknown game test suite");
  const report = { startedAt: new Date().toISOString(), ok: false, suites: [] };
  const reportPath = resolve(root, `game/artifacts/headless-test${selected.length ? "-selected" : ""}-report.json`);
  mkdirSync(dirname(reportPath), { recursive: true });
  for (const suite of suites) {
    const minimumPasses = [...config.scripts[suite].matchAll(/--script\s+/g)].length;
    const result = await runCheckedCommand("npm", ["run", suite], { cwd: root, minimumPasses });
    report.suites.push({ suite, ...result });
    writeFileSync(reportPath, JSON.stringify(report, null, 2) + "\n");
    if (!result.ok) {
      console.error(`GAME_STRICT_GATE_FAIL ${suite}: ${JSON.stringify(result)}`);
      process.exitCode = 1;
      return;
    }
  }
  report.ok = true;
  report.finishedAt = new Date().toISOString();
  writeFileSync(reportPath, JSON.stringify(report, null, 2) + "\n");
  console.log(`GAME_STRICT_GATE_PASS suites=${suites.length} report=${reportPath}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(error); process.exitCode = 1; });
}
