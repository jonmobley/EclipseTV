//
//  CameraPresetTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
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

    // MARK: - Frame Names

    @Test func frameNamesAreTrimmedClampedAndBlankMeansNone() {
        #expect(CameraFrame.cleanedName("  Lower Third \n") == "Lower Third")
        #expect(CameraFrame.cleanedName("   ") == nil)
        #expect(CameraFrame.cleanedName(nil) == nil)
        let long = String(repeating: "a", count: 100)
        #expect(CameraFrame.cleanedName(long)?.count == CameraFrame.maxNameLength)
    }

    @Test func frameNameSurvivesSavingAndOldIndexesStillLoad() throws {
        let frame = CameraFrame(
            id: frameA, createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: Date(timeIntervalSince1970: 0),
            orientation: .landscape, name: "Sponsor"
        )
        let data = try JSONEncoder().encode(frame)
        #expect(try JSONDecoder().decode(CameraFrame.self, from: data).name == "Sponsor")

        let legacy = Data(#"{"id":"\#(frameB.uuidString)","createdAt":0}"#.utf8)
        let old = try JSONDecoder().decode(CameraFrame.self, from: legacy)
        #expect(old.name == nil)
    }

    @Test func iCloudRecordCarriesTheNameOnlyWhenSet() {
        let named = CloudKitRecordMapper.makeCameraFrameRecord(
            id: frameA, orientation: .landscape, createdAt: Date(), name: "Sponsor"
        )
        #expect(CloudKitRecordMapper.cameraFrameName(from: named) == "Sponsor")

        let unnamed = CloudKitRecordMapper.makeCameraFrameRecord(
            id: frameB, orientation: .landscape, createdAt: Date()
        )
        // Unnamed frames never write the field, so they sync before it is deployed.
        #expect(!unnamed.allKeys().contains(CloudKitSchema.CameraFrameKey.name))

        // Clearing a name removes it from a record that had one.
        let cleared = CloudKitRecordMapper.makeCameraFrameRecord(
            id: frameA, orientation: .landscape, createdAt: Date(), existing: named
        )
        #expect(CloudKitRecordMapper.cameraFrameName(from: cleared) == nil)
    }

    // MARK: - Thumbnail

    @MainActor
    @Test func thumbnailIsTheOutputShapeWithTheFrameFitted() {
        // A portrait frame on a Landscape output: TV shows it fitted, so must the tile.
        let frame = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1600)).image {
            UIColor.blue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 900, height: 1600))
        }
        let backdrop = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image {
            UIColor.red.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        let out = CameraPresetThumbnail.compose(frame: frame, backdrop: backdrop, outputAspect: 16.0 / 9.0)
        #expect(out.size.width == 640)
        #expect(out.size.height == 360)
        // Edges show the camera (red), the centre the frame (blue).
        #expect(pixel(out, x: 10, y: 180).red > 0.8)
        #expect(pixel(out, x: 320, y: 180).blue > 0.8)

        let vertical = CameraPresetThumbnail.compose(frame: frame, backdrop: nil, outputAspect: 9.0 / 16.0)
        #expect(vertical.size.width == 360)
        #expect(vertical.size.height == 640)
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) -> (red: CGFloat, blue: CGFloat) {
        let cg = image.cgImage!
        var data = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(cg, in: CGRect(x: -x, y: y - cg.height + 1, width: cg.width, height: cg.height))
        return (CGFloat(data[0]) / 255, CGFloat(data[2]) / 255)
    }
}
