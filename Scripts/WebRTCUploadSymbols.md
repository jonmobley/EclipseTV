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
`WebRTC-M<milestone>-dSYM.zip`, with **152.0.0** (2026-08-31). Releases 119.0.0 through
151.0.1 — including our pinned 140.0.0 — ship the xcframework only. **153.0.0**
(2026-09-11) is the newest release and also carries the asset.

## Options

**1. Ship as-is.** Click Done. Expect the warning on every upload while we're pinned below
152.0.0.

There is also a `Generate WebRTC dSYM` build phase on the EclipseiPhone target
(`Scripts/generate_webrtc_dsym.sh`, from PR #33) that runs `dsymutil` over the embedded
framework on install builds. It can only emit a bundle whose UUID matches — the symbols it
would need were stripped upstream — so it silences the Organizer warning without making a
single WebRTC frame readable. It reports every failure as a build warning, so it can never
fail an archive. Remove the phase if you would rather see the honest warning.

**2. Move to a milestone that publishes symbols, then inject them.** Change the WebRTC
requirement in `eclipsepro/Packages/EclipsePhoneCameraClient/Package.swift` to `152.0.0` or
newer (that package lives outside this repo, and the version constraint is what keeps
`Package.resolved` on 140.0.0), re-resolve packages, and commit the updated
`Package.resolved` here. Confirm the camera client still builds and that a phone-to-Mac
camera send still connects: stasel's major version tracks the Chromium milestone, so 140 →
153 crosses thirteen of them and the ObjC API can shift on the way. Then run the script
below on each archive before uploading.

Cost of doing this, measured against the real 153.0.0 assets: the dSYM zip is 395 MiB and
the `ios-arm64` DWARF inside it is 203 MB, so the first archive pays a ~400 MB download
(cached afterwards) and every archive grows by ~200 MB.

## Scripts/inject_webrtc_dsym.sh

Reads the WebRTC version from `Package.resolved`, downloads the matching
`WebRTC-M<milestone>-dSYM.zip` (cached under
`~/Library/Caches/com.mobleypro.eclipse/webrtc-dsym`), verifies that a slice's DWARF UUIDs
match the binary actually embedded in the archive, and copies that bundle into the
archive's `dSYMs/` folder.

```bash
Scripts/inject_webrtc_dsym.sh ~/Library/Developer/Xcode/Archives/…/EclipseiPhone.xcarchive
```

The asset holds one bundle per slice at its top level — `WebRTC-ios-arm64.dSYM`,
`…-ios-x86_64_arm64-simulator.dSYM`, `…-ios-x86_64_arm64-maccatalyst.dSYM`, and
`…-macos-x86_64_arm64.dSYM` in 153.0.0. The script unpacks `ios-arm64` first, since that
is the slice a device archive embeds, and only reaches for the others if its UUIDs don't
match.

It's safe to re-run: an archive that already covers the needed UUIDs, or that embeds no
WebRTC at all, exits 0 without downloading anything. "Covers" means a DWARF file with real
debug info — the `__debug_info` section the build phase above cannot produce — so a
symbol-free placeholder sitting in `dSYMs/` does not stop the real bundle from landing. If
the pinned release publishes no dSYM, it exits non-zero and says so rather than installing
anything, because a UUID-matched bundle holding a *different* build's debug info would be
accepted by App Store Connect and then mis-symbolicate every WebRTC frame.

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
