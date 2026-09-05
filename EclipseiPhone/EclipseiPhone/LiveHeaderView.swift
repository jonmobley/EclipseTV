//
//  LiveHeaderView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// LiveHeaderView.swift
import AVFoundation
import UIKit

/// Large hero banner pinned to the top of the Library screen showing whatever is
/// currently live on the Apple TV / AirPlay. Hidden when no external display or
/// Eclipse TV is connected. When nothing is live it falls back to a neutral
/// placeholder so the layout stays fixed while the grid scrolls beneath it.
final class LiveHeaderView: UIView {

    // MARK: - Subviews

    let imageView = UIImageView()
    let placeholderIcon = UIImageView()
    let gradientLayer = CAGradientLayer()
    let liveBadge = PaddedLabel()
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    /// Large remaining-time clock while Countdown owns the hero.
    let countdownClockLabel = UILabel()

    /// Remote transport controls, shown only when the live item is a video.
    let controls = PlaybackControlsView()

    /// Host for a warm `WKWebView` when a website is live (in-app preview).
    var webPreviewHost: UIView?
    /// Page id currently attached to `webPreviewHost`, if any.
    var webPreviewPageId: UUID?
    /// In-hero muted Screensaver loop (phone preview; external has its own player).
    var screensaverPreview: SeamlessLoopPlayerView?
    /// In-hero library video (phone-only live; cleared when AirPlay owns playback).
    var libraryVideoHost: UIView?
    var libraryVideoPlayer: AVPlayer?
    var libraryVideoLayer: AVPlayerLayer?
    var libraryVideoItemId: String?
    var libraryVideoIsLooping = false
    var libraryVideoEndObserver: NSObjectProtocol?
    var libraryVideoTimeObserver: Any?
    var libraryVideoFullscreenButton: UIButton?
    /// Toggles the live slide ribbon while a Slideshow owns the hero.
    var slideshowRibbonButton: UIButton?
    /// Circular Fit / Fill shortcut while a still or slideshow owns the hero.
    var screenFitButton: UIButton?
    /// Host for the live camera frame-tap mirror (AirPlay keeps the hardware layer).
    var cameraPreviewHost: UIView?
    /// In-hero live camera, fed by `CameraManager`'s frame tap.
    var cameraPreview: CameraMirrorView?

    /// Identity of the last applied live content; used to skip no-op crossfades.
    private var presentedContentKey: String?
    /// In-flight dissolve overlay (removed when the next transition starts).
    private var transitionSnapshot: UIView?
    /// Whether playback transport should show when not in compact presentation.
    var wantsPlaybackControls = false
    /// Compact presentation progress (0 = full hero, 1 = tucked mini preview).
    /// Owned by `applyCollapse(progress:scale:)`. The open Show's hero stays at 0;
    /// foreign-Show live uses 1 on its own mini view.
    var collapseProgress: CGFloat = 0
    /// Uniform transform scale the host controller currently applies to this view.
    var collapseScale: CGFloat = 1
    /// When true, amber stroke (and LIVE LOCKED badge) mark locked live output.
    /// Read by collapse chrome so content updates don't wipe the thicker lock stroke.
    private(set) var isOutputLocked = false

    /// True once the hero reads as a trailing mini preview rather than a full hero.
    var isCompactPresentation: Bool { collapseProgress > 0.5 }

