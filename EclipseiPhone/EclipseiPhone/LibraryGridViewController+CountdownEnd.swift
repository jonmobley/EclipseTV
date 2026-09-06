//
//  LibraryGridViewController+CountdownEnd.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - End of Countdown

extension LibraryGridViewController {

    /// Runs the live countdown's end action once the clock reaches 0:00.
    func handleCountdownExpiry() {
        guard let id = CountdownController.shared.liveCountdownId else { return }
        let action = CountdownStore.shared.countdown(id: id)?.endAction ?? .fallback
        let decision = CountdownEndDecision.decide(
            action: action,
            isCountdownLive: ExternalDisplayManager.shared.isCountdownLive,
            isRemoteOperator: ShowLiveSession.shared.isRemoteOperator,
            isOutputLocked: isLiveOutputLocked,
            secondsSinceExpiry: CountdownController.shared.secondsSinceExpiry
        )
        guard decision == .run else { return }
        switch action {
        case .hold:
            break
        case .black:
            presentBlackAfterCountdown()
        case .next:
            presentNextAfterCountdown(countdownId: id)
        }
    }

    /// ⋯ submenu choosing what output does at 0:00.
    func countdownEndActionMenu(for item: ShowCountdown) -> UIMenu {
        let children: [UIMenuElement] = CountdownEndAction.allCases.map { action in
            UIAction(
                title: action.title,
                image: UIImage(systemName: action.systemImage),
                state: item.endAction == action ? .on : .off
            ) { _ in
                CountdownStore.shared.setEndAction(id: item.id, action)
            }
        }
        return UIMenu(
            title: "When It Ends",
            image: UIImage(systemName: "flag.checkered"),
            children: children
        )
    }

    /// First item after this countdown that can go live without a person.
    nonisolated static func itemAfterCountdown(
        _ id: UUID,
        in items: [ShowGridItem]
    ) -> ShowGridItem? {
        let token = ShowCountdownToken.token(for: id)
        guard let index = items.firstIndex(where: { $0.selectionId == token })
        else { return nil }
        return items.dropFirst(index + 1).first { $0.canAutoPresentLive }
    }

    // MARK: - Private

    /// Blanks output and drops the clock.
    ///
    /// Goes through `present(.black)` rather than `beginBlackout()` so no restore
    /// point is captured — toggling blackout back off should not bring a dead
    /// 0:00 clock back to the projector.
    private func presentBlackAfterCountdown() {
        SlideshowPlaybackController.shared.stop()
        ExternalDisplayManager.shared.present(.black)
        isBlackSelected = true
        isLogoSelected = false
        isScreensaverSelected = false
        announceAirPlayOverlayIfLinked()
        reloadGridIfSafe()
        refreshLiveHeader()
    }

    /// Advances to the next presentable item, or blanks when the Show ends here.
    private func presentNextAfterCountdown(countdownId: UUID) {
        guard let next = Self.itemAfterCountdown(countdownId, in: openShowGridItems)
        else {
            presentBlackAfterCountdown()
            return
        }
        presentAfterCountdown(next)
        reloadGridIfSafe()
    }

    /// Live-only routing for an auto-advance.
    ///
    /// Deliberately not `handleShowModeTap`: that opens phone Preview for media
    /// when tapped, which would leave the projector on the expired clock.
    private func presentAfterCountdown(_ item: ShowGridItem) {
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = false
        switch item {
        case .slideshow(let show):
            presentSlideshow(show)
        case .screensaver:
            presentScreensaverLive()
        case .logo:
            presentLogoLive()
        case .media(let media):
            SlideshowPlaybackController.shared.stop()
            presentMedia(media)
        case .website(let page):
            presentWebPageLive(page)
        case .pdf(let doc):
            presentPDFLive(doc)
        case .camera, .livePoll, .countdown, .unresolved, .add:
            break
        }
    }
}
