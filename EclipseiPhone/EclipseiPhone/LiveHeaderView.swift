//
//  LiveHeaderView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// LiveHeaderView.swift
import UIKit

/// Large hero banner pinned to the top of the Library screen showing whatever is
/// currently live on the Apple TV. When nothing is live it falls back to a neutral
/// placeholder so the layout stays fixed while the grid scrolls beneath it.
final class LiveHeaderView: UIView {

    // MARK: - Subviews

    let imageView = UIImageView()
    let placeholderIcon = UIImageView()
    let gradientLayer = CAGradientLayer()
    let liveBadge = PaddedLabel()
    let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    /// Remote transport controls, shown only when the live item is a video.
    let controls = PlaybackControlsView()

    /// Host for a warm `WKWebView` when a website is live (in-app preview).
    var webPreviewHost: UIView?
    /// Page id currently attached to `webPreviewHost`, if any.
    var webPreviewPageId: UUID?

    /// Identity of the last applied live content; used to skip no-op crossfades.
    private var presentedContentKey: String?
    /// In-flight dissolve overlay (removed when the next transition starts).
    private var transitionSnapshot: UIView?
    /// Whether playback transport should show when not in compact presentation.
    var wantsPlaybackControls = false
    /// Scroll-linked collapse progress (0 = full hero, 1 = tucked mini preview).
    /// Owned by `applyCollapse(progress:scale:)`.
    var collapseProgress: CGFloat = 0
    /// Uniform transform scale the host controller currently applies to this view.
    var collapseScale: CGFloat = 1

    /// True once the hero reads as a trailing mini preview rather than a full hero.
    var isCompactPresentation: Bool { collapseProgress > 0.5 }

    /// Forwarded from the transport controls (play/pause, skip ±10s, absolute seek).
    var onTogglePlayPause: (() -> Void)?
    var onSkip: ((Double) -> Void)?
    var onSeek: ((Double) -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
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
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (view: Self, _: UITraitCollection) in
            view.layer.borderColor = UIColor.separator.cgColor
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
        liveBadge.backgroundColor = .systemRed
        liveBadge.text = "LIVE"
        liveBadge.layer.cornerRadius = 6
        liveBadge.layer.masksToBounds = true
        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(liveBadge)

        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

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
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),

            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        applyBadgeCounterScale()
    }

    // MARK: - Configuration

    /// Shows the live item, or a placeholder when `item` is nil (nothing live).
    func configure(with item: LibraryItemDTO?, thumbnail: UIImage?, isOnline: Bool) {
        clearWebPreview(parking: true)
        guard let item = item else {
            applyContent(key: "placeholder") {
                self.showPlaceholder()
            }
            return
        }

        let thumbToken = thumbnail.map { "\(ObjectIdentifier($0))" } ?? "nil"
        let key = "media:\(item.id):\(thumbToken):\(isOnline)"
        applyContent(key: key) {
            self.backgroundColor = .secondarySystemBackground
            // The hero card is the output panel's aspect, so frame the art the way the
            // external screen / Apple TV does: videos letterbox, stills follow Fit / Fill.
            self.imageView.contentMode = item.isVideo
                ? .scaleAspectFit
                : MediaFitSettings.mode(forId: item.id).contentMode
            self.imageView.image = thumbnail
            self.imageView.isHidden = false
            self.imageView.alpha = 1
            self.placeholderIcon.isHidden = thumbnail != nil
            self.placeholderIcon.alpha = 1
            self.placeholderIcon.image = UIImage(systemName: item.isVideo ? "film" : "photo")
            self.placeholderIcon.tintColor = .tertiaryLabel

            // LIVE badge; video transport uses the bottom gradient. Never show
            // image titles on the preview — art alone is enough.
            let showControls = item.isVideo && isOnline
            self.wantsPlaybackControls = showControls
            self.gradientLayer.isHidden = !showControls
            self.liveBadge.isHidden = false
            self.titleLabel.isHidden = true
            self.subtitleLabel.isHidden = true
            self.controls.isHidden = !showControls
            self.applyCollapseChrome()
            self.accessibilityLabel = self.isCompactPresentation
                ? "Live, \(item.name), tap to expand"
                : "Live, \(item.name)"
        }
    }

    /// Live overlay (website / camera / black) — never shows leftover media art.
    func configureOverlay(
        title: String,
        systemImage: String?,
        fillColor: UIColor,
        thumbnail: UIImage? = nil,
        keepWebPreview: Bool = false
    ) {
        if !keepWebPreview {
            clearWebPreview(parking: true)
        }
        let thumbToken = thumbnail.map { "\(ObjectIdentifier($0))" } ?? "nil"
        let key = "overlay:\(title):\(systemImage ?? ""):\(thumbToken):web\(keepWebPreview)"
        applyContent(key: key) {
            self.backgroundColor = fillColor
            // Logo / website / camera art always fills the hero.
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
            self.gradientLayer.isHidden = true
            self.liveBadge.isHidden = false
            self.subtitleLabel.isHidden = true
            self.controls.isHidden = true

            self.titleLabel.isHidden = thumbnail != nil || keepWebPreview
            self.titleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
            self.titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
            self.titleLabel.textAlignment = .center
            self.titleLabel.text = title
            self.applyCollapseChrome()
            self.accessibilityLabel = self.isCompactPresentation
                ? "\(title), tap to expand"
                : title
            if keepWebPreview {
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

    private func showPlaceholder() {
        clearWebPreview(parking: true)
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
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.text = "Eclipse"
        applyCollapseChrome()
        accessibilityLabel = isCompactPresentation
            ? "Eclipse preview, tap to expand"
            : "Eclipse"
    }

    /// Tap-to-expand while tucked; transport taps while the full hero shows.
    func applyInteractionForPresentation() {
        isUserInteractionEnabled = isCompactPresentation || wantsPlaybackControls
    }

    /// Applies the latest playback state to the transport controls.
    func updatePlayback(_ state: PlaybackState) {
        controls.update(isPlaying: state.isPlaying, currentTime: state.currentTime, duration: state.duration)
    }

    // MARK: - Crossfade

    /// Instant update (Cut / same content) or snapshot dissolve matching AirPlay.
    private func applyContent(key: String, update: () -> Void) {
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
