import UIKit

// Plain UIKit lifecycle.
//
// This started as a SwiftUI `WindowGroup` wrapping the game view controller in
// a `UIViewControllerRepresentable`, and on iPadOS 27 that launched to a window
// with nothing drawn in it — the app ran, the scene existed, the content never
// appeared. Since everything here except the grown-up panel is UIKit anyway,
// hosting the view controller directly removes that whole layer rather than
// trying to coax it into behaving.

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: "Default Configuration", sessionRole: connectingSceneSession.role)
        // Named in code rather than in the Info.plist, so the generated scene
        // manifest doesn't have to know about this class.
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene, willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
