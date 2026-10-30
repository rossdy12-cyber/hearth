// Music tab and album / artist / playlist pages, all from Navidrome.
import { registerSongList, state } from '../state.js';
import {
  albumCard, albumRow, artistCard, errorBanner, esc, formatTime, icons, playlistCard, row, signInPrompt, songTable
} from '../ui.js';

const noNavidrome = () => signInPrompt('Navidrome', 'Sign in to your Navidrome server to play your music here.');

export async function musicView() {
  const nd = state.nd;
  if (!nd) return noNavidrome();
  try {
    const [newest, recent, frequent, random, playlists, artists] = await Promise.all([
      nd.albumList('newest'),
      nd.albumList('recent'),
      nd.albumList('frequent'),
      nd.albumList('random'),
      nd.playlists(),
      nd.artists()
    ]);
    const featured = random[0] ?? newest[0];
    const topArtists = [...artists].sort((a, b) => (b.albumCount ?? 0) - (a.albumCount ?? 0)).slice(0, 24);
    const seeAll = `<a class="row-link" href="#/artists">See all ${icons.chevronRight}</a>`;
    return `
      ${featured ? musicHero(featured) : '<div class="hero-spacer"></div>'}
      <div class="rows ${featured ? 'over-hero' : ''}">
        ${albumRow('Recently Added', newest)}
        ${albumRow('Recently Played', recent)}
        ${row('Playlists', playlists.map(playlistCard))}
        ${row('Artists', topArtists.map(artistCard), { extra: seeAll, kind: 'artist-row' })}
        ${albumRow('Most Played', frequent)}
        ${albumRow('Random Picks', random.slice(1))}
      </div>`;
  } catch (error) {
    return `<div class="hero-spacer"></div>${errorBanner(error.message)}`;
  }
}

function musicHero(album) {
  const cover = state.nd.coverURL(album.coverArt, 800);
  return `
    <section class="hero music-hero" style="--hero-image:url('${esc(cover ?? '')}')">
      <div class="hero-shade"></div>
      <div class="hero-content music-hero-content">
        <a class="hero-cover" href="#/album/${esc(album.id)}"><img src="${esc(cover ?? '')}" alt=""></a>
        <div>
          <div class="eyebrow">Featured album</div>
          <h1 class="hero-title">${esc(album.name)}</h1>
          <div class="meta"><span>${esc(album.artist ?? '')}</span>${album.year ? `<span>${esc(album.year)}</span>` : ''}</div>
          <div class="hero-buttons">
            <button class="btn btn-primary" data-play-album="${esc(album.id)}">${icons.play}<span>Play</span></button>
            <button class="btn btn-secondary" data-play-album="${esc(album.id)}" data-shuffle="1">${icons.shuffle}<span>Shuffle</span></button>
          </div>
        </div>
      </div>
    </section>`;
}

function collectionHeader({ cover, round = false, eyebrow, title, subtitleHTML, songs }) {
  const listId = registerSongList(songs);
  return `
    <section class="collection-head" style="--hero-image:url('${esc(cover ?? '')}')">
      <div class="collection-shade"></div>
      <div class="collection-inner">
        <div class="collection-cover ${round ? 'round' : ''}">
          <span class="img-box"><span class="img-fallback">${esc(title.slice(0, 1))}</span>${cover ? `<img src="${esc(cover)}" alt="">` : ''}</span>
        </div>
        <div class="collection-text">
          <div class="eyebrow">${esc(eyebrow)}</div>
          <h1>${esc(title)}</h1>
          <div class="meta">${subtitleHTML}</div>
          <div class="hero-buttons">
            <button class="btn btn-primary" data-play-list="${listId}" ${songs.length ? '' : 'disabled'}>${icons.play}<span>Play</span></button>
            <button class="btn btn-secondary" data-play-list="${listId}" data-shuffle="1" ${songs.length ? '' : 'disabled'}>${icons.shuffle}<span>Shuffle</span></button>
          </div>
        </div>
      </div>
    </section>`;
}

