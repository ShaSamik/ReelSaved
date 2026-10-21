import Foundation

/// Shared identifiers and the on-disk contract between the app and its share extension.
enum AppGroup {
    static let identifier = "group.com.shaharia.reelsaver"

    /// Root of the shared container. Both processes write here.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Drop box for URLs handed over by the share extension.
    ///
    /// The extension cannot be relied on to stay alive long enough to finish a
    /// download, so it only writes an intent here. The app drains the folder the
    /// next time it comes to the foreground.
    static var inboxURL: URL? {
        guard let container = containerURL else { return nil }
        let inbox = container.appending(path: "inbox", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    /// Location of the SwiftData store.
    ///
    /// The group container is created empty, without the `Library/Application
    /// Support` directory CoreData expects, so make it before handing over the
    /// path. Returns nil when the App Group isn't available at all.
    static var storeURL: URL? {
        guard let container = containerURL else { return nil }
        let directory = container
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        return directory.appending(path: "ReelSaver.store")
    }

    /// Where finished videos live. Kept in the group container so the extension
    /// could show a library preview later without copying anything.
    static var mediaURL: URL? {
        guard let container = containerURL else { return nil }
        let media = container.appending(path: "media", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        return media
    }
}

/// A URL handed from the extension to the app.
struct SharedIntent: Codable, Sendable {
    let id: UUID
    let url: URL
    let receivedAt: Date

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.receivedAt = Date()
    }
}

extension SharedIntent {
    /// Writes the intent into the app group inbox. Returns false if the group
    /// container is unavailable, which means the App Group capability is missing.
    @discardableResult
    func write() -> Bool {
        guard let inbox = AppGroup.inboxURL,
              let data = try? JSONEncoder().encode(self) else { return false }
        let target = inbox.appending(path: "\(id.uuidString).json")
        return (try? data.write(to: target, options: .atomic)) != nil
    }

    /// Reads and removes every pending intent, oldest first.
    static func drainInbox() -> [SharedIntent] {
        guard let inbox = AppGroup.inboxURL,
              let files = try? FileManager.default.contentsOfDirectory(
                at: inbox, includingPropertiesForKeys: nil
              ) else { return [] }

        let intents = files
            .filter { $0.pathExtension == "json" }
            .compactMap { file -> SharedIntent? in
                guard let data = try? Data(contentsOf: file),
                      let intent = try? JSONDecoder().decode(SharedIntent.self, from: data)
                else { return nil }
                try? FileManager.default.removeItem(at: file)
                return intent
            }

        return intents.sorted { $0.receivedAt < $1.receivedAt }
    }
}
