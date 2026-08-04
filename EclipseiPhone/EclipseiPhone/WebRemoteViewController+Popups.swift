//
//  WebRemoteViewController+Popups.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit
import WebKit

// MARK: - WKUIDelegate (OAuth / window.open / media capture)

extension WebRemoteViewController: WKUIDelegate {

    /// Presents a phone-only sheet for `window.open` / `target=_blank`.
    ///
    /// AirPlay is not updated; login UI stays on the phone. Session cookies
    /// flow back to the main page via the shared default data store.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        WebPopupViewController.present(from: self, configuration: configuration)
    }

    /// Grants site mic/camera once Eclipse already has (or gets) system access.
    ///
    /// Without this, WebKit defaults to `.prompt` on every request — so reopen or a
    /// new warm `WKWebView` re-asks even after the user allowed Eclipse in Settings.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        guard origin.protocol == "https" else {
            decisionHandler(.deny)
            return
        }
        Task { @MainActor in
            let allowed = await Self.ensureSystemCaptureAccess(for: type)
            decisionHandler(allowed ? .grant : .deny)
        }
    }

    /// Requests AVFoundation access for the capture kinds `type` needs.
    private static func ensureSystemCaptureAccess(
        for type: WKMediaCaptureType
    ) async -> Bool {
        switch type {
        case .camera:
            return await requestAccess(for: .video)
        case .microphone:
            return await requestAccess(for: .audio)
        case .cameraAndMicrophone:
            let camera = await requestAccess(for: .video)
            let mic = await requestAccess(for: .audio)
            return camera && mic
        @unknown default:
            return false
        }
    }

    private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
