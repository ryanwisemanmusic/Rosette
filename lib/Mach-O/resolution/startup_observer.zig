const std = @import("std");

pub const Phase = enum {
    execution,
    launch_arguments,
    logging,
    logging_ready,
};

pub const Snapshot = struct {
    step: u64,
    rip: u64,
    symbol: []const u8,
    symbol_offset: u64,
    heap_next: u64,
    import_calls: u64,
    fs_open: u64,
    fs_read: u64,
    fs_write: u64,
    heap_allocations: u64,
    heap_live: usize,
    options_seen: u64,
    options_kept: u64,
    options_skipped: u64,
    logging_lines: u64,
    pthread_created: u64,
    pthread_waits_collapsed: u64,
};

pub const Observer = struct {
    phase: Phase = .execution,
    phase_start_step: u64 = 0,
    checkpoints: u64 = 0,
    last_symbol: []const u8 = "<unknown>",
    same_symbol_checkpoints: u64 = 0,

    pub fn enter(self: *Observer, phase: Phase, step: u64) void {
        if (self.phase == phase) return;
        self.phase = phase;
        self.phase_start_step = step;
        self.last_symbol = "<unknown>";
        self.same_symbol_checkpoints = 0;
        std.debug.print("macho-processor: startup phase entered: {s} at step {d}\n", .{ @tagName(phase), step });
    }

    pub fn checkpoint(self: *Observer, snapshot: Snapshot) void {
        self.checkpoints +|= 1;
        if (std.mem.eql(u8, self.last_symbol, snapshot.symbol)) {
            self.same_symbol_checkpoints +|= 1;
        } else {
            self.last_symbol = snapshot.symbol;
            self.same_symbol_checkpoints = 1;
        }
        std.debug.print(
            "info(macho): startup phase={s} step={d} at {s}+0x{x} rip=0x{x} heap=0x{x} imports={d} fs(open/read/write)={d}/{d}/{d} guest-heap(alloc/live)={d}/{d} options(seen/kept/skipped)={d}/{d}/{d} logging(lines)={d} pthread(created/waits-collapsed)={d}/{d} same-symbol={d}\n",
            .{
                @tagName(self.phase),         snapshot.step,             snapshot.symbol,
                snapshot.symbol_offset,       snapshot.rip,              snapshot.heap_next,
                snapshot.import_calls,        snapshot.fs_open,          snapshot.fs_read,
                snapshot.fs_write,            snapshot.heap_allocations, snapshot.heap_live,
                snapshot.options_seen,        snapshot.options_kept,     snapshot.options_skipped,
                snapshot.logging_lines,       snapshot.pthread_created,  snapshot.pthread_waits_collapsed,
                self.same_symbol_checkpoints,
            },
        );
    }

    pub fn logSummary(self: *const Observer) void {
        std.debug.print(
            "macho-processor: startup observer: phase={s} checkpoints={d} phase_steps={d}\n",
            .{ @tagName(self.phase), self.checkpoints, self.phase_start_step },
        );
    }
};

test "observer tracks repeated checkpoint symbols" {
    var observer = Observer{};
    const snapshot = Snapshot{
        .step = 1,
        .rip = 0x1000,
        .symbol = "parse",
        .symbol_offset = 4,
        .heap_next = 0x2000,
        .import_calls = 3,
        .fs_open = 0,
        .fs_read = 0,
        .fs_write = 0,
        .heap_allocations = 0,
        .heap_live = 0,
        .options_seen = 0,
        .options_kept = 0,
        .options_skipped = 0,
        .logging_lines = 0,
        .pthread_created = 0,
        .pthread_waits_collapsed = 0,
    };
    observer.checkpoint(snapshot);
    observer.checkpoint(snapshot);
    try std.testing.expectEqual(@as(u64, 2), observer.same_symbol_checkpoints);
}
