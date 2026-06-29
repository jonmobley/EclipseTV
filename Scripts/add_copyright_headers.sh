#!/bin/bash
#
# add_copyright_headers.sh
#
# Ensures every Swift source file across both Xcode projects (EclipseAppleTV and
# EclipseiPhone) carries the Moxie LLC proprietary copyright header. The operation is
# idempotent: files that already contain the copyright line are left untouched, so the
# script is safe to re-run (e.g. after adding new files that bypassed the Xcode template).
#
# Behavior per file:
#   - Already has "Copyright © 2026 Moxie LLC"  -> skip.
#   - Has a legacy "Created by ..." header line -> replace that line with the copyright line.
#   - Otherwise (no header at all)              -> prepend a standard header block.
#
# Usage:
#   Scripts/add_copyright_headers.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

COPYRIGHT_LINE="//  Copyright © 2026 Moxie LLC. All rights reserved."
COPYRIGHT_MARKER="Copyright © 2026 Moxie LLC"

updated=0
skipped=0

while IFS= read -r -d '' file; do
    if grep -q "$COPYRIGHT_MARKER" "$file"; then
        skipped=$((skipped + 1))
        continue
    fi

    if grep -q "Created by" "$file"; then
        # Replace the legacy author line in-place, preserving the surrounding header block.
        tmp="$(mktemp)"
        awk -v repl="$COPYRIGHT_LINE" '
            !done && /\/\/[[:space:]]*Created by/ { print repl; done=1; next }
            { print }
        ' "$file" > "$tmp"
        mv "$tmp" "$file"
        updated=$((updated + 1))
        continue
    fi

    # No header present: prepend a standard block using the file name.
    base="$(basename "$file")"
    tmp="$(mktemp)"
    {
        printf '//\n'
        printf '//  %s\n' "$base"
        printf '//  Eclipse\n'
        printf '//\n'
        printf '%s\n' "$COPYRIGHT_LINE"
        printf '//\n'
        printf '\n'
        cat "$file"
    } > "$tmp"
    mv "$tmp" "$file"
    updated=$((updated + 1))
done < <(find "$REPO_ROOT/EclipseAppleTV" "$REPO_ROOT/EclipseiPhone" -name '*.swift' -print0)

echo "Copyright headers: $updated updated, $skipped already present."
