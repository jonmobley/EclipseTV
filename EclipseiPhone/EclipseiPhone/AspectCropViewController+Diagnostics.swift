//
//  AspectCropViewController+Diagnostics.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension AspectCropViewController {

    /// Fills the instruction area with live mapping numbers.
    func updateReframeDebugHUD() {
        guard ReframeDebug.isEnabled else { return }
        instructionLabel.text = ReframeDebug.hudText(on: self)
        instructionLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        instructionLabel.textColor = .green
        instructionLabel.textAlignment = .left
    }

    /// Logs, copies, and shows the dump so Save can be screenshot without Xcode.
    func confirmWithDebugDump() {
        guard let rect = visibleCropRectInImage() else {
            delegate?.aspectCropDidCancel(self)
            return
        }
        let dump = ReframeDebug.dump(on: self, saved: rect)
        UIPasteboard.general.string = dump
        print(dump)
        ReframeDebug.logger.error("\(dump, privacy: .public)")
        presentDebugAlert(saved: rect)
    }

    /// Applies the crop after the debug alert, or via the delegate for import.
    func finishConfirm(with rect: CGRect) {
        if let onFramingChosen {
            onFramingChosen(rect)
            return
        }
        guard let image = MediaAspect.crop(sourceImage, to: rect) else {
            delegate?.aspectCropDidCancel(self)
            return
        }
        delegate?.aspectCrop(self, didFinishWith: image, cropRectInSource: rect)
    }

    private func presentDebugAlert(saved: CGRect) {
        let alert = UIAlertController(
            title: "Reframe debug (copied)",
            message: ReframeDebug.alertText(on: self, saved: saved),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            self?.finishConfirm(with: saved)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}
