// Gene - Nov, 25, 2026: Native Rust iterative post-order file deletion engine with
// O(log N) binary-search date range matching and symlink containment.

use std::collections::{HashSet, VecDeque};
use std::ffi::CString;
use std::fmt::Write as _;
use std::fs;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};

use crate::common::{
    c_str_to_string, normalize_lexical, path_basename, push_json_escaped, resolve_within_root,
    system_time_to_epoch_ms, MAX_QUEUED_LOGS,
};

#[repr(C)]
pub struct DeleteConfigC {
    pub target_path: *const c_char,
    pub log_interval: u64,
    pub ranges_ptr: *const i64,
    pub ranges_len: usize,
}

struct DeleteUiState {
    current_dir_name: String,
    critical_error: Option<String>,
    logs: VecDeque<String>,
    error_logs: VecDeque<String>,
}

struct DeleteSharedState {
    files_scanned: AtomicU64,
    deleted: AtomicU64,
    errors: AtomicU64,
    stop_requested: AtomicBool,
    done: AtomicBool,
    ui: Mutex<DeleteUiState>,
}

pub struct DeleteJob {
    state: Arc<DeleteSharedState>,
    handle: Option<JoinHandle<()>>,
}

impl DeleteSharedState {
    fn new() -> Self {
        Self {
            files_scanned: AtomicU64::new(0),
            deleted: AtomicU64::new(0),
            errors: AtomicU64::new(0),
            stop_requested: AtomicBool::new(false),
            done: AtomicBool::new(false),
            ui: Mutex::new(DeleteUiState {
                current_dir_name: String::new(),
                critical_error: None,
                logs: VecDeque::new(),
                error_logs: VecDeque::new(),
            }),
        }
    }

    fn push_log(&self, line: String) {
        if let Ok(mut ui) = self.ui.lock() {
            if ui.logs.len() >= MAX_QUEUED_LOGS {
                ui.logs.pop_front();
            }
            ui.logs.push_back(line);
        }
    }

    fn push_error_log(&self, line: String) {
        if let Ok(mut ui) = self.ui.lock() {
            if ui.error_logs.len() >= MAX_QUEUED_LOGS {
                ui.error_logs.pop_front();
            }
            ui.error_logs.push_back(line);
        }
    }

    fn set_current_dir(&self, name: &str) {
        if let Ok(mut ui) = self.ui.lock() {
            ui.current_dir_name.clear();
            ui.current_dir_name.push_str(name);
        }
    }

    fn set_critical_error(&self, err: String) {
        if let Ok(mut ui) = self.ui.lock() {
            ui.critical_error = Some(err);
        }
    }
}

enum WalkStep {
    EnterDir(PathBuf),
    TryRemoveEmpty(PathBuf),
}

fn matches_any_range(epoch_ms: i64, ranges: &[(i64, i64)]) -> bool {
    if ranges.is_empty() {
        return false;
    }
    let idx = ranges.partition_point(|&(start, _)| start <= epoch_ms);
    if idx == 0 {
        return false;
    }
    let (start, end) = ranges[idx - 1];
    epoch_ms >= start && epoch_ms < end
}

fn check_and_delete_file(
    file_path: &std::path::Path,
    known_meta: Option<fs::Metadata>,
    ranges: &[(i64, i64)],
    log_interval: u64,
    state: &DeleteSharedState,
) {
    state.files_scanned.fetch_add(1, Ordering::Relaxed);
    let file_name = path_basename(file_path);

    let meta = match known_meta {
        Some(m) => m,
        None => match fs::metadata(file_path) {
            Ok(m) => m,
            Err(e) => {
                state.errors.fetch_add(1, Ordering::Relaxed);
                state.push_error_log(format!("✗ Error checking {file_name}: {e}"));
                return;
            }
        },
    };

    let modified = match meta.modified() {
        Ok(m) => m,
        Err(e) => {
            state.errors.fetch_add(1, Ordering::Relaxed);
            state.push_error_log(format!("✗ Error checking {file_name}: {e}"));
            return;
        }
    };

    let modified_ms = system_time_to_epoch_ms(modified);
    if !matches_any_range(modified_ms, ranges) {
        return;
    }

    match fs::remove_file(file_path) {
        Ok(()) => {
            let count = state.deleted.fetch_add(1, Ordering::Relaxed) + 1;
            if log_interval == 1 {
                state.push_log(format!("✓ Deleted: {file_name}"));
            } else if log_interval > 0 && count % log_interval == 0 {
                state.push_log(format!(
                    "✓ Deleted {log_interval} files (total: {count}) – latest: {file_name}"
                ));
            }
        }
        Err(e) => {
            state.errors.fetch_add(1, Ordering::Relaxed);
            state.push_error_log(format!("✗ Failed to delete {file_name}: {e}"));
        }
    }
}

