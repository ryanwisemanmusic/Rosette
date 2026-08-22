//! Big-endian guest memory for the PowerPC path.
//!
//! Guest memory holds Xbox 360 bytes in Xbox 360 order. The host is
//! little-endian, so every multi-byte access converts. That conversion is the
//! single most consequential line in this module: a missed swap produces a
//! plausible-looking value that is wrong in a way that only shows up several
//! thousand instructions later, and a doubled swap does the same. Both are
//! avoided the same way - one place converts, and the byte-reversed
//! instructions (`lwbrx`, `sthbrx`, ...) are the *only* callers that ask for
//! the unconverted reading.
//!
//! Bounds are checked on every access. An out-of-range effective address is a
//! guest fault with an address to report, not a host segfault: the difference
//! decides whether a diagnosis names a guest bug or a Rosette bug.

const std = @import("std");

pub const Fault = error{
    /// The effective address is outside the mapped guest window.
    OutOfBounds,
    /// The access crosses the end of the mapped guest window.
    Truncated,
    /// The access violates an alignment the instruction requires.
    Unaligned,
};

/// A flat view of the guest's physical address space.
///
/// The Xbox 360 address space is 32-bit, so an effective address is a u32 and
/// the whole space fits inside one host mapping. `origin` is the guest address
/// that `base[0]` corresponds to, which lets a caller map a window rather than
/// the whole space - useful in tests, and required when Rosette maps the guest
/// image somewhere other than guest address zero.
pub const Memory = struct {
    base: [*]u8,
    len: usize,
    origin: u32 = 0,

    pub fn fromSlice(bytes: []u8, origin: u32) Memory {
        return .{ .base = bytes.ptr, .len = bytes.len, .origin = origin };
    }

    pub fn contains(self: Memory, address: u32, size: usize) bool {
        if (address < self.origin) return false;
        const offset = address - self.origin;
        if (offset >= self.len) return false;
        return self.len - offset >= size;
    }

    fn slice(self: Memory, address: u32, comptime size: usize) Fault![]u8 {
        if (address < self.origin) return Fault.OutOfBounds;
        const offset = address - self.origin;
        if (offset >= self.len) return Fault.OutOfBounds;
        if (self.len - offset < size) return Fault.Truncated;
        return self.base[offset .. offset + size];
    }

    /// Read a big-endian guest value: the normal PowerPC load.
    pub fn read(self: Memory, comptime T: type, address: u32) Fault!T {
        const size = @sizeOf(T);
        const bytes = try self.slice(address, size);
        return std.mem.readInt(T, bytes[0..size], .big);
    }

    /// Read with the bytes taken in host order: `lhbrx`, `lwbrx`, `ldbrx`.
    /// These instructions exist precisely to read little-endian data, so
    /// swapping here would be swapping twice.
    pub fn readReversed(self: Memory, comptime T: type, address: u32) Fault!T {
        const size = @sizeOf(T);
        const bytes = try self.slice(address, size);
        return std.mem.readInt(T, bytes[0..size], .little);
    }

    /// Write a big-endian guest value: the normal PowerPC store.
    pub fn write(self: Memory, comptime T: type, address: u32, value: T) Fault!void {
        const size = @sizeOf(T);
        const bytes = try self.slice(address, size);
        std.mem.writeInt(T, bytes[0..size], value, .big);
    }

    /// Write with the bytes left in host order: `sthbrx`, `stwbrx`, `stdbrx`.
    pub fn writeReversed(self: Memory, comptime T: type, address: u32, value: T) Fault!void {
        const size = @sizeOf(T);
        const bytes = try self.slice(address, size);
        std.mem.writeInt(T, bytes[0..size], value, .little);
    }

    /// Read a 128-bit vector as four big-endian words, lane 0 highest.
    pub fn readVector(self: Memory, address: u32) Fault![4]u32 {
        const bytes = try self.slice(address, 16);
        var out: [4]u32 = undefined;
        inline for (0..4) |lane| {
            out[lane] = std.mem.readInt(u32, bytes[lane * 4 ..][0..4], .big);
        }
        return out;
    }

    pub fn writeVector(self: Memory, address: u32, value: [4]u32) Fault!void {
        const bytes = try self.slice(address, 16);
        inline for (0..4) |lane| {
            std.mem.writeInt(u32, bytes[lane * 4 ..][0..4], value[lane], .big);
        }
    }

    /// Zero a cache block, as `dcbz` and `dcbz128` do.
    pub fn zeroBlock(self: Memory, address: u32, size: u32) Fault!void {
        const aligned = address & ~(size - 1);
        if (aligned < self.origin) return Fault.OutOfBounds;
        const offset = aligned - self.origin;
        if (offset >= self.len) return Fault.OutOfBounds;
        if (self.len - offset < size) return Fault.Truncated;
        @memset(self.base[offset .. offset + size], 0);
    }

    /// Fetch an instruction word. Instructions are always big-endian and always
    /// four-byte aligned; an unaligned PC is a control-flow fault, so it is
    /// reported rather than silently rounded down.
    pub fn fetch(self: Memory, address: u32) Fault!u32 {
        if (address & 3 != 0) return Fault.Unaligned;
        return self.read(u32, address);
    }
};

