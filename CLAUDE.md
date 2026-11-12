# Eclipse: notes for Claude

- **PTZ Camera** (OBSBOT) comes from the shared package `~/apps/CamTail/Packages/CamTailKit`
  (also used by the CamTail app). All camera-control feature code belongs there, never in
  Eclipse; Eclipse only hosts it (tile `LibraryThumbnailCell+PTZCamera`, hero
  `LiveHeaderView+PTZPreview`, AirPlay `PresentationViewController+PTZCamera`, controls
  `LibraryGridViewController+PTZCamera`). After any CamTailKit change run
  `~/apps/CamTail/tools/build_all.sh`, which builds and tests both apps.
- Device builds need the NDI SDK at `/Library/NDI SDK for Apple` (linker flags in the
  EclipseiPhone target, `[sdk=iphoneos*]` only).
- All unit tests pass (1127, 2026-10-31). `snapshotView(afterScreenUpdates:)` can return
  nil on iOS 26; LiveHeaderView falls back to a rendered still so dissolves don't hard-cut.
- Menus on grid tiles (⋯, full-tile Add) use `ScrollSafeMenuButton`, never a plain `UIButton`
  with `showsMenuAsPrimaryAction`: UIKit opens those on touch-down, so starting a scroll on ⋯
  popped the menu (2026-10-19). It opens on a clean tap, ignores taps mid-glide, and lets drags
  that start on it scroll the grid.
- UI tests: if the iPhone simulator refuses to launch the test runner ("request was denied
  by service delegate"), run them on another simulator; it's a simulator state problem.
- **Pairing protocol is `EclipseShare/v3`** (2026-10-15): each iPhone sends a random device key
  (Keychain `pairing.deviceKey`); the TV remembers phones by its SHA-256, never by device name
  (iOS 16+ names are all "iPhone"). iPhone and Apple TV builds must ship together. Known limit:
  the key travels in the Multipeer invitation, so a fake TV on the same Wi-Fi could capture it.
- For 1.0, "Albums by code" / "Enter Share Code" are hidden (`AlbumConfig.offersAccountCodeEntry`);
  the TV re-syncs albums every 5 min instead of a Supabase Realtime socket (no Lovable dependency
  except the aircamtv.com manifest).
  **Owner wants both back after 1.0 is approved** (decided 2026-10-18): instant album updates and
  a way to create albums. They were turned off only for App Review (a code screen with no public
  way to get a code is a dead end; realtime tied the TV to the Lovable Supabase project). Plan:
  move albums off Lovable (e.g. the owner's iCloud, like Mac Show sync), let people create albums
  in the iPhone app, then flip `offersAccountCodeEntry` on (both apps) and restore instant updates.
  The old realtime code is in git before 277d4f2 (`RealtimeAlbumNotifier.swift`).
- App Store screenshots (Apple TV, 2026-10-15): build Release for a throwaway tvOS simulator, copy media into
  `Library/Caches/Media/Landscape`, and set the library list with
  `simctl spawn <udid> defaults write <container>/Library/Preferences/com.mobleypro.eclipse.EclipseTV EclipseTV.recentImagesKey.landscape -array a.jpg …`
  (a plain domain write or editing the plist directly is ignored, and the app then deletes the files as orphans).
  Drive the remote with osascript key codes to Simulator (123/124 arrows, 36 select, 53 Menu).

- Custom screen sizes on iPhone (AirPlay only, 2026-11-11): Settings → Display Mode → Screen Size saves
  named width×height shapes (`ExternalOutputCustomSize`, JSON in UserDefaults). They apply in Landscape only;
  the selection is kept but inactive in Vertical. `PresentationViewController.stageView` is sized by
  `ExternalOutputSettings.outputStageRect` (full screen unless a custom size is active) and every content
  container is constrained to it, so new TV overlays must attach to `stageView`, not `view`. Anything that
  mirrors the TV picture (phone camera / web / prompter stages, `webLogicalSize`, `displayModePanelRect`)
  and `MediaAspect.activeTarget` (Fit/Fill, still Reframe) read `ExternalOutputSettings.outputAspectRatio`; anything that
  rewrites a file (video re-crop) uses `MediaAspect.libraryTarget`. Grid tiles, media buckets and the Apple TV protocol still
  use `orientation` and know nothing about custom sizes.
- Crash reports: `CrashReporting.swift` in each app sends crashes and freezes to Sentry projects `eclipse-iphone` and `eclipse-appletv` (Release builds only; `scrub` keeps crash type, code location and device model, and drops all free text and activity trails; the `0.0.0.0` user address is what stops Sentry reading a city from the connection, since neither its IP setting nor `infer_ip` did). Upload symbols after each archive so reports are readable. App Privacy answers must list Crash Data and Other Diagnostic Data, not linked to the user, no tracking.

## TestFlight builds

- The iPhone project reads LivePollKit / EclipsePhoneCameraClient from `../../eclipsepro/Packages` (and CamTailKit from `../../CamTail`), i.e. whatever branch `~/apps/eclipsepro` has checked out. To archive against eclipsepro `main` without touching that checkout, lay out worktrees side by side in a scratch dir (`<dir>/EclipseTV`, `<dir>/eclipsepro`, `<dir>/CamTail` symlink) and archive from there.
- Build numbers: current scheme is `YYYYMMDDNN`; pass it explicitly (`Scripts/set_build_number.sh 2026101801`) since the script's default `YYYYMMDD.minute` sorts below it.
- Upload from the CLI: `xcodebuild archive … -allowProvisioningUpdates`, then `xcodebuild -exportArchive` with `method=app-store-connect`, `destination=upload`, team `2YBTPD32DW`. Xcode's signed-in account is enough; the WebRTC "Upload Symbols Failed" warning is expected.
- Website fullscreen on iPhone/iPad (`WebRemoteViewController`, 2026-11-04): every website card of the
  open Show is a tab (`BrowserTabList`, strip above the card, shown with 2+ tabs); the TV follows the
  active tab. Windows a site opens (`window.open`, sign-in) are phone-only tabs until "Send to TV".
  Landscape buttons (Close · ⋯ · Refresh · ⊕, then Send to TV / Back only when they apply) sit in a
  column beside the card on a phone; iPad gets a browser-style top bar (chips left, buttons top right)
  in both orientations, since iPadOS ignores the orientation lock while the app supports Split View.
- Seeding a simulator with websites/Shows for a visual check: the stores are JSON blobs in
  UserDefaults (`EclipseTV.pages.items`, `EclipseTV.localAlbums.items`); write them with
  `simctl spawn <udid> defaults write <container>/Library/Preferences/com.mobleypro.eclipse.EclipseiPhone.plist <key> -data <hex-json>`
  (dates are seconds since 2001). Open a website fullscreen by tapping its card, then the hero's expand arrows.
- Show grid scrolling (2026-11-07): `openShowGridItems` is rebuilt on every read and is read several
  times per tile, so anything it calls must be cheap. Look up library items with `store.item(id:)`
  (O(1) index), never `store.items.first(where:)`, and resolve the rows once before looping over paths.
- Note cards: tap expands or collapses, and the pencil edits (2026-10-31).
- Note editor on iPhone is a full-height sheet only: a medium detent gets pushed to large by the keyboard, which looks like a stall halfway up (2026-11-01). The text stops at `keyboardLayoutGuide`, and Hide Keyboard shows while editing because Done closes the editor.
