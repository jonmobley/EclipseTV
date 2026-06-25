import UIKit
import AVFoundation
import os.log

/// Memory + disk cache for video thumbnails.
class VideoThumbnailCache {
    static let shared = VideoThumbnailCache()
    
    private var cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let logger = Logger(subsystem: "com.eclipseapp.appletv", category: "ThumbnailCache")
    
    private init() {
        // Set up in-memory cache
        cache.countLimit = 100
        
        // Set up disk cache
        let appSupportDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupportDir.appendingPathComponent("VideoThumbnails", isDirectory: true)
        
        // Create cache directory if needed
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            do {
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create thumbnail cache directory: \(error.localizedDescription)")
            }
        }
    }
    
    func getThumbnail(for videoPath: String) -> UIImage? {
        let key = NSString(string: videoPath)
        
        // Check memory cache first
        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }
        
        // Check disk cache
        let thumbnailURL = thumbnailFileURL(for: videoPath)
        if fileManager.fileExists(atPath: thumbnailURL.path),
           let diskCachedImage = UIImage(contentsOfFile: thumbnailURL.path) {
            // Load to memory cache
            cache.setObject(diskCachedImage, forKey: key)
            return diskCachedImage
        }
        
        return nil
    }
    
    func cacheThumbnail(_ thumbnail: UIImage, for videoPath: String) {
        let key = NSString(string: videoPath)
        
        // Save to memory cache
        cache.setObject(thumbnail, forKey: key)
        
        // Save to disk cache
        let thumbnailURL = thumbnailFileURL(for: videoPath)
        if let data = thumbnail.jpegData(compressionQuality: 0.8) {
            do {
                try data.write(to: thumbnailURL)
            } catch {
                logger.error("Failed to write thumbnail to disk: \(error.localizedDescription)")
            }
        }
    }
    
    func clearCache() {
        // Clear memory cache
        cache.removeAllObjects()
        
        // Clear disk cache
        do {
            try fileManager.removeItem(at: cacheDirectory)
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to clear thumbnail cache: \(error.localizedDescription)")
        }
    }
    
    private func thumbnailFileURL(for videoPath: String) -> URL {
        // Use a deterministic hash so disk cache filenames are stable across launches.
        // (Swift's String.hashValue is randomly seeded per process and is unsuitable here.)
        let pathHash = VideoThumbnailCache.stableHash(videoPath)
        return cacheDirectory.appendingPathComponent("\(pathHash).jpg")
    }
    
    /// Deterministic FNV-1a 64-bit hash of a string, rendered as hex.
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(hash, radix: 16, uppercase: false)
    }
    
    func getThumbnailAsync(for videoPath: String, targetSize: CGSize) async -> UIImage? {
        // Check cache first
        if let cached = getThumbnail(for: videoPath) {
            return cached
        }
        
        // Generate thumbnail asynchronously using the modern async image generator API
        let url = URL(fileURLWithPath: videoPath)
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = targetSize
        imageGenerator.requestedTimeToleranceBefore = .positiveInfinity
        imageGenerator.requestedTimeToleranceAfter = .positiveInfinity
        
        // Try multiple time points for best thumbnail
        let timePoints: [CMTime] = [
            CMTime(seconds: 2.0, preferredTimescale: 600),
            CMTime(seconds: 5.0, preferredTimescale: 600),
            CMTime(seconds: 0.5, preferredTimescale: 600),
            CMTime.zero
        ]
        
        var bestThumbnail: UIImage?
        
        for timePoint in timePoints {
            do {
                let (cgImage, _) = try await imageGenerator.image(at: timePoint)
                bestThumbnail = UIImage(cgImage: cgImage)
                break // Use first successful thumbnail
            } catch {
                continue // Try next time point
            }
        }
        
        // Cache the result
        if let thumbnail = bestThumbnail {
            cacheThumbnail(thumbnail, for: videoPath)
        }
        
        return bestThumbnail
    }
}
