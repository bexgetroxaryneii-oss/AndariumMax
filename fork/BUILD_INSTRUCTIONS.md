<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Build instructions

## What builds where

| Thing | Windows PC | Mac (Apple silicon, Xcode 27) |
| --- | --- | --- |
| AndariumMax tool | Yes: `BUILD.bat` | Yes: `cargo build --release` in `fork/tool` |
| Andarium iOS app (IPA) | No | Yes |
| Android system image | No (needs a large x86-64 Linux build host, or upstream's prebuilt release) | No |

An iOS app cannot be compiled, signed or archived on Windows. The runtime is
C++20 and arm64 assembly for Apple targets only, and the project file is
Xcode 27's.

## Tool on Windows

Double-click `BUILD.bat` in the fork's folder. It finds Rust, finds or
downloads adb (Google's platform-tools), builds with live output, and opens
`AndariumMax.exe`. The tool has no third-party dependencies.

Tests: `cargo test` in `fork/tool` (16 tests; they need no phone).

## Tests on Linux or Windows (WSL), no Apple SDK

```sh
fork/tests/run-host-tests.sh
```

It builds and runs the runtime's memory-budget unit tests and the gadget
cache budget tests natively, the repository's licence and portability checks,
and the tool's tests.

## Branches

| Branch | What it is |
| --- | --- |
| `baseline-upstream` | upstream `fbe12ee`, untouched: the build to compare against |
| `performance-fork` | the baseline plus the fork's commits |

Build both the same way on the Mac and install them under different bundle
identifiers, or one after the other, to compare on the phone.

## App on a Mac

On the Mac, the focused test of the fork's change is:

```sh
cmake --workflow --preset check-unit      # or: ctest -R '^runtime-guest-memory-budget$'
```

`fork/mac/build-ipa.sh` runs the steps upstream documents, in order, and
stops with the reason at the first one that fails. It has not been run yet:
no Mac was available when it was written.

Prerequisites it checks:

- Xcode 27 with the Metal Toolchain component, CMake 3.27+, Ninja, Python 3.11+
- your team in `GuestHost/Config/Signing.local.xcconfig`
  ([`GuestHost/README.md`](../GuestHost/README.md#signing))
- the dependency prefixes under `.build/dependencies`
  ([`dependencies/README.md`](../dependencies/README.md))
- an accepted Android kernel bundle and the accepted Android release
  installed under `.build/android/releases`
  ([`android/lineage-24/README.md`](../android/lineage-24/README.md#release-installation));
  upstream publishes prebuilt images on its releases page

Steps it runs (from [`Andarium/README.md`](../Andarium/README.md#build)):

```sh
cmake --preset kernarium-ios-device-android
cmake --build --preset kernarium-ios-device-android
Kernarium/scripts/package-ios-frameworks.sh --runtimes android
Andarium/scripts/stage-system-image.py
xcodebuild archive -project Andarium/Andarium.xcodeproj -scheme Andarium \
    -configuration Release -destination 'generic/platform=iOS'
xcodebuild -exportArchive   # development export, signed with your identity
```

`Release` is upstream's development configuration: it carries the JIT row.
The AppStore and TestFlight configurations refuse a fork's unaccepted inputs
and are not for sideloading.

## Moving the fork to a Mac

The fork is an ordinary Git repository. Copy the folder, or:

```sh
git clone <path-to-the-fork-folder>/Kernarium andarium-max
cd andarium-max && git checkout performance-fork
```

The copy on Windows is a shallow clone of upstream (one commit of history).
`git fetch --unshallow origin` on the Mac brings the rest.
