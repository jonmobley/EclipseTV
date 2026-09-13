#!/bin/bash
#
# set_build_number.sh
#
# Stamps both apps with the same, strictly increasing build number before an archive.
#
# App Store Connect rejects an upload whose build number it has already seen for the
# marketing version, and it expects each new build to sort above the last. The number
# lived as a hand-edited literal in two project files and a plist, so cutting a second
# build meant remembering to raise three values in step — and forgetting produced a
# rejection only after the upload had finished.
#
#   Scripts/set_build_number.sh              # derive from the current UTC date and time
#   Scripts/set_build_number.sh 20270101.0   # or set one explicitly
#   Scripts/set_build_number.sh --dry-run    # report what would change, write nothing
#   Scripts/set_build_number.sh --print      # print the derived number and exit
#   Scripts/set_build_number.sh --self-test  # check the ordering rules (CI runs this)
#
# Commit the result: the build number that went to TestFlight is then recorded in
# history next to the code it was cut from.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

IPHONE_PROJECT="$REPO_ROOT/EclipseiPhone/EclipseiPhone.xcodeproj/project.pbxproj"
IPHONE_BUNDLE_ID="com.mobleypro.eclipse.EclipseiPhone"
TV_PROJECT="$REPO_ROOT/EclipseAppleTV/EclipseAppleTV.xcodeproj/project.pbxproj"
TV_BUNDLE_ID="com.mobleypro.eclipse.EclipseAppleTV"

# The iPhone target sets GENERATE_INFOPLIST_FILE, so CFBundleVersion is derived from
# CURRENT_PROJECT_VERSION at build time. The TV target ships a literal plist, which is
# therefore the value that actually reaches App Store Connect.
TV_PLIST="$REPO_ROOT/EclipseAppleTV/Info.plist"

# Debug and Release of each app target; anything else means the project was restructured.
EXPECTED_HITS=2

DRY_RUN=0
FORCE=0
EXPLICIT=""

usage() {
    awk 'NR < 3 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

# A build number that is unique per minute and sorts above every earlier one. A single
# integer carrying the time would exceed the 32-bit limit on a CFBundleVersion
# component, so the minute of the day rides in a second component instead.
derive_build_number() {
    local minute
    minute=$(( 10#$(date -u +%H) * 60 + 10#$(date -u +%M) ))
    printf '%s.%s' "$(date -u +%Y%m%d)" "$minute"
}

# Exits 0 when $1 sorts above $2, comparing period-separated integers component by
# component the way App Store Connect orders build numbers.
sorts_above() {
    awk -v a="$1" -v b="$2" '
        BEGIN {
            na = split(a, A, ".")
            nb = split(b, B, ".")
            n = (na > nb) ? na : nb
            for (i = 1; i <= n; i++) {
                x = (i <= na) ? A[i] + 0 : 0
                y = (i <= nb) ? B[i] + 0 : 0
                if (x > y) exit 0
                if (x < y) exit 1
            }
            exit 1
        }'
}

# CURRENT_PROJECT_VERSION from the build configurations of one app target.
#
# Read per configuration block rather than with a bare grep: the test and UI-test
# targets carry their own CURRENT_PROJECT_VERSION, and those are not shipped.
app_build_number() {
    local file="$1" bundle_id="$2"
    awk -v want="PRODUCT_BUNDLE_IDENTIFIER = $bundle_id;" '
        /isa = XCBuildConfiguration;/ { block = ""; inblock = 1 }
        inblock { block = block $0 "\n" }
        inblock && /^\t\t\};$/ {
            inblock = 0
            if (index(block, want) > 0 &&
                match(block, /CURRENT_PROJECT_VERSION = [^;]+;/)) {
                v = substr(block, RSTART, RLENGTH)
                sub(/CURRENT_PROJECT_VERSION = /, "", v)
                sub(/;$/, "", v)
                print v
            }
        }
    ' "$file" | sort -u
}

# Rewrites one project's app build number, refusing to touch a project whose shape no
# longer matches what was read out of it.
set_project_build_number() {
    local file="$1" bundle_id="$2" old="$3" new="$4" label="$5"
    local hits
    hits="$(grep -F -c "CURRENT_PROJECT_VERSION = $old;" "$file" || true)"
    if [[ "$hits" != "$EXPECTED_HITS" ]]; then
        echo "error: $label has $hits build configurations at $old, expected $EXPECTED_HITS."
        echo "       The test targets may now share the app's build number, or the project"
        echo "       was restructured. Check $file by hand."
        return 1
    fi
    echo "  $label: $old -> $new  ($hits configurations)"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        return 0
    fi

    local escaped_old="${old//./\\.}"
    local tmp="$file.build-number"
    sed "s/CURRENT_PROJECT_VERSION = $escaped_old;/CURRENT_PROJECT_VERSION = $new;/g" \
        "$file" > "$tmp"
    mv "$tmp" "$file"
}

# Rewrites CFBundleVersion in a literal Info.plist (the string after the key).
set_plist_build_number() {
    local file="$1" new="$2" label="$3"
    if ! grep -q "<key>CFBundleVersion</key>" "$file"; then
        echo "error: no CFBundleVersion in $file"
        return 1
    fi
    local old
    old="$(awk '/<key>CFBundleVersion<\/key>/ { getline; gsub(/.*<string>|<\/string>.*/, "");
                print; exit }' "$file")"
    echo "  $label: $old -> $new"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        return 0
    fi

    local tmp="$file.build-number"
    awk -v new="$new" '
        stamp { sub(/<string>[^<]*<\/string>/, "<string>" new "</string>"); stamp = 0 }
        /<key>CFBundleVersion<\/key>/ { stamp = 1 }
        { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"

    if ! grep -q "<string>$new</string>" "$file"; then
        echo "error: failed to write CFBundleVersion into $file"
        return 1
    fi
}

# Asserts the ordering this script promises. The comparison is the piece whose failure
# would be silent: a lexical compare also accepts most of these, then quietly decides
# build 999 outranks build 1160.
self_test() {
    local failures=0 above below
    while read -r above below; do
        [[ -n "$above" ]] || continue
        if ! sorts_above "$above" "$below"; then
            echo "  FAIL: expected $above to sort above $below"
            failures=$((failures + 1))
        fi
        if sorts_above "$below" "$above"; then
            echo "  FAIL: expected $below not to sort above $above"
            failures=$((failures + 1))
        fi
    done <<'CASES'
20260913.1 20260913
20260914.0 20260913.1439
20260913.1160 20260913.999
2 1.9999
1.0.1 1.0
CASES

    if sorts_above 20260913.5 20260913.5 || sorts_above 1 1.0; then
        echo "  FAIL: equal build numbers must not sort above each other"
        failures=$((failures + 1))
    fi

    local derived
    derived="$(derive_build_number)"
    if [[ ! "$derived" =~ ^[0-9]{8}\.[0-9]{1,4}$ ]]; then
        echo "  FAIL: derived \"$derived\" is not YYYYMMDD.<minute of day>"
        failures=$((failures + 1))
    fi

    if [[ "$failures" -ne 0 ]]; then
        echo "error: $failures self-test failure(s)."
        return 1
    fi
    echo "ok: build-number ordering self-test passed (derived $derived)."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --self-test) self_test; exit $? ;;
        --force) FORCE=1 ;;
        --print) derive_build_number; echo; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "error: unknown option $1"; usage; exit 64 ;;
        *) EXPLICIT="$1" ;;
    esac
    shift
