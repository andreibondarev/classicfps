// WASM module interface
import init, { parse_demo, parse_bsp, parse_bsp_textured, parse_mdl, parse_mdl_attached, get_state_at_time } from '../crate/pkg/cs16_demo_parser.js';

let wasmInitialized = false;

export async function initWasm(): Promise<void> {
  if (!wasmInitialized) {
    await init();
    wasmInitialized = true;
  }
}

export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

export interface PlayerState {
  origin: Vec3;
  angles: Vec3;
  velocity?: Vec3;
  name: string;
  gait?: number;
  sequence?: number;
  frame?: number;
  effects?: number;
  ducking?: boolean;
  weapon?: number;
  health?: number;
}

export interface HudWeaponDef {
  id: number;
  ammo_id: number;
  name: string;
}

export interface TimelineEntry {
  time: number;
  players: PlayerState[];
}

export interface GameEventData {
  killer?: string;
  victim?: string;
  weapon?: string;
  headshot: boolean;
  message?: string;
  winner?: string;
  team?: string;
  score?: number;
  round_time?: number;
  player?: string;
  model?: string;
}

export interface PovSample {
  time: number;
  origin: Vec3;
  angles: Vec3;
}

export interface GameEvent {
  time: number;
  event_type: string;
  data: GameEventData;
}

export interface Timeline {
  entries: TimelineEntry[];
  duration: number;
  events: GameEvent[];
  pov_track?: PovSample[];
}

export interface PlayerInfo {
  index: number;
  name: string;
  team: string;
  model: string;
}

export interface DemoResult {
  map_name: string;
  duration: number;
  timeline: Timeline;
  players: PlayerInfo[];
}

export interface BspEntity {
  classname: string;
  origin?: Vec3;
  properties: [string, string][];
}

export interface ParsedBsp {
  vertices: number[];
  normals: number[];
  colors: number[];
  entities: BspEntity[];
  bounds_min: Vec3;
  bounds_max: Vec3;
}

// Structure-of-arrays timeline: flat typed arrays, one fixed slot per player.
export interface SoaDemo {
  map_name: string;
  duration: number;
  players: PlayerInfo[];
  events: GameEvent[];
  slot_names: string[];
  times: Float32Array;
  positions: Float32Array; // [entry][slot][xyz]
  angles: Float32Array;    // [entry][slot][xyz]
  presence: Uint8Array;    // [entry][slot]
  povTimes: Float32Array;
  povData: Float32Array;   // 6 per sample: origin xyz + angles xyz
  povWeaponBits: Int32Array; // recorder inventory bitmask, one per POV sample
  objTimes: Float32Array;  // non-player objects (grenades, C4): sample times
  objEnts: Uint16Array;
  objKinds: Uint8Array;    // 1=he 2=flash 3=smoke 4=c4 5=backpack
  objPositions: Float32Array; // 3 per sample
  gaits: Uint8Array;       // [entry][slot] gaitsequence
  sequences: Uint8Array;   // [entry][slot] recorded sequence
  frames: Uint8Array;      // [entry][slot] 0..255 animation phase
  effects: Uint32Array;    // [entry][slot] GoldSrc EF_* flags
  ducking: Uint8Array;     // [entry][slot]
  velocities: Float32Array; // [entry][slot][xyz]
  weapons: Uint16Array;    // [entry][slot] weaponmodel index
  healths: Int16Array;     // [entry][slot], -1 when unavailable
  model_names: Array<[number, string]>;
  hud_weapons: HudWeaponDef[];
  shotTimes: Float32Array; // weapon-fire events
  shotSlots: Uint8Array;   // 0-based shooter client slot
  hudTimes: Float32Array;
  hudKinds: Uint8Array;
  hudA: Int32Array;
  hudB: Int32Array;
  observerTimes: Float32Array;
  observerTargets: Uint16Array;
  observerModes: Uint8Array;
  weaponAnimTimes: Float32Array;
  weaponAnimSequences: Uint8Array;
  weaponAnimBodies: Uint8Array;
  sounds: DemoSound[];
  network_sounds: NetworkSound[];
  temp_effects: TempEffect[];
  player_stats: PlayerStatsUpdate[];
}

