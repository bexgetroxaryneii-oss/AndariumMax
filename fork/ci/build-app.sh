#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Compile the iOS device Android runtime, package its frameworks, stage the
# Android system, archive Andarium (Release, the development configuration that
# keeps the JIT row) without signing, and wrap it as an unsigned IPA that
# SideStore signs on the phone. Steps follow Andarium/README.md ("Build").
#
# Environment:
#   SYSTEM_MODE   upstream | release | staged | none
#                 upstream: download the accepted release that upstream
#                          publishes (SYSTEM_URL, default below) and install it
#                 release: SYSTEM_ARCHIVE holds an Android release directory
#                          (android/lineage-24/README.md, "Release installation")
#                 staged:  SYSTEM_ARCHIVE holds an already staged
#                          andarium-system folder
#                 none:    no Android system; the IPA proves the build only and
#                          cannot boot Android (its name says so)
#   SYSTEM_ARCHIVE  path to a .zip, .tar, .tar.gz or .tar.zst (release/staged)
#   IPA_LABEL     short text added to the IPA name (branch, run number)

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

SYSTEM_MODE=${SYSTEM_MODE:-upstream}
# Upstream's public release asset for the accepted release (accepted-release.env).
SYSTEM_URL=${SYSTEM_URL:-https://github.com/imxieyi/Kernarium/releases/download/1.0b15-release/lineage24-mainline6.18-4k-20261115-los24-r28.tar.gz}
# Build the ahead-of-time code from the installed release (tools/aot); 0 skips it.
BUILD_AOT=${BUILD_AOT:-1}
AOT_DIR=
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

sdk_at_least()
{
	# sdk_at_least VERSION: the selected iOS SDK is VERSION or newer.
	python3 -c 'import sys; v = lambda s: [int(p) for p in s.split(".")]; sys.exit(0 if v(sys.argv[2]) >= v(sys.argv[1]) else 1)' \
		"$1" "$(xcrun --sdk iphoneos --show-sdk-version)"
}

step "Xcode"
ls -d /Applications/Xcode*.app 2>/dev/null | sed 's/^/[andariummax-ci] installed: /'
# The app uses API of the iOS 27.2 SDK; take the newest Xcode when the
# default is older.
if ! sdk_at_least 27.2; then
	newest=""
	best="0"
	for app in /Applications/Xcode*.app; do
		sdk=$(DEVELOPER_DIR="$app/Contents/Developer" xcrun --sdk iphoneos --show-sdk-version 2>/dev/null) || continue
		note "$app: iOS SDK $sdk"
		if python3 -c 'import sys; v = lambda s: [int(p) for p in s.split(".")]; sys.exit(0 if v(sys.argv[1]) > v(sys.argv[2]) else 1)' "$sdk" "$best"; then
			best=$sdk
			newest=$app
		fi
	done
	if [ -n "$newest" ]; then
		export DEVELOPER_DIR="$newest/Contents/Developer"
		note "selected $newest"
	fi
fi
note "iOS SDK $(xcrun --sdk iphoneos --show-sdk-version) ($(xcodebuild -version | head -1))"

erofs_with_zstd()
{
	# The AOT build reads the release's system partition, which is
	# Zstandard-compressed; Homebrew's erofs-utils has no zstd
	# (tools/aot/README.md). Build one with it, once per runner.
	local tool=$ROOT_DIR/.build/ci-tools/erofs/bin/fsck.erofs
	if [ ! -x "$tool" ]; then
		local work=$ROOT_DIR/.build/ci-tools/erofs-src
		rm -rf "$work"
		git clone -q --depth 1 --branch v1.9.4 \
			https://git.kernel.org/pub/scm/linux/kernel/git/xiang/erofs-utils.git "$work" >&2 || return 1
		(
			cd "$work" &&
			./autogen.sh &&
			PKG_CONFIG_PATH="$(brew --prefix zstd)/lib/pkgconfig:$(brew --prefix lz4)/lib/pkgconfig" \
				./configure --prefix="$ROOT_DIR/.build/ci-tools/erofs" \
				--with-libzstd --disable-fuse --without-uuid --without-selinux &&
			make -j "$JOBS" &&
			make install
		) >"$LOGS/erofs-utils-build.log" 2>&1 || {
			tail -30 "$LOGS/erofs-utils-build.log" >&2
			return 1
		}
	fi
	if ! "$tool" --help 2>&1 | grep -qi zstd; then
		printf 'fsck.erofs at %s lists no zstd\n' "$tool" >&2
		return 1
	fi
	printf '%s\n' "$tool"
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

step "Android system ($SYSTEM_MODE)"
rm -rf .build/andarium-system
install_release_dir()
{
	local release_dir
	release_dir=$(dirname "$(find "$1" -name release-manifest.json | head -1)")
	[ -f "$release_dir/release-manifest.json" ] || fail "no release-manifest.json in the system archive"
	release_dir=$(CDPATH= cd -- "$release_dir" && pwd -P)
	logged install-release python3 android/lineage-24/tools/install-release.py --source "$release_dir"
}

case "$SYSTEM_MODE" in
upstream)
	note "downloading $SYSTEM_URL"
	mkdir -p "$OUT/system-download"
	curl -fL --retry 3 --progress-bar -o "$OUT/system-download/release.tar.gz" "$SYSTEM_URL"
	extract "$OUT/system-download/release.tar.gz" "$OUT/system-release"
	rm -f "$OUT/system-download/release.tar.gz"
	install_release_dir "$OUT/system-release"
	rm -rf "$OUT/system-release"
	BOOTABLE=1
	;;
release)
	[ -f "${SYSTEM_ARCHIVE:-}" ] || fail "SYSTEM_ARCHIVE is not a file"
	extract "$SYSTEM_ARCHIVE" "$OUT/system-release"
	install_release_dir "$OUT/system-release"
	rm -rf "$OUT/system-release"
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
*) fail "SYSTEM_MODE must be upstream, release, staged or none" ;;
esac
if [ "$SYSTEM_MODE" = upstream ] || [ "$SYSTEM_MODE" = release ]; then
	logged stage-system python3 Andarium/scripts/stage-system-image.py
