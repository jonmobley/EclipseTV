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
        reloadLibraryGrid()
        refreshLiveHeader()
        refreshSlideshowRibbonPresentation()
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
        let alert = UIAlertController(
            title: "QuestPoll",
            message: "Enter the host PIN so Eclipse can run your live polls.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.isSecureTextEntry = true
            field.placeholder = "Host PIN"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Link", style: .default) { [weak self] _ in
            let pin = alert.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self?.verifyQuestPollPIN(pin, mode: mode)
        })
        present(alert, animated: true)
    }

    func verifyQuestPollPIN(_ pin: String, mode: QuestPollPickerMode) {
        guard !pin.isEmpty else { return }
        let busy = presentQuestPollBusy(message: "Linking…")
        Task { @MainActor [weak self] in
            do {
                try await QuestPollClient().verifyPIN(pin)
                QuestPollAccount.shared.link(pin: pin)
                busy.dismiss(animated: true) {
                    self?.presentQuestPollPicker(mode: mode)
                }
            } catch {
                busy.dismiss(animated: true) {
                    self?.presentQuestPollError(error)
                }
            }
        }
    }

    func presentQuestPollPicker(mode: QuestPollPickerMode) {
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
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
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

    func confirmStartOrReplaceQuestPoll(_ item: ShowLivePoll) {
        guard ensureQuestPollDestination() else { return }
        let hasLocal = QuestPollSessionStore.shared.session != nil
        if hasLocal {
            presentReplaceConfirm(for: item)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let hasActive = await self.serverHasActiveQuestPoll()
            if hasActive {
                self.presentReplaceConfirm(for: item)
            } else {
                self.startQuestPoll(item)
            }
        }
    }

    private func presentReplaceConfirm(for item: ShowLivePoll) {
        let alert = UIAlertController(
            title: "Replace Poll?",
            message: "Ends the current room and starts \(item.title).",
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

    private func serverHasActiveQuestPoll() async -> Bool {
        guard let pin = QuestPollAccount.shared.hostPIN else { return false }
        do {
            return try await QuestPollClient().activeSession(
                pin: pin,
                hostId: QuestPollAccount.shared.hostId
            ) != nil
        } catch {
            return false
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

    /// Adopts the server's active room when local store is empty. Returns true if adopted.
    @discardableResult
    func reattachActiveQuestPollIfNeeded(for item: ShowLivePoll) async -> Bool {
        guard QuestPollSessionStore.shared.session == nil,
              let pin = QuestPollAccount.shared.hostPIN
        else { return false }
        do {
            guard let session = try await QuestPollClient().activeSession(
                pin: pin,
                hostId: QuestPollAccount.shared.hostId
            ), session.pollId == item.pollId else { return false }
            var count = session.resolvedQuestionCount ?? item.questionCount
            if session.resolvedQuestionCount == nil {
                let polls = try? await QuestPollClient().listPolls(
                    pin: pin, hostId: QuestPollAccount.shared.hostId
                )
                count = polls?.first(where: { $0.id == session.pollId })?
                    .questionCount ?? item.questionCount
            }
            QuestPollSessionStore.shared.adopt(
                session,
                questionCount: max(count, 1),
                membershipId: item.id
            )
            return true
        } catch {
            return false
        }
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
