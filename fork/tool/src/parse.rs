// SPDX-License-Identifier: GPL-2.0-or-later

//! Parsers for the text Android's shell tools print. Every parser returns
//! `None` (or an empty list) for text it does not recognise, so a figure in a
//! result file is always one the guest really printed, never a guess.

/// `am start-activity -W`: the `TotalTime:` line, in milliseconds.
pub fn launch_total_ms(output: &str) -> Option<u64> {
    field_after(output, "TotalTime:").and_then(|v| v.parse().ok())
}

/// `am start-activity -W`: the `LaunchState:` word (COLD, WARM, HOT).
pub fn launch_state(output: &str) -> Option<String> {
    field_after(output, "LaunchState:").map(str::to_string)
}

fn field_after<'a>(output: &'a str, key: &str) -> Option<&'a str> {
    output.lines().find_map(|line| {
        let line = line.trim();
        line.strip_prefix(key)
            .and_then(|rest| rest.split_whitespace().next())
    })
}

/// The last `package/activity` line of `cmd package resolve-activity --brief`.
pub fn launcher_component(output: &str) -> Option<String> {
    output
        .lines()
        .map(str::trim)
        .filter(|l| l.contains('/') && !l.contains(' ') && !l.starts_with("No "))
        .last()
        .map(str::to_string)
}

/// `pm list packages`: the names after `package:`.
pub fn package_list(output: &str) -> Vec<String> {
    let mut names: Vec<String> = output
        .lines()
        .filter_map(|l| l.trim().strip_prefix("package:"))
        .map(|n| n.trim().to_string())
        .filter(|n| !n.is_empty())
        .collect();
    names.sort();
    names
}

/// What `dumpsys gfxinfo <package>` says of the frames the UI toolkit drew.
#[derive(Debug, Default, PartialEq, Clone)]
pub struct GfxInfo {
    pub total_frames: u64,
    pub janky_frames: u64,
    pub p50_ms: Option<u64>,
    pub p90_ms: Option<u64>,
    pub p95_ms: Option<u64>,
    pub p99_ms: Option<u64>,
}

pub fn gfxinfo(output: &str) -> Option<GfxInfo> {
    let mut info = GfxInfo::default();
    let mut seen_total = false;
    for line in output.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("Total frames rendered:") {
            // Several windows of one package each print a block: add them.
            info.total_frames += first_number(rest)?;
            seen_total = true;
        } else if let Some(rest) = line.strip_prefix("Janky frames:") {
            info.janky_frames += first_number(rest)?;
        } else if let Some(rest) = line.strip_prefix("50th percentile:") {
            info.p50_ms = max_opt(info.p50_ms, first_number(rest));
        } else if let Some(rest) = line.strip_prefix("90th percentile:") {
            info.p90_ms = max_opt(info.p90_ms, first_number(rest));
        } else if let Some(rest) = line.strip_prefix("95th percentile:") {
            info.p95_ms = max_opt(info.p95_ms, first_number(rest));
        } else if let Some(rest) = line.strip_prefix("99th percentile:") {
            info.p99_ms = max_opt(info.p99_ms, first_number(rest));
        }
    }
    seen_total.then_some(info)
}

fn max_opt(a: Option<u64>, b: Option<u64>) -> Option<u64> {
    match (a, b) {
        (Some(x), Some(y)) => Some(x.max(y)),
        (x, None) => x,
        (None, y) => y,
    }
}

fn first_number(text: &str) -> Option<u64> {
    let digits: String = text
        .trim_start()
        .chars()
        .take_while(|c| c.is_ascii_digit())
        .collect();
    digits.parse().ok()
}

/// One layer of `dumpsys SurfaceFlinger --timestats -dump`.
#[derive(Debug, PartialEq, Clone)]
pub struct LayerStats {
    pub name: String,
    pub total_frames: u64,
    pub average_fps: Option<f64>,
}

/// The layers TimeStats lists, in the order printed.
pub fn timestats_layers(output: &str) -> Vec<LayerStats> {
    let mut layers = Vec::new();
    let mut current: Option<LayerStats> = None;
    for line in output.lines() {
        let line = line.trim();
        if let Some(name) = value_of(line, "layerName") {
            if let Some(done) = current.take() {
                layers.push(done);
            }
            current = Some(LayerStats {
                name: name.to_string(),
                total_frames: 0,
                average_fps: None,
            });
        } else if let Some(layer) = current.as_mut() {
            if let Some(v) = value_of(line, "totalFrames") {
                layer.total_frames = v.parse().unwrap_or(0);
            } else if let Some(v) = value_of(line, "averageFPS") {
                layer.average_fps = v.parse().ok();
            }
        }
    }
    if let Some(done) = current {
        layers.push(done);
    }
    layers
}

