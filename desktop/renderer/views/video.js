// Home, Movies, TV Shows, "Browse all" and the title page, all from Jellyfin.
import { episodeLabel, progressOf, runtimeText } from '../api/jellyfin.js';
import { itemCache, state } from '../state.js';
import {
  albumRow, errorBanner, esc, icons, landscapeCard, posterCard, posterRow, row, signInPrompt, spinner, videoHero
} from '../ui.js';

const LIBRARIES = {
  movies: { title: 'Movies', type: 'Movie' },
  shows: { title: 'TV Shows', type: 'Series' }
};

const noJellyfin = () => signInPrompt('Jellyfin', 'Sign in to your Jellyfin server to see your movies and shows here.');

/** Half-watched titles first, then the next episode of shows you're following. */
function mergeContinue(resume, nextUp) {
  const seen = new Set(resume.map((item) => item.SeriesId ?? item.Id));
  const result = [...resume];
  for (const episode of nextUp) {
    const key = episode.SeriesId ?? episode.Id;
    if (!seen.has(key)) {
      seen.add(key);
      result.push(episode);
    }
  }
  return result;
}

export async function homeView() {
  const jf = state.jf;
  if (!jf) {
    if (state.nd) location.hash = '#/music';
    return noJellyfin();
  }
  try {
    const [resume, nextUp, movies, shows, featured, genres, albums] = await Promise.all([
      jf.resumeItems(),
      jf.nextUp(20),
      jf.latest('Movie'),
      jf.latest('Series'),
      jf.featured('Movie,Series'),
      jf.genreRows('Movie,Series', 6),
      state.nd ? state.nd.albumList('newest', 24).catch(() => []) : Promise.resolve([])
    ]);
    const hero = featured[0];
    return `
      ${hero ? videoHero(hero) : '<div class="hero-spacer"></div>'}
      <div class="rows ${hero ? 'over-hero' : ''}">
        ${row('Continue Watching', mergeContinue(resume, nextUp).map(landscapeCard), { kind: 'landscape-row' })}
        ${posterRow('Recently Added Movies', movies)}
        ${posterRow('Recently Added Shows', shows)}
        ${genres.map((genre) => posterRow(genre.title, genre.items)).join('')}
        ${albumRow('New Music', albums)}
      </div>`;
  } catch (error) {
    return `<div class="hero-spacer"></div>${errorBanner(error.message)}`;
  }
}

export async function libraryView(kind) {
  const jf = state.jf;
  const library = LIBRARIES[kind];
  if (!jf) return noJellyfin();
  try {
    const [featured, latest, genres] = await Promise.all([
      jf.featured(library.type),
      jf.latest(library.type),
      jf.genreRows(library.type, 10)
    ]);
    const hero = featured[0];
    const browse = `<a class="row-link" href="#/browse/${kind}">Browse all ${esc(library.title.toLowerCase())} ${icons.chevronRight}</a>`;
    return `
      ${hero ? videoHero(hero) : '<div class="hero-spacer"></div>'}
      <div class="rows ${hero ? 'over-hero' : ''}">
        ${row('Recently Added', latest.map(posterCard), { extra: browse })}
        ${genres.map((genre) => posterRow(genre.title, genre.items)).join('')}
      </div>`;
  } catch (error) {
    return `<div class="hero-spacer"></div>${errorBanner(error.message)}`;
  }
}

const SORTS = {
  name: { label: 'A–Z', sortBy: 'SortName', descending: false },
  added: { label: 'Recently added', sortBy: 'DateCreated,SortName', descending: true },
  year: { label: 'Release year', sortBy: 'ProductionYear,SortName', descending: true },
  rating: { label: 'Rating', sortBy: 'CommunityRating,SortName', descending: true }
};

