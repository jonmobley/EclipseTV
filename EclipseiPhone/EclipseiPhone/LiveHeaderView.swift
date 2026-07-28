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

    private let imageView = UIImageView()
    private let placeholderIcon = UIImageView()
    private let gradientLayer = CAGradientLayer()
    private let liveBadge = PaddedLabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    /// Remote transport controls, shown only when the live item is a video.
    private let controls = PlaybackControlsView()

    /// Identity of the last applied live content; used to skip no-op crossfades.
    private var presentedContentKey: String?
    /// In-flight dissolve overlay (removed when the next transition starts).
    private var transitionSnapshot: UIView?

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
    }

    // MARK: - Configuration

    /// Shows the live item, or a placeholder when `item` is nil (nothing live).
    func configure(with item: LibraryItemDTO?, thumbnail: UIImage?, isOnline: Bool) {
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
            self.imageView.image = thumbnail
            self.imageView.isHidden = false
            self.placeholderIcon.isHidden = thumbnail != nil
            self.placeholderIcon.image = UIImage(systemName: item.isVideo ? "film" : "photo")
            self.placeholderIcon.tintColor = .tertiaryLabel

            // LIVE badge + name on the bottom gradient (hidden when video controls show).
            let showControls = item.isVideo && isOnline
            self.gradientLayer.isHidden = false
            self.liveBadge.isHidden = false
            self.titleLabel.isHidden = true
            self.subtitleLabel.text = item.name
            self.subtitleLabel.isHidden = showControls
            self.isUserInteractionEnabled = true
            self.accessibilityLabel = "Live, \(item.name)"
            self.controls.isHidden = !showControls
        }
    }

    /// Live overlay (website / camera / black) — never shows leftover media art.
    func configureOverlay(
        title: String,
        systemImage: String?,
        fillColor: UIColor,
        thumbnail: UIImage? = nil
    ) {
        let thumbToken = thumbnail.map { "\(ObjectIdentifier($0))" } ?? "nil"
        let key = "overlay:\(title):\(systemImage ?? ""):\(thumbToken)"
        applyContent(key: key) {
            self.backgroundColor = fillColor
            self.imageView.image = thumbnail
            self.imageView.isHidden = thumbnail == nil
            if let systemImage {
                self.placeholderIcon.image = UIImage(systemName: systemImage)
                self.placeholderIcon.tintColor = UIColor.white.withAlphaComponent(0.55)
                self.placeholderIcon.isHidden = thumbnail != nil
            } else {
                self.placeholderIcon.isHidden = true
            }

            self.gradientLayer.isHidden = true
            self.liveBadge.isHidden = false
            self.subtitleLabel.isHidden = true
            self.controls.isHidden = true

            self.titleLabel.isHidden = thumbnail != nil
            self.titleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
            self.titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
            self.titleLabel.textAlignment = .center
            self.titleLabel.text = title
            self.isUserInteractionEnabled = false
        }
    }

    private func showPlaceholder() {
        backgroundColor = .secondarySystemBackground
        imageView.image = nil
        imageView.isHidden = true
        placeholderIcon.isHidden = false
        placeholderIcon.image = UIImage(systemName: "tv")
        placeholderIcon.tintColor = .tertiaryLabel

        gradientLayer.isHidden = true
        liveBadge.isHidden = true
        subtitleLabel.isHidden = true
        controls.isHidden = true

        titleLabel.isHidden = false
        titleLabel.textColor = .secondaryLabel
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.text = "Eclipse"
        isUserInteractionEnabled = false
    }

    /// Applies the latest playback state to the transport controls.
    func updatePlayback(_ state: PlaybackState) {
        controls.update(isPlaying: state.isPlaying, currentTime: state.currentTime, duration: state.duration)
    }

    // MARK: - Crossfade

    /// Instant update (Cut / same content) or snapshot dissolve matching AirPlay.
    private func applyContent(key: String, update: () -> Void) {
        let shouldCrossfade = ExternalOutputSettings.contentTransition == .crossfade
            && presentedContentKey != nil
            && presentedContentKey != key
            && window != nil
            && bounds.width > 0

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
