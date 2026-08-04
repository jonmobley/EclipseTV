//
//  AppDelegate.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Boots CloudKit private + shared sync engines when an iCloud account exists.
        EclipseSyncController.shared.start()
        DefaultBackgroundMusic.armOnFirstLaunchIfNeeded()
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            let config = UISceneConfiguration(
                name: "External Display",
                sessionRole: .windowExternalDisplayNonInteractive
            )
            config.delegateClass = ExternalSceneDelegate.self
            return config
        }

        return UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        // No persistent per-scene state beyond ExternalDisplayManager's live session.
    }
}
