//
//  BrowserTabStripView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Row of tab chips above the browser card: one per open tab, scrolling sideways,
/// followed by a ⊕ that opens a new tab.
///
/// The active chip is light with a close ×; the others are dark glass. A chip shows
/// a TV glyph when the TV is on that tab and a phone glyph when the tab is phone-only.
final class BrowserTabStripView: UIView {

    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onNewTab: (() -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var chips: [UUID: BrowserTabChip] = [:]
    /// ⊕ after the last chip; it scrolls with them.
    let newTabButton = UIButton(type: .system)
    /// Active chip, kept so the next layout pass can bring it (and ⊕, for the last
    /// tab) into view once chip widths and the strip's own width are final.
    private var activeId: UUID?
    private var activeIsLast = false
    private var needsActiveScroll = false
    private var lastLaidOutSize: CGSize = .zero

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

        var plus = UIButton.Configuration.plain()
        plus.image = UIImage(
            systemName: "plus",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        plus.baseForegroundColor = .white
        plus.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        plus.background.strokeColor = UIColor.white.withAlphaComponent(0.28)
        plus.background.strokeWidth = 0.5
        plus.cornerStyle = .capsule
        newTabButton.configuration = plus
        newTabButton.accessibilityLabel = "New Tab"
        newTabButton.addAction(UIAction { [weak self] _ in self?.onNewTab?() }, for: .touchUpInside)
        newTabButton.widthAnchor.constraint(equalTo: newTabButton.heightAnchor).isActive = true
        stack.addArrangedSubview(newTabButton)

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
            // ⊕ is always the last arranged view, so chips go in before it.
            if stack.arrangedSubviews[index] !== chip {
                stack.insertArrangedSubview(chip, at: index)
            }
        }
        self.activeId = activeId
        activeIsLast = tabs.last?.id == activeId
        needsActiveScroll = true
        setNeedsLayout()
    }

    /// Scrolls only once the chips have their real sizes: `update` often runs
    /// before the strip has its width, and new titles resize chips after it.
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastLaidOutSize {
            lastLaidOutSize = bounds.size
            needsActiveScroll = true
        }
        guard needsActiveScroll, bounds.width > 0 else { return }
        scrollView.layoutIfNeeded()
        stack.layoutIfNeeded()
        guard let activeId, let active = chips[activeId] else { return }
        needsActiveScroll = false
        let target = (activeIsLast ? active.frame.union(newTabButton.frame) : active.frame)
            .insetBy(dx: -12, dy: 0)
        let width = scrollView.bounds.width
        let maxOffset = max(scrollView.contentSize.width - width, 0)
        var x = scrollView.contentOffset.x
        if target.maxX > x + width { x = target.maxX - width }
        if target.minX < x { x = target.minX }
        x = min(max(x, 0), maxOffset)
        // Not animated: a layout pass in flight cancels an animated offset.
        if x != scrollView.contentOffset.x {
            scrollView.contentOffset = CGPoint(x: x, y: 0)
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
