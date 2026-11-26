// Gene - Nov, 25, 2026: Parallel 8-worker Rust file deletion engine with O(log N)
// binary-search range matching, symlink-only canonicalization, and bottom-up empty folder cleanup.

use std::collections::{HashSet, VecDeque};
use std::ffi::CString;
use std::fmt::Write as _;
use std::fs;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
// use std::path::PathBuf;
// use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
// use std::sync::{Arc, Condvar, Mutex};
// use std::thread::{self, JoinHandle};
//
// use crate::common::{
//     c_str_to_string, normalize_lexical, path_basename, push_json_escaped, resolve_within_root,
//     system_time_to_epoch_ms, DEFAULT_IO_WORKERS, MAX_QUEUED_LOGS,
// };
// Gene - Nov, 26, 2026: Import Path, io_worker_count, and resolve_canonical_within_root for parallel delete workers.
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};

use crate::common::{
    c_str_to_string, io_worker_count, normalize_lexical, path_basename, push_json_escaped,
    resolve_canonical_within_root, system_time_to_epoch_ms, MAX_QUEUED_LOGS,
};

// Gene - Nov, 26, 2026: Commented out unused DELETE_QUEUE_CAPACITY after moving to parallel DeleteWorkQueue.
// const DELETE_QUEUE_CAPACITY: usize = 512;

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

