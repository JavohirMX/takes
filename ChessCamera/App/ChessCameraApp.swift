import SwiftUI

@main
struct ChessCameraApp: App {
    var body: some Scene {
        WindowGroup {
            HistoryView()
                .preferredColorScheme(.dark)
        }
    }
}
