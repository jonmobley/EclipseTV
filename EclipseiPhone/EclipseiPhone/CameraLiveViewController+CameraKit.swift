//
//  CameraLiveViewController+CameraKit.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Camera Kit + Pictures Sheet

/// The Pictures button's sheet, the kit-aware frame ribbon, and the shared
/// "add a frame or picture" menu (also behind the stills ribbon's +).
extension CameraLiveViewController {

    // MARK: - Ribbon Entries

    /// What the phone can offer right now (kit only in Camera Mode).
    var pictureInputs: CameraPicturesSheetModel.Inputs {
        let kit = CameraKitStore.shared
        let inMode = isOperatorMode
        return CameraPicturesSheetModel.Inputs(
            showName: kit.showName,
            kitFrames: inMode ? kit.frames.map(\.id) : [],
            kitStills: inMode ? kit.stills.map(\.id) : [],
            ownFrames: CameraFrameStore.shared.enabledFrames.map(\.id),
            ownStills: CameraAlternateStillStore.shared.cutawayIds,
            showsOwn: !kit.hidesOwnPictures
        )
    }

    /// Frame ribbon tiles: kit frames, then own frames unless locked.
    var frameRibbonEntries: [CameraPictureEntry] {
        CameraPicturesSheetModel.frameRibbon(pictureInputs)
    }

    /// Thumbnail for any picture tile.
    func pictureImage(_ entry: CameraPictureEntry) -> UIImage? {
        switch entry {
        case .kitFrame(let id), .kitStill(let id): return CameraKitStore.shared.image(for: id)
        case .ownFrame(let id): return CameraFrameStore.shared.image(for: id)
        case .ownStill(let id): return CameraAlternateStillStore.shared.image(for: id)
        }
    }

    /// Whether a tile is on the camera / program now.
    func pictureIsLive(_ entry: CameraPictureEntry) -> Bool {
        switch entry {
        case .kitFrame(let id): return CameraKitStore.shared.selectedFrameId == id
        case .ownFrame(let id): return CameraFrameStore.shared.selectedId == id
        case .kitStill(let id), .ownStill(let id):
            return ExternalDisplayManager.shared.parkedCameraStill == .cutaway(id)
        }
    }

    /// Turns a frame on or off, or cuts to / back from a picture.
    func toggleFrameEntry(_ entry: CameraPictureEntry) {
        switch entry {
        case .kitFrame(let id):
            let kit = CameraKitStore.shared
            kit.selectFrame(kit.selectedFrameId == id ? nil : id)
            Haptics.impactLight()
        case .ownFrame(let id):
            toggleFrameOverlay(id)
        case .kitStill(let id), .ownStill(let id):
            handleStillRibbonItemTap(.cutaway(id))
        }
    }

    /// Kit pictures, rules or selection changed.
    @objc func cameraKitStoreChanged() {
        refreshFrameOverlay()
        reloadFrameRibbon()
        reloadStillRibbon()
        view.setNeedsLayout()
    }

    // MARK: - Pictures Sheet

    /// Opens the camera-roll style Pictures sheet.
    func presentPicturesSheet() {
        guard !isAlreadyOpen(CameraPicturesSheetViewController.self) else { return }
        let sheet = CameraPicturesSheetViewController(actions: .init(
            sections: { [weak self] in
                self.map { CameraPicturesSheetModel.sections($0.pictureInputs) } ?? []
            },
            image: { [weak self] in self?.pictureImage($0) },
            isLive: { [weak self] in self?.pictureIsLive($0) ?? false },
            select: { [weak self] in self?.toggleFrameEntry($0) },
            addMenu: { [weak self] in self?.pictureAddMenu() },
            editFrames: CameraKitStore.shared.hidesOwnPictures ? nil : { [weak self] in
                self?.dismiss(animated: true) { self?.presentFrameDrawer() }
            }
        ))
        let nav = UINavigationController(rootViewController: sheet)
        nav.modalPresentationStyle = .pageSheet
        if let controller = nav.sheetPresentationController {
            controller.detents = [.medium(), .large()]
            controller.prefersGrabberVisible = true
            controller.prefersEdgeAttachedInCompactHeight = true
        }
        present(nav, animated: true)
    }

    // MARK: - Adding

    /// Add Frame / Add Picture / From Eclipse Library, or nil when adding is off.
    func pictureAddMenu() -> UIMenu? {
        let ownRoom = CameraAlternateStillStore.shared.canAddStill
        guard CameraPictureAdding.canAdd(ownRoomLeft: ownRoom) else { return nil }
        let target = CameraPictureAdding.sendsToMac ? CameraKitStore.shared.showName : nil
        let frame = UIAction(title: "Frame from Photos", image: UIImage(systemName: "rectangle.dashed")) { [weak self] _ in
            self?.pickPhoto { CameraPictureAdding.addFrame($0) }
        }
        let picture = UIAction(title: "Picture from Photos", image: UIImage(systemName: "photo")) { [weak self] _ in
            self?.pickPhoto { [weak self] in self?.addPictureAndPark($0) }
        }
        let library = UIAction(title: "From Eclipse Library", image: UIImage(systemName: "photo.stack")) { [weak self] _ in
            self?.presentLibraryPicturePicker()
        }
        let title = target.map { "Adds to \($0) on the Mac" } ?? ""
        return UIMenu(title: title, children: [frame, picture, library])
    }

    /// Stills ribbon + in Camera Mode: the same menu, as an action sheet.
    /// - Parameter anchor: View to anchor the iPad popover on.
    func presentPictureAddMenu(from anchor: UIView?) {
        guard let menu = pictureAddMenu() else { return }
        let sheet = UIAlertController(title: nil, message: menu.title.isEmpty ? nil : menu.title,
                                      preferredStyle: .actionSheet)
        for case let action as UIAction in menu.children {
            sheet.addAction(UIAlertAction(title: action.title, style: .default) { _ in
                action.performWithSender(nil, target: nil)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = anchor ?? stillRibbonView
        topPresenter.present(sheet, animated: true)
    }

    // MARK: - Private Helpers

    /// The controller to present from (the Pictures sheet when it is open).
    private var topPresenter: UIViewController {
        var top: UIViewController = self
        while let next = top.presentedViewController { top = next }
        return top
    }

    private func pickPhoto(_ completion: @escaping @MainActor (UIImage) -> Void) {
        CameraPhotoPicker.present(from: topPresenter, completion: completion)
    }

    /// Adds a picture and, when it stays on the phone, refreshes the ribbon.
    private func addPictureAndPark(_ image: UIImage) {
        CameraPictureAdding.addStill(image)
        refreshLiveChrome()
    }

    /// Eclipse Library picker limited to images; each pick becomes a picture.
    private func presentLibraryPicturePicker() {
        let picker = MediaLibraryPickerViewController()
        picker.filter = .image
        // Add mode (multi-select + Add) without adding to any Show.
        picker.targetShowId = UUID()
        picker.onAddToShow = { [weak self] mediaIds, _ in
            for id in mediaIds {
                guard let url = LocalMediaStore.shared.localURL(forId: id),
                      let image = UIImage(contentsOfFile: url.path) else { continue }
                self?.addPictureAndPark(image)
            }
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        topPresenter.present(nav, animated: true)
    }
}
