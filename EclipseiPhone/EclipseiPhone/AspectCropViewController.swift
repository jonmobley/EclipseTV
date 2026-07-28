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
final class AspectCropViewController: UIViewController, UIScrollViewDelegate {

    // MARK: - Properties

    weak var delegate: AspectCropDelegate?

    private let sourceImage: UIImage
    private let targetAspect: CGFloat
    private let instruction: String
    private let confirmTitle: String

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let cropFrameView = UIView()
    private let dimView = UIView()
    private let instructionLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)

    private var cropFrameConstraints: [NSLayoutConstraint] = []

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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCropFrame()
        updateScrollMetricsIfNeeded()
        updateDimMask()
    }

    // MARK: - Setup

    private func setupChrome() {
        instructionLabel.text = instruction
        instructionLabel.textColor = .lightGray
        instructionLabel.font = .systemFont(ofSize: 15)
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)
    }

    private func setupScrollView() {
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
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
        cropFrameView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cropFrameView)
    }

    private func setupButtons() {
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        cancelButton.setTitleColor(.systemRed, for: .normal)
        cancelButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.12)
        cancelButton.layer.cornerRadius = 25
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        confirmButton.setTitle(confirmTitle, for: .normal)
        confirmButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        confirmButton.setTitleColor(.white, for: .normal)
        confirmButton.backgroundColor = .systemBlue
        confirmButton.layer.cornerRadius = 25
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [cancelButton, confirmButton])
        stack.axis = .horizontal
        stack.spacing = 16
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
            stack.heightAnchor.constraint(equalToConstant: 50),

            instructionLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            instructionLabel.bottomAnchor.constraint(equalTo: stack.topAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: instructionLabel.topAnchor, constant: -12),

            dimView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)
        ])
    }

    private func layoutCropFrame() {
        NSLayoutConstraint.deactivate(cropFrameConstraints)
        let maxW = scrollView.bounds.width - 32
        let maxH = scrollView.bounds.height - 32
        guard maxW > 0, maxH > 0 else { return }

        var cropW = maxW
        var cropH = cropW / targetAspect
        if cropH > maxH {
            cropH = maxH
            cropW = cropH * targetAspect
        }

        cropFrameConstraints = [
            cropFrameView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            cropFrameView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            cropFrameView.widthAnchor.constraint(equalToConstant: cropW),
            cropFrameView.heightAnchor.constraint(equalToConstant: cropH)
        ]
        NSLayoutConstraint.activate(cropFrameConstraints)
        view.layoutIfNeeded()
    }

    private var didConfigureScroll = false

    private func updateScrollMetricsIfNeeded() {
        guard !didConfigureScroll, scrollView.bounds.width > 0 else { return }
        let crop = cropFrameView.frame
        guard crop.width > 0, crop.height > 0 else { return }
        didConfigureScroll = true

        let imageSize = sourceImage.size
        imageView.frame = CGRect(origin: .zero, size: imageSize)
        scrollView.contentSize = imageSize

        let scaleW = crop.width / imageSize.width
        let scaleH = crop.height / imageSize.height
        let minZoom = max(scaleW, scaleH)
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = max(minZoom * 4, minZoom + 0.01)
        scrollView.zoomScale = minZoom

        // Center the image in the crop window.
        let scaled = CGSize(width: imageSize.width * minZoom, height: imageSize.height * minZoom)
        let offsetX = max((scaled.width - crop.width) / 2, 0)
        let offsetY = max((scaled.height - crop.height) / 2, 0)
        let cropInScroll = scrollView.convert(crop, from: view)
        scrollView.contentInset = UIEdgeInsets(
            top: cropInScroll.minY,
            left: cropInScroll.minX,
            bottom: scrollView.bounds.height - cropInScroll.maxY,
            right: scrollView.bounds.width - cropInScroll.maxX
        )
        scrollView.contentOffset = CGPoint(
            x: offsetX - scrollView.contentInset.left,
            y: offsetY - scrollView.contentInset.top
        )
    }

    private func updateDimMask() {
        let crop = cropFrameView.frame
        guard dimView.bounds.width > 0, crop.width > 0 else { return }
        let path = UIBezierPath(rect: dimView.bounds)
        let cropInDim = dimView.convert(crop, from: view)
        path.append(UIBezierPath(rect: cropInDim))
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        mask.fillRule = .evenOdd
        dimView.layer.mask = mask
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // Keep content fillable within crop via insets; no extra centering needed.
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        delegate?.aspectCropDidCancel(self)
    }

    @objc private func confirmTapped() {
        guard let result = croppedResult() else {
            delegate?.aspectCropDidCancel(self)
            return
        }
        delegate?.aspectCrop(self, didFinishWith: result.image, cropRectInSource: result.rect)
    }

    /// Maps the visible crop frame into image point space and crops.
    private func croppedResult() -> (image: UIImage, rect: CGRect)? {
        let cropInScroll = scrollView.convert(cropFrameView.frame, from: view)
        let scale = scrollView.zoomScale
        guard scale > 0 else { return nil }
        let imageRect = CGRect(
            x: (cropInScroll.origin.x + scrollView.contentOffset.x) / scale,
            y: (cropInScroll.origin.y + scrollView.contentOffset.y) / scale,
            width: cropInScroll.width / scale,
            height: cropInScroll.height / scale
        )
        let bounds = CGRect(origin: .zero, size: sourceImage.size)
        let clamped = imageRect.intersection(bounds)
        guard clamped.width > 1, clamped.height > 1,
              let image = MediaAspect.crop(sourceImage, to: clamped) else { return nil }
        return (image, clamped)
    }
}
