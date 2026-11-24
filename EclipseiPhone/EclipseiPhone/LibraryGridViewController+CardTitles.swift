//
//  LibraryGridViewController+CardTitles.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Show Card Titles

extension LibraryGridViewController {

    /// Whether `item`'s tile hides its title under the open Show's Card Titles
    /// setting. Screensaver and Background always keep theirs (same as the
    /// Mac), and so do the + tile and "Syncing…".
    func hidesCardTitle(_ item: ShowGridItem) -> Bool {
        guard openShow?.cardTitlesShown == false else { return false }
        switch item {
        case .screensaver, .logo, .add, .unresolved:
            return false
        default:
            return true
        }
    }
}
