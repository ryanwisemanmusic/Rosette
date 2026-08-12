//! Xenon — the Xbox 360 CPU.
//!
//! Three PowerPC cores, two hardware threads each, big-endian, 32-bit guest
//! address space. The facts below are the ones a dynamic binary translator has
//! to agree with; the rest of the part's specification is not Rosette's
//! business and is deliberately absent.
//!
//! Every constraint here was previously discovered as a fault:
//!
//!   * the guest page is 4 KiB and the host's is 16 KiB, so protecting one
//!     guest page necessarily protects three neighbours;
//!   * guest pointers are 32-bit, so a 64-bit value whose low half is a guest
//!     address is either canonical or not a pointer at all;
//!   * guest memory is big-endian, so every load and store across the boundary
//!     converts exactly once;
//!   * the first 64 KiB is reserved and the title protects it deliberately, so
//!     a fault there is a null dereference and never a mapping bug.
//!
//! Each of those cost a debugging session. Written down, they are questions the
//! runtime can ask before acting instead of conclusions it reaches afterwards.

const std = @import("std");
const constraint = @import("../constraint.zig");

pub const name = "Xenon";
pub const architecture = "PowerPC 64-bit (32-bit guest address space)";

pub const core_count: u32 = 3;
pub const threads_per_core: u32 = 2;
pub const logical_processor_count: u32 = core_count * threads_per_core;
pub const clock_hz: u64 = 3_200_000_000;

/// Guest memory is big-endian. The single most expensive fact in this file:
/// a missed conversion produces the right value in the wrong order, which is
/// decidable but only if something is checking.
pub const guest_byte_order: std.builtin.Endian = .big;

/// The base page the guest's virtual heaps are managed in. A host with larger
/// pages cannot express a protection at this granularity, which is a runtime
/// concern and not a guest one.
pub const guest_page_size: u64 = 4096;

/// The physical heaps use 64 KiB pages. Allocation granularity, not protection
/// granularity.
pub const physical_page_size: u64 = 64 * 1024;

/// Guest pointers are 32 bits. A 64-bit register holding one is zero- or
/// sign-extended; anything else is a host pointer that happens to alias.
pub const guest_pointer_bits: u6 = 32;

/// The title reserves the first 64 KiB and protects it with no access, so a
/// dereference there is a null pointer plus an offset. Faults in this range are
/// never a mapping defect.
pub const reserved_low_range_end: u64 = 0x1_0000;

pub const cache_line_bytes: u64 = 128;

/// Whether a 64-bit value could be a guest pointer at all.
pub fn isCanonicalGuestPointer(value: u64) bool {
    const high: u32 = @truncate(value >> 32);
    return high == 0 or high == 0xFFFF_FFFF;
}

/// Whether a guest address lies in the range the title reserves and protects.
pub fn isReservedLowAddress(guest_address: u64) bool {
    return guest_address < reserved_low_range_end;
}

/// Can the host enforce a protection at this granularity, or will it
/// necessarily affect neighbouring guest pages?
pub fn checkProtectionGranularity(host_page_size: u64) constraint.Check {
    if (host_page_size == 0) return constraint.unconstrained("protection-granularity");
    if (host_page_size <= guest_page_size) return constraint.permitted("protection-granularity");
    return constraint.violation(
        "protection-granularity",
        "the host page is larger than Xenon's 4 KiB guest page, so protecting one guest page also protects its neighbours. A refusal at a neighbour is the runtime's granularity, not the guest's intent, and must be classified as such rather than delivered as a guest fault",
    );
}

/// What a fault at this guest address means, given the hardware.
pub fn checkFaultAddress(guest_address: u64) constraint.Check {
    if (isReservedLowAddress(guest_address)) {
        return constraint.violation(
            "reserved-low-range",
            "Xenon titles reserve and protect the first 64 KiB, so this is a null pointer dereference in guest code. The mapping is correct and the pointer is the finding — do not make the page readable",
        );
    }
    return constraint.unconstrained("reserved-low-range");
}

/// A value that is not a guest pointer but whose byte reversal is has crossed
/// the endian boundary an even number of times — zero or two.
pub fn checkPointerByteOrder(value: u64) constraint.Check {
    if (value == 0) return constraint.unconstrained("guest-byte-order");
    if (!isCanonicalGuestPointer(value)) {
        const reversed = @byteSwap(value);
        if (isCanonicalGuestPointer(reversed) and reversed != 0) {
            return constraint.violation(
                "guest-byte-order",
                "this value is not a canonical guest pointer but its byte reversal is. Guest memory is big-endian and the conversion happens exactly once at the boundary; a value in the wrong order crossed it zero times or twice",
            );
        }
    }
    return constraint.permitted("guest-byte-order");
}

test "the reserved low range is stated, not guessed at" {
    try std.testing.expect(isReservedLowAddress(0));
    try std.testing.expect(isReservedLowAddress(1));
    try std.testing.expect(isReservedLowAddress(0xFFFF));
    try std.testing.expect(!isReservedLowAddress(0x1_0000));

    // The observed fault: guest address 0x1, one byte, refused.
    const check = checkFaultAddress(1);
    try std.testing.expect(!check.ruling.allowed());
    try std.testing.expect(std.mem.indexOf(u8, check.detail, "do not make the page readable") != null);
}

test "a 16 KiB host page cannot enforce a 4 KiB guest protection" {
    const check = checkProtectionGranularity(16384);
    try std.testing.expect(!check.ruling.allowed());
    try std.testing.expectEqualStrings("protection-granularity", check.rule);

    try std.testing.expect(checkProtectionGranularity(4096).ruling.allowed());
    try std.testing.expectEqual(constraint.Ruling.unconstrained, checkProtectionGranularity(0).ruling);
}

test "canonical form separates a guest pointer from a host one that aliases" {
    try std.testing.expect(isCanonicalGuestPointer(0x8258_a4a0));
    try std.testing.expect(isCanonicalGuestPointer(0xFFFF_FFFF_8258_a4a0));
    // A real 64-bit host pointer whose low half lands in the guest range.
    try std.testing.expect(!isCanonicalGuestPointer(0x1_0825_8a4a0));
}

// The defect that cost six passes, expressed as a question the hardware answers.
test "a byte-reversed guest pointer contradicts the endian contract" {
    const check = checkPointerByteOrder(0x3883_1982_0000_0000);
    try std.testing.expect(!check.ruling.allowed());
    try std.testing.expectEqualStrings("guest-byte-order", check.rule);

    // A correct pointer, and an unrelated value, are both fine.
    try std.testing.expect(checkPointerByteOrder(0x8219_8338).ruling.allowed());
    try std.testing.expect(checkPointerByteOrder(0x1234_5678_9abc_def0).ruling.allowed());
}

test "logical processor count follows from the core topology" {
    try std.testing.expectEqual(@as(u32, 6), logical_processor_count);
}
