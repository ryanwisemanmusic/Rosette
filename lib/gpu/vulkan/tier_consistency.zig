//! Where the real driver and the modelled layer meet, and why that seam breaks
//! things.
//!
//! Bringing a modelled Vulkan layer up to a real one is not a switch, it is a
//! migration — and during a migration the dangerous state is not "modelled" or
//! "real", it is **both at once on two facts that have to agree**.
//!
//! The failure that produced this module: buffers became real objects and their
//! memory *properties* were forwarded from the real device, while their memory
//! *requirements* were still answered synthetically with `memoryTypeBits = 1`.
//! Both halves worked. Neither was wrong on its own. But the caller intersects
//! one with the other — `memoryTypeBits & memory_types.host_visible` — and on
//! this platform memory type 0 is device-local and not host-visible, so every
//! upload allocation resolved to "no suitable memory type" and the GPU command
//! processor gave up during setup. The device-local allocation immediately
//! before it succeeded, which made the failure look selective and arbitrary.
//!
//! Nothing in the run could see that, because every subsystem was reporting on
//! itself and each one was healthy.
//!
//! ## The model
//!
//! Facets are the facts a Vulkan caller combines. Each is served at some tier.
//! A `Pair` says two facets are consumed together, and names what breaks when
//! they disagree. A split pair is a defect **whether or not anything has failed
//! yet** — it is a latent wrong answer waiting for the first caller to
//! intersect the two.
//!
//! ## Why "both modelled" is fine and "both real" is fine
//!
//! A wholly modelled stack is self-consistent: synthetic requirements against
//! synthetic properties agree by construction. A wholly real stack is
//! consistent because the driver is answering both. Only the seam is
//! dangerous, which is why this reports the seam and not the tier.

const std = @import("std");

/// A fact a Vulkan caller obtains and then combines with another.
pub const Facet = enum(u8) {
    /// `vkGetPhysicalDeviceMemoryProperties` — the device's memory types.
    memory_properties,
    /// `vkGetBufferMemoryRequirements` / `vkGetImageMemoryRequirements` — a
    /// resource's size, alignment and `memoryTypeBits`.
    memory_requirements,
    /// `vkAllocateMemory` — the allocation itself.
    device_memory,
    /// `vkMapMemory` — the pointer the caller writes through.
    memory_mapping,
    buffer_object,
    image_object,
    descriptor_set_layout,
    descriptor_set,
    pipeline_layout,
    pipeline,
    queue,
    surface_capabilities,
    surface_formats,
    surface_present_modes,
    swapchain,
    command_buffer,
    command_recording,
    queue_submission,
    presentation,

    pub fn label(self: Facet) []const u8 {
        return switch (self) {
            .memory_properties => "memory_properties",
            .memory_requirements => "memory_requirements",
            .device_memory => "device_memory",
            .memory_mapping => "memory_mapping",
            .buffer_object => "buffer_object",
            .image_object => "image_object",
            .descriptor_set_layout => "descriptor_set_layout",
            .descriptor_set => "descriptor_set",
            .pipeline_layout => "pipeline_layout",
            .pipeline => "pipeline",
            .queue => "queue",
            .surface_capabilities => "surface_capabilities",
            .surface_formats => "surface_formats",
            .surface_present_modes => "surface_present_modes",
            .swapchain => "swapchain",
            .command_buffer => "command_buffer",
            .command_recording => "command_recording",
            .queue_submission => "queue_submission",
            .presentation => "presentation",
        };
    }
};

pub const facet_count = @typeInfo(Facet).@"enum".fields.len;

pub const Tier = enum(u8) {
    /// Nothing has served this facet yet.
    unknown,
    /// Answered synthetically by this layer.
    modelled,
    /// Answered by the host driver.
    real,

    pub fn label(self: Tier) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .modelled => "modelled",
            .real => "real",
        };
    }
};

