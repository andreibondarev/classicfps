import test from "node:test";
import assert from "node:assert/strict";
import { triangleSweepInterval } from "./triangle-sweep-diagnostic.mjs";

const face = [[-10, -10, 0], [0, 10, 0], [10, -10, 0]];
const near = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-10, `${actual} != ${expected}`);

test("continuous box-plane crossing returns analytic entry and exit", () => {
  const hit = triangleSweepInterval([0, 0, 2], [0, 0, -4], [0.5, 0.5, 0.5], face);
  near(hit.enter, 0.375);
  near(hit.leave, 0.625);
  assert.equal(hit.initialOverlap, false);
  assert.ok(hit.normalDotMotion < 0);
});

test("finite triangle edges reject a plane crossing outside the triangle", () => {
  const triangle = [[-1, -1, 0], [0, 1, 0], [1, -1, 0]];
  assert.equal(triangleSweepInterval([0.9, 0.9, 2], [0, 0, -4], [0.05, 0.05, 0.05], triangle), null);
  assert.ok(triangleSweepInterval([0, 0, 2], [0, 0, -4], [0.05, 0.05, 0.05], triangle));
});

test("stationary overlaps, tangencies, moving away, and distant contacts", () => {
  assert.equal(triangleSweepInterval([0, 0, 0], [0, 0, 0], [0.5, 0.5, 0.5], face).initialOverlap, true);
  assert.equal(triangleSweepInterval([0, 0, 0.5], [1, 0, 0], [0.5, 0.5, 0.5], face).initialOverlap, true);
  assert.equal(triangleSweepInterval([0, 0, 0.5001], [1, 0, 0], [0.5, 0.5, 0.5], face), null);
  assert.equal(triangleSweepInterval([0, 0, 2], [0, 0, 4], [0.5, 0.5, 0.5], face), null);
  assert.equal(triangleSweepInterval([0, 0, 2], [0, 0, -1], [0.5, 0.5, 0.5], face), null);
});

test("translation, scaling, and winding preserve two-sided intersection", () => {
  const offset = [31, -12, 5];
  const transform = v => v.map((n, i) => n * 7 + offset[i]);
  const hit = triangleSweepInterval(transform([0, 0, 2]), [0, 0, -28], [3.5, 3.5, 3.5], face.map(transform).reverse());
  near(hit.enter, 0.375);
  near(hit.leave, 0.625);
  assert.ok(hit.normalDotMotion > 0);
});

test("sloped plane has an analytically known support radius", () => {
  const triangle = [[-10, -10, 10], [0, 10, 0], [10, -10, -10]];
  const hit = triangleSweepInterval([0, 0, 2], [0, 0, -4], [0.5, 0.5, 0.5], triangle);
  near(hit.enter, 0.25);
  near(hit.leave, 0.75);
});

test("invalid and degenerate geometry is not treated as a successful cast", () => {
  assert.throws(() => triangleSweepInterval([NaN, 0, 0], [0, 0, 1], [1, 1, 1], face));
  assert.equal(triangleSweepInterval([0, 0, 2], [0, 0, -4], [0.5, 0.5, 0.5], [[0, 0, 0], [1, 0, 0], [2, 0, 0]]), null);
});
