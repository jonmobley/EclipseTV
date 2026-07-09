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

    private func formatPairingPIN(_ pin: String) -> String {
        let normalized = PeerPairing.normalizePIN(pin)
        guard PeerPairing.isValidPIN(normalized) else { return pin }
        let mid = normalized.index(normalized.startIndex, offsetBy: 3)
        return "\(normalized[..<mid]) \(normalized[mid...])"
    }
}
