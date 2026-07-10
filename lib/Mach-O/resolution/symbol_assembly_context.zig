const std = @import("std");
const x64_decoder = @import("x64_decoder");
const macho_metadata = @import("../metadata.zig");

const DecodedInsn = x64_decoder.DecodedInsn;

pub const CONTEXT_BEFORE: usize = 8;
pub const CONTEXT_AFTER: usize = 8;
pub const MAX_CONTEXT_INSTRUCTIONS: usize = CONTEXT_BEFORE + 1 + CONTEXT_AFTER;
const MAX_INSTRUCTION_BYTES: usize = 15;

pub const SiteKind = enum {
    direct_call,
    indirect_call,
    tail_jump,
    indirect_tail_jump,
};

pub const Instruction = struct {
    address: u64 = 0,
    decoded: DecodedInsn = .{},
    bytes: [MAX_INSTRUCTION_BYTES]u8 = [_]u8{0} ** MAX_INSTRUCTION_BYTES,
    byte_count: u8 = 0,
    direct_target: ?u64 = null,
    operand_address: ?u64 = null,

    pub fn init(address: u64, source: []const u8, decoded: DecodedInsn, byte_count: usize) Instruction {
        var instruction = Instruction{
            .address = address,
            .decoded = decoded,
            .byte_count = @intCast(@min(byte_count, MAX_INSTRUCTION_BYTES)),
        };
        @memcpy(instruction.bytes[0..instruction.byte_count], source[0..instruction.byte_count]);

        switch (decoded.op) {
            .call_rel32, .jmp_rel8 => {
                instruction.direct_target = address +% decoded.len +% decoded.addr;
            },
            .call_mem64, .jmp_mem64 => {
                if (decoded.rip_relative and !decoded.sib_has_base and !decoded.sib_has_index) {
                    instruction.operand_address = address +% decoded.len +% decoded.addr;
                }
            },
            else => {},
        }
        if (instruction.direct_target == null and instruction.operand_address == null and
            decoded.rip_relative and !decoded.sib_has_base and !decoded.sib_has_index)
        {
            instruction.operand_address = address +% decoded.len +% decoded.addr;
        }
        return instruction;
    }
};

pub const Site = struct {
    kind: SiteKind = .direct_call,
    address: u64 = 0,
    instructions: [MAX_CONTEXT_INSTRUCTIONS]Instruction = [_]Instruction{.{}} ** MAX_CONTEXT_INSTRUCTIONS,
    instruction_count: u8 = 0,
    after_remaining: u8 = CONTEXT_AFTER,

    fn append(self: *Site, instruction: Instruction) void {
        if (self.instruction_count >= self.instructions.len) return;
        self.instructions[self.instruction_count] = instruction;
        self.instruction_count += 1;
    }
};

pub const Report = struct {
    allocator: std.mem.Allocator,
    sites: []Site,
    decoded_instructions: usize,
    decode_gaps: usize,

    pub fn deinit(self: *Report) void {
        if (self.sites.len != 0) self.allocator.free(self.sites);
        self.* = undefined;
    }
};

pub const Observation = struct {
    first_symbol: bool,
    first_use_site: bool,
    symbol_hits: u64,
    site_hits: u64,
};

pub const RuntimeRegisterState = struct {
    rsp: u64,
    rax: u64,
    rcx: u64,
    rdx: u64,
};

const UseSite = struct {
    symbol: []const u8,
    address: u64,
    hits: u64,
};

