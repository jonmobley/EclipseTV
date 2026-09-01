//
//  ShowFormatFilter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// All / Horizontal / Vertical format filter for Home Recent and the Shows list.
enum ShowFormatFilter: Int, CaseIterable, Equatable {
    case all
    case landscape
    case vertical

    var title: String {
        switch self {
        case .all: return "All"
        case .landscape: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }

    /// `nil` means both Display Modes.
    var orientation: ExternalOutputOrientation? {
        switch self {
        case .all: return nil
        case .landscape: return .landscape
        case .vertical: return .portrait
        }
    }

    init(orientation: ExternalOutputOrientation?) {
        switch orientation {
        case .landscape: self = .landscape
        case .portrait: self = .vertical
        case nil: self = .all
        }
    }

    /// Shows matching this filter. All returns `albums` unchanged.
    static func albums(
        _ albums: [LocalAlbum],
        matching filter: ShowFormatFilter
    ) -> [LocalAlbum] {
        guard let orientation = filter.orientation else { return albums }
        return albums.filter { $0.orientation == orientation }
    }
}

// MARK: - Chip bar

/// All / Horizontal / Vertical chips. All is selected by default (blue).
final class ShowFormatFilterBar: UIView {

    /// Active format filter. Starts on All.
    var selected: ShowFormatFilter = .all {
        didSet {
            guard oldValue != selected else { return }
            reloadChips()
        }
    }

    /// Called after the user taps a chip.
    var onSelect: ((ShowFormatFilter) -> Void)?

    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        reloadChips()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func reloadChips() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, filter) in ShowFormatFilter.allCases.enumerated() {
            let item = HomeSectionHeaderView.Action(
                title: filter.title,
                isSelected: selected == filter,
                handler: {}
            )
            let button = HomeSectionHeaderView.makeChipButton(item: item, tag: index)
            button.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    @objc private func chipTapped(_ sender: UIButton) {
        let filters = ShowFormatFilter.allCases
        guard filters.indices.contains(sender.tag) else { return }
        let filter = filters[sender.tag]
        selected = filter
        onSelect?(filter)
    }
}