fn value_of<'a>(line: &'a str, key: &str) -> Option<&'a str> {
    let rest = line.strip_prefix(key)?;
    let rest = rest.trim_start();
    rest.strip_prefix('=').map(str::trim)
}

/// The layer of `package` that showed the most frames.
pub fn busiest_layer<'a>(layers: &'a [LayerStats], package: &str) -> Option<&'a LayerStats> {
    layers
        .iter()
        .filter(|l| l.name.contains(package) && l.total_frames > 0)
        .max_by_key(|l| l.total_frames)
}

/// The first line of `/proc/stat`: (busy, total) in clock ticks.
pub fn proc_stat(output: &str) -> Option<(u64, u64)> {
    let line = output.lines().find(|l| l.starts_with("cpu "))?;
    let fields: Vec<u64> = line
        .split_whitespace()
        .skip(1)
        .filter_map(|f| f.parse().ok())
        .collect();
    if fields.len() < 4 {
        return None;
    }
    let total: u64 = fields.iter().take(8).sum();
    // idle and iowait are the fourth and fifth fields.
    let idle = fields[3] + fields.get(4).copied().unwrap_or(0);
    Some((total.saturating_sub(idle), total))
}

/// Guest CPU use between two `/proc/stat` readings, in percent of all vCPUs.
pub fn cpu_percent(before: (u64, u64), after: (u64, u64)) -> Option<f64> {
    let total = after.1.checked_sub(before.1)?;
    let busy = after.0.checked_sub(before.0)?;
    (total > 0).then(|| busy as f64 * 100.0 / total as f64)
}

/// A `/proc/meminfo` field, in kibibytes.
pub fn meminfo_kb(output: &str, key: &str) -> Option<u64> {
    output.lines().find_map(|l| {
        let rest = l.strip_prefix(key)?.strip_prefix(':')?;
        first_number(rest)
    })
}

/// `dumpsys thermalservice`: the `Thermal Status:` number (0 none .. 6 shutdown).
pub fn thermal_status(output: &str) -> Option<u64> {
    output
        .lines()
        .find_map(|l| l.trim().strip_prefix("Thermal Status:").and_then(first_number))
}

/// The compiler filter ART reports for a package, from `[status=...]`.
pub fn dexopt_status(output: &str) -> Option<String> {
    let start = output.find("[status=")? + "[status=".len();
    let rest = &output[start..];
    let end = rest.find(']')?;
    Some(rest[..end].to_string())
}

/// `wm size`: the size in effect (`Override size` when present).
pub fn wm_size(output: &str) -> Option<String> {
    let pick = |key: &str| {
        output
            .lines()
            .find_map(|l| l.trim().strip_prefix(key).map(|v| v.trim().to_string()))
    };
    pick("Override size:").or_else(|| pick("Physical size:"))
}

pub fn median(values: &[f64]) -> Option<f64> {
    if values.is_empty() {
        return None;
    }
    let mut sorted = values.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let mid = sorted.len() / 2;
    Some(if sorted.len() % 2 == 1 {
        sorted[mid]
    } else {
        (sorted[mid - 1] + sorted[mid]) / 2.0
    })
}

/// Percentage change from `before` to `after`; `None` when `before` is zero.
pub fn percent_change(before: f64, after: f64) -> Option<f64> {
    (before != 0.0).then(|| (after - before) * 100.0 / before)
}

/// An address the person typed: `192.0.2.20` or `192.0.2.20:5555`.
pub fn normalise_address(input: &str) -> Option<String> {
    let input = input.trim();
    if input.is_empty() || input.contains(char::is_whitespace) {
        return None;
    }
    let ok = |c: char| c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == ':';
    if !input.chars().all(ok) {
        return None;
    }
    Some(if input.contains(':') {
        input.to_string()
    } else {
        format!("{input}:5555")
    })
}

/// A package name is what Android allows and nothing a shell reads as syntax.
pub fn valid_package(name: &str) -> bool {
    !name.is_empty()
        && name.contains('.')
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_')
}

#[cfg(test)]
mod tests {
    use super::*;

    const AM_START: &str = "Starting: Intent { cmp=com.example.game/.MainActivity }\n\
Status: ok\nLaunchState: COLD\nActivity: com.example.game/.MainActivity\n\
TotalTime: 2843\nWaitTime: 2861\nComplete\n";

    #[test]
    fn launch_time_and_state() {
        assert_eq!(launch_total_ms(AM_START), Some(2843));
        assert_eq!(launch_state(AM_START).as_deref(), Some("COLD"));
        assert_eq!(launch_total_ms("Error: Activity class does not exist."), None);
    }

