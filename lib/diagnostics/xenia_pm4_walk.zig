//! Read-only PM4 provenance, including nested indirect buffers.
//!
//! The primary Xenos ring is not the whole command stream.  A Type-3
//! `INDIRECT_BUFFER` packet points at another guest-owned dword range, and
//! Xenia can execute draws from that range while a scan of the primary ring
//! correctly reports zero draw packets.  Treating that as "no draw" sends the
//! investigation to the wrong owner.
//!
//! This walker follows those references only for observation.  It never
//! executes a packet, changes a register, advances a pointer, or writes guest
//! memory.  The package layer owns the PM4 bit layout and bounds; this runtime
//! layer owns the optional guest-memory callback and the bounded history of
//! what was readable.

const std = @import("std");
const pm4 = @import("xenia_pm4_contract");
const register_map = @import("xenos_register_map");

pub const MemoryReadCallback = *const fn (context: *anyopaque, address: u32) ?u32;
pub const PacketClass = pm4.PacketClass;

pub const ReferenceStatus = enum(u8) {
    observed,
    unreadable,
    invalid,
    cycle,
    depth_limit,
    truncated,
    budget_limit,

    pub fn label(self: ReferenceStatus) []const u8 {
        return switch (self) {
            .observed => "observed",
            .unreadable => "unreadable",
            .invalid => "invalid",
            .cycle => "cycle",
            .depth_limit => "depth-limit",
            .truncated => "truncated",
            .budget_limit => "budget-limit",
        };
    }
};

pub const Reference = struct {
    depth: u8 = 0,
    opcode: u8 = 0,
    address: u32 = 0,
    size_dwords: u32 = 0,
    status: ReferenceStatus = .observed,
    /// The first dword address that could not be read while following this
    /// reference.  A missing address is different from a readable buffer
    /// whose contents contain only filler, so keep the boundary explicit.
    missing_address: ?u32 = null,
    packets: u32 = 0,
    draws: u32 = 0,
    swaps: u32 = 0,
    unknown: u32 = 0,
    words_read: u32 = 0,
};

pub const Summary = struct {
    root_packets: u32 = 0,
    nested_packets: u32 = 0,
    root_draw_packets: u32 = 0,
    nested_draw_packets: u32 = 0,
    root_swap_packets: u32 = 0,
    nested_swap_packets: u32 = 0,
    root_indirect_packets: u32 = 0,
    nested_indirect_packets: u32 = 0,
    draw_packets: u32 = 0,
    swap_packets: u32 = 0,
    indirect_packets: u32 = 0,
    wait_packets: u32 = 0,
    unknown_packets: u32 = 0,
    packets_walked: u32 = 0,
    words_read: u32 = 0,
    /// Register writes encoded by PM4 itself. Executor bookkeeping registers
    /// are intentionally absent so this structural account is comparable to
    /// the stateful decoder's command-intent counters.
    command_register_writes: u64 = 0,
    command_unclassified_register_writes: u64 = 0,
    command_out_of_range_register_writes: u64 = 0,
    /// Ordered fingerprint of every readable root and nested dword, including
    /// packet bodies. Two publications with the same opcode counts but
    /// different register values or draw parameters are not the same work.
    content_fingerprint: u64 = 0,
    packet_class_counts: [packet_class_count]u32 = [_]u32{0} ** packet_class_count,
    indirect_references: u32 = 0,
    readable_references: u32 = 0,
    unreadable_references: u32 = 0,
    invalid_references: u32 = 0,
    cycle_references: u32 = 0,
    depth_limited_references: u32 = 0,
    truncated_references: u32 = 0,
    budget_limited_references: u32 = 0,
    root_truncated: bool = false,
    packet_budget_exhausted: bool = false,

    pub fn hasDraw(self: Summary) bool {
        return self.draw_packets != 0;
    }

    pub fn hasSwap(self: Summary) bool {
        return self.swap_packets != 0;
    }

    pub fn hasNestedWork(self: Summary) bool {
        return self.nested_packets != 0;
    }
};

const max_packet_budget: u32 = 32 * 1024;
const max_depth: usize = pm4.max_indirect_depth;
const packet_class_count: usize = @typeInfo(pm4.PacketClass).@"enum".fields.len;

