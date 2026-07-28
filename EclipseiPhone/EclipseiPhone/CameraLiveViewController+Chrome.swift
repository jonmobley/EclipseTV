//
//  CameraLiveViewController+Chrome.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Preview / Live Chrome

extension CameraLiveViewController {

    /// Builds Go Live + preview banner (called from `viewDidLoad`).
    func setupPreviewChrome() {
        var liveConfig = UIButton.Configuration.filled()
        liveConfig.title = "Go Live"
        liveConfig.image = UIImage(systemName: "play.fill")
        liveConfig.imagePadding = 8
        liveConfig.baseBackgroundColor = .systemRed
        liveConfig.baseForegroundColor = .white
        liveConfig.cornerStyle = .capsule
        liveConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 14, leading: 22, bottom: 14, trailing: 22
        )
        goLiveButton.configuration = liveConfig
        goLiveButton.translatesAutoresizingMaskIntoConstraints = false
        goLiveButton.accessibilityLabel = "Go Live"
        goLiveButton.addTarget(self, action: #selector(goLiveTapped), for: .touchUpInside)
        view.addSubview(goLiveButton)

        previewBanner.text = "Preview — not on TV"
        previewBanner.textColor = .white
        previewBanner.font = .systemFont(ofSize: 14, weight: .semibold)
        previewBanner.textAlignment = .center
        previewBanner.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        previewBanner.layer.cornerRadius = 10
        previewBanner.layer.masksToBounds = true
        previewBanner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewBanner)

        NSLayoutConstraint.activate([
            goLiveButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            goLiveButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24
            ),

            previewBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            previewBanner.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12
            ),
            previewBanner.heightAnchor.constraint(equalToConstant: 36),
            previewBanner.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            previewBanner.leadingAnchor.constraint(
                greaterThanOrEqualTo: stopButton.trailingAnchor, constant: 12
            ),
            previewBanner.trailingAnchor.constraint(
                lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12
            )
        ])
    }

    /// Updates Go Live / Stop / Logo chip / banner for preview vs AirPlay-live.
    func refreshLiveChrome() {
        let live = isAirPlayLive
        goLiveButton.isHidden = live
        previewBanner.isHidden = live
        stopButton.isHidden = !live
        logoChip.isHidden = !live
        if live {
            refreshLogoChip()
        }
    }

    /// Whether AirPlay currently owns the camera overlay (including Logo park).
    var isAirPlayLive: Bool {
        ExternalDisplayManager.shared.isCameraModeActive
    }

    @objc func goLiveTapped() {
        let mgr = ExternalDisplayManager.shared
        if mgr.isCameraParkedOnLogo {
            mgr.resumeCameraFromLogoPark()
        } else {
            mgr.presentCamera()
        }
        refreshLiveChrome()
        warnIfNoExternalDisplay()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
