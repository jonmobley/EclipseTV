//
//  PreviewShareSheet.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension UIViewController {

    /// System share sheet for the previewed file.
    ///
    /// Handing over the file URL (rather than a decoded `UIImage`) is what puts
    /// Save Image / Save Video in the sheet at full resolution, alongside AirDrop,
    /// Messages, and Files. `NSPhotoLibraryAddUsageDescription` already covers the
    /// save, so no separate permission prompt is needed here.
    ///
    /// - Parameters:
    ///   - url: On-device media file to share.
    ///   - source: Button the sheet points at on iPad.
    func presentPreviewShareSheet(for url: URL, from source: UIView) {
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = source
        sheet.popoverPresentationController?.sourceRect = source.bounds
        present(sheet, animated: true)
    }
}
