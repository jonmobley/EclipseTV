//
//  AddMusicDocumentPicker.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Files picker for importing audio; confirm control reads "Add" instead of "Open".
final class AddMusicDocumentPicker: UIDocumentPickerViewController {

    /// Creates a multi-select audio importer that copies files into the app.
    convenience init() {
        self.init(forOpeningContentTypes: AudioStore.importTypes, asCopy: true)
        allowsMultipleSelection = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyAddConfirmTitle(from: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyAddConfirmTitle(from: self)
    }

    // MARK: - Confirm title

    private func applyAddConfirmTitle(from root: UIViewController) {
        renameBarItems(on: root)
        renameButtons(in: root.view)
        root.children.forEach { applyAddConfirmTitle(from: $0) }
        if let presented = root.presentedViewController {
            applyAddConfirmTitle(from: presented)
        }
    }

    private func renameBarItems(on viewController: UIViewController) {
        let item = viewController.navigationItem
        var barItems: [UIBarButtonItem] = []
        if let left = item.leftBarButtonItem { barItems.append(left) }
        if let right = item.rightBarButtonItem { barItems.append(right) }
        barItems.append(contentsOf: item.leftBarButtonItems ?? [])
        barItems.append(contentsOf: item.rightBarButtonItems ?? [])
        for barItem in barItems where barItem.title == "Open" {
            barItem.title = "Add"
        }
    }

    private func renameButtons(in view: UIView) {
        if let button = view as? UIButton {
            if button.title(for: .normal) == "Open" {
                button.setTitle("Add", for: .normal)
            }
            if var config = button.configuration, config.title == "Open" {
                config.title = "Add"
                button.configuration = config
            }
        }
        view.subviews.forEach { renameButtons(in: $0) }
    }
}
