//
//  LiveOverlayLayerView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: SwiftUI layer that draws the live template cards and media
//               overlays inside the program frame, plus the UIKit host view
//               that puts the layer on top of the external display stage and
//               the phone's live preview.
//  Thread Safety: Main thread only - UIKit / SwiftUI views.
//

import SwiftUI
import UIKit

// MARK: - LiveOverlayLayerView

/// Draws every live overlay, bottom first, inside a program-aspect frame.
struct LiveOverlayLayerView: View {

    // MARK: - Properties

    @ObservedObject var controller: LiveOverlayController
    /// Program aspect (width / height). nil fills the whole container.
    let programAspect: CGFloat?
    /// Where each overlay is drawn, for surfaces that take touches (the hero).
    var frames: LiveOverlayFrames?

    /// Coordinate space overlays report their frames in (the layer's own).
    static let coordinateSpace = "LiveOverlayLayer"

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let frame = Self.programFrame(in: proxy.size, aspect: programAspect)
            ZStack {
                ForEach(controller.rendered) { overlay in
                    overlayView(overlay, frame: frame)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(.named(Self.coordinateSpace))
            .clipped()
            .onAppear { frames?.contentFrame = frame }
            .onChange(of: frame) { _, next in frames?.contentFrame = next }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: controller.rendered.map(\.id))
    }

    // MARK: - Layout

    /// The aspect-fit program frame inside `size` (centered).
    ///
    /// - Parameters:
    ///   - size: Container size in points.
    ///   - aspect: Program width / height, or nil to use the whole container.
    /// - Returns: The frame overlays are positioned in.
    static func programFrame(in size: CGSize, aspect: CGFloat?) -> CGRect {
        guard let aspect, aspect > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        if size.width / size.height > aspect {
            let width = size.height * aspect
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        }
        let height = size.width / aspect
        return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
    }

    // MARK: - Private

    @ViewBuilder
    private func overlayView(_ overlay: RenderedOverlay, frame: CGRect) -> some View {
        switch overlay {
        case .card(let card):
            PlacedCardOverlay(config: card.config, contentFrame: frame) { rect in
                frames?.frames[overlay.id] = rect
            }
            .transition(.opacity)
        case .media(let entry):
            PlacedMediaOverlay(entry: entry, contentFrame: frame) { rect in
                frames?.frames[overlay.id] = rect
            }
            .transition(.opacity)
        }
    }
}

// MARK: - LiveOverlayHostView

/// UIKit wrapper that keeps `LiveOverlayLayerView` on top of its superview.
///
/// Usage: add it as the last subview of an output surface, keep its frame equal
/// to the surface bounds, and call `bringToFront()` after other subviews are
/// added. It never takes touches.
final class LiveOverlayHostView: UIView {

    // MARK: - Properties

    private let hosting: UIHostingController<LiveOverlayLayerView>
    /// Where each live overlay is drawn in this view, for touch hit-testing.
    let frames: LiveOverlayFrames

    // MARK: - Initialization

    /// Creates a host drawing `controller`'s overlays (the shared one when nil).
    ///
    /// - Parameter programAspect: Width / height of the program frame inside
    ///   this view, or nil when the view itself is the program frame.
    init(controller: LiveOverlayController? = nil, programAspect: CGFloat? = nil) {
        let frames = LiveOverlayFrames()
        self.frames = frames
        hosting = UIHostingController(rootView: LiveOverlayLayerView(
            controller: controller ?? .shared,
            programAspect: programAspect,
            frames: frames
        ))
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        hosting.view.backgroundColor = .clear
        hosting.view.isUserInteractionEnabled = false
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hosting.view.frame = bounds
        addSubview(hosting.view)
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public Interface

    /// Updates the program aspect the overlays are laid out in.
    func setProgramAspect(_ aspect: CGFloat?) {
        guard hosting.rootView.programAspect != aspect else { return }
        hosting.rootView = LiveOverlayLayerView(
            controller: hosting.rootView.controller,
            programAspect: aspect,
            frames: frames
        )
    }

    /// The topmost live overlay under `point` (this view's coordinates), with
    /// where it is drawn and the program frame it sits in.
    ///
    /// - Parameter slop: Extra points around each overlay that still count.
    func overlay(
        at point: CGPoint, slop: CGFloat = 0
    ) -> (overlay: RenderedOverlay, frame: CGRect, contentFrame: CGRect)? {
        let controller = hosting.rootView.controller
        for overlay in controller.rendered.reversed() {
            guard let frame = frames.frames[overlay.id],
                  frame.insetBy(dx: -slop, dy: -slop).contains(point) else { continue }
            return (overlay, frame, frames.contentFrame)
        }
        return nil
    }

    /// Moves this view above its siblings so overlays always draw on top.
    func bringToFront() {
        superview?.bringSubviewToFront(self)
    }
}

// MARK: - LiveOverlayFrames

/// Where each overlay was last drawn in one overlay layer (plain storage, not
/// observed: it only answers "what is under this finger").
final class LiveOverlayFrames {
    /// Drawn frame per overlay, in the layer's coordinates.
    var frames: [LiveOverlayID: CGRect] = [:]
    /// Program frame the overlays are placed in.
    var contentFrame: CGRect = .zero
}