// Gene - Nov, 26, 2026: Parallelized delete directory traversal across io_worker_count() workers,
// merged overlapping/adjacent ranges, tracked empty-dir removal errors, and skipped symlinks as empty dirs.
// struct DeleteQueueInner {
//     files: VecDeque<PathBuf>,
//     closed: bool,
// }
//
// struct DeleteQueue {
//     inner: Mutex<DeleteQueueInner>,
//     not_empty: Condvar,
//     not_full: Condvar,
// }
//
// impl DeleteQueue {
//     fn new() -> Self {
//         Self {
//             inner: Mutex::new(DeleteQueueInner {
//                 files: VecDeque::with_capacity(DELETE_QUEUE_CAPACITY),
//                 closed: false,
//             }),
//             not_empty: Condvar::new(),
//             not_full: Condvar::new(),
//         }
//     }
//
//     fn push(&self, path: PathBuf, stop_requested: &AtomicBool) -> bool {
//         let mut guard = match self.inner.lock() {
//             Ok(g) => g,
//             Err(p) => p.into_inner(),
//         };
//         while guard.files.len() >= DELETE_QUEUE_CAPACITY
//             && !guard.closed
//             && !stop_requested.load(Ordering::Acquire)
//         {
//             guard = match self.not_full.wait(guard) {
//                 Ok(g) => g,
//                 Err(p) => p.into_inner(),
//             };
//         }
//         if guard.closed || stop_requested.load(Ordering::Acquire) {
//             return false;
//         }
//         guard.files.push_back(path);
//         self.not_empty.notify_one();
//         true
//     }
//
//     fn pop(&self, stop_requested: &AtomicBool) -> Option<PathBuf> {
//         let mut guard = match self.inner.lock() {
//             Ok(g) => g,
//             Err(p) => p.into_inner(),
//         };
//         while guard.files.is_empty()
//             && !guard.closed
//             && !stop_requested.load(Ordering::Acquire)
//         {
//             guard = match self.not_empty.wait(guard) {
//                 Ok(g) => g,
//                 Err(p) => p.into_inner(),
//             };
//         }
//         if stop_requested.load(Ordering::Acquire) || (guard.closed && guard.files.is_empty()) {
//             return None;
//         }
//         let item = guard.files.pop_front();
//         self.not_full.notify_one();
//         item
//     }
//
//     fn close(&self, clear_pending: bool) {
//         if let Ok(mut guard) = self.inner.lock() {
//             if clear_pending {
//                 guard.files.clear();
//             }
//             guard.closed = true;
//             self.not_empty.notify_all();
//             self.not_full.notify_all();
//         }
//     }
// }
//
// struct DeleteSharedState {
//     files_scanned: AtomicU64,
//     deleted: AtomicU64,
//     errors: AtomicU64,
//     stop_requested: AtomicBool,
//     done: AtomicBool,
//     ui: Mutex<DeleteUiState>,
// }
//
// pub struct DeleteJob {
//     state: Arc<DeleteSharedState>,
//     queue: Arc<DeleteQueue>,
//     handle: Option<JoinHandle<()>>,
// }
//
// impl DeleteSharedState {
//     fn new() -> Self {
//         Self {
//             files_scanned: AtomicU64::new(0),
//             deleted: AtomicU64::new(0),
//             errors: AtomicU64::new(0),
//             stop_requested: AtomicBool::new(false),
//             done: AtomicBool::new(false),
//             ui: Mutex::new(DeleteUiState {
//                 current_dir_name: String::new(),
//                 critical_error: None,
//                 logs: VecDeque::new(),
//                 error_logs: VecDeque::new(),
//             }),
//         }
//     }
//
//     fn push_log(&self, line: String) {
//         if let Ok(mut ui) = self.ui.lock() {
//             if ui.logs.len() >= MAX_QUEUED_LOGS {
//                 ui.logs.pop_front();
//             }
//             ui.logs.push_back(line);
//         }
//     }
//
//     fn push_error_log(&self, line: String) {
//         if let Ok(mut ui) = self.ui.lock() {
//             if ui.error_logs.len() >= MAX_QUEUED_LOGS {
//                 ui.error_logs.pop_front();
//             }
//             ui.error_logs.push_back(line);
//         }
//     }
//
//     fn set_current_dir(&self, name: &str) {
//         if let Ok(mut ui) = self.ui.lock() {
//             ui.current_dir_name.clear();
//             ui.current_dir_name.push_str(name);
//         }
//     }
//
//     fn set_critical_error(&self, err: String) {
//         if let Ok(mut ui) = self.ui.lock() {
//             ui.critical_error = Some(err);
//         }
//     }
// }
//
// fn matches_any_range(epoch_ms: i64, ranges: &[(i64, i64)]) -> bool {
//     if ranges.is_empty() {
//         return false;
//     }
//     let idx = ranges.partition_point(|&(start, _)| start <= epoch_ms);
//     if idx == 0 {
//         return false;
//     }
//     let (start, end) = ranges[idx - 1];
//     epoch_ms >= start && epoch_ms < end
// }
//
// fn spawn_delete_worker(
//     queue: Arc<DeleteQueue>,
//     state: Arc<DeleteSharedState>,
//     log_interval: u64,
// ) -> Option<JoinHandle<()>> {
//     thread::Builder::new()
//         .name("delete_engine_io".to_string())
//         .spawn(move || {
//             while let Some(file_path) = queue.pop(&state.stop_requested) {
//                 let file_name = path_basename(&file_path);
//                 match fs::remove_file(&file_path) {
//                     Ok(()) => {
//                         let count = state.deleted.fetch_add(1, Ordering::Relaxed) + 1;
//                         if log_interval == 1 {
//                             state.push_log(format!("✓ Deleted: {file_name}"));
//                         } else if log_interval > 0 && count % log_interval == 0 {
//                             state.push_log(format!(
//                                 "✓ Deleted {log_interval} files (total: {count}) – latest: {file_name}"
//                             ));
//                         }
//                     }
//                     Err(e) => {
//                         state.errors.fetch_add(1, Ordering::Relaxed);
//                         state.push_error_log(format!("✗ Failed to delete {file_name}: {e}"));
//                     }
//                 }
//             }
//         })
//         .ok()
// }
//
// fn inspect_file_for_delete(
//     file_path: PathBuf,
//     known_meta: Option<fs::Metadata>,
//     ranges: &[(i64, i64)],
//     queue: &DeleteQueue,
//     state: &DeleteSharedState,
// ) -> bool {
//     state.files_scanned.fetch_add(1, Ordering::Relaxed);
//     let file_name = path_basename(&file_path);
//
//     let meta = match known_meta {
//         Some(m) => m,
//         None => match fs::metadata(&file_path) {
//             Ok(m) => m,
//             Err(e) => {
//                 state.errors.fetch_add(1, Ordering::Relaxed);
//                 state.push_error_log(format!("✗ Error checking {file_name}: {e}"));
//                 return true;
//             }
//         },
//     };
//
//     let modified = match meta.modified() {
//         Ok(m) => m,
//         Err(e) => {
//             state.errors.fetch_add(1, Ordering::Relaxed);
//             state.push_error_log(format!("✗ Error checking {file_name}: {e}"));
//             return true;
//         }
//     };
//
//     let modified_ms = system_time_to_epoch_ms(modified);
//     if !matches_any_range(modified_ms, ranges) {
//         return true;
//     }
//
//     queue.push(file_path, &state.stop_requested)
// }
//
// fn run_delete(
//     target_path: PathBuf,
//     ranges: Vec<(i64, i64)>,
//     log_interval: u64,
//     queue: Arc<DeleteQueue>,
//     state: Arc<DeleteSharedState>,
// ) {
//     let canonical_root = match fs::canonicalize(&target_path) {
//         Ok(p) => p,
//         Err(e) => {
//             state.set_critical_error(format!(
//                 "Failed to access target directory {}: {e}",
//                 target_path.display()
//             ));
//             queue.close(true);
//             state.done.store(true, Ordering::Release);
//             return;
//         }
//     };
//
//     let mut workers = Vec::with_capacity(DEFAULT_IO_WORKERS);
//     for _ in 0..DEFAULT_IO_WORKERS {
//         if let Some(h) = spawn_delete_worker(
//             Arc::clone(&queue),
//             Arc::clone(&state),
//             log_interval,
//         ) {
//             workers.push(h);
//         }
//     }
//
//     let norm_target_root = normalize_lexical(&target_path);
//     let mut visited_symlinks: HashSet<PathBuf> = HashSet::new();
//     let mut dirs_to_walk: VecDeque<PathBuf> = VecDeque::new();
//     let mut candidate_empty_dirs: Vec<PathBuf> = Vec::new();
//     dirs_to_walk.push_back(target_path);
//
//     while let Some(dir) = dirs_to_walk.pop_front() {
//         if state.stop_requested.load(Ordering::Acquire) {
//             break;
//         }
//
//         let dir_name = path_basename(&dir);
//         state.set_current_dir(&dir_name);
//
//         let entries = match fs::read_dir(&dir) {
//             Ok(iter) => iter,
//             Err(e) => {
//                 state.errors.fetch_add(1, Ordering::Relaxed);
//                 state.push_error_log(format!("✗ Error scanning directory: {e}"));
//                 continue;
//             }
//         };
//
//         if normalize_lexical(&dir) != norm_target_root {
//             candidate_empty_dirs.push(dir.clone());
//         }
//
//         for entry_res in entries {
//             if state.stop_requested.load(Ordering::Acquire) {
//                 break;
//             }
//
//             let entry = match entry_res {
//                 Ok(e) => e,
//                 Err(e) => {
//                     state.errors.fetch_add(1, Ordering::Relaxed);
//                     state.push_error_log(format!("✗ Error scanning directory: {e}"));
//                     continue;
//                 }
//             };
//
//             let entry_path = entry.path();
//             let file_type = match entry.file_type() {
//                 Ok(ft) => ft,
//                 Err(_) => continue,
//             };
//
//             if file_type.is_file() {
//                 let meta = entry.metadata().ok();
//                 if !inspect_file_for_delete(entry_path, meta, &ranges, &queue, &state) {
//                     break;
//                 }
//             } else if file_type.is_dir() {
//                 dirs_to_walk.push_back(entry_path);
//             } else if file_type.is_symlink() {
//                 if !resolve_within_root(&canonical_root, &entry_path) {
//                     state.push_log(format!(
//                         "ℹ Skipped link pointing outside the target: {}",
//                         path_basename(&entry_path)
//                     ));
//                     continue;
//                 }
//                 if let Ok(canon_target) = fs::canonicalize(&entry_path) {
//                     if let Ok(target_meta) = fs::metadata(&entry_path) {
//                         if target_meta.is_dir() {
//                             if visited_symlinks.insert(canon_target) {
//                                 dirs_to_walk.push_back(entry_path);
//                             }
//                         } else if target_meta.is_file() {
//                             if !inspect_file_for_delete(
//                                 entry_path,
//                                 Some(target_meta),
//                                 &ranges,
//                                 &queue,
//                                 &state,
//                             ) {
//                                 break;
//                             }
//                         }
//                     }
//                 }
//             }
//         }
//     }
//
//     let stopped = state.stop_requested.load(Ordering::Acquire);
//     queue.close(stopped);
//     for w in workers {
//         let _ = w.join();
//     }
//
//     if !state.stop_requested.load(Ordering::Acquire) && !candidate_empty_dirs.is_empty() {
//         // Delete deepest subdirectories first so newly emptied parents collapse cleanly.
//         candidate_empty_dirs.sort_by_key(|p| std::cmp::Reverse(p.components().count()));
//         for dir in candidate_empty_dirs {
//             if state.stop_requested.load(Ordering::Acquire) {
//                 break;
//             }
//             let is_empty = fs::read_dir(&dir)
//                 .map(|mut iter| iter.next().is_none())
//                 .unwrap_or(false);
//             if is_empty {
//                 let dir_name = path_basename(&dir);
//                 match fs::remove_dir(&dir) {
//                     Ok(()) => {
//                         state.push_log(format!("✓ Deleted empty folder: {dir_name}"));
//                     }
//                     Err(e) => {
//                         state.push_error_log(format!(
//                             "✗ Failed to delete folder {dir_name}: {e}"
//                         ));
//                     }
//                 }
//             }
//         }
//     }
//
//     state.done.store(true, Ordering::Release);
// }
//
// fn build_delete_poll_json(state: &DeleteSharedState) -> String {
//     let files_scanned = state.files_scanned.load(Ordering::Relaxed);
//     let deleted = state.deleted.load(Ordering::Relaxed);
//     let errors = state.errors.load(Ordering::Relaxed);
//     let is_done = state.done.load(Ordering::Acquire);
//
//     let (current_dir_name, critical_error, logs, error_logs) = match state.ui.lock() {
//         Ok(mut ui) => (
//             ui.current_dir_name.clone(),
//             ui.critical_error.take(),
//             ui.logs.drain(..).collect::<Vec<_>>(),
//             ui.error_logs.drain(..).collect::<Vec<_>>(),
//         ),
//         Err(_) => (String::new(), None, Vec::new(), Vec::new()),
//     };
//
//     let mut json = String::with_capacity(256);
//     let _ = write!(
//         json,
//         "{{\"filesScanned\":{files_scanned},\"deleted\":{deleted},\"errors\":{errors},\"currentDirName\":"
//     );
//     push_json_escaped(&mut json, &current_dir_name);
//     let _ = write!(json, ",\"isDone\":{is_done},\"criticalError\":");
//     match critical_error {
//         Some(ref c) => push_json_escaped(&mut json, c),
//         None => json.push_str("null"),
//     }
//     json.push_str(",\"logs\":[");
//     for (idx, line) in logs.iter().enumerate() {
//         if idx > 0 {
//             json.push(',');
//         }
//         push_json_escaped(&mut json, line);
//     }
//     json.push_str("],\"errorLogs\":[");
//     for (idx, line) in error_logs.iter().enumerate() {
//         if idx > 0 {
//             json.push(',');
//         }
//         push_json_escaped(&mut json, line);
//     }
//     json.push_str("]}");
//     json
// }
//
// #[no_mangle]
// pub unsafe extern "C" fn delete_engine_start(cfg: *const DeleteConfigC) -> *mut DeleteJob {
//     let res = catch_unwind(AssertUnwindSafe(|| {
//         if cfg.is_null() {
//             return std::ptr::null_mut();
//         }
//         let raw = &*cfg;
//         let target_path = match c_str_to_string(raw.target_path) {
//             Some(s) if !s.is_empty() => PathBuf::from(s),
//             _ => return std::ptr::null_mut(),
//         };
//         let log_interval = if raw.log_interval == 0 {
//             100
//         } else {
//             raw.log_interval
//         };
//
//         let mut ranges: Vec<(i64, i64)> = Vec::with_capacity(raw.ranges_len);
//         if !raw.ranges_ptr.is_null() && raw.ranges_len > 0 {
//             let slice = std::slice::from_raw_parts(raw.ranges_ptr, raw.ranges_len * 2);
//             for pair in slice.chunks_exact(2) {
//                 ranges.push((pair[0], pair[1]));
//             }
//             ranges.sort_unstable_by_key(|&(start, _)| start);
//         }
//
//         let state = Arc::new(DeleteSharedState::new());
//         let queue = Arc::new(DeleteQueue::new());
//         let worker_state = Arc::clone(&state);
//         let worker_queue = Arc::clone(&queue);
//
//         let handle = thread::Builder::new()
//             .name("delete_engine_coordinator".to_string())
//             .spawn(move || {
//                 let state_for_panic = Arc::clone(&worker_state);
//                 let queue_for_panic = Arc::clone(&worker_queue);
//                 let run_res = catch_unwind(AssertUnwindSafe(|| {
//                     run_delete(target_path, ranges, log_interval, worker_queue, worker_state);
//                 }));
//                 if let Err(panic_info) = run_res {
//                     let msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
//                         (*s).to_string()
//                     } else if let Some(s) = panic_info.downcast_ref::<String>() {
//                         s.clone()
//                     } else {
//                         "Unknown delete worker panic".to_string()
//                     };
//                     queue_for_panic.close(true);
//                     state_for_panic.set_critical_error(msg);
//                     state_for_panic.done.store(true, Ordering::Release);
//                 }
//             })
//             .ok();
//
//         match handle {
//             Some(h) => Box::into_raw(Box::new(DeleteJob {
//                 state,
//                 queue,
//                 handle: Some(h),
//             })),
//             None => std::ptr::null_mut(),
//         }
//     }));
//
//     res.unwrap_or(std::ptr::null_mut())
// }
//
// #[no_mangle]
// pub unsafe extern "C" fn delete_engine_stop(job: *mut DeleteJob) {
//     let _ = catch_unwind(AssertUnwindSafe(|| {
//         if job.is_null() {
//             return;
//         }
//         let job_ref = &*job;
//         job_ref.state.stop_requested.store(true, Ordering::Release);
//         job_ref.queue.close(true);
//     }));
// }
//
// #[no_mangle]
// pub unsafe extern "C" fn delete_engine_poll(job: *mut DeleteJob) -> *mut c_char {
//     let res = catch_unwind(AssertUnwindSafe(|| {
//         if job.is_null() {
//             return std::ptr::null_mut();
//         }
//         let job_ref = &*job;
//         let json = build_delete_poll_json(&job_ref.state);
//         match CString::new(json) {
//             Ok(cstr) => cstr.into_raw(),
//             Err(_) => std::ptr::null_mut(),
//         }
//     }));
//
//     res.unwrap_or(std::ptr::null_mut())
// }
//
// #[no_mangle]
// pub unsafe extern "C" fn delete_engine_destroy(job: *mut DeleteJob) {
//     let _ = catch_unwind(AssertUnwindSafe(|| {
//         if job.is_null() {
//             return;
//         }
//         let mut boxed = Box::from_raw(job);
//         boxed.state.stop_requested.store(true, Ordering::Release);
//         boxed.queue.close(true);
//         if let Some(handle) = boxed.handle.take() {
//             let _ = handle.join();
//         }
//     }));
// }
struct DeleteWorkQueueInner {
    dirs: VecDeque<PathBuf>,
    active_workers: usize,
}

