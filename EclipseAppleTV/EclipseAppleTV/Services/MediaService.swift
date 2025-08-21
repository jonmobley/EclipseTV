import Foundation
import UIKit
import AVFoundation

/// Service for media file operations
class MediaService {
    static let shared = MediaService()
    
    private let storage = ImageStorage.shared
    private let performanceMonitor = PerformanceMonitor.shared
    
    private init() {}
    
    // MARK: - Media Loading
    func loadExistingMedia() async throws -> [MediaItem] {
        return try await performanceMonitor.measureAsync("MediaService.loadExistingMedia") {
            let paths = try await storage.loadRecentImagePaths()
            return await loadMediaItems(from: paths)
        }
    }
    
    func addMediaFromPath(_ path: String) async throws -> MediaItem {
        return try await performanceMonitor.measureAsync("MediaService.addMediaFromPath") {
            return try await MediaItem.from(path: path)
        }
    }
    
    func loadSampleMedia() async throws -> [MediaItem] {
        return try await performanceMonitor.measureAsync("MediaService.loadSampleMedia") {
            print("🎯 [MEDIASERVICE] Starting loadSampleMedia")
            var sampleItems: [MediaItem] = []

            // Load sample images from Assets.xcassets first
            let sampleImageNames = ["sample1", "sample2", "sample3"]
            print("🎯 [MEDIASERVICE] Loading sample images from Assets.xcassets")
            
            for imageName in sampleImageNames {
                if let image = UIImage(named: imageName) {
                    print("🎯 [MEDIASERVICE] Found asset image: \(imageName)")
                    
                    if let imageData = image.jpegData(compressionQuality: 1.0) {
                        if let fileURL = storage.saveSampleImage(imageData, name: imageName) {
                            print("🎯 [MEDIASERVICE]   • image: \(imageName).jpg @ \(fileURL.path)")
                            let item = try await MediaItem.from(path: fileURL.path)
                            sampleItems.append(item)
                        } else {
                            print("🎯 [MEDIASERVICE] Failed to save sample image: \(imageName)")
                        }
                    } else {
                        print("🎯 [MEDIASERVICE] Failed to convert to JPEG data: \(imageName)")
                    }
                } else {
                    print("🎯 [MEDIASERVICE] Asset image not found: \(imageName)")
                }
            }

            // Find bundled videos anywhere in the app bundle
            let videoExtensions = ["mp4", "mov"]
            for ext in videoExtensions {
                if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                    print("🎯 [MEDIASERVICE] Discovered \(urls.count) .'\(ext)' files in bundle")
                    for url in urls {
                        print("🎯 [MEDIASERVICE]   • video: \(url.lastPathComponent) @ \(url.path)")
                        let item = try await MediaItem.from(path: url.path)
                        sampleItems.append(item)
                    }
                } else {
                    print("🎯 [MEDIASERVICE] No .'\(ext)' files found in bundle")
                }
            }

            // Optionally find loose images in bundle (assets won't appear here)
            let imageExtensions = ["jpg", "jpeg", "png", "heic"]
            for ext in imageExtensions {
                if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                    print("🎯 [MEDIASERVICE] Discovered \(urls.count) .'\(ext)' files in bundle")
                    for url in urls {
                        print("🎯 [MEDIASERVICE]   • image: \(url.lastPathComponent) @ \(url.path)")
                        let item = try await MediaItem.from(path: url.path)
                        sampleItems.append(item)
                    }
                } else {
                    print("🎯 [MEDIASERVICE] No .'\(ext)' files found in bundle")
                }
            }

            print("🎯 [MEDIASERVICE] Total sample items loaded: \(sampleItems.count)")
            return sampleItems
        }
    }
    
    private func loadMediaItems(from paths: [String]) async -> [MediaItem] {
        return await withTaskGroup(of: MediaItem?.self) { group in
            for path in paths {
                group.addTask {
                    do {
                        return try await MediaItem.from(path: path)
                    } catch {
                        // Log error but don't fail entire operation
                        Task { @MainActor in
                            ErrorHandler.shared.handle(.fileNotFound(path: path), context: "loadMediaItems")
                        }
                        return nil
                    }
                }
            }
            
            var items: [MediaItem] = []
            for await item in group {
                if let item = item {
                    items.append(item)
                }
            }
            return items
        }
    }
    
    // MARK: - Media Operations
    func deleteMediaFile(_ item: MediaItem) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: item.path) else {
            throw MediaError.fileNotFound(path: item.path)
        }
        
        try fileManager.removeItem(atPath: item.path)
    }
    
    func getMediaInfo(_ item: MediaItem) -> String {
        return """
        Name: \(item.fileName)
        Type: \(item.type.displayName)
        Size: \(item.fileSizeFormatted)
        Added: \(item.dateAddedFormatted)
        Path: \(item.path)
        """
    }
    
    func validateMediaLibrary(_ items: [MediaItem]) -> [MediaItem] {
        return items.filter { item in
            let exists = item.fileExists
            if !exists {
                Task { @MainActor in
                    ErrorHandler.shared.handle(.fileNotFound(path: item.path), context: "validateMediaLibrary")
                }
            }
            return exists
        }
    }
}

// MARK: - Extensions
extension ImageStorage {
    func loadRecentImagePaths() async throws -> [String] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                if let savedImages = UserDefaults.standard.stringArray(forKey: "EclipseTV.recentImagesKey") {
                    continuation.resume(returning: savedImages)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
} 