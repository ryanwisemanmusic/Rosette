//! Scalar x86 guest-memory accesses on a host that may execute other guest
//! contexts concurrently. The backing address, not the guest address,
//! decides whether a naturally aligned acquire/release access is possible.
//! Unaligned x86 operands keep their legal byte layout and use a barrier.
//!
//! The pieces live in `tso/`:
//!   - `access_stripes.zig`: the address-stripe coordinator for overlapping
//!     executors and the per-host-thread switch that turns it on;
//!   - `store_buffer.zig`: the executor-owned FIFO store buffer;
//!   - `guest_buffers.zig`: the per-guest-context buffer set of a PE process;
//!   - `scalar_access.zig`: serial and coordinated scalar load/store paths;
//!   - `boundary_ledger.zig`: why buffers drained, and the one invariant a
//!     tier boundary must never break.
//! This file is the access API every other module calls.

const std = @import("std");
const stripes = @import("tso/access_stripes.zig");
const store_buffer = @import("tso/store_buffer.zig");
const guest_buffers = @import("tso/guest_buffers.zig");
const scalar_access = @import("tso/scalar_access.zig");
pub const boundary_ledger = @import("tso/boundary_ledger.zig");
pub const memory_policy = @import("tso/memory_policy.zig");

pub const StoreBuffer = store_buffer.StoreBuffer;
pub const GuestStoreBuffers = guest_buffers.GuestStoreBuffers;
pub const Boundary = boundary_ledger.Boundary;

const AccessGuard = stripes.AccessGuard;
const cache_line_bytes = stripes.cache_line_bytes;
const littleEndian = stripes.littleEndian;
const fullBarrier = stripes.fullBarrier;

/// The store buffer of the guest context executing on this host thread.
threadlocal var active_store_buffer: ?*StoreBuffer = null;

test {
    _ = stripes;
    _ = store_buffer;
    _ = guest_buffers;
    _ = scalar_access;
    _ = boundary_ledger;
    _ = memory_policy;
}

/// Bind the current executor's buffer for scalar memory operations. Callers
/// must restore the prior binding when leaving the execution scope.
pub fn setActiveStoreBuffer(buffer: ?*StoreBuffer) ?*StoreBuffer {
    const previous = active_store_buffer;
    active_store_buffer = buffer;
    return previous;
}

pub fn activeStoreBuffer() ?*StoreBuffer {
    return active_store_buffer;
}

/// Pending stores of the bound buffer, zero when none is bound.
pub fn activePendingStores() usize {
    const buffer = active_store_buffer orelse return 0;
    return buffer.pendingCount();
}

pub fn flushActiveStoreBuffer() void {
    flushActiveStoreBufferFor(.unattributed);
}

/// Publish the bound buffer's stores, counting the drain under `boundary`.
pub fn flushActiveStoreBufferFor(boundary: Boundary) void {
    const buffer = active_store_buffer orelse return;
    if (buffer.isEmpty()) return;
    boundary_ledger.noteFlush(boundary, buffer.drain());
}

/// Translated code is about to run from `rip`, reading and writing guest
/// memory directly. Its executor must have nothing buffered: a buffered store
/// is invisible to the block's loads and would overwrite its stores when it
/// drained. Drains whatever it finds and returns true when that was a
/// violation, which is always a missing boundary flush in Rosette.
pub fn enterTranslatedCode(boundary: Boundary, rip: u64) TranslatedEntry {
    const buffer = active_store_buffer orelse return .{};
    const pending = buffer.pendingCount();
    if (pending == 0) return .{};
    const first = boundary_ledger.noteTranslatedEntryViolation(boundary, pending, rip);
    boundary_ledger.noteFlush(boundary, buffer.drain());
    return .{ .violation = true, .first = first, .pending = pending };
}

pub const TranslatedEntry = struct {
    violation: bool = false,
    /// The first violation of the run; the caller logs its site.
    first: bool = false,
    pending: usize = 0,
};

pub fn setCoordinatedGuestAccess(enabled: bool) bool {
    return stripes.setCoordinated(enabled);
}

fn coordinatedGuestAccess() bool {
    return stripes.coordinated();
}

/// Place a bulk guest read after earlier guest reads. Slice-based runtime
/// helpers cannot use one scalar `load`, so they bracket their direct view
/// with the load/load edge required by LFENCE.
pub fn loadFence() void {
    stripes.loadBarrier();
}

/// Order earlier guest stores before a slice-based bulk write. The next
/// scalar release store or bulk borrow orders this write before later stores.
pub fn storeFence() void {
    flushActiveStoreBufferFor(.raw_view);
    stripes.storeBarrier();
}

/// MFENCE orders both sides of the operation and makes this executor's
/// previously buffered stores globally visible.
pub fn memoryFence() void {
    flushActiveStoreBufferFor(.fence);
    fullBarrier();
}

/// x86 LOCK-prefixed read/modify/write instructions are indivisible and act
/// as a full memory fence. The guest-visible value is stored little-endian;
/// the host atomic always operates on the backing address used by the normal
/// load/store path.
pub const UpdateOp = enum {
    add,
    sub,
    neg,
    adc,
    sbb,
    bit_and,
    bit_or,
    bit_xor,
    bit_set,
    bit_reset,
    bit_complement,
};

pub const CompareExchangeResult = struct {
    previous: u64,
    exchanged: bool,
};

pub const CompareExchange128Result = struct {
    previous: u128,
    exchanged: bool,
};

pub const UpdateResult = struct {
    previous: u64,
    value: u64,
};

fn isInteger(comptime T: type) bool {
    return @typeInfo(T) == .int and @sizeOf(T) <= 8;
}

fn isAlignedFor(comptime T: type, bytes: []const u8) bool {
    return @intFromPtr(bytes.ptr) & (@alignOf(T) - 1) == 0;
}

/// Return null when the operand cannot use a naturally aligned host atomic.
/// The caller must execute its serial/slow path in that case; silently
/// splitting an unaligned LOCK operation into ordinary accesses is not a
/// valid implementation once guest contexts can run concurrently.
pub fn exchange(comptime T: type, bytes: []u8, value: T) ?T {
    comptime std.debug.assert(isInteger(T));
    std.debug.assert(bytes.len >= @sizeOf(T));
    flushActiveStoreBufferFor(.fence);
    if (!isAlignedFor(T, bytes)) return null;
    const guard = AccessGuard.lock(bytes[0..@sizeOf(T)]);
    defer guard.unlock();
    const pointer: *T = @ptrFromInt(@intFromPtr(bytes.ptr));
    fullBarrier();
    const old = @atomicRmw(T, pointer, .Xchg, littleEndian(value), .seq_cst);
    fullBarrier();
    return littleEndian(old);
}

/// Width-preserving exchange for an x86 operand whose host address may be
/// unaligned. The coordinator makes the byte sequence indivisible relative to
/// every helper access in parallel mode; serial execution has no competing
/// guest executor and retains the same little-endian layout.
pub fn exchangeAny(comptime T: type, bytes: []u8, value: T) ?T {
    comptime std.debug.assert(isInteger(T));
    std.debug.assert(bytes.len >= @sizeOf(T));
    flushActiveStoreBufferFor(.fence);
    const operand = bytes[0..@sizeOf(T)];
    const guard = AccessGuard.lock(operand);
    defer guard.unlock();
    const address = @intFromPtr(operand.ptr);
    fullBarrier();
    if (address & (@alignOf(T) - 1) == 0) {
        const pointer: *T = @ptrFromInt(address);
        const old = @atomicRmw(T, pointer, .Xchg, littleEndian(value), .seq_cst);
        fullBarrier();
        return littleEndian(old);
    }
    const previous = readBytesLittleEndian(T, operand);
    writeBytesLittleEndian(T, operand, value);
    fullBarrier();
    return previous;
}

/// Sequentially consistent compare/exchange for a naturally aligned guest
/// operand. `previous` is the value observed before the operation, whether
/// the comparison succeeded or failed.
pub fn compareExchange(comptime T: type, bytes: []u8, expected: T, desired: T) ?CompareExchangeResult {
    comptime std.debug.assert(isInteger(T));
    std.debug.assert(bytes.len >= @sizeOf(T));
    flushActiveStoreBufferFor(.fence);
    if (!isAlignedFor(T, bytes)) return null;
    const guard = AccessGuard.lock(bytes[0..@sizeOf(T)]);
    defer guard.unlock();
    const pointer: *T = @ptrFromInt(@intFromPtr(bytes.ptr));
    fullBarrier();
    const failure = @cmpxchgStrong(
        T,
        pointer,
        littleEndian(expected),
        littleEndian(desired),
        .seq_cst,
        .seq_cst,
    );
    fullBarrier();
    return .{
        .previous = @intCast(littleEndian(failure orelse littleEndian(expected))),
        .exchanged = failure == null,
    };
}

