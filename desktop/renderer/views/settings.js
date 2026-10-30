// Server addresses and accounts for Jellyfin and Navidrome.
import { Jellyfin } from '../api/jellyfin.js';
import { MUSIC_QUALITIES, Subsonic, savedMusicQuality } from '../api/subsonic.js';
import { state } from '../state.js';
import { esc } from '../ui.js';

const SERVICES = {
  jellyfin: {
    title: 'Jellyfin',
    subtitle: 'Movies & TV',
    placeholder: 'http://100.x.x.x:8096',
    help: 'The address you open Jellyfin with in a browser, for example http://100.x.x.x:30013 (your NAS’s Tailscale address and the app’s port).'
  },
  navidrome: {
    title: 'Navidrome',
    subtitle: 'Music',
    placeholder: 'http://100.x.x.x:4533',
    help: 'The address you open Navidrome with in a browser, for example http://100.x.x.x:30043.'
  }
};

function card(key) {
  const service = SERVICES[key];
  const session = state.accounts[key];
  const lastURL = localStorage.getItem(`hearth.last.${key}`) ?? '';
  const body = session
    ? `
      <dl class="account">
        <dt>Server</dt><dd>${esc(session.serverURL)}</dd>
        <dt>Signed in as</dt><dd>${esc(session.username)}</dd>
      </dl>
      <button class="btn btn-danger" data-signout="${key}">Sign out</button>`
    : `
      <form class="signin" data-signin="${key}">
        <label>Server address<input name="server" class="text-input" required placeholder="${esc(service.placeholder)}" value="${esc(lastURL)}" autocomplete="off" spellcheck="false"></label>
        <label>Username<input name="username" class="text-input" required autocomplete="username" spellcheck="false"></label>
        <label>Password<input name="password" class="text-input" type="password" autocomplete="current-password"></label>
        <p class="form-error" hidden></p>
        <button class="btn btn-primary" type="submit">Sign in</button>
      </form>`;
  return `
    <section class="settings-card">
      <h2>${esc(service.title)} <span class="muted">· ${esc(service.subtitle)}</span></h2>
      <p class="muted small">${esc(service.help)}</p>
      ${body}
    </section>`;
}

export function settingsView({ onAccountsChanged }) {
  return {
    html: `
      <div class="page settings-page">
        <h1>Settings</h1>
        ${card('jellyfin')}
        ${card('navidrome')}
        <section class="settings-card">
          <h2>Music quality</h2>
          <p class="muted small">Original plays your files as they are, so FLAC stays lossless. The kbps options are converted to MP3 by Navidrome and use less bandwidth. Applies from the next song.</p>
          <select id="music-quality">
            ${MUSIC_QUALITIES.map((quality) => `<option value="${quality.value}" ${quality.value === savedMusicQuality().value ? 'selected' : ''}>${esc(quality.label)}</option>`).join('')}
          </select>
        </section>
        <section class="settings-card">
          <h2>About</h2>
          <p class="muted small">Hearth only talks to your own servers. Make sure Tailscale is connected on this computer.
          Sign-ins are encrypted with ${window.hearth.platform === 'win32' ? 'Windows' : 'your system’s'} secure storage.
          For Jellyfin only a sign-in token is kept, never your password.</p>
        </section>
      </div>`,
    mount(root) {
      root.querySelector('#music-quality').addEventListener('change', (event) => {
        localStorage.setItem('hearth.musicQuality', event.target.value);
      });
      root.addEventListener('submit', async (event) => {
        const form = event.target.closest('form[data-signin]');
        if (!form) return;
        event.preventDefault();
        const key = form.dataset.signin;
        const button = form.querySelector('button[type=submit]');
        const errorEl = form.querySelector('.form-error');
        const data = new FormData(form);
        button.disabled = true;
        button.textContent = 'Signing in…';
        errorEl.hidden = true;
        try {
          const server = String(data.get('server'));
          const username = String(data.get('username'));
          const password = String(data.get('password'));
          const session = key === 'jellyfin'
            ? await Jellyfin.signIn(server, username, password)
            : await Subsonic.signIn(server, username, password);
          localStorage.setItem(`hearth.last.${key}`, session.serverURL);
          await onAccountsChanged({ ...state.accounts, [key]: session });
        } catch (error) {
          errorEl.textContent = error.message;
          errorEl.hidden = false;
          button.disabled = false;
          button.textContent = 'Sign in';
        }
      });
      root.addEventListener('click', async (event) => {
        const key = event.target.closest('[data-signout]')?.dataset.signout;
        if (!key) return;
        if (key === 'jellyfin') state.jf?.logout();
        const next = { ...state.accounts };
        delete next[key];
        await onAccountsChanged(next);
      });
    }
  };
}
