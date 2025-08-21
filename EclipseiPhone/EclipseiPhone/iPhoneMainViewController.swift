import UIKit
import MultipeerConnectivity
import Photos
import PhotosUI
import AVFoundation
import os

class iPhoneMainViewController: UIViewController {
    
    // MARK: - UI Elements
    
    private let connectionStatusContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let connectionStatusIcon: UIImageView = {
        let imageView = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        imageView.image = UIImage(systemName: "dot.radiowaves.left.and.right", withConfiguration: config)
        imageView.tintColor = .lightGray
        imageView.contentMode = .scaleAspectFit
        imageView.alpha = 0 // Start hidden
        return imageView
    }()
    
    private let connectionActivityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .lightGray
        return indicator
    }()
    
    private let connectionStatusLabel: UILabel = {
        let label = UILabel()
        label.text = "Connecting..."
        label.textColor = .lightGray
        label.font = UIFont.systemFont(ofSize: 14)
        label.textAlignment = .center
        return label
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Eclipse"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        return label
    }()
    
    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Open the Eclipse app on your AppleTV to connect"
        label.textColor = .lightGray
        label.font = UIFont.systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 16)
        label.numberOfLines = 0
        label.alpha = 0
        return label
    }()
    
    private let mediaPickerButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Select Media", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.alpha = 0.5 // Start disabled
        button.isEnabled = false
        return button
    }()
    
    private let selectedImagesCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 80, height: 80)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        return collectionView
    }()
    
    private let selectedImagesLabel: UILabel = {
        let label = UILabel()
        label.text = "Selected Images"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.isHidden = true
        return label
    }()
    
    private let sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Send to Apple TV", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemOrange
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.isEnabled = false
        button.alpha = 0.5
        button.isHidden = true
        return button
    }()
    
    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Cancel", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        button.backgroundColor = .systemRed
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.alpha = 0
        button.isHidden = true
        return button
    }()
    
    // MARK: - Properties
    
    private let connectionManager = iPhoneConnectionManager()
    private var selectedPeer: MCPeerID?
    private var selectedImages = [UIImage]()
    private var autoConnectTimer: Timer?
    private var isShowingPicker = false // Track if we're showing the image picker
    private var isReconnecting = false
    private var statusFadeTimer: Timer?
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "MainViewController")
    private var isSendingVideo = false // Track if we're currently sending a video
    private var currentTempFileURL: URL? // Track temp files for cleanup
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCollectionView()
        setupConnectionManager()
        setupNotificationObservers()
        
        navigationController?.isNavigationBarHidden = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Only start searching if we're not in the middle of picking images
        if !isShowingPicker {
            startSearching()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Only invalidate timers if we're not going to the image picker
        if !isShowingPicker {
            invalidateAllTimers()
        }
        
        // Clean up any remaining temp files if view is disappearing
        if let tempURL = currentTempFileURL {
            cleanupTempFile(at: tempURL)
            currentTempFileURL = nil
        }
        
        // Only stop searching if we're not going to the image picker
        // This way, we maintain our connection while picking images
        if !isShowingPicker {
            stopSearching()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        invalidateAllTimers()
        
        // Clean up any remaining temp files
        if let tempURL = currentTempFileURL {
            cleanupTempFile(at: tempURL)
        }
    }
    
    // MARK: - Setup
    
    private func setupNotificationObservers() {
        // Monitor app state changes to maintain connection
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func handleAppWillEnterForeground() {
        print("App will enter foreground")
        // Don't start searching yet, wait for didBecomeActive
    }
    
    @objc private func handleAppDidBecomeActive() {
        print("App did become active")
        
        // Check if we need to reconnect
        if selectedPeer != nil && !isConnected() {
            // We have a selected peer but no active connection, try to reconnect
            updateConnectedState(false, peer: nil)
            startSearching()
        }
    }
    
    @objc private func handleAppDidEnterBackground() {
        print("App did enter background")
        // Pause timers when entering background to save battery
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
        // Keep status fade timer running as it's short-lived
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Add subviews
        view.addSubview(connectionStatusContainer)
        connectionStatusContainer.addSubview(connectionStatusIcon)
        connectionStatusContainer.addSubview(connectionActivityIndicator)
        view.addSubview(connectionStatusLabel)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(statusLabel)
        view.addSubview(mediaPickerButton)
        view.addSubview(selectedImagesCollectionView)
        view.addSubview(selectedImagesLabel)
        view.addSubview(sendButton)
        view.addSubview(cancelButton)
        
        // Setup constraints
        connectionStatusContainer.translatesAutoresizingMaskIntoConstraints = false
        connectionStatusIcon.translatesAutoresizingMaskIntoConstraints = false
        connectionActivityIndicator.translatesAutoresizingMaskIntoConstraints = false
        connectionStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        mediaPickerButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Connection status container
            connectionStatusContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            connectionStatusContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            connectionStatusContainer.widthAnchor.constraint(equalToConstant: 36),
            connectionStatusContainer.heightAnchor.constraint(equalToConstant: 36),
            
            // Connection status icon and activity indicator (centered in container)
            connectionStatusIcon.centerXAnchor.constraint(equalTo: connectionStatusContainer.centerXAnchor),
            connectionStatusIcon.centerYAnchor.constraint(equalTo: connectionStatusContainer.centerYAnchor),
            connectionStatusIcon.widthAnchor.constraint(equalToConstant: 36),
            connectionStatusIcon.heightAnchor.constraint(equalToConstant: 36),
            
            connectionActivityIndicator.centerXAnchor.constraint(equalTo: connectionStatusContainer.centerXAnchor),
            connectionActivityIndicator.centerYAnchor.constraint(equalTo: connectionStatusContainer.centerYAnchor),
            
            // Connection status label
            connectionStatusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            connectionStatusLabel.topAnchor.constraint(equalTo: connectionStatusContainer.bottomAnchor, constant: 8),
            
            // Center the title and subtitle in the middle of the screen
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),
            
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            // Position status label and activity indicator below the subtitle
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            // Position the media picker button at the bottom
            mediaPickerButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mediaPickerButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            mediaPickerButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            mediaPickerButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            mediaPickerButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Position cancel button above media picker button
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: mediaPickerButton.topAnchor, constant: -16),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            cancelButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Start with activity indicator
        connectionActivityIndicator.startAnimating()
        
        mediaPickerButton.addTarget(self, action: #selector(mediaPickerButtonTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        
        // Initially disable the media picker button until connected
        mediaPickerButton.isEnabled = false
        mediaPickerButton.alpha = 0.5
        mediaPickerButton.backgroundColor = .lightGray
    }
    
    private func setupCollectionView() {
        selectedImagesCollectionView.dataSource = self
        selectedImagesCollectionView.delegate = self
        selectedImagesCollectionView.register(ImagePreviewCell.self, forCellWithReuseIdentifier: "ImagePreviewCell")
    }
    
    private func setupConnectionManager() {
        connectionManager.delegate = self
    }
    
    // MARK: - Helper Methods
    
    private func showVideoThumbnailPreview(for videoURL: URL) {
        let previewController = VideoThumbnailPreviewViewController(videoURL: videoURL)
        previewController.delegate = self
        previewController.modalPresentationStyle = .overFullScreen
        present(previewController, animated: true)
    }
    
    private func isConnected() -> Bool {
        guard let peer = selectedPeer else {
            return false
        }
        
        // Ask connection manager if we're connected to this peer
        return connectionManager.isConnectedToPeer(peer)
    }
    
    private func showTemporaryStatus(_ message: String, duration: TimeInterval = 3.0) {
        // Cancel any existing timer safely
        statusFadeTimer?.invalidate()
        statusFadeTimer = nil
        
        // Show the message
        DispatchQueue.main.async {
            self.statusLabel.text = message
            self.statusLabel.alpha = 1.0
            
            // Create a timer to fade out the message with weak self
            self.statusFadeTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] timer in
                timer.invalidate()
                UIView.animate(withDuration: 0.5) {
                    self?.statusLabel.alpha = 0
                }
                self?.statusFadeTimer = nil
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func invalidateAllTimers() {
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
        statusFadeTimer?.invalidate()
        statusFadeTimer = nil
    }
    
    private func cleanupTempFile(at url: URL) {
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.removeItem(at: url)
                print("🗑️ Cleaned up temp file: \(url.lastPathComponent)")
            } catch {
                print("⚠️ Failed to cleanup temp file: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func mediaPickerButtonTapped() {
        guard let selectedPeer = selectedPeer, connectionManager.isConnectedToPeer(selectedPeer) else {
            showTemporaryStatus("Please connect to Apple TV first")
            return
        }
        
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        // Add Image option
        alertController.addAction(UIAlertAction(title: "Image", style: .default) { [weak self] _ in
            self?.showImagePicker()
        })
        
        // Add Video option
        alertController.addAction(UIAlertAction(title: "Video", style: .default) { [weak self] _ in
            self?.showVideoPicker()
        })
        
        // Add Cancel option
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad, we need to set the source view and rect
        if let popoverController = alertController.popoverPresentationController {
            popoverController.sourceView = mediaPickerButton
            popoverController.sourceRect = mediaPickerButton.bounds
        }
        
        present(alertController, animated: true)
    }
    
    private func showImagePicker() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"] // Only show images
        present(picker, animated: true)
    }
    
    private func showVideoPicker() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.movie"] // Only show videos
        present(picker, animated: true)
    }
    
    @objc private func cancelButtonTapped() {
        // Cancel the current transfer
        connectionManager.cancelCurrentTransfer()
        
        // Reset UI
        hideTransferUI()
        
        // Show cancellation message
        statusLabel.text = "Transfer cancelled"
        UIView.animate(withDuration: 0.3) {
            self.statusLabel.alpha = 1.0
        } completion: { _ in
            // Fade out the message after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                UIView.animate(withDuration: 0.3) {
                    self.statusLabel.alpha = 0
                }
            }
        }
    }
    
    private func showTransferUI() {
        // Show initial status
        statusLabel.text = "Preparing to send..."
        UIView.animate(withDuration: 0.3) {
            self.statusLabel.alpha = 1.0
            self.cancelButton.alpha = 1.0
            // Fade out connection status while transferring
            self.connectionStatusContainer.alpha = 0.3
            self.connectionStatusLabel.alpha = 0.3
        }
        cancelButton.isHidden = false
        
        // Disable media picker button while sending
        mediaPickerButton.isEnabled = false
        mediaPickerButton.alpha = 0.5
    }
    
    private func hideTransferUI() {
        UIView.animate(withDuration: 0.3) {
            self.statusLabel.alpha = 0
            self.cancelButton.alpha = 0
            // Restore connection status visibility
            self.connectionStatusContainer.alpha = 1.0
            self.connectionStatusLabel.alpha = 1.0
        } completion: { _ in
            self.cancelButton.isHidden = true
            self.mediaPickerButton.isEnabled = true
            self.mediaPickerButton.alpha = 1.0
            
            // Clean up temp file when transfer UI is hidden
            if let tempURL = self.currentTempFileURL {
                self.cleanupTempFile(at: tempURL)
                self.currentTempFileURL = nil
            }
        }
    }
    
    private func sendMediaToAppleTV(_ mediaURL: URL) {
        // Remove aspect ratio check: allow all videos
        // Show transfer UI
        showTransferUI()
        // Send the media
        let success = connectionManager.sendVideoData(mediaURL)
        if !success {
            // Handle failure
            statusLabel.text = "Failed to send media"
            hideTransferUI()
            isSendingVideo = false
        }
    }
    
    private func sendImageToAppleTV(_ image: UIImage) {
        guard selectedPeer != nil else { return }
        
        // Show processing UI if image is large
        let largestSide = max(image.size.width, image.size.height)
        let isLargeImage = largestSide > 3840
        
        if isLargeImage {
            DispatchQueue.main.async {
                self.statusLabel.text = "Processing image..."
                self.statusLabel.alpha = 1.0
                self.showTransferUI()
                self.connectionActivityIndicator.startAnimating()
            }
        }
        
        // Process image on background queue for large images
        let processQueue = isLargeImage ? DispatchQueue.global(qos: .userInitiated) : DispatchQueue.main
        
        processQueue.async {
            // Save image to a temporary file
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "temp_image_\(UUID().uuidString).jpg"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                DispatchQueue.main.async {
                    self.showTemporaryStatus("Failed to prepare image for sending")
                    self.hideTransferUI()
                    self.connectionActivityIndicator.stopAnimating()
                }
                return
            }
            
            do {
                try imageData.write(to: fileURL)
            } catch {
                DispatchQueue.main.async {
                    self.showTemporaryStatus("Failed to save image for sending")
                    self.hideTransferUI()
                    self.connectionActivityIndicator.stopAnimating()
                }
                return
            }
            
            DispatchQueue.main.async {
                // Store temp file URL for cleanup
                self.currentTempFileURL = fileURL
                
                // Update status for sending
                if isLargeImage {
                    self.statusLabel.text = "Sending optimized image..."
                } else {
                    // Show transfer UI for smaller images
                    self.showTransferUI()
                    self.connectionActivityIndicator.startAnimating()
                }
                
                // Send the image as a resource
                let success = self.connectionManager.sendImage(at: fileURL)
                if !success {
                    self.showTemporaryStatus("Failed to send image. Please try again.")
                    self.hideTransferUI()
                    self.connectionActivityIndicator.stopAnimating()
                    // Clean up temp file if sending failed
                    self.cleanupTempFile(at: fileURL)
                    self.currentTempFileURL = nil
                }
            }
        }
    }
    
    // MARK: - Connection Methods
    
    private func startSearching() {
        if isReconnecting {
            return // Don't interfere with active reconnection
        }
    
        // Check if we already have a connection
        if isConnected() {
            // Already connected, just update UI
            updateConnectedState(true, peer: selectedPeer)
            return
        }
        
        // Update UI to show searching
        connectionStatusIcon.tintColor = .lightGray
        connectionStatusLabel.text = "Connecting..."
        connectionStatusLabel.textColor = .lightGray
        subtitleLabel.text = "Open the Eclipse app on your AppleTV to connect"
        connectionActivityIndicator.startAnimating()
        
        // Start browsing if not already browsing
        if !connectionManager.isBrowsing {
            connectionManager.startBrowsing()
        }
        
        // Create auto-connect timer that tries to find and connect to the first Apple TV every few seconds
        if autoConnectTimer == nil {
            autoConnectTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(tryAutoConnect), userInfo: nil, repeats: true)
        }
    }
    
    @objc private func tryAutoConnect() {
        // If we already have a selected peer and it's connected, no need to auto-connect
        if isConnected() {
            autoConnectTimer?.invalidate()
            autoConnectTimer = nil
            return
        }
        
        // If we have a selected peer but it's not connected, try to invite it
        if let peer = selectedPeer {
            // Only invite if we're not already connected to them
            if !connectionManager.isConnectedToPeer(peer) {
                connectionManager.invitePeer(peer)
            }
            return
        }
        
        // Try to connect to any available Apple TV peer
        for peer in connectionManager.discoveredPeers {
            if peer.displayName.contains("Apple TV") || peer.displayName.contains("AppleTV") {
                selectedPeer = peer
                connectionManager.invitePeer(peer)
                
                // Don't update UI state to connected until we actually connect
                // Just update status to show we're trying to connect
                DispatchQueue.main.async {
                    self.connectionStatusLabel.text = "Connecting to \(peer.displayName)..."
                }
                
                // Stop the timer safely
                autoConnectTimer?.invalidate()
                autoConnectTimer = nil
                break
            }
        }
    }
    
    private func stopSearching() {
        if isReconnecting {
            return // Don't interfere with active reconnection
        }
        
        connectionManager.stopBrowsing()
        connectionActivityIndicator.stopAnimating()
        
        // Clean invalidate timer safely
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
    }
    
    // MARK: - UI Updates
    
    private func updateConnectedState(_ connected: Bool, peer: MCPeerID?) {
        DispatchQueue.main.async {
            if connected, let peer = peer {
                // Update connected UI
                UIView.animate(withDuration: 0.3) {
                    self.connectionStatusIcon.alpha = 1
                    self.connectionActivityIndicator.alpha = 0
                }
                self.connectionActivityIndicator.stopAnimating()
                self.connectionStatusIcon.tintColor = .systemGreen
                self.connectionStatusLabel.text = "Connected"
                self.connectionStatusLabel.textColor = .systemGreen
                self.subtitleLabel.text = "Keep the Eclipse AppleTV app open to stay connected."
                
                // Enable media picker button when connected
                self.mediaPickerButton.isEnabled = true
                self.mediaPickerButton.alpha = 1.0
                self.mediaPickerButton.backgroundColor = .systemBlue
                
                // Update selectedPeer
                self.selectedPeer = peer
            } else {
                // Update disconnected UI
                UIView.animate(withDuration: 0.3) {
                    self.connectionStatusIcon.alpha = 0
                    self.connectionActivityIndicator.alpha = 1
                }
                self.connectionActivityIndicator.startAnimating()
                self.connectionStatusIcon.tintColor = .lightGray
                self.connectionStatusLabel.text = "Connecting..."
                self.connectionStatusLabel.textColor = .lightGray
                self.subtitleLabel.text = "Open the Eclipse app on your AppleTV to connect"
                
                // Disable media picker button when disconnected
                self.mediaPickerButton.isEnabled = false
                self.mediaPickerButton.alpha = 0.5
                self.mediaPickerButton.backgroundColor = .lightGray
                
                // Only clear selectedPeer if explicitly told to
                if peer == nil {
                    self.selectedPeer = nil
                }
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
}

// MARK: - UICollectionViewDataSource & UICollectionViewDelegate

extension iPhoneMainViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return selectedImages.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ImagePreviewCell", for: indexPath) as! ImagePreviewCell
        cell.imageView.image = selectedImages[indexPath.item]
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // Remove image when tapped in the collection
        selectedImages.remove(at: indexPath.item)
        collectionView.deleteItems(at: [indexPath])
    }
}

