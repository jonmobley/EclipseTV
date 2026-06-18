import Foundation
import Combine

/// Stores per-file video playback settings (mute, loop, etc.) with persistence.
/// Media list state lives in `MediaDataSource`; this type is intentionally narrow.
@MainActor
class AppState: ObservableObject {
    // MARK: - Video Settings Per File
    private var videoSettings: [String: VideoSettings] = [:]
    
    struct VideoSettings: Codable {
        var isLooping: Bool = false
        var isMuted: Bool = false
        var volume: Float = 1.0
        var playbackRate: Float = 1.0
        var lastPosition: TimeInterval = 0
    }
    
    private let videoSettingsKey = "EclipseTV.VideoSettings"
    
    // MARK: - Initialization
    init() {
        loadVideoSettings()
    }
    
    // MARK: - Video Settings Management
    func getVideoSettings(for path: String) -> VideoSettings {
        if let stored = videoSettings[path] {
            return stored
        }
        // Default: videos in a "Loop" folder loop automatically until the user overrides it.
        var defaults = VideoSettings()
        if path.contains("/Loop/") {
            defaults.isLooping = true
        }
        return defaults
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
}
