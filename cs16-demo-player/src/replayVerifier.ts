import { interpolateSoa, type PlayerState, type SoaDemo } from './wasm.ts';

export type VerificationStatus = 'pass' | 'warning' | 'fail';

export interface ReplayVerificationIssue {
  severity: 'warning' | 'error';
  code: string;
  message: string;
}

export interface ReplayCheckpoint {
  time: number;
  sampleIndex: number;
  interpolation: number;
  players: number;
  events: number;
  hash: string;
  seekEquivalent: boolean;
}

export interface ReplayVerificationReport {
  status: VerificationStatus;
  checksum: string;
  elapsedMs: number;
  issues: ReplayVerificationIssue[];
  checkpoints: ReplayCheckpoint[];
  stats: {
    samples: number;
    players: number;
    events: number;
    povSamples: number;
    objectSamples: number;
    shots: number;
    weaponAnimations: number;
    sounds: number;
  };
}

export interface SampleWindow {
  index: number;
  nextIndex: number;
  time: number;
  nextTime: number;
  interpolation: number;
}

const CHECKPOINT_COUNT = 9;

export function sampleWindowAt(demo: SoaDemo, time: number): SampleWindow {
  const count = demo.times.length;
  if (count === 0) {
    return { index: -1, nextIndex: -1, time: 0, nextTime: 0, interpolation: 0 };
  }

  let lo = 0;
  let hi = count - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (demo.times[mid] <= time) lo = mid;
    else hi = mid - 1;
  }
  const next = Math.min(lo + 1, count - 1);
  const startTime = demo.times[lo];
  const endTime = demo.times[next];
  const interpolation = next > lo && endTime > startTime
    ? Math.min(1, Math.max(0, (time - startTime) / (endTime - startTime)))
    : 0;

  return {
    index: lo,
    nextIndex: next,
    time: startTime,
    nextTime: endTime,
    interpolation,
  };
}

function linearStateAtTime(demo: SoaDemo, time: number): PlayerState[] {
  const count = demo.times.length;
  if (count === 0) return [];

  let index = 0;
  while (index + 1 < count && demo.times[index + 1] <= time) index++;
  const next = Math.min(index + 1, count - 1);
  const startTime = demo.times[index];
  const endTime = demo.times[next];
  const fraction = next > index && endTime > startTime
    ? Math.min(1, Math.max(0, (time - startTime) / (endTime - startTime)))
    : 0;
  const slots = demo.slot_names.length;
  const states: PlayerState[] = [];

  for (let slot = 0; slot < slots; slot++) {
    if (!demo.presence[index * slots + slot]) continue;
    const a = (index * slots + slot) * 3;
    const b = (next * slots + slot) * 3;
    const interpolate = fraction > 0 && !!demo.presence[next * slots + slot];
    const sampleGap = endTime - startTime;
    const distance = interpolate ? Math.hypot(
      demo.positions[b] - demo.positions[a],
      demo.positions[b + 1] - demo.positions[a + 1],
      demo.positions[b + 2] - demo.positions[a + 2],
    ) : 0;
    const discontinuity = distance > 256 || sampleGap > 0.5;
    const lerp = (from: number, to: number) => interpolate
      ? discontinuity ? (fraction >= 1 ? to : from) : from + (to - from) * fraction
      : from;
    const lerpAngle = (from: number, to: number) => {
      if (!interpolate) return from;
      const delta = ((to - from) % 360 + 540) % 360 - 180;
      return from + delta * fraction;
    };

    states.push({
      name: demo.slot_names[slot],
      gait: demo.gaits ? demo.gaits[index * slots + slot] : 0,
      sequence: demo.sequences ? demo.sequences[index * slots + slot] : 0,
      frame: demo.frames ? demo.frames[index * slots + slot] : 0,
      effects: demo.effects ? demo.effects[index * slots + slot] : 0,
      ducking: !!demo.ducking?.[index * slots + slot],
      weapon: demo.weapons ? demo.weapons[index * slots + slot] : 0,
      health: demo.healths ? demo.healths[index * slots + slot] : -1,
      velocity: {
        x: demo.velocities?.[a] ?? 0,
        y: demo.velocities?.[a + 1] ?? 0,
        z: demo.velocities?.[a + 2] ?? 0,
      },
      origin: {
        x: lerp(demo.positions[a], demo.positions[b]),
        y: lerp(demo.positions[a + 1], demo.positions[b + 1]),
        z: lerp(demo.positions[a + 2], demo.positions[b + 2]),
      },
      angles: {
        x: lerpAngle(demo.angles[a], demo.angles[b]),
        y: lerpAngle(demo.angles[a + 1], demo.angles[b + 1]),
        z: 0,
      },
    });
  }
  return states;
}

function quantize(value: number): string {
  return Number.isFinite(value) ? value.toFixed(4) : String(value);
}

