import { fileURLToPath } from "node:url";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { runCheckedCommand } from "./run-game-tests.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
export const fixtures = ["presentation_loading_test", "animation_pose_sampler_test", "character_shadow_render_test", "combat_effects_test", "decal_modulation_render_test", "viewmodel_residency_render_test", "hostage_presentation_test", "bsp_color_pipeline_probe", "match_lifecycle_test", "observer_match_test", "team_selection_lifecycle_test"];

export function renderOptions(options) {
  const selected = {};
  const allowed = {
    renderer: ["gl_compatibility", "mobile", "forward_plus"],
    driver: ["metal", "vulkan", "opengl3", "opengl3_angle"],
  };
  for (const option of options) {
    const match = /^--(renderer|driver)=(.+)$/.exec(option);
    if (!match) throw new Error("Use --renderer=value and --driver=value; other options are not supported");
    const [, key, value] = match;
    if (selected[key] || !allowed[key].includes(value)) throw new Error(`Invalid or repeated --${key}`);
    selected[key] = value;
  }
  if (selected.driver && !selected.renderer) throw new Error("--driver requires an explicit --renderer");
  if (selected.driver && ((selected.renderer === "gl_compatibility") !== selected.driver.startsWith("opengl3"))) {
    throw new Error("Incompatible renderer/driver pair");
  }
  return selected;
}

export function renderedTestArgs(fixture, options = [], projectRoot = root) {
  if (!fixtures.includes(fixture)) throw new Error("Unknown rendered fixture");
  const { renderer, driver } = renderOptions(options);
  return [
    "--always-on-top", "--audio-driver", "Dummy",
    ...(fixture === "presentation_loading_test" ? ["--disable-render-loop"] : []),
    ...(renderer ? ["--rendering-method", renderer] : []),
    ...(driver ? ["--rendering-driver", driver] : []),
    "--log-file", `/tmp/protocol47-${fixture}-${renderer ?? "default"}-${driver ?? "default"}-rendered.log`,
    "--path", resolve(projectRoot, "game"),
    "--script", `res://tests/${fixture}.gd`,
  ];
}

async function main() {
  const options = process.argv.slice(2);
  const selected = renderOptions(options);
  const report = { startedAt: new Date().toISOString(), requestedBackend: selected, audioMuted: true, ok: false, fixtures: [] };
  const path = resolve(root, `game/artifacts/render-test-${selected.renderer ?? "default"}-${selected.driver ?? "default"}-report.json`);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(report, null, 2) + "\n");
  for (const fixture of fixtures) {
    const result = await runCheckedCommand("godot", renderedTestArgs(fixture, options), { cwd: root, timeoutMs: 90_000 });
    report.fixtures.push({ fixture, ...result });
    if (!result.ok) report.finishedAt = new Date().toISOString();
    writeFileSync(path, JSON.stringify(report, null, 2) + "\n");
    if (!result.ok) {
      console.error(`GAME_RENDER_GATE_FAIL ${JSON.stringify(result)}`);
      process.exitCode = 1;
      return;
    }
  }
  report.ok = true;
  report.finishedAt = new Date().toISOString();
  writeFileSync(path, JSON.stringify(report, null, 2) + "\n");
  console.log(`GAME_RENDER_GATE_PASS fixtures=${fixtures.length} report=${path}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error); process.exitCode = 1; });
}
