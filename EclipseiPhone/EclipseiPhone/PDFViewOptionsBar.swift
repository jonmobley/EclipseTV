//
//  PDFViewOptionsBar.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Icon row for a PDF: Fit · Fill · Two Pages, then the Page by Page toggle.
///
/// Sits top right in the Show hero and in the full-screen reader. The chosen
/// preset is lit; a pinch clears it (the zoom is then the user's own).
final class PDFViewOptionsBar: UIView {

    var onPreset: ((PDFViewPreset) -> Void)?
    var onToggleSnap: (() -> Void)?

    private var presetButtons: [PDFViewPreset: UIButton] = [:]
    private let snapButton = UIButton(type: .system)
    private let stack = UIStackView()
    private let buttonSize: CGFloat

    /// - Parameter buttonSize: Square size of each button (the hero uses a smaller one).
    init(buttonSize: CGFloat = 36) {
        self.buttonSize = buttonSize
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius = buttonSize / 2
        layer.cornerCurve = .continuous
        clipsToBounds = true

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            heightAnchor.constraint(equalToConstant: buttonSize)
        ])

        for preset in PDFViewPreset.allCases {
            let button = makeButton(systemImage: preset.systemImage, label: preset.title)
            button.addAction(UIAction { [weak self] _ in
                Haptics.impactLight()
                self?.onPreset?(preset)
            }, for: .touchUpInside)
            presetButtons[preset] = button
            stack.addArrangedSubview(button)
        }

        let divider = UIView()
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: buttonSize * 0.5)
        ])
        stack.addArrangedSubview(divider)

        configure(snapButton, systemImage: "book.pages", label: "Page by Page")
        snapButton.accessibilityHint = "When on, a swipe stops at the next page. When off, pages scroll freely."
        snapButton.addAction(UIAction { [weak self] _ in
            Haptics.impactLight()
            self?.onToggleSnap?()
        }, for: .touchUpInside)
        stack.addArrangedSubview(snapButton)

        update(preset: .fit, snapsToPages: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Lights the chosen preset (none after a pinch) and the toggle when on.
    func update(preset: PDFViewPreset?, snapsToPages: Bool) {
        for (key, button) in presetButtons {
            setLit(key == preset, on: button)
        }
        setLit(snapsToPages, on: snapButton)
        snapButton.accessibilityValue = snapsToPages ? "On" : "Off"
    }

    // MARK: - Private

    private func makeButton(systemImage: String, label: String) -> UIButton {
        let button = UIButton(type: .system)
        configure(button, systemImage: systemImage, label: label)
        return button
    }

    private func configure(_ button: UIButton, systemImage: String, label: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: buttonSize * 0.4, weight: .semibold)
        )
        config.contentInsets = .zero
        config.cornerStyle = .capsule
        button.configuration = config
        button.accessibilityLabel = label
        button.largeContentTitle = label
        button.showsLargeContentViewer = true
        button.addInteraction(UILargeContentViewerInteraction())
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: buttonSize + 4),
            button.heightAnchor.constraint(equalToConstant: buttonSize)
        ])
    }

    private func setLit(_ lit: Bool, on button: UIButton) {
        guard var config = button.configuration else { return }
        config.baseForegroundColor = lit ? .black : .white
        config.background.backgroundColor = lit ? .white : .clear
        config.background.backgroundInsets = NSDirectionalEdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3)
        button.configuration = config
        button.isSelected = false
        if lit {
            button.accessibilityTraits.insert(.selected)
        } else {
            button.accessibilityTraits.remove(.selected)
        }
    }
}
