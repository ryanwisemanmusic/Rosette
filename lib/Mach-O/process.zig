const std = @import("std");
const builtin = @import("builtin");
const macho = @import("macho.zig");
const fat = @import("fat.zig");
const x64_decoder = @import("x64_decoder");
const x64_interpreter = @import("x64_interpreter");
const macho_runtime = @import("macho_runtime");
const exit_diagnostics = @import("exit_diagnostics");
const macho_metadata = @import("metadata.zig");
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
const symbol_assembly_context = @import("symbol-context/symbol_assembly_context.zig");
const export_table_manager = @import("dyld").export_table_manager;
const export_table_lifecycle = @import("dyld").export_table_lifecycle;
const dynamic_export_registry = @import("dyld").dynamic_export_registry;
const thread_wait_profiler = @import("pthread").thread_wait_profiler;
const contract = @import("contract");
const primitive = @import("primitive");
const import_handler = @import("import_handler");
const dyld = @import("dyld");
const vt = @import("vtable");
const scheduler = @import("scheduler");
const cleo_routing = @import("cleo_routing");
const jit = @import("jit");
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;
const primitiveCapturePrint = macho_log.primitiveCapturePrint;
const syscalls = @import("process/syscalls.zig");
const native_window = @import("process/native_window.zig");
const scheduling = @import("process/scheduling.zig");
const guest_log = @import("process/guest_log.zig");
const guest_fs = @import("guest_fs.zig");
const proc_diag = @import("process/diagnostics.zig");
const thunk_handler = @import("thunk_handler.zig");
const execution_helpers = @import("execution_helpers.zig");
const execute_impl = @import("process/execute.zig");
const packed_ops = @import("packed_ops.zig");
const signal_handling = @import("process/signal_handling.zig");
const initializers = @import("process/initializers.zig");
const compat_handlers = @import("process/compat_handlers.zig");
const crash_diag = @import("process/crash_diag.zig");

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

const constants = @import("constants.zig");
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
const GTK_IDLE_STARVATION_STEPS = constants.GTK_IDLE_STARVATION_STEPS;
const INITIALIZER_STEP_LIMIT = constants.INITIALIZER_STEP_LIMIT;
const GUEST_LOG_BUFFER_SIZE = constants.GUEST_LOG_BUFFER_SIZE;
const DECODE_CACHE_ENTRY_COUNT = constants.DECODE_CACHE_ENTRY_COUNT;
const DECODE_CACHE_HASH_SHIFT = constants.DECODE_CACHE_HASH_SHIFT;
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

