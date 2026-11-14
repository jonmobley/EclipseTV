//
//  LibraryGridViewController+LivePollPolling.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import LivePollKit
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
                // The loop body reads only shared stores, so `self` is a liveness
                // check: stop polling once the grid is gone.
                guard self != nil, !Task.isCancelled else { return }
                guard let session = QuestPollSessionStore.shared.session,
                      LivePollAccountStore.isSignedIn,
                      !QuestPollSessionStore.shared.isControlInFlight
                else {
                    if QuestPollSessionStore.shared.session == nil { return }
                    continue
                }
                let result: Result<LivePollSession, Error>
                do {
                    result = .success(try await LivePollAccountStore.client().fetchSession(
                        joinCode: session.code,
                        includeInbox: session.mode == .qa
                    ))
                } catch {
                    result = .failure(error)
                }
                // A tap or End may have changed the room while this was in flight.
                guard !Task.isCancelled,
                      !QuestPollSessionStore.shared.isControlInFlight,
                      QuestPollSessionStore.shared.session?.code == session.code
                else { continue }
                if QuestPollStatusPoll.roomIsGone(result) {
                    // Ended on the Mac or the website: close it here too.
                    await self?.endQuestPollSession(clearAccount: false, notifyServer: false)
                    self?.showPresentationToast(session.mode == .qa ? "Q&A ended" : "Poll ended")
                    return
                }
                if case .success(let updated) = result {
                    QuestPollSessionStore.shared.adopt(updated)
                }
                // Other errors are transient; keep the last known state.
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

    /// Shows `error` on top of whatever is open (the Questions or Controls
    /// sheet), so a failed tap is never silently dropped behind it.
    func presentQuestPollError(
        _ error: Error,
        fallback: String = "Could not start the poll."
    ) {
        let message = (error as? LivePollError)?.userMessage ?? fallback
        let alert = UIAlertController(
            title: "QuestPoll", message: message, preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        var host: UIViewController = self
        while let next = host.presentedViewController, !next.isBeingDismissed {
            host = next
        }
        host.present(alert, animated: true)
    }

}

/// Decisions for the 2-second room refresh.
enum QuestPollStatusPoll {
    /// True when the room was ended elsewhere or no longer exists.
    static func roomIsGone(_ result: Result<LivePollSession, Error>) -> Bool {
        switch result {
        case .success(let session):
            return session.phase == .ended
        case .failure(let error):
            if case .server(let message) = error as? LivePollError {
                return message.localizedCaseInsensitiveContains("not found")
            }
            return false
        }
    }

}
