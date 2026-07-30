//
//  SSEEventParser.swift
//  EclipseRemoteProtocol
//
//  Description: Incremental parser for `text/event-stream` data frames.
//  Thread Safety: Instances are not thread-safe; call from one task at a time.
//

import Foundation

// MARK: - SSEEventParser

/// Accumulates SSE bytes and yields complete `data:` JSON payloads.
///
/// Only the `data:` field is required by the Eclipse remote server
/// (`data: <json>\\n\\n`). Other SSE fields are ignored.
///
/// Thread Safety: Not thread-safe — use one parser per stream.
public struct SSEEventParser: Sendable {

    // MARK: - Properties

    private var buffer = Data()

    // MARK: - Public Interface

    /// Appends a chunk and returns any complete JSON payloads.
    /// - Parameter chunk: Next bytes from the HTTP body stream.
    /// - Returns: Zero or more UTF-8 JSON strings (one per SSE event).
    public mutating func push(_ chunk: Data) -> [String] {
        buffer.append(chunk)
        var events: [String] = []
        let separator = Data("\n\n".utf8)

        while let range = buffer.range(of: separator) {
            let frame = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let json = Self.dataPayload(from: frame) {
                events.append(json)
            }
        }
        return events
    }

    // MARK: - Private Helpers

    private static func dataPayload(from frame: Data) -> String? {
        guard let text = String(data: frame, encoding: .utf8) else { return nil }
        var lines: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : String(rawLine)
            if line.hasPrefix("data:") {
                var value = String(line.dropFirst(5))
                if value.hasPrefix(" ") { value = String(value.dropFirst()) }
                lines.append(value)
            }
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }
}
