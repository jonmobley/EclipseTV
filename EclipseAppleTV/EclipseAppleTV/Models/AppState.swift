import Foundation
import Combine

/// Centralized app state management
@MainActor
class AppState: ObservableObject {
    // MARK: - Published Properties
    @Published var mediaLibrary: [MediaItem] = []
    @Published var currentMediaIndex: Int = 0
    @Published var isInGridMode: Bool = true
    @Published var isMoveModeActive: Bool = false
    @Published var selectedMediaPath: String?
    
    // MARK: - Settings
    @Published var autoPlayVideos: Bool {
        didSet { saveSettings() }
    }
    @Published var defaultVideoVolume: Float {
        didSet { saveSettings() }
    }
    @Published var loopVideosByDefault: Bool {
        didSet { saveSettings() }
    }
    @Published var muteVideosByDefault: Bool {
        didSet { saveSettings() }
    }
    @Published var gridAnimationDuration: Double {
        didSet { saveSettings() }
    }
    
    // MARK: - Video Settings Per File
    private var videoSettings: [String: VideoSettings] = [:]
    
    struct VideoSettings: Codable {
        var isLooping: Bool = false
        var isMuted: Bool = false
        var volume: Float = 1.0
        var playbackRate: Float = 1.0
        var lastPosition: TimeInterval = 0
    }
    
    // MARK: - Constants
    private let maxLibrarySize = 50
    private let settingsKey = "EclipseTV.AppSettings"
    private let videoSettingsKey = "EclipseTV.VideoSettings"
    private let mediaLibraryKey = "EclipseTV.MediaLibrary"
    
    // MARK: - Initialization
    init() {
        // Load settings with defaults
        let defaults = UserDefaults.standard
        autoPlayVideos = defaults.object(forKey: "autoPlayVideos") as? Bool ?? true
        defaultVideoVolume = defaults.object(forKey: "defaultVideoVolume") as? Float ?? 0.8
        loopVideosByDefault = defaults.object(forKey: "loopVideosByDefault") as? Bool ?? false
        muteVideosByDefault = defaults.object(forKey: "muteVideosByDefault") as? Bool ?? false
        gridAnimationDuration = defaults.object(forKey: "gridAnimationDuration") as? Double ?? 0.3
        
        loadVideoSettings()
        loadMediaLibrary()
    }
    
    // MARK: - Media Library Management
    func addMediaItem(_ item: MediaItem) {
        // Check if already exists
        if let existingIndex = mediaLibrary.firstIndex(where: { $0.path == item.path }) {
            // Update existing item
            mediaLibrary[existingIndex] = item
        } else {
            // Add new item
            mediaLibrary.append(item)
        }
        
        // Keep library size manageable
        if mediaLibrary.count > maxLibrarySize {
            mediaLibrary = Array(mediaLibrary.suffix(maxLibrarySize))
        }
        
        saveMediaLibrary()
    }
    
    func removeMediaItem(at index: Int) {
        guard mediaLibrary.indices.contains(index) else { return }
        
        let item = mediaLibrary[index]
        mediaLibrary.remove(at: index)
        
        // Remove video settings for this item
        videoSettings.removeValue(forKey: item.path)
        
        // Adjust current index if necessary
        if currentMediaIndex >= mediaLibrary.count && !mediaLibrary.isEmpty {
            currentMediaIndex = mediaLibrary.count - 1
        } else if mediaLibrary.isEmpty {
            currentMediaIndex = 0
        }
        
        saveMediaLibrary()
        saveVideoSettings()
    }
    
    func moveMediaItem(from sourceIndex: Int, to destinationIndex: Int) {
        guard mediaLibrary.indices.contains(sourceIndex),
              mediaLibrary.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else { return }
        
        let item = mediaLibrary[sourceIndex]
        mediaLibrary.remove(at: sourceIndex)
        mediaLibrary.insert(item, at: destinationIndex)
        
        // Update current index if it was the moved item
        if currentMediaIndex == sourceIndex {
            currentMediaIndex = destinationIndex
        }
        
        saveMediaLibrary()
    }
    
