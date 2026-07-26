import fs from "node:fs";

const [firstPath, secondPath] = process.argv.slice(2);
if (!firstPath || !secondPath) {
  throw new Error("usage: compare-bot-determinism.mjs first.json second.json");
}
const first = JSON.parse(fs.readFileSync(firstPath, "utf8"));
const second = JSON.parse(fs.readFileSync(secondPath, "utf8"));
if (first.quantum_hu !== 1 / 64 || second.quantum_hu !== 1 / 64) {
  throw new Error("bot physical signatures must use the 1/64 HU quantum");
}
if (first.checkpoints.length !== second.checkpoints.length) {
  throw new Error("bot signature checkpoint counts differ");
}

let maximumQuantumDrift = 0;
for (let index = 0; index < first.checkpoints.length; index += 1) {
  const left = first.checkpoints[index];
  const right = second.checkpoints[index];
  if (left.tick !== right.tick || left.tick !== (index + 1) * 100) {
    throw new Error(`invalid 100-tick checkpoint at index ${index}`);
  }
  if (left.logical_sha256 !== right.logical_sha256) {
    throw new Error(`per-tick logical signature diverged by tick ${left.tick}`);
  }
  if (left.physical.length !== right.physical.length) {
    throw new Error(`physical actor counts differ at tick ${left.tick}`);
  }
  for (let actorIndex = 0; actorIndex < left.physical.length; actorIndex += 1) {
    const leftActor = left.physical[actorIndex];
    const rightActor = right.physical[actorIndex];
    if (leftActor.id !== rightActor.id) {
      throw new Error(`sorted actor IDs differ at tick ${left.tick}`);
    }
    for (let axis = 0; axis < 3; axis += 1) {
      maximumQuantumDrift = Math.max(
        maximumQuantumDrift,
        Math.abs(
          leftActor.position_q64_hu[axis] - rightActor.position_q64_hu[axis],
        ),
      );
    }
  }
}

// Godot/Jolt contact resolution can vary below one thousandth of a world unit
// with a different render schedule. Three 1/64-HU quanta is 0.046875 HU:
// microscopic, far below GoldSrc's network coordinate precision, and strict
// enough to reject the former 28–195 HU asynchronous-navigation divergence.
if (maximumQuantumDrift > 3) {
  throw new Error(
    `100-tick physical signature drifted ${maximumQuantumDrift}/64 HU`,
  );
}
console.log(
  `GAME_BOT_DETERMINISM_TEST_PASS logical=exact physical_max=${maximumQuantumDrift}/64HU`,
);
