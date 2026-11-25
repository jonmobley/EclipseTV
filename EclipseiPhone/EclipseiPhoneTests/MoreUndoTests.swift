//
//  MoreUndoTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

/// Undo for Show delete, Library delete, Arrange and bulk card removal.
@MainActor
struct MoreUndoTests {

    // MARK: - Helpers

    private func makeStore() throws -> (LocalAlbumStore, UserDefaults) {
        let suite = "MoreUndoTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (LocalAlbumStore(defaults: defaults), defaults)
    }

    // MARK: - Show delete

    @Test func pendingDeleteHidesTheShowButKeepsItSaved() throws {
        let (store, defaults) = try makeStore()
        let first = try store.create(name: "First")
        let second = try store.create(name: "Second")
        store.add(itemId: "a", toAlbumId: first.id)

        #expect(store.beginPendingDelete(id: first.id))
        #expect(store.album(id: first.id) == nil)
        #expect(store.isPendingDelete(id: first.id))
        #expect(store.albumIncludingPendingDelete(id: first.id)?.itemIds == ["a"])
        // A crash now must not lose it: the saved list still has it.
        let reloaded = LocalAlbumStore(defaults: defaults)
        #expect(reloaded.album(id: first.id) != nil)
        #expect(reloaded.album(id: second.id) != nil)
    }

    @Test func undoPutsTheShowBackInPlaceWithNoDeletionMarker() throws {
        let (store, _) = try makeStore()
        let first = try store.create(name: "First")
        _ = try store.create(name: "Second")
        let before = store.albums.map(\.id)
        let clockKey = CloudKitSchema.showModifiedKey(for: first.id)
        UserDefaults.standard.set(123.0, forKey: clockKey)
        defer { UserDefaults.standard.removeObject(forKey: clockKey) }

        store.beginPendingDelete(id: first.id)
        #expect(store.cancelPendingDelete(id: first.id))

        #expect(store.albums.map(\.id) == before)
        #expect(!store.isPendingDelete(id: first.id))
        // Nothing of the delete ran: the sync clock (pruned by a real delete) is intact.
        #expect(UserDefaults.standard.double(forKey: clockKey) == 123.0)
    }

    @Test func commitDeletesForReal() throws {
        let (store, defaults) = try makeStore()
        let show = try store.create(name: "Gone")
        let clockKey = CloudKitSchema.showModifiedKey(for: show.id)
        UserDefaults.standard.set(123.0, forKey: clockKey)
        defer { UserDefaults.standard.removeObject(forKey: clockKey) }

        store.beginPendingDelete(id: show.id)
        store.commitPendingDelete(id: show.id)

        #expect(store.albumIncludingPendingDelete(id: show.id) == nil)
        #expect(LocalAlbumStore(defaults: defaults).album(id: show.id) == nil)
        #expect(UserDefaults.standard.object(forKey: clockKey) == nil)
        #expect(!store.cancelPendingDelete(id: show.id))
    }

    /// Another device deleted the Show while the toast was up: Undo must not
    /// bring it back here (it would be re-uploaded and undo their delete).
    @Test func remoteDeleteDuringTheWindowWinsOverUndo() throws {
        let (store, _) = try makeStore()
        let show = try store.create(name: "Remote")
        store.beginPendingDelete(id: show.id)

        store.delete(id: show.id)

        #expect(!store.cancelPendingDelete(id: show.id))
        #expect(store.albumIncludingPendingDelete(id: show.id) == nil)
    }

    @Test func remoteEditDuringTheWindowLandsOnTheHiddenShow() throws {
        let (store, _) = try makeStore()
        let show = try store.create(name: "Edited")
        store.beginPendingDelete(id: show.id)
        var remote = show
        remote.itemIds = ["x", "y"]

        store.applySynced(remote, modifiedAt: Date(timeIntervalSince1970: 10))
        defer { UserDefaults.standard.removeObject(forKey: CloudKitSchema.showModifiedKey(for: show.id)) }

        #expect(store.album(id: show.id) == nil)
        store.cancelPendingDelete(id: show.id)
        #expect(store.album(id: show.id)?.itemIds == ["x", "y"])
    }

