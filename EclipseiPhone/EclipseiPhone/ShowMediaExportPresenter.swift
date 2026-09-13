//
//  ShowMediaExportPresenter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension UIViewController {

    /// Packages a Show's media export and presents the system share sheet.
    ///
    /// - Parameters:
    ///   - showId: Show to export.
    ///   - source: Anchor view for the iPad popover.
    func presentShowMediaExport(forShowId showId: UUID, from source: UIView) {
        let progress = UIAlertController(
            title: nil,
            message: "Preparing export…",
            preferredStyle: .alert
        )
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        progress.view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerYAnchor.constraint(equalTo: progress.view.centerYAnchor),
            spinner.leadingAnchor.constraint(
                equalTo: progress.view.leadingAnchor, constant: 20
            )
        ])
        present(progress, animated: true)

        Task { @MainActor in
            do {
                let request = try ShowMediaExporter.makePackageRequest(
                    forShowId: showId
                )
                let zipURL = try await Task.detached(priority: .userInitiated) {
                    try ShowMediaExporter.writeZip(request)
                }.value
                progress.dismiss(animated: true) {
                    self.presentPreviewShareSheet(for: zipURL, from: source)
                }
            } catch {
                progress.dismiss(animated: true) {
                    self.presentExportFailure(error)
                }
            }
        }
    }

    // MARK: - Private

    private func presentExportFailure(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        let alert = UIAlertController(
            title: "Couldn't Export",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