const types = @import("types.zig");
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
const GtkIdleCallback = types.GtkIdleCallback;
const GtkIdleDispatchBlock = types.GtkIdleDispatchBlock;
const GtkIdleQueueSnapshot = types.GtkIdleQueueSnapshot;
const RunnableSuspendedSnapshot = types.RunnableSuspendedSnapshot;
const SuspendedGuestThread = types.SuspendedGuestThread;
const GuestSignalAction = types.GuestSignalAction;
const GuestSignalFrame = types.GuestSignalFrame;
const ProfileAccountStage = types.ProfileAccountStage;
const ProfileAccountFlow = types.ProfileAccountFlow;
const MAX_GTK_IDLE_CALLBACKS = types.MAX_GTK_IDLE_CALLBACKS;
const GTK_IDLE_CALLBACK_HANDLE_BASE = types.GTK_IDLE_CALLBACK_HANDLE_BASE;
const MAX_SUSPENDED_GUEST_THREADS = types.MAX_SUSPENDED_GUEST_THREADS;
const GuestAssertionClass = types.GuestAssertionClass;
const classifyGuestAssertion = types.classifyGuestAssertion;
const timerQueueStateName = types.timerQueueStateName;
const gtkIdleQueueSnapshotFor = types.gtkIdleQueueSnapshotFor;
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
    dispatch_block: GtkIdleDispatchBlock = .ready,
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
    gtk_bootstrap_active: bool = false,
    gtk_bootstrap_index: u8 = 0,
    gtk_bootstrap_entries: [24]GtkBootstrapEntry = [_]GtkBootstrapEntry{.{}} ** 24,
    step_trace_entries: [5]StepTraceEntry = [_]StepTraceEntry{.{}} ** 5,
    step_trace_index: u4 = 0,
    step_trace_filled: bool = false,
    mem_init_started: bool = false,
    mem_init_entries: [8]MemInitEntry = [_]MemInitEntry{.{}} ** 8,
    mem_init_index: u8 = 0,
    mem_init_filled: bool = false,
    gtk_heartbeat_index: u4 = 0,
    gtk_heartbeat_filled: bool = false,
    gtk_heartbeat_entries: [5]GtkHeartbeatEntry = [_]GtkHeartbeatEntry{.{}} ** 5,
    ui_handoff_index: u4 = 0,
    ui_handoff_filled: bool = false,
    ui_handoff_entries: [5]UiHandoffEntry = [_]UiHandoffEntry{.{}} ** 5,
    gtk_idle_callbacks: [MAX_GTK_IDLE_CALLBACKS]GtkIdleCallback = [_]GtkIdleCallback{.{}} ** MAX_GTK_IDLE_CALLBACKS,
    gtk_idle_next_source: u64 = 1,
    gtk_idle_scheduled: u64 = 0,
    gtk_idle_started: u64 = 0,
    gtk_idle_completed: u64 = 0,
    gtk_idle_removed: u64 = 0,
    gtk_idle_wakeups: u64 = 0,
    gtk_idle_dispatch_failures: u64 = 0,
    gtk_idle_starvation_warnings: u64 = 0,
    active_gtk_idle_source: u64 = 0,
    active_gtk_idle_callback: u64 = 0,
    active_gtk_idle_started_step: u64 = 0,
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
    vtable_tracker: vt.VtableTracker,
    /// Tracks __cxa_guard variables that were acquired during the current
    /// initializer run.  When the initializer is deferred, these guards are
    /// cleared so the retry starts from a clean initialization state.
    guard_rollback: vt.GuardRollback,
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
            .guard_rollback = vt.GuardRollback.init(allocator),
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
            const force_bound_thunk = bindingRequiresBoundThunk(section);
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
            if (self.capstoneCallbackSlotName(binding.address)) |slot_name| {
                capstone_callback_bindings += 1;
                machoCapturePrint(
                    "macho-processor: Capstone runtime callback binding: slot={s} address=0x{x} import={s} target=0x{x} section={s} repaired_null={}\n",
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

    fn dumpGtkBootstrapTrace(self: *const MachOState) void {
        if (!self.gtk_bootstrap_active or self.gtk_bootstrap_index == 0) return;
        machoCapturePrint(
            "macho-processor: GTK worker bootstrap trace (incomplete, {d}/{d} entries):\n",
            .{ self.gtk_bootstrap_index, 24 },
        );
        for (0..self.gtk_bootstrap_index) |i| {
            const e = &self.gtk_bootstrap_entries[i];
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

    fn dumpMemInitTrace(self: *const MachOState) void {
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

    fn dumpCapstoneCallbackState(self: *const MachOState, reason: []const u8) void {
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

    fn bindingRequiresBoundThunk(section: macho_metadata.Section) bool {
        return std.mem.eql(u8, section.name, "__got");
    }

    pub fn addrToOffset(self: *const MachOState, vaddr: u64) ?u64 {
        if (!self.pointer_firewall.mayDereference(vaddr)) return null;
        return mappedOffset(self.mem_base, self.mem_size, self.mapped_min, vaddr);
    }

    fn setPagePermissions(self: *MachOState, address: u64, size: u64, permissions: u8) void {
        if (size == 0 or address < self.mem_base) return;
        const start_offset = address - self.mem_base;
        const end_offset = std.math.add(u64, start_offset, size) catch return;
        const first_page = start_offset / PAGE_SIZE;
        const end_page = @min((end_offset +| PAGE_SIZE - 1) / PAGE_SIZE, self.page_permissions.len);
        var page = first_page;
        while (page < end_page) : (page += 1) self.page_permissions[@intCast(page)] = permissions;
    }

    fn translateGuest(self: *const MachOState, address: u64, size: u64, access: GuestAccess) ?u64 {
        if (!self.pointer_firewall.mayDereference(address)) return null;
        const offset = mappedOffset(self.mem_base, self.mem_size, self.mapped_min, address) orelse return null;
        const end = std.math.add(u64, offset, size) catch return null;
        if (end > self.mem.len) return null;
        if (size == 0) return offset;
        const required: u8 = switch (access) {
            .read => PAGE_READ,
            .write => PAGE_WRITE,
            .execute => PAGE_EXECUTE,
        };
        const first_page = offset / PAGE_SIZE;
        const last_page = (end - 1) / PAGE_SIZE;
        var page = first_page;
        while (page <= last_page) : (page += 1) {
            if (page >= self.page_permissions.len or self.page_permissions[@intCast(page)] & required == 0) return null;
        }
        return offset;
    }

    fn describeGuestAccess(self: *const MachOState, address: u64, size: u64, access: GuestAccess) GuestAccessDescription {
        const sparse_mapped = self.sparse_memory.containsMapped(address, size);
        const sparse_allowed = switch (access) {
            .read => self.sparse_memory.bytesConst(address, size) != null,
            .write => false,
            .execute => false,
        };
        return .{
            .mapped = sparse_mapped or mappedOffset(self.mem_base, self.mem_size, self.mapped_min, address) != null,
            .allowed = sparse_allowed or self.translateGuest(address, size, access) != null,
            .region = self.memory_regions.find(address, size),
            .pointer_policy = self.pointer_firewall.policyAt(address),
        };
    }

    pub fn isExecutableAddress(self: *const MachOState, address: u64) bool {
        return self.sparse_memory.isExecutable(address, 1) or self.translateGuest(address, 1, .execute) != null;
    }

    pub fn diagnosticSymbol(self: *const MachOState, address: u64) ?exit_diagnostics.SymbolizedAddress {
        if (address == 0) return null;
        const symbol = self.metadata.nearestSymbol(address) orelse return null;
        return .{
            .address = address,
            .symbol = symbol.name,
            .symbol_offset = symbol.offset,
        };
    }

    /// Build a MemoryState referencing this MachOState's memory fields.
    fn ms(self: *const MachOState) memory_mod.MemoryState {
        return .{
            .allocator = self.allocator,
            .mem = self.mem,
            .mem_base = self.mem_base,
            .mem_size = self.mem_size,
            .heap_next = self.heap_next,
            .page_permissions = self.page_permissions,
            .sparse_memory = &self.sparse_memory,
        };
    }

    pub fn read8(self: *const MachOState, vaddr: u64) u8 {
        return memory_mod.read8(&self.ms(), vaddr, self.translateGuest(vaddr, 1, .read));
    }

    pub fn read16(self: *const MachOState, vaddr: u64) u16 {
        return memory_mod.read16(&self.ms(), vaddr, self.translateGuest(vaddr, 2, .read));
    }

    pub fn read32(self: *const MachOState, vaddr: u64) u32 {
        return memory_mod.read32(&self.ms(), vaddr, self.translateGuest(vaddr, 4, .read));
    }

    pub fn read64(self: *const MachOState, vaddr: u64) u64 {
        return memory_mod.read64(&self.ms(), vaddr, self.translateGuest(vaddr, 8, .read));
    }

    pub fn write8(self: *MachOState, vaddr: u64, val: u8) void {
        if (self.sparse_memory.bytes(vaddr, 1, true)) |bytes| {
            bytes[0] = val;
            return;
        }
        const off = self.translateGuest(vaddr, 1, .write) orelse return;
        if (off < self.mem.len) {
            self.initializer_memory.capture(self.mem, @intCast(off), 1);
            self.noteGuestWrite(vaddr, 1);
            self.mem[off] = val;
        }
    }

    pub fn write16(self: *MachOState, vaddr: u64, val: u16) void {
        if (self.sparse_memory.bytes(vaddr, 2, true)) |bytes| {
            std.mem.writeInt(u16, bytes[0..2], val, .little);
            return;
        }
        const off = self.translateGuest(vaddr, 2, .write) orelse return;
        if (off + 2 <= self.mem.len) {
            self.initializer_memory.capture(self.mem, @intCast(off), 2);
            self.noteGuestWrite(vaddr, 2);
            std.mem.writeInt(u16, self.mem[off..][0..2], val, .little);
        }
    }

    pub fn write32(self: *MachOState, vaddr: u64, val: u32) void {
        if (self.sparse_memory.bytes(vaddr, 4, true)) |bytes| {
            std.mem.writeInt(u32, bytes[0..4], val, .little);
            return;
        }
        const off = self.translateGuest(vaddr, 4, .write) orelse return;
        if (off + 4 <= self.mem.len) {
            self.initializer_memory.capture(self.mem, @intCast(off), 4);
            self.noteGuestWrite(vaddr, 4);
            std.mem.writeInt(u32, self.mem[off..][0..4], val, .little);
        }
    }
    pub fn write64(self: *MachOState, vaddr: u64, val: u64) void {
        // Suspicious write: value points into executable (code) memory — likely
        // a tree node pointer getting corrupted with function prologue bytes.
        // Values below 0x100000 (1 MB) are not plausible code pointers (Xenia
        // entry point is at 0x13fa20; MicroProfile token IDs start at 0x10000).
        // Only function_prologue values are genuinely suspicious; generic
        // code_address writes are legitimate initialization (Export struct
        // function pointer storage, hash table bucket counts, CommandVar
        // default value pointers).
        if (val >= MIN_PLAUSIBLE_CODE_POINTER and val >= self.executable_min and val < self.executable_max) {
            if (self.memory_forwarder.allocationSize(vaddr) != null or self.isAddressInMappedMemory(vaddr)) {
                if (detectFunctionProloguePtr(val)) {
                    self.vtable_tracker.heap_corruption_detections +|= 1;
                    const writer_symbol = self.metadata.nearestSymbol(self.regs.rip);
                    machoCapturePrint(
                        "macho-processor: suspicious allocation write: addr=0x{x} value=0x{x} (function prologue) writer=0x{x} {s}+0x{x} step={d}\n",
                        .{
                            vaddr,
                            val,
                            self.regs.rip,
                            if (writer_symbol) |s| s.name else "<unknown>",
                            if (writer_symbol) |s| s.offset else 0,
                            self.executed_steps,
                        },
                    );
                }
            }
        }
        if (self.sparse_memory.bytes(vaddr, 8, true)) |bytes| {
            const prev = std.mem.readInt(u64, bytes[0..8], .little);
            self.memory_writes.record(self.allocator, vaddr, prev, val, self.regs.rip, self.executed_steps, self.active_guest_thread);
            std.mem.writeInt(u64, bytes[0..8], val, .little);
            // Observe only after the guest write commits.  Failed translations
            // must not manufacture vptr history.
            self.recordAllocationWrite(vaddr, .bits64, val);
            return;
        }
        const off = self.translateGuest(vaddr, 8, .write) orelse return;
        if (off + 8 <= self.mem.len) {
            const prev = std.mem.readInt(u64, self.mem[off..][0..8], .little);
            self.memory_writes.record(self.allocator, vaddr, prev, val, self.regs.rip, self.executed_steps, self.active_guest_thread);
            self.initializer_memory.capture(self.mem, @intCast(off), 8);
            self.noteGuestWrite(vaddr, 8);
            std.mem.writeInt(u64, self.mem[off..][0..8], val, .little);
            self.recordAllocationWrite(vaddr, .bits64, val);
        }
    }

    pub fn push(self: *MachOState, val: u64) void {
        self.regs.rsp -|= 8;
        if (!self.ensureGuestAccess(self.regs.rsp, 8, .write, "stack_push")) return;
        self.write64(self.regs.rsp, val);
    }

    pub fn pop(self: *MachOState) u64 {
        if (!self.ensureGuestAccess(self.regs.rsp, 8, .read, "stack_pop")) return 0;
        const val = self.read64(self.regs.rsp);
        self.regs.rsp +|= 8;
        return val;
    }

    pub fn readMemVal(self: *MachOState, addr: u64, size: Size) u64 {
        const bytes = bytesForSize(size);
        const off = self.translateGuest(addr, bytes, .read) orelse {
            self.terminateForGuestAccess(addr, bytes, .read, @tagName(self.trace_entries[if (self.trace_index == 0) TRACE_BUFFER_LEN - 1 else self.trace_index - 1].op));
            return 0;
        };
        const ctx: *anyopaque = @ptrCast(self);
        return memReadMemVal(&self.ms(), addr, size, off, .{
            .ctx = ctx,
            .recoverVtable = struct {
                fn recover(c: *anyopaque, a: u64, suspect: u64) ?u64 {
                    const st: *MachOState = @ptrCast(@alignCast(c));
                    return st.recoverLiveAllocationVtable(a, suspect);
                }
            }.recover,
            .recordAccess = struct {
                fn record(c: *anyopaque, a: u64, bytes_count: u8, v: u64) void {
                    const st: *MachOState = @ptrCast(@alignCast(c));
                    const sz: Size = switch (bytes_count) {
                        1 => .bits8,
                        2 => .bits16,
                        4 => .bits32,
                        8 => .bits64,
                        else => .bits64,
                    };
                    st.recordMemoryAccess(a, sz, "read", v);
                }
            }.record,
        });
    }

    fn recoverLiveAllocationVtable(self: *MachOState, address: u64, current_value: u64) ?u64 {
        const exact_live_base = self.memory_forwarder.allocationSize(address) != null;
        const recovery = self.vtable_tracker.assessLowRead(
            address,
            current_value,
            exact_live_base,
        ) orelse return null;
        const symbol = self.metadata.nearestSymbol(recovery.value) orelse return null;
        if (!self.vtable_tracker.noteRecovery(address, recovery.generation)) return null;
        machoCapturePrint(
            "macho-processor: trusted vtable low-read recovery: object=0x{x} generation={d} allocation_size={d} observed=0x{x} restored=0x{x} vtable={s}+0x{x} established_by=0x{x}@{d} last_write=0x{x}@{d} prior_recoveries={d} thread=0x{x}\n",
            .{
                address,
                recovery.generation,
                self.memory_forwarder.allocationSize(address) orelse 0,
                current_value,
                recovery.value,
                symbol.name,
                symbol.offset,
                recovery.established_by.writer_rip,
                recovery.established_by.writer_step,
                recovery.last_write.writer_rip,
                recovery.last_write.writer_step,
                recovery.prior_recoveries,
                self.active_guest_thread,
            },
        );
        return recovery.value;
    }

    fn logLiveVtableGuardSummary(self: *const MachOState) void {
        machoCapturePrint(
            "macho-processor: vtable runtime: low_reads_checked={d} recoveries={d} write_time_mutations={d} tracked_objects={d} establishments={d} transitions={d} rejected_candidates={d} low_clears={d} retired={d} heap_corruption_detections={d} guard_tracked={d} memory_writes={d}; recovery requires a live allocation base and strict mapped Itanium ZTV evidence\n",
            .{
                self.vtable_tracker.live_vtable_guard_checks,
                self.vtable_tracker.live_vtable_guard_recoveries,
                self.vtable_tracker.live_vtable_write_protections,
                self.vtable_tracker.trackedAllocationCount(),
                self.vtable_tracker.trusted_establishments,
                self.vtable_tracker.trusted_transitions,
                self.vtable_tracker.rejected_candidates,
                self.vtable_tracker.low_clears_observed,
                self.vtable_tracker.retired_records,
                self.vtable_tracker.heap_corruption_detections,
                self.guard_rollback.count(),
                self.memory_writes.entries.count(),
            },
        );
    }

    pub fn hasLiveAllocationVtableHistory(self: *const MachOState, address: u64) bool {
        if (self.memory_forwarder.allocationSize(address) == null) return false;
        return self.vtable_tracker.hasTrustedHistory(address);
    }

    fn vtableIdentityEvidence(self: *const MachOState, value: u64) vt.IdentityEvidence {
        var evidence = vt.IdentityEvidence{ .value = value };
        const symbol = self.metadata.nearestSymbol(value) orelse return evidence;
        evidence.symbol_name = symbol.name;
        evidence.symbol_offset = symbol.offset;

        if (value < 16) return evidence;
        const table = self.guestMemoryConst(value - 16, 24) orelse return evidence;
        evidence.header_mapped = true;
        const typeinfo = std.mem.readInt(u64, table[8..16], .little);
        evidence.typeinfo_plausible =
            typeinfo == 0 or self.guestMemoryConst(typeinfo, 1) != null;
        const first_slot = std.mem.readInt(u64, table[16..24], .little);
        evidence.first_slot_plausible =
            first_slot == 0 or self.isExecutableAddress(first_slot);
        return evidence;
    }

    /// Record only validated vptr identities.  Generic write provenance remains
    /// in memory_writes and cannot authorize vptr recovery.
    fn recordAllocationWrite(self: *MachOState, addr: u64, size: Size, val: u64) void {
        if (size != .bits64) return;
        if (addr < 0x1000 or (addr & 7) != 0) return;
        _ = self.memory_forwarder.allocationSize(addr) orelse return;
        const result = self.vtable_tracker.observeWrite(
            addr,
            self.vtableIdentityEvidence(val),
            .{
                .writer_rip = self.regs.rip,
                .writer_step = self.executed_steps,
                .writer_thread = self.active_guest_thread,
            },
        );
        if (result.disposition == .valid_transition and
            self.vtable_tracker.trusted_transitions <= 64)
        {
            const previous_symbol = self.metadata.nearestSymbol(result.previous_vptr);
            const current_symbol = self.metadata.nearestSymbol(result.trusted_vptr);
            machoCapturePrint(
                "macho-processor: vtable lifecycle transition: object=0x{x} generation={d} previous=0x{x}({s}+0x{x}) current=0x{x}({s}+0x{x}) writer=0x{x} step={d} thread=0x{x}\n",
                .{
                    addr,
                    result.generation,
                    result.previous_vptr,
                    if (previous_symbol) |s| s.name else "<unknown>",
                    if (previous_symbol) |s| s.offset else 0,
                    result.trusted_vptr,
                    if (current_symbol) |s| s.name else "<unknown>",
                    if (current_symbol) |s| s.offset else 0,
                    self.regs.rip,
                    self.executed_steps,
                    self.active_guest_thread,
                },
            );
        }
    }

    /// Check if a pointer value looks like x86 function prologue bytes.
    /// Returns true if `value` starts with common push rbp; mov rbp, rsp patterns.
    /// This indicates heap corruption where code bytes overwrote a data pointer.
    /// Returns true if `addr` falls within the guest memory heap/data region
    /// (between the mapped image end and the stack start).  This catches writes
    /// to tree nodes and other heap allocations that aren't tracked by
    /// memory_forwarder.allocationSize (which only checks allocation bases).
    fn isAddressInMappedMemory(self: *const MachOState, addr: u64) bool {
        const stack_start = self.mem_base + self.mem_size -| self.stack_size;
        return addr >= self.mapped_min and addr < stack_start;
    }

    /// Classify a writer's RIP offset within a known function to provide
    /// semantic context for vtable protection logs.  For example, offset
    /// 0x23 within __tree_right_rotate is the "mov [rdi+0x48], rsi" write
    /// that clears a tree node's parent pointer — when the node and vtable
    /// share the same allocation, this overwrites vtable[9] (offset 0x48).
    fn classifyWriterRipOffset(name: []const u8, offset: u64) []const u8 {
        if (std.mem.indexOf(u8, name, "__tree_right_rotate") != null) {
            if (offset < 0x10) return "tree_rotate_prologue";
            if (offset < 0x30) return "tree_rotate_parent_write";
            return "tree_rotate_body";
        }
        if (std.mem.indexOf(u8, name, "__tree_left_rotate") != null) {
            if (offset < 0x10) return "tree_rotate_prologue";
            if (offset < 0x30) return "tree_rotate_parent_write";
            return "tree_rotate_body";
        }
        if (std.mem.indexOf(u8, name, "__tree_insert_node") != null) {
            if (offset < 0x10) return "tree_insert_prologue";
            return "tree_insert_body";
        }
        return "unknown";
    }

    /// Minimum value that could plausibly be a guest code pointer.
    /// Values below this are clearly small integers (e.g. MicroProfile token
    /// IDs starting at 0x10000). Xenia's entry point is at 0x13fa20 (~1.3 MB).
    const MIN_PLAUSIBLE_CODE_POINTER: u64 = 0x100000;

    fn detectFunctionProloguePtr(value: u64) bool {
        if (value & 0xFF != 0x55) return false; // must start with push rbp
        const byte1 = @as(u8, @truncate((value >> 8) & 0xFF));
        // 55 48 89 e5 (push rbp; mov rbp, rsp)
        // 55 48 8b ec (push rbp; mov rbp, rsp)
        // 55 48 81 ec (push rbp; sub rsp, imm32)
        if (byte1 == 0x48) {
            const byte2 = @as(u8, @truncate((value >> 16) & 0xFF));
            return byte2 == 0x89 or byte2 == 0x8b or byte2 == 0x81;
        }
        // 55 53 48 8b ec (push rbp; push rbx; mov rbp, rsp)
        if (byte1 == 0x53) {
            const byte2 = @as(u8, @truncate((value >> 16) & 0xFF));
            return byte2 == 0x48;
        }
        return false;
    }

    /// Dump heap corruption diagnostics when a pointer value looks like
    /// x86 function prologue bytes rather than a valid data address.
    /// `value` is the corrupted pointer value (e.g., from rax register).
    /// `fault_rip` is the instruction that attempted to dereference it.
    fn dumpHeapCorruptionDiagnostics(self: *MachOState, value: u64, fault_rip: u64) void {
        if (value < 0x1000) return;
        if (!detectFunctionProloguePtr(value)) return;
        self.vtable_tracker.heap_corruption_detections +|= 1;
        machoCapturePrint(
            "macho-processor: heap corruption detected: value=0x{x} matches function prologue pattern (55 48 89 e5 ...) fault_rip=0x{x}\n",
            .{ value, fault_rip },
        );
        // We can't infer the corrupted storage address from the value alone,
        // so report the faulting symbol and leave storage provenance to the
        // generic memory-write tracker.
        const writer_symbol = self.metadata.nearestSymbol(fault_rip);
        if (writer_symbol) |s| {
            machoCapturePrint(
                "macho-processor:   fault context: {s}+0x{x}\n",
                .{ s.name, s.offset },
            );
        }
    }

    fn timerQueueWatchWrite(self: *MachOState, addr: u64, size: Size, val: u64) void {
        if (!self.timer_queue_watch.active) return;
        if (self.timer_queue_watch.logged_writes >= 32) {
            self.timer_queue_watch.active = false;
            return;
        }
        if (addr != self.timer_queue_watch.state_addr) return;
        self.timer_queue_watch.logged_writes +|= 1;
        const state_name = guest_assertion_recovery.timerQueueStateName(@as(u8, @truncate(val)));
        const symbol = self.metadata.nearestSymbol(self.regs.rip);
        machoCapturePrint(
            "  timer queue state write #{d}: addr=0x{x} size={s} val={s}({d}) rip=0x{x} thread=0x{x} symbol={s}\n",
            .{
                self.timer_queue_watch.logged_writes,
                addr,
                @tagName(size),
                state_name,
                @as(u8, @truncate(val)),
                self.regs.rip,
                self.active_guest_thread,
                if (symbol) |s| s.name else "<unknown>",
            },
        );
    }

    pub fn writeMemVal(self: *MachOState, addr: u64, size: Size, val: u64) void {
        const bytes = bytesForSize(size);
        if (self.sparse_memory.bytes(addr, bytes, true)) |storage| {
            self.recordMemoryAccess(addr, size, "write", val);
            if (size == .bits64) {
                self.memory_writes.record(
                    self.allocator,
                    addr,
                    std.mem.readInt(u64, storage[0..8], .little),
                    val,
                    self.regs.rip,
                    self.executed_steps,
                    self.active_guest_thread,
                );
            }
            switch (size) {
                .bits8 => storage[0] = @truncate(val),
                .bits16 => std.mem.writeInt(u16, storage[0..2], @truncate(val), .little),
                .bits32 => std.mem.writeInt(u32, storage[0..4], @truncate(val), .little),
                .bits64 => std.mem.writeInt(u64, storage[0..8], val, .little),
            }
            self.recordAllocationWrite(addr, size, val);
            // Suspicious write: 64-bit value pointing into executable (code) segment
            // written to any heap/data memory — tree node structural corruption pattern.
            // Values below 0x100000 are not plausible code pointers (e.g. MicroProfile token IDs).
            // Only function_prologue values are genuinely suspicious; generic
            // code_address writes are legitimate initialization (Export struct
            // function pointer storage, hash table bucket counts, CommandVar
            // default value pointers).
            if (size == .bits64 and val >= MIN_PLAUSIBLE_CODE_POINTER and val >= self.executable_min and val < self.executable_max) {
                if (self.memory_forwarder.allocationSize(addr) != null or self.isAddressInMappedMemory(addr)) {
                    if (detectFunctionProloguePtr(val)) {
                        self.vtable_tracker.heap_corruption_detections +|= 1;
                        const writer_symbol = self.metadata.nearestSymbol(self.regs.rip);
                        machoCapturePrint(
                            "macho-processor: suspicious allocation write (writeMemVal sparse): addr=0x{x} value=0x{x} (function prologue) writer=0x{x} {s}+0x{x} step={d}\n",
                            .{
                                addr,
                                val,
                                self.regs.rip,
                                if (writer_symbol) |s| s.name else "<unknown>",
                                if (writer_symbol) |s| s.offset else 0,
                                self.executed_steps,
                            },
                        );
                    }
                }
            }
            self.timerQueueWatchWrite(addr, size, val);
            return;
        }
        const off = self.translateGuest(addr, bytes, .write) orelse {
            if (self.deferInitializerRuntimeDependency(addr, size)) return;
            self.terminateForGuestAccess(addr, bytes, .write, @tagName(self.trace_entries[if (self.trace_index == 0) TRACE_BUFFER_LEN - 1 else self.trace_index - 1].op));
            return;
        };
        self.recordMemoryAccess(addr, size, "write", val);
        if (size == .bits64) {
            self.memory_writes.record(
                self.allocator,
                addr,
                std.mem.readInt(u64, self.mem[off..][0..8], .little),
                val,
                self.regs.rip,
                self.executed_steps,
                self.active_guest_thread,
            );
        }
        self.initializer_memory.capture(self.mem, @intCast(off), bytes);
        self.noteGuestWrite(addr, bytes);
        switch (size) {
            .bits8 => self.mem[off] = @truncate(val),
            .bits16 => std.mem.writeInt(u16, self.mem[off..][0..2], @truncate(val), .little),
            .bits32 => std.mem.writeInt(u32, self.mem[off..][0..4], @truncate(val), .little),
            .bits64 => std.mem.writeInt(u64, self.mem[off..][0..8], val, .little),
        }
        self.recordAllocationWrite(addr, size, val);
        // Suspicious write: 64-bit value pointing into executable (code) segment
        // written to any heap/data memory — tree node structural corruption pattern.
        // Values below 0x100000 are not plausible code pointers (e.g. MicroProfile token IDs).
        // Only function_prologue values are genuinely suspicious; generic
        // code_address writes are legitimate initialization (Export struct
        // function pointer storage, hash table bucket counts, CommandVar
        // default value pointers).
        if (size == .bits64 and val >= 0x100000 and val >= self.executable_min and val < self.executable_max) {
            if (self.memory_forwarder.allocationSize(addr) != null or self.isAddressInMappedMemory(addr)) {
                if (detectFunctionProloguePtr(val)) {
                    self.vtable_tracker.heap_corruption_detections +|= 1;
                    const writer_symbol = self.metadata.nearestSymbol(self.regs.rip);
                    machoCapturePrint(
                        "macho-processor: suspicious allocation write (writeMemVal reg): addr=0x{x} value=0x{x} (function prologue) writer=0x{x} {s}+0x{x} step={d}\n",
                        .{
                            addr,
                            val,
                            self.regs.rip,
                            if (writer_symbol) |s| s.name else "<unknown>",
                            if (writer_symbol) |s| s.offset else 0,
                            self.executed_steps,
                        },
                    );
                }
            }
        }
        self.timerQueueWatchWrite(addr, size, val);
    }

    fn deferInitializerRuntimeDependency(self: *MachOState, address: u64, size: Size) bool {
        if (self.initializer_checkpoint == null or address >= 0x1000 or size != .bits64) return false;

        const trace_count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
        if (trace_count == 0) return false;
        const latest_index = if (self.trace_index == 0) TRACE_BUFFER_LEN - 1 else self.trace_index - 1;
        const fault_entry = self.trace_entries[latest_index];
        if (fault_entry.rip != self.regs.rip or fault_entry.thread_handle != self.active_guest_thread) return false;
        const fault = self.decodeTraceInstruction(fault_entry) orelse return false;
        if (fault.op != .mov_mem64_reg64 or !fault.sib_has_base) return false;
        const base_register = fault.sib_base_reg;
        if (traceRegisterValue(fault_entry, base_register) != address) return false;

        var after = address;
        var same_thread_distance: usize = 0;
        var reverse_index = trace_count;
        while (reverse_index != 0) {
            reverse_index -= 1;
            const index = if (self.trace_filled)
                (self.trace_index + reverse_index) % TRACE_BUFFER_LEN
            else
                reverse_index;
            const entry = self.trace_entries[index];
            if (entry.thread_handle != self.active_guest_thread) continue;
            same_thread_distance += 1;
            const before = traceRegisterValue(entry, base_register);
            if (before == after) {
                after = before;
                continue;
            }

            const producer = self.decodeTraceInstruction(entry) orelse return false;
            const producer_is_pointer_load = producer.op == .mov_reg64_mem64;
            const source_address = producer.addr;
            const source_offset = self.translateGuest(source_address, @sizeOf(u64), .read) orelse return false;
            const source_value = std.mem.readInt(u64, self.mem[source_offset..][0..8], .little);
            const region = self.memory_regions.find(source_address, @sizeOf(u64)) orelse return false;
            const source_class: initializer_dependency.SourceClass = switch (region.kind) {
                .macho_data => .writable_image_data,
                .import_got => .import_pointer,
                else => .other,
            };
            const decision = initializer_dependency.classify(.{
                .initializer_active = true,
                .fault_address = address,
                .access_width = bytesForSize(size),
                .store_uses_base_register = true,
                .producer_is_pointer_load = producer_is_pointer_load,
                .producer_destination_matches_base = producer.dst_reg == base_register,
                .producer_source_address = source_address,
                .producer_source_value = source_value,
                .producer_distance = same_thread_distance,
                .source_readable = region.permissions.read,
                .source_writable = region.permissions.write,
                .source_class = source_class,
            });
            if (decision != .defer_and_retry) return false;

            self.initializer_abort_requested = true;
            self.initializer_abort_reason = .runtime_dependency;
            const section = self.metadata.sectionAtAddress(source_address);
            const initializer = self.initializer_resolver.current();
            const source_symbol = self.metadata.nearestSymbol(source_address);
            const source_symbol_name = if (source_symbol) |resolved|
                if (resolved.offset == 0) resolved.name else "<no-exact-symbol>"
            else
                "<unknown>";
            if (initializer == null or initializer.?.attempts == 1) {
                machoCapturePrint(
                    "macho-processor: initializer dependency deferred: initializer={d}/{d} attempt={d} fault_rip=0x{x} null_store=0x{x} base={s} producer_rip=0x{x} source_slot=0x{x} source_symbol={s} source_region={s}/{s} source_value=0x{x} distance={d}; transaction will roll back before retry\n",
                    .{
                        if (initializer) |record| record.index + 1 else 0,
                        self.metadata.initializer_addresses.len,
                        if (initializer) |record| record.attempts else 0,
                        self.regs.rip,
                        address,
                        @tagName(base_register),
                        entry.rip,
                        source_address,
                        source_symbol_name,
                        @tagName(region.kind),
                        if (section) |resolved| resolved.name else region.owner,
                        source_value,
                        same_thread_distance,
                    },
                );
            }
            return true;
        }
        return false;
    }

    pub fn decodeTraceInstruction(self: *const MachOState, entry: TraceEntry) ?DecodedInsn {
        const instruction_bytes: []const u8 = if (self.sparse_memory.executableBytesConst(entry.rip, 16)) |sparse_code|
            sparse_code
        else blk: {
            const offset = self.translateGuest(entry.rip, 1, .execute) orelse return null;
            break :blk self.mem[offset..];
        };
        var decoded = decodeInsn(instruction_bytes);
        const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
        if (decoded.sib_has_index) {
            const index_value = traceRegisterValue(entry, decoded.sib_index_reg);
            decoded.addr +%= (if (address_size == .bits32) @as(u32, @truncate(index_value)) else index_value) << @as(u6, decoded.sib_scale);
        }
        if (decoded.sib_has_base) {
            const base_value = traceRegisterValue(entry, decoded.sib_base_reg);
            decoded.addr +%= if (address_size == .bits32) @as(u32, @truncate(base_value)) else base_value;
        }
        if (decoded.rip_relative) decoded.addr +%= entry.rip + decoded.len;
        if (address_size == .bits32) decoded.addr = @as(u32, @truncate(decoded.addr));
        return decoded;
    }

    fn ensureGuestAccess(self: *MachOState, address: u64, bytes: u8, access: GuestAccess, instruction: []const u8) bool {
        if (access == .read and self.sparse_memory.bytesConst(address, bytes) != null) return true;
        if (access == .write and self.sparse_memory.bytes(address, bytes, true) != null) return true;
        if (access == .execute and self.sparse_memory.isExecutable(address, bytes)) return true;
        if (self.translateGuest(address, bytes, access) != null) return true;
        self.terminateForGuestAccess(address, bytes, access, instruction);
        return false;
    }

    pub fn terminateForGuestAccess(self: *MachOState, address: u64, bytes: u8, access: GuestAccess, instruction: []const u8) void {
        if (self.terminal_memory_failure != null) return;
        if (self.tryQuarantineOpaqueDestructor(address)) return;
        const description = self.describeGuestAccess(address, bytes, access);
        if (access != .execute and description.mapped and !description.allowed) {
            const instruction_len = self.currentGuestInstructionLength();
            if (self.deliverGuestSignal(GUEST_SIGSEGV, self.regs.rip, instruction_len, address, access)) {
                machoCapturePrint(
                    "macho-processor: mapped guest protection fault routed to SIGSEGV handler: rip=0x{x} address=0x{x} bytes={d} access={s} instruction={s}\n",
                    .{ self.regs.rip, address, bytes, @tagName(access), instruction },
                );
                return;
            }
        }
        if (!self.toml_fault_diagnostics_dumped) {
            if (self.metadata.nearestSymbol(self.regs.rip)) |symbol| {
                const toml_symbol = std.mem.indexOf(u8, symbol.name, "toml") != null;
                const patch_db_symbol = std.mem.indexOf(u8, symbol.name, "PatchDB") != null or
                    std.mem.indexOf(u8, symbol.name, "patcher") != null;
                if (toml_symbol or patch_db_symbol) {
                    self.toml_fault_diagnostics_dumped = true;
                    machoCapturePrint(
                        "macho-processor: TOML/PatchDB guest access fault: rip=0x{x} symbol={s}+0x{x} address=0x{x} bytes={d} access={s}; dumping stream and schema state before termination\n",
                        .{ self.regs.rip, symbol.name, symbol.offset, address, bytes, @tagName(access) },
                    );
                    self.libcxx_streams.dumpPatchTomlDiagnostics("TOML/PatchDB guest memory fault");
                    if (patch_db_symbol and address < 0x1000) {
                        self.libcxx_streams.dumpPatchPostParseDiagnosis("near-null access in PatchDB::ReadPatchFile");
                    }
                }
            }
        }
        if (address < 0x1000) self.dumpTerminalAddressProvenance(address);
        const policy = description.pointer_policy;
        const fault: []const u8 = if (policy != null and !policy.?.may_dereference)
            "opaque_identity_dereference"
        else if (description.mapped)
            "permission_denied"
        else
            "unmapped";
        if (self.summary_output_fd >= 0) {
            var summary_buffer: [1024]u8 = undefined;
            const symbol = self.metadata.nearestSymbol(self.regs.rip);
            const region = description.region;
            const summary_line = std.fmt.bufPrint(
                &summary_buffer,
                "step={d} event=memory_fault rip=0x{x} symbol={s}+0x{x} instruction={s} access={s} address=0x{x} bytes={d} fault={s} mapped={} runtime_allowed={} region={s} owner={s} permissions={c}{c}{c}\n",
                .{
                    self.executed_steps,
                    self.regs.rip,
                    if (symbol) |resolved| resolved.name else "<unknown>",
                    if (symbol) |resolved| resolved.offset else 0,
                    instruction,
                    @tagName(access),
                    address,
                    bytes,
                    fault,
                    description.mapped,
                    description.allowed,
                    if (region) |resolved| @tagName(resolved.kind) else "none",
                    if (region) |resolved| resolved.owner else "none",
                    @as(u8, if (region != null and region.?.permissions.read) 'r' else '-'),
                    @as(u8, if (region != null and region.?.permissions.write) 'w' else '-'),
                    @as(u8, if (region != null and region.?.permissions.execute) 'x' else '-'),
                },
            ) catch "";
            _ = hostWriteFdAll(self.summary_output_fd, summary_line);
        }
        self.terminal_memory_failure = .{
            .instruction_address = self.regs.rip,
            .instruction = instruction,
            .address = address,
            .bytes = bytes,
            .access = @tagName(access),
            .fault = fault,
            .mapped = description.mapped,
        };
        // Check for heap corruption when the access involves reading a pointer
        // that looks like function prologue bytes — a common symptom of buffer
        // overflow or use-after-free where code bytes overwrote data pointers.
        if (bytes == 8 or bytes == 4) {
            // The offending value may be in rax (if this was a dereference of
            // a computed address), or we check the fault address itself.
            self.dumpHeapCorruptionDiagnostics(self.regs.rax, self.regs.rip);
        }
        self.dumpStepTraceBuffer();
        self.dumpGtkBootstrapTrace();
        self.dumpMemInitTrace();
        self.dumpGtkHeartbeatTrace();
        self.dumpUiHandoffTrace();
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.memory_access_violation);
    }

    fn dumpStepTraceBuffer(self: *const MachOState) void {
        if (!self.step_trace_filled and self.step_trace_index == 0) return;
        machoCapturePrint("macho-processor: step trace buffer (most recent {d} entries):\n", .{
            if (self.step_trace_filled) 5 else @as(usize, @intCast(self.step_trace_index)),
        });
        const count: usize = if (self.step_trace_filled) 5 else @intCast(self.step_trace_index);
        const start: usize = if (self.step_trace_filled) self.step_trace_index else 0;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const idx = (start + i) % 5;
            const e = &self.step_trace_entries[idx];
            const symbol = self.metadata.nearestSymbol(e.rip);
            machoCapturePrint(
                "  step={d} rip=0x{x} at {s}+0x{x}\n",
                .{
                    e.step,                                  e.rip,
                    if (symbol) |s| s.name else "<unknown>", if (symbol) |s| s.offset else 0,
                },
            );
        }
    }

    fn currentGuestInstructionLength(self: *const MachOState) u8 {
        const latest_index = if (self.trace_index == 0) TRACE_BUFFER_LEN - 1 else self.trace_index - 1;
        const latest = self.trace_entries[latest_index];
        if (latest.rip == self.regs.rip and latest.len != 0) return latest.len;
        const instruction_bytes: []const u8 = if (self.sparse_memory.executableBytesConst(self.regs.rip, 16)) |sparse_code|
            sparse_code
        else blk: {
            const offset = self.translateGuest(self.regs.rip, 1, .execute) orelse return 1;
            break :blk self.mem[offset..];
        };
        const decoded = decodeInsn(instruction_bytes);
        return if (decoded.len != 0) decoded.len else 1;
    }

    fn tryQuarantineOpaqueDestructor(self: *MachOState, address: u64) bool {
        const policy = self.pointer_firewall.policyAt(address) orelse return false;
        if (policy.kind != .opaque_identity or policy.may_dereference) return false;
        const address_is_this = self.regs.rdi == address or self.regs.rsi == address;
        const symbol = self.metadata.nearestSymbol(self.regs.rip) orelse return false;
        if (!opaque_lifetime_recovery.shouldQuarantine(symbol.name, true, address_is_this)) return false;

        var return_address: u64 = 0;
        var restored_via: []const u8 = "";
        if (self.guestMemoryConst(self.regs.rsp, 8) != null) {
            const candidate = self.read64(self.regs.rsp);
            if (self.isExecutableAddress(candidate)) {
                return_address = candidate;
                self.regs.rsp +|= 8;
                restored_via = "rsp";
            }
        }
        if (return_address == 0 and self.regs.rbp != 0 and self.guestMemoryConst(self.regs.rbp, 16) != null) {
            const candidate = self.read64(self.regs.rbp + 8);
            if (self.isExecutableAddress(candidate)) {
                const previous_rbp = self.read64(self.regs.rbp);
                self.regs.rsp = self.regs.rbp +| 16;
                self.regs.rbp = previous_rbp;
                return_address = candidate;
                restored_via = "rbp";
            }
        }
        if (return_address == 0) return false;

        self.regs.rip = return_address;
        self.opaque_destructor_quarantines +|= 1;
        machoCapturePrint(
            "macho-processor: opaque lifetime quarantine #{d}: destructor={s} this=0x{x} owner={s} restored_caller=0x{x} via={s}; skipped invalid guest cleanup without dereferencing API identity\n",
            .{ self.opaque_destructor_quarantines, symbol.name, address, policy.owner, return_address, restored_via },
        );
        return true;
    }

    fn dumpTerminalAddressProvenance(self: *const MachOState, effective_address: u64) void {
        const bytes = self.guestMemoryConst(self.regs.rip, 16) orelse return;
        const decoded = decodeInsn(bytes);
        if (!decoded.sib_has_base and !decoded.sib_has_index and !decoded.rip_relative) {
            machoCapturePrint(
                "macho-processor: near-null address provenance: rip=0x{x} op={s} effective=0x{x}; decoder exposed no base/index expression\n",
                .{ self.regs.rip, @tagName(decoded.op), effective_address },
            );
            return;
        }

        const address_size: Size = if (decoded.has_0x67) .bits32 else .bits64;
        const base_value = if (decoded.sib_has_base) x64_decoder.regVal(&self.regs, decoded.sib_base_reg, address_size) else 0;
        const index_value = if (decoded.sib_has_index) x64_decoder.regVal(&self.regs, decoded.sib_index_reg, address_size) else 0;
        const scaled_index = index_value << @as(u6, decoded.sib_scale);
        const rip_component = if (decoded.rip_relative) self.regs.rip + decoded.len else 0;
        machoCapturePrint(
            "macho-processor: near-null address provenance: rip=0x{x} op={s} effective=0x{x} displacement=0x{x} base({s})=0x{x} index({s},scale={d})=0x{x} rip_component=0x{x}\n",
            .{
                self.regs.rip,
                @tagName(decoded.op),
                effective_address,
                decoded.addr,
                if (decoded.sib_has_base) @tagName(decoded.sib_base_reg) else "<none>",
                base_value,
                if (decoded.sib_has_index) @tagName(decoded.sib_index_reg) else "<none>",
                @as(u8, 1) << decoded.sib_scale,
                scaled_index,
                rip_component,
            },
        );

        if (decoded.sib_has_base) self.dumpRegisterTransition(decoded.sib_base_reg, base_value, "base");
        if (decoded.sib_has_index) self.dumpRegisterTransition(decoded.sib_index_reg, index_value, "index");
        self.dumpNearNullProducerSlot();
    }

    fn dumpNearNullProducerSlot(self: *const MachOState) void {
        const count: usize = if (self.memory_trace_filled) MEMORY_TRACE_BUFFER_LEN else self.memory_trace_index;
        var reverse_index = count;
        while (reverse_index != 0) {
            reverse_index -= 1;
            const index = if (self.memory_trace_filled)
                (self.memory_trace_index + reverse_index) % MEMORY_TRACE_BUFFER_LEN
            else
                reverse_index;
            const access = self.memory_trace_entries[index];
            if (!std.mem.eql(u8, access.access, "read") or access.value != 0 or
                access.bytes != @sizeOf(u64) or access.address < 0x1000 or
                access.instruction_address == self.regs.rip)
            {
                continue;
            }

            const reader = self.metadata.nearestSymbol(access.instruction_address);
            machoCapturePrint(
                "macho-processor: near-null producer slot: loaded_zero_from=0x{x} reader=0x{x} {s}+0x{x} op={s}\n",
                .{
                    access.address,
                    access.instruction_address,
                    if (reader) |symbol| symbol.name else "<unknown>",
                    if (reader) |symbol| symbol.offset else 0,
                    access.instruction,
                },
            );
            if (self.memory_writes.lookup(access.address)) |writer| {
                const symbol = self.metadata.nearestSymbol(writer.instruction_address);
                machoCapturePrint(
                    "macho-processor: near-null producer last writer: slot=0x{x} previous=0x{x} value=0x{x} writer=0x{x} {s}+0x{x} step={d} age_steps={d} thread=0x{x}\n",
                    .{
                        writer.address,
                        writer.previous_value,
                        writer.value,
                        writer.instruction_address,
                        if (symbol) |resolved| resolved.name else "<unknown>",
                        if (symbol) |resolved| resolved.offset else 0,
                        writer.step,
                        self.executed_steps -| writer.step,
                        writer.thread,
                    },
                );
            } else {
                machoCapturePrint(
                    "macho-processor: near-null producer last writer: slot=0x{x} not retained (tracked_slots={d} dropped_slots={d})\n",
                    .{ access.address, self.memory_writes.entries.count(), self.memory_writes.dropped_slots },
                );
            }
            return;
        }
    }

    fn dumpRegisterTransition(self: *const MachOState, register: RegId, terminal_value: u64, role: []const u8) void {
        const count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
        const fault_thread = self.active_guest_thread;
        var after = terminal_value;
        var same_thread_entries: usize = 0;
        var excluded_entries: usize = 0;
        var reverse_index = count;
        while (reverse_index != 0) {
            reverse_index -= 1;
            const index = if (self.trace_filled)
                (self.trace_index + reverse_index) % TRACE_BUFFER_LEN
            else
                reverse_index;
            const entry = self.trace_entries[index];
            if (entry.thread_handle != fault_thread) {
                excluded_entries += 1;
                continue;
            }
            same_thread_entries += 1;
            const before = traceRegisterValue(entry, register);
            if (before != after) {
                const symbol = self.metadata.nearestSymbol(entry.rip);
                machoCapturePrint(
                    "macho-processor: near-null {s} register transition: thread=0x{x} register={s} before=0x{x} after=0x{x} caused_by=0x{x} {s}+0x{x} op={s} same_thread_distance={d} cross_thread_entries_excluded={d}\n",
                    .{ role, fault_thread, @tagName(register), before, after, entry.rip, if (symbol) |resolved| resolved.name else "<unknown>", if (symbol) |resolved| resolved.offset else 0, @tagName(entry.op), same_thread_entries, excluded_entries },
                );
                return;
            }
            after = before;
        }
        machoCapturePrint(
            "macho-processor: near-null {s} register transition: thread=0x{x} register={s} remained 0x{x} throughout {d} retained same-thread instructions; excluded {d} cross-thread entries\n",
            .{ role, fault_thread, @tagName(register), terminal_value, same_thread_entries, excluded_entries },
        );
    }

    fn traceRegisterValue(entry: TraceEntry, register: RegId) u64 {
        return switch (@intFromEnum(register)) {
            0 => entry.rax,
            1 => entry.rcx,
            2 => entry.rdx,
            3 => entry.rbx,
            4 => entry.rsp,
            5 => entry.rbp,
            6 => entry.rsi,
            7 => entry.rdi,
            8 => entry.r8,
            9 => entry.r9,
            10 => entry.r10,
            11 => entry.r11,
            12 => entry.r12,
            13 => entry.r13,
            14 => entry.r14,
            15 => entry.r15,
        };
    }

    fn recordMemoryAccess(self: *MachOState, address: u64, size: Size, access: []const u8, value: u64) void {
        const bytes = bytesForSize(size);
        const offset = self.translateGuest(address, bytes, if (std.mem.eql(u8, access, "write")) .write else .read);
        const backed = if (offset) |off| off + bytes <= self.mem.len else false;
        const trace_count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
        const instruction = if (trace_count == 0)
            "<runtime>"
        else blk: {
            const latest_index = if (self.trace_index == 0) TRACE_BUFFER_LEN - 1 else self.trace_index - 1;
            break :blk @tagName(self.trace_entries[latest_index].op);
        };
        // Check for near-null or negative addresses (high bit set in 64-bit, or very small positive addresses)
        const near_null = (address & 0x8000_0000_0000_0000) != 0 or address < 0x1000;
        self.memory_trace_entries[self.memory_trace_index] = .{
            .instruction_address = self.regs.rip,
            .instruction = instruction,
            .address = address,
            .bytes = bytes,
            .access = access,
            .value = value,
            .backed = backed,
            .near_null = near_null,
        };
        self.memory_trace_index = (self.memory_trace_index + 1) % MEMORY_TRACE_BUFFER_LEN;
        if (self.memory_trace_index == 0) self.memory_trace_filled = true;
    }

    pub fn readMem128(self: *MachOState, addr: u64) [16]u8 {
        var value = [_]u8{0} ** 16;
        if (self.sparse_memory.bytesConst(addr, 16)) |storage| {
            @memcpy(value[0..], storage[0..16]);
            return value;
        }
        const off = self.translateGuest(addr, 16, .read) orelse {
            self.terminateForGuestAccess(addr, 16, .read, "vector_read");
            return value;
        };
        @memcpy(value[0..], self.mem[off..][0..16]);
        return value;
    }

    pub fn writeMem128(self: *MachOState, addr: u64, value: [16]u8) void {
        if (self.sparse_memory.bytes(addr, 16, true)) |storage| {
            @memcpy(storage[0..16], value[0..]);
            return;
        }
        const off = self.translateGuest(addr, 16, .write) orelse {
            self.terminateForGuestAccess(addr, 16, .write, "vector_write");
            return;
        };
        self.initializer_memory.capture(self.mem, @intCast(off), 16);
        self.noteGuestWrite(addr, 16);
        @memcpy(self.mem[off..][0..16], value[0..]);
    }

    pub fn guestMemory(self: *MachOState, addr: u64, count: u64) ?[]u8 {
        if (self.sparse_memory.bytes(addr, count, true)) |bytes| return bytes;
        if (count > std.math.maxInt(usize)) return null;
        const off = self.translateGuest(addr, count, .write) orelse return null;
        const off_usize: usize = @intCast(off);
        const count_usize: usize = @intCast(count);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
        self.initializer_memory.capture(self.mem, off_usize, count_usize);
        self.noteGuestWrite(addr, count);
        return self.mem[off_usize .. off_usize + count_usize];
    }

    fn noteGuestWrite(self: *MachOState, address: u64, count: u64) void {
        if (count == 0 or self.executable_min == std.math.maxInt(u64)) return;
        const end = address +| count;
        if (address < self.executable_max and end > self.executable_min) {
            self.code_generation +%= 1;
            if (self.code_generation == 0) self.code_generation = 1;
        }
    }

    pub fn guestMemoryConst(self: *const MachOState, addr: u64, count: u64) ?[]const u8 {
        if (self.sparse_memory.bytesConst(addr, count)) |bytes| return bytes;
        if (count > std.math.maxInt(usize)) return null;
        const off = self.translateGuest(addr, count, .read) orelse return null;
        const off_usize: usize = @intCast(off);
        const count_usize: usize = @intCast(count);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
        return self.mem[off_usize .. off_usize + count_usize];
    }

    pub fn guestAlloc(self: *MachOState, requested_size: u64, alignment: u64) ?u64 {
        const size = @max(requested_size, 1);
        const mask = alignment - 1;
        const start = (self.heap_next + mask) & ~mask;
        const end = std.math.add(u64, start, size) catch return null;
        const stack_floor = self.mem_base + self.mem_size -| self.stack_size;
        if (end > stack_floor) return null;
        const storage = self.guestMemory(start, size) orelse return null;
        @memset(storage, 0);
        self.heap_next = end;
        _ = self.memory_regions.register(start, size, .{}, .guest_heap, "guestAlloc", self.regs.rip);
        _ = self.pointer_firewall.register(start, size, .{ .kind = .owned_guest, .may_dereference = true, .owner = "guestAlloc" });
        return start;
    }

    pub fn registerSyntheticRegion(self: *MachOState, address: u64, size: u64, kind: memory_provenance.RegionKind, owner: []const u8, policy: pointer_firewall.Policy) void {
        const permissions: memory_provenance.Permissions = switch (kind) {
            .synthetic_vtable, .synthetic_typeinfo => .{ .write = false },
            else => .{},
        };
        _ = self.memory_regions.register(address, size, permissions, kind, owner, self.regs.rip);
        _ = self.pointer_firewall.register(address, size, policy);
    }

    pub fn registerOpaqueHandle(self: *MachOState, address: u64, owner: []const u8) void {
        _ = self.memory_regions.register(address, 1, .{ .read = false, .write = false }, .objc_handle, owner, self.regs.rip);
        _ = self.pointer_firewall.register(address, 1, .{ .kind = .opaque_identity, .may_dereference = false, .owner = owner });
    }

    pub fn registerOpaqueApiHandle(self: *MachOState, address: u64, owner: []const u8) void {
        _ = self.memory_regions.register(address, 1, .{ .read = false, .write = false }, .synthetic_handle, owner, self.regs.rip);
        _ = self.pointer_firewall.register(address, 1, .{ .kind = .opaque_identity, .may_dereference = false, .owner = owner });
    }

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
    pub fn pumpNativeWindowEvents(self: *MachOState) void {
        return native_window.pumpNativeWindowEvents(self);
    }

    pub fn registerSyntheticThunk(self: *MachOState, address: u64, size: u64, owner: []const u8) void {
        _ = self.memory_regions.register(address, size, .{ .read = false, .write = false, .execute = true }, .synthetic_thunk, owner, self.regs.rip);
        _ = self.pointer_firewall.register(address, size, .{ .kind = .opaque_identity, .may_dereference = false, .may_execute = true, .owner = owner });
    }

    pub fn guestHeapAllocate(self: *MachOState, size: u64, alignment: u64) ?u64 {
        return self.memory_forwarder.allocate(self, size, alignment);
    }

    pub fn guestHeapRelease(self: *MachOState, address: u64) void {
        self.memory_forwarder.release(address);
        self.vtable_tracker.forgetAddress(address);
    }

    pub fn guestHeapContains(self: *const MachOState, address: u64) bool {
        return self.memory_forwarder.allocationSize(address) != null;
    }

    pub fn forgetMemoryWriteProvenance(self: *MachOState, address: u64) void {
        self.memory_writes.forget(address);
        // Allocation start/reuse is a hard lifecycle boundary.  Retire any
        // trusted vptr belonging to the former occupant before the new
        // allocation becomes visible.
        self.vtable_tracker.forgetAddress(address);
    }

    pub fn guestMapFile(self: *MachOState, address: u64, length: u64, prot: u32, flags: u32, host_fd: std.posix.fd_t, offset: u64) bool {
        const map_fixed: u32 = 0x0010;
        const mapped = if (flags & map_fixed != 0)
            self.sparse_memory.mapFixed(address, length, prot, flags, host_fd, offset)
        else
            self.sparse_memory.mapFile(address, length, prot, flags, host_fd, offset);
        if (!mapped) return false;
        _ = self.memory_regions.register(address, length, .{
            .read = prot & 1 != 0,
            .write = prot & 2 != 0,
            .execute = prot & 4 != 0,
        }, .guest_mmap, "sparse 64K guest mmap", self.regs.rip);
        _ = self.pointer_firewall.register(address, length, .{ .kind = .guest_backed, .may_dereference = true, .may_execute = prot & 4 != 0, .owner = "sparse 64K guest mmap" });
        return true;
    }

    pub fn guestMapAnywhereWithBacking(self: *MachOState, length: u64, prot: u32, flags: u32, host_fd: std.posix.fd_t, offset: u64) ?u64 {
        const address = self.sparse_memory.mapAnywhereWithBacking(length, prot, flags, host_fd, offset) orelse return null;
        const effective_length = sparse_virtual_memory.pageRoundedLength(length) orelse return null;
        _ = self.memory_regions.register(address, effective_length, .{
            .read = prot & 1 != 0,
            .write = prot & 2 != 0,
            .execute = prot & 4 != 0,
        }, .guest_mmap, "OS-selected sparse guest mmap", self.regs.rip);
        _ = self.pointer_firewall.register(address, length, .{
            .kind = .guest_backed,
            .may_dereference = true,
            .may_execute = prot & 4 != 0,
            .owner = "OS-selected sparse guest mmap",
        });
        return address;
    }

    pub fn guestMapBackendWithBacking(self: *MachOState, length: u64, prot: u32, flags: u32, host_fd: std.posix.fd_t, offset: u64) ?u64 {
        const backend_indirection_size: u64 = 0x1FFF_FFFF;
        const backend_code_size: u64 = 0x0FFF_FFFF;
        const executable = prot & 4 != 0;
        const preferred_base: ?u64 = if (!executable and length == backend_indirection_size)
            0x8000_0000
        else if (executable and length == backend_code_size)
            0xA000_0000
        else
            null;
        const maximum_end: ?u64 = if (preferred_base != null) 0x1_0000_0000 else null;
        const address = self.sparse_memory.mapAnywhereWithHintAndBacking(
            length,
            prot,
            flags,
            host_fd,
            offset,
            preferred_base,
            maximum_end,
        ) orelse return null;
        const effective_length = sparse_virtual_memory.pageRoundedLength(length) orelse return null;
        _ = self.memory_regions.register(address, effective_length, .{
            .read = prot & 1 != 0,
            .write = prot & 2 != 0,
            .execute = prot & 4 != 0,
        }, .guest_mmap, "low-window backend sparse mmap", self.regs.rip);
        _ = self.pointer_firewall.register(address, effective_length, .{
            .kind = .guest_backed,
            .may_dereference = true,
            .may_execute = prot & 4 != 0,
            .owner = "low-window backend sparse mmap",
        });
        machoCapturePrint(
            "macho-processor: x64 backend placement contract: requested_length={d} effective_length={d} preferred_base=0x{x} result=0x{x} result_end=0x{x} executable={} below_4g={} pointer_truncation_safe={}\n",
            .{ length, effective_length, preferred_base orelse 0, address, address +| effective_length, executable, address +| effective_length <= 0x1_0000_0000, !executable or address < 0x1_0000_0000 },
        );
        return address;
    }

    pub fn guestReserveAddressSpace(self: *MachOState, length: u64) ?u64 {
        const anon_private: u32 = 0x1000 | 0x2;
        return self.guestReserveAddressSpaceWithBacking(length, anon_private, -1, 0);
    }

    pub fn guestReserveAddressSpaceWithBacking(self: *MachOState, length: u64, flags: u32, host_fd: std.posix.fd_t, offset: u64) ?u64 {
        const address = self.sparse_memory.reserveAnywhereWithBacking(length, flags, host_fd, offset) orelse return null;
        _ = self.memory_regions.register(address, length, .{ .read = false, .write = false }, .guest_mmap, "sparse guest address-space reservation", self.regs.rip);
        _ = self.pointer_firewall.register(address, length, .{ .kind = .guest_backed, .may_dereference = false, .owner = "sparse guest address-space reservation" });
        return address;
    }

    pub fn guestUnmapFile(self: *MachOState, address: u64, length: u64) bool {
        return self.sparse_memory.unmap(address, length);
    }

    pub fn guestProtectSparseMemory(self: *MachOState, address: u64, length: u64, prot: u32) bool {
        if (!self.sparse_memory.protect(address, length, prot)) return false;
        const effective_length = sparse_virtual_memory.pageRoundedLength(length) orelse return false;
        _ = self.memory_regions.register(address, effective_length, .{
            .read = prot & 1 != 0,
            .write = prot & 2 != 0,
            .execute = prot & 4 != 0,
        }, .guest_mmap, "sparse guest mprotect", self.regs.rip);
        return true;
    }

    pub fn renderProcSelfMaps(self: *const MachOState, output: []u8) []const u8 {
        return self.sparse_memory.renderProcSelfMaps(output);
    }

    pub fn guestCString(self: *const MachOState, addr: u64, max_len: usize) ?[]const u8 {
        if (addr == 0) return null;
        const off = self.translateGuest(addr, 1, .read) orelse return null;
        const off_usize: usize = @intCast(off);
        if (off_usize >= self.mem.len) return null;
        const available = self.mem[off_usize..@min(self.mem.len, off_usize + max_len)];
        const end = std.mem.indexOfScalar(u8, available, 0) orelse return null;
        return available[0..end];
    }

    pub fn cxxExceptionTypeName(self: *const MachOState, type_info_address: u64) ?[]const u8 {
        const name_address = self.read64(type_info_address +| 8);
        return self.guestCString(name_address, 4096);
    }

    pub fn cxxExceptionMessage(self: *const MachOState, object_address: u64) ?[]const u8 {
        const runtime_error_message = self.read64(object_address +| 8);
        if (self.guestCString(runtime_error_message, 4096)) |message| {
            if (message.len != 0) return message;
        }
        const message_view = compat_runtime.libcppStringView(self, object_address +| 8) orelse return null;
        if (message_view.length == 0 or message_view.length > 4096) return null;
        const message = self.guestMemoryConst(message_view.address, message_view.length) orelse return null;
        for (message) |byte| {
            if (byte < 0x20 or byte > 0x7E) return null;
        }
        return message;
    }

    fn guestWriteCString(self: *MachOState, addr: u64, bytes: []const u8) bool {
        if (self.guestMemory(addr, bytes.len + 1)) |buf| {
            @memcpy(buf[0..bytes.len], bytes);
            buf[bytes.len] = 0;
            return true;
        }
        return false;
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

    fn dumpGuestStack(self: *const MachOState) void {
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

    fn handleImport(self: *MachOState, imported: macho_metadata.ImportedSymbol) ImportHandlerResult {
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

    fn tryPrimitiveDispatch(self: *MachOState, imported: macho_metadata.ImportedSymbol) ?ImportHandlerResult {
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
        if (self.tryPrimitiveDispatch(imported)) |result| {
            self.import_handler.primitive_dispatch_hits +|= 1;
            return result;
        }

        const cache_index = importRouteCacheIndex(imported.stub_address);
        const entry = &self.import_route_cache[cache_index];
        if (entry.valid and entry.stub_address == imported.stub_address) {
            if (self.dispatchImportRoute(entry.route, imported)) |result| {
                self.import_route_cache_hits +|= 1;
                return result;
            }
            self.import_route_cache_fallbacks +|= 1;
            entry.valid = false;
        } else {
            self.import_route_cache_misses +|= 1;
            if (entry.valid) self.import_route_cache_collisions +|= 1;
        }

        self.resolving_import_route = .legacy;
        const result = self.handleImportSlow(imported);
        entry.* = .{
            .stub_address = imported.stub_address,
            .route = self.resolving_import_route,
            .valid = true,
        };
        return result;
    }

    fn handleImportSlow(self: *MachOState, imported: macho_metadata.ImportedSymbol) ImportHandlerResult {
        const name = imported.name;
        if ((std.mem.eql(u8, name, "_exit") or std.mem.eql(u8, name, "exit")) and
            self.foreign_objects.main_loop_bypasses != 0)
        {
            machoCapturePrint(
                "macho-processor: guest exit attribution: follows {d} bypassed GTK main loop(s); this is UI event-loop shutdown, not a filesystem or config-write failure\n",
                .{self.foreign_objects.main_loop_bypasses},
            );
        }
        if (std.mem.eql(u8, name, "_exit") or std.mem.eql(u8, name, "exit")) {
            const exit_code = self.regs.rdi;
            if (self.beginGuestExit(exit_code)) return .control_transferred;
            if (self.terminated) return .control_transferred;
            return .{ .terminated = exit_code };
        }
        if (std.mem.eql(u8, name, "_memcpy") or std.mem.eql(u8, name, "_memmove") or
            std.mem.eql(u8, name, "___memcpy_chk"))
        {
            self.resolving_import_route = .guest_memory_copy;
            return self.handleGuestMemoryCopy(name);
        }
        if (std.mem.eql(u8, name, "_memset") or std.mem.eql(u8, name, "___memset_chk")) {
            self.resolving_import_route = .memset;
            const dst = self.regs.rdi;
            const val: u8 = @truncate(self.regs.rsi);
            const count = self.regs.rdx;
            if (count != 0) {
                const buf = self.guestMemory(dst, count) orelse return .{ .unsupported = 0 };
                @memset(buf, val);
            }
            return .{ .handled = dst };
        }
        if (std.mem.eql(u8, name, "_pthread_once")) {
            self.resolving_import_route = .pthread;
            const once_control = self.regs.rdi;
            const init_routine = self.regs.rsi;
            const once_value = self.readMemVal(once_control, .bits32);
            if (once_value != 0) return .{ .handled = 0 };
            self.writeMemVal(once_control, .bits32, 1);
            self.regs.rip = init_routine;
            return .control_transferred;
        }
        if (std.mem.eql(u8, name, "_bzero") or std.mem.eql(u8, name, "__bzero")) {
            self.resolving_import_route = .bzero;
            const dst = self.regs.rdi;
            const count = self.regs.rsi;
            if (count != 0) {
                const buf = self.guestMemory(dst, count) orelse return .{ .unsupported = 0 };
                @memset(buf, 0);
            }
            return .{ .handled = 0 };
        }
        if (std.mem.eql(u8, name, "_sysconf")) {
            self.resolving_import_route = .sysconf;
            const selector: i32 = @bitCast(@as(u32, @truncate(self.regs.rdi)));
            const value = guestSysconf(selector);
            if (self.verbose_trace) {
                machoCapturePrint("    [posix] sysconf({d}) -> {d}\n", .{ selector, @as(i64, @bitCast(value)) });
            }
            return .{ .handled = value };
        }
        if (std.mem.eql(u8, name, "_dlopen")) {
            const path = self.guestCString(self.regs.rdi, 1024) orelse return .{ .handled = 0 };
            const handle = self.dynamic_forwarder.openGuest(path, self.regs.rsi);
            if (self.verbose_trace or handle == 0) {
                machoCapturePrint(
                    "    [dynamic loader] dlopen({s}, 0x{x}) -> 0x{x}\n",
                    .{ path, self.regs.rsi, handle },
                );
            }
            return .{ .handled = handle };
        }
        if (std.mem.eql(u8, name, "_dlclose")) {
            const result = self.dynamic_forwarder.closeGuest(self.regs.rdi);
            return .{ .handled = @as(u32, @bitCast(result)) };
        }
        if (std.mem.eql(u8, name, "_dlsym")) {
            const symbol = self.guestCString(self.regs.rsi, 512) orelse return .{ .handled = 0 };
            const address = self.dynamic_forwarder.lookupGuest(self.regs.rdi, symbol);
            if (address != 0) self.registerSyntheticThunk(address, 1, symbol);
            if (self.verbose_trace or address == 0) {
                machoCapturePrint(
                    "    [dynamic loader] dlsym(0x{x}, {s}) -> 0x{x}\n",
                    .{ self.regs.rdi, symbol, address },
                );
            }
            return .{ .handled = address };
        }
        if (std.mem.eql(u8, name, "_SDL_GetVersion")) {
            const output = self.guestMemory(self.regs.rdi, 3) orelse return .{ .unsupported = 0 };
            output[0..3].* = sdlCompatibilityVersion();
            if (self.verbose_trace) {
                machoCapturePrint(
                    "    [SDL2] SDL_GetVersion(output=0x{x}) -> {d}.{d}.{d}\n",
                    .{ self.regs.rdi, output[0], output[1], output[2] },
                );
            }
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "_gtk_main") and self.beginGtkMainLoop()) {
            self.resolving_import_route = .gtk_main;
            return .control_transferred;
        }
        if (std.mem.eql(u8, name, "_gtk_main_quit") and self.cooperative_ui_context != null) {
            self.resolving_import_route = .gtk_main_quit;
            self.foreign_objects.main_loop_quits +|= 1;
            self.restoreGtkMainLoopCaller("gtk_main_quit");
            return .control_transferred;
        }
        if (isGtkIdleAddImport(name)) {
            self.resolving_import_route = .gtk_idle_add;
            return self.handleGtkIdleAdd(name);
        }
        if (std.mem.eql(u8, name, "_g_source_remove")) {
            self.resolving_import_route = .g_source_remove;
            return self.handleGSourceRemove();
        }
        if (isGtkEventsPendingImport(name)) {
            self.resolving_import_route = .gtk_events_pending;
            self.pumpNativeWindowEvents();
            return .{ .handled = @intFromBool(self.pendingGtkIdleCallbackCount() != 0) };
        }
        if (isGtkMainIterationImport(name)) {
            self.resolving_import_route = .gtk_main_iteration;
            self.pumpNativeWindowEvents();
            if (self.startNextGtkIdleCallback(name, false)) return .control_transferred;
            return .{ .handled = 0 };
        }
        if (self.metadata.definedSymbolAddress(name)) |target| {
            if (target != imported.stub_address and self.isExecutableAddress(target)) {
                self.regs.rip = target;
                self.resolving_import_route = .local_definition;
                self.import_provider_override = .local_definition;
                self.import_confidence_override = .verified;
                if (self.verbose_trace) {
                    machoCapturePrint("    [local definition] {s}: stub=0x{x} -> target=0x{x}\n", .{ name, imported.stub_address, target });
                }
                return .control_transferred;
            }
        }
        if (self.dispatchLibcppLocale(name)) |resolution| return resolution;
        if (self.libcxx_streams.dispatch(self, &self.fs_forwarder, name)) |resolution| {
            self.resolving_import_route = .libcxx_stream;
            self.import_provider_override = .libcpp_stream;
            self.import_confidence_override = .modeled;
            return switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        }
        if (self.foreign_objects.dispatch(self, name)) |resolution| {
            self.resolving_import_route = .foreign_object;
            self.import_confidence_override = .modeled;
            return switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        }
        if (self.pthreads.dispatchCppSynchronization(self, name)) |resolution| {
            self.resolving_import_route = .pthread;
            self.import_provider_override = .pthread_runtime;
            self.import_confidence_override = .modeled;
            return switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        }
        if (import_resolution.dispatchContract(self, name)) |resolution| {
            self.resolving_import_route = .import_contract;
            return switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
                .failed => .{ .unsupported = 0 },
            };
        }

        if (self.libcxx_filesystem.dispatch(self, &self.fs_forwarder, name)) |resolution| {
            self.resolving_import_route = .libcxx_filesystem;
            self.import_provider_override = .libcpp_filesystem;
            self.import_confidence_override = .verified;
            return switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        }

        if (self.pthreads.dispatch(self, name)) |resolution| {
            self.resolving_import_route = .pthread;
            self.import_provider_override = .pthread_runtime;
            self.import_confidence_override = .modeled;
            return switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        }

        if (self.dynamic_forwarder.forward(self, imported.dylib, name)) |resolution| {
            self.resolving_import_route = .dynamic_library;
            self.import_provider_override = .dynamic_library;
            self.import_confidence_override = .verified;
            return switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        }

        if (contract.dispatchFromAllFamilies(name, self.regs.rdi)) |outcome| {
            self.resolving_import_route = .shared_contract;
            if (self.verbose_trace) {
                const c = contract.resolveFromAllFamilies(name);
                const tag = @tagName(outcome);
                machoCapturePrint("    [contract] {s} → {s}", .{ name, if (c) |cc| cc.name else "?" });
                switch (outcome) {
                    .handled => |val| machoCapturePrint(" ({s}) handled=0x{x}\n", .{ tag, val }),
                    .terminated => |code| machoCapturePrint(" ({s}) terminated={d}\n", .{ tag, code }),
                }
            }
            if (self.contract_verification) {
                if (contract.verify.verifyDispatch(name, outcome, self.regs.rdi)) {
                    return switch (outcome) {
                        .handled => |val| ImportHandlerResult{ .handled = val },
                        .terminated => |code| ImportHandlerResult{ .terminated = code },
                    };
                }
                if (contract.verify.resolveExpected(name, self.regs.rdi)) |expected| {
                    machoCapturePrint("    [contract] WARNING: {s} verification mismatch, using expected\n", .{name});
                    return switch (expected) {
                        .handled => |val| ImportHandlerResult{ .handled = val },
                        .terminated => |code| ImportHandlerResult{ .terminated = code },
                    };
                }
                machoCapturePrint("    [contract] WARNING: {s} verification mismatch, no expected fallback\n", .{name});
            }
            return switch (outcome) {
                .handled => |val| ImportHandlerResult{ .handled = val },
                .terminated => |code| ImportHandlerResult{ .terminated = code },
            };
        }

        if (std.mem.eql(u8, name, "_objc_getClass")) {
            const class_name = self.guestCString(self.regs.rdi, 1024) orelse return .{ .unsupported = 0 };
            const handle = self.compat.classNamed(class_name);
            self.registerOpaqueHandle(handle, "objc class identity");
            machoCapturePrint("    [objc] class {s} -> 0x{x}\n", .{ class_name, handle });
            return .{ .handled = handle };
        }
        if (std.mem.eql(u8, name, "_sel_registerName")) {
            const selector_name = self.guestCString(self.regs.rdi, 1024) orelse return .{ .unsupported = 0 };
            const handle = self.compat.selectorNamed(selector_name);
            self.registerOpaqueHandle(handle, "Objective-C selector identity");
            machoCapturePrint("    [objc] selector {s} -> 0x{x}\n", .{ selector_name, handle });
            return .{ .handled = handle };
        }
        if (std.mem.eql(u8, name, "_objc_msgSend")) {
            const selector_name = self.compat.selectorName(self.regs.rsi);
            const class_name = self.compat.className(self.regs.rdi);
            if (self.native_window.handleObjcMessage(
                class_name,
                self.regs.rdi,
                selector_name,
                self.regs.rdx,
            )) |native_result| {
                if (native_result.value >= 0xFFFF_0000_0000_0000) {
                    self.registerNativeWindowHandles();
                }
                machoCapturePrint(
                    "    [objc/native] msgSend receiver=0x{x} class={s} selector={s} argument=0x{x} -> 0x{x} action={s}\n",
                    .{ self.regs.rdi, class_name, selector_name, self.regs.rdx, native_result.value, native_result.action },
                );
                return .{ .handled = native_result.value };
            }
            const result = self.compat.sendMessage(self.regs.rdi, self.regs.rsi);
            if (result.value >= 0xFFFF_0000_0000_0000) self.registerOpaqueHandle(result.value, "Objective-C object identity");
            machoCapturePrint(
                "    [objc] msgSend receiver=0x{x} selector={s} -> 0x{x} modeled={}\n",
                .{ self.regs.rdi, result.selector_name, result.value, result.modeled },
            );
            return if (result.modeled) .{ .handled = result.value } else .{ .unsupported = result.value };
        }

        if (std.mem.eql(u8, name, "_objc_autoreleasePoolPush")) {
            const handle = self.compat.currentThreadHandle();
            self.registerOpaqueHandle(handle, "Objective-C autorelease pool identity");
            return .{ .handled = handle };
        }
        if (std.mem.eql(u8, name, "___assert_rtn")) {
            self.guest_assertion_count += 1;
            const function_name = self.guestCString(self.regs.rdi, 1024) orelse "<unknown>";
            const file_name = self.guestCString(self.regs.rsi, 4096) orelse "<unknown>";
            const expression = self.guestCString(self.regs.rcx, 4096) orelse "<unknown>";
            const return_address = if (self.guestMemoryConst(self.regs.rsp, 8) != null) self.read64(self.regs.rsp) else 0;
            const caller = if (return_address != 0) self.metadata.nearestSymbol(return_address) else null;
            const assertion_class = classifyGuestAssertion(file_name, function_name, expression);
            self.last_guest_assertion_class = assertion_class;
            self.last_guest_assertion_step = self.executed_steps;
            self.last_guest_assertion_return = return_address;
            const backend_binding = x64_backend_diagnostics.Engine.classifyAssertion(file_name, self.regs.rdx, function_name);
            self.backend_diagnostics.noteAssertion(backend_binding, self.executed_steps, return_address);
            const assertion_symbol = if (caller) |symbol| return_address -| symbol.offset else return_address;
            const assertion_variant = (self.regs.rdx << 8) | @intFromEnum(assertion_class);
            const assertion_observation = self.diagnostic_throttler.observe(
                .guest_assertion,
                assertion_symbol,
                assertion_variant,
            );
            if (assertion_observation.disposition == .checkpoint) {
                machoCapturePrint(
                    "macho-processor: repeated guest assertion checkpoint: symbol={s} occurrence={d} suppressed_since_previous={d} total_assertions={d}\n",
                    .{ if (caller) |symbol| symbol.name else function_name, assertion_observation.occurrence, assertion_observation.suppressed_since_emit, self.guest_assertion_count },
                );
            } else if (assertion_observation.disposition == .detail) {
                machoCapturePrint(
                    "macho-processor: guest assertion #{d}: {s}:{d} {s}: {s}\n",
                    .{ self.guest_assertion_count, file_name, self.regs.rdx, function_name, expression },
                );
                machoCapturePrint(
                    "  assertion context: step={d} phase={s} active=0x{x} return=0x{x} caller={s}+0x{x} rsp=0x{x} rbp=0x{x}\n",
                    .{ self.executed_steps, @tagName(self.startup.phase), self.active_guest_thread, return_address, if (caller) |symbol| symbol.name else "<unknown>", if (caller) |symbol| symbol.offset else 0, self.regs.rsp, self.regs.rbp },
                );
                if (backend_binding != .none) {
                    machoCapturePrint(
                        "  x64 backend assertion binding: kind={s} backend_phase={s}\n",
                        .{ @tagName(backend_binding), @tagName(self.backend_diagnostics.phase) },
                    );
                    if (backend_binding == .x64_backend_capstone) {
                        machoCapturePrint(
                            "  x64 backend assertion cause: source line 139 is the failure branch of cs_open(CS_ARCH_X86, CS_MODE_64, &capstone_handle_); this indicates Capstone initialization failure inside an existing X64Backend constructor, not absence of the backend object\n",
                            .{},
                        );
                        machoCapturePrint(
                            "  x64 backend assertion impact: Capstone-backed disassembly/introspection is unreliable until proven otherwise; subsequent backend/code-cache/processor success events will be logged as independent readiness evidence\n",
                            .{},
                        );
                        self.dumpCapstoneCallbackState("cs_open assertion");
                    } else if (backend_binding == .x64_backend_low32_thunk) {
                        const mapping = self.backend_diagnostics.last_mapping;
                        machoCapturePrint(
                            "  x64 backend assertion cause: source line 438 requires resolve_function_thunk_ to fit in uint32_t because every indirection-table entry stores a 32-bit host-code pointer; the generated code cache was placed above the low 4 GiB window\n",
                            .{},
                        );
                        machoCapturePrint(
                            "  x64 backend assertion impact: continuing would truncate the thunk address and seed every default indirection with an invalid target; backend executable mappings must be rejected unless their end is at or below 0x100000000\n",
                            .{},
                        );
                        machoCapturePrint(
                            "  x64 backend low-address correlation: latest_mmap(valid/succeeded)={}/{} requested_address=0x{x} length={d} result=0x{x} result_high32=0x{x} stage={s}\n",
                            .{ mapping.valid, mapping.succeeded, mapping.address, mapping.length, mapping.result, mapping.result >> 32, if (mapping.stage.len != 0) mapping.stage else "<pending>" },
                        );
                    }
                    self.dumpGuestStack();
                }
                if (assertion_class == .timer_queue_wait_item_state) {
                    machoCapturePrint(
                        "  timer queue assertion cause: TimerThreadMain expected WaitItem::State::kDisarmed before its compiler-emitted UD2; this is the primary invariant failure, and a following Processor::OnThreadBreakpointHit assertion is secondary signal-handler fallout\n",
                        .{},
                    );
                    machoCapturePrint(
                        "  timer queue assertion context: cooperative active_thread=0x{x} deferred_threads={d} suspended_threads={d} pending_idle={d}; inspect wait-item arm/disarm transitions before treating the breakpoint handler as the root cause\n",
                        .{ self.active_guest_thread, self.pthreads.deferred_threads, self.suspended_guest_thread_count, gtkIdleQueueSnapshotFor(&self.gtk_idle_callbacks).pending },
                    );
                    if (guest_assertion_recovery.timerQueueSnapshot(self, self.regs.rbp)) |snapshot| {
                        machoCapturePrint(
                            "  timer queue state snapshot: frame_state[{s}]={d} at 0x{x} shared_ptr_slot=0x{x} wait_item=0x{x} object_state={s} due_ns={?d} interval_ns={?d}\n",
                            .{ timerQueueStateName(snapshot.frame_state), snapshot.frame_state, snapshot.frame_state_address, snapshot.shared_ptr_address, snapshot.wait_item, if (snapshot.object_state) |state| timerQueueStateName(state) else "<unmapped>", snapshot.due_nanoseconds, snapshot.interval_nanoseconds },
                        );
                        if (snapshot.object_state) |object_state| {
                            if (object_state != snapshot.frame_state) {
                                machoCapturePrint(
                                    "  timer queue state divergence: compare_exchange expected-output={s}({d}) but live wait_item state={s}({d}); this distinguishes decoder/CAS corruption from a genuinely concurrent state transition\n",
                                    .{ timerQueueStateName(snapshot.frame_state), snapshot.frame_state, timerQueueStateName(object_state), object_state },
                                );
                            }
                        }
                        if (snapshot.wait_item != 0) {
                            self.timer_queue_watch.active = true;
                            self.timer_queue_watch.wait_item_addr = snapshot.wait_item;
                            self.timer_queue_watch.state_addr = snapshot.wait_item + 0x50;
                            self.timer_queue_watch.thread = self.active_guest_thread;
                            self.timer_queue_watch.logged_writes = 0;
                            machoCapturePrint(
                                "  timer queue state watch activated: watching addr=0x{x} (wait_item+0x50) for next 32 writes on any thread\n",
                                .{snapshot.wait_item + 0x50},
                            );
                        }
                    } else {
                        machoCapturePrint(
                            "  timer queue state snapshot unavailable: rbp=0x{x}; retaining the assertion as non-recoverable because the modeled CAS state cannot be proven\n",
                            .{self.regs.rbp},
                        );
                    }
                } else if (assertion_class == .breakpoint_untracked_thread) {
                    machoCapturePrint(
                        "  breakpoint assertion cause: Processor::OnThreadBreakpointHit could not find the current modeled thread in Xenia's thread_debug_infos_ map; the backend exists, but this SIGILL arrived on a Rosette-cooperatively scheduled thread that Xenia's debugger registry does not track\n",
                        .{},
                    );
                    machoCapturePrint(
                        "  breakpoint assertion impact: this is a secondary failure while handling an earlier UD2. Any subsequent __Unwind_Resume(nullptr) belongs to the failed breakpoint-handler cleanup path and must not be mistaken for the original application fault\n",
                        .{},
                    );
                } else if (assertion_class == .export_ordinal_bounds) {
                    machoCapturePrint(
                        "  export ordinal bounds assertion: an export_entry->ordinal >= export_table.size(); the ordinal value exceeds the registered export count\n",
                        .{},
                    );
                    const saved = [_]u64{ self.regs.rbx, self.regs.r12, self.regs.r13, self.regs.r14, self.regs.r15 };
                    var found_pair = false;
                    for (saved) |a| {
                        if (a > 65535) continue;
                        for (saved) |b| {
                            if (b > 65535 or b < a) continue;
                            const ordinal = @as(u32, @intCast(a));
                            const size = @as(u32, @intCast(b));
                            if (ordinal < size) continue;
                            found_pair = true;
                            const recovery = self.export_table_mgr.diagnoseExportOrdinalBounds(ordinal, size, 0);
                            _ = self.export_table_lc.recordOrdinalBounds("xbdm", ordinal, size);
                            self.export_registry.register(ordinal, function_name, 0, true);
                            if (ordinal < 256 or (size < 256 and ordinal - size <= 16)) {
                                machoCapturePrint(
                                    "  export ordinal bounds ROOT CAUSE: ordinal={d} >= table_size={d}; values are small and consistent — this is a guest-side export table sizing issue (the export table needs more entries or the ordinal needs updating)\n",
                                    .{ ordinal, size },
                                );
                                if (recovery == .table_was_resized) {
                                    machoCapturePrint(
                                        "  export table sizing recovery: export table manager recorded ordinal={d} size={d}; future assertions for this table will be tracked\n",
                                        .{ ordinal, size },
                                    );
                                }
                                if (self.export_table_lc.module_count > 0 and
                                    self.export_table_lc.modules[0].class == .deferred_exports)
                                {
                                    const var_name = export_table_lifecycle.Lifecycle.extractVectorName(expression);
                                    if (var_name) |vname| {
                                        const sym_addr = self.metadata.definedSymbolAddress(vname);
                                        if (sym_addr) |addr| {
                                            machoCapturePrint(
                                                "  export table pre-population: found vector={s} at 0x{x}; scheduling growth to size {d}\n",
                                                .{ vname, addr, ordinal + 1 },
                                            );
                                            _ = self.export_table_lc.requestVectorGrowth(addr, ordinal + 1, 8, vname);
                                        } else {
                                            var sym_buf: [1]u64 = undefined;
                                            const found = self.metadata.symbolAddressesMatching("", vname, &sym_buf);
                                            if (found > 0 and sym_buf[0] != 0) {
                                                _ = self.export_table_lc.requestVectorGrowth(sym_buf[0], ordinal + 1, 8, vname);
                                                machoCapturePrint(
                                                    "  export table pre-population: found vector={s} at 0x{x} via substring match; scheduling growth to size {d}\n",
                                                    .{ vname, sym_buf[0], ordinal + 1 },
                                                );
                                            } else {
                                                machoCapturePrint(
                                                    "  export table pre-population: vector={s} not found in symbol table; will fall back to defer+retry\n",
                                                    .{vname},
                                                );
                                            }
                                        }
                                    }
                                }
                            } else {
                                machoCapturePrint(
                                    "  export ordinal bounds ROOT CAUSE: ordinal={d} >= table_size={d}; values are large or unexpected — this is likely emulator-level memory corruption or a data-structure initialization failure\n",
                                    .{ ordinal, size },
                                );
                            }
                        }
                    }
                    if (!found_pair) {
                        _ = self.export_table_mgr.recordTable(0, 0, 0);
                        machoCapturePrint(
                            "  export ordinal bounds: no plausible ordinal/size pair found in callee-saved registers (rbx/r12-r15); the values were either computed per-call and not preserved, or the register state was already clobbered\n",
                            .{},
                        );
                        machoCapturePrint(
                            "  export ordinal bounds raw register state: rbx=0x{x} r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x}\n",
                            .{ self.regs.rbx, self.regs.r12, self.regs.r13, self.regs.r14, self.regs.r15 },
                        );
                    }
                }
            }
            if (self.initializer_resolver.current()) |initializer| {
                machoCapturePrint(
                    "  assertion owner: initializer [{d}/{d}] {s}\n",
                    .{ initializer.index + 1, self.metadata.initializer_addresses.len, initializer.symbol },
                );
                self.initializer_abort_requested = true;
                if (self.initializer_abort_reason == .none) self.initializer_abort_reason = .assertion;
            }
            return .{ .handled = 0 };
        }

        if (std.mem.eql(u8, name, "_strcmp")) {
            const lhs = self.guestCString(self.regs.rdi, 1 << 20) orelse return .{ .unsupported = 0 };
            const rhs = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const ordering = std.mem.order(u8, lhs, rhs);
            const result: i32 = switch (ordering) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            };
            return .{ .handled = @as(u32, @bitCast(result)) };
        }
        if (std.mem.eql(u8, name, "_strcasecmp")) {
            const lhs = self.guestCString(self.regs.rdi, 1 << 20) orelse return .{ .unsupported = 0 };
            const rhs = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const shared = @min(lhs.len, rhs.len);
            for (0..shared) |index| {
                const left = std.ascii.toLower(lhs[index]);
                const right = std.ascii.toLower(rhs[index]);
                if (left != right) {
                    const result: i32 = if (left < right) -1 else 1;
                    return .{ .handled = @as(u32, @bitCast(result)) };
                }
            }
            const result: i32 = if (lhs.len < rhs.len) -1 else if (lhs.len > rhs.len) 1 else 0;
            return .{ .handled = @as(u32, @bitCast(result)) };
        }
        if (std.mem.eql(u8, name, "_strcpy")) {
            const source = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const destination = self.guestMemory(self.regs.rdi, source.len + 1) orelse return .{ .unsupported = 0 };
            @memcpy(destination[0..source.len], source);
            destination[source.len] = 0;
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.eql(u8, name, "_strtoul")) {
            self.resolving_import_route = .strtoul;
            const nptr = self.guestCString(self.regs.rdi, 1 << 20) orelse return .{ .handled = 0 };
            const endptr_ptr = self.regs.rsi;
            const base_raw = self.regs.rdx;
            if (base_raw > 36) {
                if (endptr_ptr != 0) self.write64(endptr_ptr, self.regs.rdi);
                return .{ .handled = 0 };
            }
            const base: u8 = @intCast(base_raw);
            var i: usize = 0;
            while (i < nptr.len and switch (nptr[i]) {
                ' ', '\t', '\n', '\r', '\x0c' => true,
                else => false,
            }) i += 1;
            var negate = false;
            if (i < nptr.len) {
                if (nptr[i] == '-') {
                    negate = true;
                    i += 1;
                } else if (nptr[i] == '+') i += 1;
            }
            var effective_base: u8 = base;
            if (effective_base == 0 or effective_base == 16) {
                if (i + 2 < nptr.len and nptr[i] == '0' and (nptr[i + 1] | 32) == 'x') {
                    effective_base = 16;
                    i += 2;
                }
            }
            if (effective_base == 0 and i < nptr.len and nptr[i] == '0') effective_base = 8;
            if (effective_base == 0) effective_base = 10;
            const start = i;
            var result: u64 = 0;
            var overflow = false;
            while (i < nptr.len) {
                const c = nptr[i];
                const digit: u64 = switch (c) {
                    '0'...'9' => c - '0',
                    'a'...'z' => c - 'a' + 10,
                    'A'...'Z' => c - 'A' + 10,
                    else => break,
                };
                if (digit >= effective_base) break;
                const next = result * effective_base;
                overflow = overflow or (effective_base > 0 and next / effective_base != result);
                result = next;
                const next2 = result +% digit;
                overflow = overflow or next2 < result;
                result = next2;
                i += 1;
            }
            if (i == start) {
                if (endptr_ptr != 0) self.write64(endptr_ptr, 0);
                return .{ .handled = 0 };
            }
            if (endptr_ptr != 0) self.write64(endptr_ptr, self.regs.rdi + i);
            if (overflow) return .{ .handled = std.math.maxInt(u64) };
            if (negate) return .{ .handled = @bitCast(@as(i64, -@as(i64, @bitCast(result)))) };
            return .{ .handled = result };
        }
        if (std.mem.eql(u8, name, "_getenv")) {
            const key = self.guestCString(self.regs.rdi, 256) orelse return .{ .handled = 0 };
            const raw = if (std.mem.eql(u8, key, "HOME"))
                std.c.getenv("HOME")
            else if (std.mem.eql(u8, key, "XDG_DATA_HOME"))
                std.c.getenv("XDG_DATA_HOME")
            else if (std.mem.eql(u8, key, "TMPDIR"))
                std.c.getenv("TMPDIR")
            else if (std.mem.eql(u8, key, "USER"))
                std.c.getenv("USER")
            else if (std.mem.eql(u8, key, "PATH"))
                std.c.getenv("PATH")
            else
                null;
            const host_value = raw orelse return .{ .handled = 0 };
            const value = std.mem.sliceTo(host_value, 0);
            const allocation = self.guestAlloc(value.len + 1, 1) orelse return .{ .handled = 0 };
            if (!self.guestWriteCString(allocation, value)) return .{ .handled = 0 };
            return .{ .handled = allocation };
        }
        if (std.mem.eql(u8, name, "_getpwuid_r")) {
            if (self.regs.r8 != 0) self.write64(self.regs.r8, 0);
            return .{ .handled = 2 };
        }
        if (std.mem.eql(u8, name, "___error")) {
            if (self.guest_errno_address == 0) {
                self.guest_errno_address = self.guestAlloc(@sizeOf(c_int), @alignOf(c_int)) orelse return .{ .unsupported = 0 };
            }
            return .{ .handled = self.guest_errno_address };
        }

        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6__initEPKcm") != null) {
            const ok = compat_runtime.initLibcppString(self, self.regs.rdi, self.regs.rsi, self.regs.rdx);
            if (self.verbose_trace) machoCapturePrint(
                "    [libc++] basic_string::__init(this=0x{x}, source=0x{x}, length={d}) -> {}\n",
                .{ self.regs.rdi, self.regs.rsi, self.regs.rdx, ok },
            );
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6assignEPKc") != null) {
            const source = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const ok = compat_runtime.initLibcppString(self, self.regs.rdi, self.regs.rsi, source.len);
            if (self.verbose_trace) machoCapturePrint(
                "    [libc++] basic_string::assign(this=0x{x}, source=0x{x}, length={d}) -> {}\n",
                .{ self.regs.rdi, self.regs.rsi, source.len, ok },
            );
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6resizeEmc") != null) {
            const ok = compat_runtime.resizeLibcppString(self, self.regs.rdi, self.regs.rsi, @truncate(self.regs.rdx));
            return if (ok) .handled_void else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEaSEc") != null) {
            const value = [_]u8{@truncate(self.regs.rsi)};
            const ok = compat_runtime.initLibcppStringLiteral(self, self.regs.rdi, &value);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6appendEPKcm") != null) {
            const ok = compat_runtime.appendLibcppString(self, self.regs.rdi, self.regs.rsi, self.regs.rdx);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6appendEPKc") != null) {
            const source = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const ok = compat_runtime.appendLibcppString(self, self.regs.rdi, self.regs.rsi, source.len);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6insertEmPKc") != null) {
            const source = self.guestCString(self.regs.rdx, 1 << 20) orelse return .{ .unsupported = 0 };
            const ok = compat_runtime.insertLibcppString(self, self.regs.rdi, self.regs.rsi, self.regs.rdx, source.len);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE9__grow_byEmmmmmm") != null) {
            const inserted_size = self.read64(self.regs.rsp + 8);
            const ok = compat_runtime.growLibcppString(
                self,
                self.regs.rdi,
                self.regs.rsi,
                self.regs.rdx,
                self.regs.rcx,
                self.regs.r8,
                self.regs.r9,
                inserted_size,
            );
            return if (ok) .{ .handled = 0 } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEC1ERKS5_") != null or
            std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEC2ERKS5_") != null)
        {
            const ok = compat_runtime.copyLibcppString(self, self.regs.rdi, self.regs.rsi);
            if (!ok) {
                machoCapturePrint(
                    "macho-processor: libc++ string copy rejected: destination=0x{x} source=0x{x} destination_mapped={} source_mapped={}\n",
                    .{ self.regs.rdi, self.regs.rsi, self.guestMemoryConst(self.regs.rdi, 24) != null, self.guestMemoryConst(self.regs.rsi, 24) != null },
                );
            }
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEaSERKS5_") != null) {
            const ok = compat_runtime.copyLibcppString(self, self.regs.rdi, self.regs.rsi);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "__ZNSt3__1plIcNS_11char_traitsIcEENS_9allocatorIcEEEENS_12basic_stringIT_T0_T1_EEPKS6_RKS9_") != null) {
            const left = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const ok = compat_runtime.concatCStringAndLibcppString(self, self.regs.rdi, self.regs.rsi, left.len, self.regs.rdx);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEED1Ev") != null or
            std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEED2Ev") != null)
        {
            const ok = compat_runtime.destroyLibcppString(self, self.regs.rdi);
            return if (ok) .{ .handled = 0 } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE4findEcm") != null) {
            const string = compat_runtime.libcppStringView(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
            const bytes = self.guestMemoryConst(string.address, string.length) orelse return .{ .unsupported = 0 };
            const start: usize = @intCast(@min(self.regs.rdx, string.length));
            const needle: u8 = @truncate(self.regs.rsi);
            const found = std.mem.indexOfScalarPos(u8, bytes, start, needle) orelse return .{ .handled = std.math.maxInt(u64) };
            return .{ .handled = found };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE7compareEPKc")) {
            const rhs = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const result = compat_runtime.compareLibcppStringWithBytes(self, self.regs.rdi, self.regs.rsi, rhs.len) orelse
                return .{ .unsupported = 0 };
            if (self.verbose_trace) {
                machoCapturePrint(
                    "    [libc++] basic_string::compare(this=0x{x}, rhs=0x{x}, rhs_length={d}) -> {d}\n",
                    .{ self.regs.rdi, self.regs.rsi, rhs.len, result },
                );
            }
            return .{ .handled = @as(u32, @bitCast(result)) };
        }

        if (std.mem.eql(u8, name, "___cxa_guard_acquire")) {
            const result = compat_runtime.cxaGuardAcquire(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
            // Track the guard address so we can clear it on initializer deferral
            self.guard_rollback.track(self.regs.rdi);
            return .{ .handled = result };
        }
        if (std.mem.eql(u8, name, "___cxa_guard_release")) {
            return if (compat_runtime.cxaGuardRelease(self, self.regs.rdi)) .{ .handled = 0 } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "___cxa_guard_abort")) {
            return if (compat_runtime.cxaGuardAbort(self, self.regs.rdi)) .{ .handled = 0 } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "___cxa_atexit")) {
            const registered = self.compat.registerAtexit(self.regs.rdi, self.regs.rsi, self.regs.rdx);
            if (self.verbose_trace) machoCapturePrint(
                "    [c++] __cxa_atexit(function=0x{x}, argument=0x{x}, dso=0x{x}) -> {}\n",
                .{ self.regs.rdi, self.regs.rsi, self.regs.rdx, registered },
            );
            return .{ .handled = if (registered) 0 else 1 };
        }
        if (std.mem.eql(u8, name, "_atexit")) {
            const registered = self.compat.registerPlainAtexit(self.regs.rdi);
            if (self.verbose_trace) {
                machoCapturePrint(
                    "    [posix] atexit(function=0x{x}) -> {}\n",
                    .{ self.regs.rdi, registered },
                );
            }
            return .{ .handled = if (registered) 0 else 1 };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__112__next_primeEm")) {
            return .{ .handled = nextPrime(self.regs.rdi) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__18ios_base6xallocEv")) {
            const slot = self.ios_xalloc_next;
            self.ios_xalloc_next +%= 1;
            return .{ .handled = slot };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__16chrono12system_clock3nowEv")) {
            return .{ .handled = self.guest_time.wallNow() };
        }
        if (std.mem.indexOf(u8, name, "recursive_mutexC1Ev") != null or
            std.mem.indexOf(u8, name, "recursive_mutexC2Ev") != null)
        {
            if (self.guestMemory(self.regs.rdi, 64)) |storage| @memset(storage, 0);
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.indexOf(u8, name, "__thread_structC1Ev") != null or
            std.mem.indexOf(u8, name, "__thread_structC2Ev") != null)
        {
            if (self.guestMemory(self.regs.rdi, 64)) |storage| @memset(storage, 0);
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__14__fs10filesystem4path16__root_directoryEv")) {
            const path = compat_runtime.libcppStringView(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
            const bytes = self.guestMemoryConst(path.address, path.length) orelse return .{ .unsupported = 0 };
            self.regs.rdx = @intFromBool(bytes.len != 0 and bytes[0] == '/');
            return .{ .handled = path.address };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__14__fs10filesystem4path10__filenameEv")) {
            const path = compat_runtime.libcppStringView(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
            const bytes = self.guestMemoryConst(path.address, path.length) orelse return .{ .unsupported = 0 };
            const start = if (std.mem.lastIndexOfScalar(u8, bytes, '/')) |separator| separator + 1 else 0;
            self.regs.rdx = bytes.len - start;
            return .{ .handled = path.address + start };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__14__fs10filesystem4path13__parent_pathEv")) {
            const path = compat_runtime.libcppStringView(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
            const bytes = self.guestMemoryConst(path.address, path.length) orelse return .{ .unsupported = 0 };
            var end = bytes.len;
            while (end > 1 and bytes[end - 1] == '/') end -= 1;
            const parent_length = if (std.mem.lastIndexOfScalar(u8, bytes[0..end], '/')) |separator|
                if (separator == 0) @as(usize, 1) else separator
            else
                0;
            self.regs.rdx = parent_length;
            return .{ .handled = path.address };
        }

        if (std.mem.eql(u8, name, "___dynamic_cast")) {
            if (self.dynamic_casts.resolve(
                self,
                self.regs.rdi,
                self.regs.rsi,
                self.regs.rdx,
                self.regs.rcx,
            )) |resolution| {
                return .{ .handled = resolution.address };
            }
            const return_address = self.read64(self.regs.rsp);
            if (self.metadata.nearestSymbol(return_address)) |caller| {
                if (std.mem.indexOf(u8, caller.name, "cxxopts") != null and
                    std.mem.indexOf(u8, caller.name, "OptionValue2as") != null)
                {
                    return .{ .handled = self.regs.rdi };
                }
            }
            self.dynamic_casts.dumpTraceBuffer(self);
            machoCapturePrint(
                "macho-processor: __dynamic_cast metadata unresolved: source=0x{x} source_type=0x{x} destination_type=0x{x} hint={d}; returning null\n",
                .{ self.regs.rdi, self.regs.rsi, self.regs.rdx, @as(i64, @bitCast(self.regs.rcx)) },
            );
            return .{ .handled = 0 };
        }

        if (std.mem.eql(u8, name, "__ZNSt3__16localeC1Ev") or std.mem.eql(u8, name, "__ZNSt3__16localeC2Ev")) {
            const ok = self.compat.initLocale(self, self.regs.rdi, null);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__16localeC1ERKS0_") or std.mem.eql(u8, name, "__ZNSt3__16localeC2ERKS0_")) {
            const ok = self.compat.initLocale(self, self.regs.rdi, self.regs.rsi);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__16localeD1Ev") or std.mem.eql(u8, name, "__ZNSt3__16localeD2Ev")) {
            return if (self.compat.destroyLocale(self, self.regs.rdi)) .{ .handled = 0 } else .{ .unsupported = 0 };
        }
        // XModule constructors may resolve through unresolved imports during XEX
        // import table loading.  Write the vtable into the object so virtual
        // dispatch (XModule::Matches etc) works.  If the real vtable wasn't
        // found at init time, create a synthetic one using synthetic thunks.
        if (std.mem.indexOf(u8, name, "7XModuleC1") != null or
            std.mem.indexOf(u8, name, "7XModuleC2") != null)
        {
            const xmodule_vtable = self.ensureXmoduleVtable() orelse 0;
            if (xmodule_vtable != 0) {
                self.write64(self.regs.rdi, xmodule_vtable);
            }
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__16locale9use_facetERNS0_2idE")) {
            const return_address = self.read64(self.regs.rsp);
            const caller_name = if (self.metadata.nearestSymbol(return_address)) |caller| caller.name else "";
            const kind: compat_runtime.LocaleFacetKind = if (std.mem.indexOf(u8, caller_name, "ctype") != null)
                .ctype
            else if (std.mem.indexOf(u8, caller_name, "collate") != null)
                .collate
            else
                .generic;
            const key = self.regs.rsi ^ (@as(u64, @intFromEnum(kind)) << 56);
            const facet = self.compat.localeFacet(self, key, kind) orelse return .{ .unsupported = 0 };
            return .{ .handled = facet };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__16locale4nameEv")) {
            const ok = compat_runtime.initLibcppStringLiteral(self, self.regs.rdi, "C");
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__115__get_classnameEPKcb")) {
            const class_name = self.guestCString(self.regs.rdi, 64) orelse return .{ .unsupported = 0 };
            const mask = compat_runtime.libcppRegexClassMask(class_name, self.regs.rsi != 0);
            return .{ .handled = mask };
        }
        if (std.mem.eql(u8, name, "___cxa_allocate_exception")) {
            const object_size = self.regs.rdi;
            const allocation = self.memory_forwarder.allocate(self, object_size +| 64, 16) orelse return .{ .unsupported = 0 };
            const object_address = allocation + 64;
            self.cxx_exceptions.recordAllocation(allocation, object_address, object_size, self.read64(self.regs.rsp));
            return .{ .handled = object_address };
        }
        if (std.mem.eql(u8, name, "___cxa_begin_catch")) {
            const object_address = self.cxx_exceptions.beginCatch(self.regs.rdi);
            machoCapturePrint("macho-processor: __cxa_begin_catch object=0x{x}\n", .{object_address});
            return .{ .handled = object_address };
        }
        if (std.mem.eql(u8, name, "___cxa_end_catch")) {
            const object_address = self.cxx_exceptions.endCatch();
            if (object_address) |object| {
                machoCapturePrint("macho-processor: __cxa_end_catch object=0x{x}\n", .{object});
                if (self.unwinder.completeCatch()) {
                    machoCapturePrint(
                        "macho-processor: Itanium catch transaction completed: object=0x{x}; phase-two checkpoint retired\n",
                        .{object},
                    );
                }
                const spirv_resolution = self.spirv_cross.noteCatch(object);
                if (spirv_resolution == .expected_dummy_probe_caught) {
                    machoCapturePrint(
                        "macho-processor: SPIRV-Cross dummy-module probe resolved: object=0x{x} entry_point_expected=false handler_completed=true; this exception is verified startup history, not a hang cause\n",
                        .{object},
                    );
                }
            }
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "___cxa_get_exception_ptr")) {
            return .{ .handled = self.cxx_exceptions.exceptionPointer(self.regs.rdi) };
        }
        if (std.mem.eql(u8, name, "___cxa_free_exception")) {
            if (self.cxx_exceptions.freeException(self.regs.rdi)) |allocation| {
                self.memory_forwarder.release(allocation.storage_address);
                self.vtable_tracker.forgetAddress(allocation.storage_address);
            }
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "__ZNSt20bad_array_new_lengthC1Ev")) {
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.eql(u8, name, "___cxa_throw")) {
            const thrown = self.cxx_exceptions.recordThrow(
                self.regs.rdi,
                self.regs.rsi,
                self.regs.rdx,
                self.read64(self.regs.rsp),
            );
            machoCapturePrint(
                "macho-processor: guest raised C++ exception object=0x{x} type_info=0x{x} destructor=0x{x}\n",
                .{ self.regs.rdi, self.regs.rsi, self.regs.rdx },
            );
            var toml_parse_error = false;
            var exception_type_name: []const u8 = "";
            var exception_message: []const u8 = "";
            if (self.cxxExceptionTypeName(thrown.type_info_address)) |type_name| {
                exception_type_name = type_name;
                machoCapturePrint("macho-processor: C++ exception ABI type name: {s}\n", .{type_name});
                if (std.mem.indexOf(u8, type_name, "toml") != null and
                    std.mem.indexOf(u8, type_name, "parse_error") != null)
                {
                    toml_parse_error = true;
                }
            }
            if (self.metadata.nearestSymbol(thrown.type_info_address)) |symbol| {
                machoCapturePrint("macho-processor: C++ exception type: {s}+0x{x}\n", .{ symbol.name, symbol.offset });
            }
            if (self.metadata.nearestSymbol(thrown.destructor_address)) |symbol| {
                machoCapturePrint("macho-processor: C++ exception destructor: {s}+0x{x}\n", .{ symbol.name, symbol.offset });
            }
            if (self.diagnosticSymbol(thrown.caller_address)) |throw_site| {
                machoCapturePrint("macho-processor: C++ exception throw site: {s}+0x{x} (0x{x})\n", .{
                    throw_site.symbol,
                    throw_site.symbol_offset,
                    throw_site.address,
                });
            }
            if (thrown.allocation) |allocation| {
                if (self.diagnosticSymbol(allocation.caller_address)) |allocation_site| {
                    machoCapturePrint("macho-processor: C++ exception allocation site: {s}+0x{x} (size={d})\n", .{
                        allocation_site.symbol,
                        allocation_site.symbol_offset,
                        allocation.object_size,
                    });
                }
            }
            if (self.cxxExceptionMessage(thrown.object_address)) |message| {
                exception_message = message;
                machoCapturePrint("macho-processor: C++ exception message: {s}\n", .{message});
                if (std.mem.indexOf(u8, message, "invalid utf-8") != null or
                    std.mem.indexOf(u8, message, "invalid UTF-8") != null or
                    std.mem.indexOf(u8, message, "utf-8") != null)
                {
                    toml_parse_error = true;
                }
            }
            if (toml_parse_error) {
                self.libcxx_streams.dumpPatchTomlDiagnostics("toml parse_error throw");
            }
            var inspection = self.unwinder.inspectThrow(self, thrown.type_info_address);
            const exception_header = if (thrown.allocation) |allocation|
                allocation.storage_address
            else
                thrown.object_address;
            const phase_two_installed = self.unwinder.installPhaseTwo(self, &inspection, exception_header);
            const spirv_classification = self.spirv_cross.noteThrow(thrown.object_address, .{
                .type_name = exception_type_name,
                .message = exception_message,
                .verification_frame_seen = spirv_cross_diagnostics.verificationFrameSeen(&self.metadata, inspection),
                .handler_found = inspection.handler != null,
                .phase_two_installed = phase_two_installed,
                .catch_completed = false,
            });
            if (spirv_classification == .expected_dummy_probe_unwinding) {
                machoCapturePrint(
                    "macho-processor: SPIRV-Cross dummy-module probe recognized: object=0x{x} missing_entry_point=true verification_frame=true handler=0x{x} phase_two_installed=true; awaiting expected catch completion\n",
                    .{ thrown.object_address, if (inspection.handler) |handler| handler.landing_pad else 0 },
                );
            }
            if (phase_two_installed) {
                self.last_unwind_inspection = inspection;
                return .control_transferred;
            }
            self.last_unwind_inspection = inspection;
            if (inspection.handler != null) {
                machoCapturePrint("macho-processor: stopping after verified phase-1 catch discovery because this frame layout is not phase-2 safe\n", .{});
            } else {
                machoCapturePrint("macho-processor: stopping after Itanium phase-1 found no matching catch handler\n", .{});
            }
            self.dumpGuestStack();
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        }
        if (std.mem.eql(u8, name, "__Unwind_Resume") or std.mem.eql(u8, name, "__Unwind_Resume_or_Rethrow")) {
            if (self.unwinder.resumePhaseTwo(self)) return .control_transferred;
            if (self.unwinder.exhaustedWithoutHandler()) {
                machoCapturePrint(
                    "macho-processor: Itanium phase-2 stopped after all verified cleanup pads; no matching LSDA catch exists for the guest exception\n",
                    .{},
                );
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
                return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
            }
            if (self.recoverOrphanedPhaseTwoResume(name)) return .control_transferred;
            if (self.regs.rdi != 0 or self.cxx_exceptions.activeThrow() != null) {
                const exception_header = if (self.regs.rdi != 0) self.regs.rdi else if (self.cxx_exceptions.activeThrow()) |thrown| if (thrown.allocation) |allocation| allocation.storage_address else thrown.object_address else 0;
                machoCapturePrint(
                    "macho-processor: Itanium host _Unwind_Resume fallback rejected: header=0x{x}; host addresses cannot be installed as guest RIP\n",
                    .{exception_header},
                );
            }
            if (self.regs.rdi == 0 and self.last_guest_assertion_class == .breakpoint_untracked_thread) {
                machoCapturePrint(
                    "macho-processor: breakpoint cleanup chain diagnosis: __Unwind_Resume received a null exception argument after Processor::OnThreadBreakpointHit asserted on an untracked modeled thread; no C++ throw object exists to resume, so exit 125 is secondary handler-cleanup termination\n",
                    .{},
                );
                machoCapturePrint(
                    "macho-processor: breakpoint cleanup chain origin: assertion_step={d} assertion_return=0x{x} active_thread=0x{x} signal_depth={d} deferred_threads={d} suspended_threads={d}\n",
                    .{ self.last_guest_assertion_step, self.last_guest_assertion_return, self.active_guest_thread, self.signal_frame_count, self.pthreads.deferred_threads, self.suspended_guest_thread_count },
                );
            }
            machoCapturePrint(
                "macho-processor: guest requested exception resume without a recoverable phase-2 cleanup chain: symbol={s} exception_arg=0x{x} rip=0x{x} rsp=0x{x} rbp=0x{x}\n",
                .{ name, self.regs.rdi, self.regs.rip, self.regs.rsp, self.regs.rbp },
            );
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        }
        if (std.mem.eql(u8, name, "___cxa_rethrow")) {
            const object_address = self.cxx_exceptions.recordRethrow() orelse self.regs.rdi;
            machoCapturePrint("macho-processor: guest rethrew exception object=0x{x}\n", .{object_address});
            const thrown = self.cxx_exceptions.last_throw orelse {
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
                return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
            };
            var inspection = self.unwinder.inspectThrow(self, thrown.type_info_address);
            const exception_header = if (thrown.allocation) |allocation| allocation.storage_address else object_address;
            if (self.unwinder.installPhaseTwo(self, &inspection, exception_header)) {
                self.last_unwind_inspection = inspection;
                return .control_transferred;
            }
            self.last_unwind_inspection = inspection;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        }

        if (std.mem.eql(u8, name, "__Znwm") or std.mem.eql(u8, name, "__Znam") or
            std.mem.eql(u8, name, "__ZnwmRKSt9nothrow_t") or
            std.mem.eql(u8, name, "__ZnwmSt11align_val_t") or
            std.mem.eql(u8, name, "__ZnamSt11align_val_t") or
            std.mem.endsWith(u8, name, "_malloc"))
        {
            self.resolving_import_route = .allocate;
            const alignment: u64 = if (std.mem.endsWith(u8, name, "St11align_val_t")) self.regs.rsi else 16;
            return .{ .handled = self.memory_forwarder.allocate(self, self.regs.rdi, alignment) orelse 0 };
        }
        if (std.mem.eql(u8, name, "__ZdlPv") or std.mem.eql(u8, name, "__ZdaPv") or
            std.mem.eql(u8, name, "__ZdlPvm") or std.mem.eql(u8, name, "__ZdaPvm") or
            std.mem.eql(u8, name, "__ZdlPvSt11align_val_t") or
            std.mem.eql(u8, name, "__ZdaPvSt11align_val_t") or
            std.mem.eql(u8, name, "__ZdlPvmSt11align_val_t") or
            std.mem.eql(u8, name, "__ZdaPvmSt11align_val_t") or
            std.mem.endsWith(u8, name, "_free"))
        {
            self.resolving_import_route = .release;
            self.memory_forwarder.release(self.regs.rdi);
            self.vtable_tracker.forgetAddress(self.regs.rdi);
            return .handled_void;
        }
        if (std.mem.endsWith(u8, name, "_realloc")) {
            self.resolving_import_route = .reallocate;
            return .{ .handled = self.memory_forwarder.reallocate(self, self.regs.rdi, self.regs.rsi) orelse 0 };
        }
        if (std.mem.eql(u8, name, "_posix_memalign")) {
            self.resolving_import_route = .posix_memalign;
            const output = self.regs.rdi;
            const alignment = self.regs.rsi;
            const size = self.regs.rdx;
            if (alignment < @sizeOf(u64) or !std.math.isPowerOfTwo(alignment)) {
                return .{ .handled = 22 };
            }
            if (self.guestMemory(output, @sizeOf(u64)) == null) return .{ .unsupported = 14 };
            const allocation = self.memory_forwarder.allocate(self, size, alignment) orelse return .{ .handled = 12 };
            self.write64(output, allocation);
            return .{ .handled = 0 };
        }
        if (std.mem.eql(u8, name, "_aligned_alloc")) {
            self.resolving_import_route = .aligned_alloc;
            const alignment = self.regs.rdi;
            if (!std.math.isPowerOfTwo(alignment) or self.regs.rsi % alignment != 0) return .{ .handled = 0 };
            return .{ .handled = self.memory_forwarder.allocate(self, self.regs.rsi, alignment) orelse 0 };
        }
        if (std.mem.endsWith(u8, name, "_calloc")) {
            self.resolving_import_route = .calloc;
            return .{ .handled = self.memory_forwarder.allocateZeroed(self, self.regs.rdi, self.regs.rsi) orelse 0 };
        }
        if (std.mem.eql(u8, name, "____chkstk_darwin")) {
            self.resolving_import_route = .chkstk;
            return .{ .handled = self.regs.rax };
        }

        if (std.mem.endsWith(u8, name, "_memset")) {
            const dst = self.regs.rdi;
            const value: u8 = @intCast(self.regs.rsi & 0xFF);
            const count = self.regs.rdx;
            if (count == 0) return .{ .handled = dst };
            const buf = self.guestMemory(dst, count) orelse {
                self.terminateForGuestAccess(dst, @intCast(@min(count, std.math.maxInt(u8))), .write, "_memset");
                return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
            };
            @memset(buf, value);
            if (self.verbose_trace) machoCapturePrint("    [import] _memset(dst=0x{x}, value=0x{x}, count={d})\n", .{ dst, value, count });
            return .{ .handled = dst };
        }
        if (std.mem.eql(u8, name, "___bzero")) {
            const dst = self.regs.rdi;
            const count = self.regs.rsi;
            if (count == 0) return .handled_void;
            const buf = self.guestMemory(dst, count) orelse {
                self.terminateForGuestAccess(dst, @intCast(@min(count, std.math.maxInt(u8))), .write, "___bzero");
                return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
            };
            @memset(buf, 0);
            if (self.verbose_trace) machoCapturePrint("    [import] _bzero(dst=0x{x}, count={d})\n", .{ dst, count });
            return .handled_void;
        }

        if (std.mem.endsWith(u8, name, "_memcpy") or std.mem.endsWith(u8, name, "_memmove")) {
            const dst = self.regs.rdi;
            const src = self.regs.rsi;
            const count = self.regs.rdx;
            if (count == 0) return .{ .handled = dst };
            const src_buf = self.guestMemoryConst(src, count) orelse {
                self.terminateForGuestAccess(src, @intCast(@min(count, std.math.maxInt(u8))), .read, name);
                return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
            };
            const dst_buf = self.guestMemory(dst, count) orelse {
                self.terminateForGuestAccess(dst, @intCast(@min(count, std.math.maxInt(u8))), .write, name);
                return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
            };
            std.mem.copyForwards(u8, dst_buf, src_buf);
            return .{ .handled = dst };
        }

        if (std.mem.endsWith(u8, name, "_memcmp")) {
            const lhs = self.guestMemoryConst(self.regs.rdi, self.regs.rdx) orelse return .{ .unsupported = 0 };
            const rhs = self.guestMemoryConst(self.regs.rsi, self.regs.rdx) orelse return .{ .unsupported = 0 };
            const cmp = std.mem.order(u8, lhs, rhs);
            return .{ .handled = switch (cmp) {
                .lt => @bitCast(@as(i64, -1)),
                .eq => 0,
                .gt => 1,
            } };
        }

        if (std.mem.endsWith(u8, name, "_strlen")) {
            const text = self.guestCString(self.regs.rdi, 1 << 20) orelse return .{ .unsupported = 0 };
            return .{ .handled = text.len };
        }

        if (std.mem.endsWith(u8, name, "_clock_getres")) {
            if (self.regs.rsi != 0) {
                if (self.guestMemory(self.regs.rsi, 16) == null) return .{ .unsupported = 14 };
                self.write64(self.regs.rsi, 0);
                self.write64(self.regs.rsi + 8, 1);
            }
            return .{ .handled = 0 };
        }

        if (std.mem.endsWith(u8, name, "_clock_gettime")) {
            if (self.guestMemory(self.regs.rsi, 16) == null) return .{ .unsupported = 14 };
            const now = self.guest_time.now();
            self.write64(self.regs.rsi, now / 1_000_000_000);
            self.write64(self.regs.rsi + 8, now % 1_000_000_000);
            return .{ .handled = 0 };
        }

        if (std.mem.endsWith(u8, name, "_gettimeofday")) {
            if (self.guestMemory(self.regs.rdi, 16) == null) return .{ .unsupported = 14 };
            const wall_now = self.guest_time.wallNow();
            self.write64(self.regs.rdi, wall_now / 1_000_000_000);
            self.write64(self.regs.rdi + 8, (wall_now % 1_000_000_000) / 1000);
            return .{ .handled = 0 };
        }

        if (std.mem.endsWith(u8, name, "_time")) {
            const now_i64: i64 = 1_719_000_000;
            const now: u64 = @bitCast(now_i64);
            const out_ptr = self.regs.rdi;
            if (out_ptr != 0) {
                if (self.guestMemory(out_ptr, 8)) |buf| {
                    std.mem.writeInt(u64, buf[0..8], now, .little);
                }
            }
            return .{ .handled = now };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__16chrono12steady_clock3nowEv")) {
            return .{ .handled = self.guest_time.now() };
        }

        if (std.mem.eql(u8, name, "_nanosleep")) {
            const req_ptr = self.regs.rdi;
            const rem_ptr = self.regs.rsi;
            const req = self.guestMemory(req_ptr, 16) orelse return .{ .handled = @bitCast(@as(i64, -1)) };
            const tv_sec = std.mem.readInt(i64, req[0..8], .little);
            const tv_nsec = std.mem.readInt(i64, req[8..16], .little);
            if (tv_sec < 0 or tv_nsec < 0 or tv_nsec >= 1_000_000_000) return .{ .handled = @bitCast(@as(i64, -1)) };
            const total_ns: u64 = (@as(u64, @intCast(tv_sec)) * 1_000_000_000) +| @as(u64, @intCast(tv_nsec));
            const requested_ns: i64 = @intCast(@min(total_ns, @as(u64, std.math.maxInt(i64))));
            self.pending_direct_sleep = scheduler.classifyGuestSleep(requested_ns);
            if (rem_ptr != 0) {
                if (self.guestMemory(rem_ptr, 16)) |rem| {
                    @memset(rem, 0);
                }
            }
            return .{ .handled = 0 };
        }

        if (std.mem.eql(u8, name, "_open")) {
            const path = self.guestCString(self.regs.rdi, 4096) orelse "";
            const result = self.fs_forwarder.open(self);
            self.noteProfileAccountOpen(path, result);
            return .{ .handled = result };
        }
        if (std.mem.eql(u8, name, "_write")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.write(self))) };
        }
        if (std.mem.eql(u8, name, "_close")) {
            return .{ .handled = self.fs_forwarder.close(self) };
        }
        if (std.mem.eql(u8, name, "_fstatat$INODE64") or std.mem.eql(u8, name, "_fstatat")) {
            return .{ .handled = self.fs_forwarder.fstatat(self) };
        }
        if (std.mem.eql(u8, name, "_openat")) {
            const path = self.guestCString(self.regs.rsi, 4096) orelse "";
            const result = self.fs_forwarder.openat(self);
            self.noteProfileAccountOpen(path, result);
            return .{ .handled = result };
        }
        if (std.mem.eql(u8, name, "_fstat$INODE64") or std.mem.eql(u8, name, "_fstat")) {
            return .{ .handled = self.fs_forwarder.fstat(self) };
        }
        if (std.mem.eql(u8, name, "_ftruncate") or std.mem.eql(u8, name, "_ftruncate64")) {
            return .{ .handled = self.fs_forwarder.ftruncate(self) };
        }
        if (std.mem.eql(u8, name, "_shm_open")) {
            return .{ .handled = self.fs_forwarder.shmOpen(self) };
        }
        if (std.mem.eql(u8, name, "_shm_unlink")) {
            return .{ .handled = self.fs_forwarder.shmUnlink(self) };
        }
        if (std.mem.eql(u8, name, "_opendir$INODE64") or std.mem.eql(u8, name, "_opendir")) {
            return .{ .handled = self.fs_forwarder.opendir(self) };
        }
        if (std.mem.eql(u8, name, "_dirfd")) {
            return .{ .handled = self.fs_forwarder.dirfd(self) };
        }
        if (std.mem.eql(u8, name, "_closedir")) {
            return .{ .handled = self.fs_forwarder.closedir(self) };
        }
        if (std.mem.eql(u8, name, "_readdir$INODE64") or std.mem.eql(u8, name, "_readdir")) {
            return .{ .handled = self.fs_forwarder.readdir(self) };
        }
        if (std.mem.eql(u8, name, "_read")) {
            const guest_fd = self.regs.rdi;
            const requested = self.regs.rdx;
            const result = self.fs_forwarder.read(self);
            self.noteProfileAccountRead(guest_fd, requested, result, 0);
            return .{ .handled = @bitCast(result) };
        }
        if (std.mem.eql(u8, name, "_readv")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.readv(self))) };
        }
        if (std.mem.eql(u8, name, "_writev")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.writev(self))) };
        }
        if (std.mem.eql(u8, name, "_pread$INODE64") or std.mem.eql(u8, name, "_pread")) {
            const guest_fd = self.regs.rdi;
            const requested = self.regs.rdx;
            const offset = self.regs.rcx;
            const result = self.fs_forwarder.pread(self);
            self.noteProfileAccountRead(guest_fd, requested, result, offset);
            return .{ .handled = @bitCast(result) };
        }
        if (std.mem.eql(u8, name, "_pwrite$INODE64") or std.mem.eql(u8, name, "_pwrite")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.pwrite(self))) };
        }
        if (std.mem.eql(u8, name, "_lseek$INODE64") or std.mem.eql(u8, name, "_lseek")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.lseek(self))) };
        }
        if (std.mem.eql(u8, name, "_stat$INODE64") or std.mem.eql(u8, name, "_stat")) {
            return .{ .handled = self.fs_forwarder.stat(self) };
        }
        if (std.mem.eql(u8, name, "_lstat$INODE64") or std.mem.eql(u8, name, "_lstat")) {
            return .{ .handled = self.fs_forwarder.lstat(self) };
        }
        if (std.mem.eql(u8, name, "_access") or std.mem.eql(u8, name, "_access$INODE64")) {
            return .{ .handled = self.fs_forwarder.access(self) };
        }
        if (std.mem.eql(u8, name, "_realpath$INODE64") or std.mem.eql(u8, name, "_realpath")) {
            return .{ .handled = self.fs_forwarder.realpath(self) };
        }
        if (std.mem.eql(u8, name, "_getcwd")) {
            return .{ .handled = self.fs_forwarder.getcwd(self) };
        }
        if (std.mem.eql(u8, name, "_chdir")) {
            return .{ .handled = self.fs_forwarder.chdir(self) };
        }
        if (std.mem.eql(u8, name, "_readlink$INODE64") or std.mem.eql(u8, name, "_readlink")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.readlink(self))) };
        }
        if (std.mem.eql(u8, name, "_dup")) {
            return .{ .handled = self.fs_forwarder.dup(self) };
        }
        if (std.mem.eql(u8, name, "_dup2")) {
            return .{ .handled = self.fs_forwarder.dup2(self) };
        }
        if (std.mem.eql(u8, name, "_fcntl")) {
            return .{ .handled = self.fs_forwarder.fcntl(self) };
        }
        if (std.mem.eql(u8, name, "_socket")) {
            return .{ .handled = self.fs_forwarder.createSocket(self) };
        }
        if (std.mem.eql(u8, name, "_setsockopt")) {
            return .{ .handled = self.fs_forwarder.setSocketOption(self) };
        }
        if (std.mem.eql(u8, name, "_connect")) {
            return .{ .handled = self.fs_forwarder.connectSocket(self) };
        }
        if (std.mem.eql(u8, name, "_send")) {
            return .{ .handled = self.fs_forwarder.sendSocket(self) };
        }
        if (std.mem.eql(u8, name, "_pipe")) {
            return .{ .handled = self.fs_forwarder.pipe(self) };
        }
        if (std.mem.eql(u8, name, "_mkdir") or std.mem.eql(u8, name, "_mkdir$INODE64")) {
            return .{ .handled = self.fs_forwarder.mkdir(self) };
        }
        if (std.mem.eql(u8, name, "_unlink") or std.mem.eql(u8, name, "_unlink$INODE64")) {
            return .{ .handled = self.fs_forwarder.unlink(self) };
        }
        if (std.mem.eql(u8, name, "_rename") or std.mem.eql(u8, name, "_rename$INODE64")) {
            return .{ .handled = self.fs_forwarder.rename(self) };
        }
        if (std.mem.eql(u8, name, "_symlink") or std.mem.eql(u8, name, "_symlink$INODE64")) {
            return .{ .handled = self.fs_forwarder.symlink(self) };
        }
        if (std.mem.eql(u8, name, "_mmap")) {
            return .{ .handled = self.fs_forwarder.mmap(self) };
        }
        if (std.mem.eql(u8, name, "_munmap")) {
            return .{ .handled = self.fs_forwarder.munmap(self) };
        }
        if (std.mem.eql(u8, name, "_mprotect")) {
            return .{ .handled = self.fs_forwarder.mprotect(self) };
        }
        if (std.mem.endsWith(u8, name, "_fopen")) {
            return .{ .handled = self.handleFopen() orelse 0 };
        }
        if (std.mem.endsWith(u8, name, "_fdopen")) {
            return .{ .handled = self.handleFdopen() orelse 0 };
        }
        if (std.mem.endsWith(u8, name, "_fileno")) {
            return .{ .handled = self.handleFileno() };
        }
        if (std.mem.endsWith(u8, name, "_fclose")) {
            return .{ .handled = self.handleFclose() };
        }
        if (std.mem.endsWith(u8, name, "_fprintf")) {
            return .{ .handled = self.handleFprintf() };
        }
        if (std.mem.endsWith(u8, name, "_snprintf")) {
            return .{ .handled = self.handleSnprintf() };
        }
        if (std.mem.endsWith(u8, name, "_fputs")) {
            return .{ .handled = self.handleFputs() };
        }
        if (std.mem.endsWith(u8, name, "_fwrite")) {
            return .{ .handled = self.handleFwrite() };
        }
        if (std.mem.eql(u8, name, "_fread")) {
            return .{ .handled = self.handleFread() };
        }
        if (std.mem.endsWith(u8, name, "_fflush")) {
            return .{ .handled = self.handleFflush() };
        }
        if (std.mem.endsWith(u8, name, "_abort")) {
            self.terminated = true;
            self.exit_code = 1;
            machoCapturePrint("macho-processor: guest called abort()\n", .{});
            return .control_transferred;
        }
        if (std.mem.eql(u8, name, "__tlv_atexit")) {
            _ = self.compat.registerAtexit(self.regs.rdi, self.regs.rsi, self.regs.rdx);
            return .{ .handled = 0 };
        }
        if (std.mem.endsWith(u8, name, "_ffs")) {
            const value = @as(u32, @truncate(self.regs.rdi));
            const result: u64 = if (value == 0) 0 else @as(u64, @ctz(value)) + 1;
            return .{ .handled = result };
        }
        if (std.mem.endsWith(u8, name, "_pthread_exit")) {
            self.terminated = true;
            self.exit_code = 0;
            return .control_transferred;
        }
        if (std.mem.eql(u8, name, "_ftell") or std.mem.eql(u8, name, "_ftello")) {
            return .{ .handled = self.handleFtell() };
        }
        if (std.mem.eql(u8, name, "_fseek") or std.mem.eql(u8, name, "_fseeko")) {
            return .{ .handled = self.handleFseek() };
        }
        if (std.mem.endsWith(u8, name, "_ferror")) {
            return .{ .handled = self.handleFerror() };
        }
        if (std.mem.endsWith(u8, name, "_printf")) {
            const arguments = [_]u64{ self.regs.rsi, self.regs.rdx, self.regs.rcx, self.regs.r8, self.regs.r9 };
            return .{ .handled = self.handlePrintfLike(null, self.regs.rdi, &arguments) };
        }
        if (std.mem.endsWith(u8, name, "_putchar")) {
            return .{ .handled = self.handlePutchar() };
        }

        if (std.mem.eql(u8, name, "_sysctlbyname")) {
            const sysctl_name = self.guestCString(self.regs.rdi, 256) orelse return .{ .unsupported = 0 };
            if (std.mem.startsWith(u8, sysctl_name, "hw.optional.")) {
                if (self.regs.rsi != 0 and self.regs.rdx != 0) {
                    const old_len_ptr = self.guestMemory(self.regs.rdx, @sizeOf(u64)) orelse return .{ .unsupported = 0 };
                    const old_len = std.mem.readInt(u64, old_len_ptr[0..8], .little);
                    std.mem.writeInt(u64, old_len_ptr[0..8], @sizeOf(u32), .little);
                    if (old_len >= @sizeOf(u32) and self.regs.rsi != 0) {
                        const old_buf = self.guestMemory(self.regs.rsi, @sizeOf(u32)) orelse return .{ .unsupported = 0 };
                        std.mem.writeInt(u32, old_buf[0..4], 0, .little);
                    }
                }
                return .{ .handled = 0 };
            }
            return .{ .handled = @bitCast(@as(i64, -1)) };
        }
        if (std.mem.eql(u8, name, "_sigaction")) {
            return .{ .handled = self.handleSigaction() };
        }
        if (std.mem.eql(u8, name, "_setjmp")) {
            const env_bytes = self.guestMemory(self.regs.rdi, @sizeOf(u64) * 4) orelse return .{ .unsupported = 0 };
            std.mem.writeInt(u64, env_bytes[0..8], self.regs.rsp, .little);
            std.mem.writeInt(u64, env_bytes[8..16], self.regs.rbx, .little);
            std.mem.writeInt(u64, env_bytes[16..24], self.regs.rbp, .little);
            std.mem.writeInt(u64, env_bytes[24..32], self.regs.rip, .little);
            return .{ .handled = 0 };
        }

        if (std.mem.eql(u8, name, "__ZNSt3__16thread4joinEv")) {
            if (self.verbose_trace) machoCapturePrint("    [import] std::thread::join(object=0x{x})\n", .{self.regs.rdi});
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "__ZNSt3__16thread20hardware_concurrencyEv")) {
            const count = std.Thread.getCpuCount() catch 1;
            if (self.verbose_trace) machoCapturePrint("    [import] std::thread::hardware_concurrency() -> {d}\n", .{count});
            return .{ .handled = count };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__111this_thread6get_idEv")) {
            const handle = self.pthreads.currentThreadHandle(self);
            if (self.verbose_trace) machoCapturePrint("    [import] std::this_thread::get_id() -> 0x{x}\n", .{handle});
            return .{ .handled = handle };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__119__thread_local_dataEv")) {
            const allocation = self.guestAlloc(64, 16) orelse return .{ .unsupported = 0 };
            if (self.verbose_trace) machoCapturePrint("    [import] __thread_local_data() -> 0x{x}\n", .{allocation});
            return .{ .handled = allocation };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEEC2Ev")) {
            const object = self.regs.rdi;
            if (self.guestMemory(object, 64)) |buf| {
                @memset(buf, 0);
                if (self.libcxx_streams.object_model.ensureType(self, .basic_streambuf, null)) |record| {
                    self.write64(object, record.vtable);
                }
                if (self.verbose_trace) machoCapturePrint("    [import] basic_streambuf::C2(object=0x{x})\n", .{object});
            }
            return .{ .handled = object };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEPKv")) {
            if (self.verbose_trace) machoCapturePrint("    [import] operator<<(void* ptr=0x{x}) -> *this\n", .{self.regs.rsi});
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__115basic_stringbufIcNS_11char_traitsIcEENS_9allocatorIcEEE3strEv")) {
            const output_ptr = self.regs.rdi;
            const stringbuf_ptr = self.regs.rsi;
            if (!self.libcxx_streams.stringbufToString(self, stringbuf_ptr, output_ptr)) {
                _ = compat_runtime.initLibcppStringLiteral(self, output_ptr, "");
            }
            if (self.verbose_trace) machoCapturePrint("    [import] basic_stringbuf::str() -> modeled string at 0x{x}\n", .{output_ptr});
            return .{ .handled = output_ptr };
        }

        if (std.mem.endsWith(u8, name, "_g_type_check_instance_cast")) {
            machoCapturePrint("    [import] _g_type_check_instance_cast compatibility shim → passthrough\n", .{});
            return .{ .handled = self.regs.rdi };
        }

        if (self.smart_stubs.resolve(name, imported.weak, self.regs.rdi)) |generated| {
            self.import_provider_override = .smart_stub;
            self.import_confidence_override = switch (generated.confidence) {
                .verified => .verified,
                .modeled => .modeled,
            };
            if (self.verbose_trace) {
                machoCapturePrint(
                    "    [smart stub] {s} reason={s} confidence={s}\n",
                    .{ name, @tagName(generated.reason), @tagName(generated.confidence) },
                );
            }
            return switch (generated.resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        }

        if (std.mem.eql(u8, name, "___sincosf_stret")) {
            const angle: f32 = @bitCast(std.mem.readInt(u32, self.xmm[0][0..4], .little));
            const sin_val: f32 = @sin(angle);
            const cos_val: f32 = @cos(angle);
            if (self.guestMemory(self.regs.rdi, 8)) |buf| {
                std.mem.writeInt(u32, buf[0..4], @bitCast(sin_val), .little);
                std.mem.writeInt(u32, buf[4..8], @bitCast(cos_val), .little);
                if (self.verbose_trace) machoCapturePrint("    [import] ___sincosf_stret(angle={d}) -> sin={d} cos={d} ptr=0x{x}\n", .{ angle, sin_val, cos_val, self.regs.rdi });
            }
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.eql(u8, name, "_cosf")) {
            const angle: f32 = @bitCast(std.mem.readInt(u32, self.xmm[0][0..4], .little));
            const result: f32 = @cos(angle);
            std.mem.writeInt(u32, self.xmm[0][0..4], @bitCast(result), .little);
            if (self.verbose_trace) machoCapturePrint("    [import] _cosf(angle={d}) -> {d}\n", .{ angle, result });
            return .{ .handled = 0 };
        }

        if (self.verbose_trace) machoCapturePrint("    [import] (unhandled) {s}\n", .{name});
        return .{ .unsupported = 0 };
    }

    fn recoverOrphanedPhaseTwoResume(self: *MachOState, symbol: []const u8) bool {
        const thrown = self.cxx_exceptions.activeThrow() orelse {
            self.unwinder.recordOrphanResume(false);
            return false;
        };
        var inspection = self.unwinder.inspectThrow(self, thrown.type_info_address);
        const tracked_header = if (thrown.allocation) |allocation| allocation.storage_address else thrown.object_address;
        // Some personality routines tail-call __Unwind_Resume after restoring
        // a signal context that no longer preserves RDI. The allocation header
        // recorded at __cxa_throw is still the ABI-correct exception pointer,
        // so do not discard an otherwise recoverable phase-two transaction.
        const supplied_header = self.regs.rdi;
        const supplied_is_tracked = supplied_header == tracked_header or supplied_header == thrown.object_address;
        const use_tracked_header = supplied_header == 0 or !supplied_is_tracked;
        const exception_header = if (use_tracked_header) tracked_header else supplied_header;
        machoCapturePrint(
            "macho-processor: Itanium orphan-resume reconstruction: symbol={s} supplied_header=0x{x} tracked_header=0x{x} using_tracked={} rip=0x{x} rsp=0x{x} frames={d} handler_found={}\n",
            .{ symbol, supplied_header, tracked_header, use_tracked_header, self.regs.rip, self.regs.rsp, inspection.frame_count, inspection.handler != null },
        );
        if (exception_header == 0) {
            self.unwinder.recordOrphanResume(false);
            self.last_unwind_inspection = inspection;
            return false;
        }
        if (!self.unwinder.installPhaseTwo(self, &inspection, exception_header)) {
            self.unwinder.recordOrphanResume(false);
            self.last_unwind_inspection = inspection;
            return false;
        }
        self.unwinder.recordOrphanResume(true);
        self.last_unwind_inspection = inspection;
        return true;
    }

    fn dispatchLibcppLocale(self: *MachOState, name: []const u8) ?ImportHandlerResult {
        if (std.mem.eql(u8, name, "__ZNSt3__16locale7classicEv")) {
            if (self.classic_locale_object == 0) {
                const object = self.guestAlloc(8, 8) orelse return .{ .unsupported = 0 };
                if (!self.compat.initLocale(self, object, null)) return .{ .unsupported = 0 };
                self.classic_locale_object = object;
                self.registerSyntheticRegion(object, 8, .synthetic_object, "std::locale::classic", .{
                    .kind = .owned_guest,
                    .may_dereference = true,
                    .owner = "libc++ locale runtime",
                });
            }
            return .{ .handled = self.classic_locale_object };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__16localeC1Ev") or
            std.mem.eql(u8, name, "__ZNSt3__16localeC2Ev"))
        {
            return if (self.compat.initLocale(self, self.regs.rdi, null)) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__16localeC1ERKS0_") or
            std.mem.eql(u8, name, "__ZNSt3__16localeC2ERKS0_"))
        {
            const source: ?u64 = if (self.regs.rsi != 0 and self.guestMemoryConst(self.regs.rsi, 8) != null) self.regs.rsi else null;
            return if (self.compat.initLocale(self, self.regs.rdi, source)) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__16localeaSERKS0_")) {
            const source: ?u64 = if (self.regs.rsi != 0 and self.guestMemoryConst(self.regs.rsi, 8) != null) self.regs.rsi else null;
            return if (self.compat.initLocale(self, self.regs.rdi, source)) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__18ios_base5imbueERKNS_6localeE")) {
            // libc++ returns the previous locale through the hidden sret object
            // in RDI; RSI is ios_base and RDX is the replacement locale.
            const previous_impl = if (self.guestMemoryConst(self.regs.rsi + 40, 8) != null) self.read64(self.regs.rsi + 40) else 0;
            if (previous_impl != 0) {
                self.write64(self.regs.rdi, previous_impl);
            } else if (!self.compat.initLocale(self, self.regs.rdi, null)) {
                return .{ .unsupported = 0 };
            }
            const replacement = if (self.regs.rdx != 0 and self.guestMemoryConst(self.regs.rdx, 8) != null)
                self.read64(self.regs.rdx)
            else blk: {
                const classic = self.classicLocale();
                if (classic == 0) return .{ .unsupported = 0 };
                break :blk self.read64(classic);
            };
            if (self.guestMemory(self.regs.rsi + 40, 8) != null) self.write64(self.regs.rsi + 40, replacement);
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE5imbueERKNS_6localeE")) {
            return .handled_void;
        }
        return null;
    }

    fn classicLocale(self: *MachOState) u64 {
        if (self.classic_locale_object != 0) return self.classic_locale_object;
        const object = self.guestAlloc(8, 8) orelse return 0;
        if (!self.compat.initLocale(self, object, null)) return 0;
        self.classic_locale_object = object;
        return object;
    }

    fn dispatchImportRoute(self: *MachOState, route: ImportRoute, imported: macho_metadata.ImportedSymbol) ?ImportHandlerResult {
        const name = imported.name;
        return switch (route) {
            .legacy => self.handleImportSlow(imported),
            .guest_memory_copy => self.handleGuestMemoryCopy(name),
            .memset => blk: {
                const destination = self.regs.rdi;
                if (self.regs.rdx != 0) {
                    const bytes = self.guestMemory(destination, self.regs.rdx) orelse break :blk .{ .unsupported = 0 };
                    @memset(bytes, @truncate(self.regs.rsi));
                }
                break :blk .{ .handled = destination };
            },
            .bzero => blk: {
                if (self.regs.rsi != 0) {
                    const bytes = self.guestMemory(self.regs.rdi, self.regs.rsi) orelse break :blk .{ .unsupported = 0 };
                    @memset(bytes, 0);
                }
                break :blk .{ .handled = 0 };
            },
            .gtk_main => if (self.beginGtkMainLoop()) .control_transferred else null,
            .gtk_main_quit => blk: {
                if (self.cooperative_ui_context == null) break :blk null;
                self.foreign_objects.main_loop_quits +|= 1;
                self.restoreGtkMainLoopCaller("gtk_main_quit");
                break :blk .control_transferred;
            },
            .gtk_idle_add => self.handleGtkIdleAdd(name),
            .g_source_remove => self.handleGSourceRemove(),
            .gtk_events_pending => blk: {
                self.pumpNativeWindowEvents();
                break :blk .{ .handled = @intFromBool(self.pendingGtkIdleCallbackCount() != 0) };
            },
            .gtk_main_iteration => blk: {
                self.pumpNativeWindowEvents();
                if (self.startNextGtkIdleCallback(name, false)) break :blk .control_transferred;
                break :blk .{ .handled = 0 };
            },
            .local_definition => blk: {
                const target = self.metadata.definedSymbolAddress(name) orelse break :blk null;
                if (target == imported.stub_address or !self.isExecutableAddress(target)) break :blk null;
                self.regs.rip = target;
                self.import_provider_override = .local_definition;
                self.import_confidence_override = .verified;
                break :blk .control_transferred;
            },
            .libcxx_stream => blk: {
                const resolution = self.libcxx_streams.dispatch(self, &self.fs_forwarder, name) orelse break :blk null;
                self.import_provider_override = .libcpp_stream;
                self.import_confidence_override = .modeled;
                break :blk switch (resolution) {
                    .handled => |value| .{ .handled = value },
                    .handled_void => .handled_void,
                };
            },
            .foreign_object => blk: {
                const resolution = self.foreign_objects.dispatch(self, name) orelse break :blk null;
                self.import_confidence_override = .modeled;
                break :blk switch (resolution) {
                    .handled => |value| .{ .handled = value },
                    .handled_void => .handled_void,
                };
            },
            .import_contract => blk: {
                const resolution = import_resolution.dispatchContract(self, name) orelse break :blk null;
                break :blk switch (resolution) {
                    .handled => |value| .{ .handled = value },
                    .handled_void => .handled_void,
                    .failed => .{ .unsupported = 0 },
                };
            },
            .libcxx_filesystem => blk: {
                const resolution = self.libcxx_filesystem.dispatch(self, &self.fs_forwarder, name) orelse break :blk null;
                self.import_provider_override = .libcpp_filesystem;
                self.import_confidence_override = .verified;
                break :blk switch (resolution) {
                    .handled => |value| .{ .handled = value },
                    .handled_void => .handled_void,
                };
            },
            .pthread => blk: {
                const resolution = self.pthreads.dispatch(self, name) orelse break :blk null;
                self.import_provider_override = .pthread_runtime;
                self.import_confidence_override = .modeled;
                break :blk switch (resolution) {
                    .handled => |value| .{ .handled = value },
                    .handled_void => .handled_void,
                };
            },
            .dynamic_library => blk: {
                const resolution = self.dynamic_forwarder.forward(self, imported.dylib, name) orelse break :blk null;
                self.import_provider_override = .dynamic_library;
                self.import_confidence_override = .verified;
                break :blk switch (resolution) {
                    .handled => |value| .{ .handled = value },
                    .handled_void => .handled_void,
                };
            },
            .shared_contract => self.dispatchSharedContract(name),
            .allocate => .{ .handled = self.memory_forwarder.allocate(self, self.regs.rdi, 16) orelse 0 },
            .release => blk: {
                self.memory_forwarder.release(self.regs.rdi);
                self.vtable_tracker.forgetAddress(self.regs.rdi);
                break :blk .handled_void;
            },
            .reallocate => .{ .handled = self.memory_forwarder.reallocate(self, self.regs.rdi, self.regs.rsi) orelse 0 },
            .posix_memalign => self.handleCachedPosixMemalign(),
            .aligned_alloc => blk: {
                const alignment = self.regs.rdi;
                if (!std.math.isPowerOfTwo(alignment) or self.regs.rsi % alignment != 0) break :blk .{ .handled = 0 };
                break :blk .{ .handled = self.memory_forwarder.allocate(self, self.regs.rsi, alignment) orelse 0 };
            },
            .calloc => .{ .handled = self.memory_forwarder.allocateZeroed(self, self.regs.rdi, self.regs.rsi) orelse 0 },
            .chkstk => .{ .handled = self.regs.rax },
            .sysconf => .{ .handled = guestSysconf(@bitCast(@as(u32, @truncate(self.regs.rdi)))) },
            .strtoul => self.handleImportSlow(imported),
        };
    }

    fn handleGtkIdleAdd(self: *MachOState, name: []const u8) ImportHandlerResult {
        const full = std.mem.eql(u8, name, "_g_idle_add_full") or std.mem.eql(u8, name, "_gdk_threads_add_idle_full");
        const callback = if (full) self.regs.rsi else self.regs.rdi;
        const data = if (full) self.regs.rdx else self.regs.rsi;
        const source = self.scheduleGtkIdleCallback(callback, data, name);
        return .{ .handled = source };
    }

    fn handleGSourceRemove(self: *MachOState) ImportHandlerResult {
        const removed = self.removeGtkIdleSource(self.regs.rdi);
        return .{ .handled = @intFromBool(removed) };
    }

    fn dispatchSharedContract(self: *MachOState, name: []const u8) ?ImportHandlerResult {
        const outcome = contract.dispatchFromAllFamilies(name, self.regs.rdi) orelse return null;
        if (self.contract_verification and !contract.verify.verifyDispatch(name, outcome, self.regs.rdi)) {
            if (contract.verify.resolveExpected(name, self.regs.rdi)) |expected| {
                return switch (expected) {
                    .handled => |value| .{ .handled = value },
                    .terminated => |code| .{ .terminated = code },
                };
            }
        }
        return switch (outcome) {
            .handled => |value| .{ .handled = value },
            .terminated => |code| .{ .terminated = code },
        };
    }

    fn handleCachedPosixMemalign(self: *MachOState) ImportHandlerResult {
        const alignment = self.regs.rsi;
        if (alignment < @sizeOf(u64) or !std.math.isPowerOfTwo(alignment)) return .{ .handled = 22 };
        if (self.guestMemory(self.regs.rdi, @sizeOf(u64)) == null) return .{ .unsupported = 14 };
        const allocation = self.memory_forwarder.allocate(self, self.regs.rdx, alignment) orelse return .{ .handled = 12 };
        self.write64(self.regs.rdi, allocation);
        return .{ .handled = 0 };
    }

    fn handleGuestMemoryCopy(self: *MachOState, name: []const u8) ImportHandlerResult {
        const destination_address = self.regs.rdi;
        const source_address = self.regs.rsi;
        const count = self.regs.rdx;
        if (std.mem.eql(u8, name, "___memcpy_chk") and count > self.regs.rcx) {
            machoCapturePrint(
                "macho-processor: fortified memcpy rejected: destination=0x{x} source=0x{x} bytes={d} destination_size={d}\n",
                .{ destination_address, source_address, count, self.regs.rcx },
            );
            return .{ .terminated = 134 };
        }
        if (count == 0) return .{ .handled = destination_address };

        const source = self.guestMemoryConst(source_address, count);
        const destination = self.guestMemory(destination_address, count);
        if (source != null and destination != null) {
            if (destination_address > source_address and destination_address - source_address < count) {
                std.mem.copyBackwards(u8, destination.?, source.?);
            } else {
                std.mem.copyForwards(u8, destination.?, source.?);
            }
        } else if (self.verbose_trace) {
            machoCapturePrint(
                "macho-processor: {s} skipped: source=0x{x} destination=0x{x} bytes={d} source_backed={} destination_backed={}\n",
                .{ name, source_address, destination_address, count, source != null, destination != null },
            );
        }
        return .{ .handled = destination_address };
    }

    fn isCooperativeWaitImport(name: []const u8) bool {
        return std.mem.indexOf(u8, name, "condition_variable15__do_timed_wait") != null or
            std.mem.indexOf(u8, name, "condition_variable4wait") != null or
            std.mem.indexOf(u8, name, "condition_variable10wait_until") != null or
            std.mem.eql(u8, name, "_pthread_cond_wait") or
            std.mem.eql(u8, name, "_pthread_cond_timedwait") or
            std.mem.eql(u8, name, "_pthread_cond_timedwait_relative_np") or
            std.mem.eql(u8, name, "_pthread_join");
    }

    fn isCooperativeYieldImport(name: []const u8) bool {
        return std.mem.eql(u8, name, "_pthread_yield_np") or std.mem.eql(u8, name, "_sched_yield");
    }

    fn handleCooperativeYieldImport(self: *MachOState, imported: macho_metadata.ImportedSymbol, return_address: u64) bool {
        if (!isCooperativeYieldImport(imported.name)) return false;
        self.pthreads.noteSchedulerYield();
        self.regs.rax = 0;
        if (return_address == 0 or !self.isExecutableAddress(return_address)) {
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
            self.terminated = true;
            return true;
        }
        _ = self.pop();
        self.regs.rip = return_address;
        const previous_thread = self.active_guest_thread;
        const switched = self.yieldActiveGuestThreadForWait(imported.name);
        self.resolving_import_route = .pthread;
        self.import_provider_override = .pthread_runtime;
        if (self.pthreads.scheduler_yields <= 8 or self.pthreads.scheduler_yields % 1000 == 0) {
            machoCapturePrint(
                "scheduler: explicit guest yield #{d}: import={s} from=0x{x} to=0x{x} switched={} suspended={d} deferred={d}\n",
                .{ self.pthreads.scheduler_yields, imported.name, previous_thread, self.active_guest_thread, switched, self.suspended_guest_thread_count, self.pthreads.deferred_threads },
            );
        }
        return true;
    }

    fn handleCooperativeWaitImport(self: *MachOState, imported: macho_metadata.ImportedSymbol, return_address: u64) bool {
        if (!isCooperativeWaitImport(imported.name)) return false;
        const cpp_condvar_wait = std.mem.indexOf(u8, imported.name, "condition_variable15__do_timed_wait") != null or
            std.mem.indexOf(u8, imported.name, "condition_variable4wait") != null or
            std.mem.indexOf(u8, imported.name, "condition_variable10wait_until") != null;
        const pthread_condvar_wait = std.mem.eql(u8, imported.name, "_pthread_cond_wait") or
            std.mem.eql(u8, imported.name, "_pthread_cond_timedwait") or
            std.mem.eql(u8, imported.name, "_pthread_cond_timedwait_relative_np");
        const condvar_wait = cpp_condvar_wait or pthread_condvar_wait;
        const timed_condvar_wait = std.mem.indexOf(u8, imported.name, "condition_variable15__do_timed_wait") != null or
            std.mem.indexOf(u8, imported.name, "condition_variable10wait_until") != null or
            std.mem.eql(u8, imported.name, "_pthread_cond_timedwait") or
            std.mem.eql(u8, imported.name, "_pthread_cond_timedwait_relative_np");
        if (cpp_condvar_wait) {
            if (!self.pthreads.beginCooperativeCppCondvarWait(self, timed_condvar_wait)) return false;
        } else if (pthread_condvar_wait and !self.pthreads.beginCooperativeCondvarWait(self, timed_condvar_wait)) {
            return false;
        }
        if (!condvar_wait) self.pthreads.collapsed_waits +|= 1;
        self.regs.rax = 0;
        if (return_address != 0 and self.isExecutableAddress(return_address)) {
            _ = self.pop();
            self.regs.rip = return_address;
        } else {
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
            self.terminated = true;
            return true;
        }
        if (self.yieldActiveGuestThreadForWait(imported.name)) {
            self.resolving_import_route = .pthread;
            self.import_provider_override = .pthread_runtime;
        } else if (condvar_wait) {
            // If this is the only runnable worker, the collapsed wait still
            // must return with the caller's mutex reacquired.
            _ = self.resumeSuspendedGuestThread();
        }
        return true;
    }

    // A contended mutex must be retried after the owner gets a time slice.
    // Unlike condition waits, keep the guest call frame intact so resuming the
    // worker re-enters pthread_mutex_lock rather than falsely reporting that
    // it acquired the mutex.
    fn handleCooperativeMutexContention(self: *MachOState, imported: macho_metadata.ImportedSymbol) bool {
        if (!std.mem.eql(u8, imported.name, "_pthread_mutex_lock") and
            !std.mem.eql(u8, imported.name, "__ZNSt3__15mutex4lockEv"))
        {
            return false;
        }
        const owner = self.pthreads.currentThreadHandle(self);
        if (!self.pthreads.mutexWouldBlock(self.regs.rdi, owner)) return false;
        self.pthreads.collapsed_waits +|= 1;
        return self.yieldActiveGuestThreadForWait("pthread mutex contention");
    }

    fn handleSleepSchedulingBoundary(self: *MachOState, decision: scheduler.GuestSleepDecision, reason: []const u8) bool {
        const sleeping_thread = self.active_guest_thread;
        var parked = false;
        switch (decision.kind) {
            .yield => _ = self.guest_time.advanceBy(decision.effective_nanoseconds),
            .invalid => return false,
            .timed => {
                const deadline = self.guest_time.now() +| decision.effective_nanoseconds;
                const sequence = self.scheduleGuestWaitDeadline(sleeping_thread, 0, 0, deadline);
                parked = self.pthreads.beginCooperativeSleep(
                    sleeping_thread,
                    self.executed_steps,
                    deadline,
                    sequence,
                );
                if (!parked) {
                    _ = self.guest_time.cancel(sequence);
                    _ = self.guest_time.advanceBy(decision.effective_nanoseconds);
                }
            },
            .indefinite => {
                parked = self.pthreads.beginCooperativeSleep(
                    sleeping_thread,
                    self.executed_steps,
                    null,
                    0,
                );
            },
        }
        const switched = self.yieldActiveGuestThreadForWait(reason);
        if (switched) self.cooperative_sleep_yields +|= 1;
        if (self.cooperative_sleep_yields <= 16 or self.cooperative_sleep_yields % 100 == 0 or decision.kind == .indefinite) {
            machoCapturePrint(
                "scheduler: virtual sleep boundary: sleeper=0x{x} resumed=0x{x} kind={s} parked={} switched={} deadline_ns={d} suspended={d} deferred={d}\n",
                .{ sleeping_thread, self.active_guest_thread, @tagName(decision.kind), parked, switched, if (decision.kind == .timed) self.guest_time.now() +| decision.effective_nanoseconds else 0, self.suspended_guest_thread_count, self.pthreads.deferred_threads },
            );
        }
        return switched;
    }

    pub fn handleVirtualSleepSchedulingBoundary(self: *MachOState, reason: []const u8) bool {
        return self.handleSleepSchedulingBoundary(self.dynamic_forwarder.lastVirtualSleepDecision(), reason);
    }

    pub fn handleDirectImportCall(self: *MachOState, imported: macho_metadata.ImportedSymbol) void {
        const boundary = x64_decoder.highway.systemBoundary(.macho64, .import, imported.stub_address, imported.name);
        if (boundary.disposition != .forward) {
            self.faulted = true;
            self.terminated = true;
            self.exit_code = 126;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.system_policy_rejected);
            return;
        }
        const return_address = self.read64(self.regs.rsp);
        if (self.handleCooperativeYieldImport(imported, return_address)) return;
        if (self.handleCooperativeMutexContention(imported)) return;
        if (self.handleCooperativeWaitImport(imported, return_address)) return;
        const virtual_sleep_calls_before = self.dynamic_forwarder.virtualSleepCallCount();
        self.pending_direct_sleep = null;
        var import_completed = false;
        switch (self.handleImport(imported)) {
            .handled => |result| {
                import_completed = true;
                self.regs.rax = result;
                if (self.verbose_trace) {
                    machoCapturePrint(
                        "  [handled direct import] {s} from {s}; stub=0x{x} return=0x{x} -> rax=0x{x}\n",
                        .{ imported.name, imported.dylib, imported.stub_address, return_address, result },
                    );
                }
            },
            .handled_void => {
                import_completed = true;
                if (self.verbose_trace) {
                    machoCapturePrint(
                        "  [handled void direct import] {s} from {s}; stub=0x{x} return=0x{x}\n",
                        .{ imported.name, imported.dylib, imported.stub_address, return_address },
                    );
                }
            },
            .control_transferred => {
                if (self.verbose_trace) {
                    machoCapturePrint(
                        "  [handled direct control transfer] {s} from {s}; landing_pad=0x{x}\n",
                        .{ imported.name, imported.dylib, self.regs.rip },
                    );
                }
                return;
            },
            .unsupported => |result| {
                self.regs.rax = result;
                self.recordUnresolvedImport(imported, return_address, result);
                machoCapturePrint(
                    "  [unresolved direct import #{d}] {s} from {s}; stub=0x{x} return=0x{x} -> rax=0x{x}\n",
                    .{ self.unresolved_import_count, imported.name, imported.dylib, imported.stub_address, return_address, result },
                );
                if (self.strict_imports) {
                    self.terminateForUnresolvedImport();
                    return;
                }
            },
            .terminated => |exit_code| {
                self.exit_code = exit_code;
                if (exit_diagnostics.reasonFromValue(self.termination_reason) == .unknown) {
                    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
                }
                self.terminated = true;
                machoCapturePrint("  [handled terminal direct import] {s}({d})\n", .{ imported.name, exit_code });
                return;
            },
        }

        if (return_address != 0 and self.isExecutableAddress(return_address)) {
            _ = self.pop();
            self.regs.rip = return_address;
            if (import_completed) {
                if (self.pending_direct_sleep) |decision| {
                    self.pending_direct_sleep = null;
                    _ = self.handleSleepSchedulingBoundary(decision, "POSIX nanosleep");
                } else if (self.dynamic_forwarder.virtualSleepCallCount() != virtual_sleep_calls_before) {
                    _ = self.handleVirtualSleepSchedulingBoundary("libc++ virtual sleep");
                }
            }
        } else {
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
            self.terminated = true;
        }
    }

    fn recordUnresolvedImport(
        self: *MachOState,
        imported: macho_metadata.ImportedSymbol,
        return_address: u64,
        synthetic_result: u64,
    ) void {
        var entry = ImportTraceEntry{
            .symbol = imported.name,
            .dylib = imported.dylib,
            .stub_address = imported.stub_address,
            .return_address = return_address,
            .synthetic_result = synthetic_result,
        };
        if (self.metadata.nearestSymbol(return_address)) |caller_sym| {
            entry.caller_symbol = caller_sym.name;
            entry.caller_offset = caller_sym.offset;
        }
        self.analyzeUnknownSymbol(imported, return_address);
        self.import_trace_entries[self.import_trace_index] = entry;
        self.import_trace_index = (self.import_trace_index + 1) % IMPORT_TRACE_BUFFER_LEN;
        if (self.import_trace_index == 0) self.import_trace_filled = true;
        self.unresolved_import_count += 1;
    }

    fn analyzeUnknownSymbol(
        self: *MachOState,
        imported: macho_metadata.ImportedSymbol,
        return_address: u64,
    ) void {
        const use_site = self.traceCallSite(return_address) orelse return_address;
        const observation = self.symbol_assembly.observe(imported.name, use_site) catch |err| {
            machoCapturePrint(
                "  [unknown-symbol assembly] tracking failed for {s}: {s}\n",
                .{ imported.name, @errorName(err) },
            );
            return;
        };

        if (observation.first_symbol) {
            if (self.symbol_assembly_catalog == null) {
                self.symbol_assembly_catalog = symbol_assembly_context.Catalog.build(
                    self.allocator,
                    &self.metadata,
                    decodeInsn,
                ) catch |err| {
                    machoCapturePrint(
                        "  [unknown-symbol assembly] static index failed for {s}: {s}\n",
                        .{ imported.name, @errorName(err) },
                    );
                    return;
                };
            }
            self.symbol_assembly_catalog.?.logImport(&self.metadata, imported, decodeInsn);
        }

        if (observation.first_use_site) {
            self.logDynamicUnknownSymbolContext(imported, use_site, observation.symbol_hits);
        } else if (observation.site_hits == 2) {
            machoCapturePrint(
                "  [unknown-symbol assembly] repeated symbol={s} use_site=0x{x}; identical context is deduplicated\n",
                .{ imported.name, use_site },
            );
        }
    }

    fn traceCallSite(self: *const MachOState, return_address: u64) ?u64 {
        const count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
        var ordinal = count;
        while (ordinal != 0) {
            ordinal -= 1;
            const index = if (self.trace_filled)
                (self.trace_index + ordinal) % TRACE_BUFFER_LEN
            else
                ordinal;
            const entry = self.trace_entries[index];
            if (entry.rip +% entry.len != return_address) continue;
            switch (entry.op) {
                .call_rel32, .call_reg64, .call_mem64 => return entry.rip,
                else => {},
            }
        }
        return null;
    }

    fn logDynamicUnknownSymbolContext(
        self: *const MachOState,
        imported: macho_metadata.ImportedSymbol,
        use_site: u64,
        symbol_hits: u64,
    ) void {
        const count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
        if (count == 0) return;
        var selected_ordinal: ?usize = null;
        for (0..count) |ordinal| {
            const index = if (self.trace_filled)
                (self.trace_index + ordinal) % TRACE_BUFFER_LEN
            else
                ordinal;
            if (self.trace_entries[index].rip == use_site) selected_ordinal = ordinal;
        }
        const selected = selected_ordinal orelse return;
        const start = selected -| symbol_assembly_context.CONTEXT_BEFORE;
        const end = @min(count, selected + 1 + symbol_assembly_context.CONTEXT_AFTER);
        if (self.metadata.nearestSymbol(use_site)) |caller| {
            machoCapturePrint(
                "  [unknown-symbol runtime block] symbol={s} occurrence={d} use_site=0x{x} caller={s}+0x{x}\n",
                .{ imported.name, symbol_hits, use_site, caller.name, caller.offset },
            );
        } else {
            machoCapturePrint(
                "  [unknown-symbol runtime block] symbol={s} occurrence={d} use_site=0x{x} caller=<unknown>\n",
                .{ imported.name, symbol_hits, use_site },
            );
        }
        machoCapturePrint(
            "    entry-registers: rdi=0x{x} rsi=0x{x} rdx=0x{x} rcx=0x{x} r8=0x{x} r9=0x{x} rsp=0x{x}\n",
            .{ self.regs.rdi, self.regs.rsi, self.regs.rdx, self.regs.rcx, self.regs.r8, self.regs.r9, self.regs.rsp },
        );
        for (self.xmm[0..4], 0..) |value, index| {
            machoCapturePrint(
                "    entry-xmm{d}: low=0x{x} high=0x{x}\n",
                .{
                    index,
                    std.mem.readInt(u64, value[0..8], .little),
                    std.mem.readInt(u64, value[8..16], .little),
                },
            );
        }

        for (start..end) |ordinal| {
            const index = if (self.trace_filled)
                (self.trace_index + ordinal) % TRACE_BUFFER_LEN
            else
                ordinal;
            const entry = self.trace_entries[index];
            const offset = self.addrToOffset(entry.rip) orelse continue;
            if (offset >= self.mem.len) continue;
            const available = @min(@as(usize, entry.len), self.mem.len - offset);
            if (available == 0) continue;
            const decoded = decodeInsn(self.mem[offset..]);
            const instruction = symbol_assembly_context.Instruction.init(
                entry.rip,
                self.mem[offset..],
                decoded,
                available,
            );
            symbol_assembly_context.logDynamicInstruction(
                &self.metadata,
                instruction,
                ordinal == selected,
                .{ .rsp = entry.rsp, .rax = entry.rax, .rcx = entry.rcx, .rdx = entry.rdx },
            );
        }
    }

    fn beginGuestExit(self: *MachOState, exit_code: u64) bool {
        if (self.atexit_running or self.compat.atexit_count == 0) return false;
        self.atexit_running = true;
        self.pending_exit_code = exit_code;
        // Model the call boundary that libc would establish before invoking
        // the first callback. Each callback then enters with rsp % 16 == 8.
        self.regs.rsp &= ~@as(u64, 0xF);
        self.dispatchNextAtexit();
        return self.atexit_running and !self.terminated;
    }

    fn dispatchNextAtexit(self: *MachOState) void {
        while (self.compat.takeLastAtexit()) |entry| {
            if (entry.function == 0 or !self.isExecutableAddress(entry.function)) {
                machoCapturePrint(
                    "macho-processor: skipping invalid atexit callback 0x{x} argument=0x{x} dso=0x{x}\n",
                    .{ entry.function, entry.argument, entry.dso },
                );
                continue;
            }
            self.push(GUEST_ATEXIT_RETURN_SENTINEL);
            if (self.terminated) return;
            self.regs.rdi = if (entry.takes_argument) entry.argument else 0;
            self.regs.rip = entry.function;
            self.atexit_callbacks_invoked +|= 1;
            if (self.verbose_trace) {
                machoCapturePrint(
                    "macho-processor: invoking atexit callback #{d}: function=0x{x} argument=0x{x} dso=0x{x} takes_argument={}\n",
                    .{ self.atexit_callbacks_invoked, entry.function, entry.argument, entry.dso, entry.takes_argument },
                );
            }
            return;
        }
        self.atexit_running = false;
        self.exit_code = self.pending_exit_code;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
        self.terminated = true;
        machoCapturePrint(
            "macho-processor: guest exit callbacks complete: invoked={d} exit_code={d}\n",
            .{ self.atexit_callbacks_invoked, self.exit_code },
        );
    }

    fn continueGuestExit(self: *MachOState) bool {
        if (!self.atexit_running) {
            self.faulted = true;
            self.terminated = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
            return false;
        }
        self.dispatchNextAtexit();
        return !self.terminated;
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
    ) bool {
        return signal_handling.deliverGuestSignal(self, signal, fault_rip, instruction_len, fault_address, fault_access);
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
        const evaluated = x64_decoder.highway.evaluate(op, width, self.regVal(d.dst_reg, size), self.regVal(d.src_reg, size), self.regs.rflags);
        self.regs.rflags = evaluated.rflags;
        if (evaluated.writeback) self.setReg(d.dst_reg, size, evaluated.value);
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
        const evaluated = x64_decoder.highway.evaluateMemory(op, width, self.regVal(reg, size), self.readMemVal(d.addr, size), direction, self.regs.rflags);
        self.regs.rflags = evaluated.rflags;
        if (evaluated.write_register) self.setReg(reg, size, evaluated.value);
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
        const lhs = if (memory) self.readMemVal(d.addr, size) else self.regVal(d.dst_reg, size);
        const evaluated = x64_decoder.highway.evaluate(op, width, lhs, d.imm, self.regs.rflags);
        self.regs.rflags = evaluated.rflags;
        if (evaluated.writeback) {
            if (memory) self.writeMemVal(d.addr, size, evaluated.value) else self.setReg(d.dst_reg, size, evaluated.value);
        }
    }

    pub fn setFlag(self: *MachOState, flag: u32, enabled: bool) void {
        if (enabled) {
            self.regs.rflags |= flag;
        } else {
            self.regs.rflags &= ~flag;
        }
    }

    pub fn executeBtrRegister(self: *MachOState, d: DecodedInsn) void {
        const value = self.regVal(d.dst_reg, d.size);
        const result = x64_decoder.bitTestAndResetRegister(d.size, value, self.regVal(d.src_reg, d.size));
        self.setFlag(RFL_CF, result.carry);
        self.setReg(d.dst_reg, d.size, result.value);
    }

    pub fn executeBtrMemory(self: *MachOState, d: DecodedInsn) void {
        const operand = x64_decoder.bitTestMemoryOperand(d.size, d.addr, self.regVal(d.src_reg, d.size)) orelse {
            self.faulted = true;
            self.terminated = true;
            return;
        };
        const mask = @as(u64, 1) << operand.bit_index;
        const value = self.readMemVal(operand.address, d.size);
        self.setFlag(RFL_CF, value & mask != 0);
        self.writeMemVal(operand.address, d.size, value & ~mask);
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

    pub fn step(self: *MachOState) bool {
        self.observeProfileAccountFlow();
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
            if (self.fileOffsetForVaddr(rip)) |file_off| {
                const remaining = if (file_off < self.data.len) self.data.len - file_off else 0;
                const file_bytes = self.data[file_off..][0..@min(@as(usize, 16), remaining)];
                machoCapturePrint("macho-processor: decode failed file_offset=0x{x} bytes={any}\n", .{ file_off, file_bytes });
            } else {
                machoCapturePrint("macho-processor: decode failed at unmapped address\n", .{});
            }
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.decode_failed);
            self.terminated = true;
            return false;
        };
        if (decoded.op == .invalid) {
            const mem_off = self.addrToOffset(self.regs.rip) orelse 0;
            const mem_bytes = self.mem[mem_off..][0..@min(@as(usize, 16), self.mem.len - mem_off)];
            const rip = self.regs.rip;
            machoCapturePrint("macho-processor: invalid instruction at rip=0x{x}, mem_off=0x{x}, bytes: {any}\n", .{ rip, mem_off, mem_bytes });
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
            self.dumpGtkBootstrapTrace();
            self.dumpMemInitTrace();
            self.dumpGtkHeartbeatTrace();
            self.dumpUiHandoffTrace();
            self.dumpRecentTrace();
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_instruction);
            self.terminated = true;
            return false;
        }
        self.recordTrace(decoded);
        if (self.gtk_bootstrap_active and self.gtk_bootstrap_index < 24) {
            const idx = self.gtk_bootstrap_index;
            self.gtk_bootstrap_entries[idx] = .{
                .rip = self.regs.rip,
                .thread = self.active_guest_thread,
                .op = @intFromEnum(decoded.op),
                .len = decoded.len,
            };
            self.gtk_bootstrap_index = idx + 1;
            if (self.gtk_bootstrap_index == 24) {
                self.gtk_bootstrap_active = false;
                const first = &self.gtk_bootstrap_entries[0];
                const last = &self.gtk_bootstrap_entries[23];
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
            self.internal_targets.sha1_process_bytes != 0 and
            self.regs.rip == self.internal_targets.sha1_process_bytes)
        {
            self.sha1_tracer.entry_rip = self.regs.rip;
            self.sha1_tracer.instruction_count = 0;
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
        // Unconditional SHA1 range detection: if RIP is inside the known SHA1
        // address range and the tracer hasn't latched an entry point yet,
        // auto-latch and force-enable the tracer so progress logging fires.
        if (!self.terminated and
            self.internal_targets.sha1_start != 0 and
            self.internal_targets.sha1_end != 0)
        {
            const rip = self.regs.rip;
            if (rip >= self.internal_targets.sha1_start and rip < self.internal_targets.sha1_end) {
                if (self.sha1_tracer.entry_rip == 0) {
                    self.sha1_tracer.entry_rip = rip;
                    machoCapturePrint(
                        "macho-processor: SHA1 tracer auto-latched: entry_rip=0x{x} step={d}\n",
                        .{ rip, self.executed_steps },
                    );
                }
            }
        }

        if (!self.terminated and self.sha1_tracer.enabled and self.sha1_tracer.entry_rip != 0) {
            self.sha1_tracer.instruction_count += 1;
            if (self.sha1_tracer.instruction_count == Sha1Tracer.HOT_THRESHOLD and !self.sha1_tracer.initial_report_done) {
                self.sha1_tracer.hot_function_rip = self.sha1_tracer.entry_rip;
                self.sha1_tracer.detected_at_step = self.executed_steps;
                self.sha1_tracer.initial_report_done = true;
                self.sha1_tracer.logSha1EntryCall(self);
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

    pub fn beginGtkMainLoop(self: *MachOState) bool {
        return scheduling.beginGtkMainLoop(self);
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

    // GTK idle scheduling is a wake-up, not merely queue bookkeeping. Dispatch
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

    pub fn scheduleGtkIdleCallback(self: *MachOState, function: u64, data: u64, tag: []const u8) u64 {
        return scheduling.scheduleGtkIdleCallback(self, function, data, tag);
    }

    pub fn pendingGtkIdleCallbackCount(self: *const MachOState) usize {
        return scheduling.pendingGtkIdleCallbackCount(self);
    }

    pub fn gtkIdleQueueSnapshot(self: *const MachOState) GtkIdleQueueSnapshot {
        return scheduling.gtkIdleQueueSnapshot(self);
    }

    pub fn gtkIdleDispatchBlock(self: *const MachOState) GtkIdleDispatchBlock {
        return scheduling.gtkIdleDispatchBlock(self);
    }

    pub fn removeGtkIdleSource(self: *MachOState, source: u64) bool {
        return scheduling.removeGtkIdleSource(self, source);
    }

    pub fn startNextGtkIdleCallback(self: *MachOState, reason: []const u8, active_already_saved: bool) bool {
        return scheduling.startNextGtkIdleCallback(self, reason, active_already_saved);
    }

    pub fn isGtkIdleCallbackHandle(self: *const MachOState, handle: u64) bool {
        return scheduling.isGtkIdleCallbackHandle(self, handle);
    }

    pub fn currentCooperativeThreadHandle(self: *const MachOState) u64 {
        if (self.active_guest_thread == 0 or self.isGtkIdleCallbackHandle(self.active_guest_thread)) {
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

    pub fn restoreGtkMainLoopCaller(self: *MachOState, reason: []const u8) void {
        scheduling.restoreGtkMainLoopCaller(self, reason);
    }

    pub fn logCooperativeSchedulerSummary(self: *const MachOState) void {
        scheduling.logCooperativeSchedulerSummary(self);
    }

    pub fn logCooperativeHeartbeat(self: *MachOState) void {
        scheduling.logCooperativeHeartbeat(self);
    }

    fn dumpGtkHeartbeatTrace(self: *const MachOState) void {
        scheduling.dumpGtkHeartbeatTrace(self);
    }

    fn dumpUiHandoffTrace(self: *const MachOState) void {
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
                const started_idle = self.pendingGtkIdleCallbackCount() != 0 and
                    self.startNextGtkIdleCallback("zero-active run guard", true);
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
                        .{ self.regs.rip, self.suspended_guest_thread_count, self.pthreads.blocked_threads, self.pendingGtkIdleCallbackCount() },
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
            // self.thread_scheduler.updatePendingIdle(self.pendingGtkIdleCallbackCount());
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
        /// Cached SHA1 arguments from onProcessBytesEntry or logSha1EntryCall.
        /// System V x86_64: RDI=this, RSI=data, RDX=length.
        sha1_this_ptr: u64 = 0,
        sha1_data_ptr: u64 = 0,
        sha1_byte_len: u64 = 0,
        /// Last-sampled SHA1 object state for progress tracking.
        last_data_ptr: u64 = 0,
        last_block_index: u32 = 0,
        last_byte_count: u64 = 0,
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

        fn reset(self: *@This()) void {
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
            self.last_byte_count = 0;
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

        /// Called from call handler when target matches sha1_process_bytes.
        /// Captures processBytes arguments (System V: RDI=this, RSI=data, RDX=len)
        /// and logs entry with caller chain and SHA1 object state.
        fn onProcessBytesEntry(self: *@This(), state: *MachOState) void {
            self.process_bytes_entry_count += 1;
            const this_ptr = state.regs.rdi;
            const data_ptr = state.regs.rsi;
            const byte_len = state.regs.rdx;
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
            }

            // Update the hot-function cache so logSha1Progress uses correct args
            self.sha1_this_ptr = this_ptr;
            self.sha1_data_ptr = data_ptr;
            self.sha1_byte_len = byte_len;
            self.last_data_ptr = data_ptr;

            // TinySHA1 object layout in this Xenia build:
            // buffered-byte count at +0x60=96, total byte count at +0x68=104.
            var block_index: u32 = 0;
            var byte_count: u64 = 0;
            if (state.guestMemoryConst(this_ptr + 96, 4)) |idx_bytes| {
                block_index = std.mem.readInt(u32, idx_bytes[0..4], .little);
            }
            if (state.guestMemoryConst(this_ptr + 104, 8)) |cnt_bytes| {
                byte_count = std.mem.readInt(u64, cnt_bytes[0..8], .little);
            }
            self.last_block_index = block_index;
            self.last_byte_count = byte_count;

            const return_address = if (state.guestMemoryConst(state.regs.rsp, 8)) |return_bytes|
                std.mem.readInt(u64, return_bytes[0..8], .little)
            else
                0;
            const caller = state.metadata.nearestSymbol(return_address);
            primitiveCapturePrint(
                "macho-processor: SHA1 processBytes entry #{d}: thread=0x{x} this=0x{x} data=0x{x} length={d} return=0x{x} caller={s}+0x{x} buffered_bytes={d} prior_total_bytes={d} step={d}\n",
                .{
                    self.process_bytes_entry_count,
                    state.active_guest_thread,
                    this_ptr,
                    data_ptr,
                    byte_len,
                    return_address,
                    if (caller) |symbol| symbol.name else "<unknown>",
                    if (caller) |symbol| symbol.offset else 0,
                    block_index,
                    byte_count,
                    state.executed_steps,
                },
            );
        }

        fn logSha1EntryCall(self: *@This(), state: *MachOState) void {
            // Capture System V x86_64 calling convention args at function entry
            // (RDI=this, RSI=data, RDX=length for member functions)
            self.sha1_this_ptr = state.regs.rdi;
            self.sha1_data_ptr = state.regs.rsi;
            self.sha1_byte_len = state.regs.rdx;
            self.last_data_ptr = self.sha1_data_ptr;
            self.sha1_byte_len = state.regs.rdx;

            // Read TinySHA1 buffered-byte and total-byte counters.
            if (state.guestMemoryConst(self.sha1_this_ptr + 96, 4)) |idx_bytes| {
                self.last_block_index = std.mem.readInt(u32, idx_bytes[0..4], .little);
            }
            if (state.guestMemoryConst(self.sha1_this_ptr + 104, 8)) |cnt_bytes| {
                self.last_byte_count = std.mem.readInt(u64, cnt_bytes[0..8], .little);
            }

            const symbol = state.metadata.nearestSymbol(self.entry_rip);
            const caller = state.metadata.nearestSymbol(self.call_site);
            primitiveCapturePrint(
                "macho-processor: SHA1 entry: function_rip=0x{x} ({s}) caller_rip=0x{x} ({s}) this=0x{x} data=0x{x} length={d} block_index={d} byte_count={d} thread=0x{x} step={d}\n",
                .{
                    self.entry_rip,
                    if (symbol) |s| s.name else "<unknown>",
                    self.call_site,
                    if (caller) |s| s.name else "<unknown>",
                    self.sha1_this_ptr,
                    self.sha1_data_ptr,
                    self.sha1_byte_len,
                    self.last_block_index,
                    self.last_byte_count,
                    state.active_guest_thread,
                    state.executed_steps,
                },
            );
        }

        fn logSha1Progress(self: *@This(), state: *MachOState) void {
            // Read current SHA1 object state from guest memory
            var current_block_index: u32 = self.last_block_index;
            var current_byte_count: u64 = self.last_byte_count;
            if (state.guestMemoryConst(self.sha1_this_ptr + 96, 4)) |idx_bytes| {
                current_block_index = std.mem.readInt(u32, idx_bytes[0..4], .little);
            }
            if (state.guestMemoryConst(self.sha1_this_ptr + 104, 8)) |cnt_bytes| {
                current_byte_count = std.mem.readInt(u64, cnt_bytes[0..8], .little);
            }
            const delta_bytes = current_byte_count -| self.last_byte_count;
            const bytes_remaining = self.sha1_byte_len -| current_byte_count;
            const blocks_delta = (current_block_index -| self.last_block_index);

            primitiveCapturePrint(
                "macho-processor: SHA1 progress: step={d} data_ptr=0x{x} delta_bytes={d} bytes_remaining={d} block_index={d} byte_count={d} new_blocks_this_sample={d} thread=0x{x}\n",
                .{
                    state.executed_steps,
                    self.sha1_data_ptr + current_byte_count,
                    delta_bytes,
                    bytes_remaining,
                    current_block_index,
                    current_byte_count,
                    blocks_delta,
                    state.active_guest_thread,
                },
            );

            // Check for stall: same 64-byte block being processed repeatedly?
            if (current_block_index == self.last_block_index and delta_bytes > 0) {
                primitiveCapturePrint(
                    "macho-processor: SHA1 WARNING: same 64-byte block being processed repeatedly! block_index={d} step={d}\n",
                    .{ current_block_index, state.executed_steps },
                );
            }
            // Check for no-progress stall: byte_count not advancing at all
            if (current_byte_count == self.last_byte_count and current_block_index == self.last_block_index) {
                primitiveCapturePrint(
                    "macho-processor: SHA1 WARNING: no byte/block progress since last sample! byte_count={d} block_index={d} step={d}\n",
                    .{ current_byte_count, current_block_index, state.executed_steps },
                );
            }
            // Check for completion: bytes_remaining == 0
            if (bytes_remaining == 0 and current_block_index > 0) {
                primitiveCapturePrint(
                    "macho-processor: SHA1 NOTE: byte_count==length reached (block_index={d}) — should complete soon! step={d}\n",
                    .{ current_block_index, state.executed_steps },
                );
            }

            self.last_block_index = current_block_index;
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

const utils = @import("utils.zig");
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

const decoder = @import("decoder.zig");

const decodeInsn = decoder.decodeInsn;
const decodeVex2 = decoder.decodeVex2;
const decodeVex3 = decoder.decodeVex3;
const decodeVexHalfMove = decoder.decodeVexHalfMove;
const decodeVexDuplicateMove = decoder.decodeVexDuplicateMove;
const x87BinaryOperation = decoder.x87BinaryOperation;
const decodeAccumulatorImmediate = decoder.decodeAccumulatorImmediate;
const decodeTwoByte = decoder.decodeTwoByte;
const decodeThreeByte = decoder.decodeThreeByte;
const decodeSseBytes = decoder.decodeSseBytes;
const hasModRM = decoder.hasModRM;
const mapReg = decoder.mapReg;
const mapJccCond8 = decoder.mapJccCond8;
const mapJccCond32 = decoder.mapJccCond32;
const readModRM = decoder.readModRM;
const decodeArithRmReg = decoder.decodeArithRmReg;
const decodeMovRmReg = decoder.decodeMovRmReg;
const decodeLea = decoder.decodeLea;
const decodePopRm = decoder.decodePopRm;
const decodeGroup1Imm = decoder.decodeGroup1Imm;
const decodeGroup2Shift = decoder.decodeGroup2Shift;
const decodeMovMemImm = decoder.decodeMovMemImm;
const decodeGroup3 = decoder.decodeGroup3;
const decodeGroup4_5 = decoder.decodeGroup4_5;
const decodeTestRmReg = decoder.decodeTestRmReg;
const decodeXchgRmReg = decoder.decodeXchgRmReg;
const decodeImulImm = decoder.decodeImulImm;
const decodeImulTwoOp = decoder.decodeImulTwoOp;
const decodeCmpxchg = decoder.decodeCmpxchg;
const decodeMovzx = decoder.decodeMovzx;
const decodeMovsx = decoder.decodeMovsx;
const decodeXadd = decoder.decodeXadd;
const decodeSetcc = decoder.decodeSetcc;
const decodeMovupsMovss = decoder.decodeMovupsMovss;
const decodeMovaps = decoder.decodeMovaps;

const VexArithmetic = decoder.VexArithmetic;
const VexBitwise = decoder.VexBitwise;
const shuffleBytes = decoder.shuffleBytes;
const compareEqualDwords = decoder.compareEqualDwords;
const unpackLowDwords = decoder.unpackLowDwords;
const permutePackedDoubles = decoder.permutePackedDoubles;
const bitwiseAndAllZero = decoder.bitwiseAndAllZero;
const bitwiseAndNotAllZero = decoder.bitwiseAndNotAllZero;
const applyVexCompare = decoder.applyVexCompare;
const vexArithmeticForOp = decoder.vexArithmeticForOp;
const applyVexArithmetic = decoder.applyVexArithmetic;
const vexBitwiseForOp = decoder.vexBitwiseForOp;
const applyVexBitwise = decoder.applyVexBitwise;
const applyVexPackedF32 = decoder.applyVexPackedF32;
const applyVexPackedF64 = decoder.applyVexPackedF64;
const roundVexFloat = decoder.roundVexFloat;
const roundNearestEven = decoder.roundNearestEven;
const roundVexPackedF32 = decoder.roundVexPackedF32;
const roundVexPackedF64 = decoder.roundVexPackedF64;
const convertVexFloatToSigned = decoder.convertVexFloatToSigned;
const integerIndefinite = decoder.integerIndefinite;
const duplicateVectorElements = decoder.duplicateVectorElements;

fn multiplyUnsignedEvenDwords(lhs: [16]u8, rhs: [16]u8) [16]u8 {
    return packed_ops.multiplyUnsignedEvenDwords(lhs, rhs);
}

fn shufflePackedDwords(source: [16]u8, control: u8) [16]u8 {
    return packed_ops.shufflePackedDwords(source, control);
}

fn unpackLowQwords(lhs: [16]u8, rhs: [16]u8) [16]u8 {
    return packed_ops.unpackLowQwords(lhs, rhs);
}

fn blendPackedWords(lhs: [16]u8, rhs: [16]u8, control: u8) [16]u8 {
    return packed_ops.blendPackedWords(lhs, rhs, control);
}

const PackedIntegerOperation = packed_ops.PackedIntegerOperation;

fn packedIntegerOperation(op: Op) PackedIntegerOperation {
    return switch (op) {
        .vpaddb, .vpaddw, .vpaddd, .vpaddq => .add,
        .vpsubb, .vpsubw, .vpsubd, .vpsubq => .sub,
        .vpmullw => .mul_low,
        else => unreachable,
    };
}

fn packedIntegerLaneBits(op: Op) u8 {
    return switch (op) {
        .vpaddb, .vpsubb => 8,
        .vpaddw, .vpsubw, .vpmullw => 16,
        .vpaddd, .vpsubd => 32,
        .vpaddq, .vpsubq => 64,
        else => unreachable,
    };
}

fn packedIntegerBinary(lhs: [16]u8, rhs: [16]u8, lane_bits: u8, operation: PackedIntegerOperation) [16]u8 {
    return packed_ops.packedIntegerBinary(lhs, rhs, lane_bits, operation);
}

fn packedShiftLaneBits(op: Op) u8 {
    return switch (op) {
        .vpsllw, .vpsrlw => 16,
        .vpslld, .vpsrld => 32,
        .vpsllq, .vpsrlq => 64,
        else => unreachable,
    };
}

fn shiftPackedElements(source: [16]u8, lane_bits: u8, count: u64, left: bool) [16]u8 {
    return packed_ops.shiftPackedElements(source, lane_bits, count, left);
}

fn shiftPackedBytes(source: [16]u8, count: u64, left: bool) [16]u8 {
    return packed_ops.shiftPackedBytes(source, count, left);
}

/// Darwin's `_SC_PAGESIZE` selector is 29. Process-level page queries describe
/// the VM syscall contract, not Rosette's finer-grained guest metadata.
fn guestSysconf(selector: i32) u64 {
    return guest_memory_geometry.darwinSysconf(selector) orelse @bitCast(@as(i64, -1));
}

fn sdlCompatibilityVersion() [3]u8 {
    return .{ 2, 0, 0 };
}

test "Darwin sysconf reports the host VM page contract" {
    try std.testing.expectEqual(guest_memory_geometry.host_vm_page_size, guestSysconf(29));
    try std.testing.expectEqual(std.math.maxInt(u64), guestSysconf(-1));
    try std.testing.expectEqual(std.math.maxInt(u64), guestSysconf(9999));
}

test "SDL compatibility version satisfies SDL2 callers" {
    const version = sdlCompatibilityVersion();
    try std.testing.expectEqual(@as(u8, 2), version[0]);
    try std.testing.expectEqual(@as(u8, 0), version[1]);
    try std.testing.expectEqual(@as(u8, 0), version[2]);
}

test "decode Xbyak shl ecx immediate" {
    const decoded = decodeInsn(&[_]u8{ 0xC1, 0xE1, 0x08 });
    try std.testing.expectEqual(Op.shl_reg_imm, decoded.op);
    try std.testing.expectEqual(Size.bits32, decoded.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(@as(u64, 8), decoded.imm);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode group two implicit and arithmetic shifts" {
    const shr = decodeInsn(&[_]u8{ 0xD1, 0xE9 });
    try std.testing.expectEqual(Op.shr_reg_imm, shr.op);
    try std.testing.expectEqual(@as(u64, 1), shr.imm);
    try std.testing.expectEqual(@as(u8, 2), shr.len);

    const sar = decodeInsn(&[_]u8{ 0x48, 0xC1, 0xFE, 0x03 });
    try std.testing.expectEqual(Op.sar_reg_imm, sar.op);
    try std.testing.expectEqual(Size.bits64, sar.size);
    try std.testing.expectEqual(RegId.dh_si_esi_rsi, sar.dst_reg);
    try std.testing.expectEqual(@as(u64, 3), sar.imm);
    try std.testing.expectEqual(@as(u8, 4), sar.len);

    const shr_cl = decodeInsn(&[_]u8{ 0xD3, 0xE8 });
    try std.testing.expectEqual(Op.shr_reg_cl, shr_cl.op);
    try std.testing.expectEqual(Size.bits32, shr_cl.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, shr_cl.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), shr_cl.len);

    const sar_cl = decodeInsn(&[_]u8{ 0xD3, 0xF8 });
    try std.testing.expectEqual(Op.sar_reg_cl, sar_cl.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, sar_cl.dst_reg);
}

test "decode group two rotate forms" {
    const fmt_ror = decodeInsn(&[_]u8{ 0xD3, 0xC8 });
    try std.testing.expectEqual(Op.ror_reg_cl, fmt_ror.op);
    try std.testing.expectEqual(Size.bits32, fmt_ror.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, fmt_ror.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), fmt_ror.len);

    const rol_byte_memory = decodeInsn(&[_]u8{ 0xC0, 0x07, 0x03 });
    try std.testing.expectEqual(Op.rol_mem_imm, rol_byte_memory.op);
    try std.testing.expectEqual(Size.bits8, rol_byte_memory.size);
    try std.testing.expectEqual(@as(u64, 3), rol_byte_memory.imm);

    const ror_rax = decodeInsn(&[_]u8{ 0x48, 0xD1, 0xC8 });
    try std.testing.expectEqual(Op.ror_reg_imm, ror_rax.op);
    try std.testing.expectEqual(Size.bits64, ror_rax.size);
    try std.testing.expectEqual(@as(u64, 1), ror_rax.imm);
}

test "decode CRC32 forms without consuming the following instruction" {
    const imgui_hash = decodeInsn(&[_]u8{ 0xF2, 0x0F, 0x38, 0xF0, 0xC1, 0xE9, 0x8F, 0xFF, 0xFF, 0xFF });
    try std.testing.expectEqual(Op.crc32_reg_reg, imgui_hash.op);
    try std.testing.expectEqual(Size.bits8, imgui_hash.size);
    try std.testing.expectEqual(Size.bits32, imgui_hash.dst_size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, imgui_hash.dst_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, imgui_hash.src_reg);
    try std.testing.expectEqual(@as(u8, 5), imgui_hash.len);

    const qword_memory = decodeInsn(&[_]u8{ 0xF2, 0x48, 0x0F, 0x38, 0xF1, 0x48, 0x08 });
    try std.testing.expectEqual(Op.crc32_reg_mem, qword_memory.op);
    try std.testing.expectEqual(Size.bits64, qword_memory.size);
    try std.testing.expectEqual(Size.bits64, qword_memory.dst_size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, qword_memory.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, qword_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 8), qword_memory.addr);
    try std.testing.expectEqual(@as(u8, 7), qword_memory.len);
}

test "decode register MOVZX without consuming the following instruction" {
    const decoded = decodeInsn(&[_]u8{ 0x0F, 0xB6, 0xC0, 0x48, 0x83, 0xC4, 0x30 });
    try std.testing.expectEqual(Op.movzx_reg32_mem8, decoded.op);
    try std.testing.expectEqual(Size.bits32, decoded.size);
    try std.testing.expect(decoded.is_reg_form);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.src_reg);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode UD2 undefined instruction" {
    const ud2 = decodeInsn(&[_]u8{ 0x0F, 0x0B, 0x48, 0x8B, 0x45, 0xB0 });
    try std.testing.expectEqual(Op.ud2, ud2.op);
    try std.testing.expectEqual(@as(u8, 2), ud2.len);
}

test "decode MOVSX memory and accumulator byte immediate forms" {
    const movsx = decodeInsn(&[_]u8{ 0x48, 0x0F, 0xBE, 0x48, 0x03 });
    try std.testing.expectEqual(Op.movsx_reg32_mem8, movsx.op);
    try std.testing.expectEqual(Size.bits64, movsx.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, movsx.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, movsx.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 3), movsx.addr);
    try std.testing.expectEqual(@as(u8, 5), movsx.len);

    const and_al = decodeInsn(&[_]u8{ 0x24, 0x01 });
    try std.testing.expectEqual(Op.and_reg8_imm8, and_al.op);
    try std.testing.expectEqual(Size.bits8, and_al.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, and_al.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), and_al.imm);
    try std.testing.expectEqual(@as(u8, 2), and_al.len);
}

test "decode accumulator TEST immediate forms" {
    const test_al = decodeInsn(&[_]u8{ 0xA8, 0x01 });
    try std.testing.expectEqual(Op.test_reg8_imm8, test_al.op);
    try std.testing.expectEqual(Size.bits8, test_al.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, test_al.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), test_al.imm);
    try std.testing.expectEqual(@as(u8, 2), test_al.len);

    const test_rax = decodeInsn(&[_]u8{ 0x48, 0xA9, 0x00, 0x00, 0x00, 0x80 });
    try std.testing.expectEqual(Op.test_reg64_imm32, test_rax.op);
    try std.testing.expectEqual(Size.bits64, test_rax.size);
    try std.testing.expectEqual(@as(u64, 0xFFFF_FFFF_8000_0000), test_rax.imm);
    try std.testing.expectEqual(@as(u8, 6), test_rax.len);
}

test "decode accumulator immediate arithmetic widths" {
    const add_rax = decodeInsn(&[_]u8{ 0x48, 0x05, 0xAB, 0x00, 0x00, 0x00 });
    try std.testing.expectEqual(Op.add_accum_imm, add_rax.op);
    try std.testing.expectEqual(Size.bits64, add_rax.size);
    try std.testing.expectEqual(@as(u64, 0xAB), add_rax.imm);
    try std.testing.expectEqual(@as(u8, 6), add_rax.len);

    const sub_ax = decodeInsn(&[_]u8{ 0x66, 0x2D, 0x34, 0x12 });
    try std.testing.expectEqual(Op.sub_accum_imm, sub_ax.op);
    try std.testing.expectEqual(Size.bits16, sub_ax.size);
    try std.testing.expectEqual(@as(u64, 0x1234), sub_ax.imm);

    const cmp_rax_negative = decodeInsn(&[_]u8{ 0x48, 0x3D, 0xFF, 0xFF, 0xFF, 0xFF });
    try std.testing.expectEqual(Op.cmp_accum_imm, cmp_rax_negative.op);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), cmp_rax_negative.imm);
}

test "decode full near conditional jump range" {
    const jc = decodeInsn(&[_]u8{ 0x0F, 0x82, 0xA7, 0x01, 0x00, 0x00 });
    try std.testing.expectEqual(Op.jcc_rel32, jc.op);
    try std.testing.expectEqual(Cond.b, jc.cond);
    try std.testing.expectEqual(@as(u64, 0x1A7), jc.addr);
    try std.testing.expect(jc.rip_relative);
    try std.testing.expectEqual(@as(u8, 6), jc.len);
}

test "decode both directions of 64-bit AND memory operands" {
    const load_and = decodeInsn(&[_]u8{ 0x48, 0x23, 0x08 });
    try std.testing.expectEqual(Op.and_reg64_mem64, load_and.op);
    try std.testing.expectEqual(Size.bits64, load_and.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, load_and.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, load_and.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), load_and.len);

    const store_and = decodeInsn(&[_]u8{ 0x48, 0x21, 0x08 });
    try std.testing.expectEqual(Op.and_mem64_reg64, store_and.op);
    try std.testing.expectEqual(Size.bits64, store_and.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, store_and.src_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, store_and.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), store_and.len);
}

