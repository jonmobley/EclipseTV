//
//  VideoTrimBarView.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Film strip with a yellow frame whose two ends drag to set where a video starts and
/// ends. Dragging inside the frame scrubs the playhead.
final class VideoTrimBarView: UIView {

    enum Edge { case start, end }

    /// Width of each grab handle.
    static let handleWidth: CGFloat = 18
    /// Extra reach around a handle, so a thumb lands on it easily.
    static let handleHitSlop: CGFloat = 22

    private(set) var range: VideoTrimRange
    /// Current playback time, drawn as a white line.
    var playheadTime: Double = 0 {
        didSet { setNeedsLayout() }
    }

    /// A handle moved; the new range is already applied.
    var onRangeChanged: ((VideoTrimRange, Edge) -> Void)?
    /// The playhead was dragged inside the frame.
    var onScrub: ((Double) -> Void)?
    /// A drag started (`true`) or ended (`false`).
    var onDragStateChanged: ((Bool) -> Void)?

    private let stripView = UIStackView()
    private let leftDim = UIView()
    private let rightDim = UIView()
    private let frameView = UIView()
    private let startHandle = UIImageView()
    private let endHandle = UIImageView()
    private let playheadView = UIView()
    private var activeDrag: Edge?

    private lazy var startElement = TrimHandleElement(bar: self, edge: .start)
    private lazy var endElement = TrimHandleElement(bar: self, edge: .end)

