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
};

pub const PROGRESS_REPORT_INTERVAL: u64 = 500_000;
pub const HEARTBEAT_INTERVAL: u64 = 25_000_000;

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
    local_definition,
    libcxx_stream,
    foreign_object,
    import_contract,
    libcxx_filesystem,
    pthread,
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
    active: bool = false,
    tag: []const u8 = "",
    scheduled_step: u64 = 0,
    scheduling_thread: u64 = 0,
    scheduling_rip: u64 = 0,
};

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
