//
//  MediaLibraryViewModel.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Combine
import UIKit

/// View model that owns sample-media loading and per-file video settings.
/// All media list state lives in `MediaDataSource`; this type only exposes the
/// narrow surface the UI actually consumes.
@MainActor
class MediaLibraryViewModel: ObservableObject {
    private let dataSource = MediaDataSource.shared
    private let appState = AppState()
    
    @Published var isLoading = false
    
    // MARK: - Sample Media Loading
    
    func loadSampleMedia() async {
        isLoading = true
        
        do {
            let sampleItems = try await MediaService.shared.loadSampleMedia()
            if !sampleItems.isEmpty {
                dataSource.addMediaBatch(paths: sampleItems.map { $0.path })
            } else {
                await loadFallbackSampleImages()
            }
        } catch {
            await loadFallbackSampleImages()
        }
        
        isLoading = false
        objectWillChange.send()
    }
    
    private func loadFallbackSampleImages() async {
        let sampleImageNames = ["sample1", "sample2", "sample3"]
        let imageStorage = ImageStorage.shared
        var fallbackPaths: [String] = []
        
        for imageName in sampleImageNames {
            guard let image = UIImage(named: imageName),
                  let imageData = image.jpegData(compressionQuality: 1.0),
                  let fileURL = imageStorage.saveSampleImage(imageData, name: imageName) else {
                continue
            }
            fallbackPaths.append(fileURL.path)
        }
        
        if !fallbackPaths.isEmpty {
            dataSource.addMediaBatch(paths: fallbackPaths)
        }
    }
    
    // MARK: - Video Settings
    
    func getVideoSettings(for item: MediaItem) -> AppState.VideoSettings {
        return appState.getVideoSettings(for: item.path)
    }
    
    func updateVideoSetting<T>(for item: MediaItem, keyPath: WritableKeyPath<AppState.VideoSettings, T>, value: T) {
        appState.updateVideoSetting(for: item.path, keyPath: keyPath, value: value)
    }
}
