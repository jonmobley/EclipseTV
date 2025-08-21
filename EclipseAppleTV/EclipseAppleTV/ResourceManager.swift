import UIKit
import AVFoundation
import os.log

/// Manages resources like timers, observers, and tasks to prevent memory leaks
class ResourceManager {
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "ResourceManager")
    
    // MARK: - Resource Tracking
    private var timers: Set<Timer> = []
    private var tasks: Set<Task<Void, Never>> = []
    private var avPlayerObservers: [(player: AVPlayer, observer: NSKeyValueObservation)] = []
    private var notificationObservers: [String: NSObjectProtocol] = [:]
    
    // MARK: - Timer Management
    func createTimer(interval: TimeInterval, repeats: Bool, block: @escaping () -> Void) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            block()
        }
        timers.insert(timer)
        logger.debug("Created timer with interval \(interval)s, repeats: \(repeats)")
        return timer
    }
    
    func invalidateTimer(_ timer: Timer) {
        timer.invalidate()
        timers.remove(timer)
        logger.debug("Invalidated timer")
    }
    
    func invalidateAllTimers() {
        let timerCount = timers.count
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        logger.debug("Invalidated \(timerCount) timers")
    }
    
    // MARK: - Notification Observer Management
    func addNotificationObserver(for name: Notification.Name, 
                                object: Any? = nil, 
                                queue: OperationQueue? = nil,
                                using block: @escaping (Notification) -> Void) -> NSObjectProtocol {
        let observer = NotificationCenter.default.addObserver(
            forName: name,
            object: object,
            queue: queue,
            using: block
        )
        
        let key = "\(name.rawValue)_\((object as AnyObject?)?.hash ?? 0)"
        notificationObservers[key] = observer
        
        logger.debug("Added notification observer for \(name.rawValue)")
        return observer
    }
    
    func removeNotificationObserver(for name: Notification.Name, object: Any? = nil) {
        let key = "\(name.rawValue)_\((object as AnyObject?)?.hash ?? 0)"
        if let observer = notificationObservers.removeValue(forKey: key) {
            NotificationCenter.default.removeObserver(observer)
            logger.debug("Removed notification observer for \(name.rawValue)")
        }
    }
    
    func removeAllNotificationObservers() {
        for observer in notificationObservers.values {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        logger.debug("Removed all notification observers")
    }
    
    // MARK: - AVPlayer Observer Management
    func addPlayerObserver(_ player: AVPlayer, 
                          keyPath: String, 
                          options: NSKeyValueObservingOptions = [],
                          changeHandler: @escaping (Any?, Any?) -> Void) -> NSKeyValueObservation {
        let observation = player.observe(\.currentItem, options: options) { player, change in
            changeHandler(change.oldValue, change.newValue)
        }
        
        avPlayerObservers.append((player: player, observer: observation))
        logger.debug("Added AVPlayer observer for keyPath: \(keyPath)")
        return observation
    }
    
    func removePlayerObservers(for player: AVPlayer) {
        avPlayerObservers.removeAll { pair in
            if pair.player === player {
                pair.observer.invalidate()
                logger.debug("Removed AVPlayer observer")
                return true
            }
            return false
        }
    }
    
    func removeAllPlayerObservers() {
        for pair in avPlayerObservers {
            pair.observer.invalidate()
        }
        avPlayerObservers.removeAll()
        logger.debug("Removed all AVPlayer observers")
    }
    
    // MARK: - Task Management
    func createTask(priority: TaskPriority = .medium, 
                   operation: @escaping () async -> Void) -> Task<Void, Never> {
        let task = Task(priority: priority) {
            await operation()
        }
        tasks.insert(task)
        
        // Auto-remove completed tasks
        Task {
            await task.value
            self.tasks.remove(task)
        }
        
        logger.debug("Created async task with priority: \(priority)")
        return task
    }
    
    func cancelAllTasks() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        logger.debug("Cancelled all async tasks")
    }
    
    // MARK: - Complete Cleanup
    func cleanup() {
        invalidateAllTimers()
        removeAllNotificationObservers()
        removeAllPlayerObservers()
        cancelAllTasks()
        logger.info("Complete resource cleanup performed")
    }
    
    // MARK: - Status Reporting
    func getResourceStatus() -> String {
        return """
        Resource Manager Status:
        - Timers: \(timers.count)
        - Notification Observers: \(notificationObservers.count)
        - AVPlayer Observers: \(avPlayerObservers.count)
        - Active Tasks: \(tasks.count)
        """
    }
    
    deinit {
        cleanup()
        logger.debug("ResourceManager deinitialized")
    }
}

// MARK: - Convenience Extensions
extension ResourceManager {
    /// Convenience method for common video playback end notification
    func addVideoEndObserver(for player: AVPlayer, completion: @escaping () -> Void) -> NSObjectProtocol {
        return addNotificationObserver(
            for: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        ) { _ in
            completion()
        }
    }
    
    /// Convenience method for connection state changes
    func addConnectionStateObserver(completion: @escaping (Notification) -> Void) -> NSObjectProtocol {
        return addNotificationObserver(
            for: NSNotification.Name("ConnectionStateChanged")
        ) { notification in
            completion(notification)
        }
    }
} 