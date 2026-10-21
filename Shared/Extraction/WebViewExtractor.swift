import Foundation
@preconcurrency import WebKit

/// Loads the embed page in a real browser engine and asks the DOM for the video.
///
/// Slower and heavier than `EmbedHTMLExtractor`, but it executes Instagram's
/// JavaScript, so it finds videos that are injected after load rather than
/// baked into the served HTML. This is the fallback, not the first try.
@MainActor
final class WebViewExtractor: NSObject, MediaExtractor {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    /// How long to let the page settle before giving up.
    private let timeout: Duration = .seconds(15)

    nonisolated func extract(from url: URL) async throws -> ExtractedMedia {
        try await MainActor.run { () -> Void in } // hop before touching WebKit
        return try await extractOnMain(from: url)
    }

    private func extractOnMain(from url: URL) async throws -> ExtractedMedia {
        let canonical = InstagramURL.isShareLink(url)
            ? try await InstagramURL.resolveShareLink(url)
            : url

        guard InstagramURL.isInstagram(canonical) else { throw ExtractionError.unsupportedURL }
        guard let shortcode = InstagramURL.shortcode(from: canonical),
              let embed = InstagramURL.embedURL(shortcode: shortcode) else {
            throw ExtractionError.notAReel
        }

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 420, height: 740), configuration: config)
        webView.customUserAgent = UserAgent.safari
        webView.navigationDelegate = self
        self.webView = webView
        defer { teardown() }

        try await load(embed, in: webView)
        guard let media = try await pollForVideo(in: webView, shortcode: shortcode) else {
            throw ExtractionError.mediaNotFound
        }
        return media
    }

    private func load(_ url: URL, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            webView.load(URLRequest(url: url))

            timeoutTask = Task { [timeout] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                await self.resume(throwing: ExtractionError.network("Timed out loading Instagram."))
            }
        }
    }

    /// The `<video>` element can appear a beat after `didFinish`, so poll briefly
    /// rather than reading the DOM once and declaring failure.
    private func pollForVideo(in webView: WKWebView, shortcode: String) async throws -> ExtractedMedia? {
        let script = """
        (function () {
          const v = document.querySelector('video');
          const src = v ? (v.src || (v.querySelector('source') || {}).src) : null;
          const poster = v ? v.poster : null;
          const meta = (p) => {
            const el = document.querySelector(`meta[property="${p}"]`);
            return el ? el.content : null;
          };
          const user = document.querySelector('.UsernameText, [class*="Username"]');
          return {
            src: src || meta('og:video'),
            poster: poster || meta('og:image'),
            author: user ? user.textContent : null,
            caption: meta('og:description')
          };
        })();
        """

        for _ in 0..<10 {
            if let result = try? await webView.evaluateJavaScript(script) as? [String: Any],
               let src = result["src"] as? String,
               let mediaURL = URL(string: src),
               mediaURL.scheme?.hasPrefix("http") == true {
                return ExtractedMedia(
                    mediaURL: mediaURL,
                    thumbnailURL: (result["poster"] as? String).flatMap(URL.init(string:)),
                    author: (result["author"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    caption: result["caption"] as? String,
                    shortcode: shortcode
                )
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        return nil
    }

    private func resume(throwing error: Error? = nil) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        if let error { cont.resume(throwing: error) } else { cont.resume() }
    }

    private func teardown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }
}

extension WebViewExtractor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resume()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resume(throwing: ExtractionError.network(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resume(throwing: ExtractionError.network(error.localizedDescription))
    }
}
