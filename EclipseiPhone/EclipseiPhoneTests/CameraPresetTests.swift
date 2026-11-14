//
//  CameraPresetTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

/// Camera Presets: the phone camera with one saved frame, as a Show tile.
struct CameraPresetTests {

    private let frameA = UUID()
    private let frameB = UUID()

    // MARK: - Token

    @Test func tokenRoundTripsTheFrameId() {
        let token = ShowCameraPresetToken.token(for: frameA)
        #expect(ShowCameraPresetToken.isCameraPreset(token))
        #expect(ShowCameraPresetToken.frameId(from: token) == frameA)
        #expect(ShowCameraPresetToken.frameId(from: ShowToolToken.camera) == nil)
        #expect(ShowCameraPresetToken.frameId(from: "a.jpg") == nil)
    }

    @Test func presetIsAToolSoItIsNeverTreatedAsMedia() {
        let token = ShowCameraPresetToken.token(for: frameA)
        #expect(ShowToolToken.isTool(token))
        // Old builds keep unknown tools that share the prefix, so presets survive sync.
        #expect(token.hasPrefix(ShowToolToken.prefix))
    }

    @Test func sanitizingKeepsPresetsInPlace() {
        let token = ShowCameraPresetToken.token(for: frameA)
        let surface = [ShowToolToken.camera, token, "a.jpg"]
        #expect(LocalAlbum.sanitizedSurface(surface, itemIds: ["a.jpg"]) == surface)
    }

    @Test func frameIdsCollectsOnlyPresets() {
        let surface = [
            ShowToolToken.camera,
            ShowCameraPresetToken.token(for: frameA),
            "a.jpg",
            ShowCameraPresetToken.token(for: frameB)
        ]
        #expect(
            ShowCameraPresetToken.frameIds(in: surface)
                == [frameA.uuidString, frameB.uuidString]
        )
    }

    // MARK: - Placement

    @Test func newPresetGoesAfterTheCameraAndItsPresets() {
        let presetA = ShowCameraPresetToken.token(for: frameA)
        #expect(
            LocalAlbumStore.cameraPresetInsertIndex(
                in: [ShowToolToken.logo, ShowToolToken.camera, "a.jpg"]
            ) == 2
        )
        #expect(
            LocalAlbumStore.cameraPresetInsertIndex(
                in: [ShowToolToken.camera, presetA, "a.jpg"]
            ) == 2
        )
        // No Camera tile: the preset goes last.
        #expect(LocalAlbumStore.cameraPresetInsertIndex(in: ["a.jpg", "b.jpg"]) == 2)
    }

    // MARK: - Which Tile Is Live

    private var grid: [ShowGridItem] {
        [.camera, .cameraPreset(frameId: frameA), .cameraPreset(frameId: frameB), .logo]
    }

    private var presetFrames: Set<String> { [frameA.uuidString, frameB.uuidString] }

    private func liveTiles(_ state: ShowProgramState) -> [ShowGridItem] {
        guard let program = ShowProgramResolver.resolve(state) else { return [] }
        return grid.filter { program.matches($0, cameraPresetFrameIds: presetFrames) }
    }

    @Test func plainCameraIsLiveWithNoFrame() {
        var state = ShowProgramState()
        state.isOverlayLive = true
        state.isCameraTileLive = true
        #expect(liveTiles(state) == [.camera])
    }

    @Test func thePresetForTheLiveFrameIsTheOnlyLiveTile() {
        var state = ShowProgramState()
        state.isOverlayLive = true
        state.isCameraTileLive = true
        state.cameraFrameId = frameB
        #expect(ShowProgramResolver.resolve(state)?.itemId == frameB.uuidString)
        #expect(liveTiles(state) == [.cameraPreset(frameId: frameB)])
    }

    @Test func aFrameWithNoPresetLightsThePlainCamera() {
        var state = ShowProgramState()
        state.isOverlayLive = true
        state.isCameraTileLive = true
        state.cameraFrameId = UUID()
        #expect(liveTiles(state) == [.camera])
    }

    @Test func presetsAreDarkWhenTheCameraIsNotLive() {
        var state = ShowProgramState()
        state.isLogoSelected = true
        state.cameraFrameId = frameA
        #expect(liveTiles(state) == [.logo])
    }

    @Test func presetNeverAutoAdvancesLive() {
        #expect(!ShowGridItem.cameraPreset(frameId: frameA).canAutoPresentLive)
        #expect(
            ShowGridItem.cameraPreset(frameId: frameA).selectionId
                == ShowCameraPresetToken.token(for: frameA)
        )
    }

    // MARK: - Thumbnail

    @MainActor
    @Test func thumbnailKeepsTheFrameShapeAndFillsTheBackdrop() {
        let frame = UIGraphicsImageRenderer(size: CGSize(width: 1920, height: 1080)).image { _ in }
        let backdrop = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image {
            UIColor.red.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        let out = CameraPresetThumbnail.compose(frame: frame, backdrop: backdrop)
        #expect(out.size.width == 640)
        #expect(out.size.height == 360)
    }
}
