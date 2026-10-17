//! Route-independent: guest thread creation parameters and the hardware
//! thread topology a title sees.
//!
//! ## Why the stack floor is a fact and not a detail
//!
//! A title may request any stack size, including zero. The kernel silently
//! raises anything below 16 KiB to 16 KiB. A runtime that honours the request
//! literally gives a thread a stack too small to hold a single PPC frame, and
//! what follows is a stack overflow into whatever was allocated below it —
//! reported, if at all, as memory corruption in an unrelated subsystem.
//!
//! Silently raising is the *correct* behaviour, which is exactly why it needs
//! writing down: a runtime that instead refuses the small request breaks a
//! title that was relying on the clamp.
//!
//! ## Six logical processors, and they are not interchangeable
//!
//! The Xenon has three cores of two hardware threads. A title pins work to
//! specific processors, and hardware thread 0 of each core has different cache
//! behaviour from thread 1. Rosette does not have to reproduce the timing, but
//! it does have to reproduce the *count*: a title that asks for processor 4 and
//! is told it does not exist will fall back to a path it never tests.
//!
//! ## What this package is not
//!
//! * It is not a scheduler. It runs nothing and parks nothing.
//! * It holds no thread. Ids, stacks and priorities of live threads are
//!   `lib/scheduler/`'s.
//! * It does not create threads. The host thread that backs a guest thread is
//!   an effect.

const std = @import("std");

/// The smallest stack the kernel will give a thread, whatever it was asked for.
pub const minimum_stack_bytes: u32 = 16 * 1024;

/// The host stack Xenia allocates behind a guest thread. Much larger than the
/// guest's, because host frames for translated code are wider.
pub const host_stack_bytes: u32 = 16 * 1024 * 1024;

/// Apply the kernel's stack clamp.
///
/// Raising rather than refusing. A title that asks for 4 KiB is relying on
/// this, and refusing the request breaks it.
pub fn clampStackSize(requested: u32) u32 {
    return @max(requested, minimum_stack_bytes);
}

// ---------------------------------------------------------------------------
// Topology
// ---------------------------------------------------------------------------

pub const core_count: u32 = 3;
pub const threads_per_core: u32 = 2;
pub const logical_processor_count: u32 = core_count * threads_per_core;

/// The core a logical processor belongs to.
pub fn coreOf(processor: u32) ?u32 {
    if (processor >= logical_processor_count) return null;
    return processor / threads_per_core;
}

/// The hardware thread within its core.
pub fn hardwareThreadOf(processor: u32) ?u32 {
    if (processor >= logical_processor_count) return null;
    return processor % threads_per_core;
}

pub fn isLogicalProcessor(processor: u32) bool {
    return processor < logical_processor_count;
}

/// The affinity mask bit for a logical processor.
pub fn affinityBit(processor: u32) u8 {
    if (!isLogicalProcessor(processor)) return 0;
    return @as(u8, 1) << @intCast(processor);
}

/// Every processor.
pub const affinity_any: u8 = 0x3F;

// ---------------------------------------------------------------------------
// Creation flags
// ---------------------------------------------------------------------------

/// Create the thread suspended.
pub const create_suspended: u32 = 0x0000_0001;
/// Raise the thread's priority. Xenia reads bit 5 for this.
pub const create_elevated_priority: u32 = 0x0000_0020;

pub fn isCreatedSuspended(flags: u32) bool {
    return flags & create_suspended != 0;
}

pub fn isElevatedPriority(flags: u32) bool {
    return flags & create_elevated_priority != 0;
}

// ---------------------------------------------------------------------------
// Priority
// ---------------------------------------------------------------------------

/// Guest priority is a signed increment around normal.
pub const priority_normal: i32 = 0;
pub const priority_lowest: i32 = -2;
pub const priority_highest: i32 = 2;
/// The value a title passes to run a thread only when nothing else can.
pub const priority_idle: i32 = -32;
pub const priority_time_critical: i32 = 32;

pub fn isPlausiblePriority(priority: i32) bool {
    return priority >= priority_idle and priority <= priority_time_critical;
}

/// Whether a priority would let this thread starve others.
///
/// A time-critical thread that spins never yields to the thread it is waiting
/// on. That is a livelock the scheduler cannot break, and it presents as a
/// hang with one thread at 100%.
pub fn canStarveOthers(priority: i32) bool {
    return priority >= priority_time_critical;
}

