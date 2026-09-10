//
//  CloudKitRemoteMediaPrefsTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import Testing
@testable import EclipseiPhone

/// Preference fields on a MediaItem carry no clock of their own, so a fetched record is
/// only newer than the local value when the local value has already been uploaded.
/// Applying it while a save is still pending reverted the crop the user just saved.
@Suite(.serialized)
@MainActor
struct CloudKitRemoteMediaPrefsTests {

    @Test func pendingLocalEditsSurviveAFetchedRecord() {
        let id = uniqueId()
        defer { reset(id) }
        let mine = MediaFraming(x: 0.2, y: 0.3, width: 0.4, height: 0.225)
        MediaFramingStore.set(mine, forId: id)
        MediaFitSettings.setMode(.fill, forId: id)

        CloudKitRecordMapper.applyRemoteMediaPrefs(
            from: mediaRecord(
                framing: MediaFraming(x: 0, y: 0, width: 1, height: 0.5625),
                fitMode: .fit
            ),
            libraryId: id,
            hasPendingLocalEdits: true
        )

        #expect(MediaFramingStore.framing(forId: id) == mine)
        #expect(MediaFitSettings.mode(forId: id) == .fill)
    }

    @Test func fetchedRecordAppliesOnceTheLocalEditHasBeenSent() {
        let id = uniqueId()
        defer { reset(id) }
        MediaFramingStore.set(
            MediaFraming(x: 0.2, y: 0.3, width: 0.4, height: 0.225), forId: id
        )
        let theirs = MediaFraming(x: 0, y: 0, width: 1, height: 0.5625)

        CloudKitRecordMapper.applyRemoteMediaPrefs(
            from: mediaRecord(framing: theirs, fitMode: .fit),
            libraryId: id,
            hasPendingLocalEdits: false
        )

        #expect(MediaFramingStore.framing(forId: id) == theirs)
        #expect(MediaFitSettings.mode(forId: id) == .fit)
    }

    @Test func pendingLocalEditsAlsoSurviveARecordThatClearsFraming() {
        // The reverting fetch is often a *cleared* framing, which looked like the crop
        // silently reverting to Fit rather than to some other position.
        let id = uniqueId()
        defer { reset(id) }
        let mine = MediaFraming(x: 0.1, y: 0.1, width: 0.5, height: 0.28125)
        MediaFramingStore.set(mine, forId: id)

        // Present but unusable is the "no custom position" wire shape.
        let record = mediaRecord(framing: nil, fitMode: .fit)
        record[CloudKitSchema.MediaKey.framing] = [0.5, 0.5] as CKRecordValue

        CloudKitRecordMapper.applyRemoteMediaPrefs(
            from: record, libraryId: id, hasPendingLocalEdits: true
        )
        #expect(MediaFramingStore.framing(forId: id) == mine)
    }

    @Test func aRecordWithoutFramingNeverWipesALocalPosition() {
        let id = uniqueId()
        defer { reset(id) }
        let mine = MediaFraming(x: 0.1, y: 0.1, width: 0.5, height: 0.28125)
        MediaFramingStore.set(mine, forId: id)

        CloudKitRecordMapper.applyRemoteMediaPrefs(
            from: mediaRecord(framing: nil, fitMode: .fill),
            libraryId: id,
            hasPendingLocalEdits: false
        )
        #expect(MediaFramingStore.framing(forId: id) == mine)
    }

    // MARK: - Helpers

    private func mediaRecord(
        framing: MediaFraming?,
        fitMode: MediaFitMode
    ) -> CKRecord {
        let record = CKRecord(
            recordType: CloudKitSchema.RecordType.mediaItem,
            recordID: CKRecord.ID(recordName: UUID().uuidString)
        )
        record[CloudKitSchema.MediaKey.isVideo] = false as CKRecordValue
        record[CloudKitSchema.MediaKey.fitMode] = fitMode.rawValue as CKRecordValue
        if let framing {
            record[CloudKitSchema.MediaKey.framing] = framing.asArray as CKRecordValue
        }
        return record
    }

    private func uniqueId() -> String {
        "remote-prefs-test-\(UUID().uuidString)"
    }

    private func reset(_ id: String) {
        MediaFramingStore.clear(forId: id)
        MediaFitSettings.clear(forId: id)
    }
}
