//
//  AudioPlayerController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import MediaPlayer
import os.log
import UIKit

/// Owns the single ambient music `AVPlayer`, queue, and system Now Playing integration.
@MainActor
final class AudioPlayerController: NSObject {

    static let shared = AudioPlayerController()

    /// Posted when play/pause/track/queue state changes.
    static let didChangeNotification = Notification.Name("AudioPlayerController.didChange")

    /// Posted when a track is removed from the store (player should drop it).
    static let trackRemovedNotification =
        Notification.Name("AudioPlayerController.trackRemoved")

    private(set) var queue: [UUID] = []
    private(set) var currentIndex: Int = 0
    private(set) var playlistId: UUID?
    private(set) var playlistName: String?
    private(set) var isPlaying = false
    private(set) var isMuted = false
    /// Relative mix level for ambient music (`0…1`), independent of system volume.
    private(set) var volume: Float = 1

    private static let volumeDefaultsKey = "Eclipse.audio.playerVolume"
    private static let playsNextDefaultsKey = "Eclipse.audio.playsNext"

    /// When true, the next queue item starts automatically when a track ends.
    private(set) var playsNext = true

    /// Active `AVPlayer`. Internal so fade helpers in `+Fade` can ramp volume.
    var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    /// Embedded artwork for the current track (used by Now Playing).
    private(set) var artworkCache: UIImage?
    private var lastTickNotify: TimeInterval = 0
    /// In-flight volume ramp; cancelled when transport changes.
    var volumeFadeTask: Task<Void, Never>?
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios", category: "AudioPlayer"
    )

    /// Current track, if the queue points at a valid id.
    var currentTrack: AudioTrack? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return AudioStore.shared.track(id: queue[currentIndex])
    }

    /// True when the mini player should be visible.
    var hasActiveSession: Bool {
        currentTrack != nil
    }

    /// Current playback time in seconds.
    var currentTime: TimeInterval {
        guard let time = player?.currentTime() else { return 0 }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite ? seconds : 0
    }

    /// Duration of the current item in seconds.
    ///
    /// Prefers the loaded asset's duration over the value captured at import: embedded
    /// metadata is missing or wrong often enough that trusting it puts a bogus range on
    /// the scrubber and the lock screen.
    var duration: TimeInterval {
        if let assetDuration = player?.currentItem?.duration {
            let seconds = CMTimeGetSeconds(assetDuration)
            if seconds.isFinite, seconds > 0 { return seconds }
        }
        return currentTrack?.duration ?? 0
    }

    /// Whether playback was active when the system interrupted us.
    /// Read and written by `AudioPlayerController+Session`.
    var wasPlayingBeforeInterruption = false

    private override init() {
        super.init()
        let stored = UserDefaults.standard.object(forKey: Self.volumeDefaultsKey) as? Float
        if let stored, stored.isFinite {
            volume = min(1, max(0, stored))
        }
        if UserDefaults.standard.object(forKey: Self.playsNextDefaultsKey) != nil {
            playsNext = UserDefaults.standard.bool(forKey: Self.playsNextDefaultsKey)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTrackRemoved(_:)),
            name: Self.trackRemovedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaylistsChanged),
            name: AudioPlaylistStore.didChangeNotification,
            object: nil
        )
        installSessionObservers()
        setupRemoteCommands()
    }

    // MARK: - Queue

    /// Plays all library tracks starting at `trackId` (or the first track).
    func playAll(startingAt trackId: UUID? = nil) {
        let ids = AudioStore.shared.tracks.map(\.id)
        guard !ids.isEmpty else { return }
        let index = trackId.flatMap { id in ids.firstIndex(of: id) } ?? 0
        loadQueue(ids, startIndex: index, playlistId: nil, playlistName: nil)
        play()
    }

    /// Plays a playlist starting at an optional track.
    func playPlaylist(_ playlist: AudioPlaylist, startingAt trackId: UUID? = nil) {
        preparePlaylist(playlist, startingAt: trackId)
        play()
    }

    /// Loads a playlist into the queue without starting playback (mini player stays up).
    func preparePlaylist(_ playlist: AudioPlaylist, startingAt trackId: UUID? = nil) {
        let ids = playlist.trackIds.filter { AudioStore.shared.track(id: $0) != nil }
        guard !ids.isEmpty else { return }
        let index = trackId.flatMap { id in ids.firstIndex(of: id) } ?? 0
        AudioPlaylistStore.shared.lastPlayedPlaylistId = playlist.id
        loadQueue(
            ids,
            startIndex: index,
            playlistId: playlist.id,
            playlistName: playlist.name
        )
        isPlaying = false
        player?.pause()
        updateNowPlayingPlayback()
        notify()
    }

    /// Plays a single track as a one-item queue.
    func play(trackId: UUID) {
        guard AudioStore.shared.track(id: trackId) != nil else { return }
        loadQueue([trackId], startIndex: 0, playlistId: nil, playlistName: nil)
        play()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    /// Starts playback with a volume fade-in.
    func play() {
        guard currentTrack != nil else { return }
        if player == nil { reloadCurrentItem() }
        // `reloadCurrentItem` leaves the player nil when the file is gone from disk.
        // Reporting `isPlaying` here would show an active mini player and lock-screen
        // transport over silence, with no way to recover.
        guard let player else {
            logger.error("No player for current track; not reporting playback")
            isPlaying = false
            updateNowPlayingPlayback()
            notify()
            return
        }
        // Already audible (or mid fade-in). After a track reload `isPlaying` can still be
        // true while the new player is idle — fall through so we fade that item in.
        if isPlaying, player.rate > 0 || volumeFadeTask != nil {
            return
        }
        cancelVolumeFade()
        activateSession()
        player.volume = 0
        player.play()
        isPlaying = true
        updateNowPlayingPlayback()
        notify()
        fadePlayerVolume(to: volume)
    }

    /// Pauses after a volume fade-out (`fade: false` syncs state when audio is already gone).
    func pause(fade: Bool = true) {
        let wasAudible = isPlaying || (player?.rate ?? 0) > 0
        cancelVolumeFade()
        isPlaying = false
        updateNowPlayingPlayback()
        notify()
        guard wasAudible, player != nil else {
            player?.pause()
            return
        }
        if fade {
            fadePlayerVolume(to: 0) { [weak self] in
                guard let self else { return }
                self.player?.pause()
                self.player?.volume = self.volume
            }
        } else {
            player?.pause()
            player?.volume = volume
        }
    }

    /// Fades out if audible, then clears the session (mini player hides immediately).
    func stop() {
        let audible = isPlaying
            && !isMuted
            && volume > 0.001
            && (player?.volume ?? 0) > 0.001
        let fadingPlayer = player
        cancelVolumeFade()

        queue = []
        currentIndex = 0
        playlistId = nil
        playlistName = nil
        isPlaying = false
        artworkCache = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        notify()

        if audible, let fadingPlayer {
            fadePlayerVolume(to: 0) { [weak self] in
                guard let self else { return }
                // A new session may have replaced the player while we faded.
                guard self.player === fadingPlayer else { return }
                self.teardownPlayer()
            }
        } else {
            teardownPlayer()
        }
    }

    /// Enables or disables automatic advance when the current track ends.
    ///
    /// Manual Next still skips. The preference is persisted.
    func setPlaysNext(_ enabled: Bool) {
        guard playsNext != enabled else { return }
        playsNext = enabled
        UserDefaults.standard.set(enabled, forKey: Self.playsNextDefaultsKey)
        notify()
    }

    func playNext() {
        guard !queue.isEmpty else { return }
        currentIndex = (currentIndex + 1) % queue.count
        reloadCurrentItem()
        play()
    }

    func playPrevious() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        reloadCurrentItem()
        play()
    }

    /// Jumps to a queue index and starts playback.
    func play(at index: Int) {
        guard queue.indices.contains(index) else { return }
        guard index != currentIndex else {
            play()
            return
        }
        currentIndex = index
        reloadCurrentItem()
        play()
    }

    func seek(to seconds: TimeInterval) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player?.seek(to: time)
        updateNowPlayingPlayback()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.isMuted = muted
        notify()
    }

    /// Sets ambient mix level (`0…1`). Values above zero clear mute.
    ///
    /// - Parameter notify: When false (slider drag), updates audio only — skips
    ///   `didChangeNotification` so Music/Home don't reload every tick.
    func setVolume(_ value: Float, notify notifyObservers: Bool = true) {
        let clamped = min(1, max(0, value.isFinite ? value : 0))
        volume = clamped
        cancelVolumeFade()
        if isPlaying {
            player?.volume = clamped
        } else {
            // Keep the paused player silent; next `play()` fades up to `volume`.
            player?.pause()
            player?.volume = 0
        }
        if clamped > 0, isMuted {
            isMuted = false
            player?.isMuted = false
        }
        guard notifyObservers else { return }
        UserDefaults.standard.set(clamped, forKey: Self.volumeDefaultsKey)
        notify()
    }

    /// Advances when Play Next is on; otherwise parks on this track, paused at 0.
    private func handleTrackDidEnd() {
        if playsNext, !queue.isEmpty {
            playNext()
            return
        }
        isPlaying = false
        reloadCurrentItem()
        player?.pause()
        updateNowPlayingPlayback()
    }

    // MARK: - Internals

    private func loadQueue(
        _ ids: [UUID],
        startIndex: Int,
        playlistId: UUID?,
        playlistName: String?
    ) {
        queue = ids
        currentIndex = min(max(0, startIndex), max(0, ids.count - 1))
        self.playlistId = playlistId
        self.playlistName = playlistName
        reloadCurrentItem()
    }

    private func reloadCurrentItem() {
        teardownPlayer(keepingQueue: true)
        guard let track = currentTrack,
              let url = AudioStore.shared.fileURL(for: track.id) else {
            notify()
            return
        }
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = isMuted
        // Start silent; `play()` fades up to the user mix level.
        newPlayer.volume = 0
        player = newPlayer
        artworkCache = nil
        let trackId = track.id
        Task {
            let image = await AudioStore.artwork(at: url)
            guard currentTrack?.id == trackId else { return }
            artworkCache = image
            publishNowPlaying()
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTrackDidEnd() }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateNowPlayingPlayback()
                self?.notifyTick()
            }
        }
        publishNowPlaying()
        notify()
    }

    func teardownPlayer(keepingQueue: Bool = false) {
        cancelVolumeFade()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player?.pause()
        player = nil
        if !keepingQueue {
            isPlaying = false
        }
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            logger.error("Audio session failed: \(error.localizedDescription)")
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Throttled UI refresh while scrubbing the playhead (~1/s).
    private func notifyTick() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTickNotify >= 0.5 else { return }
        lastTickNotify = now
        notify()
    }

    @objc private func handleTrackRemoved(_ note: Notification) {
        guard let id = note.userInfo?["id"] as? UUID else { return }
        let removedPositions = queue.indices.filter { queue[$0] == id }
        guard !removedPositions.isEmpty else { return }

        let removedCurrent = removedPositions.contains(currentIndex)
        // Shift the cursor by however many entries disappeared ahead of it, otherwise it
        // ends up pointing one past the playing track and gets clamped back to zero.
        let removedBefore = removedPositions.filter { $0 < currentIndex }.count

        queue.removeAll { $0 == id }
        if queue.isEmpty {
            stop()
            return
        }
        currentIndex = min(max(0, currentIndex - removedBefore), queue.count - 1)

        guard removedCurrent else {
            // Some other track left the queue; leave the current item playing untouched.
            notify()
            return
        }
        reloadCurrentItem()
        if isPlaying { play() } else { notify() }
    }

    /// Keeps a playing playlist queue in step with edits made in the playlist detail view.
    @objc private func handlePlaylistsChanged() {
        guard let playlistId else { return }

        guard let playlist = AudioPlaylistStore.shared.playlist(id: playlistId) else {
            // Playlist was deleted mid-playback: drop the association so the lock screen
            // stops advertising a playlist that no longer exists.
            self.playlistId = nil
            playlistName = nil
            publishNowPlaying()
            notify()
            return
        }

        playlistName = playlist.name
        let updated = playlist.trackIds.filter { AudioStore.shared.track(id: $0) != nil }
        guard updated != queue else {
            publishNowPlaying()
            notify()
            return
        }

        let playingId = currentTrack?.id
        queue = updated
        if queue.isEmpty {
            stop()
            return
        }
        if let playingId, let stillThere = queue.firstIndex(of: playingId) {
            // Same track, new position: keep it playing rather than restarting.
            currentIndex = stillThere
            publishNowPlaying()
            notify()
            return
        }
        currentIndex = min(currentIndex, queue.count - 1)
        reloadCurrentItem()
        if isPlaying { play() } else { notify() }
    }
}
