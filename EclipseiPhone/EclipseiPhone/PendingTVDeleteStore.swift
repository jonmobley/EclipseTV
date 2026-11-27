//
//  PendingTVDeleteStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Library items deleted on the phone while no EclipseTV was linked.
///
/// The phone drops them at once; this list remembers to ask the Apple TV to
/// delete its copy the next time it sends its library, and keeps them out of the
/// phone's Library until the TV confirms they are gone.
///
/// Thread safety: main actor only.
@MainActor
final class PendingTVDeleteStore {

    /// Shared instance used by the Library delete flow, `TVLibraryStore` and the
    /// connection manager.
    static let shared = PendingTVDeleteStore()

    /// Item id → library mode raw value (`landscape` / `vertical`).
    private var modesById: [String: String]
    private let defaultsKey: String
    private let defaults: UserDefaults

    /// - Parameters:
    ///   - defaults: Where the list is kept (tests pass their own suite).
    ///   - defaultsKey: Key inside `defaults`.
    init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = "EclipseTV.companion.pendingTVDeletes"
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        modesById = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    // MARK: - Reads

    /// Whether an item is waiting to be deleted from the Apple TV.
    func contains(_ id: String) -> Bool { modesById[id] != nil }

    /// Waiting ids for one library mode.
    func ids(for mode: EclipseShareProtocol.LibraryMode) -> Set<String> {
        Set(modesById.filter { $0.value == mode.rawValue }.keys)
    }

    // MARK: - Writes

    /// Remembers to delete `id` from the Apple TV's `mode` library.
    func add(_ id: String, mode: EclipseShareProtocol.LibraryMode) {
        modesById[id] = mode.rawValue
        save()
    }

    /// Forgets ids the Apple TV no longer lists for `mode`.
    /// - Parameters:
    ///   - manifestIds: Every id in the TV's latest `mode` library.
    ///   - mode: The library the manifest describes.
    /// - Returns: Waiting ids the TV still has, to ask it to delete again.
    @discardableResult
    func reconcile(
        manifestIds: Set<String>,
        mode: EclipseShareProtocol.LibraryMode
    ) -> Set<String> {
        let waiting = ids(for: mode)
        let gone = waiting.subtracting(manifestIds)
        if !gone.isEmpty {
            for id in gone { modesById[id] = nil }
            save()
        }
        return waiting.intersection(manifestIds)
    }

    private func save() {
        defaults.set(modesById, forKey: defaultsKey)
    }
}
