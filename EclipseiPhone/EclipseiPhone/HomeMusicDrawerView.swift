//
//  HomeMusicDrawerView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Floating Music drawer: pull-tab, dimming scrim, and a sliding panel.
final class HomeMusicDrawerView: UIView, UIGestureRecognizerDelegate {

    static let tabWidth: CGFloat = 32
    static let tabHeight: CGFloat = 76
    private static let panelCornerRadius: CGFloat = 16
    private static let dimmingAlpha: CGFloat = 0.32

    private let panel = UIView()
    private let dimmingView = UIControl()
    private let slideContainer = UIView()
    private let tab = UIView()
    private let tabIcon = UIImageView()
    private let tabPan = UIPanGestureRecognizer()
    private let panelPan = UIPanGestureRecognizer()

    private var panelWidthConstraint: NSLayoutConstraint?
    private var isTracking = false
    private var progressAtDragStart: CGFloat = 0
    private var settledOpen = false

    /// 0 = closed (tab peeking), 1 = open.
    private(set) var progress: CGFloat = 0

    /// Width of the Music panel (not including the pull tab).
    var panelWidth: CGFloat = HomeMusicLayout.sidebarPreferredWidth {
        didSet {
            guard abs(panelWidth - oldValue) > 0.5 else { return }
            panelWidthConstraint?.constant = panelWidth
            applyChrome()
        }
    }

    /// When false, the overlay is hidden (paging or pinned split).
    var isDrawerEnabled = false {
        didSet {
            guard isDrawerEnabled != oldValue else { return }
            isHidden = !isDrawerEnabled
            if !isDrawerEnabled {
                setOpen(false, animated: false)
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Pins `content` to fill the Music panel.
    func embedContent(_ content: UIView) {
        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: panel.topAnchor),
            content.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
    }

    /// Opens or closes the drawer, optionally animated.
    func setOpen(_ open: Bool, animated: Bool) {
        setProgress(open ? 1 : 0, animated: animated)
    }

    /// Interactive edge-swipe from the right of the screen.
    func handleEdgePan(_ gesture: UIPanGestureRecognizer) {
        handlePan(gesture, startImmediately: true)
    }

    /// Whether `point` (in this view) lands on the pull tab, with a little slop.
    func containsTab(at point: CGPoint) -> Bool {
        let local = tab.convert(point, from: self)
        return tab.bounds.insetBy(dx: -10, dy: -10).contains(local)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isDrawerEnabled, !isHidden else { return nil }
        if progress < 0.02 {
            let tabPoint = tab.convert(point, from: self)
            return tab.hitTest(tabPoint, with: event)
        }
        return super.hitTest(point, with: event)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyChrome()
        let panelRect = panel.convert(panel.bounds, to: slideContainer)
        slideContainer.layer.shadowPath = UIBezierPath(
            roundedRect: panelRect,
            cornerRadius: Self.panelCornerRadius
        ).cgPath
    }

    // MARK: - Setup

    private func setup() {
        isHidden = true
        backgroundColor = .clear
        setupDimming()
        setupSlideContainer()
        setupPanel()
        setupTab()
        setupConstraints()
        setupGestures()
        applyChrome()
        updateTabAccessibility()
    }

    private func setupDimming() {
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(Self.dimmingAlpha)
        dimmingView.alpha = 0
        dimmingView.isUserInteractionEnabled = false
        dimmingView.accessibilityLabel = "Dismiss Music"
        dimmingView.accessibilityTraits = .button
        dimmingView.addTarget(self, action: #selector(dimmingTapped), for: .touchUpInside)
        addSubview(dimmingView)
    }

    private func setupSlideContainer() {
        slideContainer.translatesAutoresizingMaskIntoConstraints = false
        slideContainer.backgroundColor = .clear
        slideContainer.layer.shadowColor = UIColor.black.cgColor
        slideContainer.layer.shadowOpacity = 0.28
        slideContainer.layer.shadowRadius = 22
        slideContainer.layer.shadowOffset = CGSize(width: -3, height: 0)
        addSubview(slideContainer)
    }

    private func setupPanel() {
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = .systemBackground
        panel.layer.cornerRadius = Self.panelCornerRadius
        panel.layer.cornerCurve = .continuous
        panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        panel.clipsToBounds = true
        slideContainer.addSubview(panel)
    }

    private func setupTab() {
        tab.translatesAutoresizingMaskIntoConstraints = false
        tab.backgroundColor = .secondarySystemBackground
        tab.layer.cornerRadius = 16
        tab.layer.cornerCurve = .continuous
        tab.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        tab.clipsToBounds = true
        tab.isAccessibilityElement = true
        tab.accessibilityTraits = .button

        tabIcon.translatesAutoresizingMaskIntoConstraints = false
        tabIcon.contentMode = .scaleAspectFit
        tabIcon.tintColor = .label
        tabIcon.image = UIImage(
            systemName: "music.note",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        )
        tab.addSubview(tabIcon)
        slideContainer.addSubview(tab)
    }

    private func setupConstraints() {
        let width = panel.widthAnchor.constraint(equalToConstant: panelWidth)
        panelWidthConstraint = width
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: bottomAnchor),

            slideContainer.topAnchor.constraint(equalTo: topAnchor),
            slideContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            slideContainer.trailingAnchor.constraint(equalTo: trailingAnchor),

            panel.topAnchor.constraint(equalTo: slideContainer.topAnchor),
            panel.bottomAnchor.constraint(equalTo: slideContainer.bottomAnchor),
            panel.trailingAnchor.constraint(equalTo: slideContainer.trailingAnchor),
            width,

            tab.trailingAnchor.constraint(equalTo: panel.leadingAnchor),
            tab.centerYAnchor.constraint(equalTo: slideContainer.centerYAnchor),
            tab.widthAnchor.constraint(equalToConstant: Self.tabWidth),
            tab.heightAnchor.constraint(equalToConstant: Self.tabHeight),
            tab.leadingAnchor.constraint(equalTo: slideContainer.leadingAnchor),

            tabIcon.centerXAnchor.constraint(equalTo: tab.centerXAnchor, constant: -1),
            tabIcon.centerYAnchor.constraint(equalTo: tab.centerYAnchor)
        ])
    }

