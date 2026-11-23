//
//  TVLibraryStore+CrossfadeLoop.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - Cross-Faded Loop

extension TVLibraryStore {

    /// Builds the blended loop for every looping video with Cross-Fade Loop on,
    /// so it plays without delay when it goes live (a few milliseconds per clip,
    /// each built once).
    func prepareCrossfadeLoops() {
        let urls = items
            .filter { $0.isVideo && $0.isLooping == true && $0.crossfadesLoop == true }
            .compactMap { LocalMediaStore.shared.localURL(forId: $0.id) }
            .filter { !CrossfadeLoopComposer.isPrepared($0) }
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            for url in urls {
                await CrossfadeLoopComposer.prepare(url)
            }
        }
    }
}
