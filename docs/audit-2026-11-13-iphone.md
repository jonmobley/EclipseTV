# Eclipse iPhone audit — 2026-11-13

Before TestFlight build 2026111301. Release tree: feature/airplay-custom-screen-size (8511a24)
merged with main 8e5f149 on branch release/testflight-20261113; sibling packages eclipsepro main
8dd92423 and CamTail main ac076aa (CamTailKit 1.8.0). iPhone target only.

## Status
- Unit tests, CI way (parallel clones, feature branch + current sibling checkouts): 1255 passed, 0 failed.
- Unit tests, serial (`-parallel-testing-enabled NO`), merged release tree: 1261 passed, 0 failed.
- Release archive (generic iOS device, NDI SDK linked): OK. Only the known NDI static-library symbol warnings.
- Launch on iPhone 17 Pro simulator (signed Debug build): OK. Settings → Display Mode → Screen Size: add,
  save, select and the Settings summary ("Landscape · Lobby wall (512×786)") all behave as designed.
- Independent code review of the branch diff (second reader): one real nit, fixed in 8511a24 (two
  `bringSubviewToFront` calls still targeted `view` after the overlays moved to `stageView`, so they
  were no-ops; z-order happened to be right by insertion order).
- CI on PR #91: green on the last run before 8511a24; the push of 8511a24 re-runs it.

## Findings
- Medium — The feature branch was cut from main at the 2026110801 build and main has since gained four
  merged PRs (#86 Phase 1 fixes, #87 Phase 2 speed, #90 Phase 3 UI, #89 poll screen options). A build
  from the branch alone would have dropped them; the release merges origin/main, so 2026111301 carries
  everything. Merge was clean; the only files both sides touched were CLAUDE.md, the project file,
  WebRemoteViewController+Preview.swift and iPhoneMainViewController+MediaActions.swift, and the merged
  tree builds and passes.
- Low — Hero (phone live preview) card stays 16:9 while a tall custom size is active, so an unframed
  "Fill" still crops differently on the phone than on the TV's letterboxed stage; framed stills match.
  Grid thumbnails and web captures also stay on the 16:9 library shape (by design). Owner decision
  whether the hero should letterbox like the TV.
- Low — Custom sizes accept any edge ≥ 2 (e.g. 1920×2 gives a sliver stage, no crash), matching the Mac
  app's rule; stored sizes are not re-validated on decode.
- Low — PR #89's signed-in "Manage on QuestPoll" link and poll screen options need the QuestPoll server
  deployed with migration 0005; until then the app falls back to the plain page / old behaviour.
- Info — The unsigned test-host build (`CODE_SIGNING_ALLOWED=NO`) traps in CloudKit at launch when run
  as an app; that is expected (no iCloud entitlement) and guarded for the XCTest host. Not a product bug.
- Info — Stale uncommitted build-number bump to 2026111001 in the main checkout (never uploaded; App
  Store Connect has no such build) was discarded.

## Checked and fine
- Sibling packages: eclipsepro main contains the last shipped fedfcff6; CamTail main contains every
  CamTailKit change from the remove-joystick commit shipped in 2026110403, plus 1.8.0.
- No new readers of the plain orientation aspect slipped in from main's PRs; the remaining ones
  (WebThumbnailAspect, ImagePreviewViewController) are the library-bucket shape on purpose.
- Settings table section/row indexing is consistent in Landscape and Vertical; swipe-delete during a
  settings post is guarded; storage posts the change notification once and only on a real change.
- Apple TV code unchanged since the TestFlight TV build; EclipseShare/v3 unchanged, so no TV upload needed.
- Disk 85 GB free; NDI SDK present; App Store Connect reachable (build 2026110801 VALID).

## Not verified
- AirPlay / HDMI output with a custom size on a real display (the simulator has no external screen).
- Sentry: `sentry-cli issues list` returns 403 with the local token and the Sentry MCP is not signed
  in, so recent crash issues were not reviewed.
- Open items from the 2026-11-02 audit are unchanged (eclipse://mac-remote host check, Int(seconds)
  trap in LibraryGridViewController+ShowLiveCommands, library delete tombstones, Sentry session
  tracking, AppStoreReviewNotes.txt).
