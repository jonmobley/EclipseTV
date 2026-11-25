//
//  CountdownTargetTimeViewController.swift
//  Eclipse
//
//  "Set Time" sheet for a To Time countdown, opened from the tile ⋯ menu.
//  Nothing is saved until Done; Cancel leaves the countdown as it was.
//  Thread Safety: Main-actor UIKit.
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Edits a countdown's To Time target (time, optional date, read-only zone).
final class CountdownTargetTimeViewController: UITableViewController {

    /// Called on Done with the settings to save (mode set to To Time).
    var onDone: ((CountdownClockSettings) -> Void)?

    private let rows: CountdownTargetRows
    private var settings: CountdownClockSettings

    /// - Parameter settings: The countdown's current settings.
    init(settings: CountdownClockSettings) {
        self.settings = settings
        self.rows = CountdownTargetRows(settings: settings)
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Set Time"
        tableView.register(
            UITableViewCell.self, forCellReuseIdentifier: CountdownTargetRows.reuseId
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in self?.finish() }
        )
        rows.onChange = { [weak self] _, rowsChanged in
            guard rowsChanged else { return }
            self?.tableView.reloadData()
        }
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.rows.count
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        rows.footer
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        rows.cell(for: rows.rows[indexPath.row], in: tableView, at: indexPath)
    }

    // MARK: - Private

    private func finish() {
        settings.mode = .timeOfDay
        settings.takeTarget(from: rows.settings)
        let done = onDone
        let result = settings
        dismiss(animated: true) { done?(result) }
    }
}
