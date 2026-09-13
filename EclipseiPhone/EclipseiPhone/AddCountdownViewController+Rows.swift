//
//  AddCountdownViewController+Rows.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Table

extension AddCountdownViewController {

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        switch sections[section] {
        case .name, .layout: return 1
        case .duration: return CountdownController.durationPresets.count + 1
        case .background: return CountdownBackgroundOption.fixed.count
        case .showMedia: return showMedia.count
        case .ending: return CountdownEndAction.allCases.count
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch sections[section] {
        case .name: return "Name"
        case .duration: return "Duration"
        case .layout: return "Size & Placement"
        case .background: return "Background"
        case .showMedia: return "From This Show"
        case .ending: return "When It Ends"
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        switch sections[section] {
        case .duration:
            return "Custom accepts minutes, m:ss, or h:mm:ss."
        case .layout:
            return "Drag and pinch the clock to where it should sit on the projector."
        case .background:
            if sections.contains(.showMedia) { return nil }
            return "Photos and videos in this Show appear here once they are on this device."
        case .ending:
            return "What the projector does when the clock reaches 0:00."
        case .name, .showMedia:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .name:
            let cell = tableView.dequeueReusableCell(withIdentifier: "field", for: indexPath)
            cell.selectionStyle = .none
            install(nameField, in: cell)
            return cell
        case .duration:
            return durationCell(tableView, at: indexPath)
        case .layout:
            let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
            var config = UIListContentConfiguration.valueCell()
            config.text = "Edit Size & Placement"
            config.secondaryText = draft.layoutSummary
            config.image = UIImage(systemName: "slider.horizontal.3")
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            return cell
        case .background:
            return optionCell(
                tableView, at: indexPath,
                option: CountdownBackgroundOption.fixed[indexPath.row]
            )
        case .showMedia:
            return optionCell(tableView, at: indexPath, option: showMedia[indexPath.row])
        case .ending:
            return endingCell(tableView, at: indexPath)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        nameField.resignFirstResponder()
        switch sections[indexPath.section] {
        case .name:
            nameField.becomeFirstResponder()
        case .duration:
            selectDuration(at: indexPath.row)
        case .layout:
            presentLayoutEditor()
        case .background:
            select(CountdownBackgroundOption.fixed[indexPath.row])
        case .showMedia:
            select(showMedia[indexPath.row])
        case .ending:
            select(CountdownEndAction.allCases[indexPath.row])
        }
    }

    // MARK: - Cells

    private func durationCell(
        _ tableView: UITableView,
        at indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        let presets = CountdownController.durationPresets
        var config = cell.defaultContentConfiguration()
        let selected: Bool
        if presets.indices.contains(indexPath.row) {
            let seconds = presets[indexPath.row]
            config.text = CountdownController.displayString(seconds: seconds)
            config.image = UIImage(systemName: "timer")
            selected = draft.duration == seconds
        } else {
            // Custom… shows the chosen length once it is not a preset.
            selected = !draft.isPresetDuration
            config.text = selected ? draft.durationText : "Custom…"
            config.image = UIImage(systemName: "pencil")
        }
        cell.contentConfiguration = config
        cell.accessoryType = selected ? .checkmark : .none
        return cell
    }

    private func optionCell(
        _ tableView: UITableView,
        at indexPath: IndexPath,
        option: CountdownBackgroundOption
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = option.title
        config.image = option.image(glyphSize: CountdownBackgroundGlyph.rowSize)
        // Symbol and thumbnail rows share one column so titles line up.
        config.imageProperties.reservedLayoutSize = CountdownBackgroundGlyph.rowSize
        config.imageProperties.maximumSize = CountdownBackgroundGlyph.rowSize
        cell.contentConfiguration = config
        cell.accessoryType = option.background == draft.background ? .checkmark : .none
        return cell
    }

    private func endingCell(
        _ tableView: UITableView,
        at indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        let action = CountdownEndAction.allCases[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = action.title
        config.image = UIImage(systemName: action.systemImage)
        cell.contentConfiguration = config
        cell.accessoryType = action == draft.endAction ? .checkmark : .none
        return cell
    }

    private func install(_ field: UITextField, in cell: UITableViewCell) {
        field.removeFromSuperview()
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(
                equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor
            ),
            field.trailingAnchor.constraint(
                equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor
            ),
            field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            field.bottomAnchor.constraint(
                equalTo: cell.contentView.bottomAnchor, constant: -12
            )
        ])
    }
}
