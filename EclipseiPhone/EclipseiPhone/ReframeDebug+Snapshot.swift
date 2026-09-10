//
//  ReframeDebug+Snapshot.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension ReframeDebug {

    /// One reading of the cropper: the save-path convert, plus two mappings that
    /// do not go through `UIView.convert`.
    struct Snapshot {
        let target: CGFloat
        let image: String
        let imageView: String
        let scroll: String
        let window: String
        let convert: CGRect?
        let convertViaScroll: CGRect?
        let arith: CGRect?
        let screen: CGRect?
        let clamped: CGRect?
        let saved: CGRect?

        init(controller: AspectCropViewController, saved: CGRect?) {
            let scrollView = controller.scrollView
            target = controller.targetAspect
            image = ReframeDebug.describe(controller.sourceImage)
            imageView = ReframeDebug.imageViewLine(controller.imageView)
            scroll = ReframeDebug.scrollLine(scrollView)
            window = ReframeDebug.windowLine(controller.cropFrameView)
            convert = controller.rawCropRectInImage()
            convertViaScroll = ReframeDebug.convertViaScrollView(controller)
            arith = ReframeDebug.arithmeticCrop(controller)
            screen = ReframeDebug.screenCrop(controller)
            clamped = saved
            self.saved = saved
        }

        var hud: String {
            """
            target \(ReframeDebug.fmt(target))  img \(image)
            \(window)
            convert \(line(convert))
            arith   \(line(arith))
            screen  \(line(screen))
            saved   \(line(saved))
            """
        }

        var alert: String {
            """
            target \(ReframeDebug.fmt(target))
            \(image)
            convert \(line(convert))
            arith   \(line(arith))
            screen  \(line(screen))
            saved   \(line(saved))
            \(diagnosis)
            """
        }

        var full: String {
            """
            === Reframe Save ===
            target \(ReframeDebug.fmt(target))
            image \(image)
            imageView \(imageView)
            scroll \(scroll)
            window \(window)
            convert \(line(convert))
            viaScroll \(line(convertViaScroll))
            arith   \(line(arith))
            screen  \(line(screen))
            clamped \(line(clamped))
            saved   \(line(saved))
            \(diagnosis)
            """
        }

        var diagnosis: String {
            if shapeIsOff(convert) && !shapeIsOff(arith) {
                return "LIKELY: convert mapping (arith matches the window)."
            }
            if shapeIsOff(convert) && !shapeIsOff(screen) {
                return "LIKELY: convert mapping (screen matches the window)."
            }
            if !shapeIsOff(saved) {
                return "LIKELY: saved rect is the right shape. Watch TILE log after Save."
            }
            return "LIKELY: every mapping is the wrong shape."
        }

        private func shapeIsOff(_ rect: CGRect?) -> Bool {
            guard let rect, rect.height > 0 else { return true }
            return abs(rect.width / rect.height - target) > 0.08
        }

        private func line(_ rect: CGRect?) -> String {
            guard let rect else { return "nil" }
            return "\(ReframeDebug.rect(rect)) \(ReframeDebug.aspect(rect))"
        }
    }
}
