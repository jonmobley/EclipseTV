//
//  CameraTileMoreButton.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// The ⋯ pill on Show-sized camera tiles (frames, quick-change stills), styled like
/// Camera Frames' ⋯. Press-and-hold on a tile still opens the same actions.
enum CameraTileMoreButton {

    private static let visualSide: CGFloat = 28
    private static let hitSide: CGFloat = 44

    /// Adds a hidden ⋯ to the top-right corner of `container`; show it with a menu.
    static func install(in container: UIView) -> ScrollSafeMenuButton {
        let button = ScrollSafeMenuButton(type: .system)
        let inset = (hitSide - visualSide) / 2
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        )
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        config.background.cornerRadius = visualSide / 2
        config.background.backgroundInsets = NSDirectionalEdgeInsets(
            top: inset, leading: inset, bottom: inset, trailing: inset
        )
        config.contentInsets = NSDirectionalEdgeInsets(
            top: inset, leading: inset, bottom: inset, trailing: inset
        )
        button.configuration = config
        button.accessibilityLabel = "More"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(
                equalTo: container.trailingAnchor, constant: -8 + inset
            ),
            button.topAnchor.constraint(equalTo: container.topAnchor, constant: 8 - inset),
            button.widthAnchor.constraint(equalToConstant: hitSide),
            button.heightAnchor.constraint(equalToConstant: hitSide)
        ])
        return button
    }

    /// Shows ⋯ with `menu`, or hides it for `nil` (small in-panel ribbon thumbs).
    static func set(_ menu: UIMenu?, on button: ScrollSafeMenuButton) {
        button.menu = menu
        button.isHidden = menu == nil
        button.superview?.bringSubviewToFront(button)
    }
}
