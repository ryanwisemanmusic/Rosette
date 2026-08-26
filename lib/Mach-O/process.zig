const std = @import("std");
const builtin = @import("builtin");
const macho_core = @import("macho_core");
const macho = macho_core.macho;
const fat = @import("fat.zig");
const x64_decoder = @import("x64_decoder");
const x64_interpreter = @import("x64_interpreter");
const macho_runtime = @import("macho_runtime");
const exit_diagnostics = @import("exit_diagnostics");
const macho_metadata = macho_core.metadata;
const compat_runtime = @import("macho_compat_runtime");
const import_resolution = @import("dyld").import_engine;
const initialization_resolution = @import("init").initialization_engine;
const initializer_dependency = @import("init").initializer_dependency;
const abi_data_materializer = @import("dyld").abi_data_materializer;
const memory_transaction = @import("memory").memory_transaction;
const dynamic_library_forwarder = @import("dyld").dynamic_library_forwarder;
const guest_memory_geometry = @import("dyld").guest_memory_geometry;
const lazy_import_stub = @import("dyld").lazy_import_stub;
const smart_stub_generator = @import("dyld").smart_stub_generator;
const cxx_exception_diagnostics = @import("cxx_abi").cxx_exception_diagnostics;
const spirv_cross_diagnostics = @import("diagnostics").spirv_cross_diagnostics;
const log_repetition = @import("diagnostics").log_repetition;
const guest_module_map = @import("diagnostics").guest_module_map;
const fs_io_forwarder = @import("io").fs_io_forwarder;
const memory_management_forwarder = @import("memory").memory_management_forwarder;
const sparse_virtual_memory = @import("memory").sparse_virtual_memory;
const memory_provenance = @import("dyld").memory_provenance;
const memory_write_provenance = @import("memory").memory_write_provenance;
const pointer_firewall = @import("dyld").pointer_firewall;
const semantic_fault_classifier = @import("diagnostics").semantic_fault_classifier;
const opaque_lifetime_recovery = @import("diagnostics").opaque_lifetime_recovery;
const libcpp_shared_control_block = @import("cxx_abi").libcpp_shared_control_block;
const launch_argument_accelerator = @import("diagnostics").launch_argument_accelerator;
const startup_observer = @import("diagnostics").startup_observer;
const itanium_unwinder = @import("cxx_abi").itanium_unwinder;
const itanium_dynamic_cast = @import("cxx_abi").itanium_dynamic_cast;
const libcpp_filesystem = @import("io").libcpp_filesystem;
const libcpp_stream_bridge = @import("io").libcpp_stream_bridge;
const vtt_resolution = @import("dyld").vtt_resolver;
const foreign_object_runtime = @import("guest_abi").foreign_object_runtime;
const native_window_runtime = @import("guest_abi").native_window_runtime;
const sdl_runtime = @import("guest_abi").sdl_runtime;
const logging_runtime = @import("diagnostics").logging_runtime;
const rosette_pkg_log = @import("diagnostics").rosette_pkg_log;
const x64_backend_diagnostics = @import("diagnostics").x64_backend_diagnostics;
const xenia_pipeline = @import("diagnostics").xenia_pipeline;
const xenia_gpu_handoff = @import("diagnostics").xenia_gpu_handoff;
const xenia_gpu_causal_trace = @import("diagnostics").xenia_gpu_causal_trace;
const graphics_health_contract = @import("diagnostics").graphics_health_contract;
const application_controller = @import("diagnostics").application_controller;
const application_framework = @import("application_framework");
const xenia_memory_views = @import("diagnostics").xenia_memory_views;
const guest_wait_liveness = @import("diagnostics").guest_wait_liveness;
const deadlock_predictor = @import("diagnostics").deadlock_predictor;
const deferred_work = @import("diagnostics").deferred_work;
const guest_exception_ledger = @import("diagnostics").guest_exception_ledger;
const sync_object_identity = @import("diagnostics").sync_object_identity;
const wait_audit = @import("diagnostics").wait_audit;
const host_contract_coverage = @import("diagnostics").host_contract_coverage;
const stall_release = @import("diagnostics").stall_release;
const bringup_failure = @import("diagnostics").bringup_failure;
const run_horizon = @import("diagnostics").run_horizon;
const event_identity = @import("diagnostics").event_identity;
const execution_tracepoints = @import("diagnostics").execution_tracepoints;
const anomaly_ledger = @import("diagnostics").anomaly_ledger;
const notifier_liveness = @import("scheduler").notifier_liveness;
const guest_critical_section = @import("diagnostics").guest_critical_section;
const near_null_predictor = @import("process_core").near_null_predictor;
const livelock_predictor = @import("process_core").livelock_predictor;
const vtable_clobber_predictor = @import("process_core").vtable_clobber_predictor;
const import_binding_predictor = @import("process_core").import_binding_predictor;
const swap_health = @import("process_core").swap_health;
const guest_assertion_recovery = @import("guest_abi").guest_assertion_recovery;
const atomic_compare_exchange = @import("memory").atomic_compare_exchange;
const memory_mod = @import("memory");
const bytesForSize = memory_mod.bytesForSize;
const writeExtendedFloat80 = memory_mod.writeExtendedFloat80;
const readExtendedFloat80 = memory_mod.readExtendedFloat80;
const memReadMemVal = memory_mod.readMemVal;
const MemReadCallbacks = memory_mod.ReadMemValCallbacks;
const diagnostic_throttle = @import("diagnostics").diagnostic_throttle;
const pthread_runtime = @import("pthread").pthread_runtime;
const runtime_output = @import("diagnostics").runtime_output;
const tlv_runtime = @import("guest_abi").tlv_runtime;
const diagnostic_text_accelerator = @import("diagnostics").diagnostic_text_accelerator;
const preflight_lib = @import("preflight");
const ready_compiler = @import("ready_compiler");
const symbol_assembly_context = macho_core.symbol_assembly_context;
const export_table_manager = @import("dyld").export_table_manager;
const export_table_lifecycle = @import("dyld").export_table_lifecycle;
const dynamic_export_registry = @import("dyld").dynamic_export_registry;
const thread_wait_profiler = @import("pthread").thread_wait_profiler;
const contract = @import("contract");
const primitive = @import("primitive");
const import_handler = @import("import_handler");
const import_dispatch = import_handler.dispatch;
const dyld = @import("dyld");
const vt = @import("vtable");
const guard_rollback_lib = @import("guard_rollback");
const scheduler = @import("scheduler");
const cleo_routing = @import("cleo_routing");
const jit = @import("jit");
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;
const primitiveCapturePrint = macho_log.primitiveCapturePrint;
const syscalls = @import("process_core").syscalls;
const native_window = @import("process_core").native_window;
const scheduling = @import("process_core").scheduling;
const guest_log = @import("process_core").guest_log;
const host_termination = @import("process_core").host_termination;
const native_crash = @import("process_core").native_crash;
const guest_fs = @import("guest_fs.zig");
const proc_diag = @import("process_core").diagnostics;
const thunk_handler = @import("macho_core").thunk_handler;
const execution_helpers = @import("macho_core").execution_helpers;
const execute_impl = @import("process_core").execute;
const memory_access = @import("process_core").memory_access;
const generated_endian_contract = @import("process_core").generated_endian_contract;
const packed_ops = @import("macho_core").packed_ops;
const signal_handling = @import("process_core").signal_handling;
const initializers = @import("process_core").initializers;
const compat_handlers = @import("process_core").compat_handlers;
const bounded_dispatch_fst = @import("process_core").bounded_dispatch_fst;
const recovery_ledger = @import("ownership").ledger;
const guest_address_space = @import("guest_address_space");
const ownership_lib = @import("ownership");
const dispatch_recovery = @import("dispatch_recovery");
const gpu = @import("gpu");
const device_tree = @import("device_tree");
const guest_structure = @import("guest_structure");
const execution_history = @import("execution_history");
const ExecutionHistory = execution_history.History(TraceEntry);
const crash_diag = @import("process_core").crash_diag;

test {
    std.testing.refAllDecls(symbol_assembly_context);
    std.testing.refAllDecls(initializer_dependency);
}

const log = std.log.scoped(.macho);

const Regs = x64_decoder.Regs;
const Size = x64_decoder.OperandSize;
const RegId = x64_decoder.RegId;
const Cond = x64_decoder.Condition;
const Op = x64_decoder.Op;
const DecodedInsn = x64_decoder.DecodedInsn;

/// A decode-cache hit that has already passed the plain-RIP gate chain. The
/// old step path returned only `host_image` from its first probe, then probed
/// the same set again in `decodeWithLiveOperands`. Carrying the decoded form
/// through the first probe makes that one cache lookup do both jobs.
const FastPlainDecode = struct {
    decoded: DecodedInsn,
    host_image: bool,
};

/// Relative control-flow operands are signed displacements, not memory
/// addresses. `rip_relative` is also used for RIP-relative ModRM operands, so
/// the opcode must disambiguate the two before address materialization.
fn hasRelativeControlDisplacement(op: Op) bool {
    return switch (op) {
        .call_rel32, .jmp_rel8, .jcc_rel8, .jcc_rel32 => true,
        else => false,
    };
}

test "relative control displacements are not materialized as memory addresses" {
    try std.testing.expect(hasRelativeControlDisplacement(.call_rel32));
    try std.testing.expect(hasRelativeControlDisplacement(.jmp_rel8));
    try std.testing.expect(hasRelativeControlDisplacement(.jcc_rel32));
    try std.testing.expect(!hasRelativeControlDisplacement(.jmp_mem64));
    try std.testing.expect(!hasRelativeControlDisplacement(.mov_reg64_mem64));
}

test "special-RIP table binary search finds only registered addresses" {
    // Sorted, deduplicated view matching buildSpecialRipTable output.
    const table = [_]u64{ 0x1000, 0x2000, 0x4000, 0x8000 };
    try std.testing.expect(specialRipTableContains(&table, 0x1000));
    try std.testing.expect(specialRipTableContains(&table, 0x8000));
    try std.testing.expect(!specialRipTableContains(&table, 0x0000));
    try std.testing.expect(!specialRipTableContains(&table, 0x0fff));
    try std.testing.expect(!specialRipTableContains(&table, 0x3000));
    try std.testing.expect(!specialRipTableContains(&table, 0x9000));
    try std.testing.expect(!specialRipTableContains(&[_]u64{}, 0x1000));
}
/// R2 (N3): binary search over the address-sorted special-RIP table. The
/// table is a load-time-resolved index of every fixed target the
/// per-instruction handler chain probes, so a miss here (combined with the
/// O(1) range probes in specialRipPossible) proves the chain is inert.
fn specialRipTableContains(table: []const u64, rip: u64) bool {
    var low: usize = 0;
    var high: usize = table.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (table[middle] < rip) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return low < table.len and table[low] == rip;
}

const VexArithmetic = macho_core.decoder.VexArithmetic;
const VexBitwise = macho_core.decoder.VexBitwise;
const BitScanKind = x64_decoder.BitScanKind;
const bitScan = x64_decoder.bitScan;
const populationCount = x64_decoder.populationCount;
const crc32cAccumulator = x64_decoder.crc32cAccumulator;

const RFL_CF = x64_decoder.RFL_CF;
const RFL_PF: u32 = 1 << 2;
const RFL_AF: u32 = 1 << 4;
const RFL_ZF = x64_decoder.RFL_ZF;
const RFL_SF = x64_decoder.RFL_SF;
const RFL_OF = x64_decoder.RFL_OF;
const RFL_DF: u32 = 1 << 10;

const constants = @import("macho_core").constants;
const STACK_SIZE = constants.STACK_SIZE;
const MEM_SIZE = constants.MEM_SIZE;
const envMemSizeMb = constants.envMemSizeMb;
const MEM_BASE = constants.MEM_BASE;
const PAGE_SIZE = constants.PAGE_SIZE;
const TRACE_BUFFER_LEN = constants.TRACE_BUFFER_LEN;
const TRACE_THREAD_SLOTS = constants.TRACE_THREAD_SLOTS;
const TRACE_PER_THREAD_LEN = constants.TRACE_PER_THREAD_LEN;
const IMPORT_TRACE_BUFFER_LEN = constants.IMPORT_TRACE_BUFFER_LEN;
const MEMORY_TRACE_BUFFER_LEN = constants.MEMORY_TRACE_BUFFER_LEN;
const ENDIAN_EVIDENCE_BUFFER_LEN = constants.ENDIAN_EVIDENCE_BUFFER_LEN;
const UNSUPPORTED_RUNTIME_EXIT_CODE = constants.UNSUPPORTED_RUNTIME_EXIT_CODE;
const GUEST_FILE_BASE = constants.GUEST_FILE_BASE;
const GUEST_FILE_MAX = constants.GUEST_FILE_MAX;
const BOUND_IMPORT_THUNK_BASE = constants.BOUND_IMPORT_THUNK_BASE;
// Thunk stride is now dynamically probed from Mach-O __stubs section via
// self.metadata.importThunkStride().  The legacy constant (16) is a fallback
// only; no live code references it directly from this scope.
const INITIALIZER_RETURN_SENTINEL = constants.INITIALIZER_RETURN_SENTINEL;
const GUEST_THREAD_RETURN_SENTINEL = constants.GUEST_THREAD_RETURN_SENTINEL;
const GUEST_SIGNAL_RETURN_SENTINEL = constants.GUEST_SIGNAL_RETURN_SENTINEL;
const GUEST_ATEXIT_RETURN_SENTINEL = constants.GUEST_ATEXIT_RETURN_SENTINEL;
const DEFAULT_GUEST_THREAD_STACK_SIZE = constants.DEFAULT_GUEST_THREAD_STACK_SIZE;
const COOPERATIVE_THREAD_QUANTUM_STEPS = constants.COOPERATIVE_THREAD_QUANTUM_STEPS;
const IDLE_STARVATION_STEPS = constants.IDLE_STARVATION_STEPS;
const INITIALIZER_STEP_LIMIT = constants.INITIALIZER_STEP_LIMIT;
const GUEST_LOG_BUFFER_SIZE = constants.GUEST_LOG_BUFFER_SIZE;
const DECODE_CACHE_ENTRY_COUNT = constants.DECODE_CACHE_ENTRY_COUNT;
const IMPORT_ROUTE_CACHE_SIZE = constants.IMPORT_ROUTE_CACHE_SIZE;
const PAGE_READ = constants.PAGE_READ;
const PAGE_WRITE = constants.PAGE_WRITE;
const PAGE_EXECUTE = constants.PAGE_EXECUTE;
const GUEST_SIGILL = constants.GUEST_SIGILL;
const GUEST_SIGSEGV = constants.GUEST_SIGSEGV;
const SA_RESETHAND = constants.SA_RESETHAND;
const SA_NODEFER = constants.SA_NODEFER;
const SA_SIGINFO = constants.SA_SIGINFO;
const GUEST_SIGNAL_ACTION_COUNT = constants.GUEST_SIGNAL_ACTION_COUNT;
const GUEST_SIGNAL_FRAME_DEPTH = constants.GUEST_SIGNAL_FRAME_DEPTH;
const DARWIN_SIGACTION_SIZE = constants.DARWIN_SIGACTION_SIZE;
const DARWIN_SIGINFO_SIZE = constants.DARWIN_SIGINFO_SIZE;
const DARWIN_UCONTEXT_SIZE = constants.DARWIN_UCONTEXT_SIZE;
const DARWIN_MCONTEXT_SIZE = constants.DARWIN_MCONTEXT_SIZE;
const TOML_CODEPOINT_CAPACITY = constants.TOML_CODEPOINT_CAPACITY;
const TOML_CODEPOINT_STRIDE = constants.TOML_CODEPOINT_STRIDE;
const TOML_READER_ISTREAM_OFFSET = constants.TOML_READER_ISTREAM_OFFSET;
const TOML_CODEPOINTS_OFFSET = constants.TOML_CODEPOINTS_OFFSET;
const TOML_CODEPOINT_CURRENT_OFFSET = constants.TOML_CODEPOINT_CURRENT_OFFSET;
const TOML_CODEPOINT_COUNT_OFFSET = constants.TOML_CODEPOINT_COUNT_OFFSET;
const TOML_UTF8_READER_MIN_SIZE = constants.TOML_UTF8_READER_MIN_SIZE;
const PROGRESS_REPORT_INTERVAL = constants.PROGRESS_REPORT_INTERVAL;
const HEARTBEAT_INTERVAL = constants.HEARTBEAT_INTERVAL;
const CONCISE_PROGRESS_INTERVAL = constants.CONCISE_PROGRESS_INTERVAL;

const types = @import("macho_core").types;
const TomlAsciiBlock = types.TomlAsciiBlock;
const TomlCodepointRepair = types.TomlCodepointRepair;
const GuestAccess = types.GuestAccess;
const GuestAccessDescription = types.GuestAccessDescription;
const MachSegment = types.MachSegment;
const TraceEntry = types.TraceEntry;
const X87Tag = types.X87Tag;
const X87State = types.X87State;
const ImportTraceEntry = types.ImportTraceEntry;
const ControlTransferContext = types.ControlTransferContext;
const DecodeCacheEntry = types.DecodeCacheEntry;
const ImportHandlerResult = types.ImportHandlerResult;
const ImportRoute = types.ImportRoute;
const ImportRouteCacheEntry = types.ImportRouteCacheEntry;
const BulkConstructionRange = types.BulkConstructionRange;
const InitializerRunOutcome = types.InitializerRunOutcome;
const GuestFileKind = types.GuestFileKind;
const GuestFile = types.GuestFile;
const BoundImportThunk = types.BoundImportThunk;
const InternalCompatibilityTargets = types.InternalCompatibilityTargets;
const InitializerCheckpoint = types.InitializerCheckpoint;
const CooperativeUiContext = types.CooperativeUiContext;
const MainLoopType = types.MainLoopType;
const IdleCallback = types.IdleCallback;
const IdleDispatchBlock = types.IdleDispatchBlock;
const IdleQueueSnapshot = types.IdleQueueSnapshot;
const RunnableSuspendedSnapshot = types.RunnableSuspendedSnapshot;
const SuspendedGuestThread = types.SuspendedGuestThread;
const GuestSignalAction = types.GuestSignalAction;
const GuestSignalFrame = types.GuestSignalFrame;
const ProfileAccountStage = types.ProfileAccountStage;
const ProfileAccountFlow = types.ProfileAccountFlow;
const MAX_IDLE_CALLBACKS = types.MAX_IDLE_CALLBACKS;
const IDLE_CALLBACK_HANDLE_BASE = types.IDLE_CALLBACK_HANDLE_BASE;
const MAX_SUSPENDED_GUEST_THREADS = types.MAX_SUSPENDED_GUEST_THREADS;
const classifyGuestAssertion = types.classifyGuestAssertion;
const timerQueueStateName = types.timerQueueStateName;
const idleQueueSnapshotFor = types.idleQueueSnapshotFor;
const isGtkIdleAddImport = types.isGtkIdleAddImport;
const isGtkEventsPendingImport = types.isGtkEventsPendingImport;
const isGtkMainIterationImport = types.isGtkMainIterationImport;

const GtkBootstrapEntry = struct {
    rip: u64 = 0,
    thread: u64 = 0,
    op: u32 = 0,
    len: u8 = 0,
};

const StepTraceEntry = struct {
    step: u64 = 0,
    rip: u64 = 0,
};

const MemInitEntry = struct {
    step: u64 = 0,
    rip: u64 = 0,
    // Shorter summary stored inline so we can log it on fault
    heap: u64 = 0,
    sparse_mappings: usize = 0,
    sparse_activations: usize = 0,
    deferred_count: u64 = 0,
    suspended_count: usize = 0,
};

const GtkHeartbeatEntry = struct {
    step: u64 = 0,
    rip: u64 = 0,
    thread: u64 = 0,
    deferred: u64 = 0,
    suspended_total: usize = 0,
    suspended_runnable: usize = 0,
    suspended_blocked: usize = 0,
    switches: u64 = 0,
    wait_yields: u64 = 0,
    quantum_yields: u64 = 0,
    rotation_yields: u64 = 0,
    idle_pending: u64 = 0,
    active_idle_source: u64 = 0,
    active_idle_callback: u64 = 0,
    dispatch_block: IdleDispatchBlock = .ready,
};

const UiHandoffEntry = struct {
    step: u64 = 0,
    rip: u64 = 0,
    generation: u64 = 0,
    phase: scheduler.UiHandoffPhase = .idle,
    source_id: u64 = 0,
    callback_handle: u64 = 0,
    callback_rip: u64 = 0,
    worker_handle: u64 = 0,
    worker_rip: u64 = 0,
    no_progress: u64 = 0,
    suspensions: u64 = 0,
    resumes: u64 = 0,
    worker_slices: u64 = 0,
};

/// Records the provenance of a 64-bit write to an allocation base address.
/// This gives us a write-order trace for every allocation-boundary write,
/// enabling crash-time diagnosis of heap corruption (e.g., tree node parent
/// pointers overwritten with function prologue bytes).
const AllocationWriteRecord = struct {
    last_value: u64 = 0,
    writer_rip: u64 = 0,
    writer_step: u64 = 0,
    writer_thread: u64 = 0,
    restore_count: u64 = 0,
};

pub const MachOState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    mem: []u8,
    mem_base: u64,
    mem_size: u64,
    heap_next: u64,
    lock_fence: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
    regs: Regs = .{},
    xmm: [16][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 16,
    // AVX-512 opmask registers (k0-k7). k0 is always all-1s when read as
    // a mask operand; k1-k7 hold actual mask values for predicated operations.
    k: [8]u64 = [_]u64{0xFFFF_FFFF_FFFF_FFFF} ** 8,
    ymm_hi: [16][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 16,
    cpu_profile: x64_decoder.capabilities.Profile = .xenia,
    compat: compat_runtime.Runtime = .{},
    terminated: bool = false,
    exit_code: u64 = 0,
    faulted: bool = false,
    termination_reason: u8 = @intFromEnum(exit_diagnostics.TerminationReason.unknown),
    host_termination_signal: u8 = 0,
    data: []const u8,
    segments: []const MachSegment,
    metadata: macho_metadata.Metadata,
    entry_point_vaddr: u64 = 0,
    stack_size: u64 = 0,
    guest_fds: [16]i32 = .{-1} ** 16,
    next_guest_fd: u64 = 3,
    guest_time: scheduler.GuestTimeService = .{},
    pending_direct_sleep: ?scheduler.GuestSleepDecision = null,
    concise_output: bool = false,
    diagnostic_output_fd: i32 = 1,
    summary_output_fd: i32 = -1,
    ios_xalloc_next: u64 = 4,
    verbose_trace: bool = false,
    contract_verification: bool = false,
    max_steps: u64 = 0,
    guest_assertion_count: u64 = 0,
    /// Assertion provenance belongs to the active guest context. It is
    /// snapshotted with registers when cooperative scheduling parks a thread,
    /// so a later UD2 cannot inherit another thread's assertion.
    last_guest_assertion: types.GuestAssertionContext = .{},
    atomic_cmpxchg: atomic_compare_exchange.Stats = .{},
    timer_queue_watch: struct {
        active: bool = false,
        wait_item_addr: u64 = 0,
        state_addr: u64 = 0,
        thread: u64 = 0,
        logged_writes: u64 = 0,
    } = .{},
    sha1_tracer: Sha1Tracer = .{},
    export_table_mgr: export_table_manager.Manager = .{},
    export_table_lc: export_table_lifecycle.Lifecycle = .{},
    export_registry: dynamic_export_registry.Registry = .{},
    wait_profiler: thread_wait_profiler.WaitProfileSystem = .{},
    diagnostic_throttler: diagnostic_throttle.Tracker = .{},
    libcpp_shared_control_blocks: libcpp_shared_control_block.Stats = .{},
    toml_ascii_fast_paths: u64 = 0,
    libcxx_string_substr_fast_paths: u64 = 0,
    profile_host_preflight_checks: u64 = 0,
    profile_account_flow: ProfileAccountFlow = .{},
    toml_ascii_entry: ?u64 = null,
    toml_read_next_entry: ?u64 = null,
    toml_ascii_block: ?TomlAsciiBlock = null,
    toml_fault_diagnostics_dumped: bool = false,
    patch_db_empty_array_recoveries: u64 = 0,
    // R2 (perf audit, N3): load-time-resolved, address-sorted table of every
    // fixed special-RIP target probed by the per-instruction handler chain
    // (internal compatibility targets, cvar launch-option vector, toml fast
    // path entries). step() consults it with one binary search inside
    // specialRipPossible() instead of 9 handler calls + ~65 compares per
    // instruction; on a hit the full chain still runs with identical
    // short-circuit semantics.
    special_rip_table: []u64 = &.{},
    // R2 (N3 phase-arm): the toml/patch-db probes only fire while config
    // parsing may still run. Cleared once runInitializers succeeds so the
    // special-RIP gate drops the non-address patch-db state probe from the
    // per-instruction cost stack.
    config_parsing_active: bool = true,
    // R2 (N7): gates the per-initializer and vtable-lifecycle detail log
    // lines that flooded the run log (722 `running initializer` lines + per
    // object vtable transitions during static init). Progress lines and
    // failure/deferral diagnostics stay unconditionally. Enable with
    // ROSETTE_MACHO_INITIALIZER_DETAIL=1.
    initializer_detail_logging: bool = false,
    // R2 (N3): if building the special-RIP table fails (startup OOM), fall
    // back to probing every instruction (the pre-R2 behavior) rather than
    // silently skipping the handler chain.
    special_rip_table_failed: bool = false,
    stalled_instruction_reports: u64 = 0,
    initializer_abort_requested: bool = false,
    initializer_abort_reason: initialization_resolution.DeferralReason = .none,
    cxxopts_split_accelerations: u64 = 0,
    imgui_text_ex_noops: u64 = 0,
    positional_options_captured: bool = false,
    executed_steps: u64 = 0,
    internal_targets: InternalCompatibilityTargets = .{},
    launch_options: launch_argument_accelerator.Filter = .{},
    startup: startup_observer.Observer = .{},
    guest_errno_address: u64 = 0,
    classic_locale_object: u64 = 0,
    cooperative_ui_context: ?CooperativeUiContext = null,
    main_loop_type: MainLoopType = .gtk,
    /// When true, enables Xenia-specific compatibility handlers
    /// (XModule vtable synthesis, binary identity checks).
    /// Set to false for non-Xenia binaries.
    has_xenia_compat: bool = true,
    active_guest_thread: u64 = 0,
    cooperative_thread_switches: u64 = 0,
    cooperative_thread_returns: u64 = 0,
    cooperative_wait_yields: u64 = 0,
    cooperative_quantum_yields: u64 = 0,
    cooperative_rotation_yields: u64 = 0,
    cooperative_sleep_yields: u64 = 0,
    cooperative_preserved_register_resumes: u64 = 0,
    cooperative_wait_result_resumes: u64 = 0,
    cooperative_self_resumes: u64 = 0,
    cooperative_quiescence_recoveries: u64 = 0,
    jit_commit_count: u64 = 0,
    jit_export_count: u64 = 0,
    opaque_destructor_quarantines: u64 = 0,
    /// NUL terminator stores skipped inside a zeroed `xe::StringBuffer` (see
    /// `lib/diagnostics/null_write_recovery.zig`): the empty-buffer write is a
    /// no-op and the buffer self-heals on next use, so the repair continues
    /// the run instead of terminating on a debug-path cleanup.
    string_buffer_null_write_repairs: u64 = 0,
    cooperative_starvation_warnings: u64 = 0,
    last_cooperative_starvation_step: u64 = 0,
    // A context's suspended_step predates the wait notification that may make
    // it runnable, so it is only an upper bound on runnable age. Require the
    // same eligible context at consecutive heartbeats before calling the state
    // starvation; these fields track that directly observed interval.
    runnable_candidate_handle: u64 = 0,
    runnable_candidate_suspended_step: u64 = 0,
    runnable_candidate_first_observed_step: u64 = 0,
    runnable_candidate_observations: u64 = 0,
    ui_callback_retained_quanta: u64 = 0,
    cooperative_quantum_steps: u64 = 0,
    // P0-1: throttled cooperative-scheduler queue scans (see
    // COOPERATIVE_SCHEDULER_SCAN_INTERVAL). The full idle-callback table and
    // suspended-thread scans used to run on every interpreted instruction;
    // they now run once per interval with cached counts used in between.
    cooperative_scheduler_scan_steps: u64 = 0,
    cached_pending_idle: usize = 0,
    cached_suspended_runnable: usize = 0,
    // P0-1 (event-driven): the suspended-runnable cache is additionally keyed
    // on the pthread runtime state_version so the O(suspended x threads) scan
    // only reruns when runnability could actually have changed, plus the
    // earliest guest-time deadline so virtual time reaching a sleep expiry
    // (which changes runnability with no explicit transition) also refreshes.
    cached_suspended_version: u64 = std.math.maxInt(u64),
    cached_suspended_next_deadline: ?u64 = null,
    scheduler_execution_deadline_crossings: u64 = 0,
    coop_bootstrap_active: bool = false,
    coop_bootstrap_index: u8 = 0,
    coop_bootstrap_entries: [24]GtkBootstrapEntry = [_]GtkBootstrapEntry{.{}} ** 24,
    step_trace_entries: [5]StepTraceEntry = [_]StepTraceEntry{.{}} ** 5,
    step_trace_index: u4 = 0,
    step_trace_filled: bool = false,
    mem_init_started: bool = false,
    mem_init_entries: [8]MemInitEntry = [_]MemInitEntry{.{}} ** 8,
    mem_init_index: u8 = 0,
    mem_init_filled: bool = false,
    coop_heartbeat_index: u4 = 0,
    coop_heartbeat_filled: bool = false,
    coop_heartbeat_entries: [5]GtkHeartbeatEntry = [_]GtkHeartbeatEntry{.{}} ** 5,
    ui_handoff_index: u4 = 0,
    ui_handoff_filled: bool = false,
    ui_handoff_entries: [5]UiHandoffEntry = [_]UiHandoffEntry{.{}} ** 5,
    idle_callbacks: [MAX_IDLE_CALLBACKS]IdleCallback = [_]IdleCallback{.{}} ** MAX_IDLE_CALLBACKS,
    gtk_idle_next_source: u64 = 1,
    idle_scheduled: u64 = 0,
    idle_started: u64 = 0,
    idle_completed: u64 = 0,
    idle_removed: u64 = 0,
    idle_wakeups: u64 = 0,
    /// Boundaries that elected idle work, switched context, and started no
    /// callback. A non-zero count means the chooser and the dispatch rule
    /// disagreed about whether the queue could run.
    idle_wakes_without_dispatch: u64 = 0,
    /// Idle dispatches refused because another synthetic callback still owned
    /// the shared UI callback stack.
    idle_stack_owner_deferrals: u64 = 0,
    /// `rsp` at which the current synthetic callback was entered, and the
    /// handle that entered it. Kept so a bad return inside a callback can be
    /// attributed to the shared callback stack instead of reported as an
    /// unexplained invalid target.
    synthetic_stack_entry_rsp: u64 = 0,
    synthetic_stack_entry_handle: u64 = 0,
    synthetic_stack_dispatches: u64 = 0,
    /// Identity of the context that faulted, fixed at the first fault reporter
    /// and read by every later block of the crash report. Without it each block
    /// re-read `active_guest_thread` at its own moment and the report could name
    /// two different threads for one fault.
    fault_context_pinned: bool = false,
    fault_context_thread: u64 = 0,
    fault_context_step: u64 = 0,
    /// Forward-looking near-null receiver signatures collected at import
    /// dispatch, dumped when a terminal casualty is confirmed. See
    /// `near_null_predictor.zig` for the cost model (one compare per import).
    near_null_predictor: near_null_predictor.Predictor = .{},
    /// Guest wait-cycle signatures observed through the mirrored guest log
    /// (KeWaitForSingleObject/KeSetEvent/KeReleaseSemaphore). A signature
    /// whose count grows while the ring write pointer is stalled is a
    /// livelock prediction — the guest is parked on an object nobody will
    /// ever signal. See `livelock_predictor.zig`; reached only from the
    /// guest-log bridge, never from the instruction stream.
    livelock_predictor: livelock_predictor.Predictor = .{},
    /// Object of the most recent `KeWaitForSingleObject` detail line, so the
    /// predictor can pair the following `result=` line with an object even
    /// against a pre-instrumentation binary that omitted it.
    livelock_pending_wait_object: u64 = 0,
    /// Judges every write-time vptr restore before Rosette performs it. The
    /// restore is a store into guest memory, and a tracked slot that turns out
    /// to be live stack scratch makes that store the defect rather than the
    /// repair. See `vtable_clobber_predictor.zig`; reached only from the
    /// `trusted_value_cleared` branch, so it costs nothing per store.
    vtable_clobber_predictor: vtable_clobber_predictor.Predictor = .{},
    /// Judges the guest's own XEX import binding audit. The audit's finding
    /// rests entirely on a thunk address it supplies, so an address no thunk
    /// can have makes the finding evidence about the auditor rather than about
    /// the import. See `import_binding_predictor.zig`.
    import_binding_predictor: import_binding_predictor.Predictor = .{},
    /// Thread carrying a C++ exception that Itanium phase one could not match
    /// to a handler, and the thrown type. Read when the thread returns, so an
    /// exception-terminated thread is distinguishable from a clean exit.
    unhandled_cxx_thread: u64 = 0,
    unhandled_cxx_type_info: u64 = 0,
    fault_context_history_epoch: u64 = 0,
    idle_dispatch_failures: u64 = 0,
    idle_starvation_warnings: u64 = 0,
    active_idle_source: u64 = 0,
    active_idle_callback: u64 = 0,
    active_idle_started_step: u64 = 0,
    ui_handoff: scheduler.UiHandoffTracker = .{},
    suspended_guest_threads: [MAX_SUSPENDED_GUEST_THREADS]SuspendedGuestThread = [_]SuspendedGuestThread{.{}} ** MAX_SUSPENDED_GUEST_THREADS,
    suspended_guest_thread_count: usize = 0,
    x87: X87State = .{},
    guest_stdin_pointer_address: u64 = 0,
    guest_stdout_pointer_address: u64 = 0,
    guest_stderr_pointer_address: u64 = 0,
    guest_log_buffer_address: u64 = 0,
    guest_log_mirror_fd: i32 = -1,
    /// Collapses consecutive identical mirrored guest lines. A guest loop that
    /// logs is the guest's defect, but a runtime whose diagnostics become
    /// unusable because of it has adopted that defect as its own — and with a
    /// workload whose source is unavailable there is no other remedy.
    guest_log_repetition: log_repetition.Collapser = .{},
    guest_log_cycles: log_repetition.CycleDetector = .{},
    guest_modules: guest_module_map.Map = .{},
    guest_module_failed_loads: u64 = 0,
    guest_log_line_count: u64 = 0,
    guest_stdio_write_count: u64 = 0,
    guest_stdout_byte_count: u64 = 0,
    guest_stderr_byte_count: u64 = 0,
    guest_stdio_mirror_failures: u64 = 0,
    guest_stdio_read_count: u64 = 0,
    guest_stdio_read_bytes: u64 = 0,
    guest_stdio_seek_count: u64 = 0,
    guest_stdio_failures: u64 = 0,
    strict_initializers: bool = false,
    strict_imports: bool = false,
    signal_actions: [GUEST_SIGNAL_ACTION_COUNT]GuestSignalAction = [_]GuestSignalAction{.{}} ** GUEST_SIGNAL_ACTION_COUNT,
    signal_frames: [GUEST_SIGNAL_FRAME_DEPTH]GuestSignalFrame = [_]GuestSignalFrame{.{}} ** GUEST_SIGNAL_FRAME_DEPTH,
    signal_frame_count: usize = 0,
    guest_signal_deliveries: u64 = 0,
    atexit_running: bool = false,
    pending_exit_code: u64 = 0,
    atexit_callbacks_invoked: u64 = 0,
    import_resolver: import_resolution.Engine,
    initializer_resolver: initialization_resolution.Engine,
    vtt_resolver: vtt_resolution.VttBindingResolver,
    dynamic_forwarder: dynamic_library_forwarder.Forwarder = .{},
    fs_forwarder: fs_io_forwarder.Forwarder,
    libcxx_filesystem: libcpp_filesystem.Bridge = .{},
    libcxx_streams: libcpp_stream_bridge.Bridge = .{},
    foreign_objects: foreign_object_runtime.Runtime = .{},
    sdl: sdl_runtime.Runtime = .{},
    native_window: native_window_runtime.Runtime = .{},
    native_window_handles_registered: bool = false,
    local_libcpp_stream_targets: std.AutoHashMap(u64, []const u8),
    /// Fast-reject span for the libcpp stream target map. Populated once at
    /// load; the per-instruction handler skips its hash probe whenever rip is
    /// outside this range.
    libcpp_stream_target_min: u64 = 0,
    libcpp_stream_target_max: u64 = 0,
    logging: logging_runtime.Engine = .{},
    backend_diagnostics: x64_backend_diagnostics.Engine = .{},
    xenia_pipeline: xenia_pipeline.Engine = .{},
    /// One-entry memo for the mapped-image half of `isExecutableAddress`.
    /// Empty by construction: low > high matches no address, so the first
    /// lookup falls through to the section search that fills it.
    executable_section_low: u64 = 1,
    executable_section_high: u64 = 0,
    executable_section_verdict: bool = false,
    xenia_gpu_handoff: xenia_gpu_handoff.Ledger = .{},
    /// Unified producer-to-present causal evidence. Unlike the handoff ledger
    /// this includes the first-draw boundary and a bounded wait/signal tail,
    /// so a run that submits state but never draws points at the title's next
    /// owner instead of collapsing everything into "VdSwap missing".
    xenia_gpu_causal_trace: xenia_gpu_causal_trace.Ledger = .{},
    /// Translation between the Xbox addresses Xenia prints and the host-view
    /// addresses Rosette actually interprets. Learned from Xenia's mmap rather
    /// than hardcoded to this process run.
    xenia_memory_views: xenia_memory_views.Model = .{},
    pthreads: pthread_runtime.Runtime = .{},
    scheduler_log: scheduler.SchedulerEventLog = .{},
    jit_log: jit.JitEventLog = .{},
    macho_log: macho_log.Logger = .{},
    tlv: tlv_runtime.Runtime = .{},
    diagnostic_text: diagnostic_text_accelerator.Engine = .{},
    /// Preflight watches a handful of configuration keys whose binding the run
    /// depends on, comparing the file Rosette serviced the open for against the
    /// values the guest itself prints. Both readings cross this runtime, so
    /// nothing is asked of the guest and nothing about it is trusted.
    preflight: preflight_lib.Collector = .{},
    preflight_report: preflight_lib.Report = .{},
    preflight_evaluated: bool = false,
    /// Set when Rosette builds the configuration dump itself from the file. The
    /// dump then restates the file rather than reporting what the guest bound,
    /// so it must never be used as the second, independent reading.
    preflight_dump_is_accelerated: bool = false,
    /// Runtime build/activation gate. Compilation and execution are separate
    /// states: a generated function is not considered useful until an actual
    /// activation boundary and the Xenia startup contract have been observed.
    ready: ready_compiler.Runtime = .{},
    memory_forwarder: memory_management_forwarder.Manager,
    sparse_memory: sparse_virtual_memory.Manager,
    /// Derived model of the guest address window. Replaces the hardcoded
    /// 0x80000000..0xA0000000 predicate: observations arrive from sparse
    /// mappings, and every classification reports whether it is derived or
    /// still running on the bootstrap default.
    guest_address_space: guest_address_space.Model = .{},
    memory_regions: memory_provenance.Registry,
    memory_writes: memory_write_provenance.Tracker = .{},
    // One ledger per recovery family: its own count, its own log throttle, and
    // its own loop guard. These were five bare counters and one shared guard,
    // which made every one of them ambiguous — see recovery_ledger.zig.
    generated_endian_contract: recovery_ledger.Ledger = .{},
    generated_null_scalar_read: recovery_ledger.Ledger = .{},
    generated_null_indirect: recovery_ledger.Ledger = .{},
    // Skips of indirect transfers from JIT-generated code to unpatched Xenia
    // indirection-table sentinels (guest-module addresses such as 0x82582cc8):
    // the same code-cache-miss family as generated_null_indirect, but the
    // target is the guest function address itself rather than 0.
    generated_guest_dispatch: recovery_ledger.Ledger = .{},
    // Zero-allocation, fail-closed recognizer for Xenia's generated
    // CALL_POSSIBLE_RETURN path. It may redirect only when the 0x67 null-base
    // load, matching guest return, tail-jump shape, and host frame all agree.
    bounded_dispatch: bounded_dispatch_fst.Machine = .{},
    // The transducer's own recoveries. Previously its redirects were counted
    // against the null-scalar-read and frame-return families, so neither of
    // those counters meant what it said and the transducer had no loop guard.
    bounded_dispatch_recoveries: recovery_ledger.Ledger = .{},
    /// Policy: may the dispatch transducer continue past an unresolvable guest
    /// dispatch on a stated assumption? On by default so a run reaches its next
    /// distinct failure instead of stopping at a known one; set
    /// ROSETTE_MACHO_STRICT_DISPATCH=1 to restore strict fail-closed behaviour.
    allow_assumed_dispatch_continuation: bool = true,
    /// Single-owner selection for generated-code scalar faults. Evaluates every
    /// claim so an overlap is reported rather than resolved by ordering.
    generated_fault_arbiter: memory_access.GeneratedFaultArbiter =
        memory_access.GeneratedFaultArbiter.init(&memory_access.generated_fault_claims),
    // RIP of the most recent generated null scalar read satisfied as
    // zero-fill; the null indirect transfer recovery reports the linkage when
    // a null function pointer dispatch follows within a short window.
    last_generated_null_read_rip: u64 = 0,
    // Frame-return recoveries for generated-code tail dispatches (null pointer
    // or guest sentinel): the bytes after the dispatch are Xenia's dead
    // function-exit epilogue, so we return to the host caller via [rbp+8]
    // instead of falling through (which double-deallocates the frame).
    generated_dispatch_frame_return: recovery_ledger.Ledger = .{},
    /// Returns that were executed as indirect dispatches because the target
    /// register held the guest return address byte-reversed, so Xenia's
    /// CALL_POSSIBLE_RETURN compare could not match. Its own family: these are
    /// not unresolvable dispatches, they are dispatches that should never have
    /// happened, and folding them into the null-indirect count would hide the
    /// byte-order defect behind a code-cache-miss statistic.
    generated_missed_guest_return: recovery_ledger.Ledger = .{},
    /// Base registers holding a guest address whose bytes were never converted
    /// from big-endian. The low half is zero, so the fault presents as a null
    /// pointer — its own family because "the pointer was never set" and "the
    /// pointer was set and not converted" send an investigation to opposite
    /// ends of the runtime.
    generated_byte_order_repair: recovery_ledger.Ledger = .{},
    /// Population of generated-code dispatch sites the bounded machine has met,
    /// split by whether it got through. Individual recoveries each report
    /// themselves; only this says whether a run met one stubborn site or forty.
    dispatch_census: dispatch_recovery.Census = .{},
    /// The guest-driven GPU bootstrap, as an ordered contract. A graphics stack
    /// that produces nothing reports zeros everywhere; the frontier is what says
    /// which step was the first not to happen and whether it was reachable —
    /// the only reading that decides whether to look at the GPU at all.
    gpu_bootstrap: gpu.Contract = .{},
    /// VdSwap's call, encoding, completion, publication and consumption are
    /// distinct facts. The call itself comes from execution tracepoints; these
    /// two stages come from Xenia's structured encoder contract, while the
    /// bootstrap's final step requires an authentic CP-consumed XE_SWAP.
    guest_vdswap_packet_encoded: bool = false,
    guest_vdswap_entry_completed: bool = false,
    /// Physical base and size of the ring the guest named in
    /// VdInitializeRingBuffer. Learned from the guest's own call, because that
    /// is the only moment the address exists.
    gpu_ring_watch_base: u64 = 0,
    gpu_ring_watch_size: u64 = 0,
    gpu_ring_watch_host_virtual: u64 = 0,
    gpu_ring_watch_host_physical: u64 = 0,
    /// Whether the guest ever *changed* the ring write pointer, as opposed to
    /// writing the register. Two writes of the same value publish nothing, and
    /// counting them as submissions credits the producer with work it never
    /// did — which is what sends a no-frame investigation past the producer and
    /// into the command processor.
    gpu_ring_publication: gpu.RingPublication = .{},
    /// The preconditions a frame needs, each with an owner. Fed from evidence
    /// the other GPU subsystems already hold; its job is to say which unmet
    /// clause is Rosette's to supply and which must not be supplied at all.
    /// See `lib/gpu/contract.zig`.
    graphics_contract: gpu.ContractLedger = .{},
    /// Cross-layer graphics evidence. This is deliberately broader than the
    /// graphics/VdSwap ladders: a native Cocoa/Vulkan presenter can be healthy
    /// while the Xenos producer is stalled, and the report must keep those
    /// paths independent.
    graphics_health: graphics_health_contract.Ledger = .{},
    /// Host-owned coordination policy at the guest/GPU/presenter seam. It
    /// returns directives and evidence only; it cannot synthesize a guest
    /// VdSwap, advance a guest ring pointer or release a guest wait.
    application_controller: application_controller.Controller = .{},
    /// Callable application-framework ledger. The exported C ABI is bound to
    /// this process-owned instance while the translated image is running, so
    /// Xenia observes the same state that the frontier report prints.
    application_framework: application_framework.Framework = .{},
    application_controller_host_drains: u64 = 0,
    application_controller_host_refreshes: u64 = 0,
    application_framework_last_sequence: u64 = std.math.maxInt(u64),
    graphics_health_last_fingerprint: u64 = std.math.maxInt(u64),
    application_controller_last_fingerprint: u64 = std.math.maxInt(u64),
    /// The GPU-facing kernel exports a title reads before it will present, and
    /// whether anything supplied them. See `lib/gpu/kernel_surface.zig`: the
    /// ladder can only see calls, and an unpopulated *variable* export stops a
    /// title without ever producing one.
    gpu_kernel_surface: gpu.KernelSurface = .{},
    gpu_kernel_surface_addresses: gpu.kernel_surface.AddressTable = .{},
    /// When each piece of platform state was provisioned, by whom, and whether
    /// its owner later agreed. The kernel-variable surface answers "is it
    /// populated"; by the time anything asks that, it is. This answers "was it
    /// there before the title read it", which is the question a late write
    /// fails and every other counter hides. See `lib/gpu/custody.zig`.
    gpu_provisioning_custody: gpu.CustodyLedger = .{},
    gpu_provisioning_early_attempts: u64 = 0,
    /// Whether the run ended because the guest stopped or because the run did.
    /// Rosette counted guest steps and host seconds and never knew how much of
    /// the *title's* own timeline a run had covered, which is the variable that
    /// decides whether "never happened" means "broken" or "not yet".
    run_horizon: run_horizon.Ledger = .{},
    run_started_at_ns: u64 = 0,
    run_horizon_vdswap_mask: u32 = 0,
    /// The same exports, read the way the title reads them: slot first, then
    /// the storage the slot points at. See `lib/gpu/kernel_variables.zig`. The
    /// surface above treats the slot's contents as the value, which cannot tell
    /// a healthy pointer from the loader's unimplemented sentinel and cannot
    /// tell a variable the *kernel* failed to write from one the *title* has
    /// not written yet. Those have opposite owners.
    gpu_kernel_variables: gpu.KernelVariableSurface = .{},
    /// Strict VdSwap -> PM4_XE_SWAP evidence. This is deliberately separate
    /// from the broad graphics contract: a generic PM4 batch or a retained
    /// nested draw cannot satisfy authentic swap consumption.
    gpu_vd_swap_contract: gpu.VdSwapContract = .{},
    /// Whether the harness stood in for a step the title never took, and at
    /// which tier. See `lib/gpu/swap_substitution.zig`. Kept separate from
    /// every authentic counter in the subsystem, permanently: a frame the
    /// harness caused must never be summable with one the title caused.
    gpu_swap_substitution: gpu.SubstitutionLedger = .{},
    /// Execution truth for the same substitution: what the synthetic queue
    /// actually wrote into the published ring, as opposed to what the decision
    /// layer authorised. See `lib/gpu/ring_injection.zig`. The packet lands in
    /// ring memory the emulator reads; advancing the emulator's own write
    /// pointer register is the one part no memory write can reach, and the
    /// ledger and log line name that boundary out loud.
    gpu_ring_injection: gpu.RingInjection = .{},
    /// The front buffer the most recent swap packet named, if the ring has ever
    /// held one. This is the only place a console-side frame's address, extent
    /// and format are all stated at once, so it is what a harness present path
    /// has to read.
    gpu_frontbuffer: ?gpu.Pm4SwapDescription = null,
    gpu_ring_scan_reports: u64 = 0,
    /// Stateful Xenos PM4 execution derived from the guest's readable ring.
    /// This does not advance CP_RPTR or manufacture a submission; it is the
    /// backend-neutral state machine that a real Vulkan command recorder can
    /// consume once the guest publishes a batch.
    gpu_xenos_runtime: gpu.XenosRuntime = .{},
    /// Lazy, process-owned Xenos EDRAM backing.  It is allocated after the
    /// Mach-O state exists so a run that never reaches GPU setup pays no inline
    /// struct cost, while every live PM4 runtime still has a real resolve store.
    gpu_xenos_edram: []u8 = &.{},
    /// Reusable linear RGBA8 target for the backend-neutral EDRAM resolve.
    /// This remains separate from the guest front buffer until a non-zero
    /// resolve exists, so an incomplete shader path cannot erase title pixels.
    gpu_xenos_resolve_scratch: []u8 = &.{},
    gpu_xenos_last_ring_epoch: u64 = std.math.maxInt(u64),
    /// Publication epoch of the last retained batch handed to the stateful
    /// command processor.  Separate from `gpu_xenos_last_ring_epoch` because
    /// the two paths select different extents: that one uses the span the ring
    /// pointers describe, this one the envelope of the dwords still present in
    /// ring memory after the command processor drained them.
    gpu_xenos_last_payload_epoch: u64 = std.math.maxInt(u64),
    gpu_xenos_retained_executions: u64 = 0,
    gpu_xenos_retained_refusals: u64 = 0,
    /// Diagnostics for the physical-to-Xenos callback boundary. The physical
    /// projection is authoritative; A/C/E aliases are used only when that
    /// projection is unreadable, and disagreement is fail-closed.
    gpu_xenos_memory_physical_misses: u64 = 0,
    gpu_xenos_memory_alias_fallbacks: u64 = 0,
    gpu_xenos_memory_alias_disagreements: u64 = 0,
    gpu_xenos_memory_alias_log_count: u64 = 0,
    /// Guest-owned callback installed by VdSetGraphicsInterruptCallback.
    /// PM4 completion is queued into the cooperative scheduler; it is never
    /// invoked from the ring decoder's synchronous memory walk.
    gpu_interrupt_callback: u64 = 0,
    gpu_interrupt_callback_arg: u64 = 0,
    gpu_interrupt_callback_registrations: u64 = 0,
    gpu_interrupt_dispatches: u64 = 0,
    gpu_interrupt_dispatch_failures: u64 = 0,
    /// Draw-completion events are tracked separately from the aggregate
    /// interrupt counter.  A command processor can queue a completion while
    /// the guest callback is absent or rejected; those are different breaks
    /// in the PM4 -> VdSwap handoff.
    gpu_draw_completion_dispatch_attempts: u64 = 0,
    gpu_draw_completion_dispatches: u64 = 0,
    gpu_draw_completion_dispatch_failures: u64 = 0,
    /// Persistent system command buffer returned by VdGetSystemCommandBuffer.
    /// Xenia's Mac video layer allocates this from the physical system heap
    /// and reuses it for the lifetime of the graphics system. Keeping the
    /// address in Mach-O state makes repeated imports idempotent and prevents
    /// a retry from exposing a different command buffer to the guest.
    gpu_system_command_buffer: u64 = 0,
    gpu_system_command_buffer_size: u64 = 0,
    /// Whether a draw packet has ever been found in ring memory, including a
    /// draw reached through an INDIRECT_BUFFER packet. Latched: a drained ring
    /// holds an empty span, so a title that rendered a frame and had it
    /// consumed is indistinguishable through the pointers alone from one that
    /// never drew, and those are opposite findings.
    gpu_ring_draws_seen: bool = false,
    gpu_ring_draws_last_count: u32 = 0,
    /// The emulator's own applied-update counter for the ring write pointer,
    /// parsed from its `wptr_updates(total=...)` report. Independent of the
    /// `REGISTER WRITE` line Rosette's tracker reads, and in the observed run
    /// the two disagree: one says two writes, the other says zero.
    gpu_xenia_wptr_updates: u64 = 0,
    gpu_xenia_wptr_counter_seen: bool = false,
    gpu_frontbuffer_offered: bool = false,
    /// Kernel-owned variables the harness supplied, and the ones it tried to
    /// supply and could not. Counted separately: a provisioning step that
    /// silently did nothing would make the report claim platform state exists
    /// when the title will read whatever was already there.
    gpu_kernel_variable_writes: u64 = 0,
    gpu_kernel_variable_write_failures: u64 = 0,
    /// What had to be true before the title's display bring-up, and whether it
    /// became true in the right order. See `lib/gpu/preinitialization.zig`. The
    /// graphics contract answers "which precondition is unmet"; this answers
    /// "were they established in the order the title reads them", which a
    /// ladder cannot, because by the end of a run everything is present and the
    /// title is still wedged on a decision it made before they were.
    gpu_preinitialization: gpu.PreinitLedger = .{},
    /// Which of the independent observers of the ring write pointer believe it
    /// moved, and whether they agree. See `lib/gpu/submission_provenance.zig`.
    /// Rosette's own tracker is fed by parsing a line the emulator printed; the
    /// emulator's applied-update counter and the register aperture are separate
    /// and stronger. When they disagree, `published()` is a claim about text.
    gpu_submission_provenance: gpu.SubmissionProvenance = .{},
    /// What the emulator's own callback-missing probe reported about each
    /// graphics import. See `lib/gpu/import_binding.zig`: the probe firing
    /// looks like a binding failure and in the observed run reported every
    /// import correctly bound, which points at the callback state machine
    /// rather than at the loader.
    gpu_import_binding: gpu.ImportBindingLedger = .{},
    /// Non-zero dwords found in ring memory. The only direct evidence that a
    /// producer wrote anything, independent of every pointer counter.
    gpu_ring_nonzero_dwords: u32 = 0,
    /// Whether the guest's waits block and are released, or are satisfied on
    /// arrival and never block. See `lib/diagnostics/guest_wait_liveness.zig`.
    /// `result=00000000` is returned by both, and only the ratio separates a
    /// working handshake from a spin that looks like a stall in whichever
    /// subsystem the loop belongs to.
    guest_wait_liveness: guest_wait_liveness.Ledger = .{},
    /// Threads that will never wake, and who was supposed to wake them. See
    /// `lib/diagnostics/deadlock_predictor.zig`. A livelock burns CPU making no
    /// progress and a deadlock burns nothing, so the detector that finds one is
    /// structurally blind to the other: a parked thread emits no log lines and
    /// is invisible to every heuristic built on activity.
    deadlock_predictor: deadlock_predictor.Ledger = .{},
    /// Work that was deferred because it failed, and the demand that later
    /// needs it. See `lib/diagnostics/deferred_work.zig`. The two events are
    /// billions of steps apart, so without this the crash is attributed to the
    /// resolver that found a null rather than to the emit that produced one.
    deferred_work: deferred_work.Ledger = .{},
    /// One synchronisation object, one identity, however many address spaces
    /// name it. See `lib/diagnostics/sync_object_identity.zig`. The emulator
    /// prints `obj_ptr=` (host) and `guest_obj=` (console) for the same object
    /// and other lines print only one of them, so without this an object waited
    /// on through one name and signalled through the other is counted as two —
    /// which is exactly the scatter of one-count predictor entries a stalled
    /// run produces.
    sync_object_identity: sync_object_identity.Table = .{},
    /// Whether each repeating wait is a problem or the system working, and the
    /// audit for the ones that are problems. See `lib/diagnostics/wait_audit.zig`.
    /// Every predictor here detects a *pattern*, and patterns are what healthy
    /// systems are made of — an audio pump and a wedged rotation are the same
    /// pattern. What separates them is whether anything else in the run moved,
    /// which is what this holds.
    wait_audit: wait_audit.Ledger = .{},
    /// How much of the capability surface the emulator needs from this host
    /// actually works. See `lib/diagnostics/host_contract_coverage.zig`. Every
    /// other diagnostic here is a microscope; this is the one that answers "how
    /// far along is this" instead of "what is the frontier of the one ladder
    /// this subsystem watches".
    host_coverage: host_contract_coverage.Ledger = .{},
    /// Bounded releases of waits nobody will ever satisfy, and what each one
    /// proved. See `lib/diagnostics/stall_release.zig`. A parked thread on a
    /// never-signalled object is either a lost wakeup (this runtime's defect)
    /// or an unsatisfied predicate (the guest's), and nothing distinguishes
    /// them from outside — one spurious wake does, because a correct waiter
    /// re-checks its predicate on return.
    stall_release: stall_release.Ledger = .{},
    /// Subsystems that failed to come up, and whether the run stopped moving
    /// afterwards. See `lib/diagnostics/bringup_failure.zig`. A subsystem that
    /// fails takes its thread with it, and everything waiting on that thread
    /// then waits for the rest of the run — the hang is downstream and the
    /// cause is thousands of log lines earlier.
    bringup_failures: bringup_failure.Ledger = .{},
    /// Whether the emulator has registered a handler for the Xenos register
    /// aperture's pages. The only evidence reachability can have: the pages are
    /// unreadable by design, and a title that programs its GPU through kernel
    /// exports never stores to them, so waiting for a guest store proves
    /// nothing about whether one *could* arrive.
    gpu_register_aperture_reachable: bool = false,
    /// Guest `KeSetEvent` calls that found their event already signalled,
    /// against the total observed. A wait that does not consume its signal
    /// never blocks, and every producer/consumer handshake above it free-runs
    /// — which reads as a GPU stall and is not one.
    guest_event_sets: u64 = 0,
    guest_event_sets_already_signalled: u64 = 0,
    /// Guest traffic to the Xenos memory-mapped register aperture. The pages
    /// behind it are unreadable by design, so every register access the title
    /// performs arrives as a protection fault and nowhere else — which makes
    /// this the only place that can say whether the title programmed the GPU
    /// at all. Without it, "the guest never wrote CP_RB_BASE" and "the guest
    /// wrote it and Rosette lost the store" produce identical evidence:
    /// nothing.
    gpu_register_aperture: gpu.RegisterApertureObserver = .{},
    /// The guest critical section the GPU path registered, put under write
    /// provenance so a later zero-owner contention can say whether anything
    /// ever wrote it. Learned from the guest's own registration, because that
    /// is the only moment the address exists.
    critical_section_watch_base: u64 = 0,
    critical_section_watch_host_virtual: u64 = 0,
    critical_section_watch_host_physical: u64 = 0,
    /// Xenia's `virtual_membase_` is the mapping base itself, so code that
    /// computes `membase + guest_address` reaches a *different host page* than
    /// `TranslateVirtual` (which adds the macOS 4 KiB E000-heap bias). The run
    /// that first diagnosed the zeroed VdHSIOCalibrationLock recorded the
    /// -1 initializer through the biased alias and lost the zeroing store
    /// entirely: it landed on this third, unwatched page. The watch now covers
    /// all three views and the integrity checkpoint reads all three, so an
    /// alias mismatch inside the fork is visible as a state disagreement
    /// instead of a NOT_RETAINED dead end.
    critical_section_watch_host_unbiased: u64 = 0,
    critical_section_initial_image: [guest_critical_section.size_bytes]u8 =
        [_]u8{0} ** guest_critical_section.size_bytes,
    critical_section_initial_valid: bool = false,
    critical_section_zero_owner_reports: u64 = 0,
    /// One identity for every boundary record in this run, so evidence from
    /// two runs can never be joined and ordering is a fact rather than an
    /// inference from wall-clock timestamps.
    event_stream: event_identity.Stream = .{},
    /// Execution-boundary tracepoints on the emulator's own graphics entry
    /// points. Whether `VdSwap` ran has been inferred from a log line for three
    /// investigation passes; these answer it from the instruction pointer.
    execution_tracepoints: execution_tracepoints.Set = .{},
    graphics_summary_emissions: u64 = 0,
    graphics_last_frontier_tag: u8 = std.math.maxInt(u8),
    graphics_last_frontier_reached: usize = std.math.maxInt(usize),
    graphics_last_role_mask: u8 = 0,
    graphics_last_ring_published: bool = false,
    graphics_last_anomaly_count: usize = std.math.maxInt(usize),
    graphics_last_causal_events: u64 = std.math.maxInt(u64),
    graphics_last_causal_mask: u16 = std.math.maxInt(u16),
    /// Guest anomalies with what happened after each. A count alone has been
    /// non-zero in every run of this investigation and has therefore stopped
    /// being read; a disposition is what makes one actionable or dismissible.
    anomalies: anomaly_ledger.Ledger = .{},
    /// Authentic guest stores observed inside the ring.
    gpu_ring_writes: u64 = 0,
    vtable_tracker: vt.VtableTracker,
    /// Tracks vtable writes for non-heap (stack-local / modeled) objects.
    /// Registered by the stream bridge during stringstream construction
    /// and checked as a fallback recovery path in readMemVal.
    vtable_stack_registry: vt.StackRegistry,
    /// Tracks __cxa_guard variables that were acquired during the current
    /// initializer run.  When the initializer is deferred, these guards are
    /// cleared so the retry starts from a clean initialization state.
    guard_rollback: guard_rollback_lib.GuardRollback,
    pointer_firewall: pointer_firewall.Firewall,
    page_permissions: []u8,
    smart_stubs: smart_stub_generator.Generator = .{},
    symbol_assembly: symbol_assembly_context.Tracker,
    symbol_assembly_catalog: ?symbol_assembly_context.Catalog = null,
    cxx_exceptions: cxx_exception_diagnostics.Tracker = .{},
    /// Whether catching a guest C++ exception actually recovered anything. See
    /// `lib/diagnostics/guest_exception_ledger.zig`. "Caught" describes the
    /// unwinder, not the program: a handler that logs a failure and abandons
    /// the work it was doing has handled the exception perfectly and left
    /// something downstream to dereference a null.
    guest_exceptions: guest_exception_ledger.Ledger = .{},
    spirv_cross: spirv_cross_diagnostics.Tracker = .{},
    unwinder: itanium_unwinder.Engine = .{},
    dynamic_casts: itanium_dynamic_cast.Engine = .{},
    last_unwind_inspection: ?itanium_unwinder.Inspection = null,
    import_provider_override: ?import_resolution.Provider = null,
    import_confidence_override: ?import_resolution.Confidence = null,
    import_route_cache: [IMPORT_ROUTE_CACHE_SIZE]ImportRouteCacheEntry = [_]ImportRouteCacheEntry{.{}} ** IMPORT_ROUTE_CACHE_SIZE,
    resolving_import_route: ImportRoute = .legacy,
    import_route_cache_hits: u64 = 0,
    import_route_cache_misses: u64 = 0,
    import_route_cache_collisions: u64 = 0,
    import_route_cache_fallbacks: u64 = 0,
    /// Cache hits whose route dispatches straight back into the slow path
    /// (`.legacy`, `.strtoul`). Counted apart so the reported hit rate measures
    /// work avoided rather than lookups matched.
    import_route_cache_slow_hits: u64 = 0,
    /// Fallbacks attributed to the route that declined the symbol it was cached
    /// for. A bare total names nothing; this names the route to fix.
    import_route_fallbacks: [@typeInfo(ImportRoute).@"enum".fields.len]u64 =
        [_]u64{0} ** @typeInfo(ImportRoute).@"enum".fields.len,
    cleo_dispatch_hits: u64 = 0,
    import_handler: import_handler.ImportHandler,
    page_entry_bulk_initializations: u64 = 0,
    page_entry_bulk_bytes: u64 = 0,
    initializer_memory: memory_transaction.Journal,
    initializer_checkpoint: ?InitializerCheckpoint = null,
    // Thread-partitioned retained instruction history. This replaces a single
    // TRACE_BUFFER_LEN ring shared by every guest thread: with thirteen live
    // threads a faulting thread's usable window was a couple of dozen entries,
    // which is why history-based recognizers reported "always zero" for a
    // register set a billion steps earlier. Heap-backed, because per-thread
    // capacity times slot count is far too large to carry by value.
    execution_history: ExecutionHistory,
    /// Generated-only history is discontinuous while native Mach-O code runs.
    /// The epoch makes that omitted interval explicit to post-fault walkers.
    execution_history_epoch: u64 = 0,
    execution_history_filter_active: bool = false,
    /// Whether the instruction currently being stepped is inside the host
    /// image's executable range, set once per step by the decode-cache fast
    /// path (from the entry's fill-time classification) or by the slow path's
    /// own range compare. The execution-history filter reads this instead of
    /// re-running the two range compares on every step.
    step_host_image: bool = false,
    /// One load replaces the per-instruction gates for the init-time
    /// diagnostic switches (verbose trace, SHA1 tracer, trace range). True
    /// when any of them can fire; computed once in `loadAndRun` after all
    /// three are set, because none of them ever changes after startup. A
    /// future per-instruction post-decode gate must extend that computation
    /// or its gate will silently never fire.
    step_tracing_active: bool = false,
    trace_range_start: ?u64 = null,
    trace_range_end: ?u64 = null,
    last_trace_rip: u64 = 0,
    last_trace_op: u64 = 0,
    trace_repeat_count: u64 = 0,
    pending_stub_slot: ?u32 = null,
    pending_stub_entry_rip: ?u64 = null,
    pending_import_stub_rip: ?u64 = null,
    stub_helper_start: u64 = 0,
    stub_helper_end: u64 = 0,
    lazy_import_direct_dispatches: u64 = 0,
    helper_cluster_start: ?u64 = null,
    helper_cluster_end: ?u64 = null,
    import_trace_entries: [IMPORT_TRACE_BUFFER_LEN]ImportTraceEntry = [_]ImportTraceEntry{ImportTraceEntry{}} ** IMPORT_TRACE_BUFFER_LEN,
    import_trace_index: usize = 0,
    import_trace_filled: bool = false,
    unresolved_import_count: u64 = 0,
    pending_control_transfer: ?ControlTransferContext = null,
    terminal_control_transfer: ?exit_diagnostics.ControlTransferFailure = null,
    terminal_memory_failure: ?exit_diagnostics.MemoryAccessFailure = null,
    memory_trace_entries: [MEMORY_TRACE_BUFFER_LEN]exit_diagnostics.MemoryAccessEvent = [_]exit_diagnostics.MemoryAccessEvent{.{}} ** MEMORY_TRACE_BUFFER_LEN,
    memory_trace_index: usize = 0,
    memory_trace_filled: bool = false,
    // P1-2 (perf audit): the per-access memory trace (translateGuest +
    // isExecutable probe + current-instruction re-decode + ring write) runs on
    // every guest load/store but is only consumed post-fault. Off by default
    // so the fast path is a direct slice read; enable with
    // ROSETTE_MACHO_MEMORY_TRACE=1 when diagnosing faults/near-null causality.
    memory_trace_enabled: bool = false,
    // A waiter that has never been notified is not, by itself, a lost-wakeup
    // proof. Long-lived host workers (for example Xenia's idle audio media
    // player) legitimately park on a POSIX condition variable until work is
    // published. Keep the predictor report enabled, but make the synthetic
    // spurious-wake repair an explicit diagnostic experiment.
    // Enable with ROSETTE_MACHO_NEVER_NOTIFIED_REPAIR=1 only after the object
    // has been identified as a broken guest wait rather than an idle worker.
    never_notified_repair_enabled: bool = false,
    // R3 (perf audit, N4): expensive write bookkeeping — capture/commit
    // before-images, the general memory_writes provenance ledger, detailed
    // vtable mutation attribution, and the suspicious-write detector — serves
    // fault-time diagnostics but used to run on every guest store. Off by
    // default so stores keep their fast path; arm with
    // ROSETTE_MACHO_WRITE_DIAGNOSTICS=1 for full diagnosis.
    //
    // Trusted vtable *establishment* is deliberately not owned by this flag.
    // It is correctness-bearing: read-time recovery may only restore a vptr
    // that an authentic constructor write established. Making that identity
    // dependent on a diagnostic environment variable caused native virtual
    // dispatch to regress after otherwise successful object construction.
    // noteGuestWrite (decode-cache invalidation, also correctness-critical)
    // likewise stays always-on.
    write_diagnostics_armed: bool = false,
    /// Set while a Rosette fault repair is writing guest memory, so
    /// write-provenance records the store as `host_repair` instead of
    /// attributing it to the faulting guest instruction. Always set through
    /// `writeMemValAsHostRepair`, never assigned directly.
    host_repair_in_flight: bool = false,
    /// Guest memory kept under write provenance without the global flag.
    /// Seeded behaviourally from generated-code structure-field operands, so
    /// the run does not have to be told in advance which address will matter.
    provenance_watch: ownership_lib.WatchSet = .{},
    /// Guest ranges whose backing Rosette discarded — a MAP_FIXED replacement,
    /// an unmap, or a re-home to a host base the guest never asked for. Every
    /// observer above keys on the guest address and outlives the bytes, so
    /// without this an absence of provenance reads as "the guest never wrote
    /// here" when it means "the storage was replaced under us".
    guest_lifetime: ownership_lib.LifetimeRegistry = .{},
    /// Observed field access shape for the structures generated code addresses.
    /// Distinguishes "this field is never written" (a missing store) from
    /// "written with the wrong value" — different bugs, and the difference is
    /// only visible as an absence measured over the whole run.
    guest_fields: guest_structure.Profile = .{},
    /// Allowance for the generated-code memory trace, whose per-access
    /// instruction re-decode is the most expensive observer in the runtime.
    /// It feeds a *fallback* attribution path (the def-use scan is primary), so
    /// a bounded prefix is enough; exhaustion is reported rather than hidden.
    memory_trace_budget: ownership_lib.Budget = ownership_lib.Budget.init(2_000_000),
    // Always-on endian-contract evidence ring. Populated at the execute site
    // (no re-decode: the interpreter already has the decoded instruction) for
    // the narrow set of ops the generated-endian contract consumes. Unlike the
    // diagnostic-gated memory trace above, this ring is written unconditionally
    // so the contract can substantiate repairs in production runs.
    endian_evidence_entries: [ENDIAN_EVIDENCE_BUFFER_LEN]generated_endian_contract.EvidenceEntry = [_]generated_endian_contract.EvidenceEntry{.{}} ** ENDIAN_EVIDENCE_BUFFER_LEN,
    endian_evidence_index: usize = 0,
    endian_evidence_filled: bool = false,
    guest_files: [GUEST_FILE_MAX]GuestFile = [_]GuestFile{GuestFile{}} ** GUEST_FILE_MAX,
    bound_import_thunks: []BoundImportThunk = &.{},
    decode_cache: []DecodeCacheEntry,
    /// Faulting instructions retried after a guest SIGSEGV handler resolved
    /// the page's protection. See `signal_handling.protectionFaultResolved`.
    guest_protection_retries: u64 = 0,
    decode_cache_hits: u64 = 0,
    decode_cache_misses: u64 = 0,
    /// A miss that filled a way nothing had occupied — the first execution of
    /// newly emitted code. Irreducible: there is nothing to cache yet.
    decode_cache_compulsory_misses: u64 = 0,
    /// A miss that evicted a live decode. This is the addressable kind.
    decode_cache_conflict_misses: u64 = 0,
    decode_cache_stale_rejections: u64 = 0,
    code_generation: u64 = 1,
    /// Which guest pages may hold a cached decode. See
    /// `types.DecodeCachePageSet`: heap-allocated rather than inline so its
    /// 128 KiB does not sit between `regs` and the other per-step fields.
    decode_cache_pages: *types.DecodeCachePageSet,
    /// Previous heartbeat's reading of the acceleration counters. See
    /// `types.PerformanceSample`: the counters are sampled per heartbeat so a
    /// timed-out run still reports its throughput, and reported as deltas so
    /// the fast startup prefix does not average away the steady state.
    performance_sample: types.PerformanceSample = .{},
    mapped_min: u64,
    /// End of the immutable Mach-O image, before the forwarded guest heap.
    /// Used as a two-comparison filter for rare image-owned vtable values so
    /// correctness tracking doesn't put symbol lookups on ordinary stores.
    image_end: u64,
    executable_min: u64,
    executable_max: u64,

    pub fn init(io: std.Io, allocator: std.mem.Allocator, binary_data: []const u8) !MachOState {
        var state = try macho.load(allocator, binary_data);
        errdefer state.deinit();
        var metadata = try macho_metadata.Metadata.init(allocator, binary_data);
        errdefer metadata.deinit();

        var min_vaddr: u64 = std.math.maxInt(u64);
        var max_vaddr: u64 = 0;
        var mapped_min: u64 = std.math.maxInt(u64);
        var executable_min: u64 = std.math.maxInt(u64);
        var executable_max: u64 = 0;

        for (state.segments) |seg| {
            if (seg.vmsize == 0) continue;
            if (seg.vmaddr < min_vaddr) min_vaddr = seg.vmaddr;
            const seg_end = try std.math.add(u64, seg.vmaddr, seg.vmsize);
            if (seg_end > max_vaddr) max_vaddr = seg_end;
            if (seg.initprot != 0) mapped_min = @min(mapped_min, seg.vmaddr);
            if (seg.initprot & 0x04 != 0) {
                executable_min = @min(executable_min, seg.vmaddr);
                executable_max = @max(executable_max, seg_end);
            }
        }

        if (min_vaddr == std.math.maxInt(u64)) return error.NoLoadableSegments;

        const image_base = alignDown(min_vaddr, PAGE_SIZE);
        const image_end = alignUp(max_vaddr, PAGE_SIZE) catch return error.SegmentOverflow;
        const image_size = image_end - image_base;

        const required_mem = image_size + STACK_SIZE;
        const mem_size_aligned = alignUp(required_mem, PAGE_SIZE) catch MEM_SIZE;
        const env_mem = if (envMemSizeMb()) |mb| mb * 1024 * 1024 else MEM_SIZE;
        const final_mem_size = @max(mem_size_aligned, @max(MEM_SIZE, env_mem));

        const mem = try allocator.alloc(u8, @intCast(final_mem_size));
        @memset(mem, 0);

        for (state.segments) |seg| {
            if (seg.vmsize == 0) continue;
            const off = (seg.vmaddr -| image_base);
            if (off + seg.vmsize > final_mem_size) continue;
            const copy_size = @min(seg.filesize, seg.vmsize);
            if (copy_size > 0) {
                const file_off = seg.fileoff;
                if (file_off + copy_size <= binary_data.len) {
                    @memcpy(mem[off..][0..@as(usize, @intCast(copy_size))], binary_data[file_off..][0..@as(usize, @intCast(copy_size))]);
                }
            }
        }

        var entry_vaddr: u64 = state.entry_point;
        if (state.entry_point > 0) {
            var mapped_entry: ?u64 = null;
            for (state.segments) |seg| {
                const file_range_end = seg.fileoff + seg.filesize;
                if (state.entry_point >= seg.fileoff and state.entry_point < file_range_end) {
                    mapped_entry = seg.vmaddr + (state.entry_point - seg.fileoff);
                    break;
                }
            }
            if (mapped_entry) |resolved| {
                entry_vaddr = resolved;
            } else if (state.entry_point < image_size) {
                entry_vaddr = image_base + state.entry_point;
            }
        }

        const initializer_count = metadata.initializer_addresses.len;
        const decode_cache = try allocator.alloc(DecodeCacheEntry, DECODE_CACHE_ENTRY_COUNT);
        @memset(decode_cache, .{});
        const decode_cache_pages = try allocator.create(types.DecodeCachePageSet);
        decode_cache_pages.* = .{};
        const page_permissions = try allocator.alloc(u8, @intCast(final_mem_size / PAGE_SIZE));
        @memset(page_permissions, PAGE_READ | PAGE_WRITE);
        var result = MachOState{
            .allocator = allocator,
            .io = io,
            .mem = mem,
            .mem_base = image_base,
            .mem_size = final_mem_size,
            .heap_next = image_end,
            .data = binary_data,
            .segments = try allocator.dupe(MachSegment, state.segments),
            .metadata = metadata,
            .entry_point_vaddr = entry_vaddr,
            .stack_size = if (state.stack_size > 0) state.stack_size else STACK_SIZE,
            .import_resolver = import_resolution.Engine.init(allocator),
            .initializer_resolver = initialization_resolution.Engine.init(allocator, initializer_count),
            .vtt_resolver = vtt_resolution.VttBindingResolver.init(allocator),
            .initializer_memory = memory_transaction.Journal.init(allocator, PAGE_SIZE),
            .execution_history = try ExecutionHistory.init(allocator, TRACE_THREAD_SLOTS, TRACE_PER_THREAD_LEN),
            .fs_forwarder = fs_io_forwarder.Forwarder.init(allocator),
            .memory_forwarder = memory_management_forwarder.Manager.init(allocator),
            .sparse_memory = sparse_virtual_memory.Manager.init(allocator),
            .memory_regions = memory_provenance.Registry.init(allocator),
            .pointer_firewall = pointer_firewall.Firewall.init(allocator),
            .symbol_assembly = symbol_assembly_context.Tracker.init(allocator),
            .page_permissions = page_permissions,
            .local_libcpp_stream_targets = std.AutoHashMap(u64, []const u8).init(allocator),
            .import_handler = import_handler.ImportHandler.init(allocator),
            .vtable_tracker = vt.VtableTracker.init(allocator),
            .vtable_stack_registry = vt.StackRegistry.init(allocator),
            .guard_rollback = guard_rollback_lib.GuardRollback.init(allocator),
            .decode_cache = decode_cache,
            .decode_cache_pages = decode_cache_pages,
            .mapped_min = mapped_min,
            .image_end = image_end,
            .executable_min = executable_min,
            .executable_max = executable_max,
        };
        errdefer result.deinit();
        // The host clock the horizon ledger measures emulated time against.
        // Without it the run knows how many instructions it executed and not
        // how long that took, and the ratio is the whole point.
        result.run_started_at_ns = startup_observer.monotonicNanoseconds();
        result.gpu_xenos_edram = try allocator.alloc(u8, gpu.edram.size_bytes);
        @memset(result.gpu_xenos_edram, 0);
        result.gpu_xenos_runtime.attachEdram(result.gpu_xenos_edram);
        for (result.segments) |segment| {
            const kind: memory_provenance.RegionKind = if (segment.initprot & 0x04 != 0)
                .macho_text
            else if (segment.initprot & 0x02 != 0)
                .macho_data
            else
                .macho_const;
            _ = result.memory_regions.register(segment.vmaddr, segment.vmsize, .{
                .read = segment.initprot & 0x01 != 0,
                .write = segment.initprot & 0x02 != 0,
                .execute = segment.initprot & 0x04 != 0,
            }, kind, segment.name, 0);
            result.setPagePermissions(segment.vmaddr, segment.vmsize, @intCast(segment.initprot & 0x07));
        }
        const stack_size = result.stack_size;
        const stack_start = result.mem_base + result.mem_size -| stack_size;
        _ = result.memory_regions.register(stack_start, stack_size, .{}, .guest_stack, "main guest stack", 0);
        result.setPagePermissions(stack_start, stack_size, PAGE_READ | PAGE_WRITE);
        for (std.enums.values(compat_runtime.SyntheticThunk)) |thunk| {
            result.registerSyntheticThunk(compat_runtime.thunkAddress(thunk), 1, @tagName(thunk));
        }
        result.guest_files[0] = .{ .active = true, .fd = 0, .kind = .regular };
        result.guest_files[1] = .{ .active = true, .fd = 1, .kind = .stdout };
        result.guest_files[2] = .{ .active = true, .fd = 2, .kind = .stderr };
        result.internal_targets.cxxopts_split_option_names = result.metadata.symbolAddressWithPrefix(
            "__ZN7cxxopts6values11parser_tool18split_option_names",
        ) orelse 0;
        result.internal_targets.xenia_cpu_feature_detector_initialize_cpu_info = result.metadata.symbolAddressWithPrefix(
            "__ZN2xe3cpu7backend3x6418CPUFeatureDetector17InitializeCPUInfoEv",
        ) orelse 0;
        result.internal_targets.xenia_vulkan_provider_vulkan_device = result.metadata.symbolAddressWithPrefix(
            "__ZNK2xe2ui6vulkan14VulkanProvider13vulkan_deviceEv",
        ) orelse 0;
        result.internal_targets.parse_launch_arguments = result.metadata.symbolAddressWithPrefix(
            "__ZN4cvar20ParseLaunchArguments",
        ) orelse 0;
        result.internal_targets.initialize_logging = result.metadata.symbolAddressWithPrefix(
            "__ZN2xe17InitializeLogging",
        ) orelse 0;
        result.internal_targets.shutdown_logging = result.metadata.symbolAddressWithPrefix(
            "__ZN2xe15ShutdownLoggingEv",
        ) orelse 0;
        result.internal_targets.cvar_add_to_launch_options_count = result.metadata.symbolAddressesMatching(
            "__ZN4cvar",
            "AddToLaunchOptions",
            &result.internal_targets.cvar_add_to_launch_options,
        );
        result.internal_targets.guest_log_get_thread_buffer = result.metadata.symbolAddressWithPrefix(
            "__ZN2xe7logging8internal15GetThreadBufferEv",
        ) orelse 0;
        result.internal_targets.guest_log_append_formatted = result.metadata.symbolAddressWithPrefix(
            "__ZN2xe7logging8internal13AppendLogLineENS_8LogLevelEcm",
        ) orelse 0;
        result.internal_targets.guest_log_append_view = result.metadata.symbolAddressWithPrefix(
            "__ZN2xe7logging13AppendLogLineENS_8LogLevelEc",
        ) orelse 0;
        result.internal_targets.libcxx_basic_streambuf_pubsetbuf = result.metadata.symbolAddressWithPrefix(
            "__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE9pubsetbuf",
        ) orelse 0;
        result.internal_targets.libcxx_basic_ifstream_default_constructor = result.metadata.symbolAddressWithPrefix(
            "__ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEC1Ev",
        ) orelse 0;
        result.internal_targets.libcxx_basic_ifstream_destructor_1 = result.metadata.symbolAddressWithPrefix(
            "__ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEED1Ev",
        ) orelse 0;
        result.internal_targets.libcxx_basic_ifstream_destructor_2 = result.metadata.symbolAddressWithPrefix(
            "__ZNSt3__114basic_ifstreamIcNS_11char_traitsIcEEED2Ev",
        ) orelse 0;
        result.internal_targets.libcxx_getline = result.metadata.symbolAddressWithPrefix(
            "__ZNSt3__17getlineB7v160006IcNS_11char_traitsIcEENS_9allocatorIcEEEERNS_13basic_istreamIT_T0_EES9_RNS_12basic_stringIS6_S7_T1_EE",
        ) orelse 0;
        result.internal_targets.libcxx_getline_delimiter = result.metadata.symbolAddressWithPrefix(
            "__ZNSt3__17getlineB7v160006IcNS_11char_traitsIcEENS_9allocatorIcEEEERNS_13basic_istreamIT_T0_EES9_RNS_12basic_stringIS6_S7_T1_EES6_",
        ) orelse 0;
        result.internal_targets.libcxx_basic_string_substr = result.metadata.symbolAddressWithPrefix(
            "__ZNKSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6substrB7v160006Emm",
        ) orelse 0;
        result.internal_targets.profile_manager_load_account = result.metadata.symbolAddressWithPrefix(
            "__ZN2xe6kernel3xam14ProfileManager11LoadAccountE",
        ) orelse 0;
        result.internal_targets.profile_manager_dismount_profile = result.metadata.symbolAddressWithPrefix(
            "__ZN2xe6kernel3xam14ProfileManager15DismountProfileE",
        ) orelse 0;
        result.internal_targets.profile_account_insert_or_assign = result.metadata.symbolAddressWithPrefix(
            "__ZNSt3__13mapIyN2xe6kernel3xam16X_XAMACCOUNTINFOENS_4lessIyEENS_9allocatorINS_4pairIKyS4_EEEEE16insert_or_assign",
        ) orelse 0;
        result.internal_targets.print_config_to_log = result.metadata.symbolAddressWithPrefix(
            "__ZN6config16PrintConfigToLog",
        ) orelse 0;
        result.internal_targets.imgui_default_malloc = result.metadata.symbolAddressWithPrefix(
            "__ZL13MallocWrappermPv",
        ) orelse 0;
        result.internal_targets.imgui_default_free = result.metadata.symbolAddressWithPrefix(
            "__ZL11FreeWrapperPvS_",
        ) orelse 0;
        result.internal_targets.imgui_mem_alloc = result.metadata.symbolAddressWithPrefix(
            "__ZN5ImGui8MemAllocEm",
        ) orelse 0;
        result.internal_targets.imgui_mem_free = result.metadata.symbolAddressWithPrefix(
            "__ZN5ImGui7MemFreeEPv",
        ) orelse 0;
        result.internal_targets.imgui_settings_push_back = result.metadata.symbolAddressWithPrefix(
            "__ZN8ImVectorI20ImGuiSettingsHandlerE9push_backERKS0_",
        ) orelse 0;
        result.internal_targets.imgui_create_context = result.metadata.symbolAddressWithPrefix(
            "__ZN5ImGui12CreateContextEPNS_9ImFontAtlasE",
        ) orelse 0;
        result.internal_targets.imgui_get_current_window = result.metadata.symbolAddressWithPrefix(
            "__ZN5ImGui16GetCurrentWindowEv",
        ) orelse 0;
        result.internal_targets.imgui_text_ex = result.metadata.symbolAddressWithPrefix(
            "__ZN5ImGui6TextExEPKcS1_i",
        ) orelse 0;
        if (result.internal_targets.imgui_text_ex != 0) {
            machoCapturePrint(
                "macho-processor: ImGui TextEx compatibility target resolved: address=0x{x} renderer_policy=noop\n",
                .{result.internal_targets.imgui_text_ex},
            );
        }
        result.internal_targets.page_entry_construct_at_end = result.metadata.symbolAddressWithPrefix(
            "__ZNSt3__114__split_bufferIN2xe9PageEntryERNS_9allocatorIS2_EEE18__construct_at_endEm",
        ) orelse 0;
        result.internal_targets.libcpp_atomic_bool_control_block_vtable = result.metadata.symbolAddressWithPrefix(
            libcpp_shared_control_block.atomic_bool_vtable_symbol_prefix,
        ) orelse 0;
        result.internal_targets.sha1_process_bytes = result.metadata.symbolAddressWithPrefix(
            "__ZN4sha14SHA112processBytesEPKvm",
        ) orelse 0;
        // Keep the entry-detection window local to processBytes. The SHA1
        // methods are not contiguous in Xenia's Mach-O image; spanning from
        // processBytes to processBlock includes unrelated XEX loader code and
        // caused the tracer to auto-latch long before SHA1 was called.
        const sha1_process_block = result.metadata.symbolAddressWithPrefix(
            "__ZN4sha14SHA112processBlockEv",
        ) orelse 0;
        result.internal_targets.sha1_start =
            result.internal_targets.sha1_process_bytes;
        result.internal_targets.sha1_end =
            result.internal_targets.sha1_process_bytes +| 0x40;
        const raw_vtable = result.metadata.symbolAddressWithPrefix(
            "__ZTVN2xe6kernel7XModuleE",
        );
        // Itanium C++ ABI: __ZTV points to the start of the vtable data
        // (offset_to_top + typeinfo).  The object stores a pointer to vtable[0],
        // which is 16 bytes past __ZTV.
        if (raw_vtable) |addr| result.internal_targets.xmodule_vtable = addr + 16;
        machoCapturePrint(
            "macho-processor: XModule vtable: resolved=0x{x} (raw=0x{x})\n",
            .{ result.internal_targets.xmodule_vtable, raw_vtable orelse 0 },
        );
        machoCapturePrint(
            "macho-processor: SHA1 tracer init: enabled={} sha1_process_bytes=0x{x} sha1_range=0x{x}..0x{x} processBlock=0x{x}\n",
            .{
                result.sha1_tracer.enabled,
                result.internal_targets.sha1_process_bytes,
                result.internal_targets.sha1_start,
                result.internal_targets.sha1_end,
                sha1_process_block,
            },
        );
        if (result.metadata.sectionNamed("__TEXT", "__stub_helper")) |section| {
            result.stub_helper_start = section.address;
            result.stub_helper_end = section.address +| section.size;
        }
        // Resolve the narrowly targeted toml++ fast path once at load time.
        // Looking up a symbol for every guest instruction turns startup into a
        // full symbol-table scan hot loop.
        result.toml_ascii_entry = result.metadata.symbolAddressWithPrefix(
            "__ZN4toml2v34impl8is_asciiEPKcm",
        );
        result.toml_read_next_entry = result.metadata.symbolAddressWithPrefix(
            "__ZN4toml2v34impl11utf8_readerINSt3__113basic_istreamIcNS3_11char_traitsIcEEEEE9read_nextEv",
        );
        // P1-3 (perf audit): arm the SHA1 tracer here (not in loadAndRun) so
        // the init log below reflects the effective state. Default off;
        // ROSETTE_MACHO_SHA1_TRACE=1 enables it when a SHA1 hot-loop stall is
        // being diagnosed.
        result.sha1_tracer.enabled = environmentFlag("ROSETTE_MACHO_SHA1_TRACE");
        var defined_symbols = result.metadata.definedSymbolIterator();
        while (defined_symbols.next()) |entry| {
            if (!libcpp_stream_bridge.Bridge.recognizesSymbol(entry.key_ptr.*)) continue;
            const target: u64 = entry.value_ptr.*;
            try result.local_libcpp_stream_targets.put(target, entry.key_ptr.*);
            if (result.libcpp_stream_target_min == 0 or target < result.libcpp_stream_target_min) {
                result.libcpp_stream_target_min = target;
            }
            if (target > result.libcpp_stream_target_max) {
                result.libcpp_stream_target_max = target;
            }
        }
        result.logging.configure(
            result.internal_targets.guest_log_get_thread_buffer != 0,
            result.internal_targets.guest_log_append_formatted != 0,
            result.internal_targets.guest_log_append_view != 0,
        );
        result.unwinder.configure(&result.metadata);
        result.applyDyldBindings() catch |err| {
            log.warn("dyld data binding setup failed: {s}", .{@errorName(err)});
        };
        result.tlv.installDescriptors(&result);
        if (result.tlv.descriptor_count != 0) {
            result.registerSyntheticThunk(tlv_runtime.bootstrap_thunk, 16, "_tlv_bootstrap");
        }

        // R2 (N3): build the address-sorted special-RIP table now that every
        // load-time target (internal compatibility, toml fast path, cvar
        // launch-option vector) is resolved. A table is a pure index over the
        // same addresses the chain probes; failure falls back to probing every
        // instruction (pre-R2 behavior).
        result.buildSpecialRipTable() catch {
            result.special_rip_table_failed = true;
        };

        // Initialize the thread scheduler
        // result.thread_scheduler.init();

        return result;
    }

    fn dumpPrimitiveTotals(self: *MachOState) void {
        const log_cb = import_handler.PrimitiveLogCallbacks{
            .ctx = @ptrCast(&self.macho_log),
            .logLine = struct {
                fn log(_: *anyopaque, text: []const u8) void {
                    primitiveCapturePrint("{s}", .{text});
                }
            }.log,
        };
        self.import_handler.dumpTotals(log_cb);
    }

    pub fn deinit(self: *MachOState) void {
        self.execution_history.deinit(self.allocator);
        self.scheduler_log.close();
        self.jit_log.close();
        self.macho_log.close();
        self.guest_time.deinit(self.allocator);
        self.closeGuestFiles();
        self.libcxx_streams.deinit();
        self.dumpPrimitiveTotals();
        self.local_libcpp_stream_targets.deinit();
        self.import_handler.deinit();
        self.vtable_tracker.deinit();
        self.vtable_stack_registry.deinit();
        self.guard_rollback.deinit();
        self.import_resolver.deinit();
        self.initializer_resolver.deinit();
        self.vtt_resolver.deinit();
        self.dynamic_forwarder.deinit();
        self.native_window.deinit();
        self.fs_forwarder.deinit();
        self.memory_forwarder.deinit();
        self.sparse_memory.deinit();
        self.memory_regions.deinit();
        self.memory_writes.deinit(self.allocator);
        self.pointer_firewall.deinit();
        if (self.symbol_assembly_catalog) |*catalog| catalog.deinit();
        self.symbol_assembly.deinit();
        self.allocator.free(self.page_permissions);
        if (self.gpu_xenos_resolve_scratch.len != 0) self.allocator.free(self.gpu_xenos_resolve_scratch);
        if (self.gpu_xenos_edram.len != 0) self.allocator.free(self.gpu_xenos_edram);
        self.initializer_memory.deinit();
        self.allocator.free(self.decode_cache);
        self.allocator.destroy(self.decode_cache_pages);
        if (self.special_rip_table.len != 0) self.allocator.free(self.special_rip_table);
        if (self.guest_log_mirror_fd >= 0) _ = std.c.close(self.guest_log_mirror_fd);
        self.metadata.deinit();
        self.allocator.free(self.mem);
        self.allocator.free(self.segments);
        if (self.bound_import_thunks.len != 0) self.allocator.free(self.bound_import_thunks);

        // Shutdown the thread scheduler
        // self.thread_scheduler.shutdown();
    }

    pub fn scheduleGuestWaitDeadline(
        self: *MachOState,
        thread: u64,
        wait_object: u64,
        wait_generation: u64,
        deadline_ns: u64,
    ) u64 {
        return self.guest_time.schedule(self.allocator, deadline_ns, thread, wait_object, wait_generation) catch {
            self.scheduler_log.emit(.{
                .kind = .deadlock,
                .step = self.executed_steps,
                .thread = thread,
                .object = wait_object,
                .generation = wait_generation,
                .deadline_ns = deadline_ns,
                .reason = "deadline_registration_failed",
            });
            return 0;
        };
    }

    fn applyDyldBindings(self: *MachOState) !void {
        var stubs = std.StringHashMap(u64).init(self.allocator);
        defer stubs.deinit();
        for (self.metadata.imports) |imported| {
            try stubs.put(imported.name, imported.stub_address);
        }

        var thunk_addresses = std.StringHashMap(u64).init(self.allocator);
        defer thunk_addresses.deinit();
        var thunks: std.ArrayList(BoundImportThunk) = .empty;
        errdefer thunks.deinit(self.allocator);

        var applied: usize = 0;
        var callable_got_bindings: usize = 0;
        var writable_callable_bindings: usize = 0;
        var capstone_callback_bindings: usize = 0;
        var bridged_abi_data_bindings: usize = 0;
        var deferred_abi_data_bindings: usize = 0;
        var standard_stream_bindings: usize = 0;
        var local_image_data_bindings: usize = 0;
        var preserved_weak_data_bindings: usize = 0;
        var stack_guard_address: u64 = 0;
        for (self.metadata.bindings) |binding| {
            if (std.mem.eql(u8, binding.name, "___stdinp") or
                std.mem.eql(u8, binding.name, "___stdoutp") or
                std.mem.eql(u8, binding.name, "___stderrp"))
            {
                const pointer_address = self.standardStreamPointer(binding.name) orelse continue;
                if (self.guestMemory(binding.address, @sizeOf(u64)) == null) continue;
                self.write64(binding.address, pointer_address);
                applied += 1;
                continue;
            }
            if (std.mem.eql(u8, binding.name, "___stack_chk_guard")) {
                if (stack_guard_address == 0) {
                    stack_guard_address = self.guestAlloc(@sizeOf(u64), @alignOf(u64)) orelse continue;
                    self.write64(stack_guard_address, 0x9E37_79B9_7F4A_7C15);
                }
                if (self.guestMemory(binding.address, @sizeOf(u64)) == null) continue;
                self.write64(binding.address, stack_guard_address);
                applied += 1;
                continue;
            }
            if (standardCppStreamKind(binding.name)) |kind| {
                // std::cin/cout/cerr/clog are data symbols exported from
                // libc++. A plain dyld binding would have fallen through the
                // callable/ABI-data checks and left the slot zeroed, so
                // `std::cerr << ...` handed a null ostream to native libc++
                // code (the Xbyak near-null casualty). Bind the slot to a
                // fully modeled synthetic stream instead: every stream
                // operator that reaches native libc++ runs against valid
                // state, and every import the bridge intercepts dispatches
                // against the same object.
                const ostream = self.libcxx_streams.ensureStandardStream(self, kind) orelse {
                    machoCapturePrint(
                        "macho-processor: standard C++ stream construction failed for {s}\n",
                        .{binding.name},
                    );
                    continue;
                };
                if (self.guestMemory(binding.address, @sizeOf(u64)) == null) continue;
                self.write64(binding.address, ostream);
                applied += 1;
                standard_stream_bindings += 1;
                continue;
            }
            const section = self.metadata.sectionAtAddress(binding.address) orelse continue;
            if (isLocalBindingScope(binding.dylib)) {
                if (self.metadata.definedSymbolAddress(binding.name)) |defined_address| {
                    const target = applyBindingAddend(defined_address, binding.addend) orelse {
                        machoCapturePrint(
                            "macho-processor: rejected overflowing local-image binding addend: slot=0x{x} symbol={s} target=0x{x} addend={d}\n",
                            .{ binding.address, binding.name, defined_address, binding.addend },
                        );
                        continue;
                    };
                    const destination = self.guestMemory(binding.address, @sizeOf(u64)) orelse continue;
                    std.mem.writeInt(u64, destination[0..8], target, .little);
                    if (std.mem.eql(u8, section.name, "__got")) {
                        _ = self.memory_regions.register(binding.address, @sizeOf(u64), .{ .read = true, .write = true }, .import_got, binding.name, self.regs.rip);
                    }
                    applied += 1;
                    local_image_data_bindings += 1;
                    continue;
                }
            }
            if (std.mem.eql(u8, binding.dylib, "weak-lookup") and binding.addend == 0) {
                const destination = self.guestMemoryConst(binding.address, @sizeOf(u64)) orelse continue;
                const existing = std.mem.readInt(u64, destination[0..8], .little);
                if (existing != 0 and self.metadata.sectionAtAddress(existing) != null) {
                    applied += 1;
                    preserved_weak_data_bindings += 1;
                    continue;
                }
            }
            if (!isCallableConstantBinding(section, binding.name, stubs.contains(binding.name))) {
                if (isAbiDataSymbol(binding.name)) {
                    if (isBridgedLibcppDataSymbol(binding.name)) {
                        bridged_abi_data_bindings += 1;
                    } else {
                        deferred_abi_data_bindings += 1;
                        self.vtt_resolver.record(binding.address, binding.name, binding.addend) catch {};
                    }
                }
                continue;
            }
            const destination = self.guestMemory(binding.address, @sizeOf(u64)) orelse continue;
            const existing = std.mem.readInt(u64, destination[0..8], .little);
            if (std.mem.eql(u8, binding.dylib, "weak-lookup") and existing != 0) continue;
            const capstone_callback_slot = self.capstoneCallbackSlotName(binding.address);
            // Function pointers stored in writable runtime data don't pass
            // through a normal call-site lazy-binding sequence. Route them
            // through Rosette's direct bound thunks so callbacks such as
            // Capstone's allocator hooks deterministically enter the import
            // dispatcher with the original ABI arguments intact.
            const force_bound_thunk = bindingRequiresBoundThunk(section, capstone_callback_slot != null);
            var target = if (!force_bound_thunk) stubs.get(binding.name) orelse 0 else 0;
            if (target == 0) target = blk: {
                if (thunk_addresses.get(binding.name)) |existing_thunk| break :blk existing_thunk;
                const thunk_address = BOUND_IMPORT_THUNK_BASE + @as(u64, @intCast(thunks.items.len)) * self.metadata.importThunkStride();
                try thunks.append(self.allocator, .{
                    .address = thunk_address,
                    .name = binding.name,
                    .dylib = binding.dylib,
                });
                try thunk_addresses.put(binding.name, thunk_address);
                break :blk thunk_address;
            };
            if (target < BOUND_IMPORT_THUNK_BASE) {
                target = applyBindingAddend(target, binding.addend) orelse {
                    machoCapturePrint(
                        "macho-processor: rejected overflowing dyld binding addend: slot=0x{x} symbol={s} target=0x{x} addend={d}\n",
                        .{ binding.address, binding.name, target, binding.addend },
                    );
                    continue;
                };
            }
            std.mem.writeInt(u64, destination[0..8], target, .little);
            _ = self.memory_regions.register(binding.address, @sizeOf(u64), .{ .read = true, .write = true }, .import_got, binding.name, self.regs.rip);
            applied += 1;
            if (std.mem.eql(u8, section.name, "__got")) callable_got_bindings += 1;
            if (isWritableDataSection(section)) writable_callable_bindings += 1;
            if (capstone_callback_slot) |slot_name| {
                capstone_callback_bindings += 1;
                machoCapturePrint(
                    "macho-processor: Capstone runtime callback binding: slot={s} address=0x{x} import={s} target=0x{x} section={s} route=direct_bound_thunk repaired_null={}\n",
                    .{ slot_name, binding.address, binding.name, target, section.name, existing == 0 },
                );
            }
        }

        self.bound_import_thunks = try thunks.toOwnedSlice(self.allocator);
        for (self.bound_import_thunks) |thunk| {
            self.registerSyntheticThunk(thunk.address, self.metadata.importThunkStride(), thunk.name);
        }

        if (self.vtt_resolver.totalDeferred() > 0) {
            const resolved = blk: {
                var count: usize = 0;
                var synthetic_count: usize = 0;
                var sentinel_count: usize = 0;
                var sentinel_samples: usize = 0;
                var category_counts = [_]usize{0} ** std.enums.values(abi_data_materializer.Category).len;
                var synthetic_symbols = std.StringHashMap(u64).init(self.allocator);
                defer synthetic_symbols.deinit();
                for (self.vtt_resolver.deferred.items) |*item| {
                    if (item.resolution != .pending) continue;
                    const category = abi_data_materializer.classify(item.symbol);
                    if (category != .unknown) {
                        const base = synthetic_symbols.get(item.symbol) orelse materialized: {
                            const result = abi_data_materializer.materialize(self, item.symbol) orelse break :materialized 0;
                            synthetic_symbols.put(item.symbol, result.address) catch break :materialized 0;
                            category_counts[@intFromEnum(result.category)] += 1;
                            break :materialized result.address;
                        };
                        const value = if (base != 0) applyBindingAddend(base, item.addend) else null;
                        if (value) |target| {
                            self.write64(item.address, target);
                            item.resolution = .synthetic_abi;
                            synthetic_count += 1;
                            continue;
                        }
                    }
                    if (vtt_resolution.VttBindingResolver.lookupSymbol(item.symbol)) |base| {
                        const value = applyBindingAddend(base, item.addend) orelse base;
                        self.write64(item.address, value);
                        item.resolution = .host_symbol;
                        count += 1;
                    } else {
                        self.write64(item.address, item.address);
                        item.resolution = .self_sentinel;
                        sentinel_count += 1;
                        if (sentinel_samples < 8) {
                            machoCapturePrint(
                                "macho-processor: unresolved ABI data fallback sample: address=0x{x} symbol={s} action=self_sentinel host_lookup=missing\n",
                                .{ item.address, item.symbol },
                            );
                            sentinel_samples += 1;
                        }
                    }
                }
                if (synthetic_count > 0) {
                    machoCapturePrint(
                        "macho-processor: guest ABI data materialized: bindings={d} unique(typeinfo/type_name/vtable/construction_vtable/vtt/guard/reference_temporary)={d}/{d}/{d}/{d}/{d}/{d}/{d}; relocation addends preserved\n",
                        .{ synthetic_count, category_counts[@intFromEnum(abi_data_materializer.Category.typeinfo)], category_counts[@intFromEnum(abi_data_materializer.Category.type_name)], category_counts[@intFromEnum(abi_data_materializer.Category.vtable)], category_counts[@intFromEnum(abi_data_materializer.Category.construction_vtable)], category_counts[@intFromEnum(abi_data_materializer.Category.vtt)], category_counts[@intFromEnum(abi_data_materializer.Category.guard)], category_counts[@intFromEnum(abi_data_materializer.Category.reference_temporary)] },
                    );
                }
                if (sentinel_count > 0) {
                    machoCapturePrint(
                        "macho-processor: unresolved ABI data fallback summary: total={d} samples={d} suppressed={d} action=self_sentinel compatibility_only=true\n",
                        .{ sentinel_count, sentinel_samples, sentinel_count - sentinel_samples },
                    );
                }
                self.vtt_resolver.resolved_count = count;
                self.vtt_resolver.synthetic_count = synthetic_count;
                self.vtt_resolver.failed_count = sentinel_count;
                break :blk count;
            };
            if (self.vtt_resolver.synthetic_count > 0) {
                applied +|= self.vtt_resolver.synthetic_count;
            }
            if (resolved > 0) {
                applied +|= resolved;
                machoCapturePrint(
                    "macho-processor: resolved {d} deferred ABI data binding(s) via host symbol lookup\n",
                    .{resolved},
                );
            }
        }

        machoCapturePrint(
            "macho-processor: applied {d} dyld data binding(s), including {d} local-image pointer(s), {d} validated prebound weak pointer(s), {d} callable GOT pointer(s), {d} writable function pointer(s), and {d}/5 Capstone runtime callback(s); created {d} synthetic import thunk(s); ABI data bridged={d} deferred={d} guest_materialized={d} host_resolved={d} standard_cpp_streams={d}\n",
            .{ applied, local_image_data_bindings, preserved_weak_data_bindings, callable_got_bindings, writable_callable_bindings, capstone_callback_bindings, self.bound_import_thunks.len, bridged_abi_data_bindings, deferred_abi_data_bindings, self.vtt_resolver.synthetic_count, self.vtt_resolver.resolved_count, standard_stream_bindings },
        );
    }

    fn isLocalBindingScope(dylib: []const u8) bool {
        return std.mem.eql(u8, dylib, "self") or
            std.mem.eql(u8, dylib, "main-executable") or
            std.mem.eql(u8, dylib, "weak-lookup");
    }

    fn isCallableConstantBinding(
        section: macho_metadata.Section,
        symbol_name: []const u8,
        has_import_stub: bool,
    ) bool {
        // A dyld pointer binding for a symbol that also has an import stub is
        // a function pointer regardless of whether the compiler placed the
        // slot in __got, __const or writable __data. Capstone's cs_mem_* slots
        // are the important writable case: leaving them zero makes cs_open
        // return CS_ERR_MEMSETUP (8).
        if (has_import_stub) return true;
        if (std.mem.eql(u8, section.name, "__got")) return has_import_stub;
        if (!std.mem.eql(u8, section.name, "__const")) return false;
        if (!std.mem.startsWith(u8, symbol_name, "__Z")) return false;

        if (isAbiDataSymbol(symbol_name)) return false;
        return true;
    }

    fn isWritableDataSection(section: macho_metadata.Section) bool {
        return std.mem.eql(u8, section.segment_name, "__DATA") and
            !std.mem.eql(u8, section.name, "__got");
    }

    fn capstoneCallbackSlotName(self: *const MachOState, address: u64) ?[]const u8 {
        const slots = [_][]const u8{
            "_cs_mem_malloc",
            "_cs_mem_calloc",
            "_cs_mem_realloc",
            "_cs_mem_free",
            "_cs_vsnprintf",
        };
        for (slots) |slot| {
            if (self.metadata.definedSymbolAddress(slot) == address) return slot;
        }
        return null;
    }

    pub fn dumpCoopBootstrapTrace(self: *const MachOState) void {
        if (!self.coop_bootstrap_active or self.coop_bootstrap_index == 0) return;
        machoCapturePrint(
            "macho-processor: GTK worker bootstrap trace (incomplete, {d}/{d} entries):\n",
            .{ self.coop_bootstrap_index, 24 },
        );
        for (0..self.coop_bootstrap_index) |i| {
            const e = &self.coop_bootstrap_entries[i];
            const symbol = self.metadata.nearestSymbol(e.rip);
            const op_str = @tagName(@as(Op, @enumFromInt(e.op)));
            machoCapturePrint(
                "  [{d}] active=0x{x} rip=0x{x} {s}+0x{x} op={s} len={d}\n",
                .{
                    i,                                       e.thread,                        e.rip,
                    if (symbol) |s| s.name else "<unknown>", if (symbol) |s| s.offset else 0, op_str,
                    e.len,
                },
            );
        }
    }

    pub fn dumpMemInitTrace(self: *const MachOState) void {
        if (!self.mem_init_filled and self.mem_init_index == 0) return;
        const count: usize = if (self.mem_init_filled) 8 else self.mem_init_index;
        const start: usize = if (self.mem_init_filled) self.mem_init_index else 0;
        machoCapturePrint(
            "macho-processor: memory initialization progress (most recent {d} entries):\n",
            .{count},
        );
        for (0..count) |i| {
            const idx = (start + i) % 8;
            const e = &self.mem_init_entries[idx];
            const symbol = self.metadata.nearestSymbol(e.rip);
            machoCapturePrint(
                "  [{d}] step={d} rip=0x{x} {s}+0x{x} heap=0x{x} sparse(mappings/activations)={d}/{d} deferred={d} suspended={d}\n",
                .{
                    i,                                       e.step,                          e.rip,
                    if (symbol) |s| s.name else "<unknown>", if (symbol) |s| s.offset else 0, e.heap,
                    e.sparse_mappings,                       e.sparse_activations,            e.deferred_count,
                    e.suspended_count,
                },
            );
        }
    }

    pub fn dumpCapstoneCallbackState(self: *const MachOState, reason: []const u8) void {
        const slots = [_][]const u8{
            "_cs_mem_malloc",
            "_cs_mem_calloc",
            "_cs_mem_realloc",
            "_cs_mem_free",
            "_cs_vsnprintf",
        };
        var present: usize = 0;
        var nonzero: usize = 0;
        machoCapturePrint("  Capstone runtime callback state ({s}):\n", .{reason});
        for (slots) |slot| {
            const address = self.metadata.definedSymbolAddress(slot) orelse {
                machoCapturePrint("    {s}: symbol_missing\n", .{slot});
                continue;
            };
            present += 1;
            const target = self.read64(address);
            if (target != 0) nonzero += 1;
            if (self.metadata.importAtStub(target)) |imported| {
                machoCapturePrint("    {s}: address=0x{x} target=0x{x} import={s}@{s}\n", .{ slot, address, target, imported.name, imported.dylib });
            } else if (self.metadata.nearestSymbol(target)) |symbol| {
                machoCapturePrint("    {s}: address=0x{x} target=0x{x} symbol={s}+0x{x}\n", .{ slot, address, target, symbol.name, symbol.offset });
            } else {
                machoCapturePrint("    {s}: address=0x{x} target=0x{x} unresolved={}\n", .{ slot, address, target, target != 0 });
            }
        }
        machoCapturePrint("    summary: symbols={d}/5 nonzero={d}/5 cs_open_requires_all_nonzero=true\n", .{ present, nonzero });
    }

    fn isAbiDataSymbol(symbol_name: []const u8) bool {
        const prefixes = [_][]const u8{ "__ZGV", "__ZGR", "__ZTC", "__ZTI", "__ZTS", "__ZTT", "__ZTV" };
        for (prefixes) |prefix| {
            if (std.mem.startsWith(u8, symbol_name, prefix)) return true;
        }
        return false;
    }

    /// Map a libc++ standard stream data symbol to its modeled stream kind.
    /// libc++ exports these as `_ZNSt3__14cerrE` (namespace std, 4-char name,
    /// data) — the Mach-O external form adds one leading underscore. Verified
    /// against the Xenia fork's undefined-symbol table: `__ZNSt3__14cerrE`,
    /// `__ZNSt3__14clogE`, `__ZNSt3__14coutE`.
    fn standardCppStreamKind(symbol_name: []const u8) ?libcpp_stream_bridge.StandardStreamKind {
        if (std.mem.eql(u8, symbol_name, "__ZNSt3__14cinE")) return .cin;
        if (std.mem.eql(u8, symbol_name, "__ZNSt3__14coutE")) return .cout;
        if (std.mem.eql(u8, symbol_name, "__ZNSt3__14cerrE")) return .cerr;
        if (std.mem.eql(u8, symbol_name, "__ZNSt3__14clogE")) return .clog;
        return null;
    }

    fn isBridgedLibcppDataSymbol(symbol_name: []const u8) bool {
        if (!isAbiDataSymbol(symbol_name)) return false;
        return std.mem.indexOf(u8, symbol_name, "basic_ifstream") != null or
            std.mem.indexOf(u8, symbol_name, "basic_istream") != null or
            std.mem.indexOf(u8, symbol_name, "basic_filebuf") != null or
            std.mem.indexOf(u8, symbol_name, "basic_ios") != null or
            std.mem.indexOf(u8, symbol_name, "ios_base") != null;
    }

    fn bindingRequiresBoundThunk(section: macho_metadata.Section, is_runtime_callback: bool) bool {
        return is_runtime_callback or std.mem.eql(u8, section.name, "__got");
    }

    pub const addrToOffset = memory_access.addrToOffset;
    pub const setPagePermissions = memory_access.setPagePermissions;
    const translateGuest = memory_access.translateGuest;
    const describeGuestAccess = memory_access.describeGuestAccess;
    pub const isExecutableAddress = memory_access.isExecutableAddress;
    pub const diagnosticSymbol = memory_access.diagnosticSymbol;
    const ms = memory_access.ms;
    pub const read8 = memory_access.read8;
    pub const read16 = memory_access.read16;
    pub const read32 = memory_access.read32;
    pub const read64 = memory_access.read64;
    pub const write8 = memory_access.write8;
    pub const write16 = memory_access.write16;
    pub const write32 = memory_access.write32;
    pub const write64 = memory_access.write64;
    pub const push = memory_access.push;
    pub const pop = memory_access.pop;
    pub const readMemVal = memory_access.readMemVal;
    const recoverLiveAllocationVtable = memory_access.recoverLiveAllocationVtable;
    const logLiveVtableGuardSummary = memory_access.logLiveVtableGuardSummary;
    pub const hasLiveAllocationVtableHistory = memory_access.hasLiveAllocationVtableHistory;
    const vtableIdentityEvidence = memory_access.vtableIdentityEvidence;
    const recordAllocationWrite = memory_access.recordAllocationWrite;
    const isAddressInMappedMemory = memory_access.isAddressInMappedMemory;
    const classifyWriterRipOffset = memory_access.classifyWriterRipOffset;
    const detectFunctionProloguePtr = memory_access.detectFunctionProloguePtr;
    const dumpHeapCorruptionDiagnostics = memory_access.dumpHeapCorruptionDiagnostics;
    const timerQueueWatchWrite = memory_access.timerQueueWatchWrite;
    pub const writeMemVal = memory_access.writeMemVal;
    pub const recordEndianEvidence = memory_access.recordEndianEvidence;
    pub const tryRepairGeneratedEndianBeforeDispatch = memory_access.tryRepairGeneratedEndianBeforeDispatch;
    pub const captureMemoryMutation = memory_access.captureMemoryMutation;
    pub const commitMemoryMutation = memory_access.commitMemoryMutation;
    const deferInitializerRuntimeDependency = memory_access.deferInitializerRuntimeDependency;
    pub const decodeWithSnapshotOperands = memory_access.decodeWithSnapshotOperands;
    const ensureGuestAccess = memory_access.ensureGuestAccess;
    pub const terminateForGuestAccess = memory_access.terminateForGuestAccess;
    const dumpStepTraceBuffer = memory_access.dumpStepTraceBuffer;
    const currentGuestInstructionLength = memory_access.currentGuestInstructionLength;
    const tryQuarantineOpaqueDestructor = memory_access.tryQuarantineOpaqueDestructor;
    const dumpTerminalAddressProvenance = memory_access.dumpTerminalAddressProvenance;
    const dumpNearNullProducerSlot = memory_access.dumpNearNullProducerSlot;
    const dumpRegisterTransition = memory_access.dumpRegisterTransition;
    const traceRegisterValue = memory_access.traceRegisterValue;
    const recordMemoryAccess = memory_access.recordMemoryAccess;
    pub const readMem128 = memory_access.readMem128;
    pub const writeMem128 = memory_access.writeMem128;
    pub const guestMemory = memory_access.guestMemory;
    pub const writeGuestBytes = memory_access.writeGuestBytes;
    pub const fillGuestMemory = memory_access.fillGuestMemory;
    /// Bulk import routes (memcpy/memset/bzero/strcpy) write guest memory
    /// directly through `guestMemory`, so they must announce the write for
    /// decode-cache invalidation and vtable ownership exactly as a scalar
    /// store does.
    pub const noteGuestWrite = memory_access.noteGuestWrite;
    pub const guestMemoryConst = memory_access.guestMemoryConst;
    pub const guestAlloc = memory_access.guestAlloc;
    pub const registerSyntheticRegion = memory_access.registerSyntheticRegion;
    pub const registerOpaqueHandle = memory_access.registerOpaqueHandle;
    pub const registerOpaqueApiHandle = memory_access.registerOpaqueApiHandle;
    pub const registerSyntheticThunk = memory_access.registerSyntheticThunk;
    pub const guestHeapAllocate = memory_access.guestHeapAllocate;
    pub const guestHeapRelease = memory_access.guestHeapRelease;
    pub const guestHeapContains = memory_access.guestHeapContains;
    pub const forgetMemoryWriteProvenance = memory_access.forgetMemoryWriteProvenance;
    pub const guestMapFile = memory_access.guestMapFile;
    pub const guestMapHinted = memory_access.guestMapHinted;
    pub const guestMapAnywhereWithBacking = memory_access.guestMapAnywhereWithBacking;
    pub const guestMapBackendWithBacking = memory_access.guestMapBackendWithBacking;
    pub const guestReserveAddressSpace = memory_access.guestReserveAddressSpace;
    pub const guestReserveAddressSpaceWithBacking = memory_access.guestReserveAddressSpaceWithBacking;
    pub const guestUnmapFile = memory_access.guestUnmapFile;
    pub const guestProtectSparseMemory = memory_access.guestProtectSparseMemory;
    pub const guestProtectMappedMemory = memory_access.guestProtectMappedMemory;
    pub const renderProcSelfMaps = memory_access.renderProcSelfMaps;
    pub const guestCString = memory_access.guestCString;
    pub const cxxExceptionTypeName = memory_access.cxxExceptionTypeName;
    pub const cxxExceptionMessage = memory_access.cxxExceptionMessage;
    pub const guestWriteCString = memory_access.guestWriteCString;
    pub fn registerNativeWindowHandles(self: *MachOState) void {
        return native_window.registerNativeWindowHandles(self);
    }
    pub fn ensureNativeApplication(self: *MachOState) bool {
        return native_window.ensureNativeApplication(self);
    }
    pub fn ensureNativeWindow(self: *MachOState) bool {
        return native_window.ensureNativeWindow(self);
    }
    pub fn setNativeWindowTitle(self: *MachOState, title: []const u8) bool {
        return native_window.setNativeWindowTitle(self, title);
    }
    pub fn setNativeWindowSize(self: *MachOState, width: i32, height: i32) bool {
        return native_window.setNativeWindowSize(self, width, height);
    }
    pub fn showNativeWindow(self: *MachOState) bool {
        return native_window.showNativeWindow(self);
    }
    pub fn setNativeWindowFullscreen(self: *MachOState, fullscreen: bool) bool {
        return native_window.setNativeWindowFullscreen(self, fullscreen);
    }
    pub fn nativeViewToken(self: *MachOState) u64 {
        return native_window.nativeViewToken(self);
    }
    pub fn nativeWindowWidth(self: *MachOState) u32 {
        return native_window.nativeWindowWidth(self);
    }
    pub fn nativeWindowHeight(self: *MachOState) u32 {
        return native_window.nativeWindowHeight(self);
    }
    pub fn validateNativeMetalLayerToken(self: *MachOState, token: u64) bool {
        return native_window.validateNativeMetalLayerToken(self, token);
    }
    pub fn nativeMetalLayerHostPointer(self: *MachOState) usize {
        return native_window.nativeMetalLayerHostPointer(self);
    }
    pub fn noteNativeVulkanSurfaceBound(self: *MachOState, layer_token: u64, guest_surface: u64, host_surface: u64) void {
        return native_window.noteNativeVulkanSurfaceBound(self, layer_token, guest_surface, host_surface);
    }
    pub fn presentNativeDiagnosticFrame(
        self: *MachOState,
        serial: u64,
        width: u32,
        height: u32,
        stage: u32,
    ) bool {
        return native_window.presentNativeDiagnosticFrame(self, serial, width, height, stage);
    }
    pub fn pumpNativeWindowEvents(self: *MachOState) void {
        return native_window.pumpNativeWindowEvents(self);
    }

    /// Arm execution tracepoints on the emulator's own graphics entry points.
    ///
    /// The question "did the title call `VdSwap`" has been answered from a
    /// mirrored log string, which cannot distinguish a call that never happened
    /// from one that logged differently, was filtered, or took another route.
    /// Rosette is the interpreter, so it can answer from the instruction
    /// pointer instead — but only if it knows the address, which is what this
    /// resolves from the emulator's own symbol table.
    ///
    /// `_entry` suffixed names are preferred because that is the shim the
    /// export dispatch actually calls; a lambda or thunk sharing the fragment
    /// would be a less direct boundary.
    pub fn armGraphicsTracepoints(self: *MachOState) void {
        const wanted = [_]struct { fragment: []const u8, role: execution_tracepoints.Role }{
            .{ .fragment = "VdSwap_entry", .role = .swap },
            .{ .fragment = "NotifyVdSwapCall", .role = .swap },
            .{ .fragment = "IssueSwap", .role = .command_swap },
            .{ .fragment = "ExecutePacketType3_XE_SWAP", .role = .xe_swap_decode },
            .{ .fragment = "DebugIssueSwapFromHost", .role = .diagnostic_swap },
            .{ .fragment = "VdInitializeRingBuffer_entry", .role = .ring_publication },
            .{ .fragment = "VdEnableRingBufferRPtrWriteBack_entry", .role = .ring_publication },
            .{ .fragment = "ExecutePrimaryBuffer", .role = .command_processor },
            .{ .fragment = "RefreshGuestOutput", .role = .presenter },
        };
        // Every executable candidate is armed, but ranked before the cap
        // applies. Taking the first four in hash order armed only the standard
        // library's closure machinery for `IssueSwap` — the allocator, the
        // compressed pair, `unique_ptr::get`, `__alloc_func::destroy` — and
        // never `VulkanCommandProcessor::IssueSwap` itself, so the role
        // reported NEVER ENTERED for a function nothing was watching.
        //
        // Ranking by mangled-name length separates them reliably: a real
        // method's name is short, and a template instantiation that merely
        // mentions it carries the whole enclosing type. Keeping four still
        // covers a virtual and its overrides.
        const per_fragment: usize = 4;
        for (wanted) |target| {
            var best_name: [per_fragment][]const u8 = [_][]const u8{""} ** per_fragment;
            var best_address: [per_fragment]u64 = [_]u64{0} ** per_fragment;
            var matches: u32 = 0;
            var rejected_non_executable: u32 = 0;
            var iterator = self.metadata.definedSymbolIterator();
            while (iterator.next()) |symbol| {
                const name = symbol.key_ptr.*;
                if (std.mem.indexOf(u8, name, target.fragment) == null) continue;
                // `DebugIssueSwapFromHost` contains `IssueSwap`, but it is a
                // different provenance boundary. Without this exclusion a
                // forced host probe is armed twice and can be misreported as
                // authentic guest progress.
                if (target.role == .command_swap and
                    std.mem.indexOf(u8, name, "DebugIssueSwapFromHost") != null)
                {
                    continue;
                }
                const address = symbol.value_ptr.*;
                matches += 1;
                // A guard variable or a static inside the function carries the
                // same fragment and is never executed, so a tracepoint there
                // would report "never entered" forever.
                if (address < self.executable_min or address >= self.executable_max) {
                    rejected_non_executable += 1;
                    continue;
                }
                var candidate_name = name;
                var candidate_address = address;
                var slot: usize = 0;
                while (slot < per_fragment) : (slot += 1) {
                    if (best_address[slot] == 0) {
                        best_name[slot] = candidate_name;
                        best_address[slot] = candidate_address;
                        break;
                    }
                    if (candidate_name.len >= best_name[slot].len) continue;
                    const displaced_name = best_name[slot];
                    const displaced_address = best_address[slot];
                    best_name[slot] = candidate_name;
                    best_address[slot] = candidate_address;
                    candidate_name = displaced_name;
                    candidate_address = displaced_address;
                }
            }
            var armed: usize = 0;
            for (best_name, best_address) |name, address| {
                if (address == 0) continue;
                if (self.execution_tracepoints.arm(name, address, target.role)) {
                    armed += 1;
                    machoCapturePrint(
                        "macho-processor: graphics tracepoint armed: role={s} ({s}) address=0x{x} candidates={d} symbol={s}\n",
                        .{ @tagName(target.role), target.role.label(), address, matches, name },
                    );
                }
            }
            if (armed == 0) {
                self.execution_tracepoints.noteUnresolved();
                machoCapturePrint(
                    "macho-processor: graphics tracepoint UNRESOLVED: fragment={s} role={s} name_matches={d} rejected_non_executable={d}; a zero hit count for this role will mean nothing was watching, NOT that it never ran\n",
                    .{ target.fragment, @tagName(target.role), matches, rejected_non_executable },
                );
            }
        }
        self.execution_tracepoints.seal();
        machoCapturePrint(
            "macho-processor: graphics tracepoints sealed: armed={d} unresolved={d} range=0x{x}..0x{x} executable=0x{x}..0x{x}; whether VdSwap executes is now read from the instruction pointer rather than inferred from a log line\n",
            .{
                self.execution_tracepoints.count,
                self.execution_tracepoints.unresolved,
                self.execution_tracepoints.low,
                self.execution_tracepoints.high,
                self.executable_min,
                self.executable_max,
            },
        );
    }

    /// The instruction pointer reached an armed boundary. Only the first entry
    /// is reported: the rest are a frame rate, and the first is the fact the
    /// investigation has been missing.
    noinline fn noteExecutionTracepoint(self: *MachOState) void {
        // At a function's entry instruction the return address is still on top
        // of the stack, so the caller is knowable without unwinding.
        const caller = self.read64(self.regs.rsp);
        const hit = self.execution_tracepoints.observe(
            self.regs.rip,
            self.executed_steps,
            self.active_guest_thread,
            caller,
        ) orelse return;
        self.ready.noteEntered(hit.address, self.executed_steps, self.active_guest_thread, caller);
        if (self.ready.enabled()) {
            machoCapturePrint(
                "macho-processor: READY COMPILER: function-enter role={s} name={s} address=0x{x} step={d} thread=0x{x} caller=0x{x}\n",
                .{ @tagName(hit.role), hit.name, hit.address, self.executed_steps, self.active_guest_thread, caller },
            );
        }
        const identity = self.event_stream.next(
            .execution_boundary,
            self.executed_steps,
            self.active_guest_thread,
            0,
            caller,
        ) orelse return;
        const caller_symbol = self.metadata.nearestSymbol(caller);
        machoCapturePrint(
            "macho-processor: EXECUTION BOUNDARY ENTERED: run=0x{x} seq={d} role={s} symbol={s} address=0x{x} step={d} guest_thread=0x{x} caller=0x{x} caller_symbol={s}+0x{x}\n",
            .{
                identity.run_id,
                identity.sequence,
                @tagName(hit.role),
                hit.name,
                hit.address,
                identity.guest_step,
                identity.guest_thread,
                caller,
                if (caller_symbol) |resolved| resolved.name else "<unknown>",
                if (caller_symbol) |resolved| resolved.offset else 0,
            },
        );
    }

    /// Configure the runtime analogue of the Xenia build graph after command
    /// line compatibility options have been applied. The gate is only active
    /// for Xenia targets unless the caller explicitly forces it through the
    /// environment; ordinary Mach-O applications keep the generic loader
    /// behaviour they had before this contract existed.
    pub fn configureReadyCompiler(
        self: *MachOState,
        enabled: bool,
        enforce: bool,
        activation_budget_steps: u64,
        quiet_budget_steps: u64,
        decoder_ready: bool,
    ) void {
        if (!enabled or !self.has_xenia_compat) {
            self.ready.disable();
            machoCapturePrint(
                "macho-processor: READY COMPILER: disabled xenia_compat={} requested={}\n",
                .{ self.has_xenia_compat, enabled },
            );
            return;
        }

        var runtime_contract = ready_compiler.xenia.contract();
        if (activation_budget_steps != 0) runtime_contract.activation_budget_steps = activation_budget_steps;
        if (quiet_budget_steps != 0) runtime_contract.quiet_budget_steps = quiet_budget_steps;
        self.ready.configure(runtime_contract, enforce);
        self.ready.beginCompile(self.executed_steps);

        const image_ready = self.entry_point_vaddr != 0 and self.segments.len != 0;
        self.ready.noteCompileCheck(
            "mach-o-image",
            image_ready,
            if (image_ready) "mapped executable image has an entry point" else "image has no executable entry point",
        );
        machoCapturePrint(
            "macho-processor: READY COMPILER: compile-check name=mach-o-image passed={} detail={s}\n",
            .{ image_ready, if (image_ready) "mapped executable image has an entry point" else "image has no executable entry point" },
        );
        self.ready.noteCompileCheck(
            "decoder-audit",
            decoder_ready,
            if (decoder_ready) "baseline VEX decoder audit passed" else "baseline VEX decoder audit failed",
        );
        machoCapturePrint(
            "macho-processor: READY COMPILER: compile-check name=decoder-audit passed={} detail={s}\n",
            .{ decoder_ready, if (decoder_ready) "baseline VEX decoder audit passed" else "baseline VEX decoder audit failed" },
        );
        _ = self.ready.noteStage(
            @intFromEnum(ready_compiler.xenia.Stage.image_ready),
            self.executed_steps,
            "rosette:image_loaded",
        );
        machoCapturePrint(
            "macho-processor: READY COMPILER: configured contract={s} enforce={} activation_budget={d} activation_budget_mode={s} quiet_budget={d}; compile checks are now separate from activation evidence\n",
            .{ runtime_contract.name, enforce, runtime_contract.activation_budget_steps, self.ready.activationBudgetMode(), runtime_contract.quiet_budget_steps },
        );
    }

    /// Seal Rosette's build-style phase and begin the guest/Xenia activation
    /// phase. This is called only after pre-main initialization has completed,
    /// so an initializer failure cannot be mislabeled as a gameplay failure.
    pub fn sealReadyCompilerCompile(self: *MachOState) bool {
        if (!self.ready.enabled()) return true;
        self.ready.noteCompileCheck(
            "static-initializers",
            true,
            "pre-main initializer transaction completed",
        );
        machoCapturePrint(
            "macho-processor: READY COMPILER: compile-check name=static-initializers passed=true detail=pre-main initializer transaction completed\n",
            .{},
        );
        if (!self.ready.sealCompile(self.executed_steps)) {
            self.logReadyCompilerFailure();
            return false;
        }
        _ = self.ready.noteStage(
            @intFromEnum(ready_compiler.xenia.Stage.compile_ready),
            self.executed_steps,
            "rosette:compile_checks",
        );
        _ = self.ready.noteStage(
            @intFromEnum(ready_compiler.xenia.Stage.static_initializers_complete),
            self.executed_steps,
            "rosette:static_initializers",
        );
        machoCapturePrint(
            "macho-processor: READY COMPILER: compile phase GREEN; activation phase opened at step={d}; the guest application is not ready until authentic native presentation\n",
            .{self.executed_steps},
        );
        machoCapturePrint(
            "macho-processor: READY COMPILER: activation phase OPEN compile_checks={d} dropped={d}\n",
            .{ self.ready.compile_check_count, self.ready.compile_checks_dropped },
        );
        return true;
    }

    /// Map the existing Xenia pipeline observer into the generic contract.
    /// The process-core observer calls this without importing Xenia-specific
    /// types, which keeps the observer usable by other Mach-O targets.
    pub fn noteReadyCompilerPipelineStage(self: *MachOState, raw_stage: u8, at_step: u64) void {
        if (!self.ready.enabled()) return;
        const stage = ready_compiler.xenia.pipelineStage(raw_stage) orelse {
            machoCapturePrint(
                "macho-processor: READY COMPILER: invalid pipeline stage raw={d} step={d}; no contract stage can consume this evidence\n",
                .{ raw_stage, at_step },
            );
            return;
        };
        const accepted = self.ready.noteStage(@intFromEnum(stage), at_step, "xenia:pipeline");
        self.logReadyCompilerStage(stage, accepted, at_step, "xenia:pipeline");
    }

    pub fn noteReadyCompilerGpuPhase(self: *MachOState, raw_phase: u8, at_step: u64) void {
        if (!self.ready.enabled()) return;
        const stage = ready_compiler.xenia.handoffPhase(raw_phase) orelse {
            machoCapturePrint(
                "macho-processor: READY COMPILER: invalid GPU handoff phase raw={d} step={d}; no contract stage can consume this evidence\n",
                .{ raw_phase, at_step },
            );
            return;
        };
        const accepted = self.ready.noteStage(@intFromEnum(stage), at_step, "xenia:gpu_handoff");
        self.logReadyCompilerStage(stage, accepted, at_step, "xenia:gpu_handoff");
    }

    pub fn noteReadyCompilerWait(self: *MachOState, object: u64, signaled: bool, at_step: u64) void {
        if (!self.ready.enabled()) return;
        const was_pending = self.ready.pending_wait_object == object;
        self.ready.noteWait(object, signaled, at_step);
        if (!signaled or was_pending) {
            machoCapturePrint(
                "macho-processor: READY COMPILER: wait object=0x{x} signaled={} step={d} pending=0x{x} timeout_count={d} signal_count={d}\n",
                .{
                    object,
                    signaled,
                    at_step,
                    self.ready.pending_wait_object,
                    self.ready.wait_timeout_count,
                    self.ready.wait_signal_count,
                },
            );
        }
    }

    pub fn observeReadyCompilerText(self: *MachOState, line: []const u8) void {
        if (!self.ready.enabled()) return;
        if (ready_compiler.xenia.translationProgressFromText(line)) |event| {
            if (self.ready.noteTranslationProgress(event.generation, self.executed_steps)) {
                machoCapturePrint(
                    "macho-processor: READY COMPILER: translation-progress accepted generation={d} guest_function=0x{x} step={d}\n",
                    .{ event.generation, event.guest_function, self.executed_steps },
                );
            }
        }
        // These boundaries are finer than the legacy Xenia pipeline stages.
        // Observe them before the generic guest-log observers consume the same
        // line so `user_module_ready` cannot hide the precompile return or make
        // a never-entered shader request look like a failed shader backend.
        if (ready_compiler.xenia.workUnitStage(line)) |stage| {
            const stage_bit = @as(u64, 1) << @as(u6, @intCast(@intFromEnum(stage)));
            const already_reached = self.ready.reached_mask & stage_bit != 0;
            const accepted = self.ready.noteStage(@intFromEnum(stage), self.executed_steps, "xenia:work_unit");
            if (!already_reached) self.logReadyCompilerStage(stage, accepted, self.executed_steps, "xenia:work_unit");
        }
        if (ready_compiler.Runtime.compilerDiagnosticKind(line)) |kind| {
            machoCapturePrint(
                "macho-processor: READY COMPILER: compiler-diagnostic kind={s} step={d} rip=0x{x} thread=0x{x} text={s}\n",
                .{ kind.label(), self.executed_steps, self.regs.rip, self.active_guest_thread, line },
            );
        }
        self.ready.observeCompilerText(line, self.executed_steps, self.regs.rip, self.active_guest_thread);
    }

    fn logReadyCompilerStage(
        self: *MachOState,
        stage: ready_compiler.xenia.Stage,
        accepted: bool,
        at_step: u64,
        source: []const u8,
    ) void {
        const spec = self.ready.stage(@intFromEnum(stage)) orelse return;
        const missing_prerequisites = spec.prerequisites & ~self.ready.reached_mask;
        const next_missing = self.ready.firstMissingRequired();
        machoCapturePrint(
            "macho-processor: READY COMPILER: stage name={s} id={d} accepted={} required={} owner={s} step={d} elapsed_steps={d} prerequisites=0x{x} missing_prerequisites=0x{x} reached=0x{x} next={s} next_owner={s} source={s}\n",
            .{
                spec.name,
                spec.id,
                accepted,
                spec.required,
                if (spec.owner.len != 0) spec.owner else "<unattributed>",
                at_step,
                self.ready.stage_duration[@intCast(spec.id)],
                spec.prerequisites,
                missing_prerequisites,
                self.ready.reached_mask,
                if (next_missing) |next| next.name else "<complete>",
                if (next_missing) |next|
                    (if (next.owner.len != 0) next.owner else "<unattributed>")
                else
                    "<none>",
                source,
            },
        );
        self.logReadyCompilerProgress();
        if (!accepted and self.ready.failure.kind != .none) self.logReadyCompilerFailure();
    }

    /// The contract as an ordered block sequence, the way a build log reads.
    /// Emitted on every accepted edge so the runtime phase has the same
    /// at-a-glance progression the build phase already has.
    fn logReadyCompilerProgress(self: *const MachOState) void {
        if (!self.ready.enabled()) return;
        const progress = self.ready.contractProgress();
        const next = self.ready.firstMissingRequired();
        machoCapturePrint(
            "macho-processor: READY COMPILER: CONTRACT PROGRESS block={d}/{d} required={d}/{d} edges={d}/{d} next={s} next_owner={s} next_detail={s}\n",
            .{
                progress.current_block,
                progress.required_total,
                progress.required_reached,
                progress.required_total,
                progress.reached,
                progress.total,
                if (next) |spec| spec.name else "<complete>",
                if (next) |spec|
                    (if (spec.owner.len != 0) spec.owner else "<unattributed>")
                else
                    "<none>",
                if (next) |spec| spec.description else "every required edge reached",
            },
        );
    }

    /// Evaluate only at heartbeats. The semantic contract is not allowed to
    /// add a per-instruction search to the interpreter's hot loop.
    noinline fn pollReadyCompiler(self: *MachOState, at_step: u64) void {
        if (!self.ready.enabled() or self.ready.phase == .ready) return;
        const wait_object = self.pthreads.worstWaitObject(at_step);
        self.ready.noteSchedulingEvidence(
            self.pthreads.activeCount(),
            self.pthreads.blocked_threads,
            if (wait_object) |object| object.address else 0,
            if (wait_object) |object| object.notifications else 0,
            if (wait_object) |object| object.first_wait_step else 0,
            if (wait_object) |object| object.last_notify_step else 0,
            at_step,
        );
        self.ready.noteProgress(at_step, self.regs.rip, self.active_guest_thread, "heartbeat");
        // A startup step that runs past one quiet budget while still reporting
        // named work is slow, not stuck. Saying so out loud keeps the long
        // stages visible without letting them end the run.
        if (self.ready.takeSlowProgressNotice(at_step)) {
            const symbol = self.metadata.nearestSymbol(self.regs.rip);
            machoCapturePrint(
                "macho-processor: READY COMPILER: SLOW BUT PROGRESSING stage={s} owner={s} last_named_work={s} work_owner={s} work_thread=0x{x} work_rip=0x{x} at_step={d} step={d} milestone_quiet_steps={d} quiet_budget={d} rip=0x{x} {s}+0x{x} notice={d}\n",
                .{
                    if (self.ready.firstMissingRequired()) |spec| spec.name else "<none>",
                    if (self.ready.firstMissingRequired()) |spec|
                        (if (spec.owner.len != 0) spec.owner else "<unattributed>")
                    else
                        "<none>",
                    self.ready.workUnitName(),
                    if (self.ready.work_unit.ownerSlice().len != 0) self.ready.work_unit.ownerSlice() else "<unknown>",
                    self.ready.work_unit.thread,
                    self.ready.work_unit.rip,
                    self.ready.work_unit.step,
                    at_step,
                    at_step -| self.ready.last_milestone_step,
                    if (self.ready.contract) |active| active.quiet_budget_steps else 0,
                    self.regs.rip,
                    if (symbol) |resolved| resolved.name else "<unknown>",
                    if (symbol) |resolved| resolved.offset else 0,
                    self.ready.slow_progress_reports,
                },
            );
        }
        const evaluation = self.ready.evaluate(at_step);
        if ((evaluation == .failed and self.ready.last_reported_phase == .failed) or
            (evaluation != .failed and self.ready.last_reported_phase == self.ready.phase)) return;
        self.ready.last_reported_phase = self.ready.phase;
        switch (evaluation) {
            .waiting => {},
            .ready => machoCapturePrint(
                "macho-processor: READY COMPILER: GREEN application-ready contract={s} step={d}; terminal=authentic_native_presented activation_polling=closed authentic native presentation is now proven\n",
                .{ self.ready.contract.?.name, at_step },
            ),
            .failed => {
                self.logReadyCompilerFailure();
                if (self.ready.enforce and !self.terminated) {
                    self.faulted = true;
                    self.exit_code = 125;
                    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.runtime_invariant_failure);
                    self.terminated = true;
                    machoCapturePrint(
                        "macho-processor: READY COMPILER: strict gate stopped execution before application readiness; no gameplay result is valid\n",
                        .{},
                    );
                }
            },
        }
    }

    fn logReadyCompilerFailure(self: *const MachOState) void {
        const failure = self.ready.failure;
        machoCapturePrint(
            "macho-processor: READY COMPILER: BLOCKED kind={s} stage={s} function={s} step={d} rip=0x{x} thread=0x{x} object=0x{x} missing_prerequisites=0x{x} compiler_diagnostics={d} waits(timeout/signaled)={d}/{d} expected={s} observed={s} reason={s}\n",
            .{
                failure.kind.label(),
                if (failure.stage.len != 0) failure.stage else "<none>",
                if (failure.function.len != 0) failure.function else "<none>",
                failure.step,
                failure.rip,
                failure.thread,
                failure.object,
                failure.missing_prerequisites,
                self.ready.compiler_diagnostic_count,
                self.ready.wait_timeout_count,
                self.ready.wait_signal_count,
                if (failure.expected.len != 0) failure.expected else "<none>",
                if (failure.observed.len != 0) failure.observed else "<none>",
                if (failure.reason.len != 0) failure.reason else "<none>",
            },
        );
        self.logReadyCompilerDiagnosis();
    }

    /// The evidence behind the verdict.
    ///
    /// A blocked line alone says that startup stopped; it does not say which
    /// axis froze, who owed the missing edge, what the guest was last observed
    /// doing, or where it spent the quiet window. Those four facts are what
    /// turn a stall report into an investigation, so they are emitted together
    /// and derived from one snapshot to keep them consistent.
    fn logReadyCompilerDiagnosis(self: *const MachOState) void {
        if (!self.ready.enabled()) return;
        const diagnosis = self.ready.diagnose(self.executed_steps);
        machoCapturePrint(
            "macho-processor: READY COMPILER: DIAGNOSIS progress={s} blockage={s} missing={s} owner={s} description={s} frontier={s}@{d} stall_steps={d} quiet_budget={d} activation_steps={d}/{d} activation_budget_mode={s}\n",
            .{
                diagnosis.progress.label(),
                diagnosis.blockage.label(),
                if (diagnosis.missing_stage.len != 0) diagnosis.missing_stage else "<none>",
                if (diagnosis.missing_owner.len != 0) diagnosis.missing_owner else "<unattributed>",
                if (diagnosis.missing_description.len != 0) diagnosis.missing_description else "<none>",
                if (diagnosis.frontier_stage.len != 0) diagnosis.frontier_stage else "<none>",
                diagnosis.frontier_step,
                diagnosis.quiet_steps,
                diagnosis.quiet_budget_steps,
                diagnosis.activation_steps,
                diagnosis.activation_budget_steps,
                self.ready.activationBudgetMode(),
            },
        );
        // The axis that answers "was the guest obtaining anything" separately
        // from "was the guest executing". A reader who sees advances still
        // climbing next to a stall verdict is looking at a gate that went blind,
        // not at a guest that stopped.
        machoCapturePrint(
            "macho-processor: READY COMPILER: DIAGNOSIS external_progress advances={d} last_step={d} translation_generation={d} heap_high_water=0x{x} heap_live={d} threads_created={d}; translation_generation rises only after PPC guest code is assembled, while the other counters rise only when the guest needs more than it has ever held\n",
            .{
                diagnosis.external_progress_advances,
                diagnosis.external_progress_step,
                diagnosis.external_translation_generation,
                self.ready.external_progress.heap_high_water,
                self.ready.external_progress.heap_live,
                self.ready.external_progress.threads_created,
            },
        );
        machoCapturePrint(
            "macho-processor: READY COMPILER: DIAGNOSIS last_named_work={s} work_owner={s} work_thread=0x{x} work_rip=0x{x} at_step={d} work_units_since_milestone={d} total_work_units={d} slow_progress_notices={d}\n",
            .{
                if (diagnosis.last_work_unit.len != 0) diagnosis.last_work_unit else "<none reported by the stage owner>",
                if (diagnosis.last_work_unit_owner.len != 0) diagnosis.last_work_unit_owner else "<unknown>",
                diagnosis.last_work_unit_thread,
                diagnosis.last_work_unit_rip,
                diagnosis.last_work_unit_step,
                diagnosis.work_units_since_milestone,
                self.ready.work_unit_count,
                self.ready.slow_progress_reports,
            },
        );
        // Who was observed running, next to who owes the next edge. When these
        // disagree the blocked line above is naming a subsystem the launch had
        // not reached yet, and chasing that owner is chasing the wrong code.
        machoCapturePrint(
            "macho-processor: READY COMPILER: DIAGNOSIS attributed_phase={s} attributed_owner={s} attributed_last_phase={s} attributed_last_owner={s} attributed_sites={d}/{d} attributed_credits={d} rejected(off_path_thread/stage_unreached/evidence_spent)={d}/{d}/{d}; attribution says which subsystem was executing, not that it was progressing\n",
            .{
                if (diagnosis.attributed_phase.len != 0) diagnosis.attributed_phase else "<unattributed>",
                if (diagnosis.attributed_owner.len != 0) diagnosis.attributed_owner else "<unattributed>",
                if (diagnosis.attributed_last_phase.len != 0) diagnosis.attributed_last_phase else "<none>",
                if (diagnosis.attributed_last_owner.len != 0) diagnosis.attributed_last_owner else "<none>",
                diagnosis.attributed_symbols,
                ready_compiler.types.max_attributed_symbols,
                diagnosis.attributed_credits,
                self.ready.attributed_rejected_thread,
                self.ready.attributed_rejected_stage,
                self.ready.attributed_symbols_dropped,
            },
        );
        // When a total budget runs out, the contract did not fail: one stage
        // ate the allowance. Naming it and its share is the only actionable
        // fact in the report.
        machoCapturePrint(
            "macho-processor: READY COMPILER: DIAGNOSIS costliest_stage={s} cost_steps={d} cost_percent_of_budget={d}%\n",
            .{
                if (diagnosis.costliest_stage.len != 0) diagnosis.costliest_stage else "<none>",
                diagnosis.costliest_stage_steps,
                diagnosis.costliest_stage_percent,
            },
        );
        const hot_symbol = self.metadata.nearestSymbol(diagnosis.hot_site.rip);
        // A high eviction rate means the sample table could not hold the
        // working set, so the spread below is a sketch. Saying so is better
        // than letting the reader over-trust it.
        const attribution_confidence: []const u8 = if (diagnosis.stall_samples == 0)
            "none"
        else if (diagnosis.stall_evictions *| 2 > diagnosis.stall_samples)
            "low (sample table saturated)"
        else
            "good";
        machoCapturePrint(
            "macho-processor: READY COMPILER: DIAGNOSIS hot_site=0x{x} {s}+0x{x} samples={d}/{d} distinct_sites={d} evictions={d} confidence={s} longest_same_site_run={d} steps=[{d}..{d}]\n",
            .{
                diagnosis.hot_site.rip,
                if (hot_symbol) |resolved| resolved.name else "<unknown>",
                if (hot_symbol) |resolved| resolved.offset else 0,
                diagnosis.hot_site.samples,
                diagnosis.stall_samples,
                diagnosis.distinct_sites,
                diagnosis.stall_evictions,
                attribution_confidence,
                self.ready.longest_same_site_run,
                diagnosis.hot_site.first_step,
                diagnosis.hot_site.last_step,
            },
        );
        machoCapturePrint(
            "macho-processor: READY COMPILER: DIAGNOSIS spin_verdict={s} scheduler(runnable/parked)={d}/{d} wait_object=0x{x} wait_notifications={d} wait_stable_since={d} evidence_step={d}; a concentrated site is not classified as scheduling starvation without all three witnesses\n",
            .{
                diagnosis.spin_verdict.label(),
                self.ready.runnable_threads,
                self.ready.parked_threads,
                self.ready.wait_object,
                self.ready.wait_notifications,
                if (self.ready.wait_notifications == 0)
                    self.ready.wait_first_step
                else
                    self.ready.wait_last_change_step,
                self.ready.scheduling_evidence_step,
            },
        );
        // One aggregate table averages a parked consumer and a busy producer
        // into a shape that describes neither. Per thread, a mobility of zero
        // is a thread that never moved.
        for (self.ready.stall_threads[0..self.ready.stall_thread_count]) |entry| {
            const thread_symbol = self.metadata.nearestSymbol(entry.last_rip);
            machoCapturePrint(
                "macho-processor: READY COMPILER: DIAGNOSIS thread=0x{x} samples={d} mobility={d}% parked={} last_rip=0x{x} {s}+0x{x} steps=[{d}..{d}]\n",
                .{
                    entry.thread,
                    entry.samples,
                    entry.mobilityPercent(),
                    entry.parked(),
                    entry.last_rip,
                    if (thread_symbol) |resolved| resolved.name else "<unknown>",
                    if (thread_symbol) |resolved| resolved.offset else 0,
                    entry.first_step,
                    entry.last_step,
                },
            );
        }
        const parked = self.ready.mostParkedThread();
        if (parked.samples != 0) {
            const parked_symbol = self.metadata.nearestSymbol(parked.last_rip);
            machoCapturePrint(
                "macho-processor: READY COMPILER: DIAGNOSIS parked_thread=0x{x} samples={d} rip=0x{x} {s}+0x{x}; this thread never changed its instruction pointer during the window, so it is waiting rather than working\n",
                .{
                    parked.thread,
                    parked.samples,
                    parked.last_rip,
                    if (parked_symbol) |resolved| resolved.name else "<unknown>",
                    if (parked_symbol) |resolved| resolved.offset else 0,
                },
            );
        }
        machoCapturePrint(
            "macho-processor: READY COMPILER: DIAGNOSIS milestone_thread=0x{x} current_thread=0x{x} thread_changed={} waits(timeout/signaled)={d}/{d} pending_wait=0x{x}\n",
            .{
                diagnosis.milestone_thread,
                diagnosis.current_thread,
                diagnosis.thread_changed,
                self.ready.wait_timeout_count,
                self.ready.wait_signal_count,
                self.ready.pending_wait_object,
            },
        );
        machoCapturePrint(
            "macho-processor: READY COMPILER: GUIDANCE {s}\n",
            .{diagnosis.guidance()},
        );
    }

    pub fn logReadyCompilerSummary(self: *const MachOState) void {
        if (!self.ready.enabled()) return;
        const missing = self.ready.firstMissingRequired();
        var passed_compile_checks: usize = 0;
        for (self.ready.compile_checks[0..self.ready.compile_check_count]) |check| {
            if (check.passed) passed_compile_checks += 1;
        }
        machoCapturePrint(
            "macho-processor: READY COMPILER SUMMARY: phase={s} enforce={} progress={s} activation_budget={d} activation_budget_mode={s} terminal={} compile_checks={d}/{d} checks_dropped={d} functions={d} functions_dropped={d} compiler_diagnostics={d} waits(timeout/signaled)={d}/{d} milestones={d}/{d} work_units={d} slow_notices={d} activation_start={d} last_milestone={d} last_named_work={d} last_progress={d} missing={s} missing_owner={s} failure={s}\n",
            .{
                @tagName(self.ready.phase),
                self.ready.enforce,
                self.ready.classifyProgress(self.executed_steps).label(),
                if (self.ready.contract) |active_contract| active_contract.activation_budget_steps else 0,
                self.ready.activationBudgetMode(),
                self.ready.terminal(),
                passed_compile_checks,
                self.ready.compile_check_count,
                self.ready.compile_checks_dropped,
                self.ready.function_count,
                self.ready.functions_dropped,
                self.ready.compiler_diagnostic_count,
                self.ready.wait_timeout_count,
                self.ready.wait_signal_count,
                @popCount(self.ready.reached_mask),
                if (self.ready.contract) |active_contract| active_contract.stages.len else 0,
                self.ready.work_unit_count,
                self.ready.slow_progress_reports,
                self.ready.activation_start_step,
                self.ready.last_milestone_step,
                self.ready.lastNamedProgressStep(),
                self.ready.last_progress_step,
                if (missing) |stage| stage.name else "<none>",
                if (missing) |stage|
                    (if (stage.owner.len != 0) stage.owner else "<unattributed>")
                else
                    "<none>",
                self.ready.failure.kind.label(),
            },
        );
        self.logReadyCompilerProgress();
        // A failure emits its own evidence below, next to the blocked line.
        // Without one, the summary is the only place the evidence can appear,
        // so a run that stopped short without a typed failure still explains
        // where startup actually got to.
        if (self.ready.failure.kind == .none) self.logReadyCompilerDiagnosis();
        for (self.ready.compile_checks[0..self.ready.compile_check_count]) |check| {
            machoCapturePrint(
                "macho-processor: READY COMPILER: report compile-check name={s} passed={} detail={s}\n",
                .{ check.name, check.passed, check.detail },
            );
        }
        if (self.ready.contract) |active_contract| {
            for (active_contract.stages) |spec| {
                const stage_bit = @as(u64, 1) << @as(u6, @intCast(spec.id));
                const reached = self.ready.reached_mask & stage_bit != 0;
                machoCapturePrint(
                    "macho-processor: READY COMPILER: report stage id={d} name={s} required={} reached={} owner={s} first_step={d} elapsed_steps={d} prerequisites=0x{x} missing_prerequisites=0x{x} blockage={s} description={s}\n",
                    .{
                        spec.id,
                        spec.name,
                        spec.required,
                        reached,
                        if (spec.owner.len != 0) spec.owner else "<unattributed>",
                        self.ready.first_stage_step[@intCast(spec.id)],
                        self.ready.stage_duration[@intCast(spec.id)],
                        spec.prerequisites,
                        spec.prerequisites & ~self.ready.reached_mask,
                        // Naming the blockage per stage separates "could not
                        // have run yet" from "ran and stayed silent" without
                        // making the reader decode the prerequisite mask.
                        if (reached)
                            "NONE"
                        else if (spec.prerequisites & ~self.ready.reached_mask != 0)
                            "PREREQUISITES_UNMET"
                        else
                            "OWNER_SILENT",
                        spec.description,
                    },
                );
            }
        }
        for (self.ready.functions[0..self.ready.function_count]) |function| {
            machoCapturePrint(
                "macho-processor: READY COMPILER: report function address=0x{x} state={s} module={s} name={s} compile_started={d} compiled={d} installed={d} entered={d} last_progress={d} entry_thread=0x{x} caller=0x{x}\n",
                .{
                    function.address,
                    @tagName(function.state),
                    if (function.module.len != 0) function.module else "<unknown>",
                    if (function.name.len != 0) function.name else "<unknown>",
                    function.compile_started_step,
                    function.compiled_step,
                    function.installed_step,
                    function.entered_step,
                    function.last_progress_step,
                    function.entry_thread,
                    function.caller,
                },
            );
        }
        // The approach to the frontier, oldest first. The last breadcrumb says
        // where startup stopped; the trail says how it got there, which is what
        // separates a subsystem that never started from one that got most of
        // the way through and stopped on a specific step.
        var trail_position: usize = 0;
        while (trail_position < ready_compiler.types.work_unit_history_len) : (trail_position += 1) {
            const entry = self.ready.workUnitHistoryAt(trail_position);
            if (entry.len == 0) continue;
            machoCapturePrint(
                "macho-processor: READY COMPILER: report work-unit [{d}] step={d} owner={s} thread=0x{x} rip=0x{x} name={s}\n",
                .{ trail_position, entry.step, if (entry.ownerSlice().len != 0) entry.ownerSlice() else "<unknown>", entry.thread, entry.rip, entry.slice() },
            );
        }
        // Where the guest spent the window that never reached the next edge.
        // The shape of this table is the finding: one site holding nearly every
        // sample is a loop, while a wide spread is ordinary forward execution
        // that simply has no breadcrumb naming it.
        // Hottest first, and only the top few: dumping every occupied slot in
        // hash order buries the site that matters under single-sample noise.
        var site_rank: usize = 0;
        while (site_rank < ready_compiler.types.reported_stall_sites) : (site_rank += 1) {
            const site = self.ready.siteByRank(site_rank);
            if (site.samples == 0) break;
            const symbol = self.metadata.nearestSymbol(site.rip);
            machoCapturePrint(
                "macho-processor: READY COMPILER: report site [{d}] rip=0x{x} {s}+0x{x} samples={d}/{d} thread=0x{x} steps=[{d}..{d}]\n",
                .{
                    site_rank,
                    site.rip,
                    if (symbol) |resolved| resolved.name else "<unknown>",
                    if (symbol) |resolved| resolved.offset else 0,
                    site.samples,
                    self.ready.stall_samples,
                    site.thread,
                    site.first_step,
                    site.last_step,
                },
            );
        }
        if (self.ready.distinctSites() > site_rank) {
            machoCapturePrint(
                "macho-processor: READY COMPILER: report site ... {d} colder sites omitted of {d} occupied\n",
                .{ self.ready.distinctSites() - site_rank, self.ready.distinctSites() },
            );
        }
        if (self.ready.pending_wait_object != 0) {
            machoCapturePrint(
                "macho-processor: READY COMPILER: report pending-wait object=0x{x} since_step={d}\n",
                .{ self.ready.pending_wait_object, self.ready.pending_wait_step },
            );
        }
        if (self.ready.failure.kind != .none) self.logReadyCompilerFailure();
    }

    /// How many symbols the reference scan resolves in one pass. The scan is
    /// linear in image size and independent of this, so the bound only caps
    /// how many questions one pass can answer.
    pub const max_reference_targets: usize = 64;

    /// The world the compile plan asks its questions of.
    ///
    /// Every probe here is a lookup, a stat, or a table hit — nothing executes
    /// guest code and nothing waits. That is the whole point: the same
    /// preconditions the run would discover four hundred million instructions
    /// in are answered before it starts.
    pub const ReadyPlanContext = struct {
        state: *MachOState,
        io: std.Io,
        image_path: []const u8,
        vex_ready: bool,
        fragments: [max_reference_targets][]const u8 = [_][]const u8{""} ** max_reference_targets,
        addresses: [max_reference_targets]u64 = [_]u64{0} ** max_reference_targets,
        referenced: [max_reference_targets]bool = [_]bool{false} ** max_reference_targets,
        target_count: usize = 0,
        scanned_bytes: u64 = 0,
        direct_call_sites: u64 = 0,
        image_fingerprint: u64 = 0,
        target_fingerprint: u64 = 0,
        static_cache_hit: bool = false,

        fn resolve(self: *ReadyPlanContext, fragment: []const u8) ?u64 {
            var found: [1]u64 = .{0};
            const count = self.state.metadata.symbolAddressesMatching(
                ready_compiler.xenia_plan.symbol_prefix,
                fragment,
                &found,
            );
            if (count == 0) return null;
            return found[0];
        }

        fn targetIndex(self: *const ReadyPlanContext, fragment: []const u8) ?usize {
            for (self.fragments[0..self.target_count], 0..) |entry, index| {
                if (std.mem.eql(u8, entry, fragment)) return index;
            }
            return null;
        }

        fn addTarget(self: *ReadyPlanContext, fragment: []const u8) void {
            if (self.targetIndex(fragment) != null) return;
            if (self.target_count >= self.fragments.len) return;
            const address = self.resolve(fragment) orelse return;
            self.fragments[self.target_count] = fragment;
            self.addresses[self.target_count] = address;
            self.target_count += 1;
        }

        /// Fingerprint the executable bytes after Mach-O mapping and any
        /// load-time patching.  The cache is therefore tied to the bytes the
        /// reference scan actually observes, not merely to the source file's
        /// original contents.
        fn executableFingerprint(self: *const ReadyPlanContext) ?u64 {
            const start = self.state.executable_min;
            const end = self.state.executable_max;
            if (end <= start) return null;
            const bytes = memory_access.guestMemoryConst(self.state, start, end - start) orelse return null;
            return std.hash.Wyhash.hash(0, bytes);
        }

        fn targetFingerprint(self: *const ReadyPlanContext) u64 {
            var count = @as(u64, @intCast(self.target_count));
            var result = std.hash.Wyhash.hash(0, std.mem.asBytes(&count));
            for (self.fragments[0..self.target_count], 0..) |fragment, index| {
                result = ready_compiler.cache.foldTarget(result, fragment, self.addresses[index]);
            }
            return result;
        }

        fn restoreCachedReferences(self: *ReadyPlanContext, snapshot_value: ready_compiler.cache.Snapshot) void {
            self.referenced = [_]bool{false} ** max_reference_targets;
            for (self.referenced[0..self.target_count], 0..) |*referenced, index| {
                referenced.* = snapshot_value.referenced_mask & (@as(u64, 1) << @as(u6, @intCast(index))) != 0;
            }
            self.scanned_bytes = snapshot_value.scanned_bytes;
            self.direct_call_sites = snapshot_value.direct_call_sites;
            self.static_cache_hit = true;
        }

        fn snapshot(self: *const ReadyPlanContext) ready_compiler.cache.Snapshot {
            var referenced_mask: u64 = 0;
            for (self.referenced[0..self.target_count], 0..) |referenced, index| {
                if (referenced) referenced_mask |= @as(u64, 1) << @as(u6, @intCast(index));
            }
            return .{
                .image_fingerprint = self.image_fingerprint,
                .contract_fingerprint = ready_compiler.xenia_plan.fingerprint(),
                .target_fingerprint = self.target_fingerprint,
                .target_count = self.target_count,
                .referenced_mask = referenced_mask,
                .scanned_bytes = self.scanned_bytes,
                .direct_call_sites = self.direct_call_sites,
            };
        }

        /// One pass over the executable range, marking which of the resolved
        /// targets something calls directly.
        ///
        /// Direct `call rel32` only. Virtual dispatch and `std::function` reach
        /// their targets through tables this does not read, so an unmarked
        /// target is evidence and not proof — which is why the units that
        /// consume this are advisory.
        fn scanReferences(self: *ReadyPlanContext) void {
            if (self.target_count == 0) return;
            const start = self.state.executable_min;
            const end = self.state.executable_max;
            if (end <= start) return;
            const span = end - start;
            const bytes = memory_access.guestMemoryConst(self.state, start, span) orelse return;
            self.scanned_bytes = bytes.len;

            var low: u64 = std.math.maxInt(u64);
            var high: u64 = 0;
            for (self.addresses[0..self.target_count]) |address| {
                low = @min(low, address);
                high = @max(high, address);
            }

            var offset: usize = 0;
            while (offset + 5 <= bytes.len) : (offset += 1) {
                if (bytes[offset] != 0xE8) continue;
                const displacement = std.mem.readInt(i32, bytes[offset + 1 ..][0..4], .little);
                const site = start +% @as(u64, offset) +% 5;
                const target = @as(u64, @bitCast(@as(i64, @bitCast(site)) +% displacement));
                if (target < low or target > high) continue;
                self.direct_call_sites +|= 1;
                for (self.addresses[0..self.target_count], 0..) |address, index| {
                    if (address == target) self.referenced[index] = true;
                }
            }
        }

        // --- probe callbacks ---------------------------------------------

        fn imageFact(context: *anyopaque, name: []const u8) bool {
            const self: *ReadyPlanContext = @ptrCast(@alignCast(context));
            const state = self.state;
            if (std.mem.eql(u8, name, "mach-o-header")) return state.segments.len != 0;
            if (std.mem.eql(u8, name, "entry-point")) return state.entry_point_vaddr != 0;
            if (std.mem.eql(u8, name, "text-segment")) return state.executable_max > state.executable_min;
            if (std.mem.eql(u8, name, "symbol-table")) {
                return state.metadata.definedSymbolAddress("_main") != null or
                    state.metadata.symbolAddressWithPrefix("_") != null;
            }
            if (std.mem.eql(u8, name, "bundle-executable")) {
                return std.mem.indexOf(u8, self.image_path, ".app/Contents/MacOS/") != null;
            }
            return false;
        }

        fn symbolExists(context: *anyopaque, name: []const u8) bool {
            const self: *ReadyPlanContext = @ptrCast(@alignCast(context));
            return self.resolve(name) != null;
        }

        fn callSiteExists(context: *anyopaque, name: []const u8) bool {
            const self: *ReadyPlanContext = @ptrCast(@alignCast(context));
            const index = self.targetIndex(name) orelse return false;
            return self.referenced[index];
        }

        fn hostCapability(context: *anyopaque, name: []const u8) bool {
            const self: *ReadyPlanContext = @ptrCast(@alignCast(context));
            if (std.mem.eql(u8, name, "decoder-audit")) return self.vex_ready;
            if (std.mem.eql(u8, name, "vex-safety")) return self.vex_ready;
            if (std.mem.eql(u8, name, "vulkan-loader")) {
                // Either the SDK is configured or a loader sits on one of the
                // usual paths. Advisory, so a false negative costs a note.
                if (std.c.getenv("VULKAN_SDK") != null) return true;
                const candidates = [_][]const u8{
                    "/usr/local/lib/libvulkan.1.dylib",
                    "/opt/homebrew/lib/libvulkan.1.dylib",
                };
                for (candidates) |candidate| {
                    _ = std.Io.Dir.cwd().statFile(self.io, candidate, .{}) catch continue;
                    return true;
                }
                return false;
            }
            // Presentation goes through AppKit, which is part of the platform.
            if (std.mem.eql(u8, name, "window-system")) return true;
            return false;
        }

        fn assetVerdict(
            context: *anyopaque,
            path: []const u8,
            kind: ready_compiler.plan.AssetKind,
        ) ready_compiler.plan.AssetVerdict {
            const self: *ReadyPlanContext = @ptrCast(@alignCast(context));
            var verdict: ready_compiler.plan.AssetVerdict = .{};
            const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch {
                // Absent and unreadable are different findings, and stat cannot
                // always tell them apart. Report absence, which is the far more
                // common cause and the one the detail line names.
                return verdict;
            };
            verdict.present = true;
            verdict.size = stat.size;
            if (stat.kind == .directory) {
                verdict.readable = true;
                verdict.writable = true;
                verdict.well_formed = kind == .directory or kind == .writable_directory;
                return verdict;
            }

            var header: [16]u8 = @splat(0);
            var read: usize = 0;
            const opened = if (std.fs.path.isAbsolute(path))
                std.Io.Dir.openFileAbsolute(self.io, path, .{})
            else
                std.Io.Dir.cwd().openFile(self.io, path, .{});
            if (opened) |file_handle| {
                var file = file_handle;
                defer file.close(self.io);
                // The positional reader is the canonical path used by
                // `readFileAlloc` throughout Rosette. The streaming reader
                // is a separate host-I/O operation and is not guaranteed to
                // be available for every forwarded file descriptor (notably
                // large title assets opened through the Rosette route).
                var reader = file.reader(self.io, &.{});
                read = reader.interface.readSliceShort(&header) catch |err| blk: {
                    machoCapturePrint(
                        "macho-processor: READY COMPILER: asset probe read failed path={s} error={s} size={d}\n",
                        .{ path, @errorName(err), stat.size },
                    );
                    break :blk 0;
                };
                verdict.readable = read != 0 or stat.size == 0;
            } else |err| {
                machoCapturePrint(
                    "macho-processor: READY COMPILER: asset probe open failed path={s} error={s} size={d}\n",
                    .{ path, @errorName(err), stat.size },
                );
                verdict.readable = false;
                return verdict;
            }

            verdict.well_formed = switch (kind) {
                .any_file => stat.size != 0,
                .directory, .writable_directory => false,
                .xex => read >= 4 and std.mem.eql(u8, header[0..4], "XEX2"),
                // A disc image has no single magic across the formats Xenia
                // accepts, so the check is that it is plausibly a filesystem
                // rather than a stub or a truncated download.
                .disc_image => stat.size >= (1 << 20),
                .spirv => read >= 4 and
                    std.mem.readInt(u32, header[0..4], .little) == 0x07230203,
                // Configuration is text; a NUL in the head means it is not.
                .toml => read != 0 and std.mem.indexOfScalar(u8, header[0..read], 0) == null,
                .dylib => read >= 4 and blk: {
                    const magic = std.mem.readInt(u32, header[0..4], .little);
                    break :blk magic == 0xfeedfacf or magic == 0xfeedface or
                        magic == 0xcafebabe or magic == 0xbebafeca;
                },
            };
            return verdict;
        }

        pub fn probe(self: *ReadyPlanContext) ready_compiler.plan.Probe {
            return .{
                .context = self,
                .symbolExists = symbolExists,
                .callSiteExists = callSiteExists,
                .assetVerdict = assetVerdict,
                .hostCapability = hostCapability,
                .imageFact = imageFact,
            };
        }
    };

    fn emitReadyPlanUnit(context: *anyopaque, progress: ready_compiler.plan.Progress) void {
        _ = context;
        switch (progress.outcome) {
            .ok => machoCapturePrint(
                "macho-processor: READY COMPILER: [{d}/{d}] Checking {s} object {s}\n",
                .{ progress.index, progress.total, progress.unit.category.label(), progress.unit.name },
            ),
            .failed => machoCapturePrint(
                "macho-processor: READY COMPILER: [{d}/{d}] FAILED {s} object {s}: {s} (needed for: {s})\n",
                .{
                    progress.index,
                    progress.total,
                    progress.unit.category.label(),
                    progress.unit.name,
                    progress.detail,
                    progress.unit.purpose,
                },
            ),
            .indeterminate => machoCapturePrint(
                "macho-processor: READY COMPILER: [{d}/{d}] UNKNOWN {s} object {s}: {s}\n",
                .{
                    progress.index,
                    progress.total,
                    progress.unit.category.label(),
                    progress.unit.name,
                    progress.detail,
                },
            ),
            .skipped, .pending => {},
        }
    }

    /// Infer what shape a file must have from how it is named.
    fn readyPlanAssetKind(path: []const u8) ?ready_compiler.plan.AssetKind {
        if (std.mem.endsWith(u8, path, ".iso")) return .disc_image;
        if (std.mem.endsWith(u8, path, ".xex")) return .xex;
        if (std.mem.endsWith(u8, path, ".toml")) return .toml;
        if (std.mem.endsWith(u8, path, ".spv")) return .spirv;
        if (std.mem.endsWith(u8, path, ".dylib")) return .dylib;
        if (std.mem.endsWith(u8, path, ".zar") or
            std.mem.endsWith(u8, path, ".zip") or
            std.mem.endsWith(u8, path, ".xcp") or
            std.mem.endsWith(u8, path, ".bin")) return .any_file;
        return null;
    }

    fn readyPlanCachePath() ?[]const u8 {
        if (std.c.getenv("ROSETTE_READY_COMPILER_CACHE")) |raw| {
            const value = std.mem.span(raw);
            if (value.len == 0 or std.ascii.eqlIgnoreCase(value, "off")) return null;
            return value;
        }
        // The event logger creates .rosette before this plan runs.  Keeping
        // the cache beside the two diagnostic logs makes it route-local and
        // avoids putting generated artifacts in the source tree.
        return ".rosette/ready-compiler.plan.cache";
    }

    fn readyPackagePath() ?[]const u8 {
        if (std.c.getenv("ROSETTE_READY_COMPILER_PACKAGE")) |raw| {
            const value = std.mem.span(raw);
            if (value.len == 0 or std.ascii.eqlIgnoreCase(value, "off")) return null;
            return value;
        }
        return ".rosette/packages/xenia-halo3-ready.r3pkg";
    }

    /// Run the startup compile plan before any guest instruction executes.
    ///
    /// Returns false when a required unit failed, in which case the caller must
    /// not start the guest: every later verdict would be a consequence of a
    /// precondition the run already knows is missing.
    pub fn runReadyCompilerPlan(
        self: *MachOState,
        io: std.Io,
        image_path: []const u8,
        args: []const []const u8,
        vex_ready: bool,
    ) bool {
        if (!self.ready.enabled()) return true;

        var assets_storage: [16]ready_compiler.xenia_plan.AssetUnit = undefined;
        var asset_count: usize = 0;
        // The files this run will actually touch are the ones it was pointed
        // at. Declaring a fixed list would check paths this launch does not
        // use and miss the one it does.
        for (args) |argument| {
            if (asset_count >= assets_storage.len) break;
            if (argument.len == 0 or argument[0] == '-') continue;
            const kind = readyPlanAssetKind(argument) orelse continue;
            assets_storage[asset_count] = .{
                .path = argument,
                .kind = kind,
                .purpose = "a file this launch was pointed at",
            };
            asset_count += 1;
        }

        var plan_storage = ready_compiler.plan.Plan{};
        ready_compiler.xenia_plan.build(&plan_storage, assets_storage[0..asset_count]);

        var context = ReadyPlanContext{
            .state = self,
            .io = io,
            .image_path = image_path,
            .vex_ready = vex_ready,
        };
        for (ready_compiler.xenia_plan.contract_units) |unit| context.addTarget(unit.fragment);
        for (ready_compiler.xenia_plan.symbol_units) |unit| context.addTarget(unit.fragment);
        const cache_path = readyPlanCachePath();
        const package_path = readyPackagePath();
        context.image_fingerprint = context.executableFingerprint() orelse 0;
        context.target_fingerprint = context.targetFingerprint();

        var restored_cache = false;
        if (package_path) |path| {
            if (context.image_fingerprint != 0) {
                if (ready_compiler.package.load(path, self.allocator)) |manifest| {
                    if (manifest.matchesStaticPlan(
                        context.image_fingerprint,
                        ready_compiler.xenia_plan.fingerprint(),
                        context.target_fingerprint,
                        context.target_count,
                    )) {
                        context.restoreCachedReferences(.{
                            .image_fingerprint = manifest.image_fingerprint,
                            .contract_fingerprint = manifest.contract_fingerprint,
                            .target_fingerprint = manifest.static_plan_target_fingerprint,
                            .target_count = manifest.static_plan_target_count,
                            .referenced_mask = manifest.static_plan_referenced_mask,
                            .scanned_bytes = manifest.static_plan_scanned_bytes,
                            .direct_call_sites = manifest.static_plan_direct_call_sites,
                        });
                        restored_cache = true;
                        machoCapturePrint(
                            "macho-processor: READY COMPILER: package HIT path={s} image=0x{x} targets={d} scanned_bytes={d} direct_call_sites={d}\n",
                            .{ path, context.image_fingerprint, context.target_count, context.scanned_bytes, context.direct_call_sites },
                        );
                    }
                }
            }
        }
        if (!restored_cache) if (cache_path) |path| {
            if (context.image_fingerprint != 0) {
                if (ready_compiler.cache.load(path, self.allocator)) |snapshot| {
                    if (ready_compiler.cache.matches(
                        snapshot,
                        context.image_fingerprint,
                        ready_compiler.xenia_plan.fingerprint(),
                        context.target_fingerprint,
                        context.target_count,
                    )) {
                        context.restoreCachedReferences(snapshot);
                        restored_cache = true;
                        machoCapturePrint(
                            "macho-processor: READY COMPILER: static plan cache HIT path={s} image=0x{x} targets={d} scanned_bytes={d} direct_call_sites={d}\n",
                            .{ path, context.image_fingerprint, context.target_count, context.scanned_bytes, context.direct_call_sites },
                        );
                    }
                }
            }
        };
        if (!restored_cache) {
            context.scanReferences();
            if (cache_path) |path| {
                if (context.image_fingerprint == 0) {
                    machoCapturePrint(
                        "macho-processor: READY COMPILER: static plan cache skipped because executable fingerprinting was unavailable\n",
                        .{},
                    );
                } else {
                    if (ready_compiler.cache.store(path, self.allocator, context.snapshot())) {
                        machoCapturePrint(
                            "macho-processor: READY COMPILER: static plan cache STORE path={s} image=0x{x} targets={d} scanned_bytes={d} direct_call_sites={d}\n",
                            .{ path, context.image_fingerprint, context.target_count, context.scanned_bytes, context.direct_call_sites },
                        );
                    } else {
                        machoCapturePrint(
                            "macho-processor: READY COMPILER: static plan cache unavailable path={s}; continuing with in-memory evidence\n",
                            .{path},
                        );
                    }
                }
            }
        }

        machoCapturePrint(
            "macho-processor: READY COMPILER: compile plan OPEN units={d} assets={d} reference_targets={d} scanned_bytes={d} direct_call_sites={d}\n",
            .{
                plan_storage.count,
                asset_count,
                context.target_count,
                context.scanned_bytes,
                context.direct_call_sites,
            },
        );

        const emitter = ready_compiler.plan.Emitter{
            .context = &context,
            .emit = emitReadyPlanUnit,
        };
        const summary = plan_storage.run(context.probe(), emitter);

        const static_snapshot = context.snapshot();
        if (summary.halted_at == 0 and package_path != null and static_snapshot.image_fingerprint != 0) {
            const manifest = ready_compiler.xenia_plan.packageManifest(static_snapshot);
            if (ready_compiler.package.store(package_path.?, self.allocator, manifest)) {
                machoCapturePrint(
                    "macho-processor: READY COMPILER: package STORE path={s} kind=xenia-halo3-startup artifacts={d} image=0x{x} target_fingerprint=0x{x}\n",
                    .{ package_path.?, manifest.artifact_count, manifest.image_fingerprint, manifest.static_plan_target_fingerprint },
                );
            } else {
                machoCapturePrint(
                    "macho-processor: READY COMPILER: package unavailable path={s}; static evidence remains in memory/cache\n",
                    .{package_path.?},
                );
            }
        }

        machoCapturePrint(
            "macho-processor: READY COMPILER: compile plan {s} units={d}/{d} ok={d} failed={d} unknown={d} skipped={d}\n",
            .{
                if (summary.halted_at != 0) "RED" else if (summary.failed != 0) "AMBER" else "GREEN",
                summary.ok,
                summary.total,
                summary.ok,
                summary.failed,
                summary.indeterminate,
                summary.skipped,
            },
        );
        if (summary.halted_at != 0) {
            machoCapturePrint(
                "macho-processor: READY COMPILER: compile plan RED at [{d}/{d}] {s} object {s}; halting before the guest executes because every later verdict would be a consequence of this\n",
                .{
                    summary.halted_at,
                    summary.total,
                    summary.halted_unit.category.label(),
                    summary.halted_unit.name,
                },
            );
            self.ready.noteCompileCheck(
                "startup-plan",
                false,
                "a required startup precondition is missing; see the compile plan units above",
            );
            return false;
        }
        // Advisory units that failed are reported and do not stop the run.
        // Most of them are reachability, where a missing direct call site is
        // evidence about the scan's reach as much as about the guest, and
        // refusing to launch over that would be failing on the gate's own
        // blind spot.
        if (summary.failed != 0 or summary.indeterminate != 0) {
            machoCapturePrint(
                "macho-processor: READY COMPILER: compile plan AMBER advisory_failures={d} unknown={d}; every required precondition resolved, so the run continues\n",
                .{ summary.failed, summary.indeterminate },
            );
        }
        self.ready.noteCompileCheck(
            "startup-plan",
            true,
            "every required startup precondition resolved before execution",
        );
        return true;
    }

    /// Which producer stopped, when threads are waiting for something that will
    /// never arrive.
    ///
    /// A blocked count cannot distinguish a thread pool at idle from a lost
    /// wakeup. The notifier's identity can: if every thread that ever signalled
    /// the object is now itself waiting on it, no wake is coming, and the last
    /// signaller's program counter is where the missing notification went.
    pub fn logNotifierLiveness(self: *MachOState) void {
        const object = self.pthreads.worstWaitObject(self.executed_steps) orelse return;
        const progress = notifier_liveness.classify(
            object,
            self.executed_steps,
            notifier_liveness.default_stall_steps,
        );
        const notifier_symbol = self.metadata.nearestSymbol(object.last_notify_pc);
        // A granted repair that ended in a re-park is a stronger statement
        // than "nobody ever signalled it": the waiter's predicate was checked
        // and found false, so this is a guest-side deadlock, not a lost wake.
        const repaired = object.repair_attempts != 0;
        machoCapturePrint(
            "macho-processor: NOTIFIER LIVENESS: object=0x{x} state={s} waiters={d} distinct_notifiers={d} notifications={d} repairs={d} steps_since_notify={d} waiting_since_step={d} last_notify(step={d} thread=0x{x} pc=0x{x} symbol={s}+0x{x})\n",
            .{
                object.address,
                progress.label(),
                object.waiterCount(),
                object.notifierCount(),
                object.notifications,
                object.repair_attempts,
                self.executed_steps -| object.last_notify_step,
                object.first_wait_step,
                object.last_notify_step,
                object.last_notify_thread,
                object.last_notify_pc,
                if (notifier_symbol) |resolved| resolved.name else "<unknown>",
                if (notifier_symbol) |resolved| resolved.offset else 0,
            },
        );
        if (repaired) {
            machoCapturePrint(
                "macho-processor: NOTIFIER LIVENESS GUIDANCE: a bounded spurious wake was already granted {d} time(s) and the waiter re-parked — the predicate is genuinely unsatisfied. The creator never published the state it waits on; find the code that should have published it and confirm it ran. The once-per-generation guard stops further wakes, so this cannot become a synthetic busy loop\n",
                .{object.repair_attempts},
            );
        } else {
            machoCapturePrint("macho-processor: NOTIFIER LIVENESS GUIDANCE: {s}\n", .{progress.guidance()});
        }
        // The repair is per-class, not per-report: an `observed_notifiers_parked`
        // object can outrank a never-notified one for the report, but only
        // never-notified waiters have the lost-wakeup repair, and the selector
        // inside `wakeNeverNotifiedWaiter` already applies the stall gate. The
        // quiescence repair cannot reach these waiters: the rest of the run is
        // alive, so "nothing runnable" never became true.
        //
        // Do not mutate a potentially healthy host worker merely because its
        // condition variable has never been signalled. If this is a confirmed
        // guest lost-wakeup, the old bounded experiment remains available via
        // ROSETTE_MACHO_NEVER_NOTIFIED_REPAIR=1.
        if (self.never_notified_repair_enabled) {
            if (self.pthreads.wakeNeverNotifiedWaiter(self.executed_steps)) |repair| {
                const woken_symbol = self.metadata.nearestSymbol(repair.thread);
                machoCapturePrint(
                    "macho-processor: NOTIFIER LIVENESS REPAIR: granted one generation-bounded POSIX spurious wake thread=0x{x} object=0x{x} waited_steps={d} symbol={s}; the guest predicate loop re-checks its own condition on return\n",
                    .{
                        repair.thread,
                        repair.object,
                        repair.waited_steps,
                        if (woken_symbol) |resolved| resolved.name else "<unknown>",
                    },
                );
                // The wake happened here; what it proved is judged elsewhere.
                // A release nobody reads the outcome of is a workaround, and
                // one whose outcome is recorded is an experiment that settles
                // which codebase the defect is in.
                self.noteStallReleaseGranted(repair.object, repair.thread, repair.waited_steps);
            }
        } else if (progress == .never_notified) {
            machoCapturePrint(
                "macho-processor: NOTIFIER LIVENESS REPAIR: disabled by default for never-notified waits; this may be an intentional idle worker. Set ROSETTE_MACHO_NEVER_NOTIFIED_REPAIR=1 only after identifying a guest lost-wakeup\n",
                .{},
            );
        }
    }

    /// Guest traffic to the GPU register aperture, and what it licenses a
    /// reader to conclude.
    ///
    /// This report is deliberately emitted even when the count is zero. Zero is
    /// the whole finding: the aperture faults on every access, so an empty
    /// table is positive evidence that the title never programmed the GPU, and
    /// that is a statement about the title rather than about the graphics
    /// stack. Suppressing it would leave exactly the silence this was built to
    /// remove.
    pub fn logRegisterApertureTraffic(self: *const MachOState) void {
        const observer = &self.gpu_register_aperture;
        const ring = observer.ringSetupWrites();
        machoCapturePrint(
            "  gpu register aperture: base=0x{x} size=0x{x} reads={d} writes={d} delivered={d} undelivered={d} ring_setup_writes={d} (delivered={d}) registers_touched={d} untracked={d} misaligned={d} verdict={s}; {s}\n",
            .{
                device_tree.gpu.xenos.register_aperture_base,
                device_tree.gpu.xenos.register_aperture_size,
                observer.total_reads,
                observer.total_writes,
                observer.total_delivered,
                observer.total_undelivered,
                ring.writes,
                ring.delivered,
                observer.count,
                observer.untracked_accesses,
                observer.misaligned,
                @tagName(observer.verdict()),
                observer.verdict().describe(),
            },
        );
        for (observer.registers[0..observer.count]) |entry| {
            machoCapturePrint(
                "    register index=0x{x} {s} reads={d} writes={d} delivered={d} undelivered={d} last_value=0x{x} nonzero_write={} first_step={d} first_rip=0x{x} first_thread=0x{x}\n",
                .{
                    entry.index,
                    entry.name(),
                    entry.reads,
                    entry.writes,
                    entry.delivered,
                    entry.undelivered,
                    entry.last_value,
                    entry.saw_nonzero_write,
                    entry.first_step,
                    entry.first_rip,
                    entry.first_thread,
                },
            );
        }
    }

    /// Anomalies with their dispositions, so a non-zero count is either acted
    /// on or explicitly dismissed rather than accumulating unread.
    pub fn logAnomalyLedger(self: *const MachOState) void {
        const ledger = &self.anomalies;
        if (ledger.count == 0) return;
        machoCapturePrint(
            "macho-processor: ANOMALY LEDGER: distinct={d} unclassified={d} implicated={d} overflow={d} signoff_clean={s}; {s}\n",
            .{
                ledger.count,
                ledger.unclassified(),
                ledger.implicated(),
                ledger.overflow,
                if (ledger.signoffClean()) "YES" else "NO",
                ledger.verdict(),
            },
        );
        for (ledger.records[0..ledger.count]) |record| {
            machoCapturePrint(
                "  anomaly kind={s} occurrences={d} disposition={s} first_step={d} thread=0x{x} caller=0x{x} detail={s}\n",
                .{
                    record.kind.label(),
                    record.occurrences,
                    record.disposition.label(),
                    record.step,
                    record.guest_thread,
                    record.caller_pc,
                    record.detailSlice(),
                },
            );
        }
    }

    /// The graphics frontier, emitted on a schedule rather than only at exit.
    ///
    /// The 21:17 run produced none of the graphics summaries at all, because
    /// the wrapper killed the process on a timeout and every summary was
    /// written from the exit path. A diagnostic that only survives a clean
    /// shutdown is unavailable in exactly the runs that need it, so this is
    /// Refresh the graphics contract from evidence the other subsystems hold,
    /// then report it.
    ///
    /// The ledger is derived rather than maintained: every fact here already
    /// exists somewhere, and the value is the join plus the owner. Keeping it
    /// derived means it cannot drift out of agreement with the subsystem that
    /// actually knows — a second copy of the truth is how two reports in one
    /// run end up contradicting each other.
    pub fn refreshGraphicsContract(self: *MachOState) void {
        const ledger = &self.graphics_contract;
        const tracepoints = &self.execution_tracepoints;
        const at = self.executed_steps;

        // Harness-owned platform surface. Rosette supplies these, so they are
        // recorded through `satisfy` — which the ledger permits only because
        // Rosette owns them. On Windows the equivalent state exists before the
        // title runs; here it exists because the harness made it.
        if (self.native_window.layer_attachments != 0) {
            _ = ledger.satisfy(.native_window_surface, at);
        }
        if (self.native_window.surface_bindings != 0) {
            _ = ledger.satisfy(.native_presenter_bound, at);
            // A bound surface is the evidence the backend instance and the
            // adapter were negotiated: neither a VkSurfaceKHR nor a CAMetalLayer
            // can be produced without them.
            _ = ledger.satisfy(.backend_instance_negotiated, at);
            _ = ledger.satisfy(.physical_adapter_negotiated, at);
        }
        // Either presentation path proves the capability. Keying this on the
        // Metal diagnostic counter alone made a run whose presenter came up
        // through Vulkan report presentation as outstanding harness work while
        // frames were on the window — the report then sent a reader to write
        // code that already existed, which is worse than reporting nothing.
        if (self.native_window.diagnostic_frames_presented != 0 or
            self.dynamic_forwarder.nativePresenterFramesPresented() != 0 or
            self.dynamic_forwarder.nativePresenterStage().isReady())
        {
            _ = ledger.satisfy(.presentation_capability_negotiated, at);
        }
        // Event handshake activity proves the guest's wait primitives are being
        // driven. Deliberately keyed on call volume and not on `was_signalled`,
        // which is a compile-time constant in the emulator and proves nothing.
        // Keyed on whether waits actually block, not on whether sets happen.
        // A run where every wait is satisfied on arrival has sets in abundance
        // and consumes nothing, which is the exact failure this clause exists
        // to catch — so counting sets satisfied it in precisely the case it was
        // written to detect.
        if (self.guest_wait_liveness.aggregateVerdict().healthy() and
            self.guest_wait_liveness.total_waits >= guest_wait_liveness.minimum_sample)
        {
            _ = ledger.satisfy(.wait_primitives_consume_signals, at);
        }

        // Emulator-owned bring-up, observed only.
        if (self.gpu_bootstrap.seen(.initialize_engines)) ledger.observe(.gpu_engines_initialised, at);
        if (self.gpu_bootstrap.seen(.graphics_interrupt_callback)) ledger.observe(.interrupt_callback_registered, at);
        if (self.gpu_bootstrap.seen(.graphics_interrupt_dispatch)) ledger.observe(.interrupt_callback_dispatched, at);
        if (self.gpu_bootstrap.seen(.ring_buffer)) ledger.observe(.ring_buffer_initialised, at);

        // Title-owned behaviour, observed only. `satisfy` would refuse these
        // anyway; observing is the only way they can ever be met.
        const publication = &self.gpu_ring_publication;
        if (publication.published()) ledger.observe(.guest_ring_payload_published, at);
        if (publication.advances != 0) ledger.observe(.guest_write_pointer_advanced, at);
        if (self.gpu_bootstrap.seen(.pm4_packet_consumed)) ledger.observe(.guest_pm4_consumed, at);
        if (tracepoints.roleEntered(.swap)) ledger.observe(.guest_swap_entered, at);
        if (self.guest_vdswap_packet_encoded) ledger.observe(.swap_packet_encoded, at);
        if (self.gpu_vd_swap_contract.authentic_consumptions != 0) ledger.observe(.swap_consumed_by_command_processor, at);
        if (tracepoints.roleEntered(.presenter)) ledger.observe(.presenter_output_refreshed, at);

        self.refreshVdSwapContract();
    }

    /// Add one observation to the cross-layer graphics ledger.  Keeping this
    /// tiny adapter beside the process state makes ownership explicit at every
    /// call site and leaves the package/runtime ledger independent of Mach-O.
    fn recordGraphicsHealth(
        self: *MachOState,
        stage: graphics_health_contract.Stage,
        state: graphics_health_contract.State,
        source: graphics_health_contract.Source,
        count: u64,
        note: []const u8,
    ) void {
        self.graphics_health.record(stage, state, self.executed_steps, source, count, note);
    }

    /// Map the native presenter state to the health schema without weakening
    /// its failure semantics.  In particular, a `surface_not_presentable`
    /// result is backpressure (degraded swapchain use), not a successful frame,
    /// and `device_lost` never gets reported as a healthy device.
    fn recordNativePresenterPrerequisites(self: *MachOState, state: graphics_health_contract.State, note: []const u8) void {
        self.recordGraphicsHealth(.vulkan_loader_resolved, state, .native_presenter, 1, note);
        self.recordGraphicsHealth(.vulkan_instance_ready, state, .native_presenter, 1, note);
        self.recordGraphicsHealth(.vulkan_surface_ready, state, .native_presenter, 1, note);
        self.recordGraphicsHealth(.physical_adapter_ready, state, .native_presenter, 1, note);
        self.recordGraphicsHealth(.logical_device_ready, state, .native_presenter, 1, note);
        self.recordGraphicsHealth(.graphics_queue_ready, state, .native_presenter, 1, note);
        self.recordGraphicsHealth(.swapchain_ready, state, .native_presenter, 1, note);
        self.recordGraphicsHealth(.frame_resources_ready, state, .native_presenter, 1, note);
    }

    fn refreshNativePresenterHealth(self: *MachOState) void {
        const stage = self.dynamic_forwarder.nativePresenterStage();
        if (self.dynamic_forwarder.native_presenter_attempts == 0) return;

        switch (stage) {
            .unstarted => {},
            .loader_unavailable => self.recordGraphicsHealth(.vulkan_loader_resolved, .blocked, .native_presenter, 1, stage.label()),
            .instance_extensions_missing, .instance_failed => {
                self.recordGraphicsHealth(.vulkan_loader_resolved, .satisfied, .native_presenter, 1, "vkGetInstanceProcAddr resolved");
                self.recordGraphicsHealth(.vulkan_instance_ready, .blocked, .native_presenter, 1, stage.label());
            },
            .surface_failed => {
                self.recordGraphicsHealth(.vulkan_loader_resolved, .satisfied, .native_presenter, 1, "Vulkan loader resolved");
                self.recordGraphicsHealth(.vulkan_instance_ready, .satisfied, .native_presenter, 1, "native instance created");
                self.recordGraphicsHealth(.vulkan_surface_ready, .blocked, .native_presenter, 1, stage.label());
            },
            .no_supported_physical_device => {
                self.recordGraphicsHealth(.vulkan_loader_resolved, .satisfied, .native_presenter, 1, "Vulkan loader resolved");
                self.recordGraphicsHealth(.vulkan_instance_ready, .satisfied, .native_presenter, 1, "native instance created");
                self.recordGraphicsHealth(.vulkan_surface_ready, .satisfied, .native_presenter, 1, "Metal surface created");
                self.recordGraphicsHealth(.physical_adapter_ready, .blocked, .native_presenter, 1, stage.label());
            },
            .device_failed => {
                self.recordNativePresenterPrerequisites(.satisfied, "native loader, instance, surface and adapter reached");
                self.recordGraphicsHealth(.logical_device_ready, .blocked, .native_presenter, 1, stage.label());
            },
            .frame_resources_failed => {
                self.recordNativePresenterPrerequisites(.satisfied, "native device and graphics queue reached");
                self.recordGraphicsHealth(.frame_resources_ready, .blocked, .native_presenter, 1, stage.label());
            },
            .swapchain_failed => {
                self.recordNativePresenterPrerequisites(.satisfied, "native frame prerequisites reached");
                self.recordGraphicsHealth(.swapchain_ready, .blocked, .native_presenter, 1, stage.label());
            },
            .surface_not_presentable => {
                self.recordNativePresenterPrerequisites(.satisfied, "native presenter exists; surface is temporarily unavailable");
                self.recordGraphicsHealth(.swapchain_ready, .degraded, .native_presenter, 1, stage.label());
            },
            .ready => {
                self.recordNativePresenterPrerequisites(.satisfied, "native presenter instance/surface/device/queue/swapchain are live");
            },
            .device_lost => {
                self.recordGraphicsHealth(.vulkan_loader_resolved, .satisfied, .native_presenter, 1, "Vulkan loader resolved before device loss");
                self.recordGraphicsHealth(.vulkan_instance_ready, .satisfied, .native_presenter, 1, "native instance existed before device loss");
                self.recordGraphicsHealth(.vulkan_surface_ready, .satisfied, .native_presenter, 1, "native surface existed before device loss");
                self.recordGraphicsHealth(.physical_adapter_ready, .satisfied, .native_presenter, 1, "physical adapter existed before device loss");
                self.recordGraphicsHealth(.logical_device_ready, .blocked, .native_presenter, 1, stage.label());
                self.recordGraphicsHealth(.graphics_queue_ready, .blocked, .native_presenter, 1, stage.label());
                self.recordGraphicsHealth(.swapchain_ready, .blocked, .native_presenter, 1, stage.label());
                self.recordGraphicsHealth(.frame_resources_ready, .blocked, .native_presenter, 1, stage.label());
            },
        }
    }

    /// Refresh the broad graphics-health ledger from the owners that already
    /// hold the evidence.  This is intentionally a join, not a second runtime
    /// implementation: every count below is read from an existing subsystem,
    /// and a missing count stays untested rather than becoming a guessed pass.
    pub fn refreshGraphicsHealthContract(self: *MachOState) void {
        const at = self.executed_steps;

        if (self.event_stream.run_id != 0 or at != 0)
            self.recordGraphicsHealth(.application_started, .satisfied, .process, 1, "event stream has a run identity");
        if (at != 0)
            self.recordGraphicsHealth(.guest_image_mapped, .satisfied, .process, at, "translated guest instructions executed");
        if (self.pthreads.created_threads != 0)
            self.recordGraphicsHealth(.guest_scheduler_running, .satisfied, .scheduler, self.pthreads.created_threads, "guest threads have been created and rotated");

        const exports = self.gpu_kernel_surface.finding();
        if (exports.imported_count != 0) {
            self.recordGraphicsHealth(
                .kernel_graphics_exports_resolved,
                if (exports.blocking == null) .satisfied else .blocked,
                .kernel_surface,
                exports.usable_count,
                if (exports.blocking) |which| which.guidance() else "imported graphics exports are bound and usable",
            );
        }
        const variables = self.gpu_kernel_variables.finding();
        if (variables.imported_count != 0) {
            self.recordGraphicsHealth(
                .kernel_graphics_variables_populated,
                if (variables.blocking == null) .satisfied else .blocked,
                .kernel_surface,
                variables.usable_count,
                if (variables.blocking) |which| which.meaning() else "imported graphics variables resolve through slot and storage",
            );
        }

        const native_window_state = &self.native_window;
        if (native_window_state.application_ensure_attempts != 0)
            self.recordGraphicsHealth(
                .native_application_ready,
                if (native_window_state.window_ready_logged or native_window_state.layer_attachments != 0) .satisfied else .degraded,
                .native_window,
                native_window_state.application_ensure_attempts,
                if (native_window_state.window_ready_logged) "NSApplication and its window status were observed" else "application ensure was attempted; native status is not yet complete",
            );
        if (native_window_state.window_ready_logged or native_window_state.surface_bindings != 0) {
            self.recordGraphicsHealth(.native_window_ready, .satisfied, .native_window, native_window_state.window_ensure_attempts, "NSWindow/NSView status was observed");
        } else if (native_window_state.window_ensure_attempts != 0) {
            self.recordGraphicsHealth(.native_window_ready, if (native_window_state.window_ensure_failures != 0) .blocked else .degraded, .native_window, native_window_state.window_ensure_attempts, "window ensure has not produced a ready status");
        }
        if (native_window_state.layer_attachments != 0) {
            self.recordGraphicsHealth(.native_layer_attached, .satisfied, .native_window, native_window_state.layer_attachments, "CAMetalLayer attachment succeeded");
        } else if (native_window_state.layer_requests != 0) {
            self.recordGraphicsHealth(.native_layer_attached, if (native_window_state.layer_attachment_failures != 0) .blocked else .degraded, .native_window, native_window_state.layer_requests, "CAMetalLayer was requested but attachment is not proven");
        }

        if (self.dynamic_forwarder.native_vulkan_loader_attempts != 0)
            self.recordGraphicsHealth(
                .vulkan_loader_resolved,
                if (self.dynamic_forwarder.native_vulkan_loader_failures == 0) .satisfied else .blocked,
                .vulkan_forwarder,
                self.dynamic_forwarder.native_vulkan_loader_attempts,
                if (self.dynamic_forwarder.native_vulkan_loader_failures == 0) "native Vulkan loader attempts resolved" else "native Vulkan loader resolution failed",
            );
        self.refreshNativePresenterHealth();

        const observed_commands = self.dynamic_forwarder.guestVulkanObservedCommands();
        const real_commands = self.dynamic_forwarder.guestVulkanCommandsForwarded();
        const real_submits = self.dynamic_forwarder.guestVulkanQueueSubmits();
        const real_presents = self.dynamic_forwarder.guestVulkanPresents();
        if (observed_commands != 0 or real_submits != 0 or real_presents != 0)
            self.recordGraphicsHealth(.guest_vulkan_activity_observed, .satisfied, .vulkan_forwarder, observed_commands +| real_submits +| real_presents, "guest Vulkan calls reached the forwarding surface");
        if (real_commands != 0) {
            self.recordGraphicsHealth(.guest_vulkan_commands_forwarded, .satisfied, .vulkan_forwarder, real_commands, "guest Vulkan command calls reached native forwarding");
        } else if (observed_commands != 0) {
            self.recordGraphicsHealth(.guest_vulkan_commands_forwarded, .degraded, .vulkan_forwarder, observed_commands, "guest Vulkan commands were observed without native command forwarding");
        }
        if (real_submits != 0) {
            self.recordGraphicsHealth(.guest_vulkan_submission_forwarded, .satisfied, .vulkan_forwarder, real_submits, "guest queue submissions reached the native driver");
        } else if (observed_commands != 0) {
            self.recordGraphicsHealth(.guest_vulkan_submission_forwarded, .degraded, .vulkan_forwarder, observed_commands, "guest command activity has no native queue submission");
        }

        if (self.gpu_bootstrap.seen(.initialize_engines))
            self.recordGraphicsHealth(.xenos_engines_initialized, .satisfied, .xenos_runtime, 1, "VdInitializeEngines was observed");
        if (self.gpu_interrupt_callback != 0)
            self.recordGraphicsHealth(.xenos_interrupt_callback_registered, .satisfied, .kernel_surface, self.gpu_interrupt_callback_registrations, "VdSetGraphicsInterruptCallback installed a guest callback");
        if (self.gpu_bootstrap.seen(.ring_buffer) or self.gpu_ring_watch_base != 0)
            self.recordGraphicsHealth(.xenos_ring_initialized, .satisfied, .ring_publication, 1, "ring base/size state is available");
        if (self.gpu_ring_publication.published())
            self.recordGraphicsHealth(.ring_publication_observed, .satisfied, .ring_publication, self.gpu_ring_publication.advances, "guest publication is latched by a pointer change or non-empty span");
        if (self.gpu_ring_publication.geometry != null)
            self.recordGraphicsHealth(.ring_geometry_observed, .satisfied, .ring_publication, 1, "ring read/write geometry was captured");

        const vd = &self.gpu_vd_swap_contract;
        const runtime = &self.gpu_xenos_runtime;
        const target = runtime.renderTargetEvidence();
        const pm4_observed = runtime.batches != 0 or vd.observed(.pm4_stream_observed);
        if (pm4_observed)
            self.recordGraphicsHealth(.pm4_stream_observed, .satisfied, if (runtime.batches != 0) .xenos_runtime else .vd_swap_contract, runtime.batches, "PM4 dwords/packets were observed");
        if (vd.observed(.pm4_stream_validated))
            self.recordGraphicsHealth(.pm4_stream_validated, .satisfied, .vd_swap_contract, 1, "PM4 framing passed the bounded validator");
        if (pm4_observed) {
            const indirect_bad = runtime.indirect_unreadable +| runtime.indirect_truncated +| runtime.indirect_invalid +| runtime.indirect_depth_limited +| runtime.indirect_budget_limited;
            if (runtime.indirect_buffers == 0 or indirect_bad == 0) {
                self.recordGraphicsHealth(.pm4_indirects_resolved, .satisfied, .xenos_runtime, runtime.indirect_buffers, if (runtime.indirect_buffers == 0) "no indirect buffers were required" else "all observed indirect buffers were readable and bounded");
            } else {
                self.recordGraphicsHealth(.pm4_indirects_resolved, .blocked, .xenos_runtime, indirect_bad, "one or more indirect buffers were unreadable, truncated or over budget");
            }
        }
        if (vd.observed(.pm4_state_programmed) or runtime.executor.register_file.write_count != 0)
            self.recordGraphicsHealth(.pm4_state_programmed, .satisfied, .xenos_runtime, runtime.executor.register_file.write_count, "Xenos register state was programmed");
        if (runtime.draw_count != 0 or vd.observed(.draw_submitted))
            self.recordGraphicsHealth(.draw_submitted, .satisfied, .xenos_runtime, runtime.draw_count, "draw packets were submitted to the stateful runtime");
        if (runtime.draw_count != 0 or vd.observed(.draw_consumed) or self.gpu_ring_publication.consumerSawBatch())
            self.recordGraphicsHealth(.draw_consumed, .satisfied, .xenos_runtime, runtime.draw_count, "the command processor consumed draw work");
        if (target.state_observed)
            self.recordGraphicsHealth(.render_target_state_observed, if (target.plausible) .satisfied else .degraded, .xenos_runtime, 1, "RB_COLOR_INFO/RB_DEPTH_INFO/RB_SURFACE_INFO state was observed");
        if (runtime.color_resolve_observations != 0)
            self.recordGraphicsHealth(.render_target_memory_observed, .satisfied, .xenos_runtime, runtime.color_resolve_observations, "EDRAM color resolve produced readable output");
        if (runtime.draw_completion_signals != 0)
            self.recordGraphicsHealth(.draw_completion_signaled, .satisfied, .xenos_runtime, runtime.draw_completion_signals, "draw completion events were queued");
        if (runtime.draw_completion_signals != 0)
            self.recordGraphicsHealth(
                .draw_completion_dispatched,
                if (self.gpu_draw_completion_dispatches != 0) .satisfied else .blocked,
                .scheduler,
                self.gpu_draw_completion_dispatches,
                if (self.gpu_draw_completion_dispatches != 0) "draw completion reached the guest callback scheduler" else "draw completion is queued but no callback dispatch is proven",
            );

        const waits = self.guest_wait_liveness.aggregateVerdict();
        if (self.guest_wait_liveness.total_waits != 0)
            self.recordGraphicsHealth(.guest_wait_progressed, if (waits.healthy()) .satisfied else .degraded, .guest_log, self.guest_wait_liveness.total_waits, waits.label());
        if (self.gpu_ring_publication.advances != 0) {
            const quiet = self.gpu_ring_publication.stalledSteps(at) orelse 0;
            self.recordGraphicsHealth(
                .guest_producer_progressed,
                if (quiet < application_controller.ring_quiet_threshold_steps) .satisfied else .blocked,
                .ring_publication,
                self.gpu_ring_publication.advances,
                if (quiet < application_controller.ring_quiet_threshold_steps) "ring producer advanced within the controller window" else "ring producer is quiet beyond the controller window",
            );
        }
        if (self.execution_tracepoints.roleEntered(.swap))
            self.recordGraphicsHealth(.guest_vdswap_entered, .satisfied, .causal_trace, 1, "execution tracepoint reached the guest VdSwap role");
        if (self.guest_vdswap_packet_encoded)
            self.recordGraphicsHealth(.guest_swap_encoded, .satisfied, .vd_swap_contract, 1, "guest-origin XE_SWAP encoding was observed");
        if (vd.authentic_consumptions != 0)
            self.recordGraphicsHealth(.authentic_swap_consumed, .satisfied, .vd_swap_contract, vd.authentic_consumptions, "authentic XE_SWAP reached the command processor");
        if (vd.observed(.issue_swap_entered))
            self.recordGraphicsHealth(.issue_swap_entered, .satisfied, .vd_swap_contract, 1, "Xenia presenter IssueSwap boundary was observed");

        const guest_output_frames = self.dynamic_forwarder.native_presenter.ledger.guest_output_frames_presented;
        if (guest_output_frames != 0) {
            self.recordGraphicsHealth(.guest_output_refreshed, .satisfied, .native_presenter, guest_output_frames, "guest-produced pixels reached the presenter source");
        } else if (self.dynamic_forwarder.guestFrontBufferAvailable()) {
            self.recordGraphicsHealth(.guest_output_refreshed, .degraded, .native_presenter, 1, "a guest output source was discovered, but no guest-produced frame has been refreshed");
        }
        const native_frames = self.dynamic_forwarder.nativePresenterFramesPresented();
        if (native_frames != 0)
            self.recordGraphicsHealth(.native_present_completed, .satisfied, .native_presenter, native_frames, "the native presenter completed a frame (classification is logged separately)");
    }

    /// Feed the controller from the independent ledgers.  The controller may
    /// authorize only host-owned work; the guest VdSwap and producer fields are
    /// observations that remain outside Rosette's mutation authority.
    pub fn refreshApplicationController(self: *MachOState) application_controller.Decision {
        const guest_output_frames = self.dynamic_forwarder.native_presenter.ledger.guest_output_frames_presented;
        const deadlocked = self.deadlock_predictor.worst().finding.deadlocked();
        return self.application_controller.observe(.{
            .step = self.executed_steps,
            .guest_progress_step = if (self.xenia_gpu_causal_trace.last_progress_step != 0) self.xenia_gpu_causal_trace.last_progress_step else null,
            .ring_progress_step = if (self.gpu_ring_publication.last_advance_step != 0) self.gpu_ring_publication.last_advance_step else null,
            .pm4_progress_step = if (self.gpu_ring_publication.last_consumed_step != 0) self.gpu_ring_publication.last_consumed_step else null,
            .guest_vdswap_entered = self.execution_tracepoints.roleEntered(.swap),
            .guest_swap_encoded = self.guest_vdswap_packet_encoded,
            .authentic_swap_consumed = self.gpu_vd_swap_contract.authentic_consumptions != 0,
            .guest_output_available = guest_output_frames != 0 or self.dynamic_forwarder.guestFrontBufferAvailable(),
            .native_present_completed = guest_output_frames != 0,
            .ring_published = self.gpu_ring_publication.published(),
            .pm4_stream_observed = self.gpu_xenos_runtime.batches != 0 or self.gpu_vd_swap_contract.observed(.pm4_stream_observed),
            .pm4_stream_consumed = self.gpu_xenos_runtime.draw_count != 0 or self.gpu_ring_publication.consumerSawBatch(),
            .render_target_state_observed = self.gpu_xenos_runtime.renderTargetEvidence().state_observed,
            .render_target_memory_observed = self.gpu_xenos_runtime.color_resolve_observations != 0,
            .draw_completion_signaled = self.gpu_xenos_runtime.draw_completion_signals,
            .draw_completion_dispatched = self.gpu_draw_completion_dispatches,
            .pending_gpu_interrupts = self.gpu_xenos_runtime.interrupts.pending_count,
            .interrupt_callback_registered = self.gpu_interrupt_callback != 0,
            .presenter_ready = self.dynamic_forwarder.nativePresenterStage().isReady(),
            .presenter_device_lost = self.dynamic_forwarder.nativePresenterStage() == .device_lost,
            .guest_wait_deadlocked = deadlocked,
            .guest_waiting = self.pthreads.blocked_threads != 0,
            .guest_runnable = self.pthreads.activeCount() != 0,
        });
    }

    /// Apply only directives whose owner is Rosette.  The guest-facing actions
    /// intentionally have no implementation here: reporting an open VdSwap
    /// boundary is the safety mechanism that prevents a diagnostic frame from
    /// erasing the actual producer defect.
    fn applyApplicationController(self: *MachOState, decision: application_controller.Decision) void {
        switch (decision.action) {
            .drain_gpu_interrupts => {
                if (self.gpu_interrupt_callback == 0 or self.gpu_xenos_runtime.interrupts.pending_count == 0) return;
                const delivered = self.gpu_xenos_runtime.drainInterrupts(deliverGpuInterrupt, self, 32);
                if (delivered != 0) self.application_controller_host_drains +|= delivered;
            },
            .refresh_discovered_output => {
                if (!decision.host_action_authorized) return;
                if (self.dynamic_forwarder.attemptScheduledRefresh(self)) self.application_controller_host_refreshes +|= 1;
            },
            else => {},
        }
    }

    /// Drain requests made through the exported framework ABI. Requests are
    /// processed at the same safe frontier as the existing controller, never
    /// from an arbitrary Xenia callback or from the instruction hot path.
    /// Guest calls and memory writes are rejected by the framework policy
    /// before they reach this method; unsupported host requests are completed
    /// explicitly so a caller can distinguish "not implemented" from "never
    /// observed".
    fn serviceApplicationFrameworkRequests(self: *MachOState) void {
        const ServiceResult = struct {
            status: application_framework.contract.RequestStatus,
            reason: u64,
        };
        var request: application_framework.contract.Request = .{};
        var serviced: usize = 0;
        while (serviced < 8 and self.application_framework.takePending(&request)) : (serviced += 1) {
            const command = if (request.command <= @intFromEnum(application_framework.contract.Command.write_host_state))
                @as(application_framework.contract.Command, @enumFromInt(request.command))
            else
                null;
            const result = if (command) |resolved| blk: {
                switch (resolved) {
                    .snapshot => break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.applied, .reason = 0 },
                    .enable_trace => {
                        self.application_framework.enableTraceMask(request.argument0);
                        break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.applied, .reason = 0 };
                    },
                    .disable_trace => {
                        self.application_framework.clearTraceFlags();
                        break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.applied, .reason = 0 };
                    },
                    .drain_gpu_interrupts => {
                        if (self.gpu_interrupt_callback == 0 or self.gpu_xenos_runtime.interrupts.pending_count == 0)
                            break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.not_ready, .reason = 0x4750_5549_4e54_0001 };
                        const delivered = self.gpu_xenos_runtime.drainInterrupts(deliverGpuInterrupt, self, 32);
                        break :blk ServiceResult{
                            .status = if (delivered != 0) application_framework.contract.RequestStatus.applied else application_framework.contract.RequestStatus.not_ready,
                            .reason = delivered,
                        };
                    },
                    .refresh_output => {
                        if (!self.dynamic_forwarder.guestFrontBufferAvailable())
                            break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.not_ready, .reason = 0x4652_4f4e_5400_0001 };
                        break :blk ServiceResult{
                            .status = if (self.dynamic_forwarder.attemptScheduledRefresh(self)) application_framework.contract.RequestStatus.applied else application_framework.contract.RequestStatus.not_ready,
                            .reason = 0,
                        };
                    },
                    .pause_guest, .resume_guest, .set_breakpoint, .inspect_guest_memory => break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.unsupported, .reason = 0x4652_414d_455f_0001 },
                    .invoke_guest_api, .write_guest_memory, .write_host_state => break :blk ServiceResult{ .status = application_framework.contract.RequestStatus.denied, .reason = 0x4755_4553_545f_0002 },
                }
            } else ServiceResult{ .status = application_framework.contract.RequestStatus.invalid, .reason = 0 };
            _ = self.application_framework.complete(request.request_id, result.status, result.reason);
        }
    }

    pub fn logGraphicsHealthContract(self: *MachOState) void {
        const H = graphics_health_contract;
        const ledger = &self.graphics_health;
        const report = ledger.report();
        machoCapturePrint(
            "macho-processor: GRAPHICS HEALTH CONTRACT: schema={d} satisfied={d} degraded={d} blocked={d} untested={d} observed={d}/{d} step={d} fingerprint=0x{x}; {s}\n",
            .{
                @as(u16, graphics_health_contract.schema_version),
                report.satisfied,
                report.degraded,
                report.blocked,
                report.untested,
                report.satisfied + report.degraded + report.blocked,
                report.total,
                self.executed_steps,
                ledger.fingerprint(),
                ledger.verdict(),
            },
        );
        inline for (@typeInfo(H.Path).@"enum".fields) |field| {
            const path: H.Path = @enumFromInt(field.value);
            const path_report = ledger.pathReport(path);
            machoCapturePrint(
                "  health path={s: <16} complete={s} progress={d}/{d} satisfied={d} degraded={d} blocked={d} untested={d} first_missing={s}\n",
                .{
                    path.label(),
                    if (path_report.complete()) "YES" else "NO",
                    path_report.percent(),
                    path_report.total,
                    path_report.satisfied,
                    path_report.degraded,
                    path_report.blocked,
                    path_report.untested,
                    if (path_report.first_missing) |missing| missing.label() else "<none>",
                },
            );
        }
        inline for (@typeInfo(H.Layer).@"enum".fields) |field| {
            const layer: H.Layer = @enumFromInt(field.value);
            const layer_report = ledger.layerReport(layer);
            machoCapturePrint(
                "  health layer={s: <16} progress={d}% satisfied={d} degraded={d} blocked={d} untested={d}\n",
                .{ layer.label(), layer_report.percent(), layer_report.satisfied, layer_report.degraded, layer_report.blocked, layer_report.untested },
            );
        }
        inline for (@typeInfo(H.Stage).@"enum".fields) |field| {
            const stage: H.Stage = @enumFromInt(field.value);
            const entry = ledger.entry(stage);
            machoCapturePrint(
                "  health stage={s: <38} state={s: <9} owner={s: <16} layer={s: <14} count={d} first={d} last={d} source_mask=0x{x} note={s}\n",
                .{ stage.label(), entry.state.label(), stage.owner().label(), stage.layer().label(), entry.count, entry.first_step, entry.last_step, entry.source_mask, entry.note() },
            );
        }
    }

    pub fn logApplicationController(self: *MachOState, decision: application_controller.Decision) void {
        machoCapturePrint(
            "macho-processor: APPLICATION CONTROLLER: epoch={d} observations={d} transitions={d} phase={s} action={s} blocker={s} secondary={s} domain={s} step={d} quiet(guest/ring/pm4/presenter)={d}/{d}/{d}/{d} host_action_authorized={s} host_drains={d} host_refreshes={d} guest_boundary_refusals={d}; guest-owned decisions remain observational\n",
            .{
                self.application_controller.run_epoch,
                self.application_controller.observations,
                self.application_controller.transitions,
                decision.phase.label(),
                decision.action.label(),
                decision.blocker.label(),
                decision.secondary_blocker.label(),
                decision.domain.label(),
                decision.step,
                decision.guest_quiet_steps,
                decision.ring_quiet_steps,
                decision.pm4_quiet_steps,
                decision.presenter_quiet_steps,
                if (decision.host_action_authorized) "YES" else "NO",
                self.application_controller_host_drains,
                self.application_controller_host_refreshes,
                self.application_controller.guest_boundary_refusals,
            },
        );
    }

    pub fn logApplicationFramework(self: *MachOState) void {
        const snapshot = self.application_framework.snapshot();
        const mode: application_framework.contract.Mode = @enumFromInt(snapshot.mode);
        machoCapturePrint(
            "macho-processor: APPLICATION FRAMEWORK: mode={s} sequence={d} events(retained/total/dropped)={d}/{d}/{d} requests(total/queued/applied/denied)={d}/{d}/{d}/{d} equivalence(checks/matches/mismatches)={d}/{d}/{d} last_guest(step/rip)=({d},0x{x}) application_id=0x{x}\n",
            .{
                mode.label(),
                snapshot.sequence,
                snapshot.events_retained,
                snapshot.events_total,
                snapshot.events_dropped,
                snapshot.requests_total,
                snapshot.requests_queued,
                snapshot.requests_applied,
                snapshot.requests_denied,
                snapshot.equivalence_checks,
                snapshot.equivalence_matches,
                snapshot.equivalence_mismatches,
                snapshot.last_guest_step,
                snapshot.last_guest_rip,
                snapshot.application_id,
            },
        );
        const retained: usize = @intCast(@min(snapshot.events_retained, 8));
        if (retained == 0) return;
        const first = snapshot.events_retained - retained;
        var ordinal: usize = @intCast(first);
        while (ordinal < @as(usize, @intCast(snapshot.events_retained))) : (ordinal += 1) {
            var event: application_framework.contract.Event = .{};
            if (!self.application_framework.readEvent(ordinal, &event)) continue;
            const name = std.mem.sliceTo(event.name[0..], 0);
            const detail = std.mem.sliceTo(event.detail[0..], 0);
            machoCapturePrint(
                "  app-event seq={d} kind={d} truth={d} owner={d} domain={d} step={d} rip=0x{x} subject=0x{x} expected=0x{x} actual=0x{x} eq={d} name={s} detail={s}\n",
                .{ event.sequence, event.kind, event.truth, event.owner, event.domain, event.guest_step, event.guest_rip, event.subject, event.expected, event.actual, event.equivalence, name, detail },
            );
        }
    }

    /// Join execution-boundary facts into the strict VdSwap ledger.  This is
    /// intentionally conservative: entering the generic PM4 decoder is not
    /// authentic swap consumption, and a presenter frame is not guest output
    /// unless an authentic XE_SWAP has already been proven.
    fn refreshVdSwapContract(self: *MachOState) void {
        const at = self.executed_steps;
        const ledger = &self.gpu_vd_swap_contract;
        defer self.noteVdSwapMilestones();
        const tracepoints = &self.execution_tracepoints;

        // The producer probes.  Each is recorded on every refresh, found or
        // not, because "the tracepoint watched this export for four billion
        // steps and it never fired" and "nobody was watching" are the two
        // readings the report has to be able to tell apart — and they send a
        // reader to opposite ends of the system.
        const swap_watched = tracepoints.roleEntered(.swap);
        ledger.observeProbe(.guest_vdswap_entered, .guest_export_tracepoint, swap_watched, ledger.vdswap_calls, at);
        ledger.observeProbe(.guest_vdswap_entered, .guest_log_breadcrumb, ledger.vdswap_calls != 0, ledger.vdswap_calls, at);
        ledger.observeProbe(.vdswap_arguments_captured, .vdswap_argument_capture, ledger.arguments_observed != 0, ledger.arguments_observed, at);
        ledger.observeProbe(.guest_xe_swap_encoded, .guest_log_breadcrumb, self.guest_vdswap_packet_encoded, ledger.guest_packet_encodes, at);
        ledger.observeProbe(.vdswap_completed, .guest_log_breadcrumb, self.guest_vdswap_entry_completed, ledger.vdswap_completions, at);
        ledger.observeProbe(.fetch_constant_encoded, .guest_log_breadcrumb, ledger.fetch_observations != 0, ledger.fetch_observations, at);
        ledger.observeProbe(.ring_write_pointer_published, .ring_geometry_capture, self.gpu_ring_publication.advances != 0, self.gpu_ring_publication.advances, at);
        ledger.observeProbe(.ring_geometry_observed, .ring_geometry_capture, self.gpu_ring_publication.geometry != null, self.gpu_ring_watch_size, at);

        if (swap_watched) {
            ledger.observeVdSwapEntered(at, .guest_tracepoint);
        }
        if (self.guest_vdswap_packet_encoded) {
            ledger.observeGuestPacketEncoded(at, .guest_log);
        }
        if (self.guest_vdswap_entry_completed) {
            ledger.observeVdSwapCompleted(at, .guest_log);
        }
        if (self.gpu_ring_publication.advances != 0) {
            ledger.observePublication(at, .guest_publication);
        }
        if (self.gpu_ring_watch_base != 0 and self.gpu_ring_watch_size != 0 and
            self.gpu_ring_publication.geometry != null)
        {
            ledger.observeRingGeometry(at, .memory_mapping);
        }

        // The PM4/indirect walk now has an explicit post-consumption section.
        // These observations are deliberately sourced from the causal ledger
        // and the stateful Xenos runtime independently: seeing 24 draw
        // packets in retained memory is not the same thing as observing a
        // programmed target, a completion signal, or a guest continuation.
        const causal = &self.xenia_gpu_causal_trace;
        ledger.observeIntermediary(.{
            .pm4_state_programmed = causal.observed(.pm4_state_programmed),
            .draw_submitted = causal.observed(.first_draw_submitted),
            .draw_consumed = causal.observed(.first_draw_consumed),
            .guest_wait_observed_after_draw = causal.postDrawWaitObserved(),
        }, at, .causal_trace);
        ledger.observeProbe(.pm4_state_programmed, .causal_event_ledger, causal.observed(.pm4_state_programmed), 0, at);
        ledger.observeProbe(.draw_submitted, .causal_event_ledger, causal.observed(.first_draw_submitted), 0, at);
        ledger.observeProbe(.draw_consumed, .causal_event_ledger, causal.observed(.first_draw_consumed), 0, at);
        ledger.observeProbe(.guest_wait_observed_after_draw, .causal_event_ledger, causal.postDrawWaitObserved(), causal.wait_events_after_draw, at);

        const target = self.gpu_xenos_runtime.renderTargetEvidence();
        ledger.observeIntermediary(.{
            .render_target_state_observed = target.state_observed,
            .render_target_memory_observed = self.gpu_xenos_runtime.color_resolve_observations != 0,
            .draw_completion_signaled = self.gpu_xenos_runtime.draw_completion_signals != 0,
        }, at, .xenos_runtime);
        ledger.observeIntermediary(.{
            .draw_completion_dispatched = self.gpu_draw_completion_dispatches != 0,
        }, at, .interrupt_dispatch);
        if (causal.firstDrawConsumedStep()) |draw_step| {
            const progressed = self.gpu_ring_publication.advances > 1 and
                self.gpu_ring_publication.last_advance_step > draw_step;
            if (progressed) {
                ledger.observeIntermediary(.{
                    .guest_producer_progressed_after_draw = true,
                }, at, .guest_progress);
            }
            // The counter is live and the producer has not moved: a finding
            // about the title, not a missing observer.
            ledger.observeProbe(
                .guest_producer_progressed_after_draw,
                .guest_progress_counter,
                progressed,
                self.gpu_ring_publication.advances,
                at,
            );
        } else {
            // Nothing has consumed a draw yet, so there is no "after" to
            // measure progress against.
            ledger.recordProbe(.guest_producer_progressed_after_draw, .guest_progress_counter, .input_unavailable, 0, at);
        }

        // The tracepoint says the decoder ran, not that the packet came from
        // VdSwap.  It closes only the packet readability/shape observations;
        // the authentic-consumption stage remains closed until a provenance-
        // bearing milestone or the stateful executor proves the source.
        if (tracepoints.roleEntered(.xe_swap_decode)) {
            ledger.observePacket(.{
                .candidate_seen = true,
                .decoded = true,
                .stream_observed = true,
                .stream_validated = true,
            }, at, .command_processor_tracepoint);
        }

        if (ledger.authentic_consumptions != 0 and tracepoints.roleEntered(.command_swap)) {
            ledger.observeIssueSwap(at, .issue_swap_tracepoint);
        }
        if (ledger.authentic_consumptions != 0 and tracepoints.roleEntered(.presenter)) {
            ledger.observeOutputRefresh(at, .output_refresh_tracepoint);
        }
        // The presenter probes are gated on an authentic consumption by owner
        // rule: entering IssueSwap for a swap the command processor never
        // consumed would present a frame the title did not draw.  That is a
        // refusal, and it is recorded as one — a policy decision a reader can
        // act on, not a capability Rosette lacks.
        if (ledger.authentic_consumptions == 0) {
            for ([_]gpu.VdSwapStage{ .issue_swap_entered, .output_refresh_succeeded }) |stage| {
                ledger.recordProbe(stage, .presenter_tracepoint, .refused_by_owner, 0, at);
            }
            ledger.recordProbe(.native_presented, .native_presenter_counter, .refused_by_owner, 0, at);
        } else {
            ledger.observeProbe(.issue_swap_entered, .presenter_tracepoint, tracepoints.roleEntered(.command_swap), 0, at);
            ledger.observeProbe(.output_refresh_succeeded, .presenter_tracepoint, tracepoints.roleEntered(.presenter), 0, at);
            ledger.observeProbe(
                .native_presented,
                .native_presenter_counter,
                self.dynamic_forwarder.nativePresenterFramesPresented() != 0,
                self.dynamic_forwarder.nativePresenterFramesPresented(),
                at,
            );
        }
        ledger.observeProbe(
            .authentic_xe_swap_consumed,
            .command_processor_tracepoint,
            ledger.authentic_consumptions != 0,
            ledger.authentic_consumptions,
            at,
        );
        if (ledger.authentic_consumptions != 0 and
            self.dynamic_forwarder.nativePresenterFramesPresented() != 0 and
            self.gpu_ring_injection.injections == 0)
        {
            ledger.observeNativePresent(at, .native_present_tracepoint);
        }
        if (self.gpu_xenos_runtime.last_swap) |swap| {
            if (self.gpu_xenos_runtime.swap_count != 0 and
                self.gpu_ring_injection.injections == 0 and
                self.gpu_ring_publication.published())
            {
                ledger.observeAuthenticConsumption(
                    swap,
                    self.gpu_xenos_runtime.frontBufferFetch(),
                    at,
                    .stateful_pm4_executor,
                );
            }
        }
    }

    /// Feed first-time contract arrivals to the horizon ledger.
    ///
    /// A milestone is a boundary reached for the first time, never a counter
    /// ticking: a spin loop advances counters, and only real progress arrives
    /// somewhere it has never been. The contract mask is exactly that — a bit
    /// per boundary, set once — so the newly-set bits since the last check are
    /// the milestones and nothing else has to be inferred.
    fn noteVdSwapMilestones(self: *MachOState) void {
        const mask = self.gpu_vd_swap_contract.observed_mask;
        const fresh = mask & ~self.run_horizon_vdswap_mask;
        if (fresh == 0) return;
        self.run_horizon_vdswap_mask = mask;
        self.run_horizon.observe(.{
            .step = self.executed_steps,
            .emulated_ms = self.run_horizon.latest.emulated_ms,
            .vblanks = self.run_horizon.latest.vblanks,
            .host_seconds = self.elapsedHostSeconds(),
        });
        inline for (@typeInfo(gpu.VdSwapStage).@"enum".fields) |field| {
            const stage: gpu.VdSwapStage = @enumFromInt(field.value);
            if (fresh & gpu.vd_swap_contract.stageBit(stage) != 0) {
                self.run_horizon.noteMilestone(stage.label());
            }
        }
    }

    fn elapsedHostSeconds(self: *const MachOState) u64 {
        // The same monotonic source the heartbeat throughput uses, so the two
        // rates in the report cannot disagree about how long the run has been
        // going.
        const now = startup_observer.monotonicNanoseconds();
        if (self.run_started_at_ns == 0 or now <= self.run_started_at_ns) return 0;
        return (now - self.run_started_at_ns) / std.time.ns_per_s;
    }

    /// Print whether the run stopped because the guest stopped, or because the
    /// run did.
    ///
    /// Every other verdict in this subsystem is built on "X has not happened",
    /// and none of them knew how much of the guest's own timeline the run
    /// covered. A title that reached its newest milestone at 93% of the way
    /// through a run has not stalled; it ran out of wall clock, and a longer
    /// run is the entire fix. Reading that as a stall costs weeks.
    pub fn logRunHorizon(self: *MachOState) void {
        const ledger = &self.run_horizon;
        ledger.observe(.{
            .step = self.executed_steps,
            .emulated_ms = ledger.latest.emulated_ms,
            .vblanks = ledger.latest.vblanks,
            .host_seconds = self.elapsedHostSeconds(),
        });

        // The independent axis: the producer's own publication counter. A
        // frozen axis alone never convicts — the verdict requires a long quiet
        // tail as well — but without one a quiet run cannot be called dead.
        const axis_frozen = self.gpu_ring_publication.advances != 0 and
            self.gpu_vd_swap_contract.observed(.draw_consumed) and
            !self.gpu_vd_swap_contract.observed(.guest_producer_progressed_after_draw);
        const verdict = ledger.verdict(axis_frozen);

        machoCapturePrint(
            "macho-processor: RUN HORIZON: verdict={s} milestones={d} last={s} progress={d}% quiet_tail={d}% step={d} emulated_ms={d} vblanks={d} host_s={d} rate={d}ms/s axis_frozen={s}; {s}\n",
            .{
                verdict.label(),
                ledger.milestones_reached,
                if (ledger.last_milestone_name.len != 0) ledger.last_milestone_name else "<none>",
                ledger.progressPercent(),
                ledger.quietTailPercent(),
                ledger.latest.step,
                ledger.latest.emulated_ms,
                ledger.latest.vblanks,
                ledger.latest.host_seconds,
                ledger.emulatedMsPerHostSecond(),
                if (axis_frozen) "YES" else "NO",
                verdict.guidance(),
            },
        );

        // The projection is what turns "run longer" from advice into a
        // decision. Four minutes and nine hours are different conversations,
        // and until the number is on the page the choice is made blind.
        inline for (.{ @as(u64, 10_000), @as(u64, 30_000), @as(u64, 60_000) }) |target| {
            const projection = ledger.project(target);
            if (projection.known()) {
                machoCapturePrint(
                    "  horizon projection: reaching emulated {d}ms needs about {d} more host seconds at the {d}ms/s this run achieved\n",
                    .{ target, projection.host_seconds_required orelse 0, projection.emulated_ms_per_host_second },
                );
            } else {
                machoCapturePrint(
                    "  horizon projection: emulated {d}ms is unprojectable — the run produced no measurable emulated-time rate, so run length cannot be reasoned about yet\n",
                    .{target},
                );
            }
        }

        for (ledger.milestones[0..ledger.milestone_count]) |milestone| {
            machoCapturePrint(
                "  milestone {s: <38} step={d: <14} emulated_ms={d: <8} vblanks={d}\n",
                .{ milestone.name, milestone.step, milestone.emulated_ms, milestone.vblanks },
            );
        }
        if (ledger.milestones_dropped != 0) {
            machoCapturePrint(
                "  RUN HORIZON: {d} milestones past the retained window; the verdict still uses the newest, the list above does not show it\n",
                .{ledger.milestones_dropped},
            );
        }
    }

    /// Print why each unmet stage is unmet, one line per stage.
    ///
    /// `logVdSwapContract` prints *what* is observed and names a single linear
    /// frontier.  On a run whose producer never presents, that frontier is
    /// always `guest VdSwap entered`, and the other eighteen unmet stages print
    /// as an undifferentiated wall of `state=NO count=0`.  Some of those are
    /// genuinely downstream of the producer.  Some are independent findings
    /// against the command processor.  Some are Rosette's own blind spots.
    /// They are three different pieces of work for three different owners, and
    /// nothing in the existing report distinguishes them.
    ///
    /// This does.  Every unmet stage is classified against its real causal
    /// prerequisites rather than its position in the total order, and against
    /// what its probes actually achieved rather than what they found.
    pub fn logVdSwapTrace(self: *MachOState) void {
        self.refreshVdSwapContract();
        const ledger = &self.gpu_vd_swap_contract;
        const totals = ledger.diagnosisSummary();
        const actionable = ledger.actionableMask();

        machoCapturePrint(
            "macho-processor: VD SWAP TRACE: met={d}/{d} walls={d} (findings={d} starved={d} unprobed={d}) downstream={d} probe_records={d} unlisted={d} step={d}; {s}\n",
            .{
                totals.met,
                gpu.vd_swap_contract.stage_count,
                totals.actionable + totals.starved + totals.unprobed,
                totals.actionable,
                totals.starved,
                totals.unprobed,
                totals.blocked_upstream,
                ledger.probes.records,
                ledger.probes.unlisted_probe_records,
                self.executed_steps,
                totals.verdict(),
            },
        );

        if (ledger.primaryWall()) |wall| {
            machoCapturePrint(
                "  VD SWAP PRIMARY WALL: stage={s} chain={s} owner={s} attribution={s} decided_by={s}/{s} detail={d}; {s}\n",
                .{
                    wall.stage.label(),
                    wall.chain.label(),
                    wall.stage.owner().label(),
                    wall.attribution.label(),
                    if (wall.decided_by) |which| which.label() else "<none>",
                    wall.decided_outcome.label(),
                    wall.detail,
                    wall.attribution.guidance(),
                },
            );
        }

        // Per-chain frontiers.  A stalled producer and a fully reached
        // transport chain are both true at once, and one linear frontier can
        // only ever report the first.
        inline for (@typeInfo(gpu.VdSwapChain).@"enum".fields) |field| {
            const chain: gpu.VdSwapChain = @enumFromInt(field.value);
            const met = ledger.chainMet(chain);
            const total = gpu.vd_swap_contract.chainStageCount(chain);
            machoCapturePrint(
                "  vd-swap chain {s: <13} met={d}/{d} frontier={s: <38} owner={s: <24}; {s}\n",
                .{
                    chain.label(),
                    met,
                    total,
                    if (ledger.chainFrontier(chain)) |stage| stage.label() else "<complete>",
                    if (ledger.chainFrontier(chain)) |stage| stage.owner().label() else "-",
                    chain.meaning(),
                },
            );
        }

        // One line per unmet stage, in contract order, with the probes that
        // decided it.  A met stage is already covered by the stage table in
        // `logVdSwapContract`; repeating it here would bury the nineteen lines
        // this report exists to make readable.
        inline for (@typeInfo(gpu.VdSwapStage).@"enum".fields) |field| {
            const stage: gpu.VdSwapStage = @enumFromInt(field.value);
            const diagnosis = ledger.diagnose(stage);
            if (diagnosis.attribution != .met) {
                machoCapturePrint(
                    "  vd-swap gap {s: <38} chain={s: <13} {s: <16} owner={s: <24} wall={s: <3} blocked_by={s: <38} probes={d}/{d} evidence={d} starved={d} decided={s}/{s} detail={d}\n",
                    .{
                        stage.label(),
                        diagnosis.chain.label(),
                        diagnosis.attribution.label(),
                        stage.owner().label(),
                        if (actionable & gpu.vd_swap_contract.stageBit(stage) != 0) "YES" else "NO",
                        if (diagnosis.blocked_by) |prerequisite| prerequisite.label() else "-",
                        diagnosis.probes_attempted,
                        diagnosis.probes_total,
                        diagnosis.probes_with_evidence,
                        diagnosis.probes_starved,
                        if (diagnosis.decided_by) |which| which.label() else "<none>",
                        diagnosis.decided_outcome.label(),
                        diagnosis.detail,
                    },
                );
            }
        }

        // The probe grid for the walls only.  Thirteen downstream stages times
        // sixteen probes is noise; the walls are where a reader has to know
        // exactly which evidence path came back with what.
        inline for (@typeInfo(gpu.VdSwapStage).@"enum".fields) |field| {
            const stage: gpu.VdSwapStage = @enumFromInt(field.value);
            const diagnosis = ledger.diagnose(stage);
            if (diagnosis.actionable()) {
                inline for (@typeInfo(gpu.VdSwapProbe).@"enum".fields) |probe_field| {
                    const which: gpu.VdSwapProbe = @enumFromInt(probe_field.value);
                    {
                        if (probeSuppliesStage(stage, which)) {
                            const cell = ledger.probes.cell(stage, which);
                            machoCapturePrint(
                                "    probe {s: <38} {s: <30} {s: <18} latest={s: <18} attempts={d} evidence={d} starved={d} detail={d} first={d} last={d}\n",
                                .{
                                    stage.label(),
                                    which.label(),
                                    cell.outcome.label(),
                                    cell.latest.label(),
                                    cell.attempts,
                                    cell.evidence_attempts,
                                    cell.starved_attempts,
                                    cell.detail,
                                    cell.first_step,
                                    cell.last_step,
                                },
                            );
                        }
                    }
                }
            }
        }

        machoCapturePrint(
            "  VD SWAP EXECUTOR: retained(executions/refusals)={d}/{d} span_epoch={d} payload_epoch={d} publication_advances={d} batches={d} ring_dwords_consumed={d} packet_errors={d}; the stateful command processor is the only source of render-target registers, EDRAM resolves and draw-completion events. Zero executions means every stage below it is unobserved rather than false\n",
            .{
                self.gpu_xenos_retained_executions,
                self.gpu_xenos_retained_refusals,
                self.gpu_xenos_last_ring_epoch,
                self.gpu_xenos_last_payload_epoch,
                self.gpu_ring_publication.advances,
                self.gpu_xenos_runtime.batches,
                self.gpu_xenos_runtime.ring_dwords_consumed,
                self.gpu_xenos_runtime.packet_errors,
            },
        );
    }

    fn probeSuppliesStage(stage: gpu.VdSwapStage, which: gpu.VdSwapProbe) bool {
        for (gpu.vd_swap_contract.probesFor(stage)) |listed| {
            if (listed == which) return true;
        }
        return false;
    }

    /// Print the complete VdSwap/PM4 ledger.  The broad graphics ladder still
    /// has value for window/bootstrap work; this report is the packet-level
    /// evidence needed to decide whether a front-buffer substitution is even
    /// legal.
    pub fn logVdSwapContract(self: *MachOState) void {
        self.refreshVdSwapContract();
        const ledger = &self.gpu_vd_swap_contract;
        const frontier = ledger.frontier();
        var source_buffer: [512]u8 = undefined;
        const sources = ledger.sourceNames(&source_buffer);
        var offset_buffer: [32]u8 = undefined;
        const packet_offset = if (ledger.last_packet_offset) |offset|
            std.fmt.bufPrint(&offset_buffer, "{d}", .{offset}) catch "?"
        else
            "<none>";
        machoCapturePrint(
            "macho-processor: VD SWAP CONTRACT: met={d}/{d} frontier={s} owner={s} blocker={s} sources={s} step={d} calls={d} args={d} candidates={d} invalid={d} conflicts={d} support(geometry/projection/stream/validated/indirects/candidates)={d}/{d}/{d}/{d}/{d}/{d} packets(readable/decoded/authentic/malformed)={d}/{d}/{d}/{d} packet_candidates(seen/readable/decoded/fetch_decoded/auth_missing)={d}/{d}/{d}/{d}/{d}\n",
            .{
                frontier.met,
                frontier.total,
                if (frontier.stage) |stage| stage.label() else "<complete>",
                frontier.owner.label(),
                frontier.blocker.label(),
                if (sources.len != 0) sources else "<none>",
                self.executed_steps,
                ledger.vdswap_calls,
                ledger.arguments_observed,
                ledger.candidate_count,
                ledger.invalid_candidate_count,
                ledger.frontbuffer_conflicts,
                ledger.ring_geometry_observations,
                ledger.projection_readable_observations,
                ledger.stream_observations,
                ledger.stream_validation_observations,
                ledger.indirect_resolution_observations,
                ledger.candidate_observations,
                ledger.readable_packet_observations,
                ledger.decoded_packet_observations,
                ledger.authentic_consumptions,
                ledger.malformed_packets,
                ledger.candidate_observations,
                ledger.readable_packet_observations,
                ledger.decoded_packet_observations,
                ledger.fetch_decoded_observations,
                ledger.authentic_missing_descriptions,
            },
        );
        machoCapturePrint(
            "  VD SWAP CONTRACT DETAIL: packet_anomalies(truncated/desync)={d}/{d} PM4(root/nested/indirect/draw/swap)={d}/{d}/{d}/{d}/{d} dwords(examined/scanned/span)={d}/{d}/{d} packet_offset={s}; {s}\n",
            .{
                ledger.truncated_observations,
                ledger.desynchronised_observations,
                ledger.root_packets,
                ledger.nested_packets,
                ledger.indirect_packets,
                ledger.draw_packets,
                ledger.swap_packets,
                ledger.dwords_examined,
                ledger.dwords_scanned,
                ledger.span_dwords,
                packet_offset,
                frontier.blocker.guidance(),
            },
        );
        machoCapturePrint(
            "  VD SWAP INTERMEDIARY: PM4(state/submitted/consumed)={s}/{s}/{s} render_target(state/memory)={s}/{s} completion(signaled/dispatched)={s}/{s} guest(wait_after_draw/progress_after_draw)={s}/{s} observations={d}\n",
            .{
                if (ledger.observed(.pm4_state_programmed)) "YES" else "NO",
                if (ledger.observed(.draw_submitted)) "YES" else "NO",
                if (ledger.observed(.draw_consumed)) "YES" else "NO",
                if (ledger.observed(.render_target_state_observed)) "YES" else "NO",
                if (ledger.observed(.render_target_memory_observed)) "YES" else "NO",
                if (ledger.observed(.draw_completion_signaled)) "YES" else "NO",
                if (ledger.observed(.draw_completion_dispatched)) "YES" else "NO",
                if (ledger.observed(.guest_wait_observed_after_draw)) "YES" else "NO",
                if (ledger.observed(.guest_producer_progressed_after_draw)) "YES" else "NO",
                ledger.intermediary_observations,
            },
        );
        const target = self.gpu_xenos_runtime.renderTargetEvidence();
        machoCapturePrint(
            "  XENOS TARGET EVIDENCE: state={s} plausible={s} color(base_tile/format)={d}/{d} depth(base_tile/format)={d}/{d} surface(pitch/msaa/mask)={d}/{d}/{d} raw(color/depth/surface)=0x{x:0>8}/0x{x:0>8}/0x{x:0>8}\n",
            .{
                if (target.state_observed) "YES" else "NO",
                if (target.plausible) "YES" else "NO",
                target.color_base_tiles,
                target.color_format,
                target.depth_base_tiles,
                target.depth_format,
                target.surface_pitch_pixels,
                target.msaa_mode,
                target.color_mask,
                target.raw_color_info,
                target.raw_depth_info,
                target.raw_surface_info,
            },
        );
        machoCapturePrint(
            "  XENOS COMPLETION EVIDENCE: draw_signals={d} draw_dispatch(attempts/success/failures)={d}/{d}/{d} color_resolves={d} causal_post_draw(wait/signal)={d}/{d}; a draw packet is not a frame until these owner boundaries are observed\n",
            .{
                self.gpu_xenos_runtime.draw_completion_signals,
                self.gpu_draw_completion_dispatch_attempts,
                self.gpu_draw_completion_dispatches,
                self.gpu_draw_completion_dispatch_failures,
                self.gpu_xenos_runtime.color_resolve_observations,
                self.xenia_gpu_causal_trace.wait_events_after_draw,
                self.xenia_gpu_causal_trace.signal_events_after_draw,
            },
        );
        machoCapturePrint(
            "  vd-swap provenance: entry_buffer_ptr=0x{x:0>8} entry_fetch_ptr=0x{x:0>8} entry_frontbuffer_ptr=0x{x:0>8} encoded_buffer_phys=0x{x:0>8} encoded_packet_dword={d} encoded_packet_dwords={d} encoded_geometry={s} encoding_mismatches={d}\n",
            .{
                ledger.arguments.command_buffer,
                ledger.arguments.fetch_pointer,
                ledger.arguments.frontbuffer_pointer,
                ledger.encoded_command_buffer,
                ledger.encoded_packet_offset,
                ledger.encoded_packet_dwords,
                if (ledger.encoded_packet_geometry_observed) "YES" else "NO",
                ledger.packet_encoding_mismatches,
            },
        );
        inline for (@typeInfo(gpu.VdSwapStage).@"enum".fields) |field| {
            const stage: gpu.VdSwapStage = @enumFromInt(field.value);
            const record = ledger.observation(stage);
            machoCapturePrint(
                "  vd-swap stage={s: <38} state={s: <3} owner={s: <28} count={d} first={d} last={d} source_mask=0x{x}\n",
                .{
                    stage.label(),
                    if (record.seen) "YES" else "NO",
                    stage.owner().label(),
                    record.count,
                    record.first_step,
                    record.last_step,
                    record.source_mask,
                },
            );
        }
        if (ledger.active_frontbuffer) |swap| {
            machoCapturePrint(
                "  vd-swap frontbuffer active=0x{x:0>8} extent={d}x{d} source={s} plausible={s} packet_offset={s}\n",
                .{
                    swap.frontbuffer_physical_address,
                    swap.width,
                    swap.height,
                    ledger.active_frontbuffer_source.label(),
                    if (ledger.frontbufferKnown()) "YES" else "NO",
                    packet_offset,
                },
            );
        } else {
            machoCapturePrint(
                "  vd-swap frontbuffer active=<none> arguments={s} fetch={s}\n",
                .{ if (ledger.arguments.frontbuffer != null) "YES" else "NO", if (ledger.arguments.fetch != null) "YES" else "NO" },
            );
        }
        for (ledger.candidates[0..ledger.candidate_count]) |candidate| {
            if (candidate.description) |swap| machoCapturePrint(
                "  vd-swap candidate source={s} address=0x{x:0>8} extent={d}x{d} plausible={s} observations={d} first_step={d}\n",
                .{
                    candidate.source.label(),
                    swap.frontbuffer_physical_address,
                    swap.width,
                    swap.height,
                    if (candidate.plausible) "YES" else "NO",
                    candidate.observations,
                    candidate.first_step,
                },
            );
        }
    }

    /// The kernel surface: what a title reads before it will present, and
    /// whether anything supplied it.
    ///
    /// Printed with the contract because the two answer different halves of the
    /// same question. The contract says which precondition is unmet and who
    /// owns it; the surface says whether the unmet one is unmet because a
    /// *value* is missing — the case a call-counting ladder cannot see at all.
    pub fn logKernelSurface(self: *MachOState) void {
        const surface = &self.gpu_kernel_surface;
        const finding = surface.finding();
        machoCapturePrint(
            "macho-processor: KERNEL SURFACE: imported={d} usable={d} unpopulated_imported={d} blocking={s} step={d}; {s}\n",
            .{
                finding.imported_count,
                finding.usable_count,
                finding.unpopulated_imported,
                if (finding.blocking) |which| which.name() else "<none>",
                self.executed_steps,
                if (finding.blocking) |which|
                    which.guidance()
                else
                    "every required kernel export the title imported holds a usable value; an absent frame is not explained by this surface",
            },
        );
        inline for (@typeInfo(gpu.KernelExport).@"enum".fields) |field| {
            const which: gpu.KernelExport = @enumFromInt(field.value);
            if (surface.imported(which) or which.isVariable()) machoCapturePrint(
                "  export 0x{x:0>3} {s: <12} {s: <9} {s}{s}\n",
                .{
                    which.ordinal(),
                    surface.population(which).label(),
                    if (which.isVariable()) "variable" else "function",
                    which.name(),
                    if (surface.imported(which)) "" else " (not imported by this title)",
                },
            );
        }
        var pending: [gpu.kernel_surface.export_count]gpu.KernelExport = undefined;
        const work = surface.harnessPopulationWork(&pending);
        for (work) |which| {
            machoCapturePrint(
                "macho-processor: KERNEL SURFACE: harness population outstanding: {s} ({d} bytes at 0x{x}) — {s}\n",
                .{ which.name(), which.byteSize(), self.gpu_kernel_surface_addresses.lookup(which.ordinal()) orelse 0, which.guidance() },
            );
        }
        if (work.len == 0) return;
        machoCapturePrint(
            "macho-processor: KERNEL SURFACE: populating a kernel *variable* is supplying platform state the real kernel already wrote, which is a legitimate harness action. Entering a kernel *function* on the title's behalf is not, and is refused by the contract's owner rule\n",
            .{},
        );
    }

    /// What the two dereferences behind each kernel variable actually found.
    ///
    /// Printed next to the export surface rather than replacing it, because the
    /// two answer different questions: that one says whether the title imported
    /// the export at all, this one says what a reader of it would get. The
    /// column that matters is `writer`: a zero the *title* was supposed to
    /// write is progress information, and a zero the *kernel* was supposed to
    /// write is harness work.
    /// One big-endian dword out of the emulated console's virtual address
    /// space. Null when the address space is not modelled yet or the page is
    /// not readable — which are different from a dword that reads zero, and the
    /// caller has to be able to tell them apart.
    pub fn readConsoleDword(self: *MachOState, console_address: u32) ?u32 {
        if (console_address == 0) return null;
        const host = self.xenia_memory_views.virtualHostAddress(console_address) orelse return null;
        const bytes = self.guestMemoryConst(host, 4) orelse return null;
        return std.mem.readInt(u32, bytes[0..4], .big);
    }

    /// Write one big-endian dword into the console's virtual address space.
    ///
    /// The only mutation this subsystem performs on console memory, and it is
    /// gated by the owner rule before it is ever called. Returns whether the
    /// write landed, because a provisioning step that silently did nothing is
    /// worse than one that did not run: the report would say the platform state
    /// was supplied.
    pub fn writeConsoleDword(self: *MachOState, console_address: u32, value: u32) bool {
        if (console_address == 0) return false;
        const host = self.xenia_memory_views.virtualHostAddress(console_address) orelse return false;
        const bytes = self.guestMemory(host, 4) orelse return false;
        std.mem.writeInt(u32, bytes[0..4], value, .big);
        return true;
    }

    /// Read every kernel variable slot whose address is known, then supply the
    /// kernel-owned ones the emulator left empty.
    ///
    /// This exists because the emulator's own per-ordinal report is the only
    /// thing that used to trigger a read, and that report **omits** the two
    /// variables the kernel is responsible for. `VdGpuClockInMHz` and
    /// `VdHSIOCalibrationLock` were therefore never looked at once in a run:
    /// they were reported `unresolved`, which reads as "nothing to see" and is
    /// actually "nobody looked". The slot addresses come from the export table
    /// dump, which lists every import whether or not the emulator narrates it,
    /// so the measurement never depended on the emulator's cooperation.
    ///
    /// Provisioning is deliberately narrow. A variable the *title* writes is
    /// never touched: a device pointer invented here points at nothing, and the
    /// crash lands three subsystems from the invention. A variable the *kernel*
    /// writes is platform state the real console established before the title
    /// ran, and supplying it is the entire job of a harness.
    pub fn refreshKernelVariables(self: *MachOState) void {
        const surface = &self.gpu_kernel_variables;
        const custody = &self.gpu_provisioning_custody;
        const at = self.executed_steps;

        // The boundary a provisioning write has to beat.  `VdInitializeEngines`
        // is the first display bring-up export the title enters, and it is the
        // point past which these variables have been read and the decision made
        // against whatever they held.  A write after this step is correct and
        // changes nothing.
        const engines = self.gpu_bootstrap.observations[@intFromEnum(gpu.Step.initialize_engines)];
        if (engines.seen) custody.noteConsumerForAll(engines.first_step);

        inline for (.{
            gpu.KernelVariable.global_device,    gpu.KernelVariable.global_xam_device,
            gpu.KernelVariable.gpu_clock_in_mhz, gpu.KernelVariable.hsio_calibration_lock,
        }) |which| {
            _ = custody.track(
                which.ordinal(),
                which.name(),
                if (which.writer().harnessMayWrite()) .console_kernel else .guest_title,
            );
            const slot_address = self.gpu_kernel_surface_addresses.lookup(which.ordinal()) orelse 0;
            if (slot_address == 0) {
                custody.noteRefusal(which.ordinal(), .address_unknown);
            } else {
                surface.observeImport(which, true, slot_address);
                if (self.readConsoleDword(slot_address)) |slot_value| {
                    surface.observeSlot(which, slot_value);
                    if (gpu.kernel_variables.plausiblePointer(slot_value) and
                        !gpu.kernel_variables.isUnimplementedSentinel(slot_value, which.ordinal()))
                    {
                        if (self.readConsoleDword(slot_value)) |storage| {
                            surface.observeStorage(which, storage);
                            // Anything in there the harness did not write came
                            // from somewhere else.  That is how adoption and
                            // divergence are detected without a write hook on
                            // the address.
                            custody.observeStorage(which.ordinal(), storage, at);
                        }
                    }
                }
            }
            self.provisionKernelVariable(which);
        }
    }

    /// Provision platform state at the earliest moment its address exists.
    ///
    /// This used to happen only from a diagnostic heartbeat, and the heartbeat
    /// interval is a hundred million guest steps.  The title reads these
    /// variables during display bring-up, orders of magnitude earlier, gets a
    /// zero and takes its early-return path — permanently, because nothing
    /// re-reads them.  By the first heartbeat the values were written, the
    /// variables reported `populated`, no ladder rung was blocked, and the
    /// title had been wedged for the entire run.
    ///
    /// The earliest possible moment is when the emulator dumps its export
    /// table: before that the slot address does not exist, so there is nowhere
    /// to write.  Calling this then is what makes the write early enough to
    /// matter.  It is cheap, idempotent, and refuses by the same owner rule as
    /// every other path — a title-owned variable is still never written.
    pub fn provisionPlatformStateNow(self: *MachOState) void {
        self.gpu_provisioning_early_attempts +|= 1;
        self.refreshKernelVariables();
    }

    /// Supply one kernel-owned variable, if the owner rule allows it and the
    /// storage is reachable.
    fn provisionKernelVariable(self: *MachOState, which: gpu.KernelVariable) void {
        const custody = &self.gpu_provisioning_custody;
        switch (self.gpu_kernel_variables.writeDecision(which)) {
            .refused_title_owned => custody.noteRefusal(which.ordinal(), .not_harness_owned),
            .refused_already_populated => custody.noteRefusal(which.ordinal(), .already_present),
            .allowed => |value| {
                const slot_value = self.gpu_kernel_variables.entry(which).slot_value;
                if (!self.writeConsoleDword(slot_value, value)) {
                    custody.noteRefusal(which.ordinal(), .storage_unwritable);
                    self.gpu_kernel_variable_write_failures +|= 1;
                    machoCapturePrint(
                        "macho-processor: KERNEL VARIABLES: could not write {s} = 0x{x} at console 0x{x:0>8}; the storage the slot points at is not writable from here, so the platform state stays unsupplied and the title will read whatever is there\n",
                        .{ which.name(), value, slot_value },
                    );
                    return;
                }
                _ = self.gpu_kernel_variables.noteHarnessWrite(which);
                self.gpu_kernel_variable_writes +|= 1;
                custody.noteHarnessWrite(which.ordinal(), value, self.executed_steps);
                const record = custody.entry(which.ordinal());
                machoCapturePrint(
                    "macho-processor: KERNEL VARIABLES: supplied {s} = 0x{x} at console 0x{x:0>8} (harness write #{d}) timing={s} guest_steps={d}. This is platform state the real kernel established before the title ran; the title owns nothing here and nothing about its behaviour has been fabricated — {s}\n",
                    .{
                        which.name(),
                        value,
                        slot_value,
                        self.gpu_kernel_variable_writes,
                        if (record) |entry| entry.timing().label() else "unknown",
                        self.executed_steps,
                        which.meaning(),
                    },
                );
            },
            else => {},
        }
    }

    /// Print who provisioned each piece of platform state and whether it was
    /// in time.
    ///
    /// `KERNEL VARIABLES` answers whether a value is present. That question is
    /// always answered "yes" by the time anyone asks it, which is exactly why
    /// a late write survives every check in the subsystem. This answers the two
    /// questions that outlive it: did the write beat the consumer, and did the
    /// resource's real owner ever agree.
    pub fn logProvisioningCustody(self: *MachOState) void {
        const custody = &self.gpu_provisioning_custody;
        const totals = custody.summary();
        const finding = totals.finding();
        machoCapturePrint(
            "macho-processor: PROVISIONING CUSTODY: finding={s} tracked={d} provisioned={d} preboot={d} in_time={d} LATE={d} unknown={d} adopted={d} load_bearing={d} contested={d} diverged={d} unprovisioned={d} refusals={d} address_unknown_attempts={d} early_attempts={d} step={d}; {s}\n",
            .{
                finding.label(),
                totals.tracked,
                totals.provisioned,
                totals.preboot,
                totals.provisioned -| (totals.preboot + totals.late + totals.unknown_timing),
                totals.late,
                totals.unknown_timing,
                totals.adopted,
                totals.load_bearing,
                totals.contested,
                totals.diverged,
                totals.unprovisioned,
                totals.refusals,
                totals.address_unknown_attempts,
                self.gpu_provisioning_early_attempts,
                self.executed_steps,
                finding.guidance(),
            },
        );
        if (custody.blocking()) |record| {
            machoCapturePrint(
                "  PROVISIONING BLOCKER: {s} owner={s} custody={s} timing={s} divergence={s}; {s}\n",
                .{
                    record.name,
                    record.owner.label(),
                    record.custody().label(),
                    record.timing().label(),
                    record.divergence().label(),
                    if (record.timing().missedItsConsumer())
                        record.timing().guidance()
                    else if (record.divergence() == .diverged)
                        record.divergence().guidance()
                    else
                        record.last_refusal.guidance(),
                },
            );
        }
        for (custody.records[0..custody.count]) |record| {
            machoCapturePrint(
                "  custody {s: <24} owner={s: <16} {s: <20} timing={s: <16} {s: <12} harness(value/step/writes)=0x{x:0>8}/{d}/{d} owner_write(value/step)=0x{x:0>8}/{d} consumer_step={d} refusal={s} refusals={d}\n",
                .{
                    record.name,
                    record.owner.label(),
                    record.custody().label(),
                    record.timing().label(),
                    record.divergence().label(),
                    record.harness_value,
                    record.harness_step,
                    record.harness_writes,
                    record.owner_value,
                    record.owner_step,
                    record.consumer_step orelse 0,
                    record.last_refusal.label(),
                    record.refusals,
                },
            );
        }
        if (custody.dropped != 0) {
            machoCapturePrint(
                "  PROVISIONING CUSTODY: {d} resources did not fit the retained window; the list above is not the whole picture\n",
                .{custody.dropped},
            );
        }
    }

    pub fn logKernelVariables(self: *MachOState) void {
        self.refreshKernelVariables();
        const surface = &self.gpu_kernel_variables;
        const finding = surface.finding();
        machoCapturePrint(
            "macho-processor: KERNEL VARIABLES: imported={d} usable={d} blocking={s} harness_writable_outstanding={d} harness_writes={d} write_failures={d} step={d}; {s}\n",
            .{
                finding.imported_count,
                finding.usable_count,
                if (finding.blocking) |which| which.name() else "<none>",
                finding.harness_writable_outstanding,
                self.gpu_kernel_variable_writes,
                self.gpu_kernel_variable_write_failures,
                self.executed_steps,
                if (finding.blocking) |which|
                    which.meaning()
                else
                    "no kernel variable the title imported is broken in a way the emulator caused. A variable reading zero because the title has not written it yet is reported below and is not a defect",
            },
        );
        inline for (.{
            gpu.KernelVariable.global_device,    gpu.KernelVariable.global_xam_device,
            gpu.KernelVariable.gpu_clock_in_mhz, gpu.KernelVariable.hsio_calibration_lock,
        }) |which| {
            const record = surface.entry(which);
            machoCapturePrint(
                "  variable 0x{x:0>3} {s: <20} {s: <13} writer={s: <6} slot=0x{x:0>8} -> 0x{x:0>8} storage=0x{x:0>8} bytes={d} harness_writes={d}\n",
                .{
                    which.ordinal(),
                    which.name(),
                    record.state.label(),
                    @tagName(which.writer()),
                    record.slot_address,
                    record.slot_value,
                    record.storage_value,
                    which.storageBytes(),
                    record.harness_writes,
                },
            );
        }
        inline for (.{
            gpu.KernelVariable.global_device,    gpu.KernelVariable.global_xam_device,
            gpu.KernelVariable.gpu_clock_in_mhz, gpu.KernelVariable.hsio_calibration_lock,
        }) |which| {
            if (surface.entry(which).imported) {
                switch (surface.writeDecision(which)) {
                    .allowed => |value| machoCapturePrint(
                        "macho-processor: KERNEL VARIABLES: harness may supply {s} = 0x{x} — {s}\n",
                        .{ which.name(), value, which.meaning() },
                    ),
                    else => |refusal| if (surface.entry(which).state == .storage_zero) machoCapturePrint(
                        "macho-processor: KERNEL VARIABLES: {s} reads zero and the harness will not write it: {s}\n",
                        .{ which.name(), refusal.label() },
                    ),
                }
            }
        }
    }

    /// Join every subsystem's evidence into the pre-initialisation ledger.
    ///
    /// Derived rather than maintained, like the graphics contract: each fact
    /// already exists somewhere, and the value here is the ordering check that
    /// no individual subsystem can perform because none of them sees the
    /// others' timing.
    pub fn refreshPreinitialization(self: *MachOState) void {
        const ledger = &self.gpu_preinitialization;
        const at = self.executed_steps;
        const variables = &self.gpu_kernel_variables;

        if (self.xenia_memory_views.ready()) ledger.observe(.memory_view_base_discovered, at);

        // Bound means the dereference lands somewhere, not that the storage
        // holds a value. Those are different failures with different owners,
        // and collapsing them is what made an unwritten clock look like an
        // unbound slot.
        var any_slot_bound = false;
        var every_slot_bound = true;
        inline for (.{
            gpu.KernelVariable.global_device,         gpu.KernelVariable.gpu_clock_in_mhz,
            gpu.KernelVariable.hsio_calibration_lock,
        }) |which| {
            const record = variables.entry(which);
            if (record.imported) {
                if (gpu.kernel_variables.plausiblePointer(record.slot_value)) {
                    any_slot_bound = true;
                } else {
                    every_slot_bound = false;
                }
            }
        }
        if (any_slot_bound and every_slot_bound) ledger.observe(.kernel_variable_slots_bound, at);

        inline for (.{
            .{ gpu.KernelVariable.gpu_clock_in_mhz, gpu.PreinitElement.gpu_clock_published },
            .{ gpu.KernelVariable.hsio_calibration_lock, gpu.PreinitElement.hsio_lock_initialised },
        }) |pair| {
            const record = variables.entry(pair[0]);
            if (record.state == .populated) {
                if (record.harness_writes != 0) {
                    _ = ledger.supply(pair[1], at);
                } else {
                    ledger.observe(pair[1], at);
                }
            }
        }

        // Either the emulator declared a handler for the aperture's pages, or
        // an access actually arrived. The first is reachability and the second
        // is usage; usage implies reachability, so both satisfy it.
        if (self.gpu_register_aperture_reachable or
            self.gpu_register_aperture.total_reads + self.gpu_register_aperture.total_writes != 0)
        {
            ledger.observe(.register_aperture_reachable, at);
        }
        if (self.gpu_bootstrap.seen(.initialize_engines)) ledger.observe(.engines_initialised, at);
        if (self.gpu_bootstrap.seen(.graphics_interrupt_callback)) ledger.observe(.interrupt_callback_registered, at);
        if (self.gpu_bootstrap.seen(.graphics_interrupt_dispatch)) ledger.observe(.interrupt_callback_dispatched, at);
        if (self.gpu_ring_watch_base != 0) ledger.observe(.ring_geometry_established, at);
        if (self.execution_tracepoints.roleEntered(.command_processor)) ledger.observe(.command_processor_running, at);
        if (variables.entry(.global_device).state == .populated) ledger.observe(.title_device_created, at);
        // Written means dwords exist, not that any of them was a draw. Keying
        // this on draws reported an ordering inversion in the observed run —
        // 'write pointer advanced' before 'payload written' — that was an
        // artifact of this mapping rather than anything the title did.
        if (self.gpu_ring_nonzero_dwords != 0) ledger.observe(.ring_payload_written, at);
        if (self.gpu_ring_publication.advances != 0) ledger.observe(.write_pointer_advanced, at);
    }

    /// Whether the guest's waits are waits or a spin wearing a wait's name.
    pub fn logGuestWaitLiveness(self: *MachOState) void {
        const ledger = &self.guest_wait_liveness;
        machoCapturePrint(
            "macho-processor: GUEST WAIT LIVENESS: waits={d} signalled={d} timed_out={d} immediate={d}% aggregate={s} objects={d} unattributed={d} untracked={d} step={d}; {s}\n",
            .{
                ledger.total_waits,
                ledger.total_signalled,
                ledger.total_timed_out,
                ledger.aggregateImmediatePercent(),
                ledger.aggregateVerdict().label(),
                ledger.count,
                ledger.unattributed_waits,
                ledger.untracked_waits,
                self.executed_steps,
                ledger.verdict(),
            },
        );
        for (ledger.objects[0..ledger.count]) |object| {
            machoCapturePrint(
                "  wait object handle=0x{x:0>8} waits={d} signalled={d} timed_out={d} immediate={d}% sets={d} sets_already_signalled={d} verdict={s}\n",
                .{
                    object.handle,
                    object.waits,
                    object.signalled,
                    object.timed_out,
                    object.immediateRatioPercent(),
                    object.sets,
                    object.sets_already_signalled,
                    object.verdict().label(),
                },
            );
        }
        if (ledger.worst()) |object| machoCapturePrint(
            "macho-processor: GUEST WAIT LIVENESS: worst object handle=0x{x:0>8} verdict={s} — {s}\n",
            .{ object.handle, object.verdict().label(), object.verdict().meaning() },
        );
    }

    /// The pre-initialisation ledger, printed with owners and ordering.
    pub fn logPreinitialization(self: *MachOState) void {
        self.refreshPreinitialization();
        const ledger = &self.gpu_preinitialization;
        const gap = ledger.firstGap();
        machoCapturePrint(
            "macho-processor: GPU PRE-INITIALIZATION: established={d}/{d} first_gap={s} owner={s} inversions={d} (dropped={d}) refused_supplies={d} step={d}; {s}\n",
            .{
                ledger.establishedCount(),
                gpu.preinitialization.element_count,
                if (gap) |element| element.label() else "<none>",
                if (gap) |element| element.owner().label() else "-",
                ledger.inversion_count,
                ledger.inversions_dropped,
                ledger.refused_supplies,
                self.executed_steps,
                ledger.verdict(),
            },
        );
        inline for (@typeInfo(gpu.PreinitElement).@"enum".fields) |field| {
            const element: gpu.PreinitElement = @enumFromInt(field.value);
            const entry = ledger.entries[field.value];
            machoCapturePrint(
                "  preinit {s: <12} {s: <12} {s: <44} step={d} observations={d}{s}{s}\n",
                .{
                    element.owner().label(),
                    ledger.state(element).label(),
                    element.label(),
                    entry.step,
                    entry.observations,
                    if (entry.state.present()) "" else " — ",
                    if (entry.state.present()) "" else element.consequence(),
                },
            );
        }
        var index: u32 = 0;
        while (index < ledger.inversion_count) : (index += 1) {
            const inversion = ledger.inversions[index];
            machoCapturePrint(
                "macho-processor: GPU PRE-INITIALIZATION: ORDERING INVERSION #{d}: '{s}' became true at step {d} while '{s}' was still absent. Whatever the title read at that moment it read too early, and nothing re-reads it — {s}\n",
                .{
                    index + 1,
                    inversion.element.label(),
                    inversion.step,
                    inversion.prerequisite.label(),
                    inversion.prerequisite.consequence(),
                },
            );
        }
        var pending: [gpu.preinitialization.element_count]gpu.PreinitElement = undefined;
        for (ledger.outstandingPlatformWork(&pending)) |element| {
            machoCapturePrint(
                "macho-processor: GPU PRE-INITIALIZATION: platform work outstanding: {s} — {s}\n",
                .{ element.label(), element.consequence() },
            );
        }
    }

    /// Read every projection of the guest's ring buffer and say what is in it.
    ///
    /// Every other counter in this subsystem describes the ring second-hand: a
    /// dword count, a pointer pair, a swap tally. None of them can distinguish
    /// a title that set state and stopped from one that drew a frame and never
    /// presented it, and those have different owners and different next steps.
    /// The ring is ordinary memory here, so the direct answer was available and
    /// simply never read.
    ///
    /// Read through all three aliases rather than one. The console's physical
    /// page is mapped into this process more than once, and the emulator's
    /// 4 KiB heap bias puts two of those mappings on different host pages — so
    /// "the producer published twenty-five dwords" and "the ring is eight
    /// thousand dwords of zeros" can both be true at once, of different host
    /// addresses. A single-address read cannot tell that apart from a producer
    /// that wrote nothing, and those are opposite bugs.
    pub fn logRingContents(self: *MachOState) void {
        if (self.gpu_ring_watch_base == 0 or self.gpu_ring_watch_size == 0) {
            machoCapturePrint(
                "macho-processor: RING CONTENTS: the ring's base and size have not been observed yet, so there is nothing to read. This is upstream of every packet question: VdInitializeRingBuffer has not run, or its arguments were not seen\n",
                .{},
            );
            return;
        }
        const ring_dwords: u32 = @intCast(@min(self.gpu_ring_watch_size / 4, std.math.maxInt(u32)));
        const virtual_alias: u32 = if (self.gpu_ring_watch_base >= 0x1000)
            @intCast(0xE000_0000 + self.gpu_ring_watch_base - 0x1000)
        else
            0;
        const unbiased = if (virtual_alias != 0)
            self.xenia_memory_views.primaryUnbiasedHostAddress(virtual_alias) orelse 0
        else
            0;

        var survey = gpu.ring_view.Survey{};
        survey.record(gpu.ring_view.examine(
            .physical,
            self.gpu_ring_watch_host_physical,
            self.guestMemoryConst(self.gpu_ring_watch_host_physical, self.gpu_ring_watch_size),
            ring_dwords,
        ));
        survey.record(gpu.ring_view.examine(
            .virtual_biased,
            self.gpu_ring_watch_host_virtual,
            self.guestMemoryConst(self.gpu_ring_watch_host_virtual, self.gpu_ring_watch_size),
            ring_dwords,
        ));
        survey.record(gpu.ring_view.examine(
            .virtual_unbiased,
            unbiased,
            self.guestMemoryConst(unbiased, self.gpu_ring_watch_size),
            ring_dwords,
        ));

        const publication = &self.gpu_ring_publication;
        const published = publication.advances != 0;
        if (publication.geometry != null) {
            self.gpu_vd_swap_contract.observeRingGeometry(self.executed_steps, .memory_mapping);
        }
        self.gpu_ring_scan_reports +|= 1;
        machoCapturePrint(
            "macho-processor: RING CONTENTS: base=0x{x} dwords={d} size=0x{x} projections(readable/written/candidates/payload_readable)={d}/{d}/{d}/{d} aliases_disagree={s}; {s}\n",
            .{
                self.gpu_ring_watch_base,
                ring_dwords,
                self.gpu_ring_watch_size,
                survey.readableCount(),
                survey.writtenCount(),
                survey.swapCandidateCount(),
                survey.readableSwapCandidateCount(),
                if (survey.aliasesDisagree()) "YES" else "NO",
                survey.verdict(published),
            },
        );
        for (survey.readings) |reading| {
            machoCapturePrint(
                "  projection {s: <16} host=0x{x:0>9} readable={s: <3} nonzero_dwords={d: <6} packets={d: <5} draws={d: <4} stream_validated={s: <3} swap_candidates={d} payload_readable={d} malformed={d} truncated={d} swap={s}; {s}\n",
                .{
                    reading.projection.label(),
                    reading.address,
                    if (reading.readable) "YES" else "NO",
                    reading.nonzero_dwords,
                    reading.packets,
                    reading.draws,
                    if (reading.stream_validated) "YES" else "NO",
                    reading.swap_candidates,
                    reading.swap_payload_readable,
                    reading.swap_malformed_candidates,
                    reading.swap_truncated_candidates,
                    if (reading.swap != null) "YES" else "NO",
                    reading.projection.meaning(),
                },
            );
        }

        // The span the pointers describe, read out of whichever projection
        // actually holds data. The pointers are frequently zero here because
        // the emulator reports them through a path this process does not see;
        // an empty span is therefore not evidence, and the whole-ring walk
        // above is what the verdict is built on.
        const geometry = publication.geometry orelse blk: {
            for ([_]gpu.VdSwapStage{ .ring_geometry_observed, .ring_projection_readable }) |stage| {
                self.gpu_vd_swap_contract.recordProbe(stage, .ring_geometry_capture, .input_unavailable, 0, self.executed_steps);
            }
            break :blk gpu.RingGeometry{};
        };
        const span: u32 = if (geometry.write_pointer >= geometry.read_pointer)
            geometry.write_pointer - geometry.read_pointer
        else
            ring_dwords - (geometry.read_pointer - geometry.write_pointer);
        // The stages the outstanding-span walk can supply.  It is recorded
        // against every one of them on every heartbeat, including the
        // heartbeats where it reads nothing: a span of zero is the normal
        // state of a drained ring, and sixteen consecutive empty walks are not
        // sixteen pieces of evidence that the producer wrote no swap.
        const span_stages = [_]gpu.VdSwapStage{
            .ring_projection_readable,
            .pm4_stream_observed,
            .pm4_stream_validated,
            .xe_swap_candidate_seen,
            .xe_swap_packet_readable,
            .xe_swap_packet_decoded,
            .fetch_constant_decoded,
        };
        if (survey.best()) |chosen| {
            if (self.guestMemoryConst(chosen.address, self.gpu_ring_watch_size)) |bytes| {
                const summary = gpu.ring_scan.scan(bytes, geometry.read_pointer, span, ring_dwords);
                if (summary.dwords_examined == 0) {
                    for (span_stages) |stage| {
                        self.gpu_vd_swap_contract.recordProbe(stage, .outstanding_span_scan, .input_empty, 0, self.executed_steps);
                    }
                } else {
                    self.gpu_vd_swap_contract.observeProbe(.ring_projection_readable, .outstanding_span_scan, chosen.readable, summary.dwords_examined, self.executed_steps);
                    self.gpu_vd_swap_contract.observeProbe(.pm4_stream_observed, .outstanding_span_scan, summary.packets != 0, summary.dwords_examined, self.executed_steps);
                    self.gpu_vd_swap_contract.observeProbe(.pm4_stream_validated, .outstanding_span_scan, !summary.truncated and !summary.desynchronised and summary.malformed_packets == 0, summary.dwords_scanned, self.executed_steps);
                    self.gpu_vd_swap_contract.observeProbe(.xe_swap_candidate_seen, .outstanding_span_scan, summary.swap_candidates != 0, summary.dwords_examined, self.executed_steps);
                    self.gpu_vd_swap_contract.observeProbe(.xe_swap_packet_readable, .outstanding_span_scan, summary.swap_payload_readable != 0, summary.swap_candidates, self.executed_steps);
                    self.gpu_vd_swap_contract.observeProbe(.xe_swap_packet_decoded, .outstanding_span_scan, summary.swap != null, summary.swap_candidates, self.executed_steps);
                    self.gpu_vd_swap_contract.observeProbe(.fetch_constant_decoded, .outstanding_span_scan, summary.fetch != null, summary.dwords_examined, self.executed_steps);
                }
                self.gpu_vd_swap_contract.observePacket(.{
                    .projection_readable = chosen.readable,
                    .stream_observed = summary.dwords_examined != 0 and summary.zero_dwords < summary.dwords_examined,
                    .stream_validated = summary.dwords_examined != 0 and summary.zero_dwords < summary.dwords_examined and
                        !summary.truncated and !summary.desynchronised and summary.malformed_packets == 0,
                    .candidate_seen = summary.swap_candidates != 0,
                    .readable = summary.swap_payload_readable != 0,
                    .decoded = summary.swap != null,
                    .swap = summary.swap,
                    .fetch = summary.fetch,
                    .fetch_decoded = summary.fetch != null,
                    .root_packets = summary.packets,
                    .draw_packets = summary.draw_packets,
                    .swap_packets = summary.swap_packets,
                    .malformed_packets = summary.malformed_packets,
                    .truncated = summary.truncated,
                    .desynchronised = summary.desynchronised,
                    .zero_dwords = summary.zero_dwords,
                    .dwords_examined = summary.dwords_examined,
                    .dwords_scanned = summary.dwords_scanned,
                    .span_dwords = summary.span_dwords,
                    .packet_offset = summary.swap_offset,
                }, self.executed_steps, .ring_memory_scan);
                self.xenia_gpu_causal_trace.observeRingPayload(
                    summary.packets,
                    summary.draw_packets,
                    summary.swap_packets,
                    self.executed_steps,
                    self.gpu_ring_injection.injections == 0 and self.gpu_ring_publication.advances != 0,
                );
                machoCapturePrint(
                    "  outstanding span: projection={s} read={d} write={d} span={d} examined={d} walked={d} packets={d} draws={d} swaps={d} candidates={d} payload_readable={d} decoded={s} fetch_decoded={s} truncated={s} desync={s}; {s}\n",
                    .{
                        chosen.projection.label(),                   geometry.read_pointer,
                        geometry.write_pointer,                      span,
                        summary.dwords_examined,                     summary.dwords_scanned,
                        summary.packets,                             summary.draw_packets,
                        summary.swap_packets,                        summary.swap_candidates,
                        summary.swap_payload_readable,               if (summary.swap != null) "YES" else "NO",
                        if (summary.fetch != null) "YES" else "NO",  if (summary.truncated) "YES" else "NO",
                        if (summary.desynchronised) "YES" else "NO", summary.verdict(),
                    },
                );

                // The ring scanner is deliberately read-only.  Once a new
                // publication is observed, hand the same bounded, endian-
                // decoded span to the stateful Xenos command processor so
                // register state, draw state, completion events, and swap
                // descriptions have a single owner.  Do not replay a drained
                // ring when the producer has not advanced its publication.
                if (span != 0 and self.gpu_xenos_last_ring_epoch != publication.advances) {
                    self.gpu_xenos_last_ring_epoch = publication.advances;
                    self.gpu_xenos_runtime.attachMemory(
                        self,
                        xenosMemoryRead,
                        self,
                        xenosMemoryWrite,
                    );
                    if (self.gpu_xenos_runtime.executeRingBytes(bytes, geometry.read_pointer, span, ring_dwords)) |execution| {
                        const indirect = self.xenia_gpu_causal_trace.observePm4SpanWithIndirects(
                            bytes,
                            geometry.read_pointer,
                            span,
                            ring_dwords,
                            self.executed_steps,
                            true,
                            self.gpu_ring_injection.injections == 0 and self.gpu_ring_publication.advances != 0,
                            self,
                            xenosMemoryRead,
                        );
                        const indirect_packets: u64 = @as(u64, indirect.root_packets) + @as(u64, indirect.nested_packets);
                        const indirect_draws: u64 = indirect.draw_packets;
                        const indirect_swaps: u64 = indirect.swap_packets;
                        const executed_packets = execution.packets_after - execution.packets_before;
                        const indirects_resolved = indirect.unreadable_references == 0 and
                            indirect.invalid_references == 0 and
                            indirect.cycle_references == 0 and
                            indirect.depth_limited_references == 0 and
                            indirect.truncated_references == 0 and
                            indirect.budget_limited_references == 0;
                        const stream_observed = execution.dwords != 0 or executed_packets != 0;
                        const stream_validated = stream_observed and !execution.truncated;
                        const runtime_fetch = self.gpu_xenos_runtime.frontBufferFetch();
                        const execution_runtime_swap = self.gpu_xenos_runtime.last_swap;
                        self.gpu_vd_swap_contract.observePacket(.{
                            .projection_readable = true,
                            .stream_observed = stream_observed,
                            .stream_validated = stream_validated,
                            .indirects_resolved = indirects_resolved,
                            .candidate_seen = execution.swaps != 0 or execution_runtime_swap != null,
                            .readable = execution_runtime_swap != null,
                            .decoded = execution_runtime_swap != null,
                            .swap = execution_runtime_swap,
                            .fetch = runtime_fetch,
                            .fetch_decoded = runtime_fetch != null,
                            .root_packets = executed_packets,
                            .nested_packets = indirect.nested_packets,
                            .indirect_packets = indirect.indirect_packets,
                            .draw_packets = execution.draws,
                            .swap_packets = execution.swaps,
                            .truncated = execution.truncated,
                            .unknown_opcodes = execution.unknown_opcodes,
                            .unreadable_references = indirect.unreadable_references,
                            .authentic_consumption = execution_runtime_swap != null and
                                self.gpu_ring_injection.injections == 0 and
                                self.gpu_ring_publication.published(),
                        }, self.executed_steps, .stateful_pm4_executor);
                        const consumed_packets = if (executed_packets > indirect_packets) executed_packets else indirect_packets;
                        const consumed_draws = if (execution.draws > indirect_draws) execution.draws else indirect_draws;
                        const consumed_swaps = if (execution.swaps > indirect_swaps) execution.swaps else indirect_swaps;
                        if (consumed_draws != 0) {
                            self.gpu_ring_draws_seen = true;
                            const draw_count: u32 = @intCast(@min(consumed_draws, @as(u64, std.math.maxInt(u32))));
                            if (draw_count > self.gpu_ring_draws_last_count) self.gpu_ring_draws_last_count = draw_count;
                        }
                        self.gpu_ring_publication.observeConsumedBatch(
                            span,
                            consumed_packets,
                            consumed_draws,
                            consumed_swaps,
                            self.executed_steps,
                        );
                        self.xenia_gpu_causal_trace.observeConsumedBatch(
                            @intCast(@min(consumed_packets, @as(u64, std.math.maxInt(u32)))),
                            @intCast(@min(consumed_draws, @as(u64, std.math.maxInt(u32)))),
                            @intCast(@min(consumed_swaps, @as(u64, std.math.maxInt(u32)))),
                            self.executed_steps,
                            self.gpu_ring_injection.injections == 0 and self.gpu_ring_publication.advances != 0,
                        );
                        machoCapturePrint(
                            "macho-processor: XENOS PM4 execution: batches={d} dwords={d} packets={d} draws={d} events={d} swaps={d} unknown={d} truncated={s}; observed_packets={d} observed_draws={d} observed_swaps={d} indirect_buffers={d} indirect_read={d}/{d} indirect_status={s} indirect_address=0x{x:0>8} indirect_missing=0x{x:0>8}; state_draws={d} state_swaps={d}\n",
                            .{
                                self.gpu_xenos_runtime.batches,
                                execution.dwords,
                                execution.packets_after - execution.packets_before,
                                execution.draws,
                                execution.events,
                                execution.swaps,
                                execution.unknown_opcodes,
                                if (execution.truncated) "YES" else "NO",
                                consumed_packets,
                                consumed_draws,
                                consumed_swaps,
                                execution.indirect_buffers,
                                execution.indirect_dwords_read,
                                execution.indirect_dwords_requested,
                                execution.indirect_last_status.label(),
                                execution.indirect_last_address,
                                execution.indirect_last_missing_address orelse 0,
                                self.gpu_xenos_runtime.draw_count,
                                self.gpu_xenos_runtime.swap_count,
                            },
                        );
                        if (execution.swaps != 0) {
                            if (self.gpu_xenos_runtime.last_swap) |runtime_swap| {
                                if (runtime_swap.plausible()) {
                                    self.gpu_frontbuffer = runtime_swap;
                                    self.gpu_vd_swap_contract.observeFrontBuffer(
                                        runtime_swap,
                                        .stateful_pm4_executor,
                                        self.executed_steps,
                                    );
                                    self.offerGuestFrontBuffer(runtime_swap, self.gpu_xenos_runtime.frontBufferFetch());
                                    machoCapturePrint(
                                        "macho-processor: XENOS PM4 present handoff: frontbuffer=0x{x:0>8} extent={d}x{d} fetch={s}; stateful command processing supplied the presenter even when the generic ring scanner did not decode the swap\n",
                                        .{
                                            runtime_swap.frontbuffer_physical_address,
                                            runtime_swap.width,
                                            runtime_swap.height,
                                            if (self.gpu_xenos_runtime.frontBufferFetch() != null) "observed" else "absent (defaults apply)",
                                        },
                                    );
                                }
                            }
                        }
                    } else |err| {
                        machoCapturePrint(
                            "macho-processor: XENOS PM4 execution refused: error={s} read={d} write={d} span={d} ring_dwords={d}\n",
                            .{ @errorName(err), geometry.read_pointer, geometry.write_pointer, span, ring_dwords },
                        );
                    }
                    if (self.gpu_interrupt_callback != 0) {
                        const delivered = self.gpu_xenos_runtime.drainInterrupts(deliverGpuInterrupt, self, 32);
                        if (delivered != 0) {
                            machoCapturePrint(
                                "macho-processor: XENOS GPU interrupts queued: delivered={d} callback=0x{x} arg=0x{x}\n",
                                .{ delivered, self.gpu_interrupt_callback, self.gpu_interrupt_callback_arg },
                            );
                        }
                    }
                }
            }
        }

        if (survey.best()) |chosen| {
            if (chosen.draws != 0) self.gpu_ring_draws_seen = true;
            if (chosen.draws > self.gpu_ring_draws_last_count) self.gpu_ring_draws_last_count = chosen.draws;
            self.gpu_ring_nonzero_dwords = chosen.nonzero_dwords;
            // The whole-ring survey is the strongest negative evidence the
            // subsystem has: it reads every dword of a readable projection,
            // drained or outstanding.  When it finds no XE_SWAP the title
            // really did not write one, and that is a finding against the
            // producer rather than a hole in the observer.  When the projection
            // holds nothing at all the reverse is true, so the two are recorded
            // as different outcomes.
            const survey_stages = [_]gpu.VdSwapStage{
                .xe_swap_candidate_seen,
                .xe_swap_packet_readable,
                .xe_swap_packet_decoded,
            };
            if (!chosen.readable) {
                for (survey_stages) |stage| {
                    self.gpu_vd_swap_contract.recordProbe(stage, .ring_projection_survey, .input_unavailable, 0, self.executed_steps);
                }
                self.gpu_vd_swap_contract.recordProbe(.ring_projection_readable, .ring_projection_survey, .input_unavailable, 0, self.executed_steps);
            } else if (chosen.nonzero_dwords == 0) {
                for (survey_stages) |stage| {
                    self.gpu_vd_swap_contract.recordProbe(stage, .ring_projection_survey, .input_empty, 0, self.executed_steps);
                }
                self.gpu_vd_swap_contract.observeProbe(.ring_projection_readable, .ring_projection_survey, true, 0, self.executed_steps);
            } else {
                self.gpu_vd_swap_contract.observeProbe(.ring_projection_readable, .ring_projection_survey, true, chosen.nonzero_dwords, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.pm4_stream_observed, .ring_projection_survey, chosen.packets != 0, chosen.nonzero_dwords, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.pm4_stream_validated, .ring_projection_survey, chosen.stream_validated, chosen.packets, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.xe_swap_candidate_seen, .ring_projection_survey, chosen.swap_candidates != 0, chosen.nonzero_dwords, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.xe_swap_packet_readable, .ring_projection_survey, chosen.swap_payload_readable != 0, chosen.swap_candidates, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.xe_swap_packet_decoded, .ring_projection_survey, chosen.swap != null, chosen.swap_candidates, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.frontbuffer_validated, .retained_batch_scan, chosen.swap != null, chosen.nonzero_dwords, self.executed_steps);
            }
            self.gpu_vd_swap_contract.observePacket(.{
                .projection_readable = chosen.readable,
                .stream_observed = chosen.nonzero_dwords != 0 and chosen.packets != 0,
                .stream_validated = chosen.stream_validated,
                .candidate_seen = chosen.swap_candidates != 0,
                .readable = chosen.swap_payload_readable != 0,
                .decoded = chosen.swap != null,
                .swap = chosen.swap,
                .fetch = chosen.fetch,
                .fetch_decoded = chosen.fetch != null,
                .root_packets = chosen.packets,
                .draw_packets = chosen.draws,
                .swap_packets = chosen.swap_candidates,
                .malformed_packets = chosen.swap_malformed_candidates,
                .truncated = chosen.swap_truncated_candidates != 0,
                .packet_offset = chosen.swap_offset,
            }, self.executed_steps, .ring_memory_scan);
            self.logRingPayload(chosen);
        }
        self.logSubmissionProvenance();
        machoCapturePrint(
            "  whole-ring draw search: effective_draws(root_or_nested)={d} ever_seen={s}; the outstanding span is what the pointers describe, and a batch the command processor already drained is still in the ring. Absence here is weak evidence and presence is strong\n",
            .{ self.gpu_ring_draws_last_count, if (self.gpu_ring_draws_seen) "YES" else "NO" },
        );

        // The pointers describe what is outstanding. A swap the command
        // processor already drained is still in the ring, and "was one ever
        // written" is a different and more useful question than "is one
        // waiting" — a yes here with a zero swap counter upstream means the
        // packet was written and not decoded, which is a completely different
        // defect from one that was never written.
        const found: ?gpu.Pm4SwapDescription = if (survey.best()) |chosen| chosen.swap else null;
        if (found) |swap| {
            if (self.gpu_frontbuffer == null) machoCapturePrint(
                "macho-processor: RING CONTENTS: a swap packet is present in ring memory: frontbuffer=0x{x:0>8} extent={d}x{d} plausible={s}. The title did write a present request into the ring at some point in this run, whatever the swap counters say\n",
                .{ swap.frontbuffer_physical_address, swap.width, swap.height, if (swap.plausible()) "YES" else "NO" },
            );
            if (swap.plausible()) {
                self.gpu_frontbuffer = swap;
                self.gpu_vd_swap_contract.observeFrontBuffer(swap, .ring_memory_scan, self.executed_steps);
                self.offerGuestFrontBuffer(swap, if (survey.best()) |chosen| chosen.fetch else null);
            }
        } else {
            machoCapturePrint(
                "macho-processor: RING CONTENTS: no XE_SWAP packet exists in any readable projection of the ring, drained or outstanding. The title has never written a present request, so the absence is the producer's and not the command processor's\n",
                .{},
            );
        }
    }

    fn deliverGpuInterrupt(context: *anyopaque, event: gpu.interrupt_controller.Event) void {
        const self: *MachOState = @ptrCast(@alignCast(context));
        self.gpu_interrupt_dispatches +|= 1;
        const is_draw_completion = event.kind == .draw_complete;
        if (is_draw_completion) self.gpu_draw_completion_dispatch_attempts +|= 1;
        if (self.gpu_interrupt_callback == 0) {
            if (is_draw_completion) self.gpu_draw_completion_dispatch_failures +|= 1;
            return;
        }
        const source = self.scheduleSignalCallback(
            self.gpu_interrupt_callback,
            self.gpu_interrupt_callback_arg,
            event.id,
            event.value,
            "xenia_gpu_interrupt",
        );
        if (source == 0) {
            self.gpu_interrupt_dispatch_failures +|= 1;
            if (is_draw_completion) self.gpu_draw_completion_dispatch_failures +|= 1;
            machoCapturePrint(
                "macho-processor: XENOS GPU interrupt callback rejected: callback=0x{x} event={s} id=0x{x} value=0x{x}; guest execution was not fabricated\n",
                .{ self.gpu_interrupt_callback, @tagName(event.kind), event.id, event.value },
            );
            return;
        }
        if (is_draw_completion) self.gpu_draw_completion_dispatches +|= 1;
        self.gpu_bootstrap.observe(.graphics_interrupt_dispatch, self.executed_steps);
    }

    fn xenosGpuSwap(value: u32, endian: u2) u32 {
        return switch (endian) {
            0 => value,
            1 => ((value << 8) & 0xFF00_FF00) | ((value >> 8) & 0x00FF_00FF),
            2 => @byteSwap(value),
            3 => (value >> 16) | (value << 16),
        };
    }

    fn xenosProjectionHostAddress(
        self: *MachOState,
        address: u32,
        projection: xenia_memory_views.PhysicalProjection,
    ) ?u64 {
        const aligned = address & ~@as(u32, 3);
        return self.xenia_memory_views.physicalProjectionHostAddress(aligned, projection);
    }

    fn xenosReadProjection(
        self: *MachOState,
        address: u32,
        projection: xenia_memory_views.PhysicalProjection,
    ) ?u32 {
        const host = self.xenosProjectionHostAddress(address, projection) orelse return null;
        const bytes = self.guestMemoryConst(host, 4) orelse return null;
        // Xenia's TranslatePhysical backing stores Xbox words in big-endian
        // memory. This is the direct equivalent of Xenia's
        // load_and_swap<uint32_t> on a little-endian macOS host.
        const raw = std.mem.readInt(u32, bytes[0..4], .big);
        return xenosGpuSwap(raw, @truncate(address));
    }

    fn xenosWriteProjection(
        self: *MachOState,
        address: u32,
        value: u32,
        endian: u2,
        projection: xenia_memory_views.PhysicalProjection,
    ) bool {
        const host = self.xenosProjectionHostAddress(address, projection) orelse return false;
        const bytes = self.guestMemory(host, 4) orelse return false;
        std.mem.writeInt(u32, bytes[0..4], xenosGpuSwap(value, endian), .big);
        return true;
    }

    fn noteXenosAliasFallback(self: *MachOState, address: u32, disagreement: bool) void {
        self.gpu_xenos_memory_alias_fallbacks +|= 1;
        if (disagreement) self.gpu_xenos_memory_alias_disagreements +|= 1;
        self.gpu_xenos_memory_alias_log_count +|= 1;
        const count = self.gpu_xenos_memory_alias_log_count;
        if (count <= 8 or (count % 256) == 0) {
            machoCapturePrint(
                "macho-processor: XENOS MEMORY projection fallback #{d}: physical=UNREADABLE address=0x{x:0>8} aliases_disagree={s}; {s}\n",
                .{
                    count,
                    address,
                    if (disagreement) "YES" else "NO",
                    if (disagreement) "read refused (zero-trust)" else "alias value accepted",
                },
            );
        }
    }

    fn xenosMemoryRead(context: *anyopaque, address: u32) ?u32 {
        const self: *MachOState = @ptrCast(@alignCast(context));
        if (self.xenosReadProjection(address, .physical)) |value| return value;
        self.gpu_xenos_memory_physical_misses +|= 1;

        var fallback: ?u32 = null;
        var disagreement = false;
        inline for ([_]xenia_memory_views.PhysicalProjection{ .a_virtual, .c_virtual, .e_virtual }) |projection| {
            if (self.xenosReadProjection(address, projection)) |value| {
                if (fallback) |existing| {
                    if (existing != value) disagreement = true;
                } else {
                    fallback = value;
                }
            }
        }
        if (disagreement) {
            self.noteXenosAliasFallback(address, true);
            return null;
        }
        if (fallback != null) self.noteXenosAliasFallback(address, false);
        return fallback;
    }

    fn xenosMemoryWrite(context: *anyopaque, address: u32, value: u32, endian: u2) bool {
        const self: *MachOState = @ptrCast(@alignCast(context));
        if (self.xenosWriteProjection(address, value, endian, .physical)) return true;
        self.gpu_xenos_memory_physical_misses +|= 1;

        var wrote_alias = false;
        inline for ([_]xenia_memory_views.PhysicalProjection{ .a_virtual, .c_virtual, .e_virtual }) |projection| {
            if (self.xenosWriteProjection(address, value, endian, projection)) wrote_alias = true;
        }
        if (wrote_alias) self.noteXenosAliasFallback(address, false);
        return wrote_alias;
    }

    /// Execute the batch that is still present in ring memory after the
    /// command processor drained it.
    ///
    /// The stateful Xenos runtime is the only source in the subsystem for
    /// render-target registers, EDRAM resolves, draw-completion events and a
    /// decoded front-buffer fetch constant.  Until this existed it ran from one
    /// place only: the branch guarded by `span != 0`, where `span` is the
    /// distance between the ring's read and write pointers.  A title that
    /// publishes once during bring-up and is then drained has `read == write`
    /// forever, so on the run this was written against that branch never fired,
    /// the register file was never written, and six contract stages read zero
    /// because nothing had ever executed a packet — not because the title
    /// failed to program its GPU.
    ///
    /// Replaying the retained batch is not a substitution.  These are dwords
    /// the producer actually wrote, framed by the same walk that reports them,
    /// decoded by Rosette's own command processor rather than invented by it.
    /// It runs at most once per publication epoch, so a drained ring is never
    /// replayed into a second frame's worth of state, and it cannot close
    /// `authentic_xe_swap_consumed` unless the batch really carries a swap —
    /// `observeAuthenticConsumption` refuses a null description.
    fn executeRetainedBatch(
        self: *MachOState,
        bytes: []const u8,
        root_start: u32,
        root_dwords: u32,
        ring_dwords: u32,
        authentic: bool,
    ) void {
        const at = self.executed_steps;
        const ledger = &self.gpu_vd_swap_contract;
        const executor_stages = [_]gpu.VdSwapStage{
            .pm4_state_programmed,
            .draw_submitted,
            .draw_consumed,
            .render_target_state_observed,
            .render_target_memory_observed,
            .draw_completion_signaled,
            .fetch_constant_decoded,
            .xe_swap_candidate_seen,
        };

        if (root_dwords == 0) {
            for (executor_stages) |stage| {
                ledger.recordProbe(stage, .stateful_pm4_execution, .input_empty, 0, at);
            }
            return;
        }
        if (self.gpu_xenos_last_payload_epoch == self.gpu_ring_publication.advances) return;
        self.gpu_xenos_last_payload_epoch = self.gpu_ring_publication.advances;

        // Read-only replay, and this is not a detail.
        //
        // The batch has already been consumed by the emulator's own command
        // processor, which means its MEM_WRITE and EVENT_WRITE_SHD packets have
        // already landed in guest memory.  Replaying them would make Rosette
        // write stale fence and progress values over addresses the guest has
        // since advanced — Rosette would become the corrupting writer, and the
        // corruption would look like a title bug.  The span-gated path can
        // safely attach the write callback because it executes an *outstanding*
        // span whose writes have not happened yet; this path cannot.
        //
        // Nothing needed here is lost.  The register file, draw state, EDRAM
        // resolves and completion events all live in Rosette's own storage, and
        // suppressed writes are counted rather than dropped silently, so the
        // batch's memory-write content stays visible as a number.
        const deferred_before = self.gpu_xenos_runtime.executor.deferred_memory_count;
        self.gpu_xenos_runtime.attachMemory(self, xenosMemoryRead, self, null);
        // Restored on every exit path.  Leaving the runtime read-only would
        // silently suppress the writes of the outstanding-span path, whose
        // batch has not been consumed yet and whose writes must land — and a
        // suppressed write there would look like a title that stopped
        // signalling rather than a callback this function unhooked.
        defer self.gpu_xenos_runtime.attachMemory(self, xenosMemoryRead, self, xenosMemoryWrite);
        const execution = self.gpu_xenos_runtime.executeRingBytes(
            bytes,
            root_start,
            root_dwords,
            ring_dwords,
        ) catch |err| {
            self.gpu_xenos_retained_refusals +|= 1;
            // A refusal is not an empty input: the walk had dwords and the
            // decoder rejected them.  Recording it as unavailable keeps the
            // stages honest about which of the two happened.
            for (executor_stages) |stage| {
                ledger.recordProbe(stage, .stateful_pm4_execution, .input_unavailable, root_dwords, at);
            }
            machoCapturePrint(
                "macho-processor: XENOS RETAINED BATCH refused: error={s} start={d} dwords={d} ring_dwords={d}; the producer's retained dwords exist and the command processor could not decode them, which is a framing defect rather than an absent batch\n",
                .{ @errorName(err), root_start, root_dwords, ring_dwords },
            );
            return;
        };
        const deferred_writes = self.gpu_xenos_runtime.executor.deferred_memory_count - deferred_before;

        self.gpu_xenos_retained_executions +|= 1;
        const executed_packets = execution.packets_after - execution.packets_before;
        const target = self.gpu_xenos_runtime.renderTargetEvidence();
        const runtime_fetch = self.gpu_xenos_runtime.frontBufferFetch();
        const runtime_swap = self.gpu_xenos_runtime.last_swap;

        // Each of these is recorded whether or not it was found.  The negative
        // outcome is the valuable one: it is the difference between "the
        // command processor executed this batch and it programmed no colour
        // target" and "nothing ever looked at the colour target".
        ledger.observeProbe(.pm4_state_programmed, .stateful_pm4_execution, executed_packets != 0, executed_packets, at);
        ledger.observeProbe(.draw_submitted, .stateful_pm4_execution, execution.draws != 0, execution.draws, at);
        ledger.observeProbe(.draw_consumed, .stateful_pm4_execution, execution.draws != 0, execution.draws, at);
        ledger.observeProbe(.render_target_state_observed, .xenos_register_file, target.state_observed, target.raw_color_info, at);
        ledger.observeProbe(
            .render_target_memory_observed,
            .xenos_register_file,
            self.gpu_xenos_runtime.color_resolve_observations != 0,
            self.gpu_xenos_runtime.color_resolve_observations,
            at,
        );
        ledger.observeProbe(
            .draw_completion_signaled,
            .stateful_pm4_execution,
            self.gpu_xenos_runtime.draw_completion_signals != 0,
            self.gpu_xenos_runtime.draw_completion_signals,
            at,
        );
        ledger.observeProbe(.fetch_constant_decoded, .xenos_register_file, runtime_fetch != null, execution.dwords, at);
        ledger.observeProbe(.xe_swap_candidate_seen, .stateful_pm4_execution, execution.swaps != 0, execution.dwords, at);

        ledger.observePacket(.{
            .projection_readable = true,
            .stream_observed = execution.dwords != 0 or executed_packets != 0,
            .stream_validated = (execution.dwords != 0 or executed_packets != 0) and !execution.truncated,
            .candidate_seen = execution.swaps != 0 or runtime_swap != null,
            .readable = runtime_swap != null,
            .decoded = runtime_swap != null,
            .swap = runtime_swap,
            .fetch = runtime_fetch,
            .fetch_decoded = runtime_fetch != null,
            .root_packets = executed_packets,
            .draw_packets = execution.draws,
            .swap_packets = execution.swaps,
            .truncated = execution.truncated,
            .unknown_opcodes = execution.unknown_opcodes,
            .dwords_examined = execution.dwords,
            .dwords_scanned = execution.dwords,
            .span_dwords = root_dwords,
            .authentic_consumption = runtime_swap != null and
                authentic and
                self.gpu_ring_injection.injections == 0,
        }, at, .stateful_pm4_executor);

        ledger.observeIntermediary(.{
            .render_target_state_observed = target.state_observed,
            .render_target_memory_observed = self.gpu_xenos_runtime.color_resolve_observations != 0,
            .draw_completion_signaled = self.gpu_xenos_runtime.draw_completion_signals != 0,
        }, at, .xenos_runtime);

        machoCapturePrint(
            "macho-processor: XENOS RETAINED BATCH: epoch={d} start={d} dwords={d} packets={d} draws={d} events={d} swaps={d} unknown={d} truncated={s} indirect(buffers/read/requested)={d}/{d}/{d} status={s}; target(state/color/depth/surface)={s}/0x{x:0>8}/0x{x:0>8}/0x{x:0>8} resolves={d} completions={d} fetch={s} guest_writes_suppressed={d}; the command processor executed the dwords the producer left in the ring, so every register-derived stage below is now a reading rather than a blank. The replay is read-only: this batch was already drained, so its memory writes are counted and not reapplied\n",
            .{
                self.gpu_ring_publication.advances,
                root_start,
                root_dwords,
                executed_packets,
                execution.draws,
                execution.events,
                execution.swaps,
                execution.unknown_opcodes,
                if (execution.truncated) "YES" else "NO",
                execution.indirect_buffers,
                execution.indirect_dwords_read,
                execution.indirect_dwords_requested,
                execution.indirect_last_status.label(),
                if (target.state_observed) "YES" else "NO",
                target.raw_color_info,
                target.raw_depth_info,
                target.raw_surface_info,
                self.gpu_xenos_runtime.color_resolve_observations,
                self.gpu_xenos_runtime.draw_completion_signals,
                if (runtime_fetch != null) "decoded" else "absent",
                deferred_writes,
            },
        );

        if (runtime_swap) |swap| {
            if (swap.plausible()) {
                self.gpu_frontbuffer = swap;
                ledger.observeFrontBuffer(swap, .stateful_pm4_executor, at);
                self.offerGuestFrontBuffer(swap, runtime_fetch);
                machoCapturePrint(
                    "macho-processor: XENOS RETAINED BATCH present handoff: frontbuffer=0x{x:0>8} extent={d}x{d} fetch={s}\n",
                    .{
                        swap.frontbuffer_physical_address,
                        swap.width,
                        swap.height,
                        if (runtime_fetch != null) "observed" else "absent (defaults apply)",
                    },
                );
            }
        }

        // A queued completion the guest callback never receives is a different
        // defect from one that was never queued, and the contract keeps them as
        // separate stages.  Draining here is what makes the second one
        // reachable at all.
        if (self.gpu_interrupt_callback != 0) {
            const delivered = self.gpu_xenos_runtime.drainInterrupts(deliverGpuInterrupt, self, 32);
            ledger.observeProbe(
                .draw_completion_dispatched,
                .interrupt_dispatch,
                self.gpu_draw_completion_dispatches != 0,
                delivered,
                at,
            );
            if (delivered != 0) {
                machoCapturePrint(
                    "macho-processor: XENOS RETAINED BATCH interrupts: delivered={d} callback=0x{x} arg=0x{x} draw_completions={d}\n",
                    .{ delivered, self.gpu_interrupt_callback, self.gpu_interrupt_callback_arg, self.gpu_draw_completion_dispatches },
                );
            }
        } else {
            // No callback has been registered, so nothing could be delivered.
            // That is an absent consumer, not a failed dispatch.
            ledger.recordProbe(.draw_completion_dispatched, .interrupt_dispatch, .input_unavailable, 0, at);
        }
    }

    /// Record that every probe fed by the retained batch was starved, and how.
    ///
    /// The whole reason this exists is that these stages have exactly one
    /// evidence path between them.  When that path cannot run, thirteen
    /// contract stages read zero at once, and without this they would all read
    /// as findings against the command processor.
    fn recordRetainedBatchStarvation(self: *MachOState, outcome: gpu.VdSwapProbeOutcome) void {
        const at = self.executed_steps;
        const ledger = &self.gpu_vd_swap_contract;
        const starved = [_]struct { stage: gpu.VdSwapStage, probe: gpu.VdSwapProbe }{
            .{ .stage = .pm4_state_programmed, .probe = .stateful_pm4_execution },
            .{ .stage = .draw_submitted, .probe = .stateful_pm4_execution },
            .{ .stage = .draw_consumed, .probe = .stateful_pm4_execution },
            .{ .stage = .render_target_state_observed, .probe = .stateful_pm4_execution },
            .{ .stage = .render_target_state_observed, .probe = .xenos_register_file },
            .{ .stage = .render_target_memory_observed, .probe = .stateful_pm4_execution },
            .{ .stage = .render_target_memory_observed, .probe = .xenos_register_file },
            .{ .stage = .draw_completion_signaled, .probe = .stateful_pm4_execution },
            .{ .stage = .fetch_constant_decoded, .probe = .stateful_pm4_execution },
            .{ .stage = .fetch_constant_decoded, .probe = .xenos_register_file },
            .{ .stage = .xe_swap_candidate_seen, .probe = .stateful_pm4_execution },
            .{ .stage = .xe_swap_packet_readable, .probe = .retained_batch_scan },
            .{ .stage = .xe_swap_packet_decoded, .probe = .retained_batch_scan },
            .{ .stage = .frontbuffer_validated, .probe = .retained_batch_scan },
        };
        for (starved) |entry| ledger.recordProbe(entry.stage, entry.probe, outcome, 0, at);
    }

    /// Print the dwords the producer actually wrote.
    ///
    /// Seventeen non-zero dwords in eight thousand is a very specific fact, and
    /// every summary built on top of it loses the only part that matters. No
    /// counter in the subsystem can say what the producer submitted; this can,
    /// and the batch is small enough to read.
    fn logRingPayload(self: *MachOState, chosen: gpu.ring_view.Reading) void {
        const bytes = self.guestMemoryConst(chosen.address, self.gpu_ring_watch_size) orelse {
            // The projection the survey chose cannot be read back.  Every
            // retained-batch probe is unavailable rather than empty, and the
            // difference decides whether the gaps below belong to Rosette's
            // memory mapping or to the title.
            self.recordRetainedBatchStarvation(.input_unavailable);
            return;
        };
        const ring_dwords: u32 = @intCast(@min(self.gpu_ring_watch_size / 4, std.math.maxInt(u32)));
        // Bounded like every other checkpoint walk. A ring configured at the
        // emulator's largest size is half a million dwords, and this runs on a
        // heartbeat in a ReleaseFast build where nothing else caps it.
        const written = gpu.ring_payload.digest(bytes, ring_dwords, gpu.ring_scan.max_search_dwords);
        var indirect_packets: u64 = 0;
        var indirect_draws: u64 = 0;
        var indirect_swaps: u64 = 0;
        self.xenia_gpu_causal_trace.observeRingPayload(
            written.real_packets,
            written.draws,
            written.swaps,
            self.executed_steps,
            self.gpu_ring_injection.injections == 0,
        );
        if (written.run_count == 0) {
            // A readable ring holding no written run at all.  The walk had
            // somewhere to look and nothing to look at.
            self.recordRetainedBatchStarvation(.input_empty);
        }
        if (written.run_count != 0) {
            // A drained primary span has equal read/write pointers, but the
            // retained ring still contains the exact batch the command
            // processor consumed.  Build the smallest envelope around the
            // written runs so a root INDIRECT_BUFFER packet can be followed
            // without pretending the whole ring is a live outstanding span.
            const root_start = written.runs[0].start;
            var root_end: u32 = root_start;
            var run_index: u32 = 0;
            while (run_index < written.run_count) : (run_index += 1) {
                const written_run = written.runs[run_index];
                const end = written_run.start +| written_run.length;
                if (end > root_end) root_end = end;
            }
            if (root_end <= root_start or root_start >= ring_dwords) {
                self.recordRetainedBatchStarvation(.input_empty);
            }
            if (root_end > root_start and root_start < ring_dwords) {
                const root_count = @min(root_end - root_start, ring_dwords - root_start);
                const consumed = self.xenia_gpu_handoff.pm4_packets != 0 or
                    self.execution_tracepoints.roleEntered(.command_processor);
                const authentic = self.gpu_ring_injection.injections == 0 and
                    self.gpu_ring_publication.published();
                const indirect = self.xenia_gpu_causal_trace.observePm4SpanWithIndirects(
                    bytes,
                    root_start,
                    root_count,
                    ring_dwords,
                    self.executed_steps,
                    consumed,
                    authentic,
                    self,
                    xenosMemoryRead,
                );
                indirect_packets = @as(u64, indirect.root_packets) + @as(u64, indirect.nested_packets);
                indirect_draws = indirect.draw_packets;
                indirect_swaps = indirect.swap_packets;
                // The walker gives us stream and indirect-reference truth, but
                // it does not retain a contiguous payload for every indirect
                // address. In particular, seeing an XE_SWAP opcode here must
                // never be promoted to "packet readable" or "decoded".
                self.gpu_vd_swap_contract.observePacket(.{
                    .projection_readable = true,
                    .stream_observed = indirect.packets_walked != 0,
                    .stream_validated = indirect.packets_walked != 0 and
                        !indirect.root_truncated and
                        !indirect.packet_budget_exhausted and
                        indirect.invalid_references == 0 and
                        indirect.cycle_references == 0 and
                        indirect.depth_limited_references == 0 and
                        indirect.truncated_references == 0 and
                        indirect.budget_limited_references == 0,
                    .indirects_resolved = indirect.unreadable_references == 0 and
                        indirect.invalid_references == 0 and
                        indirect.cycle_references == 0 and
                        indirect.depth_limited_references == 0 and
                        indirect.truncated_references == 0 and
                        indirect.budget_limited_references == 0,
                    .candidate_seen = indirect_swaps != 0,
                    .nested_packets = indirect.nested_packets,
                    .indirect_packets = indirect.indirect_packets,
                    .draw_packets = indirect.draw_packets,
                    .swap_packets = indirect_swaps,
                    .truncated = indirect.root_truncated or indirect.truncated_references != 0,
                    .unreadable_references = indirect.unreadable_references,
                    .dwords_examined = root_count,
                    .span_dwords = root_count,
                }, self.executed_steps, .nested_pm4_walk);
                const walked = indirect.packets_walked;
                self.gpu_vd_swap_contract.observeProbe(.pm4_stream_observed, .nested_indirect_walk, walked != 0, root_count, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.pm4_indirects_resolved, .nested_indirect_walk, indirect.unreadable_references == 0 and indirect.invalid_references == 0 and indirect.cycle_references == 0, indirect.indirect_references, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.draw_submitted, .nested_indirect_walk, indirect_draws != 0, indirect_draws, self.executed_steps);
                // The walk follows every indirect buffer the batch names, so a
                // zero here means no XE_SWAP exists anywhere the producer
                // pointed — the strongest form this absence takes.
                self.gpu_vd_swap_contract.observeProbe(.xe_swap_candidate_seen, .nested_indirect_walk, indirect_swaps != 0, walked, self.executed_steps);
                // The nested walk has told us what the batch contains.  Hand
                // the same envelope to the stateful command processor so the
                // register file, the completion queue and the fetch constant
                // are readings rather than blanks.  Without this the executor
                // only ever runs on an outstanding span, which a drained ring
                // never has.
                self.executeRetainedBatch(bytes, root_start, root_count, ring_dwords, authentic);
                if (indirect_draws != 0) {
                    self.gpu_ring_draws_seen = true;
                    const draw_count: u32 = @intCast(@min(indirect_draws, @as(u64, std.math.maxInt(u32))));
                    if (draw_count > self.gpu_ring_draws_last_count) self.gpu_ring_draws_last_count = draw_count;
                }
                if (consumed) {
                    const consumed_packets = if (indirect_packets > @as(u64, written.real_packets)) indirect_packets else @as(u64, written.real_packets);
                    const consumed_draws = if (indirect_draws > @as(u64, written.draws)) indirect_draws else @as(u64, written.draws);
                    const consumed_swaps = if (indirect_swaps > @as(u64, written.swaps)) indirect_swaps else @as(u64, written.swaps);
                    self.gpu_ring_publication.observeConsumedBatch(
                        root_count,
                        consumed_packets,
                        consumed_draws,
                        consumed_swaps,
                        self.executed_steps,
                    );
                }
                machoCapturePrint(
                    "macho-processor: PM4 INDIRECT WALK: root_start={d} root_dwords={d} consumed={s} authentic={s} root_packets={d} nested_packets={d} refs={d} readable={d} unreadable={d} truncated_refs={d} budget_refs={d} draws(root/nested/total)={d}/{d}/{d} swaps(root/nested/total)={d}/{d}/{d} cycles={d} truncated={s}\n",
                    .{
                        root_start,
                        root_count,
                        if (consumed) "YES" else "NO",
                        if (authentic) "YES" else "NO",
                        indirect.root_packets,
                        indirect.nested_packets,
                        indirect.indirect_references,
                        indirect.readable_references,
                        indirect.unreadable_references,
                        indirect.truncated_references,
                        indirect.budget_limited_references,
                        indirect.root_draw_packets,
                        indirect.nested_draw_packets,
                        indirect.draw_packets,
                        indirect.root_swap_packets,
                        indirect.nested_swap_packets,
                        indirect.swap_packets,
                        indirect.cycle_references,
                        if (indirect.root_truncated) "YES" else "NO",
                    },
                );
            }
        }
        const walked_draws: u32 = @intCast(@min(indirect_draws, @as(u64, std.math.maxInt(u32))));
        const walked_swaps: u32 = @intCast(@min(indirect_swaps, @as(u64, std.math.maxInt(u32))));
        // The indirect walk includes root packets as well as nested packets;
        // it is therefore a complete walked total, not an increment to add to
        // the root-only digest. Taking the maximum avoids counting a root
        // draw twice while still retaining nested draws the root digest could
        // not see.
        const effective_draws: u32 = if (written.draws > walked_draws) written.draws else walked_draws;
        const effective_swaps: u32 = if (written.swaps > walked_swaps) written.swaps else walked_swaps;
        const payload_verdict = if (effective_swaps != 0)
            "the payload contains a present request"
        else if (effective_draws != 0)
            "the payload contains draws, including indirect buffers, but no present request"
        else
            "the retained payload contains no decoded draw or present request";
        machoCapturePrint(
            "macho-processor: RING PAYLOAD: projection={s} nonzero_dwords={d} runs={d} (dropped={d}) real_packets={d} root_draws={d} root_swaps={d} indirect_packets={d} indirect_draws={d} indirect_swaps={d} total_draws={d} total_swaps={d} scanned={d}; {s}; {s}\n",
            .{
                chosen.projection.label(),
                written.nonzero_dwords,
                written.run_count,
                written.runs_dropped,
                written.real_packets,
                written.draws,
                written.swaps,
                indirect_packets,
                indirect_draws,
                indirect_swaps,
                effective_draws,
                effective_swaps,
                written.scanned_dwords,
                written.verdict(),
                payload_verdict,
            },
        );
        var run_index: u32 = 0;
        while (run_index < written.run_count) : (run_index += 1) {
            const region = written.runs[run_index];
            var dwords: [gpu.ring_payload.max_dump_dwords]u32 = undefined;
            const count = gpu.ring_payload.dumpRun(bytes, ring_dwords, region, &dwords);
            const header = region.first_header orelse gpu.Pm4Header{ .raw = 0, .kind = .type2, .count = 0 };
            machoCapturePrint(
                "  run #{d} start_dword={d} length={d} frames_cleanly={s} first_packet={s} opcode={s} declared_dwords={d}\n",
                .{
                    run_index + 1,
                    region.start,
                    region.length,
                    if (region.frames_cleanly) "YES" else "NO",
                    @tagName(header.kind),
                    if (header.kind == .type3) header.opcode.label() else "-",
                    header.totalDwords(),
                },
            );
            var at: u32 = 0;
            while (at < count) : (at += 8) {
                const end = @min(at + 8, count);
                var line: [160]u8 = undefined;
                var used: usize = 0;
                var column = at;
                while (column < end) : (column += 1) {
                    const piece = std.fmt.bufPrint(line[used..], "{x:0>8} ", .{dwords[column]}) catch break;
                    used += piece.len;
                }
                machoCapturePrint("    +{d: <5} {s}\n", .{ region.start + at, line[0..used] });
            }
        }
    }

    /// Threads that will never wake, and who was supposed to wake them.
    ///
    /// Fed from the scheduler's own thread table for waits and from its
    /// notifier graph for signals, so the two halves cannot drift apart. The
    /// notifier roster is the most recent signaller per object rather than the
    /// full set — the scheduler tracks notifiers as a slot mask and this needs
    /// handles — which makes the roster a lower bound. A lower bound is the
    /// safe direction: it can only ever make this *less* willing to call
    /// something a deadlock.
    pub fn refreshDeadlockPredictor(self: *MachOState) void {
        if (self.xenia_memory_views.ready()) {
            self.sync_object_identity.observeMappingBase(self.xenia_memory_views.mapping_base);
        }
        const ledger = &self.deadlock_predictor;
        for (&self.pthreads.threads) |*thread| {
            if (!thread.active) continue;
            const parked = switch (thread.state) {
                .waiting_mutex,
                .waiting_condvar,
                .waiting_semaphore,
                .waiting_event,
                .waiting_futex_address,
                .waiting_join,
                => true,
                else => false,
            };
            const kind: deadlock_predictor.ObjectKind = switch (thread.state) {
                .waiting_mutex => .mutex,
                .waiting_condvar => .condvar,
                .waiting_semaphore => .semaphore,
                .waiting_event => .event,
                .waiting_join => .thread_join,
                else => .unknown,
            };
            const object = if (thread.wait_address != 0)
                thread.wait_address
            else if (thread.waiting_condvar != 0)
                thread.waiting_condvar
            else
                thread.waiting_mutex;
            const state: deadlock_predictor.ThreadState = if (parked)
                .waiting
            else if (thread.state == .terminated or thread.state == .cancelled)
                .terminated
            else
                .running;
            if (parked and object != 0) ledger.observeObject(object, kind);
            ledger.observeThreadContext(.{
                .handle = thread.handle,
                .state = state,
                .waiting_on = object,
                .blocked_since_step = thread.blocked_since_step,
                .blocked_rip = thread.blocked_rip,
                .start_routine = thread.start_routine,
                .waiting_mutex = thread.waiting_mutex,
                .wait_generation = thread.wait_generation,
                .notified_generation = thread.notified_generation,
                .blocked_reason = thread.blocked_reason,
            });
        }
        for (&self.pthreads.waits.objects) |*object| {
            if (!object.active) continue;
            if (object.notifications != 0) {
                ledger.observeNotifyAt(
                    object.address,
                    .condvar,
                    object.last_notify_thread,
                    object.last_notify_pc,
                    object.last_notify_step,
                );
            }
            // A granted repair is a fact about the object that the ledger
            // cannot derive from notifications: a spurious wake is Rosette
            // manufacturing a wake, not the guest signalling. Carried over so
            // the deadlock report can distinguish "nobody ever signalled it"
            // from "we woke it once and it re-parked, so the wait is
            // genuinely unsatisfied".
            if (object.repair_attempts != 0) {
                ledger.observeRepair(object.address, object.repair_attempts);
            }
        }
        ledger.refresh(self.executed_steps);
    }

    /// Judge the releases already granted, and consider granting one more.
    ///
    /// The scheduler's own repair path performs the wake; this decides whether
    /// one is warranted and — the part that was missing — records what it
    /// proved. A release nobody reads the outcome of is a workaround; a release
    /// whose outcome is recorded is an experiment that settles which codebase
    /// the defect is in.
    pub fn refreshStallRelease(self: *MachOState) void {
        const ledger = &self.stall_release;
        const progress = self.stallReleaseProgress();

        // Settle what is outstanding first: an attempt judged against the state
        // that provoked the next one would attribute the wrong outcome.
        var index: usize = 0;
        while (index < ledger.count) : (index += 1) {
            const object = ledger.attempts[index].object;
            var re_parked = false;
            for (&self.pthreads.threads) |*thread| {
                if (!thread.active) continue;
                if (thread.waiting_condvar != object and thread.wait_address != object) continue;
                if (thread.state == .waiting_condvar) re_parked = true;
            }
            ledger.settle(object, progress, re_parked, self.executed_steps);
        }

        // A release that provably re-parked names the defect as guest-side, and
        // the waiter's own state is the only thing that makes that actionable.
        // Fetch it once per attempt: resolution, the object's ledger numbers,
        // the waiting threads, and a probe of the bytes at the object when they
        // are readable.
        for (ledger.attempts[0..ledger.count]) |attempt| {
            if (attempt.outcome != .predicate_unsatisfied or attempt.state_fetched) continue;
            self.fetchStallReleaseState(attempt.object);
            ledger.markStateFetched(attempt.object);
        }
    }

    /// Fetch the state a provably-unsatisfied waiter is waiting on, so the
    /// failure point is named rather than asserted.
    ///
    /// Three things together: where the object lives (a guest console address
    /// the emulator's view can translate, or a host-side primitive), the
    /// synchronisation ledger's own numbers for it (waiters, notifications,
    /// repairs), and the bytes at the object when they are readable — a
    /// correct waiter's predicate data sits in or near the object it waits on.
    fn fetchStallReleaseState(self: *MachOState, object: u64) void {
        // The synchronisation history this runtime keeps for the object, if it
        // has one. The repairs count is the ledger's own answer to "did we
        // already wake it and it re-parked" — the fact that separates a lost
        // wakeup from a genuinely unsatisfied predicate.
        var notifications: u64 = 0;
        var repairs: u32 = 0;
        var first_wait_step: u64 = 0;
        if (self.pthreads.waits.find(object)) |entry| {
            notifications = entry.notifications;
            repairs = entry.repair_attempts;
            first_wait_step = entry.first_wait_step;
        }

        // Where the object lives. A guest console address translates through
        // the emulator's memory view; anything else is a host-side primitive
        // whose waiter-visible predicate lives inside the guest, not here.
        var resolution: []const u8 = "host-side primitive";
        var host: u64 = object;
        if (object <= std.math.maxInt(u32)) {
            if (self.xenia_memory_views.virtualHostAddress(object)) |translated| {
                host = translated;
                resolution = "guest console address";
            }
        }

        // The waiting threads, from the scheduler's own tables, and the kind
        // they imply. A condvar waiter parks with a `waiting_condvar`; other
        // waiters carry a `wait_address`.
        var kind: []const u8 = "wait object";
        var waiter_handles: [64]u64 = undefined;
        var waiter_count: usize = 0;
        var longest_park: u64 = 0;
        for (&self.pthreads.threads) |*thread| {
            if (!thread.active) continue;
            const on_this = thread.waiting_condvar == object or thread.wait_address == object;
            if (!on_this) continue;
            if (thread.state == .waiting_condvar) kind = "condvar";
            if (waiter_count < waiter_handles.len) {
                waiter_handles[waiter_count] = thread.handle;
                waiter_count += 1;
            }
            longest_park = @max(longest_park, thread.blocked_since_step);
        }
        const parked_steps = if (longest_park != 0) self.executed_steps -| longest_park else 0;

        // Probe the bytes at the object when the emulator's memory view covers
        // them. Five dwords is enough to show an event's signal state or a
        // queue's head fields without turning the report into a memory dump.
        var probed = false;
        var dwords: [5]u32 = undefined;
        if (self.guestMemoryConst(host, 20)) |bytes| {
            for (0..5) |index| dwords[index] = std.mem.readInt(u32, bytes[index * 4 ..][0..4], .little);
            probed = true;
        }

        machoCapturePrint(
            "macho-processor: STALL RELEASE STATE: object=0x{x} kind={s} resolution={s} waiters={d} notifications={d} repairs={d} parked_steps={d} step={d}; a spurious wake already proved this predicate unsatisfied — the code that should have published the state it waits on never ran\n",
            .{
                object,        kind,    resolution,   waiter_count,
                notifications, repairs, parked_steps, self.executed_steps,
            },
        );
        if (probed) {
            machoCapturePrint(
                "  bytes at 0x{x}: q0=0x{x:0>8} q1=0x{x:0>8} q2=0x{x:0>8} q3=0x{x:0>8} q4=0x{x:0>8} {s}\n",
                .{
                    host, dwords[0], dwords[1], dwords[2], dwords[3], dwords[4],
                    if (resolution[0] == 'g')
                        "the waiter's predicate data is the guest memory behind this object"
                    else
                        "host-side primitive internals; the waiter's predicate lives inside the guest, not at this address",
                },
            );
        } else {
            machoCapturePrint(
                "  object memory not readable through the emulator's memory view (host=0x{x}); the waiter's predicate state is elsewhere — in the guest object's own fields, not in this runtime's copy of it\n",
                .{host},
            );
        }
        for (waiter_handles[0..waiter_count]) |handle| {
            machoCapturePrint(
                "  waiter thread=0x{x} parked_steps={d} first_wait_step={d}\n",
                .{ handle, parked_steps, first_wait_step },
            );
        }
    }

    /// The progress witness a release is judged against.
    ///
    /// The same axes the wait audit uses, so a release and a wait pattern can
    /// never disagree about whether the run moved. Deliberately excludes
    /// retired instructions: a livelock produces billions of those and would
    /// make every release look like it worked.
    fn stallReleaseProgress(self: *const MachOState) u64 {
        return self.wait_audit.witness.get(.pipeline_stage) +
            self.wait_audit.witness.get(.ring_publication) +
            self.wait_audit.witness.get(.gpu_callback) +
            self.wait_audit.witness.get(.module_load) +
            self.wait_audit.witness.get(.presented_frame);
    }

    /// Record a release the notifier-liveness path performed.
    ///
    /// The wake itself belongs there — it owns the selector and the generation
    /// guard — and this owns the question of what it proved. Calling the wake
    /// from both places would grant two per checkpoint and quietly turn a
    /// bounded experiment into a policy.
    pub fn noteStallReleaseGranted(self: *MachOState, object: u64, thread: u64, waited_steps: u64) void {
        const progress = self.stallReleaseProgress();
        const decision = self.stall_release.authorise(
            object,
            1,
            0,
            waited_steps,
            notifier_liveness.default_stall_steps,
        );
        if (!decision.granted()) return;
        self.stall_release.noteReleased(object, 0, thread, progress, self.executed_steps);
        machoCapturePrint(
            "macho-processor: STALL RELEASE: recorded object=0x{x} thread=0x{x} waited_steps={d} progress_witness={d} step={d}; {s}\n",
            .{ object, thread, waited_steps, progress, self.executed_steps, decision.meaning() },
        );
    }

    /// Which subsystem failed to come up, and whether that is why the run
    /// stopped moving.
    pub fn logBringupFailures(self: *MachOState) void {
        const ledger = &self.bringup_failures;
        if (ledger.count == 0) return;
        // The same witness the wait audit classifies against, so the two can
        // never disagree about whether the run is moving.
        ledger.noteProgress(self.stallReleaseProgress(), self.executed_steps);
        const finding = ledger.finding(self.executed_steps);
        machoCapturePrint(
            "macho-processor: BRINGUP FAILURE: finding={s} failures={d} dropped={d} progress={d} last_progress_step={d} step={d}; {s}\n",
            .{
                finding.label(),
                ledger.count,
                ledger.dropped,
                ledger.progress,
                ledger.last_progress_step,
                self.executed_steps,
                ledger.verdict(self.executed_steps),
            },
        );
        for (ledger.failures[0..ledger.count]) |entry| {
            machoCapturePrint(
                "  subsystem {s: <24} {s: <10} step={d} thread_exited={s} reason='{s}'\n",
                .{
                    entry.subsystem.label(),
                    ledger.classify(entry, self.executed_steps).label(),
                    entry.step,
                    if (entry.thread_exited) "YES" else "NO",
                    entry.reason(),
                },
            );
        }
        if (ledger.root(self.executed_steps)) |root| machoCapturePrint(
            "macho-processor: BRINGUP FAILURE: ROOT subsystem={s} step={d} — {s}\n",
            .{ root.subsystem.label(), root.step, root.subsystem.blocks() },
        );
    }

    /// What the bounded releases proved.
    pub fn logStallRelease(self: *MachOState) void {
        self.refreshStallRelease();
        const ledger = &self.stall_release;
        if (ledger.count == 0 and ledger.refusals == 0) return;
        machoCapturePrint(
            "macho-processor: STALL RELEASE: objects={d} attempts={d}/{d} decisive={d} refusals={d} last_refusal={s} step={d}; {s}\n",
            .{
                ledger.count,
                ledger.total_attempts,
                stall_release.max_attempts_total,
                ledger.decisiveCount(),
                ledger.refusals,
                if (ledger.last_refusal) |refusal| refusal.label() else "-",
                self.executed_steps,
                ledger.verdict(),
            },
        );
        for (ledger.attempts[0..ledger.count]) |attempt| {
            machoCapturePrint(
                "  release object=0x{x:0>8} thread=0x{x} attempts={d} {s: <22} progress={d}->{d} released_step={d}\n",
                .{
                    attempt.object,
                    attempt.thread,
                    attempt.attempts,
                    attempt.outcome.label(),
                    attempt.progress_before,
                    attempt.progress_after,
                    attempt.released_step,
                },
            );
            if (attempt.outcome.decisive()) machoCapturePrint(
                "    verdict: {s}\n",
                .{attempt.outcome.meaning()},
            );
        }
    }

    /// Score the host capability surface from what this run actually observed.
    ///
    /// Derived rather than maintained, like the graphics contract: every fact
    /// already exists in some subsystem, and the value here is the join plus
    /// the weighting. A second copy of the truth is how two reports in one run
    /// end up contradicting each other.
    pub fn refreshHostCoverage(self: *MachOState) void {
        const C = host_contract_coverage.Capability;
        const ledger = &self.host_coverage;

        if (self.xenia_memory_views.ready()) {
            ledger.record(C.address_space_translation, .satisfied, "console memory view base discovered");
        }
        if (self.executed_steps != 0) {
            ledger.record(C.guest_memory_mapping, .satisfied, "guest image mapped and executing");
        }
        ledger.record(
            C.memory_protection,
            if (self.gpu_register_aperture_reachable) .satisfied else .untested,
            "aperture handler registration is the only reachability evidence",
        );
        if (self.pthreads.created_threads != 0) {
            ledger.record(C.thread_creation, .satisfied, "guest threads created and scheduled");
            ledger.record(C.thread_scheduling, .satisfied, "cooperative rotation is running");
            ledger.record(C.sync_primitives, .satisfied, "mutexes and condvars are servicing guest waits");
        }

        // The wait handshake is scored from the audit rather than from call
        // counts: a handshake that answers every call and never releases anyone
        // is exactly the degraded state this model exists to name.
        const problems = self.wait_audit.problemCount(self.executed_steps);
        if (self.wait_audit.count != 0) {
            ledger.record(
                C.wait_signal_handshake,
                if (problems == 0) .satisfied else .degraded,
                if (problems == 0) "every observed pattern advanced the run alongside it" else "at least one object is waited on and never signalled",
            );
        }

        if (self.fs_forwarder.open_count != 0) {
            ledger.record(C.file_read, .satisfied, "guest file reads are being serviced");
        }
        if (self.xenia_pipeline.hasReached(.disc_mounted)) {
            ledger.record(C.disc_image, .satisfied, "disc image mounted");
        }

        const variables = self.gpu_kernel_variables.finding();
        if (variables.imported_count != 0) {
            ledger.record(
                C.kernel_variable_surface,
                if (variables.blocking == null) .satisfied else .unsatisfied,
                "every imported kernel variable resolves through both dereferences",
            );
        }
        if (self.gpu_import_binding.count != 0) {
            ledger.record(
                C.kernel_export_binding,
                if (self.gpu_import_binding.worst().healthy()) .satisfied else .unsatisfied,
                "probed imports are committed, translatable and begin with the export stub",
            );
        }

        if (self.gpu_bootstrap.seen(.initialize_engines)) {
            ledger.record(C.gpu_engine_init, .satisfied, "VdInitializeEngines ran");
        }
        if (self.gpu_ring_watch_base != 0) {
            ledger.record(C.gpu_ring_buffer, .satisfied, "ring geometry established and readable");
        }
        if (self.gpu_bootstrap.seen(.graphics_interrupt_dispatch)) {
            ledger.record(C.gpu_interrupt_callback, .satisfied, "callback registered and dispatched");
        }
        if (self.execution_tracepoints.roleEntered(.command_processor)) {
            ledger.record(C.gpu_command_flow, .satisfied, "the command processor drained a batch");
        }
        ledger.record(
            C.guest_swap_request,
            if (self.execution_tracepoints.roleEntered(.swap)) .satisfied else .unsatisfied,
            "VdSwap has never been entered",
        );

        // Score the guest Vulkan path from driver-bound work, not from the
        // existence of a proc token or a successful synthetic return. Real
        // command recording and queue submission are meaningful host
        // execution evidence; a present without either is still only a
        // request for a diagnostic refresh.
        const observed_commands = self.dynamic_forwarder.guestVulkanObservedCommands();
        const real_commands = self.dynamic_forwarder.guestVulkanCommandsForwarded();
        const real_submits = self.dynamic_forwarder.guestVulkanQueueSubmits();
        ledger.record(
            C.graphics_command_execution,
            if (real_submits != 0)
                .satisfied
            else if (real_commands != 0)
                .degraded
            else if (observed_commands != 0)
                .degraded
            else
                .untested,
            if (real_submits != 0)
                "guest command buffers reached native Vulkan and were submitted"
            else if (real_commands != 0)
                "guest command buffers reached native Vulkan but no native submission was observed"
            else if (observed_commands != 0)
                "guest Vulkan commands were observed but had no native command-buffer mapping"
            else
                "no guest Vulkan command recording has been observed",
        );
        ledger.record(
            C.frame_source,
            if (self.dynamic_forwarder.guestFrontBufferAvailable()) .satisfied else .unsatisfied,
            "no guest-produced image has ever held a picture",
        );
        if (self.native_window.layer_attachments != 0) {
            ledger.record(C.window_surface, .satisfied, "Cocoa layer attached and the presenter is bound");
        }
        const frames = self.dynamic_forwarder.nativePresenterFramesPresented();
        const real_presents = self.dynamic_forwarder.guestVulkanPresents();
        ledger.record(
            C.frame_presentation,
            if (self.dynamic_forwarder.guestFrontBufferAvailable())
                .satisfied
            else if (real_presents != 0)
                .degraded
            else if (frames == 0)
                .unsatisfied
            else
                .degraded,
            if (self.dynamic_forwarder.guestFrontBufferAvailable())
                "console front-buffer pixels were converted and handed to the presenter"
            else if (real_presents != 0)
                "guest vkQueuePresentKHR reached the native driver; visible pixels remain runtime-unvalidated"
            else if (frames == 0)
                "no frame has reached a presenter"
            else
                "only Rosette diagnostic frames have reached the window",
        );

        if (self.guest_exceptions.total_throws != 0) {
            ledger.record(
                C.exception_unwinding,
                if (self.guest_exceptions.worst() == null) .satisfied else .degraded,
                "phase-1 walk, handler install and catch retirement all complete",
            );
        }
        ledger.record(
            C.code_generation,
            if (self.deferred_work.total_failures == 0) .satisfied else .degraded,
            "translation works except for functions an emitter error left undefined",
        );
        if (self.dynamic_forwarder.forwarded != 0) {
            ledger.record(C.locale_and_time, .satisfied, "host library forwarding is servicing queries");
        }
    }

    /// The zoomed-out view: how much of the host contract works.
    pub fn logHostCoverage(self: *MachOState) void {
        self.refreshHostCoverage();
        const ledger = &self.host_coverage;
        const report = ledger.report();
        machoCapturePrint(
            "macho-processor: HOST CONTRACT COVERAGE: {d}% satisfied={d} degraded={d} unsatisfied={d} untested={d} of {d} step={d}; {s}\n",
            .{
                report.percent(),
                report.satisfied,
                report.degraded,
                report.unsatisfied,
                report.untested,
                host_contract_coverage.capability_count,
                self.executed_steps,
                ledger.verdict(),
            },
        );
        inline for (@typeInfo(host_contract_coverage.Layer).@"enum".fields) |field| {
            const layer: host_contract_coverage.Layer = @enumFromInt(field.value);
            const score = ledger.layerScore(layer);
            machoCapturePrint(
                "  layer {s: <18} {d: >3}%\n",
                .{ layer.label(), score.percent() },
            );
        }
        if (ledger.weakestLayer()) |weakest| machoCapturePrint(
            "macho-processor: HOST CONTRACT COVERAGE: weakest layer is {s} at {d}% — this is where the next hour belongs, not wherever the last frontier happened to point\n",
            .{ weakest.layer.label(), weakest.percent() },
        );
        var gaps: [host_contract_coverage.capability_count]host_contract_coverage.Capability = undefined;
        for (ledger.criticalGaps(&gaps)) |capability| {
            const entry = ledger.entry(capability);
            machoCapturePrint(
                "  critical gap {s: <34} {s: <12} layer={s} — {s}\n",
                .{ capability.label(), entry.status.label(), capability.layer().label(), entry.note() },
            );
        }
    }

    /// Sample the independent progress axes the wait audit classifies against.
    ///
    /// Each axis is driven by a different subsystem, so a wait can freeze one
    /// without freezing the others — and which ones it freezes is the finding.
    /// Sampled here rather than at each observation because the observation
    /// sites are in the log parser, which has no view of the run as a whole.
    pub fn refreshWaitAuditWitness(self: *MachOState) void {
        var stages: u64 = 0;
        for (self.xenia_pipeline.reached) |reached| {
            if (reached) stages += 1;
        }
        self.wait_audit.noteProgress(.pipeline_stage, stages);
        self.wait_audit.noteProgress(.ring_publication, self.gpu_ring_publication.advances);
        self.wait_audit.noteProgress(
            .gpu_callback,
            if (self.gpu_bootstrap.seen(.graphics_interrupt_dispatch)) 1 else 0,
        );
        self.wait_audit.noteProgress(.module_load, self.guest_modules.count);
        self.wait_audit.noteProgress(
            .presented_frame,
            self.dynamic_forwarder.nativePresenterFramesPresented(),
        );
        self.wait_audit.noteProgress(.executed_steps, self.executed_steps);
    }

    /// Which repeating waits are problems, and the full audit for those only.
    ///
    /// The suppression is the point. A run has many handshakes and most of them
    /// work; printing every one buries the one that does not, and the operator
    /// then reads twelve healthy pumps looking for a defect that is on line
    /// thirteen.
    pub fn logWaitAudit(self: *MachOState) void {
        self.refreshWaitAuditWitness();
        const ledger = &self.wait_audit;
        const problems = ledger.problemCount(self.executed_steps);
        machoCapturePrint(
            "macho-processor: WAIT AUDIT: subjects={d} problems={d} suppressed={d} dropped={d} step={d}; {s}\n",
            .{
                ledger.count,
                problems,
                ledger.count - problems,
                ledger.dropped,
                self.executed_steps,
                ledger.verdict(self.executed_steps),
            },
        );
        // One line per subject, whatever its classification: a reader needs to
        // know a pump exists and was judged healthy, or the suppression looks
        // like the subsystem missing it.
        for (ledger.subjects[0..ledger.count]) |subject| {
            const classification = ledger.classify(subject, self.executed_steps);
            machoCapturePrint(
                "  subject object=0x{x:0>8} handle=0x{x:0>8} type={d} {s: <21} waits={d} timeouts={d} signals={d} threads={d} period_steps={d}\n",
                .{
                    subject.object,
                    subject.handle,
                    subject.type_code,
                    classification.label(),
                    subject.waits,
                    subject.timeouts,
                    subject.signals,
                    subject.participant_count,
                    subject.periodSteps(),
                },
            );
            if (!classification.worthAuditing()) continue;

            // The full audit, for problems only.
            machoCapturePrint(
                "    audit: first_step={d} last_step={d} sightings={d}; {s}\n",
                .{ subject.first_step, subject.last_step, subject.sightings(), classification.meaning() },
            );
            for (subject.participants[0..subject.participant_count]) |thread| {
                machoCapturePrint("    participant thread=0x{x}\n", .{thread});
            }
            var axes: [wait_audit.axis_count]wait_audit.Axis = undefined;
            const frozen = ledger.frozenAxes(subject, &axes);
            if (frozen.len == 0) continue;
            machoCapturePrint("    holding back:", .{});
            for (frozen) |axis| machoCapturePrint(" {s}", .{axis.label()});
            machoCapturePrint(
                " — these are the subsystems that have not advanced once since this pattern started. Anything not listed here kept working, so this wait is not what is blocking it\n",
                .{},
            );
        }
    }

    /// Threads parked forever, and the reason nobody can release them.
    pub fn logDeadlockPredictor(self: *MachOState) void {
        // The identity table decides whether any of this is about one object or
        // two, so it is reported alongside rather than buried.
        const identity = &self.sync_object_identity;
        if (identity.count != 0 or identity.rewrites != 0) machoCapturePrint(
            "macho-processor: SYNC OBJECT IDENTITY: pairs={d} rewrites={d} conflicts={d} dropped={d} mapping_base=0x{x}; {s}\n",
            .{ identity.count, identity.rewrites, identity.conflicts, identity.dropped, identity.mapping_base, identity.verdict() },
        );
        self.refreshDeadlockPredictor();
        const ledger = &self.deadlock_predictor;
        const worst = ledger.worst();
        machoCapturePrint(
            "macho-processor: DEADLOCK PREDICTOR: finding={s} objects={d} threads={d} parked={d} deadlocked={s} untracked(threads/objects)={d}/{d} step={d}; {s}\n",
            .{
                worst.finding.label(),
                ledger.object_count,
                ledger.thread_count,
                ledger.parkedThreadCount(),
                if (worst.finding.deadlocked()) "YES" else "NO",
                ledger.untracked_threads,
                ledger.untracked_objects,
                self.executed_steps,
                ledger.verdict(),
            },
        );
        if (worst.object) |object| {
            machoCapturePrint(
                "  blocking object=0x{x} kind={s} waiters={d} notifiers={d} notifications={d} repairs={d} longest_park_steps={d} last_notify(step={d} thread=0x{x} pc=0x{x})\n",
                .{
                    object.address,
                    object.kind.label(),
                    object.waiters,
                    object.notifier_count,
                    object.notifications,
                    object.repair_attempts,
                    object.longest_park_steps,
                    object.last_notify_step,
                    object.last_notify_thread,
                    object.last_notify_pc,
                },
            );
            var waiters: [deadlock_predictor.max_threads]deadlock_predictor.Thread = undefined;
            for (ledger.waitersFor(object.address, &waiters)) |waiter| {
                machoCapturePrint(
                    "  blocking waiter thread=0x{x} start=0x{x} wait_rip=0x{x} mutex=0x{x} generation={d}/{d} blocked_since_step={d} age_steps={d} reason={s}\n",
                    .{
                        waiter.handle,
                        waiter.start_routine,
                        waiter.blocked_rip,
                        waiter.waiting_mutex,
                        waiter.wait_generation,
                        waiter.notified_generation,
                        waiter.blocked_since_step,
                        self.executed_steps -| waiter.blocked_since_step,
                        if (waiter.blocked_reason.len != 0) waiter.blocked_reason else "unknown",
                    },
                );
                if (waiter.blocked_rip != 0) {
                    machoCapturePrint(
                        "    blocking waiter symbol={s} start_symbol={s}; this is the last guest/host boundary retained for the parked context\n",
                        .{ self.metadata.symbolLabel(waiter.blocked_rip), self.metadata.symbolLabel(waiter.start_routine) },
                    );
                }
            }
            if (object.repair_attempts != 0) {
                machoCapturePrint(
                    "  repair note: a bounded spurious wake was granted {d} time(s) and the waiter re-parked — the predicate is genuinely unsatisfied, so this is a guest-side deadlock (the creator never published the state it waits on), not a lost wakeup. Find the code that should have published it and confirm it ran; the once-per-generation guard stops further wakes\n",
                    .{object.repair_attempts},
                );
            }
        }
        // A cycle is a stronger statement than "no live root", so it is looked
        // for explicitly rather than inferred from the classification.
        for (ledger.threads[0..ledger.thread_count]) |thread| {
            if (!thread.state.parked()) continue;
            var chain: [8]u64 = undefined;
            const cycle = ledger.findCycle(thread.handle, &chain) orelse continue;
            machoCapturePrint(
                "macho-processor: DEADLOCK PREDICTOR: WAIT_CYCLE length={d} — {s}\n",
                .{ cycle.len, deadlock_predictor.Finding.wait_cycle.meaning() },
            );
            for (cycle, 0..) |handle, index| {
                machoCapturePrint("    cycle[{d}] thread=0x{x}\n", .{ index, handle });
            }
            break;
        }
    }

    /// Whether the run's caught exceptions recovered anything.
    pub fn logGuestExceptions(self: *MachOState) void {
        const ledger = &self.guest_exceptions;
        // Throwing is ordinary C++ control flow; a run with no exceptions and
        // no concern does not need a line on every checkpoint.
        if (ledger.total_throws == 0) return;
        machoCapturePrint(
            "macho-processor: GUEST EXCEPTION PREDICTOR: types={d} throws={d} catches={d} concerning={s} dropped={d} step={d}; {s}\n",
            .{
                ledger.count,
                ledger.total_throws,
                ledger.total_catches,
                if (ledger.worst() != null) "YES" else "NO",
                ledger.dropped,
                self.executed_steps,
                ledger.verdict(),
            },
        );
        for (ledger.records[0..ledger.count]) |record| {
            machoCapturePrint(
                "  exception type={s} outcome={s} throws={d} catches={d} code={d} unwind_frames={d} first_step={d} last_step={d} site={s}\n",
                .{
                    record.name(),
                    record.outcome.label(),
                    record.throws,
                    record.catches,
                    record.code,
                    record.unwind_frames,
                    record.first_step,
                    record.last_step,
                    record.site(),
                },
            );
        }
    }

    /// Deferrals that became crashes, and the ones that are about to.
    pub fn logDeferredWork(self: *MachOState) void {
        const ledger = &self.deferred_work;
        const finding = ledger.finding();
        // Deferral is how the system works; a quiet ledger with nothing
        // outstanding is not worth a line on every checkpoint.
        if (finding == .quiet and ledger.total_failures == 0) return;
        machoCapturePrint(
            "macho-processor: DEFERRED WORK PREDICTOR: finding={s} deferrals={d} failures={d} demands={d} latent={d} fatal={d} unrecorded_demands={d} dropped={d} step={d}; {s}\n",
            .{
                finding.label(),
                ledger.total_deferrals,
                ledger.total_failures,
                ledger.total_demands,
                ledger.latentCount(),
                ledger.fatalCount(),
                ledger.demands_without_record,
                ledger.dropped,
                self.executed_steps,
                finding.meaning(),
            },
        );
        for (ledger.items[0..ledger.count]) |item| {
            if (item.disposition != .failed) continue;
            machoCapturePrint(
                "  deferred id=0x{x} kind={s} {s} deferred_step={d} demanded_step={d} demands={d} reason='{s}' — {s}\n",
                .{
                    item.id,
                    item.kind.label(),
                    item.disposition.label(),
                    item.deferred_step,
                    item.demanded_step,
                    item.demands,
                    item.reason(),
                    item.kind.consequence(),
                },
            );
        }
    }

    /// What the emulator's callback-missing probe actually found.
    pub fn logImportBinding(self: *MachOState) void {
        const ledger = &self.gpu_import_binding;
        machoCapturePrint(
            "macho-processor: IMPORT BINDING: probed={d} bound={d} worst={s} probes={d} untracked={d} step={d}; {s}\n",
            .{
                ledger.count,
                ledger.boundCount(),
                ledger.worst().label(),
                ledger.total_probes,
                ledger.untracked_probes,
                self.executed_steps,
                ledger.verdict(),
            },
        );
        for (ledger.entries[0..ledger.count]) |entry| {
            machoCapturePrint(
                "  import 0x{x:0>3} {s: <17} slot=0x{x:0>8} -> 0x{x:0>8} thunk=0x{x:0>8} words={x:0>8}/{x:0>8} export_stub={s} probes={d}\n",
                .{
                    entry.ordinal,
                    entry.binding.label(),
                    entry.slot_address,
                    entry.slot_word,
                    entry.thunk_address,
                    entry.thunk_word0,
                    entry.thunk_word1,
                    if (gpu.import_binding.isExportThunk(entry.thunk_word0, entry.thunk_word1)) "YES" else "NO",
                    entry.probes,
                },
            );
        }
    }

    /// Which observers believe the write pointer moved, and whether they agree.
    fn logSubmissionProvenance(self: *MachOState) void {
        const ledger = &self.gpu_submission_provenance;
        // Rosette's tracker is fed by parsing a line the emulator printed, so
        // it is recorded as the log-line source and never as a stronger one.
        ledger.record(.emulator_log_line, true, self.gpu_ring_publication.writes);
        ledger.record(.emulator_counter, self.gpu_xenia_wptr_counter_seen, self.gpu_xenia_wptr_updates);
        ledger.record(
            .guest_register_store,
            true,
            self.gpu_register_aperture.total_writes,
        );
        ledger.record(.ring_memory_contents, self.gpu_ring_watch_base != 0, self.gpu_ring_nonzero_dwords);

        const finding = ledger.finding();
        machoCapturePrint(
            "macho-processor: SUBMISSION PROVENANCE: finding={s} strongest_pointer_evidence={s} active_observers={d} undermines_publication={s} step={d}; {s}\n",
            .{
                finding.label(),
                if (ledger.strongestPointerEvidence()) |source| source.label() else "<none>",
                ledger.activeCount(),
                if (finding.undermines_publication()) "YES" else "NO",
                self.executed_steps,
                finding.meaning(),
            },
        );
        const consumer_observed = self.gpu_ring_publication.consumerSawBatch() or
            self.gpu_xenos_runtime.batches != 0 or
            self.xenia_gpu_handoff.pm4_packets != 0;
        machoCapturePrint(
            "  consumer evidence: observed={s} stateful_batches={d} handoff_packets={d} consumed_dwords={d} root_or_nested_packets={d} root_or_nested_draws={d} swaps={d} first_step={d} last_step={d}; this is independent of pointer provenance\n",
            .{
                if (consumer_observed) "YES" else "NO",
                self.gpu_xenos_runtime.batches,
                self.xenia_gpu_handoff.pm4_packets,
                self.gpu_ring_publication.consumed_batch_dwords,
                self.gpu_ring_publication.consumed_batch_packets,
                self.gpu_ring_publication.consumed_batch_draws,
                self.gpu_ring_publication.consumed_batch_swaps,
                self.gpu_ring_publication.first_consumed_step,
                self.gpu_ring_publication.last_consumed_step,
            },
        );
        inline for (.{
            gpu.submission_provenance.Source.emulator_log_line,
            gpu.submission_provenance.Source.emulator_counter,
            gpu.submission_provenance.Source.guest_register_store,
            gpu.submission_provenance.Source.ring_memory_contents,
        }) |source| {
            const observation = ledger.get(source);
            machoCapturePrint(
                "  observer {s: <22} active={s: <3} events={d: <8} {s}\n",
                .{
                    source.label(),
                    if (observation.active) "YES" else "NO",
                    observation.events,
                    source.strength(),
                },
            );
        }
    }

    /// Hand the console's own framebuffer to the presenter.
    ///
    /// Two translations stand between the swap packet and readable memory: the
    /// address it carries is a console *physical* address, and the emulator
    /// projects console physical memory into this process at a base it
    /// discovered at startup. Both are already modelled, and doing the join
    /// here keeps the presentation layer from having to know that an emulated
    /// console's address space exists at all.
    ///
    /// The surface description comes from the fetch constant the swap was
    /// written next to, not from a default. Tiling and byte order are the two
    /// facts that turn a correct read into a sheared or colour-swapped picture,
    /// and neither produces an error when wrong — so when the fetch constant is
    /// absent this says so and assumes the common case out loud.
    fn offerGuestFrontBuffer(
        self: *MachOState,
        swap: gpu.Pm4SwapDescription,
        fetch: ?gpu.Pm4FetchConstant,
    ) void {
        const host = self.xenia_memory_views.physicalHostAddress(swap.frontbuffer_physical_address) orelse {
            machoCapturePrint(
                "macho-processor: GUEST FRONT BUFFER: console physical 0x{x:0>8} could not be translated; the emulator's memory view base has not been discovered, so its framebuffer is unreadable from here\n",
                .{swap.frontbuffer_physical_address},
            );
            return;
        };
        const resolved = self.tryResolveXenosColorToFrontBuffer(swap, host);
        const tiled = if (resolved) false else if (fetch) |constant| constant.tiled() else true;
        const endian: gpu.xenos_texture.Endian = if (resolved)
            .none
        else if (fetch) |constant|
            @enumFromInt(constant.endianness())
        else
            .@"8in32";
        self.dynamic_forwarder.noteGuestFrontBuffer(host, swap.width, swap.height, tiled, endian);
        if (!self.gpu_frontbuffer_offered) {
            self.gpu_frontbuffer_offered = true;
            machoCapturePrint(
                "macho-processor: GUEST FRONT BUFFER: console physical 0x{x:0>8} -> 0x{x} extent={d}x{d} tiled={s} endian={s} fetch={s}; the presenter will convert and show these pixels ahead of any emulator Vulkan image, because they are the console's own framebuffer\n",
                .{
                    swap.frontbuffer_physical_address,                                                                                                                                                                                 host,
                    swap.width,                                                                                                                                                                                                        swap.height,
                    if (tiled) "YES" else "NO",                                                                                                                                                                                        endian.label(),
                    if (resolved) "EDRAM RESOLVE (linear RGBA8)" else if (fetch != null) "observed" else "ABSENT (tiling and byte order assumed; a wrong assumption here produces a sheared or colour-swapped picture, not an error)",
                },
            );
        }
    }

    /// Resolve the stateful Xenos color target into the guest framebuffer when
    /// the PM4 runtime has a real EDRAM result. The compact PM4 executor does
    /// not claim to rasterize shaders, so an all-zero store is deliberately
    /// ignored instead of replacing a title-owned framebuffer with black.
    /// Successful resolves are linear RGBA8 and the caller presents them as
    /// linear/none, avoiding a second guest tiling or endian transform.
    fn tryResolveXenosColorToFrontBuffer(self: *MachOState, swap: gpu.Pm4SwapDescription, host: u64) bool {
        if (self.gpu_xenos_runtime.last_draw == null) return false;
        if (swap.width == 0 or swap.height == 0 or swap.width > 4096 or swap.height > 4096) return false;
        const pitch_u64 = std.math.mul(u64, swap.width, 4) catch return false;
        const bytes_u64 = std.math.mul(u64, pitch_u64, swap.height) catch return false;
        if (bytes_u64 > std.math.maxInt(usize)) return false;
        const bytes_len: usize = @intCast(bytes_u64);
        if (self.gpu_xenos_resolve_scratch.len < bytes_len) {
            const replacement = self.allocator.alloc(u8, bytes_len) catch return false;
            if (self.gpu_xenos_resolve_scratch.len != 0) self.allocator.free(self.gpu_xenos_resolve_scratch);
            self.gpu_xenos_resolve_scratch = replacement;
        }
        const scratch = self.gpu_xenos_resolve_scratch[0..bytes_len];
        @memset(scratch, 0);
        self.gpu_xenos_runtime.resolveCurrentColor(swap.width, swap.height, scratch, @intCast(pitch_u64)) catch return false;

        var any_nonzero = false;
        for (scratch) |byte| {
            if (byte != 0) {
                any_nonzero = true;
                break;
            }
        }
        if (!any_nonzero) return false;
        const destination = self.guestMemory(host, bytes_u64) orelse return false;
        const mutation = self.captureMemoryMutation(host, bytes_u64);
        @memcpy(destination, scratch);
        self.commitMemoryMutation(mutation, .bulk_copy);
        machoCapturePrint(
            "macho-processor: XENOS EDRAM resolve: target=0x{x} extent={d}x{d} bytes={d} source=stateful_color_target destination=guest_front_buffer\n",
            .{ host, swap.width, swap.height, bytes_len },
        );
        return true;
    }

    /// Whether the harness stood in for the title, and if not, what stopped it.
    pub fn logSwapSubstitution(self: *MachOState) void {
        self.refreshVdSwapContract();
        const publication = &self.gpu_ring_publication;
        const stalled = publication.last_advance_step != 0 and
            self.executed_steps > publication.last_advance_step;
        const evidence = gpu.SubstitutionEvidence{
            .ring_published = publication.advances != 0,
            // The tracepoint is useful when Xenia's own command-processor
            // symbol is reached, but the stateful Rosette consumer can prove
            // the same boundary by draining the retained ring before that
            // symbol is visible. Keep both sources: substitution must not
            // call a consumed batch "unconsumed" merely because the generic
            // tracepoint missed an indirect-buffer route.
            .pm4_consumed = self.execution_tracepoints.roleEntered(.command_processor) or
                publication.consumerSawBatch() or
                self.gpu_xenos_runtime.batches != 0 or
                self.xenia_gpu_handoff.pm4_packets != 0,
            .draws_issued = self.gpu_ring_draws_seen,
            .authentic_swap_seen = self.gpu_vd_swap_contract.authentic_consumptions != 0,
            .steps_since_publish = if (stalled) self.executed_steps - publication.last_advance_step else 0,
            .ring_geometry_known = self.gpu_ring_watch_base != 0,
            .ring_drained = publication.drained_observations != 0,
            .frontbuffer_known = self.gpu_vd_swap_contract.frontbufferKnown(),
            .discovered_output_available = self.dynamic_forwarder.guestFrontBufferAvailable(),
            // The channel is open when the ring's host projections are writable
            // from here: the packet, and the write-pointer value it implies,
            // can be delivered into the ring memory the emulator reads. What a
            // memory write cannot reach is the emulator's own memory-mapped
            // register store — its stores are executed by guest code — and that
            // boundary is stated out loud in the SYNTHETIC QUEUE line rather
            // than hidden.
            .write_pointer_channel_available = self.gpu_ring_watch_host_physical != 0 or
                self.gpu_ring_watch_host_virtual != 0,
        };
        const decision = gpu.swap_substitution.decide(evidence, gpu.swap_substitution.default_quiet_steps);
        const triggers_before = self.gpu_swap_substitution.triggers;
        self.gpu_swap_substitution.record(decision, self.executed_steps);
        // Execute the tier the decision authorised, once per substitution
        // episode. The decision stays `substituting` for every heartbeat while
        // the producer is quiet, so gating on the trigger count is what stops
        // the queue from re-injecting the same packet on a loop — a livelock
        // of the harness's own making. Only tiers that fabricate guest
        // behaviour write a packet: presenting the guest's own discovered
        // pixels invents nothing and has no packet.
        if (decision.tier.fabricatesGuestBehaviour() and
            self.gpu_swap_substitution.triggers > triggers_before)
        {
            self.runSyntheticQueue();
        }

        machoCapturePrint(
            "macho-processor: SWAP SUBSTITUTION: tier={s} blocked_by={s} step={d} triggers={d} presented={d} packets={d} pointers={d} fabricated={s}; {s}\n",
            .{
                decision.tier.label(),
                if (decision.blocked_by) |reason| @tagName(reason) else "-",
                self.executed_steps,
                self.gpu_swap_substitution.triggers,
                self.gpu_swap_substitution.presented_discovered,
                self.gpu_swap_substitution.packets_published,
                self.gpu_swap_substitution.pointers_advanced,
                if (self.gpu_swap_substitution.fabricatedAnything()) "YES" else "NO",
                self.gpu_swap_substitution.verdict(),
            },
        );
        machoCapturePrint(
            "  evidence: published={s} consumed={s} drew={s} authentic_swap={s} quiet_steps={d} geometry={s} drained={s} frontbuffer={s} wptr_channel={s}\n",
            .{
                if (evidence.ring_published) "YES" else "NO",
                if (evidence.pm4_consumed) "YES" else "NO",
                if (evidence.draws_issued) "YES" else "NO",
                if (evidence.authentic_swap_seen) "YES" else "NO",
                evidence.steps_since_publish,
                if (evidence.ring_geometry_known) "YES" else "NO",
                if (evidence.ring_drained) "YES" else "NO",
                if (evidence.frontbuffer_known) "YES" else "NO",
                if (evidence.write_pointer_channel_available) "YES" else "NO",
            },
        );
        if (decision.blocked_by) |reason| {
            if (reason != .not_triggered) machoCapturePrint(
                "macho-processor: SWAP SUBSTITUTION: blocked — {s}\n",
                .{reason.label()},
            );
        }
        if (decision.tier.fabricatesGuestBehaviour()) {
            _ = self.graphics_contract.substitute(.guest_swap_entered, self.executed_steps);
        }
        const vd_frontier = self.gpu_vd_swap_contract.frontier();
        machoCapturePrint(
            "macho-processor: SWAP SUBSTITUTION CONTRACT: frontier={s} owner={s} blocker={s} frontbuffer={s} packet_seen={s} authentic_consumed={s}; {s}\n",
            .{
                if (vd_frontier.stage) |stage| stage.label() else "<complete>",
                vd_frontier.owner.label(),
                vd_frontier.blocker.label(),
                if (self.gpu_vd_swap_contract.frontbufferKnown()) "YES" else "NO",
                if (self.gpu_vd_swap_contract.packetSeen()) "YES" else "NO",
                if (self.gpu_vd_swap_contract.authentic_consumptions != 0) "YES" else "NO",
                vd_frontier.blocker.guidance(),
            },
        );
    }

    /// Perform the tier the substitution authorised: write the swap packet the
    /// title never wrote into the ring it published, and state the write
    /// pointer that publication requires.
    ///
    /// The packet is data in memory the harness already owns, and everything
    /// downstream of the write — decode, issue, refresh, present — is the
    /// emulator's authentic code path. What no memory write can do is advance
    /// the emulator's own memory-mapped write pointer register: its stores are
    /// executed by guest code inside the emulator, so the value is computed,
    /// recorded in the injection ledger, and reported as exactly the value the
    /// guest must publish. The emulator's ring-change watch is the channel
    /// that can act on it.
    fn runSyntheticQueue(self: *MachOState) void {
        const ledger = &self.gpu_ring_injection;
        const publication = &self.gpu_ring_publication;

        // The write pointer the packet goes at. The geometry carries the
        // emulator's own pointer pair when it reports one; the tracker's last
        // observed value is the fallback. Either way the refusal is named, not
        // swallowed.
        const write_pointer = blk: {
            if (publication.geometry) |geometry| {
                if (geometry.write_pointer != 0) break :blk geometry.write_pointer;
            }
            if (publication.last_value) |value| break :blk value;
            ledger.recordBlocked(.no_write_pointer);
            if (ledger.last_blocked_by == .no_write_pointer) machoCapturePrint(
                "macho-processor: SYNTHETIC QUEUE: blocked — {s}\n",
                .{gpu.ring_injection.Blocked.no_write_pointer.label()},
            );
            return;
        };

        const swap = self.gpu_frontbuffer orelse {
            ledger.recordBlocked(.frontbuffer_implausible);
            return;
        };
        if (!swap.plausible()) {
            ledger.recordBlocked(.frontbuffer_implausible);
            return;
        }

        // A coherent fetch constant describing the front buffer the swap
        // names. The command processor only checks the XE_SWAP payload; the
        // fetch dwords carry the surface's format and tiling for presentation,
        // and defaults here are the same ones a packet without a fetch decodes
        // to.
        var fetch = gpu.pm4.FetchConstant{};
        fetch.setBaseAddress(swap.frontbuffer_physical_address);
        fetch.setSize2d(swap.width, swap.height);
        fetch.setTiled(true);

        var packet: [gpu.ring_injection.swap_reservation_dwords]u32 = undefined;
        const used = gpu.pm4.encodeSwapSequence(
            &packet,
            fetch,
            swap,
            gpu.ring_injection.swap_reservation_dwords,
        ) orelse return;
        const dwords = packet[0..used];
        if (self.gpu_ring_watch_size == 0) {
            ledger.recordBlocked(.no_geometry);
            return;
        }
        const ring_dwords: u32 = @intCast(@min(self.gpu_ring_watch_size / 4, std.math.maxInt(u32)));

        // Write every projection the ring is readable through. The emulator
        // may read the ring through any of them and the three aliases can
        // disagree, so a single-address write is how a harness delivers a
        // packet somewhere nobody looks.
        var written_aliases: u32 = 0;
        var first_inject: ?gpu.RingInject = null;
        const aliases = [_]struct { name: []const u8, host: u64 }{
            .{ .name = "physical", .host = self.gpu_ring_watch_host_physical },
            .{ .name = "virtual", .host = self.gpu_ring_watch_host_virtual },
        };
        for (aliases) |alias| {
            if (alias.host == 0) continue;
            const ring = self.guestMemory(alias.host, @as(u64, ring_dwords) * 4) orelse continue;
            const inject = gpu.ring_injection.injectSequence(ring, ring_dwords, write_pointer, dwords) orelse continue;
            written_aliases += 1;
            if (first_inject == null) first_inject = inject;
            machoCapturePrint(
                "  synthetic queue wrote projection={s} host=0x{x} dwords={d} wptr=0x{x}->0x{x} wrap={s}\n",
                .{
                    alias.name,                 alias.host,
                    inject.dwords_written,      inject.write_pointer_before,
                    inject.write_pointer_after, if (inject.wrapped) "YES" else "NO",
                },
            );
        }
        const inject = first_inject orelse {
            ledger.recordBlocked(.not_writable);
            machoCapturePrint(
                "macho-processor: SYNTHETIC QUEUE: blocked — {s}\n",
                .{gpu.ring_injection.Blocked.not_writable.label()},
            );
            return;
        };
        ledger.record(inject, self.executed_steps);
        ledger.channel_open = true;
        machoCapturePrint(
            "macho-processor: SYNTHETIC QUEUE: injected swap packet dwords={d} ring_base=0x{x} wptr=0x{x}->0x{x} wrap={s} aliases={d}/2 frontbuffer=0x{x:0>8} {d}x{d} step={d}; the packet is in ring memory the emulator reads. The write pointer value is what the guest must publish — its register store is memory-mapped and only guest code can execute that store, so until the emulator's ring-change watch acts on this, nothing downstream may count it as an authentic submission\n",
            .{
                inject.dwords_written,
                self.gpu_ring_watch_base,
                inject.write_pointer_before,
                inject.write_pointer_after,
                if (inject.wrapped) "YES" else "NO",
                written_aliases,
                swap.frontbuffer_physical_address,
                swap.width,
                swap.height,
                self.executed_steps,
            },
        );
    }

    /// The contract, printed as a ladder with owners.
    ///
    /// The owner column is the point. A frontier the harness owns is work
    /// Rosette can do today; one the title owns is a question about the title,
    /// and no amount of harness code will move it.
    pub fn logGraphicsContract(self: *MachOState) void {
        self.refreshGraphicsContract();
        const ledger = &self.graphics_contract;
        const frontier = ledger.frontier();
        machoCapturePrint(
            "macho-processor: GRAPHICS CONTRACT: met={d}/{d} frontier={s} owner={s} step={d} harness_refusals={d}; {s}\n",
            .{
                frontier.met_required,
                frontier.required_total,
                if (frontier.clause) |clause| clause.label() else "<complete>",
                if (frontier.clause) |clause| clause.owner().label() else "-",
                self.executed_steps,
                ledger.refused_harness_satisfactions,
                if (frontier.clause) |clause| clause.guidance() else "every required clause is met",
            },
        );
        inline for (@typeInfo(gpu.ContractClause).@"enum".fields) |field| {
            const clause: gpu.ContractClause = @enumFromInt(field.value);
            machoCapturePrint(
                "  clause {s: <8} {s: <12} {s}{s}\n",
                .{
                    ledger.state(clause).label(),
                    clause.owner().label(),
                    clause.label(),
                    if (clause.required()) "" else " (optional)",
                },
            );
        }
        var pending: [gpu.contract.clause_count]gpu.ContractClause = undefined;
        const outstanding = ledger.unmetHarnessClauses(&pending);
        if (outstanding.len == 0) {
            machoCapturePrint(
                "macho-processor: GRAPHICS CONTRACT: no harness clause is outstanding — every precondition Rosette owns has been supplied, so the frontier above is not Rosette's to move\n",
                .{},
            );
            return;
        }
        for (outstanding) |clause| {
            machoCapturePrint(
                "macho-processor: GRAPHICS CONTRACT: harness work outstanding: {s} — {s}\n",
                .{ clause.label(), clause.guidance() },
            );
        }
    }

    /// Why the frame boundary is not being reached, joined from the three
    /// subsystems that each hold one third of the answer.
    ///
    /// Printed with every frontier report because the frontier's own verdict
    /// ("VdSwap never entered") is true for three different causes and names
    /// none of them. Nothing here forces or synthesises a swap: a frame Rosette
    /// manufactures is one the title did not draw, and it would retire the
    /// signal that says the title is stuck.
    pub fn logSwapHealth(self: *MachOState) void {
        const publication = &self.gpu_ring_publication;
        const swap_seen = self.gpu_vd_swap_contract.authentic_consumptions != 0;
        const livelocked = if (comptime @hasField(MachOState, "guest_log_cycles"))
            self.guest_log_cycles.active()
        else
            false;
        const assessment = swap_health.assess(
            publication.writes,
            publication.advances,
            publication.published(),
            publication.stalledSteps(self.executed_steps),
            livelocked,
            swap_seen,
        );
        machoCapturePrint(
            "macho-processor: SWAP HEALTH: blocker={s} producer={s} step={d} wptr(writes/advances/repeats)={d}/{d}/{d} published={s} last_advance_step={d} quiet_for={d} largest_span_dwords={d} consumed_batch(dwords/packets/draws/swaps)={d}/{d}/{d}/{d} consumed_steps={d}/{d} guest_livelocked={s} swap_seen={s}; {s}\n",
            .{
                assessment.blocker.label(),
                @tagName(assessment.producer),
                self.executed_steps,
                publication.writes,
                publication.advances,
                publication.repeats,
                if (assessment.published) "YES" else "NO",
                publication.last_advance_step,
                assessment.stalled_steps orelse 0,
                publication.largest_span_dwords,
                publication.consumed_batch_dwords,
                publication.consumed_batch_packets,
                publication.consumed_batch_draws,
                publication.consumed_batch_swaps,
                publication.first_consumed_step,
                publication.last_consumed_step,
                if (assessment.guest_livelocked) "YES" else "NO",
                if (assessment.swap_seen) "YES" else "NO",
                assessment.blocker.guidance(),
            },
        );
    }

    /// Print the producer-to-present causal trace.  This stays separate from
    /// the graphics contract because the contract is a current frontier while
    /// this ledger retains the bounded history needed to explain a repeated
    /// wait or a state-only PM4 batch.
    pub fn logXeniaGpuCausalTrace(self: *MachOState, force: bool) void {
        self.xenia_gpu_causal_trace.logSummary(self.executed_steps, force);
    }

    /// Join execution-boundary facts into the causal ledger before deciding
    /// whether a graphics checkpoint changed. This keeps tracepoint evidence
    /// visible even when Xenia's own breadcrumb was split across a log write.
    fn refreshXeniaGpuCausalTrace(self: *MachOState) void {
        const at = self.executed_steps;
        if (self.execution_tracepoints.roleEntered(.swap)) {
            self.xenia_gpu_causal_trace.observeStage(.guest_vdswap_entered, at);
        }
        if (self.guest_vdswap_packet_encoded) {
            self.xenia_gpu_causal_trace.observeStage(.swap_packet_encoded, at);
        }
        if (self.guest_vdswap_entry_completed) {
            self.xenia_gpu_causal_trace.observeStage(.guest_vdswap_completed, at);
        }
        if (self.gpu_bootstrap.seen(.pm4_packet_consumed)) {
            self.xenia_gpu_causal_trace.observeEvidence(.pm4_packet_consumed, at);
        }
        if (self.gpu_vd_swap_contract.observed(.authentic_xe_swap_consumed)) {
            self.xenia_gpu_causal_trace.observeEvidence(.authentic_swap_consumed, at);
        }
    }

    /// emitted periodically and again at exit.
    pub fn logGraphicsFrontier(self: *MachOState, force: bool) void {
        self.graphics_summary_emissions +|= 1;
        self.refreshXeniaGpuCausalTrace();
        // Refresh the cross-layer ledgers before deciding whether this
        // checkpoint is interesting.  The controller is deliberately sampled
        // at the same boundary as the reports: this makes its quiet windows
        // and host-only directives correlate with the exact PM4/VdSwap state
        // printed below instead of with a neighboring heartbeat.
        self.refreshGraphicsContract();
        self.refreshGraphicsHealthContract();
        const controller_decision = self.refreshApplicationController();
        self.applyApplicationController(controller_decision);
        self.serviceApplicationFrameworkRequests();
        // Interrupt delivery is a host-owned action and may make a queued
        // completion visible immediately.  Re-join the health ledger so the
        // same report cannot say both "completion dispatched=0" and "drain
        // authorized" after the controller has acted.
        self.refreshGraphicsHealthContract();
        // Publish the same seam through the callable framework. These are
        // deliberately paired observations: entering VdSwap, consuming an
        // authentic XE_SWAP, reaching IssueSwap, and refreshing guest output
        // are separate facts. The equivalence records make a successful call
        // with an absent downstream effect visible as a mismatch.
        self.application_framework.observeController(
            @intFromEnum(controller_decision.phase),
            @intFromEnum(controller_decision.action),
            @intFromEnum(controller_decision.blocker),
            self.executed_steps,
            "controller decision sampled at graphics frontier",
        );
        const guest_vdswap_entered = @intFromBool(self.execution_tracepoints.roleEntered(.swap));
        const authentic_swap_consumed = @intFromBool(self.gpu_vd_swap_contract.authentic_consumptions != 0);
        const issue_swap_entered = @intFromBool(self.gpu_vd_swap_contract.observed(.issue_swap_entered));
        const guest_output_refreshed = @intFromBool(self.dynamic_forwarder.native_presenter.ledger.guest_output_frames_presented != 0);
        self.application_framework.observeValue(.xenia_kernel, .vd_swap, 1, guest_vdswap_entered, self.executed_steps, self.regs.rip, "guest-vdswap-entered", "guest execution boundary");
        self.application_framework.observeValue(.xenia_gpu, .vd_swap, 2, authentic_swap_consumed, self.executed_steps, self.regs.rip, "authentic-xe-swap-consumed", "command processor boundary");
        self.application_framework.observeValue(.xenia_presenter, .presenter, 3, issue_swap_entered, self.executed_steps, self.regs.rip, "issue-swap-entered", "native presenter boundary");
        self.application_framework.observeValue(.xenia_presenter, .presenter, 4, guest_output_refreshed, self.executed_steps, self.regs.rip, "guest-output-refreshed", "guest-produced frame evidence");
        if (self.application_framework.isEnabled()) {
            _ = self.application_framework.compareValue(.xenia_gpu, .vd_swap, 2, guest_vdswap_entered, authentic_swap_consumed, 1, self.executed_steps, self.regs.rip, "vdswap-to-authentic-xe-swap");
            _ = self.application_framework.compareValue(.xenia_presenter, .presenter, 3, authentic_swap_consumed, issue_swap_entered, 1, self.executed_steps, self.regs.rip, "xe-swap-to-issue-swap");
            _ = self.application_framework.compareValue(.rosette, .presenter, 4, issue_swap_entered, guest_output_refreshed, 1, self.executed_steps, self.regs.rip, "issue-swap-to-guest-output");
        }
        const health_fingerprint = self.graphics_health.fingerprint();
        const controller_fingerprint = controller_decision.fingerprint();
        const framework_sequence = self.application_framework.currentSequence();
        const tracepoints = &self.execution_tracepoints;
        const frontier = self.gpu_bootstrap.frontier();
        const frontier_tag = if (frontier.step) |frontier_step|
            @intFromEnum(frontier_step)
        else
            std.math.maxInt(u8);
        var role_mask: u8 = 0;
        inline for (@typeInfo(execution_tracepoints.Role).@"enum".fields) |field| {
            const role: execution_tracepoints.Role = @enumFromInt(field.value);
            if (tracepoints.roleEntered(role)) {
                role_mask |= @as(u8, 1) << @intCast(field.value);
            }
        }
        const ring_published = self.gpu_ring_publication.published();
        const causal_changed =
            self.xenia_gpu_causal_trace.total_events != self.graphics_last_causal_events or
            self.xenia_gpu_causal_trace.observed_mask != self.graphics_last_causal_mask;
        const state_changed =
            frontier_tag != self.graphics_last_frontier_tag or
            frontier.reached != self.graphics_last_frontier_reached or
            role_mask != self.graphics_last_role_mask or
            ring_published != self.graphics_last_ring_published or
            self.anomalies.count != self.graphics_last_anomaly_count or
            causal_changed or
            health_fingerprint != self.graphics_health_last_fingerprint or
            controller_fingerprint != self.application_controller_last_fingerprint or
            framework_sequence != self.application_framework_last_sequence;
        self.graphics_last_frontier_tag = frontier_tag;
        self.graphics_last_frontier_reached = frontier.reached;
        self.graphics_last_role_mask = role_mask;
        self.graphics_last_ring_published = ring_published;
        self.graphics_last_anomaly_count = self.anomalies.count;
        self.graphics_last_causal_events = self.xenia_gpu_causal_trace.total_events;
        self.graphics_last_causal_mask = self.xenia_gpu_causal_trace.observed_mask;
        self.graphics_health_last_fingerprint = health_fingerprint;
        self.application_controller_last_fingerprint = controller_fingerprint;
        self.application_framework_last_sequence = framework_sequence;
        if (force or state_changed) self.logApplicationFramework();

        // The ring is read whether or not the frontier moved.
        //
        // Everything else in this report is derived from state that only
        // changes when the frontier does, so gating it on a transition costs
        // nothing. The ring is the opposite: it is memory the guest writes at
        // its own pace, and a run whose frontier has stopped moving is exactly
        // the run where its contents are the only thing left that can change.
        // The observed stall took its last transition at step 3.5B and then ran
        // for another 2.8B steps; gated on transitions, nothing would have
        // looked at the ring across the whole second half of the run and the
        // front buffer a swap names would never have been found.
        //
        // Rate-limited rather than free-running: the scan walks the ring, and a
        // diagnostic that runs on every checkpoint becomes the dominant cost
        // and the dominant source of log traffic at the same time.
        if (force or state_changed or self.graphics_summary_emissions % 16 == 0) {
            self.logRingContents();
            // The preinitialization ledger reads kernel-variable state. Refresh
            // that state before sampling the ledger so this report cannot lag
            // behind the variable report emitted later in the full summary.
            // Provisioning remains owner-gated: title-owned pointers are never
            // fabricated, and structured HSIO state is not synthesized here.
            self.refreshKernelVariables();
            self.logProvisioningCustody();
            self.logPreinitialization();
            self.logGuestWaitLiveness();
            self.logImportBinding();
            self.logHostCoverage();
            self.logBringupFailures();
            self.logStallRelease();
            // Drive a refresh because the emulator will not: it refreshes on a
            // swap, and this title has never swapped. The frame source is
            // unchanged, so this cannot invent a picture — it only ensures the
            // scan runs, which is the difference between "we tried and the
            // guest had nothing" and "nobody ever looked".
            // The controller owns the discovered-guest-output refresh when it
            // has proven that a guest source exists.  Keep the historical
            // diagnostic cadence for all other states, including a completely
            // empty source, so "no source" remains an observed result rather
            // than an unattempted path.
            if (controller_decision.action != .refresh_discovered_output)
                _ = self.dynamic_forwarder.attemptScheduledRefresh(self);
            self.dynamic_forwarder.logScheduledRefresh();
            self.logWaitAudit();
            self.logDeadlockPredictor();
            self.logDeferredWork();
            self.logGuestExceptions();
            self.logSwapSubstitution();
            self.refreshGraphicsHealthContract();
            self.logGraphicsHealthContract();
            self.logApplicationController(controller_decision);
        }

        // Heartbeats already say that execution is alive. The complete report
        // includes every tracepoint and the full thread census, so emit it only
        // on an actual state transition or at shutdown. A compact unchanged
        // checkpoint every 64 calls preserves liveness without making the
        // observer itself the dominant source of log traffic.
        if (!force and !state_changed) {
            if (self.graphics_summary_emissions % 64 != 0) return;
            machoCapturePrint(
                "macho-processor: GRAPHICS FRONTIER unchanged: run=0x{x} step={d} checkpoint={d} bootstrap={d}/{d} frontier={s} guest_vdswap_call_seen={s} guest_vdswap_entry_completed={s} guest_swap_command_buffer_write_seen={s} guest_swap_publication_proven={s} guest_pm4_xe_swap_seen={s} cp_xe_swap_decode_seen={s} host_issue_swap_seen={s} diagnostic_injection_seen={s} presenter_refresh_seen={s} ring_published={s}\n",
                .{
                    self.event_stream.run_id,
                    self.executed_steps,
                    self.graphics_summary_emissions,
                    frontier.reached,
                    gpu.bootstrap.required_step_count,
                    if (frontier.step) |pending| pending.label() else "<complete>",
                    if (tracepoints.roleEntered(.swap)) "YES" else "NO",
                    if (self.guest_vdswap_entry_completed) "YES" else "NO",
                    if (self.guest_vdswap_packet_encoded) "YES" else "NO",
                    if (self.gpu_vd_swap_contract.observed(.ring_write_pointer_published)) "YES" else "NO",
                    if (self.gpu_vd_swap_contract.observed(.authentic_xe_swap_consumed)) "YES" else "NO",
                    if (tracepoints.roleEntered(.xe_swap_decode)) "YES" else "NO",
                    if (tracepoints.roleEntered(.command_swap)) "YES" else "NO",
                    if (tracepoints.roleEntered(.diagnostic_swap)) "YES" else "NO",
                    if (tracepoints.roleEntered(.presenter)) "YES" else "NO",
                    if (ring_published) "YES" else "NO",
                },
            );
            self.logSwapHealth();
            self.logXeniaGpuCausalTrace(false);
            self.logVdSwapContract();
            self.logVdSwapTrace();
            self.refreshGraphicsHealthContract();
            self.logGraphicsHealthContract();
            self.logApplicationController(controller_decision);
            return;
        }
        machoCapturePrint(
            "macho-processor: GRAPHICS FRONTIER #{d}: run=0x{x} step={d} events={d} guest_vdswap_call={s}\n",
            .{
                self.graphics_summary_emissions,
                self.event_stream.run_id,
                self.executed_steps,
                self.event_stream.sequence,
                tracepoints.verdict(.swap),
            },
        );
        self.logRunHorizon();
        self.logSwapHealth();
        self.logXeniaGpuCausalTrace(force);
        self.logGraphicsContract();
        self.refreshGraphicsHealthContract();
        self.logGraphicsHealthContract();
        self.logApplicationController(controller_decision);
        self.logVdSwapContract();
        self.logVdSwapTrace();
        self.logKernelSurface();
        self.logKernelVariables();
        for (tracepoints.entries[0..tracepoints.count]) |entry| {
            machoCapturePrint(
                "  tracepoint role={s} hits={d} first_step={d} first_thread=0x{x} first_caller=0x{x} last_step={d} address=0x{x} symbol={s}\n",
                .{ @tagName(entry.role), entry.hits, entry.first_step, entry.first_thread, entry.first_caller, entry.last_step, entry.address, entry.name },
            );
        }
        inline for (@typeInfo(execution_tracepoints.Role).@"enum".fields) |field| {
            const role: execution_tracepoints.Role = @enumFromInt(field.value);
            if (tracepoints.roleArmed(role) or role == .swap) {
                machoCapturePrint(
                    "  role={s}: {s}\n",
                    .{ @tagName(role), tracepoints.verdict(role) },
                );
            }
        }
        self.logRegisterApertureTraffic();
        const publication = &self.gpu_ring_publication;
        machoCapturePrint(
            "  ring writes={d} advances={d} repeats={d} span={s} published={s}; {s}\n",
            .{
                publication.writes,
                publication.advances,
                publication.repeats,
                @tagName(publication.span()),
                if (publication.published()) "YES" else "NO",
                publication.verdict(),
            },
        );
        machoCapturePrint(
            "  bootstrap reached={d}/{d} frontier={s} precondition_met={} blocked_by={s}\n",
            .{
                frontier.reached,
                gpu.bootstrap.required_step_count,
                if (frontier.step) |pending| pending.label() else "<complete>",
                frontier.precondition_met,
                if (frontier.blocked_by) |blocked| blocked.label() else "none",
            },
        );
        self.dynamic_forwarder.logGraphicsProvenance();
        self.dynamic_forwarder.logGuestFrontBuffer();
        self.dynamic_forwarder.logVulkanTiers();
        // A blocked count is an aggregate; the frontier needs to know which
        // resource the producer is parked on and for how long.
        self.pthreads.logThreadCensus(self.executed_steps, self.active_guest_thread);
        self.logNotifierLiveness();
        self.logAnomalyLedger();
        if (self.event_stream.anySuppressed()) {
            machoCapturePrint(
                "  NOTE: some event kinds hit their budget and were suppressed; a flat count is a budget, not a cessation\n",
                .{},
            );
        }
    }

    pub fn standardStreamPointer(self: *MachOState, symbol_name: []const u8) ?u64 {
        return guest_log.standardStreamPointer(self, symbol_name);
    }

    pub fn configureGuestLogMirror(self: *MachOState, args: []const []const u8) void {
        return guest_log.configureGuestLogMirror(self, args);
    }

    pub fn hostWriteFdAll(fd: i32, bytes: []const u8) bool {
        return guest_log.hostWriteFdAll(fd, bytes);
    }

    pub fn shouldSummarizeGuestLog(level: u8, message: []const u8) bool {
        return guest_log.shouldSummarizeGuestLog(level, message);
    }

    pub fn shouldSuppressRuntimeGuestLog(message: []const u8) bool {
        return guest_log.shouldSuppressRuntimeGuestLog(message);
    }

    pub fn emitRuntimeSummaryHeartbeat(self: *const MachOState, snapshot: startup_observer.Snapshot) void {
        return guest_log.emitRuntimeSummaryHeartbeat(self, snapshot);
    }

    pub fn emitGuestLog(self: *MachOState, prefix_char_raw: u64, address: u64, length_raw: u64) bool {
        return guest_log.emitGuestLog(self, prefix_char_raw, address, length_raw);
    }

    pub fn logProfileHostPreflight(self: *MachOState, profile_id: []const u8) void {
        return guest_log.logProfileHostPreflight(self, profile_id);
    }

    pub fn observeProfileAccountFlow(self: *MachOState) void {
        return guest_log.observeProfileAccountFlow(self);
    }

    pub fn noteProfileAccountOpen(self: *MachOState, path: []const u8, guest_fd: u64) void {
        return guest_log.noteProfileAccountOpen(self, path, guest_fd);
    }

    pub fn noteProfileAccountRead(self: *MachOState, guest_fd: u64, requested: u64, result: i64, offset: u64) void {
        return guest_log.noteProfileAccountRead(self, guest_fd, requested, result, offset);
    }

    pub fn observeBackendGuestLog(self: *MachOState, message: []const u8) void {
        return guest_log.observeBackendGuestLog(self, message);
    }

    pub fn backendMemoryDiagnosticsActive(self: *const MachOState) bool {
        return guest_log.backendMemoryDiagnosticsActive(self);
    }

    pub fn noteBackendMmapAttempt(self: *MachOState, route: []const u8, address: u64, length: u64, prot: u64, flags: u64, fixed: bool, anonymous: bool) void {
        return guest_log.noteBackendMmapAttempt(self, route, address, length, prot, flags, fixed, anonymous);
    }

    pub fn noteBackendMmapResult(self: *MachOState, succeeded: bool, result: u64, stage: []const u8) void {
        return guest_log.noteBackendMmapResult(self, succeeded, result, stage);
    }

    pub fn observeXeniaFixedMemoryView(self: *MachOState, address: u64, length: u64, offset: u64, anonymous: bool) void {
        const discovery = self.xenia_memory_views.observeFixedFileView(address, length, offset, anonymous);
        switch (discovery) {
            .ignored, .confirmed => {},
            .discovered => machoCapturePrint(
                "macho-processor: Xenia memory-view model discovered: mapping_base=0x{x} source=fixed_file_view length=0x{x}; Xbox virtual and physical log addresses can now be resolved to translated host aliases\n",
                .{ address, length },
            ),
            .conflicting => machoCapturePrint(
                "macho-processor: Xenia memory-view model CONFLICT: retained_base=0x{x} observed_base=0x{x}; translated provenance is disabled rather than attributing writes to the wrong process view\n",
                .{ self.xenia_memory_views.mapping_base, address },
            ),
        }
    }

    pub fn noteBackendMprotect(self: *MachOState, route: []const u8, address: u64, length: u64, prot: u64, succeeded: bool) void {
        return guest_log.noteBackendMprotect(self, route, address, length, prot, succeeded);
    }

    pub fn allocGuestFile(self: *MachOState, fd: i32, kind: GuestFileKind) ?u64 {
        for (&self.guest_files, 0..) |*file, idx| {
            if (!file.active) {
                file.* = .{
                    .active = true,
                    .fd = fd,
                    .position = 0,
                    .error_flag = false,
                    .kind = kind,
                };
                return GUEST_FILE_BASE + idx;
            }
        }
        return null;
    }

    pub fn guestFileFromHandle(self: *MachOState, handle: u64) ?*GuestFile {
        if (handle < GUEST_FILE_BASE) return null;
        const idx_u64 = handle - GUEST_FILE_BASE;
        if (idx_u64 >= GUEST_FILE_MAX) return null;
        const idx: usize = @intCast(idx_u64);
        const file = &self.guest_files[idx];
        if (!file.active) return null;
        return file;
    }

    fn closeGuestFiles(self: *MachOState) void {
        for (&self.guest_files) |*file| {
            if (!file.active) continue;
            if (file.descriptor_alias != std.math.maxInt(u64)) {
                const alias_is_primary = file.descriptor_alias_is_primary;
                _ = self.fs_forwarder.fd_manager.closeGeneration(
                    file.descriptor_alias,
                    file.descriptor_generation,
                );
                if (alias_is_primary) file.fd = -1;
            }
            if (file.kind == .regular and file.fd >= 0) {
                _ = std.c.close(file.fd);
            }
            file.* = .{};
        }
    }

    fn fileOffsetForVaddr(self: *const MachOState, vaddr: u64) ?u64 {
        for (self.segments) |seg| {
            if (vaddr < seg.vmaddr) continue;
            const delta = vaddr - seg.vmaddr;
            if (delta < seg.filesize) {
                return seg.fileoff + delta;
            }
        }
        return null;
    }

    /// F13 (throughput audit): `inline` so the gate is a compare at the call
    /// site. This is reached on every taken conditional jump and every call,
    /// and each of the 12 call sites in `execute` had to materialise a string
    /// constant and set up a six-argument call frame before the function could
    /// decide it had nothing to do.
    pub inline fn logControlFlow(self: *const MachOState, kind: []const u8, from_rip: u64, to_rip: u64, decoded_len: u64, return_addr: ?u64) void {
        if (!self.verbose_trace) return;
        if (return_addr) |ret_addr| {
            log.info("cf({s}): rip=0x{x} -> 0x{x} len={d} ret=0x{x} rsp=0x{x}", .{ kind, from_rip, to_rip, decoded_len, ret_addr, self.regs.rsp });
        } else {
            log.info("cf({s}): rip=0x{x} -> 0x{x} len={d} rsp=0x{x}", .{ kind, from_rip, to_rip, decoded_len, self.regs.rsp });
        }
    }

    fn inHelperCluster(self: *const MachOState, rip: u64) bool {
        if (self.helper_cluster_start) |start| {
            const end = self.helper_cluster_end orelse start;
            return rip >= start and rip < end;
        }
        return false;
    }

    fn findSharedHelperCluster(self: *const MachOState, helper_rip: u64) ?struct { start: u64, end: u64 } {
        const helper_bytes = self.guestMemoryConst(helper_rip, 16) orelse return null;
        if (helper_bytes.len < 16) return null;
        var scan = helper_rip;
        var found_start: ?u64 = null;
        var count: usize = 0;
        while (count < 4096) : (count += 1) {
            if (scan < lazy_import_stub.entry_size) break;
            scan -= lazy_import_stub.entry_size;
            const bytes = self.guestMemoryConst(scan, lazy_import_stub.entry_size) orelse break;
            if (lazy_import_stub.decodeEntry(scan, bytes)) |stub| {
                if (stub.shared_helper == helper_rip) {
                    found_start = scan;
                    continue;
                }
            }
            break;
        }
        const start = found_start orelse return null;
        var end = start;
        count = 0;
        while (count < 4096) : (count += 1) {
            const bytes = self.guestMemoryConst(end, lazy_import_stub.entry_size) orelse break;
            if (lazy_import_stub.decodeEntry(end, bytes)) |stub| {
                if (stub.shared_helper == helper_rip) {
                    end += lazy_import_stub.entry_size;
                    continue;
                }
            }
            break;
        }
        return .{ .start = start, .end = end };
    }

    pub fn dumpGuestStack(self: *const MachOState) void {
        const count: usize = 12;
        machoCapturePrint("    [stack backtrace (rsp=0x{x}):\n", .{self.regs.rsp});
        var addr = self.regs.rsp;
        for (0..count) |i| {
            const val = self.read64(addr);
            if (val == 0) {
                machoCapturePrint("      [{d}] 0x{x}: 0x0\n", .{ i, addr });
            } else if (self.metadata.nearestSymbol(val)) |sym| {
                machoCapturePrint("      [{d}] 0x{x}: 0x{x} → {s}+0x{x}\n", .{ i, addr, val, sym.name, sym.offset });
            } else {
                machoCapturePrint("      [{d}] 0x{x}: 0x{x}\n", .{ i, addr, val });
            }
            addr +%= 8;
        }
    }

    noinline fn handleStubHelperTransition(self: *MachOState) bool {
        // Lazy helper decoding used to touch guest memory for every interpreted
        // instruction. All classic helper entries live in __stub_helper, so the
        // overwhelmingly common path can reject them without translation or
        // byte decoding.
        if (self.regs.rip < self.stub_helper_start or self.regs.rip >= self.stub_helper_end) {
            return false;
        }
        const entry_bytes = self.guestMemoryConst(self.regs.rip, lazy_import_stub.entry_size);
        if (if (entry_bytes) |bytes| lazy_import_stub.decodeEntry(self.regs.rip, bytes) else null) |stub| {
            self.pending_stub_slot = stub.bind_slot;
            self.pending_stub_entry_rip = self.regs.rip;
            if (self.verbose_trace) log.info("stub-entry: rip=0x{x} slot=0x{x} shared_helper=0x{x}", .{ self.regs.rip, stub.bind_slot, stub.shared_helper });
            self.regs.rip = stub.shared_helper;
            return true;
        }

        const helper_bytes = self.guestMemoryConst(self.regs.rip, 16);
        if (self.pending_stub_slot != null and (if (helper_bytes) |bytes| lazy_import_stub.isSharedHelper(bytes) else false)) {
            const slot = self.pending_stub_slot.?;
            const entry_rip = self.pending_stub_entry_rip orelse self.regs.rip;
            const synthetic_return = self.read64(self.regs.rsp);
            if (self.findSharedHelperCluster(self.regs.rip)) |cluster| {
                self.helper_cluster_start = cluster.start;
                self.helper_cluster_end = cluster.end;
                if (self.verbose_trace) log.info("stub-helper cluster: helper_rip=0x{x} cluster=[0x{x}, 0x{x})", .{ self.regs.rip, cluster.start, cluster.end });
            }
            self.pending_stub_slot = null;
            self.pending_stub_entry_rip = null;
            if (self.pending_import_stub_rip) |import_stub_rip| {
                if (self.metadata.importAtStub(import_stub_rip)) |imported| {
                    switch (self.handleImport(imported)) {
                        .handled => |result| {
                            self.regs.rax = result;
                            if (self.verbose_trace) {
                                machoCapturePrint("  [handled import] {s} from {s}; stub=0x{x} return=0x{x} → rax=0x{x}\n", .{
                                    imported.name,
                                    imported.dylib,
                                    imported.stub_address,
                                    synthetic_return,
                                    result,
                                });
                            }
                        },
                        .handled_void => {
                            if (self.verbose_trace) {
                                machoCapturePrint(
                                    "  [handled void import] {s} from {s}; stub=0x{x} return=0x{x}\n",
                                    .{ imported.name, imported.dylib, imported.stub_address, synthetic_return },
                                );
                            }
                        },
                        .control_transferred => {
                            self.pending_import_stub_rip = null;
                            if (self.verbose_trace) {
                                machoCapturePrint(
                                    "  [handled control transfer] {s} from {s}; landing_pad=0x{x}\n",
                                    .{ imported.name, imported.dylib, self.regs.rip },
                                );
                            }
                            return true;
                        },
                        .unsupported => |result| {
                            self.regs.rax = result;
                            self.recordUnresolvedImport(imported, synthetic_return, self.regs.rax);
                            if (self.metadata.nearestSymbol(synthetic_return)) |caller_sym| {
                                machoCapturePrint(
                                    "  [unresolved import #{d}] {s} from {s}; stub=0x{x} caller={s}+0x{x} return=0x{x} → rax=0x{x}\n",
                                    .{ self.unresolved_import_count, imported.name, imported.dylib, imported.stub_address, caller_sym.name, caller_sym.offset, synthetic_return, self.regs.rax },
                                );
                            } else {
                                machoCapturePrint(
                                    "  [unresolved import #{d}] {s} from {s}; stub=0x{x} caller=0x{x} → rax=0x{x}\n",
                                    .{ self.unresolved_import_count, imported.name, imported.dylib, imported.stub_address, synthetic_return, self.regs.rax },
                                );
                            }
                            self.dumpGuestStack();
                            if (self.strict_imports) self.terminateForUnresolvedImport();
                        },
                        .terminated => |exit_code| {
                            self.exit_code = exit_code;
                            if (exit_diagnostics.reasonFromValue(self.termination_reason) == .unknown) {
                                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
                            }
                            self.terminated = true;
                            machoCapturePrint("  [terminal import] {s} exit_code={d}\n", .{ imported.name, exit_code });
                        },
                    }
                }
            }
            self.pending_import_stub_rip = null;
            if (self.terminated) return true;
            if (synthetic_return != 0 and self.addrToOffset(synthetic_return) != null) {
                if (self.verbose_trace) log.warn("stub-helper aggressive fallback: helper_rip=0x{x} slot=0x{x} entry_rip=0x{x} synthetic_return=0x{x}; simulating resolved helper return", .{ self.regs.rip, slot, entry_rip, synthetic_return });
                _ = self.pop();
                self.regs.rip = synthetic_return;
            } else {
                log.warn("stub-helper conservative fallback: helper_rip=0x{x} slot=0x{x} entry_rip=0x{x}; synthetic_return invalid (0x{x}), skipping helper entry", .{ self.regs.rip, slot, entry_rip, synthetic_return });
                self.regs.rip = entry_rip + lazy_import_stub.entry_size;
            }
            return true;
        }

        if (self.inHelperCluster(self.regs.rip)) {
            const cluster_end = self.helper_cluster_end orelse self.regs.rip;
            log.warn("helper-cluster escape: rip=0x{x} cluster_end=0x{x}; forcing exit from packed stub region", .{ self.regs.rip, cluster_end });
            self.regs.rax = 0;
            self.regs.rip = cluster_end;
            self.helper_cluster_start = null;
            self.helper_cluster_end = null;
            return true;
        }

        return false;
    }

    /// Whether the primitive registry matches this import name. Distinct from
    /// `tryPrimitiveDispatch`: this only asks whether a handler exists, so the
    /// unresolved-import report can distinguish "no handler for this symbol"
    /// from "handler matched but declined this input".
    pub fn primitiveMatches(self: *MachOState, name: []const u8) bool {
        _ = self;
        return primitive.builtin().matchSymbol(name) != null;
    }

    pub fn handleImport(self: *MachOState, imported: macho_metadata.ImportedSymbol) ImportHandlerResult {
        const name = imported.name;
        const return_address = self.read64(self.regs.rsp);
        const caller = if (self.metadata.nearestSymbol(return_address)) |symbol| symbol.name else "<unknown>";
        const active_initializer = self.initializer_resolver.current();
        const phase: import_resolution.Phase = if (active_initializer != null) .initializer else .execution;
        const owner = if (active_initializer) |initializer| initializer.symbol else "<main>";
        self.import_provider_override = null;
        self.import_confidence_override = null;
        const result = self.handleImportImpl(imported);

        const exact_contract = import_resolution.contractFor(name);
        const declared_contract = contract.resolveFromAllFamilies(name);
        const outcome: import_resolution.Outcome = switch (result) {
            .handled, .handled_void, .control_transferred => .resolved,
            .unsupported => .unresolved,
            .terminated => .terminated,
        };
        const inferred_provider: import_resolution.Provider = if (exact_contract != null)
            .contract
        else switch (result) {
            .unsupported => .none,
            else => if (declared_contract) |declared|
                switch (declared.strategy) {
                    .stub, .synthesize, .terminate => .contract,
                    else => .legacy_shim,
                }
            else
                .legacy_shim,
        };
        const inferred_confidence: import_resolution.Confidence = if (exact_contract != null)
            .verified
        else if (outcome == .unresolved)
            .unknown
        else
            .modeled;
        const provider = self.import_provider_override orelse inferred_provider;
        const confidence = self.import_confidence_override orelse inferred_confidence;
        self.import_resolver.record(name, caller, owner, phase, outcome, provider, confidence);
        return result;
    }

    /// Call a translated guest function synchronously from a runtime bridge.
    ///
    /// The direct PPC adapter uses this for Xenia's CR, syscall, call
    /// resolution and trap callbacks. Those callbacks are guest x86 code even
    /// though the PPC interpreter is native ARM64, so invoking the host
    /// pointer would cross both an ABI and an address-space boundary. A
    /// distinctive guest return sentinel lets the normal `step` path service
    /// imports and synthetic thunks inside the callback while preserving the
    /// caller's full register file afterwards.
    pub fn callGuestFunction(self: *MachOState, fn_address: u64, args: [6]u64) u64 {
        const saved_regs = self.regs;
        const sentinel: u64 = 0xCA11_CA11_CA11_CA11;
        var result: u64 = 0;

        self.regs.rdi = args[0];
        self.regs.rsi = args[1];
        self.regs.rdx = args[2];
        self.regs.rcx = args[3];
        self.regs.r8 = args[4];
        self.regs.r9 = args[5];
        self.regs.rsp -%= 8;
        if (self.guestMemory(self.regs.rsp, 8)) |destination| {
            std.mem.writeInt(u64, destination[0..8], sentinel, .little);
            self.regs.rip = fn_address;

            var iterations: u32 = 0;
            while (iterations < 100_000 and !self.terminated and !self.faulted) : (iterations += 1) {
                if (self.regs.rip == sentinel) break;
                if (!self.step()) break;
            }
            result = self.regs.rax;
        }
        self.regs = saved_regs;
        return result;
    }

    pub fn tryPrimitiveDispatch(self: *MachOState, imported: macho_metadata.ImportedSymbol) ?ImportHandlerResult {
        const dispatch_cb = import_handler.PrimitiveDispatchCallbacks{
            .ctx = self,
            .matchSymbol = struct {
                fn match(_: *anyopaque, name: []const u8) ?*const anyopaque {
                    // Use primitive.builtin().matchSymbol — doesn't need MachOState
                    const h = primitive.builtin().matchSymbol(name);
                    return if (h) |handler| @ptrCast(handler) else null;
                }
            }.match,
            .callHandler = struct {
                fn call(ctx: *anyopaque, slot: u32, handler_ptr: *const anyopaque) u8 {
                    const typed_handler: primitive.types.Handler = @ptrCast(@alignCast(handler_ptr));
                    var prim_ctx = primitive.types.PrimitiveContext{
                        .ptr = ctx,
                        .readArgFn = struct {
                            fn read(ptr: *anyopaque, index: u8) u64 {
                                const inner_st: *MachOState = @ptrCast(@alignCast(ptr));
                                return switch (index) {
                                    0 => inner_st.regs.rdi,
                                    1 => inner_st.regs.rsi,
                                    2 => inner_st.regs.rdx,
                                    3 => inner_st.regs.rcx,
                                    4 => inner_st.regs.r8,
                                    5 => inner_st.regs.r9,
                                    else => 0,
                                };
                            }
                        }.read,
                        .setResultFn = struct {
                            fn set(ptr: *anyopaque, value: u64) void {
                                const inner_st: *MachOState = @ptrCast(@alignCast(ptr));
                                inner_st.regs.rax = value;
                            }
                        }.set,
                        .readGuestFn = struct {
                            fn read(ptr: *const anyopaque, address: u64, size: usize) ?[]const u8 {
                                const inner_st: *const MachOState = @ptrCast(@alignCast(ptr));
                                return inner_st.guestMemoryConst(address, @intCast(size));
                            }
                        }.read,
                        .writeGuestFn = struct {
                            fn write(ptr: *anyopaque, address: u64, data: []const u8) ?void {
                                const inner_st: *MachOState = @ptrCast(@alignCast(ptr));
                                return if (inner_st.writeGuestBytes(address, data)) {} else null;
                            }
                        }.write,
                        .readCStringFn = struct {
                            fn read(ptr: *const anyopaque, address: u64) ?[]const u8 {
                                const inner_st: *const MachOState = @ptrCast(@alignCast(ptr));
                                // Match the slow-path import handlers (strlen,
                                // strcmp, strcpy use a 1 MiB cap) so the
                                // primitive layer services the same inputs the
                                // slow path would instead of falling through
                                // to it with a shorter 4096-byte window.
                                return inner_st.guestCString(address, 1 << 20);
                            }
                        }.read,
                        .moveGuestFn = struct {
                            fn move(ptr: *anyopaque, destination_address: u64, source_address: u64, count: usize) bool {
                                const inner_st: *MachOState = @ptrCast(@alignCast(ptr));
                                if (count == 0 or destination_address == source_address) return true;
                                const count_u64: u64 = @intCast(count);
                                const source = inner_st.guestMemoryConst(source_address, count_u64) orelse return false;
                                const destination = inner_st.guestMemory(destination_address, count_u64) orelse return false;
                                const mutation = inner_st.captureMemoryMutation(destination_address, count_u64);
                                if (destination_address > source_address and destination_address - source_address < count_u64) {
                                    std.mem.copyBackwards(u8, destination, source);
                                } else {
                                    std.mem.copyForwards(u8, destination, source);
                                }
                                inner_st.commitMemoryMutation(mutation, .bulk_copy);
                                return true;
                            }
                        }.move,
                        .callGuestFn = struct {
                            fn call(ptr: *anyopaque, fn_address: u64, args: [6]u64) u64 {
                                const st: *MachOState = @ptrCast(@alignCast(ptr));

                                // Save the complete register state for restoration after the call.
                                const saved_regs = st.regs;

                                // Set up System V AMD64 ABI arguments for the guest function.
                                st.regs.rdi = args[0];
                                st.regs.rsi = args[1];
                                st.regs.rdx = args[2];
                                st.regs.rcx = args[3];
                                st.regs.r8 = args[4];
                                st.regs.r9 = args[5];

                                // Push a distinctive sentinel return address onto the guest
                                // stack so we can detect when the callee returns.
                                const sentinel: u64 = 0xCA11CA11CA11CA11;
                                st.regs.rsp -%= 8;
                                if (st.guestMemory(st.regs.rsp, 8)) |dest| {
                                    std.mem.writeInt(u64, dest[0..8], sentinel, .little);
                                }

                                st.regs.rip = fn_address;

                                // Inline decode + execute loop.  We avoid calling
                                // self.step() because that would re-enter import
                                // dispatch and sentinel checks.  Instead we manually
                                // decode and execute each instruction until the
                                // callee rets back to our sentinel.
                                const max_iters: u32 = 200;
                                var iter: u32 = 0;
                                while (iter < max_iters) : (iter += 1) {
                                    if (st.terminated or st.faulted) break;

                                    // No gate chain ran before this decode (this
                                    // loop deliberately skips it), so the fill must
                                    // not mark the entry fast_plain.
                                    const d = st.decodeWithLiveOperands(false) orelse break;
                                    if (d.op == .invalid) break;

                                    if (d.op == .ret) {
                                        // Pop return address from guest stack.
                                        if (st.guestMemory(st.regs.rsp, 8)) |src| {
                                            st.regs.rip = std.mem.readInt(u64, src[0..8], .little);
                                            st.regs.rsp +%= 8;
                                        }
                                        if (st.regs.rip == sentinel) break;
                                        continue;
                                    }

                                    const old_rip = st.regs.rip;
                                    st.execute(d);
                                    if (!st.terminated and st.regs.rip == old_rip) {
                                        st.regs.rip +%= d.len;
                                    }
                                }

                                const result = st.regs.rax;
                                st.regs = saved_regs;
                                return result;
                            }
                        }.call,
                        .raiseSignalFn = struct {
                            fn raise(ptr: *anyopaque, signal: u8) primitive.types.RaiseResult {
                                const st: *MachOState = @ptrCast(@alignCast(ptr));
                                if (signal == 0 or signal >= st.signal_actions.len) return .failed;

                                const action = st.signal_actions[signal];
                                if (action.handler == 1) return .delivered; // SIG_IGN
                                if (action.handler > 1) {
                                    const return_address = st.read64(st.regs.rsp);
                                    if (signal_handling.deliverRaisedGuestSignal(st, signal, return_address)) return .delivered;
                                }

                                // The default action, or an invalid installed
                                // handler that could not be entered, terminates
                                // the guest only. Never call the host raise API.
                                st.exit_code = 128 + signal;
                                st.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unhandled_guest_signal);
                                st.terminated = true;
                                machoCapturePrint(
                                    "macho-processor: guest raise({d}) applied default termination action; Rosette kept the host process alive\n",
                                    .{signal},
                                );
                                return .terminated;
                            }
                        }.raise,
                        .pthreadMachThreadIdFn = struct {
                            fn lookup(ptr: *anyopaque, handle: u64) u64 {
                                const inner_st: *MachOState = @ptrCast(@alignCast(ptr));
                                return inner_st.pthreads.numericThreadId(handle);
                            }
                        }.lookup,
                        .dladdrResolveFn = struct {
                            fn resolve(ptr: *anyopaque, address: u64) primitive.types.DladdrInfo {
                                const inner_st: *MachOState = @ptrCast(@alignCast(ptr));
                                const match = inner_st.metadata.nearestSymbol(address) orelse return .{};
                                const file_offset = @as(u64, @intFromPtr(match.name.ptr)) - @as(u64, @intFromPtr(inner_st.data.ptr));
                                var name_vaddr: u64 = 0;
                                for (inner_st.segments) |seg| {
                                    if (file_offset >= seg.fileoff and file_offset < seg.fileoff + seg.filesize) {
                                        name_vaddr = seg.vmaddr + (file_offset - seg.fileoff);
                                        break;
                                    }
                                }
                                return .{
                                    .found = true,
                                    .dli_fbase = inner_st.mem_base,
                                    .dli_sname = name_vaddr,
                                    .dli_saddr = match.address,
                                };
                            }
                        }.resolve,
                    };
                    const result = typed_handler(slot, &prim_ctx);
                    return @intFromEnum(result);
                }
            }.call,
            .readRegister = struct {
                fn read(ptr: *anyopaque, index: u8) u64 {
                    const st: *MachOState = @ptrCast(@alignCast(ptr));
                    return switch (index) {
                        0 => st.regs.rdi,
                        1 => st.regs.rsi,
                        2 => st.regs.rdx,
                        3 => st.regs.rcx,
                        4 => st.regs.r8,
                        5 => st.regs.r9,
                        else => 0,
                    };
                }
            }.read,
            .readResult = struct {
                fn read(ptr: *const anyopaque) u64 {
                    const st: *const MachOState = @ptrCast(@alignCast(ptr));
                    return st.regs.rax;
                }
            }.read,
        };
        const log_cb = import_handler.PrimitiveLogCallbacks{
            .ctx = self,
            .logLine = struct {
                fn log(_: *anyopaque, text: []const u8) void {
                    primitiveCapturePrint("{s}", .{text});
                }
            }.log,
        };
        const outcome = self.import_handler.tryPrimitiveDispatch(
            imported.name,
            dispatch_cb,
            log_cb,
        );
        return switch (outcome) {
            .handled => |value| ImportHandlerResult{ .handled = value },
            .handled_void => .handled_void,
            .control_transferred => .control_transferred,
            .unhandled => null,
        };
    }

    fn handleImportImpl(self: *MachOState, imported: macho_metadata.ImportedSymbol) ImportHandlerResult {
        return import_dispatch.handleImportImpl(self, imported);
    }

    pub fn handleVirtualSleepSchedulingBoundary(self: *MachOState, reason: []const u8) bool {
        return import_dispatch.handleVirtualSleepSchedulingBoundary(self, reason);
    }

    pub fn handleDirectImportCall(self: *MachOState, imported: macho_metadata.ImportedSymbol) void {
        import_dispatch.handleDirectImportCall(self, imported);
    }

    fn recordUnresolvedImport(
        self: *MachOState,
        imported: macho_metadata.ImportedSymbol,
        return_address: u64,
        synthetic_result: u64,
    ) void {
        import_dispatch.recordUnresolvedImport(self, imported, return_address, synthetic_result);
    }

    // F1 (throughput audit): `noinline` on the special-RIP chain and the
    // sentinel handlers. Every one of these is reached at most once per step,
    // and only when `specialRipPossible()` (or a sentinel compare) already
    // said so — which is false for essentially every instruction. Inlined,
    // their bodies and their diagnostic formatting sat inside `step`, on the
    // same cache lines as the fetch/decode/dispatch sequence that does run
    // every instruction. Cost when they do fire: one `bl`.
    noinline fn continueGuestExit(self: *MachOState) bool {
        return import_dispatch.continueGuestExit(self);
    }

    pub fn handleSigaction(self: *MachOState) u64 {
        return signal_handling.handleSigaction(self);
    }

    pub fn deliverGuestSignal(
        self: *MachOState,
        signal: u8,
        fault_rip: u64,
        instruction_len: u8,
        fault_address: u64,
        fault_access: ?GuestAccess,
        fault_width: u8,
        fault_instruction: []const u8,
    ) bool {
        return signal_handling.deliverGuestSignal(self, signal, fault_rip, instruction_len, fault_address, fault_access, fault_width, fault_instruction);
    }

    pub fn signalIsActive(self: *const MachOState, signal: u8) bool {
        return signal_handling.signalIsActive(self, signal);
    }

    pub fn resetActiveGuestSignalState(self: *MachOState) void {
        scheduling.resetActiveGuestSignalState(self);
    }

    pub fn ensureGuestSignalFrameStorage(self: *MachOState, frame: *GuestSignalFrame) bool {
        return signal_handling.ensureGuestSignalFrameStorage(self, frame);
    }

    pub noinline fn finishGuestSignalReturn(self: *MachOState) bool {
        return signal_handling.finishGuestSignalReturn(self);
    }

    pub fn terminateForUnresolvedImport(self: *MachOState) void {
        crash_diag.terminateForUnresolvedImport(self);
    }

    pub fn recoverLibcppSharedControlBlockCall(
        self: *MachOState,
        instruction_address: u64,
        operand_address: u64,
    ) ?u64 {
        return crash_diag.recoverLibcppSharedControlBlockCall(self, instruction_address, operand_address);
    }

    /// Static helper: matches XModule vtable symbols.
    pub fn isXModuleMatchesSymbol(symbol: []const u8) bool {
        return crash_diag.isXModuleMatchesSymbol(symbol);
    }

    pub fn findNearNullBaseTransition(self: *MachOState, register: RegId, terminal_value: u64) ?crash_diag.NearNullBaseTransition {
        return crash_diag.findNearNullBaseTransition(self, register, terminal_value);
    }

    pub fn ensureXmoduleVtable(self: *MachOState) ?u64 {
        return crash_diag.ensureXmoduleVtable(self);
    }

    pub fn recoverNearNullBaseRegister(self: *MachOState, d: *DecodedInsn) bool {
        return crash_diag.recoverNearNullBaseRegister(self, d);
    }

    pub fn recoverNullVtableSlot(self: *MachOState, instruction_address: u64, operand_address: u64) ?u64 {
        return crash_diag.recoverNullVtableSlot(self, instruction_address, operand_address);
    }

    pub fn logCrashDiagnostics(self: *MachOState, context: ControlTransferContext) void {
        crash_diag.logCrashDiagnostics(self, context);
    }

    pub fn terminateForInvalidControlTransfer(self: *MachOState, context: ControlTransferContext) void {
        crash_diag.terminateForInvalidControlTransfer(self, context);
    }

    pub fn handleOpen(self: *MachOState) u64 {
        return guest_fs.handleOpen(self);
    }

    pub fn registerGuestFd(self: *MachOState, host_fd: c_int) ?u64 {
        return guest_fs.registerGuestFd(self, host_fd);
    }

    pub fn setGuestErrno(self: *MachOState, value: c_int) void {
        guest_fs.setGuestErrno(self, value);
    }

    pub fn hostFd(self: *MachOState, guest_or_host_fd: u64) ?c_int {
        return guest_fs.hostFd(self, guest_or_host_fd);
    }

    pub fn handleFstatat(self: *MachOState) u64 {
        return guest_fs.handleFstatat(self);
    }

    pub fn handleOpenat(self: *MachOState) u64 {
        return guest_fs.handleOpenat(self);
    }

    pub fn handleFstat(self: *MachOState) u64 {
        return guest_fs.handleFstat(self);
    }

    pub fn handleFtruncate(self: *MachOState) u64 {
        return guest_fs.handleFtruncate(self);
    }

    pub fn handleOpendir(self: *MachOState) ?u64 {
        return guest_fs.handleOpendir(self);
    }

    pub fn handleClosedir(self: *MachOState) u64 {
        return guest_fs.handleClosedir(self);
    }

    pub fn handleWrite(self: *MachOState) u64 {
        return guest_fs.handleWrite(self);
    }

    pub fn handleClose(self: *MachOState) u64 {
        return guest_fs.handleClose(self);
    }

    pub fn hostWriteAll(self: *MachOState, file: *GuestFile, bytes: []const u8) bool {
        return guest_fs.hostWriteAll(self, file, bytes);
    }

    pub fn handleFopen(self: *MachOState) ?u64 {
        return guest_fs.handleFopen(self);
    }

    pub fn handleFdopen(self: *MachOState) ?u64 {
        return guest_fs.handleFdopen(self);
    }

    pub fn handleFileno(self: *MachOState) u64 {
        return guest_fs.handleFileno(self);
    }

    pub fn handleFclose(self: *MachOState) u64 {
        return guest_fs.handleFclose(self);
    }

    pub fn handleFputs(self: *MachOState) u64 {
        return guest_fs.handleFputs(self);
    }

    pub fn handleFwrite(self: *MachOState) u64 {
        return guest_fs.handleFwrite(self);
    }

    pub fn handleFread(self: *MachOState) u64 {
        return guest_fs.handleFread(self);
    }

    pub fn handleFflush(self: *MachOState) u64 {
        return guest_fs.handleFflush(self);
    }

    pub fn handleFtell(self: *MachOState) u64 {
        return guest_fs.handleFtell(self);
    }

    pub fn handleFseek(self: *MachOState) u64 {
        return guest_fs.handleFseek(self);
    }

    pub fn handleFerror(self: *MachOState) u64 {
        return guest_fs.handleFerror(self);
    }

    pub fn handleFprintf(self: *MachOState) u64 {
        return guest_fs.handleFprintf(self);
    }

    pub fn handleSnprintf(self: *MachOState) u64 {
        return guest_fs.handleSnprintf(self);
    }

    pub fn handlePrintfLike(self: *MachOState, file_opt: ?*GuestFile, format_address: u64, arguments: []const u64) u64 {
        return guest_fs.handlePrintfLike(self, file_opt, format_address, arguments);
    }

    pub fn handlePutchar(self: *MachOState) u64 {
        return guest_fs.handlePutchar(self);
    }

    pub fn handleGtkInitCheck(self: *MachOState) u64 {
        return guest_fs.handleGtkInitCheck(self);
    }

    pub fn nextVarArg(self: *const MachOState, arguments: []const u64, gp_index: *usize, stack_arg_addr: *u64) u64 {
        if (gp_index.* < arguments.len) {
            defer gp_index.* += 1;
            return arguments[gp_index.*];
        }
        const addr = stack_arg_addr.*;
        stack_arg_addr.* += 8;
        return self.read64(addr);
    }

    /// Learn which guest structures generated code treats as state.
    ///
    /// A 64-bit load through `base + small displacement` is how compiled code
    /// reads a structure field, and those fields are what the dispatch
    /// recognizers end up asking about. Watching their pages puts them under
    /// write provenance without arming it globally — the difference between
    /// "who wrote this" being answerable and being a flag the operator had to
    /// set before knowing which address mattered.
    ///
    /// Runs only for generated code (1.8% of executed steps) and stops entirely
    /// once the bounded set is full, so the cost is a short prefix of the run.
    /// Record the structure-field access shape for a generated-code operand.
    /// Separate from the watch seed because it must keep counting after the
    /// watch fills: the interesting fact is a ratio of reads to writes over the
    /// whole run, not the first few pages.
    fn noteGuestFieldAccess(self: *MachOState, decoded: DecodedInsn) void {
        const is_write = switch (decoded.op) {
            .mov_mem64_reg64,
            .mov_mem32_reg32,
            .mov_mem16_reg16,
            .mov_mem8_reg8,
            .mov_mem64_imm32,
            .mov_mem32_imm32,
            .mov_mem16_imm16,
            .mov_mem8_imm8,
            .movbe_mem_reg,
            => true,
            .mov_reg64_mem64,
            .mov_reg32_mem32,
            .mov_reg16_mem16,
            .mov_reg8_mem8,
            .movbe_reg_mem,
            => false,
            else => return,
        };
        if (!decoded.sib_has_base or decoded.sib_has_index or decoded.rip_relative) return;
        const base = self.regVal(decoded.sib_base_reg, .bits64);
        const effective = decoded.addr;
        if (base == 0 or effective < base) return;
        self.guest_fields.note(base, effective - base, is_write);
    }

    fn seedProvenanceWatch(self: *MachOState, decoded: DecodedInsn) void {
        if (self.provenance_watch.full()) return;
        if (decoded.op != .mov_reg64_mem64) return;
        if (!decoded.sib_has_base or decoded.sib_has_index or decoded.rip_relative) return;
        // On the execute path `decoded.addr` is the *resolved* effective
        // address (the decode cache applies live registers), not the raw
        // displacement. Recover the displacement rather than adding the base a
        // second time.
        const base = self.regVal(decoded.sib_base_reg, .bits64);
        const effective = decoded.addr;
        if (effective < base) return;
        _ = self.provenance_watch.seedFromOperand(base, effective - base);
    }

    fn recordTrace(self: *MachOState, decoded: DecodedInsn) void {
        self.execution_history.record(self.active_guest_thread, .{
            .thread_handle = self.active_guest_thread,
            .history_epoch = self.execution_history_epoch,
            .rip = self.regs.rip,
            .op = decoded.op,
            .len = decoded.len,
            .rsp = self.regs.rsp,
            .rax = self.regs.rax,
            .rbx = self.regs.rbx,
            .rcx = self.regs.rcx,
            .rdx = self.regs.rdx,
            .rsi = self.regs.rsi,
            .rdi = self.regs.rdi,
            .rbp = self.regs.rbp,
            .r8 = self.regs.r8,
            .r9 = self.regs.r9,
            .r10 = self.regs.r10,
            .r11 = self.regs.r11,
            .r12 = self.regs.r12,
            .r13 = self.regs.r13,
            .r14 = self.regs.r14,
            .r15 = self.regs.r15,
        });
    }

    fn shouldTraceRIP(self: *const MachOState, rip: u64) bool {
        if (self.trace_range_start) |start| {
            const end = self.trace_range_end orelse start;
            return rip >= start and rip <= end;
        }
        return false;
    }

    pub fn dumpRecentTrace(self: *const MachOState) void {
        const count: usize = self.execution_history.countFor(self.active_guest_thread);
        if (count == 0) return;
        log.err("recent trace dump (most recent last, count={d})", .{count});
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const entry = self.execution_history.chronological(self.active_guest_thread, i) orelse continue;
            log.err("trace[{d}]: thread=0x{x} rip=0x{x} op={s} len={d} rsp=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x}", .{
                i,
                entry.thread_handle,
                entry.rip,
                @tagName(entry.op),
                entry.len,
                entry.rsp,
                entry.rax,
                entry.rcx,
                entry.rdx,
            });
        }
    }

    // F2 (throughput audit): these four forward to the register-file accessors
    // and must not become call frames of their own. Before `inline`, the
    // shipped binary contained 60 out-of-line `bl` to this wrapper and 33 to
    // `setReg` from `execute` alone.
    pub inline fn regVal(self: *const MachOState, id: RegId, size: Size) u64 {
        return x64_decoder.regVal(&self.regs, id, size);
    }

    pub inline fn setReg(self: *MachOState, id: RegId, size: Size, val: u64) void {
        x64_decoder.setReg(&self.regs, id, size, val);
    }

    pub inline fn regOperandVal(self: *const MachOState, id: RegId, size: Size, high8: bool) u64 {
        return x64_decoder.registerOperandValue(&self.regs, .{ .id = id, .high8 = high8 }, size);
    }

    pub inline fn setRegOperand(self: *MachOState, id: RegId, size: Size, high8: bool, val: u64) void {
        x64_decoder.setRegisterOperand(&self.regs, .{ .id = id, .high8 = high8 }, size, val);
    }

    pub fn setFlagsSub(self: *MachOState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applySub(&self.regs.rflags, a, b, result, size);
    }

    pub fn setFlagsAdd(self: *MachOState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applyAdd(&self.regs.rflags, a, b, result, size);
    }

    pub fn setFlagsIncDec(self: *MachOState, input: u64, result: u64, size: Size, is_inc: bool) void {
        x64_decoder.applyIncDec(&self.regs.rflags, input, result, size, is_inc);
    }

    pub fn setFlagsLogic(self: *MachOState, result: u64, size: Size) void {
        x64_decoder.applyLogic(&self.regs.rflags, result, size);
    }

    pub fn executeHighwayRegisterBinary(self: *MachOState, d: DecodedInsn, op: x64_decoder.highway.BinaryOp, size: Size) void {
        const width: x64_decoder.highway.Width = switch (size) {
            .bits8 => .bits8,
            .bits16 => .bits16,
            .bits32 => .bits32,
            .bits64 => .bits64,
        };
        const evaluated = x64_decoder.highway.evaluate(
            op,
            width,
            self.regOperandVal(d.dst_reg, size, d.dst_high8),
            self.regOperandVal(d.src_reg, size, d.src_high8),
            self.regs.rflags,
        );
        self.regs.rflags = evaluated.rflags;
        if (evaluated.writeback) self.setRegOperand(d.dst_reg, size, d.dst_high8, evaluated.value);
    }

    pub fn executeHighwayMemoryBinary(
        self: *MachOState,
        d: DecodedInsn,
        op: x64_decoder.highway.BinaryOp,
        size: Size,
        direction: x64_decoder.highway.MemoryDirection,
    ) void {
        const width: x64_decoder.highway.Width = switch (size) {
            .bits8 => .bits8,
            .bits16 => .bits16,
            .bits32 => .bits32,
            .bits64 => .bits64,
        };
        // F6 (throughput audit): no `ensureGuestAccess` pre-check here. It did a
        // sparse probe plus a `translateGuest`, and `readMemVal`/`writeMemVal`
        // below immediately repeat both — so every `add reg,[mem]`,
        // `cmp [mem],reg` and friend translated its address twice. The
        // accessors already terminate on an inaccessible address, through the
        // same `terminateForGuestAccess`, with a better instruction label than
        // `@tagName(op)` gave.
        const reg = if (direction == .memory_to_register) d.dst_reg else d.src_reg;
        const reg_high8 = if (direction == .memory_to_register) d.dst_high8 else d.src_high8;
        const memory_value = self.readMemVal(d.addr, size);
        // Endian-contract evidence belongs only to JIT-generated code. Native
        // Xenia executes a large number of 32-bit memory comparisons; sending
        // each through a sparse executable probe and evidence ring made an
        // exceptional recovery predicate part of the ordinary hot path.
        const generated_endian_candidate =
            op == .cmp and size == .bits32 and direction == .memory_to_register and
            (self.regs.rip < self.executable_min or self.regs.rip >= self.executable_max);
        if (generated_endian_candidate) {
            self.recordEndianEvidence(.cmp_witness, reg, d.addr, size, memory_value);
        }
        var register_value = self.regOperandVal(reg, size, reg_high8);
        if (generated_endian_candidate) {
            if (self.tryRepairGeneratedEndianBeforeDispatch(reg, d.addr, memory_value, d.len)) |restored| {
                register_value = restored;
            }
        }
        const evaluated = x64_decoder.highway.evaluateMemory(op, width, register_value, memory_value, direction, self.regs.rflags);
        self.regs.rflags = evaluated.rflags;
        if (evaluated.write_register) self.setRegOperand(reg, size, reg_high8, evaluated.value);
        if (evaluated.write_memory) self.writeMemVal(d.addr, size, evaluated.value);
    }

    pub fn executeHighwayImmediate(self: *MachOState, d: DecodedInsn, op: x64_decoder.highway.BinaryOp, size: Size, memory: bool) void {
        const width: x64_decoder.highway.Width = switch (size) {
            .bits8 => .bits8,
            .bits16 => .bits16,
            .bits32 => .bits32,
            .bits64 => .bits64,
        };
        // F6: same removal as `executeHighwayMemoryBinary` — `readMemVal` and
        // `writeMemVal` perform and report the translation themselves.
        const lhs = if (memory) self.readMemVal(d.addr, size) else self.regOperandVal(d.dst_reg, size, d.dst_high8);
        const evaluated = x64_decoder.highway.evaluate(op, width, lhs, d.imm, self.regs.rflags);
        self.regs.rflags = evaluated.rflags;
        if (evaluated.writeback) {
            if (memory) self.writeMemVal(d.addr, size, evaluated.value) else self.setRegOperand(d.dst_reg, size, d.dst_high8, evaluated.value);
        }
    }

    pub fn setFlag(self: *MachOState, flag: u32, enabled: bool) void {
        if (enabled) {
            self.regs.rflags |= flag;
        } else {
            self.regs.rflags &= ~flag;
        }
    }

    pub fn executeBitTestRegister(
        self: *MachOState,
        d: DecodedInsn,
        operation: x64_decoder.BitTestOperation,
        immediate_index: bool,
    ) void {
        const value = self.regVal(d.dst_reg, d.size);
        const raw_index = if (immediate_index) d.imm else self.regVal(d.src_reg, d.size);
        const result = x64_decoder.bitTestRegister(d.size, value, raw_index, operation);
        self.setFlag(RFL_CF, result.carry);
        if (operation != .probe) self.setReg(d.dst_reg, d.size, result.value);
    }

    pub fn executeBitTestMemory(
        self: *MachOState,
        d: DecodedInsn,
        operation: x64_decoder.BitTestOperation,
        immediate_index: bool,
    ) void {
        const operand = if (immediate_index)
            x64_decoder.bitTestMemoryOperandImmediate(d.size, d.addr, d.imm)
        else
            x64_decoder.bitTestMemoryOperand(d.size, d.addr, self.regVal(d.src_reg, d.size));
        const resolved = operand orelse {
            self.faulted = true;
            self.terminated = true;
            return;
        };
        const value = self.readMemVal(resolved.address, d.size);
        const result = x64_decoder.bitTestRegister(d.size, value, resolved.bit_index, operation);
        self.setFlag(RFL_CF, result.carry);
        if (operation != .probe) self.writeMemVal(resolved.address, d.size, result.value);
    }

    fn terminateForMemoryAccess(self: *MachOState, check: x64_decoder.highway.MemoryCheck, instruction: []const u8) void {
        const access: GuestAccess = switch (check.access) {
            .read => .read,
            .write => .write,
            .execute => .execute,
            .atomic_read_modify_write => .write,
        };
        self.terminateForGuestAccess(check.address, check.bytes, access, instruction);
    }

    pub fn bitWidth(size: Size) u7 {
        return execution_helpers.bitWidth(size);
    }

    pub fn maskForSize(size: Size) u64 {
        return execution_helpers.maskForSize(size);
    }

    pub fn signBitForSize(size: Size) u64 {
        return execution_helpers.signBitForSize(size);
    }

    fn arithmeticShiftRight(value: u64, size: Size, count: u6) u64 {
        const signed: i64 = switch (size) {
            .bits8 => @as(i8, @bitCast(@as(u8, @truncate(value)))),
            .bits16 => @as(i16, @bitCast(@as(u16, @truncate(value)))),
            .bits32 => @as(i32, @bitCast(@as(u32, @truncate(value)))),
            .bits64 => @bitCast(value),
        };
        return @as(u64, @bitCast(signed >> count)) & maskForSize(size);
    }

    fn setupInitialStack(self: *MachOState, args: []const []const u8) void {
        var sp = self.mem_base + self.mem_size;

        sp -= 8;
        self.write64(sp, 0);

        sp -= 8;
        const envp_addr = sp;
        self.write64(sp, 0);

        var arg_addrs: std.ArrayList(u64) = .empty;
        defer arg_addrs.deinit(self.allocator);
        for (args) |arg| {
            sp -|= arg.len + 1;
            for (arg, 0..) |c, i| {
                self.write8(sp + i, c);
            }
            self.write8(sp + arg.len, 0);
            arg_addrs.append(self.allocator, sp) catch {};
        }

        sp -= 8;
        self.write64(sp, 0);

        for (0..arg_addrs.items.len) |i| {
            sp -= 8;
            self.write64(sp, arg_addrs.items[arg_addrs.items.len - 1 - i]);
        }
        const argv_addr = sp;

        sp -= 8;
        const argc_val: u64 = @intCast(args.len);
        self.write64(sp, argc_val);

        sp &= ~@as(u64, 15);
        sp -= 8;

        self.regs.rdi = argc_val;
        self.regs.rsi = argv_addr;
        self.regs.rdx = envp_addr;
        self.regs.rsp = sp;
    }

    fn setupMachOState(self: *MachOState, path: []const u8, args: []const []const u8) void {
        machoCapturePrint("ROSETTE: setupMachOState called with path: '{s}'\n", .{path});
        machoCapturePrint("ROSETTE: Argument count: {d}\n", .{args.len});
        for (args, 0..) |arg, i| {
            machoCapturePrint("ROSETTE:   argv[{d}] = '{s}'\n", .{ i, arg });
        }

        self.configureGuestLogMirror(args);
        self.launch_options.configure(args);
        var argument_index: usize = 0;
        while (argument_index < args.len) : (argument_index += 1) {
            const argument = args[argument_index];
            if (std.mem.eql(u8, argument, "--storage_root") and argument_index + 1 < args.len) {
                self.fs_forwarder.configurePaths(args[argument_index + 1]);
                break;
            }
            const prefix = "--storage_root=";
            if (std.mem.startsWith(u8, argument, prefix)) {
                self.fs_forwarder.configurePaths(argument[prefix.len..]);
                break;
            }
            if (std.mem.eql(u8, argument, "--fs-fallback") and argument_index + 1 < args.len) {
                self.fs_forwarder.addFallbackRoot(args[argument_index + 1]);
            }
            const fb_prefix = "--fs-fallback=";
            if (std.mem.startsWith(u8, argument, fb_prefix)) {
                self.fs_forwarder.addFallbackRoot(argument[fb_prefix.len..]);
            }
            if (std.mem.eql(u8, argument, "--no-xenia-compat")) {
                self.has_xenia_compat = false;
                machoCapturePrint(
                    "macho-processor: Xenia-specific compatibility handlers disabled (--no-xenia-compat)\n",
                    .{},
                );
            }
            if (std.mem.eql(u8, argument, "--wall-clock-time")) {
                self.guest_time.time_mode = .wall_clock;
                self.guest_time.captureWallClockBaseline();
                machoCapturePrint(
                    "macho-processor: wall-clock time mode enabled (--wall-clock-time)\n",
                    .{},
                );
            }
            // Generic alternatives to Xenia-specific --storage_root
            if (std.mem.eql(u8, argument, "--storage-root") and argument_index + 1 < args.len) {
                self.fs_forwarder.configurePaths(args[argument_index + 1]);
                break;
            }
            const sr_prefix = "--storage-root=";
            if (std.mem.startsWith(u8, argument, sr_prefix)) {
                self.fs_forwarder.configurePaths(argument[sr_prefix.len..]);
                break;
            }
            if (std.mem.eql(u8, argument, "--data-dir") and argument_index + 1 < args.len) {
                self.fs_forwarder.configurePaths(args[argument_index + 1]);
                break;
            }
            const dd_prefix = "--data-dir=";
            if (std.mem.startsWith(u8, argument, dd_prefix)) {
                self.fs_forwarder.configurePaths(argument[dd_prefix.len..]);
                break;
            }
            // Generic alternative to Xenia-specific --fs-fallback
            if (std.mem.eql(u8, argument, "--fs-fallback-path") and argument_index + 1 < args.len) {
                self.fs_forwarder.addFallbackRoot(args[argument_index + 1]);
            }
            const fbp_prefix = "--fs-fallback-path=";
            if (std.mem.startsWith(u8, argument, fbp_prefix)) {
                self.fs_forwarder.addFallbackRoot(argument[fbp_prefix.len..]);
            }
        }
        var full_args = std.ArrayList([]const u8).empty;
        defer full_args.deinit(self.allocator);
        full_args.append(self.allocator, path) catch {};
        for (args) |a| full_args.append(self.allocator, a) catch {};

        machoCapturePrint("ROSETTE: Full argv count (including path): {d}\n", .{full_args.items.len});
        machoCapturePrint("ROSETTE: Entry point vaddr: 0x{x}\n", .{self.entry_point_vaddr});

        // Trace range is left unset by default. Set trace_range_start/trace_range_end
        // here (e.g. 0x1332000..0x1333000) to enable target-trace logging for debugging.
        self.last_trace_rip = 0;
        self.last_trace_op = 0;
        self.trace_repeat_count = 0;
        self.setupInitialStack(full_args.items);
        self.regs.rip = self.entry_point_vaddr;

        machoCapturePrint("ROSETTE: setupMachOState complete - RIP set to 0x{x}\n", .{self.regs.rip});
    }

    pub fn initializerAbi(self: *const MachOState) initialization_resolution.AbiSnapshot {
        return initializers.initializerAbi(self);
    }

    pub fn beginInitializerTransaction(self: *MachOState) void {
        initializers.beginInitializerTransaction(self);
    }

    pub fn rollbackInitializerTransaction(self: *MachOState) bool {
        return initializers.rollbackInitializerTransaction(self);
    }

    pub fn commitInitializerTransaction(self: *MachOState) bool {
        return initializers.commitInitializerTransaction(self);
    }

    pub fn runOneInitializer(self: *MachOState, launch_regs: Regs, index: usize, is_retry: bool) InitializerRunOutcome {
        return initializers.runOneInitializer(self, launch_regs, index, is_retry);
    }

    pub fn runInitializers(self: *MachOState) bool {
        return initializers.runInitializers(self);
    }

    pub fn appendTrivialVector(self: *MachOState, vector: u64, item: u64, element_size: u64, minimum_capacity: u32) bool {
        return initializers.appendTrivialVector(self, vector, item, element_size, minimum_capacity);
    }

    pub fn handleLibcppBasicStringSubstr(self: *MachOState) bool {
        return compat_handlers.handleLibcppBasicStringSubstr(self);
    }

    pub noinline fn handleInternalCompatibility(self: *MachOState) bool {
        return compat_handlers.handleInternalCompatibility(self);
    }

    pub fn handlePageEntryBulkInitialization(self: *MachOState) bool {
        return compat_handlers.handlePageEntryBulkInitialization(self);
    }

    pub fn handleLocalLibcppStreamCompatibility(self: *MachOState) bool {
        return compat_handlers.handleLocalLibcppStreamCompatibility(self);
    }

    pub fn capturePositionalLaunchOptions(self: *MachOState) void {
        compat_handlers.capturePositionalLaunchOptions(self);
    }

    pub fn handleGuestLogBridge(self: *MachOState) bool {
        return compat_handlers.handleGuestLogBridge(self);
    }

    pub fn handleCxxoptsSplitOptionNames(self: *MachOState) bool {
        return compat_handlers.handleCxxoptsSplitOptionNames(self);
    }

    pub noinline fn handleTomlAsciiFastPath(self: *MachOState) bool {
        return compat_handlers.handleTomlAsciiFastPath(self);
    }

    pub noinline fn handleTomlReadNextIntegrity(self: *MachOState) void {
        compat_handlers.handleTomlReadNextIntegrity(self);
    }

    pub noinline fn handlePatchDbEmptyPatchArray(self: *MachOState) bool {
        return compat_handlers.handlePatchDbEmptyPatchArray(self);
    }

    pub fn logStalledInstructionDetails(self: *MachOState) void {
        compat_handlers.logStalledInstructionDetails(self);
    }

    fn executionFingerprint(self: *const MachOState) u64 {
        var hash: u64 = 0x9e37_79b9_7f4a_7c15;
        const values = [_]u64{
            self.regs.rax,    self.regs.rbx, self.regs.rcx, self.regs.rdx,
            self.regs.rsi,    self.regs.rdi, self.regs.rbp, self.regs.rsp,
            self.regs.r8,     self.regs.r9,  self.regs.r10, self.regs.r11,
            self.regs.r12,    self.regs.r13, self.regs.r14, self.regs.r15,
            self.regs.rflags,
        };
        for (values) |value| {
            hash ^= value +% 0x9e37_79b9_7f4a_7c15 +% (hash << 6) +% (hash >> 2);
        }
        return if (hash == 0) 1 else hash;
    }

    fn executableInstructionBytesAt(self: *const MachOState, address: u64) ?[]const u8 {
        // Dynamically generated x64 code (Xenia's code cache begins at
        // 0xA0000000) lives in sparse mappings rather than self.mem. Fetch
        // from the executable sparse view first so mprotect metadata remains
        // authoritative and reservation-backed JIT pages are decodable.
        // F12 (throughput audit): one descending probe, not sixteen.
        //
        // This used to call `executableBytesConst` with count = 16, 15, 14 …
        // until one succeeded, and each of those calls re-ran `isExecutable`
        // *and* the page-cache probe internally — three page-cache lookups per
        // iteration for a question already answered. The common case cost 3
        // probes instead of 1; near the end of a mapping it degraded to ~48.
        //
        // Halving instead of decrementing bounds the tail at 5 probes while
        // keeping the same result: the longest prefix, up to 16 bytes, that the
        // executable mapping can supply. A shorter slice is always safe — the
        // decoder rejects a truncated instruction rather than misreading one.
        if (self.sparse_memory.isExecutable(address, 1)) {
            var count: u64 = 16;
            while (count > 1) : (count /= 2) {
                if (self.sparse_memory.executableBytesConst(address, count)) |bytes| return bytes;
            }
            return self.sparse_memory.executableBytesConst(address, 1);
        }

        const offset = self.addrToOffset(address) orelse return null;
        if (offset >= self.mem.len) return null;
        const remaining = self.mem.len - @as(usize, @intCast(offset));
        return self.mem[@intCast(offset)..][0..@min(@as(usize, 16), remaining)];
    }

    /// R2 (N3): single special-RIP probe replacing the 9 per-instruction
    /// handler calls (which paid ~65 compares + 1 function call on every
    /// instruction even when all inert). True only when `rip` could possibly
    /// match one of the load-time-resolved fixed targets (one binary search
    /// over special_rip_table) or one of the O(1) range/state probes. The
    /// chain in step() is provably inert when this returns false, so it is
    /// skipped wholesale. Over-permissive hits are safe (the chain re-verifies
    /// every condition); a miss must imply no handler can fire.
    ///
    /// Note (deviation from the audit's "any_special_rips bool"): the gate
    /// always runs (~10 compares) rather than being short-circuited by a bool
    /// computed at load, because the dynamic-library thunk region can be
    /// populated at runtime (guest symbols are allocated as dylibs load), so a
    /// static bool could incorrectly suppress its probe. ~10 compares is still
    /// ~4x cheaper than the pre-R2 9 calls + ~65 compares.
    fn specialRipPossible(self: *const MachOState) bool {
        if (self.special_rip_table_failed) return true; // fallback: run the chain always
        const rip = self.regs.rip;
        // All synthetic/thunk bases live at or above the TLV bootstrap thunk
        // (0xFFFF_F700_0000_0000). One watermark compare replaces the five
        // per-region probes for the overwhelmingly common main-image rip.
        if (rip >= tlv_runtime.bootstrap_thunk) {
            if (rip >= BOUND_IMPORT_THUNK_BASE) return true;
            if (compat_runtime.syntheticThunk(rip) != null) return true;
            if (tlv_runtime.Runtime.handles(rip)) return true;
            if (rip >= dynamic_library_forwarder.GUEST_SYMBOL_THUNK_BASE) {
                const offset = rip - dynamic_library_forwarder.GUEST_SYMBOL_THUNK_BASE;
                if (offset != 0 and offset % 16 == 1 and
                    (offset - 1) / 16 < dynamic_library_forwarder.MAX_GUEST_SYMBOLS)
                {
                    return true;
                }
            }
            return false;
        }
        if (self.special_rip_table.len != 0 and specialRipTableContains(self.special_rip_table, rip)) return true;
        if (rip >= self.stub_helper_start and rip < self.stub_helper_end) return true;
        if (self.libcpp_stream_target_max != 0 and
            rip >= self.libcpp_stream_target_min and
            rip <= self.libcpp_stream_target_max) return true;
        if (self.config_parsing_active and self.regs.rdi == 0 and
            self.libcxx_streams.latestPatchSchemaHasEmptyPatchSet())
        {
            return true;
        }
        return false;
    }

    /// R2 (N3): collect every fixed special-RIP address the per-instruction
    /// handler chain probes, sort and deduplicate, and publish the table. The
    /// array is bounded (26 internal targets + 32 cvar vector slots + 2 toml
    /// entries), so a fixed stack buffer avoids intermediate allocation.
    fn buildSpecialRipTable(self: *MachOState) !void {
        var entries: [64]u64 = undefined;
        var count: usize = 0;
        const targets = &self.internal_targets;
        const fixed = [_]u64{
            targets.cxxopts_split_option_names,
            targets.xenia_cpu_feature_detector_initialize_cpu_info,
            targets.xenia_vulkan_provider_vulkan_device,
            targets.parse_launch_arguments,
            targets.initialize_logging,
            targets.shutdown_logging,
            targets.guest_log_get_thread_buffer,
            targets.guest_log_append_formatted,
            targets.guest_log_append_view,
            targets.libcxx_basic_streambuf_pubsetbuf,
            targets.libcxx_basic_ifstream_default_constructor,
            targets.libcxx_basic_ifstream_destructor_1,
            targets.libcxx_basic_ifstream_destructor_2,
            targets.libcxx_getline,
            targets.libcxx_getline_delimiter,
            targets.libcxx_basic_string_substr,
            targets.print_config_to_log,
            targets.imgui_default_malloc,
            targets.imgui_default_free,
            targets.imgui_mem_alloc,
            targets.imgui_mem_free,
            targets.imgui_settings_push_back,
            targets.imgui_create_context,
            targets.imgui_get_current_window,
            targets.imgui_text_ex,
            targets.page_entry_construct_at_end,
        };
        for (fixed) |address| {
            if (address != 0) {
                entries[count] = address;
                count += 1;
            }
        }
        for (targets.cvar_add_to_launch_options[0..targets.cvar_add_to_launch_options_count]) |address| {
            if (address != 0) {
                entries[count] = address;
                count += 1;
            }
        }
        if (self.toml_ascii_entry) |address| {
            entries[count] = address;
            count += 1;
        }
        if (self.toml_read_next_entry) |address| {
            entries[count] = address;
            count += 1;
        }
        // The fixed targets (26) + cvar vector (32) + toml entries (2) bound
        // at 60 < 64. Assert rather than silently truncate: a truncated table
        // would make the gate miss entries and skip handler dispatch with no
        // diagnostic — the exact failure mode a completeness gate must not have.
        std.debug.assert(count <= entries.len);
        std.mem.sort(u64, entries[0..count], {}, std.sort.asc(u64));
        // Deduplicate adjacent equal addresses (multiple conditions may match).
        var write: usize = 0;
        for (entries[0..count]) |address| {
            if (write != 0 and entries[write - 1] == address) continue;
            entries[write] = address;
            write += 1;
        }
        self.special_rip_table = try self.allocator.dupe(u64, entries[0..write]);
        machoCapturePrint(
            "macho-processor: special-RIP table built: entries={d} (R2/N3 single-probe dispatch)\n",
            .{self.special_rip_table.len},
        );
    }

    /// Whether a cached decode's address has to be recomputed from live registers.
    ///
    /// The address is `displacement + base + index*scale (+ segment base)`. Every
    /// term but the registers and the FS/GS base is fixed for the lifetime of a
    /// cache entry, so an instruction that names no base and no index resolves to
    /// the same address on every hit — the one already stored when the entry was
    /// populated. Re-deriving it meant every register-form instruction, every
    /// immediate form and every jump paid `resolveMemoryAddress` to arrive back at
    /// the value it started with.
    ///
    /// FS and GS are the exception and are treated as live: in long mode they are
    /// the only segments with a non-zero base, and a thread-local access moves when
    /// the thread does.
    ///
    /// Note what this deliberately does *not* do: cache the resolved address
    /// against a "the registers still hold these values" stamp. Deciding that the
    /// stamp still matches requires reading the base and index registers, and
    /// reading them through `regVal`'s register switch is the expensive half of the
    /// resolution — so the check would cost about what it saves.
    pub fn addressNeedsLiveRegisters(decoded: DecodedInsn) bool {
        if (decoded.rip_relative) return false;
        return decoded.sib_has_base or decoded.sib_has_index or
            decoded.segment == .fs or decoded.segment == .gs;
    }

    /// Exact LRU for a two-way set: the way just used becomes the survivor and
    /// the other becomes the eviction candidate. Written only when it changes,
    /// so a repeatedly hit entry stores nothing on the hot path.
    inline fn noteDecodeCacheUse(ways: []DecodeCacheEntry, used: *DecodeCacheEntry) void {
        if (used.recently_used) return;
        for (ways) |*way| way.recently_used = false;
        used.recently_used = true;
    }

    /// The decode-cache entry for the current RIP, when one exists that was
    /// filled with the full validation gate chain already run and declined
    /// (not a special-RIP target, executable, config parsing idle, table
    /// intact). On such a hit the per-instruction gate chain is provably
    /// redundant, so `step` skips it. This returns the decoded instruction as
    /// well as the cached host-image classification, avoiding a second probe
    /// in `decodeWithLiveOperands`.
    inline fn decodeFastPlain(self: *MachOState) ?FastPlainDecode {
        const rip = self.regs.rip;
        const set_base = constants.decodeCacheSetBase(rip);
        const ways = self.decode_cache[set_base..][0..constants.DECODE_CACHE_WAYS];
        for (ways) |*candidate| {
            if (candidate.rip == rip and
                candidate.code_generation == self.code_generation and
                candidate.fast_plain)
            {
                self.decode_cache_hits +|= 1;
                noteDecodeCacheUse(ways, candidate);
                var decoded = candidate.decoded;
                if (addressNeedsLiveRegisters(decoded)) {
                    const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
                    decoded.addr = x64_decoder.resolveMemoryAddress(&self.regs, .{
                        .displacement = candidate.displacement,
                        .has_index = decoded.sib_has_index,
                        .index_reg = decoded.sib_index_reg,
                        .scale = decoded.sib_scale,
                        .has_base = decoded.sib_has_base,
                        .base_reg = decoded.sib_base_reg,
                        .rip_relative = decoded.rip_relative,
                        .segment = decoded.segment,
                    }, self.regs.rip +% decoded.len, address_size, .long64, decoded.op != .lea_reg_mem);
                }
                return .{ .decoded = decoded, .host_image = candidate.host_image };
            }
        }
        return null;
    }

    /// Decode the instruction at the current RIP and resolve its memory operand
    /// against the **live** register file, via the decode cache. This is the
    /// execution path's decoder; the other two are readers.
    ///
    /// `gates_free` tells the fill path whether the caller already proved this
    /// RIP needs no special handling and is executable (the `step` fast path,
    /// where the special-RIP chain declined and `isExecutableAddress` passed).
    /// Only then may the entry be marked `fast_plain`; the guest-function
    /// helper and other non-gated decoders pass false and keep those entries on
    /// the slow path.
    fn decodeWithLiveOperands(self: *MachOState, gates_free: bool) ?DecodedInsn {
        // F17 (throughput audit): CS has no base in long mode — `segmentBase`
        // returns 0 for every segment but FS and GS (see addressing.zig). The
        // call was two compares and a load per instruction to add zero.
        const fetch_address = self.regs.rip;
        // Set-associative lookup. Direct-mapped, two hot instructions whose
        // addresses hash together evicted each other on every execution and
        // never recovered — a permanent conflict miss for code that is
        // otherwise perfectly cacheable. Two ways at the same total size fixes
        // the pair case, which is the common one.
        const set_base = constants.decodeCacheSetBase(fetch_address);
        const ways = self.decode_cache[set_base..][0..constants.DECODE_CACHE_WAYS];
        var entry: *DecodeCacheEntry = &ways[0];
        for (ways) |*candidate| {
            if (candidate.rip == fetch_address) {
                entry = candidate;
                break;
            }
        }
        // P0-2 (perf audit): generation-keyed fast path. Every executable
        // write bumps self.code_generation (noteGuestWrite) and precisely
        // clears overlapping entries, so a matching generation proves no
        // executable write touched this address since the entry was
        // populated — the cached decode is valid without re-fetching and
        // byte-comparing the source. Only when the generation moved (e.g. a
        // non-overlapping JIT write elsewhere) fall back to the byte check,
        // and re-arm the generation on a confirmed match so the next hit
        // takes the fast path again.
        if (entry.rip == fetch_address and entry.code_generation == self.code_generation) {
            self.decode_cache_hits +|= 1;
            noteDecodeCacheUse(ways, entry);
            var decoded = entry.decoded;
            if (addressNeedsLiveRegisters(decoded)) {
                const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
                decoded.addr = x64_decoder.resolveMemoryAddress(&self.regs, .{
                    .displacement = entry.displacement,
                    .has_index = decoded.sib_has_index,
                    .index_reg = decoded.sib_index_reg,
                    .scale = decoded.sib_scale,
                    .has_base = decoded.sib_has_base,
                    .base_reg = decoded.sib_base_reg,
                    .rip_relative = decoded.rip_relative,
                    .segment = decoded.segment,
                }, self.regs.rip +% decoded.len, address_size, .long64, decoded.op != .lea_reg_mem);
            }
            return decoded;
        }
        // Executable writes invalidate overlapping entries at the shared
        // memory-write boundary. Do not globally discard unrelated decoded
        // host/Xenia instructions whenever the JIT emits a new block.
        const fetched_bytes = if (entry.rip == fetch_address)
            self.executableInstructionBytesAt(fetch_address)
        else
            null;
        const cached_bytes_match = if (fetched_bytes) |current_bytes|
            entry.instruction_byte_count != 0 and
                current_bytes.len >= entry.instruction_byte_count and
                std.mem.eql(
                    u8,
                    entry.instruction_bytes[0..entry.instruction_byte_count],
                    current_bytes[0..entry.instruction_byte_count],
                )
        else
            false;
        if (entry.rip == fetch_address and cached_bytes_match) {
            self.decode_cache_hits +|= 1;
            noteDecodeCacheUse(ways, entry);
            entry.code_generation = self.code_generation;
            var decoded = entry.decoded;
            if (addressNeedsLiveRegisters(decoded)) {
                const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
                decoded.addr = x64_decoder.resolveMemoryAddress(&self.regs, .{
                    .displacement = entry.displacement,
                    .has_index = decoded.sib_has_index,
                    .index_reg = decoded.sib_index_reg,
                    .scale = decoded.sib_scale,
                    .has_base = decoded.sib_has_base,
                    .base_reg = decoded.sib_base_reg,
                    .rip_relative = decoded.rip_relative,
                    .segment = decoded.segment,
                }, self.regs.rip +% decoded.len, address_size, .long64, decoded.op != .lea_reg_mem);
            }
            return decoded;
        }
        if (entry.rip == fetch_address) {
            // Never execute a cached decode whose source bytes changed. This
            // catches JIT publication paths that did not pass through the
            // normal guest write boundary without flushing unrelated code.
            self.decode_cache_stale_rejections +|= 1;
            entry.* = .{};
        }
        self.decode_cache_misses +|= 1;
        // Which kind of miss this is, because the two have different remedies
        // and only one of them is fixable. A compulsory miss fills a way that
        // was never occupied — the first execution of code that has just been
        // emitted, which no cache can avoid. A conflict miss evicts a live
        // decode, which is capacity the cache could have kept.
        entry = &ways[0];
        var victim_is_empty = false;
        for (ways) |*candidate| {
            if (candidate.rip == std.math.maxInt(u64)) {
                entry = candidate;
                victim_is_empty = true;
                break;
            }
            if (!candidate.recently_used) entry = candidate;
        }
        if (victim_is_empty) {
            self.decode_cache_compulsory_misses +|= 1;
        } else {
            self.decode_cache_conflict_misses +|= 1;
        }
        const bytes = fetched_bytes orelse self.executableInstructionBytesAt(fetch_address) orelse return null;
        var decoded = decodeInsn(bytes);
        if (decoded.op == .invalid and self.sparse_memory.containsMapped(fetch_address, 1)) {
            decoded = decodeInsnCompat(bytes);
        }
        const prefixes = x64_decoder.decodeLegacyPrefixes(bytes);
        decoded.has_0x67 = prefixes.address_size_override;
        // F5 (throughput audit): resolve LOCK here, once, instead of in
        // `execute` on every instruction.
        //
        // `execute` used to re-read the byte at RIP through `guestMemoryConst`
        // — a full guest address translation, sparse probe included — purely to
        // test for 0xF0, on every interpreted instruction. The prefix scan
        // above already has the answer and the result is cached with the rest
        // of the decode.
        //
        // It is also more correct. The old test looked only at `bytes[0]`, so a
        // LOCK that followed a segment or operand-size override, or that sat
        // before a REX byte, was missed. `decodeLegacyPrefixes` walks the whole
        // prefix run. `or` rather than `=` because several decode paths already
        // set `lock` themselves.
        decoded.lock = decoded.lock or prefixes.lock;
        const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
        const base_register: ?RegId = if (decoded.sib_has_base) decoded.sib_base_reg else null;
        decoded.segment = x64_decoder.selectSegment(.explicit_data, base_register, prefixes.segment_override);
        const raw_displacement = decoded.addr;
        if (!hasRelativeControlDisplacement(decoded.op)) {
            decoded.addr = x64_decoder.resolveMemoryAddress(&self.regs, .{
                .displacement = raw_displacement,
                .has_index = decoded.sib_has_index,
                .index_reg = decoded.sib_index_reg,
                .scale = decoded.sib_scale,
                .has_base = decoded.sib_has_base,
                .base_reg = decoded.sib_base_reg,
                .rip_relative = decoded.rip_relative,
                .segment = decoded.segment,
            }, self.regs.rip +% decoded.len, address_size, .long64, decoded.op != .lea_reg_mem);
        }
        const instruction_byte_count: u8 = @intCast(@min(
            @as(usize, @max(decoded.len, 1)),
            @min(bytes.len, @as(usize, 15)),
        ));
        entry.* = .{
            .rip = fetch_address,
            .code_generation = self.code_generation,
            .decoded = decoded,
            .displacement = raw_displacement,
            .instruction_byte_count = instruction_byte_count,
            // The fast path is only sound for a fill that ran the validation
            // gate chain and saw it decline. `gates_free` already means the
            // special-RIP chain declined and the address was executable; the
            // config-parsing clause is monotone (it only ever turns off), and
            // the special-RIP table, once built, never changes — so the extra
            // guards below are belt-and-suspenders that keep startup and the
            // failed-table fallback on the slow path without needing to
            // reason about either invariant.
            .fast_plain = gates_free and
                !self.config_parsing_active and
                !self.special_rip_table_failed,
            // Computed here, once per fill, so the execution-history filter can
            // classify this instruction with one load on later hits instead of
            // re-running the range compare on every step.
            .host_image = fetch_address >= self.executable_min and
                fetch_address < self.executable_max,
        };
        // F4: this page now holds a cached decode, so a later store into it has
        // to run the invalidation walk. Noted for the instruction's whole
        // extent, because a store to its last byte must still find it.
        noteDecodeCacheUse(ways, entry);
        self.decode_cache_pages.note(fetch_address);
        self.decode_cache_pages.note(fetch_address +| (@as(u64, instruction_byte_count) -| 1));
        @memcpy(
            entry.instruction_bytes[0..instruction_byte_count],
            bytes[0..instruction_byte_count],
        );
        return decoded;
    }

    /// F1 (throughput audit): terminal decode diagnostics, held off the fetch
    /// path.
    ///
    /// Both bodies below run at most once per process — they end the run — and
    /// both were inlined into `step`, where they accounted for roughly half of
    /// its 18.7 KB and shared cache lines with the fetch/dispatch sequence that
    /// runs every instruction. Same reporting, same exit codes, same order;
    /// only the address changed. Returns `step`'s return value directly so the
    /// call sites stay one-liners.
    noinline fn reportDecodeFailure(self: *MachOState) bool {
        if (self.terminated) return false;
        const rip = self.regs.rip;
        machoCapturePrint("macho-processor: decode failed at rip=0x{x}\n", .{rip});
        if (self.sparse_memory.containsMapped(rip, 1)) {
            const bytes = self.executableInstructionBytesAt(rip) orelse
                self.sparse_memory.bytesConst(rip, 1) orelse &.{};
            machoCapturePrint(
                "macho-processor: decode failed in sparse generated-code mapping: mapped=true executable={} readable={} bytes={any}; this is not an unmapped Mach-O address\n",
                .{
                    self.sparse_memory.isExecutable(rip, 1),
                    self.sparse_memory.bytesConst(rip, 1) != null,
                    bytes,
                },
            );
        } else if (self.fileOffsetForVaddr(rip)) |file_off| {
            const remaining = if (file_off < self.data.len) self.data.len - file_off else 0;
            const file_bytes = self.data[file_off..][0..@min(@as(usize, 16), remaining)];
            machoCapturePrint("macho-processor: decode failed file_offset=0x{x} bytes={any}\n", .{ file_off, file_bytes });
        } else {
            machoCapturePrint("macho-processor: decode failed at unmapped address\n", .{});
        }
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.decode_failed);
        self.terminated = true;
        return false;
    }

    /// Operator-requested per-instruction trace for an explicit RIP window.
    /// Inert unless `trace_range_start` was set, so its formatting has no
    /// business sharing cache lines with the dispatch sequence.
    noinline fn emitTargetTrace(self: *MachOState, decoded: DecodedInsn) void {
        const mem_off = self.addrToOffset(self.regs.rip) orelse 0;
        const trace_bytes = self.mem[mem_off..][0..@min(@as(usize, 16), self.mem.len - mem_off)];
        const trace_key = self.regs.rip;
        const op_key = @intFromEnum(decoded.op);
        if (trace_key == self.last_trace_rip and op_key == self.last_trace_op) {
            self.trace_repeat_count +|= 1;
            return;
        }
        if (self.trace_repeat_count > 0) {
            log.info("target-trace: previous trace repeated {d} times", .{self.trace_repeat_count + 1});
        }
        self.last_trace_rip = trace_key;
        self.last_trace_op = op_key;
        self.trace_repeat_count = 0;
        log.info("target-trace: rip=0x{x} op={s} len={d} bytes={any} rsp=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x}", .{
            self.regs.rip,
            @tagName(decoded.op),
            decoded.len,
            trace_bytes,
            self.regs.rsp,
            self.regs.rax,
            self.regs.rcx,
            self.regs.rdx,
        });
    }

    /// Fires once, on the 24th recorded bootstrap instruction.
    noinline fn reportCoopBootstrapComplete(self: *MachOState) void {
        self.coop_bootstrap_active = false;
        const first = &self.coop_bootstrap_entries[0];
        const last = &self.coop_bootstrap_entries[23];
        const symbol = self.metadata.nearestSymbol(first.rip);
        machoCapturePrint(
            "macho-processor: GTK worker bootstrapping successful: thread=0x{x} first_rip=0x{x} last_rip=0x{x} first_symbol={s}\n",
            .{
                first.thread,                            first.rip, last.rip,
                if (symbol) |s| s.name else "<unknown>",
            },
        );
    }

    /// RIP is not an executable instruction target: either a recoverable
    /// generated-dispatch miss, or the end of the run.
    ///
    /// Held off the fetch path for the same reason as the two reporters below
    /// it. The recovery attempt lives here too rather than at the call site,
    /// because it is reached only through this same failed predicate — one
    /// `bl` on a path taken once per process, against a branch that `step`
    /// evaluates on every instruction.
    noinline fn recoverNonExecutableRip(self: *MachOState) bool {
        if (self.pending_control_transfer) |context| {
            // Generated code dispatching to an unpatched Xenia indirection
            // sentinel (a guest-module address) is the same recoverable
            // code-cache miss as a null function pointer: skip the
            // transfer and keep the run alive. The target poll below runs
            // only at this terminal raise site, never on the hot path.
            // Only recover when the failed RIP is exactly the transfer
            // target: a stale pending context (from an earlier transfer
            // that was never consulted) must not hijack an unrelated
            // non-executable RIP.
            if (context.target_address == self.regs.rip and
                memory_access.tryRecoverGeneratedGuestDispatchMiss(self, context, context.return_address != 0))
            {
                return true;
            }
            memory_access.dumpGuestDispatchTargetPoll(self, self.regs.rip);
            memory_access.logNonExecutableTarget(self, self.regs.rip, context);
            self.terminateForInvalidControlTransfer(context);
            self.dumpRecentTrace();
            return false;
        }
        memory_access.dumpGuestDispatchTargetPoll(self, self.regs.rip);
        memory_access.logNonExecutableTarget(self, self.regs.rip, null);
        machoCapturePrint(
            "macho-processor: invalid control-flow target rip=0x{x}; address is not an executable instruction target\n",
            .{self.regs.rip},
        );
        self.dumpRecentTrace();
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
        self.terminated = true;
        return false;
    }

    noinline fn reportInvalidInstruction(self: *MachOState) bool {
        const mem_bytes = self.executableInstructionBytesAt(self.regs.rip) orelse &.{};
        const rip = self.regs.rip;
        if (self.addrToOffset(rip)) |mem_off| {
            machoCapturePrint("macho-processor: invalid instruction at rip=0x{x}, mem_off=0x{x}, bytes: {any}\n", .{ rip, mem_off, mem_bytes });
        } else if (self.sparse_memory.containsMapped(rip, 1)) {
            machoCapturePrint("macho-processor: invalid instruction in sparse generated code at rip=0x{x}, bytes: {any}\n", .{ rip, mem_bytes });
        } else {
            machoCapturePrint("macho-processor: invalid instruction at unmapped rip=0x{x}, bytes: {any}\n", .{ rip, mem_bytes });
        }
        if (x64_decoder.capabilities.classifyRequirement(mem_bytes)) |requirement| {
            machoCapturePrint(
                "macho-processor: ISA requirement: {s} encoding requires {s}; virtual profile={s}, advertised={}\n",
                .{
                    @tagName(requirement.encoding),
                    x64_decoder.capabilities.featureLabel(requirement.feature),
                    self.cpu_profile.label(),
                    x64_decoder.capabilities.supports(self.cpu_profile, requirement.feature),
                },
            );
        }
        if (self.fileOffsetForVaddr(rip)) |file_off| {
            const remaining = if (file_off < self.data.len) self.data.len - file_off else 0;
            const file_bytes = self.data[file_off..][0..@min(@as(usize, 16), remaining)];
            machoCapturePrint("macho-processor: invalid instruction source-map: rip=0x{x} file_off=0x{x} file_bytes={any}\n", .{ rip, file_off, file_bytes });
        } else {
            machoCapturePrint("macho-processor: invalid instruction source-map: rip=0x{x} file_off=<unmapped>\n", .{rip});
        }
        self.dumpStepTraceBuffer();
        self.dumpCoopBootstrapTrace();
        self.dumpMemInitTrace();
        self.dumpCoopHeartbeatTrace();
        self.dumpUiHandoffTrace();
        self.dumpRecentTrace();
        if (self.deliverGuestSignal(GUEST_SIGILL, self.regs.rip, 1, self.regs.rip, null, 0, mem_bytes)) {
            return true;
        }
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_instruction);
        self.terminated = true;
        return false;
    }

    fn observeApplicationControlTransfer(self: *MachOState, decoded: DecodedInsn, source: u64) void {
        if (!self.application_framework.controlFlowTracingEnabled()) return;
        if (!isApplicationControlFlow(decoded.op)) return;

        const fallthrough = source +% decoded.len;
        const target = self.regs.rip;
        self.application_framework.observeControlTransfer(
            .guest,
            source,
            target,
            self.executed_steps,
            self.active_guest_thread,
            !self.terminated and target != fallthrough,
            @tagName(decoded.op),
        );
    }

    pub fn step(self: *MachOState) bool {
        if (@import("builtin").mode != .ReleaseFast) self.observeProfileAccountFlow();
        if (self.regs.rip == GUEST_ATEXIT_RETURN_SENTINEL) {
            return self.continueGuestExit();
        }
        if (self.regs.rip == GUEST_SIGNAL_RETURN_SENTINEL) {
            return self.finishGuestSignalReturn() and !self.terminated;
        }
        if (self.regs.rip == GUEST_THREAD_RETURN_SENTINEL) {
            self.finishActiveGuestThread();
            return !self.terminated;
        }
        // R2 (N3): the 9 special-RIP handlers below used to run (and pay
        // ~65 compares + a function call) on every instruction even when all
        // inert. specialRipPossible is one binary search over the
        // load-time-resolved table plus O(1) range/state probes; the chain
        // runs only when rip could actually match a target, with identical
        // short-circuit semantics.
        //
        // F18 (throughput audit): the chain and the executability probe are
        // still recomputed per instruction even when every fact they verify
        // is invariant for a given RIP. A decode-cache hit whose entry was
        // filled with the chain declined and the address verified executable
        // (`fast_plain`) makes both redundant: the entry survives only while
        // the bytes and permissions it was validated under still hold, and
        // every condition the chain tests is monotone after the fill. One
        // probe replaces the binary search, the range/state probes and the
        // sparse executability probe on the hot path; everything here still
        // runs on misses, on entries filled without the gates, during config
        // parsing, and whenever the special-RIP table fallback is active.
        self.pending_control_transfer = null;
        var decoded: DecodedInsn = undefined;
        var gates_free = false;
        if (self.decodeFastPlain()) |fast| {
            // The fast entry was validated (executable, not a special target)
            // at fill time and survives only while the bytes and permissions
            // it was validated under still hold. Its fill-time host-image
            // classification is exact for this RIP, so the execution-history
            // filter below reads one field instead of re-running the range
            // compare on every step.
            self.step_host_image = fast.host_image;
            decoded = fast.decoded;
        } else {
            gates_free = !self.specialRipPossible();
            if (!gates_free) {
                if (self.handleInternalCompatibility()) return !self.terminated;
                if (self.handleTlvBootstrap()) return !self.terminated;
                if (self.handleBoundImportThunk()) return !self.terminated;
                if (self.handleSyntheticRuntimeThunk()) return !self.terminated;
                if (self.handleDynamicLibraryThunk()) return !self.terminated;
                if (self.handleStubHelperTransition()) {
                    return !self.terminated;
                }
                self.handleTomlReadNextIntegrity();
                if (self.handleTomlAsciiFastPath()) return !self.terminated;
                if (self.handlePatchDbEmptyPatchArray()) return !self.terminated;
            }
            if (!self.isExecutableAddress(self.regs.rip)) return self.recoverNonExecutableRip();
            self.step_host_image = self.regs.rip >= self.executable_min and
                self.regs.rip < self.executable_max;
            decoded = self.decodeWithLiveOperands(gates_free) orelse return self.reportDecodeFailure();
        }
        if (decoded.op == .invalid) return self.reportInvalidInstruction();
        // Instruction history, gated behaviourally rather than by a flag.
        //
        // The predecessor of this line was `if (self.trace_ring_enabled)`, and
        // `trace_ring_enabled` was never assigned anywhere in the tree — so the
        // ring was empty for the entire life of the code and every recognizer
        // built on it reported "no retained evidence", which reads as a fact
        // about the guest and was a fact about an unset boolean.
        //
        // Generated code is the only region these recognizers ask about, and it
        // is a small fraction of executed steps (Xenia's own JIT compiler
        // dominates), so recording exactly there makes the tape both affordable
        // and deep where it is consulted. The host/generated split is classified
        // upstream (`step_host_image`) — from the decode entry on the fast path
        // and the range compare on the slow path — so this block does one load,
        // no page lookup.
        switch (self.execution_history.policy) {
            .disabled => {},
            .all => {
                self.execution_history_filter_active = false;
                self.recordTrace(decoded);
            },
            .generated_code_only => {
                // Classified upstream: the decode-cache fast path read the
                // entry's fill-time classification, the slow path computed the
                // same range compare this block used to run. One load replaces
                // the two range compares per step.
                if (self.step_host_image) {
                    // One increment per contiguous omitted native interval,
                    // not per instruction. Besides keeping the counter stable,
                    // this makes the hot host-code path a predictable branch.
                    if (!self.execution_history_filter_active) {
                        self.execution_history_epoch +|= 1;
                        self.execution_history_filter_active = true;
                    }
                    self.execution_history.noteFiltered();
                } else {
                    self.execution_history_filter_active = false;
                    self.recordTrace(decoded);
                    self.seedProvenanceWatch(decoded);
                    self.noteGuestFieldAccess(decoded);
                }
            },
        }
        if (self.coop_bootstrap_active and self.coop_bootstrap_index < 24) {
            const idx = self.coop_bootstrap_index;
            self.coop_bootstrap_entries[idx] = .{
                .rip = self.regs.rip,
                .thread = self.active_guest_thread,
                .op = @intFromEnum(decoded.op),
                .len = decoded.len,
            };
            self.coop_bootstrap_index = idx + 1;
            if (self.coop_bootstrap_index == 24) self.reportCoopBootstrapComplete();
        }
        // F19 (throughput audit): these gates are diagnostics that are off in
        // the steady state — the verbose trace and the SHA1 tracer are
        // env-gated off by default and the trace range is unset unless set by
        // hand — and each used to pay a load and a branch per instruction just
        // to be asked. `step_tracing_active` is computed once at startup from
        // the three immutable switches, so the cluster below costs one load
        // and one not-taken branch on the hot path; each gate still
        // self-checks inside so the aggregate can never over-fire.
        if (self.step_tracing_active) {
            if (self.verbose_trace) log.debug("rip=0x{x} op={s} len={d}", .{ self.regs.rip, @tagName(decoded.op), decoded.len });
            // Observe the resolved function entry itself rather than relying
            // on the preceding call target. Lazy-import stubs may transfer
            // here via a jump after Rosette has already handled the original
            // call.
            if (self.sha1_tracer.enabled and
                !self.sha1_tracer.active and
                self.internal_targets.sha1_process_bytes != 0 and
                self.regs.rip == self.internal_targets.sha1_process_bytes)
            {
                self.sha1_tracer.onProcessBytesEntry(self);
            }
            if (self.shouldTraceRIP(self.regs.rip)) self.emitTargetTrace(decoded);
        }
        const old_rip = self.regs.rip;
        x64_interpreter.execute(self, decoded);
        if (!self.terminated and self.regs.rip == old_rip) {
            self.regs.rip +%= decoded.len;
        }
        self.observeApplicationControlTransfer(decoded, old_rip);
        if (!self.terminated and
            self.step_tracing_active and
            self.sha1_tracer.enabled and
            self.sha1_tracer.isActiveThread(self))
        {
            self.sha1_tracer.instruction_count += 1;
            if (self.sha1_tracer.instruction_count == Sha1Tracer.HOT_THRESHOLD and !self.sha1_tracer.initial_report_done) {
                self.sha1_tracer.hot_function_rip = self.sha1_tracer.entry_rip;
                self.sha1_tracer.detected_at_step = self.executed_steps;
                self.sha1_tracer.initial_report_done = true;
            }
            if (self.sha1_tracer.initial_report_done and self.sha1_tracer.depth == 0) {
                self.sha1_tracer.progress_log_counter += 1;
                if (self.sha1_tracer.progress_log_counter >= Sha1Tracer.PROGRESS_LOG_INTERVAL) {
                    self.sha1_tracer.progress_log_counter = 0;
                    self.sha1_tracer.logSha1Progress(self);
                }
            }
        }
        return !self.terminated;
    }

    pub fn beginCooperativeMainLoop(self: *MachOState) bool {
        return scheduling.beginCooperativeMainLoop(self);
    }

    pub fn startDeferredGuestThread(self: *MachOState, deferred: pthread_runtime.DeferredThread) bool {
        return scheduling.startDeferredGuestThread(self, deferred);
    }

    pub fn saveActiveGuestThread(self: *MachOState, reason: []const u8) bool {
        return scheduling.saveActiveGuestThread(self, reason);
    }

    // Suspended workers are a FIFO queue.  A LIFO pop would immediately resume
    // the same worker that just yielded once all deferred threads had started.
    pub fn resumeSuspendedGuestThread(self: *MachOState) bool {
        return scheduling.resumeSuspendedGuestThread(self);
    }

    pub fn yieldActiveGuestThreadForWait(self: *MachOState, reason: []const u8) bool {
        return scheduling.yieldActiveGuestThreadForWait(self, reason);
    }

    // cooperative idle scheduling is a wake-up, not merely queue bookkeeping. Dispatch
    // newly queued UI work at the first safe interpreter boundary even after
    // every pthread worker has started. This is the path used by Xenia's
    // CallInUIThread presenter creation handoff.
    //
    // Guest startup code may also wait by spinning on atomics before it reaches
    // a pthread or libc++ condition-variable call. Give not-yet-started workers
    // a bounded execution slice so one spinner cannot starve their producers.
    pub fn maybeYieldActiveGuestThreadForQuantum(self: *MachOState) void {
        scheduling.maybeYieldActiveGuestThreadForQuantum(self);
    }

    pub fn refreshSuspendedRunnableCache(self: *MachOState) usize {
        return scheduling.refreshSuspendedRunnableCache(self);
    }

    pub noinline fn finishActiveGuestThread(self: *MachOState) void {
        scheduling.finishActiveGuestThread(self);
    }

    /// Queue a GTK signal handler (more than one argument, unlike a
    /// `GSourceFunc`). Used by the modelled `gtk_widget_queue_draw`.
    pub fn scheduleSignalCallback(self: *MachOState, function: u64, arg0: u64, arg1: u64, arg2: u64, tag: []const u8) u64 {
        return scheduling.scheduleSignalCallback(self, function, arg0, arg1, arg2, tag);
    }

    pub fn scheduleIdleCallback(self: *MachOState, function: u64, data: u64, tag: []const u8) u64 {
        return scheduling.scheduleIdleCallback(self, function, data, tag);
    }

    pub fn isIdleCallbackPending(self: *const MachOState, source: u64) bool {
        return scheduling.isIdleCallbackPending(self, source);
    }

    pub fn pendingIdleCallbackCount(self: *const MachOState) usize {
        return scheduling.pendingIdleCallbackCount(self);
    }

    pub fn gtkIdleQueueSnapshot(self: *const MachOState) IdleQueueSnapshot {
        return scheduling.idleQueueSnapshot(self);
    }

    pub fn gtkIdleDispatchBlock(self: *const MachOState) IdleDispatchBlock {
        return scheduling.idleDispatchBlock(self);
    }

    pub fn removeIdleSource(self: *MachOState, source: u64) bool {
        return scheduling.removeIdleSource(self, source);
    }

    pub fn startNextIdleCallback(self: *MachOState, reason: []const u8, active_already_saved: bool) bool {
        return scheduling.startNextIdleCallback(self, reason, active_already_saved);
    }

    pub fn isSyntheticCallbackHandle(self: *const MachOState, handle: u64) bool {
        return scheduling.isSyntheticCallbackHandle(self, handle);
    }

    // GTK idle sources and SDL audio callbacks share one stack — the
    // cooperative UI context's. Entering a second one while the first is only
    // suspended writes over its live frames.
    pub fn syntheticCallbackStackBusy(self: *const MachOState) bool {
        return scheduling.syntheticCallbackStackBusy(self);
    }

    pub fn syntheticCallbackStackOwner(self: *const MachOState) u64 {
        return scheduling.syntheticCallbackStackOwner(self);
    }

    pub fn noteSyntheticStackEntry(self: *MachOState, handle: u64) void {
        scheduling.noteSyntheticStackEntry(self, handle);
    }

    pub fn isIdleCallbackHandle(self: *const MachOState, handle: u64) bool {
        return scheduling.isIdleCallbackHandle(self, handle);
    }

    pub fn currentCooperativeThreadHandle(self: *const MachOState) u64 {
        if (self.active_guest_thread == 0 or self.isIdleCallbackHandle(self.active_guest_thread)) {
            return self.pthreads.main_thread_handle;
        }
        return self.active_guest_thread;
    }

    pub fn threadNumericId(self: *const MachOState, handle: u64) u64 {
        return scheduling.threadNumericId(self, handle);
    }

    pub fn threadRole(self: *const MachOState, handle: u64, address: u64) []const u8 {
        return scheduling.threadRole(self, handle, address);
    }

    pub fn contextContainsHandle(self: *const MachOState, handle: u64) bool {
        return scheduling.contextContainsHandle(self, handle);
    }

    pub fn logAudioCallbackSchedulerState(self: *const MachOState) void {
        scheduling.logAudioCallbackSchedulerState(self);
    }

    pub fn runnableSuspendedSnapshot(self: *const MachOState) RunnableSuspendedSnapshot {
        return scheduling.runnableSuspendedSnapshot(self);
    }

    pub fn logThreadTable(self: *const MachOState, reason: []const u8) void {
        scheduling.logThreadTable(self, reason);
    }

    pub fn restoreMainLoopCaller(self: *MachOState, reason: []const u8) void {
        scheduling.restoreMainLoopCaller(self, reason);
    }

    pub fn logCooperativeSchedulerSummary(self: *const MachOState) void {
        scheduling.logCooperativeSchedulerSummary(self);
    }

    pub fn logCooperativeHeartbeat(self: *MachOState) void {
        scheduling.logCooperativeHeartbeat(self);
    }

    pub fn dumpCoopHeartbeatTrace(self: *const MachOState) void {
        scheduling.dumpCoopHeartbeatTrace(self);
    }

    pub fn dumpUiHandoffTrace(self: *const MachOState) void {
        scheduling.dumpUiHandoffTrace(self);
    }

    // Once the Xenia PageEntry tables have been allocated, setup can spend a
    // long time in memory-manager code without crossing another import
    // boundary. Keep a compact, high-frequency checkpoint so a stalled
    // backing-map or heap pass is observable in the next external run.
    fn logMemoryInitializationProgress(self: *MachOState, steps: u64) void {
        scheduling.logMemoryInitializationProgress(self, steps);
    }

    pub noinline fn handleSyntheticRuntimeThunk(self: *MachOState) bool {
        return thunk_handler.handleSyntheticRuntimeThunk(self);
    }

    pub noinline fn handleTlvBootstrap(self: *MachOState) bool {
        return thunk_handler.handleTlvBootstrap(self);
    }

    pub noinline fn handleBoundImportThunk(self: *MachOState) bool {
        return thunk_handler.handleBoundImportThunk(self);
    }

    pub noinline fn handleDynamicLibraryThunk(self: *MachOState) bool {
        return thunk_handler.handleDynamicLibraryThunk(self);
    }

    // F1 (throughput audit): the three periodic report bodies below used to be
    // inlined directly into `run`'s loop body. Each fires once per 500K, 100M
    // or 250M steps; together they compiled to ~96 KB of the loop's 99 KB, and
    // that code shares instruction-cache lines with the ~60 instructions that
    // actually run every step. The interpreter's hot closure measured 189 KB
    // against a 128-192 KB L1I, so the loop could not stay resident.
    //
    // `noinline` is load-bearing, not a hint: LLVM inlines these back into the
    // single call site without it, which is exactly how they got here. The
    // bodies are unchanged; only their address is.
    noinline fn reportProgressCheckpoint(self: *MachOState, steps: u64) void {
        // Attribute the readiness gate's quiet window at this cadence rather
        // than at the heartbeat. A whole run only produces a handful of
        // heartbeats, and a handful of samples cannot tell a loop from forward
        // motion; the sample itself is O(1), so the finer rate is affordable.
        self.ready.noteExecutionSample(steps, self.regs.rip, self.active_guest_thread);
        // The symbol axis saturates against an emulator. Rosette resolves
        // *host* symbols, so a guest that JITs its own guest forever revisits
        // the same few translator functions: the axis goes quiet while the
        // work it measures is at full speed. These counters do not saturate,
        // because each advance is a request this process actually serviced.
        //
        // The failing run made the case: the gate declared no progress at step
        // 900M while guest heap allocations were still climbing by tens of
        // megabytes per hundred million steps.
        self.ready.noteExternalProgress(.{
            .heap_high_water = self.heap_next,
            .heap_live = self.memory_forwarder.summary().live_allocations,
            .threads_created = self.pthreads.created_threads,
        }, steps);
        const symbol = self.metadata.nearestSymbol(self.regs.rip);
        // The gate's blind spots are the stretches where Xenia logs nothing:
        // the per-title config and XDBF block above the shader-storage
        // request runs for hundreds of millions of instructions in silence,
        // and used to end the run with the graphics owner blamed for work that
        // had not been reached yet. The instruction pointer was never silent —
        // it was only unnamed, and the symbol above already resolved it. The
        // route package turns that symbol into a subsystem for free, because
        // the mapping is fixed when Xenia is compiled.
        if (symbol) |resolved| {
            const direct = ready_compiler.xenia.launchPhaseFor(resolved.name);
            const attribution = if (direct) |candidate| blk: {
                // A generic carrier has no owner of its own. During the one
                // source-ordered silent CompleteLaunch interval, the package
                // can safely use the current frontier to recover that owner.
                if (candidate.carrier) {
                    break :blk ready_compiler.xenia.launchPhaseFallback(
                        self.ready.frontierStageName(),
                        resolved.name,
                    ) orelse candidate;
                }
                break :blk candidate;
            } else ready_compiler.xenia.launchPhaseFallback(
                self.ready.frontierStageName(),
                resolved.name,
            );
            if (attribution) |attribution_value| {
                _ = self.ready.noteAttributedSite(
                    .{
                        .phase_id = @intFromEnum(attribution_value.phase),
                        .label = attribution_value.label,
                        .owner = attribution_value.owner,
                        .after_stage = ready_compiler.xenia.launchPhaseAfterStage(attribution_value.phase),
                        // Whose code is running and whose progress it proves
                        // are different questions once the guest is executing:
                        // Xenia's translator runs because the title reached
                        // new code, so the blocked owner is reachable through
                        // the emulator's own symbols.
                        .proxy_owner = ready_compiler.xenia.launchPhaseProxyOwner(attribution_value.phase),
                        .proxy_after_stage = ready_compiler.xenia.launchPhaseProxyAfterStage(attribution_value.phase),
                        .carrier = attribution_value.carrier,
                    },
                    resolved.name,
                    steps,
                    self.regs.rip,
                    self.active_guest_thread,
                );
            }
        }
        const heap_summary = self.memory_forwarder.summary();
        const snapshot: startup_observer.Snapshot = .{
            .step = steps,
            .rip = self.regs.rip,
            .symbol = if (symbol) |resolved| resolved.name else "<unknown>",
            .symbol_offset = if (symbol) |resolved| resolved.offset else 0,
            .heap_next = self.heap_next,
            .import_calls = self.import_resolver.total_calls,
            .fs_open = self.fs_forwarder.open_count,
            .fs_read = self.fs_forwarder.read_count,
            .fs_write = self.fs_forwarder.write_count,
            .heap_allocations = heap_summary.allocations,
            .heap_live = heap_summary.live_allocations,
            .options_seen = self.launch_options.registrations_seen,
            .options_kept = self.launch_options.registrations_kept,
            .options_skipped = self.launch_options.registrations_skipped,
            .logging_lines = self.logging.emitted_lines,
            .pthread_created = self.pthreads.created_threads,
            .pthread_waits_collapsed = self.pthreads.collapsed_waits,
            .diagnostic_text_runs = self.diagnostic_text.accelerations,
            .diagnostic_text_lines = self.diagnostic_text.lines_retained,
            .pthread_blocked = self.pthreads.blocked_threads,
            .thread_id = self.active_guest_thread,
        };
        if (self.startup.enabled) {
            self.startup.checkpoint(snapshot);
        } else {
            // Feed the native crash handler: if the emulator's own host code
            // faults a moment from now, the crash report says exactly where the
            // guest was (step, rip, thread, symbol) rather than "the run was
            // somewhere". The symbol is copied, not borrowed, because guest image
            // memory is exactly what may have faulted.
            native_crash.recordGuestProgress(
                steps,
                self.regs.rip,
                self.active_guest_thread,
                if (symbol) |resolved| resolved.name else "",
            );

            const entry = &self.step_trace_entries[self.step_trace_index];
            entry.step = steps;
            entry.rip = self.regs.rip;
            self.step_trace_index +|= 1;
            if (self.step_trace_index == 5) {
                self.step_trace_index = 0;
                self.step_trace_filled = true;
            }
        }
    }

    noinline fn reportHeartbeat(self: *MachOState, steps: u64) void {
        // Emitted here rather than only at exit: a run killed by the
        // harness timeout still has to say where the graphics frontier
        // stopped, and the exit path never runs in that case.
        self.logGraphicsFrontier(false);
        const hb_symbol = self.metadata.nearestSymbol(self.regs.rip);
        native_crash.recordGuestProgress(
            steps,
            self.regs.rip,
            self.active_guest_thread,
            if (hb_symbol) |resolved| resolved.name else "",
        );
        const heartbeat_snapshot: startup_observer.Snapshot = .{
            .step = steps,
            .rip = self.regs.rip,
            .symbol = if (hb_symbol) |resolved| resolved.name else "<unknown>",
            .symbol_offset = if (hb_symbol) |resolved| resolved.offset else 0,
            .heap_next = self.heap_next,
            .import_calls = self.import_resolver.total_calls,
            .fs_open = self.fs_forwarder.open_count,
            .fs_read = self.fs_forwarder.read_count,
            .fs_write = self.fs_forwarder.write_count,
            .heap_allocations = 0,
            .heap_live = 0,
            .options_seen = self.launch_options.registrations_seen,
            .options_kept = self.launch_options.registrations_kept,
            .options_skipped = self.launch_options.registrations_skipped,
            .logging_lines = self.logging.emitted_lines,
            .pthread_created = self.pthreads.created_threads,
            .pthread_waits_collapsed = self.pthreads.collapsed_waits,
            .pthread_blocked = self.pthreads.blocked_threads,
            .thread_id = self.active_guest_thread,
            .execution_fingerprint = self.executionFingerprint(),
        };
        self.startup.heartbeat(heartbeat_snapshot);
        self.logPerformanceHeartbeat();
        self.emitRuntimeSummaryHeartbeat(heartbeat_snapshot);
        if (self.startup.takeStallDiagnostic()) self.logStalledInstructionDetails();
        self.pthreads.diagnoseStuck(steps, self.regs.rip, self.guest_time.now());
        self.pumpNativeWindowEvents();
        self.logCooperativeHeartbeat();
        self.pthreads.profileThreadStates(&self.wait_profiler, steps, self.guest_time.now());
        if (hb_symbol) |resolved| {
            if (std.mem.indexOf(u8, resolved.name, "CommitExecutableRange") != null) {
                self.jit_commit_count +|= 1;
                self.jit_log.emit(.{
                    .kind = .code_cache_allocated,
                    .step = steps,
                    .guest_addr = @intCast(self.regs.rip & 0xFFFFFFFF),
                    .host_addr = self.regs.rip,
                    .size = 4096,
                    .total_functions = @intCast(self.import_resolver.total_calls),
                    .unique_ordinals = @intCast(self.import_resolver.total_calls),
                    .call_count = self.jit_commit_count,
                    .thread_id = self.active_guest_thread,
                    .reason = "commit",
                });
            }
            if (std.mem.indexOf(u8, resolved.name, "GetProcAddressByOrdinal") != null) {
                self.jit_export_count +|= 1;
                if (self.jit_export_count % 100 == 0) {
                    self.macho_log.emit(.{
                        .kind = .import_resolution,
                        .step = steps,
                        .thread_id = self.active_guest_thread,
                        .import_calls = self.import_resolver.total_calls,
                        .reason = "GetProcAddressByOrdinal",
                    });
                }
                if (self.jit_export_count % 10 == 0) {
                    self.jit_log.emit(.{
                        .kind = .host_to_guest_call,
                        .step = steps,
                        .guest_addr = @intCast(self.regs.rip & 0xFFFFFFFF),
                        .call_count = self.jit_export_count,
                        .total_functions = @intCast(self.import_resolver.total_calls),
                        .unique_ordinals = @intCast(self.import_resolver.total_calls),
                        .thread_id = self.active_guest_thread,
                        .reason = "export_resolution",
                    });
                }
            }
        }
        self.jit_log.emit(.{
            .kind = .monitor_snapshot,
            .step = steps,
            .total_functions = @intCast(self.import_resolver.total_calls),
            .unique_ordinals = @intCast(self.import_resolver.total_calls),
            .code_cache_bytes = @intCast(self.memory_forwarder.summary().allocations *| 4096),
            .call_count = self.jit_commit_count,
            .thread_id = self.active_guest_thread,
            .reason = "heartbeat",
        });
        self.macho_log.emit(.{
            .kind = .heartbeat,
            .step = steps,
            .thread_id = self.active_guest_thread,
            .guest_addr = self.regs.rip,
            .runnable = @intCast(self.pthreads.activeCount()),
            .blocked = @intCast(self.pthreads.blocked_threads),
            .condvar_waits = self.pthreads.collapsed_waits,
            .import_calls = self.import_resolver.total_calls,
            .reason = "heartbeat",
            .symbol = if (hb_symbol) |resolved| resolved.name else "",
        });
        self.pollReadyCompiler(steps);
    }

    /// Try to find real queued work for a parked cooperative context, and
    /// terminate with a precise invariant failure if there is none.
    ///
    /// Returns false when the caller must stop; the register file after the
    /// scheduler has parked its owner is the last saved context, not executable
    /// work, and interpreting it would manufacture millions of meaningless
    /// steps rather than reporting the deadlock.
    noinline fn recoverZeroActiveGuestThread(self: *MachOState) bool {
        const started_idle = self.pendingIdleCallbackCount() != 0 and
            self.startNextIdleCallback("zero-active run guard", true);
        if (started_idle) return true;

        // A failed context publication must not strand a newly-created
        // runnable worker merely because the deferred counter was already
        // decremented. `takeNewestDeferred` also scans the table directly, so
        // this repairs a stale counter as well as the ordinary deferred path.
        if (self.pthreads.takeNewestDeferred()) |next| {
            if (self.startDeferredGuestThread(next)) return true;
            self.pthreads.requeueDeferred(next.handle);
        }
        if (self.resumeSuspendedGuestThread()) return true;

        self.logThreadTable("zero-active run guard");
        var orphaned_runnable: u32 = 0;
        for (0..self.pthreads.tableCapacity()) |slot| {
            const snapshot = self.pthreads.snapshotAt(slot) orelse continue;
            if (snapshot.state != .runnable or self.contextContainsHandle(snapshot.handle)) continue;
            orphaned_runnable += 1;
            machoCapturePrint(
                "macho-processor: scheduler orphaned runnable thread: handle=0x{x} numeric_id={d} started={} start=0x{x} no active or suspended context owns this runnable entry\n",
                .{ snapshot.handle, snapshot.numeric_id, snapshot.started, snapshot.start_routine },
            );
        }
        self.scheduler_log.emit(.{
            .kind = .deadlock,
            .step = self.executed_steps,
            .thread = 0,
            .runnable = self.pthreads.activeCount(),
            .blocked = self.pthreads.blocked_threads,
            .reason = "zero_active_guest_thread",
        });
        machoCapturePrint(
            "macho-processor: runtime invariant failure: no resumable guest context; refusing stale-register execution rip=0x{x} suspended={d} modeled_runnable={d} orphaned_runnable={d} deferred={d} blocked={d} pending_gtk={d}\n",
            .{ self.regs.rip, self.suspended_guest_thread_count, self.pthreads.activeCount(), orphaned_runnable, self.pthreads.deferred_threads, self.pthreads.blocked_threads, self.pendingIdleCallbackCount() },
        );
        self.faulted = true;
        self.exit_code = 125;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.runtime_invariant_failure);
        self.terminated = true;
        return false;
    }

    noinline fn reportConciseProgress(self: *MachOState, steps: u64) void {
        var progress_buffer: [256]u8 = undefined;
        const progress = std.fmt.bufPrint(
            &progress_buffer,
            "Translated instructions: {d} (activity only, not application progress; runnable={d} blocked={d} condvar_waits={d} quiescence_recoveries={d})\n",
            .{
                steps,
                self.pthreads.activeCount(),
                self.pthreads.blocked_threads,
                self.pthreads.collapsed_waits,
                self.cooperative_quiescence_recoveries,
            },
        ) catch "";
        _ = hostWriteFdAll(1, progress);
        self.scheduler_log.emit(.{
            .kind = .runnable_count,
            .step = steps,
            .thread = self.active_guest_thread,
            .runnable = self.pthreads.activeCount(),
            .blocked = self.pthreads.blocked_threads,
            .reason = "progress_checkpoint",
        });
    }

    pub fn run(self: *MachOState) void {
        native_crash.recordPhase("run");
        var steps: u64 = 0;
        // N5 (perf audit): replace the four per-instruction `steps % X`
        // modulo operations below with down-counters. Each counter decrements
        // once per iteration and fires (then resets) at exactly the step the
        // old modulo would have matched — including the step-0 heartbeat
        // (`0 % HEARTBEAT_INTERVAL == 0` fires on the first iteration) and
        // excluding 0 for the `steps != 0`-guarded reports. The concise
        // progress report instead uses a boundary comparison (steps >= next
        // boundary) so checkpoints land on exact multiples of
        // CONCISE_PROGRESS_INTERVAL — a decrement-then-fire counter would fire
        // at steps == N*interval - 1.
        var next_progress_report: u64 = PROGRESS_REPORT_INTERVAL;
        var next_heartbeat: u64 = 0;
        var next_concise_report: u64 = CONCISE_PROGRESS_INTERVAL;
        var next_memory_init_report: u64 = 1_000_000;
        machoCapturePrint(
            "macho-processor: CMPXCHG contract active — 0F B0 executes at byte width, flags use ACC-DEST, and assertion-triggered CAS repair paths are absent.\n",
            .{},
        );
        while (!self.terminated and stepBudgetAllows(self.max_steps, steps)) : (steps +|= 1) {
            self.executed_steps = steps;

            // Two comparisons and a bit test on the overwhelmingly common
            // path. This is what turns "no log line said VdSwap(" into "the
            // instruction pointer did or did not reach VdSwap".
            if (self.execution_tracepoints.mightMatch(self.regs.rip)) {
                self.noteExecutionTracepoint();
            }

            // Never interpret the register file after the cooperative
            // scheduler has parked its owner. A zero active handle means the
            // registers are merely the last saved context, not executable
            // work. Try real queued work once, then stop with a precise
            // invariant failure instead of manufacturing millions of steps.
            if (self.cooperative_ui_context != null and self.active_guest_thread == 0) {
                if (!self.recoverZeroActiveGuestThread()) break;
            }

            // Update scheduler step
            // self.thread_scheduler.updateStep(steps);

            // Update scheduler with current context
            // self.thread_scheduler.setUIContext(self.cooperative_ui_context != null);
            // self.thread_scheduler.updatePendingIdle(self.pendingIdleCallbackCount());
            // self.thread_scheduler.updateDeferredThreads(self.pthreads.deferred_threads);
            next_progress_report -|= 1;
            if (next_progress_report == 0) {
                next_progress_report = PROGRESS_REPORT_INTERVAL;
                self.reportProgressCheckpoint(steps);
                if (self.consumeHostTerminationRequest()) break;
            }
            next_heartbeat -|= 1;
            if (next_heartbeat == 0) {
                next_heartbeat = HEARTBEAT_INTERVAL;
                self.reportHeartbeat(steps);
            }
            if (self.concise_output and steps >= next_concise_report) {
                next_concise_report +%= CONCISE_PROGRESS_INTERVAL;
                self.reportConciseProgress(steps);
            }
            if (!self.step()) break;
            self.maybeYieldActiveGuestThreadForQuantum();
            next_memory_init_report -|= 1;
            if (self.page_entry_bulk_initializations != 0 and next_memory_init_report == 0) {
                next_memory_init_report = 1_000_000;
                self.logMemoryInitializationProgress(steps);
            }
        }
        self.finishRun(steps);
    }

    /// Everything `run` does after its loop ends: reason normalisation, exit
    /// diagnostics, and the two process-exit event records.
    ///
    /// F1 (throughput audit): runs exactly once per process, and was inlined
    /// into `run` alongside the loop body. Extracting it (with the three
    /// periodic reporters above) took `run` from 99,272 bytes to a loop that
    /// fits alongside the rest of the interpreter in L1I.
    noinline fn finishRun(self: *MachOState, steps: u64) void {
        if (self.mem_init_started and !self.faulted) {
            machoCapturePrint(
                "macho-processor: memory initialization completed: step={d} page_entry(runs/bytes)={d}/{d} heap=0x{x}\n",
                .{ steps, self.page_entry_bulk_initializations, self.page_entry_bulk_bytes, self.heap_next },
            );
            self.mem_init_started = false;
        }
        if (self.max_steps != 0 and steps >= self.max_steps) {
            log.warn("reached max steps ({d})", .{self.max_steps});
            self.faulted = true;
            self.exit_code = 124;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.max_steps_reached);
            self.terminated = true;
        }
        if (self.unresolved_import_count != 0) {
            const current_reason = exit_diagnostics.reasonFromValue(self.termination_reason);
            if (current_reason == .unknown or current_reason == .ret_stack_empty or current_reason == .exit_syscall) {
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
            }
        }
        const recorded_reason = exit_diagnostics.reasonFromValue(self.termination_reason);
        const inferred_reason = exit_diagnostics.inferReason(recorded_reason, .{
            .faulted = self.faulted,
            .memory_access_failure = self.terminal_memory_failure != null,
            .control_transfer_failure = self.terminal_control_transfer != null,
        });
        const normalized_reason = exit_diagnostics.normalizeReason(inferred_reason, self.unresolved_import_count);
        if (normalized_reason != recorded_reason) {
            machoCapturePrint(
                "macho-processor: diagnostics invariant repaired: reason={s} faulted={} reclassified={s}\n",
                .{ @tagName(recorded_reason), self.faulted, @tagName(normalized_reason) },
            );
            self.termination_reason = @intFromEnum(normalized_reason);
        }
        if (self.termination_reason == @intFromEnum(exit_diagnostics.TerminationReason.host_termination_signal)) {
            self.logHostTerminationSnapshot(steps);
        } else if (self.terminated and (self.exit_code != 0 or self.unresolved_import_count != 0)) {
            self.logExitDiagnostics();
        }
        self.jit_log.emit(.{
            .kind = .process_exit,
            .step = steps,
            .total_functions = @intCast(self.import_resolver.total_calls),
            .unique_ordinals = @intCast(self.import_resolver.total_calls),
            .code_cache_bytes = @intCast(self.memory_forwarder.summary().allocations *| 4096),
            .thread_id = self.active_guest_thread,
            .exit_code = @as(i32, @intCast(self.exit_code & 0xFFFFFFFF)),
            .reason = @tagName(recorded_reason),
        });
        self.macho_log.emit(.{
            .kind = .process_exit,
            .step = steps,
            .thread_id = self.active_guest_thread,
            .runnable = @intCast(self.pthreads.activeCount()),
            .blocked = @intCast(self.pthreads.blocked_threads),
            .condvar_waits = self.pthreads.collapsed_waits,
            .import_calls = self.import_resolver.total_calls,
            .exit_code = @as(i32, @intCast(self.exit_code & 0xFFFFFFFF)),
            .reason = @tagName(recorded_reason),
        });
    }

    /// Converts the async-signal-safe host request into normal interpreter
    /// state. Called only at existing 500K-step checkpoints, avoiding another
    /// load/branch in the per-instruction hot path.
    pub fn consumeHostTerminationRequest(self: *MachOState) bool {
        const request = host_termination.take() orelse return false;
        const supervisor = host_termination.supervisorContext();
        self.host_termination_signal = request.number;
        self.exit_code = request.exitCode();
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.host_termination_signal);
        self.terminated = true;
        self.faulted = false;
        machoCapturePrint(
            "macho-processor: HOST TERMINATION REQUEST signal={d}({s}) owner={s} configured_timeout_seconds={d} step={d} rip=0x{x}; guest execution was live and no decoder, memory, control-flow, or GPU fault caused this stop\n",
            .{
                request.number,
                request.name(),
                if (supervisor.name.len != 0) supervisor.name else "unidentified host/user",
                supervisor.timeout_seconds,
                self.executed_steps,
                self.regs.rip,
            },
        );
        return true;
    }

    noinline fn logHostTerminationSnapshot(self: *MachOState, steps: u64) void {
        const request = host_termination.Request{ .number = self.host_termination_signal };
        const supervisor = host_termination.supervisorContext();
        machoCapturePrint(
            "macho-processor: HOST TERMINATION SNAPSHOT signal={d}({s}) owner={s} configured_timeout_seconds={d} step={d} phase={s} rip=0x{x} active_thread=0x{x} blocked_threads={d} suspended_contexts={d} faulted={} terminal_memory_failure={} terminal_control_transfer={}; classification=INTENTIONAL_OR_EXTERNAL_STOP_NOT_CRASH\n",
            .{
                request.number,
                request.name(),
                if (supervisor.name.len != 0) supervisor.name else "unidentified host/user",
                supervisor.timeout_seconds,
                steps,
                @tagName(self.startup.phase),
                self.regs.rip,
                self.active_guest_thread,
                self.pthreads.blocked_threads,
                self.suspended_guest_thread_count,
                self.faulted,
                self.terminal_memory_failure != null,
                self.terminal_control_transfer != null,
            },
        );
        macho_log.checkPointSync();
    }

    fn logDecodeCacheSummary(self: *const MachOState) void {
        proc_diag.logDecodeCacheSummary(self);
    }

    /// Mutable, unlike the summaries below it: the sampler has to retain the
    /// previous reading in order to report a delta.
    fn logPerformanceHeartbeat(self: *MachOState) void {
        proc_diag.logPerformanceHeartbeat(self);
    }

    fn logPerformanceAccelerationSummary(self: *const MachOState) void {
        proc_diag.logPerformanceAccelerationSummary(self);
    }

    fn logSharedControlBlockSummary(self: *const MachOState) void {
        proc_diag.logSharedControlBlockSummary(self);
    }

    fn logExitDiagnostics(self: *MachOState) void {
        proc_diag.logExitDiagnostics(self);
    }

    fn releaseBarrier() void {
        proc_diag.releaseBarrier();
    }

    pub fn logAtomicDiagnostic(self: *MachOState, matched: bool, size: Size, addr: u64, expected: u64, actual: u64, replacement: u64, is_locked: bool, rax_before: u64, rflags_before: u32) void {
        proc_diag.logAtomicDiagnostic(self, matched, size, addr, expected, actual, replacement, is_locked, rax_before, rflags_before);
    }

    /// Tracks hot functions that dominate execution and dumps SHA1 diagnostics.
    /// SHA1::processBytes is a guest function (part of Xenia) not in our codebase;
    /// we detect it heuristically when a function exceeds 1M guest instructions,
    /// and additionally by intercepting calls targeting the resolved symbol.
    pub const Sha1Tracer = struct {
        /// P1-3 (perf audit): master enable. Defaults to OFF so the two
        /// per-instruction probe sites (processBytes entry + post-exec
        /// accounting) collapse to a single compare on the hot path; the
        /// tracer is a diagnostic that only substantiates a SHA1 hot-loop
        /// stall, and it is only meaningful when a stall is being
        /// investigated. Arm with ROSETTE_MACHO_SHA1_TRACE=1.
        enabled: bool = false,
        /// True only while the resolved SHA1::processBytes invocation is on
        /// the active guest thread's stack. Keeping this explicit prevents
        /// unrelated long-running functions from being diagnosed as SHA1.
        active: bool = false,
        active_thread: u64 = 0,
        return_address: u64 = 0,
        /// Current call depth (0 = top level).
        depth: u32 = 0,
        /// RIP of the current function's entry point.
        entry_rip: u64 = 0,
        /// Call-site RIP that invoked the current function.
        call_site: u64 = 0,
        /// Guest instruction count spent in the current function.
        instruction_count: u64 = 0,
        /// Small call stack (depth ≤ 4) to restore function tracking on ret.
        saved_entry: [4]u64 = .{0} ** 4,
        saved_count: [4]u64 = .{0} ** 4,
        saved_call_site: [4]u64 = .{0} ** 4,
        /// Set when a hot function is detected.
        hot_function_rip: u64 = 0,
        /// Step counter at which the hot function was first detected.
        detected_at_step: u64 = 0,
        /// Whether we have reported the initial diagnostic entry.
        initial_report_done: bool = false,
        /// Throttle for periodic progress reports.
        progress_log_counter: u32 = 0,
        /// Cached SHA1 arguments captured at the exact processBytes entry.
        /// System V x86_64: RDI=this, RSI=data, RDX=length.
        sha1_this_ptr: u64 = 0,
        sha1_data_ptr: u64 = 0,
        sha1_byte_len: u64 = 0,
        /// Last-sampled SHA1 object state for progress tracking.
        last_data_ptr: u64 = 0,
        last_block_index: u32 = 0,
        last_buffered_bytes: u32 = 0,
        last_byte_count: u64 = 0,
        call_start_byte_count: u64 = 0,
        no_progress_samples: u32 = 0,
        stall_reported: bool = false,
        completion_reported: bool = false,
        /// Cumulative blocks consumed between progress samples.
        blocks_consumed: u64 = 0,

        // --- Enhanced processBytes entry tracking ---
        /// How many times sha1::SHA1::processBytes has been entered.
        process_bytes_entry_count: u64 = 0,
        /// Data pointer from the most recent processBytes entry.
        pb_data_ptr: u64 = 0,
        /// Byte length from the most recent processBytes entry.
        pb_byte_len: u64 = 0,
        /// Previous processBytes data ptr for repeat detection.
        prev_pb_data_ptr: u64 = 0,
        /// Previous processBytes byte len for repeat detection.
        prev_pb_byte_len: u64 = 0,
        /// How many times the same (data_ptr, length) pair has been seen.
        pb_repeat_count: u64 = 0,
        /// Step when the first repeat was detected.
        pb_repeat_first_step: u64 = 0,
        /// Whether a repeated-buffer scenario has been diagnosed.
        pb_repeat_detected: bool = false,

        const HOT_THRESHOLD: u64 = 1_000_000;
        const PROGRESS_LOG_INTERVAL: u32 = 100;
        const STALL_SAMPLE_THRESHOLD: u32 = 100;

        fn reset(self: *@This()) void {
            self.active = false;
            self.active_thread = 0;
            self.return_address = 0;
            self.entry_rip = 0;
            self.call_site = 0;
            self.instruction_count = 0;
            self.depth = 0;
            self.hot_function_rip = 0;
            self.detected_at_step = 0;
            self.initial_report_done = false;
            self.progress_log_counter = 0;
            self.sha1_this_ptr = 0;
            self.sha1_data_ptr = 0;
            self.sha1_byte_len = 0;
            self.last_data_ptr = 0;
            self.last_block_index = 0;
            self.last_buffered_bytes = 0;
            self.last_byte_count = 0;
            self.call_start_byte_count = 0;
            self.no_progress_samples = 0;
            self.stall_reported = false;
            self.completion_reported = false;
            self.blocks_consumed = 0;
            self.process_bytes_entry_count = 0;
            self.pb_data_ptr = 0;
            self.pb_byte_len = 0;
            self.prev_pb_data_ptr = 0;
            self.prev_pb_byte_len = 0;
            self.pb_repeat_count = 0;
            self.pb_repeat_first_step = 0;
            self.pb_repeat_detected = false;
        }

        pub fn isActiveThread(self: *const @This(), state: *const MachOState) bool {
            return self.active and self.active_thread == state.active_guest_thread;
        }

        fn blockIndex(total_bytes: u64) u32 {
            return @intCast(@min(total_bytes / 64, std.math.maxInt(u32)));
        }

        pub fn finishProcessBytes(self: *@This(), state: *MachOState) void {
            var buffered_bytes = self.last_buffered_bytes;
            var total_bytes = self.last_byte_count;
            if (state.guestMemoryConst(self.sha1_this_ptr + 96, 4)) |idx_bytes| {
                buffered_bytes = std.mem.readInt(u32, idx_bytes[0..4], .little);
            }
            if (state.guestMemoryConst(self.sha1_this_ptr + 104, 8)) |cnt_bytes| {
                total_bytes = std.mem.readInt(u64, cnt_bytes[0..8], .little);
            }
            const consumed = total_bytes -| self.call_start_byte_count;
            self.last_buffered_bytes = buffered_bytes;
            self.last_byte_count = total_bytes;
            self.last_block_index = blockIndex(total_bytes);
            if (self.stall_reported) {
                primitiveCapturePrint(
                    "macho-processor: SHA1 processBytes return #{d}: thread=0x{x} consumed={d}/{d} total_bytes={d} completed_blocks={d} buffered_bytes={d} step={d}\n",
                    .{
                        self.process_bytes_entry_count,
                        state.active_guest_thread,
                        consumed,
                        self.sha1_byte_len,
                        total_bytes,
                        self.last_block_index,
                        buffered_bytes,
                        state.executed_steps,
                    },
                );
            }

            self.active = false;
            self.active_thread = 0;
            self.return_address = 0;
            self.depth = 0;
            self.entry_rip = 0;
            self.call_site = 0;
            self.instruction_count = 0;
            self.progress_log_counter = 0;
            self.no_progress_samples = 0;
        }

        /// Called when execution reaches sha1_process_bytes. Captures its
        /// System V arguments silently; output is reserved for a detected
        /// repeat, stall, or later terminal-fault diagnostics.
        fn onProcessBytesEntry(self: *@This(), state: *MachOState) void {
            self.process_bytes_entry_count += 1;
            const this_ptr = state.regs.rdi;
            const data_ptr = state.regs.rsi;
            const byte_len = state.regs.rdx;
            const return_address = if (state.guestMemoryConst(state.regs.rsp, 8)) |return_bytes|
                std.mem.readInt(u64, return_bytes[0..8], .little)
            else
                0;

            self.active = true;
            self.active_thread = state.active_guest_thread;
            self.return_address = return_address;
            self.depth = 0;
            self.entry_rip = state.regs.rip;
            self.call_site = return_address;
            self.instruction_count = 0;
            self.initial_report_done = false;
            self.progress_log_counter = 0;
            self.hot_function_rip = 0;
            self.detected_at_step = 0;
            self.no_progress_samples = 0;
            self.stall_reported = false;
            self.completion_reported = false;
            self.pb_data_ptr = data_ptr;
            self.pb_byte_len = byte_len;

            // Detect repeated call with the same (data, length) pair
            if (data_ptr == self.prev_pb_data_ptr and byte_len == self.prev_pb_byte_len) {
                self.pb_repeat_count += 1;
                if (self.pb_repeat_count == 1) {
                    self.pb_repeat_first_step = state.executed_steps;
                }
                if (!self.pb_repeat_detected and self.pb_repeat_count >= 3) {
                    self.pb_repeat_detected = true;
                    primitiveCapturePrint(
                        "macho-processor: SHA1 WARNING: processBytes called with SAME buffer repeatedly! data=0x{x} length={d} repeat_count={d} step={d}\n",
                        .{ data_ptr, byte_len, self.pb_repeat_count, state.executed_steps },
                    );
                }
            } else {
                self.prev_pb_data_ptr = data_ptr;
                self.prev_pb_byte_len = byte_len;
                self.pb_repeat_count = 0;
                self.pb_repeat_detected = false;
            }

            // Update the hot-function cache so logSha1Progress uses correct args
            self.sha1_this_ptr = this_ptr;
            self.sha1_data_ptr = data_ptr;
            self.sha1_byte_len = byte_len;
            self.last_data_ptr = data_ptr;

            // TinySHA1 object layout in this Xenia build:
            // buffered-byte count at +0x60=96, total byte count at +0x68=104.
            var buffered_bytes: u32 = 0;
            var byte_count: u64 = 0;
            if (state.guestMemoryConst(this_ptr + 96, 4)) |idx_bytes| {
                buffered_bytes = std.mem.readInt(u32, idx_bytes[0..4], .little);
            }
            if (state.guestMemoryConst(this_ptr + 104, 8)) |cnt_bytes| {
                byte_count = std.mem.readInt(u64, cnt_bytes[0..8], .little);
            }
            self.last_block_index = blockIndex(byte_count);
            self.last_buffered_bytes = buffered_bytes;
            self.last_byte_count = byte_count;
            self.call_start_byte_count = byte_count;
        }

        fn logSha1Progress(self: *@This(), state: *MachOState) void {
            var current_buffered_bytes: u32 = self.last_buffered_bytes;
            var current_byte_count: u64 = self.last_byte_count;
            if (state.guestMemoryConst(self.sha1_this_ptr + 96, 4)) |idx_bytes| {
                current_buffered_bytes = std.mem.readInt(u32, idx_bytes[0..4], .little);
            }
            if (state.guestMemoryConst(self.sha1_this_ptr + 104, 8)) |cnt_bytes| {
                current_byte_count = std.mem.readInt(u64, cnt_bytes[0..8], .little);
            }
            const current_block_index = blockIndex(current_byte_count);
            const consumed_this_call = current_byte_count -| self.call_start_byte_count;
            const bytes_remaining = self.sha1_byte_len -| consumed_this_call;
            const blocks_delta = (current_block_index -| self.last_block_index);

            // A stable buffered-byte count with an increasing total count
            // means one or more complete 64-byte blocks were consumed. It is
            // progress, not a repeated-block stall. Diagnose a stall only
            // after many samples with neither counter changing.
            if (current_byte_count == self.last_byte_count and
                current_buffered_bytes == self.last_buffered_bytes)
            {
                self.no_progress_samples +|= 1;
            } else {
                self.no_progress_samples = 0;
            }
            if (!self.stall_reported and
                self.no_progress_samples >= STALL_SAMPLE_THRESHOLD)
            {
                self.stall_reported = true;
                primitiveCapturePrint(
                    "macho-processor: SHA1 WARNING: processBytes made no counter progress for {d} samples: data=0x{x} consumed={d}/{d} block_index={d} buffered_bytes={d} total_bytes={d} new_blocks_this_sample={d} step={d}\n",
                    .{ self.no_progress_samples, self.sha1_data_ptr, consumed_this_call, self.sha1_byte_len, current_block_index, current_buffered_bytes, current_byte_count, blocks_delta, state.executed_steps },
                );
            }
            if (!self.completion_reported and bytes_remaining == 0) {
                self.completion_reported = true;
            }

            self.last_block_index = current_block_index;
            self.last_buffered_bytes = current_buffered_bytes;
            self.last_byte_count = current_byte_count;
        }
    };

    pub fn execute(self: *MachOState, initial_d: DecodedInsn) void {
        return execute_impl.execute(self, initial_d);
    }

    pub fn executeFucomip(self: *MachOState, source: u3) void {
        execution_helpers.executeFucomip(self, source);
    }

    pub fn executeBitScan(self: *MachOState, d: DecodedInsn) void {
        execution_helpers.executeBitScan(self, d);
    }

    pub fn executeRotate(self: *MachOState, d: DecodedInsn) void {
        execution_helpers.executeRotate(self, d);
    }

    pub fn executeVexScalarF32(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        execution_helpers.executeVexScalarF32(self, d, operation);
    }

    pub fn executeVexScalarF64(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        execution_helpers.executeVexScalarF64(self, d, operation);
    }

    pub fn executeVexPackedF32(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        execution_helpers.executeVexPackedF32(self, d, operation);
    }

    pub fn executeVexPackedF64(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        execution_helpers.executeVexPackedF64(self, d, operation);
    }

    pub fn executeVexSqrtScalarF32(self: *MachOState, d: DecodedInsn) void {
        execution_helpers.executeVexSqrtScalarF32(self, d);
    }

    pub fn executeVexSqrtScalarF64(self: *MachOState, d: DecodedInsn) void {
        execution_helpers.executeVexSqrtScalarF64(self, d);
    }

    /// A comparison whose predicate this interpreter does not model must not
    /// silently write a mask: the guest would branch on it and nothing would
    /// record that the branch was decided by a guess.
    pub fn reportUnsupportedComparePredicate(self: *MachOState, d: DecodedInsn, executed: bool) void {
        if (executed) return;
        machoCapturePrint(
            "macho-processor: unsupported SIMD compare predicate: op={s} imm=0x{x} rip=0x{x}; the comparison was not performed rather than performed with a guessed relation\n",
            .{ @tagName(d.op), d.imm, self.regs.rip },
        );
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unimplemented_instruction);
        self.terminated = true;
    }

    pub fn executeVexReciprocalPacked(self: *MachOState, d: DecodedInsn, comptime square_root: bool) void {
        execution_helpers.executeVexReciprocalPacked(self, d, square_root);
    }

    pub fn executeVexReciprocalScalar(self: *MachOState, d: DecodedInsn, comptime square_root: bool) void {
        execution_helpers.executeVexReciprocalScalar(self, d, square_root);
    }

    pub fn executeVexConvertPacked(
        self: *MachOState,
        d: DecodedInsn,
        comptime direction: @TypeOf(.enum_literal),
    ) void {
        execution_helpers.executeVexConvertPacked(self, d, direction);
    }

    pub fn executeVexComparePacked(self: *MachOState, d: DecodedInsn, comptime double: bool) bool {
        return execution_helpers.executeVexComparePacked(self, d, double);
    }

    pub fn executeVexCompareScalar(self: *MachOState, d: DecodedInsn, comptime double: bool) bool {
        return execution_helpers.executeVexCompareScalar(self, d, double);
    }

    pub fn executeVexSqrtPackedF32(self: *MachOState, d: DecodedInsn) void {
        execution_helpers.executeVexSqrtPackedF32(self, d);
    }

    pub fn executeVexSqrtPackedF64(self: *MachOState, d: DecodedInsn) void {
        execution_helpers.executeVexSqrtPackedF64(self, d);
    }

    pub fn setVexComparisonFlags(self: *MachOState, lhs: anytype, rhs: @TypeOf(lhs)) void {
        execution_helpers.setVexComparisonFlags(self, lhs, rhs);
    }

    pub fn executeVexBitwise(self: *MachOState, d: DecodedInsn, operation: VexBitwise) void {
        execution_helpers.executeVexBitwise(self, d, operation);
    }

    pub fn executeAddRegImm(self: *MachOState, d: DecodedInsn, sz: Size) void {
        self.executeHighwayImmediate(d, .add, sz, false);
    }

    pub fn raiseDivideError(self: *MachOState) void {
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 136;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.divide_by_zero);
    }

    pub fn executeSubRegImm(self: *MachOState, d: DecodedInsn, sz: Size) void {
        self.executeHighwayImmediate(d, .sub, sz, false);
    }

    pub fn executeAndRegImm(self: *MachOState, d: DecodedInsn) void {
        self.executeHighwayImmediate(d, .bit_and, d.size, false);
    }

    fn resolveSyscallFd(self: *MachOState, guest_fd: u64) i32 {
        if (guest_fd < self.guest_fds.len) {
            const host = self.guest_fds[@as(usize, @intCast(guest_fd))];
            if (host >= 0) return host;
        }
        if (self.fs_forwarder.fd_manager.hostFd(guest_fd)) |host| return host;
        return -1;
    }

    pub fn dispatchMacOSSyscall(self: *MachOState, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64, arg6: u64) void {
        const number = self.regs.rax;
        log.info("syscall: number=0x{x} ({s}) args=({d}, {d}, {d}, {d}, {d}, {d})", .{
            number, macho_runtime.syscallName(number),
            arg1,   arg2,
            arg3,   arg4,
            arg5,   arg6,
        });

        switch (number) {
            @intFromEnum(macho_runtime.Syscall.exit) => {
                const exit_code = arg1;
                log.info("exit({d})", .{exit_code});
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
                self.terminated = true;
                self.exit_code = exit_code;
            },
            @intFromEnum(macho_runtime.Syscall.open) => {
                const path = self.guestCString(arg1, 4096) orelse {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                    return;
                };
                var temp_buf: [4096]u8 = undefined;
                var translated_path = path;
                if (self.fs_forwarder.resolveHostPath(path, &temp_buf)) |t| {
                    translated_path = t;
                }
                var path_buf: [4096]u8 = undefined;
                const plen = @min(translated_path.len, path_buf.len - 1);
                @memcpy(path_buf[0..plen], translated_path[0..plen]);
                path_buf[plen] = 0;
                const oflags: std.c.O = @bitCast(@as(u32, @truncate(arg2)));
                const mode: std.c.mode_t = @intCast(arg3 & 0xFFFF);
                var host_fd = std.c.open(@as([*:0]const u8, @ptrCast(&path_buf)), oflags, mode);
                if (host_fd < 0) {
                    const err = std.c.errno(host_fd);
                    if (err == .NOENT) {
                        if (self.fs_forwarder.tryOpenFallback(translated_path, oflags, @as(u32, @intCast(arg3)), err)) |fallback_fd| {
                            host_fd = fallback_fd;
                        }
                    }
                    if (host_fd < 0) {
                        self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                        return;
                    }
                }
                const guest_fd = self.fs_forwarder.fd_manager.register(host_fd, .file) orelse {
                    _ = std.c.close(host_fd);
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                    return;
                };
                if (guest_fd < self.guest_fds.len) {
                    self.guest_fds[@as(usize, @intCast(guest_fd))] = host_fd;
                }
                self.regs.rax = guest_fd;
            },
            @intFromEnum(macho_runtime.Syscall.close) => {
                const close_guest_fd = arg1;
                if (close_guest_fd < self.guest_fds.len) {
                    self.guest_fds[@as(usize, @intCast(close_guest_fd))] = -1;
                }
                const rc = self.fs_forwarder.fd_manager.close(close_guest_fd);
                self.regs.rax = if (rc < 0) std.math.maxInt(u64) else 0;
            },
            @intFromEnum(macho_runtime.Syscall.write) => {
                const fd = arg1;
                const buf = arg2;
                const count = arg3;
                const data = self.guestMemoryConst(buf, count) orelse {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFE;
                    return;
                };
                const host_fd = self.resolveSyscallFd(fd);
                var written: usize = 0;
                if (host_fd >= 0) {
                    while (written < data.len) {
                        const n = std.c.write(host_fd, data[written..].ptr, data.len - written);
                        if (n <= 0) {
                            self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                            return;
                        }
                        written += @as(usize, @intCast(n));
                    }
                }
                self.regs.rax = @intCast(written);
            },
            @intFromEnum(macho_runtime.Syscall.read) => {
                const fd = arg1;
                const buf = arg2;
                const count = arg3;
                const data = self.guestMemory(buf, count) orelse {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFE;
                    return;
                };
                const host_fd = self.resolveSyscallFd(fd);
                if (host_fd >= 0) {
                    const n = std.c.read(host_fd, data.ptr, data.len);
                    if (n < 0) {
                        self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                        return;
                    }
                    self.regs.rax = @intCast(@as(usize, @intCast(n)));
                } else {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                }
            },
            @intFromEnum(macho_runtime.Syscall.mmap) => {
                const addr = arg1;
                const length = arg2;
                const prot = arg3;
                const raw_flags: u32 = @truncate(arg4);
                const map_flags: std.c.MAP = @bitCast(raw_flags);
                const offset: i64 = @bitCast(arg6);
                self.noteBackendMmapAttempt("syscall", addr, length, prot, raw_flags, map_flags.FIXED, map_flags.ANONYMOUS);

                const alignment = PAGE_SIZE;
                const aligned_length = ((length + alignment - 1) / alignment) * alignment;

                if (self.backendMemoryDiagnosticsActive() and addr == 0 and map_flags.ANONYMOUS and length >= 64 * 1024 * 1024) {
                    const mapped = self.guestMapBackendWithBacking(length, @truncate(prot), raw_flags, -1, @bitCast(offset)) orelse {
                        machoCapturePrint(
                            "macho-processor: x64 backend sparse mmap FAILED: route=syscall address=0x0 length={d} prot=0x{x} flags=0x{x}\n",
                            .{ length, prot, raw_flags },
                        );
                        self.noteBackendMmapResult(false, 0, "syscall_backend_sparse_anywhere");
                        self.regs.rax = std.math.maxInt(u64);
                        return;
                    };
                    machoCapturePrint(
                        "macho-processor: x64 backend sparse mmap succeeded: route=syscall guest_base=0x{x} length={d} prot=0x{x} flags=0x{x} heap_bypassed=true\n",
                        .{ mapped, length, prot, raw_flags },
                    );
                    self.noteBackendMmapResult(true, mapped, "syscall_backend_sparse_anywhere");
                    self.regs.rax = mapped;
                    return;
                }

                if (length >= 1024 * 1024 * 1024) {
                    machoCapturePrint(
                        "macho-processor: large mmap entry: route=syscall addr=0x{x} length={d} aligned_length={d} prot=0x{x} flags=0x{x} fixed={} anonymous={} guest_fd=0x{x} offset={d}\n",
                        .{ addr, length, aligned_length, prot, raw_flags, map_flags.FIXED, map_flags.ANONYMOUS, arg5, offset },
                    );
                }

                if (addr == 0 and prot == 0 and length >= 1024 * 1024 * 1024) {
                    const host_fd: std.posix.fd_t = if (map_flags.ANONYMOUS)
                        -1
                    else
                        self.fs_forwarder.fd_manager.hostFd(arg5) orelse {
                            machoCapturePrint("macho-processor: large mmap FAILED: route=syscall stage=fd_translation guest_fd=0x{x}\n", .{arg5});
                            self.noteBackendMmapResult(false, 0, "syscall_large_fd_translation");
                            self.regs.rax = std.math.maxInt(u64);
                            return;
                        };
                    const reserved = self.guestReserveAddressSpaceWithBacking(aligned_length, raw_flags, host_fd, @bitCast(offset)) orelse {
                        machoCapturePrint("macho-processor: large mmap FAILED: route=syscall stage=sparse_reserve\n", .{});
                        self.noteBackendMmapResult(false, 0, "syscall_sparse_reserve");
                        self.regs.rax = std.math.maxInt(u64);
                        return;
                    };
                    machoCapturePrint("macho-processor: large mmap succeeded: route=syscall guest_base=0x{x} length={d}\n", .{ reserved, aligned_length });
                    self.noteBackendMmapResult(true, reserved, "syscall_sparse_reserve");
                    self.regs.rax = reserved;
                    return;
                }

                if (addr != 0 and map_flags.FIXED) {
                    const host_fd: std.posix.fd_t = if (map_flags.ANONYMOUS)
                        -1
                    else
                        self.fs_forwarder.fd_manager.hostFd(arg5) orelse {
                            machoCapturePrint("macho-processor: fixed mmap FAILED: route=syscall stage=fd_translation guest_fd=0x{x}\n", .{arg5});
                            self.noteBackendMmapResult(false, 0, "syscall_fixed_fd_translation");
                            self.regs.rax = std.math.maxInt(u64);
                            return;
                        };
                    if (!self.guestMapFile(addr, aligned_length, @truncate(prot), raw_flags, host_fd, @bitCast(offset))) {
                        machoCapturePrint("macho-processor: fixed mmap FAILED: route=syscall stage=sparse_map addr=0x{x} length={d}\n", .{ addr, aligned_length });
                        self.noteBackendMmapResult(false, 0, "syscall_fixed_sparse_map");
                        self.regs.rax = std.math.maxInt(u64);
                        return;
                    }
                    self.noteBackendMmapResult(true, addr, "syscall_fixed_sparse_map");
                    self.regs.rax = addr;
                    return;
                }

                const mapped = if (addr != 0) addr else self.guestAlloc(aligned_length, alignment) orelse {
                    machoCapturePrint("macho-processor: mmap FAILED: route=syscall stage=guest_heap length={d} alignment={d}\n", .{ aligned_length, alignment });
                    self.noteBackendMmapResult(false, 0, "syscall_guest_heap_allocate");
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                    return;
                };
                const off = mappedOffset(self.mem_base, self.mem_size, self.mapped_min, mapped) orelse {
                    self.noteBackendMmapResult(false, 0, "syscall_address_translation");
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                    return;
                };
                if (off + aligned_length > self.mem_size) {
                    self.noteBackendMmapResult(false, 0, "syscall_backing_bounds");
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                    return;
                }
                @memset(self.mem[off..][0..@as(usize, @intCast(aligned_length))], 0);
                self.setPagePermissions(mapped, aligned_length, @truncate(prot & 0x07));
                _ = self.memory_regions.register(mapped, aligned_length, .{
                    .read = prot & 0x01 != 0,
                    .write = prot & 0x02 != 0,
                    .execute = prot & 0x04 != 0,
                }, .guest_mmap, "guest mmap", self.regs.rip);
                self.noteBackendMmapResult(true, mapped, "syscall_guest_mapping");
                self.regs.rax = mapped;
            },
            @intFromEnum(macho_runtime.Syscall.mprotect) => {
                const address = arg1;
                const length = ((arg2 + PAGE_SIZE - 1) / PAGE_SIZE) * PAGE_SIZE;
                const prot = arg3;
                if (self.guestProtectSparseMemory(address, length, @truncate(prot))) {
                    machoCapturePrint("macho-processor: sparse mprotect succeeded: route=syscall address=0x{x} length={d} prot=0x{x}\n", .{ address, length, prot });
                    self.noteBackendMprotect("syscall", address, length, prot, true);
                    self.regs.rax = 0;
                    return;
                }
                if (mappedOffset(self.mem_base, self.mem_size, self.mapped_min, address) == null) {
                    machoCapturePrint("macho-processor: mprotect FAILED: route=syscall reason=address_not_mapped address=0x{x} length={d} prot=0x{x}\n", .{ address, length, prot });
                    self.noteBackendMprotect("syscall", address, length, prot, false);
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                    return;
                }
                self.setPagePermissions(address, length, @truncate(prot & 0x07));
                _ = self.memory_regions.register(address, length, .{
                    .read = prot & 0x01 != 0,
                    .write = prot & 0x02 != 0,
                    .execute = prot & 0x04 != 0,
                }, .guest_mmap, "guest mprotect", self.regs.rip);
                self.noteBackendMprotect("syscall", address, length, prot, true);
                self.regs.rax = 0;
            },
            @intFromEnum(macho_runtime.Syscall.munmap) => {
                const address = arg1;
                const length = ((arg2 + PAGE_SIZE - 1) / PAGE_SIZE) * PAGE_SIZE;
                if (self.guestUnmapFile(address, length)) {
                    machoCapturePrint("macho-processor: sparse munmap succeeded: route=syscall address=0x{x} length={d}\n", .{ address, length });
                    self.regs.rax = 0;
                    return;
                }
                self.setPagePermissions(address, length, 0);
                _ = self.memory_regions.register(address, length, .{ .read = false, .write = false }, .guest_unmapped, "guest munmap", self.regs.rip);
                self.regs.rax = 0;
            },
            @intFromEnum(macho_runtime.Syscall.getpid) => {
                self.regs.rax = 42;
            },
            @intFromEnum(macho_runtime.Syscall.issetugid) => {
                self.regs.rax = 0;
            },
            0x2000072 => {
                self.regs.rax = 1;
            },
            else => {
                log.warn("unimplemented syscall: 0x{x}", .{number});
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
            },
        }
    }
};

const utils = @import("macho_core").utils;
const nextPrime = utils.nextPrime;
const alignDown = utils.alignDown;
const importRouteCacheIndex = utils.importRouteCacheIndex;
const calculateBulkConstructionRange = utils.calculateBulkConstructionRange;
const mappedOffset = utils.mappedOffset;
const applyBindingAddend = utils.applyBindingAddend;
const guestSignalIndex = utils.guestSignalIndex;
const signalFailureResult = utils.signalFailureResult;
const signalHandlerMadeProgress = utils.signalHandlerMadeProgress;
const isAsciiBytes = utils.isAsciiBytes;
const profileIdFromUserDevice = utils.profileIdFromUserDevice;
const repairAsciiCodepointBlock = utils.repairAsciiCodepointBlock;
const isPatchDbNullIsArraySequence = utils.isPatchDbNullIsArraySequence;
const threeOperandImulResult = utils.threeOperandImulResult;
const resolveGuestSignalReturn = utils.resolveGuestSignalReturn;
const readDarwinSigaction = utils.readDarwinSigaction;
const writeDarwinSigaction = utils.writeDarwinSigaction;
const writeDarwinSiginfo = utils.writeDarwinSiginfo;
const writeDarwinUcontext = utils.writeDarwinUcontext;
const writeDarwinMcontext = utils.writeDarwinMcontext;
const readDarwinMcontext = utils.readDarwinMcontext;
const alignUp = utils.alignUp;
const selectedCpuProfile = utils.selectedCpuProfile;
const environmentFlag = utils.environmentFlag;
const environmentUnsigned = utils.environmentUnsigned;
const stepBudgetAllows = utils.stepBudgetAllows;
const VexDecoderAudit = utils.VexDecoderAudit;
const MachORunOptions = utils.MachORunOptions;
const auditVexDecoder = utils.auditVexDecoder;

pub fn loadAndRun(io: std.Io, allocator: std.mem.Allocator, options: MachORunOptions) !u64 {
    native_crash.recordPhase("load");
    var output = runtime_output.Controller.init(allocator);
    defer output.deinit();
    output.human("Loading Mach-O...\n", .{});

    const file_data = try std.Io.Dir.cwd().readFileAlloc(io, options.path, allocator, .unlimited);
    defer allocator.free(file_data);

    const slice = extractX8664Slice(allocator, file_data) catch |err| {
        machoCapturePrint("macho-processor: not a valid x86_64 Mach-O binary: {s}\n", .{@errorName(err)});
        return 1;
    };

    var state = try MachOState.init(io, allocator, slice);
    defer state.deinit();
    // The exported application-framework ABI must point at the live process
    // ledger, not a detached diagnostic singleton. Register the binding after
    // state construction and clear it before state.deinit releases resources.
    application_framework.activateDefault(&state.application_framework);
    defer application_framework.deactivateDefault(&state.application_framework);
    var host_termination_scope = host_termination.Scope.install();
    defer host_termination_scope.deinit();
    state.concise_output = output.concise;
    state.diagnostic_output_fd = output.diagnosticsFd();
    state.summary_output_fd = output.summaryFd();
    if (state.summary_output_fd >= 0) {
        var launch_buffer: [2048]u8 = undefined;
        const launch_line = std.fmt.bufPrint(&launch_buffer, "step=0 event=mach_o_launch path={s}\n", .{options.path}) catch "";
        _ = MachOState.hostWriteFdAll(state.summary_output_fd, launch_line);
    }
    native_crash.recordPhase("logs-open");
    state.scheduler_log.open(allocator);
    state.pthreads.attachEventLog(&state.scheduler_log);
    state.jit_log.open(allocator);
    state.macho_log.open(allocator);
    state.macho_log.emit(.{
        .kind = .process_launch,
        .step = 0,
        .reason = options.path,
    });
    // Package contract verification: checks all Xenia contracts at startup
    // and writes results to .rosette/rosette-pkg.log. Failures are also
    // piped to stderr (rosette-runtime.log) for immediate visibility.
    var pkg_log = rosette_pkg_log.Logger{};
    pkg_log.open(allocator);
    defer pkg_log.close();
    output.human("Loading imports...\n", .{});
    state.cpu_profile = selectedCpuProfile();
    state.verbose_trace = options.trace or environmentFlag("ROSETTE_MACHO_VERBOSE_TRACE");
    // F19: all three per-instruction trace gates are init-time switches that
    // never change after startup, so one boolean carries their combined state
    // into the hot path. Any future per-instruction post-decode gate must
    // extend this expression.
    state.step_tracing_active = state.verbose_trace or
        state.sha1_tracer.enabled or
        state.trace_range_start != null;
    state.unwinder.verbose = state.verbose_trace or environmentFlag("ROSETTE_MACHO_UNWIND_VERBOSE");
    state.startup.enabled = environmentFlag("ROSETTE_MACHO_STARTUP_TRACE");
    state.contract_verification = environmentFlag("ROSETTE_CONTRACT_VERIFICATION");
    state.memory_trace_enabled = environmentFlag("ROSETTE_MACHO_MEMORY_TRACE");
    // The instruction tape records generated code only, because host-image code
    // outruns it by orders of magnitude — 662 million filtered steps against a
    // few hundred recorded in a recorded run. That is the right default and the
    // wrong one for a *native* fault: a null C++ receiver in Xenia's own code is
    // host-image code, so its entire producer chain is filtered and the
    // causality engine has nothing to walk. This knob trades throughput for that
    // chain on a deliberate diagnostic run, and is named in the empty-window
    // explanation so a reader is told how to get the evidence rather than that
    // it does not exist.
    if (environmentFlag("ROSETTE_MACHO_NATIVE_TRACE")) {
        state.execution_history.policy = .all;
    }
    state.never_notified_repair_enabled =
        environmentFlag("ROSETTE_MACHO_NEVER_NOTIFIED_REPAIR");
    state.allow_assumed_dispatch_continuation = !environmentFlag("ROSETTE_MACHO_STRICT_DISPATCH");
    // R3 (perf audit): full mutation provenance, detailed vtable mutation
    // attribution and the suspicious-write detector default off. The narrow
    // constructor-vptr identity path remains active independently because it
    // authorizes correctness-bearing recovery, not merely diagnostics.
    state.write_diagnostics_armed = environmentFlag("ROSETTE_MACHO_WRITE_DIAGNOSTICS");
    state.strict_initializers = environmentFlag("ROSETTE_MACHO_STRICT_INITIALIZERS");
    state.strict_imports = environmentFlag("ROSETTE_MACHO_STRICT_IMPORTS");
    state.max_steps = environmentUnsigned("ROSETTE_MACHO_MAX_STEPS", state.max_steps);
    // N7 (perf audit): per-initializer + vtable-lifecycle detail logs default
    // to off; the run log flooded with ~700K chars of initializer detail.
    state.initializer_detail_logging = environmentFlag("ROSETTE_MACHO_INITIALIZER_DETAIL");

    var temp_state = try macho.load(allocator, slice);
    defer temp_state.deinit();

    machoCapturePrint("macho-processor: {s}\n", .{options.path});
    machoCapturePrint("ROSETTE: Loading MachO binary: '{s}'\n", .{options.path});
    if (std.mem.endsWith(u8, options.path, ".iso")) {
        machoCapturePrint("ROSETTE: WARNING: .iso file detected - this may indicate incorrect routing\n", .{});
    }
    const image_fingerprint = std.hash.Wyhash.hash(0, slice);
    const has_xbdm_diagnostics = std.mem.indexOf(
        u8,
        slice,
        "[XBDM export diagnostics] table initialized:",
    ) != null;
    machoCapturePrint(
        "macho-processor: image identity: bytes={d} wyhash64={x:0>16} xbdm_diagnostics={} bundle_executable={}\n",
        .{
            slice.len,
            image_fingerprint,
            has_xbdm_diagnostics,
            std.mem.indexOf(u8, options.path, ".app/Contents/MacOS/") != null,
        },
    );
    machoCapturePrint("  filetype: 0x{x}", .{temp_state.header.filetype});
    switch (temp_state.header.filetype) {
        2 => machoCapturePrint(" (MH_EXECUTE)\n", .{}),
        6 => machoCapturePrint(" (MH_DYLIB)\n", .{}),
        8 => machoCapturePrint(" (MH_BUNDLE)\n", .{}),
        else => machoCapturePrint("\n", .{}),
    }
    machoCapturePrint("  cputype:  0x{x}", .{temp_state.header.cputype});
    if (temp_state.header.cputype == macho.CPU_TYPE_X86_64) machoCapturePrint(" (x86_64)\n", .{}) else machoCapturePrint("\n", .{});
    machoCapturePrint("  ncmds:    {d}\n", .{temp_state.header.ncmds});
    machoCapturePrint("  segments: {d}\n", .{temp_state.segments.len});
    machoCapturePrint("  entry:    0x{x}\n", .{temp_state.entry_point});
    machoCapturePrint("  stack:    0x{x}\n", .{temp_state.stack_size});
    machoCapturePrint("  mem_base: 0x{x}\n", .{state.mem_base});
    machoCapturePrint("  entry_vaddr: 0x{x}\n", .{state.entry_point_vaddr});
    machoCapturePrint("  dylibs:    {d}\n", .{state.metadata.dylibs.len});
    machoCapturePrint("  imports:   {d}\n", .{state.metadata.imports.len});
    machoCapturePrint("  initializers: {d}\n", .{state.metadata.initializer_count});
    machoCapturePrint("  strict initializers: {}\n", .{state.strict_initializers});
    machoCapturePrint("  strict imports: {}\n", .{state.strict_imports});
    machoCapturePrint("  never-notified wait repair: {}\n", .{state.never_notified_repair_enabled});
    machoCapturePrint("  x64 cpu profile: {s}\n", .{state.cpu_profile.label()});
    machoCapturePrint(
        "  advertised ISA: SSE4.2={} AVX={} AVX2={} AVX-512F={} XCR0=0x{x}\n",
        .{
            x64_decoder.capabilities.supports(state.cpu_profile, .sse42),
            x64_decoder.capabilities.supports(state.cpu_profile, .avx),
            x64_decoder.capabilities.supports(state.cpu_profile, .avx2),
            x64_decoder.capabilities.supports(state.cpu_profile, .avx512f),
            x64_decoder.capabilities.xcr0(state.cpu_profile),
        },
    );
    const vex_audit = auditVexDecoder();
    const avx_advertised = x64_decoder.capabilities.supports(state.cpu_profile, .avx);
    machoCapturePrint(
        "  decoder ISA verification: VEX baseline={d}/{d} ready={} AVX advertised={}\n",
        .{ vex_audit.passed, vex_audit.total, vex_audit.ready(), avx_advertised },
    );
    if (avx_advertised and !vex_audit.ready()) {
        machoCapturePrint(
            "macho-processor: refusing incoherent AVX profile: CPUID advertises AVX but baseline VEX decoder audit failed: case={?} expected={s}/len={d}/ymm={} actual={s}/len={d}/ymm={}\n",
            .{
                vex_audit.first_failed_case,
                @tagName(vex_audit.expected_op),
                vex_audit.expected_len,
                vex_audit.expected_vector_256,
                @tagName(vex_audit.actual_op),
                vex_audit.actual_len,
                vex_audit.actual_vector_256,
            },
        );
        return 1;
    }
    if (state.metadata.nearestSymbol(state.entry_point_vaddr)) |entry_symbol| {
        machoCapturePrint("  entry_symbol: {s}+0x{x}\n", .{ entry_symbol.name, entry_symbol.offset });
    }

    for (temp_state.segments, 0..) |seg, i| {
        const prot_str = switch (seg.initprot) {
            7 => "rwx",
            5 => "r-x",
            3 => "rw-",
            1 => "r--",
            else => "???",
        };
        machoCapturePrint("    [{d}] {s: <12}  vm=0x{x:0>8}  size=0x{x:0>8}  file=0x{x:0>8}  ({s})\n", .{
            i, seg.name, seg.vmaddr, seg.vmsize, seg.fileoff, prot_str,
        });
    }

    if (temp_state.entry_point == 0) {
        machoCapturePrint("macho-processor: no entry point found\n", .{});
        return 1;
    }

    state.guest_fds[0] = 0;
    state.guest_fds[1] = 1;
    state.guest_fds[2] = 2;

    machoCapturePrint("ROSETTE: About to setup MachO state for path: '{s}'\n", .{options.path});
    machoCapturePrint("ROSETTE: This confirms Rosetta is routing Xenia through compatibility layer\n", .{});
    output.human("Initializing pthread runtime...\n", .{});
    state.setupMachOState(options.path, options.args);
    // Seeded from the process identity and a load-address the kernel
    // randomises per launch. Deliberately not a wall clock: two runs started in
    // the same second must not share a run identifier, because the whole point
    // of the identifier is that evidence from two runs cannot be joined by
    // accident.
    state.event_stream.begin(
        (@as(u64, @intCast(std.c.getpid())) << 32) ^ @intFromPtr(&state),
    );
    machoCapturePrint(
        "macho-processor: run identity established: run=0x{x}; every boundary record in this log carries it, so records from two runs can never be joined\n",
        .{state.event_stream.run_id},
    );
    state.armGraphicsTracepoints();
    const image_is_xenia = has_xbdm_diagnostics or
        std.mem.indexOf(u8, options.path, "xenia") != null or
        std.mem.indexOf(u8, slice, "VdSwap") != null;
    // Xenia gets the framework by default because its native host callbacks
    // are the exact boundary this ledger is meant to make observable. Other
    // translated applications opt in explicitly to avoid paying for extra
    // event retention. Fine-grained control-flow tracing remains opt-in even
    // for Xenia because it is much more expensive than boundary sampling.
    state.application_framework.configureForProcess(
        image_is_xenia or environmentFlag("ROSETTE_APPLICATION_FRAMEWORK"),
        environmentFlag("ROSETTE_APPLICATION_FRAMEWORK_TRACE"),
        environmentFlag("ROSETTE_APPLICATION_FRAMEWORK_MEMORY_TRACE"),
        image_is_xenia or environmentFlag("ROSETTE_APPLICATION_FRAMEWORK_GRAPHICS"),
    );
    state.application_framework.registerApplication(options.path, image_fingerprint);
    _ = state.application_framework.registerAdapter(
        "xenia",
        application_framework.contract.capabilityBit(.observe_events) |
            application_framework.contract.capabilityBit(.inspect_control_flow) |
            application_framework.contract.capabilityBit(.inspect_memory) |
            application_framework.contract.capabilityBit(.inspect_graphics) |
            application_framework.contract.capabilityBit(.inspect_backend),
    );
    const application_framework_config = state.application_framework.configuration();
    const application_framework_mode: application_framework.contract.Mode = @enumFromInt(application_framework_config.mode);
    machoCapturePrint(
        "macho-processor: APPLICATION FRAMEWORK: enabled={} mode={s} trace_control_flow={} trace_memory={} trace_graphics={} abi=0x{x}\n",
        .{
            application_framework_mode != .disabled,
            application_framework_mode.label(),
            application_framework_config.trace_control_flow != 0,
            application_framework_config.trace_memory != 0,
            application_framework_config.trace_graphics != 0,
            application_framework.contract.abi_version,
        },
    );
    const ready_gate_requested = environmentFlag("ROSETTE_MACHO_READY_GATE") or image_is_xenia;
    const ready_gate_enabled = ready_gate_requested and
        !environmentFlag("ROSETTE_MACHO_READY_GATE_OFF");
    const ready_gate_enforce = !environmentFlag("ROSETTE_MACHO_READY_GATE_REPORT_ONLY");
    state.configureReadyCompiler(
        ready_gate_enabled,
        ready_gate_enforce,
        environmentUnsigned("ROSETTE_MACHO_READY_MAX_STEPS", 0),
        environmentUnsigned("ROSETTE_MACHO_READY_QUIET_STEPS", 0),
        vex_audit.ready(),
    );
    // The startup compile plan runs here: after the image is mapped and its
    // symbols are indexed, and before a single guest instruction executes. A
    // precondition that is missing now is missing at step four hundred million
    // too, and this is the only point where saying so costs milliseconds
    // instead of minutes.
    if (!state.runReadyCompilerPlan(io, options.path, options.args, vex_audit.ready())) {
        state.logReadyCompilerSummary();
        machoCapturePrint(
            "macho-processor: READY COMPILER: refusing to launch; the startup contract cannot be satisfied by this image\n",
            .{},
        );
        return 125;
    }
    state.launch_options.logConfiguration(state.internal_targets.cvar_add_to_launch_options_count);
    machoCapturePrint("ROSETTE: MachO state setup completed successfully\n", .{});

    state.startup.enter(.static_init, state.executed_steps);
    native_crash.recordPhase("static_init");
    output.human("Initializing guest runtime...\n", .{});
    machoCapturePrint("macho-processor: running {d} pre-main initializer(s)\n", .{state.metadata.initializer_addresses.len});
    const initializers_ok = state.runInitializers();
    state.initializer_resolver.logSummary();
    if (!initializers_ok) {
        if (state.host_termination_signal != 0) {
            state.logHostTerminationSnapshot(state.executed_steps);
            machoCapturePrint(
                "macho-processor: graceful host-termination diagnostics complete during initializer phase; returning signal-compatible status={d}\n",
                .{state.exit_code},
            );
            macho_log.checkPointSync();
            return state.exit_code;
        }
        state.import_resolver.logSummary();
        state.foreign_objects.logSummary();
        state.sdl.logSummary();
        state.native_window.logSummary();
        state.dynamic_forwarder.logSummary();
        state.fs_forwarder.logSummary();
        state.libcxx_filesystem.logSummary();
        state.libcxx_streams.logSummary();
        state.logging.logSummary();
        state.backend_diagnostics.logSummary();
        state.xenia_pipeline.logSummary(state.executed_steps);
        state.xenia_gpu_handoff.logSummary(state.executed_steps);
        state.logReadyCompilerSummary();
        state.export_table_mgr.logSummary();
        state.export_table_lc.logSummary();
        state.export_registry.logSummary();
        state.pthreads.logSummary();
        state.logCooperativeSchedulerSummary();
        state.memory_forwarder.logSummary();
        state.logLiveVtableGuardSummary();
        state.import_binding_predictor.dump("exit");
        state.launch_options.logSummary();
        state.startup.logSummary();
        state.cxx_exceptions.logSummary();
        state.spirv_cross.logSummary();
        state.unwinder.logSummary();
        state.dynamic_casts.logSummary();
        state.diagnostic_text.logSummary();
        state.smart_stubs.logSummary();
        state.symbol_assembly.logSummary();
        state.logDecodeCacheSummary();
        state.logPerformanceAccelerationSummary();
        machoCapturePrint("macho-processor: initializer phase failed: exit_code={d}\n", .{state.exit_code});
        return state.exit_code;
    }

    if (!state.sealReadyCompilerCompile()) {
        state.logReadyCompilerSummary();
        if (state.ready.enforce) {
            state.faulted = true;
            state.terminated = true;
            state.exit_code = 125;
            state.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.runtime_invariant_failure);
            return state.exit_code;
        }
    }

    state.startup.enter(.main_enter, state.executed_steps);
    native_crash.recordPhase("main_enter");
    // R2 (N3 phase-arm): config parsing (cvar, toml patch files) completes
    // with the initializer phase. Deactivate the non-address patch-db probe so
    // the special-RIP gate drops its per-instruction state check; the fixed
    // toml table entries become unreachable once is_ascii/read_next stop
    // being called.
    //
    // Trade-off (accepted, per audit): a title that opened a patch file with
    // an empty patch set *after* the initializer phase would no longer get the
    // PatchDB empty-patch-array recovery. Xenia loads patch files pre-main
    // (the audit's run log shows patches completing in the initializer phase),
    // so the probe's trigger condition cannot occur after this point for the
    // audited target; the schema state check alone (without the phase flag)
    // is the fallback if a title ever violates that assumption.
    state.config_parsing_active = false;
    output.human("Loading guest program...\n", .{});
    machoCapturePrint("macho-processor: starting execution at 0x{x}, rsp=0x{x}\n", .{ state.regs.rip, state.regs.rsp });

    state.run();

    output.human("\nStatus:\n", .{});
    output.human("✓ Mach-O loaded\n", .{});
    output.human("✓ Imports initialized\n", .{});
    if (state.exit_code == 0 and !state.faulted) {
        output.human("✓ Guest execution completed\n", .{});
    } else {
        output.human("✗ Guest execution stopped (exit code {d})\n", .{state.exit_code});
    }
    if (state.pthreads.blocked_threads != 0) {
        output.human("✗ Waiting guest threads: {d}\n", .{state.pthreads.blocked_threads});
    }

    machoCapturePrint(
        "macho-processor: execution finished: exit_code={d}, faulted={}, terminated={}, reason={s}, active_thread=0x{x}, blocked_threads={d}, suspended_contexts={d}\n",
        .{
            state.exit_code,
            state.faulted,
            state.terminated,
            @tagName(exit_diagnostics.reasonFromValue(state.termination_reason)),
            state.active_guest_thread,
            state.pthreads.blocked_threads,
            state.suspended_guest_thread_count,
        },
    );
    if (state.host_termination_signal != 0) {
        // A host-requested stop is precisely when the live scheduler and
        // callback ownership state is most valuable. Do not bypass these
        // compact summaries merely because the guest did not return normally.
        state.sdl.logSummary();
        state.pthreads.logSummary();
        state.logCooperativeSchedulerSummary();
        machoCapturePrint(
            "macho-processor: graceful host-termination diagnostics complete; returning signal-compatible status={d} without classifying the live guest RIP as a crash\n",
            .{state.exit_code},
        );
        macho_log.checkPointSync();
        return state.exit_code;
    }
    state.logDecodeCacheSummary();
    state.logPerformanceAccelerationSummary();
    state.import_resolver.logSummary();
    state.foreign_objects.logSummary();
    state.sdl.logSummary();
    state.native_window.logSummary();
    state.dynamic_forwarder.logSummary();
    state.fs_forwarder.logSummary();
    state.libcxx_filesystem.logSummary();
    state.libcxx_streams.logSummary();
    state.logging.logSummary();
    state.backend_diagnostics.logSummary();
    state.xenia_pipeline.logSummary(state.executed_steps);
    state.xenia_gpu_handoff.logSummary(state.executed_steps);
    state.logReadyCompilerSummary();
    // The run is over, so "still unclassified" has stopped meaning "not yet"
    // and started meaning "the pipeline never advanced past it". Sealing before
    // the frontier report is what turns the ledger from a permanent blocker
    // into a verdict the report can carry.
    const newly_implicated = state.anomalies.seal();
    if (newly_implicated != 0) {
        machoCapturePrint(
            "macho-processor: anomaly ledger sealed at step={d}: {d} record(s) become IMPLICATED because no pipeline milestone was reached after them. The last structural progress was at step={d}; these are the anomalies the run did not get past\n",
            .{ state.executed_steps, newly_implicated, state.anomalies.last_advance_step },
        );
    }
    state.logGraphicsFrontier(true);
    state.pthreads.logSummary();
    state.logCooperativeSchedulerSummary();
    state.memory_forwarder.logSummary();
    state.logLiveVtableGuardSummary();
    state.import_binding_predictor.dump("exit");
    state.launch_options.logSummary();
    state.startup.logSummary();
    state.startup.timingSummary();
    state.smart_stubs.logSummary();
    state.symbol_assembly.logSummary();
    state.cxx_exceptions.logSummary();
    state.spirv_cross.logSummary();
    state.unwinder.logSummary();
    state.dynamic_casts.logSummary();
    state.diagnostic_text.logSummary();
    state.pthreads.logSummary();
    state.tlv.logSummary();
    state.sparse_memory.logSummary();
    if (state.guest_log_repetition.active()) {
        macho_log.machoCapturePrint(
            "macho-processor: guest log mirror repetition: suppressed_lines={d} runs={d} longest_run={d} truncated_comparisons={d}; a collapsed run is a guest loop that logs, and its length is the finding — the copies were not\n",
            .{
                state.guest_log_repetition.suppressed,
                state.guest_log_repetition.runs,
                state.guest_log_repetition.longest_run,
                state.guest_log_repetition.truncated_comparisons,
            },
        );
    }
    if (state.guest_log_cycles.active()) {
        macho_log.machoCapturePrint(
            "macho-processor: guest log cycles: reports={d} longest_period={d} most_iterations={d} still_cycling={} final_period={d}; a run that ends inside a cycle ended in a livelock, not at a conclusion\n",
            .{
                state.guest_log_cycles.reports,
                state.guest_log_cycles.longest_period,
                state.guest_log_cycles.most_iterations,
                state.guest_log_cycles.period != 0,
                state.guest_log_cycles.period,
            },
        );
    }
    // The wait-cycle predictor is the health checker for exactly the run the
    // cycle detector just described: name the objects the guest was cycling on
    // (wait/set/release, with counts and steps) so the loop is an address, not
    // a description. Always dumped so a healthy run reads as "no signatures".
    state.livelock_predictor.dump(&state, "exit");
    state.livelock_predictor.dumpRecent(&state);
    if (state.guest_modules.active()) {
        macho_log.machoCapturePrint(
            "macho-processor: guest module map: images={d} overflowed={d} failed_load_transactions={d}; only explicit post-call status/handle results are counted, never pre-call out-parameter values\n",
            .{
                state.guest_modules.count,
                state.guest_modules.overflowed,
                state.guest_modules.failed_loads,
            },
        );
        for (state.guest_modules.modules[0..state.guest_modules.count]) |*module| {
            if (!module.active) continue;
            macho_log.machoCapturePrint(
                "macho-processor:   module {s} base=0x{x} size=0x{x} loads(ok/failed)={d}/{d} last_handle=0x{x}\n",
                .{ module.nameSlice(), module.base, module.size, module.loads_succeeded, module.loads_failed, module.last_handle },
            );
        }
    }
    if (state.guest_log_line_count != 0) {
        macho_log.machoCapturePrint(
            "macho-processor: synchronous guest log bridge: mirrored_lines={d}\n",
            .{state.guest_log_line_count},
        );
    }
    if (state.guest_stdio_write_count != 0) {
        machoCapturePrint(
            "macho-processor: guest stdio capture: writes={d} stdout_bytes={d} stderr_bytes={d} log_mirror_active={} mirror_failures={d}\n",
            .{
                state.guest_stdio_write_count,
                state.guest_stdout_byte_count,
                state.guest_stderr_byte_count,
                state.guest_log_mirror_fd >= 0,
                state.guest_stdio_mirror_failures,
            },
        );
    }
    if (state.guest_stdio_read_count != 0 or state.guest_stdio_seek_count != 0 or state.guest_stdio_failures != 0) {
        machoCapturePrint(
            "macho-processor: guest stdio input: reads={d} bytes={d} seeks={d} failures={d}\n",
            .{ state.guest_stdio_read_count, state.guest_stdio_read_bytes, state.guest_stdio_seek_count, state.guest_stdio_failures },
        );
    }

    if (state.unresolved_import_count != 0) {
        const end = if (state.import_trace_filled) IMPORT_TRACE_BUFFER_LEN else state.import_trace_index;
        for (0..end) |i| {
            const entry = state.import_trace_entries[i];
            if (entry.caller_symbol.len != 0) {
                machoCapturePrint(
                    "macho-processor: unresolved import #{d}: {s} from {s}; stub=0x{x} return=0x{x} caller={s}+0x{x} synthesized_rax=0x{x}\n",
                    .{ i, entry.symbol, entry.dylib, entry.stub_address, entry.return_address, entry.caller_symbol, entry.caller_offset, entry.synthetic_result },
                );
            } else {
                machoCapturePrint(
                    "macho-processor: unresolved import #{d}: {s} from {s}; stub=0x{x} return=0x{x} synthesized_rax=0x{x}\n",
                    .{ i, entry.symbol, entry.dylib, entry.stub_address, entry.return_address, entry.synthetic_result },
                );
            }
        }
    }

    if (state.unresolved_import_count != 0 and !state.faulted) {
        machoCapturePrint(
            "macho-processor: runtime incomplete: {d} unresolved import call(s); guest exit {d} is diagnostic only, returning processor status {d}\n",
            .{ state.unresolved_import_count, state.exit_code, UNSUPPORTED_RUNTIME_EXIT_CODE },
        );
        return UNSUPPORTED_RUNTIME_EXIT_CODE;
    }

    return state.exit_code;
}

fn extractX8664Slice(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    return fat.extractX8664Slice(allocator, data) catch |err| {
        if (err == error.NotMachO) return error.NotMachO;
        if (err == error.NoX86_64Slice) {
            machoCapturePrint("macho-processor: no x86_64 slice found in fat binary\n", .{});
            return error.NoX86_64Slice;
        }
        return err;
    };
}

fn isApplicationControlFlow(op: Op) bool {
    return switch (op) {
        .call_rel32,
        .call_mem64,
        .call_reg64,
        .ret,
        .jmp_rel8,
        .jcc_rel8,
        .jcc_rel32,
        .jmp_mem64,
        .jmp_reg64,
        .syscall,
        .ud2,
        .hlt,
        => true,
        else => false,
    };
}

const decodeInsn = macho_core.decoder.decodeInsn;
const decodeInsnCompat = macho_core.decoder.decodeInsnCompat;

test "application control-flow trace classifier covers direct and indirect transfers" {
    try std.testing.expect(isApplicationControlFlow(.call_rel32));
    try std.testing.expect(isApplicationControlFlow(.call_mem64));
    try std.testing.expect(isApplicationControlFlow(.jmp_reg64));
    try std.testing.expect(isApplicationControlFlow(.jcc_rel32));
    try std.testing.expect(isApplicationControlFlow(.ret));
    try std.testing.expect(!isApplicationControlFlow(.mov_reg64_reg64));
}

test {
    _ = @import("decoder_tests.zig");
}
test "dyld data bindings materialize callable constant and GOT slots" {
    const constant_section = macho_metadata.Section{
        .name = "__const",
        .segment_name = "__DATA_CONST",
        .address = 0x1000,
        .size = 0x100,
        .file_offset = 0,
        .flags = 0,
        .indirect_symbol_start = 0,
        .stub_size = 0,
    };
    var got_section = constant_section;
    got_section.name = "__got";
    var data_section = constant_section;
    data_section.name = "__data";
    data_section.segment_name = "__DATA";

    try std.testing.expect(MachOState.isCallableConstantBinding(
        constant_section,
        "__ZNKSt3__123__match_any_but_newlineIcE6__execERNS_7__stateIcEE",
        false,
    ));
    try std.testing.expect(MachOState.isCallableConstantBinding(constant_section, "_strcmp", true));
    try std.testing.expect(!MachOState.isCallableConstantBinding(constant_section, "__ZTVN10__cxxabiv117__class_type_infoE", false));
    try std.testing.expect(MachOState.isCallableConstantBinding(got_section, "_strcmp", true));
    try std.testing.expect(MachOState.isCallableConstantBinding(data_section, "_calloc", true));
    try std.testing.expect(!MachOState.isCallableConstantBinding(data_section, "_ordinary_data", false));
    try std.testing.expect(MachOState.isWritableDataSection(data_section));
    try std.testing.expect(!MachOState.isCallableConstantBinding(got_section, "___stack_chk_guard", false));
    try std.testing.expect(MachOState.isAbiDataSymbol("__ZTTNSt3__114basic_ifstreamIcNS_11char_traitsIcEEEE"));
    try std.testing.expect(MachOState.isBridgedLibcppDataSymbol("__ZTVNSt3__19basic_iosIcNS_11char_traitsIcEEEE"));
    try std.testing.expect(!MachOState.isBridgedLibcppDataSymbol("__ZTVN10__cxxabiv117__class_type_infoE"));
    try std.testing.expect(MachOState.bindingRequiresBoundThunk(got_section, false));
    try std.testing.expect(!MachOState.bindingRequiresBoundThunk(constant_section, false));
    try std.testing.expect(MachOState.bindingRequiresBoundThunk(constant_section, true));
}

test "near-null XModule recovery guard is limited to Matches" {
    try std.testing.expect(MachOState.isXModuleMatchesSymbol(
        "__ZNK2xe6kernel7XModule7MatchesENSt3__117basic_string_viewIcNS2_11char_traitsIcEEEE",
    ));
    try std.testing.expect(!MachOState.isXModuleMatchesSymbol("__ZN2xe6kernel7XModuleC1Ev"));
    try std.testing.expect(!MachOState.isXModuleMatchesSymbol("__ZNSt3__16locale9use_facetEv"));
}

test "generated null scalar read gate is limited to small loads" {
    try std.testing.expect(memory_access.isGeneratedNullScalarLoadOp(x64_decoder.Op.mov_reg8_mem8));
    try std.testing.expect(memory_access.isGeneratedNullScalarLoadOp(x64_decoder.Op.mov_reg16_mem16));
    try std.testing.expect(memory_access.isGeneratedNullScalarLoadOp(x64_decoder.Op.mov_reg32_mem32));
    // 64-bit loads are owned by the vtable/XModule recovery paths and must not
    // be zero-filled by the generated-code scalar read recovery.
    try std.testing.expect(!memory_access.isGeneratedNullScalarLoadOp(x64_decoder.Op.mov_reg64_mem64));
    try std.testing.expect(!memory_access.isGeneratedNullScalarLoadOp(x64_decoder.Op.movbe_reg_mem));
    try std.testing.expect(!memory_access.isGeneratedNullScalarLoadOp(x64_decoder.Op.mov_mem32_reg32));
}

test "generated null transfer gate is limited to indirect jmp/call ops" {
    try std.testing.expect(memory_access.isGeneratedNullTransferOp(x64_decoder.Op.jmp_reg64));
    try std.testing.expect(memory_access.isGeneratedNullTransferOp(x64_decoder.Op.call_reg64));
    try std.testing.expect(memory_access.isGeneratedNullTransferOp(x64_decoder.Op.jmp_mem64));
    try std.testing.expect(memory_access.isGeneratedNullTransferOp(x64_decoder.Op.call_mem64));
    // Direct transfers and non-transfer ops stay owned by their own paths;
    // the generated null transfer recovery must never claim them.
    try std.testing.expect(!memory_access.isGeneratedNullTransferOp(x64_decoder.Op.jmp_rel8));
    try std.testing.expect(!memory_access.isGeneratedNullTransferOp(x64_decoder.Op.ret));
    try std.testing.expect(!memory_access.isGeneratedNullTransferOp(x64_decoder.Op.mov_reg32_mem32));
}

test "generated guest dispatch gate includes ret; null transfer gate stays jmp/call" {
    // The guest-dispatch recovery also covers `ret` (a corrupt-frame return
    // that pops a guest sentinel), while the null transfer gate stays
    // jmp/call-only.
    try std.testing.expect(memory_access.isGeneratedDispatchMissOp(x64_decoder.Op.ret));
    try std.testing.expect(memory_access.isGeneratedDispatchMissOp(x64_decoder.Op.jmp_reg64));
    try std.testing.expect(memory_access.isGeneratedDispatchMissOp(x64_decoder.Op.call_mem64));
    try std.testing.expect(!memory_access.isGeneratedDispatchMissOp(x64_decoder.Op.jmp_rel8));
    try std.testing.expect(!memory_access.isGeneratedDispatchMissOp(x64_decoder.Op.mov_reg32_mem32));
    try std.testing.expect(!memory_access.isGeneratedNullTransferOp(x64_decoder.Op.ret));
}

test "function-exit epilogue bytes detect Xenia dead tail-dispatch epilogue" {
    // `add rsp, 0x68; dec [rsi-0x14]; ret` — exactly the bytes observed after
    // the null `jmp rax` at 0xa0059876 (the CALL_POSSIBLE_RETURN path).
    const epilogue: []const u8 = &.{ 0x48, 0x83, 0xC4, 0x68, 0xFF, 0x4E, 0xEC, 0xC3 };
    try std.testing.expect(memory_access.isFunctionExitEpilogueBytes(epilogue));
    // imm32 teardown with no profiler decrement. `48 81 C4` is REX.W, opcode
    // and ModRM — three bytes — so with a four-byte immediate the `ret` sits at
    // index 7, not 8. The recognizer was corrected from 8 to 7 (see the comment
    // on `isFunctionExitEpilogue`, where an offset of 8 skipped past the `ret`
    // and made every large-frame epilogue unrecognisable); this assertion kept
    // the pre-fix arithmetic and a padding byte to match it, and never ran to
    // say so.
    try std.testing.expect(memory_access.isFunctionExitEpilogueBytes(&.{ 0x48, 0x81, 0xC4, 0x68, 0x01, 0x00, 0x00, 0xC3 }));
    // And the padded form the old arithmetic expected is correctly rejected:
    // the byte at the `ret` position is a zero.
    try std.testing.expect(!memory_access.isFunctionExitEpilogueBytes(&.{ 0x48, 0x81, 0xC4, 0x68, 0x01, 0x00, 0x00, 0x00, 0xC3 }));
    // Truncated buffers (length guards before byte reads) must not panic.
    try std.testing.expect(!memory_access.isFunctionExitEpilogueBytes(&.{ 0x48, 0x83, 0xC4, 0x68, 0xFF }));
    try std.testing.expect(!memory_access.isFunctionExitEpilogueBytes(&.{ 0x48, 0x81, 0xC4 }));
    // A `jmp` is not an epilogue.
    try std.testing.expect(!memory_access.isFunctionExitEpilogueBytes(&.{ 0xFF, 0xE0, 0x48, 0x83, 0xC4, 0x68 }));
    // `sub rsp` is a prologue, not a teardown.
    try std.testing.expect(!memory_access.isFunctionExitEpilogueBytes(&.{ 0x48, 0x83, 0xEC, 0x68, 0xC3 }));
    // add rsp without a terminating ret is not a function exit.
    try std.testing.expect(!memory_access.isFunctionExitEpilogueBytes(&.{ 0x48, 0x83, 0xC4, 0x68 }));
}

test "generated guest dispatch gate recognizes Xenia module sentinel addresses" {
    // Unpatched indirection sentinels are guest-module addresses in either the
    // zero-extended (0x82582cc8) or sign-extended (0xffffffff8313e528) form of
    // the guest PPC function address.
    try std.testing.expect(memory_access.isGuestModuleAddress(0x82582cc8));
    try std.testing.expect(memory_access.isGuestModuleAddress(0xffffffff8313e528));
    try std.testing.expect(memory_access.isGuestModuleAddress(0x80000000)); // xboxkrnl.exe base
    try std.testing.expect(memory_access.isGuestModuleAddress(0x801c0000)); // xam.xex base
    try std.testing.expect(memory_access.isGuestModuleAddress(0x9fffffff)); // guest RAM end
    // Mach-O text, host JIT mappings, and null are not guest module addresses.
    try std.testing.expect(!memory_access.isGuestModuleAddress(0x13fa70));
    try std.testing.expect(!memory_access.isGuestModuleAddress(0x6778000));
    try std.testing.expect(!memory_access.isGuestModuleAddress(0));
    try std.testing.expect(!memory_access.isGuestModuleAddress(0x7fff2000));
    try std.testing.expect(!memory_access.isGuestModuleAddress(0xa0000000));
    // A genuine 64-bit host pointer whose low 32 bits fall in the guest window
    // is NOT a guest sentinel and must not be skipped by the recovery.
    try std.testing.expect(!memory_access.isGuestModuleAddress(0x1082582cc8));
}

test "generated null scalar read address form gate accepts zero-base 0x67 forms" {
    // `67 8B 03` = mov eax, dword ptr [ebx] with a 0x67 address-size override
    // and EBX=0 is the exact Xenia perf_monitor_detailed_metrics fault shape:
    // the structural gate must recognize the address form. Live recovery then
    // gives this exact EAX-from-EBX layout exclusively to the bounded dispatch
    // transducer; it is never handled by the generic zero-fill fallback.
    const fault = x64_decoder.DecodedInsn{
        .op = x64_decoder.Op.mov_reg32_mem32,
        .addr = 0,
        .sib_has_base = true,
        .sib_base_reg = .bl_bx_ebx_rbx,
        .has_0x67 = true,
    };
    try std.testing.expect(memory_access.isGeneratedNullScalarAddressForm(fault));

    // A 64-bit load keeps its vtable/XModule ownership.
    var wide = fault;
    wide.op = x64_decoder.Op.mov_reg64_mem64;
    try std.testing.expect(!memory_access.isGeneratedNullScalarAddressForm(wide));

    // Indexed or RIP-relative forms are not base-only zero expressions.
    var indexed = fault;
    indexed.sib_has_index = true;
    indexed.sib_index_reg = .r12b_r12w_r12d_r12;
    try std.testing.expect(!memory_access.isGeneratedNullScalarAddressForm(indexed));
    var rip_rel = fault;
    rip_rel.rip_relative = true;
    try std.testing.expect(!memory_access.isGeneratedNullScalarAddressForm(rip_rel));

    // Non-zero displacement disqualifies (the endian contract or termination
    // owns non-zero effective addresses).
    var displaced = fault;
    displaced.addr = 0x40;
    try std.testing.expect(!memory_access.isGeneratedNullScalarAddressForm(displaced));

    // A non-0x67 zero-base form still qualifies.
    var plain = fault;
    plain.has_0x67 = false;
    try std.testing.expect(memory_access.isGeneratedNullScalarAddressForm(plain));
}

test "Mach-O PAGEZERO is excluded from guest memory" {
    try std.testing.expectEqual(@as(?u64, null), mappedOffset(0, 0x2000_0000, 0x4000, 0));
    try std.testing.expectEqual(@as(?u64, null), mappedOffset(0, 0x2000_0000, 0x4000, 0x30));
    try std.testing.expectEqual(@as(?u64, 0x4000), mappedOffset(0, 0x2000_0000, 0x4000, 0x4000));
    try std.testing.expectEqual(@as(?u64, null), mappedOffset(0, 0x2000_0000, 0x4000, 0xffff_ffff_ffff_ffe8));
    try std.testing.expectEqual(@as(?u64, null), mappedOffset(0, 0x2000_0000, 0x4000, 0x800));
}

test "the faulting context is pinned once and survives later scheduling" {
    const near_null_causality = @import("process_core").near_null_causality;
    var state = struct {
        active_guest_thread: u64 = 0,
        executed_steps: u64 = 0,
        fault_context_pinned: bool = false,
        fault_context_thread: u64 = 0,
        fault_context_step: u64 = 0,
        execution_history_epoch: u64 = 0,
        fault_context_history_epoch: u64 = 0,
    }{};

    // Before any fault, reporters see the live context.
    state.active_guest_thread = 0x7FFF_20E0;
    state.executed_steps = 100;
    state.execution_history_epoch = 4;
    try std.testing.expectEqual(@as(u64, 0x7FFF_20E0), near_null_causality.faultContextThread(&state));

    // The fault fixes the identity.
    near_null_causality.pinFaultContext(&state);
    try std.testing.expectEqual(@as(u64, 0x7FFF_20E0), state.fault_context_thread);
    try std.testing.expectEqual(@as(u64, 100), state.fault_context_step);
    try std.testing.expectEqual(@as(u64, 4), state.fault_context_history_epoch);

    // Teardown may run the cooperative scheduler, moving the active context.
    // Every later block must still report the thread that actually faulted —
    // this disagreement is what let one crash report name two threads for one
    // fault, and made the causality chain walk a tape that was not the
    // faulting thread's.
    state.active_guest_thread = 0x7FFF_2080;
    state.executed_steps = 4_755_591_826;
    state.execution_history_epoch = 9;
    near_null_causality.pinFaultContext(&state);
    try std.testing.expectEqual(@as(u64, 0x7FFF_20E0), near_null_causality.faultContextThread(&state));
    try std.testing.expectEqual(@as(u64, 0x7FFF_20E0), state.fault_context_thread);
    try std.testing.expectEqual(@as(u64, 100), state.fault_context_step);
    try std.testing.expectEqual(@as(u64, 4), state.fault_context_history_epoch);

    // A handled guest fault closes the transaction. The next fault must pin
    // its own context and continuity epoch rather than inherit this one.
    near_null_causality.clearFaultContext(&state);
    try std.testing.expect(!state.fault_context_pinned);
    state.active_guest_thread = 0x7FFF_2080;
    state.executed_steps = 200;
    state.execution_history_epoch = 9;
    near_null_causality.pinFaultContext(&state);
    try std.testing.expectEqual(@as(u64, 0x7FFF_2080), state.fault_context_thread);
    try std.testing.expectEqual(@as(u64, 200), state.fault_context_step);
    try std.testing.expectEqual(@as(u64, 9), state.fault_context_history_epoch);
}

test "SDL audio callback stack is independent from the shared UI stack" {
    const FakeSdl = struct {
        in_flight: bool = false,
        handle: u64 = 0,
        pub fn audioCallbackInFlight(self: *const @This()) bool {
            return self.in_flight;
        }
        pub fn audioCallbackHandle(self: *const @This()) u64 {
            return if (self.in_flight) self.handle else 0;
        }
    };
    const FakeState = struct {
        active_idle_source: u64 = 0,
        sdl: FakeSdl = .{},
    };

    var state = FakeState{};
    try std.testing.expect(!scheduling.syntheticCallbackStackBusy(&state));
    try std.testing.expectEqual(@as(u64, 0), scheduling.syntheticCallbackStackOwner(&state));

    // A GTK idle source holds the stack, and keeps holding it while suspended:
    // `active_idle_source` is not cleared by a suspension, only by the return.
    state.active_idle_source = 20;
    try std.testing.expect(scheduling.syntheticCallbackStackBusy(&state));
    try std.testing.expectEqual(
        types.IDLE_CALLBACK_HANDLE_BASE + 20,
        scheduling.syntheticCallbackStackOwner(&state),
    );

    // SDL runs audio callbacks on another thread. Rosette mirrors that with a
    // dedicated guest stack, so an in-flight audio callback must not claim or
    // pin the GTK stack.
    state.active_idle_source = 0;
    state.sdl = .{ .in_flight = true, .handle = 0xFFFF_F910_0000_0000 };
    try std.testing.expect(!scheduling.syntheticCallbackStackBusy(&state));
    try std.testing.expectEqual(@as(u64, 0), scheduling.syntheticCallbackStackOwner(&state));

    // The scheduler must also stop electing idle work it cannot dispatch,
    // otherwise the refusal turns into an unbounded rotation.
    try std.testing.expectEqual(scheduler.CooperativeWork.suspended_thread, scheduler.chooseCooperativeWork(.{
        .pending_idle = 1,
        .idle_dispatch_blocked = true,
        .suspended_threads = 1,
    }));

    state.sdl = .{};
    try std.testing.expect(!scheduling.syntheticCallbackStackBusy(&state));
}

test "cooperative idle wake preempts a running worker after all pthreads have started" {
    try std.testing.expectEqual(scheduler.CooperativeWork.gtk_idle, scheduler.chooseCooperativeWork(.{ .pending_idle = 1 }));
    try std.testing.expectEqual(scheduler.CooperativeWork.gtk_idle, scheduler.chooseCooperativeWork(.{ .pending_idle = 1, .deferred_threads = 3 }));
    try std.testing.expectEqual(scheduler.CooperativeWork.none, scheduler.chooseCooperativeWork(.{ .pending_idle = 1, .idle_callback_running = true }));
    try std.testing.expectEqual(scheduler.CooperativeWork.none, scheduler.chooseCooperativeWork(.{ .idle_callback_running = true, .deferred_threads = 1, .suspended_threads = 2 }));
    try std.testing.expectEqual(scheduler.CooperativeWork.deferred_thread, scheduler.chooseCooperativeWork(.{ .deferred_threads = 1, .suspended_threads = 2 }));
    try std.testing.expectEqual(scheduler.CooperativeWork.suspended_thread, scheduler.chooseCooperativeWork(.{ .suspended_threads = 2 }));
    try std.testing.expectEqual(scheduler.CooperativeWork.none, scheduler.chooseCooperativeWork(.{}));
}

test "cooperative idle diagnostics retain the oldest queued callback provenance" {
    const callbacks = [_]IdleCallback{
        .{ .source_id = 7, .function = 0x7000, .active = true, .tag = "newer", .scheduled_step = 90, .scheduling_thread = 0x77, .scheduling_rip = 0x777 },
        .{},
        .{ .source_id = 3, .function = 0x3000, .active = true, .tag = "presenter", .scheduled_step = 40, .scheduling_thread = 0x33, .scheduling_rip = 0x333 },
    };
    const snapshot = idleQueueSnapshotFor(&callbacks);
    try std.testing.expectEqual(@as(usize, 2), snapshot.pending);
    try std.testing.expectEqual(@as(u64, 3), snapshot.oldest_source);
    try std.testing.expectEqual(@as(u64, 0x3000), snapshot.oldest_callback);
    try std.testing.expectEqual(@as(u64, 40), snapshot.oldest_scheduled_step);
    try std.testing.expectEqual(@as(u64, 0x33), snapshot.oldest_scheduling_thread);
    try std.testing.expectEqual(@as(u64, 0x333), snapshot.oldest_scheduling_rip);
    try std.testing.expectEqualStrings("presenter", snapshot.oldest_tag);
}

pub fn main(init: std.process.Init) !void {
    // Install the native fault handler before anything else can fault: a
    // crash in Rosette's own host code used to die with status 139 and no
    // crash point, and the runtime log opens only inside loadAndRun. This
    // handler writes a report (host regs, backtrace, last guest progress) to
    // .rosette/rosette-crash.log and stderr, then re-raises so supervisors
    // that key on the signal-compatible status keep working.
    native_crash.install();
    native_crash.recordPhase("main");

    const allocator = init.arena.allocator();

    if (environmentFlag("ROSETTE_MACHO_VERBOSE_STDOUT")) {
        const executable_path = std.process.executablePathAlloc(init.io, allocator) catch null;
        machoCapturePrint(
            "scheduler: runtime integration active version=ui-handoff-v2 optimize={s} executable={s}\n",
            .{ @tagName(builtin.mode), if (executable_path) |path| path else "<unavailable>" },
        );
    }

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    if (args.len < 2) {
        machoCapturePrint("usage: macho_processor <binary> [args...]\n", .{});
        std.process.exit(1);
    }

    const exit_code = try loadAndRun(init.io, allocator, .{
        .path = args[1],
        .args = args[2..],
    });
    const process_status: u8 = if (exit_code <= std.math.maxInt(u8)) @intCast(exit_code) else UNSUPPORTED_RUNTIME_EXIT_CODE;
    if (process_status != exit_code) {
        machoCapturePrint("macho-processor: normalized non-status exit value 0x{x} to {d}\n", .{ exit_code, process_status });
    }
    std.process.exit(process_status);
}
