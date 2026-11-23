//
//  LibraryGridViewController+CameraRibbon.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// One thumbnail in the camera ribbon under the live camera hero.
enum GridCameraRibbonItem: Equatable {
    /// A camera frame overlay (tap puts it on / takes it off the camera).
    case frame(UUID)
    /// The Show Background still (tap cuts to it / back to the camera).
    case background
    /// A quick-change still (tap cuts to it / back to the camera).
    case cutaway(UUID)

    /// Frames first, then Background (only when the Show has one), then quick changes:
    /// the same thumbnails as the full-screen camera, minus its + tile.
    static func items(
        frameIds: [UUID],
        hasBackground: Bool,
        cutawayIds: [UUID]
    ) -> [GridCameraRibbonItem] {
        var items = frameIds.map { GridCameraRibbonItem.frame($0) }
        if hasBackground { items.append(.background) }
        items.append(contentsOf: cutawayIds.map { .cutaway($0) })
        return items
    }

    /// What VoiceOver adds after the name: frames say On / Off (the ON badge is
    /// visual only), like the full-screen camera's ribbon. Stills say nothing extra.
    func spokenState(selectedFrameId: UUID?) -> String? {
        guard case .frame(let id) = self else { return nil }
        return selectedFrameId == id ? "On" : "Off"
    }
}

// MARK: - Live camera ribbon + capture on the Show screen

/// While the phone camera owns the hero, the docked ribbon under it carries the camera's
/// frames and stills, and the hero gets Take Photo / Record, so the operator can run the
/// camera without opening the full-screen view (2026-11-15).
extension LibraryGridViewController {

    private static let recordingAudioOwner = "showHero"

    /// The live phone camera (or one of its parked stills) owns this Show's hero.
    var isLiveCameraHero: Bool {
        isShowMode
            && showsLiveHero
            && !isLiveFromOtherShow
            && !ShowLiveSession.shared.isRemoteOperator
            && ExternalDisplayManager.shared.isCameraModeActive
    }

    var cameraRibbonItems: [GridCameraRibbonItem] {
        GridCameraRibbonItem.items(
            frameIds: CameraFrameStore.shared.enabledFrames.map(\.id),
            hasBackground: LogoStore.shared.image != nil,
            cutawayIds: CameraAlternateStillStore.shared.cutawayIds
        )
    }

    /// The docked ribbon shows the camera's thumbnails (none to show, no ribbon).
    var showsCameraRibbon: Bool {
        isLiveCameraHero && !cameraRibbonItems.isEmpty
    }

    func cameraRibbonItemCount() -> Int {
        showsCameraRibbon ? cameraRibbonItems.count : 0
    }

    func configureCameraRibbonCell(_ cell: LibraryThumbnailCell, at indexPath: IndexPath) {
        let items = cameraRibbonItems
        guard items.indices.contains(indexPath.item) else { return }
        let parked = ExternalDisplayManager.shared.parkedCameraStill
        let item = items[indexPath.item]
        let image: UIImage?
        let name: String
        let isLive: Bool
        switch item {
        case .frame(let id):
            image = CameraFrameStore.shared.image(for: id)
            name = CameraFrameStore.shared.displayName(for: id)
            // A frame is a layer on the camera, not what the TV shows: ON badge, never blue.
            isLive = false
        case .background:
            image = LogoStore.shared.image
            name = "Background"
            isLive = parked == .background
        case .cutaway(let id):
            image = CameraAlternateStillStore.shared.image(for: id)
            name = "Quick Change"
            isLive = parked == .cutaway(id)
        }
        cell.configure(
            with: LibraryItemDTO(
                id: "camera-ribbon-\(indexPath.item)",
                name: name,
                isVideo: false,
                duration: 0,
                isAvailable: true
            ),
            thumbnail: image,
            isLive: isLive,
            showsTypeIcon: false
        )
        let selectedFrameId = CameraFrameStore.shared.selectedId
        if case .frame(let id) = item {
            cell.setFrameOn(selectedFrameId == id)
        } else {
            cell.setFrameOn(false)
        }
        cell.accessibilityValue = item.spokenState(selectedFrameId: selectedFrameId)
    }

    /// Frames toggle on the camera; stills cut to the still, or back to the camera.
    func handleCameraRibbonTap(at indexPath: IndexPath) {
        let items = cameraRibbonItems
        guard items.indices.contains(indexPath.item) else { return }
        let mgr = ExternalDisplayManager.shared
        switch items[indexPath.item] {
        case .frame(let id):
            let store = CameraFrameStore.shared
            store.select(store.selectedId == id ? nil : id)
            Haptics.impactLight()
        case .background:
            toggleCameraStillPark(LogoStore.shared.presentationSource, kind: .background)
        case .cutaway(let id):
            toggleCameraStillPark(
                mgr.parkedCameraStill == .cutaway(id)
                    ? nil
                    : CameraAlternateStillStore.shared.presentationSource(for: id),
                kind: .cutaway(id)
            )
        }
    }

