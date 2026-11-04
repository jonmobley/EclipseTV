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
            image: Self.autoScrollImage(isRunning: false),
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

    /// Repaints both Auto Scroll buttons and their speed menus.
    func updateAutoScrollChrome() {
        let running = autoScroller.isRunning
        let image = Self.autoScrollImage(isRunning: running)
        let label = running ? "Stop Auto Scroll" : "Auto Scroll"
        autoScrollBarButton?.image = image
        autoScrollBarButton?.accessibilityLabel = label
        autoScrollBarButton?.menu = autoScrollSpeedMenu()
        if let overlay = overlayAutoScrollButton {
            let symbol = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            overlay.configuration?.image = UIImage(
                systemName: running ? "pause.circle.fill" : "arrow.down.circle",
                withConfiguration: symbol
            )
            overlay.configuration?.baseForegroundColor = running ? .liveStroke : .white
            overlay.accessibilityLabel = label
            overlay.menu = autoScrollSpeedMenu()
        }
        refreshBookmarksMenu()
    }

    @objc func autoScrollTapped() {
        autoScroller.toggle()
        Haptics.impactLight()
    }

    private static func autoScrollImage(isRunning: Bool) -> UIImage? {
        UIImage(systemName: isRunning ? "pause.circle.fill" : "arrow.down.circle")
    }
}