export interface DemoSound {
  time: number;
  sample: string;
  volume: number;
  attenuation: number;
  pitch: number;
}

export interface NetworkSound extends DemoSound {
  origin: Vec3;
  entity: number;
  channel: number;
}

export interface TempEffect {
  time: number;
  kind: number;
  origin: Vec3;
  end: Vec3;
  color: number;
  scale: number;
}

export interface PlayerStatsUpdate {
  time: number;
  slot: number;
  frags?: number | null;
  deaths?: number | null;
  team?: string | null;
  flags?: number | null;
}

export type InterpolationMode = 'authentic' | 'cinematic';

// Parse in a Web Worker so the main thread stays responsive; reports progress 0..1.
export function parseDemoWithProgress(
  data: ArrayBuffer,
  onProgress: (fraction: number) => void
): Promise<SoaDemo> {
  return new Promise((resolve, reject) => {
    const worker = new Worker(new URL('./parseWorker.ts', import.meta.url), { type: 'module' });
    worker.onmessage = (e: MessageEvent) => {
      const msg = e.data;
      if (msg.type === 'progress') {
        onProgress(msg.value);
      } else if (msg.type === 'done') {
        worker.terminate();
        const result = msg.result as SoaDemo;
        if (!result || !result.times || !result.slot_names?.length) {
          reject(new Error('Demo parsing returned invalid data'));
        } else {
          resolve(result);
        }
      } else if (msg.type === 'error') {
        worker.terminate();
        reject(new Error(msg.error));
      }
    };
    worker.onerror = (e) => {
      worker.terminate();
      reject(new Error(e.message || 'Demo parse worker failed'));
    };
    worker.postMessage(data, [data]); // transfer, no copy
  });
}

/// Interpolated player states at `time` from the SoA track.
export function interpolateSoa(
  demo: SoaDemo,
  time: number,
  mode: InterpolationMode = 'authentic',
): PlayerState[] {
  const n = demo.times.length;
  if (n === 0) return [];
  const nSlots = demo.slot_names.length;

  // Binary search: last entry with time <= t
  let lo = 0, hi = n - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (demo.times[mid] <= time) lo = mid;
    else hi = mid - 1;
  }
  const j = Math.min(lo + 1, n - 1);
  const t0 = demo.times[lo];
  const t1 = demo.times[j];
  const f = j > lo && t1 > t0 ? Math.min(1, Math.max(0, (time - t0) / (t1 - t0))) : 0;

  const out: PlayerState[] = [];
  for (let s = 0; s < nSlots; s++) {
    if (!demo.presence[lo * nSlots + s]) continue;
    const a = (lo * nSlots + s) * 3;
    const b = (j * nSlots + s) * 3;
    const both = f > 0 && demo.presence[j * nSlots + s];
    const dt = t1 - t0;
    const distance = both ? Math.hypot(
      demo.positions[b] - demo.positions[a],
      demo.positions[b + 1] - demo.positions[a + 1],
      demo.positions[b + 2] - demo.positions[a + 2],
    ) : 0;
    // A server correction, respawn, or round transition must never become a
    // high-speed glide across the map.
    const teleport = distance > 256 || dt > 0.5;
    const positionAt = (axis: number) => {
      const x = demo.positions[a + axis];
      const y = demo.positions[b + axis];
      if (!both || teleport) return f >= 1 ? y : x;
      if (mode !== 'cinematic' || !demo.velocities || dt <= 0) {
        return x + (y - x) * f;
      }
      const m0 = demo.velocities[a + axis] * dt;
      const m1 = demo.velocities[b + axis] * dt;
      const f2 = f * f;
      const f3 = f2 * f;
      const value = (2 * f3 - 3 * f2 + 1) * x
        + (f3 - 2 * f2 + f) * m0
        + (-2 * f3 + 3 * f2) * y
        + (f3 - f2) * m1;
      // Bad velocity samples should not pull a player outside the segment by
      // more than a small foot-placement margin.
      return Math.max(Math.min(x, y) - 24, Math.min(Math.max(x, y) + 24, value));
    };
    const lerpAng = (x: number, y: number) => {
      if (!both) return x;
      const d = ((y - x) % 360 + 540) % 360 - 180;
      return x + d * f;
    };
    out.push({
      gait: demo.gaits ? demo.gaits[lo * nSlots + s] : 0,
      sequence: demo.sequences ? demo.sequences[lo * nSlots + s] : 0,
      frame: demo.frames ? demo.frames[lo * nSlots + s] : 0,
      effects: demo.effects ? demo.effects[lo * nSlots + s] : 0,
      ducking: !!demo.ducking?.[lo * nSlots + s],
      weapon: demo.weapons ? demo.weapons[lo * nSlots + s] : 0,
      health: demo.healths ? demo.healths[lo * nSlots + s] : -1,
      name: demo.slot_names[s],
      velocity: {
        x: demo.velocities && both
          ? demo.velocities[a] + (demo.velocities[b] - demo.velocities[a]) * f
          : demo.velocities?.[a] ?? 0,
        y: demo.velocities && both
          ? demo.velocities[a + 1] + (demo.velocities[b + 1] - demo.velocities[a + 1]) * f
          : demo.velocities?.[a + 1] ?? 0,
        z: demo.velocities && both
          ? demo.velocities[a + 2] + (demo.velocities[b + 2] - demo.velocities[a + 2]) * f
          : demo.velocities?.[a + 2] ?? 0,
      },
      origin: {
        x: positionAt(0),
        y: positionAt(1),
        z: positionAt(2),
      },
      angles: {
        x: lerpAng(demo.angles[a], demo.angles[b]),
        y: lerpAng(demo.angles[a + 1], demo.angles[b + 1]),
        z: 0,
      },
    });
  }
  return out;
}

