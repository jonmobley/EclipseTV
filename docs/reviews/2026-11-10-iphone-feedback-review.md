# Eclipse iPhone/iPad feedback review & phased plan

## Context
The owner wants the iPhone/iPad app treated as a **standalone media & show player** (Apple TV/sync secondary) and gave feedback in 7 areas. This document records what the code does today, what was confirmed, what still needs a device repro, and a phased plan. Nothing broad gets built until the open decisions (bottom) are reviewed.

**Repro limitation:** this session is a Linux container — no Xcode, no simulators. Everything below is traced from code (paths relative to `EclipseiPhone/EclipseiPhone/` unless noted). "Confirmed in code" = the mechanism is unambiguous; "needs device repro" = plausible, must be checked on iPhone/iPad before fixing. CamTailKit (PTZ) is not in this checkout, so PTZ findings are host-side only. Live polls render from the questpoll.com web page (`eclipsepro/quest-relay/public/present.js`, `styles.css`) in a WKWebView, not native UIKit.

## Status (2026-11-10, first pass)
Done in this branch (not yet built or run: no Xcode in the session; run the iPhone tests on a Mac):
- Phase 1.1: History opens a site **phone-only** (nothing live changes); Send to TV is an explicit go-live and now takes output even when a still is live. A phone-only browser no longer closes when some other website output ends.
- Phase 1.2: sync keeps this phone's `lastOpenedAt`; captions read "Opened 3hrs ago" / "Created 2 months ago".
- Phase 1.4 (server part): QuestPoll confirm page now uses `referrer-policy: same-origin`, so its form POST carries a real Origin and no longer gets 403 Forbidden (eclipsepro `quest-relay`, needs a deploy).
- Phase 1.6 (search part): the Media Library search field focuses on the first tap.
- Phase 1.7: iPhone no longer asks "Skip ahead?" on a forward poll cue jump; "Reopen question" still asks. The Mac strip (`StageQuestCueStrip.swift`) is unchanged.

Still to do from Phase 1: TV-message split (1.3), in-app poll sign-in follow-ups (1.4), camera resume (1.5), grid scroll anchor and slideshow editor delete (1.6).

---

## 1. Standalone direction & Home

| Item | Today | Finding | Proposed change |
|---|---|---|---|
| Apple TV sync/resend messaging | "Re-send from Photos" / "file is no longer on the Apple TV" / "Remove from Apple TV" gate only on `item.isAvailable == false` (`LibraryGridViewController+ItemOptions.swift:19-27`, `+HomeGrid.swift:779-797`, `MediaLibraryPickerViewController+Menus.swift:32-71`) | **Bug, confirmed in code.** `isAvailable` is false for (a) items in a *cached* TV manifest persisted per TV in UserDefaults (`TVLibraryStore.swift:106-110, 840-849`) — a TV paired once long ago — and (b) **iCloud items not yet downloaded** (`EclipseSync/ImportedMediaRecord.swift:59-67`, `CaptureRecord.swift:72`). (b) explains seeing TV messaging without ever connecting a TV. Settings' Apple TVs list also checkmarks `activeTVName` while disconnected (`SettingsEclipseTVViewController.swift:198-218`). | Split "unavailable" into `.downloadingFromICloud` vs `.missingOnTV`. iCloud items show "Downloading…" with no TV wording. TV wording only when the item truly came from a TV manifest **and** a TV is connected; otherwise hide. Move all TV status/resend into Settings → Apple TV (and a small connection chip only while connected). Show checkmark as "Last used" when disconnected. |
| Home banner | `HomeHeroCarouselCell` shows 3 hard-coded slides (gradient + SF Symbol, no image, tap does nothing) (`HomeHeroSlide.swift:22-44`, `+HomeGrid.swift:136`) | Static marketing placeholder. | Replace with a **"Continue" card** for the last opened Show (cover, name, "Opened 2h ago", Open button) + "New Show" when none exists. *Open decision D1.* |
| Recents "2 months ago" | Order = array order (moved to front by `touchRecentlyOpened`, `LocalAlbumStore.swift:166-172`). Label = `lastOpenedAt ?? createdAt` (`LocalAlbum.swift:226-227`), unlabeled. | **Bug, confirmed in code.** `lastOpenedAt` is not in the CloudKit record (`EclipseSync/CloudKitRecordMapper.swift:89-109`); when the remote copy wins a merge (`CloudKitConflictResolver.swift:51-54`) it becomes nil and the label falls back to **createdAt** while the Show stays first. Opening a Show also bumps its sync modified time, which makes this likely. | Keep `lastOpenedAt` local-only and preserve it across merges (never overwrite from remote). Recents keeps store order (opening a Show already moves it first). Label with the event: "Opened 2h ago" / "Created Sep 3". Add test in `ShowListSubtitleTests.swift`. |

