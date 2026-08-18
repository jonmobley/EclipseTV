//
//  CameraLiveViewController+AlternateStill.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import PhotosUI
import UIKit

// MARK: - Alternate Still (cutaway on AirPlay)

extension CameraLiveViewController {

    /// Diameter of the in-panel cutaway thumbnail.
    static let alternateStillThumbSize: CGFloat = 52

    /// Builds the cutaway thumbnail control (called from `viewDidLoad`).
    func setupAlternateStillButton() {
        alternateStillButton.translatesAutoresizingMaskIntoConstraints = true
        alternateStillButton.clipsToBounds = true
        alternateStillButton.layer.cornerRadius = 10
        alternateStillButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        alternateStillButton.accessibilityLabel = "Cutaway Photo"
        alternateStillButton.insertSubview(alternateStillImageView, at: 0)
        NSLayoutConstraint.activate([
            alternateStillImageView.topAnchor.constraint(
                equalTo: alternateStillButton.topAnchor
            ),
            alternateStillImageView.bottomAnchor.constraint(
                equalTo: alternateStillButton.bottomAnchor
            ),
            alternateStillImageView.leadingAnchor.constraint(
                equalTo: alternateStillButton.leadingAnchor
            ),
            alternateStillImageView.trailingAnchor.constraint(
                equalTo: alternateStillButton.trailingAnchor
            )
        ])
        alternateStillButton.addTarget(
            self,
            action: #selector(alternateStillButtonTapped),
            for: .touchUpInside
        )
        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(alternateStillButtonLongPressed(_:))
        )
        alternateStillButton.addGestureRecognizer(longPress)
        view.addSubview(alternateStillButton)
        refreshAlternateStillAppearance()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(alternateStillStoreDidChange),
            name: CameraAlternateStillStore.didChangeNotification,
            object: nil
        )
    }

    /// Places the cutaway thumb at the bottom-leading corner of the Display Mode panel.
    func layoutAlternateStillButton(panel: CGRect) {
        let size = Self.alternateStillThumbSize
        let inset: CGFloat = 14
        alternateStillButton.frame = CGRect(
            x: panel.minX + inset,
            y: panel.maxY - inset - size,
            width: size,
            height: size
        )
        view.bringSubviewToFront(alternateStillButton)
    }

    /// Updates thumbnail art and red stroke when the cutaway owns AirPlay.
    func refreshAlternateStillAppearance() {
        let store = CameraAlternateStillStore.shared
        let active = ExternalDisplayManager.shared.isCameraParkedOnStill
            && store.hasStill
        if let image = store.image {
            alternateStillImageView.image = image
            alternateStillImageView.isHidden = false
            alternateStillButton.setImage(nil, for: .normal)
            alternateStillButton.tintColor = nil
            alternateStillButton.backgroundColor = .black
            alternateStillButton.accessibilityHint = active
                ? "Showing on AirPlay. Tap to return to the live camera."
                : "Tap to show this photo on AirPlay. Hold to replace or clear."
            alternateStillButton.accessibilityValue = active ? "On AirPlay" : "Ready"
        } else {
            alternateStillImageView.image = nil
            alternateStillImageView.isHidden = true
            let symbol = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            alternateStillButton.setImage(
                UIImage(systemName: "photo.badge.plus", withConfiguration: symbol),
                for: .normal
            )
            alternateStillButton.tintColor = .white
            alternateStillButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            alternateStillButton.accessibilityHint =
                "Chooses a photo to toggle onto AirPlay while camera is live"
            alternateStillButton.accessibilityValue = "None"
        }
        alternateStillButton.layer.borderWidth = active ? 3 : 1
        alternateStillButton.layer.borderColor = active
            ? UIColor.systemRed.cgColor
            : UIColor.white.withAlphaComponent(0.35).cgColor
    }

    @objc private func alternateStillStoreDidChange() {
        refreshAlternateStillAppearance()
    }

    /// Empty → pick. Chosen + parked → resume camera. Chosen → park on AirPlay.
    @objc func alternateStillButtonTapped() {
        let store = CameraAlternateStillStore.shared
        guard store.hasStill else {
            presentAlternateStillPicker()
            return
        }
        let mgr = ExternalDisplayManager.shared
        if mgr.isCameraParkedOnStill {
            mgr.resumeCameraFromStillPark()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            refreshLiveChrome()
            startAlwaysLiveRecordingIfNeeded()
            return
        }
        guard let source = store.presentationSource else { return }
        if mgr.isCameraModeActive {
            // Recording belongs on the live camera feed — stop before cutaway.
            finalizeRecordingIfNeeded { [weak self] in
                guard let self else { return }
                ExternalDisplayManager.shared.parkCameraOnStill(source)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                self.refreshLiveChrome()
            }
            return
        }
        // Not live yet: go live, then immediately cut to the still.
        prepareLivePreviewHandoffToAirPlay()
        mgr.presentCamera()
        mgr.parkCameraOnStill(source)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        refreshLiveChrome()
    }

    /// Replace or clear when a cutaway is already chosen.
    @objc func alternateStillButtonLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        guard CameraAlternateStillStore.shared.hasStill else {
            presentAlternateStillPicker()
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let sheet = UIAlertController(title: "Cutaway Photo", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Replace…", style: .default) { [weak self] _ in
            self?.presentAlternateStillPicker()
        })
        sheet.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            self?.clearAlternateStill()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = alternateStillButton
            pop.sourceRect = alternateStillButton.bounds
        }
        present(sheet, animated: true)
    }

    private func clearAlternateStill() {
        let mgr = ExternalDisplayManager.shared
        if mgr.isCameraParkedOnStill {
            mgr.resumeCameraFromStillPark()
            startAlwaysLiveRecordingIfNeeded()
        }
        CameraAlternateStillStore.shared.clear()
        refreshLiveChrome()
    }

    private func presentAlternateStillPicker() {
        guard !isAlreadyOpen(PHPickerViewController.self) else { return }
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension CameraLiveViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            Task { @MainActor in
                guard let self else { return }
                CameraAlternateStillStore.shared.save(image)
                // If AirPlay was already on the cutaway, refresh the new still.
                let mgr = ExternalDisplayManager.shared
                if mgr.isCameraParkedOnStill,
                   let source = CameraAlternateStillStore.shared.presentationSource {
                    mgr.parkCameraOnStill(source)
                }
                self.refreshLiveChrome()
            }
        }
    }
}
