//
//  HomeHeaderBar+DisconnectedPreview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Disconnected Live Preview

extension HomeHeaderBar {

    /// AirPlay/HDMI or a live Eclipse TV link — the phone preview toggle is hidden.
    var hasRealLiveDestination: Bool {
        isAirPlayConnected || connectionState == .connected
    }

    /// Installs the Show-header preview control (called from `setupViews`).
    func installDisconnectedPreviewButton() {
        disconnectedPreviewButton.translatesAutoresizingMaskIntoConstraints = false
        disconnectedPreviewButton.accessibilityLabel = "Live preview"
        disconnectedPreviewButton.accessibilityHint =
            "Shows what's live on this iPhone when no display is connected"
        disconnectedPreviewButton.addTarget(
            self,
            action: #selector(disconnectedPreviewTapped),
            for: .touchUpInside
        )
        applyDisconnectedPreviewAppearance()
    }

    /// On/off for the disconnected live-preview hero.
    func setDisconnectedPreview(_ enabled: Bool) {
        guard isDisconnectedPreviewOn != enabled else { return }
        isDisconnectedPreviewOn = enabled
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseInOut) {
            self.applyDisconnectedPreviewAppearance()
            self.layoutIfNeeded()
        }
    }

    func applyDisconnectedPreviewAppearance() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let name = "rectangle.inset.filled"
        if isDisconnectedPreviewOn {
            var config = UIButton.Configuration.filled()
            config.image = UIImage(systemName: name, withConfiguration: symbolConfig)
            config.baseForegroundColor = .white
            config.baseBackgroundColor = .systemTeal
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(
                top: 6, leading: 6, bottom: 6, trailing: 6
            )
            disconnectedPreviewButton.configuration = config
        } else {
            disconnectedPreviewButton.configuration = Self.barIconConfig(
                systemName: name,
                symbolConfig: symbolConfig
            )
        }
        disconnectedPreviewButton.accessibilityValue =
            isDisconnectedPreviewOn ? "On" : "Off"
    }

    @objc private func disconnectedPreviewTapped() {
        onToggleDisconnectedPreview?()
    }
}
