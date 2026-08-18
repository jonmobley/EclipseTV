//
//  SettingsViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Companion settings root: drill into display, transition, camera, and EclipseTV.
/// When a Show is open, a top section hosts Arrange / Rename / Delete.
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
    /// Invoked when Enter Share Code is chosen (host dismisses then prompts for code).
    var onEnterShareCode: (() -> Void)?

    /// Open Show name when Settings should offer Edit Show; `nil` on Home.
    var openShowName: String?
    /// `false` when Arrange needs at least two media items.
    var canArrangeShow = false
    var onArrangeShow: (() -> Void)?
    var onRenameShow: (() -> Void)?
    var onShareShow: (() -> Void)?
    var onDeleteShow: (() -> Void)?

    /// Current Multipeer link state; host updates via `setConnectionState(_:)`.
    private(set) var connectionState: ConnectionDisplayState = .paused

    private enum Section: Hashable {
        case show
        case playback
        case showSharing
        case eclipseTV
        case eclipseMac
    }

    private enum ShowRow: Int, CaseIterable {
        case arrange
        case rename
        case delete
    }

    private enum ShowSharingRow: Int, CaseIterable {
        case shareThisShow
        case enterShareCode
    }

    private enum PlaybackRow: Int, CaseIterable {
        case displayMode
        case transition
        case cameraClose
    }

    private enum MacRow: Int, CaseIterable {
        case remote
        case phoneCamera
    }

    private var sections: [Section] {
        var result: [Section] = []
        if openShowName != nil { result.append(.show) }
        result.append(contentsOf: [.playback, .showSharing, .eclipseTV, .eclipseMac])
        return result
    }

    private var showSharingRows: [ShowSharingRow] {
        if openShowName != nil {
            return [.shareThisShow, .enterShareCode]
        }
        return [.enterShareCode]
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
        if let index = sections.firstIndex(of: .eclipseTV) {
            tableView.reloadSections(IndexSet(integer: index), with: .none)
        }
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
        if let index = sections.firstIndex(of: .playback) {
            tableView.reloadSections(IndexSet(integer: index), with: .none)
        }
    }

    // MARK: - Table Data

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .show: return ShowRow.allCases.count
        case .playback: return PlaybackRow.allCases.count
        case .showSharing: return showSharingRows.count
        case .eclipseTV: return 1
        case .eclipseMac: return MacRow.allCases.count
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch sections[section] {
        case .show:
            guard let name = openShowName else { return "Show" }
            return "Edit “\(name)”"
        case .playback: return "Playback"
        case .showSharing: return "Show Sharing"
        case .eclipseTV: return "EclipseTV"
        case .eclipseMac: return "Eclipse for Mac"
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        switch sections[section] {
        case .eclipseTV:
            return "Link an Apple TV running EclipseTV to sync Shows and present over Multipeer. "
                + "AirPlay still works without a TV link."
        case .showSharing:
            return "Show sharing lets you send and receive a show directly from another user. When they provide you a code, add it here."
        case .eclipseMac:
            return "Control Eclipse on a Mac, or send this iPhone’s camera as a "
                + "live source (any Apple ID, same Wi‑Fi)."
        case .show, .playback:
            return nil
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
        cell.isUserInteractionEnabled = true

        switch sections[indexPath.section] {
        case .show:
            configureShowCell(cell, config: &config, row: indexPath.row)
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
        case .showSharing:
            configureShowSharingCell(cell, config: &config, row: indexPath.row)
        case .eclipseTV:
            config.text = "EclipseTV"
            config.secondaryText = eclipseTVSummary()
            config.image = UIImage(systemName: "tv")
        case .eclipseMac:
            switch MacRow(rawValue: indexPath.row) {
            case .remote:
                config.text = "Connect to Mac"
                config.secondaryText = "Remote control"
                config.image = UIImage(systemName: "desktopcomputer")
            case .phoneCamera:
                config.text = "Send Camera to Mac"
                config.secondaryText = "Live phone camera source"
                config.image = UIImage(systemName: "web.camera")
            case .none:
                break
            }
        }

        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section] {
        case .show:
            handleShowRow(indexPath.row)
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
        case .showSharing:
            handleShowSharingRow(indexPath.row)
        case .eclipseTV:
            pushEclipseTV()
        case .eclipseMac:
            switch MacRow(rawValue: indexPath.row) {
            case .remote:
                presentMacRemote()
            case .phoneCamera:
                presentPhoneCameraSend()
            case .none:
                break
            }
        }
    }

    // MARK: - Show Editing

    private func configureShowCell(
        _ cell: UITableViewCell,
        config: inout UIListContentConfiguration,
        row: Int
    ) {
        cell.accessoryType = .none
        cell.selectionStyle = .default
        cell.isUserInteractionEnabled = true
        config.textProperties.color = .label
        config.imageProperties.tintColor = .label
        switch ShowRow(rawValue: row) {
        case .arrange:
            config.text = "Arrange"
            config.image = UIImage(systemName: "arrow.up.arrow.down")
            let enabled = canArrangeShow
            cell.selectionStyle = enabled ? .default : .none
            cell.isUserInteractionEnabled = enabled
            config.textProperties.color = enabled ? .label : .secondaryLabel
            config.imageProperties.tintColor = enabled ? .label : .secondaryLabel
        case .rename:
            config.text = "Rename"
            config.image = UIImage(systemName: "pencil")
        case .delete:
            config.text = "Delete Show"
            config.image = UIImage(systemName: "trash")
            config.textProperties.color = .systemRed
            config.imageProperties.tintColor = .systemRed
        case .none:
            break
        }
    }

    private func handleShowRow(_ row: Int) {
        switch ShowRow(rawValue: row) {
        case .arrange: onArrangeShow?()
        case .rename: onRenameShow?()
        case .delete: onDeleteShow?()
        case .none: break
        }
    }

    // MARK: - Show Sharing

    private func configureShowSharingCell(
        _ cell: UITableViewCell,
        config: inout UIListContentConfiguration,
        row: Int
    ) {
        cell.accessoryType = .none
        switch showSharingRows[row] {
        case .shareThisShow:
            config.text = "Share this show"
            config.image = UIImage(systemName: "person.crop.circle.badge.plus")
        case .enterShareCode:
            config.text = "Enter Code"
            config.image = UIImage(systemName: "person.2.badge.key")
        }
    }

    private func handleShowSharingRow(_ row: Int) {
        switch showSharingRows[row] {
        case .shareThisShow: onShareShow?()
        case .enterShareCode: onEnterShareCode?()
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

    private func presentMacRemote() {
        MacRemoteLauncher.open(from: self)
    }

    private func presentPhoneCameraSend() {
        PhoneCameraSendLauncher.open(from: self)
    }
}
