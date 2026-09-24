//
//  KnownTVRegistry.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// A single Apple TV the companion has connected to at least once, identified by its
/// `MCPeerID.displayName` (the tvOS device name).
struct KnownTV: Codable, Equatable {
    let name: String
    var lastSeen: Date
}

/// Persists the set of Apple TVs this phone has ever connected to so they can be
/// listed in the header dropdown even while offline. Backed by `UserDefaults`.
@MainActor
final class KnownTVRegistry {

    static let shared = KnownTVRegistry()

    private let defaults: UserDefaults
    private let key = "EclipseTV.companion.knownTVs"
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "KnownTVRegistry")
    /// When true, the primary payload was unreadable and a backup was parked;
    /// mutations must not overwrite the primary until a successful load.
    private var didFailToLoad = false

    /// - Parameter defaults: Injected for tests; production uses `.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// All known TVs, most-recently-seen first.
    func all() -> [KnownTV] {
        load().sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Records `name` (or refreshes its `lastSeen` if already known).
    func remember(name: String) {
        guard !didFailToLoad else { return }
        var list = load()
        if let index = list.firstIndex(where: { $0.name == name }) {
            list[index].lastSeen = Date()
        } else {
            list.append(KnownTV(name: name, lastSeen: Date()))
        }
        persist(list)
    }

    /// Removes `name` from the registry.
    func forget(name: String) {
        guard !didFailToLoad else { return }
        persist(load().filter { $0.name != name })
    }

    // MARK: - Private

    /// Loads through the salvaging decoder so a bad payload cannot be overwritten
    /// by the next `remember` / `forget` with an empty list.
    private func load() -> [KnownTV] {
        let outcome = SalvagingListDecoder.decodeList(
            KnownTV.self,
            forKey: key,
            from: defaults,
            logger: logger
        )
        didFailToLoad = outcome.didFailToLoad
        if outcome.didFailToLoad { return [] }
        return outcome.elements
    }

    private func persist(_ list: [KnownTV]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: key)
        }
    }
}