/// Compare/exchange for an unaligned scalar guest operand. Aligned operands
/// retain the native host CAS; unaligned operands use the same stripes as
/// ordinary coordinated loads/stores, so no peer can observe a partial
/// locked update.
pub fn compareExchangeAny(comptime T: type, bytes: []u8, expected: T, desired: T) ?CompareExchangeResult {
    comptime std.debug.assert(isInteger(T));
    std.debug.assert(bytes.len >= @sizeOf(T));
    flushActiveStoreBufferFor(.fence);
    const operand = bytes[0..@sizeOf(T)];
    const guard = AccessGuard.lock(operand);
    defer guard.unlock();
    const address = @intFromPtr(operand.ptr);
    fullBarrier();
    if (address & (@alignOf(T) - 1) == 0) {
        const pointer: *T = @ptrFromInt(address);
        const failure = @cmpxchgStrong(
            T,
            pointer,
            littleEndian(expected),
            littleEndian(desired),
            .seq_cst,
            .seq_cst,
        );
        fullBarrier();
        return .{
            .previous = @intCast(littleEndian(failure orelse littleEndian(expected))),
            .exchanged = failure == null,
        };
    }
    const previous = readBytesLittleEndian(T, operand);
    const exchanged = previous == expected;
    if (exchanged) writeBytesLittleEndian(T, operand, desired);
    fullBarrier();
    return .{ .previous = @intCast(previous), .exchanged = exchanged };
}

/// CMPXCHG16B's operand is architecturally 16-byte aligned. Keeping this
/// separate from the scalar API makes the width and alignment contract explicit
/// and lets the compiler select a native paired atomic (or its target runtime
/// implementation) instead of emulating the operation as two independent
/// 64-bit updates.
pub fn compareExchange128(bytes: []u8, expected: u128, desired: u128) ?CompareExchange128Result {
    std.debug.assert(bytes.len >= 16);
    flushActiveStoreBufferFor(.fence);
    if (@intFromPtr(bytes.ptr) & 15 != 0) return null;
    const guard = AccessGuard.lock(bytes[0..16]);
    defer guard.unlock();
    const pointer: *u128 = @ptrFromInt(@intFromPtr(bytes.ptr));
    fullBarrier();
    const failure = @cmpxchgStrong(
        u128,
        pointer,
        littleEndian(expected),
        littleEndian(desired),
        .seq_cst,
        .seq_cst,
    );
    fullBarrier();
    return .{
        .previous = littleEndian(failure orelse littleEndian(expected)),
        .exchanged = failure == null,
    };
}

/// Sequentially consistent fetch-add. The returned value is the old guest
/// value, matching XADD's register result.
pub fn fetchAdd(comptime T: type, bytes: []u8, value: T) ?T {
    comptime std.debug.assert(isInteger(T));
    std.debug.assert(bytes.len >= @sizeOf(T));
    flushActiveStoreBufferFor(.fence);
    if (!isAlignedFor(T, bytes)) return null;
    const guard = AccessGuard.lock(bytes[0..@sizeOf(T)]);
    defer guard.unlock();
    const pointer: *T = @ptrFromInt(@intFromPtr(bytes.ptr));
    fullBarrier();
    const old = @atomicRmw(T, pointer, .Add, littleEndian(value), .seq_cst);
    fullBarrier();
    return littleEndian(old);
}

pub fn fetchAddAny(comptime T: type, bytes: []u8, value: T) ?T {
    const result = updateAny(T, bytes, .add, value, false) orelse return null;
    return @intCast(result.previous);
}

/// Perform a width-limited locked arithmetic/logic update. A CAS retry loop
/// is used for operations without a direct host atomic instruction. The
/// result reports the old and committed values so x86 flags can be derived
/// from the exact value that participated in the atomic operation.
pub fn update(comptime T: type, bytes: []u8, operation: UpdateOp, operand: T, carry_in: bool) ?UpdateResult {
    comptime std.debug.assert(isInteger(T));
    std.debug.assert(bytes.len >= @sizeOf(T));
    flushActiveStoreBufferFor(.fence);
    if (!isAlignedFor(T, bytes)) return null;
    const guard = AccessGuard.lock(bytes[0..@sizeOf(T)]);
    const pointer: *T = @ptrFromInt(@intFromPtr(bytes.ptr));
    defer guard.unlock();
    const mask: T = std.math.maxInt(T);
    const carry: T = @intFromBool(carry_in);
    fullBarrier();
    var old_native = @atomicLoad(T, pointer, .monotonic);
    while (true) {
        const old = littleEndian(old_native);
        const new = applyUpdate(T, operation, old, operand, carry) & mask;
        const failed = @cmpxchgStrong(
            T,
            pointer,
            old_native,
            littleEndian(new),
            .seq_cst,
            .seq_cst,
        );
        if (failed == null) {
            fullBarrier();
            return .{ .previous = @intCast(old), .value = @intCast(new) };
        }
        old_native = failed.?;
    }
}

/// Locked update for every legal x86 scalar alignment. The unaligned form
/// performs byte accesses while holding the range coordinator; aligned
/// operands use a native CAS loop, still under the same guard as peers that
/// touch overlapping bytes with another width.
pub fn updateAny(comptime T: type, bytes: []u8, operation: UpdateOp, operand: T, carry_in: bool) ?UpdateResult {
    comptime std.debug.assert(isInteger(T));
    std.debug.assert(bytes.len >= @sizeOf(T));
    flushActiveStoreBufferFor(.fence);
    const data = bytes[0..@sizeOf(T)];
    const guard = AccessGuard.lock(data);
    defer guard.unlock();
    const address = @intFromPtr(data.ptr);
    const mask: T = std.math.maxInt(T);
    const carry: T = @intFromBool(carry_in);
    fullBarrier();
    if (address & (@alignOf(T) - 1) == 0) {
        const pointer: *T = @ptrFromInt(address);
        var old_native = @atomicLoad(T, pointer, .monotonic);
        while (true) {
            const old = littleEndian(old_native);
            const new = applyUpdate(T, operation, old, operand, carry) & mask;
            const failed = @cmpxchgStrong(
                T,
                pointer,
                old_native,
                littleEndian(new),
                .seq_cst,
                .seq_cst,
            );
            if (failed == null) {
                fullBarrier();
                return .{ .previous = @intCast(old), .value = @intCast(new) };
            }
            old_native = failed.?;
        }
    }
    const old = readBytesLittleEndian(T, data);
    const new = applyUpdate(T, operation, old, operand, carry) & mask;
    writeBytesLittleEndian(T, data, new);
    fullBarrier();
    return .{ .previous = @intCast(old), .value = @intCast(new) };
}

fn applyUpdate(comptime T: type, operation: UpdateOp, old: T, operand: T, carry: T) T {
    return switch (operation) {
        .add => old +% operand,
        .sub => old -% operand,
        .neg => 0 -% old,
        .adc => old +% operand +% carry,
        .sbb => old -% operand -% carry,
        .bit_and => old & operand,
        .bit_or, .bit_set => old | operand,
        .bit_xor, .bit_complement => old ^ operand,
        .bit_reset => old & ~operand,
    };
}

fn readBytesLittleEndian(comptime T: type, bytes: []const u8) T {
    var value: T = 0;
    inline for (0..@sizeOf(T)) |index| {
        const pointer: *const u8 = @ptrFromInt(@intFromPtr(bytes.ptr) + index);
        const byte = @atomicLoad(u8, pointer, .monotonic);
        const shift: std.math.Log2Int(T) = @intCast(index * 8);
        value |= @as(T, byte) << shift;
    }
    return value;
}

fn writeBytesLittleEndian(comptime T: type, bytes: []u8, value: T) void {
    inline for (0..@sizeOf(T)) |index| {
        const pointer: *u8 = @ptrFromInt(@intFromPtr(bytes.ptr) + index);
        const shift: std.math.Log2Int(T) = @intCast(index * 8);
        @atomicStore(u8, pointer, @truncate(value >> shift), .monotonic);
    }
}

/// Copy a stable snapshot from guest-backed memory. During serial execution
/// this is a normal copy; in coordinated mode it takes the same address
/// stripes as guest writes and reads each byte atomically.
pub fn copyIn(destination: []u8, source: []const u8) void {
    copyInMode(destination, source, coordinatedGuestAccess(), true);
}

