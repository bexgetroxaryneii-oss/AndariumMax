<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Optimization plan

## The finding that shapes the plan

Upstream has run and recorded about three hundred engine experiments, each on
matched builds on real devices ([`docs/optimization-history.md`](../docs/optimization-history.md)).
Most of the obvious ideas are in it, measured and rejected: larger caches,
extra translation tiers, prefetching, dispatch rewrites, lock replacements,
performance/efficiency core topologies. Upstream's own rule is that a gadget
change is measured on a device before it stays.

So this fork does not edit the CPU engine, the JIT, the MMU or the graphics
stack without a Mac and a phone to measure on. A blind change there is far
more likely to slow Android down or corrupt it than to speed it up.

## Order of work

| # | Item | Status | Needs |
| --- | --- | --- | --- |
| 1 | Measuring tool that works from Windows over adb | Done, v0.1; parsers unit-tested, not yet run on a phone | - |
| 2 | Baseline on the target phone with the upstream build | Open | the phone, 15 minutes |
| 3 | Settings sweep: vCPUs (4, 6), RAM, resolution, JIT on/off, per game | Open | item 2 |
| 4 | Per-app ART `speed` compile, measured before and after | Tool has it; effect unmeasured | item 2 |
| 5 | Sideload a development build to get the JIT row | Open | Mac build or upstream IPA |
| 6 | iOS build pipeline (`mac/build-ipa.sh`) run end to end | Written, never run | a Mac with Xcode 27 |
| 7 | Performance settings in the app (frame-rate cap, benchmark mode, launch timer in the stats overlay) | Not started | item 6, to compile and test Swift |
| 8 | 120 Hz guest display mode as an option | Hypothesis | item 6 and device measurement |
| 9 | Engine work guided by upstream's `tests/perf` runners | Not planned until 6 works | Mac, cable, matched ABBA runs |

## Why items 3 and 4 come first

They are the only levers that exist today without a Mac, and each is
reversible and measurable:

- vCPU count: upstream found the best count is device-specific and that
  more is not always better (boot sweeps in the optimization history). The
  phone has 2 fast and 4 efficiency cores; whether 6 vCPUs beat 4 for a given
  game is an open question the sweep answers.
- Resolution: the default is the choice nearest 2.0x; 1.0x and 1.5x cut GPU
  work. Only measurement says whether a game is GPU-bound here.
- JIT: upstream states launches get several times slower and long
  single-process work gets faster. A game may land on either side.
- ART `speed`: one Android command per app, undone by one command.

## Things this fork will not do

- Remove memory protection, page verification or correctness checks.
- Raise guest RAM or vCPUs past what Andarium offers.
- Turn off the heat limit by default.
- Claim a speedup without a saved before and after result.
