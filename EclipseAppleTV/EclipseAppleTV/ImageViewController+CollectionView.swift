// ImageViewController+CollectionView.swift
import UIKit
import AVFoundation
import os.log

// MARK: - UICollectionViewDataSource & UICollectionViewDelegate
extension ImageViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let count = dataSource.count
        logger.info("📊 [COLLECTION] numberOfItems=\(count)")
        return count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        return PerformanceMonitor.shared.measureUIOperation("cellForItemAt") {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ThumbnailCell", for: indexPath) as! ImageThumbnailCell
            
            guard let path = dataSource.getPath(at: indexPath.item) else {
                logger.warning("Invalid index: \(indexPath.item), max: \(self.dataSource.count - 1)")
                return cell
            }
            
            let mediaItem = MediaItem(path: path)
            logger.debug("🧩 [CELL] Configuring index=\(indexPath.item) file=\(mediaItem.fileName) isVideo=\(mediaItem.isVideo)")
            
            // Configure cell with media item
            configureThumbnailCell(cell, with: mediaItem, at: indexPath)
            
            // CRITICAL FIX: Set the selected state based on move mode
            if isMoveMode && indexPath == movingItemIndexPath {
                // This is the item being moved - keep it selected
                cell.isSelected = true
            } else {
                // All other cells should not be selected
                cell.isSelected = false
            }
            
            return cell
        }
    }
    
    private func configureThumbnailCell(_ cell: ImageThumbnailCell, with mediaItem: MediaItem, at indexPath: IndexPath) {
        // Remove any existing long press gestures from previous cell reuse
        cell.gestureRecognizers?.forEach { gesture in
            if gesture is UILongPressGestureRecognizer {
                cell.removeGestureRecognizer(gesture)
            }
        }
        
        // Set cell tag for identification
        cell.tag = indexPath.item
        
        // Configure basic cell state immediately
        if mediaItem.isVideo {
            cell.configure(with: nil, isVideo: true)
        } else {
            cell.configure(with: nil, isVideo: false)
        }
        
        // Add long press gesture recognizer for options menu
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        cell.addGestureRecognizer(longPressGesture)
        
        // Load thumbnail asynchronously using the improved configureAsync method
        let cellSize = (gridView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize ?? CGSize(width: 300, height: 169)
        let storedPosition = imagePositions[mediaItem.path]
        cell.configureAsync(imagePath: mediaItem.path, isVideo: mediaItem.isVideo, cellSize: cellSize, userPosition: storedPosition)
        
        // Handle video metadata separately if needed
        if mediaItem.isVideo {
            Task {
                // Extract actual video duration asynchronously
                let url = URL(fileURLWithPath: mediaItem.path)
                let duration = await getVideoDuration(for: url)
                let settings = viewModel.getVideoSettings(for: mediaItem)
                
                await MainActor.run {
                    logger.debug("🎛️ [CELL] Updating video meta index=\(indexPath.item) duration=\(duration) loop=\(settings.isLooping) mute=\(settings.isMuted)")
                    // Verify cell is still for the same item before updating
                    if let visibleCell = gridView.cellForItem(at: indexPath) as? ImageThumbnailCell,
                       visibleCell.tag == indexPath.item {
                        // Update video metadata with actual duration - don't wait for thumbnail
                        // Use current image if available, or nil if still loading
                        visibleCell.configure(with: visibleCell.currentImage, isVideo: true, duration: duration, 
                                            isLooping: settings.isLooping, isMuted: settings.isMuted)
                    }
                }
            }
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        dataSource.debugPrint() // TEMPORARY: Remove after testing
        
        // In move mode, finish the move when selecting an item
        if isMoveMode {
            // If we select the same item we're moving, end move mode
            if indexPath == movingItemIndexPath {
                endMoveMode()
            } else {
                // Otherwise, move the item to the new position
                if let sourceIndex = movingItemIndex {
                    moveItemToPosition(from: sourceIndex, to: indexPath.item)
                    endMoveMode()
                }
            }
            return
        }
        
        // Ignore selection events when ignoring
        if isIgnoringSelectionEvents {
            return
        }
        
        // Go to fullscreen
        if indexPath.item < dataSource.count {
            dataSource.setCurrentIndex(indexPath.item)
            hideGridView() // Use the smooth transition method we just created
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // CRITICAL FIX: Ensure proper selection state when cells become visible
        if let thumbnailCell = cell as? ImageThumbnailCell {
            if isMoveMode && indexPath == movingItemIndexPath {
                // This is the item being moved - ensure it stays selected
                thumbnailCell.isSelected = true
                thumbnailCell.updateVisualEffects()
            } else {
                // All other cells should not be selected
                thumbnailCell.isSelected = false
                thumbnailCell.updateVisualEffects()
            }
        }
        
        // Preload images and videos for visible cells and their neighbors
        let preloadRange = 2 // Number of cells to preload on each side
        
        // Get the range of indices to preload
        let startIndex = max(0, indexPath.item - preloadRange)
        let endIndex = min(dataSource.count - 1, indexPath.item + preloadRange)
        
        // Preload video assets around the current index for smooth transitions
        VideoCacheManager.shared.preloadVideosAroundIndex(indexPath.item, in: dataSource)
        
        // Preload thumbnails for the range
        Task {
            for index in startIndex...endIndex {
                guard let path = dataSource.getPath(at: index) else { continue }
                let isVideo = path.lowercased().hasSuffix(".mp4") || path.lowercased().hasSuffix(".mov")
                let cellSize = (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize ?? CGSize(width: 400, height: 225)
                
                if isVideo {
                    _ = await VideoThumbnailCache.shared.getThumbnailAsync(for: path, targetSize: cellSize)
                } else {
                    _ = await AsyncImageLoader.shared.loadImage(from: path, targetSize: cellSize)
                }
            }
        }
    }
    
    // Helper to evaluate thumbnail quality
    private func calculateImageQualityScore(_ image: UIImage?) -> Double? {
        guard let image = image, let cgImage = image.cgImage else { return nil }
        
        // Get image dimensions
        let width = cgImage.width
        let height = cgImage.height
        
        // Simple image variance calculation as quality metric
        // Higher variance typically means more detail/information
        if width < 10 || height < 10 {
            return 0.0  // Too small to be useful
        }
        
        // For performance, we'll sample the image instead of analyzing every pixel
        let context = CIContext()
        let ciImage = CIImage(cgImage: cgImage)
        
        // Calculate brightness variance
        if let extent = ciImage.extent.standardized as CGRect? {
            if extent.width > 1 && extent.height > 1 {
                // Very simple entropy-based measure that works well enough for thumbnails
                let averageBrightness = ciImage.averageBrightness(in: context)
                
                // Penalize extremely dark images that are likely black frames
                if averageBrightness < 0.1 {
                    return 0.1
                }
                
                // Penalize extremely bright images that are likely flash frames
                if averageBrightness > 0.9 {
                    return 0.2
                }
                
                // Calculate a rough metric for detail (could be made more sophisticated)
                let detailScore = ciImage.calculateDetailScore(in: context)
                
                return 0.3 + (detailScore * 0.7) // Weight detail more heavily
            }
        }
        
        return 0.5 // Default middle score
    }
}



// MARK: - CIImage Extension for Image Analysis
extension CIImage {
    func averageBrightness(in context: CIContext) -> Double {
        let extentVector = CIVector(x: self.extent.origin.x, y: self.extent.origin.y, 
                                  z: self.extent.size.width, w: self.extent.size.height)
        
        guard let avgFilter = CIFilter(name: "CIAreaAverage", 
                                    parameters: [kCIInputImageKey: self, kCIInputExtentKey: extentVector]) else {
            return 0.5
        }
        
        guard let outputImage = avgFilter.outputImage else {
            return 0.5
        }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage, 
                     toBitmap: &bitmap, 
                     rowBytes: 4, 
                     bounds: CGRect(x: 0, y: 0, width: 1, height: 1), 
                     format: .RGBA8, 
                     colorSpace: CGColorSpaceCreateDeviceRGB())
        
        // Calculate luminance from RGB
        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        
        // Weighted luminance formula
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    
    func calculateDetailScore(in context: CIContext) -> Double {
        // Use edge detection to identify frame detail
        guard let edgeFilter = CIFilter(name: "CIEdges", 
                                     parameters: [kCIInputImageKey: self, kCIInputIntensityKey: 5.0]) else {
            return 0.5
        }
        
        guard let edgeImage = edgeFilter.outputImage else {
            return 0.5
        }
        
        // Calculate the average intensity of the edges
        let extentVector = CIVector(x: edgeImage.extent.origin.x, y: edgeImage.extent.origin.y, 
                                  z: edgeImage.extent.size.width, w: edgeImage.extent.size.height)
        
        guard let avgFilter = CIFilter(name: "CIAreaAverage", 
                                    parameters: [kCIInputImageKey: edgeImage, kCIInputExtentKey: extentVector]) else {
            return 0.5
        }
        
        guard let outputImage = avgFilter.outputImage else {
            return 0.5
        }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage, 
                     toBitmap: &bitmap, 
                     rowBytes: 4, 
                     bounds: CGRect(x: 0, y: 0, width: 1, height: 1), 
                     format: .RGBA8, 
                     colorSpace: CGColorSpaceCreateDeviceRGB())
        
        // Average intensity across color channels
        let avg = (Double(bitmap[0]) + Double(bitmap[1]) + Double(bitmap[2])) / (3.0 * 255.0)
        return avg
    }
}

// MARK: - Thumbnail Cache
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
        // Create a filename based on the hash of the video path
        let pathHash = String(videoPath.hash, radix: 16, uppercase: false)
        return cacheDirectory.appendingPathComponent("\(pathHash).jpg")
    }
    
    // Add this async extension method to VideoThumbnailCache class:
    func getThumbnailAsync(for videoPath: String, targetSize: CGSize) async -> UIImage? {
        // Check cache first
        if let cached = getThumbnail(for: videoPath) {
            return cached
        }
        
        // Generate thumbnail asynchronously
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
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
                        let cgImage = try imageGenerator.copyCGImage(at: timePoint, actualTime: nil)
                        bestThumbnail = UIImage(cgImage: cgImage)
                        break // Use first successful thumbnail
                    } catch {
                        continue // Try next time point
                    }
                }
                
                // Cache the result
                if let thumbnail = bestThumbnail {
                    self.cacheThumbnail(thumbnail, for: videoPath)
                }
                
                continuation.resume(returning: bestThumbnail)
            }
        }
    }
}

// Helper method to get video duration - non-duplicate helper
private extension ImageViewController {
    func getVideoDuration(for url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return duration.seconds.isFinite ? duration.seconds : 0
        } catch {
            logger.error("Failed to get video duration: \(error)")
            return 0
        }
    }
}
