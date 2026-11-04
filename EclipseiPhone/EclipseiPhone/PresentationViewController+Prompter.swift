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

    /// Fills the output canvas (rotated when Vertical) and sizes the text to it.
    func applyPrompterLayout() {
        guard !prompterContainer.isHidden, let stage = prompterStage else { return }
        applyRotatedLayout(to: stage, in: prompterContainer, scale: 1)
        stage.layoutIfNeeded()
        stage.setCanvasFontSize(PrompterController.shared.fontSize, isVertical: ExternalOutputSettings.isVerticalMode)
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
        stage.setCanvasFontSize(controller.fontSize, isVertical: ExternalOutputSettings.isVerticalMode)
        guard stage.script != controller.script else { return }
        stage.setScript(controller.script, anchor: controller.readingAnchor)
    }
}
