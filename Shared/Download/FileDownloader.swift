import Foundation

/// A download task wrapped for async/await, with progress.
///
/// `URLSession.bytes` would be shorter, but it yields one byte at a time and
/// collapses under a video-sized payload. `URLSessionDownloadTask` streams to
/// disk in the networking layer and reports progress through its delegate.
final class FileDownloader: NSObject, @unchecked Sendable {
    private var session: URLSession!
    private var continuation: CheckedContinuation<URL, Error>?
    private var onProgress: (@Sendable (Int64, Int64) -> Void)?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Downloads `request` and moves the result to `destination`.
    /// `progress` is called with (downloaded, expected); expected is 0 when unknown.
    func download(
        _ request: URLRequest,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        self.onProgress = progress

        let temporary = try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            session.downloadTask(with: request).resume()
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)

        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw ExtractionError.mediaNotFound
        }
        return destination
    }

    func invalidate() {
        session.finishTasksAndInvalidate()
    }
}

extension FileDownloader: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The delegate's temp file is deleted the moment this method returns,
        // so move it somewhere we control before resuming the caller.
        let staged = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: staged)
            resume(with: .success(staged))
        } catch {
            resume(with: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown
            ? 0 : totalBytesExpectedToWrite
        onProgress?(totalBytesWritten, expected)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return } // success already handled above
        resume(with: .failure(ExtractionError.network(error.localizedDescription)))
    }

    private func resume(with result: Result<URL, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }
}
