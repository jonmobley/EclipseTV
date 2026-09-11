//
//  ZipStoreWriter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Minimal ZIP writer using the store (no compression) method.
///
/// Media is already compressed; store keeps RAM low by streaming file bytes.
enum ZipStoreWriter {

    enum WriterError: Error {
        case cannotCreateFile
        case readFailed
    }

    /// Writes `entries` to `destination`. Overwrites any existing file.
    ///
    /// - Parameters:
    ///   - entries: Relative POSIX paths (use `/`) paired with on-disk sources.
    ///   - destination: Final `.zip` URL.
    static func write(
        entries: [(relativePath: String, sourceURL: URL)],
        to destination: URL
    ) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        guard FileManager.default.createFile(
            atPath: destination.path, contents: nil
        ) else {
            throw WriterError.cannotCreateFile
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var central: [CentralEntry] = []
        var offset: UInt32 = 0

        for entry in entries {
            let path = normalizePath(entry.relativePath)
            let pathData = Data(path.utf8)
            let fileSize = try fileSize(at: entry.sourceURL)
            let crc = try crc32(of: entry.sourceURL)

            let localHeader = localFileHeader(
                pathData: pathData, crc: crc, size: fileSize
            )
            try handle.write(contentsOf: localHeader)
            try streamContents(of: entry.sourceURL, to: handle)

            central.append(CentralEntry(
                pathData: pathData,
                crc: crc,
                size: fileSize,
                localHeaderOffset: offset
            ))
            offset += UInt32(localHeader.count) + fileSize
        }

        let centralStart = offset
        var centralSize: UInt32 = 0
        for item in central {
            let header = centralDirectoryHeader(item)
            try handle.write(contentsOf: header)
            centralSize += UInt32(header.count)
        }
        try handle.write(contentsOf: endOfCentralDirectory(
            entryCount: UInt16(central.count),
            centralSize: centralSize,
            centralOffset: centralStart
        ))
    }

    // MARK: - Private

    private struct CentralEntry {
        let pathData: Data
        let crc: UInt32
        let size: UInt32
        let localHeaderOffset: UInt32
    }

    private static func normalizePath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func fileSize(at url: URL) throws -> UInt32 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = values.fileSize ?? 0
        return UInt32(size)
    }

    private static func streamContents(of url: URL, to handle: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        while true {
            let chunk = try input.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            try handle.write(contentsOf: chunk)
        }
    }

    private static func crc32(of url: URL) throws -> UInt32 {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var crc: UInt32 = 0xffff_ffff
        while true {
            let chunk = try input.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            for byte in chunk {
                crc = Self.crcTable[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xffff_ffff
    }

    private static func localFileHeader(
        pathData: Data, crc: UInt32, size: UInt32
    ) -> Data {
        var data = Data(capacity: 30 + pathData.count)
        data.appendUInt32(0x0403_4b50)
        data.appendUInt16(20)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt32(crc)
        data.appendUInt32(size)
        data.appendUInt32(size)
        data.appendUInt16(UInt16(pathData.count))
        data.appendUInt16(0)
        data.append(pathData)
        return data
    }

    private static func centralDirectoryHeader(_ entry: CentralEntry) -> Data {
        var data = Data(capacity: 46 + entry.pathData.count)
        data.appendUInt32(0x0201_4b50)
        data.appendUInt16(20)
        data.appendUInt16(20)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt32(entry.crc)
        data.appendUInt32(entry.size)
        data.appendUInt32(entry.size)
        data.appendUInt16(UInt16(entry.pathData.count))
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt32(0)
        data.appendUInt32(entry.localHeaderOffset)
        data.append(entry.pathData)
        return data
    }

    private static func endOfCentralDirectory(
        entryCount: UInt16,
        centralSize: UInt32,
        centralOffset: UInt32
    ) -> Data {
        var data = Data(capacity: 22)
        data.appendUInt32(0x0605_4b50)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(entryCount)
        data.appendUInt16(entryCount)
        data.appendUInt32(centralSize)
        data.appendUInt32(centralOffset)
        data.appendUInt16(0)
        return data
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var crc = UInt32(index)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xedb8_8320
                } else {
                    crc >>= 1
                }
            }
            return crc
        }
    }()
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