// MARK: - UIImagePickerControllerDelegate
extension iPhoneMainViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        // Reset picker flag
        isShowingPicker = false
        
        picker.dismiss(animated: true)
        
        if let videoURL = info[.mediaURL] as? URL {
            // Show validating status
            statusLabel.text = "Validating video..."
            statusLabel.alpha = 1.0
            
            // Validate video asynchronously
            Task {
                let validationResult = await MediaValidator.validateVideo(at: videoURL)
                
                DispatchQueue.main.async {
                    self.statusLabel.alpha = 0
                    
                    switch validationResult {
                    case .valid:
                        // Show thumbnail selection interface before sending
                        self.showVideoThumbnailPreview(for: videoURL)
                    case .invalid(let reason):
                        self.showAlert(title: "Video Rejected", message: reason)
                    }
                }
            }
        } else if let image = info[.originalImage] as? UIImage {
            // Check if image needs downscaling and inform user
            if MediaValidator.imageNeedsDownscaling(image) {
                if let description = MediaValidator.getDownscalingDescription(for: image) {
                    showTemporaryStatus(description, duration: 4.0)
                }
            }
            
            // Downscale image if needed and send directly with default fit-to-fill centered
            let optimizedImage = MediaValidator.downscaleImage(image)
            sendImageToAppleTV(optimizedImage)
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        // Reset picker flag
        isShowingPicker = false
        
        picker.dismiss(animated: true)
    }
}

