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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether `displayName` was previously paired (safe to auto-invite).
    func isPaired(displayName: String) -> Bool {
        pairedNames().contains(displayName)
    }

    /// Records a successful connection so future discovery can auto-invite.
    func remember(displayName: String) {
        var names = pairedNames()
        guard names.insert(displayName).inserted else { return }
        persist(names)
        logger.info("Paired Apple TV remembered: \(displayName, privacy: .private)")
    }

    /// Removes one paired TV.
    func forget(displayName: String) {
        var names = pairedNames()
        guard names.remove(displayName) != nil else { return }
        persist(names)
    }

    /// Clears every paired TV.
    func forgetAll() {
        defaults.removeObject(forKey: key)
    }

    /// Sorted display names for Settings / library UI.
    func allPairedNames() -> [String] {
        pairedNames().sorted()
    }

    // MARK: - Private

    private func pairedNames() -> Set<String> {
        guard let data = defaults.data(forKey: key),
              let names = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return []
        }
        return names
    }

    private func persist(_ names: Set<String>) {
        if let data = try? JSONEncoder().encode(names) {
            defaults.set(data, forKey: key)
        }
    }
}
