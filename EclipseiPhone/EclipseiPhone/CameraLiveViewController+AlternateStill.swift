//
//  CameraLiveViewController+AlternateStill.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import PhotosUI
import UIKit

// MARK: - Alternate Still (cutaway)

extension CameraLiveViewController {

    /// Short side of the in-panel cutaway thumbnail. Long side follows Display Mode
    /// (16:9 Landscape, 9:16 Vertical) so the thumb matches the Show stage.
    static let alternateStillThumbShortSide: CGFloat = 52

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(alternateStillStoreDidChange),
            name: LogoStore.didChangeNotification,
            object: nil
        )
    }

    /// Places the cutaway thumb at the bottom-trailing corner of the Display Mode panel.
    func layoutAlternateStillButton(panel: CGRect) {
        let short = Self.alternateStillThumbShortSide
        let aspect = ExternalOutputSettings.orientation.aspectRatio
        let width = aspect >= 1 ? short * aspect : short
        let height = width / aspect
        let inset = cameraThumbEdgeInset(panel: panel)
        alternateStillButton.frame = CGRect(
            x: panel.maxX - inset - width,
            y: panel.maxY - inset - height,
            width: width,
            height: height
        )
        view.bringSubviewToFront(alternateStillButton)
    }

    /// 14pt in-panel pad, plus any home-indicator overlap (Landscape panel).
    func cameraThumbEdgeInset(panel: CGRect) -> CGFloat {
        let base: CGFloat = 14
        let safeBottom = view.bounds.maxY - view.safeAreaInsets.bottom
        return base + max(0, panel.maxY - safeBottom)
    }

    /// Updates thumbnail art and red stroke when the cutaway is the parked still.
    func refreshAlternateStillAppearance() {
        let store = CameraAlternateStillStore.shared
        let active = ExternalDisplayManager.shared.isCameraParkedOnStill
        let onAirPlay = ExternalDisplayManager.shared.isConnected
        if let image = store.displayImage {
            alternateStillImageView.image = image
            alternateStillImageView.isHidden = false
            alternateStillButton.setImage(nil, for: .normal)
            alternateStillButton.tintColor = nil
            alternateStillButton.backgroundColor = .black
            alternateStillButton.accessibilityHint = active
                ? "Cutaway is live. Tap to return to the live camera."
                : store.hasStill
                    ? "Tap to show this photo on program. Hold to replace or remove."
                    : "Tap to show the Show Background on program. Hold to replace."
            alternateStillButton.accessibilityValue = active
                ? (onAirPlay ? "On AirPlay" : "Active")
                : (store.hasStill ? "Custom photo" : "Background")
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
                "Chooses a photo to toggle on while camera is live"
            alternateStillButton.accessibilityValue = "None"
        }
        alternateStillButton.layer.borderWidth = active ? 3 : 1
        alternateStillButton.layer.borderColor = active
            ? UIColor.systemRed.cgColor
            : UIColor.white.withAlphaComponent(0.35).cgColor
    }

    @objc private func alternateStillStoreDidChange() {
        let store = CameraAlternateStillStore.shared
        let mgr = ExternalDisplayManager.shared
        if mgr.isCameraParkedOnStill, !store.hasStill,
           let source = store.presentationSource {
            mgr.parkCameraOnStill(source)
        }
        refreshAlternateStillAppearance()
    }

    /// Parked → resume camera. Otherwise go live (if needed) and park the still.
    @objc func alternateStillButtonTapped() {
        let store = CameraAlternateStillStore.shared
        let mgr = ExternalDisplayManager.shared
        if mgr.isCameraParkedOnStill {
            mgr.resumeCameraFromStillPark()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            refreshLiveChrome()
            startAlwaysLiveRecordingIfNeeded()
            return
        }
        guard let source = store.presentationSource else {
            presentAlternateStillPicker()
            return
        }
        if mgr.isCameraModeActive {
            // Recording belongs on the live camera feed — stop before cutaway.
            finalizeRecordingIfNeeded { [weak self] in
                guard let self else { return }
                self.parkAlternateStill(source)
            }
            return
        }
        if mgr.isConnected {
            prepareLivePreviewHandoffToAirPlay()
        }
        mgr.presentCamera()
        parkAlternateStill(source)
    }

    /// Parks the cutaway on program and refreshes camera chrome.
    private func parkAlternateStill(_ source: PresentationSource) {
        ExternalDisplayManager.shared.parkCameraOnStill(source)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        refreshLiveChrome()
    }

    /// Replace the cutaway, or remove a custom photo (restores Show Background).
    @objc func alternateStillButtonLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let sheet = UIAlertController(
            title: "Cutaway Photo", message: nil, preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Replace…", style: .default) { [weak self] _ in
            self?.presentAlternateStillPicker()
        })
        if CameraAlternateStillStore.shared.hasStill {
            sheet.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
                self?.clearAlternateStill()
            })
        }
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
