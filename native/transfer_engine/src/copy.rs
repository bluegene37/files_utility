// Gene - Nov, 25, 2026: Native Rust parallel copy engine with bounded 4-worker pool,
// 512 KiB reusable buffers, destination pre-listing, resume checkpoints, and symlink safety.

use std::collections::{HashMap, HashSet, VecDeque};
use std::ffi::{CString, OsString};
use std::fmt::Write as _;
use std::fs::{self, Metadata};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant, SystemTime};

use crate::common::{
    c_str_to_string, normalize_lexical, path_basename, push_json_escaped, relative_dir_string,
    resolve_within_root, streaming_copy_to_part_and_swap, system_time_to_epoch_ms,
    COPY_BUFFER_BYTES, MAX_QUEUED_LOGS,
};

const NUM_COPY_WORKERS: usize = 4;
const BATCH_FLUSH_THRESHOLD: usize = 32;

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
    modified: SystemTime,
}

struct QueueInner {
    tasks: VecDeque<CopyTask>,
    in_flight: usize,
    closed: bool,
}

struct CopyQueue {
    inner: Mutex<QueueInner>,
    work_cv: Condvar,
    idle_cv: Condvar,
}

impl CopyQueue {
    fn new() -> Self {
        Self {
            inner: Mutex::new(QueueInner {
                tasks: VecDeque::new(),
                in_flight: 0,
                closed: false,
            }),
            work_cv: Condvar::new(),
            idle_cv: Condvar::new(),
        }
    }

    fn push(&self, task: CopyTask) {
        if let Ok(mut guard) = self.inner.lock() {
            guard.tasks.push_back(task);
            self.work_cv.notify_one();
        }
    }

