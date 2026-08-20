//! What the memory behind a failed indirect call actually is.
//!
//! `call [rax+0x30]` loaded a non-executable address and the run stopped. The
//! diagnostics that follow dump the memory around the operand and call it a
//! "jump table", then note that every entry fits in 32 bits and offer to read
//! them as offsets. Both of those are guesses dressed as findings, and in the
//! observed crash both were wrong: the region was a **thread stack**, and the
//! entries that "fit in 32 bits" were return addresses into
//! `KernelState::ApplyTitleUpdate` and `~vector<XCONTENT_AGGREGATE_DATA>`.
//!
//! A reader given "corrupt jump table" goes looking for a bad relocation. The
//! actual question was whose stack it was and whether that frame was still
//! alive — which the run already had the evidence to answer, in the thread
//! census printed forty lines further down.
//!
//! So this classifies the region before describing it. Three shapes, and they
//! send an investigation to three different places:
//!
//!   * **A vtable.** Most slots resolve to executable code. One that does not
//!     is a corrupted slot, and the object's writer is the suspect.
//!   * **A thread stack.** The address lies inside a thread's stack window.
//!     Slots mixing return addresses with data pointers is what a live frame
//!     looks like, not what corruption looks like — so the question becomes
//!     *whose* frame and whether it outlived its owner.
//!   * **Plain data.** Neither; something called a pointer it read out of a
//!     buffer.
//!
//! ## Why the thread census is the decisive input
//!
//! An address is only "a stack" relative to a thread. The run tracks every
//! thread's stack pointer, so the answer is a comparison the diagnostics
//! already had every input for and never made. When the region belongs to a
//! thread *other* than the one that faulted, the finding writes itself: one
//! thread is calling through an object that lives in another thread's frame.

const std = @import("std");

/// How much address space above a thread's stack pointer still counts as that
/// thread's frame.
///
/// Stacks grow down, so live frames sit *above* the current pointer. A window
/// rather than an exact bound because the run records the pointer and not the
/// stack's base; too small a window misses the caller's frame, and too large
/// one claims unrelated heap. A megabyte is roughly a default thread stack and
/// errs toward claiming, which is the safe direction: a wrong "this is thread
/// N's stack" is corrected by the next line, and a missed one leaves the reader
/// with "corrupt jump table".
pub const stack_window_bytes: u64 = 1 << 20;

/// Slots examined around the operand when judging a region's shape.
pub const window_slots: usize = 16;

pub const RegionKind = enum(u8) {
    unknown,
    /// Most slots resolve to executable code.
    vtable,
    /// Inside a tracked thread's stack window.
    thread_stack,
    /// Mapped, and neither of the above.
    data,

    pub fn label(self: RegionKind) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .vtable => "vtable",
            .thread_stack => "thread_stack",
            .data => "data",
        };
    }

    pub fn meaning(self: RegionKind) []const u8 {
        return switch (self) {
            .unknown => "nothing is known about the memory behind the operand",
            .vtable => "most slots in this region resolve to executable code, so it really is a dispatch table and a slot that does not is a corrupted entry. The suspect is whatever last wrote the object",
            .thread_stack => "this address lies inside a tracked thread's stack window. Slots mixing return addresses with data pointers is what a live frame looks like, not what corruption looks like — so the question is whose frame it is and whether it outlived its owner, not which relocation went wrong",
            .data => "the region is mapped and looks like neither a dispatch table nor a stack frame. Something called a pointer it read out of a buffer",
        };
    }
};

