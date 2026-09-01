//
//  ImageViewController+IdlePark.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - AirPlay Overlay Park

extension ImageViewController {

    /// Opaque fullscreen cover while the companion parks EclipseTV for an AirPlay overlay.
    private static var parkCoverTag: Int { 2_401 }

    /// Whether the companion has parked this TV (black cover on top of library).
    var isIdleParked: Bool {
        view.viewWithTag(Self.parkCoverTag) != nil
    }

    /// Parks on solid black (`true`) or clears park (`false`).
    func connectionManager(
        _ manager: ConnectionManager,
        didReceiveIdleModeBlack isBlack: Bool
    ) {
        if isBlack {
            applyIdleParkBlack()
        } else {
            clearIdlePark(restoreDisplay: true)
        }
    }

    /// Shows a solid black cover and stops any playing video under it.
    func applyIdleParkBlack() {
        guard !isIdleParked else { return }
        retireCurrentPlayer(stopBroadcasting: true)
        imageView.isHidden = true
        playerView.view.isHidden = true

        let cover = UIView()
        cover.backgroundColor = .black
        cover.tag = Self.parkCoverTag
        cover.isUserInteractionEnabled = false
        cover.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cover)
        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: view.topAnchor),
            cover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cover.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.bringSubviewToFront(cover)
        // Keep toast above park so reconnect / status can still be seen.
        view.bringSubviewToFront(toastView)
    }

    /// Removes the park cover. When `restoreDisplay` is true and we are still in
    /// fullscreen with a current item, re-shows that item; otherwise leaves grid alone.
    func clearIdlePark(restoreDisplay: Bool) {
        guard let cover = view.viewWithTag(Self.parkCoverTag) else { return }
        cover.removeFromSuperview()
        guard restoreDisplay, !isInGridMode, dataSource.getCurrentPath() != nil else { return }
        displayCurrentWithPreferredTransition()
    }

    /// Clears park before a companion play request so the chosen item is visible.
    func clearIdleParkForPlayRequest() {
        clearIdlePark(restoreDisplay: false)
    }
}