fi
disk_report
du -sh .build/andarium-system | sed 's/^/[andariummax-ci] system: /'

step "Ahead-of-time code from the installed release"
if [ "$BUILD_AOT" = 1 ] && [ -d .build/android/releases ]; then
	installed=$(find .build/android/releases -mindepth 1 -maxdepth 1 -type d | head -1)
	FSCK_EROFS=$(erofs_with_zstd || true)
	if [ -n "$installed" ] && [ -n "$FSCK_EROFS" ]; then
		AOT_DIR=$OUT/aot-artifact
		rm -rf "$AOT_DIR"
		if python3 tools/aot/release_artifact.py build --release "$installed" \
			--fsck-erofs "$FSCK_EROFS" --out "$AOT_DIR" --jobs "$JOBS" 2>&1 | tee "$LOGS/aot-build.log"; then
			note "AOT artifact built: $AOT_DIR"
			AOT_DIR=$(CDPATH= cd -- "$AOT_DIR" && pwd -P)
		else
			printf '::warning::AOT build failed; building without ahead-of-time code (see aot-build.log)\n'
			AOT_DIR=""
		fi
	else
		printf '::warning::no installed release or fsck.erofs; building without ahead-of-time code\n'
	fi
else
	note "AOT skipped (BUILD_AOT=$BUILD_AOT, mode $SYSTEM_MODE)"
fi

step "Configure the iOS device Android runtime"
AOT_ARGS=()
[ -n "$AOT_DIR" ] && AOT_ARGS=(-DUML_AOT_ARTIFACT="$AOT_DIR")
logged cmake-configure cmake --preset kernarium-ios-device-android \
	-DPython3_EXECUTABLE="$(command -v python3)" ${AOT_ARGS[@]+"${AOT_ARGS[@]}"}
grep -E 'UML_AOT' .build/kernarium-runtime-ios-device-android-4k/CMakeCache.txt \
	| sed 's/^/[andariummax-ci] /' || true

step "Build the runtime"
logged cmake-build cmake --build --preset kernarium-ios-device-android -j "$JOBS"
disk_report

step "Package the iOS frameworks (Android runtime only)"
logged package-frameworks Kernarium/scripts/package-ios-frameworks.sh --runtimes android

if ! sdk_at_least 27.2; then
	# iOS 27.2 states a motion permission; an older SDK has no such API, and a
	# device on an older iOS never reaches that branch. Runner checkout only.
	printf '::warning::iOS SDK older than 27.2: the motion-permission read is compiled out of this build\n'
	python3 - <<'PY'
from pathlib import Path
p = Path("Andarium/Andarium/Live/MotionSensors.swift")
s = p.read_text()
old = "if #available(iOS 27.2, *) { return CMMotionManager.authorizationStatus }"
if old not in s:
    raise SystemExit("MotionSensors.swift changed: update fork/ci/build-app.sh")
p.write_text(s.replace(old, "// iOS 27.2 SDK missing on the build host"))
PY
fi

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
