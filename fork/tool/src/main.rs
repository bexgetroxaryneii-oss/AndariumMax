// SPDX-License-Identifier: GPL-2.0-or-later

//! AndariumMax: measures and tunes the Android guest of Andarium from a
//! computer, over Andarium's "ADB over network". It changes nothing in
//! Andarium itself; every tuning it applies is one Android command that its
//! own menu undoes.

mod adb;
mod parse;
mod results;

use adb::Adb;
use results::Run;
use std::io::{self, BufRead, Write};
use std::path::{Path, PathBuf};
use std::thread::sleep;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const VERSION: &str = env!("CARGO_PKG_VERSION");
const CREDIT: &str = "Made by Claude Strife - X";

fn main() {
    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(Path::to_path_buf))
        .unwrap_or_else(|| PathBuf::from("."));
    println!("==========================================================");
    println!("  AndariumMax v{VERSION} - measure and tune Android on iPhone");
    println!("  {CREDIT}");
    println!("==========================================================");

    let Some(mut adb) = Adb::find(&exe_dir) else {
        println!();
        println!("  adb was not found. Run BUILD.bat again: it downloads adb");
        println!("  (Google's platform-tools) into the tools folder.");
        pause();
        return;
    };
    println!("  adb: {}", adb.program().display());
    let results_dir = exe_dir.join("results");

    loop {
        println!();
        match adb.serial() {
            Some(serial) => println!("  Connected to: {serial}"),
            None => println!("  Not connected yet - start with 1."),
        }
        println!("   1  Connect to Andarium");
        println!("   2  Show Android info");
        println!("   3  Quick benchmark   (5 cold launches + 60 s of frames, about 3 min)");
        println!("   4  Sustained test    (10 minutes of frames, CPU and heat)");
        println!("   5  Speed-compile an app (faster starts; undo with 6)");
        println!("   6  Undo speed-compile");
        println!("   7  Animation speed   (feel only, not performance)");
        println!("   8  Compare two saved results");
        println!("   9  How to connect (help)");
        println!("   0  Exit");
        let choice = ask("  Choose");
        let needs_device = matches!(choice.as_str(), "2" | "3" | "4" | "5" | "6" | "7");
        if needs_device && adb.serial().is_none() {
            println!("  Connect first (1).");
            continue;
        }
        match choice.as_str() {
            "1" => connect(&mut adb),
            "2" => show_info(&adb),
            "3" => quick_benchmark(&adb, &results_dir),
            "4" => sustained_test(&adb, &results_dir),
            "5" => speed_compile(&adb, true),
            "6" => speed_compile(&adb, false),
            "7" => animation_speed(&adb),
            "8" => compare_results(&results_dir),
            "9" => help(),
            "0" | "q" | "exit" => break,
            _ => println!("  Type a number from the list."),
        }
    }
}

fn ask(prompt: &str) -> String {
    print!("{prompt}: ");
    let _ = io::stdout().flush();
    let mut line = String::new();
    if io::stdin().lock().read_line(&mut line).unwrap_or(0) == 0 {
        return "0".to_string();
    }
    line.trim().to_string()
}

fn pause() {
    let _ = ask("  Press Enter to close");
}

fn help() {
    println!();
    println!("  On the iPhone, with Android running in Andarium:");
    println!("   a. Android Settings > About phone > tap Build number 7 times.");
    println!("   b. Android Settings > System > Developer options > USB debugging: on.");
    println!("   c. Andarium's own Settings (side keys) > Developer > ADB over network: on.");
    println!("      iOS asks for Local Network access once - allow it.");
    println!("   d. iPhone and this PC on the same Wi-Fi. The iPhone's address is in");
    println!("      iOS Settings > Wi-Fi > (i) > IP Address.");
    println!("   e. Here, choose 1 and type that address. Android then shows");
    println!("      'Allow USB debugging?' - tick Always allow, then Allow.");
    println!("  Keep Andarium on screen and the iPhone unlocked while a test runs:");
    println!("  Android is paused whenever Andarium leaves the foreground.");
    println!("  ADB over network turns itself off each time Android starts.");
}