const totalTime = (songs) => formatTime(songs.reduce((sum, song) => sum + (song.duration ?? 0), 0));

export async function albumView(id) {
  const nd = state.nd;
  if (!nd) return noNavidrome();
  try {
    const album = await nd.album(id);
    if (!album) return `<div class="hero-spacer"></div>${errorBanner('Album not found.')}`;
    const songs = album.song ?? [];
    const artist = album.artistId
      ? `<a href="#/artist/${esc(album.artistId)}">${esc(album.artist ?? '')}</a>`
      : `<span>${esc(album.artist ?? '')}</span>`;
    const subtitle = [artist, album.year ? `<span>${esc(album.year)}</span>` : '', `<span>${songs.length} songs · ${totalTime(songs)}</span>`].join('');
    return `
      ${collectionHeader({ cover: nd.coverURL(album.coverArt, 600), eyebrow: 'Album', title: album.name ?? 'Album', subtitleHTML: subtitle, songs })}
      <div class="page">${songTable(songs)}</div>`;
  } catch (error) {
    return `<div class="hero-spacer"></div>${errorBanner(error.message)}`;
  }
}

export async function playlistView(id) {
  const nd = state.nd;
  if (!nd) return noNavidrome();
  try {
    const playlist = await nd.playlist(id);
    if (!playlist) return `<div class="hero-spacer"></div>${errorBanner('Playlist not found.')}`;
    const songs = playlist.entry ?? [];
    return `
      ${collectionHeader({ cover: nd.coverURL(playlist.coverArt, 600), eyebrow: 'Playlist', title: playlist.name, subtitleHTML: `<span>${songs.length} songs · ${totalTime(songs)}</span>`, songs })}
      <div class="page">${songTable(songs, { artwork: true, numbered: false })}</div>`;
  } catch (error) {
    return `<div class="hero-spacer"></div>${errorBanner(error.message)}`;
  }
}

export async function artistView(id) {
  const nd = state.nd;
  if (!nd) return noNavidrome();
  try {
    const artist = await nd.artist(id);
    if (!artist) return `<div class="hero-spacer"></div>${errorBanner('Artist not found.')}`;
    const albums = artist.album ?? [];
    // Collect the artist's songs for Play / Shuffle (up to 20 albums).
    const details = await Promise.all(albums.slice(0, 20).map((album) => nd.album(album.id).catch(() => null)));
    const songs = details.flatMap((album) => album?.song ?? []);
    return `
      ${collectionHeader({ cover: nd.coverURL(artist.coverArt, 600), round: true, eyebrow: 'Artist', title: artist.name, subtitleHTML: `<span>${albums.length} albums · ${songs.length} songs</span>`, songs })}
      <div class="page">
        <h2 class="section-title">Albums</h2>
        <div class="grid albums-grid">${albums.map(albumCard).join('')}</div>
      </div>`;
  } catch (error) {
    return `<div class="hero-spacer"></div>${errorBanner(error.message)}`;
  }
}

export async function artistsView() {
  const nd = state.nd;
  if (!nd) return noNavidrome();
  try {
    const artists = await nd.artists();
    return {
      html: `
        <div class="page">
          <div class="page-head">
            <h1>Artists</h1>
            <input id="artist-filter" class="text-input" type="search" placeholder="Filter artists" autocomplete="off">
          </div>
          <div class="grid artists-grid" id="artists-grid">${artists.map(artistCard).join('')}</div>
        </div>`,
      mount(root) {
        const input = root.querySelector('#artist-filter');
        const cards = [...root.querySelectorAll('#artists-grid .card')];
        input.addEventListener('input', () => {
          const term = input.value.trim().toLowerCase();
          for (const card of cards) card.hidden = term !== '' && !card.title.toLowerCase().includes(term);
        });
      }
    };
  } catch (error) {
    return `<div class="hero-spacer"></div>${errorBanner(error.message)}`;
  }
}
