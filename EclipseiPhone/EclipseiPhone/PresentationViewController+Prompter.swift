//
//  PresentationViewController+Prompter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Prompter Presentation

extension PresentationViewController {

    /// Shows the scrolling script on the external display, following the
    /// controller's reading anchor in this display's own text size.
    func showPrompter() {
        hideCamera()
        hideWeb()
        hidePDF()
        hideMediaContainer()
        hideCountdown()
        messageLabel.text = nil
        imageView.isHidden = true
        imageView.image = nil
        activityIndicator.stopAnimating()
        setIdleBrandVisible(false)

        installPrompterStageIfNeeded()
        prompterContainer.isHidden = false
        applyPrompterLayout()
    }

    /// Hides the script and drops the stage, so a long text view is not kept warm.
    func hidePrompter() {
        prompterContainer.isHidden = true
        if let prompterObserver {
            NotificationCenter.default.removeObserver(prompterObserver)
            self.prompterObserver = nil
        }
        if let prompterOffsetObserver {
            NotificationCenter.default.removeObserver(prompterOffsetObserver)
            self.prompterOffsetObserver = nil
        }
        prompterStage?.removeFromSuperview()
        prompterStage = nil
    }

    /// Fills the output canvas (rotated when Vertical) and sizes the text to it. A
    /// Prompter switched to Vertical on a Landscape display is an upright 9:16 column.
    func applyPrompterLayout() {
        guard !prompterContainer.isHidden, let stage = prompterStage else { return }
        let controller = PrompterController.shared
        if controller.isVerticalOnLandscapeDisplay {
            stage.transform = .identity
            stage.frame = ExternalOutputSettings.panelRect(
                in: prompterContainer.bounds, aspect: controller.canvasAspectRatio
            )
        } else {
            applyRotatedLayout(to: stage, in: prompterContainer, scale: 1)
        }
        stage.layoutIfNeeded()
        stage.setCanvasFontSize(controller.fontSize, isVertical: controller.isVertical)
        stage.layoutIfNeeded()
        stage.apply(anchor: PrompterController.shared.readingAnchor)
    }

    // MARK: - Private

    private func installPrompterStageIfNeeded() {
        let controller = PrompterController.shared
        if prompterStage == nil {
            let stage = PrompterStageView()
            stage.translatesAutoresizingMaskIntoConstraints = true
            prompterContainer.addSubview(stage)
            prompterStage = stage
            stage.setScript(controller.script, anchor: controller.readingAnchor)
        }
        if prompterObserver == nil {
            prompterObserver = NotificationCenter.default.addObserver(
                forName: PrompterController.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPrompterScript() }
            }
        }
        if prompterOffsetObserver == nil {
            prompterOffsetObserver = NotificationCenter.default.addObserver(
                forName: PrompterController.offsetDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.prompterStage?.apply(anchor: PrompterController.shared.readingAnchor)
                }
            }
        }
    }

    private func refreshPrompterScript() {
        guard let stage = prompterStage else { return }
        let controller = PrompterController.shared
        if stage.isVertical != controller.isVertical || shapeChanged(stage, controller) {
            applyPrompterLayout()
        }
        stage.setCanvasFontSize(controller.fontSize, isVertical: controller.isVertical)
        guard stage.script != controller.script else { return }
        stage.setScript(controller.script, anchor: controller.readingAnchor)
    }

    /// True when the stage's aspect no longer matches the Prompter's canvas.
    private func shapeChanged(_ stage: PrompterStageView, _ controller: PrompterController) -> Bool {
        let size = stage.bounds.size
        guard size.width > 0, size.height > 0 else { return false }
        let wantsTall = controller.canvasAspectRatio < 1
        return (size.height > size.width) != wantsTall
    }
}