const RingSource = struct {
    bytes: []const u8,
    start_dword: u32,
    ring_dwords: u32,
};

const MemorySource = struct {
    context: *anyopaque,
    callback: MemoryReadCallback,
    address: u32,
};

const SourceRead = union(enum) {
    value: u32,
    unavailable: u32,
};

const SourceStatus = enum {
    complete,
    unreadable,
    truncated,
    budget_limit,
};

const SourceWalk = struct {
    status: SourceStatus,
    missing_address: ?u32 = null,
};

const Source = union(enum) {
    ring: RingSource,
    memory: MemorySource,
};

const ActiveRange = struct {
    address: u32,
    size_dwords: u32,
};

pub const Walker = struct {
    memory_context: ?*anyopaque = null,
    memory_callback: ?MemoryReadCallback = null,
    result: Summary = .{},
    references: [pm4.max_indirect_references]Reference = [_]Reference{.{}} ** pm4.max_indirect_references,
    reference_count: usize = 0,
    references_dropped: u64 = 0,
    active_ranges: [max_depth]ActiveRange = [_]ActiveRange{.{ .address = 0, .size_dwords = 0 }} ** max_depth,
    active_count: usize = 0,

    pub fn init(context: ?*anyopaque, callback: ?MemoryReadCallback) Walker {
        return .{
            .memory_context = context,
            .memory_callback = callback,
        };
    }

    /// Walk a root ring span.  `bytes` must contain the whole ring because the
    /// root cursor wraps; `count_dwords` is the bounded region being observed.
    pub fn walkRoot(
        self: *Walker,
        bytes: []const u8,
        start_dword: u32,
        count_dwords: u32,
        ring_dwords: u32,
    ) void {
        if (ring_dwords == 0 or @as(u64, ring_dwords) * 4 > bytes.len) {
            self.result.root_truncated = true;
            return;
        }
        _ = self.walkSource(.{ .ring = .{
            .bytes = bytes,
            .start_dword = start_dword,
            .ring_dwords = ring_dwords,
        } }, 0, true, @min(count_dwords, ring_dwords));
    }

    pub fn summary(self: *const Walker) Summary {
        return self.result;
    }

    pub fn referenceSlice(self: *const Walker) []const Reference {
        return self.references[0..self.reference_count];
    }

    pub fn droppedReferenceCount(self: *const Walker) u64 {
        return self.references_dropped;
    }

    fn readSource(self: *Walker, source: Source, index: u32) SourceRead {
        switch (source) {
            .ring => |ring| {
                if (ring.ring_dwords == 0 or index >= ring.ring_dwords) {
                    return .{ .unavailable = index };
                }
                const ring_index: u32 = @intCast((@as(u64, ring.start_dword) + index) % ring.ring_dwords);
                const offset = @as(usize, ring_index) * 4;
                if (offset + 4 > ring.bytes.len) return .{ .unavailable = ring_index * 4 };
                const value = std.mem.readInt(u32, ring.bytes[offset..][0..4], .big);
                self.noteReadableWord(value);
                return .{ .value = value };
            },
            .memory => |memory| {
                const address = @as(u64, memory.address) + @as(u64, index) * 4;
                if (address > std.math.maxInt(u32)) return .{ .unavailable = std.math.maxInt(u32) };
                if (memory.callback(memory.context, @intCast(address))) |value| {
                    self.noteReadableWord(value);
                    return .{ .value = value };
                }
                return .{ .unavailable = @intCast(address) };
            },
        }
    }

    fn noteReadableWord(self: *Walker, value: u32) void {
        self.result.words_read +|= 1;
        const seed = if (self.result.content_fingerprint == 0)
            @as(u64, 0xcbf29ce484222325)
        else
            self.result.content_fingerprint;
        self.result.content_fingerprint = (seed ^ value) *% 0x100000001b3;
    }

    fn walkSource(self: *Walker, source: Source, depth: u8, root: bool, available_dwords: u32) SourceWalk {
        const limit = if (root) available_dwords else @min(available_dwords, pm4.max_indirect_dwords);
        var cursor: u32 = 0;
        while (cursor < limit) {
            if (self.result.packets_walked >= max_packet_budget) {
                self.result.packet_budget_exhausted = true;
                return .{ .status = .budget_limit };
            }
            const header = switch (self.readSource(source, cursor)) {
                .value => |value| value,
                .unavailable => |address| {
                    if (root) self.result.root_truncated = true;
                    return .{
                        .status = if (!root and cursor == 0) .unreadable else .truncated,
                        .missing_address = if (root) null else address,
                    };
                },
            };
            if (pm4.isLikelyEmptyRing(header)) {
                cursor += 1;
                continue;
            }
            const packet = pm4.decode(header);
            const advance = packet.advance();
            if (advance == 0 or advance > limit - cursor) {
                if (root) {
                    self.result.root_truncated = true;
                }
                return .{ .status = .truncated };
            }

            // Classification uses the header, but publication identity must
            // include the packet body. Validate and fingerprint every dword so
            // a register-value-only change is unique and an unreadable body is
            // reported as truncation rather than a complete packet.
            var payload_prefix: [6]u32 = [_]u32{0} ** 6;
            var payload_prefix_count: usize = 0;
            var body = cursor + 1;
            while (body < cursor + advance) : (body += 1) {
                const value = switch (self.readSource(source, body)) {
                    .value => |value| value,
                    .unavailable => |address| {
                        if (root) self.result.root_truncated = true;
                        return .{
                            .status = .truncated,
                            .missing_address = if (root) null else address,
                        };
                    },
                };
                if (payload_prefix_count < payload_prefix.len) {
                    payload_prefix[payload_prefix_count] = value;
                    payload_prefix_count += 1;
                }
            }

            self.result.packets_walked +|= 1;
            if (root) self.result.root_packets +|= 1 else self.result.nested_packets +|= 1;
            self.noteRegisterIntent(header, packet, payload_prefix[0..payload_prefix_count]);
            switch (packet.packet_type) {
                .type0, .type1 => self.result.packet_class_counts[@intFromEnum(pm4.PacketClass.state)] +|= 1,
                .type2 => self.result.packet_class_counts[@intFromEnum(pm4.PacketClass.filler)] +|= 1,
                .type3 => {
                    const class = pm4.classifyOpcode(packet.opcode);
                    self.result.packet_class_counts[@intFromEnum(class)] +|= 1;
                    switch (class) {
                        .draw => {
                            self.result.draw_packets +|= 1;
                            if (root) self.result.root_draw_packets +|= 1 else self.result.nested_draw_packets +|= 1;
                        },
                        .emulator_extension => {
                            self.result.swap_packets +|= 1;
                            if (root) self.result.root_swap_packets +|= 1 else self.result.nested_swap_packets +|= 1;
                        },
                        .indirect => {
                            self.result.indirect_packets +|= 1;
                            if (root) self.result.root_indirect_packets +|= 1 else self.result.nested_indirect_packets +|= 1;
                            self.followIndirect(header, packet, depth, payload_prefix[0..payload_prefix_count]);
                        },
                        .wait => self.result.wait_packets +|= 1,
                        .unknown => self.result.unknown_packets +|= 1,
                        else => {},
                    }
                },
            }
            cursor += advance;
        }
        return .{ .status = .complete };
    }

    fn followIndirect(self: *Walker, header: u32, packet: pm4.Packet, depth: u8, payload: []const u32) void {
        const descriptor = pm4.decodeIndirectBuffer(header, payload) orelse {
            const reference_index = self.recordReference(.{
                .opcode = @enumFromInt(packet.opcode),
                .address = if (payload.len >= 1) payload[0] else 0,
                .size_dwords = if (payload.len >= 2) payload[1] & pm4.indirect_size_mask else 0,
                .control = if (payload.len >= 2) payload[1] & ~pm4.indirect_size_mask else 0,
            }, depth, .invalid, null);
            if (reference_index != null) self.result.invalid_references +|= 1;
            return;
        };
        const reference_index = self.recordReference(descriptor, depth, .observed, null) orelse return;
        if (!descriptor.aligned() or descriptor.size_dwords == 0) {
            self.setReferenceStatus(reference_index, .invalid);
            self.result.invalid_references +|= 1;
            return;
        }
        if (depth >= pm4.max_indirect_depth) {
            self.setReferenceStatus(reference_index, .depth_limit);
            self.result.depth_limited_references +|= 1;
            return;
        }
        if (self.memory_context == null or self.memory_callback == null) {
            self.setReferenceStatus(reference_index, .unreadable);
            self.result.unreadable_references +|= 1;
            return;
        }
        if (self.overlapsActive(descriptor.address, descriptor.size_dwords)) {
            self.setReferenceStatus(reference_index, .cycle);
            self.result.cycle_references +|= 1;
            return;
        }

        const walk_dwords = @min(descriptor.size_dwords, pm4.max_indirect_dwords);
        if (descriptor.size_dwords > pm4.max_indirect_dwords) {
            self.setReferenceStatus(reference_index, .budget_limit);
            self.result.budget_limited_references +|= 1;
        }
        if (self.active_count == self.active_ranges.len) {
            self.setReferenceStatus(reference_index, .depth_limit);
            self.result.depth_limited_references +|= 1;
            return;
        }
        const before_packets = self.result.packets_walked;
        const before_draws = self.result.draw_packets;
        const before_swaps = self.result.swap_packets;
        const before_unknown = self.result.unknown_packets;
        const before_words = self.result.words_read;
        self.active_ranges[self.active_count] = .{ .address = descriptor.address, .size_dwords = walk_dwords };
        self.active_count += 1;
        defer self.active_count -= 1;
        const walk = self.walkSource(.{ .memory = .{
            .context = self.memory_context.?,
            .callback = self.memory_callback.?,
            .address = descriptor.address,
        } }, depth + 1, false, walk_dwords);
        self.setReferenceCounts(
            reference_index,
            self.result.packets_walked - before_packets,
            self.result.draw_packets - before_draws,
            self.result.swap_packets - before_swaps,
            self.result.unknown_packets - before_unknown,
            self.result.words_read - before_words,
        );
        self.setReferenceMissingAddress(reference_index, walk.missing_address);
        if (self.referenceStatus(reference_index) == .observed) {
            switch (walk.status) {
                .complete => self.result.readable_references +|= 1,
                .unreadable => {
                    self.setReferenceStatus(reference_index, .unreadable);
                    self.result.unreadable_references +|= 1;
                },
                .truncated => {
                    self.setReferenceStatus(reference_index, .truncated);
                    self.result.truncated_references +|= 1;
                },
                .budget_limit => {
                    self.setReferenceStatus(reference_index, .budget_limit);
                    self.result.budget_limited_references +|= 1;
                },
            }
        }
    }

    fn noteCommandRegister(self: *Walker, register: u32) void {
        self.result.command_register_writes +|= 1;
        const block = register_map.blockForIndex(register) orelse {
            self.result.command_out_of_range_register_writes +|= 1;
            return;
        };
        if (block == .unclassified) self.result.command_unclassified_register_writes +|= 1;
    }

    fn noteCommandRegisterRange(self: *Walker, start: u32, count: u32, one_register: bool) void {
        var offset: u32 = 0;
        while (offset < count) : (offset += 1) {
            self.noteCommandRegister(if (one_register) start else start +| offset);
        }
    }

    /// Structural register accounting implemented independently of the
    /// stateful executor. Only immutable register-bank constants are shared.
    fn noteRegisterIntent(self: *Walker, header: u32, packet: pm4.Packet, payload: []const u32) void {
        switch (packet.packet_type) {
            .type0 => self.noteCommandRegisterRange(
                pm4.type0BaseRegister(header),
                packet.body_dwords,
                (header & (1 << 15)) != 0,
            ),
            .type1 => {
                self.noteCommandRegister(header & 0x7FF);
                self.noteCommandRegister((header >> 11) & 0x7FF);
            },
            .type2 => {},
            .type3 => switch (packet.opcode) {
                0x21 => {
                    if (packet.body_dwords >= 3 and payload.len >= 1) {
                        self.noteCommandRegister(payload[0] & 0x1FFF);
                    }
                },
                0x2D => {
                    if (packet.body_dwords < 2 or payload.len < 1) return;
                    const base = constantBankBase((payload[0] >> 16) & 0xFF) orelse return;
                    self.noteCommandRegisterRange(
                        base +| (payload[0] & 0x7FF),
                        packet.body_dwords - 1,
                        false,
                    );
                },
                0x2F => {
                    if (packet.body_dwords < 3 or payload.len < 3) return;
                    const base = constantBankBase((payload[1] >> 16) & 0xFF) orelse return;
                    self.noteCommandRegisterRange(
                        base +| (payload[1] & 0x7FF),
                        payload[2] & 0xFFF,
                        false,
                    );
                },
                0x45 => {
                    if (packet.body_dwords >= 6 and payload.len >= 5 and (payload[0] & 0x100) == 0) {
                        self.noteCommandRegister(payload[4]);
                    }
                },
                0x55, 0x56 => {
                    if (packet.body_dwords >= 2 and payload.len >= 1) {
                        self.noteCommandRegisterRange(
                            payload[0] & 0xFFFF,
                            packet.body_dwords - 1,
                            false,
                        );
                    }
                },
                else => {},
            },
        }
    }

    fn recordReference(
        self: *Walker,
        descriptor: pm4.IndirectBuffer,
        depth: u8,
        status: ReferenceStatus,
        missing_address: ?u32,
    ) ?usize {
        self.result.indirect_references +|= 1;
        if (self.reference_count == self.references.len) {
            self.references_dropped +|= 1;
            self.result.budget_limited_references +|= 1;
            return null;
        }
        const index = self.reference_count;
        self.reference_count += 1;
        self.references[index] = .{
            .depth = depth,
            .opcode = @intFromEnum(descriptor.opcode),
            .address = descriptor.address,
            .size_dwords = descriptor.size_dwords,
            .status = status,
            .missing_address = missing_address,
        };
        return index;
    }

    fn setReferenceStatus(self: *Walker, index: ?usize, status: ReferenceStatus) void {
        if (index) |value| self.references[value].status = status;
    }

    fn referenceStatus(self: *const Walker, index: ?usize) ReferenceStatus {
        return if (index) |value| self.references[value].status else .budget_limit;
    }

    fn setReferenceMissingAddress(self: *Walker, index: ?usize, address: ?u32) void {
        if (index) |value| {
            if (address) |missing| self.references[value].missing_address = missing;
        }
    }

    fn setReferenceCounts(
        self: *Walker,
        index: ?usize,
        packets: u32,
        draws: u32,
        swaps: u32,
        unknown: u32,
        words_read: u32,
    ) void {
        if (index) |value| {
            self.references[value].packets = packets;
            self.references[value].draws = draws;
            self.references[value].swaps = swaps;
            self.references[value].unknown = unknown;
            self.references[value].words_read = words_read;
        }
    }

    fn overlapsActive(self: *const Walker, address: u32, size_dwords: u32) bool {
        const start = @as(u64, address);
        const end = start + @as(u64, size_dwords) * 4;
        for (self.active_ranges[0..self.active_count]) |active| {
            const active_start = @as(u64, active.address);
            const active_end = active_start + @as(u64, active.size_dwords) * 4;
            if (start < active_end and active_start < end) return true;
        }
        return false;
    }
};

