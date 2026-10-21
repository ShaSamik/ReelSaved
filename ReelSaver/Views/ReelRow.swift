import SwiftUI

struct ReelRow: View {
    let reel: SavedReel

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(reel.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                if let caption = reel.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                statusLine
            }

            Spacer(minLength: 0)

            if reel.state == .completed {
                Image(systemName: reel.savedToPhotos ? "checkmark.circle.fill" : "internaldrive")
                    .foregroundStyle(reel.savedToPhotos ? .green : .secondary)
                    .help(reel.savedToPhotos ? "In Photos" : "Saved in app only")
            }
        }
        .padding(.vertical, 6)
    }

    private var thumbnail: some View {
        Group {
            if let data = reel.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "play.rectangle")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 54, height: 72)
        .clipShape(.rect(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch reel.state {
        case .downloading where reel.bytesExpected > 0:
            ProgressView(value: reel.progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 160)

        case .queued, .extracting, .downloading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(reel.state.label)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .failed:
            Text(reel.errorMessage ?? "Failed")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)

        case .completed:
            Text(byteLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var byteLabel: String {
        guard reel.bytesDownloaded > 0 else { return "Saved" }
        return ByteCountFormatter.string(
            fromByteCount: reel.bytesDownloaded, countStyle: .file
        )
    }
}
