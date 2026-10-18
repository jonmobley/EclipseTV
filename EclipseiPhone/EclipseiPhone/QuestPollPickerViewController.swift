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
/// Account management (sign out, delete) lives in Settings → QuestPoll, the
/// same place the Mac keeps it; this sheet is only for choosing a poll.
final class QuestPollPickerViewController: UITableViewController {

    var onPick: ((LivePollDeckSummary) -> Void)?
    var onEditHost: (() -> Void)?

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
    init(client: LivePollClient = LivePollAccountStore.client()) {
        self.client = client
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Choose a Poll"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "poll")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Manage",
            style: .plain,
            target: self,
            action: #selector(editTapped)
        )
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(
            self, action: #selector(reloadPolls), for: .valueChanged
        )
        reloadPolls()
    }

    @objc private func closeTapped() {
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
        return "Create and edit polls at questpoll.com (Manage)."
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "poll", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryType = .none
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
            content.text = "No polls on this account yet."
        } else {
            let poll = polls[indexPath.row]
            content.text = poll.title
            let modeLabel = poll.mode == .quiz ? "Quiz" : "Poll"
            let count = "\(poll.questionCount) question\(poll.questionCount == 1 ? "" : "s")"
            content.secondaryText = "\(modeLabel) · \(count)"
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
        guard indexPath.section == Section.polls.rawValue,
              loadError == nil, !isLoading,
              polls.indices.contains(indexPath.row) else { return }
        onPick?(polls[indexPath.row])
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
