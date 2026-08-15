const std = @import("std");
const builtin = @import("builtin");
const x64_decoder = @import("x64_decoder");
const memory_provenance = @import("dyld").memory_provenance;
const pointer_firewall = @import("dyld").pointer_firewall;
const macho = @import("macho.zig");
const constants = @import("constants.zig");

const compat_runtime = @import("macho_compat_runtime");
const guest_assertion_recovery = @import("guest_abi").guest_assertion_recovery;
const Op = x64_decoder.Op;
const Regs = x64_decoder.Regs;
const RegId = x64_decoder.RegId;
const DecodedInsn = x64_decoder.DecodedInsn;
const TOML_CODEPOINT_CAPACITY = constants.TOML_CODEPOINT_CAPACITY;

pub const TomlAsciiBlock = struct {
    reader: u64,
    length: u6,
    bytes: [TOML_CODEPOINT_CAPACITY]u8 = [_]u8{0} ** TOML_CODEPOINT_CAPACITY,
    validated: bool = false,
};

pub const TomlCodepointRepair = struct {
    scalar_repairs: u8 = 0,
    raw_repairs: u8 = 0,
    first_bad_index: ?u8 = null,
    first_bad_scalar: u32 = 0,
    first_bad_raw: u8 = 0,
    first_expected: u8 = 0,
};

pub const GuestAccess = enum {
    read,
    write,
    execute,
};

pub const GuestAccessDescription = struct {
    mapped: bool,
    allowed: bool,
    region: ?memory_provenance.Region,
    pointer_policy: ?pointer_firewall.Policy,
};

pub const MachSegment = macho.MachSegment;

pub const TraceEntry = struct {
    thread_handle: u64 = 0,
    rip: u64 = 0,
    op: Op = .invalid,
    len: u8 = 0,
    rsp: u64 = 0,
    rax: u64 = 0,
    rbx: u64 = 0,
    rcx: u64 = 0,
    rdx: u64 = 0,
    rsi: u64 = 0,
    rdi: u64 = 0,
    rbp: u64 = 0,
    r8: u64 = 0,
    r9: u64 = 0,
    r10: u64 = 0,
    r11: u64 = 0,
    r12: u64 = 0,
    r13: u64 = 0,
    r14: u64 = 0,
    r15: u64 = 0,

    /// The snapshot value of one architectural register.
    ///
    /// The mapping from a decoder `RegId` onto these fields existed three
    /// times — in `near_null_causality`, in `memory_access`, and in
    /// `crash_diag` — byte-identical, which is exactly how a mapping like this
    /// survives being wrong: nothing forces the copies to move together, and
    /// the register file is the input to every history-based causal walk in
    /// the runtime. The type that owns the fields owns the mapping.
    pub fn registerValue(self: TraceEntry, register: RegId) u64 {
        return switch (@intFromEnum(register)) {
            0 => self.rax,
            1 => self.rcx,
            2 => self.rdx,
            3 => self.rbx,
            4 => self.rsp,
            5 => self.rbp,
            6 => self.rsi,
            7 => self.rdi,
            8 => self.r8,
            9 => self.r9,
            10 => self.r10,
            11 => self.r11,
            12 => self.r12,
            13 => self.r13,
            14 => self.r14,
            15 => self.r15,
        };
    }
};

pub const X87Tag = enum(u2) {
    valid = 0b00,
    zero = 0b01,
    special = 0b10,
    empty = 0b11,
};

