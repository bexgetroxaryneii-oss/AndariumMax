#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Builds and runs everything of the fork that needs no Apple SDK: the
# runtime's memory-budget unit tests (header-only C++20), the gadget cache
# budget tests, the AndariumMax tool's tests, and the repository's licence and
# portability checks. Linux or macOS, with clang++ or g++, Python 3 and cargo.
#
# Usage: fork/tests/run-host-tests.sh
set -euo pipefail

root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
out="${TMPDIR:-/tmp}/andarium-max-host-tests"
mkdir -p "$out"
cxx="${CXX:-clang++}"
failed=0

unit() { # name source
    printf '[unit] %s ... ' "$1"
    if "$cxx" -std=c++20 -O1 -Wall -Wextra -Wno-missing-field-initializers \
            -I"$root/darwin" -I"$root/tests/unit/require" \
            "$root/$2" -o "$out/$1" -pthread >"$out/$1.build.log" 2>&1 &&
        "$out/$1" >"$out/$1.log" 2>&1; then
        count="$(grep -c '^ok:' "$out/$1.log" || true)"
        if [[ "$count" -gt 0 ]]; then echo "ok ($count tests)"; else echo "ok"; fi
    else
        echo "FAILED (see $out/$1.build.log and $out/$1.log)"
        failed=1
    fi
}

unit runtime-guest-memory-budget tests/unit/runtime/guest_memory_budget_tests.cpp
unit arm64-gadget-cache-budget tests/unit/arm64/gadget_cache_budget_tests.cpp

printf '[check] licence headers ... '
python3 "$root/tests/tooling/cmake/check_license_headers.py" --source-root "$root" |
    tail -1 || failed=1
printf '[check] environment portability ... '
python3 "$root/tests/tooling/cmake/check_environment_portability.py" \
    --source-root "$root" --no-denylist | tail -1 || failed=1

if command -v cargo >/dev/null 2>&1; then
    printf '[tool] AndariumMax ... '
    if CARGO_TARGET_DIR="$out/tool" cargo test --quiet --offline \
            --manifest-path "$root/fork/tool/Cargo.toml" >"$out/tool.log" 2>&1; then
        grep -E '^test result' "$out/tool.log" | head -1
    else
        echo "FAILED (see $out/tool.log)"
        failed=1
    fi
fi

if [[ "$failed" -ne 0 ]]; then
    echo "SOME CHECKS FAILED"
    exit 1
fi
echo "ALL HOST CHECKS PASSED"
