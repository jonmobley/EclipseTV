// iPhoneMainViewController+Setup.swift
import UIKit
import os

// MARK: - Notification Observers & UI Setup

extension iPhoneMainViewController {

    func setupNotificationObservers() {
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
        logger.debug("App will enter foreground")
        // Don't start searching yet, wait for didBecomeActive
    }

    @objc private func handleAppDidBecomeActive() {
        logger.debug("App did become active")

        // Check if we need to reconnect
        if selectedPeer != nil && !isConnected() {
            // We have a selected peer but no active connection, try to reconnect
            updateConnectedState(false, peer: nil)
            startSearching()
        }
    }

    @objc private func handleAppDidEnterBackground() {
        logger.debug("App did enter background")
        // Pause timers when entering background to save battery
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
        // Keep status fade timer running as it's short-lived
    }

    func setupUI() {
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

    func setupConnectionManager() {
        connectionManager.delegate = self
    }
}
