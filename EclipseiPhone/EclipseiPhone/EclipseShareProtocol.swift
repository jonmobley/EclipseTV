// EclipseShareProtocol.swift
import Foundation

/// Wire protocol shared between the Apple TV app and the iPhone companion for the
/// library-mirroring feature.
///
/// IMPORTANT: This file is intentionally duplicated verbatim in the Apple TV target
/// (`EclipseAppleTV/EclipseAppleTV/EclipseShareProtocol.swift`). The two copies MUST
/// stay in sync, exactly like the `serviceType` / handshake constants in the
/// connection managers.
///
/// Control messages travel as small JSON blobs over `MCSession.send(_:)` and are
/// tagged with a unique `eclipseMsg` key so they never collide with the legacy
/// raw-image data path or the `{type, size}` video-metadata JSON. Thumbnails travel
/// as named resources (`sendResource`) prefixed with `libthumb_`.
enum EclipseShareProtocol {
    /// Resource-name prefix used when streaming a library thumbnail TV -> iPhone.
    static let thumbnailResourcePrefix = "libthumb_"

    /// Discriminator values for the `eclipseMsg` envelope field.
    enum Kind: String {
        case libraryManifest = "library_manifest"
        case currentChanged = "current_changed"
        case playRequest = "play_request"
        case setVideoSetting = "set_video_setting"
        case deleteItem = "delete_item"
        case moveItem = "move_item"
        case reorderItems = "reorder_items"
        case restoreItem = "restore_item"
    }

    /// Builds the resource name used to send the thumbnail for a given item id.
    static func thumbnailResourceName(for id: String) -> String {
        return thumbnailResourcePrefix + id
    }

    /// Extracts the item id from a `libthumb_`-prefixed resource name, or nil if the
    /// name is not a library thumbnail.
    static func itemId(fromThumbnailResourceName name: String) -> String? {
        guard name.hasPrefix(thumbnailResourcePrefix) else { return nil }
        let id = String(name.dropFirst(thumbnailResourcePrefix.count))
        return id.isEmpty ? nil : id
    }
}

// MARK: - Item DTO

/// A single library entry as seen by the companion. Identity is the file name
/// (`lastPathComponent`) on the TV, never the absolute TV path.
///
/// `isLooping` / `isMuted` are only meaningful for videos and are optional so older
/// persisted manifests (without these fields) still decode cleanly.
struct LibraryItemDTO: Codable, Equatable {
    let id: String
    let name: String
    let isVideo: Bool
    let duration: Double
    var isLooping: Bool?
    var isMuted: Bool?
    /// nil or true means available; false means the TV's file was purged and the item
    /// can only be re-sent from the companion.
    var isAvailable: Bool?
}

// MARK: - Envelope

/// JSON envelope for every control message. Only the fields relevant to a given
/// `eclipseMsg` kind are populated.
struct EclipseShareEnvelope: Codable {
    let eclipseMsg: String
    var currentId: String?
    var items: [LibraryItemDTO]?
    var id: String?
    var isLooping: Bool? = nil
    var isMuted: Bool? = nil
    var toIndex: Int? = nil
    /// Full ordered list of item ids (file names) for a `reorderItems` message.
    var orderedIds: [String]? = nil

    var kind: EclipseShareProtocol.Kind? {
        EclipseShareProtocol.Kind(rawValue: eclipseMsg)
    }

    // MARK: Builders

    static func manifest(items: [LibraryItemDTO], currentId: String?) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.libraryManifest.rawValue,
            currentId: currentId,
            items: items,
            id: nil
        )
    }

    static func currentChanged(currentId: String?) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.currentChanged.rawValue,
            currentId: currentId,
            items: nil,
            id: nil
        )
    }

    static func playRequest(id: String) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.playRequest.rawValue,
            currentId: nil,
            items: nil,
            id: id
        )
    }

    /// Requests a per-item video setting change. Only non-nil fields are applied.
    static func setVideoSetting(id: String, isLooping: Bool?, isMuted: Bool?) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.setVideoSetting.rawValue,
            currentId: nil,
            items: nil,
            id: id,
            isLooping: isLooping,
            isMuted: isMuted
        )
    }

    static func deleteItem(id: String) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.deleteItem.rawValue,
            currentId: nil,
            items: nil,
            id: id
        )
    }

    static func moveItem(id: String, toIndex: Int) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.moveItem.rawValue,
            currentId: nil,
            items: nil,
            id: id,
            toIndex: toIndex
        )
    }

    /// Requests that the TV reorder its live library to match `orderedIds` exactly.
    /// Ids not present on the TV are ignored; unmentioned live items keep their order.
    static func reorderItems(orderedIds: [String]) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.reorderItems.rawValue,
            currentId: nil,
            items: nil,
            id: nil,
            orderedIds: orderedIds
        )
    }

    /// Marks the next inbound media resource as the restore of a purged item, so the TV
    /// can drop the ledger entry and move the freshly received item back into its slot.
    static func restoreItem(id: String) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.restoreItem.rawValue,
            currentId: nil,
            items: nil,
            id: id
        )
    }

    // MARK: Serialization

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Attempts to decode arbitrary inbound data as an Eclipse control message.
    /// Returns nil for anything that isn't a valid, tagged envelope (e.g. raw image
    /// bytes or the legacy video-metadata JSON), so callers can safely fall through
    /// to their existing handling.
    static func decode(from data: Data) -> EclipseShareEnvelope? {
        guard let envelope = try? JSONDecoder().decode(EclipseShareEnvelope.self, from: data),
              !envelope.eclipseMsg.isEmpty else {
            return nil
        }
        return envelope
    }
}
