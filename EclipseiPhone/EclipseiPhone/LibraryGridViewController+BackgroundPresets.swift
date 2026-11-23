//
//  LibraryGridViewController+BackgroundPresets.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension LibraryGridViewController {

    /// The Mac's eight Background colors as a row of chips for the Background
    /// tile's ⋯ menu. The chosen one is marked; picking one replaces the picture.
    func backgroundColorPresetMenu() -> UIMenu {
        let selected = LogoStore.shared.selectedPreset
        let actions = BackgroundColorPreset.allCases.map { preset in
            UIAction(
                title: preset.title,
                image: preset.swatch(),
                state: preset == selected ? .on : .off
            ) { _ in
                LogoStore.shared.apply(preset)
            }
        }
        return UIMenu(
            title: "Color",
            options: [.displayInline, .displayAsPalette],
            children: actions
        )
    }
}
