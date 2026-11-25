//
//  LibraryGridViewController+KeyCommands.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Hardware keyboard and presentation clicker

/// Keys for running a Show from a hardware keyboard or a presentation clicker
/// (clickers send Page Up / Page Down and arrows). Mirrors the Mac's clicker
/// mapping in `ShowKeyMap`; each action calls the same handler a tap would.
extension LibraryGridViewController {

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        var listed = Set<String>()
        return ShowKeyMap.activeBindings(in: showKeyContext).map { binding in
            let command = UIKeyCommand(
                action: #selector(handleShowKeyCommand(_:)), input: binding.input
            )
            // Arrows and Space would otherwise scroll the grid.
            command.wantsPriorityOverSystemBehavior = true
            // Only the first key per action appears in the ⌘-hold overlay.
            if listed.insert(binding.title).inserted {
                command.discoverabilityTitle = binding.title
            }
            return command
        }
    }

    /// Who owns the keyboard right now.
    var showKeyContext: ShowKeyContext {
        ShowKeyContext(
            isShowOpen: isShowMode,
            isKeyboardOwnedElsewhere: presentedViewController != nil
                || view.window.map(Self.hasTextResponder) ?? false,
            isBlackoutHolding: isBlackoutHolding
        )
    }

    /// Runs the action for the pressed key.
    @objc func handleShowKeyCommand(_ command: UIKeyCommand) {
        guard let input = command.input,
              let action = ShowKeyMap.action(forInput: input, in: showKeyContext) else { return }
        perform(showKeyAction: action)
    }

    /// Sends a key action through the same paths as the on-screen controls.
    func perform(showKeyAction action: ShowKeyAction) {
        switch action {
        case .nextCard: stepLiveCard(delta: 1)
        case .previousCard: stepLiveCard(delta: -1)
        case .toggleBlackout: toggleBlackLive()
        case .toggleLock: toggleLiveOutputLock()
        case .leaveBlackout:
            if isBlackSelected { toggleBlackLive() }
        }
    }

    /// Next / previous: a live slideshow's slide, else the Show's next still.
    private func stepLiveCard(delta: Int) {
        if activeLiveSlideshow() != nil {
            SlideshowPlaybackController.shared.goToAdjacentSlide(delta: delta)
            Haptics.impactLight()
        } else {
            browseLiveHero(delta: delta)
        }
    }

    /// True when any view under `root` is a first-responder text input.
    private static func hasTextResponder(in root: UIView) -> Bool {
        if root.isFirstResponder, root is UITextInput { return true }
        return root.subviews.contains { hasTextResponder(in: $0) }
    }
}
