//
//  HomeHeaderBar.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Top header for the home screen.
///
/// Shows a connection-status pill, a center Eclipse menu (Shows), and trailing
/// Black + settings (gear) + "+" controls.
final class HomeHeaderBar: UIView {

    /// Multipeer EclipseTV link state. `.paused` is the AirPlay-first default.
    enum ConnectionDisplayState {
        case connected
        case disconnected
        case paused
    }

    // MARK: - Subviews

    private let libraryButton = UIButton(type: .system)
    private let statusDot = UIView()
    private let statusLabel = UILabel()
    /// Transparent overlay over the status pill; opens Settings.
    private let statusButton = UIButton(type: .system)
    private let blackButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)

    /// Invoked when the gear is tapped.
    var onOpenSettings: (() -> Void)?
    /// Invoked when the status pill is tapped (opens Settings → EclipseTV).
    var onStatusTapped: (() -> Void)?
    /// Invoked when Black is tapped (AirPlay goes to a solid black frame).
    var onPresentBlack: (() -> Void)?

    private var connectionState: ConnectionDisplayState = .paused
    private var isAirPlayConnected = false
    private var isBlackLive = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setConnectionState(.paused)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        var libraryConfig = UIButton.Configuration.plain()
        libraryConfig.title = "Eclipse"
        libraryConfig.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        )
        libraryConfig.imagePlacement = .trailing
        libraryConfig.imagePadding = 4
        libraryConfig.baseForegroundColor = .label
        libraryConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 8, bottom: 8, trailing: 8
        )
        libraryConfig.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
                return outgoing
            }
        libraryButton.configuration = libraryConfig
        libraryButton.showsMenuAsPrimaryAction = true
        libraryButton.accessibilityLabel = "Eclipse, Shows menu"
        libraryButton.accessibilityHint = "Shows your Shows and creates a new Show"
        libraryButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(libraryButton)

        statusDot.layer.cornerRadius = 5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusDot)

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        statusButton.translatesAutoresizingMaskIntoConstraints = false
        statusButton.addTarget(self, action: #selector(statusTapped), for: .touchUpInside)
        addSubview(statusButton)

        blackButton.translatesAutoresizingMaskIntoConstraints = false
        blackButton.accessibilityLabel = "Black"
        blackButton.accessibilityHint = "Shows a black screen on AirPlay"
        blackButton.addTarget(self, action: #selector(blackTapped), for: .touchUpInside)
        addSubview(blackButton)
        applyBlackButtonAppearance()

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)

        var gearConfig = UIButton.Configuration.plain()
        gearConfig.image = UIImage(systemName: "gearshape", withConfiguration: symbolConfig)
        gearConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 10, bottom: 10, trailing: 10
        )
        menuButton.configuration = gearConfig
        menuButton.tintColor = .systemBlue
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.accessibilityLabel = "Settings"
        menuButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        addSubview(menuButton)

        var addConfig = UIButton.Configuration.plain()
        addConfig.image = UIImage(systemName: "plus", withConfiguration: symbolConfig)
        addConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 10, bottom: 10, trailing: 10
        )
        addButton.configuration = addConfig
        addButton.tintColor = .systemBlue
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.accessibilityLabel = "Add"
        addButton.showsMenuAsPrimaryAction = true
        addSubview(addButton)

        NSLayoutConstraint.activate([
            libraryButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            libraryButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            statusDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            statusDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 10),
            statusDot.heightAnchor.constraint(equalToConstant: 10),

            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            statusButton.leadingAnchor.constraint(equalTo: statusDot.leadingAnchor, constant: -8),
            statusButton.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),
            statusButton.topAnchor.constraint(equalTo: topAnchor),
            statusButton.bottomAnchor.constraint(equalTo: bottomAnchor),

            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 44),
            addButton.heightAnchor.constraint(equalToConstant: 44),

            menuButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -2),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44),

            blackButton.trailingAnchor.constraint(
                equalTo: menuButton.leadingAnchor, constant: -6),
            blackButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            blackButton.widthAnchor.constraint(equalToConstant: 28),
            blackButton.heightAnchor.constraint(equalToConstant: 28),

            statusLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: libraryButton.leadingAnchor, constant: -4
            ),
            libraryButton.trailingAnchor.constraint(
                lessThanOrEqualTo: blackButton.leadingAnchor, constant: -4
            )
        ])
    }

    // MARK: - Menus

    /// Sets the center control title (`"Eclipse"` on Home, show name in Show mode).
    func setCenterTitle(_ title: String) {
        guard var config = libraryButton.configuration else { return }
        config.title = title
        libraryButton.configuration = config
        libraryButton.accessibilityLabel = "\(title), menu"
    }

    /// Attaches the Shows menu to the center Eclipse control.
    func setLibraryMenu(_ menu: UIMenu) {
        libraryButton.menu = menu
    }

    /// Attaches the system add menu to the "+" control (primary action).
    func setAddMenu(_ menu: UIMenu) {
        addButton.menu = menu
    }

    // MARK: - Actions

    @objc private func statusTapped() {
        onStatusTapped?()
    }

    @objc private func settingsTapped() {
        onOpenSettings?()
    }

    @objc private func blackTapped() {
        onPresentBlack?()
    }

    // MARK: - State

    /// Reflects whether Black is the live AirPlay source (red stroke + LIVE a11y).
    func setBlackLive(_ live: Bool) {
        guard isBlackLive != live else { return }
        isBlackLive = live
        applyBlackButtonAppearance()
    }

    /// Reflects EclipseTV (Multipeer) state. Combined with `setPresenting` for AirPlay.
    func setConnectionState(_ state: ConnectionDisplayState) {
        connectionState = state
        applyStatusAppearance()
        setAddEnabled(true)
        menuButton.isEnabled = true
        menuButton.alpha = 1.0
    }

    /// Updates whether an external display is available for presentation.
    func setPresenting(_ presenting: Bool) {
        isAirPlayConnected = presenting
        applyStatusAppearance()
    }

    /// Status pill: Multipeer EclipseTV link vs AirPlay external display.
    private func applyStatusAppearance() {
        switch connectionState {
        case .connected:
            if isAirPlayConnected {
                statusDot.backgroundColor = .systemGreen
                statusLabel.text = "EclipseTV · AirPlay"
                statusLabel.textColor = .systemGreen
                statusLabel.accessibilityLabel =
                    "EclipseTV linked and AirPlay display available. Double tap for Settings."
            } else {
                statusDot.backgroundColor = .systemGreen
                statusLabel.text = "EclipseTV"
                statusLabel.textColor = .systemGreen
                statusLabel.accessibilityLabel = "EclipseTV linked. Double tap for Settings."
            }
        case .disconnected:
            statusDot.backgroundColor = .systemGray
            statusLabel.text = "Connecting…"
            statusLabel.textColor = .secondaryLabel
            statusLabel.accessibilityLabel = "Connecting to EclipseTV. Double tap for Settings."
        case .paused:
            if isAirPlayConnected {
                statusDot.backgroundColor = .systemBlue
                statusLabel.text = "AirPlay"
                statusLabel.textColor = .systemBlue
                statusLabel.accessibilityLabel =
                    "AirPlay display available. Double tap for Settings."
            } else {
                statusDot.backgroundColor = .systemGray
                statusLabel.text = "Ready"
                statusLabel.textColor = .secondaryLabel
                statusLabel.accessibilityLabel =
                    "Ready. Double tap to open Settings and connect EclipseTV."
            }
        }
    }

    /// Enables or disables the "+" button (e.g. dimmed during a transfer).
    func setAddEnabled(_ enabled: Bool) {
        addButton.isEnabled = enabled
        addButton.alpha = enabled ? 1.0 : 0.4
    }

    /// The "+" button, exposed so callers can anchor popovers (iPad action sheets) to it.
    var addAnchor: UIView { addButton }

    /// The Eclipse title control, for anchoring Show-related popovers.
    var libraryAnchor: UIView { libraryButton }

    private func applyBlackButtonAppearance() {
        var config = UIButton.Configuration.plain()
        config.background.backgroundColor = .black
        config.background.cornerRadius = 8
        config.background.strokeColor = isBlackLive ? .systemRed : .separator
        config.background.strokeWidth = isBlackLive ? 3 : 1
        config.contentInsets = .zero
        blackButton.configuration = config
        blackButton.accessibilityValue = isBlackLive ? "Live" : nil
    }
}
