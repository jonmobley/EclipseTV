//
//  SceneDelegate.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // Library / AirPlay chrome start in Landscape; Vertical is opt-in via Settings.
        ExternalOutputSettings.applyLaunchDefault()
        ExternalOutputSettings.restoreLandscapeIfNoVerticalShows(
            LocalAlbumStore.shared.albums
        )
        
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

        // Cold-start from an `eclipse://mac-remote` QR scan.
        if let url = connectionOptions.urlContexts.first?.url {
            handleIncomingURL(url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handleIncomingURL(url)
    }

    // MARK: - Deep Links

    /// Opens Eclipse for Mac remote or Phone Camera when Camera hands us a QR URL.
    private func handleIncomingURL(_ url: URL) {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        guard scheme == ConnectURLParser.appScheme || scheme == "eclipse" else {
            return
        }
        // Defer until after splash / first layout so presentation has a host VC.
        DispatchQueue.main.async {
            if host == "phone-camera" {
                PhoneCameraSendLauncher.open(connectString: url.absoluteString)
            } else if host == ConnectURLParser.appHost {
                MacRemoteLauncher.open(connectString: url.absoluteString)
            }
        }
    }

    // Note: app lifecycle work (reconnecting, pausing auto-connect timers) is handled via
    // UIApplication notifications in `iPhoneMainViewController+Setup.swift`, so the empty
    // UISceneSession lifecycle placeholders are intentionally omitted here.

    /// Accepts a Show shared via CloudKit (`CKShare` link).
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let container = CKContainer(identifier: CloudKitSchema.containerIdentifier)
        let op = CKAcceptSharesOperation(shareMetadatas: [cloudKitShareMetadata])
        op.acceptSharesResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Shared CKSyncEngine will fetch the zone contents.
                    NotificationCenter.default.post(
                        name: LocalAlbumStore.didChangeNotification,
                        object: nil
                    )
                case .failure(let error):
                    let alert = UIAlertController(
                        title: "Unable to Accept Share",
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.window?.rootViewController?.present(alert, animated: true)
                }
            }
        }
        container.add(op)
    }
}
