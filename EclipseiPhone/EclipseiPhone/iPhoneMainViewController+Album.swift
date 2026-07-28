//
//  iPhoneMainViewController+Album.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// iPhoneMainViewController+Album.swift
import UIKit

// MARK: - Join Presentation (Remote Albums)

extension iPhoneMainViewController {

    /// Presents the join / remote-album browser. Works with or without a TV connection.
    /// When the user enters a join code, it is pushed to a connected Apple TV if any.
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
            self.libraryViewController.collectionView.reloadData()
            self.libraryViewController.refreshLiveHeader()
        }
        let nav = UINavigationController(rootViewController: albumsVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
}
