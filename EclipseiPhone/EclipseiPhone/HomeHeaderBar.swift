//
//  HomeHeaderBar.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Top header for the home screen.
///
/// Home: page dropdown · + New Show.
/// Show mode trailing: Lock + Blackout (when a display, EclipseTV, or Practice
/// Mode is on), Settings, and "+".
/// iCloud Sync status surfaces via `EclipseSyncStatusBanner`, not the header.
final class HomeHeaderBar: UIView {

    /// Multipeer EclipseTV link state. `.paused` is the AirPlay-first default.
    enum ConnectionDisplayState {
        case connected
        case disconnected
        case paused
    }

    // MARK: - Subviews

    private let menuPill = UIView()
    private let libraryButton = UIButton(type: .system)
    private let trailingStack = UIStackView()
    private let lockButton = UIButton(type: .system)
    private let blackButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)
    private let newShowButton = UIButton(type: .system)
    private let doneButton = ArrangeDoneButton()
    private let selectActionsButton = UIButton(type: .system)

    /// Invoked when the Settings control is tapped.
    var onOpenSettings: (() -> Void)?
    /// Invoked when the live-output Lock control is tapped.
    var onToggleLiveLock: (() -> Void)?
    /// Invoked when the Blackout control is tapped.
    var onPresentBlack: (() -> Void)?
    /// Invoked when New Show is tapped on Home.
    var onNewShow: (() -> Void)?
    /// Invoked when Done is tapped while arranging tiles.
    var onDoneArranging: (() -> Void)?
    /// Invoked when Done is tapped while multi-selecting tiles.
    var onDoneSelecting: (() -> Void)?

    /// EclipseTV Multipeer link — read by output-status chrome.
    private(set) var connectionState: ConnectionDisplayState = .paused
    /// External/AirPlay display available — read by output-status chrome.
    private(set) var isAirPlayConnected = false
    private var isLiveLocked = false
    private var isBlackLive = false
    private var showsShowChrome = false
    private var previewsWhenDisconnected = false
    private var isArranging = false
    private var isSelecting = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setConnectionState(.paused)
        applyTrailingChrome()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        menuPill.backgroundColor = .clear
        menuPill.layer.cornerRadius = 18
        menuPill.layer.cornerCurve = .continuous
        menuPill.layer.borderWidth = 1
        menuPill.layer.borderColor = UIColor.separator.cgColor
        menuPill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(menuPill)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (view: Self, _: UITraitCollection) in
            view.menuPill.layer.borderColor = UIColor.separator.cgColor
            view.applyLockButtonAppearance()
            view.applyBlackButtonAppearance()
            view.applyNewShowButtonAppearance()
        }

        var libraryConfig = UIButton.Configuration.plain()
        libraryConfig.title = "Home"
        libraryConfig.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        )
        libraryConfig.imagePlacement = .trailing
        libraryConfig.imagePadding = 4
        libraryConfig.baseForegroundColor = .label
        libraryConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 6, leading: 12, bottom: 6, trailing: 10
        )
        libraryConfig.titleLineBreakMode = .byTruncatingTail
        libraryConfig.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
                return outgoing
            }
        libraryButton.configuration = libraryConfig
        libraryButton.showsMenuAsPrimaryAction = true
        libraryButton.accessibilityLabel = "Home menu"
        libraryButton.accessibilityHint =
            "Open Show, New Show, Library, Music, Settings, and Recent Shows"
        libraryButton.translatesAutoresizingMaskIntoConstraints = false
        libraryButton.setContentCompressionResistancePriority(
            .defaultLow, for: .horizontal
        )
        menuPill.setContentCompressionResistancePriority(
            .defaultLow, for: .horizontal
        )
        menuPill.addSubview(libraryButton)

        lockButton.translatesAutoresizingMaskIntoConstraints = false
        lockButton.accessibilityLabel = "Lock live output"
        lockButton.accessibilityHint =
            "When on, the current live output stays fixed; media, Screensaver, and Background open in Preview"
        lockButton.addTarget(self, action: #selector(lockTapped), for: .touchUpInside)
        applyLockButtonAppearance()

        blackButton.translatesAutoresizingMaskIntoConstraints = false
        blackButton.accessibilityLabel = "Blackout"
        blackButton.accessibilityHint = "Toggles a black screen on AirPlay"
        blackButton.addTarget(self, action: #selector(blackTapped), for: .touchUpInside)
        applyBlackButtonAppearance()

        // Plain SF Symbols, like UIBarButtonItem — not icons in stroked circles.
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        settingsButton.configuration = Self.barIconConfig(
            systemName: "gearshape.fill",
            symbolConfig: symbolConfig
        )
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.accessibilityLabel = "Settings"
        settingsButton.accessibilityHint = "Open Settings; edit the open Show there"
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)

        addButton.configuration = Self.barIconConfig(
            systemName: "plus",
            symbolConfig: symbolConfig,
            foreground: .systemBlue
        )
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.accessibilityLabel = "Add"
        addButton.showsMenuAsPrimaryAction = true

        newShowButton.translatesAutoresizingMaskIntoConstraints = false
        newShowButton.accessibilityLabel = "New Show"
        newShowButton.addTarget(self, action: #selector(newShowTapped), for: .touchUpInside)
        applyNewShowButtonAppearance()

        doneButton.isHidden = true
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.onTap = { [weak self] in
            guard let self else { return }
            if self.isSelecting {
                self.onDoneSelecting?()
            } else {
                self.onDoneArranging?()
            }
        }

        var selectConfig = UIButton.Configuration.filled()
        selectConfig.title = "Actions"
        selectConfig.baseBackgroundColor = .secondarySystemBackground
        selectConfig.baseForegroundColor = .label
        selectConfig.background.cornerRadius = 18
        selectConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 7, leading: 14, bottom: 7, trailing: 14
        )
        selectConfig.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 16, weight: .semibold)
                return outgoing
            }
        selectActionsButton.configuration = selectConfig
        selectActionsButton.showsMenuAsPrimaryAction = true
        selectActionsButton.isHidden = true
        selectActionsButton.translatesAutoresizingMaskIntoConstraints = false
        selectActionsButton.accessibilityLabel = "Selection actions"

        trailingStack.axis = .horizontal
        trailingStack.alignment = .center
        trailingStack.spacing = 8
        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        for button in [
            lockButton, blackButton, settingsButton,
            addButton, newShowButton, selectActionsButton, doneButton
        ] {
            trailingStack.addArrangedSubview(button)
        }
        addSubview(trailingStack)

        NSLayoutConstraint.activate([
            menuPill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            menuPill.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuPill.heightAnchor.constraint(equalToConstant: 36),

            libraryButton.leadingAnchor.constraint(equalTo: menuPill.leadingAnchor),
            libraryButton.trailingAnchor.constraint(equalTo: menuPill.trailingAnchor),
            libraryButton.topAnchor.constraint(equalTo: menuPill.topAnchor),
            libraryButton.bottomAnchor.constraint(equalTo: menuPill.bottomAnchor),

            trailingStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            trailingStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            addButton.widthAnchor.constraint(equalToConstant: 36),
            addButton.heightAnchor.constraint(equalToConstant: 36),
            settingsButton.widthAnchor.constraint(equalToConstant: 36),
            settingsButton.heightAnchor.constraint(equalToConstant: 36),
            lockButton.widthAnchor.constraint(equalToConstant: 36),
            lockButton.heightAnchor.constraint(equalToConstant: 36),
            blackButton.widthAnchor.constraint(equalToConstant: 36),
            blackButton.heightAnchor.constraint(equalToConstant: 36),
            newShowButton.heightAnchor.constraint(equalToConstant: 36),
            selectActionsButton.heightAnchor.constraint(equalToConstant: 36),
            doneButton.heightAnchor.constraint(equalToConstant: 36),

            menuPill.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -8
            )
        ])
        for button in [
            lockButton, blackButton, settingsButton,
            addButton, newShowButton
        ] {
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        lockButton.setContentHuggingPriority(.required, for: .horizontal)
        blackButton.setContentHuggingPriority(.required, for: .horizontal)
    }

    /// Toolbar-style icon button (plain SF Symbol, no stroked circle chrome).
    static func barIconConfig(
        systemName: String,
        symbolConfig: UIImage.SymbolConfiguration,
        foreground: UIColor = .label
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: systemName, withConfiguration: symbolConfig)
        config.baseForegroundColor = foreground
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 6, leading: 6, bottom: 6, trailing: 6
        )
        return config
    }

    // MARK: - Menus

    /// Sets the dropdown title (`"Home"` on Home, show name in Show mode).
    func setCenterTitle(_ title: String) {
        guard var config = libraryButton.configuration else { return }
        config.title = title
        config.titleLineBreakMode = .byTruncatingTail
        libraryButton.configuration = config
        libraryButton.accessibilityLabel = "\(title) menu"
    }

    /// Attaches the page dropdown (Home, Open Show, New Show, Library, Music, Recents).
    func setLibraryMenu(_ menu: UIMenu) {
        libraryButton.menu = menu
    }

    /// Attaches the system add menu to the "+" control (primary action).
    func setAddMenu(_ menu: UIMenu) {
        addButton.menu = menu
    }

    // MARK: - Actions

    @objc private func lockTapped() {
        onToggleLiveLock?()
    }

    @objc private func blackTapped() {
        onPresentBlack?()
    }

    @objc private func settingsTapped() {
        onOpenSettings?()
    }

    @objc private func newShowTapped() {
        onNewShow?()
    }

    // MARK: - State

    /// Show-mode trailing chrome (Settings, +, Lock / Blackout when live).
    func setShowModeChrome(_ showMode: Bool) {
        guard showsShowChrome != showMode else { return }
        showsShowChrome = showMode
        applyTrailingChrome()
        libraryButton.accessibilityHint = showMode
            ? "Home, Open Show, New Show, Library, Music, and Recent Shows"
            : "Open Show, New Show, Library, Music, Settings, and Recent Shows"
    }

    /// Practice Mode for the open Show: live preview + Lock / Blackout when
    /// nothing is connected. Off means taps open on-device Preview.
    func setPreviewsWhenDisconnected(_ enabled: Bool) {
        guard previewsWhenDisconnected != enabled else { return }
        previewsWhenDisconnected = enabled
        applyTrailingChrome()
    }

    /// Lock + Blackout: Show mode with a display, EclipseTV, or Practice Mode.
    var showsLiveOutputChrome: Bool {
        showsShowChrome && (
            isAirPlayConnected
            || connectionState == .connected
            || previewsWhenDisconnected
        )
    }

    /// Reflects whether live output is locked (amber lock control).
    func setLiveLocked(_ locked: Bool) {
        guard isLiveLocked != locked else { return }
        isLiveLocked = locked
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseInOut) {
            self.applyLockButtonAppearance()
            self.layoutIfNeeded()
        }
    }

    /// Reflects whether blackout is the live AirPlay source.
    func setBlackLive(_ live: Bool) {
        guard isBlackLive != live else { return }
        isBlackLive = live
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseInOut) {
            self.applyBlackButtonAppearance()
            self.layoutIfNeeded()
        }
    }

    /// Enters or leaves arrange mode, where Done replaces the trailing controls.
    func setArranging(_ arranging: Bool) {
        isArranging = arranging
        if arranging { isSelecting = false }
        applyEditingChrome()
    }

    /// Enters or leaves Show multi-select; `actionsMenu` is shown when items are checked.
    func setSelecting(_ selecting: Bool, actionsMenu: UIMenu?) {
        isSelecting = selecting
        if selecting { isArranging = false }
        selectActionsButton.menu = actionsMenu
        selectActionsButton.isHidden = !selecting || actionsMenu == nil
        selectActionsButton.accessibilityLabel = "Selection actions"
        applyEditingChrome()
    }

    private func applyEditingChrome() {
        let editing = isArranging || isSelecting
        applyTrailingChrome()
        libraryButton.isEnabled = !editing
        menuPill.alpha = editing ? 0.45 : 1
        doneButton.accessibilityLabel = isSelecting
            ? "Done selecting"
            : "Done arranging"
        doneButton.accessibilityHint = isSelecting
            ? "Leaves select mode"
            : "Saves the new order"
    }

    private func applyTrailingChrome() {
        let editing = isArranging || isSelecting
        doneButton.isHidden = !editing
        if !isSelecting {
            selectActionsButton.isHidden = true
            selectActionsButton.menu = nil
        }
        if editing {
            lockButton.isHidden = true
            blackButton.isHidden = true
            settingsButton.isHidden = true
            addButton.isHidden = true
            newShowButton.isHidden = true
            return
        }
        lockButton.isHidden = !showsLiveOutputChrome
        blackButton.isHidden = !showsLiveOutputChrome
        settingsButton.isHidden = !showsShowChrome
        addButton.isHidden = !showsShowChrome
        newShowButton.isHidden = showsShowChrome
    }

    /// Reflects EclipseTV (Multipeer) state. Combined with `setPresenting` for AirPlay.
    func setConnectionState(_ state: ConnectionDisplayState) {
        connectionState = state
        applyTrailingChrome()
        setAddEnabled(true)
    }

    /// Updates whether an external display is available for presentation.
    func setPresenting(_ presenting: Bool) {
        isAirPlayConnected = presenting
        applyTrailingChrome()
    }

    /// Enables or disables the "+" button (e.g. dimmed during a transfer).
    func setAddEnabled(_ enabled: Bool) {
        addButton.isEnabled = enabled
        addButton.alpha = enabled ? 1.0 : 0.4
    }

    /// The "+" button, exposed so callers can anchor popovers (iPad action sheets) to it.
    var addAnchor: UIView { addButton }

    /// The page title control, for anchoring Show-related popovers.
    var libraryAnchor: UIView { libraryButton }

    /// New Show control, for anchoring popovers when "+" is hidden on Home.
    var newShowAnchor: UIView { newShowButton }

    private func applyLockButtonAppearance() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        // Same lock glyph both ways — amber fill already marks the active state.
        let name = "lock.fill"
        if isLiveLocked {
            var config = UIButton.Configuration.filled()
            config.image = UIImage(systemName: name, withConfiguration: symbolConfig)
            config.baseForegroundColor = .white
            config.baseBackgroundColor = .systemOrange
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(
                top: 6, leading: 6, bottom: 6, trailing: 6
            )
            lockButton.configuration = config
        } else {
            lockButton.configuration = Self.barIconConfig(
                systemName: name,
                symbolConfig: symbolConfig
            )
        }
        lockButton.accessibilityValue = isLiveLocked ? "On" : "Off"
    }

    private func applyBlackButtonAppearance() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        // Always fill — matches lock / settings; active state is the blue capsule.
        let name = "moon.fill"
        if isBlackLive {
            var config = UIButton.Configuration.filled()
            config.image = UIImage(systemName: name, withConfiguration: symbolConfig)
            config.baseForegroundColor = .white
            config.baseBackgroundColor = .systemBlue
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(
                top: 6, leading: 6, bottom: 6, trailing: 6
            )
            blackButton.configuration = config
        } else {
            blackButton.configuration = Self.barIconConfig(
                systemName: name,
                symbolConfig: symbolConfig
            )
        }
        blackButton.accessibilityValue = isBlackLive ? "On" : "Off"
    }

    private func applyNewShowButtonAppearance() {
        var config = UIButton.Configuration.filled()
        config.title = "+ New Show"
        config.baseForegroundColor = .white
        config.baseBackgroundColor = .systemBlue
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 7, leading: 14, bottom: 7, trailing: 14
        )
        config.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
                return outgoing
            }
        newShowButton.configuration = config
    }
}
