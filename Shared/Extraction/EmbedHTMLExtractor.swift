import Foundation

/// Fetches Instagram's embed page and scrapes the video URL out of it.
///
/// This is the fast path: one GET, no browser engine. The embed page exists to
/// be rendered by third-party sites, so it is served to logged-out clients when
/// the main page is not. It still changes shape without warning, which is why
/// several patterns are tried and why `WebViewExtractor` sits behind it.
struct EmbedHTMLExtractor: MediaExtractor {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func extract(from url: URL) async throws -> ExtractedMedia {
        let canonical = InstagramURL.isShareLink(url)
            ? try await InstagramURL.resolveShareLink(url, session: session)
            : url

        guard InstagramURL.isInstagram(canonical) else { throw ExtractionError.unsupportedURL }
        guard let shortcode = InstagramURL.shortcode(from: canonical) else {
            throw ExtractionError.notAReel
        }
        guard let embed = InstagramURL.embedURL(shortcode: shortcode) else {
            throw ExtractionError.unsupportedURL
        }

        let html = try await fetchHTML(embed)

        // A login wall comes back as a real page, not an HTTP error.
        if html.contains("loginForm") || html.contains("Log in to Instagram") {
            throw ExtractionError.loginRequired
        }
        // Instagram serves a 200 with this marker when the reel is deleted,
        // private, or the shortcode is simply wrong.
        if html.contains("EmbedBrokenMedia") {
            throw ExtractionError.unavailable
        }

        guard let mediaURL = Self.firstMatch(of: Self.videoPatterns, in: html)
            .flatMap(URL.init(string:))
        else {
            throw ExtractionError.mediaNotFound
        }

        return ExtractedMedia(
            mediaURL: mediaURL,
            thumbnailURL: Self.firstMatch(of: Self.thumbnailPatterns, in: html)
                .flatMap(URL.init(string:)),
            author: Self.firstMatch(of: Self.authorPatterns, in: html),
            caption: Self.firstMatch(of: Self.captionPatterns, in: html),
            shortcode: shortcode
        )
    }

    private func fetchHTML(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(UserAgent.safari, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                guard (200..<300).contains(http.statusCode) else {
                    if http.statusCode == 401 || http.statusCode == 403 {
                        throw ExtractionError.loginRequired
                    }
                    throw ExtractionError.network("Instagram returned \(http.statusCode).")
                }
            }
            guard let html = String(data: data, encoding: .utf8) else {
                throw ExtractionError.mediaNotFound
            }
            return html
        } catch let error as ExtractionError {
            throw error
        } catch {
            throw ExtractionError.network(error.localizedDescription)
        }
    }

    // MARK: - Patterns
    //
    // Ordered most-specific first. The JSON keys are the reliable ones when
    // present; the og: meta tags are the fallback that survives most redesigns.

    private static let videoPatterns = [
        #""video_url"\s*:\s*"([^"]+)""#,
        #""video_versions"\s*:\s*\[\s*\{[^}]*?"url"\s*:\s*"([^"]+)""#,
        #"<meta[^>]+property="og:video"[^>]+content="([^"]+)""#,
        #"<meta[^>]+content="([^"]+)"[^>]+property="og:video""#,
        #"<video[^>]+src="([^"]+)""#,
    ]

    private static let thumbnailPatterns = [
        #""display_url"\s*:\s*"([^"]+)""#,
        #"<meta[^>]+property="og:image"[^>]+content="([^"]+)""#,
    ]

    private static let authorPatterns = [
        #""owner"\s*:\s*\{[^}]*?"username"\s*:\s*"([^"]+)""#,
        #""username"\s*:\s*"([^"]+)""#,
    ]

    private static let captionPatterns = [
        #"<meta[^>]+property="og:description"[^>]+content="([^"]+)""#,
    ]

    /// Runs patterns in order, returning the first capture group that matches.
    static func firstMatch(of patterns: [String], in html: String) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
                  let match = regex.firstMatch(
                    in: html, range: NSRange(html.startIndex..., in: html)
                  ),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html)
            else { continue }

            let value = unescape(String(html[range]))
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Instagram embeds JSON inside HTML, so captures arrive doubly escaped:
    /// `\/` for slashes, `\uXXXX` for non-ASCII, and HTML entities on top.
    static func unescape(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\""#, with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        // Decode \uXXXX sequences.
        while let range = value.range(of: #"\\u[0-9a-fA-F]{4}"#, options: .regularExpression) {
            let hex = String(value[range].dropFirst(2))
            guard let code = UInt32(hex, radix: 16),
                  let scalar = Unicode.Scalar(code) else {
                value.replaceSubrange(range, with: "")
                continue
            }
            value.replaceSubrange(range, with: String(Character(scalar)))
        }
        return value
    }
}
