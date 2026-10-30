// Jellyfin REST API. Sign in with /Users/AuthenticateByName, then send the token in the
// `Authorization: MediaBrowser ... Token="..."` header on every call.
import { ApiError, buildURL, normalizeServer, randomHex, request } from './common.js';

export const TICKS_PER_SECOND = 10_000_000;
const LIST_FIELDS = 'Overview,Genres,PrimaryImageAspectRatio';
const VERSION = '1.0.0';

export function deviceId() {
  let id = localStorage.getItem('hearth.deviceId');
  if (!id) {
    id = randomHex(16);
    localStorage.setItem('hearth.deviceId', id);
  }
  return id;
}

function deviceName() {
  return window.hearth?.platform === 'win32' ? 'Windows PC' : 'Linux PC';
}

function authorizationHeader(token) {
  let value = `MediaBrowser Client="Hearth Desktop", Device="${deviceName()}", DeviceId="${deviceId()}", Version="${VERSION}"`;
  if (token) value += `, Token="${token}"`;
  return value;
}

/** What the desktop player (Chromium + hls.js) can handle. Anything else is transcoded to HLS. */
const DEVICE_PROFILE = {
  Name: 'Hearth Desktop',
  MaxStreamingBitrate: 120_000_000,
  MaxStaticBitrate: 120_000_000,
  MusicStreamingTranscodingBitrate: 192_000,
  DirectPlayProfiles: [
    { Container: 'mp4,m4v', Type: 'Video', VideoCodec: 'h264,vp9,av1', AudioCodec: 'aac,mp3,opus,flac' },
    { Container: 'webm', Type: 'Video', VideoCodec: 'vp8,vp9,av1', AudioCodec: 'vorbis,opus' }
  ],
  TranscodingProfiles: [
    {
      Container: 'ts', Type: 'Video', VideoCodec: 'h264', AudioCodec: 'aac',
      Protocol: 'hls', Context: 'Streaming', MaxAudioChannels: '2',
      MinSegments: 1, BreakOnNonKeyFrames: true
    }
  ],
  SubtitleProfiles: [
    { Format: 'vtt', Method: 'External' },
    { Format: 'pgssub', Method: 'Encode' },
    { Format: 'dvdsub', Method: 'Encode' }
  ],
  ContainerProfiles: [],
  CodecProfiles: []
};

export class Jellyfin {
  constructor(session) {
    this.session = session;
    this.base = session.serverURL;
  }

