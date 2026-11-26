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

// Gene - Nov, 26, 2026: Added file-type category bitmask constants and case-insensitive extension classifier.
pub const COUNT_CAT_IMAGES: u32 = 1 << 0;
pub const COUNT_CAT_DOCUMENTS: u32 = 1 << 1;
pub const COUNT_CAT_VIDEOS: u32 = 1 << 2;
pub const COUNT_CAT_AUDIO: u32 = 1 << 3;
pub const COUNT_CAT_ARCHIVES: u32 = 1 << 4;
pub const COUNT_CAT_OTHERS: u32 = 1 << 5;
pub const COUNT_CAT_ALL: u32 = COUNT_CAT_IMAGES
    | COUNT_CAT_DOCUMENTS
    | COUNT_CAT_VIDEOS
    | COUNT_CAT_AUDIO
    | COUNT_CAT_ARCHIVES
    | COUNT_CAT_OTHERS;

// #[repr(C)]
// pub struct CountConfigC {
//     pub target_path: *const c_char,
//     pub log_interval: u64,
// }
// Gene - Nov, 26, 2026: Added include_mask bitmask field to CountConfigC for file-type filtering.
// Gene - Nov, 26, 2026: Added size_only flag to CountConfigC for fast folder-size-only mode.
// #[repr(C)]
// pub struct CountConfigC {
//     pub target_path: *const c_char,
//     pub log_interval: u64,
//     pub include_mask: u32,
// }
#[repr(C)]
pub struct CountConfigC {
    pub target_path: *const c_char,
    pub log_interval: u64,
    pub include_mask: u32,
    pub size_only: u8,
}

fn classify_file_category(file_name: &str) -> u32 {
    let ext = match std::path::Path::new(file_name)
        .extension()
        .and_then(|e| e.to_str())
    {
        Some(e) if !e.is_empty() && e.is_ascii() && e.len() <= 8 => e,
        _ => return COUNT_CAT_OTHERS,
    };

    let mut buf = [0u8; 8];
    let len = ext.len();
    for (i, b) in ext.as_bytes().iter().enumerate() {
        buf[i] = b.to_ascii_lowercase();
    }

    match &buf[..len] {
        b"jpg" | b"jpeg" | b"png" | b"gif" | b"bmp" | b"webp" | b"svg" | b"tif" | b"tiff"
        | b"heic" | b"heif" | b"ico" | b"jfif" | b"avif" | b"raw" | b"cr2" | b"nef" | b"arw"
        | b"dng" | b"psd" | b"ai" | b"eps" => COUNT_CAT_IMAGES,
        b"pdf" | b"doc" | b"docx" | b"xls" | b"xlsx" | b"ppt" | b"pptx" | b"txt" | b"rtf"
        | b"csv" | b"tsv" | b"odt" | b"ods" | b"odp" | b"md" | b"epub" | b"pages"
        | b"numbers" | b"key" | b"wps" => COUNT_CAT_DOCUMENTS,
        b"mp4" | b"mov" | b"avi" | b"mkv" | b"wmv" | b"flv" | b"webm" | b"m4v" | b"mpg"
        | b"mpeg" | b"3gp" | b"mts" | b"m2ts" | b"vob" | b"ogv" => COUNT_CAT_VIDEOS,
        b"mp3" | b"wav" | b"flac" | b"aac" | b"ogg" | b"m4a" | b"wma" | b"aiff" | b"aif"
        | b"opus" | b"mid" | b"midi" | b"amr" => COUNT_CAT_AUDIO,
        b"zip" | b"rar" | b"7z" | b"tar" | b"gz" | b"bz2" | b"xz" | b"tgz" | b"tbz2"
        | b"iso" | b"dmg" | b"cab" | b"zst" => COUNT_CAT_ARCHIVES,
        _ => COUNT_CAT_OTHERS,
    }
}

