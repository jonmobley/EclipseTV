//
//  iPhoneMainViewController+Setup.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// iPhoneMainViewController+Setup.swift
import AVFoundation
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocalAlbumsChanged),
            name: LocalAlbumStore.didChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleJoinedAccountConflict),
            name: JoinedAccountReconcile.conflictNotification,
            object: nil
        )
    }

    @objc private func handleLocalAlbumsChanged() {
        guard isConnected() else { return }
        connectionManager.sendSetLibraryAlbums(LibraryAlbumPush.currentAlbums())
    }

    @objc private func handleJoinedAccountConflict() {
        showTemporaryStatus(
            "Join codes differ — this phone and Apple TV are on different albums."
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

    /// Pins the header bar to the top safe area.
    private func setupHeaderBar() {
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerBar.setAddMenu(makeAddMenu())
        headerBar.onOpenSettings = { [weak self] in
            self?.presentSettings()
        }
        headerBar.onOpenOutputStatus = { [weak self] in
            self?.presentOutputStatusOptions()
        }
        headerBar.onToggleLiveLock = { [weak self] in
            self?.libraryViewController.toggleLiveOutputLock()
        }
        headerBar.onPresentBlack = { [weak self] in
            self?.libraryViewController.toggleBlackLive()
        }
        headerBar.onOpenGettingStarted = { [weak self] in
            self?.presentGettingStarted()
        }
        headerBar.onNewShow = { [weak self] in
            self?.promptNewAlbum()
        }
        headerBar.onDoneArranging = { [weak self] in
            self?.libraryViewController.commitArranging()
        }
        headerBar.onDoneSelecting = { [weak self] in
            self?.libraryViewController.cancelSelecting()
        }
        view.addSubview(headerBar)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            // Same side edges as the pager, so the header controls line up with the
            // content columns and keep clear of the Dynamic Island in landscape.
            headerBar.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor
            ),
            headerBar.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor
            ),
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

        // Reflect any display already connected at launch.
        headerBar.setPresenting(ExternalDisplayManager.shared.isConnected)
    }

    /// Pins the ambient music mini player / bubble above the home safe-area bottom.
    private func setupAudioMiniPlayer() {
        audioMiniPlayer.translatesAutoresizingMaskIntoConstraints = false
        audioMiniPlayer.isHidden = true
        audioMiniPlayer.onOpenLibrary = { [weak self] in
            self?.presentNowPlaying()
        }
        audioMiniPlayer.onTogglePlayPause = {
            AudioPlayerController.shared.togglePlayPause()
        }
        audioMiniPlayer.onMinimize = { [weak self] in
            self?.setAudioMiniCollapsed(true, animated: true)
        }
        view.addSubview(audioMiniPlayer)

        audioMiniBubble.translatesAutoresizingMaskIntoConstraints = false
        audioMiniBubble.isHidden = true
        audioMiniBubble.onExpand = { [weak self] in
            self?.setAudioMiniCollapsed(false, animated: true)
        }
        audioMiniBubble.onStop = { [weak self] in
            AudioPlayerController.shared.stop()
            self?.audioMiniCollapsed = true
            self?.isAudioMiniChromeAnimating = false
            HomeMusicSwipeHint.markEligibleAfterMiniPlayerClose()
            self?.libraryViewController.refreshMusicSwipeHintVisibility()
            self?.refreshAudioMiniPlayer()
        }
        view.addSubview(audioMiniBubble)

        let height = audioMiniPlayer.heightAnchor.constraint(equalToConstant: 0)
        audioMiniHeightConstraint = height
        audioMiniPortraitConstraints = [
            audioMiniPlayer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            audioMiniPlayer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            audioMiniPlayer.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor
            )
        ]
        // Constants track the live preview frame — don't pin across the pager
        // scroll view, which fights Auto Layout when content moves.
        let dockLeading = audioMiniPlayer.leadingAnchor.constraint(
            equalTo: view.leadingAnchor, constant: 0
        )
        let dockWidth = audioMiniPlayer.widthAnchor.constraint(equalToConstant: 160)
        let dockTop = audioMiniPlayer.topAnchor.constraint(
            equalTo: view.topAnchor, constant: 0
        )
        audioMiniDockLeadingConstraint = dockLeading
        audioMiniDockWidthConstraint = dockWidth
        audioMiniDockTopConstraint = dockTop
        audioMiniSideBySideConstraints = [dockLeading, dockWidth, dockTop]
        NSLayoutConstraint.activate(audioMiniPortraitConstraints + [
            height,
            audioMiniBubble.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16
            ),
            audioMiniBubble.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12
            )
        ])
        isAudioMiniSideBySide = false

        audioPlayerObserver = NotificationCenter.default.addObserver(
            forName: AudioPlayerController.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAudioMiniPlayer()
        }
        refreshAudioMiniPlayer()
    }

    /// Reveals the Music page to the right of the media grid (no-op when split).
    func presentAudioLibrary() {
        guard !isHomeSplitLayout else { return }
        showMusicPage(animated: true)
    }

    /// Presents the expanded Now Playing sheet for the ambient player.
    ///
    /// One at a time: the mini player is a plain button, and this goes up through
    /// `presentationAnchor`, which would happily stack a second sheet on the first.
    func presentNowPlaying() {
        guard !isAlreadyOpen(AudioNowPlayingViewController.self) else { return }
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
            sheet.selectedDetentIdentifier = .medium
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

    /// Presents the camera control surface (preview first; tap preview for AirPlay).
    ///
    /// Parks the home tile on a still first so the shared preview handoff doesn't
    /// flash black; keeps the session running for a live fullscreen open.
    func presentCameraLive() {
        guard !isAlreadyOpen(CameraLiveViewController.self) else { return }
        SlideshowPlaybackController.shared.stop()
        libraryViewController.parkHomeCameraTileForFullscreen()
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
           !ExternalDisplayManager.shared.isCameraModeActive,
           !CameraManager.shared.isSessionRunning {
            CameraManager.shared.prepareAndStart { }
        }
        let cameraVC = CameraLiveViewController()
        // Opened from inside a Show: what you shoot becomes a card in that Show.
        cameraVC.captureDestinationShowId = libraryViewController.openShow?.id
        cameraVC.modalPresentationStyle = .fullScreen
        present(cameraVC, animated: true)
        if TVLibraryStore.shared.isOnline, ExternalDisplayManager.shared.isConnected {
            showTemporaryStatus("Showing on AirPlay. EclipseTV is still on the library.")
        }
    }

    /// Presents History for managing saved sites (one list at a time).
    func presentPages() {
        if let open = openController(ofType: WebPagesViewController.self) {
            open.navigationController?.popToViewController(open, animated: true)
            return
        }
        if let compose = openController(ofType: AddWebsiteViewController.self),
           let nav = compose.navigationController {
            let history = WebPagesViewController()
            nav.pushViewController(history, animated: true)
            return
        }
        let pagesVC = WebPagesViewController()
        // The browser pushed from this list rotates with Landscape Display Mode.
        let nav = DisplayModeNavigationController(rootViewController: pagesVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    /// Presents a filterable sheet of existing images, videos, and PDFs.
    ///
    /// With an open Show: multi-select and **Add** appends cards (never goes live).
    /// Without a Show: tap presents the item (legacy path).
    func presentMediaLibrary() {
        guard !isAlreadyOpen(MediaLibraryPickerViewController.self) else { return }
        let picker = MediaLibraryPickerViewController()
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        if let showId = libraryViewController.openShowId {
            picker.targetShowId = showId
            picker.onAddToShow = { mediaIds, pdfIds in
                for id in mediaIds {
                    LocalAlbumStore.shared.add(itemId: id, toAlbumId: showId)
                }
                for id in pdfIds {
                    LocalAlbumStore.shared.add(itemId: id.uuidString, toAlbumId: showId)
                }
            }
        } else {
            picker.onSelectMedia = { [weak self, weak nav] item in
                nav?.dismiss(animated: true) {
                    self?.libraryViewController.presentMedia(item)
                }
            }
            picker.onSelectPDF = { [weak self, weak nav] doc in
                nav?.dismiss(animated: true) {
                    self?.libraryViewController.presentPDF(doc)
                }
            }
        }
        presentationAnchor.present(nav, animated: true)
    }
}
