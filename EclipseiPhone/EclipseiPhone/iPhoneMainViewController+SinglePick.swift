//
//  iPhoneMainViewController+SinglePick.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import PhotosUI

// MARK: - Single Photos Pick

/// One pick at a time: the Background tile, the Screensaver, a re-send, and the
/// single video add that still goes through thumbnail and crop confirm.
///
/// These paths get the same download treatment as a batch. An original that lives
/// in iCloud takes just as long whether it was picked alone or with twenty others,
/// and picking one item is where the wait used to be invisible — the picker
/// dismissed and nothing happened until the download finished or gave up.
extension iPhoneMainViewController {

    // MARK: - Download

    /// Downloads one picked still behind the import overlay.
    private func downloadPickedImage(
        _ provider: NSItemProvider
    ) async -> Result<UIImage, PhotoImportFailure> {
        beginImportProgress(count: 1)
        let result = await PhotoImportLoader.loadImage(from: provider) { progress in
            photoImportSession.track(progress, at: 0)
        }
        photoImportSession.finish(at: 0)
        endImportProgress()
        return result
    }

    /// Downloads one picked movie behind the import overlay.
    private func downloadPickedMovie(
        _ provider: NSItemProvider
    ) async -> Result<URL, PhotoImportFailure> {
        beginImportProgress(count: 1)
        let result = await PhotoImportLoader.loadMovie(from: provider) { progress in
            photoImportSession.track(progress, at: 0)
        }
        photoImportSession.finish(at: 0)
        endImportProgress()
        return result
    }

    // MARK: - Background tile

    /// Saves a picked still as the home-grid Background.
    func handlePickedLogo(_ provider: NSItemProvider) {
        Task { @MainActor in
            let result = await downloadPickedImage(provider)
            pendingLogoPick = false
            switch result {
            case .success(let image):
                // Save only — tap Background to go live. Already-live output
                // refreshes via LogoStore.didChangeNotification.
                LogoStore.shared.save(image)
            case .failure(let failure):
                reportImportFailure(failure, noun: "image") { [weak self] in
                    self?.handlePickedLogo(provider)
                }
            }
        }
    }

    // MARK: - Screensaver

    /// Replaces the Screensaver with a picked image or video.
    func handlePickedScreensaver(_ provider: NSItemProvider) {
        if PhotoImportLoader.isMovie(provider) {
            handlePickedScreensaverVideo(provider)
            return
        }
        guard PhotoImportLoader.isImage(provider) else {
            pendingScreensaverPick = false
            showAlert(
                title: "Couldn't Replace",
                message: "Choose an image or video for the Screensaver."
            )
            return
        }
        Task { @MainActor in
            let result = await downloadPickedImage(provider)
            pendingScreensaverPick = false
            switch result {
            case .success(let image):
                // Save only — tap Screensaver to go live. Already-live output
                // refreshes via ScreensaverStore.didChangeNotification.
                ScreensaverStore.shared.saveImage(image)
            case .failure(let failure):
                reportImportFailure(failure, noun: "image") { [weak self] in
                    self?.handlePickedScreensaver(provider)
                }
            }
        }
    }

    private func handlePickedScreensaverVideo(_ provider: NSItemProvider) {
        Task { @MainActor in
            let result = await downloadPickedMovie(provider)
            pendingScreensaverPick = false
            switch result {
            case .success(let localURL):
                ScreensaverStore.shared.saveVideo(from: localURL)
                cleanupTempFile(at: localURL)
            case .failure(let failure):
                reportImportFailure(failure, noun: "video") { [weak self] in
                    self?.handlePickedScreensaver(provider)
                }
            }
        }
    }

    // MARK: - Library adds

    /// Single video add: download, validate, then open the thumbnail picker.
    func handlePickedVideo(_ provider: NSItemProvider) {
        Task { @MainActor in
            switch await downloadPickedMovie(provider) {
            case .success(let localURL):
                switch await MediaValidator.validateVideo(at: localURL) {
                case .valid:
                    showVideoThumbnailPreview(for: localURL)
                case .invalid(let reason):
                    cleanupTempFile(at: localURL)
                    showAlert(title: "Video Rejected", message: reason)
                }
            case .failure(let failure):
                reportImportFailure(failure, noun: "video") { [weak self] in
                    self?.handlePickedVideo(provider)
                }
            }
        }
    }

    /// Re-send of a purged Apple TV item: keeps crop/confirm so it can be framed.
    ///
    /// The restore id is put back only by Try Again. Left set after a failed
    /// download it would turn the user's next ordinary send into a restore.
    func handlePickedImage(_ provider: NSItemProvider) {
        Task { @MainActor in
            switch await downloadPickedImage(provider) {
            case .success(let image):
                // Vertical + non-9:16 → crop first; otherwise confirm preview.
                presentImageAddFlow(for: image)
            case .failure(let failure):
                let restoreId = connectionManager.pendingRestoreId
                connectionManager.pendingRestoreId = nil
                reportImportFailure(failure, noun: "image") { [weak self] in
                    self?.connectionManager.pendingRestoreId = restoreId
                    self?.handlePickedImage(provider)
                }
            }
        }
    }
}
