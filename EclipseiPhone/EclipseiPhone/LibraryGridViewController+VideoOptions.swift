//
//  LibraryGridViewController+VideoOptions.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Video ⋯ Menu (When Video Ends / Mute / Thumbnail)

extension LibraryGridViewController {

    /// When Video Ends, Mute, and Thumbnail actions for a video tile’s more menu.
    func videoOptionActions(for item: LibraryItemDTO) -> [UIMenuElement] {
        guard item.isVideo, item.isAvailable != false else { return [] }

        let endAction = item.videoEndAction
        let whenEnds = VideoEndAction.menu(current: endAction) { [weak self] choice in
            self?.applyVideoSetting(id: item.id, isLooping: nil, isMuted: nil, endAction: choice)
        }

        let muted = item.isMuted ?? false
        let mute = UIAction(
            title: "Mute",
            image: UIImage(systemName: muted ? "checkmark" : "speaker.wave.2.fill")
        ) { [weak self] _ in
            self?.applyVideoSetting(id: item.id, isLooping: nil, isMuted: !muted)
        }

        var actions: [UIMenuElement] = [whenEnds]
        // Only a looping video has a loop point to dissolve.
        if endAction == .loop {
            let crossfadeOn = item.crossfadesLoop ?? false
            actions.append(UIAction(
                title: "Cross-Fade Loop",
                image: UIImage(systemName: crossfadeOn ? "checkmark" : "circle.lefthalf.filled")
            ) { [weak self] _ in
                self?.applyVideoSetting(
                    id: item.id, isLooping: nil, isMuted: nil, crossfadesLoop: !crossfadeOn
                )
            })
        }
        actions.append(mute)

        if LocalMediaStore.shared.localURL(forId: item.id) != nil {
            let thumbnail = UIAction(
                title: "Choose Thumbnail…",
                image: UIImage(systemName: "photo.on.rectangle")
            ) { [weak self] _ in
                self?.onRequestVideoThumbnail?(item.id)
            }
            actions.append(thumbnail)
        }

        return actions
    }

    /// Persists loop/mute/cross-fade locally, syncs to EclipseTV when linked,
    /// refreshes AirPlay if live.
    func applyVideoSetting(
        id: String,
        isLooping: Bool?,
        isMuted: Bool?,
        crossfadesLoop: Bool? = nil,
        endAction: VideoEndAction? = nil
    ) {
        // The Apple TV only knows Loop on/off; iCloud carries the full choice too.
        let loopFlag = endAction.map { $0 == .loop } ?? isLooping
        store.updateVideoSetting(
            id: id, isLooping: endAction == nil ? isLooping : nil, isMuted: isMuted,
            crossfadesLoop: crossfadesLoop, endAction: endAction
        )
        EclipseSyncController.shared.backend.scheduleMediaPrefsSave(libraryId: id)
        Haptics.selection()
        _ = connectionManager.sendVideoSetting(
            id: id, isLooping: loopFlag, isMuted: isMuted, crossfadesLoop: crossfadesLoop
        )
        guard crossfadesLoop == true, let url = LocalMediaStore.shared.localURL(forId: id) else {
            refreshLiveVideoPresentationIfNeeded(id: id)
            return
        }
        // Build the blend first so the refreshed video plays it straight away.
        Task { @MainActor [weak self] in
            await CrossfadeLoopComposer.prepare(url)
            self?.refreshLiveVideoPresentationIfNeeded(id: id)
        }
    }

    /// Re-pushes the live video so AirPlay picks up new loop / mute / fit flags.
    ///
    /// Keeps the current playback position so the change does not restart from 0.
    func refreshLiveVideoPresentationIfNeeded(id: String) {
        guard store.currentId == id,
              let item = store.items.first(where: { $0.id == id }),
              item.isVideo else { return }
        if liveHeader.isLibraryVideoPreviewActive {
            refreshLiveHeader()
            return
        }
        let manager = ExternalDisplayManager.shared
        // Same projector signal as the go-live tap; `present` attaches on demand.
        guard LiveOutputRouting.projectorAvailable,
              !manager.isOverlayLive,
              !manager.isJoinedLive else { return }
        let startAt = manager.currentVideoPlaybackTime(forItemId: id) ?? 0
        manager.present(
            .forLibraryItem(item, thumbnail: store.thumbnail(for: id), startAt: startAt)
        )
    }
}
