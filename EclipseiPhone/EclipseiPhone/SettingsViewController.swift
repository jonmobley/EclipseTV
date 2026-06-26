// SettingsViewController.swift
import UIKit

/// Companion settings: a (currently stubbed) toggle to keep every Apple TV's library
/// in sync, and management of the Apple TVs this phone has connected to.
final class SettingsViewController: UITableViewController {

    /// Invoked when the known-TV list changes (e.g. a TV is forgotten) so the host can
    /// refresh the header dropdown and grid.
    var onLibrariesChanged: (() -> Void)?

    private enum Section: Int, CaseIterable {
        case sync
        case appleTVs
    }

    /// Persists the (inert) "keep all Apple TVs in sync" preference.
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                            target: self,
                                                            action: #selector(doneTapped))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        reloadKnownTVs()
    }

    private func reloadKnownTVs() {
        knownTVs = KnownTVRegistry.shared.all()
        tableView.reloadData()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    // MARK: - Table Data

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .sync: return 1
        case .appleTVs: return max(knownTVs.count, 1)
        case .none: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .sync: return "Sync"
        case .appleTVs: return "Apple TVs"
        case .none: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .sync:
            return "When on, your library will be mirrored to every Apple TV you connect to so they all match. Coming soon."
        case .appleTVs:
            return "Removing an Apple TV clears its cached library on this iPhone."
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .sync:
            return syncCell()
        case .appleTVs:
            return appleTVCell(at: indexPath)
        case .none:
            return UITableViewCell()
        }
    }

    // MARK: - Cells

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

        if knownTVs.isEmpty {
            config.text = "No Apple TVs yet"
            config.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
        } else {
            let tv = knownTVs[indexPath.row]
            config.text = tv.name
            config.secondaryText = "Last seen " + tv.lastSeen.formatted(date: .abbreviated, time: .shortened)
            cell.selectionStyle = .none
        }

        cell.contentConfiguration = config
        return cell
    }

    // MARK: - Actions

    @objc private func syncToggleChanged(_ sender: UISwitch) {
        // Stubbed for now: the preference is persisted but no sync engine runs yet.
        UserDefaults.standard.set(sender.isOn, forKey: syncAllTVsKey)
    }

    // MARK: - Editing (swipe to forget a TV)

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return Section(rawValue: indexPath.section) == .appleTVs && !knownTVs.isEmpty
    }

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .appleTVs, !knownTVs.isEmpty else { return nil }
        let action = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, completion in
            self?.forgetTV(at: indexPath)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    private func forgetTV(at indexPath: IndexPath) {
        let tv = knownTVs[indexPath.row]
        KnownTVRegistry.shared.forget(name: tv.name)
        TVLibraryStore.shared.reset(tvName: tv.name)

        // If this was the preferred TV, clear the preference so we no longer hold out for it.
        if UserDefaults.standard.string(forKey: preferredTVNameKey) == tv.name {
            UserDefaults.standard.removeObject(forKey: preferredTVNameKey)
        }

        reloadKnownTVs()
        onLibrariesChanged?()
    }
}
