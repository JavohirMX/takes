import SwiftData
import SwiftUI
import UIKit

final class ChessCameraAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .allButUpsideDown
    }
}

@main
struct ChessCameraApp: App {
    @UIApplicationDelegateAdaptor(ChessCameraAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            HistoryView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: GameRecord.self)
    }
}