pub const Finding = enum(u8) {
    /// Not enough information to classify.
    inconclusive,
    /// A dispatch table with one bad slot.
    vtable_slot_corrupted,
    /// The object lives in the stack of the thread that is calling. Normal
    /// C++ — a lambda on the stack — so the defect is the *contents*, not the
    /// location.
    own_stack_object,
    /// The object lives in the stack of a *different* thread. One thread is
    /// dispatching through another thread's frame, which is only safe while
    /// that frame is alive and is the classic dangling-callback shape.
    foreign_stack_object,
    /// Something called a pointer read out of ordinary data.
    data_called_as_code,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .inconclusive => "inconclusive",
            .vtable_slot_corrupted => "VTABLE_SLOT_CORRUPTED",
            .own_stack_object => "OWN_STACK_OBJECT",
            .foreign_stack_object => "FOREIGN_STACK_OBJECT",
            .data_called_as_code => "DATA_CALLED_AS_CODE",
        };
    }

    pub fn meaning(self: Finding) []const u8 {
        return switch (self) {
            .inconclusive => "the region could not be classified, so nothing here narrows the search",
            .vtable_slot_corrupted => "the region is a dispatch table and the slot called is not code. Look at what last wrote the object, not at the call site",
            .own_stack_object => "the object lives in the calling thread's own stack, which is ordinary for a callable held in a local. The location is fine and the contents are not, so the question is what overwrote the frame",
            .foreign_stack_object => "the object lives in a *different* thread's stack frame. One thread is dispatching through a callable owned by another thread's local, which is only valid while that frame is alive — and nothing here guarantees it is. This is the dangling-callback shape: find where the owning frame returns and whether it waits for this thread first",
            .data_called_as_code => "a pointer read out of ordinary data was called. Either the value was never a function pointer or the field it came from was overwritten",
        };
    }

    pub fn actionable(self: Finding) bool {
        return self != .inconclusive;
    }
};

/// A thread's stack, as the run knows it.
pub const ThreadStack = struct {
    handle: u64 = 0,
    stack_pointer: u64 = 0,

    /// Whether an address is inside this thread's live frames. Stacks grow
    /// down, so a live frame is at or above the current pointer.
    pub fn contains(self: ThreadStack, address: u64) bool {
        if (self.stack_pointer == 0 or address < self.stack_pointer) return false;
        return address - self.stack_pointer <= stack_window_bytes;
    }
};

/// One slot of the region, already resolved by the caller.
pub const Slot = struct {
    address: u64 = 0,
    value: u64 = 0,
    /// Whether the value resolves to a known code symbol.
    resolves_to_code: bool = false,
    /// Whether the value points at memory marked executable.
    executable: bool = false,
};

pub const Audit = struct {
    kind: RegionKind = .unknown,
    finding: Finding = .inconclusive,
    /// The thread whose stack the region belongs to, when it belongs to one.
    owning_thread: u64 = 0,
    /// The thread that executed the failed call.
    faulting_thread: u64 = 0,
    code_slots: u32 = 0,
    data_slots: u32 = 0,
    examined_slots: u32 = 0,

    /// Proportion of examined slots that resolve to code, in percent.
    pub fn codeSlotPercent(self: Audit) u32 {
        if (self.examined_slots == 0) return 0;
        return self.code_slots * 100 / self.examined_slots;
    }
};

/// Proportion of code-resolving slots above which a region is a dispatch table.
/// Not a majority: a vtable's trailing slots are frequently null or padding,
/// and demanding most of them would classify every real vtable as data.
pub const vtable_code_percent: u32 = 40;