test "decode arithmetic byte width and operand direction" {
    const xor_al = decodeInsn(&[_]u8{ 0x30, 0xC0 });
    try std.testing.expectEqual(Op.xor_reg8_reg8, xor_al.op);
    try std.testing.expectEqual(Size.bits8, xor_al.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, xor_al.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, xor_al.src_reg);

    const sub_mem = decodeInsn(&[_]u8{ 0x29, 0x08 });
    try std.testing.expectEqual(Op.sub_mem32_reg32, sub_mem.op);
    try std.testing.expectEqual(Size.bits32, sub_mem.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, sub_mem.src_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, sub_mem.sib_base_reg);
}

test "decode SBB register forms used for borrow masks" {
    const failing = decodeInsn(&[_]u8{ 0x19, 0xC9 });
    try std.testing.expectEqual(Op.sbb_reg32_reg32, failing.op);
    try std.testing.expectEqual(Size.bits32, failing.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, failing.dst_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, failing.src_reg);
    try std.testing.expectEqual(@as(u8, 2), failing.len);

    const reverse_64 = decodeInsn(&[_]u8{ 0x48, 0x1B, 0xC8 });
    try std.testing.expectEqual(Op.sbb_reg64_reg64, reverse_64.op);
    try std.testing.expectEqual(Size.bits64, reverse_64.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, reverse_64.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, reverse_64.src_reg);
}

