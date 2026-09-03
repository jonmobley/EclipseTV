//
//  HomeMusicLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Layout math for the home Music pane (drawer on regular, paging on compact).
enum HomeMusicLayout {

    /// Preferred Music sidebar / drawer width in regular-width layout.
    static let sidebarPreferredWidth: CGFloat = 340
    /// Minimum Library pane width when Music was pinned beside it (legacy).
    static let librarySplitMinWidth: CGFloat = 360
    /// Floor for a squeezed Music sidebar on narrower regular widths.
    static let sidebarMinWidth: CGFloat = 280
    /// UserDefaults key for the legacy pinned-sidebar preference.
    static let pinDefaultsKey = "EclipseTV.home.musicSidebarPinned"

    /// How Library and Music share the home screen.
    enum Mode: Equatable {
        /// Compact width: swipe between full-width Library and Music pages.
        case paging
        /// Legacy: persistent side-by-side sidebar (no longer selected).
        case split
        /// Regular width: Library is full width; Music is a slide-out drawer.
        case drawer
    }

    /// Resolves the home Music layout for the current size class.
    ///
    /// Regular width always uses the slide-out drawer (no pinned split). The
    /// blue Music circle toggles that pane; there is no Music header tab.
    static func mode(
        horizontalSizeClass: UIUserInterfaceSizeClass,
        pinned: Bool
    ) -> Mode {
        _ = pinned
        guard horizontalSizeClass == .regular else { return .paging }
        return .drawer
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
