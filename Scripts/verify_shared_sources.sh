#!/bin/bash
#
# verify_shared_sources.sh
#
# Guards against drift in source files that are intentionally duplicated across the two
# separate Xcode projects (EclipseAppleTV and EclipseiPhone). Because the apps are
# distinct projects that don't share a module, the wire protocol lives as a verbatim copy
# in each target. This script fails the build if those copies diverge in any meaningful
# way, so the duplication can't silently break the iPhone <-> Apple TV contract.
#
# Run automatically as a build phase in both targets, and usable standalone / in CI:
#   Scripts/verify_shared_sources.sh
#
# Exit code 0 = in sync, non-zero = drift detected (with a diff printed).

set -euo pipefail

# Resolve the repository root from this script's location so it works regardless of the
# caller's working directory (Xcode runs build phases from the project directory).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TV_PROTOCOL="$REPO_ROOT/EclipseAppleTV/EclipseAppleTV/EclipseShareProtocol.swift"
IPHONE_PROTOCOL="$REPO_ROOT/EclipseiPhone/EclipseiPhone/EclipseShareProtocol.swift"

status=0

# Compares the code portion of two duplicated Swift files, ignoring the leading
# documentation header (everything before the first declaration matched by $3). The
# header intentionally differs (each copy cross-references the other's path); the code
# below it must be identical for the wire contract to hold.
compare_from() {
    local file_a="$1"
    local file_b="$2"
    local anchor="$3"
    local label="$4"

    if [[ ! -f "$file_a" ]]; then
        echo "error: missing shared source: $file_a"
        return 1
    fi
    if [[ ! -f "$file_b" ]]; then
        echo "error: missing shared source: $file_b"
        return 1
    fi

    local body_a body_b
    body_a="$(awk -v a="$anchor" 'index($0, a){p=1} p' "$file_a")"
    body_b="$(awk -v a="$anchor" 'index($0, a){p=1} p' "$file_b")"

    if [[ -z "$body_a" || -z "$body_b" ]]; then
        echo "error: could not find anchor \"$anchor\" in $label copies; update verify_shared_sources.sh"
        return 1
    fi

    if ! diff <(printf '%s' "$body_a") <(printf '%s' "$body_b") >/dev/null; then
        echo "error: $label has drifted between the Apple TV and iPhone targets:"
        echo "  $file_a"
        echo "  $file_b"
        echo "----- diff (Apple TV vs iPhone) -----"
        diff <(printf '%s' "$body_a") <(printf '%s' "$body_b") || true
        echo "-------------------------------------"
        echo "Keep the two copies in sync (only the cross-reference comment header may differ)."
        return 1
    fi

    echo "ok: $label is in sync across both targets."
    return 0
}

compare_from "$TV_PROTOCOL" "$IPHONE_PROTOCOL" "enum EclipseShareProtocol" "EclipseShareProtocol.swift" || status=1

exit $status
