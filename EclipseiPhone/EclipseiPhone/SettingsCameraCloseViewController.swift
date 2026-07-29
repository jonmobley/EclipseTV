//
//  SettingsCameraCloseViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Chooses what AirPlay shows after the camera control screen is dismissed.
final class SettingsCameraCloseViewController: UITableViewController {

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "When Camera Closes"
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

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        CameraCloseDestination.allCases.count
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        "When you slide the shutter off live, switch AirPlay to Logo, Black, or "
            + "whatever was live before the camera."
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        let destination = CameraCloseDestination.allCases[indexPath.row]
        config.text = destination.rawValue
        switch destination {
        case .previous:
            config.secondaryText = "Restore what was on AirPlay before camera"
        case .logo, .black:
            config.secondaryText = nil
        }
        cell.accessoryType =
            ExternalOutputSettings.cameraCloseDestination == destination
            ? .checkmark : .none
        cell.selectionStyle = .default
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        ExternalOutputSettings.cameraCloseDestination =
            CameraCloseDestination.allCases[indexPath.row]
    }
}