pub fn contractIsWellFormed() bool {
    if (logical_processor_count != 6) return false;
    if (clampStackSize(0) != minimum_stack_bytes) return false;
    if (affinity_any != 0x3F) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "a small stack request is raised, not refused" {
    // A title asking for 4 KiB is relying on the clamp; refusing breaks it,
    // and honouring it literally overflows into the allocation below.
    try std.testing.expectEqual(minimum_stack_bytes, clampStackSize(0));
    try std.testing.expectEqual(minimum_stack_bytes, clampStackSize(1));
    try std.testing.expectEqual(minimum_stack_bytes, clampStackSize(4096));
    try std.testing.expectEqual(minimum_stack_bytes, clampStackSize(minimum_stack_bytes));
    // A larger request is honoured unchanged.
    try std.testing.expectEqual(@as(u32, 64 * 1024), clampStackSize(64 * 1024));
    try std.testing.expectEqual(@as(u32, 1 << 20), clampStackSize(1 << 20));
}

test "the host stack is far larger than the guest's" {
    // Host frames for translated code are wider, so sizing the host stack
    // from the guest's request underflows on deep guest recursion.
    try std.testing.expect(host_stack_bytes > minimum_stack_bytes * 100);
    try std.testing.expectEqual(@as(u32, 16 * 1024 * 1024), host_stack_bytes);
}

test "six logical processors across three cores" {
    try std.testing.expectEqual(@as(u32, 6), logical_processor_count);
    try std.testing.expectEqual(@as(u32, 0), coreOf(0).?);
    try std.testing.expectEqual(@as(u32, 0), coreOf(1).?);
    try std.testing.expectEqual(@as(u32, 1), coreOf(2).?);
    try std.testing.expectEqual(@as(u32, 2), coreOf(5).?);
    try std.testing.expect(coreOf(6) == null);
}

test "hardware threads alternate within a core" {
    // Processor 0 and 1 share a core; 0 is thread 0 and 1 is thread 1. A
    // title pinning to "the second thread of core 0" means processor 1.
    try std.testing.expectEqual(@as(u32, 0), hardwareThreadOf(0).?);
    try std.testing.expectEqual(@as(u32, 1), hardwareThreadOf(1).?);
    try std.testing.expectEqual(@as(u32, 0), hardwareThreadOf(2).?);
    try std.testing.expectEqual(@as(u32, 1), hardwareThreadOf(5).?);
    try std.testing.expect(hardwareThreadOf(6) == null);
}

test "an out of range processor is refused rather than wrapped" {
    // Wrapping processor 6 to 0 silently co-schedules two threads a title
    // deliberately separated.
    try std.testing.expect(isLogicalProcessor(5));
    try std.testing.expect(!isLogicalProcessor(6));
    try std.testing.expect(!isLogicalProcessor(0xFFFF_FFFF));
    try std.testing.expectEqual(@as(u8, 0), affinityBit(6));
}

test "the affinity mask covers exactly six bits" {
    var mask: u8 = 0;
    var processor: u32 = 0;
    while (processor < logical_processor_count) : (processor += 1) {
        mask |= affinityBit(processor);
    }
    try std.testing.expectEqual(affinity_any, mask);
    try std.testing.expectEqual(@as(u8, 0x3F), mask);
    // The top two bits are not processors.
    try std.testing.expectEqual(@as(u8, 0), mask & 0xC0);
}

test "creation flags are read as bits, not as values" {
    try std.testing.expect(isCreatedSuspended(create_suspended));
    try std.testing.expect(!isCreatedSuspended(0));
    try std.testing.expect(isElevatedPriority(create_elevated_priority));
    try std.testing.expect(!isElevatedPriority(create_suspended));
    // Both together.
    const both = create_suspended | create_elevated_priority;
    try std.testing.expect(isCreatedSuspended(both));
    try std.testing.expect(isElevatedPriority(both));
}

test "a suspended thread is not a stalled one" {
    // Recorded because the two look identical from outside: a thread created
    // suspended and never resumed is the title's own doing, not a scheduler
    // failure, and blaming the scheduler for it wastes the search.
    try std.testing.expect(isCreatedSuspended(0x1));
    try std.testing.expect(!isCreatedSuspended(0x2));
}

test "priorities are signed increments around normal" {
    try std.testing.expectEqual(@as(i32, 0), priority_normal);
    try std.testing.expect(isPlausiblePriority(priority_normal));
    try std.testing.expect(isPlausiblePriority(priority_lowest));
    try std.testing.expect(isPlausiblePriority(priority_highest));
    try std.testing.expect(isPlausiblePriority(priority_idle));
    try std.testing.expect(isPlausiblePriority(priority_time_critical));
    try std.testing.expect(!isPlausiblePriority(33));
    try std.testing.expect(!isPlausiblePriority(-33));
}

test "a time critical thread can starve the thread it waits on" {
    // A livelock the scheduler cannot break: it presents as a hang with one
    // thread pinned at 100%, which reads as an infinite loop in that thread
    // rather than as a priority inversion.
    try std.testing.expect(canStarveOthers(priority_time_critical));
    try std.testing.expect(!canStarveOthers(priority_highest));
    try std.testing.expect(!canStarveOthers(priority_normal));
    try std.testing.expect(!canStarveOthers(priority_idle));
}
