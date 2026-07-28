//
//  HomeHeaderBar.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Top header for the home (library) screen.
///
/// Shows a connection-status pill (Ready / Presenting / TV App), a center Library
/// dropdown (Camera / Albums / Web), and trailing settings (gear) + "+" controls.
///
/// While arranging, it switches to Cancel / Arrange / Done.
final class HomeHeaderBar: UIView {

    /// Multipeer Eclipse TV app link state. `.paused` is the AirPlay-first default.
    enum ConnectionDisplayState {
        case connected
        case disconnected
        case paused
    }

    // MARK: - Subviews

    private let libraryButton = UIButton(type: .system)
    private let statusDot = UIView()
    private let statusLabel = UILabel()
    /// Transparent overlay over the status pill; tappable to connect when not linked.
    private let statusButton = UIButton(type: .system)
    private let presentingIcon = UIImageView()
    private let menuButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)

    private let titleLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    /// Invoked when the "+" button is tapped.
    var onAddTapped: (() -> Void)?
    /// Invoked when "Done" is tapped while arranging.
    var onArrangeDone: (() -> Void)?
    /// Invoked when "Cancel" is tapped while arranging.
    var onArrangeCancel: (() -> Void)?
    /// Invoked when the gear is tapped.
    var onOpenSettings: (() -> Void)?
    /// Invoked when the status pill is tapped while not linked (opens connect flow).
    var onConnect: (() -> Void)?
    /// Invoked when "Camera" is chosen from the library dropdown.
    var onPresentCamera: (() -> Void)?
    /// Invoked when "Albums" is chosen from the library dropdown.
    var onBrowseAlbums: (() -> Void)?
    /// Invoked when "Web" is chosen from the library dropdown.
    var onBrowseWeb: (() -> Void)?

    private var connectionState: ConnectionDisplayState = .paused
    private var isAirPlayConnected = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setConnectionState(.paused)
        setArranging(false)
        rebuildLibraryMenu()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.down",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        config.imagePlacement = .trailing
        config.imagePadding = 4
        config.baseForegroundColor = .label
        config.contentInsets = .zero
        libraryButton.configuration = config
        libraryButton.showsMenuAsPrimaryAction = true
        libraryButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(libraryButton)
        setLibraryTitle(nil)

        statusDot.layer.cornerRadius = 5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusDot)

        statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        statusButton.translatesAutoresizingMaskIntoConstraints = false
        statusButton.addTarget(self, action: #selector(statusTapped), for: .touchUpInside)
        addSubview(statusButton)

        // Kept for layout compatibility; always hidden — an AirPlay glyph next to the
        // status pill read like a named TV device identity.
        presentingIcon.isHidden = true
        presentingIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(presentingIcon)

        let menuConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        menuButton.setImage(UIImage(systemName: "gearshape", withConfiguration: menuConfig), for: .normal)
        menuButton.tintColor = .label
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.accessibilityLabel = "Settings"
        menuButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        addSubview(menuButton)

        let plusConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        addButton.setImage(UIImage(systemName: "plus", withConfiguration: plusConfig), for: .normal)
        addButton.tintColor = .white
        addButton.backgroundColor = .systemBlue
        addButton.layer.cornerRadius = 18
        addButton.clipsToBounds = true
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        addSubview(addButton)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.text = "Arrange"
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        addSubview(cancelButton)

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        addSubview(doneButton)

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

            presentingIcon.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),
            presentingIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            presentingIcon.widthAnchor.constraint(equalToConstant: 22),
            presentingIcon.heightAnchor.constraint(equalToConstant: 18),

            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 36),
            addButton.heightAnchor.constraint(equalToConstant: 36),

            menuButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -12),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 36),
            menuButton.heightAnchor.constraint(equalToConstant: 36),

            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: libraryButton.leadingAnchor, constant: -8),

            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            doneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            doneButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    // MARK: - Library Dropdown

    /// Sets the center title. Pass a Multipeer-linked Eclipse TV app name, or `nil`
    /// for the AirPlay-first default ("Library").
    func setLibraryTitle(_ name: String?) {
        let title = (name?.isEmpty == false) ? name! : "Library"
        libraryButton.configuration?.attributedTitle = AttributedString(
            title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .bold)]))
    }

    private func rebuildLibraryMenu() {
        let camera = UIAction(title: "Camera",
                              image: UIImage(systemName: "camera.fill")) { [weak self] _ in
            self?.onPresentCamera?()
        }
        let albums = UIAction(title: "Albums",
                              image: UIImage(systemName: "rectangle.stack")) { [weak self] _ in
            self?.onBrowseAlbums?()
        }
        let web = UIAction(title: "Web",
                           image: UIImage(systemName: "safari")) { [weak self] _ in
            self?.onBrowseWeb?()
        }
        libraryButton.menu = UIMenu(children: [camera, albums, web])
    }

    // MARK: - Actions

    @objc private func addTapped() {
        onAddTapped?()
    }

    @objc private func cancelTapped() {
        onArrangeCancel?()
    }

    @objc private func statusTapped() {
        guard connectionState != .connected else { return }
        onConnect?()
    }

    @objc private func doneTapped() {
        onArrangeDone?()
    }

    @objc private func settingsTapped() {
        onOpenSettings?()
    }

    // MARK: - State

    /// Reflects Eclipse TV app (Multipeer) state. AirPlay presentation is shown via
    /// `setPresenting` when the TV app isn't linked.
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
        presentingIcon.isHidden = true
        applyStatusAppearance()
    }

    /// Status pill: Multipeer TV app link vs external-display presentation.
    private func applyStatusAppearance() {
        switch connectionState {
        case .connected:
            statusDot.backgroundColor = .systemGreen
            statusLabel.text = "TV App"
            statusLabel.textColor = .systemGreen
            statusLabel.accessibilityLabel = "Eclipse TV app linked"
        case .disconnected:
            statusDot.backgroundColor = .systemGray
            statusLabel.text = "Connecting…"
            statusLabel.textColor = .secondaryLabel
            statusLabel.accessibilityLabel = "Connecting to Eclipse TV app"
        case .paused:
            if isAirPlayConnected {
                statusDot.backgroundColor = .systemBlue
                statusLabel.text = "Presenting"
                statusLabel.textColor = .systemBlue
                statusLabel.accessibilityLabel =
                    "External display available for presentation"
            } else {
                statusDot.backgroundColor = .systemGray
                statusLabel.text = "Ready"
                statusLabel.textColor = .secondaryLabel
                statusLabel.accessibilityLabel = "Ready"
            }
        }
    }

    /// Enables or disables the "+" button (e.g. dimmed during a transfer).
    func setAddEnabled(_ enabled: Bool) {
        addButton.isEnabled = enabled
        addButton.alpha = enabled ? 1.0 : 0.4
    }

    /// Toggles between the normal layout and the arranging (Cancel / Done) layout.
    func setArranging(_ arranging: Bool) {
        libraryButton.isHidden = arranging
        statusDot.isHidden = arranging
        statusLabel.isHidden = arranging
        statusButton.isHidden = arranging
        presentingIcon.isHidden = true
        menuButton.isHidden = arranging
        addButton.isHidden = arranging
        titleLabel.isHidden = !arranging
        cancelButton.isHidden = !arranging
        doneButton.isHidden = !arranging
    }

    /// The "+" button, exposed so callers can anchor popovers (iPad action sheets) to it.
    var addAnchor: UIView { addButton }
}
