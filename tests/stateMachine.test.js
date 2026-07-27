import assert from "node:assert/strict";
import { test } from "node:test";
import { PetStateMachine } from "../renderer/stateMachine.js";

const behavior = {
  actions: {
    idle: { frames: ["idle"], loop: true },
    roll: { frames: ["roll"] },
    knead: { frames: ["knead"] },
    "prepare-roll": { frames: ["idle", "roll"] },
    "prepare-knead": { frames: ["idle", "knead"] },
    sleep: { frames: ["closed"], loop: true },
    wake: { frames: ["closed", "half", "open"] },
    "ear-twitch": { frames: ["ear"] },
  },
  events: {
    petOrHover: { random: ["roll", "knead"], weights: [0.5, 0.5] },
    idle: {
      microActions: [],
      specialActions: [{ action: "ear-twitch", weight: 1 }],
    },
  },
};
const config = {
  triggerCooldownMs: 2000,
  idlePauseRangeMs: [4000, 8000],
  idle: {
    basicActionIntervalMs: [4000, 8000],
    specialAfterMs: 30000,
    sleepAfterMs: 180000,
  },
};

test("pet actions always pass through independent preparation frames", () => {
  let now = 0;
  const played = [];
  const fsm = new PetStateMachine({
    behavior,
    config,
    play: (name, time) => played.push([name, time]),
    now: () => now,
    random: () => 0,
  });
  fsm.start();
  fsm.requestPetAction(now);
  assert.equal(fsm.state, "transition");
  assert.equal(fsm.currentAction, "prepare-roll");
  now = 120;
  fsm.actionComplete("prepare-roll", now);
  assert.equal(fsm.currentAction, "roll");
  assert.deepEqual(played.map(([name]) => name), ["idle", "prepare-roll", "roll"]);
});

test("three-stage idle enters special at 30s and sleep at 3min", () => {
  let now = 0;
  const played = [];
  const fsm = new PetStateMachine({
    behavior,
    config,
    play: (name) => played.push(name),
    now: () => now,
    random: () => 0,
  });
  fsm.start();
  now = 30000;
  fsm.tick(now);
  assert.equal(fsm.currentAction, "ear-twitch");
  fsm.actionComplete("ear-twitch", now + 100);
  now = 180000;
  fsm.tick(now);
  assert.equal(fsm.state, "sleep");
  assert.equal(fsm.currentAction, "sleep");
});

test("touching a sleeping pet wakes before the queued interaction", () => {
  let now = 180000;
  const played = [];
  const fsm = new PetStateMachine({
    behavior,
    config,
    play: (name) => played.push(name),
    now: () => now,
    random: () => 0,
  });
  fsm.lastActivityAt = 0;
  fsm.state = "sleep";
  fsm.currentAction = "sleep";
  fsm.requestPetAction(now);
  assert.equal(fsm.currentAction, "wake");
  now += 540;
  fsm.actionComplete("wake", now);
  assert.equal(fsm.currentAction, "prepare-roll");
  assert.deepEqual(played, ["wake", "prepare-roll"]);
});
