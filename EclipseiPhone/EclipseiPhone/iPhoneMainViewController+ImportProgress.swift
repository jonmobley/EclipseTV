//
//  iPhoneMainViewController+ImportProgress.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Photos Import Progress

extension iPhoneMainViewController {

    /// Adds the import overlay above the rest of the home chrome.
    func setupImportProgressOverlay() {
        importProgressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(importProgressView)
        NSLayoutConstraint.activate([
            importProgressView.topAnchor.constraint(equalTo: view.topAnchor),
            importProgressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            importProgressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            importProgressView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        importProgressView.onCancel = { [weak self] in
            guard let self else { return }
            self.photoImportSession.cancel()
            self.renderImportProgress()
        }
        photoImportSession.onChange = { [weak self] in
            self?.renderImportProgress()
        }
    }

    /// Starts tracking an import of `count` picks.
    ///
    /// The overlay reveals itself only if the work outlasts the session's reveal
    /// delay, so picks already on the device import with no chrome at all.
    func beginImportProgress(count: Int) {
        photoImportSession.begin(total: count)
    }

    /// Stops tracking and takes the overlay down.
    func endImportProgress() {
        photoImportSession.end()
    }

    /// Mirrors the session onto the overlay.
    func renderImportProgress() {
        let session = photoImportSession
        guard session.isVisible else {
            importProgressView.setVisible(false)
            return
        }
        if session.isCancelled {
            importProgressView.update(
                title: PhotoImportProgressCopy.stopping,
                fraction: nil,
                canCancel: false
            )
        } else {
            importProgressView.update(
                title: PhotoImportProgressCopy.title(
                    completed: session.completed,
                    total: session.total
                ),
                // A zero fraction means the system hasn't sized the download yet;
                // a bar pinned at zero reads as broken, so spin instead.
                fraction: session.fraction > 0 ? session.fraction : nil
            )
        }
        importProgressView.setVisible(true)
    }

    // MARK: - Retry

    /// Offers another attempt at picks whose originals never left iCloud.
    ///
    /// - Parameters:
    ///   - message: What was left behind.
    ///   - retry: Re-runs the import for the failed picks only.
    func presentICloudRetry(message: String, retry: @escaping () -> Void) {
        let alert = UIAlertController(
            title: "Still in iCloud",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { _ in
            retry()
        })
        presentationAnchor.present(alert, animated: true)
    }

    /// Reports a single failed pick, offering another attempt when it could help.
    ///
    /// - Parameters:
    ///   - failure: Why the pick could not be loaded.
    ///   - noun: What the user picked ("image", "video", "media").
    ///   - retry: Re-runs the same pick.
    func reportImportFailure(
        _ failure: PhotoImportFailure,
        noun: String,
        retry: (() -> Void)? = nil
    ) {
        guard failure != .cancelled else {
            // The user asked for this, so acknowledge it without an alert.
            showTemporaryStatus("Import stopped")
            return
        }
        let alert = UIAlertController(
            title: failure.alertTitle,
            message: failure.message(noun: noun),
            preferredStyle: .alert
        )
        if let retry, failure.isWorthRetrying {
            alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
            alert.addAction(UIAlertAction(title: "Try Again", style: .default) { _ in
                retry()
            })
        } else {
            alert.addAction(UIAlertAction(title: "OK", style: .default))
        }
        presentationAnchor.present(alert, animated: true)
    }
}
