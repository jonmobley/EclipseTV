//
//  PDFReaderViewportLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  The reader only letterboxes to the Display Mode aspect when a projector is
//  there to match. Without one, a 16:9 panel on a portrait phone left the page
//  a sliver of the screen, so the reader takes the whole stage instead.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct PDFReaderViewportLayoutTests {

    /// The reader stages the whole safe area and insets the panel inside it.
    private let portraitStage = CGRect(x: 0, y: 0, width: 390, height: 764)
    private let landscapeStage = CGRect(x: 0, y: 0, width: 844, height: 390)
    private let inset = PDFReaderViewportLayout.projectorPanelInset

    @Test func noProjectorUsesTheWholeStage() {
        ExternalOutputOrientationFixture.with(.landscape) {
            let panel = PDFReaderViewportLayout.panelRect(
                in: portraitStage,
                matchesProjectorFraming: false
            )
            #expect(panel == portraitStage)
        }
    }

    @Test func noProjectorIgnoresVerticalDisplayMode() {
        ExternalOutputOrientationFixture.with(.portrait) {
            let panel = PDFReaderViewportLayout.panelRect(
                in: portraitStage,
                matchesProjectorFraming: false
            )
            #expect(panel == portraitStage)
        }
    }

    @Test func projectorKeepsTheSixteenByNinePanel() {
        ExternalOutputOrientationFixture.with(.landscape) {
            let panel = PDFReaderViewportLayout.panelRect(
                in: portraitStage,
                matchesProjectorFraming: true
            )
            #expect(abs(panel.width / panel.height - 16.0 / 9.0) < 0.01)
            #expect(panel.height < portraitStage.height)
            #expect(abs(panel.midY - portraitStage.midY) < 0.5)
            #expect(abs(panel.width - (portraitStage.width - inset * 2)) < 0.5)
        }
    }

    @Test func projectorKeepsTheNineBySixteenPanelInVertical() {
        ExternalOutputOrientationFixture.with(.portrait) {
            let panel = PDFReaderViewportLayout.panelRect(
                in: landscapeStage,
                matchesProjectorFraming: true
            )
            #expect(abs(panel.width / panel.height - 9.0 / 16.0) < 0.01)
            #expect(panel.width < landscapeStage.width)
        }
    }

    /// The reported bug: a portrait phone with no screen attached.
    @Test func disconnectedPortraitReaderIsTallerThanTheProjectorPanel() {
        ExternalOutputOrientationFixture.with(.landscape) {
            let letterboxed = PDFReaderViewportLayout.panelRect(
                in: portraitStage,
                matchesProjectorFraming: true
            )
            let full = PDFReaderViewportLayout.panelRect(
                in: portraitStage,
                matchesProjectorFraming: false
            )
            #expect(full.height > letterboxed.height * 3)
            #expect(full.width > letterboxed.width)
        }
    }

    @Test func emptyStageProducesNoPanel() {
        #expect(
            PDFReaderViewportLayout.panelRect(
                in: .zero,
                matchesProjectorFraming: false
            ) == .zero
        )
        #expect(
            PDFReaderViewportLayout.panelRect(
                in: CGRect(x: 0, y: 0, width: 366, height: 0),
                matchesProjectorFraming: true
            ) == .zero
        )
        // Stage too small to carry the frame inset.
        #expect(
            PDFReaderViewportLayout.panelRect(
                in: CGRect(x: 0, y: 0, width: 16, height: 16),
                matchesProjectorFraming: true
            ) == .zero
        )
    }
}
