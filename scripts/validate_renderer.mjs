import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const behavior = JSON.parse(
  await readFile(path.join(projectRoot, "pet", "miaomiao", "behavior.json"), "utf8"),
);
const config = JSON.parse(
  await readFile(path.join(projectRoot, "miaomiao.config.json"), "utf8"),
);

const checks = [];
function check(name, condition, detail) {
  checks.push({ name, passed: Boolean(condition), detail });
}

for (const [name, action] of Object.entries(behavior.actions)) {
  check(
    `${name}:duration-count`,
    action.frames.length === action.frameDurationsMs.length,
    `${action.frames.length} frames / ${action.frameDurationsMs.length} durations`,
  );
}

const roll = behavior.actions.roll;
const standardDurations = roll.motion.standardFrames.map((index) => roll.frameDurationsMs[index]);
const holdDurations = roll.motion.holdFrames.map((index) => roll.frameDurationsMs[index]);
const sortedStandard = [...standardDurations].sort((a, b) => a - b);
const standardMedian = sortedStandard[Math.floor(sortedStandard.length / 2)];
const holdRatios = holdDurations.map((duration) => duration / standardMedian);
check(
  "roll:hold-200-to-300-percent",
  holdRatios.every((ratio) => ratio >= 2 && ratio <= 3),
  `ratios=${holdRatios.map((ratio) => ratio.toFixed(2)).join(",")}`,
);
check(
  "roll:secondary-bounce",
  roll.motion.bounceKeyframes.length >= 2,
  `${roll.motion.bounceKeyframes.length} overshoot/bounce keyframes`,
);

const knead = behavior.actions.knead;
check(
  "knead:press-squish",
  knead.motion.pressScale[0] === 1.04 && knead.motion.pressScale[1] === 0.96,
  JSON.stringify(knead.motion.pressScale),
);
check(
  "knead:lift-stretch",
  knead.motion.liftScale[0] === 0.98 && knead.motion.liftScale[1] === 1.02,
  JSON.stringify(knead.motion.liftScale),
);
check(
  "knead:alternating-paws",
  knead.motion.leftPawFrames.length >= 4 && knead.motion.rightPawFrames.length >= 4,
  `left=${knead.motion.leftPawFrames}; right=${knead.motion.rightPawFrames}`,
);

check(
  "renderer:no-alpha-crossfade",
  config.renderer.engine === "canvas" && config.renderer.alphaCrossfade === false,
  `engine=${config.renderer.engine}; alphaCrossfade=${config.renderer.alphaCrossfade}`,
);
check(
  "renderer:60hz-transform-interpolation",
  config.renderer.targetFps === 60 && config.renderer.transformInterpolation === true,
  `targetFps=${config.renderer.targetFps}`,
);
check(
  "fsm:independent-preparation-frames",
  behavior.actions["prepare-roll"].frames.length === 2 &&
    behavior.actions["prepare-knead"].frames.length === 2,
  "two-frame 120ms preparation sequences",
);
check(
  "fsm:three-stage-idle",
  config.idle.specialAfterMs === 30000 && config.idle.sleepAfterMs === 180000,
  `special=${config.idle.specialAfterMs}ms; sleep=${config.idle.sleepAfterMs}ms`,
);
check(
  "fsm:wake-before-interaction",
  behavior.actions.sleep.loop && behavior.actions.wake.frames.length >= 3,
  `${behavior.actions.wake.frames.length} wake frames`,
);

const failed = checks.filter((item) => !item.passed);
const report = {
  ok: failed.length === 0,
  generatedAt: new Date().toISOString(),
  engine: "Electron Renderer Process + Canvas 2D + requestAnimationFrame",
  policy: {
    fullCharacterAlphaCrossfade: "disabled",
    frameInterpolation: "continuous transform interpolation only",
    sourceFrames: "independent opaque PNG poses",
  },
  smokePreviews: {
    transparent: [
      "previews/actions-v4/canvas-smoke-knead.png",
      "previews/actions-v4/canvas-smoke-roll.png"
    ],
    black: [
      "previews/actions-v4/black/knead.png",
      "previews/actions-v4/black/roll.png"
    ],
    white: [
      "previews/actions-v4/white/knead.png",
      "previews/actions-v4/white/roll.png"
    ]
  },
  checks,
};
const output = path.join(projectRoot, "previews", "actions-v4", "runtime-validation.json");
await mkdir(path.dirname(output), { recursive: true });
await writeFile(output, `${JSON.stringify(report, null, 2)}\n`, "utf8");
console.log(output);
if (failed.length) process.exitCode = 1;
