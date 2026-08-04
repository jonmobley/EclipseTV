//
//  VideoThumbnailPreviewViewController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import AVFoundation

protocol VideoThumbnailPreviewDelegate: AnyObject {
    func videoThumbnailPreview(_ controller: VideoThumbnailPreviewViewController, didFinishWithVideoURL videoURL: URL, selectedThumbnail: UIImage)
    func videoThumbnailPreviewDidCancel(_ controller: VideoThumbnailPreviewViewController)
}

class VideoThumbnailPreviewViewController: UIViewController {
    
    // MARK: - Properties
    
    weak var delegate: VideoThumbnailPreviewDelegate?
    private let videoURL: URL
    private var asset: AVAsset
    private var imageGenerator: AVAssetImageGenerator
    private var videoDuration: CMTime = .zero
    private var currentTime: CMTime = .zero
    private var selectedThumbnail: UIImage?
    /// Bumps on every scrub request so stale generator callbacks never paint.
    private var scrubGeneration: UInt64 = 0

    private static let scrubPreviewSize = CGSize(width: 480, height: 270)
    private static let finalThumbnailSize = CGSize(width: 800, height: 450)

    // MARK: - UI Elements
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        return view
    }()
    
    private let thumbnailImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        return imageView
    }()
    
    private let scrubberSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = 0
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = .systemGray4
        slider.thumbTintColor = .white
        return slider
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.text = "00:00 / 00:00"
        return label
    }()
    
    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.textColor = .lightGray
        label.font = UIFont.systemFont(ofSize: 16)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "Drag the slider to choose a thumbnail frame for your video"
        return label
    }()
    
    private let buttonStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 16
        return stack
    }()
    
    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Cancel", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        button.setTitleColor(.systemRed, for: .normal)
        button.backgroundColor = UIColor.systemRed.withAlphaComponent(0.1)
        button.layer.cornerRadius = 25
        return button
    }()
    
    private let useButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Use This Frame", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemBlue
        button.layer.cornerRadius = 25
        return button
    }()
    
    // MARK: - Initialization
    
    init(videoURL: URL) {
        self.videoURL = videoURL
        self.asset = AVURLAsset(url: videoURL)
        self.imageGenerator = AVAssetImageGenerator(asset: asset)
        super.init(nibName: nil, bundle: nil)
        
        setupImageGenerator()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActions()
        loadVideoInfo()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        generateThumbnail(at: .zero, exact: false)
    }

    deinit {
        imageGenerator.cancelAllCGImageGeneration()
    }

    // MARK: - Setup Methods

    private func setupImageGenerator() {
        imageGenerator.appliesPreferredTrackTransform = true
        configureGeneratorForScrubbing()
    }

    /// Fast keyframe-friendly settings for live scrubbing.
    private func configureGeneratorForScrubbing() {
        imageGenerator.maximumSize = Self.scrubPreviewSize
        imageGenerator.requestedTimeToleranceBefore = .positiveInfinity
        imageGenerator.requestedTimeToleranceAfter = .positiveInfinity
    }

    /// Tighter seek + full resolution for finger-up / confirm.
    private func configureGeneratorForExactFrame() {
        imageGenerator.maximumSize = Self.finalThumbnailSize
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        
        // Add subviews
        view.addSubview(containerView)
        containerView.addSubview(thumbnailImageView)
        containerView.addSubview(instructionLabel)
        containerView.addSubview(scrubberSlider)
        containerView.addSubview(timeLabel)
        containerView.addSubview(buttonStackView)
        
        buttonStackView.addArrangedSubview(cancelButton)
        buttonStackView.addArrangedSubview(useButton)
        
        // Setup constraints
        containerView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        scrubberSlider.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Container
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.9),
            containerView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.8),
            
            // Thumbnail image
            thumbnailImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            thumbnailImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            thumbnailImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            thumbnailImageView.heightAnchor.constraint(equalTo: thumbnailImageView.widthAnchor, multiplier: 9.0/16.0),
            
            // Instruction label
            instructionLabel.topAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor, constant: 16),
            instructionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Scrubber slider
            scrubberSlider.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 20),
            scrubberSlider.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            scrubberSlider.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            scrubberSlider.heightAnchor.constraint(equalToConstant: 44),
            
            // Time label
            timeLabel.topAnchor.constraint(equalTo: scrubberSlider.bottomAnchor, constant: 8),
            timeLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            timeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            
            // Button stack
            buttonStackView.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 24),
            buttonStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            buttonStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            buttonStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20),
            buttonStackView.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    private func setupActions() {
        scrubberSlider.addTarget(self, action: #selector(scrubberValueChanged(_:)), for: .valueChanged)
        scrubberSlider.addTarget(
            self,
            action: #selector(scrubberTouchEnded(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        useButton.addTarget(self, action: #selector(useButtonTapped), for: .touchUpInside)
    }
    
    private func loadVideoInfo() {
        Task {
            do {
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    self.videoDuration = duration
                    self.updateTimeLabel()
                }
            } catch {
                await MainActor.run {
                    self.showError("Unable to load video information")
                }
            }
        }
    }
    
    // MARK: - Actions

    @objc private func scrubberValueChanged(_ sender: UISlider) {
        guard let time = timeForSliderValue(sender.value) else { return }
        currentTime = time
        updateTimeLabel()
        generateThumbnail(at: time, exact: false)
    }

    @objc private func scrubberTouchEnded(_ sender: UISlider) {
        guard let time = timeForSliderValue(sender.value) else { return }
        currentTime = time
        updateTimeLabel()
        // Snap to a nearer frame at full resolution once the finger lifts.
        generateThumbnail(at: time, exact: true)
    }

    @objc private func cancelButtonTapped() {
        imageGenerator.cancelAllCGImageGeneration()
        delegate?.videoThumbnailPreviewDidCancel(self)
    }

    @objc private func useButtonTapped() {
        // Always regenerate exact/high-res at the slider position before finishing.
        generateThumbnailForFinalUse()
    }

    private func generateThumbnailForFinalUse() {
        let targetTime = timeForSliderValue(scrubberSlider.value) ?? currentTime
        scrubGeneration &+= 1
        let id = scrubGeneration
        imageGenerator.cancelAllCGImageGeneration()
        configureGeneratorForExactFrame()

        let fallbackTimes: [CMTime] = [
            targetTime,
            CMTime(seconds: max(videoDuration.seconds * 0.1, 0), preferredTimescale: 600),
            CMTime(seconds: 1.0, preferredTimescale: 600),
            .zero
        ]

        requestExactThumbnail(from: fallbackTimes, generation: id)
    }

    /// Tries each time until one succeeds, then finishes via the delegate.
    private func requestExactThumbnail(from times: [CMTime], generation: UInt64, index: Int = 0) {
        guard generation == scrubGeneration else { return }
        guard index < times.count else {
            let placeholder = UIImage(systemName: "video.fill")?
                .withTintColor(.white, renderingMode: .alwaysOriginal) ?? UIImage()
            selectedThumbnail = placeholder
            delegate?.videoThumbnailPreview(
                self, didFinishWithVideoURL: videoURL, selectedThumbnail: placeholder
            )
            return
        }

        let clamped = clampedTime(times[index])
        imageGenerator.generateCGImageAsynchronously(for: clamped) { [weak self] cgImage, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard generation == self.scrubGeneration else { return }
                if let cgImage, error == nil {
                    let thumbnail = UIImage(cgImage: cgImage)
                    self.thumbnailImageView.image = thumbnail
                    self.selectedThumbnail = thumbnail
                    self.delegate?.videoThumbnailPreview(
                        self, didFinishWithVideoURL: self.videoURL, selectedThumbnail: thumbnail
                    )
                    return
                }
                self.requestExactThumbnail(
                    from: times, generation: generation, index: index + 1
                )
            }
        }
    }

    // MARK: - Helper Methods

    /// Cancels in-flight work and requests a frame. Scrub uses loose tolerance;
    /// `exact` tightens seek for finger-up / confirm. Stale callbacks are dropped.
    private func generateThumbnail(at time: CMTime, exact: Bool) {
        scrubGeneration &+= 1
        let id = scrubGeneration
        imageGenerator.cancelAllCGImageGeneration()
        if exact {
            configureGeneratorForExactFrame()
        } else {
            configureGeneratorForScrubbing()
        }

        let clamped = clampedTime(time)
        imageGenerator.generateCGImageAsynchronously(for: clamped) { [weak self] cgImage, _, error in
            guard let self, let cgImage, error == nil else { return }
            DispatchQueue.main.async {
                guard id == self.scrubGeneration else { return }
                let thumbnail = UIImage(cgImage: cgImage)
                self.thumbnailImageView.image = thumbnail
                self.selectedThumbnail = thumbnail
            }
        }
    }

    private func timeForSliderValue(_ value: Float) -> CMTime? {
        guard videoDuration.isValid, !videoDuration.isIndefinite else { return nil }
        return CMTime(
            seconds: Double(value) * videoDuration.seconds,
            preferredTimescale: videoDuration.timescale
        )
    }

    private func clampedTime(_ time: CMTime) -> CMTime {
        guard videoDuration.isValid, !videoDuration.isIndefinite else {
            return max(time, .zero)
        }
        return max(.zero, min(time, videoDuration))
    }
    
    private func updateTimeLabel() {
        let currentSeconds = currentTime.isValid ? currentTime.seconds : 0
        let totalSeconds = videoDuration.isValid ? videoDuration.seconds : 0
        
        let currentText = formatTime(currentSeconds)
        let totalText = formatTime(totalSeconds)
        
        timeLabel.text = "\(currentText) / \(totalText)"
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    private func showError(_ message: String) {
        // Prevent multiple alerts from being presented
        guard presentedViewController == nil else { return }
        
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
