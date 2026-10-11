//! Where the host thread that runs the guest spends its wall time.
//!
//! Every guest thread of a PE run is served by one host thread, so that
//! thread's time *is* the frame rate. The run log can count the things
//! Rosette knows it does - fallbacks, chain hops, Vulkan calls - but it
//! cannot say what share of the thread each of them costs, and every
//! optimisation until now was chosen from counts multiplied by guesses.
//!
//! This samples the thread's program counter from a second host thread, the
//! way `sample(1)` does: suspend it, read its register state, resume it. That
//! measures wall time rather than CPU time, so a thread blocked in a driver
//! wait or a kernel sleep is sampled where it is blocked, and it needs no
//! signal handler, so nothing it does can land inside the guest's own fault
//! handling. The sampler takes no lock and allocates nothing while the target
//! is suspended - it writes one entry of a table it alone owns - so it cannot
//! deadlock against anything the target was holding.
//!
//! Attribution is done at exit, by the caller: this module only records
//! program counters and link registers and names the image and symbol for an
//! address outside translated code.
//!
//! In a parallel PE run every guest thread has a host thread of its own, and
//! the owner (Xenia's UI thread) spends most of its life parked in
//! GetMessage: on 2026-09-26 its profile read 84% `__ulock_wait2` while the
//! title's threads - the ones deciding the frame rate - were never sampled.
//! Each worker therefore registers its host thread by guest slot, and every
//! tick samples it into a table of its own.

const std = @import("std");
const builtin = @import("builtin");

pub const supported = builtin.os.tag == .macos and builtin.cpu.arch == .aarch64;

pub const Entry = struct {
    pc: u64 = 0,
    /// The link register at the first sample of this pc. For a Rosette
    /// helper reached from translated code, it says which block called it.
    lr: u64 = 0,
    count: u32 = 0,
};

const table_bits = 16;
const table_len: usize = 1 << table_bits;
const table_mask: usize = table_len - 1;

const mach_port_t = std.c.mach_port_t;
extern "c" fn mach_thread_self() mach_port_t;
extern "c" fn thread_suspend(thread: mach_port_t) std.c.kern_return_t;

const ARM_THREAD_STATE64: c_int = 6;
/// `sizeof(arm_thread_state64_t) / sizeof(natural_t)`: x0-x28, fp, lr, sp,
/// pc, cpsr and a pad word.
const ARM_THREAD_STATE64_COUNT: u32 = 68;
const state_lr_index = 30;
const state_pc_index = 32;
/// User addresses fit in 47 bits; masking also drops any signing bits.
const address_mask: u64 = 0x0000_7FFF_FFFF_FFFF;

const Sampler = struct {
    table: [table_len]Entry = @splat(.{}),
    samples: u64 = 0,
    /// Samples whose pc found the table full.
    dropped: u64 = 0,
    /// Suspend or state reads that failed; the thread was not sampled.
    failures: u64 = 0,
    interval_ns: u64 = default_interval_ns,
    target: mach_port_t = 0,
    running: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    started_ns: u64 = 0,
    elapsed_ns: u64 = 0,
};

pub const default_interval_ns: u64 = 1_000_000;

var sampler: Sampler = .{};

/// Guest worker slots the sampler follows, one table each.
pub const max_workers: usize = 64;
/// The owner occupies the final slot in frame-window storage. Worker slots
/// retain their existing guest-slot indices.
pub const owner_frame_slot: usize = max_workers;
/// Keep the most recent host-side frame intervals. The profiler is opt-in,
/// and a fixed small ring avoids allocations while guest workers are live.
pub const frame_window_count: usize = 16;
/// A frame often samples many distinct PCs; the bounded histogram keeps the
/// hot entries and counts any tail it could not retain.
pub const frame_pc_capacity: usize = 24;
/// 2026-09-30: a 4096-entry table filled early in a 188 s run and dropped
/// 68% of Halo 3's main-thread samples - the code that ran after it filled,
/// which is the title's own translated code, was the part that went missing,
/// and the wall-time split printed beside it was computed from what was left.
/// A table is allocated per slot on first use, so 1.5 MiB is paid only by
/// slots that ran a thread.
const worker_table_bits = 16;
const worker_table_len: usize = 1 << worker_table_bits;

