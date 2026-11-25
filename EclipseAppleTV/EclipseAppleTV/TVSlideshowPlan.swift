//
//  TVSlideshowPlan.swift
//  EclipseTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Where a TV-run slideshow stands, and the rules for moving through it.
///
/// Built from a phone's `play_slideshow` message. Slides the TV does not have are
/// dropped up front, so every step lands on something it can show. Pure value:
/// the timer and the screen live in `TVSlideshowPlayer`.
///
/// Thread Safety: Value type; safe from any thread.
struct TVSlideshowPlan: Equatable {

    // MARK: - Properties

    /// Slide ids (TV library file names) in play order. Never empty.
    let slideIds: [String]
    /// Index of the slide on screen.
    private(set) var index: Int
    /// Seconds per slide; nil when the slideshow only moves when stepped.
    let seconds: TimeInterval?
    /// After the last slide, start again from the first.
    let loops: Bool
    /// Dissolve between slides (else cut).
    let crossfades: Bool

    /// Shortest slide time the TV accepts, so a bad value can't spin the timer.
    static let minimumSeconds: TimeInterval = 1

    // MARK: - Initialization

    /// Builds a plan from a phone's slideshow, keeping only slides the TV has.
    /// - Parameters:
    ///   - dto: The slideshow the phone sent.
    ///   - isAvailable: Whether the TV library holds a slide id.
    /// - Returns: nil when no slide can be shown.
    init?(dto: SlideshowDTO, isAvailable: (String) -> Bool) {
        let wanted = dto.slides.map(\.id)
        let startId = wanted.indices.contains(dto.startIndex) ? wanted[dto.startIndex] : nil
        let kept = wanted.filter(isAvailable)
        guard !kept.isEmpty else { return nil }
        slideIds = kept
        index = startId.flatMap { kept.firstIndex(of: $0) } ?? 0
        if let seconds = dto.seconds, seconds > 0 {
            self.seconds = max(seconds, Self.minimumSeconds)
        } else {
            self.seconds = nil
        }
        loops = dto.loops
        crossfades = dto.crossfades
    }

    // MARK: - Public Interface

    /// Id of the slide on screen.
    var currentId: String { slideIds[index] }

    /// Whether the TV should run a timer at all.
    var autoAdvances: Bool { seconds != nil && slideIds.count > 1 }

    /// The plan after the slide timer fires.
    /// - Returns: The next slide, wrapping when looping; nil at the end of a
    ///   non-looping slideshow (the last slide stays on screen).
    func advanced() -> TVSlideshowPlan? {
        var next = self
        if index + 1 < slideIds.count {
            next.index = index + 1
        } else if loops, slideIds.count > 1 {
            next.index = 0
        } else {
            return nil
        }
        return next
    }

    /// The plan after the phone asks for the slide `id`.
    /// - Parameter id: A slide id from this slideshow.
    /// - Returns: The plan on that slide, or nil when `id` is not a slide here.
    func jumped(toId id: String) -> TVSlideshowPlan? {
        guard let target = slideIds.firstIndex(of: id) else { return nil }
        var next = self
        next.index = target
        return next
    }

    /// The plan after a slide disappears from the TV library mid-run.
    /// - Parameter id: The id that is gone.
    /// - Returns: The plan without it, or nil when nothing is left.
    func removing(id: String) -> TVSlideshowPlan? {
        guard let gone = slideIds.firstIndex(of: id) else { return self }
        var ids = slideIds
        ids.remove(at: gone)
        guard !ids.isEmpty else { return nil }
        var newIndex = index
        if gone < index { newIndex -= 1 }
        if newIndex >= ids.count { newIndex = 0 }
        return TVSlideshowPlan(
            slideIds: ids, index: newIndex, seconds: seconds,
            loops: loops, crossfades: crossfades
        )
    }

    // MARK: - Private Helpers

    private init(
        slideIds: [String], index: Int, seconds: TimeInterval?,
        loops: Bool, crossfades: Bool
    ) {
        self.slideIds = slideIds
        self.index = index
        self.seconds = seconds
        self.loops = loops
        self.crossfades = crossfades
    }
}
