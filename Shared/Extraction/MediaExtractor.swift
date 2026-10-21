import Foundation

/// A single resolved piece of media, ready to download.
struct ExtractedMedia: Sendable, Equatable {
    let mediaURL: URL
    let thumbnailURL: URL?
    let author: String?
    let caption: String?
    let shortcode: String

    /// Filename to use on disk, stable for a given reel.
    var suggestedFilename: String { "\(shortcode).mp4" }
}

enum ExtractionError: LocalizedError, Equatable {
    case unsupportedURL
    case notAReel
    case loginRequired
    case mediaNotFound
    case unavailable
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            "That doesn't look like an Instagram link."
        case .notAReel:
            "That Instagram link isn't a reel."
        case .loginRequired:
            "Instagram wants a login for this one — it's probably private."
        case .mediaNotFound:
            "Couldn't find a video at that link."
        case .unavailable:
            "That reel is unavailable — it may have been deleted, or the account is private."
        case .network(let detail):
            detail
        }
    }
}

/// The seam that keeps extraction swappable.
///
/// Everything upstream of this — the queue, the UI, the share extension — only
/// knows this protocol. Moving extraction to a server later means writing one
/// new conformance and changing the line that builds the extractor; nothing else.
protocol MediaExtractor: Sendable {
    func extract(from url: URL) async throws -> ExtractedMedia
}

/// Tries each extractor in order and returns the first success.
///
/// Instagram serves different markup to different clients, so a cheap HTTP
/// fetch works often but not always. When it doesn't, we fall back to something
/// slower that looks more like a real browser.
struct ChainedExtractor: MediaExtractor {
    let extractors: [any MediaExtractor]

    func extract(from url: URL) async throws -> ExtractedMedia {
        var lastError: Error = ExtractionError.mediaNotFound

        for extractor in extractors {
            do {
                return try await extractor.extract(from: url)
            } catch let error as ExtractionError {
                // A login wall won't resolve by trying a different parser.
                if error == .loginRequired || error == .unsupportedURL || error == .unavailable { throw error }
                lastError = error
            } catch {
                lastError = error
            }
        }

        throw lastError
    }
}
