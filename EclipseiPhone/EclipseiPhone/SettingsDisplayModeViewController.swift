//
//  SettingsDisplayModeViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Chooses AirPlay / external-display orientation and vertical rotation.
final class SettingsDisplayModeViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case orientation
        case rotation
    }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Display Mode"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: ExternalOutputSettings.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reload() {
        tableView.reloadData()
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        ExternalOutputSettings.isVerticalMode ? Section.allCases.count : 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .orientation: return ExternalOutputOrientation.allCases.count
        case .rotation: return ExternalRotationDirection.allCases.count
        case .none: return 0
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch Section(rawValue: section) {
        case .orientation: return "Orientation"
        case .rotation: return "Vertical Rotation"
        case .none: return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        switch Section(rawValue: section) {
        case .orientation:
            return "Landscape is 16:9. Vertical is 9:16 for a portrait-mounted TV."
        case .rotation:
            return "Which way the image rotates for a vertically mounted display."
        case .none:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.selectionStyle = .default

        switch Section(rawValue: indexPath.section) {
        case .orientation:
            let mode = ExternalOutputOrientation.allCases[indexPath.row]
            config.text = mode.rawValue
            cell.accessoryType =
                ExternalOutputSettings.orientation == mode ? .checkmark : .none
        case .rotation:
            let rotation = ExternalRotationDirection.allCases[indexPath.row]
            config.text = rotation.rawValue
            cell.accessoryType =
                ExternalOutputSettings.rotationDirection == rotation ? .checkmark : .none
        case .none:
            break
        }

        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .orientation:
            ExternalOutputSettings.orientation =
                ExternalOutputOrientation.allCases[indexPath.row]
        case .rotation:
            ExternalOutputSettings.rotationDirection =
                ExternalRotationDirection.allCases[indexPath.row]
        case .none:
            break
        }
    }
}