fn constantBankBase(kind: u32) ?u32 {
    return switch (kind) {
        0 => register_map.shader_constant_alu_base,
        1 => register_map.shader_constant_fetch_base,
        2 => register_map.shader_constant_bool_base,
        3 => register_map.shader_constant_loop_base,
        4 => register_map.shader_constant_register_base,
        else => null,
    };
}

fn indirectHeader(opcode: u8, body_dwords: u32) u32 {
    return 0xC000_0000 |
        ((body_dwords - 1) << pm4.count_shift) |
        (@as(u32, opcode) << pm4.opcode_shift);
}

const MemoryFixture = struct {
    words: [128]u32 = [_]u32{0} ** 128,

    fn read(context: *anyopaque, address: u32) ?u32 {
        const self: *MemoryFixture = @ptrCast(@alignCast(context));
        if ((address & 3) != 0 or address / 4 >= self.words.len) return null;
        return self.words[address / 4];
    }
};

fn writeBig(bytes: []u8, index: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[index * 4 ..][0..4], value, .big);
}

test "the walker follows an indirect buffer without executing it" {
    var root = [_]u8{0} ** 32;
    writeBig(&root, 0, indirectHeader(0x3F, 2));
    writeBig(&root, 1, 0x0000_0100);
    writeBig(&root, 2, 3);

    var memory = MemoryFixture{};
    memory.words[0x100 / 4] = indirectHeader(0x22, 1);
    memory.words[0x104 / 4] = 3;

    var walker = Walker.init(&memory, MemoryFixture.read);
    walker.walkRoot(&root, 0, 8, 8);
    const result = walker.summary();
    try std.testing.expectEqual(@as(u32, 1), result.root_indirect_packets);
    try std.testing.expectEqual(@as(u32, 1), result.indirect_references);
    try std.testing.expectEqual(@as(u32, 1), result.nested_draw_packets);
    try std.testing.expectEqual(@as(u32, 1), result.draw_packets);
    try std.testing.expectEqual(ReferenceStatus.observed, walker.referenceSlice()[0].status);
    try std.testing.expectEqual(@as(u32, 1), walker.referenceSlice()[0].draws);
}

