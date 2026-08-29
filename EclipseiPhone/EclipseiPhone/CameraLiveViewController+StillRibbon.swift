//
//  CameraLiveViewController+StillRibbon.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import PhotosUI
import UIKit

// MARK: - Camera Stills Ribbon (Background / Quick Change)

extension CameraLiveViewController {

    /// Short side of in-panel still thumbs. Long side follows Display Mode.
    static let alternateStillThumbShortSide: CGFloat = 52

    /// Ribbon items: Background, quick-change stills, trailing +.
    var stillRibbonItems: [CameraStillRibbonItem] {
        let store = CameraAlternateStillStore.shared
        return CameraStillRibbon.items(
            cutawayIds: store.cutawayIds,
            canAdd: store.canAddStill
        )
    }

    /// Builds the stills ribbon (called from `viewDidLoad`).
    func setupStillRibbon() {
        stillRibbonView.dataSource = self
        stillRibbonView.delegate = self
        stillRibbonView.register(
            CameraStillRibbonCell.self,
            forCellWithReuseIdentifier: CameraStillRibbonCell.reuseId
        )
        view.addSubview(stillRibbonView)
        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(stillRibbonLongPressed(_:))
        )
        stillRibbonView.addGestureRecognizer(longPress)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stillRibbonStoreDidChange),
            name: CameraAlternateStillStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stillRibbonStoreDidChange),
            name: LogoStore.didChangeNotification,
            object: nil
        )
        reloadStillRibbon()
    }

    /// Packs the ribbon at the bottom-trailing corner of the Display Mode panel.
    func layoutStillRibbon(panel: CGRect) {
        let items = stillRibbonItems
        let thumb = stillRibbonThumbSize()
        applyStillRibbonItemSize(thumb)
        let gap: CGFloat = 8
        let inset = cameraThumbEdgeInset(panel: panel)
        let trailing = panel.maxX - inset
        let leadingMin = stillRibbonLeadingMinX(panel: panel, gap: gap)
        let count = CGFloat(max(items.count, 1))
        let contentWidth = count * thumb.width + max(0, count - 1) * gap
        let width = min(contentWidth, max(0, trailing - leadingMin))
        stillRibbonView.frame = CGRect(
            x: trailing - width,
            y: panel.maxY - inset - thumb.height,
            width: width,
            height: thumb.height
        )
        stillRibbonView.contentInset = .zero
        view.bringSubviewToFront(stillRibbonView)
    }

    /// Reloads ribbon thumbs after the library or parked still changes.
    func reloadStillRibbon() {
        stillRibbonView.reloadData()
        layoutStillRibbon(panel: panelView.convert(panelView.bounds, to: view))
    }

    /// 14pt in-panel pad, plus any home-indicator overlap (Landscape panel).
    func cameraThumbEdgeInset(panel: CGRect) -> CGFloat {
        let base: CGFloat = 14
        let safeBottom = view.bounds.maxY - view.safeAreaInsets.bottom
        return base + max(0, panel.maxY - safeBottom)
    }

    /// Hands Background off to the Show grid when Camera closes on that still.
    func commitParkedStillOnClose() {
        ExternalDisplayManager.shared.commitCameraParkToBackground()
    }

    // MARK: Tap / Park

    func handleStillRibbonTap(at indexPath: IndexPath) {
        let items = stillRibbonItems
        guard items.indices.contains(indexPath.item) else { return }
        switch items[indexPath.item] {
        case .add:
            presentStillPicker(replacing: nil)
        case .background:
            toggleParkedStill(
                source: LogoStore.shared.presentationSource,
                kind: .background
            )
        case .cutaway(let id):
            toggleParkedStill(
                source: CameraAlternateStillStore.shared.presentationSource(for: id),
                kind: .cutaway(id)
            )
        }
    }

    /// Parked on this still → resume camera. Otherwise go live (if needed) and park.
    func toggleParkedStill(source: PresentationSource?, kind: CameraParkedStill) {
        let mgr = ExternalDisplayManager.shared
        if mgr.parkedCameraStill == kind {
            mgr.resumeCameraFromStillPark()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            refreshLiveChrome()
            startAlwaysLiveRecordingIfNeeded()
            return
        }
        guard let source else {
            if case .cutaway(let id) = kind {
                presentStillPicker(replacing: id)
            }
            return
        }
        parkStillGoingLiveIfNeeded(source, kind: kind)
    }

    /// Recording belongs on the live camera feed — stop before cutaway.
    func parkStillGoingLiveIfNeeded(
        _ source: PresentationSource,
        kind: CameraParkedStill
    ) {
        let mgr = ExternalDisplayManager.shared
        if mgr.isCameraModeActive {
            finalizeRecordingIfNeeded { [weak self] in
                self?.parkStill(source, kind: kind)
            }
            return
        }
        if mgr.isConnected {
            prepareLivePreviewHandoffToAirPlay()
        }
        mgr.presentCamera()
        parkStill(source, kind: kind)
    }

    func parkStill(_ source: PresentationSource, kind: CameraParkedStill) {
        ExternalDisplayManager.shared.parkCameraOnStill(source, kind: kind)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        refreshLiveChrome()
    }
}

