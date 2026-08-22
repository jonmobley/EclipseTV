//
//  iPhoneMainViewController+Album.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// iPhoneMainViewController+Album.swift
import UIKit

// MARK: - Show Sharing (Remote Albums)

extension iPhoneMainViewController {

    /// Prompts for a share code immediately, then opens the joined-show browser on success.
    func presentShareCodePrompt() {
        let store = AlbumBrowserStore.shared
        let alert = UIAlertController(
            title: "Enter Code",
            message: "Type your \(AlbumConfig.codeLength)-digit share code.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = String(repeating: "0", count: AlbumConfig.codeLength)
            field.keyboardType = .numberPad
            field.textContentType = .oneTimeCode
            field.text = store.accountCode
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Join", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let raw = alert?.textFields?.first?.text ?? ""
            guard store.setAccountCode(raw) else {
                self.presentInvalidShareCodeAlert()
                return
            }
            let code = AlbumConfig.normalize(raw)
            if self.isConnected() {
                _ = self.connectionManager.sendSetAccount(code: code)
            }
            self.presentAlbums()
        })
        present(alert, animated: true)
    }

    /// Presents the joined-show browser. Works with or without a TV connection.
    /// When the user enters a share code, it is pushed to a connected Apple TV if any.
    func presentAlbums() {
        let albumsVC = AlbumsViewController()
        albumsVC.onCodeEntered = { [weak self] code in
            guard let self = self, self.isConnected() else { return }
            _ = self.connectionManager.sendSetAccount(code: code)
        }
        albumsVC.onBecameLive = { [weak self] in
            self?.libraryViewController.clearLiveSelectionForJoinedPresent()
        }
        albumsVC.onLeftPresentation = { [weak self] in
            guard let self else { return }
            if ExternalDisplayManager.shared.isJoinedLive {
                ExternalDisplayManager.shared.clearJoinedLive()
                ExternalDisplayManager.shared.restoreCurrentSource()
            }
            self.libraryViewController.reloadLibraryGrid()
            self.libraryViewController.refreshLiveHeader()
        }
        let nav = UINavigationController(rootViewController: albumsVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func presentInvalidShareCodeAlert() {
        let alert = UIAlertController(
            title: "Invalid Code",
            message: "Enter your \(AlbumConfig.codeLength)-digit share code.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.presentShareCodePrompt()
        })
        present(alert, animated: true)
    }
}
