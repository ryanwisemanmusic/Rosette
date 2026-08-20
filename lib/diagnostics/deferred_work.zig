//! Work that was put off, and the small subset of it that later becomes a
//! crash.
//!
//! Deferral is normal and mostly healthy. Threads are created suspended and
//! started later; functions are compiled the first time they are called;
//! imports bind lazily. A run performs thousands of deferrals and almost all of
//! them are simply how the system works, so a diagnostic that reports deferrals
//! is a diagnostic nobody can read.
//!
//! One shape is different, and it is the one that kills runs:
//!
//!   1. Something is deferred **because it failed**. The failure is recorded,
//!      the work is abandoned, and execution continues.
//!   2. Much later, something *demands* the result.
//!   3. The demand finds nothing, and the caller — which has no error path,
//!      because the thing was supposed to exist — dereferences null.
//!
//! The two events are separated by billions of steps and by several
//! subsystems, so the crash is attributed to the demander. It belongs to the
//! failure. The observed run is exactly this: a guest function's code
//! generation threw, the function was "left undefined", and four thousand steps
//! later `ResolveFunction` asserted on a null and took the process down.
//!
//! ## The prediction
//!
//! At step 1 the outcome is not yet decided: the host retries a failed
//! translation once at the first demand, so a transient codegen failure (an
//! Xbyak error while finalizing label relocations, say) can still recover.
//! Only a second failure is a latent fatal defect whose trigger is "somebody
//! calls this". That is worth saying *then*, while the failure is still on
//! screen with its reason attached, rather than at the null dereference where
//! none of that context survives.
//!
//! ## What is deliberately not reported
//!
//! A deferral that was never demanded is not a problem and never appears as
//! one. A deferral that succeeded and was demanded is the system working. Only
//! failures, and only failures that something actually needed, are findings.

const std = @import("std");

/// What was deferred. Kinds exist because the remedy differs completely, not
/// to decorate the log.
pub const Kind = enum(u8) {
    unknown,
    /// Translation of a guest function into host code.
    guest_function_codegen,
    /// A guest thread created but not yet started.
    guest_thread_start,
    /// An import left unbound until first use.
    import_binding,
    /// A module load postponed.
    module_load,
    /// A resource the graphics path will need.
    graphics_resource,

    pub fn label(self: Kind) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .guest_function_codegen => "guest_function_codegen",
            .guest_thread_start => "guest_thread_start",
            .import_binding => "import_binding",
            .module_load => "module_load",
            .graphics_resource => "graphics_resource",
        };
    }

    /// What a demand for a failed item of this kind does to the caller.
    pub fn consequence(self: Kind) []const u8 {
        return switch (self) {
            .unknown => "the demander receives nothing and behaves as its own error handling allows",
            .guest_function_codegen => "the resolver returns a null function pointer and its caller — which has no error path, because a demanded function is supposed to exist — dereferences it. The crash lands in the resolver and belongs to the code generation that failed. The first demand now re-attempts the translation once, so only a second failure reaches the dereference",
            .guest_thread_start => "a thread that was never started is joined or signalled, and whatever waits on it waits forever",
            .import_binding => "a call goes through an unbound slot to an address nobody wrote",
            .module_load => "a lookup into a module that was never mapped returns nothing and the caller proceeds as though it did",
            .graphics_resource => "the graphics path proceeds with a resource handle that refers to nothing",
        };
    }
};

/// Why the work is outstanding. The distinction between these two is the whole
/// module: one will complete on demand, the other never will.
pub const Disposition = enum(u8) {
    /// Postponed and expected to complete when demanded. Healthy.
    postponed,
    /// Attempted and failed. The first demand re-attempts the translation
    /// once; a second failure is fatal because nothing re-attempts a failed
    /// retry.
    failed,
    /// Completed. Retained so a demand can be told apart from a demand for
    /// something that never existed.
    completed,

    pub fn label(self: Disposition) []const u8 {
        return switch (self) {
            .postponed => "postponed",
            .failed => "FAILED",
            .completed => "completed",
        };
    }
};

