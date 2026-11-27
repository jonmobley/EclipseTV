//
//  MacRemoteFlowViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import SwiftUI
import UIKit

// MARK: - MacRemoteFlowViewController

/// Finds Eclipse on a Mac, then shows the Mac's own remote page.
///
/// Opened from Settings → Connect to Mac or an `eclipse://mac-remote` QR / deep link.
final class MacRemoteFlowViewController: UIViewController {

    // MARK: - Properties

    private let model = MacRemoteConnectModel()
    private var connectHost: UIHostingController<ConnectView>?
    private var remote: MacRemoteWebViewController?
    private var pendingConnectString: String?

    // MARK: - Initialization

    /// - Parameter initialConnectString: Deep link / QR payload to open on appear.
    init(initialConnectString: String? = nil) {
        self.pendingConnectString = initialConnectString
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override var childForStatusBarStyle: UIViewController? { remote }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        model.onConnect = { [weak self] info in self?.showRemote(info) }
        embedConnectScreen()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let pending = pendingConnectString {
            pendingConnectString = nil
            connect(with: pending)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            MacRemoteLauncher.didDismiss(self)
        }
    }

    // MARK: - Public Interface

    /// Opens the Mac named by a fresh QR / deep-link payload.
    /// - Parameter raw: `eclipse://mac-remote…` or `http://…#t=…` string.
    func connect(with raw: String) {
        model.connect(scannedURL: raw)
    }

    // MARK: - Private Helpers

    private func embedConnectScreen() {
        let root = ConnectView(model: model) { [weak self] in
            self?.closeFlow()
        }
        let host = UIHostingController(rootView: root)
        connectHost = host
        embed(host)
    }

    /// Covers the connect screen with the Mac's remote page.
    private func showRemote(_ info: RemoteConnectInfo) {
        removeRemote()
        view.endEditing(true)
        let remote = MacRemoteWebViewController(info: info)
        // Back returns to the connect screen's caller, like Back on a Show.
        remote.onClose = { [weak self] in self?.closeFlow() }
        remote.onFailure = { [weak self] message in
            self?.removeRemote()
            self?.model.fail(message)
        }
        self.remote = remote
        embed(remote)
        setNeedsStatusBarAppearanceUpdate()
    }

    private func removeRemote() {
        guard let remote else { return }
        remote.willMove(toParent: nil)
        remote.view.removeFromSuperview()
        remote.removeFromParent()
        self.remote = nil
        setNeedsStatusBarAppearanceUpdate()
    }

    private func embed(_ child: UIViewController) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        child.didMove(toParent: self)
    }

    private func closeFlow() {
        MacRemoteLauncher.didDismiss(self)
        dismiss(animated: true)
    }
}
