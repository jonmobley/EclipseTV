//
//  LibraryGridViewController+VideoOptions.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Video ⋯ Menu (Loop / Mute / Thumbnail)

extension LibraryGridViewController {

    /// Loop, Mute, and Thumbnail actions for a video tile’s more menu.
    func videoOptionActions(for item: LibraryItemDTO) -> [UIMenuElement] {
        guard item.isVideo, item.isAvailable != false else { return [] }

        let loopOn = item.isLooping ?? false
        let loop = UIAction(
            title: "Loop",
            image: UIImage(systemName: "repeat"),
            state: loopOn ? .on : .off
        ) { [weak self] _ in
            self?.applyVideoSetting(id: item.id, isLooping: !loopOn, isMuted: nil)
        }

        let muted = item.isMuted ?? false
        let mute = UIAction(
            title: "Mute",
            image: UIImage(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill"),
            state: muted ? .on : .off
        ) { [weak self] _ in
            self?.applyVideoSetting(id: item.id, isLooping: nil, isMuted: !muted)
        }

        var actions: [UIMenuElement] = [loop, mute]

        if LocalMediaStore.shared.localURL(forId: item.id) != nil {
            let thumbnail = UIAction(
                title: "Thumbnail",
                image: UIImage(systemName: "photo.on.rectangle")
            ) { [weak self] _ in
                self?.onRequestVideoThumbnail?(item.id)
            }
            actions.append(thumbnail)
        }

        return actions
    }

    /// Persists loop/mute locally, syncs to EclipseTV when linked, refreshes AirPlay if live.
    func applyVideoSetting(id: String, isLooping: Bool?, isMuted: Bool?) {
        store.updateVideoSetting(id: id, isLooping: isLooping, isMuted: isMuted)
        UISelectionFeedbackGenerator().selectionChanged()
        _ = connectionManager.sendVideoSetting(
            id: id, isLooping: isLooping, isMuted: isMuted
        )
        refreshLiveVideoPresentationIfNeeded(id: id)
    }

    /// Re-pushes the live video so AirPlay picks up new loop / mute flags.
    private func refreshLiveVideoPresentationIfNeeded(id: String) {
        guard store.currentId == id,
              let item = store.items.first(where: { $0.id == id }),
              item.isVideo else { return }
        let manager = ExternalDisplayManager.shared
        guard manager.isConnected,
              !manager.isOverlayLive,
              !manager.isJoinedLive else { return }
        manager.present(
            .forLibraryItem(item, thumbnail: store.thumbnail(for: id))
        )
    }
}
