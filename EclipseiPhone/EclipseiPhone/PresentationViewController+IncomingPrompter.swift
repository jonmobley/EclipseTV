//
//  PresentationViewController+IncomingPrompter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Incoming Prompter

extension PresentationViewController {

    /// Composes the script in the transition overlay. Text on black is already the
    /// finished frame, so it reports ready as soon as it is laid out.
    func installIncomingPrompter(generation: Int) {
        let host = makeIncomingMediaHost()
        let stage = PrompterStageView()
        stage.frame = host.bounds
        stage.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(stage)
        incomingPrompterStage = stage
        layoutIncomingMediaHost()
        host.layoutIfNeeded()
        layoutIncomingPrompter()
        notifyIfCurrent(generation)
    }

    /// Re-sizes the overlay script after a rotation or Display Mode change.
    func layoutIncomingPrompter() {
        guard let stage = incomingPrompterStage, let host = incomingMediaHost else { return }
        stage.frame = host.bounds
        let canvas = host.bounds.size
        stage.horizontalInset = PrompterStageMetrics.outputTextInset(for: canvas)
        stage.setFont(PrompterStageMetrics.font(ofSize: PrompterStageMetrics.outputFontSize(in: canvas)))
        let controller = PrompterController.shared
        stage.setScript(controller.script, anchor: controller.readingAnchor)
    }
}
