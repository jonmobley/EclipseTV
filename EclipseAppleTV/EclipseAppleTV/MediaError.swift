import Foundation
import UIKit

/// Comprehensive error types for media operations
enum MediaError: LocalizedError, Equatable {
    // File System Errors
    case fileNotFound(path: String)
    case fileCorrupted(path: String, reason: String?)
    case insufficientStorage(needed: Int64, available: Int64)
    case permissionDenied(operation: String)
    case unsupportedFormat(extension: String, supportedFormats: [String])
    
    // Video Specific Errors
    case videoDecodingFailed(path: String, details: String)
    case thumbnailGenerationFailed(path: String, timeStamp: Double?)
    case videoTooLarge(path: String, size: Int64, maxSize: Int64)
    case videoDurationInvalid(path: String)
    
    // Network Errors
    case connectionFailed(peerName: String?)
    case transferTimeout(fileName: String, duration: TimeInterval)
    case transferCorrupted(fileName: String, expectedSize: Int64, actualSize: Int64)
    case networkUnavailable
    
    // App State Errors
    case invalidIndex(index: Int, maxIndex: Int)
    case emptyLibrary
    case concurrentModification(operation: String)
    case focusSystemError(context: String)
    
    // System Errors
    case memoryPressure(availableMemory: Int64)
    case backgroundTaskExpired(taskName: String)
    case unknown(underlyingError: Error?)
    
    // MARK: - Error Properties
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            return "File not found: \(fileName)"
            
        case .fileCorrupted(let path, let reason):
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            if let reason = reason {
                return "File corrupted: \(fileName) - \(reason)"
            }
            return "File appears to be corrupted: \(fileName)"
            
        case .insufficientStorage(let needed, let available):
            let neededMB = needed / (1024 * 1024)
            let availableMB = available / (1024 * 1024)
            return "Not enough storage space. Need \(neededMB)MB, only \(availableMB)MB available"
            
        case .permissionDenied(let operation):
            return "Permission denied for \(operation)"
            
        case .unsupportedFormat(let ext, let supported):
            return "Unsupported format: .\(ext)\nSupported formats: \(supported.joined(separator: ", "))"
            
        case .videoDecodingFailed(let path, let details):
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            return "Cannot play video: \(fileName)\n\(details)"
            
        case .thumbnailGenerationFailed(let path, let timeStamp):
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            if let time = timeStamp {
                return "Cannot generate thumbnail for \(fileName) at \(String(format: "%.1f", time))s"
            }
            return "Cannot generate thumbnail for \(fileName)"
            
        case .videoTooLarge(let path, let size, let maxSize):
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            let sizeMB = size / (1024 * 1024)
            let maxMB = maxSize / (1024 * 1024)
            return "Video too large: \(fileName) (\(sizeMB)MB). Maximum size: \(maxMB)MB"
            
        case .videoDurationInvalid(let path):
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            return "Invalid video duration: \(fileName)"
            
        case .connectionFailed(let peerName):
            if let peer = peerName {
                return "Connection failed to \(peer)"
            }
            return "Connection failed"
            
        case .transferTimeout(let fileName, let duration):
            return "Transfer timeout: \(fileName) (after \(String(format: "%.1f", duration))s)"
            
        case .transferCorrupted(let fileName, let expected, let actual):
            return "Transfer corrupted: \(fileName)\nExpected: \(expected) bytes, Got: \(actual) bytes"
            
        case .networkUnavailable:
            return "Network unavailable"
            
        case .invalidIndex(let index, let maxIndex):
            return "Invalid index: \(index) (max: \(maxIndex))"
            
        case .emptyLibrary:
            return "No media files available"
            
        case .concurrentModification(let operation):
            return "Concurrent modification during \(operation). Please try again."
            
        case .focusSystemError(let context):
            return "Focus system error in \(context)"
            
        case .memoryPressure(let available):
            let availableMB = available / (1024 * 1024)
            return "Low memory warning. Available: \(availableMB)MB"
            
        case .backgroundTaskExpired(let taskName):
            return "Background task expired: \(taskName)"
            
        case .unknown(let error):
            if let underlying = error {
                return "Unknown error: \(underlying.localizedDescription)"
            }
            return "An unknown error occurred"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .fileNotFound, .fileCorrupted:
            return "The file may have been moved or deleted. Try refreshing the library or re-transferring from your device."
            
        case .insufficientStorage:
            return "Free up space by deleting unused media files or transfer fewer files at once."
            
