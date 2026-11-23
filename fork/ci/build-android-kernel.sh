#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build and publish the Android (LineageOS 24) kernel bundle the iOS runtime
# embeds, following kernel/mainline-6.18/README.md ("Standalone build and
# publication"). Upstream publishes no kernel bundle, so the cloud build makes
# its own from the same pinned source and patch series.
#
# The bundle is published under the accepted release ID, so its directory is
# the one kernel/mainline-6.18/artifacts/accepted-android-4k.env names. Fields
# that depend on the replay (the "release" string carries the replay commit's
# abbreviated ID) can differ from upstream's; when they do, this script
# rewrites the descriptor in the runner's checkout only, from the bundle's own
# manifest, and says so. The fork's own kernel topics change the final tree;
# that is accepted when the tree is the one this commit's series produce. That is allowed for the Release (development)
# configuration, which is what the cloud build archives. The AppStore and
# TestFlight configurations would refuse it, by design.

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

DESCRIPTOR=kernel/mainline-6.18/artifacts/accepted-android-4k.env
# shellcheck disable=SC1090
. "$DESCRIPTOR"
RELEASE_ID=$UML_KERNEL_ARTIFACT_RELEASE_ID
BUNDLE_DIR=.build/kernel/artifacts/$UML_KERNEL_ARTIFACT_DIRECTORY_NAME

sync_descriptor()
{
	step "Check the accepted descriptor against the bundle"
	python3 - "$BUNDLE_DIR" "$DESCRIPTOR" <<'PY'
import sys
from pathlib import Path
bundle, descriptor = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, "kernel/common/artifacts")
from kernel_artifact import load_manifest  # kernel-artifact.json, validated
m = load_manifest(bundle)
want = {
    "SCHEMA": m["schema_version"], "RELEASE_ID": m["release_id"],
    "DIRECTORY_NAME": m["directory_name"], "FAMILY": m["family"],
    "SLICE": m["slice"], "RELEASE": m["release"], "PAGE_SIZE": m["page_size"],
    "FINAL_TREE": m["source"]["final_tree"], "ABI_VERSION": m["abi"]["version"],
    "ABI_FINGERPRINT": m["abi"]["fingerprint"],
}
have = {}
for line in descriptor.read_text().splitlines():
    if line.startswith("UML_KERNEL_ARTIFACT_"):
        k, v = line.split("=", 1)
        have[k[len("UML_KERNEL_ARTIFACT_"):]] = v.strip("'")
diff = {k: (have.get(k), str(v)) for k, v in want.items() if have.get(k) != str(v)}
if not diff:
    print("[andariummax-ci] descriptor matches the bundle")
    sys.exit(0)
for k, (old, new) in diff.items():
    print(f"::warning::kernel descriptor {k}: upstream {old!r}, cloud bundle {new!r}")
# A tree other than the accepted one is allowed only when it is the tree this
# commit's series produce (kernel/mainline-6.18/patches/metadata.env): the
# fork's own kernel change, pending upstream acceptance. The bridge ABI must
# match, since the runtime is built against it.
series_tree = None
for line in Path("kernel/mainline-6.18/patches/metadata.env").read_text().splitlines():
    if line.startswith("UML_KERNEL_FINAL_TREE="):
        series_tree = line.split("=", 1)[1].strip("'")
if "FINAL_TREE" in diff and m["source"]["final_tree"] != series_tree:
    sys.exit("the rebuilt kernel's source tree is neither the accepted one nor this commit's series: stop")
if "ABI_VERSION" in diff or "ABI_FINGERPRINT" in diff:
    sys.exit("the rebuilt kernel's bridge ABI differs from the accepted one: stop")
lines = ["# SPDX-License-Identifier: GPL-2.0-or-later",
         "# Rewritten by fork/ci/build-android-kernel.sh in the runner only."]
for k, v in want.items():
    v = str(v)
    lines.append(f"UML_KERNEL_ARTIFACT_{k}={v}" if v.isdigit() else f"UML_KERNEL_ARTIFACT_{k}='{v}'")
descriptor.write_text("\n".join(lines) + "\n")
print("[andariummax-ci] descriptor rewritten for this runner (development build only)")
PY
}

step "Host tools"
ensure_host_tools

if [ -d "$BUNDLE_DIR" ]; then
	note "kernel bundle restored from cache: $BUNDLE_DIR"
	sync_descriptor
	exit 0
fi

[ -f .build/dependencies/kernel-host-tools/lib/libelf.a ] ||
	fail "kernel host tools missing: the dependencies job must run first"

step "Case-sensitive volume for the Linux source"
SCRATCH=${RUNNER_TEMP:-$ROOT_DIR/.build/ci}
VOLUME=$SCRATCH/uml-kernel-volume
if [ ! -d "$VOLUME/linux" ] && ! mount | grep -q " on $VOLUME "; then
	mkdir -p "$VOLUME"
	hdiutil create -size 40g -type SPARSE -fs 'Case-sensitive APFS' \
		-volname uml-kernel "$SCRATCH/uml-kernel.sparseimage" >/dev/null
	hdiutil attach -mountpoint "$VOLUME" "$SCRATCH/uml-kernel.sparseimage" >/dev/null
fi
printf 'UML_KERNEL_SOURCE_DIR=%s/linux\n' "$VOLUME" \
	>kernel/mainline-6.18/source-location.conf
disk_report

step "Prepare the pinned Linux source (arm64 slice)"
kernel/mainline-6.18/scripts/prepare-source.sh --slice arm64

LLVM_BIN=$(brew --prefix llvm)/bin
export UML_KERNEL_CC="$LLVM_BIN/clang"
export UML_KERNEL_LD="$(brew --prefix lld)/bin/ld.lld"
export UML_KERNEL_JOBS="$JOBS"
note "kernel compiler: $("$UML_KERNEL_CC" --version | head -1)"

step "Build the Android kernel"
kernel/mainline-6.18/build/build-kernel.sh --product android \
	--build "$VOLUME/build-android" --jobs "$JOBS"
disk_report

step "Publish the Android kernel bundle ($RELEASE_ID)"
mkdir -p .build/kernel/artifacts
python3 kernel/mainline-6.18/build/publish-artifact.py \
	--source "$VOLUME/linux" --build "$VOLUME/build-android" \
	--product android --slice arm64 \
	--output-root "$ROOT_DIR/.build/kernel/artifacts" --release-id "$RELEASE_ID" \
	--objcopy "$LLVM_BIN/llvm-objcopy"
[ -d "$BUNDLE_DIR" ] || fail "publisher did not create $BUNDLE_DIR"
sync_descriptor
note "kernel bundle ready: $BUNDLE_DIR"