pub const Finding = enum(u8) {
    /// Nothing outstanding has been demanded.
    quiet = 0,
    /// Failures exist and nothing has demanded them yet. Latent: the outcome is
    /// already decided and the trigger has not happened.
    latent_failure = 1,
    /// Something demanded work that had failed. This is a crash that has either
    /// happened or is about to.
    failed_then_demanded = 2,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .quiet => "quiet",
            .latent_failure => "LATENT_FAILURE",
            .failed_then_demanded => "FAILED_THEN_DEMANDED",
        };
    }

    pub fn meaning(self: Finding) []const u8 {
        return switch (self) {
            .quiet => "every deferral either completed or has not been needed. Deferral on its own is how the system works and is not reported as a problem",
            .latent_failure => "work failed and was abandoned, and nothing has demanded it yet. The first demand re-attempts the translation once, so a transient codegen failure can still recover; only a second failure is a decided crash. The reason is attached below while it is still recoverable — at the demand site none of this context survives",
            .failed_then_demanded => "something demanded work that had already failed. The demander has no error path, because the thing it asked for was supposed to exist, so this is where the run dies — and the defect is the failure, not the demand. Read the recorded reason, not the crash site",
        };
    }
};

pub const max_items = 32;

pub const Item = struct {
    /// Identity of the work: a guest address, a handle, an ordinal.
    id: u64 = 0,
    kind: Kind = .unknown,
    disposition: Disposition = .postponed,
    deferred_step: u64 = 0,
    demanded_step: u64 = 0,
    demands: u64 = 0,
    /// A short reason captured at failure time. Fixed storage: the reason is
    /// worth carrying to the demand site and not worth an allocator.
    reason_storage: [96]u8 = [_]u8{0} ** 96,
    reason_length: u8 = 0,

    pub fn reason(self: *const Item) []const u8 {
        return self.reason_storage[0..self.reason_length];
    }

    /// Whether this item is a crash that has already been triggered.
    pub fn fatal(self: Item) bool {
        return self.disposition == .failed and self.demands != 0;
    }

    /// Whether this item is a crash waiting for its trigger.
    pub fn latent(self: Item) bool {
        return self.disposition == .failed and self.demands == 0;
    }
};

