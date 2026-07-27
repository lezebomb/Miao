const TAU = Math.PI * 2;

export const IDENTITY_TRANSFORM = Object.freeze({
  x: 0,
  y: 0,
  rotation: 0,
  scaleX: 1,
  scaleY: 1,
});

export function clamp01(value) {
  return Math.max(0, Math.min(1, value));
}

export function smoothstep(value) {
  const t = clamp01(value);
  return t * t * (3 - 2 * t);
}

export function lerp(first, second, amount) {
  return first + (second - first) * amount;
}

function pressureAt(action, frameIndex) {
  const motion = action.motion ?? {};
  if ((motion.contactFrames ?? []).includes(frameIndex)) return 1;
  if ((motion.liftFrames ?? []).includes(frameIndex)) return -1;
  return 0;
}

function kneadSideAt(action, frameIndex) {
  const motion = action.motion ?? {};
  if ((motion.leftPawFrames ?? []).includes(frameIndex)) return -1;
  if ((motion.rightPawFrames ?? []).includes(frameIndex)) return 1;
  return 0;
}

function rollPoseAt(action, frameIndex) {
  const keyframe = (action.motion?.bounceKeyframes ?? []).find(
    (entry) => entry.frame === frameIndex,
  );
  return {
    ...IDENTITY_TRANSFORM,
    x: Number(keyframe?.x ?? 0),
    y: Number(keyframe?.y ?? 0),
    rotation: Number(keyframe?.rotation ?? 0),
    scaleX: Number(keyframe?.scaleX ?? 1),
    scaleY: Number(keyframe?.scaleY ?? 1),
  };
}

function interpolateTransform(first, second, progress) {
  const amount = smoothstep(progress);
  return {
    x: lerp(first.x, second.x, amount),
    y: lerp(first.y, second.y, amount),
    rotation: lerp(first.rotation, second.rotation, amount),
    scaleX: lerp(first.scaleX, second.scaleX, amount),
    scaleY: lerp(first.scaleY, second.scaleY, amount),
  };
}

export function sampleMotionTransform(actionName, action, frameIndex, progress, nowMs) {
  const count = action.frames.length;
  const nextIndex = Math.min(count - 1, frameIndex + 1);

  if (actionName === "knead") {
    const pressure = lerp(
      pressureAt(action, frameIndex),
      pressureAt(action, nextIndex),
      smoothstep(progress),
    );
    const side = lerp(
      kneadSideAt(action, frameIndex),
      kneadSideAt(action, nextIndex),
      smoothstep(progress),
    );
    const phase = ((frameIndex + progress) / count) * TAU;
    const pressureDown = Math.max(0, pressure);
    const pawLift = Math.max(0, -pressure);
    return {
      x: 0,
      y: 1.5 + Math.sin(phase - Math.PI / 2) * 1.5 + pressureDown * 0.75,
      rotation: side * 1.35,
      scaleX: 1 + pressureDown * 0.04 - pawLift * 0.02,
      scaleY: 1 - pressureDown * 0.04 + pawLift * 0.02,
    };
  }

  if (actionName === "roll") {
    return interpolateTransform(
      rollPoseAt(action, frameIndex),
      rollPoseAt(action, nextIndex),
      progress,
    );
  }

  if (actionName === "idle" || actionName === "sleep") {
    const period = actionName === "sleep" ? 6200 : 3800;
    const amplitude = actionName === "sleep" ? 1.2 : 0.8;
    const breath = Math.sin((nowMs / period) * TAU);
    return {
      x: 0,
      y: breath * amplitude,
      rotation: 0,
      scaleX: 1 + breath * 0.006,
      scaleY: 1 - breath * 0.006,
    };
  }

  if (actionName.startsWith("running-")) {
    const phase = ((frameIndex + progress) / count) * TAU;
    return {
      ...IDENTITY_TRANSFORM,
      y: Math.sin(phase * 2) * 1.25,
      rotation: Math.sin(phase) * 0.55,
    };
  }

  if (actionName.startsWith("prepare-") || actionName === "wake") {
    const settle = Math.sin(smoothstep(progress) * Math.PI);
    return {
      ...IDENTITY_TRANSFORM,
      y: settle * 1.5,
      scaleX: 1 + settle * 0.012,
      scaleY: 1 - settle * 0.012,
    };
  }

  return { ...IDENTITY_TRANSFORM };
}
