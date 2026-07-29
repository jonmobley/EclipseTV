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
        let openShow = libraryViewController.openShow
        headerBar.setCenterTitle(openShow?.name ?? "Eclipse")
        // Arrange mode keeps the user in the Show until they tap Done.
        headerBar.setShowingBackToHome(
            openShow != nil && !libraryViewController.isArranging
        )
        headerBar.setLibraryMenu(makeLibraryMenu())
        headerBar.setAddMenu(makeAddMenu())
        refreshPresentedSettingsConnectionState()
    }

    /// Home: Open Show + New Show + Settings. An open Show adds an Edit submenu.
    ///
    /// Arrange mode needs no entry here: the header disables this dropdown and
    /// offers Done as the single way to finish.
    func makeLibraryMenu() -> UIMenu {
        let openShow = libraryViewController.openShow
        var children: [UIMenuElement] = []
        if let shows = openShowSubmenu(excluding: openShow?.id) {
            children.append(shows)
        }
        children.append(newShowAction())
        if openShow != nil {
            children.append(editShowSubmenu())
        }
        children.append(settingsMenuAction())
        return UIMenu(children: children)
    }

    private func newShowAction() -> UIAction {
        UIAction(
            title: "New Show…",
            image: UIImage(systemName: "plus")
        ) { [weak self] _ in
            self?.promptNewAlbum()
        }
    }

    /// Arrange / Rename / Delete for the open Show, grouped under one entry.
    private func editShowSubmenu() -> UIMenu {
        let arrange = UIAction(
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

        return UIMenu(
            title: "Edit",
            image: UIImage(systemName: "square.and.pencil"),
            children: [
                UIMenu(title: "", options: .displayInline, children: [arrange, rename]),
                UIMenu(title: "", options: .displayInline, children: [delete])
            ]
        )
    }

    /// Settings entry for the Eclipse header dropdown.
    private func settingsMenuAction() -> UIAction {
        UIAction(
            title: "Settings",
            image: UIImage(systemName: "gearshape")
        ) { [weak self] _ in
            self?.presentSettings()
        }
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

    /// Presents Settings (playback prefs + EclipseTV drill-in).
    /// When `focusEclipseTV` is true, opens the EclipseTV detail page.
    func presentSettings(focusEclipseTV: Bool = false) {
        let settings = SettingsViewController()
        settings.setConnectionState(settingsConnectionState())
        settings.onLibrariesChanged = { [weak self] in
            self?.refreshLibraryMenu()
            self?.libraryViewController.collectionView.reloadData()
        }
        settings.onSyncPreferenceChanged = { [weak self] isOn in
            // Clear caught-up state before flipping the switch: the setter immediately
            // invites replicas, and a peer that connects first would have its fresh
            // signature wiped by a later reset.
            MultiTVSyncCoordinator.shared.reset()
            self?.connectionManager.syncAllEnabled = isOn
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