    func clearLibrary() {
        mediaLibrary.removeAll()
        videoSettings.removeAll()
        currentMediaIndex = 0
        saveMediaLibrary()
        saveVideoSettings()
    }
    
    // MARK: - Current Media Management
    var currentMediaItem: MediaItem? {
        guard mediaLibrary.indices.contains(currentMediaIndex) else { return nil }
        return mediaLibrary[currentMediaIndex]
    }
    
    func selectMedia(at index: Int) {
        guard mediaLibrary.indices.contains(index) else { return }
        currentMediaIndex = index
        selectedMediaPath = mediaLibrary[index].path
    }
    
    func selectNextMedia() -> Bool {
        guard currentMediaIndex < mediaLibrary.count - 1 else { return false }
        currentMediaIndex += 1
        selectedMediaPath = mediaLibrary[currentMediaIndex].path
        return true
    }
    
    func selectPreviousMedia() -> Bool {
        guard currentMediaIndex > 0 else { return false }
        currentMediaIndex -= 1
        selectedMediaPath = mediaLibrary[currentMediaIndex].path
        return true
    }
    
    // MARK: - Video Settings Management
    func getVideoSettings(for path: String) -> VideoSettings {
        return videoSettings[path] ?? VideoSettings()
    }
    
    func setVideoSettings(_ settings: VideoSettings, for path: String) {
        videoSettings[path] = settings
        saveVideoSettings()
    }
    
    func updateVideoSetting<T>(for path: String, keyPath: WritableKeyPath<VideoSettings, T>, value: T) {
        var settings = getVideoSettings(for: path)
        settings[keyPath: keyPath] = value
        setVideoSettings(settings, for: path)
    }
    
    // MARK: - Persistence
    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(autoPlayVideos, forKey: "autoPlayVideos")
        defaults.set(defaultVideoVolume, forKey: "defaultVideoVolume")
        defaults.set(loopVideosByDefault, forKey: "loopVideosByDefault")
        defaults.set(muteVideosByDefault, forKey: "muteVideosByDefault")
        defaults.set(gridAnimationDuration, forKey: "gridAnimationDuration")
    }
    
    private func saveVideoSettings() {
        if let data = try? JSONEncoder().encode(videoSettings) {
            UserDefaults.standard.set(data, forKey: videoSettingsKey)
        }
    }
    
    private func loadVideoSettings() {
        guard let data = UserDefaults.standard.data(forKey: videoSettingsKey),
              let settings = try? JSONDecoder().decode([String: VideoSettings].self, from: data) else {
            return
        }
        videoSettings = settings
    }
    
    private func saveMediaLibrary() {
        if let data = try? JSONEncoder().encode(mediaLibrary) {
            UserDefaults.standard.set(data, forKey: mediaLibraryKey)
        }
    }
    
    private func loadMediaLibrary() {
        guard let data = UserDefaults.standard.data(forKey: mediaLibraryKey),
              let library = try? JSONDecoder().decode([MediaItem].self, from: data) else {
            return
        }
        
        // Filter out items where files no longer exist
        mediaLibrary = library.filter { $0.fileExists }
        
        // Save filtered library if any items were removed
        if mediaLibrary.count != library.count {
            saveMediaLibrary()
        }
    }
}

// MARK: - Computed Properties
extension AppState {
    var hasMedia: Bool {
        !mediaLibrary.isEmpty
    }
    
    var mediaCount: Int {
        mediaLibrary.count
    }
    
    var videoCount: Int {
        mediaLibrary.filter { $0.isVideo }.count
    }
    
    var imageCount: Int {
        mediaLibrary.filter { !$0.isVideo }.count
    }
    
    var librarySize: String {
        let totalSize = mediaLibrary.reduce(0) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
} 