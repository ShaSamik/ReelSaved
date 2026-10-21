import SwiftUI

struct ReelCard: View {
    let reel: SavedReel
    var onRetry: () -> Void
    var onDelete: () -> Void

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 5) {
                Text(reel.displayTitle)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let caption = reel.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                }

                status
            }

            Spacer(minLength: 0)

            trailing
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.smooth(duration: 0.45)) { appeared = true }
        }
        .contextMenu {
            if reel.state == .failed {
                Button("Retry", systemImage: "arrow.clockwise", action: onRetry)
            }
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var thumbnail: some View {
        ZStack {
            if let data = reel.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [.white.opacity(0.14), .white.opacity(0.04)],
                    startPoint: .top, endPoint: .bottom
                )
                Image(systemName: "film")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.4))
            }

            if reel.state == .completed {
                // A play affordance, since tapping a finished card opens the player.
                Circle()
                    .fill(.black.opacity(0.45))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: 58, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var status: some View {
        switch reel.state {
        case .downloading where reel.bytesExpected > 0:
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule()
                            .fill(Palette.accentGradient)
                            .frame(width: max(6, geo.size.width * reel.progress))
                    }
                }
                .frame(height: 5)
                Text(progressLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: 190)
            .animation(.smooth, value: reel.bytesDownloaded)

        case .queued, .extracting, .downloading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Palette.accent)
                Text(reel.state.label)
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))

        case .failed:
            Text(reel.errorMessage ?? "Failed")
                .font(.caption)
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
                .lineLimit(2)

        case .completed:
            Text(sizeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch reel.state {
        case .completed:
            Image(systemName: reel.savedToPhotos ? "checkmark.circle.fill" : "internaldrive.fill")
                .font(.title3)
                .foregroundStyle(reel.savedToPhotos ? Color(red: 0.3, green: 0.85, blue: 0.5) : .white.opacity(0.4))
        case .failed:
            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        default:
            EmptyView()
        }
    }

    private var progressLabel: String {
        let done = ByteCountFormatter.string(fromByteCount: reel.bytesDownloaded, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: reel.bytesExpected, countStyle: .file)
        return "\(done) of \(total)"
    }

    private var sizeLabel: String {
        guard reel.bytesDownloaded > 0 else { return "Saved" }
        return ByteCountFormatter.string(fromByteCount: reel.bytesDownloaded, countStyle: .file)
    }
}
