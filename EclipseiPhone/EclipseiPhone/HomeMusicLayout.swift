//
//  HomeMusicLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Layout math and pin preference for the home Music pane.
enum HomeMusicLayout {

    /// Preferred Music sidebar / drawer width in regular-width layout.
    static let sidebarPreferredWidth: CGFloat = 340
    /// Minimum Library pane width when Music is pinned beside it.
    static let librarySplitMinWidth: CGFloat = 360
    /// Floor for a squeezed Music sidebar on narrower regular widths.
    static let sidebarMinWidth: CGFloat = 280
    /// UserDefaults key for the pinned (always-visible) sidebar.
    static let pinDefaultsKey = "EclipseTV.home.musicSidebarPinned"

    /// How Library and Music share the home screen.
    enum Mode: Equatable {
        /// Compact width: swipe between full-width Library and Music pages.
        case paging
        /// Regular width, pinned: persistent side-by-side sidebar.
        case split
        /// Regular width, default: Library is full width; Music is a drawer.
        case drawer
    }

    /// Resolves the home Music layout for the current size class and pin.
    static func mode(
        horizontalSizeClass: UIUserInterfaceSizeClass,
        pinned: Bool
    ) -> Mode {
        guard horizontalSizeClass == .regular else { return .paging }
        return pinned ? .split : .drawer
    }

    /// Music sidebar width, keeping Library at least `librarySplitMinWidth`
    /// when possible.
    static func sidebarWidth(for totalWidth: CGFloat) -> CGFloat {
        let preferred = sidebarPreferredWidth
        let minLibrary = librarySplitMinWidth
        if totalWidth >= minLibrary + preferred {
            return preferred
        }
        return max(sidebarMinWidth, totalWidth - minLibrary)
    }

    /// Snap decision after an interactive drag. Negative `velocityX` is toward
    /// open (finger moving left).
    static func shouldSettleOpen(progress: CGFloat, velocityX: CGFloat) -> Bool {
        if velocityX < -420 { return true }
        if velocityX > 420 { return false }
        return progress >= 0.5
    }

    /// Whether Music stays pinned beside Library (`false` until the user pins).
    static func isPinned(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pinDefaultsKey)
    }

    /// Persists the pinned-sidebar preference.
    static func setPinned(_ pinned: Bool, defaults: UserDefaults = .standard) {
        defaults.set(pinned, forKey: pinDefaultsKey)
    }
}
