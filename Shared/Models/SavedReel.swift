import Foundation
import SwiftData

@Model
final class SavedReel {
    /// Instagram's shortcode. Unique so re-sharing the same reel updates the
    /// existing row instead of creating a duplicate.
    @Attribute(.unique) var shortcode: String

    var sourceURLString: String
    var author: String?
    var caption: String?
    var filename: String?
    var thumbnailData: Data?
    var createdAt: Date
    var bytesDownloaded: Int64
    var bytesExpected: Int64
    var savedToPhotos: Bool
    var errorMessage: String?

    /// Stored as a raw value because SwiftData can't index an enum directly.
    var stateRaw: String

    init(
        shortcode: String,
        sourceURL: URL,
        state: ReelState = .queued
    ) {
        self.shortcode = shortcode
        self.sourceURLString = sourceURL.absoluteString
        self.createdAt = Date()
        self.bytesDownloaded = 0
        self.bytesExpected = 0
        self.savedToPhotos = false
        self.stateRaw = state.rawValue
    }
}

extension SavedReel {
    var state: ReelState {
        get { ReelState(rawValue: stateRaw) ?? .queued }
        set { stateRaw = newValue.rawValue }
    }

    var sourceURL: URL? { URL(string: sourceURLString) }

    /// Location of the downloaded file, if it is still on disk.
    var localURL: URL? {
        guard let filename, let media = AppGroup.mediaURL else { return nil }
        let url = media.appending(path: filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var progress: Double {
        guard bytesExpected > 0 else { return 0 }
        return min(1, Double(bytesDownloaded) / Double(bytesExpected))
    }

    var displayTitle: String {
        if let author, !author.isEmpty { return "@\(author)" }
        return shortcode
    }
}

enum ReelState: String, Codable, Sendable, CaseIterable {
    case queued
    case extracting
    case downloading
    case completed
    case failed

    var isTerminal: Bool { self == .completed || self == .failed }

    var label: String {
        switch self {
        case .queued: "Queued"
        case .extracting: "Finding video"
        case .downloading: "Downloading"
        case .completed: "Saved"
        case .failed: "Failed"
        }
    }
}
