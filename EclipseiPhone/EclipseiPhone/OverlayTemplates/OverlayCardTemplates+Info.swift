//
//  OverlayCardTemplates+Info.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Informational card templates (Wi-Fi, Announcement, Chapter).
//               Each is a pure data descriptor consumed by the template picker
//               and editor; adding one requires only a new
//               `OverlayCardTemplateKind` case and a descriptor here.
//  Thread Safety: Value types - no shared mutable state.
//

import SwiftUI

// MARK: - Info Templates

extension OverlayCardTemplate {

    /// Field keys for the Wi-Fi template.
    enum WiFiKey {
        static let ssid = "ssid"
        static let password = "password"
    }

    /// Shows a network name with its password underneath. Uses a monospaced
    /// design so passwords stay legible.
    static let wifi = OverlayCardTemplate(
        kind: .wifi,
        displayName: "Wi-Fi",
        menuIcon: "wifi",
        cardIcon: "wifi",
        category: .connectivity,
        fields: [
            OverlayCardField(key: WiFiKey.ssid, label: "Network Name",
                             placeholder: "Network name", isSecure: false),
            OverlayCardField(key: WiFiKey.password, label: "Password",
                             placeholder: "Password", isSecure: true)
        ],
        previewFields: [
            WiFiKey.ssid: "Guest Wi-Fi",
            WiFiKey.password: "sunrise2026"
        ],
        defaultStyle: wifiDefaultStyle,
        title: { fields in trimmed(fields, WiFiKey.ssid) ?? "Wi-Fi" },
        subtitle: { fields in trimmed(fields, WiFiKey.password) }
    )

    /// Field keys for the Announcement template.
    enum AnnouncementKey {
        static let heading = "heading"
        static let detail = "detail"
    }

    /// Shows a bold heading with an optional detail line underneath.
    static let announcement = OverlayCardTemplate(
        kind: .announcement,
        displayName: "Announcement",
        menuIcon: "megaphone.fill",
        cardIcon: "megaphone",
        category: .info,
        fields: [
            OverlayCardField(key: AnnouncementKey.heading, label: "Heading",
                             placeholder: "Heading", isSecure: false),
            OverlayCardField(key: AnnouncementKey.detail, label: "Detail",
                             placeholder: "Detail", isSecure: false)
        ],
        previewFields: [
            AnnouncementKey.heading: "Doors open at 6:30",
            AnnouncementKey.detail: "Overflow seating in the lobby"
        ],
        defaultStyle: OverlayCardLook.standard.style(),
        title: { fields in trimmed(fields, AnnouncementKey.heading) ?? "Announcement" },
        subtitle: { fields in trimmed(fields, AnnouncementKey.detail) }
    )

    /// Field keys for the Chapter / Segment template.
    enum ChapterMarkerKey {
        static let label = "label"
        static let title = "title"
    }

    /// Compact chapter or segment marker for corporate and education flows.
    static let chapterMarker = OverlayCardTemplate(
        kind: .chapterMarker,
        displayName: "Chapter / Segment",
        menuIcon: "bookmark.fill",
        cardIcon: "bookmark.fill",
        category: .info,
        fields: [
            OverlayCardField(key: ChapterMarkerKey.label, label: "Chapter",
                             placeholder: "Chapter 3", isSecure: false),
            OverlayCardField(key: ChapterMarkerKey.title, label: "Title",
                             placeholder: "Segment title", isSecure: false)
        ],
        previewFields: [
            ChapterMarkerKey.label: "Chapter 3",
            ChapterMarkerKey.title: "Market Outlook"
        ],
        defaultStyle: OverlayCardLook.standard.style(),
        title: { fields in trimmed(fields, ChapterMarkerKey.label) ?? "Chapter" },
        subtitle: { fields in trimmed(fields, ChapterMarkerKey.title) }
    )

    /// Wi-Fi keeps a monospaced face so passwords show every glyph clearly
    /// (l vs 1, O vs 0); the look still supplies plate, accent, and radius.
    private static var wifiDefaultStyle: OverlayCardStyle {
        var style = OverlayCardLook.standard.style(showsIcon: true)
        style.fontDesign = .monospaced
        return style
    }
}
