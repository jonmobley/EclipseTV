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
        setupMusicDrawer()
        view.bringSubviewToFront(musicDrawer)
        setupTransferOverlay()
    }

    /// Pins the header bar to the top safe area.
    private func setupHeaderBar() {
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerBar.setAddMenu(makeAddMenu())
        headerBar.onOpenSettings = { [weak self] in
            self?.presentSettings()
        }
        headerBar.onToggleLiveLock = { [weak self] in
            self?.libraryViewController.toggleLiveOutputLock()
        }
        headerBar.onPresentBlack = { [weak self] in
            self?.libraryViewController.toggleBlackLive()
        }
        headerBar.onNewShow = { [weak self] in
            self?.promptNewAlbum()
        }
        headerBar.onGoHome = { [weak self] in
            self?.libraryViewController.closeOpenShow()
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

    /// Pins the ambient music mini player / bubble to the home bottom.
    ///
    /// Portrait is a full-width footer through the home indicator so tiles cannot
    /// show under the bar. Landscape is a compact card beside the Music bubble.
    private func setupAudioMiniPlayer() {
        audioMiniPlayer.translatesAutoresizingMaskIntoConstraints = false
        audioMiniPlayer.isHidden = true
        audioMiniPlayer.onOpenLibrary = { [weak self] in
            self?.presentNowPlaying()
        }
        audioMiniPlayer.onMinimize = { [weak self] in
            self?.setAudioMiniCollapsed(true, animated: true)
        }
        view.addSubview(audioMiniPlayer)

        audioMiniBubble.translatesAutoresizingMaskIntoConstraints = false
        audioMiniBubble.isHidden = true
        audioMiniBubble.onToggle = { [weak self] in
            self?.handleAudioMiniBubbleToggle()
        }
        view.addSubview(audioMiniBubble)

        let height = audioMiniPlayer.heightAnchor.constraint(equalToConstant: 0)
        audioMiniHeightConstraint = height
        audioMiniPortraitConstraints = [
            audioMiniPlayer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            audioMiniPlayer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            audioMiniPlayer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]
        // Compact card sits beside the Music bubble in the same corner.
        let landTrailing = audioMiniPlayer.trailingAnchor.constraint(
            equalTo: audioMiniBubble.leadingAnchor,
            constant: -AudioMiniPlayerView.circleFooterGap
        )
        let landBottom = audioMiniPlayer.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -AudioMiniPlayerView.compactBottomInset
        )
        let landWidth = audioMiniPlayer.widthAnchor.constraint(
            equalToConstant: AudioMiniPlayerView.compactWidth
        )
        audioMiniLandscapeWidthConstraint = landWidth
        audioMiniLandscapeConstraints = [landTrailing, landBottom, landWidth]
        NSLayoutConstraint.activate(audioMiniPortraitConstraints + [
            height,
            audioMiniBubble.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -AudioMiniPlayerView.compactTrailingInset
            ),
            audioMiniBubble.bottomAnchor.constraint(
                equalTo: view.bottomAnchor,
                constant: -AudioMiniPlayerView.compactBottomInset
            )
        ])
        isAudioMiniLandscapeCompact = false

        hadActiveAudioSession = AudioPlayerController.shared.hasActiveSession
        audioPlayerObserver = NotificationCenter.default.addObserver(
            forName: AudioPlayerController.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAudioPlayerDidChange()
        }
        refreshAudioMiniPlayer()
    }

    /// Reveals Music: pager page, floating drawer, or no-op when already pinned.
    func presentAudioLibrary() {
        showMusicPage(animated: true)
    }

    /// Presents the Music library as a bottom sheet to choose something to play.
    ///
    /// Stays on Home instead of paging to the Music page. One at a time via the
    /// presented chain (embedded Music is a child, so it does not false-positive).
    func presentMusicPicker() {
        guard !isAlreadyOpen(AudioLibraryViewController.self) else { return }
        let nav = AudioLibraryViewController.makePickerNavigation { [weak self] in
            self?.showAudioPicker()
        }
        presentationAnchor.present(nav, animated: true)
    }

    /// Presents the expanded Now Playing sheet for the ambient player.
    ///
    /// One at a time: the mini player is a plain button, and this goes up through
    /// `presentationAnchor`, which would happily stack a second sheet on the first.
    func presentNowPlaying() {
        guard !isAlreadyOpen(AudioNowPlayingViewController.self) else { return }
        let nav = AudioNowPlayingViewController.makeNavigation { [weak self] in
            self?.presentMusicPicker()
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

    /// Presents the camera control surface without changing live output.
    ///
    /// Parks the home tile on a still first so the shared preview handoff doesn't
    /// flash black; keeps the session running for a live fullscreen open. Tap the
    /// stage to put Camera on AirPlay.
    func presentCameraLive() {
        guard !isAlreadyOpen(CameraLiveViewController.self) else { return }
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
            showTemporaryStatus("Showing on AirPlay. EclipseTV is parked.")
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

    /// Opens Media Library as a page of existing images, videos, and PDFs.
    ///
    /// With an open Show: multi-select and **Add** appends cards (never goes live).
    /// Without a Show: tap Previews on top of this page (library stays open).
    func presentMediaLibrary() {
        guard !isAlreadyOpen(MediaLibraryPickerViewController.self) else { return }
        let picker = MediaLibraryPickerViewController()
        picker.onRequestEdit = { [weak self] id in
            self?.beginEditCrop(forItemId: id)
        }
        picker.onRequestVideoThumbnail = { [weak self] id in
            self?.beginChangeVideoThumbnail(forItemId: id)
        }
        picker.onApplyVideoSetting = { [weak self] id, isLooping, isMuted in
            self?.libraryViewController.applyVideoSetting(
                id: id, isLooping: isLooping, isMuted: isMuted
            )
        }
        picker.onPerformDelete = { [weak self] id in
            self?.libraryViewController.performDelete(id: id)
        }
        picker.onRequestResend = { [weak self] id in
            self?.beginResend(forItemId: id)
        }
        picker.onIsEclipseTVLinked = { [weak self] in
            self?.isConnected() ?? false
        }
        picker.onRequestEclipseTVConnect = { [weak self] in
            self?.resumeConnection()
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
        }
        showMediaLibraryPage(picker)
    }

    /// Pushes onto the Home nav stack, or presents full-screen when there is none.
    private func showMediaLibraryPage(_ picker: MediaLibraryPickerViewController) {
        if let nav = navigationController {
            navigationItem.backButtonTitle = "Back"
            nav.pushViewController(picker, animated: true)
            return
        }
        let wrapped = UINavigationController(rootViewController: picker)
        wrapped.modalPresentationStyle = .fullScreen
        presentationAnchor.present(wrapped, animated: true)
    }
}