// The architectural x87 register file is circular.  `top` identifies the
// physical register exposed as ST(0); tags deliberately use physical indexes.
pub const X87State = struct {
    values: [8]f64 = [_]f64{0.0} ** 8,
    tags: [8]X87Tag = [_]X87Tag{.empty} ** 8,
    top: u3 = 0,
    status: u16 = 0,
    control: u16 = 0x037F,

    pub const status_invalid: u16 = 1 << 0;
    pub const status_zero_divide: u16 = 1 << 2;
    pub const status_stack_fault: u16 = 1 << 6;
    pub const status_c1: u16 = 1 << 9;
    pub const status_top_mask: u16 = 0x3800;

    pub fn physical(self: *const X87State, logical: u3) u3 {
        return @truncate(self.top +% logical);
    }

    pub fn statusWord(self: *const X87State) u16 {
        return (self.status & ~status_top_mask) | (@as(u16, self.top) << 11);
    }

    pub fn tagWord(self: *const X87State) u16 {
        var word: u16 = 0;
        for (self.tags, 0..) |tag, index| word |= @as(u16, @intFromEnum(tag)) << @intCast(index * 2);
        return word;
    }

    pub fn classify(value: f64) X87Tag {
        if (value == 0.0) return .zero;
        if (std.math.isFinite(value)) return .valid;
        return .special;
    }

    pub fn stackFault(self: *X87State, overflow: bool) void {
        self.status |= status_invalid | status_stack_fault;
        if (overflow) self.status |= status_c1 else self.status &= ~status_c1;
    }

    pub fn reset(self: *X87State) void {
        self.* = .{};
    }

    pub fn push(self: *X87State, value: f64) bool {
        const next: u3 = @truncate(self.top -% 1);
        if (self.tags[next] != .empty) {
            self.stackFault(true);
            return false;
        }
        self.top = next;
        self.values[next] = value;
        self.tags[next] = classify(value);
        return true;
    }

    pub fn get(self: *X87State, logical: u3) ?f64 {
        const index = self.physical(logical);
        if (self.tags[index] == .empty) {
            self.stackFault(false);
            return null;
        }
        return self.values[index];
    }

    pub fn set(self: *X87State, logical: u3, value: f64) bool {
        const index = self.physical(logical);
        if (self.tags[index] == .empty) {
            self.stackFault(false);
            return false;
        }
        self.values[index] = value;
        self.tags[index] = classify(value);
        return true;
    }

    pub fn pop(self: *X87State) ?f64 {
        const index = self.top;
        if (self.tags[index] == .empty) {
            self.stackFault(false);
            return null;
        }
        const value = self.values[index];
        self.tags[index] = .empty;
        self.top +%= 1;
        return value;
    }

    pub fn exchange(self: *X87State, logical: u3) bool {
        const other = self.physical(logical);
        if (self.tags[self.top] == .empty or self.tags[other] == .empty) {
            self.stackFault(false);
            return false;
        }
        std.mem.swap(f64, &self.values[self.top], &self.values[other]);
        std.mem.swap(X87Tag, &self.tags[self.top], &self.tags[other]);
        return true;
    }

    pub fn free(self: *X87State, logical: u3) void {
        self.tags[self.physical(logical)] = .empty;
    }

    // `operation` uses the architectural operand order already selected by
    // the decoder: add, multiply, subtract, reverse-subtract, divide, and
    // reverse-divide respectively.
    pub fn binary(self: *X87State, destination: u3, source: u3, operation: u3, pop_result: bool) void {
        const lhs = self.get(destination) orelse return;
        const rhs = self.get(source) orelse return;
        const result: f64 = switch (operation) {
            0 => lhs + rhs,
            1 => lhs * rhs,
            2 => lhs - rhs,
            3 => rhs - lhs,
            4 => blk: {
                if (rhs == 0.0) self.status |= status_zero_divide;
                break :blk lhs / rhs;
            },
            5 => blk: {
                if (lhs == 0.0) self.status |= status_zero_divide;
                break :blk rhs / lhs;
            },
            else => unreachable,
        };
        _ = self.set(destination, result);
        if (pop_result) _ = self.pop();
    }
};

pub const ImportTraceEntry = struct {
    symbol: []const u8 = "",
    dylib: []const u8 = "",
    stub_address: u64 = 0,
    return_address: u64 = 0,
    synthetic_result: u64 = 0,
    caller_symbol: []const u8 = "",
    caller_offset: u64 = 0,
};

pub const ControlTransferContext = struct {
    kind: []const u8,
    instruction_address: u64,
    operand_address: u64 = 0,
    target_address: u64,
    return_address: u64 = 0,
};

