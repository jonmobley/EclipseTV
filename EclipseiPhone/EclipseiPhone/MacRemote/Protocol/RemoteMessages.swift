//
//  RemoteMessages.swift
//  EclipseRemoteProtocol
//
//  Description: Codable wire contracts for the Eclipse LAN phone remote.
//               Used by the iOS EclipseRemote client. Kept in sync with the Mac
//               app's RemoteControlMessages.swift via the golden-JSON contract
//               check (Scripts/check_remote_protocol_contract.sh).
//  Thread Safety: Value types — no shared mutable state.
//

import Foundation

// MARK: - Remote Command

/// An action requested by a phone remote client.
///
/// Most actions map onto existing Mac global-shortcut notifications;
/// media/presentation actions carry target ids.
public enum RemoteCommandAction: String, Codable, Sendable {
    case next
    case previous
    case freeze
    case blackout
    case lock
    case screenshot
    case screensaver
    case selectMedia
    case selectLibraryMedia
    case switchPresentation
    case draw
    case drawUndo
    case drawClear
    case timerToggle
    case timerLive
    case timerPlay
    case timerReset
    case timerDuration
    case record
}

/// A single command decoded from a phone `POST /command` request.
public struct RemoteCommand: Codable, Sendable {
    public let action: RemoteCommandAction
    /// Target media item id (UUID string) for media actions; nil otherwise.
    public let mediaID: String?
    /// Target presentation id for `switchPresentation`; nil otherwise.
    public let presentationID: String?
    /// Numeric payload (e.g. `timerDuration` seconds); nil otherwise.
    public let value: Int?

    /// Creates a remote command payload.
    /// - Parameters:
    ///   - action: Command verb.
    ///   - mediaID: Optional media target.
    ///   - presentationID: Optional presentation target.
    ///   - value: Optional numeric payload.
    public init(
        action: RemoteCommandAction,
        mediaID: String? = nil,
        presentationID: String? = nil,
        value: Int? = nil
    ) {
        self.action = action
        self.mediaID = mediaID
        self.presentationID = presentationID
        self.value = value
    }
}

// MARK: - State Snapshot

/// One entry in the remote's media grid.
public struct RemoteMediaEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let type: String
    public let isLive: Bool
    /// Whether this overlay is layered over live content.
    public let isOverlayActive: Bool
    public let hasThumbnail: Bool

    /// Creates a media grid entry.
    public init(
        id: String,
        title: String,
        type: String,
        isLive: Bool,
        isOverlayActive: Bool,
        hasThumbnail: Bool
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.isLive = isLive
        self.isOverlayActive = isOverlayActive
        self.hasThumbnail = hasThumbnail
    }
}

/// One user presentation in the remote picker.
public struct RemotePresentationEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let isCurrent: Bool

    /// Creates a presentation picker entry.
    public init(id: String, name: String, isCurrent: Bool) {
        self.id = id
        self.name = name
        self.isCurrent = isCurrent
    }
}

/// Countdown timer overlay state for the remote timer panel.
public struct RemoteTimerState: Codable, Sendable {
    public let visible: Bool
    public let live: Bool
    public let running: Bool
    public let remaining: Int
    public let duration: Int
    public let label: String

    /// Creates a timer state snapshot.
    public init(
        visible: Bool,
        live: Bool,
        running: Bool,
        remaining: Int,
        duration: Int,
        label: String
    ) {
        self.visible = visible
        self.live = live
        self.running = running
        self.remaining = remaining
        self.duration = duration
        self.label = label
    }
}

/// Full state pushed to connected phones whenever anything changes.
public struct RemoteStateSnapshot: Codable, Sendable {
    public let presentationName: String
    public let currentPresentationID: String?
    public let presentations: [RemotePresentationEntry]
    public let liveMediaID: String?
    public let livePresentationID: String?
    public let livePresentationName: String?
    public let isFrozen: Bool
    public let isBlackout: Bool
    public let isLocked: Bool
    public let hasExternalDisplay: Bool
    public let isPresenting: Bool
    public let isDrawing: Bool
    public let isRecording: Bool
    /// Whether Prev/Next should show (slideshow, PDF, PowerPoint, Quest, web).
    public let showsSlideNavigation: Bool
    public let timer: RemoteTimerState
    /// Program content aspect (width ÷ height) for preview and card slots.
    ///
    /// Matches Mac Landscape / Vertical / custom show size. Defaults to 16:9
    /// when pairing with an older Mac that omits the field.
    public let programAspect: Double
    public let media: [RemoteMediaEntry]
    public let libraryMedia: [RemoteMediaEntry]

    /// Creates a full remote state snapshot.
    public init(
        presentationName: String,
        currentPresentationID: String?,
        presentations: [RemotePresentationEntry],
        liveMediaID: String?,
        livePresentationID: String?,
        livePresentationName: String?,
        isFrozen: Bool,
        isBlackout: Bool,
        isLocked: Bool,
        hasExternalDisplay: Bool,
        isPresenting: Bool,
        isDrawing: Bool,
        isRecording: Bool,
        showsSlideNavigation: Bool,
        timer: RemoteTimerState,
        programAspect: Double = 16.0 / 9.0,
        media: [RemoteMediaEntry],
        libraryMedia: [RemoteMediaEntry]
    ) {
        self.presentationName = presentationName
        self.currentPresentationID = currentPresentationID
        self.presentations = presentations
        self.liveMediaID = liveMediaID
        self.livePresentationID = livePresentationID
        self.livePresentationName = livePresentationName
        self.isFrozen = isFrozen
        self.isBlackout = isBlackout
        self.isLocked = isLocked
        self.hasExternalDisplay = hasExternalDisplay
        self.isPresenting = isPresenting
        self.isDrawing = isDrawing
        self.isRecording = isRecording
        self.showsSlideNavigation = showsSlideNavigation
        self.timer = timer
        self.programAspect = programAspect
        self.media = media
        self.libraryMedia = libraryMedia
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presentationName = try container.decode(String.self, forKey: .presentationName)
        currentPresentationID = try container.decodeIfPresent(
            String.self, forKey: .currentPresentationID
        )
        presentations = try container.decode(
            [RemotePresentationEntry].self, forKey: .presentations
        )
        liveMediaID = try container.decodeIfPresent(String.self, forKey: .liveMediaID)
        livePresentationID = try container.decodeIfPresent(
            String.self, forKey: .livePresentationID
        )
        livePresentationName = try container.decodeIfPresent(
            String.self, forKey: .livePresentationName
        )
        isFrozen = try container.decode(Bool.self, forKey: .isFrozen)
        isBlackout = try container.decode(Bool.self, forKey: .isBlackout)
        isLocked = try container.decode(Bool.self, forKey: .isLocked)
        hasExternalDisplay = try container.decode(Bool.self, forKey: .hasExternalDisplay)
        isPresenting = try container.decode(Bool.self, forKey: .isPresenting)
        isDrawing = try container.decode(Bool.self, forKey: .isDrawing)
        isRecording = try container.decode(Bool.self, forKey: .isRecording)
        showsSlideNavigation = try container.decode(Bool.self, forKey: .showsSlideNavigation)
        timer = try container.decode(RemoteTimerState.self, forKey: .timer)
        programAspect = try container.decodeIfPresent(Double.self, forKey: .programAspect)
            ?? (16.0 / 9.0)
        media = try container.decode([RemoteMediaEntry].self, forKey: .media)
        libraryMedia = try container.decode([RemoteMediaEntry].self, forKey: .libraryMedia)
    }
}
