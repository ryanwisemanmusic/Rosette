const std = @import("std");
const sparse_virtual_memory = @import("sparse_virtual_memory.zig");

/// Returns the byte count for a size variant. Accepts any enum type with
/// .bits8, .bits16, .bits32, .bits64 variants (e.g. x64_decoder.OperandSize).
pub fn bytesForSize(size: anytype) u8 {
    return switch (size) {
        .bits8 => 1,
        .bits16 => 2,
        .bits32 => 4,
        .bits64 => 8,
    };
}

/// Write an f64 value as an x87 extended-precision 80-bit float (10 bytes).
pub fn writeExtendedFloat80(destination: []u8, value: f64) void {
    std.debug.assert(destination.len >= 10);
    @memset(destination[0..10], 0);
    const bits: u64 = @bitCast(value);
    const sign: u16 = if ((bits >> 63) != 0) 0x8000 else 0;
    const fraction = bits & 0x000F_FFFF_FFFF_FFFF;
    const exponent: u16 = @truncate((bits >> 52) & 0x7FF);
    if (exponent == 0 and fraction == 0) return;
    if (exponent == 0x7FF) {
        const significand: u64 = if (fraction == 0) 0x8000_0000_0000_0000 else 0xC000_0000_0000_0000;
        std.mem.writeInt(u64, destination[0..8], significand, .little);
        std.mem.writeInt(u16, destination[8..10], sign | 0x7FFF, .little);
        return;
    }
    var significand: u64 = 0;
    var unbiased: i32 = 0;
    if (exponent == 0) {
        const shift: u6 = @intCast(@clz(fraction));
        significand = fraction << shift;
        unbiased = -1011 - @as(i32, shift);
    } else {
        significand = (fraction | (@as(u64, 1) << 52)) << 11;
        unbiased = @as(i32, exponent) - 1023;
    }
    std.mem.writeInt(u64, destination[0..8], significand, .little);
    std.mem.writeInt(u16, destination[8..10], sign | @as(u16, @intCast(unbiased + 16383)), .little);
}

/// Read an x87 extended-precision 80-bit float (10 bytes) to f64.
pub fn readExtendedFloat80(source: []const u8) f64 {
    std.debug.assert(source.len >= 10);
    const significand = std.mem.readInt(u64, source[0..8], .little);
    const sign_exponent = std.mem.readInt(u16, source[8..10], .little);
    const negative = (sign_exponent & 0x8000) != 0;
    const exponent = sign_exponent & 0x7FFF;
    const sign_bit: u64 = if (negative) @as(u64, 1) << 63 else 0;
    if (exponent == 0x7FFF) {
        const special_bits = if ((significand & 0x7FFF_FFFF_FFFF_FFFF) == 0)
            sign_bit | 0x7FF0_0000_0000_0000
        else
            sign_bit | 0x7FF8_0000_0000_0000;
        return @bitCast(special_bits);
    }
    if (significand == 0) return @bitCast(sign_bit);
    const unbiased: i32 = if (exponent == 0) -16382 else @as(i32, exponent) - 16383;
    if (unbiased > 1023) return @bitCast(sign_bit | 0x7FF0_0000_0000_0000);
    if (unbiased >= -1022) {
        const binary64_exponent: u64 = @intCast(unbiased + 1023);
        const fraction = (significand >> 11) & 0x000F_FFFF_FFFF_FFFF;
        return @bitCast(sign_bit | (binary64_exponent << 52) | fraction);
    }
    if (unbiased < -1074) return @bitCast(sign_bit);
    const subnormal_shift: u6 = @intCast(-1011 - unbiased);
    const fraction = significand >> subnormal_shift;
    return @bitCast(sign_bit | (fraction & 0x000F_FFFF_FFFF_FFFF));
}

/// Holds the raw memory state that memory-access functions operate on.
/// All pointer fields reference state owned by the parent (e.g. MachOState).
/// Uses const pointers so that read-only callers work without @constCast.
/// Fields `memory_writes` and `initializer_memory` are reserved for future
/// write-method extraction and are omitted here until needed.
pub const MemoryState = struct {
    allocator: std.mem.Allocator,
    mem: []u8,
    mem_base: u64,
    mem_size: u64,
    heap_next: u64,
    page_permissions: []u8,
    sparse_memory: *const sparse_virtual_memory.Manager,
};

