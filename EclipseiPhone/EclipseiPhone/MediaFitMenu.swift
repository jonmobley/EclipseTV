//
//  MediaFitMenu.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Shared Fit / Fill / Custom submenu for stills.
enum MediaFitMenu {

    /// Builds the Screen Fit menu for `id`.
    ///
    /// Custom is the pan/zoom cropper. Fit and Fill discard any saved position.
    static func make(
        forId id: String,
        onSelectFit: @escaping (MediaFitMode) -> Void,
        onCustom: @escaping () -> Void
    ) -> UIMenu {
        let hasCustom = MediaFramingStore.hasFraming(forId: id)
        let current = MediaFitSettings.mode(forId: id)
        // Checkmark rides in the trailing image slot rather than `state:` so the
        // selected row keeps the same title inset as the others.
        var actions: [UIMenuElement] = MediaFitMode.allCases.map { mode in
            let isCurrent = !hasCustom && mode == current
            return UIAction(
                title: mode.rawValue,
                image: UIImage(systemName: isCurrent ? "checkmark" : mode.iconName)
            ) { _ in
                onSelectFit(mode)
            }
        }
        actions.append(UIAction(
            title: "Custom",
            image: UIImage(systemName: hasCustom ? "checkmark" : "crop")
        ) { _ in
            onCustom()
        })
        return UIMenu(
            title: "Screen Fit",
            image: UIImage(systemName: "aspectratio"),
            children: actions
        )
    }
}