test "decode group three TEST register immediate" {
    const test_cl = decodeInsn(&[_]u8{ 0xF6, 0xC1, 0x01 });
    try std.testing.expectEqual(Op.test_reg8_imm8, test_cl.op);
    try std.testing.expectEqual(Size.bits8, test_cl.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, test_cl.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), test_cl.imm);
    try std.testing.expectEqual(@as(u8, 3), test_cl.len);
}

test "decode CPUID and XGETBV" {
    const cpuid = decodeInsn(&[_]u8{ 0x0F, 0xA2 });
    try std.testing.expectEqual(Op.cpuid, cpuid.op);
    try std.testing.expectEqual(@as(u8, 2), cpuid.len);

    const xgetbv = decodeInsn(&[_]u8{ 0x0F, 0x01, 0xD0 });
    try std.testing.expectEqual(Op.xgetbv, xgetbv.op);
    try std.testing.expectEqual(@as(u8, 3), xgetbv.len);
}

test "decode non-W REX prefixes used by CPUID result copies" {
    const mov_r9d_eax = decodeInsn(&[_]u8{ 0x41, 0x89, 0xC1 });
    try std.testing.expectEqual(Op.mov_reg32_reg32, mov_r9d_eax.op);
    try std.testing.expectEqual(Size.bits32, mov_r9d_eax.size);
    try std.testing.expectEqual(RegId.r9b_r9w_r9d_r9, mov_r9d_eax.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, mov_r9d_eax.src_reg);
    try std.testing.expectEqual(@as(u8, 3), mov_r9d_eax.len);

    const mov_mem_r9d = decodeInsn(&[_]u8{ 0x45, 0x89, 0x08 });
    try std.testing.expectEqual(Op.mov_mem32_reg32, mov_mem_r9d.op);
    try std.testing.expectEqual(RegId.r9b_r9w_r9d_r9, mov_mem_r9d.src_reg);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, mov_mem_r9d.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), mov_mem_r9d.len);
}

