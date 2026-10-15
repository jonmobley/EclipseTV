//
//  ImageViewController+OptionsButton.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// ImageViewController+OptionsButton.swift
import UIKit

// MARK: - Top-Right Options Button (tvOS dropdown menu)

extension ImageViewController {

    /// Adds the top-right options button to the safe area and attaches a dropdown menu
    /// that rebuilds itself each time it opens (so configured/unconfigured items stay in
    /// sync). Call once during view setup. This is the discoverable, on-screen equivalent
    /// of the legacy Menu-button action sheet (`showOptionsMenu()`).
    func setupOptionsButton() {
        view.addSubview(optionsButton)
        NSLayoutConstraint.activate([
            optionsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            optionsButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
        ])

        optionsButton.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.optionsMenuElements() ?? [])
            }
        ])

        updateOptionsButtonVisibility()
    }

    /// Builds the current dropdown items, mirroring the actions in `showOptionsMenu()`.
    private func optionsMenuElements() -> [UIMenuElement] {
        var elements: [UIMenuElement] = []

        if albumStore.hasAlbumConfigured || AlbumConfig.offersAccountCodeEntry {
            let codeTitle = albumStore.hasAlbumConfigured ? "Change Account Code" : "Enter Account Code"
            elements.append(UIAction(title: codeTitle,
                                     image: UIImage(systemName: "number")) { [weak self] _ in
                self?.presentAccountCodeEntry()
            })
        }

        if albumStore.hasAlbumConfigured {
            elements.append(UIAction(title: "Refresh Albums",
                                     image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                self?.refreshAlbumFromMenu()
            })
            elements.append(UIAction(title: "Remove Albums",
                                     image: UIImage(systemName: "trash"),
                                     attributes: .destructive) { [weak self] _ in
                self?.confirmRemoveAlbums()
            })
        }

        elements.append(UIAction(title: "Show Pairing Code",
                                 image: UIImage(systemName: "lock.rectangle")) { [weak self] _ in
            self?.presentPairingCode()
        })

        elements.append(UIAction(title: "Forget Paired iPhones",
                                 image: UIImage(systemName: "iphone.slash")) { [weak self] _ in
            self?.confirmForgetPairedPhones()
        })

        elements.append(UIAction(title: "Show Help",
                                 image: UIImage(systemName: "questionmark.circle")) { [weak self] _ in
            self?.showHelp()
        })

        #if DEBUG
        elements.append(UIAction(title: "Load Demo Album",
                                 image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in
            self?.loadDemoAlbum()
        })
        #endif

        return elements
    }

    /// Shows the options button only while the grid is visible, and keeps it above the
    /// full-screen grid collection view so it stays focusable.
    func updateOptionsButtonVisibility() {
        optionsButton.isHidden = !isInGridMode
        if isInGridMode {
            view.bringSubviewToFront(optionsButton)
        }
    }
}

// MARK: - Remove Albums

extension ImageViewController {

    /// Asks before deleting every downloaded album and the saved account code.
    func confirmRemoveAlbums() {
        let alert = UIAlertController(
            title: "Remove Albums?",
            message: "This deletes the downloaded albums from this Apple TV. You'll need the account code to get them back.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            self?.albumStore.clearAlbum()
            self?.albumNotifier.stop()
            self?.showNotificationToast(message: "Albums removed")
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}
