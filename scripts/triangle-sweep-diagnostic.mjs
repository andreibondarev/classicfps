import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const sub = (a, b) => a.map((v, i) => v - b[i]);
const dot = (a, b) => a.reduce((sum, v, i) => sum + v * b[i], 0);
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const basis = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];

// Independent double-precision geometry diagnostic, NOT a GoldSrc/BSP oracle.
// On each separating axis the translated box overlaps the triangle during an
// interval of t. Intersect all 13 intervals to obtain continuous contact time.
// This returns two-sided geometric intersections, without a physics engine's
// initial-overlap policy, solver tolerance, shape margin, or contact recovery.
export function triangleSweepInterval(origin, motion, halfSize, triangle) {
  if ([origin, motion, halfSize, ...triangle].some(v => v.length !== 3 || v.some(n => !Number.isFinite(n)))
      || halfSize.some(v => v < 0) || triangle.length !== 3) throw new Error("Invalid swept-box geometry");
  const edges = triangle.map((v, i) => sub(triangle[(i + 1) % 3], v));
  // Godot's clockwise face convention.
  const normal = cross(sub(triangle[0], triangle[2]), sub(triangle[0], triangle[1]));
  if (dot(normal, normal) < 1e-24) return null;
  let enter = -Infinity, leave = Infinity;
  for (const candidate of [...basis, normal, ...edges.flatMap(edge => basis.map(axis => cross(edge, axis)))]) {
    const length = Math.hypot(...candidate);
    if (length < 1e-12) continue;
    const axis = candidate.map(v => v / length);
    const points = triangle.map(v => dot(sub(v, origin), axis));
    const radius = dot(halfSize, axis.map(Math.abs));
    const low = Math.min(...points) - radius, high = Math.max(...points) + radius;
    const speed = dot(motion, axis);
    if (Math.abs(speed) < 1e-12) {
      if (low > 1e-12 || high < -1e-12) return null;
      continue;
    }
    enter = Math.max(enter, Math.min(low / speed, high / speed));
    leave = Math.min(leave, Math.max(low / speed, high / speed));
    if (enter > leave + 1e-12) return null;
  }
  if (leave < 0 || enter > 1) return null;
  return { enter, leave, initialOverlap: enter <= 0 && leave >= 0,
    normalDotMotion: dot(normal, motion) / Math.hypot(...normal) };
}

export function analyzeReport(report) {
  return report.queries.map(query => {
    const hits = [];
    for (const body of report.geometry) {
      for (let offset = 0; offset < body.vertices.length; offset += 3) {
        const triangle = body.vertices.slice(offset, offset + 3);
        const interval = triangleSweepInterval(query.origin, query.motion, query.half_size, triangle);
        if (interval) hits.push({ model: body.model, face: offset / 3, ...interval,
          frontFacing: body.backface_collision || interval.normalDotMotion < 0 });
      }
    }
    hits.sort((a, b) => a.enter - b.enter);
    return { index: query.index, engineFractions: query.fractions, engineInitialModels: query.initial_models,
      geometricInitialHits: hits.filter(h => h.initialOverlap),
      firstNewHits: hits.filter(h => !h.initialOverlap).slice(0, 8),
      firstFrontFacingNewHits: hits.filter(h => !h.initialOverlap && h.frontFacing).slice(0, 8) };
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  for (const path of process.argv.slice(2)) {
    const report = JSON.parse(readFileSync(path, "utf8"));
    console.log(JSON.stringify({ path, map: report.map, physics: report.physics_space_class, queries: analyzeReport(report) }));
  }
}
