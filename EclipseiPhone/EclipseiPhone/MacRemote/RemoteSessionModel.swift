//
//  RemoteSessionModel.swift
//  EclipseRemote
//
//  Description: Observable session state for pairing, SSE snapshots, and
//               command dispatch to the Mac remote server.
//  Thread Safety: Main actor — UI-facing ObservableObject.
//

import Combine
import Foundation

// MARK: - RemoteSessionModel

/// Owns connection credentials and the latest `RemoteStateSnapshot`.
///
/// Thread Safety: Main actor only.
@MainActor
final class RemoteSessionModel: ObservableObject {

    // MARK: - Nested Types

    enum Phase: Equatable {
        case disconnected
        case connecting
        case needsPIN
        case connected
        case failed(String)
    }

    // MARK: - Properties

    @Published private(set) var phase: Phase = .disconnected
    @Published private(set) var snapshot: RemoteStateSnapshot?
    /// True while SSE is down and a backoff retry is in flight.
    @Published private(set) var isReconnecting = false
    @Published var hostText: String = "eclipse.local"
    @Published var pinText: String = ""

    /// In-memory PNG cache for the media grid.
    let thumbnails = RemoteThumbnailStore()

    private var client: RemoteAPIClient?
    private var sessionToken: String?
    private var eventsTask: Task<Void, Never>?
    private var reconnectAttempt = 0

    // MARK: - Public Interface

    /// Connects using the typed host field (PIN path when no QR token).
    func connectFromHostField() {
        guard let info = ConnectURLParser.parse(hostText) else {
            phase = .failed("Enter a valid host like eclipse.local or 192.168.1.10")
            return
        }
        connect(info: info)
    }

    /// Connects from a scanned QR payload.
    /// - Parameter raw: Full connect URL including optional `#t=` fragment.
    func connect(scannedURL raw: String) {
        guard let info = ConnectURLParser.parse(raw) else {
            phase = .failed("Could not read that QR code")
            return
        }
        hostText = info.baseURL.absoluteString
        connect(info: info)
    }

    /// Completes PIN pairing after `needsPIN`.
    func submitPIN() {
        let digits = pinText.filter(\.isNumber)
        guard digits.count == 6, let client else {
            phase = .failed("Enter the 6-digit PIN from Eclipse Settings")
            return
        }
        phase = .connecting
        Task { await pairAndListen(client: client, pin: digits) }
    }

    /// Tears down SSE and clears credentials.
    func disconnect() {
        eventsTask?.cancel()
        eventsTask = nil
        client = nil
        sessionToken = nil
        snapshot = nil
        reconnectAttempt = 0
        isReconnecting = false
        thumbnails.reset()
        phase = .disconnected
    }

    /// Sends a remote command using the active session token.
    /// - Parameter command: Action to execute on the Mac.
    func send(_ command: RemoteCommand) {
        guard let client, let token = sessionToken else { return }
        Task {
            do {
                try await client.send(command: command, token: token)
            } catch let error as RemoteAPIError where error == .unauthorized {
                invalidateForUnauthorized()
            } catch {
                phase = .failed(Self.describe(error))
            }
        }
    }

    /// Convenience for simple toggle actions.
    /// - Parameter action: Command verb with no payload.
    func send(_ action: RemoteCommandAction) {
        send(RemoteCommand(action: action))
    }

    // MARK: - Private Helpers

    private func connect(info: RemoteConnectInfo) {
        eventsTask?.cancel()
        let client = RemoteAPIClient(baseURL: info.baseURL)
        self.client = client
        phase = .connecting

        if let token = info.bootstrapToken {
            Task { await sessionAndListen(client: client, bootstrap: token) }
        } else {
            phase = .needsPIN
        }
    }

    private func sessionAndListen(client: RemoteAPIClient, bootstrap: String) async {
        do {
            let token = try await client.establishSession(bootstrapToken: bootstrap)
            beginSession(client: client, token: token)
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    private func pairAndListen(client: RemoteAPIClient, pin: String) async {
        do {
            let token = try await client.pair(pin: pin)
            pinText = ""
            beginSession(client: client, token: token)
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    private func beginSession(client: RemoteAPIClient, token: String) {
        sessionToken = token
        thumbnails.configure(client: client, token: token)
        reconnectAttempt = 0
        isReconnecting = false
        phase = .connected
        startListening(client: client, token: token)
    }

    /// Opens SSE and retries with backoff after drops (matches web remote).
    private func startListening(client: RemoteAPIClient, token: String) {
        eventsTask?.cancel()
        eventsTask = Task { [weak self] in
            await self?.runEventLoop(client: client, token: token)
        }
    }

    private func runEventLoop(client: RemoteAPIClient, token: String) async {
        while !Task.isCancelled {
            guard sessionToken == token, self.client != nil else { return }

            let outcome = await listenOnce(client: client, token: token)
            switch outcome {
            case .cancelled:
                return
            case .unauthorized:
                invalidateForUnauthorized()
                return
            case .disconnected:
                break
            }

            guard sessionToken == token else { return }
            isReconnecting = true

            let sessionOK = await client.probeSession(token: token)
            if !sessionOK {
                invalidateForUnauthorized()
                return
            }

            let delayMs = min(1_000 * (1 << min(reconnectAttempt, 4)), 15_000)
            reconnectAttempt += 1
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
        }
    }

    private enum ListenOutcome {
        case cancelled
        case unauthorized
        case disconnected
    }

    private func listenOnce(client: RemoteAPIClient, token: String) async -> ListenOutcome {
        do {
            try await client.listenForEvents(token: token) { [weak self] snapshot in
                Task { @MainActor in
                    self?.apply(snapshot: snapshot)
                }
            }
            return .disconnected
        } catch is CancellationError {
            return .cancelled
        } catch let error as RemoteAPIError where error == .unauthorized {
            return .unauthorized
        } catch {
            return .disconnected
        }
    }

    private func apply(snapshot: RemoteStateSnapshot) {
        isReconnecting = false
        reconnectAttempt = 0
        self.snapshot = snapshot
        thumbnails.prefetch(items: snapshot.media + snapshot.libraryMedia)
    }

    private func invalidateForUnauthorized() {
        eventsTask?.cancel()
        eventsTask = nil
        client = nil
        sessionToken = nil
        snapshot = nil
        reconnectAttempt = 0
        isReconnecting = false
        thumbnails.reset()
        phase = .failed("Unauthorized — generate a new link on the Mac")
    }

    private static func describe(_ error: Error) -> String {
        if let api = error as? RemoteAPIError {
            switch api {
            case .unauthorized:
                return "Unauthorized — generate a new link on the Mac"
            case .pairWrongPIN(let remaining):
                if let remaining {
                    return "Wrong PIN — \(remaining) tries left"
                }
                return "Wrong PIN"
            case .pairLocked:
                return "Too many PIN attempts — wait, then try again"
            case .pairNotArmed:
                return "Remote is off on the Mac — enable it in Settings"
            case .rateLimited:
                return "Rate limited — slow down and retry"
            case .disconnected:
                return "Disconnected from Mac"
            case .invalidURL:
                return "Invalid server URL"
            case .decoding:
                return "Could not read server state"
            case .server(let message, let status):
                return "Server error \(status): \(message)"
            }
        }
        return error.localizedDescription
    }
}