pub const Tracker = struct {
    allocator: std.mem.Allocator,
    use_sites: std.ArrayList(UseSite) = .empty,
    observations: u64 = 0,
    unique_symbols: u64 = 0,
    repeated_observations: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) Tracker {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Tracker) void {
        self.use_sites.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn observe(self: *Tracker, symbol: []const u8, address: u64) !Observation {
        self.observations +|= 1;
        var symbol_hits: u64 = 0;
        var first_symbol = true;
        for (self.use_sites.items) |site| {
            if (!std.mem.eql(u8, site.symbol, symbol)) continue;
            first_symbol = false;
            symbol_hits +|= site.hits;
        }

        for (self.use_sites.items) |*site| {
            if (site.address != address or !std.mem.eql(u8, site.symbol, symbol)) continue;
            site.hits +|= 1;
            self.repeated_observations +|= 1;
            return .{
                .first_symbol = false,
                .first_use_site = false,
                .symbol_hits = symbol_hits +| 1,
                .site_hits = site.hits,
            };
        }

        try self.use_sites.append(self.allocator, .{
            .symbol = symbol,
            .address = address,
            .hits = 1,
        });
        if (first_symbol) self.unique_symbols +|= 1;
        return .{
            .first_symbol = first_symbol,
            .first_use_site = true,
            .symbol_hits = symbol_hits +| 1,
            .site_hits = 1,
        };
    }

    pub fn logSummary(self: *const Tracker) void {
        std.debug.print(
            "macho-processor: unknown-symbol assembly analysis: symbols={d} use_sites={d} observations={d} repeated={d}\n",
            .{ self.unique_symbols, self.use_sites.items.len, self.observations, self.repeated_observations },
        );
    }
};

const IndexedSite = struct {
    symbol: []const u8,
    kind: SiteKind,
    address: u64,
};

pub const Catalog = struct {
    allocator: std.mem.Allocator,
    sites: []IndexedSite,
    decoded_instructions: usize,
    decode_gaps: usize,

    pub fn build(
        allocator: std.mem.Allocator,
        metadata: *const macho_metadata.Metadata,
        comptime decode: fn ([]const u8) DecodedInsn,
    ) !Catalog {
        var direct_targets = std.AutoHashMap(u64, []const u8).init(allocator);
        defer direct_targets.deinit();
        var indirect_targets = std.AutoHashMap(u64, []const u8).init(allocator);
        defer indirect_targets.deinit();
        for (metadata.imports) |imported| try direct_targets.put(imported.stub_address, imported.name);
        for (metadata.bindings) |binding| try indirect_targets.put(binding.address, binding.name);

        var sites: std.ArrayList(IndexedSite) = .empty;
        errdefer sites.deinit(allocator);
        var decoded_instructions: usize = 0;
        var decode_gaps: usize = 0;
        for (metadata.sections) |section| {
            if (!std.mem.eql(u8, section.segment_name, "__TEXT") or
                !std.mem.eql(u8, section.name, "__text")) continue;
            const bytes = metadata.sectionBytes(section) orelse continue;
            var starts = try functionStarts(allocator, metadata, section);
            defer starts.deinit(allocator);

            if (starts.items.len == 0) {
                try indexText(
                    allocator,
                    &sites,
                    &decoded_instructions,
                    &decode_gaps,
                    section.address,
                    bytes,
                    &direct_targets,
                    &indirect_targets,
                    decode,
                );
                continue;
            }
            if (starts.items[0] > section.address) {
                const prefix_size: usize = @intCast(starts.items[0] - section.address);
                try indexText(
                    allocator,
                    &sites,
                    &decoded_instructions,
                    &decode_gaps,
                    section.address,
                    bytes[0..prefix_size],
                    &direct_targets,
                    &indirect_targets,
                    decode,
                );
            }
            for (starts.items, 0..) |start_address, index| {
                const end_address = if (index + 1 < starts.items.len)
                    starts.items[index + 1]
                else
                    section.address + section.size;
                const start_offset: usize = @intCast(start_address - section.address);
                const end_offset: usize = @intCast(end_address - section.address);
                try indexText(
                    allocator,
                    &sites,
                    &decoded_instructions,
                    &decode_gaps,
                    start_address,
                    bytes[start_offset..end_offset],
                    &direct_targets,
                    &indirect_targets,
                    decode,
                );
            }
        }

        return .{
            .allocator = allocator,
            .sites = try sites.toOwnedSlice(allocator),
            .decoded_instructions = decoded_instructions,
            .decode_gaps = decode_gaps,
        };
    }

    pub fn deinit(self: *Catalog) void {
        if (self.sites.len != 0) self.allocator.free(self.sites);
        self.* = undefined;
    }

    pub fn logImport(
        self: *const Catalog,
        metadata: *const macho_metadata.Metadata,
        imported: macho_metadata.ImportedSymbol,
        comptime decode: fn ([]const u8) DecodedInsn,
    ) void {
        var site_count: usize = 0;
        for (self.sites) |site| {
            if (std.mem.eql(u8, site.symbol, imported.name)) site_count += 1;
        }
        std.debug.print(
            "  [unknown-symbol assembly] symbol={s} image={s} stub=0x{x} static_use_sites={d} indexed_sites={d} decoded={d} decode_gaps={d}\n",
            .{ imported.name, imported.dylib, imported.stub_address, site_count, self.sites.len, self.decoded_instructions, self.decode_gaps },
        );
        if (self.decode_gaps != 0) {
            std.debug.print(
                "    coverage: exact for indexed control transfers; {d} function region(s) stopped at an undecoded instruction and were not inferred past that boundary\n",
                .{self.decode_gaps},
            );
        }
        if (site_count == 0) {
            std.debug.print("    no statically resolvable use site; runtime context below is authoritative for register-indirect dispatch\n", .{});
            return;
        }

        var ordinal: usize = 0;
        for (self.sites) |indexed| {
            if (!std.mem.eql(u8, indexed.symbol, imported.name)) continue;
            const site = collectContextAt(metadata, indexed, decode) orelse {
                std.debug.print(
                    "    use-site[{d}] kind={s} address=0x{x} context=<unavailable before exact decode boundary>\n",
                    .{ ordinal, @tagName(indexed.kind), indexed.address },
                );
                ordinal += 1;
                continue;
            };
            if (metadata.nearestSymbol(site.address)) |caller| {
                std.debug.print(
                    "    use-site[{d}] kind={s} address=0x{x} caller={s}+0x{x}\n",
                    .{ ordinal, @tagName(site.kind), site.address, caller.name, caller.offset },
                );
            } else {
                std.debug.print(
                    "    use-site[{d}] kind={s} address=0x{x} caller=<unknown>\n",
                    .{ ordinal, @tagName(site.kind), site.address },
                );
            }
            for (site.instructions[0..site.instruction_count]) |instruction| {
                logInstruction(metadata, instruction, instruction.address == site.address, null);
            }
            ordinal += 1;
        }
    }
};

