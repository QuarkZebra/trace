import SwiftUI
import UIKit

@main
struct TraceApp: App {
    var body: some Scene {
        WindowGroup {
            GameHost()
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
                .statusBarHidden()
        }
    }
}

private struct GameHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GameViewController { GameViewController() }
    func updateUIViewController(_ vc: GameViewController, context: Context) {}
}
