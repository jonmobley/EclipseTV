import Foundation
import AVFoundation
import os.log

/// Manages preloading and caching of video assets for smooth transitions
@MainActor
class VideoCacheManager {
    static let shared = VideoCacheManager()
    
    private let logger = Logger(subsystem: "EclipseAppleTV", category: "VideoCacheManager")
    private let maxCacheSize = 10 // Maximum number of videos to keep cached
    private let preloadDistance = 2 // Number of videos to preload on each side
    
    // Cache storage
    private var assetCache: [String: AVURLAsset] = [:]
    private var cacheAccessTimes: [String: Date] = [:]
    private var preloadingTasks: [String: Task<Void, Never>] = [:]
    
    // Memory pressure monitoring
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    private init() {
        setupMemoryPressureMonitoring()
    }
    
    deinit {
        memoryPressureSource?.cancel()
        // Cancel tasks synchronously in deinit
        for task in preloadingTasks.values {
            task.cancel()
        }
        preloadingTasks.removeAll()
    }
    
    // MARK: - Public Interface
    
    /// Gets a cached asset if available, otherwise returns nil
    func getCachedAsset(for path: String) -> AVURLAsset? {
        if let asset = assetCache[path] {
            cacheAccessTimes[path] = Date()
            logger.debug("📹 Cache HIT for: \(URL(fileURLWithPath: path).lastPathComponent)")
            return asset
        }
        logger.debug("📹 Cache MISS for: \(URL(fileURLWithPath: path).lastPathComponent)")
        return nil
    }
    
    /// Preloads video assets for the specified paths
    func preloadVideos(paths: [String]) {
        for path in paths {
            preloadVideo(at: path)
        }
    }
    
    /// Preloads videos around a specific index in the media collection
    func preloadVideosAroundIndex(_ index: Int, in dataSource: MediaDataSource) {
        let totalCount = dataSource.count
        let startIndex = max(0, index - preloadDistance)
        let endIndex = min(totalCount - 1, index + preloadDistance)
        
        for i in startIndex...endIndex {
            guard let path = dataSource.getPath(at: i),
                  isVideoFile(path) else { continue }
            preloadVideo(at: path)
        }
    }
    
    /// Preloads the first few videos for app launch
    func preloadInitialVideos(from dataSource: MediaDataSource) {
        let initialCount = min(5, dataSource.count)
        for i in 0..<initialCount {
            guard let path = dataSource.getPath(at: i),
                  isVideoFile(path) else { continue }
            preloadVideo(at: path)
        }
    }
    
    /// Clears all cached assets
    func clearCache() {
        logger.info("📹 Clearing video cache")
        cancelAllPreloadingTasks()
        assetCache.removeAll()
        cacheAccessTimes.removeAll()
    }
    
    /// Returns cache statistics for debugging
    func getCacheStats() -> (cachedCount: Int, preloadingCount: Int) {
        return (assetCache.count, preloadingTasks.count)
    }
    
    // MARK: - Private Methods
    
    private func preloadVideo(at path: String) {
        // Skip if already cached or being preloaded
        if assetCache[path] != nil || preloadingTasks[path] != nil {
            return
        }
        
        logger.debug("📹 Starting preload for: \(URL(fileURLWithPath: path).lastPathComponent)")
        
        let task = Task { [weak self] in
            await self?.performPreload(for: path)
            return ()
        }
        
        preloadingTasks[path] = task
    }
    
    private func performPreload(for path: String) async {
        guard FileManager.default.fileExists(atPath: path) else {
            logger.warning("📹 File not found for preload: \(path)")
            preloadingTasks.removeValue(forKey: path)
            return
        }
        
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        
        do {
            // Preload essential properties for smooth playback
            let _ = try await asset.load(.duration)
            let _ = try await asset.load(.tracks)
            
            // Cache the asset if task wasn't cancelled
            if !Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.storeAssetInCache(asset, for: path)
                }
            }
            
        } catch {
            if !Task.isCancelled {
                logger.error("📹 Failed to preload video: \(error.localizedDescription)")
            }
        }
        
        preloadingTasks.removeValue(forKey: path)
    }
    
    private func storeAssetInCache(_ asset: AVURLAsset, for path: String) {
        // Check cache size and evict if necessary
        if assetCache.count >= maxCacheSize {
            evictLeastRecentlyUsed()
        }
        
        assetCache[path] = asset
        cacheAccessTimes[path] = Date()
        
        logger.debug("📹 Cached asset for: \(URL(fileURLWithPath: path).lastPathComponent) (cache size: \(self.assetCache.count))")
    }
    
    private func evictLeastRecentlyUsed() {
        guard let oldestPath = cacheAccessTimes.min(by: { $0.value < $1.value })?.key else {
            return
        }
        
        assetCache.removeValue(forKey: oldestPath)
        cacheAccessTimes.removeValue(forKey: oldestPath)
        
        logger.debug("📹 Evicted LRU asset: \(URL(fileURLWithPath: oldestPath).lastPathComponent)")
    }
    
    private func cancelAllPreloadingTasks() {
        for task in preloadingTasks.values {
            task.cancel()
        }
        preloadingTasks.removeAll()
    }
    
    private func isVideoFile(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["mp4", "mov", "m4v"].contains(ext)
    }
    
    // MARK: - Memory Pressure Monitoring
    
    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue.main
        )
        
        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            let event = self.memoryPressureSource?.mask
            if event?.contains(.critical) == true {
                self.logger.warning("📹 Critical memory pressure - clearing video cache")
                self.clearCache()
            } else if event?.contains(.warning) == true {
                self.logger.info("📹 Memory pressure warning - reducing cache size")
                self.reduceCacheSize()
            }
        }
        
        memoryPressureSource?.resume()
    }
    
    private func reduceCacheSize() {
        let targetSize = max(3, maxCacheSize / 2)
        while assetCache.count > targetSize {
            evictLeastRecentlyUsed()
        }
    }
}
