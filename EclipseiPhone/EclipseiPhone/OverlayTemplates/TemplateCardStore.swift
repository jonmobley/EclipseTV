//
//  TemplateCardStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Persists per-Show template cards as JSON in UserDefaults and
//               schedules their `TemplateCard` iCloud uploads and deletes.
//  Thread Safety: Main actor only.
//

import Foundation
import os.log

// MARK: - TemplateCardStore

/// Persists per-Show template cards, mirroring `CountdownStore`.
///
/// Every mutation persists, posts `didChangeNotification`, and (unless it came
/// from iCloud) schedules the matching `TemplateCard` record save or delete.
@MainActor
final class TemplateCardStore {

    // MARK: - Properties

    static let shared = TemplateCardStore()

    /// Posted when template cards change.
    static let didChangeNotification = Notification.Name("TemplateCardStore.didChange")

    private(set) var cards: [ShowTemplateCard] = []

    private let defaults: UserDefaults
    /// False in tests so a scratch store never schedules real iCloud work.
    private let schedulesSync: Bool
    private let itemsKey = "EclipseTV.templateCards.items"
    private let syncedIdsKey = "EclipseTV.templateCards.syncedIds"
    private var syncedIds: Set<String> = []
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "TemplateCardStore")

    // MARK: - Initialization

    /// Loads saved cards from `defaults`.
    init(defaults: UserDefaults = .standard, schedulesSync: Bool = true) {
        self.defaults = defaults
        self.schedulesSync = schedulesSync
        load()
    }

    // MARK: - Queries

    /// Cards belonging to `showId`, oldest first.
    func cards(forShowId showId: UUID) -> [ShowTemplateCard] {
        cards.filter { $0.showId == showId }
    }

    /// Card with `id`, if any.
    func card(id: UUID) -> ShowTemplateCard? {
        cards.first { $0.id == id }
    }

    /// Stack order that puts a new card above every card in `showId`.
    func nextStackOrder(inShowId showId: UUID) -> Int {
        (cards(forShowId: showId).map(\.stackOrder).max() ?? -1) + 1
    }

    /// Cards the server has not acknowledged yet.
    var idsNeedingUpload: [UUID] {
        cards.filter { !syncedIds.contains($0.id.uuidString) }.map(\.id)
    }

    // MARK: - Mutations

    /// Creates a card on top of the Show's stack and appends its tile.
    @discardableResult
    func create(config: OverlayCardConfig, name: String? = nil, showId: UUID) -> ShowTemplateCard {
        let trimmed = name.flatMap(UserDisplayName.normalized)
        let card = ShowTemplateCard(
            showId: showId,
            name: trimmed,
            config: config,
            stackOrder: nextStackOrder(inShowId: showId)
        )
        cards.append(card)
        persist()
        if schedulesSync {
            LocalAlbumStore.shared.addTemplate(card.id, toAlbumId: showId)
        }
        scheduleSaveIfNeeded(id: card.id)
        return card
    }

    /// Replaces the card's config (fields, style, corner) and optionally its name.
    func update(id: UUID, config: OverlayCardConfig, name: String? = nil) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let newName = name.flatMap(UserDisplayName.normalized) ?? cards[index].name
        guard cards[index].config != config || cards[index].name != newName else { return }
        cards[index].config = config
        cards[index].name = newName
        cards[index].modifiedAt = Date()
        persist()
        scheduleSaveIfNeeded(id: id)
    }

    /// Deletes the card, drops its tile, and schedules the iCloud delete.
    func delete(id: UUID) {
        guard let card = card(id: id) else { return }
        cards.removeAll { $0.id == id }
        syncedIds.remove(id.uuidString)
        persist()
        LiveOverlayController.shared.remove(.template(id))
        guard schedulesSync else { return }
        LocalAlbumStore.shared.removeTemplate(id, fromAlbumId: card.showId)
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        EclipseSyncController.shared.backend.scheduleTemplateCardDelete(id: id)
    }

    /// Purges after an iCloud tombstone without echoing a delete.
    func purgeRemote(id: UUID) {
        guard cards.contains(where: { $0.id == id }) else { return }
        cards.removeAll { $0.id == id }
        syncedIds.remove(id.uuidString)
        persist()
        LiveOverlayController.shared.remove(.template(id))
    }

    /// Inserts or replaces a card that arrived from iCloud.
    func applyRemote(_ card: ShowTemplateCard) {
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index] = card
        } else {
            cards.append(card)
        }
        syncedIds.insert(card.id.uuidString)
        persist()
    }

    /// Forgets every upload acknowledgement (zone loss, iCloud account switch).
    func markAllNeedsUpload() {
        guard !syncedIds.isEmpty else { return }
        syncedIds.removeAll()
        defaults.set(Array(syncedIds), forKey: syncedIdsKey)
    }

    /// Records that the backend accepted this card's upload.
    func markSynced(id: UUID) {
        guard syncedIds.insert(id.uuidString).inserted else { return }
        defaults.set(Array(syncedIds), forKey: syncedIdsKey)
    }

    /// Deletes every card belonging to `showId` (the Show itself was deleted).
    func deleteAll(forShowId showId: UUID) {
        let before = cards.count
        cards.removeAll { $0.showId == showId }
        guard cards.count != before else { return }
        persist()
    }

    // MARK: - Persistence

    private func load() {
        syncedIds = Set(defaults.stringArray(forKey: syncedIdsKey) ?? [])
        cards = SalvagingListDecoder.decodeList(
            ShowTemplateCard.self,
            forKey: itemsKey,
            from: defaults,
            logger: logger
        ).elements
    }

    private func scheduleSaveIfNeeded(id: UUID) {
        guard schedulesSync, !EclipseSyncController.shared.isApplyingRemote else { return }
        EclipseSyncController.shared.backend.scheduleTemplateCardSave(id: id)
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(cards)
            defaults.set(data, forKey: itemsKey)
            defaults.set(Array(syncedIds), forKey: syncedIdsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to encode template cards: \(error.localizedDescription)")
        }
    }
}
