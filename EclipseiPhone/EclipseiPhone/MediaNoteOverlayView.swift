//
//  MediaNoteOverlayView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Footer gradient + note card for phone image Preview.
final class MediaNoteOverlayView: UIView {

    /// Invoked when the user taps the note card.
    var onTap: (() -> Void)?

    private let scrim = GradientView()
    private let card = MediaNoteCardView()
    private var itemId: String?

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
        card.configure(note: note)
        isHidden = !MediaNoteStore.shouldShowOverlay(forId: itemId)
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

        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        card.addGestureRecognizer(tap)
        card.isUserInteractionEnabled = true

        NSLayoutConstraint.activate([
            scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrim.topAnchor.constraint(equalTo: topAnchor),

            card.leadingAnchor.constraint(
                equalTo: layoutMarginsGuide.leadingAnchor
            ),
            card.trailingAnchor.constraint(
                equalTo: layoutMarginsGuide.trailingAnchor
            ),
            card.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12
            ),
            card.topAnchor.constraint(
                greaterThanOrEqualTo: topAnchor, constant: 24
            )
        ])
        layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
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

    @objc private func cardTapped() {
        onTap?()
    }
}
