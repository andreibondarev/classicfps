import test from "node:test";
import assert from "node:assert/strict";
import { fixtures, renderOptions, renderedTestArgs } from "./run-game-render-tests.mjs";

test("all rendered checks are silent, visible, and use the project default unless requested", () => {
  assert.equal(fixtures.length, 11);
  assert.ok(fixtures.includes("presentation_loading_test"));
  assert.ok(fixtures.includes("team_selection_lifecycle_test"));
  assert.ok(fixtures.includes("decal_modulation_render_test"));
  assert.ok(fixtures.includes("bsp_color_pipeline_probe"));
  assert.ok(fixtures.includes("match_lifecycle_test"));
  assert.ok(fixtures.includes("observer_match_test"));
  for (const fixture of fixtures) {
    const args = renderedTestArgs(fixture, [], "/test project");
    assert.ok(args.includes("--always-on-top"));
    assert.ok(!args.includes("--headless"));
    assert.equal(args.includes("--disable-render-loop"), fixture === "presentation_loading_test");
    assert.equal(args[args.indexOf("--audio-driver") + 1], "Dummy");
    assert.equal(args[args.indexOf("--path") + 1], "/test project/game");
    assert.equal(args[args.indexOf("--script") + 1], `res://tests/${fixture}.gd`);
    assert.ok(!args.includes("--rendering-method"));
  }
});

test("backend overrides reach Godot, not script arguments, and keep logs separate", () => {
  for (const renderer of ["mobile", "forward_plus"]) {
    const args = renderedTestArgs(fixtures[0], [`--renderer=${renderer}`, "--driver=metal"]);
    assert.equal(args[args.indexOf("--rendering-method") + 1], renderer);
    assert.equal(args[args.indexOf("--rendering-driver") + 1], "metal");
    assert.ok(!args.includes("--"));
    assert.ok(args[args.indexOf("--log-file") + 1].includes(`${renderer}-metal`));
  }
  assert.deepEqual(renderOptions(["--renderer=gl_compatibility", "--driver=opengl3"]), { renderer: "gl_compatibility", driver: "opengl3" });
});

test("invalid, incompatible, ambiguous, and unknown arguments fail before launch", () => {
  for (const options of [
    ["--driver=metal"], ["--renderer=moblie"], ["--renderer", "mobile"],
    ["--renderer=mobile", "--renderer=forward_plus"], ["--headless"],
    ["--renderer=mobile", "--driver=opengl3"],
    ["--renderer=gl_compatibility", "--driver=metal"],
    ["--renderer=mobile", "--driver=metal", "--driver=vulkan"],
  ]) assert.throws(() => renderOptions(options));
  assert.throws(() => renderedTestArgs("../unintended"), /Unknown rendered fixture/);
});
