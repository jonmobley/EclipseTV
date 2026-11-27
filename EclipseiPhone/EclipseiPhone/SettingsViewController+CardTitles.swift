//
//  SettingsViewController+CardTitles.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Card Titles (per Show)

extension SettingsViewController {

    /// Footer under the per-Show Card Titles toggle.
    static let cardTitlesFooter =
        "Show each card's name on its thumbnail, for every card in this show. "
        + "Syncs with Eclipse for Mac."

    /// Toggle: every card in the open Show draws its name over the thumbnail.
    func configureCardTitlesCell(
        _ cell: UITableViewCell,
        config: inout UIListContentConfiguration
    ) {
        cell.accessoryType = .none
        cell.selectionStyle = .none
        config.text = "Card Titles"
        config.image = UIImage(systemName: "textformat")
        config.secondaryText = nil

        let toggle = UISwitch()
        toggle.isOn = currentCardTitlesShown
        toggle.addTarget(self, action: #selector(cardTitlesChanged(_:)), for: .valueChanged)
        toggle.accessibilityLabel = "Card Titles"
        cell.accessoryView = toggle
    }

    /// Open Show's Card Titles setting; on when Settings is on Home.
    var currentCardTitlesShown: Bool {
        guard let openShowId else { return true }
        return LocalAlbumStore.shared.album(id: openShowId)?.cardTitlesShown ?? true
    }

    @objc func cardTitlesChanged(_ sender: UISwitch) {
        guard let openShowId else { return }
        LocalAlbumStore.shared.setCardTitlesShown(sender.isOn, albumId: openShowId)
    }
}
