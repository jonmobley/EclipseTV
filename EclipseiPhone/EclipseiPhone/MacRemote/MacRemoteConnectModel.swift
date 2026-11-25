//
//  MacRemoteConnectModel.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Combine
import Foundation

// MARK: - MacRemoteConnectModel

/// State of the "find the Mac" screen: the typed address and why the last try failed.
///
/// It only works out *which* Mac to open. Signing in (link secret or PIN) and
/// everything after it belong to the Mac's own remote page.
///
/// Thread Safety: Main actor only.
@MainActor
final class MacRemoteConnectModel: ObservableObject {

    // MARK: - Properties

    @Published var hostText: String = "eclipse.local"
    /// Why the last try failed, in the owner's words; nil when there is nothing to say.
    @Published private(set) var failure: String?

    /// Called with a Mac on the local network to open.
    var onConnect: ((RemoteConnectInfo) -> Void)?

    // MARK: - Public Interface

    /// Opens the Mac at the typed address; its page asks for the PIN.
    func connectFromHostField() {
        guard let info = ConnectURLParser.parse(hostText) else {
            failure = "Enter the Mac's address, like eclipse.local or 192.168.1.10"
            return
        }
        open(info)
    }

    /// Opens the Mac named by a scanned QR code or an `eclipse://mac-remote` link.
    /// - Parameter raw: Full connect link, including its optional `#t=` secret.
    func connect(scannedURL raw: String) {
        guard let info = ConnectURLParser.parse(raw) else {
            failure = "That code isn't an Eclipse for Mac remote code"
            return
        }
        hostText = info.baseURL.absoluteString
        open(info)
    }

    /// Shows why the remote page could not be opened.
    func fail(_ message: String) {
        failure = message
    }

    // MARK: - Private Helpers

    private func open(_ info: RemoteConnectInfo) {
        failure = nil
        onConnect?(info)
    }
}
