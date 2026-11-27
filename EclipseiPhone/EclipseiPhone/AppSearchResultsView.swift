//
//  AppSearchResultsView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: The whole-app search results under the header: Shows, This Show,
//               Library and Music, each a section. See `AppSearch`.
//  Thread Safety: Main thread only - UIKit.
//

import UIKit

final class AppSearchResultsView: UIView, UITableViewDataSource, UITableViewDelegate {

    /// A row was tapped.
    var onSelect: ((AppSearchResult) -> Void)?
    /// Name of the open Show, for its section's heading.
    var thisShowName: String?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private var groups: [(section: AppSearchSection, results: [AppSearchResult])] = []
    private static let cellId = "result"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        accessibilityIdentifier = "home.search.results"

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellId)
        addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 48),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the results for `query`.
    func show(
        _ groups: [(section: AppSearchSection, results: [AppSearchResult])],
        query: String
    ) {
        self.groups = groups
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        emptyLabel.text = "No results for “\(needle)”"
        emptyLabel.isHidden = !groups.isEmpty
        tableView.reloadData()
        if !groups.isEmpty {
            tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
        }
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int { groups.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups[section].results.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let group = groups[section].section
        if group == .thisShow, let thisShowName, !thisShowName.isEmpty {
            return "In “\(thisShowName)”"
        }
        return group.title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellId, for: indexPath)
        let result = groups[indexPath.section].results[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = result.title
        config.image = UIImage(systemName: result.symbolName)
        config.imageProperties.tintColor = .secondaryLabel
        config.imageProperties.reservedLayoutSize = CGSize(width: 28, height: 28)
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelect?(groups[indexPath.section].results[indexPath.row])
    }
}
