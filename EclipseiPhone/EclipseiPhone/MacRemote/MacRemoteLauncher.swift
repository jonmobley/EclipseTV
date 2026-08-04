//
//  MacRemoteLauncher.swift
//  Eclipse
//
//  Description: Presents the Mac remote flow from Settings or a deep link.
//  Thread Safety: Main thread only.
//

import UIKit

// MARK: - MacRemoteLauncher

/// Opens (or reuses) the full-screen Eclipse-for-Mac remote UI.
enum MacRemoteLauncher {

    private static weak var activeFlow: MacRemoteFlowViewController?

    /// Presents the Mac remote flow.
    /// - Parameters:
    ///   - connectString: Optional deep link / QR payload to auto-pair.
    ///   - presenter: View controller to present from; falls back to key window.
    @MainActor
    static func open(connectString: String? = nil, from presenter: UIViewController? = nil) {
        if let active = activeFlow {
            if let connectString {
                active.connect(with: connectString)
            }
            return
        }

        guard let host = presenter ?? topViewController() else { return }
        let flow = MacRemoteFlowViewController(initialConnectString: connectString)
        flow.modalPresentationStyle = .fullScreen
        activeFlow = flow
        host.present(flow, animated: true)
    }

    /// Clears the active-flow pointer when the sheet dismisses.
    @MainActor
    static func didDismiss(_ flow: MacRemoteFlowViewController) {
        if activeFlow === flow {
            activeFlow = nil
        }
    }

    // MARK: - Private Helpers

    @MainActor
    private static func topViewController(
        from root: UIViewController? = nil
    ) -> UIViewController? {
        let base = root
            ?? UIApplication.shared.connectedScenes
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
