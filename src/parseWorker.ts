// Web Worker: parses a demo off the main thread and streams progress back.
// Returns an SoA timeline whose typed arrays are transferred zero-copy.
import init, { parse_demo_soa } from '../crate/pkg/cs16_demo_parser.js';

self.onmessage = async (e: MessageEvent<ArrayBuffer>) => {
  try {
    await init();
    const soa = parse_demo_soa(new Uint8Array(e.data), (fraction: number) => {
      self.postMessage({ type: 'progress', value: fraction });
    }) as {
      meta: string;
      times: Float32Array;
      positions: Float32Array;
      angles: Float32Array;
      presence: Uint8Array;
      povTimes: Float32Array;
      povData: Float32Array;
      povWeaponBits: Int32Array;
      objTimes: Float32Array;
      objEnts: Uint16Array;
      objKinds: Uint8Array;
      objPositions: Float32Array;
      gaits: Uint8Array;
      sequences: Uint8Array;
      frames: Uint8Array;
      effects: Uint32Array;
      ducking: Uint8Array;
      velocities: Float32Array;
      weapons: Uint16Array;
      healths: Int16Array;
      shotTimes: Float32Array;
      shotSlots: Uint8Array;
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
    };
    const meta = JSON.parse(soa.meta);
    self.postMessage(
      {
        type: 'done',
        result: {
          ...meta,
          times: soa.times,
          positions: soa.positions,
          angles: soa.angles,
          presence: soa.presence,
          povTimes: soa.povTimes,
          povData: soa.povData,
          povWeaponBits: soa.povWeaponBits,
          objTimes: soa.objTimes,
          objEnts: soa.objEnts,
          objKinds: soa.objKinds,
          objPositions: soa.objPositions,
          gaits: soa.gaits,
          sequences: soa.sequences,
          frames: soa.frames,
          effects: soa.effects,
          ducking: soa.ducking,
          velocities: soa.velocities,
          weapons: soa.weapons,
          healths: soa.healths,
          shotTimes: soa.shotTimes,
          shotSlots: soa.shotSlots,
          hudTimes: soa.hudTimes,
          hudKinds: soa.hudKinds,
          hudA: soa.hudA,
          hudB: soa.hudB,
          observerTimes: soa.observerTimes,
          observerTargets: soa.observerTargets,
          observerModes: soa.observerModes,
          weaponAnimTimes: soa.weaponAnimTimes,
          weaponAnimSequences: soa.weaponAnimSequences,
          weaponAnimBodies: soa.weaponAnimBodies,
        },
      },
      {
        transfer: [
          soa.times.buffer,
          soa.positions.buffer,
          soa.angles.buffer,
          soa.presence.buffer,
          soa.povTimes.buffer,
          soa.povData.buffer,
          soa.povWeaponBits.buffer,
          soa.objTimes.buffer,
          soa.objEnts.buffer,
          soa.objKinds.buffer,
          soa.objPositions.buffer,
          soa.gaits.buffer,
          soa.sequences.buffer,
          soa.frames.buffer,
          soa.effects.buffer,
          soa.ducking.buffer,
          soa.velocities.buffer,
          soa.weapons.buffer,
          soa.healths.buffer,
          soa.shotTimes.buffer,
          soa.shotSlots.buffer,
          soa.hudTimes.buffer,
          soa.hudKinds.buffer,
          soa.hudA.buffer,
          soa.hudB.buffer,
          soa.observerTimes.buffer,
          soa.observerTargets.buffer,
          soa.observerModes.buffer,
          soa.weaponAnimTimes.buffer,
          soa.weaponAnimSequences.buffer,
          soa.weaponAnimBodies.buffer,
        ],
      }
    );
  } catch (err) {
    self.postMessage({ type: 'error', error: String(err) });
  }
};
