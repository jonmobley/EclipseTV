//
//  LibraryGridViewController+HeroPhonePreview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Hero Phone Preview (Lock / Blackout)

/// While Live Lock or Blackout holds the TV, a tile tap shows the item in the hero
/// on this phone only (see `HeroPhonePreview`). Nothing here ever reaches the TV.
extension LibraryGridViewController {

    /// Where a tile tap lands right now.
    var heroPhonePreviewTapSurface: HeroPhonePreview.TapSurface {
        HeroPhonePreview.tapSurface(
            isLiveOutputLocked: isLiveOutputLocked,
            isBlackoutHolding: isBlackoutHolding,
            hasOutputDestination: hasLiveOutputDestination,
            showsLiveHero: showsLiveHero && !isLiveFromOtherShow,
            isRemoteOperator: ShowLiveSession.shared.isRemoteOperator
        )
    }

    /// Whether a phone preview may stay in the hero at all.
    var allowsHeroPhonePreview: Bool {
        isShowMode && heroPhonePreviewTapSurface == .hero
    }

    /// Return button wording: what the hero goes back to.
    var heroPhonePreviewReturnTitle: String {
        isBlackoutHolding ? "Back to Blackout" : "Back to Live"
    }

    // MARK: Taps

    /// Handles a Show tile tap as a hero preview. True when it was handled.
    func handleShowTapForHeroPreview(_ item: ShowGridItem) -> Bool {
        guard allowsHeroPhonePreview, HeroPhonePreview.canPreview(item) else { return false }
        let action = HeroPhonePreview.tapAction(
            tappedId: item.selectionId,
            previewedId: heroPhonePreview?.selectionId,
            isLiveOrHeld: isLiveOrHeldForHeroPreview(item)
        )
        switch action {
        case .openFullscreen:
            presentFullscreenForHeroPhonePreview()
        case .backToLive:
            if heroPhonePreview != nil {
                Haptics.impactLight()
                clearHeroPhonePreview()
            } else {
                // The hero already shows this: the bigger view is the useful answer.
                presentPhoneFullscreen(for: item)
            }
        case .preview:
            showHeroPhonePreview(item)
        }
        return true
    }

    /// The tile is what the hero shows without a preview: program, or the item
    /// Blackout will bring back.
    func isLiveOrHeldForHeroPreview(_ item: ShowGridItem) -> Bool {
        if isBlackoutHolding {
            guard case .media(let media) = item else { return false }
            return media.id == blackoutHeldLibraryItem?.id
        }
        return isShowGridItemLive(item)
    }

    /// Puts `item` in the hero, phone only.
    func showHeroPhonePreview(_ item: ShowGridItem) {
        if heroPhonePreview == nil {
            rememberBlackoutScrubBeforePreview()
        }
        heroPhonePreview = item
        Haptics.impactLight()
        refreshLiveHeader()
    }

    /// Drops the preview and shows program again.
    func clearHeroPhonePreview() {
        guard heroPhonePreview != nil else { return }
        heroPhonePreview = nil
        refreshLiveHeader()
    }

    /// The held video's scrub lives in the hero's player, which a preview replaces.
    private func rememberBlackoutScrubBeforePreview() {
        guard isBlackoutHolding,
              let held = blackoutHeldLibraryItem, held.isVideo,
              liveHeader.libraryVideoItemId == held.id else { return }
        liveHeader.pauseLibraryVideoPreview()
        blackoutHeldScrubPosition = (
            held.id, liveHeader.libraryVideoPlaybackState.currentTime
        )
    }

    // MARK: Hero

