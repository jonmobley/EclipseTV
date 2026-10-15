//
//  ImageViewController+Pairing.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Pairing PIN presentation

extension ImageViewController {

    /// Shows the current pairing PIN and offers to rotate it for a fresh code.
    func presentPairingCode() {
        let pin = connectionManager?.currentPairingPIN ?? PairedPeerStore.shared.currentPIN
        let formatted = formatPairingPIN(pin)
        let alert = UIAlertController(
            title: "Pairing Code",
            message: "On your iPhone, choose Connect and enter:\n\n\(formatted)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "New Code", style: .default) { [weak self] _ in
            let newPIN = self?.connectionManager?.rotatePairingPIN()
                ?? PairedPeerStore.shared.rotatePIN()
            self?.emptyStateView.setPairingCode(newPIN)
            self?.presentPairingCode()
        })
        alert.addAction(UIAlertAction(title: "Done", style: .cancel))
        present(alert, animated: true)
    }

    /// Keeps the on-screen code current when it changes after a pair or too many wrong tries.
    func observePairingPIN() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePairingPINChanged),
            name: .pairingPINDidChange,
            object: nil
        )
    }

    @objc private func handlePairingPINChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let pin = self.connectionManager?.currentPairingPIN else { return }
            self.emptyStateView.setPairingCode(pin)
        }
    }

    /// Asks before forgetting every paired iPhone.
    func confirmForgetPairedPhones() {
        let count = connectionManager?.pairedPhoneNames.count ?? 0
        let alert = UIAlertController(
            title: "Forget Paired iPhones?",
            message: count == 0
                ? "No iPhones are paired with this Apple TV."
                : "Every iPhone will need to enter the code on this screen to connect again.",
            preferredStyle: .alert
        )
        if count > 0 {
            alert.addAction(UIAlertAction(title: "Forget", style: .destructive) { [weak self] _ in
                self?.connectionManager?.forgetAllPairedPhones()
                self?.toastView.show(message: "Paired iPhones forgotten")
            })
        }
        alert.addAction(UIAlertAction(title: count == 0 ? "OK" : "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func formatPairingPIN(_ pin: String) -> String {
        let normalized = PeerPairing.normalizePIN(pin)
        guard PeerPairing.isValidPIN(normalized) else { return pin }
        let mid = normalized.index(normalized.startIndex, offsetBy: 3)
        return "\(normalized[..<mid]) \(normalized[mid...])"
    }
}
