import { File } from 'expo-file-system';
import * as MediaLibrary from 'expo-media-library';

import { ChainedExtractor, EmbedHtmlExtractor } from '../extraction/embedExtractor';
import { ExtractionError, MediaExtractor, SAFARI_USER_AGENT, suggestedFilename } from '../extraction/types';
import { isInstagram, shortcodeFrom } from '../extraction/instagramUrl';
import { deleteMedia, loadLibrary, mediaDirectory, mediaFile, saveLibrary } from './storage';
import { Reel } from './types';

// The chain is assembled here and nowhere else. Swapping in a server-side
// extractor later is a one-line change at this call site.
const extractor: MediaExtractor = new ChainedExtractor([new EmbedHtmlExtractor()]);

let reels: Reel[] = [];
let hydrated = false;
const listeners = new Set<() => void>();
/** Shortcodes currently being worked on, so a double tap can't double-queue. */
const inFlight = new Set<string>();

export function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function getReels(): Reel[] {
  return reels;
}

function commit(next: Reel[], persist = true) {
  reels = next;
  if (persist) void saveLibrary(reels);
  listeners.forEach((l) => l());
}

function patch(shortcode: string, changes: Partial<Reel>, persist = true) {
  commit(
    reels.map((r) => (r.shortcode === shortcode ? { ...r, ...changes } : r)),
    persist,
  );
}

export async function hydrate(): Promise<void> {
  if (hydrated) return;
  hydrated = true;
  const stored = await loadLibrary();
  // Anything caught mid-flight by a previous launch is stale, not running.
  commit(
    stored.map((r) =>
      r.state === 'completed' || r.state === 'failed'
        ? r
        : { ...r, state: 'failed', errorMessage: 'Interrupted — tap to retry.' },
    ),
    false,
  );
}

export async function enqueue(url: string): Promise<void> {
  if (!isInstagram(url)) {
    throw new ExtractionError('unsupportedUrl');
  }
  await process(url);
}

export async function retry(reel: Reel): Promise<void> {
  await process(reel.sourceUrl);
}

export function remove(reel: Reel): void {
  deleteMedia(reel.filename);
  commit(reels.filter((r) => r.shortcode !== reel.shortcode));
}

async function process(url: string): Promise<void> {
  // Before extraction the shortcode may be unknown (a /share/ link), so the
  // URL stands in as the key until we learn the real one.
  const provisional = shortcodeFrom(url) ?? url;
  if (inFlight.has(provisional)) return;
  inFlight.add(provisional);

  if (!reels.some((r) => r.shortcode === provisional)) {
    commit([
      {
        shortcode: provisional,
        sourceUrl: url,
        state: 'extracting',
        createdAt: Date.now(),
        bytesDownloaded: 0,
        bytesExpected: 0,
        savedToLibrary: false,
      },
      ...reels,
    ]);
  } else {
    patch(provisional, { state: 'extracting', errorMessage: undefined });
  }

  let key = provisional;
  try {
    const media = await extractor.extract(url);

    // Extraction may reveal the real shortcode behind a /share/ link.
    if (media.shortcode !== key) {
      const resolved = media.shortcode;
      commit(reels.map((r) => (r.shortcode === key ? { ...r, shortcode: resolved } : r)), false);
      inFlight.delete(key);
      inFlight.add(resolved);
      key = resolved;
    }

    patch(key, {
      author: media.author,
      caption: media.caption,
      thumbnailUrl: media.thumbnailUrl,
      state: 'downloading',
    });

    const filename = suggestedFilename(media);
    const destination = mediaFile(filename);
    if (destination.exists) destination.delete();

    await File.downloadFileAsync(media.mediaUrl, mediaDirectory(), {
      headers: {
        'User-Agent': SAFARI_USER_AGENT,
        // Instagram's CDN rejects media requests without a plausible referer.
        Referer: 'https://www.instagram.com/',
      },
      idempotent: true,
      onProgress: ({ bytesWritten, totalBytes }) => {
        patch(key, {
          bytesDownloaded: bytesWritten,
          bytesExpected: totalBytes > 0 ? totalBytes : 0,
        }, false);
      },
    });

    // downloadFileAsync names the file from the URL, so move it to the stable
    // shortcode-based name the library expects.
    const downloaded = landedFile(media.mediaUrl);
    if (downloaded && downloaded.uri !== destination.uri) {
      downloaded.move(destination);
    }

    const size = destination.exists ? destination.size ?? 0 : 0;
    if (size <= 0) throw new ExtractionError('mediaNotFound');

    patch(key, {
      filename,
      state: 'completed',
      bytesDownloaded: size,
      bytesExpected: size,
    });

    patch(key, { savedToLibrary: await saveToPhotos(destination) });
  } catch (error) {
    const message =
      error instanceof ExtractionError ? error.message : (error as Error).message;
    patch(key, { state: 'failed', errorMessage: message });
  } finally {
    inFlight.delete(key);
    inFlight.delete(provisional);
  }
}

/** The file downloadFileAsync just wrote, named after the URL's last path
 *  component with its query string stripped. */
function landedFile(url: string): File | null {
  try {
    const name = new URL(url).pathname.split('/').filter(Boolean).pop();
    if (!name) return null;
    const file = mediaFile(name);
    return file.exists ? file : null;
  } catch {
    return null;
  }
}

/** Copies the finished video into the OS gallery — Photos on iOS, MediaStore
 *  on Android. Returns false if permission was refused; the file is still in
 *  the in-app library either way. */
async function saveToPhotos(file: File): Promise<boolean> {
  try {
    const { granted } = await MediaLibrary.requestPermissionsAsync();
    if (!granted) return false;
    await MediaLibrary.createAssetAsync(file.uri);
    return true;
  } catch {
    return false;
  }
}
