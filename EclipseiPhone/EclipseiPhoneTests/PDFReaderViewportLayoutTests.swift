//
//  PDFReaderViewportLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  The reader always frames what the audience sees, in the output shape, in
//  both phone orientations and with or without a projector. The page around the
//  frame is drawn dimmed by a context view in the frame's column.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct PDFReaderViewportLayoutTests {

    private let portraitStage = CGRect(x: 0, y: 0, width: 390, height: 764)
    private let landscapeStage = CGRect(x: 0, y: 0, width: 844, height: 390)
    private let inset = PDFReaderViewportLayout.framePanelInset

    @Test func portraitPhoneFramesSixteenByNine() {
        let panel = PDFReaderViewportLayout.panelRect(in: portraitStage, aspect: 16.0 / 9.0)
        #expect(abs(panel.width / panel.height - 16.0 / 9.0) < 0.01)
        #expect(abs(panel.width - (portraitStage.width - inset * 2)) < 0.5)
        #expect(abs(panel.midY - portraitStage.midY) < 0.5)
    }

    @Test func landscapePhoneFramesSixteenByNine() {
        let panel = PDFReaderViewportLayout.panelRect(in: landscapeStage, aspect: 16.0 / 9.0)
        #expect(abs(panel.width / panel.height - 16.0 / 9.0) < 0.01)
        #expect(abs(panel.height - (landscapeStage.height - inset * 2)) < 0.5)
        #expect(abs(panel.midX - landscapeStage.midX) < 0.5)
    }

    @Test func verticalDisplayModeFramesNineBySixteen() {
        let panel = PDFReaderViewportLayout.panelRect(in: landscapeStage, aspect: 9.0 / 16.0)
        #expect(abs(panel.width / panel.height - 9.0 / 16.0) < 0.01)
        #expect(panel.width < landscapeStage.width)
    }

    @Test func defaultAspectFollowsTheOutputSetting() {
        ExternalOutputOrientationFixture.with(.landscape) {
            let panel = PDFReaderViewportLayout.panelRect(in: portraitStage)
            let expected = ExternalOutputSettings.outputAspectRatio
            #expect(abs(panel.width / panel.height - expected) < 0.01)
        }
        ExternalOutputOrientationFixture.with(.portrait) {
            let panel = PDFReaderViewportLayout.panelRect(in: portraitStage)
            #expect(abs(panel.width / panel.height - 9.0 / 16.0) < 0.01)
        }
    }

    @Test func contextColumnSpansTheStageHeightUnderTheFrame() {
        let panel = PDFReaderViewportLayout.panelRect(in: portraitStage, aspect: 16.0 / 9.0)
        let context = PDFReaderViewportLayout.contextRect(for: panel, in: portraitStage)
        #expect(context.minX == panel.minX)
        #expect(context.width == panel.width)
        #expect(context.minY == portraitStage.minY)
        #expect(context.height == portraitStage.height)
    }

    @Test func contextOffsetShiftsByTheFrameTop() {
        let offset = PDFReaderViewportLayout.contextOffset(
            forPanelOffset: CGPoint(x: 4, y: 500),
            panelTop: 279
        )
        #expect(offset == CGPoint(x: 4, y: 221))
    }

    @Test func emptyStageProducesNoPanel() {
        #expect(PDFReaderViewportLayout.panelRect(in: .zero, aspect: 16.0 / 9.0) == .zero)
        #expect(
            PDFReaderViewportLayout.panelRect(
                in: CGRect(x: 0, y: 0, width: 16, height: 16), aspect: 16.0 / 9.0
            ) == .zero
        )
        #expect(PDFReaderViewportLayout.contextRect(for: .zero, in: portraitStage) == .zero)
    }
}
