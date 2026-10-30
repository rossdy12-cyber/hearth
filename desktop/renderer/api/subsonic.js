// Navidrome through the Subsonic API with token + salt auth:
// each request carries u, s (salt) and t = md5(password + salt), never the password itself.
import { ApiError, buildURL, normalizeServer, randomHex, request } from './common.js';

// Formats Chromium can decode; anything else is converted to mp3 by Navidrome.
const NATIVE_FORMATS = new Set(['mp3', 'aac', 'm4a', 'flac', 'ogg', 'oga', 'opus', 'wav', 'webm']);

export class Subsonic {
  constructor(session, salt, token) {
    this.session = session;
    this.salt = salt;
    this.token = token;
  }

  /** One salt per sign-in keeps cover-art URLs stable, so the image cache works. */
  static async create(session) {
    const salt = randomHex(6);
    const token = await window.hearth.md5(session.password + salt);
    return new Subsonic(session, salt, token);
  }

  static async signIn(server, username, password) {
    const session = { serverURL: normalizeServer(server), username, password };
    const client = await Subsonic.create(session);
    await client.call('ping');
    return session;
  }

  url(endpoint, params = {}) {
    return buildURL(this.session.serverURL, `/rest/${endpoint}`, {
      u: this.session.username, t: this.token, s: this.salt, v: '1.16.1', c: 'Hearth', f: 'json', ...params
    });
  }

  async call(endpoint, params) {
    let response;
    try {
      response = await request(this.url(endpoint, params));
    } catch (error) {
      if (/HTTP 404/.test(error.message)) {
        throw new ApiError("Something answered at that address, but it doesn't look like Navidrome. Check the port number.");
      }
      throw error;
    }
    let body = null;
    try {
      body = (await response.json())?.['subsonic-response'];
    } catch {
      // handled below
    }
    if (!body) throw new ApiError("Something answered at that address, but it doesn't look like Navidrome. Check the port number.");
    if (body.status !== 'ok') {
      if (body.error?.code === 40 || body.error?.code === 41) {
        throw new ApiError('Wrong username or password. Check them in Settings.', 'auth');
      }
      throw new ApiError(body.error?.message || 'Navidrome returned an error.');
    }
    return body;
  }

  /** type: newest, recent, frequent, random, alphabeticalByName, starred */
  async albumList(type, size = 24) {
    return (await this.call('getAlbumList2', { type, size })).albumList2?.album ?? [];
  }

  async artists() {
    const indexes = (await this.call('getArtists')).artists?.index ?? [];
    return indexes.flatMap((index) => index.artist ?? []);
  }

  async artist(id) {
    return (await this.call('getArtist', { id })).artist ?? null;
  }

  async album(id) {
    return (await this.call('getAlbum', { id })).album ?? null;
  }

  async playlists() {
    return (await this.call('getPlaylists')).playlists?.playlist ?? [];
  }

  async playlist(id) {
    return (await this.call('getPlaylist', { id })).playlist ?? null;
  }

  async search(query) {
    return (await this.call('search3', { query, artistCount: 12, albumCount: 24, songCount: 40 })).searchResult3 ?? {};
  }

  scrobble(id, submission) {
    return this.call('scrobble', { id, submission }).catch(() => {});
  }

  coverURL(coverArtId, size) {
    return coverArtId ? this.url('getCoverArt', { id: coverArtId, size }) : null;
  }

  /** maxBitRate: null streams the original file (FLAC stays FLAC); a number converts to MP3. */
  streamURL(song, maxBitRate = null) {
    const kbps = conversionBitRate(song, maxBitRate);
    return this.url('stream', kbps ? { id: song.id, format: 'mp3', maxBitRate: kbps } : { id: song.id, format: 'raw' });
  }
}

export const MUSIC_QUALITIES = [
  { value: 'original', label: 'Original (lossless)', maxBitRate: null },
  { value: '320', label: '320 kbps', maxBitRate: 320 },
  { value: '256', label: '256 kbps', maxBitRate: 256 },
  { value: '192', label: '192 kbps', maxBitRate: 192 },
  { value: '128', label: '128 kbps', maxBitRate: 128 }
];

export function savedMusicQuality() {
  const value = localStorage.getItem('hearth.musicQuality') ?? 'original';
  return MUSIC_QUALITIES.find((quality) => quality.value === value) ?? MUSIC_QUALITIES[0];
}

/** The bitrate Navidrome will convert to, or null when the original file is streamed. */
export function conversionBitRate(song, maxBitRate) {
  const suffix = String(song.suffix ?? '').toLowerCase();
  const playable = !suffix || NATIVE_FORMATS.has(suffix);
  if (!maxBitRate) return playable ? null : 320;
  // An MP3 already at or below the limit is sent as it is.
  if (suffix === 'mp3' && song.bitRate > 0 && song.bitRate <= maxBitRate) return null;
  return maxBitRate;
}

const LOSSLESS = new Set(['flac', 'alac', 'wav', 'aif', 'aiff', 'ape', 'wv', 'dsf', 'dff']);

function isLossless(song) {
  const suffix = String(song.suffix ?? '').toLowerCase();
  return LOSSLESS.has(suffix) || (suffix === 'm4a' && song.bitRate > 500);
}

/** e.g. "FLAC · 24-bit/44.1 kHz" or "MP3 · 320 kbps". */
export function sourceFormat(song) {
  const suffix = String(song.suffix ?? 'audio').toLowerCase();
  const name = suffix === 'm4a' ? (isLossless(song) ? 'ALAC' : 'AAC') : suffix.toUpperCase();
  if (isLossless(song)) {
    const detail = [];
    if (song.bitDepth > 0) detail.push(`${song.bitDepth}-bit`);
    if (song.samplingRate > 0) detail.push(`${+(song.samplingRate / 1000).toFixed(1)} kHz`);
    return detail.length ? `${name} · ${detail.join('/')}` : name;
  }
  return song.bitRate > 0 ? `${name} · ${song.bitRate} kbps` : name;
}

/** What is actually streaming, e.g. "MP3 · 256 kbps (from FLAC)". */
export function streamFormat(song, maxBitRate) {
  const kbps = conversionBitRate(song, maxBitRate);
  if (!kbps) return sourceFormat(song);
  const source = String(song.suffix ?? '').toUpperCase();
  return source ? `MP3 · ${kbps} kbps (from ${source})` : `MP3 · ${kbps} kbps`;
}
