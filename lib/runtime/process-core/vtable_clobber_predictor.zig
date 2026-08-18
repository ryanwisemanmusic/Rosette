//! VTABLE CLOBBER PREDICTOR — decide whether restoring a trusted vptr is a
//! repair or a corruption, before the write happens.
//!
//! The write-time vptr guard restores a trusted vtable pointer whenever a store
//! clears a tracked slot inside a live allocation. That is correct for a heap
//! object whose header was damaged, and it is *the opposite of correct* when
//! the tracked slot is not an object at all — because the restore is itself a
//! store, and Rosette performs it into memory the guest is actively using.
//!
//! The failure this module exists for, observed end to end:
//!
//!   1. A stack slot transiently held a vtable pointer (a spilled `this`, a
//!      temporary, a copied vptr), and the allocation map reported a live block
//!      covering it, so the tracker established a record there.
//!   2. Thousands of steps later a completely unrelated function reused that
//!      stack depth. `fmt::detail::digits2` stored the character `'0'` into
//!      what the tracker still believed was `xe::vfs::NullFile`'s vptr.
//!   3. The guard "restored" `__ZTVN2xe3vfs8NullFileE+0x10` on top of it.
//!   4. `fmt::detail::do_format_decimal` loaded that value as its own output
//!      cursor and stored through it. The run died writing to `0x1019839a6` —
//!      the restored vtable address point, minus the two bytes the formatter
//!      had already walked back. Rosette's repair was the crash.
//!
//! Two behavioural predicates separate the two cases. Neither knows anything
//! about a program, a symbol or an address range:
//!
//!   * **Active frame.** The slot lies inside the live stack frame of the
//!     thread performing the write. Nothing that is inside the frame the CPU is
//!     executing in is an object with a lifetime worth preserving — it is
//!     scratch that the current call owns. Caught on the first event.
//!   * **Restore churn.** The same slot has already been restored several
//!     times and the guest keeps storing different non-vtable values into it.
//!     A real vptr is written once at construction and once per base-class
//!     transition; storage that is rewritten on a loop is live scratch. Caught
//!     after a bounded number of events, for whatever the frame test misses
//!     (another thread's stack, a pooled buffer).
//!
//! Refusing is strictly safer than restoring. A refused slot keeps whatever the
//! guest wrote — which is what the guest wanted — and if the storage really did
//! belong to an object, the *read* side still repairs it at the next virtual
//! call through `assessLowRead`. That moment carries better evidence than write
//! time does (a real dispatch, not a store that merely looked like a clear), so
//! the degradation is graceful in the one direction that matters.
//!
//! Cost: nothing on any hot path. `assess` is reached only from the
//! `trusted_value_cleared` branch of the write guard, which fired twelve times
//! in a three-billion-step run. The predicate itself is four comparisons.

const std = @import("std");
const machoCapturePrint = @import("dyld").event_log.machoCapturePrint;

/// SysV AMD64 leaf functions may use 128 bytes below RSP without adjusting it.
/// A store there is as much "inside the live frame" as one above RSP.
pub const RED_ZONE: u64 = 128;

/// How far above RSP a plausible frame pointer may sit. Beyond this, RBP is
/// holding something else (it is a general-purpose register in frame-pointer-
/// omitted code) and must not be used to size the frame.
pub const MAX_FRAME_SPAN: u64 = 1 << 20;

/// Frame window used when RBP is not a plausible frame pointer. One page is
/// larger than the overwhelming majority of frames and small enough that a
/// heap object a page above the stack pointer is not swept up by it.
pub const DEFAULT_FRAME_WINDOW: u64 = 0x1000;

/// Restores permitted on one slot before the slot is judged to be live scratch.
/// Three is enough to let a genuinely damaged object be repaired more than once
/// (a repeated bulk write over the same header) without letting a formatting
/// loop be fought indefinitely.
pub const MAX_RESTORES_PER_SLOT: u32 = 3;

pub const SITE_CAPACITY: usize = 32;
pub const MAX_EMISSIONS_PER_SITE: u32 = 3;

