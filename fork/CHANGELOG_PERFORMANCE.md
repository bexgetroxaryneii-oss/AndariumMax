<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Performance changelog

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
