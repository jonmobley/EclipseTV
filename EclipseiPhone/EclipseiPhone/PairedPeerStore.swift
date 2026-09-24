//
//  PairedPeerStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Allowlist of Apple TVs this iPhone has successfully paired with.
///
/// Peers are keyed by `MCPeerID.displayName`. First connect requires entering the PIN
/// shown on the TV; later auto-connect uses the remembered invitation context.
final class PairedPeerStore {

    static let shared = PairedPeerStore()

    private let defaults: UserDefaults
    private let key = "EclipseTV.companion.pairedTVs"
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "PairedPeerStore")
    /// When true, the primary payload was unreadable and a backup was parked;
    /// mutations must not overwrite the primary until a successful load.
    private var didFailToLoad = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether `displayName` was previously paired (safe to auto-invite).
    func isPaired(displayName: String) -> Bool {
        pairedNames().contains(displayName)
    }

    /// Records a successful connection so future discovery can auto-invite.
    func remember(displayName: String) {
        guard !didFailToLoad else { return }
        var names = pairedNames()
        guard names.insert(displayName).inserted else { return }
        persist(names)
        logger.info("Paired Apple TV remembered: \(displayName, privacy: .private)")
    }

    /// Removes one paired TV.
    func forget(displayName: String) {
        guard !didFailToLoad else { return }
        var names = pairedNames()
        guard names.remove(displayName) != nil else { return }
        persist(names)
    }

    /// Clears every paired TV.
    func forgetAll() {
        didFailToLoad = false
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: SalvagingListDecoder.backupKey(for: key))
    }

    /// Sorted display names for Settings / library UI.
    func allPairedNames() -> [String] {
        pairedNames().sorted()
    }

    // MARK: - Private

    /// Loads through the salvaging decoder so a bad payload cannot be overwritten
    /// by the next `remember` / `forget` with an empty allowlist.
    private func pairedNames() -> Set<String> {
        let outcome = SalvagingListDecoder.decodeList(
            String.self,
            forKey: key,
            from: defaults,
            logger: logger
        )
        didFailToLoad = outcome.didFailToLoad
        if outcome.didFailToLoad { return [] }
        return Set(outcome.elements)
    }

    private func persist(_ names: Set<String>) {
        // Store as a sorted array so SalvagingListDecoder can salvage element-wise.
        if let data = try? JSONEncoder().encode(names.sorted()) {
            defaults.set(data, forKey: key)
        }
    }
}