/// Classify the memory behind a failed indirect call.
///
/// `stacks` is the thread census. Its presence is what turns "corrupt jump
/// table" into "thread 0x…'s frame", and its absence is why the previous
/// diagnostic could not tell them apart.
pub fn classify(
    operand_address: u64,
    slots: []const Slot,
    stacks: []const ThreadStack,
    faulting_thread: u64,
    target_executable: bool,
) Audit {
    var audit = Audit{ .faulting_thread = faulting_thread };
    for (slots) |slot| {
        if (slot.address == 0) continue;
        audit.examined_slots += 1;
        if (slot.resolves_to_code and slot.executable) {
            audit.code_slots += 1;
        } else {
            audit.data_slots += 1;
        }
    }

    // The stack test runs first and wins. An address inside a live frame is a
    // stack frame whatever its slots happen to look like — and a frame full of
    // return addresses looks exactly like a partly-populated dispatch table,
    // which is the confusion this ordering exists to prevent.
    for (stacks) |stack| {
        if (!stack.contains(operand_address)) continue;
        audit.kind = .thread_stack;
        audit.owning_thread = stack.handle;
        audit.finding = if (stack.handle == faulting_thread)
            .own_stack_object
        else
            .foreign_stack_object;
        return audit;
    }

    if (audit.examined_slots == 0) return audit;
    if (audit.codeSlotPercent() >= vtable_code_percent) {
        audit.kind = .vtable;
        audit.finding = if (target_executable) .inconclusive else .vtable_slot_corrupted;
        return audit;
    }
    audit.kind = .data;
    audit.finding = if (target_executable) .inconclusive else .data_called_as_code;
    return audit;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn codeSlot(address: u64, value: u64) Slot {
    return .{ .address = address, .value = value, .resolves_to_code = true, .executable = true };
}

fn dataSlot(address: u64, value: u64) Slot {
    return .{ .address = address, .value = value };
}

// The observed crash. The region is a thread stack and the previous diagnostic
// called it a corrupt jump table, which sends a reader looking for a bad
// relocation.
test "a region inside another thread's stack is named as the dangling-callback shape" {
    // Slots as the run dumped them: return addresses interleaved with heap
    // pointers, which is what a live frame looks like.
    const slots = [_]Slot{
        dataSlot(0x1b386d70, 0x1b386f20),
        codeSlot(0x1b386d78, 0x6acef1),
        dataSlot(0x1b386d80, 0x1b386da0),
        codeSlot(0x1b386d88, 0x55b9c5),
        dataSlot(0x1b386d90, 0x67c01a0),
        dataSlot(0x1b386d98, 0x1b386eb0),
        dataSlot(0x1b386da0, 0x1b386f20),
        codeSlot(0x1b386da8, 0x6ad7f2),
    };
    // Thread 0x7fff20e0 was parked with its stack pointer just below the region.
    const stacks = [_]ThreadStack{
        .{ .handle = 0x7fff20e0, .stack_pointer = 0x1b385f60 },
        .{ .handle = 0x7fff21b0, .stack_pointer = 0x2585abc0 },
    };

    const audit = classify(0x1b386da0, &slots, &stacks, 0x7fff21b0, false);
    try std.testing.expectEqual(RegionKind.thread_stack, audit.kind);
    try std.testing.expectEqual(Finding.foreign_stack_object, audit.finding);
    try std.testing.expectEqual(@as(u64, 0x7fff20e0), audit.owning_thread);
    try std.testing.expect(audit.finding.actionable());
    try std.testing.expect(std.mem.indexOf(u8, audit.finding.meaning(), "dangling-callback") != null);
}

// A callable held in a local is ordinary C++. The location is fine; the
// contents are the question.
test "a region in the faulting thread's own stack is not blamed on its location" {
    const slots = [_]Slot{ dataSlot(0x2585ab00, 0x1234), codeSlot(0x2585ab08, 0x6acef1) };
    const stacks = [_]ThreadStack{.{ .handle = 0x7fff21b0, .stack_pointer = 0x2585aa00 }};
    const audit = classify(0x2585ab00, &slots, &stacks, 0x7fff21b0, false);
    try std.testing.expectEqual(Finding.own_stack_object, audit.finding);
    try std.testing.expectEqual(@as(u64, 0x7fff21b0), audit.owning_thread);
    try std.testing.expect(std.mem.indexOf(u8, audit.finding.meaning(), "location is fine") != null);
}

test "a region of code pointers is a dispatch table with one bad slot" {
    const slots = [_]Slot{
        codeSlot(0x400000, 0x401000), codeSlot(0x400008, 0x401100),
        codeSlot(0x400010, 0x401200), dataSlot(0x400018, 0x9999),
        codeSlot(0x400020, 0x401300), codeSlot(0x400028, 0x401400),
    };
    const audit = classify(0x400018, &slots, &.{}, 1, false);
    try std.testing.expectEqual(RegionKind.vtable, audit.kind);
    try std.testing.expectEqual(Finding.vtable_slot_corrupted, audit.finding);
    try std.testing.expect(audit.codeSlotPercent() >= vtable_code_percent);
    try std.testing.expect(std.mem.indexOf(u8, audit.finding.meaning(), "not at the call site") != null);
}

// Stacks grow down, so a live frame is above the pointer. An address below it
// belongs to nobody.
test "an address below a thread's stack pointer is not in its frames" {
    const stack = ThreadStack{ .handle = 1, .stack_pointer = 0x2000 };
    try std.testing.expect(!stack.contains(0x1FFF));
    try std.testing.expect(stack.contains(0x2000));
    try std.testing.expect(stack.contains(0x2000 + stack_window_bytes));
    try std.testing.expect(!stack.contains(0x2000 + stack_window_bytes + 1));
    // A thread with no recorded pointer claims nothing.
    try std.testing.expect(!(ThreadStack{ .handle = 1 }).contains(0x2000));
}

// A frame full of return addresses looks exactly like a partly-populated
// dispatch table, so the stack test has to win.
test "the stack test outranks the slot-shape test" {
    const slots = [_]Slot{
        codeSlot(0x1000, 0x401000), codeSlot(0x1008, 0x401100),
        codeSlot(0x1010, 0x401200), codeSlot(0x1018, 0x401300),
    };
    // Without a census this is a vtable.
    try std.testing.expectEqual(RegionKind.vtable, classify(0x1000, &slots, &.{}, 1, false).kind);
    // With one, it is a frame.
    const stacks = [_]ThreadStack{.{ .handle = 7, .stack_pointer = 0x800 }};
    try std.testing.expectEqual(RegionKind.thread_stack, classify(0x1000, &slots, &stacks, 1, false).kind);
}

test "data called as code is its own finding" {
    const slots = [_]Slot{
        dataSlot(0x800000, 0x11), dataSlot(0x800008, 0x22),
        dataSlot(0x800010, 0x33), dataSlot(0x800018, 0x44),
    };
    const audit = classify(0x800000, &slots, &.{}, 1, false);
    try std.testing.expectEqual(RegionKind.data, audit.kind);
    try std.testing.expectEqual(Finding.data_called_as_code, audit.finding);
    try std.testing.expectEqual(@as(u32, 0), audit.codeSlotPercent());
}

// A vtable's trailing slots are frequently null or padding, so demanding a
// majority would classify every real dispatch table as data.
test "a partly populated dispatch table is still a dispatch table" {
    const slots = [_]Slot{
        codeSlot(0x400000, 0x401000), codeSlot(0x400008, 0x401100),
        dataSlot(0x400010, 0),        dataSlot(0x400018, 0),
        dataSlot(0x400020, 0),
    };
    try std.testing.expectEqual(RegionKind.vtable, classify(0x400000, &slots, &.{}, 1, false).kind);
}

test "an executable target is not accused of anything" {
    const slots = [_]Slot{ codeSlot(0x400000, 0x401000), codeSlot(0x400008, 0x401100) };
    const audit = classify(0x400000, &slots, &.{}, 1, true);
    try std.testing.expectEqual(Finding.inconclusive, audit.finding);
    try std.testing.expect(!audit.finding.actionable());
}

test "no slots and no census concludes nothing rather than guessing" {
    const audit = classify(0x1000, &.{}, &.{}, 1, false);
    try std.testing.expectEqual(RegionKind.unknown, audit.kind);
    try std.testing.expectEqual(Finding.inconclusive, audit.finding);
    inline for (.{ RegionKind.unknown, RegionKind.vtable, RegionKind.thread_stack, RegionKind.data }) |kind| {
        try std.testing.expect(kind.label().len > 0);
        try std.testing.expect(kind.meaning().len > 40);
    }
    inline for (.{
        Finding.inconclusive, Finding.vtable_slot_corrupted, Finding.own_stack_object,
        Finding.foreign_stack_object, Finding.data_called_as_code,
    }) |finding| {
        try std.testing.expect(finding.label().len > 0);
        try std.testing.expect(finding.meaning().len > 40);
    }
}
