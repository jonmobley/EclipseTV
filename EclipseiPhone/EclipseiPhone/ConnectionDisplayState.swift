//
//  ConnectionDisplayState.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Multipeer EclipseTV link state as shown by the home header and Settings.
///
/// `.paused` is the AirPlay-first default: the phone is not searching for a TV.
/// One type for both surfaces so the host never has to map header state onto
/// Settings state case by case.
enum ConnectionDisplayState {
    case connected
    case disconnected
    case paused
}
