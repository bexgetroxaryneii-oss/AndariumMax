#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Check the cloud build configuration without a Mac: workflow YAML parses and
# has the expected jobs, every CI script passes `bash -n` (and shellcheck when
# installed), and every repository script and preset the CI calls exists.
# Runs on Linux, WSL or Git Bash. It cannot prove that the cloud build
# compiles: only a run on the macOS runner does.

set -u
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT_DIR"
errors=0
ok() { printf '  [ OK ] %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; errors=$((errors + 1)); }

echo "Workflow"
WF=.github/workflows/andariummax-ios.yml
if [ ! -f "$WF" ]; then
	bad "$WF missing"
elif python3 - "$WF" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("  [SKIP] PyYAML not installed: structure not checked")
    sys.exit(0)
wf = yaml.safe_load(open(sys.argv[1]))
on = wf.get("on", wf.get(True))
assert "workflow_dispatch" in on, "no manual trigger"
jobs = wf["jobs"]
for name in ("dependencies", "kernel", "app"):
    assert name in jobs, f"job {name} missing"
    assert jobs[name]["runs-on"] == "xcode-27", f"{name} not on xcode-27"
for job in jobs.values():
    for s in job["steps"]:
        if "run" in s and s["run"].startswith("fork/ci/"):
            import os
            p = s["run"].split()[0]
            assert os.path.isfile(p), f"step runs missing {p}"
print("  [ OK ] workflow parses; 3 jobs on xcode-27; manual trigger")
PY
then :; else bad "workflow structure"; fi

echo "CI scripts"
for f in fork/ci/*.sh; do
	if bash -n "$f"; then ok "bash -n $f"; else bad "syntax $f"; fi
	[ -x "$f" ] || git ls-files -s "$f" | grep -q '^100755' || bad "$f is not executable in Git"
done
if command -v shellcheck >/dev/null 2>&1; then
	if shellcheck -S warning -x fork/ci/*.sh; then ok "shellcheck"; else bad "shellcheck"; fi
else
	echo "  [SKIP] shellcheck not installed"
fi

echo "Repository entry points the CI calls"
for p in dependencies/prepare.sh dependencies/build-ios-network.sh \
	dependencies/build-apple-gpu.sh dependencies/build-kernel-host-tools.sh \
	dependencies/build-ios-storage.sh dependencies/build-ios-zstd.sh \
	dependencies/kernel-host-tools/archives.tsv \
	kernel/mainline-6.18/scripts/prepare-source.sh \
	kernel/mainline-6.18/build/build-kernel.sh \
	kernel/mainline-6.18/build/publish-artifact.py \
	kernel/mainline-6.18/artifacts/accepted-android-4k.env \
	Kernarium/scripts/package-ios-frameworks.sh \
	android/lineage-24/tools/install-release.py \
	Andarium/scripts/stage-system-image.py \
	Andarium/Andarium.xcodeproj/project.xcproj \
	Andarium/Config/Andarium.entitlements; do
	if [ -e "$p" ]; then ok "$p"; else bad "missing $p"; fi
done
if python3 -c "import json,sys; n=[p['name'] for p in json.load(open('CMakePresets.json'))['configurePresets']]; sys.exit(0 if 'kernarium-ios-device-android' in n else 1)"; then
	ok "CMake preset kernarium-ios-device-android"
else
	bad "CMake preset kernarium-ios-device-android missing"
fi

echo
if [ "$errors" -eq 0 ]; then
	echo "RESULT: configuration valid (local checks only; cloud compile not proven here)"
else
	echo "RESULT: $errors problem(s)"
fi
exit "$errors"
