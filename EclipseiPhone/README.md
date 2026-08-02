# Eclipse iPhone

Operator app for Eclipse: curate **Shows**, present on **AirPlay**, optionally link the **Eclipse Apple TV** app over Multipeer, and sync Shows across iPhones with **CloudKit**.

Built around a Shows-first home (Recent Shows → open Show grid with live hero), not a one-off pick-and-send flow.

## Sync planes

| Plane | Role | Scope |
|-------|------|--------|
| **Multipeer** | Primary path for Apple TV media | Imported library items → TV; play / delete / reorder / video settings |
| **CloudKit Eclipse Sync** | Multi-iPhone Shows & captures | Same Apple ID / Share Show; **TV does not participate** |
| **HTTPS remote albums** | Read-only hosted albums | 6-digit account code → `aircamtv.com` (separate from Shows) |

**Rule of thumb:** AirPlay works without EclipseTV linked. Multipeer is for the Eclipse TV *app* library. Captures never upload to Apple TV.

## Core features

### Shows
- Named collections: media, screensaver / logo / camera tools, websites, PDFs, slideshows
- Home = Recent Shows; opening a Show reveals the live hero + member grid
- Display Mode (Landscape / Vertical) scopes which Shows appear

### AirPlay presentation
- App-owned external window; phone UI stays interactive
- Sources: image, video (loop/mute), screensaver, camera, web, PDF, black
- Full-res copies live in `LocalMediaStore` for offline AirPlay

### EclipseTV Multipeer link
- Encrypted discovery (`eclipse-share`)
- Mirror / control the TV library; multi-TV keep-in-sync optional
- Re-send items purged from tvOS Caches

### Live camera
- Shared capture session for tile + fullscreen + AirPlay
- In-app captures stay phone-local (CloudKit may sync; Multipeer never)

### Ambient music
- Local tracks / playlists; mini player bubble ↔ footer bar
- Yields with **pause** (not stop) when unmuted video / web media plays

## Video tile options (⋯)

- **Loop** / **Mute** — checkmark toggles (local + TV when linked; refreshes live AirPlay)
- **Thumbnail** — same frame scrubber as add-video; updates poster on phone (+ TV when linked)
- **Preview** — in-app player (honors loop/mute)

## Thumbnail memory

Decoded grid thumbs use purgeable `NSCache` + **visible pins** + on-disk JPEG cache. Go-live may purge `NSCache`; on-screen tiles stay painted via pins and `reloadLibraryGrid()`.

## TestFlight — Show → Present checklist

1. Open a Show with many media tiles; confirm thumbs paint.
2. Tap a **video** to go live on AirPlay — grid must **not** go blank.
3. ⋯ → Loop / Mute — checkmarks stick; live AirPlay follows.
4. ⋯ → Thumbnail — scrubber updates poster; tile refreshes.
5. ⋯ → Preview — video plays in-app with loop/mute.
6. With EclipseTV linked: same item goes live on TV; loop/mute/thumbnail reach the TV.
7. Tap a **capture** (if any): AirPlay only — never Multipeer upload.

## CloudKit verification

See [EclipseSync-VERIFICATION.md](EclipseSync-VERIFICATION.md).

## Requirements

- iOS 16.0+
- Xcode 15.0+ (development)
- Local Network + Photos (+ Camera / Microphone as needed)
- Optional: Eclipse Apple TV on the same Wi‑Fi; iCloud for Eclipse Sync

## Architecture (high level)

```
Shows (LocalAlbumStore) ──► LibraryGridViewController
        │                         │
        │                    go live
        ▼                         ▼
LocalMediaStore ──► ExternalDisplayManager → PresentationViewController (AirPlay)
        │
        └──► iPhoneConnectionManager (Multipeer) → Eclipse Apple TV library

EclipseSyncController (CloudKit) ──► Shows / captures across iPhones (TV out)
AlbumBrowserStore (HTTPS) ──► read-only hosted albums
```

Key types: `PresentationSource`, `TVLibraryStore`, `ThumbnailMemoryCache`, `AudioAmbientPolicy`, `EclipseSyncTVPolicy`.
