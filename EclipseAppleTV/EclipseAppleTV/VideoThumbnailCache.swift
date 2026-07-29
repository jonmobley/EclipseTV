//
//  VideoThumbnailCache.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation
import os.log

/// Memory + disk cache for video thumbnails.
class VideoThumbnailCache {
    static let shared = VideoThumbnailCache()
    
    /// Decoded-thumbnail memory budget. A count limit alone says nothing about bytes: 100
    /// grid-sized thumbnails can be hundreds of megabytes on a 4K TV layout.
    private static let memoryCostLimit = 40 * 1024 * 1024
    /// Disk budget for the thumbnail directory, which otherwise grew without bound.
    private static let diskByteLimit = 60 * 1024 * 1024

    private var cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let logger = Logger(subsystem: "com.eclipseapp.appletv", category: "ThumbnailCache")
    
    private init() {
        // Set up in-memory cache
        cache.countLimit = 100
        cache.totalCostLimit = Self.memoryCostLimit
        
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

        let directory = cacheDirectory
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.pruneDiskCache(at: directory)
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
            cache.setObject(diskCachedImage, forKey: key, cost: Self.cost(of: diskCachedImage))
            return diskCachedImage
        }
        
        return nil
    }
    
    func cacheThumbnail(_ thumbnail: UIImage, for videoPath: String) {
        let key = NSString(string: videoPath)
        
        // Save to memory cache
        cache.setObject(thumbnail, forKey: key, cost: Self.cost(of: thumbnail))
        
        // Save to disk cache
        let thumbnailURL = thumbnailFileURL(for: videoPath)
        if let data = thumbnail.jpegData(compressionQuality: 0.8) {
            do {
                try data.write(to: thumbnailURL, options: .atomic)
            } catch {
                logger.error("Failed to write thumbnail to disk: \(error.localizedDescription)")
            }
        }
    }

    /// Approximate decoded byte size, used as the `NSCache` cost.
    private static func cost(of image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        return Int(pixels * 4)
    }

    /// Trims the disk cache to `diskByteLimit`, dropping the oldest files first.
    private func pruneDiskCache(at directory: URL) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return }

        var files: [(url: URL, size: Int, modified: Date)] = []
        var totalBytes = 0
        for url in entries {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize else { continue }
            files.append((url, size, values.contentModificationDate ?? .distantPast))
            totalBytes += size
        }

        guard totalBytes > Self.diskByteLimit else { return }
        logger.info("Pruning thumbnail cache from \(totalBytes) bytes")

        for file in files.sorted(by: { $0.modified < $1.modified }) {
            guard totalBytes > Self.diskByteLimit else { break }
            do {
                try fileManager.removeItem(at: file.url)
                totalBytes -= file.size
            } catch {
                logger.error("Prune failed for \(file.url.lastPathComponent, privacy: .public)")
            }
        }
    }
    
    /// Removes the cached thumbnail (memory and disk) for a single video, e.g. when the
    /// video is deleted from the library. Without this, disk entries live until the next
    /// full `clearCache()`.
    func removeThumbnail(for videoPath: String) {
        cache.removeObject(forKey: NSString(string: videoPath))
        let thumbnailURL = thumbnailFileURL(for: videoPath)
        if fileManager.fileExists(atPath: thumbnailURL.path) {
            do {
                try fileManager.removeItem(at: thumbnailURL)
            } catch {
                logger.error("Failed to remove thumbnail from disk: \(error.localizedDescription)")
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
