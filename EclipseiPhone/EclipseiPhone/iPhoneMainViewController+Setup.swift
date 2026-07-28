//
//  iPhoneMainViewController+Setup.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// iPhoneMainViewController+Setup.swift
import UIKit
import os

// MARK: - Notification Observers & UI Setup

extension iPhoneMainViewController {

    func setupNotificationObservers() {
        // Monitor app state changes to maintain connection
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalDisplayChange),
            name: ExternalDisplayManager.didChangeNotification,
            object: nil
        )
    }

    @objc private func handleExternalDisplayChange() {
        DispatchQueue.main.async { [weak self] in
            self?.headerBar.setPresenting(ExternalDisplayManager.shared.isConnected)
        }
    }

    @objc private func handleAppWillEnterForeground() {
        logger.debug("App will enter foreground")
        // Don't start searching yet, wait for didBecomeActive
    }

    @objc private func handleAppDidBecomeActive() {
        logger.debug("App did become active")

        // Only reconnect if the user has opted into the Eclipse TV app link.
        guard !isConnectionPaused, selectedPeer != nil, !isConnected() else { return }
        updateConnectedState(false, peer: selectedPeer)
        startSearching()
    }

    @objc private func handleAppDidEnterBackground() {
        logger.debug("App did enter background")
        // Pause timers when entering background to save battery
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
        // Keep status fade timer running as it's short-lived
    }

    func setupUI() {
        view.backgroundColor = .systemBackground

        setupHeaderBar()
        embedLibrary()
        setupTransferOverlay()
    }

    /// Pins the header bar (status + "+") to the top safe area.
    private func setupHeaderBar() {
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerBar.onAddTapped = { [weak self] in
            self?.mediaPickerButtonTapped()
        }
        headerBar.onArrangeDone = { [weak self] in
            guard let self = self else { return }
            if self.libraryViewController.commitArranging() {
                self.headerBar.setArranging(false)
            }
        }
        headerBar.onArrangeCancel = { [weak self] in
            guard let self = self else { return }
            self.libraryViewController.cancelArranging()
            self.headerBar.setArranging(false)
        }
        headerBar.onBrowseAlbums = { [weak self] in
            self?.presentAlbums()
        }
        headerBar.onBrowseWeb = { [weak self] in
            self?.presentPages()
        }
        headerBar.onOpenSettings = { [weak self] in
            self?.presentSettings()
        }
        headerBar.onConnect = { [weak self] in
            self?.resumeConnection()
        }
        headerBar.onPresentCamera = { [weak self] in
            self?.presentCameraLive()
        }
        view.addSubview(headerBar)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 52)
        ])

        // Populate the dropdown with any remembered Apple TVs and the active library.
        refreshLibraryMenu()

        // Reflect any display already connected at launch.
        headerBar.setPresenting(ExternalDisplayManager.shared.isConnected)
    }

    /// Embeds the library grid as a child controller filling the area below the header.
    private func embedLibrary() {
        libraryViewController.onRequestResend = { [weak self] id in
            self?.beginResend(forItemId: id)
        }
        libraryViewController.onRequestEdit = { [weak self] id in
            self?.beginEditCrop(forItemId: id)
        }

        addChild(libraryViewController)
        let gridView = libraryViewController.view!
        gridView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gridView)
        NSLayoutConstraint.activate([
            gridView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        libraryViewController.didMove(toParent: self)
    }

    /// Adds the transfer status overlay (message + cancel) above the library content.
    private func setupTransferOverlay() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),

            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            cancelButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
    }

    func setupConnectionManager() {
        connectionManager.delegate = self
        // AirPlay-first: do not browse for the Eclipse TV app until the user asks.
        connectionManager.autoConnectEnabled = false
        headerBar.setConnectionState(.paused)

        // Wire up the multi-TV sync coordinator so newly connected replica TVs get caught
        // up to the active library when "Keep all Apple TVs in sync" is enabled.
        let coordinator = MultiTVSyncCoordinator.shared
        coordinator.connectionManager = connectionManager
        connectionManager.syncCoordinator = coordinator
    }

    /// Presents the live camera control surface for AirPlay output.
    func presentCameraLive() {
        let cameraVC = CameraLiveViewController()
        cameraVC.modalPresentationStyle = .fullScreen
        present(cameraVC, animated: true)
    }

    /// Presents the saved Web list for AirPlay web display.
    func presentPages() {
        let pagesVC = WebPagesViewController()
        let nav = UINavigationController(rootViewController: pagesVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
}
