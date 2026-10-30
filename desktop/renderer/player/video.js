// Full-window video player for Jellyfin. Direct files play in a plain <video>;
// transcoded streams (HLS master.m3u8) go through hls.js. Progress, volume and track choices
// are reported to Jellyfin so other devices ("Play on…" remotes) can see and steer playback.
import { TICKS_PER_SECOND, episodeLabel } from '../api/jellyfin.js';
import { audio, state } from '../state.js';
import { esc, icons, showLoading, toast } from '../ui.js';

const REPORT_INTERVAL_MS = 5000;

let current = null;
let starting = false;
// True when this player switched the window to full screen (so it should switch it back).
let ownsFullscreen = false;

function savedVolume() {
  const value = Number(localStorage.getItem('hearth.videoVolume'));
  return localStorage.getItem('hearth.videoVolume') !== null && Number.isFinite(value) ? value : 1;
}

export function isVideoActive() {
  return Boolean(current);
}

/**
 * Plays a Jellyfin item. For a show it picks the next episode to watch.
 * options: queue (items), index, startTicks, audioStreamIndex, subtitleStreamIndex.
 */
export async function playItem(item, options = {}) {
  const jf = state.jf;
  if (!jf || starting) return;
  starting = true;
  showLoading(true, 'Starting playback…');
  try {
    let target = item;
    if (item.Type === 'Series') {
      target = (await jf.nextUpFor(item.Id)) ?? (await jf.firstEpisode(item.Id));
      if (!target) throw new Error('No episodes were found for this show.');
    }
    const forceTranscode = options.audioStreamIndex != null || (options.subtitleStreamIndex != null && options.subtitleStreamIndex >= 0 && options.burnSubtitles);
    const source = await jf.playbackSource(target.Id, {
      audioStreamIndex: options.audioStreamIndex,
      subtitleStreamIndex: options.burnSubtitles ? options.subtitleStreamIndex : undefined,
      forceTranscode
    });
    const queue = options.queue?.length ? options.queue : [target];
    const index = options.queue?.length ? Math.max(0, Math.min(options.index ?? 0, queue.length - 1)) : 0;
    const keepFullscreen = Boolean(current);
    if (current) current.close({ silent: true, keepFullscreen: true });
    open(target, source, jf, { ...options, queue, index, keepFullscreen });
  } catch (error) {
    toast(error.message || 'This video could not be played.');
  } finally {
    starting = false;
    showLoading(false);
  }
}

/** Commands for remote control and media keys. They do nothing when no video is open. */
export const videoControls = {
  get active() { return Boolean(current); },
  pause: () => current?.video.pause(),
  unpause: () => current?.video.play().catch(() => {}),
  playPause: () => (current?.video.paused ? videoControls.unpause() : videoControls.pause()),
  stop: () => current?.close(),
  seekTicks: (ticks) => current && (current.video.currentTime = Math.max(0, ticks / TICKS_PER_SECOND)),
  skip: (seconds) => current && (current.video.currentTime = Math.max(0, current.video.currentTime + seconds)),
  next: () => current?.next(),
  previous: () => current?.previous(),
  setVolume: (percent) => {
    const volume = Math.max(0, Math.min(1, percent / 100));
    localStorage.setItem('hearth.videoVolume', String(volume));
    if (current) {
      current.video.volume = volume;
      current.video.muted = false;
    }
  },
  changeVolume: (delta) => videoControls.setVolume(Math.round((current ? current.video.volume : savedVolume()) * 100) + delta),
  setMuted: (muted) => current && (current.video.muted = muted),
  toggleMute: () => current && (current.video.muted = !current.video.muted),
  setAudioStream: (index) => current?.setAudioStream(index),
  setSubtitleStream: (index) => current?.setSubtitleStream(index),
  toggleFullscreen: async () => window.hearth.setFullscreen(!(await window.hearth.isFullscreen())),
  enqueue: (items, last) => current?.enqueue(items, last)
};