test "decode Xbyak unaligned feature-mask copy" {
    const load = decodeInsn(&[_]u8{ 0x0F, 0x10, 0x00 });
    try std.testing.expectEqual(Op.movups_xmm_mem, load.op);
    try std.testing.expectEqual(@as(u8, 0), load.xmm_dst);
    try std.testing.expectEqual(@as(u8, 3), load.len);

    const store = decodeInsn(&[_]u8{ 0x0F, 0x29, 0x45, 0xF0 });
    try std.testing.expectEqual(Op.movaps_mem_xmm, store.op);
    try std.testing.expectEqual(@as(u8, 0), store.xmm_src);
    try std.testing.expectEqual(@as(u8, 4), store.len);
}

test "decode 128-bit VEX move families" {
    const extended_base_store = decodeInsn(&[_]u8{ 0xC4, 0xC1, 0x7A, 0x7F, 0x01 });
    try std.testing.expectEqual(Op.vmovdqu_mem_xmm, extended_base_store.op);
    try std.testing.expectEqual(@as(u8, 0), extended_base_store.xmm_src);
    try std.testing.expectEqual(RegId.r9b_r9w_r9d_r9, extended_base_store.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 5), extended_base_store.len);

    const load_dqu = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x6F, 0x00 });
    try std.testing.expectEqual(Op.vmovdqu_xmm_mem, load_dqu.op);
    try std.testing.expectEqual(@as(u8, 0), load_dqu.xmm_dst);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, load_dqu.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 4), load_dqu.len);

    const store_dqa = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x7F, 0x45, 0xF0 });
    try std.testing.expectEqual(Op.vmovdqa_mem_xmm, store_dqa.op);
    try std.testing.expectEqual(@as(u8, 0), store_dqa.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, store_dqa.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -16))), store_dqa.addr);
    try std.testing.expectEqual(@as(u8, 5), store_dqa.len);

    const register_ups = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x10, 0xCA });
    try std.testing.expectEqual(Op.vmovups_xmm_xmm, register_ups.op);
    try std.testing.expectEqual(@as(u8, 1), register_ups.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), register_ups.xmm_src);

    const load_ss = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x10, 0x01 });
    try std.testing.expectEqual(Op.vmovss_xmm_mem, load_ss.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, load_ss.sib_base_reg);

    const store_ss = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x11, 0x00 });
    try std.testing.expectEqual(Op.vmovss_mem_xmm, store_ss.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, store_ss.sib_base_reg);

    const load_sd = decodeInsn(&[_]u8{ 0xC5, 0xFB, 0x10, 0x02 });
    try std.testing.expectEqual(Op.vmovsd_xmm_mem, load_sd.op);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, load_sd.sib_base_reg);
}

