#!/bin/bash
#
# inject_webrtc_dsym.sh
#
# Puts a matching dSYM for the prebuilt WebRTC.framework into an .xcarchive so
# Distribute App's "Upload Symbols" step stops failing with:
#
#   Upload Symbols Failed
#   The archive did not include a dSYM for the WebRTC.framework with the UUIDs [...].
#
# WebRTC arrives through EclipsePhoneCameraClient as a stasel/WebRTC binaryTarget.
# Xcode embeds that slice stripped (no __DWARF). DEBUG_INFORMATION_FORMAT does not
# apply, and a Run Script that writes a dSYM next to the app is not copied into
# the xcarchive — Apple only packages dSYMs from the compile debug map. The hook
# that actually lands a file in <archive>/dSYMs is this script, run as the
# EclipseiPhone scheme's Archive post-action ($ARCHIVE_PATH is set for us).
#
# stasel publishes WebRTC-M<milestone>-dSYM.zip from 152.0.0. When Package.resolved
# pins that or newer, we download the matching slice (cached) and install it.
# Older pins (including the current 140.0.0) have no upstream DWARF, so we emit a
# UUID-matched placeholder with dsymutil. That silences the upload warning; WebRTC
# frames still will not symbolicate until the pin moves to 152+.
#
# Usage:
#   Scripts/inject_webrtc_dsym.sh /path/to/EclipseiPhone.xcarchive
#   Scripts/inject_webrtc_dsym.sh           # uses $ARCHIVE_PATH (scheme post-action)
#   Scripts/inject_webrtc_dsym.sh --self-test
#
# Environment:
#   WEBRTC_VERSION   Override the version read from Package.resolved (e.g. 152.0.0).
#   DSYM_CACHE_DIR   Release download cache. Defaults to
#                    ~/Library/Caches/com.mobleypro.eclipse/webrtc-dsym.
#
# Exit 0 = archive now has a UUID-matched dSYM, already had real DWARF, or embeds
# no WebRTC. Any other exit means Distribute App will still warn.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFTPM_DIR="EclipseiPhone/EclipseiPhone.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
RESOLVED_FILE="$REPO_ROOT/$SWIFTPM_DIR/Package.resolved"
CACHE_DIR="${DSYM_CACHE_DIR:-$HOME/Library/Caches/com.mobleypro.eclipse/webrtc-dsym}"
FIRST_DSYM_VERSION="152.0.0"
PLACEHOLDER_BUNDLE="WebRTC.framework.dSYM"

# MARK: - Version helpers

