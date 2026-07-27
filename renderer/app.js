import { Animator } from "./animator.js";
import { CanvasRenderer } from "./canvasRenderer.js";
import { PetStateMachine } from "./stateMachine.js";

const canvas = document.querySelector("#pet-canvas");
const bootstrap = await window.petHost.getBootstrap();
const { behavior, config, assetBaseUrl } = bootstrap;
const renderer = new CanvasRenderer(canvas, {
  width: behavior.cell.width,
  height: behavior.cell.height,
  edgeSmoothing: config.renderer?.edgeSmoothing,
});

let fsm;
const animator = new Animator({
  renderer,
  behavior,
  assetBaseUrl,
  onComplete: (actionName, nowMs) => fsm.actionComplete(actionName, nowMs),
});
await animator.preload();

fsm = new PetStateMachine({
  behavior,
  config,
  play: (actionName, nowMs, options) => animator.play(actionName, nowMs, options),
});
fsm.start();
window.petHost.onDebugAction((actionName) => {
  fsm.startDirect(actionName, performance.now());
});
window.petHost.rendererReady();

function animationLoop(nowMs) {
  fsm.tick(nowMs);
  animator.update(nowMs);
  requestAnimationFrame(animationLoop);
}
requestAnimationFrame(animationLoop);

let hoverTimer = 0;
let hoverArmed = true;
let pointerDown = null;
let dragging = false;
let runningDirection = null;
const hoverDwellMs = Number(config.hoverDwellMs ?? 500);
const dragThreshold = Number(config.drag?.horizontalThresholdPx ?? 16);
const dominance = Number(config.drag?.horizontalDominanceRatio ?? 1.35);

function clearHover() {
  window.clearTimeout(hoverTimer);
  hoverTimer = 0;
}

canvas.addEventListener("pointerenter", () => {
  if (!hoverArmed || pointerDown) return;
  clearHover();
  hoverTimer = window.setTimeout(() => {
    hoverArmed = false;
    fsm.requestPetAction(performance.now());
  }, hoverDwellMs);
});

canvas.addEventListener("pointerleave", () => {
  clearHover();
  if (!pointerDown) hoverArmed = true;
});

canvas.addEventListener("pointerdown", (event) => {
  if (event.button !== 0) return;
  clearHover();
  fsm.noteActivity(performance.now());
  pointerDown = { x: event.screenX, y: event.screenY };
  dragging = false;
  runningDirection = null;
  canvas.setPointerCapture(event.pointerId);
  document.body.classList.add("dragging");
  window.petHost.dragStart();
});

canvas.addEventListener("pointermove", (event) => {
  if (!pointerDown) return;
  const dx = event.screenX - pointerDown.x;
  const dy = event.screenY - pointerDown.y;
  if (Math.abs(dx) + Math.abs(dy) >= 2) dragging = true;
  if (dragging) window.petHost.dragMove();
  if (
    Math.abs(dx) >= dragThreshold &&
    Math.abs(dx) >= Math.abs(dy) * dominance
  ) {
    const direction = dx < 0 ? "running-left" : "running-right";
    if (direction !== runningDirection) {
      runningDirection = direction;
      fsm.startDirect(direction, performance.now());
    }
  }
});

canvas.addEventListener("pointerup", (event) => {
  if (event.button !== 0 || !pointerDown) return;
  canvas.releasePointerCapture(event.pointerId);
  window.petHost.dragEnd();
  document.body.classList.remove("dragging");
  pointerDown = null;
  if (dragging) {
    fsm.enterIdle(performance.now());
  } else {
    fsm.requestPetAction(performance.now());
  }
  dragging = false;
  runningDirection = null;
});

canvas.addEventListener("contextmenu", (event) => {
  event.preventDefault();
  window.petHost.close();
});

document.addEventListener("visibilitychange", () => {
  if (!document.hidden) fsm.noteActivity(performance.now());
});
