//
//  ShowOfflineDownloadPresenter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension UIViewController {

    /// How the Show's offline row reads: an action while something is in iCloud
    /// only, a plain status once everything is on this iPhone.
    struct OfflineRow {
        let title: String
        let subtitle: String?
        let systemImage: String
        let canDownload: Bool
    }

    @MainActor
    static func offlineRow(forShowId showId: UUID) -> OfflineRow {
        let missing = ShowOfflinePlanner.idsToDownload(forShowId: showId).count
        guard missing > 0 else {
            return OfflineRow(
                title: String(localized: "Available Offline"),
                subtitle: nil,
                systemImage: "checkmark.circle",
                canDownload: false
            )
        }
        return OfflineRow(
            title: String(localized: "Download for Offline"),
            subtitle: missing == 1
                ? String(localized: "1 item is in iCloud only")
                : String(localized: "\(missing) items are in iCloud only"),
            systemImage: "arrow.down.circle",
            canDownload: true
        )
    }

    /// Downloads every photo and video the Show needs, one at a time, then says
    /// whether the Show is ready to present without internet.
    func presentShowOfflineDownload(forShowId showId: UUID) {
        let ids = ShowOfflinePlanner.idsToDownload(forShowId: showId)
        guard !ids.isEmpty else { return }
        var cancelled = false
        let progress = UIAlertController(
            title: String(localized: "Downloading Show"),
            message: Self.offlineProgressText(done: 0, total: ids.count),
            preferredStyle: .alert
        )
        progress.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            cancelled = true
        })
        // Downloads start once the alert is fully on screen: a download can fail
        // at once (no iCloud), and dismissing a half-presented alert would leave it
        // stuck and swallow the outcome.
        present(progress, animated: true) {
            Task { @MainActor in
                var failed = 0
                for (index, id) in ids.enumerated() {
                    if cancelled { return }
                    progress.message = Self.offlineProgressText(done: index, total: ids.count)
                    if !(await Self.download(id)) { failed += 1 }
                }
                guard !cancelled else { return }
                progress.dismiss(animated: true) {
                    self.presentOfflineOutcome(failed: failed, total: ids.count)
                }
            }
        }
    }

    // MARK: - Private

    private static func offlineProgressText(done: Int, total: Int) -> String {
        String(localized: "\(done + 1) of \(total)…")
    }

    private static func download(_ id: String) async -> Bool {
        await withCheckedContinuation { continuation in
            EclipseSyncController.shared.backend.downloadAsset(id: id, progress: nil) { result in
                if case .success = result {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func presentOfflineOutcome(failed: Int, total: Int) {
        if failed == 0 {
            presentOfflineResult(
                title: String(localized: "Available Offline"),
                message: String(localized: "Everything in this Show is on this iPhone.")
            )
            return
        }
        Haptics.error()
        presentOfflineResult(
            title: String(localized: "Some Items Didn't Download"),
            message: String(
                localized: "\(failed) of \(total) couldn't download. Check your internet connection and try again."
            )
        )
    }

    private func presentOfflineResult(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