/// Snapshot guest-backed bytes with coordination regardless of the calling
/// host thread's thread-local execution flag. Diagnostics and code-validation
/// paths can run outside the active executor thread while still sharing its
/// address space.
pub fn copyInCoordinated(destination: []u8, source: []const u8) void {
    copyInMode(destination, source, true, true);
}

/// Compare cached instruction bytes against live guest code without taking
/// an address stripe.
///
/// A decode cache hit only has to prove the bytes it decoded are the bytes
/// there now. A torn read of bytes another executor is rewriting either
/// differs from the cached copy, and the caller refills from a coordinated
/// snapshot, or equals it, which is an interleaving in which this fetch came
/// before the write. Either way the decode used is exact for the bytes seen.
/// This executor's own queued stores still forward, through the coordinated
/// comparison: a thread sees its own code writes in program order.
///
/// The stripe cost two atomic read-modify-writes on a line every executor
/// decoding the same code shares; on 2026-09-30 that comparison was 5.5% of
/// the title's main thread and 3% of its render thread.
pub fn eqlCodeBytes(expected: []const u8, source: []const u8, scratch: []u8) bool {
    if (expected.len > source.len or scratch.len < expected.len) return false;
    if (expected.len == 0) return true;
    if (active_store_buffer) |buffer| {
        if (buffer.mayForward(@intFromPtr(source.ptr), expected.len)) return eqlCoordinated(expected, source, scratch);
    }
    for (expected, source[0..expected.len]) |wanted, *actual| {
        if (@atomicLoad(u8, actual, .monotonic) != wanted) return false;
    }
    return true;
}

/// Compare guest-backed bytes without staging a copy when the current
/// executor has no buffered stores. Instruction-cache hits use this while
/// holding the corresponding decode-cache set lock: it takes the same shared
/// address stripes as guest writes and compares aligned atomic word chunks
/// in place. When this executor has a store buffer, keep the snapshot path so
/// its own stores are forwarded exactly as a normal instruction fetch would
/// observe them.
fn eqlAtomicChunk(comptime T: type, expected: []const u8, source_address: usize) bool {
    const source: *const T = @ptrFromInt(source_address);
    const actual = littleEndian(@atomicLoad(T, source, .monotonic));
    const wanted = std.mem.readInt(T, expected[0..@sizeOf(T)], .little);
    return actual == wanted;
}

pub fn eqlCoordinated(expected: []const u8, source: []const u8, scratch: []u8) bool {
    if (expected.len > source.len or scratch.len < expected.len) return false;
    if (expected.len == 0) return true;
    if (active_store_buffer) |buffer| {
        if (buffer.mayForward(@intFromPtr(source.ptr), expected.len)) {
            const snapshot = scratch[0..expected.len];
            copyInMode(snapshot, source[0..expected.len], true, true);
            return std.mem.eql(u8, expected, snapshot);
        }
    }

    var offset: usize = 0;
    while (offset < expected.len) {
        const address = @intFromPtr(source.ptr) + offset;
        const line_remaining = cache_line_bytes - (address & (cache_line_bytes - 1));
        const count = @min(expected.len - offset, line_remaining);
        const chunk = source[offset..][0..count];
        const guard = AccessGuard.lockMode(chunk, true, true);
        var equal = true;
        var compared: usize = 0;
        while (compared < count) {
            const chunk_address = address + compared;
            const available = count - compared;
            const width: usize = if (available >= 8 and chunk_address & 7 == 0)
                8
            else if (available >= 4 and chunk_address & 3 == 0)
                4
            else if (available >= 2 and chunk_address & 1 == 0)
                2
            else
                1;
            const matched = switch (width) {
                8 => eqlAtomicChunk(u64, expected[offset + compared ..], chunk_address),
                4 => eqlAtomicChunk(u32, expected[offset + compared ..], chunk_address),
                2 => eqlAtomicChunk(u16, expected[offset + compared ..], chunk_address),
                1 => eqlAtomicChunk(u8, expected[offset + compared ..], chunk_address),
                else => unreachable,
            };
            if (!matched) {
                equal = false;
                break;
            }
            compared += width;
        }
        guard.unlock();
        if (!equal) return false;
        offset += count;
    }
    fullBarrier();
    return true;
}

/// Take a coordinated snapshot of backing bytes without applying the current
/// executor's store-buffer overlay. This is reserved for fault diagnostics:
/// comparing it with `copyInCoordinated` distinguishes bytes already
/// published to memory from bytes visible only to the current guest context.
pub fn copyBackingCoordinated(destination: []u8, source: []const u8) void {
    copyInMode(destination, source, true, false);
}

/// Find the terminator in a guest C string without making ordinary host
/// reads race translated guest stores. The source must already be bounded to
/// a readable guest region. In coordinated mode each cache-line chunk shares
/// the same stripe locks and atomic byte loads as guest writes.
pub fn findCStringEnd(source: []const u8) ?usize {
    return findByteMode(source, 0, coordinatedGuestAccess());
}

/// Forced-coordination form for runtime helpers that snapshot guest memory
/// from outside the active executor's thread-local access scope.
pub fn findCStringEndCoordinated(source: []const u8) ?usize {
    return findByteMode(source, 0, true);
}

/// Find a byte in a bounded guest region. The forced form is used by runtime
/// helpers such as `memchr` that may inspect memory from outside a guest
/// instruction's thread-local coordinator scope.
pub fn findByteCoordinated(source: []const u8, needle: u8) ?usize {
    return findByteMode(source, needle, true);
}

/// Search one cache line at a time: snapshot the line under its stripe (when
/// coordinated), overlay this executor's buffered stores, then search.
fn findByteMode(source: []const u8, needle: u8, coordinated: bool) ?usize {
    if (!coordinated and active_store_buffer == null) return std.mem.indexOfScalar(u8, source, needle);

    var line: [cache_line_bytes]u8 = undefined;
    var offset: usize = 0;
    while (offset < source.len) {
        const address = @intFromPtr(source.ptr) + offset;
        const line_remaining = cache_line_bytes - (address & (cache_line_bytes - 1));
        const count = @min(source.len - offset, line_remaining);
        const chunk = source[offset..][0..count];
        const guard = AccessGuard.lockMode(chunk, coordinated, true);
        for (line[0..count], 0..) |*byte, index| {
            const pointer: *const u8 = @ptrFromInt(address + index);
            byte.* = @atomicLoad(u8, pointer, .monotonic);
        }
        guard.unlock();
        if (active_store_buffer) |buffer| _ = buffer.forwardInto(line[0..count], address);
        if (std.mem.indexOfScalar(u8, line[0..count], needle)) |index| return offset + index;
        offset += count;
    }
    return null;
}

fn copyInMode(destination: []u8, source: []const u8, coordinated: bool, forward_stores: bool) void {
    std.debug.assert(destination.len <= source.len);
    const input = source[0..destination.len];
    if (!coordinated) {
        @memcpy(destination, input);
        if (forward_stores) {
            if (active_store_buffer) |buffer| _ = buffer.forwardInto(destination, @intFromPtr(input.ptr));
        }
        return;
    }

    // Limit each guard to one source cache line. `copyIn` is also used for
    // short instruction fetches, but it is a public bulk helper and must not
    // leave intermediate stripes unlocked for a larger caller buffer.
    var offset: usize = 0;
    while (offset < input.len) {
        const address = @intFromPtr(input.ptr) + offset;
        const line_remaining = cache_line_bytes - (address & (cache_line_bytes - 1));
        const count = @min(input.len - offset, line_remaining);
        const chunk = input[offset..][0..count];
        const guard = AccessGuard.lockMode(chunk, coordinated, true);
        for (destination[offset..][0..count], 0..) |*byte, index| {
            const pointer: *const u8 = @ptrFromInt(address + index);
            byte.* = @atomicLoad(u8, pointer, .monotonic);
        }
        guard.unlock();
        offset += count;
    }
    fullBarrier();
    if (forward_stores) {
        if (active_store_buffer) |buffer| _ = buffer.forwardInto(destination[0..input.len], @intFromPtr(input.ptr));
    }
}

pub fn load(comptime T: type, bytes: []const u8) T {
    return loadMode(T, bytes, coordinatedGuestAccess());
}

/// Forced-coordination scalar load for a runtime snapshot taken outside the
/// active guest executor's thread-local access scope.
pub fn loadCoordinated(comptime T: type, bytes: []const u8) T {
    return loadMode(T, bytes, true);
}