pub const DecodeCacheEntry = struct {
    rip: u64 = std.math.maxInt(u64),
    code_generation: u64 = 0,
    decoded: DecodedInsn = .{},
    /// Exact bytes used to produce `decoded`. Executable-write notifications
    /// remain the fast invalidation path, while this snapshot is the final
    /// guard against a missed JIT publication or an alternate write route.
    instruction_bytes: [15]u8 = [_]u8{0} ** 15,
    instruction_byte_count: u8 = 0,
    /// Which way of the set survives the next eviction. Exact LRU for two
    /// ways; see `MachOState.noteDecodeCacheUse`.
    recently_used: bool = false,
    /// Raw displacement from `decodeInsn`, before base/index/rip-relative
    /// resolution.  Used on cache hit to re-resolve the operand address
    /// from current register state without double-counting the base
    /// register (which happens when the already-resolved `decoded.addr`
    /// is fed back through `resolveMemoryAddress` as `displacement`).
    displacement: u64 = 0,
};

/// Which 4 KiB pages may have a decode-cache entry in them.
///
/// F4 (throughput audit): `noteGuestWrite` must invalidate any cached decode
/// whose bytes a store touched. An x86 instruction is at most 15 bytes, so a
/// 1-byte store has 15 possible starts, and probing them meant 15 multiplicative
/// hashes into a ~5.8 MB table — 15 uncorrelated cache misses — for *every*
/// byte Xenia's JIT emits.
///
/// The asymmetry this exploits: the emitter writes a code page many times
/// before anything executes from it, and writes plenty of pages nothing ever
/// executes from. A page with no cached decode cannot invalidate anything, and
/// that is answerable with one bit.
///
/// Direction matters for soundness. A set bit means "an entry may exist in this
/// page" and is set when an entry is populated; a clear bit means no entry was
/// ever populated there since the last reset, so nothing can need clearing.
/// Hash collisions in the decode cache can only evict entries, never move one
/// into a page whose bit is clear. Bits are therefore never cleared except by a
/// full flush, which clears the whole table with them.
pub const DecodeCachePageSet = struct {
    /// 4 GiB of guest address space at 4 KiB granularity = 1 Mi pages = 128 KiB
    /// of bitmap. Addresses above that (synthetic thunk space) fold onto the
    /// same bits, which is safe: folding can only make the answer "maybe",
    /// never "no".
    const page_count: usize = 1 << 20;
    const word_count: usize = page_count / 64;

    words: [word_count]u64 = [_]u64{0} ** word_count,

    inline fn pageIndex(address: u64) usize {
        return @intCast((address >> 12) & (page_count - 1));
    }

    pub inline fn note(self: *DecodeCachePageSet, address: u64) void {
        const page = pageIndex(address);
        self.words[page / 64] |= @as(u64, 1) << @truncate(page % 64);
    }

    /// Whether any page spanned by `[first, last]` may hold a cached decode.
    /// The range is at most 15 bytes wide, so it covers one page or two.
    pub inline fn anyCoveringRange(self: *const DecodeCachePageSet, first: u64, last: u64) bool {
        const first_page = pageIndex(first);
        if ((self.words[first_page / 64] >> @truncate(first_page % 64)) & 1 != 0) return true;
        const last_page = pageIndex(last);
        if (last_page == first_page) return false;
        return (self.words[last_page / 64] >> @truncate(last_page % 64)) & 1 != 0;
    }

    pub fn reset(self: *DecodeCachePageSet) void {
        @memset(&self.words, 0);
    }
};

test "decode-cache page set answers per page and never under-reports a noted page" {
    var set = DecodeCachePageSet{};
    try std.testing.expect(!set.anyCoveringRange(0xA000_0000, 0xA000_000F));
    set.note(0xA000_0800);
    try std.testing.expect(set.anyCoveringRange(0xA000_0000, 0xA000_000F));
    // A write straddling a page boundary must consult both pages.
    try std.testing.expect(!set.anyCoveringRange(0xA000_1000, 0xA000_100F));
    try std.testing.expect(set.anyCoveringRange(0x9FFF_FFF9, 0xA000_0007));
    set.reset();
    try std.testing.expect(!set.anyCoveringRange(0xA000_0000, 0xA000_000F));
}

