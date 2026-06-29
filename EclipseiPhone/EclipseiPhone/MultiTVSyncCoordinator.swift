// MultiTVSyncCoordinator.swift
import Foundation
import os.log

/// Keeps every Apple TV the companion is connected to in sync with the active TV's
/// library when "Keep all Apple TVs in sync" is enabled.
///
/// How sync works overall:
/// - While a replica TV is connected, live library mutations (sends, deletes, moves,
///   reorders, video settings) are broadcast to all connected TVs by
///   `iPhoneConnectionManager`, so connected TVs stay matched in real time.
/// - This coordinator handles the catch-up case: when a TV connects (or reconnects after
///   being offline during changes), it replays the full active library — the
///   full-resolution copies kept in `LocalMediaStore`, in the active TV's order — so the
///   newly connected TV converges on the same contents.
///
/// The active TV is the single source of truth for "the library"; `TVLibraryStore` mirrors
/// it. Replicas are caught up to that mirror. Items the phone has no local copy of (e.g.
/// added on the TV directly, or sent from another device) can't be replayed and are
/// skipped — the active TV still owns them.
@MainActor
final class MultiTVSyncCoordinator {

    /// Shared instance wired to the connection manager during setup.
    static let shared = MultiTVSyncCoordinator()

    /// The connection manager used to address individual TVs. Weak to avoid a retain cycle.
    weak var connectionManager: iPhoneConnectionManager?

    /// The library signature each TV was last caught up to, so we don't redundantly replay
    /// the same library to the same TV within a session.
    private var syncedSignatureByTV: [String: String] = [:]

    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "MultiTVSync")

    private init() {}

    // MARK: - Events

    /// Called when a replica TV connects. Replays the active library to it if sync is on
    /// and it isn't already caught up to the current library.
    func peerConnected(named name: String) {
        guard connectionManager?.syncAllEnabled == true else { return }
        replayLibrary(toPeerNamed: name)
    }

    /// Forgets a TV's caught-up state so a future connect re-replays the full library
    /// (e.g. after the user removes/forgets the TV, or clears its mirrored library).
    func forget(tvNamed name: String) {
        syncedSignatureByTV[name] = nil
    }

    /// Drops all caught-up state (e.g. when sync is toggled off and back on).
    func reset() {
        syncedSignatureByTV.removeAll()
    }

    // MARK: - Replay

    private func replayLibrary(toPeerNamed name: String) {
        let items = TVLibraryStore.shared.items
        guard !items.isEmpty else {
            logger.info("Active library is empty; nothing to replay to \(name, privacy: .public)")
            return
        }

        let signature = Self.signature(for: items)
        if syncedSignatureByTV[name] == signature {
            logger.info("Replica \(name, privacy: .public) already in sync; skipping replay")
            return
        }

        // Resolve the locally-stored full-resolution copies, preserving the active order.
        var payload: [(id: String, url: URL)] = []
        for item in items {
            if let url = LocalMediaStore.shared.localURL(forId: item.id) {
                payload.append((id: item.id, url: url))
            } else {
                logger.info("No local copy for \(item.id, privacy: .public); cannot replay to \(name, privacy: .public)")
            }
        }

        guard !payload.isEmpty else {
            logger.info("No replayable local media for \(name, privacy: .public)")
            return
        }

        let orderedIds = items.map { $0.id }
        logger.info("Replaying \(payload.count) of \(items.count) item(s) to replica \(name, privacy: .public)")
        connectionManager?.replayLibrary(payload, orderedIds: orderedIds, toPeerNamed: name) { [weak self] sent in
            guard let self, sent else { return }
            // Record only the items we could actually replay; if the local set later grows
            // (more items get local copies), the signature changes and we replay again.
            self.syncedSignatureByTV[name] = Self.signature(forIds: payload.map { $0.id })
        }
    }

    // MARK: - Signatures

    /// Order-sensitive signature of a library's item ids.
    private static func signature(for items: [LibraryItemDTO]) -> String {
        signature(forIds: items.map { $0.id })
    }

    private static func signature(forIds ids: [String]) -> String {
        ids.joined(separator: "\n")
    }
}
