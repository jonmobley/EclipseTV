//
//  UndoToastCenter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// The Undo currently on offer in a toast, so ⌘Z on an iPad keyboard can run it.
///
/// Only the latest Undo toast counts, and only while it is up: ⌘Z never reaches
/// back to an older action the screen no longer mentions. Main actor only.
@MainActor
final class UndoToastCenter {

    // MARK: - Properties

    static let shared = UndoToastCenter()

    private var token: UUID?
    private var action: (() -> Void)?

    // MARK: - Public Interface

    /// Whether ⌘Z has something to undo right now.
    var canUndo: Bool { action != nil }

    /// Offers `undo` until `clear(token:)` is called with the same token.
    func register(token: UUID, undo: @escaping () -> Void) {
        self.token = token
        action = undo
    }

    /// Withdraws the offer if `token` is still the current one.
    func clear(token: UUID) {
        guard self.token == token else { return }
        self.token = nil
        action = nil
    }

    /// Runs the offered Undo once.
    /// - Returns: false when nothing was on offer.
    @discardableResult
    func performUndo() -> Bool {
        guard let action else { return false }
        token = nil
        self.action = nil
        action()
        return true
    }
}

// MARK: - Keyboard

extension UndoToastCenter {

    /// ⌘Z for the Undo toast, or nil when no toast offers one.
    ///
    /// Served from `AppDelegate.keyCommands`, the end of every responder chain,
    /// so it works whatever has focus; a text field's own ⌘Z still comes first.
    var keyCommand: UIKeyCommand? {
        guard canUndo else { return nil }
        let command = UIKeyCommand(
            title: "Undo",
            action: #selector(UIResponder.performUndoToastCommand),
            input: "z",
            modifierFlags: .command
        )
        command.discoverabilityTitle = "Undo"
        return command
    }
}

extension UIResponder {

    /// Target of the ⌘Z key command; runs the Undo toast's action.
    @objc func performUndoToastCommand() {
        UndoToastCenter.shared.performUndo()
    }
}
