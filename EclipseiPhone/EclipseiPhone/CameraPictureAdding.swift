//
//  CameraPictureAdding.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import EclipsePhoneCameraProtocol
import ObjectiveC
import PhotosUI
import UIKit

// MARK: - CameraPictureAdding

/// Where a frame or picture added on the camera goes, and whether one can be.
///
/// In Camera Mode with a two-way Camera Kit, additions are sent to the Mac
/// show (and come back as kit pictures). Otherwise they join the phone's own
/// frames and pictures. A locked one-way kit allows no additions.
@MainActor
enum CameraPictureAdding {

    /// True when additions go to the Mac show.
    static var sendsToMac: Bool {
        CameraOperatorMode.shared.isActive && CameraKitStore.shared.isTwoWay
    }

    /// Whether the + button should be offered.
    /// - Parameter ownRoomLeft: The phone's own picture list has room.
    /// - Returns: True when something can be added.
    static func canAdd(ownRoomLeft: Bool) -> Bool {
        decide(isTwoWay: CameraKitStore.shared.isTwoWay,
               isLocked: CameraKitStore.shared.hidesOwnPictures,
               ownRoomLeft: ownRoomLeft)
    }

    /// Pure rule behind `canAdd`, for tests.
    static func decide(isTwoWay: Bool, isLocked: Bool, ownRoomLeft: Bool) -> Bool {
        if isTwoWay { return true }
        return !isLocked && ownRoomLeft
    }

    /// Adds a frame: to the Mac kit when two-way, else to the phone's frames
    /// (and puts it on the camera).
    /// - Parameter image: Frame picture (PNG transparency kept).
    static func addFrame(_ image: UIImage) {
        if sendsToMac {
            Task { await CameraKitSync.shared.upload(image, kind: .frame) }
            return
        }
        guard let id = CameraFrameStore.shared.add(image) else { return }
        CameraKitStore.shared.clearFrameSelection()
        CameraFrameStore.shared.select(id)
    }

    /// Adds a picture: to the Mac kit when two-way, else to quick-change stills.
    /// - Parameter image: The picture.
    /// - Returns: The new own-still id, or nil when it went to the Mac / failed.
    @discardableResult
    static func addStill(_ image: UIImage) -> UUID? {
        if sendsToMac {
            Task { await CameraKitSync.shared.upload(image, kind: .still) }
            return nil
        }
        return CameraAlternateStillStore.shared.save(image, replacing: nil)
    }
}

// MARK: - CameraPhotoPicker

/// One-shot Photos picker that hands back a single image.
///
/// Retains itself on the picker it presents, so callers need not keep it.
final class CameraPhotoPicker: NSObject, PHPickerViewControllerDelegate {

    private static var key: UInt8 = 0
    private let completion: @MainActor (UIImage) -> Void

    private init(completion: @escaping @MainActor (UIImage) -> Void) {
        self.completion = completion
    }

    /// Presents the Photos picker over `presenter`.
    /// - Parameters:
    ///   - presenter: Controller to present from.
    ///   - completion: Called on main with the chosen image.
    @MainActor
    static func present(from presenter: UIViewController, completion: @escaping @MainActor (UIImage) -> Void) {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        let handler = CameraPhotoPicker(completion: completion)
        picker.delegate = handler
        objc_setAssociatedObject(picker, &key, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        presenter.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }
        let completion = completion
        provider.loadObject(ofClass: UIImage.self) { object, _ in
            guard let image = object as? UIImage else { return }
            Task { @MainActor in completion(image) }
        }
    }
}

// MARK: - Transparency Checkerboard

extension UIColor {
    /// Dark checkerboard drawn behind frame thumbnails so see-through areas show.
    static let transparencyCheckerboard: UIColor = {
        let tile: CGFloat = 6
        let size = CGSize(width: tile * 2, height: tile * 2)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(white: 0.16, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.26, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: tile, height: tile))
            context.fill(CGRect(x: tile, y: tile, width: tile, height: tile))
        }
        return UIColor(patternImage: image)
    }()
}
