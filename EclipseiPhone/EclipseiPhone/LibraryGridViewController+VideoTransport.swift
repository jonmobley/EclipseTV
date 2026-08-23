//
//  LibraryGridViewController+VideoTransport.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - Live Hero Video Remote

extension LibraryGridViewController {

    /// Play/pause: in-hero phone player, else AirPlay, and EclipseTV when linked.
    func handleLiveVideoPlayPause() {
        if liveHeader.toggleLibraryVideoPlayback() { return }
        let airPlay = ExternalDisplayManager.shared.toggleLibraryVideoPlayback()
        if store.isOnline {
            connectionManager.sendPlaybackCommand(action: .toggle, position: nil)
        }
        if airPlay { applyAirPlayVideoPlaybackToHero() }
    }

    /// Skip: in-hero phone player, else AirPlay, and EclipseTV when linked.
    func handleLiveVideoSkip(by delta: TimeInterval) {
        if liveHeader.skipLibraryVideo(by: delta) { return }
        let airPlay = ExternalDisplayManager.shared.skipLibraryVideo(by: delta)
        if store.isOnline {
            connectionManager.sendPlaybackCommand(action: .skip, position: delta)
        }
        if airPlay { applyAirPlayVideoPlaybackToHero() }
    }

    /// Seek: in-hero phone player, else AirPlay, and EclipseTV when linked.
    func handleLiveVideoSeek(to position: TimeInterval) {
        if liveHeader.seekLibraryVideo(to: position) { return }
        let airPlay = ExternalDisplayManager.shared.seekLibraryVideo(to: position)
        if store.isOnline {
            connectionManager.sendPlaybackCommand(action: .seek, position: position)
        }
        if airPlay { applyAirPlayVideoPlaybackToHero() }
    }

    /// Practice Mode plays in the hero; AirPlay / EclipseTV uses a black monitor.
    func applyLibraryVideoLiveHeader(item: LibraryItemDTO) {
        let mgr = ExternalDisplayManager.shared
        let phonePlays = LiveOutputRouting.phoneHeroPlaysLibraryVideo(
            airPlayConnected: mgr.isConnected,
            eclipseTVOnline: store.isOnline,
            practiceMode: prefersDisconnectedLivePreview
        )
        if phonePlays, let url = LocalMediaStore.shared.localURL(forId: item.id) {
            liveHeader.configure(
                with: item,
                thumbnail: nil,
                isOnline: store.isOnline,
                showsLocalTransport: true
            )
            let startAt = mgr.currentVideoPlaybackTime(forItemId: item.id)
                ?? mgr.lastPresentedVideoStartAt(forItemId: item.id)
            liveHeader.showLibraryVideoPreview(
                url: url,
                itemId: item.id,
                isMuted: item.isMuted ?? false,
                isLooping: item.isLooping ?? false,
                startAt: startAt
            )
            liveHeader.updatePlayback(liveHeader.libraryVideoPlaybackState)
            return
        }

        liveHeader.configure(
            with: item,
            thumbnail: nil,
            isOnline: store.isOnline,
            showsLocalTransport: mgr.isLibraryVideoLive || store.isOnline,
            usesRemoteVideoMonitor: true
        )
        liveHeader.clearLibraryVideoPreview()
        if mgr.isLibraryVideoLive {
            liveHeader.updatePlayback(mgr.libraryVideoPlaybackState)
        } else {
            liveHeader.updatePlayback(store.playback)
        }
    }

    /// Scrubber follows AirPlay when that player is live; otherwise EclipseTV state.
    func applyAirPlayVideoPlaybackToHero() {
        let mgr = ExternalDisplayManager.shared
        guard mgr.isLibraryVideoLive else { return }
        if !liveHeader.wantsPlaybackControls {
            refreshLiveHeader()
            return
        }
        liveHeader.updatePlayback(mgr.libraryVideoPlaybackState)
    }
}
