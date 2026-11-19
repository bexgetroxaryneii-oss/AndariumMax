// SPDX-License-Identifier: GPL-2.0-or-later

//! A measurement run as a small text file, and the comparison of two runs.
//! Every figure in a comparison is computed from the two files' own numbers.

use crate::parse::{median, percent_change};
use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::Path;

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Run {
    pub entries: BTreeMap<String, String>,
}

impl Run {
    pub fn set(&mut self, key: &str, value: impl ToString) {
        self.entries.insert(key.to_string(), clean(&value.to_string()));
    }

    pub fn set_series(&mut self, key: &str, values: &[f64]) {
        let text: Vec<String> = values.iter().map(|v| format_number(*v)).collect();
        self.set(key, text.join(","));
    }

    pub fn get(&self, key: &str) -> Option<&str> {
        self.entries.get(key).map(String::as_str)
    }

    /// The numbers of an entry; `None` unless every item is a number.
    pub fn numbers(&self, key: &str) -> Option<Vec<f64>> {
        let text = self.get(key)?;
        let parsed: Option<Vec<f64>> = text.split(',').map(|v| v.trim().parse().ok()).collect();
        parsed.filter(|v| !v.is_empty())
    }

    pub fn to_text(&self) -> String {
        let mut text = String::from("# AndariumMax result file. key<TAB>value, one per line.\n");
        for (key, value) in &self.entries {
            text.push_str(key);
            text.push('\t');
            text.push_str(value);
            text.push('\n');
        }
        text
    }

    pub fn from_text(text: &str) -> Run {
        let mut run = Run::default();
        for line in text.lines() {
            if line.starts_with('#') {
                continue;
            }
            if let Some((key, value)) = line.split_once('\t') {
                run.entries.insert(key.to_string(), value.to_string());
            }
        }
        run
    }

    pub fn save(&self, path: &Path) -> io::Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, self.to_text())
    }

    pub fn load(path: &Path) -> io::Result<Run> {
        Ok(Run::from_text(&fs::read_to_string(path)?))
    }
}

fn clean(value: &str) -> String {
    value.replace(['\t', '\n', '\r'], " ").trim().to_string()
}

pub fn format_number(value: f64) -> String {
    if value.fract() == 0.0 && value.abs() < 1e15 {
        format!("{value:.0}")
    } else {
        format!("{value:.2}")
    }
}

/// Which way is better for a measured key, by its prefix.
#[derive(Debug, PartialEq, Clone, Copy)]
pub enum Better {
    Lower,
    Higher,
}

pub fn direction(key: &str) -> Option<Better> {
    const LOWER: [&str; 5] = ["launch_ms.", "ui_janky_pct.", "ui_p50_ms.", "ui_p90_ms.", "ui_p99_ms."];
    const HIGHER: [&str; 3] = ["fps.", "sustained_fps_first.", "sustained_fps_last."];
    if LOWER.iter().any(|p| key.starts_with(p)) {
        Some(Better::Lower)
    } else if HIGHER.iter().any(|p| key.starts_with(p)) {
        Some(Better::Higher)
    } else {
        None
    }
}

#[derive(Debug, PartialEq)]
pub struct Row {
    pub key: String,
    pub before: f64,
    pub after: f64,
    pub change_pct: Option<f64>,
    pub verdict: &'static str,
}

/// The settings two runs must share for their figures to be comparable.
pub const CONDITION_KEYS: [&str; 5] = [
    "info.vcpus",
    "info.mem_total_kb",
    "info.display_size",
    "info.android",
    "info.build",
];

pub fn condition_differences(before: &Run, after: &Run) -> Vec<String> {
    CONDITION_KEYS
        .iter()
        .filter_map(|key| {
            let (a, b) = (before.get(key)?, after.get(key)?);
            (a != b).then(|| format!("{key}: {a} -> {b}"))
        })
        .collect()
}