fn functionStarts(
    allocator: std.mem.Allocator,
    metadata: *const macho_metadata.Metadata,
    section: macho_metadata.Section,
) !std.ArrayList(u64) {
    var starts: std.ArrayList(u64) = .empty;
    errdefer starts.deinit(allocator);
    var symbols = metadata.definedSymbolIterator();
    while (symbols.next()) |entry| {
        const address = entry.value_ptr.*;
        if (address < section.address or address - section.address >= section.size) continue;
        try starts.append(allocator, address);
    }
    std.mem.sort(u64, starts.items, {}, struct {
        fn lessThan(_: void, lhs: u64, rhs: u64) bool {
            return lhs < rhs;
        }
    }.lessThan);
    var unique_count: usize = 0;
    for (starts.items) |address| {
        if (unique_count != 0 and starts.items[unique_count - 1] == address) continue;
        starts.items[unique_count] = address;
        unique_count += 1;
    }
    starts.shrinkRetainingCapacity(unique_count);
    return starts;
}

fn indexText(
    allocator: std.mem.Allocator,
    sites: *std.ArrayList(IndexedSite),
    decoded_instructions: *usize,
    decode_gaps: *usize,
    text_address: u64,
    text: []const u8,
    direct_targets: *const std.AutoHashMap(u64, []const u8),
    indirect_targets: *const std.AutoHashMap(u64, []const u8),
    comptime decode: fn ([]const u8) DecodedInsn,
) !void {
    var offset: usize = 0;
    while (offset < text.len) {
        const decoded = decode(text[offset..]);
        const valid_length = decoded.op != .invalid and decoded.len != 0 and decoded.len <= text.len - offset;
        if (!valid_length) {
            decode_gaps.* += 1;
            break;
        }
        decoded_instructions.* += 1;
        const instruction = Instruction.init(text_address + offset, text[offset..], decoded, decoded.len);
        var kind: ?SiteKind = null;
        var symbol: ?[]const u8 = null;
        switch (decoded.op) {
            .call_rel32 => {
                kind = .direct_call;
                symbol = direct_targets.get(instruction.direct_target orelse 0);
            },
            .jmp_rel8 => {
                kind = .tail_jump;
                symbol = direct_targets.get(instruction.direct_target orelse 0);
            },
            .call_mem64 => {
                kind = .indirect_call;
                symbol = indirect_targets.get(instruction.operand_address orelse 0);
            },
            .jmp_mem64 => {
                kind = .indirect_tail_jump;
                symbol = indirect_targets.get(instruction.operand_address orelse 0);
            },
            else => {},
        }
        if (symbol) |resolved| {
            try sites.append(allocator, .{
                .symbol = resolved,
                .kind = kind.?,
                .address = instruction.address,
            });
        }
        offset += decoded.len;
    }
}

