export class ApiError extends Error {
  constructor(message, kind = 'error') {
    super(message);
    this.kind = kind;
  }
}

/** Trims, adds http:// when no scheme was typed and drops trailing slashes. */
export function normalizeServer(raw) {
  let address = String(raw ?? '').trim();
  if (!/^https?:\/\//i.test(address)) address = `http://${address}`;
  return address.replace(/\/+$/, '');
}

export function buildURL(base, path, query = {}) {
  const url = new URL(base + path);
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
  }
  return url.toString();
}

export function randomHex(bytes) {
  return Array.from(crypto.getRandomValues(new Uint8Array(bytes)), (b) => b.toString(16).padStart(2, '0')).join('');
}

/** fetch with friendly errors. */
export async function request(url, options = {}) {
  let response;
  try {
    response = await fetch(url, { ...options, signal: options.signal ?? AbortSignal.timeout(20000) });
  } catch (error) {
    if (options.signal?.aborted) throw error;
    if (error?.name === 'TimeoutError') {
      throw new ApiError("The server didn't answer in time. Check that Tailscale is connected.");
    }
    throw new ApiError("Couldn't reach the server. Check that Tailscale is connected and that the address and port are right.");
  }
  if (response.status === 401 || response.status === 403) {
    throw new ApiError('Wrong username or password, or your sign-in has expired. Sign in again in Settings.', 'auth');
  }
  if (!response.ok) throw new ApiError(`The server answered with an error (HTTP ${response.status}).`);
  return response;
}
