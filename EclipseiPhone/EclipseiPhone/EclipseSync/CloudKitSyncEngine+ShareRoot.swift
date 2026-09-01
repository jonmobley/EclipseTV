//
//  CloudKitSyncEngine+ShareRoot.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

extension CloudKitSyncEngine {

    /// Records that this Show is a `CKShare` root and re-saves its children
    /// with CloudKit `parent` set.
    func noteShareRootEstablished(_ showId: UUID) {
        guard shareRoots.mark(showId) else { return }
        enqueueShareChildren(of: showId)
    }

    /// Clears the share-root mark and re-saves children without `parent`.
    func noteShareRootRemoved(_ showId: UUID) {
        guard shareRoots.unmark(showId) else { return }
        enqueueShareChildren(of: showId)
    }

    /// Learns share-root status from a fetched Show (`record.share != nil`).
    ///
    /// Does not unmark when `share` is missing — local Show saves omit the
    /// share system field and must not erase a root we already know about.
    func learnShareRoot(from record: CKRecord) {
        guard record.recordType == CloudKitSchema.RecordType.show,
              record.share != nil,
              let uuid = UUID(uuidString: record.recordID.recordName)
        else { return }
        noteShareRootEstablished(uuid)
    }

    /// Re-enqueues children that belong to `showId`.
    func enqueueShareChildren(of showId: UUID) {
        guard let engine else { return }
        let itemIds = shareChildItemIds(for: showId)
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        var seen = Set<String>()
        for itemId in itemIds {
            appendChildSave(itemId: itemId, into: &changes, seen: &seen)
        }
        for show in SlideshowStore.shared.slideshows(forShowId: showId) {
            let key = show.id.uuidString
            guard seen.insert(key).inserted else { continue }
            changes.append(
                .saveRecord(CloudKitSchema.slideshowRecordID(for: show.id))
            )
        }
        for item in CountdownStore.shared.countdowns(forShowId: showId) {
            let key = item.id.uuidString
            guard seen.insert(key).inserted else { continue }
            changes.append(
                .saveRecord(CloudKitSchema.countdownRecordID(for: item.id))
            )
        }
        for item in LivePollStore.shared.polls(forShowId: showId) {
            let key = item.id.uuidString
            guard seen.insert(key).inserted else { continue }
            changes.append(
                .saveRecord(CloudKitSchema.livePollRecordID(for: item.id))
            )
        }
        if !changes.isEmpty {
            engine.state.add(pendingRecordZoneChanges: changes)
        }
    }

    private func shareChildItemIds(for showId: UUID) -> [String] {
        let albumIds = LocalAlbumStore.shared.album(id: showId)?.itemIds ?? []
        let captureIds = CaptureStore.shared.allActive
            .filter { $0.showId == showId }
            .map(\.id)
        let importIds = ImportedMediaStore.shared.allActive
            .filter { $0.showId == showId }
            .map(\.cloudId)
        return albumIds + captureIds + importIds
    }

    private func appendChildSave(
        itemId: String,
        into changes: inout [CKSyncEngine.PendingRecordZoneChange],
        seen: inout Set<String>
    ) {
        if let capture = CaptureStore.shared.record(id: itemId),
           seen.insert(capture.id).inserted {
            changes.append(
                .saveRecord(CloudKitSchema.mediaRecordID(for: capture.id))
            )
            return
        }
        if let imported = ImportedMediaStore.shared.record(id: itemId),
           seen.insert(imported.cloudId).inserted {
            changes.append(
                .saveRecord(CloudKitSchema.mediaRecordID(for: imported.cloudId))
            )
            return
        }
        guard let uuid = UUID(uuidString: itemId) else { return }
        if WebPageStore.shared.page(id: uuid) != nil,
           seen.insert(uuid.uuidString).inserted {
            changes.append(.saveRecord(CloudKitSchema.webPageRecordID(for: uuid)))
            return
        }
        if PDFStore.shared.documents.contains(where: { $0.id == uuid }),
           seen.insert(uuid.uuidString).inserted {
            changes.append(.saveRecord(CloudKitSchema.pdfRecordID(for: uuid)))
        }
    }

    /// Unmarks the parent Show so the next batch omits `parent` and can succeed.
    func retryWithoutShareParent(_ record: CKRecord) {
        if let showId = membershipShowId(from: record) {
            shareRoots.unmark(showId)
        }
        logger.notice(
            "Retrying \(record.recordID.recordName, privacy: .public) without parent"
        )
    }

    private func membershipShowId(from record: CKRecord) -> UUID? {
        let raw = (record[CloudKitSchema.MediaKey.showId] as? String)
            ?? (record[CloudKitSchema.SlideshowKey.showId] as? String)
            ?? (record[CloudKitSchema.PDFKey.showId] as? String)
            ?? record.parent?.recordID.recordName
        return raw.flatMap(UUID.init(uuidString:))
    }
}