/// Load without forwarding from the executor's ordinary RAM store buffer.
/// The caller selects coordination from the address class and must name why
/// the buffer is bypassed. Pending temporal stores are published first.
pub fn loadUnbuffered(comptime T: type, bytes: []const u8, coordinated: bool, boundary: Boundary) T {
    flushActiveStoreBufferFor(boundary);
    return scalar_access.load(T, bytes, coordinated, null);
}

fn loadMode(comptime T: type, bytes: []const u8, coordinated: bool) T {
    return scalar_access.load(T, bytes, coordinated, active_store_buffer);
}

pub fn store(comptime T: type, bytes: []u8, value: T) void {
    storeMode(T, bytes, value, coordinatedGuestAccess());
}

/// Forced-coordination scalar store for runtime writes outside the active
/// guest executor's thread-local access scope.
pub fn storeCoordinated(comptime T: type, bytes: []u8, value: T) void {
    storeMode(T, bytes, value, true);
}

/// Store directly to the backing memory instead of entering the ordinary
/// temporal queue. Used for device-backed aliases and non-temporal guest
/// stores after publishing earlier queued stores.
pub fn storeUnbuffered(comptime T: type, bytes: []u8, value: T, coordinated: bool, boundary: Boundary) void {
    flushActiveStoreBufferFor(boundary);
    scalar_access.store(T, bytes, value, coordinated, null);
}

fn storeMode(comptime T: type, bytes: []u8, value: T, coordinated: bool) void {
    scalar_access.store(T, bytes, value, coordinated, active_store_buffer);
}

/// Copy bytes as an ordered series of scalar guest accesses. It accepts
/// overlapping slices (memmove semantics), so helpers that implement
/// guest-visible memcpy/memmove do not accidentally let the host compiler
/// reorder a batch of stores past one another on ARM64.
pub fn copy(destination: []u8, source: []const u8) void {
    copyMode(destination, source, coordinatedGuestAccess());
}

/// Forced-coordination bulk copy for runtime helpers outside the active
/// executor scope. Each scalar access still participates in the same stripes
/// as the guest instruction path.
pub fn copyCoordinated(destination: []u8, source: []const u8) void {
    copyMode(destination, source, true);
}

fn copyMode(destination: []u8, source: []const u8, coordinated: bool) void {
    std.debug.assert(destination.len >= source.len);
    if (source.len == 0 or destination.ptr == source.ptr) return;
    const dst_address = @intFromPtr(destination.ptr);
    const src_address = @intFromPtr(source.ptr);
    const backwards = dst_address > src_address and dst_address - src_address < source.len;
    copyDirectionalMode(destination, source, backwards, coordinated);
}

/// Copy in the supplied direction. Guest virtual addresses decide memmove's
/// overlap direction even when two guest mappings alias the same host view.
/// Callers implementing a guest routine should therefore pass the decision
/// made from guest addresses rather than infer it from these slices.
pub fn copyDirectional(destination: []u8, source: []const u8, backwards: bool) void {
    copyDirectionalMode(destination, source, backwards, coordinatedGuestAccess());
}

/// Forced-coordination variant when a bulk guest operation runs outside the
/// active executor's thread-local access scope.
pub fn copyDirectionalCoordinated(destination: []u8, source: []const u8, backwards: bool) void {
    copyDirectionalMode(destination, source, backwards, true);
}

fn copyDirectionalMode(destination: []u8, source: []const u8, backwards: bool, coordinated: bool) void {
    std.debug.assert(destination.len >= source.len);
    if (source.len == 0 or destination.ptr == source.ptr) return;
    const count = source.len;
    const dst_address = @intFromPtr(destination.ptr);
    const src_address = @intFromPtr(source.ptr);

    if (!backwards) {
        var index: usize = 0;
        if ((dst_address ^ src_address) & 7 == 0) {
            while (index < count and (dst_address + index) & 7 != 0) : (index += 1) {
                storeMode(u8, destination[index..], loadMode(u8, source[index..], coordinated), coordinated);
            }
            while (count - index >= 8) : (index += 8) {
                const word = loadMode(u64, source[index..], coordinated);
                storeMode(u64, destination[index..], word, coordinated);
            }
        }
        while (index < count) : (index += 1) {
            storeMode(u8, destination[index..], loadMode(u8, source[index..], coordinated), coordinated);
        }
        return;
    }

    var remaining = count;
    if ((dst_address ^ src_address) & 7 == 0) {
        while (remaining != 0 and (dst_address + remaining) & 7 != 0) : (remaining -= 1) {
            storeMode(u8, destination[remaining - 1 ..], loadMode(u8, source[remaining - 1 ..], coordinated), coordinated);
        }
        while (remaining >= 8) : (remaining -= 8) {
            const offset = remaining - 8;
            const word = loadMode(u64, source[offset..], coordinated);
            storeMode(u64, destination[offset..], word, coordinated);
        }
    }
    while (remaining != 0) {
        remaining -= 1;
        storeMode(u8, destination[remaining..], loadMode(u8, source[remaining..], coordinated), coordinated);
    }
}

/// Fill guest memory with ordered scalar stores. Aligned eight-byte stores
/// amortize the ordering cost while each store remains release-ordered with
/// respect to the previous guest access.
pub fn fill(destination: []u8, byte: u8) void {
    fillMode(destination, byte, coordinatedGuestAccess());
}

/// Forced-coordination variant for zero/fill operations from a host runtime
/// callback that is not currently inside `ElfState.step`.
pub fn fillCoordinated(destination: []u8, byte: u8) void {
    fillMode(destination, byte, true);
}

fn fillMode(destination: []u8, byte: u8, coordinated: bool) void {
    var index: usize = 0;
    while (index < destination.len and @intFromPtr(destination.ptr) + index & 7 != 0) : (index += 1) {
        storeMode(u8, destination[index..], byte, coordinated);
    }
    const repeated: u64 = @as(u64, byte) *% 0x0101_0101_0101_0101;
    while (destination.len - index >= 8) : (index += 8) {
        storeMode(u64, destination[index..], repeated, coordinated);
    }
    while (index < destination.len) : (index += 1) {
        storeMode(u8, destination[index..], byte, coordinated);
    }
}

test "guest store buffers forward newest overlapping bytes and drain in order" {
    var backing: [32]u8 align(16) = [_]u8{0} ** 32;
    var writer: StoreBuffer = .{};
    var reader: StoreBuffer = .{};
    const prior_mode = setCoordinatedGuestAccess(true);
    defer _ = setCoordinatedGuestAccess(prior_mode);
    const prior_buffer = setActiveStoreBuffer(&writer);
    defer _ = setActiveStoreBuffer(prior_buffer);

    storeCoordinated(u64, backing[8..16], 0x1122_3344_5566_7788);
    storeCoordinated(u16, backing[10..12], 0xAABB);
    try std.testing.expectEqual(@as(usize, 2), writer.pendingCount());
    try std.testing.expectEqual(@as(u64, 0x1122_3344_AABB_7788), loadCoordinated(u64, backing[8..16]));

    _ = setActiveStoreBuffer(&reader);
    try std.testing.expectEqual(@as(u64, 0), loadCoordinated(u64, backing[8..16]));
    _ = setActiveStoreBuffer(&writer);
    _ = writer.drain();
    _ = setActiveStoreBuffer(&reader);
    try std.testing.expectEqual(@as(u64, 0x1122_3344_AABB_7788), loadCoordinated(u64, backing[8..16]));
    try std.testing.expectEqual(@as(usize, 0), writer.pendingCount());
}

test "serial guest store buffers forward locally and drain after bounded retirement" {
    var backing: [8]u8 align(8) = [_]u8{0} ** 8;
    var buffer: StoreBuffer = .{};
    const prior_mode = setCoordinatedGuestAccess(false);
    defer _ = setCoordinatedGuestAccess(prior_mode);
    const prior_buffer = setActiveStoreBuffer(&buffer);
    defer _ = setActiveStoreBuffer(prior_buffer);

    store(u32, backing[0..4], 0xA1B2_C3D4);
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, backing[0..4], .little));
    try std.testing.expectEqual(@as(u32, 0xA1B2_C3D4), load(u32, backing[0..4]));

    var snapshot: [4]u8 = undefined;
    copyIn(&snapshot, backing[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 0xD4, 0xC3, 0xB2, 0xA1 }, &snapshot);

    for (0..StoreBuffer.retire_interval - 1) |_| buffer.retireInstruction();
    try std.testing.expectEqual(@as(usize, 1), buffer.pendingCount());
    buffer.retireInstruction();
    try std.testing.expectEqual(@as(usize, 0), buffer.pendingCount());
    try std.testing.expectEqual(@as(u32, 0xA1B2_C3D4), load(u32, backing[0..4]));
}