const WorkerTarget = struct {
    /// The worker's host thread while it runs, zero when none is registered.
    port: std.atomic.Value(mach_port_t) = .init(0),
    /// Guest thread occupying this worker slot. Zero for non-guest callers.
    guest_handle: std.atomic.Value(u64) = .init(0),
    samples: u64 = 0,
    dropped: u64 = 0,
    failures: u64 = 0,
    /// Published before the port, so the sampler never sees a registered
    /// thread without a table.
    table: std.atomic.Value(?[*]Entry) = .init(null),
};

var worker_targets: [max_workers]WorkerTarget = @splat(.{});

pub const FrameTotals = struct {
    epoch: u64,
    guest_handle: u64,
    mixed_guest_handles: bool,
    samples: u64,
    dropped: u64,
    failures: u64,
    distinct: usize,
};

const FrameBucket = struct {
    epoch: u64 = 0,
    guest_handle: u64 = 0,
    mixed_guest_handles: bool = false,
    samples: u64 = 0,
    dropped: u64 = 0,
    failures: u64 = 0,
    entries: [frame_pc_capacity]Entry = @splat(.{}),
};

var frame_epoch: std.atomic.Value(u64) = .init(0);
var frame_buckets: [max_workers + 1][frame_window_count]FrameBucket = @splat(@splat(.{}));

/// Follow the calling thread as guest worker `index` until it unregisters.
/// Samples accumulate per slot: a recycled slot keeps its predecessor's
/// samples, and the report names the slot's latest thread.
pub fn registerWorker(index: usize) void {
    registerWorkerWithGuestHandle(index, 0);
}

/// Follow a worker slot with the guest identity it currently executes. The
/// per-frame bucket marks intervals that cross a recycled guest slot.
pub fn registerWorkerWithGuestHandle(index: usize, guest_handle: u64) void {
    if (comptime !supported) return;
    if (index >= max_workers) return;
    const target = &worker_targets[index];
    if (target.table.load(.acquire) == null) {
        // Fresh pages are zero, which is an empty table.
        const table = std.heap.page_allocator.alloc(Entry, worker_table_len) catch return;
        target.table.store(table.ptr, .release);
    }
    target.guest_handle.store(guest_handle, .release);
    const previous = target.port.swap(mach_thread_self(), .acq_rel);
    if (previous != 0) _ = std.c.mach_port_deallocate(std.c.mach_task_self(), previous);
}

pub fn unregisterWorker(index: usize) void {
    if (comptime !supported) return;
    if (index >= max_workers) return;
    const previous = worker_targets[index].port.swap(0, .acq_rel);
    worker_targets[index].guest_handle.store(0, .release);
    if (previous != 0) _ = std.c.mach_port_deallocate(std.c.mach_task_self(), previous);
}

pub fn workerTotals(index: usize) Totals {
    const target = &worker_targets[index];
    var distinct: usize = 0;
    for (workerEntries(index)) |entry| {
        if (entry.count != 0) distinct += 1;
    }
    return .{
        .samples = target.samples,
        .dropped = target.dropped,
        .failures = target.failures,
        .interval_ns = sampler.interval_ns,
        .elapsed_ns = sampler.elapsed_ns,
        .distinct = distinct,
    };
}

/// One worker slot's sampled program counters. Read only after `stop`.
pub fn workerEntries(index: usize) []const Entry {
    const table = worker_targets[index].table.load(.acquire) orelse return &.{};
    return table[0..worker_table_len];
}

/// Start sampling the calling thread. Idempotent; false when this host
/// cannot sample or the sampler thread could not start.
pub fn startOnCurrentThread(interval_ns: u64) bool {
    if (comptime !supported) return false;
    if (sampler.running.load(.acquire)) return true;
    frame_epoch.store(0, .release);
    for (&frame_buckets) |*slots| @memset(slots, .{});
    sampler.target = mach_thread_self();
    sampler.interval_ns = @max(interval_ns, 100_000);
    sampler.started_ns = monotonicNanoseconds();
    sampler.running.store(true, .release);
    sampler.thread = std.Thread.spawn(.{ .stack_size = 64 * 1024 }, run, .{}) catch {
        sampler.running.store(false, .release);
        return false;
    };
    return true;
}

