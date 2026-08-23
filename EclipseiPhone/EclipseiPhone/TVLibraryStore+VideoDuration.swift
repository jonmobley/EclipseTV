//
//  TVLibraryStore+VideoDuration.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - Missing video duration backfill

extension TVLibraryStore {

    /// Reads file duration for videos persisted with `duration == 0`.
    func fillMissingVideoDurations() {
        let mode = activeLibraryMode
        let missing = items.filter { $0.isVideo && $0.duration <= 0 }
        guard !missing.isEmpty else { return }
        Task { @MainActor in
            var durations: [String: Double] = [:]
            for item in missing {
                guard let url = LocalMediaStore.shared.localURL(forId: item.id, mode: mode) else {
                    continue
                }
                let seconds = await VideoPosterFrame.durationSeconds(at: url)
                if seconds > 0.05 { durations[item.id] = seconds }
            }
            applyVideoDurations(durations)
        }
    }
}