fn collectContextAt(
    metadata: *const macho_metadata.Metadata,
    indexed: IndexedSite,
    comptime decode: fn ([]const u8) DecodedInsn,
) ?Site {
    const section = metadata.sectionAtAddress(indexed.address) orelse return null;
    const section_bytes = metadata.sectionBytes(section) orelse return null;
    var start_address = section.address;
    if (metadata.nearestSymbol(indexed.address)) |caller| {
        if (caller.address >= section.address and caller.address <= indexed.address) start_address = caller.address;
    }
    const start_offset: usize = @intCast(start_address - section.address);
    const text = section_bytes[start_offset..];
    var previous: [CONTEXT_BEFORE]Instruction = [_]Instruction{.{}} ** CONTEXT_BEFORE;
    var previous_count: usize = 0;
    var result: ?Site = null;
    var offset: usize = 0;
    while (offset < text.len) {
        const decoded = decode(text[offset..]);
        const valid_length = decoded.op != .invalid and decoded.len != 0 and decoded.len <= text.len - offset;
        if (!valid_length) break;
        const instruction = Instruction.init(start_address + offset, text[offset..], decoded, decoded.len);
        if (result) |*site| {
            site.append(instruction);
            site.after_remaining -= 1;
            if (site.after_remaining == 0) return site.*;
        } else if (instruction.address == indexed.address) {
            var site = Site{ .kind = indexed.kind, .address = indexed.address };
            for (previous[0..previous_count]) |prior| site.append(prior);
            site.append(instruction);
            result = site;
        }

        if (previous_count < previous.len) {
            previous[previous_count] = instruction;
            previous_count += 1;
        } else {
            std.mem.copyForwards(Instruction, previous[0 .. previous.len - 1], previous[1..]);
            previous[previous.len - 1] = instruction;
        }
        offset += decoded.len;
    }
    return result;
}

pub fn analyzeText(
    allocator: std.mem.Allocator,
    text_address: u64,
    text: []const u8,
    stub_address: u64,
    binding_addresses: []const u64,
    comptime decode: fn ([]const u8) DecodedInsn,
) !Report {
    var sites: std.ArrayList(Site) = .empty;
    errdefer sites.deinit(allocator);
    var previous: [CONTEXT_BEFORE]Instruction = [_]Instruction{.{}} ** CONTEXT_BEFORE;
    var previous_count: usize = 0;
    var decoded_instructions: usize = 0;
    var decode_gaps: usize = 0;
    var offset: usize = 0;

    while (offset < text.len) {
        const decoded = decode(text[offset..]);
        const valid_length = decoded.op != .invalid and decoded.len != 0 and decoded.len <= text.len - offset;
        if (!valid_length) {
            decode_gaps += 1;
            break;
        }
        const byte_count: usize = decoded.len;
        decoded_instructions += 1;
        const instruction = Instruction.init(text_address + offset, text[offset..], decoded, byte_count);

        for (sites.items) |*site| {
            if (site.after_remaining == 0) continue;
            site.append(instruction);
            site.after_remaining -= 1;
        }

        if (siteKind(instruction, stub_address, binding_addresses)) |kind| {
            var site = Site{ .kind = kind, .address = instruction.address };
            for (previous[0..previous_count]) |prior| site.append(prior);
            site.append(instruction);
            try sites.append(allocator, site);
        }

        if (previous_count < previous.len) {
            previous[previous_count] = instruction;
            previous_count += 1;
        } else {
            std.mem.copyForwards(Instruction, previous[0 .. previous.len - 1], previous[1..]);
            previous[previous.len - 1] = instruction;
        }
        offset += byte_count;
    }

    return .{
        .allocator = allocator,
        .sites = try sites.toOwnedSlice(allocator),
        .decoded_instructions = decoded_instructions,
        .decode_gaps = decode_gaps,
    };
}

