// SceneDelegate.swift
import UIKit
import os.log
import MultipeerConnectivity

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "SceneDelegate")
    var connectionManager: ConnectionManager?
    var librarySync: TVLibrarySync?

	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
		guard let windowScene = scene as? UIWindowScene else { return }
		let window = UIWindow(windowScene: windowScene)
		let root = ImageViewController()
		window.rootViewController = root
		self.window = window
		window.makeKeyAndVisible()

		// Initialize and start advertising
		connectionManager = ConnectionManager()
		connectionManager?.delegate = root
		root.connectionManager = connectionManager

		// Wire up library mirroring to the companion app
		if let connectionManager = connectionManager {
			let sync = TVLibrarySync(connectionManager: connectionManager)
			connectionManager.librarySync = sync
			librarySync = sync
		}

		connectionManager?.startAdvertising()

		logger.info("🌅 [SCENE] Window connected. Root=ImageViewController, advertising started")
	}

	func sceneDidDisconnect(_ scene: UIScene) {
        logger.info("🌇 [SCENE] Scene disconnected - tearing down connection manager")
        connectionManager?.cleanup()
        connectionManager = nil
        librarySync = nil
    }

	func sceneDidBecomeActive(_ scene: UIScene) {
        logger.info("Scene did become active")
        connectionManager?.startAdvertising()

        // Re-sync the remote album when returning to the foreground. This also (re)opens
        // the Realtime subscription so server-side changes push to the TV while it's open.
        (window?.rootViewController as? ImageViewController)?.refreshAlbumIfConfigured()
    }
    func sceneWillResignActive(_ scene: UIScene) {
        logger.info("⏸️ [SCENE] Scene will resign active")
    }
    func sceneWillEnterForeground(_ scene: UIScene) {
        logger.info("🚪 [SCENE] Scene will enter foreground")
    }
	func sceneDidEnterBackground(_ scene: UIScene) {
        logger.info("Scene did enter background")

        // Drop the Realtime WebSocket while backgrounded; the foreground re-sync in
        // sceneDidBecomeActive reopens it and catches anything missed in the meantime.
        (window?.rootViewController as? ImageViewController)?.albumNotifier.stop()
    }
}


