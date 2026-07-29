//
//  AsyncImageLoader.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import ImageIO
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
        
        // Check cache first
        if let cached = cache.object(forKey: NSString(string: cacheKey)) {
            return cached
        }
        
        // Check if operation is already running
        if let ongoingTask = ongoingOperations[cacheKey] {
            return await ongoingTask.value
        }
        
        // Create new loading task
        let task = Task<UIImage?, Never> {
            defer { 
                Task { self.removeOngoingOperation(for: cacheKey) }
            }
            
            return await self.loadImageFromDisk(path: path, targetSize: targetSize, cacheKey: cacheKey)
        }
        
        ongoingOperations[cacheKey] = task
        return await task.value
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

    /// Loads and optionally downsamples via ImageIO so large photos never decode at
    /// full resolution into RAM before being resized for the grid.
    private func loadImageFromDisk(path: String, targetSize: CGSize?, cacheKey: String) async -> UIImage? {
        guard fileManager.fileExists(atPath: path) else {
            logger.warning("Image file not found: \(path, privacy: .public)")
            return nil
        }

        let url = URL(fileURLWithPath: path)
        let scale = await displayScale()
        guard let image = Self.downsampledImage(
            at: url, targetSize: targetSize, scale: scale
        ) else {
            logger.error("Failed to decode image: \(path, privacy: .public)")
            return nil
        }

        let cost = Int(image.size.width * image.size.height * 4.0)
        cache.setObject(image, forKey: NSString(string: cacheKey), cost: cost)
        return image
    }

    /// Screen scale, sampled once on the main actor.
    ///
    /// Callers pass `targetSize` in points but ImageIO wants pixels, and the loader's own
    /// executor can't touch `UIScreen`. It's a constant for the life of the process, so
    /// one hop is cheaper than threading it through every call site.
    private var cachedDisplayScale: CGFloat?

    private func displayScale() async -> CGFloat {
        if let cachedDisplayScale { return cachedDisplayScale }
        let scale = await MainActor.run { UIScreen.main.scale }
        cachedDisplayScale = scale
        return scale
    }

    /// Creates a thumbnail-sized `UIImage` using `CGImageSourceCreateThumbnailAtIndex`.
    /// When `targetSize` is nil, still caps at 3840px on the long edge to bound memory.
    private static func downsampledImage(
        at url: URL,
        targetSize: CGSize?,
        scale: CGFloat
    ) -> UIImage? {
        let maxPixel: CGFloat
        if let targetSize {
            maxPixel = max(targetSize.width, targetSize.height) * scale
        } else {
            maxPixel = 3840
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
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