/// Stop sampling and wait for the sampler to finish its last sample.
pub fn stop() void {
    if (comptime !supported) return;
    if (!sampler.running.swap(false, .acq_rel)) return;
    if (sampler.thread) |thread| thread.join();
    sampler.thread = null;
    const now = monotonicNanoseconds();
    if (sampler.started_ns != 0 and now > sampler.started_ns) sampler.elapsed_ns = now - sampler.started_ns;
}

pub fn active() bool {
    return sampler.running.load(.acquire);
}

/// Advance the host sample epoch at a guest frame boundary and return the
/// interval that just ended. Zero denotes the first boundary, which is only
/// a baseline and has no complete preceding interval.
pub fn noteFrameBoundary() u64 {
    if (!active()) return 0;
    return frame_epoch.fetchAdd(1, .acq_rel);
}

/// Host PCs sampled during the requested frame interval. Call only after the
/// sampler has stopped; the sampler is the sole writer of these buckets.
pub fn frameEntries(slot: usize, epoch: u64) []const Entry {
    if (slot > owner_frame_slot or epoch == 0) return &.{};
    const bucket = &frame_buckets[slot][epoch % frame_window_count];
    if (bucket.epoch != epoch) return &.{};
    return &bucket.entries;
}

pub fn frameTotals(slot: usize, epoch: u64) FrameTotals {
    if (slot > owner_frame_slot or epoch == 0) return .{ .epoch = epoch, .guest_handle = 0, .mixed_guest_handles = false, .samples = 0, .dropped = 0, .failures = 0, .distinct = 0 };
    const bucket = &frame_buckets[slot][epoch % frame_window_count];
    if (bucket.epoch != epoch) return .{ .epoch = epoch, .guest_handle = 0, .mixed_guest_handles = false, .samples = 0, .dropped = 0, .failures = 0, .distinct = 0 };
    var distinct: usize = 0;
    for (bucket.entries) |entry| if (entry.count != 0) {
        distinct += 1;
    };
    return .{ .epoch = epoch, .guest_handle = bucket.guest_handle, .mixed_guest_handles = bucket.mixed_guest_handles, .samples = bucket.samples, .dropped = bucket.dropped, .failures = bucket.failures, .distinct = distinct };
}

/// Sampling suspends the owner and every registered worker to read host PCs,
/// so normal throughput runs leave the profiler off unless explicitly opted in.
pub fn enabledSetting(value: ?[]const u8) bool {
    const setting = value orelse return false;
    if (setting.len == 0) return false;
    return std.mem.eql(u8, setting, "1") or
        std.ascii.eqlIgnoreCase(setting, "true") or
        std.ascii.eqlIgnoreCase(setting, "yes") or
        std.ascii.eqlIgnoreCase(setting, "on");
}

test "host profiling is opt-in because sampling suspends guest workers" {
    try std.testing.expect(!enabledSetting(null));
    try std.testing.expect(!enabledSetting(""));
    try std.testing.expect(!enabledSetting("0"));
    try std.testing.expect(!enabledSetting("false"));
    try std.testing.expect(!enabledSetting("off"));
    try std.testing.expect(enabledSetting("1"));
    try std.testing.expect(enabledSetting("true"));
    try std.testing.expect(enabledSetting("YES"));
    try std.testing.expect(enabledSetting("on"));
}

test "frame host samples stay isolated by worker slot and epoch" {
    const slot = max_workers - 1;
    const saved = frame_buckets[slot];
    defer frame_buckets[slot] = saved;
    frame_buckets[slot] = @splat(.{});
    recordFrame(slot, 17, 0x10, 0x1234, 0x5678);
    recordFrame(slot, 17, 0x10, 0x1234, 0x9999);
    recordFrame(slot, 18, 0x20, 0xABCD, 0x9876);
    const frame = frameTotals(slot, 17);
    try std.testing.expectEqual(@as(u64, 17), frame.epoch);
    try std.testing.expectEqual(@as(u64, 2), frame.samples);
    try std.testing.expectEqual(@as(usize, 1), frame.distinct);
    try std.testing.expectEqual(@as(u32, 2), frameEntries(slot, 17)[0].count);
    try std.testing.expectEqual(@as(u64, 0x10), frame.guest_handle);
    try std.testing.expect(!frame.mixed_guest_handles);
    try std.testing.expectEqual(@as(u64, 0), frameTotals(slot, 16).samples);
    try std.testing.expectEqual(@as(u64, 1), frameTotals(slot, 18).samples);
}

