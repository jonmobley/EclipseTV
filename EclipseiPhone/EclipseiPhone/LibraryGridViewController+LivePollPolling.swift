//
//  LibraryGridViewController+LivePollPolling.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Status polling / busy chrome

extension LibraryGridViewController {

    // MARK: - Status polling

    func startQuestPollStatusPolling() {
        stopQuestPollStatusPolling()
        guard QuestPollSessionStore.shared.session != nil else { return }
        questPollStatusPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard let session = QuestPollSessionStore.shared.session,
                      let pin = QuestPollAccount.shared.hostPIN,
                      !QuestPollSessionStore.shared.isControlInFlight
                else {
                    if QuestPollSessionStore.shared.session == nil { return }
                    continue
                }
                do {
                    let updated = try await QuestPollClient().fetchSession(
                        joinCode: session.code,
                        pin: pin,
                        hostId: QuestPollAccount.shared.hostId
                    )
                    QuestPollSessionStore.shared.adopt(updated)
                } catch {
                    // Transient; keep the ribbon on the last known state.
                }
            }
        }
    }

    func stopQuestPollStatusPolling() {
        questPollStatusPollTask?.cancel()
        questPollStatusPollTask = nil
    }

    // MARK: - Chrome helpers

    func presentQuestPollBusy(message: String) -> UIAlertController {
        let alert = UIAlertController(
            title: nil, message: message, preferredStyle: .alert
        )
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        alert.view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerYAnchor.constraint(equalTo: alert.view.centerYAnchor),
            indicator.leadingAnchor.constraint(
                equalTo: alert.view.leadingAnchor, constant: 20
            )
        ])
        present(alert, animated: true)
        return alert
    }

    func presentQuestPollError(_ error: Error) {
        let message = (error as? QuestPollError)?.userMessage
            ?? "Could not start the poll."
        let alert = UIAlertController(
            title: "QuestPoll", message: message, preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

}
