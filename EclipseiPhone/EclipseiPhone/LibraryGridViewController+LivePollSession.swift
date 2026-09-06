//
//  LibraryGridViewController+LivePollSession.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

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

    /// Opens questpoll.live/host in Safari for deck editing.
    func presentQuestPollHostEditor() {
        let safari = SFSafariViewController(url: QuestPollConfig.hostURL)
        present(safari, animated: true)
    }

    /// Ends the active room (best-effort), clears local state, drops the overlay.
    func endQuestPollSession(clearAccount: Bool) async {
        stopQuestPollStatusPolling()
        livePollGateMembershipId = nil
        let account = QuestPollAccount.shared
        if let session = QuestPollSessionStore.shared.session,
           let pin = account.hostPIN {
            do {
                _ = try await QuestPollClient().control(
                    joinCode: session.code,
                    action: "end",
                    pin: pin,
                    hostId: account.hostId
                )
            } catch {
                // Room may already be gone; still clear local state.
            }
        }
        QuestPollSessionStore.shared.clear()
        if clearAccount {
            account.unlink()
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

    // MARK: - PIN / picker / start

    /// Opens the deck list, prompting for a PIN when unlinked.
    func presentQuestPollPickerOrLink(mode: QuestPollPickerMode) {
        if QuestPollAccount.shared.isLinked {
            presentQuestPollPicker(mode: mode)
            return
        }
        promptQuestPollPIN(mode: mode)
    }

    func promptQuestPollPIN(mode: QuestPollPickerMode) {
        let pin = QuestPollPINViewController()
        let nav = UINavigationController(rootViewController: pin)
        nav.modalPresentationStyle = .formSheet
        nav.preferredContentSize = QuestPollPINViewController.sheetSize
        pin.onLinked = { [weak self, weak nav] in
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
        picker.onUnlink = { [weak self] in
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

    func handleQuestPollPick(_ poll: QuestPollSummary, mode: QuestPollPickerMode) {
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
            let decision = QuestPollStartDecision.decide(
                hasLocalSession: false, active: active, pollId: item.pollId
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
        running: QuestPollSession?
    ) {
        let message: String
        if let running {
            message = "\(running.pollTitle) is live in room \(running.code), "
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

    /// Server's active PIN room, or nil when none, unlinked, or unreachable.
    private func fetchActiveQuestPoll() async -> QuestPollSession? {
        guard let pin = QuestPollAccount.shared.hostPIN else { return nil }
        do {
            return try await QuestPollClient().activeSession(
                pin: pin,
                hostId: QuestPollAccount.shared.hostId
            )
        } catch {
            return nil
        }
    }

    func startQuestPoll(_ item: ShowLivePoll) {
        guard ensureQuestPollDestination() else { return }
        guard let pin = QuestPollAccount.shared.hostPIN else {
            promptQuestPollPIN(mode: .start(item))
            return
        }
        let busy = presentQuestPollBusy(message: "Starting…")
        Task { @MainActor [weak self] in
            do {
                let session = try await QuestPollClient().startSession(
                    pollId: item.pollId,
                    pin: pin,
                    hostId: QuestPollAccount.shared.hostId
                )
                QuestPollSessionStore.shared.adopt(
                    session,
                    questionCount: item.questionCount,
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
    /// while the room is still in the lobby (no `totalQuestions` yet).
    private func resumeQuestPoll(_ session: QuestPollSession, for item: ShowLivePoll) {
        QuestPollSessionStore.shared.adopt(
            session,
            questionCount: session.resolvedQuestionCount ?? item.questionCount,
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
            let actions = QuestPollRibbon.forwardActions(
                from: current,
                to: index,
                questionCount: store.questionCount
            )
            guard !actions.isEmpty else { return }
            if actions.count > 1 {
                confirmSkipAheadQuestPoll(to: index, actions: actions)
                return
            }
            sendQuestPollActions(actions)
            return
        }
        if index < current {
            let actions = QuestPollRibbon.backwardActions(
                from: current,
                to: index,
                questionCount: store.questionCount
            )
            if actions.isEmpty {
                showPresentationToast("Already on this cue")
                return
            }
            sendQuestPollActions(actions)
            return
        }
    }

    private func confirmSkipAheadQuestPoll(to index: Int, actions: [String]) {
        let items = QuestPollSessionStore.shared.ribbonItems
        let label = items.indices.contains(index) ? items[index].title : "that cue"
        let alert = UIAlertController(
            title: "Skip ahead?",
            message: "Skip to \(label)? This will walk the cues in between.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Skip", style: .default) { [weak self] _ in
            self?.sendQuestPollActions(actions)
        })
        present(alert, animated: true)
    }

    func sendQuestPollActions(_ actions: [String]) {
        guard let pin = QuestPollAccount.shared.hostPIN else { return }
        QuestPollSessionStore.shared.setControlInFlight(true)
        Task { @MainActor [weak self] in
            defer { QuestPollSessionStore.shared.setControlInFlight(false) }
            var remaining = actions
            while !remaining.isEmpty {
                guard let session = QuestPollSessionStore.shared.session else { return }
                do {
                    let updated = try await QuestPollClient().control(
                        joinCode: session.code,
                        action: remaining.removeFirst(),
                        pin: pin,
                        hostId: QuestPollAccount.shared.hostId
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
