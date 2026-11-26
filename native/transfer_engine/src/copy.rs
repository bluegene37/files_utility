// Gene - Nov, 25, 2026: High-speed 8-worker Rust copy engine with bounded streaming
// queue (no per-batch barrier stalls), kernel CopyFileExW / fs::copy offload,
// destination pre-listing, zero-canonicalize normal walks, and exact resume tracking.

use std::collections::{HashMap, HashSet, VecDeque};
use std::ffi::{CString, OsString};
use std::fmt::Write as _;
use std::fs::{self, Metadata};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant, SystemTime};

// use crate::common::{
//     c_str_to_string, fast_copy_to_part_and_swap, path_basename, push_json_escaped,
//     relative_dir_string, resolve_within_root, system_time_to_epoch_ms, DEFAULT_IO_WORKERS,
//     MAX_QUEUED_LOGS, MAX_QUEUE_CAPACITY,
// };
// Gene - Nov, 26, 2026: Import case-insensitive filename_key, dynamic io_worker_count, lexical dest-skipping, and single-canonicalize symlink check.
use crate::common::{
    c_str_to_string, fast_copy_to_part_and_swap, filename_key, io_worker_count,
    lexical_equal_or_within, normalize_lexical, path_basename, push_json_escaped,
    relative_dir_string, resolve_canonical_within_root, system_time_to_epoch_ms, FilenameKey,
    MAX_QUEUED_LOGS, MAX_QUEUE_CAPACITY,
};

const PHASE_SCANNING: u8 = 1;
const PHASE_COPYING: u8 = 2;
const PHASE_CHECKING: u8 = 3;
const PHASE_DONE: u8 = 4;

#[repr(C)]
pub struct CopyConfigC {
    pub source_path: *const c_char,
    pub dest_path: *const c_char,
    pub progress_file_path: *const c_char,
    pub completed_dirs_serialized: *const c_char,
    pub last_processed_serialized: *const c_char,
    pub enable_age_filter: u8,
    pub age_threshold_epoch_ms: i64,
    pub enable_date_range: u8,
    pub from_inclusive_epoch_ms: i64,
    pub to_exclusive_epoch_ms: i64,
    pub initial_copied: u64,
    pub initial_skipped: u64,
    pub initial_already_exist: u64,
    pub initial_errors: u64,
    pub initial_inspected: u64,
    pub log_interval: u64,
}

struct CopyConfig {
    source_path: PathBuf,
    dest_path: PathBuf,
    progress_file_path: Option<PathBuf>,
    completed_dirs: HashSet<String>,
    last_processed_files: HashMap<String, String>,
    enable_age_filter: bool,
    age_threshold_epoch_ms: i64,
    enable_date_range: bool,
    from_inclusive_epoch_ms: i64,
    to_exclusive_epoch_ms: i64,
    initial_copied: u64,
    initial_skipped: u64,
    initial_already_exist: u64,
    initial_errors: u64,
    initial_inspected: u64,
    log_interval: u64,
}

struct CopyTask {
    src: PathBuf,
    dest: PathBuf,
    modified: Option<SystemTime>,
    dir_pending: Option<Arc<AtomicUsize>>,
}

struct QueueInner {
    tasks: VecDeque<CopyTask>,
    closed: bool,
}

struct CopyQueue {
    inner: Mutex<QueueInner>,
    not_empty: Condvar,
    not_full: Condvar,
}

impl CopyQueue {
    fn new() -> Self {
        Self {
            inner: Mutex::new(QueueInner {
                tasks: VecDeque::with_capacity(MAX_QUEUE_CAPACITY),
                closed: false,
            }),
            not_empty: Condvar::new(),
            not_full: Condvar::new(),
        }
    }

