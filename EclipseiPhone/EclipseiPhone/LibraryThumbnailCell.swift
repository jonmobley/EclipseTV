//
//  LibraryThumbnailCell.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Grid cell for home-library media or special tiles (Background, Camera, Web, Album).
final class LibraryThumbnailCell: UICollectionViewCell {

    static let reuseIdentifier = "LibraryThumbnailCell"

    // MARK: - Subviews

    /// Rounded media / tool surface (titles overlay the bottom with a fade).
    let cardView = UIView()
    let imageView = UIImageView()
    let placeholderIcon = UIImageView()
    let captionLabel = UILabel()
    /// Bottom fade under on-card titles (tools, Shows, websites).
    let captionScrimView = GradientView()
    /// Bottom-leading photo / video / slideshow / website / PDF glyph.
    let typeIconOverlay = ThumbnailTypeIconView()
    /// Last content type applied; Rewind may hide the overlay without clearing this.
    var contentTypeIcon: ThumbnailTypeIcon?
    let durationLabel = PaddedLabel()
    private let unavailableBadge = PaddedLabel()
    /// Multi-select tick for the Add-to-Show picker and Show-grid select mode.
    let selectionBadge = UIImageView()
    /// Hides the last-frame freeze once the tile preview is painting.
    var cameraFreezeRevealGate: TilePreviewPaintGate?
    /// Clear overlay that hosts a pull-down menu (empty-Show Add tile).
    private let menuButton: UIButton = {
        let button = UIButton(type: .custom)
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    /// Visible ⋯ control for Show media / Background (same idea as Recent Show tiles).
    let moreButton = UIButton(type: .system)
    /// Clears a parked mid-play leave without going live.
    let rewindButton = UIButton(type: .system)
    /// Nudged up when a caption sits under the glyph; 0 for + -only add tiles.
    private var placeholderCenterY: NSLayoutConstraint!
    var captionLeadingToCard: NSLayoutConstraint!
    var captionLeadingToIcon: NSLayoutConstraint!
    var captionLeadingToRewind: NSLayoutConstraint!
    var captionTrailingToCard: NSLayoutConstraint!
    var captionTrailingToDuration: NSLayoutConstraint!
    var captionBottomToCard: NSLayoutConstraint!
    var captionCenterYToIcon: NSLayoutConstraint!
    var captionCenterYToRewind: NSLayoutConstraint!
    /// Last media id painted; keeps art when a reload hits a transient cache miss.
    private var configuredMediaId: String?

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
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false

        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 14
        cardView.layer.cornerCurve = .continuous
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(imageView)

        placeholderIcon.tintColor = .tertiaryLabel
        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(placeholderIcon)

        captionScrimView.colors = [
            UIColor.clear,
            UIColor.black.withAlphaComponent(0.72)
        ]
        captionScrimView.locations = [0, 1]
        captionScrimView.isHidden = true
        captionScrimView.isUserInteractionEnabled = false
        captionScrimView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(captionScrimView)

        captionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        captionLabel.textColor = .white
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 2
        captionLabel.lineBreakMode = .byTruncatingTail
        captionLabel.isHidden = true
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(captionLabel)

        configurePill(durationLabel, background: UIColor.black.withAlphaComponent(0.6), textColor: .white)
        durationLabel.isHidden = true
        cardView.addSubview(durationLabel)

        configurePill(unavailableBadge, background: UIColor.black.withAlphaComponent(0.7), textColor: .white)
        unavailableBadge.text = "Unavailable"
        unavailableBadge.isHidden = true
        cardView.addSubview(unavailableBadge)

        selectionBadge.image = UIImage(
            systemName: "checkmark.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        )
        selectionBadge.tintColor = .systemBlue
        // White inner disc so the tick reads over any thumbnail.
        selectionBadge.backgroundColor = .white
        selectionBadge.layer.cornerRadius = 11
        selectionBadge.clipsToBounds = true
        selectionBadge.isHidden = true
        selectionBadge.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(selectionBadge)

        cardView.addSubview(menuButton)
        installMoreButton()
        installRewindButton()
        installTypeIcon()

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            imageView.topAnchor.constraint(equalTo: cardView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            placeholderIcon.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 36),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 36),

            captionScrimView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            captionScrimView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            captionScrimView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            captionScrimView.heightAnchor.constraint(
                equalTo: cardView.heightAnchor, multiplier: 0.42
            ),

            durationLabel.trailingAnchor.constraint(
                equalTo: cardView.trailingAnchor, constant: -8
            ),
            durationLabel.bottomAnchor.constraint(
                equalTo: cardView.bottomAnchor, constant: -8
            ),

            unavailableBadge.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            unavailableBadge.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -8),

            selectionBadge.trailingAnchor.constraint(
                equalTo: cardView.trailingAnchor, constant: -8
            ),
            selectionBadge.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            selectionBadge.widthAnchor.constraint(equalToConstant: 22),
            selectionBadge.heightAnchor.constraint(equalToConstant: 22),

