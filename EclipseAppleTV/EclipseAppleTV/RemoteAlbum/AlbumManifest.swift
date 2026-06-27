// AlbumManifest.swift
import Foundation

/// Wire format for an account's albums, which the Apple TV syncs over HTTPS.
///
/// The TV performs a plain `GET` of `…/manifest?code=<accountCode>`, returning a JSON
/// document shaped like:
/// ```json
/// {
///   "version": 1,
///   "code": "123456",
///   "albums": [
///     {
///       "id": "uuid",
///       "name": "Summer Trip",
///       "items": [
///         { "id": "uuid", "url": "https://.../photo.jpg", "type": "image", "name": "photo", "checksum": "photo.jpg" }
///       ]
///     }
///   ]
/// }
/// ```
/// Albums and items are pre-sorted; display order follows the arrays as given. Unknown
/// fields are ignored so the contract can grow without breaking older clients.
struct AlbumManifest: Codable, Equatable {
    /// Schema version. Currently always `1`; reserved for future migrations.
    let version: Int
    /// The account code this manifest was fetched for (echoed back by the server).
    let code: String?
    /// The account's albums, in display order.
    let albums: [AlbumManifestAlbum]
}

/// A single album within an account manifest.
struct AlbumManifestAlbum: Codable, Equatable {
    /// Stable album identity (used to scope the album's on-disk media directory).
    let id: String
    /// Optional human-readable album name, shown as the section header.
    let name: String?
    /// Ordered album entries. Display order follows this array.
    let items: [AlbumManifestItem]

    /// Display name, falling back to the id when the manifest omits `name`.
    var resolvedName: String { name?.isEmpty == false ? name! : id }
}

/// A single entry in an album.
struct AlbumManifestItem: Codable, Equatable {
    /// Stable cross-sync identity. Also used (sanitized) as the local filename stem.
    let id: String
    /// Absolute HTTPS URL the media is downloaded from.
    let url: String
    /// Optional server thumbnail URL (under `thumbs/`). The TV ignores this — it
    /// downloads the full media and generates its own thumbnails — but it's carried for
    /// parity with the iPhone manifest and forward compatibility.
    var thumbnailUrl: String? = nil
    /// `"image"` or `"video"`. Anything other than `"video"` is treated as an image.
    let type: String
    /// Optional display name. Falls back to `id` when absent.
    let name: String?
    /// Optional content fingerprint. When it changes, the file is re-downloaded.
    let checksum: String?

    /// Whether this entry is a video (vs. an image).
    var isVideo: Bool { type.lowercased() == "video" }

    /// Parsed remote URL, or `nil` if the manifest contained an invalid string.
    var remoteURL: URL? { URL(string: url) }

    /// Display name, falling back to the id when the manifest omits `name`.
    var resolvedName: String { name?.isEmpty == false ? name! : id }
}
