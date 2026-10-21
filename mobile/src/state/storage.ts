import { Directory, File, Paths } from 'expo-file-system';
import { Reel } from './types';

const INDEX_NAME = 'library.json';
const MEDIA_DIR = 'media';

/** Where downloaded videos live. Created on first use. */
export function mediaDirectory(): Directory {
  const dir = new Directory(Paths.document, MEDIA_DIR);
  if (!dir.exists) dir.create({ intermediates: true });
  return dir;
}

export function mediaFile(filename: string): File {
  return new File(mediaDirectory(), filename);
}

function indexFile(): File {
  return new File(Paths.document, INDEX_NAME);
}

export async function loadLibrary(): Promise<Reel[]> {
  const file = indexFile();
  if (!file.exists) return [];
  try {
    const parsed = JSON.parse(await file.text());
    return Array.isArray(parsed) ? (parsed as Reel[]) : [];
  } catch {
    // A corrupt index shouldn't stop the app from opening; the files on disk
    // are still there and can be re-added.
    return [];
  }
}

export async function saveLibrary(reels: Reel[]): Promise<void> {
  const file = indexFile();
  if (!file.exists) file.create({ intermediates: true });
  file.write(JSON.stringify(reels));
}

/** Removes the downloaded video, if it is still on disk. */
export function deleteMedia(filename?: string): void {
  if (!filename) return;
  const file = mediaFile(filename);
  if (file.exists) file.delete();
}
