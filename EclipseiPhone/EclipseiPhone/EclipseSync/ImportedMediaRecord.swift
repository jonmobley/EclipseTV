//
//  ImportedMediaRecord.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Phone-owned metadata for a Photos import that syncs via CloudKit.
///
/// Distinct from `CaptureStore` so imports stay Multipeer-sendable to Apple TV.
/// CloudKit `MediaItem` record name is `cloudId`; Show membership uses `libraryId`.
struct ImportedMediaRecord: Equatable, Identifiable, Hashable {
    /// CloudKit record name (hyphenated UUID).
    let cloudId: String
    /// Show membership / LocalMedia filename (`LibraryItemDTO.id`).
    let libraryId: String
    let isVideo: Bool
    let duration: Double
    let capturedAt: Date
    var orientation: ExternalOutputOrientation
    var showId: UUID?
    var fileExtension: String
    var displayName: String?
    var syncState: CaptureSyncState
    var isDeleted: Bool

    var id: String { cloudId }

    /// Creates a registry row for a local import.
    init(
        cloudId: String = UUID().uuidString,
        libraryId: String,
        isVideo: Bool,
        duration: Double = 0,
        capturedAt: Date = Date(),
        orientation: ExternalOutputOrientation = ExternalOutputSettings.orientation,
        showId: UUID? = nil,
        fileExtension: String,
        displayName: String? = nil,
        syncState: CaptureSyncState = .pendingUpload,
        isDeleted: Bool = false
    ) {
        self.cloudId = cloudId
        self.libraryId = libraryId
        self.isVideo = isVideo
        self.duration = duration
        self.capturedAt = capturedAt
        self.orientation = orientation
        self.showId = showId
        self.fileExtension = fileExtension
        self.displayName = displayName
        self.syncState = syncState
        self.isDeleted = isDeleted
    }

    /// Mirror as a library DTO for Show grids (unavailable when remote-only).
    var asLibraryItem: LibraryItemDTO {
        LibraryItemDTO(
            id: libraryId,
            name: displayName ?? libraryId,
            isVideo: isVideo,
            duration: duration,
            isLooping: isVideo ? false : nil,
            isMuted: isVideo ? false : nil,
            isAvailable: syncState != .remoteOnly
        )
    }
}

// MARK: - Codable

extension ImportedMediaRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case cloudId, libraryId, isVideo, duration, capturedAt, orientation
        case showId, fileExtension, displayName, syncState, isDeleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cloudId = try c.decode(String.self, forKey: .cloudId)
        libraryId = try c.decode(String.self, forKey: .libraryId)
        isVideo = try c.decode(Bool.self, forKey: .isVideo)
        duration = try c.decode(Double.self, forKey: .duration)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        let raw = try c.decodeIfPresent(String.self, forKey: .orientation)
        orientation = ExternalOutputOrientation.resolved(fromStored: raw)
        showId = try c.decodeIfPresent(UUID.self, forKey: .showId)
        fileExtension = try c.decode(String.self, forKey: .fileExtension)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        syncState = try c.decode(CaptureSyncState.self, forKey: .syncState)
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cloudId, forKey: .cloudId)
        try c.encode(libraryId, forKey: .libraryId)
        try c.encode(isVideo, forKey: .isVideo)
        try c.encode(duration, forKey: .duration)
        try c.encode(capturedAt, forKey: .capturedAt)
        try c.encode(orientation.rawValue, forKey: .orientation)
        try c.encodeIfPresent(showId, forKey: .showId)
        try c.encode(fileExtension, forKey: .fileExtension)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encode(syncState, forKey: .syncState)
        try c.encode(isDeleted, forKey: .isDeleted)
    }
}
