//
//  CaptureRecord.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Phone-owned metadata for an in-app camera capture (or a capture synced from iCloud).
///
/// Identity is a minted UUID string (stable across devices). Full-res bytes live under
/// `Captures/<Mode>/` via `LocalMediaStore` with `.captured` provenance.
struct CaptureRecord: Equatable, Identifiable, Hashable {
    /// Stable id — also the CloudKit record name and on-disk file stem.
    let id: String
    let isVideo: Bool
    let duration: Double
    let capturedAt: Date
    /// Landscape / Vertical bucket for Display Mode.
    var orientation: ExternalOutputOrientation
    /// Optional Show this capture belongs to (CloudKit `showId` field).
    var showId: UUID?
    /// Reserved for change detection / dedupe. Schema read/write only — nothing
    /// assigns a hash yet; leave inert until a consumer needs it.
    var contentHash: String?
    /// File extension without the leading dot (`jpg`, `mov`).
    var fileExtension: String
    var syncState: CaptureSyncState
    /// Soft-deleted locally while a cloud delete is pending.
    var isDeleted: Bool

    /// Creates a new local capture record.
    init(
        id: String = UUID().uuidString,
        isVideo: Bool,
        duration: Double = 0,
        capturedAt: Date = Date(),
        orientation: ExternalOutputOrientation = ExternalOutputSettings.orientation,
        showId: UUID? = nil,
        contentHash: String? = nil,
        fileExtension: String,
        syncState: CaptureSyncState = .localOnly,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.isVideo = isVideo
        self.duration = duration
        self.capturedAt = capturedAt
        self.orientation = orientation
        self.showId = showId
        self.contentHash = contentHash
        self.fileExtension = fileExtension
        self.syncState = syncState
        self.isDeleted = isDeleted
    }

    /// Library filename used by `LocalMediaStore` / `LibraryItemDTO.id`.
    var libraryFileName: String {
        LocalMediaStore.canonicalFileName(forId: "\(id).\(fileExtension)")
    }

    /// Mirror as a library DTO for Show grids and the gallery.
    var asLibraryItem: LibraryItemDTO {
        LibraryItemDTO(
            id: libraryFileName,
            name: libraryFileName,
            isVideo: isVideo,
            duration: duration,
            isLooping: isVideo ? false : nil,
            isMuted: isVideo ? false : nil,
            isAvailable: syncState != .remoteOnly
        )
    }
}

// MARK: - Codable

extension CaptureRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, isVideo, duration, capturedAt, orientation, showId
        case contentHash, fileExtension, syncState, isDeleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        isVideo = try c.decode(Bool.self, forKey: .isVideo)
        duration = try c.decode(Double.self, forKey: .duration)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        let raw = try c.decodeIfPresent(String.self, forKey: .orientation)
        orientation = ExternalOutputOrientation.resolved(fromStored: raw)
        showId = try c.decodeIfPresent(UUID.self, forKey: .showId)
        contentHash = try c.decodeIfPresent(String.self, forKey: .contentHash)
        fileExtension = try c.decode(String.self, forKey: .fileExtension)
        syncState = try c.decode(CaptureSyncState.self, forKey: .syncState)
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(isVideo, forKey: .isVideo)
        try c.encode(duration, forKey: .duration)
        try c.encode(capturedAt, forKey: .capturedAt)
        try c.encode(orientation.rawValue, forKey: .orientation)
        try c.encodeIfPresent(showId, forKey: .showId)
        try c.encodeIfPresent(contentHash, forKey: .contentHash)
        try c.encode(fileExtension, forKey: .fileExtension)
        try c.encode(syncState, forKey: .syncState)
        try c.encode(isDeleted, forKey: .isDeleted)
    }
}
