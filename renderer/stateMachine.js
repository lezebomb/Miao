function weightedChoice(entries, random) {
  if (!entries.length) return null;
  const total = entries.reduce((sum, entry) => sum + Math.max(0, Number(entry.weight ?? 1)), 0);
  if (total <= 0) return null;
  let cursor = random() * total;
  for (const entry of entries) {
    cursor -= Math.max(0, Number(entry.weight ?? 1));
    if (cursor < 0) return entry.action;
  }
  return entries.at(-1).action;
}

function randomRange(range, random, fallback) {
  const [minimum, maximum] = range?.length === 2 ? range : fallback;
  return minimum + random() * (maximum - minimum);
}

export class PetStateMachine {
  constructor({ behavior, config, play, now = () => performance.now(), random = Math.random }) {
    this.behavior = behavior;
    this.config = config;
    this.play = play;
    this.now = now;
    this.random = random;
    this.state = "boot";
    this.currentAction = null;
    this.pendingAction = null;
    this.lastActivityAt = this.now();
    this.specialUsedSinceActivity = false;
    this.nextMicroAt = this.lastActivityAt;
    this.lastPetAt = Number.NEGATIVE_INFINITY;
  }

  start() {
    this.enterIdle(this.now());
  }

  idleConfig() {
    return this.config.idle ?? {};
  }

  scheduleMicro(nowMs) {
    this.nextMicroAt =
      nowMs +
      randomRange(
        this.idleConfig().basicActionIntervalMs,
        this.random,
        this.config.idlePauseRangeMs ?? [4000, 8000],
      );
  }

  noteActivity(nowMs = this.now()) {
    this.lastActivityAt = nowMs;
    this.specialUsedSinceActivity = false;
    this.scheduleMicro(nowMs);
  }

  enterIdle(nowMs = this.now()) {
    this.state = "idle";
    this.currentAction = "idle";
    this.pendingAction = null;
    this.play("idle", nowMs);
    this.scheduleMicro(nowMs);
  }

  startDirect(actionName, nowMs = this.now()) {
    if (!this.behavior.actions[actionName]) return false;
    this.noteActivity(nowMs);
    this.state = "action";
    this.currentAction = actionName;
    this.pendingAction = null;
    this.play(actionName, nowMs);
    return true;
  }

  requestAction(actionName, nowMs = this.now()) {
    if (!this.behavior.actions[actionName]) return false;
    if (!["idle", "sleep"].includes(this.state)) return false;
    if (this.state === "sleep") {
      this.pendingAction = actionName;
      this.state = "waking";
      this.currentAction = "wake";
      this.play("wake", nowMs);
      return true;
    }
    const preparation = `prepare-${actionName}`;
    if (this.behavior.actions[preparation]) {
      this.pendingAction = actionName;
      this.state = "transition";
      this.currentAction = preparation;
      this.play(preparation, nowMs);
    } else {
      this.state = "action";
      this.currentAction = actionName;
      this.play(actionName, nowMs);
    }
    return true;
  }

  requestPetAction(nowMs = this.now()) {
    const cooldown = Number(this.config.triggerCooldownMs ?? 2000);
    if (nowMs - this.lastPetAt < cooldown) return false;
    this.noteActivity(nowMs);
    const event = this.behavior.events.petOrHover;
    const entries = event.random.map((action, index) => ({
      action,
      weight: event.weights?.[index] ?? 1,
    }));
    const action = weightedChoice(entries, this.random);
    if (!action || !this.requestAction(action, nowMs)) return false;
    this.lastPetAt = nowMs;
    return true;
  }

  wake(nowMs = this.now()) {
    this.noteActivity(nowMs);
    if (this.state !== "sleep") return false;
    this.state = "waking";
    this.currentAction = "wake";
    this.play("wake", nowMs);
    return true;
  }

  actionComplete(actionName, nowMs = this.now()) {
    if (this.state === "transition" && actionName === this.currentAction) {
      const target = this.pendingAction;
      this.pendingAction = null;
      this.state = "action";
      this.currentAction = target;
      this.play(target, nowMs);
      return;
    }
    if (this.state === "waking" && actionName === "wake") {
      const target = this.pendingAction;
      this.pendingAction = null;
      if (target) {
        this.state = "idle";
        this.currentAction = "idle";
        this.requestAction(target, nowMs);
      } else {
        this.enterIdle(nowMs);
      }
      return;
    }
    const action = this.behavior.actions[actionName];
    if (this.state === "action" && action?.outroAction) {
      this.state = "returning";
      this.currentAction = action.outroAction;
      this.play(action.outroAction, nowMs);
      return;
    }
    this.enterIdle(nowMs);
  }

  tick(nowMs = this.now()) {
    const idleFor = nowMs - this.lastActivityAt;
    const idle = this.idleConfig();
    if (this.state === "idle" && idleFor >= Number(idle.sleepAfterMs ?? 180000)) {
      this.state = "sleep";
      this.currentAction = "sleep";
      this.play("sleep", nowMs);
      return;
    }
    if (
      this.state === "idle" &&
      !this.specialUsedSinceActivity &&
      idleFor >= Number(idle.specialAfterMs ?? 30000)
    ) {
      const action = weightedChoice(this.behavior.events.idle.specialActions ?? [], this.random);
      if (action && this.behavior.actions[action]) {
        this.specialUsedSinceActivity = true;
        this.state = "action";
        this.currentAction = action;
        this.play(action, nowMs);
        return;
      }
    }
    if (this.state === "idle" && nowMs >= this.nextMicroAt) {
      const action = weightedChoice(this.behavior.events.idle.microActions ?? [], this.random);
      this.scheduleMicro(nowMs);
      if (action && this.behavior.actions[action]) {
        this.state = "action";
        this.currentAction = action;
        this.play(action, nowMs);
      }
    }
  }
}

export { weightedChoice };
