// Hearth desktop: app shell, router, click handling and the music player bar.
import { Jellyfin } from './api/jellyfin.js';
import { Subsonic } from './api/subsonic.js';
import { startRemoteSession } from './player/remote.js';
import { isVideoActive, playItem } from './player/video.js';
import { audio, itemCache, songLists, state } from './state.js';
import { esc, formatTime, icons, spinner, toast } from './ui.js';
import { albumView, artistView, artistsView, musicView, playlistView } from './views/music.js';
import { searchView } from './views/search.js';
import { settingsView } from './views/settings.js';
import { browseView, homeView, libraryView, titleView } from './views/video.js';

const view = document.getElementById('view');
const nav = document.getElementById('topnav');

// ---- Accounts ----

async function applyAccounts(accounts) {
  state.accounts = accounts ?? {};
  state.jf = state.accounts.jellyfin ? new Jellyfin(state.accounts.jellyfin) : null;
  state.nd = state.accounts.navidrome ? await Subsonic.create(state.accounts.navidrome) : null;
  if (!state.nd) audio.stop();
  audio.client = state.nd;
  // Lets the iPhone or the Jellyfin web app control this computer ("Play on…").
  startRemoteSession(state.jf);
}

async function onAccountsChanged(accounts) {
  await window.hearth.saveAccounts(accounts);
  await applyAccounts(accounts);
  render();
}

// ---- Router ----

const routes = [
  [/^\/home$/, () => homeView(), 'home'],
  [/^\/movies$/, () => libraryView('movies'), 'movies'],
  [/^\/shows$/, () => libraryView('shows'), 'shows'],
  [/^\/browse\/(movies|shows)$/, (m) => browseView(m[1]), (m) => m[1]],
  [/^\/title\/([^/]+)$/, (m) => titleView(decodeURIComponent(m[1])), ''],
  [/^\/music$/, () => musicView(), 'music'],
  [/^\/album\/([^/]+)$/, (m) => albumView(decodeURIComponent(m[1])), 'music'],
  [/^\/artist\/([^/]+)$/, (m) => artistView(decodeURIComponent(m[1])), 'music'],
  [/^\/playlist\/([^/]+)$/, (m) => playlistView(decodeURIComponent(m[1])), 'music'],
  [/^\/artists$/, () => artistsView(), 'music'],
  [/^\/search$/, () => searchView(), 'search'],
  [/^\/settings$/, () => settingsView({ onAccountsChanged }), 'settings']
];

let renderToken = 0;

async function render() {
  const path = location.hash.replace(/^#/, '') || '/home';
  const match = routes.map(([pattern, build, section]) => [path.match(pattern), build, section]).find(([m]) => m);
  if (!match) {
    location.hash = '#/home';
    return;
  }
  const [m, build, section] = match;
  const token = ++renderToken;
  const isCurrent = () => token === renderToken;

  const sectionName = typeof section === 'function' ? section(m) : section;
  for (const link of nav.querySelectorAll('[data-nav]')) {
    link.classList.toggle('active', link.dataset.nav === sectionName);
  }

  const page = document.createElement('div');
  page.className = 'page-root';
  page.innerHTML = spinner();
  view.replaceChildren(page);
  window.scrollTo(0, 0);

  let result;
  try {
    result = await build(m);
  } catch (error) {
    result = `<div class="hero-spacer"></div><div class="error-banner">${esc(error.message)}</div>`;
  }
  if (!isCurrent()) return;
  const { html, mount } = typeof result === 'string' ? { html: result } : result;
  page.innerHTML = html;
  mount?.(page, isCurrent);
  markPlayingSong();
  updateNavBackground();
}

window.addEventListener('hashchange', render);

// Refresh Continue Watching and episode progress after a video closes.
window.addEventListener('hearth:playback-stopped', () => {
  const path = location.hash;
  if (/^#\/(home|title\/|movies|shows)/.test(path) || path === '') {
    const y = window.scrollY;
    render().then(() => window.scrollTo(0, y));
  }
});

// ---- Top bar ----

function updateNavBackground() {
  nav.classList.toggle('solid', window.scrollY > 40 || !document.querySelector('.hero'));
}
window.addEventListener('scroll', updateNavBackground, { passive: true });

// ---- Clicks anywhere in the app ----

document.addEventListener('click', async (event) => {
  const target = event.target;

  const scrollButton = target.closest('[data-scroll]');
  if (scrollButton) {
    const scroller = scrollButton.parentElement.querySelector('.row-scroller');
    scroller.scrollBy({ left: Number(scrollButton.dataset.scroll) * scroller.clientWidth * 0.85, behavior: 'smooth' });
    return;
  }

  const play = target.closest('[data-play]');
  if (play) {
    event.preventDefault();
    const id = play.dataset.play;
    let item = itemCache.get(id);
    if (!item && state.jf) item = await state.jf.item(id).catch(() => null);
    if (item) playItem(item);
    return;
  }

  const song = target.closest('[data-song-list]');
  if (song) {
    const list = songLists.get(song.dataset.songList);
    if (list) audio.play(list, Number(song.dataset.songIndex));
    return;
  }

  const playList = target.closest('[data-play-list]');
  if (playList) {
    const list = songLists.get(playList.dataset.playList) ?? [];
    audio.play(playList.dataset.shuffle ? shuffled(list) : list);
    return;
  }

  const playAlbum = target.closest('[data-play-album]');
  if (playAlbum && state.nd) {
    try {
      const album = await state.nd.album(playAlbum.dataset.playAlbum);
      const songs = album?.song ?? [];
      audio.play(playAlbum.dataset.shuffle ? shuffled(songs) : songs);
    } catch (error) {
      toast(error.message);
    }
    return;
  }

  const playerAction = target.closest('[data-player]');
  if (playerAction) {
    handlePlayerAction(playerAction.dataset.player, playerAction);
  }
});

document.addEventListener('keydown', (event) => {
  if (isVideoActive()) return;
  const song = event.target.closest?.('[data-song-list]');
  if (song && (event.key === 'Enter' || event.key === ' ')) {
    event.preventDefault();
    song.click();
    return;
  }
  const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName);
  if (!typing && event.key === ' ' && audio.current) {
    event.preventDefault();
    audio.toggle();
  }
  if (event.key === 'Escape' && nowPlaying.classList.contains('open')) closeNowPlaying();
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'f') {
    event.preventDefault();
    location.hash = '#/search';
  }
});

