//
//  VideoEndAction.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - VideoEndAction

/// What output does when a video finishes playing (the Mac's "When Video Ends").
///
/// Stored per video on this phone only (`LibraryItemDTO.videoEndAction`). Loop is
/// also mirrored into the existing `isLooping` flag, which is what iCloud sync and
/// the Apple TV understand, so `isLooping == true` always wins when the two disagree.
///
/// Thread safety: value type, safe anywhere.
enum VideoEndAction: String, CaseIterable, Equatable {
    /// Hold on the last frame (what a video without Loop always did).
    case pause
    /// Restart from the beginning.
    case loop
    /// Go live with the next item in the Show.
    case next
    /// Switch output to the Show's Screensaver.
    case screensaver

    /// Menu title and the words the Mac uses.
    var title: String {
        switch self {
        case .pause: return "Pause"
        case .loop: return "Loop"
        case .next: return "Next"
        case .screensaver: return "Screensaver"
        }
    }

    /// Menu glyph.
    var systemImage: String {
        switch self {
        case .pause: return "pause.fill"
        case .loop: return "repeat"
        case .next: return "forward.end.fill"
        case .screensaver: return "photo.fill"
        }
    }

    /// Title of the submenu that holds the four choices.
    static let menuTitle = "When Video Ends"

    /// The choice that applies to a video, from its two stored flags.
    ///
    /// - Parameters:
    ///   - isLooping: The synced Loop flag (nil = never set = off).
    ///   - stored: The phone-only choice, if any. Unreadable values count as unset.
    static func resolve(isLooping: Bool?, stored: String?) -> VideoEndAction {
        if isLooping == true { return .loop }
        guard let stored, let action = VideoEndAction(rawValue: stored), action != .loop
        else { return .pause }
        return action
    }
}

// MARK: - LibraryItemDTO

extension LibraryItemDTO {
    /// What happens when this video ends.
    var videoEndAction: VideoEndAction {
        VideoEndAction.resolve(isLooping: isLooping, stored: endAction)
    }
}

// MARK: - Menus

extension VideoEndAction {

    /// "When Video Ends" submenu with the current choice ticked.
    static func menu(
        current: VideoEndAction,
        onSelect: @escaping (VideoEndAction) -> Void
    ) -> UIMenu {
        let children: [UIMenuElement] = allCases.map { action in
            UIAction(
                title: action.title,
                image: UIImage(systemName: action.systemImage),
                state: action == current ? .on : .off
            ) { _ in onSelect(action) }
        }
        return UIMenu(
            title: menuTitle,
            image: UIImage(systemName: "flag.checkered"),
            children: children
        )
    }

    /// Action sheet with the four choices, for the older options sheet.
    static func sheet(
        current: VideoEndAction,
        onSelect: @escaping (VideoEndAction) -> Void
    ) -> UIAlertController {
        let sheet = UIAlertController(title: menuTitle, message: nil, preferredStyle: .actionSheet)
        for action in allCases {
            sheet.addAction(UIAlertAction(
                title: action == current ? "\(action.title) ✓" : action.title,
                style: .default
            ) { _ in onSelect(action) })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        return sheet
    }
}
