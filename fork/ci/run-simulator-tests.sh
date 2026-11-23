#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Run Andarium's hosted model tests in the iOS Simulator: build the Simulator
# dependency prefixes (Mesa's software renderer with LLVM, the network
# closure), the Simulator Android runtime and its frameworks, stage the
# Android system, then `xcodebuild test` with the suites in TEST_SUITES
# (default: the suites of AndariumTests/JitTests.swift). docs/testing.md and Andarium/README.md own the steps.
#
# Environment:
#   TEST_SUITES   space-separated AndariumTests suites (default JitTests)
#   SYSTEM_URL    the Android release to stage (default: upstream's accepted)

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

TEST_SUITES=${TEST_SUITES:-JitPreferenceTests JitAnswerTests JitStatusTests JitStatusLaunchTests JitLaunchRequestTests JitAtLaunchTests}
SYSTEM_URL=${SYSTEM_URL:-https://github.com/imxieyi/Kernarium/releases/download/1.0b15-release/lineage24-mainline6.18-4k-20261115-los24-r28.tar.gz}
OUT=.build/ci
LOGS=$OUT/logs
mkdir -p "$LOGS"

retry_prepare()
{
	dependencies/prepare.sh "$@" ||
		{ note "retrying prepare.sh $* in 60 s"; sleep 60; dependencies/prepare.sh "$@"; }
}

step "Xcode"
select_xcode_with_sdk 27.2

step "Host tools"
ensure_host_tools
ensure_metal_toolchain
disk_report

NETWORK_PREFIX=.build/dependencies/ios-simulator-arm64/network
GPU_PREFIX=.build/dependencies/apple-gpu-vulkan-experiment/ios-simulator-arm64

step "Simulator network prefix"
if [ -d "$NETWORK_PREFIX" ]; then
	dependencies/build-ios-network.sh --platform ios-simulator --prefix "$NETWORK_PREFIX" --verify-only
else
	retry_prepare --product ios-network
	dependencies/build-ios-network.sh --platform ios-simulator --prefix "$NETWORK_PREFIX" \
		--work-root .build/dependency-build/ios-network-simulator --jobs "$JOBS"
fi

step "Simulator GPU prefix (Mesa llvmpipe with LLVM)"
if [ -d "$GPU_PREFIX" ]; then
	dependencies/build-apple-gpu.sh --platform ios-simulator --prefix "$GPU_PREFIX" --verify-only
else
	retry_prepare --product apple-gpu-vulkan-experiment
	retry_prepare --archive-manifest dependencies/llvm/archives.tsv
	dependencies/build-apple-gpu.sh --platform ios-simulator --prefix "$GPU_PREFIX" \
		--work-root .build/dependency-build/apple-gpu-simulator --jobs "$JOBS"
fi
rm -rf .build/dependency-build
disk_report

step "Kernel bundle and descriptor"
"$CI_DIR/build-android-kernel.sh"

step "Sources the framework packaging builds (GPT fdisk, zstd)"
retry_prepare --product ios-storage
retry_prepare --product ios-compression

step "Android system"
if [ ! -d .build/andarium-system ]; then
	mkdir -p "$OUT/system-release"
	curl -fL --retry 3 --progress-bar -o "$OUT/release.tar.gz" "$SYSTEM_URL"
	tar -xzf "$OUT/release.tar.gz" -C "$OUT/system-release"
	rm -f "$OUT/release.tar.gz"
	release_dir=$(dirname "$(find "$OUT/system-release" -name release-manifest.json | head -1)")
	release_dir=$(CDPATH= cd -- "$release_dir" && pwd -P)
	python3 android/lineage-24/tools/install-release.py --source "$release_dir"
	rm -rf "$OUT/system-release"
	python3 Andarium/scripts/stage-system-image.py
fi

step "Simulator Android runtime"
cmake --preset kernarium-ios-simulator-android -DPython3_EXECUTABLE="$(command -v python3)" \
	2>&1 | tee "$LOGS/sim-cmake-configure.log"
cmake --build --preset kernarium-ios-simulator-android -j "$JOBS" 2>&1 | tee "$LOGS/sim-cmake-build.log"
Kernarium/scripts/package-ios-frameworks.sh --sdk simulator --runtimes android \
	2>&1 | tee "$LOGS/sim-package-frameworks.log"

step "Simulator"
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime, entries in sorted(devices.items(), reverse=True):
    if "iOS" not in runtime:
        continue
    for device in entries:
        if device["name"].startswith("iPhone"):
            print(device["udid"])
            raise SystemExit
')
[ -n "$UDID" ] || fail "no available iPhone simulator"
note "simulator $UDID"

step "xcodebuild test: $TEST_SUITES"
ONLY=()
for suite in $TEST_SUITES; do
	ONLY+=("-only-testing:AndariumTests/$suite")
done
set +e
xcodebuild test -project Andarium/Andarium.xcodeproj -scheme Andarium \
	-destination "id=$UDID" -derivedDataPath "$OUT/DerivedData-simulator" \
	-resultBundlePath "$OUT/simulator-tests.xcresult" "${ONLY[@]}" \
	2>&1 | tee "$LOGS/simulator-tests.log"
status=${PIPESTATUS[0]}
set -e
grep -E "Test run|✔|✘|Executed|error:" "$LOGS/simulator-tests.log" | tail -80 || true
# Swift Testing reports "Test run with N tests ... passed"; a filter that
# matches no suite runs nothing and still succeeds, which is a failure here.
ran=$(grep -Eo 'Test run with [0-9]+ test' "$LOGS/simulator-tests.log" | grep -Eo '[0-9]+' | tail -1 || true)
ran=${ran:-0}
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### Simulator tests: $([ "$status" = 0 ] && [ "$ran" -gt 0 ] && echo "passed ($ran tests)" || echo FAILED)"
		echo '```'
		grep -E "Test run|✘|error:" "$LOGS/simulator-tests.log" | tail -40 || true
		echo '```'
	} >>"$GITHUB_STEP_SUMMARY"
fi
[ "$status" = 0 ] || fail "simulator tests failed (exit $status)"
[ "$ran" -gt 0 ] || fail "no test ran: check TEST_SUITES ($TEST_SUITES)"
note "simulator tests passed: $ran tests"