// Hide artwork that the server doesn't have, so the title text underneath shows.
document.addEventListener('error', (event) => {
  if (event.target.tagName === 'IMG') event.target.classList.add('broken');
}, true);

function shuffled(list) {
  const copy = list.slice();
  for (let i = copy.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

// ---- Music player bar and Now Playing ----

const bar = document.getElementById('player-bar');
const nowPlaying = document.getElementById('now-playing');

bar.innerHTML = `
  <div class="pb-left" data-player="open">
    <div class="pb-art"><span class="img-box"><span class="img-fallback"></span><img id="pb-cover" alt=""></span></div>
    <div class="pb-text"><div id="pb-title" class="pb-title"></div><div id="pb-artist" class="pb-artist"></div><div id="pb-format" class="pb-format"></div></div>
  </div>
  <div class="pb-center">
    <div class="pb-buttons">
      <button class="icon-button" data-player="previous" title="Previous">${icons.previous}</button>
      <button class="icon-button pb-play" data-player="toggle" title="Play/Pause (Space)" id="pb-toggle">${icons.play}</button>
      <button class="icon-button" data-player="next" title="Next">${icons.next}</button>
    </div>
    <div class="pb-seek">
      <span id="pb-elapsed">0:00</span>
      <input id="pb-slider" type="range" min="0" max="1000" value="0" aria-label="Position">
      <span id="pb-duration">0:00</span>
    </div>
  </div>
  <div class="pb-right">
    <button class="icon-button" data-player="open" title="Now Playing">${icons.queue}</button>
    <span class="pb-volume-icon">${icons.volume}</span>
    <input id="pb-volume" type="range" min="0" max="100" aria-label="Volume">
  </div>`;

nowPlaying.innerHTML = `
  <div class="np-backdrop" id="np-backdrop"></div>
  <div class="np-inner">
    <button class="icon-button np-close" data-player="close" title="Close (Esc)">${icons.close}</button>
    <div class="np-main">
      <div class="np-art"><span class="img-box"><span class="img-fallback"></span><img id="np-cover" alt=""></span></div>
      <div class="np-info">
        <div class="eyebrow">Now playing</div>
        <h1 id="np-title"></h1>
        <div id="np-artist" class="np-artist"></div>
        <div id="np-format" class="format-badge"></div>
      </div>
    </div>
    <div class="np-queue">
      <h2>Up next</h2>
      <div id="np-list" class="np-list"></div>
    </div>
  </div>`;

const el = (id) => document.getElementById(id);
const slider = el('pb-slider');
const volume = el('pb-volume');
let dragging = false;

function handlePlayerAction(action, element) {
  if (action === 'toggle') audio.toggle();
  if (action === 'next') audio.next();
  if (action === 'previous') audio.previous();
  if (action === 'open') openNowPlaying();
  if (action === 'close') closeNowPlaying();
  if (action === 'jump') audio.jump(Number(element.dataset.index));
}

function openNowPlaying() {
  if (!audio.current) return;
  renderQueue();
  nowPlaying.classList.add('open');
}

function closeNowPlaying() {
  nowPlaying.classList.remove('open');
}

function renderQueue() {
  el('np-list').innerHTML = audio.queue.map((song, index) => `
    <button class="np-song ${index === audio.index ? 'current' : ''}" data-player="jump" data-index="${index}">
      <span class="np-num">${index === audio.index ? icons.volume : index + 1}</span>
      <span class="np-song-text"><span class="np-song-title">${esc(song.title ?? 'Unknown track')}</span><span class="np-song-artist">${esc(song.artist ?? '')}</span></span>
      <span class="np-time">${formatTime(song.duration ?? 0)}</span>
    </button>`).join('');
  el('np-list').querySelector('.current')?.scrollIntoView({ block: 'center' });
}

function setImage(img, url) {
  img.classList.remove('broken');
  if (url) img.src = url;
  else img.removeAttribute('src');
}

function markPlayingSong() {
  const id = audio.current?.id;
  for (const row of document.querySelectorAll('.song.playing')) row.classList.remove('playing');
  if (!id) return;
  for (const row of document.querySelectorAll(`.song[data-song-id="${CSS.escape(id)}"]`)) row.classList.add('playing');
}

audio.addEventListener('change', () => {
  const song = audio.current;
  document.body.classList.toggle('has-player', Boolean(song));
  bar.hidden = !song;
  el('pb-toggle').innerHTML = audio.isPlaying ? icons.pause : icons.play;
  if (!song) {
    closeNowPlaying();
    return;
  }
  el('np-format').textContent = audio.streamDescription;
  el('pb-format').textContent = audio.streamDescription;
  const cover = state.nd?.coverURL(song.coverArt, 300);
  if (bar.dataset.songId !== song.id) {
    bar.dataset.songId = song.id;
    setImage(el('pb-cover'), cover);
    setImage(el('np-cover'), state.nd?.coverURL(song.coverArt, 800));
    el('np-backdrop').style.backgroundImage = cover ? `url("${cover}")` : '';
    el('pb-title').textContent = song.title ?? 'Unknown track';
    el('pb-artist').textContent = song.artist ?? '';
    el('np-title').textContent = song.title ?? 'Unknown track';
    el('np-artist').textContent = [song.artist, song.album].filter(Boolean).join(' — ');
    if (nowPlaying.classList.contains('open')) renderQueue();
    markPlayingSong();
  }
});

audio.addEventListener('time', () => {
  const duration = audio.duration;
  el('pb-elapsed').textContent = formatTime(audio.elapsed);
  el('pb-duration').textContent = formatTime(duration);
  if (!dragging) slider.value = duration ? String(Math.round((audio.elapsed / duration) * 1000)) : '0';
});

audio.addEventListener('volume', () => {
  volume.value = String(Math.round(audio.el.volume * 100));
});

audio.addEventListener('error', () => {
  toast(`Couldn't play “${audio.current?.title ?? 'this track'}”. Skipping.`);
  setTimeout(() => audio.next(), 1200);
});

slider.addEventListener('input', () => {
  dragging = true;
  el('pb-elapsed').textContent = formatTime((Number(slider.value) / 1000) * audio.duration);
});
slider.addEventListener('change', () => {
  audio.seek((Number(slider.value) / 1000) * audio.duration);
  dragging = false;
});
volume.value = String(Math.round(audio.el.volume * 100));
volume.addEventListener('input', () => audio.setVolume(Number(volume.value) / 100));

// ---- Start ----

nav.innerHTML = `
  <a class="logo" href="#/home" aria-label="Hearth home">${icons.logo}<span>HEARTH</span></a>
  <nav class="nav-links">
    <a href="#/home" data-nav="home">Home</a>
    <a href="#/shows" data-nav="shows">TV Shows</a>
    <a href="#/movies" data-nav="movies">Movies</a>
    <a href="#/music" data-nav="music">Music</a>
  </nav>
  <div class="nav-right">
    <a class="icon-button" href="#/search" data-nav="search" title="Search (Ctrl+F)">${icons.search}</a>
    <a class="icon-button" href="#/settings" data-nav="settings" title="Settings">${icons.gear}</a>
  </div>`;

(async () => {
  try {
    await applyAccounts(await window.hearth.loadAccounts());
  } catch (error) {
    toast(`Couldn't load your saved sign-ins: ${error.message}`);
  }
  if (!state.jf && !state.nd && !location.hash.startsWith('#/settings')) {
    location.hash = '#/settings';
  }
  render();
})();