test "decode VEX dword move and byte insertion" {
    const move_register = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x6E, 0xC0 });
    try std.testing.expectEqual(Op.vmovd_xmm_reg32, move_register.op);
    try std.testing.expectEqual(@as(u8, 0), move_register.xmm_dst);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, move_register.src_reg);
    try std.testing.expectEqual(@as(u8, 4), move_register.len);

    const move_memory = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x6E, 0x09 });
    try std.testing.expectEqual(Op.vmovd_xmm_mem32, move_memory.op);
    try std.testing.expectEqual(@as(u8, 1), move_memory.xmm_dst);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, move_memory.sib_base_reg);

    const insert_register = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x20, 0xC0, 0x0F });
    try std.testing.expectEqual(Op.vpinsrb_xmm_xmm_reg32, insert_register.op);
    try std.testing.expectEqual(@as(u8, 0), insert_register.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), insert_register.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, insert_register.src_reg);
    try std.testing.expectEqual(@as(u64, 15), insert_register.imm);
    try std.testing.expectEqual(@as(u8, 6), insert_register.len);

    const insert_memory = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x20, 0x00, 0x05 });
    try std.testing.expectEqual(Op.vpinsrb_xmm_xmm_mem8, insert_memory.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, insert_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 5), insert_memory.imm);

    const shuffle = decodeInsn(&[_]u8{ 0xC4, 0xE2, 0x79, 0x00, 0xC1 });
    try std.testing.expectEqual(Op.vpshufb, shuffle.op);
    try std.testing.expect(!shuffle.vector_256);
    try std.testing.expectEqual(@as(u8, 0), shuffle.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), shuffle.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), shuffle.xmm_src2);
    try std.testing.expect(shuffle.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), shuffle.len);
}

