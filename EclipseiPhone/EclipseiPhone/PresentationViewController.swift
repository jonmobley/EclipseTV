//
//  PresentationViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// PresentationViewController.swift
import UIKit
import AVFoundation
import WebKit
import PDFKit
import os.log

/// Fullscreen, non-interactive view shown on an AirPlay-connected external display.
/// Renders the currently selected item (image, video, camera, web, or PDF) while the
/// phone keeps its normal UI — including playback controls. This screen never
/// hosts `AVPlayerViewController` or transport chrome.
/// Driven entirely by `ExternalDisplayManager`.
final class PresentationViewController: UIViewController {

    // MARK: - Subviews

    /// Fullscreen host for library image/video; content inside is rotated in Vertical.
    let mediaContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Image / player layer target laid out then rotated into `mediaContainer`.
    let mediaContentView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        // Frame-driven via applyRotatedLayout; keep Autolayout off for this view.
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }()

    let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let messageLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        label.font = .systemFont(ofSize: 28, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Centered phone icon + "Eclipse" shown when nothing is presenting.
    let idleBrandView: UIStackView = {
        let icon = UIImageView(image: UIImage(systemName: "iphone"))
        icon.tintColor = UIColor.white.withAlphaComponent(0.45)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 96),
            icon.heightAnchor.constraint(equalToConstant: 96)
        ])

        let title = UILabel()
        title.text = "Eclipse"
        title.textColor = UIColor.white.withAlphaComponent(0.55)
        title.font = .systemFont(ofSize: 32, weight: .semibold)
        title.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [icon, title])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.isHidden = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    /// Host for the live camera preview; rotated for vertically mounted TVs.
    let cameraContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let cameraPreviewView = CameraPreviewView()

    /// PNG frame overlay on AirPlay camera (matches phone framing).
    let cameraFrameOverlayView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }()

    /// Incoming transition camera frame overlay.
    var incomingCameraFrameOverlay: UIImageView?

    /// Host for the scaled/rotated web view on the external display.
    let webContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.isHidden = true
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    var webView: WKWebView?
    /// URL last asked of `webView`. Compared instead of `webView.url`, which a
    /// redirect or in-page navigation can change and thereby force a reload.
    var webRequestedURL: URL?
    /// Matches overscroll gutters to the page colour; does not alter the page.
    var webBackgroundTint: WebBackgroundTint?
    /// Active YouTube / Vimeo shell, if the web view is hosting an embed.
    var webVideoLink: WebVideoLink?
    /// Latest embed playback snapshot for the phone hero scrubber.
    var webVideoPlaybackState = PlaybackState()

    /// Host for the scaled/rotated PDF view on the external display.
    let pdfContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.isHidden = true
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    var pdfView: PDFView?

    /// Host for the countdown clock; rotated for vertically mounted TVs.
    let countdownContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.isHidden = true
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let countdownClockHost = UIView()
    let countdownTimeLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = true
        return label
    }()
    /// Still or muted loop behind the clock, installed only when one is chosen.
    var countdownBackgroundView: CountdownBackgroundView?
    var countdownObserver: NSObjectProtocol?
    var countdownLayoutObserver: NSObjectProtocol?
    var countdownPreviewObserver: NSObjectProtocol?

    /// Incoming dual-layer host — next content builds here while underlay stays live.
    let transitionOverlayContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.isHidden = true
        view.alpha = 0
        view.clipsToBounds = true
        return view
    }()

    /// Source currently installed in the primary containers.
    ///
    /// Cleared by the teardown paths, so a non-nil value means that content is live on
    /// the external display right now. `showIfNeeded(_:)` reads it to skip rebuilds.
    var presentedSource: PresentationSource?

    // MARK: - Incoming transition state

    var pendingTransitionSource: PresentationSource?
    var isTransitionInFlight = false
    /// True while Cut/Crossfade reveal is scheduled or running.
    var isRevealScheduled = false
    /// True while promoting overlay → primary (suppresses nested ready signals).
    var isCommittingTransition = false
    var transitionFallbackWorkItem: DispatchWorkItem?
    var transitionGeneration = 0

    var incomingMediaHost: UIView?
    var incomingImageView: UIImageView?
    var incomingImageRequest: RemoteImageRequest?
    var incomingPlayer: AVPlayer?
    var incomingPlayerLayer: AVPlayerLayer?
    var incomingLoopObserver: NSObjectProtocol?
    var incomingVideoReadyObservation: NSKeyValueObservation?
    /// Overlay video layer has a decoded frame (`isReadyForDisplay`).
    var incomingLayerReadyObservation: NSKeyValueObservation?
    var incomingCameraPreview: CameraPreviewView?
    var incomingWebView: WKWebView?
    var incomingWebNavigation: NSObject?
    var incomingPDFView: PDFView?

    var playerLayer: AVPlayerLayer?
    var player: AVPlayer?
    /// Periodic time observer for the phone video remote (not shown on TV).
    var videoTransportTimeObserver: Any?
    var loopObserver: NSObjectProtocol?
    /// Seamless looping Screensaver (dual-player crossfade).
    var screensaverView: SeamlessLoopPlayerView?
    var incomingScreensaverView: SeamlessLoopPlayerView?
    /// Countdown composed in the transition overlay: background plus frozen digits.
    var incomingCountdownBackground: CountdownBackgroundView?
    var incomingCountdownLabel: UILabel?
    var imageRequest: RemoteImageRequest?
    var imageLoadGeneration = 0
    var settingsObserver: NSObjectProtocol?
    var cameraFrameStoreObserver: NSObjectProtocol?
    var cameraPositionObserver: NSObjectProtocol?

    /// Observes AirPlay video item readiness for primary install.
    var videoReadyObservation: NSKeyValueObservation?

    /// Corner badge while ambient music plays under non-video content.
    var audioNowPlayingBadge: UIVisualEffectView?
    var audioNowPlayingLabel: UILabel?
    var audioPlayerObserver: NSObjectProtocol?
    /// True while the external display is showing library video.
    var isPresentingVideo = false

    let logger = Logger(subsystem: "com.eclipseapp.ios", category: "Presentation")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // External is output-only; transport lives on the phone hero.
        view.isUserInteractionEnabled = false

        view.addSubview(mediaContainer)
        mediaContainer.addSubview(mediaContentView)
        mediaContentView.addSubview(imageView)
        view.addSubview(idleBrandView)
        view.addSubview(messageLabel)
        view.addSubview(activityIndicator)
        view.addSubview(cameraContainer)
        view.addSubview(webContainer)
        view.addSubview(pdfContainer)
        view.addSubview(countdownContainer)
        view.addSubview(transitionOverlayContainer)
        cameraContainer.addSubview(cameraPreviewView)
        cameraContainer.addSubview(cameraFrameOverlayView)
        // Frame-driven via applyRotatedLayout — Auto Layout size constraints
        // collapse the preview to zero and black the TV (same as mediaContentView).
        cameraPreviewView.translatesAutoresizingMaskIntoConstraints = true
        transitionOverlayContainer.translatesAutoresizingMaskIntoConstraints = false

        cameraFrameStoreObserver = NotificationCenter.default.addObserver(
            forName: CameraFrameStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshCameraFrameOverlay()
            self?.refreshIncomingCameraFrameOverlay()
        }

        NSLayoutConstraint.activate([
            mediaContainer.topAnchor.constraint(equalTo: view.topAnchor),
            mediaContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mediaContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mediaContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            imageView.topAnchor.constraint(equalTo: mediaContentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: mediaContentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: mediaContentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: mediaContentView.trailingAnchor),

            idleBrandView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            idleBrandView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: 60
            ),
            messageLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -60
            ),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            cameraContainer.topAnchor.constraint(equalTo: view.topAnchor),
            cameraContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            cameraContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            webContainer.topAnchor.constraint(equalTo: view.topAnchor),
            webContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            pdfContainer.topAnchor.constraint(equalTo: view.topAnchor),
            pdfContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pdfContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            countdownContainer.topAnchor.constraint(equalTo: view.topAnchor),
            countdownContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            countdownContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            countdownContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            transitionOverlayContainer.topAnchor.constraint(equalTo: view.topAnchor),
            transitionOverlayContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            transitionOverlayContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transitionOverlayContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        settingsObserver = NotificationCenter.default.addObserver(
            forName: ExternalOutputSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyMediaLayout()
            self?.applyCameraLayout()
            self?.applyWebLayout()
            self?.applyPDFLayout()
            self?.applyCountdownLayout()
            self?.layoutIncomingOverlayContent()
        }

        cameraPositionObserver = NotificationCenter.default.addObserver(
            forName: CameraManager.cameraPositionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.cameraContainer.isHidden else { return }
            self.cameraPreviewView.syncDisplayModeOrientation()
            self.applyCameraLayout()
        }

        setupAudioNowPlayingOverlay()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !mediaContainer.isHidden {
            applyMediaLayout()
        }
        if !cameraContainer.isHidden {
            applyCameraLayout()
        }
        if !webContainer.isHidden {
            applyWebLayout()
        }
        if !pdfContainer.isHidden {
            applyPDFLayout()
        }
        if !countdownContainer.isHidden {
            applyCountdownLayout()
        }
        if !transitionOverlayContainer.isHidden {
            layoutIncomingOverlayContent()
        }
    }

    deinit {
        if let loopObserver = loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        if let settingsObserver = settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let audioPlayerObserver {
            NotificationCenter.default.removeObserver(audioPlayerObserver)
        }
        if let cameraFrameStoreObserver {
            NotificationCenter.default.removeObserver(cameraFrameStoreObserver)
        }
        if let cameraPositionObserver {
            NotificationCenter.default.removeObserver(cameraPositionObserver)
        }
        if let incomingLoopObserver {
            NotificationCenter.default.removeObserver(incomingLoopObserver)
        }
        if let countdownObserver {
            NotificationCenter.default.removeObserver(countdownObserver)
        }
        if let countdownLayoutObserver {
            NotificationCenter.default.removeObserver(countdownLayoutObserver)
        }
        if let countdownPreviewObserver {
            NotificationCenter.default.removeObserver(countdownPreviewObserver)
        }
    }

    // MARK: - Presentation

    /// Replaces the displayed content via dual-layer hold (live underlay → incoming).
    func show(_ source: PresentationSource) {
        // Connect / foreground re-entry used to cancel the in-flight first paint.
        if pendingTransitionSource == source, isTransitionInFlight { return }
        if shouldSkipScreensaverReshow(source) { return }
        performContentTransition(to: source)
    }

    /// Same Screensaver is already on the primary surface. Rebuilding it blinks black.
    func shouldSkipScreensaverReshow(_ source: PresentationSource) -> Bool {
        guard !isTransitionInFlight else { return false }
        guard presentedSource == source else { return false }
        if case .screensaver = source.content { return true }
        return false
    }

    /// Installs `source`, skipping the rebuild when the same web page is already live.
    ///
    /// Re-assertion runs on every scene reconnect, foreground, and Display Mode rotation,
    /// and `show(_:)` always runs a transition. For a web page that is already on the
    /// primary surface that is pointless churn (the hidden-primary reuse in
    /// `installIncomingWeb` only applies when the page is *not* currently showing).
    /// Other content is only skipped at the cost of correctness — video in particular
    /// relies on the rebuild to resume after a background — so the shortcut is
    /// deliberately limited to web.
    func showIfNeeded(_ source: PresentationSource) {
        if pendingTransitionSource == source { return }
        switch source.content {
        case .web, .webVideo:
            if presentedSource == source, !isTransitionInFlight { return }
            show(source)
        default:
            show(source)
        }
    }

    /// Installs `source` into the primary containers. Caller must cover with the
    /// opaque transition overlay when replacing live camera/video.
    func applyShowDirect(_ source: PresentationSource) {
        teardownPlayer()
        imageRequest?.cancel()
        imageRequest = nil
        setIdleBrandVisible(false)
        // Library video and web-video embeds hide ambient chrome; muted Screensaver does not.
        switch source.content {
        case .video, .webVideo:
            isPresentingVideo = true
        default:
            isPresentingVideo = false
        }

        switch source.content {
        case .image(let url, let fill, let framing):
            hideCountdown()
            hideCamera()
            hideWeb()
            hidePDF()
            showImage(at: url, fill: fill, framing: framing)
        case .video(let url, let isLooping, let isMuted):
            hideCountdown()
            hideCamera()
            hideWeb()
            hidePDF()
            showVideo(
                at: url,
                isLooping: isLooping,
                isMuted: isMuted,
                startAt: source.videoStartAt,
                autoplay: source.videoAutoplay
            )
        case .screensaver(let url, let crossfade):
            hideCountdown()
            hideCamera()
            hideWeb()
            hidePDF()
            showScreensaver(at: url, crossfade: crossfade)
        case .camera:
            hideCountdown()
            hideMediaContainer()
            showCamera()
        case .web(let url):
            hideCountdown()
            hideMediaContainer()
            showWeb(url: url)
        case .webVideo(let link):
            hideCountdown()
            hideMediaContainer()
            showWebVideo(link)
        case .pdf(let url):
            hideCountdown()
            hideMediaContainer()
            showPDF(url: url)
        case .countdown:
            showCountdown()
        case .black:
            hideCountdown()
            showBlack()
        case .unavailable(let thumbnail, _):
            hideCountdown()
            hideCamera()
            hideWeb()
            hidePDF()
            showUnavailable(thumbnail: thumbnail)
        }
        presentedSource = source
    }

    /// Solid black — no idle brand, media, camera, web, or PDF chrome.
    func showBlack() {
        teardownPlayer()
        hideCamera()
        hideMediaContainer()
        teardownWeb()
        teardownPDF()
        hideCountdown()
        imageRequest?.cancel()
        imageRequest = nil
        imageView.image = nil
        imageView.isHidden = true
        activityIndicator.stopAnimating()
        messageLabel.text = nil
        setIdleBrandVisible(false)
    }

    /// Clears content and shows the idle Eclipse brand on the AirPlay display.
    func showIdle() {
        transitionFallbackWorkItem?.cancel()
        clearIncomingOverlay(animated: false)
        pendingTransitionSource = nil
        isTransitionInFlight = false
        isRevealScheduled = false
        isCommittingTransition = false

        teardownPlayer()
        hideCamera()
        hideMediaContainer()
        teardownWeb()
        teardownPDF()
        hideCountdown()
        imageRequest?.cancel()
        imageRequest = nil
        imageView.image = nil
        imageView.isHidden = true
        activityIndicator.stopAnimating()
        messageLabel.text = nil
        setIdleBrandVisible(true)
        presentedSource = nil
    }

    /// Shows or hides the centered phone + "Eclipse" idle mark.
    func setIdleBrandVisible(_ visible: Bool) {
        idleBrandView.isHidden = !visible
    }

}