pub const PROGRESS_REPORT_INTERVAL: u64 = 500_000;
pub const HEARTBEAT_INTERVAL: u64 = 25_000_000;

/// Previous-heartbeat readings of the acceleration counters, so the heartbeat
/// can report **deltas** rather than run-cumulative totals.
///
/// Cumulative is the wrong shape for this question. The interpreter's rate is
/// not constant — image load and hashing run several times faster than steady
/// state — so a run-cumulative hit rate averages the fast prefix with the slow
/// body and reports a number that describes neither. Every interesting change
/// to throughput is a change *between* two heartbeats, which is exactly what a
/// cumulative counter cannot show.
///
/// This exists at all because the counters it samples were previously emitted
/// only from the exit path, and the runs that matter are the ones the harness
/// kills at its timeout — where the exit path never executes. A counter that is
/// only readable on a clean exit is not readable on the runs being diagnosed.
pub const PerformanceSample = struct {
    step: u64 = 0,
    wall_ns: u64 = 0,
    decode_cache_hits: u64 = 0,
    decode_cache_misses: u64 = 0,
    decode_cache_stale_rejections: u64 = 0,
    decode_cache_compulsory_misses: u64 = 0,
    decode_cache_conflict_misses: u64 = 0,
    code_generation: u64 = 0,
    import_route_cache_hits: u64 = 0,
    import_route_cache_misses: u64 = 0,
    import_route_cache_slow_hits: u64 = 0,
    import_route_cache_fallbacks: u64 = 0,
    cleo_dispatch_hits: u64 = 0,
    /// False until the first sample is taken; the first heartbeat has no
    /// predecessor and must report that rather than a delta against zero.
    primed: bool = false,
};

pub const ImportHandlerResult = union(enum) {
    handled: u64,
    handled_void,
    control_transferred,
    unsupported: u64,
    terminated: u64,
};

pub const ImportRoute = enum(u8) {
    legacy,
    guest_memory_copy,
    memset,
    bzero,
    coop_main,
    coop_main_quit,
    idle_add,
    idle_source_remove,
    events_pending,
    coop_main_iteration,
    sdl_compat,
    local_definition,
    libcxx_stream,
    foreign_object,
    import_contract,
    libcxx_filesystem,
    /// `pthread_runtime.dispatch` — the POSIX pthread surface.
    ///
    /// This tag used to cover three different owners: this one, the C++
    /// synchronization surface, and the inline `_pthread_once` handler. The
    /// route cache replays a tag by calling *one* function, so every symbol
    /// belonging to either of the other two was cached as `.pthread`, declined
    /// on replay, and fell back through the entire symbol chain — 73,802 times
    /// in a 1.5-billion-step run, which is essentially every C++ lock and
    /// unlock the guest performed. One tag, one owner.
    pthread,
    /// `pthread_runtime.dispatchCppSynchronization` — libc++ mutex/condvar.
    pthread_cpp_sync,
    /// The `_pthread_once` handler, which transfers control to the guest's
    /// initializer rather than returning a value.
    pthread_once,
    dynamic_library,
    shared_contract,
    allocate,
    release,
    reallocate,
    posix_memalign,
    aligned_alloc,
    calloc,
    chkstk,
    sysconf,
    strtoul,
};

pub fn isGtkIdleAddImport(name: []const u8) bool {
    return std.mem.eql(u8, name, "_gdk_threads_add_idle") or
        std.mem.eql(u8, name, "_gdk_threads_add_idle_full") or
        std.mem.eql(u8, name, "_g_idle_add") or
        std.mem.eql(u8, name, "_g_idle_add_full");
}

pub fn isGtkEventsPendingImport(name: []const u8) bool {
    return std.mem.eql(u8, name, "_gtk_events_pending") or
        std.mem.eql(u8, name, "_g_main_context_pending");
}

