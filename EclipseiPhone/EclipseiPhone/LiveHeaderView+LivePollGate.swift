//
//  LiveHeaderView+LivePollGate.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension LiveHeaderView {

    private static let gateHostTag = 9_104_221
    private static let gateIconTag = 9_104_222

    /// True while Practice / Start chrome is on the hero.
    var isShowingLivePollGate: Bool {
        viewWithTag(Self.gateHostTag) != nil
    }

    /// Chart icon on the Practice / Start gate, if present.
    var livePollGateIconView: UIView? {
        viewWithTag(Self.gateIconTag)
    }

    /// Shows Practice / Start for an idle Live Poll card (clears web preview).
    func showLivePollGate(
        title: String,
        onPractice: @escaping () -> Void,
        onStart: @escaping () -> Void
    ) {
        hideLivePollGate()
        clearWebPreview(parking: true)
        configureOverlay(
            title: title,
            systemImage: "chart.bar.fill",
            fillColor: UIColor(white: 0.12, alpha: 1),
            keepWebPreview: false,
            showsLiveBadge: false
        )
        placeholderIcon.isHidden = true
        titleLabel.isHidden = true
        updatePlayback(PlaybackState())
        installLivePollGate(
            title: title, onPractice: onPractice, onStart: onStart
        )
        applyInteractionForPresentation()
    }

    /// Removes the Practice / Start chrome when present.
    func hideLivePollGate() {
        viewWithTag(Self.gateHostTag)?.removeFromSuperview()
        applyInteractionForPresentation()
    }

    // MARK: - Private

    private func installLivePollGate(
        title: String,
        onPractice: @escaping () -> Void,
        onStart: @escaping () -> Void
    ) {
        let host = UIView()
        host.tag = Self.gateHostTag
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)

        let stack = Self.gateStack(
            title: title, onPractice: onPractice, onStart: onStart
        )
        host.addSubview(stack)
        pinGateStack(stack, in: host)
    }

    private func pinGateStack(_ stack: UIStackView, in host: UIView) {
        let centerY = stack.centerYAnchor.constraint(equalTo: host.centerYAnchor)
        centerY.priority = .defaultHigh
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -20),
            centerY,
            stack.topAnchor.constraint(
                greaterThanOrEqualTo: host.topAnchor, constant: 16
            ),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: host.bottomAnchor, constant: -16
            )
        ])
    }

    private static func gateStack(
        title: String,
        onPractice: @escaping () -> Void,
        onStart: @escaping () -> Void
    ) -> UIStackView {
        let caption = UIStackView(arrangedSubviews: [
            gateIconView(), gateTitleLabel(title)
        ])
        caption.axis = .vertical
        caption.alignment = .center
        caption.spacing = 8

        let practice = gateButton(title: "Practice", primary: false)
        practice.addAction(UIAction { _ in onPractice() }, for: .touchUpInside)
        let start = gateButton(title: "Start", primary: true)
        start.addAction(UIAction { _ in onStart() }, for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [practice, start])
        buttons.axis = .horizontal
        buttons.spacing = 12
        buttons.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [caption, buttons])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            practice.heightAnchor.constraint(equalToConstant: 44)
        ])
        return stack
    }

    private static func gateIconView() -> UIImageView {
        let icon = UIImageView()
        icon.tag = gateIconTag
        icon.contentMode = .scaleAspectFit
        icon.tintColor = UIColor.white.withAlphaComponent(0.7)
        icon.image = UIImage(systemName: "chart.bar.fill")
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44)
        ])
        return icon
    }

    private static func gateTitleLabel(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private static func gateButton(title: String, primary: Bool) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.cornerStyle = .medium
        if primary {
            config.baseBackgroundColor = .systemBlue
            config.baseForegroundColor = .white
        } else {
            config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.18)
            config.baseForegroundColor = .white
        }
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}
