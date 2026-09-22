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
    @State private var alertMessage: String?
    @State private var toastMessage: String?

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
            .safeAreaInset(edge: .top, spacing: 0) {
                actionBar
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search opponent, event, opening…")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSettings) {
                SettingsView(
                    pendingVideo: $pendingVideo,
                    onPieceStudio: {
                        showSettings = false
                        beginPieceStudio()
                    }
                )
            }
            .navigationDestination(item: $replay) { route in
                ReplayView(
                    pgn: route.pgn,
                    title: route.title,
                    initialFen: route.initialFen,
                    gamePersistentID: route.gamePersistentID,
                    onContinueGame: { game in
                        self.replay = nil
                        self.continueGame(game)
                    }
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
            showSettings = false
            Task { await importVideo(item) }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear {
            if !SetupFlags.didSeePrimer && games.isEmpty {
                showPrimer = true
            }
        }
        .actionToast(message: $toastMessage)
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
                                    initialFen: game.initialFen ?? PGNMoveList.extractFEN(from: game.pgn),
                                    gamePersistentID: game.persistentModelID
                                )
                            } label: {
                                HistoryRow(game: game, onContinue: {
                                    continueGame(game)
                                })
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    pendingDelete = game
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(Theme.danger)
                            }
                            .swipeActions(edge: .leading) {
                                if game.displayResult == "*" {
                                    Button {
                                        continueGame(game)
                                    } label: {
                                        Label("Continue", systemImage: "camera.viewfinder")
                                    }
                                    .tint(Theme.accent)
                                }
                                Button {
                                    editingGame = game
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                if game.displayResult == "*" {
                                    Button("Continue Game", systemImage: "camera.viewfinder") {
                                        continueGame(game)
                                    }
                                }
                                Button("Replay", systemImage: "play") {
                                    replay = ReplayRoute(
                                        pgn: game.pgn,
                                        title: game.title,
                                        initialFen: game.initialFen ?? PGNMoveList.extractFEN(from: game.pgn),
                                        gamePersistentID: game.persistentModelID
                                    )
                                }
                                Button("Edit Details", systemImage: "pencil") {
                                    editingGame = game
                                }
                                ShareLink(
                                    item: (try? PGNShareFile.write(pgn: game.pgnWithHeaders, title: game.title)) ?? FileManager.default.temporaryDirectory.appending(path: "game.pgn"),
                                    preview: SharePreview(game.title, image: Image(systemName: "square.and.arrow.up"))
                                ) {
                                    Label("Share PGN", systemImage: "square.and.arrow.up")
                                }
                                ExternalAnalysisMenu(pgn: game.pgnWithHeaders, onCopied: { msg in
                                    toastMessage = msg
                                })
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

    private var actionBar: some View {
        HStack {
            GlassCircleButton(
                icon: "gearshape",
                title: "Settings",
                diameter: 40
            ) {
                showSettings = true
            }
            Spacer()
            GlassCircleButton(
                icon: "plus",
                title: "New Game",
                diameter: 40
            ) {
                beginNewGame()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Theme.background)
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
            shareItems = [try PGNShareFile.write(pgn: game.pgnWithHeaders, title: game.title)]
            showShare = true
        } catch {
            UIPasteboard.general.string = game.pgnWithHeaders
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

    private func continueGame(_ game: GameRecord) {
        switch LiveCameraSource.authorizationStatus() {
        case .authorized:
            let model = RecordingSessionViewModel()
            session = model
            model.continueGame(record: game)
        default:
            showPermission = true
        }
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
                alertMessage = "Couldn't load that video."
                return
            }
            let model = RecordingSessionViewModel()
            session = model
            await model.importVideo(url: movie.url)
        } catch {
            alertMessage = error.localizedDescription
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
    var onContinue: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            DigitalBoardView(
                fen: game.finalFen,
                showsCoordinates: false
            )
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.border.opacity(0.6), lineWidth: 1)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 8) {
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
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border.opacity(0.35), lineWidth: 1)
        }
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

    private var plies: Int {
        PGNMoveList.sans(from: game.pgn).count
    }

    private var resultToken: String {
        game.displayResult
    }

    private var resultChip: some View {
        HStack(spacing: 4) {
            if resultToken == "*" {
                Circle()
                    .fill(Theme.caution)
                    .frame(width: 6, height: 6)
            }
            Text(resultToken == "*" ? "Ongoing" : resultToken)
                .font(.caption.monospaced().weight(.semibold))
        }
        .foregroundStyle(resultForeground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(resultForeground.opacity(0.14), in: Capsule())
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
        let time = game.createdAt.formatted(date: .omitted, time: .shortened)
        let moves = plies == 1 ? "1 move" : "\(plies) moves"
        var parts = ["\(time) · \(moves)"]
        if let opening = game.openingName ?? OpeningDetector.detect(sans: PGNMoveList.sans(from: game.pgn)), !opening.isEmpty {
            parts.append(opening)
        }
        if let analysis = game.loadPersistedAnalysis()?.result {
            if let wElo = analysis.whiteElo, let bElo = analysis.blackElo {
                parts.append("Est. \(wElo) vs \(bElo)")
            } else if let wAcc = analysis.whiteAccuracy, let bAcc = analysis.blackAccuracy {
                parts.append(String(format: "%.0f%% vs %.0f%% acc", wAcc, bAcc))
            }
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilitySummary: String {
        let date = game.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(displayTitle), \(resultSpoken), \(plies) moves, \(date)"
    }
}

struct ReplayRoute: Hashable, Identifiable {
    var id: String { title + pgn + (initialFen ?? "") + (gamePersistentID.map { String(describing: $0) } ?? "") }
    var pgn: String
    var title: String
    var initialFen: String? = nil
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
