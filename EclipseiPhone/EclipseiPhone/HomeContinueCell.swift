//
//  HomeContinueCell.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Home's top card: pick up the last Show, or make the first one.
///
/// Replaces the marketing carousel (three static slides that did nothing when
/// tapped). Eclipse is mainly a standalone show player, so the most useful thing
/// at the top of Home is getting back into the Show you were running.
///
/// Uses the carousel's card size, so the Home layout and its tests are unchanged.
final class HomeContinueCell: UICollectionViewCell {

    static let reuseIdentifier = "HomeContinueCell"

    /// What the card offers.
    enum Content: Equatable {
        /// The most recently opened Show.
        case show(id: UUID, name: String, detail: String, cover: UIImage?)
        /// No Shows yet.
        case firstShow
    }

    /// Opens the Show, or creates the first one. Wired by the grid.
    var onPrimaryAction: (() -> Void)?

    private let card = UIView()
    private let coverView = UIImageView()
    private let scrim = CAGradientLayer()
    private let kickerLabel = UILabel()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var cardWidth: NSLayoutConstraint?
    private var cardHeight: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onPrimaryAction = nil
        coverView.image = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = HomeHeroCarouselCell.cardSize(
            availableWidth: contentView.bounds.width,
            containerHeight: enclosingCollectionViewHeight,
            horizontalSizeClass: traitCollection.horizontalSizeClass
        )
        if cardWidth?.constant != size.width || cardHeight?.constant != size.height {
            cardWidth?.constant = size.width
            cardHeight?.constant = size.height
            contentView.layoutIfNeeded()
        }
        scrim.frame = card.bounds
    }

    func configure(_ content: Content) {
        var button = actionButton.configuration ?? .filled()
        switch content {
        case let .show(_, name, detail, cover):
            kickerLabel.text = "CONTINUE"
            titleLabel.text = name
            detailLabel.text = detail
            coverView.image = cover
            coverView.isHidden = cover == nil
            button.title = "Open"
            button.image = UIImage(systemName: "play.fill")
            accessibilityLabel = "Continue \(name)"
            accessibilityValue = detail
            accessibilityHint = "Opens this Show."
        case .firstShow:
            kickerLabel.text = "GET STARTED"
            titleLabel.text = "Create your first Show"
            detailLabel.text = "Put photos, videos, websites and polls in order, then present them."
            coverView.image = nil
            coverView.isHidden = true
            button.title = "New Show"
            button.image = UIImage(systemName: "plus")
            accessibilityLabel = "Create your first Show"
            accessibilityValue = nil
            accessibilityHint = "Creates a new Show."
        }
        actionButton.configuration = button
    }

    // MARK: - Private

    private func setUp() {
        card.backgroundColor = UIColor(white: 0.12, alpha: 1)
        card.layer.applyContinuousCorner(radius: CornerRadii.large)
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(coverView)

        // Keeps white text readable over any cover.
        scrim.colors = [
            UIColor.black.withAlphaComponent(0.05).cgColor,
            UIColor.black.withAlphaComponent(0.75).cgColor
        ]
        scrim.locations = [0.3, 1]
        card.layer.addSublayer(scrim)

        kickerLabel.font = .scaled(12, weight: .semibold, relativeTo: .caption1, maximumPointSize: 18)
        kickerLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        titleLabel.font = .scaled(26, weight: .bold, relativeTo: .title2, maximumPointSize: 34)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        detailLabel.font = .scaled(14, weight: .medium, relativeTo: .subheadline, maximumPointSize: 20)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        detailLabel.numberOfLines = 2
        for label in [kickerLabel, titleLabel, detailLabel] {
            label.adjustsFontForContentSizeCategory = true
        }

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .white
        config.baseForegroundColor = .black
        config.imagePadding = 6
        config.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        actionButton.configuration = config
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.addAction(UIAction { [weak self] _ in
            self?.onPrimaryAction?()
        }, for: .touchUpInside)

        let text = UIStackView(arrangedSubviews: [kickerLabel, titleLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 4
        let bottom = UIStackView(arrangedSubviews: [text, actionButton])
        bottom.axis = .horizontal
        bottom.alignment = .bottom
        bottom.spacing = 12
        bottom.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(bottom)

        let width = card.widthAnchor.constraint(equalToConstant: 320)
        let height = card.heightAnchor.constraint(equalToConstant: 180)
        cardWidth = width
        cardHeight = height
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            width,
            height,
            coverView.topAnchor.constraint(equalTo: card.topAnchor),
            coverView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            coverView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            bottom.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            bottom.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            bottom.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            bottom.topAnchor.constraint(greaterThanOrEqualTo: card.topAnchor, constant: 12)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    private var enclosingCollectionViewHeight: CGFloat {
        var view: UIView? = superview
        while let current = view {
            if let collection = current as? UICollectionView {
                return collection.bounds.height
            }
            view = current.superview
        }
        return 0
    }

    // The whole card is the button for VoiceOver and for taps outside "Open".
    override func accessibilityActivate() -> Bool {
        onPrimaryAction?()
        return true
    }
}
