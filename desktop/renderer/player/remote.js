// Makes Hearth a Jellyfin "cast target": other devices (Hearth on iPhone, the Jellyfin web app)
// can pick this computer under "Play on…" and send it Play / Playstate / GeneralCommand messages
// over Jellyfin's /socket WebSocket.
import { state } from '../state.js';
import { toast } from '../ui.js';
import { playItem, videoControls } from './video.js';

let socket = null;
let client = null;
let keepAliveTimer = null;
let reconnectTimer = null;
let retryDelay = 2000;

export function startRemoteSession(jf) {
  stopRemoteSession();
  if (!jf) return;
  client = jf;
  connect();
}

export function stopRemoteSession() {
  client = null;
  clearTimeout(reconnectTimer);
  clearInterval(keepAliveTimer);
  if (socket) {
    socket.onclose = null;
    socket.close();
    socket = null;
  }
}

function connect() {
  const jf = client;
  if (!jf) return;
  let ws;
  try {
    ws = new WebSocket(jf.socketURL());
  } catch {
    scheduleReconnect();
    return;
  }
  socket = ws;
  ws.onopen = () => {
    retryDelay = 2000;
    jf.postCapabilities().catch((error) => console.warn('Could not register for remote control:', error.message));
  };
  ws.onmessage = (event) => {
    let message;
    try {
      message = JSON.parse(event.data);
    } catch {
      return;
    }
    handle(message, ws).catch((error) => toast(error.message || 'A remote command failed.'));
  };
  ws.onclose = () => {
    clearInterval(keepAliveTimer);
    if (socket === ws) socket = null;
    scheduleReconnect();
  };
}

function scheduleReconnect() {
  if (!client) return;
  clearTimeout(reconnectTimer);
  reconnectTimer = setTimeout(connect, retryDelay);
  retryDelay = Math.min(retryDelay * 2, 60000);
}

async function handle(message, ws) {
  const data = message.Data ?? {};
  switch (message.MessageType) {
    case 'ForceKeepAlive': {
      const seconds = Number(data) || 60;
      clearInterval(keepAliveTimer);
      keepAliveTimer = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ MessageType: 'KeepAlive' }));
      }, (seconds * 1000) / 2);
      ws.send(JSON.stringify({ MessageType: 'KeepAlive' }));
      break;
    }
    case 'Play':
      await handlePlay(data);
      break;
    case 'Playstate':
      handlePlaystate(data);
      break;
    case 'GeneralCommand':
      handleGeneralCommand(data);
      break;
    default:
      break;
  }
}

async function handlePlay(data) {
  const ids = data.ItemIds ?? [];
  if (!ids.length || !state.jf) return;
  const items = await state.jf.itemsByIds(ids);
  if (!items.length) return;
  const command = data.PlayCommand ?? 'PlayNow';
  if ((command === 'PlayNext' || command === 'PlayLast') && videoControls.active) {
    videoControls.enqueue(items, command === 'PlayLast');
    return;
  }
  const index = Math.max(0, Math.min(data.StartIndex ?? 0, items.length - 1));
  await playItem(items[index], {
    queue: items,
    index,
    startTicks: data.StartPositionTicks ?? undefined,
    audioStreamIndex: data.AudioStreamIndex ?? undefined,
    subtitleStreamIndex: data.SubtitleStreamIndex ?? undefined
  });
}

function handlePlaystate(data) {
  switch (data.Command) {
    case 'Stop': videoControls.stop(); break;
    case 'Pause': videoControls.pause(); break;
    case 'Unpause': videoControls.unpause(); break;
    case 'PlayPause': videoControls.playPause(); break;
    case 'Seek': videoControls.seekTicks(Number(data.SeekPositionTicks ?? 0)); break;
    case 'NextTrack': videoControls.next(); break;
    case 'PreviousTrack': videoControls.previous(); break;
    case 'Rewind': videoControls.skip(-10); break;
    case 'FastForward': videoControls.skip(30); break;
    default: break;
  }
}

function handleGeneralCommand(data) {
  const args = data.Arguments ?? {};
  switch (data.Name) {
    case 'SetVolume': videoControls.setVolume(Number(args.Volume ?? 100)); break;
    case 'VolumeUp': videoControls.changeVolume(5); break;
    case 'VolumeDown': videoControls.changeVolume(-5); break;
    case 'Mute': videoControls.setMuted(true); break;
    case 'Unmute': videoControls.setMuted(false); break;
    case 'ToggleMute': videoControls.toggleMute(); break;
    case 'SetAudioStreamIndex': videoControls.setAudioStream(Number(args.Index)); break;
    case 'SetSubtitleStreamIndex': videoControls.setSubtitleStream(Number(args.Index)); break;
    case 'ToggleFullscreen': videoControls.toggleFullscreen(); break;
    case 'DisplayMessage': {
      const text = [args.Header, args.Text].filter(Boolean).join(': ');
      if (text) toast(text);
      break;
    }
    default: break;
  }
}
