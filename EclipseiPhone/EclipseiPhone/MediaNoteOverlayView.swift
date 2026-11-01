//
//  MediaNoteOverlayView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Footer gradient + note card for phone image Preview.
final class MediaNoteOverlayView: UIView {

    /// Widest the card gets in regular width, so lines stay easy to read.
    static let readableCardWidth: CGFloat = 640
    private static let cardBottomGap: CGFloat = 12
    private static let cardTopGap: CGFloat = 24

    /// Asks the host to open the editor: the pencil, or a tap on the empty card.
    var onEdit: (() -> Void)?

    /// Where a popover editor should point.
    var editAnchor: UIView { card.editAnchor }

    private let scrim = GradientView()
    private let card = MediaNoteCardView()
    private var itemId: String?
    private var shownNote: String?
    private lazy var cardHeight = card.heightAnchor.constraint(equalToConstant: 0)
    private lazy var cardMaxWidth = card.widthAnchor.constraint(
        lessThanOrEqualToConstant: Self.readableCardWidth
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Reloads the card for `id` and shows/hides per visibility prefs.
    func configure(itemId: String) {
        self.itemId = itemId
        reload()
    }

    /// Refreshes from `MediaNoteStore` for the current item.
    func reload() {
        guard let itemId else {
            isHidden = true
            return
        }
        let note = MediaNoteStore.note(forId: itemId)
        if note != shownNote {
            collapse()
        }
        shownNote = note
        card.configure(note: note)
        isHidden = !MediaNoteStore.shouldShowOverlay(forId: itemId)
    }

    /// Returns the card to its collapsed lines without animating.
    func collapse() {
        card.setExpanded(false)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCardHeight()
    }

    // MARK: - Private

    private func setup() {
        isHidden = true
        backgroundColor = .clear
        isUserInteractionEnabled = true

        scrim.colors = [
            UIColor.black.withAlphaComponent(0),
            UIColor.black.withAlphaComponent(0.72)
        ]
        scrim.locations = [0, 1]
        scrim.isUserInteractionEnabled = false
        scrim.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrim)

        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        card.addTarget(self, action: #selector(cardTapped), for: .touchUpInside)
        card.onEdit = { [weak self] in
            self?.onEdit?()
        }
        card.onMetricsChanged = { [weak self] in
            self?.applyReadableWidth()
            self?.setNeedsLayout()
        }

        // Full width until `cardMaxWidth` is on, then centered at that width.
        let fullLeading = card.leadingAnchor.constraint(
            equalTo: layoutMarginsGuide.leadingAnchor
        )
        let fullTrailing = card.trailingAnchor.constraint(
            equalTo: layoutMarginsGuide.trailingAnchor
        )
        fullLeading.priority = .defaultHigh
        fullTrailing.priority = .defaultHigh
        cardHeight.priority = .required - 1

        NSLayoutConstraint.activate([
            scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrim.topAnchor.constraint(equalTo: topAnchor),

            fullLeading,
            fullTrailing,
            card.leadingAnchor.constraint(
                greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor
            ),
            card.trailingAnchor.constraint(
                lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor
            ),
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Self.cardBottomGap
            ),
            card.topAnchor.constraint(
                greaterThanOrEqualTo: topAnchor, constant: Self.cardTopGap
            ),
            cardHeight
        ])
        layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        applyReadableWidth()
    }

    /// Limits the card's width on a big iPad, where a full-width note reads badly.
    private func applyReadableWidth() {
        cardMaxWidth.isActive = traitCollection.prefersRegularNoteLayout
    }

    /// Pins the card to its note, inside the overlay's band. A short landscape
    /// band can be smaller than even the collapsed card.
    private func updateCardHeight() {
        let room = max(
            0,
            bounds.height - safeAreaInsets.bottom - Self.cardBottomGap - Self.cardTopGap
        )
        cardHeight.constant = min(card.height(forWidth: card.bounds.width, maxHeight: room), room)
    }

    /// Only the card captures taps; zoom/pan pass through the gradient.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled else { return nil }
        let cardPoint = convert(point, to: card)
        guard !card.isHidden, card.point(inside: cardPoint, with: event) else {
            return nil
        }
        return card.hitTest(cardPoint, with: event) ?? card
    }

    /// A filled card reads in place; only the empty card opens the editor.
    @objc private func cardTapped() {
        guard card.hasNote else {
            onEdit?()
            return
        }
        guard card.isToggleable else { return }
        card.setExpanded(!card.isExpanded)
        UIView.animate(
            withDuration: ExpandableNoteCardView.toggleDuration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            self.updateCardHeight()
            self.layoutIfNeeded()
        } completion: { _ in
            self.card.flashScrollIndicators()
        }
    }
}