fn siteKind(instruction: Instruction, stub_address: u64, binding_addresses: []const u64) ?SiteKind {
    switch (instruction.decoded.op) {
        .call_rel32 => if (instruction.direct_target == stub_address) return .direct_call,
        .jmp_rel8 => if (instruction.direct_target == stub_address) return .tail_jump,
        .call_mem64 => if (containsAddress(binding_addresses, instruction.operand_address)) return .indirect_call,
        .jmp_mem64 => if (containsAddress(binding_addresses, instruction.operand_address)) return .indirect_tail_jump,
        else => {},
    }
    return null;
}

fn containsAddress(addresses: []const u64, candidate: ?u64) bool {
    const address = candidate orelse return false;
    for (addresses) |expected| {
        if (expected == address) return true;
    }
    return false;
}

pub fn logDynamicInstruction(
    metadata: *const macho_metadata.Metadata,
    instruction: Instruction,
    selected: bool,
    register_state: ?RuntimeRegisterState,
) void {
    logInstruction(metadata, instruction, selected, register_state);
}

fn logInstruction(
    metadata: *const macho_metadata.Metadata,
    instruction: Instruction,
    selected: bool,
    register_state: ?RuntimeRegisterState,
) void {
    std.debug.print("      {s} 0x{x}: ", .{ if (selected) ">" else " ", instruction.address });
    for (instruction.bytes[0..instruction.byte_count]) |byte| std.debug.print("{x:0>2} ", .{byte});
    std.debug.print(" {s} size={s}", .{ @tagName(instruction.decoded.op), @tagName(instruction.decoded.size) });
    if (instruction.decoded.imm != 0) std.debug.print(" imm=0x{x}", .{instruction.decoded.imm});
    if (instruction.direct_target) |target| {
        logAddressRelationship(metadata, "target", target);
    } else if (instruction.operand_address) |operand| {
        logAddressRelationship(metadata, "operand", operand);
    }
    if (register_state) |regs| {
        std.debug.print(" rsp=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x}", .{ regs.rsp, regs.rax, regs.rcx, regs.rdx });
    }
    std.debug.print("\n", .{});
}

fn logAddressRelationship(metadata: *const macho_metadata.Metadata, label: []const u8, address: u64) void {
    if (metadata.importAtStub(address)) |imported| {
        std.debug.print(" {s}=0x{x}<{s}@{s}>", .{ label, address, imported.name, imported.dylib });
    } else if (metadata.nearestSymbol(address)) |symbol| {
        std.debug.print(" {s}=0x{x}<{s}+0x{x}>", .{ label, address, symbol.name, symbol.offset });
    } else {
        std.debug.print(" {s}=0x{x}", .{ label, address });
    }
}

fn testDecode(bytes: []const u8) DecodedInsn {
    if (bytes.len == 0) return .{};
    if (bytes[0] == 0x90) return .{ .op = .nop, .len = 1 };
    if (bytes[0] == 0xE8 and bytes.len >= 5) {
        return .{
            .op = .call_rel32,
            .addr = @bitCast(@as(i64, std.mem.readInt(i32, bytes[1..5], .little))),
            .rip_relative = true,
            .len = 5,
        };
    }
    if (bytes.len >= 6 and bytes[0] == 0xFF and bytes[1] == 0x15) {
        return .{
            .op = .call_mem64,
            .addr = @bitCast(@as(i64, std.mem.readInt(i32, bytes[2..6], .little))),
            .rip_relative = true,
            .len = 6,
        };
    }
    return .{};
}