    fn wait_idle(&self, stop_requested: &AtomicBool) {
        let mut guard = match self.inner.lock() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        while (!guard.tasks.is_empty() || guard.in_flight > 0)
            && !stop_requested.load(Ordering::Acquire)
        {
            guard = match self.idle_cv.wait(guard) {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
        }
    }

    fn close_and_clear(&self) {
        if let Ok(mut guard) = self.inner.lock() {
            guard.tasks.clear();
            guard.closed = true;
            self.work_cv.notify_all();
            self.idle_cv.notify_all();
        }
    }

    fn close(&self) {
        if let Ok(mut guard) = self.inner.lock() {
            guard.closed = true;
            self.work_cv.notify_all();
            self.idle_cv.notify_all();
        }
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

    fn set_phase(&self, phase: u8, dir_name: Option<&str>, copied_name: Option<&str>) {
        if let Ok(mut ui) = self.ui.lock() {
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

    let _ = fs::write(path, json);
}

fn spawn_copy_worker(
    queue: Arc<CopyQueue>,
    state: Arc<CopySharedState>,
    log_interval: u64,
) -> Option<JoinHandle<()>> {
    thread::Builder::new()
        .name("copy_engine_worker".to_string())
        .spawn(move || {
            let mut copy_buf = vec![0u8; COPY_BUFFER_BYTES];
            loop {
                let task = {
                    let mut guard = match queue.inner.lock() {
                        Ok(g) => g,
                        Err(p) => p.into_inner(),
                    };
                    while guard.tasks.is_empty() && !guard.closed && !state.is_stopped() {
                        guard = match queue.work_cv.wait(guard) {
                            Ok(g) => g,
                            Err(p) => p.into_inner(),
                        };
                    }
                    if state.is_stopped() || (guard.closed && guard.tasks.is_empty()) {
                        break;
                    }
                    let popped = guard.tasks.pop_front();
                    if popped.is_some() {
                        guard.in_flight += 1;
                    }
                    popped
                };

                let Some(task) = task else {
                    continue;
                };

                if state.wait_if_paused() {
                    let file_name = path_basename(&task.src);
                    match streaming_copy_to_part_and_swap(
                        &task.src,
                        &task.dest,
                        task.modified,
                        &mut copy_buf,
                        &state.stop_requested,
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
                        Err(err) if err == "__STOPPED__" => {}
                        Err(err) => {
                            state.errors.fetch_add(1, Ordering::Relaxed);
                            state.push_error_log(format!(
                                "✗ Failed to copy {file_name}: {err}"
                            ));
                        }
                    }
                }

                if let Ok(mut guard) = queue.inner.lock() {
                    guard.in_flight = guard.in_flight.saturating_sub(1);
                    if guard.tasks.is_empty() && guard.in_flight == 0 {
                        queue.idle_cv.notify_all();
                    }
                }
            }
        })
        .ok()
}

struct FileCandidate {
    path: PathBuf,
    name_os: OsString,
    name: String,
    known_meta: Option<Metadata>,
}

fn read_dest_sizes(dest_dir: &Path) -> HashMap<OsString, u64> {
    let mut map = HashMap::new();
    let entries = match fs::read_dir(dest_dir) {
        Ok(iter) => iter,
        Err(_) => return map,
    };
    for entry in entries.flatten() {
        if let Ok(ft) = entry.file_type() {
            if ft.is_file() {
                if let Ok(meta) = entry.metadata() {
                    map.insert(entry.file_name(), meta.len());
                }
            }
        }
    }
    map
}

#[allow(clippy::too_many_arguments)]
fn walk_and_copy(
    dir: &Path,
    canonical_root: &Path,
    config: &CopyConfig,
    state: &CopySharedState,
    queue: &CopyQueue,
    visited_dirs: &mut HashSet<PathBuf>,
    created_dirs: &mut HashSet<PathBuf>,
    completed_dirs: &mut HashSet<String>,
    last_processed_files: &mut HashMap<String, String>,
    last_save: &mut Instant,
) {
    if state.is_stopped() || !state.wait_if_paused() {
        return;
    }

    let canonical_dir = fs::canonicalize(dir).unwrap_or_else(|_| normalize_lexical(dir));
    if !visited_dirs.insert(canonical_dir) {
        return;
    }

    let rel_path = relative_dir_string(dir, &config.source_path);
    if completed_dirs.contains(&rel_path) {
        state.dirs_skipped.fetch_add(1, Ordering::Relaxed);
        return;
    }

    let dir_name = path_basename(dir);
    state.set_phase(PHASE_SCANNING, Some(&dir_name), None);

    let entries = match fs::read_dir(dir) {
        Ok(iter) => iter,
        Err(e) => {
            state.errors.fetch_add(1, Ordering::Relaxed);
            state.push_error_log(format!("✗ Cannot access: {} ({e})", dir.display()));
            return;
        }
    };

    let mut files: Vec<FileCandidate> = Vec::new();
    let mut subdirs: Vec<PathBuf> = Vec::new();

    for entry_res in entries {
        if state.is_stopped() {
            return;
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
            files.push(FileCandidate {
                path: entry_path,
                name_os,
                name,
                known_meta: entry.metadata().ok(),
            });
        } else if ft.is_dir() {
            subdirs.push(entry_path);
        } else if ft.is_symlink() {
            if !resolve_within_root(canonical_root, &entry_path) {
                continue;
            }
            if let Ok(meta) = fs::metadata(&entry_path) {
                if meta.is_dir() {
                    subdirs.push(entry_path);
                } else if meta.is_file() {
                    let name_os = entry.file_name();
                    let name = name_os.to_string_lossy().into_owned();
                    files.push(FileCandidate {
                        path: entry_path,
                        name_os,
                        name,
                        known_meta: Some(meta),
                    });
                }
            }
        }
    }

    files.sort_by(|a, b| a.name.cmp(&b.name));
    subdirs.sort_by(|a, b| path_basename(a).cmp(&path_basename(b)));

    let mut start_index = 0usize;
    if let Some(last_name) = last_processed_files.get(&rel_path) {
        if let Some(idx) = files.iter().position(|f| &f.name == last_name) {
            start_index = idx + 1;
        }
    }

    if !files.is_empty() && start_index < files.len() {
        let dest_dir = if rel_path == "." {
            config.dest_path.clone()
        } else {
            config.dest_path.join(&rel_path)
        };
        let dest_sizes = read_dest_sizes(&dest_dir);

        let mut batch_queued = 0usize;
        let mut last_in_batch: Option<String> = None;

        for candidate in &files[start_index..] {
            if state.is_stopped() || !state.wait_if_paused() {
                break;
            }

            state.files_inspected.fetch_add(1, Ordering::Relaxed);

            let meta = match &candidate.known_meta {
                Some(m) => m.clone(),
                None => match fs::metadata(&candidate.path) {
                    Ok(m) => m,
                    Err(e) => {
                        state.errors.fetch_add(1, Ordering::Relaxed);
                        state.push_error_log(format!(
                            "✗ Failed to inspect {}: {e}",
                            candidate.name
                        ));
                        continue;
                    }
                },
            };

            let src_size = meta.len();
            let modified = match meta.modified() {
                Ok(m) => m,
                Err(e) => {
                    state.errors.fetch_add(1, Ordering::Relaxed);
                    state.push_error_log(format!(
                        "✗ Failed to inspect {}: {e}",
                        candidate.name
                    ));
                    continue;
                }
            };
            let modified_ms = system_time_to_epoch_ms(modified);

            if config.enable_age_filter && modified_ms > config.age_threshold_epoch_ms {
                state.files_skipped.fetch_add(1, Ordering::Relaxed);
                continue;
            }

            if config.enable_date_range
                && (modified_ms < config.from_inclusive_epoch_ms
                    || modified_ms >= config.to_exclusive_epoch_ms)
            {
                state.files_skipped.fetch_add(1, Ordering::Relaxed);
                continue;
            }

            if dest_sizes.get(&candidate.name_os) == Some(&src_size) {
                let already = state.files_already_exist.fetch_add(1, Ordering::Relaxed) + 1;
                if config.log_interval > 0 && already % config.log_interval == 0 {
                    state.set_phase(PHASE_CHECKING, Some(&dir_name), None);
                    state.push_log(format!(
                        "⏭ {already} files already exist at destination (skipping)"
                    ));
                }
                continue;
            }

            if !created_dirs.contains(&dest_dir) {
                if let Err(e) = fs::create_dir_all(&dest_dir) {
                    state.errors.fetch_add(1, Ordering::Relaxed);
                    state.push_error_log(format!(
                        "✗ Failed to copy {}: {e}",
                        candidate.name
                    ));
                    continue;
                }
                created_dirs.insert(dest_dir.clone());
            }

            queue.push(CopyTask {
                src: candidate.path.clone(),
                dest: dest_dir.join(&candidate.name_os),
                modified,
            });
            batch_queued += 1;
            last_in_batch = Some(candidate.name.clone());

            if batch_queued >= BATCH_FLUSH_THRESHOLD {
                queue.wait_idle(&state.stop_requested);
                if !state.is_stopped() {
                    if let Some(ref name) = last_in_batch {
                        last_processed_files.insert(rel_path.clone(), name.clone());
                    }
                }
                batch_queued = 0;

                if let Some(ref progress_path) = config.progress_file_path {
                    if last_save.elapsed() >= Duration::from_secs(1) {
                        save_progress_file(
                            progress_path,
                            config,
                            completed_dirs,
                            last_processed_files,
                            state,
                        );
                        *last_save = Instant::now();
                    }
                }
            }
        }

        if batch_queued > 0 {
            queue.wait_idle(&state.stop_requested);
            if !state.is_stopped() {
                if let Some(ref name) = last_in_batch {
                    last_processed_files.insert(rel_path.clone(), name.clone());
                }
            }
        }
    }

    for sub in subdirs {
        if state.is_stopped() {
            return;
        }
        walk_and_copy(
            &sub,
            canonical_root,
            config,
            state,
            queue,
            visited_dirs,
            created_dirs,
            completed_dirs,
            last_processed_files,
            last_save,
        );
    }

    if !state.is_stopped() {
        completed_dirs.insert(rel_path.clone());
        last_processed_files.remove(&rel_path);
        if let Some(ref progress_path) = config.progress_file_path {
            if completed_dirs.len() % 100 == 0 || last_save.elapsed() >= Duration::from_secs(1) {
                save_progress_file(
                    progress_path,
                    config,
                    completed_dirs,
                    last_processed_files,
                    state,
                );
                *last_save = Instant::now();
            }
        }
    }
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
            queue.close_and_clear();
            state.set_phase(PHASE_DONE, None, None);
            state.done.store(true, Ordering::Release);
            return;
        }
    };

    let mut workers = Vec::with_capacity(NUM_COPY_WORKERS);
    for _ in 0..NUM_COPY_WORKERS {
        if let Some(h) = spawn_copy_worker(
            Arc::clone(&queue),
            Arc::clone(&state),
            config.log_interval,
        ) {
            workers.push(h);
        }
    }

    let mut visited_dirs: HashSet<PathBuf> = HashSet::new();
    let mut created_dirs: HashSet<PathBuf> = HashSet::new();
    let mut completed_dirs = config.completed_dirs.clone();
    let mut last_processed_files = config.last_processed_files.clone();
    let mut last_save = Instant::now();

    walk_and_copy(
        &config.source_path,
        &canonical_root,
        &config,
        &state,
        &queue,
        &mut visited_dirs,
        &mut created_dirs,
        &mut completed_dirs,
        &mut last_processed_files,
        &mut last_save,
    );

    if state.is_stopped() {
        queue.close_and_clear();
    } else {
        queue.close();
    }
    for w in workers {
        let _ = w.join();
    }

    if state.is_stopped() {
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

    let mut json = String::with_capacity(384);
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
                    queue_for_panic.close_and_clear();
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

#[no_mangle]
pub unsafe extern "C" fn copy_engine_pause(job: *mut CopyJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let job_ref = &*job;
        if let Ok(mut paused) = job_ref.state.pause_lock.lock() {
            *paused = true;
        }
    }));
}

#[no_mangle]
pub unsafe extern "C" fn copy_engine_resume(job: *mut CopyJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let job_ref = &*job;
        if let Ok(mut paused) = job_ref.state.pause_lock.lock() {
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
        job_ref.state.stop_requested.store(true, Ordering::Release);
        if let Ok(mut paused) = job_ref.state.pause_lock.lock() {
            *paused = false;
        }
        job_ref.state.pause_cvar.notify_all();
        job_ref.queue.close_and_clear();
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
        boxed.state.stop_requested.store(true, Ordering::Release);
        if let Ok(mut paused) = boxed.state.pause_lock.lock() {
            *paused = false;
        }
        boxed.state.pause_cvar.notify_all();
        boxed.queue.close_and_clear();
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
}
