// Gene - Nov, 25, 2026: Parallel 8-thread Rust directory & file counting engine
// with zero stat() calls and symlink-only canonicalization.

use std::collections::{HashSet, VecDeque};
use std::ffi::CString;
use std::fmt::Write as _;
use std::fs;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};

use crate::common::{
    c_str_to_string, path_basename, push_json_escaped, resolve_within_root, DEFAULT_IO_WORKERS,
    MAX_QUEUED_LOGS,
};

#[repr(C)]
pub struct CountConfigC {
    pub target_path: *const c_char,
    pub log_interval: u64,
}

struct CountUiState {
    current_dir_name: String,
    critical_error: Option<String>,
    logs: VecDeque<String>,
    error_logs: VecDeque<String>,
}

struct CountQueueInner {
    dirs: VecDeque<PathBuf>,
    active_workers: usize,
}

struct CountWorkQueue {
    inner: Mutex<CountQueueInner>,
    cv: Condvar,
}

impl CountWorkQueue {
    fn new(root: PathBuf) -> Self {
        let mut dirs = VecDeque::new();
        dirs.push_back(root);
        Self {
            inner: Mutex::new(CountQueueInner {
                dirs,
                active_workers: 0,
            }),
            cv: Condvar::new(),
        }
    }

    fn pop_dir(&self, stop_requested: &AtomicBool) -> Option<PathBuf> {
        let mut guard = match self.inner.lock() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        loop {
            if stop_requested.load(Ordering::Acquire) {
                return None;
            }
            if let Some(dir) = guard.dirs.pop_front() {
                guard.active_workers += 1;
                return Some(dir);
            }
            if guard.active_workers == 0 {
                return None;
            }
            guard = match self.cv.wait(guard) {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
        }
    }

    fn push_subdirs_and_finish_dir(&self, subdirs: Vec<PathBuf>) {
        if let Ok(mut guard) = self.inner.lock() {
            for d in subdirs {
                guard.dirs.push_back(d);
            }
            guard.active_workers = guard.active_workers.saturating_sub(1);
            self.cv.notify_all();
        }
    }

    fn wake_all(&self) {
        self.cv.notify_all();
    }
}

struct CountSharedState {
    files: AtomicU64,
    folders: AtomicU64,
    errors: AtomicU64,
    stop_requested: AtomicBool,
    done: AtomicBool,
    visited_symlinks: Mutex<HashSet<PathBuf>>,
    ui: Mutex<CountUiState>,
}

pub struct CountJob {
    state: Arc<CountSharedState>,
    queue: Arc<CountWorkQueue>,
    handle: Option<JoinHandle<()>>,
}

impl CountSharedState {
    fn new() -> Self {
        Self {
            files: AtomicU64::new(0),
            folders: AtomicU64::new(0),
            errors: AtomicU64::new(0),
            stop_requested: AtomicBool::new(false),
            done: AtomicBool::new(false),
            visited_symlinks: Mutex::new(HashSet::new()),
            ui: Mutex::new(CountUiState {
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

    fn record_counted_file(&self, file_name: &str, log_interval: u64) {
        let total = self.files.fetch_add(1, Ordering::Relaxed) + 1;
        if log_interval == 1 {
            self.push_log(format!("✓ Counted: {file_name}"));
        } else if log_interval > 0 && total % log_interval == 0 {
            self.push_log(format!(
                "✓ Counted {log_interval} files (total: {total}) – latest: {file_name}"
            ));
        }
    }
}

fn run_count_worker(
    canonical_root: &PathBuf,
    log_interval: u64,
    queue: &CountWorkQueue,
    state: &CountSharedState,
) {
    while let Some(dir) = queue.pop_dir(&state.stop_requested) {
        let dir_name = path_basename(&dir);
        state.set_current_dir(&dir_name);

        let mut subdirs = Vec::new();
        match fs::read_dir(&dir) {
            Ok(entries) => {
                for entry_res in entries {
                    if state.stop_requested.load(Ordering::Acquire) {
                        break;
                    }
                    let entry = match entry_res {
                        Ok(e) => e,
                        Err(e) => {
                            state.errors.fetch_add(1, Ordering::Relaxed);
                            state.push_error_log(format!(
                                "Error accessing: {} — {e}",
                                dir.display()
                            ));
                            continue;
                        }
                    };

                    let ft = match entry.file_type() {
                        Ok(ft) => ft,
                        Err(_) => continue,
                    };

                    if ft.is_file() {
                        let name = entry.file_name().to_string_lossy().into_owned();
                        state.record_counted_file(&name, log_interval);
                    } else if ft.is_dir() {
                        state.folders.fetch_add(1, Ordering::Relaxed);
                        subdirs.push(entry.path());
                    } else if ft.is_symlink() {
                        let entry_path = entry.path();
                        if !resolve_within_root(canonical_root, &entry_path) {
                            continue;
                        }
                        if let Ok(canon_target) = fs::canonicalize(&entry_path) {
                            if let Ok(meta) = fs::metadata(&entry_path) {
                                if meta.is_dir() {
                                    let is_new = state
                                        .visited_symlinks
                                        .lock()
                                        .map(|mut s| s.insert(canon_target))
                                        .unwrap_or(false);
                                    if is_new {
                                        state.folders.fetch_add(1, Ordering::Relaxed);
                                        subdirs.push(entry_path);
                                    }
                                } else if meta.is_file() {
                                    let name = entry.file_name().to_string_lossy().into_owned();
                                    state.record_counted_file(&name, log_interval);
                                }
                            }
                        }
                    }
                }
            }
            Err(e) => {
                state.errors.fetch_add(1, Ordering::Relaxed);
                state.push_error_log(format!("Error accessing: {} — {e}", dir.display()));
            }
        }

        queue.push_subdirs_and_finish_dir(subdirs);
    }
}

fn run_count(
    target_path: PathBuf,
    log_interval: u64,
    queue: Arc<CountWorkQueue>,
    state: Arc<CountSharedState>,
) {
    let canonical_root = match fs::canonicalize(&target_path) {
        Ok(p) => Arc::new(p),
        Err(e) => {
            state.set_critical_error(format!(
                "Failed to access target directory {}: {e}",
                target_path.display()
            ));
            state.done.store(true, Ordering::Release);
            return;
        }
    };

    let mut handles = Vec::with_capacity(DEFAULT_IO_WORKERS);
    for _ in 0..DEFAULT_IO_WORKERS {
        let q = Arc::clone(&queue);
        let s = Arc::clone(&state);
        let r = Arc::clone(&canonical_root);
        if let Ok(h) = thread::Builder::new()
            .name("count_engine_worker".to_string())
            .spawn(move || {
                run_count_worker(&r, log_interval, &q, &s);
            })
        {
            handles.push(h);
        }
    }

    for h in handles {
        let _ = h.join();
    }

    state.done.store(true, Ordering::Release);
}

fn build_count_poll_json(state: &CountSharedState) -> String {
    let files = state.files.load(Ordering::Relaxed);
    let folders = state.folders.load(Ordering::Relaxed);
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
        "{{\"files\":{files},\"folders\":{folders},\"errors\":{errors},\"currentDirName\":"
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
pub unsafe extern "C" fn count_engine_start(cfg: *const CountConfigC) -> *mut CountJob {
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

        let state = Arc::new(CountSharedState::new());
        let queue = Arc::new(CountWorkQueue::new(target_path.clone()));
        let worker_state = Arc::clone(&state);
        let worker_queue = Arc::clone(&queue);

        let handle = thread::Builder::new()
            .name("count_engine_coordinator".to_string())
            .spawn(move || {
                let state_for_panic = Arc::clone(&worker_state);
                let run_res = catch_unwind(AssertUnwindSafe(|| {
                    run_count(target_path, log_interval, worker_queue, worker_state);
                }));
                if let Err(panic_info) = run_res {
                    let msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
                        (*s).to_string()
                    } else if let Some(s) = panic_info.downcast_ref::<String>() {
                        s.clone()
                    } else {
                        "Unknown count worker panic".to_string()
                    };
                    state_for_panic.set_critical_error(msg);
                    state_for_panic.done.store(true, Ordering::Release);
                }
            })
            .ok();

        match handle {
            Some(h) => Box::into_raw(Box::new(CountJob {
                state,
                queue,
                handle: Some(h),
            })),
            None => std::ptr::null_mut(),
        }
    }));

    res.unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn count_engine_stop(job: *mut CountJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let job_ref = &*job;
        job_ref.state.stop_requested.store(true, Ordering::Release);
        job_ref.queue.wake_all();
    }));
}