test "an unreadable indirect buffer is reported without claiming a draw" {
    var root = [_]u8{0} ** 16;
    writeBig(&root, 0, indirectHeader(0x3F, 2));
    writeBig(&root, 1, 0x0000_0300);
    writeBig(&root, 2, 4);

    var memory = MemoryFixture{};
    var walker = Walker.init(&memory, MemoryFixture.read);
    walker.walkRoot(&root, 0, 4, 4);
    const result = walker.summary();
    try std.testing.expectEqual(@as(u32, 1), result.indirect_references);
    try std.testing.expectEqual(@as(u32, 1), result.unreadable_references);
    try std.testing.expectEqual(@as(u32, 0), result.draw_packets);
    try std.testing.expectEqual(ReferenceStatus.unreadable, walker.referenceSlice()[0].status);
    try std.testing.expectEqual(@as(u32, 0), walker.referenceSlice()[0].words_read);
    try std.testing.expectEqual(@as(?u32, 0x0000_0300), walker.referenceSlice()[0].missing_address);
}

test "overlapping indirect ranges are stopped as cycles" {
    var root = [_]u8{0} ** 16;
    writeBig(&root, 0, indirectHeader(0x3F, 2));
    writeBig(&root, 1, 0x0000_0100);
    writeBig(&root, 2, 3);

    var memory = MemoryFixture{};
    memory.words[0x100 / 4] = indirectHeader(0x3F, 2);
    memory.words[0x104 / 4] = 0x0000_0100;
    memory.words[0x108 / 4] = 3;

    var walker = Walker.init(&memory, MemoryFixture.read);
    walker.walkRoot(&root, 0, 4, 4);
    const result = walker.summary();
    try std.testing.expectEqual(@as(u32, 2), result.indirect_references);
    try std.testing.expectEqual(@as(u32, 1), result.cycle_references);
    try std.testing.expectEqual(ReferenceStatus.cycle, walker.referenceSlice()[1].status);
}

