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

    /// Updates the center title: Multipeer-linked device name, or "Library".
    func refreshLibraryMenu() {
        let connectedName = isConnected() ? selectedPeer?.displayName : nil
        headerBar.setLibraryTitle(connectedName)
        refreshPresentedSettingsConnectionState()
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

    /// Presents Settings (display mode, Eclipse TV app, sync, known TVs).
    func presentSettings() {
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
        settings.onArrange = { [weak self] in
            self?.dismiss(animated: true) {
                guard let self else { return }
                self.libraryViewController.beginArranging()
                self.headerBar.setArranging(true)
            }
        }
        settings.onSetUpAlbum = { [weak self] in
            self?.dismiss(animated: true) {
                self?.presentSetUpAlbum()
            }
        }
        let nav = UINavigationController(rootViewController: settings)
        present(nav, animated: true)
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
