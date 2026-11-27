//
//  SettingsWebTextSizeViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Chooses how large text looks on websites shown on the phone preview, AirPlay and EclipseTV.
///
/// Smaller sizes give the page a wider desktop-style canvas, so text looks smaller;
/// Large gives a narrower canvas, so text looks bigger. Main-thread only (UIKit).
final class SettingsWebTextSizeViewController: UITableViewController {

    // MARK: - Display order

    /// Shown biggest text first so the list reads Large, Medium, Small.
    private let sizes: [WebTextSize] = [.large, .medium, .small]

    // MARK: - Lifecycle

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Website Text Size"
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

    @objc private func reload() {
        tableView.reloadData()
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sizes.count
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        "How big text looks when a website is on the phone, AirPlay or EclipseTV. "
            + "Large suits a TV across the room; Small fits more of the page."
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        let size = sizes[indexPath.row]
        config.text = size.rawValue
        cell.accessoryType = ExternalOutputSettings.webTextSize == size ? .checkmark : .none
        cell.selectionStyle = .default
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        ExternalOutputSettings.webTextSize = sizes[indexPath.row]
    }
}
