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
- **Blackout White + Freeze** (2026-11-25, match the Mac): long-press the moon picks Black / White
  (`OutputBlankKind`, remembered). White reaches the TV as `set_idle_mode` `"black"` + `color: "white"`,
  so older TV builds still go black; AirPlay gets a white cover over the `.black` source
  (`ExternalDisplayManager+Covers`). Freeze (snowflake) brings Lock's hold, pauses video (TV via the
  plain pause command, AirPlay player) or lays a still over AirPlay; Lock while frozen = moving Lock,
  Blackout ends Freeze. Show Live carries `isFrozen` / `blankKind` (optional, legacy-safe).
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
- Odd-shaped external screens (2026-11-22, `ExternalScreenSignal`, `ExternalDisplayManager+ScreenSignal`): for an LED wall
  behind an EDID box that reports its own size (e.g. 2048×768). On attach the manager reads the screen's signal into
  `ExternalOutputSettings.connectedScreenSignal`. When that size is not 16:9 (1% tolerance) and no custom size is chosen,
  `outputAspectRatio` is the screen's own shape in Landscape (so Full Screen fills the wall), and
  `overscanCompensation` is set to `.none` so nothing is shrunk. If a chosen custom size is not 16:9 and the screen offers
  exactly that pixel size, the screen is switched to it. 16:9 screens are never touched. `updateConnectedScreenSignal`
  does not post `didChangeNotification`; the manager posts it on the next main-queue turn and only when the shape
  changed, because it runs inside `attach` and that notification's observers call back into the manager. Settings →
  Display Mode → Connected Screen shows the signal being sent and the other sizes offered. Tests use the pure rules only
  and never set the global signal. Proven on real hardware 2026-11-25 (iPhone 17 Pro → J-Tech EDID box): iOS lists
  every size the box offers and sends the one the app sets, but by itself it starts on the LARGEST offered size, not the
  box's preferred one. So the odd-shaped offered sizes are one-tap "Use W×H" rows (`selectableOffered`; tapping saves or
  reuses a custom size via `useCustomSize`), and saving a size in the editor also calls `refreshScreenSignal()`.
- Show page preview follows the output's shape (2026-11-25): the live hero box and the small "live in another Show" preview
  use `LibraryGridViewController.heroAspect` (= `outputAspectRatio`), not a fixed 16:9 / 9:16. Stacked layout is one rule,
  `StackedHeroMetrics.stackedSize`: full width when no taller than the cap, else capped and centred (so a wide wall is a
  short banner and a tall one looks like Vertical). Everything drawn in the hero fills its box, so the box's shape is what
  makes photos, video, camera, websites and the countdown match the screen. Grid tiles, website tile art and the import
  confirm screens stay library-shaped on purpose.
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
  Any test that writes an `ExternalOutputSettings` value must be `@MainActor` (2026-11-14): the setters post
  `didChangeNotification` on the calling thread, so a nonisolated suite (`AudioAmbientPolicyTests`) ran other suites'
  live view-controller observers off the main thread and segfaulted the parallel CI run. The crash also left a
  custom screen size saved in UserDefaults, which the relaunched test host inherited, so 16:9 suites failed after it.
  `ExternalOutputOrientationFixture` now clears any selected custom size for its body (also covers simulators with a
  size saved by hand). A local test run reading 512×786 / "Lobby wall" comes from that simulator's own saved settings.
- Crash reports: `CrashReporting.swift` in each app sends crashes and freezes to Sentry projects `eclipse-iphone` and `eclipse-appletv` (Release builds only; `scrub` keeps crash type, code location and device model, and drops all free text and activity trails; the `0.0.0.0` user address is what stops Sentry reading a city from the connection, since neither its IP setting nor `infer_ip` did). Upload symbols after each archive so reports are readable. App Privacy answers must list Crash Data and Other Diagnostic Data, not linked to the user, no tracking.
- Music Up Next (iPhone, 2026-11-23, `MusicUpNext`, `AudioQueueActions`): Play Next / Add to Queue on song rows
  (menu + leading swipe), same rules as the Mac's `MusicQueue` (a song at most once; Play Next puts it first, Add to
  Queue last). Offered only while music is loaded (`AudioPlayerController.canQueue`). A queued song playing sets
  `queuedTrackId` and leaves `currentIndex` on the interrupted playlist song, so the playlist resumes at index+1.
  Queued songs play even with Autoplay Next off. Up Next is session-only (cleared by `stop()`), reorderable by drag in
  Now Playing (VoiceOver: Move Up / Move Down). Now Playing reloads its list only when `queueState` changes, since the
  player posts its change notice twice a second while playing (a reload every tick cancelled swipes and drags).
