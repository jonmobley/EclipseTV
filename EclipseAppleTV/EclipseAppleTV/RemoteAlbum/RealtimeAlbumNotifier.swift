//
//  RealtimeAlbumNotifier.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// RealtimeAlbumNotifier.swift
import Foundation
import Supabase
import os.log

/// Opens a Supabase Realtime WebSocket and listens for "album changed" broadcasts scoped
/// to a single account code, invoking `onChange` (debounced) so the caller can re-sync.
///
/// The TV's manifest sync (`RemoteAlbumSync`) remains the source of truth; this only
/// delivers a lightweight nudge that says "something changed, re-fetch now". It is safe
/// to `start`/`stop` repeatedly; starting with a new code replaces any prior subscription.
/// When Realtime isn't configured (placeholder credentials in `AlbumConfig`), every call
/// is a no-op and the app keeps relying on launch/foreground/manual sync.
@MainActor
final class RealtimeAlbumNotifier {

    /// Invoked on the main actor when the server signals the account's albums changed.
    /// Debounced so a burst of edits collapses into a single callback.
    var onChange: (() -> Void)?

    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "RealtimeAlbumNotifier")

    /// Built lazily so the WebSocket client only exists once Realtime is configured.
    private lazy var client: SupabaseClient? = {
        guard AlbumConfig.isRealtimeConfigured else { return nil }
        return SupabaseClient(supabaseURL: AlbumConfig.supabaseURL,
                              supabaseKey: AlbumConfig.supabaseAnonKey)
    }()

    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var currentCode: String?

    /// Window for coalescing a burst of change events into one `onChange`.
    private let debounceInterval: Duration = .milliseconds(800)

    // MARK: - Lifecycle

    /// Subscribes to the broadcast topic for `code`. No-op if already listening to the
    /// same code, if `code` is malformed, or if Realtime isn't configured.
    func start(code: String) {
        let normalized = AlbumConfig.normalize(code)
        guard AlbumConfig.isValidCode(normalized) else { return }
        guard let client else {
            logger.info("Realtime not configured; skipping subscription")
            return
        }
        if currentCode == normalized, channel != nil { return }

        stop()
        currentCode = normalized

        let topic = AlbumConfig.realtimeTopic(forCode: normalized)
        let channel = client.channel(topic)
        self.channel = channel
        logger.info("Subscribing to realtime topic \(topic, privacy: .public)")

        listenTask = Task { [weak self] in
            // Register the broadcast handler before subscribing, per the Realtime SDK.
            let stream = channel.broadcastStream(event: AlbumConfig.realtimeChangeEvent)
            await channel.subscribe()
            for await _ in stream {
                if Task.isCancelled { break }
                self?.scheduleChange()
            }
        }
    }

    /// Tears down the subscription and frees the WebSocket.
    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        listenTask?.cancel()
        listenTask = nil
        currentCode = nil
        if let channel, let client {
            Task { await client.removeChannel(channel) }
        }
        channel = nil
    }

    // MARK: - Debounce

    /// Schedules `onChange` after a quiet period, cancelling any previously scheduled fire
    /// so rapid bursts (e.g. deleting several items) collapse into one re-sync.
    private func scheduleChange() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounceInterval)
            if Task.isCancelled { return }
            self.logger.info("Realtime change received; firing onChange")
            self.onChange?()
        }
    }
}
