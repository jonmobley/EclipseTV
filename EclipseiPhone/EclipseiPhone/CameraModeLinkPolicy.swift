//
//  CameraModeLinkPolicy.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import EclipsePhoneCameraProtocol
import Foundation

// MARK: - CameraModeLinkPolicy

/// Decides which Mac links Camera Mode may send the camera to.
///
/// Eclipse on a Mac serves Phone Camera on the local network only, so a link
/// pointing anywhere else (an internet address) is refused. That stops a
/// web page or message from streaming this camera off-site. Pure and
/// thread-safe.
enum CameraModeLinkPolicy {

    /// The Mac's host name or address in a Phone Camera link.
    /// - Parameter link: A scanned or opened `eclipse://phone-camera?...` link.
    /// - Returns: The host, or nil when the link can't be read.
    static func macHost(in link: String) -> String? {
        PhoneCameraConnectURLParser.parse(link)?.baseURL.host
    }

    /// True when the link points at a Mac on the local network.
    /// - Parameter link: A Phone Camera link.
    static func isAllowed(_ link: String) -> Bool {
        guard let host = macHost(in: link) else { return false }
        return isLocalNetworkHost(host)
    }

    /// True for private, link-local and `.local` addresses.
    /// - Parameter host: Host name or IP address (IPv6 with or without brackets).
    static func isLocalNetworkHost(_ host: String) -> Bool {
        let name = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if name.hasSuffix(".local") { return true }
        if name.contains(":") { return isLocalIPv6(name) }
        return isPrivateIPv4(name)
    }

    // MARK: - Private Helpers

    private static func isPrivateIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    /// Link-local (fe80::/10) and unique-local (fc00::/7) addresses.
    private static func isLocalIPv6(_ address: String) -> Bool {
        let first = address.split(separator: ":", omittingEmptySubsequences: false).first ?? ""
        guard let value = UInt16(first, radix: 16), !first.isEmpty else { return false }
        return (value & 0xFFC0) == 0xFE80 || (value & 0xFE00) == 0xFC00
    }
}
