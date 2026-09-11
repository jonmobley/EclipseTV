# "Upload Symbols Failed" for WebRTC.framework

Distributing EclipseiPhone finishes with **Upload completed with warnings**:

> **Upload Symbols Failed** — The archive did not include a dSYM for the WebRTC.framework
> with the UUIDs [4C4C449B-5555-3144-A133-7CD1ED11D07B]. Ensure that the archive's dSYM
> folder includes a DWARF file for WebRTC.framework with the expected UUIDs.

## What it does and doesn't affect

The build is accepted — this is a warning on the symbol-upload step, not on the upload.
EclipseiPhone's own dSYM (and every other target we compile) still goes up, so our frames
symbolicate normally in Xcode Organizer and in Apple-collected crash reports. The only
loss is that stack frames *inside* WebRTC stay as raw addresses.

## Why the dSYM isn't there

WebRTC reaches the app through the `EclipsePhoneCameraClient` package as a Swift Package
`binaryTarget` pointing at [stasel/WebRTC](https://github.com/stasel/WebRTC) (pinned in
`EclipseiPhone.xcodeproj/.../swiftpm/Package.resolved`). Xcode embeds the prebuilt
`ios-arm64` slice byte for byte: the UUID in the dialog above is exactly the UUID of the
slice inside the upstream `WebRTC-M140.xcframework.zip`.

That binary is fully stripped — no `__DWARF` segment, only its exported symbol table — and
the release zip contains no `dSYMs/` directory. So there is nothing for Xcode to copy into
the archive, and nothing `dsymutil` can recover locally. `DEBUG_INFORMATION_FORMAT` only
governs code we compile, so it has no bearing here.

Upstream started publishing the debug info as a **separate release asset**,
`WebRTC-M<milestone>-dSYM.zip`, with **152.0.0**. Releases 119.0.0 through 151.0.1 —
including our pinned 140.0.0 — ship the xcframework only.

## Options

**1. Ship as-is.** Click Done. Expect the warning on every upload while we're pinned below
152.0.0.

**2. Move to a milestone that publishes symbols, then inject them.** Change the WebRTC
requirement in `eclipsepro/Packages/EclipsePhoneCameraClient/Package.swift` to `152.0.0` or
newer (that package lives outside this repo, and the version constraint is what keeps
`Package.resolved` on 140.0.0), re-resolve packages, and confirm the camera client still
builds — stasel's major version tracks the Chromium milestone, so the ObjC API can shift
between them. Then run the script below on each archive before uploading.

## Scripts/inject_webrtc_dsym.sh

Reads the WebRTC version from `Package.resolved`, downloads the matching
`WebRTC-M<milestone>-dSYM.zip` (cached under
`~/Library/Caches/com.mobleypro.eclipse/webrtc-dsym`), verifies that a slice's DWARF UUIDs
match the binary actually embedded in the archive, and copies that bundle into the
archive's `dSYMs/` folder.

```bash
Scripts/inject_webrtc_dsym.sh ~/Library/Developer/Xcode/Archives/…/EclipseiPhone.xcarchive
```

It's safe to re-run: an archive that already covers the needed UUIDs, or that embeds no
WebRTC at all, exits 0 without downloading anything. If the pinned release publishes no
dSYM, it exits non-zero and says so rather than installing anything, because a
UUID-matched bundle holding a *different* build's debug info would be accepted by App
Store Connect and then mis-symbolicate every WebRTC frame.

To run it automatically, add it as an **Archive post-action** on the EclipseiPhone scheme
(Product → Scheme → Edit Scheme → Archive → Post-actions → New Run Script Action, with
"Provide build settings from" set to EclipseiPhone). Xcode passes the archive in
`$ARCHIVE_PATH`, which the script uses when no path argument is given:

```bash
"$SRCROOT/../Scripts/inject_webrtc_dsym.sh"
```

Note that post-actions run after the archive is created but *before* Distribute App, and
their output only appears in the scheme's post-action log — so verify the first run by
invoking the script by hand.
