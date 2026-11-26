#!/bin/bash
# Runs the audit walk-through in a simulator and exports its pictures.
#
#   Scripts/run_ui_walkthrough.sh iphone|tv <simulator-udid> dark|light <out-dir> [derived-data]
#
# Use a fresh simulator that is not signed in to iCloud. The simulator runs
# headless (Simulator.app need not be open), so nothing takes the screen.
# Pictures land in <out-dir>/<platform>-<appearance>/ as PNGs named
# "NNNN area - step.png"; findings and element dumps are .txt files there.
set -uo pipefail

platform="${1:?iphone or tv}"
udid="${2:?simulator udid}"
appearance="${3:?dark or light}"
out="${4:?output folder}"
derived="${5:-$out/dd-$platform}"
root="$(cd "$(dirname "$0")/.." && pwd)"

case "$platform" in
  iphone) project="$root/EclipseiPhone/EclipseiPhone.xcodeproj"; scheme=EclipseiPhone
          only="EclipseiPhoneUITests/EclipseWalkthroughTests" ;;
  tv)     project="$root/EclipseAppleTV/EclipseAppleTV.xcodeproj"; scheme=EclipseAppleTV
          only="EclipseAppleTVUITests/EclipseTVWalkthroughTests" ;;
  *) echo "platform must be iphone or tv" >&2; exit 1 ;;
esac

name="$(xcrun simctl list devices | grep "$udid" | sed 's/ (.*//; s/^ *//' | tr ' ' '-')"
result="$out/$name-$appearance.xcresult"
pictures="$out/$name-$appearance"
rm -rf "$result" "$pictures"
mkdir -p "$pictures"

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
# Start from a fresh install every run (no shows, no remembered modes).
case "$platform" in
  iphone) xcrun simctl uninstall "$udid" com.mobleypro.eclipse.EclipseiPhone 2>/dev/null || true ;;
  tv)     xcrun simctl uninstall "$udid" com.mobleypro.eclipse.EclipseTV 2>/dev/null || true ;;
esac
xcrun simctl ui "$udid" appearance "$appearance" 2>/dev/null || true
if [ "$platform" = iphone ]; then
  for service in camera microphone photos; do
    xcrun simctl privacy "$udid" grant "$service" com.mobleypro.eclipse.EclipseiPhone 2>/dev/null || true
  done
fi

xcodebuild test \
  -project "$project" -scheme "$scheme" \
  -destination "id=$udid" \
  -derivedDataPath "$derived" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled NO \
  -only-testing:"$only" \
  -resultBundlePath "$result" \
  > "$pictures/xcodebuild.log" 2>&1
echo "xcodebuild exit $? (the walk-through logs problems instead of failing)"

xcrun xcresulttool export attachments --path "$result" --output-path "$pictures" >/dev/null
# Name each exported file after its attachment.
python3 - "$pictures" <<'PY'
import json, os, re, sys
folder = sys.argv[1]
manifest = os.path.join(folder, "manifest.json")
if os.path.exists(manifest):
    for test in json.load(open(manifest)):
        for item in test.get("attachments", []):
            src = os.path.join(folder, item["exportedFileName"])
            ext = os.path.splitext(src)[1]
            safe = item.get("suggestedHumanReadableName", item["exportedFileName"]).replace("/", "-")
            base = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", os.path.splitext(safe)[0])
            if os.path.exists(src):
                os.replace(src, os.path.join(folder, base[:120] + ext))
PY
echo "Pictures: $(find "$pictures" -name '*.png' | wc -l | tr -d ' ') in $pictures"