test "store fence drains the active guest store buffer" {
    var backing: [8]u8 align(8) = [_]u8{0} ** 8;
    var buffer: StoreBuffer = .{};
    const prior_mode = setCoordinatedGuestAccess(true);
    defer _ = setCoordinatedGuestAccess(prior_mode);
    const prior_buffer = setActiveStoreBuffer(&buffer);
    defer _ = setActiveStoreBuffer(prior_buffer);

    storeCoordinated(u32, backing[0..4], 0xDEAD_BEEF);
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, backing[0..4], .little));
    storeFence();
    try std.testing.expectEqual(@as(usize, 0), buffer.pendingCount());
    try std.testing.expectEqual(@as(u32, 0xDEAD_BEEF), loadCoordinated(u32, backing[0..4]));
}

test "unbuffered access publishes earlier temporal stores and never requeues" {
    var backing: [16]u8 align(8) = [_]u8{0} ** 16;
    var buffer: StoreBuffer = .{};
    const prior_mode = setCoordinatedGuestAccess(true);
    defer _ = setCoordinatedGuestAccess(prior_mode);
    const prior_buffer = setActiveStoreBuffer(&buffer);
    defer _ = setActiveStoreBuffer(prior_buffer);

    storeCoordinated(u32, backing[0..4], 0x1122_3344);
    storeUnbuffered(u32, backing[8..12], 0xAABB_CCDD, true, .device_access);
    try std.testing.expectEqual(@as(usize, 0), buffer.pendingCount());
    try std.testing.expectEqual(@as(u32, 0x1122_3344), std.mem.readInt(u32, backing[0..4], .little));
    try std.testing.expectEqual(@as(u32, 0xAABB_CCDD), loadUnbuffered(u32, backing[8..12], true, .device_access));

    const ledger = boundary_ledger.snapshot();
    try std.testing.expectEqual(@as(u64, 1), ledger.flushes[@intFromEnum(Boundary.device_access)]);
    try std.testing.expectEqual(@as(u64, 1), ledger.entries[@intFromEnum(Boundary.device_access)]);
}

test "load fence preserves pending stores for same-context forwarding" {
    var backing: [8]u8 align(8) = [_]u8{0} ** 8;
    var buffer: StoreBuffer = .{};
    const prior_mode = setCoordinatedGuestAccess(true);
    defer _ = setCoordinatedGuestAccess(prior_mode);
    const prior_buffer = setActiveStoreBuffer(&buffer);
    defer _ = setActiveStoreBuffer(prior_buffer);

    storeCoordinated(u32, backing[0..4], 0xC0DE_CAFE);
    loadFence();
    try std.testing.expectEqual(@as(usize, 1), buffer.pendingCount());
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, backing[0..4], .little));
    try std.testing.expectEqual(@as(u32, 0xC0DE_CAFE), loadCoordinated(u32, backing[0..4]));
}

test "full memory fence drains pending stores" {
    var backing: [8]u8 align(8) = [_]u8{0} ** 8;
    var buffer: StoreBuffer = .{};
    const prior_buffer = setActiveStoreBuffer(&buffer);
    defer _ = setActiveStoreBuffer(prior_buffer);

    store(u64, backing[0..8], 0x0123_4567_89AB_CDEF);
    memoryFence();
    try std.testing.expectEqual(@as(usize, 0), buffer.pendingCount());
    try std.testing.expectEqual(@as(u64, 0x0123_4567_89AB_CDEF), std.mem.readInt(u64, backing[0..8], .little));
}

test "locked compare exchange drains prior guest stores before its atomic update" {
    var backing: [8]u8 align(8) = [_]u8{0} ** 8;
    var buffer: StoreBuffer = .{};
    const prior_mode = setCoordinatedGuestAccess(true);
    defer _ = setCoordinatedGuestAccess(prior_mode);
    const prior_buffer = setActiveStoreBuffer(&buffer);
    defer _ = setActiveStoreBuffer(prior_buffer);

    storeCoordinated(u64, backing[0..8], 3);
    const result = compareExchangeAny(u64, backing[0..8], 3, 7).?;
    try std.testing.expect(result.exchanged);
    try std.testing.expectEqual(@as(u64, 3), result.previous);
    try std.testing.expectEqual(@as(usize, 0), buffer.pendingCount());
    try std.testing.expectEqual(@as(u64, 7), loadCoordinated(u64, backing[0..8]));
}

test "translated-code entry with buffered stores is drained and counted once" {
    boundary_ledger.resetForTest();
    defer boundary_ledger.resetForTest();
    var backing: [8]u8 align(8) = @splat(0);
    var buffer: StoreBuffer = .{};
    const prior_buffer = setActiveStoreBuffer(&buffer);
    defer _ = setActiveStoreBuffer(prior_buffer);

    try std.testing.expect(!enterTranslatedCode(.jit_entry, 0x1000).violation);
    store(u32, backing[0..4], 0x0102_0304);
    const entry = enterTranslatedCode(.jit_entry, 0x2000);
    try std.testing.expect(entry.violation and entry.first);
    try std.testing.expectEqual(@as(usize, 1), entry.pending);
    try std.testing.expectEqual(@as(usize, 0), buffer.pendingCount());
    try std.testing.expectEqual(@as(u32, 0x0102_0304), std.mem.readInt(u32, backing[0..4], .little));
    store(u32, backing[4..8], 5);
    try std.testing.expect(!enterTranslatedCode(.jit_fallback, 0x3000).first);
    const recorded = boundary_ledger.snapshot();
    try std.testing.expectEqual(@as(u64, 2), recorded.translated_entry_violations);
    try std.testing.expectEqual(@as(u64, 0x2000), recorded.first_violation_rip);
}

test "a string search sees this executor's buffered terminator" {
    var bytes: [80]u8 align(64) = [_]u8{'x'} ** 80;
    var buffer: StoreBuffer = .{};
    const prior_buffer = setActiveStoreBuffer(&buffer);
    defer _ = setActiveStoreBuffer(prior_buffer);
    try std.testing.expectEqual(@as(?usize, null), findCStringEnd(bytes[0..80]));
    store(u8, bytes[70..71], 0);
    try std.testing.expectEqual(@as(?usize, 70), findCStringEnd(bytes[0..80]));
    try std.testing.expectEqual(@as(?usize, 70), findByteCoordinated(bytes[0..80], 0));
    _ = buffer.drain();
}

test "two guest executors can observe x86 store to load reordering" {
    const Shared = struct {
        bytes: [16]u8 align(8) = [_]u8{0} ** 16,
        stores_queued: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        loads_completed: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        observed: [2]u32 = [_]u32{0} ** 2,

        fn execute(shared: *@This(), executor: usize) void {
            var buffer: StoreBuffer = .{};
            const prior_mode = setCoordinatedGuestAccess(true);
            defer _ = setCoordinatedGuestAccess(prior_mode);
            const prior_buffer = setActiveStoreBuffer(&buffer);
            defer _ = setActiveStoreBuffer(prior_buffer);

            const own = if (executor == 0) shared.bytes[0..4] else shared.bytes[8..12];
            const peer = if (executor == 0) shared.bytes[8..12] else shared.bytes[0..4];
            storeCoordinated(u32, own, 1);
            _ = shared.stores_queued.fetchAdd(1, .release);
            while (shared.stores_queued.load(.acquire) != 2) std.atomic.spinLoopHint();
            shared.observed[executor] = loadCoordinated(u32, peer);
            _ = shared.loads_completed.fetchAdd(1, .release);
            while (shared.loads_completed.load(.acquire) != 2) std.atomic.spinLoopHint();
            _ = buffer.drain();
        }
    };

    var shared = Shared{};
    const first = try std.Thread.spawn(.{}, Shared.execute, .{ &shared, 0 });
    const second = try std.Thread.spawn(.{}, Shared.execute, .{ &shared, 1 });
    first.join();
    second.join();
    const expected = [_]u32{ 0, 0 };
    try std.testing.expectEqualSlices(u32, &expected, &shared.observed);
    try std.testing.expectEqual(@as(u32, 1), loadCoordinated(u32, shared.bytes[0..4]));
    try std.testing.expectEqual(@as(u32, 1), loadCoordinated(u32, shared.bytes[8..12]));
}

