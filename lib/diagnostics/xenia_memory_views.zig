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

/// Host projection used by Xenia's physical memory and physical-alias views.
/// The physical view is canonical; A/C/E aliases are fallback probes only.
pub const PhysicalProjection = enum(u8) {
    physical,
    a_virtual,
    c_virtual,
    e_virtual,
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

    /// The host address code that computes `virtual_membase_ + guest_address`
    /// reaches. Xenia's `virtual_membase_` is the mapping base itself (no
    /// bias), so on macOS this is a *different host page* than
    /// `virtualHostAddress` for the E000 physical-4K window, which applies the
    /// 4 KiB bias. The guest's own stores — e.g. a title's inline critical
    /// section spin on an exported lock — use exactly this form, and a watch
    /// armed only on the biased alias misses them.
    pub fn primaryUnbiasedHostAddress(self: *const Model, guest_address: u64) ?u64 {
        if (!self.ready() or guest_address > std.math.maxInt(u32)) return null;
        return std.math.add(u64, self.mapping_base, guest_address) catch null;
    }

    /// Equivalent to Xenia `Memory::TranslatePhysical`.
    pub fn physicalHostAddress(self: *const Model, physical_address: u64) ?u64 {
        if (!self.ready()) return null;
        const physical = physical_address & physical_mask;
        const base = std.math.add(u64, self.mapping_base, physical_view_offset) catch return null;
        return std.math.add(u64, base, physical) catch return null;
    }

    /// Resolve a physical byte address through one of Xenia's host-visible
    /// projections. Keep this conversion here so GPU handoff code cannot
    /// accidentally treat an Xbox physical address as a Rosetta host pointer.
    /// The E000 projection is expressed through virtualHostAddress so its
    /// documented 4 KiB macOS bias is applied exactly once.
    pub fn physicalProjectionHostAddress(
        self: *const Model,
        physical_address: u64,
        projection: PhysicalProjection,
    ) ?u64 {
        const physical = physical_address & physical_mask;
        return switch (projection) {
            .physical => self.physicalHostAddress(physical),
            .a_virtual => self.virtualHostAddress(0xA000_0000 + physical),
            .c_virtual => self.virtualHostAddress(0xC000_0000 + physical),
            .e_virtual => if (physical < physical_4k_bias)
                null
            else
                self.virtualHostAddress(physical_4k_virtual_base + physical - physical_4k_bias),
        };
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

test "the E000 window has a distinct unbiased membase page" {
    var model: Model = .{};
    _ = model.observeFixedFileView(0x34D890000, primary_view_length, 0, false);
    const biased = model.virtualHostAddress(0xFFCAB000).?;
    const unbiased = model.primaryUnbiasedHostAddress(0xFFCAB000).?;
    // TranslateVirtual adds the 4 KiB bias; membase-relative code does not,
    // and the two are 4 KiB apart — a different watch page. This is exactly
    // the split that let the zeroing store of VdHSIOCalibrationLock escape
    // provenance: it was watching the biased page while the guest wrote the
    // unbiased one.
    try std.testing.expectEqual(biased - 0x1000, unbiased);
    try std.testing.expect((biased & ~@as(u64, 0xFFF)) != (unbiased & ~@as(u64, 0xFFF)));
    // Ordinary virtual addresses outside the E000 window have no bias, so the
    // two forms agree there.
    try std.testing.expectEqual(
        model.virtualHostAddress(0x30002000).?,
        model.primaryUnbiasedHostAddress(0x30002000).?,
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

test "resolves physical memory through Xenia's canonical and alias projections" {
    var model: Model = .{};
    _ = model.observeFixedFileView(0x34D890000, primary_view_length, 0, false);
    const physical = 0x0510_C040;
    try std.testing.expectEqual(
        @as(?u64, 0x4529_9C040),
        model.physicalProjectionHostAddress(physical, .physical),
    );
    try std.testing.expectEqual(
        @as(?u64, 0x3F29_9C040),
        model.physicalProjectionHostAddress(physical, .a_virtual),
    );
    try std.testing.expectEqual(
        @as(?u64, 0x4129_9C040),
        model.physicalProjectionHostAddress(physical, .c_virtual),
    );
    try std.testing.expectEqual(
        @as(?u64, 0x4329_9C040),
        model.physicalProjectionHostAddress(physical, .e_virtual),
    );
    try std.testing.expect(
        model.physicalProjectionHostAddress(0xFFF, .e_virtual) == null,
    );
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
