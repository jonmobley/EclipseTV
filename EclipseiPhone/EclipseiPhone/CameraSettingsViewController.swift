//
//  CameraSettingsViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Camera-page settings: shutter guide, recording, and frame burn-in.
///
/// Frame picking / import lives on the camera Frame button drawer, not here.
final class CameraSettingsViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case buttonGuide
        case recording
        case frameCaptures
    }

    private var buttonGuideRows: [String] {
        var rows = [
            "Tap preview to go LIVE",
            "Tap shutter to take a photo"
        ]
        if !ExternalOutputSettings.alwaysRecordWhenLive {
            rows.append("Hold shutter to start/stop recording")
        }
        return rows
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
            return buttonGuideRows.count
        case .recording, .frameCaptures:
            return 1
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
        case .recording:
            return "Recording"
        case .frameCaptures:
            return "Frames"
        case .none:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        switch Section(rawValue: section) {
        case .recording:
            return "When on, video recording starts as soon as the camera goes live "
                + "and stops when you switch to the cutaway or another source. "
                + "Tap shutter still takes a photo."
        case .frameCaptures:
            return "When on, the selected frame is saved into photos and video recordings. "
                + "Live view always shows the frame. Choose frames with the Frame button."
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
            config.text = buttonGuideRows[indexPath.row]
            config.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
        case .recording:
            config.text = "Always Record When Live"
            config.textProperties.color = .label
            config.image = UIImage(systemName: "video.fill")
            cell.selectionStyle = .none
            let toggle = UISwitch()
            toggle.isOn = ExternalOutputSettings.alwaysRecordWhenLive
            toggle.addTarget(
                self,
                action: #selector(alwaysRecordToggleChanged(_:)),
                for: .valueChanged
            )
            cell.accessoryView = toggle
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
        case .none:
            break
        }

        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .buttonGuide, .recording, .frameCaptures, .none:
            break
        }
    }

    @objc private func alwaysRecordToggleChanged(_ sender: UISwitch) {
        ExternalOutputSettings.alwaysRecordWhenLive = sender.isOn
        // Button Guide drops/restores the hold-to-record tip when this changes.
        tableView.reloadSections(
            IndexSet(integer: Section.buttonGuide.rawValue),
            with: .automatic
        )
    }

    @objc private func includeFrameToggleChanged(_ sender: UISwitch) {
        ExternalOutputSettings.includeFrameInCaptures = sender.isOn
    }
}