test "ordered scalar accesses preserve width and legal misalignment" {
    var bytes: [32]u8 align(8) = @splat(0);
    inline for (.{ u8, u16, u32, u64 }) |T| {
        const value: T = @truncate(0x8877_6655_4433_2211);
        for (0..8) |offset| {
            @memset(&bytes, 0);
            store(T, bytes[offset..], value);
            try std.testing.expectEqual(value, load(T, bytes[offset..]));
            try std.testing.expectEqual(@as(u8, 0), bytes[offset + @sizeOf(T)]);
        }
    }
}

test "unaligned scalar accesses use atomic bytes and preserve adjacent data" {
    var bytes: [24]u8 align(8) = [_]u8{0xA5} ** 24;
    inline for (.{ u16, u32, u64 }) |T| {
        const width = @sizeOf(T);
        for (1..8) |offset| {
            if (offset + width >= bytes.len) continue;
            @memset(&bytes, 0xA5);
            const value: T = @truncate(0x8877_6655_4433_2211);
            store(T, bytes[offset..], value);
            try std.testing.expectEqual(value, load(T, bytes[offset..]));
            try std.testing.expectEqual(@as(u8, 0xA5), bytes[offset - 1]);
            try std.testing.expectEqual(@as(u8, 0xA5), bytes[offset + width]);
        }
    }
}

test "release publication makes an earlier guest store visible on another host thread" {
    const Shared = struct {
        payload: u64 = 0,
        ready: u64 = 0,
        consumed: u64 = 0,
        mismatch: u8 = 0,

        fn consumer(self: *@This()) void {
            for (1..10_001) |round| {
                const expected: u64 = @intCast(round);
                while (load(u64, std.mem.asBytes(&self.ready)) != expected) std.atomic.spinLoopHint();
                if (load(u64, std.mem.asBytes(&self.payload)) != expected) {
                    @atomicStore(u8, &self.mismatch, 1, .release);
                }
                store(u64, std.mem.asBytes(&self.consumed), expected);
            }
        }
    };
    var shared = Shared{};
    const thread = try std.Thread.spawn(.{}, Shared.consumer, .{&shared});
    for (1..10_001) |round| {
        const expected: u64 = @intCast(round);
        while (load(u64, std.mem.asBytes(&shared.consumed)) != expected - 1) std.atomic.spinLoopHint();
        store(u64, std.mem.asBytes(&shared.payload), expected);
        store(u64, std.mem.asBytes(&shared.ready), expected);
    }
    thread.join();
    try std.testing.expectEqual(@as(u8, 0), @atomicLoad(u8, &shared.mismatch, .acquire));
}

test "coordinated unaligned accesses cannot observe a split peer store" {
    const Shared = struct {
        bytes: [128]u8 align(64) = [_]u8{0} ** 128,
        done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        invalid: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn observe(shared: *@This()) void {
            const previous = setCoordinatedGuestAccess(true);
            defer _ = setCoordinatedGuestAccess(previous);
            const first: u64 = 0x1122_3344_5566_7788;
            const second: u64 = 0xAABB_CCDD_EEFF_0011;
            while (!shared.done.load(.acquire)) {
                const value = load(u64, shared.bytes[63..]);
                if (value != first and value != second) shared.invalid.store(true, .release);
            }
            const value = load(u64, shared.bytes[63..]);
            if (value != first and value != second) shared.invalid.store(true, .release);
        }
    };

    var shared = Shared{};
    const first: u64 = 0x1122_3344_5566_7788;
    const second: u64 = 0xAABB_CCDD_EEFF_0011;
    const prior = setCoordinatedGuestAccess(true);
    store(u64, shared.bytes[63..], first);
    _ = setCoordinatedGuestAccess(prior);

    const observer = try std.Thread.spawn(.{}, Shared.observe, .{&shared});
    const previous = setCoordinatedGuestAccess(true);
    for (0..50_000) |iteration| {
        const value = if (iteration & 1 == 0) second else first;
        if (iteration & 3 == 0) {
            _ = exchangeAny(u64, shared.bytes[63..], value);
        } else {
            store(u64, shared.bytes[63..], value);
        }
    }
    shared.done.store(true, .release);
    _ = setCoordinatedGuestAccess(previous);
    observer.join();
    try std.testing.expect(!shared.invalid.load(.acquire));
}

test "mixed-width overlapping buffered stores remain local until publication" {
    const Shared = struct {
        bytes: [8]u8 align(8) = [_]u8{0xA5} ** 8,
        ready: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        observed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

        fn observe(shared: *@This()) void {
            const previous_mode = setCoordinatedGuestAccess(true);
            defer _ = setCoordinatedGuestAccess(previous_mode);
            while (!shared.ready.load(.acquire)) std.atomic.spinLoopHint();
            shared.observed.store(loadCoordinated(u64, shared.bytes[0..8]), .release);
        }
    };

    var shared = Shared{};
    var buffer = StoreBuffer{};
    const previous_mode = setCoordinatedGuestAccess(true);
    defer _ = setCoordinatedGuestAccess(previous_mode);
    const previous_buffer = setActiveStoreBuffer(&buffer);
    defer _ = setActiveStoreBuffer(previous_buffer);

    store(u64, shared.bytes[0..8], 0x8877_6655_4433_2211);
    store(u32, shared.bytes[2..6], 0xAABB_CCDD);
    store(u16, shared.bytes[5..7], 0xEEFF);
    try std.testing.expectEqual(@as(usize, 3), buffer.pendingCount());

    const observer = try std.Thread.spawn(.{}, Shared.observe, .{&shared});
    shared.ready.store(true, .release);

    var forwarded: [8]u8 = undefined;
    copyInCoordinated(&forwarded, &shared.bytes);
    try std.testing.expectEqual([_]u8{ 0x11, 0x22, 0xDD, 0xCC, 0xBB, 0xFF, 0xEE, 0x88 }, forwarded);
    observer.join();

    const backing_value = std.mem.readInt(u64, &shared.bytes, .little);
    try std.testing.expectEqual(@as(u64, 0xA5A5_A5A5_A5A5_A5A5), shared.observed.load(.acquire));
    try std.testing.expectEqual(@as(u64, 0xA5A5_A5A5_A5A5_A5A5), backing_value);
    try std.testing.expectEqual(@as(usize, 3), buffer.drain());
    try std.testing.expectEqualSlices(u8, &forwarded, &shared.bytes);
}

test "an unaligned store crossing a cache line drains atomically to peers" {
    const Shared = struct {
        bytes: [128]u8 align(64) = [_]u8{0} ** 128,
        done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        invalid: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn observe(shared: *@This()) void {
            const previous_mode = setCoordinatedGuestAccess(true);
            defer _ = setCoordinatedGuestAccess(previous_mode);
            const first: u64 = 0x1122_3344_5566_7788;
            const second: u64 = 0xAABB_CCDD_EEFF_0011;
            while (!shared.done.load(.acquire)) {
                const value = loadCoordinated(u64, shared.bytes[60..68]);
                if (value != first and value != second) shared.invalid.store(true, .release);
            }
            const value = loadCoordinated(u64, shared.bytes[60..68]);
            if (value != first and value != second) shared.invalid.store(true, .release);
        }
    };

    var shared = Shared{};
    const first: u64 = 0x1122_3344_5566_7788;
    const second: u64 = 0xAABB_CCDD_EEFF_0011;
    const previous_mode = setCoordinatedGuestAccess(true);
    storeCoordinated(u64, shared.bytes[60..68], first);
    _ = setCoordinatedGuestAccess(previous_mode);

    const observer = try std.Thread.spawn(.{}, Shared.observe, .{&shared});
    const producer_mode = setCoordinatedGuestAccess(true);
    var buffer = StoreBuffer{};
    const previous_buffer = setActiveStoreBuffer(&buffer);
    for (0..50_000) |iteration| {
        const value = if (iteration & 1 == 0) second else first;
        store(u64, shared.bytes[60..68], value);
        _ = buffer.drain();
    }
    shared.done.store(true, .release);
    _ = setActiveStoreBuffer(previous_buffer);
    _ = setCoordinatedGuestAccess(producer_mode);
    observer.join();
    try std.testing.expect(!shared.invalid.load(.acquire));
    try std.testing.expect(buffer.isEmpty());
}