test "decode VEX qword moves between XMM general registers and memory" {
    const failing_vex2_load = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x7E, 0x40, 0x48 });
    try std.testing.expectEqual(Op.vmovq_xmm_mem64, failing_vex2_load.op);
    try std.testing.expectEqual(@as(u8, 0), failing_vex2_load.xmm_dst);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, failing_vex2_load.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x48), failing_vex2_load.addr);
    try std.testing.expectEqual(@as(u8, 5), failing_vex2_load.len);

    const failing_signbit_move = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xF9, 0x7E, 0xC0 });
    try std.testing.expectEqual(Op.vmovq_reg64_xmm, failing_signbit_move.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, failing_signbit_move.dst_reg);
    try std.testing.expectEqual(@as(u8, 0), failing_signbit_move.xmm_src);
    try std.testing.expectEqual(@as(u8, 5), failing_signbit_move.len);

    const load_register = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xF9, 0x6E, 0xC8 });
    try std.testing.expectEqual(Op.vmovq_xmm_reg64, load_register.op);
    try std.testing.expectEqual(@as(u8, 1), load_register.xmm_dst);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, load_register.src_reg);

    const store_memory = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xF9, 0x7E, 0x45, 0xF8 });
    try std.testing.expectEqual(Op.vmovq_mem64_xmm, store_memory.op);
    try std.testing.expectEqual(@as(u8, 0), store_memory.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, store_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -8))), store_memory.addr);
}

test "decode VEX low and high packed half moves" {
    const failing_store = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x13, 0x85, 0xD8, 0xFD, 0xFF, 0xFF });
    try std.testing.expectEqual(Op.vmovlpd_mem64_xmm, failing_store.op);
    try std.testing.expectEqual(@as(u8, 0), failing_store.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, failing_store.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -0x228))), failing_store.addr);
    try std.testing.expectEqual(@as(u8, 8), failing_store.len);

    const low_load = decodeInsn(&[_]u8{ 0xC5, 0xE8, 0x12, 0x08 });
    try std.testing.expectEqual(Op.vmovlps_xmm_xmm_mem64, low_load.op);
    try std.testing.expectEqual(@as(u8, 1), low_load.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), low_load.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, low_load.sib_base_reg);

    const high_store = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x17, 0x4D, 0xF8 });
    try std.testing.expectEqual(Op.vmovhpd_mem64_xmm, high_store.op);
    try std.testing.expectEqual(@as(u8, 1), high_store.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, high_store.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -8))), high_store.addr);
}

test "decode and execute VEX duplicate moves" {
    const failing = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x16, 0xC0 });
    try std.testing.expectEqual(Op.vmovshdup, failing.op);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_src);
    try std.testing.expect(failing.is_reg_form);
    try std.testing.expect(!failing.vector_256);
    try std.testing.expectEqual(@as(u8, 4), failing.len);

    const low_memory = decodeInsn(&[_]u8{ 0xC5, 0xFE, 0x12, 0x4D, 0xE0 });
    try std.testing.expectEqual(Op.vmovsldup, low_memory.op);
    try std.testing.expectEqual(@as(u8, 1), low_memory.xmm_dst);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, low_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -0x20))), low_memory.addr);
    try std.testing.expect(low_memory.vector_256);
    try std.testing.expect(!low_memory.is_reg_form);

    const doubles = duplicateVectorElements(.vmovddup, .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 });
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7 }, &doubles);
}

test "decode 256-bit VEX packed moves" {
    const decoded = decodeInsn(&[_]u8{ 0xC5, 0xFE, 0x6F, 0x00 });
    try std.testing.expectEqual(Op.vmovdqu_ymm_mem, decoded.op);

    const copy_state = decodeInsn(&[_]u8{ 0xC5, 0xFC, 0x10, 0x00 });
    try std.testing.expectEqual(Op.vmovups_ymm_mem, copy_state.op);

    const store_state = decodeInsn(&[_]u8{ 0xC5, 0xFC, 0x11, 0x07 });
    try std.testing.expectEqual(Op.vmovups_mem_ymm, store_state.op);

    const zero_upper = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x77 });
    try std.testing.expectEqual(Op.vzeroupper, zero_upper.op);
    try std.testing.expectEqual(@as(u8, 3), zero_upper.len);
}

test "decode the reported VEX2 VPMULUDQ instruction" {
    const decoded = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0xF4, 0xC1, 0xC5, 0xF9, 0x7F });
    try std.testing.expectEqual(Op.vpmuludq, decoded.op);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), decoded.xmm_src2);
    try std.testing.expect(decoded.is_reg_form);
    try std.testing.expect(!decoded.vector_256);
    try std.testing.expectEqual(@as(u8, 4), decoded.len);

    const vex3 = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x79, 0xF4, 0xC1 });
    try std.testing.expectEqual(Op.vpmuludq, vex3.op);
    try std.testing.expectEqual(@as(u8, 0), vex3.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), vex3.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), vex3.xmm_src2);
    try std.testing.expectEqual(@as(u8, 5), vex3.len);

    const memory = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0xF4, 0x45, 0xE0 });
    try std.testing.expectEqual(Op.vpmuludq, memory.op);
    try std.testing.expectEqual(@as(u8, 0), memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), memory.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -0x20))), memory.addr);
    try std.testing.expect(!memory.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), memory.len);

    const extended = decodeInsn(&[_]u8{ 0xC4, 0x41, 0x31, 0xF4, 0xC2 });
    try std.testing.expectEqual(Op.vpmuludq, extended.op);
    try std.testing.expectEqual(@as(u8, 8), extended.xmm_dst);
    try std.testing.expectEqual(@as(u8, 9), extended.xmm_src);
    try std.testing.expectEqual(@as(u8, 10), extended.xmm_src2);
    try std.testing.expect(extended.is_reg_form);
    try std.testing.expect(!extended.vector_256);

    const ymm = decodeInsn(&[_]u8{ 0xC5, 0xFD, 0xF4, 0xC1 });
    try std.testing.expectEqual(Op.vpmuludq, ymm.op);
    try std.testing.expect(ymm.vector_256);

    const wrong_prefix = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0xF4, 0xC1 });
    try std.testing.expectEqual(Op.invalid, wrong_prefix.op);

    var lhs = [_]u8{0} ** 16;
    var rhs = [_]u8{0} ** 16;
    std.mem.writeInt(u32, lhs[0..4], 3, .little);
    std.mem.writeInt(u32, lhs[8..12], 7, .little);
    std.mem.writeInt(u32, rhs[0..4], 5, .little);
    std.mem.writeInt(u32, rhs[8..12], 11, .little);
    const product = multiplyUnsignedEvenDwords(lhs, rhs);
    try std.testing.expectEqual(@as(u64, 15), std.mem.readInt(u64, product[0..8], .little));
    try std.testing.expectEqual(@as(u64, 77), std.mem.readInt(u64, product[8..16], .little));

    std.mem.writeInt(u32, lhs[0..4], std.math.maxInt(u32), .little);
    std.mem.writeInt(u32, rhs[0..4], std.math.maxInt(u32), .little);
    const wide_product = multiplyUnsignedEvenDwords(lhs, rhs);
    try std.testing.expectEqual(@as(u64, 0xFFFFFFFE00000001), std.mem.readInt(u64, wide_product[0..8], .little));
}

test "VPSHUFD applies its immediate independently to every 128-bit lane" {
    const decoded = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x70, 0xC1, 0x1B });
    try std.testing.expectEqual(Op.vpshufd, decoded.op);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_dst);
    try std.testing.expectEqual(@as(u8, 1), decoded.xmm_src);
    try std.testing.expectEqual(@as(u64, 0x1B), decoded.imm);
    try std.testing.expect(decoded.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), decoded.len);

    var source: [16]u8 = undefined;
    for (0..4) |lane| {
        std.mem.writeInt(u32, source[lane * 4 ..][0..4], @intCast(lane + 1), .little);
    }
    const reversed = shufflePackedDwords(source, 0x1B);
    try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, reversed[0..4], .little));
    try std.testing.expectEqual(@as(u32, 3), std.mem.readInt(u32, reversed[4..8], .little));
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, reversed[8..12], .little));
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, reversed[12..16], .little));

    const broadcast = shufflePackedDwords(source, 0x00);
    for (0..4) |lane| {
        try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, broadcast[lane * 4 ..][0..4], .little));
    }
}

test "decode and execute the XXH3 packed integer VEX cluster" {
    const addq_memory = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0xD4, 0x45, 0xE0 });
    try std.testing.expectEqual(Op.vpaddq, addq_memory.op);
    try std.testing.expectEqual(@as(u8, 0), addq_memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), addq_memory.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, addq_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -0x20))), addq_memory.addr);
    try std.testing.expect(!addq_memory.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), addq_memory.len);

    const shift_right = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0xD3, 0xC1 });
    try std.testing.expectEqual(Op.vpsrlq, shift_right.op);
    try std.testing.expectEqual(@as(u8, 0), shift_right.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), shift_right.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), shift_right.xmm_src2);
    try std.testing.expect(!shift_right.uses_imm);
    try std.testing.expectEqual(@as(u8, 4), shift_right.len);

    const shift_left = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0xF3, 0xC2 });
    try std.testing.expectEqual(Op.vpsllq, shift_left.op);
    try std.testing.expectEqual(@as(u8, 2), shift_left.xmm_src2);

    const blend = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x0E, 0xDA, 0xCC });
    try std.testing.expectEqual(Op.vpblendw, blend.op);
    try std.testing.expectEqual(@as(u8, 3), blend.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), blend.xmm_src);
    try std.testing.expectEqual(@as(u8, 2), blend.xmm_src2);
    try std.testing.expectEqual(@as(u64, 0xCC), blend.imm);
    try std.testing.expectEqual(@as(u8, 6), blend.len);

    const unpack = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x6C, 0xC1 });
    try std.testing.expectEqual(Op.vpunpcklqdq, unpack.op);
    try std.testing.expectEqual(@as(u8, 0), unpack.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), unpack.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), unpack.xmm_src2);

    var lhs = [_]u8{0} ** 16;
    var rhs = [_]u8{0} ** 16;
    std.mem.writeInt(u64, lhs[0..8], std.math.maxInt(u64), .little);
    std.mem.writeInt(u64, lhs[8..16], 0x100, .little);
    std.mem.writeInt(u64, rhs[0..8], 2, .little);
    std.mem.writeInt(u64, rhs[8..16], 0x20, .little);

    const sum = packedIntegerBinary(lhs, rhs, 64, .add);
    try std.testing.expectEqual(@as(u64, 1), std.mem.readInt(u64, sum[0..8], .little));
    try std.testing.expectEqual(@as(u64, 0x120), std.mem.readInt(u64, sum[8..16], .little));

    const shifted_right = shiftPackedElements(lhs, 64, 4, false);
    try std.testing.expectEqual(@as(u64, 0x0FFF_FFFF_FFFF_FFFF), std.mem.readInt(u64, shifted_right[0..8], .little));
    const shifted_left = shiftPackedElements(rhs, 64, 32, true);
    try std.testing.expectEqual(@as(u64, 0x0000_0002_0000_0000), std.mem.readInt(u64, shifted_left[0..8], .little));

    const blended = blendPackedWords(lhs, rhs, 0xCC);
    const blend_control: u8 = 0xCC;
    for (0..8) |lane| {
        const expected = if ((blend_control >> @intCast(lane)) & 1 != 0)
            std.mem.readInt(u16, rhs[lane * 2 ..][0..2], .little)
        else
            std.mem.readInt(u16, lhs[lane * 2 ..][0..2], .little);
        try std.testing.expectEqual(expected, std.mem.readInt(u16, blended[lane * 2 ..][0..2], .little));
    }

    const interleaved = unpackLowQwords(lhs, rhs);
    try std.testing.expectEqual(std.mem.readInt(u64, lhs[0..8], .little), std.mem.readInt(u64, interleaved[0..8], .little));
    try std.testing.expectEqual(std.mem.readInt(u64, rhs[0..8], .little), std.mem.readInt(u64, interleaved[8..16], .little));
}

test "decode VEX signed integer scalar conversions" {
    const failing_memory = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x2A, 0x45, 0xE8 });
    try std.testing.expectEqual(Op.vcvtsi2ss_xmm_mem, failing_memory.op);
    try std.testing.expectEqual(Size.bits32, failing_memory.size);
    try std.testing.expectEqual(@as(u8, 0), failing_memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), failing_memory.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, failing_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -0x18))), failing_memory.addr);
    try std.testing.expectEqual(@as(u8, 5), failing_memory.len);

    const two_byte_register = decodeInsn(&[_]u8{ 0xC5, 0xEB, 0x2A, 0xC9 });
    try std.testing.expectEqual(Op.vcvtsi2sd_xmm_reg, two_byte_register.op);
    try std.testing.expectEqual(Size.bits32, two_byte_register.size);
    try std.testing.expectEqual(@as(u8, 1), two_byte_register.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), two_byte_register.xmm_src);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, two_byte_register.src_reg);

    const to_float = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xFA, 0x2A, 0xC0 });
    try std.testing.expectEqual(Op.vcvtsi2ss_xmm_reg, to_float.op);
    try std.testing.expectEqual(Size.bits64, to_float.size);
    try std.testing.expectEqual(@as(u8, 0), to_float.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), to_float.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, to_float.src_reg);
    try std.testing.expectEqual(@as(u8, 5), to_float.len);

    const to_double = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x7B, 0x2A, 0x09 });
    try std.testing.expectEqual(Op.vcvtsi2sd_xmm_mem, to_double.op);
    try std.testing.expectEqual(Size.bits32, to_double.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, to_double.sib_base_reg);
}

test "decode VCVTSS2SD register and memory forms" {
    const register = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x5A, 0xC1 });
    try std.testing.expectEqual(Op.vcvtss2sd, register.op);
    try std.testing.expectEqual(@as(u8, 0), register.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), register.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), register.xmm_src2);
    try std.testing.expect(register.is_reg_form);
    try std.testing.expectEqual(@as(u8, 4), register.len);

    const memory = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x7A, 0x5A, 0x48, 0x10 });
    try std.testing.expectEqual(Op.vcvtss2sd, memory.op);
    try std.testing.expectEqual(@as(u8, 1), memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), memory.xmm_src);
    try std.testing.expect(!memory.is_reg_form);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x10), memory.addr);
}

test "decode VCVTSD2SS register form" {
    // VCVTSD2SS xmm0, xmm0, xmm1: C5 FB 5A C1 (F2 prefix, VEX.L=1)
    const decoded = decodeInsn(&[_]u8{ 0xC5, 0xFB, 0x5A, 0xC1 });
    try std.testing.expectEqual(Op.vcvtsd2ss, decoded.op);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), decoded.xmm_src2);
    try std.testing.expect(decoded.is_reg_form);
}