- TV-run slideshows + idle screen (2026-11-25, branch claude/p5-tv-slides-idle): the TV lists `capabilities: ["slideshow"]`
  in its library manifest; only then does the phone send `play_slideshow` (slides + seconds/Loop/Crossfade/per-slide
  Fit/Fill) and `slideshow_control` (goto id / stop), else it sends one `playRequest` per slide as before
  (`SlideshowTVHandoff`, `AppleTVCapabilities`). Slides that live only on the phone (captures) always go photo by photo.
  On the TV, `TVSlideshowPlayer` keeps time; a play request, park, display-mode switch or the remote's left/right/Menu
  stops it. New shared file `EclipseShareProtocol+Slideshow.swift` is checked by `verify_shared_sources.sh` and must be
  listed in both build phases' input files (script sandboxing). Idle screen (`IdleScreenRules`, `IdleScreenView`): the
  bundled Eclipse loop over the grid once a phone has paired, at launch / after disconnect; Select opens the grid, Menu
  there returns to idle, hold Select opens Options. To see it on a fresh simulator, seed a paired phone:
  `defaults write <container>/Library/Preferences/com.mobleypro.eclipse.EclipseTV EclipseTV.pairing.pairedDevices -data <hex of {"x":"iPhone"}>`.

## TestFlight builds

- The iPhone project reads LivePollKit / EclipsePhoneCameraClient from `../../eclipsepro/Packages` (and CamTailKit from `../../CamTail`), i.e. whatever branch `~/apps/eclipsepro` has checked out. To archive against eclipsepro `main` without touching that checkout, lay out worktrees side by side in a scratch dir (`<dir>/EclipseTV`, `<dir>/eclipsepro`, `<dir>/CamTail` symlink) and archive from there.
- Build numbers: current scheme is `YYYYMMDDNN`; pass it explicitly (`Scripts/set_build_number.sh 2026101801`) since the script's default `YYYYMMDD.minute` sorts below it.
- Upload from the CLI (2026-11-14): `xcodebuild archive … -allowProvisioningUpdates`, then
  `Scripts/upload_testflight.sh <archive>` (`--validate-only` for a dry run). It signs with this Mac's own
  Apple Distribution certificate (cert 9W52VA48F9, login keychain, expires 2027-11-14) and the App Store
  profile "Eclipse iPhone App Store (Mac CLI)", then uploads with the vault's `Moxie Builder` key, so
  Xcode's Apple sign-in is no longer needed (it lapsed every few hours: "Failed to Use Accounts").
  Cert + key backup: vault Moxie `APPLE_DISTRIBUTION_2YBTPD32DW_P12_B64` / `_P12_PASSWORD`; that key can
  also create certificates and profiles through the App Store Connect API. Works for both apps: the script
  reads the bundle ID from the archive and picks the iPhone profile or "Eclipse Apple TV App Store (Mac CLI)"
  (archive the Apple TV with `-scheme EclipseAppleTV -destination 'generic/platform=tvOS'`). Upload crash
  symbols with `sentry-cli` (projects `eclipse-iphone` / `eclipse-appletv`).