## 2. Adding content, browsing, preview speed

| Item | Today | Finding | Proposed change |
|---|---|---|---|
| **Add never goes live (requirement)** | Audited every add in `makeAddMenu` (`iPhoneMainViewController+MediaActions.swift:247-390`): media, batch Photos, website, countdown, slideshow, PDF, music, tools, Copy to Show, **Live Poll / Q&A** (`+LivePoll.swift:47-55` → `LivePollStore.create` + reveal only). | **Live Poll add does not go live — confirmed in code.** Three related paths do touch output: (1) **History row tap on Home calls `ExternalDisplayManager.presentWeb` → replaces live output** (`WebPagesViewController.swift:127-136, 203-204`) — violates the requirement; (2) Prompter opens its operator screen after add (not live until Live is pressed); (3) re-crop/replace of the *currently live* item re-presents it (intended update, not an add). Also: the TV adds media silently (`addMediaSilently`). | Fix (1): History tap opens preview/browser only; going live is an explicit action. Add a unit-test guard: every add path leaves `ExternalDisplayManager` current content unchanged. Needs device repro of the poll case you saw — possibly a tile tap after add (tap = Start). |
| Search one tap | Only in Media Library picker. `searchTapped` installs `navigationItem.searchController` then sets `isActive = true` in the same turn (`MediaLibraryPickerViewController+Search.swift:27-33`); no `becomeFirstResponder`. | Likely bug (needs device repro): activating in the same runloop as install often doesn't focus. | Implement `didPresentSearchController` → `searchBar.becomeFirstResponder()` (and/or defer activation one runloop). |
| Slow thumbnails (5–10 s) | `TVLibraryStore` loads thumbnails on **one serial `.utility` ioQueue** (`TVLibraryStore.swift:45,84,213-295`). Video posters use `VideoPosterFrame.image(at:)` which **blocks a semaphore up to 8 s** (`VideoPosterFrame.swift:39-47`). JPEG persist/prune share the queue. Retries give up after ~1 s (`:546-566`). Batch import: no tile until all picks download, movies one at a time, then main-thread `copyItem` per file (`+BatchImport.swift:61-74`, `+BatchImportPrepare.swift:19,73-141`, `+MediaActions.swift:743`). | **Root cause identified in code** (head-of-line blocking on serial queue + 8 s video poster). Needs Instruments confirmation. | Concurrent decode queue (limit ~4, `.userInitiated`) separate from video poster generation; async `AVAssetImageGenerator` without semaphore; generate thumbnail from the picked file before the copy; per-item tiles during batch import; move `copyItem` off main. |
| Tap → preview delay | Tap → `updateCurrentId` → hero refresh, then **full `reloadLibraryGrid()` of three collection views + `layoutIfNeeded`** (`ExternalDisplay.swift:92-101`); hero waits for 640-px thumb from the same serial queue; crossfade adds 0.08 s hold + 0.35 s dissolve (`LiveHeaderView.swift:690-733`); a second dissolve when the thumb arrives. No double-tap gesture delay. | Not intentional beyond the dissolve. | Reconfigure only the old/new selected cells instead of full reload; synchronous memory-cache hit for hero; drop the 0.08 s hold; skip dissolve for the phone preview (keep it on output). Measure before/after with signposts. |
| Grid jumps on ribbon change | When dock state flips, `applyShowPageLayout()` swaps in a **new layout + `reloadData()`** (`+Pages.swift:112-119`) even though in-grid ribbon is permanently off (`HomeLayout.swift:44-51`); then `contentInset.top` changes by ribbon height and the "previous offset" is sampled *after* the reload (`+RibbonTransition.swift:40-90`, `+ScrollAnchor.swift:62-107`). | **Cause confirmed in code.** | Skip the layout rebuild when only dock state changes; capture anchor (first visible item + offset) before any change and restore after inset animation. |