    private func setupGestures() {
        tabPan.addTarget(self, action: #selector(tabPanned(_:)))
        tabPan.delegate = self
        tab.addGestureRecognizer(tabPan)

        let tabTap = UITapGestureRecognizer(target: self, action: #selector(tabTapped))
        tab.addGestureRecognizer(tabTap)

        panelPan.addTarget(self, action: #selector(panelPanned(_:)))
        panelPan.delegate = self
        panel.addGestureRecognizer(panelPan)
    }

    // MARK: - Gestures

    override func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard isDrawerEnabled else { return false }
        guard gestureRecognizer === panelPan else { return true }
        let pan = panelPan
        let velocity = pan.velocity(in: panel)
        let translation = pan.translation(in: panel)
        if abs(velocity.x) + abs(velocity.y) > 80 {
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }
        return abs(translation.x) > abs(translation.y) * 1.2
    }

    @objc private func dimmingTapped() {
        setOpen(false, animated: true)
    }

    @objc private func tabTapped() {
        setOpen(progress < 0.5, animated: true)
    }

    @objc private func tabPanned(_ gesture: UIPanGestureRecognizer) {
        handlePan(gesture, startImmediately: false)
    }

    @objc private func panelPanned(_ gesture: UIPanGestureRecognizer) {
        handlePan(gesture, startImmediately: false)
    }

    private func handlePan(
        _ gesture: UIPanGestureRecognizer,
        startImmediately: Bool
    ) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        switch gesture.state {
        case .began:
            if startImmediately {
                beginTracking()
            }
        case .changed:
            if !isTracking, startImmediately || abs(translation.x) > 8 {
                beginTracking()
            }
            guard isTracking else { return }
            let delta = -translation.x / max(panelWidth, 1)
            setProgress(
                min(1, max(0, progressAtDragStart + delta)),
                animated: false
            )
        case .ended, .cancelled:
            finishPan(velocityX: velocity.x)
        default:
            break
        }
    }

    private func beginTracking() {
        isTracking = true
        progressAtDragStart = progress
        dimmingView.isUserInteractionEnabled = false
    }

    private func finishPan(velocityX: CGFloat) {
        guard isTracking else { return }
        isTracking = false
        let open = HomeMusicLayout.shouldSettleOpen(
            progress: progress, velocityX: velocityX
        )
        setOpen(open, animated: true)
    }

    // MARK: - Chrome

    private func setProgress(_ value: CGFloat, animated: Bool) {
        progress = min(1, max(0, value))
        let apply = { self.applyChrome() }
        guard animated else {
            apply()
            settleIfNeeded(animated: false)
            return
        }
        let reduce = UIAccessibility.isReduceMotionEnabled
        if reduce {
            UIView.animate(withDuration: 0.15, delay: 0, options: .beginFromCurrentState) {
                apply()
            } completion: { _ in
                self.settleIfNeeded(animated: true)
            }
            return
        }
        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.35,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            apply()
        } completion: { _ in
            self.settleIfNeeded(animated: true)
        }
    }

    private func applyChrome() {
        slideContainer.transform = CGAffineTransform(
            translationX: (1 - progress) * panelWidth, y: 0
        )
        dimmingView.alpha = progress
    }

    private func settleIfNeeded(animated: Bool) {
        guard !isTracking else { return }
        let open = progress > 0.5
        dimmingView.isUserInteractionEnabled = open
        accessibilityViewIsModal = open
        updateTabAccessibility()
        guard open != settledOpen else { return }
        settledOpen = open
        if animated {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    private func updateTabAccessibility() {
        let open = progress > 0.5
        tab.accessibilityLabel = open ? "Close Music" : "Music"
        tab.accessibilityHint = open
            ? "Hides the Music drawer."
            : "Shows Music as a drawer."
    }
}