test "a locked exchange publishes buffered stores before a peer observes its handoff" {
    const Shared = struct {
        const rounds = 4096;
        bytes: [64]u8 align(64) = [_]u8{0} ** 64,
        mismatch: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn consume(shared: *@This()) void {
            const previous_mode = setCoordinatedGuestAccess(true);
            defer _ = setCoordinatedGuestAccess(previous_mode);
            const payload = shared.bytes[0..8];
            const ready = shared.bytes[8..16];
            const acknowledged = shared.bytes[16..24];
            for (1..rounds + 1) |round| {
                const expected: u64 = @intCast(round);
                while (loadCoordinated(u64, ready) != expected) std.atomic.spinLoopHint();
                if (loadCoordinated(u64, payload) != expected) shared.mismatch.store(true, .release);
                storeCoordinated(u64, acknowledged, expected);
            }
        }
    };

    var shared = Shared{};
    const consumer = try std.Thread.spawn(.{}, Shared.consume, .{&shared});
    const previous_mode = setCoordinatedGuestAccess(true);
    defer _ = setCoordinatedGuestAccess(previous_mode);
    var buffer = StoreBuffer{};
    const previous_buffer = setActiveStoreBuffer(&buffer);
    defer {
        _ = setActiveStoreBuffer(previous_buffer);
        _ = buffer.drain();
    }
    const payload = shared.bytes[0..8];
    const ready = shared.bytes[8..16];
    const acknowledged = shared.bytes[16..24];
    for (1..Shared.rounds + 1) |round| {
        const expected: u64 = @intCast(round);
        while (loadCoordinated(u64, acknowledged) != expected - 1) std.atomic.spinLoopHint();
        store(u64, payload, expected);
        const previous = exchangeAny(u64, ready, expected) orelse unreachable;
        try std.testing.expectEqual(expected - 1, previous);
    }
    consumer.join();
    try std.testing.expect(!shared.mismatch.load(.acquire));
    try std.testing.expect(buffer.isEmpty());
}

test "locked atomics retain width and do not overwrite neighboring bytes" {
    var bytes: [32]u8 align(16) = [_]u8{0xA5} ** 32;
    inline for (.{ u8, u16, u32, u64 }) |T| {
        const width = @sizeOf(T);
        const offset = 16 - width;
        const before = bytes[offset - 1];
        const after = bytes[offset + width];
        const initial: T = 3;
        const replacement: T = 7;
        store(T, bytes[offset..], initial);
        try std.testing.expectEqual(initial, exchange(T, bytes[offset..], replacement).?);
        try std.testing.expectEqual(replacement, load(T, bytes[offset..]));
        const mismatch = compareExchange(T, bytes[offset..], initial, 11).?;
        try std.testing.expect(!mismatch.exchanged);
        try std.testing.expectEqual(@as(u64, 7), mismatch.previous);
        const matched = compareExchange(T, bytes[offset..], replacement, 9).?;
        try std.testing.expect(matched.exchanged);
        try std.testing.expectEqual(@as(u64, 7), matched.previous);
        const old = fetchAdd(T, bytes[offset..], 2).?;
        try std.testing.expectEqual(@as(u64, 9), old);
        const updated = update(T, bytes[offset..], .bit_xor, 0x3, false).?;
        try std.testing.expectEqual(@as(u64, 11), updated.previous);
        try std.testing.expectEqual(@as(u64, 8), updated.value);
        try std.testing.expectEqual(before, bytes[offset - 1]);
        try std.testing.expectEqual(after, bytes[offset + width]);
    }
}

test "locked negation writes the two's-complement value at each supported width" {
    var bytes: [16]u8 align(8) = [_]u8{0xA5} ** 16;
    inline for (.{ u8, u16, u32, u64 }) |T| {
        const offset = 8 - @sizeOf(T);
        const initial: T = 3;
        store(T, bytes[offset..], initial);
        const result = update(T, bytes[offset..], .neg, 0, false).?;
        const expected = 0 -% initial;
        try std.testing.expectEqual(@as(u64, initial), result.previous);
        try std.testing.expectEqual(@as(u64, expected), result.value);
        try std.testing.expectEqual(expected, load(T, bytes[offset..]));
    }
}

test "locked atomics reject unaligned operands instead of splitting them" {
    var bytes: [24]u8 align(8) = [_]u8{0} ** 24;
    try std.testing.expect(exchange(u16, bytes[1..], 1) == null);
    try std.testing.expect(compareExchange(u32, bytes[2..], 0, 1) == null);
    try std.testing.expect(fetchAdd(u64, bytes[4..], 1) == null);
    try std.testing.expect(update(u32, bytes[1..], .add, 1, false) == null);
}

test "coordinated locked scalar operations preserve legal unaligned operands" {
    var bytes: [24]u8 align(8) = [_]u8{0xA5} ** 24;
    const previous_mode = setCoordinatedGuestAccess(true);
    defer _ = setCoordinatedGuestAccess(previous_mode);
    const address = bytes[3..];
    const before = bytes[2];
    const after = bytes[11];
    store(u64, address, 7);
    try std.testing.expectEqual(@as(?u64, 7), exchangeAny(u64, address, 9));
    const mismatch = compareExchangeAny(u64, address, 7, 11).?;
    try std.testing.expect(!mismatch.exchanged);
    try std.testing.expectEqual(@as(u64, 9), mismatch.previous);
    const matched = compareExchangeAny(u64, address, 9, 11).?;
    try std.testing.expect(matched.exchanged);
    try std.testing.expectEqual(@as(u64, 9), matched.previous);
    const updated = updateAny(u64, address, .add, 2, false).?;
    try std.testing.expectEqual(@as(u64, 11), updated.previous);
    try std.testing.expectEqual(@as(u64, 13), updated.value);
    try std.testing.expectEqual(@as(u64, 13), fetchAddAny(u64, address, 1).?);
    try std.testing.expectEqual(@as(u64, 14), load(u64, address));
    try std.testing.expectEqual(before, bytes[2]);
    try std.testing.expectEqual(after, bytes[11]);
}

test "coordinated locked updates serialize across overlapping operand widths" {
    const Shared = struct {
        bytes: [64]u8 align(64) = [_]u8{0} ** 64,

        fn addWide(shared: *@This()) void {
            const previous_mode = setCoordinatedGuestAccess(true);
            defer _ = setCoordinatedGuestAccess(previous_mode);
            for (0..10_000) |_| {
                _ = updateAny(u64, shared.bytes[0..8], .add, 1, false) orelse unreachable;
            }
        }
    };

    var shared = Shared{};
    const previous_mode = setCoordinatedGuestAccess(true);
    defer _ = setCoordinatedGuestAccess(previous_mode);
    const wide = try std.Thread.spawn(.{}, Shared.addWide, .{&shared});
    for (0..10_000) |_| {
        _ = updateAny(u32, shared.bytes[0..4], .add, 1, false) orelse unreachable;
    }
    wide.join();
    const observed = load(u64, shared.bytes[0..8]);
    try std.testing.expectEqual(@as(u64, 20_000), observed);
}

test "mixed-width locked RMWs serialize with ordinary coordinated stores" {
    const Shared = struct {
        const rounds = 20_000;
        bytes: [64]u8 align(64) = [_]u8{0} ** 64,
        ready: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

        fn addWide(shared: *@This()) void {
            const previous_mode = setCoordinatedGuestAccess(true);
            defer _ = setCoordinatedGuestAccess(previous_mode);
            _ = shared.ready.fetchAdd(1, .release);
            while (shared.ready.load(.acquire) != 2) std.atomic.spinLoopHint();
            for (0..rounds) |_| {
                _ = updateAny(u64, shared.bytes[0..8], .add, 1, false) orelse unreachable;
            }
        }
    };

    var shared = Shared{};
    const previous_mode = setCoordinatedGuestAccess(true);
    defer _ = setCoordinatedGuestAccess(previous_mode);
    const wide = try std.Thread.spawn(.{}, Shared.addWide, .{&shared});
    _ = shared.ready.fetchAdd(1, .release);
    while (shared.ready.load(.acquire) != 2) std.atomic.spinLoopHint();
    for (1..Shared.rounds + 1) |value| {
        // The 32-bit store updates the upper half of the same 64-bit word
        // that the peer changes with a locked update. Both paths must enter
        // the same exclusive stripe or the CAS can replay a stale upper half.
        storeCoordinated(u32, shared.bytes[4..8], @intCast(value));
    }
    wide.join();
    try std.testing.expectEqual(
        (@as(u64, Shared.rounds) << 32) | Shared.rounds,
        loadCoordinated(u64, shared.bytes[0..8]),
    );
}

