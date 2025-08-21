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
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called when scene is being released
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when scene has moved from inactive to active state
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when scene will move from active to inactive state
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as scene transitions from background to foreground
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as scene transitions from foreground to background
    }
}
