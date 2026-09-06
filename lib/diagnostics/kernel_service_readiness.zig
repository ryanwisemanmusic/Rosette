//! Which kernel services the title has actually demanded, and which of those
//! are on the path between a command and a frame.
//!
//! The defect this exists for
//! --------------------------
//! A missing or stubbed kernel export is not automatically a graphics
//! blocker, and it is not automatically harmless either. The 2026-08-31 run
//! shows imports and audio middleware activity after the GPU probe, and a
//! title can sit waiting on a non-graphics service before it submits its next
//! frame — which looks exactly like a graphics stall from the graphics side.
//!
//! Building out every kernel service on suspicion is the expensive mistake.
//! The cheap one is demanding evidence: an export becomes P0 only when the
//! guest program counter or the wait graph puts it on the producer-to-frame
//! dependency chain. Until then it is inventory.

const std = @import("std");

/// The service families a title can wait on.
pub const Domain = enum(u8) {
    threading = 0,
    synchronization = 1,
    timers_and_dpc = 2,
    memory = 3,
    filesystem = 4,
    xam_title = 5,
    input = 6,
    audio = 7,
    network = 8,
    video = 9,
    shader_texture_storage = 10,

    pub fn label(self: Domain) []const u8 {
        return switch (self) {
            .threading => "threading",
            .synchronization => "synchronization",
            .timers_and_dpc => "timers-and-dpc",
            .memory => "memory",
            .filesystem => "filesystem",
            .xam_title => "xam-title",
            .input => "input",
            .audio => "audio",
            .network => "network",
            .video => "video",
            .shader_texture_storage => "shader-texture-storage",
        };
    }

    /// Whether this family is on the path from a title's command to a frame by
    /// construction. The rest become relevant only when the wait graph puts
    /// them there.
    pub fn structurallyOnFrameChain(self: Domain) bool {
        return switch (self) {
            .video, .synchronization, .memory, .timers_and_dpc, .shader_texture_storage => true,
            else => false,
        };
    }
};

pub const domain_count: usize = @typeInfo(Domain).@"enum".fields.len;

/// How much a service has been shown to work.
pub const State = enum(u8) {
    /// Nothing has asked for it.
    not_yet_demanded = 0,
    /// The guest called it and nothing checked the result.
    observed = 1,
    /// Called, and its result or side effect was checked.
    called_and_validated = 2,
    /// Called, and the implementation is a stub.
    called_but_stubbed = 3,
    /// Called and not implemented.
    missing = 4,

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .not_yet_demanded => "not-yet-demanded",
            .observed => "observed",
            .called_and_validated => "called-and-validated",
            .called_but_stubbed => "called-but-stubbed",
            .missing => "MISSING",
        };
    }

    pub fn describe(self: State) []const u8 {
        return switch (self) {
            .not_yet_demanded => "the title has not called this. It is inventory, not work",
            .observed => "the title called it and nothing checked what it got back. The call happened; whether it did the right thing is unknown",
            .called_and_validated => "the title called it and its result or side effect was checked",
            .called_but_stubbed => "the title called it and the implementation makes something up. Whether that matters depends on whether the title reads it or waits on it",
            .missing => "the title called an export that is not implemented. Whatever it expected did not happen",
        };
    }

    pub fn satisfied(self: State) bool {
        return self == .called_and_validated;
    }
};

/// What to do about one service.
pub const Priority = enum(u8) {
    /// On the dependency chain and not working. Blocks the frame.
    blocking,
    /// On the chain and working.
    satisfied_on_chain,
    /// Demanded, off the chain, not working. Real and not urgent.
    background,
    /// Not demanded.
    inventory,

    pub fn label(self: Priority) []const u8 {
        return switch (self) {
            .blocking => "BLOCKING",
            .satisfied_on_chain => "satisfied-on-chain",
            .background => "background",
            .inventory => "inventory",
        };
    }

    pub fn isWork(self: Priority) bool {
        return self == .blocking;
    }
};

pub const max_services: usize = 48;

/// One export.
pub const Service = struct {
    domain: Domain = .threading,
    /// Ordinal or name hash, whichever the caller has.
    identifier: u32 = 0,
    state: State = .not_yet_demanded,
    calls: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    /// Set when the wait graph or a guest program counter puts this service
    /// between the producer and a frame. Evidence, not suspicion.
    on_dependency_chain: bool = false,
    /// The object a waiter is parked on because of this service, when there
    /// is one.
    blocked_object: u64 = 0,

    pub fn priority(self: Service) Priority {
        if (self.calls == 0) return .inventory;
        const on_chain = self.on_dependency_chain or self.domain.structurallyOnFrameChain();
        if (!on_chain) return .background;
        return if (self.state.satisfied()) .satisfied_on_chain else .blocking;
    }
};

