import UIKit
import UniformTypeIdentifiers
import Social

/// Receives a reel URL from Instagram's share sheet.
///
/// Deliberately does almost nothing: extensions get a small memory budget and
/// can be killed as soon as they look idle, which is no way to run a download.
/// It writes the URL into the shared inbox and gets out of the way.
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpChrome()

        Task {
            let outcome = await handleInput()
            await MainActor.run { finish(with: outcome) }
        }
    }

    private func setUpChrome() {
        view.backgroundColor = .clear

        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 20
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        label.text = "Saving to Reel Saver…"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
    }

    private enum Outcome {
        case queued
        case notInstagram
        case noURL
        case containerUnavailable

        var message: String {
            switch self {
            case .queued: "Saved to Reel Saver"
            case .notInstagram: "That's not an Instagram link"
            case .noURL: "No link found to save"
            case .containerUnavailable: "Reel Saver isn't set up correctly"
            }
        }
    }

    private func handleInput() async -> Outcome {
        guard let url = await firstURL() else { return .noURL }
        guard InstagramURL.isInstagram(url) else { return .notInstagram }
        return SharedIntent(url: url).write() ? .queued : .containerUnavailable
    }

    /// Instagram may attach the link as a URL item or inside a plain-text blob,
    /// so check both.
    private func firstURL() async -> URL? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return url
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let url = Self.firstURL(inText: text) {
                return url
            }
        }
        return nil
    }

    static func firstURL(inText text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url
    }

    private func finish(with outcome: Outcome) {
        label.text = outcome.message
        // Leave the confirmation up just long enough to be read.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