/// Two facets a caller combines, and what goes wrong when they come from
/// different tiers. The consequence is written per pair because "these
/// disagree" is not actionable and "the type bits are intersected with the
/// device's real types, so an upload allocation finds nothing" is.
pub const Pair = struct {
    left: Facet,
    right: Facet,
    consequence: []const u8,
};

pub const pairs = [_]Pair{
    .{
        .left = .memory_requirements,
        .right = .memory_properties,
        .consequence = "a caller intersects the requirement's memoryTypeBits with the device's memory types. Synthetic bits against real types pick a type the resource cannot use, or none at all — an upload allocation then fails while the device-local one beside it succeeds, which reads as an arbitrary driver refusal",
    },
    .{
        .left = .buffer_object,
        .right = .device_memory,
        .consequence = "a real buffer bound to modelled memory has nothing behind it, and a modelled buffer bound to real memory binds nothing. Either way the bind reports success and the first read returns whatever was already there",
    },
    .{
        .left = .image_object,
        .right = .device_memory,
        .consequence = "a real image bound to modelled memory samples uninitialised contents, which is a black or garbage frame rather than an error",
    },
    .{
        .left = .device_memory,
        .right = .memory_mapping,
        .consequence = "real memory with a modelled mapping hands the caller a pointer into guest memory that the device will never read, so every upload silently goes nowhere. Modelled memory with a real mapping hands the caller a host pointer the translated guest cannot write through",
    },
    .{
        .left = .descriptor_set_layout,
        .right = .pipeline_layout,
        .consequence = "a pipeline layout is built from descriptor set layout handles. Mixing tiers means the handles in the array are not objects the consuming side knows, so the layout describes bindings that do not exist",
    },
    .{
        .left = .pipeline,
        .right = .pipeline_layout,
        .consequence = "a real pipeline created against a modelled pipeline layout has descriptor and push-constant interfaces the driver cannot match; recording may succeed until the first draw validates the layout",
    },
    .{
        .left = .command_buffer,
        .right = .queue_submission,
        .consequence = "commands recorded into a real command buffer and submitted to a modelled queue never execute, and the submission reports success. This is the state a whole stack can sit in while every counter reads healthy",
    },
};

pub const Finding = enum(u8) {
    /// Nothing has been observed.
    unknown = 0,
    /// Every pair whose facets are both known agrees.
    consistent = 1,
    /// At least one pair is served at two different tiers.
    split = 2,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .consistent => "consistent",
            .split => "TIER_SPLIT",
        };
    }

    pub fn meaning(self: Finding) []const u8 {
        return switch (self) {
            .unknown => "no facet has been served yet, so there is no seam to report",
            .consistent => "every pair of facts a caller combines is served at one tier. A wholly modelled stack is self-consistent and so is a wholly real one; only the seam between them produces answers that are individually correct and jointly wrong",
            .split => "at least one pair of facts a caller combines is served at two different tiers. Both halves are individually correct, which is why nothing reports an error — the wrongness only appears where the caller intersects them, and it appears as an arbitrary refusal somewhere else entirely",
        };
    }
};

pub const Split = struct {
    pair: Pair,
    left_tier: Tier,
    right_tier: Tier,
};

