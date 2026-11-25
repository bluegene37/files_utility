// Gene - Nov, 25, 2026: Shared utilities, JSON encoding, path containment, and reusable
// 512 KiB streaming copy helper for all native Rust file engines.

use std::ffi::{CStr, OsString};
use std::fmt::Write as _;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::raw::c_char;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

pub const COPY_BUFFER_BYTES: usize = 512 * 1024;
pub const MAX_QUEUED_LOGS: usize = 2000;

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

pub fn paths_equal_or_within(parent: &Path, candidate: &Path) -> bool {
    let norm_parent = normalize_lexical(parent);
    let norm_candidate = normalize_lexical(candidate);
    if norm_candidate == norm_parent || norm_candidate.starts_with(&norm_parent) {
        return true;
    }
    if let (Ok(canon_parent), Ok(canon_candidate)) =
        (fs::canonicalize(parent), fs::canonicalize(candidate))
    {
        return canon_candidate == canon_parent || canon_candidate.starts_with(&canon_parent);
    }
    false
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

pub fn resolve_within_root(canonical_root: &Path, candidate: &Path) -> bool {
    match fs::canonicalize(candidate) {
        Ok(resolved) => resolved == canonical_root || resolved.starts_with(canonical_root),
        Err(_) => false,
    }
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

/// Streams `src_file` into `<dest_file>.part` using a caller-owned reusable buffer,
/// verifies exact byte count, preserves `modified`, closes handles before rename
/// (required on Windows), and cleans up `.part` on any error or stop signal.
pub fn streaming_copy_to_part_and_swap(
    src_file: &Path,
    dest_file: &Path,
    modified: SystemTime,
    copy_buf: &mut [u8],
    stop_requested: &AtomicBool,
    allow_overwrite: bool,
) -> Result<(), String> {
    let temp_path = append_part_extension(dest_file);

    let result: Result<(), String> = (|| {
        let mut src = File::open(src_file).map_err(|e| format!("open source: {e}"))?;
        let src_len = src
            .metadata()
            .map_err(|e| format!("stat source: {e}"))?
            .len();

        let mut dst = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(&temp_path)
            .map_err(|e| format!("create temp file: {e}"))?;

        let mut bytes_copied: u64 = 0;
        loop {
            if stop_requested.load(Ordering::Acquire) {
                drop(dst);
                let _ = fs::remove_file(&temp_path);
                return Err("__STOPPED__".to_string());
            }

            let n = src
                .read(copy_buf)
                .map_err(|e| format!("read source: {e}"))?;
            if n == 0 {
                break;
            }
            dst.write_all(&copy_buf[..n])
                .map_err(|e| format!("write temp file: {e}"))?;
            bytes_copied += n as u64;
        }

        dst.flush().map_err(|e| format!("flush temp file: {e}"))?;

        let dst_len = dst
            .metadata()
            .map_err(|e| format!("stat temp file: {e}"))?
            .len();
        if bytes_copied != src_len || dst_len != src_len {
            return Err(format!(
                "Incomplete copy ({dst_len} of {src_len} bytes)"
            ));
        }

        let _ = dst.set_modified(modified);
        // Must close handle before renaming on Windows.
        drop(dst);
        drop(src);

        if !allow_overwrite && fs::symlink_metadata(dest_file).is_ok() {
            return Err("__EXISTS__".to_string());
        }

        fs::rename(&temp_path, dest_file).map_err(|e| format!("rename temp to dest: {e}"))?;
        Ok(())
    })();

    if result.is_err() {
        let _ = fs::remove_file(&temp_path);
    }

    result
}
