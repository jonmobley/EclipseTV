//
//  ExternalOutputCustomSizeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// Custom screen sizes letterbox the AirPlay picture; these cover the model,
/// persistence, and the geometry the TV and phone stages share.
@Suite(.serialized)
struct ExternalOutputCustomSizeTests {

    /// Runs `body` with no custom sizes saved, restoring the user's list after.
    @MainActor
    private func withCleanCustomSizes<T>(
        orientation: ExternalOutputOrientation = .landscape,
        _ body: () throws -> T
    ) rethrows -> T {
        let savedSizes = ExternalOutputSettings.customSizes
        let savedSelection = ExternalOutputSettings.selectedCustomSizeID
        defer {
            ExternalOutputSettings.customSizes = savedSizes
            ExternalOutputSettings.selectedCustomSizeID = savedSelection
        }
        ExternalOutputSettings.customSizes = []
        ExternalOutputSettings.selectedCustomSizeID = nil
        return try ExternalOutputOrientationFixture.with(orientation, body)
    }

    @Test func labelsAndRatio() {
        let wall = ExternalOutputCustomSize(name: "Lobby wall", width: 512, height: 786)
        #expect(wall.sizeLabel == "512×786")
        #expect(wall.displayLabel == "Lobby wall (512×786)")
        #expect(abs(wall.aspectRatio - 512.0 / 786.0) < 0.0001)

        let named = ExternalOutputCustomSize(name: "Wall 512×786", width: 512, height: 786)
        #expect(named.displayLabel == "Wall 512×786")

        let blank = ExternalOutputCustomSize(name: "   ", width: 4, height: 3)
        #expect(blank.displayLabel == "Custom (4×3)")
    }

    @Test func edgesClampToMinimum() {
        let tiny = ExternalOutputCustomSize(name: "x", width: 0, height: -5)
        #expect(tiny.width == 2)
        #expect(tiny.height == 2)
        #expect(ExternalOutputCustomSize.isValid(width: 2, height: 2))
        #expect(!ExternalOutputCustomSize.isValid(width: 1, height: 1080))
        #expect(ExternalOutputCustomSize.defaultName(width: 1920, height: 1080) == "1920×1080")
    }

    @Test @MainActor func addSelectsAndPersists() {
        withCleanCustomSizes {
            let added = ExternalOutputSettings.addCustomSize(name: "", width: 1024, height: 768)
            #expect(added != nil)
            #expect(added?.name == "1024×768")
            #expect(ExternalOutputSettings.customSizes == [added].compactMap { $0 })
            #expect(ExternalOutputSettings.selectedCustomSizeID == added?.id)
            #expect(ExternalOutputSettings.activeCustomSize == added)
            #expect(abs(ExternalOutputSettings.outputAspectRatio - 4.0 / 3.0) < 0.0001)

            #expect(ExternalOutputSettings.addCustomSize(name: "bad", width: 1, height: 9) == nil)
            #expect(ExternalOutputSettings.customSizes.count == 1)
        }
    }

    @Test @MainActor func updateAndRemove() {
        withCleanCustomSizes {
            guard let size = ExternalOutputSettings.addCustomSize(name: "A", width: 4, height: 2)
            else { Issue.record("add failed"); return }

            #expect(ExternalOutputSettings.updateCustomSize(
                id: size.id, name: " Wide ", width: 6, height: 2))
            let updated = ExternalOutputSettings.customSizes.first
            #expect(updated?.name == "Wide")
            #expect(updated?.width == 6)
            #expect(ExternalOutputSettings.activeCustomSize?.id == size.id)

            #expect(!ExternalOutputSettings.updateCustomSize(
                id: UUID(), name: "", width: 6, height: 2))
            #expect(!ExternalOutputSettings.updateCustomSize(
                id: size.id, name: "", width: 1, height: 1))

            ExternalOutputSettings.removeCustomSize(id: size.id)
            #expect(ExternalOutputSettings.customSizes.isEmpty)
            #expect(ExternalOutputSettings.selectedCustomSizeID == nil)
            #expect(ExternalOutputSettings.activeCustomSize == nil)
            #expect(abs(ExternalOutputSettings.outputAspectRatio - 16.0 / 9.0) < 0.0001)
        }
    }

    @Test @MainActor func selectionSurvivesVerticalButDoesNotApplyThere() {
        withCleanCustomSizes {
            let size = ExternalOutputSettings.addCustomSize(name: "Wall", width: 512, height: 786)
            ExternalOutputOrientationFixture.withSwitching { set in
                set(.portrait)
                #expect(ExternalOutputSettings.activeCustomSize == nil)
                #expect(abs(ExternalOutputSettings.outputAspectRatio - 9.0 / 16.0) < 0.0001)
                #expect(ExternalOutputSettings.selectedCustomSizeID == size?.id)

                set(.landscape)
                #expect(ExternalOutputSettings.activeCustomSize == size)
            }
        }
    }

    @Test @MainActor func stageRectLetterboxesOnlyForCustomSizes() {
        withCleanCustomSizes {
            let tv = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            #expect(ExternalOutputSettings.outputStageRect(in: tv) == tv)

            ExternalOutputSettings.addCustomSize(name: "Square", width: 100, height: 100)
            let stage = ExternalOutputSettings.outputStageRect(in: tv)
            #expect(stage.width == 1080)
            #expect(stage.height == 1080)
            #expect(stage.midX == 960)
            #expect(stage.midY == 540)

            // The phone stage uses the same shape.
            let phone = CGRect(x: 0, y: 0, width: 390, height: 300)
            let panel = ExternalOutputSettings.displayModePanelRect(in: phone)
            #expect(panel.width == 300)
            #expect(panel.height == 300)

            // Web viewport follows too: square logical page at the text-size width.
            let logical = ExternalOutputSettings.webLogicalSize
            #expect(abs(logical.width - logical.height) < 0.001)
        }
    }

    @Test @MainActor func verticalStageFillsTheDisplay() {
        withCleanCustomSizes(orientation: .portrait) {
            ExternalOutputSettings.addCustomSize(name: "Square", width: 10, height: 10)
            let tv = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            #expect(ExternalOutputSettings.outputStageRect(in: tv) == tv)
        }
    }

    @Test @MainActor func fitFillMeasuresAgainstTheCustomSize() {
        withCleanCustomSizes {
            let wide = CGSize(width: 1920, height: 1080)
            #expect(!MediaFitAvailability.fitDiffersFromFill(forSize: wide))

            ExternalOutputSettings.addCustomSize(name: "Wall", width: 512, height: 786)
            #expect(abs(MediaAspect.activeTarget - 512.0 / 786.0) < 0.0001)
            #expect(MediaFitAvailability.fitDiffersFromFill(forSize: wide))
            #expect(!MediaFitAvailability.fitDiffersFromFill(
                forSize: CGSize(width: 512, height: 786)))
        }
    }

    @Test func editorParsesWholeNumbersOfAtLeastTwo() {
        let parsed = SettingsDisplayModeViewController.parsedSize(" 512 ", "786")
        #expect(parsed?.0 == 512)
        #expect(parsed?.1 == 786)
        #expect(SettingsDisplayModeViewController.parsedSize("1", "786") == nil)
        #expect(SettingsDisplayModeViewController.parsedSize("abc", "786") == nil)
        #expect(SettingsDisplayModeViewController.parsedSize(nil, "786") == nil)
        #expect(SettingsDisplayModeViewController.parsedSize("12.5", "786") == nil)
    }
}