pub fn isGtkMainIterationImport(name: []const u8) bool {
    return std.mem.eql(u8, name, "_gtk_main_iteration") or
        std.mem.eql(u8, name, "_gtk_main_iteration_do") or
        std.mem.eql(u8, name, "_g_main_context_iteration");
}

pub const ImportRouteCacheEntry = struct {
    stub_address: u64 = 0,
    route: ImportRoute = .legacy,
    valid: bool = false,
};

pub const BulkConstructionRange = struct {
    byte_count: u64,
    new_end: u64,
};

pub const InitializerRunOutcome = enum {
    completed,
    deferred,
    failed,
};

pub const GuestFileKind = enum {
    regular,
    stdout,
    stderr,
};

pub const GuestFile = struct {
    active: bool = false,
    fd: i32 = -1,
    position: i64 = 0,
    error_flag: bool = false,
    kind: GuestFileKind = .regular,
    descriptor_alias: u64 = std.math.maxInt(u64),
    descriptor_generation: u64 = 0,
    descriptor_alias_is_primary: bool = false,
};

pub const BoundImportThunk = struct {
    address: u64,
    name: []const u8,
    dylib: []const u8,
};

pub const InternalCompatibilityTargets = struct {
    xenia_cpu_feature_detector_initialize_cpu_info: u64 = 0,
    xenia_vulkan_provider_vulkan_device: u64 = 0,
    cxxopts_split_option_names: u64 = 0,
    parse_launch_arguments: u64 = 0,
    initialize_logging: u64 = 0,
    shutdown_logging: u64 = 0,
    cvar_add_to_launch_options: [32]u64 = [_]u64{0} ** 32,
    cvar_add_to_launch_options_count: usize = 0,
    guest_log_get_thread_buffer: u64 = 0,
    guest_log_append_formatted: u64 = 0,
    guest_log_append_view: u64 = 0,
    libcxx_basic_streambuf_pubsetbuf: u64 = 0,
    libcxx_basic_ifstream_default_constructor: u64 = 0,
    libcxx_basic_ifstream_destructor_1: u64 = 0,
    libcxx_basic_ifstream_destructor_2: u64 = 0,
    libcxx_getline: u64 = 0,
    libcxx_getline_delimiter: u64 = 0,
    libcxx_basic_string_substr: u64 = 0,
    profile_manager_load_account: u64 = 0,
    profile_manager_dismount_profile: u64 = 0,
    profile_account_insert_or_assign: u64 = 0,
    print_config_to_log: u64 = 0,
    imgui_default_malloc: u64 = 0,
    imgui_default_free: u64 = 0,
    imgui_mem_alloc: u64 = 0,
    imgui_mem_free: u64 = 0,
    imgui_settings_push_back: u64 = 0,
    imgui_create_context: u64 = 0,
    imgui_get_current_window: u64 = 0,
    /// ImGui::TextEx entry. Rosette has no native renderer, so this GUI-only
    /// call is modeled as a no-op rather than entering an incomplete ImGui
    /// object graph during Xenia startup.
    imgui_text_ex: u64 = 0,
    page_entry_construct_at_end: u64 = 0,
    libcpp_atomic_bool_control_block_vtable: u64 = 0,
    /// sha1::SHA1::processBytes — resolved at init for entry-tracking
    sha1_process_bytes: u64 = 0,
    /// Start of the sha1::SHA1 virtual-method table region (inclusive).
    sha1_start: u64 = 0,
    /// End of the sha1::SHA1 virtual-method table region (exclusive).
    sha1_end: u64 = 0,
    /// xe::kernel::XModule vtable, resolved at init for constructor vtable repair
    xmodule_vtable: u64 = 0,
    /// Synthetic XModule vtable allocated when real symbol isn't found
    xmodule_synthetic_vtable: u64 = 0,
    /// Empty string allocated for xmodule_get_name to return
    xmodule_empty_string: u64 = 0,
};

pub const InitializerCheckpoint = struct {
    heap_next: u64,
    compat: compat_runtime.Runtime,
    monotonic_nanoseconds: u64,
    ios_xalloc_next: u64,
    cxxopts_split_accelerations: u64,
    guest_errno_address: u64,
};

