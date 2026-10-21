# Reel Saver

An iOS app that saves public Instagram reels to your photo library.

## Running it

Requires Xcode 26+. The `.xcodeproj` is generated, not checked in:

```bash
brew install xcodegen
xcodegen generate
open ReelSaver.xcodeproj
```

Pick a simulator and run. On a device you'll need to set `DEVELOPMENT_TEAM`
in `project.yml` and register the App Group `group.com.shaharia.reelsaver`.

## How it works

Two ways in. The share extension is the main one — in Instagram, tap Share and
choose **Save Reel**. There's also a paste field in the app.

The extension doesn't download anything. Extensions get a small memory budget
and are killed as soon as they look idle, so it writes the URL into a shared
App Group inbox and exits. The app drains that inbox when it next comes to the
foreground.

```
URL → shortcode → extract media URL → download → Photos + in-app library
```

Extraction sits behind the `MediaExtractor` protocol and is assembled in one
place, `DownloadManager.init`. Two implementations run in a chain:

1. `EmbedHTMLExtractor` — fetches `/embed/captioned/` and scrapes the video URL
   out of the markup. One request, no browser engine.
2. `WebViewExtractor` — loads the same page in a `WKWebView` and asks the DOM.
   Slower, but it runs Instagram's JavaScript, so it finds videos that are
   injected after load.

Instagram is the moving part here. When a parse breaks, the fix is almost
always a new pattern in `EmbedHTMLExtractor.videoPatterns` — they're tried in
order and the first match wins.

## Moving extraction to a server

The protocol is the seam. Write one conformance that calls your endpoint and
change the chain in `DownloadManager.init`; nothing else needs to know. This is
worth doing if on-device parsing gets tiresome to maintain — a server running
`yt-dlp` self-heals with a package update instead of an App Store release.

## Scope

Public reels only. Stories, carousels and private accounts would need a
logged-in session, which is a different and much larger problem.

Note that the App Store rejects apps whose evident purpose is downloading from
services whose terms forbid it. That mostly bites YouTube, but it's the main
thing standing between this and a listing.
