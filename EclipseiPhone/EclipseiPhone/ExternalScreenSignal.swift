//
//  ExternalScreenSignal.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import os
import UIKit

/// What a connected external screen says about itself: the size iOS is sending
/// it, and the other sizes it offers.
///
/// A TV or projector is 16:9. An LED wall behind an EDID box can report its own
/// size instead (e.g. 2048×768). When the size is not 16:9, Eclipse composes
/// the picture for that shape and turns off the edge shrink iOS applies to TVs,
/// so every dot of the signal lands on the wall.
///
/// Thread safety: a value type. The connected signal is held by
/// `ExternalOutputSettings` behind a lock and written on the main thread only.
struct ExternalScreenSignal: Equatable, Sendable {

    /// A size in real screen dots.
    struct PixelSize: Equatable, Hashable, Sendable {
        let width: Int
        let height: Int

        /// Compact size, e.g. `2048×768`.
        var label: String { "\(width)×\(height)" }

        /// Width ÷ height, or 0 for an empty size.
        var aspectRatio: CGFloat {
            height > 0 ? CGFloat(width) / CGFloat(height) : 0
        }
    }

    /// The shape of an ordinary TV.
    static let standardAspectRatio: CGFloat = 16.0 / 9.0

    /// How far from 16:9 a size may be and still count as a TV (1366×768 does).
    static let standardShapeTolerance: CGFloat = 0.01

    /// The size iOS is sending right now.
    let current: PixelSize

    /// Every size the screen offers, in the order iOS lists them.
    let offered: [PixelSize]

    // MARK: - Rules

    /// Width ÷ height when the screen is not 16:9; nil for an ordinary TV.
    var oddShape: CGFloat? {
        let ratio = current.aspectRatio
        guard ratio > 0 else { return nil }
        let distance = abs(ratio - Self.standardAspectRatio) / Self.standardAspectRatio
        return distance > Self.standardShapeTolerance ? ratio : nil
    }

    /// The offered sizes other than the current one, without repeats.
    var otherOffered: [PixelSize] {
        var seen: Set<PixelSize> = [current]
        return offered.filter { seen.insert($0).inserted }
    }

    /// Video sizes iOS lists for every HDMI screen; never a screen's own shape.
    static let standardVideoSizes: Set<PixelSize> = [
        PixelSize(width: 640, height: 480),
        PixelSize(width: 720, height: 480),
        PixelSize(width: 720, height: 576)
    ]

    /// The other offered sizes that are the screen's own odd shapes, such as an
    /// LED wall's other widths: the ones worth a one-tap choice.
    var selectableOffered: [PixelSize] {
        otherOffered.filter { size in
            !Self.standardVideoSizes.contains(size)
                && ExternalScreenSignal(current: size, offered: []).oddShape != nil
        }
    }

    /// Which offered size to switch to so the signal matches `wanted`.
    ///
    /// Only for a wanted size that is not 16:9: a custom size such as 1280×720
    /// describes proportions, and must not pull a 4K TV down to a smaller signal.
    /// - Parameters:
    ///   - wanted: The size the operator chose in Settings, if any.
    ///   - offered: Sizes the screen offers.
    ///   - current: The size being sent now.
    /// - Returns: An index into `offered`, or nil to leave the signal alone.
    static func indexOfOffered(
        matching wanted: PixelSize?,
        in offered: [PixelSize],
        current: PixelSize
    ) -> Int? {
        guard let wanted, wanted != current,
              ExternalScreenSignal(current: wanted, offered: []).oddShape != nil
        else { return nil }
        return offered.firstIndex(of: wanted)
    }

    /// True when replacing `old` with `new` changes the picture's shape.
    static func shapeChanged(from old: ExternalScreenSignal?, to new: ExternalScreenSignal?) -> Bool {
        old?.oddShape != new?.oddShape
    }
}

// MARK: - Reading a Screen

@MainActor
extension ExternalScreenSignal {

    /// Reads `screen` after switching it to `wanted` when the screen offers that
    /// exact size, and turns off the edge shrink on a screen that is not 16:9.
    ///
    /// Ordinary 16:9 screens are left exactly as iOS set them up.
    /// - Parameters:
    ///   - screen: The external screen.
    ///   - wanted: The operator's custom size, if one is active.
    /// - Returns: The signal after any change.
    static func prepare(_ screen: UIScreen, wanted: PixelSize?) -> ExternalScreenSignal {
        let modes = screen.availableModes
        let offered = modes.map { pixelSize($0.size) }
        let index = indexOfOffered(matching: wanted, in: offered, current: currentSize(of: screen))
        if let index {
            screen.currentMode = modes[index]
        }
        let signal = ExternalScreenSignal(current: currentSize(of: screen), offered: offered)
        if signal.oddShape != nil, screen.overscanCompensation != .none {
            screen.overscanCompensation = .none
        }
        return signal
    }

    private static func currentSize(of screen: UIScreen) -> PixelSize {
        pixelSize(screen.currentMode?.size ?? screen.nativeBounds.size)
    }

    private static func pixelSize(_ size: CGSize) -> PixelSize {
        PixelSize(width: Int(size.width.rounded()), height: Int(size.height.rounded()))
    }
}

// MARK: - Settings

extension ExternalOutputSettings {

    private static let screenSignalBox = OSAllocatedUnfairLock<ExternalScreenSignal?>(
        initialState: nil
    )

    /// The connected external screen's signal; nil when nothing is connected.
    static var connectedScreenSignal: ExternalScreenSignal? {
        screenSignalBox.withLock { $0 }
    }

    /// Records the connected screen's signal.
    ///
    /// Does not post `didChangeNotification` itself: the caller is in the middle
    /// of attaching to the screen, and observers of that notification call back
    /// into the display manager. `ExternalDisplayManager` posts it afterwards.
    /// - Parameter signal: The new signal, or nil after a disconnect.
    /// - Returns: True when the picture's shape changed.
    @discardableResult
    static func updateConnectedScreenSignal(_ signal: ExternalScreenSignal?) -> Bool {
        let previous = screenSignalBox.withLock { box -> ExternalScreenSignal? in
            let old = box
            box = signal
            return old
        }
        return ExternalScreenSignal.shapeChanged(from: previous, to: signal)
    }

    /// Label for the Full Screen choice: the real size on an odd-shaped screen.
    static var fullScreenLabel: String {
        fullScreenLabel(signal: connectedScreenSignal)
    }

    /// Label for the Full Screen choice given a connected signal.
    static func fullScreenLabel(signal: ExternalScreenSignal?) -> String {
        guard let signal, signal.oddShape != nil else { return "Full Screen (16:9)" }
        return "Full Screen (\(signal.current.label))"
    }
}
