//
//  ConnectView.swift
//  Eclipse
//
//  Description: Host entry, PIN pairing, and QR scan for EclipsePro Mac remote.
//  Thread Safety: Main thread only — SwiftUI view.
//

import SwiftUI

// MARK: - ConnectView

/// First screen: type a Mac host or scan the Settings QR code.
///
/// Thread Safety: Main thread only.
struct ConnectView: View {
    @ObservedObject var session: RemoteSessionModel
    var onClose: () -> Void
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mac address", text: $session.hostText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Connect") { session.connectFromHostField() }
                        .disabled(session.phase == .connecting)
                } header: {
                    Text("Eclipse on your Mac")
                } footer: {
                    Text(
                        "Same Wi‑Fi as the Mac. Scan the QR in Eclipse → Settings "
                            + "→ Remote with Camera to jump here, or type the "
                            + "address / PIN below."
                    )
                }

                if session.phase == .needsPIN || !session.pinText.isEmpty {
                    Section("Pairing PIN") {
                        TextField("6-digit PIN", text: $session.pinText)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button("Pair") { session.submitPIN() }
                    }
                }

                Section {
                    Button("Scan QR Code") { showScanner = true }
                }

                if case .failed(let message) = session.phase {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }

                if session.phase == .connecting {
                    Section {
                        ProgressView("Connecting…")
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
                    session.connect(scannedURL: payload)
                }
            }
        }
    }
}
