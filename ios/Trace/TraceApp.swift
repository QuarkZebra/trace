import UIKit

/// Startup breadcrumbs, written three ways because on a device none of them is
/// reliable on its own: print() reaches `devicectl --console`, NSLog reaches the
/// unified log, and the file in Documents can be pulled off with
/// `devicectl device copy from` without needing root or a debugger.
func bootLog(_ message: String) {
    print("TRACE-BOOT \(message)")
    NSLog("TRACE-BOOT %@", message)
    guard
        let dir = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
        let data = "\(Date()) \(message)\n".data(using: .utf8)
    else { return }
    let url = dir.appendingPathComponent("boot.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}

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
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        bootLog("didFinishLaunching")
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        bootLog("configurationForConnecting role=\(connectingSceneSession.role.rawValue)")
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
        bootLog("scene willConnectTo, scene is UIWindowScene: \(scene is UIWindowScene)")
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
        bootLog(
            "window frame \(NSCoder.string(for: window.frame)) "
                + "key=\(window.isKeyWindow) hidden=\(window.isHidden) "
                + "root=\(String(describing: window.rootViewController))")
    }
}
