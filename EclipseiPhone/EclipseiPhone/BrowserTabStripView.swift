//
//  BrowserTabStripView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Row of tab chips above the browser card: one per open tab, scrolling sideways.
///
/// The active chip is light with a close ×; the others are dark glass. A chip shows
/// a TV glyph when the TV is on that tab and a phone glyph when the tab is phone-only.
final class BrowserTabStripView: UIView {

    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var chips: [UUID: BrowserTabChip] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Rebuilds the chips to match `tabs` and scrolls the active one into view.
    func update(tabs: [BrowserTab], activeId: UUID, tvTabId: UUID?) {
        let ids = Set(tabs.map(\.id))
        for (id, chip) in chips where !ids.contains(id) {
            chip.removeFromSuperview()
            chips[id] = nil
        }
        for (index, tab) in tabs.enumerated() {
            let chip = chips[tab.id] ?? makeChip(for: tab.id)
            chip.configure(
                title: tab.title,
                isActive: tab.id == activeId,
                showsTV: tab.id == tvTabId,
                isPhoneOnly: tab.isPhoneOnly,
                canClose: tabs.count > 1
            )
            if stack.arrangedSubviews.count > index {
                if stack.arrangedSubviews[index] !== chip {
                    stack.insertArrangedSubview(chip, at: index)
                }
            } else {
                stack.addArrangedSubview(chip)
            }
        }
        layoutIfNeeded()
        if let active = chips[activeId] {
            scrollView.scrollRectToVisible(active.frame.insetBy(dx: -12, dy: 0), animated: true)
        }
    }

    private func makeChip(for id: UUID) -> BrowserTabChip {
        let chip = BrowserTabChip()
        chip.onTap = { [weak self] in self?.onSelect?(id) }
        chip.onClose = { [weak self] in self?.onClose?(id) }
        chips[id] = chip
        return chip
    }
}

/// One tab chip: glyph · title · × (active only).
final class BrowserTabChip: UIControl {

    var onTap: (() -> Void)?
    var onClose: (() -> Void)?

    private let glyph = UIImageView()
    private let label = UILabel()
    private let closeButton = UIButton(type: .system)
    private let content = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        isAccessibilityElement = true
        accessibilityTraits = .button

        glyph.contentMode = .scaleAspectFit
        glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 11, weight: .semibold
        )
        glyph.setContentHuggingPriority(.required, for: .horizontal)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var closeConfig = UIButton.Configuration.plain()
        closeConfig.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        )
        closeConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 6, leading: 4, bottom: 6, trailing: 2
        )
        closeButton.configuration = closeConfig
        closeButton.accessibilityLabel = "Close Tab"
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        closeButton.setContentHuggingPriority(.required, for: .horizontal)

        content.axis = .horizontal
        content.alignment = .center
        content.spacing = 5
        content.isUserInteractionEnabled = true
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(glyph)
        content.addArrangedSubview(label)
        content.addArrangedSubview(closeButton)
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    /// The × takes its own taps; everything else on the chip selects the tab.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, bounds.contains(point) else {
            return nil
        }
        if !closeButton.isHidden,
           closeButton.bounds.contains(convert(point, to: closeButton)) {
            return closeButton
        }
        return self
    }

    func configure(
        title: String,
        isActive: Bool,
        showsTV: Bool,
        isPhoneOnly: Bool,
        canClose: Bool
    ) {
        label.text = title
        let symbol: String? = isPhoneOnly ? "iphone" : (showsTV ? "tv" : nil)
        glyph.image = symbol.map { UIImage(systemName: $0) ?? UIImage() }
        glyph.isHidden = symbol == nil
        closeButton.isHidden = !(isActive && canClose)

        let fore: UIColor = isActive ? .black : .white
        label.textColor = fore
        glyph.tintColor = isActive ? .black : UIColor.white.withAlphaComponent(0.8)
        closeButton.tintColor = fore
        backgroundColor = isActive
            ? UIColor(white: 0.92, alpha: 1)
            : UIColor.black.withAlphaComponent(0.45)
        layer.borderColor = UIColor.white.withAlphaComponent(isActive ? 0 : 0.28).cgColor

        var hint = title
        if isPhoneOnly { hint += ", on the phone only" } else if showsTV { hint += ", on the TV" }
        accessibilityLabel = hint
        accessibilityTraits = isActive ? [.button, .selected] : .button
    }
}
