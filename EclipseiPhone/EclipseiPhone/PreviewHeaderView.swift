//
//  PreviewHeaderView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// What a Preview header describes, and what it can hand to the share sheet.
struct PreviewHeaderItem: Equatable {

    /// Library item id used to look up the overlay title. `nil` for Show tools.
    var itemId: String?
    /// Local file offered to the share sheet. `nil` hides Share.
    var shareURL: URL?

    /// Close-only header: no title lookup, no Share.
    static let untitled = PreviewHeaderItem()

    /// A library still or video: titled from `MediaTitleStore` and shareable.
    static func libraryItem(id: String, fileURL: URL) -> PreviewHeaderItem {
        PreviewHeaderItem(itemId: id, shareURL: fileURL)
    }

    /// Header payload for one Show gallery page.
    ///
    /// Screensaver and Background are Show tools rather than library media, so they
    /// carry neither an overlay title nor a file to share.
    static func showPage(_ item: ShowPreviewItem) -> PreviewHeaderItem {
        switch item {
        case .still(let still):
            return libraryItem(id: still.id, fileURL: still.fileURL)
        case .displayMode:
            return .untitled
        }
    }
}

/// Top overlay chrome for fullscreen phone Preview: Share, the item's title, ⋯, Close.
///
/// Only the buttons take touches — the scrim and title let pinch, pan, and
/// double-tap reach the media underneath. Titles come from `MediaTitleStore` and
/// refresh in place when the user edits one, including from this header's own ⋯.
final class PreviewHeaderView: UIView {

    /// Invoked when the user taps Close.
    var onClose: (() -> Void)?
    /// Invoked with the file to share and the button to anchor the sheet to.
    var onShare: ((URL, UIButton) -> Void)?
    /// Builds the ⋯ menu for the given item id. Called each time the menu opens so
    /// checkmarks and Add / Edit wording stay current; `nil` hides the button.
    var menuProvider: ((String) -> UIMenu?)? {
        didSet { reload() }
    }

    let titleLabel = UILabel()
    let shareButton = UIButton(type: .system)
    let moreButton = UIButton(type: .system)
    let closeButton = UIButton(type: .system)

    private let scrim = GradientView()
    private var item = PreviewHeaderItem.untitled
    private var titleObserver: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let titleObserver {
            NotificationCenter.default.removeObserver(titleObserver)
        }
    }

    /// Points the header at a page: title from `MediaTitleStore`, Share at its file.
    func configure(with item: PreviewHeaderItem) {
        self.item = item
        reload()
    }

    /// Re-reads the current item's title after an Add / Edit title.
    func reload() {
        let title = item.itemId.flatMap { MediaTitleStore.title(forId: $0) }
        titleLabel.text = title
        titleLabel.isHidden = title == nil
        shareButton.isHidden = item.shareURL == nil
        moreButton.isHidden = item.itemId == nil || menuProvider == nil
        scrim.isHidden = title == nil
    }

    /// Only the buttons capture taps; zoom and pan pass through the rest.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled else { return nil }
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        setupScrim()
        setupTitle()
        setupButtons()
        activateConstraints()
        reload()
        observeTitleChanges()
    }

    private func setupScrim() {
        scrim.colors = [
            UIColor.black.withAlphaComponent(0.55),
            UIColor.black.withAlphaComponent(0)
        ]
        scrim.locations = [0, 1]
        scrim.isUserInteractionEnabled = false
        scrim.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrim)
    }

    private func setupTitle() {
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.shadowColor = UIColor.black.withAlphaComponent(0.5)
        titleLabel.shadowOffset = CGSize(width: 0, height: 1)
        titleLabel.accessibilityTraits = .header
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
    }

    private func setupButtons() {
        shareButton.applyPreviewShareAppearance()
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        addSubview(shareButton)

        moreButton.applyPreviewChromeAppearance(
            systemName: "ellipsis", accessibilityLabel: "More"
        )
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.showsMenuAsPrimaryAction = true
        // Rebuilt on every open: Loop / Mute checkmarks and Add vs Edit wording
        // change underneath a cached menu.
        moreButton.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.menuChildrenForCurrentItem() ?? [])
            }
        ])
        addSubview(moreButton)

        closeButton.applyPreviewCloseAppearance()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(closeButton)
    }

    private func activateConstraints() {
        NSLayoutConstraint.activate([
            scrim.topAnchor.constraint(equalTo: topAnchor),
            scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: bottomAnchor),

            closeButton.topAnchor.constraint(
                equalTo: safeAreaLayoutGuide.topAnchor, constant: 12
            ),
            closeButton.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -16
            ),
            bottomAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 12),

            shareButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            shareButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            moreButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            moreButton.trailingAnchor.constraint(
                equalTo: closeButton.leadingAnchor, constant: -8
            ),

            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: shareButton.trailingAnchor, constant: 12
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: moreButton.leadingAnchor, constant: -12
            )
        ])
    }

    private func observeTitleChanges() {
        titleObserver = NotificationCenter.default.addObserver(
            forName: MediaTitleStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let changedId = note.object as? String, changedId != self.item.itemId {
                return
            }
            self.reload()
        }
    }

    // MARK: - Actions

    /// Actions the ⋯ button offers for the page on screen right now.
    func menuChildrenForCurrentItem() -> [UIMenuElement] {
        guard let itemId = item.itemId, let menu = menuProvider?(itemId) else { return [] }
        return menu.children
    }

    @objc private func shareTapped() {
        guard let url = item.shareURL else { return }
        onShare?(url, shareButton)
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
