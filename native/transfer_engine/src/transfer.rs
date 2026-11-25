// Gene - Nov, 25, 2026: Native Rust file transfer engine module (using shared common helpers).

use std::collections::{HashSet, VecDeque};
use std::ffi::CString;
use std::fmt::Write as _;
use std::fs;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::SystemTime;

use crate::common::{
    c_str_to_string, normalize_lexical, path_basename, paths_equal_or_within, push_json_escaped,
    resolve_within_root, streaming_copy_to_part_and_swap, system_time_to_epoch_ms,
    COPY_BUFFER_BYTES, MAX_QUEUED_LOGS,
};

const SAVE_PROGRESS_INTERVAL_DIRS: u64 = 20;

const PHASE_STARTING: u8 = 0;
const PHASE_SCANNING: u8 = 1;
const PHASE_MOVING: u8 = 2;
const PHASE_STOPPING: u8 = 3;
const PHASE_DONE: u8 = 4;

#[repr(C)]
pub struct TransferConfigC {
    pub source_path: *const c_char,
    pub dest_path: *const c_char,
    pub last_scanned_dir: *const c_char,
    pub enable_age_filter: u8,
    pub age_threshold_epoch_ms: i64,
    pub enable_date_range: u8,
    pub from_inclusive_epoch_ms: i64,
    pub to_exclusive_epoch_ms: i64,
    pub exclude_subfolders: u8,
    pub initial_files_moved: u64,
    pub initial_errors: u64,
    pub log_interval: u64,
}

struct TransferConfig {
    source_path: PathBuf,
    dest_path: PathBuf,
    last_scanned_dir: Option<PathBuf>,
    enable_age_filter: bool,
    age_threshold_epoch_ms: i64,
    enable_date_range: bool,
    from_inclusive_epoch_ms: i64,
    to_exclusive_epoch_ms: i64,
    exclude_subfolders: bool,
    initial_files_moved: u64,
    initial_errors: u64,
    log_interval: u64,
}

struct UiState {
    current_dir_name: String,
    phase: u8,
    latest_save_dir: Option<String>,
    critical_error: Option<String>,
    logs: VecDeque<String>,
}

struct SharedState {
    files_scanned: AtomicU64,
    dirs_scanned: AtomicU64,
    files_moved: AtomicU64,
    errors: AtomicU64,
    stop_requested: AtomicBool,
    done: AtomicBool,
    pause_lock: Mutex<bool>,
    pause_cvar: Condvar,
    ui: Mutex<UiState>,
}

pub struct TransferJob {
    state: Arc<SharedState>,
    handle: Option<JoinHandle<()>>,
}

