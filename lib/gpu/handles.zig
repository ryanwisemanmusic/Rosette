const std = @import("std");

pub const max_handles: usize = 512;

pub const Kind = enum(u8) {
    invalid = 0,
    session = 1,
    adapter = 2,
    device = 3,
    queue = 4,
    memory = 5,
    buffer = 6,
    image = 7,
    sampler = 8,
    command_buffer = 9,
    fence = 10,
    semaphore = 11,
    surface = 12,
    swapchain = 13,
    guest_mapping = 14,
};

pub const Handle = extern struct {
    raw: u64 = 0,

    const slot_mask: u64 = 0xFFFF;
    const generation_mask: u64 = 0x00FF_FFFF;

    pub fn isValid(self: Handle) bool {
        return self.raw != 0;
    }

    pub fn slot(self: Handle) usize {
        if (self.raw == 0) return max_handles;
        return @intCast((self.raw & slot_mask) - 1);
    }

    pub fn generation(self: Handle) u32 {
        return @intCast((self.raw >> 16) & generation_mask);
    }

    pub fn kind(self: Handle) Kind {
        return @enumFromInt(@as(u8, @truncate(self.raw >> 40)));
    }

    fn encode(slot_index: usize, generation_value: u32, handle_kind: Kind) Handle {
        return .{ .raw = @as(u64, @intCast(slot_index + 1)) |
            (@as(u64, generation_value & @as(u32, @intCast(generation_mask))) << 16) |
            (@as(u64, @intFromEnum(handle_kind)) << 40) };
    }
};

pub const ValidationError = error{
    InvalidHandle,
    OutOfRange,
    DeadHandle,
    StaleGeneration,
    WrongKind,
    WrongOwner,
    RegistryFull,
};

const Slot = struct {
    generation: u32 = 1,
    kind: Kind = .invalid,
    owner: u32 = 0,
    alive: bool = false,
};

pub const Registry = struct {
    slots: [max_handles]Slot = [_]Slot{.{}} ** max_handles,
    next_slot: usize = 0,
    live_count: usize = 0,

    pub fn allocate(self: *Registry, kind: Kind, owner: u32) ValidationError!Handle {
        if (kind == .invalid) return error.InvalidHandle;
        for (0..max_handles) |offset| {
            const index = (self.next_slot + offset) % max_handles;
            const slot = &self.slots[index];
            if (slot.alive) continue;
            slot.alive = true;
            slot.kind = kind;
            slot.owner = owner;
            if (slot.generation == 0) slot.generation = 1;
            self.next_slot = (index + 1) % max_handles;
            self.live_count += 1;
            return Handle.encode(index, slot.generation, kind);
        }
        return error.RegistryFull;
    }

    pub fn validate(self: *const Registry, handle: Handle, expected_kind: Kind, owner: u32) ValidationError!void {
        if (!handle.isValid()) return error.InvalidHandle;
        const index = handle.slot();
        if (index >= max_handles) return error.OutOfRange;
        const slot = self.slots[index];
        if (!slot.alive) return error.DeadHandle;
        if (slot.generation != handle.generation()) return error.StaleGeneration;
        if (slot.kind != handle.kind() or slot.kind != expected_kind) return error.WrongKind;
        if (slot.owner != owner) return error.WrongOwner;
    }

    pub fn ownerOf(self: *const Registry, handle: Handle) ValidationError!u32 {
        if (!handle.isValid()) return error.InvalidHandle;
        const index = handle.slot();
        if (index >= max_handles) return error.OutOfRange;
        const slot = self.slots[index];
        if (!slot.alive) return error.DeadHandle;
        if (slot.generation != handle.generation()) return error.StaleGeneration;
        if (slot.kind != handle.kind()) return error.WrongKind;
        return slot.owner;
    }

    pub fn handleAt(self: *const Registry, index: usize) ?Handle {
        if (index >= max_handles) return null;
        const slot = self.slots[index];
        if (!slot.alive) return null;
        return Handle.encode(index, slot.generation, slot.kind);
    }

    pub fn destroy(self: *Registry, handle: Handle, expected_kind: Kind, owner: u32) ValidationError!void {
        try self.validate(handle, expected_kind, owner);
        const slot = &self.slots[handle.slot()];
        slot.alive = false;
        slot.kind = .invalid;
        slot.owner = 0;
        slot.generation +%= 1;
        if (slot.generation == 0) slot.generation = 1;
        self.live_count -= 1;
    }
};

test "resource handles reject stale generations and cross-owner use" {
    var registry = Registry{};
    const first = try registry.allocate(.buffer, 7);
    try registry.validate(first, .buffer, 7);
    try std.testing.expectError(error.WrongOwner, registry.validate(first, .buffer, 8));
    try registry.destroy(first, .buffer, 7);
    try std.testing.expectError(error.DeadHandle, registry.validate(first, .buffer, 7));

    registry.next_slot = first.slot();
    const replacement = try registry.allocate(.buffer, 7);
    try std.testing.expectEqual(first.slot(), replacement.slot());
    try std.testing.expect(first.generation() != replacement.generation());
    try std.testing.expectError(error.StaleGeneration, registry.validate(first, .buffer, 7));
}

test "resource handles carry kind without exposing backend handles" {
    var registry = Registry{};
    const image = try registry.allocate(.image, 1);
    try std.testing.expectEqual(Kind.image, image.kind());
    try std.testing.expectError(error.WrongKind, registry.validate(image, .buffer, 1));
}