pub const Summary = struct {
    services: usize = 0,
    dropped: u64 = 0,
    demanded: usize = 0,
    blocking: usize = 0,
    background: usize = 0,
    inventory: usize = 0,
    stubbed: usize = 0,
    missing: usize = 0,
    by_domain: [domain_count]u64 = [_]u64{0} ** domain_count,

    /// The list the audit says is the only one worth shortening.
    pub fn actionable(self: Summary) usize {
        return self.blocking;
    }
};

pub const Inventory = struct {
    services: [max_services]Service = [_]Service{.{}} ** max_services,
    count: usize = 0,
    dropped: u64 = 0,
    by_domain: [domain_count]u64 = [_]u64{0} ** domain_count,

    fn find(self: *Inventory, domain: Domain, identifier: u32) ?*Service {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const entry = &self.services[index];
            if (entry.domain == domain and entry.identifier == identifier) return entry;
        }
        return null;
    }

    pub fn intern(self: *Inventory, domain: Domain, identifier: u32) ?*Service {
        if (self.find(domain, identifier)) |existing| return existing;
        if (self.count >= max_services) {
            self.dropped +|= 1;
            return null;
        }
        const slot = &self.services[self.count];
        self.count += 1;
        slot.* = .{ .domain = domain, .identifier = identifier };
        self.by_domain[@intFromEnum(domain)] +|= 1;
        return slot;
    }

    pub fn noteCall(self: *Inventory, domain: Domain, identifier: u32, state: State, step: u64) void {
        const slot = self.intern(domain, identifier) orelse return;
        if (slot.calls == 0) slot.first_step = step;
        slot.calls +|= 1;
        slot.last_step = step;
        // A weaker state never overwrites a stronger one: a validated call
        // followed by an unchecked one is still validated.
        if (@intFromEnum(state) > @intFromEnum(slot.state) or slot.state == .not_yet_demanded) {
            slot.state = state;
        }
    }

    /// Put a service on the dependency chain, with the object that puts it
    /// there. This is what promotes a background service to blocking, and it
    /// requires evidence rather than a hunch.
    pub fn placeOnChain(self: *Inventory, domain: Domain, identifier: u32, blocked_object: u64) bool {
        const slot = self.find(domain, identifier) orelse return false;
        slot.on_dependency_chain = true;
        slot.blocked_object = blocked_object;
        return true;
    }

    pub fn retained(self: *const Inventory) []const Service {
        return self.services[0..self.count];
    }

    pub fn summary(self: *const Inventory) Summary {
        var out = Summary{ .services = self.count, .dropped = self.dropped, .by_domain = self.by_domain };
        for (self.retained()) |service| {
            if (service.calls != 0) out.demanded += 1;
            switch (service.priority()) {
                .blocking => out.blocking += 1,
                .background => out.background += 1,
                .inventory => out.inventory += 1,
                .satisfied_on_chain => {},
            }
            switch (service.state) {
                .called_but_stubbed => out.stubbed += 1,
                .missing => out.missing += 1,
                else => {},
            }
        }
        return out;
    }

    /// The service to fix next: a missing one on the chain before a stubbed
    /// one, and neither before something nothing has demanded.
    pub fn nextSubject(self: *const Inventory) ?Service {
        var best: ?Service = null;
        for (self.retained()) |service| {
            if (service.priority() != .blocking) continue;
            if (best == null or @intFromEnum(service.state) > @intFromEnum(best.?.state)) best = service;
        }
        return best;
    }

    pub fn fingerprint(self: *const Inventory) u64 {
        const totals = self.summary();
        var hash: u64 = totals.services;
        hash = hash *% 31 +% totals.blocking;
        hash = hash *% 31 +% totals.missing;
        return hash;
    }
};

test "a stubbed service off the chain is background rather than work" {
    var inventory = Inventory{};
    inventory.noteCall(.audio, 0x100, .called_but_stubbed, 1000);
    const service = inventory.retained()[0];
    try std.testing.expectEqual(Priority.background, service.priority());
    try std.testing.expect(!service.priority().isWork());
    try std.testing.expectEqual(@as(usize, 0), inventory.summary().actionable());
    try std.testing.expectEqual(@as(usize, 1), inventory.summary().stubbed);
}

