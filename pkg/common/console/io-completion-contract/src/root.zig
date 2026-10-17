//! Route-independent: I/O completion port semantics and the asynchronous I/O
//! status block layout.
//!
//! ## Why the status block is the fact worth fixing
//!
//! An overlapped read hands the kernel a pointer to a status block and returns
//! `STATUS_PENDING` before the data exists. The title then polls or waits, and
//! reads the block when it believes the operation finished. Everything about
//! that is a race unless the *order* of the two writes is fixed: information
//! first, status last. A runtime that fills the status field before the byte
//! count lets the title observe "complete" and then read a stale length, and
//! the resulting short read is attributed to the file, the disc image, or the
//! decompressor — anything but the ordering.
//!
//! `STATUS_PENDING` is 0x00000103, which is a *success* code by the high-bit
//! convention. Code that tests `status >= 0` to mean "done" therefore treats a
//! pending operation as finished. That single misreading produces reads of
//! uninitialised buffers that look like corrupt game data.
//!
//! ## What this package is not
//!
//! * It is not a completion port. It queues nothing and holds no pending
//!   operations; that state is `lib/io/`'s.
//! * It performs no I/O. The host filesystem APIs are out of reach from a
//!   package by construction.
//! * It does not complete an operation. `isComplete` classifies a status value
//!   it was handed.

const std = @import("std");

// ---------------------------------------------------------------------------
// Status codes
// ---------------------------------------------------------------------------

/// NTSTATUS is a signed 32-bit value whose top two bits are its severity.
pub const Status = u32;

pub const status_success: Status = 0x0000_0000;
/// A success code, despite meaning "not finished". The trap.
pub const status_pending: Status = 0x0000_0103;
pub const status_timeout: Status = 0x0000_0102;
pub const status_end_of_file: Status = 0xC000_0011;
pub const status_invalid_handle: Status = 0xC000_0008;
pub const status_cancelled: Status = 0xC000_0120;

/// Severity lives in the top two bits.
pub const severity_shift: u5 = 30;

pub const Severity = enum(u2) {
    success = 0,
    informational = 1,
    warning = 2,
    @"error" = 3,
};

pub fn severityOf(status: Status) Severity {
    return @enumFromInt(@as(u2, @truncate(status >> severity_shift)));
}

/// Whether a status reports failure.
pub fn isError(status: Status) bool {
    return severityOf(status) == .@"error";
}

/// Whether a status means the operation is finished, successfully or not.
///
/// The predicate that must be used instead of a sign test. `STATUS_PENDING` is
/// a success-severity code and is the one value that is emphatically *not*
/// complete.
pub fn isComplete(status: Status) bool {
    return status != status_pending;
}

// ---------------------------------------------------------------------------
// Status block
// ---------------------------------------------------------------------------

/// `IO_STATUS_BLOCK` as the guest sees it. Big-endian 32-bit fields on the
/// console; `extern` because the guest reads these offsets.
pub const IoStatusBlock = extern struct {
    status: Status = status_pending,
    /// Bytes transferred. Meaningful only once `status` is not pending.
    information: u32 = 0,

    pub fn isComplete(self: IoStatusBlock) bool {
        return self.status != status_pending;
    }
};

/// The order the two fields must be written in when an operation completes.
///
/// Information first, status last. Stated as data so a runtime can assert it
/// rather than rely on a comment being read.
pub const CompletionWriteOrder = enum(u8) {
    information_then_status,
    status_then_information,
};

pub const required_write_order: CompletionWriteOrder = .information_then_status;

/// Whether a proposed write order is the safe one.
pub fn isSafeWriteOrder(order: CompletionWriteOrder) bool {
    return order == required_write_order;
}

// ---------------------------------------------------------------------------
// Bounds
// ---------------------------------------------------------------------------

/// Completion packets a port will hold before a post must block.
pub const max_pending_completions: u32 = 256;
/// Open file objects the kernel will track.
pub const max_open_files: u32 = 1024;

/// The disc sector size every unbuffered read must be a multiple of.
///
/// A title reading with `FILE_NO_INTERMEDIATE_BUFFERING` must present an
/// aligned offset and length. An unaligned request is refused by the hardware,
/// not silently rounded, so a runtime that rounds it hands back data from the
/// wrong place.
pub const disc_sector_bytes: u32 = 2048;

