import SwiftData
import SwiftUI
import UIKit

struct SessionFlowView: View {
    @Bindable var model: RecordingSessionViewModel
    var onFinished: (GameRecord?) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var replayFromGameOver = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle, .importingVideo:
                    ZStack {
                        Theme.background.ignoresSafeArea()
                        ProgressView()
                            .tint(Theme.accent)
                    }
                case .boardStudio, .detectingBoard, .calibratingCorners:
                    BoardStudioView(model: model)
                case .pieceStudio:
                    PieceStudioView(model: model)
                case .confirmingStart:
                    ConfirmStartView(model: model)
                case .recording, .disturbed, .awaitingEdit:
                    LiveRecordingView(model: model)
                case .gameOver:
                    GameOverView(
                        model: model,
                        onReplay: {
                            ensureGameSaved()
                            replayFromGameOver = true
                        },
                        onDone: {
                            let record = ensureGameSaved()
                            onFinished(record)
                        }
                    )
                case .replay:
                    ReplayView(
                        pgn: model.pgn,
                        title: model.savedRecord?.title ?? "Replay",
                        gamePersistentID: ensureGameSaved()?.persistentModelID,
                        onDone: {
                            let record = ensureGameSaved()
                            onFinished(record)
                        }
                    )
                }
            }
            .navigationDestination(isPresented: $replayFromGameOver) {
                ReplayView(
                    pgn: model.pgn,
                    title: model.savedRecord?.title ?? "Replay",
                    gamePersistentID: model.savedRecord?.persistentModelID,
                    onDone: {
                        let record = ensureGameSaved()
                        onFinished(record)
                    }
                )
            }
            .overlay(alignment: .topLeading) {
                if canCloseWithoutConfirm {
                    Button {
                        let record = ensureGameSaved()
                        Task {
                            await model.teardown()
                            onFinished(record)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Theme.overlayScrim, in: Circle())
                    }
                    .padding(16)
                    .accessibilityLabel("Close")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .interactiveDismissDisabled(true)
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                if model.engine.plyCount > 0 {
                    ensureGameSaved()
                }
                model.handleBackground()
            case .active:
                model.handleForeground()
            default:
                break
            }
        }
        .onChange(of: model.committedPlyCount) { _, newPlyCount in
            if newPlyCount > 0 {
                ensureGameSaved()
            } else if newPlyCount == 0 {
                model.discardSavedRecord()
            }
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            syncVideoRotation()
            if model.engine.plyCount > 0 {
                ensureGameSaved()
            }
        }
        .onChange(of: model.phase) { _, newPhase in
            if newPhase == .gameOver || newPhase == .replay {
                ensureGameSaved()
            }
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onChange(of: verticalSizeClass) { _, _ in
            syncVideoRotation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            syncVideoRotation()
        }
    }

    @discardableResult
    private func ensureGameSaved() -> GameRecord? {
        guard let record = model.savedRecordIfNeeded() else { return nil }
        if record.modelContext == nil {
            modelContext.insert(record)
        }
        try? modelContext.save()
        return record
    }

    private func syncVideoRotation() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        model.updateVideoRotation(from: scene)
    }

    private var canCloseWithoutConfirm: Bool {
        switch model.phase {
        case .detectingBoard, .calibratingCorners, .confirmingStart, .importingVideo, .boardStudio, .pieceStudio:
            true
        default:
            false
        }
    }
}
