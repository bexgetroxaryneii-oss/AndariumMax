#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build the private dependency prefixes the iOS device Android runtime and its
# packaging need, with the repository's own scripts (dependencies/README.md):
#   ios-network                 -> .build/dependencies/ios-device-arm64/network
#   apple-gpu-vulkan-experiment -> .build/dependencies/apple-gpu-vulkan-experiment/ios-device-arm64
#   ios-storage, ios-compression (sources only; package-ios-frameworks.sh builds them)
#   kernel-host-tools           -> .build/dependencies/kernel-host-tools (pahole, libelf)
# A prefix that already exists (restored from the Actions cache) is verified,
# not rebuilt: the scripts never replace an installed prefix.

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

step "Host tools"
ensure_host_tools
ensure_metal_toolchain
disk_report

prepare()
{
	step "Prepare sources: $*"
	dependencies/prepare.sh "$@"
}

prepare --product ios-network
prepare --product ios-storage
prepare --product ios-compression
prepare --product apple-gpu-vulkan-experiment
prepare --product kernel-host-tools
prepare --archive-manifest dependencies/kernel-host-tools/archives.tsv
disk_report

NETWORK_PREFIX=.build/dependencies/ios-device-arm64/network
GPU_PREFIX=.build/dependencies/apple-gpu-vulkan-experiment/ios-device-arm64
HOST_TOOLS_PREFIX=.build/dependencies/kernel-host-tools

step "iOS network prefix (GLib, libslirp)"
if [ -d "$NETWORK_PREFIX" ]; then
	dependencies/build-ios-network.sh --platform ios --prefix "$NETWORK_PREFIX" --verify-only
else
	dependencies/build-ios-network.sh --platform ios --prefix "$NETWORK_PREFIX" \
		--work-root .build/dependency-build/ios-network-device --jobs "$JOBS"
fi
disk_report

step "Kernel host tools (pahole, libelf)"
if [ -d "$HOST_TOOLS_PREFIX" ]; then
	dependencies/build-kernel-host-tools.sh --verify-only
else
	dependencies/build-kernel-host-tools.sh --jobs "$JOBS"
fi
disk_report

step "Apple GPU prefix for iOS device (Mesa Zink + KosmicKrisp, virglrenderer)"
if [ -d "$GPU_PREFIX" ]; then
	dependencies/build-apple-gpu.sh --platform ios --prefix "$GPU_PREFIX" --verify-only
else
	dependencies/build-apple-gpu.sh --platform ios --prefix "$GPU_PREFIX" \
		--work-root .build/dependency-build/apple-gpu-ios --jobs "$JOBS"
fi
disk_report

step "Free work trees (keep only installed prefixes for the cache)"
rm -rf .build/dependency-build
disk_report
note "dependencies ready"
