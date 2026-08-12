//! A fake guest for the dynamic-cast tests.
//!
//! It implements the same duck-typed surface the Mach-O process state exposes —
//! `guestMemoryConst`, `guestCString`, `metadata`, and the executability oracle
//! the RTTI reader uses to tell a record from a vtable — so the tests exercise
//! the real code paths rather than a simplified stand-in.

const std = @import("std");

pub const Symbol = struct { name: []const u8 };

pub const Binding = struct { address: u64, name: []const u8 };

pub const SymbolAt = struct { address: u64, name: []const u8 };

pub const Metadata = struct {
    bindings: []const Binding = &.{},
    symbols: []const SymbolAt = &.{},

    pub fn nearestSymbol(self: Metadata, address: u64) ?Symbol {
        for (self.symbols) |symbol| {
            if (symbol.address == address) return .{ .name = symbol.name };
        }
        return null;
    }
};

/// Room for RTTI records low, names in the middle, and live objects above
/// 0x1000. Anything at or past the end models memory the guest never mapped.
pub const memory_size: usize = 0x2000;

pub const State = struct {
    mem: [memory_size]u8 = [_]u8{0} ** memory_size,
    metadata: Metadata = .{},
    /// Addresses at or above this are reported executable. Null models a state
    /// with no code mapped, which is also how a caller that cannot answer the
    /// question at all behaves.
    executable_from: ?u64 = null,

    pub fn isExecutableAddress(self: *const State, address: u64) bool {
        const threshold = self.executable_from orelse return false;
        return address >= threshold;
    }

    pub fn guestMemoryConst(self: *const State, address: u64, count: u64) ?[]const u8 {
        if (address >= self.mem.len) return null;
        const start: usize = @intCast(address);
        const len: usize = @intCast(count);
        if (len > self.mem.len - start) return null;
        return self.mem[start .. start + len];
    }

    pub fn guestCString(self: *const State, address: u64, max_len: usize) ?[]const u8 {
        if (address >= self.mem.len) return null;
        const start: usize = @intCast(address);
        const available = self.mem[start..@min(self.mem.len, start + max_len)];
        const end = std.mem.indexOfScalar(u8, available, 0) orelse available.len;
        return available[0..end];
    }

    pub fn read64(self: *const State, address: u64) u64 {
        const bytes = self.guestMemoryConst(address, 8) orelse return 0;
        return std.mem.readInt(u64, bytes[0..8], .little);
    }

    pub fn write64(self: *State, address: usize, value: u64) void {
        std.mem.writeInt(u64, self.mem[address..][0..8], value, .little);
    }

    pub fn write32(self: *State, address: usize, value: u32) void {
        std.mem.writeInt(u32, self.mem[address..][0..4], value, .little);
    }

    pub fn writeString(self: *State, address: usize, text: []const u8) void {
        @memcpy(self.mem[address..][0..text.len], text);
        self.mem[address + text.len] = 0;
    }

    /// Lay down a `type_info` record: vtable pointer, name pointer, name.
    pub fn writeTypeInfo(self: *State, address: usize, vtable: u64, name_address: usize, name: []const u8) void {
        self.write64(address, vtable);
        self.write64(address + 8, name_address);
        self.writeString(name_address, name);
    }

    /// Lay down an object whose vptr reaches a vtable carrying the standard
    /// `offset_to_top` / `type_info` prologue.
    pub fn writeObject(self: *State, object: usize, vtable: usize, offset_to_top: i64, dynamic_type: u64) void {
        self.write64(object, vtable);
        self.write64(vtable - 16, @bitCast(offset_to_top));
        self.write64(vtable - 8, dynamic_type);
    }

    /// Lay down a `__vmi_class_type_info` base list.
    pub fn writeVmi(self: *State, type_info: usize, flags: u32, bases: []const VmiBase) void {
        self.write32(type_info + 16, flags);
        self.write32(type_info + 20, @intCast(bases.len));
        for (bases, 0..) |base, index| {
            const entry = type_info + 24 + index * 16;
            self.write64(entry, base.type_info);
            self.write64(entry + 8, (@as(u64, @bitCast(base.offset)) << 8) | base.flags);
        }
    }
};

pub const VmiBase = struct {
    type_info: u64,
    offset: i64,
    flags: u64,
};