#[no_mangle]
pub unsafe extern "C" fn count_engine_poll(job: *mut CountJob) -> *mut c_char {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return std::ptr::null_mut();
        }
        let job_ref = &*job;
        let json = build_count_poll_json(&job_ref.state);
        match CString::new(json) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => std::ptr::null_mut(),
        }
    }));

    res.unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn count_engine_destroy(job: *mut CountJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let mut boxed = Box::from_raw(job);
        boxed.state.stop_requested.store(true, Ordering::Release);
        boxed.queue.wake_all();
        if let Some(handle) = boxed.handle.take() {
            let _ = handle.join();
        }
    }));
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
    fn counts_nested_files_and_folders_accurately() {
        let root = make_temp_dir("rust_count_basic");
        let sub1 = root.join("sub1");
        let sub2 = sub1.join("sub2");
        fs::create_dir_all(&sub2).unwrap();
        fs::write(root.join("a.txt"), b"1").unwrap();
        fs::write(sub1.join("b.txt"), b"2").unwrap();
        fs::write(sub2.join("c.txt"), b"3").unwrap();

        let state = Arc::new(CountSharedState::new());
        let queue = Arc::new(CountWorkQueue::new(root.clone()));
        run_count(root.clone(), 1, queue, Arc::clone(&state));

        assert_eq!(state.files.load(Ordering::Relaxed), 3);
        assert_eq!(state.folders.load(Ordering::Relaxed), 2);
        assert_eq!(state.errors.load(Ordering::Relaxed), 0);

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn parallel_counts_100_files_accurately() {
        let root = make_temp_dir("rust_count_parallel_100");
        for d in 0..10 {
            let sub = root.join(format!("dir_{d}"));
            fs::create_dir_all(&sub).unwrap();
            for f in 0..10 {
                fs::write(sub.join(format!("f_{f}.txt")), b"X").unwrap();
            }
        }

        let state = Arc::new(CountSharedState::new());
        let queue = Arc::new(CountWorkQueue::new(root.clone()));
        run_count(root.clone(), 25, queue, Arc::clone(&state));

        assert_eq!(state.files.load(Ordering::Relaxed), 100);
        assert_eq!(state.folders.load(Ordering::Relaxed), 10);
        assert_eq!(state.errors.load(Ordering::Relaxed), 0);

        let _ = fs::remove_dir_all(&root);
    }

    #[cfg(unix)]
    #[test]
    fn skips_symlinks_outside_root() {
        use std::os::unix::fs::symlink;

        let root = make_temp_dir("rust_count_symlink");
        let target = root.join("target");
        let outside = root.join("outside");
        fs::create_dir_all(&target).unwrap();
        fs::create_dir_all(&outside).unwrap();

        fs::write(target.join("inside.txt"), b"1").unwrap();
        fs::write(outside.join("secret.txt"), b"2").unwrap();
        symlink(&outside, target.join("escape")).unwrap();

        let state = Arc::new(CountSharedState::new());
        let queue = Arc::new(CountWorkQueue::new(target.clone()));
        run_count(target.clone(), 100, queue, Arc::clone(&state));

        assert_eq!(state.files.load(Ordering::Relaxed), 1);
        assert_eq!(state.folders.load(Ordering::Relaxed), 0);

        let _ = fs::remove_dir_all(&root);
    }
}
