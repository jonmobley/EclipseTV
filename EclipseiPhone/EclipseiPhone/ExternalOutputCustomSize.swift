//
//  ExternalOutputCustomSize.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CoreGraphics
import Foundation

/// A saved custom screen shape for the AirPlay / external-display picture.
///
/// Mirrors the Mac app's `ProgramAspectPreset`: width and height describe the
/// physical surface (e.g. a 512×786 LED wall) and only their ratio matters.
/// When one is active, the TV picture is the largest rect of that ratio that
/// fits the connected display, with black around it, and the phone's stages
/// frame content the same way.
struct ExternalOutputCustomSize: Codable, Identifiable, Equatable, Hashable {

    /// Smallest accepted edge, matching the Mac app.
    static let minimumEdge = 2

    /// Stable identity for selection and persistence.
    var id: UUID

    /// Label shown in Settings.
    var name: String

    /// Surface width (≥ `minimumEdge`).
    var width: Int

    /// Surface height (≥ `minimumEdge`).
    var height: Int

    init(id: UUID = UUID(), name: String, width: Int, height: Int) {
        self.id = id
        self.name = name
        self.width = max(Self.minimumEdge, width)
        self.height = max(Self.minimumEdge, height)
    }

    /// Width ÷ height of the output picture.
    var aspectRatio: CGFloat {
        CGFloat(width) / CGFloat(height)
    }

    /// Compact size, e.g. `512×786`.
    var sizeLabel: String { "\(width)×\(height)" }

    /// Name plus size, unless the name already carries the size.
    var displayLabel: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Custom" : trimmed
        return base.contains(sizeLabel) ? base : "\(base) (\(sizeLabel))"
    }

    /// Name used when the user leaves the field blank.
    static func defaultName(width: Int, height: Int) -> String {
        "\(max(minimumEdge, width))×\(max(minimumEdge, height))"
    }

    /// True when both edges are large enough to describe a screen.
    static func isValid(width: Int, height: Int) -> Bool {
        width >= minimumEdge && height >= minimumEdge
    }
}

// MARK: - Storage

extension ExternalOutputSettings {
    private static let customSizesKey = "EclipseTV.output.customSizes"
    private static let selectedCustomSizeKey = "EclipseTV.output.selectedCustomSizeID"

    /// Saved custom sizes, in the order they were added.
    static var customSizes: [ExternalOutputCustomSize] {
        get {
            guard let data = UserDefaults.standard.data(forKey: customSizesKey),
                  let sizes = try? JSONDecoder().decode([ExternalOutputCustomSize].self, from: data)
            else { return [] }
            return sizes
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: customSizesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: customSizesKey)
            }
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// The chosen custom size, or nil for the plain Landscape / Vertical picture.
    ///
    /// Kept while Display Mode is Vertical so switching back to Landscape
    /// restores it, like the Mac keeps its built-in mode under a custom preset.
    static var selectedCustomSizeID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: selectedCustomSizeKey) else {
                return nil
            }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: selectedCustomSizeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: selectedCustomSizeKey)
            }
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// The custom size shaping the output right now.
    ///
    /// Custom sizes apply in Landscape only: Vertical already rotates a 9:16
    /// picture onto the display, and a second shape on top would be ambiguous.
    static var activeCustomSize: ExternalOutputCustomSize? {
        guard orientation == .landscape, let id = selectedCustomSizeID else { return nil }
        return customSizes.first { $0.id == id }
    }

    /// Width ÷ height of the picture the TV shows: the active custom size, else
    /// 16:9 in Landscape and 9:16 in Vertical.
    static var outputAspectRatio: CGFloat {
        activeCustomSize?.aspectRatio ?? orientation.aspectRatio
    }

    /// Where the picture sits on the external display.
    ///
    /// Full screen for Landscape / Vertical (Vertical rotates the content to fill
    /// the display itself). With a custom size, the largest centered rect of that
    /// ratio that fits, leaving the rest black.
    static func outputStageRect(in bounds: CGRect) -> CGRect {
        guard activeCustomSize != nil else { return bounds }
        return displayModePanelRect(in: bounds)
    }

    // MARK: Editing

    /// Adds a custom size and makes it active.
    /// - Returns: The saved size, or nil when the edges are too small.
    @discardableResult
    static func addCustomSize(name: String, width: Int, height: Int) -> ExternalOutputCustomSize? {
        guard ExternalOutputCustomSize.isValid(width: width, height: height) else { return nil }
        let size = ExternalOutputCustomSize(
            name: resolvedName(name, width: width, height: height),
            width: width,
            height: height
        )
        customSizes.append(size)
        selectedCustomSizeID = size.id
        return size
    }

    /// Renames or resizes a saved custom size in place.
    /// - Returns: False when the size is missing or the edges are too small.
    @discardableResult
    static func updateCustomSize(id: UUID, name: String, width: Int, height: Int) -> Bool {
        guard ExternalOutputCustomSize.isValid(width: width, height: height) else { return false }
        var sizes = customSizes
        guard let index = sizes.firstIndex(where: { $0.id == id }) else { return false }
        sizes[index].name = resolvedName(name, width: width, height: height)
        sizes[index].width = width
        sizes[index].height = height
        customSizes = sizes
        return true
    }

    /// Deletes a custom size. If it was active, the picture returns to full screen.
    static func removeCustomSize(id: UUID) {
        var sizes = customSizes
        guard let index = sizes.firstIndex(where: { $0.id == id }) else { return }
        sizes.remove(at: index)
        if selectedCustomSizeID == id {
            UserDefaults.standard.removeObject(forKey: selectedCustomSizeKey)
        }
        customSizes = sizes
    }

    private static func resolvedName(_ name: String, width: Int, height: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? ExternalOutputCustomSize.defaultName(width: width, height: height)
            : trimmed
    }
}