test "a normal load converts from guest byte order" {
    var buf = [_]u8{ 0x12, 0x34, 0x56, 0x78, 0, 0, 0, 0 };
    const mem = Memory.fromSlice(&buf, 0x8200_0000);
    try std.testing.expectEqual(@as(u32, 0x12345678), try mem.read(u32, 0x8200_0000));
    try std.testing.expectEqual(@as(u16, 0x1234), try mem.read(u16, 0x8200_0000));
    try std.testing.expectEqual(@as(u8, 0x12), try mem.read(u8, 0x8200_0000));
}

test "a byte-reversed load does not convert twice" {
    var buf = [_]u8{ 0x12, 0x34, 0x56, 0x78 };
    const mem = Memory.fromSlice(&buf, 0x8200_0000);
    // lwz sees the big-endian reading; lwbrx sees the little-endian one.
    try std.testing.expectEqual(@as(u32, 0x12345678), try mem.read(u32, 0x8200_0000));
    try std.testing.expectEqual(@as(u32, 0x78563412), try mem.readReversed(u32, 0x8200_0000));
}

test "stores round-trip through their own load" {
    var buf = [_]u8{0} ** 16;
    const mem = Memory.fromSlice(&buf, 0x8200_0000);
    try mem.write(u32, 0x8200_0000, 0xAABBCCDD);
    try std.testing.expectEqual(@as(u8, 0xAA), buf[0]);
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), try mem.read(u32, 0x8200_0000));

    try mem.writeReversed(u32, 0x8200_0004, 0xAABBCCDD);
    try std.testing.expectEqual(@as(u8, 0xDD), buf[4]);
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), try mem.readReversed(u32, 0x8200_0004));
}

test "a vector keeps lane zero at the high end" {
    var buf = [_]u8{0} ** 16;
    const mem = Memory.fromSlice(&buf, 0);
    try mem.writeVector(0, .{ 1, 2, 3, 4 });
    try std.testing.expectEqual(@as(u8, 1), buf[3]);
    try std.testing.expectEqual(@as(u8, 4), buf[15]);
    try std.testing.expectEqual([4]u32{ 1, 2, 3, 4 }, try mem.readVector(0));
}

test "an out-of-range address faults instead of reaching host memory" {
    var buf = [_]u8{0} ** 8;
    const mem = Memory.fromSlice(&buf, 0x8200_0000);
    try std.testing.expectError(Fault.OutOfBounds, mem.read(u32, 0x8100_0000));
    try std.testing.expectError(Fault.OutOfBounds, mem.read(u32, 0x8200_0008));
    // The last word fits exactly; one byte past it does not.
    _ = try mem.read(u32, 0x8200_0004);
    try std.testing.expectError(Fault.Truncated, mem.read(u32, 0x8200_0005));
}

test "an unaligned instruction fetch is a fault, not a rounded-down fetch" {
    var buf = [_]u8{ 0x60, 0, 0, 0, 0x60, 0, 0, 0 };
    const mem = Memory.fromSlice(&buf, 0x8200_0000);
    try std.testing.expectEqual(@as(u32, 0x60000000), try mem.fetch(0x8200_0000));
    try std.testing.expectError(Fault.Unaligned, mem.fetch(0x8200_0002));
}

test "dcbz zeroes the block containing its address" {
    var buf = [_]u8{0xFF} ** 64;
    const mem = Memory.fromSlice(&buf, 0);
    try mem.zeroBlock(40, 32);
    try std.testing.expectEqual(@as(u8, 0xFF), buf[31]);
    try std.testing.expectEqual(@as(u8, 0), buf[32]);
    try std.testing.expectEqual(@as(u8, 0), buf[63]);
}
