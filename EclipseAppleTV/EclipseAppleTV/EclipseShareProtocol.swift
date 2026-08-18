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
    /// Resource-name prefix that stamps Landscape / Vertical onto Multipeer media sends
    /// (`eclmode_<mode>_<fileName>`). Keeps mode atomic with the file so a mid-transfer
    /// display-mode switch cannot mis-bucket the receive.
    static let mediaModeResourcePrefix = "eclmode_"

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
        /// Companion switches the TV's active Landscape / Vertical library bucket.
        case setDisplayMode = "set_display_mode"
        /// Companion sets Cut vs Crossfade for TV content switches.
        case setContentTransition = "set_content_transition"
        /// Companion sets whether a still fills (crops to) the TV screen or letterboxes.
        case setImageFit = "set_image_fit"
        /// Companion pushes Show groupings; the TV presents them as albums.
        case setLibraryAlbums = "set_library_albums"
    }

    /// Separate media libraries: Landscape (16:9) vs Vertical (9:16).
    enum LibraryMode: String, Codable, CaseIterable {
        case landscape
        case vertical

        /// On-disk subdirectory under `Caches/Media` / `LocalMedia`.
        var directoryName: String {
            switch self {
            case .landscape: return "Landscape"
            case .vertical: return "Vertical"
            }
        }

        static func resolved(from raw: String?) -> LibraryMode {
            guard let raw, let mode = LibraryMode(rawValue: raw) else { return .landscape }
            return mode
        }
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

    /// Wire name for a media (or `thumbnail_…`) Multipeer resource, stamped with `mode`.
    static func mediaResourceName(for fileName: String, mode: LibraryMode) -> String {
        mediaModeResourcePrefix + mode.rawValue + "_" + fileName
    }

    /// Parses a Multipeer media resource name into the on-disk file name and optional mode.
    /// Unprefixed legacy names return `mode == nil` (caller falls back to active library).
    static func parseMediaResourceName(_ resourceName: String) -> (fileName: String, mode: LibraryMode?) {
        guard resourceName.hasPrefix(mediaModeResourcePrefix) else {
            return (resourceName, nil)
        }
        let rest = String(resourceName.dropFirst(mediaModeResourcePrefix.count))
        for mode in LibraryMode.allCases {
            let token = mode.rawValue + "_"
            if rest.hasPrefix(token) {
                let fileName = String(rest.dropFirst(token.count))
                guard !fileName.isEmpty else { return (resourceName, nil) }
                return (fileName, mode)
            }
        }
        return (resourceName, nil)
    }

    /// Infers library mode from an on-disk media path under `…/Landscape/` or `…/Vertical/`.
    static func libraryMode(inferredFromPath path: String) -> LibraryMode {
        if path.contains("/\(LibraryMode.vertical.directoryName)/") { return .vertical }
        return .landscape
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

/// A phone Show as the TV should group it (named "album" in the TV UI).
///
/// `itemIds` are TV library file names only — tools, captures, websites, and PDFs
/// are stripped before send. Empty albums are omitted by the companion.
struct LibraryAlbumDTO: Codable, Equatable {
    let id: String
    let name: String
    var itemIds: [String]
    var coverId: String?
    /// `"landscape"` / `"vertical"` — which library bucket this album belongs to.
    var libraryMode: String?

    /// Resolved cover, falling back to the first member.
    var resolvedCoverId: String? {
        if let coverId, itemIds.contains(coverId) { return coverId }
        return itemIds.first
    }
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
    /// Fit / Fill framing for a still. `true` fills (and crops to) the screen, `false`
    /// letterboxes it. Carried on `playRequest` so the TV frames the first show
    /// correctly, and on `setImageFit` when the choice changes while an item is live.
    var isFill: Bool? = nil
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
    /// `"landscape"` / `"vertical"` — which library bucket this message applies to.
    /// Optional for backward compatibility with older peers.
    var libraryMode: String? = nil
    /// `"Cut"` / `"Crossfade"` — content switch style for the TV app.
    var contentTransition: String? = nil
    /// Show groupings for `setLibraryAlbums` (phone → TV).
    var albums: [LibraryAlbumDTO]? = nil

    var kind: EclipseShareProtocol.Kind? {
        EclipseShareProtocol.Kind(rawValue: eclipseMsg)
    }

    var resolvedLibraryMode: EclipseShareProtocol.LibraryMode {
        EclipseShareProtocol.LibraryMode.resolved(from: libraryMode)
    }

    /// Returns a copy stamped with `mode` for outbound sends.
    func withLibraryMode(_ mode: EclipseShareProtocol.LibraryMode) -> EclipseShareEnvelope {
        var copy = self
        copy.libraryMode = mode.rawValue
        return copy
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

    /// Makes an item live on the TV.
    /// - Parameter isFill: Fit / Fill framing for a still, so the TV matches the phone on
    ///   the first show. Nil leaves the TV's stored choice untouched.
    /// - Parameter startAt: Absolute seconds to seek when the item is a video (nil / 0 =
    ///   from the start). Carried in `position` for wire compatibility.
    static func playRequest(
        id: String,
        isFill: Bool? = nil,
        startAt: Double? = nil
    ) -> EclipseShareEnvelope {
        let seek = (startAt ?? 0) > 0 ? startAt : nil
        return EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.playRequest.rawValue,
            currentId: nil,
            items: nil,
            id: id,
            isFill: isFill,
            position: seek
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

    /// Sets whether a still fills (crops to) the TV screen instead of letterboxing.
    static func setImageFit(id: String, isFill: Bool) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.setImageFit.rawValue,
            currentId: nil,
            items: nil,
            id: id,
            isFill: isFill
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

    /// Tells the TV to switch its active Landscape / Vertical library.
    static func setDisplayMode(_ mode: EclipseShareProtocol.LibraryMode) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.setDisplayMode.rawValue,
            libraryMode: mode.rawValue
        )
    }

    /// Tells the TV to use Cut or Crossfade when switching content.
    static func setContentTransition(_ style: String) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.setContentTransition.rawValue,
            contentTransition: style
        )
    }

    /// Pushes the companion's Show groupings so the TV can present them as albums.
    static func setLibraryAlbums(_ albums: [LibraryAlbumDTO]) -> EclipseShareEnvelope {
        EclipseShareEnvelope(
            eclipseMsg: EclipseShareProtocol.Kind.setLibraryAlbums.rawValue,
            albums: albums
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
