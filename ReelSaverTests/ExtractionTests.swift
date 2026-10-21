import Testing
import Foundation

/// Anchor for locating the test bundle's resources.
private final class BundleAnchor {}

private func fixture(_ name: String) throws -> String {
    let bundle = Bundle(for: BundleAnchor.self)
    let url = try #require(
        bundle.url(forResource: name, withExtension: "html"),
        "fixture \(name).html is missing from the test bundle"
    )
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite("Instagram URL parsing")
struct InstagramURLTests {

    @Test("shortcode is read from every canonical link shape", arguments: [
        ("https://www.instagram.com/reel/Cx1AbC-dEf_/", "Cx1AbC-dEf_"),
        ("https://instagram.com/reel/Cx1AbC/?igsh=abc123", "Cx1AbC"),
        ("https://www.instagram.com/reels/Cx1AbC/", "Cx1AbC"),
        ("https://www.instagram.com/p/Cx1AbC/", "Cx1AbC"),
        ("https://www.instagram.com/someuser/reel/Cx1AbC/", "Cx1AbC"),
        ("https://m.instagram.com/reel/Cx1AbC/", "Cx1AbC"),
    ])
    func readsShortcode(link: String, expected: String) throws {
        let url = try #require(URL(string: link))
        #expect(InstagramURL.shortcode(from: url) == expected)
    }

    @Test("non-reel and non-Instagram links yield no shortcode", arguments: [
        "https://www.instagram.com/someuser/",
        "https://youtube.com/watch?v=abc",
        "https://example.com/reel/Cx1AbC/",
    ])
    func rejectsOtherLinks(link: String) throws {
        let url = try #require(URL(string: link))
        #expect(InstagramURL.shortcode(from: url) == nil)
    }

    /// Regression: `/share/reel/{token}/` matched the `/{user}/reel/{code}/`
    /// rule, so the opaque token was mistaken for a shortcode and the redirect
    /// was never followed. Every reel shared from the Instagram app failed.
    @Test("share links are not mistaken for shortcodes")
    func shareLinkNeedsResolving() throws {
        let url = try #require(URL(string: "https://www.instagram.com/share/reel/_xYz123/"))
        #expect(InstagramURL.isShareLink(url))
        #expect(InstagramURL.shortcode(from: url) == nil)
    }

    @Test("query parameters are stripped from the shortcode")
    func ignoresTrackingParameters() throws {
        let url = try #require(
            URL(string: "https://www.instagram.com/reel/DeHtg27jeRl/?exln=MWlmMzkyaTFkNHhmdQ==")
        )
        #expect(InstagramURL.shortcode(from: url) == "DeHtg27jeRl")
    }
}

@Suite("Embed page parsing")
struct EmbedHTMLExtractorTests {

    /// The bug that made every download fail: Instagram nests its JSON in a
    /// JavaScript string, so one unescape pass turns `\\\/` into `\/` — still
    /// not a slash. Unescaping has to repeat until the string settles.
    @Test("escaping is collapsed however many layers deep it is", arguments: [
        (#"https:\/\/cdn.example\/v.mp4"#, "https://cdn.example/v.mp4"),
        (#"https:\\\/\\\/cdn.example\\\/v.mp4"#, "https://cdn.example/v.mp4"),
        (#"a\"b"#, #"a"b"#),
    ])
    func unescapeCollapsesEveryLayer(raw: String, expected: String) {
        #expect(EmbedHTMLExtractor.unescape(raw) == expected)
    }

    @Test("html entities and unicode escapes are decoded")
    func decodesEntitiesAndUnicode() {
        #expect(EmbedHTMLExtractor.unescape("a&amp;b&quot;c") == #"a&b"c"#)
        #expect(EmbedHTMLExtractor.unescape(#"café ✨"#) == "café ✨")
    }

    /// Pinned to a real response. If Instagram reshapes its markup, this fails
    /// here rather than silently returning "couldn't find a video" on device.
    @Test("a recorded live response still parses")
    func parsesRecordedResponse() throws {
        let html = try fixture("embed-reel")
        let media = try EmbedHTMLExtractor.parse(html: html, shortcode: "DeHtg27jeRl")

        #expect(media.shortcode == "DeHtg27jeRl")
        #expect(media.author == "v8roll")
        #expect(media.mediaURL.scheme == "https")
        #expect(media.mediaURL.host()?.contains("cdninstagram.com") == true)
        #expect(media.mediaURL.path().hasSuffix(".mp4"))
        #expect(media.thumbnailURL?.scheme == "https")
        #expect(media.suggestedFilename == "DeHtg27jeRl.mp4")

        // A slash that survived as a backslash means the unescaper regressed.
        #expect(!media.mediaURL.absoluteString.contains(#"\"#))
    }

    @Test("a deleted or private reel is reported as unavailable")
    func detectsBrokenMedia() {
        let html = #"<html><body><div class="EmbedBrokenMedia">…</div></body></html>"#
        #expect(throws: ExtractionError.unavailable) {
            try EmbedHTMLExtractor.parse(html: html, shortcode: "abc")
        }
    }

    @Test("a login wall is reported as needing a login")
    func detectsLoginWall() {
        let html = #"<html><body><form id="loginForm"></form></body></html>"#
        #expect(throws: ExtractionError.loginRequired) {
            try EmbedHTMLExtractor.parse(html: html, shortcode: "abc")
        }
    }

    @Test("markup with no video is reported as not found")
    func reportsMissingVideo() {
        #expect(throws: ExtractionError.mediaNotFound) {
            try EmbedHTMLExtractor.parse(html: "<html><body>nothing</body></html>", shortcode: "abc")
        }
    }
}
