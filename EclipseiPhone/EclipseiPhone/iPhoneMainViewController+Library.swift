//
//  iPhoneMainViewController+Library.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// iPhoneMainViewController+Library.swift
import UIKit
import MultipeerConnectivity

// MARK: - Library Dropdown & Switching

extension iPhoneMainViewController {

    private static let relativeFormatter = RelativeDateTimeFormatter()

    /// Rebuilds the header dropdown from the union of currently discovered Apple TVs and
    /// the remembered (known) TVs, and updates the title to the active library.
    func refreshLibraryMenu() {
        let discoveredNames = connectionManager.discoveredPeers.map { $0.displayName }
        let known = KnownTVRegistry.shared.all()
        let activeName = TVLibraryStore.shared.activeTVName
        let connectedName = isConnected() ? selectedPeer?.displayName : nil

        // Known TVs first (most-recently-seen order), then any newly discovered ones.
        var names = known.map { $0.name }
        for name in discoveredNames where !names.contains(name) {
            names.append(name)
        }

        let items = names.map { name -> HomeHeaderBar.LibraryMenuItem in
            let subtitle: String?
            if name == connectedName {
                subtitle = "Connected"
            } else if discoveredNames.contains(name) {
                subtitle = "Available"
            } else if let tv = known.first(where: { $0.name == name }) {
                subtitle = "Last seen " + Self.relativeFormatter.localizedString(for: tv.lastSeen, relativeTo: Date())
            } else {
                subtitle = nil
            }
            return HomeHeaderBar.LibraryMenuItem(name: name, subtitle: subtitle, isActive: name == activeName)
        }

        headerBar.setLibraryMenu(items: items)
        headerBar.setLibraryTitle(activeName)
    }

    /// Switches the viewed library to `name`. If that Apple TV is currently reachable we
    /// connect to it; otherwise we show its cached library offline.
    func selectLibrary(named name: String) {
        preferredTVName = name
        TVLibraryStore.shared.setActiveTV(name)

        if let peer = connectionManager.discoveredPeers.first(where: { $0.displayName == name }) {
            if !connectionManager.isConnectedToPeer(peer) {
                // Show the cached library offline until the new connection is established.
                TVLibraryStore.shared.setOnline(false)
                updateConnectedState(false, peer: peer)
            }
            selectedPeer = peer
            connectionManager.switchToPeer(peer)
        } else {
            // Not reachable right now: drop any live connection and view the cache offline.
            connectionManager.disconnect()
            selectedPeer = nil
            TVLibraryStore.shared.setOnline(false)
            updateConnectedState(false, peer: nil)
            startSearching()
        }

        refreshLibraryMenu()
    }

    /// Presents the Settings screen (library sync toggle + known-TV management).
    func presentSettings() {
        let settings = SettingsViewController()
        settings.onLibrariesChanged = { [weak self] in
            self?.refreshLibraryMenu()
            self?.libraryViewController.collectionView.reloadData()
        }
        settings.onSyncPreferenceChanged = { [weak self] isOn in
            // Apply to the live connection manager: enabling fans out to / gathers replica
            // TVs; disabling stops replicating. Reset coordinator state so re-enabling
            // re-replays the library to reconnected TVs.
            self?.connectionManager.syncAllEnabled = isOn
            MultiTVSyncCoordinator.shared.reset()
        }
        let nav = UINavigationController(rootViewController: settings)
        present(nav, animated: true)
    }
}
