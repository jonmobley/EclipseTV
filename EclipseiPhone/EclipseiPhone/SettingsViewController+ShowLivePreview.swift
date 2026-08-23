//
//  SettingsViewController+ShowLivePreview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Practice Mode (disconnected)

extension SettingsViewController {

    /// Footer under the per-Show Practice Mode toggle.
    static let disconnectedLivePreviewFooter =
        "When nothing is connected, tapping a card opens Preview on this iPhone. "
        + "Practice Mode uses the live preview and Lock / Blackout instead."

    /// Toggle: live preview plus Lock / Blackout with no display connected.
    func configureDisconnectedLivePreviewCell(
        _ cell: UITableViewCell,
        config: inout UIListContentConfiguration
    ) {
        cell.accessoryType = .none
        cell.selectionStyle = .none
        config.text = "Practice Mode"
        config.image = UIImage(systemName: "tv.slash")
        config.secondaryText = nil

        let toggle = UISwitch()
        toggle.isOn = currentPreviewsWhenDisconnected
        toggle.addTarget(
            self,
            action: #selector(disconnectedLivePreviewChanged(_:)),
            for: .valueChanged
        )
        toggle.accessibilityLabel = "Practice Mode"
        cell.accessoryView = toggle
    }

    /// Current Show's Practice Mode flag; `false` when Settings is on Home.
    var currentPreviewsWhenDisconnected: Bool {
        guard let openShowId else { return false }
        return LocalAlbumStore.shared.album(id: openShowId)?.previewsWhenDisconnected
            ?? false
    }

    @objc func disconnectedLivePreviewChanged(_ sender: UISwitch) {
        guard let openShowId else { return }
        LocalAlbumStore.shared.setPreviewsWhenDisconnected(
            sender.isOn, albumId: openShowId
        )
    }
}
