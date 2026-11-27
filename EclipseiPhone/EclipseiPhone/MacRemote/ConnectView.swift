//
//  ConnectView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import SwiftUI

// MARK: - ConnectView

/// First screen: type a Mac address or scan the QR code from Eclipse on the Mac.
///
/// Thread Safety: Main thread only.
struct ConnectView: View {
    @ObservedObject var model: MacRemoteConnectModel
    var onClose: () -> Void
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Scan QR Code") { showScanner = true }
                } footer: {
                    Text(
                        "On the Mac, open Eclipse → Settings → Eclipse Remote "
                            + "and scan the code shown there."
                    )
                }

                Section {
                    TextField("Mac address", text: $model.hostText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit { model.connectFromHostField() }
                    Button("Connect") { model.connectFromHostField() }
                } header: {
                    Text("Or type the address")
                } footer: {
                    Text(
                        "Use the same Wi‑Fi as the Mac. You'll be asked for the "
                            + "6-digit PIN from the same Settings page."
                    )
                }

                if let failure = model.failure {
                    Section {
                        Text(failure)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Eclipse for Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { payload in
                    showScanner = false
                    model.connect(scannedURL: payload)
                }
            }
        }
    }
}
