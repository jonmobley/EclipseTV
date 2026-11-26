//
//  HomeFooterBar.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// iOS-style footer for the paging home screen: a glass bar of icon buttons,
/// Camera and Search, like a tab bar's, with no words under them. The blue Music
/// circle sits beside it.
///
/// Search turns the bar into the search field for the page in front, with ✕ beside
/// it, the way the system's search tab does. The bar slides away while the page
/// scrolls down and returns on the way back up, and rides above the keyboard while
/// searching. Home has nothing to search, so there it is Camera alone.
final class HomeFooterBar: UIView {

    /// Invoked when the search field takes focus.
    var onBeginSearch: (() -> Void)?
    /// Invoked as the search text changes.
    var onSearchTextChanged: ((String) -> Void)?
    /// Invoked by the ✕ beside the search field.
    var onCancelSearch: (() -> Void)?
    /// Invoked by Camera.
    var onOpenCamera: (() -> Void)?

    static let height: CGFloat = 52

    let searchField = UISearchTextField()
    private let bar = HomeFooterBar.makeGlass()
    private let cancelGlass = HomeFooterBar.makeGlass()
    private let cameraButton = UIButton(type: .system)
    private let searchButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let buttonStack = UIStackView()
    private var idleConstraints: [NSLayoutConstraint] = []
    private var searchingConstraints: [NSLayoutConstraint] = []
    private var placeholder = "Search"

    /// The page in front can be searched (Library, Music's list, an open Show).
    private(set) var isSearchable = false
    /// The field is up: the bar must stay, with ✕ beside it.
    private(set) var isSearching = false
    /// Slid away by scrolling.
    private(set) var isScrolledAway = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the Search button, with `placeholder` for its field, or (nil) leaves
    /// Camera alone.
    func setSearch(placeholder: String?) {
        isSearchable = placeholder != nil
        if let placeholder {
            self.placeholder = placeholder
            searchField.placeholder = placeholder
        }
        applyControls()
    }

