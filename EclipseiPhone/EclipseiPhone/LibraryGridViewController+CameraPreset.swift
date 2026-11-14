//
//  LibraryGridViewController+CameraPreset.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Camera Presets (camera + saved frame as a Show tile)

extension LibraryGridViewController {

    /// Camera Preset tap: put the camera on output wearing `frameId`.
    ///
    /// While the camera is already live, a tap swaps the frame in place; tapping the
    /// preset that is already live opens the viewfinder, like the Camera tile.
    ///
    /// - Parameter opensControllerWhenLive: False for an operator's command, which
    ///   must never pop a viewfinder on the director.
    func presentCameraPreset(frameId: UUID, opensControllerWhenLive: Bool = true) {
        let frames = CameraFrameStore.shared
        let isLive = ExternalDisplayManager.shared.isCameraTileLive
        if isLive, frames.selectedId == frameId {
            if opensControllerWhenLive {
                Haptics.impactLight()
                onPresentCamera?()
            }
            return
        }
        guard !blockLiveChangeIfLocked() else { return }
        if sendShowLiveSelectIfOperator(.camera, itemId: frameId.uuidString) {
            Haptics.impactLight()
            return
        }
        frames.select(frameId)
        guard frames.selectedId == frameId else {
            // Frames belong to one Display Mode; this one isn't in the current mode.
            Haptics.warning()
            showPresentationToast("This frame belongs to the other Display Mode")
            return
        }
        if isLive {
            Haptics.impactLight()
            return
        }
        presentCameraLiveOnOutput()
    }

    /// Takes a preset's frame off the camera so the plain Camera tile means the plain
    /// feed. A frame picked in the viewfinder (no preset) stays on.
    ///
    /// - Returns: false when the lock stops a change to what is on output.
    @discardableResult
    func clearCameraPresetFrameForPlainCamera() -> Bool {
        guard isCameraWearingPresetFrame else { return true }
        if ExternalDisplayManager.shared.isCameraTileLive, blockLiveChangeIfLocked() {
            return false
        }
        CameraFrameStore.shared.select(nil)
        return true
    }

    /// Whether the selected camera frame has a preset tile on the open Show.
    var isCameraWearingPresetFrame: Bool {
        guard let selected = CameraFrameStore.shared.selectedId else { return false }
        return cameraPresetFrameIds(for: .camera).contains(selected.uuidString)
    }

    // MARK: - Saving

    /// "Save as Camera Preset" submenu listing this Display Mode's frames, or nil
    /// outside a Show.
    func cameraPresetSaveMenu() -> UIMenuElement? {
        guard let show = openShow else { return nil }
        let title = "Save as Camera Preset"
        let image = UIImage(systemName: "plus.rectangle.on.rectangle")
        let frames = CameraFrameStore.shared.frames.sorted { $0.createdAt < $1.createdAt }
        guard !frames.isEmpty else {
            return UIAction(
                title: title,
                subtitle: "Add a frame in Camera Controls first",
                image: image,
                attributes: .disabled
            ) { _ in }
        }
        let saved = ShowCameraPresetToken.frameIds(in: show.surfaceIds ?? [])
        let selectedId = CameraFrameStore.shared.selectedId
        let actions = frames.enumerated().map { offset, frame -> UIAction in
            let isSaved = saved.contains(frame.id.uuidString)
            return UIAction(
                title: "Frame \(offset + 1)",
                subtitle: isSaved
                    ? "Already in this Show"
                    : (frame.id == selectedId ? "On the camera now" : nil),
                image: CameraFrameStore.shared.image(for: frame.id)?
                    .preparingThumbnail(of: CGSize(width: 96, height: 96)),
                attributes: isSaved ? .disabled : []
            ) { [weak self] _ in
                self?.saveCameraPreset(frameId: frame.id)
            }
        }
        return UIMenu(title: title, image: image, children: actions)
    }

    /// Adds a preset tile for `frameId` to the open Show.
    func saveCameraPreset(frameId: UUID) {
        guard let showId = openShowId else { return }
        guard LocalAlbumStore.shared.addCameraPreset(frameId: frameId, albumId: showId) else {
            showPresentationToast("Already in this Show")
            return
        }
        Haptics.success()
        showPresentationToast("Camera Preset added")
    }

    // MARK: - Frame Changes

    /// Keeps preset tiles and the live stroke in step with frame edits and picks.
    func installCameraPresetObservers() {
        observe(CameraFrameStore.didChangeNotification) { [weak self] _ in
            self?.cameraFramesDidChange()
        }
    }

    private func cameraFramesDidChange() {
        CameraPresetThumbnail.invalidate()
        guard isShowMode,
              let showsSection = sectionIndex(for: .shows),
              !ShowCameraPresetToken.frameIds(in: openShow?.surfaceIds ?? []).isEmpty
        else {
            return
        }
        let items = openShowGridItems
        let presetPaths = collectionView.indexPathsForVisibleItems.filter { path in
            guard path.section == showsSection, items.indices.contains(path.item),
                  case .cameraPreset = items[path.item] else { return false }
            return true
        }
        if !presetPaths.isEmpty {
            UIView.performWithoutAnimation {
                collectionView.reconfigureItems(at: presetPaths)
            }
        }
        // A frame swap moves the stroke between the Camera tile and its presets.
        syncVisibleShowTileLiveStrokes()
        broadcastShowLiveSnapshotIfNeeded()
    }
}