// MARK: - iPhoneConnectionManagerDelegate

extension iPhoneMainViewController: iPhoneConnectionManagerDelegate {
    func connectionManager(_ manager: iPhoneConnectionManager, didFindPeer peer: MCPeerID) {
        print("📱 Found peer: \(peer.displayName)")
        
        // Auto-connect to Apple TV peers if we don't already have a connection
        if selectedPeer == nil && (peer.displayName.contains("Apple TV") || peer.displayName.contains("AppleTV")) {
            print("📱 Attempting to connect to Apple TV: \(peer.displayName)")
            selectedPeer = peer
            connectionManager.invitePeer(peer)
            
            // Update UI to show we're attempting to connect
            DispatchQueue.main.async {
                self.connectionStatusLabel.text = "Connecting to \(peer.displayName)..."
            }
        }
    }
    
    func connectionManager(_ manager: iPhoneConnectionManager, didLosePeer peer: MCPeerID) {
        if selectedPeer == peer {
            if !isShowingPicker && !isReconnecting {
                updateConnectedState(false, peer: nil)
                startSearching()
            }
        }
    }
    
    func connectionManager(_ manager: iPhoneConnectionManager, didConnectToPeer peer: MCPeerID) {
        // Reset reconnect flag
        isReconnecting = false
        updateConnectedState(true, peer: peer)
    }
    
