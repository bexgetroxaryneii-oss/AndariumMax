<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Performance fork

This directory holds everything the `performance-fork` branch adds to
Kernarium. Nothing outside it is changed, so upstream merges stay clean.

| File | What it is |
| --- | --- |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | How Andarium runs Android, checked against the source |
| [`PERFORMANCE_BASELINE.md`](PERFORMANCE_BASELINE.md) | The measuring procedure and the baseline's state |
| [`OPTIMIZATION_PLAN.md`](OPTIMIZATION_PLAN.md) | What can be made faster, in order, and what cannot |
| [`BENCHMARK_RESULTS.md`](BENCHMARK_RESULTS.md) | Measured results only |
| [`BUILD_INSTRUCTIONS.md`](BUILD_INSTRUCTIONS.md) | Building the tool (Windows) and the app (Mac) |
| [`IPHONE_INSTALLATION.md`](IPHONE_INSTALLATION.md) | Installing, JIT, keeping Android data |
| [`CHANGELOG_PERFORMANCE.md`](CHANGELOG_PERFORMANCE.md) | What each fork version changed |
| [`tool/`](tool) | AndariumMax: measures and tunes the Android guest over adb |
| [`windows/`](windows) | One-step build of the tool on Windows |
| [`mac/`](mac) | Build script for the iOS app (needs a Mac) |

Made by Claude Strife - X. Licence: GPL-2.0-or-later, as upstream.
