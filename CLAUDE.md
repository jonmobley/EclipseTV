# Eclipse: notes for Claude

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
- UI tests: if the iPhone simulator refuses to launch the test runner ("request was denied
  by service delegate"), run them on another simulator; it's a simulator state problem.
- **Pairing protocol is `EclipseShare/v3`** (2026-10-15): each iPhone sends a random device key
  (Keychain `pairing.deviceKey`); the TV remembers phones by its SHA-256, never by device name
  (iOS 16+ names are all "iPhone"). iPhone and Apple TV builds must ship together. Known limit:
  the key travels in the Multipeer invitation, so a fake TV on the same Wi-Fi could capture it.
- For 1.0, "Albums by code" / "Enter Share Code" are hidden (`AlbumConfig.offersAccountCodeEntry`);
  the TV re-syncs albums every 5 min instead of a Supabase Realtime socket (no Lovable dependency
  except the aircamtv.com manifest).
