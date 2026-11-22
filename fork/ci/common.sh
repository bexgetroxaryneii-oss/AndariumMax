#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Shared helpers for the AndariumMax cloud build (fork/ci/*.sh). These scripts
# run on a GitHub-hosted macOS runner (label xcode-27). They only call the
# repository's own documented build scripts, in the documented order, and keep
# every product under .build exactly where a local Mac build puts it.

set -euo pipefail

CI_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$CI_DIR/../.." && pwd)
export ROOT_DIR
cd "$ROOT_DIR"

# Three cores on the standard arm64 runner; use what the machine reports.
JOBS=${CI_JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo 3)}
export JOBS

STEP_START=$(date +%s)

step()
{
	local now
	now=$(date +%s)
	printf '\n::endgroup::\n' 2>/dev/null || true
	printf '::group::[%s] %s (previous step %ss)\n' "$(date -u +%H:%M:%S)" "$*" \
		"$((now - STEP_START))"
	STEP_START=$now
}

note()
{
	printf '[andariummax-ci] %s\n' "$*"
}

fail()
{
	printf '::error::%s\n' "$*" >&2
	exit 1
}

disk_report()
{
	note "disk: $(df -h "$ROOT_DIR" | awk 'NR == 2 { print $4 " free of " $2 }')"
}

# Build tools only. The repository's own scripts refuse Homebrew *libraries*
# for production; Homebrew here supplies programs (cmake, meson, gmake, lld).
ensure_host_tools()
{
	export HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1
	local wanted=(cmake ninja meson pkgconf autoconf automake gettext libtool
		gperf groff make rsync coreutils llvm lld zstd erofs-utils)
	wanted+=("python@3.12")
	local missing=()
	local formula
	for formula in "${wanted[@]}"; do
		brew list --formula "$formula" >/dev/null 2>&1 || missing+=("$formula")
	done
	if [ "${#missing[@]}" -gt 0 ]; then
		note "installing build tools: ${missing[*]}"
		brew install "${missing[@]}"
	fi
	local python
	python=$(brew --prefix python@3.12)/bin/python3.12
	[ -x "$python" ] || fail "python 3.12 not found at $python"
	# Meson, Mako, PyYAML and packaging in the venv the GPU build prefers.
	if [ ! -x "$ROOT_DIR/.build/gpu-tools-venv/bin/meson" ]; then
		"$python" -m venv "$ROOT_DIR/.build/gpu-tools-venv"
		"$ROOT_DIR/.build/gpu-tools-venv/bin/pip" install --quiet \
			meson mako pyyaml packaging
	fi
	# Python 3.11+ first on PATH (macOS's own python3 is 3.9).
	mkdir -p "$ROOT_DIR/.build/ci-bin"
	ln -sf "$python" "$ROOT_DIR/.build/ci-bin/python3"
	# gmake (the kernel's UML_KERNEL_MAKE default) comes from the make formula,
	# ld.lld from lld; both land in Homebrew's bin, which is already on PATH.
	export PATH="$ROOT_DIR/.build/ci-bin:$(brew --prefix gettext)/bin:$(brew --prefix lld)/bin:$PATH"
	command -v gmake >/dev/null || fail "gmake missing after installing make"
	command -v ld.lld >/dev/null || fail "ld.lld missing after installing lld"
	# Git identity: the patch-series tooling refuses a host-derived one.
	git config --global user.name >/dev/null 2>&1 ||
		git config --global user.name "AndariumMax CI"
	git config --global user.email >/dev/null 2>&1 ||
		git config --global user.email "${GITHUB_ACTOR:-ci}@users.noreply.github.com"
	note "xcode: $(xcodebuild -version | tr '\n' ' ')"
	note "cmake: $(cmake --version | head -1), python: $(python3 --version)"
}

ensure_metal_toolchain()
{
	if xcrun -f metal >/dev/null 2>&1 && xcrun metal --version >/dev/null 2>&1; then
		note "Metal toolchain present"
		return
	fi
	note "downloading Xcode's Metal Toolchain component"
	xcodebuild -downloadComponent MetalToolchain
}