fn run_delete(
    target_path: PathBuf,
    ranges: Vec<(i64, i64)>,
    log_interval: u64,
    state: Arc<DeleteSharedState>,
) {
    let canonical_root = match fs::canonicalize(&target_path) {
        Ok(p) => p,
        Err(e) => {
            state.set_critical_error(format!(
                "Failed to access target directory {}: {e}",
                target_path.display()
            ));
            state.done.store(true, Ordering::Release);
            return;
        }
    };

    let norm_target_root = normalize_lexical(&target_path);
    let mut visited_dirs: HashSet<PathBuf> = HashSet::new();
    let mut stack: Vec<WalkStep> = Vec::new();
    stack.push(WalkStep::EnterDir(target_path));

    while let Some(step) = stack.pop() {
        if state.stop_requested.load(Ordering::Acquire) {
            break;
        }

        match step {
            WalkStep::EnterDir(dir) => {
                let canonical_dir =
                    fs::canonicalize(&dir).unwrap_or_else(|_| normalize_lexical(&dir));
                if !visited_dirs.insert(canonical_dir) {
                    continue;
                }

                let dir_name = path_basename(&dir);
                state.set_current_dir(&dir_name);

                let entries = match fs::read_dir(&dir) {
                    Ok(iter) => iter,
                    Err(e) => {
                        state.errors.fetch_add(1, Ordering::Relaxed);
                        state.push_error_log(format!("✗ Error scanning directory: {e}"));
                        continue;
                    }
                };

                let is_root = normalize_lexical(&dir) == norm_target_root;
                if !is_root {
                    stack.push(WalkStep::TryRemoveEmpty(dir.clone()));
                }

                let mut subdirs: Vec<PathBuf> = Vec::new();

                for entry_res in entries {
                    if state.stop_requested.load(Ordering::Acquire) {
                        break;
                    }

                    let entry = match entry_res {
                        Ok(e) => e,
                        Err(e) => {
                            state.errors.fetch_add(1, Ordering::Relaxed);
                            state.push_error_log(format!("✗ Error scanning directory: {e}"));
                            continue;
                        }
                    };

                    let entry_path = entry.path();
                    let file_type = match entry.file_type() {
                        Ok(ft) => ft,
                        Err(_) => continue,
                    };

                    if file_type.is_file() {
                        let meta = entry.metadata().ok();
                        check_and_delete_file(&entry_path, meta, &ranges, log_interval, &state);
                    } else if file_type.is_dir() {
                        subdirs.push(entry_path);
                    } else if file_type.is_symlink() {
                        if !resolve_within_root(&canonical_root, &entry_path) {
                            state.push_log(format!(
                                "ℹ Skipped link pointing outside the target: {}",
                                path_basename(&entry_path)
                            ));
                            continue;
                        }
                        if let Ok(target_meta) = fs::metadata(&entry_path) {
                            if target_meta.is_dir() {
                                subdirs.push(entry_path);
                            } else if target_meta.is_file() {
                                check_and_delete_file(
                                    &entry_path,
                                    Some(target_meta),
                                    &ranges,
                                    log_interval,
                                    &state,
                                );
                            }
                        }
                    }
                }

                if !subdirs.is_empty() && !state.stop_requested.load(Ordering::Acquire) {
                    subdirs.sort_by(|a, b| path_basename(a).cmp(&path_basename(b)));
                    for sub in subdirs.into_iter().rev() {
                        stack.push(WalkStep::EnterDir(sub));
                    }
                }
            }
            WalkStep::TryRemoveEmpty(dir) => {
                let is_empty = fs::read_dir(&dir)
                    .map(|mut iter| iter.next().is_none())
                    .unwrap_or(false);
                if is_empty {
                    let dir_name = path_basename(&dir);
                    match fs::remove_dir(&dir) {
                        Ok(()) => {
                            state.push_log(format!("✓ Deleted empty folder: {dir_name}"));
                        }
                        Err(e) => {
                            state.push_error_log(format!(
                                "✗ Failed to delete folder {dir_name}: {e}"
                            ));
                        }
                    }
                }
            }
        }
    }

    state.done.store(true, Ordering::Release);
}