/** Every movie or show as a poster grid, loaded page by page as you scroll. */
export function browseView(kind) {
  const library = LIBRARIES[kind];
  if (!state.jf || !library) return noJellyfin();
  const options = Object.entries(SORTS).map(([key, sort]) => `<option value="${key}">${esc(sort.label)}</option>`).join('');
  return {
    html: `
      <div class="page">
        <div class="page-head">
          <h1>${esc(library.title)}</h1>
          <label class="select-label">Sort by <select id="browse-sort">${options}</select></label>
        </div>
        <div class="grid" id="browse-grid"></div>
        <div id="browse-sentinel">${spinner()}</div>
      </div>`,
    mount(root, isCurrent) {
      const grid = root.querySelector('#browse-grid');
      const sentinel = root.querySelector('#browse-sentinel');
      const select = root.querySelector('#browse-sort');
      let sortKey = sessionStorage.getItem(`hearth.sort.${kind}`) || 'name';
      select.value = sortKey;
      let loaded = 0;
      let total = Infinity;
      let loading = false;
      let generation = 0;

      async function loadMore() {
        if (loading || loaded >= total || !isCurrent()) return;
        loading = true;
        const mine = generation;
        const sort = SORTS[sortKey];
        try {
          const page = await state.jf.browse({ includeTypes: library.type, sortBy: sort.sortBy, descending: sort.descending, start: loaded, limit: 60 });
          if (mine !== generation || !isCurrent()) return;
          const items = page?.Items ?? [];
          grid.insertAdjacentHTML('beforeend', items.map(posterCard).join(''));
          loaded += items.length;
          total = page?.TotalRecordCount ?? loaded;
          if (loaded >= total) sentinel.innerHTML = '';
        } catch (error) {
          sentinel.innerHTML = errorBanner(error.message);
          total = loaded;
        } finally {
          loading = false;
        }
        if (sentinel.getBoundingClientRect().top < window.innerHeight + 400) loadMore();
      }

      new IntersectionObserver((entries) => {
        if (entries.some((entry) => entry.isIntersecting)) loadMore();
      }, { rootMargin: '600px' }).observe(sentinel);

      select.addEventListener('change', () => {
        sortKey = select.value;
        sessionStorage.setItem(`hearth.sort.${kind}`, sortKey);
        generation += 1;
        grid.innerHTML = '';
        sentinel.innerHTML = spinner();
        loaded = 0;
        total = Infinity;
        loading = false;
        loadMore();
      });
      loadMore();
    }
  };
}