## 3. Cameras & PTZ

| Item | Finding | Proposed change |
|---|---|---|
| Camera resume | Session restarts are gated on `wantsSessionRunning` (`CameraManager+SessionLifecycle.swift`). Paths that never restart (code-confirmed, need device repro): (a) AirPlay camera ends while Settings/Frame sheet is open over Camera Live → `stopSession()` sets wanted=false and `cameraEndedExternally` early-returns (`CameraLiveViewController.swift:499-500`, `ExternalDisplayManager.swift:1167`); page-sheet dismissal fires no `viewWillAppear`. (b) Camera Live torn down by an ancestor dismissal → `didDismissNotification` not posted, `homeCameraWarmPreviewSuspended` stays true (`+CameraTile.swift:42`). (c) 6 failed starts then silent give-up. | Single "camera demand" model: each visible consumer (tile, Camera Live, hero) registers/unregisters; session runs while demand > 0. Restart on sheet dismissal (`presentationControllerDidDismiss`) and foreground; bounded retry with visible "Tap to retry". |
| PTZ disconnected / setup | Host tile/hero/AirPlay embed `CamTailLiveVideoView` with no disconnected branch (`LibraryThumbnailCell+PTZCamera.swift:18-47`); tap goes live even if not connected (`LibraryGridViewController+PTZCamera.swift:21-38`). Setup lives entirely in CamTailKit (not available here). | Expose a connection state from CamTailKit (`.searching/.connected/.notFound/.needsPermission`). Tile shows "Not connected · Set up" ; tapping when disconnected opens setup, never goes live. Setup: local-network permission → auto-discover NDI → manual IP fallback → test view. **Implementation goes in CamTailKit** (per CLAUDE.md), run `build_all.sh`. Needs a walkthrough on a device with CamTailKit. |

## 4. Live polls

| Item | Finding | Proposed change |
|---|---|---|
| `Forbidden` auth bug | App flow: `POST /api/auth/request` → code → `POST /api/auth/verify` → Bearer token in Keychain. Literal `{"error":"Forbidden"}` comes from `handleAuthConfirm` (`eclipsepro/quest-relay/src/index.ts`): rejects when `Origin` ≠ site origin. The confirm page is served with `referrer-policy: no-referrer`, which makes browsers send **`Origin: null`** on the form POST → 403. **Strong code-based hypothesis**; repro with the email link in Safari. Extra login steps: (1) server falls back to link flow (`userCode`) after wrong-code budget; (2) signing in from a poll tile's Start lands on the picker instead of starting (`+LivePollSession.swift:102-116`); (3) "Manage/Edit on QuestPoll" opens `/host` in SFSafariViewController with its own cookie → asks to log in again. Also stale tokens never force re-sign-in (`LivePollAccount.swift:24-26`). | Server: accept `Origin: null` only when token+code validate (or change page to `strict-origin`/`same-origin` referrer policy). App: resume the original Start after sign-in; on `.unauthorized` clear token and show sign-in; hand the web `/host` a one-time login link so no second login. |
| Timer / duration / QR controls | Timer always shown while voting; duration per question from web editor (default 30 s); QR shows in lobby and is unpinned on every transition (`present.js:292-303,332`, `hostCommands.ts`). No app-side settings. | Add deck/session options `showTimer`, `voteSeconds` override, `keepJoinQR` (persistent corner QR, not full-frame) — server command + `present.js` + iPhone controls. Needs both repos to ship together. |
| Timer ring direction | SVG rotated −90°, `dashoffset = C*(1−left/total)`: the arc's free end retreats **counterclockwise** toward 12 (`present.js:434-481`). Confirmed. | Recommend: remaining arc depletes **clockwise** (like a clock hand sweeping away time) — mirror via `scale(-1,1)`. *D7.* |
| Answer gap | `.options { margin-top:auto; padding-top:40px }` in a flex column pushes answers to the bottom (`styles.css:149-158, 289-324`). | Remove `margin-top:auto`, center question+answers as a group, keep 2 columns + centered 5th. |
| Controller drawer | Shows Responses, Joined, countdown, results list, primary button ("Show results" = `reveal` closes voting & shows bars; then "Next question"), Extend +15s, **Skip** (drops current question unrevealed, opens next), Show/Hide QR, Join Code, End Poll (`QuestPollHostViewController.swift`). | Compact: one row of counts (Joined · Responses · time) + big `+15s`; one primary "Next" that reveals then advances; Skip moved into ⋯ renamed "Skip question (no results)"; QR toggle as a chip. *D5.* |
| Jump-ahead prompt | "Skip ahead?" when jumping >1 cue forward (`LivePollCues.swift:96-157`). Protects only against skipping intermediate questions; responses aren't lost. The "Reopen Question N? earlier answers cleared" prompt **does** protect data. | Remove the skip-ahead confirm; keep the reopen/clear-answers confirm. |

