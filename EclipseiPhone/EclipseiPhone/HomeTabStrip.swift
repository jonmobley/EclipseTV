//
//  HomeTabStrip.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// The four pages of the compact home screen, left to right.
///
/// Swiping moves one page at a time in this order, and the text tabs under the
/// header name them. Regular-width iPad keeps `HomeHeaderNavTabs` instead.
enum HomeTab: Int, CaseIterable {
    case home
    case library
    case show
    case music

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .show: return "Show"
        case .music: return "Music"
        }
    }

    /// Stable identifier for tests and accessibility.
    var accessibilityIdentifier: String {
        "home.tab.\(title.lowercased())"
    }
}

/// Rules for the four-page pager that need no views.
///
/// Home and Show are one screen in two modes (`LibraryGridViewController`), so it
/// can only stand in one of their two slots. Library sits between them, which means
/// the two slots are never on screen together: the grid can change mode and move
/// across as soon as the other slot starts to come into view.
enum HomeTabPaging {

    /// Which of the grid's two slots is showing at `position` (offset ÷ page width).
    ///
    /// `nil` exactly on Library or Music, where neither slot is visible.
    static func visibleGridSlot(atPosition position: CGFloat) -> HomeTab? {
        let slack: CGFloat = 0.002
        if position < CGFloat(HomeTab.library.rawValue) - slack {
            return .home
        }
        if position > CGFloat(HomeTab.library.rawValue) + slack,
           position < CGFloat(HomeTab.music.rawValue) - slack {
            return .show
        }
        return nil
    }

    /// The page nearest `position`.
    static func nearestTab(toPosition position: CGFloat) -> HomeTab {
        let last = HomeTab.allCases.count - 1
        let index = max(0, min(last, Int(position.rounded())))
        return HomeTab(rawValue: index) ?? .home
    }

    /// Neighbours slide; a jump across pages fades, so the pages in between
    /// (and the Show the grid would open on the way past) never flash by.
    static func slides(from: HomeTab, to: HomeTab) -> Bool {
        abs(from.rawValue - to.rawValue) == 1
    }

    /// The Show the Show tab opens when none is open.
    ///
    /// The last one that was open, if it still exists in the current Display Mode,
    /// else the most recent Show of that mode. Never one from the other Display
    /// Mode: a swipe must not flip the screen's shape.
    static func showToOpen<Show>(
        lastOpen: Show?,
        recents: [Show],
        isCurrentMode: (Show) -> Bool
    ) -> Show? {
        if let lastOpen, isCurrentMode(lastOpen) { return lastOpen }
        return recents.first(where: isCurrentMode)
    }
}

/// Text tabs with a line under the current one: Home · Library · Show · Music.
final class HomeTabStripView: UIView {

    /// Invoked when a tab is tapped (also the current one).
    var onSelect: ((HomeTab) -> Void)?

    static let height: CGFloat = 38

    private let stack = UIStackView()
    private let indicator = UIView()
    private var buttons: [HomeTab: UIButton] = [:]
    private(set) var selected: HomeTab = .home
    /// Pager position the line follows (0…3); whole numbers sit under a tab.
    private var position: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let width = stack.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize
        ).width
        return CGSize(width: width, height: Self.height)
    }

    /// Marks `tab` current and parks the line under it.
    func setSelected(_ tab: HomeTab, animated: Bool) {
        selected = tab
        applyButtonStyles()
        let move = {
            self.position = CGFloat(tab.rawValue)
            self.layoutIndicator()
        }
        if animated, window != nil, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: move
            )
        } else {
            move()
        }
    }

    /// Moves the line with a swipe; `position` is the pager offset in pages.
    func setPosition(_ position: CGFloat) {
        let last = CGFloat(HomeTab.allCases.count - 1)
        self.position = max(0, min(last, position))
        let nearest = HomeTabPaging.nearestTab(toPosition: self.position)
        if nearest != selected {
            selected = nearest
            applyButtonStyles()
        }
        layoutIndicator()
    }

    /// Dims and disables the tabs (arranging or selecting tiles).
    func setEnabled(_ enabled: Bool) {
        isUserInteractionEnabled = enabled
        alpha = enabled ? 1 : 0.45
    }

    /// Frame of the line for `position`, in this view's coordinates.
    func indicatorFrame(forPosition position: CGFloat) -> CGRect {
        let lower = HomeTab(rawValue: Int(position.rounded(.down))) ?? .home
        let upper = HomeTab(rawValue: lower.rawValue + 1) ?? lower
        let fraction = position - CGFloat(lower.rawValue)
        let from = titleFrame(for: lower)
        let to = titleFrame(for: upper)
        let x = from.minX + (to.minX - from.minX) * fraction
        let width = from.width + (to.width - from.width) * fraction
        return CGRect(x: x, y: bounds.height - 5, width: width, height: 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutIndicator()
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        accessibilityIdentifier = "home.tabStrip"

        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for tab in HomeTab.allCases {
            let button = MinimumHitTargetButton(type: .system)
            button.accessibilityIdentifier = tab.accessibilityIdentifier
            button.addAction(UIAction { [weak self] _ in
                self?.onSelect?(tab)
            }, for: .touchUpInside)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            buttons[tab] = button
            stack.addArrangedSubview(button)
        }

        indicator.backgroundColor = .label
        indicator.layer.cornerRadius = 1
        indicator.isUserInteractionEnabled = false
        addSubview(indicator)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: Self.height)
        ])
        applyButtonStyles()
    }

    private func applyButtonStyles() {
        for tab in HomeTab.allCases {
            guard let button = buttons[tab] else { continue }
            let isSelected = tab == selected
            var config = UIButton.Configuration.plain()
            config.title = tab.title
            config.baseForegroundColor = isSelected ? .label : .secondaryLabel
            config.contentInsets = .zero
            // One weight for every tab: a heavier current tab is wider, and the row
            // would shuffle sideways as a swipe passes the halfway point.
            let weight = UIFont.Weight.semibold
            config.titleTextAttributesTransformer =
                UIConfigurationTextAttributesTransformer { incoming in
                    var outgoing = incoming
                    outgoing.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                        for: .systemFont(ofSize: 16, weight: weight),
                        maximumPointSize: 20
                    )
                    return outgoing
                }
            button.configuration = config
            button.accessibilityLabel = tab.title
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }

    private func titleFrame(for tab: HomeTab) -> CGRect {
        guard let button = buttons[tab] else { return .zero }
        // The words, not the button: short words sit in a wider tap target.
        if let label = button.titleLabel, label.bounds.width > 0 {
            return label.convert(label.bounds, to: self)
        }
        return stack.convert(button.frame, to: self)
    }

    private func layoutIndicator() {
        stack.layoutIfNeeded()
        indicator.frame = indicatorFrame(forPosition: position)
    }
}
