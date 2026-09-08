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
    var onEditHost: (() -> Void)?

    private let client: LivePollClient
    private var polls: [LivePollDeckSummary] = []
    private var loadError: String?
    private var isLoading = true

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

    override func tableView(
        _ tableView: UITableView, numberOfRowsInSection section: Int
    ) -> Int {
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
        guard loadError == nil, !isLoading,
              polls.indices.contains(indexPath.row) else { return }
        onPick?(polls[indexPath.row])
    }

    private static func message(for error: Error) -> String {
        if let poll = error as? LivePollError {
            return poll.userMessage
        }
        return "Could not load decks."
    }
}
