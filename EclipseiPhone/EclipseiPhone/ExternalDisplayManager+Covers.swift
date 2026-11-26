//
//  ExternalDisplayManager+Covers.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Blank Colour and Freeze Covers

/// Views laid over the AirPlay / HDMI picture, above whatever is presented:
///
/// - **White cover**: Blackout on White. Program stays `.black` underneath, so
///   everything that asks "is Blackout on?" keeps working unchanged.
/// - **Freeze cover**: a still of the screen at the moment Freeze went on. A
///   library video is paused instead (a snapshot of a playing video can come
///   out black), and plays on from the same frame when Freeze ends.
///
/// Both live on the external window, so presents and transitions underneath
/// never draw over them.
extension ExternalDisplayManager {

    private static let whiteCoverTag = 7_301
    private static let freezeCoverTag = 7_302

    /// Freeze is holding the audience screen still.
    private(set) static var isFrozen = false
    /// Freeze paused a playing library video, so ending it plays on.
    private static var freezePausedVideo = false

    // MARK: White

    /// Puts the white cover up while Blackout is on White, and takes it down
    /// otherwise. Called after every present and when the colour changes.
    func applyBlankCover() {
        guard let window = externalWindow else { return }
        let wantsWhite = isBlankPresented && OutputBlankKind.current == .white
        let existing = window.viewWithTag(Self.whiteCoverTag)
        if !wantsWhite {
            existing?.removeFromSuperview()
            return
        }
        let cover = existing ?? makeCover(tag: Self.whiteCoverTag, in: window)
        cover.backgroundColor = OutputBlankKind.white.fillColor
        keepFreezeCoverOnTop(in: window)
    }

    // MARK: Freeze

    /// Holds the audience screen on what it shows now.
    func beginFreeze() {
        guard !Self.isFrozen else { return }
        Self.isFrozen = true
        Self.freezePausedVideo = false
        if presentationVC?.libraryVideoPlaybackState.isPlaying == true {
            Self.freezePausedVideo = presentationVC?.toggleLibraryVideoPlayback() == true
            return
        }
        guard let window = externalWindow, let still = snapshotStill() else { return }
        still.tag = Self.freezeCoverTag
        still.frame = window.bounds
        still.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        still.isUserInteractionEnabled = false
        window.addSubview(still)
    }

    /// Lets the audience screen move again; a paused video plays on.
    func endFreeze() {
        guard Self.isFrozen else { return }
        Self.isFrozen = false
        externalWindow?.viewWithTag(Self.freezeCoverTag)?.removeFromSuperview()
        if Self.freezePausedVideo,
           presentationVC?.libraryVideoPlaybackState.isPlaying == false {
            presentationVC?.toggleLibraryVideoPlayback()
        }
        Self.freezePausedVideo = false
    }

    // MARK: Private Helpers

    /// A still of the presented picture: the render server's copy first (it
    /// keeps camera and web layers), else the view drawn into an image.
    private func snapshotStill() -> UIView? {
        guard let view = presentationVC?.view else { return nil }
        if let copy = view.snapshotView(afterScreenUpdates: false) {
            copy.backgroundColor = .black
            return copy
        }
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        let imageView = UIImageView(image: image)
        imageView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        return imageView
    }

    private func makeCover(tag: Int, in window: UIWindow) -> UIView {
        let cover = UIView(frame: window.bounds)
        cover.tag = tag
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.isUserInteractionEnabled = false
        window.addSubview(cover)
        return cover
    }

    private func keepFreezeCoverOnTop(in window: UIWindow) {
        if let freeze = window.viewWithTag(Self.freezeCoverTag) {
            window.bringSubviewToFront(freeze)
        }
    }
}
