//
//  CameraKitStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import EclipsePhoneCameraProtocol
import UIKit

// MARK: - CameraKitPicture

/// One downloaded Camera Kit picture from the Mac show.
struct CameraKitPicture: Equatable {
    /// Mac card id (also used as the parked-still id).
    let id: UUID
    let kind: PhoneCameraKitItem.Kind
    let name: String
    let orientation: ExternalOutputOrientation
    let fileURL: URL
}

// MARK: - CameraKitStore

/// The open Mac show's Camera Kit while Camera Mode is connected.
///
/// Holds the kit pictures (cached under Caches so they never mix with the
/// volunteer's own frames and pictures), the show's Lock / two-way rules, and
/// which kit frame is on the camera. Empty outside Camera Mode.
///
/// Thread safety: main actor only.
@MainActor
final class CameraKitStore {

    // MARK: - Properties

    static let shared = CameraKitStore()

    /// Posted on main when pictures, rules or the kit frame selection change.
    static let didChangeNotification = Notification.Name("CameraKitStore.didChange")

    /// Open show's name, nil when no kit is loaded.
    private(set) var showName: String?
    /// Volunteer may use kit pictures only.
    private(set) var isLocked = false
    /// Pictures added on the phone go to the Mac show.
    private(set) var isTwoWay = false
    /// All kit pictures, in show order.
    private(set) var pictures: [CameraKitPicture] = []
    /// Kit frame laid over the camera, or nil.
    private(set) var selectedFrameId: UUID?

    /// Folder the kit pictures are cached in.
    let cacheDirectory: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CameraKit", isDirectory: true)

    private var images: [UUID: UIImage] = [:]

    // MARK: - Initialization

    private init() {}

    // MARK: - Queries

    /// Whether a kit (even an empty one) came from the Mac.
    var hasKit: Bool { showName != nil }

    /// Kit frames for the current Display Mode.
    var frames: [CameraKitPicture] {
        let mode = ExternalOutputSettings.orientation
        return pictures.filter { $0.kind == .frame && $0.orientation == mode }
    }

    /// Kit stills (any shape; program fits them).
    var stills: [CameraKitPicture] { pictures.filter { $0.kind == .still } }

    /// Whether the volunteer's own frames and pictures should be hidden.
    var hidesOwnPictures: Bool { CameraOperatorMode.shared.isActive && isLocked }

    /// Picture for a kit id, decoded once.
    /// - Parameter id: Kit picture id.
    /// - Returns: The image, or nil when it is not in the kit.
    func image(for id: UUID) -> UIImage? {
        if let cached = images[id] { return cached }
        guard let picture = pictures.first(where: { $0.id == id }),
              let image = UIImage(contentsOfFile: picture.fileURL.path) else { return nil }
        images[id] = image
        return image
    }

    /// Program source for a kit still, for parking the camera on it.
    /// - Parameter id: Kit picture id.
    /// - Returns: The source, or nil when it is not a kit still.
    func presentationSource(for id: UUID) -> PresentationSource? {
        guard let picture = stills.first(where: { $0.id == id }) else { return nil }
        return .image(picture.fileURL, fill: true)
    }

    /// Whether `id` is a kit still.
    func containsStill(_ id: UUID) -> Bool { stills.contains { $0.id == id } }

    /// The frame on the camera: a kit frame first, else the volunteer's own.
    var activeFrameImage: UIImage? {
        if let selectedFrameId { return image(for: selectedFrameId) }
        return hidesOwnPictures ? nil : CameraFrameStore.shared.selectedImage
    }

    // MARK: - Updates

    /// Replaces the kit with what the Mac sent.
    /// - Parameters:
    ///   - manifest: Kit description.
    ///   - pictures: Downloaded pictures, in manifest order.
    func apply(_ manifest: PhoneCameraKitManifest, pictures: [CameraKitPicture]) {
        showName = manifest.showName
        isLocked = manifest.locked
        isTwoWay = manifest.twoWay
        self.pictures = pictures
        images.removeAll()
        if let selectedFrameId, !frames.contains(where: { $0.id == selectedFrameId }) {
            self.selectedFrameId = nil
        }
        if isLocked, CameraOperatorMode.shared.isActive {
            CameraFrameStore.shared.select(nil)
        }
        postChange()
    }

    /// Puts a kit frame on the camera (nil takes it off).
    /// - Parameter id: Kit frame id.
    func selectFrame(_ id: UUID?) {
        selectedFrameId = id
        if id != nil, CameraFrameStore.shared.selectedId != nil {
            // One frame at a time: a kit frame replaces the volunteer's own.
            CameraFrameStore.shared.select(nil)
        }
        postChange()
    }

    /// Takes the kit frame off because the volunteer picked one of their own.
    func clearFrameSelection() {
        guard selectedFrameId != nil else { return }
        selectedFrameId = nil
        postChange()
    }

    /// Forgets the kit (Camera Mode ended or the Mac went away).
    func clear() {
        showName = nil
        isLocked = false
        isTwoWay = false
        pictures = []
        selectedFrameId = nil
        images.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        postChange()
    }

    // MARK: - Private Helpers

    private func postChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
