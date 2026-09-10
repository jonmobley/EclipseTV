//
//  AspectCropViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Notifies the host when the user finishes or cancels an aspect-ratio crop.
protocol AspectCropDelegate: AnyObject {
    /// - Parameter cropRectInSource: Crop rectangle in the normalized source image's
    ///   point space (top-left origin), useful when applying the same crop to a video.
    func aspectCrop(_ controller: AspectCropViewController,
                    didFinishWith image: UIImage,
                    cropRectInSource: CGRect)
    func aspectCropDidCancel(_ controller: AspectCropViewController)
}

/// Pan/zoom cropper that locks output to a fixed aspect (e.g. 9:16 for Vertical).
///
/// Destructive mode (default): Save returns a cropped bitmap via `AspectCropDelegate`.
/// Framing mode (`onFramingChosen` set): Save reports the crop rect only — the original
/// file is left alone — and a Reset button returns the editor to the default framing
/// (photo fitted and centered) without closing, so the user can adjust or Save from there.
final class AspectCropViewController: UIViewController, UIScrollViewDelegate {

    // MARK: - Properties

    weak var delegate: AspectCropDelegate?

    /// When set, Save reports the crop rect without producing a bitmap, and Reset is shown.
    var onFramingChosen: ((CGRect) -> Void)?

    /// Point-space crop to restore on open (from a previously saved framing).
    var initialCropRect: CGRect?

    let sourceImage: UIImage
    let targetAspect: CGFloat
    private let instruction: String
    private let confirmTitle: String

    let scrollView = UIScrollView()
    let imageView = UIImageView()
    let cropFrameView = UIView()
    let dimView = UIView()
    private let instructionLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)

    /// Layout the scroll metrics currently describe; nil until the first pass.
    var configuredGeometry: AspectCropScrollGeometry?

    /// Region behind the crop window as of the last `viewWillLayoutSubviews`.
    var framedBeforeLayout: CGRect?

    // MARK: - Initialization

    /// - Parameters:
    ///   - image: Source image (any orientation).
    ///   - targetAspect: Desired width ÷ height (use `MediaAspect.vertical` for 9:16).
    ///   - instruction: Optional guidance under the crop frame.
    ///   - confirmTitle: Primary button title (`Add` for new media, `Save` when editing).
    init(image: UIImage,
         targetAspect: CGFloat = MediaAspect.vertical,
         instruction: String = "Drag and pinch to frame your Vertical crop",
         confirmTitle: String = "Add") {
        self.sourceImage = MediaAspect.normalized(image)
        self.targetAspect = targetAspect
        self.instruction = instruction
        self.confirmTitle = confirmTitle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupChrome()
        setupScrollView()
        setupCropFrame()
        setupButtons()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Last chance to read what the user is looking at: this pass can move the crop
        // window (safe-area insets settling after presentation, rotation), and the
        // region behind it moves with it.
        guard configuredGeometry != nil else { return }
        framedBeforeLayout = visibleCropRectInImage()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let framed = framedBeforeLayout
        framedBeforeLayout = nil
        layoutCropFrame()
        updateScrollMetrics(restoring: framed)
        updateDimMask()
    }

    // MARK: - Setup

    private func setupChrome() {
        instructionLabel.text = instruction
        instructionLabel.numberOfLines = 0
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.textColor = .lightGray
        instructionLabel.font = .systemFont(ofSize: 15)
        instructionLabel.textAlignment = .center
        view.addSubview(instructionLabel)
    }

    private func setupScrollView() {
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        // The insets below make the scrollable range exactly "the photo may not leave
        // the crop window", and the minimum zoom keeps the photo at least window-sized.
        // Rubber-banding breaks that promise: a Save taken while the content is bounced
        // past its limit describes a region the photo does not cover.
        scrollView.bounces = false
        scrollView.bouncesZoom = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.decelerationRate = .fast
        // Insets are the crop window's margins; safe-area adjustment would skew them.
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .black
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        imageView.image = sourceImage
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
    }

    private func setupCropFrame() {
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        dimView.isUserInteractionEnabled = false
        dimView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimView)

        cropFrameView.backgroundColor = .clear
        cropFrameView.isUserInteractionEnabled = false
        cropFrameView.layer.borderColor = UIColor.white.cgColor
        cropFrameView.layer.borderWidth = 2
        // Positioned by frame in `layoutCropFrame`, not by constraints.
        view.addSubview(cropFrameView)
    }

    private func setupButtons() {
        styleChromeButton(
            cancelButton,
            title: "Cancel",
            titleColor: .systemRed,
            background: UIColor.systemRed.withAlphaComponent(0.12)
        )
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        styleChromeButton(
            resetButton,
            title: "Reset",
            titleColor: .white,
            background: UIColor.white.withAlphaComponent(0.15)
        )
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        resetButton.isHidden = onFramingChosen == nil

        styleChromeButton(
            confirmButton,
            title: confirmTitle,
            titleColor: .white,
            background: .systemBlue
        )
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)

        var buttons: [UIView] = [cancelButton]
        if onFramingChosen != nil {
            buttons.append(resetButton)
        }
        buttons.append(confirmButton)

        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
            stack.heightAnchor.constraint(equalToConstant: 50),

            instructionLabel.leadingAnchor.constraint(
                equalTo: guide.leadingAnchor, constant: 20
            ),
            instructionLabel.trailingAnchor.constraint(
                equalTo: guide.trailingAnchor, constant: -20
            ),
            instructionLabel.bottomAnchor.constraint(
                equalTo: stack.topAnchor, constant: -16
            ),

            scrollView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(
                equalTo: instructionLabel.topAnchor, constant: -12
            ),

            dimView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)
        ])
    }

    private func styleChromeButton(
        _ button: UIButton,
        title: String,
        titleColor: UIColor,
        background: UIColor
    ) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        button.setTitleColor(titleColor, for: .normal)
        button.backgroundColor = background
        button.layer.applyContinuousCorner(radius: CornerRadii.large)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    // MARK: - Actions

    @objc private func cancelTapped() {
        delegate?.aspectCropDidCancel(self)
    }

    @objc private func resetTapped() {
        resetToDefaultFraming(animated: true)
    }

    @objc private func confirmTapped() {
        let rect = visibleCropRectInImage()
        logSave(saved: rect)
        guard let rect else {
            delegate?.aspectCropDidCancel(self)
            return
        }
        finishConfirm(with: rect)
    }

    /// Reports the framing, or hands back a cropped bitmap for the destructive path.
    private func finishConfirm(with rect: CGRect) {
        if let onFramingChosen {
            onFramingChosen(rect)
            return
        }
        guard let image = MediaAspect.crop(sourceImage, to: rect) else {
            delegate?.aspectCropDidCancel(self)
            return
        }
        delegate?.aspectCrop(self, didFinishWith: image, cropRectInSource: rect)
    }
}
