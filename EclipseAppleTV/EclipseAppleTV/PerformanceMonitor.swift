import Foundation
import UIKit
import os.log

/// Performance monitoring and measurement system
class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "Performance")
    private var measurements: [String: MeasurementData] = [:]
    private var startTimes: [String: CFAbsoluteTime] = [:]
    private var frameRateMonitor: CADisplayLink?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    // Performance thresholds
    private let slowOperationThreshold: TimeInterval = 0.5 // 500ms
    private let verySlowOperationThreshold: TimeInterval = 1.0 // 1 second
    private let targetFrameRate: Double = 60.0
    
    struct MeasurementData {
        var totalTime: TimeInterval = 0
        var callCount: Int = 0
        var minTime: TimeInterval = Double.greatestFiniteMagnitude
        var maxTime: TimeInterval = 0
        var lastMeasurement: TimeInterval = 0
        
        var averageTime: TimeInterval {
            return callCount > 0 ? totalTime / Double(callCount) : 0
        }
        
        mutating func addMeasurement(_ time: TimeInterval) {
            totalTime += time
            callCount += 1
            minTime = min(minTime, time)
            maxTime = max(maxTime, time)
            lastMeasurement = time
        }
    }
    
    struct MemoryInfo {
        let used: Int64
        let free: Int64
        let total: Int64
        
        var usedMB: Double { Double(used) / (1024 * 1024) }
        var freeMB: Double { Double(free) / (1024 * 1024) }
        var totalMB: Double { Double(total) / (1024 * 1024) }
        var usagePercentage: Double { Double(used) / Double(total) * 100 }
    }
    
    private init() {
        setupMemoryPressureMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Start timing an operation
    func startTiming(_ operation: String) {
        startTimes[operation] = CFAbsoluteTimeGetCurrent()
    }
    
    /// End timing an operation and log results
    func endTiming(_ operation: String) {
        guard let startTime = startTimes.removeValue(forKey: operation) else {
            logger.warning("No start time found for operation: \(operation)")
            return
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        recordMeasurement(operation, duration: duration)
    }
    
    /// Measure a synchronous operation
    func measure<T>(_ operation: String, block: () throws -> T) rethrows -> T {
        startTiming(operation)
        defer { endTiming(operation) }
        return try block()
    }
    
    /// Measure an async operation
    func measureAsync<T>(_ operation: String, block: () async throws -> T) async rethrows -> T {
        startTiming(operation)
        defer { endTiming(operation) }
        return try await block()
    }
    
    /// Start monitoring frame rate
    func startFrameRateMonitoring() {
        guard frameRateMonitor == nil else { return }
        
        frameRateMonitor = CADisplayLink(target: self, selector: #selector(frameRateCallback))
        frameRateMonitor?.add(to: .main, forMode: .common)
        logger.info("Started frame rate monitoring")
    }
    
    /// Stop monitoring frame rate
    func stopFrameRateMonitoring() {
        frameRateMonitor?.invalidate()
        frameRateMonitor = nil
        logger.info("Stopped frame rate monitoring")
    }
    
    /// Get current memory usage
    func getMemoryInfo() -> MemoryInfo {
        var info = createMachTaskBasicInfo()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let used = Int64(info.resident_size)
            // Estimate total memory (this is approximate for tvOS)
            let total: Int64 = 3 * 1024 * 1024 * 1024 // 3GB for Apple TV 4K
            let free = total - used
            
            return MemoryInfo(used: used, free: free, total: total)
        } else {
            // Fallback values
            return MemoryInfo(used: 0, free: 0, total: 0)
        }
    }
    
    /// Get performance summary
    func getPerformanceSummary() -> String {
        let memInfo = getMemoryInfo()
        let sortedMeasurements = measurements.sorted { $0.value.averageTime > $1.value.averageTime }
        
        var summary = """
        📊 Performance Summary
        💾 Memory: \(String(format: "%.1f", memInfo.usedMB))MB used (\(String(format: "%.1f", memInfo.usagePercentage))%)
        
        🐌 Slowest Operations:
        """
        
        for (operation, data) in sortedMeasurements.prefix(5) {
            let avgMs = data.averageTime * 1000
            let maxMs = data.maxTime * 1000
            summary += """
            
            • \(operation): \(String(format: "%.1f", avgMs))ms avg (\(data.callCount) calls, max: \(String(format: "%.1f", maxMs))ms)
            """
        }
        
        return summary
    }
    
    /// Reset all measurements
    func resetMeasurements() {
        measurements.removeAll()
        logger.info("Performance measurements reset")
    }
    
    /// Log current performance state
    func logPerformanceState() {
        logger.info("\(self.getPerformanceSummary())")
    }
    
    // MARK: - Private Methods
    
    private func recordMeasurement(_ operation: String, duration: TimeInterval) {
        if measurements[operation] == nil {
            measurements[operation] = MeasurementData()
        }
        measurements[operation]?.addMeasurement(duration)
        
        let durationMs = duration * 1000
        
        // Log based on duration
        if duration > verySlowOperationThreshold {
            logger.error("🐌 Very slow operation: \(operation) took \(String(format: "%.1f", durationMs))ms")
        } else if duration > slowOperationThreshold {
            logger.warning("⚠️ Slow operation: \(operation) took \(String(format: "%.1f", durationMs))ms")
        } else {
            logger.debug("⏱️ \(operation): \(String(format: "%.1f", durationMs))ms")
        }
        
        // Check for performance regression
        if let data = measurements[operation], data.callCount > 5 {
            let recentAverage = data.averageTime
            if duration > recentAverage * 2.0 {
                logger.warning("📈 Performance regression detected in \(operation): \(String(format: "%.1f", durationMs))ms vs \(String(format: "%.1f", recentAverage * 1000))ms avg")
            }
        }
    }
    
    @objc private func frameRateCallback() {
        guard let displayLink = frameRateMonitor else { return }
        
        // Calculate actual frame rate using duration
        let actualFrameRate = 1.0 / displayLink.duration
        
        // Only log if frame rate is significantly low (avoid spam during startup)
        if actualFrameRate > 0 && actualFrameRate < targetFrameRate * 0.8 {
            logger.warning("🎞️ Low frame rate detected: \(String(format: "%.1f", actualFrameRate)) FPS")
        }
    }
    
    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .main)
        
        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            let memInfo = self.getMemoryInfo()
            
            if memInfo.usagePercentage > 80 {
                self.logger.warning("🔥 High memory usage: \(String(format: "%.1f", memInfo.usagePercentage))%")
                
                // Suggest cleanup
                NotificationCenter.default.post(
                    name: Notification.Name("MemoryPressureDetected"),
                    object: memInfo
                )
            }
        }
        
        memoryPressureSource?.resume()
    }
    
    deinit {
        stopFrameRateMonitoring()
        memoryPressureSource?.cancel()
    }
}

// MARK: - Convenience Extensions
extension PerformanceMonitor {
    /// Quick measurement for image operations
    func measureImageOperation<T>(_ operation: String, block: () throws -> T) rethrows -> T {
        return try measure("Image.\(operation)", block: block)
    }
    
    /// Quick measurement for video operations
    func measureVideoOperation<T>(_ operation: String, block: () throws -> T) rethrows -> T {
        return try measure("Video.\(operation)", block: block)
    }
    
    /// Quick measurement for UI operations
    func measureUIOperation<T>(_ operation: String, block: () throws -> T) rethrows -> T {
        return try measure("UI.\(operation)", block: block)
    }
    
    /// Quick measurement for network operations
    func measureNetworkOperation<T>(_ operation: String, block: () throws -> T) rethrows -> T {
        return try measure("Network.\(operation)", block: block)
    }
}

// MARK: - Memory Helper Functions
private func createMachTaskBasicInfo() -> mach_task_basic_info {
    var info = mach_task_basic_info()
    info.virtual_size = 0
    info.resident_size = 0
    info.resident_size_max = 0
    info.user_time = time_value_t()
    info.system_time = time_value_t()
    info.policy = 0
    info.suspend_count = 0
    return info
} 