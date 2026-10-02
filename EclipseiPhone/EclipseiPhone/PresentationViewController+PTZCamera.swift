//
//  PresentationViewController+PTZCamera.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CamTailKit
import UIKit

// MARK: - PTZ Camera Presentation

extension PresentationViewController {

    /// Shows the network PTZ camera's live picture full screen on the external display.
    ///
    /// The view shares CamTailKit's one NDI stream with the phone's tile, hero and
    /// controls; it starts showing frames once it's in the window and stops when removed.
    func showPTZCamera() {
        hideCamera()
        hideWeb()
        hidePDF()
        hideMediaContainer()
        messageLabel.text = nil
        imageView.isHidden = true
        imageView.image = nil
        activityIndicator.stopAnimating()
        setIdleBrandVisible(false)

        if ptzCameraView == nil {
            let live = CamTailLiveVideoView()
            live.translatesAutoresizingMaskIntoConstraints = false
            live.isUserInteractionEnabled = false
            view.insertSubview(live, belowSubview: transitionOverlayContainer)
            NSLayoutConstraint.activate([
                live.topAnchor.constraint(equalTo: view.topAnchor),
                live.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                live.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                live.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            ptzCameraView = live
        }
        ptzCameraView?.isHidden = false
    }

    /// Removes the PTZ picture (detaching it from the stream).
    func hidePTZCamera() {
        ptzCameraView?.removeFromSuperview()
        ptzCameraView = nil
    }

    /// Transition layer for an incoming PTZ source: the same live picture, so the
    /// crossfade blends into motion rather than a frozen frame.
    func installIncomingPTZCamera(generation: Int) {
        let host = makeIncomingMediaHost()
        let live = CamTailLiveVideoView()
        live.translatesAutoresizingMaskIntoConstraints = false
        live.isUserInteractionEnabled = false
        host.addSubview(live)
        NSLayoutConstraint.activate([
            live.topAnchor.constraint(equalTo: host.topAnchor),
            live.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            live.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            live.trailingAnchor.constraint(equalTo: host.trailingAnchor)
        ])
        layoutIncomingMediaHost()
        notifyIfCurrent(generation)
    }
}
