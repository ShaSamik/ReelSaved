/** A single resolved piece of media, ready to download. */
export interface ExtractedMedia {
  mediaUrl: string;
  thumbnailUrl?: string;
  author?: string;
  caption?: string;
  shortcode: string;
}

export type ExtractionErrorKind =
  | 'unsupportedUrl'
  | 'notAReel'
  | 'loginRequired'
  | 'mediaNotFound'
  | 'unavailable'
  | 'network';

const MESSAGES: Record<ExtractionErrorKind, string> = {
  unsupportedUrl: "That doesn't look like an Instagram link.",
  notAReel: "That Instagram link isn't a reel.",
  loginRequired: "Instagram wants a login for this one — it's probably private.",
  mediaNotFound: "Couldn't find a video at that link.",
  unavailable:
    'That reel is unavailable — it may have been deleted, or the account is private.',
  network: 'Something went wrong reaching Instagram.',
};

export class ExtractionError extends Error {
  readonly kind: ExtractionErrorKind;

  constructor(kind: ExtractionErrorKind, detail?: string) {
    super(detail ?? MESSAGES[kind]);
    this.name = 'ExtractionError';
    this.kind = kind;
  }
}

/** Filename to use on disk, stable for a given reel. */
export function suggestedFilename(media: ExtractedMedia): string {
  return `${media.shortcode}.mp4`;
}

/**
 * The seam that keeps extraction swappable.
 *
 * Everything upstream — the queue, the UI, the share handler — depends only on
 * this. Moving extraction to a server later means one new implementation and
 * one changed line where the chain is assembled.
 */
export interface MediaExtractor {
  extract(url: string): Promise<ExtractedMedia>;
}

/** A desktop Safari string. The embed page returns richer markup to a
 *  browser-looking client than it does to a default fetch agent. */
export const SAFARI_USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';