pub const Ledger = struct {
    tiers: [facet_count]Tier = [_]Tier{.unknown} ** facet_count,
    /// Times a facet was served, per tier. A facet served both ways over a run
    /// is its own hazard: the answer depends on which path the caller took.
    modelled_serves: [facet_count]u64 = [_]u64{0} ** facet_count,
    real_serves: [facet_count]u64 = [_]u64{0} ** facet_count,

    pub fn note(self: *Ledger, facet: Facet, served_at: Tier) void {
        const index = @intFromEnum(facet);
        switch (served_at) {
            .modelled => self.modelled_serves[index] +|= 1,
            .real => self.real_serves[index] +|= 1,
            .unknown => return,
        }
        self.tiers[index] = served_at;
    }

    pub fn tier(self: *const Ledger, facet: Facet) Tier {
        return self.tiers[@intFromEnum(facet)];
    }

    /// Whether a facet has been answered both ways during this run. The tier
    /// field holds only the most recent answer, and a facet that flips is a
    /// caller-dependent result — which is worse than either tier alone.
    pub fn servedBothWays(self: *const Ledger, facet: Facet) bool {
        const index = @intFromEnum(facet);
        return self.modelled_serves[index] != 0 and self.real_serves[index] != 0;
    }

    pub fn splits(self: *const Ledger, out: []Split) []Split {
        var length: usize = 0;
        for (pairs) |pair| {
            if (length == out.len) break;
            const left = self.tier(pair.left);
            const right = self.tier(pair.right);
            if (left == .unknown or right == .unknown) continue;
            if (left == right) continue;
            out[length] = .{ .pair = pair, .left_tier = left, .right_tier = right };
            length += 1;
        }
        return out[0..length];
    }

    pub fn finding(self: *const Ledger) Finding {
        var any_known = false;
        for (self.tiers) |value| {
            if (value != .unknown) any_known = true;
        }
        if (!any_known) return .unknown;
        var buffer: [pairs.len]Split = undefined;
        return if (self.splits(&buffer).len != 0) .split else .consistent;
    }

    pub fn realCount(self: *const Ledger) u32 {
        var count: u32 = 0;
        for (self.tiers) |value| {
            if (value == .real) count += 1;
        }
        return count;
    }

    pub fn modelledCount(self: *const Ledger) u32 {
        var count: u32 = 0;
        for (self.tiers) |value| {
            if (value == .modelled) count += 1;
        }
        return count;
    }

    pub fn verdict(self: *const Ledger) []const u8 {
        return self.finding().meaning();
    }

    /// True when every facet is served real and none of them has ever been
    /// answered the other way.
    ///
    /// This is the condition under which the per-facet list carries nothing the
    /// header does not: there is no seam to locate, so nineteen lines saying
    /// `real` are the success case printing itself out. A facet that flipped
    /// tiers at any point is excluded even though its current tier is real —
    /// that is the caller-dependent case, and it is precisely what the list
    /// exists to show.
    pub fn whollyReal(self: *const Ledger) bool {
        for (self.tiers, 0..) |value, index| {
            if (value != .real) return false;
            if (self.modelled_serves[index] != 0) return false;
        }
        return true;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// The exact failure this module was written for.
test "real properties against modelled requirements is reported as the split" {
    var ledger = Ledger{};
    ledger.note(.memory_properties, .real);
    ledger.note(.memory_requirements, .modelled);

    try std.testing.expectEqual(Finding.split, ledger.finding());
    var buffer: [pairs.len]Split = undefined;
    const found = ledger.splits(&buffer);
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqual(Facet.memory_requirements, found[0].pair.left);
    try std.testing.expectEqual(Tier.modelled, found[0].left_tier);
    try std.testing.expectEqual(Tier.real, found[0].right_tier);
    try std.testing.expect(std.mem.indexOf(u8, found[0].pair.consequence, "upload allocation then fails") != null);
}

// A wholly modelled stack is self-consistent, and so is a wholly real one. The
// seam is the whole finding.
test "a stack at one tier is consistent whichever tier that is" {
    var modelled = Ledger{};
    inline for (@typeInfo(Facet).@"enum".fields) |field| {
        modelled.note(@enumFromInt(field.value), .modelled);
    }
    try std.testing.expectEqual(Finding.consistent, modelled.finding());
    try std.testing.expectEqual(@as(u32, facet_count), modelled.modelledCount());

    var real = Ledger{};
    inline for (@typeInfo(Facet).@"enum".fields) |field| {
        real.note(@enumFromInt(field.value), .real);
    }
    try std.testing.expectEqual(Finding.consistent, real.finding());
    try std.testing.expectEqual(@as(u32, facet_count), real.realCount());
    try std.testing.expect(std.mem.indexOf(u8, real.verdict(), "only the seam") != null);
}

// A pair with one side never served says nothing: the migration has not
// reached it, which is not the same as the two disagreeing.
test "a pair with an unserved side is not a split" {
    var ledger = Ledger{};
    ledger.note(.memory_properties, .real);
    var buffer: [pairs.len]Split = undefined;
    try std.testing.expectEqual(@as(usize, 0), ledger.splits(&buffer).len);
    try std.testing.expectEqual(Finding.consistent, ledger.finding());
}

// The state the run was actually in: buffers and layouts real, memory
// requirements and mapping still modelled.
test "the observed migration reports every seam it has, not just the first" {
    var ledger = Ledger{};
    ledger.note(.memory_properties, .real);
    ledger.note(.memory_requirements, .modelled);
    ledger.note(.buffer_object, .real);
    ledger.note(.device_memory, .real);
    ledger.note(.memory_mapping, .modelled);
    ledger.note(.descriptor_set_layout, .real);
    ledger.note(.pipeline_layout, .real);

    var buffer: [pairs.len]Split = undefined;
    const found = ledger.splits(&buffer);
    // requirements/properties and memory/mapping both split; buffer/memory and
    // layout/layout agree.
    try std.testing.expectEqual(@as(usize, 2), found.len);
    try std.testing.expectEqual(Facet.memory_requirements, found[0].pair.left);
    try std.testing.expectEqual(Facet.device_memory, found[1].pair.left);
    try std.testing.expect(std.mem.indexOf(u8, found[1].pair.consequence, "silently goes nowhere") != null);
}

// A facet answered both ways is worse than either: the result depends on which
// path the caller took to ask.
test "a facet served at both tiers is flagged even after it settles" {
    var ledger = Ledger{};
    ledger.note(.memory_requirements, .modelled);
    ledger.note(.memory_requirements, .real);
    try std.testing.expectEqual(Tier.real, ledger.tier(.memory_requirements));
    try std.testing.expect(ledger.servedBothWays(.memory_requirements));
    try std.testing.expect(!ledger.servedBothWays(.memory_properties));
}

test "an empty ledger reports no seam rather than consistency" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Finding.unknown, ledger.finding());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "no facet has been served") != null);
}

