//
//  SettingsEclipseTVViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// EclipseTV link controls, sync preference, and known Apple TVs.
final class SettingsEclipseTVViewController: UITableViewController {

    /// Multipeer link state; host updates via `setConnectionState(_:)`.
    var connectionState: SettingsViewController.ConnectionDisplayState = .paused

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

    private enum Section: Int, CaseIterable {
        case connection
        case sync
        case appleTVs
    }

    private var knownTVs: [KnownTV] = []

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "EclipseTV"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        reloadKnownTVs()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // A TV can be remembered while this screen is open (or pushed over), so re-read
        // the registry instead of showing the list captured at load time.
        reloadKnownTVs()
    }

    /// Refreshes connection rows for the current Multipeer link state.
    func setConnectionState(_ state: SettingsViewController.ConnectionDisplayState) {
        connectionState = state
        guard isViewLoaded else { return }
        tableView.reloadSections(IndexSet(integer: Section.connection.rawValue), with: .none)
    }

    private func reloadKnownTVs() {
        knownTVs = KnownTVRegistry.shared.all()
        tableView.reloadData()
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .connection:
            switch connectionState {
            case .connected, .paused: return 1
            case .disconnected: return 2
            }
        case .sync: return 1
        case .appleTVs: return max(knownTVs.count, 1)
        case .none: return 0
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch Section(rawValue: section) {
        case .connection: return "Link"
        case .sync: return "Sync"
        case .appleTVs: return "Apple TVs"
        case .none: return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        switch Section(rawValue: section) {
        case .connection:
            return "Optional link to the Eclipse app on Apple TV for media sync. "
                + "Uses the pairing code on the TV. Separate from AirPlay and from "
                + "Share Code (shared Shows)."
        case .sync:
            return "When on, media changes go to every linked Apple TV, and newly "
                + "linked TVs are caught up. Only media sent from this iPhone can "
                + "be mirrored."
        case .appleTVs:
            return "Tap a TV to view its Shows. Swipe to remove and clear its "
                + "cached media on this iPhone."
        case .none:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .connection: return connectionCell(at: indexPath.row)
        case .sync: return syncCell()
        case .appleTVs: return appleTVCell(at: indexPath)
        case .none: return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .connection:
            handleConnectionAction(at: indexPath.row)
        case .appleTVs:
            guard !knownTVs.isEmpty else { return }
            onSelectTV?(knownTVs[indexPath.row].name)
            tableView.reloadSections(IndexSet(integer: Section.appleTVs.rawValue), with: .none)
        case .sync, .none:
            break
        }
    }

    // MARK: - Connection / Sync / TVs

    private func connectionCell(at row: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .default
        switch connectionState {
        case .connected:
            cell.textLabel?.text = "Linked"
            cell.imageView?.image = UIImage(systemName: "checkmark.circle.fill")
            cell.imageView?.tintColor = .systemGreen
            cell.selectionStyle = .none
        case .disconnected:
            if row == 0 {
                cell.textLabel?.text = "Connect / Enter Pairing Code…"
                cell.imageView?.image = UIImage(systemName: "wifi")
            } else {
                cell.textLabel?.text = "Stop Connecting to EclipseTV"
                cell.imageView?.image = UIImage(systemName: "pause.circle")
            }
            cell.imageView?.tintColor = .label
        case .paused:
            cell.textLabel?.text = "Connect EclipseTV…"
            cell.imageView?.image = UIImage(systemName: "wifi")
            cell.imageView?.tintColor = .label
        }
        return cell
    }

    private func handleConnectionAction(at row: Int) {
        switch connectionState {
        case .connected:
            break
        case .disconnected:
            if row == 0 { onConnect?() } else { onStopConnecting?() }
        case .paused:
            onConnect?()
        }
    }

    private func syncCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "Keep all Apple TVs in sync"
        cell.selectionStyle = .none

        let toggle = UISwitch()
        toggle.isOn = CompanionSettings.syncAllTVs
        toggle.addTarget(self, action: #selector(syncToggleChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    private func appleTVCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        let activeName = TVLibraryStore.shared.activeTVName

        if knownTVs.isEmpty {
            config.text = "No Apple TVs yet"
            config.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
            cell.accessoryType = .none
        } else {
            let tv = knownTVs[indexPath.row]
            config.text = tv.name
            config.secondaryText = "Last seen "
                + tv.lastSeen.formatted(date: .abbreviated, time: .shortened)
            cell.selectionStyle = .default
            cell.accessoryType = tv.name == activeName ? .checkmark : .none
        }

        cell.contentConfiguration = config
        return cell
    }

    @objc private func syncToggleChanged(_ sender: UISwitch) {
        CompanionSettings.syncAllTVs = sender.isOn
        onSyncPreferenceChanged?(sender.isOn)
    }

    // MARK: - Editing

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .appleTVs && !knownTVs.isEmpty
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .appleTVs, !knownTVs.isEmpty else {
            return nil
        }
        let action = UIContextualAction(style: .destructive, title: "Remove") {
            [weak self] _, _, done in
            self?.confirmForgetTV(at: indexPath, completion: done)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    private func confirmForgetTV(at indexPath: IndexPath, completion: @escaping (Bool) -> Void) {
        let tv = knownTVs[indexPath.row]
        let alert = UIAlertController(
            title: "Remove \(tv.name)?",
            message: "Clears this Apple TV from the list and removes its cached "
                + "media on this iPhone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(false)
        })
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) {
            [weak self] _ in
            self?.forgetTV(named: tv.name)
            completion(true)
        })
        present(alert, animated: true)
    }

    private func forgetTV(named name: String) {
        KnownTVRegistry.shared.forget(name: name)
        TVLibraryStore.shared.reset(tvName: name)
        MultiTVSyncCoordinator.shared.forget(tvNamed: name)
        PairedPeerStore.shared.forget(displayName: name)

        if CompanionSettings.preferredTVName == name {
            CompanionSettings.preferredTVName = nil
        }

        reloadKnownTVs()
        onLibrariesChanged?()
    }
}