    /// Marks a search as under way (the field is up) or over.
    func setSearching(_ searching: Bool) {
        guard searching != isSearching else { return }
        isSearching = searching
        if searching {
            setScrolledAway(false, animated: true)
        } else {
            searchField.text = ""
            searchField.resignFirstResponder()
        }
        let apply = {
            self.applyControls()
            self.layoutIfNeeded()
        }
        if window != nil, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: apply
            )
        } else {
            apply()
        }
    }

    /// Slides the bar off the bottom (scrolling down) or back (scrolling up).
    /// A search in progress keeps it up.
    func setScrolledAway(_ away: Bool, animated: Bool) {
        let away = away && !isSearching
        guard away != isScrolledAway else { return }
        isScrolledAway = away
        let apply = {
            self.transform = away
                ? CGAffineTransform(translationX: 0, y: Self.height + 40) : .identity
            self.alpha = away ? 0 : 1
        }
        if animated, window != nil, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                animations: apply
            )
        } else {
            apply()
        }
    }

    // MARK: - Setup

    /// Liquid Glass on iOS 26, a blurred material before it.
    private static func makeGlass() -> UIVisualEffectView {
        let view: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = true
            view = UIVisualEffectView(effect: glass)
        } else {
            view = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        }
        view.layer.cornerRadius = height / 2
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func setup() {
        accessibilityIdentifier = "home.footer"
        addSubview(bar)
        addSubview(cancelGlass)

        configureItem(
            cameraButton,
            systemName: ThumbnailTypeIcon.camera.systemName,
            title: "Camera"
        )
        cameraButton.accessibilityHint =
            "Opens the camera. Nothing goes to the TV until you tap the picture."
        cameraButton.accessibilityIdentifier = "home.camera"
        cameraButton.addAction(UIAction { [weak self] _ in
            self?.onOpenCamera?()
        }, for: .touchUpInside)

        configureItem(searchButton, systemName: "magnifyingglass", title: "Search")
        searchButton.accessibilityIdentifier = "home.search"
        searchButton.addAction(UIAction { [weak self] _ in
            self?.searchField.becomeFirstResponder()
        }, for: .touchUpInside)

        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 0
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.addArrangedSubview(cameraButton)
        buttonStack.addArrangedSubview(searchButton)
        bar.contentView.addSubview(buttonStack)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.returnKeyType = .search
        searchField.backgroundColor = .clear
        searchField.borderStyle = .none
        searchField.accessibilityIdentifier = "home.search.field"
        searchField.addAction(UIAction { [weak self] _ in
            self?.onBeginSearch?()
        }, for: .editingDidBegin)
        searchField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onSearchTextChanged?(self.searchField.text ?? "")
        }, for: .editingChanged)
        // Return keeps the results and puts the keyboard away.
        searchField.addAction(UIAction { [weak self] _ in
            self?.searchField.resignFirstResponder()
        }, for: .editingDidEndOnExit)
        // Keyboard put away with nothing typed: the search is over.
        searchField.addAction(UIAction { [weak self] _ in
            guard let self, (self.searchField.text ?? "").isEmpty, self.isSearching else {
                return
            }
            self.onCancelSearch?()
        }, for: .editingDidEnd)
        bar.contentView.addSubview(searchField)

        var cancelConfig = UIButton.Configuration.plain()
        cancelConfig.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        )
        cancelConfig.baseForegroundColor = .label
        cancelButton.configuration = cancelConfig
        cancelButton.accessibilityLabel = "Cancel search"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addAction(UIAction { [weak self] _ in
            self?.onCancelSearch?()
        }, for: .touchUpInside)
        cancelGlass.contentView.addSubview(cancelButton)

        // Idle: the bar hugs its buttons. Searching: it stretches for the field,
        // up to ✕ (and stops short on a wide screen).
        idleConstraints = [
            bar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ]
        let stretch = bar.trailingAnchor.constraint(
            equalTo: cancelGlass.leadingAnchor, constant: -10
        )
        stretch.priority = .defaultHigh
        searchingConstraints = [
            stretch,
            bar.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            bar.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            cancelGlass.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ]
        let hug = bar.widthAnchor.constraint(equalTo: buttonStack.widthAnchor, constant: 12)
        hug.priority = .defaultLow
        let pinCancel = cancelGlass.trailingAnchor.constraint(equalTo: trailingAnchor)
        pinCancel.priority = .defaultLow

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            hug,

            buttonStack.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor, constant: 6),
            buttonStack.topAnchor.constraint(equalTo: bar.contentView.topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: bar.contentView.bottomAnchor),
            cameraButton.widthAnchor.constraint(equalToConstant: 60),

            searchField.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor, constant: 18),
            searchField.trailingAnchor.constraint(equalTo: bar.contentView.trailingAnchor, constant: -14),
            searchField.topAnchor.constraint(equalTo: bar.contentView.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: bar.contentView.bottomAnchor),

            cancelGlass.topAnchor.constraint(equalTo: topAnchor),
            cancelGlass.bottomAnchor.constraint(equalTo: bottomAnchor),
            cancelGlass.widthAnchor.constraint(equalToConstant: Self.height),
            pinCancel,
            cancelButton.leadingAnchor.constraint(equalTo: cancelGlass.contentView.leadingAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: cancelGlass.contentView.trailingAnchor),
            cancelButton.topAnchor.constraint(equalTo: cancelGlass.contentView.topAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: cancelGlass.contentView.bottomAnchor)
        ])
        applyControls()
    }

    /// A tab-bar style button, symbol only (the owner wants no words down here);
    /// `title` is what VoiceOver says.
    private func configureItem(_ button: UIButton, systemName: String, title: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)
        )
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        button.configuration = config
        button.showsLargeContentViewer = true
        button.largeContentTitle = title
        button.accessibilityLabel = title
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func applyControls() {
        searchButton.isHidden = !isSearchable
        buttonStack.isHidden = isSearching
        buttonStack.alpha = isSearching ? 0 : 1
        searchField.isHidden = !isSearching
        cancelGlass.isHidden = !isSearching
        NSLayoutConstraint.deactivate(idleConstraints + searchingConstraints)
        NSLayoutConstraint.activate(isSearching ? searchingConstraints : idleConstraints)
    }

    /// Only the glass takes touches; the page beside it shows through and stays
    /// tappable.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for view in [bar, cancelGlass] where !view.isHidden {
            if view.frame.contains(point) { return true }
        }
        return false
    }
}

/// When the bottom bar hides: the rule for one scroll step.
enum HomeFooterScroll {

    /// `true` hide, `false` show, `nil` leave as it is.
    ///
    /// - Parameters:
    ///   - delta: How far the page moved since the last step (down is positive).
    ///   - distanceFromTop: How far the page is scrolled from its top.
    static func shouldHide(delta: CGFloat, distanceFromTop: CGFloat) -> Bool? {
        // At the top the bar is always there, whichever way the bounce goes.
        if distanceFromTop <= 8 { return false }
        if delta > 3 { return true }
        if delta < -3 { return false }
        return nil
    }
}
