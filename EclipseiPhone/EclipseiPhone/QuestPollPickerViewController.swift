//
//  QuestPollPickerViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
import UIKit

/// Lists account decks (Poll and Quiz) after email sign-in.
final class QuestPollPickerViewController: UITableViewController {

    var onPick: ((LivePollDeckSummary) -> Void)?
    var onSignOut: (() -> Void)?
    /// Called after the server has deleted the account. The token is still stored.
    var onAccountDeleted: (() -> Void)?
    var onEditHost: (() -> Void)?

    private let client: LivePollClient
    private var polls: [LivePollDeckSummary] = []
    private var loadError: String?
    private var isLoading = true
    private var isDeleting = false

    private enum Section: Int {
        case decks = 0
        case account = 1
    }

    /// - Parameter client: Injected for tests; production uses the account token.
    init(client: LivePollClient = LivePollAccountStore.client()) {
        self.client = client
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Live Poll"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "poll")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                title: "Sign Out",
                style: .plain,
                target: self,
                action: #selector(signOutTapped)
            ),
            UIBarButtonItem(
                title: "Edit",
                style: .plain,
                target: self,
                action: #selector(editTapped)
            )
        ]
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(
            self, action: #selector(reloadPolls), for: .valueChanged
        )
        reloadPolls()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func signOutTapped() {
        onSignOut?()
        dismiss(animated: true)
    }

    @objc private func editTapped() {
        onEditHost?()
    }

    @objc private func reloadPolls() {
        loadError = nil
        isLoading = polls.isEmpty
        tableView.reloadData()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.polls = try await self.client.listDecks()
            } catch {
                self.polls = []
                self.loadError = Self.message(for: error)
            }
            self.isLoading = false
            self.refreshControl?.endRefreshing()
            self.tableView.reloadData()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.account.rawValue + 1
    }

    override func tableView(
        _ tableView: UITableView, numberOfRowsInSection section: Int
    ) -> Int {
        if section == Section.account.rawValue { return 1 }
        if loadError != nil || isLoading { return 1 }
        return max(polls.count, 1)
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "poll", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.selectionStyle = .none
        cell.accessibilityIdentifier = nil
        if indexPath.section == Section.account.rawValue {
            content.text = "Delete Account"
            content.textProperties.color = .systemRed
            cell.selectionStyle = isDeleting ? .none : .default
            cell.accessibilityIdentifier = "livepoll.delete.account"
            cell.contentConfiguration = content
            return cell
        }
        if let loadError {
            content.text = loadError
        } else if isLoading {
            content.text = "Loading decks…"
        } else if polls.isEmpty {
            content.text = "No decks on this account yet."
        } else {
            let poll = polls[indexPath.row]
            content.text = poll.title
            let modeLabel = poll.mode == .quiz ? "Quiz" : "Poll"
            content.secondaryText = "\(modeLabel) · \(poll.questionCount) questions"
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(
        _ tableView: UITableView, didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == Section.account.rawValue {
            confirmDeleteAccount()
            return
        }
        guard loadError == nil, !isLoading,
              polls.indices.contains(indexPath.row) else { return }
        onPick?(polls[indexPath.row])
    }

    // MARK: - Account deletion

    private func confirmDeleteAccount() {
        guard !isDeleting else { return }
        let alert = UIAlertController(
            title: "Delete Live Poll Account?",
            message: "Deletes this account and its decks. This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete Account", style: .destructive) {
            [weak self] _ in
            self?.deleteAccount()
        })
        present(alert, animated: true)
    }

    private func deleteAccount() {
        guard !isDeleting else { return }
        isDeleting = true
        tableView.reloadSections(
            IndexSet(integer: Section.account.rawValue), with: .none
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.client.deleteAccount()
                self.onAccountDeleted?()
                self.dismiss(animated: true)
            } catch {
                self.isDeleting = false
                self.tableView.reloadSections(
                    IndexSet(integer: Section.account.rawValue), with: .none
                )
                self.present(Self.deleteFailedAlert(for: error), animated: true)
            }
        }
    }

    private static func deleteFailedAlert(for error: Error) -> UIAlertController {
        let alert = UIAlertController(
            title: "Could Not Delete Account",
            message: message(for: error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        return alert
    }

    private static func message(for error: Error) -> String {
        if let poll = error as? LivePollError {
            return poll.userMessage
        }
        return "Could not load decks."
    }
}
