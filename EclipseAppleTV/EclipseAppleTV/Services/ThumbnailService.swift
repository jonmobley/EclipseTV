import UIKit
import AVFoundation

/// Service for generating and caching thumbnails
class ThumbnailService {
    static let shared = ThumbnailService()
    
    private let cache = NSCache<NSString, UIImage>()
    private let performanceMonitor = PerformanceMonitor.shared
    
    private init() {
        setupCache()
    }
    
    private func setupCache() {
        cache.countLimit = 200
        cache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }
    
    // MARK: - Public Methods
    func getThumbnail(for item: MediaItem, size: CGSize) async -> UIImage? {
        let cacheKey = "\(item.path)_\(Int(size.width))x\(Int(size.height))"
        
        // Check cache first
        if let cached = cache.object(forKey: NSString(string: cacheKey)) {
            return cached
        }
        
        // Generate thumbnail
        let thumbnail = await generateThumbnail(for: item, size: size)
        
        // Cache result
        if let thumbnail = thumbnail {
            let cost = Int(thumbnail.size.width * thumbnail.size.height * 4)
            cache.setObject(thumbnail, forKey: NSString(string: cacheKey), cost: cost)
        }
        
        return thumbnail
    }
    
    func preloadThumbnails(for items: [MediaItem], size: CGSize) async {
        await withTaskGroup(of: Void.self) { group in
            for item in items.prefix(10) { // Preload first 10
                group.addTask {
                    _ = await self.getThumbnail(for: item, size: size)
                }
            }
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
    
    // MARK: - Private Methods
    private func generateThumbnail(for item: MediaItem, size: CGSize) async -> UIImage? {
        return await performanceMonitor.measureAsync("ThumbnailService.generate") {
            if item.isVideo {
                return await generateVideoThumbnail(path: item.path, size: size)
            } else {
                return await generateImageThumbnail(path: item.path, size: size)
            }
        }
    }
    
    private func generateImageThumbnail(path: String, size: CGSize) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let image = UIImage(contentsOfFile: path) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let thumbnail = image.aspectFittedThumbnail(targetSize: size)
                continuation.resume(returning: thumbnail)
            }
        }
    }
    
    private func generateVideoThumbnail(path: String, size: CGSize) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let url = URL(fileURLWithPath: path)
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = size
            imageGenerator.requestedTimeToleranceBefore = .positiveInfinity
            imageGenerator.requestedTimeToleranceAfter = .positiveInfinity
            
            // Try multiple time points for best thumbnail
            let timePoints: [CMTime] = [
                CMTime(seconds: 2.0, preferredTimescale: 600),
                CMTime(seconds: 5.0, preferredTimescale: 600),
                CMTime(seconds: 0.5, preferredTimescale: 600),
                CMTime.zero
            ]
            
            for timePoint in timePoints {
                do {
                    let cgImage = try imageGenerator.copyCGImage(at: timePoint, actualTime: nil)
                    let thumbnail = UIImage(cgImage: cgImage)
                    continuation.resume(returning: thumbnail)
                    return
                } catch {
                    continue
                }
            }
            
            continuation.resume(returning: nil)
        }
    }
}

// MARK: - UIImage Extension
extension UIImage {
    func aspectFittedThumbnail(targetSize: CGSize) -> UIImage {
        let aspectRatio = size.width / size.height
        let targetAspectRatio = targetSize.width / targetSize.height
        
        let drawSize: CGSize
        if aspectRatio > targetAspectRatio {
            drawSize = CGSize(width: targetSize.width, height: targetSize.width / aspectRatio)
        } else {
            drawSize = CGSize(width: targetSize.height * aspectRatio, height: targetSize.height)
        }
        
        let renderer = UIGraphicsImageRenderer(size: drawSize)
        return renderer.image { context in
            self.draw(in: CGRect(origin: .zero, size: drawSize))
        }
    }
} 