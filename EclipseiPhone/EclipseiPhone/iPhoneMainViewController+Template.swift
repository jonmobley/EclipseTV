//
//  iPhoneMainViewController+Template.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Opens the "Template…" picker from the Show's + menu.
//  Thread Safety: Main thread only - UIKit.
//

import SwiftUI
import UIKit

// MARK: - Template Picker

extension iPhoneMainViewController {

    /// Template picker → field editor; Add appends the tile to this Show.
    ///
    /// - Parameter showId: The open Show that receives the new card.
    func addTemplate(toShowId showId: UUID) {
        guard !isAlreadyOpen(TemplatePickerHostingController.self) else { return }
        weak var host: UIViewController?
        let picker = TemplatePickerView(
            showId: showId,
            onAdded: { [weak self] cardId in
                host?.dismiss(animated: true)
                self?.libraryViewController.revealAddedShowMember(
                    id: ShowTemplateToken.token(for: cardId)
                )
            },
            onCancel: { host?.dismiss(animated: true) }
        )
        let controller = TemplatePickerHostingController(rootView: picker)
        controller.modalPresentationStyle = .formSheet
        host = controller
        presentationAnchor.present(controller, animated: true)
    }
}

// MARK: - TemplatePickerHostingController

/// Named host so a second tap on Template… does not stack another sheet.
final class TemplatePickerHostingController: UIHostingController<TemplatePickerView> {}
