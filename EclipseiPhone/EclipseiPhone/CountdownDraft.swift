//
//  CountdownDraft.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Everything the Add Countdown screen collects before a countdown exists.
///
/// Kept apart from `ShowCountdown` so nothing is written to the store — or synced —
/// until the operator taps Add. Cancel simply drops the draft.
struct CountdownDraft: Equatable {
    var showId: UUID
    var name: String
    /// Length in seconds.
    var duration: Int
    var layout: CountdownClockLayout
    var background: CountdownBackground
    var endAction: CountdownEndAction

    /// Fresh draft for `showId`: next free name and the last chosen length.
    ///
    /// Everything else starts where a countdown created from the ⋯ menu did, so the
    /// screen never invents a look the operator has not asked for.
    init(
        showId: UUID,
        name: String,
        duration: Int,
        layout: CountdownClockLayout = .default,
        background: CountdownBackground = .black,
        endAction: CountdownEndAction = .hold
    ) {
        self.showId = showId
        self.name = name
        self.duration = duration
        self.layout = layout
        self.background = background
        self.endAction = endAction
    }

    /// Whether `duration` is one of the ribbon presets (Custom… is highlighted otherwise).
    var isPresetDuration: Bool {
        CountdownController.durationPresets.contains(duration)
    }

    /// `M:SS` / `H:MM:SS` for the Duration rows.
    var durationText: String {
        CountdownController.displayString(seconds: duration)
    }

    /// One-line summary of `layout` for the Size & Placement row.
    ///
    /// `Centered · 100%` when untouched, otherwise `Custom position · 130%`, so the
    /// operator can see whether the editor has been used without opening it.
    var layoutSummary: String {
        Self.layoutSummary(for: layout)
    }

    /// See `layoutSummary`.
    static func layoutSummary(for layout: CountdownClockLayout) -> String {
        let clamped = layout.clampedScale
        let percent = Int((clamped.scale * 100).rounded())
        let isCentered = abs(clamped.centerX - 0.5) < 0.005
            && abs(clamped.centerY - 0.5) < 0.005
        return "\(isCentered ? "Centered" : "Custom position") · \(percent)%"
    }

    /// Unsaved `ShowCountdown` with these values, for previews and the layout editor.
    ///
    /// The id is stable for the life of the draft so `CountdownClockLayoutPreview` can
    /// key on it; it is *not* the id the store assigns on Add.
    func previewItem(id: UUID) -> ShowCountdown {
        ShowCountdown(
            id: id,
            showId: showId,
            name: UserDisplayName.normalized(name) ?? "Countdown",
            duration: CountdownController.clampedDuration(duration),
            layout: layout,
            background: background,
            endAction: endAction
        )
    }

    /// Creates the countdown in `store` and remembers `duration` as the next default.
    @MainActor
    @discardableResult
    func commit(
        to store: CountdownStore = .shared,
        defaults: UserDefaults = .standard
    ) throws -> ShowCountdown {
        let item = try store.create(
            name: name,
            showId: showId,
            duration: duration,
            layout: layout,
            background: background,
            endAction: endAction
        )
        // Same memory the ⋯ Duration menu keeps, so the next Add starts here.
        defaults.set(item.duration, forKey: CountdownController.durationKey)
        return item
    }
}

@MainActor
extension CountdownDraft {

    /// Draft seeded from the live stores for a new countdown in `showId`.
    static func make(forShowId showId: UUID) -> CountdownDraft {
        CountdownDraft(
            showId: showId,
            name: CountdownStore.shared.nextDefaultName(inShowId: showId),
            duration: CountdownController.lastStoredDuration()
        )
    }
}