pub const CooperativeUiContext = struct {
    regs: Regs,
    xmm: [16][16]u8,
    ymm_hi: [16][16]u8,
    x87: X87State,
    thread: u64 = 0,
    caller: u64 = 0,
};

/// Main loop type for cooperative UI-thread scheduling.
/// Determines which import-handler dispatch paths are active and how the
/// main loop entry/exit is detected.  Defaults to `.gtk` for Xenia
/// compatibility.
///
/// NOTE: Only `.gtk` currently has wired dispatch logic. The other variants
/// are forward-looking scaffolding — they define the type so consuming code
/// can set the field, but `dispatch.zig` only activates GTK interception
/// when `main_loop_type == .gtk`.
pub const MainLoopType = enum {
    /// GTK main loop (g_idle_add, gtk_main, gtk_main_quit, etc.)
    gtk,
    /// macOS NSApplication main loop (NSApplicationMain, NSRunLoop, etc.)
    ns_application,
    /// SDL2 main loop (SDL_PollEvent, SDL_WaitEvent, etc.)
    sdl,
    /// Generic/other main loop — imports are not specially intercepted;
    /// cooperative scheduling still applies but must be triggered by
    /// custom import bindings or direct function patching.
    generic,
};

pub const MAX_IDLE_CALLBACKS = 32;
pub const IDLE_CALLBACK_HANDLE_BASE: u64 = 0xFFFF_F900_0000_0000;

pub const IdleCallback = struct {
    source_id: u64 = 0,
    function: u64 = 0,
    data: u64 = 0,
    /// Second and third integer arguments, for queued callbacks that are not
    /// `GSourceFunc`. A GTK signal handler is invoked as
    /// `handler(instance, detail..., user_data)`, so the queue has to carry
    /// more than the single `gpointer` an idle source takes.
    ///
    /// `extra_arguments` gates them deliberately. A `GSourceFunc` reads only
    /// its first argument, so writing rsi/rdx for one is ABI-legal but it is
    /// still a change to the register state the dispatcher restores from the
    /// cooperative UI context — and applying that to every pre-existing idle
    /// source in order to serve a new one is a wider blast radius than the new
    /// feature needs. Ordinary sources keep the exact dispatch they had.
    arg1: u64 = 0,
    arg2: u64 = 0,
    extra_arguments: bool = false,
    active: bool = false,
    tag: []const u8 = "",
    scheduled_step: u64 = 0,
    scheduling_thread: u64 = 0,
    scheduling_rip: u64 = 0,
};

test "only signal handlers request the extra argument registers" {
    // A `GSourceFunc` reads one argument. Leaving rsi/rdx alone for it keeps
    // the dispatch byte-identical to the restored cooperative UI context, so
    // adding signal-handler support cannot perturb the idle sources that pump
    // the guest's main loop.
    const idle = IdleCallback{ .function = 0x1000, .data = 0x20 };
    try std.testing.expect(!idle.extra_arguments);
    try std.testing.expectEqual(@as(u64, 0), idle.arg1);
    try std.testing.expectEqual(@as(u64, 0), idle.arg2);

    const handler = IdleCallback{ .function = 0x1000, .data = 0x20, .arg1 = 0, .arg2 = 0x30, .extra_arguments = true };
    try std.testing.expect(handler.extra_arguments);
}

pub const IdleDispatchBlock = enum {
    ready,
    no_ui_context,
    no_active_guest_thread,
    callback_already_running,
    suspended_queue_full,
};

pub const IdleQueueSnapshot = struct {
    pending: usize = 0,
    oldest_source: u64 = 0,
    oldest_callback: u64 = 0,
    oldest_scheduled_step: u64 = 0,
    oldest_scheduling_thread: u64 = 0,
    oldest_scheduling_rip: u64 = 0,
    oldest_tag: []const u8 = "",
};

pub const RunnableSuspendedSnapshot = struct {
    runnable: usize = 0,
    blocked: usize = 0,
    oldest_handle: u64 = 0,
    oldest_rip: u64 = 0,
    oldest_step: u64 = 0,
    oldest_reason: []const u8 = "",
};

