import { sampleMotionTransform } from "./motionProfiles.js";

export class Animator {
  constructor({ renderer, behavior, assetBaseUrl, onComplete = () => {} }) {
    this.renderer = renderer;
    this.behavior = behavior;
    this.assetBaseUrl = assetBaseUrl;
    this.onComplete = onComplete;
    this.playback = null;
    this.renderToken = 0;
  }

  frameUrl(relativePath) {
    return new URL(relativePath, this.assetBaseUrl).href;
  }

  async preload() {
    const urls = Object.values(this.behavior.actions).flatMap((action) =>
      action.frames.map((frame) => this.frameUrl(frame)),
    );
    await this.renderer.preload(urls);
  }

  play(actionName, nowMs, { startFrame = 0 } = {}) {
    const action = this.behavior.actions[actionName];
    if (!action) throw new Error(`Unknown action: ${actionName}`);
    const frameIndex = Math.max(0, Math.min(startFrame, action.frames.length - 1));
    this.playback = {
      actionName,
      action,
      frameIndex,
      cycle: 0,
      frameStartedAt: nowMs,
    };
  }

  stop() {
    this.playback = null;
  }

  durationAt(action, frameIndex) {
    return Number(action.frameDurationsMs?.[frameIndex] ?? action.frameDurationMs ?? 100);
  }

  advance(nowMs) {
    if (!this.playback) return;
    let safety = 0;
    while (this.playback && safety++ < 128) {
      const { action, frameIndex, frameStartedAt } = this.playback;
      const duration = this.durationAt(action, frameIndex);
      if (nowMs - frameStartedAt < duration) break;
      this.playback.frameStartedAt += duration;
      this.playback.frameIndex += 1;
      if (this.playback.frameIndex < action.frames.length) continue;

      if (action.loop) {
        this.playback.frameIndex = 0;
        continue;
      }
      this.playback.cycle += 1;
      const repeatCount = Number(action.repeatCount ?? 1);
      if (this.playback.cycle < repeatCount) {
        this.playback.frameIndex = 0;
        continue;
      }
      const completed = this.playback.actionName;
      this.playback = null;
      this.onComplete(completed, nowMs);
    }
  }

  update(nowMs) {
    this.advance(nowMs);
    if (!this.playback) return;
    const { actionName, action, frameIndex, frameStartedAt } = this.playback;
    const duration = this.durationAt(action, frameIndex);
    const progress = Math.max(0, Math.min(1, (nowMs - frameStartedAt) / duration));
    const transform = sampleMotionTransform(
      actionName,
      action,
      frameIndex,
      progress,
      nowMs,
    );
    const token = ++this.renderToken;
    this.renderer
      .render(this.frameUrl(action.frames[frameIndex]), transform)
      .catch((error) => {
        if (token === this.renderToken) console.error(error);
      });
  }

  snapshot() {
    if (!this.playback) return null;
    return {
      actionName: this.playback.actionName,
      frameIndex: this.playback.frameIndex,
      cycle: this.playback.cycle,
    };
  }
}
