//
//  iPhoneMainViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import MultipeerConnectivity
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import os

class iPhoneMainViewController: UIViewController {
    
    // MARK: - UI Elements

    /// Top header: connection status (leading) and the blue "+" media button (trailing).
    let headerBar = HomeHeaderBar()

    /// The library grid is the home screen; it's embedded as a child view controller.
    lazy var libraryViewController = LibraryGridViewController(connectionManager: connectionManager)

    /// Music list; pager page on compact, drawer or pinned sidebar on regular width.
    lazy var audioLibraryViewController = AudioLibraryViewController(embedded: true)

    /// Horizontal pager hosting Library (page 0) and Music (page 1).
    let homePagerScrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.isPagingEnabled = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.bounces = false
        scroll.alwaysBounceVertical = false
        scroll.isDirectionalLockEnabled = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    /// Navigation stack for the Music page. An open playlist stays here so
    /// Show ↔ Music paging returns to that playlist instead of the library list.
    var audioLibraryNavController: UINavigationController?
    /// 0 = Library, 1 = Music.
    var homePageIndex = 0
    /// True when Library and Music share the home screen (unused; drawer-only on
    /// regular width). Kept so layout math can still branch on `.split`.
    var isHomeSplitLayout = false
    /// Legacy pinned-sidebar preference (ignored for layout; regular is drawer).
    var isMusicSidebarPinned = HomeMusicLayout.isPinned()
    /// True while Music is hosted in the floating drawer (regular width).
    var isMusicInDrawer = false
    /// Overlay drawer for Music on regular width.
    let musicDrawer = HomeMusicDrawerView()
    /// Pager constraints for the Music page; empty while Music is in the drawer.
    var musicPagerConstraints: [NSLayoutConstraint] = []
    /// Pins Library to the pager’s trailing edge when Music is not a pager page.
    var libraryTrailingToContentConstraint: NSLayoutConstraint?
    /// Right-edge pan that opens the Music drawer.
    var musicEdgePanRecognizer: UIScreenEdgePanGestureRecognizer?
    /// Width of the Library page (full pager width, or remaining space in split).
    var libraryPageWidthConstraint: NSLayoutConstraint?
    /// Width of the Music page (full pager width, or sidebar in split).
    var musicPageWidthConstraint: NSLayoutConstraint?
    /// Pager pinned under the library header (Library page / split).
    var homePagerTopToHeaderConstraint: NSLayoutConstraint?
    /// Pager pinned to the safe area (compact Music page — Music has its own nav bar).
    var homePagerTopToSafeAreaConstraint: NSLayoutConstraint?

    /// Transient transfer/status message overlaid on top of the library while sending.
    let statusLabel: PaddedLabel = {
        let label = PaddedLabel()
        label.textAlignment = .center
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.numberOfLines = 0
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.alpha = 0
        return label
    }()

