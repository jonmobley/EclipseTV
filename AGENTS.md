# Eclipse: notes for Codex

- **PTZ Camera** (OBSBOT) comes from the shared package `~/apps/CamTail/Packages/CamTailKit`
  (also used by the CamTail app). All camera-control feature code belongs there, never in
  Eclipse; Eclipse only hosts it (tile `LibraryThumbnailCell+PTZCamera`, hero
  `LiveHeaderView+PTZPreview`, AirPlay `PresentationViewController+PTZCamera`, controls
  `LibraryGridViewController+PTZCamera`). After any CamTailKit change run
  `~/apps/CamTail/tools/build_all.sh`, which builds and tests both apps.
- Device builds need the NDI SDK at `/Library/NDI SDK for Apple` (linker flags in the
  EclipseiPhone target, `[sdk=iphoneos*]` only).
- All unit tests pass (1085, 2026-10-02). `snapshotView(afterScreenUpdates:)` can return
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

## TestFlight builds

- The iPhone project reads LivePollKit / EclipsePhoneCameraClient from `../../eclipsepro/Packages` (and CamTailKit from `../../CamTail`), i.e. whatever branch `~/apps/eclipsepro` has checked out. To archive against eclipsepro `main` without touching that checkout, lay out worktrees side by side in a scratch dir (`<dir>/EclipseTV`, `<dir>/eclipsepro`, `<dir>/CamTail` symlink) and archive from there.
- Build numbers: current scheme is `YYYYMMDDNN`; pass it explicitly (`Scripts/set_build_number.sh 2026101801`) since the script's default `YYYYMMDD.minute` sorts below it.
- Upload from the CLI: `xcodebuild archive … -allowProvisioningUpdates`, then `xcodebuild -exportArchive` with `method=app-store-connect`, `destination=upload`, team `2YBTPD32DW`. Xcode's signed-in account is enough; the WebRTC "Upload Symbols Failed" warning is expected.