test "frame host bucket marks guest worker slot reuse as mixed identity" {
    const slot = max_workers - 1;
    const saved = frame_buckets[slot];
    defer frame_buckets[slot] = saved;
    frame_buckets[slot] = @splat(.{});
    recordFrame(slot, 21, 0x10, 0x1234, 0);
    recordFrame(slot, 21, 0x20, 0x5678, 0);
    const frame = frameTotals(slot, 21);
    try std.testing.expect(frame.mixed_guest_handles);
    try std.testing.expectEqual(@as(u64, 2), frame.samples);
}

pub const Totals = struct {
    samples: u64,
    dropped: u64,
    failures: u64,
    interval_ns: u64,
    elapsed_ns: u64,
    distinct: usize,
};

pub fn totals() Totals {
    var distinct: usize = 0;
    for (sampler.table) |entry| {
        if (entry.count != 0) distinct += 1;
    }
    return .{
        .samples = sampler.samples,
        .dropped = sampler.dropped,
        .failures = sampler.failures,
        .interval_ns = sampler.interval_ns,
        .elapsed_ns = sampler.elapsed_ns,
        .distinct = distinct,
    };
}

/// Every sampled program counter. Read only after `stop`.
pub fn entries() []const Entry {
    return &sampler.table;
}

fn run() void {
    while (sampler.running.load(.acquire)) {
        sampleOnce();
        var request = std.c.timespec{
            .sec = @intCast(sampler.interval_ns / std.time.ns_per_s),
            .nsec = @intCast(sampler.interval_ns % std.time.ns_per_s),
        };
        _ = std.c.nanosleep(&request, null);
    }
}

fn monotonicNanoseconds() u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &timestamp) != 0) return 0;
    if (timestamp.sec < 0 or timestamp.nsec < 0) return 0;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(timestamp.nsec));
}

const Sample = struct { pc: u64, lr: u64 };

/// Suspend `target`, read its pc and lr, resume it. Nothing between suspend
/// and resume may take a lock or allocate.
fn sampleThread(target: mach_port_t) ?Sample {
    var state: [ARM_THREAD_STATE64_COUNT]u32 align(8) = undefined;
    var count: u32 = ARM_THREAD_STATE64_COUNT;
    if (thread_suspend(target) != 0) return null;
    const read = std.c.thread_get_state(target, ARM_THREAD_STATE64, @ptrCast(&state), &count);
    _ = std.c.thread_resume(target);
    if (read != 0 or count < ARM_THREAD_STATE64_COUNT) return null;
    const words: *const [ARM_THREAD_STATE64_COUNT / 2]u64 = @ptrCast(&state);
    return .{ .pc = words[state_pc_index] & address_mask, .lr = words[state_lr_index] & address_mask };
}

fn sampleOnce() void {
    const owner_epoch = frame_epoch.load(.acquire);
    if (sampleThread(sampler.target)) |sample| {
        record(sample.pc, sample.lr);
        recordFrame(owner_frame_slot, owner_epoch, 0, sample.pc, sample.lr);
    } else {
        sampler.failures +|= 1;
        recordFrameFailure(owner_frame_slot, owner_epoch, 0);
    }
    for (&worker_targets, 0..) |*target, slot| {
        const port = target.port.load(.acquire);
        if (port == 0) continue;
        const worker_epoch = frame_epoch.load(.acquire);
        const guest_handle = target.guest_handle.load(.acquire);
        // A worker that ended between the load and the suspend fails the
        // suspend; that is a failure count, never a stale sample.
        const sample = sampleThread(port) orelse {
            target.failures +|= 1;
            recordFrameFailure(slot, worker_epoch, guest_handle);
            continue;
        };
        // Do not attach this PC to either identity if the worker was
        // unregistered or reused while its host thread was suspended.
        if (target.port.load(.acquire) != port or target.guest_handle.load(.acquire) != guest_handle) {
            target.failures +|= 1;
            recordFrameFailure(slot, worker_epoch, guest_handle);
            continue;
        }
        target.samples +|= 1;
        const table = target.table.load(.acquire) orelse {
            target.dropped +|= 1;
            continue;
        };
        if (!recordInto(table[0..worker_table_len], sample.pc, sample.lr)) target.dropped +|= 1;
        recordFrame(slot, worker_epoch, guest_handle, sample.pc, sample.lr);
    }
}

