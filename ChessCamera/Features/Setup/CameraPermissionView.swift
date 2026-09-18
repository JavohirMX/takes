import AVFoundation
import SwiftUI
import UIKit

struct CameraPermissionView: View {
    var onAuthorized: () -> Void
    var onCancel: () -> Void

    @State private var status = LiveCameraSource.authorizationStatus()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)

                Text("Camera access")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(copy)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                if status == .denied || status == .restricted {
                    PrimaryButton(title: "Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } else {
                    PrimaryButton(title: "Allow camera") {
                        Task { await request() }
                    }
                }

                Button("Cancel", action: onCancel)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 44)
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
        .task {
            if status == .authorized {
                onAuthorized()
            } else if status == .notDetermined {
                await request()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status = LiveCameraSource.authorizationStatus()
            if status == .authorized {
                onAuthorized()
            }
        }
    }

    private var copy: String {
        switch status {
        case .denied, .restricted:
            "Takes needs the camera to watch the board. Turn it on in Settings."
        default:
            "Takes watches the board to record your game."
        }
    }

    private func request() async {
        _ = await LiveCameraSource.ensureAuthorized()
        status = LiveCameraSource.authorizationStatus()
        if status == .authorized {
            onAuthorized()
        }
    }
}
