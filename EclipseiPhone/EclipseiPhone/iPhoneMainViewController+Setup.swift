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
        embedHomePager()
        setupAudioMiniPlayer()
        setupTransferOverlay()
    }

    /// Pins the header bar (status + "+") to the top safe area.
    private func setupHeaderBar() {
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerBar.setAddMenu(makeAddMenu())
        headerBar.onOpenSettings = { [weak self] in
            self?.presentSettings()
        }
        headerBar.onStatusTapped = { [weak self] in
            self?.presentSettings(focusEclipseTV: true)
        }
        headerBar.onPresentBlack = { [weak self] in
            self?.libraryViewController.presentBlackLive()
        }
        view.addSubview(headerBar)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 52)
        ])

        refreshLibraryMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(libraryMenuContextDidChange),
            name: LocalAlbumStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(libraryMenuContextDidChange),
            name: ExternalOutputSettings.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(libraryMenuContextDidChange),
            name: PDFStore.didChangeNotification,
            object: nil
        )

        // Reflect any display already connected at launch.
        headerBar.setPresenting(ExternalDisplayManager.shared.isConnected)
    }

    /// Pins the ambient music mini player above the home safe-area bottom.
    private func setupAudioMiniPlayer() {
        audioMiniPlayer.translatesAutoresizingMaskIntoConstraints = false
        audioMiniPlayer.isHidden = true
        audioMiniPlayer.onOpenLibrary = { [weak self] in
            self?.presentNowPlaying()
        }
        audioMiniPlayer.onTogglePlayPause = {
            AudioPlayerController.shared.togglePlayPause()
        }
        audioMiniPlayer.onSkipNext = {
            AudioPlayerController.shared.playNext()
        }
        audioMiniPlayer.onToggleMute = {
            let player = AudioPlayerController.shared
            player.setMuted(!player.isMuted)
        }
        view.addSubview(audioMiniPlayer)

        let height = audioMiniPlayer.heightAnchor.constraint(equalToConstant: 0)
        audioMiniHeightConstraint = height
        NSLayoutConstraint.activate([
            audioMiniPlayer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            audioMiniPlayer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            audioMiniPlayer.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor
            ),
            height
        ])

        audioPlayerObserver = NotificationCenter.default.addObserver(
            forName: AudioPlayerController.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAudioMiniPlayer()
        }
        refreshAudioMiniPlayer()
    }

    /// Shows or hides the mini player and insets Library + Music pages.
    func refreshAudioMiniPlayer() {
        let active = AudioPlayerController.shared.hasActiveSession
        audioMiniPlayer.reload()
        let height: CGFloat = active ? AudioMiniPlayerView.preferredHeight : 0
        audioMiniHeightConstraint?.constant = height
        audioMiniPlayer.isHidden = !active
        libraryViewController.miniPlayerBottomInset = height
        audioLibraryViewController.miniPlayerBottomInset = height
        view.layoutIfNeeded()
    }

    /// Reveals the Music page to the right of the media grid (no-op when split).
    func presentAudioLibrary() {
        guard !isHomeSplitLayout else { return }
        showMusicPage(animated: true)
    }

    /// Presents the expanded Now Playing sheet for the ambient player.
    func presentNowPlaying() {
        let nowPlaying = AudioNowPlayingViewController()
        nowPlaying.onOpenLibrary = { [weak self] in
            self?.dismiss(animated: true) {
                guard let self, !self.isHomeSplitLayout else { return }
                self.showMusicPage(animated: true)
            }
        }
        let nav = UINavigationController(rootViewController: nowPlaying)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presentationAnchor.present(nav, animated: true)
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

    /// Presents the camera control surface (preview first; Go Live for AirPlay).
    ///
    /// The home tile is only a launcher / LIVE indicator — no mini preview.
    func presentCameraLive() {
        if presentedViewController is CameraLiveViewController { return }
        SlideshowPlaybackController.shared.stop()
        // Warm capture for phone framing — AirPlay waits for Go Live.
        if !ExternalDisplayManager.shared.isCameraModeActive {
            Task { @MainActor in
                let granted = await CameraManager.shared.checkPermissions()
                guard granted else { return }
                CameraManager.shared.prepareAndStart { }
            }
        }
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
