//
//  CameraLiveViewController+SavePreset.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Save Preset (header button) and frame ⋯ menu

extension CameraLiveViewController {

    /// The Show Camera was opened from, where a Camera Preset tile goes (`nil` otherwise).
    var presetDestinationShow: LocalAlbum? {
        captureDestinationShowId.flatMap { LocalAlbumStore.shared.album(id: $0) }
    }

    /// Whether `frameId` is already a Camera Preset in `show`.
    func isCameraPreset(_ frameId: UUID, in show: LocalAlbum) -> Bool {
        show.surfaceIds?.contains(ShowCameraPresetToken.token(for: frameId)) == true
    }

    /// Header bookmark, left of the gear. Shown only while a frame is on the camera and
    /// Camera was opened from a Show.
    static func showsSavePresetButton(hasDestinationShow: Bool, selectedFrameId: UUID?) -> Bool {
        hasDestinationShow && selectedFrameId != nil
    }

    /// Adds the Save Preset button (called from `viewDidLoad`).
    func setupSavePresetButton() {
        savePresetButton.accessibilityLabel = "Save as Preset"
        savePresetButton.translatesAutoresizingMaskIntoConstraints = true
        savePresetButton.addTarget(
            self, action: #selector(savePresetButtonTapped), for: .touchUpInside
        )
        view.addSubview(savePresetButton)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(savePresetStateChanged),
            name: LocalAlbumStore.didChangeNotification,
            object: nil
        )
        refreshSavePresetButton()
    }

    /// Visibility and saved state (filled bookmark once this frame is a preset).
    func refreshSavePresetButton() {
        let show = presetDestinationShow
        let frameId = CameraFrameStore.shared.selectedId
        let visible = Self.showsSavePresetButton(
            hasDestinationShow: show != nil, selectedFrameId: frameId
        )
        savePresetButton.isHidden = !visible
        guard visible, let show, let frameId else { return }
        let saved = isCameraPreset(frameId, in: show)
        var config = UIButton.Configuration.plain()
        let symbol = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        config.image = UIImage(
            systemName: saved ? "bookmark.fill" : "bookmark", withConfiguration: symbol
        )
        config.baseForegroundColor = .white
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 10, bottom: 10, trailing: 10
        )
        savePresetButton.configuration = config
        savePresetButton.accessibilityValue = saved ? "Saved" : nil
    }

    @objc func savePresetStateChanged() {
        refreshSavePresetButton()
        thumbGridView.reloadData()
    }

    @objc func savePresetButtonTapped() {
        guard let show = presetDestinationShow,
              let frameId = CameraFrameStore.shared.selectedId else { return }
        if isCameraPreset(frameId, in: show) {
            showPresentationToast("Already a preset in “\(show.name)”", centeredIn: panelView)
            return
        }
        confirmSaveCameraPreset(frameId: frameId, show: show)
    }

    /// "Save as preset?" prompt, then adds the tile to the Show.
    func confirmSaveCameraPreset(frameId: UUID, show: LocalAlbum) {
        let alert = UIAlertController(
            title: "Save as preset?",
            message: "Adds camera and frame as preset to your show.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            self?.saveCameraPreset(frameId: frameId, show: show)
        })
        present(alert, animated: true)
    }

    private func saveCameraPreset(frameId: UUID, show: LocalAlbum) {
        guard LocalAlbumStore.shared.addCameraPreset(frameId: frameId, albumId: show.id)
        else { return }
        Haptics.success()
        // Centred in the panel: the default bottom spot sits under the shutter row.
        showPresentationToast("Camera Preset added to the Show", centeredIn: panelView)
        refreshSavePresetButton()
    }

    /// ⋯ on a frame grid tile: Rename, and Save as Preset when Camera came from a Show.
    func frameTileMenu(frameId: UUID) -> UIMenu {
        var actions: [UIMenuElement] = [
            UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.presentRenameCameraFrame(frameId)
            }
        ]
        if let show = presetDestinationShow {
            let saved = isCameraPreset(frameId, in: show)
            actions.append(UIAction(
                title: saved ? "Saved as Preset" : "Save as Preset…",
                image: UIImage(systemName: saved ? "bookmark.fill" : "bookmark"),
                attributes: saved ? .disabled : []
            ) { [weak self] _ in
                self?.confirmSaveCameraPreset(frameId: frameId, show: show)
            })
        }
        return UIMenu(children: actions)
    }
}
