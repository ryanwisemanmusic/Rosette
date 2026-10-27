const std = @import("std");
const runtime_abi = @import("runtime_abi_handshake");
const bridge = @import("bridge_heap");
const reg_trace = @import("../register-tracing/runtime.zig");

pub const process_heap_handle: u32 = 0x00F0_0000;
const heap_base: u32 = 0x0200_0000;
const heap_align: u32 = 16;

var initialized = false;
var next_ptr: u32 = heap_base;
var allocations: ?std.AutoHashMap(u32, u32) = null;

fn ensureState() *std.AutoHashMap(u32, u32) {
    if (allocations == null) {
        allocations = std.AutoHashMap(u32, u32).init(std.heap.page_allocator);
    }
    initialized = true;
    return &allocations.?;
}

fn alignUp(value: u32, alignment: u32) u32 {
    return (value + alignment - 1) & ~(alignment - 1);
}

fn reportShadow(scope: []const u8, action: bridge.HeapAction, seq: u64, heap_handle: u32, address: u32, size: u32, flags: u32, result: u32) void {
    var target = bridge.makeHeapEvent(.arm64, seq, scope, action);
    target.heap_handle = heap_handle;
    target.address = address;
    target.size = size;
    target.flags = flags;
    target.result = result;
    bridge.reportHeapEvent(target, reg_trace.emitOperationContext);
}

fn reportSource(scope: []const u8, action: bridge.HeapAction, seq: u64, heap_handle: u32, address: u32, size: u32, flags: u32, result: u32) void {
    var source = bridge.makeHeapEvent(.x86, seq, scope, action);
    source.heap_handle = heap_handle;
    source.address = address;
    source.size = size;
    source.flags = flags;
    source.result = result;
    bridge.reportHeapEvent(source, reg_trace.emitOperationContext);
    reportShadow(scope, action, seq, heap_handle, address, size, flags, result);
}

pub fn getProcessHeap(scope: []const u8) u32 {
    _ = ensureState();
    const seq = reg_trace.currentSequence();
    runtime_abi.common.writeLine(
        "[heap-trace][x86][get_process_heap] scope={s} seq={d} heap=0x{x}\n",
        .{ scope, seq, process_heap_handle },
    );
    reportSource(scope, .get_process_heap, seq, process_heap_handle, 0, 0, 0, process_heap_handle);
    return process_heap_handle;
}

pub fn alloc(scope: []const u8, heap_handle: u32, flags: u32, size: u32) u32 {
    const map = ensureState();
    if (heap_handle != process_heap_handle) {
        runtime_abi.common.violation(
            "x86-heap-trace",
            "invalid_heap_handle",
            "scope={s} alloc requested on unknown heap=0x{x}",
            .{ scope, heap_handle },
        );
    }

    const seq = reg_trace.currentSequence();
    const aligned_ptr = alignUp(next_ptr, heap_align);
    const aligned_size = @max(alignUp(@max(size, 1), heap_align), heap_align);
    next_ptr = aligned_ptr + aligned_size;
    map.put(aligned_ptr, aligned_size) catch {
        runtime_abi.common.violation(
            "x86-heap-trace",
            "allocation_bookkeeping_failed",
            "scope={s} addr=0x{x} size=0x{x}",
            .{ scope, aligned_ptr, aligned_size },
        );
    };
    runtime_abi.common.writeLine(
        "[heap-trace][x86][alloc] scope={s} seq={d} heap=0x{x} addr=0x{x} size=0x{x} flags=0x{x}\n",
        .{ scope, seq, heap_handle, aligned_ptr, size, flags },
    );
    reportSource(scope, .alloc, seq, heap_handle, aligned_ptr, size, flags, aligned_ptr);
    return aligned_ptr;
}

pub fn free(scope: []const u8, heap_handle: u32, flags: u32, address: u32) bool {
    const map = ensureState();
    if (heap_handle != process_heap_handle) {
        runtime_abi.common.violation(
            "x86-heap-trace",
            "invalid_heap_handle",
            "scope={s} free requested on unknown heap=0x{x}",
            .{ scope, heap_handle },
        );
    }

    const removed = map.fetchRemove(address);
    if (address != 0 and removed == null) {
        runtime_abi.common.violation(
            "x86-heap-trace",
            "invalid_free",
            "scope={s} heap=0x{x} addr=0x{x} was never allocated",
            .{ scope, heap_handle, address },
        );
    }
    const seq = reg_trace.currentSequence();
    runtime_abi.common.writeLine(
        "[heap-trace][x86][free] scope={s} seq={d} heap=0x{x} addr=0x{x} flags=0x{x} result={d}\n",
        .{ scope, seq, heap_handle, address, flags, 1 },
    );
    reportSource(scope, .free, seq, heap_handle, address, 0, flags, 1);
    return true;
}

/// Return the original aligned size of an allocation owned by the synthetic
/// process heap. Win32 HeapSize reports SIZE_T(-1) for invalid blocks.
pub fn querySize(scope: []const u8, heap_handle: u32, flags: u32, address: u32) u32 {
    const map = ensureState();
    if (heap_handle != process_heap_handle or flags != 0) return std.math.maxInt(u32);
    const allocation_size = map.get(address) orelse return std.math.maxInt(u32);
    runtime_abi.common.writeLine(
        "[heap-trace][x86][size] scope={s} seq={d} heap=0x{x} addr=0x{x} size=0x{x} flags=0x{x}\n",
        .{ scope, reg_trace.currentSequence(), heap_handle, address, allocation_size, flags },
    );
    return allocation_size;
}

test "x86 heap runtime alloc/free roundtrip" {
    const heap_handle = getProcessHeap("heap-test");
    const addr = alloc("heap-test", heap_handle, 0, 32);
    try std.testing.expect(addr != 0);
    try std.testing.expectEqual(@as(u32, 32), querySize("heap-test", heap_handle, 0, addr));
    try std.testing.expectEqual(std.math.maxInt(u32), querySize("heap-test", heap_handle, 0, addr + 1));
    try std.testing.expect(free("heap-test", heap_handle, 0, addr));
}
