//
//  LiveHeroBackdropView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Portrait live preview occludes the grid from the page top through the card.
enum LiveHeroBackdrop {
    /// Shown only for the stacked (portrait) live hero — landscape already
    /// puts the grid in a separate column.
    static func isVisible(showsLiveHero: Bool, isSideBySideChrome: Bool) -> Bool {
        showsLiveHero && !isSideBySideChrome
    }

    /// Soft edge under the plate so tiles read as passing beneath the preview.
    static let shadowOpacity: Float = 0.5
    static let shadowRadius: CGFloat = 10
    static let shadowYOffset: CGFloat = 4
}

/// Black plate behind the portrait live card. Runs from the page top past the
/// hero (and docked ribbon) so tiles scrolling under the preview disappear behind
/// a band of black, with a drop shadow along the bottom edge.
final class LiveHeroBackdropView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = LiveHeroBackdrop.shadowOpacity
        layer.shadowRadius = LiveHeroBackdrop.shadowRadius
        layer.shadowOffset = CGSize(width: 0, height: LiveHeroBackdrop.shadowYOffset)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Explicit path keeps the shadow cheap while the grid scrolls beneath it.
        layer.shadowPath = bounds.isEmpty ? nil : UIBezierPath(rect: bounds).cgPath
    }
}
