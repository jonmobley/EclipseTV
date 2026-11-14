//
//  WebHistoryDrawerView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// The phone browser's history drawer: saved websites, then recent pages.
///
/// It slides in from the right edge beside a Landscape card (where the buttons and
/// the thumb already are) and up from the bottom in Vertical. It lives inside the
/// browser's view rather than being presented, so it never asks the scene to turn.
final class WebHistoryDrawerView: UIView {

    enum Placement: Equatable {
        case trailing
        case bottom
    }

    var onSelectSaved: ((WebPage) -> Void)?
    var onSelectRecent: ((URL) -> Void)?
    var onClearRecent: (() -> Void)?
    var onDismiss: (() -> Void)?

    var placement: Placement {
        didSet { if placement != oldValue { applyPlacementStyle(); setNeedsLayout() } }
    }

    private(set) var saved: [WebPage] = []
    private(set) var currentSavedId: UUID?
    private(set) var recent: [WebHistoryEntry] = []

    private let dimmer = UIControl()
    let panel = UIView()
    private let grabber = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var isShown = false

    static let trailingWidth: CGFloat = 360
    static let bottomHeightFraction: CGFloat = 0.62
    private static let headerHeight: CGFloat = 52

    private enum Section: Int, CaseIterable { case saved, recent }

    init(placement: Placement) {
        self.placement = placement
        super.init(frame: .zero)
        overrideUserInterfaceStyle = .dark

        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimmer.alpha = 0
        dimmer.isAccessibilityElement = true
        dimmer.accessibilityLabel = "Close History"
        dimmer.accessibilityTraits = .button
        dimmer.addAction(UIAction { [weak self] _ in self?.dismiss() }, for: .touchUpInside)
        addSubview(dimmer)

        panel.backgroundColor = UIColor(white: 0.11, alpha: 1)
        panel.layer.cornerCurve = .continuous
        panel.layer.cornerRadius = 22
        panel.clipsToBounds = true
        panel.accessibilityViewIsModal = true
        addSubview(panel)

        grabber.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        grabber.layer.cornerRadius = 2.5
        panel.addSubview(grabber)

        titleLabel.text = "History"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.accessibilityTraits = .header
        panel.addSubview(titleLabel)

        var close = UIButton.Configuration.plain()
        close.image = UIImage(
            systemName: "xmark.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        )
        close.baseForegroundColor = UIColor.white.withAlphaComponent(0.55)
        closeButton.configuration = close
        closeButton.accessibilityLabel = "Close History"
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss() }, for: .touchUpInside)
        panel.addSubview(closeButton)

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        panel.addSubview(tableView)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
        swipeRight.direction = .right
        panel.addGestureRecognizer(swipeRight)
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
        swipeDown.direction = .down
        panel.addGestureRecognizer(swipeDown)
        swipeDown.delegate = self
        swipeRight.delegate = self

        applyPlacementStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(saved: [WebPage], currentSavedId: UUID?, recent: [WebHistoryEntry]) {
        self.saved = saved
        self.currentSavedId = currentSavedId
        self.recent = recent
        tableView.reloadData()
    }

    // MARK: - Show / dismiss

    /// Adds the drawer over `host` and slides the panel in.
    func show(in host: UIView, animated: Bool = true) {
        frame = host.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(self)
        isShown = true
        layoutIfNeeded()
        let shown = panel.frame
        panel.frame = offscreenFrame(for: shown)
        let animations = {
            self.dimmer.alpha = 1
            self.panel.frame = shown
        }
        if animated, window != nil {
            UIView.animate(
                withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.92,
                initialSpringVelocity: 0, options: [.beginFromCurrentState],
                animations: animations
            )
        } else {
            animations()
        }
        UIAccessibility.post(notification: .screenChanged, argument: titleLabel)
    }

