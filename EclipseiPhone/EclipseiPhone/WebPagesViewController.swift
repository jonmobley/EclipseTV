//
//  WebPagesViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Global website History — manage/present, or pick cards for a Show.
final class WebPagesViewController: UITableViewController {

    /// When set, taps add membership to this Show instead of presenting.
    private let targetShowId: UUID?
    /// Fired after a Show card is added, once the sheet has dismissed.
    var onAdded: ((UUID) -> Void)?
    private let store = WebPageStore.shared
    private let cellReuseId = "pageCell"

    private var isAddToShowMode: Bool { targetShowId != nil }

    /// Pages not already members of the target Show (add-to-Show mode only).
    private var candidates: [WebPage] {
        guard let showId = targetShowId else { return store.pages }
        let memberIds = Set(LocalAlbumStore.shared.album(id: showId)?.itemIds ?? [])
        return store.pages.filter { !memberIds.contains($0.id.uuidString) }
    }

    private var displayedPages: [WebPage] {
        isAddToShowMode ? candidates : store.pages
    }

    private var isNavRoot: Bool {
        navigationController?.viewControllers.first === self
    }

    // MARK: - Lifecycle

    /// - Parameter targetShowId: Show to add a History card into, or `nil` to manage.
    init(targetShowId: UUID? = nil) {
        self.targetShowId = targetShowId
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "History"
        if isNavRoot {
            let leftSystemItem: UIBarButtonItem.SystemItem = isAddToShowMode ? .cancel : .done
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: leftSystemItem,
                target: self,
                action: #selector(doneTapped)
            )
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addTapped)
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseId)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pagesDidChange),
            name: WebPageStore.didChangeNotification,
            object: nil
        )
        if isAddToShowMode {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pagesDidChange),
                name: LocalAlbumStore.didChangeNotification,
                object: nil
            )
        }
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
        if let nav = navigationController,
           let compose = nav.viewControllers
            .compactMap({ $0 as? AddWebsiteViewController }).last {
            nav.popToViewController(compose, animated: true)
            return
        }
        let compose = AddWebsiteViewController(targetShowId: targetShowId)
        compose.onAdded = onAdded
        navigationController?.pushViewController(compose, animated: true)
    }

    private func addToShow(_ page: WebPage) {
        guard let showId = targetShowId else { return }
        WebPageStore.shared.touch(page.id)
        LocalAlbumStore.shared.add(itemId: page.id.uuidString, toAlbumId: showId)
        let notify = onAdded
        dismiss(animated: true) {
            notify?(page.id)
        }
    }

    /// Opens `page` in the phone browser, at most one browser at a time.
    ///
    /// If a browser is already open, navigates it (and AirPlay) instead of stacking
    /// a second one that would fight over the warm web view.
    private func presentPage(_ page: WebPage) {
        if let open = openController(ofType: WebRemoteViewController.self) {
            open.loadBrowserURL(page.url, pageId: page.id)
            return
        }
        WarmWebSessionPool.shared.warmIfNeeded(for: page)
        ExternalDisplayManager.shared.presentWeb(page.url, pageId: page.id)
        let preview = WebRemoteViewController(page: page)
        navigationController?.pushViewController(preview, animated: true)
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(displayedPages.count, 1)
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        guard isAddToShowMode else { return nil }
        if store.pages.isEmpty {
            return "Tap + to add a website, then add it as a card."
        }
        if candidates.isEmpty {
            return "Every site is already a card here. Tap + to add a new one."
        }
        return "Choose a site to add as a card, or tap + to add a new one."
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseId, for: indexPath)
        var config = cell.defaultContentConfiguration()
        let pages = displayedPages

        if pages.isEmpty {
            if isAddToShowMode {
                config.text = store.pages.isEmpty
                    ? "No history yet"
                    : "All sites are already cards here"
            } else {
                config.text = "No history yet"
                config.secondaryText = "Tap + to add a website"
                config.textProperties.color = .secondaryLabel
                config.secondaryTextProperties.color = .tertiaryLabel
            }
            cell.selectionStyle = .none
            cell.accessoryType = .none
        } else {
            let page = pages[indexPath.row]
            config.text = page.title
            config.secondaryText = page.url.host ?? page.url.absoluteString
            cell.selectionStyle = .default
            cell.accessoryType = isAddToShowMode ? .none : .disclosureIndicator
        }

        cell.contentConfiguration = config
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        let pages = displayedPages
        guard pages.indices.contains(indexPath.row) else { return }
        // Opportunistic warm is deferred inside the pool so WebKit creation
        // does not run during the History present animation.
        WarmWebSessionPool.shared.warmSoon([pages[indexPath.row]])
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let pages = displayedPages
        guard pages.indices.contains(indexPath.row) else { return }
        let page = pages[indexPath.row]
        if isAddToShowMode {
            addToShow(page)
        } else {
            presentPage(page)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        canEditRowAt indexPath: IndexPath
    ) -> Bool {
        !isAddToShowMode && !store.pages.isEmpty
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !isAddToShowMode, !store.pages.isEmpty else { return nil }
        let page = store.pages[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") {
            [weak self] _, _, done in
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
