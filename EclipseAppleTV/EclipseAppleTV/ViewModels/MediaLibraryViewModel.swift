import Foundation
import Combine
import UIKit

/// View model for the media library interface
@MainActor
class MediaLibraryViewModel: ObservableObject {
    // Remove the old mediaLibrary array - now we delegate to MediaDataSource
    private let dataSource = MediaDataSource.shared
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isLoading = false
    @Published var isShowingEmptyState = false
    
    // COMPUTED PROPERTIES - Always in sync with data source
    var mediaLibrary: [MediaItem] {
        return dataSource.mediaPaths.map { MediaItem(path: $0) }
    }
    
    var currentMediaIndex: Int {
        get { dataSource.currentIndex }
        set { dataSource.setCurrentIndex(newValue) }
    }
    
    var hasMedia: Bool {
        return !dataSource.isEmpty
    }
    
    var currentMediaItem: MediaItem? {
        guard let path = dataSource.getCurrentPath() else { return nil }
        return MediaItem(path: path)
    }
    
    init() {
        // Listen to data source changes
        dataSource.$mediaPaths
            .map { $0.isEmpty }
            .assign(to: \.isShowingEmptyState, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods (Delegate to data source)
    
    func loadMedia() {
        // Data source handles loading from storage automatically
        // Just trigger UI update
        objectWillChange.send()
    }
    
    func addMedia(at path: String) {
        dataSource.addMedia(at: path)
    }
    
    func addMediaBatch(paths: [String]) {
        dataSource.addMediaBatch(paths: paths)
    }
    
    func removeMedia(at index: Int) {
        dataSource.removeMedia(at: index)
    }
    
    func moveMedia(from sourceIndex: Int, to targetIndex: Int) {
        dataSource.moveMedia(from: sourceIndex, to: targetIndex)
    }
    
    func selectMedia(at index: Int) {
        dataSource.setCurrentIndex(index)
    }
    
    func nextMedia() -> Bool {
        let success = dataSource.nextIndex()
        if success { objectWillChange.send() }
        return success
    }
    
    func previousMedia() -> Bool {
        let success = dataSource.previousIndex()
        if success { objectWillChange.send() }
        return success
    }
    
    // MARK: - Sample Media Loading
    
    func loadSampleMedia() async {
        print("🎯 [VIEWMODEL] Starting loadSampleMedia")
        isLoading = true
        
        do {
            // Try to load from MediaService first
            let mediaService = MediaService.shared
            let sampleItems = try await mediaService.loadSampleMedia()
            
            print("🎯 [VIEWMODEL] MediaService returned \(sampleItems.count) sample items")
            
            if !sampleItems.isEmpty {
                // Use batch loading to avoid collection view update conflicts
                let paths = sampleItems.map { $0.path }
                print("🎯 [VIEWMODEL] Extracted paths: \(paths)")
                dataSource.addMediaBatch(paths: paths)
            } else {
                print("🎯 [VIEWMODEL] MediaService returned 0 items, falling back to bundle images")
                // Fallback to bundle images if MediaService returns no items
                await loadFallbackSampleImages()
            }
            
        } catch {
            print("🎯 [VIEWMODEL] MediaService failed: \(error), falling back to bundle images")
            // Fallback to bundle images if MediaService fails
            await loadFallbackSampleImages()
        }
        
        print("🎯 [VIEWMODEL] loadSampleMedia completed")
        isLoading = false
        objectWillChange.send()
    }
    
    private func loadFallbackSampleImages() async {
        print("🎯 [VIEWMODEL] Starting fallback sample images loading")
        
        // Fallback: try to load from bundle using sample image names
        let sampleImageNames = ["sample1", "sample2", "sample3"]
        let imageStorage = ImageStorage.shared
        
        var fallbackPaths: [String] = []
        
        for imageName in sampleImageNames {
            print("🎯 [VIEWMODEL] Trying to load sample image: \(imageName)")
            
            if let image = UIImage(named: imageName) {
                print("🎯 [VIEWMODEL] Successfully loaded UIImage for: \(imageName)")
                
                if let imageData = image.jpegData(compressionQuality: 1.0) {
                    print("🎯 [VIEWMODEL] Converted to JPEG data for: \(imageName)")
                    
                    if let fileURL = imageStorage.saveSampleImage(imageData, name: imageName) {
                        print("🎯 [VIEWMODEL] Saved sample image to: \(fileURL.path)")
                        fallbackPaths.append(fileURL.path)
                    } else {
                        print("🎯 [VIEWMODEL] Failed to save sample image: \(imageName)")
                    }
                } else {
                    print("🎯 [VIEWMODEL] Failed to convert to JPEG data: \(imageName)")
                }
            } else {
                print("🎯 [VIEWMODEL] Failed to load UIImage for: \(imageName)")
            }
        }
        
        print("🎯 [VIEWMODEL] Fallback loaded \(fallbackPaths.count) sample images")
        
        // Use batch loading for fallback images too
        if !fallbackPaths.isEmpty {
            dataSource.addMediaBatch(paths: fallbackPaths)
        } else {
            print("🎯 [VIEWMODEL] No fallback images available - will show empty state")
        }
    }
    
    // MARK: - Thumbnail Management (Keep existing functionality)
    private let thumbnailService: ThumbnailService = .shared
    
    func getThumbnail(for item: MediaItem, size: CGSize) async -> UIImage? {
        return await thumbnailService.getThumbnail(for: item, size: size)
    }
    
    func preloadThumbnails(size: CGSize) {
        Task {
            await thumbnailService.preloadThumbnails(for: mediaLibrary, size: size)
        }
    }
    
    // MARK: - Video Settings (Maintain existing functionality)
    private let appState: AppState = AppState()
    
    func getVideoSettings(for item: MediaItem) -> AppState.VideoSettings {
        return appState.getVideoSettings(for: item.path)
    }
    
    func updateVideoSetting<T>(for item: MediaItem, keyPath: WritableKeyPath<AppState.VideoSettings, T>, value: T) {
        appState.updateVideoSetting(for: item.path, keyPath: keyPath, value: value)
    }
    
    // MARK: - Move Mode Support
    func startMoveMode() {
        appState.isMoveModeActive = true
    }
    
    func endMoveMode() {
        appState.isMoveModeActive = false
    }
    
    var isMoveModeActive: Bool {
        appState.isMoveModeActive
    }
} 