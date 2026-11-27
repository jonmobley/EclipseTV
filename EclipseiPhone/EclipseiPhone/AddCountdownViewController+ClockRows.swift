//
//  AddCountdownViewController+ClockRows.swift
//  Eclipse
//
//  Mode, To Time target, Caption and "Card behind numbers" rows of the Add
//  Countdown screen.
//  Thread Safety: Main-actor UIKit.
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Clock Rows

extension AddCountdownViewController {

    /// Cell for the Mode, Count Down To, Caption and plate sections.
    func clockCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section] {
        case .mode:
            return modeCell(tableView, at: indexPath)
        case .target:
            return targetRows.cell(
                for: targetRows.rows[indexPath.row], in: tableView, at: indexPath
            )
        case .caption:
            let cell = tableView.dequeueReusableCell(withIdentifier: "field", for: indexPath)
            cell.selectionStyle = .none
            install(captionField, in: cell)
            return cell
        default:
            return plateCell(tableView, at: indexPath)
        }
    }

    // MARK: - Private

    /// Mode choice with the Mac's one-line explanation under each title.
    private func modeCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        let mode = CountdownMode.allCases[indexPath.row]
        var config = UIListContentConfiguration.subtitleCell()
        config.text = mode.title
        config.secondaryText = mode.explanation
        config.secondaryTextProperties.color = .secondaryLabel
        config.image = UIImage(systemName: mode.systemImage)
        cell.contentConfiguration = config
        cell.accessoryType = mode == draft.clock.mode ? .checkmark : .none
        cell.accessibilityTraits = mode == draft.clock.mode ? [.button, .selected] : .button
        return cell
    }

    /// "Card behind numbers" switch, on by default like the Mac.
    private func plateCell(_ tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: CountdownTargetRows.reuseId, for: indexPath
        )
        var config = cell.defaultContentConfiguration()
        config.text = "Card behind numbers"
        config.image = UIImage(systemName: "rectangle.fill")
        cell.contentConfiguration = config
        let toggle = (cell.accessoryView as? UISwitch) ?? UISwitch()
        toggle.removeTarget(nil, action: nil, for: .valueChanged)
        toggle.isOn = draft.clock.showsPlate
        toggle.accessibilityLabel = "Card behind numbers"
        toggle.addTarget(self, action: #selector(plateSwitchChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        cell.selectionStyle = .none
        return cell
    }
}
