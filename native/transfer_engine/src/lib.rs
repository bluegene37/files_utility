// Gene - Nov, 25, 2026: Crate root exposing native Rust engines (transfer, copy, count, delete, ftp_scan) over C-ABI.

use std::ffi::CString;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};

pub mod common;
pub mod copy;
pub mod count;
pub mod delete;
pub mod ftp_scan;
pub mod transfer;

pub use copy::{
    copy_engine_destroy, copy_engine_pause, copy_engine_poll, copy_engine_resume,
    copy_engine_start, copy_engine_stop, CopyConfigC, CopyJob,
};
pub use count::{
    count_engine_destroy, count_engine_poll, count_engine_start, count_engine_stop, CountConfigC,
    CountJob,
};
pub use delete::{
    delete_engine_destroy, delete_engine_poll, delete_engine_start, delete_engine_stop,
    DeleteConfigC, DeleteJob,
};
pub use ftp_scan::{
    ftp_scan_destroy, ftp_scan_poll, ftp_scan_start, native_file_creation_ms, FtpScanJob,
};
pub use transfer::{
    transfer_engine_destroy, transfer_engine_pause, transfer_engine_poll, transfer_engine_resume,
    transfer_engine_start, transfer_engine_stop, TransferConfigC, TransferJob,
};

#[no_mangle]
pub unsafe extern "C" fn transfer_engine_free_string(ptr: *mut c_char) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !ptr.is_null() {
            drop(CString::from_raw(ptr));
        }
    }));
}
