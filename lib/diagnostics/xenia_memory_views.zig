//! Xenia's 32-bit Xbox address space as it is projected into the translated
//! Mach-O process.
//!
//! Xenia reserves one file-backed host window and maps several aliases of the
//! same Xbox physical memory into it.  Log messages name Xbox addresses, while
//! Rosette's sparse-memory and write-provenance systems are keyed by the host
//! virtual addresses used by the translated x86 code.  Treating an Xbox
//! address such as `0xFFCAB000` as a host address therefore makes valid memory
//! look unreadable and arms provenance on a page that no writer will touch.
//!
//! This module owns that boundary.  It learns the base from Xenia's first
//! fixed, file-backed 1 GiB view rather than assuming a process-specific
//! address, and exposes both the virtual and raw-physical aliases.  It does
//! not allocate or modify memory.

const std = @import("std");

pub const primary_view_length: u64 = 0x4000_0000;
pub const physical_view_offset: u64 = 0x1_0000_0000;
pub const physical_mask: u64 = 0x1FFF_FFFF;
pub const physical_4k_virtual_base: u64 = 0xE000_0000;
pub const physical_4k_bias: u64 = 0x1000;

pub const Discovery = enum(u8) {
    ignored,
    discovered,
    confirmed,
    conflicting,
};

pub const Model = struct {
    mapping_base: u64 = 0,
    observations: u64 = 0,
    conflicts: u64 = 0,

    /// Observe a successful native mmap.  Only Xenia's unmistakable primary
    /// memory view is accepted: fixed, file-backed, offset zero, exactly 1 GiB.
    pub fn observeFixedFileView(
        self: *Model,
        address: u64,
        length: u64,
        offset: u64,
        anonymous: bool,
    ) Discovery {
        if (address == 0 or length != primary_view_length or offset != 0 or anonymous) {
            return .ignored;
        }
        self.observations +|= 1;
        if (self.mapping_base == 0) {
            self.mapping_base = address;
            return .discovered;
        }
        if (self.mapping_base == address) return .confirmed;
        self.conflicts +|= 1;
        return .conflicting;
    }

    pub fn ready(self: *const Model) bool {
        return self.mapping_base != 0 and self.conflicts == 0;
    }

    /// Equivalent to Xenia `Memory::TranslateVirtual` on the macOS 16 KiB
    /// host-page layout.  The E000 physical-4K view carries Xenia's explicit
    /// 4 KiB bias.
    pub fn virtualHostAddress(self: *const Model, guest_address: u64) ?u64 {
        if (!self.ready() or guest_address > std.math.maxInt(u32)) return null;
        var address = std.math.add(u64, self.mapping_base, guest_address) catch return null;
        if (guest_address >= physical_4k_virtual_base) {
            address = std.math.add(u64, address, physical_4k_bias) catch return null;
        }
        return address;
    }

    /// Equivalent to Xenia `Memory::TranslatePhysical`.
    pub fn physicalHostAddress(self: *const Model, physical_address: u64) ?u64 {
        if (!self.ready()) return null;
        const physical = physical_address & physical_mask;
        const base = std.math.add(u64, self.mapping_base, physical_view_offset) catch return null;
        return std.math.add(u64, base, physical) catch return null;
    }

    /// Convert an E000 virtual alias to the physical address it represents.
    pub fn physicalAddressForVirtual(guest_address: u64) ?u64 {
        if (guest_address < physical_4k_virtual_base or guest_address > std.math.maxInt(u32)) return null;
        return (guest_address - physical_4k_virtual_base + physical_4k_bias) & physical_mask;
    }

    pub fn physicalAliasHostAddress(self: *const Model, guest_address: u64) ?u64 {
        return self.physicalHostAddress(physicalAddressForVirtual(guest_address) orelse return null);
    }
};

test "discovers Xenia primary memory view without hardcoding its placement" {
    var model: Model = .{};
    try std.testing.expectEqual(
        Discovery.ignored,
        model.observeFixedFileView(0x1000, primary_view_length, 0, true),
    );
    try std.testing.expectEqual(
        Discovery.discovered,
        model.observeFixedFileView(0x34D890000, primary_view_length, 0, false),
    );
    try std.testing.expect(model.ready());
    try std.testing.expectEqual(@as(u64, 0x34D890000), model.mapping_base);
}

test "translates observed VdHSIO virtual and physical aliases" {
    var model: Model = .{};
    _ = model.observeFixedFileView(0x34D890000, primary_view_length, 0, false);
    try std.testing.expectEqual(
        @as(?u64, 0x44D53C000),
        model.virtualHostAddress(0xFFCAB000),
    );
    try std.testing.expectEqual(
        @as(?u64, 0x1FCAC000),
        Model.physicalAddressForVirtual(0xFFCAB000),
    );
    try std.testing.expectEqual(
        @as(?u64, 0x46D53C000),
        model.physicalAliasHostAddress(0xFFCAB000),
    );
}

test "ordinary virtual addresses have no physical-view bias" {
    var model: Model = .{};
    _ = model.observeFixedFileView(0x34D890000, primary_view_length, 0, false);
    try std.testing.expectEqual(
        @as(?u64, 0x37D892000),
        model.virtualHostAddress(0x30002000),
    );
    try std.testing.expect(Model.physicalAddressForVirtual(0x30002000) == null);
}

test "a conflicting primary view fails closed" {
    var model: Model = .{};
    _ = model.observeFixedFileView(0x34D890000, primary_view_length, 0, false);
    try std.testing.expectEqual(
        Discovery.conflicting,
        model.observeFixedFileView(0x50D890000, primary_view_length, 0, false),
    );
    try std.testing.expect(!model.ready());
    try std.testing.expect(model.virtualHostAddress(0xFFCAB000) == null);
}