test "static analysis finds direct and RIP-relative import contexts" {
    const text = [_]u8{
        0x90,
        0xE8,
        0xFA,
        0x0F,
        0x00,
        0x00,
        0x90,
        0xFF,
        0x15,
        0xF3,
        0x1F,
        0x00,
        0x00,
        0x90,
    };
    var report = try analyzeText(std.testing.allocator, 0x1000, &text, 0x2000, &.{0x3000}, testDecode);
    defer report.deinit();

    try std.testing.expectEqual(@as(usize, 2), report.sites.len);
    try std.testing.expectEqual(SiteKind.direct_call, report.sites[0].kind);
    try std.testing.expectEqual(@as(u64, 0x1001), report.sites[0].address);
    try std.testing.expectEqual(SiteKind.indirect_call, report.sites[1].kind);
    try std.testing.expectEqual(@as(u64, 0x1007), report.sites[1].address);
    try std.testing.expectEqual(@as(usize, 0), report.decode_gaps);
}

test "tracker deduplicates repeated unknown symbol use sites" {
    var tracker = Tracker.init(std.testing.allocator);
    defer tracker.deinit();

    const first = try tracker.observe("_missing", 0x1000);
    try std.testing.expect(first.first_symbol);
    try std.testing.expect(first.first_use_site);
    const repeated = try tracker.observe("_missing", 0x1000);
    try std.testing.expect(!repeated.first_symbol);
    try std.testing.expect(!repeated.first_use_site);
    try std.testing.expectEqual(@as(u64, 2), repeated.site_hits);
    const another = try tracker.observe("_missing", 0x1100);
    try std.testing.expect(!another.first_symbol);
    try std.testing.expect(another.first_use_site);
    try std.testing.expectEqual(@as(u64, 3), another.symbol_hits);
}

test "static analysis never guesses instruction boundaries after a decode gap" {
    const text = [_]u8{
        0x90,
        0xCC,
        0xE8,
        0xF4,
        0x0F,
        0x00,
        0x00,
    };
    var report = try analyzeText(std.testing.allocator, 0x1000, &text, 0x2000, &.{}, testDecode);
    defer report.deinit();

    try std.testing.expectEqual(@as(usize, 0), report.sites.len);
    try std.testing.expectEqual(@as(usize, 1), report.decoded_instructions);
    try std.testing.expectEqual(@as(usize, 1), report.decode_gaps);
}

test "binary-wide catalog indexes every import use in one decode pass" {
    const text = [_]u8{
        0x90,
        0xE8,
        0xFA,
        0x0F,
        0x00,
        0x00,
        0x90,
        0xFF,
        0x15,
        0xF3,
        0x1F,
        0x00,
        0x00,
        0x90,
    };
    var direct = std.AutoHashMap(u64, []const u8).init(std.testing.allocator);
    defer direct.deinit();
    try direct.put(0x2000, "_direct");
    var indirect = std.AutoHashMap(u64, []const u8).init(std.testing.allocator);
    defer indirect.deinit();
    try indirect.put(0x3000, "_indirect");
    var sites: std.ArrayList(IndexedSite) = .empty;
    defer sites.deinit(std.testing.allocator);
    var decoded: usize = 0;
    var gaps: usize = 0;

    try indexText(
        std.testing.allocator,
        &sites,
        &decoded,
        &gaps,
        0x1000,
        &text,
        &direct,
        &indirect,
        testDecode,
    );

    try std.testing.expectEqual(@as(usize, 2), sites.items.len);
    try std.testing.expectEqualStrings("_direct", sites.items[0].symbol);
    try std.testing.expectEqual(SiteKind.direct_call, sites.items[0].kind);
    try std.testing.expectEqualStrings("_indirect", sites.items[1].symbol);
    try std.testing.expectEqual(SiteKind.indirect_call, sites.items[1].kind);
    try std.testing.expectEqual(@as(usize, 0), gaps);
    try std.testing.expectEqual(@as(usize, 5), decoded);
}
