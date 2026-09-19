#!/bin/bash
#
# generate_webrtc_dsym.sh
#
# Best-effort dSYM next to the embedded WebRTC.framework during install/archive
# builds. This is not enough on its own: Xcode copies dSYMs from the compile
# debug map, and a prebuilt SPM binary is not on that map, so the bundle often
# never reaches the xcarchive. The EclipseiPhone scheme's Archive post-action
# (`Scripts/inject_webrtc_dsym.sh`) is what actually lands a UUID-matched dSYM
# in <archive>/dSYMs before Distribute App.
#
# Kept as a Run Script phase so a local products-dir copy exists for lldb. Any
# failure here is a warning — the post-action is the one that must succeed.

set -uo pipefail

if [[ -z "${BUILT_PRODUCTS_DIR:-}" || -z "${FRAMEWORKS_FOLDER_PATH:-}" ]]; then
    echo "warning: generate_webrtc_dsym.sh expects to run as an Xcode build phase"
    exit 0
fi

FRAMEWORK_BINARY="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/WebRTC.framework/WebRTC"
DSYM_DIR="${DWARF_DSYM_FOLDER_PATH:-$BUILT_PRODUCTS_DIR}"
DSYM_OUTPUT="${DSYM_DIR}/WebRTC.framework.dSYM"

if [[ ! -f "$FRAMEWORK_BINARY" ]]; then
    echo "warning: WebRTC.framework not found at ${FRAMEWORK_BINARY}; skipping dSYM generation"
    exit 0
fi

# User Script Sandboxing blocks dsymutil's default temp dir; stay inside outputs.
if [[ -n "${DERIVED_FILE_DIR:-}" ]]; then
    export TMPDIR="$DERIVED_FILE_DIR"
    mkdir -p "$TMPDIR"
fi
mkdir -p "$DSYM_DIR"

if ! xcrun dsymutil "$FRAMEWORK_BINARY" -o "$DSYM_OUTPUT"; then
    echo "warning: dsymutil failed for WebRTC.framework; Archive post-action will retry"
    exit 0
fi

echo "Generated ${DSYM_OUTPUT}"
