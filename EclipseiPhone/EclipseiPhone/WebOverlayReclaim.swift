//
//  WebOverlayReclaim.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Whether a phone-browser navigation may put its page back on live output.
enum WebOverlayReclaim {

    /// True only when the last thing presented is still a web page.
    ///
    /// The browser mirrors every committed navigation onto live output, and it
    /// outlives the page's turn on program: closing it does not stop output, and
    /// output can change from the grid behind it. So a late commit has to be able
    /// to restore an overlay this page still owns — after an AirPlay drop, say —
    /// without claiming program back from the still, slideshow, or tool that
    /// replaced it, which left the website's card carrying a red live stroke
    /// beside the card that was really live.
    static func allowsRestore(lastContent: PresentationSource.Content?) -> Bool {
        if case .web = lastContent { return true }
        return false
    }
}