function serializeStates(states: PlayerState[]): string {
  return [...states]
    .sort((a, b) => a.name.localeCompare(b.name))
    .map((state) => [
      state.name,
      quantize(state.origin.x),
      quantize(state.origin.y),
      quantize(state.origin.z),
      quantize(state.angles.x),
      quantize(state.angles.y),
      state.gait ?? 0,
      state.sequence ?? 0,
      state.frame ?? 0,
      state.effects ?? 0,
      state.ducking ? 1 : 0,
      state.weapon ?? 0,
      state.health ?? -1,
    ].join('|'))
    .join('\n');
}

function fnv1a(text: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

function eventsUpTo(demo: SoaDemo, time: number): number {
  let lo = 0;
  let hi = demo.events.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (demo.events[mid].time <= time) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}

function validateOrderedTimes(
  values: ArrayLike<number>,
  label: string,
  issues: ReplayVerificationIssue[],
  maximum?: number,
): void {
  let previous = -Infinity;
  for (let i = 0; i < values.length; i++) {
    const value = values[i];
    if (!Number.isFinite(value)) {
      issues.push({ severity: 'error', code: `${label}_non_finite`, message: `${label} ${i} has an invalid time.` });
      return;
    }
    if (value < previous) {
      issues.push({ severity: 'error', code: `${label}_unordered`, message: `${label} times go backwards at index ${i}.` });
      return;
    }
    if (maximum !== undefined && value > maximum + 1) {
      issues.push({ severity: 'warning', code: `${label}_past_duration`, message: `${label} ${i} is beyond the declared duration.` });
      return;
    }
    previous = value;
  }
}

function addLengthIssue(
  issues: ReplayVerificationIssue[],
  label: string,
  actual: number,
  expected: number,
): void {
  if (actual !== expected) {
    issues.push({
      severity: 'error',
      code: `${label}_length`,
      message: `${label} has ${actual.toLocaleString()} values; expected ${expected.toLocaleString()}.`,
    });
  }
}

function checkpointTimes(demo: SoaDemo): number[] {
  const duration = Math.max(0, demo.duration);
  const candidates = Array.from(
    { length: CHECKPOINT_COUNT },
    (_, index) => duration * index / (CHECKPOINT_COUNT - 1),
  );
  for (const event of demo.events) {
    if (['Kill', 'RoundStart', 'RoundEnd', 'BombPlanted'].includes(event.event_type)) {
      candidates.push(Math.max(0, Math.min(duration, event.time)));
      if (candidates.length >= CHECKPOINT_COUNT + 4) break;
    }
  }
  return [...new Set(candidates.map((time) => Math.round(time * 1000) / 1000))]
    .sort((a, b) => a - b);
}

export function verifyReplay(demo: SoaDemo): ReplayVerificationReport {
  const started = performance.now();
  const issues: ReplayVerificationIssue[] = [];
  const samples = demo.times.length;
  const slots = demo.slot_names.length;
  const cells = samples * slots;

  if (!Number.isFinite(demo.duration) || demo.duration <= 0) {
    issues.push({ severity: 'error', code: 'invalid_duration', message: 'The demo duration is missing or invalid.' });
  }
  if (samples === 0) {
    issues.push({ severity: 'error', code: 'empty_timeline', message: 'The parsed demo contains no timeline samples.' });
  }
  if (slots === 0) {
    issues.push({ severity: 'error', code: 'empty_roster', message: 'The parsed demo contains no player slots.' });
  }
  if (new Set(demo.slot_names).size !== slots) {
    issues.push({ severity: 'error', code: 'duplicate_slots', message: 'The timeline contains duplicate player slot names.' });
  }

  addLengthIssue(issues, 'positions', demo.positions.length, cells * 3);
  addLengthIssue(issues, 'angles', demo.angles.length, cells * 3);
  addLengthIssue(issues, 'presence', demo.presence.length, cells);
  addLengthIssue(issues, 'gaits', demo.gaits.length, cells);
  addLengthIssue(issues, 'sequences', demo.sequences.length, cells);
  addLengthIssue(issues, 'frames', demo.frames.length, cells);
  addLengthIssue(issues, 'effects', demo.effects.length, cells);
  addLengthIssue(issues, 'ducking', demo.ducking.length, cells);
  addLengthIssue(issues, 'velocities', demo.velocities.length, cells * 3);
  addLengthIssue(issues, 'weapons', demo.weapons.length, cells);
  addLengthIssue(issues, 'healths', demo.healths.length, cells);
  addLengthIssue(issues, 'pov_data', demo.povData.length, demo.povTimes.length * 6);
  addLengthIssue(issues, 'pov_weapon_bits', demo.povWeaponBits.length, demo.povTimes.length);
  addLengthIssue(issues, 'object_entities', demo.objEnts.length, demo.objTimes.length);
  addLengthIssue(issues, 'object_kinds', demo.objKinds.length, demo.objTimes.length);
  addLengthIssue(issues, 'object_positions', demo.objPositions.length, demo.objTimes.length * 3);
  addLengthIssue(issues, 'shot_slots', demo.shotSlots.length, demo.shotTimes.length);
  addLengthIssue(issues, 'hud_kinds', demo.hudKinds.length, demo.hudTimes.length);
  addLengthIssue(issues, 'hud_a', demo.hudA.length, demo.hudTimes.length);
  addLengthIssue(issues, 'hud_b', demo.hudB.length, demo.hudTimes.length);
  addLengthIssue(issues, 'observer_targets', demo.observerTargets.length, demo.observerTimes.length);
  addLengthIssue(issues, 'observer_modes', demo.observerModes.length, demo.observerTimes.length);
  addLengthIssue(issues, 'weapon_anim_sequences', demo.weaponAnimSequences.length, demo.weaponAnimTimes.length);
  addLengthIssue(issues, 'weapon_anim_bodies', demo.weaponAnimBodies.length, demo.weaponAnimTimes.length);

  validateOrderedTimes(demo.times, 'timeline', issues, demo.duration);
  validateOrderedTimes(demo.povTimes, 'pov', issues, demo.duration);
  validateOrderedTimes(demo.objTimes, 'object', issues, demo.duration);
  validateOrderedTimes(demo.shotTimes, 'shot', issues, demo.duration);
  validateOrderedTimes(demo.hudTimes, 'hud', issues, demo.duration);
  validateOrderedTimes(demo.observerTimes, 'observer', issues, demo.duration);
  validateOrderedTimes(demo.weaponAnimTimes, 'weapon animation', issues, demo.duration);
  validateOrderedTimes(demo.sounds.map((sound) => sound.time), 'recorded sound', issues, demo.duration);
  validateOrderedTimes(demo.network_sounds.map((sound) => sound.time), 'network sound', issues, demo.duration);
  validateOrderedTimes(demo.temp_effects.map((effect) => effect.time), 'temporary effect', issues, demo.duration);
  validateOrderedTimes(demo.events.map((event) => event.time), 'event', issues, demo.duration);

  if (demo.positions.length === cells * 3 && demo.angles.length === cells * 3) {
    for (let cell = 0; cell < cells; cell++) {
      if (!demo.presence[cell]) continue;
      const offset = cell * 3;
      const values = [
        demo.positions[offset], demo.positions[offset + 1], demo.positions[offset + 2],
        demo.angles[offset], demo.angles[offset + 1], demo.angles[offset + 2],
      ];
      if (values.some((value) => !Number.isFinite(value))) {
        issues.push({
          severity: 'error',
          code: 'invalid_entity_state',
          message: `Player state ${cell.toLocaleString()} contains a non-finite position or angle.`,
        });
        break;
      }
    }
  }

  const checkpoints: ReplayCheckpoint[] = checkpointTimes(demo).map((time) => {
    const direct = interpolateSoa(demo, time);
    const linear = linearStateAtTime(demo, time);
    const directState = serializeStates(direct);
    const linearState = serializeStates(linear);
    const window = sampleWindowAt(demo, time);
    return {
      time,
      sampleIndex: window.index,
      interpolation: window.interpolation,
      players: direct.length,
      events: eventsUpTo(demo, time),
      hash: fnv1a(`${quantize(time)}\n${directState}`),
      seekEquivalent: directState === linearState,
    };
  });

  const mismatch = checkpoints.find((checkpoint) => !checkpoint.seekEquivalent);
  if (mismatch) {
    issues.push({
      severity: 'error',
      code: 'seek_mismatch',
      message: `Direct seeking disagrees with linear playback at ${mismatch.time.toFixed(3)}s.`,
    });
  }

  // Run the direct sampler twice so accidental hidden state is detected.
  const unstable = checkpoints.find((checkpoint) => {
    const repeated = fnv1a(`${quantize(checkpoint.time)}\n${serializeStates(interpolateSoa(demo, checkpoint.time))}`);
    return repeated !== checkpoint.hash;
  });
  if (unstable) {
    issues.push({
      severity: 'error',
      code: 'non_deterministic',
      message: `Repeated sampling produced different state at ${unstable.time.toFixed(3)}s.`,
    });
  }

  if (!issues.length && demo.events.length === 0) {
    issues.push({ severity: 'warning', code: 'no_events', message: 'No game events were extracted from this demo.' });
  }

  const status: VerificationStatus = issues.some((issue) => issue.severity === 'error')
    ? 'fail'
    : issues.length
      ? 'warning'
      : 'pass';
  const checksum = fnv1a([
    demo.map_name,
    quantize(demo.duration),
    samples,
    slots,
    demo.events.length,
    ...checkpoints.map((checkpoint) => checkpoint.hash),
  ].join('|'));

  return {
    status,
    checksum,
    elapsedMs: performance.now() - started,
    issues,
    checkpoints,
    stats: {
      samples,
      players: slots,
      events: demo.events.length,
      povSamples: demo.povTimes.length,
      objectSamples: demo.objTimes.length,
      shots: demo.shotTimes.length,
      weaponAnimations: demo.weaponAnimTimes.length,
      sounds: demo.sounds.length + demo.network_sounds.length,
    },
  };
}
