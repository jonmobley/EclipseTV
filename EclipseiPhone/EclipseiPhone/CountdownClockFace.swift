//
//  CountdownClockFace.swift
//  Eclipse
//
//  Caption and "Card behind numbers" plate drawn with the countdown digits on
//  output, the hero and the Position editor. Proportions follow the Mac's
//  `TimerOverlayCard` so both apps put the same picture on the projector.
//  Thread Safety: Main-actor UIKit drawing; the face value is a plain struct.
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Face

/// What is drawn around the digits: an optional caption and an optional plate.
struct CountdownClockFace: Equatable {
    /// Words above the digits; empty shows none.
    var caption: String
    /// Dark rounded plate behind the digits and caption.
    var showsPlate: Bool

    /// Bare digits: no caption, no plate.
    static let plain = CountdownClockFace(caption: "", showsPlate: false)

    /// Creates a face from explicit values.
    init(caption: String, showsPlate: Bool) {
        self.caption = caption
        self.showsPlate = showsPlate
    }

    /// The face a countdown's settings ask for.
    init(_ settings: CountdownClockSettings) {
        self.init(caption: settings.caption, showsPlate: settings.showsPlate)
    }

    /// Face of the clock on output now, or plain when no countdown is live.
    @MainActor
    static var live: CountdownClockFace {
        let clock = CountdownController.shared
        guard clock.liveCountdownId != nil else { return .plain }
        return CountdownClockFace(clock.clockSettings)
    }

    // MARK: Proportions (shares of the digit font size, from the Mac)

    static let plateColor = UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1)
    static let plateEdgeColor = UIColor.white.withAlphaComponent(0.12)
    static let plateEdgeFactor: CGFloat = 0.012
    static let plateCornerFactor: CGFloat = 0.3
    static let plateHorizontalPadFactor: CGFloat = 0.42
    static let plateVerticalPadFactor: CGFloat = 0.18
    static let captionFontFactor: CGFloat = 0.26
    static let captionSpacingFactor: CGFloat = 0.18
    static let captionPadHorizontalFactor: CGFloat = 0.18
    static let captionPadVerticalFactor: CGFloat = 0.06
    static let captionCornerFactor: CGFloat = 0.12
    static let captionTrackingFactor: CGFloat = 0.18
    /// Padding around bare digits (points), as before plates existed.
    static let plainPad = CGSize(width: 4, height: 2)
    /// Tag of the caption label hosted inside the digit label.
    static let captionTag = 0x0C10C

    /// Padding around the digits for a font size.
    func digitPad(fontSize: CGFloat) -> CGSize {
        guard showsPlate else { return Self.plainPad }
        return CGSize(
            width: fontSize * Self.plateHorizontalPadFactor,
            height: fontSize * Self.plateVerticalPadFactor
        )
    }

    /// Caption words as drawn: upper case, letter-spaced.
    func captionText(fontSize: CGFloat) -> NSAttributedString? {
        guard !caption.isEmpty else { return nil }
        let size = fontSize * Self.captionFontFactor
        let font = UIFont.systemFont(ofSize: size, weight: .semibold)
        let rounded = font.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: size) } ?? font
        return NSAttributedString(string: caption.uppercased(), attributes: [
            .font: rounded,
            .foregroundColor: UIColor.white,
            .kern: size * Self.captionTrackingFactor
        ])
    }

    /// Caption chip size (text plus padding), zero without a caption.
    func captionSize(fontSize: CGFloat) -> CGSize {
        guard let text = captionText(fontSize: fontSize) else { return .zero }
        let fitted = text.size()
        return CGSize(
            width: ceil(fitted.width) + fontSize * Self.captionPadHorizontalFactor * 2,
            height: ceil(fitted.height) + fontSize * Self.captionPadVerticalFactor * 2
        )
    }

    /// Height the caption adds above the digits, spacing included.
    func captionBlockHeight(fontSize: CGFloat) -> CGFloat {
        let size = captionSize(fontSize: fontSize)
        guard size.height > 0 else { return 0 }
        return size.height + fontSize * Self.captionSpacingFactor
    }
}
