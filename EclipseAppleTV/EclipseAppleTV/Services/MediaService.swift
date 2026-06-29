//
//  MediaService.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

/// Service for loading bundled sample media.
class MediaService {
    static let shared = MediaService()
    
    private let storage = ImageStorage.shared
    private let performanceMonitor = PerformanceMonitor.shared
    
    private init() {}
    
    // MARK: - Sample Media Loading
    func loadSampleMedia() async throws -> [MediaItem] {
        return try await performanceMonitor.measureAsync("MediaService.loadSampleMedia") {
            var sampleItems: [MediaItem] = []

            // Load sample images from Assets.xcassets first
            let sampleImageNames = ["sample1", "sample2", "sample3"]
            for imageName in sampleImageNames {
                guard let image = UIImage(named: imageName),
                      let imageData = image.jpegData(compressionQuality: 1.0),
                      let fileURL = storage.saveSampleImage(imageData, name: imageName) else {
                    continue
                }
                let item = try await MediaItem.from(path: fileURL.path)
                sampleItems.append(item)
            }

            // Find bundled videos anywhere in the app bundle
            let videoExtensions = ["mp4", "mov", "m4v"]
            for ext in videoExtensions {
                if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                    for url in urls {
                        let item = try await MediaItem.from(path: url.path)
                        sampleItems.append(item)
                    }
                }
            }

            // Optionally find loose images in bundle (assets won't appear here)
            let imageExtensions = ["jpg", "jpeg", "png", "heic"]
            for ext in imageExtensions {
                if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                    for url in urls {
                        let item = try await MediaItem.from(path: url.path)
                        sampleItems.append(item)
                    }
                }
            }

            return sampleItems
        }
    }
}
