import UIKit
import MultipeerConnectivity
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import os

class iPhoneMainViewController: UIViewController {
    
    // MARK: - UI Elements
    
    let connectionStatusContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let connectionStatusIcon: UIImageView = {
        let imageView = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        imageView.image = UIImage(systemName: "dot.radiowaves.left.and.right", withConfiguration: config)
        imageView.tintColor = .lightGray
        imageView.contentMode = .scaleAspectFit
        imageView.alpha = 0 // Start hidden
        return imageView
    }()
    
    let connectionActivityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .lightGray
        return indicator
    }()
    
    let connectionStatusLabel: UILabel = {
        let label = UILabel()
        label.text = "Connecting..."
        label.textColor = .lightGray
        label.font = UIFont.systemFont(ofSize: 14)
        label.textAlignment = .center
        return label
    }()
    
    let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Eclipse"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        return label
    }()
    
    let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Open the Eclipse app on your AppleTV to connect"
        label.textColor = .lightGray
        label.font = UIFont.systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    
    let statusLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 16)
        label.numberOfLines = 0
        label.alpha = 0
        return label
    }()
    
    let mediaPickerButton: UIButton = {
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
    
    let sendButton: UIButton = {
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
    
    let cancelButton: UIButton = {
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
    
    let connectionManager = iPhoneConnectionManager()
    var selectedPeer: MCPeerID?
    var autoConnectTimer: Timer?
    var isShowingPicker = false // Track if we're showing the image picker
    private var statusFadeTimer: Timer?
    let logger = Logger(subsystem: "com.eclipseapp.ios", category: "MainViewController")
    var currentTempFileURL: URL? // Track temp files for cleanup
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
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
    
    // MARK: - Helper Methods
    
    func showVideoThumbnailPreview(for videoURL: URL) {
        let previewController = VideoThumbnailPreviewViewController(videoURL: videoURL)
        previewController.delegate = self
        previewController.modalPresentationStyle = .overFullScreen
        present(previewController, animated: true)
    }
    
    func isConnected() -> Bool {
        guard let peer = selectedPeer else {
            return false
        }
        
        // Ask connection manager if we're connected to this peer
        return connectionManager.isConnectedToPeer(peer)
    }
    
    func showTemporaryStatus(_ message: String, duration: TimeInterval = 3.0) {
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
    
    func cleanupTempFile(at url: URL) {
        DispatchQueue.global(qos: .utility).async { [logger] in
            do {
                try FileManager.default.removeItem(at: url)
                logger.debug("Cleaned up temp file: \(url.lastPathComponent, privacy: .public)")
            } catch {
                logger.error("Failed to cleanup temp file: \(error.localizedDescription)")
            }
        }
    }
    
}
