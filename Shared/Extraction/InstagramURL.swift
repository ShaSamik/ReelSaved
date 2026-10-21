import Foundation

/// Parsing for the several URL shapes Instagram hands out for one reel.
enum InstagramURL {
    private static let hosts: Set<String> = [
        "instagram.com", "www.instagram.com", "m.instagram.com", "instagr.am"
    ]

    /// Path prefixes that carry a shortcode directly.
    /// `/p/` is included because reels shared from the feed often use it.
    private static let directPrefixes: Set<String> = ["reel", "reels", "p", "tv"]

    static func isInstagram(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return hosts.contains(host)
    }

    /// Pulls the shortcode out of a canonical URL.
    ///
    /// Returns nil for `/share/` links, which carry an opaque token rather than
    /// a shortcode and have to be resolved over the network first.
    static func shortcode(from url: URL) -> String? {
        guard isInstagram(url) else { return nil }
        // A /share/ token sits in the same position as a shortcode but is not
        // one; it has to be resolved over the network first.
        guard !isShareLink(url) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        // /reel/{code}/ or /p/{code}/
        if parts.count >= 2, directPrefixes.contains(parts[0].lowercased()) {
            return sanitise(parts[1])
        }
        // /{username}/reel/{code}/
        if parts.count >= 3, directPrefixes.contains(parts[1].lowercased()) {
            return sanitise(parts[2])
        }
        return nil
    }

    /// True for the `/share/...` redirect links the Instagram app produces.
    static func isShareLink(_ url: URL) -> Bool {
        guard isInstagram(url) else { return false }
        return url.pathComponents.contains { $0.lowercased() == "share" }
    }

    /// Follows a `/share/` link to the canonical URL it redirects to.
    static func resolveShareLink(_ url: URL, session: URLSession = .shared) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(UserAgent.safari, forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await session.data(for: request)
            // URLSession follows redirects by default, so the final URL is on the response.
            guard let resolved = response.url, resolved != url else {
                throw ExtractionError.mediaNotFound
            }
            return resolved
        } catch let error as ExtractionError {
            throw error
        } catch {
            throw ExtractionError.network(error.localizedDescription)
        }
    }

    /// The lightweight embed page, which is far more permissive than the main
    /// page for logged-out clients.
    static func embedURL(shortcode: String) -> URL? {
        URL(string: "https://www.instagram.com/reel/\(shortcode)/embed/captioned/")
    }

    static func canonicalURL(shortcode: String) -> URL? {
        URL(string: "https://www.instagram.com/reel/\(shortcode)/")
    }

    /// Shortcodes are base64-ish; strip anything that isn't.
    private static func sanitise(_ raw: String) -> String? {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let cleaned = raw.unicodeScalars.filter { allowed.contains($0) }
        let code = String(String.UnicodeScalarView(cleaned))
        return code.isEmpty ? nil : code
    }
}

enum UserAgent {
    /// A desktop Safari string. The embed page returns richer markup to a
    /// browser-looking client than it does to the default URLSession agent.
    static let safari = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}
