//
//  PresentationToast.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension UIViewController {

    /// Brief toast for presentation feedback.
    /// - Parameter centeredIn: When set, centers in that view; otherwise bottom of `view`.
    func showPresentationToast(
        _ message: String,
        duration: TimeInterval = 2.2,
        centeredIn host: UIView? = nil
    ) {
        removePresentationToast()

        let container = host ?? view!
        let toast = PresentationToastView(message: message)
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
        if host != nil {
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

        UIAccessibility.post(notification: .announcement, argument: message)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak toast] in
            guard let toast, toast.superview != nil else { return }
            UIView.animate(withDuration: 0.2, animations: {
                toast.alpha = 0
                toast.transform = CGAffineTransform(translationX: 0, y: 8)
            }, completion: { _ in
                toast.removeFromSuperview()
            })
        }
    }

    private func removePresentationToast() {
        let id = PresentationToastView.accessibilityID
        var stack: [UIView] = [view]
        while let current = stack.popLast() {
            if current.accessibilityIdentifier == id {
                current.removeFromSuperview()
                return
            }
            stack.append(contentsOf: current.subviews)
        }
    }

    /// Clears any on-screen presentation toast (e.g. after a long download).
    func removePresentationToastIfPresent() {
        removePresentationToast()
    }

}

// MARK: - View

private final class PresentationToastView: UIView {
    static let accessibilityID = "PresentationToastView"

    init(message: String) {
        super.init(frame: .zero)
        accessibilityIdentifier = Self.accessibilityID
        accessibilityLabel = message
        isAccessibilityElement = true
        backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.96)
        layer.applyContinuousCorner(radius: CornerRadii.standard)
        layer.masksToBounds = true

        let label = UILabel()
        label.text = message
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

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
}
