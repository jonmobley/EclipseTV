//
//  AlreadyInShowAlert.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Confirm before adding library content that is already a Show member.
enum AlreadyInShowAlert {

    /// Alert title matching the Continue action.
    static let title = "Already in show. Continue?"

    /// True when any selected id is already on the Show.
    static func needsConfirmation(
        selectedIds: [String],
        memberIds: Set<String>
    ) -> Bool {
        selectedIds.contains { memberIds.contains($0) }
    }

    /// Presents Cancel / Continue. `onContinue` runs only if the user confirms.
    static func present(
        from viewController: UIViewController,
        onContinue: @escaping () -> Void
    ) {
        let alert = UIAlertController(
            title: title,
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
            onContinue()
        })
        viewController.present(alert, animated: true)
    }
}
