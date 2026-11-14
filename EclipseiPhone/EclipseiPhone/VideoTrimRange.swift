//
//  VideoTrimRange.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CoreGraphics
import Foundation

/// The kept part of a video in the trimmer: a start and end within its length.
///
/// Edits clamp instead of failing, so a handle dragged past the other one (or off the
/// bar) stops where the rules allow and the kept part never gets shorter than
/// `minimumLength` (or the whole video, if that is shorter).
struct VideoTrimRange: Equatable {

    /// Shortest clip the trimmer keeps, in seconds.
    static let minimumLength: Double = 0.5

    /// Differences under this are treated as "not trimmed", so a handle nudged and put
    /// back doesn't rewrite the file.
    static let tolerance: Double = 0.05

    let duration: Double
    private(set) var start: Double
    private(set) var end: Double

    init(duration: Double) {
        let safe = duration.isFinite ? max(0, duration) : 0
        self.duration = safe
        self.start = 0
        self.end = safe
    }

    /// Length of the kept part.
    var length: Double { end - start }

    /// Shortest allowed kept part for this video.
    var effectiveMinimumLength: Double { min(Self.minimumLength, duration) }

    /// True when nothing would be cut.
    var isFullLength: Bool {
        start <= Self.tolerance && end >= duration - Self.tolerance
    }

    mutating func setStart(_ seconds: Double) {
        guard seconds.isFinite else { return }
        start = min(max(0, seconds), end - effectiveMinimumLength)
    }

    mutating func setEnd(_ seconds: Double) {
        guard seconds.isFinite else { return }
        end = max(min(duration, seconds), start + effectiveMinimumLength)
    }

    /// Puts both ends back to the whole video.
    mutating func reset() {
        start = 0
        end = duration
    }

    /// Keeps a time inside the kept part (for the playhead).
    func clamped(_ seconds: Double) -> Double {
        min(max(seconds, start), end)
    }

    /// Where a time sits along the video, 0...1.
    func fraction(of seconds: Double) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(seconds / duration, 0), 1))
    }

    /// The time at a point along the video, 0...1.
    func time(atFraction fraction: CGFloat) -> Double {
        Double(min(max(fraction, 0), 1)) * duration
    }

    /// "0:07.4", "1:02.0", "1:00:05.0": tenths so small trims are visible.
    static func label(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? max(0, seconds) : 0
        let tenths = Int((safe * 10).rounded())
        let totalSeconds = tenths / 10
        let tenth = tenths % 10
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, secs, tenth)
        }
        return String(format: "%d:%02d.%d", minutes, secs, tenth)
    }
}
