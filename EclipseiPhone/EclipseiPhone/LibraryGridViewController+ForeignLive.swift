//
//  LibraryGridViewController+ForeignLive.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live From Another Show

/// When Show A is still live and the user opens Show B, AirPlay keeps playing A while
/// B's hero shows “Select item to go live.” A tucked mini preview carries A's live
/// art; tap returns to A. Going live from B replaces ownership and hides the mini.
extension LibraryGridViewController {

    /// Show that owns the current live media / website / PDF / slideshow, if any.
    /// Camera, Background, Screensaver, and Blackout are global tools (no owner).
    var liveOwningShowId: UUID? {
        let mgr = ExternalDisplayManager.shared
        if mgr.isCameraTileLive || isBlackSelected || isLogoSelected || isScreensaverSelected {
            return nil
        }
        if mgr.isWebLive, let pageId = mgr.liveWebPageId {
            return showIdOwning(memberId: pageId.uuidString)
        }
        if mgr.isPDFLive, let docId = mgr.livePDFDocumentId {
            return showIdOwning(memberId: docId.uuidString)
        }
        if let slideshowId = SlideshowPlaybackController.shared.activeSlideshowId,
           let show = SlideshowStore.shared.slideshow(id: slideshowId) {
            return show.showId
        }
        if let currentId = store.currentId, !mgr.isOverlayLive {
            return showIdOwning(memberId: currentId)
        }
        return nil
    }

    /// True when an open Show is viewing while live output still belongs to another.
    var isLiveFromOtherShow: Bool {
        guard isShowMode,
              let openShowId,
              let owning = liveOwningShowId else { return false }
        return owning != openShowId
    }

    /// Wires the foreign mini preview (added to the hierarchy only when shown).
    func installForeignLivePreview() {
        foreignLiveHeader.isHidden = true
        foreignLiveHeader.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleForeignLiveTap)
        )
        foreignLiveHeader.addGestureRecognizer(tap)
    }

    /// Configures or hides the tucked mini preview for foreign-show live.
    func refreshForeignLivePreview() {
        guard isLiveFromOtherShow else {
            hideForeignLivePreview()
            return
        }
        configureForeignLiveContent()
        foreignLiveHeader.isHidden = false
        foreignLiveHeader.setOutputLocked(isLiveOutputLocked)
        layoutForeignLivePreview()
        guard foreignLiveHeader.frame.width > 1 else { return }
        if foreignLiveHeader.superview == nil {
            view.addSubview(foreignLiveHeader)
        }
        view.bringSubviewToFront(foreignLiveHeader)

        let name = liveOwningShowId.flatMap {
            LocalAlbumStore.shared.album(id: $0)?.name
        } ?? "Show"
        foreignLiveHeader.accessibilityLabel = "Live on \(name)"
        foreignLiveHeader.accessibilityHint = "Double tap to return to that Show"
    }

    /// Positions the foreign mini in the compact hero slot (or a trailing fallback).
    func layoutForeignLivePreview() {
        guard !foreignLiveHeader.isHidden else { return }
        guard let rect = foreignLiveTargetRect() else { return }
        foreignLiveHeader.transform = .identity
        foreignLiveHeader.frame = rect
        // Compact chrome (progress 1): `applyInteractionForPresentation` only enables
        // taps when compact / transport / slideshow — progress 0 left the mini dead.
        foreignLiveHeader.applyCollapse(progress: 1, scale: 1)
        foreignLiveHeader.isUserInteractionEnabled = true
    }

    // MARK: - Private

    private func hideForeignLivePreview() {
        foreignLiveHeader.isHidden = true
        foreignLiveHeader.removeFromSuperview()
        foreignLiveHeader.clearWebPreview(parking: true)
        foreignLiveHeader.clearScreensaverPreview()
        foreignLiveHeader.clearCameraPreview()
    }

    /// Prefer the open Show when a member lives in more than one album.
    private func showIdOwning(memberId: String) -> UUID? {
        let matches = LocalAlbumStore.shared.albums.filter {
            $0.itemIds.contains(memberId)
        }
        if let openShowId, matches.contains(where: { $0.id == openShowId }) {
            return openShowId
        }
        return matches.first?.id
    }

    private func foreignLiveTargetRect() -> CGRect? {
        if let rect = compactHeroTargetRect() { return rect }
        let width = ExternalOutputSettings.isVerticalMode
            ? Self.compactHeroWidthVertical
            : Self.compactHeroWidthLandscape
        let height: CGFloat = ExternalOutputSettings.isVerticalMode
            ? (width * 16.0 / 9.0).rounded(.down)
            : (width * 9.0 / 16.0).rounded(.down)
        guard view.bounds.width > width + headerInset * 2 else { return nil }
        return CGRect(
            x: view.bounds.width - headerInset - width,
            y: view.safeAreaInsets.top + headerInset,
            width: width,
            height: height
        )
    }

    private func configureForeignLiveContent() {
        let mgr = ExternalDisplayManager.shared
        if mgr.isWebLive {
            let pageId = mgr.liveWebPageId
            let page = pageId.flatMap { WebPageStore.shared.page(id: $0) }
            let thumb = pageId.flatMap { WebThumbnailStore.shared.image(for: $0) }
            foreignLiveHeader.configureOverlay(
                title: page?.title ?? "Website",
                systemImage: "safari",
                fillColor: UIColor(white: 0.12, alpha: 1),
                thumbnail: thumb
            )
            pinForeignLiveChrome()
            return
        }
        if mgr.isPDFLive {
            let doc = PDFStore.shared.documents
                .first(where: { $0.id == mgr.livePDFDocumentId })
            let thumb = doc.flatMap { PDFThumbnailStore.shared.image(for: $0.id) }
            foreignLiveHeader.configureOverlay(
                title: doc?.title ?? "PDF",
                systemImage: "doc.richtext",
                fillColor: UIColor(white: 0.12, alpha: 1),
                thumbnail: thumb
            )
            pinForeignLiveChrome()
            return
        }

        let liveItem = store.currentId.flatMap { id in
            store.items.first(where: { $0.id == id })
        }
        let thumbnail = liveItem.flatMap { store.thumbnail(for: $0.id) }
        foreignLiveHeader.configure(
            with: liveItem,
            thumbnail: thumbnail,
            isOnline: store.isOnline
        )
        pinForeignLiveChrome()
    }

    /// Mini preview is art + LIVE only — no transport on the tucked card.
    private func pinForeignLiveChrome() {
        foreignLiveHeader.wantsPlaybackControls = false
        foreignLiveHeader.controls.isHidden = true
        foreignLiveHeader.gradientLayer.isHidden = true
        foreignLiveHeader.allowsSlideshowBrowse = false
        // progress 1 so collapse chrome keeps interaction on for the return tap.
        foreignLiveHeader.applyCollapse(progress: 1, scale: 1)
        foreignLiveHeader.isUserInteractionEnabled = true
    }

    @objc private func handleForeignLiveTap() {
        guard let id = liveOwningShowId else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        openLocalAlbum(id: id)
    }
}