    fn push(&self, task: CopyTask, state: &CopySharedState) -> bool {
        let mut guard = match self.inner.lock() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        while guard.tasks.len() >= MAX_QUEUE_CAPACITY && !guard.closed && !state.is_stopped() {
            guard = match self.not_full.wait(guard) {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
        }
        if guard.closed || state.is_stopped() {
            return false;
        }
        guard.tasks.push_back(task);
        self.not_empty.notify_one();
        true
    }

    fn pop(&self, state: &CopySharedState) -> Option<CopyTask> {
        let mut guard = match self.inner.lock() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        while guard.tasks.is_empty() && !guard.closed && !state.is_stopped() {
            guard = match self.not_empty.wait(guard) {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
        }
        if state.is_stopped() || (guard.closed && guard.tasks.is_empty()) {
            return None;
        }
        let popped = guard.tasks.pop_front();
        self.not_full.notify_one();
        popped
    }

    // Gene - Nov, 26, 2026: Recover poisoned mutexes on close and use try_lock for transient UI phase updates.
    // fn close(&self, clear_pending: bool) {
    //     if let Ok(mut guard) = self.inner.lock() {
    //         if clear_pending {
    //             guard.tasks.clear();
    //         }
    //         guard.closed = true;
    //         self.not_empty.notify_all();
    //         self.not_full.notify_all();
    //     }
    // }
    fn close(&self, clear_pending: bool) {
        let mut guard = self.inner.lock().unwrap_or_else(|p| p.into_inner());
        if clear_pending {
            guard.tasks.clear();
        }
        guard.closed = true;
        self.not_empty.notify_all();
        self.not_full.notify_all();
    }
}

struct CopyUiState {
    phase: u8,
    current_dir_name: String,
    latest_copied_name: String,
    critical_error: Option<String>,
    logs: VecDeque<String>,
    error_logs: VecDeque<String>,
}

struct CopySharedState {
    files_copied: AtomicU64,
    files_skipped: AtomicU64,
    files_already_exist: AtomicU64,
    errors: AtomicU64,
    files_inspected: AtomicU64,
    dirs_skipped: AtomicU64,
    stop_requested: AtomicBool,
    cancel_flag: AtomicI32,
    done: AtomicBool,
    pause_lock: Mutex<bool>,
    pause_cvar: Condvar,
    ui: Mutex<CopyUiState>,
}

pub struct CopyJob {
    state: Arc<CopySharedState>,
    queue: Arc<CopyQueue>,
    handle: Option<JoinHandle<()>>,
}

impl CopySharedState {
    fn new(cfg: &CopyConfig) -> Self {
        Self {
            files_copied: AtomicU64::new(cfg.initial_copied),
            files_skipped: AtomicU64::new(cfg.initial_skipped),
            files_already_exist: AtomicU64::new(cfg.initial_already_exist),
            errors: AtomicU64::new(cfg.initial_errors),
            files_inspected: AtomicU64::new(cfg.initial_inspected),
            dirs_skipped: AtomicU64::new(0),
            stop_requested: AtomicBool::new(false),
            cancel_flag: AtomicI32::new(0),
            done: AtomicBool::new(false),
            pause_lock: Mutex::new(false),
            pause_cvar: Condvar::new(),
            ui: Mutex::new(CopyUiState {
                phase: PHASE_SCANNING,
                current_dir_name: String::new(),
                latest_copied_name: String::new(),
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

    // Gene - Nov, 26, 2026: Use try_lock for transient phase updates while blocking for PHASE_DONE, and write progress files atomically.
    // fn set_phase(&self, phase: u8, dir_name: Option<&str>, copied_name: Option<&str>) {
    //     if let Ok(mut ui) = self.ui.lock() {
    //         ui.phase = phase;
    //         if let Some(d) = dir_name {
    //             ui.current_dir_name.clear();
    //             ui.current_dir_name.push_str(d);
    //         }
    //         if let Some(c) = copied_name {
    //             ui.latest_copied_name.clear();
    //             ui.latest_copied_name.push_str(c);
    //         }
    //     }
    // }
    fn set_phase(&self, phase: u8, dir_name: Option<&str>, copied_name: Option<&str>) {
        let mut ui = if phase == PHASE_DONE {
            match self.ui.lock() {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            }
        } else {
            match self.ui.try_lock() {
                Ok(g) => g,
                Err(_) => return,
            }
        };
        ui.phase = phase;
        if let Some(d) = dir_name {
            ui.current_dir_name.clear();
            ui.current_dir_name.push_str(d);
        }
        if let Some(c) = copied_name {
            ui.latest_copied_name.clear();
            ui.latest_copied_name.push_str(c);
        }
    }

    fn set_critical_error(&self, err: String) {
        if let Ok(mut ui) = self.ui.lock() {
            ui.critical_error = Some(err);
        }
    }

    fn is_stopped(&self) -> bool {
        self.stop_requested.load(Ordering::Acquire)
    }

    fn wait_if_paused(&self) -> bool {
        let mut paused = match self.pause_lock.lock() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        while *paused && !self.is_stopped() {
            paused = match self.pause_cvar.wait(paused) {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
        }
        !self.is_stopped()
    }
}

fn save_progress_file(
    path: &Path,
    config: &CopyConfig,
    completed_dirs: &HashSet<String>,
    last_processed_files: &HashMap<String, String>,
    state: &CopySharedState,
) {
    if let Some(parent) = path.parent() {
        if !parent.exists() {
            let _ = fs::create_dir_all(parent);
        }
    }

    let mut json = String::with_capacity(512);
    json.push_str("{\"sourcePath\":");
    push_json_escaped(&mut json, &config.source_path.to_string_lossy());
    json.push_str(",\"destPath\":");
    push_json_escaped(&mut json, &config.dest_path.to_string_lossy());
    json.push_str(",\"completedDirs\":[");
    for (idx, d) in completed_dirs.iter().enumerate() {
        if idx > 0 {
            json.push(',');
        }
        push_json_escaped(&mut json, d);
    }
    json.push_str("],\"lastProcessedFiles\":{");
    for (idx, (k, v)) in last_processed_files.iter().enumerate() {
        if idx > 0 {
            json.push(',');
        }
        push_json_escaped(&mut json, k);
        json.push(':');
        push_json_escaped(&mut json, v);
    }
    let _ = write!(
        json,
        "}},\"filesCopied\":{},\"filesSkipped\":{},\"filesAlreadyExist\":{},\"errors\":{},\"filesInspected\":{}}}",
        state.files_copied.load(Ordering::Relaxed),
        state.files_skipped.load(Ordering::Relaxed),
        state.files_already_exist.load(Ordering::Relaxed),
        state.errors.load(Ordering::Relaxed),
        state.files_inspected.load(Ordering::Relaxed),
    );

    // let _ = fs::write(path, json);
    let mut tmp_os = path.as_os_str().to_os_string();
    tmp_os.push(".tmp");
    let tmp_path = PathBuf::from(tmp_os);
    if fs::write(&tmp_path, &json).is_ok() {
        if fs::rename(&tmp_path, path).is_err() {
            let _ = fs::remove_file(&tmp_path);
            let _ = fs::write(path, &json);
        }
    } else {
        let _ = fs::write(path, &json);
    }
}

fn spawn_copy_worker(
    queue: Arc<CopyQueue>,
    state: Arc<CopySharedState>,
    log_interval: u64,
) -> Option<JoinHandle<()>> {
    thread::Builder::new()
        .name("copy_engine_io".to_string())
        .spawn(move || {
            while let Some(task) = queue.pop(&state) {
                if !state.wait_if_paused() {
                    if let Some(ref cnt) = task.dir_pending {
                        cnt.fetch_sub(1, Ordering::Release);
                    }
                    break;
                }

                let file_name = path_basename(&task.src);
                match fast_copy_to_part_and_swap(
                    &task.src,
                    &task.dest,
                    task.modified,
                    &state.stop_requested,
                    &state.cancel_flag,
                    true,
                ) {
                    Ok(()) => {
                        let copied = state.files_copied.fetch_add(1, Ordering::Relaxed) + 1;
                        if log_interval > 0 && copied % log_interval == 0 {
                            state.set_phase(PHASE_COPYING, None, Some(&file_name));
                            state.push_log(format!(
                                "✓ Copied {log_interval} files (total: {copied}) – latest: {file_name}"
                            ));
                        }
                    }
                    Err(err) if err == "__STOPPED__" => {
                        if let Some(ref cnt) = task.dir_pending {
                            cnt.fetch_sub(1, Ordering::Release);
                        }
                        break;
                    }
                    Err(err) => {
                        state.errors.fetch_add(1, Ordering::Relaxed);
                        state.push_error_log(format!("✗ Failed to copy {file_name}: {err}"));
                    }
                }

                if let Some(ref cnt) = task.dir_pending {
                    cnt.fetch_sub(1, Ordering::Release);
                }
            }
        })
        .ok()
}

// Gene - Nov, 26, 2026: Case-accurate dest map, zero-lastProcessed parallel copy, iterative DFS stack,
// dest-inside-source guard, single-canonicalize symlinks, dynamic workers, and safe resume completion tracking.
// fn read_dest_sizes(dest_dir: &Path) -> HashMap<OsString, u64> {
//     let mut map = HashMap::new();
//     let entries = match fs::read_dir(dest_dir) {
//         Ok(iter) => iter,
//         Err(_) => return map,
//     };
//     for entry in entries.flatten() {
//         if let Ok(ft) = entry.file_type() {
//             if ft.is_file() {
//                 if let Ok(meta) = entry.metadata() {
//                     map.insert(entry.file_name(), meta.len());
//                 }
//             }
//         }
//     }
//     map
// }
//
// fn drain_completed_trackers(
//     pending_trackers: &mut Vec<(String, Arc<AtomicUsize>)>,
//     completed_dirs: &mut HashSet<String>,
//     last_processed_files: &mut HashMap<String, String>,
// ) {
//     pending_trackers.retain(|(rel, cnt)| {
//         if cnt.load(Ordering::Acquire) == 0 {
//             completed_dirs.insert(rel.clone());
//             last_processed_files.remove(rel);
//             false
//         } else {
//             true
//         }
//     });
// }
//
// #[allow(clippy::too_many_arguments)]
// fn inspect_and_enqueue_copy_file(
//     file_path: PathBuf,
//     name_os: OsString,
//     name_str: &str,
//     known_meta: Option<Metadata>,
//     dir_name: &str,
//     rel_path: &str,
//     dest_dir: &Path,
//     dest_dir_created: &mut bool,
//     dest_sizes: &mut Option<HashMap<OsString, u64>>,
//     created_dirs: &mut HashSet<PathBuf>,
//     dir_pending: &Option<Arc<AtomicUsize>>,
//     config: &CopyConfig,
//     state: &CopySharedState,
//     queue: &CopyQueue,
//     last_processed_files: &mut HashMap<String, String>,
// ) -> bool {
//     state.files_inspected.fetch_add(1, Ordering::Relaxed);
//
//     let meta = match known_meta {
//         Some(m) => m,
//         None => match fs::metadata(&file_path) {
//             Ok(m) => m,
//             Err(e) => {
//                 state.errors.fetch_add(1, Ordering::Relaxed);
//                 state.push_error_log(format!("✗ Failed to inspect {name_str}: {e}"));
//                 return true;
//             }
//         },
//     };
//
//     let src_size = meta.len();
//     let modified = match meta.modified() {
//         Ok(m) => m,
//         Err(e) => {
//             state.errors.fetch_add(1, Ordering::Relaxed);
//             state.push_error_log(format!("✗ Failed to inspect {name_str}: {e}"));
//             return true;
//         }
//     };
//
//     if config.enable_age_filter || config.enable_date_range {
//         let modified_ms = system_time_to_epoch_ms(modified);
//         if config.enable_age_filter && modified_ms > config.age_threshold_epoch_ms {
//             state.files_skipped.fetch_add(1, Ordering::Relaxed);
//             return true;
//         }
//         if config.enable_date_range
//             && (modified_ms < config.from_inclusive_epoch_ms
//                 || modified_ms >= config.to_exclusive_epoch_ms)
//         {
//             state.files_skipped.fetch_add(1, Ordering::Relaxed);
//             return true;
//         }
//     }
//
//     let sizes_map = dest_sizes.get_or_insert_with(|| read_dest_sizes(dest_dir));
//     if sizes_map.get(&name_os) == Some(&src_size) {
//         let already = state.files_already_exist.fetch_add(1, Ordering::Relaxed) + 1;
//         if config.log_interval > 0 && already % config.log_interval == 0 {
//             state.set_phase(PHASE_CHECKING, Some(dir_name), None);
//             state.push_log(format!(
//                 "⏭ {already} files already exist at destination (skipping)"
//             ));
//         }
//         return true;
//     }
//
//     if !*dest_dir_created {
//         if !created_dirs.contains(dest_dir) {
//             if let Err(e) = fs::create_dir_all(dest_dir) {
//                 state.errors.fetch_add(1, Ordering::Relaxed);
//                 state.push_error_log(format!("✗ Failed to copy {name_str}: {e}"));
//                 return true;
//             }
//             created_dirs.insert(dest_dir.to_path_buf());
//         }
//         *dest_dir_created = true;
//     }
//
//     if let Some(ref cnt) = dir_pending {
//         cnt.fetch_add(1, Ordering::AcqRel);
//     }
//
//     let ok = queue.push(
//         CopyTask {
//             src: file_path,
//             dest: dest_dir.join(&name_os),
//             modified: Some(modified),
//             dir_pending: dir_pending.clone(),
//         },
//         state,
//     );
//     if !ok {
//         if let Some(ref cnt) = dir_pending {
//             cnt.fetch_sub(1, Ordering::AcqRel);
//         }
//         return false;
//     }
//
//     if config.progress_file_path.is_some() {
//         last_processed_files.insert(rel_path.to_string(), name_str.to_string());
//     }
//     true
// }
//
// struct ResumeFileCandidate {
//     path: PathBuf,
//     name_os: OsString,
//     name: String,
//     known_meta: Option<Metadata>,
// }
//
// #[allow(clippy::too_many_arguments)]
// fn walk_and_copy(
//     dir: &Path,
//     canonical_root: &Path,
//     config: &CopyConfig,
//     state: &CopySharedState,
//     queue: &CopyQueue,
//     visited_symlinks: &mut HashSet<PathBuf>,
//     created_dirs: &mut HashSet<PathBuf>,
//     completed_dirs: &mut HashSet<String>,
//     last_processed_files: &mut HashMap<String, String>,
//     pending_trackers: &mut Vec<(String, Arc<AtomicUsize>)>,
//     last_save: &mut Instant,
// ) {
//     if state.is_stopped() || !state.wait_if_paused() {
//         return;
//     }
//
//     let rel_path = relative_dir_string(dir, &config.source_path);
//     if completed_dirs.contains(&rel_path) {
//         state.dirs_skipped.fetch_add(1, Ordering::Relaxed);
//         return;
//     }
//
//     let dir_name = path_basename(dir);
//     state.set_phase(PHASE_SCANNING, Some(&dir_name), None);
//
//     let entries = match fs::read_dir(dir) {
//         Ok(iter) => iter,
//         Err(e) => {
//             state.errors.fetch_add(1, Ordering::Relaxed);
//             state.push_error_log(format!("✗ Cannot access: {} ({e})", dir.display()));
//             return;
//         }
//     };
//
//     let dest_dir = if rel_path == "." {
//         config.dest_path.clone()
//     } else {
//         config.dest_path.join(&rel_path)
//     };
//     let mut dest_dir_created = created_dirs.contains(&dest_dir);
//     let mut dest_sizes: Option<HashMap<OsString, u64>> = None;
//     let dir_pending = config
//         .progress_file_path
//         .as_ref()
//         .map(|_| Arc::new(AtomicUsize::new(0)));
//
//     let mut subdirs: Vec<PathBuf> = Vec::new();
//     let resume_last_name = last_processed_files.get(&rel_path).cloned();
//
//     if let Some(ref last_name) = resume_last_name {
//         // Resuming an interrupted directory requires deterministic filename sorting.
//         let mut files: Vec<ResumeFileCandidate> = Vec::new();
//         for entry_res in entries {
//             if state.is_stopped() {
//                 return;
//             }
//             let entry = match entry_res {
//                 Ok(e) => e,
//                 Err(_) => continue,
//             };
//             let entry_path = entry.path();
//             let ft = match entry.file_type() {
//                 Ok(t) => t,
//                 Err(_) => continue,
//             };
//             if ft.is_file() {
//                 let name_os = entry.file_name();
//                 let name = name_os.to_string_lossy().into_owned();
//                 files.push(ResumeFileCandidate {
//                     path: entry_path,
//                     name_os,
//                     name,
//                     known_meta: entry.metadata().ok(),
//                 });
//             } else if ft.is_dir() {
//                 subdirs.push(entry_path);
//             } else if ft.is_symlink() && resolve_within_root(canonical_root, &entry_path) {
//                 if let Ok(canon_target) = fs::canonicalize(&entry_path) {
//                     if let Ok(meta) = fs::metadata(&entry_path) {
//                         if meta.is_dir() {
//                             if visited_symlinks.insert(canon_target) {
//                                 subdirs.push(entry_path);
//                             }
//                         } else if meta.is_file() {
//                             let name_os = entry.file_name();
//                             let name = name_os.to_string_lossy().into_owned();
//                             files.push(ResumeFileCandidate {
//                                 path: entry_path,
//                                 name_os,
//                                 name,
//                                 known_meta: Some(meta),
//                             });
//                         }
//                     }
//                 }
//             }
//         }
//
//         files.sort_by(|a, b| a.name.cmp(&b.name));
//         let start_idx = files
//             .iter()
//             .position(|f| &f.name == last_name)
//             .map(|i| i + 1)
//             .unwrap_or(0);
//
//         for candidate in files.into_iter().skip(start_idx) {
//             if state.is_stopped() || !state.wait_if_paused() {
//                 break;
//             }
//             if !inspect_and_enqueue_copy_file(
//                 candidate.path,
//                 candidate.name_os,
//                 &candidate.name,
//                 candidate.known_meta,
//                 &dir_name,
//                 &rel_path,
//                 &dest_dir,
//                 &mut dest_dir_created,
//                 &mut dest_sizes,
//                 created_dirs,
//                 &dir_pending,
//                 config,
//                 state,
//                 queue,
//                 last_processed_files,
//             ) {
//                 break;
//             }
//         }
//     } else {
//         // Streaming fast-path: process read_dir entries directly with zero sorting overhead.
//         for entry_res in entries {
//             if state.is_stopped() || !state.wait_if_paused() {
//                 break;
//             }
//             let entry = match entry_res {
//                 Ok(e) => e,
//                 Err(_) => continue,
//             };
//             let entry_path = entry.path();
//             let ft = match entry.file_type() {
//                 Ok(t) => t,
//                 Err(_) => continue,
//             };
//
//             if ft.is_file() {
//                 let name_os = entry.file_name();
//                 let name_str = name_os.to_string_lossy().into_owned();
//                 if !inspect_and_enqueue_copy_file(
//                     entry_path,
//                     name_os,
//                     &name_str,
//                     entry.metadata().ok(),
//                     &dir_name,
//                     &rel_path,
//                     &dest_dir,
//                     &mut dest_dir_created,
//                     &mut dest_sizes,
//                     created_dirs,
//                     &dir_pending,
//                     config,
//                     state,
//                     queue,
//                     last_processed_files,
//                 ) {
//                     break;
//                 }
//             } else if ft.is_dir() {
//                 subdirs.push(entry_path);
//             } else if ft.is_symlink() && resolve_within_root(canonical_root, &entry_path) {
//                 if let Ok(canon_target) = fs::canonicalize(&entry_path) {
//                     if let Ok(meta) = fs::metadata(&entry_path) {
//                         if meta.is_dir() {
//                             if visited_symlinks.insert(canon_target) {
//                                 subdirs.push(entry_path);
//                             }
//                         } else if meta.is_file() {
//                             let name_os = entry.file_name();
//                             let name_str = name_os.to_string_lossy().into_owned();
//                             if !inspect_and_enqueue_copy_file(
//                                 entry_path,
//                                 name_os,
//                                 &name_str,
//                                 Some(meta),
//                                 &dir_name,
//                                 &rel_path,
//                                 &dest_dir,
//                                 &mut dest_dir_created,
//                                 &mut dest_sizes,
//                                 created_dirs,
//                                 &dir_pending,
//                                 config,
//                                 state,
//                                 queue,
//                                 last_processed_files,
//                             ) {
//                                 break;
//                             }
//                         }
//                     }
//                 }
//             }
//
//             if let Some(ref progress_path) = config.progress_file_path {
//                 if last_save.elapsed() >= Duration::from_secs(2) {
//                     drain_completed_trackers(pending_trackers, completed_dirs, last_processed_files);
//                     save_progress_file(
//                         progress_path,
//                         config,
//                         completed_dirs,
//                         last_processed_files,
//                         state,
//                     );
//                     *last_save = Instant::now();
//                 }
//             }
//         }
//     }
//
//     if let Some(cnt) = dir_pending {
//         pending_trackers.push((rel_path.clone(), cnt));
//     }
//
//     subdirs.sort_by(|a, b| path_basename(a).cmp(&path_basename(b)));
//     for sub in subdirs {
//         if state.is_stopped() {
//             return;
//         }
//         walk_and_copy(
//             &sub,
//             canonical_root,
//             config,
//             state,
//             queue,
//             visited_symlinks,
//             created_dirs,
//             completed_dirs,
//             last_processed_files,
//             pending_trackers,
//             last_save,
//         );
//     }
//
//     if let Some(ref progress_path) = config.progress_file_path {
//         drain_completed_trackers(pending_trackers, completed_dirs, last_processed_files);
//         if last_save.elapsed() >= Duration::from_secs(2) {
//             save_progress_file(
//                 progress_path,
//                 config,
//                 completed_dirs,
//                 last_processed_files,
//                 state,
//             );
//             *last_save = Instant::now();
//         }
//     }
// }
//
// fn run_copy_coordinator(
//     config: CopyConfig,
//     state: Arc<CopySharedState>,
//     queue: Arc<CopyQueue>,
// ) {
//     let is_resuming =
//         !config.completed_dirs.is_empty() || !config.last_processed_files.is_empty();
//
//     let canonical_root = match fs::canonicalize(&config.source_path) {
//         Ok(p) => p,
//         Err(e) => {
//             state.set_critical_error(format!(
//                 "Failed to access source directory {}: {e}",
//                 config.source_path.display()
//             ));
//             queue.close(true);
//             state.set_phase(PHASE_DONE, None, None);
//             state.done.store(true, Ordering::Release);
//             return;
//         }
//     };
//
//     let mut workers = Vec::with_capacity(DEFAULT_IO_WORKERS);
//     for _ in 0..DEFAULT_IO_WORKERS {
//         if let Some(h) = spawn_copy_worker(
//             Arc::clone(&queue),
//             Arc::clone(&state),
//             config.log_interval,
//         ) {
//             workers.push(h);
//         }
//     }
//
//     let mut visited_symlinks: HashSet<PathBuf> = HashSet::new();
//     let mut created_dirs: HashSet<PathBuf> = HashSet::new();
//     let mut completed_dirs = config.completed_dirs.clone();
//     let mut last_processed_files = config.last_processed_files.clone();
//     let mut pending_trackers: Vec<(String, Arc<AtomicUsize>)> = Vec::new();
//     let mut last_save = Instant::now();
//
//     walk_and_copy(
//         &config.source_path,
//         &canonical_root,
//         &config,
//         &state,
//         &queue,
//         &mut visited_symlinks,
//         &mut created_dirs,
//         &mut completed_dirs,
//         &mut last_processed_files,
//         &mut pending_trackers,
//         &mut last_save,
//     );
//
//     queue.close(state.is_stopped());
//     for w in workers {
//         let _ = w.join();
//     }
//
//     if state.is_stopped() {
//         drain_completed_trackers(&mut pending_trackers, &mut completed_dirs, &mut last_processed_files);
//         if let Some(ref progress_path) = config.progress_file_path {
//             save_progress_file(
//                 progress_path,
//                 &config,
//                 &completed_dirs,
//                 &last_processed_files,
//                 &state,
//             );
//         }
//     } else {
//         let dirs_skipped = state.dirs_skipped.load(Ordering::Relaxed);
//         let resume_note = if is_resuming {
//             format!(" ({dirs_skipped} dirs skipped via resume)")
//         } else {
//             String::new()
//         };
//         state.push_log(format!("🏁 Copy completed successfully.{resume_note}"));
//         if let Some(ref progress_path) = config.progress_file_path {
//             let _ = fs::remove_file(progress_path);
//         }
//     }
//
//     state.set_phase(PHASE_DONE, None, None);
//     state.done.store(true, Ordering::Release);
// }
//
// fn build_copy_poll_json(state: &CopySharedState) -> String {
//     let files_copied = state.files_copied.load(Ordering::Relaxed);
//     let files_skipped = state.files_skipped.load(Ordering::Relaxed);
//     let files_already_exist = state.files_already_exist.load(Ordering::Relaxed);
//     let errors = state.errors.load(Ordering::Relaxed);
//     let files_inspected = state.files_inspected.load(Ordering::Relaxed);
//     let dirs_skipped = state.dirs_skipped.load(Ordering::Relaxed);
//     let is_done = state.done.load(Ordering::Acquire);
//
//     let (phase, current_dir_name, latest_copied_name, critical_error, logs, error_logs) =
//         match state.ui.lock() {
//             Ok(mut ui) => (
//                 ui.phase,
//                 ui.current_dir_name.clone(),
//                 ui.latest_copied_name.clone(),
//                 ui.critical_error.take(),
//                 ui.logs.drain(..).collect::<Vec<_>>(),
//                 ui.error_logs.drain(..).collect::<Vec<_>>(),
//             ),
//             Err(_) => (
//                 PHASE_DONE,
//                 String::new(),
//                 String::new(),
//                 None,
//                 Vec::new(),
//                 Vec::new(),
//             ),
//         };
//
//     let mut json = String::with_capacity(384);
fn read_dest_sizes(dest_dir: &Path) -> HashMap<FilenameKey, u64> {
    let mut map = HashMap::new();
    let entries = match fs::read_dir(dest_dir) {
        Ok(iter) => iter,
        Err(_) => return map,
    };
    for entry in entries.flatten() {
        if let Ok(ft) = entry.file_type() {
            if ft.is_file() {
                if let Ok(meta) = entry.metadata() {
                    map.insert(filename_key(&entry.file_name()), meta.len());
                }
            }
        }
    }
    map
}

fn drain_completed_trackers(
    pending_trackers: &mut Vec<(String, Arc<AtomicUsize>)>,
    completed_dirs: &mut HashSet<String>,
    last_processed_files: &mut HashMap<String, String>,
) {
    pending_trackers.retain(|(rel, cnt)| {
        if cnt.load(Ordering::Acquire) == 0 {
            completed_dirs.insert(rel.clone());
            last_processed_files.remove(rel);
            false
        } else {
            true
        }
    });
}

#[allow(clippy::too_many_arguments)]
fn inspect_and_enqueue_copy_file(
    file_path: PathBuf,
    name_os: OsString,
    name_str: &str,
    known_meta: Option<Metadata>,
    dir_name: &str,
    rel_path: &str,
    dest_dir: &Path,
    dest_dir_created: &mut bool,
    dest_sizes: &mut Option<HashMap<FilenameKey, u64>>,
    created_dirs: &mut HashSet<PathBuf>,
    dir_pending: &Option<Arc<AtomicUsize>>,
    config: &CopyConfig,
    state: &CopySharedState,
    queue: &CopyQueue,
    last_processed_files: &mut HashMap<String, String>,
    record_last_processed: bool,
) -> bool {
    state.files_inspected.fetch_add(1, Ordering::Relaxed);

    let meta = match known_meta {
        Some(m) => m,
        None => match fs::metadata(&file_path) {
            Ok(m) => m,
            Err(e) => {
                state.errors.fetch_add(1, Ordering::Relaxed);
                state.push_error_log(format!("✗ Failed to inspect {name_str}: {e}"));
                return true;
            }
        },
    };

    let src_size = meta.len();
    let modified = match meta.modified() {
        Ok(m) => m,
        Err(e) => {
            state.errors.fetch_add(1, Ordering::Relaxed);
            state.push_error_log(format!("✗ Failed to inspect {name_str}: {e}"));
            return true;
        }
    };

    if config.enable_age_filter || config.enable_date_range {
        let modified_ms = system_time_to_epoch_ms(modified);
        if config.enable_age_filter && modified_ms > config.age_threshold_epoch_ms {
            state.files_skipped.fetch_add(1, Ordering::Relaxed);
            return true;
        }
        if config.enable_date_range
            && (modified_ms < config.from_inclusive_epoch_ms
                || modified_ms >= config.to_exclusive_epoch_ms)
        {
            state.files_skipped.fetch_add(1, Ordering::Relaxed);
            return true;
        }
    }

    let sizes_map = dest_sizes.get_or_insert_with(|| read_dest_sizes(dest_dir));
    if sizes_map.get(&filename_key(&name_os)) == Some(&src_size) {
        let already = state.files_already_exist.fetch_add(1, Ordering::Relaxed) + 1;
        if config.log_interval > 0 && already % config.log_interval == 0 {
            state.set_phase(PHASE_CHECKING, Some(dir_name), None);
            state.push_log(format!(
                "⏭ {already} files already exist at destination (skipping)"
            ));
        }
        return true;
    }

    if !*dest_dir_created {
        if !created_dirs.contains(dest_dir) {
            match fs::create_dir(dest_dir) {
                Ok(()) => {
                    created_dirs.insert(dest_dir.to_path_buf());
                    *dest_sizes = Some(HashMap::new());
                }
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                    created_dirs.insert(dest_dir.to_path_buf());
                }
                Err(_) => {
                    if let Err(e) = fs::create_dir_all(dest_dir) {
                        state.errors.fetch_add(1, Ordering::Relaxed);
                        state.push_error_log(format!("✗ Failed to copy {name_str}: {e}"));
                        return true;
                    }
                    created_dirs.insert(dest_dir.to_path_buf());
                }
            }
        }
        *dest_dir_created = true;
    }

    if let Some(ref cnt) = dir_pending {
        cnt.fetch_add(1, Ordering::AcqRel);
    }

    let ok = queue.push(
        CopyTask {
            src: file_path,
            dest: dest_dir.join(&name_os),
            modified: Some(modified),
            dir_pending: dir_pending.clone(),
        },
        state,
    );
    if !ok {
        if let Some(ref cnt) = dir_pending {
            cnt.fetch_sub(1, Ordering::AcqRel);
        }
        return false;
    }

    if record_last_processed && config.progress_file_path.is_some() {
        last_processed_files.insert(rel_path.to_string(), name_str.to_string());
    }
    true
}

struct ResumeFileCandidate {
    path: PathBuf,
    name_os: OsString,
    name: String,
    known_meta: Option<Metadata>,
}

fn run_copy_coordinator(
    config: CopyConfig,
    state: Arc<CopySharedState>,
    queue: Arc<CopyQueue>,
) {
    let is_resuming =
        !config.completed_dirs.is_empty() || !config.last_processed_files.is_empty();

    let canonical_root = match fs::canonicalize(&config.source_path) {
        Ok(p) => p,
        Err(e) => {
            state.set_critical_error(format!(
                "Failed to access source directory {}: {e}",
                config.source_path.display()
            ));
            queue.close(true);
            state.set_phase(PHASE_DONE, None, None);
            state.done.store(true, Ordering::Release);
            return;
        }
    };

    let norm_dest = normalize_lexical(&config.dest_path);
    let canon_dest = fs::canonicalize(&config.dest_path).ok();

    let worker_count = io_worker_count();
    let mut workers = Vec::with_capacity(worker_count);
    for _ in 0..worker_count {
        if let Some(h) = spawn_copy_worker(
            Arc::clone(&queue),
            Arc::clone(&state),
            config.log_interval,
        ) {
            workers.push(h);
        }
    }

    if workers.is_empty() {
        state.set_critical_error("Failed to spawn copy worker threads".to_string());
        queue.close(true);
        state.set_phase(PHASE_DONE, None, None);
        state.done.store(true, Ordering::Release);
        return;
    }

    let mut visited_symlinks: HashSet<PathBuf> = HashSet::new();
    let mut created_dirs: HashSet<PathBuf> = HashSet::new();
    let mut completed_dirs = config.completed_dirs.clone();
    let mut last_processed_files = config.last_processed_files.clone();
    let mut pending_trackers: Vec<(String, Arc<AtomicUsize>)> = Vec::new();
    let mut last_save = Instant::now();

    let mut dirs_stack: Vec<PathBuf> = Vec::new();
    dirs_stack.push(config.source_path.clone());

    while let Some(dir) = dirs_stack.pop() {
        if state.is_stopped() || !state.wait_if_paused() {
            break;
        }

        let dir_name = path_basename(&dir);
        if lexical_equal_or_within(&norm_dest, &dir) {
            state.push_log(format!("ℹ Skipping destination folder: {dir_name}"));
            continue;
        }

        let rel_path = relative_dir_string(&dir, &config.source_path);
        if completed_dirs.contains(&rel_path) {
            state.dirs_skipped.fetch_add(1, Ordering::Relaxed);
            continue;
        }

        state.set_phase(PHASE_SCANNING, Some(&dir_name), None);

        let entries = match fs::read_dir(&dir) {
            Ok(iter) => iter,
            Err(e) => {
                state.errors.fetch_add(1, Ordering::Relaxed);
                state.push_error_log(format!("✗ Cannot access: {} ({e})", dir.display()));
                continue;
            }
        };

        let dest_dir = if rel_path == "." {
            config.dest_path.clone()
        } else {
            config.dest_path.join(&rel_path)
        };
        let mut dest_dir_created = created_dirs.contains(&dest_dir);
        let mut dest_sizes: Option<HashMap<FilenameKey, u64>> = None;
        let dir_pending = config
            .progress_file_path
            .as_ref()
            .map(|_| Arc::new(AtomicUsize::new(0)));

        let mut subdirs: Vec<PathBuf> = Vec::new();
        let mut dir_completed_scan = true;
        let resume_last_name = last_processed_files.get(&rel_path).cloned();

        if let Some(ref last_name) = resume_last_name {
            // Resuming a legacy directory checkpoint requires deterministic filename sorting.
            let mut files: Vec<ResumeFileCandidate> = Vec::new();
            for entry_res in entries {
                if state.is_stopped() {
                    dir_completed_scan = false;
                    break;
                }
                let entry = match entry_res {
                    Ok(e) => e,
                    Err(_) => continue,
                };
                let entry_path = entry.path();
                let ft = match entry.file_type() {
                    Ok(t) => t,
                    Err(_) => continue,
                };
                if ft.is_file() {
                    let name_os = entry.file_name();
                    let name = name_os.to_string_lossy().into_owned();
                    files.push(ResumeFileCandidate {
                        path: entry_path,
                        name_os,
                        name,
                        known_meta: entry.metadata().ok(),
                    });
                } else if ft.is_dir() {
                    subdirs.push(entry_path);
                } else if ft.is_symlink() {
                    if let Some(canon_target) =
                        resolve_canonical_within_root(&canonical_root, &entry_path)
                    {
                        if let Some(ref cd) = canon_dest {
                            if canon_target == *cd || canon_target.starts_with(cd) {
                                continue;
                            }
                        }
                        if let Ok(meta) = fs::metadata(&entry_path) {
                            if meta.is_dir() {
                                if visited_symlinks.insert(canon_target) {
                                    subdirs.push(entry_path);
                                }
                            } else if meta.is_file() {
                                let name_os = entry.file_name();
                                let name = name_os.to_string_lossy().into_owned();
                                files.push(ResumeFileCandidate {
                                    path: entry_path,
                                    name_os,
                                    name,
                                    known_meta: Some(meta),
                                });
                            }
                        }
                    }
                }
            }

            if dir_completed_scan {
                files.sort_unstable_by(|a, b| a.name.cmp(&b.name));
                let start_idx = files
                    .iter()
                    .position(|f| &f.name == last_name)
                    .map(|i| i + 1)
                    .unwrap_or(0);

                for candidate in files.into_iter().skip(start_idx) {
                    if state.is_stopped() || !state.wait_if_paused() {
                        dir_completed_scan = false;
                        break;
                    }
                    if !inspect_and_enqueue_copy_file(
                        candidate.path,
                        candidate.name_os,
                        &candidate.name,
                        candidate.known_meta,
                        &dir_name,
                        &rel_path,
                        &dest_dir,
                        &mut dest_dir_created,
                        &mut dest_sizes,
                        &mut created_dirs,
                        &dir_pending,
                        &config,
                        &state,
                        &queue,
                        &mut last_processed_files,
                        false,
                    ) {
                        dir_completed_scan = false;
                        break;
                    }
                }
            }
        } else {
            // Streaming fast-path: process read_dir entries directly with zero sorting overhead.
            for entry_res in entries {
                if state.is_stopped() || !state.wait_if_paused() {
                    dir_completed_scan = false;
                    break;
                }
                let entry = match entry_res {
                    Ok(e) => e,
                    Err(_) => continue,
                };
                let entry_path = entry.path();
                let ft = match entry.file_type() {
                    Ok(t) => t,
                    Err(_) => continue,
                };

                if ft.is_file() {
                    let name_os = entry.file_name();
                    let name_str = name_os.to_string_lossy().into_owned();
                    if !inspect_and_enqueue_copy_file(
                        entry_path,
                        name_os,
                        &name_str,
                        entry.metadata().ok(),
                        &dir_name,
                        &rel_path,
                        &dest_dir,
                        &mut dest_dir_created,
                        &mut dest_sizes,
                        &mut created_dirs,
                        &dir_pending,
                        &config,
                        &state,
                        &queue,
                        &mut last_processed_files,
                        false,
                    ) {
                        dir_completed_scan = false;
                        break;
                    }
                } else if ft.is_dir() {
                    subdirs.push(entry_path);
                } else if ft.is_symlink() {
                    if let Some(canon_target) =
                        resolve_canonical_within_root(&canonical_root, &entry_path)
                    {
                        if let Some(ref cd) = canon_dest {
                            if canon_target == *cd || canon_target.starts_with(cd) {
                                continue;
                            }
                        }
                        if let Ok(meta) = fs::metadata(&entry_path) {
                            if meta.is_dir() {
                                if visited_symlinks.insert(canon_target) {
                                    subdirs.push(entry_path);
                                }
                            } else if meta.is_file() {
                                let name_os = entry.file_name();
                                let name_str = name_os.to_string_lossy().into_owned();
                                if !inspect_and_enqueue_copy_file(
                                    entry_path,
                                    name_os,
                                    &name_str,
                                    Some(meta),
                                    &dir_name,
                                    &rel_path,
                                    &dest_dir,
                                    &mut dest_dir_created,
                                    &mut dest_sizes,
                                    &mut created_dirs,
                                    &dir_pending,
                                    &config,
                                    &state,
                                    &queue,
                                    &mut last_processed_files,
                                    false,
                                ) {
                                    dir_completed_scan = false;
                                    break;
                                }
                            }
                        }
                    }
                }

                if let Some(ref progress_path) = config.progress_file_path {
                    if last_save.elapsed() >= Duration::from_secs(2) {
                        drain_completed_trackers(
                            &mut pending_trackers,
                            &mut completed_dirs,
                            &mut last_processed_files,
                        );
                        save_progress_file(
                            progress_path,
                            &config,
                            &completed_dirs,
                            &last_processed_files,
                            &state,
                        );
                        last_save = Instant::now();
                    }
                }
            }
        }

        if dir_completed_scan && !state.is_stopped() {
            if let Some(cnt) = dir_pending {
                pending_trackers.push((rel_path.clone(), cnt));
            }
        }

        subdirs.sort_unstable_by(|a, b| path_basename(a).cmp(&path_basename(b)));
        for sub in subdirs.into_iter().rev() {
            dirs_stack.push(sub);
        }

        if let Some(ref progress_path) = config.progress_file_path {
            drain_completed_trackers(
                &mut pending_trackers,
                &mut completed_dirs,
                &mut last_processed_files,
            );
            if last_save.elapsed() >= Duration::from_secs(2) {
                save_progress_file(
                    progress_path,
                    &config,
                    &completed_dirs,
                    &last_processed_files,
                    &state,
                );
                last_save = Instant::now();
            }
        }
    }

    queue.close(state.is_stopped());
    for w in workers {
        let _ = w.join();
    }

    if state.is_stopped() {
        drain_completed_trackers(
            &mut pending_trackers,
            &mut completed_dirs,
            &mut last_processed_files,
        );
        if let Some(ref progress_path) = config.progress_file_path {
            save_progress_file(
                progress_path,
                &config,
                &completed_dirs,
                &last_processed_files,
                &state,
            );
        }
    } else {
        let dirs_skipped = state.dirs_skipped.load(Ordering::Relaxed);
        let resume_note = if is_resuming {
            format!(" ({dirs_skipped} dirs skipped via resume)")
        } else {
            String::new()
        };
        state.push_log(format!("🏁 Copy completed successfully.{resume_note}"));
        if let Some(ref progress_path) = config.progress_file_path {
            let _ = fs::remove_file(progress_path);
        }
    }

    state.set_phase(PHASE_DONE, None, None);
    state.done.store(true, Ordering::Release);
}

fn build_copy_poll_json(state: &CopySharedState) -> String {
    let files_copied = state.files_copied.load(Ordering::Relaxed);
    let files_skipped = state.files_skipped.load(Ordering::Relaxed);
    let files_already_exist = state.files_already_exist.load(Ordering::Relaxed);
    let errors = state.errors.load(Ordering::Relaxed);
    let files_inspected = state.files_inspected.load(Ordering::Relaxed);
    let dirs_skipped = state.dirs_skipped.load(Ordering::Relaxed);
    let is_done = state.done.load(Ordering::Acquire);

    let (phase, current_dir_name, latest_copied_name, critical_error, logs, error_logs) =
        match state.ui.lock() {
            Ok(mut ui) => (
                ui.phase,
                ui.current_dir_name.clone(),
                ui.latest_copied_name.clone(),
                ui.critical_error.take(),
                ui.logs.drain(..).collect::<Vec<_>>(),
                ui.error_logs.drain(..).collect::<Vec<_>>(),
            ),
            Err(_) => (
                PHASE_DONE,
                String::new(),
                String::new(),
                None,
                Vec::new(),
                Vec::new(),
            ),
        };

    let mut json = String::with_capacity(384 + logs.len() * 64 + error_logs.len() * 64);
    let _ = write!(
        json,
        "{{\"filesCopied\":{files_copied},\"filesSkipped\":{files_skipped},\"filesAlreadyExist\":{files_already_exist},\"errors\":{errors},\"filesInspected\":{files_inspected},\"dirsSkipped\":{dirs_skipped},\"phase\":{phase},\"currentDirName\":"
    );
    push_json_escaped(&mut json, &current_dir_name);
    json.push_str(",\"latestCopiedName\":");
    push_json_escaped(&mut json, &latest_copied_name);
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
pub unsafe extern "C" fn copy_engine_start(cfg: *const CopyConfigC) -> *mut CopyJob {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if cfg.is_null() {
            return std::ptr::null_mut();
        }
        let raw = &*cfg;
        let source_path = match c_str_to_string(raw.source_path) {
            Some(s) if !s.is_empty() => PathBuf::from(s),
            _ => return std::ptr::null_mut(),
        };
        let dest_path = match c_str_to_string(raw.dest_path) {
            Some(s) if !s.is_empty() => PathBuf::from(s),
            _ => return std::ptr::null_mut(),
        };
        let progress_file_path = c_str_to_string(raw.progress_file_path)
            .filter(|s| !s.is_empty())
            .map(PathBuf::from);

        let mut completed_dirs = HashSet::new();
        if let Some(s) = c_str_to_string(raw.completed_dirs_serialized) {
            for line in s.lines() {
                if !line.is_empty() {
                    completed_dirs.insert(line.to_string());
                }
            }
        }

        let mut last_processed_files = HashMap::new();
        if let Some(s) = c_str_to_string(raw.last_processed_serialized) {
            for line in s.lines() {
                if let Some((dir, file)) = line.split_once('\t') {
                    if !dir.is_empty() && !file.is_empty() {
                        last_processed_files.insert(dir.to_string(), file.to_string());
                    }
                }
            }
        }

        let config = CopyConfig {
            source_path,
            dest_path,
            progress_file_path,
            completed_dirs,
            last_processed_files,
            enable_age_filter: raw.enable_age_filter != 0,
            age_threshold_epoch_ms: raw.age_threshold_epoch_ms,
            enable_date_range: raw.enable_date_range != 0,
            from_inclusive_epoch_ms: raw.from_inclusive_epoch_ms,
            to_exclusive_epoch_ms: raw.to_exclusive_epoch_ms,
            initial_copied: raw.initial_copied,
            initial_skipped: raw.initial_skipped,
            initial_already_exist: raw.initial_already_exist,
            initial_errors: raw.initial_errors,
            initial_inspected: raw.initial_inspected,
            log_interval: if raw.log_interval == 0 {
                100
            } else {
                raw.log_interval
            },
        };

        let state = Arc::new(CopySharedState::new(&config));
        let queue = Arc::new(CopyQueue::new());
        let worker_state = Arc::clone(&state);
        let worker_queue = Arc::clone(&queue);

        let handle = thread::Builder::new()
            .name("copy_engine_coordinator".to_string())
            .spawn(move || {
                let state_for_panic = Arc::clone(&worker_state);
                let queue_for_panic = Arc::clone(&worker_queue);
                let run_res = catch_unwind(AssertUnwindSafe(|| {
                    run_copy_coordinator(config, worker_state, worker_queue);
                }));
                if let Err(panic_info) = run_res {
                    let msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
                        (*s).to_string()
                    } else if let Some(s) = panic_info.downcast_ref::<String>() {
                        s.clone()
                    } else {
                        "Unknown copy coordinator panic".to_string()
                    };
                    queue_for_panic.close(true);
                    state_for_panic.set_critical_error(msg);
                    state_for_panic.set_phase(PHASE_DONE, None, None);
                    state_for_panic.done.store(true, Ordering::Release);
                }
            })
            .ok();

        match handle {
            Some(h) => Box::into_raw(Box::new(CopyJob {
                state,
                queue,
                handle: Some(h),
            })),
            None => std::ptr::null_mut(),
        }
    }));

    res.unwrap_or(std::ptr::null_mut())
}

// Gene - Nov, 26, 2026: Use poison-safe mutex recovery across copy_engine pause/resume/stop/destroy.
// #[no_mangle]
// pub unsafe extern "C" fn copy_engine_pause(job: *mut CopyJob) {
//     let _ = catch_unwind(AssertUnwindSafe(|| {
//         if job.is_null() {
//             return;
//         }
//         let job_ref = &*job;
//         if let Ok(mut paused) = job_ref.state.pause_lock.lock() {
//             *paused = true;
//         }
//     }));
// }
//
// #[no_mangle]
// pub unsafe extern "C" fn copy_engine_resume(job: *mut CopyJob) {
//     let _ = catch_unwind(AssertUnwindSafe(|| {
//         if job.is_null() {
//             return;
//         }
//         let job_ref = &*job;
//         if let Ok(mut paused) = job_ref.state.pause_lock.lock() {
//             *paused = false;
//         }
//         job_ref.state.pause_cvar.notify_all();
//     }));
// }
//
// #[no_mangle]
// pub unsafe extern "C" fn copy_engine_stop(job: *mut CopyJob) {
//     let _ = catch_unwind(AssertUnwindSafe(|| {
//         if job.is_null() {
//             return;
//         }
//         let job_ref = &*job;
//         job_ref.state.cancel_flag.store(1, Ordering::Release);
//         job_ref.state.stop_requested.store(true, Ordering::Release);
//         if let Ok(mut paused) = job_ref.state.pause_lock.lock() {
//             *paused = false;
//         }
//         job_ref.state.pause_cvar.notify_all();
//         job_ref.queue.close(true);
//     }));
// }
//
// #[no_mangle]
// pub unsafe extern "C" fn copy_engine_poll(job: *mut CopyJob) -> *mut c_char {
//     let res = catch_unwind(AssertUnwindSafe(|| {
//         if job.is_null() {
//             return std::ptr::null_mut();
//         }
//         let job_ref = &*job;
//         let json = build_copy_poll_json(&job_ref.state);
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
// pub unsafe extern "C" fn copy_engine_destroy(job: *mut CopyJob) {
//     let _ = catch_unwind(AssertUnwindSafe(|| {
//         if job.is_null() {
//             return;
//         }
//         let mut boxed = Box::from_raw(job);
//         boxed.state.cancel_flag.store(1, Ordering::Release);
//         boxed.state.stop_requested.store(true, Ordering::Release);
//         if let Ok(mut paused) = boxed.state.pause_lock.lock() {
//             *paused = false;
//         }
//         boxed.state.pause_cvar.notify_all();
//         boxed.queue.close(true);
//         if let Some(handle) = boxed.handle.take() {
//             let _ = handle.join();
//         }
//     }));
// }
#[no_mangle]
pub unsafe extern "C" fn copy_engine_pause(job: *mut CopyJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let job_ref = &*job;
        let mut paused = job_ref
            .state
            .pause_lock
            .lock()
            .unwrap_or_else(|p| p.into_inner());
        *paused = true;
    }));
}

