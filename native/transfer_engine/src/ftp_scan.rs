// Gene - Nov, 25, 2026: Native Rust FTP local directory scanner (verifies root containment
// once per directory instead of per-file canonicalize) and OS birthtime lookup.

use std::ffi::CString;
use std::fmt::Write as _;
use std::fs;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};

use crate::common::{
    c_str_to_string, push_json_escaped, resolve_within_root, system_time_to_epoch_ms,
};

struct ScannedFile {
    path: String,
    size: u64,
    modified_ms: i64,
    created_ms: i64,
}

struct FtpScanResult {
    files: Vec<ScannedFile>,
    errors: Vec<String>,
}

// Gene - Nov, 26, 2026: Added cooperative stop_requested cancellation on destroy and unstable sort for FTP scan.
// pub struct FtpScanJob {
//     done: Arc<AtomicBool>,
//     result: Arc<Mutex<Option<FtpScanResult>>>,
//     handle: Option<JoinHandle<()>>,
// }
//
// fn run_ftp_scan(
//     dir_path: PathBuf,
//     root_path: PathBuf,
//     include_creation_time: bool,
// ) -> FtpScanResult {
pub struct FtpScanJob {
    done: Arc<AtomicBool>,
    stop_requested: Arc<AtomicBool>,
    result: Arc<Mutex<Option<FtpScanResult>>>,
    handle: Option<JoinHandle<()>>,
}

#[cfg(test)]
fn run_ftp_scan(
    dir_path: PathBuf,
    root_path: PathBuf,
    include_creation_time: bool,
) -> FtpScanResult {
    let never_stop = AtomicBool::new(false);
    run_ftp_scan_with_cancel(dir_path, root_path, include_creation_time, &never_stop)
}

fn run_ftp_scan_with_cancel(
    dir_path: PathBuf,
    root_path: PathBuf,
    include_creation_time: bool,
    stop_requested: &AtomicBool,
) -> FtpScanResult {
    let mut files = Vec::new();
    let mut errors = Vec::new();

    let canonical_root = match fs::canonicalize(&root_path) {
        Ok(p) => p,
        Err(e) => {
            errors.push(format!(
                "Failed scanning {}: {e}",
                dir_path.display()
            ));
            return FtpScanResult { files, errors };
        }
    };

    if !resolve_within_root(&canonical_root, &dir_path) {
        return FtpScanResult { files, errors };
    }

    let entries = match fs::read_dir(&dir_path) {
        Ok(iter) => iter,
        Err(e) => {
            errors.push(format!(
                "Failed scanning {}: {e}",
                dir_path.display()
            ));
            return FtpScanResult { files, errors };
        }
    };

    for entry_res in entries {
        // Gene - Nov, 26, 2026: Abort scan promptly when stop_requested is set.
        if stop_requested.load(Ordering::Acquire) {
            return FtpScanResult {
                files: Vec::new(),
                errors: Vec::new(),
            };
        }
        let entry = match entry_res {
            Ok(e) => e,
            Err(e) => {
                errors.push(format!("Failed scanning {}: {e}", dir_path.display()));
                continue;
            }
        };

        let ft = match entry.file_type() {
            Ok(t) => t,
            Err(_) => continue,
        };
        // Non-symlink regular file inside an already-verified directory.
        if !ft.is_file() {
            continue;
        }

        let entry_path = entry.path();
        match entry.metadata() {
            Ok(meta) if meta.is_file() => {
                let size = meta.len();
                let modified_ms = meta
                    .modified()
                    .map(system_time_to_epoch_ms)
                    .unwrap_or(0);
                let created_ms = if include_creation_time {
                    meta.created()
                        .map(system_time_to_epoch_ms)
                        .unwrap_or(modified_ms)
                } else {
                    modified_ms
                };
                files.push(ScannedFile {
                    path: entry_path.to_string_lossy().into_owned(),
                    size,
                    modified_ms,
                    created_ms,
                });
            }
            Ok(_) => {}
            Err(e) => {
                errors.push(format!("Failed to stat {}: {e}", entry_path.display()));
            }
        }
    }

    // files.sort_by(|a, b| a.path.cmp(&b.path));
    // Gene - Nov, 26, 2026: Use sort_unstable_by for faster deterministic path sorting.
    files.sort_unstable_by(|a, b| a.path.cmp(&b.path));
    FtpScanResult { files, errors }
}

fn build_ftp_scan_json(res: &FtpScanResult) -> String {
    let mut json = String::with_capacity(256 + res.files.len() * 96);
    json.push_str("{\"done\":true,\"files\":[");
    for (idx, f) in res.files.iter().enumerate() {
        if idx > 0 {
            json.push(',');
        }
        json.push_str("{\"path\":");
        push_json_escaped(&mut json, &f.path);
        let _ = write!(
            json,
            ",\"size\":{},\"modifiedMs\":{},\"createdMs\":{}}}",
            f.size, f.modified_ms, f.created_ms
        );
    }
    json.push_str("],\"errors\":[");
    for (idx, err) in res.errors.iter().enumerate() {
        if idx > 0 {
            json.push(',');
        }
        push_json_escaped(&mut json, err);
    }
    json.push_str("]}");
    json
}