pub const Verdict = enum {
    /// A genuine clobber of a live object: perform the restore.
    restore,
    /// The slot is inside the writing thread's live stack frame.
    refuse_active_frame,
    /// The slot has been restored repeatedly and keeps being rewritten.
    refuse_restore_churn,

    pub fn refused(self: Verdict) bool {
        return self != .restore;
    }

    pub fn reason(self: Verdict) []const u8 {
        return switch (self) {
            .restore => "live_object_clobber",
            .refuse_active_frame => "slot_is_inside_the_writers_live_stack_frame",
            .refuse_restore_churn => "slot_rewritten_after_repeated_restores",
        };
    }
};

/// Is `address` inside the live stack frame of a thread stopped at `rsp`/`rbp`?
///
/// Kept pure and separate from the table so the judgement can be tested without
/// a machine state: this single predicate is what decides whether Rosette
/// writes into memory the guest owns, and it is the part that can be wrong in a
/// way no compiler catches.
pub fn withinActiveFrame(rsp: u64, rbp: u64, address: u64) bool {
    if (rsp == 0) return false;
    const low = rsp -| RED_ZONE;
    // RBP bounds the frame only when it looks like a frame pointer for this
    // RSP. Frame-pointer-omitted code leaves arbitrary values in RBP, and
    // trusting one of those would stretch "the frame" across unrelated memory.
    const high = if (rbp > rsp and rbp - rsp <= MAX_FRAME_SPAN)
        rbp +| 16
    else
        rsp +| DEFAULT_FRAME_WINDOW;
    return address >= low and address < high;
}

const Site = struct {
    valid: bool = false,
    slot: u64 = 0,
    owner_base: u64 = 0,
    expected_vptr: u64 = 0,
    first_writer_rip: u64 = 0,
    last_writer_rip: u64 = 0,
    /// Whether more than one distinct instruction has clobbered this slot. Two
    /// writers on one slot is the signature of reused storage rather than of
    /// one buggy memcpy.
    multiple_writers: bool = false,
    first_observed: u64 = 0,
    last_observed: u64 = 0,
    /// Whether the values stored over the "vptr" have differed. Identical
    /// values every time is consistent with one repeated clear; differing
    /// values are consistent with live data being written.
    observed_varies: bool = false,
    restores: u32 = 0,
    refusals: u32 = 0,
    events: u32 = 0,
    emissions: u32 = 0,
    thread: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    /// Sticky: once a slot is judged scratch it stays judged, so a later event
    /// that happens to miss the frame test cannot re-authorise a restore.
    condemned: bool = false,
    condemned_by: Verdict = .restore,
};