impl SharedState {
    fn new(initial_files_moved: u64, initial_errors: u64) -> Self {
        Self {
            files_scanned: AtomicU64::new(0),
            dirs_scanned: AtomicU64::new(0),
            files_moved: AtomicU64::new(initial_files_moved),
            errors: AtomicU64::new(initial_errors),
            stop_requested: AtomicBool::new(false),
            done: AtomicBool::new(false),
            pause_lock: Mutex::new(false),
            pause_cvar: Condvar::new(),
            ui: Mutex::new(UiState {
                current_dir_name: String::new(),
                phase: PHASE_STARTING,
                latest_save_dir: None,
                critical_error: None,
                logs: VecDeque::new(),
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

    fn set_phase_and_dir(&self, phase: u8, dir_name: &str, save_dir: Option<String>) {
        if let Ok(mut ui) = self.ui.lock() {
            ui.phase = phase;
            if !dir_name.is_empty() {
                ui.current_dir_name.clear();
                ui.current_dir_name.push_str(dir_name);
            }
            if let Some(dir) = save_dir {
                ui.latest_save_dir = Some(dir);
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
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        while *paused && !self.is_stopped() {
            paused = match self.pause_cvar.wait(paused) {
                Ok(guard) => guard,
                Err(poisoned) => poisoned.into_inner(),
            };
        }
        !self.is_stopped()
    }
}

fn move_file_with_fallback(
    src_file: &Path,
    dest_file: &Path,
    modified: SystemTime,
    copy_buf: &mut [u8],
    state: &SharedState,
) -> Result<(), String> {
    if fs::rename(src_file, dest_file).is_ok() {
        return Ok(());
    }

    streaming_copy_to_part_and_swap(
        src_file,
        dest_file,
        modified,
        copy_buf,
        &state.stop_requested,
        false,
    )?;

    if let Err(del_err) = fs::remove_file(src_file) {
        state.push_log(format!(
            "⚠ Copied to destination, but could not delete source: {} ({del_err})",
            src_file.display()
        ));
    }

    Ok(())
}

fn check_and_move_file(
    file_path: &Path,
    parent_dir: &Path,
    dir_name: &str,
    known_metadata: Option<fs::Metadata>,
    config: &TransferConfig,
    created_dirs: &mut HashSet<PathBuf>,
    copy_buf: &mut [u8],
    state: &SharedState,
) {
    state.files_scanned.fetch_add(1, Ordering::Relaxed);

    let meta = match known_metadata {
        Some(m) => m,
        None => match fs::metadata(file_path) {
            Ok(m) => m,
            Err(e) => {
                state.push_log(format!(
                    "✗ Error accessing {}: {e}",
                    file_path.display()
                ));
                state.errors.fetch_add(1, Ordering::Relaxed);
                return;
            }
        },
    };

    let modified = match meta.modified() {
        Ok(m) => m,
        Err(e) => {
            state.push_log(format!(
                "✗ Error accessing {}: {e}",
                file_path.display()
            ));
            state.errors.fetch_add(1, Ordering::Relaxed);
            return;
        }
    };

    let modified_ms = system_time_to_epoch_ms(modified);

    if config.enable_age_filter && modified_ms > config.age_threshold_epoch_ms {
        return;
    }

    if config.enable_date_range
        && (modified_ms < config.from_inclusive_epoch_ms
            || modified_ms >= config.to_exclusive_epoch_ms)
    {
        return;
    }

    let file_name = path_basename(file_path);
    let rel_dir = parent_dir
        .strip_prefix(&config.source_path)
        .unwrap_or_else(|_| Path::new(""));
    let dest_dir = if rel_dir.as_os_str().is_empty() {
        config.dest_path.clone()
    } else {
        config.dest_path.join(rel_dir)
    };
    let dest_file = dest_dir.join(&file_name);

    if !created_dirs.contains(&dest_dir) {
        if let Err(e) = fs::create_dir_all(&dest_dir) {
            state.push_log(format!(
                "✗ Failed to move {}: {e}",
                file_path.display()
            ));
            state.errors.fetch_add(1, Ordering::Relaxed);
            return;
        }
        created_dirs.insert(dest_dir);
    }

    if fs::symlink_metadata(&dest_file).is_ok() {
        state.push_log(format!(
            "⚠ Skipped {file_name}: a file with that name already exists at the destination"
        ));
        state.errors.fetch_add(1, Ordering::Relaxed);
        return;
    }

    match move_file_with_fallback(file_path, &dest_file, modified, copy_buf, state) {
        Ok(()) => {
            let moved = state.files_moved.fetch_add(1, Ordering::Relaxed) + 1;
            if config.log_interval > 0 && moved % config.log_interval == 0 {
                state.set_phase_and_dir(PHASE_MOVING, dir_name, None);
                state.push_log(format!("__MOVED__|{moved}|{modified_ms}|{file_name}"));
            }
        }
        Err(err) if err == "__STOPPED__" => {}
        Err(err) if err == "__EXISTS__" => {
            state.push_log(format!(
                "⚠ Skipped {file_name}: a file with that name already exists at the destination"
            ));
            state.errors.fetch_add(1, Ordering::Relaxed);
        }
        Err(err) => {
            state.push_log(format!(
                "✗ Failed to move {}: {err}",
                file_path.display()
            ));
            state.errors.fetch_add(1, Ordering::Relaxed);
        }
    }
}

fn run_transfer(config: TransferConfig, state: Arc<SharedState>) {
    let mut copy_buf = vec![0u8; COPY_BUFFER_BYTES];
    let mut created_dirs: HashSet<PathBuf> = HashSet::new();
    let mut visited_dirs: HashSet<PathBuf> = HashSet::new();
    let mut dirs_to_process: VecDeque<PathBuf> = VecDeque::new();

    let canonical_source_root = match fs::canonicalize(&config.source_path) {
        Ok(p) => p,
        Err(e) => {
            state.set_critical_error(format!(
                "Failed to access source directory {}: {e}",
                config.source_path.display()
            ));
            state.set_phase_and_dir(PHASE_DONE, "", None);
            state.done.store(true, Ordering::Release);
            return;
        }
    };

    let _ = &config.last_scanned_dir;

    dirs_to_process.push_back(config.source_path.clone());
    let recursive = !config.exclude_subfolders;

    while let Some(dir) = dirs_to_process.pop_front() {
        if state.is_stopped() || !state.wait_if_paused() {
            break;
        }

        let dir_name = path_basename(&dir);

        if paths_equal_or_within(&config.dest_path, &dir) {
            state.push_log(format!("ℹ Skipping destination folder: {dir_name}"));
            continue;
        }

        let canonical_dir = fs::canonicalize(&dir).unwrap_or_else(|_| normalize_lexical(&dir));
        if !visited_dirs.insert(canonical_dir) {
            continue;
        }

        let dirs_count = state.dirs_scanned.fetch_add(1, Ordering::Relaxed) + 1;
        let save_dir = if dirs_count % SAVE_PROGRESS_INTERVAL_DIRS == 0 {
            Some(dir.to_string_lossy().into_owned())
        } else {
            None
        };
        state.set_phase_and_dir(PHASE_SCANNING, &dir_name, save_dir);

        let entries = match fs::read_dir(&dir) {
            Ok(iter) => iter,
            Err(e) => {
                state.push_log(format!("✗ Error reading directory {}: {e}", dir.display()));
                continue;
            }
        };

        let mut subdirs: Vec<PathBuf> = Vec::new();

        for entry_res in entries {
            if state.is_stopped() || !state.wait_if_paused() {
                break;
            }

            let entry = match entry_res {
                Ok(e) => e,
                Err(e) => {
                    state.push_log(format!("✗ Error reading directory {}: {e}", dir.display()));
                    continue;
                }
            };

            let entry_path = entry.path();
            let file_type = match entry.file_type() {
                Ok(ft) => ft,
                Err(e) => {
                    state.push_log(format!(
                        "✗ Error accessing {}: {e}",
                        entry_path.display()
                    ));
                    state.errors.fetch_add(1, Ordering::Relaxed);
                    continue;
                }
            };

            if file_type.is_file() {
                let meta = entry.metadata().ok();
                check_and_move_file(
                    &entry_path,
                    &dir,
                    &dir_name,
                    meta,
                    &config,
                    &mut created_dirs,
                    &mut copy_buf,
                    &state,
                );
            } else if file_type.is_dir() {
                if recursive {
                    subdirs.push(entry_path);
                }
            } else if file_type.is_symlink() {
                if !resolve_within_root(&canonical_source_root, &entry_path) {
                    state.push_log(format!(
                        "ℹ Skipped link pointing outside the source: {}",
                        path_basename(&entry_path)
                    ));
                    continue;
                }
                if let Ok(target_meta) = fs::metadata(&entry_path) {
                    if target_meta.is_dir() {
                        if recursive {
                            subdirs.push(entry_path);
                        }
                    } else if target_meta.is_file() {
                        check_and_move_file(
                            &entry_path,
                            &dir,
                            &dir_name,
                            Some(target_meta),
                            &config,
                            &mut created_dirs,
                            &mut copy_buf,
                            &state,
                        );
                    }
                }
            }
        }

        if recursive && !subdirs.is_empty() {
            subdirs.sort_by(|a, b| path_basename(a).cmp(&path_basename(b)));
            for sub in subdirs {
                dirs_to_process.push_back(sub);
            }
        }
    }

    state.set_phase_and_dir(PHASE_DONE, "", None);
    state.done.store(true, Ordering::Release);
}

fn build_poll_json(state: &SharedState) -> String {
    let files_scanned = state.files_scanned.load(Ordering::Relaxed);
    let dirs_scanned = state.dirs_scanned.load(Ordering::Relaxed);
    let files_moved = state.files_moved.load(Ordering::Relaxed);
    let errors = state.errors.load(Ordering::Relaxed);
    let is_done = state.done.load(Ordering::Acquire);

    let (phase, current_dir_name, save_scanned_dir, critical_error, logs) =
        match state.ui.lock() {
            Ok(mut ui) => {
                let dir = ui.current_dir_name.clone();
                let save = ui.latest_save_dir.take();
                let crit = ui.critical_error.take();
                let drained: Vec<String> = ui.logs.drain(..).collect();
                (ui.phase, dir, save, crit, drained)
            }
            Err(_) => (PHASE_DONE, String::new(), None, None, Vec::new()),
        };

    let mut json = String::with_capacity(256);
    let _ = write!(
        json,
        "{{\"filesScanned\":{files_scanned},\"dirsScanned\":{dirs_scanned},\"filesMoved\":{files_moved},\"errors\":{errors},\"phase\":{phase},\"currentDirName\":"
    );
    push_json_escaped(&mut json, &current_dir_name);

    json.push_str(",\"saveScannedDir\":");
    match save_scanned_dir {
        Some(ref s) => push_json_escaped(&mut json, s),
        None => json.push_str("null"),
    }

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
    json.push_str("]}");
    json
}

#[no_mangle]
pub unsafe extern "C" fn transfer_engine_start(cfg: *const TransferConfigC) -> *mut TransferJob {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if cfg.is_null() {
            return std::ptr::null_mut();
        }
        let raw = &*cfg;
        let source = match c_str_to_string(raw.source_path) {
            Some(s) if !s.is_empty() => PathBuf::from(s),
            _ => return std::ptr::null_mut(),
        };
        let dest = match c_str_to_string(raw.dest_path) {
            Some(s) if !s.is_empty() => PathBuf::from(s),
            _ => return std::ptr::null_mut(),
        };
        let last_scanned_dir = c_str_to_string(raw.last_scanned_dir)
            .filter(|s| !s.is_empty())
            .map(PathBuf::from);

        let config = TransferConfig {
            source_path: source,
            dest_path: dest,
            last_scanned_dir,
            enable_age_filter: raw.enable_age_filter != 0,
            age_threshold_epoch_ms: raw.age_threshold_epoch_ms,
            enable_date_range: raw.enable_date_range != 0,
            from_inclusive_epoch_ms: raw.from_inclusive_epoch_ms,
            to_exclusive_epoch_ms: raw.to_exclusive_epoch_ms,
            exclude_subfolders: raw.exclude_subfolders != 0,
            initial_files_moved: raw.initial_files_moved,
            initial_errors: raw.initial_errors,
            log_interval: if raw.log_interval == 0 {
                100
            } else {
                raw.log_interval
            },
        };

        let state = Arc::new(SharedState::new(
            config.initial_files_moved,
            config.initial_errors,
        ));
        let worker_state = Arc::clone(&state);

        let handle = thread::Builder::new()
            .name("transfer_engine_worker".to_string())
            .spawn(move || {
                let state_for_panic = Arc::clone(&worker_state);
                let run_res = catch_unwind(AssertUnwindSafe(|| {
                    run_transfer(config, worker_state);
                }));
                if let Err(panic_info) = run_res {
                    let msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
                        (*s).to_string()
                    } else if let Some(s) = panic_info.downcast_ref::<String>() {
                        s.clone()
                    } else {
                        "Unknown worker panic".to_string()
                    };
                    state_for_panic.set_critical_error(msg);
                    state_for_panic.set_phase_and_dir(PHASE_DONE, "", None);
                    state_for_panic.done.store(true, Ordering::Release);
                }
            })
            .ok();

        match handle {
            Some(h) => Box::into_raw(Box::new(TransferJob {
                state,
                handle: Some(h),
            })),
            None => std::ptr::null_mut(),
        }
    }));

    res.unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn transfer_engine_pause(job: *mut TransferJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let job_ref = &*job;
        let mut paused = match job_ref.state.pause_lock.lock() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        *paused = true;
    }));
}

