//
//  HomeHeaderBar+OutputStatus.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Output Status (AirPlay / EclipseTV)

extension HomeHeaderBar {

    /// Installs the trailing output-status control (visible AirPlay / link state).
    func installOutputStatusButton() {
        outputStatusButton.translatesAutoresizingMaskIntoConstraints = false
        outputStatusButton.accessibilityLabel = "AirPlay and EclipseTV"
        outputStatusButton.accessibilityHint =
            "Shows AirPlay and EclipseTV link status. Double tap for options."
        outputStatusButton.addTarget(
            self,
            action: #selector(outputStatusTapped),
            for: .touchUpInside
        )
        applyOutputStatusAppearance()
    }

    /// Refreshes the status glyph from AirPlay + EclipseTV link state.
    func applyOutputStatusAppearance() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let linked = connectionState == .connected
        let searching = connectionState == .disconnected
        let name: String
        let color: UIColor
        let accessibility: String

        switch (isAirPlayConnected, linked, searching) {
        case (true, true, _):
            name = "airplayvideo"
            color = .systemGreen
            accessibility = "AirPlay available, EclipseTV linked"
        case (true, false, true):
            name = "airplayvideo"
            color = .systemBlue
            accessibility = "AirPlay available, connecting to EclipseTV"
        case (true, false, false):
            name = "airplayvideo"
            color = .systemBlue
            accessibility = "AirPlay available"
        case (false, true, _):
            name = "tv.fill"
            color = .systemGreen
            accessibility = "EclipseTV linked"
        case (false, false, true):
            name = "tv"
            color = .secondaryLabel
            accessibility = "Connecting to EclipseTV"
        case (false, false, false):
            name = "airplayvideo"
            color = .tertiaryLabel
            accessibility = "No AirPlay display, EclipseTV not linked"
        }

        outputStatusButton.configuration = Self.barIconConfig(
            systemName: name,
            symbolConfig: symbolConfig,
            foreground: color
        )
        outputStatusButton.accessibilityValue = accessibility
    }

    @objc private func outputStatusTapped() {
        onOpenOutputStatus?()
    }
}
