const std = @import("std");
const compat_runtime = @import("macho_compat_runtime");

pub const Outcome = enum {
    resolved,
    unresolved,
    terminated,
};

pub const Provider = enum {
    contract,
    dynamic_library,
    libcpp_filesystem,
    smart_stub,
    legacy_shim,
    none,
};

pub const Phase = enum {
    initializer,
    execution,
};

pub const Confidence = enum {
    verified,
    modeled,
    unknown,
};

pub const Domain = enum {
    libcxx,
    cxx_abi,
    compiler_runtime,
    posix,
    objective_c,
    graphics,
    unknown,
};

pub const ReturnConvention = enum {
    void,
    rax,
    rax_rdx,
};

pub const Effects = struct {
    return_convention: ReturnConvention,
    writes_guest_memory: bool = false,
};

pub const ContractId = enum {
    libcxx_match_any_but_newline_char,
    libcxx_basic_string_push_back_char,
    libcxx_basic_string_init_fill,
};

pub const Contract = struct {
    id: ContractId,
    canonical_symbol: []const u8,
    domain: Domain,
    confidence: Confidence,
    effects: Effects,
};

pub const ContractDispatch = union(enum) {
    handled: u64,
    handled_void,
    failed,
};

pub const match_any_but_newline_char = Contract{
    .id = .libcxx_match_any_but_newline_char,
    .canonical_symbol = "_ZNKSt3__123__match_any_but_newlineIcE6__execERNS_7__stateIcEE",
    .domain = .libcxx,
    .confidence = .verified,
    .effects = .{ .return_convention = .void, .writes_guest_memory = true },
};

pub const basic_string_push_back_char = Contract{
    .id = .libcxx_basic_string_push_back_char,
    .canonical_symbol = "_ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE9push_backEc",
    .domain = .libcxx,
    .confidence = .verified,
    .effects = .{ .return_convention = .void, .writes_guest_memory = true },
};

pub const basic_string_init_fill = Contract{
    .id = .libcxx_basic_string_init_fill,
    .canonical_symbol = "_ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6__initEmc",
    .domain = .libcxx,
    .confidence = .verified,
    .effects = .{ .return_convention = .void, .writes_guest_memory = true },
};

pub fn normalizeSymbol(symbol: []const u8) []const u8 {
    var normalized = symbol;
    if (normalized.len != 0 and normalized[0] == '_') normalized = normalized[1..];
    if (std.mem.endsWith(u8, normalized, "$INODE64")) {
        normalized = normalized[0 .. normalized.len - "$INODE64".len];
    }
    return normalized;
}

pub fn contractFor(symbol: []const u8) ?Contract {
    const normalized = normalizeSymbol(symbol);
    if (std.mem.eql(u8, normalized, match_any_but_newline_char.canonical_symbol)) {
        return match_any_but_newline_char;
    }
    if (std.mem.eql(u8, normalized, basic_string_push_back_char.canonical_symbol)) {
        return basic_string_push_back_char;
    }
    if (std.mem.eql(u8, normalized, basic_string_init_fill.canonical_symbol)) {
        return basic_string_init_fill;
    }
    return null;
}

pub fn dispatchContract(state: anytype, symbol: []const u8) ?ContractDispatch {
    const resolved = contractFor(symbol) orelse return null;
    return switch (resolved.id) {
        .libcxx_match_any_but_newline_char => if (executeMatchAnyButNewlineChar(state, state.regs.rdi, state.regs.rsi))
            .handled_void
        else
            .failed,
        .libcxx_basic_string_push_back_char => if (compat_runtime.pushBackLibcppString(state, state.regs.rdi, @truncate(state.regs.rsi)))
            .handled_void
        else
            .failed,
        .libcxx_basic_string_init_fill => if (compat_runtime.initLibcppStringFill(state, state.regs.rdi, state.regs.rsi, @truncate(state.regs.rdx)))
            .handled_void
        else
            .failed,
    };
}

pub fn classifyDomain(symbol: []const u8) Domain {
    const normalized = normalizeSymbol(symbol);
    if (std.mem.startsWith(u8, normalized, "_ZNSt3__1") or
        std.mem.startsWith(u8, normalized, "_ZNKSt3__1")) return .libcxx;
    if (std.mem.startsWith(u8, normalized, "__cxa_") or
        std.mem.eql(u8, normalized, "__dynamic_cast")) return .cxx_abi;
    if (std.mem.startsWith(u8, normalized, "__stack_chk") or
        std.mem.startsWith(u8, normalized, "___chkstk")) return .compiler_runtime;
    if (std.mem.startsWith(u8, normalized, "objc_") or
        std.mem.startsWith(u8, normalized, "sel_")) return .objective_c;
    if (std.mem.startsWith(u8, normalized, "gtk_") or
        std.mem.startsWith(u8, normalized, "gdk_") or
        std.mem.startsWith(u8, normalized, "SDL_")) return .graphics;
    if (std.mem.startsWith(u8, normalized, "pthread_") or
        std.mem.startsWith(u8, normalized, "open") or
        std.mem.startsWith(u8, normalized, "close") or
        std.mem.startsWith(u8, normalized, "stat") or
        std.mem.startsWith(u8, normalized, "fstat") or
        std.mem.startsWith(u8, normalized, "ftruncate")) return .posix;
    return .unknown;
}