fn build_delete_poll_json(state: &DeleteSharedState) -> String {
    let files_scanned = state.files_scanned.load(Ordering::Relaxed);
    let deleted = state.deleted.load(Ordering::Relaxed);
    let errors = state.errors.load(Ordering::Relaxed);
    let is_done = state.done.load(Ordering::Acquire);

    let (current_dir_name, critical_error, logs, error_logs) = match state.ui.lock() {
        Ok(mut ui) => (
            ui.current_dir_name.clone(),
            ui.critical_error.take(),
            ui.logs.drain(..).collect::<Vec<_>>(),
            ui.error_logs.drain(..).collect::<Vec<_>>(),
        ),
        Err(_) => (String::new(), None, Vec::new(), Vec::new()),
    };

    let mut json = String::with_capacity(256);
    let _ = write!(
        json,
        "{{\"filesScanned\":{files_scanned},\"deleted\":{deleted},\"errors\":{errors},\"currentDirName\":"
    );
    push_json_escaped(&mut json, &current_dir_name);
    let _ = write!(json, ",\"isDone\":{is_done},\"criticalError\":");
    match critical_error {
        Some(ref c) => push_json_escaped(&mut json, c),
        None => json.push_str("null"),
    }
    json.push_str(",\"logs\":[");
    for (idx, line) in logs.iter().enumerate() {
        if idx > 0 {
            json.push(',');
        }
        push_json_escaped(&mut json, line);
    }
    json.push_str("],\"errorLogs\":[");
    for (idx, line) in error_logs.iter().enumerate() {
        if idx > 0 {
            json.push(',');
        }
        push_json_escaped(&mut json, line);
    }
    json.push_str("]}");
    json
}

#[no_mangle]
pub unsafe extern "C" fn delete_engine_start(cfg: *const DeleteConfigC) -> *mut DeleteJob {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if cfg.is_null() {
            return std::ptr::null_mut();
        }
        let raw = &*cfg;
        let target_path = match c_str_to_string(raw.target_path) {
            Some(s) if !s.is_empty() => PathBuf::from(s),
            _ => return std::ptr::null_mut(),
        };
        let log_interval = if raw.log_interval == 0 {
            100
        } else {
            raw.log_interval
        };

        let mut ranges: Vec<(i64, i64)> = Vec::with_capacity(raw.ranges_len);
        if !raw.ranges_ptr.is_null() && raw.ranges_len > 0 {
            let slice = std::slice::from_raw_parts(raw.ranges_ptr, raw.ranges_len * 2);
            for pair in slice.chunks_exact(2) {
                ranges.push((pair[0], pair[1]));
            }
            ranges.sort_unstable_by_key(|&(start, _)| start);
        }

        let state = Arc::new(DeleteSharedState::new());
        let worker_state = Arc::clone(&state);

        let handle = thread::Builder::new()
            .name("delete_engine_worker".to_string())
            .spawn(move || {
                let state_for_panic = Arc::clone(&worker_state);
                let run_res = catch_unwind(AssertUnwindSafe(|| {
                    run_delete(target_path, ranges, log_interval, worker_state);
                }));
                if let Err(panic_info) = run_res {
                    let msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
                        (*s).to_string()
                    } else if let Some(s) = panic_info.downcast_ref::<String>() {
                        s.clone()
                    } else {
                        "Unknown delete worker panic".to_string()
                    };
                    state_for_panic.set_critical_error(msg);
                    state_for_panic.done.store(true, Ordering::Release);
                }
            })
            .ok();

        match handle {
            Some(h) => Box::into_raw(Box::new(DeleteJob {
                state,
                handle: Some(h),
            })),
            None => std::ptr::null_mut(),
        }
    }));

    res.unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn delete_engine_stop(job: *mut DeleteJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let job_ref = &*job;
        job_ref.state.stop_requested.store(true, Ordering::Release);
    }));
}

