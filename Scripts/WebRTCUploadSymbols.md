# "Upload Symbols Failed" for WebRTC.framework

Distributing EclipseiPhone used to finish with **Upload completed with warnings**:

> **Upload Symbols Failed** — The archive did not include a dSYM for the WebRTC.framework
> with the UUIDs [4C4C449B-5555-3144-A133-7CD1ED11D07B]. Ensure that the archive's dSYM
> folder includes a DWARF file for WebRTC.framework with the expected UUIDs.

That is handled automatically. Product → Archive on the shared **EclipseiPhone** scheme
runs `Scripts/inject_webrtc_dsym.sh` as an Archive post-action (`$ARCHIVE_PATH`). The
script writes a UUID-matched dSYM into `<archive>/dSYMs` before Distribute App, which
is the only place Apple's uploader looks.

## What it does and doesn't affect

The iPhone binary is unchanged. EclipseiPhone's own dSYM still goes up, so our frames
symbolicate in Organizer and in Apple-collected crash reports.

WebRTC frames stay as raw addresses **until** `Package.resolved` pins stasel/WebRTC
**152.0.0 or newer** (the first releases that publish `WebRTC-M<milestone>-dSYM.zip`).
The current pin is 140.0.0, so the post-action emits a UUID-matched placeholder —
enough for Upload Symbols, not enough to symbolicate inside WebRTC.

## Why a build-phase dSYM is not enough

WebRTC reaches the app through `EclipsePhoneCameraClient` as a Swift Package
`binaryTarget` ([stasel/WebRTC](https://github.com/stasel/WebRTC)). Xcode embeds the
prebuilt `ios-arm64` slice byte for byte. That binary is stripped (no `__DWARF`), and
it is not on the target's compile debug map, so Xcode does not copy a sibling
`WebRTC.framework.dSYM` into the xcarchive. `DEBUG_INFORMATION_FORMAT` only governs
code we compile.

The `Generate WebRTC dSYM` build phase still runs `dsymutil` for lldb. User Script
Sandboxing and the debug-map copy step mean that output often never reaches the
archive — which is why the Organizer warning survived that phase.

## When the pin moves to 152+

Change the WebRTC requirement in `eclipsepro/Packages/EclipsePhoneCameraClient/Package.swift`
to `152.0.0` or newer, re-resolve, and commit `Package.resolved` here. Confirm a
phone-to-Mac camera send still connects: stasel's major version is the Chromium
milestone, so 140 → 153 crosses many of them. After that, the same post-action
downloads `WebRTC-M<milestone>-dSYM.zip` (cached under
`~/Library/Caches/com.mobleypro.eclipse/webrtc-dsym`), verifies UUIDs against the
embedded binary, and installs real DWARF. The first archive pays a ~400 MB download;
later archives reuse the cache. Do not hand-install a different milestone's dSYM —
a UUID match with the wrong DWARF would mis-symbolicate every WebRTC frame.

## Manual run

```bash
Scripts/inject_webrtc_dsym.sh ~/Library/Developer/Xcode/Archives/…/EclipseiPhone.xcarchive
```

Safe to re-run. No WebRTC in the app, or an archive that already has real DWARF for
every needed UUID, exits 0 without downloading.

If Archive still warns, a *personal* EclipseiPhone scheme is hiding the shared one
(Xcode prefers user schemes). Either share that scheme or add the same Archive
post-action: New Run Script Action, "Provide build settings from" EclipseiPhone:

```bash
"${SRCROOT}/../Scripts/inject_webrtc_dsym.sh"
```