#[inline]
fn matches_count_filter(file_name: &str, include_mask: u32) -> bool {
    if include_mask == COUNT_CAT_ALL {
        return true;
    }
    if include_mask == 0 {
        return false;
    }
    (classify_file_category(file_name) & include_mask) != 0
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

// struct CountSharedState {
//     files: AtomicU64,
//     folders: AtomicU64,
//     errors: AtomicU64,
//     stop_requested: AtomicBool,
//     done: AtomicBool,
//     visited_symlinks: Mutex<HashSet<PathBuf>>,
//     ui: Mutex<CountUiState>,
// }
//
// pub struct CountJob {
//     state: Arc<CountSharedState>,
//     queue: Arc<CountWorkQueue>,
//     handle: Option<JoinHandle<()>>,
// }
//
// impl CountSharedState {
//     fn new() -> Self {
//         Self {
//             files: AtomicU64::new(0),
//             folders: AtomicU64::new(0),
//             errors: AtomicU64::new(0),
//             stop_requested: AtomicBool::new(false),
//             done: AtomicBool::new(false),
//             visited_symlinks: Mutex::new(HashSet::new()),
//             ui: Mutex::new(CountUiState {
//                 current_dir_name: String::new(),
//                 critical_error: None,
//                 logs: VecDeque::new(),
//                 error_logs: VecDeque::new(),
//             }),
//         }
//     }
// Gene - Nov, 26, 2026: Added excluded_files counter to CountSharedState.
// Gene - Nov, 26, 2026: Added total_bytes atomic counter to CountSharedState.
// struct CountSharedState {
//     files: AtomicU64,
//     excluded_files: AtomicU64,
//     folders: AtomicU64,
//     errors: AtomicU64,
//     stop_requested: AtomicBool,
//     done: AtomicBool,
//     visited_symlinks: Mutex<HashSet<PathBuf>>,
//     ui: Mutex<CountUiState>,
// }
//
// pub struct CountJob {
//     state: Arc<CountSharedState>,
//     queue: Arc<CountWorkQueue>,
//     handle: Option<JoinHandle<()>>,
// }
//
// impl CountSharedState {
//     fn new() -> Self {
//         Self {
//             files: AtomicU64::new(0),
//             excluded_files: AtomicU64::new(0),
//             folders: AtomicU64::new(0),
//             errors: AtomicU64::new(0),
//             stop_requested: AtomicBool::new(false),
//             done: AtomicBool::new(false),
//             visited_symlinks: Mutex::new(HashSet::new()),
//             ui: Mutex::new(CountUiState {
//                 current_dir_name: String::new(),
//                 critical_error: None,
//                 logs: VecDeque::new(),
//                 error_logs: VecDeque::new(),
//             }),
//         }
//     }
struct CountSharedState {
    files: AtomicU64,
    excluded_files: AtomicU64,
    folders: AtomicU64,
    total_bytes: AtomicU64,
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
            excluded_files: AtomicU64::new(0),
            folders: AtomicU64::new(0),
            total_bytes: AtomicU64::new(0),
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

// fn run_count_worker(
//     canonical_root: &PathBuf,
//     log_interval: u64,
//     queue: &CountWorkQueue,
//     state: &CountSharedState,
// ) {
//     while let Some(dir) = queue.pop_dir(&state.stop_requested) {
//         let dir_name = path_basename(&dir);
//         state.set_current_dir(&dir_name);
//
//         let mut subdirs = Vec::new();
//         match fs::read_dir(&dir) {
//             Ok(entries) => {
//                 for entry_res in entries {
//                     if state.stop_requested.load(Ordering::Acquire) {
//                         break;
//                     }
//                     let entry = match entry_res {
//                         Ok(e) => e,
//                         Err(e) => {
//                             state.errors.fetch_add(1, Ordering::Relaxed);
//                             state.push_error_log(format!(
//                                 "Error accessing: {} — {e}",
//                                 dir.display()
//                             ));
//                             continue;
//                         }
//                     };
//
//                     let ft = match entry.file_type() {
//                         Ok(ft) => ft,
//                         Err(_) => continue,
//                     };
//
//                     if ft.is_file() {
//                         let name = entry.file_name().to_string_lossy().into_owned();
//                         state.record_counted_file(&name, log_interval);
//                     } else if ft.is_dir() {
//                         state.folders.fetch_add(1, Ordering::Relaxed);
//                         subdirs.push(entry.path());
//                     } else if ft.is_symlink() {
//                         let entry_path = entry.path();
//                         if !resolve_within_root(canonical_root, &entry_path) {
//                             continue;
//                         }
//                         if let Ok(canon_target) = fs::canonicalize(&entry_path) {
//                             if let Ok(meta) = fs::metadata(&entry_path) {
//                                 if meta.is_dir() {
//                                     let is_new = state
//                                         .visited_symlinks
//                                         .lock()
//                                         .map(|mut s| s.insert(canon_target))
//                                         .unwrap_or(false);
//                                     if is_new {
//                                         state.folders.fetch_add(1, Ordering::Relaxed);
//                                         subdirs.push(entry_path);
//                                     }
//                                 } else if meta.is_file() {
//                                     let name = entry.file_name().to_string_lossy().into_owned();
//                                     state.record_counted_file(&name, log_interval);
//                                 }
//                             }
//                         }
//                     }
//                 }
//             }
//             Err(e) => {
//                 state.errors.fetch_add(1, Ordering::Relaxed);
//                 state.push_error_log(format!("Error accessing: {} — {e}", dir.display()));
//             }
//         }
//
//         queue.push_subdirs_and_finish_dir(subdirs);
//     }
// }
//
// fn run_count(
//     target_path: PathBuf,
//     log_interval: u64,
//     queue: Arc<CountWorkQueue>,
//     state: Arc<CountSharedState>,
// ) {
//     let canonical_root = match fs::canonicalize(&target_path) {
//         Ok(p) => Arc::new(p),
//         Err(e) => {
//             state.set_critical_error(format!(
//                 "Failed to access target directory {}: {e}",
//                 target_path.display()
//             ));
//             state.done.store(true, Ordering::Release);
//             return;
//         }
//     };
//
//     let mut handles = Vec::with_capacity(DEFAULT_IO_WORKERS);
//     for _ in 0..DEFAULT_IO_WORKERS {
//         let q = Arc::clone(&queue);
//         let s = Arc::clone(&state);
//         let r = Arc::clone(&canonical_root);
//         if let Ok(h) = thread::Builder::new()
//             .name("count_engine_worker".to_string())
//             .spawn(move || {
//                 run_count_worker(&r, log_interval, &q, &s);
//             })
//         {
//             handles.push(h);
//         }
//     }
//
//     for h in handles {
//         let _ = h.join();
//     }
//
//     state.done.store(true, Ordering::Release);
// }
//
// fn build_count_poll_json(state: &CountSharedState) -> String {
//     let files = state.files.load(Ordering::Relaxed);
//     let folders = state.folders.load(Ordering::Relaxed);
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
//         "{{\"files\":{files},\"folders\":{folders},\"errors\":{errors},\"currentDirName\":"
//     );
// Gene - Nov, 26, 2026: Filtered counted files by include_mask and tracked excluded_files in worker & JSON poll output.
// Gene - Nov, 26, 2026: Added total_bytes tracking and size_only mode to count worker, coordinator, and JSON poll.
// fn run_count_worker(
//     canonical_root: &PathBuf,
//     log_interval: u64,
//     include_mask: u32,
//     queue: &CountWorkQueue,
//     state: &CountSharedState,
// ) {
//     while let Some(dir) = queue.pop_dir(&state.stop_requested) {
//         let dir_name = path_basename(&dir);
//         state.set_current_dir(&dir_name);
//
//         let mut subdirs = Vec::new();
//         match fs::read_dir(&dir) {
//             Ok(entries) => {
//                 for entry_res in entries {
//                     if state.stop_requested.load(Ordering::Acquire) {
//                         break;
//                     }
//                     let entry = match entry_res {
//                         Ok(e) => e,
//                         Err(e) => {
//                             state.errors.fetch_add(1, Ordering::Relaxed);
//                             state.push_error_log(format!(
//                                 "Error accessing: {} — {e}",
//                                 dir.display()
//                             ));
//                             continue;
//                         }
//                     };
//
//                     let ft = match entry.file_type() {
//                         Ok(ft) => ft,
//                         Err(_) => continue,
//                     };
//
//                     if ft.is_file() {
//                         let name = entry.file_name().to_string_lossy().into_owned();
//                         if matches_count_filter(&name, include_mask) {
//                             state.record_counted_file(&name, log_interval);
//                         } else {
//                             state.excluded_files.fetch_add(1, Ordering::Relaxed);
//                         }
//                     } else if ft.is_dir() {
//                         state.folders.fetch_add(1, Ordering::Relaxed);
//                         subdirs.push(entry.path());
//                     } else if ft.is_symlink() {
//                         let entry_path = entry.path();
//                         if !resolve_within_root(canonical_root, &entry_path) {
//                             continue;
//                         }
//                         if let Ok(canon_target) = fs::canonicalize(&entry_path) {
//                             if let Ok(meta) = fs::metadata(&entry_path) {
//                                 if meta.is_dir() {
//                                     let is_new = state
//                                         .visited_symlinks
//                                         .lock()
//                                         .map(|mut s| s.insert(canon_target))
//                                         .unwrap_or(false);
//                                     if is_new {
//                                         state.folders.fetch_add(1, Ordering::Relaxed);
//                                         subdirs.push(entry_path);
//                                     }
//                                 } else if meta.is_file() {
//                                     let name = entry.file_name().to_string_lossy().into_owned();
//                                     if matches_count_filter(&name, include_mask) {
//                                         state.record_counted_file(&name, log_interval);
//                                     } else {
//                                         state.excluded_files.fetch_add(1, Ordering::Relaxed);
//                                     }
//                                 }
//                             }
//                         }
//                     }
//                 }
//             }
//             Err(e) => {
//                 state.errors.fetch_add(1, Ordering::Relaxed);
//                 state.push_error_log(format!("Error accessing: {} — {e}", dir.display()));
//             }
//         }
//
//         queue.push_subdirs_and_finish_dir(subdirs);
//     }
// }
//
// fn run_count(
//     target_path: PathBuf,
//     log_interval: u64,
//     include_mask: u32,
//     queue: Arc<CountWorkQueue>,
//     state: Arc<CountSharedState>,
// ) {
//     let canonical_root = match fs::canonicalize(&target_path) {
//         Ok(p) => Arc::new(p),
//         Err(e) => {
//             state.set_critical_error(format!(
//                 "Failed to access target directory {}: {e}",
//                 target_path.display()
//             ));
//             state.done.store(true, Ordering::Release);
//             return;
//         }
//     };
//
//     let mut handles = Vec::with_capacity(DEFAULT_IO_WORKERS);
//     for _ in 0..DEFAULT_IO_WORKERS {
//         let q = Arc::clone(&queue);
//         let s = Arc::clone(&state);
//         let r = Arc::clone(&canonical_root);
//         if let Ok(h) = thread::Builder::new()
//             .name("count_engine_worker".to_string())
//             .spawn(move || {
//                 run_count_worker(&r, log_interval, include_mask, &q, &s);
//             })
//         {
//             handles.push(h);
//         }
//     }
//
//     for h in handles {
//         let _ = h.join();
//     }
//
//     state.done.store(true, Ordering::Release);
// }
//
// fn build_count_poll_json(state: &CountSharedState) -> String {
//     let files = state.files.load(Ordering::Relaxed);
//     let excluded_files = state.excluded_files.load(Ordering::Relaxed);
//     let folders = state.folders.load(Ordering::Relaxed);
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
//         "{{\"files\":{files},\"excludedFiles\":{excluded_files},\"folders\":{folders},\"errors\":{errors},\"currentDirName\":"
//     );
fn run_count_worker(
    canonical_root: &PathBuf,
    log_interval: u64,
    include_mask: u32,
    size_only: bool,
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
                        if size_only {
                            state.files.fetch_add(1, Ordering::Relaxed);
                            if let Ok(meta) = entry.metadata() {
                                state.total_bytes.fetch_add(meta.len(), Ordering::Relaxed);
                            }
                        } else {
                            let name = entry.file_name().to_string_lossy().into_owned();
                            if matches_count_filter(&name, include_mask) {
                                let size = entry.metadata().map(|m| m.len()).unwrap_or(0);
                                state.total_bytes.fetch_add(size, Ordering::Relaxed);
                                state.record_counted_file(&name, log_interval);
                            } else {
                                state.excluded_files.fetch_add(1, Ordering::Relaxed);
                            }
                        }
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
                                    if size_only {
                                        state.files.fetch_add(1, Ordering::Relaxed);
                                        state.total_bytes.fetch_add(meta.len(), Ordering::Relaxed);
                                    } else {
                                        let name = entry.file_name().to_string_lossy().into_owned();
                                        if matches_count_filter(&name, include_mask) {
                                            state
                                                .total_bytes
                                                .fetch_add(meta.len(), Ordering::Relaxed);
                                            state.record_counted_file(&name, log_interval);
                                        } else {
                                            state.excluded_files.fetch_add(1, Ordering::Relaxed);
                                        }
                                    }
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
    include_mask: u32,
    size_only: bool,
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
                run_count_worker(&r, log_interval, include_mask, size_only, &q, &s);
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
    let excluded_files = state.excluded_files.load(Ordering::Relaxed);
    let folders = state.folders.load(Ordering::Relaxed);
    let total_bytes = state.total_bytes.load(Ordering::Relaxed);
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
        "{{\"files\":{files},\"excludedFiles\":{excluded_files},\"folders\":{folders},\"totalBytes\":{total_bytes},\"errors\":{errors},\"currentDirName\":"
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
//         let log_interval = if raw.log_interval == 0 {
//             100
//         } else {
//             raw.log_interval
//         };
//
//         let state = Arc::new(CountSharedState::new());
//         let queue = Arc::new(CountWorkQueue::new(target_path.clone()));
//         let worker_state = Arc::clone(&state);
//         let worker_queue = Arc::clone(&queue);
//
//         let handle = thread::Builder::new()
//             .name("count_engine_coordinator".to_string())
//             .spawn(move || {
//                 let state_for_panic = Arc::clone(&worker_state);
//                 let run_res = catch_unwind(AssertUnwindSafe(|| {
//                     run_count(target_path, log_interval, worker_queue, worker_state);
//                 }));
// Gene - Nov, 26, 2026: Pass sanitized include_mask from CountConfigC to run_count.
// Gene - Nov, 26, 2026: Forward size_only flag from CountConfigC to run_count.
//         let log_interval = if raw.log_interval == 0 {
//             100
//         } else {
//             raw.log_interval
//         };
//         let include_mask = raw.include_mask & COUNT_CAT_ALL;
//
//         let state = Arc::new(CountSharedState::new());
//         let queue = Arc::new(CountWorkQueue::new(target_path.clone()));
//         let worker_state = Arc::clone(&state);
//         let worker_queue = Arc::clone(&queue);
//
//         let handle = thread::Builder::new()
//             .name("count_engine_coordinator".to_string())
//             .spawn(move || {
//                 let state_for_panic = Arc::clone(&worker_state);
//                 let run_res = catch_unwind(AssertUnwindSafe(|| {
//                     run_count(
//                         target_path,
//                         log_interval,
//                         include_mask,
//                         worker_queue,
//                         worker_state,
//                     );
//                 }));
        let size_only = raw.size_only != 0;
        let log_interval = if size_only {
            0
        } else if raw.log_interval == 0 {
            100
        } else {
            raw.log_interval
        };
        let include_mask = if size_only {
            COUNT_CAT_ALL
        } else {
            raw.include_mask & COUNT_CAT_ALL
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
                    run_count(
                        target_path,
                        log_interval,
                        include_mask,
                        size_only,
                        worker_queue,
                        worker_state,
                    );
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
        // run_count(root.clone(), 1, queue, Arc::clone(&state));
        // Gene - Nov, 26, 2026: Pass COUNT_CAT_ALL to run_count in existing tests.
        // run_count(root.clone(), 1, COUNT_CAT_ALL, queue, Arc::clone(&state));
        // Gene - Nov, 26, 2026: Pass size_only=false to existing tests and add total_bytes / size_only unit tests.
        run_count(root.clone(), 1, COUNT_CAT_ALL, false, queue, Arc::clone(&state));

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
        // run_count(root.clone(), 25, COUNT_CAT_ALL, queue, Arc::clone(&state));
        // Gene - Nov, 26, 2026: Pass size_only=false to run_count.
        run_count(root.clone(), 25, COUNT_CAT_ALL, false, queue, Arc::clone(&state));

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
        // run_count(target.clone(), 100, COUNT_CAT_ALL, queue, Arc::clone(&state));
        // Gene - Nov, 26, 2026: Pass size_only=false to run_count.
        run_count(target.clone(), 100, COUNT_CAT_ALL, false, queue, Arc::clone(&state));

        assert_eq!(state.files.load(Ordering::Relaxed), 1);
        assert_eq!(state.folders.load(Ordering::Relaxed), 0);

        let _ = fs::remove_dir_all(&root);
    }

    // Gene - Nov, 26, 2026: Added unit test verifying category bitmask filtering and excluded_files count.
    #[test]
    fn filters_files_by_category_mask_and_tracks_excluded() {
        let root = make_temp_dir("rust_count_filter_mask");
        let sub = root.join("nested");
        fs::create_dir_all(&sub).unwrap();

        fs::write(root.join("photo.jpg"), b"1").unwrap();
        fs::write(sub.join("diagram.PNG"), b"2").unwrap();
        fs::write(root.join("report.pdf"), b"3").unwrap();
        fs::write(sub.join("notes.docx"), b"4").unwrap();
        fs::write(root.join("clip.mp4"), b"5").unwrap();
        fs::write(sub.join("track.mp3"), b"6").unwrap();
        fs::write(root.join("bundle.zip"), b"7").unwrap();
        fs::write(sub.join("firmware.bin"), b"8").unwrap();
        fs::write(root.join("README"), b"9").unwrap();

        let run_with_mask = |mask: u32| -> (u64, u64, u64) {
            let state = Arc::new(CountSharedState::new());
            let queue = Arc::new(CountWorkQueue::new(root.clone()));
            // run_count(root.clone(), 100, mask, queue, Arc::clone(&state));
            // Gene - Nov, 26, 2026: Pass size_only=false to run_count.
            run_count(root.clone(), 100, mask, false, queue, Arc::clone(&state));
            (
                state.files.load(Ordering::Relaxed),
                state.excluded_files.load(Ordering::Relaxed),
                state.folders.load(Ordering::Relaxed),
            )
        };

        assert_eq!(run_with_mask(COUNT_CAT_ALL), (9, 0, 1));
        assert_eq!(run_with_mask(COUNT_CAT_IMAGES), (2, 7, 1));
        assert_eq!(run_with_mask(COUNT_CAT_DOCUMENTS), (2, 7, 1));
        assert_eq!(
            run_with_mask(COUNT_CAT_IMAGES | COUNT_CAT_DOCUMENTS),
            (4, 5, 1)
        );
        assert_eq!(
            run_with_mask(COUNT_CAT_VIDEOS | COUNT_CAT_AUDIO | COUNT_CAT_ARCHIVES),
            (3, 6, 1)
        );
        assert_eq!(run_with_mask(COUNT_CAT_OTHERS), (2, 7, 1));
        assert_eq!(run_with_mask(0), (0, 9, 1));

        let _ = fs::remove_dir_all(&root);
    }

    // Gene - Nov, 26, 2026: Verify total_bytes sums only matched categories and size_only sums all files without logs.
    #[test]
    fn sums_total_bytes_for_all_and_filtered_categories() {
        let root = make_temp_dir("rust_count_total_bytes");
        let sub = root.join("nested");
        fs::create_dir_all(&sub).unwrap();

        fs::write(root.join("photo.jpg"), vec![b'a'; 10]).unwrap();
        fs::write(sub.join("banner.png"), vec![b'b'; 25]).unwrap();
        fs::write(root.join("report.pdf"), vec![b'c'; 100]).unwrap();
        fs::write(sub.join("clip.mp4"), vec![b'd'; 250]).unwrap();

        let state_all = Arc::new(CountSharedState::new());
        let queue_all = Arc::new(CountWorkQueue::new(root.clone()));
        run_count(
            root.clone(),
            100,
            COUNT_CAT_ALL,
            false,
            queue_all,
            Arc::clone(&state_all),
        );
        assert_eq!(state_all.files.load(Ordering::Relaxed), 4);
        assert_eq!(state_all.total_bytes.load(Ordering::Relaxed), 385);

        let state_img = Arc::new(CountSharedState::new());
        let queue_img = Arc::new(CountWorkQueue::new(root.clone()));
        run_count(
            root.clone(),
            100,
            COUNT_CAT_IMAGES,
            false,
            queue_img,
            Arc::clone(&state_img),
        );
        assert_eq!(state_img.files.load(Ordering::Relaxed), 2);
        assert_eq!(state_img.excluded_files.load(Ordering::Relaxed), 2);
        assert_eq!(state_img.total_bytes.load(Ordering::Relaxed), 35);

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn size_only_mode_sums_entire_folder_without_per_file_logs() {
        let root = make_temp_dir("rust_count_size_only");
        let sub = root.join("sub");
        fs::create_dir_all(&sub).unwrap();

        fs::write(root.join("a.jpg"), vec![b'1'; 12]).unwrap();
        fs::write(sub.join("b.pdf"), vec![b'2'; 38]).unwrap();
        fs::write(sub.join("c.bin"), vec![b'3'; 50]).unwrap();

        let state = Arc::new(CountSharedState::new());
        let queue = Arc::new(CountWorkQueue::new(root.clone()));
        // Pass include_mask = 0 to prove size_only ignores category filtering and emits no logs.
        run_count(root.clone(), 0, 0, true, queue, Arc::clone(&state));

        assert_eq!(state.files.load(Ordering::Relaxed), 3);
        assert_eq!(state.excluded_files.load(Ordering::Relaxed), 0);
        assert_eq!(state.folders.load(Ordering::Relaxed), 1);
        assert_eq!(state.total_bytes.load(Ordering::Relaxed), 100);
        assert!(state.ui.lock().unwrap().logs.is_empty());

        let _ = fs::remove_dir_all(&root);
    }
}