    #[test]
    fn launcher_component_is_the_last_component_line() {
        let out = "priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=true\n\
com.example.game/.MainActivity\n";
        assert_eq!(
            launcher_component(out).as_deref(),
            Some("com.example.game/.MainActivity")
        );
        assert_eq!(launcher_component("No activity found\n"), None);
    }

    #[test]
    fn packages_are_sorted_names() {
        let out = "package:org.b\npackage:com.a\n\n";
        assert_eq!(package_list(out), vec!["com.a", "org.b"]);
    }

    #[test]
    fn gfxinfo_adds_windows_and_keeps_worst_percentile() {
        let out = "Stats since: 1ns\nTotal frames rendered: 100\nJanky frames: 10 (10.00%)\n\
50th percentile: 9ms\n90th percentile: 20ms\n95th percentile: 30ms\n99th percentile: 61ms\n\
Total frames rendered: 20\nJanky frames: 5 (25.00%)\n50th percentile: 12ms\n\
90th percentile: 18ms\n95th percentile: 22ms\n99th percentile: 40ms\n";
        let info = gfxinfo(out).unwrap();
        assert_eq!(info.total_frames, 120);
        assert_eq!(info.janky_frames, 15);
        assert_eq!(info.p50_ms, Some(12));
        assert_eq!(info.p99_ms, Some(61));
        assert_eq!(gfxinfo("No process found for: com.x"), None);
    }

    #[test]
    fn timestats_picks_the_package_layer_with_most_frames() {
        let out = "SurfaceFlinger TimeStats:\nstatsStart = 1\n\
layerName = SurfaceView[com.example.game/.MainActivity](BLAST)#120\n\
packageName = com.example.game\ntotalFrames = 1750\ndroppedFrames = 3\naverageFPS = 58.312\n\
layerName = com.example.game/.MainActivity#118\ntotalFrames = 12\naverageFPS = 0.400\n\
layerName = StatusBar#70\ntotalFrames = 9000\naverageFPS = 60.000\n";
        let layers = timestats_layers(out);
        assert_eq!(layers.len(), 3);
        let best = busiest_layer(&layers, "com.example.game").unwrap();
        assert_eq!(best.total_frames, 1750);
        assert_eq!(best.average_fps, Some(58.312));
        assert!(busiest_layer(&layers, "com.other").is_none());
    }

    #[test]
    fn cpu_use_from_two_readings() {
        let a = proc_stat("cpu  100 0 100 800 0 0 0 0 0 0\ncpu0 1 2 3 4\n").unwrap();
        let b = proc_stat("cpu  300 0 200 1500 0 0 0 0 0 0\n").unwrap();
        assert_eq!(a, (200, 1000));
        assert_eq!(b, (500, 2000));
        assert_eq!(cpu_percent(a, b), Some(30.0));
        assert_eq!(cpu_percent(b, b), None);
        assert_eq!(proc_stat("garbage"), None);
    }

    #[test]
    fn meminfo_thermal_dexopt_and_size() {
        let mem = "MemTotal:        3980000 kB\nMemAvailable:    2100000 kB\n";
        assert_eq!(meminfo_kb(mem, "MemTotal"), Some(3_980_000));
        assert_eq!(meminfo_kb(mem, "MemAvailable"), Some(2_100_000));
        assert_eq!(meminfo_kb(mem, "SwapTotal"), None);
        assert_eq!(thermal_status("IsStatusOverride: false\nThermal Status: 4\n"), Some(4));
        assert_eq!(
            dexopt_status("  arm64: [status=speed-profile] [reason=install]").as_deref(),
            Some("speed-profile")
        );
        assert_eq!(dexopt_status("nothing"), None);
        assert_eq!(
            wm_size("Physical size: 880x1912\nOverride size: 660x1434\n").as_deref(),
            Some("660x1434")
        );
    }

    #[test]
    fn statistics() {
        assert_eq!(median(&[3.0, 1.0, 2.0]), Some(2.0));
        assert_eq!(median(&[4.0, 1.0, 2.0, 3.0]), Some(2.5));
        assert_eq!(median(&[]), None);
        assert_eq!(percent_change(2000.0, 1500.0), Some(-25.0));
        assert_eq!(percent_change(0.0, 5.0), None);
    }

    #[test]
    fn addresses_and_packages_are_checked() {
        assert_eq!(normalise_address(" 192.0.2.20 ").as_deref(), Some("192.0.2.20:5555"));
        assert_eq!(normalise_address("198.51.100.5:5556").as_deref(), Some("198.51.100.5:5556"));
        assert_eq!(normalise_address("1.2.3.4; rm -rf /"), None);
        assert_eq!(normalise_address(""), None);
        assert!(valid_package("com.example.game_2"));
        assert!(!valid_package("com.example;reboot"));
        assert!(!valid_package("nodots"));
    }
}