export async function parseDemo(data: ArrayBuffer): Promise<DemoResult> {
  await initWasm();
  const result = parse_demo(new Uint8Array(data)) as DemoResult;

  if (!result || !result.timeline || !Array.isArray(result.timeline.entries)) {
    throw new Error('Demo parsing returned invalid data');
  }

  return result;
}

export interface TexturedBspGroup {
  model_index: number;
  name: string;
  width: number;
  height: number;
  vert_start: number;
  vert_count: number;
  pix_offset: number; // -1 = no pixels
}

export interface TexturedBsp {
  groups: TexturedBspGroup[];
  entities: BspEntity[];
  bounds_min: Vec3;
  bounds_max: Vec3;
  positions: Float32Array;
  normals: Float32Array;
  colors: Float32Array;
  uvs: Float32Array;
  pixels: Uint8Array;
}

export async function parseBspTextured(
  data: ArrayBuffer,
  wads: ArrayBuffer[]
): Promise<TexturedBsp> {
  await initWasm();
  const raw = parse_bsp_textured(
    new Uint8Array(data),
    wads.map((w) => new Uint8Array(w))
  ) as {
    meta: string;
    positions: Float32Array;
    normals: Float32Array;
    colors: Float32Array;
    uvs: Float32Array;
    pixels: Uint8Array;
  };
  const meta = JSON.parse(raw.meta);
  return { ...meta, positions: raw.positions, normals: raw.normals, colors: raw.colors, uvs: raw.uvs, pixels: raw.pixels };
}

// (seqLabels come back with every parsed model)
export interface MdlAnim {
  name: string; // 'idle' | 'run' | 'die'
  fps: number;
  frames: number;
  data: Float32Array; // frames * positions.length
}

export interface ParsedMdl {
  groups: TexturedBspGroup[];
  positions: Float32Array;
  uvs: Float32Array;
  pixels: Uint8Array;
  anims: MdlAnim[];
  seqLabels: string[];
}

export async function parseMdl(data: ArrayBuffer): Promise<ParsedMdl> {
  await initWasm();
  const raw = parse_mdl(new Uint8Array(data)) as {
    meta: string;
    positions: Float32Array;
    uvs: Float32Array;
    pixels: Uint8Array;
    animMeta: string;
    animData: Float32Array[];
    seqLabels: string;
  };
  const animMeta = JSON.parse(raw.animMeta ?? '[]') as Array<{ name: string; fps: number; frames: number }>;
  const anims: MdlAnim[] = animMeta.map((a, i) => ({ ...a, data: raw.animData[i] }));
  return { groups: JSON.parse(raw.meta), positions: raw.positions, uvs: raw.uvs, pixels: raw.pixels,
           anims, seqLabels: JSON.parse(raw.seqLabels ?? '[]') };
}