pub fn idleQueueSnapshotFor(callbacks: []const IdleCallback) IdleQueueSnapshot {
    var snapshot = IdleQueueSnapshot{};
    for (callbacks) |entry| {
        if (!entry.active) continue;
        snapshot.pending += 1;
        if (snapshot.oldest_source != 0 and entry.source_id >= snapshot.oldest_source) continue;
        snapshot.oldest_source = entry.source_id;
        snapshot.oldest_callback = entry.function;
        snapshot.oldest_scheduled_step = entry.scheduled_step;
        snapshot.oldest_scheduling_thread = entry.scheduling_thread;
        snapshot.oldest_scheduling_rip = entry.scheduling_rip;
        snapshot.oldest_tag = entry.tag;
    }
    return snapshot;
}

pub const MAX_SUSPENDED_GUEST_THREADS = 64;

pub const SuspendedGuestThread = struct {
    handle: u64 = 0,
    suspended_step: u64 = 0,
    reason: []const u8 = "",
    regs: Regs = .{},
    xmm: [16][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 16,
    ymm_hi: [16][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 16,
    x87: X87State = .{},
};

pub const GuestSignalAction = struct {
    handler: u64 = 0,
    mask: u32 = 0,
    flags: u32 = 0,
};

pub const GuestAssertionClass = guest_assertion_recovery.Class;
pub const classifyGuestAssertion = guest_assertion_recovery.classify;
pub const timerQueueStateName = guest_assertion_recovery.timerQueueStateName;

pub const GuestSignalFrame = struct {
    signal: u8 = 0,
    instruction_len: u8 = 0,
    fault_rip: u64 = 0,
    fault_address: u64 = 0,
    fault_access: ?GuestAccess = null,
    fault_width: u8 = 0,
    fault_instruction: []const u8 = "",
    siginfo: u64 = 0,
    mcontext: u64 = 0,
    ucontext: u64 = 0,
    assertion_class: GuestAssertionClass = .none,
};

pub const ProfileAccountStage = enum {
    idle,
    loading,
    host_opened,
    reading,
    open_failed,
    short_read,
    decrypt_failed,
    decrypted,
    inserting,
    completed,
};

pub const ProfileAccountFlow = struct {
    active: bool = false,
    manager: u64 = 0,
    xuid: u64 = 0,
    return_address: u64 = 0,
    started_step: u64 = 0,
    stage: ProfileAccountStage = .idle,
    account_guest_fd: u64 = std.math.maxInt(u64),
    requested_bytes: u64 = 0,
    bytes_read: u64 = 0,
    attempts: u64 = 0,
    successes: u64 = 0,
    failures: u64 = 0,
};

// The mapping this replaces was copied into three modules. Each copy was the
// input to a causal walk that decides where guest execution resumes, so a
// single transposed ordinal would have produced confident, wrong attribution
// in whichever consumers happened to hold the bad copy. One owner, one test.
test "a trace snapshot maps every register id onto its own field" {
    const entry = TraceEntry{
        .rax = 0x00,
        .rcx = 0x11,
        .rdx = 0x22,
        .rbx = 0x33,
        .rsp = 0x44,
        .rbp = 0x55,
        .rsi = 0x66,
        .rdi = 0x77,
        .r8 = 0x88,
        .r9 = 0x99,
        .r10 = 0xAA,
        .r11 = 0xBB,
        .r12 = 0xCC,
        .r13 = 0xDD,
        .r14 = 0xEE,
        .r15 = 0xFF,
    };
    const expected = [_]u64{ 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF };
    for (expected, 0..) |value, ordinal| {
        const register: RegId = @enumFromInt(@as(u4, @intCast(ordinal)));
        try std.testing.expectEqual(value, entry.registerValue(register));
    }
    // The faulting-base register of the dispatch layout these walks exist for.
    try std.testing.expectEqual(@as(u64, 0x33), entry.registerValue(.bl_bx_ebx_rbx));
}
