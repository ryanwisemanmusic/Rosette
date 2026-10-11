//! A causal snapshot of the GPU ring at a stopped title frame. A PAUSE in an
//! unrelated timer thread must not be treated as proof of a lost GPU wake.
//! Only a ring with unconsumed work, or a worker pointer behind the published
//! pointer, is eligible for the harmless wake assist.
const std = @import("std");

pub const Snapshot = struct {
    frame: u64,
    guest_write: u64,
    read: u64,
    worker_write: u64,
    ring_dwords: u64,
    fence: u32,
    kicks: u64,
    interrupt_dpcs: u64,

    pub fn pending(self: Snapshot) u64 {
        if (self.ring_dwords == 0) return 0;
        return (self.guest_write +% self.ring_dwords -% self.read) % self.ring_dwords;
    }

    pub fn needsWorkerWake(self: Snapshot) bool {
        return self.pending() != 0 or
            (self.ring_dwords != 0 and self.worker_write % self.ring_dwords != self.guest_write);
    }
};

pub const Verdict = enum {
    ring_has_work,
    worker_pointer_behind,
    ring_drained_fence_advancing,
    ring_drained_new_kicks_no_fence,
    ring_drained_no_new_submission,
    ring_drained_first_sample,
};

pub fn classify(current: Snapshot, previous: ?Snapshot) Verdict {
    if (current.pending() != 0) return .ring_has_work;
    if (current.needsWorkerWake()) return .worker_pointer_behind;
    const before = previous orelse return .ring_drained_first_sample;
    if (before.frame != current.frame) return .ring_drained_first_sample;
    if (current.fence != before.fence) return .ring_drained_fence_advancing;
    if (current.kicks != before.kicks) return .ring_drained_new_kicks_no_fence;
    return .ring_drained_no_new_submission;
}

test "an empty ring with no new fence or kick is a producer stall" {
    const first = Snapshot{ .frame = 776, .guest_write = 0xd9b, .read = 0xd9b, .worker_write = 0xd9b, .ring_dwords = 8192, .fence = 3445, .kicks = 3812, .interrupt_dpcs = 5000 };
    var later = first;
    later.interrupt_dpcs += 1200; // Vblank continues independently.
    try std.testing.expectEqual(Verdict.ring_drained_no_new_submission, classify(later, first));
    try std.testing.expect(!later.needsWorkerWake());
    later.read -= 3;
    try std.testing.expectEqual(Verdict.ring_has_work, classify(later, first));
    try std.testing.expect(later.needsWorkerWake());
}

test "a new frame is a new stall episode" {
    const first = Snapshot{ .frame = 754, .guest_write = 0x383, .read = 0x383, .worker_write = 0x383, .ring_dwords = 8192, .fence = 3025, .kicks = 3024, .interrupt_dpcs = 3917 };
    var later = first;
    later.frame = 776;
    try std.testing.expectEqual(Verdict.ring_drained_first_sample, classify(later, first));
}
