//
//  HomeSectionHeaderView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Section title above a home grid band, with optional trailing link and chips.
final class HomeSectionHeaderView: UICollectionReusableView {

    static let reuseIdentifier = "HomeSectionHeaderView"

    /// One under-title quick action chip.
    struct Action {
        let title: String
        let systemImage: String?
        let isSelected: Bool
        let handler: () -> Void

        init(
            title: String,
            systemImage: String? = nil,
            isSelected: Bool = false,
            handler: @escaping () -> Void
        ) {
            self.title = title
            self.systemImage = systemImage
            self.isSelected = isSelected
            self.handler = handler
        }
    }

    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let titleRow = UIStackView()
    private let titleLabel: UILabel = {
        let label = UILabel()
        let base = UIFont.systemFont(ofSize: 22, weight: .bold)
        label.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: base)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.accessibilityTraits = .header
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let trailingButton = UIButton(type: .system)
    private let actionsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var actionHandlers: [() -> Void] = []
    private var trailingHandler: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 8
        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(trailingButton)

        trailingButton.isHidden = true
        trailingButton.setContentHuggingPriority(.required, for: .horizontal)
        trailingButton.addTarget(self, action: #selector(trailingTapped), for: .touchUpInside)

        addSubview(stack)
        stack.addArrangedSubview(titleRow)
        stack.addArrangedSubview(actionsStack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        clearActions()
        titleLabel.text = nil
        titleLabel.isHidden = true
        trailingButton.isHidden = true
        trailingHandler = nil
    }

    /// Sets the section title, optional trailing text link, and under-title chips.
    func configure(
        title: String,
        trailingTitle: String? = nil,
        trailingHandler: (() -> Void)? = nil,
        actions: [Action] = []
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = trimmed
        titleLabel.isHidden = trimmed.isEmpty

        if let trailingTitle, let trailingHandler {
            var config = UIButton.Configuration.plain()
            config.title = trailingTitle
            config.baseForegroundColor = .systemBlue
            config.contentInsets = .zero
            config.titleTextAttributesTransformer =
                UIConfigurationTextAttributesTransformer { incoming in
                    var outgoing = incoming
                    outgoing.font = .systemFont(ofSize: 16, weight: .semibold)
                    return outgoing
                }
            trailingButton.configuration = config
            trailingButton.accessibilityLabel = trailingTitle
            trailingButton.isHidden = false
            self.trailingHandler = trailingHandler
        } else {
            trailingButton.isHidden = true
            self.trailingHandler = nil
        }

        clearActions()
        for (index, item) in actions.enumerated() {
            let button = Self.makeChipButton(item: item, tag: index)
            button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
            actionHandlers.append(item.handler)
            actionsStack.addArrangedSubview(button)
        }
        if !actions.isEmpty {
            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            actionsStack.addArrangedSubview(spacer)
        }
        actionsStack.isHidden = actions.isEmpty
    }

    /// Convenience for a single under-title chip action.
    func configure(
        title: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        if let actionTitle, let action {
            configure(
                title: title,
                actions: [Action(title: actionTitle, handler: action)]
            )
        } else {
            configure(title: title, actions: [])
        }
    }

    private static func makeChipButton(item: Action, tag: Int) -> UIButton {
        var config = item.isSelected
            ? UIButton.Configuration.filled()
            : UIButton.Configuration.gray()
        config.cornerStyle = .capsule
        config.title = item.title
        if let systemImage = item.systemImage {
            config.image = UIImage(
                systemName: systemImage,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            )
            config.imagePadding = 5
            config.imagePlacement = .leading
        }
        config.baseForegroundColor = .label
        if item.isSelected {
            config.baseBackgroundColor = .secondarySystemFill
        }
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 7, leading: 12, bottom: 7, trailing: 12
        )
        config.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 13, weight: .semibold)
                return outgoing
            }
        let button = UIButton(configuration: config)
        button.tag = tag
        button.accessibilityLabel = item.title
            .replacingOccurrences(of: " >", with: "")
            .replacingOccurrences(of: " ›", with: "")
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private func clearActions() {
        actionHandlers.removeAll()
        for view in actionsStack.arrangedSubviews {
            actionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    @objc private func actionTapped(_ sender: UIButton) {
        guard actionHandlers.indices.contains(sender.tag) else { return }
        actionHandlers[sender.tag]()
    }

    @objc private func trailingTapped() {
        trailingHandler?()
    }
}
