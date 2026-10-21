import Foundation
import SwiftData
import Photos
import UIKit

/// Owns the pipeline: URL in, extraction, download, Photos save, model updates.
@MainActor
@Observable
final class DownloadManager {
    private let extractor: any MediaExtractor
    private let modelContext: ModelContext
    private let session: URLSession

    /// Reels currently being worked on, by shortcode. Keeps the UI honest about
    /// what is in flight and stops the same reel being queued twice.
    private(set) var active: Set<String> = []

    var lastError: String?

    init(modelContext: ModelContext, extractor: (any MediaExtractor)? = nil) {
        self.modelContext = modelContext
        self.session = URLSession(configuration: .default)
        // The chain is assembled here and nowhere else. Swapping in a server
        // extractor later is a one-line change at this call site.
        self.extractor = extractor ?? ChainedExtractor(extractors: [
            EmbedHTMLExtractor(),
            WebViewExtractor(),
        ])
    }

    // MARK: - Entry points

    /// Handles a URL from paste, the share extension, or a deep link.
    func enqueue(_ url: URL) async {
        guard InstagramURL.isInstagram(url) else {
            lastError = ExtractionError.unsupportedURL.localizedDescription
            return
        }
        await process(url)
    }

    /// Picks up anything the share extension left behind.
    func drainSharedInbox() async {
        for intent in SharedIntent.drainInbox() {
            await process(intent.url)
        }
    }

    func retry(_ reel: SavedReel) async {
        guard let url = reel.sourceURL else { return }
        reel.errorMessage = nil
        reel.state = .queued
        await process(url)
    }

    // MARK: - Pipeline

    private func process(_ url: URL) async {
        // Resolve a provisional key so duplicate taps don't double-queue while
        // extraction is still running.
        let provisionalKey = InstagramURL.shortcode(from: url) ?? url.absoluteString
        guard !active.contains(provisionalKey) else { return }
        active.insert(provisionalKey)
        defer { active.remove(provisionalKey) }

        let reel = findOrCreate(shortcode: provisionalKey, url: url)
        reel.state = .extracting
        reel.errorMessage = nil
        save()

        do {
            let media = try await extractor.extract(from: url)

            // Extraction may reveal the real shortcode for a /share/ link.
            if reel.shortcode != media.shortcode {
                reel.shortcode = media.shortcode
            }
            reel.author = media.author
            reel.caption = media.caption
            reel.state = .downloading
            save()

            if let thumb = media.thumbnailURL {
                reel.thumbnailData = try? await fetchData(thumb)
            }

            let fileURL = try await download(media, into: reel)
            reel.filename = fileURL.lastPathComponent
            reel.state = .completed
            save()

            reel.savedToPhotos = await saveToPhotos(fileURL)
            save()
        } catch {
            reel.state = .failed
            reel.errorMessage = (error as? ExtractionError)?.localizedDescription
                ?? error.localizedDescription
            lastError = reel.errorMessage
            save()
        }
    }

    private func findOrCreate(shortcode: String, url: URL) -> SavedReel {
        let descriptor = FetchDescriptor<SavedReel>(
            predicate: #Predicate { $0.shortcode == shortcode }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let reel = SavedReel(shortcode: shortcode, sourceURL: url)
        modelContext.insert(reel)
        return reel
    }

    // MARK: - Transfer

    /// Streams the file to disk and reports progress onto the model as it goes.
    private func download(_ media: ExtractedMedia, into reel: SavedReel) async throws -> URL {
        guard let mediaDir = AppGroup.mediaURL else {
            throw ExtractionError.network("Shared container unavailable — check the App Group capability.")
        }
        let destination = mediaDir.appending(path: media.suggestedFilename)

        var request = URLRequest(url: media.mediaURL)
        request.setValue(UserAgent.safari, forHTTPHeaderField: "User-Agent")
        // Instagram's CDN rejects media requests without a plausible referer.
        request.setValue("https://www.instagram.com/", forHTTPHeaderField: "Referer")

        let downloader = FileDownloader()
        defer { downloader.invalidate() }

        let shortcode = media.shortcode
        return try await downloader.download(request, to: destination) { [weak self] written, expected in
            Task { @MainActor in
                guard let self, let reel = self.reel(withShortcode: shortcode) else { return }
                reel.bytesDownloaded = written
                reel.bytesExpected = expected
            }
        }
    }

    private func reel(withShortcode shortcode: String) -> SavedReel? {
        let descriptor = FetchDescriptor<SavedReel>(
            predicate: #Predicate { $0.shortcode == shortcode }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(UserAgent.safari, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        return data
    }

    // MARK: - Photos

    /// Copies the finished video into the user's photo library. Returns false
    /// if permission was refused — the file is still in the in-app library.
    private func saveToPhotos(_ fileURL: URL) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - Persistence

    func delete(_ reel: SavedReel) {
        if let local = reel.localURL {
            try? FileManager.default.removeItem(at: local)
        }
        modelContext.delete(reel)
        save()
    }

    private func save() {
        try? modelContext.save()
    }
}
