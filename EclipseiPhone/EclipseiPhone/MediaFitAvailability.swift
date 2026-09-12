//
//  MediaFitAvailability.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Whether Fit and Fill are two different pictures for a given still.
///
/// `.scaleAspectFit` and `.scaleAspectFill` resolve to the same rectangle once the
/// source already shares the destination's shape, and the destination is always
/// exactly the Display Mode aspect — `ExternalOutputSettings.displayModePanelRect`
/// letterboxes the panel to it whatever the screen is, and opening a Show flips the
/// mode to that Show's orientation. So a still matching `MediaAspect.activeTarget`
/// looks identical either way, and the controls that switch between them are hidden
/// rather than left on screen doing nothing.
///
/// Vertical mode makes this the common case rather than a corner: imports are
/// force-cropped to 9:16 on the way in, so nearly every still in a Vertical Show
/// already matches.
enum MediaFitAvailability {

    /// Relative aspect slack treated as "the same shape".
    ///
    /// Deliberately tighter than `MediaAspect.matches`' own default, which decides
    /// whether to make the user crop on import — being generous there only skips a
    /// prompt. Here it takes a control away, so a still that is visibly off keeps it.
    static let tolerance: CGFloat = 0.01

    /// Whether Fit and Fill render differently for a still of `size`.
    static func fitDiffersFromFill(forSize size: CGSize) -> Bool {
        !MediaAspect.matches(size, target: MediaAspect.activeTarget, tolerance: tolerance)
    }

    /// Whether Fit and Fill render differently for the still `id`, or nil while its
    /// shape is unknown.
    ///
    /// Measured from the grid thumbnail, which is downsampled aspect-fit and so keeps
    /// the source ratio to well inside `tolerance`. Nil means the thumbnail has not
    /// been decoded yet; callers decide what an unknown shape costs them, since a
    /// missing menu row and a missing hero button are not the same mistake.
    @MainActor
    static func fitDiffersFromFill(forId id: String) -> Bool? {
        guard let size = TVLibraryStore.shared.thumbnail(for: id)?.size,
              size.width > 0, size.height > 0 else { return nil }
        return fitDiffersFromFill(forSize: size)
    }
}
