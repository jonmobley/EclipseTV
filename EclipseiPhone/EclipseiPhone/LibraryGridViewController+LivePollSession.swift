//
//  LibraryGridViewController+LivePollSession.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
import SafariServices
import UIKit

/// How the deck picker applies a selection.
enum QuestPollPickerMode {
    /// Create a new ShowLivePoll card in `showId`.
    case add(showId: UUID)
    /// Rebind an existing card's pollId / title.
    case replace(UUID)
    /// Start (or replace) a live room for an existing card.
    case start(ShowLivePoll)
}

// MARK: - Session lifecycle / ribbon control

extension LibraryGridViewController {

    /// Opens the Live Poll host editor in Safari for deck editing.
    func presentQuestPollHostEditor() {
        let safari = SFSafariViewController(url: QuestPollConfig.hostURL)
        present(safari, animated: true)
    }

    /// Ends the active room (best-effort), clears local state, drops the overlay.
    func endQuestPollSession(clearAccount: Bool) async {
        stopQuestPollStatusPolling()
        livePollGateMembershipId = nil
        if let session = QuestPollSessionStore.shared.session,
           LivePollAccountStore.isSignedIn {
            do {
                _ = try await LivePollAccountStore.client().control(
                    joinCode: session.code,
                    command: .end
                )
            } catch {
                // Room may already be gone; still clear local state.
            }
        }
        QuestPollSessionStore.shared.clear()
        if clearAccount {
            LivePollAccountStore.signOut()
        }
        if ExternalDisplayManager.shared.isQuestPollLive {
            ExternalDisplayManager.shared.stopWebAndRestoreLibrary()
        }
        refreshLivePollPresentation()
    }

