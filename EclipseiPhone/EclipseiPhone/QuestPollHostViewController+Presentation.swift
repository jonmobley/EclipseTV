//
//  QuestPollHostViewController+Presentation.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
import UIKit

extension QuestPollHostViewController {

    /// Navigation wrapper presented as a sheet that leaves the live chrome alone.
    ///
    /// The room's projector preview and cue ribbon are the Show screen's own live
    /// header and docked ribbon, so CONTROLS rests at the medium detent with that
    /// detent left undimmed: the host keeps watching the poll and can still cue
    /// from the ribbon without closing this sheet.
    ///
    /// Copies of the preview cannot live in here — a warm page owns a single
    /// `WKWebView`, so a second preview would pull it out of the hero.
    ///
    /// - Parameters:
    ///   - onAdvance: Host control command to send.
    ///   - onEnd: Runs after the sheet dismisses, so End can confirm from the Show.
    static func makeNavigation(
        onAdvance: ((LivePollHostCommand) -> Void)?,
        onEnd: (() -> Void)?
    ) -> UINavigationController {
        let host = QuestPollHostViewController()
        host.onAdvance = onAdvance
        let nav = UINavigationController(rootViewController: host)
        host.onEnd = { [weak nav] in
            nav?.dismiss(animated: true, completion: onEnd)
        }
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            // Undimmed is what makes the preview *usable* rather than merely
            // visible: it keeps hero and ribbon taps reaching the Show screen.
            sheet.largestUndimmedDetentIdentifier = .medium
            // Controls scroll inside the sheet. Left to expand, reaching the
            // scroll edge would snap it to large and swallow the preview.
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.prefersGrabberVisible = true
            // Landscape puts the hero in the leading column; an edge-attached
            // card keeps it in view instead of covering the whole height.
            sheet.prefersEdgeAttachedInCompactHeight = true
        }
        return nav
    }
}
