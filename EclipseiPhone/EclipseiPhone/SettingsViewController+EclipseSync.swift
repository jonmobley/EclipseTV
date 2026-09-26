//
//  SettingsViewController+EclipseSync.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - iCloud (Eclipse Sync) row

extension SettingsViewController {

    static let eclipseSyncFooter =
        "Shows, media, and tools sync automatically between your devices signed into "
        + "the same iCloud account. Apple TV receives media from this device over your "
        + "network, not iCloud."

    /// Status row: "On · Synced 2 minutes ago", or the pause reason.
    ///
    /// Tappable only when signing in would fix it; that opens the system Settings app.
    func configureEclipseSyncCell(
        _ cell: UITableViewCell,
        config: inout UIListContentConfiguration
    ) {
        config.text = "Eclipse Sync"
        config.secondaryText = EclipseSyncController.shared.settingsSummary
        config.image = UIImage(systemName: "icloud")
        let canOpenSettings = EclipseSyncController.shared.pauseReason == .noAccount
        cell.accessoryType = canOpenSettings ? .disclosureIndicator : .none
        cell.selectionStyle = canOpenSettings ? .default : .none
    }

    /// Opens the system Settings app when sync is paused for lack of an iCloud account.
    func handleEclipseSyncRowTap() {
        guard EclipseSyncController.shared.pauseReason == .noAccount,
              let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Keeps the row current while Settings is open.
    func observeEclipseSyncStatus() {
        for name in [
            EclipseSyncController.statusDidChangeNotification,
            EclipseSyncActivity.didChangeNotification
        ] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(eclipseSyncStatusDidChange),
                name: name,
                object: nil
            )
        }
    }

    @objc private func eclipseSyncStatusDidChange() {
        reloadEclipseSyncSection()
    }
}
