//
//  PrompterController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Source of per-frame ticks for the Prompter (a `CADisplayLink` in the app; a fake
/// in tests, which step frames by hand).
@MainActor
protocol PrompterFrameSource: AnyObject {
    var onFrame: ((TimeInterval) -> Void)? { get set }
    func start()
    func stop()
}

/// Where the Prompter reads its script from (`PrompterScriptStore` in the app).
@MainActor
protocol PrompterScriptStoring: AnyObject {
    func script(forShowId showId: UUID) -> String
}

extension PrompterScriptStore: PrompterScriptStoring {}

/// Session state for the Prompter: the bound Show's script, playback, scroll position
/// and the reading anchor both stages follow.
///
/// Mirrors `CountdownController`: one shared instance that keeps running while the
/// operator view is closed, so the output display keeps scrolling. Offsets live in a
/// private "canonical" layout at the operator's font size; stages map the anchor into
/// their own layouts.
@MainActor
final class PrompterController {

    static let shared = PrompterController()

    /// Posted when script, play state, speed, text size, binding or live state change.
    static let didChangeNotification = Notification.Name("PrompterController.didChange")

    /// Posted on every frame the scroll position moves. Only stages and the hero's
    /// line check listen; it never reloads the grid.
    static let offsetDidChangeNotification = Notification.Name("PrompterController.offsetDidChange")

    /// Width the canonical layout wraps at before any stage has reported its size.
    static let defaultStageWidth: CGFloat = 600

    // MARK: - State

    /// Script the operator is working with (`PrompterScriptStore` key: the Show id
    /// for a Show's first Prompter, the tile's own id for an extra one).
    private(set) var boundScriptId: UUID?

    /// Show whose Prompter is on the output display, while `isLive`.
    private(set) var liveShowId: UUID?

    /// Script on the output display, while `isLive`.
    private(set) var liveScriptId: UUID?

    private(set) var isLive = false

    private(set) var script = ""

    private(set) var fontSize: CGFloat

    private(set) var isScrubbing = false

    private(set) var viewportHeight: CGFloat = 0

    private(set) var stageWidth: CGFloat = PrompterController.defaultStageWidth

    private(set) var layout: PrompterTextLayout

    var isPlaying: Bool { engine.isPlaying }

    var speedMultiplier: Double { engine.speed }

    /// Points from the top of the script, in the canonical layout.
    var offset: CGFloat { engine.offset }

    var lineHeight: CGFloat { layout.lineHeight }

    var maxOffset: CGFloat {
        PrompterStageMetrics.maxOffset(contentHeight: layout.contentHeight, lineHeight: lineHeight)
    }

    /// 0 at the top, 1 with the last line on the guide.
    var progress: Double {
        maxOffset > 0 ? Double(min(max(0, engine.offset / maxOffset), 1)) : 0
    }

    /// The character under the reading guide, for stages to follow.
    var readingAnchor: PrompterReadingAnchor {
        layout.anchor(atTextY: engine.offset + lineHeight / 2)
    }

    var canPlay: Bool { !script.isEmpty }

    /// The Prompter's own Vertical choice (see `PrompterLocalSettings.prefersVertical`).
    var prefersVertical: Bool { settings.prefersVertical }

    /// True when the script is laid out on a 9:16 canvas: Display Mode is Vertical, or
    /// the Prompter was switched to Vertical on its own.
    var isVertical: Bool { ExternalOutputSettings.isVerticalMode || settings.prefersVertical }

    /// True when the Prompter is 9:16 although Display Mode is Landscape, so the
    /// display shows it as an upright 9:16 column instead of filling the screen.
    var isVerticalOnLandscapeDisplay: Bool { settings.prefersVertical && !ExternalOutputSettings.isVerticalMode }

    /// Width ÷ height of the Prompter's canvas.
    var canvasAspectRatio: CGFloat {
        isVerticalOnLandscapeDisplay ? 9.0 / 16.0 : ExternalOutputSettings.outputAspectRatio
    }

    // MARK: - Private

    private var engine = PrompterScrollEngine()
    private let frames: PrompterFrameSource
    private let settings: PrompterLocalSettings
    private let scriptStore: PrompterScriptStoring
    private var storeObserver: NSObjectProtocol?

