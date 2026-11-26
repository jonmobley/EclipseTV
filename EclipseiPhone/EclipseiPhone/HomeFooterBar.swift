//
//  HomeFooterBar.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Floating bar at the bottom of the paging home screen: a search field for the
/// page in front, and Camera.
///
/// It slides away while the page scrolls down and returns on the way back up, and
/// rides above the keyboard while searching. Home has nothing to search, so there
/// it is the Camera button alone.
final class HomeFooterBar: UIView {

    /// Invoked when the search field takes focus.
    var onBeginSearch: (() -> Void)?
    /// Invoked as the search text changes.
    var onSearchTextChanged: ((String) -> Void)?
    /// Invoked by the ✕ beside the search field.
    var onCancelSearch: (() -> Void)?
    /// Invoked by Camera.
    var onOpenCamera: (() -> Void)?

    static let height: CGFloat = 48

    let searchField = UISearchTextField()
    private let cameraButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let stack = UIStackView()

    /// The page in front can be searched (Library, Music's list, an open Show).
    private(set) var isSearchable = false
    /// The field has focus or text: the bar must stay up, with ✕ in place of Camera.
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

    /// Shows the search field with `placeholder`, or (nil) leaves Camera alone.
    func setSearch(placeholder: String?) {
        isSearchable = placeholder != nil
        if let placeholder {
            searchField.placeholder = placeholder
        }
        applyControls()
    }

    /// Marks a search as under way (focus or text) or over.
    func setSearching(_ searching: Bool) {
        isSearching = searching
        if !searching {
            searchField.text = ""
            searchField.resignFirstResponder()
        } else {
            setScrolledAway(false, animated: true)
        }
        applyControls()
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

    private func setup() {
        accessibilityIdentifier = "home.footer"

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.returnKeyType = .search
        searchField.backgroundColor = .secondarySystemBackground
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

        configureRound(
            cameraButton,
            systemName: ThumbnailTypeIcon.camera.systemName,
            label: "Camera"
        )
        cameraButton.accessibilityHint =
            "Opens the camera. Nothing goes to the TV until you tap the picture."
        cameraButton.accessibilityIdentifier = "home.camera"
        cameraButton.addAction(UIAction { [weak self] _ in
            self?.onOpenCamera?()
        }, for: .touchUpInside)

        configureRound(cancelButton, systemName: "xmark", label: "Cancel search")
        cancelButton.addAction(UIAction { [weak self] _ in
            self?.onCancelSearch?()
        }, for: .touchUpInside)

        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(searchField)
        stack.addArrangedSubview(cameraButton)
        stack.addArrangedSubview(cancelButton)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
            // On a wide screen the field stops short and Camera stays beside it.
            searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
            cameraButton.widthAnchor.constraint(equalToConstant: Self.height),
            cancelButton.widthAnchor.constraint(equalToConstant: Self.height)
        ])
        // The field takes the room; without it the bar is just the button.
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let fill = stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        fill.priority = .defaultHigh
        fill.isActive = true
        applyControls()
    }

    private func configureRound(_ button: UIButton, systemName: String, label: String) {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )
        config.baseBackgroundColor = .secondarySystemBackground
        config.baseForegroundColor = .label
        config.cornerStyle = .capsule
        button.configuration = config
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func applyControls() {
        searchField.isHidden = !isSearchable
        cancelButton.isHidden = !(isSearchable && isSearching)
        cameraButton.isHidden = isSearchable && isSearching
    }

    /// Only the controls take touches: beside a lone Camera button the page shows
    /// through and stays tappable.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for view in [searchField, cameraButton, cancelButton] where !view.isHidden {
            if view.frame.insetBy(dx: -4, dy: -4).contains(
                convert(point, to: stack)
            ) {
                return true
            }
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
