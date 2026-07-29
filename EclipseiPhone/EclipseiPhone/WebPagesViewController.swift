//
//  WebPagesViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Lists saved pages the user can present full-bleed on an AirPlay display.
final class WebPagesViewController: UITableViewController {

    private let store = WebPageStore.shared
    private let cellReuseId = "pageCell"

    // MARK: - Lifecycle

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Web"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseId)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pagesDidChange),
            name: WebPageStore.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func pagesDidChange() {
        tableView.reloadData()
    }

    @objc private func addTapped() {
        let alert = UIAlertController(
            title: "Add Website",
            message: "Enter a title and HTTPS address.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Title"
            field.autocapitalizationType = .words
            field.clearButtonMode = .whileEditing
        }
        alert.addTextField { field in
            field.placeholder = "example.com"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.textContentType = .URL
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let title = alert?.textFields?[0].text ?? ""
            let urlString = alert?.textFields?[1].text ?? ""
            do {
                let page = try self.store.add(title: title, urlString: urlString)
                self.presentPage(page)
            } catch {
                self.presentError(error)
            }
        })
        present(alert, animated: true)
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(
            title: "Couldn't Add Website",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func presentPage(_ page: WebPage) {
        WarmWebSessionPool.shared.warmIfNeeded(for: page)
        ExternalDisplayManager.shared.presentWeb(page.url, pageId: page.id)
        let preview = WebRemoteViewController(page: page)
        navigationController?.pushViewController(preview, animated: true)
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(store.pages.count, 1)
    }

    override func tableView(_ tableView: UITableView,
                            titleForFooterInSection section: Int) -> String? {
        nil
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseId, for: indexPath)
        var config = cell.defaultContentConfiguration()

        if store.pages.isEmpty {
            config.text = "No pages yet"
            config.secondaryText = "Tap + to pin an HTTPS page"
            config.textProperties.color = .secondaryLabel
            config.secondaryTextProperties.color = .tertiaryLabel
            cell.selectionStyle = .none
            cell.accessoryType = .none
        } else {
            let page = store.pages[indexPath.row]
            config.text = page.title
            config.secondaryText = page.url.host ?? page.url.absoluteString
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        }

        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView,
                            willDisplay cell: UITableViewCell,
                            forRowAt indexPath: IndexPath) {
        guard !store.pages.isEmpty else { return }
        WarmWebSessionPool.shared.warmSoon([store.pages[indexPath.row]])
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !store.pages.isEmpty else { return }
        presentPage(store.pages[indexPath.row])
    }

    override func tableView(_ tableView: UITableView,
                            canEditRowAt indexPath: IndexPath) -> Bool {
        !store.pages.isEmpty
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !store.pages.isEmpty else { return nil }
        let page = store.pages[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.confirmDelete(page: page, completion: done)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func confirmDelete(page: WebPage, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(
            title: "Delete Website?",
            message: "“\(page.title)” will be removed from this iPhone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(false)
        })
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.store.remove(id: page.id)
            completion(true)
        })
        present(alert, animated: true)
    }
}