    @Test func undoRenamesWhenTheNameWasTakenMeanwhile() throws {
        let (store, _) = try makeStore()
        let show = try store.create(name: "Sunday")
        store.beginPendingDelete(id: show.id)
        _ = try store.create(name: "Sunday")

        store.cancelPendingDelete(id: show.id)

        #expect(store.album(id: show.id)?.name == "Sunday (2)")
    }

    // MARK: - Pending deletes

    @Test func pendingDeletesRunOnlyWhenNotUndone() {
        let pending = PendingDeletes(notificationCenter: NotificationCenter())
        var ran: [String] = []
        pending.schedule(.libraryItem("a"), delay: 60) { ran.append("a") }
        pending.schedule(.libraryItem("b"), delay: 60) { ran.append("b") }
        #expect(pending.hiddenLibraryIds == ["a", "b"])

        #expect(pending.cancel(.libraryItem("a")))
        pending.commitAll()

        #expect(ran == ["b"])
        #expect(pending.hiddenLibraryIds.isEmpty)
        #expect(!pending.cancel(.libraryItem("b")))
    }

    @Test func pendingDeleteRunsWhenTimeIsUp() async throws {
        let pending = PendingDeletes(notificationCenter: NotificationCenter())
        var ran = false
        pending.schedule(.showCard("countdown:1"), delay: 0.05) { ran = true }
        #expect(pending.hiddenShowCardTokens == ["countdown:1"])

        try await Task.sleep(for: .milliseconds(300))

        #expect(ran)
        #expect(!pending.isPending(.showCard("countdown:1")))
    }

    @Test func schedulingTheSameKeyAgainRunsTheFirstDelete() {
        let pending = PendingDeletes(notificationCenter: NotificationCenter())
        var count = 0
        let key = PendingDeletes.Key.show(UUID())
        pending.schedule(key, delay: 60) { count += 1 }
        pending.schedule(key, delay: 60) { count += 10 }
        #expect(count == 1)
        pending.commit(key)
        #expect(count == 11)
    }

    // MARK: - Keyboard Undo

    @Test func keyboardUndoRunsTheLatestToastOnlyOnce() {
        let center = UndoToastCenter()
        var ran: [Int] = []
        let old = UUID()
        let new = UUID()
        center.register(token: old) { ran.append(1) }
        center.register(token: new) { ran.append(2) }
        center.clear(token: old)
        #expect(center.canUndo)

        #expect(center.performUndo())
        #expect(!center.performUndo())
        #expect(ran == [2])
    }

    // MARK: - Arrange

    @Test func arrangeUndoRestoresTheStartingOrder() {
        let restored = ArrangeUndo.restoredOrder(
            original: ["a", "b", "c"],
            current: ["c", "a", "b"]
        )
        #expect(restored == ["a", "b", "c"])
    }

    @Test func arrangeUndoKeepsNewCardsAndLeavesRemovedOnesOut() {
        let restored = ArrangeUndo.restoredOrder(
            original: ["a", "b", "c"],
            current: ["c", "new", "a"]
        )
        #expect(restored == ["a", "c", "new"])
    }

    // MARK: - Cards (countdowns / polls) vs. tombstones

    /// Undo of a removed countdown card re-adds its token with a newer date, so
    /// a device that already merged the removal shows the card again.
    @Test func cardUndoBeatsASyncedRemoval() throws {
        let (store, _) = try makeStore()
        let show = try store.create(name: "Cards")
        let countdownId = UUID()
        let token = ShowCountdownToken.token(for: countdownId)
        store.addCountdown(countdownId, toAlbumId: show.id)
        let snapshot = try #require(store.album(id: show.id))

        store.removeCountdown(countdownId, fromAlbumId: show.id)
        let otherDevice = try #require(store.album(id: show.id))
        #expect(SyncTombstones.isRemoved(token, in: otherDevice.deletedSurfaceIds))

        store.restoreMembership(from: snapshot)
        let undone = try #require(store.album(id: show.id))
        #expect(undone.surfaceIds?.contains(token) == true)
        let merged = CloudKitConflictResolver.mergeShows(
            local: otherDevice,
            localModified: Date(timeIntervalSince1970: 2),
            remote: undone,
            remoteModified: Date(timeIntervalSince1970: 1)
        )
        #expect(merged.resolvedSurfaceIds.contains(token))
    }
}