#[no_mangle]
pub unsafe extern "C" fn transfer_engine_resume(job: *mut TransferJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let job_ref = &*job;
        let mut paused = match job_ref.state.pause_lock.lock() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        *paused = false;
        job_ref.state.pause_cvar.notify_all();
    }));
}

#[no_mangle]
pub unsafe extern "C" fn transfer_engine_stop(job: *mut TransferJob) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return;
        }
        let job_ref = &*job;
        job_ref.state.stop_requested.store(true, Ordering::Release);
        job_ref.state.set_phase_and_dir(PHASE_STOPPING, "", None);
        if let Ok(mut paused) = job_ref.state.pause_lock.lock() {
            *paused = false;
        }
        job_ref.state.pause_cvar.notify_all();
    }));
}

#[no_mangle]
pub unsafe extern "C" fn transfer_engine_poll(job: *mut TransferJob) -> *mut c_char {
    let res = catch_unwind(AssertUnwindSafe(|| {
        if job.is_null() {
            return std::ptr::null_mut();
        }
        let job_ref = &*job;
        let json = build_poll_json(&job_ref.state);
        match CString::new(json) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => std::ptr::null_mut(),
        }
    }));

    res.unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn transfer_engine_destroy(job: *mut TransferJob) {
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
        if let Some(handle) = boxed.handle.take() {
            let _ = handle.join();
        }
    }));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transfer_engine_free_string;
    use std::ffi::CStr;
    use std::fs::File;
    use std::time::{Duration, UNIX_EPOCH};

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

    fn run_sync(cfg: TransferConfig) -> (Arc<SharedState>, Vec<String>) {
        let state = Arc::new(SharedState::new(
            cfg.initial_files_moved,
            cfg.initial_errors,
        ));
        run_transfer(cfg, Arc::clone(&state));
        let logs = state.ui.lock().unwrap().logs.drain(..).collect();
        (state, logs)
    }

    #[test]
    fn moves_files_and_preserves_subfolders_without_year_injection() {
        let root = make_temp_dir("rust_tx_basic");
        let src = root.join("source");
        let sub = src.join("subfolder");
        let dst = root.join("dest");
        fs::create_dir_all(&sub).unwrap();
        fs::create_dir_all(&dst).unwrap();

        fs::write(src.join("root.txt"), b"ROOT").unwrap();
        fs::write(sub.join("child.txt"), b"CHILD").unwrap();

        let (state, _) = run_sync(TransferConfig {
            source_path: src.clone(),
            dest_path: dst.clone(),
            last_scanned_dir: None,
            enable_age_filter: false,
            age_threshold_epoch_ms: 0,
            enable_date_range: false,
            from_inclusive_epoch_ms: 0,
            to_exclusive_epoch_ms: 0,
            exclude_subfolders: false,
            initial_files_moved: 0,
            initial_errors: 0,
            log_interval: 1,
        });

        assert!(dst.join("root.txt").exists());
        assert!(dst.join("subfolder").join("child.txt").exists());
        assert!(!src.join("root.txt").exists());
        assert!(!sub.join("child.txt").exists());
        assert_eq!(state.files_moved.load(Ordering::Relaxed), 2);
        assert_eq!(state.files_scanned.load(Ordering::Relaxed), 2);
        assert_eq!(state.errors.load(Ordering::Relaxed), 0);

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn never_overwrites_existing_destination_file() {
        let root = make_temp_dir("rust_tx_no_overwrite");
        let src = root.join("source");
        let dst = root.join("dest");
        fs::create_dir_all(&src).unwrap();
        fs::create_dir_all(&dst).unwrap();

        fs::write(src.join("report.txt"), b"INCOMING").unwrap();
        fs::write(dst.join("report.txt"), b"ORIGINAL").unwrap();

        let (state, logs) = run_sync(TransferConfig {
            source_path: src.clone(),
            dest_path: dst.clone(),
            last_scanned_dir: None,
            enable_age_filter: false,
            age_threshold_epoch_ms: 0,
            enable_date_range: false,
            from_inclusive_epoch_ms: 0,
            to_exclusive_epoch_ms: 0,
            exclude_subfolders: false,
            initial_files_moved: 0,
            initial_errors: 0,
            log_interval: 100,
        });

        assert_eq!(fs::read(dst.join("report.txt")).unwrap(), b"ORIGINAL");
        assert!(src.join("report.txt").exists());
        assert_eq!(state.files_moved.load(Ordering::Relaxed), 0);
        assert_eq!(state.errors.load(Ordering::Relaxed), 1);
        assert_eq!(state.files_scanned.load(Ordering::Relaxed), 1);
        assert!(logs.iter().any(|l| l.contains("already exists")));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn date_range_filter_counts_all_scanned_and_moves_only_matching() {
        let root = make_temp_dir("rust_tx_date_range");
        let src = root.join("source");
        let dst = root.join("dest");
        fs::create_dir_all(&src).unwrap();
        fs::create_dir_all(&dst).unwrap();

        let old_f = File::create(src.join("old.txt")).unwrap();
        let match_f = File::create(src.join("match.txt")).unwrap();
        let new_f = File::create(src.join("new.txt")).unwrap();

        let t_old = UNIX_EPOCH + Duration::from_secs(1_700_000_000);
        let t_match = UNIX_EPOCH + Duration::from_secs(1_700_500_000);
        let t_new = UNIX_EPOCH + Duration::from_secs(1_701_000_000);

        old_f.set_modified(t_old).unwrap();
        match_f.set_modified(t_match).unwrap();
        new_f.set_modified(t_new).unwrap();
        drop(old_f);
        drop(match_f);
        drop(new_f);

        let (state, _) = run_sync(TransferConfig {
            source_path: src.clone(),
            dest_path: dst.clone(),
            last_scanned_dir: None,
            enable_age_filter: false,
            age_threshold_epoch_ms: 0,
            enable_date_range: true,
            from_inclusive_epoch_ms: 1_700_400_000_000,
            to_exclusive_epoch_ms: 1_700_600_000_000,
            exclude_subfolders: false,
            initial_files_moved: 0,
            initial_errors: 0,
            log_interval: 1,
        });

        assert!(dst.join("match.txt").exists());
        assert!(!src.join("match.txt").exists());
        assert!(src.join("old.txt").exists());
        assert!(src.join("new.txt").exists());
        assert_eq!(state.files_moved.load(Ordering::Relaxed), 1);
        assert_eq!(state.files_scanned.load(Ordering::Relaxed), 3);

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn age_filter_moves_only_older_files() {
        let root = make_temp_dir("rust_tx_age");
        let src = root.join("source");
        let dst = root.join("dest");
        fs::create_dir_all(&src).unwrap();
        fs::create_dir_all(&dst).unwrap();

        let old_f = File::create(src.join("old.txt")).unwrap();
        let recent_f = File::create(src.join("recent.txt")).unwrap();

        let now = SystemTime::now();
        old_f
            .set_modified(now - Duration::from_secs(60 * 60 * 24 * 40))
            .unwrap();
        recent_f.set_modified(now).unwrap();
        drop(old_f);
        drop(recent_f);

        let threshold_ms = system_time_to_epoch_ms(now - Duration::from_secs(60 * 60 * 24 * 30));

        let (state, _) = run_sync(TransferConfig {
            source_path: src.clone(),
            dest_path: dst.clone(),
            last_scanned_dir: None,
            enable_age_filter: true,
            age_threshold_epoch_ms: threshold_ms,
            enable_date_range: false,
            from_inclusive_epoch_ms: 0,
            to_exclusive_epoch_ms: 0,
            exclude_subfolders: false,
            initial_files_moved: 0,
            initial_errors: 0,
            log_interval: 100,
        });

        assert!(dst.join("old.txt").exists());
        assert!(!dst.join("recent.txt").exists());
        assert!(src.join("recent.txt").exists());
        assert_eq!(state.files_moved.load(Ordering::Relaxed), 1);
        assert_eq!(state.files_scanned.load(Ordering::Relaxed), 2);

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn exclude_subfolders_skips_nested_directories() {
        let root = make_temp_dir("rust_tx_nosub");
        let src = root.join("source");
        let sub = src.join("nested");
        let dst = root.join("dest");
        fs::create_dir_all(&sub).unwrap();
        fs::create_dir_all(&dst).unwrap();

        fs::write(src.join("top.txt"), b"TOP").unwrap();
        fs::write(sub.join("deep.txt"), b"DEEP").unwrap();

        let (state, _) = run_sync(TransferConfig {
            source_path: src.clone(),
            dest_path: dst.clone(),
            last_scanned_dir: None,
            enable_age_filter: false,
            age_threshold_epoch_ms: 0,
            enable_date_range: false,
            from_inclusive_epoch_ms: 0,
            to_exclusive_epoch_ms: 0,
            exclude_subfolders: true,
            initial_files_moved: 0,
            initial_errors: 0,
            log_interval: 100,
        });

        assert!(dst.join("top.txt").exists());
        assert!(!dst.join("nested").exists());
        assert!(sub.join("deep.txt").exists());
        assert_eq!(state.files_moved.load(Ordering::Relaxed), 1);
        assert_eq!(state.files_scanned.load(Ordering::Relaxed), 1);

        let _ = fs::remove_dir_all(&root);
    }

    #[cfg(unix)]
    #[test]
    fn symlink_outside_source_root_is_skipped() {
        use std::os::unix::fs::symlink;

        let root = make_temp_dir("rust_tx_symlink");
        let src = root.join("source");
        let outside = root.join("outside");
        let dst = root.join("dest");
        fs::create_dir_all(&src).unwrap();
        fs::create_dir_all(&outside).unwrap();
        fs::create_dir_all(&dst).unwrap();

        let secret = outside.join("secret.txt");
        fs::write(&secret, b"SECRET").unwrap();
        symlink(&secret, src.join("escape_link.txt")).unwrap();

        let (state, logs) = run_sync(TransferConfig {
            source_path: src.clone(),
            dest_path: dst.clone(),
            last_scanned_dir: None,
            enable_age_filter: false,
            age_threshold_epoch_ms: 0,
            enable_date_range: false,
            from_inclusive_epoch_ms: 0,
            to_exclusive_epoch_ms: 0,
            exclude_subfolders: false,
            initial_files_moved: 0,
            initial_errors: 0,
            log_interval: 100,
        });

        assert!(secret.exists());
        assert!(!dst.join("escape_link.txt").exists());
        assert_eq!(state.files_moved.load(Ordering::Relaxed), 0);
        assert!(logs
            .iter()
            .any(|l| l.contains("Skipped link pointing outside the source")));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn ffi_pause_resume_and_stop_work_cleanly() {
        let root = make_temp_dir("rust_tx_ffi");
        let src = root.join("source");
        let dst = root.join("dest");
        fs::create_dir_all(&src).unwrap();
        fs::create_dir_all(&dst).unwrap();
        for i in 0..10 {
            fs::write(src.join(format!("file_{i}.txt")), b"DATA").unwrap();
        }

        let c_src = CString::new(src.to_string_lossy().as_ref()).unwrap();
        let c_dst = CString::new(dst.to_string_lossy().as_ref()).unwrap();
        let cfg = TransferConfigC {
            source_path: c_src.as_ptr(),
            dest_path: c_dst.as_ptr(),
            last_scanned_dir: std::ptr::null(),
            enable_age_filter: 0,
            age_threshold_epoch_ms: 0,
            enable_date_range: 0,
            from_inclusive_epoch_ms: 0,
            to_exclusive_epoch_ms: 0,
            exclude_subfolders: 0,
            initial_files_moved: 0,
            initial_errors: 0,
            log_interval: 5,
        };

        unsafe {
            let job = transfer_engine_start(&cfg);
            assert!(!job.is_null());
            transfer_engine_pause(job);
            transfer_engine_resume(job);

            let mut done = false;
            for _ in 0..100 {
                let ptr = transfer_engine_poll(job);
                assert!(!ptr.is_null());
                let json = CStr::from_ptr(ptr).to_string_lossy().into_owned();
                transfer_engine_free_string(ptr);
                if json.contains("\"isDone\":true") {
                    done = true;
                    break;
                }
                thread::sleep(Duration::from_millis(20));
            }
            assert!(done);
            transfer_engine_stop(job);
            transfer_engine_destroy(job);
        }

        assert_eq!(fs::read_dir(&dst).unwrap().count(), 10);
        let _ = fs::remove_dir_all(&root);
    }
}
