//
//  SettingsViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Companion settings root: drill into display, transition, camera, and EclipseTV.
final class SettingsViewController: UITableViewController {

    /// Multipeer link state for the Eclipse TV App section.
    enum ConnectionDisplayState {
        case connected
        case disconnected
        case paused
    }

    /// Invoked when the known-TV list changes so the host can refresh the grid/title.
    var onLibrariesChanged: (() -> Void)?
    /// Invoked when the sync-all preference changes.
    var onSyncPreferenceChanged: ((Bool) -> Void)?
    /// Invoked when the user wants to connect / enter a pairing code.
    var onConnect: (() -> Void)?
    /// Invoked when the user stops an in-progress Multipeer search.
    var onStopConnecting: (() -> Void)?
    /// Invoked when a known TV is chosen (switch library / reconnect).
    var onSelectTV: ((String) -> Void)?
    /// Invoked when Join Presentation is chosen (host should dismiss then open Join).
    var onJoinPresentation: (() -> Void)?
    /// Current Multipeer link state; host updates via `setConnectionState(_:)`.
    private(set) var connectionState: ConnectionDisplayState = .paused

    private enum Section: Int, CaseIterable {
        case playback
        case join
        case eclipseTV
    }

    private enum PlaybackRow: Int, CaseIterable {
        case displayMode
        case transition
        case cameraClose
    }

    // MARK: - Lifecycle

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(doneTapped)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.tableFooterView = makeCopyrightFooter()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayModeDidChange),
            name: ExternalOutputSettings.didChangeNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Updates the EclipseTV summary and any open EclipseTV detail page.
    func setConnectionState(_ state: ConnectionDisplayState) {
        connectionState = state
        guard isViewLoaded else { return }
        tableView.reloadSections(IndexSet(integer: Section.eclipseTV.rawValue), with: .none)
        if let detail = navigationController?.topViewController
            as? SettingsEclipseTVViewController {
            detail.setConnectionState(state)
        }
    }

    /// Opens the EclipseTV detail page (e.g. after opening Settings from Ready).
    func scrollToEclipseTVSection() {
        guard isViewLoaded else { return }
        pushEclipseTV()
    }

    private func makeCopyrightFooter() -> UIView {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "1.0"
        let label = UILabel()
        label.text = "Eclipse \(version)\nCopyright © 2026 Moxie LLC. All rights reserved."
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 56)
        return label
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func displayModeDidChange() {
        tableView.reloadSections(IndexSet(integer: Section.playback.rawValue), with: .none)
    }

    // MARK: - Table Data

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .playback: return PlaybackRow.allCases.count
        case .join, .eclipseTV: return 1
        case .none: return 0
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch Section(rawValue: section) {
        case .playback: return "Playback"
        case .join: return "Shared Presentation"
        case .eclipseTV: return "EclipseTV"
        case .none: return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default

        switch Section(rawValue: indexPath.section) {
        case .playback:
            switch PlaybackRow(rawValue: indexPath.row) {
            case .displayMode:
                config.text = "Display Mode"
                config.secondaryText = displayModeSummary()
            case .transition:
                config.text = "Content Transition"
                config.secondaryText = ExternalOutputSettings.contentTransition.rawValue
            case .cameraClose:
                config.text = "When Camera Closes"
                config.secondaryText = ExternalOutputSettings.cameraCloseDestination.rawValue
            case .none:
                break
            }
        case .join:
            let joined = AlbumBrowserStore.shared.hasAccountConfigured
            config.text = joined ? "Open Joined Presentation…" : "Join Presentation…"
            config.image = UIImage(systemName: "person.2.badge.key")
            cell.accessoryType = .disclosureIndicator
        case .eclipseTV:
            config.text = "EclipseTV"
            config.secondaryText = eclipseTVSummary()
            config.image = UIImage(systemName: "tv")
        case .none:
            break
        }

        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .playback:
            switch PlaybackRow(rawValue: indexPath.row) {
            case .displayMode:
                navigationController?.pushViewController(
                    SettingsDisplayModeViewController(), animated: true
                )
            case .transition:
                navigationController?.pushViewController(
                    SettingsTransitionViewController(), animated: true
                )
            case .cameraClose:
                navigationController?.pushViewController(
                    SettingsCameraCloseViewController(), animated: true
                )
            case .none:
                break
            }
        case .join:
            onJoinPresentation?()
        case .eclipseTV:
            pushEclipseTV()
        case .none:
            break
        }
    }

    // MARK: - Summaries / Navigation

    private func displayModeSummary() -> String {
        let orientation = ExternalOutputSettings.orientation
        guard ExternalOutputSettings.isVerticalMode else {
            return orientation.rawValue
        }
        return "\(orientation.rawValue) · \(ExternalOutputSettings.rotationDirection.rawValue)"
    }

    private func eclipseTVSummary() -> String {
        switch connectionState {
        case .connected: return "Linked"
        case .disconnected: return "Connecting…"
        case .paused: return "Not linked"
        }
    }

    private func pushEclipseTV() {
        let detail = SettingsEclipseTVViewController()
        detail.connectionState = connectionState
        detail.onLibrariesChanged = onLibrariesChanged
        detail.onSyncPreferenceChanged = onSyncPreferenceChanged
        detail.onConnect = { [weak self] in
            self?.onConnect?()
        }
        detail.onStopConnecting = { [weak self] in
            self?.onStopConnecting?()
        }
        detail.onSelectTV = onSelectTV
        navigationController?.pushViewController(detail, animated: true)
    }
}