## 5. Website controls & layout
- **Today:** iPhone landscape card is **left-aligned**, height-limited, with a 60 pt button column + right safe area; leftover width all lands on the right (~132 pt, ~217 pt with tabs) (`WebRemoteViewController+Preview.swift:56-106,153-191`). Column: Close, ⋯, Auto Scroll, Refresh, ⊕, [Send to TV], [Back]. iPad: top bar with chips left, buttons right. ⊕ opens a **temporary, unsaved tab** via URL alert (`+Chrome.swift:277-312`) — confusing because ⊕ elsewhere means "add to Show". "History" is a full screen (`WebPagesViewController`) reached from the main + menu (2nd item) and the Add Website sheet; tapping a row there goes live (see §2).
- **Proposed:** center the 16:9 card in the space left of the column and pin the column to the trailing safe edge; move Auto Scroll and ⊕ ("New Tab") into ⋯; rename ⊕ semantics or icon (`plus.square.on.square`). Demote History out of the main + menu into Add Website as "Recent sites". Phone landscape: put tab chips above the card (as today) and controls in the right column — a full top bar on iPhone landscape costs too much height. *D6.*

## 6. Slideshow drawer & editing
- **Today** (`SlideshowDetailViewController.swift`): title is the nav title; rename via a `pencil` bar button + alert; sections "Preferences" (Autoplay, Duration, Loop, Crossfade, Screen Fit, Show Ribbon When Live) and "Images"; rows read "Image 1…" (no names), 44×44 thumbs; reorder only in Edit mode; swipe Remove; Edit-mode delete style likely non-functional (`commit editingStyle` missing — needs repro).
- **Proposed:** large left-aligned title row that is an inline-editable text field (tap to rename, Return commits). Item rows: 72 pt thumb, real item name (inline-editable), always-on drag handles (`tableView.dragInteractionEnabled` / reorder in normal mode), swipe delete; per-row Fit/Fill control (§7). Rename section to "Slides (N)" or drop the heading. Fix Edit-mode delete.
- **Ribbon when live:** per-slideshow `showRibbonWhenLive`, default **false** (`Slideshow.swift:45,62`), synced via CloudKit; risk of loss on conflict because `scheduleSaveAfterConflict` writes server copy first (`CloudKitSyncEngine+Conflict.swift:99-103`) — needs repro. *D3.*

## 7. Fit/Fill
- **Today:** per-item `MediaFitSettings` (default Fit) + per-item crop; per-slideshow `Slideshow.isFill` **overrides every slide** during playback, but a slide's custom crop still wins (`SlideshowPlaybackController.swift:81-258`, `PresentationSource.swift:183-186`). No per-slide setting in the drawer. Icons `rectangle.arrowtriangle.2.inward/outward` (hard to read). Editor "Screen Fit" row shows value + chevron and is always tappable (I found no non-responsive "Fit ›"; needs your pointer to the spot you saw). Item menus already hide Fit/Fill when aspect matches (`MediaFitAvailability.swift:30-61`, 1% tolerance) but slideshows and the live button for slideshows never hide.
- **Proposed (recommended model, D4):** remove slideshow-wide `isFill`; each slide uses its own item setting, editable per row in the drawer before going live. Migration: when a slideshow had `isFill=true`, write Fill to its items (only where not already set). Control = segmented "Fit | Fill" text (or `aspectratio`/`arrow.up.left.and.arrow.down.right` with label), hidden per slide when aspect matches. Live button reflects the current slide and hides when moot.

