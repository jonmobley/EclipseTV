//
//  PerformanceSignposts.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import os

/// Signposts for the paths people feel as slow, shown in Instruments → Points of Interest.
///
/// - `Thumbnail`: a grid thumbnail from request to decoded (one interval per id).
/// - `VideoPoster`: building a poster frame from a video file.
/// - `TapToPreview`: tapping a grid tile until the phone hero has repainted.
///
/// Signposts cost almost nothing when Instruments isn't recording, so they stay on in
/// Release builds; compare a device before and after a change with the same media.
enum PerformanceSignposts {
    static let signposter = OSSignposter(
        subsystem: "com.eclipseapp.ios",
        category: .pointsOfInterest
    )
}