/// Read 1 byte from guest memory. `off` is the result of translateGuest,
/// or null if the address was not accessible.
pub fn read8(state: *const MemoryState, vaddr: u64, off: ?u64) u8 {
    if (state.sparse_memory.bytesConst(vaddr, 1)) |bytes| return bytes[0];
    const offset = off orelse return 0;
    return state.mem[offset];
}

/// Read 2 bytes (little-endian) from guest memory.
pub fn read16(state: *const MemoryState, vaddr: u64, off: ?u64) u16 {
    if (state.sparse_memory.bytesConst(vaddr, 2)) |bytes| return std.mem.readInt(u16, bytes[0..2], .little);
    const offset = off orelse return 0;
    return std.mem.readInt(u16, state.mem[offset..][0..2], .little);
}

/// Read 4 bytes (little-endian) from guest memory.
pub fn read32(state: *const MemoryState, vaddr: u64, off: ?u64) u32 {
    if (state.sparse_memory.bytesConst(vaddr, 4)) |bytes| return std.mem.readInt(u32, bytes[0..4], .little);
    const offset = off orelse return 0;
    return std.mem.readInt(u32, state.mem[offset..][0..4], .little);
}

/// Read 8 bytes (little-endian) from guest memory.
pub fn read64(state: *const MemoryState, vaddr: u64, off: ?u64) u64 {
    if (state.sparse_memory.bytesConst(vaddr, 8)) |bytes| return std.mem.readInt(u64, bytes[0..8], .little);
    const offset = off orelse return 0;
    return std.mem.readInt(u64, state.mem[offset..][0..8], .little);
}

/// Callback context for readMemVal. Uses an opaque context pointer so that
/// the parent (e.g. MachOState) can pass `self` without closure allocation.
/// `size` is passed as a u64 byte count to keep the function pointer concrete.
pub const ReadMemValCallbacks = struct {
    ctx: *anyopaque,
    recoverVtable: *const fn (ctx: *anyopaque, addr: u64, suspect: u64) ?u64,
    recordAccess: *const fn (ctx: *anyopaque, addr: u64, size_bytes: u8, final_value: u64) void,
};

/// Read a multi-size value from guest memory with vtable recovery support.
/// The core memory-access logic is here; MachOState-specific side effects
/// (vtable recovery tracing, access recording) are delegated to callbacks.
/// Callbacks receive an opaque `ctx` pointer (typically `*MachOState`).
pub fn readMemVal(
    state: *const MemoryState,
    vaddr: u64,
    size: anytype,
    off: ?u64,
    callbacks: ReadMemValCallbacks,
) u64 {
    const byte_count = bytesForSize(size);
    if (state.sparse_memory.bytesConst(vaddr, byte_count)) |storage| {
        var value: u64 = switch (size) {
            .bits8 => storage[0],
            .bits16 => std.mem.readInt(u16, storage[0..2], .little),
            .bits32 => std.mem.readInt(u32, storage[0..4], .little),
            .bits64 => std.mem.readInt(u64, storage[0..8], .little),
        };
        if (size == .bits64 and value < 0x1000) {
            if (callbacks.recoverVtable(callbacks.ctx, vaddr, value)) |recovered| {
                if (@constCast(state.sparse_memory).bytes(vaddr, @sizeOf(u64), true)) |mutable_storage| {
                    std.mem.writeInt(u64, mutable_storage[0..8], recovered, .little);
                    value = recovered;
                }
            }
        } else if (size == .bits64) {
            // Non-zero corruption recovery: even when value >= 0x1000, ask
            // the callback whether this looks like a corrupted vtable pointer
            // (e.g. overwritten with a kernel-space address or scrambled offset).
            if (callbacks.recoverVtable(callbacks.ctx, vaddr, value)) |recovered| {
                if (@constCast(state.sparse_memory).bytes(vaddr, @sizeOf(u64), true)) |mutable_storage| {
                    std.mem.writeInt(u64, mutable_storage[0..8], recovered, .little);
                    value = recovered;
                }
            }
        }
        callbacks.recordAccess(callbacks.ctx, vaddr, byte_count, value);
        return value;
    }
    const offset = off orelse return 0;
    if (offset + byte_count > state.mem.len) return 0;
    var value: u64 = switch (size) {
        .bits8 => state.mem[offset],
        .bits16 => std.mem.readInt(u16, state.mem[offset..][0..2], .little),
        .bits32 => std.mem.readInt(u32, state.mem[offset..][0..4], .little),
        .bits64 => std.mem.readInt(u64, state.mem[offset..][0..8], .little),
    };
    if (size == .bits64 and value < 0x1000) {
        if (callbacks.recoverVtable(callbacks.ctx, vaddr, value)) |recovered| {
            std.mem.writeInt(u64, state.mem[offset..][0..8], recovered, .little);
            value = recovered;
        }
    } else if (size == .bits64) {
        // Non-zero corruption recovery path.
        if (callbacks.recoverVtable(callbacks.ctx, vaddr, value)) |recovered| {
            std.mem.writeInt(u64, state.mem[offset..][0..8], recovered, .little);
            value = recovered;
        }
    }
    callbacks.recordAccess(callbacks.ctx, vaddr, byte_count, value);
    return value;
}

