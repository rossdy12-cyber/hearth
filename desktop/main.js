// Hearth desktop: Electron main process.
// Serves the UI from a private hearth:// scheme, keeps sign-ins encrypted with the
// operating system's key store (safeStorage), and does md5 for Navidrome token auth.
const { app, BrowserWindow, ipcMain, net, protocol, safeStorage, shell, globalShortcut } = require('electron');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const SCHEME = 'hearth';
const RENDERER_DIR = path.join(__dirname, 'renderer');

// Not marked "secure" on purpose: the servers are plain http over Tailscale, and a
// secure page would have its http images, video and audio blocked as mixed content.
protocol.registerSchemesAsPrivileged([
  { scheme: SCHEME, privileges: { standard: true, supportFetchAPI: true, corsEnabled: true, stream: true } }
]);

if (!app.requestSingleInstanceLock()) {
  app.quit();
}

let mainWindow = null;

function accountsFile() {
  return path.join(app.getPath('userData'), 'accounts.dat');
}

function loadAccounts() {
  try {
    const raw = fs.readFileSync(accountsFile());
    const text = raw.subarray(0, 6).toString() === 'plain:'
      ? raw.subarray(6).toString('utf8')
      : safeStorage.decryptString(raw);
    return JSON.parse(text);
  } catch {
    return {};
  }
}

function saveAccounts(accounts) {
  const text = JSON.stringify(accounts ?? {});
  fs.mkdirSync(path.dirname(accountsFile()), { recursive: true });
  if (safeStorage.isEncryptionAvailable()) {
    fs.writeFileSync(accountsFile(), safeStorage.encryptString(text));
  } else {
    // No key store available (rare on Linux without a keyring): fall back to a private file.
    fs.writeFileSync(accountsFile(), Buffer.concat([Buffer.from('plain:'), Buffer.from(text, 'utf8')]), { mode: 0o600 });
  }
  return true;
}

function resolveAsset(urlPath) {
  if (urlPath === '/vendor/hls.min.js') {
    return path.join(__dirname, 'node_modules', 'hls.js', 'dist', 'hls.min.js');
  }
  const file = path.normalize(path.join(RENDERER_DIR, urlPath));
  if (!file.startsWith(RENDERER_DIR)) return null;
  return file;
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 960,
    minHeight: 600,
    backgroundColor: '#0b0b0c',
    title: 'Hearth',
    icon: path.join(__dirname, 'build', 'icon.png'),
    autoHideMenuBar: true,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      // The UI only ever loads its own files. Turning this off lets it call the
      // Jellyfin and Navidrome APIs directly, whatever their CORS settings.
      webSecurity: false,
      allowRunningInsecureContent: true
    }
  });

  mainWindow.once('ready-to-show', () => mainWindow.show());

  // Links to other websites open in the normal browser; nothing else may navigate the app.
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http://') || url.startsWith('https://')) shell.openExternal(url);
    return { action: 'deny' };
  });
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (!url.startsWith(`${SCHEME}://`)) event.preventDefault();
  });

  if (process.env.HEARTH_DEBUG) {
    mainWindow.webContents.on('console-message', (event) => {
      console.log(`[renderer:${event.level}] ${event.message}`);
    });
  }

  const route = process.env.HEARTH_ROUTE ? `#${process.env.HEARTH_ROUTE}` : '';
  mainWindow.loadURL(`${SCHEME}://app/index.html${route}`);

  // Used for automated screenshots: HEARTH_SCREENSHOT=C:\path\shot.png npm start
  if (process.env.HEARTH_SCREENSHOT) {
    mainWindow.webContents.once('did-finish-load', () => {
      setTimeout(async () => {
        // Optional: run a step (e.g. click the first poster) before capturing.
        if (process.env.HEARTH_SCREENSHOT_STEP) {
          await mainWindow.webContents.executeJavaScript(process.env.HEARTH_SCREENSHOT_STEP).catch(() => {});
          await new Promise((resolve) => setTimeout(resolve, Number(process.env.HEARTH_SCREENSHOT_STEP_WAIT || 4000)));
        }
        const image = await mainWindow.webContents.capturePage();
        fs.writeFileSync(process.env.HEARTH_SCREENSHOT, image.toPNG());
        app.quit();
      }, Number(process.env.HEARTH_SCREENSHOT_DELAY || 4000));
    });
  }
}

app.on('second-instance', () => {
  if (!mainWindow) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.focus();
});

app.whenReady().then(() => {
  protocol.handle(SCHEME, (request) => {
    const { pathname } = new URL(request.url);
    const file = resolveAsset(decodeURIComponent(pathname));
    if (!file) return new Response('Not found', { status: 404 });
    return net.fetch(pathToFileURL(file).toString());
  });

  ipcMain.handle('accounts:load', () => loadAccounts());
  ipcMain.handle('accounts:save', (_event, accounts) => saveAccounts(accounts));
  ipcMain.handle('md5', (_event, text) => crypto.createHash('md5').update(String(text), 'utf8').digest('hex'));
  ipcMain.handle('window:fullscreen', (event, on) => {
    const win = BrowserWindow.fromWebContents(event.sender);
    if (win) win.setFullScreen(Boolean(on));
    return win ? win.isFullScreen() : false;
  });
  ipcMain.handle('window:isFullscreen', (event) => {
    const win = BrowserWindow.fromWebContents(event.sender);
    return win ? win.isFullScreen() : false;
  });

  // Fallback media keys for systems where the page can't use the Media Session API.
  ipcMain.handle('mediakeys:register', (event) => {
    const send = (action) => () => event.sender.send('mediakey', action);
    try {
      globalShortcut.register('MediaPlayPause', send('toggle'));
      globalShortcut.register('MediaNextTrack', send('next'));
      globalShortcut.register('MediaPreviousTrack', send('previous'));
    } catch {
      // Another app may own the keys; that's fine.
    }
    return true;
  });

  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('will-quit', () => globalShortcut.unregisterAll());

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
