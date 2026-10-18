//
//  SettingsQuestPollViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
import SafariServices
import UIKit

/// Settings → QuestPoll: account, plan, and account actions.
///
/// Mirrors the Mac's QuestPoll account settings. Signing out or deleting the
/// account ends a running room first, while the account can still end it.
final class SettingsQuestPollViewController: UITableViewController {

    private enum Row: Hashable {
        case account
        case plan
        case manage
        case signIn
        case signOut
        case deleteAccount
    }

    private var plan: LivePollPlan?
    private var isWorking = false

    private var sections: [[Row]] {
        guard LivePollAccountStore.isSignedIn else {
            return [[.account, .signIn]]
        }
        return [[.account, .plan, .manage], [.signOut], [.deleteAccount]]
    }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "QuestPoll"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        loadPlan()
    }

    private func loadPlan() {
        guard LivePollAccountStore.isSignedIn else { return }
        Task { @MainActor [weak self] in
            self?.plan = try? await LivePollAccountStore.client().plan()
            self?.tableView.reloadData()
        }
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].count
    }

    override func tableView(
        _ tableView: UITableView, titleForFooterInSection section: Int
    ) -> String? {
        guard section == 0 else { return nil }
        return "QuestPoll runs the live polls and Q&A in your Shows. "
            + "Create and edit polls at questpoll.com."
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.selectionStyle = .default
        switch sections[indexPath.section][indexPath.row] {
        case .account:
            config.text = LivePollAccountStore.isSignedIn ? "Signed in" : "Not signed in"
            config.image = UIImage(systemName: "person.crop.circle")
            cell.selectionStyle = .none
        case .plan:
            config.text = plan == nil ? "Plan" : QuestPollPlanText.title(plan)
            config.secondaryText = QuestPollPlanText.detail(plan)
            config.image = UIImage(systemName: "person.3")
            cell.selectionStyle = .none
        case .manage:
            config.text = "Manage Polls on questpoll.com"
            config.image = UIImage(systemName: "safari")
            cell.accessoryType = .disclosureIndicator
        case .signIn:
            config.text = "Sign In…"
            config.textProperties.color = .tintColor
        case .signOut:
            config.text = "Sign Out"
            config.textProperties.color = .tintColor
        case .deleteAccount:
            config.text = "Delete Account"
            config.textProperties.color = .systemRed
            cell.accessibilityIdentifier = "livepoll.delete.account"
        }
        if isWorking { cell.selectionStyle = .none }
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isWorking else { return }
        switch sections[indexPath.section][indexPath.row] {
        case .manage:
            present(SFSafariViewController(url: QuestPollConfig.hostURL), animated: true)
        case .signIn:
            presentSignIn()
        case .signOut:
            Task { @MainActor [weak self] in
                await self?.endRoomThen { LivePollAccountStore.signOut() }
                self?.tableView.reloadData()
            }
        case .deleteAccount:
            confirmDeleteAccount()
        case .account, .plan:
            break
        }
    }

    // MARK: - Actions

    private func presentSignIn() {
        let migrate = LivePollAccountStore.prepareEmailSignInPrompt()
        let signIn = LivePollSignInViewController(showsMigrationMessage: migrate)
        let nav = UINavigationController(rootViewController: signIn)
        nav.modalPresentationStyle = .formSheet
        nav.preferredContentSize = LivePollSignInViewController.sheetSize
        signIn.onSignedIn = { [weak self, weak nav] in
            nav?.dismiss(animated: true)
            self?.tableView.reloadData()
            self?.loadPlan()
        }
        present(nav, animated: true)
    }

    /// Ends a running room (best effort), then runs `action`.
    private func endRoomThen(_ action: () -> Void) async {
        if let session = QuestPollSessionStore.shared.session {
            _ = try? await LivePollAccountStore.client().control(
                joinCode: session.code, command: .end
            )
        }
        action()
    }

    private func confirmDeleteAccount() {
        let alert = UIAlertController(
            title: "Delete QuestPoll Account?",
            message: "Deletes this account and its polls. This cannot be undone.",
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
        isWorking = true
        tableView.reloadData()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                await self.endRoomThen {}
                try await LivePollAccountStore.client().deleteAccount()
                LivePollAccountStore.signOut()
            } catch {
                let message = (error as? LivePollError)?.userMessage ?? "Could not delete the account."
                let alert = UIAlertController(
                    title: "Could Not Delete Account", message: message, preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
            self.isWorking = false
            self.plan = nil
            self.tableView.reloadData()
        }
    }
}
