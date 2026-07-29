//
//  CameraSettingsViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Camera-page settings: Frames and When Camera Closes.
final class CameraSettingsViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case frames
        case cameraClose
    }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Camera"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: ExternalOutputSettings.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: CameraFrameStore.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    @objc private func reload() {
        tableView.reloadData()
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        switch Section(rawValue: section) {
        case .frames:
            return 1
        case .cameraClose:
            return CameraCloseDestination.allCases.count
        case .none:
            return 0
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch Section(rawValue: section) {
        case .cameraClose:
            return "When Camera Closes"
        case .frames, .none:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        switch Section(rawValue: section) {
        case .cameraClose:
            return "When you slide the shutter off live, switch AirPlay to Logo, "
                + "Black, or whatever was live before the camera."
        case .frames, .none:
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
        case .frames:
            config.text = "Frames"
            config.secondaryText = frameSummary()
            config.image = UIImage(systemName: "rectangle.dashed")
            cell.accessoryType = .disclosureIndicator
        case .cameraClose:
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
        case .none:
            break
        }

        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .frames:
            navigationController?.pushViewController(
                CameraFramePickerViewController(), animated: true
            )
        case .cameraClose:
            ExternalOutputSettings.cameraCloseDestination =
                CameraCloseDestination.allCases[indexPath.row]
        case .none:
            break
        }
    }

    private func frameSummary() -> String {
        CameraFrameStore.shared.selectedImage == nil ? "None" : "Selected"
    }
}