    let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Cancel", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        button.backgroundColor = .systemRed
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.alpha = 0
        button.isHidden = true
        return button
    }()

    // MARK: - Properties
    
    let connectionManager = iPhoneConnectionManager()
    var selectedPeer: MCPeerID?
    /// When true (the default), Multipeer browsing/auto-connect to the Eclipse TV app
    /// is off until the user explicitly connects. AirPlay (Camera/Web) is unaffected.
    var isConnectionPaused = true
    var autoConnectTimer: Timer?
    /// Retained for cleanup; connection troubleshooting alerts are no longer scheduled.
    var connectionHintTimer: Timer?
    var isShowingPicker = false // Track if we're showing the image picker
    private var statusFadeTimer: Timer?
    let logger = Logger(subsystem: "com.eclipseapp.ios", category: "MainViewController")
    var currentTempFileURL: URL? // Track temp files for cleanup
    /// When set, the active `AspectCropViewController` is cropping a video (not a still).
    var pendingVideoCropURL: URL?
    /// Thumbnail chosen before a Vertical video crop; reused after export.
    var pendingVideoThumbnail: UIImage?
    /// Size of the still shown in the video cropper (for mapping crop → video pixels).
    var pendingVideoCropPreviewSize: CGSize?
    /// When set, the cropper is re-editing an existing library item (not a new add).
    var pendingEditItemId: String?
    /// When set, the thumbnail picker updates an existing video’s poster (not a new add).
    var pendingThumbnailEditItemId: String?
    /// When set, the next successfully added media item is also appended to this album.
    var pendingAlbumId: UUID?
    /// When set with `pendingSlideshowName`, the next image batch becomes a Slideshow.
    var pendingSlideshowShowId: UUID?
    /// Name for the Slideshow created from the next image-only import batch.
    var pendingSlideshowName: String?
    /// When true, the next image pick updates the Background tile instead of the library.
    var pendingLogoPick = false
    /// Photos pick for custom Screensaver (image or video).
    var pendingScreensaverPick = false
    /// Distinguishes PDF vs audio document-picker results.
    var pendingDocumentKind: PendingDocumentKind = .pdf

    enum PendingDocumentKind {
        case pdf
        case audio
    }

    /// Floating mini player card for ambient music.
    let audioMiniPlayer = AudioMiniPlayerView()
    /// Persistent Music control. Regular: toggles the drawer. Compact: picker /
    /// expand card / stop.
    let audioMiniBubble = AudioMiniPlayerBubbleView()
    /// When true, the bar is hidden; the Music circle stays visible.
    /// Ambient control prefers the floating bubble; expand is temporary.
    var audioMiniCollapsed = true
    /// Tracks session edge so the Music picker dismisses only when playback starts.
    var hadActiveAudioSession = false
    /// True while the bubble ↔ card morph is in flight.
    var isAudioMiniChromeAnimating = false
    var audioMiniHeightConstraint: NSLayoutConstraint?
    /// Width of the floating card (`compactWidth`, squeezed on narrow phones).
    var audioMiniCardWidthConstraint: NSLayoutConstraint?
    var audioPlayerObserver: NSObjectProtocol?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConnectionManager()
        setupNotificationObservers()
        // iOS 27+: external display scenes only connect after a scene accessory is
        // registered on a presented main-interface VC. No-op on iOS 18–26.
        ExternalDisplaySceneAccessory.register(on: self)
        registerForTraitChanges(
            [UITraitHorizontalSizeClass.self]
        ) { (self: Self, _: UITraitCollection) in
            self.updateHomeSplitLayoutIfNeeded()
            self.syncAudioMiniLayoutIfNeeded()
            self.refreshLibraryMenu()
        }
        registerForTraitChanges(
            [UITraitVerticalSizeClass.self]
        ) { (self: Self, _: UITraitCollection) in
            // Phone landscape disables Library↔Music paging (grid|preview split).
            self.setHomePagingEnabled(true)
            self.syncAudioMiniLayoutIfNeeded()
        }

        navigationController?.isNavigationBarHidden = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // The home screen uses its own custom header bar, so keep the nav bar hidden.
        navigationController?.setNavigationBarHidden(true, animated: animated)
        
        // Eclipse TV app link is opt-in; don't browse/auto-connect on appear.
        if !isShowingPicker {
            if isConnectionPaused {
                headerBar.setConnectionState(.paused)
            } else {
                startSearching()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHomeSplitLayoutIfNeeded()
        syncHomePagerOffsetIfNeeded()
        // Library decides side-by-side after its own layout; dock the mini bar after.
        syncAudioMiniLayoutIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Only invalidate timers if we're not going to the image picker
        if !isShowingPicker {
            invalidateAllTimers()
        }
        
        // Clean up any remaining temp files if view is disappearing
        if let tempURL = currentTempFileURL {
            cleanupTempFile(at: tempURL)
            currentTempFileURL = nil
        }
        
        // Only stop searching if we're not going to the image picker
        // This way, we maintain our connection while picking images
        if !isShowingPicker {
            stopSearching()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        invalidateAllTimers()
        
        // Clean up any remaining temp files
        if let tempURL = currentTempFileURL {
            cleanupTempFile(at: tempURL)
        }
    }
    
    // MARK: - Helper Methods
    
    func showVideoThumbnailPreview(for videoURL: URL) {
        let previewController = VideoThumbnailPreviewViewController(videoURL: videoURL)
        previewController.delegate = self
        previewController.modalPresentationStyle = .overFullScreen
        presentationAnchor.present(previewController, animated: true)
    }

    func showImagePreview(for image: UIImage) {
        let previewController = ImagePreviewViewController(
            image: image,
            sendsToAppleTV: isConnected()
        )
        previewController.delegate = self
        previewController.modalPresentationStyle = .overFullScreen
        presentationAnchor.present(previewController, animated: true)
    }

    /// In Vertical mode, forces a 9:16 crop when the image isn't already that aspect;
    /// otherwise opens the normal confirm preview.
    func presentImageAddFlow(for image: UIImage) {
        let size = MediaAspect.orientedPixelSize(of: image)
        if MediaAspect.requiresVerticalCrop,
           !MediaAspect.matches(size, target: MediaAspect.vertical) {
            let cropper = AspectCropViewController(image: image, targetAspect: MediaAspect.vertical)
            cropper.delegate = self
            cropper.modalPresentationStyle = .overFullScreen
            presentationAnchor.present(cropper, animated: true)
            return
        }
        showImagePreview(for: image)
    }
    
    func isConnected() -> Bool {
        guard let peer = selectedPeer else {
            return false
        }
        
        // Ask connection manager if we're connected to this peer
        return connectionManager.isConnectedToPeer(peer)
    }
    
    func showTemporaryStatus(_ message: String, duration: TimeInterval = 3.0) {
        // Cancel any existing timer safely
        statusFadeTimer?.invalidate()
        statusFadeTimer = nil
        
        // Show the message
        DispatchQueue.main.async {
            self.statusLabel.text = message
            self.statusLabel.alpha = 1.0
            
            // Create a timer to fade out the message with weak self
            self.statusFadeTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] timer in
                timer.invalidate()
                UIView.animate(withDuration: 0.5) {
                    self?.statusLabel.alpha = 0
                }
                self?.statusFadeTimer = nil
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func invalidateAllTimers() {
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
        statusFadeTimer?.invalidate()
        statusFadeTimer = nil
        connectionHintTimer?.invalidate()
        connectionHintTimer = nil
    }
    
    func cleanupTempFile(at url: URL) {
        DispatchQueue.global(qos: .utility).async { [logger] in
            do {
                try FileManager.default.removeItem(at: url)
                logger.debug("Cleaned up temp file: \(url.lastPathComponent, privacy: .public)")
            } catch {
                logger.error("Failed to cleanup temp file: \(error.localizedDescription)")
            }
        }
    }
    
}