// MARK: - Picker / Long Press

extension CameraLiveViewController {

    @objc func stillRibbonStoreDidChange() {
        let mgr = ExternalDisplayManager.shared
        if case .cutaway(let id) = mgr.parkedCameraStill,
           !CameraAlternateStillStore.shared.contains(id) {
            mgr.resumeCameraFromStillPark()
        }
        reloadStillRibbon()
        refreshLiveChrome()
    }

    @objc func stillRibbonLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: stillRibbonView)
        guard let indexPath = stillRibbonView.indexPathForItem(at: point) else {
            return
        }
        let items = stillRibbonItems
        guard items.indices.contains(indexPath.item),
              case .cutaway(let id) = items[indexPath.item]
        else { return }
        presentCutawayActions(id: id, at: indexPath)
    }

    func presentCutawayActions(id: UUID, at indexPath: IndexPath) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let sheet = UIAlertController(
            title: "Quick Change", message: nil, preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Replace…", style: .default) { [weak self] _ in
            self?.presentStillPicker(replacing: id)
        })
        sheet.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            self?.removeCutaway(id)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController,
           let cell = stillRibbonView.cellForItem(at: indexPath) {
            pop.sourceView = cell
            pop.sourceRect = cell.bounds
        }
        present(sheet, animated: true)
    }

    func removeCutaway(_ id: UUID) {
        let mgr = ExternalDisplayManager.shared
        if mgr.parkedCameraStill == .cutaway(id) {
            mgr.resumeCameraFromStillPark()
            startAlwaysLiveRecordingIfNeeded()
        }
        CameraAlternateStillStore.shared.remove(id)
        refreshLiveChrome()
    }

    func presentStillPicker(replacing id: UUID?) {
        guard !isAlreadyOpen(PHPickerViewController.self) else { return }
        stillPickerReplaceId = id
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: Layout helpers

    func stillRibbonThumbSize() -> CGSize {
        let short = Self.alternateStillThumbShortSide
        let aspect = ExternalOutputSettings.orientation.aspectRatio
        let width = aspect >= 1 ? short * aspect : short
        return CGSize(width: width, height: width / aspect)
    }

    func applyStillRibbonItemSize(_ thumb: CGSize) {
        guard let layout = stillRibbonView.collectionViewLayout
            as? UICollectionViewFlowLayout else { return }
        layout.itemSize = thumb
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = 8
    }

    /// Ribbon may grow left to the program thumb, or the panel inset.
    func stillRibbonLeadingMinX(panel: CGRect, gap: CGFloat) -> CGFloat {
        if !liveOutputThumbView.isHidden, liveOutputThumbView.bounds.width > 1 {
            return liveOutputThumbView.frame.maxX + gap
        }
        return panel.minX + cameraThumbEdgeInset(panel: panel)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension CameraLiveViewController: PHPickerViewControllerDelegate {
    func picker(
        _ picker: PHPickerViewController,
        didFinishPicking results: [PHPickerResult]
    ) {
        picker.dismiss(animated: true)
        let replaceId = stillPickerReplaceId
        stillPickerReplaceId = nil
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            Task { @MainActor in
                self?.finishPickingStill(image, replacing: replaceId)
            }
        }
    }

    func finishPickingStill(_ image: UIImage, replacing id: UUID?) {
        guard let savedId = CameraAlternateStillStore.shared.save(
            image, replacing: id
        ) else { return }
        let mgr = ExternalDisplayManager.shared
        if mgr.parkedCameraStill == .cutaway(savedId),
           let source = CameraAlternateStillStore.shared.presentationSource(
            for: savedId
           ) {
            mgr.parkCameraOnStill(source, kind: .cutaway(savedId))
        }
        refreshLiveChrome()
    }
}