#[no_mangle]
pub unsafe extern "C" fn ftp_scan_start(
    dir_path: *const c_char,
    root_path: *const c_char,
    include_creation_time: u8,
) -> *mut FtpScanJob {
    let res = catch_unwind(AssertUnwindSafe(|| {
        let dir = match c_str_to_string(dir_path) {
            Some(s) if !s.is_empty() => PathBuf::from(s),
            _ => return std::ptr::null_mut(),
        };
        let root = match c_str_to_string(root_path) {
            Some(s) if !s.is_empty() => PathBuf::from(s),
            _ => return std::ptr::null_mut(),
        };
        let include_created = include_creation_time != 0;

        let done = Arc::new(AtomicBool::new(false));
        // Gene - Nov, 26, 2026: Wire stop_requested cancellation into FtpScanJob start and destroy.
        let stop_requested = Arc::new(AtomicBool::new(false));
        let result = Arc::new(Mutex::new(None));
        let worker_done = Arc::clone(&done);
        let worker_stop = Arc::clone(&stop_requested);
        let worker_result = Arc::clone(&result);

        let handle = thread::Builder::new()
            .name("ftp_scan_worker".to_string())
            .spawn(move || {
                let scan_res = catch_unwind(AssertUnwindSafe(|| {
                    run_ftp_scan_with_cancel(dir, root, include_created, &worker_stop)
                }))
                .unwrap_or_else(|_| FtpScanResult {
                    files: Vec::new(),
                    errors: vec!["Unknown FTP scan panic".to_string()],
                });
                if let Ok(mut guard) = worker_result.lock() {
                    *guard = Some(scan_res);
                }
                worker_done.store(true, Ordering::Release);
            })
            .ok();

        match handle {
            Some(h) => Box::into_raw(Box::new(FtpScanJob {
                done,
                stop_requested,
                result,
                handle: Some(h),
            })),
            None => std::ptr::null_mut(),
        }
    }));

    res.unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn ftp_scan_poll(job: *mut FtpScanJob) -> *mut c_char {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return std::ptr::null_mut();
        }
        let job_ref = &*job;
        if !job_ref.done.load(Ordering::Acquire) {
            return std::ptr::null_mut();
        }
        let json = match job_ref.result.lock() {
            Ok(mut guard) => match guard.take() {
                Some(r) => build_ftp_scan_json(&r),
                None => "{\"done\":true,\"files\":[],\"errors\":[]}".to_string(),
            },
            Err(_) => "{\"done\":true,\"files\":[],\"errors\":[]}".to_string(),
        };
        match CString::new(json) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => std::ptr::null_mut(),
        }
    }));

    res.unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn ftp_scan_destroy(job: *mut FtpScanJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let mut boxed = Box::from_raw(job);
        // Gene - Nov, 26, 2026: Signal stop_requested before joining worker so cancelled scans exit promptly.
        boxed.stop_requested.store(true, Ordering::Release);
        if let Some(handle) = boxed.handle.take() {
            let _ = handle.join();
        }
    }));
}

#[no_mangle]
pub unsafe extern "C" fn native_file_creation_ms(path: *const c_char) -> i64 {
    let res = catch_unwind(AssertUnwindSafe(|| {
        let p = match c_str_to_string(path) {
            Some(s) if !s.is_empty() => PathBuf::from(s),
            _ => return i64::MIN,
        };
        match fs::metadata(&p).and_then(|m| m.created()) {
            Ok(created) => system_time_to_epoch_ms(created),
            Err(_) => i64::MIN,
        }
    }));

    res.unwrap_or(i64::MIN)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn make_temp_dir(prefix: &str) -> PathBuf {
        let mut dir = std::env::temp_dir();
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        dir.push(format!("{prefix}_{}_{nanos}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn scans_files_deterministically_and_returns_creation_ms() {
        let root = make_temp_dir("rust_ftp_scan");
        let sub = root.join("folder");
        fs::create_dir_all(&sub).unwrap();
        fs::write(sub.join("b.txt"), b"BB").unwrap();
        fs::write(sub.join("a.txt"), b"AAA").unwrap();

        let res = run_ftp_scan(sub.clone(), root.clone(), true);
        assert!(res.errors.is_empty());
        assert_eq!(res.files.len(), 2);
        assert!(res.files[0].path.ends_with("a.txt"));
        assert_eq!(res.files[0].size, 3);
        assert!(res.files[1].path.ends_with("b.txt"));
        assert_eq!(res.files[1].size, 2);

        let c_path = CString::new(res.files[0].path.as_str()).unwrap();
        let created = unsafe { native_file_creation_ms(c_path.as_ptr()) };
        assert!(created == i64::MIN || created > 0);

        let _ = fs::remove_dir_all(&root);
    }

    // Gene - Nov, 26, 2026: Verify ftp_scan aborts cleanly when stop_requested is pre-signaled.
    #[test]
    fn ftp_scan_respects_stop_requested_flag() {
        let root = make_temp_dir("rust_ftp_cancel");
        fs::write(root.join("file.txt"), b"DATA").unwrap();
        let stop = AtomicBool::new(true);
        let res = run_ftp_scan_with_cancel(root.clone(), root.clone(), false, &stop);
        assert!(res.files.is_empty());
        assert!(res.errors.is_empty());
        let _ = fs::remove_dir_all(&root);
    }
}
