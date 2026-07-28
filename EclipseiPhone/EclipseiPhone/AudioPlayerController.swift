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

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    /// Embedded artwork for the current track (used by Now Playing).
    private(set) var artworkCache: UIImage?
    private var lastTickNotify: TimeInterval = 0
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
    var duration: TimeInterval {
        currentTrack?.duration ?? 0
    }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTrackRemoved(_:)),
            name: Self.trackRemovedNotification,
            object: nil
        )
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
        play()
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

    func play() {
        guard currentTrack != nil else { return }
        if player == nil { reloadCurrentItem() }
        activateSession()
        player?.play()
        isPlaying = true
        updateNowPlayingPlayback()
        notify()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingPlayback()
        notify()
    }

    /// Stops playback and clears the active session (mini player hides).
    func stop() {
        teardownPlayer()
        queue = []
        currentIndex = 0
        playlistId = nil
        playlistName = nil
        isPlaying = false
        artworkCache = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
            Task { @MainActor in self?.playNext() }
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

    private func teardownPlayer(keepingQueue: Bool = false) {
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
        queue.removeAll { $0 == id }
        if queue.isEmpty {
            stop()
            return
        }
        if currentIndex >= queue.count {
            currentIndex = 0
        }
        reloadCurrentItem()
        if isPlaying { play() } else { notify() }
    }
}
