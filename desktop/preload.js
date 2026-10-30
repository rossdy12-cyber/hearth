// The only bridge between the UI and the main process.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('hearth', {
  platform: process.platform,
  loadAccounts: () => ipcRenderer.invoke('accounts:load'),
  saveAccounts: (accounts) => ipcRenderer.invoke('accounts:save', accounts),
  md5: (text) => ipcRenderer.invoke('md5', text),
  setFullscreen: (on) => ipcRenderer.invoke('window:fullscreen', on),
  isFullscreen: () => ipcRenderer.invoke('window:isFullscreen'),
  registerMediaKeys: () => ipcRenderer.invoke('mediakeys:register'),
  onMediaKey: (callback) => ipcRenderer.on('mediakey', (_event, action) => callback(action))
});