done

for file in "$IPHONE_PROJECT" "$TV_PROJECT" "$TV_PLIST"; do
    if [[ ! -f "$file" ]]; then
        echo "error: missing $file"
        exit 66
    fi
done

NEW="${EXPLICIT:-$(derive_build_number)}"
if [[ ! "$NEW" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "error: \"$NEW\" is not a valid CFBundleVersion (up to three integers, dotted)."
    exit 65
fi

IPHONE_OLD="$(app_build_number "$IPHONE_PROJECT" "$IPHONE_BUNDLE_ID")"
TV_OLD="$(app_build_number "$TV_PROJECT" "$TV_BUNDLE_ID")"
for pair in "iPhone:$IPHONE_OLD" "Apple TV:$TV_OLD"; do
    value="${pair#*:}"
    if [[ -z "$value" || "$(wc -l <<<"$value")" -ne 1 ]]; then
        echo "error: could not read one build number for ${pair%%:*} (got \"$value\")."
        echo "       Debug and Release may disagree; reconcile them before stamping."
        exit 65
    fi
done

# Going backwards is the one mistake this script exists to prevent, so it is refused
# even when asked politely. --force is for a deliberate reset after a version bump.
#
# A dry run only reports it. The derived number carries the minute of the day, so a
# check running just after midnight legitimately sits below a number stamped the
# previous evening — and CI must not fail for that.
for pair in "iPhone:$IPHONE_OLD" "Apple TV:$TV_OLD"; do
    old="${pair#*:}"
    if [[ "$FORCE" -eq 1 ]] || sorts_above "$NEW" "$old"; then
        continue
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "note: $NEW would not sort above ${pair%%:*}'s current $old."
        continue
    fi
    echo "error: $NEW does not sort above ${pair%%:*}'s current $old."
    echo "       App Store Connect expects each build to rise. Pass --force only if"
    echo "       MARKETING_VERSION is also moving, which starts a fresh build train."
    exit 65
done

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Build number $NEW (dry run)"
else
    echo "Build number $NEW"
fi
set_project_build_number "$IPHONE_PROJECT" "$IPHONE_BUNDLE_ID" "$IPHONE_OLD" "$NEW" "iPhone project"
set_project_build_number "$TV_PROJECT" "$TV_BUNDLE_ID" "$TV_OLD" "$NEW" "Apple TV project"
set_plist_build_number "$TV_PLIST" "$NEW" "Apple TV Info.plist"

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "ok: dry run only, nothing written."
else
    echo "ok: both apps are at $NEW. Commit this, then archive."
fi
