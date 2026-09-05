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
/// Show is the share root. Child records always store `showId` as a field;
/// CloudKit `parent` is set only when that Show is an actual `CKShare` root.
/// Setting `parent` on an unshared Show is rejected ("no chain protection info").
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
        static let webPage = "WebPage"
        static let slideshow = "Slideshow"
        static let countdown = "Countdown"
        static let livePoll = "LivePoll"
        static let background = "Background"
        static let screensaver = "Screensaver"
        static let cameraFrame = "CameraFrame"
        static let cameraSettings = "CameraSettings"
        static let cutawayStill = "CutawayStill"
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
        /// Practice Mode: live preview + Lock / Blackout when disconnected.
        static let previewsWhenDisconnected = "previewsWhenDisconnected"
        /// Membership ids removed on a device — union merge subtracts these.
        static let deletedItemIds = "deletedItemIds"
        /// Surface ids removed on a device (tools / slideshow tokens).
        static let deletedSurfaceIds = "deletedSurfaceIds"
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
        /// `imported` or `captured`. Missing → captured (legacy).
        static let provenance = "provenance"
        static let displayName = "displayName"
        /// Show membership / LocalMedia filename (imports; optional for captures).
        static let libraryId = "libraryId"
        static let fitMode = "fitMode"
        static let isLooping = "isLooping"
        static let isMuted = "isMuted"
    }

    enum PDFKey {
        static let title = "title"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"
        static let asset = "asset"
        static let showId = "showId"
    }

    enum WebPageKey {
        static let title = "title"
        static let url = "url"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"
    }

    enum SlideshowKey {
        static let showId = "showId"
        static let name = "name"
        static let itemIds = "itemIds"
        static let coverId = "coverId"
        static let orientation = "orientation"
        static let autoplay = "autoplay"
        static let autoplaySeconds = "autoplaySeconds"
        static let loop = "loop"
        static let crossfade = "crossfade"
        static let showRibbonWhenLive = "showRibbonWhenLive"
        static let isFill = "isFill"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"
    }

    enum CountdownKey {
        static let showId = "showId"
        static let name = "name"
        static let duration = "duration"
        static let layoutCenterX = "layoutCenterX"
        static let layoutCenterY = "layoutCenterY"
        static let layoutScale = "layoutScale"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"
    }

    enum LivePollKey {
        static let showId = "showId"
        static let pollId = "pollId"
        static let title = "title"
        static let questionCount = "questionCount"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"
    }

    enum BackgroundKey {
        static let asset = "asset"
        static let modifiedAt = "modifiedAt"
    }

    enum ScreensaverKey {
        static let kind = "kind"
        static let asset = "asset"
        static let poster = "poster"
        static let modifiedAt = "modifiedAt"
    }

    enum CameraFrameKey {
        static let asset = "asset"
        static let orientation = "orientation"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"
    }

    enum CameraSettingsKey {
        static let orientation = "orientation"
        static let enabledIds = "enabledIds"
        static let selectedId = "selectedId"
        static let modifiedAt = "modifiedAt"
    }

    enum CutawayKey {
        static let asset = "asset"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"
    }

    /// Singleton Background record in the library zone.
    static let backgroundRecordName = "eclipse.background"
    /// Singleton Screensaver record in the library zone.
    static let screensaverRecordName = "eclipse.screensaver"

    /// Record ID for a Show in the library zone.
    static func showRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Record ID for a MediaItem (capture UUID / import cloud id) in the library zone.
    static func mediaRecordID(for id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: id, zoneID: zoneID)
    }

    /// Record ID for a saved PDF in the library zone.
    static func pdfRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Record ID for a WebPage in the library zone.
    static func webPageRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Record ID for a Slideshow in the library zone.
    static func slideshowRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Record ID for a Countdown in the library zone.
    static func countdownRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Record ID for a Live Poll card in the library zone.
    static func livePollRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Singleton Background record ID.
    static var backgroundRecordID: CKRecord.ID {
        CKRecord.ID(recordName: backgroundRecordName, zoneID: zoneID)
    }

    /// Singleton Screensaver record ID.
    static var screensaverRecordID: CKRecord.ID {
        CKRecord.ID(recordName: screensaverRecordName, zoneID: zoneID)
    }

    /// Record ID for a camera frame PNG.
    static func cameraFrameRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Per-orientation camera ribbon settings.
    static func cameraSettingsRecordID(
        for orientation: ExternalOutputOrientation
    ) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "eclipse.cameraSettings.\(orientation.rawValue)",
            zoneID: zoneID
        )
    }

    /// Record ID for a camera cutaway still.
    static func cutawayRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }
}