/** Title page: backdrop, synopsis, Play, seasons and episodes, and similar titles. */
export async function titleView(id) {
  const jf = state.jf;
  if (!jf) return noJellyfin();
  let item;
  try {
    item = await jf.item(id);
  } catch (error) {
    return `<div class="hero-spacer"></div>${errorBanner(error.message)}`;
  }
  if (!item) return `<div class="hero-spacer"></div>${errorBanner('This title could not be found.')}`;
  itemCache.set(item.Id, item);

  const isSeries = item.Type === 'Series';
  const [seasons, nextUp, similar] = await Promise.all([
    isSeries ? jf.seasons(item.Id).catch(() => []) : Promise.resolve([]),
    isSeries ? jf.nextUpFor(item.Id).catch(() => null) : Promise.resolve(null),
    jf.similar(item.Id).catch(() => [])
  ]);
  if (nextUp) itemCache.set(nextUp.Id, nextUp);

  const target = isSeries ? nextUp : item;
  const resuming = target && progressOf(target);
  let playLabel = resuming ? 'Resume' : 'Play';
  if (isSeries && nextUp) playLabel += ` ${episodeLabel(nextUp)}`;
  const playId = target?.Id ?? item.Id;

  const meta = [
    item.ProductionYear,
    item.OfficialRating ? `<span class="rating">${esc(item.OfficialRating)}</span>` : '',
    isSeries ? (seasons.length === 1 ? '1 Season' : seasons.length ? `${seasons.length} Seasons` : '') : runtimeText(item),
    item.CommunityRating ? `★ ${item.CommunityRating.toFixed(1)}` : ''
  ].filter(Boolean).map((part) => (String(part).startsWith('<span') ? part : `<span>${esc(part)}</span>`)).join('');

  const logo = jf.logoURL(item);
  const progress = resuming ? `<div class="progress wide"><div style="width:${Math.round(resuming * 100)}%"></div></div>` : '';
  const seasonId = nextUp?.SeasonId ?? seasons[0]?.Id;
  const seasonOptions = seasons.map((season) =>
    `<option value="${esc(season.Id)}" ${season.Id === seasonId ? 'selected' : ''}>${esc(season.Name)}</option>`).join('');

  const html = `
    <section class="hero detail-hero" style="--hero-image:url('${esc(jf.backdropURL(item))}')">
      <div class="hero-shade"></div>
      <div class="hero-content">
        ${item.Type === 'Episode' && item.SeriesName ? `<a class="eyebrow" href="#/title/${esc(item.SeriesId)}">${esc(item.SeriesName)}</a>` : ''}
        ${logo ? `<img class="hero-logo" src="${esc(logo)}" alt="${esc(item.Name)}">` : `<h1 class="hero-title">${esc(item.Name)}</h1>`}
        <div class="meta">${meta}</div>
        <div class="hero-buttons">
          <button class="btn btn-primary" data-play="${esc(playId)}">${icons.play}<span>${esc(playLabel)}</span></button>
        </div>
        ${progress}
        ${item.Overview ? `<p class="hero-overview full">${esc(item.Overview)}</p>` : ''}
        ${item.Genres?.length ? `<div class="genres">Genres: ${esc(item.Genres.join(', '))}</div>` : ''}
      </div>
    </section>
    <div class="rows over-hero">
      ${isSeries && seasons.length ? `
        <section class="episodes">
          <div class="row-head">
            <h2>Episodes</h2>
            ${seasons.length > 1 ? `<select id="season-select">${seasonOptions}</select>` : `<span class="season-name">${esc(seasons[0].Name)}</span>`}
          </div>
          <div id="episode-list">${spinner()}</div>
        </section>` : ''}
      ${row('More Like This', similar.map(posterCard))}
    </div>`;

  return {
    html,
    mount(root, isCurrent) {
      if (!isSeries || !seasons.length) return;
      const list = root.querySelector('#episode-list');
      const select = root.querySelector('#season-select');
      const load = async (season) => {
        list.innerHTML = spinner();
        try {
          const episodes = await jf.episodes(item.Id, season);
          if (!isCurrent()) return;
          list.innerHTML = episodes.map(episodeRow).join('') || '<p class="muted">No episodes in this season.</p>';
        } catch (error) {
          list.innerHTML = errorBanner(error.message);
        }
      };
      select?.addEventListener('change', () => load(select.value));
      load(seasonId);
    }
  };
}

function episodeRow(episode) {
  itemCache.set(episode.Id, episode);
  const progress = progressOf(episode);
  const played = episode.UserData?.Played;
  return `
    <button class="episode" data-play="${esc(episode.Id)}">
      <span class="episode-num">${esc(episode.IndexNumber ?? '')}</span>
      <span class="episode-art">
        <span class="img-box"><span class="img-fallback"></span><img loading="lazy" src="${esc(state.jf.landscapeURL(episode))}" alt=""></span>
        <span class="play-badge">${icons.play}</span>
        ${progress ? `<span class="progress"><span style="width:${Math.round(progress * 100)}%"></span></span>` : ''}
      </span>
      <span class="episode-text">
        <span class="episode-title">${esc(episode.Name)} ${played ? `<span class="watched">${icons.check}</span>` : ''}</span>
        <span class="episode-overview">${esc(episode.Overview ?? '')}</span>
      </span>
      <span class="episode-time">${esc(runtimeText(episode))}</span>
    </button>`;
}