/// One row per measured key both runs have, from the median of each side.
pub fn compare(before: &Run, after: &Run) -> Vec<Row> {
    let mut rows = Vec::new();
    for key in before.entries.keys() {
        let Some(better) = direction(key) else { continue };
        let (Some(a), Some(b)) = (before.numbers(key), after.numbers(key)) else { continue };
        let (Some(a), Some(b)) = (median(&a), median(&b)) else { continue };
        let change = percent_change(a, b);
        let verdict = match change {
            None => "n/a",
            // Under three percent is inside run-to-run noise for these tests.
            Some(c) if c.abs() < 3.0 => "same",
            Some(c) => match (better, c < 0.0) {
                (Better::Lower, true) | (Better::Higher, false) => "better",
                _ => "worse",
            },
        };
        rows.push(Row { key: key.clone(), before: a, after: b, change_pct: change, verdict });
    }
    rows
}

/// "YYYY-MM-DD HH:MM" in UTC for seconds since 1970.
pub fn utc_stamp(epoch_seconds: u64) -> String {
    let days = epoch_seconds / 86_400;
    let secs = epoch_seconds % 86_400;
    // Civil-from-days (proleptic Gregorian), valid for every date after 1970.
    let z = days as i64 + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + if month <= 2 { 1 } else { 0 };
    format!("{year:04}-{month:02}-{day:02} {:02}:{:02}", secs / 3600, secs % 3600 / 60)
}

/// A label as a file name: letters, digits, dash and underscore only.
pub fn file_label(label: &str) -> String {
    let cleaned: String = label
        .trim()
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
        .collect();
    if cleaned.is_empty() { "run".to_string() } else { cleaned }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run_with(pairs: &[(&str, &str)]) -> Run {
        let mut run = Run::default();
        for (k, v) in pairs {
            run.set(k, v);
        }
        run
    }

    #[test]
    fn text_round_trip_keeps_every_entry() {
        let mut run = run_with(&[("info.vcpus", "6"), ("note", "tab\there")]);
        run.set_series("launch_ms.com.a", &[2100.0, 1999.5]);
        let back = Run::from_text(&run.to_text());
        assert_eq!(back, run);
        assert_eq!(back.get("note"), Some("tab here"));
        assert_eq!(back.numbers("launch_ms.com.a"), Some(vec![2100.0, 1999.5]));
        assert_eq!(back.numbers("note"), None);
    }

    #[test]
    fn comparison_uses_medians_and_the_right_direction() {
        let before = run_with(&[
            ("launch_ms.com.a", "2000,2400,2200"),
            ("fps.com.a", "40"),
            ("ui_p90_ms.com.a", "30"),
            ("info.vcpus", "6"),
        ]);
        let after = run_with(&[
            ("launch_ms.com.a", "1700,1600,1650"),
            ("fps.com.a", "30"),
            ("ui_p90_ms.com.a", "30.5"),
            ("info.vcpus", "4"),
        ]);
        let rows = compare(&before, &after);
        let row = |key: &str| rows.iter().find(|r| r.key == key).unwrap();
        assert_eq!(row("launch_ms.com.a").before, 2200.0);
        assert_eq!(row("launch_ms.com.a").after, 1650.0);
        assert_eq!(row("launch_ms.com.a").change_pct, Some(-25.0));
        assert_eq!(row("launch_ms.com.a").verdict, "better");
        assert_eq!(row("fps.com.a").verdict, "worse");
        assert_eq!(row("ui_p90_ms.com.a").verdict, "same");
        assert!(rows.iter().all(|r| !r.key.starts_with("info.")));
        assert_eq!(condition_differences(&before, &after), vec!["info.vcpus: 6 -> 4"]);
    }

    #[test]
    fn a_key_only_one_run_has_is_not_compared() {
        let before = run_with(&[("fps.com.a", "40")]);
        let after = run_with(&[("fps.com.b", "50")]);
        assert!(compare(&before, &after).is_empty());
    }

    #[test]
    fn dates_and_labels() {
        assert_eq!(utc_stamp(0), "1970-01-01 00:00");
        assert_eq!(utc_stamp(1_795_125_240), "2026-11-19 21:54");
        assert_eq!(utc_stamp(951_782_400), "2000-02-29 00:00");
        assert_eq!(file_label(" my run #2 "), "my_run__2");
        assert_eq!(file_label(""), "run");
        assert_eq!(format_number(12.0), "12");
        assert_eq!(format_number(12.345), "12.35");
    }
}