    /// Show-screen half of the camera chrome: capture buttons, the mic, ribbon highlights.
    /// Runs from every live-header refresh.
    func syncLiveCameraCaptureChrome() {
        let visible = isLiveCameraHero
        // Capture buttons belong to the camera picture, not a phone preview over it.
        liveHeader.setCameraCaptureVisible(
            visible && heroPhonePreview == nil, isRecording: CameraManager.shared.isRecording
        )
        // Mic on while capture is a tap away, so Record / Stop don't blip other apps' music.
        if visible {
            CameraManager.shared.armRecordingAudio(owner: Self.recordingAudioOwner)
        } else {
            CameraManager.shared.disarmRecordingAudio(owner: Self.recordingAudioOwner)
        }
        if showsCameraRibbon {
            reloadDockedRibbonThumbsInPlace()
        }
    }

    /// Thumbnails changed (frames, stills, Background): rebuild the ribbon.
    func installCameraRibbonObservers() {
        for name in [
            CameraFrameStore.didChangeNotification,
            CameraAlternateStillStore.didChangeNotification,
            LogoStore.didChangeNotification
        ] {
            observe(name) { [weak self] _ in
                guard let self, self.isShowMode else { return }
                self.refreshSlideshowRibbonPresentation()
                self.syncLiveCameraCaptureChrome()
            }
        }
        observe(CameraManager.recordingDidChangeNotification) { [weak self] _ in
            self?.syncLiveCameraCaptureChrome()
        }
    }

    // MARK: Capture

    /// Hero Take Photo: saves to Photos and to this Show, like the full-screen shutter.
    func takeLiveCameraPhoto() {
        resumeCameraIfParked()
        liveHeader.playCameraShutterBlink()
        Haptics.impactLight()
        let showId = openShowId
        CameraManager.shared.capturePhotoToLibrary { [weak self] result in
            switch result {
            case .success(let image):
                CameraCaptureFiling.fileStill(image, showId: showId)
                Haptics.success()
                self?.showPresentationToast("Photo saved")
            case .failure(let error):
                self?.showCameraCaptureError(error)
            }
        }
    }

    /// Hero Record / Stop.
    func toggleLiveCameraRecording() {
        if CameraManager.shared.isRecording {
            stopLiveCameraRecording(completion: nil)
            return
        }
        resumeCameraIfParked()
        Haptics.impactHeavy()
        CameraManager.shared.startRecording { [weak self] result in
            self?.syncLiveCameraCaptureChrome()
            if case .failure(let error) = result {
                self?.showCameraCaptureError(error)
            }
        }
    }

    // MARK: Private

    /// Stops a movie and files it in Photos and this Show.
    private func stopLiveCameraRecording(completion: (() -> Void)?) {
        let showId = openShowId
        CameraManager.shared.stopRecording { [weak self] result in
            self?.syncLiveCameraCaptureChrome()
            switch result {
            case .success(let previewURL):
                if let previewURL {
                    CameraCaptureFiling.fileMovie(at: previewURL, duration: 0, showId: showId)
                }
                Haptics.success()
                self?.showPresentationToast("Video saved")
            case .failure(let error):
                self?.showCameraCaptureError(error)
            }
            completion?()
        }
    }

    /// Parked on `kind` → back to the camera; otherwise cut to the still. A movie stops
    /// first: recording belongs to the live camera feed.
    private func toggleCameraStillPark(_ source: PresentationSource?, kind: CameraParkedStill) {
        let mgr = ExternalDisplayManager.shared
        if mgr.parkedCameraStill == kind {
            mgr.resumeCameraFromStillPark()
            Haptics.impactMedium()
            return
        }
        guard let source else { return }
        let park = {
            mgr.parkCameraOnStill(source, kind: kind)
            Haptics.impactMedium()
        }
        if CameraManager.shared.isRecording {
            stopLiveCameraRecording(completion: park)
        } else {
            park()
        }
    }

    private func resumeCameraIfParked() {
        let mgr = ExternalDisplayManager.shared
        guard mgr.isCameraParkedOnStill else { return }
        mgr.resumeCameraFromStillPark()
    }

    private func showCameraCaptureError(_ error: Error) {
        let alert = UIAlertController(
            title: "Capture Failed",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
