const std = @import("std");

pub const PointerKind = enum {
    opaque_identity,
    guest_backed,
    borrowed_guest,
    owned_guest,
    caller_storage,
};

pub const Policy = struct {
    kind: PointerKind,
    may_dereference: bool,
    may_execute: bool = false,
    may_compare: bool = true,
    may_pass_to_modeled_api: bool = true,
    owner: []const u8,
};

pub const Record = struct {
    address: u64,
    size: u64,
    policy: Policy,
};

pub const Firewall = struct {
    allocator: std.mem.Allocator,
    records: std.AutoHashMap(u64, Record),
    violations: u64 = 0,
    denied_min: u64 = std.math.maxInt(u64),
    denied_max: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) Firewall {
        return .{ .allocator = allocator, .records = std.AutoHashMap(u64, Record).init(allocator) };
    }

    pub fn deinit(self: *Firewall) void {
        self.records.deinit();
        self.* = undefined;
    }

    pub fn register(self: *Firewall, address: u64, size: u64, policy: Policy) bool {
        if (address == 0 or size == 0) return false;
        const end = std.math.add(u64, address, size) catch return false;
        self.records.put(address, .{ .address = address, .size = size, .policy = policy }) catch return false;
        if (!policy.may_dereference) {
            self.denied_min = @min(self.denied_min, address);
            self.denied_max = @max(self.denied_max, end);
        }
        return true;
    }

    pub fn policyAt(self: *const Firewall, address: u64) ?Policy {
        if (self.records.get(address)) |record| return record.policy;
        var iterator = self.records.valueIterator();
        while (iterator.next()) |record| {
            const end = std.math.add(u64, record.address, record.size) catch continue;
            if (address >= record.address and address < end) return record.policy;
        }
        return null;
    }

    pub fn allowDereference(self: *Firewall, address: u64) bool {
        if (self.mayDereference(address)) return true;
        self.violations +|= 1;
        return false;
    }

    pub fn mayDereference(self: *const Firewall, address: u64) bool {
        // Ordinary guest pointers never enter the sparse opaque-handle range.
        // Keep the emulator's hottest address-translation path O(1).
        if (address < self.denied_min or address >= self.denied_max) return true;
        const policy = self.policyAt(address) orelse return true;
        return policy.may_dereference;
    }
};

pub fn policyForSymbol(symbol: []const u8) ?Policy {
    if (std.mem.startsWith(u8, symbol, "_CFStringCreate") or
        std.mem.startsWith(u8, symbol, "_CFDictionaryCreate") or
        std.mem.indexOf(u8, symbol, "basic_ifstream") != null or
        std.mem.indexOf(u8, symbol, "basic_ostream") != null or
        std.mem.indexOf(u8, symbol, "basic_istream") != null)
    {
        return .{ .kind = .owned_guest, .may_dereference = true, .owner = symbol };
    }
    if (std.mem.startsWith(u8, symbol, "_objc_getClass") or std.mem.startsWith(u8, symbol, "_sel_registerName")) {
        return .{ .kind = .opaque_identity, .may_dereference = false, .owner = symbol };
    }
    return null;
}

test "opaque identities cannot cross the dereference firewall" {
    var firewall = Firewall.init(std.testing.allocator);
    defer firewall.deinit();
    try std.testing.expect(firewall.register(0xFFFF_0000, 8, .{ .kind = .opaque_identity, .may_dereference = false, .owner = "selector" }));
    try std.testing.expect(!firewall.mayDereference(0xFFFF_0000));
    try std.testing.expect(!firewall.allowDereference(0xFFFF_0000));
    try std.testing.expectEqual(@as(u64, 1), firewall.violations);
    try std.testing.expect(policyForSymbol("_CFStringCreateWithCString").?.may_dereference);
}