  static async signIn(server, username, password) {
    const base = normalizeServer(server);
    const response = await request(`${base}/Users/AuthenticateByName`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: authorizationHeader() },
      body: JSON.stringify({ Username: username, Pw: password })
    });
    let data = null;
    try {
      data = await response.json();
    } catch {
      // handled below
    }
    if (!data?.AccessToken || !data?.User?.Id) {
      throw new ApiError("Something answered at that address, but it doesn't look like Jellyfin. Check the port number.");
    }
    return { serverURL: base, username: data.User.Name ?? username, userId: data.User.Id, accessToken: data.AccessToken };
  }

  url(path, query) {
    return buildURL(this.base, path, query);
  }

  async call(path, { query, method = 'GET', body, signal } = {}) {
    const headers = { Authorization: authorizationHeader(this.session.accessToken), Accept: 'application/json' };
    if (body) headers['Content-Type'] = 'application/json';
    const response = await request(this.url(path, query), {
      method, headers, signal, body: body ? JSON.stringify(body) : undefined
    });
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  }

  async items(path, query) {
    return (await this.call(path, { query }))?.Items ?? [];
  }

  logout() {
    return this.call('/Sessions/Logout', { method: 'POST' }).catch(() => {});
  }

  // ---- Browsing ----

  get user() {
    return this.session.userId;
  }

  resumeItems() {
    return this.items('/Items', {
      userId: this.user, Recursive: true, Filters: 'IsResumable', SortBy: 'DatePlayed',
      SortOrder: 'Descending', IncludeItemTypes: 'Movie,Episode', Limit: 20, Fields: LIST_FIELDS
    });
  }

  nextUp(limit = 20) {
    return this.items('/Shows/NextUp', { userId: this.user, Limit: limit, Fields: LIST_FIELDS });
  }

  async nextUpFor(seriesId) {
    return (await this.items('/Shows/NextUp', { userId: this.user, SeriesId: seriesId, Limit: 1, Fields: LIST_FIELDS }))[0] ?? null;
  }

  async firstEpisode(seriesId) {
    return (await this.items(`/Shows/${seriesId}/Episodes`, { userId: this.user, Limit: 1 }))[0] ?? null;
  }

  latest(includeTypes, limit = 24) {
    return this.items('/Items', {
      userId: this.user, Recursive: true, IncludeItemTypes: includeTypes,
      SortBy: 'DateCreated,SortName', SortOrder: 'Descending', Limit: limit, Fields: LIST_FIELDS
    });
  }

  /** Random titles that have a backdrop, for the big banner. */
  featured(includeTypes) {
    return this.items('/Items', {
      userId: this.user, Recursive: true, IncludeItemTypes: includeTypes,
      SortBy: 'Random', ImageTypes: 'Backdrop', Limit: 10, Fields: LIST_FIELDS
    });
  }

  browse({ includeTypes, genreId, sortBy = 'SortName', descending = false, start = 0, limit = 60 }) {
    return this.call('/Items', {
      query: {
        userId: this.user, Recursive: true, IncludeItemTypes: includeTypes, GenreIds: genreId,
        SortBy: sortBy, SortOrder: descending ? 'Descending' : 'Ascending',
        StartIndex: start, Limit: limit, Fields: LIST_FIELDS
      }
    });
  }

  genres(includeTypes) {
    return this.items('/Genres', { userId: this.user, IncludeItemTypes: includeTypes, SortBy: 'SortName', Recursive: true });
  }

  /** A few genre rows ("Comedy", "Drama", ...) with random titles in each. */
  async genreRows(includeTypes, maxRows) {
    let all = [];
    try {
      all = await this.genres(includeTypes);
    } catch {
      return [];
    }
    const picked = all.sort(() => Math.random() - 0.5).slice(0, maxRows);
    const rows = await Promise.all(picked.map(async (genre) => {
      try {
        const page = await this.browse({ includeTypes, genreId: genre.Id, sortBy: 'Random', limit: 24 });
        return page?.Items?.length >= 3 ? { title: genre.Name, items: page.Items } : null;
      } catch {
        return null;
      }
    }));
    return rows.filter(Boolean);
  }

  async item(id) {
    return (await this.items('/Items', { userId: this.user, Ids: id, Fields: LIST_FIELDS }))[0] ?? null;
  }

  seasons(seriesId) {
    return this.items(`/Shows/${seriesId}/Seasons`, { userId: this.user });
  }

  episodes(seriesId, seasonId) {
    return this.items(`/Shows/${seriesId}/Episodes`, { userId: this.user, SeasonId: seasonId, Fields: 'Overview' });
  }

  similar(id) {
    return this.items(`/Items/${id}/Similar`, { userId: this.user, Limit: 16 });
  }

  search(term) {
    return this.items('/Items', {
      userId: this.user, SearchTerm: term, Recursive: true,
      IncludeItemTypes: 'Movie,Series', Limit: 48, Fields: LIST_FIELDS
    });
  }

  // ---- Images ----

  imageURL(itemId, type, maxWidth, tag) {
    return this.url(`/Items/${itemId}/Images/${type}`, { maxWidth, quality: 85, tag });
  }

  posterURL(item) {
    if (item.Type === 'Episode' && item.SeriesId) return this.imageURL(item.SeriesId, 'Primary', 360);
    return this.imageURL(item.Id, 'Primary', 360, item.ImageTags?.Primary);
  }

  backdropURL(item, maxWidth = 1920) {
    if (item.BackdropImageTags?.length) return this.imageURL(item.Id, 'Backdrop', maxWidth, item.BackdropImageTags[0]);
    if (item.ParentBackdropItemId) return this.imageURL(item.ParentBackdropItemId, 'Backdrop', maxWidth);
    if (item.SeriesId) return this.imageURL(item.SeriesId, 'Backdrop', maxWidth);
    return this.imageURL(item.Id, 'Primary', maxWidth, item.ImageTags?.Primary);
  }

  /** Wide 16:9 still for Continue Watching and episode lists. */
  landscapeURL(item) {
    if (item.Type === 'Episode') return this.imageURL(item.Id, 'Primary', 600, item.ImageTags?.Primary);
    if (item.ImageTags?.Thumb) return this.imageURL(item.Id, 'Thumb', 600, item.ImageTags.Thumb);
    return this.backdropURL(item, 600);
  }

  logoURL(item) {
    return item.ImageTags?.Logo ? this.imageURL(item.Id, 'Logo', 800, item.ImageTags.Logo) : null;
  }

  // ---- Playback ----

  /**
   * Asks Jellyfin how to play an item on this device. Files Chromium can play are streamed
   * as they are; everything else comes from Jellyfin's HLS transcoder (master.m3u8).
   */
  async playbackSource(itemId, { audioStreamIndex, subtitleStreamIndex, forceTranscode = false } = {}) {
    const choose = {};
    if (audioStreamIndex != null) choose.AudioStreamIndex = audioStreamIndex;
    if (subtitleStreamIndex != null) choose.SubtitleStreamIndex = subtitleStreamIndex;
    const info = await this.call(`/Items/${itemId}/PlaybackInfo`, {
      method: 'POST',
      query: { userId: this.user, ...choose },
      body: {
        UserId: this.user,
        MaxStreamingBitrate: 120_000_000,
        AutoOpenLiveStream: true,
        // A non-default audio track or a burned-in subtitle needs the server to re-encode.
        EnableDirectPlay: !forceTranscode,
        EnableDirectStream: !forceTranscode,
        EnableTranscoding: true,
        AllowVideoStreamCopy: true,
        AllowAudioStreamCopy: true,
        DeviceProfile: DEVICE_PROFILE,
        ...choose
      }
    });
    const source = info?.MediaSources?.[0];
    if (!source) throw new ApiError('Jellyfin has no playable file for this title.');
    const playSessionId = info.PlaySessionId ?? randomHex(16);
    const mediaSourceId = source.Id ?? itemId;
    const token = this.session.accessToken;
    const streams = source.MediaStreams ?? [];

    const subtitles = streams
      .filter((stream) => stream.Type === 'Subtitle' && stream.DeliveryMethod === 'External' && stream.DeliveryUrl)
      .map((stream) => ({
        index: stream.Index,
        label: stream.DisplayTitle || stream.Language || `Subtitle ${stream.Index}`,
        language: stream.Language || '',
        url: withApiKey(this.base + stream.DeliveryUrl, token),
        isDefault: stream.Index === source.DefaultSubtitleStreamIndex
      }));

    const base = {
      mediaSourceId,
      playSessionId,
      subtitles,
      defaultAudioIndex: source.DefaultAudioStreamIndex ?? null,
      defaultSubtitleIndex: source.DefaultSubtitleStreamIndex ?? -1,
      subtitleIndexes: streams.filter((stream) => stream.Type === 'Subtitle').map((stream) => stream.Index)
    };

    if (source.SupportsDirectPlay) {
      return {
        ...base,
        playMethod: 'DirectPlay',
        isHls: false,
        url: this.url(`/Videos/${itemId}/stream`, {
          static: true, MediaSourceId: mediaSourceId, PlaySessionId: playSessionId,
          DeviceId: deviceId(), ApiKey: token
        })
      };
    }
    if (source.TranscodingUrl) {
      return { ...base, playMethod: 'Transcode', isHls: true, url: withApiKey(this.base + source.TranscodingUrl, token) };
    }
    return {
      ...base,
      playMethod: 'Transcode',
      isHls: true,
      url: this.url(`/Videos/${itemId}/master.m3u8`, {
        MediaSourceId: mediaSourceId, PlaySessionId: playSessionId, DeviceId: deviceId(),
        VideoCodec: 'h264', AudioCodec: 'aac', SegmentContainer: 'ts', TranscodingMaxAudioChannels: 2,
        VideoBitrate: 20_000_000, AudioBitrate: 192_000, BreakOnNonKeyFrames: true, ApiKey: token
      })
    };
  }

  /** `extra` carries live state for remote controllers: volume, mute, chosen tracks, queue. */
  progressBody(source, itemId, positionTicks, isPaused, extra = {}) {
    return {
      ItemId: itemId,
      MediaSourceId: source.mediaSourceId,
      PlaySessionId: source.playSessionId,
      PositionTicks: Math.max(0, Math.round(positionTicks)),
      PlayMethod: source.playMethod,
      CanSeek: true,
      IsPaused: isPaused,
      ...extra
    };
  }

  reportStart(source, itemId, positionTicks, extra) {
    return this.call('/Sessions/Playing', { method: 'POST', body: this.progressBody(source, itemId, positionTicks, false, extra) }).catch(() => {});
  }

  reportProgress(source, itemId, positionTicks, isPaused, extra) {
    return this.call('/Sessions/Playing/Progress', { method: 'POST', body: this.progressBody(source, itemId, positionTicks, isPaused, extra) }).catch(() => {});
  }

  // ---- Remote control ("Play on…") ----

  async itemsByIds(ids) {
    const items = await this.items('/Items', { userId: this.user, Ids: ids.join(','), Fields: LIST_FIELDS });
    const byId = new Map(items.map((item) => [item.Id, item]));
    return ids.map((id) => byId.get(id)).filter(Boolean);
  }

  seriesEpisodes(seriesId) {
    return this.items(`/Shows/${seriesId}/Episodes`, { userId: this.user });
  }

  socketURL() {
    const url = new URL(`${this.base}/socket`);
    url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
    url.searchParams.set('api_key', this.session.accessToken);
    url.searchParams.set('deviceId', deviceId());
    return url.toString();
  }

  /** Tells Jellyfin this app can be controlled from other devices. */
  postCapabilities() {
    return this.call('/Sessions/Capabilities/Full', {
      method: 'POST',
      body: {
        PlayableMediaTypes: ['Video'],
        SupportedCommands: [
          'Play', 'PlayState', 'PlayNext', 'PlayMediaSource',
          'SetVolume', 'VolumeUp', 'VolumeDown', 'Mute', 'Unmute', 'ToggleMute',
          'SetAudioStreamIndex', 'SetSubtitleStreamIndex', 'DisplayMessage', 'ToggleFullscreen'
        ],
        SupportsMediaControl: true,
        SupportsPersistentIdentifier: true
      }
    });
  }

  async reportStopped(source, itemId, positionTicks) {
    await this.call('/Sessions/Playing/Stopped', { method: 'POST', body: this.progressBody(source, itemId, positionTicks, true) }).catch(() => {});
    if (source.playMethod === 'Transcode') {
      await this.call('/Videos/ActiveEncodings', {
        method: 'DELETE', query: { DeviceId: deviceId(), PlaySessionId: source.playSessionId }
      }).catch(() => {});
    }
  }
}

function withApiKey(url, token) {
  return /[?&](apikey|api_key)=/i.test(url) ? url : `${url}${url.includes('?') ? '&' : '?'}ApiKey=${encodeURIComponent(token)}`;
}

// ---- Display helpers ----

export function runtimeText(item) {
  const ticks = item?.RunTimeTicks;
  if (!ticks) return '';
  const minutes = Math.round(ticks / TICKS_PER_SECOND / 60);
  return minutes >= 60 ? `${Math.floor(minutes / 60)}h ${minutes % 60}m` : `${minutes}m`;
}

export function progressOf(item) {
  const position = item?.UserData?.PlaybackPositionTicks;
  if (!position || !item.RunTimeTicks || item.UserData?.Played) return null;
  return Math.min(1, position / item.RunTimeTicks);
}

export function episodeLabel(item) {
  if (item?.Type !== 'Episode') return '';
  const parts = [];
  if (item.ParentIndexNumber != null) parts.push(`S${item.ParentIndexNumber}`);
  if (item.IndexNumber != null) parts.push(`E${item.IndexNumber}`);
  return parts.join(':');
}