    func connectionManager(_ manager: iPhoneConnectionManager, didDisconnectFromPeer peer: MCPeerID) {
        if selectedPeer == peer {
            // Only update UI and restart searching if we're not already reconnecting
            // and not in the middle of picking images
            if !isShowingPicker && !isReconnecting {
                updateConnectedState(false, peer: nil)
                startSearching()
            }
        }
    }
    
    func connectionManager(_ manager: iPhoneConnectionManager, didReceiveConfirmationFromPeer peer: MCPeerID) {
        DispatchQueue.main.async {
            self.showTemporaryStatus("Sent successfully!", duration: 3.0)
            self.hideTransferUI() // This will now clean up temp files
            self.connectionActivityIndicator.stopAnimating()
            self.isSendingVideo = false
        }
    }
    
    func connectionManager(_ manager: iPhoneConnectionManager, didUpdateVideoTransferProgress progress: Double) {
        // Update status label with progress
        statusLabel.text = String(format: "Sending video: %.1f%%", progress)
        statusLabel.alpha = 1.0
        
        // If transfer is complete, show completion message and hide transfer UI
        if progress >= 100.0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                self.statusLabel.text = "Video sent successfully"
                self.hideTransferUI()
                self.connectionActivityIndicator.stopAnimating()
                
                // Fade out status after 3 seconds
                UIView.animate(withDuration: 0.5, delay: 3.0, options: [], animations: {
                    self.statusLabel.alpha = 0
                })
            }
        }
    }
    
    // Add delegate method for image progress
    func connectionManager(_ manager: iPhoneConnectionManager, didUpdateImageTransferProgress progress: Double) {
        statusLabel.text = String(format: "Sending image: %.1f%%", progress)
        statusLabel.alpha = 1.0
        if progress >= 100.0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                self.statusLabel.text = "Image sent successfully"
                self.hideTransferUI()
                self.connectionActivityIndicator.stopAnimating()
                UIView.animate(withDuration: 0.5, delay: 3.0, options: [], animations: {
                    self.statusLabel.alpha = 0
                })
            }
        }
    }
    
    // Handle move mode state changes from Apple TV
    func connectionManager(_ manager: iPhoneConnectionManager, didReceiveMoveModeState enabled: Bool) {
        DispatchQueue.main.async {
            if enabled {
                // Show notification that AppleTV is in move mode
                self.showTemporaryStatus("AppleTV is organizing content. Your media will be added when complete.", duration: 5.0)
                
                // Update button state to indicate move mode (optional)
                if self.mediaPickerButton.isEnabled {
                    self.mediaPickerButton.setTitle("Waiting...", for: .normal)
                }
            } else {
                // Show notification that AppleTV has exited move mode
                self.showTemporaryStatus("AppleTV is ready to receive media again", duration: 3.0)
                
                // Restore button state
                if self.mediaPickerButton.isEnabled {
                    self.mediaPickerButton.setTitle("Send Media", for: .normal)
                }
            }
        }
    }
}

