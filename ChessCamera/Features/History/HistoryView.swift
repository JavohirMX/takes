import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct HistoryView: View {
    @Query(sort: \GameRecord.createdAt, order: .reverse) private var games: [GameRecord]
    @Environment(\.modelContext) private var modelContext
    @State private var session: RecordingSessionViewModel?
    @State private var showPrimer = false
    @State private var showPermission = false
    @State private var pendingVideo: PhotosPickerItem?
    @State private var replay: ReplayRoute?
    @State private var pendingDelete: GameRecord?
    @State private var editingGame: GameRecord?
    @State private var startAfterPrimer = false
    @State private var pendingPieceStudio = false
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var selectedFilter = "All"

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
            .navigationTitle("Takes")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search opponent, event, opening…")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: beginNewGame) {
                        Image(systemName: "plus")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("New Game")
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(item: $replay) { route in
                ReplayView(
                    pgn: route.pgn,
                    title: route.title,
                    gamePersistentID: route.gamePersistentID
                )
            }
            .sheet(item: $editingGame) { game in
                EditGameDetailsSheet(game: game)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .fullScreenCover(item: $session, onDismiss: {
            if let session, session.engine.plyCount > 0 {
                let record = session.savedRecordIfNeeded()
                if let record, record.modelContext == nil {
                    modelContext.insert(record)
                }
                try? modelContext.save()
            }
            Task { await session?.teardown() }
        }) { session in
            SessionFlowView(model: session) { record in
                if let record, record.modelContext == nil {
                    modelContext.insert(record)
                }
                try? modelContext.save()
                Task { await session.teardown() }
                self.session = nil
            }
        }
        .fullScreenCover(isPresented: $showPermission) {
            CameraPermissionView(
                onAuthorized: {
                    showPermission = false
                    if pendingPieceStudio {
                        pendingPieceStudio = false
                        startPieceStudio()
                    } else {
                        startSession()
                    }
                },
                onCancel: {
                    pendingPieceStudio = false
                    showPermission = false
                }
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
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
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
            DigitalBoardView(
                fen: FenCodec.standard,
                showsCoordinates: false,
                styleOverride: .tournament
            )
            .frame(width: 168, height: 168)
            .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Games you record will appear here.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("New Game opens the camera.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            PrimaryButton(title: "New Game", action: beginNewGame)
                .padding(.horizontal, 16)
            Spacer()
        }
        .padding(16)
    }

    private var populated: some View {
        VStack(spacing: 0) {
            filterBar
            List {
                ForEach(historySections) { section in
                    Section {
                        ForEach(section.games) { game in
                            Button {
                                replay = ReplayRoute(
                                    pgn: game.pgn,
                                    title: game.title,
                                    gamePersistentID: game.persistentModelID
                                )
                            } label: {
                                HistoryRow(game: game)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    pendingDelete = game
                                }
                            }
                            .contextMenu {
                                Button("Replay", systemImage: "play") {
                                    replay = ReplayRoute(
                                        pgn: game.pgn,
                                        title: game.title,
                                        gamePersistentID: game.persistentModelID
                                    )
                                }
                                Button("Edit Details", systemImage: "pencil") {
                                    editingGame = game
                                }
                                Button("Share PGN", systemImage: "square.and.arrow.up") {
                                    share(game)
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    pendingDelete = game
                                }
                            }
                        }
                    } header: {
                        Text(section.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(8)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["All", "1-0", "0-1", "½-½", "*"], id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter == "*" ? "Ongoing (*)" : filter)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                selectedFilter == filter ? Theme.accent : Theme.surface,
                                in: Capsule()
                            )
                            .foregroundStyle(
                                selectedFilter == filter ? Theme.background : Theme.textSecondary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var filteredGames: [GameRecord] {
        games.filter { game in
            let matchesFilter: Bool = {
                if selectedFilter == "All" { return true }
                return game.displayResult == selectedFilter
            }()
            guard matchesFilter else { return false }

            if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                return true
            }
            let query = searchText.lowercased()
            let titleMatch = game.title.lowercased().contains(query)
            let whiteMatch = game.whitePlayer?.lowercased().contains(query) ?? false
            let blackMatch = game.blackPlayer?.lowercased().contains(query) ?? false
            let eventMatch = game.event?.lowercased().contains(query) ?? false
            let openingMatch = (game.openingName ?? OpeningDetector.detect(sans: PGNMoveList.sans(from: game.pgn)))?.lowercased().contains(query) ?? false
            return titleMatch || whiteMatch || blackMatch || eventMatch || openingMatch
        }
    }

    private var historySections: [HistorySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredGames) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            HistorySection(
                id: day,
                title: HistorySection.title(for: day, calendar: calendar),
                games: (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt }
            )
        }
    }

    private func share(_ game: GameRecord) {
        do {
            shareItems = [try PGNShareFile.write(pgn: game.pgn, title: game.title)]
            showShare = true
        } catch {
            UIPasteboard.general.string = game.pgn
        }
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

    private func beginPieceStudio() {
        switch LiveCameraSource.authorizationStatus() {
        case .authorized:
            startPieceStudio()
        default:
            pendingPieceStudio = true
            showPermission = true
        }
    }

    private func startSession() {
        let model = RecordingSessionViewModel()
        session = model
        Task { await model.newGame() }
    }

    private func startPieceStudio() {
        let model = RecordingSessionViewModel()
        session = model
        Task { await model.startPieceStudio() }
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

private struct HistorySection: Identifiable {
    var id: Date
    var title: String
    var games: [GameRecord]

    static func title(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct HistoryRow: View {
    let game: GameRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DigitalBoardView(
                fen: game.finalFen,
                showsCoordinates: false
            )
            .frame(width: 72, height: 72)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(displayTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    resultChip
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                if !preview.isEmpty {
                    Text(preview)
                        .font(.body.monospaced())
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
    }

    private var displayTitle: String {
        if let white = game.whitePlayer, let black = game.blackPlayer, !white.isEmpty, !black.isEmpty {
            return "\(white) vs \(black)"
        }
        return game.title
    }

    private var preview: String {
        PGNMoveList.preview(game.pgn, maxPlies: 6)
    }

    private var plies: Int {
        PGNMoveList.sans(from: game.pgn).count
    }

    private var resultToken: String {
        game.displayResult
    }

    private var resultChip: some View {
        Text(resultToken)
            .font(.caption.monospaced().weight(.semibold))
            .foregroundStyle(resultForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(resultForeground.opacity(0.16), in: Capsule())
            .accessibilityHidden(true)
    }

    private var resultForeground: Color {
        switch resultToken {
        case "1-0": Theme.accent
        case "0-1": Theme.textPrimary
        case "½-½": Theme.textSecondary
        default: Theme.caution
        }
    }

    private var resultSpoken: String {
        switch resultToken {
        case "1-0": "1-0"
        case "0-1": "0-1"
        case "½-½": "draw"
        default: "In progress"
        }
    }

    private var subtitle: String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(game.createdAt) {
            day = "Today"
        } else if calendar.isDateInYesterday(game.createdAt) {
            day = "Yesterday"
        } else {
            day = game.createdAt.formatted(date: .abbreviated, time: .omitted)
        }
        let time = game.createdAt.formatted(date: .omitted, time: .shortened)
        let moves = plies == 1 ? "1 move" : "\(plies) moves"
        var parts = ["\(day) · \(time) · \(moves)"]
        if let opening = game.openingName ?? OpeningDetector.detect(sans: PGNMoveList.sans(from: game.pgn)) {
            parts.append(opening)
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilitySummary: String {
        let date = game.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(displayTitle), \(resultSpoken), \(plies) moves, \(date)"
    }
}

struct ReplayRoute: Hashable, Identifiable {
    var id: String { title + pgn + (gamePersistentID.map { String(describing: $0) } ?? "") }
    var pgn: String
    var title: String
    var gamePersistentID: PersistentIdentifier?
}

#Preview("History empty") {
    HistoryView()
        .modelContainer(for: GameRecord.self, inMemory: true)
}

#Preview("History filled") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: GameRecord.self, configurations: config)
    let calendar = Calendar.current
    let now = Date()
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
    let lastWeek = calendar.date(byAdding: .day, value: -5, to: now) ?? now

    let ruy = GameEngine()
    for san in ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6"] {
        try? ruy.apply(san: san)
    }
    container.mainContext.insert(
        GameRecord(
            createdAt: now,
            pgn: "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6",
            finalFen: ruy.fen,
            title: GameRecord.defaultTitle(for: now)
        )
    )

    let foolsMate = GameEngine()
    for san in ["f3", "e5", "g4", "Qh4"] {
        try? foolsMate.apply(san: san)
    }
    container.mainContext.insert(
        GameRecord(
            createdAt: yesterday,
            pgn: "1. f3 e5 2. g4 Qh4# 0-1",
            finalFen: foolsMate.fen,
            title: GameRecord.defaultTitle(for: yesterday)
        )
    )

    container.mainContext.insert(
        GameRecord(
            createdAt: lastWeek,
            pgn: "1. e4",
            finalFen: {
                let engine = GameEngine()
                try? engine.apply(san: "e4")
                return engine.fen
            }(),
            title: GameRecord.defaultTitle(for: lastWeek)
        )
    )

    return HistoryView()
        .modelContainer(container)
}