// The audit's rule: an export becomes P0 only when evidence puts it on the
// producer-to-frame chain.
test "evidence promotes a background service to blocking" {
    var inventory = Inventory{};
    inventory.noteCall(.audio, 0x100, .called_but_stubbed, 1000);
    try std.testing.expectEqual(@as(usize, 0), inventory.summary().blocking);

    try std.testing.expect(inventory.placeOnChain(.audio, 0x100, 0x4000_4BF4));
    const service = inventory.retained()[0];
    try std.testing.expectEqual(Priority.blocking, service.priority());
    try std.testing.expect(service.priority().isWork());
    try std.testing.expectEqual(@as(u64, 0x4000_4BF4), service.blocked_object);
    try std.testing.expectEqual(@as(usize, 1), inventory.summary().actionable());
}

test "a video export is on the chain by construction" {
    var inventory = Inventory{};
    inventory.noteCall(.video, 0x1D5, .called_but_stubbed, 1000);
    try std.testing.expectEqual(Priority.blocking, inventory.retained()[0].priority());
    try std.testing.expect(Domain.video.structurallyOnFrameChain());
    try std.testing.expect(!Domain.network.structurallyOnFrameChain());
}

test "a validated call on the chain is satisfied and not work" {
    var inventory = Inventory{};
    inventory.noteCall(.synchronization, 0x50, .called_and_validated, 1000);
    try std.testing.expectEqual(Priority.satisfied_on_chain, inventory.retained()[0].priority());
    try std.testing.expectEqual(@as(usize, 0), inventory.summary().blocking);
    try std.testing.expect(State.called_and_validated.satisfied());
}

test "a weaker later observation never downgrades a validated service" {
    var inventory = Inventory{};
    inventory.noteCall(.memory, 0x20, .called_and_validated, 1000);
    inventory.noteCall(.memory, 0x20, .observed, 2000);
    const service = inventory.retained()[0];
    try std.testing.expectEqual(State.called_and_validated, service.state);
    try std.testing.expectEqual(@as(u64, 2), service.calls);
    try std.testing.expectEqual(@as(u64, 1000), service.first_step);
    try std.testing.expectEqual(@as(u64, 2000), service.last_step);
}

test "nothing demanded is inventory rather than a gap" {
    var inventory = Inventory{};
    _ = inventory.intern(.network, 0x300).?;
    const service = inventory.retained()[0];
    try std.testing.expectEqual(Priority.inventory, service.priority());
    try std.testing.expectEqual(State.not_yet_demanded, service.state);
    try std.testing.expectEqual(@as(usize, 1), inventory.summary().inventory);
    try std.testing.expect(inventory.nextSubject() == null);
    try std.testing.expect(std.mem.indexOf(u8, State.not_yet_demanded.describe(), "not work") != null);
}

test "a missing export on the chain is the next subject over a stubbed one" {
    var inventory = Inventory{};
    inventory.noteCall(.video, 0x1D5, .called_but_stubbed, 1000);
    inventory.noteCall(.video, 0x1C6, .missing, 2000);
    const subject = inventory.nextSubject().?;
    try std.testing.expectEqual(State.missing, subject.state);
    try std.testing.expectEqual(@as(u32, 0x1C6), subject.identifier);
    try std.testing.expectEqual(@as(usize, 2), inventory.summary().blocking);
    try std.testing.expectEqual(@as(usize, 1), inventory.summary().missing);
}

test "placing an unknown service on the chain is refused" {
    var inventory = Inventory{};
    try std.testing.expect(!inventory.placeOnChain(.audio, 0x999, 1));
}

test "the inventory is bounded and every domain and state is named" {
    var inventory = Inventory{};
    var index: u32 = 0;
    while (index < max_services + 4) : (index += 1) {
        _ = inventory.intern(.threading, index);
    }
    try std.testing.expectEqual(max_services, inventory.retained().len);
    try std.testing.expectEqual(@as(u64, 4), inventory.dropped);

    inline for (@typeInfo(Domain).@"enum".fields) |field| {
        const which: Domain = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    inline for (@typeInfo(State).@"enum".fields) |field| {
        const which: State = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
        try std.testing.expect(which.describe().len != 0);
    }
}
