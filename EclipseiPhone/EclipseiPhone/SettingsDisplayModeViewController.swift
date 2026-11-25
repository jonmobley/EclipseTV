//
//  SettingsDisplayModeViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Chooses AirPlay / external-display orientation, vertical rotation, and the
/// custom screen size that letterboxes the Landscape picture to an odd surface.
final class SettingsDisplayModeViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case orientation
        case rotation
        case screenSize
        case connectedScreen
    }

    /// Rows of the Screen Size section: full screen, one per custom size, then Add.
    private enum ScreenSizeRow {
        case fullScreen
        case custom(ExternalOutputCustomSize)
        case add
    }

    /// Rows of the Connected Screen section.
    private enum ConnectedScreenRow {
        case signal(String)
        case use(ExternalScreenSignal.PixelSize)
        case alsoOffered(String)
    }

    /// Set while this controller applies its own row edit, so the settings
    /// notification that edit posts does not reload the table mid-update
    /// (UIKit throws when a reload lands inside a swipe-to-delete commit).
    private var isApplyingRowEdit = false

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
        // A screen was plugged in or removed: the Connected Screen section follows.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: ExternalDisplayManager.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reload() {
        guard !isApplyingRowEdit else { return }
        tableView.reloadData()
    }

    // MARK: - Sections

    /// Rotation only matters in Vertical; custom sizes only apply in Landscape.
    private var visibleSections: [Section] {
        let sections: [Section] = ExternalOutputSettings.isVerticalMode
            ? [.orientation, .rotation]
            : [.orientation, .screenSize]
        return ExternalOutputSettings.connectedScreenSignal == nil
            ? sections
            : sections + [.connectedScreen]
    }

    /// Rows of the Connected Screen section: the signal, one tappable row per
    /// odd-shaped size the screen also offers (an LED wall's other widths), then
    /// the ordinary TV sizes as plain text.
    private var connectedScreenRows: [ConnectedScreenRow] {
        guard let signal = ExternalOutputSettings.connectedScreenSignal else { return [] }
        // Custom sizes apply in Landscape only, so the choices show there only.
        let choices = ExternalOutputSettings.isVerticalMode ? [] : signal.selectableOffered
        let plain = signal.otherOffered.filter { !choices.contains($0) }.map(\.label)
        return [.signal(signal.current.label)]
            + choices.map { .use($0) }
            + (plain.isEmpty ? [] : [.alsoOffered(plain.joined(separator: ", "))])
    }

    private func connectedScreenRow(at row: Int) -> ConnectedScreenRow? {
        let rows = connectedScreenRows
        return rows.indices.contains(row) ? rows[row] : nil
    }

    private func section(at index: Int) -> Section? {
        visibleSections.indices.contains(index) ? visibleSections[index] : nil
    }

    private var screenSizeRows: [ScreenSizeRow] {
        [.fullScreen] + ExternalOutputSettings.customSizes.map { .custom($0) } + [.add]
    }

    private func screenSizeRow(at row: Int) -> ScreenSizeRow? {
        let rows = screenSizeRows
        return rows.indices.contains(row) ? rows[row] : nil
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch self.section(at: section) {
        case .orientation: return ExternalOutputOrientation.allCases.count
        case .rotation: return ExternalRotationDirection.allCases.count
        case .screenSize: return screenSizeRows.count
        case .connectedScreen: return connectedScreenRows.count
        case .none: return 0
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch self.section(at: section) {
        case .orientation: return "Orientation"
        case .rotation: return "Vertical Rotation"
        case .screenSize: return "Screen Size"
        case .connectedScreen: return "Connected Screen"
        case .none: return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        switch self.section(at: section) {
        case .orientation:
            return """
            Landscape is 16:9. Vertical is 9:16 for a portrait-mounted TV. \
            Each Show and its media belong to one mode — switching hides the other \
            mode’s Shows (they are not deleted). Open any Show to switch to its mode.
            """
        case .rotation:
            return "Which way the image rotates for a vertically mounted display."
        case .screenSize:
            return """
            For a screen that is not 16:9, such as an LED wall, enter its size. \
            The AirPlay picture is fitted to that shape with black around it, and the \
            phone frames content the same way. Only the proportions matter. \
            Swipe a size to delete it; tap ⓘ to edit.
            """
        case .connectedScreen:
            return connectedScreenFooter
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

        switch section(at: indexPath.section) {
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
        case .screenSize:
            switch screenSizeRow(at: indexPath.row) {
            case .fullScreen:
                config.text = ExternalOutputSettings.fullScreenLabel
                cell.accessoryType =
                    ExternalOutputSettings.activeCustomSize == nil ? .checkmark : .none
            case .custom(let size):
                config.text = size.name
                config.secondaryText = size.sizeLabel
                cell.accessoryType = .detailButton
                // The checkmark is drawn as an image so the ⓘ edit button stays.
                config.image = ExternalOutputSettings.activeCustomSize?.id == size.id
                    ? UIImage(systemName: "checkmark")
                    : UIImage(systemName: "rectangle.dashed")
                config.imageProperties.tintColor = ExternalOutputSettings.activeCustomSize?.id == size.id
                    ? view.tintColor : .secondaryLabel
            case .add:
                config.text = "Add Custom Size…"
                config.textProperties.color = view.tintColor
            case .none:
                break
            }
        case .connectedScreen:
            config = connectedScreenContent(at: indexPath.row, cell: cell)
        case .none:
            break
        }

        cell.contentConfiguration = config
        return cell
    }

    /// Content for a Connected Screen row; only the "Use" rows can be tapped.
    private func connectedScreenContent(at row: Int, cell: UITableViewCell) -> UIListContentConfiguration {
        var config = UIListContentConfiguration.valueCell()
        cell.selectionStyle = .none
        switch connectedScreenRow(at: row) {
        case .signal(let size):
            config.text = "Signal"
            config.secondaryText = size
        case .use(let size):
            config = cell.defaultContentConfiguration()
            config.text = "Use \(size.label)"
            config.textProperties.color = view.tintColor
            cell.selectionStyle = .default
        case .alsoOffered(let sizes):
            config.text = "Also Offered"
            config.secondaryText = sizes
        case .none:
            break
        }
        return config
    }

    private var connectedScreenFooter: String {
        guard let signal = ExternalOutputSettings.connectedScreenSignal, signal.oddShape != nil else {
            return "The size this device is sending to the screen."
        }
        let fills = "This screen is not 16:9, so Full Screen fills its real size and every dot of the signal is used."
        return connectedScreenRows.contains { if case .use = $0 { true } else { false } }
            ? fills + " Tap another size to send that one instead."
            : fills
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch section(at: indexPath.section) {
        case .orientation:
            ExternalOutputSettings.orientation =
                ExternalOutputOrientation.allCases[indexPath.row]
        case .rotation:
            ExternalOutputSettings.rotationDirection =
                ExternalRotationDirection.allCases[indexPath.row]
        case .screenSize:
            switch screenSizeRow(at: indexPath.row) {
            case .fullScreen:
                ExternalOutputSettings.selectedCustomSizeID = nil
                ExternalDisplayManager.shared.refreshScreenSignal()
            case .custom(let size):
                ExternalOutputSettings.selectedCustomSizeID = size.id
                // If the screen offers exactly this size, send it.
                ExternalDisplayManager.shared.refreshScreenSignal()
            case .add:
                presentSizeEditor(editing: nil)
            case .none:
                break
            }
        case .connectedScreen:
            guard case .use(let size)? = connectedScreenRow(at: indexPath.row) else { break }
            // Saved as the active custom size, so it is sent again on the next connect.
            ExternalOutputSettings.useCustomSize(width: size.width, height: size.height)
            ExternalDisplayManager.shared.refreshScreenSignal()
        case .none:
            break
        }
    }

    override func tableView(
        _ tableView: UITableView,
        accessoryButtonTappedForRowWith indexPath: IndexPath
    ) {
        guard section(at: indexPath.section) == .screenSize,
              case .custom(let size)? = screenSizeRow(at: indexPath.row) else { return }
        presentSizeEditor(editing: size)
    }

    override func tableView(
        _ tableView: UITableView,
        canEditRowAt indexPath: IndexPath
    ) -> Bool {
        guard section(at: indexPath.section) == .screenSize,
              case .custom? = screenSizeRow(at: indexPath.row) else { return false }
        return true
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete,
              case .custom(let size)? = screenSizeRow(at: indexPath.row) else { return }
        let wasActive = ExternalOutputSettings.activeCustomSize?.id == size.id
        isApplyingRowEdit = true
        ExternalOutputSettings.removeCustomSize(id: size.id)
        isApplyingRowEdit = false
        tableView.deleteRows(at: [indexPath], with: .automatic)
        if wasActive {
            // Full Screen takes the checkmark back.
            tableView.reloadRows(
                at: [IndexPath(row: 0, section: indexPath.section)], with: .none
            )
        }
    }

    // MARK: - Editor

    /// Name / width / height alert. Save stays disabled until both edges are ≥ 2.
    private func presentSizeEditor(editing size: ExternalOutputCustomSize?) {
        let alert = UIAlertController(
            title: size == nil ? "Add Custom Size" : "Edit Custom Size",
            message: "Enter the screen’s width and height. Only the proportions matter.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Name (optional)"
            field.text = size?.name
            field.autocapitalizationType = .words
        }
        alert.addTextField { field in
            field.placeholder = "Width"
            field.text = size.map { String($0.width) } ?? "1920"
            field.keyboardType = .numberPad
        }
        alert.addTextField { field in
            field.placeholder = "Height"
            field.text = size.map { String($0.height) } ?? "1080"
            field.keyboardType = .numberPad
        }

        let save = UIAlertAction(title: "Save", style: .default) { [weak alert] _ in
            guard let fields = alert?.textFields, fields.count == 3,
                  let (width, height) = Self.parsedSize(fields[1].text, fields[2].text)
            else { return }
            let name = fields[0].text ?? ""
            if let size {
                ExternalOutputSettings.updateCustomSize(
                    id: size.id, name: name, width: width, height: height
                )
            } else {
                ExternalOutputSettings.addCustomSize(name: name, width: width, height: height)
            }
            // A new or edited size may now match one the screen offers: send it.
            ExternalDisplayManager.shared.refreshScreenSignal()
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(save)
        alert.preferredAction = save

        let refreshSave: (UITextField) -> Void = { [weak alert] _ in
            guard let fields = alert?.textFields, fields.count == 3 else { return }
            save.isEnabled = Self.parsedSize(fields[1].text, fields[2].text) != nil
        }
        for field in alert.textFields?.dropFirst() ?? [] {
            field.addAction(UIAction { action in
                if let field = action.sender as? UITextField { refreshSave(field) }
            }, for: .editingChanged)
        }
        present(alert, animated: true)
    }

    /// Both fields as whole numbers of at least 2, else nil.
    static func parsedSize(_ widthText: String?, _ heightText: String?) -> (Int, Int)? {
        guard let width = Int((widthText ?? "").trimmingCharacters(in: .whitespaces)),
              let height = Int((heightText ?? "").trimmingCharacters(in: .whitespaces)),
              ExternalOutputCustomSize.isValid(width: width, height: height)
        else { return nil }
        return (width, height)
    }
}
