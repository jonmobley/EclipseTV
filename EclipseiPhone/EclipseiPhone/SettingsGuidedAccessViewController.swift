//
//  SettingsGuidedAccessViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Explains Guided Access and how to start a session before presenting.
final class SettingsGuidedAccessViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case status
        case why
        case how
    }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = GuidedAccessRecommendation.rowTitle
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadStatus),
            name: UIAccessibility.guidedAccessStatusDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reloadStatus() {
        guard isViewLoaded else { return }
        tableView.reloadSections(IndexSet(integer: Section.status.rawValue), with: .none)
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
        case .status, .why: return 1
        case .how: return GuidedAccessRecommendation.howSteps.count
        case .none: return 0
        }
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch Section(rawValue: section) {
        case .status: return nil
        case .why: return GuidedAccessRecommendation.whyTitle
        case .how: return GuidedAccessRecommendation.howTitle
        case .none: return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.selectionStyle = .none
        switch Section(rawValue: indexPath.section) {
        case .status:
            config.text = GuidedAccessRecommendation.rowTitle
            config.secondaryText = GuidedAccessRecommendation.statusText
            config.image = UIImage(systemName: "lock.iphone")
        case .why:
            config.text = GuidedAccessRecommendation.whyBody
            config.textProperties.numberOfLines = 0
            config.textProperties.color = .secondaryLabel
        case .how:
            config.text = "\(indexPath.row + 1). "
                + GuidedAccessRecommendation.howSteps[indexPath.row]
            config.textProperties.numberOfLines = 0
        case .none:
            break
        }
        cell.contentConfiguration = config
        return cell
    }
}
