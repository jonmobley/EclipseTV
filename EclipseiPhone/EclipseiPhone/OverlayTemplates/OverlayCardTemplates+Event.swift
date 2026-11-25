//
//  OverlayCardTemplates+Event.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Event-oriented card templates (Up Next, Event Title, Now
//               Playing). Pure data descriptors consumed by the template picker
//               and editor; wired into `OverlayCardTemplate.all`.
//  Thread Safety: Value types - no shared mutable state.
//

import SwiftUI

// MARK: - Event Templates

extension OverlayCardTemplate {

    /// Field keys for the Up Next template.
    enum UpNextKey {
        static let item = "item"
    }

    /// A fixed "Up Next" label above the name of what's coming next.
    static let upNext = OverlayCardTemplate(
        kind: .upNext,
        displayName: "Up Next",
        menuIcon: "forward.fill",
        cardIcon: "forward.end.fill",
        category: .event,
        fields: [
            OverlayCardField(key: UpNextKey.item, label: "What's Next",
                             placeholder: "Segment or session name", isSecure: false)
        ],
        previewFields: [
            UpNextKey.item: "Keynote"
        ],
        defaultStyle: OverlayCardLook.standard.style(),
        title: { _ in "Up Next" },
        subtitle: { fields in trimmed(fields, UpNextKey.item) }
    )

    /// Field keys for the Event Title template.
    enum EventTitleKey {
        static let title = "title"
        static let detail = "detail"
    }

    /// A prominent event name with an optional time/location line.
    static let eventTitle = OverlayCardTemplate(
        kind: .eventTitle,
        displayName: "Event Title",
        menuIcon: "calendar",
        cardIcon: "calendar",
        category: .event,
        fields: [
            OverlayCardField(key: EventTitleKey.title, label: "Event",
                             placeholder: "Event name", isSecure: false),
            OverlayCardField(key: EventTitleKey.detail, label: "Time / Location",
                             placeholder: "When or where", isSecure: false)
        ],
        previewFields: [
            EventTitleKey.title: "Summer Conference",
            EventTitleKey.detail: "Sat 10:00 AM - Main Hall"
        ],
        defaultStyle: OverlayCardLook.standard.style(),
        title: { fields in trimmed(fields, EventTitleKey.title) ?? "Event" },
        subtitle: { fields in trimmed(fields, EventTitleKey.detail) }
    )

    /// Field keys for the Now Playing template.
    enum NowPlayingKey {
        static let title = "title"
        static let artist = "artist"
    }

    /// Current media or segment — distinct from Up Next (upcoming).
    static let nowPlaying = OverlayCardTemplate(
        kind: .nowPlaying,
        displayName: "Now Playing",
        menuIcon: "play.circle.fill",
        cardIcon: "play.fill",
        category: .event,
        fields: [
            OverlayCardField(key: NowPlayingKey.title, label: "Title",
                             placeholder: "Song or segment", isSecure: false),
            OverlayCardField(key: NowPlayingKey.artist, label: "Artist / Source",
                             placeholder: "Artist or source", isSecure: false)
        ],
        previewFields: [
            NowPlayingKey.title: "Horizon Line",
            NowPlayingKey.artist: "North Echo"
        ],
        defaultStyle: OverlayCardLook.standard.style(showsIcon: true),
        title: { _ in "Now Playing" },
        subtitle: { fields in nowPlayingSubtitle(fields) }
    )

    private static func nowPlayingSubtitle(_ fields: [String: String]) -> String? {
        let title = trimmed(fields, NowPlayingKey.title)
        let artist = trimmed(fields, NowPlayingKey.artist)
        switch (title, artist) {
        case let (title?, artist?): return "\(title) — \(artist)"
        case let (title?, nil): return title
        case let (nil, artist?): return artist
        case (nil, nil): return nil
        }
    }

    /// Field keys for the Agenda Item template.
    enum AgendaItemKey {
        static let time = "time"
        static let item = "item"
    }

    /// Schedule row: time label with agenda item title.
    static let agendaItem = OverlayCardTemplate(
        kind: .agendaItem,
        displayName: "Agenda",
        menuIcon: "list.bullet.rectangle",
        cardIcon: "list.bullet",
        category: .event,
        fields: [
            OverlayCardField(key: AgendaItemKey.time, label: "Time",
                             placeholder: "10:30 AM", isSecure: false),
            OverlayCardField(key: AgendaItemKey.item, label: "Item",
                             placeholder: "Session name", isSecure: false)
        ],
        previewFields: [
            AgendaItemKey.time: "10:30 AM",
            AgendaItemKey.item: "Breakout Sessions"
        ],
        defaultStyle: OverlayCardLook.standard.style(),
        title: { fields in trimmed(fields, AgendaItemKey.time) ?? "Time" },
        subtitle: { fields in trimmed(fields, AgendaItemKey.item) }
    )

    /// Field keys for the Location / Room template.
    enum LocationCalloutKey {
        static let place = "place"
        static let detail = "detail"
    }

    /// Room change or wayfinding callout for events and venues.
    static let locationCallout = OverlayCardTemplate(
        kind: .locationCallout,
        displayName: "Location / Room",
        menuIcon: "mappin.and.ellipse",
        cardIcon: "mappin.circle.fill",
        category: .event,
        fields: [
            OverlayCardField(key: LocationCalloutKey.place, label: "Location",
                             placeholder: "Main Hall", isSecure: false),
            OverlayCardField(key: LocationCalloutKey.detail, label: "Detail",
                             placeholder: "Directions or note", isSecure: false)
        ],
        previewFields: [
            LocationCalloutKey.place: "Ballroom B",
            LocationCalloutKey.detail: "Take the south elevators"
        ],
        defaultStyle: OverlayCardLook.standard.style(showsIcon: true),
        title: { fields in trimmed(fields, LocationCalloutKey.place) ?? "Location" },
        subtitle: { fields in trimmed(fields, LocationCalloutKey.detail) }
    )
}
