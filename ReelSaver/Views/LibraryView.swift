import SwiftUI
import SwiftData
import AVKit

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SavedReel.createdAt, order: .reverse) private var reels: [SavedReel]

    @State private var manager: DownloadManager?
    @State private var pastedLink = ""
    @State private var playing: SavedReel?
    @FocusState private var linkFieldFocused: Bool

    var body: some View {
        ZStack {
            AnimatedBackground()

            VStack(spacing: 0) {
                header
                content
            }
            .safeAreaInset(edge: .bottom) { pasteBar }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $playing) { reel in
            PlayerScreen(reel: reel)
        }
        .task {
            if manager == nil {
                manager = DownloadManager(modelContext: modelContext)
            }
            await manager?.drainSharedInbox()
        }
        .onChange(of: scenePhase) { _, phase in
            // Anything shared while we were backgrounded is waiting in the inbox.
            guard phase == .active else { return }
            Task { await manager?.drainSharedInbox() }
        }
        .onOpenURL { url in
            Task { await manager?.enqueue(url) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reel Saver")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if !reels.isEmpty {
                    Text("^[\(reels.count) reel](inflect: true)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        if reels.isEmpty {
            EmptyState()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(reels) { reel in
                        ReelCard(
                            reel: reel,
                            onRetry: { Task { await manager?.retry(reel) } },
                            onDelete: { withAnimation(.smooth) { manager?.delete(reel) } }
                        )
                        .contentShape(.rect)
                        .onTapGesture {
                            guard reel.state == .completed, reel.localURL != nil else { return }
                            playing = reel
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var pasteBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))

            TextField(
                "",
                text: $pastedLink,
                prompt: Text("Paste a reel link").foregroundStyle(.white.opacity(0.4))
            )
            .textFieldStyle(.plain)
            .foregroundStyle(.white)
            .tint(Palette.accent)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .submitLabel(.go)
            .focused($linkFieldFocused)
            .onSubmit(submit)

            Button(action: submit) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(canSubmit ? AnyShapeStyle(Palette.accentGradient)
                                                : AnyShapeStyle(Color.white.opacity(0.12)))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .animation(.smooth(duration: 0.25), value: canSubmit)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var canSubmit: Bool {
        URL(string: pastedLink.trimmingCharacters(in: .whitespacesAndNewlines))?.host() != nil
    }

    private func submit() {
        let trimmed = pastedLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return }
        pastedLink = ""
        linkFieldFocused = false
        Task { await manager?.enqueue(url) }
    }
}

/// Shown until the first reel lands. The icon breathes rather than spins —
/// nothing is loading, so a spinner would be a lie.
private struct EmptyState: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.18))
                    .frame(width: 118, height: 118)
                    .scaleEffect(breathing ? 1.12 : 0.92)
                    .blur(radius: 12)

                Circle()
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    .background(Circle().fill(.ultraThinMaterial))
                    .frame(width: 92, height: 92)

                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Palette.accentGradient)
            }

            VStack(spacing: 7) {
                Text("No reels yet")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text("In Instagram, tap Share and choose **Save Reel** — or paste a link below.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }

            Spacer()
            Spacer()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

private struct PlayerScreen: View {
    let reel: SavedReel
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ContentUnavailableView(
                    "File missing",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The video is no longer on disk.")
                )
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        player?.pause()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.black.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 18)
                    .padding(.top, 10)
                }
                Spacer()
            }
        }
        .onAppear {
            guard let url = reel.localURL else { return }
            let player = AVPlayer(url: url)
            // Reels are short; looping saves reaching for replay.
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                player.play()
            }
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}