- Website fullscreen on iPhone/iPad (`WebRemoteViewController`, 2026-11-04): every website card of the
  open Show is a tab (`BrowserTabList`, strip above the card, shown with 2+ tabs); the TV follows the
  active tab. Windows a site opens (`window.open`, sign-in) are phone-only tabs until "Send to TV".
  Landscape buttons (Close · history · Refresh, then ⊕ only with a single tab, Send to TV / Back only
  when they apply) sit in a column beside the card on a phone; with 2+ tabs ⊕ ends the tab chips
  instead (`BrowserTabStripView.newTabButton`). The clock button opens Websites (named History until 2026-11-23; the owner found
  "History" + "Saved" confusing): on iPhone a drawer (`WebHistoryDrawerView`, from the right in Landscape, from the
  bottom in Vertical) with My Websites (the library's website cards) and Recently Visited; on iPad a pop-up menu with the same two sections. The Mac uses the same words (eclipsepro, 2026-11-23): browser-window list My Websites / Recently
  Visited, main-window list My Websites / Recently Live (it also holds photos and videos that went live); same clock icon on both apps. Recent is the last 30 pages
  the phone finished loading in a tab (`WebHistoryStore`, UserDefaults `EclipseTV.web.recentPages`, phone only), and
  picking one loads it in the active tab. The overlay buttons are re-raised on every layout, so the drawer is re-raised after them.
  Website Auto Scroll was removed (2026-11-13); `ScrollSpeedSlider` now serves only the Prompter. iPad gets a browser-style top bar (chips left, buttons top right)
  in both orientations, since iPadOS ignores the orientation lock while the app supports Split View.
  The website card matches the hero preview: 16pt corners and a 1pt `separator` hairline (2026-11-13).
  Zoom mirrors to the TV (2026-11-23, `WebViewportMirror`): pinch zoom plus position across and down, sent as zoom +
  0…1 fractions (not points) on every scroll/zoom. A pinch can't shrink the page below fit (`fitScale`: 1, or a wide
  page's own width), so no empty background ever shows on either screen. Not yet tried on a real TV.
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
- Screensaver fallback tile (2026-11-26): with nothing picked, the TV / Practice shows the Screensaver and the hero
  mirrors it, so the Screensaver tile gets the blue live outline too (`isScreensaverFallbackOnProgram`, used only by
  `isShowGridItemLive`; the program resolver and operator snapshots are unchanged).
- Hero labels with nothing connected (2026-11-26): the plain LIVE badge hides when no TV is connected (Practice Mode),
  but BLACK / WHITE SCREEN, FREEZE FRAME and LOCKED SCREEN always show (`LiveHeaderView.applyHoldBadgeVisibility`,
  re-applied after every hero refresh and on each Freeze / Lock toggle).
- Blackout hold (iPhone, 2026-11-13, `LibraryGridViewController+BlackoutHold.swift`): while Blackout is on the TV stays
  black and the phone stays usable. Tile taps open a private Preview in the hero (`prefersPhonePreviewOnTap(isBlackoutHolding:)`, see Hero phone preview),
  the held video scrubs muted in the hero, and ⋯ › Show After Blackout cues what follows (`blackoutCue`, "UP NEXT" pill).
  Ending Blackout puts the cue live (videos paused), else restores what was live (video paused at the scrub, slideshow
  on its slide). Operators are never held. Tools with no private Preview (camera, poll, countdown, prompter, slideshows)
  show a toast instead. Apple TV gets paused video via the optional `startsPaused` field on `play_request`; older TV
  builds ignore it and just play, so ship iPhone and Apple TV together.
- Hero phone preview (iPhone, 2026-11-22, `HeroPhonePreview` + `LibraryGridViewController+HeroPhonePreview`): while
  Live Lock or Blackout holds the TV, tapping a photo, video, website, PDF, Background or Screensaver tile shows it in the
  hero on the phone only (grey PREVIEW badge, "Back to Live" / "Back to Blackout"), instead of opening fullscreen.
  Tapping the previewed tile again, or the hero's expand control, opens it fullscreen; tapping the live (or held) tile,
  the return button, toggling Lock or starting Blackout drops the preview. Nothing connected / operators keep the old
  fullscreen Preview. While previewing, hero transport only drives the hero's own muted player, and Screen Fit, hero
  swipe, slideshow and camera-capture buttons are hidden (they act on program). A held Blackout video's scrub is kept in
  `blackoutHeldScrubPosition` while a preview borrows the hero player. Any new hero chrome that acts on program must
  check `heroPhonePreview == nil`.
- Several Prompters per Show (2026-11-13): the first keeps token `__eclipse.tool.prompter` and the
  Show-id script (`prompter-<showId>`, which the Mac reads too); extras are
  `__eclipse.tool.prompter.<nonce>` whose script id is `ShowToolToken.extraPrompterScriptId(nonce:showId:)`
  (SHA-256 of Show id + nonce, shaped as a version-8 UUID). So a token only ever reaches its own
  Show's scripts, wherever it is planted, and never a Show's own (version-4) id. Records reuse the
  `Prompter` type, so no iCloud schema or Mac change. `PrompterScript.showId` is really the script
  key. Copy to Show makes a new Prompter with a copy of the text. There is one `PrompterController`,
  so the TV shows whatever script is bound; opening a different Prompter while one is live asks first.
- Prompter shape (2026-11-23): the Prompter always takes the display's shape (`ExternalOutputSettings.outputAspectRatio`,
  Vertical only when Display Mode is Vertical). The owner removed the Prompter's own Landscape / Vertical menu
  ("it should just match the Show's screen"). The phone turns freely on the Prompter screen (`.allButUpsideDown`, no
  forced rotation): on its side the card is large with one control row, upright it is smaller with the controls
  stacked. Use `PrompterController.isVertical` / `canvasAspectRatio` for prompter layout.
  The blue reading-guide lines were removed (2026-11-13, owner found them confusing); the line read sits mid-stage.
