//
//  HomeCameraTilePreview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

/// Owns the single `CameraPreviewView` behind the grid's Camera tile.
///
/// The grid rebuilds its cells whenever the live selection changes, so a preview owned
/// by the cell was unbound and rebound to the capture session on every tap. A freshly
/// bound `AVCaptureVideoPreviewLayer` renders black until it paints — that is the
/// tile's black blink. One long-lived view, re-parented into whichever cell hosts the
/// tile, keeps its session binding and its picture across reloads.
final class HomeCameraTilePreview {

    /// Shared instance — only one Camera tile exists at a time.
    static let shared = HomeCameraTilePreview()

    /// The preview view, or nil until the first Camera tile asks for one.
    private(set) var view: CameraPreviewView?

    /// True once the live picture has been revealed over a running session.
    private(set) var hasRevealedLivePicture = false

    /// Grace period before an unparented preview drops its session binding, so a
    /// reload that re-hosts the tile in another cell never has to rebind.
    private static let unbindGrace: TimeInterval = 0.3

    private var hostConstraints: [NSLayoutConstraint] = []
    private var pendingUnbind: DispatchWorkItem?

    private init() {}

    /// True while the preview is bound to a running session and already painting, so
    /// re-hosting it needs no freeze-frame cover.
    var isWarm: Bool {
        guard let view, view.videoPreviewLayer.session != nil else { return false }
        return hasRevealedLivePicture && CameraManager.shared.isSessionRunning
    }

    /// The preview when `container` currently hosts it, else nil.
    func hostedView(in container: UIView) -> CameraPreviewView? {
        guard let view, view.superview === container else { return nil }
        return view
    }

    /// Creates or re-parents the preview inside `container`, pinned to its edges.
    /// - Returns: The shared preview, ready for `attach(session:)`.
    @discardableResult
    func adopt(into container: UIView) -> CameraPreviewView {
        pendingUnbind?.cancel()
        pendingUnbind = nil

        let preview = view ?? makeView()
        guard preview.superview !== container else { return preview }

        NSLayoutConstraint.deactivate(hostConstraints)
        preview.removeFromSuperview()
        container.insertSubview(preview, at: 0)
        hostConstraints = [
            preview.topAnchor.constraint(equalTo: container.topAnchor),
            preview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            preview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ]
        NSLayoutConstraint.activate(hostConstraints)
        return preview
    }

    /// Unparents on cell reuse, holding the session binding briefly so a grid reload
    /// can re-host the tile without a black rebuild. Leaving the grid re-hosts nothing,
    /// so the binding — and the extra session client — goes away on its own.
    func relinquish() {
        guard let view else { return }
        NSLayoutConstraint.deactivate(hostConstraints)
        hostConstraints = []
        view.removeFromSuperview()

        pendingUnbind?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.view?.superview == nil else { return }
            self.unbind()
        }
        pendingUnbind = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.unbindGrace, execute: work)
    }

    /// Drops the session binding now — fullscreen Camera or AirPlay wants the feed.
    func unbind() {
        pendingUnbind?.cancel()
        pendingUnbind = nil
        hasRevealedLivePicture = false
        guard let view else { return }
        view.detach()
        NSLayoutConstraint.deactivate(hostConstraints)
        hostConstraints = []
        view.removeFromSuperview()
    }

    /// Records that the tile has faded its freeze-frame away over live video.
    func noteLivePictureRevealed() {
        hasRevealedLivePicture = true
    }

    // MARK: - Private

    private func makeView() -> CameraPreviewView {
        let created = CameraPreviewView()
        created.translatesAutoresizingMaskIntoConstraints = false
        view = created
        return created
    }
}