---

## Phased plan

**Phase 1 — Live-output safety & functional bugs (no UI redesign)**
1. History row no longer goes live (`WebPagesViewController.swift`); add "add never changes live output" tests.
2. Recents: preserve local `lastOpenedAt` across sync merges, label "Opened … / Created …" (`LocalAlbumStore.swift`, `CloudKitConflictResolver.swift`, `LocalAlbum.swift`).
3. TV messaging: split iCloud-downloading vs missing-on-TV; hide TV wording when not applicable (`ItemOptions`, `HomeGrid`, `MediaLibraryPicker+Menus`, `TVLibraryStore`).
4. Poll auth: fix `Origin: null` 403 in quest-relay; resume Start after sign-in; clear stale token on 401 (`quest-relay/src/index.ts`, `+LivePollSession.swift`, `LivePollAccountStore.swift`).
5. Camera resume: demand-based session + sheet-dismiss restart (`CameraManager+SessionLifecycle.swift`, `CameraLiveViewController*.swift`, `+CameraTile.swift`).
6. Search focuses on one tap; grid scroll anchor on ribbon change; Edit-mode delete in slideshow editor; ribbon toggle conflict loss.
7. Remove poll skip-ahead confirm (keep reopen confirm).

**Phase 2 — Performance (measure first with signposts/Instruments on device)**
1. Thumbnail queue: concurrent decode, async video poster (no 8 s semaphore), off-main copies, per-item batch tiles.
2. Tap→preview: targeted cell reconfigure instead of full reload; immediate hero from memory cache; trim phone-side dissolve.

**Phase 3 — UI changes after decisions are approved**
Home Continue card; TV controls moved to Settings; slideshow drawer redesign + per-slide Fit/Fill + master removal/migration; website layout centering & control regrouping; poll drawer compaction, poll display options (timer/duration/persistent QR — needs eclipsepro quest-relay + both apps), answer gap, ring direction; PTZ disconnected/setup UX in CamTailKit.

## Open decisions (not requirements yet)
- **D1** Home banner content: Continue-last-Show card (recommended) vs remove the banner vs tips.
- **D2** Where TV status lives: Settings only + chip while connected (recommended) vs a Home indicator.
- **D3** Show ribbons when live: default on and remove the per-slideshow switch (your leaning) vs keep switch with default on.
- **D4** Fit/Fill: per-slide only, remove master (recommended, matches your leaning) vs master default + per-slide override with "Default (Fit)" shown on each row.
- **D5** Poll drawer: single "Next" (reveal→advance) and Skip moved to ⋯ (recommended).
- **D6** Website: keep side column on iPhone landscape, centered card (recommended) vs top bar on iPhone too.
- **D7** Timer ring: deplete clockwise (recommended) vs fill-up clockwise.
- **D8** PTZ setup flow details — need CamTailKit and a device walkthrough.

## Verification
- On a Mac: `xcodebuild test` for EclipseiPhone (baseline 1127 passing) after each phase; new unit tests for add-flow live guard, Recents label/sort, availability split, cue plan without skip-ahead confirm.
- Device repros before fixing (iPhone + iPad): TV messaging with iCloud-only items and never-paired TV; Recents after open on two devices; search focus; thumbnail timing with a batch of videos (Instruments Time Profiler + signposts on `ioQueue`); tap→hero latency; grid offset when a slideshow goes live while scrolled; camera resume via each path above; poll email link sign-in in Safari (expect 403 before fix).
- quest-relay: `wrangler dev` + form POST with `Origin: null` reproduces 403; passes after fix. PTZ changes: `~/apps/CamTail/tools/build_all.sh`.