# True when $1 >= $2 (dotted triples, missing parts count as 0).
version_ge() {
    local IFS=.
    # shellcheck disable=SC2206
    local a=($1) b=($2)
    local i ai bi
    for i in 0 1 2; do
        ai="${a[i]:-0}"
        bi="${b[i]:-0}"
        if ((10#$ai > 10#$bi)); then return 0; fi
        if ((10#$ai < 10#$bi)); then return 1; fi
    done
    return 0
}

# First "version" after the webrtc identity line in a Package.resolved.
parse_webrtc_version() {
    local file="$1"
    awk '
        /"identity"[[:space:]]*:[[:space:]]*"webrtc"/ { found = 1 }
        found && /"version"/ { gsub(/[^0-9.]/, ""); print; exit }
    ' "$file"
}

# MARK: - Self-test (Linux CI; no dwarfdump / archive required)

run_self_test() {
    version_ge 152.0.0 152.0.0 || { echo "fail: 152 >= 152"; return 1; }
    version_ge 153.0.0 152.0.0 || { echo "fail: 153 >= 152"; return 1; }
    version_ge 140.0.0 152.0.0 && { echo "fail: 140 >= 152"; return 1; }
    version_ge 151.9.9 152.0.0 && { echo "fail: 151.9.9 >= 152"; return 1; }
    version_ge 152.0.1 152.0.0 || { echo "fail: 152.0.1 >= 152"; return 1; }

    local tmp
    tmp="$(mktemp)"
    cat >"$tmp" <<'EOF'
{
  "pins" : [
    {
      "identity" : "webrtc",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/stasel/WebRTC.git",
      "state" : {
        "revision" : "abc",
        "version" : "140.0.0"
      }
    }
  ],
  "version" : 3
}
EOF
    local parsed
    parsed="$(parse_webrtc_version "$tmp")"
    rm -f "$tmp"
    [[ "$parsed" == "140.0.0" ]] || { echo "fail: parsed \"$parsed\""; return 1; }

    parsed="$(parse_webrtc_version "$RESOLVED_FILE")"
    [[ "$parsed" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        echo "fail: Package.resolved webrtc version \"$parsed\""
        return 1
    }

    echo "ok: inject_webrtc_dsym self-test"
}

if [[ "${1:-}" == "--self-test" ]]; then
    run_self_test
    exit 0
fi

# MARK: - Archive injection

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

for tool in curl unzip dwarfdump otool; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: required tool not found: $tool"
        exit 69
    fi
done

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

carries_debug_info() {
    otool -l "$1" 2>/dev/null | grep -q 'sectname __debug_info'
}

# Real DWARF only — a dsymutil placeholder matches UUID but has nothing to
# symbolicate, so it must not skip installing upstream symbols after a 152+ pin.
archive_covers_needed_uuids() {
    local present="" dwarf
    while IFS= read -r dwarf; do
        carries_debug_info "$dwarf" || continue
        present+="$(uuids_of "$dwarf")"$'\n'
    done < <(find "$ARCHIVE/dSYMs" -path '*/Contents/Resources/DWARF/*' -type f 2>/dev/null)

    local uuid
    while IFS= read -r uuid; do
        grep -qxF "$uuid" <<<"$present" || return 1
    done <<<"$NEEDED_UUIDS"
    return 0
}

dwarf_files_cover_needed_uuids() {
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
    VERSION="$(parse_webrtc_version "$RESOLVED_FILE")"
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: could not read the pinned WebRTC version (got \"$VERSION\")."
    echo "       Pass it explicitly: WEBRTC_VERSION=$FIRST_DSYM_VERSION $0 \"$ARCHIVE\""
    exit 65
fi

MILESTONE="${VERSION%%.*}"
echo "Pinned WebRTC: $VERSION (Chromium milestone M$MILESTONE)"

# MARK: - Placeholder (pins below 152.0.0)

install_placeholder_dsym() {
    if ! command -v xcrun >/dev/null 2>&1; then
        echo "error: xcrun/dsymutil is required to emit a UUID-matched placeholder."
        return 69
    fi
    mkdir -p "$ARCHIVE/dSYMs"
    local dest="$ARCHIVE/dSYMs/$PLACEHOLDER_BUNDLE"
    rm -rf "$dest"
    # Sandboxed build phases cannot always run dsymutil; a scheme post-action can.
    if ! xcrun dsymutil "$WEBRTC_BINARY" -o "$dest"; then
        echo "error: dsymutil failed for $WEBRTC_BINARY"
        return 70
    fi
    if ! dwarf_files_cover_needed_uuids; then
        echo "error: dsymutil wrote $dest but its UUID(s) do not match the binary."
        return 65
    fi
    echo "ok: installed UUID-matched placeholder $PLACEHOLDER_BUNDLE"
    echo "    Upload Symbols will accept this; WebRTC frames stay unsymbolicated"
    echo "    until Package.resolved pins $FIRST_DSYM_VERSION or newer."
    return 0
}

if ! version_ge "$VERSION" "$FIRST_DSYM_VERSION"; then
    echo "note: $VERSION ships no WebRTC-M${MILESTONE}-dSYM.zip (first asset is $FIRST_DSYM_VERSION)."
    install_placeholder_dsym
    exit $?
fi

# MARK: - Official dSYM zip (152.0.0+)

ASSET="WebRTC-M$MILESTONE-dSYM.zip"
ASSET_URL="https://github.com/stasel/WebRTC/releases/download/$VERSION/$ASSET"
ZIP="$CACHE_DIR/$ASSET"
mkdir -p "$CACHE_DIR"

if [[ ! -f "$ZIP" ]]; then
    status="$(curl -sIL -o /dev/null -w '%{http_code}' "$ASSET_URL" || true)"
    if [[ "$status" != "200" ]]; then
        echo "warning: expected $ASSET for $VERSION but GitHub returned HTTP $status."
        echo "         Falling back to a UUID-matched placeholder."
        install_placeholder_dsym
        exit $?
    fi
    echo "Downloading $ASSET (a few hundred MB, cached in $CACHE_DIR)…"
    curl -fL --retry 3 --retry-delay 2 -o "$ZIP.part" "$ASSET_URL"
    mv "$ZIP.part" "$ZIP"
fi

UNPACK_DIR="$CACHE_DIR/M$MILESTONE"
mkdir -p "$UNPACK_DIR"

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
    echo "warning: $ASSET contains no dSYM matching the embedded binary's UUID(s)."
    echo "         Falling back to a UUID-matched placeholder."
    install_placeholder_dsym
    exit $?
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
