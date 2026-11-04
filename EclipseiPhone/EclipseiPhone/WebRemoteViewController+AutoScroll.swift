//
//  WebRemoteViewController+AutoScroll.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Auto Scroll chrome

extension WebRemoteViewController {

    /// Nav-bar Auto Scroll: tap starts or stops, long-press picks the speed.
    func makeAutoScrollBarButton() -> UIBarButtonItem {
        let item = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: Self.autoScrollSymbol(for: .off)),
            primaryAction: UIAction { [weak self] _ in self?.autoScrollTapped() },
            menu: autoScrollSpeedMenu()
        )
        item.accessibilityLabel = "Auto Scroll"
        item.accessibilityHint = "Scrolls the page down by itself. Touch and hold for speed."
        return item
    }

    /// Landscape overlay Auto Scroll button (same tap / long-press behaviour).
    func makeOverlayAutoScrollButton() -> UIButton {
        let button = makeOverlayChromeButton(
            systemName: "arrow.down.circle",
            accessibilityLabel: "Auto Scroll",
            action: #selector(autoScrollTapped)
        )
        button.menu = autoScrollSpeedMenu()
        button.accessibilityHint = "Scrolls the page down by itself. Touch and hold for speed."
        return button
    }

    /// Speed choices, checkmarked at the current one.
    func autoScrollSpeedMenu() -> UIMenu {
        let current = autoScroller.speed
        let options = WebAutoScroller.speedOptions.map { multiplier in
            UIAction(
                title: WebAutoScroller.speedLabel(multiplier),
                state: multiplier == current ? .on : .off
            ) { [weak self] _ in
                self?.autoScroller.setSpeed(multiplier)
            }
        }
        return UIMenu(
            title: "Auto Scroll Speed",
            image: UIImage(systemName: "speedometer"),
            children: options
        )
    }

    /// Repaints both Auto Scroll buttons, their speed menus, and the page tap.
    func updateAutoScrollChrome() {
        let state = autoScroller.state
        let symbolName = Self.autoScrollSymbol(for: state)
        let label = state == .off ? "Auto Scroll" : "Stop Auto Scroll"
        autoScrollBarButton?.image = UIImage(systemName: symbolName)
        autoScrollBarButton?.accessibilityLabel = label
        autoScrollBarButton?.menu = autoScrollSpeedMenu()
        if let overlay = overlayAutoScrollButton {
            let symbol = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            overlay.configuration?.image = UIImage(systemName: symbolName, withConfiguration: symbol)
            overlay.configuration?.baseForegroundColor = state == .off ? .white : .liveStroke
            overlay.accessibilityLabel = label
            overlay.menu = autoScrollSpeedMenu()
        }
        // Only while Auto Scroll is on does a tap belong to it; otherwise links work.
        autoScrollTap?.isEnabled = autoScroller.isActive
        refreshBookmarksMenu()
    }

    /// Installs the page tap that pauses / resumes Auto Scroll, once the stage exists,
    /// and makes the active web view's own tap handling wait for it.
    ///
    /// A web view recognises taps itself and would otherwise win every time. While
    /// Auto Scroll is on its recognisers wait for ours, so a tap toggles instead of
    /// clicking a link; while it is off ours is disabled, fails at once, and links
    /// work as usual. Scrolling is untouched either way (the scroll view's pan is
    /// not among them).
    func installAutoScrollTapIfNeeded() {
        if autoScrollTap == nil, let stage = webStageView {
            let tap = UITapGestureRecognizer(target: self, action: #selector(autoScrollPageTapped))
            tap.isEnabled = autoScroller.isActive
            stage.addGestureRecognizer(tap)
            autoScrollTap = tap
        }
        guard let tap = autoScrollTap, let content = webView?.scrollView.subviews.first else { return }
        for recognizer in content.gestureRecognizers ?? [] where recognizer !== tap {
            recognizer.require(toFail: tap)
        }
    }

    @objc func autoScrollTapped() {
        autoScroller.toggle()
        Haptics.impactLight()
    }

    @objc func autoScrollPageTapped() {
        guard autoScroller.isActive else { return }
        autoScroller.togglePlayPause()
        Haptics.impactLight()
    }

    /// Off: a down arrow. Running: pause. Paused: play.
    static func autoScrollSymbol(for state: WebAutoScroller.State) -> String {
        switch state {
        case .off: return "arrow.down.circle"
        case .running: return "pause.circle.fill"
        case .paused: return "play.circle.fill"
        }
    }
}
