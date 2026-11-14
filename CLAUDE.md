# Eclipse: notes for Claude

- **PTZ Camera** (OBSBOT) comes from the shared package `~/apps/CamTail/Packages/CamTailKit`
  (also used by the CamTail app). All camera-control feature code belongs there, never in
  Eclipse; Eclipse only hosts it (tile `LibraryThumbnailCell+PTZCamera`, hero
  `LiveHeaderView+PTZPreview`, AirPlay `PresentationViewController+PTZCamera`, controls
  `LibraryGridViewController+PTZCamera`). Tile and hero host CamTailKit's status-aware
  `CamTailLivePreview` via `CamTailPreviewHost` (AirPlay keeps the plain picture); a tile tap
  with no camera connected opens the controls, which are CamTailKit's setup screen (2026-11-11). After any CamTailKit change run
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
  Z-order on the TV picture goes through `stageView.bringSubviewToFront` (transition overlay, audio badge);
  `view.bringSubviewToFront` on a stage subview is a no-op.
- Leaving a live countdown (2026-11-13): `endOverlay` moves output state on *before* tearing the overlay down,
  same order as `beginOverlay`. Ending the clock posts its change synchronously, and if `overlaySource` still says
  countdown the grid repaints the hero back onto the frozen clock (countdown posts no end notice to fix it).
- iPhone UI from the AirPlay branch (2026-11-13): the hero's Fit / Fill toggle shows the words, not an icon (menus keep
  icons); tile menus say "Camera Controls" and "PTZ Controls"; Home Recent Shows uses two columns in panes under 500pt.
- Settings notifications are expensive and reach the camera (2026-11-12): `ExternalOutputSettings.didChangeNotification`
  observers re-sync the library, refresh the camera tile (start/stop of the capture session) and re-lay-out every
  `PresentationViewController`. `CameraPreviewView.layoutSubviews` talks to the capture connection, so never force a
  layout pass (`layoutIfNeeded`) from that notification unless a frame really changed; doing so on every post made the
  camera suites crash (`AVCaptureSession.stopRunning` throws on the simulator) or hang under CI's parallel test mode.
  Setters that post it should post only on a real change. CI runs the iPhone unit tests in the default parallel mode,
  which is far more sensitive than the local `-parallel-testing-enabled NO` runs; before pushing anything that touches
  settings observers or test fixtures, run the suite once the CI way (`xcodebuild test … -quiet`, no parallel flag).
  Root cause of those hangs/crashes: on the simulator `AVCaptureVideoPreviewLayer.session = stubSession` waits in a
  nested run loop inside `commitConfiguration`, so other main-actor tests run *inside* a camera test (UIKit animation
  state crashes, `stopRunning` exceptions, or a wait that never ends). `CameraPreviewView.attach` therefore never binds
  the session on the simulator (same as `detach`); keep it that way.
- Crash reports: `CrashReporting.swift` in each app sends crashes and freezes to Sentry projects `eclipse-iphone` and `eclipse-appletv` (Release builds only; `scrub` keeps crash type, code location and device model, and drops all free text and activity trails; the `0.0.0.0` user address is what stops Sentry reading a city from the connection, since neither its IP setting nor `infer_ip` did). Upload symbols after each archive so reports are readable. App Privacy answers must list Crash Data and Other Diagnostic Data, not linked to the user, no tracking.

## TestFlight builds

- The iPhone project reads LivePollKit / EclipsePhoneCameraClient from `../../eclipsepro/Packages` (and CamTailKit from `../../CamTail`), i.e. whatever branch `~/apps/eclipsepro` has checked out. To archive against eclipsepro `main` without touching that checkout, lay out worktrees side by side in a scratch dir (`<dir>/EclipseTV`, `<dir>/eclipsepro`, `<dir>/CamTail` symlink) and archive from there.
- Build numbers: current scheme is `YYYYMMDDNN`; pass it explicitly (`Scripts/set_build_number.sh 2026101801`) since the script's default `YYYYMMDD.minute` sorts below it.
- Upload from the CLI: `xcodebuild archive … -allowProvisioningUpdates`, then `xcodebuild -exportArchive` with `method=app-store-connect`, `destination=upload`, team `2YBTPD32DW`. Xcode's signed-in account is enough; the WebRTC "Upload Symbols Failed" warning is expected.
- Website fullscreen on iPhone/iPad (`WebRemoteViewController`, 2026-11-04): every website card of the
  open Show is a tab (`BrowserTabList`, strip above the card, shown with 2+ tabs); the TV follows the
  active tab. Windows a site opens (`window.open`, sign-in) are phone-only tabs until "Send to TV".
  Landscape buttons (Close · history · Refresh, then ⊕ only with a single tab, Send to TV / Back only
  when they apply) sit in a column beside the card on a phone; with 2+ tabs ⊕ ends the tab chips
  instead (`BrowserTabStripView.newTabButton`). The history clock opens History: on iPhone a drawer (`WebHistoryDrawerView`, from the right in Landscape, from the
  bottom in Vertical) with Saved and Recent; on iPad a pop-up menu with the same two sections. Recent is the last 30 pages
  the phone finished loading in a tab (`WebHistoryStore`, UserDefaults `EclipseTV.web.recentPages`, phone only), and
  picking one loads it in the active tab. The overlay buttons are re-raised on every layout, so the drawer is re-raised after them.
  Website Auto Scroll was removed (2026-11-13); `ScrollSpeedSlider` now serves only the Prompter. iPad gets a browser-style top bar (chips left, buttons top right)
  in both orientations, since iPadOS ignores the orientation lock while the app supports Split View.
  The website card matches the hero preview: 16pt corners and a 1pt `separator` hairline (2026-11-13).
