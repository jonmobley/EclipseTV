//
//  HomeHeaderBar.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Top header for the home screen.
///
/// Left: back chevron (Show mode only) + status-dot + Eclipse dropdown
/// (Shows + Settings). Trailing: moon (blackout) and "+" add control.
final class HomeHeaderBar: UIView {

    /// Multipeer EclipseTV link state. `.paused` is the AirPlay-first default.
    enum ConnectionDisplayState {
        case connected
        case disconnected
        case paused
    }

    // MARK: - Subviews

    private let menuPill = UIView()
    private let statusDot = UIView()
    private let backButton = UIButton(type: .system)
    private let libraryButton = UIButton(type: .system)
    private let blackButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)
    private let doneButton = ArrangeDoneButton()

    /// Invoked when Settings is chosen from the Eclipse menu.
    var onOpenSettings: (() -> Void)?
    /// Invoked when the moon (blackout) control is tapped.
    var onPresentBlack: (() -> Void)?
    /// Invoked when Done is tapped while arranging tiles.
    var onDoneArranging: (() -> Void)?
    /// Invoked when the back chevron is tapped to leave an open Show.
    var onGoHome: (() -> Void)?

    private var connectionState: ConnectionDisplayState = .paused
    private var isAirPlayConnected = false
    private var isBlackLive = false
    private var pillLeadingToEdge: NSLayoutConstraint!
    private var pillLeadingToBack: NSLayoutConstraint!

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
        menuPill.backgroundColor = .clear
        menuPill.layer.cornerRadius = 18
        menuPill.layer.borderWidth = 1
        menuPill.layer.borderColor = UIColor.separator.cgColor
        menuPill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(menuPill)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (view: Self, _: UITraitCollection) in
            view.menuPill.layer.borderColor = UIColor.separator.cgColor
            view.applyBlackButtonAppearance()
            if var addConfig = view.addButton.configuration {
                addConfig.background.strokeColor = .separator
                view.addButton.configuration = addConfig
            }
        }

        statusDot.layer.cornerRadius = 5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        menuPill.addSubview(statusDot)

        var backConfig = UIButton.Configuration.plain()
        backConfig.image = UIImage(
            systemName: "chevron.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        backConfig.baseForegroundColor = .label
        backConfig.contentInsets = .zero
        backButton.configuration = backConfig
        backButton.isHidden = true
        backButton.accessibilityLabel = "Home"
        backButton.accessibilityHint = "Closes this Show and returns to Recent Shows"
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        addSubview(backButton)

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
            top: 6, leading: 4, bottom: 6, trailing: 10
        )
        libraryConfig.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
                return outgoing
            }
        libraryButton.configuration = libraryConfig
        libraryButton.showsMenuAsPrimaryAction = true
        libraryButton.accessibilityLabel = "Eclipse menu"
        libraryButton.accessibilityHint = "Shows, Settings, and create a new Show"
        libraryButton.translatesAutoresizingMaskIntoConstraints = false
        menuPill.addSubview(libraryButton)

        blackButton.translatesAutoresizingMaskIntoConstraints = false
        blackButton.accessibilityLabel = "Blackout"
        blackButton.accessibilityHint = "Shows a black screen on AirPlay"
        blackButton.addTarget(self, action: #selector(blackTapped), for: .touchUpInside)
        addSubview(blackButton)
        applyBlackButtonAppearance()

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        var addConfig = UIButton.Configuration.plain()
        addConfig.image = UIImage(systemName: "plus", withConfiguration: symbolConfig)
        addConfig.background.strokeColor = .separator
        addConfig.background.strokeWidth = 1
        addConfig.background.cornerRadius = 18
        addConfig.background.backgroundColor = .clear
        addConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 8, bottom: 8, trailing: 8
        )
        addButton.configuration = addConfig
        addButton.tintColor = .systemBlue
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.accessibilityLabel = "Add"
        addButton.showsMenuAsPrimaryAction = true
        addSubview(addButton)

        doneButton.isHidden = true
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.onTap = { [weak self] in
            self?.onDoneArranging?()
        }
        addSubview(doneButton)

        pillLeadingToEdge = menuPill.leadingAnchor.constraint(
            equalTo: leadingAnchor, constant: 16
        )
        pillLeadingToBack = menuPill.leadingAnchor.constraint(
            equalTo: backButton.trailingAnchor, constant: 4
        )

        NSLayoutConstraint.activate([
            pillLeadingToEdge,
            menuPill.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuPill.heightAnchor.constraint(equalToConstant: 36),

            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 28),
            backButton.heightAnchor.constraint(equalToConstant: 36),

            statusDot.leadingAnchor.constraint(equalTo: menuPill.leadingAnchor, constant: 12),
            statusDot.centerYAnchor.constraint(equalTo: menuPill.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 10),
            statusDot.heightAnchor.constraint(equalToConstant: 10),

            libraryButton.leadingAnchor.constraint(
                equalTo: statusDot.trailingAnchor, constant: 8),
            libraryButton.trailingAnchor.constraint(equalTo: menuPill.trailingAnchor),
            libraryButton.topAnchor.constraint(equalTo: menuPill.topAnchor),
            libraryButton.bottomAnchor.constraint(equalTo: menuPill.bottomAnchor),

            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 36),
            addButton.heightAnchor.constraint(equalToConstant: 36),

            doneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            doneButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            doneButton.heightAnchor.constraint(equalToConstant: 36),

            blackButton.trailingAnchor.constraint(
                equalTo: addButton.leadingAnchor, constant: -10),
            blackButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            blackButton.heightAnchor.constraint(equalToConstant: 36),
            // Width is intrinsic: compact moon when idle, expands for "Blackout".

            menuPill.trailingAnchor.constraint(
                lessThanOrEqualTo: blackButton.leadingAnchor, constant: -12
            )
        ])
    }

    // MARK: - Menus

    /// Sets the dropdown title (`"Eclipse"` on Home, show name in Show mode).
    func setCenterTitle(_ title: String) {
        guard var config = libraryButton.configuration else { return }
        config.title = title
        libraryButton.configuration = config
        libraryButton.accessibilityLabel = "\(title) menu"
    }

    /// Attaches the Shows + Settings menu to the Eclipse control.
    func setLibraryMenu(_ menu: UIMenu) {
        libraryButton.menu = menu
    }

    /// Attaches the system add menu to the "+" control (primary action).
    func setAddMenu(_ menu: UIMenu) {
        addButton.menu = menu
    }

    // MARK: - Actions

    @objc private func blackTapped() {
        onPresentBlack?()
    }

    @objc private func backTapped() {
        onGoHome?()
    }

    // MARK: - State

    /// Reflects whether blackout is the live AirPlay source.
    func setBlackLive(_ live: Bool) {
        guard isBlackLive != live else { return }
        isBlackLive = live
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseInOut) {
            self.applyBlackButtonAppearance()
            self.layoutIfNeeded()
        }
    }

    /// Shows the back chevron ahead of the title; the only way out of Show mode.
    func setShowingBackToHome(_ showing: Bool) {
        guard backButton.isHidden == showing else { return }
        backButton.isHidden = !showing
        if showing {
            pillLeadingToEdge.isActive = false
            pillLeadingToBack.isActive = true
        } else {
            pillLeadingToBack.isActive = false
            pillLeadingToEdge.isActive = true
        }
    }

    /// Enters or leaves arrange mode, where Done replaces the blackout / "+" controls.
    func setArranging(_ arranging: Bool) {
        doneButton.isHidden = !arranging
        blackButton.isHidden = arranging
        addButton.isHidden = arranging
        // The Show name stays legible, but its menu is inert until Done.
        libraryButton.isEnabled = !arranging
        menuPill.alpha = arranging ? 0.45 : 1
    }

    /// Reflects EclipseTV (Multipeer) state. Combined with `setPresenting` for AirPlay.
    func setConnectionState(_ state: ConnectionDisplayState) {
        connectionState = state
        applyStatusAppearance()
        setAddEnabled(true)
    }

    /// Updates whether an external display is available for presentation.
    func setPresenting(_ presenting: Bool) {
        isAirPlayConnected = presenting
        applyStatusAppearance()
    }

    /// Status dot: green linked, blue AirPlay-only, grey offline / ready.
    private func applyStatusAppearance() {
        let color: UIColor
        let accessibility: String
        switch connectionState {
        case .connected:
            color = .systemGreen
            accessibility = isAirPlayConnected
                ? "EclipseTV linked, AirPlay available"
                : "EclipseTV linked"
        case .disconnected:
            color = .systemOrange
            accessibility = "Connecting to EclipseTV"
        case .paused:
            if isAirPlayConnected {
                color = .systemBlue
                accessibility = "AirPlay display available"
            } else {
                color = .systemGray
                accessibility = "Not connected"
            }
        }
        statusDot.backgroundColor = color
        menuPill.accessibilityLabel = accessibility
        libraryButton.accessibilityValue = accessibility
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
        let symbol = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "moon.fill", withConfiguration: symbol)
        config.imagePlacement = .leading
        config.background.cornerRadius = 18

        if isBlackLive {
            config.title = "Blackout"
            config.imagePadding = 6
            config.baseForegroundColor = .white
            config.background.backgroundColor = .systemBlue
            config.background.strokeWidth = 0
            config.contentInsets = NSDirectionalEdgeInsets(
                top: 6, leading: 12, bottom: 6, trailing: 14
            )
            config.titleTextAttributesTransformer =
                UIConfigurationTextAttributesTransformer { incoming in
                    var outgoing = incoming
                    outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
                    return outgoing
                }
        } else {
            config.title = nil
            config.imagePadding = 0
            config.baseForegroundColor = .label
            config.background.backgroundColor = .clear
            config.background.strokeColor = .separator
            config.background.strokeWidth = 1
            config.contentInsets = NSDirectionalEdgeInsets(
                top: 8, leading: 9, bottom: 8, trailing: 9
            )
        }

        blackButton.configuration = config
        blackButton.accessibilityValue = isBlackLive ? "On" : "Off"
    }
}
