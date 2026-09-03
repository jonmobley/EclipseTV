//
//  HomeHeaderNavTabs.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Top-level header destinations on regular-width iPad.
enum HomeHeaderDestination: Int, CaseIterable {
    case home
    case show
    case library
    case music

    /// Tabs shown in the iPad header cluster (Music uses the blue circle instead).
    static let tabBarCases: [HomeHeaderDestination] = [.home, .show, .library]

    /// Visible tab title. Show may be replaced with the open album name.
    var title: String {
        switch self {
        case .home: return "Home"
        case .show: return "Show"
        case .library: return "Library"
        case .music: return "Music"
        }
    }

    /// Stable identifier for tests and accessibility.
    var accessibilityIdentifier: String {
        "home.nav.\(title.lowercased())"
    }
}

/// Whether the header uses visible tabs instead of the compact dropdown.
enum HomeHeaderNavLayout {

    /// Full iPad canvas only (regular width and height). Compact Split View
    /// and iPhone — including Plus landscape — keep the dropdown.
    static func showsDestinationTabs(
        horizontalSizeClass: UIUserInterfaceSizeClass,
        verticalSizeClass: UIUserInterfaceSizeClass
    ) -> Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
}

/// Selected Home vs Show, plus whether Music is pinned beside the grid.
struct HomeHeaderNavSelection: Equatable {
    var isShowMode: Bool
    var isMusicPinned: Bool
    var showTitle: String

    /// Home when no Show is open.
    static let home = HomeHeaderNavSelection(
        isShowMode: false,
        isMusicPinned: false,
        showTitle: HomeHeaderDestination.show.title
    )
}

/// Bordered cluster of Home, Show, and Library (Music is the blue circle).
final class HomeHeaderNavTabs: UIView {

    /// Invoked when a destination tab is tapped.
    var onSelect: ((HomeHeaderDestination) -> Void)?

    private let stack = UIStackView()
    private var buttons: [HomeHeaderDestination: UIButton] = [:]
    private var selection = HomeHeaderNavSelection.home

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        apply(selection)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Updates selected tabs and the Show title.
    func apply(_ selection: HomeHeaderNavSelection) {
        self.selection = selection
        for destination in HomeHeaderDestination.tabBarCases {
            guard let button = buttons[destination] else { continue }
            style(button, destination: destination, selection: selection)
        }
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        clipsToBounds = true

        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for destination in HomeHeaderDestination.tabBarCases {
            let button = makeTabButton(destination)
            buttons[destination] = button
            stack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 36)
        ])

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (view: Self, _: UITraitCollection) in
            view.layer.borderColor = UIColor.separator.cgColor
        }
    }

    private func makeTabButton(_ destination: HomeHeaderDestination) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = destination.accessibilityIdentifier
        button.addAction(UIAction { [weak self] _ in
            self?.onSelect?(destination)
        }, for: .touchUpInside)
        if destination == .show {
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return button
    }

    private func style(
        _ button: UIButton,
        destination: HomeHeaderDestination,
        selection: HomeHeaderNavSelection
    ) {
        let selected = isSelected(destination, selection: selection)
        let title = destination == .show ? selection.showTitle : destination.title
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = selected ? .label : .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 6, leading: 10, bottom: 6, trailing: 10
        )
        config.titleLineBreakMode = .byTruncatingTail
        let weight: UIFont.Weight = selected ? .semibold : .medium
        config.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 15, weight: weight)
                return outgoing
            }
        if selected {
            config.background.backgroundColor = .secondarySystemFill
            config.cornerStyle = .capsule
        }
        button.configuration = config
        button.accessibilityLabel = destination.title
        button.accessibilityValue = selected ? "Selected" : nil
        button.accessibilityHint = hint(for: destination, selection: selection)
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }

    private func isSelected(
        _ destination: HomeHeaderDestination,
        selection: HomeHeaderNavSelection
    ) -> Bool {
        switch destination {
        case .home: return !selection.isShowMode
        case .show: return selection.isShowMode
        case .library: return false
        case .music: return selection.isMusicPinned
        }
    }

    private func hint(
        for destination: HomeHeaderDestination,
        selection: HomeHeaderNavSelection
    ) -> String {
        switch destination {
        case .home:
            return "Returns to Home"
        case .show:
            return selection.isShowMode
                ? "Opens the Shows list"
                : "Opens a Show"
        case .library:
            return "Opens the media Library"
        case .music:
            return "Shows Music"
        }
    }
}