    /// Slides the panel away and removes the drawer.
    func dismiss(animated: Bool = true) {
        guard isShown else { return }
        isShown = false
        let finish = { [weak self] in
            guard let self else { return }
            self.removeFromSuperview()
            self.onDismiss?()
        }
        guard animated, window != nil else { finish(); return }
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseIn]) {
            self.dimmer.alpha = 0
            self.panel.frame = self.offscreenFrame(for: self.panel.frame)
        } completion: { _ in
            finish()
        }
    }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        switch (placement, gesture.direction) {
        case (.trailing, .right):
            dismiss()
        case (.bottom, .down):
            // Only from the top of the list; lower down a swipe just scrolls it.
            let top = -tableView.adjustedContentInset.top
            if tableView.contentOffset.y <= top + 1 { dismiss() }
        default:
            break
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        dimmer.frame = bounds
        // While sliding away the panel keeps its animated frame.
        guard isShown else { return }
        panel.frame = Self.panelFrame(placement: placement, in: bounds, safe: safeAreaInsets)
        layoutPanelContents()
    }

    /// The panel: a full-height column at the right edge, or the lower part of the screen.
    static func panelFrame(placement: Placement, in bounds: CGRect, safe: UIEdgeInsets) -> CGRect {
        switch placement {
        case .trailing:
            let width = min(trailingWidth + safe.right, bounds.width * 0.6)
            return CGRect(x: bounds.maxX - width, y: bounds.minY, width: width, height: bounds.height)
        case .bottom:
            let height = min(bounds.height * bottomHeightFraction, 600)
            return CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height)
        }
    }

    private func layoutPanelContents() {
        let safe = safeAreaInsets
        let inner: UIEdgeInsets
        switch placement {
        case .trailing:
            inner = UIEdgeInsets(top: max(safe.top, 12), left: 4, bottom: 0, right: safe.right)
        case .bottom:
            inner = UIEdgeInsets(top: 14, left: safe.left, bottom: 0, right: safe.right)
        }
        let content = panel.bounds.inset(by: inner)
        grabber.frame = CGRect(x: panel.bounds.midX - 18, y: 6, width: 36, height: 5)
        let header = CGRect(x: content.minX + 16, y: content.minY, width: content.width - 24,
                            height: Self.headerHeight)
        let closeSize: CGFloat = 44
        closeButton.frame = CGRect(x: header.maxX - closeSize, y: header.midY - closeSize / 2,
                                   width: closeSize, height: closeSize)
        titleLabel.frame = CGRect(x: header.minX, y: header.minY,
                                  width: closeButton.frame.minX - header.minX, height: header.height)
        tableView.frame = CGRect(x: content.minX, y: header.maxY, width: content.width,
                                 height: panel.bounds.maxY - header.maxY)
        tableView.contentInset.bottom = placement == .bottom ? safe.bottom : max(safe.bottom, 8)
    }

    private func applyPlacementStyle() {
        grabber.isHidden = placement != .bottom
        switch placement {
        case .trailing:
            panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        case .bottom:
            panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        }
    }

    private func offscreenFrame(for frame: CGRect) -> CGRect {
        switch placement {
        case .trailing: return frame.offsetBy(dx: bounds.maxX - frame.minX, dy: 0)
        case .bottom: return frame.offsetBy(dx: 0, dy: bounds.maxY - frame.minY)
        }
    }

    // MARK: - Rows

    /// What a row in `section` shows; empty sections show one placeholder row.
    enum Row: Equatable {
        case saved(WebPage)
        case noSaved
        case recent(WebHistoryEntry)
        case noRecent
        case clearRecent
    }

    func rows(in section: Int) -> [Row] {
        switch Section(rawValue: section) {
        case .saved:
            return saved.isEmpty ? [.noSaved] : saved.map(Row.saved)
        case .recent:
            return recent.isEmpty ? [.noRecent] : recent.map(Row.recent) + [.clearRecent]
        case nil:
            return []
        }
    }

    /// "Today 3:42 PM"-style stamp for a recent row.
    static func visitedText(_ date: Date) -> String {
        visitedFormatter.string(from: date)
    }

    private static let visitedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

extension WebHistoryDrawerView: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows(in: section).count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .saved: return "Saved"
        case .recent: return "Recent"
        case nil: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.secondaryTextProperties.color = .secondaryLabel
        content.textProperties.numberOfLines = 1
        content.secondaryTextProperties.numberOfLines = 1
        cell.accessoryType = .none
        cell.selectionStyle = .default
        cell.accessibilityTraits = .button

        switch rows(in: indexPath.section)[indexPath.row] {
        case .saved(let page):
            content.text = page.title
            content.secondaryText = WebHistoryStore.fallbackTitle(for: page.url)
            content.image = UIImage(systemName: "safari")
            if page.id == currentSavedId {
                cell.accessoryType = .checkmark
                cell.accessibilityTraits = [.button, .selected]
            }
        case .noSaved:
            content = .cell()
            content.text = "No saved websites"
            content.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
            cell.accessibilityTraits = .staticText
        case .recent(let entry):
            content.text = entry.title
            content.secondaryText = WebHistoryStore.fallbackTitle(for: entry.url)
                + " · " + Self.visitedText(entry.visitedAt)
            content.image = UIImage(systemName: "clock")
        case .noRecent:
            content = .cell()
            content.text = "Pages you visit show up here"
            content.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
            cell.accessibilityTraits = .staticText
        case .clearRecent:
            content = .cell()
            content.text = "Clear Recent"
            content.textProperties.color = .systemRed
        }
        content.imageProperties.tintColor = .secondaryLabel
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows(in: indexPath.section)[indexPath.row] {
        case .saved(let page):
            dismiss()
            onSelectSaved?(page)
        case .recent(let entry):
            dismiss()
            onSelectRecent?(entry.url)
        case .clearRecent:
            onClearRecent?()
        case .noSaved, .noRecent:
            break
        }
    }
}

extension WebHistoryDrawerView: UIGestureRecognizerDelegate {
    /// Swipes ride alongside the list's own scrolling.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