function open(item, source, jf, options) {
  audio.pause();
  const startSeconds = options.startTicks != null
    ? options.startTicks / TICKS_PER_SECOND
    : (item.UserData?.Played ? 0 : (item.UserData?.PlaybackPositionTicks ?? 0) / TICKS_PER_SECOND);
  const title = item.Type === 'Episode'
    ? `${item.SeriesName ?? ''} · ${episodeLabel(item)} ${item.Name ?? ''}`
    : (item.Name ?? '');
  const queue = options.queue.slice();
  let index = options.index;
  let audioIndex = options.audioStreamIndex ?? source.defaultAudioIndex;
  let subtitleIndex = options.subtitleStreamIndex ?? source.defaultSubtitleIndex;

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
  video.volume = savedVolume();

  // Text subtitles come as separate WebVTT files; only the chosen one is shown.
  const tracks = source.subtitles.map((subtitle) => {
    const track = document.createElement('track');
    track.kind = 'subtitles';
    track.label = subtitle.label;
    track.srclang = subtitle.language;
    track.src = subtitle.url;
    video.appendChild(track);
    return { index: subtitle.index, track };
  });
  const showSubtitle = (wanted) => {
    for (const { index: trackIndex, track } of tracks) {
      track.track.mode = trackIndex === wanted ? 'showing' : 'disabled';
    }
  };
  showSubtitle(subtitleIndex);

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
  const liveState = (eventName) => ({
    VolumeLevel: Math.round(video.volume * 100),
    IsMuted: video.muted,
    AudioStreamIndex: audioIndex,
    SubtitleStreamIndex: subtitleIndex,
    NowPlayingQueue: queue.map((queued) => ({ Id: queued.Id, PlaylistItemId: queued.Id })),
    PlaylistItemId: item.Id,
    EventName: eventName
  });
  const report = (eventName = 'TimeUpdate') => jf.reportProgress(source, item.Id, ticks(), video.paused, liveState(eventName));

  jf.reportStart(source, item.Id, startSeconds * TICKS_PER_SECOND, liveState('Start'));
  const progressTimer = setInterval(() => report(), REPORT_INTERVAL_MS);
  video.addEventListener('pause', () => report('Pause'));
  video.addEventListener('play', () => report('Unpause'));
  video.addEventListener('seeked', () => report('TimeUpdate'));
  video.addEventListener('volumechange', () => report('VolumeChange'));
  video.addEventListener('ended', () => {
    if (!next()) close();
  });
  video.addEventListener('error', () => {
    if (!hls) fail('This video could not be played.');
  });

  setUpMediaSession(item, title, jf);

  // Hide the top bar and cursor when the mouse is still.
  let idleTimer = null;
  const wake = () => {
    overlay.classList.remove('idle');
    clearTimeout(idleTimer);
    idleTimer = setTimeout(() => overlay.classList.add('idle'), 3000);
  };
  overlay.addEventListener('mousemove', wake);
  wake();

  if (!options.keepFullscreen) {
    window.hearth.isFullscreen().then((already) => {
      if (!already) {
        ownsFullscreen = true;
        window.hearth.setFullscreen(true);
      }
    });
  }

  const onKey = (event) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      close();
    } else if (event.key === ' ' || event.key === 'k') {
      event.preventDefault();
      videoControls.playPause();
    } else if (event.key === 'ArrowRight') {
      event.preventDefault();
      videoControls.skip(10);
    } else if (event.key === 'ArrowLeft') {
      event.preventDefault();
      videoControls.skip(-10);
    } else if (event.key === 'f' || event.key === 'F') {
      event.preventDefault();
      videoControls.toggleFullscreen();
    }
    wake();
  };
  document.addEventListener('keydown', onKey, true);

  overlay.addEventListener('click', (event) => {
    const action = event.target.closest('[data-video]')?.dataset.video;
    if (action === 'close') close();
    if (action === 'fullscreen') videoControls.toggleFullscreen();
  });

  /** Restarts the same title at the same spot with different tracks. */
  function restartWith(changes) {
    playItem(item, {
      queue, index, startTicks: ticks(),
      audioStreamIndex: audioIndex === source.defaultAudioIndex ? undefined : audioIndex,
      subtitleStreamIndex: subtitleIndex,
      ...changes
    });
  }

  function setAudioStream(wanted) {
    if (wanted === audioIndex) return;
    audioIndex = wanted;
    restartWith({ audioStreamIndex: wanted === source.defaultAudioIndex ? undefined : wanted });
  }

  function setSubtitleStream(wanted) {
    subtitleIndex = wanted;
    if (wanted < 0 || tracks.some((entry) => entry.index === wanted)) {
      showSubtitle(wanted);
      report('SubtitleTrackChange');
    } else if (source.subtitleIndexes.includes(wanted)) {
      // Picture-based subtitles have to be burned into the video by the server.
      restartWith({ subtitleStreamIndex: wanted, burnSubtitles: true });
    }
  }

  async function adjacentEpisode(step) {
    if (item.Type !== 'Episode' || !item.SeriesId) return null;
    const episodes = await jf.seriesEpisodes(item.SeriesId).catch(() => []);
    const position = episodes.findIndex((episode) => episode.Id === item.Id);
    return position >= 0 ? episodes[position + step] ?? null : null;
  }

  function next() {
    if (index + 1 < queue.length) {
      playItem(queue[index + 1], { queue, index: index + 1 });
      return true;
    }
    adjacentEpisode(1).then((episode) => {
      if (episode) playItem(episode, { startTicks: 0 });
      else if (video.ended) close();
    });
    return true;
  }

  function previous() {
    if (video.currentTime > 5) {
      video.currentTime = 0;
      return;
    }
    if (index > 0) {
      playItem(queue[index - 1], { queue, index: index - 1 });
      return;
    }
    adjacentEpisode(-1).then((episode) => {
      if (episode) playItem(episode, { startTicks: 0 });
      else video.currentTime = 0;
    });
  }

  function enqueue(items, last) {
    if (last) queue.push(...items);
    else queue.splice(index + 1, 0, ...items);
    report('PlaylistItemAdd');
  }

  let closed = false;
  function close({ silent = false, keepFullscreen = false } = {}) {
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
    if (ownsFullscreen && !keepFullscreen) {
      ownsFullscreen = false;
      window.hearth.setFullscreen(false);
    }
    if (current?.video === video) current = null;
    audio.override = null;
    audio.updateMediaSession();
    jf.reportStopped(source, item.Id, position).then(() => {
      if (!silent) window.dispatchEvent(new Event('hearth:playback-stopped'));
    });
  }

  function fail(message) {
    close();
    toast(message);
  }

  current = { video, close, next, previous, setAudioStream, setSubtitleStream, enqueue };
  audio.override = videoControls;
}

/** Shows the video on the OS media overlay (Windows SMTC / Linux MPRIS) and routes media keys to it. */
function setUpMediaSession(item, title, jf) {
  if (!('mediaSession' in navigator)) return;
  const art = item.Type === 'Episode' && item.SeriesId ? jf.imageURL(item.SeriesId, 'Primary', 512) : jf.imageURL(item.Id, 'Primary', 512);
  navigator.mediaSession.metadata = new MediaMetadata({
    title: item.Name ?? title,
    artist: item.SeriesName ?? '',
    album: item.Type === 'Episode' ? episodeLabel(item) : '',
    artwork: [{ src: art, sizes: '512x512' }]
  });
}