    /// Forwarded from the transport controls (play/pause, skip ±10s, absolute seek).
    var onTogglePlayPause: (() -> Void)?
    var onSkip: ((Double) -> Void)?
    var onSeek: ((Double) -> Void)?
    /// Fullscreen Preview for phone-local library media.
    var onRequestFullscreen: (() -> Void)?
    /// Opens the Live Poll host CONTROLS sheet from the expanded hero.
    var onRequestHostController: (() -> Void)?
    /// Opens the Camera live controller from the expanded hero.
    var onRequestCameraController: (() -> Void)?
    /// Swipe on the hero while a Slideshow is live: `+1` next, `-1` previous.
    var onSlideshowSwipe: ((Int) -> Void)?
    /// Toggles `showRibbonWhenLive` for the active Slideshow from the hero.
    var onToggleSlideshowRibbon: (() -> Void)?
    /// Toggles Fit / Fill for the live still or slideshow from the hero.
    var onToggleScreenFit: (() -> Void)?
    /// When true, the expanded hero accepts left/right swipes (and stays tappable).
    var allowsSlideshowBrowse = false {
        didSet {
            guard allowsSlideshowBrowse != oldValue else { return }
            applyInteractionForPresentation()
        }
    }
    /// When true, tapping the expanded hero requests fullscreen Preview (phone-live stills).
    var allowsFullscreenTap = false {
        didSet {
            guard allowsFullscreenTap != oldValue else { return }
            applyInteractionForPresentation()
        }
    }
    /// When true, tapping the expanded Live Poll hero opens host CONTROLS.
    var allowsHostControllerTap = false {
        didSet {
            guard allowsHostControllerTap != oldValue else { return }
            applyInteractionForPresentation()
        }
    }
    /// When true, tapping the expanded Camera hero opens the camera controller.
    var allowsCameraControllerTap = false {
        didSet {
            guard allowsCameraControllerTap != oldValue else { return }
            applyInteractionForPresentation()
        }
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Before inner Auto Layout: a 0-width TAMIC mask fights 14/40pt insets
        // and dumps unsatisfiable-constraint logs at construction.
        translatesAutoresizingMaskIntoConstraints = false
        setupViews()
        installSlideshowBrowseGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 16
        layer.masksToBounds = true
        // Thin outline so Black / dark live content doesn't blend into the screen.
        applyOutputLockChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (view: Self, _: UITraitCollection) in
            view.applyOutputLockChrome()
        }

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        placeholderIcon.tintColor = .tertiaryLabel
        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.image = UIImage(systemName: "tv")
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderIcon)

        gradientLayer.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.65).cgColor]
        gradientLayer.locations = [0.45, 1.0]
        layer.addSublayer(gradientLayer)

        liveBadge.font = .systemFont(ofSize: 13, weight: .bold)
        liveBadge.textColor = .white
        liveBadge.text = "LIVE"
        liveBadge.layer.cornerRadius = 6
        liveBadge.layer.masksToBounds = true
        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(liveBadge)

        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        countdownClockLabel.font = .monospacedDigitSystemFont(ofSize: 56, weight: .semibold)
        countdownClockLabel.textColor = .white
        countdownClockLabel.textAlignment = .center
        countdownClockLabel.adjustsFontSizeToFitWidth = true
        countdownClockLabel.minimumScaleFactor = 0.4
        countdownClockLabel.numberOfLines = 1
        countdownClockLabel.isHidden = true
        countdownClockLabel.translatesAutoresizingMaskIntoConstraints = true
        addSubview(countdownClockLabel)

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        // No tap-to-open-options on the banner; only the transport controls are interactive.
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.isHidden = true
        controls.onTogglePlayPause = { [weak self] in self?.onTogglePlayPause?() }
        controls.onSkip = { [weak self] delta in self?.onSkip?(delta) }
        controls.onSeek = { [weak self] position in self?.onSeek?(position) }
        addSubview(controls)

        let fullscreenTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleFullscreenContentTap)
        )
        addGestureRecognizer(fullscreenTap)

        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor),
            controls.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),

            placeholderIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -14),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 52),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 52),

            liveBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            liveBadge.topAnchor.constraint(equalTo: topAnchor, constant: 14),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: placeholderIcon.bottomAnchor, constant: 10),
            Self.flexible(
                titleLabel.leadingAnchor.constraint(
                    greaterThanOrEqualTo: leadingAnchor, constant: 14
                )
            ),
            Self.flexible(
                titleLabel.trailingAnchor.constraint(
                    lessThanOrEqualTo: trailingAnchor, constant: -14
                )
            ),
            Self.flexible(
                subtitleLabel.leadingAnchor.constraint(
                    equalTo: leadingAnchor, constant: 14
                )
            ),
            Self.flexible(
                subtitleLabel.trailingAnchor.constraint(
                    equalTo: trailingAnchor, constant: -14
                )
            ),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }

    /// Insets that need width; yield when the hero is still 0pt at launch.
    private static func flexible(_ constraint: NSLayoutConstraint) -> NSLayoutConstraint {
        constraint.priority = .defaultHigh
        return constraint
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        applyBadgeCounterScale()
        layoutLibraryVideoPreviewIfNeeded()
        layoutCameraPreviewIfNeeded()
        layoutWebPreviewIfNeeded()
        layoutCountdownClockIfNeeded()
        // Keep the float-mode shadow path matched to the current bounds.
        if layer.shadowOpacity > 0, bounds.width > 1, bounds.height > 1 {
            layer.shadowPath = UIBezierPath(
                roundedRect: bounds,
                cornerRadius: layer.cornerRadius
            ).cgPath
        }
    }

    // MARK: - Configuration

    /// Shows the live item, or a placeholder when `item` is nil (nothing live).
    ///
    /// - Parameter showsLocalTransport: When true (phone-only or AirPlay library video),
    ///   show play/pause chrome even without an Eclipse TV Multipeer link.
    /// - Parameter allowsStillFullscreenTap: When true (phone-only still), tap opens
    ///   fullscreen Preview.
    /// - Parameter usesRemoteVideoMonitor: When true (AirPlay / EclipseTV owns video),
    ///   show a black program monitor (no poster, no film glyph).
    /// - Parameter showsLiveBadge: When true (HDMI / AirPlay / EclipseTV), show
    ///   the LIVE overlay. Practice Mode keeps the preview without the badge.
    ///   `nil` uses the current HDMI / AirPlay / EclipseTV connection.
    func configure(
        with item: LibraryItemDTO?,
        thumbnail: UIImage?,
        isOnline: Bool,
        showsLocalTransport: Bool = false,
        allowsStillFullscreenTap: Bool = false,
        usesRemoteVideoMonitor: Bool = false,
        showsLiveBadge: Bool? = nil
    ) {
        let showLiveBadge = showsLiveBadge ?? LiveOutputRouting.showsHeroLiveBadge()
        clearWebPreview(parking: true)
        clearScreensaverPreview()
        clearCameraPreview()
        if !showsLocalTransport {
            clearLibraryVideoPreview()
        }
        guard let item = item else {
            clearLibraryVideoPreview()
            allowsFullscreenTap = false
            let message = isOnline
                ? "Select item to go live"
                : "Connect to HDMI or AirPlay"
            applyContent(key: "placeholder:\(message)") {
                self.showPlaceholder(message: message)
            }
            return
        }

        let thumbToken = thumbnail.map { "\(ObjectIdentifier($0))" } ?? "nil"
        let fitToken = item.isVideo
            ? "video"
            : (SlideshowPlaybackController.shared.contentModeForLiveStill(id: item.id)
                == .scaleAspectFill ? "fill" : "fit")
        let key = "media:\(item.id):\(thumbToken):\(isOnline)"
            + ":local\(showsLocalTransport):fs\(allowsStillFullscreenTap):\(fitToken)"
            + ":monitor\(usesRemoteVideoMonitor):badge\(showLiveBadge)"
        applyContent(key: key) {
            self.hideCountdownClock()
            let showControls = item.isVideo && (isOnline || showsLocalTransport)
            if usesRemoteVideoMonitor {
                // Match the black stage behind the card — a grey fill + film glyph
                // reads as a two-tone empty monitor while the TV actually plays.
                self.backgroundColor = .black
                self.imageView.image = nil
                self.imageView.isHidden = true
                self.imageView.alpha = 1
                self.placeholderIcon.isHidden = true
            } else {
                // Video letterboxes on black so the card matches the stage; stills
                // keep the light fill. Never put a film glyph on a video preview.
                self.backgroundColor = item.isVideo ? .black : .secondarySystemBackground
                self.imageView.contentMode = item.isVideo
                    ? .scaleAspectFit
                    : SlideshowPlaybackController.shared.contentModeForLiveStill(id: item.id)
                self.imageView.image = thumbnail
                self.imageView.isHidden = false
                self.imageView.alpha = 1
                self.placeholderIcon.isHidden = thumbnail != nil || item.isVideo
                self.placeholderIcon.alpha = 1
                self.placeholderIcon.image = UIImage(systemName: "photo")
                self.placeholderIcon.tintColor = .tertiaryLabel
            }

            // LIVE badge; video transport uses the bottom gradient. Never show
            // image titles on the preview — art alone is enough.
            self.wantsPlaybackControls = showControls
            self.allowsFullscreenTap = allowsStillFullscreenTap
            self.gradientLayer.isHidden = !showControls
            self.liveBadge.isHidden = !showLiveBadge
            self.titleLabel.isHidden = true
            self.subtitleLabel.isHidden = true
            self.controls.isHidden = !showControls
            self.applyCollapseChrome()
            self.accessibilityLabel = self.isCompactPresentation
                ? "Live, \(item.name), tap to expand"
                : allowsStillFullscreenTap
                    ? "Live, \(item.name), tap for full screen"
                    : "Live, \(item.name)"
            if showsLocalTransport && !usesRemoteVideoMonitor {
                self.setStaticPreviewHidden(true)
            }
        }
    }

    /// Live overlay (website / camera / black) — never shows leftover media art.
    /// - Parameter showsLiveBadge: When true (HDMI / AirPlay / EclipseTV), show
    ///   the LIVE overlay. Practice Mode keeps the preview without the badge.
    ///   `nil` uses the current HDMI / AirPlay / EclipseTV connection.
    /// - Parameter stableContentKey: When set, ticks (countdown remaining) do not
    ///   retrigger a hero crossfade.
    func configureOverlay(
        title: String,
        systemImage: String?,
        fillColor: UIColor,
        thumbnail: UIImage? = nil,
        keepWebPreview: Bool = false,
        keepScreensaverPreview: Bool = false,
        keepCameraPreview: Bool = false,
        showsLiveBadge: Bool? = nil,
        stableContentKey: String? = nil
    ) {
        let showLiveBadge = showsLiveBadge ?? LiveOutputRouting.showsHeroLiveBadge()
        if !keepWebPreview {
            clearWebPreview(parking: true)
        }
        if !keepScreensaverPreview {
            clearScreensaverPreview()
        }
        if !keepCameraPreview {
            clearCameraPreview()
        }
        clearLibraryVideoPreview()
        let thumbToken = thumbnail.map { "\(ObjectIdentifier($0))" } ?? "nil"
        let key = stableContentKey ?? (
            "overlay:\(title):\(systemImage ?? ""):\(thumbToken)"
            + ":web\(keepWebPreview):ss\(keepScreensaverPreview):cam\(keepCameraPreview)"
            + ":badge\(showLiveBadge)"
        )
        applyContent(key: key) {
            self.hideCountdownClock()
            self.backgroundColor = fillColor
            // Background / website / camera art always fills the hero.
            self.imageView.contentMode = .scaleAspectFill
            self.imageView.image = thumbnail
            self.imageView.isHidden = thumbnail == nil
            if let systemImage {
                self.placeholderIcon.image = UIImage(systemName: systemImage)
                self.placeholderIcon.tintColor = UIColor.white.withAlphaComponent(0.55)
                self.placeholderIcon.isHidden = thumbnail != nil
            } else {
                self.placeholderIcon.isHidden = true
            }

            self.wantsPlaybackControls = false
            self.allowsFullscreenTap = false
            self.allowsHostControllerTap = false
            self.allowsCameraControllerTap = false
            self.gradientLayer.isHidden = true
            self.liveBadge.isHidden = !showLiveBadge
            self.subtitleLabel.isHidden = true
            self.controls.isHidden = true

            let hidingStatic = keepWebPreview || keepScreensaverPreview
                || keepCameraPreview
            self.titleLabel.isHidden = thumbnail != nil || hidingStatic
            self.titleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
            self.titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
            self.titleLabel.textAlignment = .center
            self.titleLabel.text = title
            self.applyCollapseChrome()
            self.accessibilityLabel = self.isCompactPresentation
                ? "\(title), tap to expand"
                : title
            if hidingStatic {
                self.setStaticPreviewHidden(true)
            }
        }
    }

    /// Creates the web-preview host once, pinned under LIVE chrome.
    func ensureWebPreviewHost() {
        if webPreviewHost != nil { return }
        let host = UIView()
        host.backgroundColor = .black
        host.clipsToBounds = true
        host.isUserInteractionEnabled = false
        host.translatesAutoresizingMaskIntoConstraints = false
        host.isHidden = true
        insertSubview(host, at: 0)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        webPreviewHost = host
    }

    /// Hides the static thumb/placeholder while a live WKWebView fills the hero.
    func setStaticPreviewHidden(_ hidden: Bool) {
        imageView.alpha = hidden ? 0 : 1
        placeholderIcon.alpha = hidden ? 0 : 1
    }

    /// Keeps LIVE badge / labels above the embedded website preview.
    func bringWebPreviewChromeToFront() {
        if let host = webPreviewHost {
            insertSubview(host, at: 0)
        }
        bringSubviewToFront(liveBadge)
        bringSubviewToFront(titleLabel)
        bringSubviewToFront(subtitleLabel)
        bringSubviewToFront(controls)
    }

    /// Empty Show hero while live output still belongs to another Show.
    func configureSelectToGoLive() {
        clearWebPreview(parking: true)
        clearScreensaverPreview()
        clearCameraPreview()
        clearLibraryVideoPreview()
        applyContent(key: "selectToGoLive") {
            self.allowsFullscreenTap = false
            self.showPlaceholder(message: "Select item to go live")
        }
    }

    /// Neutral empty hero (`tv` icon + centered message). No LIVE badge.
    private func showPlaceholder(message: String) {
        clearWebPreview(parking: true)
        clearScreensaverPreview()
        clearCameraPreview()
        clearLibraryVideoPreview()
        hideCountdownClock()
        allowsFullscreenTap = false
        backgroundColor = .secondarySystemBackground
        imageView.image = nil
        imageView.isHidden = true
        imageView.alpha = 1
        placeholderIcon.isHidden = false
        placeholderIcon.alpha = 1
        placeholderIcon.image = UIImage(systemName: "tv")
        placeholderIcon.tintColor = .tertiaryLabel

        wantsPlaybackControls = false
        gradientLayer.isHidden = true
        liveBadge.isHidden = true
        subtitleLabel.isHidden = true
        controls.isHidden = true

        titleLabel.isHidden = false
        titleLabel.textColor = .secondaryLabel
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.text = message
        applyCollapseChrome()
        accessibilityLabel = isCompactPresentation
            ? "\(message), tap to expand"
            : message
    }

    /// Compact mini: tap to return. Expanded: transport / slideshow / still Preview.
    /// The slide-ribbon and Screen Fit buttons must stay tappable when shown.
    /// Practice / Start on the Live Poll gate must stay tappable too.
    func applyInteractionForPresentation() {
        isUserInteractionEnabled =
            isCompactPresentation
            || wantsPlaybackControls
            || allowsSlideshowBrowse
            || allowsFullscreenTap
            || allowsHostControllerTap
            || allowsCameraControllerTap
            || slideshowRibbonButton != nil
            || screenFitButton != nil
            || isShowingLivePollGate
    }

    /// Expanded phone-live still: open fullscreen Preview.
    /// Live Poll room: open host CONTROLS. Camera: open the camera controller.
    @objc func handleFullscreenContentTap() {
        guard !isCompactPresentation else { return }
        if allowsHostControllerTap {
            onRequestHostController?()
            return
        }
        if allowsCameraControllerTap {
            onRequestCameraController?()
            return
        }
        guard allowsFullscreenTap else { return }
        onRequestFullscreen?()
    }

    /// Applies the latest playback state to the transport controls.
    func updatePlayback(_ state: PlaybackState) {
        controls.update(isPlaying: state.isPlaying, currentTime: state.currentTime, duration: state.duration)
    }

    /// Amber hero stroke + LIVE LOCKED badge while live output is locked.
    func setOutputLocked(_ locked: Bool) {
        guard isOutputLocked != locked else { return }
        isOutputLocked = locked
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseInOut) {
            self.applyOutputLockChrome()
        }
    }

    private func applyOutputLockChrome() {
        if isOutputLocked {
            layer.borderColor = UIColor.systemOrange.cgColor
            liveBadge.backgroundColor = .systemOrange
            liveBadge.text = "LIVE LOCKED"
        } else {
            layer.borderColor = UIColor.separator.cgColor
            liveBadge.backgroundColor = .systemRed
            liveBadge.text = "LIVE"
        }
        // Width is owned by collapse chrome (counter-scales with the hero transform).
        applyCollapseChrome()
    }

    // MARK: - Crossfade

    /// Instant update (Cut / same content) or snapshot dissolve matching AirPlay.
    func applyContent(key: String, update: () -> Void) {
        // A snapshot added as our own subview would inherit the collapse transform on
        // top of the scale it was captured at, so cut instead of dissolving while
        // the hero is anything but fully expanded.
        let shouldCrossfade = ExternalOutputSettings.contentTransition == .crossfade
            && presentedContentKey != nil
            && presentedContentKey != key
            && window != nil
            && bounds.width > 0
            && collapseProgress <= 0.01

        presentedContentKey = key
        guard shouldCrossfade else {
            update()
            return
        }

        transitionSnapshot?.removeFromSuperview()
        let snapshot = snapshotView(afterScreenUpdates: false)
        update()

        guard let snapshot else { return }
        snapshot.frame = bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(snapshot)
        // Keep chrome above the dissolve (LIVE badge / transport).
        bringSubviewToFront(liveBadge)
        bringSubviewToFront(controls)
        transitionSnapshot = snapshot

        // Brief hold so thumbnail/layout can settle under the snapshot.
        UIView.animate(
            withDuration: 0.35,
            delay: 0.08,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            snapshot.alpha = 0
        } completion: { [weak self] _ in
            snapshot.removeFromSuperview()
            if self?.transitionSnapshot === snapshot {
                self?.transitionSnapshot = nil
            }
        }
    }
}
