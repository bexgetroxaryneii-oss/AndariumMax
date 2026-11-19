<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Installing on an iPhone

Checked on 2026-11-19. Sideloading tools change with every iOS release:
confirm each tool's current notes for iOS 27 before relying on a step marked
"unverified".

## Three ways to get Andarium

| Way | JIT | Build needed | Notes |
| --- | --- | --- | --- |
| App Store | No | None | Upstream's shipping build. Simplest, and updates itself |
| Upstream's IPA from its releases page, sideloaded | Yes, with a debugger | None | A development-style build with the JIT row |
| This fork's IPA | Yes, with a debugger | A Mac | Only useful once the fork changes the app |

Until the fork changes app code, the App Store build or upstream's IPA is the
fastest thing you can install. This fork's tool works with any of the three.

## Sideloading an IPA

- An unsigned IPA cannot be installed, and the Files app cannot install one.
  A sideloading tool signs it with your Apple ID and installs it.
- Developer Mode must be on: iOS Settings > Privacy & Security > Developer Mode.
- Andarium needs two entitlements: increased memory limit and extended
  virtual addressing (`Andarium/Config/Andarium.entitlements`). Whether a
  free Apple ID can sign them with a given tool is unverified here; a paid
  Apple Developer account can.
- Refresh: an app signed with a free Apple ID expires after 7 days and must
  be refreshed by the sideloading tool; with a paid account it lasts a year.
- Tools in common use: SideStore and AltStore (they refresh on the device),
  Sideloadly (from a PC). Use the tool's own guide for iOS 27.

## JIT

- JIT exists only in a development build, and iOS grants it only while a
  debugger is attached at launch (`docs/architecture.md`, "Executable code").
- Upstream's method is StikDebug: assign its universal script to Andarium
  once, then open Andarium from StikDebug each time.
- StikDebug is no longer on the App Store; it is sideloaded, and it needs a
  pairing file and a loopback VPN (LocalDevVPN). Its support for iOS 27 is
  unverified here.
- In Andarium: Home > JIT row on. The boot screen and the row say whether the
  start is on the JIT or fell back to gadgets, and why. That is the check that
  JIT is really active.
- JIT is not a general speedup: upstream states boot, app launches and
  background work run several times slower on it, and long single-process
  computation runs faster. Measure your game both ways.

## Keeping Android data across updates

- Android's data is `Library/Guest/data.img` inside Andarium's container.
- Installing a newer build over the same app (same bundle identifier, same
  signer) keeps it. Deleting the app deletes it.
- A fork build signed by another team has its own bundle identifier, so it
  is a second app with its own empty Android. Data does not move between them.
- An older Android release is refused on data from a newer one.
- Before any update: shut Android down and take a snapshot (Home > Snapshots).
  "Include in backups" on Home adds the guest to iCloud and computer backups.
