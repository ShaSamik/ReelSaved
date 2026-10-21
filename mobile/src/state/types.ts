export type ReelState =
  | 'queued'
  | 'extracting'
  | 'downloading'
  | 'completed'
  | 'failed';

export interface Reel {
  /** Instagram's shortcode, and the identity of the row. */
  shortcode: string;
  sourceUrl: string;
  state: ReelState;
  createdAt: number;
  bytesDownloaded: number;
  bytesExpected: number;
  savedToLibrary: boolean;
  author?: string;
  caption?: string;
  thumbnailUrl?: string;
  /** Name of the downloaded file inside the media directory. */
  filename?: string;
  errorMessage?: string;
}

export const stateLabel: Record<ReelState, string> = {
  queued: 'Queued',
  extracting: 'Finding video',
  downloading: 'Downloading',
  completed: 'Saved',
  failed: 'Failed',
};

export function progressOf(reel: Reel): number {
  if (reel.bytesExpected <= 0) return 0;
  return Math.min(1, reel.bytesDownloaded / reel.bytesExpected);
}

export function displayTitle(reel: Reel): string {
  return reel.author ? `@${reel.author}` : reel.shortcode;
}
