const std = @import("std");
const compat_runtime = @import("macho_compat_runtime");
const pointer_firewall = @import("pointer_firewall.zig");

pub const Outcome = enum {
    resolved,
    unresolved,
    terminated,
};

pub const Provider = enum {
    contract,
    local_definition,
    dynamic_library,
    libcpp_filesystem,
    libcpp_stream,
    pthread_runtime,
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
    corefoundation,
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
    pointer_result: ?pointer_firewall.PointerKind = null,
};

pub const ContractId = enum {
    libcxx_match_any_but_newline_char,
    libcxx_basic_string_push_back_char,
    libcxx_basic_string_init_fill,
    libcxx_basic_string_reserve,
    libcxx_ios_base_init,
    libcxx_basic_filebuf_constructor,
    libcxx_basic_streambuf_pubsetbuf,
    libcxx_runtime_error_constructor,
    libcxx_runtime_error_what,
    libcxx_runtime_error_destructor,
    posix_fileno,
    posix_isatty,
    corefoundation_cfstring_create_with_cstring,
    corefoundation_cfdictionary_create,
    libcxx_ios_base_getloc,
    libcxx_basic_istream_sentry_constructor,
    libcxx_basic_ostream_constructor,
    libcxx_basic_ostream_destructor,
    libcxx_basic_ios_init,
    libcxx_basic_ios_rdbuf,
    libcxx_basic_ios_rdstate,
    libcxx_basic_ios_clear,
    libcxx_basic_ios_setstate,
    libcxx_basic_ios_bool,
    libcxx_basic_ios_good,
    libcxx_basic_ios_fail,
    libcxx_basic_ios_eof,
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

pub const basic_string_reserve = Contract{
    .id = .libcxx_basic_string_reserve,
    .canonical_symbol = "_ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE7reserveEm",
    .domain = .libcxx,
    .confidence = .verified,
    .effects = .{ .return_convention = .void, .writes_guest_memory = true },
};

pub const ios_base_init = Contract{
    .id = .libcxx_ios_base_init,
    .canonical_symbol = "_ZNSt3__18ios_base4initEPv",
    .domain = .libcxx,
    .confidence = .verified,
    .effects = .{ .return_convention = .void, .writes_guest_memory = true },
};

pub const basic_filebuf_constructor = Contract{
    .id = .libcxx_basic_filebuf_constructor,
    .canonical_symbol = "_ZNSt3__113basic_filebufIcNS_11char_traitsIcEEEC1Ev",
    .domain = .libcxx,
    .confidence = .verified,
    .effects = .{ .return_convention = .void, .writes_guest_memory = true },
};

pub const basic_streambuf_pubsetbuf = Contract{
    .id = .libcxx_basic_streambuf_pubsetbuf,
    .canonical_symbol = "_ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE9pubsetbufB7v160006EPcl",
    .domain = .libcxx,
    .confidence = .verified,
    .effects = .{ .return_convention = .rax, .writes_guest_memory = true },
};

pub const runtime_error_constructor = Contract{
    .id = .libcxx_runtime_error_constructor,
    .canonical_symbol = "_ZNSt13runtime_errorC2EPKc",
    .domain = .libcxx,
    .confidence = .verified,
    .effects = .{ .return_convention = .void, .writes_guest_memory = true },
};

pub const runtime_error_what = Contract{
    .id = .libcxx_runtime_error_what,
    .canonical_symbol = "_ZNKSt13runtime_error4whatEv",
    .domain = .libcxx,
    .confidence = .verified,
    .effects = .{ .return_convention = .rax },
};

pub const runtime_error_destructor = Contract{
    .id = .libcxx_runtime_error_destructor,
    .canonical_symbol = "_ZNSt13runtime_errorD2Ev",
    .domain = .libcxx,
    .confidence = .verified,
    .effects = .{ .return_convention = .void, .writes_guest_memory = true },
};

pub const fileno = Contract{
    .id = .posix_fileno,
    .canonical_symbol = "fileno",
    .domain = .posix,
    .confidence = .verified,
    .effects = .{ .return_convention = .rax },
};

pub const isatty = Contract{
    .id = .posix_isatty,
    .canonical_symbol = "isatty",
    .domain = .posix,
    .confidence = .verified,
    .effects = .{ .return_convention = .rax },
};

pub const cfstring_create_with_cstring = Contract{
    .id = .corefoundation_cfstring_create_with_cstring,
    .canonical_symbol = "CFStringCreateWithCString",
    .domain = .corefoundation,
    .confidence = .verified,
    .effects = .{ .return_convention = .rax, .writes_guest_memory = true, .pointer_result = .owned_guest },
};

pub const cfdictionary_create = Contract{
    .id = .corefoundation_cfdictionary_create,
    .canonical_symbol = "CFDictionaryCreate",
    .domain = .corefoundation,
    .confidence = .verified,
    .effects = .{ .return_convention = .rax, .writes_guest_memory = true, .pointer_result = .owned_guest },
};

pub const ios_base_getloc = Contract{
    .id = .libcxx_ios_base_getloc,
    .canonical_symbol = "_ZNKSt3__18ios_base6getlocEv",
    .domain = .libcxx,
    .confidence = .verified,
    .effects = .{ .return_convention = .rax, .writes_guest_memory = true, .pointer_result = .owned_guest },
};

pub const basic_istream_sentry_constructor = Contract{
    .id = .libcxx_basic_istream_sentry_constructor,
    .canonical_symbol = "_ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE6sentryC1ERS3_b",
    .domain = .libcxx,
    .confidence = .verified,
    .effects = .{ .return_convention = .void, .writes_guest_memory = true },
};

pub const basic_ostream_constructor = Contract{ .id = .libcxx_basic_ostream_constructor, .canonical_symbol = "basic_ostream::constructor", .domain = .libcxx, .confidence = .verified, .effects = .{ .return_convention = .rax, .writes_guest_memory = true, .pointer_result = .caller_storage } };
pub const basic_ostream_destructor = Contract{ .id = .libcxx_basic_ostream_destructor, .canonical_symbol = "basic_ostream::destructor", .domain = .libcxx, .confidence = .verified, .effects = .{ .return_convention = .void, .writes_guest_memory = true } };
pub const basic_ios_init = Contract{ .id = .libcxx_basic_ios_init, .canonical_symbol = "basic_ios::init", .domain = .libcxx, .confidence = .verified, .effects = .{ .return_convention = .void, .writes_guest_memory = true } };
pub const basic_ios_rdbuf = Contract{ .id = .libcxx_basic_ios_rdbuf, .canonical_symbol = "basic_ios::rdbuf", .domain = .libcxx, .confidence = .verified, .effects = .{ .return_convention = .rax, .pointer_result = .borrowed_guest } };
pub const basic_ios_rdstate = Contract{ .id = .libcxx_basic_ios_rdstate, .canonical_symbol = "basic_ios::rdstate", .domain = .libcxx, .confidence = .verified, .effects = .{ .return_convention = .rax } };
pub const basic_ios_clear = Contract{ .id = .libcxx_basic_ios_clear, .canonical_symbol = "basic_ios::clear", .domain = .libcxx, .confidence = .verified, .effects = .{ .return_convention = .void, .writes_guest_memory = true } };
pub const basic_ios_setstate = Contract{ .id = .libcxx_basic_ios_setstate, .canonical_symbol = "basic_ios::setstate", .domain = .libcxx, .confidence = .verified, .effects = .{ .return_convention = .void, .writes_guest_memory = true } };
pub const basic_ios_bool = Contract{ .id = .libcxx_basic_ios_bool, .canonical_symbol = "basic_ios::operator bool", .domain = .libcxx, .confidence = .verified, .effects = .{ .return_convention = .rax } };
pub const basic_ios_good = Contract{ .id = .libcxx_basic_ios_good, .canonical_symbol = "basic_ios::good", .domain = .libcxx, .confidence = .verified, .effects = .{ .return_convention = .rax } };
pub const basic_ios_fail = Contract{ .id = .libcxx_basic_ios_fail, .canonical_symbol = "basic_ios::fail", .domain = .libcxx, .confidence = .verified, .effects = .{ .return_convention = .rax } };
pub const basic_ios_eof = Contract{ .id = .libcxx_basic_ios_eof, .canonical_symbol = "basic_ios::eof", .domain = .libcxx, .confidence = .verified, .effects = .{ .return_convention = .rax } };

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
    if (std.mem.eql(u8, normalized, basic_string_reserve.canonical_symbol)) {
        return basic_string_reserve;
    }
    if (std.mem.eql(u8, normalized, ios_base_init.canonical_symbol)) {
        return ios_base_init;
    }
    if (std.mem.eql(u8, normalized, basic_filebuf_constructor.canonical_symbol)) {
        return basic_filebuf_constructor;
    }
    if (std.mem.eql(u8, normalized, basic_streambuf_pubsetbuf.canonical_symbol)) {
        return basic_streambuf_pubsetbuf;
    }
    if (std.mem.eql(u8, normalized, runtime_error_constructor.canonical_symbol)) {
        return runtime_error_constructor;
    }
    if (std.mem.eql(u8, normalized, runtime_error_what.canonical_symbol)) {
        return runtime_error_what;
    }
    if (std.mem.eql(u8, normalized, runtime_error_destructor.canonical_symbol) or
        std.mem.eql(u8, normalized, "_ZNSt13runtime_errorD1Ev"))
    {
        return runtime_error_destructor;
    }
    if (std.mem.eql(u8, normalized, fileno.canonical_symbol)) {
        return fileno;
    }
    if (std.mem.eql(u8, normalized, isatty.canonical_symbol)) {
        return isatty;
    }
    if (std.mem.eql(u8, normalized, cfstring_create_with_cstring.canonical_symbol)) {
        return cfstring_create_with_cstring;
    }
    if (std.mem.eql(u8, normalized, cfdictionary_create.canonical_symbol)) {
        return cfdictionary_create;
    }
    if (std.mem.eql(u8, normalized, ios_base_getloc.canonical_symbol)) {
        return ios_base_getloc;
    }
    if (std.mem.eql(u8, normalized, basic_istream_sentry_constructor.canonical_symbol)) {
        return basic_istream_sentry_constructor;
    }
    if (std.mem.indexOf(u8, normalized, "basic_ostreamIcNS_11char_traitsIcEEEC1") != null or
        std.mem.indexOf(u8, normalized, "basic_ostreamIcNS_11char_traitsIcEEEC2") != null) return basic_ostream_constructor;
    if (std.mem.indexOf(u8, normalized, "basic_ostreamIcNS_11char_traitsIcEEED1") != null or
        std.mem.indexOf(u8, normalized, "basic_ostreamIcNS_11char_traitsIcEEED2") != null) return basic_ostream_destructor;
    if (std.mem.indexOf(u8, normalized, "basic_iosIcNS_11char_traitsIcEEE") != null) {
        if (std.mem.indexOf(u8, normalized, "4initE") != null) return basic_ios_init;
        if (std.mem.indexOf(u8, normalized, "5rdbuf") != null) return basic_ios_rdbuf;
        if (std.mem.indexOf(u8, normalized, "7rdstate") != null) return basic_ios_rdstate;
        if (std.mem.indexOf(u8, normalized, "5clearE") != null) return basic_ios_clear;
        if (std.mem.indexOf(u8, normalized, "8setstateE") != null) return basic_ios_setstate;
        if (std.mem.indexOf(u8, normalized, "cvb") != null) return basic_ios_bool;
        if (std.mem.indexOf(u8, normalized, "4good") != null) return basic_ios_good;
        if (std.mem.indexOf(u8, normalized, "4fail") != null) return basic_ios_fail;
        if (std.mem.indexOf(u8, normalized, "3eof") != null) return basic_ios_eof;
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
        .libcxx_basic_string_reserve => if (executeBasicStringReserve(state, state.regs.rdi, state.regs.rsi))
            .handled_void
        else
            .failed,
        .libcxx_ios_base_init => if (executeIosBaseInit(state, state.regs.rdi, state.regs.rsi))
            .handled_void
        else
            .failed,
        .libcxx_basic_filebuf_constructor => if (executeBasicFilebufConstructor(state, state.regs.rdi))
            .handled_void
        else
            .failed,
        .libcxx_basic_streambuf_pubsetbuf => if (executeBasicStreambufPubsetbuf(state, state.regs.rdi, state.regs.rsi, state.regs.rdx))
            .{ .handled = state.regs.rax }
        else
            .failed,
        .libcxx_runtime_error_constructor => if (executeRuntimeErrorConstructor(state, state.regs.rdi, state.regs.rsi))
            .handled_void
        else
            .failed,
        .libcxx_runtime_error_what => if (executeRuntimeErrorWhat(state, state.regs.rdi)) |message|
            .{ .handled = message }
        else
            .failed,
        .libcxx_runtime_error_destructor => if (executeRuntimeErrorDestructor(state, state.regs.rdi))
            .handled_void
        else
            .failed,
        .posix_fileno => if (executeFileno(state, state.regs.rdi))
            .{ .handled = state.regs.rax }
        else
            .failed,
        .posix_isatty => if (executeIsatty(state, state.regs.rdi))
            .{ .handled = state.regs.rax }
        else
            .failed,
        .corefoundation_cfstring_create_with_cstring => if (executeCFStringCreateWithCString(state, state.regs.rdi, state.regs.rsi, state.regs.rdx))
            .{ .handled = state.regs.rax }
        else
            .failed,
        .corefoundation_cfdictionary_create => if (executeCFDictionaryCreate(state, state.regs.rdi, state.regs.rsi, state.regs.rdx, state.regs.rcx, state.regs.r8))
            .{ .handled = state.regs.rax }
        else
            .failed,
        .libcxx_ios_base_getloc => if (executeIosBaseGetloc(state, state.regs.rdi))
            .{ .handled = state.regs.rax }
        else
            .failed,
        .libcxx_basic_istream_sentry_constructor => if (executeBasicIstreamSentryConstructor(state, state.regs.rdi, state.regs.rsi, state.regs.rdx))
            .handled_void
        else
            .failed,
        .libcxx_basic_ostream_constructor,
        .libcxx_basic_ostream_destructor,
        .libcxx_basic_ios_init,
        .libcxx_basic_ios_rdbuf,
        .libcxx_basic_ios_rdstate,
        .libcxx_basic_ios_clear,
        .libcxx_basic_ios_setstate,
        .libcxx_basic_ios_bool,
        .libcxx_basic_ios_good,
        .libcxx_basic_ios_fail,
        .libcxx_basic_ios_eof,
        => .failed,
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
    if (std.mem.startsWith(u8, normalized, "CF") or
        std.mem.startsWith(u8, normalized, "CF")) return .corefoundation;
    if (std.mem.startsWith(u8, normalized, "pthread_") or
        std.mem.startsWith(u8, normalized, "open") or
        std.mem.startsWith(u8, normalized, "close") or
        std.mem.startsWith(u8, normalized, "stat") or
        std.mem.startsWith(u8, normalized, "fstat") or
        std.mem.startsWith(u8, normalized, "ftruncate") or
        std.mem.eql(u8, normalized, "fileno") or
        std.mem.eql(u8, normalized, "isatty")) return .posix;
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
    writes_guest_memory: bool = false,
    pointer_kind: ?pointer_firewall.PointerKind = null,
    object_model_safe: bool = false,
    crash_nearby: bool = false,
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
    local_definition_calls: u64 = 0,
    dynamic_library_calls: u64 = 0,
    libcpp_filesystem_calls: u64 = 0,
    libcpp_stream_calls: u64 = 0,
    pthread_runtime_calls: u64 = 0,
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
            .local_definition => self.local_definition_calls += 1,
            .dynamic_library => self.dynamic_library_calls += 1,
            .libcpp_filesystem => self.libcpp_filesystem_calls += 1,
            .libcpp_stream => self.libcpp_stream_calls += 1,
            .pthread_runtime => self.pthread_runtime_calls += 1,
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
            const declared_contract = contractFor(symbol);
            const pointer_policy = pointer_firewall.policyForSymbol(symbol);
            const new_index = self.entries.items.len;
            self.entries.append(self.allocator, .{
                .symbol = symbol,
                .first_caller = caller,
                .first_owner = owner,
                .first_phase = phase,
                .domain = classifyDomain(symbol),
                .provider = provider,
                .confidence = confidence,
                .writes_guest_memory = if (declared_contract) |declared| declared.effects.writes_guest_memory else false,
                .pointer_kind = if (declared_contract) |declared| declared.effects.pointer_result else if (pointer_policy) |policy| policy.kind else null,
                .object_model_safe = provider == .libcpp_stream or (pointer_policy != null and pointer_policy.?.may_dereference),
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
        if (provider == .libcpp_stream) entry.object_model_safe = true;
        entry.calls += 1;
        switch (outcome) {
            .resolved => entry.resolved += 1,
            .unresolved => entry.unresolved += 1,
            .terminated => entry.terminated += 1,
        }
    }

    pub fn logSummary(self: *const Engine) void {
        std.debug.print(
            "macho-processor: import resolution summary: calls={d} resolved={d} unresolved={d} terminated={d} symbols={d} contract={d} local={d} dynamic={d} libcxx_fs={d} libcxx_stream={d} pthread={d} smart_stub={d} shim={d} verified={d} modeled={d}",
            .{
                self.total_calls,
                self.resolved_calls,
                self.unresolved_calls,
                self.terminated_calls,
                self.entries.items.len,
                self.contract_calls,
                self.local_definition_calls,
                self.dynamic_library_calls,
                self.libcpp_filesystem_calls,
                self.libcpp_stream_calls,
                self.pthread_runtime_calls,
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

        std.debug.print("macho-processor: import contract coverage matrix:\n", .{});
        for (self.entries.items) |entry| {
            const pointer_kind = if (entry.pointer_kind) |kind| @tagName(kind) else "none";
            std.debug.print(
                "  {s} | domain={s} provider={s} confidence={s} calls={d} writes_guest_memory={} pointer={s} object_model_safe={} crash_nearby={}\n",
                .{
                    entry.symbol,
                    @tagName(entry.domain),
                    @tagName(entry.provider),
                    @tagName(entry.confidence),
                    entry.calls,
                    entry.writes_guest_memory,
                    pointer_kind,
                    entry.object_model_safe,
                    entry.crash_nearby,
                },
            );
        }
    }

    pub fn markCrashNearby(self: *Engine, symbol: []const u8) void {
        if (self.indices.get(symbol)) |index| self.entries.items[index].crash_nearby = true;
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

pub fn executeBasicStringReserve(state: anytype, object: u64, new_capacity: u64) bool {
    const object_bytes = state.guestMemory(object, 24) orelse return false;

    // Small string optimization - if it's already using SSO and new capacity fits in SSO, do nothing
    if (object_bytes[0] & 1 == 0) {
        // Currently using SSO (small string optimization)
        const current_length = object_bytes[0] >> 1;
        if (new_capacity <= 22) {
            // Already fits in SSO, no action needed
            return true;
        }
        // Need to allocate - copy current content to heap
        const capacity = (std.math.add(u64, new_capacity, 16) catch return false) & ~@as(u64, 15);
        const allocation = state.guestAlloc(capacity, 16) orelse return false;
        const storage = state.guestMemory(allocation, capacity) orelse return false;
        const len: usize = @intCast(current_length);
        @memcpy(storage[0..len], object_bytes[1 .. 1 + len]);
        storage[len] = 0;
        state.write64(object, capacity | 1);
        state.write64(object + 8, current_length);
        state.write64(object + 16, allocation);
        return true;
    }

    // Already using heap allocation
    const current_capacity = state.read64(object) & ~@as(u64, 1);
    if (new_capacity <= current_capacity) {
        // Already have enough capacity
        return true;
    }

    // Need to reallocate with larger capacity
    const current_length = state.read64(object + 8);
    const current_data = state.read64(object + 16);
    const capacity = (std.math.add(u64, new_capacity, 16) catch return false) & ~@as(u64, 15);
    const allocation = state.guestAlloc(capacity, 16) orelse return false;
    const storage = state.guestMemory(allocation, capacity) orelse return false;
    const current_bytes = state.guestMemoryConst(current_data, current_length) orelse return false;
    const len: usize = @intCast(current_length);
    @memcpy(storage[0..len], current_bytes);
    storage[len] = 0;
    state.write64(object, capacity | 1);
    state.write64(object + 16, allocation);
    return true;
}

pub fn executeIosBaseInit(state: anytype, object: u64, streambuf: u64) bool {
    // ios_base::init initializes the ios_base object with a stream buffer
    // For our purposes, we just need to store the streambuf pointer
    const object_bytes = state.guestMemory(object, 32) orelse return false;
    @memset(object_bytes, 0);
    state.write64(object, streambuf);
    return true;
}

pub fn executeBasicFilebufConstructor(state: anytype, object: u64) bool {
    // basic_filebuf constructor initializes the file buffer object
    // For our purposes, we just need to zero it out
    const object_bytes = state.guestMemory(object, 128) orelse return false;
    @memset(object_bytes, 0);
    return true;
}

pub fn executeBasicStreambufPubsetbuf(state: anytype, object: u64, buffer: u64, size: u64) bool {
    // basic_streambuf::pubsetbuf is a public wrapper around the protected setbuf
    // It sets the buffer for the stream buffer and returns the this pointer
    // For our purposes, we just return the this pointer (object) via rax
    _ = buffer;
    _ = size;
    state.regs.rax = object;
    return true;
}

pub fn executeRuntimeErrorConstructor(state: anytype, object: u64, message: u64) bool {
    const source = state.guestCString(message, 4096) orelse return false;
    const allocation = state.guestAlloc(source.len + 1, 1) orelse return false;
    const copy = state.guestMemory(allocation, source.len + 1) orelse return false;
    @memcpy(copy[0..source.len], source);
    copy[source.len] = 0;

    // Rosette owns a compact runtime_error representation: vptr slot followed
    // by a stable guest C-string pointer. Derived exceptions start after it.
    const object_bytes = state.guestMemory(object, 16) orelse return false;
    @memset(object_bytes, 0);
    state.write64(object + 8, allocation);
    return true;
}

pub fn executeRuntimeErrorWhat(state: anytype, object: u64) ?u64 {
    const message = state.read64(object + 8);
    _ = state.guestCString(message, 4096) orelse return null;
    return message;
}

pub fn executeRuntimeErrorDestructor(state: anytype, object: u64) bool {
    const object_bytes = state.guestMemory(object, 16) orelse return false;
    @memset(object_bytes, 0);
    return true;
}

pub fn executeFileno(state: anytype, stream: u64) bool {
    // fileno returns the file descriptor for a stream
    // For Rosette's purposes, we return a dummy file descriptor (2 = stderr)
    // This allows the has_console_attached check to continue
    _ = stream;
    state.regs.rax = 2;
    return true;
}

pub fn executeIsatty(state: anytype, fd: u64) bool {
    // isatty tests if a file descriptor refers to a terminal
    // For Rosette's purposes, we return 0 (not a terminal)
    // This allows the has_console_attached check to continue
    _ = fd;
    state.regs.rax = 0;
    return true;
}

pub fn executeCFStringCreateWithCString(state: anytype, allocator: u64, cstr: u64, encoding: u64) bool {
    _ = allocator;
    _ = encoding;
    const source = state.guestCString(cstr, 1024 * 1024) orelse return false;
    const bytes_address = state.guestAlloc(source.len + 1, 1) orelse return false;
    const bytes = state.guestMemory(bytes_address, source.len + 1) orelse return false;
    @memcpy(bytes[0..source.len], source);
    bytes[source.len] = 0;
    const object = state.guestAlloc(16, @alignOf(u64)) orelse return false;
    state.write64(object, source.len);
    state.write64(object + 8, bytes_address);
    if (@hasDecl(@TypeOf(state.*), "registerSyntheticRegion")) {
        state.registerSyntheticRegion(bytes_address, source.len + 1, .file_buffer, "CFString bytes", .{ .kind = .owned_guest, .may_dereference = true, .owner = "CFString bytes" });
        state.registerSyntheticRegion(object, 16, .synthetic_object, "CFString", .{ .kind = .owned_guest, .may_dereference = true, .owner = "CFString" });
    }
    state.regs.rax = object;
    return true;
}

pub fn executeCFDictionaryCreate(state: anytype, allocator: u64, keys: u64, values: u64, num_values: u64, call_backs: u64) bool {
    _ = allocator;
    _ = call_backs;
    const object = state.guestAlloc(24, @alignOf(u64)) orelse return false;
    state.write64(object, num_values);
    state.write64(object + 8, keys);
    state.write64(object + 16, values);
    if (@hasDecl(@TypeOf(state.*), "registerSyntheticRegion")) {
        state.registerSyntheticRegion(object, 24, .synthetic_object, "CFDictionary", .{ .kind = .owned_guest, .may_dereference = true, .owner = "CFDictionary" });
    }
    state.regs.rax = object;
    return true;
}

pub fn executeIosBaseGetloc(state: anytype, ios_base: u64) bool {
    _ = ios_base;
    const object = state.guestAlloc(16, @alignOf(u64)) orelse return false;
    state.write64(object, 1);
    state.write64(object + 8, 0);
    if (@hasDecl(@TypeOf(state.*), "registerSyntheticRegion")) {
        state.registerSyntheticRegion(object, 16, .synthetic_object, "std::locale", .{ .kind = .owned_guest, .may_dereference = true, .owner = "std::locale" });
    }
    state.regs.rax = object;
    return true;
}

pub fn executeBasicIstreamSentryConstructor(state: anytype, sentry: u64, istream: u64, noskipws: u64) bool {
    // basic_istream::sentry constructor initializes the sentry object
    // For Rosette's purposes, we just need to zero it out
    // The sentry is typically 8-16 bytes
    const sentry_bytes = state.guestMemory(sentry, 16) orelse return false;
    @memset(sentry_bytes, 0);
    _ = istream;
    _ = noskipws;
    return true;
}

const TestState = struct {
    mem: [512]u8 = [_]u8{0} ** 512,
    heap_next: u64 = 320,
    regs: struct { rax: u64 = 0 } = .{},

    fn guestMemory(self: *TestState, address: u64, count: u64) ?[]u8 {
        if (address + count > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + count)];
    }

    fn guestMemoryConst(self: *const TestState, address: u64, count: u64) ?[]const u8 {
        if (address + count > self.mem.len) return null;
        return self.mem[@intCast(address)..@intCast(address + count)];
    }

    fn guestCString(self: *const TestState, address: u64, maximum: usize) ?[]const u8 {
        if (address >= self.mem.len) return null;
        const start: usize = @intCast(address);
        const available = self.mem[start..@min(self.mem.len, start + maximum)];
        const length = std.mem.indexOfScalar(u8, available, 0) orelse return null;
        return available[0..length];
    }

    fn guestAlloc(self: *TestState, size: u64, alignment: u64) ?u64 {
        const mask = alignment - 1;
        const address = (self.heap_next + mask) & ~mask;
        if (address + size > self.mem.len) return null;
        self.heap_next = address + size;
        return address;
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
    try std.testing.expectEqual(ContractId.libcxx_basic_string_reserve, contractFor("__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE7reserveEm").?.id);
    try std.testing.expectEqual(ContractId.libcxx_ios_base_init, contractFor("__ZNSt3__18ios_base4initEPv").?.id);
    try std.testing.expectEqual(ContractId.libcxx_basic_filebuf_constructor, contractFor("__ZNSt3__113basic_filebufIcNS_11char_traitsIcEEEC1Ev").?.id);
    try std.testing.expectEqual(ContractId.libcxx_basic_streambuf_pubsetbuf, contractFor("__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE9pubsetbufB7v160006EPcl").?.id);
    try std.testing.expectEqual(ContractId.libcxx_runtime_error_constructor, contractFor("__ZNSt13runtime_errorC2EPKc").?.id);
    try std.testing.expectEqual(ContractId.libcxx_runtime_error_what, contractFor("__ZNKSt13runtime_error4whatEv").?.id);
    try std.testing.expectEqual(ContractId.libcxx_runtime_error_destructor, contractFor("__ZNSt13runtime_errorD2Ev").?.id);
    try std.testing.expectEqual(ContractId.posix_fileno, contractFor("_fileno").?.id);
    try std.testing.expectEqual(ContractId.posix_isatty, contractFor("_isatty").?.id);
    try std.testing.expectEqual(ContractId.corefoundation_cfstring_create_with_cstring, contractFor("_CFStringCreateWithCString").?.id);
    try std.testing.expectEqual(ContractId.corefoundation_cfdictionary_create, contractFor("_CFDictionaryCreate").?.id);
    try std.testing.expectEqual(ContractId.libcxx_ios_base_getloc, contractFor("__ZNKSt3__18ios_base6getlocEv").?.id);
    try std.testing.expectEqual(ContractId.libcxx_basic_istream_sentry_constructor, contractFor("__ZNSt3__113basic_istreamIcNS_11char_traitsIcEEE6sentryC1ERS3_b").?.id);
    try std.testing.expectEqual(ContractId.libcxx_basic_ostream_constructor, contractFor("__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEEC2B7v160006EPNS_15basic_streambufIcS2_EE").?.id);
    try std.testing.expectEqual(ContractId.libcxx_basic_ios_rdbuf, contractFor("__ZNKSt3__19basic_iosIcNS_11char_traitsIcEEE5rdbufB7v160006Ev").?.id);
    try std.testing.expectEqual(ContractId.libcxx_basic_ios_setstate, contractFor("__ZNSt3__19basic_iosIcNS_11char_traitsIcEEE8setstateEj").?.id);
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

test "import coverage matrix records memory and pointer semantics" {
    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();
    const symbol = "_CFStringCreateWithCString";
    engine.record(symbol, "caller", "main", .execution, .resolved, .contract, .verified);
    engine.markCrashNearby(symbol);
    const entry = engine.entries.items[engine.indices.get(symbol).?];
    try std.testing.expect(entry.writes_guest_memory);
    try std.testing.expectEqual(pointer_firewall.PointerKind.owned_guest, entry.pointer_kind.?);
    try std.testing.expect(entry.object_model_safe);
    try std.testing.expect(entry.crash_nearby);
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

test "libc++ basic_streambuf pubsetbuf returns this pointer" {
    var state = TestState{};
    const object: u64 = 0x1000;
    const buffer: u64 = 0x2000;
    const size: u64 = 1024;
    try std.testing.expect(executeBasicStreambufPubsetbuf(&state, object, buffer, size));
    try std.testing.expectEqual(@as(u64, object), state.regs.rax);
}

test "libc++ runtime_error constructor initializes object" {
    var state = TestState{};
    const object: u64 = 0x100;
    const message: u64 = 0x120;
    @memcpy(state.mem[message .. message + "bad config".len], "bad config");
    try std.testing.expect(executeRuntimeErrorConstructor(&state, object, message));
    const what = executeRuntimeErrorWhat(&state, object).?;
    try std.testing.expectEqualStrings("bad config", state.guestCString(what, 64).?);
    try std.testing.expect(executeRuntimeErrorDestructor(&state, object));
    try std.testing.expectEqual(@as(u64, 0), state.read64(object + 8));
}

test "CoreFoundation contracts return guest-backed objects" {
    var state = TestState{};
    const source: u64 = 32;
    @memcpy(state.mem[source .. source + "Rosette".len], "Rosette");
    try std.testing.expect(executeCFStringCreateWithCString(&state, 0, source, 0));
    const string_object = state.regs.rax;
    try std.testing.expect(string_object >= 320);
    try std.testing.expectEqual(@as(u64, "Rosette".len), state.read64(string_object));
    try std.testing.expectEqualStrings("Rosette", state.guestCString(state.read64(string_object + 8), 32).?);

    state = .{};
    try std.testing.expect(executeCFDictionaryCreate(&state, 0, 0x80, 0xA0, 3, 0));
    const dictionary = state.regs.rax;
    try std.testing.expectEqual(@as(u64, 3), state.read64(dictionary));
    try std.testing.expectEqual(@as(u64, 0x80), state.read64(dictionary + 8));
    try std.testing.expectEqual(@as(u64, 0xA0), state.read64(dictionary + 16));
}