const Entry = struct {
    symbol: []const u8,
    first_caller: []const u8,
    first_owner: []const u8,
    first_phase: Phase,
    domain: Domain,
    provider: Provider,
    confidence: Confidence,
    calls: u64 = 0,
    resolved: u64 = 0,
    unresolved: u64 = 0,
    terminated: u64 = 0,
};

pub const Engine = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,
    indices: std.StringHashMap(usize),
    total_calls: u64 = 0,
    resolved_calls: u64 = 0,
    unresolved_calls: u64 = 0,
    terminated_calls: u64 = 0,
    contract_calls: u64 = 0,
    dynamic_library_calls: u64 = 0,
    libcpp_filesystem_calls: u64 = 0,
    smart_stub_calls: u64 = 0,
    legacy_shim_calls: u64 = 0,
    verified_calls: u64 = 0,
    modeled_calls: u64 = 0,
    dropped_records: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) Engine {
        return .{
            .allocator = allocator,
            .indices = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.entries.deinit(self.allocator);
        self.indices.deinit();
        self.* = undefined;
    }

    pub fn record(
        self: *Engine,
        symbol: []const u8,
        caller: []const u8,
        owner: []const u8,
        phase: Phase,
        outcome: Outcome,
        provider: Provider,
        confidence: Confidence,
    ) void {
        self.total_calls += 1;
        switch (outcome) {
            .resolved => self.resolved_calls += 1,
            .unresolved => self.unresolved_calls += 1,
            .terminated => self.terminated_calls += 1,
        }
        switch (provider) {
            .contract => self.contract_calls += 1,
            .dynamic_library => self.dynamic_library_calls += 1,
            .libcpp_filesystem => self.libcpp_filesystem_calls += 1,
            .smart_stub => self.smart_stub_calls += 1,
            .legacy_shim => self.legacy_shim_calls += 1,
            .none => {},
        }
        switch (confidence) {
            .verified => self.verified_calls += 1,
            .modeled => self.modeled_calls += 1,
            .unknown => {},
        }

        const index = self.indices.get(symbol) orelse create: {
            const new_index = self.entries.items.len;
            self.entries.append(self.allocator, .{
                .symbol = symbol,
                .first_caller = caller,
                .first_owner = owner,
                .first_phase = phase,
                .domain = classifyDomain(symbol),
                .provider = provider,
                .confidence = confidence,
            }) catch {
                self.dropped_records += 1;
                return;
            };
            self.indices.put(symbol, new_index) catch {
                _ = self.entries.pop();
                self.dropped_records += 1;
                return;
            };
            break :create new_index;
        };

        const entry = &self.entries.items[index];
        if (@intFromEnum(confidence) < @intFromEnum(entry.confidence)) entry.confidence = confidence;
        if (entry.provider == .none and provider != .none) entry.provider = provider;
        entry.calls += 1;
        switch (outcome) {
            .resolved => entry.resolved += 1,
            .unresolved => entry.unresolved += 1,
            .terminated => entry.terminated += 1,
        }
    }

    pub fn logSummary(self: *const Engine) void {
        std.debug.print(
            "macho-processor: import resolution summary: calls={d} resolved={d} unresolved={d} terminated={d} symbols={d} contract={d} dynamic={d} libcxx_fs={d} smart_stub={d} shim={d} verified={d} modeled={d}",
            .{
                self.total_calls,
                self.resolved_calls,
                self.unresolved_calls,
                self.terminated_calls,
                self.entries.items.len,
                self.contract_calls,
                self.dynamic_library_calls,
                self.libcpp_filesystem_calls,
                self.smart_stub_calls,
                self.legacy_shim_calls,
                self.verified_calls,
                self.modeled_calls,
            },
        );
        if (self.dropped_records != 0) std.debug.print(" dropped={d}", .{self.dropped_records});
        std.debug.print("\n", .{});

        for (self.entries.items) |entry| {
            if (entry.unresolved != 0) {
                std.debug.print(
                    "  unresolved: {s} domain={s} calls={d} phase={s} owner={s} first_caller={s}\n",
                    .{
                        entry.symbol,
                        @tagName(entry.domain),
                        entry.unresolved,
                        @tagName(entry.first_phase),
                        entry.first_owner,
                        entry.first_caller,
                    },
                );
            } else if (entry.provider == .contract and entry.confidence == .verified) {
                std.debug.print(
                    "  verified contract: {s} domain={s} calls={d}\n",
                    .{ entry.symbol, @tagName(entry.domain), entry.calls },
                );
            }
        }
    }
};

const REGEX_STATE_DO_OFFSET: u64 = 0;
const REGEX_STATE_CURRENT_OFFSET: u64 = 16;
const REGEX_STATE_LAST_OFFSET: u64 = 24;
const REGEX_STATE_NODE_OFFSET: u64 = 80;
const MATCHER_FIRST_NODE_OFFSET: u64 = 8;
const REGEX_ACCEPT_AND_CONSUME: i32 = -995;
const REGEX_REJECT: i32 = -993;