#[no_mangle]
pub unsafe extern "C" fn delete_engine_poll(job: *mut DeleteJob) -> *mut c_char {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return std::ptr::null_mut();
        }
        let job_ref = &*job;
        let json = build_delete_poll_json(&job_ref.state);
        match CString::new(json) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => std::ptr::null_mut(),
        }
    }));

    res.unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn delete_engine_destroy(job: *mut DeleteJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let mut boxed = Box::from_raw(job);
        boxed.state.stop_requested.store(true, Ordering::Release);
        if let Some(handle) = boxed.handle.take() {
            let _ = handle.join();
        }
    }));
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use std::time::{Duration, SystemTime, UNIX_EPOCH};

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
    fn deletes_matching_files_and_empty_subfolders_only() {
        let root = make_temp_dir("rust_delete_basic");
        let empty_after = root.join("empty_after");
        let keep_dir = root.join("keep_dir");
        fs::create_dir_all(&empty_after).unwrap();
        fs::create_dir_all(&keep_dir).unwrap();

        let match_f = File::create(empty_after.join("old.txt")).unwrap();
        let keep_f = File::create(keep_dir.join("new.txt")).unwrap();

        let t_match = UNIX_EPOCH + Duration::from_secs(1_580_000_000);
        let t_keep = UNIX_EPOCH + Duration::from_secs(1_700_000_000);
        match_f.set_modified(t_match).unwrap();
        keep_f.set_modified(t_keep).unwrap();
        drop(match_f);
        drop(keep_f);

        let ranges = vec![(1_577_836_800_000, 1_583_020_800_000)];
        let state = Arc::new(DeleteSharedState::new());
        run_delete(root.clone(), ranges, 1, Arc::clone(&state));

        assert_eq!(state.files_scanned.load(Ordering::Relaxed), 2);
        assert_eq!(state.deleted.load(Ordering::Relaxed), 1);
        assert!(!empty_after.exists());
        assert!(keep_dir.join("new.txt").exists());
        assert!(root.exists());

        let _ = fs::remove_dir_all(&root);
    }

    #[cfg(unix)]
    #[test]
    fn symlink_outside_target_is_never_deleted() {
        use std::os::unix::fs::symlink;

        let root = make_temp_dir("rust_delete_symlink");
        let target = root.join("target");
        let outside = root.join("outside");
        fs::create_dir_all(&target).unwrap();
        fs::create_dir_all(&outside).unwrap();

        let inside_f = File::create(target.join("inside.txt")).unwrap();
        let outside_f = File::create(outside.join("precious.txt")).unwrap();
        let t_match = UNIX_EPOCH + Duration::from_secs(1_580_000_000);
        inside_f.set_modified(t_match).unwrap();
        outside_f.set_modified(t_match).unwrap();
        symlink(&outside, target.join("escape_hatch")).unwrap();

        let ranges = vec![(1_577_836_800_000, 1_583_020_800_000)];
        let state = Arc::new(DeleteSharedState::new());
        run_delete(target.clone(), ranges, 1, Arc::clone(&state));

        assert!(!target.join("inside.txt").exists());
        assert!(outside.join("precious.txt").exists());
        assert_eq!(state.deleted.load(Ordering::Relaxed), 1);

        let _ = fs::remove_dir_all(&root);
    }
}
