// Small HTML builders shared by every page. Everything from a server goes through esc().
import { episodeLabel, progressOf, runtimeText } from './api/jellyfin.js';
import { itemCache, registerSongList, state } from './state.js';

export function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

const svg = (body, size = 24) =>
  `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="currentColor" aria-hidden="true">${body}</svg>`;

export const icons = {
  logo: `<svg viewBox="0 0 64 64" width="26" height="26" aria-hidden="true"><path d="M10 54V28L32 9l22 19v26z" fill="none" stroke="currentColor" stroke-width="6" stroke-linejoin="round"/><path d="M26 25l16 10-16 10z" fill="currentColor"/></svg>`,
  play: svg('<path d="M8 5.14v13.72a1 1 0 0 0 1.52.85l10.6-6.86a1 1 0 0 0 0-1.7L9.52 4.29A1 1 0 0 0 8 5.14z"/>'),
  pause: svg('<path d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z"/>'),
  next: svg('<path d="M5 6.5v11a1 1 0 0 0 1.55.83L14 13.2V17a1 1 0 0 0 2 0V7a1 1 0 0 0-2 0v3.8L6.55 5.67A1 1 0 0 0 5 6.5zM17 6h2v12h-2z"/>'),
  previous: svg('<path d="M19 6.5v11a1 1 0 0 1-1.55.83L10 13.2V17a1 1 0 0 1-2 0V7a1 1 0 0 1 2 0v3.8l7.45-5.13A1 1 0 0 1 19 6.5zM5 6h2v12H5z"/>'),
  info: svg('<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 15h-2v-6h2zm0-8h-2V7h2z"/>'),
  search: svg('<path d="M10.5 3a7.5 7.5 0 0 1 5.96 12.05l4.25 4.24-1.42 1.42-4.24-4.25A7.5 7.5 0 1 1 10.5 3zm0 2a5.5 5.5 0 1 0 0 11 5.5 5.5 0 0 0 0-11z"/>'),
  gear: svg('<path d="M19.4 13a7.6 7.6 0 0 0 0-2l2.1-1.6-2-3.5-2.5 1a7.4 7.4 0 0 0-1.7-1L15 3.3h-4l-.4 2.6a7.4 7.4 0 0 0-1.7 1l-2.5-1-2 3.5L6.6 11a7.6 7.6 0 0 0 0 2l-2.1 1.6 2 3.5 2.5-1a7.4 7.4 0 0 0 1.7 1l.4 2.6h4l.4-2.6a7.4 7.4 0 0 0 1.7-1l2.5 1 2-3.5zM13 15.5a3.5 3.5 0 1 1 0-7 3.5 3.5 0 0 1 0 7z" transform="translate(-1 0)"/>'),
  shuffle: svg('<path d="M17 3l4 4-4 4V8h-2.6l-3 3.6-1.3-1.6L13.5 6H17zM3 6h4.5l9 11H17v-3l4 4-4 4v-3h-1.4l-9-11H3zm0 12h4.5l2-2.4 1.3 1.6L8.5 20H3z"/>'),
  back: svg('<path d="M15.4 4.6 8 12l7.4 7.4-1.4 1.4L5.2 12 14 3.2z"/>'),
  close: svg('<path d="M6.4 5 12 10.6 17.6 5 19 6.4 13.4 12l5.6 5.6-1.4 1.4-5.6-5.6L6.4 19 5 17.6l5.6-5.6L5 6.4z"/>'),
  chevronLeft: svg('<path d="M15.4 4.6 8 12l7.4 7.4-1.4 1.4L5.2 12 14 3.2z"/>', 32),
  chevronRight: svg('<path d="m8.6 4.6 7.4 7.4-7.4 7.4L10 20.8l8.8-8.8L10 3.2z"/>', 32),
  fullscreen: svg('<path d="M4 4h6v2H6v4H4zm10 0h6v6h-2V6h-4zM4 14h2v4h4v2H4zm14 0h2v6h-6v-2h4z"/>'),
  volume: svg('<path d="M4 9h4l5-4v14l-5-4H4zm11.5 3a4 4 0 0 0-2-3.46v6.92a4 4 0 0 0 2-3.46zM13.5 3.2v2.06a7 7 0 0 1 0 13.48v2.06a9 9 0 0 0 0-17.6z"/>'),
  queue: svg('<path d="M3 6h13v2H3zm0 5h13v2H3zm0 5h9v2H3zm15-2v-4l5 3-5 3z"/>'),
  check: svg('<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm-1.5 14.4L6 11.9l1.4-1.4 3.1 3.1 6.1-6.1L18 8.9z"/>', 20),
  music: svg('<path d="M9 18.5A3.5 3.5 0 1 1 7 15.3V5l12-2v12.5a3.5 3.5 0 1 1-2-3.2V7.4l-8 1.3z"/>')
};