struct DeleteWorkQueue {
    inner: Mutex<DeleteWorkQueueInner>,
    cv: Condvar,
}

impl DeleteWorkQueue {
    fn new(root: PathBuf) -> Self {
        let mut dirs = VecDeque::new();
        dirs.push_back(root);
        Self {
            inner: Mutex::new(DeleteWorkQueueInner {
                dirs,
                active_workers: 0,
            }),
            cv: Condvar::new(),
        }
    }

    fn pop_dir(&self, stop_requested: &AtomicBool) -> Option<PathBuf> {
        let mut guard = self.inner.lock().unwrap_or_else(|p| p.into_inner());
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
            guard = self.cv.wait(guard).unwrap_or_else(|p| p.into_inner());
        }
    }

    fn push_subdirs_and_finish_dir(&self, subdirs: Vec<PathBuf>) {
        let mut guard = self.inner.lock().unwrap_or_else(|p| p.into_inner());
        let added = subdirs.len();
        for d in subdirs {
            guard.dirs.push_back(d);
        }
        guard.active_workers = guard.active_workers.saturating_sub(1);
        if guard.active_workers == 0 && guard.dirs.is_empty() {
            self.cv.notify_all();
        } else if added == 1 {
            self.cv.notify_one();
        } else if added > 1 {
            self.cv.notify_all();
        }
    }

    fn wake_all(&self) {
        self.cv.notify_all();
    }
}