fn connect(adb: &mut Adb) {
    let typed = ask("  iPhone IP address (four numbers with dots, from its Wi-Fi page)");
    let Some(address) = parse::normalise_address(&typed) else {
        println!("  That is not an address.");
        return;
    };
    println!("  Connecting to {address} ...");
    match adb.raw(&["connect", &address], 30) {
        Ok(text) => println!("  adb: {}", text.trim()),
        Err(e) => {
            println!("  {e}");
            return;
        }
    }
    adb.set_serial(Some(address));
    for attempt in 1..=15 {
        match adb.shell("getprop ro.build.version.release", 15) {
            Ok(text) if !text.trim().is_empty() => {
                println!("  Connected. Android {}.", text.trim());
                return;
            }
            _ => {
                println!("  Waiting for Android to allow this PC ({attempt}/15) - check the iPhone screen...");
                sleep(Duration::from_secs(4));
            }
        }
    }
    println!("  No answer. Choose 9 for the checklist, then try again.");
    adb.set_serial(None);
}

fn shell_or_note(adb: &Adb, command: &str, timeout_s: u64) -> Option<String> {
    match adb.shell(command, timeout_s) {
        Ok(text) => Some(text),
        Err(e) => {
            println!("    ({command}: {e})");
            None
        }
    }
}

/// The conditions a result is only comparable under.
fn record_info(adb: &Adb, run: &mut Run) {
    let prop = |name: &str| {
        adb.shell(&format!("getprop {name}"), 15)
            .map(|t| t.trim().to_string())
            .unwrap_or_default()
    };
    run.set("info.android", prop("ro.build.version.release"));
    run.set("info.build", prop("ro.build.display.id"));
    run.set("info.abi", prop("ro.product.cpu.abi"));
    if let Ok(text) = adb.shell("cat /proc/cpuinfo", 15) {
        let count = text.lines().filter(|l| l.starts_with("processor")).count();
        run.set("info.vcpus", count);
    }
    if let Ok(text) = adb.shell("cat /proc/meminfo", 15) {
        if let Some(kb) = parse::meminfo_kb(&text, "MemTotal") {
            run.set("info.mem_total_kb", kb);
        }
        if let Some(kb) = parse::meminfo_kb(&text, "MemAvailable") {
            run.set("info.mem_available_kb", kb);
        }
    }
    if let Ok(text) = adb.shell("wm size", 15) {
        if let Some(size) = parse::wm_size(&text) {
            run.set("info.display_size", size);
        }
    }
    if let Ok(text) = adb.shell("dumpsys thermalservice", 20) {
        if let Some(status) = parse::thermal_status(&text) {
            run.set("info.thermal_status_at_start", status);
        }
    }
}

fn show_info(adb: &Adb) {
    let mut run = Run::default();
    record_info(adb, &mut run);
    println!();
    for (key, value) in &run.entries {
        println!("  {:<32} {}", key.trim_start_matches("info."), value);
    }
    println!("  (vCPUs, memory and display size are what Andarium gave this start.)");
}

fn pick_package(adb: &Adb) -> Option<String> {
    let list = shell_or_note(adb, "pm list packages -3", 30)?;
    let packages = parse::package_list(&list);
    if packages.is_empty() {
        println!("  No installed apps found. Install one in Andarium first (Install APK).");
        return None;
    }
    println!();
    for (index, name) in packages.iter().enumerate() {
        println!("   {:>2}  {name}", index + 1);
    }
    let typed = ask("  App number");
    let index: usize = typed.parse().ok()?;
    let name = packages.get(index.checked_sub(1)?)?.clone();
    parse::valid_package(&name).then_some(name)
}

fn launcher_of(adb: &Adb, package: &str) -> Option<String> {
    let command =
        format!("cmd package resolve-activity --brief -c android.intent.category.LAUNCHER {package}");
    let text = shell_or_note(adb, &command, 20)?;
    let component = parse::launcher_component(&text);
    if component.is_none() {
        println!("  This app has no launcher activity.");
    }
    component
}

fn cpu_over(adb: &Adb, seconds: u64) -> Option<f64> {
    let before = parse::proc_stat(&adb.shell("cat /proc/stat", 15).ok()?)?;
    sleep(Duration::from_secs(seconds));
    let after = parse::proc_stat(&adb.shell("cat /proc/stat", 15).ok()?)?;
    parse::cpu_percent(before, after)
}

fn now_stamp() -> (u64, String) {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    (seconds, results::utc_stamp(seconds))
}

fn save_run(run: &Run, dir: &Path, kind: &str, label: &str) {
    let (seconds, _) = now_stamp();
    let name = format!("{seconds}-{}-{kind}.txt", results::file_label(label));
    let path = dir.join(name);
    match run.save(&path) {
        Ok(()) => println!("  Saved: {}", path.display()),
        Err(e) => println!("  Could not save the result: {e}"),
    }
}

