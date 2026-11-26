//
//  OverlayCardTemplateKind+Layout.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Layout routing and preferred corner defaults for card template
//               kinds. Keeps OverlayCard.swift focused on model + registry.
//  Thread Safety: Value types - no shared mutable state.
//

import Foundation

// MARK: - Layout Flags

extension OverlayCardTemplateKind {

    /// Sports scoreboards use a dedicated layout and editor (not icon+title).
    var usesScoreboardLayout: Bool {
        switch self {
        case .scoreboardVersus, .scoreboardMatch, .scoreboardPlayers,
             .scoreboardClock, .scoreboardSeries:
            return true
        default:
            return false
        }
    }

    /// Broadcast lower thirds use dedicated nameplate layouts (not icon+title).
    var usesLowerThirdLayout: Bool {
        switch self {
        case .lowerThird, .lowerThirdBanner, .lowerThirdGlass,
             .lowerThirdSpeaker, .lowerThirdTopic:
            return true
        default:
            return false
        }
    }

    /// Scripture uses a dedicated verse-plate layout (not icon+title).
    var usesScriptureLayout: Bool {
        self == .scripture
    }

    /// Poll / question prompts use a dedicated stacked-options layout.
    var usesPollLayout: Bool {
        self == .pollPrompt
    }

    /// Viewer chat questions use a dedicated speech-bubble layout.
    var usesChatLayout: Bool {
        self == .chatQuestion
    }

    /// Sponsor end-cards use a dedicated centered plate layout.
    var usesSponsorLayout: Bool {
        self == .sponsorEndcard
    }

    /// Standard-layout templates whose `title` is a fixed or short label (time,
    /// chapter, "Up Next") render that label as a small eyebrow and promote the
    /// subtitle to the big line, so the content is always louder than its label.
    var showsTitleAsEyebrow: Bool {
        switch self {
        case .upNext, .nowPlaying, .chapterMarker, .agendaItem:
            return true
        default:
            return false
        }
    }

    /// Whether this template has string fields editable in Edit Template.
    ///
    /// Preview no longer mounts a live Name/Role-style bar for these — that
    /// chrome covered short lower thirds and blocked move / resize. Scoreboards
    /// put − / + on the card (`ScoreboardInlineScoreControls`); Match/Clock keep
    /// a slim period/clock bar. QR uses `QRCodeLiveControlsBar`.
    var supportsLiveFieldEditing: Bool {
        !usesScoreboardLayout
    }

    /// Corner used for picker samples and new-card authoring defaults.
    var preferredCorner: OverlayCorner {
        if usesLowerThirdLayout || usesScriptureLayout {
            return .bottomLeading
        }
        if self == .chapterMarker || self == .scoreboardClock
            || self == .scoreboardSeries {
            return .topLeading
        }
        return .topTrailing
    }
}
