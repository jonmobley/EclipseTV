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
        
        window = UIWindow(windowScene: windowScene)
        
        // Set main view controller
        let mainViewController = iPhoneMainViewController()
        window?.rootViewController = UINavigationController(rootViewController: mainViewController)
        window?.makeKeyAndVisible()
        
        // Set app to dark mode
        window?.overrideUserInterfaceStyle = .dark

        // Begin watching for an AirPlay-mirrored Apple TV (external display) so the
        // selected item can be presented fullscreen on it.
        ExternalDisplayManager.shared.start()
    }

    // Note: app lifecycle work (reconnecting, pausing auto-connect timers) is handled via
    // UIApplication notifications in `iPhoneMainViewController+Setup.swift`, so the empty
    // UISceneSession lifecycle placeholders are intentionally omitted here.
}
