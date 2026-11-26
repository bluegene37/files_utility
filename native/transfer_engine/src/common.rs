// Gene - Nov, 25, 2026: Shared utilities, JSON encoding, symlink containment, and
// OS-native zero-copy / SMB-offloaded file move & copy helpers.

// use std::ffi::{CStr, OsString};
// Gene - Nov, 26, 2026: Added OsStr, io_worker_count, case-accurate FilenameKey/filename_key, and single-canonicalize resolve_canonical_within_root.
use std::ffi::{CStr, OsStr, OsString};
use std::fmt::Write as _;
use std::fs;
#[cfg(not(windows))]
use std::fs::OpenOptions;
use std::os::raw::c_char;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

pub const DEFAULT_IO_WORKERS: usize = 8;
pub const MAX_QUEUE_CAPACITY: usize = 256;
pub const MAX_QUEUED_LOGS: usize = 2000;

pub fn io_worker_count() -> usize {
    std::thread::available_parallelism()
        .map(|n| n.get().clamp(8, 12))
        .unwrap_or(DEFAULT_IO_WORKERS)
}

#[cfg(any(windows, target_os = "macos"))]
pub type FilenameKey = String;

#[cfg(any(windows, target_os = "macos"))]
pub fn filename_key(name: &OsStr) -> FilenameKey {
    let lossy = name.to_string_lossy();
    if lossy.is_ascii() {
        lossy.to_ascii_lowercase()
    } else {
        lossy.to_lowercase()
    }
}

#[cfg(not(any(windows, target_os = "macos")))]
pub type FilenameKey = OsString;

#[cfg(not(any(windows, target_os = "macos")))]
pub fn filename_key(name: &OsStr) -> FilenameKey {
    name.to_os_string()
}

pub unsafe fn c_str_to_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    Some(CStr::from_ptr(ptr).to_string_lossy().into_owned())
}

pub fn system_time_to_epoch_ms(time: SystemTime) -> i64 {
    match time.duration_since(UNIX_EPOCH) {
        Ok(dur) => i64::try_from(dur.as_millis()).unwrap_or(i64::MAX),
        Err(err) => {
            let dur = err.duration();
            let ms = i64::try_from(dur.as_millis()).unwrap_or(i64::MAX);
            ms.saturating_neg()
        }
    }
}

pub fn path_basename(path: &Path) -> String {
    path.file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| path.to_string_lossy().into_owned())
}

pub fn normalize_lexical(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for comp in path.components() {
        match comp {
            Component::CurDir => {}
            Component::ParentDir => {
                if !out.pop() {
                    out.push(comp.as_os_str());
                }
            }
            _ => out.push(comp.as_os_str()),
        }
    }
    out
}

pub fn lexical_equal_or_within(norm_parent: &Path, candidate: &Path) -> bool {
    let norm_candidate = normalize_lexical(candidate);
    norm_candidate == norm_parent || norm_candidate.starts_with(norm_parent)
}

pub fn relative_dir_string(dir: &Path, root: &Path) -> String {
    match dir.strip_prefix(root) {
        Ok(rel) if rel.as_os_str().is_empty() => ".".to_string(),
        Ok(rel) => rel.to_string_lossy().into_owned(),
        Err(_) => ".".to_string(),
    }
}

pub fn append_part_extension(path: &Path) -> PathBuf {
    let mut os: OsString = path.as_os_str().to_os_string();
    os.push(".part");
    PathBuf::from(os)
}

// pub fn resolve_within_root(canonical_root: &Path, candidate: &Path) -> bool {
//     match fs::canonicalize(candidate) {
//         Ok(resolved) => resolved == canonical_root || resolved.starts_with(canonical_root),
//         Err(_) => false,
//     }
// }
// Gene - Nov, 26, 2026: Canonicalize symlink once and return the resolved target path when contained inside canonical_root.
pub fn resolve_canonical_within_root(canonical_root: &Path, candidate: &Path) -> Option<PathBuf> {
    match fs::canonicalize(candidate) {
        Ok(resolved) if resolved == canonical_root || resolved.starts_with(canonical_root) => {
            Some(resolved)
        }
        _ => None,
    }
}

pub fn resolve_within_root(canonical_root: &Path, candidate: &Path) -> bool {
    resolve_canonical_within_root(canonical_root, candidate).is_some()
}

