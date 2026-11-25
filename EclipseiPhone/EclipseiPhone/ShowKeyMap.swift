//
//  ShowKeyMap.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - Show keyboard actions

/// What a hardware key (or presentation clicker) does while a Show is open.
enum ShowKeyAction: Equatable {
    case nextCard
    case previousCard
    case toggleBlackout
    case toggleLock
    case leaveBlackout
}

/// Where the key press lands, so the mapping can stay out of the way.
struct ShowKeyContext: Equatable {
    /// A Show (not Home) is open on the grid.
    var isShowOpen: Bool
    /// A text field, sheet, or the Prompter owns the keyboard.
    var isKeyboardOwnedElsewhere: Bool
    /// Blackout is holding the audience screen.
    var isBlackoutHolding: Bool
}

/// Pure key → action table, matching the Mac's presentation-clicker keys.
///
/// Thread safety: value-only, no shared state.
enum ShowKeyMap {

    /// One key the Show screen listens for.
    struct Binding: Equatable {
        let input: String
        let action: ShowKeyAction
        /// Name shown in the iPad ⌘-hold shortcut overlay.
        let title: String
    }

    /// Arrow / Page key names as UIKit spells them (`UIKeyCommand.input…`).
    static let rightArrow = "UIKeyInputRightArrow"
    static let leftArrow = "UIKeyInputLeftArrow"
    static let upArrow = "UIKeyInputUpArrow"
    static let downArrow = "UIKeyInputDownArrow"
    static let pageUp = "UIKeyInputPageUp"
    static let pageDown = "UIKeyInputPageDown"
    static let escape = "UIKeyInputEscape"

    /// Every binding, in the order the shortcut overlay lists them.
    static let allBindings: [Binding] = [
        Binding(input: rightArrow, action: .nextCard, title: "Next Card"),
        Binding(input: downArrow, action: .nextCard, title: "Next Card"),
        Binding(input: pageDown, action: .nextCard, title: "Next Card"),
        Binding(input: " ", action: .nextCard, title: "Next Card"),
        Binding(input: leftArrow, action: .previousCard, title: "Previous Card"),
        Binding(input: upArrow, action: .previousCard, title: "Previous Card"),
        Binding(input: pageUp, action: .previousCard, title: "Previous Card"),
        Binding(input: "b", action: .toggleBlackout, title: "Blackout"),
        Binding(input: ".", action: .toggleBlackout, title: "Blackout"),
        Binding(input: "l", action: .toggleLock, title: "Lock Live Output"),
        Binding(input: escape, action: .leaveBlackout, title: "Leave Blackout")
    ]

    /// Bindings that should be active right now; empty when another owner has the keyboard.
    static func activeBindings(in context: ShowKeyContext) -> [Binding] {
        guard context.isShowOpen, !context.isKeyboardOwnedElsewhere else { return [] }
        return allBindings.filter { binding in
            // Escape keeps dismissing things everywhere except while Blackout holds.
            binding.action != .leaveBlackout || context.isBlackoutHolding
        }
    }

    /// The action for a plain (no modifier) key press, nil when the key is not ours.
    static func action(forInput input: String, in context: ShowKeyContext) -> ShowKeyAction? {
        let key = input.lowercased()
        return activeBindings(in: context).first { $0.input == key }?.action
    }
}
