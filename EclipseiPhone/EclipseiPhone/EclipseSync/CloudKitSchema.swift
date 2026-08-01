//
//  CloudKitSchema.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

/// CloudKit record types, zone, and field keys for Eclipse Sync.
///
/// Show is the share root; each MediaItem sets `parent` to its Show so a `CKShare`
/// carries the whole hierarchy. Captures without a Show use a nil parent.
enum CloudKitSchema {

    /// Custom zone in the private database (required for sharing).
    static let zoneName = "EclipseLibrary"
    static let zoneID = CKRecordZone.ID(
        zoneName: zoneName,
        ownerName: CKCurrentUserDefaultName
    )

    /// Container matching the iPhone entitlements file.
    static let containerIdentifier = "iCloud.com.mobleypro.eclipse.EclipseiPhone"

    enum RecordType {
        static let show = "Show"
        static let mediaItem = "MediaItem"
        static let pdfDoc = "PDFDoc"
    }

    enum ShowKey {
        static let name = "name"
        static let orientation = "orientation"
        static let itemIds = "itemIds"
        /// Optional Show grid order (tool tokens + members). Missing → default tools.
        static let surfaceIds = "surfaceIds"
        static let coverId = "coverId"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"
    }

    enum MediaKey {
        static let isVideo = "isVideo"
        static let duration = "duration"
        static let capturedAt = "capturedAt"
        static let contentHash = "contentHash"
        static let orientation = "orientation"
        static let fileExtension = "fileExtension"
        static let asset = "asset"
        static let showId = "showId"
        static let modifiedAt = "modifiedAt"
    }

    enum PDFKey {
        static let title = "title"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"
        static let asset = "asset"
        static let showId = "showId"
    }

    /// Record ID for a Show in the library zone.
    static func showRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Record ID for a MediaItem (capture UUID / library id) in the library zone.
    static func mediaRecordID(for id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: id, zoneID: zoneID)
    }

    /// Record ID for a saved PDF in the library zone.
    ///
    /// Shows and PDFs both use a bare UUID string, which is unambiguous because the
    /// two id spaces are independently minted. Callers resolving an unknown record
    /// name must consult the stores rather than the shape of the name.
    static func pdfRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }
}
