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
        let remote = ShowLiveSession.shared
        let subtitle: String? = {
            guard remote.isRemoteOperator else { return nil }
            let name = remote.directorDeviceName ?? "another device"
            return "Live on \(name)"
        }()
        headerBar.setCenterTitle(openShow?.name ?? "Home", subtitle: subtitle)
        headerBar.setPreviewsWhenDisconnected(openShow?.previewsWhenDisconnected ?? false)
        headerBar.setShowModeChrome(openShow != nil)
        headerBar.setNavSelection(
            HomeHeaderNavSelection(
                isShowMode: openShow != nil,
                isMusicPinned: false,
                showTitle: openShow?.name ?? HomeHeaderDestination.show.title
            )
        )
        headerBar.setLibraryMenu(makeLibraryMenu())
        headerBar.setAddMenu(makeAddMenu())
        refreshPresentedSettingsConnectionState()
    }

    /// Open Show → New Show → Library → Music → Settings, then Recent Shows.
    /// Show mode drops Settings — the header gear already opens it. Return to
    /// Home is the compact back control or the iPad Home tab, not this menu.
    /// Home Settings omits show-specific rows.
    /// Getting Started lives in Settings, not this dropdown.
    ///
    /// Open Show presents the same Shows list as Home See All (not a nested menu).
    /// Recent Shows stay inline as a short hop list.
    ///
    /// Arrange mode needs no entry here: the header disables this dropdown and
    /// offers Done as the single way to finish.
    func makeLibraryMenu() -> UIMenu {
        let openShow = libraryViewController.openShow
        var children: [UIMenuElement] = []
        if let openList = openShowListAction() {
            children.append(openList)
        }
        children.append(newShowAction())
        children.append(mediaLibraryAction())
        children.append(musicAction())
        if openShow == nil {
            children.append(settingsAction())
        }
        let recents = recentShowsForMenu(excluding: openShow?.id)
        if !recents.isEmpty {
            children.append(recentShowsMenu(recents))
        }
        return UIMenu(children: children)
    }

    /// iPad header tabs: Home closes Show, Show opens the list, Library opens
    /// the media library. Music is the blue circle (and dropdown), not a tab.
    func selectHeaderDestination(_ destination: HomeHeaderDestination) {
        switch destination {
        case .home:
            libraryViewController.closeOpenShow()
        case .show:
            libraryViewController.presentAllShows()
        case .library:
            presentMediaLibrary()
        case .music:
            selectMusicDestination()
        }
    }

    /// Compact: opens the Music page. Regular: toggles the slide-out Music pane.
    private func selectMusicDestination() {
        if traitCollection.horizontalSizeClass == .regular {
            toggleMusicDrawer()
        } else {
            presentAudioLibrary()
        }
    }

    /// Opens the Library picker from the Home dropdown.
    private func mediaLibraryAction() -> UIAction {
        UIAction(
            title: "Library",
            image: UIImage(systemName: "square.grid.2x2")
        ) { [weak self] _ in
            self?.presentMediaLibrary()
        }
    }

    /// Compact: opens the Music page. Regular: toggles the slide-out Music pane.
    private func musicAction() -> UIAction {
        UIAction(
            title: "Music",
            image: UIImage(systemName: "music.note")
        ) { [weak self] _ in
            self?.selectMusicDestination()
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
    /// When a Show is open, Settings also hosts the show name and Delete.
    /// When `focusEclipseTV` is true, opens the EclipseTV detail page.
    func presentSettings(focusEclipseTV: Bool = false) {
        let settings = SettingsViewController()
        settings.setConnectionState(settingsConnectionState())
        configureOpenShowEditing(on: settings)
        settings.onLibrariesChanged = { [weak self] in
            self?.refreshLibraryMenu()
            self?.libraryViewController.reloadLibraryGrid()
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

    /// Wires name, Share, Delete, and Practice Mode when Settings opens over a Show.
    private func configureOpenShowEditing(on settings: SettingsViewController) {
        guard let show = libraryViewController.openShow else {
            settings.openShowName = nil
            settings.openShowId = nil
            return
        }
        settings.openShowName = show.name
        settings.openShowId = show.id
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
            guard let self, let id = self.libraryViewController.openShowId else { return }
            LocalAlbumStore.shared.delete(id: id)
            self.libraryViewController.closeOpenShow()
            self.dismiss(animated: true)
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
