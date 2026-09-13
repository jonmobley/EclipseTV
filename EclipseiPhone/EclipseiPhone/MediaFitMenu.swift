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
    ///
    /// - Parameter offersFitFill: False for a still already shaped like the display
    ///   panel, where the two rows are the same picture (see `MediaFitAvailability`).
    ///   Custom survives: on a matching still the cropper can no longer letterbox,
    ///   but it still punches in and pans, so Reset takes over the job of getting
    ///   back to the whole photo.
    static func make(
        forId id: String,
        offersFitFill: Bool,
        onSelectFit: @escaping (MediaFitMode) -> Void,
        onCustom: @escaping () -> Void
    ) -> UIMenu {
        let hasCustom = MediaFramingStore.hasFraming(forId: id)
        let current = MediaFitSettings.mode(forId: id)
        var actions: [UIMenuElement] = []
        if offersFitFill {
            // Checkmark rides in the trailing image slot rather than `state:` so the
            // selected row keeps the same title inset as the others.
            actions = MediaFitMode.allCases.map { mode in
                let isCurrent = !hasCustom && mode == current
                return UIAction(
                    title: mode.rawValue,
                    image: UIImage(systemName: isCurrent ? "checkmark" : mode.iconName)
                ) { _ in
                    onSelectFit(mode)
                }
            }
        }
        actions.append(UIAction(
            title: "Custom",
            image: UIImage(systemName: hasCustom ? "checkmark" : "crop")
        ) { _ in
            onCustom()
        })
        if !offersFitFill, hasCustom {
            actions.append(UIAction(
                title: "Reset",
                image: UIImage(systemName: "arrow.uturn.backward")
            ) { _ in
                // Fit clears the saved position, and on a matching still landing on
                // Fit is landing on the whole photo.
                onSelectFit(.fit)
            })
        }
        return UIMenu(
            title: "Screen Fit",
            image: UIImage(systemName: "aspectratio"),
            children: actions
        )
    }
}
