// iPhoneMainViewController+Album.swift
import UIKit

// MARK: - Remote Album Setup

extension iPhoneMainViewController {

    /// Number of digits in an account code. Mirrors `AlbumConfig.codeLength` on the TV;
    /// the two targets don't share source, so the value is duplicated here.
    private static let accountCodeLength = 6

    /// Prompts for the account code and pushes it to the TV.
    ///
    /// The TV hardcodes the album host and composes the manifest URL from this code, so
    /// the user only ever enters a short code — never a full URL. The manifest returns
    /// all of the account's albums, so no per-album name is collected here.
    func presentSetUpAlbum() {
        guard isConnected() else {
            showAlert(title: "Not Connected",
                      message: "Connect to your Apple TV first, then set up your albums.")
            return
        }

        let alert = UIAlertController(
            title: "Set Up Albums",
            message: "Enter your \(Self.accountCodeLength)-digit account code. Your Apple TV will sync your albums.",
            preferredStyle: .alert)

        alert.addTextField { field in
            field.placeholder = String(repeating: "0", count: Self.accountCodeLength)
            field.keyboardType = .numberPad
            field.textContentType = .oneTimeCode
            field.clearButtonMode = .whileEditing
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Send to Apple TV", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let code = Self.normalizeCode(alert?.textFields?.first?.text ?? "")

            guard Self.isValidCode(code) else {
                self.showAlert(title: "Invalid Code",
                               message: "Enter your \(Self.accountCodeLength)-digit account code.")
                return
            }

            // Store locally so the phone's Albums browser uses it too, then push to the TV.
            AlbumBrowserStore.shared.setAccountCode(code)

            let sent = self.connectionManager.sendSetAccount(code: code)
            if sent {
                self.showTemporaryStatus("Account code sent to Apple TV")
            } else {
                self.showAlert(title: "Couldn't Send",
                               message: "Make sure your Apple TV is still connected and try again.")
            }
        })

        present(alert, animated: true)
    }

    /// Presents the album browser (modally, in its own navigation controller, like
    /// Settings). Works with or without a TV connection. When the user enters a code
    /// there, it's also pushed to the Apple TV if one is currently connected.
    func presentAlbums() {
        let albumsVC = AlbumsViewController()
        albumsVC.onCodeEntered = { [weak self] code in
            guard let self = self, self.isConnected() else { return }
            _ = self.connectionManager.sendSetAccount(code: code)
        }
        let nav = UINavigationController(rootViewController: albumsVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    /// Strips everything but digits from raw user input.
    private static func normalizeCode(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }

    /// Whether a normalized string is a valid account code (exactly `accountCodeLength` digits).
    private static func isValidCode(_ code: String) -> Bool {
        code.count == accountCodeLength && code.allSatisfy(\.isNumber)
    }
}