pub const Ledger = struct {
    items: [max_items]Item = [_]Item{.{}} ** max_items,
    count: usize = 0,
    /// Items past capacity. Failures evict postponed entries rather than being
    /// dropped, because a postponed entry is the one that does not matter.
    dropped: u64 = 0,
    total_deferrals: u64 = 0,
    total_failures: u64 = 0,
    total_demands: u64 = 0,
    /// Demands for work no deferral covers. Not a finding on its own — most
    /// demands are for things that were never deferred — but a rising count
    /// alongside a stalled run says the table is missing the deferrals.
    demands_without_record: u64 = 0,

    fn find(self: *Ledger, id: u64) ?*Item {
        for (self.items[0..self.count]) |*item| {
            if (item.id == id) return item;
        }
        return null;
    }

    fn insert(self: *Ledger, id: u64) ?*Item {
        if (self.count < max_items) {
            const item = &self.items[self.count];
            item.* = .{ .id = id };
            self.count += 1;
            return item;
        }
        // Full. Evict a completed or postponed entry — never a failure, which
        // is the only kind that can still take the run down.
        for (self.items[0..self.count]) |*item| {
            if (item.disposition != .failed) {
                self.dropped +|= 1;
                item.* = .{ .id = id };
                return item;
            }
        }
        self.dropped +|= 1;
        return null;
    }

    pub fn noteDeferred(self: *Ledger, id: u64, kind: Kind, step: u64) void {
        if (id == 0) return;
        self.total_deferrals +|= 1;
        const item = self.find(id) orelse self.insert(id) orelse return;
        item.kind = kind;
        item.disposition = .postponed;
        item.deferred_step = step;
    }

    /// Record that deferred work was attempted and failed. The reason is
    /// captured here because this is the only place it exists.
    pub fn noteFailed(self: *Ledger, id: u64, kind: Kind, reason: []const u8, step: u64) void {
        if (id == 0) return;
        self.total_failures +|= 1;
        const item = self.find(id) orelse self.insert(id) orelse return;
        item.kind = kind;
        item.disposition = .failed;
        item.deferred_step = step;
        const length = @min(reason.len, item.reason_storage.len);
        @memcpy(item.reason_storage[0..length], reason[0..length]);
        item.reason_length = @intCast(length);
    }

    pub fn noteCompleted(self: *Ledger, id: u64, step: u64) void {
        if (id == 0) return;
        const item = self.find(id) orelse return;
        item.disposition = .completed;
        item.deferred_step = step;
    }

    /// Something asked for the result. Returns the item when the demand is for
    /// work that failed, which is the caller's cue to report a fatal finding
    /// while it still has the context.
    pub fn noteDemanded(self: *Ledger, id: u64, step: u64) ?Item {
        if (id == 0) return null;
        self.total_demands +|= 1;
        const item = self.find(id) orelse {
            self.demands_without_record +|= 1;
            return null;
        };
        item.demands +|= 1;
        item.demanded_step = step;
        return if (item.disposition == .failed) item.* else null;
    }

    /// A demand that does not carry the identity of what it wanted.
    ///
    /// The emulator's resolver asserts on a null function pointer without
    /// naming the address it was resolving, so the demand and the failure
    /// cannot be joined by identity. They can be joined by *kind*: if exactly
    /// one item of this kind has failed, the attribution is unambiguous, and if
    /// several have, they are all suspects and the report says so rather than
    /// picking one.
    ///
    /// Returns the number of latent failures of this kind, and marks them
    /// demanded so the finding escalates.
    pub fn noteUnaddressedDemand(self: *Ledger, kind: Kind, step: u64) u32 {
        self.total_demands +|= 1;
        var suspects: u32 = 0;
        for (self.items[0..self.count]) |*item| {
            if (item.kind != kind or item.disposition != .failed) continue;
            item.demands +|= 1;
            item.demanded_step = step;
            suspects += 1;
        }
        if (suspects == 0) self.demands_without_record +|= 1;
        return suspects;
    }

    /// Whether an unaddressed demand can be attributed to exactly one failure.
    pub fn unambiguousSuspect(self: *const Ledger, kind: Kind) ?Item {
        var found: ?Item = null;
        for (self.items[0..self.count]) |item| {
            if (item.kind != kind or item.disposition != .failed) continue;
            if (found != null) return null;
            found = item;
        }
        return found;
    }

    pub fn latentCount(self: *const Ledger) u32 {
        var count: u32 = 0;
        for (self.items[0..self.count]) |item| {
            if (item.latent()) count += 1;
        }
        return count;
    }

    pub fn fatalCount(self: *const Ledger) u32 {
        var count: u32 = 0;
        for (self.items[0..self.count]) |item| {
            if (item.fatal()) count += 1;
        }
        return count;
    }

    /// The item a reader should look at first, if any.
    pub fn worst(self: *const Ledger) ?Item {
        var chosen: ?Item = null;
        for (self.items[0..self.count]) |item| {
            if (item.fatal()) return item;
            if (item.latent() and chosen == null) chosen = item;
        }
        return chosen;
    }

    pub fn finding(self: *const Ledger) Finding {
        if (self.fatalCount() != 0) return .failed_then_demanded;
        if (self.latentCount() != 0) return .latent_failure;
        return .quiet;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Deferral is how the system works. Reporting it makes the diagnostic
// unreadable and buries the one shape that matters.
test "a healthy deferral is never reported as a problem" {
    var ledger = Ledger{};
    ledger.noteDeferred(0x1000, .guest_thread_start, 10);
    ledger.noteDeferred(0x2000, .guest_function_codegen, 20);
    try std.testing.expectEqual(Finding.quiet, ledger.finding());

    // Demanded and satisfied is still healthy.
    ledger.noteCompleted(0x2000, 30);
    try std.testing.expect(ledger.noteDemanded(0x2000, 40) == null);
    try std.testing.expectEqual(Finding.quiet, ledger.finding());
    try std.testing.expect(ledger.worst() == null);
    try std.testing.expect(std.mem.indexOf(u8, Finding.quiet.meaning(), "not reported as a problem") != null);
}

// The observed run: code generation threw, the function was left undefined, and
// the crash arrived four thousand steps later in a different subsystem.
test "a failure is predicted as latent before anything demands it" {
    var ledger = Ledger{};
    ledger.noteFailed(0x826D0D80, .guest_function_codegen, "Xbyak error 11: label is not found", 4548004449);

    try std.testing.expectEqual(Finding.latent_failure, ledger.finding());
    try std.testing.expectEqual(@as(u32, 1), ledger.latentCount());
    try std.testing.expectEqual(@as(u32, 0), ledger.fatalCount());
    const item = ledger.worst().?;
    try std.testing.expect(item.latent());
    try std.testing.expectEqualStrings("Xbyak error 11: label is not found", item.reason());
    try std.testing.expect(std.mem.indexOf(u8, Finding.latent_failure.meaning(), "re-attempts the translation once") != null);
    try std.testing.expect(std.mem.indexOf(u8, Finding.latent_failure.meaning(), "decided crash") != null);
}

test "a demand for failed work returns the failure with its original reason" {
    var ledger = Ledger{};
    ledger.noteFailed(0x826D0D80, .guest_function_codegen, "Xbyak error 11: label is not found", 4548004449);
    const fatal = ledger.noteDemanded(0x826D0D80, 4548008892).?;

    try std.testing.expectEqual(Finding.failed_then_demanded, ledger.finding());
    try std.testing.expectEqual(@as(u32, 1), ledger.fatalCount());
    try std.testing.expectEqual(@as(u32, 0), ledger.latentCount());
    // The reason survives the four-thousand-step gap, which is the point.
    try std.testing.expectEqualStrings("Xbyak error 11: label is not found", fatal.reason());
    try std.testing.expectEqual(@as(u64, 4548004449), fatal.deferred_step);
    try std.testing.expectEqual(@as(u64, 4548008892), fatal.demanded_step);
    try std.testing.expect(std.mem.indexOf(u8, Kind.guest_function_codegen.consequence(), "belongs to the code generation") != null);
}

test "a fatal item outranks a latent one in what to read first" {
    var ledger = Ledger{};
    ledger.noteFailed(0x1000, .guest_function_codegen, "first", 10);
    ledger.noteFailed(0x2000, .import_binding, "second", 20);
    try std.testing.expectEqual(@as(u64, 0x1000), ledger.worst().?.id);

    _ = ledger.noteDemanded(0x2000, 30);
    try std.testing.expectEqual(@as(u64, 0x2000), ledger.worst().?.id);
    try std.testing.expect(ledger.worst().?.fatal());
}

// A failure is the only entry that can still take the run down, so a full table
// must never evict one to make room for a postponed entry.
test "a full table evicts healthy entries and never a failure" {
    var ledger = Ledger{};
    ledger.noteFailed(0xFEED, .guest_function_codegen, "kept", 1);
    var index: u64 = 1;
    while (index < max_items) : (index += 1) ledger.noteDeferred(index, .guest_thread_start, index);
    try std.testing.expectEqual(@as(usize, max_items), ledger.count);

    // Pushing more in evicts postponed entries.
    ledger.noteDeferred(0xAAAA, .guest_thread_start, 100);
    ledger.noteDeferred(0xBBBB, .guest_thread_start, 101);
    try std.testing.expect(ledger.dropped >= 2);

    // The failure survived and is still findable with its reason.
    const fatal = ledger.noteDemanded(0xFEED, 200).?;
    try std.testing.expectEqualStrings("kept", fatal.reason());
}

test "a demand for work nothing deferred is counted and is not a finding" {
    var ledger = Ledger{};
    try std.testing.expect(ledger.noteDemanded(0x9999, 10) == null);
    try std.testing.expectEqual(@as(u64, 1), ledger.demands_without_record);
    try std.testing.expectEqual(Finding.quiet, ledger.finding());
}

test "a reason longer than the storage is truncated rather than refused" {
    var ledger = Ledger{};
    const long = "x" ** 300;
    ledger.noteFailed(0x1000, .guest_function_codegen, long, 1);
    const item = ledger.worst().?;
    try std.testing.expectEqual(@as(usize, 96), item.reason().len);
    try std.testing.expect(item.latent());
}

// A retry that succeeds must clear the prediction, or a recovered run reports a
// crash that will never happen.
test "work that failed and then completed is no longer a finding" {
    var ledger = Ledger{};
    ledger.noteFailed(0x1000, .guest_function_codegen, "transient", 10);
    try std.testing.expectEqual(Finding.latent_failure, ledger.finding());
    ledger.noteCompleted(0x1000, 20);
    try std.testing.expectEqual(Finding.quiet, ledger.finding());
    try std.testing.expect(ledger.noteDemanded(0x1000, 30) == null);
}

test "identity zero is ignored so an unknown address cannot become an entry" {
    var ledger = Ledger{};
    ledger.noteDeferred(0, .guest_function_codegen, 1);
    ledger.noteFailed(0, .guest_function_codegen, "nowhere", 1);
    try std.testing.expect(ledger.noteDemanded(0, 1) == null);
    try std.testing.expectEqual(@as(usize, 0), ledger.count);
}

// The resolver asserts without naming the address it wanted, so the demand and
// the failure can only be joined by kind — and the report has to say whether
// that attribution is unambiguous.
test "an unaddressed demand attributes to a single failure when there is only one" {
    var ledger = Ledger{};
    ledger.noteFailed(0x826D0D80, .guest_function_codegen, "Xbyak error 11", 100);

    const suspect = ledger.unambiguousSuspect(.guest_function_codegen).?;
    try std.testing.expectEqual(@as(u64, 0x826D0D80), suspect.id);

    try std.testing.expectEqual(@as(u32, 1), ledger.noteUnaddressedDemand(.guest_function_codegen, 200));
    try std.testing.expectEqual(Finding.failed_then_demanded, ledger.finding());
    try std.testing.expectEqual(@as(u64, 200), ledger.worst().?.demanded_step);
}

test "several failures of one kind are all suspects rather than one being picked" {
    var ledger = Ledger{};
    ledger.noteFailed(0x1000, .guest_function_codegen, "first", 10);
    ledger.noteFailed(0x2000, .guest_function_codegen, "second", 20);
    try std.testing.expect(ledger.unambiguousSuspect(.guest_function_codegen) == null);
    try std.testing.expectEqual(@as(u32, 2), ledger.noteUnaddressedDemand(.guest_function_codegen, 30));
    try std.testing.expectEqual(@as(u32, 2), ledger.fatalCount());
}

test "an unaddressed demand with no matching failure is not a finding" {
    var ledger = Ledger{};
    ledger.noteDeferred(0x1000, .guest_function_codegen, 10);
    try std.testing.expectEqual(@as(u32, 0), ledger.noteUnaddressedDemand(.guest_function_codegen, 20));
    try std.testing.expectEqual(Finding.quiet, ledger.finding());
    try std.testing.expectEqual(@as(u64, 1), ledger.demands_without_record);
}

test "every kind and finding explains its consequence" {
    inline for (.{
        Kind.unknown, Kind.guest_function_codegen, Kind.guest_thread_start,
        Kind.import_binding, Kind.module_load, Kind.graphics_resource,
    }) |kind| {
        try std.testing.expect(kind.label().len > 0);
        try std.testing.expect(kind.consequence().len > 40);
    }
    inline for (.{ Finding.quiet, Finding.latent_failure, Finding.failed_then_demanded }) |finding| {
        try std.testing.expect(finding.label().len > 0);
        try std.testing.expect(finding.meaning().len > 40);
    }
    inline for (.{ Disposition.postponed, Disposition.failed, Disposition.completed }) |disposition| {
        try std.testing.expect(disposition.label().len > 0);
    }
}
