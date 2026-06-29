import UIKit
import MultipeerConnectivity
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import os

class iPhoneMainViewController: UIViewController {
    
    // MARK: - UI Elements

    /// Top header: connection status (leading) and the blue "+" media button (trailing).
    let headerBar = HomeHeaderBar()

    /// The library grid is the home screen; it's embedded as a child view controller.
    lazy var libraryViewController = LibraryGridViewController(connectionManager: connectionManager)

    /// Transient transfer/status message overlaid on top of the library while sending.
    let statusLabel: PaddedLabel = {
        let label = PaddedLabel()
        label.textAlignment = .center
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.numberOfLines = 0
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.alpha = 0
        return label
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
    /// Session-only flag: when true the user chose to use Eclipse without an Apple TV,
    /// so auto-connect, browsing, and the "Still connecting?" hint are all suspended
    /// until they reconnect. Resets to false on next launch.
    var isConnectionPaused = false
    var autoConnectTimer: Timer?
    /// One-shot timer that reveals the troubleshooting hint if we can't connect in time.
    var connectionHintTimer: Timer?
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
        
        // The home screen uses its own custom header bar, so keep the nav bar hidden.
        navigationController?.setNavigationBarHidden(true, animated: animated)
        
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

    func showImagePreview(for image: UIImage) {
        let previewController = ImagePreviewViewController(image: image)
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
        connectionHintTimer?.invalidate()
        connectionHintTimer = nil
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
