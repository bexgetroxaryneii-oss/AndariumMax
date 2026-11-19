<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Performance baseline

## State

No baseline has been measured yet. Nothing here or in
[`BENCHMARK_RESULTS.md`](BENCHMARK_RESULTS.md) is a number until a run on the
target phone produces it.

## What can be measured, and from where

| Measure | How | Needs |
| --- | --- | --- |
| Cold app launch time | `am start-activity -W -S`, 5 runs, median | AndariumMax over adb |
| Frames shown per second | SurfaceFlinger TimeStats frames over a timed window | AndariumMax |
| UI frame time and jank | `dumpsys gfxinfo` (toolkit-drawn apps only, not games) | AndariumMax |
| Guest CPU use | `/proc/stat` over the window | AndariumMax |
| Sustained performance | 20 windows of 30 s: fps, CPU, Android thermal status | AndariumMax |
| Host CPU, VRAM, guest RAM | Andarium's own statistics overlay | read on the phone |
| Cold and warm boot | Andarium's boot screen; stopwatch | by hand |
| Engine-level profiles | upstream `tests/perf` runners, Instruments | a Mac and a cable |

## The session record (host side, no Mac needed)

The runtime writes a session record that Andarium adds to a bug report
(Settings > Create bug report, folder `andarium/` in the zip). Its history
rows are the device's own readings, one row per checkpoint:

| Column | Meaning |
| --- | --- |
| `footprint`, `available` | the process's memory and what the limit still leaves; their sum is the limit |
| `guest`, `gpu`, `graphics` | guest RAM held, host GPU memory |
| `cache` | bytes the gadget cache holds |
| `reliefs`, `shed`, `renewals`, `largest` | cache reliefs, accounts shed, and the largest program's bytes |
| `frames`, `gap` | frames flushed and the longest gap between two |
| `thermal`, `pressure` | iOS thermal state and memory pressure |
| `cpu`, `vcpu`, `perf` | process and vCPU time, and the share on fast cores |

This is the baseline the fork's cache change is judged against
([`OPTIMIZATION_PLAN.md`](OPTIMIZATION_PLAN.md)).

## Procedure for a comparable run

1. Same Andarium build and the same Andarium settings (vCPUs, RAM,
   resolution, JIT, "When hot"). The tool records what you type and what
   Android reports, and warns when two runs differ.
2. Phone unplugged or plugged the same way, not hot, Low Power Mode off,
   Andarium in front, screen unlocked for the whole run.
3. Android booted for at least two minutes before the first run.
4. One change at a time. Run each arm twice, alternating (A, B, B, A).
5. Differences under 3 % are treated as the same.

## Limits of these measurements

- Frame counts come from Android's compositor: they count frames Android
  showed, and the guest cannot tell a presented frame from a discarded one
  (`docs/graphics.md`). Host-side frame timing needs a Mac.
- Launch time ends at Android's first drawn frame, not when a game finishes
  loading.
- The tool's parsers are tested against sample text; the first run on a real
  Android 17 guest is what confirms each one. A figure Android does not print
  is left out, never estimated.
