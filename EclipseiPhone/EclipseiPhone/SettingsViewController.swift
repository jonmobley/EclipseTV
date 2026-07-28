//
//  SettingsViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Companion settings: display mode, Eclipse TV app link, library sync, and known TVs.
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
        case displayMode
        case transition
        case cameraClose
        case join
        case eclipseTV
        case sync
        case appleTVs
    }

    private let syncAllTVsKey = "EclipseTV.companion.syncAllTVs"
    private let preferredTVNameKey = "EclipseTV.companion.preferredTVName"

    private var knownTVs: [KnownTV] = []

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
        reloadKnownTVs()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayModeDidChange),
            name: ExternalOutputSettings.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Updates the Eclipse TV App section for the current Multipeer link state.
    func setConnectionState(_ state: ConnectionDisplayState) {
        connectionState = state
        guard isViewLoaded else { return }
        let section = IndexSet(integer: Section.eclipseTV.rawValue)
        tableView.reloadSections(section, with: .none)
    }

    /// Scrolls the Eclipse TV App section into view (e.g. after opening from Ready).
    func scrollToEclipseTVSection() {
        guard isViewLoaded else { return }
        let section = Section.eclipseTV.rawValue
        guard tableView.numberOfRows(inSection: section) > 0 else { return }
        let indexPath = IndexPath(row: 0, section: section)
        tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
    }

    private func makeCopyrightFooter() -> UIView {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let label = UILabel()
        label.text = "Eclipse \(version)\nCopyright © 2026 Moxie LLC. All rights reserved."
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 56)
        return label
    }

    private func reloadKnownTVs() {
        knownTVs = KnownTVRegistry.shared.all()
        tableView.reloadData()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func displayModeDidChange() {
        tableView.reloadSections(
            IndexSet(arrayLiteral:
                Section.displayMode.rawValue,
                Section.transition.rawValue,
                Section.cameraClose.rawValue
            ),
            with: .none
        )
    }

    // MARK: - Table Data

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .displayMode:
            return ExternalOutputSettings.isVerticalMode
                ? ExternalOutputOrientation.allCases.count + ExternalRotationDirection.allCases.count
                : ExternalOutputOrientation.allCases.count
        case .transition:
            return ContentTransitionStyle.allCases.count
        case .cameraClose:
            return CameraCloseDestination.allCases.count
        case .join:
            return 1
        case .eclipseTV:
            switch connectionState {
            case .connected: return 1
            case .disconnected: return 2
            case .paused: return 1
            }
        case .sync: return 1
        case .appleTVs: return max(knownTVs.count, 1)
        case .none: return 0
        }
    }

    override func tableView(_ tableView: UITableView,
                            titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .displayMode: return "Display Mode"
        case .transition: return "Content Transition"
        case .cameraClose: return "When Camera Closes"
        case .join: return "Shared Presentation"
        case .eclipseTV: return "EclipseTV"
        case .sync: return "Sync"
        case .appleTVs: return "Apple TVs"
        case .none: return nil
        }
    }

    override func tableView(_ tableView: UITableView,
                            titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .displayMode:
            return "Landscape is 16:9. Vertical is 9:16 for a portrait-mounted TV. Home shows Black, Logo, Camera, and your Shows. Linking EclipseTV syncs media across Shows."
        case .transition:
            return "Previous live content (including camera/video) stays up while the next item prepares. Cut reveals instantly when ready; Crossfade dissolves the next layer over it."
        case .cameraClose:
            return "After you close the camera screen, keep the live camera or switch AirPlay to Logo or Black."
        case .join:
            return "Enter a join code to open a shared cloud presentation on this iPhone. AirPlay works without EclipseTV. Linking EclipseTV also syncs that join code to the room display."
        case .eclipseTV:
            return "Optional link to the Eclipse app on Apple TV for media sync. Separate from AirPlay and from the join code. Camera, Join, Web, and PDF still work over AirPlay without this."
        case .sync:
            return "When on, media changes are sent to every Apple TV you're linked to with EclipseTV, and newly linked TVs are caught up to match. Only media you've sent from this iPhone can be mirrored to other TVs."
        case .appleTVs:
            return "Tap a TV to view its Shows. Swipe to remove and clear its cached media on this iPhone."
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .displayMode: return displayModeCell(at: indexPath.row)
        case .transition: return transitionCell(at: indexPath.row)
        case .cameraClose: return cameraCloseCell(at: indexPath.row)
        case .join: return joinCell()
        case .eclipseTV: return eclipseTVCell(at: indexPath.row)
        case .sync: return syncCell()
        case .appleTVs: return appleTVCell(at: indexPath)
        case .none: return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .displayMode:
            selectDisplayMode(at: indexPath.row)
        case .transition:
            ExternalOutputSettings.contentTransition =
                ContentTransitionStyle.allCases[indexPath.row]
            tableView.reloadSections(
                IndexSet(integer: Section.transition.rawValue), with: .none
            )
        case .cameraClose:
            ExternalOutputSettings.cameraCloseDestination =
                CameraCloseDestination.allCases[indexPath.row]
            tableView.reloadSections(
                IndexSet(integer: Section.cameraClose.rawValue), with: .none
            )
        case .join:
            onJoinPresentation?()
        case .eclipseTV:
            handleEclipseTVAction(at: indexPath.row)
        case .appleTVs:
            guard !knownTVs.isEmpty else { return }
            onSelectTV?(knownTVs[indexPath.row].name)
            tableView.reloadSections(IndexSet(integer: Section.appleTVs.rawValue), with: .none)
        case .sync, .none:
            break
        }
    }

    // MARK: - Display Mode

    private func displayModeCell(at row: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let modes = ExternalOutputOrientation.allCases
        if row < modes.count {
            let mode = modes[row]
            cell.textLabel?.text = mode.rawValue
            cell.accessoryType = ExternalOutputSettings.orientation == mode ? .checkmark : .none
        } else {
            let rotation = ExternalRotationDirection.allCases[row - modes.count]
            cell.textLabel?.text = rotation.rawValue
            cell.accessoryType =
                ExternalOutputSettings.rotationDirection == rotation ? .checkmark : .none
        }
        cell.selectionStyle = .default
        return cell
    }

    private func selectDisplayMode(at row: Int) {
        let modes = ExternalOutputOrientation.allCases
        if row < modes.count {
            ExternalOutputSettings.orientation = modes[row]
        } else {
            ExternalOutputSettings.rotationDirection =
                ExternalRotationDirection.allCases[row - modes.count]
        }
    }

    private func transitionCell(at row: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let style = ContentTransitionStyle.allCases[row]
        cell.textLabel?.text = style.rawValue
        cell.accessoryType =
            ExternalOutputSettings.contentTransition == style ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }

    private func cameraCloseCell(at row: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let destination = CameraCloseDestination.allCases[row]
        cell.textLabel?.text = destination.rawValue
        cell.accessoryType =
            ExternalOutputSettings.cameraCloseDestination == destination
            ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }

    // MARK: - Join / Eclipse TV App

    private func joinCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .default
        let joined = AlbumBrowserStore.shared.hasAccountConfigured
        cell.textLabel?.text = joined ? "Open Joined Presentation…" : "Join Presentation…"
        cell.imageView?.image = UIImage(systemName: "person.2.badge.key")
        cell.imageView?.tintColor = .label
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func eclipseTVCell(at row: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .default
        switch connectionState {
        case .connected:
            cell.textLabel?.text = "Linked"
            cell.imageView?.image = UIImage(systemName: "checkmark.circle.fill")
            cell.imageView?.tintColor = .systemGreen
            cell.selectionStyle = .none
            return cell
        case .disconnected:
            if row == 0 {
                cell.textLabel?.text = "Connect / Enter Pairing Code…"
                cell.imageView?.image = UIImage(systemName: "wifi")
            } else {
                cell.textLabel?.text = "Stop Connecting to EclipseTV"
                cell.imageView?.image = UIImage(systemName: "pause.circle")
            }
        case .paused:
            cell.textLabel?.text = "Connect EclipseTV…"
            cell.imageView?.image = UIImage(systemName: "wifi")
        }
        cell.imageView?.tintColor = .label
        return cell
    }

    private func handleEclipseTVAction(at row: Int) {
        switch connectionState {
        case .connected:
            break
        case .disconnected:
            if row == 0 { onConnect?() } else { onStopConnecting?() }
        case .paused:
            onConnect?()
        }
    }

    // MARK: - Sync / Apple TVs

    private func syncCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "Keep all Apple TVs in sync"
        cell.selectionStyle = .none

        let toggle = UISwitch()
        toggle.isOn = UserDefaults.standard.bool(forKey: syncAllTVsKey)
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
        UserDefaults.standard.set(sender.isOn, forKey: syncAllTVsKey)
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
        let action = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, done in
            self?.confirmForgetTV(at: indexPath, completion: done)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    private func confirmForgetTV(at indexPath: IndexPath, completion: @escaping (Bool) -> Void) {
        let tv = knownTVs[indexPath.row]
        let alert = UIAlertController(
            title: "Remove \(tv.name)?",
            message: "Clears this Apple TV from the list and removes its cached media on this iPhone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(false)
        })
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
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

        if UserDefaults.standard.string(forKey: preferredTVNameKey) == name {
            UserDefaults.standard.removeObject(forKey: preferredTVNameKey)
        }

        reloadKnownTVs()
        onLibrariesChanged?()
    }
}
