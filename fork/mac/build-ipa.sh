#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Builds a sideloadable development IPA of Andarium on an Apple silicon Mac,
# by the steps Andarium/README.md documents. It prepares nothing itself: it
# checks each prerequisite, says exactly what is missing, and stops.
#
# NOT YET RUN ON A MAC. Written from upstream's documentation.
#
# Usage: fork/mac/build-ipa.sh [--output DIR]
set -euo pipefail

root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
output="$root/.build/andarium-max"
if [[ "${1:-}" == "--output" && -n "${2:-}" ]]; then
    output="$2"
fi
log="$output/build.log"
mkdir -p "$output"

step() { printf '\n[%s] %s\n' "$1" "$2"; }
fail() { printf '\nSTOPPED: %s\n' "$1" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "$1 is not installed. $2"; }

step 1/7 "Checking the Mac"
[[ "$(uname -s)" == "Darwin" ]] || fail "this script needs macOS; an iOS app cannot be built elsewhere."
[[ "$(uname -m)" == "arm64" ]] || fail "an Apple silicon Mac is required."
need xcodebuild "Install Xcode 27 from the App Store."
need cmake "Install CMake 3.27 or newer (brew install cmake)."
need ninja "Install Ninja (brew install ninja)."
need python3 "Install Python 3.11 or newer (brew install python)."
xcode_major="$(xcodebuild -version | awk 'NR==1 {split($2, v, "."); print v[1]}')"
[[ "$xcode_major" -ge 27 ]] || fail "Xcode 27 or newer is required (found $xcode_major)."
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' ||
    fail "python3 on PATH is older than 3.11."
echo "  Xcode $xcode_major, $(cmake --version | head -1), Python $(python3 -V | cut -d' ' -f2)"

step 2/7 "Checking signing"
signing="$root/GuestHost/Config/Signing.local.xcconfig"
[[ -f "$signing" ]] || fail "no $signing.
  Run:  cp GuestHost/Config/Signing.local.xcconfig.example GuestHost/Config/Signing.local.xcconfig
  then put your 10-character Team ID in it."
grep -q 'ABCDE12345' "$signing" && fail "Signing.local.xcconfig still holds the example Team ID."

step 3/7 "Checking prebuilt inputs"
[[ -d "$root/.build/dependencies" ]] ||
    fail "the dependency prefixes are not built. See dependencies/README.md
  (products apple-gpu-vulkan-experiment, ios-network, ios-storage, ios-compression)."
[[ -d "$root/.build/android/releases" ]] ||
    fail "no Android release is installed. Download upstream's prebuilt release and run
  android/lineage-24/tools/install-release.py --source /absolute/path/to/release"

step 4/7 "Building the Android runtime for the iOS device"
# CMake reads the presets from the directory it runs in.
(cd "$root" && cmake --preset kernarium-ios-device-android) 2>&1 | tee "$log"
(cd "$root" && cmake --build --preset kernarium-ios-device-android) 2>&1 | tee -a "$log" ||
    fail "the runtime build failed; see $log"

step 5/7 "Packaging frameworks and staging the system image"
(cd "$root" && Kernarium/scripts/package-ios-frameworks.sh --runtimes android) 2>&1 | tee -a "$log"
(cd "$root" && Andarium/scripts/stage-system-image.py) 2>&1 | tee -a "$log"

step 6/7 "Archiving Andarium (Release: the development build with the JIT row)"
archive="$output/Andarium.xcarchive"
xcodebuild archive \
    -project "$root/Andarium/Andarium.xcodeproj" -scheme Andarium \
    -configuration Release -destination 'generic/platform=iOS' \
    -archivePath "$archive" -allowProvisioningUpdates 2>&1 | tee -a "$log" | grep -E '^(\*\*|error|warning: unable)|Archive' || true
[[ -d "$archive" ]] || fail "the archive was not made; see $log"

step 7/7 "Exporting the IPA"
options="$output/ExportOptions.plist"
cat >"$options" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>debugging</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$output/ipa" \
    -exportOptionsPlist "$options" -allowProvisioningUpdates 2>&1 | tee -a "$log" | tail -5
ipa="$(find "$output/ipa" -name '*.ipa' -print -quit)"
[[ -n "$ipa" ]] || fail "no IPA was exported; see $log"

printf '\nDONE: %s\nLog:  %s\n' "$ipa" "$log"
echo "Entitlements in the signed app:"
codesign -d --entitlements - "$archive/Products/Applications/Andarium.app" 2>/dev/null |
    grep -E 'increased-memory-limit|extended-virtual-addressing|get-task-allow' || true