fn recordFrame(slot: usize, epoch: u64, guest_handle: u64, pc: u64, lr: u64) void {
    if (epoch == 0 or slot > owner_frame_slot) return;
    const bucket = &frame_buckets[slot][epoch % frame_window_count];
    if (bucket.epoch != epoch) bucket.* = .{ .epoch = epoch, .guest_handle = guest_handle };
    if (bucket.guest_handle != guest_handle) bucket.mixed_guest_handles = true;
    bucket.samples +|= 1;
    if (pc == 0) {
        bucket.dropped +|= 1;
        return;
    }
    for (&bucket.entries) |*entry| {
        if (entry.pc == pc) {
            entry.count +|= 1;
            return;
        }
        if (entry.pc == 0) {
            entry.* = .{ .pc = pc, .lr = lr, .count = 1 };
            return;
        }
    }
    bucket.dropped +|= 1;
}

fn recordFrameFailure(slot: usize, epoch: u64, guest_handle: u64) void {
    if (epoch == 0 or slot > owner_frame_slot) return;
    const bucket = &frame_buckets[slot][epoch % frame_window_count];
    if (bucket.epoch != epoch) bucket.* = .{ .epoch = epoch, .guest_handle = guest_handle };
    if (bucket.guest_handle != guest_handle) bucket.mixed_guest_handles = true;
    bucket.failures +|= 1;
}

fn record(pc: u64, lr: u64) void {
    sampler.samples +|= 1;
    if (!recordInto(&sampler.table, pc, lr)) sampler.dropped +|= 1;
}

/// Count `pc` in an open-addressed table; false when it has no room (or the
/// pc is zero), in which case the caller counts a drop.
fn recordInto(table: []Entry, pc: u64, lr: u64) bool {
    if (pc == 0) return false;
    const mask = table.len - 1;
    const bits: u7 = std.math.log2_int(usize, table.len);
    const shift: u6 = @intCast(64 - bits);
    var slot: usize = @intCast((pc *% 0x9E37_79B9_7F4A_7C15) >> shift);
    var probes: usize = 0;
    while (probes < table.len) : (probes += 1) {
        const entry = &table[slot];
        if (entry.pc == pc) {
            entry.count +|= 1;
            return true;
        }
        if (entry.pc == 0) {
            entry.* = .{ .pc = pc, .lr = lr, .count = 1 };
            return true;
        }
        slot = (slot + 1) & mask;
    }
    return false;
}

pub const HostSymbol = struct {
    /// The image's file name without its directory.
    image: []const u8,
    /// The nearest preceding symbol, when the image keeps one.
    symbol: ?[]const u8,
};

/// Name the image and symbol containing `pc`, for an address outside
/// translated code. Safe to call only after `stop`.
pub fn hostSymbol(pc: u64) ?HostSymbol {
    if (comptime !supported) return null;
    if (pc == 0) return null;
    var info: std.c.dl_info = undefined;
    if (std.c.dladdr(@ptrFromInt(pc), &info) == 0) return null;
    const path = std.mem.span(info.fname);
    const image = if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash| path[slash + 1 ..] else path;
    return .{
        .image = image,
        .symbol = if (info.sname) |name| std.mem.span(name) else null,
    };
}

/// A coarse owner for a host image, for the one-line split.
pub const Owner = enum { rosette, vulkan_driver, metal, system, other };

