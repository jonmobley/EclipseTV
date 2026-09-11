//
//  CountdownDurationPrompt.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Custom Time alert shared by the ⋯ Duration menu, the live ribbon, and Add Countdown.
@MainActor
enum CountdownDurationPrompt {

    /// Presents Custom Time pre-filled with `seconds`; `onSet` gets the parsed length.
    ///
    /// Bad input explains itself and reopens the prompt rather than silently keeping
    /// the old length, so a typo never looks like it took.
    static func present(
        from host: UIViewController,
        seconds: Int,
        onSet: @escaping (Int) -> Void
    ) {
        let alert = UIAlertController(
            title: "Custom Time",
            message: "Minutes, m:ss, or h:mm:ss.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "7:30"
            field.text = CountdownController.displayString(seconds: seconds)
            field.keyboardType = .numbersAndPunctuation
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Set", style: .default) { [weak host] _ in
            let raw = alert.textFields?.first?.text ?? ""
            guard let parsed = CountdownController.parseDuration(raw) else {
                if let host {
                    presentInvalid(from: host, seconds: seconds, onSet: onSet)
                }
                return
            }
            onSet(parsed)
        })
        host.present(alert, animated: true)
    }

    // MARK: - Private

    private static func presentInvalid(
        from host: UIViewController,
        seconds: Int,
        onSet: @escaping (Int) -> Void
    ) {
        let alert = UIAlertController(
            title: "Couldn't Set Time",
            message: "Enter minutes, m:ss, or h:mm:ss — for example 7, 7:30, or 1:15:00.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak host] _ in
            guard let host else { return }
            present(from: host, seconds: seconds, onSet: onSet)
        })
        host.present(alert, animated: true)
    }
}
