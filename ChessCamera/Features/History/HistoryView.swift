import PhotosUI
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \GameRecord.createdAt, order: .reverse) private var games: [GameRecord]
    @Environment(\.modelContext) private var modelContext
    @State private var session: RecordingSessionViewModel?
    @State private var showPrimer = false
    @State private var showPermission = false
    @State private var pendingVideo: PhotosPickerItem?
    @State private var replay: ReplayRoute?
    @State private var pendingDelete: GameRecord?
    @State private var startAfterPrimer = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if games.isEmpty {
                    emptyState
                } else {
                    populated
                }
            }
            .navigationTitle("Chess Camera")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: beginNewGame) {
                        Image(systemName: "plus")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("New Game")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        PhotosPicker(selection: $pendingVideo, matching: .videos) {
                            Label("Process a video…", systemImage: "film")
                        }
                        Button("Setup tips") { showPrimer = true }
                        Menu("Settle duration") {
                            Button("300 ms") { SettleSettings.milliseconds = 300 }
                            Button("600 ms") { SettleSettings.milliseconds = 600 }
                            Button("900 ms") { SettleSettings.milliseconds = 900 }
                            Button("1500 ms") { SettleSettings.milliseconds = 1500 }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("More")
                }
            }
            .navigationDestination(item: $replay) { route in
                ReplayView(pgn: route.pgn, title: route.title)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .fullScreenCover(item: $session, onDismiss: {
            Task { await session?.teardown() }
        }) { session in
            SessionFlowView(model: session) { record in
                if let record {
                    modelContext.insert(record)
                }
                Task { await session.teardown() }
                self.session = nil
            }
        }
        .fullScreenCover(isPresented: $showPermission) {
            CameraPermissionView(
                onAuthorized: {
                    showPermission = false
                    startSession()
                },
                onCancel: { showPermission = false }
            )
        }
        .sheet(isPresented: $showPrimer, onDismiss: {
            if startAfterPrimer {
                startAfterPrimer = false
                continueAfterPrimer()
            }
        }) {
            SetupPrimerView(
                onContinue: {
                    SetupFlags.didSeePrimer = true
                    startAfterPrimer = true
                    showPrimer = false
                },
                onDismiss: { showPrimer = false }
            )
        }
        .confirmationDialog(
            "Delete this game?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    modelContext.delete(pendingDelete)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .onChange(of: pendingVideo) { _, item in
            guard let item else { return }
            Task { await importVideo(item) }
        }
        .onAppear {
            if !SetupFlags.didSeePrimer && games.isEmpty {
                showPrimer = true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkerboard.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text("Line up a board. New Game opens the camera.")
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            PrimaryButton(title: "New Game", action: beginNewGame)
                .padding(.horizontal, 16)
            Spacer()
        }
        .padding(16)
    }

    private var populated: some View {
        List {
            ForEach(games) { game in
                Button {
                    replay = ReplayRoute(pgn: game.pgn, title: game.title)
                } label: {
                    HistoryRow(game: game)
                }
                .listRowBackground(Theme.surface)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        pendingDelete = game
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func beginNewGame() {
        if !SetupFlags.didSeePrimer {
            startAfterPrimer = true
            showPrimer = true
            return
        }
        continueAfterPrimer()
    }

    private func continueAfterPrimer() {
        switch LiveCameraSource.authorizationStatus() {
        case .authorized:
            startSession()
        default:
            showPermission = true
        }
    }

    private func startSession() {
        let model = RecordingSessionViewModel()
        session = model
        Task { await model.newGame() }
    }

    private func importVideo(_ item: PhotosPickerItem) async {
        pendingVideo = nil
        do {
            guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                return
            }
            let model = RecordingSessionViewModel()
            session = model
            await model.importVideo(url: movie.url)
        } catch {
            // PhotosPicker already dismissed; surface via a new session alert if needed.
        }
    }
}

private struct HistoryRow: View {
    let game: GameRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(game.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(resultToken)
                    .font(.body.monospaced())
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(game.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            if !preview.isEmpty {
                Text(preview)
                    .font(.body.monospaced())
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }

    private var preview: String {
        PGNMoveList.preview(game.pgn, maxPlies: 6)
    }

    private var resultToken: String {
        (try? GameEngine(fen: game.finalFen))?.resultToken ?? "*"
    }
}

struct ReplayRoute: Hashable, Identifiable {
    var id: String { title + pgn }
    var pgn: String
    var title: String
}

#Preview("History empty") {
    HistoryView()
        .modelContainer(for: GameRecord.self, inMemory: true)
}

#Preview("History filled") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: GameRecord.self, configurations: config)
    let sample = GameRecord(
        createdAt: .now,
        pgn: "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6",
        finalFen: FenCodec.standard,
        title: GameRecord.defaultTitle(for: .now)
    )
    container.mainContext.insert(sample)
    return HistoryView()
        .modelContainer(container)
}