struct DeleteSharedState {
    files_scanned: AtomicU64,
    deleted: AtomicU64,
    errors: AtomicU64,
    stop_requested: AtomicBool,
    done: AtomicBool,
    visited_symlinks: Mutex<HashSet<PathBuf>>,
    candidate_empty_dirs: Mutex<Vec<PathBuf>>,
    ui: Mutex<DeleteUiState>,
}

pub struct DeleteJob {
    state: Arc<DeleteSharedState>,
    queue: Arc<DeleteWorkQueue>,
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
            visited_symlinks: Mutex::new(HashSet::new()),
            candidate_empty_dirs: Mutex::new(Vec::new()),
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
        if let Ok(mut ui) = self.ui.try_lock() {
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

fn normalize_ranges(mut ranges: Vec<(i64, i64)>) -> Vec<(i64, i64)> {
    ranges.retain(|&(start, end)| start < end);
    if ranges.len() <= 1 {
        return ranges;
    }
    ranges.sort_unstable_by_key(|&(start, _)| start);
    let mut merged: Vec<(i64, i64)> = Vec::with_capacity(ranges.len());
    for (start, end) in ranges {
        if let Some(last) = merged.last_mut() {
            if start <= last.1 {
                if end > last.1 {
                    last.1 = end;
                }
                continue;
            }
        }
        merged.push((start, end));
    }
    merged
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

fn delete_if_matches_range(
    file_path: &Path,
    known_meta: Option<fs::Metadata>,
    ranges: &[(i64, i64)],
    log_interval: u64,
    state: &DeleteSharedState,
) {
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

fn run_delete_worker(
    canonical_root: &Path,
    norm_target_root: &Path,
    ranges: &[(i64, i64)],
    log_interval: u64,
    queue: &DeleteWorkQueue,
    state: &DeleteSharedState,
) {
    while let Some(dir) = queue.pop_dir(&state.stop_requested) {
        let dir_name = path_basename(&dir);
        state.set_current_dir(&dir_name);

        if normalize_lexical(&dir) != norm_target_root
            && fs::symlink_metadata(&dir)
                .map(|m| m.is_dir())
                .unwrap_or(false)
        {
            if let Ok(mut candidates) = state.candidate_empty_dirs.lock() {
                candidates.push(dir.clone());
            }
        }

        let mut subdirs: Vec<PathBuf> = Vec::new();
        let mut local_scanned: u64 = 0;

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
                            state.push_error_log(format!("✗ Error scanning directory: {e}"));
                            continue;
                        }
                    };

                    let file_type = match entry.file_type() {
                        Ok(ft) => ft,
                        Err(_) => continue,
                    };

                    if file_type.is_file() {
                        local_scanned += 1;
                        if local_scanned >= 64 {
                            state
                                .files_scanned
                                .fetch_add(local_scanned, Ordering::Relaxed);
                            local_scanned = 0;
                        }
                        let entry_path = entry.path();
                        let meta = entry.metadata().ok();
                        delete_if_matches_range(&entry_path, meta, ranges, log_interval, state);
                    } else if file_type.is_dir() {
                        subdirs.push(entry.path());
                    } else if file_type.is_symlink() {
                        let entry_path = entry.path();
                        let Some(canon_target) =
                            resolve_canonical_within_root(canonical_root, &entry_path)
                        else {
                            state.push_log(format!(
                                "ℹ Skipped link pointing outside the target: {}",
                                path_basename(&entry_path)
                            ));
                            continue;
                        };
                        if let Ok(target_meta) = fs::metadata(&entry_path) {
                            if target_meta.is_dir() {
                                let is_new = state
                                    .visited_symlinks
                                    .lock()
                                    .map(|mut s| s.insert(canon_target))
                                    .unwrap_or(false);
                                if is_new {
                                    subdirs.push(entry_path);
                                }
                            } else if target_meta.is_file() {
                                local_scanned += 1;
                                if local_scanned >= 64 {
                                    state
                                        .files_scanned
                                        .fetch_add(local_scanned, Ordering::Relaxed);
                                    local_scanned = 0;
                                }
                                delete_if_matches_range(
                                    &entry_path,
                                    Some(target_meta),
                                    ranges,
                                    log_interval,
                                    state,
                                );
                            }
                        }
                    }
                }
            }
            Err(e) => {
                state.errors.fetch_add(1, Ordering::Relaxed);
                state.push_error_log(format!("✗ Error scanning directory: {e}"));
            }
        }