#[no_mangle]
pub unsafe extern "C" fn copy_engine_resume(job: *mut CopyJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let job_ref = &*job;
        {
            let mut paused = job_ref
                .state
                .pause_lock
                .lock()
                .unwrap_or_else(|p| p.into_inner());
            *paused = false;
        }
        job_ref.state.pause_cvar.notify_all();
    }));
}

#[no_mangle]
pub unsafe extern "C" fn copy_engine_stop(job: *mut CopyJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let job_ref = &*job;
        job_ref.state.cancel_flag.store(1, Ordering::Release);
        job_ref.state.stop_requested.store(true, Ordering::Release);
        {
            let mut paused = job_ref
                .state
                .pause_lock
                .lock()
                .unwrap_or_else(|p| p.into_inner());
            *paused = false;
        }
        job_ref.state.pause_cvar.notify_all();
        job_ref.queue.close(true);
    }));
}

#[no_mangle]
pub unsafe extern "C" fn copy_engine_poll(job: *mut CopyJob) -> *mut c_char {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return std::ptr::null_mut();
        }
        let job_ref = &*job;
        let json = build_copy_poll_json(&job_ref.state);
        match CString::new(json) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => std::ptr::null_mut(),
        }
    }));

    res.unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn copy_engine_destroy(job: *mut CopyJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let mut boxed = Box::from_raw(job);
        boxed.state.cancel_flag.store(1, Ordering::Release);
        boxed.state.stop_requested.store(true, Ordering::Release);
        {
            let mut paused = boxed
                .state
                .pause_lock
                .lock()
                .unwrap_or_else(|p| p.into_inner());
            *paused = false;
        }
        boxed.state.pause_cvar.notify_all();
        boxed.queue.close(true);
        if let Some(handle) = boxed.handle.take() {
            let _ = handle.join();
        }
    }));
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use std::time::UNIX_EPOCH;

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
    fn copies_matching_skips_filtered_and_skips_same_size_existing() {
        let root = make_temp_dir("rust_copy_basic");
        let src = root.join("source");
        let sub = src.join("sub");
        let dst = root.join("dest");
        fs::create_dir_all(&sub).unwrap();
        fs::create_dir_all(dst.join("sub")).unwrap();

        let match_f = File::create(sub.join("match.txt")).unwrap();
        let exist_f = File::create(sub.join("exist.txt")).unwrap();
        let old_f = File::create(sub.join("old.txt")).unwrap();
        drop(match_f);
        drop(exist_f);
        drop(old_f);

        fs::write(sub.join("match.txt"), b"HELLO").unwrap();
        fs::write(sub.join("exist.txt"), b"SAME").unwrap();
        fs::write(dst.join("sub").join("exist.txt"), b"SAME").unwrap();
        fs::write(sub.join("old.txt"), b"OLD").unwrap();

        let t_in = UNIX_EPOCH + Duration::from_secs(1_700_500_000);
        let t_old = UNIX_EPOCH + Duration::from_secs(1_600_000_000);
        File::options()
            .write(true)
            .open(sub.join("match.txt"))
            .unwrap()
            .set_modified(t_in)
            .unwrap();
        File::options()
            .write(true)
            .open(sub.join("exist.txt"))
            .unwrap()
            .set_modified(t_in)
            .unwrap();
        File::options()
            .write(true)
            .open(sub.join("old.txt"))
            .unwrap()
            .set_modified(t_old)
            .unwrap();

        let cfg = CopyConfig {
            source_path: src.clone(),
            dest_path: dst.clone(),
            progress_file_path: None,
            completed_dirs: HashSet::new(),
            last_processed_files: HashMap::new(),
            enable_age_filter: false,
            age_threshold_epoch_ms: 0,
            enable_date_range: true,
            from_inclusive_epoch_ms: 1_700_400_000_000,
            to_exclusive_epoch_ms: 1_700_600_000_000,
            initial_copied: 0,
            initial_skipped: 0,
            initial_already_exist: 0,
            initial_errors: 0,
            initial_inspected: 0,
            log_interval: 1,
        };
        let state = Arc::new(CopySharedState::new(&cfg));
        let queue = Arc::new(CopyQueue::new());
        run_copy_coordinator(cfg, Arc::clone(&state), queue);

        assert_eq!(state.files_inspected.load(Ordering::Relaxed), 3);
        assert_eq!(state.files_copied.load(Ordering::Relaxed), 1);
        assert_eq!(state.files_already_exist.load(Ordering::Relaxed), 1);
        assert_eq!(state.files_skipped.load(Ordering::Relaxed), 1);
        assert_eq!(fs::read(dst.join("sub").join("match.txt")).unwrap(), b"HELLO");
        assert!(!dst.join("sub").join("old.txt").exists());

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn parallel_copies_100_files_across_nested_folders() {
        let root = make_temp_dir("rust_copy_parallel_100");
        let src = root.join("source");
        let dst = root.join("dest");
        fs::create_dir_all(&dst).unwrap();
        for d in 0..5 {
            let sub = src.join(format!("dir_{d}"));
            fs::create_dir_all(&sub).unwrap();
            for f in 0..20 {
                fs::write(sub.join(format!("f_{f}.bin")), b"PAYLOAD").unwrap();
            }
        }

        let cfg = CopyConfig {
            source_path: src.clone(),
            dest_path: dst.clone(),
            progress_file_path: None,
            completed_dirs: HashSet::new(),
            last_processed_files: HashMap::new(),
            enable_age_filter: false,
            age_threshold_epoch_ms: 0,
            enable_date_range: false,
            from_inclusive_epoch_ms: 0,
            to_exclusive_epoch_ms: 0,
            initial_copied: 0,
            initial_skipped: 0,
            initial_already_exist: 0,
            initial_errors: 0,
            initial_inspected: 0,
            log_interval: 25,
        };
        let state = Arc::new(CopySharedState::new(&cfg));
        let queue = Arc::new(CopyQueue::new());
        run_copy_coordinator(cfg, Arc::clone(&state), queue);

        assert_eq!(state.files_inspected.load(Ordering::Relaxed), 100);
        assert_eq!(state.files_copied.load(Ordering::Relaxed), 100);
        assert_eq!(state.errors.load(Ordering::Relaxed), 0);
        assert!(dst.join("dir_4").join("f_19.bin").exists());

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn resume_skips_completed_dirs_and_prior_files() {
        let root = make_temp_dir("rust_copy_resume");
        let src = root.join("source");
        let done_dir = src.join("done_dir");
        let dst = root.join("dest");
        fs::create_dir_all(&done_dir).unwrap();
        fs::create_dir_all(&dst).unwrap();

        fs::write(done_dir.join("skip_dir_file.txt"), b"1").unwrap();
        fs::write(src.join("a.txt"), b"A").unwrap();
        fs::write(src.join("b.txt"), b"B").unwrap();

        let mut completed_dirs = HashSet::new();
        completed_dirs.insert("done_dir".to_string());
        let mut last_processed_files = HashMap::new();
        last_processed_files.insert(".".to_string(), "a.txt".to_string());

        let cfg = CopyConfig {
            source_path: src.clone(),
            dest_path: dst.clone(),
            progress_file_path: None,
            completed_dirs,
            last_processed_files,
            enable_age_filter: false,
            age_threshold_epoch_ms: 0,
            enable_date_range: false,
            from_inclusive_epoch_ms: 0,
            to_exclusive_epoch_ms: 0,
            initial_copied: 5,
            initial_skipped: 0,
            initial_already_exist: 0,
            initial_errors: 0,
            initial_inspected: 5,
            log_interval: 100,
        };
        let state = Arc::new(CopySharedState::new(&cfg));
        let queue = Arc::new(CopyQueue::new());
        run_copy_coordinator(cfg, Arc::clone(&state), queue);

        assert!(!dst.join("a.txt").exists());
        assert!(dst.join("b.txt").exists());
        assert!(!dst.join("done_dir").exists());
        assert_eq!(state.dirs_skipped.load(Ordering::Relaxed), 1);
        assert_eq!(state.files_copied.load(Ordering::Relaxed), 6);

        let _ = fs::remove_dir_all(&root);
    }

    // Gene - Nov, 26, 2026: Added regression tests for dest-inside-source skipping, read-only mtime preservation, and atomic progress writes.
    #[test]
    fn skips_destination_nested_inside_source() {
        let root = make_temp_dir("rust_copy_nested_dest");
        let src = root.join("source");
        let dst = src.join("backup_dest");
        fs::create_dir_all(&dst).unwrap();
        fs::write(src.join("a.txt"), b"ALPHA").unwrap();

        let cfg = CopyConfig {
            source_path: src.clone(),
            dest_path: dst.clone(),
            progress_file_path: None,
            completed_dirs: HashSet::new(),
            last_processed_files: HashMap::new(),
            enable_age_filter: false,
            age_threshold_epoch_ms: 0,
            enable_date_range: false,
            from_inclusive_epoch_ms: 0,
            to_exclusive_epoch_ms: 0,
            initial_copied: 0,
            initial_skipped: 0,
            initial_already_exist: 0,
            initial_errors: 0,
            initial_inspected: 0,
            log_interval: 100,
        };
        let state = Arc::new(CopySharedState::new(&cfg));
        let queue = Arc::new(CopyQueue::new());
        run_copy_coordinator(cfg, Arc::clone(&state), queue);

        assert_eq!(fs::read(dst.join("a.txt")).unwrap(), b"ALPHA");
        assert!(!dst.join("backup_dest").exists());
        assert_eq!(state.files_copied.load(Ordering::Relaxed), 1);
        assert_eq!(state.errors.load(Ordering::Relaxed), 0);

        let _ = fs::remove_dir_all(&root);
    }

    #[cfg(unix)]
    #[test]
    fn preserves_modified_timestamp_for_readonly_file() {
        let root = make_temp_dir("rust_copy_readonly_mtime");
        let src = root.join("source");
        let dst = root.join("dest");
        fs::create_dir_all(&src).unwrap();
        fs::create_dir_all(&dst).unwrap();

        let src_file = src.join("readonly.txt");
        fs::write(&src_file, b"READONLY").unwrap();
        let target_time = UNIX_EPOCH + Duration::from_secs(1_650_000_000);
        File::options()
            .write(true)
            .open(&src_file)
            .unwrap()
            .set_modified(target_time)
            .unwrap();
        let mut perms = fs::metadata(&src_file).unwrap().permissions();
        perms.set_readonly(true);
        fs::set_permissions(&src_file, perms).unwrap();

        let cfg = CopyConfig {
            source_path: src.clone(),
            dest_path: dst.clone(),
            progress_file_path: None,
            completed_dirs: HashSet::new(),
            last_processed_files: HashMap::new(),
            enable_age_filter: false,
            age_threshold_epoch_ms: 0,
            enable_date_range: false,
            from_inclusive_epoch_ms: 0,
            to_exclusive_epoch_ms: 0,
            initial_copied: 0,
            initial_skipped: 0,
            initial_already_exist: 0,
            initial_errors: 0,
            initial_inspected: 0,
            log_interval: 100,
        };
        let state = Arc::new(CopySharedState::new(&cfg));
        let queue = Arc::new(CopyQueue::new());
        run_copy_coordinator(cfg, Arc::clone(&state), queue);

        assert_eq!(state.files_copied.load(Ordering::Relaxed), 1);
        let dst_mtime = fs::metadata(dst.join("readonly.txt"))
            .unwrap()
            .modified()
            .unwrap();
        let diff = dst_mtime
            .duration_since(target_time)
            .or_else(|_| target_time.duration_since(dst_mtime))
            .unwrap();
        assert!(diff <= Duration::from_secs(1));

        // Restore write permission so remove_dir_all succeeds cleanly.
        let mut reset_perms = fs::metadata(&src_file).unwrap().permissions();
        reset_perms.set_readonly(false);
        let _ = fs::set_permissions(&src_file, reset_perms);
        let dst_file = dst.join("readonly.txt");
        if let Ok(m) = fs::metadata(&dst_file) {
            let mut dp = m.permissions();
            dp.set_readonly(false);
            let _ = fs::set_permissions(&dst_file, dp);
        }
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn interrupted_directory_is_not_marked_completed_and_progress_is_valid_json() {
        let root = make_temp_dir("rust_copy_progress_atomic");
        let src = root.join("source");
        let dst = root.join("dest");
        let progress_path = root.join("progress.json");
        fs::create_dir_all(&src).unwrap();
        fs::create_dir_all(&dst).unwrap();

        let cfg = CopyConfig {
            source_path: src.clone(),
            dest_path: dst.clone(),
            progress_file_path: Some(progress_path.clone()),
            completed_dirs: HashSet::new(),
            last_processed_files: HashMap::new(),
            enable_age_filter: false,
            age_threshold_epoch_ms: 0,
            enable_date_range: false,
            from_inclusive_epoch_ms: 0,
            to_exclusive_epoch_ms: 0,
            initial_copied: 2,
            initial_skipped: 1,
            initial_already_exist: 0,
            initial_errors: 0,
            initial_inspected: 3,
            log_interval: 100,
        };
        let state = Arc::new(CopySharedState::new(&cfg));
        let mut completed = HashSet::new();
        completed.insert("done_sub".to_string());
        let last_proc = HashMap::new();

        save_progress_file(&progress_path, &cfg, &completed, &last_proc, &state);
        let saved = fs::read_to_string(&progress_path).unwrap();
        assert!(saved.contains("\"completedDirs\":[\"done_sub\"]"));
        assert!(saved.contains("\"filesCopied\":2"));
        assert!(!root.join("progress.json.tmp").exists());

        let _ = fs::remove_dir_all(&root);
    }
}
