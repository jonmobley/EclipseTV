# Plan: card titles that match and sync (iPhone + Mac)

Owner decisions (2026-11-02):
- **Defaults:** the Mac's rule on both apps. Photos, videos, slideshows and PDFs start untitled;
  websites, cameras, PTZ, screens, polls, countdowns, apps and graphics show their name.
  Screensaver, Background and Desktop always show theirs and cannot be hidden.
- **Sync:** the title text *and* the Show/Hide choice sync to every device signed in to the same iCloud.
- **Shared Shows:** collaborators see the same titles (unlike presenter notes, which stay private).

## Today

| | iPhone (`EclipseTV`) | Mac (`eclipsepro`, newest branch `rail-pages-145`) |
|---|---|---|
| Photo/video title | `MediaTitleStore`: phone-only UserDefaults, never synced | `MediaItem.title`, sent to iCloud as `MediaItem.displayName` |
| PDF / web / slideshow / countdown / poll name | synced (`title` / `name` fields) | same records, same fields |
| Show/Hide choice | none; tool tiles always titled, media titled only if a title is set | `MediaItem.cardTitleShown` (Mac-local) + `MediaManager+CardTitle.swift` |
| Fixed titles | Screensaver, Background | Screensaver, Background, Desktop |

Both apps already use the same CloudKit container (`iCloud.com.mobleypro.eclipse.EclipseiPhone`),
zone `EclipseLibrary` and record types. The Mac reads them through `Packages/EclipseSyncKit`, the iPhone
through `EclipseiPhone/EclipseSync`. So nothing new has to be invented: one new field plus wiring.

## Design

1. **Title text = the existing `displayName` field** on `MediaItem` records (`title` / `name` on the other
   record types, unchanged). The iPhone stops keeping photo/video titles phone-only: "Add Title" /
   "Edit Title" writes `displayName`; incoming `displayName` updates the tile. Existing phone-only titles
   are uploaded once (same one-time pattern as presenter notes, commit 5722ce8).
2. **New field `titleShown` (Bool)** on `MediaItem`, `PDFDoc`, `WebPage`, `Slideshow`, `Countdown`,
   `LivePoll` records. Absent = "never chosen, use the default for the kind", so older records and older
   app builds keep working. Unlike `note`, it rides on shared-Show records too.
3. **One default table** in both apps (Mac's `showsTitleByDefault`). iPhone change people will notice:
   PDFs and slideshows stop showing a title until switched on; photos/videos with a title set keep showing it
   (their migrated `titleShown` = true).
4. **iPhone UI:** ⋯ menu gets "Show Title" / "Hide Title" on every tile except Screensaver and Background,
   next to the existing "Add/Edit Title". Mac already has the same menu items.
5. **Conflicts:** last change wins, like the other item settings; a pending local edit wins over an
   incoming one (existing prefs rule in `CloudKitSyncEngine+Apply`).

## Work, in order

1. **Shared sync code (Mac repo):** add `titleShown` to `EclipseSyncKit` (`SyncSchema` keys + the six
   record structs, read/write, tests). Mac: map `MediaItem.cardTitleShown` ⇄ `titleShown` in
   `ShowSyncMacStore`, sync edits made from the card menu.
2. **iPhone repo:** same key in `CloudKitSchema` + `CloudKitRecordMapper*`; a `CardTitleStore`
   (text + shown) replacing phone-only `MediaTitleStore`; one-time upload of old titles; default table;
   ⋯ menu items; tile reads the store. Tests for round-trip, absent field, migration, shared Show.
3. **Check together:** iPhone Simulator + Mac test copy on the same iCloud account: rename and hide on one,
   see it on the other within a sync cycle; shared Show with a second account if available.
4. **Ship both together** (like the pairing change): an iPhone TestFlight build and a Mac build that both
   understand `titleShown`. Older builds simply ignore the new field.

Rough size: 1–2 focused sessions per app. Steps 1 and 2 can run in parallel (separate repos) once the
field name is fixed as above.

## Needs the owner

- **iCloud schema for production:** CloudKit creates new fields automatically only in the *development*
  environment. Before a TestFlight/App Store build uses `titleShown`, the schema must be deployed to
  Production in the CloudKit Console (icloud.developer.apple.com → container
  `iCloud.com.mobleypro.eclipse.EclipseiPhone` → Deploy Schema Changes). That needs your Apple login.
  Worth checking whether the presenter-note field (`note`) was deployed the same way.
- Approving the TestFlight and Mac release when they're ready.
