//
//  PhoneCameraSendLauncher.swift
//  Eclipse
//
//  Description: Presents Send Camera to Mac from Settings or a deep link.
//  Thread Safety: Main thread only.
//

import SwiftUI
import UIKit

// MARK: - PhoneCameraSendLauncher

/// Opens the phone-camera → Mac streaming flow.
enum PhoneCameraSendLauncher {

    private static weak var activeHost: UIViewController?

    /// Presents the send-camera flow.
    /// - Parameters:
    ///   - connectString: Optional `eclipse://phone-camera…` QR payload.
    ///   - presenter: Host view controller; falls back to key window.
    @MainActor
    static func open(connectString: String? = nil, from presenter: UIViewController? = nil) {
        if activeHost != nil { return }
        guard let host = presenter ?? MacRemoteLauncherTop.topViewController() else { return }

        let root = PhoneCameraSendView(
            onClose: { [weak host] in
                host?.dismiss(animated: true)
                activeHost = nil
            },
            initialConnectString: connectString
        )
        let controller = UIHostingController(rootView: root)
        controller.modalPresentationStyle = .fullScreen
        activeHost = controller
        host.present(controller, animated: true)
    }
}

// MARK: - Top VC helper (shared shape with MacRemoteLauncher)

enum MacRemoteLauncherTop {
    @MainActor
    static func topViewController() -> UIViewController? {
        let base = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        guard let base else { return nil }
        var current = base
        while true {
            if let presented = current.presentedViewController {
                current = presented
                continue
            }
            if let nav = current as? UINavigationController,
               let visible = nav.visibleViewController {
                current = visible
                continue
            }
            if let tabs = current as? UITabBarController,
               let selected = tabs.selectedViewController {
                current = selected
                continue
            }
            return current
        }
    }
}
