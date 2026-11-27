//
//  HomeTabPages.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Navigation stack for a home pager page (Library, Music).
///
/// At its root the Home header carries the page's buttons, so the bar is hidden
/// there; it returns for anything pushed (a playlist) and whenever the root says it
/// needs one (searching, reordering tracks).
final class HomeTabPageNavigationController: UINavigationController,
    UINavigationControllerDelegate {

    /// True while the page sits under the Home header and text tabs.
    var hidesBarAtRoot = false {
        didSet {
            guard hidesBarAtRoot != oldValue else { return }
            syncBar(animated: false)
        }
    }

    /// Asked for the root page: true keeps its bar (search field, Done).
    var rootNeedsBar: (() -> Bool)?
    /// Called when the stack goes between its root and a pushed page.
    var onDepthChanged: ((_ isAtRoot: Bool) -> Void)?

    var isAtRoot: Bool { viewControllers.count <= 1 }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
    }

    /// Shows or hides the bar for the page now on top.
    func syncBar(animated: Bool) {
        setNavigationBarHidden(wantsBarHidden(atRoot: isAtRoot), animated: animated)
    }

    private func wantsBarHidden(atRoot: Bool) -> Bool {
        hidesBarAtRoot && atRoot && !(rootNeedsBar?() ?? false)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        let atRoot = viewController === viewControllers.first
        setNavigationBarHidden(wantsBarHidden(atRoot: atRoot), animated: animated)
        onDepthChanged?(atRoot)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        // A cancelled swipe-back ends on the page it started from.
        onDepthChanged?(isAtRoot)
    }
}

/// What the Show page says when there is no Show to open.
final class HomeShowPlaceholderView: UIView {

    /// Invoked by "New Show".
    var onNewShow: (() -> Void)?
    /// Invoked by "Open Show".
    var onOpenShow: (() -> Void)?

    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let newShowButton = UIButton(type: .system)
    private let openShowButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `hasShows`: some Show exists (in either Display Mode), so offer the list.
    func configure(hasShows: Bool) {
        detailLabel.text = hasShows
            ? "Open one of your Shows, or start a new one."
            : "A Show holds everything you put on the screen. Start your first one."
        openShowButton.isHidden = !hasShows
    }

    private func setup() {
        backgroundColor = .systemBackground
        accessibilityIdentifier = "home.showPlaceholder"

        let icon = UIImageView(image: UIImage(
            systemName: "rectangle.stack",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        ))
        icon.tintColor = .tertiaryLabel
        icon.isAccessibilityElement = false

        titleLabel.text = "No Show open"
        let titleFont = UIFont.preferredFont(forTextStyle: .title2)
        titleLabel.font = titleFont.fontDescriptor.withSymbolicTraits(.traitBold)
            .map { UIFont(descriptor: $0, size: 0) } ?? titleFont
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center

        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        var newConfig = UIButton.Configuration.filled()
        newConfig.title = "+ New Show"
        newConfig.baseBackgroundColor = .accent
        newConfig.baseForegroundColor = .white
        newConfig.cornerStyle = .capsule
        newConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 11, leading: 22, bottom: 11, trailing: 22
        )
        newShowButton.configuration = newConfig
        newShowButton.addAction(UIAction { [weak self] _ in
            self?.onNewShow?()
        }, for: .touchUpInside)

        var openConfig = UIButton.Configuration.plain()
        openConfig.title = "Open Show"
        openConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 11, leading: 22, bottom: 11, trailing: 22
        )
        openShowButton.configuration = openConfig
        openShowButton.addAction(UIAction { [weak self] _ in
            self?.onOpenShow?()
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            icon, titleLabel, detailLabel, newShowButton, openShowButton
        ])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.setCustomSpacing(16, after: icon)
        stack.setCustomSpacing(22, after: detailLabel)
        stack.setCustomSpacing(2, after: newShowButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let centered = stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -30)
        centered.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            centered,
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 12),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 32
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -32
            )
        ])
        configure(hasShows: false)
    }
}
