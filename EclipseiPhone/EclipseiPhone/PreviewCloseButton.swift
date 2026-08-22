//
//  PreviewCloseButton.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension UIButton {

    /// White disk, black X, and a light shadow so Close stays visible on any photo.
    ///
    /// Do not use `xmark.circle.fill` with `.alwaysOriginal`: that symbol’s default
    /// multicolor is a red badge, which reads as delete or an error.
    func applyPreviewCloseAppearance() {
        var config = UIButton.Configuration.filled()
        let symbol = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        config.image = UIImage(systemName: "xmark", withConfiguration: symbol)
        config.baseForegroundColor = .black
        config.baseBackgroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 9, leading: 9, bottom: 9, trailing: 9
        )
        configuration = config
        tintColor = nil
        accessibilityLabel = "Close"
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 3
        layer.shadowOffset = .zero
    }
}