pub fn push_json_escaped(out: &mut String, s: &str) {
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

pub enum MoveOutcome {
    Moved,
    CopiedSourceDeleteFailed(String),
}

#[cfg(windows)]
mod win32_fs {
    use std::ffi::c_void;
    use std::io;
    use std::os::windows::ffi::OsStrExt;
    use std::path::Path;
    use std::sync::atomic::AtomicI32;

    const MOVEFILE_REPLACE_EXISTING: u32 = 0x1;
    const ERROR_FILE_EXISTS: i32 = 80;
    const ERROR_ALREADY_EXISTS: i32 = 183;
    const ERROR_REQUEST_ABORTED: i32 = 1235;

    pub enum WinMoveErr {
        AlreadyExists,
        Other(io::Error),
    }

    #[link(name = "kernel32")]
    extern "system" {
        fn CopyFileExW(
            lpExistingFileName: *const u16,
            lpNewFileName: *const u16,
            lpProgressRoutine: *const c_void,
            lpData: *mut c_void,
            pbCancel: *const i32,
            dwCopyFlags: u32,
        ) -> i32;

        fn MoveFileExW(
            lpExistingFileName: *const u16,
            lpNewFileName: *const u16,
            dwFlags: u32,
        ) -> i32;
    }

    fn to_wide_null(path: &Path) -> Vec<u16> {
        path.as_os_str()
            .encode_wide()
            .chain(std::iter::once(0))
            .collect()
    }

    pub fn move_no_overwrite(src: &Path, dst: &Path) -> Result<(), WinMoveErr> {
        let src_w = to_wide_null(src);
        let dst_w = to_wide_null(dst);
        let ok = unsafe { MoveFileExW(src_w.as_ptr(), dst_w.as_ptr(), 0) };
        if ok != 0 {
            return Ok(());
        }
        let err = io::Error::last_os_error();
        match err.raw_os_error() {
            Some(ERROR_FILE_EXISTS) | Some(ERROR_ALREADY_EXISTS) => Err(WinMoveErr::AlreadyExists),
            _ => Err(WinMoveErr::Other(err)),
        }
    }

    pub fn move_replace(src: &Path, dst: &Path) -> Result<(), String> {
        let src_w = to_wide_null(src);
        let dst_w = to_wide_null(dst);
        let ok = unsafe { MoveFileExW(src_w.as_ptr(), dst_w.as_ptr(), MOVEFILE_REPLACE_EXISTING) };
        if ok != 0 {
            return Ok(());
        }
        Err(format!(
            "MoveFileExW failed: {}",
            io::Error::last_os_error()
        ))
    }

    pub fn copy_file_ex(src: &Path, dst: &Path, cancel_flag: &AtomicI32) -> Result<(), String> {
        let src_w = to_wide_null(src);
        let dst_w = to_wide_null(dst);
        let ok = unsafe {
            CopyFileExW(
                src_w.as_ptr(),
                dst_w.as_ptr(),
                std::ptr::null(),
                std::ptr::null_mut(),
                cancel_flag.as_ptr(),
                0,
            )
        };
        if ok != 0 {
            return Ok(());
        }
        let err = io::Error::last_os_error();
        if err.raw_os_error() == Some(ERROR_REQUEST_ABORTED) {
            return Err("__STOPPED__".to_string());
        }
        Err(format!("CopyFileExW failed: {err}"))
    }
}

/// Copies `src_file` into `<dest_file>.part` using OS-native kernel/SMB offload
/// (`CopyFileExW` on Windows, `fs::copy` / `fcopyfile` / `copy_file_range` on Unix),
/// preserves modification timestamps, and swaps into `dest_file` atomically.
// pub fn fast_copy_to_part_and_swap(
//     src_file: &Path,
//     dest_file: &Path,
//     modified: Option<SystemTime>,
//     stop_requested: &AtomicBool,
//     cancel_flag: &AtomicI32,
//     allow_overwrite: bool,
// ) -> Result<(), String> {
//     if stop_requested.load(Ordering::Acquire) {
//         return Err("__STOPPED__".to_string());
//     }
//
//     let temp_path = append_part_extension(dest_file);
//
//     #[cfg(windows)]
//     let result: Result<(), String> = {
//         let _ = modified;
//         let res = (|| {
//             win32_fs::copy_file_ex(src_file, &temp_path, cancel_flag)?;
//             if stop_requested.load(Ordering::Acquire) {
//                 return Err("__STOPPED__".to_string());
//             }
//             if allow_overwrite {
//                 win32_fs::move_replace(&temp_path, dest_file)
//             } else {
//                 match win32_fs::move_no_overwrite(&temp_path, dest_file) {
//                     Ok(()) => Ok(()),
//                     Err(win32_fs::WinMoveErr::AlreadyExists) => Err("__EXISTS__".to_string()),
//                     Err(win32_fs::WinMoveErr::Other(e)) => {
//                         Err(format!("MoveFileExW failed: {e}"))
//                     }
//                 }
//             }
//         })();
//         res
//     };
//
//     #[cfg(not(windows))]
//     let result: Result<(), String> = {
//         let _ = cancel_flag;
//         (|| {
//             let copied = fs::copy(src_file, &temp_path)
//                 .map_err(|e| format!("copy to temp file: {e}"))?;
//             if stop_requested.load(Ordering::Acquire) {
//                 return Err("__STOPPED__".to_string());
//             }
//             if let Ok(src_meta) = fs::metadata(src_file) {
//                 let src_len = src_meta.len();
//                 if copied != src_len {
//                     return Err(format!("Incomplete copy ({copied} of {src_len} bytes)"));
//                 }
//             }
//             if let Some(mtime) = modified {
//                 if let Ok(f) = OpenOptions::new().write(true).open(&temp_path) {
//                     let _ = f.set_modified(mtime);
//                 }
//             }
//             if !allow_overwrite && fs::symlink_metadata(dest_file).is_ok() {
//                 return Err("__EXISTS__".to_string());
//             }
//             fs::rename(&temp_path, dest_file).map_err(|e| format!("rename temp to dest: {e}"))
//         })()
//     };
//
//     if result.is_err() {
//         let _ = fs::remove_file(&temp_path);
//     }
//
//     result
// }
// Gene - Nov, 26, 2026: Preserve mtime on read-only copied files and force-clean read-only .part temp files.
fn remove_temp_file_force(path: &Path) {
    if fs::remove_file(path).is_err() {
        if let Ok(meta) = fs::symlink_metadata(path) {
            let mut perms = meta.permissions();
            if perms.readonly() {
                perms.set_readonly(false);
                let _ = fs::set_permissions(path, perms);
                let _ = fs::remove_file(path);
            }
        }
    }
}

pub fn fast_copy_to_part_and_swap(
    src_file: &Path,
    dest_file: &Path,
    modified: Option<SystemTime>,
    stop_requested: &AtomicBool,
    cancel_flag: &AtomicI32,
    allow_overwrite: bool,
) -> Result<(), String> {
    if stop_requested.load(Ordering::Acquire) {
        return Err("__STOPPED__".to_string());
    }

    let temp_path = append_part_extension(dest_file);

    #[cfg(windows)]
    let result: Result<(), String> = {
        let _ = modified;
        if fs::symlink_metadata(&temp_path).is_ok() {
            remove_temp_file_force(&temp_path);
        }
        let res = (|| {
            win32_fs::copy_file_ex(src_file, &temp_path, cancel_flag)?;
            if stop_requested.load(Ordering::Acquire) {
                return Err("__STOPPED__".to_string());
            }
            if allow_overwrite {
                win32_fs::move_replace(&temp_path, dest_file)
            } else {
                match win32_fs::move_no_overwrite(&temp_path, dest_file) {
                    Ok(()) => Ok(()),
                    Err(win32_fs::WinMoveErr::AlreadyExists) => Err("__EXISTS__".to_string()),
                    Err(win32_fs::WinMoveErr::Other(e)) => {
                        Err(format!("MoveFileExW failed: {e}"))
                    }
                }
            }
        })();
        res
    };

    #[cfg(not(windows))]
    let result: Result<(), String> = {
        let _ = cancel_flag;
        (|| {
            let copied = fs::copy(src_file, &temp_path)
                .map_err(|e| format!("copy to temp file: {e}"))?;
            if stop_requested.load(Ordering::Acquire) {
                return Err("__STOPPED__".to_string());
            }
            if let Ok(src_meta) = fs::metadata(src_file) {
                let src_len = src_meta.len();
                if copied != src_len {
                    return Err(format!("Incomplete copy ({copied} of {src_len} bytes)"));
                }
            }
            if let Some(mtime) = modified {
                if let Ok(f) = OpenOptions::new()
                    .write(true)
                    .open(&temp_path)
                    .or_else(|_| fs::File::open(&temp_path))
                {
                    let _ = f.set_modified(mtime);
                }
            }
            if !allow_overwrite && fs::symlink_metadata(dest_file).is_ok() {
                return Err("__EXISTS__".to_string());
            }
            fs::rename(&temp_path, dest_file).map_err(|e| format!("rename temp to dest: {e}"))
        })()
    };

    if result.is_err() {
        remove_temp_file_force(&temp_path);
    }

    result
}

/// Moves `src_file` to `dest_file` without ever overwriting an existing destination.
/// Uses atomic `MoveFileExW` / `fs::rename` first, falling back to kernel-offloaded
/// `.part` copy + source delete across volumes/SMB shares.
pub fn fast_move_no_overwrite(
    src_file: &Path,
    dest_file: &Path,
    modified: Option<SystemTime>,
    stop_requested: &AtomicBool,
    cancel_flag: &AtomicI32,
) -> Result<MoveOutcome, String> {
    if stop_requested.load(Ordering::Acquire) {
        return Err("__STOPPED__".to_string());
    }

    #[cfg(windows)]
    {
        match win32_fs::move_no_overwrite(src_file, dest_file) {
            Ok(()) => return Ok(MoveOutcome::Moved),
            Err(win32_fs::WinMoveErr::AlreadyExists) => return Err("__EXISTS__".to_string()),
            Err(win32_fs::WinMoveErr::Other(_)) => {}
        }
    }

    #[cfg(not(windows))]
    {
        if fs::symlink_metadata(dest_file).is_ok() {
            return Err("__EXISTS__".to_string());
        }
        if fs::rename(src_file, dest_file).is_ok() {
            return Ok(MoveOutcome::Moved);
        }
    }

    fast_copy_to_part_and_swap(
        src_file,
        dest_file,
        modified.or_else(|| fs::metadata(src_file).and_then(|m| m.modified()).ok()),
        stop_requested,
        cancel_flag,
        false,
    )?;

    if let Err(del_err) = fs::remove_file(src_file) {
        return Ok(MoveOutcome::CopiedSourceDeleteFailed(del_err.to_string()));
    }

    Ok(MoveOutcome::Moved)
}
