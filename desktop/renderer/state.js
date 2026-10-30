import { AudioPlayer } from './player/audio.js';

/** Shared app state: the signed-in clients, the music player and lookup tables for click handlers. */
export const state = {
  accounts: {},
  jf: null,
  nd: null
};

export const audio = new AudioPlayer();

/** Jellyfin items by id, filled as cards are drawn, so a click can find the full item. */
export const itemCache = new Map();

/** Song lists by id, so a click on a track can play the whole list from there. */
export const songLists = new Map();
let nextListId = 1;

export function registerSongList(songs) {
  const id = String(nextListId++);
  songLists.set(id, songs);
  if (songLists.size > 200) {
    songLists.delete(songLists.keys().next().value);
  }
  return id;
}
