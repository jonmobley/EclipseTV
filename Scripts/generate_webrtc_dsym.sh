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

if [[ -z "${BUILT_PRODUCTS_DIR:-}" || -z "${FRAMEWORKS_FOLDER_PATH:-}" ]]; then
    echo "warning: generate_webrtc_dsym.sh expects to run as an Xcode build phase"
    exit 0
fi

FRAMEWORK_BINARY="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/WebRTC.framework/WebRTC"
DSYM_OUTPUT="${BUILT_PRODUCTS_DIR}/WebRTC.framework.dSYM"

if [[ ! -f "$FRAMEWORK_BINARY" ]]; then
    echo "warning: WebRTC.framework not found at ${FRAMEWORK_BINARY}; skipping dSYM generation"
    exit 0
fi

if ! xcrun dsymutil "$FRAMEWORK_BINARY" -o "$DSYM_OUTPUT"; then
    echo "warning: dsymutil failed for WebRTC.framework; the archive will not include its dSYM"
    exit 0
fi

echo "Generated ${DSYM_OUTPUT}"
