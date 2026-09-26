//
//  LibraryThumbnailCell+SyncPresence.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Sync presence chrome

extension LibraryThumbnailCell {

    /// Installs the bottom-centre presence pill and the bottom-leading upload badge.
    ///
    /// Top-trailing belongs to ⋯ and the selection tick, top-leading to the type
    /// glyph, bottom-trailing to the duration. Bottom-leading is only ever Rewind,
    /// which wins while it is showing (see `refreshUploadBadgeVisibility`).
    func installSyncPresenceChrome() {
        syncPill.isHidden = true
        syncPill.isUserInteractionEnabled = false
        cardView.addSubview(syncPill)

        uploadBadge.image = UIImage(
            systemName: "icloud.and.arrow.up",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        )
        uploadBadge.tintColor = .white
        uploadBadge.contentMode = .center
        uploadBadge.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        uploadBadge.layer.cornerRadius = 11
        uploadBadge.clipsToBounds = true
        uploadBadge.isHidden = true
        uploadBadge.isUserInteractionEnabled = false
        uploadBadge.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(uploadBadge)

        NSLayoutConstraint.activate([
            syncPill.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            syncPill.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -8),
            syncPill.leadingAnchor.constraint(
                greaterThanOrEqualTo: cardView.leadingAnchor, constant: 6
            ),

            uploadBadge.leadingAnchor.constraint(
                equalTo: cardView.leadingAnchor, constant: 8
            ),
            uploadBadge.bottomAnchor.constraint(
                equalTo: cardView.bottomAnchor, constant: -8
            ),
            uploadBadge.widthAnchor.constraint(equalToConstant: 22),
            uploadBadge.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    /// Paints the pill / badge for `presence` and dims art that cannot play.
    func applySyncPresence(_ presence: MediaSyncPresence) {
        imageView.alpha = presence.thumbnailAlpha
        syncPill.apply(presence)
        wantsUploadBadge = presence == .pendingUpload
        refreshUploadBadgeVisibility()
    }

    /// Hides both pieces of presence chrome (media-cell reset).
    func clearSyncPresence() {
        syncPill.isHidden = true
        syncPill.stopSpinning()
        wantsUploadBadge = false
        uploadBadge.isHidden = true
    }

    /// Rewind and the upload badge share a corner; Rewind wins.
    func refreshUploadBadgeVisibility() {
        uploadBadge.isHidden = !wantsUploadBadge || !rewindButton.isHidden
    }

    /// Visible pill text, or nil when the tile carries no pill.
    var syncPillText: String? {
        syncPill.isHidden ? nil : syncPill.title
    }
}

// MARK: - SyncStatusPillView

/// Compact tile pill: optional glyph or spinner, then a short label.
///
/// Replaces the single-purpose "Unavailable" label so a tile can also say
/// "In iCloud" (with a cloud glyph) or "Downloading…" (with a spinner).
final class SyncStatusPillView: UIView {

    private let iconView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()
    private let stack = UIStackView()

    /// Current label text.
    var title: String? { label.text }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.black.withAlphaComponent(0.7)
        layer.cornerRadius = 6
        layer.masksToBounds = true

        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 11, weight: .bold
        )
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        spinner.color = .white
        spinner.hidesWhenStopped = true
        // `.medium` draws at 20pt; shrink it so the pill stays label-height.
        spinner.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)

        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(label)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    /// Shows the pill for `presence`, or hides it when there is nothing to say.
    func apply(_ presence: MediaSyncPresence) {
        guard let title = presence.pillTitle else {
            isHidden = true
            stopSpinning()
            return
        }
        label.text = title
        if let symbol = presence.pillSymbolName {
            iconView.image = UIImage(systemName: symbol)
            iconView.isHidden = false
        } else {
            iconView.image = nil
            iconView.isHidden = true
        }
        if presence == .downloading {
            spinner.startAnimating()
        } else {
            stopSpinning()
        }
        isHidden = false
    }

    /// Stops the download spinner (no-op when it is not running).
    func stopSpinning() {
        spinner.stopAnimating()
    }
}
