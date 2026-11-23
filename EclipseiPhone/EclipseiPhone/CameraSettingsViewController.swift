//
//  CameraSettingsViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Camera-page settings: recording and frame burn-in.
///
/// Frame picking / import lives on the camera Frame button drawer, not here.
/// In Camera Mode it also holds the Mac link and Exit Camera Mode (see
/// `cameraModeActions` and `CameraSettingsViewController+CameraMode.swift`).
final class CameraSettingsViewController: UITableViewController {

    enum Section {
        case recording
        case frameCaptures
        case mac
        case cameraMode
    }

    /// Set in Camera Mode: adds the Mac and Camera Mode sections. Nil hides them.
    var cameraModeActions: CameraModeSettingsActions?

    /// Sections shown, in order.
    var sections: [Section] {
        cameraModeActions == nil
            ? [.recording, .frameCaptures]
            : [.recording, .frameCaptures, .mac, .cameraMode]
    }

    private func section(at index: Int) -> Section? {
        sections.indices.contains(index) ? sections[index] : nil
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
            name: CameraOperatorMode.didChangeNotification,
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
        sections.count
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        switch self.section(at: section) {
        case .recording, .frameCaptures, .cameraMode:
            return 1
        case .mac:
            return macRowCount
        case .none:
            return 0
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch self.section(at: section) {
        case .recording:
            return "Recording"
        case .frameCaptures:
            return "Frames"
        case .mac:
            return "Mac"
        case .cameraMode:
            return "Camera Mode"
        case .none:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        switch self.section(at: section) {
        case .recording:
            return "When on, video recording starts as soon as the camera goes live "
                + "and stops when you switch to the cutaway or another source. "
                + "The photo button still takes a picture while you record."
        case .frameCaptures:
            return "When on, the selected frame is saved into photos and video recordings. "
                + "Live view always shows the frame. Choose frames with the Frame button."
        case .mac:
            return CameraOperatorChromeText.settingsFooter(for: CameraOperatorMode.shared.macStatus)
        case .cameraMode:
            return CameraOperatorMode.shared.macStatus.isLinkedOrTrying
                ? "Stops sending this camera to the Mac and goes back to the Home screen."
                : "Goes back to the Home screen."
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
        cell.accessoryType = .none
        cell.accessoryView = nil
        config.secondaryText = nil
        config.image = nil

        switch section(at: indexPath.section) {
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
        case .mac:
            configureMacRow(&config, cell: cell, row: indexPath.row)
        case .cameraMode:
            configureExitRow(&config)
        case .none:
            break
        }

        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch section(at: indexPath.section) {
        case .mac: didSelectMacRow(indexPath.row)
        case .cameraMode: confirmExitCameraMode()
        default: break
        }
    }

    @objc private func alwaysRecordToggleChanged(_ sender: UISwitch) {
        ExternalOutputSettings.alwaysRecordWhenLive = sender.isOn
    }

    @objc private func includeFrameToggleChanged(_ sender: UISwitch) {
        ExternalOutputSettings.includeFrameInCaptures = sender.isOn
    }
}
