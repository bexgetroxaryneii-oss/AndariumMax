#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Compile the iOS device Android runtime, package its frameworks, stage the
# Android system, archive Andarium (Release, the development configuration that
# keeps the JIT row) without signing, and wrap it as an unsigned IPA that
# SideStore signs on the phone. Steps follow Andarium/README.md ("Build").
#
# Environment:
#   SYSTEM_MODE   release | staged | none
#                 release: SYSTEM_ARCHIVE holds an Android release directory
#                          (android/lineage-24/README.md, "Release installation")
#                 staged:  SYSTEM_ARCHIVE holds an already staged
#                          andarium-system folder
#                 none:    no Android system; the IPA proves the build only and
#                          cannot boot Android (its name says so)
#   SYSTEM_ARCHIVE  path to a .zip, .tar, .tar.gz or .tar.zst (release/staged)
#   IPA_LABEL     short text added to the IPA name (branch, run number)

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

SYSTEM_MODE=${SYSTEM_MODE:-none}
IPA_LABEL=${IPA_LABEL:-local}
OUT=.build/ci
LOGS=$OUT/logs
mkdir -p "$LOGS"

summary()
{
	[ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY"
	return 0
}

logged()
{
	# logged NAME command...: live output in the job log, full copy in $LOGS.
	local name=$1
	shift
	if ! "$@" 2>&1 | tee "$LOGS/$name.log"; then
		summary "### ❌ $name failed"
		summary '```'
		grep -E 'error:|Error |FAILED|fatal' "$LOGS/$name.log" | head -40 >>"${GITHUB_STEP_SUMMARY:-/dev/null}" || true
		summary '```'
		fail "$name failed (full log: $LOGS/$name.log in the build-logs artifact)"
	fi
}

extract()
{
	local archive=$1 dest=$2
	mkdir -p "$dest"
	case "$archive" in
	*.zip) ditto -x -k "$archive" "$dest" ;;
	*.tar.zst) zstd -dc "$archive" | tar -xf - -C "$dest" ;;
	*.tar.gz | *.tgz) tar -xzf "$archive" -C "$dest" ;;
	*.tar) tar -xf "$archive" -C "$dest" ;;
	*) fail "unsupported system archive: $archive" ;;
	esac
}

step "Host tools"
ensure_host_tools
ensure_metal_toolchain
disk_report

step "Kernel bundle and descriptor"
"$CI_DIR/build-android-kernel.sh"

step "Sources the framework packaging builds (GPT fdisk, zstd)"
dependencies/prepare.sh --product ios-storage
dependencies/prepare.sh --product ios-compression

step "Configure the iOS device Android runtime"
logged cmake-configure cmake --preset kernarium-ios-device-android \
	-DPython3_EXECUTABLE="$(command -v python3)"
grep -E 'UML_AOT' .build/kernarium-runtime-ios-device-android-4k/CMakeCache.txt \
	| sed 's/^/[andariummax-ci] /' || true

step "Build the runtime"
logged cmake-build cmake --build --preset kernarium-ios-device-android -j "$JOBS"
disk_report

step "Package the iOS frameworks (Android runtime only)"
logged package-frameworks Kernarium/scripts/package-ios-frameworks.sh --runtimes android

step "Android system ($SYSTEM_MODE)"
rm -rf .build/andarium-system
case "$SYSTEM_MODE" in
release)
	[ -f "${SYSTEM_ARCHIVE:-}" ] || fail "SYSTEM_ARCHIVE is not a file"
	extract "$SYSTEM_ARCHIVE" "$OUT/system-release"
	release_dir=$(dirname "$(find "$OUT/system-release" -name 'release-manifest*.json' | head -1)")
	[ -d "$release_dir" ] || fail "no release manifest in the system archive"
	logged install-release python3 android/lineage-24/tools/install-release.py --source "$release_dir"
	logged stage-system python3 Andarium/scripts/stage-system-image.py
	BOOTABLE=1
	;;
staged)
	[ -f "${SYSTEM_ARCHIVE:-}" ] || fail "SYSTEM_ARCHIVE is not a file"
	extract "$SYSTEM_ARCHIVE" "$OUT/system-staged"
	staged=$(find "$OUT/system-staged" -type d -name andarium-system | head -1)
	[ -n "$staged" ] || fail "the archive has no andarium-system folder"
	mkdir -p .build
	ditto "$staged" .build/andarium-system
	note "staged system copied as is; it must match this runtime's kernel ABI"
	BOOTABLE=1
	;;
none)
	mkdir -p .build/andarium-system
	cat >.build/andarium-system/NOT_BOOTABLE.txt <<'EOF'
This build carries no Android system image. It proves that the AndariumMax
source compiles, links and packages; it cannot boot Android.
EOF
	BOOTABLE=0
	summary "> ⚠️ No Android system image was supplied: this IPA cannot boot Android."
	;;
*) fail "SYSTEM_MODE must be release, staged or none" ;;
esac
du -sh .build/andarium-system | sed 's/^/[andariummax-ci] system: /'

step "Archive Andarium (Release, unsigned)"
ARCHIVE=$OUT/Andarium.xcarchive
rm -rf "$ARCHIVE"
logged xcodebuild-archive xcodebuild archive \
	-project Andarium/Andarium.xcodeproj -scheme Andarium \
	-configuration Release -destination 'generic/platform=iOS' \
	-archivePath "$ARCHIVE" \
	CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
	CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=

step "Wrap the IPA"
APP=$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -1)
[ -d "$APP" ] || fail "the archive holds no application"
PAYLOAD=$OUT/ipa/Payload
rm -rf "$OUT/ipa"
mkdir -p "$PAYLOAD"
ditto "$APP" "$PAYLOAD/$(basename "$APP")"
APP=$PAYLOAD/$(basename "$APP")
# Ad-hoc signatures only carry the entitlements for SideStore to read; SideStore
# re-signs everything with the user's own certificate on the phone.
find "$APP/Frameworks" -maxdepth 1 -name '*.framework' -print0 2>/dev/null |
	xargs -0 -I{} codesign --force --sign - --timestamp=none {}
codesign --force --sign - --timestamp=none \
	--entitlements Andarium/Config/Andarium.entitlements "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | sed 's/^/[andariummax-ci] /' || true

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist" 2>/dev/null || echo 0)
if [ "$BOOTABLE" = 1 ]; then
	IPA_NAME="AndariumMax-$VERSION-$IPA_LABEL-unsigned.ipa"
else
	IPA_NAME="AndariumMax-$VERSION-$IPA_LABEL-compile-check-NO-ANDROID.ipa"
fi
(cd "$OUT/ipa" && zip -qry -1 "../$IPA_NAME" Payload)
ls -lh "$OUT/$IPA_NAME" | sed 's/^/[andariummax-ci] /'
summary "### ✅ $IPA_NAME"
summary "Size: $(du -h "$OUT/$IPA_NAME" | cut -f1). Unsigned: sign and install it with SideStore."
[ -n "${GITHUB_OUTPUT:-}" ] && printf 'ipa=%s\n' "$OUT/$IPA_NAME" >>"$GITHUB_OUTPUT"
note "done: $OUT/$IPA_NAME"