test "cmpxchg16b is one aligned 128-bit transaction" {
    var bytes: [48]u8 align(16) = [_]u8{0xA5} ** 48;
    const operand = bytes[16..32];
    const before = bytes[15];
    const after = bytes[32];
    store(u64, operand[0..], 0x1122_3344_5566_7788);
    store(u64, operand[8..], 0x99AA_BBCC_DDEE_FF00);
    const expected: u128 = (@as(u128, 0x99AA_BBCC_DDEE_FF00) << 64) | 0x1122_3344_5566_7788;
    const desired: u128 = (@as(u128, 0xAABB_CCDD_EEFF_0011) << 64) | 0x2233_4455_6677_8899;
    const result = compareExchange128(operand, expected, desired).?;
    try std.testing.expect(result.exchanged);
    try std.testing.expectEqual(expected, result.previous);
    try std.testing.expectEqual(@as(u64, 0x2233_4455_6677_8899), load(u64, operand[0..]));
    try std.testing.expectEqual(@as(u64, 0xAABB_CCDD_EEFF_0011), load(u64, operand[8..]));
    try std.testing.expectEqual(before, bytes[15]);
    try std.testing.expectEqual(after, bytes[32]);
    try std.testing.expect(compareExchange128(bytes[1..], expected, desired) == null);
}

test "ordered bulk copy preserves both overlap directions" {
    var bytes: [48]u8 align(16) = undefined;
    for (&bytes, 0..) |*byte, index| byte.* = @truncate(index);
    copy(bytes[8..32], bytes[0..24]);
    for (0..24) |index| try std.testing.expectEqual(@as(u8, @truncate(index)), bytes[8 + index]);
    copy(bytes[0..24], bytes[8..32]);
    for (0..24) |index| try std.testing.expectEqual(@as(u8, @truncate(index)), bytes[index]);
    var misaligned: [24]u8 align(8) = undefined;
    copy(misaligned[1..18], bytes[3..20]);
    try std.testing.expectEqualSlices(u8, bytes[3..20], misaligned[1..18]);
}

test "ordered bulk fill preserves size and boundary bytes" {
    var bytes: [32]u8 align(8) = [_]u8{0xA5} ** 32;
    fill(bytes[3..29], 0x5A);
    try std.testing.expectEqual(@as(u8, 0xA5), bytes[2]);
    try std.testing.expectEqual(@as(u8, 0xA5), bytes[29]);
    for (bytes[3..29]) |byte| try std.testing.expectEqual(@as(u8, 0x5A), byte);
}

test "forced coordination snapshots bounded strings outside executor mode" {
    var source: [96]u8 align(64) = [_]u8{'x'} ** 96;
    @memcpy(source[4..14], "guest-text");
    source[14] = 0;
    var snapshot: [24]u8 = [_]u8{0xA5} ** 24;

    const previous_mode = setCoordinatedGuestAccess(false);
    defer _ = setCoordinatedGuestAccess(previous_mode);

    try std.testing.expectEqual(@as(?usize, 14), findCStringEndCoordinated(source[0..32]));
    copyInCoordinated(snapshot[0..14], source[0..14]);
    try std.testing.expectEqualSlices(u8, source[0..14], snapshot[0..14]);
    try std.testing.expectEqual(@as(?usize, 14), findByteCoordinated(source[0..32], 0));

    storeCoordinated(u64, source[32..40], 0x1122_3344_5566_7788);
    try std.testing.expectEqual(@as(u64, 0x1122_3344_5566_7788), loadCoordinated(u64, source[32..40]));
}

test "coordinated equality compares backing directly and forwards this executor's stores" {
    var bytes: [64]u8 align(64) = [_]u8{0} ** 64;
    @memcpy(bytes[10..14], &[_]u8{ 1, 2, 3, 4 });
    var scratch: [16]u8 = undefined;
    var buffer: StoreBuffer = .{};
    const prior_access = setCoordinatedGuestAccess(true);
    defer _ = setCoordinatedGuestAccess(prior_access);
    const prior_buffer = setActiveStoreBuffer(null);
    defer _ = setActiveStoreBuffer(prior_buffer);

    try std.testing.expect(eqlCoordinated(&.{ 1, 2, 3, 4 }, bytes[10..14], &scratch));
    try std.testing.expect(!eqlCoordinated(&.{ 1, 2, 3, 5 }, bytes[10..14], &scratch));
    try std.testing.expect(eqlCodeBytes(&.{ 1, 2, 3, 4 }, bytes[10..14], &scratch));
    try std.testing.expect(!eqlCodeBytes(&.{ 1, 2, 3, 5 }, bytes[10..14], &scratch));
    try std.testing.expect(!eqlCodeBytes(&.{ 1, 2, 3, 4, 5 }, bytes[10..14], &scratch));

    _ = setActiveStoreBuffer(&buffer);
    defer _ = buffer.drain();
    // A bound but empty buffer is the normal worker state and must still
    // take the no-copy path. Pending stores to an unrelated range also do not
    // require forwarding into this comparison.
    try std.testing.expect(eqlCoordinated(&.{ 1, 2, 3, 4 }, bytes[10..14], &scratch));
    buffer.enqueue(@intFromPtr(&bytes[32]), &.{9});
    try std.testing.expect(eqlCoordinated(&.{ 1, 2, 3, 4 }, bytes[10..14], &scratch));
    _ = buffer.drain();
    buffer.enqueue(@intFromPtr(&bytes[11]), &.{9});
    try std.testing.expect(eqlCoordinated(&.{ 1, 9, 3, 4 }, bytes[10..14], &scratch));
    try std.testing.expect(!eqlCoordinated(&.{ 1, 2, 3, 4 }, bytes[10..14], &scratch));
    // The lock-free comparison forwards this executor's own queued code
    // write exactly as the coordinated one does.
    try std.testing.expect(eqlCodeBytes(&.{ 1, 9, 3, 4 }, bytes[10..14], &scratch));
    try std.testing.expect(!eqlCodeBytes(&.{ 1, 2, 3, 4 }, bytes[10..14], &scratch));
}

test "coordinated equality uses aligned atomic chunks at every offset and cache-line edge" {
    var bytes: [128]u8 align(64) = undefined;
    for (&bytes, 0..) |*byte, index| byte.* = @truncate(index *% 37 +% 11);
    var scratch: [16]u8 = undefined;
    var expected: [15]u8 = undefined;
    const prior_access = setCoordinatedGuestAccess(true);
    defer _ = setCoordinatedGuestAccess(prior_access);
    const prior_buffer = setActiveStoreBuffer(null);
    defer _ = setActiveStoreBuffer(prior_buffer);

    for (0..8) |offset| {
        const source = bytes[16 + offset ..][0..expected.len];
        @memcpy(&expected, source);
        try std.testing.expect(eqlCoordinated(&expected, source, &scratch));
        for (0..expected.len) |changed_index| {
            var changed = expected;
            changed[changed_index] ^= 0x80;
            try std.testing.expect(!eqlCoordinated(&changed, source, &scratch));
        }
    }

    const crossing = bytes[61..76];
    @memcpy(&expected, crossing);
    try std.testing.expect(eqlCoordinated(&expected, crossing, &scratch));
    expected[7] ^= 0x40;
    try std.testing.expect(!eqlCoordinated(&expected, crossing, &scratch));
}

test "backing snapshot excludes the current executor store-buffer overlay" {
    var source: [8]u8 align(8) = [_]u8{0x41} ** 8;
    var buffer = StoreBuffer{};
    const previous_buffer = setActiveStoreBuffer(&buffer);
    defer _ = setActiveStoreBuffer(previous_buffer);

    buffer.enqueue(@intFromPtr(&source[0]), &.{0x65});
    var visible: [1]u8 = undefined;
    var backing: [1]u8 = undefined;
    copyInCoordinated(&visible, source[0..1]);
    copyBackingCoordinated(&backing, source[0..1]);

    try std.testing.expectEqual(@as(u8, 0x65), visible[0]);
    try std.testing.expectEqual(@as(u8, 0x41), backing[0]);
    try std.testing.expectEqual(@as(usize, 1), buffer.pendingCount());
    _ = buffer.drain();
}

test "forced coordinated bulk copy and fill use the guest access path" {
    const previous_mode = setCoordinatedGuestAccess(false);
    defer _ = setCoordinatedGuestAccess(previous_mode);

    var source: [73]u8 align(64) = undefined;
    for (&source, 0..) |*byte, index| byte.* = @truncate(index * 3);
    var destination: [96]u8 align(64) = [_]u8{0xA5} ** 96;
    copyCoordinated(destination[7..80], source[0..73]);
    try std.testing.expectEqualSlices(u8, source[0..73], destination[7..80]);
    fillCoordinated(destination[1..6], 0x3C);
    for (destination[1..6]) |byte| try std.testing.expectEqual(@as(u8, 0x3C), byte);
    try std.testing.expectEqual(@as(u8, 0xA5), destination[0]);
    try std.testing.expectEqual(@as(u8, 0xA5), destination[6]);
}
