//
//  CloudKitRecordMapper+Slideshow.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Slideshow

extension CloudKitRecordMapper {

    /// Builds a Slideshow metadata record. Sets `parent` only for share roots.
    static func makeSlideshowRecord(
        from show: Slideshow,
        existing: CKRecord? = nil,
        modifiedAt: Date = Date(),
        attachAsShareChild: Bool = false
    ) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.RecordType.slideshow,
            recordID: CloudKitSchema.slideshowRecordID(for: show.id)
        )
        record[CloudKitSchema.SlideshowKey.name] = show.name as CKRecordValue
        record[CloudKitSchema.SlideshowKey.itemIds] = show.itemIds as CKRecordValue
        if let cover = show.coverId {
            record[CloudKitSchema.SlideshowKey.coverId] = cover as CKRecordValue
        } else {
            record[CloudKitSchema.SlideshowKey.coverId] = nil
        }
        record[CloudKitSchema.SlideshowKey.orientation] =
            show.orientation.rawValue as CKRecordValue
        record[CloudKitSchema.SlideshowKey.autoplay] = show.autoplay as CKRecordValue
        record[CloudKitSchema.SlideshowKey.autoplaySeconds] =
            show.autoplaySeconds.rawValue as CKRecordValue
        record[CloudKitSchema.SlideshowKey.loop] = show.loop as CKRecordValue
        record[CloudKitSchema.SlideshowKey.crossfade] = show.crossfade as CKRecordValue
        record[CloudKitSchema.SlideshowKey.showRibbonWhenLive] =
            show.showRibbonWhenLive as CKRecordValue
        record[CloudKitSchema.SlideshowKey.isFill] = show.isFill as CKRecordValue
        record[CloudKitSchema.SlideshowKey.createdAt] = show.createdAt as CKRecordValue
        record[CloudKitSchema.SlideshowKey.modifiedAt] = modifiedAt as CKRecordValue
        applyShowLink(
            to: record,
            showId: show.showId,
            showIdKey: CloudKitSchema.SlideshowKey.showId,
            attachAsShareChild: attachAsShareChild
        )
        return record
    }

    /// Local slideshow from a Slideshow record.
    static func slideshow(from record: CKRecord) -> Slideshow? {
        guard record.recordType == CloudKitSchema.RecordType.slideshow,
              let uuid = UUID(uuidString: record.recordID.recordName),
              let name = record[CloudKitSchema.SlideshowKey.name] as? String,
              let showRaw = record[CloudKitSchema.SlideshowKey.showId] as? String,
              let showId = UUID(uuidString: showRaw)
        else { return nil }
        let itemIds = (record[CloudKitSchema.SlideshowKey.itemIds] as? [String]) ?? []
        let coverId = record[CloudKitSchema.SlideshowKey.coverId] as? String
        let rawOrientation = record[CloudKitSchema.SlideshowKey.orientation] as? String
        let orientation = ExternalOutputOrientation.resolved(fromStored: rawOrientation)
        let createdAt = (record[CloudKitSchema.SlideshowKey.createdAt] as? Date) ?? Date()
        let autoplay = (record[CloudKitSchema.SlideshowKey.autoplay] as? Bool) ?? false
        let secondsRaw = record[CloudKitSchema.SlideshowKey.autoplaySeconds] as? Int
        let autoplaySeconds = secondsRaw.flatMap(SlideshowAutoplaySeconds.init(rawValue:))
            ?? .default
        let loop = (record[CloudKitSchema.SlideshowKey.loop] as? Bool) ?? false
        let crossfade = (record[CloudKitSchema.SlideshowKey.crossfade] as? Bool) ?? true
        let showRibbon = (record[CloudKitSchema.SlideshowKey.showRibbonWhenLive] as? Bool)
            ?? false
        let isFill = (record[CloudKitSchema.SlideshowKey.isFill] as? Bool) ?? false
        return Slideshow(
            id: uuid,
            showId: showId,
            name: UserDisplayName.clamp(name),
            itemIds: itemIds,
            coverId: coverId,
            orientation: orientation,
            autoplay: autoplay,
            autoplaySeconds: autoplaySeconds,
            loop: loop,
            crossfade: crossfade,
            showRibbonWhenLive: showRibbon,
            isFill: isFill,
            createdAt: createdAt
        )
    }
}