test {
    const TestSize = enum { bits8, bits16, bits32, bits64 };
    try std.testing.expectEqual(@as(u8, 1), bytesForSize(TestSize.bits8));
    try std.testing.expectEqual(@as(u8, 2), bytesForSize(TestSize.bits16));
    try std.testing.expectEqual(@as(u8, 4), bytesForSize(TestSize.bits32));
    try std.testing.expectEqual(@as(u8, 8), bytesForSize(TestSize.bits64));

    _ = readMemVal;
    _ = ReadMemValCallbacks;

    var encoded: [10]u8 = undefined;
    const durations = [_]f64{ 0.001, 0.010, 0.100, 0.500, -0.001 };
    for (durations) |duration| {
        writeExtendedFloat80(&encoded, duration);
        try std.testing.expectApproxEqAbs(duration, readExtendedFloat80(&encoded), 1e-15);
    }
}

test "scalar read accepts sparse backing without a contiguous image offset" {
    var sparse = sparse_virtual_memory.Manager.init(std.testing.allocator);
    defer sparse.deinit();

    const base: u64 = 0x37D7_C0000;
    const fixed_anonymous_private: u32 = 0x0010 | 0x1000 | 0x0002;
    try std.testing.expect(sparse.mapFixed(
        base,
        sparse_virtual_memory.PAGE_64K,
        3,
        fixed_anonymous_private,
        -1,
        0,
    ));
    const storage = sparse.bytes(base + 0x120, @sizeOf(u32), true) orelse
        return error.TestUnexpectedResult;
    std.mem.writeInt(u32, storage[0..4], 0xA1B2_C3D4, .little);

    var image: [1]u8 = .{0};
    var permissions: [1]u8 = .{0};
    const state = MemoryState{
        .allocator = std.testing.allocator,
        .mem = &image,
        .mem_base = 0,
        .mem_size = image.len,
        .heap_next = 0,
        .page_permissions = &permissions,
        .sparse_memory = &sparse,
    };
    const Size = enum { bits8, bits16, bits32, bits64 };
    const callbacks = ReadMemValCallbacks{
        .ctx = @ptrCast(&image),
        .recoverVtable = struct {
            fn recover(_: *anyopaque, _: u64, _: u64) ?u64 {
                return null;
            }
        }.recover,
        .recordAccess = struct {
            fn record(_: *anyopaque, _: u64, _: u8, _: u64) void {}
        }.record,
    };

    try std.testing.expectEqual(
        @as(u64, 0xA1B2_C3D4),
        readMemVal(&state, base + 0x120, Size.bits32, null, callbacks),
    );
}
