// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UIKit

#if !APP_STORE

/// Asks StikDebug to attach to this running process, so that the JIT can be
/// prepared without the person opening Andarium from StikDebug first.
///
/// StikDebug's `enable-jit` URL names the bundle and the process. On a device
/// with TXM (iOS 26 and later on recent chips) a debugger flag alone does not
/// let a page run: every executable region is prepared through the debug
/// connection, which StikDebug's `universal.js` script does when the process
/// executes `brk #0xf00d` with x16 = 1 (prepare) or 0 (detach). That is the
/// protocol `darwin/cpu/jit_memory/executable_memory.cpp` speaks, so the URL
/// names that script. A successful open only means iOS handed the URL to
/// StikDebug; the debugger being attached is read separately
/// (`JitDebugger.attached`).
enum StikDebugLink {
    /// The StikDebug script that serves the runtime's requests.
    nonisolated static let script = "universal.js"

    /// The URL that asks StikDebug to attach to `pid` of `bundleID`.
    nonisolated static func url(bundleID: String, pid: Int32) -> URL? {
        var components = URLComponents()
        components.scheme = "stikdebug"
        components.host = "enable-jit"
        components.queryItems = [
            URLQueryItem(name: "bundle-id", value: bundleID),
            URLQueryItem(name: "pid", value: String(pid)),
            URLQueryItem(name: "script-name", value: script),
        ]
        return components.url
    }

    /// Hands the request to StikDebug; false when no app takes the URL (StikDebug is
    /// not installed) or this process has no bundle identifier.
    static func open() async -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let url = url(bundleID: bundleID, pid: getpid())
        else { return false }
        return await UIApplication.shared.open(url)
    }
}

#endif
