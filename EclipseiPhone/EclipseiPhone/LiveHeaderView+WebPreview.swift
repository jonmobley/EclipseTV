//
//  LiveHeaderView+WebPreview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - In-App Live Website Preview

extension LiveHeaderView {

    /// Shows the warm website session in the home hero (works without AirPlay).
    /// - Parameter pageId: Live free-browse or bookmark id.
    func showWebPreview(pageId: UUID) {
        if webPreviewPageId != pageId {
            clearWebPreview(parking: true)
        }
        ensureWebPreviewHost()
        guard let host = webPreviewHost,
              WarmWebSessionPool.shared.attachPreview(pageId: pageId, to: host)
        else {
            webPreviewHost?.isHidden = true
            return
        }
        webPreviewPageId = pageId
        host.isHidden = false
        setStaticPreviewHidden(true)
        bringWebPreviewChromeToFront()
    }

    /// Removes any in-hero web preview.
    /// - Parameter parking: When true, returns the web view to the off-screen warm host.
    func clearWebPreview(parking: Bool) {
        if parking, let pageId = webPreviewPageId {
            WarmWebSessionPool.shared.parkPreview(pageId: pageId)
        }
        webPreviewPageId = nil
        webPreviewHost?.isHidden = true
        setStaticPreviewHidden(false)
    }
}