export function formatTime(seconds) {
  if (!Number.isFinite(seconds) || seconds <= 0) return '0:00';
  const total = Math.floor(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = String(total % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`;
}

// ---- Feedback ----

export function toast(message) {
  const el = document.createElement('div');
  el.className = 'toast';
  el.textContent = message;
  document.body.appendChild(el);
  requestAnimationFrame(() => el.classList.add('show'));
  setTimeout(() => {
    el.classList.remove('show');
    setTimeout(() => el.remove(), 300);
  }, 5000);
}

export function showLoading(on, label = 'Loading…') {
  let el = document.getElementById('loading-overlay');
  if (!on) {
    el?.remove();
    return;
  }
  if (!el) {
    el = document.createElement('div');
    el.id = 'loading-overlay';
    document.body.appendChild(el);
  }
  el.innerHTML = `<div class="loading-box"><div class="spinner"></div><span>${esc(label)}</span></div>`;
}

export const spinner = () => '<div class="page-spinner"><div class="spinner"></div></div>';

export function errorBanner(message) {
  return `<div class="error-banner">${esc(message)}</div>`;
}

export function signInPrompt(service, message) {
  return `
    <div class="empty-state">
      <div class="empty-icon">${service === 'Navidrome' ? icons.music : icons.logo}</div>
      <h2>Connect ${esc(service)}</h2>
      <p>${esc(message)}</p>
      <a class="btn btn-primary" href="#/settings">${icons.gear}<span>Open Settings</span></a>
    </div>`;
}

// ---- Image with a text fallback when the server has no artwork ----

function img(url, fallback) {
  return `
    <div class="img-box">
      <span class="img-fallback">${esc(fallback)}</span>
      ${url ? `<img loading="lazy" decoding="async" src="${esc(url)}" alt="">` : ''}
    </div>`;
}

function progressBar(fraction) {
  return fraction ? `<div class="progress"><div style="width:${Math.round(fraction * 100)}%"></div></div>` : '';
}

// ---- Rows ----

export function row(title, cards, { extra = '', kind = '' } = {}) {
  if (!cards.length) return '';
  return `
    <section class="row ${kind}">
      <div class="row-head"><h2>${esc(title)}</h2>${extra}</div>
      <div class="row-wrap">
        <button class="row-arrow left" data-scroll="-1" aria-label="Scroll left">${icons.chevronLeft}</button>
        <div class="row-scroller">${cards.join('')}</div>
        <button class="row-arrow right" data-scroll="1" aria-label="Scroll right">${icons.chevronRight}</button>
      </div>
    </section>`;
}

// ---- Video cards ----

export function posterCard(item) {
  itemCache.set(item.Id, item);
  return `
    <a class="card poster" href="#/title/${esc(item.Id)}" title="${esc(item.Name)}">
      ${img(state.jf.posterURL(item), item.Name)}
      ${progressBar(progressOf(item))}
    </a>`;
}

export function landscapeCard(item) {
  itemCache.set(item.Id, item);
  const subtitle = item.Type === 'Episode'
    ? [episodeLabel(item), item.Name].filter(Boolean).join(' · ')
    : runtimeText(item);
  return `
    <button class="card landscape" data-play="${esc(item.Id)}" title="Play ${esc(item.Name)}">
      <div class="landscape-art">
        ${img(state.jf.landscapeURL(item), item.SeriesName ?? item.Name)}
        <span class="play-badge">${icons.play}</span>
        ${progressBar(progressOf(item))}
      </div>
      <div class="card-title">${esc(item.SeriesName ?? item.Name)}</div>
      <div class="card-sub">${esc(subtitle)}</div>
    </button>`;
}

export function posterRow(title, items) {
  return row(title, items.map(posterCard));
}

export function videoHero(item) {
  itemCache.set(item.Id, item);
  const jf = state.jf;
  const logo = jf.logoURL(item);
  const meta = [item.ProductionYear, item.OfficialRating, item.Type === 'Series' ? 'Series' : runtimeText(item)]
    .filter(Boolean).map((part) => `<span>${esc(part)}</span>`).join('');
  const playLabel = progressOf(item) ? 'Resume' : 'Play';
  return `
    <section class="hero" style="--hero-image:url('${esc(jf.backdropURL(item))}')">
      <div class="hero-shade"></div>
      <div class="hero-content">
        ${logo ? `<img class="hero-logo" src="${esc(logo)}" alt="${esc(item.Name)}">` : `<h1 class="hero-title">${esc(item.Name)}</h1>`}
        <div class="meta">${meta}</div>
        ${item.Overview ? `<p class="hero-overview">${esc(item.Overview)}</p>` : ''}
        <div class="hero-buttons">
          <button class="btn btn-primary" data-play="${esc(item.Id)}">${icons.play}<span>${playLabel}</span></button>
          <a class="btn btn-secondary" href="#/title/${esc(item.Id)}">${icons.info}<span>More Info</span></a>
        </div>
      </div>
    </section>`;
}

// ---- Music cards ----

export function albumCard(album) {
  return `
    <a class="card album" href="#/album/${esc(album.id)}" title="${esc(album.name)}">
      <div class="square-art">${img(state.nd.coverURL(album.coverArt, 300), album.name)}</div>
      <div class="card-title">${esc(album.name ?? 'Unknown album')}</div>
      <div class="card-sub">${esc(album.artist ?? '')}</div>
    </a>`;
}

export function artistCard(artist) {
  return `
    <a class="card artist" href="#/artist/${esc(artist.id)}" title="${esc(artist.name)}">
      <div class="round-art">${img(state.nd.coverURL(artist.coverArt, 300), (artist.name ?? '?').slice(0, 1))}</div>
      <div class="card-title">${esc(artist.name)}</div>
    </a>`;
}

export function playlistCard(playlist) {
  return `
    <a class="card album" href="#/playlist/${esc(playlist.id)}" title="${esc(playlist.name)}">
      <div class="square-art">${img(state.nd.coverURL(playlist.coverArt, 300), playlist.name)}<span class="corner-badge">${icons.queue}</span></div>
      <div class="card-title">${esc(playlist.name)}</div>
      <div class="card-sub">${esc(playlist.songCount ?? 0)} songs</div>
    </a>`;
}

export function albumRow(title, albums) {
  return row(title, albums.map(albumCard));
}

/** A table of songs. Clicking a row plays the whole list from that song. */
export function songTable(songs, { artwork = false, numbered = true } = {}) {
  if (!songs.length) return '';
  const listId = registerSongList(songs);
  const rows = songs.map((song, index) => `
    <div class="song" data-song-list="${listId}" data-song-index="${index}" data-song-id="${esc(song.id)}" role="button" tabindex="0">
      <div class="song-lead">
        ${artwork
          ? `<div class="song-art">${img(state.nd.coverURL(song.coverArt, 100), '')}</div>`
          : `<span class="song-num">${numbered ? esc(song.track ?? index + 1) : ''}</span>`}
        <span class="song-play">${icons.play}</span>
      </div>
      <div class="song-main">
        <div class="song-title">${esc(song.title ?? 'Unknown track')}</div>
        <div class="song-artist">${esc(song.artist ?? '')}</div>
      </div>
      <div class="song-album">${esc(song.album ?? '')}</div>
      <div class="song-time">${formatTime(song.duration ?? 0)}</div>
    </div>`).join('');
  return `<div class="song-table">${rows}</div>`;
}
