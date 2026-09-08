//
//  PresentationToast.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension UIViewController {

    /// Brief toast for presentation and transfer feedback. The one toast in the app:
    /// Dynamic Type, VoiceOver announcement, bottom of the safe area by default.
    ///
    /// Calling again while a toast is up in the same place replaces its text without
    /// re-animating, so progress ("Sending video: 42%") reads as one message that
    /// updates rather than a strobe of pills. A different placement swaps the toast.
    ///
    /// - Parameter duration: Seconds before auto-dismiss. `nil` holds the toast until
    ///   the next call or `removePresentationToastIfPresent()` — for progress that
    ///   ends with its own outcome message.
    /// - Parameter centeredIn: When set, centers in that view; otherwise bottom of `view`.
    func showPresentationToast(
        _ message: String,
        duration: TimeInterval? = 2.2,
        centeredIn host: UIView? = nil
    ) {
        let container = host ?? view!
        let toast: PresentationToastView
        if let existing = existingPresentationToast(),
           existing.superview === container,
           existing.isCentered == (host != nil) {
            toast = existing
            toast.setMessage(message)
        } else {
            removePresentationToast()
            toast = PresentationToastView(message: message, isCentered: host != nil)
            installPresentationToast(toast, in: container, centered: host != nil)
        }

        UIAccessibility.post(notification: .announcement, argument: message)

        let token = UUID()
        toast.dismissToken = token
        guard let duration else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak toast] in
            guard let toast, toast.superview != nil, toast.dismissToken == token else {
                return
            }
            UIView.animate(withDuration: 0.2, animations: {
                toast.alpha = 0
                toast.transform = CGAffineTransform(translationX: 0, y: 8)
            }, completion: { _ in
                toast.removeFromSuperview()
            })
        }
    }

    /// Clears any on-screen presentation toast (e.g. after a long download).
    func removePresentationToastIfPresent() {
        removePresentationToast()
    }

    // MARK: - Private

    private func installPresentationToast(
        _ toast: PresentationToastView,
        in container: UIView,
        centered: Bool
    ) {
        toast.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toast)
        container.bringSubviewToFront(toast)

        var constraints: [NSLayoutConstraint] = [
            toast.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toast.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor, constant: 24
            ),
            toast.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor, constant: -24
            )
        ]
        if centered {
            constraints.append(
                toast.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            )
        } else {
            constraints.append(
                toast.bottomAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16
                )
            )
        }
        NSLayoutConstraint.activate(constraints)

        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: 8)
        UIView.animate(withDuration: 0.22) {
            toast.alpha = 1
            toast.transform = .identity
        }
    }

    private func existingPresentationToast() -> PresentationToastView? {
        let id = PresentationToastView.accessibilityID
        var stack: [UIView] = [view]
        while let current = stack.popLast() {
            if current.accessibilityIdentifier == id {
                return current as? PresentationToastView
            }
            stack.append(contentsOf: current.subviews)
        }
        return nil
    }

    private func removePresentationToast() {
        existingPresentationToast()?.removeFromSuperview()
    }
}

// MARK: - View

private final class PresentationToastView: UIView {
    static let accessibilityID = "PresentationToastView"

    /// Whether this toast is centered in its host (vs. pinned to the safe-area bottom).
    let isCentered: Bool
    /// Identifies the latest show call; a stale dismissal compares and bails.
    var dismissToken = UUID()

    private let label = UILabel()

    init(message: String, isCentered: Bool) {
        self.isCentered = isCentered
        super.init(frame: .zero)
        accessibilityIdentifier = Self.accessibilityID
        isAccessibilityElement = true
        backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.96)
        layer.applyContinuousCorner(radius: CornerRadii.standard)
        layer.masksToBounds = true

        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        setMessage(message)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMessage(_ message: String) {
        label.text = message
        accessibilityLabel = message
    }
}
