import SwiftUI
import UIKit

struct SessionFlowView: View {
    @Bindable var model: RecordingSessionViewModel
    var onFinished: (GameRecord?) -> Void
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
                case .confirmingStart:
                    ConfirmStartView(model: model)
                case .recording, .disturbed, .awaitingEdit:
                    LiveRecordingView(model: model)
                case .gameOver:
                    GameOverView(
                        model: model,
                        onReplay: { replayFromGameOver = true },
                        onDone: { onFinished(model.savedRecordIfNeeded()) }
                    )
                case .replay:
                    ReplayView(pgn: model.pgn, title: "Replay")
                }
            }
            .navigationDestination(isPresented: $replayFromGameOver) {
                ReplayView(pgn: model.pgn, title: "Replay")
            }
            .overlay(alignment: .topLeading) {
                if canCloseWithoutConfirm {
                    Button {
                        Task {
                            await model.teardown()
                            onFinished(nil)
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
                model.handleBackground()
            case .active:
                model.handleForeground()
            default:
                break
            }
        }
        .onAppear { syncVideoRotation() }
        .onChange(of: verticalSizeClass) { _, _ in
            syncVideoRotation()
        }
    }

    private func syncVideoRotation() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        model.updateVideoRotation(from: scene)
    }

    private var canCloseWithoutConfirm: Bool {
        switch model.phase {
        case .detectingBoard, .calibratingCorners, .confirmingStart, .importingVideo, .boardStudio:
            true
        default:
            false
        }
    }
}
