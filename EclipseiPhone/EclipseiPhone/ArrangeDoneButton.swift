//
//  ArrangeDoneButton.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Filled "Done" pill shown in the header while the grid is in arrange mode.
///
/// Mirrors the Home Screen edit-mode affordance: while tiles wiggle, Done is the
/// only control offered, and tapping it saves the order and leaves arrange mode.
final class ArrangeDoneButton: UIButton {

    /// Invoked when the user taps Done.
    var onTap: (() -> Void)?

    init() {
        super.init(frame: .zero)
        var config = UIButton.Configuration.filled()
        config.title = "Done"
        config.baseBackgroundColor = .systemBlue
        config.baseForegroundColor = .white
        config.background.cornerRadius = 18
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 7, leading: 16, bottom: 7, trailing: 16
        )
        config.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 16, weight: .semibold)
                return outgoing
            }
        configuration = config
        accessibilityLabel = "Done arranging"
        accessibilityHint = "Saves the new order"
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
