//
//  AlbumManifest.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// AlbumManifest.swift
import Foundation

/// Wire format for an account's albums, fetched over HTTPS from
/// `…/manifest?code=<accountCode>`.
///
/// IMPORTANT: This mirrors `AlbumManifest` in the Apple TV target
/// (`EclipseAppleTV/EclipseAppleTV/RemoteAlbum/AlbumManifest.swift`) and MUST stay in
/// sync with it. Albums and items are pre-sorted; display order follows the arrays as
/// given. Unknown fields are ignored.
struct AlbumManifest: Codable, Equatable {
    /// Schema version. Currently always `1`.
    let version: Int
    /// The account code this manifest was fetched for (echoed back by the server).
    let code: String?
    /// The account's albums, in display order.
    let albums: [AlbumManifestAlbum]
}

/// A single album within an account manifest.
struct AlbumManifestAlbum: Codable, Equatable {
    let id: String
    let name: String?
    let items: [AlbumManifestItem]

    /// Display name, falling back to the id when the manifest omits `name`.
    var resolvedName: String { name?.isEmpty == false ? name! : id }
}

/// A single entry in an album.
struct AlbumManifestItem: Codable, Equatable {
    let id: String
    /// Absolute HTTPS URL of the full-resolution media.
    let url: String
    /// Optional absolute HTTPS URL of a server-generated thumbnail (under `thumbs/`).
    /// Preferred for grid cells; absent for older manifests.
    let thumbnailUrl: String?
    /// `"image"` or `"video"`. Anything other than `"video"` is treated as an image.
    let type: String
    let name: String?
    let checksum: String?

    var isVideo: Bool { type.lowercased() == "video" }
    var remoteURL: URL? { URL(string: url) }
    var thumbnailRemoteURL: URL? { thumbnailUrl.flatMap(URL.init(string:)) }
    var resolvedName: String { name?.isEmpty == false ? name! : id }

    /// Best URL for a grid thumbnail: the server thumbnail when present, otherwise the
    /// full image (images only). Videos with no thumbnail return `nil` (placeholder).
    var gridThumbnailURL: URL? {
        if let thumb = thumbnailRemoteURL { return thumb }
        return isVideo ? nil : remoteURL
    }
}