pub fn isSectorAligned(value: u64) bool {
    return value % disc_sector_bytes == 0;
}

pub const CompletionPacket = struct {
    /// The key the title associated with the handle at registration.
    completion_key: u32 = 0,
    /// The guest address of the overlapped structure.
    overlapped_address: u32 = 0,
    bytes_transferred: u32 = 0,
    status: Status = status_success,
};

pub fn contractIsWellFormed() bool {
    if (isComplete(status_pending)) return false;
    if (isError(status_pending)) return false;
    if (!isError(status_end_of_file)) return false;
    if (@sizeOf(IoStatusBlock) != 8) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "pending is a success code that does not mean complete" {
    // The single misreading behind reads of uninitialised buffers: a sign or
    // severity test says "success", so the caller reads a buffer the kernel
    // has not filled yet.
    try std.testing.expectEqual(@as(Status, 0x0000_0103), status_pending);
    try std.testing.expectEqual(Severity.success, severityOf(status_pending));
    try std.testing.expect(!isError(status_pending));
    // ...and yet:
    try std.testing.expect(!isComplete(status_pending));
}

test "completion is tested by inequality with pending, not by severity" {
    // Every other status, error or not, means the operation finished.
    try std.testing.expect(isComplete(status_success));
    try std.testing.expect(isComplete(status_end_of_file));
    try std.testing.expect(isComplete(status_cancelled));
    try std.testing.expect(isComplete(status_invalid_handle));
    try std.testing.expect(isComplete(status_timeout));
    try std.testing.expect(!isComplete(status_pending));
}

test "severity comes from the top two bits" {
    try std.testing.expectEqual(Severity.success, severityOf(status_success));
    try std.testing.expectEqual(Severity.@"error", severityOf(status_end_of_file));
    try std.testing.expectEqual(Severity.@"error", severityOf(status_invalid_handle));
    try std.testing.expectEqual(Severity.@"error", severityOf(status_cancelled));
    // 0x40000000 is informational, 0x80000000 is a warning. Neither is an
    // error, and code that tests only the high bit conflates the two.
    try std.testing.expectEqual(Severity.informational, severityOf(0x4000_0000));
    try std.testing.expectEqual(Severity.warning, severityOf(0x8000_0000));
    try std.testing.expect(!isError(0x8000_0000));
}

test "a fresh status block reads as pending" {
    // The default matters: a zero-initialised block would read as
    // STATUS_SUCCESS with zero bytes, which a title takes as a completed
    // empty read rather than an operation in flight.
    const block = IoStatusBlock{};
    try std.testing.expectEqual(status_pending, block.status);
    try std.testing.expect(!block.isComplete());

    const finished = IoStatusBlock{ .status = status_success, .information = 4096 };
    try std.testing.expect(finished.isComplete());
    try std.testing.expectEqual(@as(u32, 4096), finished.information);
}

test "information is written before status" {
    // The ordering rule, as a checkable value rather than a comment. The
    // reverse order lets a title observe completion and then read a stale
    // byte count, which presents as a short read.
    try std.testing.expect(isSafeWriteOrder(.information_then_status));
    try std.testing.expect(!isSafeWriteOrder(.status_then_information));
    try std.testing.expectEqual(CompletionWriteOrder.information_then_status, required_write_order);
}

test "the status block layout is the ABI the guest reads" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(IoStatusBlock, "status"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(IoStatusBlock, "information"));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(IoStatusBlock));
}

test "unbuffered reads are sector aligned" {
    // 2048, the DVD sector. Rounding an unaligned request instead of refusing
    // it returns data from the wrong offset.
    try std.testing.expectEqual(@as(u32, 2048), disc_sector_bytes);
    try std.testing.expect(isSectorAligned(0));
    try std.testing.expect(isSectorAligned(2048));
    try std.testing.expect(isSectorAligned(4096));
    try std.testing.expect(!isSectorAligned(1));
    try std.testing.expect(!isSectorAligned(512));
    try std.testing.expect(!isSectorAligned(2047));
}

test "the bounds are the ones the device tree publishes" {
    try std.testing.expectEqual(@as(u32, 256), max_pending_completions);
    try std.testing.expectEqual(@as(u32, 1024), max_open_files);
}
