import {
  ExtractedMedia,
  ExtractionError,
  MediaExtractor,
  SAFARI_USER_AGENT,
} from './types';
import { embedUrl, isInstagram, isShareLink, resolveShareLink, shortcodeFrom } from './instagramUrl';

// Ordered most-specific first. The JSON keys are reliable when present; the
// og: meta tags are the fallback that survives most redesigns.
export const VIDEO_PATTERNS = [
  /"video_url"\s*:\s*"([^"]+)"/,
  /"video_versions"\s*:\s*\[\s*\{[^}]*?"url"\s*:\s*"([^"]+)"/,
  /<meta[^>]+property="og:video"[^>]+content="([^"]+)"/,
  /<meta[^>]+content="([^"]+)"[^>]+property="og:video"/,
  /<video[^>]+src="([^"]+)"/,
];

export const THUMBNAIL_PATTERNS = [
  /"display_url"\s*:\s*"([^"]+)"/,
  /<meta[^>]+property="og:image"[^>]+content="([^"]+)"/,
];

export const AUTHOR_PATTERNS = [
  /"owner"\s*:\s*\{[^}]*?"username"\s*:\s*"([^"]+)"/,
  /"username"\s*:\s*"([^"]+)"/,
];

export const CAPTION_PATTERNS = [
  /<meta[^>]+property="og:description"[^>]+content="([^"]+)"/,
];

/**
 * Collapses the layered escaping Instagram wraps its JSON in.
 *
 * The payload sits in a JS string inside HTML, so a slash can arrive as `\\\/`
 * and a quote as `\"`. One pass isn't enough — unescaping `\\\/` yields `\/`,
 * which still needs another — so repeat until it settles. Five rounds is well
 * past any nesting seen in practice and bounds the work.
 */
export function unescape(raw: string): string {
  let value = raw;
  for (let i = 0; i < 5; i += 1) {
    const before = value;
    value = value
      .replaceAll('\\\\', '\\')
      .replaceAll('\\/', '/')
      .replaceAll('\\"', '"');
    if (value === before) break;
  }

  value = value
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

  // Decode \uXXXX sequences.
  return value.replace(/\\u([0-9a-fA-F]{4})/g, (_, hex) =>
    String.fromCharCode(parseInt(hex, 16)),
  );
}

/** Runs patterns in order, returning the first capture group that matches. */
export function firstMatch(patterns: RegExp[], html: string): string | undefined {
  for (const pattern of patterns) {
    const match = pattern.exec(html);
    if (match && match[1]) {
      const value = unescape(match[1]);
      if (value.length > 0) return value;
    }
  }
  return undefined;
}

/**
 * Turns embed-page markup into media, with no network involved.
 *
 * Split out from the fetch so it can be pinned to a recorded response. This is
 * the part Instagram breaks, and the part worth testing.
 */
export function parse(html: string, shortcode: string): ExtractedMedia {
  // A login wall comes back as a real page, not an HTTP error.
  if (html.includes('loginForm') || html.includes('Log in to Instagram')) {
    throw new ExtractionError('loginRequired');
  }
  // Instagram serves a 200 with this marker when the reel is deleted,
  // private, or the shortcode is simply wrong.
  if (html.includes('EmbedBrokenMedia')) {
    throw new ExtractionError('unavailable');
  }

  // The post JSON is embedded in a JavaScript string literal, so it is escaped
  // twice. Collapsing the whole document first lets one set of plain patterns
  // match both that and singly-escaped older responses.
  const normalized = unescape(html);
  const find = (patterns: RegExp[]) =>
    firstMatch(patterns, html) ?? firstMatch(patterns, normalized);

  const mediaUrl = find(VIDEO_PATTERNS);
  if (!mediaUrl) throw new ExtractionError('mediaNotFound');

  return {
    mediaUrl,
    thumbnailUrl: find(THUMBNAIL_PATTERNS),
    author: find(AUTHOR_PATTERNS),
    caption: find(CAPTION_PATTERNS),
    shortcode,
  };
}

/**
 * Fetches Instagram's embed page and scrapes the video URL out of it.
 *
 * The fast path: one GET, no browser engine. The embed page exists to be
 * rendered by third-party sites, so it is served to logged-out clients when
 * the main page is not.
 */
export class EmbedHtmlExtractor implements MediaExtractor {
  async extract(url: string): Promise<ExtractedMedia> {
    const canonical = isShareLink(url) ? await resolveShareLink(url) : url;

    if (!isInstagram(canonical)) throw new ExtractionError('unsupportedUrl');
    const shortcode = shortcodeFrom(canonical);
    if (!shortcode) throw new ExtractionError('notAReel');

    const html = await this.fetchHtml(embedUrl(shortcode));
    return parse(html, shortcode);
  }

  private async fetchHtml(url: string): Promise<string> {
    let response: Response;
    try {
      response = await fetch(url, {
        headers: {
          'User-Agent': SAFARI_USER_AGENT,
          'Accept-Language': 'en-US,en;q=0.9',
        },
      });
    } catch (error) {
      throw new ExtractionError('network', (error as Error).message);
    }

    if (!response.ok) {
      if (response.status === 401 || response.status === 403) {
        throw new ExtractionError('loginRequired');
      }
      throw new ExtractionError('network', `Instagram returned ${response.status}.`);
    }
    return response.text();
  }
}

/**
 * Tries each extractor in order and returns the first success.
 *
 * Instagram serves different markup to different clients, so a cheap fetch
 * works often but not always.
 */
export class ChainedExtractor implements MediaExtractor {
  private readonly extractors: MediaExtractor[];

  constructor(extractors: MediaExtractor[]) {
    this.extractors = extractors;
  }

  async extract(url: string): Promise<ExtractedMedia> {
    let lastError: unknown = new ExtractionError('mediaNotFound');

    for (const extractor of this.extractors) {
      try {
        return await extractor.extract(url);
      } catch (error) {
        // These won't resolve by trying a different parser.
        if (
          error instanceof ExtractionError &&
          ['loginRequired', 'unsupportedUrl', 'unavailable'].includes(error.kind)
        ) {
          throw error;
        }
        lastError = error;
      }
    }
    throw lastError;
  }
}
