//
//  AudioQueueActions.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Play Next / Add to Queue / Remove from Up Next on Music song rows. Same words as
/// the Mac's song menu. Offered only while music is loaded (`canQueue`).
@MainActor
enum AudioQueueActions {

    static let playNextTitle = "Play Next"
    static let addToQueueTitle = "Add to Queue"
    static let removeFromUpNextTitle = "Remove from Up Next"

    static let playNextSymbol = "text.line.first.and.arrowtriangle.forward"
    static let addToQueueSymbol = "text.line.last.and.arrowtriangle.forward"

    /// Inline menu section for a song's press-and-hold menu, or `nil` when nothing is loaded.
    /// - Parameter host: Shows a short confirmation toast.
    static func menuSection(for trackId: UUID, host: UIViewController?) -> UIMenu? {
        let player = AudioPlayerController.shared
        guard player.canQueue else { return nil }
        let playNext = UIAction(
            title: playNextTitle,
            image: UIImage(systemName: playNextSymbol)
        ) { [weak host] _ in
            queueNext(trackId, host: host)
        }
        let second: UIAction
        if player.upNext.contains(trackId) {
            second = UIAction(
                title: removeFromUpNextTitle,
                image: UIImage(systemName: "minus.circle")
            ) { _ in
                AudioPlayerController.shared.removeFromUpNext(trackId)
            }
        } else {
            second = UIAction(
                title: addToQueueTitle,
                image: UIImage(systemName: addToQueueSymbol)
            ) { [weak host] _ in
                queueLast(trackId, host: host)
            }
        }
        return UIMenu(options: .displayInline, children: [playNext, second])
    }

    /// Leading swipe on a song row: Play Next and Add to Queue, or `nil` when nothing is loaded.
    static func leadingSwipe(
        for trackId: UUID,
        host: UIViewController?
    ) -> UISwipeActionsConfiguration? {
        guard AudioPlayerController.shared.canQueue else { return nil }
        let playNext = UIContextualAction(style: .normal, title: playNextTitle) {
            [weak host] _, _, done in
            queueNext(trackId, host: host)
            done(true)
        }
        playNext.image = UIImage(systemName: playNextSymbol)
        playNext.backgroundColor = .accent
        let addToQueue = UIContextualAction(style: .normal, title: addToQueueTitle) {
            [weak host] _, _, done in
            queueLast(trackId, host: host)
            done(true)
        }
        addToQueue.image = UIImage(systemName: addToQueueSymbol)
        addToQueue.backgroundColor = .systemOrange
        let config = UISwipeActionsConfiguration(actions: [playNext, addToQueue])
        // A full swipe should not queue a song by accident.
        config.performsFirstActionWithFullSwipe = false
        return config
    }

    private static func queueNext(_ trackId: UUID, host: UIViewController?) {
        AudioPlayerController.shared.playTrackNext(trackId)
        confirm("Playing Next", host: host)
    }

    private static func queueLast(_ trackId: UUID, host: UIViewController?) {
        AudioPlayerController.shared.addTrackToQueue(trackId)
        confirm("Added to Up Next", host: host)
    }

    private static func confirm(_ message: String, host: UIViewController?) {
        Haptics.impactLight()
        host?.showPresentationToast(message, duration: 1.4)
    }
}