    init(range: VideoTrimRange) {
        self.range = range
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    func setRange(_ newRange: VideoTrimRange) {
        range = newRange
        setNeedsLayout()
    }

    /// How many film-strip pictures fit at the current width.
    var preferredThumbnailCount: Int {
        let width = trackRect.width
        let height = max(bounds.height, 1)
        return max(4, min(16, Int((width / (height * 0.75)).rounded(.up))))
    }

    func setThumbnails(_ images: [UIImage]) {
        stripView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for image in images {
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            stripView.addArrangedSubview(view)
        }
    }

    // MARK: - Setup

    private func setup() {
        isAccessibilityElement = false

        stripView.axis = .horizontal
        stripView.distribution = .fillEqually
        stripView.clipsToBounds = true
        stripView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        stripView.layer.cornerRadius = 6
        stripView.isUserInteractionEnabled = false
        addSubview(stripView)

        for dim in [leftDim, rightDim] {
            dim.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            dim.isUserInteractionEnabled = false
            addSubview(dim)
        }

        frameView.isUserInteractionEnabled = false
        frameView.layer.borderColor = UIColor.systemYellow.cgColor
        frameView.layer.borderWidth = 3
        frameView.layer.cornerRadius = 6
        addSubview(frameView)

        let chevron = UIImage.SymbolConfiguration(pointSize: 13, weight: .heavy)
        startHandle.image = UIImage(systemName: "chevron.compact.left", withConfiguration: chevron)
        endHandle.image = UIImage(systemName: "chevron.compact.right", withConfiguration: chevron)
        for handle in [startHandle, endHandle] {
            handle.backgroundColor = .systemYellow
            handle.tintColor = .black
            handle.contentMode = .center
            handle.isUserInteractionEnabled = false
            addSubview(handle)
        }
        startHandle.layer.cornerRadius = 6
        startHandle.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        endHandle.layer.cornerRadius = 6
        endHandle.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]

        playheadView.backgroundColor = .white
        playheadView.layer.cornerRadius = 1.5
        playheadView.layer.shadowColor = UIColor.black.cgColor
        playheadView.layer.shadowOpacity = 0.5
        playheadView.layer.shadowRadius = 2
        playheadView.layer.shadowOffset = .zero
        playheadView.isUserInteractionEnabled = false
        addSubview(playheadView)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    // MARK: - Layout

    /// The part of the bar the video's length maps onto (between the two handles).
    var trackRect: CGRect {
        bounds.insetBy(dx: Self.handleWidth, dy: 0)
    }

    func x(for seconds: Double) -> CGFloat {
        trackRect.minX + range.fraction(of: seconds) * trackRect.width
    }

    func time(atX x: CGFloat) -> Double {
        guard trackRect.width > 0 else { return 0 }
        return range.time(atFraction: (x - trackRect.minX) / trackRect.width)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let track = trackRect
        stripView.frame = track.insetBy(dx: 0, dy: 3)
        let startX = x(for: range.start)
        let endX = x(for: range.end)

        leftDim.frame = CGRect(
            x: stripView.frame.minX, y: stripView.frame.minY,
            width: max(0, startX - stripView.frame.minX), height: stripView.frame.height
        )
        rightDim.frame = CGRect(
            x: endX, y: stripView.frame.minY,
            width: max(0, stripView.frame.maxX - endX), height: stripView.frame.height
        )
        startHandle.frame = CGRect(
            x: startX - Self.handleWidth, y: 0, width: Self.handleWidth, height: bounds.height
        )
        endHandle.frame = CGRect(
            x: endX, y: 0, width: Self.handleWidth, height: bounds.height
        )
        frameView.frame = CGRect(
            x: startX - Self.handleWidth, y: 0,
            width: endX - startX + Self.handleWidth * 2, height: bounds.height
        )
        let playX = x(for: range.clamped(playheadTime))
        playheadView.frame = CGRect(x: playX - 1.5, y: -4, width: 3, height: bounds.height + 8)
        playheadView.isHidden = activeDrag != nil

        startElement.accessibilityFrameInContainerSpace = startHandle.frame
        endElement.accessibilityFrameInContainerSpace = endHandle.frame
    }

    // MARK: - Gestures

    /// Which handle a touch at `x` grabs, preferring the nearer one when both are in reach.
    func edge(atX pointX: CGFloat) -> Edge? {
        let startCenter = x(for: range.start) - Self.handleWidth / 2
        let endCenter = x(for: range.end) + Self.handleWidth / 2
        let reach = Self.handleWidth / 2 + Self.handleHitSlop
        let toStart = abs(pointX - startCenter)
        let toEnd = abs(pointX - endCenter)
        if toStart <= reach, toStart <= toEnd { return .start }
        if toEnd <= reach { return .end }
        return nil
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let location = pan.location(in: self)
        switch pan.state {
        case .began:
            let startLocation = CGPoint(
                x: location.x - pan.translation(in: self).x, y: location.y
            )
            activeDrag = edge(atX: startLocation.x)
            onDragStateChanged?(true)
            if activeDrag != nil {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            fallthrough
        case .changed:
            let seconds = time(atX: location.x)
            switch activeDrag {
            case .start:
                range.setStart(seconds)
                onRangeChanged?(range, .start)
            case .end:
                range.setEnd(seconds)
                onRangeChanged?(range, .end)
            case nil:
                let clamped = range.clamped(seconds)
                playheadTime = clamped
                onScrub?(clamped)
            }
            setNeedsLayout()
        default:
            activeDrag = nil
            setNeedsLayout()
            onDragStateChanged?(false)
        }
    }

    @objc private func handleTap(_ tap: UITapGestureRecognizer) {
        let seconds = range.clamped(time(atX: tap.location(in: self).x))
        playheadTime = seconds
        onScrub?(seconds)
    }

    // MARK: - Accessibility

    override var accessibilityElements: [Any]? {
        get { [startElement, endElement] }
        set { _ = newValue }
    }

    fileprivate func nudge(_ edge: Edge, by seconds: Double) {
        switch edge {
        case .start: range.setStart(range.start + seconds)
        case .end: range.setEnd(range.end + seconds)
        }
        setNeedsLayout()
        onRangeChanged?(range, edge)
    }
}

/// VoiceOver handle: swipe up or down moves that end by one second.
private final class TrimHandleElement: UIAccessibilityElement {
    private weak var bar: VideoTrimBarView?
    private let edge: VideoTrimBarView.Edge

    init(bar: VideoTrimBarView, edge: VideoTrimBarView.Edge) {
        self.bar = bar
        self.edge = edge
        super.init(accessibilityContainer: bar)
        accessibilityTraits = .adjustable
        accessibilityLabel = edge == .start ? "Start" : "End"
    }

    override var accessibilityValue: String? {
        get {
            guard let range = bar?.range else { return nil }
            return VideoTrimRange.label(edge == .start ? range.start : range.end)
        }
        set { _ = newValue }
    }

    override func accessibilityIncrement() { bar?.nudge(edge, by: 1) }
    override func accessibilityDecrement() { bar?.nudge(edge, by: -1) }
}
