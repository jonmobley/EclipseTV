//
//  iPhoneMainViewController+Library.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import MultipeerConnectivity

// MARK: - Library Title & Settings

extension iPhoneMainViewController {

    /// Rebuilds the center title/menu and "+" menu for Home or open Show.
    func refreshLibraryMenu() {
        if let show = libraryViewController.openShow {
            headerBar.setCenterTitle(show.name)
        } else {
            headerBar.setCenterTitle("Eclipse")
        }
        headerBar.setLibraryMenu(makeLibraryMenu())
        headerBar.setAddMenu(makeAddMenu())
        refreshPresentedSettingsConnectionState()
    }

    /// Home: Shows + New Show. Show mode: Home, Shows, New Show, arrange actions.
    func makeLibraryMenu() -> UIMenu {
        if libraryViewController.isArranging {
            let done = UIAction(
                title: "Done Arranging",
                image: UIImage(systemName: "checkmark")
            ) { [weak self] _ in
                _ = self?.libraryViewController.commitArranging()
                self?.refreshLibraryMenu()
            }
            return UIMenu(children: [done])
        }

        if let open = libraryViewController.openShow {
            return makeOpenShowMenu(openShow: open)
        }

        let shows = LocalAlbumStore.shared.albumsForCurrentMode
        let showActions: [UIAction] = shows.map { show in
            UIAction(
                title: show.name,
                image: UIImage(systemName: "rectangle.stack")
            ) { [weak self] _ in
                self?.libraryViewController.openLocalAlbum(id: show.id)
            }
        }
        let newShow = UIAction(
            title: "New Show…",
            image: UIImage(systemName: "plus")
        ) { [weak self] _ in
            self?.promptNewAlbum()
        }
        guard !showActions.isEmpty else {
            return UIMenu(children: [newShow])
        }
        let showGroup = UIMenu(title: "", options: .displayInline, children: showActions)
        return UIMenu(children: [showGroup, newShow])
    }

    private func makeOpenShowMenu(openShow: LocalAlbum) -> UIMenu {
        let home = UIAction(
            title: "Home",
            image: UIImage(systemName: "house")
        ) { [weak self] _ in
            self?.libraryViewController.closeOpenShow()
        }

        let others = LocalAlbumStore.shared.albumsForCurrentMode
            .filter { $0.id != openShow.id }
            .map { show in
                UIAction(
                    title: show.name,
                    image: UIImage(systemName: "rectangle.stack")
                ) { [weak self] _ in
                    self?.libraryViewController.openLocalAlbum(id: show.id)
                }
            }

        let newShow = UIAction(
            title: "New Show…",
            image: UIImage(systemName: "plus")
        ) { [weak self] _ in
            self?.promptNewAlbum()
        }

        var arrange = UIAction(
            title: "Arrange",
            image: UIImage(systemName: "arrow.up.arrow.down")
        ) { [weak self] _ in
            self?.libraryViewController.beginArranging()
            self?.refreshLibraryMenu()
        }
        if libraryViewController.openShowItems.count < 2 {
            arrange.attributes = .disabled
        }

        let rename = UIAction(
            title: "Rename",
            image: UIImage(systemName: "pencil")
        ) { [weak self] _ in
            self?.libraryViewController.promptRenameOpenShow()
        }
        let delete = UIAction(
            title: "Delete Show",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.libraryViewController.confirmDeleteOpenShow()
        }

        var children: [UIMenuElement] = [home]
        if !others.isEmpty {
            children.append(UIMenu(title: "", options: .displayInline, children: others))
        }
        children.append(newShow)
        children.append(UIMenu(
            title: "",
            options: .displayInline,
            children: [arrange, rename, delete]
        ))
        return UIMenu(children: children)
    }

    @objc func libraryMenuContextDidChange() {
        refreshLibraryMenu()
    }

    /// Switches the viewed library to `name`. Connects if that Apple TV is nearby.
    func selectLibrary(named name: String) {
        preferredTVName = name
        TVLibraryStore.shared.setActiveTV(name)

        // Choosing a TV is an explicit request to use the Eclipse TV app.
        isConnectionPaused = false
        connectionManager.autoConnectEnabled = true

        if let peer = connectionManager.discoveredPeers.first(where: { $0.displayName == name }) {
            if !connectionManager.isConnectedToPeer(peer) {
                TVLibraryStore.shared.setOnline(false)
                updateConnectedState(false, peer: peer)
            }
            selectedPeer = peer
            connectionManager.switchToPeer(peer)
        } else {
            connectionManager.disconnect()
            selectedPeer = nil
            TVLibraryStore.shared.setOnline(false)
            updateConnectedState(false, peer: nil)
            startSearching()
        }

        refreshLibraryMenu()
    }

    /// Current Multipeer link state for Settings / header.
    func currentConnectionDisplayState() -> HomeHeaderBar.ConnectionDisplayState {
        if isConnected() { return .connected }
        if isConnectionPaused { return .paused }
        return .disconnected
    }

    /// Presents Settings (display mode, EclipseTV, sync, known TVs).
    /// When `focusEclipseTV` is true, scrolls to the EclipseTV section.
    func presentSettings(focusEclipseTV: Bool = false) {
        let settings = SettingsViewController()
        settings.setConnectionState(settingsConnectionState())
        settings.onLibrariesChanged = { [weak self] in
            self?.refreshLibraryMenu()
            self?.libraryViewController.collectionView.reloadData()
        }
        settings.onSyncPreferenceChanged = { [weak self] isOn in
            self?.connectionManager.syncAllEnabled = isOn
            MultiTVSyncCoordinator.shared.reset()
        }
        settings.onConnect = { [weak self, weak settings] in
            self?.resumeConnection()
            settings?.setConnectionState(self?.settingsConnectionState() ?? .paused)
        }
        settings.onStopConnecting = { [weak self, weak settings] in
            self?.pauseConnection()
            settings?.setConnectionState(self?.settingsConnectionState() ?? .paused)
        }
        settings.onSelectTV = { [weak self] name in
            self?.selectLibrary(named: name)
        }
        settings.onJoinPresentation = { [weak self] in
            self?.dismiss(animated: true) {
                self?.presentAlbums()
            }
        }
        let nav = UINavigationController(rootViewController: settings)
        present(nav, animated: true) {
            if focusEclipseTV {
                settings.scrollToEclipseTVSection()
            }
        }
    }

    private func settingsConnectionState() -> SettingsViewController.ConnectionDisplayState {
        switch currentConnectionDisplayState() {
        case .connected: return .connected
        case .disconnected: return .disconnected
        case .paused: return .paused
        }
    }

    /// Keeps an open Settings screen in sync with Multipeer link changes.
    private func refreshPresentedSettingsConnectionState() {
        guard let nav = presentedViewController as? UINavigationController,
              let settings = nav.viewControllers.first as? SettingsViewController else { return }
        settings.setConnectionState(settingsConnectionState())
    }
}
