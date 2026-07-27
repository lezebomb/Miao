const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("petHost", {
  getBootstrap: () => ipcRenderer.invoke("pet:get-bootstrap"),
  rendererReady: () => ipcRenderer.send("pet:renderer-ready"),
  onDebugAction: (callback) =>
    ipcRenderer.on("pet:debug-action", (_event, action) => callback(action)),
  close: () => ipcRenderer.send("pet:close"),
  dragStart: () => ipcRenderer.send("pet:drag-start"),
  dragMove: () => ipcRenderer.send("pet:drag-move"),
  dragEnd: () => ipcRenderer.send("pet:drag-end"),
});
