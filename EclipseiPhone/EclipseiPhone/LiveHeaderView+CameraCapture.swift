//
//  LiveHeaderView+CameraCapture.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Take Photo / Record on the live camera hero

extension LiveHeaderView {

    private static let captureButtonSide: CGFloat = 36
    private static let photoTag = 1
    private static let recordTag = 2

    /// Bottom-leading Take Photo and Record while the live camera owns the hero, so the
    /// operator can capture without opening the full-screen camera.
    func setCameraCaptureVisible(_ visible: Bool, isRecording: Bool = false) {
        guard visible else {
            cameraCaptureStack?.removeFromSuperview()
            cameraCaptureStack = nil
            return
        }
        if cameraCaptureStack == nil {
            installCameraCaptureStack()
        }
        applyRecordAppearance(isRecording: isRecording)
        bringCameraCaptureChromeToFront()
    }

    /// Brief black flash over the hero (shutter feedback).
    func playCameraShutterBlink() {
        let flash = UIView(frame: bounds)
        flash.backgroundColor = .black
        flash.isUserInteractionEnabled = false
        flash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let stack = cameraCaptureStack {
            insertSubview(flash, belowSubview: stack)
        } else {
            addSubview(flash)
        }
        UIView.animate(
            withDuration: 0.14,
            delay: 0.03,
            options: [.curveEaseOut],
            animations: { flash.alpha = 0 },
            completion: { _ in flash.removeFromSuperview() }
        )
    }

    func bringCameraCaptureChromeToFront() {
        guard let stack = cameraCaptureStack else { return }
        bringSubviewToFront(stack)
    }

    // MARK: - Private

    private func installCameraCaptureStack() {
        let photo = makeCaptureButton(tag: Self.photoTag) { [weak self] in
            self?.onCameraTakePhoto?()
        }
        var config = photo.configuration ?? .plain()
        config.image = UIImage(
            systemName: "camera.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        config.baseForegroundColor = .white
        photo.configuration = config
        photo.accessibilityLabel = "Take Photo"

        let record = makeCaptureButton(tag: Self.recordTag) { [weak self] in
            self?.onCameraToggleRecording?()
        }

        let stack = UIStackView(arrangedSubviews: [photo, record])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
        cameraCaptureStack = stack
    }

    private func makeCaptureButton(tag: Int, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.contentInsets = .zero
        let button = MinimumHitTargetButton(configuration: config)
        button.tag = tag
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = Self.captureButtonSide / 2
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.captureButtonSide),
            button.heightAnchor.constraint(equalToConstant: Self.captureButtonSide)
        ])
        return button
    }

    /// Red dot to record; white stop square on red while a movie is rolling.
    private func applyRecordAppearance(isRecording: Bool) {
        guard let record = cameraCaptureStack?.viewWithTag(Self.recordTag) as? UIButton
        else { return }
        var config = record.configuration ?? .plain()
        config.image = UIImage(
            systemName: isRecording ? "stop.fill" : "circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: isRecording ? 12 : 16, weight: .semibold
            )
        )
        config.baseForegroundColor = isRecording ? .white : .systemRed
        config.contentInsets = .zero
        record.configuration = config
        record.backgroundColor = isRecording
            ? .systemRed
            : UIColor.black.withAlphaComponent(0.45)
        record.accessibilityLabel = isRecording ? "Stop Recording" : "Record"
    }
}