    /// Paints the preview into the hero. False when there is nothing to preview.
    ///
    /// Called from `refreshLiveHeader`, which also drops a preview that Lock /
    /// Blackout no longer allows. The item is looked up again on every refresh so
    /// an edit or a removal from the Show is never shown stale.
    func applyHeroPhonePreviewHeaderIfNeeded() -> Bool {
        guard let previewed = heroPhonePreview else { return false }
        guard let key = previewed.selectionId,
              let item = openShowGridItems.first(where: { $0.selectionId == key }) else {
            heroPhonePreview = nil
            return false
        }
        heroPhonePreview = item
        switch item {
        case .media(let media):
            applyMediaHeroPhonePreview(media)
        case .website(let page):
            liveHeader.configureOverlay(
                title: page.title,
                systemImage: ThumbnailTypeIcon.website.systemName,
                fillColor: .mediaPlaceholder,
                thumbnail: WebThumbnailStore.shared.image(for: page.id),
                showsLiveBadge: true
            )
            liveHeader.allowsFullscreenTap = true
            liveHeader.updatePlayback(PlaybackState())
        case .pdf(let doc):
            let fileURL = PDFStore.shared.fileURL(for: doc.id)
            liveHeader.configureOverlay(
                title: doc.title,
                systemImage: ThumbnailTypeIcon.pdf.systemName,
                fillColor: .mediaPlaceholder,
                thumbnail: PDFThumbnailStore.shared.image(for: doc.id),
                keepPDFPreview: fileURL != nil,
                showsLiveBadge: true
            )
            // Readable in place; a private Preview never moves the TV.
            if let fileURL {
                liveHeader.showPDFPreview(documentId: doc.id, fileURL: fileURL, drivesOutput: false)
            }
            liveHeader.allowsFullscreenTap = true
            liveHeader.updatePlayback(PlaybackState())
        case .logo:
            liveHeader.configureOverlay(
                title: "Background",
                systemImage: "seal.fill",
                fillColor: .mediaPlaceholder,
                thumbnail: LogoStore.shared.image,
                showsLiveBadge: true
            )
            liveHeader.allowsFullscreenTap = true
            liveHeader.updatePlayback(PlaybackState())
        case .screensaver:
            presentScreensaverInLiveHeader()
            liveHeader.allowsFullscreenTap = true
        default:
            heroPhonePreview = nil
            return false
        }
        return true
    }

    /// Still, or a muted phone-only player for video that never drives the TV.
    private func applyMediaHeroPhonePreview(_ item: LibraryItemDTO) {
        let thumbnail = store.thumbnail(for: item.id)
        if item.isVideo, let url = LocalMediaStore.shared.localURL(forId: item.id) {
            liveHeader.configure(
                with: item,
                thumbnail: thumbnail,
                isOnline: store.isOnline,
                showsLocalTransport: true,
                showsLiveBadge: true
            )
            liveHeader.showLibraryVideoPreview(
                url: url,
                itemId: item.id,
                isMuted: true,
                isLooping: item.isLooping ?? false,
                autoplay: false
            )
            liveHeader.updatePlayback(liveHeader.libraryVideoPlaybackState)
            return
        }
        liveHeader.configure(
            with: item,
            thumbnail: thumbnail,
            isOnline: store.isOnline,
            allowsStillFullscreenTap: !item.isVideo,
            showsLiveBadge: true
        )
        liveHeader.clearLibraryVideoPreview()
        liveHeader.updatePlayback(PlaybackState())
    }

    // MARK: Fullscreen

    /// Opens the previewed item full screen, still phone only.
    ///
    /// Each presenter below already keeps Lock / Blackout off the TV.
    func presentFullscreenForHeroPhonePreview() {
        guard let item = heroPhonePreview else { return }
        presentPhoneFullscreen(for: item)
    }

    /// Phone-only fullscreen for a previewable tile (the pre-hero-preview tap).
    func presentPhoneFullscreen(for item: ShowGridItem) {
        switch item {
        case .media(let media):
            if media.isVideo, liveHeader.libraryVideoItemId == media.id,
               let url = LocalMediaStore.shared.localURL(forId: media.id) {
                let startAt = liveHeader.libraryVideoPlaybackState.currentTime
                liveHeader.pauseLibraryVideoPreview()
                presentLocalVideoPreview(
                    fileURL: url,
                    isMuted: media.isMuted ?? false,
                    isLooping: media.isLooping ?? false,
                    startAt: startAt
                ) { [weak self] position in
                    _ = self?.liveHeader.seekLibraryVideo(to: position)
                }
                return
            }
            presentLocalPreview(for: media, in: openShowItems)
        case .website(let page):
            presentWebPage(page)
        case .pdf(let doc):
            presentPDF(doc)
        case .logo:
            presentLogoPhonePreview()
        case .screensaver:
            presentScreensaverPhonePreview()
        default:
            break
        }
    }
}
