// SPDX-License-Identifier: GPL-2.0-or-later

//! Finds adb and runs it with a time limit.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

pub struct Adb {
    program: PathBuf,
    serial: Option<String>,
}

#[derive(Debug)]
pub enum AdbError {
    Spawn(String),
    TimedOut(u64),
    Failed(String),
}

impl std::fmt::Display for AdbError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AdbError::Spawn(e) => write!(f, "could not start adb: {e}"),
            AdbError::TimedOut(s) => write!(f, "adb gave no answer in {s} s"),
            AdbError::Failed(e) => write!(f, "adb failed: {}", e.trim()),
        }
    }
}

const ADB_NAME: &str = if cfg!(windows) { "adb.exe" } else { "adb" };

/// Where adb may be: beside the program, on the PATH, in the Android SDK.
pub fn candidates(exe_dir: &Path) -> Vec<PathBuf> {
    let mut list = vec![
        exe_dir.join("tools").join("platform-tools").join(ADB_NAME),
        exe_dir.join("platform-tools").join(ADB_NAME),
        PathBuf::from(ADB_NAME),
    ];
    if let Ok(local) = std::env::var("LOCALAPPDATA") {
        list.push(
            PathBuf::from(local)
                .join("Android")
                .join("Sdk")
                .join("platform-tools")
                .join(ADB_NAME),
        );
    }
    if let Ok(home) = std::env::var("ANDROID_HOME") {
        list.push(PathBuf::from(home).join("platform-tools").join(ADB_NAME));
    }
    list
}

impl Adb {
    /// The first candidate that answers `adb version`.
    pub fn find(exe_dir: &Path) -> Option<Adb> {
        candidates(exe_dir).into_iter().find_map(|program| {
            let adb = Adb { program, serial: None };
            adb.raw(&["version"], 20).ok().map(|_| adb)
        })
    }

    pub fn program(&self) -> &Path {
        &self.program
    }

    pub fn serial(&self) -> Option<&str> {
        self.serial.as_deref()
    }

    pub fn set_serial(&mut self, serial: Option<String>) {
        self.serial = serial;
    }

    /// Runs adb with these arguments, without naming a device.
    pub fn raw(&self, args: &[&str], timeout_s: u64) -> Result<String, AdbError> {
        run(&self.program, args, timeout_s)
    }

    /// Runs one shell command line in the guest.
    pub fn shell(&self, command: &str, timeout_s: u64) -> Result<String, AdbError> {
        let mut args: Vec<&str> = Vec::new();
        if let Some(serial) = &self.serial {
            args.push("-s");
            args.push(serial);
        }
        args.push("shell");
        args.push(command);
        run(&self.program, &args, timeout_s)
    }
}

fn run(program: &Path, args: &[&str], timeout_s: u64) -> Result<String, AdbError> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| AdbError::Spawn(e.to_string()))?;

    // Drain both pipes on their own threads so a long answer never blocks adb.
    let mut out = child.stdout.take().expect("stdout is piped");
    let mut err = child.stderr.take().expect("stderr is piped");
    let out_thread = thread::spawn(move || {
        let mut text = Vec::new();
        let _ = out.read_to_end(&mut text);
        text
    });
    let err_thread = thread::spawn(move || {
        let mut text = Vec::new();
        let _ = err.read_to_end(&mut text);
        text
    });

    let deadline = Instant::now() + Duration::from_secs(timeout_s);
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() >= deadline => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(AdbError::TimedOut(timeout_s));
            }
            Ok(None) => thread::sleep(Duration::from_millis(50)),
            Err(e) => return Err(AdbError::Spawn(e.to_string())),
        }
    };
    let stdout = String::from_utf8_lossy(&out_thread.join().unwrap_or_default()).replace('\r', "");
    let stderr = String::from_utf8_lossy(&err_thread.join().unwrap_or_default()).replace('\r', "");
    if status.success() {
        Ok(stdout)
    } else {
        Err(AdbError::Failed(if stderr.trim().is_empty() { stdout } else { stderr }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn looks_beside_the_program_first() {
        let list = candidates(Path::new("base"));
        assert!(list[0].starts_with(Path::new("base").join("tools")));
        assert!(list.iter().any(|p| p == Path::new(ADB_NAME)));
    }

    #[cfg(unix)]
    #[test]
    fn a_silent_command_is_ended_at_its_time_limit() {
        let started = Instant::now();
        let result = run(Path::new("sleep"), &["30"], 1);
        assert!(matches!(result, Err(AdbError::TimedOut(1))));
        assert!(started.elapsed() < Duration::from_secs(10));
    }

    #[cfg(unix)]
    #[test]
    fn output_and_failure_are_told_apart() {
        assert_eq!(run(Path::new("echo"), &["hi"], 5).unwrap().trim(), "hi");
        assert!(matches!(run(Path::new("false"), &[], 5), Err(AdbError::Failed(_))));
        assert!(matches!(
            run(Path::new("no-such-program-here"), &[], 5),
            Err(AdbError::Spawn(_))
        ));
    }
}