pub const Predictor = struct {
    sites: [SITE_CAPACITY]Site = [_]Site{.{}} ** SITE_CAPACITY,
    distinct_sites: u32 = 0,
    events: u64 = 0,
    restores_allowed: u64 = 0,
    refused_active_frame: u64 = 0,
    refused_restore_churn: u64 = 0,
    /// Sites the table could not hold. Reported so an empty-looking dump is
    /// never mistaken for "this did not happen".
    dropped_sites: u64 = 0,
    emissions: u64 = 0,

    /// Judge one write-time clobber. Call before performing the restore; the
    /// caller owns the store and must skip it when the verdict is refused.
    ///
    /// `rsp`/`rbp` are the registers of the *writing* instruction, which is
    /// what makes the frame test meaningful: the question is whether the store
    /// landed in the frame its own function owns.
    pub fn assess(
        self: *Predictor,
        slot: u64,
        owner_base: u64,
        expected_vptr: u64,
        observed: u64,
        writer_rip: u64,
        rsp: u64,
        rbp: u64,
        step: u64,
        thread: u64,
    ) Verdict {
        self.events +|= 1;
        const site = self.findOrInsert(slot) orelse {
            // No slot to record in. Judge on the frame test alone rather than
            // defaulting to a restore: a table that is full must not become a
            // reason to write into a live frame.
            self.dropped_sites +|= 1;
            if (withinActiveFrame(rsp, rbp, slot)) {
                self.refused_active_frame +|= 1;
                return .refuse_active_frame;
            }
            self.restores_allowed +|= 1;
            return .restore;
        };

        if (site.events == 0) {
            site.owner_base = owner_base;
            site.expected_vptr = expected_vptr;
            site.first_writer_rip = writer_rip;
            site.first_observed = observed;
            site.first_step = step;
            site.thread = thread;
        } else {
            if (site.last_writer_rip != writer_rip) site.multiple_writers = true;
            if (site.last_observed != observed) site.observed_varies = true;
        }
        site.last_writer_rip = writer_rip;
        site.last_observed = observed;
        site.last_step = step;
        site.events +|= 1;

        const verdict = self.judge(site, rsp, rbp);
        switch (verdict) {
            .restore => {
                site.restores +|= 1;
                self.restores_allowed +|= 1;
            },
            .refuse_active_frame => {
                site.refusals +|= 1;
                self.refused_active_frame +|= 1;
            },
            .refuse_restore_churn => {
                site.refusals +|= 1;
                self.refused_restore_churn +|= 1;
            },
        }
        if (verdict.refused() and !site.condemned) {
            site.condemned = true;
            site.condemned_by = verdict;
        }
        if (verdict.refused() and site.emissions < MAX_EMISSIONS_PER_SITE) {
            site.emissions +|= 1;
            self.emit(site, verdict, rsp, rbp);
        }
        return verdict;
    }

    fn judge(self: *Predictor, site: *const Site, rsp: u64, rbp: u64) Verdict {
        _ = self;
        if (site.condemned) return site.condemned_by;
        if (withinActiveFrame(rsp, rbp, site.slot)) return .refuse_active_frame;
        // Churn only condemns once the slot has actually been repaired the
        // permitted number of times *and* the guest keeps putting something
        // different back. Identical repeated values are a repeating clear,
        // which is the case the guard was written for.
        if (site.restores >= MAX_RESTORES_PER_SLOT and site.observed_varies) {
            return .refuse_restore_churn;
        }
        return .restore;
    }

    fn emit(self: *Predictor, site: *const Site, verdict: Verdict, rsp: u64, rbp: u64) void {
        self.emissions +|= 1;
        machoCapturePrint(
            "VTABLE CLOBBER PREDICTOR: action=refuse_restore reason={s} slot=0x{x} owner_base=0x{x} expected=0x{x} observed=0x{x} writer=0x{x} multiple_writers={} observed_varies={} events={d} prior_restores={d} rsp=0x{x} rbp=0x{x} thread=0x{x} step={d}; the tracked slot is live scratch, not an object header — restoring would store 0x{x} into memory the writer owns, and predicted=the writer reloads it as its own datum and faults at or just below 0x{x}. The record is retired so the slot stops being defended\n",
            .{
                verdict.reason(),
                site.slot,
                site.owner_base,
                site.expected_vptr,
                site.last_observed,
                site.last_writer_rip,
                site.multiple_writers,
                site.observed_varies,
                site.events,
                site.restores,
                rsp,
                rbp,
                site.thread,
                site.last_step,
                site.expected_vptr,
                site.expected_vptr,
            },
        );
    }

    /// Every judged slot, for the exit summary. Mirrors the near-null
    /// predictor's dump so the two read the same way.
    pub fn dump(self: *const Predictor, reason: []const u8) void {
        var retained: usize = 0;
        for (&self.sites) |*site| {
            if (!site.valid) continue;
            retained += 1;
            machoCapturePrint(
                "VTABLE CLOBBER PREDICTOR: site slot=0x{x} owner_base=0x{x} expected=0x{x} verdict={s} events={d} restores={d} refusals={d} multiple_writers={} observed_varies={} first_observed=0x{x} last_observed=0x{x} first_writer=0x{x} last_writer=0x{x} thread=0x{x} steps=[{d}..{d}]\n",
                .{
                    site.slot,
                    site.owner_base,
                    site.expected_vptr,
                    if (site.condemned) site.condemned_by.reason() else Verdict.restore.reason(),
                    site.events,
                    site.restores,
                    site.refusals,
                    site.multiple_writers,
                    site.observed_varies,
                    site.first_observed,
                    site.last_observed,
                    site.first_writer_rip,
                    site.last_writer_rip,
                    site.thread,
                    site.first_step,
                    site.last_step,
                },
            );
        }
        machoCapturePrint(
            "VTABLE CLOBBER PREDICTOR: dump reason={s} distinct={d} retained={d} events={d} restores_allowed={d} refused(active_frame/restore_churn)={d}/{d} dropped_sites={d} emissions={d}; a refused restore is Rosette declining to write a vtable pointer into memory the guest owns — the read side still repairs the slot at the next virtual call if it really was an object\n",
            .{
                reason,
                self.distinct_sites,
                retained,
                self.events,
                self.restores_allowed,
                self.refused_active_frame,
                self.refused_restore_churn,
                self.dropped_sites,
                self.emissions,
            },
        );
    }

    fn findOrInsert(self: *Predictor, slot: u64) ?*Site {
        var index: usize = @intCast(hashSlot(slot) % SITE_CAPACITY);
        var first_empty: ?usize = null;
        var probes: usize = 0;
        while (probes < SITE_CAPACITY) : (probes += 1) {
            const site = &self.sites[index];
            if (!site.valid) {
                if (first_empty == null) first_empty = index;
                break;
            }
            if (site.slot == slot) return site;
            index = (index + 1) % SITE_CAPACITY;
        }
        const slot_index = first_empty orelse return null;
        self.sites[slot_index] = .{ .valid = true, .slot = slot };
        self.distinct_sites +|= 1;
        return &self.sites[slot_index];
    }

    fn hashSlot(slot: u64) u64 {
        var mixed = slot >> 3;
        mixed ^= mixed >> 33;
        mixed *%= 0xff51afd7ed558ccd;
        mixed ^= mixed >> 33;
        return mixed;
    }
};

