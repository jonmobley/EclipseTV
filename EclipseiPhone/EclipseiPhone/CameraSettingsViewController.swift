//
//  CameraSettingsViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Camera-page settings: shutter guide, frame burn-in, and When Camera Closes.
///
/// Frame picking / import lives on the camera Frame button drawer, not here.
final class CameraSettingsViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case buttonGuide
        case frameCaptures
        case cameraClose
    }

    private static let buttonGuideRows = [
        "Slide button to toggle LIVE",
        "Tap button to take a photo",
        "Hold down to start/stop recording"
    ]

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
        case .buttonGuide:
            return Self.buttonGuideRows.count
        case .frameCaptures:
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
        case .buttonGuide:
            return "Button Guide"
        case .frameCaptures:
            return "Frames"
        case .cameraClose:
            return "When Camera Closes"
        case .none:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        switch Section(rawValue: section) {
        case .frameCaptures:
            return "When on, the selected frame is saved into photos and video recordings. "
                + "Live view always shows the frame. Choose frames with the Frame button."
        case .cameraClose:
            return "When you slide the shutter off live, switch AirPlay to Background, "
                + "Black, or whatever was live before the camera."
        case .buttonGuide, .none:
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
        cell.accessoryType = .none
        cell.accessoryView = nil
        config.secondaryText = nil
        config.image = nil

        switch Section(rawValue: indexPath.section) {
        case .buttonGuide:
            config.text = Self.buttonGuideRows[indexPath.row]
            config.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
        case .frameCaptures:
            config.text = "Include in Photos & Videos"
            config.textProperties.color = .label
            config.image = UIImage(systemName: "square.and.arrow.down")
            cell.selectionStyle = .none
            let toggle = UISwitch()
            toggle.isOn = ExternalOutputSettings.includeFrameInCaptures
            toggle.addTarget(
                self,
                action: #selector(includeFrameToggleChanged(_:)),
                for: .valueChanged
            )
            cell.accessoryView = toggle
        case .cameraClose:
            let destination = CameraCloseDestination.allCases[indexPath.row]
            config.text = destination.rawValue
            config.textProperties.color = .label
            switch destination {
            case .previous:
                config.secondaryText = "Show what was previously live"
            case .logo, .black:
                break
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
        case .cameraClose:
            ExternalOutputSettings.cameraCloseDestination =
                CameraCloseDestination.allCases[indexPath.row]
        case .buttonGuide, .frameCaptures, .none:
            break
        }
    }

    @objc private func includeFrameToggleChanged(_ sender: UISwitch) {
        ExternalOutputSettings.includeFrameInCaptures = sender.isOn
    }
}
