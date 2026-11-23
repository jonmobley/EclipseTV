//
//  QuestPollPickerViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
import UIKit

/// Lists the account's polls (Poll and Quiz) after email sign-in.
///
/// Polls are made and changed right here: + starts a new one, the pencil (or
/// a swipe) edits or deletes one. Account management (sign out, delete) lives
/// in Settings → QuestPoll, the same place the Mac keeps it.
final class QuestPollPickerViewController: UITableViewController {

    enum Mode {
        /// Tapping a poll picks it (for a Show card); the pencil edits it.
        case choose
        /// Settings → My Polls: tapping a poll edits it.
        case manage
    }

    var onPick: ((LivePollDeckSummary) -> Void)?

    private let mode: Mode
    private let client: LivePollClient
    private var polls: [LivePollDeckSummary] = []
    private var plan: LivePollPlan?
    private var loadError: String?
    private var isLoading = true

    private enum Section: Int, CaseIterable {
        case plan = 0
        case polls = 1
    }

    /// - Parameter client: Injected for tests; production uses the account token.
    init(mode: Mode = .choose, client: LivePollClient = LivePollAccountStore.client()) {
        self.mode = mode
        self.client = client
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = mode == .choose ? "Choose a Poll" : "My Polls"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "poll")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(newPollTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "New Poll"
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "questpoll.picker.new"
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(
            self, action: #selector(reloadPolls), for: .valueChanged
        )
        reloadPolls()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func newPollTapped() {
        presentEditor(.new)
    }

    /// Opens the in-app editor over this list.
    private func presentEditor(_ target: QuestPollEditorViewController.Target) {
        let nav = QuestPollEditorViewController.makeNavigation(
            target: target,
            client: client,
            onSaved: { [weak self] deck in self?.didSave(deck, wasNew: target == .new) },
            onDeleted: { [weak self] _ in self?.reloadPolls() }
        )
        present(nav, animated: true)
    }

    /// A poll made while choosing one is the choice; anything else just
    /// refreshes the list.
    private func didSave(_ deck: LivePollDeck, wasNew: Bool) {
        if wasNew, mode == .choose, let id = deck.id, let onPick {
            onPick(LivePollDeckSummary(
                id: id, title: deck.title, questionCount: deck.questions.count, mode: deck.mode
            ))
            return
        }
        reloadPolls()
    }

    private func confirmDelete(_ poll: LivePollDeckSummary) {
        let cards = LivePollStore.shared.polls.filter { $0.pollId == poll.id }.count
        let alert = UIAlertController(
            title: poll.mode == .quiz ? "Delete Quiz?" : "Delete Poll?",
            message: QuestPollEditorViewController.deleteMessage(
                title: poll.title, cardsUsingIt: cards
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.delete(poll)
        })
        present(alert, animated: true)
    }

    private func delete(_ poll: LivePollDeckSummary) {
        let client = self.client
        Task { @MainActor [weak self] in
            do {
                try await client.deleteDeck(id: poll.id)
            } catch {
                let alert = UIAlertController(
                    title: "Could Not Delete",
                    message: Self.message(for: error),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            }
            self?.reloadPolls()
        }
    }

    @objc private func reloadPolls() {
        loadError = nil
        isLoading = polls.isEmpty
        tableView.reloadData()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.polls = try await self.client.listDecks()
                // Cards in Shows pick up names / lengths edited on the web.
                LivePollStore.shared.refresh(from: self.polls)
            } catch {
                self.polls = []
                self.loadError = Self.message(for: error)
            }
            self.plan = try? await self.client.plan()
            self.isLoading = false
            self.refreshControl?.endRefreshing()
            self.tableView.reloadData()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(
        _ tableView: UITableView, numberOfRowsInSection section: Int
    ) -> Int {
        if section == Section.plan.rawValue { return plan == nil ? 0 : 1 }
        if loadError != nil || isLoading { return 1 }
        return max(polls.count, 1)
    }

    override func tableView(
        _ tableView: UITableView, titleForFooterInSection section: Int
    ) -> String? {
        guard section == Section.polls.rawValue, !isLoading, loadError == nil else {
            return nil
        }
        return Self.footerText(mode: mode, hasPolls: !polls.isEmpty)
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "poll", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .none
        cell.accessibilityIdentifier = nil
        if indexPath.section == Section.plan.rawValue {
            content.text = QuestPollPlanText.title(plan)
            content.secondaryText = QuestPollPlanText.detail(plan)
            content.image = UIImage(systemName: "person.3")
            cell.accessibilityIdentifier = "questpoll.plan"
            cell.contentConfiguration = content
            return cell
        }
        if let loadError {
            content.text = loadError
        } else if isLoading {
            content.text = "Loading polls…"
        } else if polls.isEmpty {
            content.text = "No polls yet. Tap + to make one."
        } else {
            let poll = polls[indexPath.row]
            content.text = poll.title
            let modeLabel = poll.mode == .quiz ? "Quiz" : "Poll"
            let count = "\(poll.questionCount) question\(poll.questionCount == 1 ? "" : "s")"
            content.secondaryText = "\(modeLabel) · \(count)"
            cell.selectionStyle = .default
            if mode == .choose {
                cell.accessoryView = editButton(for: poll)
            } else {
                cell.accessoryType = .disclosureIndicator
            }
        }
        cell.contentConfiguration = content
        return cell
    }

    /// The pencil at the end of a row in `choose` mode.
    private func editButton(for poll: LivePollDeckSummary) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "pencil")
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 4)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.presentEditor(.existing(pollId: poll.id))
        })
        button.accessibilityLabel = "Edit \(poll.title)"
        button.sizeToFit()
        return button
    }

    static func footerText(mode: Mode, hasPolls: Bool) -> String {
        let saved = "Polls are saved to your QuestPoll account, so they are on your "
            + "other devices and questpoll.com too."
        guard hasPolls else { return saved }
        switch mode {
        case .choose: return "Tap a poll to use it. Tap the pencil to change it. " + saved
        case .manage: return "Tap a poll to change it. " + saved
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section == Section.polls.rawValue,
              loadError == nil, !isLoading,
              polls.indices.contains(indexPath.row) else { return nil }
        let poll = polls[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") {
            [weak self] _, _, done in
            self?.confirmDelete(poll)
            done(false)
        }
        let edit = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, done in
            self?.presentEditor(.existing(pollId: poll.id))
            done(true)
        }
        let configuration = UISwipeActionsConfiguration(actions: [delete, edit])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    override func tableView(
        _ tableView: UITableView, didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == Section.polls.rawValue,
              loadError == nil, !isLoading,
              polls.indices.contains(indexPath.row) else { return }
        switch mode {
        case .choose: onPick?(polls[indexPath.row])
        case .manage: presentEditor(.existing(pollId: polls[indexPath.row].id))
        }
    }

    private static func message(for error: Error) -> String {
        if let poll = error as? LivePollError {
            return poll.userMessage
        }
        return "Could not load polls."
    }
}

// MARK: - QuestPollPlanText

/// Plan wording shared by the poll picker, Settings, and Controls.
enum QuestPollPlanText {

    /// "Free plan · up to 50 people" / "Eclipse plan · up to 300 people".
    static func title(_ plan: LivePollPlan?) -> String {
        guard let plan else { return "QuestPoll" }
        let name = plan.eclipse ? "Eclipse plan" : "Free plan"
        return "\(name) · up to \(plan.playerLimit) people"
    }

    /// How to lift the free limit, or nil on the Eclipse plan.
    static func detail(_ plan: LivePollPlan?) -> String? {
        guard let plan, !plan.eclipse else { return nil }
        if plan.linkExpired == true {
            return "Your Eclipse license needs re-checking. Add it again at questpoll.com."
        }
        return "Add your Eclipse license key at questpoll.com to allow 300."
    }
}
