//
//  PhoneCameraSendView.swift
//  Eclipse
//
//  Description: Send this iPhone’s camera to EclipsePro on the Mac (LAN WebRTC).
//  Thread Safety: Main thread only — SwiftUI view.
//

import EclipsePhoneCameraClient
import SwiftUI

// MARK: - PhoneCameraSendView

/// Pair + stream UI for Mac phone-camera ingest (same protocol as the lite app).
struct PhoneCameraSendView: View {
    @StateObject private var session = PhoneCameraSessionController()
    var onClose: () -> Void
    var initialConnectString: String?
    @State private var showScanner = false
    @State private var didApplyInitial = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mac address", text: $session.hostText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Connect") { session.connectFromHostField() }
                        .disabled(
                            session.phase == .connecting || session.phase == .streaming
                        )
                } header: {
                    Text("Send Camera to Mac")
                } footer: {
                    Text(
                        "Same Wi‑Fi as Eclipse on Mac (guest/hotel networks "
                            + "often block phone↔Mac — try a Personal Hotspot). "
                            + "Scan the Phone Camera QR in Mac Connect, or "
                            + "type the address / PIN."
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
                    if session.phase == .streaming {
                        Button("Stop Streaming", role: .destructive) {
                            session.disconnect()
                        }
                    }
                }

                statusSection
            }
            .navigationTitle("Phone Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        session.disconnect()
                        onClose()
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                // Reuse Mac Remote QR scanner.
                QRScannerView { payload in
                    showScanner = false
                    session.connect(scannedURL: payload)
                }
            }
            .onAppear {
                guard !didApplyInitial, let initialConnectString else { return }
                didApplyInitial = true
                session.connect(scannedURL: initialConnectString)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch session.phase {
        case .idle:
            EmptyView()
        case .connecting:
            Section { ProgressView("Connecting…") }
        case .needsPIN:
            Section {
                Text("Enter the PIN shown on the Mac.")
                    .foregroundStyle(.secondary)
            }
        case .streaming:
            Section {
                Label("Streaming to Eclipse", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
            }
        case .failed(let message):
            Section { Text(message).foregroundStyle(.red) }
        }
    }
}