test "a store inside the writer's own frame is never an object header" {
    // The observed geometry: `mov [rbp-8], reg` with rbp two words above rsp.
    try std.testing.expect(withinActiveFrame(0x18d39c50, 0x18d39ca0, 0x18d39c38));
    try std.testing.expect(withinActiveFrame(0x18d39c50, 0x18d39ca0, 0x18d39c98));
    // A deep local: RequestPaint stored at rbp-0x280.
    try std.testing.expect(withinActiveFrame(0x18d3a700, 0x18d3aa50, 0x18d3a7d0));
    // The red zone below RSP still belongs to the frame.
    try std.testing.expect(withinActiveFrame(0x18d39c50, 0x18d39ca0, 0x18d39be0));
    // Far below the red zone is not this frame.
    try std.testing.expect(!withinActiveFrame(0x18d39c50, 0x18d39ca0, 0x18d39000));
    // Above the frame pointer is the caller's frame, not this one.
    try std.testing.expect(!withinActiveFrame(0x18d39c50, 0x18d39ca0, 0x18d3b000));
}

test "an implausible RBP does not stretch the frame across unrelated memory" {
    // Frame-pointer-omitted code leaves arbitrary values in RBP. A heap object
    // must not become "the current frame" because RBP happened to point past
    // it, so the window falls back to a page above RSP.
    const rsp: u64 = 0x18d39c50;
    const nonsense_rbp: u64 = 0x7fff_0000_0000;
    try std.testing.expect(withinActiveFrame(rsp, nonsense_rbp, rsp + 0x40));
    try std.testing.expect(!withinActiveFrame(rsp, nonsense_rbp, rsp + 0x8000));
    // RBP below RSP is not a frame pointer either.
    try std.testing.expect(!withinActiveFrame(rsp, rsp - 0x100, rsp + 0x8000));
    // A thread with no stack pointer yields no frame at all.
    try std.testing.expect(!withinActiveFrame(0, 0x1000, 0x1000));
}

