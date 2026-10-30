// Full-window video player for Jellyfin. Direct files play in a plain <video>;
// transcoded streams (HLS master.m3u8) go through hls.js. Progress is reported every 10 s.
import { TICKS_PER_SECOND, episodeLabel } from '../api/jellyfin.js';
import { audio, state } from '../state.js';
import { esc, icons, showLoading, toast } from '../ui.js';

let active = null;

export function isVideoActive() {
  return Boolean(active);
}

export async function playItem(item) {
  const jf = state.jf;
  if (!jf || active) return;
  showLoading(true, 'Starting playback…');
  let target = item;
  let source;
  try {
    if (item.Type === 'Series') {
      target = (await jf.nextUpFor(item.Id)) ?? (await jf.firstEpisode(item.Id));
      if (!target) throw new Error('No episodes were found for this show.');
    }
    source = await jf.playbackSource(target.Id);
  } catch (error) {
    showLoading(false);
    toast(error.message || 'This video could not be played.');
    return;
  }
  showLoading(false);
  open(target, source, jf);
}

function open(item, source, jf) {
  audio.pause();
  const startSeconds = item.UserData?.Played ? 0 : (item.UserData?.PlaybackPositionTicks ?? 0) / TICKS_PER_SECOND;
  const title = item.Type === 'Episode'
    ? `${item.SeriesName ?? ''} · ${episodeLabel(item)} ${item.Name ?? ''}`
    : (item.Name ?? '');

  const overlay = document.createElement('div');
  overlay.className = 'video-overlay';
  overlay.innerHTML = `
    <video class="video" controls autoplay playsinline></video>
    <div class="video-top">
      <button class="icon-button" data-video="close" title="Back (Esc)">${icons.back}</button>
      <div class="video-title">${esc(title)}</div>
      <button class="icon-button" data-video="fullscreen" title="Full screen (F)">${icons.fullscreen}</button>
    </div>`;
  document.body.appendChild(overlay);
  document.body.classList.add('video-open');
  const video = overlay.querySelector('video');

  for (const subtitle of source.subtitles) {
    const track = document.createElement('track');
    track.kind = 'subtitles';
    track.label = subtitle.label;
    track.srclang = subtitle.language;
    track.src = subtitle.url;
    if (subtitle.isDefault) track.default = true;
    video.appendChild(track);
  }

  let hls = null;
  if (source.isHls && window.Hls?.isSupported()) {
    hls = new window.Hls({ startPosition: startSeconds > 0 ? startSeconds : -1, maxBufferLength: 30 });
    hls.on(window.Hls.Events.ERROR, (_event, data) => {
      if (data.fatal) fail(`The stream stopped (${data.details}).`);
    });
    hls.loadSource(source.url);
    hls.attachMedia(video);
  } else {
    video.src = source.url;
    video.addEventListener('loadedmetadata', () => {
      if (startSeconds > 0) video.currentTime = startSeconds;
    }, { once: true });
  }
  video.play().catch(() => {});

  const ticks = () => (Number.isFinite(video.currentTime) ? video.currentTime : 0) * TICKS_PER_SECOND;
  jf.reportStart(source, item.Id, startSeconds * TICKS_PER_SECOND);
  const progressTimer = setInterval(() => jf.reportProgress(source, item.Id, ticks(), video.paused), 10000);
  video.addEventListener('pause', () => jf.reportProgress(source, item.Id, ticks(), true));
  video.addEventListener('ended', () => close());
  video.addEventListener('error', () => {
    if (!hls) fail('This video could not be played.');
  });

  // Hide the top bar and cursor when the mouse is still.
  let idleTimer = null;
  const wake = () => {
    overlay.classList.remove('idle');
    clearTimeout(idleTimer);
    idleTimer = setTimeout(() => overlay.classList.add('idle'), 3000);
  };
  overlay.addEventListener('mousemove', wake);
  wake();

  let wentFullscreen = false;
  window.hearth.isFullscreen().then((already) => {
    if (!already) {
      wentFullscreen = true;
      window.hearth.setFullscreen(true);
    }
  });

  const onKey = (event) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      close();
    } else if (event.key === ' ' || event.key === 'k') {
      event.preventDefault();
      if (video.paused) video.play(); else video.pause();
    } else if (event.key === 'ArrowRight') {
      event.preventDefault();
      video.currentTime += 10;
    } else if (event.key === 'ArrowLeft') {
      event.preventDefault();
      video.currentTime = Math.max(0, video.currentTime - 10);
    } else if (event.key === 'f' || event.key === 'F') {
      event.preventDefault();
      toggleFullscreen();
    }
    wake();
  };
  document.addEventListener('keydown', onKey, true);

  async function toggleFullscreen() {
    const now = await window.hearth.isFullscreen();
    await window.hearth.setFullscreen(!now);
  }

  overlay.addEventListener('click', (event) => {
    const action = event.target.closest('[data-video]')?.dataset.video;
    if (action === 'close') close();
    if (action === 'fullscreen') toggleFullscreen();
  });

  let closed = false;
  function close() {
    if (closed) return;
    closed = true;
    const position = ticks();
    clearInterval(progressTimer);
    clearTimeout(idleTimer);
    document.removeEventListener('keydown', onKey, true);
    video.pause();
    if (hls) hls.destroy();
    video.removeAttribute('src');
    video.load();
    overlay.remove();
    document.body.classList.remove('video-open');
    if (wentFullscreen) window.hearth.setFullscreen(false);
    active = null;
    jf.reportStopped(source, item.Id, position).then(() => {
      window.dispatchEvent(new Event('hearth:playback-stopped'));
    });
  }

  function fail(message) {
    close();
    toast(message);
  }

  active = { close };
}
