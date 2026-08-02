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
const logging_runtime = @import("diagnostics").logging_runtime;
const x64_backend_diagnostics = @import("diagnostics").x64_backend_diagnostics;
const xenia_pipeline = @import("diagnostics").xenia_pipeline;
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
const guest_fs = @import("guest_fs.zig");
const proc_diag = @import("process_core").diagnostics;
const thunk_handler = @import("macho_core").thunk_handler;
const execution_helpers = @import("macho_core").execution_helpers;
const execute_impl = @import("process_core").execute;
const memory_access = @import("process_core").memory_access;
const packed_ops = @import("macho_core").packed_ops;
const signal_handling = @import("process_core").signal_handling;
const initializers = @import("process_core").initializers;
const compat_handlers = @import("process_core").compat_handlers;
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
const IMPORT_TRACE_BUFFER_LEN = constants.IMPORT_TRACE_BUFFER_LEN;
const MEMORY_TRACE_BUFFER_LEN = constants.MEMORY_TRACE_BUFFER_LEN;
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
const GuestAssertionClass = types.GuestAssertionClass;
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
    last_guest_assertion_class: GuestAssertionClass = .none,
    last_guest_assertion_step: u64 = 0,
    last_guest_assertion_return: u64 = 0,
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
    stalled_instruction_reports: u64 = 0,
    initializer_abort_requested: bool = false,
    initializer_abort_reason: initialization_resolution.DeferralReason = .none,
    cxxopts_split_accelerations: u64 = 0,
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
    cooperative_starvation_warnings: u64 = 0,
    last_cooperative_starvation_step: u64 = 0,
    ui_callback_retained_quanta: u64 = 0,
    cooperative_quantum_steps: u64 = 0,
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
    native_window: native_window_runtime.Runtime = .{},
    native_window_handles_registered: bool = false,
    local_libcpp_stream_targets: std.AutoHashMap(u64, []const u8),
    logging: logging_runtime.Engine = .{},
    backend_diagnostics: x64_backend_diagnostics.Engine = .{},
    xenia_pipeline: xenia_pipeline.Engine = .{},
    pthreads: pthread_runtime.Runtime = .{},
    scheduler_log: scheduler.SchedulerEventLog = .{},
    jit_log: jit.JitEventLog = .{},
    macho_log: macho_log.Logger = .{},
    tlv: tlv_runtime.Runtime = .{},
    diagnostic_text: diagnostic_text_accelerator.Engine = .{},
    memory_forwarder: memory_management_forwarder.Manager,
    sparse_memory: sparse_virtual_memory.Manager,
    memory_regions: memory_provenance.Registry,
    memory_writes: memory_write_provenance.Tracker = .{},
    generated_endian_contract_recoveries: u64 = 0,
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
    cleo_dispatch_hits: u64 = 0,
    import_handler: import_handler.ImportHandler,
    page_entry_bulk_initializations: u64 = 0,
    page_entry_bulk_bytes: u64 = 0,
    initializer_memory: memory_transaction.Journal,
    initializer_checkpoint: ?InitializerCheckpoint = null,
    trace_entries: [TRACE_BUFFER_LEN]TraceEntry = [_]TraceEntry{TraceEntry{}} ** TRACE_BUFFER_LEN,
    trace_index: usize = 0,
    trace_filled: bool = false,
    trace_range_start: ?u64 = null,
    trace_range_end: ?u64 = null,
    last_trace_rip: u64 = 0,
    last_trace_op: u64 = 0,
    trace_repeat_count: u64 = 0,
    trace_ring_enabled: bool = false,
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
    guest_files: [GUEST_FILE_MAX]GuestFile = [_]GuestFile{GuestFile{}} ** GUEST_FILE_MAX,
    bound_import_thunks: []BoundImportThunk = &.{},
    decode_cache: []DecodeCacheEntry,
    decode_cache_hits: u64 = 0,
    decode_cache_misses: u64 = 0,
    decode_cache_stale_rejections: u64 = 0,
    code_generation: u64 = 1,
    mapped_min: u64,
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
            .mapped_min = mapped_min,
            .executable_min = executable_min,
            .executable_max = executable_max,
        };
        errdefer result.deinit();
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
        var defined_symbols = result.metadata.definedSymbolIterator();
        while (defined_symbols.next()) |entry| {
            if (!libcpp_stream_bridge.Bridge.recognizesSymbol(entry.key_ptr.*)) continue;
            try result.local_libcpp_stream_targets.put(entry.value_ptr.*, entry.key_ptr.*);
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
        self.initializer_memory.deinit();
        self.allocator.free(self.decode_cache);
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
            "macho-processor: applied {d} dyld data binding(s), including {d} local-image pointer(s), {d} validated prebound weak pointer(s), {d} callable GOT pointer(s), {d} writable function pointer(s), and {d}/5 Capstone runtime callback(s); created {d} synthetic import thunk(s); ABI data bridged={d} deferred={d} guest_materialized={d} host_resolved={d}\n",
            .{ applied, local_image_data_bindings, preserved_weak_data_bindings, callable_got_bindings, writable_callable_bindings, capstone_callback_bindings, self.bound_import_thunks.len, bridged_abi_data_bindings, deferred_abi_data_bindings, self.vtt_resolver.synthetic_count, self.vtt_resolver.resolved_count },
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
    pub const captureMemoryMutation = memory_access.captureMemoryMutation;
    pub const commitMemoryMutation = memory_access.commitMemoryMutation;
    const deferInitializerRuntimeDependency = memory_access.deferInitializerRuntimeDependency;
    pub const decodeTraceInstruction = memory_access.decodeTraceInstruction;
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
    const noteGuestWrite = memory_access.noteGuestWrite;
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
    pub fn presentNativeSyntheticVulkanFrame(
        self: *MachOState,
        serial: u64,
        width: u32,
        height: u32,
        stage: u32,
    ) bool {
        return native_window.presentNativeSyntheticVulkanFrame(self, serial, width, height, stage);
    }
    pub fn pumpNativeWindowEvents(self: *MachOState) void {
        return native_window.pumpNativeWindowEvents(self);
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
                _ = self.fs_forwarder.fd_manager.close(file.descriptor_alias);
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

    pub fn logControlFlow(self: *const MachOState, kind: []const u8, from_rip: u64, to_rip: u64, decoded_len: u64, return_addr: ?u64) void {
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

    fn handleStubHelperTransition(self: *MachOState) bool {
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
                                const dest = inner_st.guestMemory(address, @intCast(data.len)) orelse return null;
                                @memcpy(dest[0..data.len], data);
                                return {};
                            }
                        }.write,
                        .readCStringFn = struct {
                            fn read(ptr: *const anyopaque, address: u64) ?[]const u8 {
                                const inner_st: *const MachOState = @ptrCast(@alignCast(ptr));
                                return inner_st.guestCString(address, 4096);
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

                                    const d = st.decodeAt() orelse break;
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

    fn continueGuestExit(self: *MachOState) bool {
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

    pub fn ensureGuestSignalFrameStorage(self: *MachOState, frame: *GuestSignalFrame) bool {
        return signal_handling.ensureGuestSignalFrameStorage(self, frame);
    }

    pub fn finishGuestSignalReturn(self: *MachOState) bool {
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

    fn recordTrace(self: *MachOState, decoded: DecodedInsn) void {
        self.trace_entries[self.trace_index] = .{
            .thread_handle = self.active_guest_thread,
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
        };
        self.trace_index = (self.trace_index + 1) % TRACE_BUFFER_LEN;
        if (self.trace_index == 0) self.trace_filled = true;
    }

    fn shouldTraceRIP(self: *const MachOState, rip: u64) bool {
        if (self.trace_range_start) |start| {
            const end = self.trace_range_end orelse start;
            return rip >= start and rip <= end;
        }
        return false;
    }

    pub fn dumpRecentTrace(self: *const MachOState) void {
        const count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
        if (count == 0) return;
        log.err("recent trace dump (most recent last, count={d})", .{count});
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const idx = if (self.trace_filled)
                (self.trace_index + i) % TRACE_BUFFER_LEN
            else
                i;
            const entry = self.trace_entries[idx];
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

    pub fn regVal(self: *const MachOState, id: RegId, size: Size) u64 {
        return x64_decoder.regVal(&self.regs, id, size);
    }

    pub fn setReg(self: *MachOState, id: RegId, size: Size, val: u64) void {
        x64_decoder.setReg(&self.regs, id, size, val);
    }

    pub fn regOperandVal(self: *const MachOState, id: RegId, size: Size, high8: bool) u64 {
        return x64_decoder.registerOperandValue(&self.regs, .{ .id = id, .high8 = high8 }, size);
    }

    pub fn setRegOperand(self: *MachOState, id: RegId, size: Size, high8: bool, val: u64) void {
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
        const access: GuestAccess = if (direction == .register_to_memory and op != .cmp and op != .test_bits) .write else .read;
        if (!self.ensureGuestAccess(d.addr, bytesForSize(size), access, @tagName(op))) return;
        const reg = if (direction == .memory_to_register) d.dst_reg else d.src_reg;
        const reg_high8 = if (direction == .memory_to_register) d.dst_high8 else d.src_high8;
        const evaluated = x64_decoder.highway.evaluateMemory(op, width, self.regOperandVal(reg, size, reg_high8), self.readMemVal(d.addr, size), direction, self.regs.rflags);
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
        if (memory) {
            const access: GuestAccess = if (op == .cmp or op == .test_bits) .read else .write;
            if (!self.ensureGuestAccess(d.addr, bytesForSize(size), access, @tagName(op))) return;
        }
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

    pub fn handleInternalCompatibility(self: *MachOState) bool {
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

    pub fn handleTomlAsciiFastPath(self: *MachOState) bool {
        return compat_handlers.handleTomlAsciiFastPath(self);
    }

    pub fn handleTomlReadNextIntegrity(self: *MachOState) void {
        compat_handlers.handleTomlReadNextIntegrity(self);
    }

    pub fn handlePatchDbEmptyPatchArray(self: *MachOState) bool {
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
        if (self.sparse_memory.isExecutable(address, 1)) {
            var count: u64 = 16;
            while (count != 0) : (count -= 1) {
                if (self.sparse_memory.executableBytesConst(address, count)) |bytes| return bytes;
            }
            return null;
        }

        const offset = self.addrToOffset(address) orelse return null;
        if (offset >= self.mem.len) return null;
        const remaining = self.mem.len - @as(usize, @intCast(offset));
        return self.mem[@intCast(offset)..][0..@min(@as(usize, 16), remaining)];
    }

    fn decodeAt(self: *MachOState) ?DecodedInsn {
        const fetch_address = self.regs.rip +% x64_decoder.segmentBase(&self.regs, .cs, .long64);
        const cache_index = constants.decodeCacheIndex(fetch_address);
        const entry = &self.decode_cache[cache_index];
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
            var decoded = entry.decoded;
            if (!decoded.rip_relative) {
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
        const bytes = fetched_bytes orelse self.executableInstructionBytesAt(fetch_address) orelse return null;
        var decoded = decodeInsn(bytes);
        if (decoded.op == .invalid and self.sparse_memory.containsMapped(fetch_address, 1)) {
            decoded = decodeInsnCompat(bytes);
        }
        const prefixes = x64_decoder.decodeLegacyPrefixes(bytes);
        decoded.has_0x67 = prefixes.address_size_override;
        const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
        const base_register: ?RegId = if (decoded.sib_has_base) decoded.sib_base_reg else null;
        decoded.segment = x64_decoder.selectSegment(.explicit_data, base_register, prefixes.segment_override);
        const raw_displacement = decoded.addr;
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
        };
        @memcpy(
            entry.instruction_bytes[0..instruction_byte_count],
            bytes[0..instruction_byte_count],
        );
        return decoded;
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
        if (!self.isExecutableAddress(self.regs.rip)) {
            if (self.pending_control_transfer) |context| {
                self.terminateForInvalidControlTransfer(context);
                self.dumpRecentTrace();
                return false;
            }
            machoCapturePrint(
                "macho-processor: invalid control-flow target rip=0x{x}; address is outside executable Mach-O segments\n",
                .{self.regs.rip},
            );
            self.dumpRecentTrace();
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
            self.terminated = true;
            return false;
        }
        self.pending_control_transfer = null;
        const decoded = self.decodeAt() orelse {
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
        };
        if (decoded.op == .invalid) {
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
        if (self.trace_ring_enabled) self.recordTrace(decoded);
        if (self.coop_bootstrap_active and self.coop_bootstrap_index < 24) {
            const idx = self.coop_bootstrap_index;
            self.coop_bootstrap_entries[idx] = .{
                .rip = self.regs.rip,
                .thread = self.active_guest_thread,
                .op = @intFromEnum(decoded.op),
                .len = decoded.len,
            };
            self.coop_bootstrap_index = idx + 1;
            if (self.coop_bootstrap_index == 24) {
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
        }
        if (self.verbose_trace) log.debug("rip=0x{x} op={s} len={d}", .{ self.regs.rip, @tagName(decoded.op), decoded.len });
        // Observe the resolved function entry itself rather than relying on
        // the preceding call target. Lazy-import stubs may transfer here via a
        // jump after Rosette has already handled the original call.
        if (self.sha1_tracer.enabled and
            !self.sha1_tracer.active and
            self.internal_targets.sha1_process_bytes != 0 and
            self.regs.rip == self.internal_targets.sha1_process_bytes)
        {
            self.sha1_tracer.onProcessBytesEntry(self);
        }
        if (self.shouldTraceRIP(self.regs.rip)) {
            const mem_off = self.addrToOffset(self.regs.rip) orelse 0;
            const trace_bytes = self.mem[mem_off..][0..@min(@as(usize, 16), self.mem.len - mem_off)];
            const trace_key = self.regs.rip;
            const op_key = @intFromEnum(decoded.op);
            if (trace_key == self.last_trace_rip and op_key == self.last_trace_op) {
                self.trace_repeat_count +|= 1;
            } else {
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
        }
        const old_rip = self.regs.rip;
        x64_interpreter.execute(self, decoded);
        if (!self.terminated and self.regs.rip == old_rip) {
            self.regs.rip +%= decoded.len;
        }
        if (!self.terminated and
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

    pub fn finishActiveGuestThread(self: *MachOState) void {
        scheduling.finishActiveGuestThread(self);
    }

    pub fn scheduleIdleCallback(self: *MachOState, function: u64, data: u64, tag: []const u8) u64 {
        return scheduling.scheduleIdleCallback(self, function, data, tag);
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

    pub fn currentCooperativeThreadHandle(self: *const MachOState) u64 {
        if (self.active_guest_thread == 0 or self.isSyntheticCallbackHandle(self.active_guest_thread)) {
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

    pub fn handleSyntheticRuntimeThunk(self: *MachOState) bool {
        return thunk_handler.handleSyntheticRuntimeThunk(self);
    }

    pub fn handleTlvBootstrap(self: *MachOState) bool {
        return thunk_handler.handleTlvBootstrap(self);
    }

    pub fn handleBoundImportThunk(self: *MachOState) bool {
        return thunk_handler.handleBoundImportThunk(self);
    }

    pub fn handleDynamicLibraryThunk(self: *MachOState) bool {
        return thunk_handler.handleDynamicLibraryThunk(self);
    }

    pub fn run(self: *MachOState) void {
        var steps: u64 = 0;
        machoCapturePrint(
            "macho-processor: CMPXCHG contract active — 0F B0 executes at byte width, flags use ACC-DEST, and assertion-triggered CAS repair paths are absent.\n",
            .{},
        );
        while (!self.terminated and stepBudgetAllows(self.max_steps, steps)) : (steps +|= 1) {
            self.executed_steps = steps;

            // Never interpret the register file after the cooperative
            // scheduler has parked its owner. A zero active handle means the
            // registers are merely the last saved context, not executable
            // work. Try real queued work once, then stop with a precise
            // invariant failure instead of manufacturing millions of steps.
            if (self.cooperative_ui_context != null and self.active_guest_thread == 0) {
                const started_idle = self.pendingIdleCallbackCount() != 0 and
                    self.startNextIdleCallback("zero-active run guard", true);
                const resumed_worker = !started_idle and self.resumeSuspendedGuestThread();
                if (!started_idle and !resumed_worker) {
                    self.scheduler_log.emit(.{
                        .kind = .deadlock,
                        .step = steps,
                        .thread = 0,
                        .runnable = self.pthreads.activeCount(),
                        .blocked = self.pthreads.blocked_threads,
                        .reason = "zero_active_guest_thread",
                    });
                    machoCapturePrint(
                        "macho-processor: runtime invariant failure: no active or runnable guest thread; refusing stale-register execution rip=0x{x} suspended={d} blocked={d} pending_gtk={d}\n",
                        .{ self.regs.rip, self.suspended_guest_thread_count, self.pthreads.blocked_threads, self.pendingIdleCallbackCount() },
                    );
                    self.faulted = true;
                    self.exit_code = 125;
                    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.runtime_invariant_failure);
                    self.terminated = true;
                    break;
                }
            }

            // Update scheduler step
            // self.thread_scheduler.updateStep(steps);

            // Update scheduler with current context
            // self.thread_scheduler.setUIContext(self.cooperative_ui_context != null);
            // self.thread_scheduler.updatePendingIdle(self.pendingIdleCallbackCount());
            // self.thread_scheduler.updateDeferredThreads(self.pthreads.deferred_threads);
            if (steps != 0 and steps % PROGRESS_REPORT_INTERVAL == 0) {
                const symbol = self.metadata.nearestSymbol(self.regs.rip);
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
            if (steps % HEARTBEAT_INTERVAL == 0) {
                const hb_symbol = self.metadata.nearestSymbol(self.regs.rip);
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
            }
            if (self.concise_output and steps != 0 and steps % 100_000_000 == 0) {
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
            if (!self.step()) break;
            self.maybeYieldActiveGuestThreadForQuantum();
            if (self.page_entry_bulk_initializations != 0 and steps != 0 and steps % 1_000_000 == 0) {
                self.logMemoryInitializationProgress(steps);
            }
        }
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
        if (self.terminated and (self.exit_code != 0 or self.unresolved_import_count != 0)) {
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

    fn logDecodeCacheSummary(self: *const MachOState) void {
        proc_diag.logDecodeCacheSummary(self);
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
        /// Master enable — always on, negligible overhead.
        enabled: bool = true,
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
    state.concise_output = output.concise;
    state.diagnostic_output_fd = output.diagnosticsFd();
    state.summary_output_fd = output.summaryFd();
    if (state.summary_output_fd >= 0) {
        var launch_buffer: [2048]u8 = undefined;
        const launch_line = std.fmt.bufPrint(&launch_buffer, "step=0 event=mach_o_launch path={s}\n", .{options.path}) catch "";
        _ = MachOState.hostWriteFdAll(state.summary_output_fd, launch_line);
    }
    state.scheduler_log.open(allocator);
    state.pthreads.attachEventLog(&state.scheduler_log);
    state.jit_log.open(allocator);
    state.macho_log.open(allocator);
    state.macho_log.emit(.{
        .kind = .process_launch,
        .step = 0,
        .reason = options.path,
    });
    output.human("Loading imports...\n", .{});
    state.cpu_profile = selectedCpuProfile();
    state.verbose_trace = options.trace or environmentFlag("ROSETTE_MACHO_VERBOSE_TRACE");
    state.unwinder.verbose = state.verbose_trace or environmentFlag("ROSETTE_MACHO_UNWIND_VERBOSE");
    state.startup.enabled = environmentFlag("ROSETTE_MACHO_STARTUP_TRACE");
    state.contract_verification = environmentFlag("ROSETTE_CONTRACT_VERIFICATION");
    state.strict_initializers = environmentFlag("ROSETTE_MACHO_STRICT_INITIALIZERS");
    state.strict_imports = environmentFlag("ROSETTE_MACHO_STRICT_IMPORTS");
    state.max_steps = environmentUnsigned("ROSETTE_MACHO_MAX_STEPS", state.max_steps);

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
    state.launch_options.logConfiguration(state.internal_targets.cvar_add_to_launch_options_count);
    machoCapturePrint("ROSETTE: MachO state setup completed successfully\n", .{});

    state.startup.enter(.static_init, state.executed_steps);
    output.human("Initializing guest runtime...\n", .{});
    machoCapturePrint("macho-processor: running {d} pre-main initializer(s)\n", .{state.metadata.initializer_addresses.len});
    const initializers_ok = state.runInitializers();
    state.initializer_resolver.logSummary();
    if (!initializers_ok) {
        state.import_resolver.logSummary();
        state.foreign_objects.logSummary();
        state.native_window.logSummary();
        state.dynamic_forwarder.logSummary();
        state.fs_forwarder.logSummary();
        state.libcxx_filesystem.logSummary();
        state.libcxx_streams.logSummary();
        state.logging.logSummary();
        state.backend_diagnostics.logSummary();
        state.xenia_pipeline.logSummary(state.executed_steps);
        state.export_table_mgr.logSummary();
        state.export_table_lc.logSummary();
        state.export_registry.logSummary();
        state.pthreads.logSummary();
        state.logCooperativeSchedulerSummary();
        state.memory_forwarder.logSummary();
        state.logLiveVtableGuardSummary();
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

    state.startup.enter(.main_enter, state.executed_steps);
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

    machoCapturePrint("macho-processor: execution finished: exit_code={d}, faulted={}, terminated={}\n", .{ state.exit_code, state.faulted, state.terminated });
    state.logDecodeCacheSummary();
    state.logPerformanceAccelerationSummary();
    state.import_resolver.logSummary();
    state.foreign_objects.logSummary();
    state.native_window.logSummary();
    state.dynamic_forwarder.logSummary();
    state.fs_forwarder.logSummary();
    state.libcxx_filesystem.logSummary();
    state.libcxx_streams.logSummary();
    state.logging.logSummary();
    state.backend_diagnostics.logSummary();
    state.xenia_pipeline.logSummary(state.executed_steps);
    state.pthreads.logSummary();
    state.logCooperativeSchedulerSummary();
    state.memory_forwarder.logSummary();
    state.logLiveVtableGuardSummary();
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
    state.sparse_memory.logSummary();
    if (state.guest_log_line_count != 0) {
        machoCapturePrint(
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

const decodeInsn = macho_core.decoder.decodeInsn;
const decodeInsnCompat = macho_core.decoder.decodeInsnCompat;

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

test "Mach-O PAGEZERO is excluded from guest memory" {
    try std.testing.expectEqual(@as(?u64, null), mappedOffset(0, 0x2000_0000, 0x4000, 0));
    try std.testing.expectEqual(@as(?u64, null), mappedOffset(0, 0x2000_0000, 0x4000, 0x30));
    try std.testing.expectEqual(@as(?u64, 0x4000), mappedOffset(0, 0x2000_0000, 0x4000, 0x4000));
    try std.testing.expectEqual(@as(?u64, null), mappedOffset(0, 0x2000_0000, 0x4000, 0xffff_ffff_ffff_ffe8));
    try std.testing.expectEqual(@as(?u64, null), mappedOffset(0, 0x2000_0000, 0x4000, 0x800));
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
