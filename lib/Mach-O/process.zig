const std = @import("std");
const builtin = @import("builtin");

extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

const fcntl_c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
});

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
const diagnostics_execution_profile = @import("diagnostics").execution_profile;
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
const macos_host_contract = @import("rosette_macos_host_contract");
const xenia_pipeline = @import("diagnostics").xenia_pipeline;
const xenia_gpu_handoff = @import("diagnostics").xenia_gpu_handoff;
const xenia_gpu_causal_trace = @import("diagnostics").xenia_gpu_causal_trace;
const xenia_pm4_walk = @import("diagnostics").xenia_pm4_walk;
const graphics_health_contract = @import("diagnostics").graphics_health_contract;
const application_controller = @import("diagnostics").application_controller;
const application_framework = @import("application_framework");
const xenia_memory_views = @import("diagnostics").xenia_memory_views;
const guest_wait_liveness = @import("diagnostics").guest_wait_liveness;
const deadlock_predictor = @import("diagnostics").deadlock_predictor;
const deferred_work = @import("diagnostics").deferred_work;
const guest_exception_ledger = @import("diagnostics").guest_exception_ledger;
const guest_status_ledger = @import("diagnostics").guest_status_ledger;
const unknown_inventory_mod = @import("diagnostics").unknown_inventory;
const sync_object_identity = @import("diagnostics").sync_object_identity;
const wait_audit = @import("diagnostics").wait_audit;
const host_contract_coverage = @import("diagnostics").host_contract_coverage;
const stall_release = @import("diagnostics").stall_release;
const bringup_failure = @import("diagnostics").bringup_failure;
const run_horizon = @import("diagnostics").run_horizon;
const claim_reconciliation = @import("diagnostics").claim_reconciliation;
const interrupt_callback_transaction = @import("diagnostics").interrupt_callback_transaction;
const async_log = @import("diagnostics").async_log;
const translation_economics = @import("diagnostics").translation_economics;
const run_integrity = @import("diagnostics").run_integrity;
const substantiation = @import("diagnostics").substantiation;
const guest_log_channels = @import("diagnostics").guest_log_channels;
const wait_graph = @import("diagnostics").wait_graph;
const event_identity = @import("diagnostics").event_identity;
const execution_tracepoints = @import("diagnostics").execution_tracepoints;
const mandatory_order = @import("diagnostics").mandatory_order;
const monotone_witness = @import("diagnostics").monotone_witness;
const pipeline_evidence = @import("diagnostics").pipeline_evidence;
const fault_pause_transaction = @import("diagnostics").fault_pause_transaction;
const sync_object_registry = @import("diagnostics").sync_object_registry;
const run_journal = @import("diagnostics").run_journal;
const durable_journal = @import("diagnostics").durable_journal;
const run_closure = @import("diagnostics").run_closure;
const execution_provenance = @import("diagnostics").execution_provenance;
const guest_alias_contract = @import("diagnostics").guest_alias_contract;
const storage_integrity = @import("diagnostics").storage_integrity;
const run_budget = @import("diagnostics").run_budget;
const run_manifest = @import("diagnostics").run_manifest;
const fatal_conditions = @import("diagnostics").fatal_conditions;
const xiso_preflight = @import("diagnostics").xiso_preflight;
const xiso_format = @import("xenia_xiso_format");
const kernel_service_readiness = @import("diagnostics").kernel_service_readiness;
const import_integrity = @import("diagnostics").import_integrity;
const acceptance_gates = @import("diagnostics").acceptance_gates;
const timeout_fidelity = @import("diagnostics").timeout_fidelity;
const signal_expectation = @import("diagnostics").signal_expectation;
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
const register_map = @import("xenos_register_map");
const ownership_contract = gpu.ownership_contract;
const device_tree = @import("device_tree");
const guest_structure = @import("guest_structure");
const execution_history = @import("execution_history");
const ExecutionHistory = execution_history.History(TraceEntry);
const crash_diag = @import("process_core").crash_diag;

/// How close a bounded poll's first expiry has to be to the producer's last
/// ring advance before the two are reported as the same event.
///
/// The observed pair is nine million steps apart — the title published its
/// batch and started waiting on the same submission. A window of fifty
/// million is generous enough to survive the sampling in between and far too
/// tight to join a poll that belongs to an unrelated part of the title.
const bootstrap_poll_join_steps: u64 = 50_000_000;

