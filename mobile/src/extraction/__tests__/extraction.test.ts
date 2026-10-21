import { readFileSync } from 'fs';
import { join } from 'path';

import { isShareLink, shortcodeFrom } from '../instagramUrl';
import { parse, unescape } from '../embedExtractor';
import { ExtractionError } from '../types';

const fixture = (name: string) =>
  readFileSync(join(__dirname, 'fixtures', `${name}.html`), 'utf8');

describe('Instagram URL parsing', () => {
  test('shortcode is read from every canonical link shape', () => {
    const cases: [string, string][] = [
      ['https://www.instagram.com/reel/Cx1AbC-dEf_/', 'Cx1AbC-dEf_'],
      ['https://instagram.com/reel/Cx1AbC/?igsh=abc123', 'Cx1AbC'],
      ['https://www.instagram.com/reels/Cx1AbC/', 'Cx1AbC'],
      ['https://www.instagram.com/p/Cx1AbC/', 'Cx1AbC'],
      ['https://www.instagram.com/someuser/reel/Cx1AbC/', 'Cx1AbC'],
      ['https://m.instagram.com/reel/Cx1AbC/', 'Cx1AbC'],
    ];
    for (const [link, expected] of cases) {
      expect(shortcodeFrom(link)).toBe(expected);
    }
  });

  test('non-reel and non-Instagram links yield no shortcode', () => {
    for (const link of [
      'https://www.instagram.com/someuser/',
      'https://youtube.com/watch?v=abc',
      'https://example.com/reel/Cx1AbC/',
      'not a url at all',
    ]) {
      expect(shortcodeFrom(link)).toBeNull();
    }
  });

  // Regression: `/share/reel/{token}/` matched the `/{user}/reel/{code}/`
  // rule, so the opaque token was mistaken for a shortcode and the redirect
  // was never followed. Every reel shared from the Instagram app failed.
  test('share links are not mistaken for shortcodes', () => {
    const url = 'https://www.instagram.com/share/reel/_xYz123/';
    expect(isShareLink(url)).toBe(true);
    expect(shortcodeFrom(url)).toBeNull();
  });

  test('query parameters are stripped from the shortcode', () => {
    expect(
      shortcodeFrom('https://www.instagram.com/reel/DeHtg27jeRl/?exln=MWlmMzkyaTFkNHhmdQ=='),
    ).toBe('DeHtg27jeRl');
  });
});

describe('Embed page parsing', () => {
  // The bug that made every download fail: Instagram nests its JSON in a
  // JavaScript string, so one unescape pass turns `\\\/` into `\/` — still
  // not a slash. Unescaping has to repeat until the string settles.
  test('escaping is collapsed however many layers deep it is', () => {
    expect(unescape('https:\\/\\/cdn.example\\/v.mp4')).toBe('https://cdn.example/v.mp4');
    expect(unescape('https:\\\\\\/\\\\\\/cdn.example\\\\\\/v.mp4')).toBe('https://cdn.example/v.mp4');
    expect(unescape('a\\"b')).toBe('a"b');
  });

  test('html entities and unicode escapes are decoded', () => {
    expect(unescape('a&amp;b&quot;c')).toBe('a&b"c');
    expect(unescape('caf\\u00e9 \\u2728')).toBe('café ✨');
  });

  // Pinned to a real response. If Instagram reshapes its markup, this fails
  // here rather than silently returning "couldn't find a video" on device.
  test('a recorded live response still parses', () => {
    const media = parse(fixture('embed-reel'), 'DeHtg27jeRl');

    expect(media.shortcode).toBe('DeHtg27jeRl');
    expect(media.author).toBe('v8roll');
    expect(media.mediaUrl).toMatch(/^https:\/\//);
    expect(media.mediaUrl).toMatch(/cdninstagram\.com/);
    expect(media.mediaUrl).toMatch(/\.mp4/);
    expect(media.thumbnailUrl ?? '').toMatch(/^https:\/\//);

    // A slash that survived as a backslash means the unescaper regressed.
    expect(!media.mediaUrl.includes('\\')).toBe(true);
  });

  test('a deleted or private reel is reported as unavailable', () => {
    expect(() =>
      parse('<html><body><div class="EmbedBrokenMedia">x</div></body></html>', 'abc'),
    ).toThrow(expect.objectContaining({ kind: 'unavailable' }));
  });

  test('a login wall is reported as needing a login', () => {
    expect(() =>
      parse('<html><body><form id="loginForm"></form></body></html>', 'abc'),
    ).toThrow(expect.objectContaining({ kind: 'loginRequired' }));
  });

  test('markup with no video is reported as not found', () => {
    expect(() => parse('<html><body>nothing</body></html>', 'abc')).toThrow(expect.objectContaining({ kind: 'mediaNotFound' }));
  });
});
