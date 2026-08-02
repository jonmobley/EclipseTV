//
//  RootView.swift
//  Eclipse
//
//  Description: Router between Mac connect and lean live-control screens.
//  Thread Safety: Main thread only — SwiftUI view.
//

import SwiftUI

// MARK: - MacRemoteRootView

/// Chooses connect vs control UI from `RemoteSessionModel.phase`.
///
/// Thread Safety: Main thread only.
struct MacRemoteRootView: View {
    @ObservedObject var session: RemoteSessionModel
    /// Dismisses the Mac-remote flow and returns to the main Eclipse UI.
    var onClose: () -> Void

    var body: some View {
        Group {
            switch session.phase {
            case .connected:
                RemoteControlView(session: session)
            default:
                ConnectView(session: session, onClose: onClose)
            }
        }
        // Follow system appearance so the remote matches the Show page, not a
        // separate dark-only skin.
        .animation(.easeInOut(duration: 0.2), value: session.phase)
    }
}
