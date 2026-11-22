<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Performance changelog

## v0.3 (2026-11-22)

Base: `performance-fork` v0.2 plus the cloud build (`cloud-build`).

| File | Change |
| --- | --- |
| `Andarium/Andarium/Live/StikDebugLink.swift` | new: StikDebug's `enable-jit` link for this process, with `universal.js` |
| `Andarium/Andarium/Shared/Model.swift` | `requestJitFromStikDebug`, `requestJitAtOpenIfWanted`: ask StikDebug, wait up to 60 s for the debugger, prepare the memory |
| `Andarium/Andarium/Shared/Jit.swift` | `JitRequestState`, footer sentences, `canRequest` |
| `Andarium/Andarium/Shared/HomeSections.swift` | the JIT row asks StikDebug when turned on, and offers "Enable JIT with StikDebug" |
| `Andarium/Andarium/Shared/RuntimeDriver.swift`, `Live/LiveRuntime.swift` | `requestJitDebugger` |
| `Andarium/AndariumTests/JitTests.swift`, `UpdateFlowTests.swift` | 4 tests and the stub's StikDebug |
| `Andarium/Localization/JIT.xcstrings` | 4 strings, ja / zh-Hans / zh-Hant |
| `darwin/device/audio/in_process_service.cpp`, `README.md` | the Virtio Sound service thread runs at user-interactive QoS |
| `fork/ci/build-app.sh` | AOT artifact built from the installed release and passed to the runtime |

Why JIT showed as off: a fresh install keeps the JIT row off, and a launch
from StikDebug with the row off tells the debugger to leave. StikDebug then
reports success while Home says to open Andarium from StikDebug, and turning
the row on afterwards could not get the debugger back in that process.

Why audio may crackle: the guest's ALSA ring is 1024 frames (four 5 ms
periods, about 21 ms). The host thread that completes those periods had no
QoS of its own. The ring size itself is an Android release input
(`ro.hardware.audio.tinyalsa.*`) and needs a rebuilt release to change.

Tests run on Linux: `localization.py check` (catalogs complete),
`fork/tests/run-host-tests.sh` (unit tests, licence and portability checks,
tool tests). Not run here: the Swift tests (need the iOS Simulator runtime),
anything on the phone. Compilation is checked by the cloud build.

Rollback: revert the commit (`git revert`), or build `cloud-build`, which
is upstream plus the build scripts only.

Measured performance change: none claimed yet.

## v0.2 (2026-11-19)

Base: upstream `fbe12ee`, kept as the branch `baseline-upstream`.

Emulator source changed:

| File | Change |
| --- | --- |
| `darwin/runtime/guest_memory_budget.hpp` | `gadget_cache_capped_budget` (the old rule), `gadget_cache_raise`, and `gadget_cache_budget` as their sum |
| `darwin/runtime/context.cpp` | the JIT's region is sized from the capped budget |
| `darwin/runtime/execution_engine.hpp` | comments follow the two budgets |
| `tests/unit/runtime/guest_memory_budget_tests.cpp` | 3 new tests; 2 existing ones name the capped budget |
| `tests/unit/emulator/gpu_budget_plan_tests.cpp` | a roomy limit's raised engine figure, and a tight one's cap |
| `tests/unit/arm64/arm64_jit_memory_preparation_tests.cpp` | sizes the region from the capped budget |
| `docs/architecture.md`, `docs/optimization-history.md` | the formula and the unmeasured entry |
| `Andarium/Andarium/Preview/PreviewData.swift` | comment only |

Tests run on Linux: `runtime-guest-memory-budget` (32 tests) and
`arm64-gadget-cache-budget` built natively and passed; licence and
portability checks passed; the changed function in `context.cpp` and the two
other test files were type-checked by clang. Not run: everything that needs an
Apple SDK (the runtime build, the hosted app tests, the JIT and plan tests).

Measured performance change: none claimed. Nothing has been measured.

## v0.1 (2026-11-19)

Base: upstream `fbe12ee`.

- Added the AndariumMax tool: connect over ADB over network, Android info,
  quick benchmark (cold launches, frames, UI jank, guest CPU), 10-minute
  sustained test, per-app ART speed-compile with undo, animation scale,
  comparison of two saved results.
- Added the fork documents and the Mac build script.
- No change to Andarium, the runtime, the kernel or the Android image.
- Measured performance change: none claimed. Nothing has been measured yet.
