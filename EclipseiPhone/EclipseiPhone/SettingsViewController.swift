//
//  SettingsViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Companion settings root: drill into display, transition, camera, EclipseTV,
/// and Getting Started.
/// When a Show is open, a top section hosts the name field and Delete, plus a
/// Practice Mode toggle.
final class SettingsViewController: UITableViewController, UITextFieldDelegate {

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

    /// Open Show name when Settings should offer show editing; `nil` on Home.
    var openShowName: String?
    /// Open Show id for per-Show prefs (name, share, delete, Practice Mode). `nil` on Home.
    var openShowId: UUID?
    var onShareShow: (() -> Void)?
    /// Invoked after the user confirms Delete Show. Host deletes and dismisses.
    var onDeleteShow: (() -> Void)?

    private let showNameField = UITextField()

    /// Current Multipeer link state; host updates via `setConnectionState(_:)`.
    private(set) var connectionState: ConnectionDisplayState = .paused

    private enum Section: Hashable {
        case show
        case showLivePreview
        case playback
        case showSharing
        case eclipseTV
        case eclipseMac
        case help
    }

    private enum ShowRow: Int, CaseIterable {
        case name
        case delete
    }

    private enum ShowSharingRow: Int, CaseIterable {
        case shareThisShow
        case enterShareCode
    }

    private enum PlaybackRow: Int, CaseIterable {
        case displayMode
        case transition
    }

    private enum MacRow: Int, CaseIterable {
        case remote
        case phoneCamera
    }