test "structural register intent excludes observer side effects" {
    var root = [_]u8{0} ** (9 * 4);
    // Two classified Type-0 writes starting at RB_COLOR_INFO.
    writeBig(
        &root,
        0,
        (@as(u32, 1) << pm4.count_shift) | @as(u32, register_map.RB_COLOR_INFO),
    );
    writeBig(&root, 1, 0x1111);
    writeBig(&root, 2, 0x2222);
    // One in-range but unclassified REG_RMW target.
    writeBig(&root, 3, indirectHeader(0x21, 3));
    writeBig(&root, 4, 0x1000);
    writeBig(&root, 5, 0xFFFF_FFFF);
    writeBig(&root, 6, 0);
    // One Type-0 target immediately outside the retained aperture.
    writeBig(&root, 7, @intCast(register_map.register_count));
    writeBig(&root, 8, 0x3333);

    var walker = Walker.init(null, null);
    walker.walkRoot(&root, 0, 9, 9);
    const result = walker.summary();
    try std.testing.expectEqual(@as(u32, 3), result.packets_walked);
    try std.testing.expectEqual(@as(u64, 4), result.command_register_writes);
    try std.testing.expectEqual(@as(u64, 1), result.command_unclassified_register_writes);
    try std.testing.expectEqual(@as(u64, 1), result.command_out_of_range_register_writes);
}
