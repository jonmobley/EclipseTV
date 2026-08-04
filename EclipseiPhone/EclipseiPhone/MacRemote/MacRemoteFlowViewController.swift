//
//  MacRemoteFlowViewController.swift
//  Eclipse
//
//  Description: UIKit host for the SwiftUI EclipsePro Mac remote flow.
//  Thread Safety: Main thread only.
//

import SwiftUI
import UIKit

// MARK: - MacRemoteFlowViewController

/// Presents connect + lean live control for Eclipse on Mac.
///
/// Invisible to the rest of the app until Settings → Eclipse for Mac or an
/// `eclipse://mac-remote` QR / deep link opens this controller.
final class MacRemoteFlowViewController: UIViewController {

    // MARK: - Properties

    private let session = RemoteSessionModel()
    private var hostingController: UIHostingController<MacRemoteRootView>?
    private var pendingConnectString: String?

    // MARK: - Initialization

    /// - Parameter initialConnectString: Deep link / QR payload to pair on appear.
    init(initialConnectString: String? = nil) {
        self.pendingConnectString = initialConnectString
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        embedRemoteRoot()
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

    /// Applies a fresh QR / deep-link payload to the active session.
    /// - Parameter raw: `eclipse://mac-remote…` or `http://…#t=…` string.
    func connect(with raw: String) {
        session.connect(scannedURL: raw)
    }

    // MARK: - Private Helpers

    private func embedRemoteRoot() {
        let root = MacRemoteRootView(session: session) { [weak self] in
            self?.closeFlow()
        }
        let host = UIHostingController(rootView: root)
        hostingController = host
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    private func closeFlow() {
        session.disconnect()
        MacRemoteLauncher.didDismiss(self)
        dismiss(animated: true)
    }
}