export async function parseMdlAttached(player: ArrayBuffer, weapon: ArrayBuffer): Promise<ParsedMdl> {
  await initWasm();
  const raw = parse_mdl_attached(new Uint8Array(player), new Uint8Array(weapon)) as {
    meta: string;
    positions: Float32Array;
    uvs: Float32Array;
    pixels: Uint8Array;
    animMeta: string;
    animData: Float32Array[];
    seqLabels: string;
  };
  const animMeta = JSON.parse(raw.animMeta ?? '[]') as Array<{ name: string; fps: number; frames: number }>;
  const anims: MdlAnim[] = animMeta.map((a, i) => ({ ...a, data: raw.animData[i] }));
  return { groups: JSON.parse(raw.meta), positions: raw.positions, uvs: raw.uvs, pixels: raw.pixels,
           anims, seqLabels: JSON.parse(raw.seqLabels ?? '[]') };
}

export async function parseBsp(data: ArrayBuffer): Promise<ParsedBsp> {
  await initWasm();
  const result = parse_bsp(new Uint8Array(data));
  return result as ParsedBsp;
}

export function getStateAtTime(timeline: Timeline, time: number): PlayerState[] {
  // Note: This crosses the JS/WASM boundary, which has some overhead.
  // For better performance, we do the interpolation in JS and only use
  // WASM for parsing. But this function is here if needed.
  const result = get_state_at_time(timeline, time);
  return result as PlayerState[];
}

// JS-side interpolation (faster than crossing WASM boundary every frame)
export function interpolateState(timeline: Timeline, time: number): PlayerState[] {
  if (!timeline?.entries || timeline.entries.length === 0) {
    return [];
  }

  // Handle single entry case
  if (timeline.entries.length === 1) {
    return timeline.entries[0].players || [];
  }

  // Binary search
  let left = 0;
  let right = timeline.entries.length - 1;

  while (left < right) {
    const mid = Math.floor((left + right + 1) / 2);
    if (timeline.entries[mid].time <= time) {
      left = mid;
    } else {
      right = mid - 1;
    }
  }

  const prev = timeline.entries[left];
  const next = timeline.entries[left + 1];

  if (!prev?.players) {
    return [];
  }

  if (!next || next.time <= prev.time) {
    return prev.players;
  }

  // Interpolate
  const t = (time - prev.time) / (next.time - prev.time);

  // Guard against invalid interpolation factor
  if (!Number.isFinite(t) || t < 0 || t > 1) {
    return prev.players;
  }

  // Match players by name, not array index — the player set can differ
  // between samples (deaths, spawns, entity dropouts), and index pairing
  // would interpolate one player toward another's position.
  const nextByName = new Map(next.players.map((p) => [p.name, p]));

  return prev.players.map((p) => {
    const n = nextByName.get(p.name);
    if (!n) return p;

    // Safe lerp helper that handles NaN/Infinity
    const safeLerp = (a: number, b: number) => {
      if (!Number.isFinite(a)) return Number.isFinite(b) ? b : 0;
      if (!Number.isFinite(b)) return a;
      return a + (b - a) * t;
    };

    return {
      origin: {
        x: safeLerp(p.origin.x, n.origin.x),
        y: safeLerp(p.origin.y, n.origin.y),
        z: safeLerp(p.origin.z, n.origin.z),
      },
      angles: {
        x: lerpAngle(p.angles.x, n.angles.x, t),
        y: lerpAngle(p.angles.y, n.angles.y, t),
        z: lerpAngle(p.angles.z, n.angles.z, t),
      },
      name: p.name,
    };
  });
}

function lerpAngle(a: number, b: number, t: number): number {
  // Guard against NaN/Infinity which would cause infinite loops
  if (!Number.isFinite(a) || !Number.isFinite(b) || !Number.isFinite(t)) {
    return Number.isFinite(a) ? a : (Number.isFinite(b) ? b : 0);
  }
  let diff = b - a;
  // Use modulo instead of while loops to avoid infinite loops
  diff = ((diff % 360) + 540) % 360 - 180;
  return a + diff * t;
}
