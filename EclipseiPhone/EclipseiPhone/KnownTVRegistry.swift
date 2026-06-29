//
//  KnownTVRegistry.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// KnownTVRegistry.swift
import Foundation

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

    private let key = "EclipseTV.companion.knownTVs"

    private init() {}

    /// All known TVs, most-recently-seen first.
    func all() -> [KnownTV] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([KnownTV].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Records `name` (or refreshes its `lastSeen` if already known).
    func remember(name: String) {
        var list = all()
        if let index = list.firstIndex(where: { $0.name == name }) {
            list[index].lastSeen = Date()
        } else {
            list.append(KnownTV(name: name, lastSeen: Date()))
        }
        persist(list)
    }

    /// Removes `name` from the registry.
    func forget(name: String) {
        persist(all().filter { $0.name != name })
    }

    private func persist(_ list: [KnownTV]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
