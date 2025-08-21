// SceneDelegate.swift
import UIKit
import os.log
import MultipeerConnectivity

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "SceneDelegate")
    var connectionManager: ConnectionManager?

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
		connectionManager?.startAdvertising()

		logger.info("🌅 [SCENE] Window connected. Root=ImageViewController, advertising started")
	}

	func sceneDidBecomeActive(_ scene: UIScene) {
        logger.info("Scene did become active")
        connectionManager?.startAdvertising()
    }
    func sceneWillResignActive(_ scene: UIScene) {
        logger.info("⏸️ [SCENE] Scene will resign active")
    }
    func sceneWillEnterForeground(_ scene: UIScene) {
        logger.info("🚪 [SCENE] Scene will enter foreground")
    }
	func sceneDidEnterBackground(_ scene: UIScene) {
        logger.info("Scene did enter background")
    }
}


