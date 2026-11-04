//
//  WebRemoteViewController+OrientationCover.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Whether the browser's view has the shape its Display Mode layout is drawn for.
///
/// The browser opens from a portrait grid and then asks the scene to turn. Until
/// that turn lands, a Landscape stage would lay its 16:9 card and trailing
/// Back / ⋯ / Close column out across a portrait screen for a moment.
enum BrowserOrientationFit {

    /// False while a phone view is still the wrong shape for the Display Mode.
    ///
    /// iPad keeps whatever orientation it is in, so it is never covered.
    static func matches(
        bounds: CGSize,
        isVertical: Bool,
        idiom: UIUserInterfaceIdiom
    ) -> Bool {
        guard idiom == .phone else { return true }
        guard bounds.width > 0, bounds.height > 0 else { return false }
        return isVertical ? bounds.height >= bounds.width : bounds.width >= bounds.height
    }
}

extension WebRemoteViewController {

    /// Keeps the page and its chrome hidden over plain black until the view has
    /// turned to the Display Mode orientation, then fades them in.
    ///
    /// Called from every viewport layout, so it follows the rotation without a
    /// separate observer.
    func updateOrientationCover() {
        let fits = BrowserOrientationFit.matches(
            bounds: view.bounds.size,
            isVertical: ExternalOutputSettings.isVerticalMode,
            idiom: traitCollection.userInterfaceIdiom
        )
        let covered: [UIView?] = [webStageView] + allOverlayChromeButtons
        let target: CGFloat = fits ? 1 : 0
        guard covered.contains(where: { $0 != nil && $0?.alpha != target }) else { return }
        let apply = { covered.forEach { $0?.alpha = target } }
        if fits, view.window != nil {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: apply
            )
        } else {
            apply()
        }
    }
}