    /// Confirms End Poll from the tile menu.
    func confirmEndQuestPoll() {
        guard QuestPollSessionStore.shared.session != nil else { return }
        let alert = UIAlertController(
            title: "End Poll?",
            message: "Closes the room for everyone and leaves the projector.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "End Poll", style: .destructive) {
            [weak self] _ in
            Task { @MainActor in
                await self?.endQuestPollSession(clearAccount: false)
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Sign-in / picker / start

    /// Opens the deck list, prompting for email sign-in when needed.
    func presentQuestPollPickerOrLink(mode: QuestPollPickerMode) {
        if LivePollAccountStore.isSignedIn {
            presentQuestPollPicker(mode: mode)
            return
        }
        promptLivePollSignIn(mode: mode)
    }

    func promptLivePollSignIn(mode: QuestPollPickerMode) {
        let migrate = LivePollAccountStore.prepareEmailSignInPrompt()
        let signIn = LivePollSignInViewController(showsMigrationMessage: migrate)
        let nav = UINavigationController(rootViewController: signIn)
        nav.modalPresentationStyle = .formSheet
        nav.preferredContentSize = LivePollSignInViewController.sheetSize
        signIn.onSignedIn = { [weak self, weak nav] in
            guard let self, let nav else { return }
            nav.setViewControllers(
                [self.makeQuestPollPicker(mode: mode)],
                animated: true
            )
        }
        present(nav, animated: true)
    }

    func presentQuestPollPicker(mode: QuestPollPickerMode) {
        let nav = UINavigationController(
            rootViewController: makeQuestPollPicker(mode: mode)
        )
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    private func makeQuestPollPicker(
        mode: QuestPollPickerMode
    ) -> QuestPollPickerViewController {
        let picker = QuestPollPickerViewController()
        picker.onSignOut = { [weak self] in
            Task { @MainActor in
                await self?.endQuestPollSession(clearAccount: true)
            }
        }
        picker.onEditHost = { [weak self] in
            self?.presentQuestPollHostEditor()
        }
        picker.onPick = { [weak self] poll in
            picker.dismiss(animated: true) {
                self?.handleQuestPollPick(poll, mode: mode)
            }
        }
        return picker
    }

    func handleQuestPollPick(_ poll: LivePollDeckSummary, mode: QuestPollPickerMode) {
        switch mode {
        case .add(let showId):
            let item = LivePollStore.shared.create(
                pollId: poll.id,
                title: poll.title,
                questionCount: poll.questionCount,
                showId: showId
            )
            revealAddedShowMember(id: ShowLivePollToken.token(for: item.id))
        case .replace(let membershipId):
            LivePollStore.shared.replace(id: membershipId, with: poll)
            if QuestPollSessionStore.shared.membershipId == membershipId {
                Task { @MainActor [weak self] in
                    await self?.endQuestPollSession(clearAccount: false)
                }
            }
        case .start(let item):
            LivePollStore.shared.replace(id: item.id, with: poll)
            if let updated = LivePollStore.shared.poll(id: item.id) {
                confirmStartOrReplaceQuestPoll(updated)
            } else {
                confirmStartOrReplaceQuestPoll(item)
            }
        }
    }

    /// Starts a room for `item`, or rejoins one already running its deck
    /// (after a relaunch, or started from another device such as the Mac).
    func confirmStartOrReplaceQuestPoll(_ item: ShowLivePoll) {
        guard ensureQuestPollDestination() else { return }
        let hasLocal = QuestPollSessionStore.shared.session != nil
        if hasLocal {
            presentReplaceConfirm(for: item, running: nil)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let active = await self.fetchActiveQuestPoll()
            let decision = LivePollStartDecision.decide(
                hasLocalSession: false,
                active: active,
                matchingDeckTitle: item.title
            )
            switch decision {
            case .start:
                self.startQuestPoll(item)
            case .resume(let session):
                self.resumeQuestPoll(session, for: item)
            case .replace(let running):
                self.presentReplaceConfirm(for: item, running: running)
            }
        }
    }

    private func presentReplaceConfirm(
        for item: ShowLivePoll,
        running: LivePollSession?
    ) {
        let message: String
        if let running {
            message = "\(running.deckTitle) is live in room \(running.code), "
                + "possibly from another device. End it and start \(item.title)?"
        } else {
            message = "Ends the current room and starts \(item.title)."
        }
        let alert = UIAlertController(
            title: "Replace Poll?",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Replace", style: .destructive) {
            [weak self] _ in
            Task { @MainActor in
                await self?.endQuestPollSession(clearAccount: false)
                self?.startQuestPoll(item)
            }
        })
        present(alert, animated: true)
    }

    /// Server's active account room, or nil when none, signed out, or unreachable.
    private func fetchActiveQuestPoll() async -> LivePollSession? {
        guard LivePollAccountStore.isSignedIn else { return nil }
        do {
            return try await LivePollAccountStore.client().activeSession()
        } catch {
            return nil
        }
    }

    func startQuestPoll(_ item: ShowLivePoll) {
        guard ensureQuestPollDestination() else { return }
        guard LivePollAccountStore.isSignedIn else {
            promptLivePollSignIn(mode: .start(item))
            return
        }
        let busy = presentQuestPollBusy(message: "Starting…")
        Task { @MainActor [weak self] in
            do {
                let response = try await LivePollAccountStore.client().startSession(
                    deckId: item.pollId
                )
                let session: LivePollSession
                if let created = response.session {
                    session = created
                } else {
                    session = try await LivePollAccountStore.client().fetchSession(
                        joinCode: response.joinCode
                    )
                }
                QuestPollSessionStore.shared.adopt(
                    session,
                    questionCount: max(item.questionCount, session.questionCount),
                    membershipId: item.id
                )
                busy.dismiss(animated: true) {
                    self?.presentQuestPollLive()
                }
            } catch {
                busy.dismiss(animated: true) {
                    self?.presentQuestPollError(error)
                }
            }
        }
    }

    /// Adopts a room already running `item`'s deck and goes live on it,
    /// instead of ending it. The card's own question count is the fallback
    /// while the room is still in the lobby.
    private func resumeQuestPoll(_ session: LivePollSession, for item: ShowLivePoll) {
        QuestPollSessionStore.shared.adopt(
            session,
            questionCount: session.questionCount > 0
                ? session.questionCount
                : item.questionCount,
            membershipId: item.id
        )
        presentQuestPollLive()
        showPresentationToast("Rejoined room \(session.code)")
    }

    // MARK: - Ribbon cues

    func cueQuestPollStage(at index: Int) {
        let store = QuestPollSessionStore.shared
        guard store.session != nil, !store.isControlInFlight else { return }
        let current = store.ribbonIndex
        if index > current {
            let commands = QuestPollRibbon.forwardCommands(
                from: current,
                to: index,
                questionCount: store.questionCount
            )
            guard !commands.isEmpty else { return }
            if commands.count > 1 {
                confirmSkipAheadQuestPoll(to: index, commands: commands)
                return
            }
            sendQuestPollCommands(commands)
            return
        }
        if index < current {
            let commands = QuestPollRibbon.backwardCommands(
                from: current,
                to: index,
                questionCount: store.questionCount
            )
            if commands.isEmpty {
                showPresentationToast("Already on this cue")
                return
            }
            sendQuestPollCommands(commands)
            return
        }
    }

    private func confirmSkipAheadQuestPoll(
        to index: Int,
        commands: [LivePollHostCommand]
    ) {
        let items = QuestPollSessionStore.shared.ribbonItems
        let label = items.indices.contains(index) ? items[index].title : "that cue"
        let alert = UIAlertController(
            title: "Skip ahead?",
            message: "Skip to \(label)? This will walk the cues in between.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Skip", style: .default) { [weak self] _ in
            self?.sendQuestPollCommands(commands)
        })
        present(alert, animated: true)
    }

    func sendQuestPollCommands(_ commands: [LivePollHostCommand]) {
        guard LivePollAccountStore.isSignedIn else { return }
        QuestPollSessionStore.shared.setControlInFlight(true)
        Task { @MainActor [weak self] in
            defer { QuestPollSessionStore.shared.setControlInFlight(false) }
            var remaining = commands
            while !remaining.isEmpty {
                guard let session = QuestPollSessionStore.shared.session else { return }
                do {
                    let updated = try await LivePollAccountStore.client().control(
                        joinCode: session.code,
                        command: remaining.removeFirst()
                    )
                    QuestPollSessionStore.shared.adopt(
                        updated,
                        membershipId: QuestPollSessionStore.shared.membershipId
                    )
                } catch {
                    self?.presentQuestPollError(error)
                    return
                }
            }
        }
    }
}
