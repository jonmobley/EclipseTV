#!/bin/bash
#
# inject_webrtc_dsym.sh
#
# Puts a matching dSYM for the prebuilt WebRTC.framework into an .xcarchive, so the App
# Store upload's "Upload Symbols" step stops failing with:
#
#   Upload Symbols Failed
#   The archive did not include a dSYM for the WebRTC.framework with the UUIDs [...].
#
# Why the archive has no dSYM to begin with: WebRTC reaches the iPhone app through the
# EclipsePhoneCameraClient package as a Swift Package binaryTarget (stasel/WebRTC). Xcode
# embeds that prebuilt slice byte for byte — it is fully stripped (no __DWARF, no debug
# symbols anywhere in the build graph), so nothing local can generate the dSYM and
# DEBUG_INFORMATION_FORMAT has no effect on it. Upstream publishes the debug info as a
# separate release asset (WebRTC-M<milestone>-dSYM.zip), so this script downloads that
# asset, verifies its UUIDs against the binary actually embedded in the archive, and
# copies the matching bundle into <archive>/dSYMs.
#
# The script never fabricates a dSYM. A UUID-matched bundle carrying some other build's
# debug info would be accepted by App Store Connect and then mis-symbolicate every WebRTC
# frame, which is worse than an unsymbolicated one; so when upstream published no dSYM for
# the pinned milestone the script says exactly that and exits non-zero.
#
# Usage:
#   Scripts/inject_webrtc_dsym.sh /path/to/EclipseiPhone.xcarchive
#   Scripts/inject_webrtc_dsym.sh           # uses $ARCHIVE_PATH (Xcode archive post-action)
#
# Environment:
#   WEBRTC_VERSION   Override the version read from Package.resolved (e.g. 152.0.0).
#   DSYM_CACHE_DIR   Where release downloads are unpacked. Defaults to
#                    ~/Library/Caches/com.mobleypro.eclipse/webrtc-dsym.
#
# Exit 0 = the archive now carries a UUID-matched dSYM, already had one, or embeds no
# WebRTC at all. Any other exit code means the upload will still warn.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFTPM_DIR="EclipseiPhone/EclipseiPhone.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
RESOLVED_FILE="$REPO_ROOT/$SWIFTPM_DIR/Package.resolved"
CACHE_DIR="${DSYM_CACHE_DIR:-$HOME/Library/Caches/com.mobleypro.eclipse/webrtc-dsym}"

# The milestone that first shipped a -dSYM.zip release asset. Quoted in the failure path so
# the fix is actionable without going digging through upstream releases.
FIRST_DSYM_VERSION="152.0.0"

ARCHIVE="${1:-${ARCHIVE_PATH:-}}"

if [[ -z "$ARCHIVE" ]]; then
    echo "error: no archive given."
    echo "usage: Scripts/inject_webrtc_dsym.sh /path/to/EclipseiPhone.xcarchive"
    echo "       (or set ARCHIVE_PATH, which Xcode does for archive post-actions)"
    exit 64
fi

if [[ ! -d "$ARCHIVE" ]]; then
    echo "error: not an archive directory: $ARCHIVE"
    exit 66
fi

for tool in curl unzip dwarfdump; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: required tool not found: $tool"
        exit 69
    fi
done

# Every UUID in a Mach-O or dSYM DWARF file, one per line. A device archive has a single
# arm64 slice, but reading them all keeps the comparison honest for fat binaries.
uuids_of() {
    dwarfdump --uuid "$1" 2>/dev/null | awk '/^UUID:/ { print $2 }' | sort -u
}

APP="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' -print -quit \
    2>/dev/null || true)"
if [[ -z "$APP" ]]; then
    echo "error: no .app inside $ARCHIVE/Products/Applications"
    exit 66
fi

WEBRTC_BINARY="$APP/Frameworks/WebRTC.framework/WebRTC"
if [[ ! -f "$WEBRTC_BINARY" ]]; then
    echo "note: $(basename "$APP") embeds no WebRTC.framework — nothing to inject."
    exit 0
fi

NEEDED_UUIDS="$(uuids_of "$WEBRTC_BINARY")"
if [[ -z "$NEEDED_UUIDS" ]]; then
    echo "error: could not read any UUID from $WEBRTC_BINARY"
    exit 65
fi
echo "Archive embeds WebRTC with UUID(s):"
sed 's/^/  /' <<<"$NEEDED_UUIDS"

# True when the archive's dSYMs folder already covers every UUID the binary needs.
archive_covers_needed_uuids() {
    local present="" dwarf
    while IFS= read -r dwarf; do
        present+="$(uuids_of "$dwarf")"$'\n'
    done < <(find "$ARCHIVE/dSYMs" -path '*/Contents/Resources/DWARF/*' -type f 2>/dev/null)

    local uuid
    while IFS= read -r uuid; do
        grep -qxF "$uuid" <<<"$present" || return 1
    done <<<"$NEEDED_UUIDS"
    return 0
}

if archive_covers_needed_uuids; then
    echo "ok: archive already carries a matching WebRTC dSYM."
    exit 0
fi