test "the active-frame verdict lands on the first event and sticks" {
    var predictor = Predictor{};
    const slot: u64 = 0x18d39c38;
    const verdict = predictor.assess(
        slot,
        0x18d39bb0,
        0x19839a8,
        0x30,
        0xdc584,
        0x18d39c50,
        0x18d39c40,
        3_016_191_374,
        0x7fff20e0,
    );
    try std.testing.expectEqual(Verdict.refuse_active_frame, verdict);
    try std.testing.expect(verdict.refused());
    try std.testing.expectEqual(@as(u64, 1), predictor.refused_active_frame);
    try std.testing.expectEqual(@as(u64, 0), predictor.restores_allowed);

    // A later event on the same slot from a frame that no longer covers it
    // must not re-authorise the restore: the slot was already judged scratch.
    const again = predictor.assess(
        slot,
        0x18d39bb0,
        0x19839a8,
        0x22,
        0xdc584,
        0x1000_0000,
        0x1000_1000,
        3_016_191_414,
        0x7fff20e0,
    );
    try std.testing.expectEqual(Verdict.refuse_active_frame, again);
    try std.testing.expectEqual(@as(u64, 2), predictor.refused_active_frame);
}

test "a genuine heap clobber is still restored, repeatedly if the value is stable" {
    var predictor = Predictor{};
    // A heap object nowhere near the writer's stack, cleared to zero each time
    // by the same writer — the case the write-time guard exists for.
    const slot: u64 = 0x1720_4320;
    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        const verdict = predictor.assess(
            slot,
            slot,
            0x1983888,
            0,
            0x9376c9,
            0x1b38_2c60,
            0x1b38_2c80,
            69_921_602 + i,
            0x7fff20e0,
        );
        try std.testing.expectEqual(Verdict.restore, verdict);
    }
    try std.testing.expectEqual(@as(u64, 6), predictor.restores_allowed);
    try std.testing.expectEqual(@as(u64, 0), predictor.refused_active_frame);
    try std.testing.expectEqual(@as(u64, 0), predictor.refused_restore_churn);
}

test "restore churn condemns a slot the guest keeps rewriting with new values" {
    var predictor = Predictor{};
    const slot: u64 = 0x2000_0000;
    // Off-frame, so only churn can catch it. Distinct values every time.
    const observed = [_]u64{ 0x30, 0x22, 0xa73, 0x41, 0x5c, 0x7 };
    var allowed: u32 = 0;
    for (observed, 0..) |value, index| {
        const verdict = predictor.assess(
            slot,
            slot,
            0x19839a8,
            value,
            0xdc584,
            0x1000_0000,
            0x1000_1000,
            3_000_000_000 + index,
            0x7fff20e0,
        );
        if (verdict == .restore) allowed += 1;
    }
    try std.testing.expectEqual(MAX_RESTORES_PER_SLOT, allowed);
    try std.testing.expect(predictor.refused_restore_churn > 0);
}

test "a full site table still refuses a write into the writer's live frame" {
    // Losing the table must never become permission to corrupt a live frame:
    // the frame test does not need a record to be correct.
    var predictor = Predictor{};
    var i: u64 = 0;
    while (i < SITE_CAPACITY) : (i += 1) {
        _ = predictor.assess(0x3000_0000 + i * 8, 0, 0x19839a8, 0, 0x1000, 0x9000_0000, 0x9000_1000, i, 1);
    }
    try std.testing.expectEqual(@as(u32, @intCast(SITE_CAPACITY)), predictor.distinct_sites);

    const overflow = predictor.assess(
        0x18d39c38,
        0x18d39bb0,
        0x19839a8,
        0x30,
        0xdc584,
        0x18d39c50,
        0x18d39c40,
        1,
        1,
    );
    try std.testing.expectEqual(Verdict.refuse_active_frame, overflow);
    try std.testing.expectEqual(@as(u64, 1), predictor.dropped_sites);
}
