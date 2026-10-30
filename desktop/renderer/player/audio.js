// Music queue for Navidrome, with media keys and OS media controls via the Media Session API.
import { conversionBitRate, savedMusicQuality, streamFormat } from '../api/subsonic.js';

export class AudioPlayer extends EventTarget {
  constructor() {
    super();
    this.client = null;
    /** Set by the video player while a video is open, so media keys control the video. */
    this.override = null;
    this.queue = [];
    this.index = 0;
    /** What is streaming now, e.g. "FLAC · 24-bit/44.1 kHz". */
    this.streamDescription = '';
    this.triedConversion = false;
    this.el = new Audio();
    this.el.preload = 'auto';
    const savedVolume = Number(localStorage.getItem('hearth.volume'));
    this.el.volume = Number.isFinite(savedVolume) && localStorage.getItem('hearth.volume') !== null ? savedVolume : 0.8;

    this.el.addEventListener('timeupdate', () => this.emit('time'));
    this.el.addEventListener('durationchange', () => this.emit('time'));
    this.el.addEventListener('play', () => this.changed());
    this.el.addEventListener('pause', () => this.changed());
    this.el.addEventListener('volumechange', () => {
      localStorage.setItem('hearth.volume', String(this.el.volume));
      this.emit('volume');
    });
    this.el.addEventListener('ended', () => {
      const song = this.current;
      if (song && this.client) this.client.scrobble(song.id, true);
      this.next();
    });
    this.el.addEventListener('error', () => {
      if (!this.current || !this.el.getAttribute('src')) return;
      // The original file wouldn't play here: try the same song converted to MP3 first.
      if (!this.triedConversion) this.load(320);
      else this.emit('error');
    });

    this.setUpMediaKeys();
  }

  get current() {
    return this.queue[this.index] ?? null;
  }

  get isPlaying() {
    return Boolean(this.current) && !this.el.paused;
  }

  get elapsed() {
    return this.el.currentTime || 0;
  }

  get duration() {
    const d = this.el.duration;
    return Number.isFinite(d) && d > 0 ? d : (this.current?.duration ?? 0);
  }

  emit(type) {
    this.dispatchEvent(new Event(type));
  }

  changed() {
    this.updateMediaSession();
    this.emit('change');
  }

  play(songs, start = 0) {
    if (!songs?.length) return;
    this.queue = songs.slice();
    this.index = Math.max(0, Math.min(start, songs.length - 1));
    this.load();
  }

  /** forceBitRate retries a song converted to MP3 when the original file won't play. */
  load(forceBitRate = null) {
    const song = this.current;
    if (!song || !this.client) return;
    const maxBitRate = forceBitRate ?? savedMusicQuality().maxBitRate;
    this.triedConversion = conversionBitRate(song, maxBitRate) !== null;
    this.streamDescription = streamFormat(song, maxBitRate);
    this.el.src = this.client.streamURL(song, maxBitRate);
    this.el.play().catch(() => {});
    this.client.scrobble(song.id, false);
    this.changed();
  }

  toggle() {
    if (this.isPlaying) this.pause();
    else this.resume();
  }

  pause() {
    this.el.pause();
  }

  resume() {
    if (!this.current) return;
    if (!this.el.src) {
      this.load();
      return;
    }
    this.el.play().catch(() => {});
  }

  next() {
    if (this.index + 1 < this.queue.length) {
      this.index += 1;
      this.load();
    } else {
      this.el.pause();
      this.el.currentTime = 0;
      this.changed();
    }
  }

  previous() {
    if (this.el.currentTime > 3 || this.index === 0) {
      this.seek(0);
    } else {
      this.index -= 1;
      this.load();
    }
  }

  jump(index) {
    if (index < 0 || index >= this.queue.length) return;
    this.index = index;
    this.load();
  }

  seek(seconds) {
    if (!Number.isFinite(seconds)) return;
    this.el.currentTime = Math.max(0, seconds);
    this.updatePositionState();
  }

  setVolume(volume) {
    this.el.volume = Math.max(0, Math.min(1, volume));
  }

  stop() {
    this.el.pause();
    this.el.removeAttribute('src');
    this.el.load();
    this.queue = [];
    this.index = 0;
    if ('mediaSession' in navigator) navigator.mediaSession.metadata = null;
    this.changed();
  }

  // ---- OS integration ----

  setUpMediaKeys() {
    if ('mediaSession' in navigator) {
      const session = navigator.mediaSession;
      const on = (action, handler) => {
        try {
          session.setActionHandler(action, handler);
        } catch {
          // Unsupported action on this platform.
        }
      };
      // While a video is open, override (the video player) gets the keys instead.
      on('play', () => (this.override ? this.override.unpause() : this.resume()));
      on('pause', () => (this.override ? this.override.pause() : this.pause()));
      on('previoustrack', () => (this.override ? this.override.previous() : this.previous()));
      on('nexttrack', () => (this.override ? this.override.next() : this.next()));
      on('seekto', (details) => (this.override ? this.override.seekTicks(details.seekTime * 10_000_000) : this.seek(details.seekTime)));
      on('stop', () => (this.override ? this.override.stop() : this.pause()));
    } else if (window.hearth?.registerMediaKeys) {
      window.hearth.registerMediaKeys();
      window.hearth.onMediaKey((action) => {
        const target = this.override;
        if (action === 'toggle') (target ? target.playPause() : this.toggle());
        if (action === 'next') (target ? target.next() : this.next());
        if (action === 'previous') (target ? target.previous() : this.previous());
      });
    }
  }

  updateMediaSession() {
    if (!('mediaSession' in navigator) || this.override) return;
    const song = this.current;
    if (!song) {
      navigator.mediaSession.metadata = null;
      navigator.mediaSession.playbackState = 'none';
      return;
    }
    const cover = this.client?.coverURL(song.coverArt, 512);
    navigator.mediaSession.metadata = new MediaMetadata({
      title: song.title ?? 'Unknown track',
      artist: song.artist ?? '',
      album: song.album ?? '',
      artwork: cover ? [{ src: cover, sizes: '512x512' }] : []
    });
    navigator.mediaSession.playbackState = this.el.paused ? 'paused' : 'playing';
    this.updatePositionState();
  }

  updatePositionState() {
    if (!('mediaSession' in navigator) || !navigator.mediaSession.setPositionState) return;
    const duration = this.duration;
    if (!duration) return;
    try {
      navigator.mediaSession.setPositionState({
        duration,
        position: Math.min(this.el.currentTime || 0, duration),
        playbackRate: 1
      });
    } catch {
      // Ignore position errors while the track is still loading.
    }
  }
}