/// Execution context captured at the first armed and first violated
/// checkpoint of an integrity invariant. The predicate snapshot lives in the
/// integrity ledger; this is the machine context that tells us which guest
/// instruction was active when that snapshot became actionable.
const RunIntegrityContext = struct {
    valid: bool = false,
    rip: u64 = 0,
    thread: u64 = 0,
};

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
const translation_cache = @import("macho_core").translation_cache;
const translation_domain = @import("macho_core").translation_domain;
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
    completion_mode: scheduler.UiHandoffCompletionMode = .rendezvous,
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
    // AVX-512 exposes sixteen architectural vector registers plus the
    // EVEX R'/B/X extensions (zmm16-zmm31). Keep the complete register file
    // in the interpreter state so a decoded high-register operand cannot
    // alias or index past the legacy XMM/YMM arrays.
    xmm: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    // AVX-512 opmask registers (k0-k7). k0 is always all-1s when read as
    // a mask operand; k1-k7 hold actual mask values for predicated operations.
    k: [8]u64 = [_]u64{0xFFFF_FFFF_FFFF_FFFF} ** 8,
    ymm_hi: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    zmm_hi: [32][32]u8 = [_][32]u8{[_]u8{0} ** 32} ** 32,
    cpu_profile: x64_decoder.capabilities.Profile = .xenia,
    compat: compat_runtime.Runtime = .{},
    terminated: bool = false,
    exit_code: u64 = 0,
    faulted: bool = false,
    /// A drawable extent mismatch is a non-bypassable host/guest contract
    /// fault. Keep a separate guard so a returning signal handler or a later
    /// diagnostic checkpoint cannot re-enter the failed presentation path.
    graphics_extent_contract_faulted: bool = false,
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
    /// Fingerprint of the last near-null status line. The status is emitted
    /// even when no casualty occurred, so a final report can distinguish
    /// "observer saw no qualifying event" from "the observer was never
    /// consulted" without repeating a wall-clock-only line every checkpoint.
    near_null_status_last_fingerprint: u64 = std.math.maxInt(u64),
    /// Guest wait-cycle signatures observed through the mirrored guest log
    /// (KeWaitForSingleObject/KeSetEvent/KeReleaseSemaphore). A signature
    /// whose count grows while the ring write pointer is stalled is a
    /// livelock prediction — the guest is parked on an object nobody will
    /// ever signal. See `livelock_predictor.zig`; reached only from the
    /// guest-log bridge, never from the instruction stream.
    livelock_predictor: livelock_predictor.Predictor = .{},
    /// Legacy single-slot fallback for synthetic states that do not expose the
    /// per-thread table below. Mach-O uses the table so interleaved guest log
    /// producers cannot steal one another's wait identity.
    livelock_pending_wait_object: u64 = 0,
    /// Per-guest-thread replacement for the legacy scalar breadcrumb above.
    /// Guest diagnostic lines may interleave; pairing by thread prevents one
    /// wait result from consuming another thread's object identity.
    livelock_pending_waits: [guest_log.pending_wait_capacity]guest_log.PendingWait =
        [_]guest_log.PendingWait{.{}} ** guest_log.pending_wait_capacity,
    livelock_pending_wait_active: u32 = 0,
    livelock_pending_wait_dropped: u64 = 0,
    livelock_pending_wait_unmatched_results: u64 = 0,
    livelock_pending_wait_identity_conflicts: u64 = 0,
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
    /// Xenia's formatting buffer is thread-local by contract. A process-global
    /// address allowed cooperative guest threads to splice two records into a
    /// false wait/PM4 line before either append completed.
    guest_log_channels: guest_log_channels.Registry = .{},
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
    /// Bounded, text-boundary health account for Xenia's JIT. The guest-log
    /// bridge is the only place this is fed; no per-instruction JIT scanning is
    /// added to the interpreter hot loop.
    jit_health: jit.JitHealth = .{},
    /// A JIT health fault is terminal and must be reported exactly once.  The
    /// guard also protects the diagnostic path if a signal handler returns and
    /// the failed host operation unwinds farther than expected.
    jit_health_faulted: bool = false,
    /// Readiness failures are a separate contract from JIT health. Keep their
    /// terminal path independently guarded so a compiler diagnostic cannot be
    /// logged repeatedly if the heartbeat is re-entered after a signal handler
    /// returns.
    ready_compiler_faulted: bool = false,
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
    /// The image-wide subsystem census is retained so the graphics preflight
    /// can consume the same evidence without walking the symbol table twice.
    prelaunch_audit_summary: ?preflight_lib.prelaunch_audit.Summary = null,
    /// Static graphics readiness established after the image is indexed, host
    /// capabilities are probed, and the full graphics boundary observer set is
    /// sealed.  This is deliberately separate from the runtime graphics
    /// ledger: a ready static image is not evidence that the guest has reached
    /// VdSwap, and an untested runtime path is not allowed to masquerade as a
    /// static link failure.
    graphics_preflight_report: preflight_lib.graphics_readiness.Report = .{},
    /// Results of the executable host/guest graphics path tests performed at
    /// admission. This is separate from the static report above and from the
    /// runtime ledger: an untested or not-yet-reachable stage must remain
    /// visible instead of being silently treated as a pass.
    graphics_path_preflight: preflight_lib.graphics_path_probe.Report = .{},
    graphics_preflight_enabled: bool = false,
    graphics_preflight_window_allowed: bool = true,
    /// A normal guest exit can follow a failed Xenia setup and otherwise look
    /// like a Rosette crash because the host UI requests deferred shutdown.
    /// Keep the syscall evidence so the final diagnosis can name that path.
    guest_exit_observed: bool = false,
    guest_exit_code: u64 = 0,
    guest_exit_step: u64 = 0,
    /// The selected backend is part of the guest-facing authentic admission
    /// contract. Keep the spelling, not only its identity hash, because the
    /// title asks for it through getenv during GraphicsSystem::Setup.
    audit_backend_name: [32]u8 = [_]u8{0} ** 32,
    audit_backend_name_length: u8 = 0,
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
    /// Reconciles the guest-log bootstrap breadcrumbs with instruction-trace
    /// crossings. These are separate authorities: a call-site probe can miss
    /// a call that the guest actually executed, while a tracepoint can fire
    /// without Xenia publishing a trustworthy guest breadcrumb. Keeping both
    /// here prevents a weak probe from retracting the late VdInitialize/VdSet
    /// sequence visible in the current Xenia run.
    gpu_bootstrap_provenance: gpu.BootstrapProvenance = .{},
    gpu_bootstrap_provenance_last_fingerprint: u64 = std.math.maxInt(u64),
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
    /// Canonical Cocoa graphics truth. This reconciles identities and custody
    /// across AppKit, SDL, Rosette Vulkan, Xenia Vulkan, Xenos and completed
    /// frames without making any of those producers share an owner merely
    /// because they end at the same window.
    cocoa_graphics: gpu.CocoaGraphicsRuntime = .{},
    cocoa_graphics_last_fingerprint: u64 = std.math.maxInt(u64),
    cocoa_graphics_last_outcome: gpu.CocoaGraphicsOutcome = .{},
    /// Every forwarding into Rosette's window: what it named, who made it, and
    /// what was decided. Rosette stands the window up before the guest runs, so
    /// a forwarding that means nothing here is not an early arrival — it is a
    /// message addressed to an identity Rosette owns that Rosette cannot
    /// account for, and under the fault policy the run stops at it.
    window_admission: gpu.WindowAdmissionLedger = .{},
    window_admission_configured: bool = false,
    window_admission_last_fingerprint: u64 = std.math.maxInt(u64),
    /// The standards this run has to meet. Judged at every graphics checkpoint;
    /// the first invariant violated stops the run and names what to fix. See
    /// `lib/diagnostics/run_integrity.zig`.
    run_integrity: run_integrity.Ledger = .{},
    /// Which of several counters of the same increasing fact a report may
    /// quote. Two carriers of one number disagreeing is not itself a defect —
    /// a throttled breadcrumb is allowed to be short — but a report that
    /// quotes the short one attributes a working mechanism to the wrong owner.
    /// See `lib/diagnostics/monotone_witness.zig`.
    monotone_witness: monotone_witness.Ledger = .{},
    monotone_witness_last_fingerprint: u64 = std.math.maxInt(u64),
    pipeline_evidence_last_fingerprint: u64 = std.math.maxInt(u64),
    /// The contracts and evidence systems the 2026-08-31 systems-gap audit
    /// asked for. Each is a ledger with its own vocabulary and its own refusal
    /// rules; they are grouped here so one checkpoint can synchronise them
    /// from the ledgers that already exist and emit one ordered report.
    ///
    /// They are deliberately not merged into the older reports. A contract
    /// that folded into an existing health percentage would lose the one
    /// property the audit is asking for — that a gap names an owner and a
    /// refusal is visible as a refusal.
    audit_manifest: run_manifest.Manifest = .{},
    audit_journal: run_journal.Journal = .{},
    /// One immutable posture controls every fallback and host-side nudge.
    /// Unknown configuration never gets the authentic default by accident.
    audit_profile: run_manifest.Profile = .authentic,
    audit_profile_valid: bool = true,
    audit_identity_fields: run_manifest.IdentityFields = .{},
    audit_build_identity_hash: u64 = 0,
    audit_build_identity_loaded: bool = false,
    audit_identity_conflict: bool = false,
    audit_media_fingerprint: u64 = 0,
    audit_media_preflight_evaluated: bool = false,
    audit_media_preflight_passed: bool = false,
    audit_config_fingerprint: u64 = 0,
    audit_title_id: u32 = 0,
    /// The binary journal is deliberately a small writer, not the 512 KiB
    /// in-memory test image. A killed process leaves a prefix without a
    /// footer, which recovery classifies as incomplete.
    audit_durable_journal: durable_journal.Writer = .{},
    audit_durable_fd: i32 = -1,
    audit_durable_open_failed: bool = false,
    /// The single run-scoped owner joins in-memory publication, the durable
    /// sink, producer quiescence, and the terminal footer. A journal that is
    /// merely open is not an authentic evidence channel.
    audit_evidence_owner: run_closure.EvidenceOwner = .{},
    audit_evidence_owner_started: bool = false,
    audit_evidence_owner_producer: u64 = 0x524F_5345_5454_4531,
    audit_closure_admission: run_closure.Admission = .{},
    audit_closure_admission_failure: run_closure.AdmissionFailure = .none,
    audit_guest_start_verdict: run_closure.StartVerdict = .refused,
    audit_pause: fault_pause_transaction.Ledger = .{},
    audit_producer: gpu.producer_liveness.Ledger = .{},
    audit_ring_transport: gpu.ring_transport.Ledger = .{},
    audit_pm4: gpu.pm4_authority.Ledger = .{},
    audit_render_target: gpu.render_target_evidence.Ledger = .{},
    audit_edram: gpu.edram_model.Model = .{},
    audit_resolve: gpu.resolve_pipeline.Ledger = .{},
    audit_registers: gpu.xenos_register_state.Journal = .{},
    audit_shaders: gpu.shader_execution.Ledger = .{},
    audit_shader_storage: gpu.shader_storage_contract.Ledger = .{},
    audit_vectors: gpu.controlled_vectors.Suite = .{},
    audit_video: gpu.video_contract.Table = .{},
    audit_admission: gpu.feature_admission.Ledger = .{},
    audit_forwarding: gpu.forwarding_fidelity.Matrix = .{},
    audit_frames: gpu.frame_custody_chain.Ledger = .{},
    audit_interrupts: gpu.interrupt_effect.Ledger = .{},
    /// The presenter's own account of the guest output it does not have. Read
    /// from its breadcrumbs so `mailbox=-1` can be joined to Rosette's swap
    /// frontier instead of being read as a presenter defect.
    gpu_guest_output_mailbox: gpu.guest_output_mailbox.Ledger = .{},
    audit_sync: sync_object_registry.Registry = .{},
    audit_provenance: execution_provenance.Ledger = .{},
    audit_alias: guest_alias_contract.Ledger = .{},
    audit_storage: storage_integrity.Ledger = .{},
    audit_budget: run_budget.Ledger = .{},
    /// The throughput budget is a guest-execution contract. Keep the raw
    /// process totals in `audit_budget`, but anchor the judged window at the
    /// first Xenia pipeline boundary that proves the guest main thread has
    /// actually retired an instruction. Loader, import-resolution and JIT
    /// startup work must not be reported as a zero-guest-time guest deficit.
    audit_budget_guest_window: run_budget.Window = .{},
    audit_services: kernel_service_readiness.Inventory = .{},
    audit_imports: import_integrity.Ledger = .{},
    audit_gates: acceptance_gates.Board = .{},
    audit_gates_last_fingerprint: u64 = std.math.maxInt(u64),
    audit_configured: bool = false,
    /// Wyhash of the loaded image. The manifest needs it to say which build
    /// this run is, and two runs of different builds are not comparable.
    audit_image_fingerprint: u64 = 0,
    run_integrity_configured: bool = false,
    /// Evidence policy selected by `ensureRunIntegrity`. Fault and warn modes
    /// use the strict predicates; observe mode preserves the non-invasive
    /// historical readings. This is separate from the action policy so warn
    /// can expose every strict finding without terminating the process.
    run_integrity_strict: bool = false,
    run_integrity_last_fingerprint: u64 = std.math.maxInt(u64),
    run_integrity_first_armed_context: [run_integrity.invariant_count]RunIntegrityContext =
        [_]RunIntegrityContext{.{}} ** run_integrity.invariant_count,
    run_integrity_first_violation_context: [run_integrity.invariant_count]RunIntegrityContext =
        [_]RunIntegrityContext{.{}} ** run_integrity.invariant_count,
    /// Presentations the window has made, counted where they happen so the
    /// custody invariant compares two independently sourced numbers rather than
    /// one number against itself.
    window_presentations: u64 = 0,
    /// Swap boundaries the emulator reached, counted the same way.
    swap_boundaries_reached: u64 = 0,
    /// The highest host-capability score reached, and when. A capability that
    /// is failing while the score still climbs is work in progress; once the
    /// score stops moving, what is left failing is a finding.
    host_coverage_best_percent: u32 = 0,
    host_coverage_progress_step: u64 = 0,
    /// Which side can answer for each boundary, and whether the two agree.
    /// `NEVER ENTERED` on an armed tracepoint is a defect only where Rosette
    /// also has nothing to say about the same question; this is what decides
    /// that. See `lib/diagnostics/substantiation.zig`.
    substantiation: substantiation.Ledger = .{},
    substantiation_last_fingerprint: u64 = std.math.maxInt(u64),
    substantiation_summary: substantiation.Summary = .{},
    /// What this host can actually sample, and what the emulator settled for.
    /// Rosette owns a real physical device, so it answers the capability
    /// question itself rather than taking the emulator's log line for it.
    texture_formats: gpu.TextureFormatSupport = .{},
    texture_format_summary: gpu.texture_format_support.Summary = .{},
    texture_format_last_fingerprint: u64 = std.math.maxInt(u64),
    /// The progress witness captured when a never-notified park was first seen.
    /// A park beside a run that keeps advancing is an idle worker; the same park
    /// beside a frozen run is a lost wakeup, and only this comparison separates
    /// them.
    never_notified_witness: wait_audit.Witness = .{},
    never_notified_witness_valid: bool = false,
    /// Which checkpoint the collapsible reports are currently printing for.
    ///
    /// Several of them are reachable from two paths inside one checkpoint, and
    /// were emitting twice: `GRAPHICS HEALTH CONTRACT` and `VD SWAP CONTRACT`
    /// each appeared 214 times in a 107-checkpoint run, which is 214 copies of
    /// a 42-line and a 29-line block. The epoch makes an emission idempotent
    /// within a checkpoint without either caller having to know about the other.
    report_epoch: u64 = 0,
    graphics_health_report_epoch: u64 = std.math.maxInt(u64),
    vd_swap_contract_report_epoch: u64 = std.math.maxInt(u64),
    /// Set once each collapsible report has printed its detail for a state it
    /// has since kept. The detail returns the moment the state changes, so a
    /// regression is never hidden by the collapse.
    graphics_health_detail_fingerprint: u64 = std.math.maxInt(u64),
    vd_swap_detail_mask: u64 = std.math.maxInt(u64),
    cocoa_control_detail_fingerprint: u64 = std.math.maxInt(u64),
    /// Which tracepoints had been entered at the last detailed print. Four
    /// words because the armed set covers the whole graphics boundary surface
    /// now; a single u64 silently stopped noticing changes past the sixty-fifth
    /// address, which is exactly the class of blind spot this file exists to
    /// remove.
    tracepoint_detail_mask: [4]u64 = [_]u64{std.math.maxInt(u64)} ** 4,
    /// Once every export the title imported is usable, the per-export kernel
    /// table is stable evidence rather than a new finding at every graphics
    /// checkpoint. Keep the first complete table, collapse only an identical
    /// complete state, and reopen it immediately on an import/value regression.
    kernel_surface_complete: bool = false,
    kernel_surface_detail_fingerprint: u64 = std.math.maxInt(u64),
    kernel_surface_collapsed: u64 = 0,
    window_harness_surface_offered: bool = false,
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
    /// Delivering queued GPU completions when nothing else will, and supplying
    /// the front buffer substitution is blocked on.
    ///
    /// Off by default. A completion nobody delivers is indistinguishable from
    /// one nobody generated, and those have opposite causes — so delivering one
    /// and watching what changes is the only way to tell them apart. Everything
    /// it does is recorded as a substitution and can never close an authentic
    /// stage. Selected with ROSETTE_DRAW_DISPATCH.
    gpu_draw_dispatch: gpu.DrawDispatchLedger = .{},
    gpu_draw_dispatch_configured: bool = false,
    /// Checkpoints at which a complete contract's per-element detail was
    /// suppressed. Counted rather than silent: a reader has to be able to tell
    /// a collapsed report from one that stopped being emitted.
    gpu_preinitialization_collapsed: u64 = 0,
    /// Who waits on what and whether the handshake is going anywhere.
    ///
    /// The livelock predictor answers "is this signature repeating"; a matched
    /// wait/signal pair cycling twelve hundred times passes every deadlock
    /// check because nothing is parked and nothing is unsignalled. This answers
    /// the other half: which thread waits, which feeds it, and whether anything
    /// outside the pair moved while it cycled.
    wait_graph: wait_graph.Ledger = .{},
    /// Whether translation cost ends or repeats.
    ///
    /// The decode-cache hit rate says how well the cache works; it cannot say
    /// whether the same code is being decoded over and over because an emitter
    /// keeps reusing its addresses. "Still compiling after four billion steps"
    /// fits a large title compiled once and a small one compiled forever, and
    /// those have opposite remedies.
    translation_economics: translation_economics.Ledger = .{},
    /// Which of several disagreeing statements about the same fact is current.
    /// The emulator never retracts a bring-up snapshot, so its loudest claim
    /// about the ring or the interrupt callback is routinely not its truest.
    claim_reconciliation: claim_reconciliation.Ledger = .{},
    /// Xenia's PowerPC graphics callback transaction. Kept distinct from the
    /// Rosette-model callback fields below so equal names cannot create a false
    /// cross-domain reconciliation failure.
    interrupt_callback_transaction: interrupt_callback_transaction.Ledger = .{},
    /// Rosette's optional host callback installed into Xenia. This callback
    /// keeps the host-side bridge observable, but it is not a title-owned
    /// PowerPC callback and must never satisfy the guest callback boundary.
    host_interrupt_callback_transaction: interrupt_callback_transaction.Ledger = .{ .domain = .xenia_host },
    /// Domain of the most recent callback breadcrumb that had enough
    /// provenance to route context-only lines. 0 is unknown, 1 is the
    /// title/PowerPC callback, and 2 is Rosette's host callback.
    last_interrupt_callback_log_domain: u8 = 0,
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
    /// A ring inspection is an integrity input, not merely a report. Keep
    /// the last inspection identity so the integrity gate can force one scan
    /// after geometry first becomes observable without duplicating the scan at
    /// the same execution checkpoint.
    gpu_ring_inspection_attempted: bool = false,
    gpu_ring_last_inspected_base: u64 = 0,
    gpu_ring_last_inspected_size: u64 = 0,
    gpu_ring_last_inspection_step: u64 = std.math.maxInt(u64),
    /// Stateful Xenos PM4 execution derived from the guest's readable ring.
    /// This does not advance CP_RPTR or manufacture a submission; it is the
    /// backend-neutral state machine that a real Vulkan command recorder can
    /// consume once the guest publishes a batch.
    gpu_xenos_runtime: gpu.XenosRuntime = .{},
    /// Earliest bounded GPU frontier. This is intentionally separate from the
    /// broad graphics/VdSwap ledgers: it records the first observable edge in
    /// the live route, including edges that occur before a full contract report
    /// is emitted, without treating a guest-owned edge as host-authorized.
    gpu_early_frontier: gpu.GpuEarlyFrontier = .{},
    gpu_early_frontier_last_fingerprint: u64 = 0,
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
    gpu_pm4_last_fault_logged: u64 = 0,
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
    /// The graphics boundary surface, decided from the instruction pointer and
    /// nothing else. This is the report a reader should look at first: it is
    /// the only graphics ledger in the process where "the title did not do
    /// this" and "Rosette did not look" are separate masks rather than the
    /// same zero.
    gpu_bringup_gate: gpu.bringup_gate.Gate = .{},
    /// Which observer to believe when the graphics reports disagree. Every
    /// previous run answered "did the ring initialise?" both ways in one log
    /// and had no rule for ranking the answers.
    gpu_evidence: gpu.evidence_grade.Ledger = .{},
    /// The routes by which a finished frame can be reported back to the title,
    /// and whether anything has ever travelled down one. A title that submits
    /// once and stops is waiting on one of these.
    gpu_completion_routes: gpu.completion_route.Ledger = .{},
    /// Provenance at the native-presenter/Cocoa seam. A diagnostic clear keeps
    /// the window alive but never satisfies a guest-output boundary; this
    /// ledger is the authority that keeps those two facts separate.
    presentation_provenance: gpu.presentation_provenance.Ledger = .{},
    presentation_provenance_last_fingerprint: u64 = std.math.maxInt(u64),
    /// What the thread that published to the ring did next. `SWAP HEALTH` has
    /// been ending with "find what the submitting thread is waiting on" for
    /// weeks and nothing joined the producer thread to the wait records.
    gpu_producer_stall: gpu.producer_stall.Tracker = .{},
    /// Crossed-boundary mask at the last full gate table, so the table is
    /// printed on change rather than on every checkpoint.
    gpu_gate_detail_mask: u64 = std.math.maxInt(u64),
    /// Which events must precede which, judged from boundary crossings, with a
    /// bounded ring of what happened before a violation.
    mandatory_order: mandatory_order.Ledger = .{},
    /// What this machine actually did when asked to perform the operations the
    /// emulator depends on. Filled once, before the guest runs.
    host_capabilities: preflight_lib.host_capability.Report = .{},
    /// Supplemental host operations whose subjects are outside the generic
    /// capability prober: the actual libc notification edge and a read-only
    /// libc locale query.  Keep the results on the run state so the final
    /// admission snapshot consumes exactly the operations that were logged,
    /// rather than probing again and letting the two lines disagree.
    host_signal_handshake_proven: bool = false,
    host_locale_query_proven: bool = false,
    /// What is actually in the graphics interrupt callback slot, from the
    /// emulator's own `SetInterruptCallback` line. The slot holds one address
    /// and the newest statement is the true one; every earlier one is a
    /// snapshot of a slot that has since changed hands.
    gpu_interrupt_slot_address: u32 = 0,
    gpu_interrupt_slot_user_data: u32 = 0,
    gpu_interrupt_slot_step: u64 = 0,
    gpu_interrupt_slot_writes: u64 = 0,
    /// Bounded history of callback-slot ownership. The current slot is the
    /// authority for dispatch, while this transition record explains why an
    /// older periodic occupancy line may name a host callback after the title
    /// has replaced it.
    gpu_interrupt_slot_previous_address: u32 = 0,
    gpu_interrupt_slot_previous_user_data: u32 = 0,
    gpu_interrupt_slot_previous_step: u64 = 0,
    gpu_interrupt_slot_previous_is_guest: bool = false,
    gpu_interrupt_slot_transitions: u64 = 0,
    gpu_interrupt_slot_guest_writes: u64 = 0,
    gpu_interrupt_slot_host_writes: u64 = 0,
    /// Whether the current occupant lives in the console's address space. A
    /// builtin outside it is the emulator's own host callback, and a dispatch
    /// into it reaches the harness rather than the title.
    gpu_interrupt_slot_is_guest: bool = false,
    /// What became of the draws that entered the command processor. Rosette
    /// sees both ends of this from the instruction pointer and cannot see which
    /// of the nine ways out of `IssueDraw` took them; the emulator counts them
    /// and these hold the count.
    gpu_draws_entered: u64 = 0,
    gpu_draws_reached_render_target: u64 = 0,
    /// First live draw that Rosette classified as target-backed and therefore
    /// eligible for the render-target ordering rule. Raw IssueDraw entry is
    /// intentionally not enough: Xenia also enters IssueDraw for no-effect
    /// draws that never require a target.
    gpu_renderable_draw_first_step: u64 = 0,
    gpu_renderable_draw_first_thread: u64 = 0,
    /// First step at which any live, guest-owned output opportunity was
    /// observed. This prevents an earlier diagnostic host paint from being
    /// retroactively reclassified as an authentic guest frame.
    gpu_guest_output_first_step: u64 = 0,
    gpu_guest_output_first_thread: u64 = 0,
    gpu_draw_early_exits: u64 = 0,
    /// Early exits the emulator classifies as its own failure, as opposed to a
    /// draw that legitimately had no effect. A total that mixed the two would
    /// hide the second inside the first.
    gpu_draw_defect_exits: u64 = 0,
    gpu_draw_exits_named: u64 = 0,
    gpu_draw_first_exit: [48]u8 = [_]u8{0} ** 48,
    gpu_draw_first_exit_length: u8 = 0,
    gpu_draw_first_exit_step: u64 = 0,
    /// Guest deadlines against the time they actually consumed. The number that
    /// decides whether a bounded poll that expired is evidence about a producer
    /// or evidence about a clock.
    timeout_fidelity: timeout_fidelity.Ledger = .{},
    /// Which components have been shown to work, and whether the proof arrived
    /// before the guest first depended on them.
    component_readiness: preflight_lib.component_readiness.Ledger = .{},
    /// Objects with only one end of a handshake. Separately neither half is a
    /// finding; together they usually are.
    signal_expectation: signal_expectation.Ledger = .{},
    /// Which PM4 opcodes the title actually encoded, and whether it ever asked
    /// to be told its work had finished.
    gpu_packet_census: gpu.packet_census.Ledger = .{},
    /// The console physical address the command processor was told to mirror
    /// the ring read pointer into, from the emulator's own configuration line.
    ///
    /// Only the address comes from the log. Whether anything ever *arrives*
    /// there is read out of console memory, because a word written with the
    /// same value forever is inert to the title polling it and the emulator has
    /// no way to notice that.
    gpu_read_pointer_writeback_address: u32 = 0,
    gpu_read_pointer_writeback_freq: u32 = 0,
    gpu_read_pointer_writeback_mapped: bool = false,
    graphics_summary_emissions: u64 = 0,
    graphics_last_frontier_tag: u8 = std.math.maxInt(u8),
    graphics_last_frontier_reached: usize = std.math.maxInt(usize),
    graphics_last_role_mask: u16 = 0,
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
    /// Every NTSTATUS the guest kernel converted to a DOS error, classified by
    /// whether the caller asked a question that may answer no.
    /// See `lib/diagnostics/guest_status_ledger.zig`.
    guest_status: guest_status_ledger.Ledger = .{},
    guest_status_last_total: u64 = 0,
    /// Every raw value a classifier declined, so the report can name the case
    /// to add rather than print the word `unknown`.
    /// See `lib/diagnostics/unknown_inventory.zig`.
    unknown_inventory: unknown_inventory_mod.Ledger = .{},
    unknown_inventory_last_total: u64 = 0,
    /// Which boundary the GPU gate last named as the frontier, and the step it
    /// began naming it. A frontier that keeps moving is a run making progress
    /// and is never judged; only one the run has settled at is a wall.
    frontier_boundary_last: u8 = 0xFF,
    frontier_boundary_since_step: u64 = 0,
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
    /// The symbols behind that count. See `SlowRouteWitness`.
    import_route_slow_witness: types.SlowRouteWitness = .{},
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
    // S6 (perf audit): the per-instruction CMPXCHG diagnostic (CMPXCHG#N
    // lines) costs a formatted capture on every atomic op and runs even in
    // healthy runs, where a CAS-heavy guest like Xenia's own JIT produces
    // thousands of uncontended compares. Off by default; enable with
    // ROSETTE_MACHO_CMPXCHG_TRACE=1 when diagnosing CAS-contention or
    // lock-state divergence. The atomic_cmpxchg counters still accumulate
    // regardless, so the summary's operations/mismatch totals stay intact.
    cmpxchg_trace_enabled: bool = false,
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
    decode_cache: []align(constants.HOST_CACHE_LINE_BYTES) DecodeCacheEntry,
    /// Recently displaced primary entries.  This is probed only after a
    /// primary miss, so the common hit path remains a single set lookup while
    /// returning code can survive a short cold-stream eviction burst.
    decode_victim_cache: []align(constants.HOST_CACHE_LINE_BYTES) DecodeCacheEntry,
    /// Static-image L2. Unlike the generation-sensitive primary/victim
    /// caches, this bank survives unrelated generated-code writes and only
    /// leaves on an explicit executable-range invalidation.
    static_decode_l2: []align(constants.HOST_CACHE_LINE_BYTES) DecodeCacheEntry,
    /// Faulting instructions retried after a guest SIGSEGV handler resolved
    /// the page's protection. See `signal_handling.protectionFaultResolved`.
    guest_protection_retries: u64 = 0,
    decode_cache_hits: u64 = 0,
    decode_cache_misses: u64 = 0,
    /// A miss that filled a way nothing had occupied — the first execution of
    /// newly emitted code. Irreducible: there is nothing to cache yet.
    decode_cache_vacant_misses: u64 = 0,
    /// A miss that evicted a live decode. This is the addressable kind.
    decode_cache_conflict_misses: u64 = 0,
    /// A non-empty but never-reused entry displaced by a cold stream. Keep it
    /// out of conflict pressure so the report does not call a working-set fill
    /// a hot-code collision.
    decode_cache_cold_eviction_misses: u64 = 0,
    decode_cache_stale_rejections: u64 = 0,
    decode_cache_victim_hits: u64 = 0,
    decode_cache_victim_fills: u64 = 0,
    decode_cache_victim_stale_rejections: u64 = 0,
    static_decode_l2_hits: u64 = 0,
    static_decode_l2_fills: u64 = 0,
    /// Per-domain counters make the isolation measurable. Aggregate counters
    /// remain for compatibility with the existing performance report.
    decode_domain_hits: [translation_domain.count]u64 = [_]u64{0} ** translation_domain.count,
    decode_domain_misses: [translation_domain.count]u64 = [_]u64{0} ** translation_domain.count,
    decode_domain_fills: [translation_domain.count]u64 = [_]u64{0} ** translation_domain.count,
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
        // Align every translation tier to the host cache line.
        //
        // A set is `ways * @sizeOf(DecodeCacheEntry)` bytes, and because the
        // entry is 8-byte aligned that product is always a whole number of
        // 128-byte lines on Apple Silicon — but only if the table's base is
        // line-aligned too. At the natural 8-byte alignment every set in the
        // table shares the base's offset within its line, so a misaligned
        // base makes *every* set straddle one extra line, on a scan that
        // reads all sixteen ways. Asking for the alignment costs a few bytes
        // once and takes it out of the allocator's hands.
        const decode_cache = try allocator.alignedAlloc(
            DecodeCacheEntry,
            constants.HOST_CACHE_LINE_ALIGNMENT,
            DECODE_CACHE_ENTRY_COUNT,
        );
        @memset(decode_cache, .{});
        const decode_victim_cache = try allocator.alignedAlloc(
            DecodeCacheEntry,
            constants.HOST_CACHE_LINE_ALIGNMENT,
            constants.DECODE_VICTIM_CACHE_ENTRY_COUNT,
        );
        @memset(decode_victim_cache, .{});
        const static_decode_l2 = try allocator.alignedAlloc(
            DecodeCacheEntry,
            constants.HOST_CACHE_LINE_ALIGNMENT,
            constants.DECODE_STATIC_L2_ENTRY_COUNT,
        );
        @memset(static_decode_l2, .{});
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
            .decode_victim_cache = decode_victim_cache,
            .static_decode_l2 = static_decode_l2,
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

    pub fn dumpPrimitiveTotals(self: *MachOState) void {
        return macho_process_lifecycle_bindings.dumpPrimitiveTotals(self);
    }

    /// Project the compact Rosette identity into the dependency-free Pass 10
    /// admission record.  The two manifests intentionally remain separate:
    /// `run_manifest.Manifest` carries the journal/run inputs, while this
    /// record is the cross-process contract Xenia authenticates.
    pub fn runIdentity(self: *const MachOState) run_closure.Identity {
        return macho_process_lifecycle_bindings.runIdentity(self);
    }

    pub fn configureAdmission(self: *MachOState, manifest_sealed: bool) void {
        return macho_process_lifecycle_bindings.configureAdmission(self, manifest_sealed);
    }

    pub fn auditEnvironmentMatches(self: *const MachOState, name: [*:0]const u8, expected: u64) bool {
        return macho_process_lifecycle_bindings.auditEnvironmentMatches(self, name, expected);
    }

    pub fn setAuditBackend(self: *MachOState, backend: []const u8) bool {
        return macho_process_lifecycle_bindings.setAuditBackend(self, backend);
    }

    pub fn auditBackend(self: *const MachOState) []const u8 {
        return macho_process_lifecycle_bindings.auditBackend(self);
    }

    pub fn publishAuditEnvironment(self: *const MachOState, allocator: std.mem.Allocator) bool {
        return macho_process_lifecycle_bindings.publishAuditEnvironment(self, allocator);
    }

    /// Configure the cross-process identity and the one execution profile
    /// before any guest instruction can run.  The old path initialized the
    /// in-memory journal lazily at its first graphics checkpoint, which made a
    /// killed startup interval indistinguishable from a run that had never
    /// been observed.  This method is intentionally idempotent so the normal
    /// checkpoint synchronizer can call it as a safety net.
    pub fn configureAuditContracts(self: *MachOState, at_step: u64) void {
        return macho_process_lifecycle_bindings.configureAuditContracts(self, at_step);
    }

    /// Route one stamped in-memory journal record to the append-only durable
    /// sink.  The journal remains the source of the record's domain/global
    /// sequences; the durable writer never serializes the unstamped input.
    pub fn writeAuditJournal(self: *MachOState, record: run_journal.Record) bool {
        return macho_process_lifecycle_bindings.writeAuditJournal(self, record);
    }

    pub fn writeCompactedAuditJournal(self: *MachOState, record: run_journal.Record) bool {
        return macho_process_lifecycle_bindings.writeCompactedAuditJournal(self, record);
    }

    pub fn openAuditDurableJournal(self: *MachOState) void {
        return macho_process_lifecycle_bindings.openAuditDurableJournal(self);
    }

    pub fn finishAuditDurableJournal(self: *MachOState) void {
        return macho_process_lifecycle_bindings.finishAuditDurableJournal(self);
    }

    pub fn deinit(self: *MachOState) void {
        return macho_process_lifecycle_bindings.deinit(self);
    }

    pub fn scheduleGuestWaitDeadline(
        self: *MachOState,
        thread: u64,
        wait_object: u64,
        wait_generation: u64,
        deadline_ns: u64,
    ) u64 {
        return macho_process_lifecycle_bindings.scheduleGuestWaitDeadline(self, thread, wait_object, wait_generation, deadline_ns);
    }

    pub fn applyDyldBindings(self: *MachOState) !void {
        return macho_process_lifecycle_bindings.applyDyldBindings(self);
    }

    pub fn isLocalBindingScope(dylib: []const u8) bool {
        return macho_process_lifecycle_bindings.isLocalBindingScope(dylib);
    }

    pub fn isCallableConstantBinding(
        section: macho_metadata.Section,
        symbol_name: []const u8,
        has_import_stub: bool,
    ) bool {
        return macho_process_lifecycle_bindings.isCallableConstantBinding(section, symbol_name, has_import_stub);
    }

    pub fn isWritableDataSection(section: macho_metadata.Section) bool {
        return macho_process_lifecycle_bindings.isWritableDataSection(section);
    }

    pub fn capstoneCallbackSlotName(self: *const MachOState, address: u64) ?[]const u8 {
        return macho_process_lifecycle_bindings.capstoneCallbackSlotName(self, address);
    }

    pub fn dumpCoopBootstrapTrace(self: *const MachOState) void {
        return macho_process_lifecycle_bindings.dumpCoopBootstrapTrace(self);
    }

    pub fn dumpMemInitTrace(self: *const MachOState) void {
        return macho_process_lifecycle_bindings.dumpMemInitTrace(self);
    }

    pub fn dumpCapstoneCallbackState(self: *const MachOState, reason: []const u8) void {
        return macho_process_lifecycle_bindings.dumpCapstoneCallbackState(self, reason);
    }

    pub fn isAbiDataSymbol(symbol_name: []const u8) bool {
        return macho_process_lifecycle_bindings.isAbiDataSymbol(symbol_name);
    }

    /// Map a libc++ standard stream data symbol to its modeled stream kind.
    /// libc++ exports these as `_ZNSt3__14cerrE` (namespace std, 4-char name,
    /// data) — the Mach-O external form adds one leading underscore. Verified
    /// against the Xenia fork's undefined-symbol table: `__ZNSt3__14cerrE`,
    /// `__ZNSt3__14clogE`, `__ZNSt3__14coutE`.
    pub fn standardCppStreamKind(symbol_name: []const u8) ?libcpp_stream_bridge.StandardStreamKind {
        return macho_process_lifecycle_bindings.standardCppStreamKind(symbol_name);
    }

    pub fn isBridgedLibcppDataSymbol(symbol_name: []const u8) bool {
        return macho_process_lifecycle_bindings.isBridgedLibcppDataSymbol(symbol_name);
    }

    pub fn bindingRequiresBoundThunk(section: macho_metadata.Section, is_runtime_callback: bool) bool {
        return macho_process_lifecycle_bindings.bindingRequiresBoundThunk(section, is_runtime_callback);
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
    pub const dumpStepTraceBuffer = memory_access.dumpStepTraceBuffer;
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
        return macho_process_lifecycle_bindings.registerNativeWindowHandles(self);
    }
    pub fn ensureNativeApplication(self: *MachOState) bool {
        return macho_process_lifecycle_bindings.ensureNativeApplication(self);
    }
    pub fn ensureNativeWindow(self: *MachOState) bool {
        return macho_process_lifecycle_bindings.ensureNativeWindow(self);
    }
    pub fn setNativeWindowTitle(self: *MachOState, title: []const u8) bool {
        return macho_process_lifecycle_bindings.setNativeWindowTitle(self, title);
    }
    pub fn setNativeWindowSize(self: *MachOState, width: i32, height: i32) bool {
        return macho_process_lifecycle_bindings.setNativeWindowSize(self, width, height);
    }
    pub fn showNativeWindow(self: *MachOState) bool {
        return macho_process_lifecycle_bindings.showNativeWindow(self);
    }
    pub fn hideNativeWindow(self: *MachOState) bool {
        return macho_process_lifecycle_bindings.hideNativeWindow(self);
    }
    pub fn setNativeWindowFullscreen(self: *MachOState, fullscreen: bool) bool {
        return macho_process_lifecycle_bindings.setNativeWindowFullscreen(self, fullscreen);
    }
    pub fn nativeViewToken(self: *MachOState) u64 {
        return macho_process_lifecycle_bindings.nativeViewToken(self);
    }
    pub fn nativeWindowToken(self: *MachOState) u64 {
        return macho_process_lifecycle_bindings.nativeWindowToken(self);
    }
    pub fn nativeWindowWidth(self: *MachOState) u32 {
        return macho_process_lifecycle_bindings.nativeWindowWidth(self);
    }
    pub fn nativeWindowHeight(self: *MachOState) u32 {
        return macho_process_lifecycle_bindings.nativeWindowHeight(self);
    }
    pub fn validateNativeMetalLayerToken(self: *MachOState, token: u64) bool {
        return macho_process_lifecycle_bindings.validateNativeMetalLayerToken(self, token);
    }
    pub fn nativeMetalLayerHostPointer(self: *MachOState) usize {
        return macho_process_lifecycle_bindings.nativeMetalLayerHostPointer(self);
    }
    pub fn prepareNativeMetalDrawable(self: *MachOState, width: u32, height: u32) bool {
        return macho_process_lifecycle_bindings.prepareNativeMetalDrawable(self, width, height);
    }
    pub fn setNativeMetalDrawableOwner(self: *MachOState, owned_by_swapchain: bool) bool {
        return macho_process_lifecycle_bindings.setNativeMetalDrawableOwner(self, owned_by_swapchain);
    }
    pub fn noteNativeVulkanSurfaceBound(self: *MachOState, layer_token: u64, guest_surface: u64, host_surface: u64) void {
        return macho_process_lifecycle_bindings.noteNativeVulkanSurfaceBound(self, layer_token, guest_surface, host_surface);
    }
    pub fn presentNativeDiagnosticFrame(
        self: *MachOState,
        serial: u64,
        width: u32,
        height: u32,
        stage: u32,
    ) bool {
        return macho_process_lifecycle_bindings.presentNativeDiagnosticFrame(self, serial, width, height, stage);
    }
    pub fn pumpNativeWindowEvents(self: *MachOState) void {
        return macho_process_lifecycle_bindings.pumpNativeWindowEvents(self);
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
    /// The coarse role an address carries in the nine-value vocabulary that
    /// predates the boundary contract.
    ///
    /// A dozen call sites read `roleEntered`, and several of them gate real
    /// decisions. Newly armed boundaries therefore take `.other` rather than
    /// the role that would most naturally describe them: arming
    /// `WorkerThreadMain` as `.command_processor` would make "the command
    /// processor consumed PM4" true the moment its thread started, which is a
    /// different fact and a worse one. The boundary tag carries the precision;
    /// this carries only what the old predicates already meant.
    pub fn legacyTracepointRole(boundary: gpu.bringup_gate.Boundary) execution_tracepoints.Role {
        return macho_process_lifecycle_bindings.legacyTracepointRole(boundary);
    }

    pub fn boundaryLabel(index: u8) []const u8 {
        return macho_process_lifecycle_bindings.boundaryLabel(index);
    }

    pub fn armGraphicsTracepoints(self: *MachOState) void {
        return macho_process_window_bootstrap.armGraphicsTracepoints(self);
    }

    /// The instruction pointer reached an armed boundary. Only the first entry
    /// is reported: the rest are a frame rate, and the first is the fact the
    /// investigation has been missing.
    pub inline fn noteExecutionTracepoint(self: *MachOState) void {
        return macho_process_window_bootstrap.noteExecutionTracepoint(self);
    }

    /// Publish a tracepoint hit into the earliest GPU frontier immediately,
    /// before the normal heartbeat/report cadence. Tracepoints are execution
    /// evidence, not permission to execute the next edge, so only the exact
    /// boundary represented by the function entry is observed here.
    pub fn observeGpuEarlyTracepoint(self: *MachOState, role: execution_tracepoints.Role, address: u64) void {
        return macho_process_window_bootstrap.observeGpuEarlyTracepoint(self, role, address);
    }

    /// The first observation of a boundary is printed synchronously with the
    /// event. This keeps the exact handoff location visible even if a later
    /// guest livelock prevents another graphics heartbeat from being emitted.
    pub fn observeGpuEarlyBoundary(
        self: *MachOState,
        boundary: gpu.GpuEarlyBoundary,
        source: gpu.GpuEarlySource,
        value: u64,
    ) void {
        return macho_process_window_bootstrap.observeGpuEarlyBoundary(self, boundary, source, value);
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
        return macho_process_window_bootstrap.configureReadyCompiler(self, enabled, enforce, activation_budget_steps, quiet_budget_steps, decoder_ready);
    }

    /// Seal Rosette's build-style phase and begin the guest/Xenia activation
    /// phase. This is called only after pre-main initialization has completed,
    /// so an initializer failure cannot be mislabeled as a gameplay failure.
    pub fn sealReadyCompilerCompile(self: *MachOState) bool {
        return macho_process_window_bootstrap.sealReadyCompilerCompile(self);
    }

    /// Map the existing Xenia pipeline observer into the generic contract.
    /// The process-core observer calls this without importing Xenia-specific
    /// types, which keeps the observer usable by other Mach-O targets.
    pub fn noteReadyCompilerPipelineStage(self: *MachOState, raw_stage: u8, at_step: u64) void {
        return macho_process_window_bootstrap.noteReadyCompilerPipelineStage(self, raw_stage, at_step);
    }

    pub fn noteReadyCompilerGpuPhase(self: *MachOState, raw_phase: u8, at_step: u64) void {
        return macho_process_window_bootstrap.noteReadyCompilerGpuPhase(self, raw_phase, at_step);
    }

    pub fn noteReadyCompilerWait(self: *MachOState, object: u64, signaled: bool, at_step: u64) void {
        return macho_process_window_bootstrap.noteReadyCompilerWait(self, object, signaled, at_step);
    }

    /// Observe Xenia JIT health at the guest-log boundary. This is deliberately
    /// independent of the readiness gate: a run with readiness reporting
    /// disabled still needs to retain an explicit compiler or code-cache
    /// failure rather than letting it disappear into ordinary guest text.
    pub fn observeJitHealthText(self: *MachOState, line: []const u8) void {
        return macho_process_window_bootstrap.observeJitHealthText(self, line);
    }

    pub fn reportJitHealthObservation(self: *MachOState, observation: jit.JitHealthObservation) void {
        return macho_process_window_bootstrap.reportJitHealthObservation(self, observation);
    }

    /// Stop on a typed JIT failure after retaining the exact physical line and
    /// all adjacent readiness/backend evidence. A compiler diagnostic is not a
    /// recoverable guest exception: continuing would let Xenia publish or call
    /// code whose provenance is already known to be broken.
    pub fn faultOnJitHealth(self: *MachOState, observation: jit.JitHealthObservation) void {
        return macho_process_window_bootstrap.faultOnJitHealth(self, observation);
    }

    /// Stop on a failed Xenia readiness contract. Readiness failures are not
    /// ordinary guest errors: once the compiler contract has rejected the
    /// generated-code path, allowing startup to continue would turn a useful
    /// compile failure into a later null call, bad GPU handle, or silent
    /// no-frame condition. Keep this terminal path separate from JIT health so
    /// either subsystem can preserve its own evidence and so a returning
    /// signal handler cannot re-enter the failed run.
    pub fn faultOnReadyCompilerFailure(self: *MachOState) void {
        return macho_process_window_bootstrap.faultOnReadyCompilerFailure(self);
    }

    /// Record a failed host mmap from the Xenia backend's code-cache window.
    /// MAP_JIT failures are separated from ordinary allocation failures so the
    /// crash report answers the important question: missing Apple JIT support,
    /// or a code-cache allocation/publication bug after support was available.
    pub fn noteJitHostMmapFailure(
        self: *MachOState,
        stage: []const u8,
        address: u64,
        length: u64,
        prot: u64,
        flags: u64,
        map_jit: bool,
    ) void {
        return macho_process_window_bootstrap.noteJitHostMmapFailure(self, stage, address, length, prot, flags, map_jit);
    }

    /// A failed protection transition means emitted bytes did not reach the
    /// permissions Xenia asked for. Keep it distinct from mmap so the exact
    /// publication edge is visible before the intentional crash.
    pub fn noteJitHostMprotectFailure(
        self: *MachOState,
        route: []const u8,
        address: u64,
        length: u64,
        prot: u64,
    ) void {
        return macho_process_window_bootstrap.noteJitHostMprotectFailure(self, route, address, length, prot);
    }

    /// Emit the compact JIT health account at a heartbeat or at run exit.
    /// Progress is evidence of a working compiler path, not evidence that the
    /// application is ready; the readiness contract remains the authority for
    /// activation and presentation.
    pub fn logJitHealth(self: *const MachOState, force: bool) void {
        return macho_process_window_bootstrap.logJitHealth(self, force);
    }

    pub fn observeReadyCompilerText(self: *MachOState, line: []const u8) void {
        return macho_process_window_bootstrap.observeReadyCompilerText(self, line);
    }

    pub fn observeReadyCompilerPhysicalLine(self: *MachOState, line: []const u8) void {
        return macho_process_window_bootstrap.observeReadyCompilerPhysicalLine(self, line);
    }

    pub fn logReadyCompilerStage(
        self: *MachOState,
        stage: ready_compiler.xenia.Stage,
        accepted: bool,
        at_step: u64,
        source: []const u8,
    ) void {
        return macho_process_window_bootstrap.logReadyCompilerStage(self, stage, accepted, at_step, source);
    }

    /// The contract as an ordered block sequence, the way a build log reads.
    /// Emitted on every accepted edge so the runtime phase has the same
    /// at-a-glance progression the build phase already has.
    pub fn logReadyCompilerProgress(self: *const MachOState) void {
        return macho_process_window_bootstrap.logReadyCompilerProgress(self);
    }

    /// Evaluate only at heartbeats. The semantic contract is not allowed to
    /// add a per-instruction search to the interpreter's hot loop.
    pub inline fn pollReadyCompiler(self: *MachOState, at_step: u64) void {
        return macho_process_window_bootstrap.pollReadyCompiler(self, at_step);
    }

    pub fn logReadyCompilerFailure(self: *const MachOState) void {
        return macho_process_window_bootstrap.logReadyCompilerFailure(self);
    }

    /// The evidence behind the verdict.
    ///
    /// A blocked line alone says that startup stopped; it does not say which
    /// axis froze, who owed the missing edge, what the guest was last observed
    /// doing, or where it spent the quiet window. Those four facts are what
    /// turn a stall report into an investigation, so they are emitted together
    /// and derived from one snapshot to keep them consistent.
    pub fn logReadyCompilerDiagnosis(self: *const MachOState) void {
        return macho_process_readiness.logReadyCompilerDiagnosis(self);
    }

    pub fn logReadyCompilerSummary(self: *const MachOState) void {
        return macho_process_readiness.logReadyCompilerSummary(self);
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

        pub fn addTarget(self: *ReadyPlanContext, fragment: []const u8) void {
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
        pub fn executableFingerprint(self: *const ReadyPlanContext) ?u64 {
            const start = self.state.executable_min;
            const end = self.state.executable_max;
            if (end <= start) return null;
            const bytes = memory_access.guestMemoryConst(self.state, start, end - start) orelse return null;
            return std.hash.Wyhash.hash(0, bytes);
        }

        pub fn targetFingerprint(self: *const ReadyPlanContext) u64 {
            var count = @as(u64, @intCast(self.target_count));
            var result = std.hash.Wyhash.hash(0, std.mem.asBytes(&count));
            for (self.fragments[0..self.target_count], 0..) |fragment, index| {
                result = ready_compiler.cache.foldTarget(result, fragment, self.addresses[index]);
            }
            return result;
        }

        pub fn restoreCachedReferences(self: *ReadyPlanContext, snapshot_value: ready_compiler.cache.Snapshot) void {
            self.referenced = [_]bool{false} ** max_reference_targets;
            for (self.referenced[0..self.target_count], 0..) |*referenced, index| {
                referenced.* = snapshot_value.referenced_mask & (@as(u64, 1) << @as(u6, @intCast(index))) != 0;
            }
            self.scanned_bytes = snapshot_value.scanned_bytes;
            self.direct_call_sites = snapshot_value.direct_call_sites;
            self.static_cache_hit = true;
        }

        pub fn snapshot(self: *const ReadyPlanContext) ready_compiler.cache.Snapshot {
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
        pub fn scanReferences(self: *ReadyPlanContext) void {
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

        fn hostPathExists(self: *const ReadyPlanContext, path: []const u8) bool {
            _ = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return false;
            return true;
        }

        fn hostPrefixHasVulkanLoader(self: *const ReadyPlanContext, prefix: []const u8) bool {
            var path_buffer: [1024]u8 = undefined;
            // This is a native Rosette runtime probe. An x86_64 loader in a
            // managed build prefix is useful to the translated toolchain but
            // cannot satisfy the ARM64 process's Vulkan dependency.
            for (macos_host_contract.native_vulkan_loader_suffixes) |suffix| {
                const candidate = macos_host_contract.joinPath(prefix, suffix, &path_buffer) orelse continue;
                if (self.hostPathExists(candidate)) return true;
            }
            return false;
        }

        fn hostCapability(context: *anyopaque, name: []const u8) bool {
            const self: *ReadyPlanContext = @ptrCast(@alignCast(context));
            if (std.mem.eql(u8, name, "decoder-audit")) return self.vex_ready;
            if (std.mem.eql(u8, name, "vex-safety")) return self.vex_ready;
            if (std.mem.eql(u8, name, "vulkan-loader")) {
                // An environment variable is only a location hint, not proof
                // that a loader exists. Check the actual file and keep native
                // ARM Homebrew valid here: this is the host-native Vulkan
                // provider, not an x86 build-tool lookup.
                if (std.c.getenv("VULKAN_SDK")) |raw_sdk| {
                    if (self.hostPrefixHasVulkanLoader(std.mem.span(raw_sdk))) return true;
                }
                if (std.c.getenv(macos_host_contract.host_root_environment)) |raw_root| {
                    if (self.hostPrefixHasVulkanLoader(std.mem.span(raw_root))) return true;
                }
                for (macos_host_contract.vulkan_loader_default_paths) |candidate| {
                    if (self.hostPathExists(candidate)) return true;
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

    pub fn emitReadyPlanUnit(context: *anyopaque, progress: ready_compiler.plan.Progress) void {
        return macho_process_readiness.emitReadyPlanUnit(context, progress);
    }

    /// Infer what shape a file must have from how it is named.
    pub fn readyPlanAssetKind(path: []const u8) ?ready_compiler.plan.AssetKind {
        return macho_process_readiness.readyPlanAssetKind(path);
    }

    pub fn readyPlanCachePath() ?[]const u8 {
        return macho_process_readiness.readyPlanCachePath();
    }

    pub fn readyPackagePath() ?[]const u8 {
        return macho_process_readiness.readyPackagePath();
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
        return macho_process_readiness.runReadyCompilerPlan(self, io, image_path, args, vex_ready);
    }

    /// Which producer stopped, when threads are waiting for something that will
    /// never arrive.
    ///
    /// A blocked count cannot distinguish a thread pool at idle from a lost
    /// wakeup. The notifier's identity can: if every thread that ever signalled
    /// the object is now itself waiting on it, no wake is coming, and the last
    /// signaller's program counter is where the missing notification went.
    pub fn logNotifierLiveness(self: *MachOState) void {
        return macho_process_readiness.logNotifierLiveness(self);
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
        return macho_process_readiness.logRegisterApertureTraffic(self);
    }

    /// Anomalies with their dispositions, so a non-zero count is either acted
    /// on or explicitly dismissed rather than accumulating unread.
    pub fn logAnomalyLedger(self: *const MachOState) void {
        return macho_process_readiness.logAnomalyLedger(self);
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
        return macho_process_readiness.refreshGraphicsContract(self);
    }

    /// Add one observation to the cross-layer graphics ledger.  Keeping this
    /// tiny adapter beside the process state makes ownership explicit at every
    /// call site and leaves the package/runtime ledger independent of Mach-O.
    pub fn recordGraphicsHealth(
        self: *MachOState,
        stage: graphics_health_contract.Stage,
        state: graphics_health_contract.State,
        source: graphics_health_contract.Source,
        count: u64,
        note: []const u8,
    ) void {
        return macho_process_readiness.recordGraphicsHealth(self, stage, state, source, count, note);
    }

    /// Count only completed presentations whose payload came from Xenia or
    /// guest memory. Rosette's diagnostic clears intentionally live in a
    /// different counter so a working Cocoa sink cannot be mistaken for a
    /// working emulator producer.
    pub fn guestOutputFramesPresented(self: *const MachOState) u64 {
        return macho_process_readiness.guestOutputFramesPresented(self);
    }

    /// Join the native presenter, frame-source and boundary ledgers without
    /// changing any of their ownership semantics. A diagnostic Cocoa paint is
    /// a valid sink observation but is explicitly ineligible to keep the guest
    /// presenter pump alive. Conversely, a real Xenia/Vulkan source makes a
    /// quiet presenter actionable even before its first completed frame.
    pub fn syncPresentationProvenance(self: *MachOState) void {
        return macho_process_readiness.syncPresentationProvenance(self);
    }

    pub fn logPresentationProvenance(self: *MachOState, force: bool) void {
        return macho_process_readiness.logPresentationProvenance(self, force);
    }

    /// The presenter's own account of the guest output it does not have,
    /// joined to Rosette's independent reading of whether a swap happened.
    ///
    /// `mailbox=-1 frontbuffer=0x0 refresh_attempt_count=0` is where a reader
    /// arrives, and every one of those numbers is a consequence: the mailbox is
    /// empty because nothing refreshed it, and nothing refreshed it because no
    /// swap was produced. Printing the presenter's numbers next to Rosette's
    /// swap frontier is what turns the loudest subsystem in the chain back into
    /// the last one.
    pub fn logGuestOutputMailbox(self: *MachOState, swap_observed: bool) void {
        return macho_process_readiness.logGuestOutputMailbox(self, swap_observed);
    }

    pub fn logNearNullDispatchStatus(self: *MachOState, force: bool) void {
        return macho_process_readiness.logNearNullDispatchStatus(self, force);
    }

    /// Map the native presenter state to the health schema without weakening
    /// its failure semantics.  In particular, a `surface_not_presentable`
    /// result is backpressure (degraded swapchain use), not a successful frame,
    /// and `device_lost` never gets reported as a healthy device.
    pub fn recordNativePresenterPrerequisites(self: *MachOState, state: graphics_health_contract.State, note: []const u8) void {
        return macho_process_readiness.recordNativePresenterPrerequisites(self, state, note);
    }

    pub fn refreshNativePresenterHealth(self: *MachOState) void {
        return macho_process_readiness.refreshNativePresenterHealth(self);
    }

    /// Refresh the broad graphics-health ledger from the owners that already
    /// hold the evidence.  This is intentionally a join, not a second runtime
    /// implementation: every count below is read from an existing subsystem,
    /// and a missing count stays untested rather than becoming a guessed pass.
    pub fn refreshGraphicsHealthContract(self: *MachOState) void {
        return macho_process_readiness.refreshGraphicsHealthContract(self);
    }

    /// Feed the controller from the independent ledgers.  The controller may
    /// authorize only host-owned work; the guest VdSwap and producer fields are
    /// observations that remain outside Rosette's mutation authority.
    pub fn refreshApplicationController(self: *MachOState) application_controller.Decision {
        return macho_process_readiness.refreshApplicationController(self);
    }

    /// Apply only directives whose owner is Rosette.  The guest-facing actions
    /// intentionally have no implementation here: reporting an open VdSwap
    /// boundary is the safety mechanism that prevents a diagnostic frame from
    /// erasing the actual producer defect.
    pub fn applyApplicationController(self: *MachOState, decision: application_controller.Decision) void {
        return macho_process_readiness.applyApplicationController(self, decision);
    }

    /// Reconcile every graphics owner at one checkpoint.  This is intentionally
    /// observation-only: it can transfer custody of an already completed frame
    /// in the ledger, but it never creates a Cocoa object, submits a Vulkan
    /// command, advances Xenos state, or calls guest code.
    pub fn refreshCocoaGraphicsControl(self: *MachOState) gpu.CocoaGraphicsOutcome {
        return macho_process_readiness.refreshCocoaGraphicsControl(self);
    }

    /// Journal SDL graphics calls at the import boundary. The SDL runtime has
    /// already validated the ABI and updated its generation counters before
    /// this hook runs, so these records carry semantic meaning rather than raw
    /// x86 instruction bytes.
    pub fn observeSdlGraphicsImport(self: *MachOState, symbol: []const u8) void {
        return macho_process_readiness.observeSdlGraphicsImport(self, symbol);
    }

    // ---------------------------------------------------------------------
    // Window admission
    // ---------------------------------------------------------------------

    /// `ROSETTE_WINDOW_ADMISSION=fault|refuse|observe`.
    ///
    /// `fault` is the default because the window is Rosette's. Rosette stands
    /// the whole surface up before the guest runs, so a forwarding that names
    /// something Rosette has no semantics for is not a missing feature that
    /// will arrive later in bring-up — it is a message addressed to an identity
    /// Rosette owns, and answering it with a plausible value is how a window
    /// ends up displaying something nobody can account for. Ordering refusals
    /// are never fatal under any policy, so this cannot abort a healthy
    /// bring-up; `refuse` keeps the run alive through an unaccountable one.
    pub fn windowAdmissionPolicyFromEnvironment() gpu.WindowAdmissionPolicy {
        return macho_process_readiness.windowAdmissionPolicyFromEnvironment();
    }

    pub fn ensureWindowAdmission(self: *MachOState) void {
        return macho_process_readiness.ensureWindowAdmission(self);
    }

    /// The window preconditions Rosette has actually observed this instant.
    ///
    /// Read from the live AppKit status and the presenter rather than from a
    /// retained snapshot: an admission decision made against a stale readiness
    /// mask is the same defect as a stale log claim.
    pub fn windowConditions(self: *MachOState, status: native_window_runtime.Status) gpu.window_admission.ConditionMask {
        return macho_process_readiness.windowConditions(self, status);
    }

    /// Decide and record one forwarding into the window.
    ///
    /// Returns the outcome so the caller can act on it. The caller must honour
    /// a `.fault` disposition by calling `faultOnWindowAdmission`; that is
    /// deliberately not done here, so the reporting path can run first.
    pub fn admitWindowForwarding(
        self: *MachOState,
        actor: gpu.WindowActor,
        facility: gpu.WindowFacility,
        operation: gpu.WindowOperation,
        origin: []const u8,
    ) gpu.WindowAdmissionOutcome {
        return macho_process_readiness.admitWindowForwarding(self, actor, facility, operation, origin);
    }

    /// The same decision with per-request conditions the window itself cannot
    /// observe.
    ///
    /// `frame_verified`, `frontbuffer_named` and `swap_boundary_observed` are
    /// facts about the frame being offered, not about the window, so the window
    /// snapshot cannot supply them and the caller has to state them. Passing
    /// them as a mask rather than letting `windowConditions` guess keeps the
    /// guess impossible.
    pub fn admitWindowForwardingWith(
        self: *MachOState,
        actor: gpu.WindowActor,
        facility: gpu.WindowFacility,
        operation: gpu.WindowOperation,
        extra: gpu.window_admission.ConditionMask,
        origin: []const u8,
    ) gpu.WindowAdmissionOutcome {
        return macho_process_readiness.admitWindowForwardingWith(self, actor, facility, operation, extra, origin);
    }

    /// Facts about a frame being offered that the window itself cannot observe.
    ///
    /// Stated by the caller because they are properties of the frame, not of
    /// the window: whether its source was read and validated, whether a front
    /// buffer is named for it, and whether a guest swap boundary was seen. A
    /// `windowConditions` that guessed at these would be describing a frame it
    /// never looked at.
    pub const PresentationFacts = struct {
        frame_verified: bool = false,
        frontbuffer_named: bool = false,
        swap_boundary_observed: bool = false,

        pub fn mask(self: PresentationFacts) gpu.window_admission.ConditionMask {
            const W = gpu.window_admission;
            var value: W.ConditionMask = 0;
            if (self.frame_verified) value |= W.conditionBit(.frame_verified);
            if (self.frontbuffer_named) value |= W.conditionBit(.frontbuffer_named);
            if (self.swap_boundary_observed) value |= W.conditionBit(.swap_boundary_observed);
            return value;
        }
    };

    /// Ask the window whether these pixels may reach it.
    pub fn admitWindowPresentation(
        self: *MachOState,
        actor: gpu.WindowActor,
        facility: gpu.WindowFacility,
        facts: PresentationFacts,
        origin: []const u8,
    ) gpu.WindowAdmissionOutcome {
        return macho_process_readiness.admitWindowPresentation(self, actor, facility, facts, origin);
    }

    /// Whether a facility Rosette promises before the guest runs is standing.
    /// Only the pre-initialized ones are consulted; for the rest the contract
    /// ignores this and absence is ordering.
    pub fn windowFacilityPresent(
        self: *MachOState,
        status: native_window_runtime.Status,
        facility: gpu.WindowFacility,
    ) bool {
        return macho_process_readiness.windowFacilityPresent(self, status, facility);
    }

    /// Terminate on an unaccountable forwarding into Rosette's window.
    ///
    /// The report is written first and the fault is raised second, so the crash
    /// log and the runtime log both name the forwarding that caused it. The
    /// signal is real: `native_crash` has handlers installed for it, writes the
    /// host register file and the last guest progress, and re-raises, so the
    /// process still exits 139 and a supervisor keying on that keeps working.
    ///
    /// Unlike a generic window-admission refusal, this path cannot be made
    /// conditional on a profile or an environment bypass. A layer whose
    /// drawable extent is not the extent the presenter/guest is about to use
    /// is already an invalid presentation graph; letting execution continue
    /// would make every later Vulkan result and every black frame ambiguous.
    pub fn faultOnGraphicsExtentContract(
        self: *MachOState,
        requested_width: u32,
        requested_height: u32,
        observed_width: u32,
        observed_height: u32,
        reason: []const u8,
    ) void {
        return macho_process_readiness.faultOnGraphicsExtentContract(self, requested_width, requested_height, observed_width, observed_height, reason);
    }

    pub fn faultOnWindowAdmission(self: *MachOState, outcome: gpu.WindowAdmissionOutcome) void {
        return macho_process_readiness.faultOnWindowAdmission(self, outcome);
    }

    /// Offer every swap boundary Xenia has reached to the window's gate.
    ///
    /// Runs once per graphics checkpoint rather than at each boundary, because
    /// the evidence is a joint reading: whether a boundary may hand
    /// presentation over depends on the front buffer, the ring epoch and the
    /// presenter lease as they stand now, not as they stood when the tracepoint
    /// fired. A boundary Xenia has never reached is never offered — an
    /// unoffered boundary and a refused one are different facts and the report
    /// keeps them apart.
    pub fn refreshWindowSwapAdmission(self: *MachOState) void {
        return macho_process_readiness.refreshWindowSwapAdmission(self);
    }

    /// Rank how Rosette came to believe a boundary occurred, from the sources
    /// the VdSwap ledger recorded for it.
    ///
    /// A parsed emulator log line is deliberately the weakest: twice in this
    /// codebase a claim read out of the emulator's own diagnostics was a
    /// snapshot of state that had already moved, and the swap gate refuses to
    /// act on one.
    pub fn swapProvenanceFor(source_mask: u32) gpu.window_admission.SwapProvenance {
        return macho_process_readiness.swapProvenanceFor(source_mask);
    }

    // ---------------------------------------------------------------------
    // Run integrity
    // ---------------------------------------------------------------------

    /// `ROSETTE_RUN_INTEGRITY=fault|warn|observe`, and
    /// `ROSETTE_RUN_INTEGRITY_ALLOW=<comma-separated invariant labels>`.
    ///
    /// `fault` is the default. A run that is not meeting the standards is worse
    /// than a run that stops: it burns hours and produces a log in which the
    /// real defect is one line among tens of thousands. The allow list exists
    /// so a reader who has triaged one violation can reach the next without
    /// disarming the whole gate.
    pub fn ensureRunIntegrity(self: *MachOState) void {
        return macho_process_readiness.ensureRunIntegrity(self);
    }

    /// Assemble the one shared output-evidence record used by both capability
    /// coverage and run-integrity. Keeping the construction here prevents a
    /// raw PM4 draw count, a retained replay, and a guest-owned output request
    /// from becoming three different meanings of "frame opportunity".
    pub fn guestOutputEvidence(self: *const MachOState) host_contract_coverage.GuestOutputEvidence {
        return macho_process_readiness.guestOutputEvidence(self);
    }

    /// Return the budget measurements after the proven guest-main boundary.
    /// Before that boundary the empty summary is intentional: the process may
    /// be doing substantial Xenia setup, but no guest-time rate exists yet.
    pub fn runBudgetGuestWindowSummary(self: *const MachOState) run_budget.Summary {
        return macho_process_readiness.runBudgetGuestWindowSummary(self);
    }

    /// The ten-second settling interval applies inside the guest window, not
    /// to Rosette's process-creation or Xenia loader prefix. Keeping this test
    /// beside the summary makes every report and gate use the same boundary.
    pub fn runBudgetGuestWindowObserved(self: *const MachOState, totals: run_budget.Summary) bool {
        return macho_process_readiness.runBudgetGuestWindowObserved(self, totals);
    }

    pub fn runBudgetGuestWindowVerdict(
        self: *const MachOState,
        totals: run_budget.Summary,
    ) run_budget.Verdict {
        return macho_process_readiness.runBudgetGuestWindowVerdict(self, totals);
    }

    /// Assemble the measurements every invariant is decided from.
    ///
    /// Read once, here, so a judgement is never assembled out of two different
    /// instants — the same discipline the window admission decision follows.
    pub fn runIntegrityObservation(self: *MachOState) run_integrity.Observation {
        return macho_process_graphics_health.runIntegrityObservation(self);
    }

    /// Return the application boundary that makes a missing notifier
    /// actionable.
    ///
    /// Host workers are created and parked while Xenia is still loading and
    /// translating the title. Their condition variables can have no observed
    /// notifier yet, but that is not evidence that the guest's execution path
    /// has lost a wake. The strict run-integrity liveness checks begin only
    /// after guest execution or a guest-driven GPU boundary is proven. The
    /// wait/deadlock ledgers continue to record the pre-boundary state in full.
    /// Refresh the wait graph's independent progress axis before any consumer
    /// judges its pair states. Keeping this in one process-side helper prevents
    /// the integrity gate and the verbose report from taking different views of
    /// the same handshake.
    pub fn refreshWaitGraphProgress(self: *MachOState) void {
        return macho_process_graphics_health.refreshWaitGraphProgress(self);
    }

    pub fn runIntegrityGpuActivity(self: *const MachOState) bool {
        return macho_process_graphics_health.runIntegrityGpuActivity(self);
    }

    /// Return the strongest trustworthy progress witness for capability
    /// closure. Coverage is the normal witness, but Xenia can spend a long
    /// prefix compiling PPC guest functions while the graphics ladder quite
    /// correctly remains unchanged. Successful translation generations and
    /// other host-serviced Ready Compiler counters are real work in that
    /// interval; treating them as silence made the integrity gate fault while
    /// the bootstrap dependency was still advancing.
    pub fn capabilityGuestProgressStep(self: *const MachOState) u64 {
        return macho_process_graphics_health.capabilityGuestProgressStep(self);
    }

    /// Boundary substantiation arms later than general graphics setup. Engine
    /// initialization and callback registration prove that Rosette can host a
    /// GPU, but they do not make a missing ring publication or swap request
    /// actionable. Require guest main or a guest-driven command/swap edge.
    pub fn substantiationGpuActivity(self: *const MachOState) bool {
        return macho_process_graphics_health.substantiationGpuActivity(self);
    }

    pub fn runIntegrityLivenessScope(self: *const MachOState) run_integrity.LivenessScope {
        return macho_process_graphics_health.runIntegrityLivenessScope(self);
    }

    /// Count one presentation the window actually made.
    ///
    /// Sourced from the presenter ledgers rather than from custody, so the
    /// custody invariant compares two independently produced numbers. A counter
    /// compared against itself proves nothing.
    pub fn refreshWindowPresentations(self: *MachOState) void {
        return macho_process_graphics_health.refreshWindowPresentations(self);
    }

    /// State what each side can say about every boundary, then judge the set.
    ///
    /// The two sides are asked separately and neither is allowed to speak for
    /// the other. Xenia's side is the instruction pointer reaching an armed
    /// address or its own ledger advancing; Rosette's is a modelled
    /// implementation that ran. When both answer, the values are compared —
    /// that comparison is the only thing that makes a number from either side
    /// quotable without saying which side it came from.
    pub fn refreshSubstantiation(self: *MachOState) substantiation.Summary {
        return macho_process_graphics_health.refreshSubstantiation(self);
    }

    pub fn logSubstantiation(self: *MachOState, summary: substantiation.Summary, force: bool) void {
        return macho_process_graphics_health.logSubstantiation(self, summary, force);
    }

    /// Ask this host what it can sample, and resolve every guest format
    /// against the answer.
    ///
    /// Only runs once the presenter has a physical device. Before that every
    /// format would read absent and the ladder would refuse everything, which
    /// would be an observation about the observer rather than about the host.
    pub fn refreshTextureFormatSupport(self: *MachOState) void {
        return macho_process_graphics_health.refreshTextureFormatSupport(self);
    }

    pub fn logTextureFormatSupport(self: *MachOState) void {
        return macho_process_graphics_health.logTextureFormatSupport(self);
    }

    pub fn ringInspectionNeedsPreIntegrityScan(self: *const MachOState) bool {
        return macho_process_graphics_health.ringInspectionNeedsPreIntegrityScan(self);
    }

    pub fn refreshRunIntegrity(self: *MachOState) void {
        return macho_process_graphics_health.refreshRunIntegrity(self);
    }

    /// Join the immutable predicate history with the execution context that
    /// made it actionable. The contract owns the decision and the ledger owns
    /// the input snapshot; this small process-side table owns the RIP/thread
    /// because only the process can see them. It is populated after every
    /// evaluation, including warn/observe mode, so stepping past a violation
    /// does not erase its provenance.
    pub fn captureRunIntegrityContexts(self: *MachOState) void {
        return macho_process_graphics_health.captureRunIntegrityContexts(self);
    }

    /// Print all predicate inputs as one coherent snapshot. Keeping the groups
    /// separate makes a long line grep-friendly while retaining the complete
    /// observation vector needed to replay why the contract made its decision.
    pub fn logRunIntegrityTraceSnapshot(
        self: *MachOState,
        label: []const u8,
        observation: run_integrity.Observation,
    ) void {
        return macho_process_graphics_health.logRunIntegrityTraceSnapshot(self, label, observation);
    }

    /// Print the live-only PM4 quality ledger. This intentionally does not use
    /// the retained VdSwap scanner: a replay can explain missing state but must
    /// never make a historical packet anomaly look like a current hardware
    /// failure (or hide one).
    pub fn logRunIntegrityPm4Evidence(self: *MachOState) void {
        return macho_process_graphics_health.logRunIntegrityPm4Evidence(self);
    }

    /// Print the exact host capability records behind capability violations.
    /// Aggregate counts are intentionally not enough: this is what identifies
    /// whether the failing surface is a ring, a guest swap, a frame source, a
    /// presenter, or some other layer.
    pub fn logRunIntegrityCapabilityCauses(self: *MachOState, invariant: run_integrity.Invariant) void {
        return macho_process_graphics_health.logRunIntegrityCapabilityCauses(self, invariant);
    }

    /// Emit the native presenter's terminal state and the most recent frame
    /// transaction together. The stage alone says where bring-up stopped; the
    /// frame report says whether a later queue/acquire/present operation was
    /// the first native failure.
    pub fn logRunIntegrityPresenterCause(self: *MachOState) void {
        return macho_process_graphics_health.logRunIntegrityPresenterCause(self);
    }

    /// List the concrete symbols behind execution-profile classifier debt.
    /// The normal audit report already prints the hottest rows; this bounded
    /// repeat is kept in the fatal trace so the failure remains self-contained
    /// when the run stops before the next full audit pass.
    pub fn logRunIntegrityProfileGaps(self: *MachOState) void {
        return macho_process_graphics_health.logRunIntegrityProfileGaps(self);
    }

    /// Emit every required monotone subject inside the fatal trace. The normal
    /// witness report is periodic and may be separated from the stop by a
    /// large amount of output; this bounded block keeps the missing observer
    /// and both carriers attached to the exact closure failure.
    pub fn logRunIntegrityWitnessCorroboration(self: *MachOState) void {
        return macho_process_graphics_health.logRunIntegrityWitnessCorroboration(self);
    }

    /// Name the stages nothing ever probed, and the probe rows that prove it.
    ///
    /// A count of unprobed stages is not actionable: the work is at a specific
    /// call site for a specific probe, and the row that identifies it is
    /// `attempts=0` sitting beside siblings with hundreds. Printing the floor
    /// alongside is what separates "the driver never ran" from "the driver ran
    /// and never came here", which are different repairs.
    pub fn logRunIntegrityUnprobedStages(self: *MachOState) void {
        return macho_process_graphics_health.logRunIntegrityUnprobedStages(self);
    }

    /// Name the stages starved for a cause Rosette can remove, and the probe
    /// and cause for each.
    ///
    /// A count says how many gaps there are; the repair is at one call site
    /// per stage, and only the deciding probe and its recorded cause identify
    /// it. `probe-unwired` and `source-never-fed` need different fixes and the
    /// row has to say which.
    pub fn logRunIntegrityClosableStarvations(self: *MachOState) void {
        return macho_process_graphics_health.logRunIntegrityClosableStarvations(self);
    }

    /// Name every contested claim inside a fatal integrity trace.
    ///
    /// The gate's remedy says "read CLAIM RECONCILIATION", and on 2026-09-06
    /// that report was not in the log: it is periodic, it collapses when
    /// unchanged, and the run died before the next emission. A stop whose
    /// evidence lives in a different report is a stop a reader cannot act on,
    /// so the evidence is printed here, on the fault path, where lines are
    /// written synchronously and survive the signal.
    pub fn logRunIntegrityContestedClaims(self: *MachOState) void {
        return macho_process_graphics_health.logRunIntegrityContestedClaims(self);
    }

    /// Emit the budget inputs inside a fatal integrity trace. The ordinary
    /// RUN BUDGET line is periodic and may be separated from the stop by a
    /// large amount of guest/JIT output; this compact block keeps the measured
    /// rate, threshold and host-time attribution attached to the failure.
    pub fn logRunIntegrityBudgetCause(self: *MachOState) void {
        return macho_process_graphics_health.logRunIntegrityBudgetCause(self);
    }

    /// Emit a detailed block only at a violation entry or when its measured
    /// detail changes. The ordinary integrity report can continue to appear at
    /// checkpoints; this event block is the bounded, causal record that makes
    /// the first failure searchable and prevents an unchanged fault from
    /// drowning the run in duplicate evidence.
    pub fn logRunIntegrityViolationTrace(self: *MachOState, summary: run_integrity.Summary) void {
        return macho_process_graphics_health.logRunIntegrityViolationTrace(self, summary);
    }

    /// Emit the exact controller decision and immutable sample that violated
    /// the ownership/evidence contract. This is intentionally separate from
    /// the normal controller summary: the summary can have moved on by the
    /// time the integrity trace is flushed, while the retained violation is
    /// the evidence that justified the stop.
    pub fn logApplicationControllerContractViolation(self: *MachOState) void {
        return macho_process_graphics_health.logApplicationControllerContractViolation(self);
    }

    pub fn logRunIntegrity(self: *MachOState, summary: run_integrity.Summary) void {
        return macho_process_graphics_health.logRunIntegrity(self, summary);
    }

    /// Stop at the cache fill when strict fault policy is miss-intolerant.
    ///
    /// The periodic run-integrity checkpoint remains the authoritative
    /// summary, but waiting for that checkpoint would let a cache conflict
    /// execute an unbounded amount of guest work. This path is armed only
    /// after the runtime policy has been configured, only faults under the
    /// fault policy, and honors the same allow-list as the periodic gate.
    pub inline fn failFastOnTranslationCause(
        self: *MachOState,
        address: u64,
        domain: translation_domain.Domain,
        cause: translation_economics.Cause,
        set_base: usize,
        cache_way: usize,
        victim: *const DecodeCacheEntry,
        victim_is_empty: bool,
        victim_was_reused: bool,
        stale_rejected: bool,
        bytes: []const u8,
    ) void {
        return macho_process_graphics_health.failFastOnTranslationCause(self, address, domain, cause, set_base, cache_way, victim, victim_is_empty, victim_was_reused, stale_rejected, bytes);
    }

    /// Terminate on a violated invariant.
    ///
    /// The whole report is written first, then the fault is raised, so the
    /// crash log and the runtime log both name the standard that was not met.
    pub fn faultOnRunIntegrity(self: *MachOState, summary: run_integrity.Summary) void {
        return macho_process_graphics_health.faultOnRunIntegrity(self, summary);
    }

    pub fn logWindowAdmission(self: *MachOState, force: bool) void {
        return macho_process_graphics_health.logWindowAdmission(self, force);
    }

    pub fn logWindowSwapAdmission(self: *MachOState) void {
        return macho_process_graphics_health.logWindowSwapAdmission(self);
    }

    pub fn cocoaGraphicsPolicyFromEnvironment() gpu.cocoa_runtime.RoutePolicy {
        return macho_process_graphics_health.cocoaGraphicsPolicyFromEnvironment();
    }

    /// Emit the complete ownership map only when its semantic fingerprint
    /// changes. Repeated observations and presenter-lease renewals are counted
    /// internally but do not reprint the map or masquerade as new GPU work.
    pub fn logCocoaGraphicsControl(self: *MachOState, force: bool) void {
        return macho_process_graphics_health.logCocoaGraphicsControl(self, force);
    }

    /// Drain requests made through the exported framework ABI. Requests are
    /// processed at the same safe frontier as the existing controller, never
    /// from an arbitrary Xenia callback or from the instruction hot path.
    /// Guest calls and memory writes are rejected by the framework policy
    /// before they reach this method; unsupported host requests are completed
    /// explicitly so a caller can distinguish "not implemented" from "never
    /// observed".
    pub fn serviceApplicationFrameworkRequests(self: *MachOState) void {
        return macho_process_graphics_health.serviceApplicationFrameworkRequests(self);
    }

    pub fn logGraphicsHealthContract(self: *MachOState) void {
        return macho_process_graphics_health.logGraphicsHealthContract(self);
    }

    pub fn logApplicationController(self: *MachOState, decision: application_controller.Decision) void {
        return macho_process_graphics_health.logApplicationController(self, decision);
    }

    pub fn logApplicationFramework(self: *MachOState) void {
        return macho_process_graphics_health.logApplicationFramework(self);
    }

    /// Join execution-boundary facts into the strict VdSwap ledger.  This is
    /// intentionally conservative: entering the generic PM4 decoder is not
    /// authentic swap consumption, and a presenter frame is not guest output
    /// unless an authentic XE_SWAP has already been proven.
    pub fn refreshVdSwapContract(self: *MachOState) void {
        return macho_process_graphics_health.refreshVdSwapContract(self);
    }

    /// Feed first-time contract arrivals to the horizon ledger.
    ///
    /// A milestone is a boundary reached for the first time, never a counter
    /// ticking: a spin loop advances counters, and only real progress arrives
    /// somewhere it has never been. The contract mask is exactly that — a bit
    /// per boundary, set once — so the newly-set bits since the last check are
    /// the milestones and nothing else has to be inferred.
    pub fn noteVdSwapMilestones(self: *MachOState) void {
        return macho_process_graphics_health.noteVdSwapMilestones(self);
    }

    pub fn elapsedHostSeconds(self: *const MachOState) u64 {
        return macho_process_graphics_health.elapsedHostSeconds(self);
    }

    /// State the harness's own view of the facts the emulator also reports.
    ///
    /// Recorded on every checkpoint rather than on change: the reconciliation
    /// rule reads how many times a source repeated a value *after* being
    /// contradicted, and a change-only feed erases exactly that signal.
    pub fn stateHarnessClaims(self: *MachOState) void {
        return macho_process_graphics_health.stateHarnessClaims(self);
    }

    /// Print which of several disagreeing statements about the same fact is
    /// current, and which sources are still asserting a contradicted one.
    ///
    /// This report exists because the log's loudest statement about a fact is
    /// routinely not its truest. `ring_init=NO rb_base=00000000` appears four
    /// times during bring-up and is contradicted 1.7 seconds later by a
    /// different line that appears three times. Both remain in the log. Two
    /// separate investigations in this project were spent on the stale one.
    pub fn logClaimReconciliation(self: *MachOState) void {
        return macho_process_graphics_health.logClaimReconciliation(self);
    }

    /// The systems-gap audit's contracts, in the order they gate each other.
    ///
    /// Led by the acceptance board, because the one thing every earlier report
    /// could not say is *where the run actually is*. A frontier of `G4` with
    /// everything past it `not-reached` is a different sentence from a list of
    /// zeros, and it is the sentence the next hour should be spent on.
    pub fn pipelineEvidence(self: *const MachOState) pipeline_evidence.Report {
        return macho_process_graphics_health.pipelineEvidence(self);
    }

    pub fn logPipelineEvidence(self: *MachOState) void {
        return macho_process_graphics_health.logPipelineEvidence(self);
    }

    pub fn logAuditContracts(self: *MachOState) void {
        return macho_process_audit_waits.logAuditContracts(self);
    }

    /// Which counters of the same increasing fact disagree, and which number a
    /// reader may quote.
    ///
    /// Printed even when everything agrees, because the useful half of this
    /// report is the list of subjects with only one witness: those are the
    /// places where an absence is currently being quoted on one carrier's word
    /// alone, and that is how `INERT: the emulator has never entered it` was
    /// printed about a callback that had run two hundred and forty times.
    pub fn logMonotoneWitnesses(self: *MachOState) void {
        return macho_process_audit_waits.logMonotoneWitnesses(self);
    }

    /// Report one callback transaction without collapsing execution domains.
    /// A return is the authoritative execution fact; absence of a sampled ring
    /// mutation remains advisory. The host callback gets the same detail as a
    /// title callback, but its separate domain makes the ownership boundary
    /// visible in every report.
    pub fn logInterruptCallbackLedger(ledger: *const interrupt_callback_transaction.Ledger, prefix: []const u8) void {
        return macho_process_audit_waits.logInterruptCallbackLedger(ledger, prefix);
    }

    /// Report Xenia's PowerPC callback transaction independently of Rosette's
    /// fallback-model interrupt callback. Rosette's host callback is logged as
    /// a second, explicitly labelled transaction and cannot satisfy the
    /// PowerPC account used by the graphics/substantiation contracts.
    pub fn logInterruptCallbackTransaction(self: *MachOState) void {
        return macho_process_audit_waits.logInterruptCallbackTransaction(self);
    }

    /// Print which Xenos registers the executed PM4 stream actually wrote.
    ///
    /// Forty state packets executed with every render-target register reading
    /// zero is either a title that has not chosen a target or a harness losing
    /// the write, and a count of state packets cannot tell those apart. The
    /// register indices can.
    pub fn logRegisterJournal(self: *MachOState) void {
        return macho_process_audit_waits.logRegisterJournal(self);
    }

    /// Learn the callback address from every source, keeping how much each
    /// one assumes, and select the dispatch policy this run asked for.
    ///
    /// The live gap this closes: the callback address `0x821951f8` is printed
    /// in one report while the dispatcher holds zero and makes no attempt. Both
    /// are correct — the address was parsed from a diagnostic line and nothing
    /// intercepted a registration — and the run is stuck between them.
    pub fn refreshDrawDispatch(self: *MachOState) void {
        return macho_process_audit_waits.refreshDrawDispatch(self);
    }

    /// How long after a delivery before "nothing changed" is a conclusion
    /// rather than impatience. A hundred million steps is a full heartbeat
    /// interval, so a consumer that was going to act has had a turn.
    const effect_settle_steps: u64 = 100_000_000;

    pub fn drawDispatchPolicyFromEnvironment() gpu.DrawDispatchPolicy {
        return macho_process_audit_waits.drawDispatchPolicyFromEnvironment();
    }

    /// Print what the dispatch scaffold knows, what it did, and what it
    /// refused.
    pub fn logDrawDispatch(self: *MachOState) void {
        return macho_process_audit_waits.logDrawDispatch(self);
    }

    /// Print who waits on what and whether the handshake is going anywhere.
    ///
    /// Read this when the deadlock predictor says nothing is wrong and the run
    /// is still not moving. A matched pair cycling with nothing else advancing
    /// is invisible to every check that asks "is something parked", because
    /// nothing is.
    pub fn logWaitGraph(self: *MachOState) void {
        return macho_process_audit_waits.logWaitGraph(self);
    }

    /// Print the cause the cache fill path proved for every decode miss.
    ///
    /// A repeated page is not evidence that an emitter rewrote it. The 6.2B
    /// run's hottest pages were immutable Xenia image text and precise byte
    /// invalidation was effectively absent; the repeated work was eviction.
    /// Preserve the fill cause here so cache pressure and executable mutation
    /// can never collapse into the same diagnosis again.
    pub fn logTranslationEconomics(self: *MachOState) void {
        return macho_process_audit_waits.logTranslationEconomics(self);
    }

    /// Prove that formatted Xenia records stayed isolated across cooperative
    /// guest threads. A missing append is deliberately rejected; accepting it
    /// from another thread's buffer would turn corrupted text into false PM4
    /// and scheduling evidence.
    pub fn logGuestLogChannels(self: *MachOState) void {
        return macho_process_audit_waits.logGuestLogChannels(self);
    }

    /// Print whether the run stopped because the guest stopped, or because the
    /// run did.
    ///
    /// Every other verdict in this subsystem is built on "X has not happened",
    /// and none of them knew how much of the guest's own timeline the run
    /// covered. A title that reached its newest milestone at 93% of the way
    /// through a run has not stalled; it ran out of wall clock, and a longer
    /// run is the entire fix. Reading that as a stall costs weeks.
    /// The producer's own publication axis, frozen.
    ///
    /// Deliberately not "the guest stopped executing": an emulator's main loop
    /// retires instructions forever while its pipeline is dead, which is what
    /// let the 2026-09-08 run hold every armed invariant at satisfied for 7.5
    /// billion steps. This asks whether the *producer* advanced, which a spin
    /// cannot fake.
    pub fn runHorizonAxisFrozen(self: *const MachOState) bool {
        return macho_process_audit_waits.runHorizonAxisFrozen(self);
    }

    /// Whether the horizon has reached the verdict that says a longer run will
    /// not help. One computation, read by both the report and the gate.
    pub fn runHorizonStalled(self: *const MachOState) bool {
        return macho_process_audit_waits.runHorizonStalled(self);
    }

    pub fn logRunHorizon(self: *MachOState) void {
        return macho_process_audit_waits.logRunHorizon(self);
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
        return macho_process_audit_waits.logVdSwapTrace(self);
    }

    /// Emit each PM4 failure once with enough context to reproduce its framing
    /// decision. The bounded journal remains available for later summaries;
    /// this changed-sequence gate keeps periodic health reports from repeating
    /// the same fault indefinitely.
    pub fn logNewPm4Fault(self: *MachOState) void {
        return macho_process_audit_waits.logNewPm4Fault(self);
    }

    pub fn probeSuppliesStage(stage: gpu.VdSwapStage, which: gpu.VdSwapProbe) bool {
        return macho_process_audit_waits.probeSuppliesStage(stage, which);
    }

    /// Print the complete VdSwap/PM4 ledger.  The broad graphics ladder still
    /// has value for window/bootstrap work; this report is the packet-level
    /// evidence needed to decide whether a front-buffer substitution is even
    /// legal.
    pub fn logVdSwapContract(self: *MachOState) void {
        return macho_process_audit_waits.logVdSwapContract(self);
    }

    /// The kernel surface: what a title reads before it will present, and
    /// whether anything supplied it.
    ///
    /// Printed with the contract because the two answer different halves of the
    /// same question. The contract says which precondition is unmet and who
    /// owns it; the surface says whether the unmet one is unmet because a
    /// *value* is missing — the case a call-counting ladder cannot see at all.
    pub fn logKernelSurface(self: *MachOState) void {
        return macho_process_audit_waits.logKernelSurface(self);
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
        return macho_process_audit_waits.readConsoleDword(self, console_address);
    }

    /// One big-endian dword out of the console's *physical* address space.
    ///
    /// Separate from `readConsoleDword` because the ring read-pointer
    /// write-back address is a physical one — the command processor resolves it
    /// with `TranslatePhysical` — and reading it through the virtual view would
    /// silently sample an unrelated page and report a value that never changes.
    pub fn readConsolePhysicalDword(self: *MachOState, physical_address: u32) ?u32 {
        return macho_process_audit_waits.readConsolePhysicalDword(self, physical_address);
    }

    /// Write one big-endian dword into the console's virtual address space.
    ///
    /// The only mutation this subsystem performs on console memory, and it is
    /// gated by the owner rule before it is ever called. Returns whether the
    /// write landed, because a provisioning step that silently did nothing is
    /// worse than one that did not run: the report would say the platform state
    /// was supplied.
    pub fn writeConsoleDword(self: *MachOState, console_address: u32, value: u32) bool {
        return macho_process_audit_waits.writeConsoleDword(self, console_address, value);
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
        return macho_process_audit_waits.refreshKernelVariables(self);
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
        return macho_process_audit_waits.provisionPlatformStateNow(self);
    }

    /// Supply one kernel-owned variable, if the owner rule allows it and the
    /// storage is reachable.
    pub fn provisionKernelVariable(self: *MachOState, which: gpu.KernelVariable) void {
        return macho_process_audit_waits.provisionKernelVariable(self, which);
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
        return macho_process_audit_waits.logProvisioningCustody(self);
    }

    pub fn logKernelVariables(self: *MachOState) void {
        return macho_process_audit_waits.logKernelVariables(self);
    }

    /// Whether a translated-x86 callback route has a title-owned registration
    /// witness. The callback address alone is intentionally insufficient:
    /// VdInitializeEngines carries a callback-shaped argument on some Xenia
    /// paths, but only VdSetGraphicsInterruptCallback establishes the route.
    pub fn titleInterruptCallbackRegistrationObserved(self: *const MachOState) bool {
        return macho_process_audit_waits.titleInterruptCallbackRegistrationObserved(self);
    }

    pub fn titleInterruptCallbackRouteProven(self: *const MachOState) bool {
        return macho_process_audit_waits.titleInterruptCallbackRouteProven(self);
    }

    /// Record a callback dispatch at the event boundary, before any callback
    /// selection or fallback. This is what turns an early synthetic/host
    /// dispatch into a retained pre-initialization inversion instead of a
    /// later report that merely says the callback was absent.
    pub fn noteGpuInterruptDispatch(self: *MachOState) void {
        return macho_process_audit_waits.noteGpuInterruptDispatch(self);
    }

    /// Join every subsystem's evidence into the pre-initialisation ledger.
    ///
    /// Derived rather than maintained, like the graphics contract: each fact
    /// already exists somewhere, and the value here is the ordering check that
    /// no individual subsystem can perform because none of them sees the
    /// others' timing.
    pub fn refreshPreinitialization(self: *MachOState) void {
        return macho_process_audit_waits.refreshPreinitialization(self);
    }

    /// What Rosette could not map, ranked, each row naming the value to add.
    ///
    /// This is the report to read when a run keeps reaching the same frontier.
    /// A blocking row is a classifier that declined a value a conclusion needed:
    /// no amount of further running produces the answer, because the answer is
    /// a case statement nobody has written.
    pub fn logUnknownInventory(self: *MachOState) void {
        return macho_process_audit_waits.logUnknownInventory(self);
    }

    /// Which kernel calls the guest reported as failed, and which of those
    /// nobody asked for.
    ///
    /// Collapsed on an unchanged total: a title that probes for a hundred
    /// cache files emits a hundred identical conversions, and reprinting the
    /// same table for each is how a real failure gets buried under an answered
    /// question.
    pub fn logGuestKernelStatus(self: *MachOState) void {
        return macho_process_audit_waits.logGuestKernelStatus(self);
    }

    /// Whether the guest's waits are waits or a spin wearing a wait's name.
    pub fn logGuestWaitLiveness(self: *MachOState) void {
        return macho_process_audit_waits.logGuestWaitLiveness(self);
    }

    /// The pre-initialisation ledger, printed with owners and ordering.
    pub fn logPreinitialization(self: *MachOState) void {
        return macho_process_audit_waits.logPreinitialization(self);
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
        return macho_process_gpu_execution.logRingContents(self);
    }

    pub fn deliverGpuInterrupt(context: *anyopaque, event: gpu.interrupt_controller.Event) void {
        return macho_process_gpu_execution.deliverGpuInterrupt(context, event);
    }

    pub fn xenosGpuSwap(value: u32, endian: u2) u32 {
        return macho_process_gpu_execution.xenosGpuSwap(value, endian);
    }

    pub fn xenosProjectionHostAddress(
        self: *MachOState,
        address: u32,
        projection: xenia_memory_views.PhysicalProjection,
    ) ?u64 {
        return macho_process_gpu_execution.xenosProjectionHostAddress(self, address, projection);
    }

    pub fn xenosReadProjection(
        self: *MachOState,
        address: u32,
        projection: xenia_memory_views.PhysicalProjection,
    ) ?u32 {
        return macho_process_gpu_execution.xenosReadProjection(self, address, projection);
    }

    pub fn xenosWriteProjection(
        self: *MachOState,
        address: u32,
        value: u32,
        endian: u2,
        projection: xenia_memory_views.PhysicalProjection,
    ) bool {
        return macho_process_gpu_execution.xenosWriteProjection(self, address, value, endian, projection);
    }

    pub fn noteXenosAliasFallback(self: *MachOState, address: u32, disagreement: bool) void {
        return macho_process_gpu_execution.noteXenosAliasFallback(self, address, disagreement);
    }

    pub fn xenosMemoryRead(context: *anyopaque, address: u32) ?u32 {
        return macho_process_gpu_execution.xenosMemoryRead(context, address);
    }

    pub fn xenosMemoryWrite(context: *anyopaque, address: u32, value: u32, endian: u2) bool {
        return macho_process_gpu_execution.xenosMemoryWrite(context, address, value, endian);
    }

    /// Execute the batch that is still present in ring memory after the
    /// command processor drained it.
    pub fn pm4BatchIdentity(
        self: *const MachOState,
        bytes: []const u8,
        start: u32,
        dwords: u32,
        ring_dwords: u32,
        content_fingerprint: u64,
    ) u64 {
        return macho_process_gpu_execution.pm4BatchIdentity(self, bytes, start, dwords, ring_dwords, content_fingerprint);
    }

    pub fn pm4AuthorityAccount(
        execution: gpu.xenos_runtime.Report,
        batch_id: u64,
        source: gpu.pm4_authority.SourceClass,
    ) gpu.pm4_authority.Account {
        return macho_process_gpu_execution.pm4AuthorityAccount(execution, batch_id, source);
    }

    pub fn pm4AuthorityWalkAccount(
        summary: xenia_pm4_walk.Summary,
        batch_id: u64,
        source: gpu.pm4_authority.SourceClass,
    ) gpu.pm4_authority.Account {
        return macho_process_gpu_execution.pm4AuthorityWalkAccount(summary, batch_id, source);
    }

    pub fn recordPm4AuthorityAccount(
        self: *MachOState,
        account_value: gpu.pm4_authority.Account,
    ) void {
        return macho_process_gpu_execution.recordPm4AuthorityAccount(self, account_value);
    }

    pub fn recordPm4AuthorityWalk(
        self: *MachOState,
        batch_id: u64,
        summary: xenia_pm4_walk.Summary,
        source: gpu.pm4_authority.SourceClass,
    ) void {
        return macho_process_gpu_execution.recordPm4AuthorityWalk(self, batch_id, summary, source);
    }

    pub fn recordPm4AuthorityExecution(
        self: *MachOState,
        batch_id: u64,
        execution: gpu.xenos_runtime.Report,
        source: gpu.pm4_authority.SourceClass,
    ) void {
        return macho_process_gpu_execution.recordPm4AuthorityExecution(self, batch_id, execution, source);
    }

    /// Execute the batch that is still present in ring memory after the
    /// command processor drained it.
    ///
    /// Join the stateful executor's packet summary into the earliest frontier.
    /// This is called at the moment a batch finishes, rather than waiting for a
    /// periodic graphics report, so a guest that immediately parks after its
    /// draw still leaves a causally ordered record in the log.
    pub fn observeGpuEarlyPacketExecution(
        self: *MachOState,
        execution: gpu.xenos_runtime.Report,
        authentic: bool,
    ) void {
        return macho_process_gpu_execution.observeGpuEarlyPacketExecution(self, execution, authentic);
    }

    /// Print the decoded front-buffer fetch constant.  Until this existed it ran from one
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
    pub fn executeRetainedBatch(
        self: *MachOState,
        bytes: []const u8,
        root_start: u32,
        root_dwords: u32,
        ring_dwords: u32,
        authentic: bool,
        authority_batch_id: u64,
    ) void {
        return macho_process_gpu_execution.executeRetainedBatch(self, bytes, root_start, root_dwords, ring_dwords, authentic, authority_batch_id);
    }

    /// Record that every probe fed by the ring survey was starved, and how.
    ///
    /// The survey's records all live inside `if (survey.best()) |chosen|` and
    /// `if (guestMemoryConst(...)) |bytes|`. When either declines, the whole
    /// block is skipped and nothing is recorded — so on 2026-09-03 the run
    /// reached step 2.9B with `ring projection readable` at `probes=0/5` while
    /// the driver beside it had 178 attempts, and the contract reported
    /// Rosette's silence as a fact about the transport. A probe that skips a
    /// round has to say it skipped and why; that is the whole difference
    /// between "nobody was watching" and "I looked and there was nothing".
    pub fn recordRingSurveyStarvation(
        self: *MachOState,
        outcome: gpu.VdSwapProbeOutcome,
        cause: gpu.VdSwapStarvationCause,
    ) void {
        return macho_process_gpu_execution.recordRingSurveyStarvation(self, outcome, cause);
    }

    /// Record that every probe fed by the retained batch was starved, and how.
    ///
    /// The whole reason this exists is that these stages have exactly one
    /// evidence path between them.  When that path cannot run, thirteen
    /// contract stages read zero at once, and without this they would all read
    /// as findings against the command processor.
    pub fn recordRetainedBatchStarvation(
        self: *MachOState,
        outcome: gpu.VdSwapProbeOutcome,
        cause: gpu.VdSwapStarvationCause,
    ) void {
        return macho_process_gpu_execution.recordRetainedBatchStarvation(self, outcome, cause);
    }

    /// Print the dwords the producer actually wrote.
    ///
    /// Seventeen non-zero dwords in eight thousand is a very specific fact, and
    /// every summary built on top of it loses the only part that matters. No
    /// counter in the subsystem can say what the producer submitted; this can,
    /// and the batch is small enough to read.
    pub fn logRingPayload(self: *MachOState, chosen: gpu.ring_view.Reading) void {
        return macho_process_gpu_execution.logRingPayload(self, chosen);
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
        return macho_process_gpu_execution.refreshDeadlockPredictor(self);
    }

    /// Judge the releases already granted, and consider granting one more.
    ///
    /// The scheduler's own repair path performs the wake; this decides whether
    /// one is warranted and — the part that was missing — records what it
    /// proved. A release nobody reads the outcome of is a workaround; a release
    /// whose outcome is recorded is an experiment that settles which codebase
    /// the defect is in.
    pub fn refreshStallRelease(self: *MachOState) void {
        return macho_process_gpu_execution.refreshStallRelease(self);
    }

    /// Fetch the state a provably-unsatisfied waiter is waiting on, so the
    /// failure point is named rather than asserted.
    ///
    /// Three things together: where the object lives (a guest console address
    /// the emulator's view can translate, or a host-side primitive), the
    /// synchronisation ledger's own numbers for it (waiters, notifications,
    /// repairs), and the bytes at the object when they are readable — a
    /// correct waiter's predicate data sits in or near the object it waits on.
    pub fn fetchStallReleaseState(self: *MachOState, object: u64) void {
        return macho_process_gpu_execution.fetchStallReleaseState(self, object);
    }

    /// The progress witness a release is judged against.
    ///
    /// The same axes the wait audit uses, so a release and a wait pattern can
    /// never disagree about whether the run moved. Deliberately excludes
    /// retired instructions: a livelock produces billions of those and would
    /// make every release look like it worked.
    pub fn stallReleaseProgress(self: *const MachOState) u64 {
        return macho_process_gpu_execution.stallReleaseProgress(self);
    }

    /// Record a release the notifier-liveness path performed.
    ///
    /// The wake itself belongs there — it owns the selector and the generation
    /// guard — and this owns the question of what it proved. Calling the wake
    /// from both places would grant two per checkpoint and quietly turn a
    /// bounded experiment into a policy.
    pub fn noteStallReleaseGranted(self: *MachOState, object: u64, thread: u64, waited_steps: u64) void {
        return macho_process_gpu_execution.noteStallReleaseGranted(self, object, thread, waited_steps);
    }

    /// Which subsystem failed to come up, and whether that is why the run
    /// stopped moving.
    pub fn logBringupFailures(self: *MachOState) void {
        return macho_process_gpu_execution.logBringupFailures(self);
    }

    /// What the bounded releases proved.
    pub fn logStallRelease(self: *MachOState) void {
        return macho_process_gpu_execution.logStallRelease(self);
    }

    pub fn preflightOutcomeStatus(
        outcome: preflight_lib.host_capability.Outcome,
    ) host_contract_coverage.Status {
        return macho_process_gpu_execution.preflightOutcomeStatus(outcome);
    }

    /// Exercise the pure address-space contract with the same fixed-view
    /// geometry Xenia publishes at runtime.  The base is deliberately a
    /// synthetic value: before the guest runs there is no live Xenia mapping
    /// to inspect, and inventing one from a process address would turn a model
    /// test into a false claim about the guest.
    pub fn preflightAddressTranslation() bool {
        return macho_process_gpu_execution.preflightAddressTranslation();
    }

    /// Seed the host half of the coverage ledger from operations Rosette has
    /// already performed without guest execution.  Runtime observation still
    /// refines these rows later, but this is the first complete answer and is
    /// intentionally kept separate from the guest-owned ten rows.
    pub fn seedPreWindowHostCoverage(self: *MachOState) void {
        return macho_process_graphics_evidence.seedPreWindowHostCoverage(self);
    }

    /// Close the host side of admission at the last point before any guest
    /// initializer can execute.  Every host-owned row must now be satisfied;
    /// the ten guest-owned rows remain explicit deferred work for the run.
    pub fn enforcePreWindowHostCoverage(self: *MachOState) bool {
        return macho_process_graphics_evidence.enforcePreWindowHostCoverage(self);
    }

    /// Score the host capability surface from what this run actually observed.
    ///
    /// Derived rather than maintained, like the graphics contract: every fact
    /// already exists in some subsystem, and the value here is the join plus
    /// the weighting. A second copy of the truth is how two reports in one run
    /// end up contradicting each other.
    pub fn refreshHostCoverage(self: *MachOState) void {
        return macho_process_graphics_evidence.refreshHostCoverage(self);
    }

    /// The zoomed-out view: how much of the host contract works.
    pub fn logHostCoverage(self: *MachOState) void {
        return macho_process_graphics_evidence.logHostCoverage(self);
    }

    /// Sample the independent progress axes the wait audit classifies against.
    ///
    /// Each axis is driven by a different subsystem, so a wait can freeze one
    /// without freezing the others — and which ones it freezes is the finding.
    /// Sampled here rather than at each observation because the observation
    /// sites are in the log parser, which has no view of the run as a whole.
    pub fn refreshWaitAuditWitness(self: *MachOState) void {
        return macho_process_graphics_evidence.refreshWaitAuditWitness(self);
    }

    /// Which repeating waits are problems, and the full audit for those only.
    ///
    /// The suppression is the point. A run has many handshakes and most of them
    /// work; printing every one buries the one that does not, and the operator
    /// then reads twelve healthy pumps looking for a defect that is on line
    /// thirteen.
    pub fn logWaitAudit(self: *MachOState) void {
        return macho_process_graphics_evidence.logWaitAudit(self);
    }

    /// Threads parked forever, and the reason nobody can release them.
    pub fn logDeadlockPredictor(self: *MachOState) void {
        return macho_process_graphics_evidence.logDeadlockPredictor(self);
    }

    /// Whether the run's caught exceptions recovered anything.
    pub fn logGuestExceptions(self: *MachOState) void {
        return macho_process_graphics_evidence.logGuestExceptions(self);
    }

    /// Deferrals that became crashes, and the ones that are about to.
    pub fn logDeferredWork(self: *MachOState) void {
        return macho_process_graphics_evidence.logDeferredWork(self);
    }

    /// What the emulator's callback-missing probe actually found.
    pub fn logImportBinding(self: *MachOState) void {
        return macho_process_graphics_evidence.logImportBinding(self);
    }

    /// Which observers believe the write pointer moved, and whether they agree.
    pub fn logSubmissionProvenance(self: *MachOState) void {
        return macho_process_graphics_evidence.logSubmissionProvenance(self);
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
    pub fn offerGuestFrontBuffer(
        self: *MachOState,
        swap: gpu.Pm4SwapDescription,
        fetch: ?gpu.Pm4FetchConstant,
        harness_supplied: bool,
    ) void {
        return macho_process_graphics_evidence.offerGuestFrontBuffer(self, swap, fetch, harness_supplied);
    }

    /// Resolve the stateful Xenos color target into the guest framebuffer when
    /// the PM4 runtime has a real EDRAM result. The compact PM4 executor does
    /// not claim to rasterize shaders, so an all-zero store is deliberately
    /// ignored instead of replacing a title-owned framebuffer with black.
    /// Successful resolves are linear RGBA8 and the caller presents them as
    /// linear/none, avoiding a second guest tiling or endian transform.
    pub fn tryResolveXenosColorToFrontBuffer(self: *MachOState, swap: gpu.Pm4SwapDescription, host: u64) bool {
        return macho_process_graphics_evidence.tryResolveXenosColorToFrontBuffer(self, swap, host);
    }

    /// Whether the harness stood in for the title, and if not, what stopped it.
    pub fn logSwapSubstitution(self: *MachOState) void {
        return macho_process_graphics_evidence.logSwapSubstitution(self);
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
    pub fn runSyntheticQueue(self: *MachOState) void {
        return macho_process_graphics_evidence.runSyntheticQueue(self);
    }

    /// The contract, printed as a ladder with owners.
    ///
    /// The owner column is the point. A frontier the harness owns is work
    /// Rosette can do today; one the title owns is a question about the title,
    /// and no amount of harness code will move it.
    pub fn logGraphicsContract(self: *MachOState) void {
        return macho_process_graphics_evidence.logGraphicsContract(self);
    }

    /// Copy every crossing the instruction pointer recorded into the boundary
    /// gate, and derive the evidence, completion-route and producer readings
    /// that follow from it.
    ///
    /// Synchronisation rather than incremental notification on purpose. The
    /// tracepoint set is the authority and it is already counting; a second
    /// counter that could drift from it would be one more observer to
    /// reconcile, and reconciling observers is the problem this whole group of
    /// modules exists to stop.
    pub fn syncGraphicsBoundaryGate(self: *MachOState) void {
        return macho_process_graphics_evidence.syncGraphicsBoundaryGate(self);
    }

    /// State Rosette's own counts of facts the emulator also counts.
    ///
    /// Only witnesses of *literally the same occurrences* are paired here, and
    /// the restraint is the whole point. Xenia's packet census counts type-0
    /// and type-3 packets while the tracepoint counts type-3 entries; the
    /// register journal replays a retained ring while `WriteRegister` counts
    /// live executions. Pairing either of those would manufacture a permanent
    /// Populate the audit contracts from the ledgers this run already keeps.
    ///
    /// One-way, like every other synchronisation in this file: a contract
    /// takes what an existing ledger observed and applies its own rules to it.
    /// Nothing here writes back, and nothing invents an observation that was
    /// not made — a contract with no input reports `unobserved`, which is the
    /// answer the audit asks for and is not the same as a zero.
    pub fn syncAuditContracts(self: *MachOState, at_step: u64) void {
        return macho_process_graphics_evidence.syncAuditContracts(self, at_step);
    }

    /// Judge the acceptance gates from the contracts above, in order.
    ///
    /// A gate whose predecessor has not passed is recorded as `not_reached`
    /// by the board itself, so the run's frontier is always the first thing
    /// that is genuinely missing rather than the loudest downstream zero.
    pub fn syncAcceptanceGates(self: *MachOState, at_step: u64) void {
        return macho_process_graphics_evidence.syncAcceptanceGates(self, at_step);
    }

    /// disagreement between two correct counters, and the gate below stops the
    /// run for a disagreement. A subject with one witness is reported as
    /// uncorroborated, which is the honest answer and is not a finding.
    pub fn syncMonotoneWitnesses(self: *MachOState, at_step: u64) void {
        return macho_process_graphics_evidence.syncMonotoneWitnesses(self, at_step);
    }

    /// Join the small set of execution-boundary crossings that correspond to
    /// guest GPU bootstrap milestones. This is intentionally a one-way join:
    /// an IP tracepoint becomes trace evidence in the provenance ledger, but a
    /// guest breadcrumb never becomes a fabricated tracepoint in
    /// `gpu_bringup_gate`.
    pub fn syncBootstrapProvenanceTracepoints(self: *MachOState) void {
        return macho_process_graphics_evidence.syncBootstrapProvenanceTracepoints(self);
    }

    /// Offer every graphics observer's reading to the evidence ledger, each
    /// labelled with what kind of observer it is.
    ///
    /// The tiers are the point. A ring scan that finds twenty-four draws and a
    /// tracepoint at `IssueDraw` that never fired are both in this list, and
    /// the ledger is what stops the first from being reported as fact when the
    /// second, looking later, saw nothing.
    pub fn syncGraphicsEvidence(self: *MachOState) void {
        return macho_process_graphics_evidence.syncGraphicsEvidence(self);
    }

    /// Which routes the title has for being told its work finished, and
    /// whether anything has come down one.
    ///
    /// The three facts per route are deliberately separate. `established` is
    /// the title asking and the emulator agreeing; `delivered` is the guest
    /// observing an effect. A run where the first is true and the second is
    /// false is the exact shape of a title that submits once and stops, and no
    /// previous report could produce that sentence.
    pub fn syncCompletionRoutes(self: *MachOState, at_step: u64) void {
        return macho_process_graphics_evidence.syncCompletionRoutes(self, at_step);
    }

    /// Attribute the ring producer to the thread that crossed the
    /// write-pointer boundary, so its later waits can be joined to it. The
    /// bring-up boundary's first_thread is an observer-side value and may be
    /// the command-processor worker; only the per-publication guest context is
    /// allowed to establish producer ownership.
    pub fn syncProducerAttribution(self: *MachOState) void {
        return macho_process_graphics_evidence.syncProducerAttribution(self);
    }

    /// Record what has been shown to work and what the guest is depending on,
    /// then report the relationship between the two.
    ///
    /// The proofs are deliberately of two kinds and are kept apart. The ones
    /// Rosette owns are exercised before the guest runs, so they can be proven
    /// *ahead* of first use. The rest can only be proven by watching the guest's
    /// own use complete — and a component in that group being `used_unproven` is
    /// not a defect on its own while it is unused. Once an essential component
    /// is used unproven, the run-integrity admission contract makes that gap
    /// fatal; the readiness report remains the source of the component, first
    /// use, proof and obligation details.
    pub fn syncComponentReadiness(self: *MachOState) void {
        return macho_process_graphics_evidence.syncComponentReadiness(self);
    }

    /// Whether every component a frame depends on was shown to work, and
    /// whether the proof arrived before the guest relied on it.
    pub fn logComponentReadiness(self: *MachOState) void {
        return macho_process_graphics_evidence.logComponentReadiness(self);
    }

    /// Copy the executor's opcode histogram into the census, then say what the
    /// title asked for.
    ///
    /// Synchronisation rather than an incremental feed: the executor is already
    /// counting and a second counter that could drift from it would be one more
    /// observer to reconcile.
    pub fn syncPacketCensus(self: *MachOState) void {
        return macho_process_graphics_evidence.syncPacketCensus(self);
    }

    /// Every boundary that is supposed to keep repeating, with when it last
    /// did.
    ///
    /// The boundary gate names the first stalled one in console order, which is
    /// correct for finding a frontier and wrong for understanding a shutdown: a
    /// run where four pumps stopped needs the *sequence* they stopped in, and
    /// that is four last-steps side by side rather than one verdict. On the
    /// 2026-08-31 run the producer went quiet at step 3 415 047 818 and the
    /// vblank pump kept going until 3 485 520 781 — seventy million steps
    /// later — which is the difference between "the pump died and the producer
    /// starved" and "the producer stopped and the pump followed".
    pub fn logPumpLiveness(self: *MachOState) void {
        return macho_process_graphics_evidence.logPumpLiveness(self);
    }

    /// Which PM4 opcodes the title encoded, and whether it ever asked for a
    /// completion at all.
    ///
    /// This is the report that separates the two opposite explanations for a
    /// title that submits one batch and stops: it asked to be told and was not,
    /// or it never asked and is waiting on something that is not the GPU.
    pub fn logPacketCensus(self: *MachOState) void {
        return macho_process_graphics_evidence.logPacketCensus(self);
    }

    /// Which synchronisation objects have only one end.
    ///
    /// The wait graph already reports edges and the notifier ledger already
    /// reports never-signalled objects. Neither produces the pair, and the pair
    /// is the finding: an object waited on and never signalled beside one
    /// signalled and never waited on is two halves of a handshake that are not
    /// meeting.
    pub fn logSignalExpectation(self: *MachOState) void {
        return macho_process_graphics_evidence.logSignalExpectation(self);
    }

    /// Feed the ordering ledger from the boundary crossings, then judge every
    /// declared rule against them.
    ///
    /// The events come from the tracepoint set rather than from any counter,
    /// so an ordering violation reported here is two instruction pointers and a
    /// step number. That matters: an ordering derived from log lines could be
    /// inverted by nothing more than one subsystem logging late.
    pub fn syncMandatoryOrder(self: *MachOState) void {
        return macho_process_graphics_admission.syncMandatoryOrder(self);
    }

    /// The ordering report, and — at a new finding — the events that led to it.
    pub fn logMandatoryOrder(self: *MachOState) void {
        return macho_process_graphics_admission.logMandatoryOrder(self);
    }

    /// Perform every host operation the emulator depends on, once, and report
    /// what this machine actually did.
    ///
    /// Emitted before the guest runs. Everything else in the process observes
    /// the emulator; this is the only thing that asks the kernel directly, and
    /// it exists because "Xenia mapped a page" and "a page can be mapped here"
    /// are two facts that the rest of the run cannot separate.
    pub fn logHostCapabilities(self: *MachOState) void {
        return macho_process_graphics_admission.logHostCapabilities(self);
    }

    /// Whether a guest deadline means what the guest thinks it means.
    pub fn logTimeoutFidelity(self: *MachOState) void {
        return macho_process_graphics_admission.logTimeoutFidelity(self);
    }

    /// The graphics report a reader should look at first.
    ///
    /// One verdict line naming one boundary and one owner, then the evidence
    /// conflicts, then the completion routes, then what the producer thread did
    /// next. Everything else in the graphics block is detail underneath this.
    pub fn logGraphicsBoundaryGate(self: *MachOState) void {
        return macho_process_graphics_admission.logGraphicsBoundaryGate(self);
    }

    /// What became of the draws between entering the command processor and
    /// reaching a render target.
    ///
    /// The two ends are Rosette's, read from the instruction pointer. The
    /// middle is the emulator's, and until it was counted a run could say
    /// twenty-four draws happened and could not say that none of them rendered.
    pub fn logDrawAttrition(self: *MachOState) void {
        return macho_process_graphics_admission.logDrawAttrition(self);
    }

    pub fn logCompletionRoutes(self: *MachOState) void {
        return macho_process_graphics_admission.logCompletionRoutes(self);
    }

    pub fn logProducerStall(self: *MachOState) void {
        return macho_process_graphics_admission.logProducerStall(self);
    }

    pub fn logGraphicsEvidence(self: *MachOState) void {
        return macho_process_graphics_admission.logGraphicsEvidence(self);
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
        return macho_process_graphics_admission.logSwapHealth(self);
    }

    /// Print the producer-to-present causal trace.  This stays separate from
    /// the graphics contract because the contract is a current frontier while
    /// this ledger retains the bounded history needed to explain a repeated
    /// wait or a state-only PM4 batch.
    pub fn logXeniaGpuCausalTrace(self: *MachOState, force: bool) void {
        return macho_process_graphics_admission.logXeniaGpuCausalTrace(self, force);
    }

    /// Emit the bounded early frontier only when it changes. The per-edge rows
    /// intentionally include negative space (untested edges) so the next run
    /// can distinguish “no observer looked” from “the observer looked and the
    /// guest never crossed this boundary.”
    pub fn logGpuEarlyFrontier(self: *MachOState, force: bool) void {
        return macho_process_graphics_admission.logGpuEarlyFrontier(self, force);
    }

    /// Join execution-boundary facts into the causal ledger before deciding
    /// whether a graphics checkpoint changed. This keeps tracepoint evidence
    /// visible even when Xenia's own breadcrumb was split across a log write.
    pub fn refreshXeniaGpuCausalTrace(self: *MachOState) void {
        return macho_process_graphics_admission.refreshXeniaGpuCausalTrace(self);
    }

    /// Print the reconciliation between guest bootstrap breadcrumbs and the
    /// instruction-trace gate. This is the missing context behind the current
    /// `VdInitializeEngines` callsite-probe miss: the probe is a search aid,
    /// while the concrete guest call is execution evidence.
    pub fn logGpuBootstrapProvenance(self: *MachOState, force: bool) void {
        return macho_process_graphics_admission.logGpuBootstrapProvenance(self, force);
    }

    /// emitted periodically and again at exit.
    pub fn logGraphicsFrontier(self: *MachOState, force: bool) void {
        return macho_process_graphics_admission.logGraphicsFrontier(self, force);
    }

    /// What the title is doing instead of reaching the bootstrap frontier.
    ///
    /// `reached=7/8 frontier=authentic PM4_XE_SWAP consumed precondition_met=true
    /// blocked_by=none` is an accurate and complete answer to the question the
    /// ladder asks, and it is the wrong place for a reader to stop. Everything
    /// upstream is done, nothing is blocking, and the step has not happened —
    /// which means the title is occupied with something else, and Rosette
    /// already knows what: on the 2026-08-31 run a guest thread had been
    /// polling one manual-reset event with a thirty-millisecond timeout since
    /// step 3 250 630 268, which is within nine million steps of the ring
    /// publication the frontier is waiting for a successor to.
    ///
    /// The join is only stated when the poll began at or after the producer's
    /// last advance. A poll that predates the batch is the title's own
    /// business; a poll that started with it is the title waiting for that
    /// batch, and that is the next question rather than a restatement of the
    /// frontier.
    pub fn logBootstrapFrontierOccupation(
        self: *MachOState,
        frontier: gpu.bootstrap.Frontier,
    ) void {
        return macho_process_graphics_admission.logBootstrapFrontierOccupation(self, frontier);
    }

    pub fn standardStreamPointer(self: *MachOState, symbol_name: []const u8) ?u64 {
        return macho_process_graphics_admission.standardStreamPointer(self, symbol_name);
    }

    pub fn configureGuestLogMirror(self: *MachOState, args: []const []const u8) void {
        return macho_process_graphics_admission.configureGuestLogMirror(self, args);
    }

    pub fn hostWriteFdAll(fd: i32, bytes: []const u8) bool {
        return macho_process_graphics_admission.hostWriteFdAll(fd, bytes);
    }

    pub fn shouldSummarizeGuestLog(level: u8, message: []const u8) bool {
        return macho_process_graphics_admission.shouldSummarizeGuestLog(level, message);
    }

    pub fn shouldSuppressRuntimeGuestLog(message: []const u8) bool {
        return macho_process_graphics_admission.shouldSuppressRuntimeGuestLog(message);
    }

    pub fn emitRuntimeSummaryHeartbeat(self: *const MachOState, snapshot: startup_observer.Snapshot) void {
        return macho_process_graphics_admission.emitRuntimeSummaryHeartbeat(self, snapshot);
    }

    pub fn emitGuestLog(self: *MachOState, prefix_char_raw: u64, address: u64, length_raw: u64) bool {
        return macho_process_graphics_admission.emitGuestLog(self, prefix_char_raw, address, length_raw);
    }

    pub fn logProfileHostPreflight(self: *MachOState, profile_id: []const u8) void {
        return macho_process_graphics_admission.logProfileHostPreflight(self, profile_id);
    }

    pub fn observeProfileAccountFlow(self: *MachOState) void {
        return macho_process_graphics_admission.observeProfileAccountFlow(self);
    }

    pub fn noteProfileAccountOpen(self: *MachOState, path: []const u8, guest_fd: u64) void {
        return macho_process_graphics_admission.noteProfileAccountOpen(self, path, guest_fd);
    }

    pub fn noteProfileAccountRead(self: *MachOState, guest_fd: u64, requested: u64, result: i64, offset: u64) void {
        return macho_process_graphics_admission.noteProfileAccountRead(self, guest_fd, requested, result, offset);
    }

    pub fn observeBackendGuestLog(self: *MachOState, message: []const u8) void {
        return macho_process_graphics_admission.observeBackendGuestLog(self, message);
    }

    pub fn backendMemoryDiagnosticsActive(self: *const MachOState) bool {
        return macho_process_graphics_admission.backendMemoryDiagnosticsActive(self);
    }

    pub fn noteBackendMmapAttempt(self: *MachOState, route: []const u8, address: u64, length: u64, prot: u64, flags: u64, fixed: bool, anonymous: bool) void {
        return macho_process_graphics_admission.noteBackendMmapAttempt(self, route, address, length, prot, flags, fixed, anonymous);
    }

    pub fn noteBackendMmapResult(self: *MachOState, succeeded: bool, result: u64, stage: []const u8) void {
        return macho_process_graphics_admission.noteBackendMmapResult(self, succeeded, result, stage);
    }

    pub fn observeXeniaFixedMemoryView(self: *MachOState, address: u64, length: u64, offset: u64, anonymous: bool) void {
        return macho_process_graphics_admission.observeXeniaFixedMemoryView(self, address, length, offset, anonymous);
    }

    pub fn noteBackendMprotect(self: *MachOState, route: []const u8, address: u64, length: u64, prot: u64, succeeded: bool) void {
        return macho_process_graphics_admission.noteBackendMprotect(self, route, address, length, prot, succeeded);
    }

    pub fn allocGuestFile(self: *MachOState, fd: i32, kind: GuestFileKind) ?u64 {
        return macho_process_graphics_admission.allocGuestFile(self, fd, kind);
    }

    pub fn guestFileFromHandle(self: *MachOState, handle: u64) ?*GuestFile {
        return macho_process_graphics_admission.guestFileFromHandle(self, handle);
    }

    pub fn closeGuestFiles(self: *MachOState) void {
        return macho_process_graphics_admission.closeGuestFiles(self);
    }

    pub fn fileOffsetForVaddr(self: *const MachOState, vaddr: u64) ?u64 {
        return macho_process_graphics_admission.fileOffsetForVaddr(self, vaddr);
    }

    /// F13 (throughput audit): `inline` so the gate is a compare at the call
    /// site. This is reached on every taken conditional jump and every call,
    /// and each of the 12 call sites in `execute` had to materialise a string
    /// constant and set up a six-argument call frame before the function could
    /// decide it had nothing to do.
    pub inline fn logControlFlow(self: *const MachOState, kind: []const u8, from_rip: u64, to_rip: u64, decoded_len: u64, return_addr: ?u64) void {
        return macho_process_graphics_admission.logControlFlow(self, kind, from_rip, to_rip, decoded_len, return_addr);
    }

    pub fn inHelperCluster(self: *const MachOState, rip: u64) bool {
        return macho_process_graphics_admission.inHelperCluster(self, rip);
    }

    pub fn findSharedHelperCluster(self: *const MachOState, helper_rip: u64) ?macho_process_graphics_admission.HelperCluster {
        return macho_process_graphics_admission.findSharedHelperCluster(self, helper_rip);
    }

    pub fn dumpGuestStack(self: *const MachOState) void {
        return macho_process_graphics_admission.dumpGuestStack(self);
    }

    pub inline fn handleStubHelperTransition(self: *MachOState) bool {
        return macho_process_graphics_admission.handleStubHelperTransition(self);
    }

    /// Whether the primitive registry matches this import name. Distinct from
    /// `tryPrimitiveDispatch`: this only asks whether a handler exists, so the
    /// unresolved-import report can distinguish "no handler for this symbol"
    /// from "handler matched but declined this input".
    pub fn primitiveMatches(self: *MachOState, name: []const u8) bool {
        return macho_process_graphics_admission.primitiveMatches(self, name);
    }

    pub fn handleImport(self: *MachOState, imported: macho_metadata.ImportedSymbol) ImportHandlerResult {
        return macho_process_graphics_admission.handleImport(self, imported);
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
        return macho_process_graphics_admission.callGuestFunction(self, fn_address, args);
    }

    pub fn tryPrimitiveDispatch(self: *MachOState, imported: macho_metadata.ImportedSymbol) ?ImportHandlerResult {
        return macho_process_graphics_admission.tryPrimitiveDispatch(self, imported);
    }

    pub fn handleImportImpl(self: *MachOState, imported: macho_metadata.ImportedSymbol) ImportHandlerResult {
        return macho_process_execution_core.handleImportImpl(self, imported);
    }

    pub fn handleVirtualSleepSchedulingBoundary(self: *MachOState, reason: []const u8) bool {
        return macho_process_execution_core.handleVirtualSleepSchedulingBoundary(self, reason);
    }

    pub fn handleDirectImportCall(self: *MachOState, imported: macho_metadata.ImportedSymbol) void {
        return macho_process_execution_core.handleDirectImportCall(self, imported);
    }

    pub fn recordUnresolvedImport(
        self: *MachOState,
        imported: macho_metadata.ImportedSymbol,
        return_address: u64,
        synthetic_result: u64,
    ) void {
        return macho_process_execution_core.recordUnresolvedImport(self, imported, return_address, synthetic_result);
    }

    // F1 (throughput audit): `noinline` on the special-RIP chain and the
    // sentinel handlers. Every one of these is reached at most once per step,
    // and only when `specialRipPossible()` (or a sentinel compare) already
    // said so — which is false for essentially every instruction. Inlined,
    // their bodies and their diagnostic formatting sat inside `step`, on the
    // same cache lines as the fetch/decode/dispatch sequence that does run
    // every instruction. Cost when they do fire: one `bl`.
    pub inline fn continueGuestExit(self: *MachOState) bool {
        return macho_process_execution_core.continueGuestExit(self);
    }

    pub fn handleSigaction(self: *MachOState) u64 {
        return macho_process_execution_core.handleSigaction(self);
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
        return macho_process_execution_core.deliverGuestSignal(self, signal, fault_rip, instruction_len, fault_address, fault_access, fault_width, fault_instruction);
    }

    pub fn signalIsActive(self: *const MachOState, signal: u8) bool {
        return macho_process_execution_core.signalIsActive(self, signal);
    }

    pub fn resetActiveGuestSignalState(self: *MachOState) void {
        return macho_process_execution_core.resetActiveGuestSignalState(self);
    }

    pub fn ensureGuestSignalFrameStorage(self: *MachOState, frame: *GuestSignalFrame) bool {
        return macho_process_execution_core.ensureGuestSignalFrameStorage(self, frame);
    }

    pub inline fn finishGuestSignalReturn(self: *MachOState) bool {
        return macho_process_execution_core.finishGuestSignalReturn(self);
    }

    pub fn terminateForUnresolvedImport(self: *MachOState) void {
        return macho_process_execution_core.terminateForUnresolvedImport(self);
    }

    pub fn recoverLibcppSharedControlBlockCall(
        self: *MachOState,
        instruction_address: u64,
        operand_address: u64,
    ) ?u64 {
        return macho_process_execution_core.recoverLibcppSharedControlBlockCall(self, instruction_address, operand_address);
    }

    /// Static helper: matches XModule vtable symbols.
    pub fn isXModuleMatchesSymbol(symbol: []const u8) bool {
        return macho_process_execution_core.isXModuleMatchesSymbol(symbol);
    }

    pub fn findNearNullBaseTransition(self: *MachOState, register: RegId, terminal_value: u64) ?crash_diag.NearNullBaseTransition {
        return macho_process_execution_core.findNearNullBaseTransition(self, register, terminal_value);
    }

    pub fn ensureXmoduleVtable(self: *MachOState) ?u64 {
        return macho_process_execution_core.ensureXmoduleVtable(self);
    }

    pub fn recoverNearNullBaseRegister(self: *MachOState, d: *DecodedInsn) bool {
        return macho_process_execution_core.recoverNearNullBaseRegister(self, d);
    }

    pub fn recoverNullVtableSlot(self: *MachOState, instruction_address: u64, operand_address: u64) ?u64 {
        return macho_process_execution_core.recoverNullVtableSlot(self, instruction_address, operand_address);
    }

    pub fn logCrashDiagnostics(self: *MachOState, context: ControlTransferContext) void {
        return macho_process_execution_core.logCrashDiagnostics(self, context);
    }

    pub fn terminateForInvalidControlTransfer(self: *MachOState, context: ControlTransferContext) void {
        return macho_process_execution_core.terminateForInvalidControlTransfer(self, context);
    }

    pub fn handleOpen(self: *MachOState) u64 {
        return macho_process_execution_core.handleOpen(self);
    }

    pub fn registerGuestFd(self: *MachOState, host_fd: c_int) ?u64 {
        return macho_process_execution_core.registerGuestFd(self, host_fd);
    }

    pub fn setGuestErrno(self: *MachOState, value: c_int) void {
        return macho_process_execution_core.setGuestErrno(self, value);
    }

    pub fn hostFd(self: *MachOState, guest_or_host_fd: u64) ?c_int {
        return macho_process_execution_core.hostFd(self, guest_or_host_fd);
    }

    pub fn handleFstatat(self: *MachOState) u64 {
        return macho_process_execution_core.handleFstatat(self);
    }

    pub fn handleOpenat(self: *MachOState) u64 {
        return macho_process_execution_core.handleOpenat(self);
    }

    pub fn handleFstat(self: *MachOState) u64 {
        return macho_process_execution_core.handleFstat(self);
    }

    pub fn handleFtruncate(self: *MachOState) u64 {
        return macho_process_execution_core.handleFtruncate(self);
    }

    pub fn handleOpendir(self: *MachOState) ?u64 {
        return macho_process_execution_core.handleOpendir(self);
    }

    pub fn handleClosedir(self: *MachOState) u64 {
        return macho_process_execution_core.handleClosedir(self);
    }

    pub fn handleWrite(self: *MachOState) u64 {
        return macho_process_execution_core.handleWrite(self);
    }

    pub fn handleClose(self: *MachOState) u64 {
        return macho_process_execution_core.handleClose(self);
    }

    pub fn hostWriteAll(self: *MachOState, file: *GuestFile, bytes: []const u8) bool {
        return macho_process_execution_core.hostWriteAll(self, file, bytes);
    }

    pub fn handleFopen(self: *MachOState) ?u64 {
        return macho_process_execution_core.handleFopen(self);
    }

    pub fn handleFdopen(self: *MachOState) ?u64 {
        return macho_process_execution_core.handleFdopen(self);
    }

    pub fn handleFileno(self: *MachOState) u64 {
        return macho_process_execution_core.handleFileno(self);
    }

    pub fn handleFclose(self: *MachOState) u64 {
        return macho_process_execution_core.handleFclose(self);
    }

    pub fn handleFputs(self: *MachOState) u64 {
        return macho_process_execution_core.handleFputs(self);
    }

    pub fn handleFwrite(self: *MachOState) u64 {
        return macho_process_execution_core.handleFwrite(self);
    }

    pub fn handleFread(self: *MachOState) u64 {
        return macho_process_execution_core.handleFread(self);
    }

    pub fn handleFflush(self: *MachOState) u64 {
        return macho_process_execution_core.handleFflush(self);
    }

    pub fn handleFtell(self: *MachOState) u64 {
        return macho_process_execution_core.handleFtell(self);
    }

    pub fn handleFseek(self: *MachOState) u64 {
        return macho_process_execution_core.handleFseek(self);
    }

    pub fn handleFerror(self: *MachOState) u64 {
        return macho_process_execution_core.handleFerror(self);
    }

    pub fn handleFprintf(self: *MachOState) u64 {
        return macho_process_execution_core.handleFprintf(self);
    }

    pub fn handleSnprintf(self: *MachOState) u64 {
        return macho_process_execution_core.handleSnprintf(self);
    }

    pub fn handlePrintfLike(self: *MachOState, file_opt: ?*GuestFile, format_address: u64, arguments: []const u64) u64 {
        return macho_process_execution_core.handlePrintfLike(self, file_opt, format_address, arguments);
    }

    pub fn handlePutchar(self: *MachOState) u64 {
        return macho_process_execution_core.handlePutchar(self);
    }

    pub fn handleGtkInitCheck(self: *MachOState) u64 {
        return macho_process_execution_core.handleGtkInitCheck(self);
    }

    pub fn nextVarArg(self: *const MachOState, arguments: []const u64, gp_index: *usize, stack_arg_addr: *u64) u64 {
        return macho_process_execution_core.nextVarArg(self, arguments, gp_index, stack_arg_addr);
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
    pub fn noteGuestFieldAccess(self: *MachOState, decoded: DecodedInsn) void {
        return macho_process_execution_core.noteGuestFieldAccess(self, decoded);
    }

    pub fn seedProvenanceWatch(self: *MachOState, decoded: DecodedInsn) void {
        return macho_process_execution_core.seedProvenanceWatch(self, decoded);
    }

    pub fn recordTrace(self: *MachOState, decoded: DecodedInsn) void {
        return macho_process_execution_core.recordTrace(self, decoded);
    }

    pub fn shouldTraceRIP(self: *const MachOState, rip: u64) bool {
        return macho_process_execution_core.shouldTraceRIP(self, rip);
    }

    pub fn dumpRecentTrace(self: *const MachOState) void {
        return macho_process_execution_core.dumpRecentTrace(self);
    }

    // F2 (throughput audit): these four forward to the register-file accessors
    // and must not become call frames of their own. Before `inline`, the
    // shipped binary contained 60 out-of-line `bl` to this wrapper and 33 to
    // `setReg` from `execute` alone.
    pub inline fn regVal(self: *const MachOState, id: RegId, size: Size) u64 {
        return macho_process_execution_core.regVal(self, id, size);
    }

    pub inline fn setReg(self: *MachOState, id: RegId, size: Size, val: u64) void {
        return macho_process_execution_core.setReg(self, id, size, val);
    }

    pub inline fn regOperandVal(self: *const MachOState, id: RegId, size: Size, high8: bool) u64 {
        return macho_process_execution_core.regOperandVal(self, id, size, high8);
    }

    pub inline fn setRegOperand(self: *MachOState, id: RegId, size: Size, high8: bool, val: u64) void {
        return macho_process_execution_core.setRegOperand(self, id, size, high8, val);
    }

    pub fn setFlagsSub(self: *MachOState, a: u64, b: u64, result: u64, size: Size) void {
        return macho_process_execution_core.setFlagsSub(self, a, b, result, size);
    }

    pub fn setFlagsAdd(self: *MachOState, a: u64, b: u64, result: u64, size: Size) void {
        return macho_process_execution_core.setFlagsAdd(self, a, b, result, size);
    }

    pub fn setFlagsIncDec(self: *MachOState, input: u64, result: u64, size: Size, is_inc: bool) void {
        return macho_process_execution_core.setFlagsIncDec(self, input, result, size, is_inc);
    }

    pub fn setFlagsLogic(self: *MachOState, result: u64, size: Size) void {
        return macho_process_execution_core.setFlagsLogic(self, result, size);
    }

    pub fn executeHighwayRegisterBinary(self: *MachOState, d: DecodedInsn, op: x64_decoder.highway.BinaryOp, size: Size) void {
        return macho_process_execution_core.executeHighwayRegisterBinary(self, d, op, size);
    }

    pub fn executeHighwayMemoryBinary(
        self: *MachOState,
        d: DecodedInsn,
        op: x64_decoder.highway.BinaryOp,
        size: Size,
        direction: x64_decoder.highway.MemoryDirection,
    ) void {
        return macho_process_execution_core.executeHighwayMemoryBinary(self, d, op, size, direction);
    }

    pub fn executeHighwayImmediate(self: *MachOState, d: DecodedInsn, op: x64_decoder.highway.BinaryOp, size: Size, memory: bool) void {
        return macho_process_execution_core.executeHighwayImmediate(self, d, op, size, memory);
    }

    pub fn setFlag(self: *MachOState, flag: u32, enabled: bool) void {
        return macho_process_execution_core.setFlag(self, flag, enabled);
    }

    pub fn executeBitTestRegister(
        self: *MachOState,
        d: DecodedInsn,
        operation: x64_decoder.BitTestOperation,
        immediate_index: bool,
    ) void {
        return macho_process_execution_core.executeBitTestRegister(self, d, operation, immediate_index);
    }

    pub fn executeBitTestMemory(
        self: *MachOState,
        d: DecodedInsn,
        operation: x64_decoder.BitTestOperation,
        immediate_index: bool,
    ) void {
        return macho_process_execution_core.executeBitTestMemory(self, d, operation, immediate_index);
    }

    pub fn terminateForMemoryAccess(self: *MachOState, check: x64_decoder.highway.MemoryCheck, instruction: []const u8) void {
        return macho_process_execution_core.terminateForMemoryAccess(self, check, instruction);
    }

    pub fn bitWidth(size: Size) u7 {
        return macho_process_execution_core.bitWidth(size);
    }

    pub fn maskForSize(size: Size) u64 {
        return macho_process_execution_core.maskForSize(size);
    }

    pub fn signBitForSize(size: Size) u64 {
        return macho_process_execution_core.signBitForSize(size);
    }

    pub fn arithmeticShiftRight(value: u64, size: Size, count: u6) u64 {
        return macho_process_execution_core.arithmeticShiftRight(value, size, count);
    }

    pub fn setupInitialStack(self: *MachOState, args: []const []const u8) void {
        return macho_process_execution_core.setupInitialStack(self, args);
    }

    pub fn setupMachOState(self: *MachOState, path: []const u8, args: []const []const u8) void {
        return macho_process_execution_core.setupMachOState(self, path, args);
    }

    pub fn initializerAbi(self: *const MachOState) initialization_resolution.AbiSnapshot {
        return macho_process_execution_core.initializerAbi(self);
    }

    pub fn beginInitializerTransaction(self: *MachOState) void {
        return macho_process_execution_core.beginInitializerTransaction(self);
    }

    pub fn rollbackInitializerTransaction(self: *MachOState) bool {
        return macho_process_execution_core.rollbackInitializerTransaction(self);
    }

    pub fn commitInitializerTransaction(self: *MachOState) bool {
        return macho_process_execution_core.commitInitializerTransaction(self);
    }

    pub fn runOneInitializer(self: *MachOState, launch_regs: Regs, index: usize, is_retry: bool) InitializerRunOutcome {
        return macho_process_execution_core.runOneInitializer(self, launch_regs, index, is_retry);
    }

    pub fn runInitializers(self: *MachOState) bool {
        return macho_process_execution_core.runInitializers(self);
    }

    pub fn appendTrivialVector(self: *MachOState, vector: u64, item: u64, element_size: u64, minimum_capacity: u32) bool {
        return macho_process_execution_core.appendTrivialVector(self, vector, item, element_size, minimum_capacity);
    }

    pub fn handleLibcppBasicStringSubstr(self: *MachOState) bool {
        return macho_process_execution_core.handleLibcppBasicStringSubstr(self);
    }

    pub inline fn handleInternalCompatibility(self: *MachOState) bool {
        return macho_process_execution_core.handleInternalCompatibility(self);
    }

    pub fn handlePageEntryBulkInitialization(self: *MachOState) bool {
        return macho_process_execution_core.handlePageEntryBulkInitialization(self);
    }

    pub fn handleLocalLibcppStreamCompatibility(self: *MachOState) bool {
        return macho_process_execution_core.handleLocalLibcppStreamCompatibility(self);
    }

    pub fn capturePositionalLaunchOptions(self: *MachOState) void {
        return macho_process_execution_core.capturePositionalLaunchOptions(self);
    }

    pub fn handleGuestLogBridge(self: *MachOState) bool {
        return macho_process_execution_core.handleGuestLogBridge(self);
    }

    pub fn handleCxxoptsSplitOptionNames(self: *MachOState) bool {
        return macho_process_execution_core.handleCxxoptsSplitOptionNames(self);
    }

    pub inline fn handleTomlAsciiFastPath(self: *MachOState) bool {
        return macho_process_execution_core.handleTomlAsciiFastPath(self);
    }

    pub inline fn handleTomlReadNextIntegrity(self: *MachOState) void {
        return macho_process_execution_core.handleTomlReadNextIntegrity(self);
    }

    pub inline fn handlePatchDbEmptyPatchArray(self: *MachOState) bool {
        return macho_process_execution_core.handlePatchDbEmptyPatchArray(self);
    }

    pub fn logStalledInstructionDetails(self: *MachOState) void {
        return macho_process_execution_core.logStalledInstructionDetails(self);
    }

    pub fn executionFingerprint(self: *const MachOState) u64 {
        return macho_process_execution_core.executionFingerprint(self);
    }

    pub fn executableInstructionBytesAt(self: *const MachOState, address: u64) ?[]const u8 {
        return macho_process_execution_core.executableInstructionBytesAt(self, address);
    }

    /// Classify a successful instruction fetch without consulting mutable
    /// sparse-page state. An address in the immutable image is static code;
    /// the reserved high address bands are bridge/thunk code; every other
    /// successful executable fetch is generated code. The cache never stores
    /// an entry for an unmapped address, so treating the remaining space as
    /// dynamic is safe and keeps the hot lookup to range compares rather than
    /// another page-table probe.
    pub inline fn translationDomainFor(self: *const MachOState, address: u64) translation_domain.Domain {
        return macho_process_execution_core.translationDomainFor(self, address);
    }

    pub inline fn decodeCacheSetBaseFor(self: *const MachOState, address: u64, domain: translation_domain.Domain) usize {
        return macho_process_execution_core.decodeCacheSetBaseFor(self, address, domain);
    }

    pub inline fn decodeCacheSetBaseForChoice(
        self: *const MachOState,
        address: u64,
        domain: translation_domain.Domain,
        choice: usize,
    ) usize {
        return macho_process_execution_core.decodeCacheSetBaseForChoice(self, address, domain, choice);
    }

    pub inline fn decodeCacheSetBasesFor(
        self: *const MachOState,
        address: u64,
        domain: translation_domain.Domain,
    ) [translation_cache.primary_set_choice_count]usize {
        return macho_process_execution_core.decodeCacheSetBasesFor(self, address, domain);
    }

    pub inline fn decodeCacheAlternateSetBaseFor(
        self: *const MachOState,
        address: u64,
        domain: translation_domain.Domain,
    ) usize {
        return macho_process_execution_core.decodeCacheAlternateSetBaseFor(self, address, domain);
    }

    pub inline fn decodeVictimCacheSetBaseFor(self: *const MachOState, address: u64, domain: translation_domain.Domain) usize {
        return macho_process_execution_core.decodeVictimCacheSetBaseFor(self, address, domain);
    }

    pub inline fn noteDecodeDomainHit(self: *MachOState, domain: translation_domain.Domain) void {
        return macho_process_execution_core.noteDecodeDomainHit(self, domain);
    }

    pub inline fn noteDecodeDomainMiss(self: *MachOState, domain: translation_domain.Domain) void {
        return macho_process_execution_core.noteDecodeDomainMiss(self, domain);
    }

    pub inline fn noteDecodeDomainFill(self: *MachOState, domain: translation_domain.Domain) void {
        return macho_process_execution_core.noteDecodeDomainFill(self, domain);
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
    pub fn specialRipPossible(self: *const MachOState) bool {
        return macho_process_execution_core.specialRipPossible(self);
    }

    /// R2 (N3): collect every fixed special-RIP address the per-instruction
    /// handler chain probes, sort and deduplicate, and publish the table. The
    /// array is bounded (26 internal targets + 32 cvar vector slots + 2 toml
    /// entries), so a fixed stack buffer avoids intermediate allocation.
    pub fn buildSpecialRipTable(self: *MachOState) !void {
        return macho_process_execution_core.buildSpecialRipTable(self);
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
        return macho_process_execution_core.addressNeedsLiveRegisters(decoded);
    }

    /// Give a used way a second chance.
    ///
    /// The former rule cleared every other way when one was touched. That was
    /// exact enough for two ways, but with a wider set it made the last
    /// unmarked array element absorb nearly every eviction. Reference bits
    /// retain all recently used ways; the miss path clears a set only after
    /// every resident earned a chance. A hot hit that is already marked still
    /// performs no store.
    pub inline fn noteDecodeCacheUse(ways: []DecodeCacheEntry, used: *DecodeCacheEntry) void {
        return macho_process_execution_core.noteDecodeCacheUse(ways, used);
    }

    pub inline fn noteDecodeCacheReuse(entry: *DecodeCacheEntry) void {
        return macho_process_execution_core.noteDecodeCacheReuse(entry);
    }

    pub inline fn resolveCachedDecode(self: *MachOState, entry: *const DecodeCacheEntry) DecodedInsn {
        return macho_process_execution_core.resolveCachedDecode(self, entry);
    }

    pub inline fn decodeCacheEntryOccupied(entry: *const DecodeCacheEntry) bool {
        return macho_process_execution_core.decodeCacheEntryOccupied(entry);
    }

    const DecodeCacheSelection = struct {
        entry: *DecodeCacheEntry,
        empty: bool,
    };

    /// One bank's measured occupancy, from a bounded uniform sample.
    const BankOccupancy = struct {
        capacity: usize,
        sampled_sets: usize,
        sampled_entries: usize,
        occupied: usize,

        pub fn percent(self: BankOccupancy) usize {
            if (self.sampled_entries == 0) return 0;
            return (self.occupied * 100) / self.sampled_entries;
        }

        /// The whole bank's live entry count, estimated from the sample.
        pub fn estimated(self: BankOccupancy) usize {
            if (self.sampled_entries == 0) return 0;
            return (self.occupied * self.capacity) / self.sampled_entries;
        }
    };

    /// Sample a bank's occupancy rather than counting it on the hot path.
    ///
    /// Occupancy is the number that decides whether a bank is about to start
    /// evicting, and nothing was reporting it: the 2026-09-07 run printed
    /// per-domain hits, misses and fills at every checkpoint while the static
    /// bank sat at 86% and two other banks had never held a single decode.
    /// Fills alone cannot say that — they never come back down.
    ///
    /// A live counter would need a decrement at every clear site (precise
    /// invalidation, stale rejection, coarse flush) and would silently lie
    /// after the first missed one. A stride sample cannot drift, costs nothing
    /// between checkpoints, and is far more precise than the question needs:
    /// 1/64th of a bank is tens of thousands of entries, so the estimate is
    /// within a fraction of a percent.
    pub fn sampleBankOccupancy(self: *const MachOState, domain: translation_domain.Domain) BankOccupancy {
        return macho_process_execution_core.sampleBankOccupancy(self, domain);
    }

    const PrimaryDecodeCacheSelection = struct {
        entry: *DecodeCacheEntry,
        empty: bool,
        set_base: usize,
    };

    /// Choose a way using the standalone cache contract's second-chance plus
    /// reuse-count policy. L2 restores are hits in the translation hierarchy,
    /// but they still need to install a copy into L1 without discarding a hot
    /// resident merely because it is the first unmarked array element.
    pub fn selectDecodeCacheWay(ways: []DecodeCacheEntry) DecodeCacheSelection {
        return macho_process_execution_core.selectDecodeCacheWay(ways);
    }

    /// Choose a primary destination from both independently hashed set
    /// choices, comparing their depth rather than taking the first that has
    /// room.
    ///
    /// Returning the first choice with a free way is first-fit, and it wastes
    /// the second hash: the alternate set is only ever consulted for an
    /// address whose first choice is already completely full, so set depth
    /// follows the single-choice balls-in-bins tail. That is what produced the
    /// 2026-09-07 `cold-eviction` at `spirv_cross::Parser::parse+0x397` —
    /// 470,192 fills into a bank that was 45% occupied, with one address
    /// unlucky enough to hash to two sixteen-deep sets. Comparing the two
    /// depths holds the same stream at ten of sixteen; the contract's
    /// `chooseSet` carries the measurement.
    ///
    /// Occupancy is counted with a side-effect-free scan so the replacement
    /// policy — which clears reference bits when the epoch rolls — never runs
    /// on a set this fill is not going to use. It is also the same 32 ways the
    /// lookup immediately above just walked to declare the miss, so the lines
    /// are already resident.
    pub fn selectPrimaryDecodeCacheSet(
        self: *MachOState,
        set_bases: [translation_cache.primary_set_choice_count]usize,
    ) PrimaryDecodeCacheSelection {
        return macho_process_execution_core.selectPrimaryDecodeCacheSet(self, set_bases);
    }

    /// Retain an immutable image decode that is being displaced from the
    /// primary cache. This is intentionally independent of the
    /// generation-keyed L1: writes to generated code must not age image
    /// entries out of the only cache that can cheaply recover them.
    ///
    /// Called on eviction, never on a fill. Populating it from the fill path
    /// made it write-only: a fill happens because the address was in no tier,
    /// so the copy could not be answering any future lookup that the primary
    /// would not have answered first. The 2026-09-07 run measured exactly
    /// that — `static_l2(entries/hits/fills)=131072/0/903034`, 903,034 copies
    /// of a 104-byte entry into a 13 MiB table that was never once read. An
    /// eviction is the only event that can make a later lookup need this tier.
    pub fn saveStaticDecodeL2(self: *MachOState, source: *const DecodeCacheEntry) void {
        return macho_process_execution_core.saveStaticDecodeL2(self, source);
    }

    /// Restore an image decode that was displaced from the primary set. A
    /// static L2 hit is a translation hit: no source-byte fetch, generation
    /// check, or decoder invocation is needed. Any primary entry displaced by
    /// the restore still goes through the ordinary victim cache.
    pub fn restoreStaticDecodeL2(
        self: *MachOState,
        fetch_address: u64,
        primary_ways: []DecodeCacheEntry,
    ) ?DecodedInsn {
        return macho_process_execution_core.restoreStaticDecodeL2(self, fetch_address, primary_ways);
    }

    /// Clear static L2 entries whose instruction bytes overlap a range that is
    /// being unmapped, reprotected, or written. Static image code is expected
    /// to be immutable, but this explicit boundary preserves correctness if a
    /// loader or patcher changes it through a route outside noteGuestWrite.
    pub fn invalidateStaticDecodeL2Range(self: *MachOState, address: u64, count: u64) void {
        return macho_process_execution_core.invalidateStaticDecodeL2Range(self, address, count);
    }

    /// Preserve a primary victim in the bounded second-level cache. This is
    /// called only on a primary replacement, never on the common hit path.
    pub fn saveDecodeCacheVictim(self: *MachOState, evicted: *const DecodeCacheEntry) void {
        return macho_process_execution_core.saveDecodeCacheVictim(self, evicted);
    }

    /// Restore a primary entry displaced by a short-lived working-set burst.
    /// The swap makes the old primary slot a new victim, so repeated return to
    /// the same code does not allocate or decode again.
    pub fn restoreDecodeCacheVictim(
        self: *MachOState,
        fetch_address: u64,
        destination: *DecodeCacheEntry,
    ) ?DecodedInsn {
        return macho_process_execution_core.restoreDecodeCacheVictim(self, fetch_address, destination);
    }

    /// The decode-cache entry for the current RIP, when one exists that was
    /// filled with the full validation gate chain already run and declined
    /// (not a special-RIP target, executable, config parsing idle, table
    /// intact). On such a hit the per-instruction gate chain is provably
    /// redundant, so `step` skips it. This returns the decoded instruction as
    /// well as the cached host-image classification, avoiding a second probe
    /// in `decodeWithLiveOperands`.
    pub inline fn decodeFastPlain(self: *MachOState) ?FastPlainDecode {
        return macho_process_execution_core.decodeFastPlain(self);
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
    pub fn decodeWithLiveOperands(self: *MachOState, gates_free: bool) ?DecodedInsn {
        return macho_process_execution_core.decodeWithLiveOperands(self, gates_free);
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
    pub inline fn reportDecodeFailure(self: *MachOState) bool {
        return macho_process_execution_core.reportDecodeFailure(self);
    }

    /// Operator-requested per-instruction trace for an explicit RIP window.
    /// Inert unless `trace_range_start` was set, so its formatting has no
    /// business sharing cache lines with the dispatch sequence.
    pub inline fn emitTargetTrace(self: *MachOState, decoded: DecodedInsn) void {
        return macho_process_execution_core.emitTargetTrace(self, decoded);
    }

    /// Fires once, on the 24th recorded bootstrap instruction.
    pub inline fn reportCoopBootstrapComplete(self: *MachOState) void {
        return macho_process_execution_core.reportCoopBootstrapComplete(self);
    }

    /// RIP is not an executable instruction target: either a recoverable
    /// generated-dispatch miss, or the end of the run.
    ///
    /// Held off the fetch path for the same reason as the two reporters below
    /// it. The recovery attempt lives here too rather than at the call site,
    /// because it is reached only through this same failed predicate — one
    /// `bl` on a path taken once per process, against a branch that `step`
    /// evaluates on every instruction.
    pub inline fn recoverNonExecutableRip(self: *MachOState) bool {
        return macho_process_execution_core.recoverNonExecutableRip(self);
    }

    pub inline fn reportInvalidInstruction(self: *MachOState) bool {
        return macho_process_execution_core.reportInvalidInstruction(self);
    }

    pub fn observeApplicationControlTransfer(self: *MachOState, decoded: DecodedInsn, source: u64) void {
        return macho_process_execution_core.observeApplicationControlTransfer(self, decoded, source);
    }

    pub fn step(self: *MachOState) bool {
        return macho_process_run_loop.step(self);
    }

    pub fn beginCooperativeMainLoop(self: *MachOState) bool {
        return macho_process_run_loop.beginCooperativeMainLoop(self);
    }

    pub fn startDeferredGuestThread(self: *MachOState, deferred: pthread_runtime.DeferredThread) bool {
        return macho_process_run_loop.startDeferredGuestThread(self, deferred);
    }

    pub fn saveActiveGuestThread(self: *MachOState, reason: []const u8) bool {
        return macho_process_run_loop.saveActiveGuestThread(self, reason);
    }

    // Suspended workers are a FIFO queue.  A LIFO pop would immediately resume
    // the same worker that just yielded once all deferred threads had started.
    pub fn resumeSuspendedGuestThread(self: *MachOState) bool {
        return macho_process_run_loop.resumeSuspendedGuestThread(self);
    }

    pub fn yieldActiveGuestThreadForWait(self: *MachOState, reason: []const u8) bool {
        return macho_process_run_loop.yieldActiveGuestThreadForWait(self, reason);
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
        return macho_process_run_loop.maybeYieldActiveGuestThreadForQuantum(self);
    }

    pub fn refreshSuspendedRunnableCache(self: *MachOState) usize {
        return macho_process_run_loop.refreshSuspendedRunnableCache(self);
    }

    pub inline fn finishActiveGuestThread(self: *MachOState) void {
        return macho_process_run_loop.finishActiveGuestThread(self);
    }

    /// Queue a GTK signal handler (more than one argument, unlike a
    /// `GSourceFunc`). Used by the modelled `gtk_widget_queue_draw`.
    pub fn scheduleSignalCallback(self: *MachOState, function: u64, arg0: u64, arg1: u64, arg2: u64, tag: []const u8) u64 {
        return macho_process_run_loop.scheduleSignalCallback(self, function, arg0, arg1, arg2, tag);
    }

    pub fn scheduleIdleCallback(self: *MachOState, function: u64, data: u64, tag: []const u8) u64 {
        return macho_process_run_loop.scheduleIdleCallback(self, function, data, tag);
    }

    /// Queue a UI callback that has an explicit guest-side completion fence.
    /// Ordinary GTK idle sources remain detached because their API is
    /// fire-and-forget; this entry point is reserved for a proven rendezvous.
    pub fn scheduleRendezvousIdleCallback(self: *MachOState, function: u64, data: u64, tag: []const u8) u64 {
        return macho_process_run_loop.scheduleRendezvousIdleCallback(self, function, data, tag);
    }

    pub fn isIdleCallbackPending(self: *const MachOState, source: u64) bool {
        return macho_process_run_loop.isIdleCallbackPending(self, source);
    }

    pub fn pendingIdleCallbackCount(self: *const MachOState) usize {
        return macho_process_run_loop.pendingIdleCallbackCount(self);
    }

    pub fn gtkIdleQueueSnapshot(self: *const MachOState) IdleQueueSnapshot {
        return macho_process_run_loop.gtkIdleQueueSnapshot(self);
    }

    pub fn gtkIdleDispatchBlock(self: *const MachOState) IdleDispatchBlock {
        return macho_process_run_loop.gtkIdleDispatchBlock(self);
    }

    pub fn removeIdleSource(self: *MachOState, source: u64) bool {
        return macho_process_run_loop.removeIdleSource(self, source);
    }

    pub fn startNextIdleCallback(self: *MachOState, reason: []const u8, active_already_saved: bool) bool {
        return macho_process_run_loop.startNextIdleCallback(self, reason, active_already_saved);
    }

    pub fn isSyntheticCallbackHandle(self: *const MachOState, handle: u64) bool {
        return macho_process_run_loop.isSyntheticCallbackHandle(self, handle);
    }

    // GTK idle sources and SDL audio callbacks share one stack — the
    // cooperative UI context's. Entering a second one while the first is only
    // suspended writes over its live frames.
    pub fn syntheticCallbackStackBusy(self: *const MachOState) bool {
        return macho_process_run_loop.syntheticCallbackStackBusy(self);
    }

    pub fn syntheticCallbackStackOwner(self: *const MachOState) u64 {
        return macho_process_run_loop.syntheticCallbackStackOwner(self);
    }

    pub fn noteSyntheticStackEntry(self: *MachOState, handle: u64) void {
        return macho_process_run_loop.noteSyntheticStackEntry(self, handle);
    }

    pub fn isIdleCallbackHandle(self: *const MachOState, handle: u64) bool {
        return macho_process_run_loop.isIdleCallbackHandle(self, handle);
    }

    pub fn currentCooperativeThreadHandle(self: *const MachOState) u64 {
        return macho_process_run_loop.currentCooperativeThreadHandle(self);
    }

    pub fn threadNumericId(self: *const MachOState, handle: u64) u64 {
        return macho_process_run_loop.threadNumericId(self, handle);
    }

    pub fn threadRole(self: *const MachOState, handle: u64, address: u64) []const u8 {
        return macho_process_run_loop.threadRole(self, handle, address);
    }

    pub fn contextContainsHandle(self: *const MachOState, handle: u64) bool {
        return macho_process_run_loop.contextContainsHandle(self, handle);
    }

    pub fn logAudioCallbackSchedulerState(self: *const MachOState) void {
        return macho_process_run_loop.logAudioCallbackSchedulerState(self);
    }

    pub fn runnableSuspendedSnapshot(self: *const MachOState) RunnableSuspendedSnapshot {
        return macho_process_run_loop.runnableSuspendedSnapshot(self);
    }

    pub fn logThreadTable(self: *const MachOState, reason: []const u8) void {
        return macho_process_run_loop.logThreadTable(self, reason);
    }

    pub fn restoreMainLoopCaller(self: *MachOState, reason: []const u8) void {
        return macho_process_run_loop.restoreMainLoopCaller(self, reason);
    }

    pub fn logCooperativeSchedulerSummary(self: *const MachOState) void {
        return macho_process_run_loop.logCooperativeSchedulerSummary(self);
    }

    pub fn logCooperativeHeartbeat(self: *MachOState) void {
        return macho_process_run_loop.logCooperativeHeartbeat(self);
    }

    pub fn dumpCoopHeartbeatTrace(self: *const MachOState) void {
        return macho_process_run_loop.dumpCoopHeartbeatTrace(self);
    }

    pub fn dumpUiHandoffTrace(self: *const MachOState) void {
        return macho_process_run_loop.dumpUiHandoffTrace(self);
    }

    // Once the Xenia PageEntry tables have been allocated, setup can spend a
    // long time in memory-manager code without crossing another import
    // boundary. Keep a compact, high-frequency checkpoint so a stalled
    // backing-map or heap pass is observable in the next external run.
    pub fn logMemoryInitializationProgress(self: *MachOState, steps: u64) void {
        return macho_process_run_loop.logMemoryInitializationProgress(self, steps);
    }

    pub inline fn handleSyntheticRuntimeThunk(self: *MachOState) bool {
        return macho_process_run_loop.handleSyntheticRuntimeThunk(self);
    }

    pub inline fn handleTlvBootstrap(self: *MachOState) bool {
        return macho_process_run_loop.handleTlvBootstrap(self);
    }

    pub inline fn handleBoundImportThunk(self: *MachOState) bool {
        return macho_process_run_loop.handleBoundImportThunk(self);
    }

    pub inline fn handleDynamicLibraryThunk(self: *MachOState) bool {
        return macho_process_run_loop.handleDynamicLibraryThunk(self);
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
    pub inline fn reportProgressCheckpoint(self: *MachOState, steps: u64) void {
        return macho_process_run_loop.reportProgressCheckpoint(self, steps);
    }

    /// Where a sampled program counter lives, for the execution profile.
    ///
    /// The profile can classify a name but not an address, and the one thing a
    /// name can never say is that no name was ever possible. An address
    /// outside every image section, in memory this run made executable, is the
    /// emulator's own generated code — Xenia's code cache at 0xA0000000 is the
    /// whole of it here. Reporting that as an unresolved symbol sent the
    /// reader to repair a symbol table that had nothing wrong with it, and
    /// stopped the run on an observation debt that could never be paid.
    pub fn executionProfileOrigin(
        self: *MachOState,
        address: u64,
    ) diagnostics_execution_profile.Origin {
        return macho_process_run_loop.executionProfileOrigin(self, address);
    }

    pub inline fn reportHeartbeat(self: *MachOState, steps: u64) void {
        return macho_process_run_loop.reportHeartbeat(self, steps);
    }

    /// Try to find real queued work for a parked cooperative context, and
    /// terminate with a precise invariant failure if there is none.
    ///
    /// Returns false when the caller must stop; the register file after the
    /// scheduler has parked its owner is the last saved context, not executable
    /// work, and interpreting it would manufacture millions of meaningless
    /// steps rather than reporting the deadlock.
    pub inline fn recoverZeroActiveGuestThread(self: *MachOState) bool {
        return macho_process_run_loop.recoverZeroActiveGuestThread(self);
    }

    pub inline fn reportConciseProgress(self: *MachOState, steps: u64) void {
        return macho_process_run_loop.reportConciseProgress(self, steps);
    }

    pub fn run(self: *MachOState) void {
        return macho_process_run_loop.run(self);
    }

    /// Everything `run` does after its loop ends: reason normalisation, exit
    /// diagnostics, and the two process-exit event records.
    ///
    /// F1 (throughput audit): runs exactly once per process, and was inlined
    /// into `run` alongside the loop body. Extracting it (with the three
    /// periodic reporters above) took `run` from 99,272 bytes to a loop that
    /// fits alongside the rest of the interpreter in L1I.
    pub inline fn finishRun(self: *MachOState, steps: u64) void {
        return macho_process_run_loop.finishRun(self, steps);
    }

    /// Converts the async-signal-safe host request into normal interpreter
    /// state. Called only at existing 500K-step checkpoints, avoiding another
    /// load/branch in the per-instruction hot path.
    pub fn consumeHostTerminationRequest(self: *MachOState) bool {
        return macho_process_run_loop.consumeHostTerminationRequest(self);
    }

    pub inline fn logHostTerminationSnapshot(self: *MachOState, steps: u64) void {
        return macho_process_run_loop.logHostTerminationSnapshot(self, steps);
    }

    pub fn logDecodeCacheSummary(self: *const MachOState) void {
        return macho_process_run_loop.logDecodeCacheSummary(self);
    }

    /// Mutable, unlike the summaries below it: the sampler has to retain the
    /// previous reading in order to report a delta.
    pub fn logPerformanceHeartbeat(self: *MachOState) void {
        return macho_process_run_loop.logPerformanceHeartbeat(self);
    }

    pub fn logPerformanceAccelerationSummary(self: *const MachOState) void {
        return macho_process_run_loop.logPerformanceAccelerationSummary(self);
    }

    pub fn logSharedControlBlockSummary(self: *const MachOState) void {
        return macho_process_run_loop.logSharedControlBlockSummary(self);
    }

    pub fn logExitDiagnostics(self: *MachOState) void {
        return macho_process_run_loop.logExitDiagnostics(self);
    }

    pub fn releaseBarrier() void {
        return macho_process_run_loop.releaseBarrier();
    }

    pub fn logAtomicDiagnostic(self: *MachOState, matched: bool, size: Size, addr: u64, expected: u64, actual: u64, replacement: u64, is_locked: bool, rax_before: u64, rflags_before: u32) void {
        return macho_process_run_loop.logAtomicDiagnostic(self, matched, size, addr, expected, actual, replacement, is_locked, rax_before, rflags_before);
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

        pub const HOT_THRESHOLD: u64 = 1_000_000;
        pub const PROGRESS_LOG_INTERVAL: u32 = 100;
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
        pub fn onProcessBytesEntry(self: *@This(), state: *MachOState) void {
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

        pub fn logSha1Progress(self: *@This(), state: *MachOState) void {
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
        return macho_process_run_loop.execute(self, initial_d);
    }

    pub fn executeFucomip(self: *MachOState, source: u3) void {
        return macho_process_run_loop.executeFucomip(self, source);
    }

    pub fn executeFucomi(self: *MachOState, source: u3) void {
        return macho_process_run_loop.executeFucomi(self, source);
    }

    pub fn executeFcomi(self: *MachOState, source: u3) void {
        return macho_process_run_loop.executeFcomi(self, source);
    }

    pub fn executeFcomip(self: *MachOState, source: u3) void {
        return macho_process_run_loop.executeFcomip(self, source);
    }

    pub fn executeFcmov(self: *MachOState, source: u3, condition: Cond) void {
        return macho_process_run_loop.executeFcmov(self, source, condition);
    }

    pub fn executeBitScan(self: *MachOState, d: DecodedInsn) void {
        return macho_process_run_loop.executeBitScan(self, d);
    }

    pub fn executeRotate(self: *MachOState, d: DecodedInsn) void {
        return macho_process_run_loop.executeRotate(self, d);
    }

    pub fn executeVexScalarF32(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        return macho_process_run_loop.executeVexScalarF32(self, d, operation);
    }

    pub fn executeVexScalarF64(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        return macho_process_run_loop.executeVexScalarF64(self, d, operation);
    }

    pub fn executeVexPackedF32(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        return macho_process_run_loop.executeVexPackedF32(self, d, operation);
    }

    pub fn executeVexPackedF64(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        return macho_process_run_loop.executeVexPackedF64(self, d, operation);
    }

    pub fn executeVexSqrtScalarF32(self: *MachOState, d: DecodedInsn) void {
        return macho_process_run_loop.executeVexSqrtScalarF32(self, d);
    }

    pub fn executeVexSqrtScalarF64(self: *MachOState, d: DecodedInsn) void {
        return macho_process_run_loop.executeVexSqrtScalarF64(self, d);
    }

    /// A comparison whose predicate this interpreter does not model must not
    /// silently write a mask: the guest would branch on it and nothing would
    /// record that the branch was decided by a guess.
    pub fn reportUnsupportedComparePredicate(self: *MachOState, d: DecodedInsn, executed: bool) void {
        return macho_process_run_loop.reportUnsupportedComparePredicate(self, d, executed);
    }

    pub fn executeVexReciprocalPacked(self: *MachOState, d: DecodedInsn, comptime square_root: bool) void {
        return macho_process_run_loop.executeVexReciprocalPacked(self, d, square_root);
    }

    pub fn executeVexReciprocalScalar(self: *MachOState, d: DecodedInsn, comptime square_root: bool) void {
        return macho_process_run_loop.executeVexReciprocalScalar(self, d, square_root);
    }

    pub fn executeVexConvertPacked(
        self: *MachOState,
        d: DecodedInsn,
        comptime direction: @TypeOf(.enum_literal),
    ) void {
        return macho_process_run_loop.executeVexConvertPacked(self, d, direction);
    }

    pub fn executeVexComparePacked(self: *MachOState, d: DecodedInsn, comptime double: bool) bool {
        return macho_process_run_loop.executeVexComparePacked(self, d, double);
    }

    pub fn executeVexCompareScalar(self: *MachOState, d: DecodedInsn, comptime double: bool) bool {
        return macho_process_run_loop.executeVexCompareScalar(self, d, double);
    }

    pub fn executeVexSqrtPackedF32(self: *MachOState, d: DecodedInsn) void {
        return macho_process_run_loop.executeVexSqrtPackedF32(self, d);
    }

    pub fn executeVexSqrtPackedF64(self: *MachOState, d: DecodedInsn) void {
        return macho_process_run_loop.executeVexSqrtPackedF64(self, d);
    }

    pub fn setVexComparisonFlags(self: *MachOState, lhs: anytype, rhs: @TypeOf(lhs)) void {
        return macho_process_run_loop.setVexComparisonFlags(self, lhs, rhs);
    }

    pub fn executeVexBitwise(self: *MachOState, d: DecodedInsn, operation: VexBitwise) void {
        return macho_process_run_loop.executeVexBitwise(self, d, operation);
    }

    pub fn executeAddRegImm(self: *MachOState, d: DecodedInsn, sz: Size) void {
        return macho_process_run_loop.executeAddRegImm(self, d, sz);
    }

    pub fn raiseDivideError(self: *MachOState) void {
        return macho_process_run_loop.raiseDivideError(self);
    }

    pub fn executeSubRegImm(self: *MachOState, d: DecodedInsn, sz: Size) void {
        return macho_process_run_loop.executeSubRegImm(self, d, sz);
    }

    pub fn executeAndRegImm(self: *MachOState, d: DecodedInsn) void {
        return macho_process_run_loop.executeAndRegImm(self, d);
    }

    pub fn resolveSyscallFd(self: *MachOState, guest_fd: u64) i32 {
        return macho_process_run_loop.resolveSyscallFd(self, guest_fd);
    }

    pub fn dispatchMacOSSyscall(self: *MachOState, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64, arg6: u64) void {
        return macho_process_run_loop.dispatchMacOSSyscall(self, arg1, arg2, arg3, arg4, arg5, arg6);
    }
};

/// Narrow export table used only by split Mach-O process modules.
pub const __ProcessInternals = struct {
    pub const _AllocationWriteRecord = AllocationWriteRecord;
    pub const _BOUND_IMPORT_THUNK_BASE = BOUND_IMPORT_THUNK_BASE;
    pub const _BitScanKind = BitScanKind;
    pub const _BoundImportThunk = BoundImportThunk;
    pub const _BulkConstructionRange = BulkConstructionRange;
    pub const _CONCISE_PROGRESS_INTERVAL = CONCISE_PROGRESS_INTERVAL;
    pub const _COOPERATIVE_THREAD_QUANTUM_STEPS = COOPERATIVE_THREAD_QUANTUM_STEPS;
    pub const _Cond = Cond;
    pub const _ControlTransferContext = ControlTransferContext;
    pub const _CooperativeUiContext = CooperativeUiContext;
    pub const _DARWIN_MCONTEXT_SIZE = DARWIN_MCONTEXT_SIZE;
    pub const _DARWIN_SIGACTION_SIZE = DARWIN_SIGACTION_SIZE;
    pub const _DARWIN_SIGINFO_SIZE = DARWIN_SIGINFO_SIZE;
    pub const _DARWIN_UCONTEXT_SIZE = DARWIN_UCONTEXT_SIZE;
    pub const _DECODE_CACHE_ENTRY_COUNT = DECODE_CACHE_ENTRY_COUNT;
    pub const _DEFAULT_GUEST_THREAD_STACK_SIZE = DEFAULT_GUEST_THREAD_STACK_SIZE;
    pub const _DecodeCacheEntry = DecodeCacheEntry;
    pub const _DecodedInsn = DecodedInsn;
    pub const _ENDIAN_EVIDENCE_BUFFER_LEN = ENDIAN_EVIDENCE_BUFFER_LEN;
    pub const _ExecutionHistory = ExecutionHistory;
    pub const _FastPlainDecode = FastPlainDecode;
    pub const _GUEST_ATEXIT_RETURN_SENTINEL = GUEST_ATEXIT_RETURN_SENTINEL;
    pub const _GUEST_FILE_BASE = GUEST_FILE_BASE;
    pub const _GUEST_FILE_MAX = GUEST_FILE_MAX;
    pub const _GUEST_LOG_BUFFER_SIZE = GUEST_LOG_BUFFER_SIZE;
    pub const _GUEST_SIGILL = GUEST_SIGILL;
    pub const _GUEST_SIGNAL_ACTION_COUNT = GUEST_SIGNAL_ACTION_COUNT;
    pub const _GUEST_SIGNAL_FRAME_DEPTH = GUEST_SIGNAL_FRAME_DEPTH;
    pub const _GUEST_SIGNAL_RETURN_SENTINEL = GUEST_SIGNAL_RETURN_SENTINEL;
    pub const _GUEST_SIGSEGV = GUEST_SIGSEGV;
    pub const _GUEST_THREAD_RETURN_SENTINEL = GUEST_THREAD_RETURN_SENTINEL;
    pub const _GtkBootstrapEntry = GtkBootstrapEntry;
    pub const _GtkHeartbeatEntry = GtkHeartbeatEntry;
    pub const _GuestAccess = GuestAccess;
    pub const _GuestAccessDescription = GuestAccessDescription;
    pub const _GuestFile = GuestFile;
    pub const _GuestFileKind = GuestFileKind;
    pub const _GuestSignalAction = GuestSignalAction;
    pub const _GuestSignalFrame = GuestSignalFrame;
    pub const _HEARTBEAT_INTERVAL = HEARTBEAT_INTERVAL;
    pub const _IDLE_CALLBACK_HANDLE_BASE = IDLE_CALLBACK_HANDLE_BASE;
    pub const _IDLE_STARVATION_STEPS = IDLE_STARVATION_STEPS;
    pub const _IMPORT_ROUTE_CACHE_SIZE = IMPORT_ROUTE_CACHE_SIZE;
    pub const _IMPORT_TRACE_BUFFER_LEN = IMPORT_TRACE_BUFFER_LEN;
    pub const _INITIALIZER_RETURN_SENTINEL = INITIALIZER_RETURN_SENTINEL;
    pub const _INITIALIZER_STEP_LIMIT = INITIALIZER_STEP_LIMIT;
    pub const _IdleCallback = IdleCallback;
    pub const _IdleDispatchBlock = IdleDispatchBlock;
    pub const _IdleQueueSnapshot = IdleQueueSnapshot;
    pub const _ImportHandlerResult = ImportHandlerResult;
    pub const _ImportRoute = ImportRoute;
    pub const _ImportRouteCacheEntry = ImportRouteCacheEntry;
    pub const _ImportTraceEntry = ImportTraceEntry;
    pub const _InitializerCheckpoint = InitializerCheckpoint;
    pub const _InitializerRunOutcome = InitializerRunOutcome;
    pub const _InputFingerprint = InputFingerprint;
    pub const _InternalCompatibilityTargets = InternalCompatibilityTargets;
    pub const _MAX_IDLE_CALLBACKS = MAX_IDLE_CALLBACKS;
    pub const _MAX_SUSPENDED_GUEST_THREADS = MAX_SUSPENDED_GUEST_THREADS;
    pub const _MEMORY_TRACE_BUFFER_LEN = MEMORY_TRACE_BUFFER_LEN;
    pub const _MEM_BASE = MEM_BASE;
    pub const _MEM_SIZE = MEM_SIZE;
    pub const _MachORunOptions = MachORunOptions;
    pub const _MachSegment = MachSegment;
    pub const _MainLoopType = MainLoopType;
    pub const _MemInitEntry = MemInitEntry;
    pub const _MemReadCallbacks = MemReadCallbacks;
    pub const _Op = Op;
    pub const _PAGE_EXECUTE = PAGE_EXECUTE;
    pub const _PAGE_READ = PAGE_READ;
    pub const _PAGE_SIZE = PAGE_SIZE;
    pub const _PAGE_WRITE = PAGE_WRITE;
    pub const _PROGRESS_REPORT_INTERVAL = PROGRESS_REPORT_INTERVAL;
    pub const _ProfileAccountFlow = ProfileAccountFlow;
    pub const _ProfileAccountStage = ProfileAccountStage;
    pub const _RFL_AF = RFL_AF;
    pub const _RFL_CF = RFL_CF;
    pub const _RFL_DF = RFL_DF;
    pub const _RFL_OF = RFL_OF;
    pub const _RFL_PF = RFL_PF;
    pub const _RFL_SF = RFL_SF;
    pub const _RFL_ZF = RFL_ZF;
    pub const _RegId = RegId;
    pub const _Regs = Regs;
    pub const _RunIntegrityContext = RunIntegrityContext;
    pub const _RunnableSuspendedSnapshot = RunnableSuspendedSnapshot;
    pub const _SA_NODEFER = SA_NODEFER;
    pub const _SA_RESETHAND = SA_RESETHAND;
    pub const _SA_SIGINFO = SA_SIGINFO;
    pub const _STACK_SIZE = STACK_SIZE;
    pub const _Size = Size;
    pub const _StepTraceEntry = StepTraceEntry;
    pub const _SuspendedGuestThread = SuspendedGuestThread;
    pub const _TOML_CODEPOINTS_OFFSET = TOML_CODEPOINTS_OFFSET;
    pub const _TOML_CODEPOINT_CAPACITY = TOML_CODEPOINT_CAPACITY;
    pub const _TOML_CODEPOINT_COUNT_OFFSET = TOML_CODEPOINT_COUNT_OFFSET;
    pub const _TOML_CODEPOINT_CURRENT_OFFSET = TOML_CODEPOINT_CURRENT_OFFSET;
    pub const _TOML_CODEPOINT_STRIDE = TOML_CODEPOINT_STRIDE;
    pub const _TOML_READER_ISTREAM_OFFSET = TOML_READER_ISTREAM_OFFSET;
    pub const _TOML_UTF8_READER_MIN_SIZE = TOML_UTF8_READER_MIN_SIZE;
    pub const _TRACE_BUFFER_LEN = TRACE_BUFFER_LEN;
    pub const _TRACE_PER_THREAD_LEN = TRACE_PER_THREAD_LEN;
    pub const _TRACE_THREAD_SLOTS = TRACE_THREAD_SLOTS;
    pub const _TomlAsciiBlock = TomlAsciiBlock;
    pub const _TomlCodepointRepair = TomlCodepointRepair;
    pub const _TraceEntry = TraceEntry;
    pub const _UNSUPPORTED_RUNTIME_EXIT_CODE = UNSUPPORTED_RUNTIME_EXIT_CODE;
    pub const _UiHandoffEntry = UiHandoffEntry;
    pub const _VexArithmetic = VexArithmetic;
    pub const _VexBitwise = VexBitwise;
    pub const _VexDecoderAudit = VexDecoderAudit;
    pub const _X87State = X87State;
    pub const _X87Tag = X87Tag;
    pub const _abi_data_materializer = abi_data_materializer;
    pub const _acceptance_gates = acceptance_gates;
    pub const _alignDown = alignDown;
    pub const _alignUp = alignUp;
    pub const _anomaly_ledger = anomaly_ledger;
    pub const _application_controller = application_controller;
    pub const _application_framework = application_framework;
    pub const _applyBindingAddend = applyBindingAddend;
    pub const _asyncTransportSleep = asyncTransportSleep;
    pub const _asyncTransportWrite = asyncTransportWrite;
    pub const _async_log = async_log;
    pub const _atomic_compare_exchange = atomic_compare_exchange;
    pub const _auditVexDecoder = auditVexDecoder;
    pub const _audited_image_bytes = audited_image_bytes;
    pub const _audited_image_preflight_passed = audited_image_preflight_passed;
    pub const _audited_image_volume = audited_image_volume;
    pub const _bitScan = bitScan;
    pub const _bootstrap_poll_join_steps = bootstrap_poll_join_steps;
    pub const _bounded_dispatch_fst = bounded_dispatch_fst;
    pub const _bringup_failure = bringup_failure;
    pub const _builtin = builtin;
    pub const _bytesForSize = bytesForSize;
    pub const _calculateBulkConstructionRange = calculateBulkConstructionRange;
    pub const _claim_reconciliation = claim_reconciliation;
    pub const _classifyGuestAssertion = classifyGuestAssertion;
    pub const _cleo_routing = cleo_routing;
    pub const _compat_handlers = compat_handlers;
    pub const _compat_runtime = compat_runtime;
    pub const _configuredInputFingerprint = configuredInputFingerprint;
    pub const _constants = constants;
    pub const _contract = contract;
    pub const _crash_diag = crash_diag;
    pub const _crc32cAccumulator = crc32cAccumulator;
    pub const _cxx_exception_diagnostics = cxx_exception_diagnostics;
    pub const _deadlock_predictor = deadlock_predictor;
    pub const _decodeInsn = decodeInsn;
    pub const _decodeInsnCompat = decodeInsnCompat;
    pub const _deferred_work = deferred_work;
    pub const _device_tree = device_tree;
    pub const _diagnostic_text_accelerator = diagnostic_text_accelerator;
    pub const _diagnostic_throttle = diagnostic_throttle;
    pub const _diagnostics_execution_profile = diagnostics_execution_profile;
    pub const _dispatch_recovery = dispatch_recovery;
    pub const _durable_journal = durable_journal;
    pub const _dyld = dyld;
    pub const _dynamic_export_registry = dynamic_export_registry;
    pub const _dynamic_library_forwarder = dynamic_library_forwarder;
    pub const _envMemSizeMb = envMemSizeMb;
    pub const _environmentFlag = environmentFlag;
    pub const _environmentFlagEnabled = environmentFlagEnabled;
    pub const _environmentPolicyFlag = environmentPolicyFlag;
    pub const _environmentText = environmentText;
    pub const _environmentUnsigned = environmentUnsigned;
    pub const _event_identity = event_identity;
    pub const _execute_impl = execute_impl;
    pub const _execution_helpers = execution_helpers;
    pub const _execution_history = execution_history;
    pub const _execution_provenance = execution_provenance;
    pub const _execution_tracepoints = execution_tracepoints;
    pub const _exit_diagnostics = exit_diagnostics;
    pub const _export_table_lifecycle = export_table_lifecycle;
    pub const _export_table_manager = export_table_manager;
    pub const _extractX8664Slice = extractX8664Slice;
    pub const _fat = fat;
    pub const _fatalConditionContext = fatalConditionContext;
    pub const _fatal_conditions = fatal_conditions;
    pub const _fatal_context_state = fatal_context_state;
    pub const _fault_pause_transaction = fault_pause_transaction;
    pub const _fcntl_c = fcntl_c;
    pub const _foreign_object_runtime = foreign_object_runtime;
    pub const _fs_io_forwarder = fs_io_forwarder;
    pub const _generated_endian_contract = generated_endian_contract;
    pub const _gpu = gpu;
    pub const _graphicsPathStageLabel = graphicsPathStageLabel;
    pub const _graphicsTracepointFacts = graphicsTracepointFacts;
    pub const _graphics_health_contract = graphics_health_contract;
    pub const _guard_rollback_lib = guard_rollback_lib;
    pub const _guestSignalIndex = guestSignalIndex;
    pub const _guest_address_space = guest_address_space;
    pub const _guest_alias_contract = guest_alias_contract;
    pub const _guest_assertion_recovery = guest_assertion_recovery;
    pub const _guest_critical_section = guest_critical_section;
    pub const _guest_exception_ledger = guest_exception_ledger;
    pub const _guest_fs = guest_fs;
    pub const _guest_log = guest_log;
    pub const _guest_log_channels = guest_log_channels;
    pub const _guest_memory_geometry = guest_memory_geometry;
    pub const _guest_module_map = guest_module_map;
    pub const _guest_status_ledger = guest_status_ledger;
    pub const _guest_structure = guest_structure;
    pub const _guest_wait_liveness = guest_wait_liveness;
    pub const _hasPathSuffixIgnoreCase = hasPathSuffixIgnoreCase;
    pub const _hasRelativeControlDisplacement = hasRelativeControlDisplacement;
    pub const _hashInputPath = hashInputPath;
    pub const _hashInputReference = hashInputReference;
    pub const _hostGraphicsAdmissionStages = hostGraphicsAdmissionStages;
    pub const _hostIdentityDescriptor = hostIdentityDescriptor;
    pub const _hostPresenterFailureIndex = hostPresenterFailureIndex;
    pub const _host_contract_coverage = host_contract_coverage;
    pub const _host_termination = host_termination;
    pub const _idleQueueSnapshotFor = idleQueueSnapshotFor;
    pub const _importRouteCacheIndex = importRouteCacheIndex;
    pub const _import_binding_predictor = import_binding_predictor;
    pub const _import_dispatch = import_dispatch;
    pub const _import_handler = import_handler;
    pub const _import_integrity = import_integrity;
    pub const _import_resolution = import_resolution;
    pub const _initialization_resolution = initialization_resolution;
    pub const _initializer_dependency = initializer_dependency;
    pub const _initializers = initializers;
    pub const _interrupt_callback_transaction = interrupt_callback_transaction;
    pub const _isApplicationControlFlow = isApplicationControlFlow;
    pub const _isAsciiBytes = isAsciiBytes;
    pub const _isGtkEventsPendingImport = isGtkEventsPendingImport;
    pub const _isGtkIdleAddImport = isGtkIdleAddImport;
    pub const _isGtkMainIterationImport = isGtkMainIterationImport;
    pub const _isPatchDbNullIsArraySequence = isPatchDbNullIsArraySequence;
    pub const _itanium_dynamic_cast = itanium_dynamic_cast;
    pub const _itanium_unwinder = itanium_unwinder;
    pub const _jit = jit;
    pub const _kernel_service_readiness = kernel_service_readiness;
    pub const _launchMediaPath = launchMediaPath;
    pub const _launchOptionValue = launchOptionValue;
    pub const _launch_argument_accelerator = launch_argument_accelerator;
    pub const _lazy_import_stub = lazy_import_stub;
    pub const _libcpp_filesystem = libcpp_filesystem;
    pub const _libcpp_shared_control_block = libcpp_shared_control_block;
    pub const _libcpp_stream_bridge = libcpp_stream_bridge;
    pub const _livelock_predictor = livelock_predictor;
    pub const _loadAndRun = loadAndRun;
    pub const _log = log;
    pub const _logGraphicsHostPreflightSnapshot = logGraphicsHostPreflightSnapshot;
    pub const _logGraphicsPathPreflight = logGraphicsPathPreflight;
    pub const _log_repetition = log_repetition;
    pub const _logging_runtime = logging_runtime;
    pub const _macho = macho;
    pub const _machoCapturePrint = machoCapturePrint;
    pub const _macho_core = macho_core;
    pub const _macho_log = macho_log;
    pub const _macho_metadata = macho_metadata;
    pub const _macho_runtime = macho_runtime;
    pub const _macos_host_contract = macos_host_contract;
    pub const _main = main;
    pub const _mandatory_order = mandatory_order;
    pub const _mappedOffset = mappedOffset;
    pub const _markHostAdmissionFailure = markHostAdmissionFailure;
    pub const _markHostPresenterFacts = markHostPresenterFacts;
    pub const _memReadMemVal = memReadMemVal;
    pub const _memory_access = memory_access;
    pub const _memory_management_forwarder = memory_management_forwarder;
    pub const _memory_mod = memory_mod;
    pub const _memory_provenance = memory_provenance;
    pub const _memory_transaction = memory_transaction;
    pub const _memory_write_provenance = memory_write_provenance;
    pub const _monotone_witness = monotone_witness;
    pub const _native_crash = native_crash;
    pub const _native_window = native_window;
    pub const _native_window_runtime = native_window_runtime;
    pub const _near_null_predictor = near_null_predictor;
    pub const _nextPrime = nextPrime;
    pub const _notifier_liveness = notifier_liveness;
    pub const _opaque_lifetime_recovery = opaque_lifetime_recovery;
    pub const _ownership_contract = ownership_contract;
    pub const _ownership_lib = ownership_lib;
    pub const _packed_ops = packed_ops;
    pub const _pipeline_evidence = pipeline_evidence;
    pub const _pointer_firewall = pointer_firewall;
    pub const _populationCount = populationCount;
    pub const _preflightDecodeInstruction = preflightDecodeInstruction;
    pub const _preflightUnsigned = preflightUnsigned;
    pub const _preflight_lib = preflight_lib;
    pub const _primitive = primitive;
    pub const _primitiveCapturePrint = primitiveCapturePrint;
    pub const _proc_diag = proc_diag;
    pub const _profileIdFromUserDevice = profileIdFromUserDevice;
    pub const _pthread_runtime = pthread_runtime;
    pub const _readDarwinMcontext = readDarwinMcontext;
    pub const _readDarwinSigaction = readDarwinSigaction;
    pub const _readExtendedFloat80 = readExtendedFloat80;
    pub const _ready_compiler = ready_compiler;
    pub const _recovery_ledger = recovery_ledger;
    pub const _register_map = register_map;
    pub const _repairAsciiCodepointBlock = repairAsciiCodepointBlock;
    pub const _reportDecodeCoverage = reportDecodeCoverage;
    pub const _reportGraphicsPreflight = reportGraphicsPreflight;
    pub const _reportInputHashDiagnosis = reportInputHashDiagnosis;
    pub const _reportInputHashFailure = reportInputHashFailure;
    pub const _reportInputHashProgress = reportInputHashProgress;
    pub const _reportInputHashRetry = reportInputHashRetry;
    pub const _reportInputSurveyStart = reportInputSurveyStart;
    pub const _reportInteropAudit = reportInteropAudit;
    pub const _reportMediaPreflight = reportMediaPreflight;
    pub const _reportPrelaunchAudit = reportPrelaunchAudit;
    pub const _resolveGuestSignalReturn = resolveGuestSignalReturn;
    pub const _rosette_pkg_log = rosette_pkg_log;
    pub const _runGraphicsPathPreflight = runGraphicsPathPreflight;
    pub const _run_budget = run_budget;
    pub const _run_closure = run_closure;
    pub const _run_horizon = run_horizon;
    pub const _run_integrity = run_integrity;
    pub const _run_journal = run_journal;
    pub const _run_manifest = run_manifest;
    pub const _runtimeValue = runtimeValue;
    pub const _runtime_output = runtime_output;
    pub const _scheduler = scheduler;
    pub const _scheduling = scheduling;
    pub const _sdl_runtime = sdl_runtime;
    pub const _seedGraphicsPathFacts = seedGraphicsPathFacts;
    pub const _selectedCpuProfile = selectedCpuProfile;
    pub const _semantic_fault_classifier = semantic_fault_classifier;
    pub const _setenv = setenv;
    pub const _signalFailureResult = signalFailureResult;
    pub const _signalHandlerMadeProgress = signalHandlerMadeProgress;
    pub const _signal_expectation = signal_expectation;
    pub const _signal_handling = signal_handling;
    pub const _smart_stub_generator = smart_stub_generator;
    pub const _sparse_virtual_memory = sparse_virtual_memory;
    pub const _specialRipTableContains = specialRipTableContains;
    pub const _spirv_cross_diagnostics = spirv_cross_diagnostics;
    pub const _stall_release = stall_release;
    pub const _startAsyncDiagnosticTransport = startAsyncDiagnosticTransport;
    pub const _startup_observer = startup_observer;
    pub const _std = std;
    pub const _stepBudgetAllows = stepBudgetAllows;
    pub const _stopAsyncDiagnosticTransport = stopAsyncDiagnosticTransport;
    pub const _storage_integrity = storage_integrity;
    pub const _substantiation = substantiation;
    pub const _swap_health = swap_health;
    pub const _symbol_assembly_context = symbol_assembly_context;
    pub const _sync_object_identity = sync_object_identity;
    pub const _sync_object_registry = sync_object_registry;
    pub const _syscalls = syscalls;
    pub const _thread_wait_profiler = thread_wait_profiler;
    pub const _threeOperandImulResult = threeOperandImulResult;
    pub const _thunk_handler = thunk_handler;
    pub const _timeout_fidelity = timeout_fidelity;
    pub const _timerQueueStateName = timerQueueStateName;
    pub const _tlv_runtime = tlv_runtime;
    pub const _translation_cache = translation_cache;
    pub const _translation_domain = translation_domain;
    pub const _translation_economics = translation_economics;
    pub const _types = types;
    pub const _unknown_inventory_mod = unknown_inventory_mod;
    pub const _utils = utils;
    pub const _vt = vt;
    pub const _vtable_clobber_predictor = vtable_clobber_predictor;
    pub const _vtt_resolution = vtt_resolution;
    pub const _wait_audit = wait_audit;
    pub const _wait_graph = wait_graph;
    pub const _writeDarwinMcontext = writeDarwinMcontext;
    pub const _writeDarwinSigaction = writeDarwinSigaction;
    pub const _writeDarwinSiginfo = writeDarwinSiginfo;
    pub const _writeDarwinUcontext = writeDarwinUcontext;
    pub const _writeExtendedFloat80 = writeExtendedFloat80;
    pub const _x64_backend_diagnostics = x64_backend_diagnostics;
    pub const _x64_decoder = x64_decoder;
    pub const _x64_interpreter = x64_interpreter;
    pub const _xenia_gpu_causal_trace = xenia_gpu_causal_trace;
    pub const _xenia_gpu_handoff = xenia_gpu_handoff;
    pub const _xenia_memory_views = xenia_memory_views;
    pub const _xenia_pipeline = xenia_pipeline;
    pub const _xenia_pm4_walk = xenia_pm4_walk;
    pub const _xiso_format = xiso_format;
    pub const _xiso_preflight = xiso_preflight;
    pub const _BankOccupancy = MachOState.BankOccupancy;
    pub const _DecodeCacheSelection = MachOState.DecodeCacheSelection;
    pub const _PresentationFacts = MachOState.PresentationFacts;
    pub const _PrimaryDecodeCacheSelection = MachOState.PrimaryDecodeCacheSelection;
    pub const _ReadyPlanContext = MachOState.ReadyPlanContext;
    pub const _Sha1Tracer = MachOState.Sha1Tracer;
    pub const _addrToOffset = MachOState.addrToOffset;
    pub const _captureMemoryMutation = MachOState.captureMemoryMutation;
    pub const _classifyWriterRipOffset = MachOState.classifyWriterRipOffset;
    pub const _commitMemoryMutation = MachOState.commitMemoryMutation;
    pub const _currentGuestInstructionLength = MachOState.currentGuestInstructionLength;
    pub const _cxxExceptionMessage = MachOState.cxxExceptionMessage;
    pub const _cxxExceptionTypeName = MachOState.cxxExceptionTypeName;
    pub const _decodeWithSnapshotOperands = MachOState.decodeWithSnapshotOperands;
    pub const _deferInitializerRuntimeDependency = MachOState.deferInitializerRuntimeDependency;
    pub const _describeGuestAccess = MachOState.describeGuestAccess;
    pub const _detectFunctionProloguePtr = MachOState.detectFunctionProloguePtr;
    pub const _diagnosticSymbol = MachOState.diagnosticSymbol;
    pub const _dumpHeapCorruptionDiagnostics = MachOState.dumpHeapCorruptionDiagnostics;
    pub const _dumpNearNullProducerSlot = MachOState.dumpNearNullProducerSlot;
    pub const _dumpRegisterTransition = MachOState.dumpRegisterTransition;
    pub const _dumpStepTraceBuffer = MachOState.dumpStepTraceBuffer;
    pub const _dumpTerminalAddressProvenance = MachOState.dumpTerminalAddressProvenance;
    pub const _effect_settle_steps = MachOState.effect_settle_steps;
    pub const _ensureGuestAccess = MachOState.ensureGuestAccess;
    pub const _fillGuestMemory = MachOState.fillGuestMemory;
    pub const _forgetMemoryWriteProvenance = MachOState.forgetMemoryWriteProvenance;
    pub const _guestAlloc = MachOState.guestAlloc;
    pub const _guestCString = MachOState.guestCString;
    pub const _guestHeapAllocate = MachOState.guestHeapAllocate;
    pub const _guestHeapContains = MachOState.guestHeapContains;
    pub const _guestHeapRelease = MachOState.guestHeapRelease;
    pub const _guestMapAnywhereWithBacking = MachOState.guestMapAnywhereWithBacking;
    pub const _guestMapBackendWithBacking = MachOState.guestMapBackendWithBacking;
    pub const _guestMapFile = MachOState.guestMapFile;
    pub const _guestMapHinted = MachOState.guestMapHinted;
    pub const _guestMemory = MachOState.guestMemory;
    pub const _guestMemoryConst = MachOState.guestMemoryConst;
    pub const _guestProtectMappedMemory = MachOState.guestProtectMappedMemory;
    pub const _guestProtectSparseMemory = MachOState.guestProtectSparseMemory;
    pub const _guestReserveAddressSpace = MachOState.guestReserveAddressSpace;
    pub const _guestReserveAddressSpaceWithBacking = MachOState.guestReserveAddressSpaceWithBacking;
    pub const _guestUnmapFile = MachOState.guestUnmapFile;
    pub const _guestWriteCString = MachOState.guestWriteCString;
    pub const _hasLiveAllocationVtableHistory = MachOState.hasLiveAllocationVtableHistory;
    pub const _isAddressInMappedMemory = MachOState.isAddressInMappedMemory;
    pub const _isExecutableAddress = MachOState.isExecutableAddress;
    pub const _logLiveVtableGuardSummary = MachOState.logLiveVtableGuardSummary;
    pub const _max_reference_targets = MachOState.max_reference_targets;
    pub const _ms = MachOState.ms;
    pub const _noteGuestWrite = MachOState.noteGuestWrite;
    pub const _pop = MachOState.pop;
    pub const _push = MachOState.push;
    pub const _read16 = MachOState.read16;
    pub const _read32 = MachOState.read32;
    pub const _read64 = MachOState.read64;
    pub const _read8 = MachOState.read8;
    pub const _readMem128 = MachOState.readMem128;
    pub const _readMemVal = MachOState.readMemVal;
    pub const _recordAllocationWrite = MachOState.recordAllocationWrite;
    pub const _recordEndianEvidence = MachOState.recordEndianEvidence;
    pub const _recordMemoryAccess = MachOState.recordMemoryAccess;
    pub const _recoverLiveAllocationVtable = MachOState.recoverLiveAllocationVtable;
    pub const _registerOpaqueApiHandle = MachOState.registerOpaqueApiHandle;
    pub const _registerOpaqueHandle = MachOState.registerOpaqueHandle;
    pub const _registerSyntheticRegion = MachOState.registerSyntheticRegion;
    pub const _registerSyntheticThunk = MachOState.registerSyntheticThunk;
    pub const _renderProcSelfMaps = MachOState.renderProcSelfMaps;
    pub const _setPagePermissions = MachOState.setPagePermissions;
    pub const _terminateForGuestAccess = MachOState.terminateForGuestAccess;
    pub const _timerQueueWatchWrite = MachOState.timerQueueWatchWrite;
    pub const _traceRegisterValue = MachOState.traceRegisterValue;
    pub const _translateGuest = MachOState.translateGuest;
    pub const _tryQuarantineOpaqueDestructor = MachOState.tryQuarantineOpaqueDestructor;
    pub const _tryRepairGeneratedEndianBeforeDispatch = MachOState.tryRepairGeneratedEndianBeforeDispatch;
    pub const _vtableIdentityEvidence = MachOState.vtableIdentityEvidence;
    pub const _write16 = MachOState.write16;
    pub const _write32 = MachOState.write32;
    pub const _write64 = MachOState.write64;
    pub const _write8 = MachOState.write8;
    pub const _writeGuestBytes = MachOState.writeGuestBytes;
    pub const _writeMem128 = MachOState.writeMem128;
    pub const _writeMemVal = MachOState.writeMemVal;
};

const macho_process_lifecycle_bindings = @import("process/lifecycle_bindings.zig");
const macho_process_window_bootstrap = @import("process/window_bootstrap.zig");
const macho_process_readiness = @import("process/readiness.zig");
const macho_process_graphics_health = @import("process/graphics_health.zig");
const macho_process_audit_waits = @import("process/audit_waits.zig");
const macho_process_gpu_execution = @import("process/gpu_execution.zig");
const macho_process_graphics_evidence = @import("process/graphics_evidence.zig");
const macho_process_graphics_admission = @import("process/graphics_admission.zig");
const macho_process_execution_core = @import("process/execution_core.zig");
const macho_process_run_loop = @import("process/run_loop.zig");

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

/// Start the asynchronous diagnostic transport when this run selected it.
///
/// Reported either way: a run whose logging model changed must say so in its
/// own log, or two runs become incomparable for a reason nothing records.
fn startAsyncDiagnosticTransport(
    allocator: std.mem.Allocator,
    output: *runtime_output.Controller,
) bool {
    if (!environmentFlagEnabled("ROSETTE_ASYNC_LOG")) return false;
    const fd = output.detailFd();
    if (fd < 0) {
        machoCapturePrint(
            "macho-processor: ASYNC LOG: refused — no runtime-log descriptor is open, so a ring would have nowhere to drain and would drop every line after the first {d}. Staying synchronous\n",
            .{async_log.slot_count},
        );
        return false;
    }
    // When the controller redirected stderr into the runtime log, mirroring
    // would write every line twice into the same file.
    const mirror = !output.capturedStderr();
    if (!async_log.startTransport(allocator, fd, mirror, asyncTransportWrite, asyncTransportSleep)) {
        machoCapturePrint(
            "macho-processor: ASYNC LOG: refused — the writer thread could not start. A ring with no writer fills once and drops forever, which is worse than the synchronous path it would replace. Staying synchronous\n",
            .{},
        );
        return false;
    }
    macho_log.installAsyncTransport(
        async_log.offerLine,
        async_log.flushTransport,
        async_log.lineIsCritical,
    );
    machoCapturePrint(
        "macho-processor: ASYNC LOG: enabled slots={d} slot_bytes={d} ring_bytes={d} mirror_stderr={s}; diagnostic writes now happen on a writer thread. Producers never block: a full ring drops and counts rather than pausing the translated guest, so the log may have counted gaps and the program's timing stays its own\n",
        .{
            async_log.slot_count,
            async_log.slot_bytes,
            async_log.slot_count * async_log.slot_bytes,
            if (mirror) "YES" else "NO",
        },
    );
    return true;
}

fn stopAsyncDiagnosticTransport() void {
    const totals = async_log.transportStats();
    machoCapturePrint(
        "macho-processor: ASYNC LOG: integrity={s} accepted={d} dropped={d} truncated={d} written={d} queued={d} write_calls={d} batch_factor={d} bytes={d} synchronous_criticals={d}; {s}\n",
        .{
            totals.integrity().label(),
            totals.accepted,
            totals.dropped,
            totals.truncated,
            totals.written,
            totals.queued,
            totals.write_calls,
            totals.batchFactor(),
            totals.bytes_written,
            totals.synchronous_criticals,
            totals.integrity().guidance(),
        },
    );
    macho_log.clearAsyncTransport();
    async_log.stopTransport();
}

fn asyncTransportWrite(fd: i32, bytes: []const u8) void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const written = std.c.write(fd, bytes.ptr + offset, bytes.len - offset);
        if (written <= 0) return;
        offset += @intCast(written);
    }
}

fn asyncTransportSleep(nanoseconds: u64) void {
    var request = std.c.timespec{
        .sec = @intCast(nanoseconds / std.time.ns_per_s),
        .nsec = @intCast(nanoseconds % std.time.ns_per_s),
    };
    var remaining: std.c.timespec = undefined;
    _ = std.c.nanosleep(&request, &remaining);
}

fn environmentFlagEnabled(name: [*:0]const u8) bool {
    const raw = std.c.getenv(name) orelse return false;
    const value = std.mem.span(raw);
    if (value.len == 0) return false;
    return !std.mem.eql(u8, value, "0") and
        !std.mem.eql(u8, value, "false") and
        !std.mem.eql(u8, value, "no");
}

/// Reads a policy flag whose absence has an explicit default, while treating
/// every unrecognised value as disabled.  The latter is intentional for host
/// mutation controls: a typo must not silently turn a capability on.
fn environmentPolicyFlag(name: [*:0]const u8, default_value: bool) bool {
    const raw = std.c.getenv(name) orelse return default_value;
    const value = std.mem.span(raw);
    if (value.len == 0) return false;

    if (std.mem.eql(u8, value, "1") or
        std.mem.eql(u8, value, "true") or
        std.mem.eql(u8, value, "yes") or
        std.mem.eql(u8, value, "on") or
        std.mem.eql(u8, value, "allow"))
    {
        return true;
    }
    if (std.mem.eql(u8, value, "0") or
        std.mem.eql(u8, value, "false") or
        std.mem.eql(u8, value, "no") or
        std.mem.eql(u8, value, "off") or
        std.mem.eql(u8, value, "deny") or
        std.mem.eql(u8, value, "disabled"))
    {
        return false;
    }
    return false;
}

const InputFingerprint = struct {
    hash: u64 = 0,
    source: []const u8 = "missing",
};

fn environmentText(name: [*:0]const u8) ?[]const u8 {
    const raw = std.c.getenv(name) orelse return null;
    const value = std.mem.trim(u8, std.mem.span(raw), " \t\r\n");
    return if (value.len == 0) null else value;
}

fn launchOptionValue(args: []const []const u8, name: []const u8) ?[]const u8 {
    for (args, 0..) |arg, index| {
        if (std.mem.eql(u8, arg, name)) {
            return if (index + 1 < args.len) args[index + 1] else null;
        }
        if (arg.len > name.len and std.mem.startsWith(u8, arg, name) and arg[name.len] == '=') {
            return arg[name.len + 1 ..];
        }
    }
    return null;
}

fn hasPathSuffixIgnoreCase(path: []const u8, suffix: []const u8) bool {
    return path.len >= suffix.len and
        std.ascii.eqlIgnoreCase(path[path.len - suffix.len ..], suffix);
}

fn launchMediaPath(args: []const []const u8) ?[]const u8 {
    // Xenia accepts both an XISO and a loose XEX.  Keep this deliberately
    // suffix-based: --config and --storage_root are also paths, but they are
    // separate identity inputs and must not be treated as title media.
    for (args) |arg| {
        if (arg.len == 0 or arg[0] == '-') continue;
        if (hasPathSuffixIgnoreCase(arg, ".iso") or
            hasPathSuffixIgnoreCase(arg, ".xiso") or
            hasPathSuffixIgnoreCase(arg, ".xex")) return arg;
    }
    return null;
}

fn reportInputHashProgress(bytes_read: u64, total_bytes: ?u64) void {
    if (total_bytes) |total| {
        const percent = if (total == 0) 100 else @divTrunc(bytes_read * 100, total);
        machoCapturePrint(
            "macho-processor: AUDIT INPUTS: hashing progress bytes={d}/{d} ({d}%)\n",
            .{ bytes_read, total, percent },
        );
    } else {
        machoCapturePrint(
            "macho-processor: AUDIT INPUTS: hashing progress bytes={d} (total unavailable)\n",
            .{bytes_read},
        );
    }
}

fn reportInputHashRetry(
    offset: u64,
    recovery_event: u32,
    chunk_bytes: usize,
    error_name: []const u8,
    wait_ns: u64,
) void {
    machoCapturePrint(
        "macho-processor: AUDIT INPUTS: read retry offset={d} recovery_event={d} request_bytes={d} error={s} device_wait_ms={d}; reopening input at the exact digest offset\n",
        .{ offset, recovery_event, chunk_bytes, error_name, @divTrunc(wait_ns, std.time.ns_per_ms) },
    );
}

fn reportInputHashFailure(
    offset: u64,
    total_bytes: ?u64,
    recovery_events: u32,
    chunk_bytes: usize,
    error_name: []const u8,
    wait_ns: u64,
) void {
    const wait_ms = @divTrunc(wait_ns, std.time.ns_per_ms);
    if (total_bytes) |total| {
        machoCapturePrint(
            "macho-processor: AUDIT INPUTS: read failure offset={d}/{d} recovery_events={d} request_bytes={d} reason={s} device_wait_ms={d}; complete content identity was not established\n",
            .{ offset, total, recovery_events, chunk_bytes, error_name, wait_ms },
        );
    } else {
        machoCapturePrint(
            "macho-processor: AUDIT INPUTS: read failure offset={d} recovery_events={d} request_bytes={d} reason={s} device_wait_ms={d}; complete content identity was not established\n",
            .{ offset, recovery_events, chunk_bytes, error_name, wait_ms },
        );
    }
}

/// Announce the damage survey before it goes quiet.
///
/// The survey makes no output while it runs and every probe that refuses costs
/// the device's whole retry budget, so a launcher watching this log for
/// liveness sees a silence it cannot tell from a wedged process. Declaring the
/// budget lets the watchdog wait exactly as long as the runtime said, rather
/// than guessing a constant that is too tight to survive one device retry.
fn reportInputSurveyStart(offset: u64, budget_ns: u64) void {
    machoCapturePrint(
        "macho-processor: AUDIT INPUTS: damage survey starting offset={d} budget_ms={d}; probing for the extent of the unreadable region. This log is silent while it runs, by design\n",
        .{ offset, @divTrunc(budget_ns, std.time.ns_per_ms) },
    );
}

/// The failure line says the digest stopped. This says what stopped it.
///
/// A launch input that will not hash leaves the operator with two very
/// different jobs — repackage the image, or stop trusting the volume — and the
/// error name alone does not choose between them. These lines carry the
/// evidence that does: how long the device took to refuse, whether the file
/// holds every byte it claims, and how far the unreadable region runs.
/// Do the subsystems reach each other, and can the guest ask us what it needs?
///
/// Runs after the run identity is sealed and before the first guest
/// instruction. It has to be after the seal: the guest asks for the identity by
/// name, and whether Rosette can answer is not decidable until there is an
/// identity to answer with.
fn reportInteropAudit(allocator: std.mem.Allocator, state: *const MachOState) bool {
    const audit = preflight_lib.interop_audit;
    // Answer through the guest's own lookup rather than a stand-in for it.
    const Resolver = struct {
        state: *const MachOState,
        fn answer(context: ?*anyopaque, name: []const u8) bool {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            return import_dispatch.guestCanAnswerEnvironmentName(self.state, name);
        }
    };
    var resolver = Resolver{ .state = state };
    const findings = audit.auditImage(allocator, &state.metadata, .{
        .identity_sealed = state.audit_manifest.sealIntact(),
        .context = @ptrCast(&resolver),
        .answer = Resolver.answer,
    }) catch {
        machoCapturePrint(
            "macho-processor: INTEROP AUDIT: UNEVALUATED; the image could not be walked, so nothing was established about how its subsystems reach each other\n",
            .{},
        );
        // An unevaluated graph is not a pass.  The old return value allowed a
        // failed allocator walk to continue into guest setup, where the same
        // missing edge would surface as a late graphics or environment error.
        return false;
    };

    machoCapturePrint(
        "macho-processor: INTEROP AUDIT: symbols={d} text_bytes={d} direct_edges={d} lost_links={d} names={d} elapsed_ms={d}; direct calls only — indirect dispatch through the kernel ordinal table and through vtables leaves no call edge, so an absent link is not a finding and only a lost one is\n",
        .{
            findings.symbols,
            findings.text_bytes,
            findings.direct_edges,
            findings.lost_links,
            findings.environment_count,
            @divTrunc(findings.elapsed_ns, std.time.ns_per_ms),
        },
    );

    // Only the links that are gone. Seven "present" lines on every healthy run
    // are seven lines that never change; the summary above already carries
    // lost_links, and the detail is what a reader needs only when it is not
    // zero.
    for (preflight_lib.interop_audit.contract_links) |link| {
        if (findings.edgeCount(link.from, link.to) != 0) continue;
        machoCapturePrint(
            "  link LOST {s} -> {s}; {s}\n",
            .{ link.from.label(), link.to.label(), link.why },
        );
    }

    // Only the names the run cannot answer. A guest reading fifteen variables
    // successfully is not news; one it needs and cannot get is the whole
    // finding.
    for (findings.names()) |use| {
        if (use.answerable) continue;
        machoCapturePrint(
            "  guest reads {s} sites={d} required={s} answerable=NO{s}\n",
            .{
                use.name,
                use.sites,
                if (use.required) "YES" else "NO",
                if (use.required) "; the guest cannot start without this" else "; the guest is expected to cope with this being unset",
            },
        );
    }
    if (findings.environment_overflow) {
        machoCapturePrint(
            "  guest reads MORE names than there was room to record; the list above is a prefix, not the surface\n",
            .{},
        );
    }

    if (findings.blocksLaunch()) {
        machoCapturePrint(
            "macho-processor: INTEROP AUDIT: BLOCKED name={s}; the guest reads this to bind its run to ours and Rosette cannot answer it. To the guest an unanswerable name is an unset one, and it refuses its own start over it — which is this failure, moved forward to where the cause is\n",
            .{findings.first_unanswerable},
        );
        return false;
    }
    if (findings.lost_links != 0) {
        const lost = findings.first_lost.?;
        machoCapturePrint(
            "macho-processor: INTEROP AUDIT: LINK LOST {s} -> {s}; a build that reached graphics had direct calls here and this one has none. That is worth reading before a run, but it does not refuse one: the graph cannot see indirect dispatch, so the call may have moved rather than gone\n",
            .{ lost.from.label(), lost.to.label() },
        );
        return true;
    }
    machoCapturePrint(
        "macho-processor: INTEROP AUDIT: PASS; every link a working build had is still here and every name the guest asks for can be answered\n",
        .{},
    );
    return true;
}

/// The state a fatal-condition report reads its machine context from.
///
/// A file-scope pointer because the condition is matched inside the logging
/// funnel, which has no argument to carry one.
var fatal_context_state: ?*const MachOState = null;

fn fatalConditionContext() fatal_conditions.FaultContext {
    const state = fatal_context_state orelse return .{};
    const rip = state.regs.rip;
    var context = fatal_conditions.FaultContext{
        .valid = true,
        .step = state.executed_steps,
        .rip = rip,
        .thread = state.active_guest_thread,
        .address_kind = state.metadata.addressKind(rip).label(),
    };
    if (state.metadata.sectionAtAddress(rip)) |section| context.section = section.name;
    if (state.metadata.nearestSymbol(rip)) |match| {
        context.symbol = match.name;
        context.symbol_offset = match.offset;
    }
    return context;
}

/// Read the emulator image's subsystem surface before anything else.
///
/// Returns false when the build cannot reach a frame at all. This runs ahead of
/// the media hash on purpose: refusing a build that never linked its command
/// processor should not cost six gigabytes of reads first.
/// What fraction of the x86-64 opcode space this decoder accepts.
///
/// Rosette translates x86-64, and "does it handle all of x86-64?" used to have
/// no answer: the evidence was anecdotal, one guest-reached encoding at a
/// time, with the distance between them invisible. This asks the production
/// decoder about every slot of every opcode map before the first guest
/// instruction, so the claim is a number with its gaps named.
///
/// The three excluded classes are excluded because a decoder that accepted
/// them would be wrong: encodings x86-64 removed, ring-0 instructions a
/// user-mode guest cannot execute, and the prefixes and map escapes that are
/// not instructions at all. Scoring those as gaps would send a reader to
/// implement instructions that must not exist.
fn reportDecodeCoverage(state: *MachOState) void {
    _ = state;
    const result = x64_decoder.coverage.census();
    const weakest = result.weakest();
    machoCapturePrint(
        "macho-processor: DECODE COVERAGE: {d}% decoded={d} refused={d} of {d} scorable slot(s); excluded(not-an-opcode/not-in-long-mode/privileged)={d}/{d}/{d}; weakest map is {s} at {d}%. A refused slot is a lead rather than a verdict — the census probes each opcode with a synthesized encoding, so it can understate coverage and never overstate it\n",
        .{
            result.percent(),
            result.decoded(),
            result.refused(),
            result.scored(),
            blk: {
                var total: u32 = 0;
                for (result.maps) |entry| total += entry.not_an_opcode;
                break :blk total;
            },
            blk: {
                var total: u32 = 0;
                for (result.maps) |entry| total += entry.not_in_long_mode;
                break :blk total;
            },
            blk: {
                var total: u32 = 0;
                for (result.maps) |entry| total += entry.privileged;
                break :blk total;
            },
            weakest.map.label(),
            weakest.percent(),
        },
    );
    for (result.maps) |entry| {
        machoCapturePrint(
            "  decode map {s: <12} {d: >3}% decoded={d: >3} refused={d: >3} first_refused=0x{x:0>2}\n",
            .{
                entry.map.label(),
                entry.percent(),
                entry.decoded,
                entry.refused,
                entry.first_refused orelse 0,
            },
        );
    }
}

fn reportPrelaunchAudit(state: *MachOState) bool {
    reportDecodeCoverage(state);
    const audit = preflight_lib.prelaunch_audit;
    const summary = audit.auditImage(&state.metadata);
    state.prelaunch_audit_summary = summary;

    machoCapturePrint(
        "macho-processor: PRELAUNCH AUDIT: verdict={s} symbols={d} import_stubs={d} elapsed_ms={d}; the image's subsystem surface is read before the first guest instruction, so a build that could never reach a frame is answered here rather than after minutes of emulated boot\n",
        .{
            summary.verdict.label(),
            summary.symbols_walked,
            summary.import_stubs,
            @divTrunc(summary.elapsed_ns, std.time.ns_per_ms),
        },
    );

    for (audit.contract_stages) |stage| {
        const facts = summary.classified(stage);
        machoCapturePrint(
            "  stage {s} symbols={d} fingerprint=0x{x} range=0x{x}..0x{x} blocking={s}\n",
            .{
                stage.label(),
                facts.symbols,
                facts.fingerprint,
                facts.lowest_address,
                facts.highest_address,
                if (stage.blocksLaunch()) "YES" else "NO",
            },
        );
        // Names are printed only where they are evidence.
        //
        // Every stage listing four examples was forty lines that said the same
        // thing on every healthy run: the build is fine. The names are only
        // worth reading when a stage is actually holding the run back, so a
        // blocking stage that carries no code names itself and everything else
        // stays quiet.
        if (stage.blocksLaunch() and facts.isEmpty()) {
            machoCapturePrint(
                "    contains blocking: nothing at all; this stage is required for a frame and has no code, which is the link failure\n",
                .{},
            );
        }
    }

    switch (summary.verdict) {
        .ready => machoCapturePrint(
            "macho-processor: PRELAUNCH AUDIT: PASS; every subsystem a frame depends on carries code. This says they linked, not that they work — presence is the only thing a symbol table can prove\n",
            .{},
        ),
        .unevaluated => machoCapturePrint(
            "macho-processor: PRELAUNCH AUDIT: UNEVALUATED; no classified symbol was read from the image, so nothing was established about this build. That is a statement about the reader, not an accusation against the build\n",
            .{},
        ),
        .blocked => {
            const gap = summary.blocking_gap orelse .unclassified;
            machoCapturePrint(
                "macho-processor: PRELAUNCH AUDIT: BLOCKED stage={s}; the image contains no code for a subsystem a frame cannot be produced without. Running longer cannot reach it and no guest behaviour explains it — this is a link failure in the emulator build\n",
                .{gap.label()},
            );
        },
    }
    // An unevaluated census is not a pass.  The legacy report used to allow it
    // through because it could not distinguish an empty image from an absent
    // reader; the graphics preflight now consumes the same summary and keeps
    // the distinction explicit.  Refusing here saves the media hash and gives
    // the caller the earliest actionable failure.
    return summary.verdict == .ready;
}

/// Decode one image entry without executing it.  The full image scan is a
/// bounded startup operation; its result is a coverage signal, while the
/// normal interpreter remains the authority for guest execution.
fn preflightDecodeInstruction(bytes: []const u8) preflight_lib.graphics_readiness.DecodeResult {
    const decoded = x64_decoder.decodeLegacyInstruction(bytes, .long64);
    return .{
        .valid = decoded.len != 0 and decoded.op != .invalid,
        .length = @intCast(@min(decoded.len, std.math.maxInt(u8))),
    };
}

fn graphicsTracepointFacts(state: *const MachOState) preflight_lib.graphics_readiness.TracepointFacts {
    var facts = preflight_lib.graphics_readiness.TracepointFacts{
        .sealed = state.execution_tracepoints.sealed,
        .armed_total = @intCast(state.execution_tracepoints.count),
        .unresolved = state.execution_tracepoints.unresolved,
        .saturated = state.execution_tracepoints.saturated(),
    };
    for (state.execution_tracepoints.entries[0..state.execution_tracepoints.count]) |entry| {
        if (entry.boundary == execution_tracepoints.unbound_boundary or
            entry.boundary >= preflight_lib.graphics_readiness.boundary_count)
        {
            continue;
        }
        facts.armed_by_boundary[entry.boundary] +|= 1;
    }
    return facts;
}

/// Seed the executable path report before the host smoke test. Static image
/// evidence is not a runtime pass: host stages stay untested until exercised,
/// while guest-owned stages are explicitly not-reached because this function
/// runs before guest start.
fn seedGraphicsPathFacts(state: *MachOState) preflight_lib.graphics_path_probe.Facts {
    const probe = preflight_lib.graphics_path_probe;
    var facts = probe.Facts{};
    for (0..probe.stage_count) |index| {
        const stage: probe.Stage = @enumFromInt(index);
        const host_admission_stage = switch (stage) {
            .native_application_ready, .native_window_ready, .native_layer_attached, .vulkan_loader_resolved, .vulkan_instance_ready, .vulkan_surface_ready, .physical_adapter_ready, .logical_device_ready, .graphics_queue_ready, .swapchain_ready, .frame_resources_ready, .native_present_completed => true,
            else => false,
        };
        if (!host_admission_stage) {
            facts.set(
                stage,
                .not_reached,
                "this downstream stage cannot execute before guest start; it is not a pre-window pass",
                "guest start",
            );
        }
    }
    facts.set(
        .application_started,
        if (state.event_stream.run_id != 0) .satisfied else .unknown,
        "Rosette established the run identity before admission",
        "run identity",
    );
    facts.set(
        .guest_image_mapped,
        .satisfied,
        "the translated guest image is mapped and available to the preflight observer",
        "",
    );
    return facts;
}

const hostGraphicsAdmissionStages = [_]preflight_lib.graphics_path_probe.Stage{
    .native_application_ready,
    .native_window_ready,
    .native_layer_attached,
    .vulkan_loader_resolved,
    .vulkan_instance_ready,
    .vulkan_surface_ready,
    .physical_adapter_ready,
    .logical_device_ready,
    .graphics_queue_ready,
    .swapchain_ready,
    .frame_resources_ready,
    .native_present_completed,
};

fn markHostAdmissionFailure(
    facts: *preflight_lib.graphics_path_probe.Facts,
    failed_stage: preflight_lib.graphics_path_probe.Stage,
    detail: []const u8,
) void {
    var found = false;
    for (hostGraphicsAdmissionStages) |stage| {
        if (stage == failed_stage) {
            facts.set(stage, .blocked, detail, failed_stage.label());
            found = true;
        } else if (found) {
            facts.set(stage, .not_reached, "the host admission probe stopped at its first failed stage", failed_stage.label());
        }
    }
}

fn hostPresenterFailureIndex(stage: gpu.NativePresenterStage) ?usize {
    return switch (stage) {
        .loader_unavailable => 0,
        .instance_extensions_missing, .instance_failed => 1,
        .surface_failed => 2,
        .no_supported_physical_device => 3,
        .device_failed, .device_lost => 4,
        .frame_resources_failed => 7,
        .swapchain_failed, .surface_not_presentable => 6,
        .unstarted, .ready => null,
    };
}

fn markHostPresenterFacts(
    facts: *preflight_lib.graphics_path_probe.Facts,
    stage: gpu.NativePresenterStage,
) void {
    const probe = preflight_lib.graphics_path_probe;
    const host_stages = [_]probe.Stage{
        .vulkan_loader_resolved,
        .vulkan_instance_ready,
        .vulkan_surface_ready,
        .physical_adapter_ready,
        .logical_device_ready,
        .graphics_queue_ready,
        .swapchain_ready,
        .frame_resources_ready,
    };

    if (stage == .ready) {
        for (host_stages) |host_stage| {
            facts.set(host_stage, .satisfied, "native presenter smoke test completed this stage", "");
        }
        facts.set(
            .native_present_completed,
            .not_reached,
            "a guest-produced source is required; the preflight never promotes a host clear to guest output",
            "guest frame source",
        );
        return;
    }

    const failure_index = hostPresenterFailureIndex(stage) orelse return;
    for (host_stages, 0..) |host_stage, index| {
        if (index < failure_index) {
            facts.set(host_stage, .satisfied, "native presenter smoke test completed this stage", "");
        } else if (index == failure_index) {
            facts.set(
                host_stage,
                if (stage == .surface_not_presentable) .degraded else .blocked,
                stage.label(),
                stage.label(),
            );
        } else {
            facts.set(host_stage, .not_reached, "the native presenter stopped at its first failed stage", stage.label());
        }
    }
    facts.set(
        .native_present_completed,
        .not_reached,
        "the native presenter did not reach a guest-owned presentation request",
        stage.label(),
    );
}

fn runGraphicsPathPreflight(
    state: *MachOState,
    static_report: *const preflight_lib.graphics_readiness.Report,
) preflight_lib.graphics_path_probe.Report {
    const probe = preflight_lib.graphics_path_probe;
    var facts = seedGraphicsPathFacts(state);

    // A static failure is intentionally not repaired by the executable probe.
    // Preserve the common image facts, leave host stages untested, and let the
    // two reports explain whether the refusal was structural or operational.
    // The host portion remains UNTESTED when static admission fails: no
    // executable probe was attempted. That is different from the
    // NOT_REACHED tail produced after a probe actually stops at a blocker.
    if (!static_report.allowsGuestStart()) return probe.evaluate(facts);

    // The native window gate normally prevents this operation from running
    // before the static report is complete. The probe is the authority that
    // earns the permission, so open the gate only for this hidden smoke test;
    // no show call is made and no guest pixels are presented.
    state.graphics_preflight_window_allowed = true;
    const application_ready = state.ensureNativeApplication();
    if (!application_ready) {
        markHostAdmissionFailure(&facts, .native_application_ready, "NSApplication ensure failed during the host smoke test");
        return probe.evaluate(facts);
    }
    facts.set(.native_application_ready, .satisfied, "NSApplication ensure completed", "");

    const window_ready = state.ensureNativeWindow();
    if (!window_ready) {
        markHostAdmissionFailure(&facts, .native_window_ready, "NSWindow ensure failed during the host smoke test");
        return probe.evaluate(facts);
    }
    facts.set(.native_window_ready, .satisfied, "NSWindow ensure completed without making it visible", "");

    const layer_ready = state.native_window.attachLayer(native_window_runtime.METAL_LAYER_TOKEN);
    if (!layer_ready) {
        markHostAdmissionFailure(&facts, .native_layer_attached, "CAMetalLayer attachment failed during the host smoke test");
        return probe.evaluate(facts);
    }
    facts.set(.native_layer_attached, .satisfied, "CAMetalLayer attachment completed", "");

    const presenter_stage = state.dynamic_forwarder.preflightNativePresenter(state);
    markHostPresenterFacts(&facts, presenter_stage);
    return probe.evaluate(facts);
}

fn graphicsPathStageLabel(stage: ?preflight_lib.graphics_path_probe.Stage) []const u8 {
    return if (stage) |value| value.label() else "none";
}

fn logGraphicsPathPreflight(report: *const preflight_lib.graphics_path_probe.Report) void {
    machoCapturePrint(
        "macho-processor: GRAPHICS PREFLIGHT TESTS: schema={d} verdict={s} admission={s} window_gate={} plan_complete={} planned_stages={d} stages={d} evaluated={d} evaluated_percent={d} satisfied={d} coverage_percent={d} degraded={d} blocked={d} untested={d} not_reached={d} unknown={d} actionable={d} deferred={d} first_actionable={s} first_deferred={s}; terminal_on_admission_failure=YES; guest-owned phases are deferred, never counted as passes\n",
        .{
            preflight_lib.graphics_path_probe.schema_version,
            report.verdict.label(),
            if (report.windowGateAllows()) "ALLOW" else "REFUSE",
            report.windowGateAllows(),
            report.plan_complete,
            report.planned_stages,
            report.total,
            report.tested(),
            report.testedPercent(),
            report.satisfied,
            report.coveragePercent(),
            report.degraded,
            report.blocked,
            report.untested,
            report.not_reached,
            report.unknown,
            report.actionable,
            report.deferred,
            graphicsPathStageLabel(report.first_actionable),
            graphicsPathStageLabel(report.first_deferred),
        },
    );
    for (report.paths) |path_report| {
        machoCapturePrint(
            "  graphics-health-test path={s} complete={} progress={d}/{d} coverage_percent={d} satisfied={d} degraded={d} blocked={d} untested={d} not_reached={d} unknown={d} evaluated={d}/{d} evaluated_percent={d} actionable={d} deferred={d} first_missing={s} first_actionable={s} first_deferred={s}\n",
            .{
                path_report.path.label(),
                path_report.complete(),
                path_report.progress(),
                path_report.total,
                path_report.coveragePercent(),
                path_report.satisfied,
                path_report.degraded,
                path_report.blocked,
                path_report.untested,
                path_report.not_reached,
                path_report.unknown,
                path_report.tested(),
                path_report.total,
                path_report.testedPercent(),
                path_report.actionable(),
                path_report.deferred(),
                graphicsPathStageLabel(path_report.first_missing),
                graphicsPathStageLabel(path_report.first_actionable),
                graphicsPathStageLabel(path_report.first_deferred),
            },
        );
    }
    for (report.layers) |layer_report| {
        machoCapturePrint(
            "  graphics-health-test layer={s} stages={d} satisfied={d} degraded={d} blocked={d} untested={d} not_reached={d} unknown={d} actionable={d} deferred={d} first_actionable={s} first_deferred={s}\n",
            .{
                layer_report.layer.label(),
                layer_report.total,
                layer_report.satisfied,
                layer_report.degraded,
                layer_report.blocked,
                layer_report.untested,
                layer_report.not_reached,
                layer_report.unknown,
                layer_report.actionable(),
                layer_report.deferred(),
                graphicsPathStageLabel(layer_report.first_actionable),
                graphicsPathStageLabel(layer_report.first_deferred),
            },
        );
    }
    for (report.stages) |stage_report| {
        machoCapturePrint(
            "  graphics-health-test stage_index={d} stage={s} state={s} phase={s} probe={s} owner={s} layer={s} detail={s} blocked_by={s} next_action={s}\n",
            .{
                @intFromEnum(stage_report.stage),
                stage_report.stage.label(),
                stage_report.state.label(),
                stage_report.phase.label(),
                stage_report.probe,
                stage_report.owner.label(),
                stage_report.layer.label(),
                stage_report.detail,
                if (stage_report.blocked_by.len != 0) stage_report.blocked_by else "none",
                stage_report.next_action,
            },
        );
    }
    machoCapturePrint(
        "  graphics-health-test window_gate={d}/{d} first_missing={s} first_actionable={s} first_deferred={s} reason={s}; native_present_completed is intentionally downstream of a guest-owned frame source\n",
        .{
            report.window_gate_satisfied,
            report.window_gate_total,
            graphicsPathStageLabel(report.window_gate_first_missing),
            graphicsPathStageLabel(report.first_actionable),
            graphicsPathStageLabel(report.first_deferred),
            report.admissionReason(),
        },
    );
}

/// Preserve the raw host probe inputs beside the derived stage verdict. The
/// stage line says *which* contract stopped; this snapshot says whether the
/// cause was AppKit state, surface binding, loader discovery, driver
/// selection, or a native Vulkan result. It is emitted only once at admission
/// and therefore cannot create a per-frame logging cost.
fn logGraphicsHostPreflightSnapshot(state: *const MachOState) void {
    const status = state.native_window.snapshot();
    const presenter = &state.dynamic_forwarder.native_presenter.report;
    const stage = state.dynamic_forwarder.nativePresenterStage();
    machoCapturePrint(
        "macho-processor: GRAPHICS PREFLIGHT HOST SNAPSHOT: app=0x{x} window=0x{x} view=0x{x} layer=0x{x} metal_device=0x{x} drawable={d}x{d} ready(app/window/layer/main)={}/{}/{}/{} surface_bindings={d} native_stage={s} native_attempts={d} loader_attempts/failures={d}/{d} VkResult={d} rejection={s}\n",
        .{
            status.application,
            status.window,
            status.view,
            status.metal_layer,
            status.metal_device,
            status.width,
            status.height,
            status.application_ready != 0,
            status.window_ready != 0,
            status.layer_attached != 0,
            status.on_main_thread != 0,
            state.native_window.surface_bindings,
            @tagName(stage),
            state.dynamic_forwarder.native_presenter_attempts,
            state.dynamic_forwarder.native_vulkan_loader_attempts,
            state.dynamic_forwarder.native_vulkan_loader_failures,
            presenter.last_result,
            presenter.rejectionLabel(),
        },
    );
    machoCapturePrint(
        "macho-processor: GRAPHICS PREFLIGHT DRIVER SNAPSHOT: physical_devices={d} queues(graphics/present/unified)={d}/{d}/{} swapchain_images={d} swapchain_extent={d}x{d} requested={d}x{d} extent_contract(failed/failures/required/observed)={}/{}/{d}x{d}/{d}x{d} native_present_completed=NO\n",
        .{
            presenter.physical_device_count,
            presenter.graphics_family,
            presenter.present_family,
            presenter.unified_queue,
            presenter.swapchain_image_count,
            presenter.extent_width,
            presenter.extent_height,
            presenter.requested_extent_width,
            presenter.requested_extent_height,
            state.dynamic_forwarder.graphics_extent_contract_failed,
            state.dynamic_forwarder.graphics_extent_contract_failures,
            state.dynamic_forwarder.graphics_extent_requested_width,
            state.dynamic_forwarder.graphics_extent_requested_height,
            state.dynamic_forwarder.graphics_extent_observed_width,
            state.dynamic_forwarder.graphics_extent_observed_height,
        },
    );
}

fn reportGraphicsPreflight(state: *MachOState, decoder_ready: bool) bool {
    const readiness = preflight_lib.graphics_readiness;
    const report = readiness.auditMetadata(state.allocator, &state.metadata, .{
        .entry_point = state.entry_point_vaddr,
        .image_is_x86_64 = true,
        .tracepoints = graphicsTracepointFacts(state),
        .decoder_baseline_ready = decoder_ready,
        .decode_instruction = preflightDecodeInstruction,
        .host_capabilities = &state.host_capabilities,
        .image_fingerprint = state.audit_image_fingerprint,
        .prelaunch = state.prelaunch_audit_summary,
    }) catch |err| {
        state.graphics_preflight_report = .{};
        state.graphics_preflight_window_allowed = false;
        machoCapturePrint(
            "macho-processor: GRAPHICS PREFLIGHT: verdict=UNKNOWN error={s}; the static graphics contract could not be evaluated, so no window is admitted\n",
            .{@errorName(err)},
        );
        return false;
    };
    state.graphics_preflight_report = report;

    machoCapturePrint(
        "macho-processor: GRAPHICS PREFLIGHT: static_verdict={s} admission={s} complete={} checks={d} satisfied={d} degraded={d} blocked={d} unknown={d} required_unknown={d} check_overflowed={} checks_dropped={d} elapsed_scope=static; admission is fail-closed for required findings, while advisory unknowns remain visible and keep complete=false\n",
        .{
            report.verdict.label(),
            if (report.allowsGuestStart()) "ALLOW" else "REFUSE",
            report.complete(),
            report.check_count,
            report.satisfied,
            report.degraded,
            report.blocked,
            report.unknown,
            report.required_unknown,
            report.check_overflowed,
            report.checks_dropped,
        },
    );
    if (report.firstBlockedCheck()) |item| {
        machoCapturePrint(
            "  graphics-preflight first_blocked state={s} required={} observed={d} expected={d} check={s} action={s}\n",
            .{ item.state.label(), item.required, item.observed, item.expected, item.name, item.detail },
        );
    }
    if (report.firstRequiredUnknownCheck()) |item| {
        machoCapturePrint(
            "  graphics-preflight first_required_unknown state={s} required={} observed={d} expected={d} check={s} action={s}\n",
            .{ item.state.label(), item.required, item.observed, item.expected, item.name, item.detail },
        );
    }
    if (report.firstNonSatisfiedCheck()) |item| {
        machoCapturePrint(
            "  graphics-preflight first_non_satisfied state={s} required={} observed={d} expected={d} check={s} action={s}\n",
            .{ item.state.label(), item.required, item.observed, item.expected, item.name, item.detail },
        );
    }
    machoCapturePrint(
        "  image x86_64={} image_hash=0x{x} text_hash=0x{x} contract_hash=0x{x} text_bytes={d} symbols={d}/{d} imports={d} dylibs={d} bindings={d} decoder_entries={d} decoder_invalid={d} linear_decode={d}/{d} linear_invalid={d} linear_bytes={d}/{d} graph_nodes={d} graph_reachable={d} direct_edges={d} graph_complete={}\n",
        .{
            report.image_is_x86_64,
            report.image_fingerprint,
            report.text_fingerprint,
            report.contract_fingerprint,
            report.text_bytes,
            report.symbol_entries,
            report.unique_symbol_entries,
            report.import_stubs,
            report.dylibs,
            report.bindings,
            report.decoder_checked,
            report.decoder_invalid,
            report.linear_decoder_valid,
            report.linear_decoder_checked,
            report.linear_decoder_invalid,
            report.linear_decoder_bytes_covered,
            report.text_bytes,
            report.graph.nodes,
            report.graph.reachable_nodes,
            report.graph.direct_edges,
            report.graph.complete,
        },
    );
    if (report.linear_first_invalid_address != 0) {
        machoCapturePrint(
            "  decoder linear_first_invalid=0x{x}; arbitrary-byte linear sweeps can encounter literal data, so this is retained as coverage unknown rather than treated as a required instruction failure\n",
            .{report.linear_first_invalid_address},
        );
    }
    if (report.prelaunch.evaluated) {
        machoCapturePrint(
            "  prelaunch census verdict={s} symbols={d} import_stubs={d}; all classified stages are included below and empty nonblocking stages remain visible\n",
            .{ report.prelaunch.verdict.label(), report.prelaunch.symbols, report.prelaunch.import_stubs },
        );
        for (preflight_lib.prelaunch_audit.contract_stages) |stage| {
            const stage_facts = report.prelaunch.stages[@intFromEnum(stage)];
            machoCapturePrint(
                "  prelaunch-stage {s} symbols={d} fingerprint=0x{x} range=0x{x}..0x{x} blocking={}\n",
                .{
                    stage.label(),
                    stage_facts.symbols,
                    stage_facts.fingerprint,
                    stage_facts.lowest_address,
                    stage_facts.highest_address,
                    stage.blocksLaunch(),
                },
            );
        }
    }
    for (report.components) |component| {
        machoCapturePrint(
            "  graphics-component {s} owner={s} proof={s} state={s} essential={} obligation={s}\n",
            .{
                component.component.label(),
                component.component.owner(),
                component.proof.label(),
                component.state.label(),
                component.essential,
                component.component.obligation(),
            },
        );
    }
    if (report.first_invalid_address != 0) {
        machoCapturePrint(
            "  decoder first_invalid_entry=0x{x}; symbol-entry coverage is advisory unless a required graphics boundary has no decodable candidate\n",
            .{report.first_invalid_address},
        );
    }
    for (report.checks[0..report.check_count]) |item| {
        machoCapturePrint(
            "  graphics-preflight check={s} state={s} required={} observed={d} expected={d} detail={s}\n",
            .{ item.name, item.state.label(), item.required, item.observed, item.expected, item.detail },
        );
    }
    for (report.boundaries) |fact| {
        machoCapturePrint(
            "  graphics-boundary {s} requirement={s} owner={s} symbols={d} executable={d} candidates={d} decodable={d} armed={d} direct_reachable={} direct_inbound={}\n",
            .{
                fact.boundary.label(),
                fact.boundary.requirement().label(),
                fact.boundary.owner().label(),
                fact.symbol_matches,
                fact.executable_candidates,
                fact.candidate_count,
                fact.decoder_valid_candidates,
                fact.armed_candidates,
                fact.direct_reachable,
                fact.direct_inbound,
            },
        );
    }

    const path_report = runGraphicsPathPreflight(state, &report);
    state.graphics_path_preflight = path_report;
    logGraphicsPathPreflight(&path_report);
    logGraphicsHostPreflightSnapshot(state);
    const static_allowed = report.allowsGuestStart();
    const host_allowed = path_report.windowGateAllows();
    state.graphics_preflight_window_allowed = static_allowed and host_allowed;
    machoCapturePrint(
        "macho-processor: GRAPHICS PREFLIGHT DECISION: static_admission={s} host_window_admission={s} prewindow_candidate={s} final_host_closure=DEFERRED terminal_on_failure=YES static_reason={s} path_reason={s}; no bypass is implicit\n",
        .{
            if (static_allowed) "ALLOW" else "REFUSE",
            if (host_allowed) "ALLOW" else "REFUSE",
            if (static_allowed and host_allowed) "ALLOW" else "REFUSE",
            if (report.firstBlockedCheck()) |item| item.detail else if (report.firstRequiredUnknownCheck()) |item| item.detail else "no required static finding",
            path_report.admissionReason(),
        },
    );

    machoCapturePrint(
        "macho-processor: PRE-WINDOW COVERAGE: static and host-path probes complete; full Rosette-owned closure is deferred until identity, interop, and the startup compiler have sealed their evidence\n",
        .{},
    );
    if (!path_report.windowGateAllows()) {
        machoCapturePrint(
            "macho-processor: GRAPHICS PREFLIGHT: refusing native window admission; first_missing={s} first_actionable={s} probe={s} phase={s} next_action={s}. Static image presence is insufficient\n",
            .{
                graphicsPathStageLabel(path_report.window_gate_first_missing),
                graphicsPathStageLabel(path_report.first_actionable),
                if (path_report.first_actionable) |stage| stage.preflightProbe() else "none",
                if (path_report.first_actionable) |stage| stage.preflightPhase().label() else "none",
                if (path_report.first_actionable) |stage| stage.guidance() else "no actionable host gap",
            },
        );
    }
    return static_allowed and host_allowed;
}

/// What the image pre-flight established about the media being hashed.
///
/// The hash's fault observer is a bare function pointer with nowhere to carry a
/// context, and without the image's layout a fault is only an offset. This is
/// how the two meet: written once before the digest starts, read only if it
/// fails.
var audited_image_volume: ?xiso_format.VolumeDescriptor = null;
var audited_image_bytes: u64 = 0;
var audited_image_preflight_passed: bool = false;

/// Establish whether the image is *usable* before anything reads it whole.
///
/// Being whole costs gigabytes of reads; being usable costs the volume
/// descriptor and the root directory table, at offsets the container format
/// fixes in advance. Running the cheap question first means an image that could
/// never have mounted is refused in milliseconds instead of at the end of a
/// digest that was never going to finish.
fn preflightUnsigned(name: [*:0]const u8, fallback: u64, maximum: u64) u64 {
    const raw = environmentText(name) orelse return fallback;
    const parsed = std.fmt.parseUnsigned(u64, raw, 10) catch return fallback;
    return @min(parsed, maximum);
}

fn reportMediaPreflight(io: std.Io, path: []const u8) void {
    const finding = xiso_preflight.inspectFile(io, path, .{
        .content_samples = @intCast(preflightUnsigned("ROSETTE_IMAGE_SAMPLES", 64, 64)),
        .sample_budget_ns = preflightUnsigned("ROSETTE_IMAGE_SAMPLE_BUDGET_MS", 1_500, 600_000) *
            std.time.ns_per_ms,
    });
    audited_image_volume = finding.volume;
    audited_image_bytes = finding.image_bytes;
    audited_image_preflight_passed = finding.outcome == .structure_intact;

    machoCapturePrint(
        "macho-processor: AUDIT INPUTS: image preflight outcome={s} bytes={d} probes={d} refusals={d} samples={d}/{d} elapsed_ms={d}\n",
        .{
            finding.outcome.text(),
            finding.image_bytes,
            finding.probes,
            finding.refusals,
            finding.samples_read,
            finding.samples_planned,
            @divTrunc(finding.elapsed_ns, std.time.ns_per_ms),
        },
    );

    if (finding.volume) |volume| {
        machoCapturePrint(
            "macho-processor: AUDIT INPUTS: image layout partition_base=0x{x} descriptor=0x{x} directory_table=0x{x} directory_bytes={d}\n",
            .{ volume.game_offset, volume.descriptorOffset(), volume.rootOffset(), volume.root_size },
        );
    }

    if (finding.refused_offset) |offset| {
        const kind_text = if (finding.refused_kind) |kind| kind.text() else "unknown";
        const impact_text = if (finding.impact()) |impact| impact.text() else "unclassified";
        machoCapturePrint(
            "macho-processor: AUDIT INPUTS: image refusal offset={d} probe={s} error={s} impact={s}\n",
            .{ offset, kind_text, finding.refused_error, impact_text },
        );
    }

    switch (finding.outcome) {
        .structure_intact => machoCapturePrint(
            "macho-processor: AUDIT INPUTS: image PREFLIGHT PASS; the image identifies and its directory table reads. This is not a claim that it is whole — only the content hash establishes that\n",
            .{},
        ),
        .content_suspect => machoCapturePrint(
            "macho-processor: AUDIT INPUTS: image PREFLIGHT CONTENT SUSPECT; the image mounts and a sampled region does not read. Whatever file occupies that region is gone; the rest of the image is unaffected\n",
            .{},
        ),
        .structure_unreadable => machoCapturePrint(
            "macho-processor: AUDIT INPUTS: image PREFLIGHT FAIL structure; the image cannot be mounted, so no run of it can proceed. Restore the image from its source rather than retrying\n",
            .{},
        ),
        .not_an_image => machoCapturePrint(
            "macho-processor: AUDIT INPUTS: image PREFLIGHT FAIL identity; no known partition base carries the disc magic. This file is not a disc image, which is a different problem from a damaged one\n",
            .{},
        ),
        .unavailable => machoCapturePrint(
            "macho-processor: AUDIT INPUTS: image PREFLIGHT SKIPPED; the path could not be opened or measured, so nothing about the image was established\n",
            .{},
        ),
    }
}

fn reportInputHashDiagnosis(diagnosis: run_manifest.InputFaultDiagnosis) void {
    machoCapturePrint(
        "macho-processor: AUDIT INPUTS: fault owner={s} offset={d} request_bytes={d} error={s} device_wait_ms={d} recovery_events={d}\n",
        .{
            diagnosis.owner.text(),
            diagnosis.offset,
            diagnosis.request_bytes,
            diagnosis.error_name,
            @divTrunc(diagnosis.fault_wait_ns, std.time.ns_per_ms),
            diagnosis.recovery_events,
        },
    );

    if (diagnosis.allocated_bytes) |allocated| {
        const size = diagnosis.logical_size orelse 0;
        if (allocated >= size) {
            machoCapturePrint(
                "macho-processor: AUDIT INPUTS: allocation logical={d} allocated={d} fully_allocated=YES; every byte the file claims is stored, so the unreadable region was written and later stopped reading back\n",
                .{ size, allocated },
            );
        } else {
            machoCapturePrint(
                "macho-processor: AUDIT INPUTS: allocation logical={d} allocated={d} fully_allocated=NO; the file holds fewer bytes than its length claims and was never written whole\n",
                .{ size, allocated },
            );
        }
    } else {
        machoCapturePrint(
            "macho-processor: AUDIT INPUTS: allocation unavailable; block count could not be read, so truncation and media damage are not separated on this volume\n",
            .{},
        );
    }

    if (diagnosis.survey) |survey| {
        const bounded = if (survey.budget_exhausted) "YES" else "NO";
        const elapsed_ms = @divTrunc(survey.elapsed_ns, std.time.ns_per_ms);
        if (survey.first_fault_offset) |first_fault| {
            if (survey.damagedBytes()) |damaged| {
                machoCapturePrint(
                    "macho-processor: AUDIT INPUTS: damage first_unreadable={d} resumes={d} bytes={d} probe_bytes={d} probes={d} refused={d} elapsed_ms={d} bounded={s}\n",
                    .{
                        first_fault,
                        survey.resume_offset orelse first_fault,
                        damaged,
                        survey.probe_bytes,
                        survey.probes_attempted,
                        survey.probes_failed,
                        elapsed_ms,
                        bounded,
                    },
                );
            } else {
                machoCapturePrint(
                    "macho-processor: AUDIT INPUTS: damage first_unreadable={d} resumes=UNREACHED probe_bytes={d} probes={d} refused={d} elapsed_ms={d} bounded={s}; readable data was not found inside the probe budget, so this is a floor on the damage and not its size\n",
                    .{
                        first_fault,
                        survey.probe_bytes,
                        survey.probes_attempted,
                        survey.probes_failed,
                        elapsed_ms,
                        bounded,
                    },
                );
            }
        } else {
            machoCapturePrint(
                "macho-processor: AUDIT INPUTS: damage none_confirmed scan_start={d} probes={d} refused={d} elapsed_ms={d} bounded={s}; the failed window read cleanly when probed on its own, so the refusal was transient rather than a hole\n",
                .{
                    survey.scan_start,
                    survey.probes_attempted,
                    survey.probes_failed,
                    elapsed_ms,
                    bounded,
                },
            );
        }
        if (survey.tail_readable) |tail_readable| {
            if (tail_readable) {
                machoCapturePrint(
                    "macho-processor: AUDIT INPUTS: tail probe readable=YES; the end of the file still answers, so the damage is a region rather than the volume ending here\n",
                    .{},
                );
            } else {
                machoCapturePrint(
                    "macho-processor: AUDIT INPUTS: tail probe readable=NO; the end of the file does not answer either, so the damage is not known to be bounded\n",
                    .{},
                );
            }
        }
    }

    // An offset is not a diagnosis. The same hole is fatal over the volume
    // descriptor and merely unfortunate in the middle of one file's data, and
    // only the image's layout separates them.
    if (audited_image_volume) |volume| {
        if (diagnosis.survey) |survey| {
            if (survey.first_fault_offset) |first_fault| {
                const damage_end = survey.resume_offset orelse (first_fault + survey.probe_bytes);
                const impact = xiso_format.impactOfDamage(
                    volume,
                    audited_image_bytes,
                    first_fault,
                    damage_end,
                );
                if (impact.blocksMount()) {
                    machoCapturePrint(
                        "macho-processor: AUDIT INPUTS: image impact={s} blocks_mount=YES; the unreadable region covers structure the image cannot be mounted without\n",
                        .{impact.text()},
                    );
                } else {
                    machoCapturePrint(
                        "macho-processor: AUDIT INPUTS: image impact={s} blocks_mount=NO; the unreadable region is file contents, so the image still identifies and mounts and only what occupies that region is lost\n",
                        .{impact.text()},
                    );
                }
            }
        }
    }

    switch (diagnosis.owner) {
        .host_media => machoCapturePrint(
            "macho-processor: AUDIT INPUTS: VERDICT host-media; the image is intact as recorded and the volume will not return part of it. Restore the input from its source onto storage that reads back, and treat this volume as suspect. Repackaging the title changes nothing here\n",
            .{},
        ),
        .input_truncated => machoCapturePrint(
            "macho-processor: AUDIT INPUTS: VERDICT input-truncated; the input is shorter than it claims to be and was never written whole. Repackage or recopy the image; the volume is not accused\n",
            .{},
        ),
        .input_replaced => machoCapturePrint(
            "macho-processor: AUDIT INPUTS: VERDICT input-replaced; the file changed underneath the digest, so no hash of it would describe the input this run was given\n",
            .{},
        ),
        .undetermined => machoCapturePrint(
            "macho-processor: AUDIT INPUTS: VERDICT undetermined; the evidence does not separate a damaged input from a failing volume, and the audit will not name an owner it cannot show\n",
            .{},
        ),
    }
}

fn hashInputPath(io: std.Io, path: []const u8, source: []const u8) InputFingerprint {
    machoCapturePrint(
        "macho-processor: AUDIT INPUTS: hashing path={s} source={s}\n",
        .{ path, source },
    );
    const hash_options = run_manifest.defaultFileHashOptions();
    machoCapturePrint(
        "macho-processor: AUDIT INPUTS: hash policy max_recovery_ms={d} max_recovery_events={d} recovery_reset_bytes={d} retry_limit={d} retry_chunk_bytes={d} final_retry_chunk_bytes={d}\n",
        .{
            @divTrunc(hash_options.max_recovery_time_ns, std.time.ns_per_ms),
            hash_options.max_recovery_events,
            hash_options.recovery_reset_bytes,
            hash_options.retry_limit,
            hash_options.retry_chunk_bytes,
            hash_options.final_retry_chunk_bytes,
        },
    );
    const hash = run_manifest.hashFileContentsWithDiagnosis(
        io,
        path,
        reportInputHashProgress,
        reportInputHashRetry,
        reportInputHashFailure,
        reportInputHashDiagnosis,
        reportInputSurveyStart,
        hash_options,
    ) catch |err| {
        machoCapturePrint(
            "macho-processor: AUDIT INPUTS: hash failure path={s} source={s} error={s}\n",
            .{ path, source, @errorName(err) },
        );
        // Say what the failure costs, rather than leaving a zero fingerprint
        // to be read later as an input that was simply never declared.
        machoCapturePrint(
            "macho-processor: AUDIT INPUTS: identity unestablished path={s}; the fingerprint is recorded as 0x0, this run cannot be compared to any other run of the same input, and a generated media identity cannot be matched\n",
            .{path},
        );
        return .{ .hash = 0, .source = path };
    };
    machoCapturePrint(
        "macho-processor: AUDIT INPUTS: hash complete path={s} hash=0x{x}\n",
        .{ path, hash },
    );
    return .{ .hash = hash, .source = path };
}

fn hashInputReference(io: std.Io, env_name: [*:0]const u8, value: []const u8) InputFingerprint {
    const declared = run_manifest.hashFromEnvironment(env_name);
    if (declared != 0) {
        machoCapturePrint(
            "macho-processor: AUDIT INPUTS: using declared hash source={s} hash=0x{x}\n",
            .{ std.mem.span(env_name), declared },
        );
        return .{ .hash = declared, .source = "environment" };
    }

    // hashFromEnvironment intentionally rejects path-shaped values.  At this
    // boundary we do have the authority to open the named input, so hash its
    // verified bytes rather than ever hashing the pathname itself.
    return hashInputPath(io, value, std.mem.span(env_name));
}

fn configuredInputFingerprint(
    io: std.Io,
    primary: [*:0]const u8,
    alias: [*:0]const u8,
    argument_path: ?[]const u8,
) InputFingerprint {
    for ([_][*:0]const u8{ primary, alias }) |name| {
        if (environmentText(name)) |value| return hashInputReference(io, name, value);
    }
    if (argument_path) |path| return hashInputPath(io, path, "launch argument");
    return .{};
}

fn hostIdentityDescriptor(buffer: []u8) []const u8 {
    const cpu_profile = environmentText("ROSETTE_X64_CPU_PROFILE") orelse "xenia";
    return std.fmt.bufPrint(
        buffer,
        "os={s};arch={s};page={d};x64-profile={s}",
        .{
            @tagName(builtin.target.os.tag),
            @tagName(builtin.target.cpu.arch),
            std.heap.page_size_min,
            cpu_profile,
        },
    ) catch "runtime-host-descriptor-unavailable";
}

fn runtimeValue(name: [*:0]const u8, default_value: []const u8) []const u8 {
    return environmentText(name) orelse default_value;
}

pub fn loadAndRun(io: std.Io, allocator: std.mem.Allocator, options: MachORunOptions) !u64 {
    native_crash.recordPhase("load");
    var output = runtime_output.Controller.init(allocator);
    defer output.deinit();
    output.human("Loading Mach-O...\n", .{});

    // The diagnostic transport, if this run asked for it.
    //
    // Synchronous by default. `ROSETTE_ASYNC_LOG=1` moves every diagnostic
    // write off the translated guest threads and onto one writer thread, so
    // observing the guest stops changing the guest's scheduling. It is opt-in
    // because it trades a counted gap under load for that property, and a run
    // that is not investigating timing would rather have the complete log.
    const async_started = startAsyncDiagnosticTransport(allocator, &output);
    defer if (async_started) stopAsyncDiagnosticTransport();

    machoCapturePrint(
        "macho-processor: STARTUP: reading Mach-O image path={s}\n",
        .{options.path},
    );
    const file_data = std.Io.Dir.cwd().readFileAlloc(io, options.path, allocator, .unlimited) catch |err| {
        machoCapturePrint(
            "macho-processor: STARTUP: Mach-O image read failure path={s} error={s}\n",
            .{ options.path, @errorName(err) },
        );
        return err;
    };
    defer allocator.free(file_data);

    const slice = extractX8664Slice(allocator, file_data) catch |err| {
        machoCapturePrint("macho-processor: not a valid x86_64 Mach-O binary: {s}\n", .{@errorName(err)});
        return 1;
    };
    const image_fingerprint = std.hash.Wyhash.hash(0, slice);
    machoCapturePrint(
        "macho-processor: STARTUP: Mach-O image loaded bytes={d}; constructing runtime state before reading launch inputs\n",
        .{slice.len},
    );

    var state = MachOState.init(io, allocator, slice) catch |err| {
        machoCapturePrint(
            "macho-processor: STARTUP: runtime state initialization failure error={s}\n",
            .{@errorName(err)},
        );
        return err;
    };
    defer state.deinit();
    state.audit_image_fingerprint = image_fingerprint;
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
    machoCapturePrint(
        "macho-processor: STARTUP: runtime diagnostics open; launch-input verification is next\n",
        .{},
    );
    // Armed before the launch-input audit so the watch covers everything from
    // here on, Rosette's own lines and the guest's mirrored ones alike.
    fatal_conditions.configure(
        fatal_conditions.policyFromText(environmentText("ROSETTE_FATAL_CONDITIONS")),
        environmentText("ROSETTE_FATAL_CONDITIONS_ALLOW"),
    );
    fatal_context_state = &state;
    fatal_conditions.setContextProvider(fatalConditionContext);
    fatal_conditions.arm();

    const media_path = launchMediaPath(options.args);
    const config_path = launchOptionValue(options.args, "--config") orelse
        launchOptionValue(options.args, "--config_path") orelse
        launchOptionValue(options.args, "--config-path");
    native_crash.recordPhase("input-hash");
    output.human("Verifying launch inputs...\n", .{});
    // Ahead of the media hash: a build that cannot reach a frame should be
    // refused before six gigabytes are read to identify what it would have run.
    if (!reportPrelaunchAudit(&state) and !environmentFlag("ROSETTE_PRELAUNCH_AUDIT_OFF")) {
        machoCapturePrint(
            "macho-processor: PRELAUNCH AUDIT: refusing to start this build; set ROSETTE_PRELAUNCH_AUDIT_OFF=1 to launch it anyway and read the failure at runtime instead\n",
            .{},
        );
        // 123, not 124: the launchers already exit 124 for their own
        // input-hash stall kill, and a refusal that cannot be told apart from
        // a timeout is a refusal nobody can act on.
        return 123;
    }
    if (media_path) |image_path| {
        if (hasPathSuffixIgnoreCase(image_path, ".iso") or hasPathSuffixIgnoreCase(image_path, ".xiso")) {
            reportMediaPreflight(io, image_path);
            state.audit_media_preflight_evaluated = true;
            state.audit_media_preflight_passed = audited_image_volume != null and audited_image_preflight_passed;
        } else if (hasPathSuffixIgnoreCase(image_path, ".xex")) {
            // A loose XEX is a valid Xenia launch input, not a disc image. Its
            // format parser belongs to the guest, while Rosette can still
            // prove the host-side input operation through the content hash.
            // Mark the disc-format portion not-applicable rather than making
            // loose-XEX launches fail for a check that has no subject.
            state.audit_media_preflight_evaluated = true;
            state.audit_media_preflight_passed = true;
        }
    }
    const media_input = configuredInputFingerprint(
        io,
        "ROSETTE_MEDIA_HASH",
        "XENIA_MEDIA_HASH",
        media_path,
    );
    const config_input = configuredInputFingerprint(
        io,
        "ROSETTE_CONFIG_HASH",
        "XENIA_CONFIG_HASH",
        config_path,
    );
    state.audit_media_fingerprint = media_input.hash;
    state.audit_config_fingerprint = config_input.hash;
    machoCapturePrint(
        "macho-processor: AUDIT INPUTS: media=0x{x} source={s} config=0x{x} source={s}; input paths are content-hashed before authentic admission\n",
        .{
            media_input.hash,
            media_input.source,
            config_input.hash,
            config_input.source,
        },
    );
    if (std.c.getenv("ROSETTE_EXECUTION_PROFILE")) |raw_profile| {
        const profile_text = std.mem.span(raw_profile);
        if (run_manifest.parseProfile(profile_text)) |profile| {
            state.audit_profile = profile;
        } else {
            state.audit_profile_valid = false;
            machoCapturePrint(
                "macho-processor: unknown ROSETTE_EXECUTION_PROFILE={s}; refusing to seal the run manifest\n",
                .{profile_text},
            );
        }
    }
    state.audit_identity_fields = run_manifest.identityFieldsFromEnvironment();
    // `make shell-update` produces the authenticated build artifact consumed
    // by both sides of the bridge.  Environment values may fill genuinely
    // run-specific inputs (for example a device discovered at launch), but a
    // disagreement with the generated content identity is a hard admission
    // conflict, never an override.  The generated artifact is merged before
    // computed runtime defaults are filled: a default is an absence of a
    // deployment declaration, not a second declaration that can falsely
    // conflict with the artifact (notably for host/toolchain identity).
    const explicit_build_identity_path = std.c.getenv("ROSETTE_BUILD_IDENTITY_MANIFEST");
    var owned_identity_paths: [2][]const u8 = undefined;
    var owned_identity_path_count: usize = 0;
    defer for (owned_identity_paths[0..owned_identity_path_count]) |path| allocator.free(path);
    var source_root_contents: ?[]u8 = null;
    defer if (source_root_contents) |contents| allocator.free(contents);
    var identity_candidates: [4][]const u8 = undefined;
    var identity_candidate_count: usize = 0;
    if (explicit_build_identity_path) |raw| {
        identity_candidates[identity_candidate_count] = std.mem.span(raw);
        identity_candidate_count += 1;
    } else {
        if (environmentText("ROSETTE_SOURCE_ROOT")) |source_root| {
            if (std.fs.path.join(allocator, &.{ source_root, ".rosette", "build-identity.json" })) |path| {
                owned_identity_paths[owned_identity_path_count] = path;
                owned_identity_path_count += 1;
                identity_candidates[identity_candidate_count] = path;
                identity_candidate_count += 1;
            } else |_| {}
        }
        if (std.c.getenv("HOME")) |home_raw| {
            const home = std.mem.span(home_raw);
            if (std.fs.path.join(allocator, &.{ home, ".rosette", "source-root" })) |source_root_path| {
                defer allocator.free(source_root_path);
                source_root_contents = std.Io.Dir.cwd().readFileAlloc(
                    io,
                    source_root_path,
                    allocator,
                    .limited(4096),
                ) catch null;
                if (source_root_contents) |contents| {
                    const source_root = std.mem.trim(u8, contents, " \t\r\n");
                    if (source_root.len != 0) {
                        if (std.fs.path.join(allocator, &.{ source_root, ".rosette", "build-identity.json" })) |path| {
                            owned_identity_paths[owned_identity_path_count] = path;
                            owned_identity_path_count += 1;
                            identity_candidates[identity_candidate_count] = path;
                            identity_candidate_count += 1;
                        } else |_| {}
                    }
                }
            } else |_| {}
        }
        identity_candidates[identity_candidate_count] = ".rosette/build-identity.json";
        identity_candidate_count += 1;
    }

    for (identity_candidates[0..identity_candidate_count]) |build_identity_path| {
        if (std.Io.Dir.cwd().readFileAlloc(io, build_identity_path, allocator, .limited(16 * 1024 * 1024))) |bytes| {
            defer allocator.free(bytes);
            if (run_manifest.parseBuildIdentityJson(allocator, bytes)) |generated| {
                var identity_conflict = false;
                const identity_conflict_mask = run_manifest.identityConflictMask(
                    state.audit_identity_fields,
                    generated.fields,
                );
                if (identity_conflict_mask != 0) {
                    var remaining_conflicts = identity_conflict_mask;
                    while (remaining_conflicts != 0) {
                        const field_index: u8 = @intCast(@ctz(remaining_conflicts));
                        const field: run_manifest.IdentityField = @enumFromInt(field_index);
                        machoCapturePrint(
                            "macho-processor: BUILD IDENTITY: conflict field={s} supplied=0x{x} generated=0x{x}\n",
                            .{
                                run_manifest.identityFieldLabel(field),
                                run_manifest.identityFieldValue(state.audit_identity_fields, field),
                                run_manifest.identityFieldValue(generated.fields, field),
                            },
                        );
                        remaining_conflicts &= remaining_conflicts - 1;
                    }
                }
                state.audit_identity_fields = run_manifest.mergeIdentityFields(
                    state.audit_identity_fields,
                    generated.fields,
                    &identity_conflict,
                );
                if (generated.media_hash != 0 and generated.media_hash != state.audit_media_fingerprint) {
                    identity_conflict = true;
                    machoCapturePrint(
                        "macho-processor: BUILD IDENTITY: selected media differs from generated media identity path={s} generated=0x{x} selected=0x{x}\n",
                        .{ build_identity_path, generated.media_hash, state.audit_media_fingerprint },
                    );
                }
                state.audit_identity_conflict = identity_conflict;
                state.audit_build_identity_hash = generated.manifest_hash;
                state.audit_build_identity_loaded = true;
                machoCapturePrint(
                    "macho-processor: BUILD IDENTITY: loaded path={s} hash=0x{x} conflict={} conflict_fields=0x{x} complete={}\n",
                    .{
                        build_identity_path,
                        generated.manifest_hash,
                        identity_conflict,
                        identity_conflict_mask,
                        state.audit_identity_fields.complete(),
                    },
                );
                break;
            } else |err| {
                if (explicit_build_identity_path != null) {
                    state.audit_identity_conflict = true;
                    machoCapturePrint(
                        "macho-processor: BUILD IDENTITY: refusing invalid generated manifest path={s} error={s}\n",
                        .{ build_identity_path, @errorName(err) },
                    );
                    break;
                }
            }
        } else |err| {
            if (explicit_build_identity_path != null) {
                state.audit_identity_conflict = true;
                machoCapturePrint(
                    "macho-processor: BUILD IDENTITY: configured manifest unavailable path={s} error={s}\n",
                    .{ build_identity_path, @errorName(err) },
                );
                break;
            }
        }
    }
    if (!state.audit_build_identity_loaded) {
        machoCapturePrint(
            "macho-processor: BUILD IDENTITY: no generated manifest found; searched the launch context, source-root config, and current directory\n",
            .{},
        );
    }

    var host_identity_buffer: [256]u8 = undefined;
    const host_identity = hostIdentityDescriptor(&host_identity_buffer);
    var launch_config_buffer: [256]u8 = undefined;
    const launch_config = std.fmt.bufPrint(
        &launch_config_buffer,
        "image=0x{x};media=0x{x};config=0x{x};profile={s}",
        .{
            image_fingerprint,
            media_input.hash,
            config_input.hash,
            state.audit_profile.label(),
        },
    ) catch "launch-config-descriptor-unavailable";
    const selected_backend = launchOptionValue(options.args, "--gpu") orelse
        runtimeValue("ROSETTE_BACKEND", "vulkan");
    if (!state.setAuditBackend(selected_backend)) {
        machoCapturePrint(
            "macho-processor: AUDIT IDENTITY: refusing to continue; selected backend name is empty or exceeds the guest admission field\n",
            .{},
        );
        return 125;
    }
    var device_identity_buffer: [320]u8 = undefined;
    const device_identity = std.fmt.bufPrint(
        &device_identity_buffer,
        "{s};{s}",
        .{ host_identity, runtimeValue("ROSETTE_DEVICE", "system-default") },
    ) catch "runtime-device-descriptor-unavailable";
    var driver_identity_buffer: [320]u8 = undefined;
    const driver_identity = std.fmt.bufPrint(
        &driver_identity_buffer,
        "{s};{s}",
        .{ host_identity, runtimeValue("ROSETTE_DRIVER", "system-default") },
    ) catch "runtime-driver-descriptor-unavailable";
    var moltenvk_identity_buffer: [320]u8 = undefined;
    const moltenvk_identity = std.fmt.bufPrint(
        &moltenvk_identity_buffer,
        "{s};{s}",
        .{ host_identity, runtimeValue("ROSETTE_MOLTENVK", "system-default") },
    ) catch "runtime-moltenvk-descriptor-unavailable";
    var metal_identity_buffer: [320]u8 = undefined;
    const metal_identity = std.fmt.bufPrint(
        &metal_identity_buffer,
        "{s};{s}",
        .{ host_identity, runtimeValue("ROSETTE_METAL_CAPABILITIES", "system-default") },
    ) catch "runtime-metal-descriptor-unavailable";
    const runtime_defaults = run_manifest.RuntimeIdentityValues{
        .host = host_identity,
        .driver = driver_identity,
        .cvar = launch_config,
        .backend = selected_backend,
        .device = device_identity,
        .moltenvk = moltenvk_identity,
        .metal = metal_identity,
        .semantic_config = launch_config,
        .time_config = runtimeValue("ROSETTE_TIME_CONFIG", "defaults-v1"),
        .scheduler_config = runtimeValue("ROSETTE_SCHEDULER_CONFIG", "defaults-v1"),
        .observer_config = runtimeValue("ROSETTE_OBSERVER_CONFIG", "defaults-v1"),
        .admission_config = runtimeValue("ROSETTE_ADMISSION_CONFIG", "defaults-v1"),
        .budget_config = runtimeValue("ROSETTE_BUDGET_CONFIG", "defaults-v1"),
        .frontier_config = runtimeValue("ROSETTE_FRONTIER_CONFIG", "defaults-v1"),
    };
    state.audit_identity_fields = run_manifest.completeRuntimeIdentity(
        state.audit_identity_fields,
        runtime_defaults,
    );
    // The exported application-framework ABI must point at the live process
    // ledger, not a detached diagnostic singleton. Register the binding after
    // state construction and clear it before state.deinit releases resources.
    application_framework.activateDefault(&state.application_framework);
    defer application_framework.deactivateDefault(&state.application_framework);
    var host_termination_scope = host_termination.Scope.install();
    defer host_termination_scope.deinit();
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
    // S6 (perf audit): per-instruction CMPXCHG capture is off unless asked
    // for; see the field comment on `cmpxchg_trace_enabled`.
    state.cmpxchg_trace_enabled = environmentFlag("ROSETTE_MACHO_CMPXCHG_TRACE");
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
    // Arm the run-integrity evidence policy before any initializer or guest
    // decode can execute. Translation conflicts are proven at the fill site,
    // so waiting for the first graphics checkpoint would allow the very
    // behavior this diagnostic run is meant to catch to continue unchecked.
    state.ensureRunIntegrity();

    var temp_state = try macho.load(allocator, slice);
    defer temp_state.deinit();

    machoCapturePrint("macho-processor: {s}\n", .{options.path});
    machoCapturePrint("ROSETTE: Loading MachO binary: '{s}'\n", .{options.path});
    if (std.mem.endsWith(u8, options.path, ".iso")) {
        machoCapturePrint("ROSETTE: WARNING: .iso file detected - this may indicate incorrect routing\n", .{});
    }
    // The manifest's identity input. Without it two runs cannot be compared,
    // and a frontier that moved between them is not a finding.
    state.audit_image_fingerprint = image_fingerprint;
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
    state.audit_title_id = @truncate(run_manifest.firstHashFromEnvironment(
        "ROSETTE_TITLE_ID",
        "XENIA_TITLE_ID",
    ));
    state.audit_identity_fields = run_manifest.identityFieldsWithImage(
        state.audit_identity_fields,
        image_fingerprint,
        state.entry_point_vaddr,
    );
    machoCapturePrint(
        "macho-processor: run identity established: run=0x{x}; every boundary record in this log carries it, so records from two runs can never be joined\n",
        .{state.event_stream.run_id},
    );
    // Before anything is armed, ask the machine what it can actually do. The
    // whole run's memory, timing and threading behaviour rests on these, and
    // every one of them has a failure mode that surfaces somewhere else — so
    // this is the last moment at which any of them can be attributed.
    state.logHostCapabilities();
    state.armGraphicsTracepoints();
    const image_is_xenia = has_xbdm_diagnostics or
        std.ascii.indexOfIgnoreCase(options.path, "xenia") != null or
        std.ascii.indexOfIgnoreCase(slice, "vdswap") != null;
    state.graphics_preflight_enabled = image_is_xenia or
        environmentFlag("ROSETTE_GRAPHICS_PREFLIGHT");
    if (state.graphics_preflight_enabled) {
        const graphics_preflight_off = environmentFlag("ROSETTE_GRAPHICS_PREFLIGHT_OFF");
        const graphics_preflight_ok = reportGraphicsPreflight(&state, vex_audit.ready());
        if (state.graphics_extent_contract_faulted or state.terminated) {
            machoCapturePrint(
                "macho-processor: GRAPHICS PREFLIGHT: terminating after non-bypassable runtime extent contract failure; static preflight bypass cannot admit an unproven CAMetalLayer geometry\n",
                .{},
            );
            return state.exit_code;
        }
        if (!graphics_preflight_ok and !graphics_preflight_off) {
            machoCapturePrint(
                "macho-processor: GRAPHICS PREFLIGHT: refusing guest/window start; a required static graphics condition is blocked or unevaluated. Set ROSETTE_GRAPHICS_PREFLIGHT_OFF=1 only to bypass this gate for diagnostics\n",
                .{},
            );
            return 122;
        }
        if (graphics_preflight_off) {
            state.graphics_preflight_window_allowed = true;
            machoCapturePrint(
                "macho-processor: GRAPHICS PREFLIGHT: explicit bypass enabled; static findings remain authoritative and native window admission will still enforce its runtime contract\n",
                .{},
            );
        }
    }
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
    // A host callback is a diagnostic/synthetic intervention, not a default
    // bridge for an authentic run.  The profile gate is evaluated before the
    // provider is armed; the admission ledger records the intervention when a
    // non-authentic profile explicitly permits it.
    state.application_framework.setXeniaHostGpuCallbackEnabled(
        image_is_xenia and
            state.audit_profile != .authentic and
            environmentPolicyFlag("ROSETTE_XENIA_HOST_GPU_CALLBACK", true),
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
        "macho-processor: APPLICATION FRAMEWORK: enabled={} mode={s} trace_control_flow={} trace_memory={} trace_graphics={} host_gpu_callback={} abi=0x{x}\n",
        .{
            application_framework_mode != .disabled,
            application_framework_mode.label(),
            application_framework_config.trace_control_flow != 0,
            application_framework_config.trace_memory != 0,
            application_framework_config.trace_graphics != 0,
            state.application_framework.xeniaHostGpuCallbackEnabled(),
            application_framework.contract.abi_version,
        },
    );
    // Freeze the run identity, profile, admission posture, and durable journal
    // before the ready-compiler plan or any guest initializer can execute.
    state.configureAuditContracts(0);
    if (state.audit_profile == .authentic) {
        if (state.audit_guest_start_verdict != .admitted or
            !state.publishAuditEnvironment(allocator))
        {
            machoCapturePrint(
                "macho-processor: RUN ADMISSION: refusing authentic guest start verdict={s} failure={s} manifest_sealed={} identity_loaded={} identity_conflict={}\n",
                .{
                    state.audit_guest_start_verdict.label(),
                    state.audit_closure_admission_failure.label(),
                    state.audit_manifest.sealIntact(),
                    state.audit_build_identity_loaded,
                    state.audit_identity_conflict,
                },
            );
            return 125;
        }
    }
    // After the seal, before the guest: whether Rosette can answer the identity
    // the guest asks for is not decidable until there is one to answer with.
    if (!reportInteropAudit(allocator, &state) and !environmentFlag("ROSETTE_PRELAUNCH_AUDIT_OFF")) {
        machoCapturePrint(
            "macho-processor: INTEROP AUDIT: refusing to start this build; set ROSETTE_PRELAUNCH_AUDIT_OFF=1 to launch it anyway and read the refusal from the guest instead\n",
            .{},
        );
        return 123;
    }
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
        state.logJitHealth(true);
        machoCapturePrint(
            "macho-processor: READY COMPILER: refusing to launch; the startup contract cannot be satisfied by this image\n",
            .{},
        );
        return 125;
    }
    // This is the final pre-guest boundary.  The graphics report above can
    // only answer static obligations and host path stages; identity/interop
    // and the startup compiler complete the remaining Rosette-owned evidence
    // here.  Guest-owned GPU, swap, frame and presentation edges remain
    // explicitly deferred, because satisfying them before execution would be
    // fabricating the evidence the run is meant to collect.
    if (state.graphics_preflight_enabled or environmentFlag("ROSETTE_PREWINDOW_COVERAGE")) {
        const host_closure_ok = state.enforcePreWindowHostCoverage();
        if (!host_closure_ok and state.audit_profile == .authentic) {
            machoCapturePrint(
                "macho-processor: PRE-WINDOW COVERAGE: refusing guest/window start; the Rosette-owned host contract is not closed. Set ROSETTE_PREWINDOW_COVERAGE_OFF=1 only for a conditional diagnostic run\n",
                .{},
            );
            return 126;
        }
        if (!host_closure_ok) {
            machoCapturePrint(
                "macho-processor: PRE-WINDOW COVERAGE: non-authentic profile is continuing over the host-closure finding; all runtime conclusions are conditional\n",
                .{},
            );
        }
    }
    state.launch_options.logConfiguration(state.internal_targets.cvar_add_to_launch_options_count);
    machoCapturePrint("ROSETTE: MachO state setup completed successfully\n", .{});

    state.startup.enter(.static_init, state.executed_steps);
    native_crash.recordPhase("static_init");
    output.human("Initializing guest runtime...\n", .{});
    machoCapturePrint("macho-processor: running {d} pre-main initializer(s)\n", .{state.metadata.initializer_addresses.len});
    const initializers_ok = state.runInitializers();
    state.initializer_resolver.logSummary();
    if (state.graphics_extent_contract_faulted) {
        machoCapturePrint(
            "macho-processor: initializer phase: terminating after non-bypassable graphics extent contract failure; guest startup cannot continue\n",
            .{},
        );
        return state.exit_code;
    }
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
        state.logJitHealth(true);
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
        state.logGuestLogChannels();
        machoCapturePrint("macho-processor: initializer phase failed: exit_code={d}\n", .{state.exit_code});
        return state.exit_code;
    }

    if (!state.sealReadyCompilerCompile()) {
        state.logReadyCompilerSummary();
        state.logJitHealth(true);
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
        state.logGuestLogChannels();
        machoCapturePrint(
            "macho-processor: graceful host-termination diagnostics complete; returning signal-compatible status={d} without classifying the live guest RIP as a crash\n",
            .{state.exit_code},
        );
        macho_log.checkPointSync();
        return state.exit_code;
    }
    state.logDecodeCacheSummary();
    state.logPerformanceAccelerationSummary();
    state.logGuestLogChannels();
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
    state.logJitHealth(true);
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
    if (state.guest_log_cycles.hasHistory()) {
        const cycle_active = state.guest_log_cycles.active();
        macho_log.machoCapturePrint(
            "macho-processor: guest log cycles: reports={d} longest_period={d} most_iterations={d} still_cycling={} final_period={d}; {s}\n",
            .{
                state.guest_log_cycles.reports,
                state.guest_log_cycles.longest_period,
                state.guest_log_cycles.most_iterations,
                cycle_active,
                state.guest_log_cycles.period,
                if (cycle_active)
                    "the run ended inside a confirmed cycle, so this remains current livelock evidence"
                else
                    "cycle reports are historical; a later guest line broke the cycle, so they do not by themselves establish current livelock",
            },
        );
    }
    // The wait-cycle predictor is the health checker for exactly the run the
    // cycle detector just described: name the objects the guest was cycling on
    // (wait/set/release, with counts and steps) so the loop is an address, not
    // a description. Always dumped so a healthy run reads as "no signatures".
    // The recent window is correlation evidence for a pattern nothing accounts
    // for. When every retained signature is a handshake the wait audit already
    // explained, sixteen more lines of a working pump's operations are not
    // evidence of anything and the verdict line above says so.
    if (state.livelock_predictor.dump(&state, "exit") == .unaccounted_cycle) {
        state.livelock_predictor.dumpRecent(&state);
    }
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
    // The ostringstream/stringstream family is fully modeled by the bridge
    // (constructors, base inits, destructors, synthetic vtables), so its VTT
    // and vtable ABI data must route through the bridge classification rather
    // than the deferred materializer — the D1 destructor loads its hidden VTT
    // before entering D2, and a zeroed VTT is exactly the ostringstream crash.
    try std.testing.expect(MachOState.isBridgedLibcppDataSymbol("__ZTTNSt3__124basic_ostringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEEE"));
    try std.testing.expect(MachOState.isBridgedLibcppDataSymbol("__ZTVNSt3__115basic_stringstreamIcNS_11char_traitsIcEENS_9allocatorIcEEEE"));
    try std.testing.expect(MachOState.isBridgedLibcppDataSymbol("__ZTVNSt3__115basic_stringbufIcNS_11char_traitsIcEENS_9allocatorIcEEEE"));
    try std.testing.expect(MachOState.isBridgedLibcppDataSymbol("__ZTVNSt3__113basic_ostreamIcNS_11char_traitsIcEEE"));
    try std.testing.expect(MachOState.isBridgedLibcppDataSymbol("__ZTVNSt3__115basic_streambufIcNS_11char_traitsIcEEE"));
    try std.testing.expect(!MachOState.isBridgedLibcppDataSymbol("__ZTVN10__cxxabiv117__class_type_infoE"));
    try std.testing.expect(!MachOState.isBridgedLibcppDataSymbol("__ZTVN3xen3ui3d3D11TextureCacheE"));
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