fn start_run(adb: &Adb, kind: &str, package: &str) -> (Run, String) {
    let label = ask("  Name this run (for example: baseline, 4cpu, jit-on)");
    let mut run = Run::default();
    let (_, stamp) = now_stamp();
    run.set("run.label", &label);
    run.set("run.kind", kind);
    run.set("run.package", package);
    run.set("run.date_utc", stamp);
    run.set("run.tool", format!("AndariumMax {VERSION}"));
    run.set("run.andarium_settings", ask(
        "  Andarium settings now (vCPUs / RAM / resolution / JIT on or off) - type what you set",
    ));
    record_info(adb, &mut run);
    (run, label)
}

fn quick_benchmark(adb: &Adb, dir: &Path) {
    let Some(package) = pick_package(adb) else { return };
    let Some(component) = launcher_of(adb, &package) else { return };
    let (mut run, label) = start_run(adb, "quick", &package);

    if let Some(text) = shell_or_note(adb, &format!("dumpsys package {package}"), 30) {
        if let Some(status) = parse::dexopt_status(&text) {
            println!("  ART compile state of the app: {status}");
            run.set(&format!("info.dexopt.{package}"), status);
        }
    }

    println!();
    println!("  Part 1 of 2: 5 cold launches. Do not touch the iPhone.");
    let mut launches = Vec::new();
    for round in 1..=5 {
        let _ = adb.shell(&format!("am force-stop {package}"), 20);
        sleep(Duration::from_secs(3));
        let command = format!("am start-activity -W -S -n {component}");
        match adb.shell(&command, 180) {
            Ok(text) => match parse::launch_total_ms(&text) {
                Some(ms) => {
                    let state = parse::launch_state(&text).unwrap_or_else(|| "?".to_string());
                    println!("    launch {round}/5: {ms} ms ({state})");
                    launches.push(ms as f64);
                }
                None => println!("    launch {round}/5: Android gave no time: {}", text.trim()),
            },
            Err(e) => println!("    launch {round}/5: {e}"),
        }
        sleep(Duration::from_secs(4));
    }
    if !launches.is_empty() {
        run.set_series(&format!("launch_ms.{package}"), &launches);
    }

    println!();
    println!("  Part 2 of 2: 60 s of frames. The app is open now: play or scroll");
    println!("  in it the same way for every run you want to compare.");
    let _ = ask("  Press Enter when you are in the part to measure");
    measure_frames(adb, &package, 60, &mut run);

    print_run_summary(&run, &package);
    save_run(&run, dir, "quick", &label);
}

/// Counts the frames of `seconds`: the UI toolkit's own (gfxinfo) and what
/// reached the display (SurfaceFlinger TimeStats), plus guest CPU use.
fn measure_frames(adb: &Adb, package: &str, seconds: u64, run: &mut Run) {
    let _ = adb.shell(&format!("dumpsys gfxinfo {package} reset"), 30);
    let _ = adb.shell("dumpsys SurfaceFlinger --timestats -disable -clear -enable", 30);
    let cpu_before = adb
        .shell("cat /proc/stat", 15)
        .ok()
        .and_then(|t| parse::proc_stat(&t));
    let step = 10;
    let mut waited = 0;
    while waited < seconds {
        let chunk = step.min(seconds - waited);
        sleep(Duration::from_secs(chunk));
        waited += chunk;
        println!("    measuring... {waited}/{seconds} s");
    }
    let cpu_after = adb
        .shell("cat /proc/stat", 15)
        .ok()
        .and_then(|t| parse::proc_stat(&t));
    if let (Some(a), Some(b)) = (cpu_before, cpu_after) {
        if let Some(pct) = parse::cpu_percent(a, b) {
            run.set_series("guest_cpu_pct", &[pct]);
        }
    }
    if let Some(text) = shell_or_note(adb, "dumpsys SurfaceFlinger --timestats -dump", 30) {
        let layers = parse::timestats_layers(&text);
        match parse::busiest_layer(&layers, package) {
            Some(layer) => {
                run.set_series(&format!("display_frames.{package}"), &[layer.total_frames as f64]);
                // Frames over the measured time, not TimeStats' own average,
                // so every run divides by the same clock.
                let fps = layer.total_frames as f64 / seconds as f64;
                run.set_series(&format!("fps.{package}"), &[fps]);
            }
            None => println!("    (no display layer of the app reported frames)"),
        }
    }
    let _ = adb.shell("dumpsys SurfaceFlinger --timestats -disable", 30);
    if let Some(text) = shell_or_note(adb, &format!("dumpsys gfxinfo {package}"), 30) {
        if let Some(info) = parse::gfxinfo(&text) {
            if info.total_frames > 0 {
                let janky = info.janky_frames as f64 * 100.0 / info.total_frames as f64;
                run.set_series(&format!("ui_frames.{package}"), &[info.total_frames as f64]);
                run.set_series(&format!("ui_janky_pct.{package}"), &[janky]);
                for (name, value) in [("p50", info.p50_ms), ("p90", info.p90_ms), ("p99", info.p99_ms)] {
                    if let Some(ms) = value {
                        run.set_series(&format!("ui_{name}_ms.{package}"), &[ms as f64]);
                    }
                }
            }
        }
    }
}

