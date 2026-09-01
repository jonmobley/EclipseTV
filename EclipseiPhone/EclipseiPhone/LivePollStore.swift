//
//  LivePollStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Persists per-Show Live Poll cards as JSON metadata in UserDefaults.
@MainActor
final class LivePollStore {

    static let shared = LivePollStore()

    /// Posted when Live Poll cards change.
    static let didChangeNotification = Notification.Name("LivePollStore.didChange")

    private(set) var polls: [ShowLivePoll] = []

    private let defaults: UserDefaults
    private let itemsKey = "EclipseTV.livePolls.items"
    private let syncedIdsKey = "EclipseTV.livePolls.syncedIds"
    private var syncedIds: Set<String> = []
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "LivePollStore"
    )

    private var didDropLegacy = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Queries

    /// Cards belonging to `showId`, oldest first (surface append order).
    func polls(forShowId showId: UUID) -> [ShowLivePoll] {
        polls.filter { $0.showId == showId }
    }

    /// Card with `id`, if any.
    func poll(id: UUID) -> ShowLivePoll? {
        polls.first { $0.id == id }
    }

    // MARK: - Mutations

    /// Creates a card from a QuestPoll deck and appends it to the Show surface.
    @discardableResult
    func create(
        pollId: String,
        title: String,
        questionCount: Int,
        showId: UUID
    ) -> ShowLivePoll {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = ShowLivePoll(
            showId: showId,
            pollId: pollId,
            title: trimmedTitle.isEmpty ? "Live Poll" : trimmedTitle,
            questionCount: questionCount
        )
        polls.append(item)
        persist()
        LocalAlbumStore.shared.addLivePoll(item.id, toAlbumId: showId)
        return item
    }

    /// Rebinds an existing card to another QuestPoll deck.
    func replace(id: UUID, with summary: QuestPollSummary) {
        guard let index = polls.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = summary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        polls[index].pollId = summary.id
        polls[index].title = trimmed.isEmpty ? "Live Poll" : trimmed
        polls[index].questionCount = max(summary.questionCount, 1)
        persist()
    }

    /// Deletes the card with `id` when present.
    func delete(id: UUID) {
        guard let item = polls.first(where: { $0.id == id }) else { return }
        polls.removeAll { $0.id == id }
        syncedIds.remove(id.uuidString)
        persist()
        LocalAlbumStore.shared.removeLivePoll(id, fromAlbumId: item.showId)
    }

    /// Deletes every card belonging to `showId`.
    func deleteAll(forShowId showId: UUID) {
        let before = polls.count
        polls.removeAll { $0.showId == showId }
        guard polls.count != before else { return }
        persist()
    }

    /// Drops retired singleton `__eclipse.tool.livePoll` tokens (no pollId).
    func dropLegacyToolTokensIfNeeded() {
        guard defaults === UserDefaults.standard, !didDropLegacy else { return }
        didDropLegacy = true
        for album in LocalAlbumStore.shared.albums {
            LocalAlbumStore.shared.dropLegacyLivePollTool(albumId: album.id)
        }
    }

    // MARK: - Persistence

    private func load() {
        syncedIds = Set(defaults.stringArray(forKey: syncedIdsKey) ?? [])
        polls = SalvagingListDecoder.decodeList(
            ShowLivePoll.self,
            forKey: itemsKey,
            from: defaults,
            logger: logger
        ).elements
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(polls)
            defaults.set(data, forKey: itemsKey)
            defaults.set(Array(syncedIds), forKey: syncedIdsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to encode live polls: \(error.localizedDescription)")
        }
    }
}
