//
//  PresentationToast.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension UIViewController {

    /// Brief bottom banner for presentation feedback (e.g. no AirPlay display).
    func showPresentationToast(_ message: String, duration: TimeInterval = 2.2) {
        let existing = view.subviews.first {
            $0.accessibilityIdentifier == PresentationToastView.accessibilityID
        }
        existing?.removeFromSuperview()

        let toast = PresentationToastView(message: message)
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: 24
            ),
            toast.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -24
            ),
            toast.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16
            )
        ])

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

    /// Tip when an AirPlay-only action runs with no external display.
    /// Soft-repeats every few attempts so users aren't stranded after the first tip.
    func warnIfNoExternalDisplay() {
        guard !ExternalDisplayManager.shared.isConnected else { return }
        let countKey = "EclipseTV.tip.airPlayConnectCount"
        let count = UserDefaults.standard.integer(forKey: countKey) + 1
        UserDefaults.standard.set(count, forKey: countKey)
        guard count == 1 || count % 4 == 0 else { return }
        showPresentationToast("Connect AirPlay to present on the TV")
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
        layer.cornerRadius = 14
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
