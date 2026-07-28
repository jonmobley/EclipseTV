//
//  ExternalSceneDelegate.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Hosts `PresentationViewController` on an AirPlay / wired external display scene.
///
/// Attaching a window to `.windowExternalDisplayNonInteractive` replaces system
/// mirroring with app-owned TV content. Releasing or hiding that window returns
/// AirPlay to phone mirroring — so we keep it alive across background transitions.
final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = ExternalDisplayManager.shared.attach(to: windowScene)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        ExternalDisplayManager.shared.keepPresentationAlive()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // App switcher: do not hide — hidden external windows snap back to mirroring.
        window?.isHidden = false
        ExternalDisplayManager.shared.keepPresentationAlive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        window?.isHidden = false
        ExternalDisplayManager.shared.keepPresentationAlive()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Do not nil `window` here. Manager retains it and defers teardown so a
        // transient disconnect (common when minimizing) doesn't flash mirroring.
        ExternalDisplayManager.shared.didDisconnect(from: scene)
    }
}
