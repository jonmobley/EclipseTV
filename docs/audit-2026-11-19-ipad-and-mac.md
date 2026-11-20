# Eclipse audit: iPad, and iPhone/iPad vs Mac — 2026-11-19

Read-only audit. No code was changed.
Trees: EclipseTV `fix/camera-photo-viewfinder-crop` (2940daa); eclipsepro at main's sync code (8e027574).

## How it was checked
- iPad: read every iPad-specific code path (70 branches in 23 files), built Debug and ran it on an
  iPad simulator (Home, new Show, Show page in both orientations, add menu, Prompter, Settings,
  camera permission flow).
- Mac comparison: full inventory of the Mac app's features and of its iCloud sync code
  (`Packages/EclipseSyncKit`, `EclipsePro/ShowSync`), compared field by field with
  `EclipseiPhone/EclipseSync`.

## Part 1: iPad

### Works
- Home, Show page (stacked upright, side by side when turned), add menu, Prompter, Settings sheet and
  the camera-permission alerts all lay out correctly at full screen.
- All 8 action sheets and both share sheets have an iPad anchor (no "action sheet with nowhere to
  point" crash), with the two exceptions below.

### Findings
1. **High — FIXED 2026-11-19 (verified on simulator). Return on a keyboard cancelled name prompts.** Seen on the simulator: New Show, type a name,
   press Return, the prompt closes and no Show is made. `ShowNamePrompt.swift` and 18 other text
   prompts never set the alert's preferred action (only `SettingsDisplayModeViewController.swift:289`
   does). iPads are often used with a keyboard.
2. **High — FIXED in code 2026-11-19, needs a real iPad to confirm. Camera went dark when Eclipse is not full screen.** Nothing
   turns on the "camera while multitasking" switch (`isMultitaskingCameraAccessEnabled`), so iPadOS
   stops the camera in Split View, Slide Over, or a resized window. `CameraManager+SessionLifecycle`
   treats it like a phone call and shows no explanation.
3. **Medium — a second Eclipse window is allowed and not designed for.** `UIApplicationSupportsMultipleScenes`
   is on. Each new window builds a second main screen on top of single shared players (one TV output,
   one camera, one Prompter), re-runs `ExternalDisplayManager.start()`, and can snap Display Mode back
   to Landscape (`SceneDelegate.swift:19-22`).
4. **Medium — no minimum window size.** With iPadOS 26 windows a pane can be dragged very narrow; the
   side-by-side layout turns on whenever width > height (`LibraryGridViewController+ChromeLayout.swift:50`),
   including small short windows.
5. **Low — two camera sheets can crash if their tile is off screen.** Frame actions and Quick Change
   only anchor when an anchor view exists (`CameraLiveViewController+CameraPreset.swift:69`,
   `+StillRibbon.swift:208`); with none, iPad throws.
6. **Low — little keyboard/trackpad support.** Shortcuts exist only in the note and script editors;
   pointer hover only on note cards; no drag-in of files from other apps; no menu bar commands.
7. **Low — cosmetic.** Home's "Create your first Show" card is a large empty panel on iPad; the Music
   button sits on the window-resize corner.

### Not verified
Camera, AirPlay/HDMI and Stage Manager external display (simulator has none); Split View / narrow
windows; website browser and History pop-up on iPad; iCloud (simulator not signed in).

## Part 2: iPhone/iPad vs Mac

### Sync issues
1. **High (needs a two-device test) — iPhone/iPad does not regularly pull changes.** The Mac asks
   iCloud every 60 s and on activation (`ShowSyncController.swift:59,166-178`). The iPhone app has no
   pull at all for its own library: on foreground it only re-sends (`EclipseSyncController.swift:66-73`,
   `retryPendingWork`), and it has no push entitlement, so iCloud cannot wake it. Mac edits may not
   appear until the iPhone app is relaunched. There is also no "Sync Now" on iPhone (Mac has one).
2. **Medium — shared Shows never reach the Mac.** Sharing (CKShare) exists only on iPhone. The Mac
   reads only the private database, so a Show someone shared with you is missing on your Mac.
3. **Medium — deletes behave differently.** Deleting a Show on the Mac removes only the Show and its
   Prompter record; its photos, PDFs and cards stay in iCloud. When the iPhone deletes an item the Mac
   keeps its copy; when the Mac's delete arrives the iPhone removes its copy.
4. **Medium — edits to one card on both devices: the Mac always wins.** For photos, videos, PDFs,
   websites, slideshows, countdowns and polls the Mac re-sends its own copy on a conflict with no
   date check (`ShowSyncController+Events.swift:290-294`). Shows and Prompter scripts merge properly.
5. **Low — "show title" is Mac-only.** The Mac writes `titleShown` on six record types; the iPhone
   has no such field.
6. **Low — extra Prompters.** The Mac holds one script per Show. A second iPhone Prompter syncs as a
   record the Mac stores but never shows (no harm to the first).

### Things that exist on one side only
| iPhone/iPad only | Mac only |
|---|---|
| Camera Presets, frame names, Quick Change stills | Templates/overlays (26 kinds), PowerPoint, App and screen cards |
| Several Prompters per Show; Vertical Prompter | Timer modes Count Up / To Time; timer styles |
| Blackout hold with "Show After Blackout" | White, Freeze Frame, Test Patterns, Recording |
| Website History drawer, Send to TV | Website zoom, bookmarks, Web Video, widgets |
| Practice Mode; Share a Show with people | Import/Export Show file, Duplicate Show, Stage Monitor |
| Screensaver/Background sync between iPhones | Slideshow videos, pan & zoom, music bed (not synced) |
| Q&A in the add menu (Mac: beta switch) | Virtual camera, EclipseCast, multiple displays |

Custom screen sizes exist on both but do not sync; a Show only carries Landscape or Vertical.
The iPhone remote for the Mac lacks the Mac's music controls (10 `music…` commands and the `music`
state are missing from `MacRemote/Protocol/RemoteMessages.swift`).

### Wording differences
| iPhone/iPad | Mac |
|---|---|
| Display Mode | Show Format |
| Blackout | Black Screen / Black |
| Countdown | Timer |
| Website | Website / Slides |
| Image | Image (same); "Media Library" vs "Add from Library…" |
| Content Transition | Media Transitions |

### Matches (checked, fine)
Container, zone, record names, Show merge rules, delete markers, Landscape/Vertical, Fit/Fill,
countdown end actions and backgrounds, 48-character names, 200,000-character scripts, and unknown
Show tool tiles surviving a round trip through the Mac.
