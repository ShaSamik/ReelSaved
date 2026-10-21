import { ExtractionError, SAFARI_USER_AGENT } from './types';

const HOSTS = new Set([
  'instagram.com',
  'www.instagram.com',
  'm.instagram.com',
  'instagr.am',
]);

/** Path prefixes that carry a shortcode directly. `p` is included because
 *  reels shared from the feed often use it. */
const DIRECT_PREFIXES = new Set(['reel', 'reels', 'p', 'tv']);

const SHORTCODE_CHARS = /^[A-Za-z0-9_-]+$/;

function parts(url: URL): string[] {
  return url.pathname.split('/').filter((p) => p.length > 0);
}

export function isInstagram(raw: string): boolean {
  try {
    return HOSTS.has(new URL(raw).hostname.toLowerCase());
  } catch {
    return false;
  }
}

/** True for the `/share/...` redirect links the Instagram app produces. */
export function isShareLink(raw: string): boolean {
  if (!isInstagram(raw)) return false;
  return parts(new URL(raw)).some((p) => p.toLowerCase() === 'share');
}

/**
 * Pulls the shortcode out of a canonical URL.
 *
 * Returns null for `/share/` links, which carry an opaque token rather than a
 * shortcode and have to be resolved over the network first.
 */
export function shortcodeFrom(raw: string): string | null {
  if (!isInstagram(raw)) return null;
  // A /share/ token sits in the same position as a shortcode but is not one.
  if (isShareLink(raw)) return null;

  const segments = parts(new URL(raw));

  // /reel/{code}/ or /p/{code}/
  if (segments.length >= 2 && DIRECT_PREFIXES.has(segments[0].toLowerCase())) {
    return sanitise(segments[1]);
  }
  // /{username}/reel/{code}/
  if (segments.length >= 3 && DIRECT_PREFIXES.has(segments[1].toLowerCase())) {
    return sanitise(segments[2]);
  }
  return null;
}

function sanitise(raw: string): string | null {
  return SHORTCODE_CHARS.test(raw) ? raw : null;
}

/** The lightweight embed page, far more permissive than the main page for
 *  logged-out clients. */
export function embedUrl(shortcode: string): string {
  return `https://www.instagram.com/reel/${shortcode}/embed/captioned/`;
}

/** Follows a `/share/` link to the canonical URL it redirects to. */
export async function resolveShareLink(raw: string): Promise<string> {
  try {
    const response = await fetch(raw, {
      method: 'GET',
      headers: { 'User-Agent': SAFARI_USER_AGENT },
    });
    // fetch follows redirects, so the final URL is on the response.
    if (!response.url || response.url === raw) {
      throw new ExtractionError('mediaNotFound');
    }
    return response.url;
  } catch (error) {
    if (error instanceof ExtractionError) throw error;
    throw new ExtractionError('network', (error as Error).message);
  }
}
