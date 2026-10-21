import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { isShareLink, shortcodeFrom } from '../instagramUrl';
import { parse, unescape } from '../embedExtractor';
import { ExtractionError } from '../types';

const here = dirname(fileURLToPath(import.meta.url));
const fixture = (name: string) =>
  readFileSync(join(here, 'fixtures', `${name}.html`), 'utf8');

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
      assert.equal(shortcodeFrom(link), expected, link);
    }
  });

  test('non-reel and non-Instagram links yield no shortcode', () => {
    for (const link of [
      'https://www.instagram.com/someuser/',
      'https://youtube.com/watch?v=abc',
      'https://example.com/reel/Cx1AbC/',
      'not a url at all',
    ]) {
      assert.equal(shortcodeFrom(link), null, link);
    }
  });

  // Regression: `/share/reel/{token}/` matched the `/{user}/reel/{code}/`
  // rule, so the opaque token was mistaken for a shortcode and the redirect
  // was never followed. Every reel shared from the Instagram app failed.
  test('share links are not mistaken for shortcodes', () => {
    const url = 'https://www.instagram.com/share/reel/_xYz123/';
    assert.equal(isShareLink(url), true);
    assert.equal(shortcodeFrom(url), null);
  });

  test('query parameters are stripped from the shortcode', () => {
    assert.equal(
      shortcodeFrom('https://www.instagram.com/reel/DeHtg27jeRl/?exln=MWlmMzkyaTFkNHhmdQ=='),
      'DeHtg27jeRl',
    );
  });
});

describe('Embed page parsing', () => {
  // The bug that made every download fail: Instagram nests its JSON in a
  // JavaScript string, so one unescape pass turns `\\\/` into `\/` — still
  // not a slash. Unescaping has to repeat until the string settles.
  test('escaping is collapsed however many layers deep it is', () => {
    assert.equal(unescape('https:\\/\\/cdn.example\\/v.mp4'), 'https://cdn.example/v.mp4');
    assert.equal(unescape('https:\\\\\\/\\\\\\/cdn.example\\\\\\/v.mp4'), 'https://cdn.example/v.mp4');
    assert.equal(unescape('a\\"b'), 'a"b');
  });

  test('html entities and unicode escapes are decoded', () => {
    assert.equal(unescape('a&amp;b&quot;c'), 'a&b"c');
    assert.equal(unescape('caf\\u00e9 \\u2728'), 'café ✨');
  });

  // Pinned to a real response. If Instagram reshapes its markup, this fails
  // here rather than silently returning "couldn't find a video" on device.
  test('a recorded live response still parses', () => {
    const media = parse(fixture('embed-reel'), 'DeHtg27jeRl');

    assert.equal(media.shortcode, 'DeHtg27jeRl');
    assert.equal(media.author, 'v8roll');
    assert.match(media.mediaUrl, /^https:\/\//);
    assert.match(media.mediaUrl, /cdninstagram\.com/);
    assert.match(media.mediaUrl, /\.mp4/);
    assert.match(media.thumbnailUrl ?? '', /^https:\/\//);

    // A slash that survived as a backslash means the unescaper regressed.
    assert.ok(!media.mediaUrl.includes('\\'), 'media URL still contains a backslash');
  });

  test('a deleted or private reel is reported as unavailable', () => {
    assert.throws(
      () => parse('<html><body><div class="EmbedBrokenMedia">x</div></body></html>', 'abc'),
      (e: unknown) => e instanceof ExtractionError && e.kind === 'unavailable',
    );
  });

  test('a login wall is reported as needing a login', () => {
    assert.throws(
      () => parse('<html><body><form id="loginForm"></form></body></html>', 'abc'),
      (e: unknown) => e instanceof ExtractionError && e.kind === 'loginRequired',
    );
  });

  test('markup with no video is reported as not found', () => {
    assert.throws(
      () => parse('<html><body>nothing</body></html>', 'abc'),
      (e: unknown) => e instanceof ExtractionError && e.kind === 'mediaNotFound',
    );
  });
});
