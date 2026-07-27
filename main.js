import { app, BrowserWindow, ipcMain, screen } from "electron";
import { spawn } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const projectRoot = path.dirname(fileURLToPath(import.meta.url));
const behaviorPath = path.join(projectRoot, "pet", "miaomiao", "behavior.json");
const configPath = path.join(projectRoot, "miaomiao.config.json");
const rendererPath = path.join(projectRoot, "renderer", "index.html");
const preloadPath = path.join(projectRoot, "preload.cjs");
const bridgePath = path.join(projectRoot, "scripts", "windows_host_bridge.ps1");

const args = new Map(
  process.argv.slice(2).map((argument) => {
    const separator = argument.indexOf("=");
    return separator === -1
      ? [argument.replace(/^--/, ""), true]
      : [argument.slice(0, separator).replace(/^--/, ""), argument.slice(separator + 1)];
  }),
);

const singleInstance = app.requestSingleInstanceLock();
if (!singleInstance) {
  app.quit();
}

let petWindow;
let bridge;
let config;
let followState = { manualX: 0, manualY: 0 };
let dragState = null;
let smokeScheduled = false;

function scheduleSmokeCapture() {
  const smokeAction = args.get("smoke-test");
  if (!smokeAction || !petWindow || smokeScheduled) return;
  smokeScheduled = true;
  setTimeout(() => {
    petWindow?.webContents.send("pet:debug-action", String(smokeAction));
  }, 200);
  setTimeout(async () => {
    const image = await petWindow.capturePage();
    const output = path.join(projectRoot, "previews", "actions-v4", `canvas-smoke-${smokeAction}.png`);
    await writeFile(output, image.toPNG());
    console.log(output);
    app.quit();
  }, 1200);
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}

function placeBesideHost(host) {
  if (!petWindow || petWindow.isDestroyed()) return;
  // Win32 GetWindowRect and BrowserWindow.setPosition use the same virtual
  // desktop coordinate space here. Converting the host rectangle a second
  // time caused under-travel on 125–175% Windows display scaling.
  const start = { x: host.left, y: host.top };
  const end = { x: host.right, y: host.bottom };
  const workArea = screen.getDisplayMatching({
    x: start.x,
    y: start.y,
    width: Math.max(1, end.x - start.x),
    height: Math.max(1, end.y - start.y),
  }).workArea;
  const bounds = petWindow.getBounds();
  const options = config.codexWindow ?? {};
  let x = end.x + Number(options.offsetX ?? 16);
  let y = end.y - bounds.height + Number(options.offsetY ?? -16);
  if (x + bounds.width > workArea.x + workArea.width) {
    x = end.x - bounds.width - Number(options.edgePadding ?? 16);
  }
  x = clamp(x + followState.manualX, workArea.x, workArea.x + workArea.width - bounds.width);
  y = clamp(y + followState.manualY, workArea.y, workArea.y + workArea.height - bounds.height);
  petWindow.setPosition(Math.round(x), Math.round(y), false);
}

function startHostBridge() {
  const handle = args.get("follow-hwnd");
  if (!handle || process.platform !== "win32") return;
  const interval = Number(config.codexWindow?.followIntervalMs ?? 100);
  bridge = spawn(
    "powershell.exe",
    [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      bridgePath,
      "-WindowHandle",
      String(handle),
      "-ProcessId",
      String(args.get("follow-pid") ?? 0),
      "-IntervalMs",
      String(interval),
    ],
    { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] },
  );
  let pending = "";
  bridge.stdout.setEncoding("utf8");
  bridge.stdout.on("data", (chunk) => {
    pending += chunk;
    const lines = pending.split(/\r?\n/);
    pending = lines.pop() ?? "";
    for (const line of lines) {
      if (!line.trim()) continue;
      const event = JSON.parse(line);
      if (event.state === "closed") {
        petWindow?.close();
      } else if (event.state === "hidden") {
        petWindow?.hide();
      } else if (event.state === "visible") {
        if (!petWindow?.isVisible()) petWindow?.showInactive();
        placeBesideHost(event);
      }
    }
  });
  bridge.once("exit", () => {
    bridge = undefined;
  });
}

async function createWindow() {
  const [behaviorText, configText] = await Promise.all([
    readFile(behaviorPath, "utf8"),
    readFile(configPath, "utf8"),
  ]);
  const behavior = JSON.parse(behaviorText);
  config = JSON.parse(configText);
  const scale = Number(config.windowScale ?? 1);
  const width = Math.round(behavior.cell.width * scale);
  const height = Math.round(behavior.cell.height * scale);

  petWindow = new BrowserWindow({
    width,
    height,
    transparent: true,
    frame: false,
    resizable: false,
    movable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    show: false,
    hasShadow: false,
    focusable: false,
    backgroundColor: "#00000000",
    webPreferences: {
      preload: preloadPath,
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      backgroundThrottling: false,
    },
  });
  petWindow.setAlwaysOnTop(true, "floating");
  petWindow.webContents.setAudioMuted(true);
  petWindow.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  petWindow.webContents.on("will-navigate", (event) => event.preventDefault());
  petWindow.webContents.on("did-finish-load", scheduleSmokeCapture);
  petWindow.once("ready-to-show", () => {
    petWindow.showInactive();
    startHostBridge();
  });
  await petWindow.loadFile(rendererPath);
}

ipcMain.handle("pet:get-bootstrap", async () => {
  const [behavior, runtimeConfig] = await Promise.all([
    readFile(behaviorPath, "utf8").then(JSON.parse),
    readFile(configPath, "utf8").then(JSON.parse),
  ]);
  return {
    behavior,
    config: runtimeConfig,
    assetBaseUrl: pathToFileURL(path.join(projectRoot, "pet", "miaomiao") + path.sep).href,
  };
});

ipcMain.on("pet:close", () => petWindow?.close());
ipcMain.on("pet:renderer-ready", () => {
  scheduleSmokeCapture();
});
ipcMain.on("pet:drag-start", () => {
  dragState = {
    cursor: screen.getCursorScreenPoint(),
    bounds: petWindow.getBounds(),
    movedX: 0,
    movedY: 0,
  };
});
ipcMain.on("pet:drag-move", () => {
  if (!dragState || !petWindow) return;
  const cursor = screen.getCursorScreenPoint();
  const dx = cursor.x - dragState.cursor.x;
  const dy = cursor.y - dragState.cursor.y;
  dragState.movedX = dx;
  dragState.movedY = dy;
  petWindow.setPosition(dragState.bounds.x + dx, dragState.bounds.y + dy, false);
});
ipcMain.on("pet:drag-end", () => {
  if (!dragState) return;
  followState.manualX += dragState.movedX;
  followState.manualY += dragState.movedY;
  dragState = null;
});

app.on("second-instance", () => petWindow?.showInactive());
app.on("window-all-closed", () => app.quit());
app.on("before-quit", () => bridge?.kill());

if (singleInstance) {
  app.whenReady().then(createWindow);
}