            menuButton.topAnchor.constraint(equalTo: cardView.topAnchor),
            menuButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            menuButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            menuButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor)
        ])
        placeholderCenterY = placeholderIcon.centerYAnchor.constraint(
            equalTo: cardView.centerYAnchor, constant: -10
        )
        placeholderCenterY.isActive = true
        captionLabel.setContentCompressionResistancePriority(
            .defaultLow, for: .horizontal
        )
        installCaptionLayoutConstraints()
    }

    private func configurePill(_ label: PaddedLabel, background: UIColor, textColor: UIColor) {
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = textColor
        label.backgroundColor = background
        label.layer.cornerRadius = 6
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Configuration

    /// - Parameter isLocked: Live lock uses amber chrome.
    /// - Parameter showsTypeIcon: False for the live-slideshow ribbon (all stills).
    func configure(
        with item: LibraryItemDTO,
        thumbnail: UIImage?,
        isLive: Bool,
        isLocked: Bool = false,
        showsTypeIcon: Bool = true
    ) {
        // Under memory pressure `thumbnail(for:)` can briefly return nil after a
        // reload — keep the previous bitmap for the same item instead of flashing
        // the mountain / film placeholder.
        let retained = (configuredMediaId == item.id && thumbnail == nil)
            ? imageView.image
            : nil
        let image = thumbnail ?? retained

        resetChrome()
        configuredMediaId = item.id
        cardView.backgroundColor = .secondarySystemBackground

        let isUnavailable = (item.isAvailable == false)

        imageView.image = image
        imageView.alpha = isUnavailable ? 0.35 : 1.0
        placeholderIcon.isHidden = image != nil
        placeholderIcon.image = UIImage(systemName: item.isVideo ? "film" : "photo")
        placeholderIcon.tintColor = .tertiaryLabel

        if showsTypeIcon, !isUnavailable {
            setTypeIcon(.media(isVideo: item.isVideo))
        }

        if !isUnavailable, item.isVideo, item.duration > 0 {
            durationLabel.text = Self.formatDuration(item.duration)
            durationLabel.isHidden = false
            raiseDurationOverlay()
        }

        unavailableBadge.isHidden = !isUnavailable
        setLive(isLive && !isUnavailable, isLocked: isLocked)
        var a11y = item.name
        if item.isVideo {
            a11y += ", video"
            if item.duration > 0 {
                a11y += ", \(Self.formatDuration(item.duration))"
            }
        } else {
            a11y += ", photo"
        }
        if isUnavailable { a11y += ", unavailable" }
        if isLive && !isUnavailable { a11y += ", live" }
        if isLive && !isUnavailable && isLocked { a11y += ", locked" }
        accessibilityLabel = a11y
        isAccessibilityElement = true
    }

    /// Soft “add” tile (New Show / Add media) — quiet fill, blue glyph.
    ///
    /// Pass an empty `title` for + -only tiles; VoiceOver still gets
    /// `accessibilityLabel` (defaults to `"Add"` when the caption is empty).
    /// - Parameter menu: When set, tap shows this pull-down (same pattern as header +).
    func configureActionTile(
        title: String,
        systemImage: String = "plus",
        menu: UIMenu? = nil,
        accessibilityLabel: String? = nil
    ) {
        resetChrome()
        cardView.backgroundColor = UIColor.tertiarySystemFill
        cardView.layer.borderWidth = 0
        let symbol = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        placeholderIcon.image = UIImage(systemName: systemImage, withConfiguration: symbol)
        placeholderIcon.tintColor = .systemBlue
        placeholderIcon.isHidden = false
        // + alone is dead-center; titled tiles (New Show) keep the caption offset.
        placeholderCenterY.constant = title.isEmpty ? 0 : -10
        let voice = accessibilityLabel ?? (title.isEmpty ? "Add" : title)
        captionLabel.text = title
        captionLabel.textColor = .systemBlue
        captionLabel.isHidden = title.isEmpty
        // Keep the title readable on the light fill without a dark scrim.
        captionScrimView.isHidden = true
        updateCaptionLayout()
        self.accessibilityLabel = voice
        isAccessibilityElement = true
        setPrimaryMenu(menu, accessibilityLabel: voice)
    }

    /// Hosts a system pull-down on the tile; clears when `menu` is nil.
    func setPrimaryMenu(_ menu: UIMenu?, accessibilityLabel: String? = nil) {
        menuButton.menu = menu
        menuButton.isHidden = menu == nil
        guard menu != nil else { return }
        isAccessibilityElement = false
        menuButton.isAccessibilityElement = true
        menuButton.accessibilityLabel = accessibilityLabel ?? self.accessibilityLabel
    }

    /// Configures a non-media home tile (Background, Camera, Show).
    /// - Parameter outlined: When true, draws a light stroke so a dark fill doesn't
    ///   disappear into the grid background.
    /// - Parameter thumbnailContentMode: `.scaleAspectFit` suits favicons; fill for snapshots.
    /// - Parameter titleNumberOfLines: Caption wrap; PDFs use 1 (tail ellipsis).
    /// - Parameter typeIcon: Bottom-leading content glyph. Tool tiles keep it
    ///   even without a poster so the title can sit beside the disc.
    func configureSpecial(
        title: String,
        systemImage: String?,
        thumbnail: UIImage?,
        fillColor: UIColor,
        isLive: Bool,
        isLocked: Bool = false,
        outlined: Bool = false,
        thumbnailContentMode: UIView.ContentMode = .scaleAspectFill,
        titleNumberOfLines: Int = 2,
        typeIcon: ThumbnailTypeIcon? = nil
    ) {
        resetChrome()
        cardView.backgroundColor = fillColor
        imageView.contentMode = thumbnailContentMode
        imageView.image = thumbnail
        imageView.alpha = thumbnail == nil ? 0 : 1
        if let systemImage {
            placeholderIcon.image = UIImage(systemName: systemImage)
            placeholderIcon.tintColor = UIColor.white.withAlphaComponent(0.85)
            placeholderIcon.isHidden = thumbnail != nil
                || typeIcon?.showsWithoutThumbnail == true
        } else {
            placeholderIcon.isHidden = true
        }
        captionLabel.text = title
        captionLabel.numberOfLines = titleNumberOfLines
        captionLabel.lineBreakMode = .byTruncatingTail
        captionLabel.isHidden = false
        setTypeIcon(typeIcon)
        updateCaptionScrim()
        setLive(isLive, isLocked: isLocked)
        if outlined && !isLive {
            cardView.layer.borderWidth = 1
            cardView.layer.borderColor = UIColor.separator.cgColor
        }
        accessibilityLabel = isLive
            ? (isLocked ? "\(title), live, locked" : "\(title), live")
            : title
        if let typeIcon {
            let spoken = typeIcon.spokenName
            if title.compare(spoken, options: .caseInsensitive) != .orderedSame {
                accessibilityLabel = "\(accessibilityLabel ?? title), \(spoken)"
            }
        }
        isAccessibilityElement = true
    }

    func resetChrome() {
        contentView.alpha = 1
        imageView.image = nil
        imageView.alpha = 1.0
        imageView.contentMode = .scaleAspectFill
        placeholderIcon.isHidden = false
        placeholderCenterY.constant = -10
        captionLabel.isHidden = true
        captionLabel.text = nil
        captionLabel.textColor = .white
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 2
        captionLabel.lineBreakMode = .byTruncatingTail
        captionScrimView.isHidden = true
        hideMediaBadges()
        selectionBadge.isHidden = true
        cardView.layer.borderWidth = 0
        menuButton.menu = nil
        menuButton.isHidden = true
        menuButton.isAccessibilityElement = false
        clearMoreMenu()
        clearRewind()
        recycleCameraPreview()
        stopArrangeWiggle()
        configuredMediaId = nil
    }

    /// Visible duration pill text, or nil when the overlay is hidden.
    var durationOverlayText: String? {
        durationLabel.isHidden ? nil : durationLabel.text
    }

    /// Clears duration / unavailable / type-icon chrome used only by media cells.
    func hideMediaBadges() {
        durationLabel.isHidden = true
        unavailableBadge.isHidden = true
        setTypeIcon(nil)
    }

    /// Keeps the duration pill above thumbnail art and caption fade.
    func raiseDurationOverlay() {
        guard !durationLabel.isHidden else { return }
        cardView.bringSubviewToFront(durationLabel)
    }

    /// Multi-select state for the Add-to-Show picker (call after `configure…`).
    ///
    /// Shares the card border with `setLive`; picker cells are never live.
    func setPickerSelected(_ isSelected: Bool) {
        selectionBadge.image = UIImage(
            systemName: "checkmark.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        )
        selectionBadge.tintColor = .systemBlue
        selectionBadge.backgroundColor = .white
        selectionBadge.isHidden = !isSelected
        cardView.layer.borderWidth = isSelected ? 3 : 0
        cardView.layer.borderColor = isSelected
            ? UIColor.systemBlue.cgColor
            : UIColor.clear.cgColor
    }

    /// - Parameter isLocked: When live is locked, the stroke uses amber.
    func setLive(_ isLive: Bool, isLocked: Bool = false) {
        cardView.layer.borderWidth = isLive ? 3 : 0
        let accent: UIColor = isLocked ? .systemOrange : .systemRed
        cardView.layer.borderColor = isLive ? accent.cgColor : UIColor.clear.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetChrome()
        cardView.backgroundColor = .secondarySystemBackground
    }

    // MARK: - Helpers

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A label with internal padding, used for the duration and unavailable pills.
final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}

/// Vertical `CAGradientLayer` host for caption readability scrims.
final class GradientView: UIView {
    var colors: [UIColor] = [] {
        didSet { updateColors() }
    }
    var locations: [NSNumber] = [0, 1] {
        didSet { gradient.locations = locations }
    }

    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Clear→black must composite over the thumbnail; opaque skips that blend.
        isOpaque = false
        backgroundColor = .clear
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradient)
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    private func updateColors() {
        gradient.colors = colors.map(\.cgColor)
        gradient.locations = locations
    }
}