// MARK: - VideoThumbnailPreviewDelegate

extension iPhoneMainViewController: VideoThumbnailPreviewDelegate {
    func videoThumbnailPreview(_ controller: VideoThumbnailPreviewViewController, didFinishWithVideoURL videoURL: URL, selectedThumbnail: UIImage) {
        controller.dismiss(animated: true) { [weak self] in
            // Save the custom thumbnail for later use
            self?.saveCustomThumbnail(selectedThumbnail, for: videoURL)
            // Send the video to Apple TV
            self?.sendMediaToAppleTV(videoURL)
        }
    }
    
    func videoThumbnailPreviewDidCancel(_ controller: VideoThumbnailPreviewViewController) {
        controller.dismiss(animated: true)
    }
    
    private func saveCustomThumbnail(_ thumbnail: UIImage, for videoURL: URL) {
        // Save the custom thumbnail to a temporary location
        // We'll use this when the video is received on the Apple TV side
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else { return }
        
        let tempDir = FileManager.default.temporaryDirectory
        let thumbnailFileName = "thumbnail_\(videoURL.lastPathComponent).jpg"
        let thumbnailURL = tempDir.appendingPathComponent(thumbnailFileName)
        
        do {
            try thumbnailData.write(to: thumbnailURL)
            // Store the thumbnail path associated with the video
            UserDefaults.standard.set(thumbnailURL.path, forKey: "customThumbnail_\(videoURL.lastPathComponent)")
        } catch {
            print("Failed to save custom thumbnail: \(error)")
        }
    }
}