        case .permissionDenied:
            return "Grant file access permissions in Settings > Privacy & Security."
            
        case .unsupportedFormat:
            return "Convert the file to a supported format: JPEG, PNG, HEIC for images or MP4, MOV for videos."
            
        case .videoDecodingFailed, .videoDurationInvalid:
            return "The video file may be corrupted. Try re-transferring or converting to MP4 format."
            
        case .thumbnailGenerationFailed:
            return "The video will still play, but no thumbnail preview is available."
            
        case .videoTooLarge:
            return "Compress the video or split it into smaller segments before transferring."
            
        case .connectionFailed, .networkUnavailable:
            return "Check your network connection and ensure both devices are on the same network."
            
        case .transferTimeout:
            return "Try transferring smaller files or check your network connection stability."
            
        case .transferCorrupted:
            return "Try transferring the file again. If the problem persists, check the source file."
            
        case .invalidIndex, .concurrentModification:
            return "Please refresh the library and try again."
            
        case .emptyLibrary:
            return "Add images or videos by using the iPhone app to send content to this device."
            
        case .focusSystemError:
            return "Try navigating with the remote control or restart the app if the issue persists."
            
        case .memoryPressure:
            return "Close other apps or restart this app to free up memory."
            
        case .backgroundTaskExpired:
            return "The operation took too long. Try again when the app is in the foreground."
            
        case .unknown:
            return "Try restarting the app. If the problem persists, contact support."
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .fileNotFound, .fileCorrupted, .unsupportedFormat, .thumbnailGenerationFailed, .emptyLibrary:
            return .warning
            
        case .videoDecodingFailed, .videoDurationInvalid, .videoTooLarge, .transferTimeout, .transferCorrupted, .invalidIndex, .concurrentModification, .focusSystemError:
            return .error
            
        case .insufficientStorage, .permissionDenied, .connectionFailed, .networkUnavailable, .memoryPressure:
            return .critical
            
        case .backgroundTaskExpired, .unknown:
            return .severe
        }
    }
    
    var shouldRetry: Bool {
        switch self {
        case .connectionFailed, .transferTimeout, .networkUnavailable, .concurrentModification, .memoryPressure:
            return true
        default:
            return false
        }
    }
    
    var category: ErrorCategory {
        switch self {
        case .fileNotFound, .fileCorrupted, .insufficientStorage, .permissionDenied, .unsupportedFormat:
            return .fileSystem
        case .videoDecodingFailed, .thumbnailGenerationFailed, .videoTooLarge, .videoDurationInvalid:
            return .video
        case .connectionFailed, .transferTimeout, .transferCorrupted, .networkUnavailable:
            return .network
        case .invalidIndex, .emptyLibrary, .concurrentModification, .focusSystemError:
            return .appState
        case .memoryPressure, .backgroundTaskExpired, .unknown:
            return .system
        }
    }
}

// MARK: - Supporting Types

enum ErrorSeverity {
    case info, warning, error, critical, severe
    
    var color: UIColor {
        switch self {
        case .info: return .systemBlue
        case .warning: return .systemOrange
        case .error: return .systemRed
        case .critical: return .systemPurple
        case .severe: return .systemPink
        }
    }
    
    var systemImageName: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .critical: return "exclamationmark.octagon"
        case .severe: return "exclamationmark.triangle.fill"
        }
    }
}

enum ErrorCategory {
    case fileSystem, video, network, appState, system
    
    var displayName: String {
        switch self {
        case .fileSystem: return "File System"
        case .video: return "Video Processing"
        case .network: return "Network"
        case .appState: return "App State"
        case .system: return "System"
        }
    }
}

// MARK: - Equatable Implementation
extension MediaError {
    static func == (lhs: MediaError, rhs: MediaError) -> Bool {
        switch (lhs, rhs) {
        case (.fileNotFound(let a), .fileNotFound(let b)):
            return a == b
        case (.fileCorrupted(let a, let ar), .fileCorrupted(let b, let br)):
            return a == b && ar == br
        case (.unsupportedFormat(let extA, let supportedA), .unsupportedFormat(let extB, let supportedB)):
            return extA == extB && supportedA == supportedB
        case (.connectionFailed(let a), .connectionFailed(let b)):
            return a == b
        case (.invalidIndex(let a, let am), .invalidIndex(let b, let bm)):
            return a == b && am == bm
        // Add other cases as needed, or use a simpler approach:
        default:
            return String(describing: lhs) == String(describing: rhs)
        }
    }
} 