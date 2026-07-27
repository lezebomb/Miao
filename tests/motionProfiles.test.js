import assert from "node:assert/strict";
import { test } from "node:test";
import { readFile } from "node:fs/promises";
import { sampleMotionTransform } from "../renderer/motionProfiles.js";

const behavior = JSON.parse(
  await readFile(new URL("../pet/miaomiao/behavior.json", import.meta.url), "utf8"),
);

test("knead contact frames squish and lifted frames stretch", () => {
  const action = behavior.actions.knead;
  const pressed = sampleMotionTransform("knead", action, 3, 0, 0);
  const lifted = sampleMotionTransform("knead", action, 1, 0, 0);
  assert.equal(pressed.scaleX, 1.04);
  assert.equal(pressed.scaleY, 0.96);
  assert.equal(lifted.scaleX, 0.98);
  assert.equal(lifted.scaleY, 1.02);
  assert.ok(Math.abs(pressed.rotation) <= 1.5);
  assert.ok(Math.abs(lifted.rotation) <= 1.5);
});

test("roll includes a damped overshoot and bounce", () => {
  const action = behavior.actions.roll;
  const overshoot = sampleMotionTransform("roll", action, 14, 0, 0);
  const bounce = sampleMotionTransform("roll", action, 15, 0, 0);
  const settle = sampleMotionTransform("roll", action, 16, 0, 0);
  assert.ok(overshoot.y < 0);
  assert.ok(bounce.y > 0);
  assert.ok(Math.abs(settle.y) < Math.abs(bounce.y));
});

test("idle and sleep breathing stay within subtle pixel bounds", () => {
  for (const name of ["idle", "sleep"]) {
    const action = behavior.actions[name];
    for (let time = 0; time <= 7000; time += 100) {
      const transform = sampleMotionTransform(name, action, 0, 0, time);
      assert.ok(Math.abs(transform.y) <= 1.3);
      assert.ok(Math.abs(transform.scaleX - 1) <= 0.007);
    }
  }
});