- Camera Presets (2026-11-13): a Show tile = phone camera + one saved frame. Stored only as the surface token
  `__eclipse.tool.cameraPreset.<frameUUID>` (`ShowCameraPresetToken`, counts as a tool), so it syncs with the Show and
  older builds keep it. Saved from the Camera tile ⋯ → Save as Camera Preset, or by holding a frame in full-screen Camera.
  While the camera is live, `ShowProgram.itemId` carries the selected frame id so the matching preset (not the plain
  Camera tile) gets the live stroke; the plain Camera tile drops a preset's frame when tapped. Deleting a frame removes its
  presets. Tiles show a still (last camera picture + frame): the one live preview layer belongs to the Camera tile.
- Frame names (2026-11-14): `CameraFrame.name` (optional, ≤40 chars); `CameraFrameStore.displayName(for:)` falls back to
  "Frame N" by creation order. Renamed from a preset tile's ⋯ → Rename Frame or by holding a frame in full-screen Camera.
  Preset tiles show the name (or "Camera Preset"). Syncs as CloudKit field `CameraFrame.name`, written only when a frame
  has a name: **the field must be deployed Development → Production in the CloudKit Console** before names sync in
  TestFlight/App Store builds (until then a renamed frame's save is refused there; unnamed frames are unaffected).
- Other apps' music (2026-11-14, `AppAudioSession.swift`): Eclipse must never stop Spotify etc. just by being open.
  Launch sets `.ambient`; audible video uses `.playback` + `.mixWithOthers` (non-mixing only when Pause Music for
  Video is on); the camera has `automaticallyConfiguresApplicationAudioSession = false`, records with
  `.playAndRecord` + `.mixWithOthers`. The mic is attached when the full-screen camera opens and removed when it
  closes (`armRecordingAudio` / `disarmRecordingAudio`), never at record start/stop: turning the mic on or off
  re-routes audio and cuts other apps' music for a moment (2026-11-15). Eclipse's own Background
  Music still takes over audio when the user presses play (normal for a music player).
- Camera tile colors (2026-11-23): blue (`liveStroke`) means "on the TV" and nothing else. A frame switched on over the
  camera gets the "✓ ON" badge (`CameraFrameOnBadge`, check only on small ribbon thumbs), never the blue outline, in the
  full-screen camera, the Pictures sheet and the Show camera ribbon. Background / Quick Change tiles are blue while parked on
  program, and the camera can always go live, TV or not (`canGoLiveFromCamera` is always true since 2026-11-26: opened from the
  round Camera button on any tab it used to say "Preview only · No TV connected" and refuse, which the owner rejected). The centered hint says what the TV shows ("TV shows Quick Change · Tap for camera", "Preview only · No TV
  connected", else "Tap screen to go LIVE").
- Camera's first card (2026-11-26, `CameraLiveViewController+LiveOutput`): whatever was live in the Show as the camera
  opened (`entryLiveSource`, also with no TV). Before the camera goes live it is a blue LIVE card and a tap does nothing;
  while the camera (or a parked still) holds the TV it shows that item without blue, and a tap puts it back
  (`returnToEntryLive`: websites / PDFs as the same card via `entryLiveOwnerId`) and the camera screen closes on the
  camera's end notice. "Tap screen to go LIVE" and its other wordings sit in the camera header between Back and the gear.
- Camera frames order (2026-11-15): `CameraFrameStore.frames` is newest-first by `createdAt` and never reorders on a tap
  (sorting by `lastUsedAt` made a tapped frame jump in the camera ribbon). The camera header shows only the LIVE pill;
  the PRACTICE pill was removed at the owner's request. Buttons placed inside a `UIImageView` need
  `isUserInteractionEnabled = true` on the image view, or they never get taps (Camera Frames ⋯).
- Camera tile ⋯ and Save Preset (2026-11-15): Show-sized camera grid tiles have a ⋯ (`CameraTileMoreButton`): frames get
  Rename / Save as Preset…, quick-change stills Replace… / Delete (small in-panel ribbon thumbs keep press-and-hold only).
  A bookmark left of the gear (`savePresetButton`) shows only while a frame is on the camera and Camera came from a Show;
  it asks "Save as preset?" / "Adds camera and frame as preset to your show." (all save paths use that prompt) and turns
  filled once saved.
- Live camera on the Show screen (2026-11-15): while the phone camera owns the hero, the docked ribbon under it shows
  the camera's frames, Background and quick-change stills (`LibraryGridViewController+CameraRibbon`, hooked into the
  slideshow/Live Poll ribbon like Live Poll), and the hero has Take Photo / Record bottom-left
  (`LiveHeaderView+CameraCapture`). Captures file through `CameraCaptureFiling` (shared with fullscreen). The mic is
  armed per owner (`armRecordingAudio(owner:)`: "fullscreen", "showHero"), so it stays on while the camera hero is up.
  Hero expand control is a 36pt circle. `CameraMirrorView` flushes its renderer when it re-enters a window or reports
  it needs a flush: a fullscreen presentation stalled it and left the hero black after closing the camera.
- Interactive PDF in the hero (iPhone/iPad, 2026-11-26, `LiveHeaderView+PDFPreview`, `PDFReaderDriver`): a Show PDF card
  tap puts the PDF live in the hero as a real `PDFView` (sharp, scrolls and pinches in place); only the hero's expand
  control (or ⋯ Preview) opens the full-screen reader. Both views share one `PDFReaderDriver` design and show the same
  icon row top right (`PDFViewOptionsBar`: Fit · Fill · 2 Pages, then Page by Page; same words, defaults and Page by
  Page icon `book.pages` as the Mac's presets. Fit / Fill icons differ on purpose (owner's call, 2026-11-26): iPhone uses
  `rectangle.arrowtriangle.2.inward` / `.outward` because the Mac's shrink/expand arrows match the hero's expand control;
  the Mac keeps the arrows because the triangle pair looked alike at its 12 pt size). Only one driver moves the TV at a
  time (`PDFReaderDriver.active`): the reader takes over while open and hands back on close (`didResignNotification`).
  The shared view (`PDFLiveViewState`: page, 0…1 scroll fractions, zoom relative to fit, two-up, preset, snapping) lives on
  `ExternalDisplayManager.pdfViewState` and the TV applies it whole (`applyPDFViewState`). A reader on a PDF that is not
  live never moves the TV. Page by Page: on finger lift a pan target picks the next row stop (`PDFViewMath.snapOffset`);
  a row taller than the screen (zoomed in) scrolls freely and stops at its edge. A pinch clears the lit preset.
  Default is Fit with natural scrolling. PDF tile pictures are 720×960 (`<id>-v2.jpg`); old 360×480 ones stay unused in Caches.
  A hero refresh can un-hide the still picture (e.g. `clearWebPreview`), so `showPDFPreview` re-hides it every time.
