<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Architecture (as verified in the source)

Base: upstream `main` at `fbe12ee` ("Merge cpu/aot-default"), 2026-11-19.
Every statement names the upstream file it was read from. Upstream's own
[`docs/architecture.md`](../docs/architecture.md) stays the owner; this is the
summary this fork's plan rests on.

## One picture

```text
iOS app (Andarium, SwiftUI)
  -> runtime loader (GuestHost) -> runtime framework (darwin/, C++20 + arm64 asm)
       Linux 6.18 kernel, User-mode Linux, compiled to native arm64   (not emulated)
       Android 17 userspace (LineageOS 24)                            (emulated)
          gadget engine  : threaded interpreter, hand-written arm64
          AOT framework  : Android's own libraries pre-translated to native code
          JIT engine     : native blocks, development builds only, needs a debugger
       virtio devices: gpu, block, net (libslirp), sound, input, camera, vsock
  -> guest Mesa (Virgl / Venus) -> virglrenderer -> Zink -> KosmicKrisp -> Metal
```

## Confirmed facts

| Area | Fact | Source |
| --- | --- | --- |
| Kernel | Mainline 6.18 User-mode Linux, native arm64, linked into the runtime | `README.md`, `docs/architecture.md` |
| Guest pages | 4 KiB guest pages on the 16 KiB host page, software MMU | `docs/architecture.md` "Memory and executable code" |
| vCPUs | One host thread per vCPU; uniform vCPUs; default and maximum = physical cores, at most 8 | `docs/architecture.md`, `runtime/guest_memory_budget.hpp` rule |
| Interpreter | "Gadget" engine: streams of pointers to precompiled gadgets, data only, no executable memory | `darwin/cpu/arm64/gadgets/README.md` |
| AOT | Android system libraries and boot image rewritten ahead of time into a signed framework; pages verified by SHA-256 before native execution | `docs/architecture.md` "Ahead-of-time code" |
| AOT at this commit | No `android/lineage-24/metadata/accepted-aot.env` is tracked, so a build carries AOT only with an artifact supplied to it | repository tree |
| JIT | Only in development configurations; iOS gives executable memory only through an attached debugger (StikDebug) | `docs/architecture.md` "Executable code" |
| JIT cost | On the JIT, Android boot, app launches and background work run several times slower; a long single-process computation runs faster | `Andarium/README.md` "JIT" |
| App Store build | No JIT engine at all; reads no environment knob | `Andarium/README.md` "Configurations" |
| Graphics | One path: Virtio-GPU -> virglrenderer -> Zink on KosmicKrisp -> Metal 4. GLES 3.2 via Virgl, Vulkan 1.4 via Venus | `docs/graphics.md`, `android/lineage-24/README.md` |
| Display pacing | Guest display is paced by a kernel vblank timer at the mode's refresh rate | `kernel/common/README.md` |
| Memory | Guest RAM is committed on demand; default guest size is capped at 4 GiB; GPU budget is derived from the iOS process limit | `docs/architecture.md` "Budgets" |
| Heat | Android is told only of iOS's critical thermal state and then limits to 30 fps; Settings > Performance > "When hot" can turn that off | `Andarium/README.md` "Heat" |
| Lifecycle | Android runs only while Andarium is in the foreground | `Andarium/README.md` "Targets" |
| Entitlements | Increased memory limit and extended virtual addressing | `Andarium/Config/Andarium.entitlements` |
| Minimum OS | iOS 27.0, built with Xcode 27 (JSON project format) | `docs/architecture.md`, `Andarium/README.md` |
| adb | Andarium is the adb host over vsock; "ADB over network" relays TCP 5555 while USB debugging is on, off at every start | `Andarium/README.md` "Android operations" |

## Settings that already exist upstream

vCPU count, guest RAM, resolution (1.0 to native in 0.5 steps), JIT row
(development builds), "When hot" frame-rate limit, statistics overlay (CPU,
FPS, RAM, VRAM). Source: `Andarium/README.md`, `Shared/PerformanceSection.swift`.

## Where time goes (upstream's measurements, not this fork's)

From [`docs/optimization-history.md`](../docs/optimization-history.md):

- Memory translation is the broadest gadget cost; dispatch cost is in
  predicting the target, not loading it (G178, G192, G193, G291).
- The translator is a few percent of a vCPU's time; bigger caches or extra
  tiers did not pay (G166, G235).
- Asymmetric (performance/efficiency) vCPU topologies were built and rejected:
  they reduced useful capacity (G176, G177).
- Android boot is dominated by ART and host scheduling, not by the engine's
  fixed costs.

## Hypotheses (not confirmed by anyone)

- Fully compiling an installed app with ART (`speed`) shortens its launches
  under this engine, because less Java runs in ART's interpreter and less code
  is generated at run time. To be measured with the tool here.
- A 120 Hz guest display mode would lower input latency on a ProMotion
  screen. It needs a runtime change and a device to measure.