VERSION="${WEBRTC_VERSION:-}"
if [[ -z "$VERSION" ]]; then
    if [[ ! -f "$RESOLVED_FILE" ]]; then
        echo "error: cannot find $RESOLVED_FILE; set WEBRTC_VERSION to the pinned version."
        exit 66
    fi
    # The webrtc pin's "version" is the first one after its identity line.
    VERSION="$(awk '
        /"identity"[[:space:]]*:[[:space:]]*"webrtc"/ { found = 1 }
        found && /"version"/ { gsub(/[^0-9.]/, ""); print; exit }
    ' "$RESOLVED_FILE")"
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: could not read the pinned WebRTC version (got \"$VERSION\")."
    echo "       Pass it explicitly: WEBRTC_VERSION=$FIRST_DSYM_VERSION $0 \"$ARCHIVE\""
    exit 65
fi

MILESTONE="${VERSION%%.*}"
ASSET="WebRTC-M$MILESTONE-dSYM.zip"
ASSET_URL="https://github.com/stasel/WebRTC/releases/download/$VERSION/$ASSET"
echo "Pinned WebRTC: $VERSION (Chromium milestone M$MILESTONE)"

ZIP="$CACHE_DIR/$ASSET"
mkdir -p "$CACHE_DIR"

if [[ ! -f "$ZIP" ]]; then
    status="$(curl -sIL -o /dev/null -w '%{http_code}' "$ASSET_URL" || true)"
    if [[ "$status" != "200" ]]; then
        echo "error: stasel/WebRTC $VERSION publishes no $ASSET (HTTP $status)."
        echo "       That release ships only the stripped xcframework, so no dSYM for"
        echo "       these UUIDs exists anywhere — one cannot be generated locally."
        echo "       To make the upload warning go away, move the WebRTC requirement in"
        echo "       EclipsePhoneCameraClient's Package.swift to $FIRST_DSYM_VERSION or"
        echo "       newer (the first release with a -dSYM.zip asset) and re-archive."
        echo "       Until then the warning is expected: Apple keeps the build and only"
        echo "       leaves WebRTC frames unsymbolicated in Apple-collected crash reports."
        exit 75
    fi
    echo "Downloading $ASSET (a few hundred MB, cached in $CACHE_DIR)…"
    curl -fL --retry 3 --retry-delay 2 -o "$ZIP.part" "$ASSET_URL"
    mv "$ZIP.part" "$ZIP"
fi

UNPACK_DIR="$CACHE_DIR/M$MILESTONE"
mkdir -p "$UNPACK_DIR"

# Slice bundles are named WebRTC-<slice>.dSYM. Device archives always want ios-arm64, so
# try it first and unpack the rest only if its UUIDs don't match — each slice's DWARF is
# hundreds of MB.
slice_bundles() {
    unzip -Z1 "$ZIP" '*.dSYM/Contents/Info.plist' \
        | sed 's|/Contents/Info.plist$||' \
        | sort -u \
        | awk '/-ios-arm64\.dSYM$/ { print; next }
               { rest = rest $0 "\n" }
               END { printf "%s", rest }'
}

installed=()
mkdir -p "$ARCHIVE/dSYMs"

while IFS= read -r bundle; do
    [[ -n "$bundle" ]] || continue
    if [[ ! -d "$UNPACK_DIR/$bundle" ]]; then
        echo "Unpacking $bundle…"
        unzip -oq "$ZIP" "$bundle/*" -d "$UNPACK_DIR"
    fi

    dwarf="$(find "$UNPACK_DIR/$bundle/Contents/Resources/DWARF" -type f -print -quit)"
    [[ -n "$dwarf" ]] || continue
    slice_uuids="$(uuids_of "$dwarf")"

    # Install the slice only if it actually symbolicates part of what shipped.
    wanted=0
    while IFS= read -r uuid; do
        grep -qxF "$uuid" <<<"$slice_uuids" && wanted=1
    done <<<"$NEEDED_UUIDS"
    [[ "$wanted" -eq 1 ]] || continue

    rm -rf "$ARCHIVE/dSYMs/$bundle"
    cp -R "$UNPACK_DIR/$bundle" "$ARCHIVE/dSYMs/$bundle"
    installed+=("$bundle")

    archive_covers_needed_uuids && break
done < <(slice_bundles)

if [[ "${#installed[@]}" -eq 0 ]]; then
    echo "error: $ASSET contains no dSYM matching the embedded binary's UUID(s)."
    echo "       The archive was probably built against a different WebRTC version than"
    echo "       the one Package.resolved pins ($VERSION). Re-resolve packages, archive"
    echo "       again, or pass WEBRTC_VERSION explicitly."
    exit 65
fi

if ! archive_covers_needed_uuids; then
    echo "error: installed ${installed[*]} but the archive's dSYMs still don't cover every"
    echo "       UUID in the embedded binary. Left them in place for inspection:"
    echo "       $ARCHIVE/dSYMs"
    exit 65
fi

echo "ok: installed ${installed[*]} into"
echo "    $ARCHIVE/dSYMs"
echo "    Re-run Distribute App; Upload Symbols now has the DWARF it asked for."
