#!/bin/bash
#
# generate_webrtc_dsym.sh
#
# Produces a dSYM for the prebuilt WebRTC.framework that ships inside the app.
#
# EclipseiPhone links EclipsePhoneCameraClient, which depends on the stasel/WebRTC binary
# xcframework. That binary is distributed stripped, with no dSYM, so Xcode 16+ reports
# "Upload Symbols Failed: The archive did not include a dSYM for the WebRTC.framework"
# on every App Store Connect upload. The upload itself succeeds; the message is noise.
#
# Running dsymutil over the embedded Mach-O emits a dSYM whose UUID matches the binary,
# which is all the upload check looks for. It does NOT recover WebRTC's symbols — the
# vendor stripped them before publishing — so WebRTC frames in crash reports stay
# unsymbolicated either way. This only keeps the Organizer quiet.
#
# Wired in as a Run Script phase on the EclipseiPhone target, set to run only when
# installing (archive/install builds). The phase declares the embedded binary as an
# input and the dSYM as an output so it runs with User Script Sandboxing left on.
#
# Any failure here is reported as a build warning rather than an error: the worst case
# must be "the Organizer warning comes back", never "the archive fails".

set -uo pipefail

if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${FRAMEWORKS_FOLDER_PATH:-}" \
      || -z "${DWARF_DSYM_FOLDER_PATH:-}" ]]; then
    echo "warning: generate_webrtc_dsym.sh expects to run as an Xcode build phase"
    exit 0
fi

# Read the app from TARGET_BUILD_DIR, not BUILT_PRODUCTS_DIR. In an archive the copy under
# BUILT_PRODUCTS_DIR is only a symlink into InstallationBuildProductsLocation, and the user
# script sandbox checks the resolved path, which isn't a declared input: dsymutil got
# "Operation not permitted", no dSYM was written, and the Organizer warning came back
# (build 2026110801). TARGET_BUILD_DIR is the real location in archive and plain builds.
FRAMEWORK_BINARY="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/WebRTC.framework/WebRTC"
# Next to EclipseiPhone.app.dSYM, which is where the archive collects dSYMs from.
DSYM_OUTPUT="${DWARF_DSYM_FOLDER_PATH}/WebRTC.framework.dSYM"
# The bundle's two files are this phase's declared outputs. The user script sandbox only
# lets a phase write its declared outputs (and create their parent folders), so dsymutil
# writing the whole bundle in place failed with "cannot create bundle: Operation not
# permitted" and left an empty WebRTC.framework.dSYM folder in the archive (build
# 2026110901). Build the bundle in a temp folder instead, then copy just these two in.
DSYM_PLIST="${DSYM_OUTPUT}/Contents/Info.plist"
DSYM_DWARF="${DSYM_OUTPUT}/Contents/Resources/DWARF/WebRTC"

if [[ ! -f "$FRAMEWORK_BINARY" ]]; then
    echo "warning: WebRTC.framework not found at ${FRAMEWORK_BINARY}; skipping dSYM generation"
    exit 0
fi

# dsymutil writes "error:" lines on failure, and Xcode turns any line starting with
# "error:" into a failed build phase even when this script exits 0. Capture its output
# and re-report the first line as a warning: a missing WebRTC dSYM must never fail the
# archive, but it shouldn't fail silently either (it did, until build 2026110801).
work_dir="$(mktemp -d)"
dsym_log="${work_dir}/dsymutil.log"
staged="${work_dir}/WebRTC.framework.dSYM"

fail() {
    reason="$(sed -e 's/^[[:space:]]*error:[[:space:]]*//' "$dsym_log" 2>/dev/null | head -n 1)"
    echo "warning: WebRTC dSYM not generated; App Store Connect will warn on upload (${reason:-$1})"
    rm -rf "$work_dir"
    exit 0
}

xcrun dsymutil "$FRAMEWORK_BINARY" -o "$staged" >"$dsym_log" 2>&1 || fail "dsymutil failed"
[[ -f "${staged}/Contents/Info.plist" && -f "${staged}/Contents/Resources/DWARF/WebRTC" ]] \
    || fail "dsymutil produced no bundle"

mkdir -p "$(dirname "$DSYM_DWARF")" >"$dsym_log" 2>&1 \
    && cp -f "${staged}/Contents/Info.plist" "$DSYM_PLIST" >>"$dsym_log" 2>&1 \
    && cp -f "${staged}/Contents/Resources/DWARF/WebRTC" "$DSYM_DWARF" >>"$dsym_log" 2>&1 \
    || fail "could not copy the bundle into place"
rm -rf "$work_dir"

echo "Generated ${DSYM_OUTPUT}"
