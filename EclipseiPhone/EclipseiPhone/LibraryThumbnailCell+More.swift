//
//  LibraryThumbnailCell+More.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - More Menu (ellipsis)

extension LibraryThumbnailCell {

    /// Visual size of the ⋯ pill.
    static let moreButtonVisualSide: CGFloat = 28
    /// Generous tap target so ⋯ is easy without grazing the tile (go-live).
    static let moreButtonHitSide: CGFloat = 44

    /// Installs the trailing ellipsis control used by Show media / tool tiles.
    func installMoreButton() {
        let inset = (Self.moreButtonHitSide - Self.moreButtonVisualSide) / 2
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        )
        config.baseForegroundColor = .white
        // 28pt pill painted inside a 44×44 hit target.
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        config.background.cornerRadius = Self.moreButtonVisualSide / 2
        config.background.backgroundInsets = NSDirectionalEdgeInsets(
            top: inset, leading: inset, bottom: inset, trailing: inset
        )
        config.contentInsets = NSDirectionalEdgeInsets(
            top: inset, leading: inset, bottom: inset, trailing: inset
        )
        moreButton.configuration = config
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.accessibilityLabel = "More"
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.isHidden = true
        cardView.addSubview(moreButton)
        // Visual pill stays at the old 8pt inset; hit area grows inward.
        NSLayoutConstraint.activate([
            moreButton.trailingAnchor.constraint(
                equalTo: cardView.trailingAnchor, constant: -8 + inset
            ),
            moreButton.topAnchor.constraint(
                equalTo: cardView.topAnchor, constant: 8 - inset
            ),
            moreButton.widthAnchor.constraint(equalToConstant: Self.moreButtonHitSide),
            moreButton.heightAnchor.constraint(equalToConstant: Self.moreButtonHitSide)
        ])
    }

    /// Shows the ellipsis with `menu`, or hides it when `menu` is nil.
    func setMoreMenu(_ menu: UIMenu?) {
        moreButton.menu = menu
        moreButton.isHidden = menu == nil
        // Camera preview / caption chrome may have buried this under `imageView`.
        if menu != nil {
            cardView.bringSubviewToFront(moreButton)
        }
    }

    /// Clears the ellipsis (called from `resetChrome`).
    func clearMoreMenu() {
        moreButton.menu = nil
        moreButton.isHidden = true
    }
}
