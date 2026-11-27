//
//  ImageViewController+IdleScreen.swift
//  EclipseTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Calm Idle Screen

/// Shows the Eclipse loop with a short hint while the TV waits for the phone.
///
/// Comes up at launch and when the phone disconnects, as long as the TV is on its
/// library grid and `IdleScreenRules.shouldShow` agrees (never over the pairing
/// screen, a menu, Move or the phone's black park). Anything the phone puts on
/// screen takes it away. Select / Play-Pause opens the library grid; Menu there
/// comes back here; holding Select opens Options.
/// Thread Safety: Main thread only (UIKit).
extension ImageViewController {

    // MARK: - Public Interface

    /// Whether the idle screen is up.
    var isIdleScreenShowing: Bool {
        idleScreenView.superview != nil
    }

    /// The TV's state as the idle rules see it.
    var idleScreenContext: IdleScreenContext {
        IdleScreenContext(
            isInGridMode: isInGridMode,
            isShowingPairingScreen: emptyStateView.superview != nil,
            hasPairedPhone: !PairedPeerStore.shared.allPairedNames().isEmpty,
            isMoveMode: isMoveMode,
            isMenuOpen: presentedViewController != nil,
            isParked: isIdleParked,
            isBrowsingLibrary: isBrowsingLibraryFromIdle
        )
    }

    /// Shows the idle screen when the rules allow it.
    func showIdleScreenIfReady() {
        guard !isIdleScreenShowing, IdleScreenRules.shouldShow(idleScreenContext) else { return }
        wireIdleScreenIfNeeded()
        idleScreenView.translatesAutoresizingMaskIntoConstraints = false
        idleScreenView.alpha = 0
        view.addSubview(idleScreenView)
        NSLayoutConstraint.activate([
            idleScreenView.topAnchor.constraint(equalTo: view.topAnchor),
            idleScreenView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            idleScreenView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            idleScreenView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.bringSubviewToFront(toastView)
        setLibraryFocusable(false)
        idleScreenView.start()
        UIView.animate(withDuration: IdleScreenRules.hintFadeSeconds) {
            self.idleScreenView.alpha = 1
        }
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    /// Takes the idle screen away (something is about to be shown).
    func hideIdleScreen() {
        guard isIdleScreenShowing else { return }
        idleScreenView.stop()
        idleScreenView.removeFromSuperview()
        setLibraryFocusable(true)
        setNeedsFocusUpdate()
    }

    /// Phone disconnected: a fresh wait starts, so idle may come back.
    func idleScreenPhoneDidDisconnect() {
        isBrowsingLibraryFromIdle = false
        showIdleScreenIfReady()
    }

    /// Menu at the root grid after browsing from idle goes back to idle.
    /// - Returns: `true` when the press was used.
    @discardableResult
    func returnToIdleScreenFromLibrary() -> Bool {
        guard canReturnToIdleScreen else { return false }
        isBrowsingLibraryFromIdle = false
        showIdleScreenIfReady()
        return isIdleScreenShowing
    }

    /// Whether Menu on the root grid should come back to the idle screen.
    var canReturnToIdleScreen: Bool {
        guard isBrowsingLibraryFromIdle, !isIdleScreenShowing else { return false }
        var context = idleScreenContext
        context.isBrowsingLibrary = false
        return IdleScreenRules.shouldShow(context)
    }

    // MARK: - Private Helpers

    private func wireIdleScreenIfNeeded() {
        guard idleScreenView.onPress == nil else { return }
        idleScreenView.onPress = { [weak self] press in
            self?.handleIdleScreenPress(press)
        }
        idleScreenView.onLongSelect = { [weak self] in
            // Options can open Help, which lives under the idle screen.
            self?.handleIdleScreenPress(.select)
            self?.showOptionsMenu()
        }
    }

    private func handleIdleScreenPress(_ press: IdleScreenRules.Press) {
        switch IdleScreenRules.action(for: press) {
        case .showHint:
            idleScreenView.showHint()
        case .browseLibrary:
            isBrowsingLibraryFromIdle = true
            hideIdleScreen()
            updateOptionsButtonVisibility()
            updateFocusIfNeeded()
        case .passThrough:
            break
        }
    }

    /// Library tiles and the Options button can't take focus under the idle screen.
    private func setLibraryFocusable(_ focusable: Bool) {
        gridView.isUserInteractionEnabled = focusable
        optionsButton.isUserInteractionEnabled = focusable
    }
}
