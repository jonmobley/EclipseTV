//
//  LibraryGridViewController+VideoEnd.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - When Video Ends

extension LibraryGridViewController {

    /// Runs the live video's "When Video Ends" choice once it has played out.
    func handleLiveVideoEnded() {
        guard let id = store.currentId,
              let item = store.items.first(where: { $0.id == id }), item.isVideo
        else { return }
        let decision = VideoEndDecision.decide(
            action: item.videoEndAction,
            isVideoLive: true,
            isRemoteOperator: ShowLiveSession.shared.isRemoteOperator,
            isOutputLocked: isLiveOutputLocked,
            isPhonePreview: heroPhonePreview != nil,
            isBlackoutHolding: isBlackoutHolding
        )
        switch decision {
        case .stay:
            break
        case .next:
            presentNextAfterVideo(videoId: id)
        case .screensaver:
            presentLiveUnattended(.screensaver)
            reloadGridIfSafe()
        }
    }

    /// First item after this video that can go live without a person.
    nonisolated static func itemAfterVideo(
        _ id: String,
        in items: [ShowGridItem]
    ) -> ShowGridItem? {
        guard let index = items.firstIndex(where: { $0.selectionId == id })
        else { return nil }
        return items.dropFirst(index + 1).first { $0.canAutoPresentLive }
    }

    // MARK: - Private

    /// Same ending as a countdown's Next: blank output when the Show runs out.
    private func presentNextAfterVideo(videoId: String) {
        guard let next = Self.itemAfterVideo(videoId, in: openShowGridItems) else {
            presentBlackAfterCountdown()
            return
        }
        presentLiveUnattended(next)
        reloadGridIfSafe()
    }
}
