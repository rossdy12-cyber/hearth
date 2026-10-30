// One search box for both servers.
import { state } from '../state.js';
import { albumRow, artistCard, errorBanner, esc, posterCard, row, songTable, spinner } from '../ui.js';

export function searchView() {
  const initial = sessionStorage.getItem('hearth.search') ?? '';
  return {
    html: `
      <div class="page search-page">
        <div class="search-box">
          <input id="search-input" class="text-input big" type="search" placeholder="Search movies, shows, artists, albums and songs" value="${esc(initial)}" autocomplete="off">
        </div>
        <div id="search-results"></div>
      </div>`,
    mount(root, isCurrent) {
      const input = root.querySelector('#search-input');
      const results = root.querySelector('#search-results');
      let timer = null;
      let generation = 0;

      const hint = (text) => `<div class="empty-state small"><p>${esc(text)}</p></div>`;

      async function run() {
        const term = input.value.trim();
        sessionStorage.setItem('hearth.search', input.value);
        const mine = ++generation;
        if (term.length < 2) {
          results.innerHTML = hint('Type at least two letters.');
          return;
        }
        if (!state.jf && !state.nd) {
          results.innerHTML = hint('Sign in to a server in Settings first.');
          return;
        }
        results.innerHTML = spinner();
        const [videos, music] = await Promise.all([
          state.jf ? state.jf.search(term).catch((error) => error) : [],
          state.nd ? state.nd.search(term).catch((error) => error) : {}
        ]);
        if (mine !== generation || !isCurrent()) return;
        const parts = [];
        if (videos instanceof Error) parts.push(errorBanner(`Jellyfin: ${videos.message}`));
        else if (videos.length) {
          parts.push(`<section class="row"><div class="row-head"><h2>Movies &amp; TV</h2></div><div class="grid">${videos.map(posterCard).join('')}</div></section>`);
        }
        if (music instanceof Error) parts.push(errorBanner(`Navidrome: ${music.message}`));
        else {
          parts.push(row('Artists', (music.artist ?? []).map(artistCard), { kind: 'artist-row' }));
          parts.push(albumRow('Albums', music.album ?? []));
          if (music.song?.length) {
            parts.push(`<section class="row"><div class="row-head"><h2>Songs</h2></div><div class="page-inner">${songTable(music.song, { artwork: true, numbered: false })}</div></section>`);
          }
        }
        const html = parts.join('');
        results.innerHTML = html.trim() ? html : hint(`Nothing found for “${term}”.`);
      }

      input.addEventListener('input', () => {
        clearTimeout(timer);
        timer = setTimeout(run, 300);
      });
      input.focus();
      run();
    }
  };
}