pub fn executeMatchAnyButNewlineChar(state: anytype, matcher: u64, regex_state: u64) bool {
    if (state.guestMemoryConst(matcher, 16) == null or state.guestMemory(regex_state, 96) == null) return false;
    const current = state.read64(regex_state + REGEX_STATE_CURRENT_OFFSET);
    const last = state.read64(regex_state + REGEX_STATE_LAST_OFFSET);
    if (current != last) {
        const character = state.guestMemoryConst(current, 1) orelse return false;
        if (character[0] != '\r' and character[0] != '\n') {
            state.write32(regex_state + REGEX_STATE_DO_OFFSET, @bitCast(REGEX_ACCEPT_AND_CONSUME));
            state.write64(regex_state + REGEX_STATE_CURRENT_OFFSET, current + 1);
            state.write64(regex_state + REGEX_STATE_NODE_OFFSET, state.read64(matcher + MATCHER_FIRST_NODE_OFFSET));
            return true;
        }
    }
    state.write32(regex_state + REGEX_STATE_DO_OFFSET, @bitCast(REGEX_REJECT));
    state.write64(regex_state + REGEX_STATE_NODE_OFFSET, 0);
    return true;
}

const TestState = struct {
    mem: [256]u8 = [_]u8{0} ** 256,

    fn guestMemory(self: *TestState, address: u64, count: u64) ?[]u8 {
        if (address + count > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + count)];
    }

    fn guestMemoryConst(self: *const TestState, address: u64, count: u64) ?[]const u8 {
        if (address + count > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + count)];
    }

    fn read64(self: *const TestState, address: u64) u64 {
        return std.mem.readInt(u64, self.mem[@intCast(address)..][0..8], .little);
    }

    fn write32(self: *TestState, address: u64, value: u32) void {
        std.mem.writeInt(u32, self.mem[@intCast(address)..][0..4], value, .little);
    }

    fn write64(self: *TestState, address: u64, value: u64) void {
        std.mem.writeInt(u64, self.mem[@intCast(address)..][0..8], value, .little);
    }
};

test "symbol normalization and contract lookup" {
    try std.testing.expectEqualStrings("open", normalizeSymbol("_open$INODE64"));
    try std.testing.expectEqual(Domain.libcxx, classifyDomain("__ZNSt3__15mutex4lockEv"));
    try std.testing.expectEqual(ContractId.libcxx_match_any_but_newline_char, contractFor("__ZNKSt3__123__match_any_but_newlineIcE6__execERNS_7__stateIcEE").?.id);
    try std.testing.expectEqual(ContractId.libcxx_basic_string_push_back_char, contractFor("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE9push_backEc").?.id);
    try std.testing.expectEqual(ContractId.libcxx_basic_string_init_fill, contractFor("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6__initEmc").?.id);
}

test "import audit separates resolved and unresolved calls" {
    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();
    engine.record("_open", "main", "<main>", .execution, .resolved, .legacy_shim, .modeled);
    engine.record("_missing", "main", "<main>", .execution, .unresolved, .none, .unknown);
    try std.testing.expectEqual(@as(u64, 2), engine.total_calls);
    try std.testing.expectEqual(@as(u64, 1), engine.resolved_calls);
    try std.testing.expectEqual(@as(u64, 1), engine.unresolved_calls);
}

test "libc++ newline matcher contract accepts ordinary bytes and rejects newlines" {
    var state = TestState{};
    const matcher: u64 = 16;
    const regex_state: u64 = 64;
    state.write64(matcher + MATCHER_FIRST_NODE_OFFSET, 0xB0);
    state.mem[200] = 'x';
    state.write64(regex_state + REGEX_STATE_CURRENT_OFFSET, 200);
    state.write64(regex_state + REGEX_STATE_LAST_OFFSET, 201);
    try std.testing.expect(executeMatchAnyButNewlineChar(&state, matcher, regex_state));
    try std.testing.expectEqual(@as(u64, 201), state.read64(regex_state + REGEX_STATE_CURRENT_OFFSET));
    try std.testing.expectEqual(@as(u64, 0xB0), state.read64(regex_state + REGEX_STATE_NODE_OFFSET));
    try std.testing.expectEqual(@as(u32, @bitCast(REGEX_ACCEPT_AND_CONSUME)), std.mem.readInt(u32, state.mem[64..68], .little));

    state.mem[200] = '\n';
    state.write64(regex_state + REGEX_STATE_CURRENT_OFFSET, 200);
    try std.testing.expect(executeMatchAnyButNewlineChar(&state, matcher, regex_state));
    try std.testing.expectEqual(@as(u64, 200), state.read64(regex_state + REGEX_STATE_CURRENT_OFFSET));
    try std.testing.expectEqual(@as(u64, 0), state.read64(regex_state + REGEX_STATE_NODE_OFFSET));
    try std.testing.expectEqual(@as(u32, @bitCast(REGEX_REJECT)), std.mem.readInt(u32, state.mem[64..68], .little));
}