- Seeding a simulator with websites/Shows for a visual check: the stores are JSON blobs in
  UserDefaults (`EclipseTV.pages.items`, `EclipseTV.localAlbums.items`); write them with
  `simctl spawn <udid> defaults write <container>/Library/Preferences/com.mobleypro.eclipse.EclipseiPhone.plist <key> -data <hex-json>`
  (dates are seconds since 2001). Open a website fullscreen by tapping its card, then the hero's expand arrows.
- Show grid scrolling (2026-11-07): `openShowGridItems` is rebuilt on every read and is read several
  times per tile, so anything it calls must be cheap. Look up library items with `store.item(id:)`
  (O(1) index), never `store.items.first(where:)`, and resolve the rows once before looping over paths.
- Adding content never changes live output (2026-11-10). History opens a website phone-only
  (`WebRemoteViewController(previewOnly:)`); Send to TV is the explicit go-live. Feedback review and
  phased plan: `docs/reviews/2026-11-10-iphone-feedback-review.md`.
- Show website card tap (2026-11-13): only puts the site live (hero shows it); the hero tap / expand arrows or ⋯ Preview open
  the fullscreen browser. Closing it leaves the site live on whatever page it was on, and re-tapping the live card changes nothing.
  With no destination (or output locked) the tap still opens the browser as a phone preview.
- Note cards: tap expands or collapses, and the pencil edits (2026-10-31).
- Note editor on iPhone is a full-height sheet only: a medium detent gets pushed to large by the keyboard, which looks like a stall halfway up (2026-11-01). The text stops at `keyboardLayoutGuide`, and Hide Keyboard shows while editing because Done closes the editor.
- Blackout hold (iPhone, 2026-11-13, `LibraryGridViewController+BlackoutHold.swift`): while Blackout is on the TV stays
  black and the phone stays usable. Tile taps open a private Preview (`prefersPhonePreviewOnTap(isBlackoutHolding:)`),
  the held video scrubs muted in the hero, and ⋯ › Show After Blackout cues what follows (`blackoutCue`, "UP NEXT" pill).
  Ending Blackout puts the cue live (videos paused), else restores what was live (video paused at the scrub, slideshow
  on its slide). Operators are never held. Tools with no private Preview (camera, poll, countdown, prompter, slideshows)
  show a toast instead. Apple TV gets paused video via the optional `startsPaused` field on `play_request`; older TV
  builds ignore it and just play, so ship iPhone and Apple TV together.
- Several Prompters per Show (2026-11-13): the first keeps token `__eclipse.tool.prompter` and the
  Show-id script (`prompter-<showId>`, which the Mac reads too); extras are
  `__eclipse.tool.prompter.<nonce>` whose script id is `ShowToolToken.extraPrompterScriptId(nonce:showId:)`
  (SHA-256 of Show id + nonce, shaped as a version-8 UUID). So a token only ever reaches its own
  Show's scripts, wherever it is planted, and never a Show's own (version-4) id. Records reuse the
  `Prompter` type, so no iCloud schema or Mac change. `PrompterScript.showId` is really the script
  key. Copy to Show makes a new Prompter with a copy of the text. There is one `PrompterController`,
  so the TV shows whatever script is bound; opening a different Prompter while one is live asks first.
- Prompter shape (2026-11-13): the Prompter screen has its own Landscape / Vertical menu (`PrompterLocalSettings.prefersVertical`,
  this phone only). Vertical while Display Mode is Landscape makes the card 9:16, turns the phone upright, and shows an upright
  9:16 column on the TV (`PrompterController.isVerticalOnLandscapeDisplay`); the menu is hidden in Vertical Display Mode.
  Use `PrompterController.isVertical` / `canvasAspectRatio` for prompter layout, never `ExternalOutputSettings.isVerticalMode`.
  The blue reading-guide lines were removed (2026-11-13, owner found them confusing); the line read sits mid-stage.
  The blue lines are the reading guide (the line being read), on purpose.
- Camera Presets (2026-11-13): a Show tile = phone camera + one saved frame. Stored only as the surface token
  `__eclipse.tool.cameraPreset.<frameUUID>` (`ShowCameraPresetToken`, counts as a tool), so it syncs with the Show and
  older builds keep it. Saved from the Camera tile ⋯ → Save as Camera Preset, or by holding a frame in full-screen Camera.
  While the camera is live, `ShowProgram.itemId` carries the selected frame id so the matching preset (not the plain
  Camera tile) gets the live stroke; the plain Camera tile drops a preset's frame when tapped. Deleting a frame removes its
  presets. Tiles show a still (last camera picture + frame): the one live preview layer belongs to the Camera tile.