fn print_run_summary(run: &Run, package: &str) {
    println!();
    println!("  ---- result ----");
    let show = |title: &str, key: String, unit: &str| {
        if let Some(values) = run.numbers(&key) {
            if let Some(mid) = parse::median(&values) {
                println!("  {title:<34} {} {unit}", results::format_number(mid));
            }
        }
    };
    show("Cold launch (median of runs)", format!("launch_ms.{package}"), "ms");
    show("Frames shown per second", format!("fps.{package}"), "fps");
    show("UI frames janky", format!("ui_janky_pct.{package}"), "%");
    show("UI frame time, 90th percentile", format!("ui_p90_ms.{package}"), "ms");
    show("Android CPU use (all vCPUs)", "guest_cpu_pct".to_string(), "%");
    println!("  A figure that is missing was not reported by Android for this app.");
}

fn sustained_test(adb: &Adb, dir: &Path) {
    let Some(package) = pick_package(adb) else { return };
    let (mut run, label) = start_run(adb, "sustained", &package);
    println!();
    println!("  Open the app on the iPhone and get into steady play (a looping");
    println!("  benchmark or a demo scene is best). This runs 10 minutes.");
    let _ = ask("  Press Enter to start");

    let (mut fps_series, mut cpu_series, mut heat_series) = (Vec::new(), Vec::new(), Vec::new());
    let interval = 30u64;
    let rounds = 20;
    for round in 1..=rounds {
        let _ = adb.shell("dumpsys SurfaceFlinger --timestats -disable -clear -enable", 30);
        let cpu = cpu_over(adb, interval);
        let fps = adb
            .shell("dumpsys SurfaceFlinger --timestats -dump", 30)
            .ok()
            .and_then(|text| {
                let layers = parse::timestats_layers(&text);
                parse::busiest_layer(&layers, &package).map(|l| l.total_frames as f64 / interval as f64)
            });
        let heat = adb
            .shell("dumpsys thermalservice", 20)
            .ok()
            .and_then(|t| parse::thermal_status(&t));
        let text = |v: Option<f64>| v.map(results::format_number).unwrap_or_else(|| "-".to_string());
        println!(
            "    {:>2}/{rounds}  {:>5} s   fps {:>6}   cpu {:>5} %   heat {}",
            round,
            round * interval,
            text(fps),
            text(cpu),
            heat.map(|h| h.to_string()).unwrap_or_else(|| "-".to_string())
        );
        if let Some(v) = fps { fps_series.push(v) }
        if let Some(v) = cpu { cpu_series.push(v) }
        if let Some(v) = heat { heat_series.push(v as f64) }
    }
    let _ = adb.shell("dumpsys SurfaceFlinger --timestats -disable", 30);

    if !fps_series.is_empty() {
        run.set_series(&format!("sustained_fps_series.{package}"), &fps_series);
        let third = (fps_series.len() / 3).max(1);
        let first = &fps_series[..third];
        let last = &fps_series[fps_series.len() - third..];
        run.set_series(&format!("sustained_fps_first.{package}"), first);
        run.set_series(&format!("sustained_fps_last.{package}"), last);
        if let (Some(a), Some(b)) = (parse::median(first), parse::median(last)) {
            println!();
            println!("  First third: {} fps. Last third: {} fps.", results::format_number(a), results::format_number(b));
            if let Some(change) = parse::percent_change(a, b) {
                println!("  Change over the run: {change:+.1} %  (a drop is heat or memory pressure).");
            }
        }
    } else {
        println!("  Android reported no frames for this app, so there is no fps figure.");
    }
    if !cpu_series.is_empty() {
        run.set_series("sustained_guest_cpu_pct_series", &cpu_series);
    }
    if !heat_series.is_empty() {
        run.set_series("sustained_thermal_status_series", &heat_series);
    }
    save_run(&run, dir, "sustained", &label);
}