test "every facet, tier and pair explains itself" {
    inline for (@typeInfo(Facet).@"enum".fields) |field| {
        const facet: Facet = @enumFromInt(field.value);
        try std.testing.expect(facet.label().len > 0);
    }
    inline for (.{ Tier.unknown, Tier.modelled, Tier.real }) |value| {
        try std.testing.expect(value.label().len > 0);
    }
    inline for (.{ Finding.unknown, Finding.consistent, Finding.split }) |value| {
        try std.testing.expect(value.label().len > 0);
        try std.testing.expect(value.meaning().len > 40);
    }
    for (pairs) |pair| {
        try std.testing.expect(pair.consequence.len > 60);
        try std.testing.expect(pair.left != pair.right);
    }
}

test "a wholly real stack has no seam to print" {
    var ledger = Ledger{};
    try std.testing.expect(!ledger.whollyReal());
    inline for (@typeInfo(Facet).@"enum".fields) |field| {
        ledger.note(@enumFromInt(field.value), .real);
    }
    try std.testing.expect(ledger.whollyReal());
    try std.testing.expectEqual(@as(u32, facet_count), ledger.realCount());
}

test "a facet that flipped tiers is never collapsed away" {
    var ledger = Ledger{};
    inline for (@typeInfo(Facet).@"enum".fields) |field| {
        ledger.note(@enumFromInt(field.value), .real);
    }
    ledger.note(.queue, .modelled);
    ledger.note(.queue, .real);
    try std.testing.expectEqual(Tier.real, ledger.tier(.queue));
    try std.testing.expect(ledger.servedBothWays(.queue));
    try std.testing.expect(!ledger.whollyReal());
}
