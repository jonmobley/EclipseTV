//
//  SceneDelegate.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // Library / AirPlay chrome start in Landscape; Vertical is opt-in via Settings.
        ExternalOutputSettings.applyLaunchDefault()
        
        window = UIWindow(windowScene: windowScene)
        
        // Set main view controller
        let mainViewController = iPhoneMainViewController()
        window?.rootViewController = UINavigationController(rootViewController: mainViewController)
        window?.makeKeyAndVisible()

        // Set app to dark mode
        window?.overrideUserInterfaceStyle = .dark

        // Bridge the static launch storyboard into the live UI with a short fade.
        if let window {
            LaunchSplashView.present(over: window)
        }

        // Begin watching for an AirPlay-mirrored Apple TV (external display) so the
        // selected item can be presented fullscreen on it.
        ExternalDisplayManager.shared.start()

        // Warm the Website tile (real WKWebView) so its tap is instant + hero-ready.
        // Saved bookmarks warm as they scroll into view instead of all at launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WarmWebSessionPool.shared.warmFreeBrowse()
        }
    }

    // Note: app lifecycle work (reconnecting, pausing auto-connect timers) is handled via
    // UIApplication notifications in `iPhoneMainViewController+Setup.swift`, so the empty
    // UISceneSession lifecycle placeholders are intentionally omitted here.
}
