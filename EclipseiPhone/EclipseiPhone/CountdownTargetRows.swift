//
//  CountdownTargetRows.swift
//  Eclipse
//
//  Table rows for a To Time target: a time picker, an "On a date" switch with
//  its date picker, and a read-only zone line when the Mac chose a zone. Shared
//  by Add Countdown and the Set Time sheet so both edit the target the same way.
//  Thread Safety: Main-actor UIKit.
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Builds and drives the To Time rows for a table view.
@MainActor
final class CountdownTargetRows: NSObject {

    /// One row in the target section.
    enum Row: Equatable {
        case time
        case onDate
        case date
        case zone
    }

    /// Cell reuse id the host table registers (`UITableViewCell`) for these rows,
    /// kept apart from plain rows so a picker accessory never leaks onto one.
    static let reuseId = "countdownControl"

    /// Current settings; the pickers write into this.
    private(set) var settings: CountdownClockSettings
    /// Called after any picker or switch change. The flag is true when the row
    /// list changed (the date row came or went), so the table must reload.
    var onChange: ((CountdownClockSettings, Bool) -> Void)?

    private let timePicker = UIDatePicker()
    private let datePicker = UIDatePicker()
    private let dateSwitch = UISwitch()
    private let now: () -> Date

    /// - Parameters:
    ///   - settings: Starting values; a missing target gets the next whole hour.
    ///   - now: Clock, injectable for tests.
    init(settings: CountdownClockSettings, now: @escaping () -> Date = { Date() }) {
        var seeded = settings
        if seeded.targetMinutes == nil {
            seeded.targetMinutes = CountdownClockSettings.defaultTargetMinutes(after: now())
        }
        self.settings = seeded
        self.now = now
        super.init()
        configureControls()
    }

    /// Rows to show, in order.
    var rows: [Row] {
        var rows: [Row] = [.time, .onDate]
        if !settings.targetDay.isEmpty { rows.append(.date) }
        if settings.zoneDescription != nil { rows.append(.zone) }
        return rows
    }

    /// Footer under the rows.
    var footer: String {
        var text = CountdownMode.timeOfDay.explanation
        if settings.zoneDescription != nil {
            text += " The time zone was set on the Mac."
        }
        return text
    }

    /// A configured cell for `row`.
    func cell(for row: Row, in tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.reuseId, for: indexPath)
        cell.selectionStyle = .none
        cell.accessoryType = .none
        var config = cell.defaultContentConfiguration()
        switch row {
        case .time:
            config.text = "Time"
            config.image = UIImage(systemName: "clock")
            cell.accessoryView = timePicker
        case .onDate:
            config.text = "On a date"
            config.image = UIImage(systemName: "calendar")
            cell.accessoryView = dateSwitch
        case .date:
            config.text = "Date"
            config.image = UIImage(systemName: "calendar.badge.clock")
            cell.accessoryView = datePicker
        case .zone:
            config.text = "Time Zone"
            config.secondaryText = settings.zoneDescription
            config.image = UIImage(systemName: "globe")
            cell.accessoryView = nil
        }
        cell.contentConfiguration = config
        refreshControls()
        return cell
    }

    // MARK: - Private

    private func configureControls() {
        timePicker.datePickerMode = .time
        timePicker.preferredDatePickerStyle = .compact
        timePicker.accessibilityLabel = "Time"
        timePicker.addTarget(self, action: #selector(timeChanged), for: .valueChanged)
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.accessibilityLabel = "Date"
        datePicker.addTarget(self, action: #selector(dateChanged), for: .valueChanged)
        dateSwitch.accessibilityLabel = "On a date"
        dateSwitch.addTarget(self, action: #selector(dateSwitchChanged), for: .valueChanged)
        refreshControls()
    }

    /// Puts the settings into the controls, in the target's own zone.
    private func refreshControls() {
        let zone = settings.resolvedTimeZone
        timePicker.timeZone = zone
        datePicker.timeZone = zone
        let target = settings.targetDate(relativeTo: now()) ?? now()
        timePicker.setDate(target, animated: false)
        datePicker.setDate(target, animated: false)
        dateSwitch.isOn = !settings.targetDay.isEmpty
        timePicker.sizeToFit()
        datePicker.sizeToFit()
    }

    @objc private func timeChanged() {
        let calendar = CountdownClockSettings.calendar(in: settings.targetTimeZone)
        let parts = calendar.dateComponents([.hour, .minute], from: timePicker.date)
        settings.targetMinutes = CountdownClockSettings.clampedMinutes(
            (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        )
        onChange?(settings, false)
    }

    @objc private func dateChanged() {
        settings.targetDay = dayString(for: datePicker.date)
        onChange?(settings, false)
    }

    @objc private func dateSwitchChanged() {
        settings.targetDay = dateSwitch.isOn ? dayString(for: datePicker.date) : ""
        onChange?(settings, true)
    }

    private func dayString(for date: Date) -> String {
        let calendar = CountdownClockSettings.calendar(in: settings.targetTimeZone)
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return CountdownClockSettings.dayString(
            year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1
        )
    }
}
