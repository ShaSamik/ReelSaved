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

    var body: some View {
        NavigationStack {
            Group {
                if reels.isEmpty {
                    EmptyLibraryView()
                } else {
                    reelList
                }
            }
            .navigationTitle("Reel Saver")
            .safeAreaInset(edge: .bottom) { pasteBar }
            .sheet(item: $playing) { reel in
                PlayerSheet(reel: reel)
            }
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

    private var reelList: some View {
        List {
            ForEach(reels) { reel in
                ReelRow(reel: reel)
                    .contentShape(.rect)
                    .onTapGesture {
                        guard reel.state == .completed, reel.localURL != nil else { return }
                        playing = reel
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            manager?.delete(reel)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        if reel.state == .failed {
                            Button {
                                Task { await manager?.retry(reel) }
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            .tint(.blue)
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    private var pasteBar: some View {
        HStack(spacing: 10) {
            TextField("Paste an Instagram reel link", text: $pastedLink)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .onSubmit(submit)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(.thinMaterial, in: .rect(cornerRadius: 12))

            Button(action: submit) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
            }
            .disabled(URL(string: pastedLink.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func submit() {
        let trimmed = pastedLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return }
        pastedLink = ""
        Task { await manager?.enqueue(url) }
    }
}

private struct EmptyLibraryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No reels yet", systemImage: "arrow.down.square")
        } description: {
            Text("In Instagram, tap Share on a reel and choose **Save Reel**. Or paste a link below.")
        }
    }
}

private struct PlayerSheet: View {
    let reel: SavedReel

    var body: some View {
        if let url = reel.localURL {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
        } else {
            ContentUnavailableView("File missing", systemImage: "exclamationmark.triangle")
        }
    }
}