pub fn ownerOfImage(image: []const u8, rosette_image: []const u8) Owner {
    if (std.mem.eql(u8, image, rosette_image)) return .rosette;
    const has = struct {
        fn f(haystack: []const u8, needle: []const u8) bool {
            return std.ascii.indexOfIgnoreCase(haystack, needle) != null;
        }
    }.f;
    if (has(image, "moltenvk") or has(image, "vulkan")) return .vulkan_driver;
    if (has(image, "metal") or has(image, "agx") or has(image, "iogpu") or has(image, "gpu")) return .metal;
    if (std.mem.startsWith(u8, image, "libsystem") or std.mem.startsWith(u8, image, "libdyld") or
        std.mem.startsWith(u8, image, "libobjc") or std.mem.startsWith(u8, image, "libc++") or
        std.mem.eql(u8, image, "dyld") or has(image, "corefoundation") or has(image, "foundation"))
        return .system;
    return .other;
}

test "the sampler records a busy thread and names this test binary's own code" {
    if (comptime !supported) return error.SkipZigTest;
    try std.testing.expect(startOnCurrentThread(200_000));
    // Spin in a function of this image for long enough to be sampled.
    const began = monotonicNanoseconds();
    var sink: u64 = 0;
    while (true) {
        for (0..10_000) |index| sink +%= index *% 0x9E37;
        if (monotonicNanoseconds() -| began > 60 * std.time.ns_per_ms) break;
    }
    std.mem.doNotOptimizeAway(sink);
    stop();
    const summary = totals();
    try std.testing.expect(summary.samples > 10);
    try std.testing.expect(summary.distinct > 0);
    var named: u64 = 0;
    for (entries()) |entry| {
        if (entry.count == 0) continue;
        if (hostSymbol(entry.pc)) |symbol| {
            if (symbol.image.len != 0) named += entry.count;
        }
    }
    try std.testing.expect(named > 0);
}

test "a full table drops samples instead of overwriting them" {
    const saved = sampler.table;
    defer sampler.table = saved;
    const saved_counts = .{ sampler.samples, sampler.dropped };
    defer {
        sampler.samples = saved_counts[0];
        sampler.dropped = saved_counts[1];
    }
    sampler.table = @splat(.{ .pc = 1, .count = 1 });
    const dropped_before = sampler.dropped;
    record(0x1234_5678, 0);
    try std.testing.expectEqual(dropped_before + 1, sampler.dropped);
    record(1, 0);
    // pc 1 is present everywhere; the probe finds it at its home slot.
    var total: u64 = 0;
    for (sampler.table) |entry| total += entry.count;
    try std.testing.expectEqual(@as(u64, table_len + 1), total);
}

test "a registered worker thread is sampled into its own table" {
    if (comptime !supported) return error.SkipZigTest;
    const slot = max_workers - 1;
    const saved = worker_targets[slot];
    defer worker_targets[slot] = saved;
    worker_targets[slot] = .{};
    const Busy = struct {
        fn run(stop_flag: *std.atomic.Value(bool)) void {
            registerWorker(slot);
            defer unregisterWorker(slot);
            var sink: u64 = 0;
            while (!stop_flag.load(.acquire)) {
                for (0..10_000) |index| sink +%= index *% 0x9E37;
            }
            std.mem.doNotOptimizeAway(sink);
        }
    };
    var stop_flag = std.atomic.Value(bool).init(false);
    const worker = try std.Thread.spawn(.{}, Busy.run, .{&stop_flag});
    try std.testing.expect(startOnCurrentThread(200_000));
    const began = monotonicNanoseconds();
    while (monotonicNanoseconds() -| began < 60 * std.time.ns_per_ms) std.atomic.spinLoopHint();
    stop_flag.store(true, .release);
    worker.join();
    stop();
    const summary = workerTotals(slot);
    try std.testing.expect(summary.samples > 5);
    try std.testing.expect(summary.distinct > 0);
    try std.testing.expectEqual(@as(mach_port_t, 0), worker_targets[slot].port.load(.acquire));
}

test "images are owned coarsely" {
    try std.testing.expectEqual(Owner.rosette, ownerOfImage("elf_processor", "elf_processor"));
    try std.testing.expectEqual(Owner.vulkan_driver, ownerOfImage("libMoltenVK.dylib", "x"));
    try std.testing.expectEqual(Owner.metal, ownerOfImage("AGXMetalG13X", "x"));
    try std.testing.expectEqual(Owner.system, ownerOfImage("libsystem_kernel.dylib", "x"));
    try std.testing.expectEqual(Owner.other, ownerOfImage("libSDL2-2.0.0.dylib", "x"));
}
