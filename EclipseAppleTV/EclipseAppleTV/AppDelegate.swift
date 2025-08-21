// AppDelegate.swift
import UIKit
import TVUIKit
import os.log
import MultipeerConnectivity

/// The AppDelegate responsible for application lifecycle management.
/// This class conforms to Apple TV HIG by providing a clean, simple startup sequence.
@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // MARK: - Properties
    
    /// The main application window (managed by SceneDelegate on tvOS)
    var window: UIWindow?
    
    /// Logger for troubleshooting application startup issues
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "AppDelegate")
    
    // Connection manager is managed by SceneDelegate on tvOS
    var connectionManager: ConnectionManager?

    // MARK: - Application Lifecycle
    
    /// Sets up the application's initial state and view hierarchy
    /// - Parameters:
    ///   - application: The singleton app instance
    ///   - launchOptions: Dictionary of options specified at launch
    /// - Returns: Success indicator for app launch
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        logger.info("Application did finish launching")
        // UIScene handles window and connection setup on tvOS
        return true
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        logger.info("Application became active")
        // SceneDelegate manages advertising
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        logger.info("Application will resign active")
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        logger.info("Application will enter foreground")
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        logger.info("Application did enter background")
        
        // Log performance summary before backgrounding
        PerformanceMonitor.shared.logPerformanceState()
        
        // Clean up some resources to free memory while backgrounded
        Task {
            await AsyncImageLoader.shared.clearCache()
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        logger.info("Application will terminate - cleaning up resources")
        
        // Clean up connection manager
        connectionManager?.cleanup()
        connectionManager = nil
        
        // Clear image caches asynchronously
        Task {
            await AsyncImageLoader.shared.clearCache()
        }
        VideoThumbnailCache.shared.clearCache()
    }
}
