//
//  PairedPeerStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Allowlist of iPhone companions that have successfully paired with this Apple TV.
///
/// MultipeerConnectivity does not expose a stable cryptographic peer identity, so peers
/// are keyed by `MCPeerID.displayName` (the iPhone's device name). A correct pairing PIN
/// is still required on first connect; later reconnects use the `remembered` context and
/// this allowlist.
final class PairedPeerStore {

    static let shared = PairedPeerStore()

    private let defaults: UserDefaults
    private let key = "EclipseTV.pairing.pairedPhones"
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "PairedPeerStore")

    /// Current on-screen pairing PIN. Regenerated on demand; not persisted.
    private(set) var currentPIN: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.currentPIN = PeerPairing.generatePIN()
    }

    /// Whether `displayName` has completed a successful PIN pair on this TV.
    func isPaired(displayName: String) -> Bool {
        pairedNames().contains(displayName)
    }

    /// Records a successful pair so future invites can use the remembered context.
    func remember(displayName: String) {
        var names = pairedNames()
        guard names.insert(displayName).inserted else { return }
        persist(names)
        logger.info("Paired phone remembered: \(displayName, privacy: .private)")
    }

    /// Removes one paired phone (or no-op if absent).
    func forget(displayName: String) {
        var names = pairedNames()
        guard names.remove(displayName) != nil else { return }
        persist(names)
    }

    /// Clears every paired phone.
    func forgetAll() {
        defaults.removeObject(forKey: key)
    }

    /// Sorted display names for UI (e.g. forget-device menus).
    func allPairedNames() -> [String] {
        pairedNames().sorted()
    }

    /// Issues a new PIN and returns it. Call when the user asks to re-pair or after a
    /// successful pair if you want the old code to stop working.
    @discardableResult
    func rotatePIN() -> String {
        currentPIN = PeerPairing.generatePIN()
        logger.info("Pairing PIN rotated")
        return currentPIN
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