    private var sections: [Section] {
        var result: [Section] = []
        if openShowName != nil {
            result.append(.show)
            result.append(.showLivePreview)
        }
        result.append(contentsOf: [
            .playback, .showSharing, .eclipseTV, .eclipseMac, .help
        ])
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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "showName")
        tableView.keyboardDismissMode = .interactive
        tableView.tableFooterView = makeCopyrightFooter()
        configureShowNameField()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayModeDidChange),
            name: ExternalOutputSettings.didChangeNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !showNameField.isFirstResponder else { return }
        tableView.reloadData()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            commitShowName(revertOnFailure: true)
        }
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
        commitShowName(revertOnFailure: true)
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
        case .showLivePreview: return 1
        case .playback: return PlaybackRow.allCases.count
        case .showSharing: return showSharingRows.count
        case .eclipseTV: return 1
        case .eclipseMac: return MacRow.allCases.count
        case .help: return 1
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch sections[section] {
        case .show:
            return "Show"
        case .showLivePreview: return nil
        case .playback: return "Playback"
        case .showSharing: return "Show Sharing"
        case .eclipseTV: return "EclipseTV"
        case .eclipseMac: return "Eclipse for Mac"
        case .help: return "Help"
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        switch sections[section] {
        case .showLivePreview:
            return Self.disconnectedLivePreviewFooter
        case .eclipseTV:
            return "Link an Apple TV running EclipseTV to sync Shows and present over Multipeer. "
                + "AirPlay still works without a TV link."
        case .showSharing:
            return "Show sharing lets you send and receive a show directly from another user. When they provide you a code, add it here."
        case .eclipseMac:
            return "Control Eclipse on a Mac, or send this iPhone’s camera as a "
                + "live source (any Apple ID, same Wi‑Fi)."
        case .show, .playback, .help:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        if sections[indexPath.section] == .show,
           ShowRow(rawValue: indexPath.row) == .name {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "showName", for: indexPath
            )
            configureShowNameCell(cell)
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .disclosureIndicator
        cell.accessoryView = nil
        cell.selectionStyle = .default
        cell.isUserInteractionEnabled = true

        switch sections[indexPath.section] {
        case .show:
            configureShowCell(cell, config: &config)
        case .showLivePreview:
            configureDisconnectedLivePreviewCell(cell, config: &config)
        case .playback:
            switch PlaybackRow(rawValue: indexPath.row) {
            case .displayMode:
                config.text = "Display Mode"
                config.secondaryText = displayModeSummary()
            case .transition:
                config.text = "Content Transition"
                config.secondaryText = ExternalOutputSettings.contentTransition.rawValue
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
        case .help:
            config.text = "Getting Started"
            config.secondaryText = "Learn the basics"
            config.image = UIImage(systemName: "questionmark.circle")
        }

        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section] {
        case .show:
            if ShowRow(rawValue: indexPath.row) == .name {
                showNameField.becomeFirstResponder()
            } else {
                confirmDeleteShow()
            }
        case .showLivePreview:
            break
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
        case .help:
            pushGettingStarted()
        }
    }

    // MARK: - Show Editing

    private func configureShowNameField() {
        showNameField.placeholder = "Show name"
        showNameField.accessibilityLabel = "Show name"
        showNameField.autocapitalizationType = .words
        showNameField.clearButtonMode = .whileEditing
        showNameField.returnKeyType = .done
        showNameField.enablesReturnKeyAutomatically = true
        showNameField.font = .preferredFont(forTextStyle: .body)
        showNameField.adjustsFontForContentSizeCategory = true
        showNameField.delegate = self
        UserDisplayName.configureTextField(showNameField)
        showNameField.addTarget(
            self,
            action: #selector(showNameEditingChanged),
            for: .editingChanged
        )
    }

    private func configureShowNameCell(_ cell: UITableViewCell) {
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .none
        cell.contentConfiguration = nil
        if !showNameField.isFirstResponder {
            showNameField.text = openShowName
            showNameField.textColor = .label
        }
        installShowNameField(in: cell)
    }

    private func installShowNameField(in cell: UITableViewCell) {
        showNameField.removeFromSuperview()
        showNameField.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(showNameField)
        NSLayoutConstraint.activate([
            showNameField.leadingAnchor.constraint(
                equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor
            ),
            showNameField.trailingAnchor.constraint(
                equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor
            ),
            showNameField.topAnchor.constraint(
                equalTo: cell.contentView.topAnchor, constant: 12
            ),
            showNameField.bottomAnchor.constraint(
                equalTo: cell.contentView.bottomAnchor, constant: -12
            )
        ])
    }

    private func configureShowCell(
        _ cell: UITableViewCell,
        config: inout UIListContentConfiguration
    ) {
        cell.accessoryType = .none
        cell.selectionStyle = .default
        config.text = "Delete Show"
        config.image = UIImage(systemName: "trash")
        config.textProperties.color = .systemRed
        config.imageProperties.tintColor = .systemRed
    }

    /// Confirm in-place so Cancel can stay in Settings.
    private func confirmDeleteShow() {
        showNameField.resignFirstResponder()
        let name = openShowName ?? "this Show"
        let alert = UIAlertController(
            title: "Delete Show?",
            message: "“\(name)” is removed from Home. Its images and videos stay on this iPhone and any linked EclipseTV.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.onDeleteShow?()
        })
        present(alert, animated: true)
    }

    @objc private func showNameEditingChanged() {
        let raw = showNameField.text ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = !trimmed.isEmpty
            && LocalAlbumStore.shared.isNameTaken(trimmed, excluding: openShowId)
        showNameField.textColor = taken ? .systemRed : .label
    }

    /// Saves the field when the name is valid; otherwise restores the current name.
    @discardableResult
    private func commitShowName(revertOnFailure: Bool) -> Bool {
        guard let id = openShowId else { return true }
        let current = openShowName ?? ""
        guard let trimmed = UserDisplayName.normalized(showNameField.text ?? "") else {
            showNameField.text = current
            showNameField.textColor = .label
            return true
        }
        if trimmed == current {
            showNameField.text = current
            showNameField.textColor = .label
            return true
        }
        do {
            try LocalAlbumStore.shared.rename(id: id, to: trimmed)
            openShowName = trimmed
            showNameField.text = trimmed
            showNameField.textColor = .label
            return true
        } catch {
            if revertOnFailure {
                showNameField.text = current
                showNameField.textColor = .label
            }
            return false
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard textField === showNameField else { return true }
        guard commitShowName(revertOnFailure: false) else { return false }
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        guard textField === showNameField else { return }
        commitShowName(revertOnFailure: true)
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

    private func pushGettingStarted() {
        navigationController?.pushViewController(
            GettingStartedViewController(), animated: true
        )
    }
}
