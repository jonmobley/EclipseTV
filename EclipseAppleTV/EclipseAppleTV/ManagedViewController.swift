import UIKit
import os.log

/// Base view controller that automatically manages resources
class ManagedViewController: UIViewController {
    
    // MARK: - Properties
    private(set) var resourceManager = ResourceManager()
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "ManagedViewController")
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        logger.debug("ManagedViewController loaded: \(String(describing: type(of: self)))")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Clean up resources when view is disappearing permanently
        if isBeingDismissed || isMovingFromParent {
            logger.debug("Cleaning up resources for: \(String(describing: type(of: self)))")
            resourceManager.cleanup()
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Additional cleanup for edge cases
        if parent == nil && presentingViewController == nil {
            resourceManager.cleanup()
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Creates a managed timer that will be automatically cleaned up
    func createManagedTimer(interval: TimeInterval, repeats: Bool, block: @escaping () -> Void) -> Timer {
        return resourceManager.createTimer(interval: interval, repeats: repeats, block: block)
    }
    
    /// Adds a managed notification observer that will be automatically cleaned up
    func addManagedObserver(for name: Notification.Name, 
                           object: Any? = nil,
                           block: @escaping (Notification) -> Void) -> NSObjectProtocol {
        return resourceManager.addNotificationObserver(for: name, object: object, using: block)
    }
    
    /// Creates a managed async task that will be automatically cleaned up
    func createManagedTask(priority: TaskPriority = .medium, 
                          operation: @escaping () async -> Void) -> Task<Void, Never> {
        return resourceManager.createTask(priority: priority, operation: operation)
    }
    
    /// Manually trigger resource cleanup (useful for testing)
    func cleanupResources() {
        resourceManager.cleanup()
    }
    
    deinit {
        logger.debug("ManagedViewController deallocated: \(String(describing: type(of: self)))")
        resourceManager.cleanup()
    }
} 