- Interactive website in the hero (iPhone/iPad, 2026-11-26, `HeroWebViewportSync`, `LibraryGridViewController+HeroWebInteraction`):
  the live website scrolls and pinches in place in the hero and the TV follows (same `WebViewportMirror` as the full browser,
  sent only for the operator's own drags/pinches, never below fit). Links and buttons don't work there
  (`WarmWebSession.setPreviewInteraction` turns off touches on the page's content view, keeping the scroll view's pan
  and pinch), so the hero can never show a different page from the TV; a tap opens the full browser. Same off-rules as
  DirectAdjust (Live Lock, Blackout hold, phone Preview, another Show live, remote operator, tucked hero). The browser
  is presented inside a nav controller, so its `viewWillDisappear` must also check `navigationController?.isBeingDismissed`:
  without that it never handed the warm page back and the hero showed a still after Close.
- PDF reader zoom snap (2026-11-14): pinching in `PDFRemoteViewController` catches where the current page exactly fills
  the audience frame's width and where it fills its height (`PDFZoomSnap`, ±4% hold band, light haptic on entry). It
  rides the scroll view's own pinch recognizer (added target, never the delegate). Holding sets the zoom, and the scroll
  view then pinches on *from the held zoom*, so a slow pinch stayed caught for good (found 2026-11-19). Once a pinch has
  held, the reader drives the zoom from finger spread (`PDFZoomSnap.fingerScale`). Only snap sizes inside the reader's
  zoom range count: a portrait page in a 16:9 frame only gets the fill-width catch.
- Practice Mode is always on (2026-11-25, owner's call: "the Mac app has no such setting"). Inside any open Show,
  nothing connected behaves like a TV is connected: taps put cards in the hero, Lock / Blackout show, Prompter /
  Countdown / QuestPoll / websites can go live (`prefersDisconnectedLivePreview == isShowMode`). Home is unchanged.
  The per-Show switch is gone from Settings; the old `previewsWhenDisconnected` key is still written as `true`
  (JSON and CloudKit) because older builds read it as their switch.
- Hero video controls fade like a video player (2026-11-25, `LiveHeaderView+TransportAutoHide`): only when the hero plays
  the video itself (nothing connected / Practice Mode, or a phone Preview). They fade 3s into playback; a tap on the
  picture shows them, a tap while they show hides them (it no longer toggles play/pause; the button does). They stay up
  while paused, while scrubbing and with VoiceOver on. A TV-driven hero (AirPlay / Eclipse TV) is a remote and never hides.
- Live overlays move on the hero (2026-11-26, `LiveHeaderView+OverlayAdjust`, `OverlayAdjustSession`): one-finger drag
  moves a live template card or photo/video overlay, pinch resizes it (cards 0.25–3×, media 10–100% width, the Mac's
  ranges), snapping to the centerlines with a tick. The TV follows through `LiveOverlayController.setAdjusting` (no
  `didChangeNotification` per frame); lift saves: a card's `placement` via `TemplateCardStore.update` (syncs to the Mac,
  editor Position then reads Custom), media via `MediaOverlayStore.update` (phone only). Hit-testing uses frames each
  overlay reports into `LiveOverlayHostView.frames`. Off when locked, Blackout, phone Preview, other Show, remote operator.
- Live preview (hero) takes pinch and drag directly (2026-11-04, `LiveHeaderView+DirectAdjust`):
  countdown pinch resizes / drag on the clock moves it (live through `CountdownClockLayoutPreview`,
  saved on lift); stills pinch-zoom into a crop (`StillFramingGesture`, saved via `applyFraming`
  when fingers lift, snapping to Fill/Fit within 3%). Like Photos: at plain Fit/Fill a swipe browses,
  once cropped a one-finger drag pans. The Fit/Fill corner button turns into ↺ (reset) while adjusted.
  Browse swipes and the home pager `require(toFail:)` the adjust pan, which fails at once when
  there's nothing to drag. Off for video, overlays, locked output, remote operators.
- iPad (2026-11-19, audit `docs/audit-2026-11-19-ipad-and-mac.md`): every alert with a text field calls
  `alert.preferConfirmAction()` before it is presented; without a preferred action UIKit sends a keyboard's
  Return to Cancel. The camera and QR scanner sessions set `isMultitaskingCameraAccessEnabled` so the camera
  keeps running in Split View / resized windows (unconfirmed on a real iPad).
- Polls naming (2026-11-23): the owner dropped the QuestPoll brand. On screen, the thing on stage is a "Poll", and the
  web account/service is "Eclipse Polls" at polls.eclipseapp.com (Q&A audience link ask.eclipseapp.com/CODE).
  questpoll.com / quest.eclipseapp.com still answer the API and forward pages. Code names (QuestPoll*, LivePoll*) stay.
- Polls are made and edited in the app (iPhone/iPad, 2026-11-22): `QuestPollEditorViewController` (name, Poll / Quiz,
  time per question, question list) → `QuestPollQuestionEditorViewController` (text, 2–5 answers, right answer in a quiz).
  Reached from the poll list's + and pencil (`QuestPollPickerViewController`, also Settings → QuestPoll → My Polls in
  `.manage` mode) and a card's ⋯ → Edit Poll…. `QuestPollDraft` holds the unsaved poll and its limits (mirrors
  `quest-relay/src/limits.ts`); saving and deleting go through LivePollKit's `saveDeck` / `deleteDeck` (`POST` / `PUT` / `DELETE /api/polls`, the same calls
  the website editor and the Mac use). A new poll made while
  choosing one for a Show is picked automatically. A running room keeps its own copy, so edits show on the next start.
  questpoll.com has no test copy: never save/delete polls against it to try things out. Check the screens with a stub
  `URLProtocol` client instead (see `QuestPollEditorTests`).