    /// Defaults resolve inside the initializer: default-argument expressions run
    /// outside the main actor, and these are all main-actor types.
    init(
        scriptStore: PrompterScriptStoring? = nil,
        settings: PrompterLocalSettings? = nil,
        frames: PrompterFrameSource? = nil
    ) {
        let settings = settings ?? PrompterLocalSettings()
        let frames = frames ?? DisplayLinkFrameSource()
        self.scriptStore = scriptStore ?? PrompterScriptStore.shared
        self.settings = settings
        self.frames = frames
        self.fontSize = settings.fontSize
        self.engine.speed = settings.scrollSpeed
        self.layout = PrompterTextLayout(
            script: "",
            font: PrompterStageMetrics.font(ofSize: PrompterStageMetrics.stageFontSize(
                canvasFontSize: settings.fontSize,
                textWidth: Self.defaultStageWidth,
                isVertical: false
            )),
            width: Self.defaultStageWidth
        )
        frames.onFrame = { [weak self] dt in self?.tick(deltaTime: dt) }
        storeObserver = NotificationCenter.default.addObserver(
            forName: PrompterScriptStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, let id = note.object as? UUID else { return }
            MainActor.assumeIsolated {
                guard id == self.boundScriptId else { return }
                self.reloadScript()
            }
        }
    }

    // MARK: - Binding

    /// Points the Prompter at a script. Switching scripts starts from the top.
    ///
    /// While live, the output follows: it shows whatever script is bound. A switch to
    /// another Show's Prompter goes through `prepareLive` so `liveShowId` moves too.
    func bind(scriptId: UUID) {
        guard boundScriptId != scriptId else { return }
        boundScriptId = scriptId
        if isLive { liveScriptId = scriptId }
        script = scriptStore.script(forShowId: scriptId)
        engine.reset()
        rebuildLayout(preserving: nil)
        postChange()
        publishOffset()
    }

    /// Re-reads the bound Show's script (after an edit here or a synced one),
    /// keeping the reading position where it was.
    func reloadScript() {
        guard let boundScriptId else { return }
        let next = scriptStore.script(forShowId: boundScriptId)
        guard next != script else { return }
        let anchor = readingAnchor
        script = next
        rebuildLayout(preserving: anchor)
        if !canPlay { pause() }
        postChange()
        publishOffset()
    }

    // MARK: - Transport

    func play() {
        guard canPlay, !engine.isPlaying else { return }
        engine.isPlaying = true
        frames.start()
        postChange()
    }

    func pause() {
        guard engine.isPlaying else { return }
        engine.isPlaying = false
        refreshFrames()
        postChange()
    }

    func toggleRunning() {
        isPlaying ? pause() : play()
    }

    /// Back to the top without changing play state.
    func reset() {
        engine.reset()
        publishOffset()
    }

    /// Moves `count` lines down (negative = up) and lands on a line.
    func nudge(lines count: Int) {
        engine.setOffset(engine.offset + CGFloat(count) * lineHeight)
        engine.clamp(to: maxOffset)
        engine.setOffset(engine.nearestCenteredOffset(lineHeight: lineHeight, maxOffset: maxOffset))
        publishOffset()
    }

    func setSpeed(_ multiplier: Double) {
        let next = PrompterStageMetrics.clampedSpeed(multiplier)
        guard next != engine.speed else { return }
        engine.speed = next
        settings.scrollSpeed = next
        postChange()
    }

    /// Text size in canvas points; the operator card and the display scale it alike.
    func setFontSize(_ size: CGFloat) {
        let next = PrompterStageMetrics.clampedCanvasFontSize(size)
        guard next != fontSize else { return }
        let anchor = readingAnchor
        fontSize = next
        settings.fontSize = next
        rebuildLayout(preserving: anchor)
        postChange()
        publishOffset()
    }

    /// Switches the Prompter between its own Vertical (9:16) and Landscape shape.
    /// The reading position is kept.
    func setPrefersVertical(_ vertical: Bool) {
        guard vertical != settings.prefersVertical else { return }
        let anchor = readingAnchor
        settings.prefersVertical = vertical
        rebuildLayout(preserving: anchor)
        postChange()
        publishOffset()
    }