test "decode VEX scalar and packed arithmetic" {
    const boundary = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x58, 0xC0 });
    try std.testing.expectEqual(Op.vaddss, boundary.op);
    try std.testing.expectEqual(@as(u8, 0), boundary.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), boundary.xmm_src);
    try std.testing.expectEqual(@as(u8, 0), boundary.xmm_src2);
    try std.testing.expect(boundary.is_reg_form);
    try std.testing.expectEqual(@as(u8, 4), boundary.len);

    const packed_256 = decodeInsn(&[_]u8{ 0xC5, 0xEC, 0x59, 0xCB });
    try std.testing.expectEqual(Op.vmulps, packed_256.op);
    try std.testing.expectEqual(@as(u8, 1), packed_256.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), packed_256.xmm_src);
    try std.testing.expectEqual(@as(u8, 3), packed_256.xmm_src2);
    try std.testing.expect(packed_256.vector_256);

    const scalar_memory = decodeInsn(&[_]u8{ 0xC5, 0xEB, 0x5E, 0x08 });
    try std.testing.expectEqual(Op.vdivsd, scalar_memory.op);
    try std.testing.expectEqual(@as(u8, 1), scalar_memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), scalar_memory.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, scalar_memory.sib_base_reg);
    try std.testing.expect(!scalar_memory.is_reg_form);
}

test "decode VEX bitwise vector operations" {
    const zero = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x57, 0xC0 });
    try std.testing.expectEqual(Op.vxorps, zero.op);
    try std.testing.expectEqual(@as(u8, 0), zero.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), zero.xmm_src);
    try std.testing.expectEqual(@as(u8, 0), zero.xmm_src2);
    try std.testing.expect(!zero.vector_256);

    const and_not_256 = decodeInsn(&[_]u8{ 0xC5, 0xED, 0x55, 0x08 });
    try std.testing.expectEqual(Op.vandnpd, and_not_256.op);
    try std.testing.expectEqual(@as(u8, 1), and_not_256.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), and_not_256.xmm_src);
    try std.testing.expect(and_not_256.vector_256);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, and_not_256.sib_base_reg);
}

test "decode VPCMPEQD register memory and extended-register forms" {
    const failing = decodeInsn(&[_]u8{ 0xC5, 0xFD, 0x76, 0xC0 });
    try std.testing.expectEqual(Op.vpcmpeqd, failing.op);
    try std.testing.expect(failing.vector_256);
    try std.testing.expect(failing.is_reg_form);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_src);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_src2);
    try std.testing.expectEqual(@as(u8, 4), failing.len);

    const memory = decodeInsn(&[_]u8{ 0xC5, 0xED, 0x76, 0x08 });
    try std.testing.expectEqual(Op.vpcmpeqd, memory.op);
    try std.testing.expect(memory.vector_256);
    try std.testing.expect(!memory.is_reg_form);
    try std.testing.expectEqual(@as(u8, 1), memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), memory.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory.sib_base_reg);

    const extended = decodeInsn(&[_]u8{ 0xC4, 0x41, 0x6D, 0x76, 0xC8 });
    try std.testing.expectEqual(Op.vpcmpeqd, extended.op);
    try std.testing.expectEqual(@as(u8, 9), extended.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), extended.xmm_src);
    try std.testing.expectEqual(@as(u8, 8), extended.xmm_src2);
}

test "VPCMPEQD compares independent dword lanes" {
    var lhs = [_]u8{0} ** 16;
    var rhs = [_]u8{0} ** 16;
    std.mem.writeInt(u32, lhs[0..4], 7, .little);
    std.mem.writeInt(u32, rhs[0..4], 7, .little);
    std.mem.writeInt(u32, lhs[4..8], 9, .little);
    std.mem.writeInt(u32, rhs[4..8], 10, .little);
    const result = compareEqualDwords(lhs, rhs);
    try std.testing.expectEqual(std.math.maxInt(u32), std.mem.readInt(u32, result[0..4], .little));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, result[4..8], .little));
    try std.testing.expectEqual(std.math.maxInt(u32), std.mem.readInt(u32, result[8..12], .little));
    try std.testing.expectEqual(std.math.maxInt(u32), std.mem.readInt(u32, result[12..16], .little));
}

test "decode VEX unordered scalar comparisons" {
    const single = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x2E, 0xC1 });
    try std.testing.expectEqual(Op.vucomiss, single.op);
    try std.testing.expectEqual(@as(u8, 0), single.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), single.xmm_src2);
    try std.testing.expect(single.is_reg_form);
    try std.testing.expectEqual(@as(u8, 4), single.len);

    const double_memory = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x2F, 0x08 });
    try std.testing.expectEqual(Op.vucomisd, double_memory.op);
    try std.testing.expectEqual(@as(u8, 1), double_memory.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, double_memory.sib_base_reg);
    try std.testing.expect(!double_memory.is_reg_form);
}

test "decode VEX scalar and packed rounding" {
    const ceiling = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x0A, 0xC1, 0x0A });
    try std.testing.expectEqual(Op.vroundss, ceiling.op);
    try std.testing.expectEqual(@as(u8, 0), ceiling.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), ceiling.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), ceiling.xmm_src2);
    try std.testing.expectEqual(@as(u64, 0x0A), ceiling.imm);
    try std.testing.expectEqual(@as(u8, 6), ceiling.len);

    const packed_round = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x7D, 0x08, 0x00, 0x03 });
    try std.testing.expectEqual(Op.vroundps, packed_round.op);
    try std.testing.expect(packed_round.vector_256);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, packed_round.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 3), packed_round.imm);
}

test "VEX rounding modes include ties-to-even" {
    try std.testing.expectEqual(@as(f32, 2.0), roundVexFloat(f32, 2.5, 0));
    try std.testing.expectEqual(@as(f32, 4.0), roundVexFloat(f32, 3.5, 0));
    try std.testing.expectEqual(@as(f32, -3.0), roundVexFloat(f32, -2.1, 1));
    try std.testing.expectEqual(@as(f32, -2.0), roundVexFloat(f32, -2.1, 2));
    try std.testing.expectEqual(@as(f32, -2.0), roundVexFloat(f32, -2.9, 3));
}

test "decode VEX scalar float to signed integer conversions" {
    const imgui_truncate_memory = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x2C, 0x45, 0xFC, 0xC5, 0xFA, 0x2A, 0xC0 });
    try std.testing.expectEqual(Op.vcvttss2si, imgui_truncate_memory.op);
    try std.testing.expectEqual(Size.bits32, imgui_truncate_memory.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, imgui_truncate_memory.dst_reg);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, imgui_truncate_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -4))), imgui_truncate_memory.addr);
    try std.testing.expect(!imgui_truncate_memory.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), imgui_truncate_memory.len);

    const truncate_to_64 = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xFA, 0x2C, 0xC1 });
    try std.testing.expectEqual(Op.vcvttss2si, truncate_to_64.op);
    try std.testing.expectEqual(Size.bits64, truncate_to_64.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, truncate_to_64.dst_reg);
    try std.testing.expectEqual(@as(u8, 1), truncate_to_64.xmm_src);
    try std.testing.expect(truncate_to_64.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), truncate_to_64.len);

    const round_double_memory = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x7B, 0x2D, 0x08 });
    try std.testing.expectEqual(Op.vcvtsd2si, round_double_memory.op);
    try std.testing.expectEqual(Size.bits32, round_double_memory.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, round_double_memory.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, round_double_memory.sib_base_reg);
}

test "VEX float to signed conversion handles rounding and overflow" {
    try std.testing.expectEqual(@as(u64, 3), convertVexFloatToSigned(f32, 3.9, .bits64, true));
    try std.testing.expectEqual(@as(u64, 4), convertVexFloatToSigned(f32, 3.5, .bits64, false));
    try std.testing.expectEqual(@as(u64, 2), convertVexFloatToSigned(f32, 2.5, .bits64, false));
    try std.testing.expectEqual(@as(u64, 0x8000_0000), convertVexFloatToSigned(f64, std.math.nan(f64), .bits32, true));
    try std.testing.expectEqual(@as(u64, 0x8000_0000_0000_0000), convertVexFloatToSigned(f64, 1.0e30, .bits64, true));
}

test "decode MOVSXD from memory" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0x63, 0x09 });
    try std.testing.expectEqual(Op.movsxd_reg64_mem32, decoded.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode signed 64-bit register division" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0xF7, 0xF9 });
    try std.testing.expectEqual(Op.idiv_reg64, decoded.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode unsigned 64-bit register division" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0xF7, 0xF1 });
    try std.testing.expectEqual(Op.div_reg64, decoded.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode signed and unsigned 32-bit register division" {
    const signed = decodeInsn(&[_]u8{ 0xF7, 0xF9 });
    try std.testing.expectEqual(Op.idiv_reg32, signed.op);
    try std.testing.expectEqual(Size.bits32, signed.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, signed.dst_reg);

    const unsigned = decodeInsn(&[_]u8{ 0xF7, 0xF1 });
    try std.testing.expectEqual(Op.div_reg32, unsigned.op);
    try std.testing.expectEqual(Size.bits32, unsigned.size);
}

test "decode signed and unsigned memory division" {
    const unsigned = decodeInsn(&[_]u8{ 0x48, 0xF7, 0x75, 0xF8 });
    try std.testing.expectEqual(Op.div_mem64, unsigned.op);
    try std.testing.expectEqual(Size.bits64, unsigned.size);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, unsigned.sib_base_reg);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64) - 7), unsigned.addr);
    try std.testing.expectEqual(@as(u8, 4), unsigned.len);

    const signed = decodeInsn(&[_]u8{ 0xF7, 0x7B, 0x10 });
    try std.testing.expectEqual(Op.idiv_mem32, signed.op);
    try std.testing.expectEqual(Size.bits32, signed.size);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, signed.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x10), signed.addr);
    try std.testing.expectEqual(@as(u8, 3), signed.len);
}

test "decode group three NOT register and memory forms" {
    const register = decodeInsn(&[_]u8{ 0xF6, 0xD1 });
    try std.testing.expectEqual(Op.not_reg8, register.op);
    try std.testing.expectEqual(Size.bits8, register.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, register.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), register.len);

    const memory = decodeInsn(&[_]u8{ 0x48, 0xF7, 0x55, 0xF8 });
    try std.testing.expectEqual(Op.not_mem64, memory.op);
    try std.testing.expectEqual(Size.bits64, memory.size);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -8))), memory.addr);
}

test "decode group three NEG register and memory forms" {
    const failing_neg_cl = decodeInsn(&[_]u8{ 0xF6, 0xD9 });
    try std.testing.expectEqual(Op.neg_reg8, failing_neg_cl.op);
    try std.testing.expectEqual(Size.bits8, failing_neg_cl.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, failing_neg_cl.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), failing_neg_cl.len);

    const neg_qword_memory = decodeInsn(&[_]u8{ 0x48, 0xF7, 0x5D, 0xF8 });
    try std.testing.expectEqual(Op.neg_mem64, neg_qword_memory.op);
    try std.testing.expectEqual(Size.bits64, neg_qword_memory.size);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, neg_qword_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -8))), neg_qword_memory.addr);
}

test "decode group three unsigned multiply register widths" {
    const multiply64 = decodeInsn(&[_]u8{ 0x48, 0xF7, 0xE1 });
    try std.testing.expectEqual(Op.mul_reg64, multiply64.op);
    try std.testing.expectEqual(Size.bits64, multiply64.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, multiply64.dst_reg);
    try std.testing.expectEqual(@as(u8, 3), multiply64.len);

    const multiply8 = decodeInsn(&[_]u8{ 0xF6, 0xE2 });
    try std.testing.expectEqual(Op.mul_reg8, multiply8.op);
    try std.testing.expectEqual(Size.bits8, multiply8.size);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, multiply8.dst_reg);
}

test "decode carry flag control instructions" {
    try std.testing.expectEqual(Op.cmc, decodeInsn(&[_]u8{0xF5}).op);
    try std.testing.expectEqual(Op.clc, decodeInsn(&[_]u8{0xF8}).op);
    try std.testing.expectEqual(Op.stc, decodeInsn(&[_]u8{0xF9}).op);
}

test "decode bit scan and count instructions without losing ModRM" {
    const fmt_bsr = decodeInsn(&[_]u8{ 0x48, 0x0F, 0xBD, 0xC0 });
    try std.testing.expectEqual(Op.bsr_reg_reg, fmt_bsr.op);
    try std.testing.expectEqual(Size.bits64, fmt_bsr.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, fmt_bsr.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, fmt_bsr.src_reg);
    try std.testing.expectEqual(@as(u8, 4), fmt_bsr.len);

    const memory_bsf = decodeInsn(&[_]u8{ 0x0F, 0xBC, 0x48, 0x08 });
    try std.testing.expectEqual(Op.bsf_reg_mem, memory_bsf.op);
    try std.testing.expectEqual(Size.bits32, memory_bsf.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, memory_bsf.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory_bsf.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 8), memory_bsf.addr);
    try std.testing.expectEqual(@as(u8, 4), memory_bsf.len);

    const lzcnt = decodeInsn(&[_]u8{ 0xF3, 0x48, 0x0F, 0xBD, 0xC3 });
    try std.testing.expectEqual(Op.lzcnt_reg_reg, lzcnt.op);
    try std.testing.expectEqual(Size.bits64, lzcnt.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, lzcnt.dst_reg);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, lzcnt.src_reg);
    try std.testing.expectEqual(@as(u8, 5), lzcnt.len);
}

test "decode POPCNT exact FBO failure and width variants" {
    const exact_failure = decodeInsn(&[_]u8{ 0xF3, 0x0F, 0xB8, 0xC0, 0x5D, 0xC3 });
    try std.testing.expectEqual(Op.popcnt_reg_reg, exact_failure.op);
    try std.testing.expectEqual(Size.bits32, exact_failure.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, exact_failure.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, exact_failure.src_reg);
    try std.testing.expectEqual(@as(u8, 4), exact_failure.len);

    const memory_16 = decodeInsn(&[_]u8{ 0x66, 0xF3, 0x0F, 0xB8, 0x48, 0x08 });
    try std.testing.expectEqual(Op.popcnt_reg_mem, memory_16.op);
    try std.testing.expectEqual(Size.bits16, memory_16.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, memory_16.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory_16.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 8), memory_16.addr);

    const register_64 = decodeInsn(&[_]u8{ 0xF3, 0x48, 0x0F, 0xB8, 0xD3 });
    try std.testing.expectEqual(Op.popcnt_reg_reg, register_64.op);
    try std.testing.expectEqual(Size.bits64, register_64.size);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, register_64.dst_reg);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, register_64.src_reg);

    try std.testing.expectEqual(Op.invalid, decodeInsn(&[_]u8{ 0x0F, 0xB8, 0xC0 }).op);
}

test "POPCNT semantics mask width and define status flags" {
    const all_status_flags = RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF;
    const nonzero = populationCount(.bits32, 0xFFFF_FFFF_0000_000B, all_status_flags | RFL_DF);
    try std.testing.expectEqual(@as(u64, 3), nonzero.value);
    try std.testing.expectEqual(@as(u32, RFL_DF), nonzero.rflags & (all_status_flags | RFL_DF));

    const zero = populationCount(.bits64, 0, all_status_flags | RFL_DF);
    try std.testing.expectEqual(@as(u64, 0), zero.value);
    try std.testing.expectEqual(@as(u32, RFL_ZF | RFL_DF), zero.rflags & (all_status_flags | RFL_DF));
}

test "decode BTR register forms without consuming following instructions" {
    const exact_failure = decodeInsn(&[_]u8{ 0x0F, 0xB3, 0xC8, 0x89, 0x85 });
    try std.testing.expectEqual(Op.btr_reg_reg, exact_failure.op);
    try std.testing.expectEqual(Size.bits32, exact_failure.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, exact_failure.dst_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, exact_failure.src_reg);
    try std.testing.expectEqual(@as(u8, 3), exact_failure.len);

    const rex_w = decodeInsn(&[_]u8{ 0x4D, 0x0F, 0xB3, 0xC8 });
    try std.testing.expectEqual(Op.btr_reg_reg, rex_w.op);
    try std.testing.expectEqual(Size.bits64, rex_w.size);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, rex_w.dst_reg);
    try std.testing.expectEqual(RegId.r9b_r9w_r9d_r9, rex_w.src_reg);
}

test "decode BSWAP register family" {
    const initializer_bswap = decodeInsn(&[_]u8{ 0x0F, 0xC8 });
    try std.testing.expectEqual(Op.bswap_reg, initializer_bswap.op);
    try std.testing.expectEqual(Size.bits32, initializer_bswap.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, initializer_bswap.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), initializer_bswap.len);

    const extended_bswap = decodeInsn(&[_]u8{ 0x49, 0x0F, 0xCF });
    try std.testing.expectEqual(Op.bswap_reg, extended_bswap.op);
    try std.testing.expectEqual(Size.bits64, extended_bswap.size);
    try std.testing.expectEqual(RegId.r15b_r15w_r15d_r15, extended_bswap.dst_reg);
    try std.testing.expectEqual(@as(u8, 3), extended_bswap.len);
}

test "bit scan and count semantics cover zero and operand width" {
    const bsr = bitScan(.bits64, .bsr, 0x8000_0000_0000_0000);
    try std.testing.expectEqual(@as(u64, 63), bsr.value);
    try std.testing.expect(bsr.write_destination);
    try std.testing.expect(!bsr.zero_flag);
    try std.testing.expectEqual(@as(?bool, null), bsr.carry_flag);

    const empty_bsf = bitScan(.bits32, .bsf, 0);
    try std.testing.expect(!empty_bsf.write_destination);
    try std.testing.expect(empty_bsf.zero_flag);

    const empty_tzcnt = bitScan(.bits16, .tzcnt, 0);
    try std.testing.expectEqual(@as(u64, 16), empty_tzcnt.value);
    try std.testing.expectEqual(@as(?bool, true), empty_tzcnt.carry_flag);

    const lzcnt = bitScan(.bits32, .lzcnt, 0x0000_0100);
    try std.testing.expectEqual(@as(u64, 23), lzcnt.value);
    try std.testing.expectEqual(@as(?bool, false), lzcnt.carry_flag);
}

test "unknown two-byte opcode is rejected at its real boundary" {
    const decoded = decodeInsn(&[_]u8{ 0x0F, 0xFF, 0xC0 });
    try std.testing.expectEqual(Op.invalid, decoded.op);
    try std.testing.expectEqual(@as(u8, 0), decoded.len);
}

test "decode conditional moves without losing the ModRM byte" {
    const register = decodeInsn(&[_]u8{ 0x0F, 0x42, 0xC1 });
    try std.testing.expectEqual(Op.cmovcc_reg_reg, register.op);
    try std.testing.expectEqual(Cond.b, register.cond);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, register.dst_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, register.src_reg);
    try std.testing.expectEqual(@as(u8, 3), register.len);

    const memory = decodeInsn(&[_]u8{ 0x48, 0x0F, 0x45, 0x45, 0xF8 });
    try std.testing.expectEqual(Op.cmovcc_reg_mem, memory.op);
    try std.testing.expectEqual(Cond.ne, memory.cond);
    try std.testing.expectEqual(Size.bits64, memory.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory.dst_reg);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64) - 7), memory.addr);
    try std.testing.expectEqual(@as(u8, 5), memory.len);
}

test "decode 64-bit OR register immediate without aliasing memory opcodes" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0x83, 0xC9, 0x01 });
    try std.testing.expectEqual(Op.or_reg64_imm8, decoded.op);
    try std.testing.expectEqual(Size.bits64, decoded.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), decoded.imm);
    try std.testing.expectEqual(@as(u8, 4), decoded.len);

    const memory = decodeInsn(&[_]u8{ 0x48, 0x83, 0x49, 0x08, 0x01 });
    try std.testing.expectEqual(Op.or_mem64_imm8, memory.op);
    try std.testing.expectEqual(Size.bits64, memory.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 8), memory.addr);
    try std.testing.expectEqual(@as(u64, 1), memory.imm);
    try std.testing.expectEqual(@as(u8, 5), memory.len);
}

test "decode XCHG ModRM register and memory forms without aliasing" {
    // 4C 87 C3 is XCHG RBX,R8, the exact instruction family that previously
    // fell through the memory executor and attempted to dereference address 0.
    const register = decodeInsn(&[_]u8{ 0x4C, 0x87, 0xC3 });
    try std.testing.expectEqual(Op.xchg_reg64_reg64, register.op);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, register.dst_reg);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, register.src_reg);
    try std.testing.expect(register.is_reg_form);
    try std.testing.expectEqual(@as(u8, 3), register.len);

    const memory = decodeInsn(&[_]u8{ 0x4C, 0x87, 0x03 });
    try std.testing.expectEqual(Op.xchg_mem64_reg64, memory.op);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, memory.sib_base_reg);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, memory.src_reg);
    try std.testing.expect(!memory.is_reg_form);
}

test "decode CMPXCHG ModRM register form without aliasing memory" {
    const register = decodeInsn(&[_]u8{ 0x4C, 0x0F, 0xB1, 0xC3 });
    try std.testing.expectEqual(Op.cmpxchg_reg64_reg64, register.op);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, register.dst_reg);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, register.src_reg);
    try std.testing.expect(register.is_reg_form);
}

test "decode CMPXCHG byte and word forms without widening atomics" {
    const byte_memory = decodeInsn(&[_]u8{ 0xF0, 0x0F, 0xB0, 0x11 });
    try std.testing.expectEqual(Op.cmpxchg_mem8_reg8, byte_memory.op);
    try std.testing.expectEqual(Size.bits8, byte_memory.size);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, byte_memory.src_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, byte_memory.sib_base_reg);
    try std.testing.expect(!byte_memory.is_reg_form);

    const word_memory = decodeInsn(&[_]u8{ 0xF0, 0x66, 0x0F, 0xB1, 0x11 });
    try std.testing.expectEqual(Op.cmpxchg_mem16_reg16, word_memory.op);
    try std.testing.expectEqual(Size.bits16, word_memory.size);

    const byte_register = decodeInsn(&[_]u8{ 0x0F, 0xB0, 0xD1 });
    try std.testing.expectEqual(Op.cmpxchg_reg8_reg8, byte_register.op);
    try std.testing.expectEqual(Size.bits8, byte_register.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, byte_register.dst_reg);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, byte_register.src_reg);
    try std.testing.expect(byte_register.is_reg_form);
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
    try std.testing.expect(MachOState.bindingRequiresBoundThunk(got_section));
    try std.testing.expect(!MachOState.bindingRequiresBoundThunk(constant_section));
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

test "decode compiler long NOP with segment override" {
    const decoded = decodeInsn(&[_]u8{ 0x66, 0x66, 0x2E, 0x0F, 0x1F, 0x84, 0x00, 0, 0, 0, 0 });
    try std.testing.expectEqual(Op.nop, decoded.op);
    try std.testing.expectEqual(@as(u8, 11), decoded.len);
}

test "decode prefetch memory hint as no-op" {
    const prefetchnta = decodeInsn(&[_]u8{ 0x0F, 0x18, 0x00, 0x5D, 0xC3 });
    try std.testing.expectEqual(Op.nop, prefetchnta.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, prefetchnta.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), prefetchnta.len);

    const prefetchw = decodeInsn(&[_]u8{ 0x0F, 0x0D, 0x48, 0x20 });
    try std.testing.expectEqual(Op.nop, prefetchw.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, prefetchw.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x20), prefetchw.addr);
    try std.testing.expectEqual(@as(u8, 4), prefetchw.len);
}

test "decode x87 integer and extended-real forms used by chrono timeout path" {
    const load = decodeInsn(&[_]u8{ 0xDF, 0x6D, 0xC8, 0xDB, 0x7D, 0xD0 });
    try std.testing.expectEqual(Op.fild_mem64, load.op);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, load.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -56))), load.addr);
    try std.testing.expectEqual(@as(u8, 3), load.len);

    const store = decodeInsn(&[_]u8{ 0xDB, 0x7D, 0xD0, 0x31, 0xC0 });
    try std.testing.expectEqual(Op.fstp_mem80, store.op);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, store.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -48))), store.addr);
    try std.testing.expectEqual(@as(u8, 3), store.len);

    // FLD m80real in libc++'s duration comparison. This was previously
    // misdecoded as FILD m32int, forcing every finite sleep to duration::max().
    const load_extended = decodeInsn(&[_]u8{ 0xDB, 0x6D, 0xB4 });
    try std.testing.expectEqual(Op.fld_mem80, load_extended.op);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, load_extended.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -76))), load_extended.addr);
    try std.testing.expectEqual(@as(u8, 3), load_extended.len);

    const load_i32 = decodeInsn(&[_]u8{ 0xDB, 0x00 });
    try std.testing.expectEqual(Op.fild_mem32, load_i32.op);
}

test "x87 stack tracks physical tags and status TOP" {
    var x87 = X87State{};
    try std.testing.expectEqual(@as(u16, 0xFFFF), x87.tagWord());
    try std.testing.expectEqual(@as(u16, 0), x87.statusWord());

    try std.testing.expect(x87.push(1.0));
    try std.testing.expect(x87.push(2.0));
    try std.testing.expectEqual(@as(u3, 6), x87.top);
    try std.testing.expectEqual(@as(u16, 0x0FFF), x87.tagWord());
    try std.testing.expectEqual(@as(u16, 0x3000), x87.statusWord() & 0x3800);
    try std.testing.expectEqual(@as(f64, 2.0), x87.get(0).?);
    try std.testing.expectEqual(@as(f64, 1.0), x87.get(1).?);

    _ = x87.pop();
    try std.testing.expectEqual(@as(u3, 7), x87.top);
    try std.testing.expectEqual(X87Tag.empty, x87.tags[6]);
    try std.testing.expectEqual(X87Tag.valid, x87.tags[7]);
}

test "x87 stack faults preserve TOP and report overflow or underflow" {
    var x87 = X87State{};
    try std.testing.expect(x87.push(0.0));
    try std.testing.expect(x87.push(1.0));
    try std.testing.expect(x87.push(2.0));
    try std.testing.expect(x87.push(3.0));
    try std.testing.expect(x87.push(4.0));
    try std.testing.expect(x87.push(5.0));
    try std.testing.expect(x87.push(6.0));
    try std.testing.expect(x87.push(7.0));
    const top_before = x87.top;
    try std.testing.expect(!x87.push(8.0));
    try std.testing.expectEqual(top_before, x87.top);
    try std.testing.expect((x87.statusWord() & 0x0241) == 0x0241);

    x87.reset();
    try std.testing.expect(x87.pop() == null);
    try std.testing.expect((x87.statusWord() & 0x0241) == 0x0041);
}

test "decode x87 memory and stack forms" {
    const fild16 = decodeInsn(&[_]u8{ 0xDF, 0x00 });
    try std.testing.expectEqual(Op.fild_mem16, fild16.op);
    try std.testing.expectEqual(@as(u8, 2), fild16.len);

    const fld64 = decodeInsn(&[_]u8{ 0xDD, 0x00 });
    try std.testing.expectEqual(Op.fld_mem64, fld64.op);
    const fstp32 = decodeInsn(&[_]u8{ 0xD9, 0x18 });
    try std.testing.expectEqual(Op.fstp_mem32, fstp32.op);
    const fld_st3 = decodeInsn(&[_]u8{ 0xD9, 0xC3 });
    try std.testing.expectEqual(Op.fld_st, fld_st3.op);
    try std.testing.expectEqual(@as(u64, 3), fld_st3.imm);
    const fnstsw = decodeInsn(&[_]u8{ 0xDF, 0xE0 });
    try std.testing.expectEqual(Op.fnstsw_ax, fnstsw.op);

    const fmulp = decodeInsn(&[_]u8{ 0xDE, 0xC9 });
    try std.testing.expectEqual(Op.x87_binary, fmulp.op);
    try std.testing.expectEqual(@as(u64, 0x209), fmulp.imm);

    const fucomip = decodeInsn(&[_]u8{ 0xDF, 0xE9 });
    try std.testing.expectEqual(Op.fucomip_st, fucomip.op);
    try std.testing.expectEqual(@as(u64, 1), fucomip.imm);
}

test "x87 FMULP writes ST(i) before popping ST(0)" {
    var x87 = X87State{};
    try std.testing.expect(x87.push(3.0));
    try std.testing.expect(x87.push(4.0));
    x87.binary(1, 0, 1, true);
    try std.testing.expectEqual(@as(u3, 7), x87.top);
    try std.testing.expectEqual(@as(f64, 12.0), x87.get(0).?);
    try std.testing.expectEqual(X87Tag.empty, x87.tags[6]);
}

test "GTK idle wake preempts a running worker after all pthreads have started" {
    try std.testing.expectEqual(scheduler.CooperativeWork.gtk_idle, scheduler.chooseCooperativeWork(.{ .pending_idle = 1 }));
    try std.testing.expectEqual(scheduler.CooperativeWork.gtk_idle, scheduler.chooseCooperativeWork(.{ .pending_idle = 1, .deferred_threads = 3 }));
    try std.testing.expectEqual(scheduler.CooperativeWork.none, scheduler.chooseCooperativeWork(.{ .pending_idle = 1, .idle_callback_running = true }));
    try std.testing.expectEqual(scheduler.CooperativeWork.none, scheduler.chooseCooperativeWork(.{ .idle_callback_running = true, .deferred_threads = 1, .suspended_threads = 2 }));
    try std.testing.expectEqual(scheduler.CooperativeWork.deferred_thread, scheduler.chooseCooperativeWork(.{ .deferred_threads = 1, .suspended_threads = 2 }));
    try std.testing.expectEqual(scheduler.CooperativeWork.suspended_thread, scheduler.chooseCooperativeWork(.{ .suspended_threads = 2 }));
    try std.testing.expectEqual(scheduler.CooperativeWork.none, scheduler.chooseCooperativeWork(.{}));
}

test "GTK idle diagnostics retain the oldest queued callback provenance" {
    const callbacks = [_]GtkIdleCallback{
        .{ .source_id = 7, .function = 0x7000, .active = true, .tag = "newer", .scheduled_step = 90, .scheduling_thread = 0x77, .scheduling_rip = 0x777 },
        .{},
        .{ .source_id = 3, .function = 0x3000, .active = true, .tag = "presenter", .scheduled_step = 40, .scheduling_thread = 0x33, .scheduling_rip = 0x333 },
    };
    const snapshot = gtkIdleQueueSnapshotFor(&callbacks);
    try std.testing.expectEqual(@as(usize, 2), snapshot.pending);
    try std.testing.expectEqual(@as(u64, 3), snapshot.oldest_source);
    try std.testing.expectEqual(@as(u64, 0x3000), snapshot.oldest_callback);
    try std.testing.expectEqual(@as(u64, 40), snapshot.oldest_scheduled_step);
    try std.testing.expectEqual(@as(u64, 0x33), snapshot.oldest_scheduling_thread);
    try std.testing.expectEqual(@as(u64, 0x333), snapshot.oldest_scheduling_rip);
    try std.testing.expectEqualStrings("presenter", snapshot.oldest_tag);
}

test "decode C6 and C7 register immediate forms" {
    const byte_move = decodeInsn(&[_]u8{ 0x41, 0xC6, 0xC0, 0x7F });
    try std.testing.expectEqual(Op.mov_reg_imm, byte_move.op);
    try std.testing.expectEqual(Size.bits8, byte_move.size);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, byte_move.dst_reg);
    try std.testing.expectEqual(@as(u64, 0x7F), byte_move.imm);

    const max_unsigned = decodeInsn(&[_]u8{ 0x48, 0xC7, 0xC0, 0xFF, 0xFF, 0xFF, 0xFF });
    try std.testing.expectEqual(Op.mov_reg_imm, max_unsigned.op);
    try std.testing.expectEqual(Size.bits64, max_unsigned.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, max_unsigned.dst_reg);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), max_unsigned.imm);
    try std.testing.expectEqual(@as(u8, 7), max_unsigned.len);
}

test "decode C7 memory immediate sign extends to 64 bits" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0xC7, 0x00, 0xFF, 0xFF, 0xFF, 0xFF });
    try std.testing.expectEqual(Op.mov_mem64_imm32, decoded.op);
    try std.testing.expectEqual(Size.bits64, decoded.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.sib_base_reg);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), decoded.imm);
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
