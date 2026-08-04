//
//  ShowNamePrompt.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import ObjectiveC
import UIKit

extension UIViewController {

    /// Show create/rename alert with a live “Already taken” hint under the field.
    ///
    /// - Parameters:
    ///   - title: Alert title (`New Show` / `Rename Show`).
    ///   - initialName: Prefill for rename; omit for create.
    ///   - excludingId: Show being renamed (its current name is allowed).
    ///   - confirmTitle: Primary action title.
    ///   - onConfirm: Invoked with the trimmed name when Create/Save is tapped.
    func presentShowNamePrompt(
        title: String,
        initialName: String? = nil,
        excludingId: UUID? = nil,
        confirmTitle: String,
        onConfirm: @escaping (String) -> Void
    ) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Show name"
            field.text = initialName
            field.autocapitalizationType = .words
            field.clearButtonMode = .whileEditing
            field.enablesReturnKeyAutomatically = true
            UserDisplayName.configureTextField(field)
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        let confirm = UIAlertAction(title: confirmTitle, style: .default) { [weak alert] _ in
            let name = alert?.textFields?.first?.text ?? ""
            guard let trimmed = UserDisplayName.normalized(name) else { return }
            onConfirm(trimmed)
        }
        alert.addAction(confirm)

        let bridge = ShowNamePromptBridge(
            alert: alert,
            confirm: confirm,
            excludingId: excludingId
        )
        // Retain the bridge for the alert’s lifetime.
        objc_setAssociatedObject(
            alert,
            &ShowNamePromptBridge.assocKey,
            bridge,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        if let field = alert.textFields?.first {
            field.addTarget(
                bridge,
                action: #selector(ShowNamePromptBridge.editingChanged(_:)),
                for: .editingChanged
            )
            bridge.refresh(with: field.text ?? "")
        }
        present(alert, animated: true)
    }
}

// MARK: - Live validation

@MainActor
private final class ShowNamePromptBridge: NSObject {
    static var assocKey: UInt8 = 0

    private weak var alert: UIAlertController?
    private weak var confirm: UIAlertAction?
    private let excludingId: UUID?

    init(alert: UIAlertController, confirm: UIAlertAction, excludingId: UUID?) {
        self.alert = alert
        self.confirm = confirm
        self.excludingId = excludingId
    }

    @objc func editingChanged(_ field: UITextField) {
        refresh(with: field.text ?? "")
    }

    func refresh(with raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = !trimmed.isEmpty
            && LocalAlbumStore.shared.isNameTaken(trimmed, excluding: excludingId)
        alert?.message = taken ? "Already taken" : nil
        confirm?.isEnabled = UserDisplayName.normalized(raw) != nil && !taken
    }
}