    /// The operator stage reports its text width and height so the canonical layout
    /// wraps like the stage does. The reading position is kept.
    func updateStage(width: CGFloat, viewportHeight: CGFloat) {
        let nextWidth = max(1, width)
        guard nextWidth != stageWidth || viewportHeight != self.viewportHeight else { return }
        let anchor = readingAnchor
        stageWidth = nextWidth
        self.viewportHeight = viewportHeight
        rebuildLayout(preserving: anchor)
        publishOffset()
    }

    // MARK: - Scrubbing

    func beginScrub() {
        isScrubbing = true
        engine.velocity = 0
        engine.isSettling = false
        frames.start()
    }

    /// Positive `deltaY` is a finger dragging down (rewind).
    func scrub(by deltaY: CGFloat) {
        guard isScrubbing else { return }
        engine.applyScrollDelta(deltaY, synthesizesMomentum: false)
        engine.clamp(to: maxOffset)
        publishOffset()
    }

    /// `velocity` is the pan velocity in points/s (positive = finger moving down).
    func endScrub(velocity: CGFloat) {
        guard isScrubbing else { return }
        isScrubbing = false
        engine.release(velocity: -velocity)
        engine.beginSettleToCenter()
        frames.start()
    }

    // MARK: - Live

    /// The output display is about to show `scriptId`, one of `showId`'s Prompters.
    func prepareLive(showId: UUID, scriptId: UUID) {
        bind(scriptId: scriptId)
        liveShowId = showId
        liveScriptId = scriptId
        isLive = true
        postChange()
    }

    /// The output display stopped showing the script. Position and play state are
    /// kept so the operator can resume where they were.
    func endLive() {
        guard isLive else { return }
        isLive = false
        liveShowId = nil
        liveScriptId = nil
        postChange()
    }

    // MARK: - Ticking

    /// One frame of playback / coasting. Public so tests can step time by hand.
    func tick(deltaTime: TimeInterval) {
        if !isScrubbing {
            engine.advance(by: deltaTime)
        }
        let keepInteracting = engine.tickInteraction(
            deltaTime: deltaTime,
            lineHeight: lineHeight,
            maxOffset: maxOffset,
            scrubDetent: isScrubbing
        )
        // Seeking can sit at the end; only playback itself auto-pauses there.
        if maxOffset > 0,
           engine.offset >= maxOffset,
           engine.isPlaying,
           !isScrubbing,
           !keepInteracting {
            engine.isPlaying = false
            postChange()
        }
        publishOffset()
        if !engine.isPlaying, !keepInteracting, !isScrubbing {
            frames.stop()
        }
    }

    // MARK: - Private helpers

    private func refreshFrames() {
        if engine.isPlaying || engine.needsInteractionTicks || isScrubbing {
            frames.start()
        } else {
            frames.stop()
        }
    }

    private func rebuildLayout(preserving anchor: PrompterReadingAnchor?) {
        let pointSize = PrompterStageMetrics.stageFontSize(
            canvasFontSize: fontSize,
            textWidth: stageWidth,
            isVertical: isVertical
        )
        layout = PrompterTextLayout(
            script: script,
            font: PrompterStageMetrics.font(ofSize: pointSize),
            width: stageWidth
        )
        if let anchor {
            engine.setOffset(layout.textY(for: anchor) - lineHeight / 2)
        }
        engine.clamp(to: maxOffset)
    }

    private var lastPublishedOffset: CGFloat = -1

    private func publishOffset() {
        guard engine.offset != lastPublishedOffset else { return }
        lastPublishedOffset = engine.offset
        NotificationCenter.default.post(name: Self.offsetDidChangeNotification, object: self)
    }

    private func postChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

// MARK: - DisplayLinkFrameSource

/// `CADisplayLink` ticks on the main run loop, with the frame delta clamped so a
/// hitch or a return from the background never leaps the script forward.
@MainActor
final class DisplayLinkFrameSource: PrompterFrameSource {

    /// Longest step one frame may advance (a 20 fps floor).
    static let maximumFrameInterval: TimeInterval = 1.0 / 20

    var onFrame: ((TimeInterval) -> Void)?

    private var link: CADisplayLink?

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let dt = min(max(link.targetTimestamp - link.timestamp, 0), Self.maximumFrameInterval)
        onFrame?(dt)
    }
}
