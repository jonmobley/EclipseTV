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
        // Generate initial thumbnail at start of video
        generateThumbnail(at: CMTime.zero)
    }
    
    // MARK: - Setup Methods
    
    private func setupImageGenerator() {
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 800, height: 450) // 16:9 aspect ratio
        // Use small tolerance to improve generation success rate
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
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
        guard videoDuration.isValid && !videoDuration.isIndefinite else { return }
        
        let targetTime = CMTime(seconds: Double(sender.value) * videoDuration.seconds, preferredTimescale: videoDuration.timescale)
        currentTime = targetTime
        updateTimeLabel()
        
        // Generate thumbnail at new time
        generateThumbnail(at: targetTime)
    }
    
    @objc private func cancelButtonTapped() {
        delegate?.videoThumbnailPreviewDidCancel(self)
    }
    
    @objc private func useButtonTapped() {
        // If no thumbnail is selected, generate one at current time as fallback
        guard let thumbnail = selectedThumbnail ?? thumbnailImageView.image else {
            // Generate thumbnail at current slider position as last resort
            generateThumbnailForFinalUse()
            return
        }
        
        delegate?.videoThumbnailPreview(self, didFinishWithVideoURL: videoURL, selectedThumbnail: thumbnail)
    }
    
    private func generateThumbnailForFinalUse() {
        let targetTime = CMTime(seconds: Double(scrubberSlider.value) * videoDuration.seconds, preferredTimescale: videoDuration.timescale)
        
        Task {
            // Try multiple fallback times if the current time fails
            let fallbackTimes: [CMTime] = [
                targetTime,
                CMTime(seconds: videoDuration.seconds * 0.1, preferredTimescale: videoDuration.timescale),
                CMTime(seconds: 1.0, preferredTimescale: 600),
                CMTime.zero
            ]
            
            for time in fallbackTimes {
                do {
                    let cgImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                        imageGenerator.generateCGImageAsynchronously(for: time) { cgImage, actualTime, error in
                            if let cgImage = cgImage {
                                continuation.resume(returning: cgImage)
                            } else {
                                continuation.resume(throwing: error ?? NSError(domain: "ThumbnailError", code: -1))
                            }
                        }
                    }
                    
                    let thumbnail = UIImage(cgImage: cgImage)
                    
                    await MainActor.run {
                        self.selectedThumbnail = thumbnail
                        self.delegate?.videoThumbnailPreview(self, didFinishWithVideoURL: self.videoURL, selectedThumbnail: thumbnail)
                    }
                    return
                    
                } catch {
                    continue // Try next fallback time
                }
            }
            
            // If all fallback attempts fail, create a simple placeholder
            await MainActor.run {
                let placeholderImage = UIImage(systemName: "video.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal) ?? UIImage()
                self.delegate?.videoThumbnailPreview(self, didFinishWithVideoURL: self.videoURL, selectedThumbnail: placeholderImage)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateThumbnail(at time: CMTime) {
        Task {
            do {
                // Clamp time to valid range
                let clampedTime = max(CMTime.zero, min(time, videoDuration))
                
                let cgImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                    imageGenerator.generateCGImageAsynchronously(for: clampedTime) { cgImage, actualTime, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let cgImage = cgImage {
                            continuation.resume(returning: cgImage)
                        } else {
                            continuation.resume(throwing: NSError(domain: "ThumbnailError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate thumbnail"]))
                        }
                    }
                }
                
                let thumbnail = UIImage(cgImage: cgImage)
                
                await MainActor.run {
                    self.thumbnailImageView.image = thumbnail
                    self.selectedThumbnail = thumbnail
                }
                
            } catch {
                // Silently fall back to a default frame instead of showing error
                await MainActor.run {
                    self.generateFallbackThumbnail()
                }
            }
        }
    }
    
    private func generateFallbackThumbnail() {
        // Try to generate thumbnail at a safe time (1 second or 10% into video, whichever is smaller)
        let fallbackTime: CMTime
        if videoDuration.isValid && videoDuration.seconds > 0 {
            let safeTime = min(1.0, videoDuration.seconds * 0.1)
            fallbackTime = CMTime(seconds: safeTime, preferredTimescale: videoDuration.timescale)
        } else {
            fallbackTime = CMTime(seconds: 1.0, preferredTimescale: 600)
        }
        
        Task {
            do {
                let cgImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                    imageGenerator.generateCGImageAsynchronously(for: fallbackTime) { cgImage, actualTime, error in
                        if let cgImage = cgImage {
                            continuation.resume(returning: cgImage)
                        } else {
                            continuation.resume(throwing: error ?? NSError(domain: "ThumbnailError", code: -1))
                        }
                    }
                }
                
                let thumbnail = UIImage(cgImage: cgImage)
                
                await MainActor.run {
                    self.thumbnailImageView.image = thumbnail
                    self.selectedThumbnail = thumbnail
                }
                
            } catch {
                // If even fallback fails, just continue with whatever thumbnail we have
                print("Thumbnail generation failed, continuing with existing thumbnail")
            }
        }
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
