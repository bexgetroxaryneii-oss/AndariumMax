<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# AndariumMax cloud build

Status: **configured and checked locally, not yet run in the cloud.** Nothing
here has compiled on a Mac yet. The first run will show the real errors.

## 1. What the repository needs to build an IPA (Phase 1 report)

Checked against the checkout at `baseline-upstream` (upstream `fbe12ee`).

| Input | In the repo? | Where it comes from | Cloud build |
| --- | --- | --- | --- |
| App source (`Andarium/`, `GuestHost/`, `darwin/`) | yes | — | compiled |
| Xcode 27, iOS 27 SDK, Metal Toolchain | — | Xcode 27 only (JSON project format) | `xcode-27` runner |
| Dependency prefixes: Mesa 26.2.6 (Zink + KosmicKrisp), virglrenderer, libepoxy, GLib, libslirp, GPT fdisk, zstd | pinned sources + patch series | `dependencies/prepare.sh` then the `build-*.sh` scripts | built, then cached |
| Kernel host tools (pahole, libelf) | pinned | `build-kernel-host-tools.sh` | built, cached |
| Android kernel bundle (`android-6.18-arm64-4k`) | patch series only; **no published bundle** | `kernel/mainline-6.18/build/build-kernel.sh --product android` on macOS | built, cached |
| **Android system image** (LineageOS 24 release `20261115-los24-r28`) | descriptor only | **upstream publishes it**: release `1.0b15-release`, asset `lineage24-mainline6.18-4k-20261115-los24-r28.tar.gz` (~1 GB) | downloaded, installed with `install-release.py`, staged |
| AOT artifact (`UmlArm64Aot`) | none accepted (`accepted-aot.env` absent) | `tools/aot/release_artifact.py build` from the installed release | built on the runner and passed as `UML_AOT_ARTIFACT`; skipped with a warning if it fails |
| Signing team | ignored local file | `GuestHost/Config/Signing.local.xcconfig` | not used: the IPA is unsigned |
| Submodules | none | — | — |

Runtime pieces found for later phases: CPU engines under `darwin/cpu`
(arm64 interpreter/JIT, `darwin/cpu/arm64/aot`, `darwin/cpu/jit_memory`), GPU
through Mesa Zink on KosmicKrisp (Metal 4) with virglrenderer/Venus, audio as
the Virtio Sound provider (`UML_BUILD_AUDIO`), the Android guest in
`android/lineage-24`.

Notes:

- The system release is the exact one `accepted-release.env` names, so no
  substitute image is used. Its kernel is the one this checkout builds
  (upstream's published kernel `vd2` is older than the accepted `ca1`).
- `system_mode = none` still makes a *compile-check* IPA (name ends
  `compile-check-NO-ANDROID`) for quick compile tests.
- If the AOT build fails the IPA has no ahead-of-time code and can be slower
  than upstream's; the run shows a warning. Compare cloud builds with cloud
  builds.

## 2. The pipeline

`.github/workflows/andariummax-ios.yml`, manual trigger only
(`workflow_dispatch`), all jobs on the `xcode-27` label (Apple silicon, Xcode
27). Each job calls one script in `fork/ci/`, so the same commands run on a
Mac by hand.

| Job | Script | Output | Cache key |
| --- | --- | --- | --- |
| 1 Dependency prefixes | `build-dependencies.sh` | `.build/dependencies/...` | hash of `dependencies/**` |
| 2 Android kernel bundle | `build-android-kernel.sh` | `.build/kernel/artifacts/...` | hash of `kernel/**` |
| 3 Andarium IPA | `build-app.sh` | unsigned IPA + logs | — |

The first run builds Mesa and the kernel and is long; later runs restore them
in minutes unless their inputs change.

Logs: every long step is written in full to `.build/ci/logs/*.log` and
uploaded as `build-logs-runN` (also when the run fails). The run's summary
page lists the first error lines of a failed step.

Kernel descriptor: the bundle is published under upstream's accepted release
ID. If the rebuilt bundle's `release` string differs from upstream's (it holds
the replay commit's ID), the script rewrites
`accepted-android-4k.env` **in the runner only** and prints a warning. It
stops if the source tree or the bridge ABI differ. This is fine for the
Release (development) configuration the cloud build uses; AppStore and
TestFlight would refuse it on purpose.

Build config is separate from performance work: these files are on branch
`cloud-build` (from `baseline-upstream`), merged into `performance-fork`.
Running the workflow on `baseline-upstream`-plus-CI vs `performance-fork`
gives the before/after pair.

## 3. Supplying a different Android system

By default the workflow downloads upstream's accepted release. To use another
one, upload it as an asset of a release in **your** GitHub repository (keep that
repository private if you do not want to redistribute the image), then start
the workflow with `system_mode = tag` and `system_release_tag` set to that tag.

| Asset name | Meaning | Mode |
| --- | --- | --- |
| `andarium-system*.zip` | an already staged `andarium-system` folder | `staged` |
| `android-release*.zip / .tar.zst` | a release directory with its `release-manifest` | `release` (installed and staged by the repo's scripts) |

## 4. Signing and SideStore

The archive is made with `CODE_SIGNING_ALLOWED=NO`, then ad-hoc signed
(`codesign -s -`) so the entitlements in `Andarium/Config/Andarium.entitlements`
travel inside the IPA. SideStore re-signs with your Apple ID.

What a **free** Apple ID allows:

- 3 sideloaded apps at a time; re-sign every 7 days (SideStore refreshes).
- `increased-memory-limit` and `extended-virtual-addressing` are App ID
  capabilities. SideStore does not add them by default for free accounts.
  Community tools (GetMoreRam / iRAM+-style apps) add them to the App ID after
  the first install. Without them, Android may be killed for memory.
- JIT through StikDebug needs `get-task-allow`, which SideStore's development
  signing gives.
- An IPA with the system inside is several GB; installing over SideStore is
  slow but is one file.

A paid account removes the 7-day limit and lets you enable both memory
capabilities on developer.apple.com.

## 5. Running it

From Windows, `BUILD_ANDARIUMMAX.bat` in the AndariumMax folder (GitHub CLI).
Or on github.com: Actions → AndariumMax iOS build → Run workflow.

Local check (Linux, WSL, Git Bash): `fork/ci/validate-local.sh`. It checks
the workflow's structure, script syntax and that every script the CI calls
exists. It does **not** prove the cloud build compiles.

## 6. Not verified yet

- Any compile on the runner (needs the repo on GitHub and a run).
- Whether the iOS device runtime's configure also wants the `macos` host
  dependency prefix; if it does, job 1 gets one more product.
- Whether the free runner's disk (listed as 14 GB) holds the Mesa build; the
  scripts print free space after each step.
- Whether the rebuilt kernel's source tree matches upstream's (the script
  checks and stops if not).
- Anything on the phone.
