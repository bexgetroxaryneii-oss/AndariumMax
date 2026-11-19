<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Optimization plan

## What was inspected

The arm64 gadget engine and its cache (`darwin/cpu`), the JIT and its
executable memory (`darwin/cpu/arm64/jit`, `darwin/cpu/jit_memory`), the
ahead-of-time component (`darwin/cpu/arm64/aot`, `tools/aot`), the memory
budgets (`darwin/runtime/guest_memory_budget.hpp`, `darwin/platform/gpu_budget.hpp`),
the session record (`darwin/runtime/session_record.cpp`), the Android product
(`android/lineage-24`), the graphics path (`docs/graphics.md`, `darwin/device/gpu`),
the last 400 fetched upstream commits and all of
[`docs/optimization-history.md`](../docs/optimization-history.md).

Upstream has recorded about three hundred engine experiments, each on matched
builds on devices. The fork does not repeat them and does not change gadget,
JIT, MMU or graphics code that only a device can validate.

## The three most promising bottlenecks

| # | Bottleneck | Evidence | Status |
| --- | --- | --- | --- |
| 1 | Translated-code cache held to a per-vCPU cap (272 MiB at 6 vCPUs). A program past it is shed whole and translated again; an Android guest at the cap relieves tens of times a session | Upstream G296, G297, G298 measured the mechanism on a 6-vCPU iPhone and on a Mac | Mechanism confirmed by upstream. Whether this phone's limit leaves room, and how often its games hit the cap, needs the phone's session record |
| 2 | vCPU threads on efficiency cores. The phone has 2 fast and 4 efficiency cores and the guest gets 6 uniform vCPUs | Upstream G176, G177: binding to core types is not available through supported APIs and an asymmetric topology regressed boot. The session record's `perf` column is the share of CPU time on fast cores | Needs device data: `perf` at 4 and at 6 vCPUs for the same game |
| 3 | Application code that the ahead-of-time component cannot cover. It translates Android's own libraries; an installed game's code runs on the gadget engine, and its Java in ART's interpreter until ART compiles it | Upstream AOT2: boot at 0.72 of the engine's time with system libraries covered; nothing covers installed apps | Half confirmed. The ART part is measurable today over adb (the tool's speed-compile, before and after); the native part needs the JIT or a device profile |

Graphics (Virgl or Venus through Zink and KosmicKrisp to Metal) is the next
candidate after these. It needs Instruments on a Mac: the guest cannot tell a
presented frame from a discarded one.

## The optimization selected

Bottleneck 1 is the only one whose remedy is plain arithmetic that this
machine can build and test completely. It is implemented in the emulator:

- `darwin/runtime/guest_memory_budget.hpp`: `gadget_cache_raise`. Where the
  process limit leaves the host GPU more than 2048 MiB with the capped cache,
  the surplus goes to the gadget cache, up to the budget a host without a
  limit gives the same guest (what every macOS run already uses).
- The raise comes out of the GPU's budget and leaves it at 2048 MiB or more.
  The maximum, conservative and default guest sizes and the graphics warning
  line do not move; the unit test holds that for every limit up to 16 GiB.
- `darwin/runtime/context.cpp`: the JIT's wired region stays sized from the
  capped budget.

What it does at 6 vCPUs, computed by the built code (MiB):

| Process limit | Guest RAM | Cache before | Cache after | GPU budget before | after |
| --- | --- | --- | --- | --- | --- |
| 5120 | 3072 (default) | 272 | 272 | 1218 | 1218 |
| 5120 | 2048 | 272 | 466 | 2242 | 2048 |
| 6144 | 3072 | 272 | 466 | 2242 | 2048 |
| 7168 | 4096 (default) | 272 | 466 | 2242 | 2048 |
| 8192 | 4096 (default) | 272 | 1024 | 3266 | 2514 |
| 9216 | 4096 (default) | 272 | 1024 | 4290 | 3538 |

Upstream's preview mock assumes 5120 MiB for an iPhone 18 Pro Max
(`Andarium/Andarium/Preview/PreviewData.swift`). If that is the real limit,
the change does nothing at the default guest size and acts only on a guest of
about 2.2 GiB or less. The real limit is the first thing to read off the phone.

No speed change is claimed. Nothing has been measured.

## Device testing this needs

1. The limit. In Andarium's statistics the VRAM row is "used / budget"; with
   the guest's RAM and vCPU count that gives the limit:
   `limit = budget + guest RAM + 830` at 6 vCPUs, in MiB.
2. A baseline session record. Play one heavy game for ten minutes on the
   upstream build, then Settings > Create bug report. The zip's `andarium/`
   folder holds the session record; its history rows carry `cache`,
   `reliefs`, `shed`, `largest`, `gap` (worst frame gap), `perf` and
   `thermal`.
3. The same game, same settings, on a build of this branch. Compare
   `reliefs`, `shed` and `gap`. Fewer reliefs with a smaller worst gap
   supports the change; equal figures mean the cap was not binding.

## Order of work after this

| # | Item | Needs |
| --- | --- | --- |
| 1 | Read the limit and a baseline session record from the phone | the phone, 15 minutes |
| 2 | Build this branch into an IPA | a Mac with Xcode 27, or a hosted macOS build you authorise |
| 3 | A/B the cache raise (above) | items 1 and 2 |
| 4 | vCPU sweep, 4 against 6, reading `perf` | item 1 |
| 5 | Lower the keep line if session records show GPU memory unused and the cache relieved | item 3 |
| 6 | Engine work with upstream's `tests/perf` runners | Mac, cable, matched runs |

## Things this fork will not do

- Remove memory protection, page verification or correctness checks.
- Raise guest RAM or vCPUs past what Andarium offers.
- Turn off the heat limit by default.
- Claim a speedup without a saved before and after result.
