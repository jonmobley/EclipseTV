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
        showPresentationToast(
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
        setupHomeFooter()
        setupMusicDrawer()
        raiseAudioMiniChrome()
        setupTransferOverlay()
        setupImportProgressOverlay()
    }

    /// Pins the header bar to the top safe area.
    private func setupHeaderBar() {
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerBar.setAddMenu(makeAddMenu())
        headerBar.onOpenSettings = { [weak self] in
            self?.presentSettings()
        }
        headerBar.onGoBack = { [weak self] in
            self?.libraryViewController.closeOpenShow()
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
        headerBar.onDoneArranging = { [weak self] in
            self?.libraryViewController.commitArranging()
        }
        headerBar.onDoneSelecting = { [weak self] in
            self?.libraryViewController.cancelSelecting()
        }
        headerBar.onSelectDestination = { [weak self] destination in
            self?.selectHeaderDestination(destination)
        }
        headerBar.onSelectTab = { [weak self] tab in
            self?.selectHomeTab(tab)
        }
        headerBar.onAddMusic = { [weak self] in
            guard let self else { return }
            self.audioLibraryViewController.presentAddMenu(
                from: self.headerBar.addMusicAnchor
            )
        }
        view.addSubview(headerBar)

        let headerHeight = headerBar.heightAnchor.constraint(
            equalToConstant: HomeHeaderBar.rowHeight
        )
        headerHeightConstraint = headerHeight
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
            headerHeight
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
    /// Every orientation uses the same compact card joined to the Music circle;
    /// only its width changes with the available room.
    private func setupAudioMiniPlayer() {
        audioMiniPlayer.translatesAutoresizingMaskIntoConstraints = false
        audioMiniPlayer.isHidden = true
        audioMiniPlayer.onOpenLibrary = { [weak self] in
            self?.presentNowPlaying()
        }
        audioMiniPlayer.onStop = { [weak self] in
            self?.stopAmbientPlayback()
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
        let cardWidth = audioMiniPlayer.widthAnchor.constraint(
            equalToConstant: AudioMiniPlayerView.compactWidth
        )
        audioMiniCardWidthConstraint = cardWidth
        let bubbleBottom = audioMiniBubble.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -AudioMiniPlayerView.compactBottomInset
        )
        audioMiniBubbleBottomConstraint = bubbleBottom
        NSLayoutConstraint.activate([
            height,
            cardWidth,
            // Card runs under the Music circle, which sits in its bottom corner.
            audioMiniPlayer.trailingAnchor.constraint(
                equalTo: audioMiniBubble.leadingAnchor,
                constant: AudioMiniPlayerView.connectedOverlap
            ),
            // The card hangs off the circle, so the two rise together.
            audioMiniPlayer.bottomAnchor.constraint(equalTo: audioMiniBubble.bottomAnchor),
            audioMiniBubble.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -AudioMiniPlayerView.compactTrailingInset
            ),
            bubbleBottom
        ])

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

    /// Reveals Music: pager page or floating drawer.
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

    /// Adds the transfer Cancel control above the library content. Transfer status
    /// itself is the shared presentation toast, centered so it clears this button.
    private func setupTransferOverlay() {
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        // Full width on a portrait phone, capped so it isn't a screen-wide bar in
        // landscape or on iPad; kept inside the safe area clear of the notch.
        let safe = view.safeAreaLayoutGuide
        let fillWidth = cancelButton.widthAnchor.constraint(
            equalTo: safe.widthAnchor, constant: -80
        )
        fillWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            cancelButton.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -24),
            cancelButton.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            fillWidth,
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
            showPresentationToast("Showing on AirPlay. EclipseTV is parked.")
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
        let picker = makeMediaLibraryPicker()
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
        let openShow = libraryViewController.openShow
        picker.headerSelection = HomeHeaderNavSelection(
            isShowMode: openShow != nil,
            isMusicPinned: false,
            showTitle: openShow?.name ?? HomeHeaderDestination.show.title
        )
        picker.onSelectHeaderDestination = { [weak self] destination in
            guard let self else { return }
            switch destination {
            case .home:
                self.libraryViewController.closeOpenShow()
            case .show:
                // Back on the open Show already; with none open, offer the list.
                if self.libraryViewController.openShowId == nil {
                    self.libraryViewController.presentAllShows()
                }
            case .library, .music:
                break
            }
        }
        showMediaLibraryPage(picker)
    }

    /// A Library page wired to the grid's edit, delete and re-send actions.
    ///
    /// Shared by the pushed page (which may add to a Show) and the pager's Library
    /// page (which only browses and previews).
    func makeMediaLibraryPicker() -> MediaLibraryPickerViewController {
        let picker = MediaLibraryPickerViewController()
        picker.onRequestEdit = { [weak self] id in
            self?.beginEditCrop(forItemId: id)
        }
        picker.onRequestTrim = { [weak self] id in
            self?.beginTrimVideo(forItemId: id)
        }
        picker.onApplyScreenFit = { [weak self] item, mode in
            self?.libraryViewController.applyScreenFit(mode, to: item)
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
        return picker
    }

    /// Pushes onto the Home nav stack, or presents full-screen when there is none.
    ///
    /// iPad destination tabs swap instantly — a slide made Library feel like a
    /// different app instead of the Home / Show / Library cluster.
    private func showMediaLibraryPage(_ picker: MediaLibraryPickerViewController) {
        let animated = !HomeHeaderNavLayout.usesInstantLibraryTransition(
            horizontalSizeClass: traitCollection.horizontalSizeClass,
            verticalSizeClass: traitCollection.verticalSizeClass
        )
        picker.usesInstantTransition = !animated
        if let nav = navigationController {
            navigationItem.backButtonTitle = "Back"
            nav.pushViewController(picker, animated: animated)
            return
        }
        let wrapped = UINavigationController(rootViewController: picker)
        wrapped.modalPresentationStyle = .fullScreen
        presentationAnchor.present(wrapped, animated: animated)
    }
}
