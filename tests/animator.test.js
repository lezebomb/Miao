import assert from "node:assert/strict";
import { test } from "node:test";
import { Animator } from "../renderer/animator.js";

const behavior = {
  actions: {
    cycle: {
      frames: ["a.png", "b.png"],
      frameDurationsMs: [100, 200],
      repeatCount: 2,
      loop: false,
    },
  },
};

test("Animator honors per-frame delays and repeatCount", () => {
  const completed = [];
  const renderer = {
    preload: async () => {},
    render: async () => {},
  };
  const animator = new Animator({
    renderer,
    behavior,
    assetBaseUrl: "file:///pet/",
    onComplete: (name) => completed.push(name),
  });
  animator.play("cycle", 0);
  animator.update(99);
  assert.deepEqual(animator.snapshot(), { actionName: "cycle", frameIndex: 0, cycle: 0 });
  animator.update(100);
  assert.equal(animator.snapshot().frameIndex, 1);
  animator.update(300);
  assert.deepEqual(animator.snapshot(), { actionName: "cycle", frameIndex: 0, cycle: 1 });
  animator.update(600);
  assert.equal(animator.snapshot(), null);
  assert.deepEqual(completed, ["cycle"]);
});