        if local_scanned > 0 {
            state
                .files_scanned
                .fetch_add(local_scanned, Ordering::Relaxed);
        }

        queue.push_subdirs_and_finish_dir(subdirs);
    }
}

fn run_delete(
    target_path: PathBuf,
    ranges: Vec<(i64, i64)>,
    log_interval: u64,
    queue: Arc<DeleteWorkQueue>,
    state: Arc<DeleteSharedState>,
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

    let norm_ranges = Arc::new(normalize_ranges(ranges));
    let norm_target_root = Arc::new(normalize_lexical(&target_path));
    let worker_count = io_worker_count();
    let mut workers = Vec::with_capacity(worker_count);
    for _ in 0..worker_count {
        let q = Arc::clone(&queue);
        let s = Arc::clone(&state);
        let r = Arc::clone(&canonical_root);
        let nt = Arc::clone(&norm_target_root);
        let nr = Arc::clone(&norm_ranges);
        if let Ok(h) = thread::Builder::new()
            .name("delete_engine_worker".to_string())
            .spawn(move || {
                run_delete_worker(&r, &nt, &nr, log_interval, &q, &s);
            })
        {
            workers.push(h);
        }
    }

    if workers.is_empty() {
        state.set_critical_error("Failed to spawn delete worker threads".to_string());
        state.done.store(true, Ordering::Release);
        return;
    }

    for w in workers {
        let _ = w.join();
    }

    if !state.stop_requested.load(Ordering::Acquire) {
        let mut candidate_empty_dirs = match state.candidate_empty_dirs.lock() {
            Ok(mut g) => std::mem::take(&mut *g),
            Err(p) => std::mem::take(&mut *p.into_inner()),
        };
        if !candidate_empty_dirs.is_empty() {
            // Delete deepest subdirectories first so newly emptied parents collapse cleanly.
            candidate_empty_dirs.sort_unstable_by_key(|p| std::cmp::Reverse(p.components().count()));
            for dir in candidate_empty_dirs {
                if state.stop_requested.load(Ordering::Acquire) {
                    break;
                }
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
                            state.errors.fetch_add(1, Ordering::Relaxed);
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

    let mut json = String::with_capacity(256 + logs.len() * 64 + error_logs.len() * 64);
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

        let mut raw_ranges: Vec<(i64, i64)> = Vec::with_capacity(raw.ranges_len);
        if !raw.ranges_ptr.is_null() && raw.ranges_len > 0 {
            let slice = std::slice::from_raw_parts(raw.ranges_ptr, raw.ranges_len * 2);
            for pair in slice.chunks_exact(2) {
                raw_ranges.push((pair[0], pair[1]));
            }
        }
        let ranges = normalize_ranges(raw_ranges);

        let state = Arc::new(DeleteSharedState::new());
        let queue = Arc::new(DeleteWorkQueue::new(target_path.clone()));
        let worker_state = Arc::clone(&state);
        let worker_queue = Arc::clone(&queue);

        let handle = thread::Builder::new()
            .name("delete_engine_coordinator".to_string())
            .spawn(move || {
                let state_for_panic = Arc::clone(&worker_state);
                let queue_for_panic = Arc::clone(&worker_queue);
                let run_res = catch_unwind(AssertUnwindSafe(|| {
                    run_delete(target_path, ranges, log_interval, worker_queue, worker_state);
                }));
                if let Err(panic_info) = run_res {
                    let msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
                        (*s).to_string()
                    } else if let Some(s) = panic_info.downcast_ref::<String>() {
                        s.clone()
                    } else {
                        "Unknown delete worker panic".to_string()
                    };
                    queue_for_panic.wake_all();
                    state_for_panic.set_critical_error(msg);
                    state_for_panic.done.store(true, Ordering::Release);
                }
            })
            .ok();

        match handle {
            Some(h) => Box::into_raw(Box::new(DeleteJob {
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
pub unsafe extern "C" fn delete_engine_stop(job: *mut DeleteJob) {
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
        boxed.queue.wake_all();
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

        let ranges = vec![(1_577_836_800_000, 1_583_020_800_000)];
        let state = Arc::new(DeleteSharedState::new());
        // let queue = Arc::new(DeleteQueue::new());
        // Gene - Nov, 26, 2026: Use DeleteWorkQueue::new(root.clone()) for parallel delete tests.
        let queue = Arc::new(DeleteWorkQueue::new(root.clone()));
        run_delete(root.clone(), ranges, 1, queue, Arc::clone(&state));

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
        // let queue = Arc::new(DeleteQueue::new());
        // Gene - Nov, 26, 2026: Use DeleteWorkQueue::new(target.clone()) for parallel delete symlink test.
        let queue = Arc::new(DeleteWorkQueue::new(target.clone()));
        run_delete(target.clone(), ranges, 1, queue, Arc::clone(&state));

        assert!(!target.join("inside.txt").exists());
        assert!(outside.join("precious.txt").exists());
        assert_eq!(state.deleted.load(Ordering::Relaxed), 1);

        let _ = fs::remove_dir_all(&root);
    }

    // Gene - Nov, 26, 2026: Added tests for overlapping/adjacent range normalization and parallel 100-file folder cleanup.
    #[test]
    fn merges_overlapping_ranges_accurately() {
        let merged = normalize_ranges(vec![(300, 200), (10, 100), (20, 50), (100, 200)]);
        assert_eq!(merged, vec![(10, 200)]);
        assert!(matches_any_range(75, &merged));
        assert!(matches_any_range(150, &merged));
        assert!(!matches_any_range(200, &merged));
        assert!(!matches_any_range(9, &merged));
    }

    #[test]
    fn parallel_deletes_100_matching_files_and_cleans_empty_nested_dirs() {
        let root = make_temp_dir("rust_delete_parallel_100");
        let keep_dir = root.join("keep");
        fs::create_dir_all(&keep_dir).unwrap();

        let t_match = UNIX_EPOCH + Duration::from_secs(1_580_000_000);
        let t_keep = UNIX_EPOCH + Duration::from_secs(1_700_000_000);

        for d in 0..5 {
            let nested = root.join(format!("batch_{d}")).join("inner");
            fs::create_dir_all(&nested).unwrap();
            for f in 0..20 {
                let file = File::create(nested.join(format!("old_{f}.txt"))).unwrap();
                file.set_modified(t_match).unwrap();
            }
        }
        for k in 0..10 {
            let file = File::create(keep_dir.join(format!("new_{k}.txt"))).unwrap();
            file.set_modified(t_keep).unwrap();
        }

        let ranges = vec![(1_577_836_800_000, 1_583_020_800_000)];
        let state = Arc::new(DeleteSharedState::new());
        let queue = Arc::new(DeleteWorkQueue::new(root.clone()));
        run_delete(root.clone(), ranges, 25, queue, Arc::clone(&state));

        assert_eq!(state.files_scanned.load(Ordering::Relaxed), 110);
        assert_eq!(state.deleted.load(Ordering::Relaxed), 100);
        assert_eq!(state.errors.load(Ordering::Relaxed), 0);
        for d in 0..5 {
            assert!(!root.join(format!("batch_{d}")).exists());
        }
        assert_eq!(fs::read_dir(&keep_dir).unwrap().count(), 10);

        let _ = fs::remove_dir_all(&root);
    }
}
