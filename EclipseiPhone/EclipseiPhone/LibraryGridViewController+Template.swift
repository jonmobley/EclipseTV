//
//  LibraryGridViewController+Template.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Template card tiles in an open Show: the tile, its ⋯ menu,
//               and the tap that lays the card over (or takes it off) the
//               live picture.
//  Thread Safety: Main thread only - UIKit.
//

import SwiftUI
import UIKit

// MARK: - Template Tiles

extension LibraryGridViewController {

    // MARK: - Tile

    /// Paints a template tile: a 16:9 preview of the card where it sits on output.
    func configureTemplateTile(_ cell: LibraryThumbnailCell, card: ShowTemplateCard, isLive: Bool) {
        cell.configureSpecial(
            title: card.name,
            systemImage: ThumbnailTypeIcon.template.systemName,
            thumbnail: OverlayCardThumbnail.image(for: card.config),
            fillColor: .specialTile,
            isLive: isLive,
            thumbnailContentMode: .scaleAspectFill,
            typeIcon: .template
        )
        cell.accessibilityLabel = isLive
            ? "\(card.name), on screen, template"
            : "\(card.name), template"
        cell.accessibilityHint = isLive
            ? "Takes the template off the screen"
            : "Shows the template over what is live"
    }

    // MARK: - Tap

    /// Lays the card over whatever is live, or takes it off when it is on.
    ///
    /// Like the Mac, a template never replaces the live picture; several can be
    /// on at once. While Blackout is on the card is remembered but hidden.
    func toggleTemplateOverlay(_ card: ShowTemplateCard) {
        LiveOverlayController.shared.toggle(.template(card.id))
        Haptics.impactLight()
    }

    // MARK: - Menu

    /// ⋯ menu: show / take off, edit, arrange, select, delete.
    func templateContextMenu(_ card: ShowTemplateCard) -> UIMenu {
        let isOn = LiveOverlayController.shared.isLive(.template(card.id))
        let toggle = UIAction(
            title: isOn ? "Take Off Screen" : "Show on Screen",
            image: UIImage(systemName: isOn ? "eye.slash" : "eye")
        ) { [weak self] _ in
            self?.toggleTemplateOverlay(card)
        }
        let edit = UIAction(title: "Edit…", image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.presentTemplateEditor(card)
        }
        let delete = UIAction(
            title: "Delete Template",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmDeleteTemplate(card)
        }
        return UIMenu(children: [
            toggle,
            edit,
            arrangeAction(),
            selectAction(seedId: ShowTemplateToken.token(for: card.id)),
            delete
        ])
    }

    // MARK: - Editor

    /// Opens the field editor for an existing card; Save updates it everywhere.
    func presentTemplateEditor(_ card: ShowTemplateCard) {
        weak var host: UIViewController?
        let editor = TemplateEditorView(
            draft: TemplateCardDraft(editing: card),
            isNew: false,
            onCommit: { draft in
                TemplateCardStore.shared.update(id: card.id, config: draft.config, name: draft.name)
                host?.dismiss(animated: true)
            },
            onCancel: { host?.dismiss(animated: true) }
        )
        let controller = UIHostingController(rootView: NavigationStack { editor })
        controller.modalPresentationStyle = .formSheet
        host = controller
        present(controller, animated: true)
    }

    // MARK: - Private

    private func confirmDeleteTemplate(_ card: ShowTemplateCard) {
        let alert = UIAlertController(
            title: "Delete Template?",
            message: "“\(card.name)” is removed from this Show.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            TemplateCardStore.shared.delete(id: card.id)
        })
        present(alert, animated: true)
    }
}