fn speed_compile(adb: &Adb, on: bool) {
    let Some(package) = pick_package(adb) else { return };
    let before = adb
        .shell(&format!("dumpsys package {package}"), 30)
        .ok()
        .and_then(|t| parse::dexopt_status(&t));
    println!("  Now: {}", before.as_deref().unwrap_or("unknown"));
    let command = if on {
        println!("  Compiling all of the app's code ahead of time. This can take");
        println!("  several minutes in Andarium; keep the iPhone on this screen.");
        format!("cmd package compile -m speed -f {package}")
    } else {
        println!("  Putting the app back to Android's own choice...");
        format!("cmd package compile --reset {package}")
    };
    match adb.shell(&command, 1800) {
        Ok(text) => println!("  Android: {}", text.trim()),
        Err(e) => {
            println!("  {e}");
            return;
        }
    }
    let after = adb
        .shell(&format!("dumpsys package {package}"), 30)
        .ok()
        .and_then(|t| parse::dexopt_status(&t));
    println!("  After: {}", after.as_deref().unwrap_or("unknown"));
    if on {
        println!("  Run the quick benchmark again and compare (8) to see what it did.");
    }
}

fn animation_speed(adb: &Adb) {
    println!("   1  Fast (0.5x)   2  Off (0)   3  Android default (1x)");
    let scale = match ask("  Choose").as_str() {
        "1" => "0.5",
        "2" => "0",
        "3" => "1",
        _ => return,
    };
    for name in ["window_animation_scale", "transition_animation_scale", "animator_duration_scale"] {
        if let Err(e) = adb.shell(&format!("settings put global {name} {scale}"), 20) {
            println!("  {e}");
            return;
        }
    }
    println!("  Animation scale is now {scale}. Screens change sooner; nothing runs faster.");
}

fn compare_results(dir: &Path) {
    let mut files: Vec<PathBuf> = std::fs::read_dir(dir)
        .map(|entries| {
            entries
                .filter_map(|e| e.ok().map(|e| e.path()))
                .filter(|p| p.extension().is_some_and(|x| x == "txt"))
                .collect()
        })
        .unwrap_or_default();
    files.sort();
    if files.len() < 2 {
        println!("  Two saved results are needed. Run a benchmark twice (3 or 4).");
        return;
    }
    println!();
    for (index, path) in files.iter().enumerate() {
        println!("   {:>2}  {}", index + 1, path.file_name().unwrap_or_default().to_string_lossy());
    }
    let pick = |prompt: &str| -> Option<Run> {
        let index: usize = ask(prompt).parse().ok()?;
        Run::load(files.get(index.checked_sub(1)?)?).ok()
    };
    let (Some(before), Some(after)) = (pick("  BEFORE (number)"), pick("  AFTER (number)")) else {
        println!("  Not a number from the list.");
        return;
    };
    println!();
    println!(
        "  BEFORE: {} [{}]   AFTER: {} [{}]",
        before.get("run.label").unwrap_or("?"),
        before.get("run.andarium_settings").unwrap_or("?"),
        after.get("run.label").unwrap_or("?"),
        after.get("run.andarium_settings").unwrap_or("?"),
    );
    let differences = results::condition_differences(&before, &after);
    if !differences.is_empty() {
        println!("  These differ between the runs (that may be what you are testing):");
        for line in &differences {
            println!("    {line}");
        }
    }
    let rows = results::compare(&before, &after);
    if rows.is_empty() {
        println!("  The two results share no measured figure (different app or test?).");
        return;
    }
    println!();
    println!("  {:<44} {:>10} {:>10} {:>9}  {}", "measure", "before", "after", "change", "");
    for row in rows {
        let change = row
            .change_pct
            .map(|c| format!("{c:+.1} %"))
            .unwrap_or_else(|| "n/a".to_string());
        println!(
            "  {:<44} {:>10} {:>10} {:>9}  {}",
            row.key,
            results::format_number(row.before),
            results::format_number(row.after),
            change,
            row.verdict
        );
    }
    println!("  Changes under 3 % count as the same. Repeat a run before trusting one result.");
}
