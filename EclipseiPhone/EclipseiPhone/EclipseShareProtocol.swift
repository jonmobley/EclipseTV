//
//  EclipseShareProtocol.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

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
        case playbackCommand = "playback_command"
        case playbackStatus = "playback_status"
        /// Companion configures the TV's read-only remote albums from an account code.
        case setAccount = "set_account"
    }

    /// Remote playback actions a companion can request for the live video on the TV.
    enum PlaybackAction: String {
        case play
        case pause
        case toggle
        /// Seek to an absolute position (seconds), carried in the envelope's `position`.
        case seek
        /// Seek relative to the current position by `position` seconds (may be negative).
        case skip
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
    /// Remote-playback fields. `playbackAction` names a command (iPhone -> TV); `position`
    /// carries an absolute seek target or a relative skip delta (seconds). For a
    /// `playbackStatus` (TV -> iPhone), `isPlaying`, `position` (current time) and
    /// `playbackDuration` describe the live video's playback state.
    var playbackAction: String? = nil
    var position: Double? = nil
    var playbackDuration: Double? = nil
    var isPlaying: Bool? = nil
    /// Remote-album field (iPhone -> TV). `accountCode` is the short account code the TV
    /// composes its manifest URL from (via `AlbumConfig`); the manifest returns all of
    /// that account's albums.
    var accountCode: String? = nil

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

    /// Requests a remote playback action for the live video on the TV. `position` is the
    /// absolute target for `.seek` or the relative delta for `.skip` (seconds).
    static func playbackCommand(action: EclipseShareProtocol.PlaybackAction, position: Double?) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.playbackCommand.rawValue,
            currentId: nil,
            items: nil,
            id: nil,
            playbackAction: action.rawValue,
            position: position
        )
    }

    /// Reports the live video's current playback state to companions.
    static func playbackStatus(currentId: String?, isPlaying: Bool, position: Double, duration: Double) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.playbackStatus.rawValue,
            currentId: currentId,
            items: nil,
            id: nil,
            position: position,
            playbackDuration: duration,
            isPlaying: isPlaying
        )
    }

    /// Tells the TV to configure its read-only remote albums from an account `code`.
    static func setAccount(code: String) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.setAccount.rawValue,
            accountCode: code
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
