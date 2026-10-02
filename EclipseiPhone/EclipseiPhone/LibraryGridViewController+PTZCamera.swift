//
//  LibraryGridViewController+PTZCamera.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CamTailKit
import SwiftUI
import UIKit

// MARK: - PTZ Camera Source

/// The network PTZ camera (OBSBOT Tail 2) as a Show source. Everything about the camera
/// itself — controls, tracking, presets, live NDI picture — comes from CamTailKit, which
/// the CamTail app shares, so both apps always have the same feature. This file only
/// places it in Eclipse: tile tap → program, hero tap → full-screen controls.
extension LibraryGridViewController {

    /// Tile tap: put the PTZ picture on program, or open the controls when it's already
    /// live (or there's no output to send it to, or this phone is a Show Live operator).
    func presentPTZCameraFromTile() {
        let mgr = ExternalDisplayManager.shared
        if mgr.isPTZCameraLive || prefersPhonePreviewOnTap || ShowLiveSession.shared.isRemoteOperator {
            Haptics.impactLight()
            presentPTZCameraControls()
            return
        }
        guard !blockLiveChangeIfLocked() else { return }
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = false
        SlideshowPlaybackController.shared.stop()
        mgr.presentPTZCamera()
        Haptics.impactLight()
        reloadLibraryGrid()
        refreshLiveHeader()
    }

    /// The full CamTail experience (steer, track, zoom, presets), full screen.
    func presentPTZCameraControls() {
        var controller: UIHostingController<CamTailScreen>?
        let screen = CamTailScreen(onClose: { controller?.dismiss(animated: true) })
        let host = UIHostingController(rootView: screen)
        controller = host
        host.modalPresentationStyle = .fullScreen
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black
        present(host, animated: true)
    }

    /// Hero while the PTZ camera is on program: its live picture; tap opens the controls.
    func presentPTZCameraInLiveHeader() {
        liveHeader.configureOverlay(
            title: "PTZ Camera",
            systemImage: "web.camera",
            fillColor: .mediaPlaceholder
        )
        liveHeader.showPTZPreview()
        liveHeader.allowsOverlayControllerTap = true
        liveHeader.updatePlayback(PlaybackState())
    }
}
