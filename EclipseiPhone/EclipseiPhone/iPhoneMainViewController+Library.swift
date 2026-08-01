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
        headerBar.setCenterTitle(openShow?.name ?? "Home")
        headerBar.setShowModeChrome(openShow != nil)
        headerBar.setLibraryMenu(makeLibraryMenu())
        headerBar.setAddMenu(makeAddMenu())
        refreshPresentedSettingsConnectionState()
    }

    /// Presents the Getting Started overview guide.
    func presentGettingStarted() {
        let guide = GettingStartedViewController()
        let nav = UINavigationController(rootViewController: guide)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    /// Home → Open Show → New Show → Library → Music → Settings, then Recent Shows.
    /// An open Show adds Home (leave Show mode). Show-mode also keeps the header
    /// gear for Settings with Edit Show; Home Settings omits show-specific rows.
    ///
    /// Open Show always lists every openable Show (only the currently open one is
    /// left out). Recent Shows stay inline as a short hop list — they must not
    /// suppress the Open Show verb, or libraries with ≤5 Shows lose that entry.
    ///
    /// Arrange mode needs no entry here: the header disables this dropdown and
    /// offers Done as the single way to finish.
    func makeLibraryMenu() -> UIMenu {
        let openShow = libraryViewController.openShow
        var children: [UIMenuElement] = []
        if openShow != nil {
            children.append(
                UIMenu(title: "", options: .displayInline, children: [goBackAction()])
            )
        }
        var excluded = Set<UUID>()
        if let openShowId = openShow?.id {
            excluded.insert(openShowId)
        }
        if let shows = openShowSubmenu(excluding: excluded) {
            children.append(shows)
        }
        children.append(newShowAction())
        children.append(mediaLibraryAction())
        children.append(musicAction())
        children.append(settingsAction())
        let recents = recentShowsForMenu(excluding: openShow?.id)
        if !recents.isEmpty {
            children.append(recentShowsMenu(recents))
        }
        return UIMenu(children: children)
    }

    /// Opens the Media Library picker from the Home dropdown.
    private func mediaLibraryAction() -> UIAction {
        UIAction(
            title: "Media Library",
            image: UIImage(systemName: "square.grid.2x2")
        ) { [weak self] _ in
            self?.presentMediaLibrary()
        }
    }

    /// Opens the Music page from the Home dropdown.
    private func musicAction() -> UIAction {
        UIAction(
            title: "Music",
            image: UIImage(systemName: "music.note")
        ) { [weak self] _ in
            self?.presentAudioLibrary()
        }
    }

    /// Closes the open Show and returns to Recent Shows.
    private func goBackAction() -> UIAction {
        UIAction(
            title: "Home",
            image: UIImage(systemName: "chevron.left")
        ) { [weak self] _ in
            self?.libraryViewController.closeOpenShow()
        }
    }

    private func newShowAction() -> UIAction {
        UIAction(
            title: "New Show…",
            image: UIImage(systemName: "plus")
        ) { [weak self] _ in
            self?.promptNewAlbum()
        }
    }

    private func settingsAction() -> UIAction {
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
    /// When a Show is open, Settings also hosts Edit Show actions.
    /// When `focusEclipseTV` is true, opens the EclipseTV detail page.
    func presentSettings(focusEclipseTV: Bool = false) {
        let settings = SettingsViewController()
        settings.setConnectionState(settingsConnectionState())
        configureOpenShowEditing(on: settings)
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
        settings.onEnterShareCode = { [weak self] in
            self?.dismiss(animated: true) {
                self?.presentShareCodePrompt()
            }
        }
        let nav = UINavigationController(rootViewController: settings)
        present(nav, animated: true) {
            if focusEclipseTV {
                settings.scrollToEclipseTVSection()
            }
        }
    }

    /// Wires Arrange / Rename / Share / Delete when Settings opens over a Show.
    private func configureOpenShowEditing(on settings: SettingsViewController) {
        guard let show = libraryViewController.openShow else {
            settings.openShowName = nil
            return
        }
        settings.openShowName = show.name
        settings.canArrangeShow = libraryViewController.openShowMembershipIds.count >= 2
        settings.onArrangeShow = { [weak self] in
            self?.dismiss(animated: true) {
                self?.libraryViewController.beginArranging()
                self?.refreshLibraryMenu()
            }
        }
        settings.onRenameShow = { [weak self] in
            self?.dismiss(animated: true) {
                self?.libraryViewController.promptRenameOpenShow()
            }
        }
        settings.onShareShow = { [weak self] in
            guard let self,
                  let id = self.libraryViewController.openShowId else { return }
            self.dismiss(animated: true) {
                EclipseSyncController.shared.backend.presentShareUI(
                    forShowId: id,
                    from: self
                )
            }
        }
        settings.onDeleteShow = { [weak self] in
            self?.dismiss(animated: true) {
                self?.libraryViewController.confirmDeleteOpenShow()
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