- Home screen pages and text tabs (iPhone / narrow iPad windows, 2026-11-25, `HomeTabStrip.swift`, `HomeTabPages.swift`,
  `iPhoneMainViewController+HomePaging.swift`): the pager has four pages, Home · Library · Show · Music (`HomeTab`), named by
  text tabs under the header row (inside the row in phone landscape) with a line under the current one. Home and Show are still
  one screen in two modes (`LibraryGridViewController`), so the grid *moves* between the Home slot and the Show slot; Library
  sits between them, so the two slots are never on screen together and the grid changes mode as soon as a finger swipe brings
  the other slot into view (`moveGrid(into:)`: Home closes the Show, Show reopens `lastOpenShowId` or the most recent Show of
  the current Display Mode, else the "No Show open" page). Only a finger swipe does that: tab slides and layout passes never
  change the grid's mode (a layout pass that snapped the offset mid-slide once closed the Show). `HomePagerScrollView` ignores
  `scrollRectToVisible`, or focusing a text field nudges the pager sideways. The header (`HomeHeaderBar`) stays on every page
  and swaps its right-hand buttons by page (`setTabPage`): Library gets "+" (Photos & Videos / PDF into the Library only,
  never the open Show: `makeLibraryAddMenu`, `pendingPDFLibraryOnly`, 2026-11-26), Music gets "+", and Library and Music hide their
  own navigation bar at the root (`HomeTabPageNavigationController`; it returns for a playlist or reordering).
  The dropdown says "Eclipse" on Home (no "Home": that is a tab) and has no Library / Music entries or back chevron there.
  Search is the first item on the tab row, left of Home (owner's call 2026-11-26); Settings has no icon on the paging home screen and
  is in the dropdown instead, with or without a Show open (owner's calls, 2026-11-26). Camera is a round button in the
  bottom-leading corner (`HomeCameraButton`, owner's call 2026-11-26, after a word on the tab row): it mirrors the Music
  circle (same size and insets), is dark grey (blue means "on the TV"; a blue ring shows while the phone camera is live),
  and is on iPhone and iPad alike. It fades out while the music card would cover it (an upright phone; a wider screen keeps
  it), while tiles are arranged or selected, and while a search field is up (`HomeCameraButton.shouldHide`,
  `refreshHomeCameraButton`). The Show's bottom banners (iCloud, swipe hint) keep clear of it
  (`bottomChromeCameraClearance`). A floating bottom bar and an iOS-style glass footer were both tried and rejected: do not
  bring a footer back. Camera opens the full-screen camera (`presentCameraLive`). Search works on
  Library, Music's list and an open Show (elsewhere, and while arranging, the icon stays put, dimmed and inactive, so the
  tabs never shift). Its field replaces the tab row until Cancel (`beginPageSearch` / `endPageSearch`; the header keeps
  its height) and
  filters the page in front by name: Show cards (`ShowGridItem.searchTitle`, `showSearchQuery`), tracks and playlists,
  Library titles. The filter ends when the page or the Show changes, and arranging ends it first, because arrange
  positions are positions in the whole Show (a filtered grid would save the wrong order). The pushed Library page keeps
  its own search field. The music player (blue circle + card) is untouched and must stay as it is: a replacement strip
  was tried and the owner wanted the old player back. A tab's slide always ends on the tapped tab
  (`scrollViewDidEndScrollingAnimation` never reads the offset).
  The Library *tab* only browses and previews; adding to a Show is still the pushed Library page from the Show's "+".
  Regular width (full iPad, big phones in landscape) is unchanged: `HomeHeaderNavTabs`, Music drawer, pushed Library.
- Content icons match the Mac app (2026-11-22): `ThumbnailTypeIcon.systemName` is the one place a content kind's SF Symbol is named
  (Website `globe`, PDF `doc.text`, Prompter `text.viewfinder`, Slideshow `photo.on.rectangle.angled`, same as the Mac's
  `AddMediaList` / `MediaTypeVisual`). Every screen reads it; never write those symbol names inline. `safari` stays only on
  "Open questpoll.com" (it opens Safari) and `rectangle.stack` / `.fill` means a Show, not a slideshow. Tiles no longer draw
  the top-left type disc (`ThumbnailTypeIconView.showsOnTiles = false`, owner's call: the Mac has none); VoiceOver still speaks the kind.
  Review and before/after pictures: `docs/reviews/2026-11-22-polish/`.
- iPad Library tab (2026-11-22): on a full iPad canvas the Media Library page shows its own copy of the Home / Show / Library
  tabs (Library lit) in place of Back and the centred title (`MediaLibraryPickerViewController.refreshLeadingBarItem`,
  `HomeHeaderNavSelection.isLibrary`). Home or Show closes the page first, then acts. iPhone and narrow iPad windows keep Back.
  The page still covers the Music button.
- Titles over pictures (2026-11-22): white titles on Home Recent tiles, the Continue card and Library/Show tile captions sit on
  `GradientView.titleScrimColors` (three stops, about 62% black where the words start). A plain clear-to-dark ramp was half
  strength at the title and unreadable on a white website thumbnail; keep the three-stop shade for any new title over art.
- Shows list (2026-11-22): presented as a form sheet (compact centred sheet on iPad, like Settings); its filter says
  "Landscape", the same word as Display Mode, never "Horizontal".
- Card pictures for websites, video links and PDFs (audit 2026-11-26): website cards are captured from the warm web view
  0.5s after load and again 2.5s later (`WarmWebSession.scheduleThumbnailCapture`; sites that fade in, like github.com, were
  blank white at 0.5s). Video-link posters (`WebVideoPosterFetcher`) crop from the middle (`saveSnapshot(_:for:centered:)`;
  YouTube's 4:3 `hqdefault` fallback has bars), ask Vimeo oEmbed for `width=1280` (default is 295×166), and direct
  `.mp4`/`.mov` links get a still from `VideoPosterFrame` (HLS `.m3u8` can't be sampled and keeps the icon). Posters saved
  before these rules are fetched once more (`EclipseTV.webVideoPoster.v2Ids`). PDF pictures render into 960×960
  (`PDFThumbnailStore.renderSize`, files `<id>-v2.jpg`, NSCache-bounded); older 360 px files are rebuilt on first read.
- Background colors (2026-11-22, `BackgroundColorPreset`): the Background tile's ⋯ menu has a "Color" row with the Mac's
  eight presets (same names, order, stops and `eclipse://builtin/gradient/<name>` URL as eclipsepro's
  `BackgroundGradientPreset`; keep them in step). Picking one draws a 1920×1080 picture and stores it as the Background
  still (`LogoStore.apply(_:)`), so tile, hero, AirPlay/HDMI and iCloud use the existing picture path; it replaces a
  custom picture, like the Mac. Which preset is chosen is remembered on this device only (UserDefaults
  `EclipseTV.background.colorPreset`): other iPhones receive the picture without the name, since the iCloud Background
  record has no field for it. The Mac does not sync its Background (it is per presentation there).
- Music sync (2026-11-23, with the Mac): songs are `AudioTrack` records `audio-<UUID>`, playlists `AudioPlaylist`
  records `playlist-<UUID>`, never parented, last writer wins on `modifiedAt` (tie → remote). Protected items
  (Background Music + Chill Low Fi) never sync; `caf` and files over 200 MB stay on the phone. Clocks and
  acknowledgements live in `MusicSyncLedger`, not in the saved track/playlist format. Playlists keep song ids the
  phone has no file for yet (`MusicSyncPolicy.mergeOrder` on reorder). **Both record types must be deployed
  Development → Production in the CloudKit Console** before music syncs in TestFlight/App Store builds.
- Mac remote on iPhone/iPad is the Mac's own page (2026-11-25, `MacRemote/`): Settings → Connect to Mac (or an
  `eclipse://mac-remote` QR / link) finds the Mac, then `MacRemoteWebViewController` shows the remote page that Eclipse
  on the Mac serves (eclipsepro `EclipsePro/RemoteControl/WebRemote`). There is no second, hand-built remote screen any
  more (owner's call: browser and app must look and behave the same), so **new remote controls are built once, in the
  Mac's page**, never in this app. The app only adds a Back arrow to the page's header (`MacRemotePage.backArrowScript`;
  its own Back button stands in while the page loads, while the page's PIN card covers the header, or if the header is
  ever missing), keeps the page on the Mac it opened (`allowsNavigation`), and keeps the remote's sign-in in its own
  cookie store, apart from the website browser. Sign-in (link secret or PIN) is the page's job. To look at it without a
  Mac, serve the three `WebRemote` files from a small local stand-in and open
  `eclipse://mac-remote?h=127.0.0.1&p=<port>#t=x` in the simulator.
- Music bar on iPhone (2026-11-25, `AudioMiniPlayerView`): two rows. Song name (one line, chevron hints the tap opens Now
  Playing) over four round buttons in the owner's order: mic duck, Pause / Play, Stop, Next. The Music circle sits in the
  card's bottom trailing corner, level with the buttons (`controlRowHeight` = `AudioMiniPlayerBubbleView.side`; the card
  is `preferredHeight` = button row + title row). Next dims when there is nowhere to go (`AudioPlayerController.hasNextSong`:
  one song, nothing in Up Next). A very narrow window shrinks the four buttons evenly instead of clipping one.
- Second-phone remote ("Show Live", `ShowLive*`, 2026-11-25): a second iPhone on the same iCloud account with the same Show
  open becomes a remote of the phone that owns the TV, only while `ShowLiveRouting.directorAppliesSelects` is true. That flag
  was false from 2026-09-07 to 2026-11-25, so in every build of that period the remote never engaged and all
  `isRemoteOperator` paths were dead code; check the flag before describing how the remote behaves. Never run on two real
  phones since it was turned back on. The remote reads the live slideshow through `liveSlideshowView` (own player, or the
  director's snapshot), never `SlideshowPlaybackController` directly, and the hero Fit / Fill rule is `liveScreenFitChrome()`
  for both the button and the snapshot. New snapshot fields must be optional and new commands new verbs: an older build
  ignores unknown fields but drops a whole message whose verb or item kind it cannot decode (which is why PTZ Camera and
  Prompter are still sent as "nothing live"). Not done on the remote: turning PDF pages, scrolling a website, Prompter and
  PTZ go-live, the live camera's frames and capture, pinch-to-crop.
