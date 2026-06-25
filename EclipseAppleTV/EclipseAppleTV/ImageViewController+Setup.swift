// ImageViewController+Setup.swift
import UIKit
import os.log

// MARK: - View Model & UI Setup

extension ImageViewController {

    func setupViewModel() {
        // Bind to view model changes
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading {
                    self?.activityIndicator.startAnimating()
                } else {
                    self?.activityIndicator.stopAnimating()
                }
            }
            .store(in: &cancellables)

        // Start in grid mode and hide all views initially while loading
        logger.info("Setting up initial state - starting in grid mode")
        isInGridMode = true
        gridView.isHidden = true  // Hide until sample media loads
        gradientView.isHidden = true  // Hide background until ready
        imageView.isHidden = true
        playerView.view.isHidden = true

        // Always load sample media first. Run at utility priority so the heavy
        // image/asset processing yields to first-frame UI rendering at launch.
        logger.info("Loading sample media automatically on every launch")
        Task(priority: .utility) {
            logger.info("🚀 [SETUP] About to call viewModel.loadSampleMedia()")
            await viewModel.loadSampleMedia()
            await MainActor.run {
                logger.info("✅ [SETUP] Sample media loading completed. Data source count: \(self.dataSource.count)")

                // Debug data source state
                self.dataSource.debugState()

                // Fallback: if no media found by service, try scanning bundle subfolders explicitly
                if self.dataSource.isEmpty {
                    self.logger.info("❔ [SETUP] No media after service load — scanning bundle 'Videos' and 'Images' folders as fallback")
                    let before = self.dataSource.count
                    self.loadVideosFromBundle()
                    self.logger.info("📦 [SETUP] After videos scan: count=\(self.dataSource.count) (Δ=\(self.dataSource.count - before))")
                    self.loadImagesFromBundle()
                    self.logger.info("📦 [SETUP] After images scan: count=\(self.dataSource.count)")
                    if self.dataSource.isEmpty {
                        self.logger.error("🚫 [SETUP] Still empty after fallback scans. Showing empty state.")
                    }
                }

                // Always go directly to grid view with sample media
                logger.info("🎯 [SETUP] Going directly to grid view with sample media")
                self.isInGridMode = true

                // If we have media, show grid view directly
                if !self.dataSource.isEmpty {
                    logger.info("✅ [SETUP] Data source has \(self.dataSource.count) items - showing grid view")
                    self.gridView.isHidden = false
                    self.titleLabel.isHidden = false
                    self.gradientView.isHidden = false

                    // Start preloading videos for smooth transitions
                    logger.info("🚀 [CACHE] Starting initial video preloading")
                    VideoCacheManager.shared.preloadInitialVideos(from: self.dataSource)

                    // Reload and select first item
                    self.gridView.reloadData()
                    if let firstIndexPath = IndexPath(item: 0, section: 0) as IndexPath?, self.dataSource.count > 0 {
                        self.simpleSelectionManager.selectItem(at: firstIndexPath)
                        self.dataSource.setCurrentIndex(0)

                        // Update focus to the grid view
                        self.setNeedsFocusUpdate()
                        self.updateFocusIfNeeded()
                    }
                } else {
                    // If no media loaded, show empty state
                    logger.info("❌ [SETUP] Data source is empty - showing empty state")
                    self.showEmptyState()
                }
            }
        }
    }

    func setupUI() {
        // Add views in proper z-index order
        view.addSubview(gradientView)
        view.addSubview(imageView)
        view.addSubview(gridView)
        view.addSubview(activityIndicator)
        view.addSubview(instructionLabel)
        view.addSubview(helpView)
        view.addSubview(toastView)

        // Configure helpers
        helpView.delegate = self
        helpView.isHidden = true
        emptyStateView.delegate = self
        instructionLabel.isHidden = true

        // Setup constraints
        imageView.translatesAutoresizingMaskIntoConstraints = false
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        gridView.translatesAutoresizingMaskIntoConstraints = false
        helpView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Image view constraints
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Gradient view constraints
            gradientView.topAnchor.constraint(equalTo: view.topAnchor),
            gradientView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Grid view constraints
            gridView.topAnchor.constraint(equalTo: view.topAnchor),
            gridView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Help view constraints
            helpView.topAnchor.constraint(equalTo: view.topAnchor),
            helpView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            helpView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            helpView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Toast view constraints
            toastView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            toastView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            toastView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.4)
        ])
    }

    func setupGradientBackground() {
        // Create a new gradient layer
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.black.cgColor,
            UIColor(white: 0.1, alpha: 1.0).cgColor
        ]
        gradientLayer.locations = [0.0, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.frame = gradientView.bounds

        // Remove any existing layers
        gradientView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        // Add the new gradient layer
        gradientView.layer.insertSublayer(gradientLayer, at: 0)
    }

    func setupFocusGuide() {
        view.addLayoutGuide(focusGuide)

        NSLayoutConstraint.activate([
            focusGuide.topAnchor.constraint(equalTo: view.topAnchor),
            focusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            focusGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            focusGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
