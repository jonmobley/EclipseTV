import UIKit
import os.log

actor AsyncImageLoader {
    static let shared = AsyncImageLoader()
    
    // MARK: - Properties
    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "AsyncImageLoader")
    
    // Track ongoing operations to avoid duplicates
    private var ongoingOperations: [String: Task<UIImage?, Never>] = [:]
    
    private init() {
        // Configure cache
        cache.countLimit = 100  // Keep 100 images in memory
        cache.totalCostLimit = 100 * 1024 * 1024  // 100MB limit
    }
    
    // MARK: - Public Methods
    func loadImage(from path: String, targetSize: CGSize? = nil) async -> UIImage? {
        let cacheKey = makeCacheKey(path: path, targetSize: targetSize)
        
        logger.debug("🔍 [ASYNC-LOADER] Loading image from path: \(path)")
        logger.debug("🔍 [ASYNC-LOADER] Target size: \(targetSize?.debugDescription ?? "nil")")
        logger.debug("🔍 [ASYNC-LOADER] Cache key: \(cacheKey)")
        
        // Check cache first
        let cached = cache.object(forKey: NSString(string: cacheKey))
        
        if let cached = cached {
            logger.debug("🔍 [ASYNC-LOADER] Cache HIT - returning cached image")
            return cached
        }
        
        logger.debug("🔍 [ASYNC-LOADER] Cache MISS - need to load from disk")
        
        // Check if operation is already running
        if let ongoingTask = ongoingOperations[cacheKey] {
            logger.debug("🔍 [ASYNC-LOADER] Found ongoing operation, waiting for result")
            return await ongoingTask.value
        }
        
        logger.debug("🔍 [ASYNC-LOADER] Creating new loading task")
        
        // Create new loading task
        let task = Task<UIImage?, Never> {
            defer { 
                Task { self.removeOngoingOperation(for: cacheKey) }
            }
            
            return await self.loadImageFromDisk(path: path, targetSize: targetSize, cacheKey: cacheKey)
        }
        
        ongoingOperations[cacheKey] = task
        let result = await task.value
        
        logger.debug("🔍 [ASYNC-LOADER] Task completed, result: \(result != nil ? "SUCCESS" : "FAILED")")
        return result
    }
    
    func preloadImages(at paths: [String], targetSize: CGSize) async {
        await withTaskGroup(of: Void.self) { group in
            for path in paths.prefix(10) {  // Only preload first 10 to avoid memory pressure
                group.addTask {
                    _ = await self.loadImage(from: path, targetSize: targetSize)
                }
            }
        }
    }
    
    func clearCache() async {
        cache.removeAllObjects()
        ongoingOperations.removeAll()
        logger.info("Image cache cleared")
    }
    
    func getCacheStatus() -> (count: Int, cost: Int) {
        return (count: cache.countLimit, cost: cache.totalCostLimit)
    }
    
    // MARK: - Private Methods
    private func loadImageFromDisk(path: String, targetSize: CGSize?, cacheKey: String) async -> UIImage? {
        logger.debug("💾 [DISK-LOAD] Starting disk load for path: \(path)")
        
        // Check if file exists
        guard fileManager.fileExists(atPath: path) else {
            logger.warning("💾 [DISK-LOAD] ❌ Image file not found: \(path)")
            return nil
        }
        
        logger.debug("💾 [DISK-LOAD] ✅ File exists, loading image")
        
        // Load image (since we're in an actor, this is already off the main queue)
        logger.debug("💾 [DISK-LOAD] Loading image on background queue")
        
        // Load image
        guard let image = UIImage(contentsOfFile: path) else {
            logger.error("💾 [DISK-LOAD] ❌ Failed to load image from file: \(path)")
            return nil
        }
        
        logger.debug("💾 [DISK-LOAD] ✅ Image loaded successfully")
        
        // Resize if needed
        let finalImage: UIImage
        if let targetSize: CGSize = targetSize {
            logger.debug("💾 [DISK-LOAD] Resizing image to target size")
            finalImage = image.resized(to: targetSize) as UIImage
            logger.debug("💾 [DISK-LOAD] ✅ Image resized successfully")
        } else {
            logger.debug("💾 [DISK-LOAD] No resizing needed, using original image")
            finalImage = image
        }
        
        logger.debug("💾 [DISK-LOAD] ✅ Final image ready, caching result")
        
        // Cache the result
        let cost: Int = Int(finalImage.size.width * finalImage.size.height * 4.0) // Rough memory cost
        cache.setObject(finalImage, forKey: NSString(string: cacheKey), cost: cost)
        logger.debug("💾 [DISK-LOAD] ✅ Image cached successfully")
        
        return finalImage
    }
    
    private func makeCacheKey(path: String, targetSize: CGSize?) -> String {
        if let size: CGSize = targetSize {
            return "\(path)_\(Int(size.width))x\(Int(size.height))"
        }
        return path
    }
    
    private func removeOngoingOperation(for key: String) {
        ongoingOperations.removeValue(forKey: key)
    }
}

// MARK: - UIImage Extension
extension UIImage {
    func resized(to targetSize: CGSize) -> UIImage {
        // Calculate size that fits within target while maintaining aspect ratio
        let aspectFittedSize = self.aspectFittedSize(in: targetSize)
        
        let renderer = UIGraphicsImageRenderer(size: aspectFittedSize)
        return renderer.image { context in
            self.draw(in: CGRect(origin: .zero, size: aspectFittedSize))
        }
    }
    
    func aspectFittedSize(in bounds: CGSize) -> CGSize {
        let aspectRatio = size.width / size.height
        let boundsAspectRatio = bounds.width / bounds.height
        
        if aspectRatio > boundsAspectRatio {
            // Image is wider - fit to width
            let height = bounds.width / aspectRatio
            return CGSize(width: bounds.width, height: height)
        } else {
            // Image is taller - fit to height
            let width = bounds.height * aspectRatio
            return CGSize(width: width, height: bounds.height)
        }
    }
} 