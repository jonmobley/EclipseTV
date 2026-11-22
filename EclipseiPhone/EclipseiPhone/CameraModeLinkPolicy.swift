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
        guard let parts = canonicalIPv4Octets(address) else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    /// Strict dotted-decimal: exactly four 0–255 parts, digits only, no
    /// leading zeros. Anything else (octal like "010", hex, extra or missing
    /// parts) is refused, since other code could read it as a different address.
    private static func canonicalIPv4Octets(_ address: String) -> [Int]? {
        let pieces = address.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 4 else { return nil }
        var octets: [Int] = []
        for piece in pieces {
            guard (1...3).contains(piece.count),
                  piece.allSatisfy({ ("0"..."9").contains($0) }),
                  piece == "0" || !piece.hasPrefix("0"),
                  let value = Int(piece), value <= 255 else { return nil }
            octets.append(value)
        }
        return octets
    }

    /// Link-local (fe80::/10) and unique-local (fc00::/7) addresses.
    private static func isLocalIPv6(_ address: String) -> Bool {
        let first = address.split(separator: ":", omittingEmptySubsequences: false).first ?? ""
        guard let value = UInt16(first, radix: 16), !first.isEmpty else { return false }
        return (value & 0xFFC0) == 0xFE80 || (value & 0xFE00) == 0xFC00
    }
}
