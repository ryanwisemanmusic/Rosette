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
const import_resolution = @import("resolution/import_engine.zig");
const initialization_resolution = @import("resolution/initialization_engine.zig");
const initializer_dependency = @import("resolution/initializer_dependency.zig");
const abi_data_materializer = @import("resolution/abi_data_materializer.zig");
const memory_transaction = @import("resolution/memory_transaction.zig");
const dynamic_library_forwarder = @import("resolution/dynamic_library_forwarder.zig");
const guest_memory_geometry = @import("resolution/guest_memory_geometry.zig");
const lazy_import_stub = @import("resolution/lazy_import_stub.zig");
const smart_stub_generator = @import("resolution/smart_stub_generator.zig");
const cxx_exception_diagnostics = @import("resolution/cxx_exception_diagnostics.zig");
const spirv_cross_diagnostics = @import("resolution/spirv_cross_diagnostics.zig");
const fs_io_forwarder = @import("resolution/fs_io_forwarder.zig");
const memory_management_forwarder = @import("resolution/memory_management_forwarder.zig");
const sparse_virtual_memory = @import("resolution/sparse_virtual_memory.zig");
const memory_provenance = @import("resolution/memory_provenance.zig");
const pointer_firewall = @import("resolution/pointer_firewall.zig");
const semantic_fault_classifier = @import("resolution/semantic_fault_classifier.zig");
const opaque_lifetime_recovery = @import("resolution/opaque_lifetime_recovery.zig");
const libcpp_shared_control_block = @import("resolution/libcpp_shared_control_block.zig");
const launch_argument_accelerator = @import("resolution/launch_argument_accelerator.zig");
const startup_observer = @import("resolution/startup_observer.zig");
const itanium_unwinder = @import("resolution/itanium_unwinder.zig");
const itanium_dynamic_cast = @import("resolution/itanium_dynamic_cast.zig");
const libcpp_filesystem = @import("resolution/libcpp_filesystem.zig");
const libcpp_stream_bridge = @import("resolution/libcpp_stream_bridge.zig");
const vtt_resolution = @import("resolution/vtt_resolver.zig");
const foreign_object_runtime = @import("resolution/foreign_object_runtime.zig");
const native_window_runtime = @import("resolution/native_window_runtime.zig");
const logging_runtime = @import("resolution/logging_runtime.zig");
const x64_backend_diagnostics = @import("resolution/x64_backend_diagnostics.zig");
const guest_assertion_recovery = @import("resolution/guest_assertion_recovery.zig");
const atomic_compare_exchange = @import("resolution/atomic_compare_exchange.zig");
const diagnostic_throttle = @import("resolution/diagnostic_throttle.zig");
const pthread_runtime = @import("resolution/pthread_runtime.zig");
const runtime_output = @import("resolution/runtime_output.zig");
const tlv_runtime = @import("resolution/tlv_runtime.zig");
const diagnostic_text_accelerator = @import("resolution/diagnostic_text_accelerator.zig");
const symbol_assembly_context = @import("resolution/symbol_assembly_context.zig");
const export_table_manager = @import("resolution/export_table_manager.zig");
const export_table_lifecycle = @import("resolution/export_table_lifecycle.zig");
const dynamic_export_registry = @import("resolution/dynamic_export_registry.zig");
const thread_wait_profiler = @import("resolution/thread_wait_profiler.zig");
const contract = @import("contract");
const scheduler = @import("scheduler");

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
const BOUND_IMPORT_THUNK_STRIDE = constants.BOUND_IMPORT_THUNK_STRIDE;
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
const SA_RESETHAND = constants.SA_RESETHAND;
const SA_NODEFER = constants.SA_NODEFER;
const SA_SIGINFO = constants.SA_SIGINFO;
const GUEST_SIGNAL_ACTION_COUNT = constants.GUEST_SIGNAL_ACTION_COUNT;
const GUEST_SIGNAL_FRAME_DEPTH = constants.GUEST_SIGNAL_FRAME_DEPTH;
const DARWIN_SIGACTION_SIZE = constants.DARWIN_SIGACTION_SIZE;
const DARWIN_SIGINFO_SIZE = constants.DARWIN_SIGINFO_SIZE;
const DARWIN_UCONTEXT_SIZE = constants.DARWIN_UCONTEXT_SIZE;
const DARWIN_MCONTEXT_SIZE = constants.DARWIN_MCONTEXT_SIZE;
const PROFILE_ACCOUNT_INFO_BYTES = constants.PROFILE_ACCOUNT_INFO_BYTES;
const PROFILE_ENCRYPTED_ACCOUNT_BYTES = constants.PROFILE_ENCRYPTED_ACCOUNT_BYTES;
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
    atomic_cmpxchg8: atomic_compare_exchange.Stats = .{},
    classified_ud2_recoveries: u64 = 0,
    timer_recovery_tracker: guest_assertion_recovery.TimerRecoveryTracker = .{},
    export_table_mgr: export_table_manager.Manager = .{},
    export_table_lc: export_table_lifecycle.Lifecycle = .{},
    export_registry: dynamic_export_registry.Registry = .{},
    wait_profiler: thread_wait_profiler.WaitProfileSystem = .{},
    breakpoint_cleanup_recoveries: u64 = 0,
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
    opaque_destructor_quarantines: u64 = 0,
    cooperative_starvation_warnings: u64 = 0,
    last_cooperative_starvation_step: u64 = 0,
    ui_callback_retained_quanta: u64 = 0,
    cooperative_quantum_steps: u64 = 0,
    cooperative_bootstrap_trace_remaining: u8 = 0,
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
    tlv: tlv_runtime.Runtime = .{},
    diagnostic_text: diagnostic_text_accelerator.Engine = .{},
    memory_forwarder: memory_management_forwarder.Manager,
    sparse_memory: sparse_virtual_memory.Manager,
    memory_regions: memory_provenance.Registry,
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
    page_entry_bulk_initializations: u64 = 0,
    page_entry_bulk_bytes: u64 = 0,
    initializer_memory: memory_transaction.Journal,
    initializer_checkpoint: ?InitializerCheckpoint = null,
    trace_entries: [TRACE_BUFFER_LEN]TraceEntry = [_]TraceEntry{TraceEntry{}} ** TRACE_BUFFER_LEN,
    trace_index: usize = 0,
    trace_filled: bool = false,
    trace_range_start: ?u64 = null,
    trace_range_end: ?u64 = null,
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

    pub fn deinit(self: *MachOState) void {
        self.scheduler_log.close();
        self.guest_time.deinit(self.allocator);
        self.closeGuestFiles();
        self.libcxx_streams.deinit();
        self.local_libcpp_stream_targets.deinit();
        self.import_resolver.deinit();
        self.initializer_resolver.deinit();
        self.vtt_resolver.deinit();
        self.dynamic_forwarder.deinit();
        self.native_window.deinit();
        self.fs_forwarder.deinit();
        self.memory_forwarder.deinit();
        self.sparse_memory.deinit();
        self.memory_regions.deinit();
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
                        std.debug.print(
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
                const thunk_address = BOUND_IMPORT_THUNK_BASE + @as(u64, @intCast(thunks.items.len)) * BOUND_IMPORT_THUNK_STRIDE;
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
                    std.debug.print(
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
                std.debug.print(
                    "macho-processor: Capstone runtime callback binding: slot={s} address=0x{x} import={s} target=0x{x} section={s} repaired_null={}\n",
                    .{ slot_name, binding.address, binding.name, target, section.name, existing == 0 },
                );
            }
        }

        self.bound_import_thunks = try thunks.toOwnedSlice(self.allocator);
        for (self.bound_import_thunks) |thunk| {
            self.registerSyntheticThunk(thunk.address, BOUND_IMPORT_THUNK_STRIDE, thunk.name);
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
                            std.debug.print(
                                "macho-processor: unresolved ABI data fallback sample: address=0x{x} symbol={s} action=self_sentinel host_lookup=missing\n",
                                .{ item.address, item.symbol },
                            );
                            sentinel_samples += 1;
                        }
                    }
                }
                if (synthetic_count > 0) {
                    std.debug.print(
                        "macho-processor: guest ABI data materialized: bindings={d} unique(typeinfo/type_name/vtable/construction_vtable/vtt/guard/reference_temporary)={d}/{d}/{d}/{d}/{d}/{d}/{d}; relocation addends preserved\n",
                        .{ synthetic_count, category_counts[@intFromEnum(abi_data_materializer.Category.typeinfo)], category_counts[@intFromEnum(abi_data_materializer.Category.type_name)], category_counts[@intFromEnum(abi_data_materializer.Category.vtable)], category_counts[@intFromEnum(abi_data_materializer.Category.construction_vtable)], category_counts[@intFromEnum(abi_data_materializer.Category.vtt)], category_counts[@intFromEnum(abi_data_materializer.Category.guard)], category_counts[@intFromEnum(abi_data_materializer.Category.reference_temporary)] },
                    );
                }
                if (sentinel_count > 0) {
                    std.debug.print(
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
                std.debug.print(
                    "macho-processor: resolved {d} deferred ABI data binding(s) via host symbol lookup\n",
                    .{resolved},
                );
            }
        }

        std.debug.print(
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
        std.debug.print("  Capstone runtime callback state ({s}):\n", .{reason});
        for (slots) |slot| {
            const address = self.metadata.definedSymbolAddress(slot) orelse {
                std.debug.print("    {s}: symbol_missing\n", .{slot});
                continue;
            };
            present += 1;
            const target = self.read64(address);
            if (target != 0) nonzero += 1;
            if (self.metadata.importAtStub(target)) |imported| {
                std.debug.print("    {s}: address=0x{x} target=0x{x} import={s}@{s}\n", .{ slot, address, target, imported.name, imported.dylib });
            } else if (self.metadata.nearestSymbol(target)) |symbol| {
                std.debug.print("    {s}: address=0x{x} target=0x{x} symbol={s}+0x{x}\n", .{ slot, address, target, symbol.name, symbol.offset });
            } else {
                std.debug.print("    {s}: address=0x{x} target=0x{x} unresolved={}\n", .{ slot, address, target, target != 0 });
            }
        }
        std.debug.print("    summary: symbols={d}/5 nonzero={d}/5 cs_open_requires_all_nonzero=true\n", .{ present, nonzero });
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
        const sparse_mapped = self.sparse_memory.contains(address, size);
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

    fn isExecutableAddress(self: *const MachOState, address: u64) bool {
        return self.sparse_memory.isExecutable(address, 1) or self.translateGuest(address, 1, .execute) != null;
    }

    fn diagnosticSymbol(self: *const MachOState, address: u64) ?exit_diagnostics.SymbolizedAddress {
        if (address == 0) return null;
        const symbol = self.metadata.nearestSymbol(address) orelse return null;
        return .{
            .address = address,
            .symbol = symbol.name,
            .symbol_offset = symbol.offset,
        };
    }

    pub fn read8(self: *const MachOState, vaddr: u64) u8 {
        if (self.sparse_memory.bytesConst(vaddr, 1)) |bytes| return bytes[0];
        const off = self.translateGuest(vaddr, 1, .read) orelse return 0;
        return self.mem[off];
    }

    pub fn read16(self: *const MachOState, vaddr: u64) u16 {
        if (self.sparse_memory.bytesConst(vaddr, 2)) |bytes| return std.mem.readInt(u16, bytes[0..2], .little);
        const off = self.translateGuest(vaddr, 2, .read) orelse return 0;
        return std.mem.readInt(u16, self.mem[off..][0..2], .little);
    }

    pub fn read32(self: *const MachOState, vaddr: u64) u32 {
        if (self.sparse_memory.bytesConst(vaddr, 4)) |bytes| return std.mem.readInt(u32, bytes[0..4], .little);
        const off = self.translateGuest(vaddr, 4, .read) orelse return 0;
        return std.mem.readInt(u32, self.mem[off..][0..4], .little);
    }

    pub fn read64(self: *const MachOState, vaddr: u64) u64 {
        if (self.sparse_memory.bytesConst(vaddr, 8)) |bytes| return std.mem.readInt(u64, bytes[0..8], .little);
        const off = self.translateGuest(vaddr, 8, .read) orelse return 0;
        return std.mem.readInt(u64, self.mem[off..][0..8], .little);
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
        if (self.sparse_memory.bytes(vaddr, 8, true)) |bytes| {
            std.mem.writeInt(u64, bytes[0..8], val, .little);
            return;
        }
        const off = self.translateGuest(vaddr, 8, .write) orelse return;
        if (off + 8 <= self.mem.len) {
            self.initializer_memory.capture(self.mem, @intCast(off), 8);
            self.noteGuestWrite(vaddr, 8);
            std.mem.writeInt(u64, self.mem[off..][0..8], val, .little);
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
        if (self.sparse_memory.bytesConst(addr, bytes)) |storage| {
            const value: u64 = switch (size) {
                .bits8 => storage[0],
                .bits16 => std.mem.readInt(u16, storage[0..2], .little),
                .bits32 => std.mem.readInt(u32, storage[0..4], .little),
                .bits64 => std.mem.readInt(u64, storage[0..8], .little),
            };
            self.recordMemoryAccess(addr, size, "read", value);
            return value;
        }
        const off = self.translateGuest(addr, bytes, .read) orelse {
            self.terminateForGuestAccess(addr, bytes, .read, @tagName(self.trace_entries[if (self.trace_index == 0) TRACE_BUFFER_LEN - 1 else self.trace_index - 1].op));
            return 0;
        };
        const value: u64 = switch (size) {
            .bits8 => self.mem[off],
            .bits16 => std.mem.readInt(u16, self.mem[off..][0..2], .little),
            .bits32 => std.mem.readInt(u32, self.mem[off..][0..4], .little),
            .bits64 => std.mem.readInt(u64, self.mem[off..][0..8], .little),
        };
        self.recordMemoryAccess(addr, size, "read", value);
        return value;
    }

    pub fn writeMemVal(self: *MachOState, addr: u64, size: Size, val: u64) void {
        const bytes = bytesForSize(size);
        if (self.sparse_memory.bytes(addr, bytes, true)) |storage| {
            self.recordMemoryAccess(addr, size, "write", val);
            switch (size) {
                .bits8 => storage[0] = @truncate(val),
                .bits16 => std.mem.writeInt(u16, storage[0..2], @truncate(val), .little),
                .bits32 => std.mem.writeInt(u32, storage[0..4], @truncate(val), .little),
                .bits64 => std.mem.writeInt(u64, storage[0..8], val, .little),
            }
            return;
        }
        const off = self.translateGuest(addr, bytes, .write) orelse {
            if (self.deferInitializerRuntimeDependency(addr, size)) return;
            self.terminateForGuestAccess(addr, bytes, .write, @tagName(self.trace_entries[if (self.trace_index == 0) TRACE_BUFFER_LEN - 1 else self.trace_index - 1].op));
            return;
        };
        self.recordMemoryAccess(addr, size, "write", val);
        self.initializer_memory.capture(self.mem, @intCast(off), bytes);
        self.noteGuestWrite(addr, bytes);
        switch (size) {
            .bits8 => self.mem[off] = @truncate(val),
            .bits16 => std.mem.writeInt(u16, self.mem[off..][0..2], @truncate(val), .little),
            .bits32 => std.mem.writeInt(u32, self.mem[off..][0..4], @truncate(val), .little),
            .bits64 => std.mem.writeInt(u64, self.mem[off..][0..8], val, .little),
        }
    }

    fn bytesForSize(size: Size) u8 {
        return switch (size) {
            .bits8 => 1,
            .bits16 => 2,
            .bits32 => 4,
            .bits64 => 8,
        };
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
                std.debug.print(
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

    fn decodeTraceInstruction(self: *const MachOState, entry: TraceEntry) ?DecodedInsn {
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

    fn writeExtendedFloat80(destination: []u8, value: f64) void {
        std.debug.assert(destination.len >= 10);
        @memset(destination[0..10], 0);
        const bits: u64 = @bitCast(value);
        const sign: u16 = if ((bits >> 63) != 0) 0x8000 else 0;
        const fraction = bits & 0x000F_FFFF_FFFF_FFFF;
        const exponent: u16 = @truncate((bits >> 52) & 0x7FF);
        if (exponent == 0 and fraction == 0) return;
        if (exponent == 0x7FF) {
            const significand: u64 = if (fraction == 0) 0x8000_0000_0000_0000 else 0xC000_0000_0000_0000;
            std.mem.writeInt(u64, destination[0..8], significand, .little);
            std.mem.writeInt(u16, destination[8..10], sign | 0x7FFF, .little);
            return;
        }
        var significand: u64 = 0;
        var unbiased: i32 = 0;
        if (exponent == 0) {
            // A binary64 subnormal has no hidden bit. Normalize its leading
            // set bit into x87's explicit integer bit at position 63.
            const shift: u6 = @intCast(@clz(fraction));
            significand = fraction << shift;
            unbiased = -1011 - @as(i32, shift);
        } else {
            significand = (fraction | (@as(u64, 1) << 52)) << 11;
            unbiased = @as(i32, exponent) - 1023;
        }
        std.mem.writeInt(u64, destination[0..8], significand, .little);
        std.mem.writeInt(u16, destination[8..10], sign | @as(u16, @intCast(unbiased + 16383)), .little);
    }

    fn ensureGuestAccess(self: *MachOState, address: u64, bytes: u8, access: GuestAccess, instruction: []const u8) bool {
        if (access == .read and self.sparse_memory.bytesConst(address, bytes) != null) return true;
        if (access == .write and self.sparse_memory.bytes(address, bytes, true) != null) return true;
        if (access == .execute and self.sparse_memory.isExecutable(address, bytes)) return true;
        if (self.translateGuest(address, bytes, access) != null) return true;
        self.terminateForGuestAccess(address, bytes, access, instruction);
        return false;
    }

    fn terminateForGuestAccess(self: *MachOState, address: u64, bytes: u8, access: GuestAccess, instruction: []const u8) void {
        if (self.terminal_memory_failure != null) return;
        if (self.tryQuarantineOpaqueDestructor(address)) return;
        if (!self.toml_fault_diagnostics_dumped) {
            if (self.metadata.nearestSymbol(self.regs.rip)) |symbol| {
                const toml_symbol = std.mem.indexOf(u8, symbol.name, "toml") != null;
                const patch_db_symbol = std.mem.indexOf(u8, symbol.name, "PatchDB") != null or
                    std.mem.indexOf(u8, symbol.name, "patcher") != null;
                if (toml_symbol or patch_db_symbol) {
                    self.toml_fault_diagnostics_dumped = true;
                    std.debug.print(
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
        const description = self.describeGuestAccess(address, bytes, access);
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
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.memory_access_violation);
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
        std.debug.print(
            "macho-processor: opaque lifetime quarantine #{d}: destructor={s} this=0x{x} owner={s} restored_caller=0x{x} via={s}; skipped invalid guest cleanup without dereferencing API identity\n",
            .{ self.opaque_destructor_quarantines, symbol.name, address, policy.owner, return_address, restored_via },
        );
        return true;
    }

    fn dumpTerminalAddressProvenance(self: *const MachOState, effective_address: u64) void {
        const bytes = self.guestMemoryConst(self.regs.rip, 16) orelse return;
        const decoded = decodeInsn(bytes);
        if (!decoded.sib_has_base and !decoded.sib_has_index and !decoded.rip_relative) {
            std.debug.print(
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
        std.debug.print(
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
                std.debug.print(
                    "macho-processor: near-null {s} register transition: thread=0x{x} register={s} before=0x{x} after=0x{x} caused_by=0x{x} {s}+0x{x} op={s} same_thread_distance={d} cross_thread_entries_excluded={d}\n",
                    .{ role, fault_thread, @tagName(register), before, after, entry.rip, if (symbol) |resolved| resolved.name else "<unknown>", if (symbol) |resolved| resolved.offset else 0, @tagName(entry.op), same_thread_entries, excluded_entries },
                );
                return;
            }
            after = before;
        }
        std.debug.print(
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

    fn registerNativeWindowHandles(self: *MachOState) void {
        if (self.native_window_handles_registered) return;
        self.registerOpaqueHandle(native_window_runtime.APPLICATION_TOKEN, "native NSApplication identity");
        self.registerOpaqueHandle(native_window_runtime.WINDOW_TOKEN, "native NSWindow identity");
        self.registerOpaqueHandle(native_window_runtime.VIEW_TOKEN, "native NSView identity");
        self.registerOpaqueHandle(native_window_runtime.METAL_LAYER_TOKEN, "native CAMetalLayer identity");
        self.native_window_handles_registered = true;
    }

    pub fn ensureNativeApplication(self: *MachOState) bool {
        const ready = self.native_window.ensureApplication();
        if (ready) self.registerNativeWindowHandles();
        return ready;
    }

    pub fn ensureNativeWindow(self: *MachOState) bool {
        const ready = self.native_window.ensureWindow();
        if (ready) self.registerNativeWindowHandles();
        return ready;
    }

    pub fn setNativeWindowTitle(self: *MachOState, title: []const u8) bool {
        const ready = self.native_window.setTitle(title);
        if (ready) self.registerNativeWindowHandles();
        return ready;
    }

    pub fn setNativeWindowSize(self: *MachOState, width: i32, height: i32) bool {
        const ready = self.native_window.setSize(width, height);
        if (ready) self.registerNativeWindowHandles();
        return ready;
    }

    pub fn showNativeWindow(self: *MachOState) bool {
        const ready = self.native_window.show();
        if (ready) self.registerNativeWindowHandles();
        return ready;
    }

    pub fn setNativeWindowFullscreen(self: *MachOState, fullscreen: bool) bool {
        return self.native_window.setFullscreen(fullscreen);
    }

    pub fn nativeViewToken(self: *MachOState) u64 {
        const token = self.native_window.viewToken();
        if (token != 0) self.registerNativeWindowHandles();
        return token;
    }

    pub fn nativeWindowWidth(self: *MachOState) u32 {
        return self.native_window.width();
    }

    pub fn nativeWindowHeight(self: *MachOState) u32 {
        return self.native_window.height();
    }

    pub fn validateNativeMetalLayerToken(self: *MachOState, token: u64) bool {
        return self.native_window.validateLayerToken(token);
    }

    pub fn nativeMetalLayerHostPointer(self: *MachOState) usize {
        return self.native_window.hostMetalLayer();
    }

    pub fn noteNativeVulkanSurfaceBound(self: *MachOState, layer_token: u64, guest_surface: u64, host_surface: u64) void {
        self.native_window.noteSurfaceBound(layer_token, guest_surface, host_surface);
    }

    fn pumpNativeWindowEvents(self: *MachOState) void {
        if (self.native_window.application_ensure_attempts == 0) return;
        _ = self.native_window.pumpEvents();
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
    }

    pub fn guestHeapContains(self: *const MachOState, address: u64) bool {
        return self.memory_forwarder.allocationSize(address) != null;
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
        std.debug.print(
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

    pub fn guestCString(self: *const MachOState, addr: u64, max_len: usize) ?[]const u8 {
        if (addr == 0) return null;
        const off = self.translateGuest(addr, 1, .read) orelse return null;
        const off_usize: usize = @intCast(off);
        if (off_usize >= self.mem.len) return null;
        const available = self.mem[off_usize..@min(self.mem.len, off_usize + max_len)];
        const end = std.mem.indexOfScalar(u8, available, 0) orelse return null;
        return available[0..end];
    }

    fn cxxExceptionTypeName(self: *const MachOState, type_info_address: u64) ?[]const u8 {
        const name_address = self.read64(type_info_address +| 8);
        return self.guestCString(name_address, 4096);
    }

    fn cxxExceptionMessage(self: *const MachOState, object_address: u64) ?[]const u8 {
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

    fn standardStreamPointer(self: *MachOState, symbol_name: []const u8) ?u64 {
        const stream: struct { slot: *u64, handle: u64 } = if (std.mem.eql(u8, symbol_name, "___stdinp"))
            .{ .slot = &self.guest_stdin_pointer_address, .handle = GUEST_FILE_BASE }
        else if (std.mem.eql(u8, symbol_name, "___stdoutp"))
            .{ .slot = &self.guest_stdout_pointer_address, .handle = GUEST_FILE_BASE + 1 }
        else if (std.mem.eql(u8, symbol_name, "___stderrp"))
            .{ .slot = &self.guest_stderr_pointer_address, .handle = GUEST_FILE_BASE + 2 }
        else
            return null;
        if (stream.slot.* == 0) {
            stream.slot.* = self.guestAlloc(@sizeOf(u64), @alignOf(u64)) orelse return null;
            self.write64(stream.slot.*, stream.handle);
        }
        return stream.slot.*;
    }

    fn configureGuestLogMirror(self: *MachOState, args: []const []const u8) void {
        std.debug.print("ROSETTE: configureGuestLogMirror called\n", .{});
        const prefix = "--log_file=";
        var found_log_file = false;
        for (args) |arg| {
            if (!std.mem.startsWith(u8, arg, prefix) or arg.len == prefix.len) continue;
            const path = arg[prefix.len..];
            std.debug.print("ROSETTE: Found --log_file= argument: '{s}'\n", .{path});
            found_log_file = true;
            const path_z = self.allocator.dupeZ(u8, path) catch return;
            defer self.allocator.free(path_z);
            const flags = parseFopenFlags("a") orelse return;
            const fd = std.c.open(
                path_z.ptr,
                @bitCast(@as(u32, @intCast(flags))),
                @as(c_int, 0o666),
            );
            if (fd < 0) {
                std.debug.print("ROSETTE: guest log mirror could not open {s}\n", .{path});
                return;
            }
            if (self.guest_log_mirror_fd >= 0) _ = std.c.close(self.guest_log_mirror_fd);
            self.guest_log_mirror_fd = fd;
            std.debug.print(
                "ROSETTE: guest log mirror configured: {s}; captures synchronous Xenia logs and modeled guest stdout/stderr\n",
                .{path},
            );
            return;
        }
        if (!found_log_file) {
            std.debug.print("ROSETTE: No --log_file= argument found - Xenia logs will not be mirrored to file\n", .{});
            std.debug.print("ROSETTE: Add --log_file=/path/to/log.txt to capture Xenia output\n", .{});
        }
    }

    fn hostWriteFdAll(fd: i32, bytes: []const u8) bool {
        if (fd < 0) return false;
        var written: usize = 0;
        while (written < bytes.len) {
            const result = std.c.write(fd, bytes.ptr + written, bytes.len - written);
            if (result <= 0) return false;
            written += @intCast(result);
        }
        return true;
    }

    fn shouldSummarizeGuestLog(level: u8, message: []const u8) bool {
        if (level == 'F' or level == 'E' or level == 'e' or level == 'W' or level == 'w') return true;
        const markers = [_][]const u8{
            "RunTitle",
            "LaunchPath",
            "LaunchDiscImage",
            "CompleteLaunch",
            "MountPath",
            "GetFileSignature",
            "DiscImage",
            "UserModule",
            "XexModule",
            "LoadUserModule",
            "LaunchModule",
            "SetExecutableModule",
            "GraphicsSystem",
            "VulkanPresenter",
            "RING BUFFER",
            "main thread",
            "stage=",
            "FAILED",
            "failed",
            "assert",
        };
        for (markers) |marker| {
            if (std.mem.indexOf(u8, message, marker) != null) return true;
        }
        return false;
    }

    fn emitRuntimeSummaryHeartbeat(self: *const MachOState, snapshot: startup_observer.Snapshot) void {
        if (self.summary_output_fd < 0) return;
        var buffer: [2048]u8 = undefined;
        const line = std.fmt.bufPrint(
            &buffer,
            "step={d} heartbeat thread=0x{x} rip=0x{x} symbol={s}+0x{x} heap=0x{x} imports={d} fs_open/read/write={d}/{d}/{d} runnable={d} blocked={d} condvar_waits={d}\n",
            .{
                snapshot.step,
                snapshot.thread_id,
                snapshot.rip,
                snapshot.symbol,
                snapshot.symbol_offset,
                snapshot.heap_next,
                snapshot.import_calls,
                snapshot.fs_open,
                snapshot.fs_read,
                snapshot.fs_write,
                self.pthreads.activeCount(),
                snapshot.pthread_blocked,
                snapshot.pthread_waits_collapsed,
            },
        ) catch return;
        _ = hostWriteFdAll(self.summary_output_fd, line);
    }

    fn emitGuestLog(self: *MachOState, prefix_char_raw: u64, address: u64, length_raw: u64) bool {
        const length = @min(length_raw, GUEST_LOG_BUFFER_SIZE);
        const message = self.guestMemoryConst(address, length) orelse return false;
        self.observeBackendGuestLog(message);
        const raw_char: u8 = @truncate(prefix_char_raw);
        const prefix_char: u8 = if (raw_char >= 0x20 and raw_char <= 0x7E) raw_char else '?';
        var prefix_buffer: [32]u8 = undefined;
        const prefix = std.fmt.bufPrint(&prefix_buffer, "[xenia] {c}> ", .{prefix_char}) catch return false;

        _ = hostWriteFdAll(self.diagnostic_output_fd, prefix);
        _ = hostWriteFdAll(self.diagnostic_output_fd, message);
        if (message.len == 0 or message[message.len - 1] != '\n') _ = hostWriteFdAll(self.diagnostic_output_fd, "\n");
        if (self.summary_output_fd >= 0 and shouldSummarizeGuestLog(prefix_char, message)) {
            var step_buffer: [64]u8 = undefined;
            const step_prefix = std.fmt.bufPrint(&step_buffer, "step={d} ", .{self.executed_steps}) catch "";
            _ = hostWriteFdAll(self.summary_output_fd, step_prefix);
            _ = hostWriteFdAll(self.summary_output_fd, prefix);
            _ = hostWriteFdAll(self.summary_output_fd, message);
            if (message.len == 0 or message[message.len - 1] != '\n') _ = hostWriteFdAll(self.summary_output_fd, "\n");
        }

        if (std.mem.startsWith(u8, message, "HostPathDevice::ResolvePath(User_")) {
            const storage_root = self.fs_forwarder.storageRoot();
            std.debug.print(
                "macho-processor: profile resolution trace: Xenia is resolving an internal User_<profile-id>: device; storage_root={s}; this is before any host open syscall\n",
                .{if (storage_root.len != 0) storage_root else "<not configured>"},
            );
            if (profileIdFromUserDevice(message)) |profile_id| {
                self.logProfileHostPreflight(profile_id);
            }
        }
        if (std.mem.indexOf(u8, message, "Failed to open Account file: C000000F") != null) {
            if (self.profile_account_flow.active) self.profile_account_flow.stage = .open_failed;
            std.debug.print(
                "macho-processor: profile resolution failure: X_STATUS_NO_SUCH_FILE (0xC000000F); the Xenia User_<profile-id>: device has no Account-file backing path. Check the following fs open/status diagnostics for a host-path attempt; if none follows, the missing mapping is inside Xenia's virtual device layer.\n",
                .{},
            );
        }
        if (std.mem.indexOf(u8, message, "Failed to decrypt account data file for XUID") != null) {
            if (self.profile_account_flow.active) self.profile_account_flow.stage = .decrypt_failed;
            std.debug.print(
                "macho-processor: profile crypto diagnosis: both retail and devkit Account HMAC/RC4 verification paths rejected the 404-byte payload; this is a real Account failure, unlike a success-path device dismount\n",
                .{},
            );
        }
        if (std.mem.startsWith(u8, message, "Unregistered device: User_")) {
            const stage = self.profile_account_flow.stage;
            std.debug.print(
                "macho-processor: profile device lifecycle: temporary User_<profile-id>: mount was unregistered at stage={s}; interpretation={s}\n",
                .{ @tagName(stage), if (stage == .decrypted or stage == .inserting or stage == .completed) "expected LoadAccount cleanup after successful Account decryption; the decoded account remains eligible for accounts_ insertion" else "early cleanup associated with an incomplete Account load" },
            );
        }

        if (self.guest_log_mirror_fd >= 0) {
            _ = hostWriteFdAll(self.guest_log_mirror_fd, prefix);
            _ = hostWriteFdAll(self.guest_log_mirror_fd, message);
            if (message.len == 0 or message[message.len - 1] != '\n') {
                _ = hostWriteFdAll(self.guest_log_mirror_fd, "\n");
            }
        }
        self.guest_log_line_count +|= 1;
        return true;
    }

    fn logProfileHostPreflight(self: *MachOState, profile_id: []const u8) void {
        self.profile_host_preflight_checks +|= 1;
        const storage_root = self.fs_forwarder.storageRoot();
        if (storage_root.len == 0) {
            std.debug.print(
                "macho-processor: profile host preflight #{d}: profile={s} unavailable because no storage root is configured\n",
                .{ self.profile_host_preflight_checks, profile_id },
            );
            return;
        }

        var path_buffer: [4096]u8 = undefined;
        const account_path = std.fmt.bufPrint(
            &path_buffer,
            "{s}/content/{s}/FFFE07D1/00010000/{s}/Account",
            .{ storage_root, profile_id, profile_id },
        ) catch {
            std.debug.print(
                "macho-processor: profile host preflight #{d}: profile={s} expected Account path exceeds diagnostic buffer\n",
                .{ self.profile_host_preflight_checks, profile_id },
            );
            return;
        };
        const file_stat = std.Io.Dir.cwd().statFile(self.io, account_path, .{}) catch |err| {
            std.debug.print(
                "macho-processor: profile host preflight #{d}: profile={s} account={s} host_status={s}; VFS failure may be genuine\n",
                .{ self.profile_host_preflight_checks, profile_id, account_path, @errorName(err) },
            );
            return;
        };
        std.debug.print(
            "macho-processor: profile host preflight #{d}: profile={s} account={s} host_status=present kind={s} bytes={d}; a later C000000F without an Account open is a guest VFS path-resolution failure\n",
            .{ self.profile_host_preflight_checks, profile_id, account_path, @tagName(file_stat.kind), file_stat.size },
        );
    }

    fn observeProfileAccountFlow(self: *MachOState) void {
        const load_entry = self.internal_targets.profile_manager_load_account;
        if (load_entry != 0 and self.regs.rip == load_entry) {
            const return_address = if (self.guestMemoryConst(self.regs.rsp, 8) != null) self.read64(self.regs.rsp) else 0;
            self.profile_account_flow.active = true;
            self.profile_account_flow.manager = self.regs.rdi;
            self.profile_account_flow.xuid = self.regs.rsi;
            self.profile_account_flow.return_address = return_address;
            self.profile_account_flow.started_step = self.executed_steps;
            self.profile_account_flow.stage = .loading;
            self.profile_account_flow.account_guest_fd = std.math.maxInt(u64);
            self.profile_account_flow.requested_bytes = 0;
            self.profile_account_flow.bytes_read = 0;
            self.profile_account_flow.attempts +|= 1;
            const caller = if (return_address != 0) self.metadata.nearestSymbol(return_address) else null;
            std.debug.print(
                "macho-processor: profile Account flow #{d} started: manager=0x{x} xuid={x:0>16} return=0x{x} {s}+0x{x} step={d}\n",
                .{ self.profile_account_flow.attempts, self.regs.rdi, self.regs.rsi, return_address, if (caller) |symbol| symbol.name else "<unknown>", if (caller) |symbol| symbol.offset else 0, self.executed_steps },
            );
            return;
        }

        if (!self.profile_account_flow.active) return;

        const dismount_entry = self.internal_targets.profile_manager_dismount_profile;
        if (dismount_entry != 0 and self.regs.rip == dismount_entry) {
            const return_address = if (self.guestMemoryConst(self.regs.rsp, 8) != null) self.read64(self.regs.rsp) else 0;
            const caller = if (return_address != 0) self.metadata.nearestSymbol(return_address) else null;
            if (caller) |symbol| {
                if (classifyProfileDismountCaller(symbol.name, symbol.offset)) |stage| self.profile_account_flow.stage = stage;
            }
            std.debug.print(
                "macho-processor: profile temporary dismount: xuid={x:0>16} stage={s} caller=0x{x} {s}+0x{x} bytes_read={d} minimum_account_bytes={d} interpretation={s}\n",
                .{ self.profile_account_flow.xuid, @tagName(self.profile_account_flow.stage), return_address, if (caller) |symbol| symbol.name else "<unknown>", if (caller) |symbol| symbol.offset else 0, self.profile_account_flow.bytes_read, PROFILE_ACCOUNT_INFO_BYTES, if (self.profile_account_flow.stage == .decrypted) "expected success-path cleanup before accounts_ insertion" else "early LoadAccount cleanup" },
            );
            return;
        }

        const insert_entry = self.internal_targets.profile_account_insert_or_assign;
        if (insert_entry != 0 and self.regs.rip == insert_entry) {
            self.profile_account_flow.stage = .inserting;
            const key = if (self.guestMemoryConst(self.regs.rsi, 8) != null) self.read64(self.regs.rsi) else 0;
            std.debug.print(
                "macho-processor: profile accounts_ insertion checkpoint: map=0x{x} key_ptr=0x{x} key={x:0>16} account=0x{x} expected_xuid={x:0>16} key_matches={}\n",
                .{ self.regs.rdi, self.regs.rsi, key, self.regs.rdx, self.profile_account_flow.xuid, key == self.profile_account_flow.xuid },
            );
            return;
        }

        if (self.profile_account_flow.return_address != 0 and
            self.regs.rip == self.profile_account_flow.return_address)
        {
            const succeeded = self.regs.rax & 1 != 0;
            if (succeeded) {
                self.profile_account_flow.successes +|= 1;
                self.profile_account_flow.stage = .completed;
            } else {
                self.profile_account_flow.failures +|= 1;
            }
            std.debug.print(
                "macho-processor: profile Account flow completed: xuid={x:0>16} success={} final_stage={s} bytes_read={d}/{d} elapsed_steps={d}; device dismount before this return is {s}\n",
                .{ self.profile_account_flow.xuid, succeeded, @tagName(self.profile_account_flow.stage), self.profile_account_flow.bytes_read, self.profile_account_flow.requested_bytes, self.executed_steps -| self.profile_account_flow.started_step, if (succeeded) "normal and the decoded account is now in accounts_" else "associated with an earlier load failure" },
            );
            self.profile_account_flow.active = false;
            self.profile_account_flow.account_guest_fd = std.math.maxInt(u64);
        }
    }

    fn noteProfileAccountOpen(self: *MachOState, path: []const u8, guest_fd: u64) void {
        const account_path = std.mem.eql(u8, path, "Account") or
            std.mem.endsWith(u8, path, "/Account") or
            std.mem.endsWith(u8, path, "\\Account");
        if (!self.profile_account_flow.active or !account_path) return;
        if (guest_fd == std.math.maxInt(u64)) {
            self.profile_account_flow.stage = .open_failed;
            return;
        }
        self.profile_account_flow.stage = .host_opened;
        self.profile_account_flow.account_guest_fd = guest_fd;
        std.debug.print(
            "macho-processor: profile Account host descriptor bound: xuid={x:0>16} guest_fd={d} stage=host_opened\n",
            .{ self.profile_account_flow.xuid, guest_fd },
        );
    }

    fn noteProfileAccountRead(self: *MachOState, guest_fd: u64, requested: u64, result: i64, offset: u64) void {
        if (!self.profile_account_flow.active or guest_fd != self.profile_account_flow.account_guest_fd) return;
        self.profile_account_flow.requested_bytes +|= requested;
        if (result > 0) self.profile_account_flow.bytes_read +|= @intCast(result);
        self.profile_account_flow.stage = .reading;
        std.debug.print(
            "macho-processor: profile Account read checkpoint: xuid={x:0>16} guest_fd={d} offset={d} requested={d} returned={d} cumulative={d} minimum={d} complete_encrypted_file={}\n",
            .{ self.profile_account_flow.xuid, guest_fd, offset, requested, result, self.profile_account_flow.bytes_read, PROFILE_ACCOUNT_INFO_BYTES, self.profile_account_flow.bytes_read >= PROFILE_ENCRYPTED_ACCOUNT_BYTES },
        );
    }

    fn observeBackendGuestLog(self: *MachOState, message: []const u8) void {
        const observation = self.backend_diagnostics.observeLine(message, self.executed_steps) orelse return;
        const return_address = if (self.guestMemoryConst(self.regs.rsp, 8) != null) self.read64(self.regs.rsp) else 0;
        const caller = if (return_address != 0) self.metadata.nearestSymbol(return_address) else null;
        std.debug.print(
            "macho-processor: x64 backend event #{d}: event={s} phase={s}->{s} step={d} delta={d} active=0x{x} caller=0x{x} {s}+0x{x}\n",
            .{
                observation.sequence,
                @tagName(observation.event),
                @tagName(observation.previous_phase),
                @tagName(observation.phase),
                observation.step,
                observation.delta_steps,
                self.active_guest_thread,
                return_address,
                if (caller) |symbol| symbol.name else "<unknown>",
                if (caller) |symbol| symbol.offset else 0,
            },
        );

        if (observation.event == .indirection_table_failed) {
            const mapping = self.backend_diagnostics.last_mapping;
            if (!mapping.valid) {
                std.debug.print(
                    "macho-processor: x64 code-cache warning correlation: no mmap call was observed after backend initialization began; allocation may have used an unmodeled route\n",
                    .{},
                );
            } else {
                std.debug.print(
                    "macho-processor: x64 code-cache warning correlation: latest mmap route={s} address=0x{x} length={d} prot=0x{x} flags=0x{x} result_known={} succeeded={} result=0x{x} stage={s}\n",
                    .{ mapping.route, mapping.address, mapping.length, mapping.prot, mapping.flags, mapping.result_known, mapping.succeeded, mapping.result, if (mapping.stage.len != 0) mapping.stage else "<pending>" },
                );
                if (mapping.address == 0) {
                    std.debug.print(
                        "macho-processor: x64 code-cache warning interpretation: the macOS guest requested OS-selected placement (address=0), so the guest's 0x80000000-0x9fffffff warning text does not describe the actual mmap hint used on this path\n",
                        .{},
                    );
                }
            }
        }
        if (observation.event == .backend_initialize_succeeded and self.backend_diagnostics.capstone_assertions != 0) {
            std.debug.print(
                "macho-processor: x64 backend recovery evidence: initialization reached completed-successfully after {d} Capstone constructor assertion(s); backend object existence is proven, while Capstone-dependent diagnostics remain degraded\n",
                .{self.backend_diagnostics.capstone_assertions},
            );
        }
    }

    pub fn backendMemoryDiagnosticsActive(self: *const MachOState) bool {
        return self.backend_diagnostics.mappingWindowActive();
    }

    pub fn noteBackendMmapAttempt(self: *MachOState, route: []const u8, address: u64, length: u64, prot: u64, flags: u64, fixed: bool, anonymous: bool) void {
        if (!self.backend_diagnostics.noteMmapAttempt(route, address, length, prot, flags, fixed, anonymous, self.executed_steps)) return;
        const return_address = if (self.guestMemoryConst(self.regs.rsp, 8) != null) self.read64(self.regs.rsp) else 0;
        const caller = if (return_address != 0) self.metadata.nearestSymbol(return_address) else null;
        std.debug.print(
            "macho-processor: x64 backend mmap attempt #{d}: route={s} phase={s} step={d} address=0x{x} length={d} prot=0x{x} flags=0x{x} fixed={} anonymous={} caller=0x{x} {s}+0x{x}\n",
            .{ self.backend_diagnostics.mmap_attempts_during_backend, route, @tagName(self.backend_diagnostics.phase), self.executed_steps, address, length, prot, flags, fixed, anonymous, return_address, if (caller) |symbol| symbol.name else "<unknown>", if (caller) |symbol| symbol.offset else 0 },
        );
    }

    pub fn noteBackendMmapResult(self: *MachOState, succeeded: bool, result: u64, stage: []const u8) void {
        if (!self.backend_diagnostics.last_mapping.valid or self.backend_diagnostics.last_mapping.step != self.executed_steps) return;
        self.backend_diagnostics.noteMmapResult(succeeded, result, stage);
        std.debug.print(
            "macho-processor: x64 backend mmap result: attempt={d} succeeded={} result=0x{x} stage={s}\n",
            .{ self.backend_diagnostics.mmap_attempts_during_backend, succeeded, result, stage },
        );
    }

    pub fn noteBackendMprotect(self: *MachOState, route: []const u8, address: u64, length: u64, prot: u64, succeeded: bool) void {
        if (!self.backend_diagnostics.noteMprotectAttempt()) return;
        std.debug.print(
            "macho-processor: x64 backend mprotect #{d}: route={s} phase={s} step={d} address=0x{x} length={d} prot=0x{x} succeeded={}\n",
            .{ self.backend_diagnostics.mprotect_attempts_during_backend, route, @tagName(self.backend_diagnostics.phase), self.executed_steps, address, length, prot, succeeded },
        );
    }

    fn allocGuestFile(self: *MachOState, fd: i32, kind: GuestFileKind) ?u64 {
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

    fn guestFileFromHandle(self: *MachOState, handle: u64) ?*GuestFile {
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

    fn logControlFlow(self: *const MachOState, kind: []const u8, from_rip: u64, to_rip: u64, decoded_len: u64, return_addr: ?u64) void {
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
        std.debug.print("    [stack backtrace (rsp=0x{x}):\n", .{self.regs.rsp});
        var addr = self.regs.rsp;
        for (0..count) |i| {
            const val = self.read64(addr);
            if (val == 0) {
                std.debug.print("      [{d}] 0x{x}: 0x0\n", .{ i, addr });
            } else if (self.metadata.nearestSymbol(val)) |sym| {
                std.debug.print("      [{d}] 0x{x}: 0x{x} → {s}+0x{x}\n", .{ i, addr, val, sym.name, sym.offset });
            } else {
                std.debug.print("      [{d}] 0x{x}: 0x{x}\n", .{ i, addr, val });
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
                                std.debug.print("  [handled import] {s} from {s}; stub=0x{x} return=0x{x} → rax=0x{x}\n", .{
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
                                std.debug.print(
                                    "  [handled void import] {s} from {s}; stub=0x{x} return=0x{x}\n",
                                    .{ imported.name, imported.dylib, imported.stub_address, synthetic_return },
                                );
                            }
                        },
                        .control_transferred => {
                            self.pending_import_stub_rip = null;
                            if (self.verbose_trace) {
                                std.debug.print(
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
                                std.debug.print(
                                    "  [unresolved import #{d}] {s} from {s}; stub=0x{x} caller={s}+0x{x} return=0x{x} → rax=0x{x}\n",
                                    .{ self.unresolved_import_count, imported.name, imported.dylib, imported.stub_address, caller_sym.name, caller_sym.offset, synthetic_return, self.regs.rax },
                                );
                            } else {
                                std.debug.print(
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
                            std.debug.print("  [terminal import] {s} exit_code={d}\n", .{ imported.name, exit_code });
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

    fn handleImportImpl(self: *MachOState, imported: macho_metadata.ImportedSymbol) ImportHandlerResult {
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
            std.debug.print(
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
                std.debug.print("    [posix] sysconf({d}) -> {d}\n", .{ selector, @as(i64, @bitCast(value)) });
            }
            return .{ .handled = value };
        }
        if (std.mem.eql(u8, name, "_dlopen")) {
            const path = self.guestCString(self.regs.rdi, 1024) orelse return .{ .handled = 0 };
            const handle = self.dynamic_forwarder.openGuest(path, self.regs.rsi);
            if (self.verbose_trace or handle == 0) {
                std.debug.print(
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
                std.debug.print(
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
                std.debug.print(
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
                    std.debug.print("    [local definition] {s}: stub=0x{x} -> target=0x{x}\n", .{ name, imported.stub_address, target });
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
                std.debug.print("    [contract] {s} → {s}", .{ name, if (c) |cc| cc.name else "?" });
                switch (outcome) {
                    .handled => |val| std.debug.print(" ({s}) handled=0x{x}\n", .{ tag, val }),
                    .terminated => |code| std.debug.print(" ({s}) terminated={d}\n", .{ tag, code }),
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
                    std.debug.print("    [contract] WARNING: {s} verification mismatch, using expected\n", .{name});
                    return switch (expected) {
                        .handled => |val| ImportHandlerResult{ .handled = val },
                        .terminated => |code| ImportHandlerResult{ .terminated = code },
                    };
                }
                std.debug.print("    [contract] WARNING: {s} verification mismatch, no expected fallback\n", .{name});
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
            std.debug.print("    [objc] class {s} -> 0x{x}\n", .{ class_name, handle });
            return .{ .handled = handle };
        }
        if (std.mem.eql(u8, name, "_sel_registerName")) {
            const selector_name = self.guestCString(self.regs.rdi, 1024) orelse return .{ .unsupported = 0 };
            const handle = self.compat.selectorNamed(selector_name);
            self.registerOpaqueHandle(handle, "Objective-C selector identity");
            std.debug.print("    [objc] selector {s} -> 0x{x}\n", .{ selector_name, handle });
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
                std.debug.print(
                    "    [objc/native] msgSend receiver=0x{x} class={s} selector={s} argument=0x{x} -> 0x{x} action={s}\n",
                    .{ self.regs.rdi, class_name, selector_name, self.regs.rdx, native_result.value, native_result.action },
                );
                return .{ .handled = native_result.value };
            }
            const result = self.compat.sendMessage(self.regs.rdi, self.regs.rsi);
            if (result.value >= 0xFFFF_0000_0000_0000) self.registerOpaqueHandle(result.value, "Objective-C object identity");
            std.debug.print(
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
                std.debug.print(
                    "macho-processor: repeated guest assertion checkpoint: symbol={s} occurrence={d} suppressed_since_previous={d} total_assertions={d}\n",
                    .{ if (caller) |symbol| symbol.name else function_name, assertion_observation.occurrence, assertion_observation.suppressed_since_emit, self.guest_assertion_count },
                );
            } else if (assertion_observation.disposition == .detail) {
                std.debug.print(
                    "macho-processor: guest assertion #{d}: {s}:{d} {s}: {s}\n",
                    .{ self.guest_assertion_count, file_name, self.regs.rdx, function_name, expression },
                );
                std.debug.print(
                    "  assertion context: step={d} phase={s} active=0x{x} return=0x{x} caller={s}+0x{x} rsp=0x{x} rbp=0x{x}\n",
                    .{ self.executed_steps, @tagName(self.startup.phase), self.active_guest_thread, return_address, if (caller) |symbol| symbol.name else "<unknown>", if (caller) |symbol| symbol.offset else 0, self.regs.rsp, self.regs.rbp },
                );
                if (backend_binding != .none) {
                    std.debug.print(
                        "  x64 backend assertion binding: kind={s} backend_phase={s}\n",
                        .{ @tagName(backend_binding), @tagName(self.backend_diagnostics.phase) },
                    );
                    if (backend_binding == .x64_backend_capstone) {
                        std.debug.print(
                            "  x64 backend assertion cause: source line 139 is the failure branch of cs_open(CS_ARCH_X86, CS_MODE_64, &capstone_handle_); this indicates Capstone initialization failure inside an existing X64Backend constructor, not absence of the backend object\n",
                            .{},
                        );
                        std.debug.print(
                            "  x64 backend assertion impact: Capstone-backed disassembly/introspection is unreliable until proven otherwise; subsequent backend/code-cache/processor success events will be logged as independent readiness evidence\n",
                            .{},
                        );
                        self.dumpCapstoneCallbackState("cs_open assertion");
                    } else if (backend_binding == .x64_backend_low32_thunk) {
                        const mapping = self.backend_diagnostics.last_mapping;
                        std.debug.print(
                            "  x64 backend assertion cause: source line 438 requires resolve_function_thunk_ to fit in uint32_t because every indirection-table entry stores a 32-bit host-code pointer; the generated code cache was placed above the low 4 GiB window\n",
                            .{},
                        );
                        std.debug.print(
                            "  x64 backend assertion impact: continuing would truncate the thunk address and seed every default indirection with an invalid target; backend executable mappings must be rejected unless their end is at or below 0x100000000\n",
                            .{},
                        );
                        std.debug.print(
                            "  x64 backend low-address correlation: latest_mmap(valid/succeeded)={}/{} requested_address=0x{x} length={d} result=0x{x} result_high32=0x{x} stage={s}\n",
                            .{ mapping.valid, mapping.succeeded, mapping.address, mapping.length, mapping.result, mapping.result >> 32, if (mapping.stage.len != 0) mapping.stage else "<pending>" },
                        );
                    }
                    self.dumpGuestStack();
                }
                if (assertion_class == .timer_queue_wait_item_state) {
                    std.debug.print(
                        "  timer queue assertion cause: TimerThreadMain expected WaitItem::State::kDisarmed before its compiler-emitted UD2; this is the primary invariant failure, and a following Processor::OnThreadBreakpointHit assertion is secondary signal-handler fallout\n",
                        .{},
                    );
                    std.debug.print(
                        "  timer queue assertion context: cooperative active_thread=0x{x} deferred_threads={d} suspended_threads={d} pending_idle={d}; inspect wait-item arm/disarm transitions before treating the breakpoint handler as the root cause\n",
                        .{ self.active_guest_thread, self.pthreads.deferred_threads, self.suspended_guest_thread_count, gtkIdleQueueSnapshotFor(&self.gtk_idle_callbacks).pending },
                    );
                    if (guest_assertion_recovery.timerQueueSnapshot(self, self.regs.rbp)) |snapshot| {
                        std.debug.print(
                            "  timer queue state snapshot: frame_state[{s}]={d} at 0x{x} shared_ptr_slot=0x{x} wait_item=0x{x} object_state={s} due_ns={?d} interval_ns={?d}\n",
                            .{ timerQueueStateName(snapshot.frame_state), snapshot.frame_state, snapshot.frame_state_address, snapshot.shared_ptr_address, snapshot.wait_item, if (snapshot.object_state) |state| timerQueueStateName(state) else "<unmapped>", snapshot.due_nanoseconds, snapshot.interval_nanoseconds },
                        );
                        if (snapshot.object_state) |object_state| {
                            if (object_state != snapshot.frame_state) {
                                std.debug.print(
                                    "  timer queue state divergence: compare_exchange expected-output={s}({d}) but live wait_item state={s}({d}); this distinguishes decoder/CAS corruption from a genuinely concurrent state transition\n",
                                    .{ timerQueueStateName(snapshot.frame_state), snapshot.frame_state, timerQueueStateName(object_state), object_state },
                                );
                            }
                        }
                    } else {
                        std.debug.print(
                            "  timer queue state snapshot unavailable: rbp=0x{x}; retaining the assertion as non-recoverable because the modeled CAS state cannot be proven\n",
                            .{self.regs.rbp},
                        );
                    }
                } else if (assertion_class == .breakpoint_untracked_thread) {
                    std.debug.print(
                        "  breakpoint assertion cause: Processor::OnThreadBreakpointHit could not find the current modeled thread in Xenia's thread_debug_infos_ map; the backend exists, but this SIGILL arrived on a Rosette-cooperatively scheduled thread that Xenia's debugger registry does not track\n",
                        .{},
                    );
                    std.debug.print(
                        "  breakpoint assertion impact: this is a secondary failure while handling an earlier UD2. Any subsequent __Unwind_Resume(nullptr) belongs to the failed breakpoint-handler cleanup path and must not be mistaken for the original application fault\n",
                        .{},
                    );
                } else if (assertion_class == .export_ordinal_bounds) {
                    std.debug.print(
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
                                std.debug.print(
                                    "  export ordinal bounds ROOT CAUSE: ordinal={d} >= table_size={d}; values are small and consistent — this is a guest-side export table sizing issue (the export table needs more entries or the ordinal needs updating)\n",
                                    .{ ordinal, size },
                                );
                                if (recovery == .table_was_resized) {
                                    std.debug.print(
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
                                            std.debug.print(
                                                "  export table pre-population: found vector={s} at 0x{x}; scheduling growth to size {d}\n",
                                                .{ vname, addr, ordinal + 1 },
                                            );
                                            _ = self.export_table_lc.requestVectorGrowth(addr, ordinal + 1, 8, vname);
                                        } else {
                                            var sym_buf: [1]u64 = undefined;
                                            const found = self.metadata.symbolAddressesMatching("", vname, &sym_buf);
                                            if (found > 0 and sym_buf[0] != 0) {
                                                _ = self.export_table_lc.requestVectorGrowth(sym_buf[0], ordinal + 1, 8, vname);
                                                std.debug.print(
                                                    "  export table pre-population: found vector={s} at 0x{x} via substring match; scheduling growth to size {d}\n",
                                                    .{ vname, sym_buf[0], ordinal + 1 },
                                                );
                                            } else {
                                                std.debug.print(
                                                    "  export table pre-population: vector={s} not found in symbol table; will fall back to defer+retry\n",
                                                    .{vname},
                                                );
                                            }
                                        }
                                    }
                                }
                            } else {
                                std.debug.print(
                                    "  export ordinal bounds ROOT CAUSE: ordinal={d} >= table_size={d}; values are large or unexpected — this is likely emulator-level memory corruption or a data-structure initialization failure\n",
                                    .{ ordinal, size },
                                );
                            }
                        }
                    }
                    if (!found_pair) {
                        _ = self.export_table_mgr.recordTable(0, 0, 0);
                        std.debug.print(
                            "  export ordinal bounds: no plausible ordinal/size pair found in callee-saved registers (rbx/r12-r15); the values were either computed per-call and not preserved, or the register state was already clobbered\n",
                            .{},
                        );
                        std.debug.print(
                            "  export ordinal bounds raw register state: rbx=0x{x} r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x}\n",
                            .{ self.regs.rbx, self.regs.r12, self.regs.r13, self.regs.r14, self.regs.r15 },
                        );
                    }
                }
            }
            if (self.initializer_resolver.current()) |initializer| {
                std.debug.print(
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
            if (self.verbose_trace) std.debug.print(
                "    [libc++] basic_string::__init(this=0x{x}, source=0x{x}, length={d}) -> {}\n",
                .{ self.regs.rdi, self.regs.rsi, self.regs.rdx, ok },
            );
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6assignEPKc") != null) {
            const source = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const ok = compat_runtime.initLibcppString(self, self.regs.rdi, self.regs.rsi, source.len);
            if (self.verbose_trace) std.debug.print(
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
                std.debug.print(
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
                std.debug.print(
                    "    [libc++] basic_string::compare(this=0x{x}, rhs=0x{x}, rhs_length={d}) -> {d}\n",
                    .{ self.regs.rdi, self.regs.rsi, rhs.len, result },
                );
            }
            return .{ .handled = @as(u32, @bitCast(result)) };
        }

        if (std.mem.eql(u8, name, "___cxa_guard_acquire")) {
            const result = compat_runtime.cxaGuardAcquire(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
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
            if (self.verbose_trace) std.debug.print(
                "    [c++] __cxa_atexit(function=0x{x}, argument=0x{x}, dso=0x{x}) -> {}\n",
                .{ self.regs.rdi, self.regs.rsi, self.regs.rdx, registered },
            );
            return .{ .handled = if (registered) 0 else 1 };
        }
        if (std.mem.eql(u8, name, "_atexit")) {
            const registered = self.compat.registerPlainAtexit(self.regs.rdi);
            if (self.verbose_trace) {
                std.debug.print(
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
            std.debug.print(
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
            std.debug.print("macho-processor: __cxa_begin_catch object=0x{x}\n", .{object_address});
            return .{ .handled = object_address };
        }
        if (std.mem.eql(u8, name, "___cxa_end_catch")) {
            const object_address = self.cxx_exceptions.endCatch();
            if (object_address) |object| {
                std.debug.print("macho-processor: __cxa_end_catch object=0x{x}\n", .{object});
                if (self.unwinder.completeCatch()) {
                    std.debug.print(
                        "macho-processor: Itanium catch transaction completed: object=0x{x}; phase-two checkpoint retired\n",
                        .{object},
                    );
                }
                const spirv_resolution = self.spirv_cross.noteCatch(object);
                if (spirv_resolution == .expected_dummy_probe_caught) {
                    std.debug.print(
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
            std.debug.print(
                "macho-processor: guest raised C++ exception object=0x{x} type_info=0x{x} destructor=0x{x}\n",
                .{ self.regs.rdi, self.regs.rsi, self.regs.rdx },
            );
            var toml_parse_error = false;
            var exception_type_name: []const u8 = "";
            var exception_message: []const u8 = "";
            if (self.cxxExceptionTypeName(thrown.type_info_address)) |type_name| {
                exception_type_name = type_name;
                std.debug.print("macho-processor: C++ exception ABI type name: {s}\n", .{type_name});
                if (std.mem.indexOf(u8, type_name, "toml") != null and
                    std.mem.indexOf(u8, type_name, "parse_error") != null)
                {
                    toml_parse_error = true;
                }
            }
            if (self.metadata.nearestSymbol(thrown.type_info_address)) |symbol| {
                std.debug.print("macho-processor: C++ exception type: {s}+0x{x}\n", .{ symbol.name, symbol.offset });
            }
            if (self.metadata.nearestSymbol(thrown.destructor_address)) |symbol| {
                std.debug.print("macho-processor: C++ exception destructor: {s}+0x{x}\n", .{ symbol.name, symbol.offset });
            }
            if (self.diagnosticSymbol(thrown.caller_address)) |throw_site| {
                std.debug.print("macho-processor: C++ exception throw site: {s}+0x{x} (0x{x})\n", .{
                    throw_site.symbol,
                    throw_site.symbol_offset,
                    throw_site.address,
                });
            }
            if (thrown.allocation) |allocation| {
                if (self.diagnosticSymbol(allocation.caller_address)) |allocation_site| {
                    std.debug.print("macho-processor: C++ exception allocation site: {s}+0x{x} (size={d})\n", .{
                        allocation_site.symbol,
                        allocation_site.symbol_offset,
                        allocation.object_size,
                    });
                }
            }
            if (self.cxxExceptionMessage(thrown.object_address)) |message| {
                exception_message = message;
                std.debug.print("macho-processor: C++ exception message: {s}\n", .{message});
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
                std.debug.print(
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
                std.debug.print("macho-processor: stopping after verified phase-1 catch discovery because this frame layout is not phase-2 safe\n", .{});
            } else {
                std.debug.print("macho-processor: stopping after Itanium phase-1 found no matching catch handler\n", .{});
            }
            self.dumpGuestStack();
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        }
        if (std.mem.eql(u8, name, "__Unwind_Resume") or std.mem.eql(u8, name, "__Unwind_Resume_or_Rethrow")) {
            const outer_assertion = if (self.signal_frame_count != 0)
                self.signal_frames[self.signal_frame_count - 1].assertion_class
            else
                GuestAssertionClass.none;
            if (guest_assertion_recovery.shouldEscapeNullBreakpointUnwind(
                self.regs.rdi,
                self.last_guest_assertion_class,
                outer_assertion,
                self.signal_frame_count,
            )) {
                std.debug.print(
                    "macho-processor: suppressing null __Unwind_Resume from nested breakpoint-handler fallout: outer_assertion={s} inner_assertion={s} signal_depth={d}; restoring outer signal context\n",
                    .{ @tagName(outer_assertion), @tagName(self.last_guest_assertion_class), self.signal_frame_count },
                );
                if (self.finishGuestSignalReturn()) {
                    self.breakpoint_cleanup_recoveries +|= 1;
                    self.last_guest_assertion_class = .none;
                    return .control_transferred;
                }
            }
            if (self.unwinder.resumePhaseTwo(self)) return .control_transferred;
            if (self.unwinder.exhaustedWithoutHandler()) {
                std.debug.print(
                    "macho-processor: Itanium phase-2 stopped after all verified cleanup pads; no matching LSDA catch exists for the guest exception\n",
                    .{},
                );
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
                return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
            }
            if (self.recoverOrphanedPhaseTwoResume(name)) return .control_transferred;
            if (self.regs.rdi != 0 or self.cxx_exceptions.activeThrow() != null) {
                const exception_header = if (self.regs.rdi != 0) self.regs.rdi else if (self.cxx_exceptions.activeThrow()) |thrown| if (thrown.allocation) |allocation| allocation.storage_address else thrown.object_address else 0;
                std.debug.print(
                    "macho-processor: Itanium host _Unwind_Resume fallback rejected: header=0x{x}; host addresses cannot be installed as guest RIP\n",
                    .{exception_header},
                );
            }
            if (self.regs.rdi == 0 and self.last_guest_assertion_class == .breakpoint_untracked_thread) {
                std.debug.print(
                    "macho-processor: breakpoint cleanup chain diagnosis: __Unwind_Resume received a null exception argument after Processor::OnThreadBreakpointHit asserted on an untracked modeled thread; no C++ throw object exists to resume, so exit 125 is secondary handler-cleanup termination\n",
                    .{},
                );
                std.debug.print(
                    "macho-processor: breakpoint cleanup chain origin: assertion_step={d} assertion_return=0x{x} active_thread=0x{x} signal_depth={d} deferred_threads={d} suspended_threads={d}\n",
                    .{ self.last_guest_assertion_step, self.last_guest_assertion_return, self.active_guest_thread, self.signal_frame_count, self.pthreads.deferred_threads, self.suspended_guest_thread_count },
                );
            }
            std.debug.print(
                "macho-processor: guest requested exception resume without a recoverable phase-2 cleanup chain: symbol={s} exception_arg=0x{x} rip=0x{x} rsp=0x{x} rbp=0x{x}\n",
                .{ name, self.regs.rdi, self.regs.rip, self.regs.rsp, self.regs.rbp },
            );
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        }
        if (std.mem.eql(u8, name, "___cxa_rethrow")) {
            const object_address = self.cxx_exceptions.recordRethrow() orelse self.regs.rdi;
            std.debug.print("macho-processor: guest rethrew exception object=0x{x}\n", .{object_address});
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
            if (self.verbose_trace) std.debug.print("    [import] _memset(dst=0x{x}, value=0x{x}, count={d})\n", .{ dst, value, count });
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
            if (self.verbose_trace) std.debug.print("    [import] _bzero(dst=0x{x}, count={d})\n", .{ dst, count });
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
            if (tv_sec < 0 or tv_nsec < 0) return .{ .handled = @bitCast(@as(i64, -1)) };
            const total_ns: u64 = (@as(u64, @intCast(tv_sec)) * 1_000_000_000) +| @as(u64, @intCast(tv_nsec));
            _ = self.guest_time.advanceBy(total_ns);
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
            std.debug.print("macho-processor: guest called abort()\n", .{});
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
            if (self.verbose_trace) std.debug.print("    [import] std::thread::join(object=0x{x})\n", .{self.regs.rdi});
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "__ZNSt3__16thread20hardware_concurrencyEv")) {
            const count = std.Thread.getCpuCount() catch 1;
            if (self.verbose_trace) std.debug.print("    [import] std::thread::hardware_concurrency() -> {d}\n", .{count});
            return .{ .handled = count };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__111this_thread6get_idEv")) {
            const handle = self.pthreads.currentThreadHandle(self);
            if (self.verbose_trace) std.debug.print("    [import] std::this_thread::get_id() -> 0x{x}\n", .{handle});
            return .{ .handled = handle };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__119__thread_local_dataEv")) {
            const allocation = self.guestAlloc(64, 16) orelse return .{ .unsupported = 0 };
            if (self.verbose_trace) std.debug.print("    [import] __thread_local_data() -> 0x{x}\n", .{allocation});
            return .{ .handled = allocation };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEEC2Ev")) {
            const object = self.regs.rdi;
            if (self.guestMemory(object, 64)) |buf| {
                @memset(buf, 0);
                if (self.libcxx_streams.object_model.ensureType(self, .basic_streambuf, null)) |record| {
                    self.write64(object, record.vtable);
                }
                if (self.verbose_trace) std.debug.print("    [import] basic_streambuf::C2(object=0x{x})\n", .{object});
            }
            return .{ .handled = object };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEElsEPKv")) {
            if (self.verbose_trace) std.debug.print("    [import] operator<<(void* ptr=0x{x}) -> *this\n", .{self.regs.rsi});
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__115basic_stringbufIcNS_11char_traitsIcEENS_9allocatorIcEEE3strEv")) {
            const output_ptr = self.regs.rdi;
            const stringbuf_ptr = self.regs.rsi;
            if (!self.libcxx_streams.stringbufToString(self, stringbuf_ptr, output_ptr)) {
                _ = compat_runtime.initLibcppStringLiteral(self, output_ptr, "");
            }
            if (self.verbose_trace) std.debug.print("    [import] basic_stringbuf::str() -> modeled string at 0x{x}\n", .{output_ptr});
            return .{ .handled = output_ptr };
        }

        if (std.mem.endsWith(u8, name, "_g_type_check_instance_cast")) {
            std.debug.print("    [import] _g_type_check_instance_cast compatibility shim → passthrough\n", .{});
            return .{ .handled = self.regs.rdi };
        }

        if (self.smart_stubs.resolve(name, imported.weak, self.regs.rdi)) |generated| {
            self.import_provider_override = .smart_stub;
            self.import_confidence_override = switch (generated.confidence) {
                .verified => .verified,
                .modeled => .modeled,
            };
            if (self.verbose_trace) {
                std.debug.print(
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
                if (self.verbose_trace) std.debug.print("    [import] ___sincosf_stret(angle={d}) -> sin={d} cos={d} ptr=0x{x}\n", .{ angle, sin_val, cos_val, self.regs.rdi });
            }
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.eql(u8, name, "_cosf")) {
            const angle: f32 = @bitCast(std.mem.readInt(u32, self.xmm[0][0..4], .little));
            const result: f32 = @cos(angle);
            std.mem.writeInt(u32, self.xmm[0][0..4], @bitCast(result), .little);
            if (self.verbose_trace) std.debug.print("    [import] _cosf(angle={d}) -> {d}\n", .{ angle, result });
            return .{ .handled = 0 };
        }

        if (self.verbose_trace) std.debug.print("    [import] (unhandled) {s}\n", .{name});
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
        std.debug.print(
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
            std.debug.print(
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
            std.debug.print(
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
            std.debug.print(
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

    fn handleVirtualSleepSchedulingBoundary(self: *MachOState, reason: []const u8) bool {
        const decision = self.dynamic_forwarder.lastVirtualSleepDecision();
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
            std.debug.print(
                "scheduler: virtual sleep boundary: sleeper=0x{x} resumed=0x{x} kind={s} parked={} switched={} deadline_ns={d} suspended={d} deferred={d}\n",
                .{ sleeping_thread, self.active_guest_thread, @tagName(decision.kind), parked, switched, if (decision.kind == .timed) self.guest_time.now() +| decision.effective_nanoseconds else 0, self.suspended_guest_thread_count, self.pthreads.deferred_threads },
            );
        }
        return switched;
    }

    fn handleDirectImportCall(self: *MachOState, imported: macho_metadata.ImportedSymbol) void {
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
        var import_completed = false;
        switch (self.handleImport(imported)) {
            .handled => |result| {
                import_completed = true;
                self.regs.rax = result;
                if (self.verbose_trace) {
                    std.debug.print(
                        "  [handled direct import] {s} from {s}; stub=0x{x} return=0x{x} -> rax=0x{x}\n",
                        .{ imported.name, imported.dylib, imported.stub_address, return_address, result },
                    );
                }
            },
            .handled_void => {
                import_completed = true;
                if (self.verbose_trace) {
                    std.debug.print(
                        "  [handled void direct import] {s} from {s}; stub=0x{x} return=0x{x}\n",
                        .{ imported.name, imported.dylib, imported.stub_address, return_address },
                    );
                }
            },
            .control_transferred => {
                if (self.verbose_trace) {
                    std.debug.print(
                        "  [handled direct control transfer] {s} from {s}; landing_pad=0x{x}\n",
                        .{ imported.name, imported.dylib, self.regs.rip },
                    );
                }
                return;
            },
            .unsupported => |result| {
                self.regs.rax = result;
                self.recordUnresolvedImport(imported, return_address, result);
                std.debug.print(
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
                std.debug.print("  [handled terminal direct import] {s}({d})\n", .{ imported.name, exit_code });
                return;
            },
        }

        if (return_address != 0 and self.isExecutableAddress(return_address)) {
            _ = self.pop();
            self.regs.rip = return_address;
            if (import_completed and self.dynamic_forwarder.virtualSleepCallCount() != virtual_sleep_calls_before) {
                _ = self.handleVirtualSleepSchedulingBoundary("libc++ virtual sleep");
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
            std.debug.print(
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
                    std.debug.print(
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
            std.debug.print(
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
            std.debug.print(
                "  [unknown-symbol runtime block] symbol={s} occurrence={d} use_site=0x{x} caller={s}+0x{x}\n",
                .{ imported.name, symbol_hits, use_site, caller.name, caller.offset },
            );
        } else {
            std.debug.print(
                "  [unknown-symbol runtime block] symbol={s} occurrence={d} use_site=0x{x} caller=<unknown>\n",
                .{ imported.name, symbol_hits, use_site },
            );
        }
        std.debug.print(
            "    entry-registers: rdi=0x{x} rsi=0x{x} rdx=0x{x} rcx=0x{x} r8=0x{x} r9=0x{x} rsp=0x{x}\n",
            .{ self.regs.rdi, self.regs.rsi, self.regs.rdx, self.regs.rcx, self.regs.r8, self.regs.r9, self.regs.rsp },
        );
        for (self.xmm[0..4], 0..) |value, index| {
            std.debug.print(
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
                std.debug.print(
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
                std.debug.print(
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
        std.debug.print(
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

    fn handleSigaction(self: *MachOState) u64 {
        const signal_index = guestSignalIndex(self.regs.rdi) orelse return signalFailureResult();
        const previous = self.signal_actions[signal_index];

        if (self.regs.rdx != 0) {
            const output = self.guestMemory(self.regs.rdx, DARWIN_SIGACTION_SIZE) orelse return signalFailureResult();
            writeDarwinSigaction(output, previous);
        }
        if (self.regs.rsi != 0) {
            const input = self.guestMemoryConst(self.regs.rsi, DARWIN_SIGACTION_SIZE) orelse return signalFailureResult();
            self.signal_actions[signal_index] = readDarwinSigaction(input) orelse return signalFailureResult();
        }
        if (self.verbose_trace) {
            const action = self.signal_actions[signal_index];
            std.debug.print(
                "    [signal] sigaction signal={d} handler=0x{x} flags=0x{x} mask=0x{x}\n",
                .{ self.regs.rdi, action.handler, action.flags, action.mask },
            );
        }
        return 0;
    }

    fn tryRecoverClassifiedAssertionUd2(self: *MachOState, instruction_len: u8) bool {
        if (self.last_guest_assertion_class != .timer_queue_wait_item_state) return false;
        const step_delta = self.executed_steps -| self.last_guest_assertion_step;
        const address_delta = if (self.regs.rip >= self.last_guest_assertion_return)
            self.regs.rip - self.last_guest_assertion_return
        else
            self.last_guest_assertion_return - self.regs.rip;
        const snapshot = guest_assertion_recovery.timerQueueSnapshot(self, self.regs.rbp) orelse return false;
        const action = guest_assertion_recovery.timerQueueAction(
            step_delta,
            address_delta,
            snapshot.frame_state,
            snapshot.object_state,
        );
        switch (action) {
            .none => return false,
            .replay_false_negative_idle_cas => {
                const disposition = self.timer_recovery_tracker.observe(snapshot, action, self.executed_steps);
                if (disposition == .quarantine_repeated_generation) {
                    if (!guest_assertion_recovery.quarantineRepeatedIdleGeneration(self, snapshot)) return false;
                    self.classified_ud2_recoveries +|= 1;
                    const owner = self.metadata.nearestSymbol(self.last_guest_assertion_return);
                    std.debug.print(
                        "macho-processor: timer recovery circuit breaker: wait_item=0x{x} due_ns={?d} interval_ns={?d} owner={s} repeated_generation_quarantined=true state=kIdle->kDisarmed resume=0x{x}; callback replay for this generation was already attempted\n",
                        .{ snapshot.wait_item, snapshot.due_nanoseconds, snapshot.interval_nanoseconds, if (owner) |symbol| symbol.name else "<unknown>", self.regs.rip +% instruction_len },
                    );
                    self.scheduler_log.emit(.{
                        .kind = .quiescence_recovery,
                        .step = self.executed_steps,
                        .thread = self.active_guest_thread,
                        .object = snapshot.wait_item,
                        .deadline_ns = snapshot.due_nanoseconds orelse 0,
                        .reason = "stale_timer_generation_quarantined",
                    });
                    self.last_guest_assertion_class = .none;
                    self.regs.rip +%= instruction_len;
                    return true;
                }
                const replay_rip = guest_assertion_recovery.applyIdleCasReplay(
                    self,
                    snapshot,
                    self.last_guest_assertion_return,
                ) orelse return false;
                self.classified_ud2_recoveries +|= 1;
                const owner = self.metadata.nearestSymbol(self.last_guest_assertion_return);
                const owner_address = if (owner) |symbol| self.last_guest_assertion_return -| symbol.offset else self.last_guest_assertion_return;
                const observation = self.diagnostic_throttler.observe(
                    .classified_ud2_recovery,
                    owner_address,
                    @intFromEnum(action),
                );
                if (observation.disposition == .detail) {
                    std.debug.print(
                        "macho-processor: classified UD2 recovery #{d}: timer queue strong CAS false-negative frame/live=kIdle; owner={s} wait_item=0x{x} state kIdle->kInCallback replay=0x{x} callback_pending=true step_delta={d} address_delta={d}\n",
                        .{ self.classified_ud2_recoveries, if (owner) |symbol| symbol.name else "<unknown>", snapshot.wait_item, replay_rip, step_delta, address_delta },
                    );
                } else if (observation.disposition == .checkpoint) {
                    std.debug.print(
                        "macho-processor: repeated classified UD2 recovery checkpoint: owner={s} case=idle_cas_false_negative occurrence={d} suppressed_since_previous={d} total_recoveries={d}\n",
                        .{ if (owner) |symbol| symbol.name else "<unknown>", observation.occurrence, observation.suppressed_since_emit, self.classified_ud2_recoveries },
                    );
                }
                self.last_guest_assertion_class = .none;
                self.regs.rip = replay_rip;
                return true;
            },
            .quarantine_callback_owned_duplicate => {
                self.classified_ud2_recoveries +|= 1;
                const owner = self.metadata.nearestSymbol(self.last_guest_assertion_return);
                const owner_address = if (owner) |symbol| self.last_guest_assertion_return -| symbol.offset else self.last_guest_assertion_return;
                const observation = self.diagnostic_throttler.observe(
                    .classified_ud2_recovery,
                    owner_address,
                    (@as(u64, @intFromEnum(action)) << 8) | snapshot.frame_state,
                );
                if (observation.disposition == .detail) {
                    std.debug.print(
                        "macho-processor: classified UD2 recovery #{d}: duplicate timer queue reference owner={s} frame/live={s}; wait_item=0x{x} action=quarantine_duplicate resume=0x{x} step_delta={d} address_delta={d}\n",
                        .{ self.classified_ud2_recoveries, if (owner) |symbol| symbol.name else "<unknown>", timerQueueStateName(snapshot.frame_state), snapshot.wait_item, self.regs.rip +% instruction_len, step_delta, address_delta },
                    );
                } else if (observation.disposition == .checkpoint) {
                    std.debug.print(
                        "macho-processor: repeated classified UD2 recovery checkpoint: owner={s} case=callback_owned_duplicate state={s} occurrence={d} suppressed_since_previous={d} total_recoveries={d}\n",
                        .{ if (owner) |symbol| symbol.name else "<unknown>", timerQueueStateName(snapshot.frame_state), observation.occurrence, observation.suppressed_since_emit, self.classified_ud2_recoveries },
                    );
                }
                self.last_guest_assertion_class = .none;
                self.regs.rip +%= instruction_len;
                return true;
            },
        }
    }

    fn deliverGuestSignal(self: *MachOState, signal: u8, fault_rip: u64, instruction_len: u8) bool {
        const signal_index = guestSignalIndex(signal) orelse return false;
        const action = self.signal_actions[signal_index];
        if (action.handler == 0) return false; // SIG_DFL: retain Rosette's diagnostic termination.
        if (action.handler == 1) { // SIG_IGN: make forward progress without synthesizing a callback.
            self.regs.rip +%= instruction_len;
            std.debug.print("macho-processor: guest ignored signal {d} at rip=0x{x}\n", .{ signal, fault_rip });
            return true;
        }
        if (action.flags & SA_NODEFER == 0 and self.signalIsActive(signal)) {
            // POSIX blocks the signal currently being handled unless
            // SA_NODEFER is requested. Queueing is unnecessary for UD2: the
            // outer handler already owns the exception and the nested trap is
            // an assertion in that handler's diagnostic path.
            self.regs.rip = fault_rip +% instruction_len;
            std.debug.print(
                "macho-processor: deferred recursive guest signal {d} at rip=0x{x}; outer handler remains active\n",
                .{ signal, fault_rip },
            );
            if (self.last_guest_assertion_class == .breakpoint_untracked_thread) {
                std.debug.print(
                    "macho-processor: recursive signal provenance: Processor::OnThreadBreakpointHit asserted because the active modeled thread was absent from Xenia's debugger registry; this nested UD2 is handler fallout, not a second independent backend failure\n",
                    .{},
                );
            }
            return true;
        }
        if (!self.isExecutableAddress(action.handler) or self.signal_frame_count >= self.signal_frames.len) return false;

        const frame = &self.signal_frames[self.signal_frame_count];
        if (!self.ensureGuestSignalFrameStorage(frame)) return false;
        const siginfo_bytes = self.guestMemory(frame.siginfo, DARWIN_SIGINFO_SIZE) orelse return false;
        const mcontext_bytes = self.guestMemory(frame.mcontext, DARWIN_MCONTEXT_SIZE) orelse return false;
        const ucontext_bytes = self.guestMemory(frame.ucontext, DARWIN_UCONTEXT_SIZE) orelse return false;

        writeDarwinSiginfo(siginfo_bytes, signal, fault_rip);
        writeDarwinMcontext(mcontext_bytes, self.regs);
        writeDarwinUcontext(ucontext_bytes, frame.mcontext);

        if (action.flags & SA_RESETHAND != 0) self.signal_actions[signal_index] = .{};
        frame.signal = signal;
        frame.instruction_len = instruction_len;
        frame.fault_rip = fault_rip;
        frame.assertion_class = self.last_guest_assertion_class;
        self.signal_frame_count += 1;
        self.push(GUEST_SIGNAL_RETURN_SENTINEL);
        if (self.terminated) {
            self.signal_frame_count -= 1;
            return false;
        }
        self.regs.rdi = signal;
        if (action.flags & SA_SIGINFO != 0) {
            self.regs.rsi = frame.siginfo;
            self.regs.rdx = frame.ucontext;
        } else {
            self.regs.rsi = 0;
            self.regs.rdx = 0;
        }
        self.regs.rip = action.handler;
        self.guest_signal_deliveries +|= 1;
        const backend_correlated = self.backend_diagnostics.signalCorrelates(self.executed_steps, fault_rip);
        if (backend_correlated) self.backend_diagnostics.noteSignalDelivery();
        std.debug.print(
            "macho-processor: delivered guest signal {d} to 0x{x}; fault_rip=0x{x} siginfo=0x{x} ucontext=0x{x}\n",
            .{ signal, action.handler, fault_rip, frame.siginfo, frame.ucontext },
        );
        if (backend_correlated) {
            std.debug.print(
                "macho-processor: guest signal correlation: signal={d} fault_rip=0x{x} is linked to backend assertion kind={s} assertion_return=0x{x} step_delta={d}\n",
                .{ signal, fault_rip, @tagName(self.backend_diagnostics.last_backend_assertion_binding), self.backend_diagnostics.last_backend_assertion_rip, self.executed_steps -| self.backend_diagnostics.last_backend_assertion_step },
            );
        }
        const assertion_distance = if (fault_rip >= self.last_guest_assertion_return)
            fault_rip - self.last_guest_assertion_return
        else
            self.last_guest_assertion_return - fault_rip;
        if (self.last_guest_assertion_class != .none and
            self.executed_steps -| self.last_guest_assertion_step <= 4096 and
            assertion_distance <= 16)
        {
            std.debug.print(
                "macho-processor: guest signal assertion provenance: signal={d} fault_rip=0x{x} assertion={s} assertion_return=0x{x} address_delta={d} step_delta={d}\n",
                .{ signal, fault_rip, @tagName(self.last_guest_assertion_class), self.last_guest_assertion_return, assertion_distance, self.executed_steps -| self.last_guest_assertion_step },
            );
        }
        return true;
    }

    fn signalIsActive(self: *const MachOState, signal: u8) bool {
        for (self.signal_frames[0..self.signal_frame_count]) |frame| {
            if (frame.signal == signal) return true;
        }
        return false;
    }

    fn ensureGuestSignalFrameStorage(self: *MachOState, frame: *GuestSignalFrame) bool {
        if (frame.siginfo == 0) frame.siginfo = self.guestAlloc(DARWIN_SIGINFO_SIZE, 16) orelse return false;
        if (frame.mcontext == 0) frame.mcontext = self.guestAlloc(DARWIN_MCONTEXT_SIZE, 16) orelse return false;
        if (frame.ucontext == 0) frame.ucontext = self.guestAlloc(DARWIN_UCONTEXT_SIZE, 16) orelse return false;
        return true;
    }

    fn finishGuestSignalReturn(self: *MachOState) bool {
        if (self.signal_frame_count == 0) {
            self.faulted = true;
            self.terminated = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
            return false;
        }
        self.signal_frame_count -= 1;
        const frame = self.signal_frames[self.signal_frame_count];
        const bytes = self.guestMemoryConst(frame.mcontext, DARWIN_MCONTEXT_SIZE) orelse {
            self.faulted = true;
            self.terminated = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
            return false;
        };
        if (!readDarwinMcontext(bytes, &self.regs)) {
            self.faulted = true;
            self.terminated = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
            return false;
        }
        const fault_bytes = self.guestMemoryConst(frame.fault_rip, frame.instruction_len) orelse &.{};
        const resume_rip = resolveGuestSignalReturn(frame, self.regs.rip, fault_bytes) orelse {
            std.debug.print(
                "macho-processor: guest signal {d} handler returned without resolving fault at rip=0x{x}\n",
                .{ frame.signal, frame.fault_rip },
            );
            self.faulted = true;
            self.terminated = true;
            self.exit_code = 128 + frame.signal;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unhandled_guest_signal);
            return false;
        };
        if (resume_rip != self.regs.rip) {
            std.debug.print(
                "macho-processor: guest signal {d} handler returned with unchanged UD2 at rip=0x{x}; resuming at 0x{x}\n",
                .{ frame.signal, frame.fault_rip, resume_rip },
            );
            self.regs.rip = resume_rip;
        }
        if (self.backend_diagnostics.signalReturnCorrelates(frame.fault_rip)) {
            self.backend_diagnostics.noteSignalReturn();
            std.debug.print(
                "macho-processor: guest signal correlation resolved: signal={d} backend_assertion={s} fault_rip=0x{x} resume_rip=0x{x}; execution continued\n",
                .{ frame.signal, @tagName(self.backend_diagnostics.last_backend_assertion_binding), frame.fault_rip, self.regs.rip },
            );
        }
        if (self.verbose_trace) {
            std.debug.print(
                "macho-processor: guest signal {d} returned; fault_rip=0x{x} resume_rip=0x{x}\n",
                .{ frame.signal, frame.fault_rip, self.regs.rip },
            );
        }
        return true;
    }

    fn terminateForUnresolvedImport(self: *MachOState) void {
        self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
        self.terminated = true;
    }

    fn recoverLibcppSharedControlBlockCall(
        self: *MachOState,
        instruction_address: u64,
        operand_address: u64,
    ) ?u64 {
        const caller = self.metadata.nearestSymbol(instruction_address) orelse return null;
        const object = self.regs.rdi;
        const object_bytes = self.guestMemoryConst(object, 3 * @sizeOf(u64));
        const vtable_symbol = self.internal_targets.libcpp_atomic_bool_control_block_vtable;
        const address_point = std.math.add(
            u64,
            vtable_symbol,
            libcpp_shared_control_block.vtable_address_point_offset,
        ) catch 0;
        const slot_address = std.math.add(
            u64,
            address_point,
            libcpp_shared_control_block.on_zero_shared_slot_offset,
        ) catch 0;
        const vtable_mapped = vtable_symbol != 0 and self.guestMemoryConst(vtable_symbol, 5 * @sizeOf(u64)) != null;
        const slot_target = if (vtable_mapped) self.read64(slot_address) else 0;
        const decision = libcpp_shared_control_block.assess(.{
            .operation = "call_mem64",
            .caller_symbol = caller.name,
            .operand_address = operand_address,
            .object_address = object,
            .current_vptr = if (object_bytes != null) self.read64(object) else 0,
            .strong_count = if (object_bytes != null) self.read64(object + 8) else 0,
            .weak_count = if (object_bytes != null) self.read64(object + 16) else 0,
            .vtable_symbol_address = vtable_symbol,
            .slot_target = slot_target,
            .object_mapped = object_bytes != null,
            .vtable_mapped = vtable_mapped,
            .target_executable = self.isExecutableAddress(slot_target),
        });
        self.libcpp_shared_control_blocks.record(decision);
        switch (decision) {
            .not_applicable => return null,
            .rejected => |reason| {
                std.debug.print(
                    "macho-processor: libc++ shared control-block recovery rejected: object=0x{x} operand=0x{x} vptr=0x{x} strong=0x{x} weak=0x{x} reason={s}\n",
                    .{
                        object,
                        operand_address,
                        if (object_bytes != null) self.read64(object) else 0,
                        if (object_bytes != null) self.read64(object + 8) else 0,
                        if (object_bytes != null) self.read64(object + 16) else 0,
                        reason,
                    },
                );
                return null;
            },
            .recover => |recovery| {
                self.write64(object, recovery.address_point);
                std.debug.print(
                    "macho-processor: libc++ shared control-block vptr restored: object=0x{x} vtable_symbol=0x{x} address_point=0x{x} slot=0x{x} target=0x{x} strong=0x{x} weak=0x{x} caller={s}+0x{x}; continuing verified __on_zero_shared dispatch\n",
                    .{
                        object,
                        vtable_symbol,
                        recovery.address_point,
                        recovery.slot_address,
                        recovery.target,
                        self.read64(object + 8),
                        self.read64(object + 16),
                        caller.name,
                        caller.offset,
                    },
                );
                return recovery.target;
            },
        }
    }

    fn terminateForInvalidControlTransfer(self: *MachOState, context: ControlTransferContext) void {
        var failure = exit_diagnostics.ControlTransferFailure{
            .kind = context.kind,
            .instruction_address = context.instruction_address,
            .operand_address = context.operand_address,
            .target_address = context.target_address,
            .return_address = context.return_address,
            .operand_mapped = context.operand_address != 0 and self.addrToOffset(context.operand_address) != null,
            .target_mapped = self.addrToOffset(context.target_address) != null,
            .target_executable = self.isExecutableAddress(context.target_address),
        };
        if (self.guestMemoryConst(context.instruction_address, 16)) |bytes| {
            const byte_count: usize = @min(bytes.len, failure.instruction_bytes.len);
            @memcpy(failure.instruction_bytes[0..byte_count], bytes[0..byte_count]);
            failure.instruction_byte_count = @intCast(byte_count);
            const decoded = decodeInsn(bytes[0..byte_count]);
            failure.decoded_operation = @tagName(decoded.op);
            failure.decoded_length = decoded.len;
        }
        if (context.operand_address != 0) {
            if (self.guestMemoryConst(context.operand_address, 8)) |_| {
                failure.operand_value = self.read64(context.operand_address);
            }
        }
        if (self.metadata.nearestSymbol(context.instruction_address)) |caller| {
            failure.caller_symbol = caller.name;
            failure.caller_offset = caller.offset;
        }
        if (self.metadata.nearestSymbol(context.target_address)) |target| {
            failure.target_symbol = target.name;
            failure.target_offset = target.offset;
        }
        for (self.metadata.imports) |imported| {
            if (imported.stub_address == context.instruction_address or
                (context.operand_address != 0 and imported.lazy_pointer_address == context.operand_address))
            {
                failure.candidate_import = imported.name;
                failure.candidate_image = imported.dylib;
                break;
            }
        }
        self.pending_control_transfer = null;
        self.terminal_control_transfer = failure;
        std.debug.print(
            "macho-processor: invalid control transfer: kind={s} instruction=0x{x} operand=0x{x} target=0x{x} return=0x{x} candidate_import={s}\n",
            .{
                failure.kind,
                failure.instruction_address,
                failure.operand_address,
                failure.target_address,
                failure.return_address,
                if (failure.candidate_import.len != 0) failure.candidate_import else "<none>",
            },
        );
        if (failure.instruction_byte_count != 0) {
            std.debug.print(
                "macho-processor: transfer decode: op={s} len={d} bytes={any} indirect=[0x{x}]=0x{x} mapped={} executable={} import_image={s}\n",
                .{
                    failure.decoded_operation,
                    failure.decoded_length,
                    failure.instruction_bytes[0..failure.instruction_byte_count],
                    failure.operand_address,
                    failure.operand_value,
                    failure.target_mapped,
                    failure.target_executable,
                    if (failure.candidate_image.len != 0) failure.candidate_image else "<none>",
                },
            );
        }
        self.logCrashDiagnostics(context);
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
        self.terminated = true;
    }

    /// Log extensive crash diagnostics around an invalid control transfer.
    /// Called before the process is marked as faulted.
    fn logCrashDiagnostics(self: *MachOState, context: ControlTransferContext) void {
        std.debug.print("macho-processor: CRASH DIAGNOSTICS BEGIN\n", .{});

        // 1. Thread info
        const thread_handle = self.active_guest_thread;
        const thread_id = self.threadNumericId(thread_handle);
        const thread_role = self.threadRole(thread_handle, self.regs.rip);
        std.debug.print(
            "macho-processor:   thread: handle=0x{x} numeric_id={d} role={s} rip=0x{x} rsp=0x{x} rbp=0x{x}\n",
            .{ thread_handle, thread_id, thread_role, self.regs.rip, self.regs.rsp, self.regs.rbp },
        );

        // 2. Full register dump
        std.debug.print(
            "macho-processor:   regs: rax=0x{x} rbx=0x{x} rcx=0x{x} rdx=0x{x}\n" ++ "macho-processor:         rsi=0x{x} rdi=0x{x} rbp=0x{x} rsp=0x{x}\n" ++ "macho-processor:         r8=0x{x}  r9=0x{x}  r10=0x{x} r11=0x{x}\n" ++ "macho-processor:         r12=0x{x} r13=0x{x} r14=0x{x} r15=0x{x}\n" ++ "macho-processor:         rip=0x{x} rflags=0x{x}\n",
            .{
                self.regs.rax, self.regs.rbx,    self.regs.rcx, self.regs.rdx,
                self.regs.rsi, self.regs.rdi,    self.regs.rbp, self.regs.rsp,
                self.regs.r8,  self.regs.r9,     self.regs.r10, self.regs.r11,
                self.regs.r12, self.regs.r13,    self.regs.r14, self.regs.r15,
                self.regs.rip, self.regs.rflags,
            },
        );

        // 3. Instruction context (re-decode showing addressing mode)
        {
            const insn_bytes = self.guestMemoryConst(context.instruction_address, 16);
            if (insn_bytes) |bytes| {
                const dec = decodeInsn(bytes[0..@min(bytes.len, 15)]);
                const addrmode = if (dec.rip_relative)
                    "rip_relative"
                else if (dec.sib_has_index)
                    "sib_indexed"
                else
                    "direct";
                const dst_reg = @tagName(dec.dst_reg);
                std.debug.print(
                    "macho-processor:   instr decode: op={s} addr_mode={s} addr=0x{x} dst_reg={s}\n",
                    .{ @tagName(dec.op), addrmode, dec.addr, dst_reg },
                );
                if (dec.sib_has_index) {
                    const idx_reg = @tagName(dec.sib_index_reg);
                    const base_reg = if (dec.sib_has_base) @tagName(dec.sib_base_reg) else "none";
                    std.debug.print(
                        "macho-processor:     sib: index={s} scale={d} base={s}\n",
                        .{ idx_reg, dec.sib_scale, base_reg },
                    );
                }
            }
        }

        // 4. Operand memory region info and nearby jump table dump
        if (context.operand_address != 0) {
            const op_offset = self.addrToOffset(context.operand_address);
            const op_mapped = op_offset != null;
            if (op_mapped) {
                const op_sym = self.metadata.nearestSymbol(context.operand_address);
                const op_value = self.read64(context.operand_address);
                std.debug.print(
                    "macho-processor:   operand 0x{x}: mapped=yes offset=0x{x} value=0x{x}\n",
                    .{ context.operand_address, op_offset.?, op_value },
                );
                // Show nearest symbol with stale-match warning
                if (op_sym) |s| {
                    const stale = if (s.offset > 1024) " (STALE MATCH: offset > 1024)" else "";
                    std.debug.print(
                        "macho-processor:   nearest symbol: {s}+0x{x}{s}\n",
                        .{ s.name, s.offset, stale },
                    );
                }
            } else {
                std.debug.print(
                    "macho-processor:   operand 0x{x}: mapped=no offset=<none>\n",
                    .{context.operand_address},
                );
            }

            // Segment/region info for operand address
            {
                var found_seg = false;
                for (self.segments) |seg| {
                    if (context.operand_address >= seg.vmaddr and context.operand_address < seg.vmaddr + seg.vmsize) {
                        const rel_off = context.operand_address - seg.vmaddr;
                        std.debug.print(
                            "macho-processor:   address region: Mach-O segment {s} [0x{x}-0x{x}] offset_in_segment=0x{x} prot=",
                            .{ seg.name, seg.vmaddr, seg.vmaddr + seg.vmsize - 1, rel_off },
                        );
                        if (seg.initprot & 1 != 0) {
                            std.debug.print("r", .{});
                        } else {
                            std.debug.print("-", .{});
                        }
                        if (seg.initprot & 2 != 0) {
                            std.debug.print("w", .{});
                        } else {
                            std.debug.print("-", .{});
                        }
                        if (seg.initprot & 4 != 0) {
                            std.debug.print("x", .{});
                        } else {
                            std.debug.print("-", .{});
                        }
                        std.debug.print("\n", .{});
                        found_seg = true;
                        break;
                    }
                }
                if (!found_seg) {
                    // Not in a Mach-O segment; check if it's a sparse mapping
                    const in_sparse = self.sparse_memory.contains(context.operand_address, 8);
                    std.debug.print(
                        "macho-processor:   address region: outside Mach-O segments sparse_mapped={}\n",
                        .{in_sparse},
                    );
                }
            }

            // Dump nearby entries (16 qwords: 8 before, the operand, 8 after)
            std.debug.print("macho-processor:   jump table dump [0x{x} +/- 64 bytes]:\n", .{context.operand_address});
            const dump_start = context.operand_address -| 64;
            const dump_end = context.operand_address + 72;
            var dump_addr = dump_start;
            while (dump_addr < dump_end) : (dump_addr += 8) {
                const marker = if (dump_addr == context.operand_address) " <-- OPERAND" else "";
                if (self.addrToOffset(dump_addr)) |_| {
                    const val = self.read64(dump_addr);
                    const val_sym = self.metadata.nearestSymbol(val);
                    std.debug.print(
                        "macho-processor:     [0x{x}]=0x{x}{s}",
                        .{ dump_addr, val, marker },
                    );
                    if (val_sym) |s| {
                        std.debug.print(" {s}+0x{x}", .{ s.name, s.offset });
                    }
                    std.debug.print("\n", .{});
                } else {
                    std.debug.print("macho-processor:     [0x{x}]=<unmapped>{s}\n", .{ dump_addr, marker });
                }
            }

            // Corruption pattern analysis on jump table entries
            {
                var hi32_const: ?u32 = null;
                var hi32_all_same = true;
                var lo32_prev: ?u32 = null;
                var lo32_step: ?i64 = null;
                var lo32_arith_prog = true;
                var lo32_counts: u32 = 0;
                var lo32_all_small = true;

                var scan_addr = context.operand_address -| 64;
                const scan_end = context.operand_address + 72;
                while (scan_addr < scan_end) : (scan_addr += 8) {
                    if (self.addrToOffset(scan_addr) == null) continue;
                    const val = self.read64(scan_addr);
                    if (val == 0) continue; // skip zero entries for pattern analysis
                    const hi32 = @as(u32, @truncate(val >> 32));
                    const lo32 = @as(u32, @truncate(val));
                    lo32_counts += 1;
                    if (lo32 >= 0x1000000000) lo32_all_small = false;

                    // Hi32 constancy check
                    if (hi32_const) |h| {
                        if (h != hi32) hi32_all_same = false;
                    } else {
                        hi32_const = hi32;
                    }

                    // Lo32 arithmetic progression check
                    if (lo32_prev) |p| {
                        const diff = @as(i64, lo32) - @as(i64, p);
                        if (lo32_step) |known_step| {
                            if (diff != known_step) lo32_arith_prog = false;
                        } else {
                            lo32_step = diff;
                        }
                    }
                    lo32_prev = lo32;
                }

                // Print hi32 analysis
                if (lo32_counts > 1 and hi32_const != null and hi32_all_same) {
                    const hi = hi32_const.?;
                    std.debug.print(
                        "macho-processor:   corruption pattern: all entries have constant high 32 bits = 0x{x}",
                        .{hi},
                    );
                    if (hi == 0xfffffc00) {
                        std.debug.print(" (kernel-space range, possible sign-extended 32-bit address)\n", .{});
                    } else if (hi == 0x00000000) {
                        std.debug.print(" (entries are valid 32-bit addresses in low 4GB)\n", .{});
                    } else if (hi == 0xffffffff) {
                        std.debug.print(" (possible -1 / invalid pattern)\n", .{});
                    } else if (hi == 0x00007fff) {
                        std.debug.print(" (possible userspace address on macOS)\n", .{});
                    } else {
                        std.debug.print("\n", .{});
                    }

                    // Interpret the entries as 32-bit pointers
                    std.debug.print("macho-processor:   interpreting as 32-bit pointer table:\n", .{});
                    scan_addr = context.operand_address -| 64;
                    while (scan_addr < scan_end) : (scan_addr += 8) {
                        if (self.addrToOffset(scan_addr) == null) continue;
                        const val = self.read64(scan_addr);
                        if (val == 0) continue;
                        const lo32 = @as(u32, @truncate(val));
                        const lo_sym = self.metadata.nearestSymbol(lo32);
                        const lo_small = if (lo32 < 0x1000) " (looks like a small offset, not a pointer)" else "";
                        if (lo_sym) |s| {
                            std.debug.print(
                                "macho-processor:     0x{x} -> 0x{x} (lo32) {s}+0x{x}{s}\n",
                                .{ scan_addr, lo32, s.name, s.offset, lo_small },
                            );
                        } else {
                            std.debug.print(
                                "macho-processor:     0x{x} -> 0x{x} (lo32){s}\n",
                                .{ scan_addr, lo32, lo_small },
                            );
                        }
                    }
                }

                // Print lo32 arithmetic progression analysis
                if (lo32_counts > 1 and lo32_arith_prog and lo32_step != null) {
                    const step_val = lo32_step.?;
                    std.debug.print(
                        "macho-processor:   corruption pattern: lo32 entries form arithmetic progression (step={d}, decreasing={}). Table was shifted by one entry (read as wrong-type entries).\n",
                        .{ @abs(step_val), step_val < 0 },
                    );
                }

                // Print lo32 small offset warning
                if (lo32_counts > 1 and lo32_all_small) {
                    std.debug.print(
                        "macho-processor:   corruption pattern: all lo32 values are small (< 4GB). Entries may be 32-bit offsets, not addresses.\n",
                        .{},
                    );
                }
            }
        }

        // 5. Suspended thread table snapshot
        if (self.suspended_guest_thread_count > 0) {
            std.debug.print("macho-processor:   suspended threads ({d}):\n", .{self.suspended_guest_thread_count});
            for (self.suspended_guest_threads[0..self.suspended_guest_thread_count], 0..) |st, i| {
                const st_sym = self.metadata.nearestSymbol(st.regs.rip);
                std.debug.print(
                    "macho-processor:     [{d}] handle=0x{x} rip=0x{x} rsp=0x{x} reason={s} suspended_step={d}",
                    .{ i, st.handle, st.regs.rip, st.regs.rsp, st.reason, st.suspended_step },
                );
                if (st_sym) |s| {
                    std.debug.print(" {s}+0x{x}", .{ s.name, s.offset });
                }
                std.debug.print("\n", .{});
            }
        }

        // 6. Guest backtrace (walk stack via rbp chain)
        std.debug.print("macho-processor:   guest backtrace (rbp chain):\n", .{});
        var frame_rbp = self.regs.rbp;
        var frame_rip = self.regs.rip;
        var frame_depth: usize = 0;
        while (frame_depth < 16) : (frame_depth += 1) {
            const frame_sym = self.metadata.nearestSymbol(frame_rip);
            std.debug.print(
                "macho-processor:     #{d} rip=0x{x} rbp=0x{x}",
                .{ frame_depth, frame_rip, frame_rbp },
            );
            if (frame_sym) |s| {
                std.debug.print(" {s}+0x{x}", .{ s.name, s.offset });
            }
            std.debug.print("\n", .{});
            // Walk to next frame: saved rbp is at [rbp], saved return address is at [rbp+8]
            if (frame_rbp == 0 or self.addrToOffset(frame_rbp) == null) break;
            const next_rbp = self.read64(frame_rbp);
            const next_rip_offset = frame_rbp + 8;
            if (next_rbp == 0 or next_rbp <= frame_rbp) {
                // rbp chain broken; try reading return address at known stack slot
                if (self.addrToOffset(next_rip_offset) != null) {
                    frame_rip = self.read64(next_rip_offset);
                    break;
                }
                break;
            }
            if (self.addrToOffset(next_rip_offset) == null) break;
            frame_rip = self.read64(next_rip_offset);
            frame_rbp = next_rbp;
        }

        // 7. Scheduler counters
        std.debug.print(
            "macho-processor:   scheduler: active=0x{x} suspended={d} switches={d} returns={d}" ++ " wait_yields={d} quantum_yields={d} rotation_yields={d}" ++ " preserved_resumes={d} wait_resumes={d} self_resumes={d}" ++ " quiescence_recoveries={d} starvation_warnings={d}\n",
            .{
                self.active_guest_thread,
                self.suspended_guest_thread_count,
                self.cooperative_thread_switches,
                self.cooperative_thread_returns,
                self.cooperative_wait_yields,
                self.cooperative_quantum_yields,
                self.cooperative_rotation_yields,
                self.cooperative_preserved_register_resumes,
                self.cooperative_wait_result_resumes,
                self.cooperative_self_resumes,
                self.cooperative_quiescence_recoveries,
                self.cooperative_starvation_warnings,
            },
        );
        std.debug.print("macho-processor: CRASH DIAGNOSTICS END\n", .{});
    }

    fn handleOpen(self: *MachOState) u64 {
        const path = self.guestCString(self.regs.rdi, 4096) orelse return @bitCast(@as(i64, -1));
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.allocator);
        path_buffer.appendSlice(self.allocator, path) catch return @bitCast(@as(i64, -1));
        path_buffer.append(self.allocator, 0) catch return @bitCast(@as(i64, -1));

        const host_fd = std.c.open(
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            @bitCast(@as(u32, @truncate(self.regs.rsi))),
            @as(c_int, @intCast(self.regs.rdx & 0xFFFF)),
        );
        if (host_fd < 0) return @bitCast(@as(i64, -1));
        return self.registerGuestFd(host_fd) orelse @bitCast(@as(i64, -1));
    }

    fn registerGuestFd(self: *MachOState, host_fd: c_int) ?u64 {
        var guest_fd: usize = @intCast(@max(self.next_guest_fd, 3));
        while (guest_fd < self.guest_fds.len and self.guest_fds[guest_fd] >= 0) : (guest_fd += 1) {}
        if (guest_fd >= self.guest_fds.len) {
            _ = std.c.close(host_fd);
            return null;
        }
        self.guest_fds[guest_fd] = host_fd;
        self.next_guest_fd = guest_fd + 1;
        return guest_fd;
    }

    pub fn setGuestErrno(self: *MachOState, value: c_int) void {
        if (self.guest_errno_address == 0) {
            self.guest_errno_address = self.guestAlloc(@sizeOf(c_int), @alignOf(c_int)) orelse return;
        }
        const storage = self.guestMemory(self.guest_errno_address, @sizeOf(c_int)) orelse return;
        std.mem.writeInt(c_int, storage[0..@sizeOf(c_int)], value, .little);
    }

    fn hostFd(self: *MachOState, guest_or_host_fd: u64) ?c_int {
        if (guest_or_host_fd < self.guest_fds.len) {
            const guest_fd: usize = @intCast(guest_or_host_fd);
            if (self.guest_fds[guest_fd] >= 0) return self.guest_fds[guest_fd];
        }
        if (guest_or_host_fd > std.math.maxInt(c_int)) return null;
        return @intCast(guest_or_host_fd);
    }

    fn handleFstatat(self: *MachOState) u64 {
        const directory_fd = self.hostFd(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        const path = self.guestCString(self.regs.rsi, 4096) orelse return @bitCast(@as(i64, -1));
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.allocator);
        path_buffer.appendSlice(self.allocator, path) catch return @bitCast(@as(i64, -1));
        path_buffer.append(self.allocator, 0) catch return @bitCast(@as(i64, -1));
        var host_stat: std.c.Stat = undefined;
        const result = std.c.fstatat(
            directory_fd,
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            &host_stat,
            @truncate(self.regs.rcx),
        );
        if (result != 0) {
            self.setGuestErrno(2);
            return @bitCast(@as(i64, -1));
        }
        const destination = self.guestMemory(self.regs.rdx, @sizeOf(std.c.Stat)) orelse return @bitCast(@as(i64, -1));
        @memcpy(destination, std.mem.asBytes(&host_stat));
        return 0;
    }

    fn handleOpenat(self: *MachOState) u64 {
        const directory_fd = self.hostFd(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        const path = self.guestCString(self.regs.rsi, 4096) orelse return @bitCast(@as(i64, -1));
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.allocator);
        path_buffer.appendSlice(self.allocator, path) catch return @bitCast(@as(i64, -1));
        path_buffer.append(self.allocator, 0) catch return @bitCast(@as(i64, -1));
        const host_fd = std.c.openat(
            directory_fd,
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            @bitCast(@as(u32, @truncate(self.regs.rdx))),
            @as(c_int, @intCast(self.regs.rcx & 0xFFFF)),
        );
        if (host_fd < 0) {
            self.setGuestErrno(2);
            return @bitCast(@as(i64, -1));
        }
        return self.registerGuestFd(host_fd) orelse @bitCast(@as(i64, -1));
    }

    fn handleFstat(self: *MachOState) u64 {
        const host_fd = self.hostFd(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        var host_stat: std.c.Stat = undefined;
        if (std.c.fstat(host_fd, &host_stat) != 0) {
            self.setGuestErrno(2);
            return @bitCast(@as(i64, -1));
        }
        const destination = self.guestMemory(self.regs.rsi, @sizeOf(std.c.Stat)) orelse return @bitCast(@as(i64, -1));
        @memcpy(destination, std.mem.asBytes(&host_stat));
        return 0;
    }

    fn handleFtruncate(self: *MachOState) u64 {
        const host_fd = self.hostFd(self.regs.rdi) orelse {
            self.setGuestErrno(9);
            return @bitCast(@as(i64, -1));
        };
        const result = std.c.ftruncate(host_fd, @bitCast(self.regs.rsi));
        if (result != 0) self.setGuestErrno(22);
        return @bitCast(@as(i64, result));
    }

    fn handleOpendir(self: *MachOState) ?u64 {
        const path = self.guestCString(self.regs.rdi, 4096) orelse return null;
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.allocator);
        path_buffer.appendSlice(self.allocator, path) catch return null;
        path_buffer.append(self.allocator, 0) catch return null;
        const host_fd = std.c.open(
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            std.c.O{ .DIRECTORY = true },
            @as(c_int, 0),
        );
        if (host_fd < 0) return null;
        return self.allocGuestFile(host_fd, .regular) orelse {
            _ = std.c.close(host_fd);
            return null;
        };
    }

    fn handleClosedir(self: *MachOState) u64 {
        const directory = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        if (directory.fd >= 0 and std.c.close(directory.fd) != 0) return @bitCast(@as(i64, -1));
        directory.* = .{};
        return 0;
    }

    fn handleWrite(self: *MachOState) u64 {
        const guest_fd: usize = @intCast(self.regs.rdi);
        if (guest_fd >= self.guest_fds.len or self.guest_fds[guest_fd] < 0) return @bitCast(@as(i64, -1));
        const bytes = self.guestMemoryConst(self.regs.rsi, self.regs.rdx) orelse return @bitCast(@as(i64, -1));
        const written = std.c.write(self.guest_fds[guest_fd], bytes.ptr, bytes.len);
        return if (written < 0) @bitCast(@as(i64, -1)) else @intCast(written);
    }

    fn handleClose(self: *MachOState) u64 {
        const guest_fd: usize = @intCast(self.regs.rdi);
        if (guest_fd >= self.guest_fds.len or self.guest_fds[guest_fd] < 0) return @bitCast(@as(i64, -1));
        const result = std.c.close(self.guest_fds[guest_fd]);
        self.guest_fds[guest_fd] = -1;
        if (guest_fd < self.next_guest_fd) self.next_guest_fd = @max(guest_fd, 3);
        return if (result == 0) 0 else @bitCast(@as(i64, -1));
    }

    fn hostWriteAll(self: *MachOState, file: *GuestFile, bytes: []const u8) bool {
        if (file.fd < 0) return false;
        var written: usize = 0;
        while (written < bytes.len) {
            const rc = std.c.write(file.fd, bytes.ptr + written, bytes.len - written);
            if (rc < 0) {
                self.setGuestErrno(@intCast(@intFromEnum(std.c.errno(rc))));
                file.error_flag = true;
                return false;
            }
            if (rc == 0) break;
            written += @intCast(rc);
        }
        if (file.kind == .regular) file.position += @intCast(written);
        const completed = written == bytes.len;
        if (completed and file.kind != .regular) {
            self.guest_stdio_write_count +|= 1;
            switch (file.kind) {
                .stdout => self.guest_stdout_byte_count +|= written,
                .stderr => self.guest_stderr_byte_count +|= written,
                .regular => unreachable,
            }
            if (self.guest_log_mirror_fd >= 0 and
                self.guest_log_mirror_fd != file.fd and
                !hostWriteFdAll(self.guest_log_mirror_fd, bytes))
            {
                self.guest_stdio_mirror_failures +|= 1;
            }
            if (self.guest_stdio_write_count == 1) {
                std.debug.print(
                    "macho-processor: guest stdio capture active: first_stream={s} log_mirror_active={}\n",
                    .{ @tagName(file.kind), self.guest_log_mirror_fd >= 0 },
                );
            }
        }
        return completed;
    }

    fn handleFopen(self: *MachOState) ?u64 {
        const path = self.guestCString(self.regs.rdi, 4096) orelse return null;
        const mode = self.guestCString(self.regs.rsi, 32) orelse return null;
        const flags = parseFopenFlags(mode) orelse return null;
        var temp_buf: [4096]u8 = undefined;
        var translated_path: []const u8 = path;
        if (self.fs_forwarder.resolveHostPath(path, &temp_buf)) |t| {
            translated_path = t;
        }
        var path_buf = std.ArrayList(u8).empty;
        defer path_buf.deinit(self.allocator);
        path_buf.appendSlice(self.allocator, translated_path) catch return null;
        path_buf.append(self.allocator, 0) catch return null;
        const zpath: [*:0]const u8 = @ptrCast(path_buf.items.ptr);
        const oflags: std.c.O = @bitCast(@as(u32, @intCast(flags)));
        var fd = std.c.open(zpath, oflags, @as(c_int, 0o666));
        if (fd < 0) {
            const err = std.c.errno(fd);
            if (self.fs_forwarder.tryOpenFallback(translated_path, oflags, 0o666, err)) |fallback_fd| {
                fd = fallback_fd;
            } else {
                return null;
            }
        }
        return self.allocGuestFile(fd, .regular);
    }

    fn handleFdopen(self: *MachOState) ?u64 {
        const mode = self.guestCString(self.regs.rsi, 32) orelse {
            self.setGuestErrno(@intFromEnum(std.c.E.FAULT));
            std.debug.print("macho-processor: fdopen rejected: unreadable mode pointer=0x{x}\n", .{self.regs.rsi});
            return null;
        };
        const guest_fd = self.regs.rdi;
        const host_fd = self.fs_forwarder.fd_manager.take(guest_fd) orelse {
            self.setGuestErrno(@intFromEnum(std.c.E.BADF));
            std.debug.print("macho-processor: fdopen rejected: invalid guest_fd={d} mode={s}\n", .{ guest_fd, mode });
            return null;
        };
        const handle = self.allocGuestFile(host_fd, .regular) orelse {
            _ = std.c.close(host_fd);
            self.setGuestErrno(@intFromEnum(std.c.E.NOMEM));
            return null;
        };
        std.debug.print(
            "macho-processor: fdopen: guest_fd={d} host_fd={d} mode={s} -> FILE=0x{x}\n",
            .{ guest_fd, host_fd, mode, handle },
        );
        return handle;
    }

    fn handleFileno(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        if (file.descriptor_alias != std.math.maxInt(u64) and
            self.fs_forwarder.fd_manager.hostFd(file.descriptor_alias) != null)
        {
            return file.descriptor_alias;
        }
        const duplicate = std.c.dup(file.fd);
        if (duplicate < 0) return @bitCast(@as(i64, -1));
        const guest_fd = self.fs_forwarder.fd_manager.register(duplicate, .file) orelse return @bitCast(@as(i64, -1));
        file.descriptor_alias = guest_fd;
        return guest_fd;
    }

    fn handleFclose(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        if (file.descriptor_alias != std.math.maxInt(u64)) {
            _ = self.fs_forwarder.fd_manager.close(file.descriptor_alias);
            file.descriptor_alias = std.math.maxInt(u64);
        }
        if (file.kind == .regular and file.fd >= 0) {
            if (std.c.close(file.fd) != 0) {
                file.error_flag = true;
                return @bitCast(@as(i64, -1));
            }
        }
        file.* = .{};
        return 0;
    }

    fn handleFputs(self: *MachOState) u64 {
        const text = self.guestCString(self.regs.rdi, 1 << 20) orelse return @bitCast(@as(i64, -1));
        const file = self.guestFileFromHandle(self.regs.rsi) orelse return @bitCast(@as(i64, -1));
        if (!self.hostWriteAll(file, text)) return @bitCast(@as(i64, -1));
        return @intCast(text.len);
    }

    fn handleFwrite(self: *MachOState) u64 {
        const element_size = self.regs.rsi;
        const element_count = self.regs.rdx;
        if (element_size == 0 or element_count == 0) return 0;
        const byte_count = std.math.mul(u64, element_size, element_count) catch {
            self.setGuestErrno(@intFromEnum(std.c.E.OVERFLOW));
            return 0;
        };
        const bytes = self.guestMemoryConst(self.regs.rdi, byte_count) orelse {
            self.setGuestErrno(@intFromEnum(std.c.E.FAULT));
            std.debug.print("macho-processor: fwrite rejected: source=0x{x} bytes={d}\n", .{ self.regs.rdi, byte_count });
            return 0;
        };
        const file = self.guestFileFromHandle(self.regs.rcx) orelse {
            self.setGuestErrno(@intFromEnum(std.c.E.BADF));
            std.debug.print("macho-processor: fwrite rejected: FILE=0x{x} bytes={d}\n", .{ self.regs.rcx, byte_count });
            return 0;
        };
        if (!self.hostWriteAll(file, bytes)) {
            std.debug.print("macho-processor: fwrite failed: FILE=0x{x} host_fd={d} requested={d}\n", .{ self.regs.rcx, file.fd, byte_count });
            return 0;
        }
        std.debug.print("macho-processor: fwrite: FILE=0x{x} host_fd={d} bytes={d} elements={d}\n", .{ self.regs.rcx, file.fd, byte_count, element_count });
        return element_count;
    }

    fn handleFread(self: *MachOState) u64 {
        const element_size = self.regs.rsi;
        const element_count = self.regs.rdx;
        if (element_size == 0 or element_count == 0) return 0;
        const byte_count = std.math.mul(u64, element_size, element_count) catch {
            self.setGuestErrno(@intFromEnum(std.c.E.OVERFLOW));
            self.guest_stdio_failures +|= 1;
            return 0;
        };
        const destination = self.guestMemory(self.regs.rdi, byte_count) orelse {
            self.setGuestErrno(@intFromEnum(std.c.E.FAULT));
            self.guest_stdio_failures +|= 1;
            std.debug.print("macho-processor: fread rejected: destination=0x{x} bytes={d}\n", .{ self.regs.rdi, byte_count });
            return 0;
        };
        const file = self.guestFileFromHandle(self.regs.rcx) orelse {
            self.setGuestErrno(@intFromEnum(std.c.E.BADF));
            self.guest_stdio_failures +|= 1;
            std.debug.print("macho-processor: fread rejected: FILE=0x{x} bytes={d}\n", .{ self.regs.rcx, byte_count });
            return 0;
        };
        if (file.fd < 0) {
            self.setGuestErrno(@intFromEnum(std.c.E.BADF));
            file.error_flag = true;
            self.guest_stdio_failures +|= 1;
            return 0;
        }

        const initial_position = file.position;
        var bytes_read: usize = 0;
        while (bytes_read < destination.len) {
            const result = std.c.read(file.fd, destination.ptr + bytes_read, destination.len - bytes_read);
            if (result < 0) {
                self.setGuestErrno(@intCast(@intFromEnum(std.c.errno(result))));
                file.error_flag = true;
                self.guest_stdio_failures +|= 1;
                break;
            }
            if (result == 0) break;
            bytes_read += @intCast(result);
        }
        file.position += @intCast(bytes_read);
        self.guest_stdio_read_count +|= 1;
        self.guest_stdio_read_bytes +|= bytes_read;
        const complete_elements = bytes_read / @as(usize, @intCast(element_size));
        if (self.guest_stdio_read_count <= 8 or self.guest_stdio_read_count % 1000 == 0) {
            std.debug.print(
                "macho-processor: fread #{d}: FILE=0x{x} host_fd={d} position={d}->{d} requested={d} read={d} elements={d}/{d}\n",
                .{ self.guest_stdio_read_count, self.regs.rcx, file.fd, initial_position, file.position, byte_count, bytes_read, complete_elements, element_count },
            );
        }
        return complete_elements;
    }

    fn handleFflush(self: *MachOState) u64 {
        if (self.regs.rdi == 0) return 0;
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        if (std.c.fsync(file.fd) != 0 and file.kind == .regular) {
            file.error_flag = true;
            return @bitCast(@as(i64, -1));
        }
        return 0;
    }

    fn handleFtell(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        return @bitCast(file.position);
    }

    fn handleFseek(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        const offset: i64 = @bitCast(self.regs.rsi);
        const whence: i32 = @intCast(self.regs.rdx);
        self.guest_stdio_seek_count +|= 1;
        if (file.fd < 0) {
            self.setGuestErrno(@intFromEnum(std.c.E.BADF));
            self.guest_stdio_failures +|= 1;
            return @bitCast(@as(i64, -1));
        }
        const initial_position = file.position;
        const pos = std.c.lseek(file.fd, offset, whence);
        if (pos < 0) {
            self.setGuestErrno(@intCast(@intFromEnum(std.c.errno(pos))));
            file.error_flag = true;
            self.guest_stdio_failures +|= 1;
            return @bitCast(@as(i64, -1));
        }
        file.position = pos;
        if (self.guest_stdio_seek_count <= 8 or self.guest_stdio_seek_count % 1000 == 0) {
            std.debug.print(
                "macho-processor: fseek #{d}: FILE=0x{x} host_fd={d} position={d}->{d} offset={d} whence={d}\n",
                .{ self.guest_stdio_seek_count, self.regs.rdi, file.fd, initial_position, pos, offset, whence },
            );
        }
        return 0;
    }

    fn handleFerror(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return 1;
        return if (file.error_flag) 1 else 0;
    }

    fn handleFprintf(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        const arguments = [_]u64{ self.regs.rdx, self.regs.rcx, self.regs.r8, self.regs.r9 };
        return self.handlePrintfLike(file, self.regs.rsi, &arguments);
    }

    fn handleSnprintf(self: *MachOState) u64 {
        const destination = self.regs.rdi;
        const capacity: usize = @intCast(self.regs.rsi);
        const format = self.guestCString(self.regs.rdx, 1 << 20) orelse return @bitCast(@as(i64, -1));
        var output = std.ArrayList(u8).empty;
        defer output.deinit(self.allocator);
        const arguments = [_]u64{ self.regs.rcx, self.regs.r8, self.regs.r9 };
        var argument_index: usize = 0;
        var stack_argument = self.regs.rsp + 8;
        var index: usize = 0;
        while (index < format.len) : (index += 1) {
            if (format[index] != '%') {
                output.append(self.allocator, format[index]) catch return @bitCast(@as(i64, -1));
                continue;
            }
            index += 1;
            if (index >= format.len) break;
            if (format[index] == '%') {
                output.append(self.allocator, '%') catch return @bitCast(@as(i64, -1));
                continue;
            }
            while (index < format.len and (format[index] == '-' or format[index] == '+' or format[index] == ' ' or format[index] == '#' or format[index] == '0')) : (index += 1) {}
            while (index < format.len and std.ascii.isDigit(format[index])) : (index += 1) {}
            if (index < format.len and format[index] == '.') {
                index += 1;
                while (index < format.len and std.ascii.isDigit(format[index])) : (index += 1) {}
            }
            while (index < format.len and (format[index] == 'l' or format[index] == 'h' or format[index] == 'z' or format[index] == 't' or format[index] == 'j')) : (index += 1) {}
            if (index >= format.len) break;
            const argument = self.nextVarArg(&arguments, &argument_index, &stack_argument);
            switch (format[index]) {
                's' => output.appendSlice(self.allocator, self.guestCString(argument, 1 << 20) orelse "(null)") catch return @bitCast(@as(i64, -1)),
                'c' => output.append(self.allocator, @truncate(argument)) catch return @bitCast(@as(i64, -1)),
                'd', 'i' => {
                    const rendered = std.fmt.allocPrint(self.allocator, "{d}", .{@as(i64, @bitCast(argument))}) catch return @bitCast(@as(i64, -1));
                    defer self.allocator.free(rendered);
                    output.appendSlice(self.allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'u' => {
                    const rendered = std.fmt.allocPrint(self.allocator, "{d}", .{argument}) catch return @bitCast(@as(i64, -1));
                    defer self.allocator.free(rendered);
                    output.appendSlice(self.allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'x', 'X', 'p' => {
                    const rendered = std.fmt.allocPrint(self.allocator, "{x}", .{argument}) catch return @bitCast(@as(i64, -1));
                    defer self.allocator.free(rendered);
                    if (format[index] == 'p') output.appendSlice(self.allocator, "0x") catch return @bitCast(@as(i64, -1));
                    output.appendSlice(self.allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                // Floating-point varargs are carried in XMM registers. Preserve a
                // valid numeric field until the formatter gains full width and
                // precision handling rather than exposing an unresolved import.
                'f', 'F', 'e', 'E', 'g', 'G', 'a', 'A' => output.append(self.allocator, '0') catch return @bitCast(@as(i64, -1)),
                else => {
                    output.append(self.allocator, '%') catch return @bitCast(@as(i64, -1));
                    output.append(self.allocator, format[index]) catch return @bitCast(@as(i64, -1));
                },
            }
        }
        if (capacity != 0) {
            const target = self.guestMemory(destination, capacity) orelse return @bitCast(@as(i64, -1));
            const written = @min(output.items.len, capacity - 1);
            @memcpy(target[0..written], output.items[0..written]);
            target[written] = 0;
        }
        return output.items.len;
    }

    fn handlePrintfLike(self: *MachOState, file_opt: ?*GuestFile, format_address: u64, arguments: []const u64) u64 {
        const format = self.guestCString(format_address, 1 << 20) orelse return @bitCast(@as(i64, -1));
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        var output = std.ArrayList(u8).empty;
        defer output.deinit(allocator);

        var gp_index: usize = 0;
        var stack_arg_addr = self.regs.rsp + 8;
        var i: usize = 0;
        while (i < format.len) : (i += 1) {
            if (format[i] != '%') {
                output.append(allocator, format[i]) catch return @bitCast(@as(i64, -1));
                continue;
            }
            i += 1;
            if (i >= format.len) break;
            if (format[i] == '%') {
                output.append(allocator, '%') catch return @bitCast(@as(i64, -1));
                continue;
            }

            while (i < format.len and (format[i] == '-' or format[i] == '+' or format[i] == ' ' or format[i] == '#' or format[i] == '0')) : (i += 1) {}
            while (i < format.len and std.ascii.isDigit(format[i])) : (i += 1) {}
            if (i < format.len and format[i] == '.') {
                i += 1;
                while (i < format.len and std.ascii.isDigit(format[i])) : (i += 1) {}
            }
            while (i < format.len and
                (format[i] == 'l' or format[i] == 'h' or format[i] == 'z' or
                    format[i] == 't' or format[i] == 'j' or format[i] == 'L')) : (i += 1)
            {}
            if (i >= format.len) break;

            const spec = format[i];
            const arg = self.nextVarArg(arguments, &gp_index, &stack_arg_addr);
            switch (spec) {
                's' => {
                    const text = self.guestCString(arg, 1 << 20) orelse "(null)";
                    output.appendSlice(allocator, text) catch return @bitCast(@as(i64, -1));
                },
                'd', 'i' => {
                    const val: i64 = @bitCast(arg);
                    const rendered = std.fmt.allocPrint(allocator, "{}", .{val}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'u' => {
                    const rendered = std.fmt.allocPrint(allocator, "{}", .{arg}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'x' => {
                    const rendered = std.fmt.allocPrint(allocator, "{x}", .{arg}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'X' => {
                    const rendered = std.fmt.allocPrint(allocator, "{X}", .{arg}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'p' => {
                    const rendered = std.fmt.allocPrint(allocator, "0x{x}", .{arg}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'c' => {
                    output.append(allocator, @intCast(arg & 0xFF)) catch return @bitCast(@as(i64, -1));
                },
                else => {
                    output.append(allocator, '%') catch return @bitCast(@as(i64, -1));
                    output.append(allocator, spec) catch return @bitCast(@as(i64, -1));
                },
            }
        }

        const sink = file_opt orelse self.guestFileFromHandle(GUEST_FILE_BASE + 1).?;
        if (!self.hostWriteAll(sink, output.items)) return @bitCast(@as(i64, -1));
        return output.items.len;
    }

    fn handlePutchar(self: *MachOState) u64 {
        const ch: u8 = @intCast(self.regs.rdi & 0xFF);
        const sink = self.guestFileFromHandle(GUEST_FILE_BASE + 1) orelse return @bitCast(@as(i64, -1));
        if (!self.hostWriteAll(sink, &[_]u8{ch})) return @bitCast(@as(i64, -1));
        return ch;
    }

    fn handleGtkInitCheck(self: *MachOState) u64 {
        const argc_ptr = self.regs.rdi;
        const argv_ptr = self.regs.rsi;
        _ = argc_ptr;
        _ = argv_ptr;
        std.debug.print("    [import] _gtk_init_check compatibility shim → success\n", .{});
        return 1;
    }

    fn nextVarArg(self: *const MachOState, arguments: []const u64, gp_index: *usize, stack_arg_addr: *u64) u64 {
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

    fn dumpRecentTrace(self: *const MachOState) void {
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

    fn regVal(self: *const MachOState, id: RegId, size: Size) u64 {
        return x64_decoder.regVal(&self.regs, id, size);
    }

    fn setReg(self: *MachOState, id: RegId, size: Size, val: u64) void {
        x64_decoder.setReg(&self.regs, id, size, val);
    }

    fn setFlagsSub(self: *MachOState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applySub(&self.regs.rflags, a, b, result, size);
    }

    fn setFlagsAdd(self: *MachOState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applyAdd(&self.regs.rflags, a, b, result, size);
    }

    fn setFlagsIncDec(self: *MachOState, input: u64, result: u64, size: Size, is_inc: bool) void {
        x64_decoder.applyIncDec(&self.regs.rflags, input, result, size, is_inc);
    }

    fn setFlagsLogic(self: *MachOState, result: u64, size: Size) void {
        x64_decoder.applyLogic(&self.regs.rflags, result, size);
    }

    fn executeHighwayRegisterBinary(self: *MachOState, d: DecodedInsn, op: x64_decoder.highway.BinaryOp, size: Size) void {
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

    fn executeHighwayMemoryBinary(
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

    fn executeHighwayImmediate(self: *MachOState, d: DecodedInsn, op: x64_decoder.highway.BinaryOp, size: Size, memory: bool) void {
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

    fn setFlag(self: *MachOState, flag: u32, enabled: bool) void {
        if (enabled) {
            self.regs.rflags |= flag;
        } else {
            self.regs.rflags &= ~flag;
        }
    }

    fn executeBtrRegister(self: *MachOState, d: DecodedInsn) void {
        const value = self.regVal(d.dst_reg, d.size);
        const result = x64_decoder.bitTestAndResetRegister(d.size, value, self.regVal(d.src_reg, d.size));
        self.setFlag(RFL_CF, result.carry);
        self.setReg(d.dst_reg, d.size, result.value);
    }

    fn executeBtrMemory(self: *MachOState, d: DecodedInsn) void {
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

    fn bitWidth(size: Size) u7 {
        return switch (size) {
            .bits8 => 8,
            .bits16 => 16,
            .bits32 => 32,
            .bits64 => 64,
        };
    }

    fn maskForSize(size: Size) u64 {
        return switch (size) {
            .bits8 => 0xFF,
            .bits16 => 0xFFFF,
            .bits32 => 0xFFFF_FFFF,
            .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
        };
    }

    fn signBitForSize(size: Size) u64 {
        return switch (size) {
            .bits8 => 0x80,
            .bits16 => 0x8000,
            .bits32 => 0x8000_0000,
            .bits64 => 0x8000_0000_0000_0000,
        };
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
        std.debug.print("ROSETTE: setupMachOState called with path: '{s}'\n", .{path});
        std.debug.print("ROSETTE: Argument count: {d}\n", .{args.len});
        for (args, 0..) |arg, i| {
            std.debug.print("ROSETTE:   argv[{d}] = '{s}'\n", .{ i, arg });
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

        std.debug.print("ROSETTE: Full argv count (including path): {d}\n", .{full_args.items.len});
        std.debug.print("ROSETTE: Entry point vaddr: 0x{x}\n", .{self.entry_point_vaddr});

        self.trace_range_start = 0x1332000;
        self.trace_range_end = 0x1333000;
        self.setupInitialStack(full_args.items);
        self.regs.rip = self.entry_point_vaddr;

        std.debug.print("ROSETTE: setupMachOState complete - RIP set to 0x{x}\n", .{self.regs.rip});
    }

    fn initializerAbi(self: *const MachOState) initialization_resolution.AbiSnapshot {
        return .{
            .rsp = self.regs.rsp,
            .rbx = self.regs.rbx,
            .rbp = self.regs.rbp,
            .r12 = self.regs.r12,
            .r13 = self.regs.r13,
            .r14 = self.regs.r14,
            .r15 = self.regs.r15,
        };
    }

    fn beginInitializerTransaction(self: *MachOState) void {
        self.initializer_memory.begin();
        self.initializer_checkpoint = .{
            .heap_next = self.heap_next,
            .compat = self.compat,
            .monotonic_nanoseconds = self.guest_time.now(),
            .ios_xalloc_next = self.ios_xalloc_next,
            .cxxopts_split_accelerations = self.cxxopts_split_accelerations,
            .guest_errno_address = self.guest_errno_address,
        };
    }

    fn rollbackInitializerTransaction(self: *MachOState) bool {
        const checkpoint = self.initializer_checkpoint orelse return false;
        const complete = self.initializer_memory.rollback(self.mem);
        self.heap_next = checkpoint.heap_next;
        self.compat = checkpoint.compat;
        self.guest_time.monotonic_ns = checkpoint.monotonic_nanoseconds;
        self.ios_xalloc_next = checkpoint.ios_xalloc_next;
        self.cxxopts_split_accelerations = checkpoint.cxxopts_split_accelerations;
        self.guest_errno_address = checkpoint.guest_errno_address;
        self.initializer_checkpoint = null;
        return complete;
    }

    fn commitInitializerTransaction(self: *MachOState) bool {
        if (self.initializer_checkpoint == null) return false;
        self.initializer_checkpoint = null;
        return self.initializer_memory.commit();
    }

    fn runOneInitializer(self: *MachOState, launch_regs: Regs, index: usize, is_retry: bool) InitializerRunOutcome {
        const address = self.metadata.initializer_addresses[index];
        const nearest_symbol = self.metadata.nearestSymbol(address);
        const symbol_name = if (nearest_symbol) |symbol| symbol.name else "<unknown>";
        self.regs = launch_regs;
        self.initializer_abort_requested = false;
        self.initializer_abort_reason = .none;

        if (is_retry) {
            if (!self.initializer_resolver.retry(
                index,
                self.initializerAbi(),
                self.unresolved_import_count,
                self.guest_assertion_count,
            )) return .failed;
        } else {
            if (!self.initializer_resolver.begin(
                index,
                address,
                symbol_name,
                self.initializerAbi(),
                self.unresolved_import_count,
                self.guest_assertion_count,
            )) {
                self.faulted = true;
                self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.initializer_transaction_failure);
                self.terminated = true;
                return .failed;
            }
        }

        self.beginInitializerTransaction();

        if (!self.isExecutableAddress(address)) {
            std.debug.print(
                "macho-processor: initializer [{d}/{d}] has invalid target 0x{x}\n",
                .{ index + 1, self.metadata.initializer_addresses.len, address },
            );
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
            self.terminated = true;
            _ = self.rollbackInitializerTransaction();
            self.initializer_resolver.fail(
                .invalid_target,
                0,
                self.initializerAbi(),
                self.unresolved_import_count,
                self.guest_assertion_count,
            );
            return .failed;
        }

        self.push(INITIALIZER_RETURN_SENTINEL);
        self.regs.rip = address;

        var steps: u64 = 0;
        while (!self.terminated and !self.initializer_abort_requested and
            self.regs.rip != INITIALIZER_RETURN_SENTINEL and steps < INITIALIZER_STEP_LIMIT) : (steps +|= 1)
        {
            if (!self.step()) break;
        }
        if (self.initializer_abort_requested) {
            const final_abi = self.initializerAbi();
            const deferral_reason = self.initializer_abort_reason;
            const deferral_attempt = if (self.initializer_resolver.current()) |record| record.attempts else 0;
            if (!self.rollbackInitializerTransaction()) {
                self.initializer_resolver.fail(
                    .transaction_failed,
                    steps,
                    final_abi,
                    self.unresolved_import_count,
                    self.guest_assertion_count,
                );
                self.faulted = true;
                self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.initializer_transaction_failure);
                self.terminated = true;
                return .failed;
            }
            self.initializer_resolver.deferCurrent(
                steps,
                final_abi,
                self.unresolved_import_count,
                self.guest_assertion_count,
                deferral_reason,
            );
            self.initializer_abort_requested = false;
            self.initializer_abort_reason = .none;
            if (deferral_reason != .runtime_dependency or deferral_attempt <= 1) {
                std.debug.print(
                    "macho-processor: deferred initializer [{d}/{d}] {s} reason={s}\n",
                    .{ index + 1, self.metadata.initializer_addresses.len, symbol_name, @tagName(deferral_reason) },
                );
            }
            return .deferred;
        }
        if (self.terminated) {
            const final_abi = self.initializerAbi();
            std.debug.print(
                "macho-processor: initializer [{d}/{d}] terminated at rip=0x{x} reason={s} exit_code=0x{x}\n",
                .{ index + 1, self.metadata.initializer_addresses.len, self.regs.rip, @tagName(exit_diagnostics.reasonFromValue(self.termination_reason)), self.exit_code },
            );
            self.dumpRecentTrace();
            _ = self.rollbackInitializerTransaction();
            self.initializer_resolver.fail(
                .terminated,
                steps,
                final_abi,
                self.unresolved_import_count,
                self.guest_assertion_count,
            );
            std.debug.print(
                "macho-processor: initializer [{d}/{d}] failed at {s}+0x{x}\n",
                .{ index + 1, self.metadata.initializer_addresses.len, symbol_name, if (nearest_symbol) |item| item.offset else address },
            );
            return .failed;
        }
        if (self.regs.rip != INITIALIZER_RETURN_SENTINEL) {
            const final_abi = self.initializerAbi();
            std.debug.print(
                "macho-processor: initializer [{d}/{d}] exceeded {d} steps at {s}+0x{x}; terminal_rip=0x{x}\n",
                .{ index + 1, self.metadata.initializer_addresses.len, INITIALIZER_STEP_LIMIT, symbol_name, if (nearest_symbol) |item| item.offset else address, self.regs.rip },
            );
            self.dumpRecentTrace();
            _ = self.rollbackInitializerTransaction();
            self.initializer_resolver.deferCurrent(
                steps,
                final_abi,
                self.unresolved_import_count,
                self.guest_assertion_count,
                .step_limit,
            );
            std.debug.print(
                "macho-processor: deferred initializer [{d}/{d}] {s} after step limit\n",
                .{ index + 1, self.metadata.initializer_addresses.len, symbol_name },
            );
            return .deferred;
        }

        const final_abi = self.initializerAbi();
        if (!self.commitInitializerTransaction()) {
            self.initializer_resolver.fail(
                .transaction_failed,
                steps,
                final_abi,
                self.unresolved_import_count,
                self.guest_assertion_count,
            );
            self.faulted = true;
            self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.initializer_transaction_failure);
            self.terminated = true;
            return .failed;
        }

        const degraded_before = self.initializer_resolver.degraded;
        self.initializer_resolver.finish(
            steps,
            final_abi,
            self.unresolved_import_count,
            self.guest_assertion_count,
        );
        if (self.strict_initializers and self.initializer_resolver.degraded != degraded_before) {
            std.debug.print(
                "macho-processor: strict initializer mode rejected [{d}/{d}] {s}\n",
                .{ index + 1, self.metadata.initializer_addresses.len, symbol_name },
            );
            self.faulted = true;
            self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
            self.terminated = true;
            return .failed;
        }
        return .completed;
    }

    fn runInitializers(self: *MachOState) bool {
        if (self.metadata.initializer_addresses.len == 0) return true;

        const launch_regs = self.regs;
        self.export_table_lc.enterPhase(.initializers_in_progress);

        var pending: std.ArrayList(usize) = .empty;
        defer pending.deinit(self.allocator);
        var next_pending: std.ArrayList(usize) = .empty;
        defer next_pending.deinit(self.allocator);

        for (self.metadata.initializer_addresses, 0..) |_, index| {
            switch (self.runOneInitializer(launch_regs, index, false)) {
                .completed => {},
                .deferred => pending.append(self.allocator, index) catch return false,
                .failed => return false,
            }
            if ((index + 1) % 50 == 0 or index + 1 == self.metadata.initializer_addresses.len) {
                std.debug.print(
                    "macho-processor: processed initializer {d}/{d}\n",
                    .{ index + 1, self.metadata.initializer_addresses.len },
                );
            }
        }

        self.export_table_lc.enterPhase(.exports_resolved);

        if (pending.items.len != 0) {
            var growth_buf: [4]export_table_lifecycle.VectorGrowthRequest = undefined;
            const growth_count = self.export_table_lc.popGrowthRequests(&growth_buf);
            if (growth_count > 0) {
                std.debug.print(
                    "macho-processor: pre-populating {d} export vector(s) before retry pass\n",
                    .{growth_count},
                );
            }
            for (growth_buf[0..growth_count]) |req| {
                const var_name = std.mem.sliceTo(&req.variable_name, 0);
                const current_size = if (self.guestMemoryConst(req.vector_address, 16) != null)
                    self.read32(req.vector_address)
                else
                    0;
                std.debug.print(
                    "macho-processor:   pre-populating vector={s} at 0x{x} current_size={d} needed_size={d} element_size={d}\n",
                    .{ var_name, req.vector_address, current_size, req.needed_size, req.element_size },
                );
                if (current_size >= req.needed_size) {
                    std.debug.print(
                        "macho-processor:   vector already has enough entries ({d} >= {d}); skipping growth\n",
                        .{ current_size, req.needed_size },
                    );
                    continue;
                }
                if (current_size > 0) {
                    std.debug.print(
                        "macho-processor:   vector has {d} entries but needs {d}; growing\n",
                        .{ current_size, req.needed_size },
                    );
                }
                const dummy_item = self.memory_forwarder.allocate(self, req.element_size, 16) orelse {
                    std.debug.print(
                        "macho-processor:   failed to allocate dummy item for vector pre-population\n",
                        .{},
                    );
                    continue;
                };
                {
                    const slice = self.guestMemory(dummy_item, req.element_size) orelse {
                        std.debug.print(
                            "macho-processor:   dummy item memory not writable after allocation\n",
                            .{},
                        );
                        continue;
                    };
                    @memset(slice, 0);
                }
                const item_addr = dummy_item;
                var append_count: u32 = 0;
                while (self.read32(req.vector_address) < req.needed_size) {
                    if (!self.appendTrivialVector(req.vector_address, item_addr, req.element_size, req.needed_size)) {
                        std.debug.print(
                            "macho-processor:   appendTrivialVector failed after {d} appends\n",
                            .{append_count},
                        );
                        break;
                    }
                    append_count += 1;
                }
                std.debug.print(
                    "macho-processor:   vector pre-population: appended {d} entries, new size={d}\n",
                    .{ append_count, self.read32(req.vector_address) },
                );
            }
        }

        var retry_round: u8 = 0;
        while (pending.items.len != 0 and retry_round < 3) : (retry_round += 1) {
            self.export_table_lc.retry_pass = retry_round + 1;
            std.debug.print(
                "macho-processor: retrying {d} deferred initializer(s), pass {d}\n",
                .{ pending.items.len, retry_round + 1 },
            );
            for (pending.items) |index| {
                switch (self.runOneInitializer(launch_regs, index, true)) {
                    .completed => {},
                    .deferred => next_pending.append(self.allocator, index) catch return false,
                    .failed => return false,
                }
            }
            self.export_table_lc.onRetryPass(retry_round + 1);
            pending.clearRetainingCapacity();
            std.mem.swap(std.ArrayList(usize), &pending, &next_pending);
        }

        if (pending.items.len != 0) {
            std.debug.print(
                "macho-processor: {d} initializer(s) remained deferred after 3 retry passes\n",
                .{pending.items.len},
            );
            self.faulted = true;
            self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
            self.terminated = true;
            return false;
        }

        self.regs = launch_regs;
        return true;
    }

    fn appendTrivialVector(self: *MachOState, vector: u64, item: u64, element_size: u64, minimum_capacity: u32) bool {
        const header_size: u64 = 16;
        if (element_size == 0 or self.guestMemory(vector, header_size) == null or self.guestMemoryConst(item, element_size) == null) {
            const bad_address = if (self.guestMemory(vector, header_size) == null) vector else item;
            self.terminateForGuestAccess(bad_address, @intCast(@min(@max(element_size, header_size), std.math.maxInt(u8))), .read, "trivial_vector_push_back");
            return false;
        }

        const size = self.read32(vector);
        var capacity = self.read32(vector + 4);
        var data = self.read64(vector + 8);
        const storage_is_valid = data != 0 and capacity >= size and
            self.guestMemoryConst(data, @as(u64, capacity) * element_size) != null;

        // A non-empty vector without backing storage cannot be repaired without
        // inventing missing elements. Stop at the violated invariant instead
        // of allowing a later near-null dereference to obscure the cause.
        if (size != 0 and !storage_is_valid) {
            self.terminateForGuestAccess(data, @intCast(@min(element_size, std.math.maxInt(u8))), .read, "trivial_vector_invalid_storage");
            return false;
        }

        if (!storage_is_valid or size == capacity) {
            const requested = size +| 1;
            const grown = if (capacity == 0) minimum_capacity else capacity +| capacity / 2;
            const new_capacity = @max(requested, grown);
            const allocation_size = std.math.mul(u64, new_capacity, element_size) catch {
                self.terminated = true;
                self.faulted = true;
                self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
                return false;
            };
            const new_data = self.memory_forwarder.allocate(self, allocation_size, 16) orelse {
                self.terminated = true;
                self.faulted = true;
                self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
                return false;
            };
            if (size != 0) {
                const used = @as(u64, size) * element_size;
                const source = self.guestMemoryConst(data, used) orelse return false;
                const destination = self.guestMemory(new_data, used) orelse return false;
                std.mem.copyForwards(u8, destination, source);
                self.memory_forwarder.release(data);
            }
            data = new_data;
            capacity = new_capacity;
            self.write32(vector + 4, capacity);
            self.write64(vector + 8, data);
        }

        const destination_address = data + @as(u64, size) * element_size;
        const source = self.guestMemoryConst(item, element_size) orelse return false;
        const destination = self.guestMemory(destination_address, element_size) orelse return false;
        std.mem.copyForwards(u8, destination, source);
        self.write32(vector, size +| 1);
        return true;
    }

    fn handleLibcppBasicStringSubstr(self: *MachOState) bool {
        const entry = self.internal_targets.libcxx_basic_string_substr;
        if (entry == 0 or self.regs.rip != entry) return false;

        const destination = self.regs.rdi;
        const source_object = self.regs.rsi;
        const position = self.regs.rdx;
        const count = self.regs.rcx;
        const source_view = compat_runtime.libcppStringView(self, source_object) orelse {
            std.debug.print(
                "macho-processor: libc++ basic_string::substr rejected unreadable source object=0x{x} destination=0x{x}\n",
                .{ source_object, destination },
            );
            return false;
        };
        if (source_view.length > 1 << 20 or
            self.guestMemoryConst(source_view.address, source_view.length) == null)
        {
            std.debug.print(
                "macho-processor: libc++ basic_string::substr rejected corrupt source: object=0x{x} data=0x{x} length={d} pos={d} count={d}\n",
                .{ source_object, source_view.address, source_view.length, position, count },
            );
            return false;
        }
        if (position > source_view.length) {
            // Preserve libc++'s std::out_of_range path instead of converting a
            // programming error into a different string.
            std.debug.print(
                "macho-processor: libc++ basic_string::substr out-of-range delegated to guest: source_length={d} pos={d} count={d}\n",
                .{ source_view.length, position, count },
            );
            return false;
        }

        const source_bytes = self.guestMemoryConst(source_view.address, source_view.length).?;
        const profile_device = std.mem.startsWith(u8, source_bytes, "User_") and
            std.mem.endsWith(u8, source_bytes, ":");
        var preview_buffer: [256]u8 = undefined;
        const preview_length = @min(source_bytes.len, preview_buffer.len);
        @memcpy(preview_buffer[0..preview_length], source_bytes[0..preview_length]);
        const preview = preview_buffer[0..preview_length];
        const result_length = compat_runtime.substringLibcppString(
            self,
            destination,
            source_object,
            position,
            count,
        ) orelse return false;
        const return_address = if (self.guestMemoryConst(self.regs.rsp, 8) != null) self.read64(self.regs.rsp) else 0;
        const caller = if (return_address != 0) self.metadata.nearestSymbol(return_address) else null;
        const vfs_resolution = if (caller) |symbol|
            std.mem.indexOf(u8, symbol.name, "VirtualFileSystem11ResolvePath") != null
        else
            false;
        self.libcxx_string_substr_fast_paths +|= 1;
        if (self.libcxx_string_substr_fast_paths <= 16 or vfs_resolution or profile_device) {
            std.debug.print(
                "macho-processor: libc++ basic_string::substr fast path #{d}: source_object=0x{x} destination=0x{x} source_length={d} pos={d} count={d} result_length={d} caller=0x{x} {s}+0x{x} source='{s}'\n",
                .{ self.libcxx_string_substr_fast_paths, source_object, destination, source_view.length, position, count, result_length, return_address, if (caller) |symbol| symbol.name else "<unknown>", if (caller) |symbol| symbol.offset else 0, preview },
            );
        }
        if (vfs_resolution) {
            std.debug.print(
                "macho-processor: VFS relative-path checkpoint: mount_length={d} normalized_length={d} relative_length={d} root_resolution={}; HostPathDevice must receive only this suffix, never the User_<profile-id>: prefix\n",
                .{ position, source_view.length, result_length, result_length == 0 },
            );
        }
        if (profile_device and position == source_view.length and result_length == 0) {
            std.debug.print(
                "macho-processor: profile device root normalized successfully: source='{s}' pos==size and substr result is empty; ResolvePath should now return the mounted HostPathDevice root before Account child lookup\n",
                .{preview},
            );
            if (profileIdFromUserDevice(preview)) |profile_id| {
                self.logProfileHostPreflight(profile_id);
            }
        }

        self.regs.rax = destination;
        self.regs.rip = self.pop();
        return true;
    }

    fn handleInternalCompatibility(self: *MachOState) bool {
        if (self.handleLibcppBasicStringSubstr()) return true;
        if (self.handleLocalLibcppStreamCompatibility()) return true;
        // Xenia's backend dispatches through a host-populated CPU feature
        // detector. Under guest execution that dispatch table has no host
        // implementation, leaving its first slot null. The function is void;
        // completing it here preserves the backend's portable fallback path.
        if (self.internal_targets.xenia_cpu_feature_detector_initialize_cpu_info != 0 and
            self.regs.rip == self.internal_targets.xenia_cpu_feature_detector_initialize_cpu_info)
        {
            std.debug.print("macho-processor: modeled x64 CPU feature detection\n", .{});
            self.regs.rip = self.pop();
            return true;
        }
        // A presentation provider is intentionally absent when the guest's
        // Vulkan probe finds no compatible surface. Let its caller observe a
        // null device rather than dereferencing the absent provider as `this`.
        if (self.internal_targets.xenia_vulkan_provider_vulkan_device != 0 and
            self.regs.rip == self.internal_targets.xenia_vulkan_provider_vulkan_device and
            self.regs.rdi == 0)
        {
            std.debug.print("macho-processor: Vulkan provider unavailable; returning null Vulkan device\n", .{});
            self.regs.rax = 0;
            self.regs.rip = self.pop();
            return true;
        }
        if (self.internal_targets.page_entry_construct_at_end != 0 and
            self.regs.rip == self.internal_targets.page_entry_construct_at_end and
            self.handlePageEntryBulkInitialization())
        {
            return true;
        }
        if (self.internal_targets.imgui_settings_push_back != 0 and
            self.regs.rip == self.internal_targets.imgui_settings_push_back)
        {
            _ = self.appendTrivialVector(self.regs.rdi, self.regs.rsi, 0x48, 8);
            if (!self.terminated) self.regs.rip = self.pop();
            return true;
        }
        // ImGui::MemAlloc dispatches through a writable global callback. Model
        // the stable allocator boundary directly while dyld data bindings are
        // synthetic, preventing Size > 0 / Data == null container states.
        if (self.internal_targets.imgui_mem_alloc != 0 and
            self.regs.rip == self.internal_targets.imgui_mem_alloc)
        {
            self.regs.rax = self.memory_forwarder.allocate(self, self.regs.rdi, 16) orelse 0;
            self.regs.rip = self.pop();
            return true;
        }
        if (self.internal_targets.imgui_mem_free != 0 and
            self.regs.rip == self.internal_targets.imgui_mem_free)
        {
            self.memory_forwarder.release(self.regs.rdi);
            self.regs.rip = self.pop();
            return true;
        }
        if (self.internal_targets.imgui_default_malloc != 0 and
            self.regs.rip == self.internal_targets.imgui_default_malloc)
        {
            self.regs.rax = self.memory_forwarder.allocate(self, self.regs.rdi, 16) orelse 0;
            self.regs.rip = self.pop();
            return true;
        }
        if (self.internal_targets.imgui_default_free != 0 and
            self.regs.rip == self.internal_targets.imgui_default_free)
        {
            self.memory_forwarder.release(self.regs.rdi);
            self.regs.rip = self.pop();
            return true;
        }
        if (self.internal_targets.parse_launch_arguments != 0 and
            self.regs.rip == self.internal_targets.parse_launch_arguments)
        {
            self.startup.enter(.launch_arguments, self.executed_steps);
            self.capturePositionalLaunchOptions();
        }
        if (self.internal_targets.initialize_logging != 0 and
            self.regs.rip == self.internal_targets.initialize_logging)
        {
            self.startup.enter(.logging, self.executed_steps);
            const app_name = self.guestMemoryConst(self.regs.rdi, @min(self.regs.rsi, 1024)) orelse "";
            if (self.logging.initialize(app_name)) {
                if (self.guest_log_buffer_address == 0) {
                    self.guest_log_buffer_address = self.guestAlloc(GUEST_LOG_BUFFER_SIZE, 16) orelse return false;
                }
                self.regs.rip = self.pop();
                self.startup.enter(.logging_ready, self.executed_steps);
                return true;
            }
        }
        if (self.internal_targets.shutdown_logging != 0 and
            self.regs.rip == self.internal_targets.shutdown_logging and
            self.logging.shutdown())
        {
            self.regs.rip = self.pop();
            return true;
        }
        if (self.handleGuestLogBridge()) return true;
        for (self.internal_targets.cvar_add_to_launch_options[0..self.internal_targets.cvar_add_to_launch_options_count]) |target| {
            if (self.regs.rip != target) continue;
            const view = compat_runtime.libcppStringView(self, self.regs.rdi + 8) orelse return false;
            const name = self.guestMemoryConst(view.address, view.length) orelse return false;
            if (self.launch_options.shouldRegister(name)) return false;
            if (self.launch_options.registrations_skipped == 1 or
                self.launch_options.registrations_skipped % 100 == 0)
            {
                std.debug.print(
                    "macho-processor: launch option fast path skipped {d} unused registration(s); latest={s}\n",
                    .{ self.launch_options.registrations_skipped, name },
                );
            }
            self.regs.rip = self.pop();
            return true;
        }
        if (self.internal_targets.cxxopts_split_option_names != 0 and
            self.regs.rip == self.internal_targets.cxxopts_split_option_names)
        {
            return self.handleCxxoptsSplitOptionNames();
        }
        if (self.internal_targets.libcxx_basic_streambuf_pubsetbuf != 0 and
            self.regs.rip == self.internal_targets.libcxx_basic_streambuf_pubsetbuf)
        {
            self.regs.rax = self.libcxx_streams.handlePubsetbuf(self.regs.rdi, self.regs.rsi, self.regs.rdx);
            self.regs.rip = self.pop();
            return true;
        }
        if (self.internal_targets.libcxx_basic_ifstream_default_constructor != 0 and
            self.regs.rip == self.internal_targets.libcxx_basic_ifstream_default_constructor)
        {
            if (!self.libcxx_streams.constructIfstream(self, self.regs.rdi)) return false;
            self.regs.rax = self.regs.rdi;
            self.regs.rip = self.pop();
            return true;
        }
        if ((self.internal_targets.libcxx_basic_ifstream_destructor_1 != 0 and
            self.regs.rip == self.internal_targets.libcxx_basic_ifstream_destructor_1) or
            (self.internal_targets.libcxx_basic_ifstream_destructor_2 != 0 and
                self.regs.rip == self.internal_targets.libcxx_basic_ifstream_destructor_2))
        {
            self.libcxx_streams.destroyIfstream(self, self.regs.rdi);
            self.regs.rip = self.pop();
            return true;
        }
        if ((self.internal_targets.libcxx_getline != 0 and self.regs.rip == self.internal_targets.libcxx_getline) or
            (self.internal_targets.libcxx_getline_delimiter != 0 and self.regs.rip == self.internal_targets.libcxx_getline_delimiter))
        {
            const delimiter: u8 = if (self.regs.rip == self.internal_targets.libcxx_getline_delimiter) @truncate(self.regs.rdx) else '\n';
            _ = self.libcxx_streams.readLine(self, self.regs.rdi, self.regs.rsi, delimiter);
            self.regs.rax = self.regs.rdi;
            self.regs.rip = self.pop();
            return true;
        }
        if (self.internal_targets.print_config_to_log != 0 and
            self.regs.rip == self.internal_targets.print_config_to_log)
        {
            self.startup.enter(.config_load, self.executed_steps);
            if (self.diagnostic_text.buildConfigDump(self, &self.fs_forwarder, self.regs.rdi)) |dump| {
                const emitted = self.emitGuestLog('i', dump.address, dump.length);
                self.logging.recordEmission(dump.length, emitted);
                self.regs.rip = self.pop();
                return true;
            }
        }
        return false;
    }

    fn handlePageEntryBulkInitialization(self: *MachOState) bool {
        const split_buffer = self.regs.rdi;
        const count = self.regs.rsi;
        if (self.guestMemoryConst(split_buffer, 32) == null) return false;

        const begin = self.read64(split_buffer + 8);
        const end = self.read64(split_buffer + 16);
        const capacity_end = self.read64(split_buffer + 24);
        if (begin == 0 or end < begin or capacity_end < end) return false;

        const range = calculateBulkConstructionRange(begin, end, capacity_end, count, 16) orelse return false;
        if (range.byte_count != 0) {
            const destination = self.guestMemory(end, range.byte_count) orelse return false;
            @memset(destination, 0);
        }
        self.write64(split_buffer + 16, range.new_end);
        self.page_entry_bulk_initializations +|= 1;
        self.page_entry_bulk_bytes +|= range.byte_count;
        const return_address = self.read64(self.regs.rsp);
        const caller = self.metadata.nearestSymbol(return_address);
        std.debug.print(
            "macho-processor: bulk default construction: PageEntry count={d} bytes={d} range=0x{x}-0x{x} return={s}+0x{x}\n",
            .{ count, range.byte_count, end, range.new_end, if (caller) |resolved| resolved.name else "<unknown>", if (caller) |resolved| resolved.offset else 0 },
        );
        self.regs.rip = self.pop();
        return !self.terminated;
    }

    fn handleLocalLibcppStreamCompatibility(self: *MachOState) bool {
        const symbol = self.local_libcpp_stream_targets.get(self.regs.rip) orelse return false;
        const resolution = self.libcxx_streams.dispatch(self, &self.fs_forwarder, symbol) orelse return false;
        switch (resolution) {
            .handled => |value| self.regs.rax = value,
            .handled_void => {},
        }
        self.regs.rip = self.pop();
        return true;
    }

    fn capturePositionalLaunchOptions(self: *MachOState) void {
        if (self.positional_options_captured) return;
        self.positional_options_captured = true;

        const vector = self.regs.r8;
        const begin = self.read64(vector);
        const end = self.read64(vector + 8);
        if (begin == 0 or end < begin or (end - begin) % 24 != 0) {
            std.debug.print("macho-processor: launch option acceleration could not decode positional option vector at 0x{x}\n", .{vector});
            return;
        }
        const count = @min((end - begin) / 24, launch_argument_accelerator.MAX_REQUESTED_OPTIONS);
        for (0..@as(usize, @intCast(count))) |index| {
            const object = begin + index * 24;
            const view = compat_runtime.libcppStringView(self, object) orelse continue;
            const name = self.guestMemoryConst(view.address, view.length) orelse continue;
            self.launch_options.request(name);
            std.debug.print("macho-processor: launch option acceleration retained positional option: {s}\n", .{name});
        }
    }

    fn handleGuestLogBridge(self: *MachOState) bool {
        if (self.internal_targets.guest_log_get_thread_buffer != 0 and
            self.regs.rip == self.internal_targets.guest_log_get_thread_buffer)
        {
            if (self.guest_log_buffer_address == 0) {
                self.guest_log_buffer_address = self.guestAlloc(GUEST_LOG_BUFFER_SIZE, 16) orelse return false;
                std.debug.print(
                    "macho-processor: synchronous Xenia log bridge enabled at buffer=0x{x}\n",
                    .{self.guest_log_buffer_address},
                );
            }
            self.regs.rax = self.guest_log_buffer_address;
            self.regs.rdx = GUEST_LOG_BUFFER_SIZE;
            self.regs.rip = self.pop();
            return true;
        }
        if (self.internal_targets.guest_log_append_formatted != 0 and
            self.regs.rip == self.internal_targets.guest_log_append_formatted)
        {
            var emitted = false;
            if (self.guest_log_buffer_address != 0) {
                emitted = self.emitGuestLog(self.regs.rsi, self.guest_log_buffer_address, self.regs.rdx);
            }
            self.logging.recordEmission(self.regs.rdx, emitted);
            self.regs.rip = self.pop();
            return true;
        }
        if (self.internal_targets.guest_log_append_view != 0 and
            self.regs.rip == self.internal_targets.guest_log_append_view)
        {
            const emitted = self.emitGuestLog(self.regs.rsi, self.regs.rdx, self.regs.rcx);
            self.logging.recordEmission(self.regs.rcx, emitted);
            self.regs.rip = self.pop();
            return true;
        }
        return false;
    }

    fn handleCxxoptsSplitOptionNames(self: *MachOState) bool {
        const output = self.regs.rdi;
        const input = self.regs.rsi;
        const view = compat_runtime.libcppStringView(self, input) orelse return false;
        const bytes = self.guestMemoryConst(view.address, view.length) orelse return false;
        if (bytes.len == 0 or self.guestMemory(output, 24) == null) return false;

        var token_count: u64 = 1;
        var token_start: usize = 0;
        for (bytes, 0..) |byte, index| {
            if (byte != ',') continue;
            var end = index;
            while (end > token_start and bytes[end - 1] == ' ') end -= 1;
            while (token_start < end and bytes[token_start] == ' ') token_start += 1;
            if (token_start == end) return false;
            token_count += 1;
            token_start = index + 1;
        }
        var final_end = bytes.len;
        while (final_end > token_start and bytes[final_end - 1] == ' ') final_end -= 1;
        while (token_start < final_end and bytes[token_start] == ' ') token_start += 1;
        if (token_start == final_end) return false;

        const storage_size = std.math.mul(u64, token_count, 24) catch return false;
        const storage = self.guestAlloc(storage_size, 8) orelse return false;
        @memset(self.guestMemory(output, 24).?, 0);

        token_start = 0;
        var token_index: u64 = 0;
        var cursor: usize = 0;
        while (cursor <= bytes.len) : (cursor += 1) {
            if (cursor != bytes.len and bytes[cursor] != ',') continue;
            var start = token_start;
            var end = cursor;
            while (start < end and bytes[start] == ' ') start += 1;
            while (end > start and bytes[end - 1] == ' ') end -= 1;
            const object = storage + token_index * 24;
            if (!compat_runtime.initLibcppString(self, object, view.address + start, end - start)) return false;
            token_index += 1;
            token_start = cursor + 1;
        }

        self.write64(output, storage);
        self.write64(output + 8, storage + storage_size);
        self.write64(output + 16, storage + storage_size);
        self.cxxopts_split_accelerations += 1;
        if (self.cxxopts_split_accelerations == 1 or self.cxxopts_split_accelerations % 250 == 0) {
            std.debug.print(
                "macho-processor: cxxopts option-name fast path handled {d} call(s)\n",
                .{self.cxxopts_split_accelerations},
            );
        }
        self.regs.rax = output;
        self.regs.rip = self.pop();
        return true;
    }

    fn decodeAt(self: *MachOState) ?DecodedInsn {
        const instruction_bytes: []const u8 = if (self.sparse_memory.executableBytesConst(self.regs.rip, 16)) |sparse_code|
            sparse_code
        else blk: {
            const off = self.translateGuest(self.regs.rip, 1, .execute) orelse {
                self.terminateForGuestAccess(self.regs.rip, 1, .execute, "instruction_fetch");
                return null;
            };
            break :blk self.mem[off..];
        };
        const cache_hash = self.regs.rip *% 0x9E37_79B9_7F4A_7C15;
        const cache_index: usize = @intCast(cache_hash >> DECODE_CACHE_HASH_SHIFT);
        const entry = &self.decode_cache[cache_index];
        var d: DecodedInsn = if (entry.rip == self.regs.rip and entry.code_generation == self.code_generation) blk: {
            self.decode_cache_hits += 1;
            break :blk entry.decoded;
        } else blk: {
            self.decode_cache_misses += 1;
            const decoded = decodeInsn(instruction_bytes);
            entry.* = .{
                .rip = self.regs.rip,
                .code_generation = self.code_generation,
                .decoded = decoded,
            };
            break :blk decoded;
        };

        const addr_size: Size = if (d.has_0x67) .bits32 else .bits64;
        if (d.sib_has_index) {
            const index_val = self.regVal(d.sib_index_reg, addr_size);
            d.addr +%= index_val << @as(u6, d.sib_scale);
        }
        if (d.sib_has_base) {
            const base_val = self.regVal(d.sib_base_reg, addr_size);
            d.addr +%= base_val;
        }
        if (d.rip_relative) {
            d.addr +%= self.regs.rip + d.len;
        }

        return d;
    }

    /// toml++'s `is_ascii(const char*, size_t)` is a pure, bounded predicate.
    /// Xenia's debug build emits an AVX implementation for it.  A valid
    /// 32-byte patch-file read was repeatedly observed executing that loop for
    /// tens of millions of guest steps, even though the source buffer and
    /// length were both verified.  Execute the ABI-equivalent predicate here
    /// so the parser receives the same result without relying on that faulty
    /// guest AVX loop.
    fn handleTomlAsciiFastPath(self: *MachOState) bool {
        const entry = self.toml_ascii_entry orelse return false;
        if (self.regs.rip != entry) return false;

        const raw_length = self.regs.rsi;
        const data_ptr = self.regs.rdi;

        // basic_istream::read() is modeled, but gcount() may execute from a
        // locally-linked libc++ body. The stream bridge mirrors __gc_ into
        // guest memory so raw_length is normally the exact block size. Any
        // mismatch is diagnostic evidence.
        // For .patch.toml files findPatchTomlByteCount() yields the correct
        // block size. For all other file types (profiles, etc.) that suffer
        // from the same buffer_.__size_ corruption, we cannot know the correct
        // block length; return ascii=false to force the parser's slow path
        // (codepoint-by-codepoint stream reads) which bypasses the corrupted
        // size entirely.
        const expected_length = self.libcxx_streams.findPatchTomlByteCount();
        const length_mismatch = raw_length > 1024 * 1024 or
            (expected_length != null and raw_length != expected_length.?);
        const safe_length: u64 = if (length_mismatch) expected_length orelse 0 else raw_length;
        const have_bytes = if (length_mismatch and expected_length == null)
            null
        else
            self.guestMemoryConst(data_ptr, safe_length);
        const ascii = if (have_bytes) |bytes| isAsciiBytes(bytes) else false;
        if (have_bytes == null and raw_length > 1024 * 1024) {
            std.debug.print(
                "macho-processor: toml++ is_ascii fast path UNCERTAIN: pointer=0x{x} raw_bytes={d} forced_ascii=false; parser will use slow path\n",
                .{ data_ptr, raw_length },
            );
        } else if (have_bytes == null) {
            std.debug.print(
                "macho-processor: toml++ is_ascii fast path rejected unreadable input: pointer=0x{x} raw_bytes={d} capped={d}\n",
                .{ data_ptr, raw_length, safe_length },
            );
        } else if (length_mismatch) {
            std.debug.print(
                "macho-processor: toml++ is_ascii ABI LENGTH MISMATCH: pointer=0x{x} raw={d} expected={?d} bounded={d} ascii={}; no guest parser fields were modified\n",
                .{ data_ptr, raw_length, expected_length, safe_length, ascii },
            );
            self.libcxx_streams.dumpPatchTomlDiagnostics("is_ascii length mismatch");
        }

        // In this toml++ build, is_ascii() is called by read_next_block()
        // with its 32-byte raw buffer on the caller's stack. Capture the
        // verified bytes and the owning reader now, then validate the emitted
        // utf8_codepoint block at the next read_next() entry. Every address is
        // checked against both guest memory and the active patch istream.
        if (!length_mismatch and ascii and safe_length <= TOML_CODEPOINT_CAPACITY and self.regs.rbp >= 0x128) {
            const reader_slot = self.regs.rbp - 0x128;
            if (self.guestMemoryConst(reader_slot, 8) != null) {
                const reader = self.read64(reader_slot);
                if (reader != 0 and self.guestMemoryConst(reader, TOML_UTF8_READER_MIN_SIZE) != null) {
                    const istream = self.read64(reader + TOML_READER_ISTREAM_OFFSET);
                    if (self.libcxx_streams.isActivePatchTomlIstream(istream)) {
                        var block = TomlAsciiBlock{ .reader = reader, .length = @intCast(safe_length) };
                        @memcpy(block.bytes[0..block.length], have_bytes.?[0..block.length]);
                        self.toml_ascii_block = block;
                        std.debug.print(
                            "macho-processor: toml++ ASCII codepoint checkpoint armed: reader=0x{x} istream=0x{x} bytes={d} caller_rbp=0x{x}\n",
                            .{ reader, istream, safe_length, self.regs.rbp },
                        );
                    }
                }
            }
        }

        self.regs.rax = @intFromBool(ascii);
        self.regs.rip = self.pop();
        self.toml_ascii_fast_paths +|= 1;
        if (self.toml_ascii_fast_paths <= 8 or self.toml_ascii_fast_paths % 256 == 0) {
            std.debug.print(
                "macho-processor: toml++ is_ascii fast path #{d}: pointer=0x{x} bytes={d} ascii={} return=0x{x}\n",
                .{ self.toml_ascii_fast_paths, data_ptr, safe_length, ascii, self.regs.rip },
            );
        }
        return true;
    }

    fn handleTomlReadNextIntegrity(self: *MachOState) void {
        const entry = self.toml_read_next_entry orelse return;
        if (self.regs.rip != entry) return;
        const pending = self.toml_ascii_block orelse return;
        if (pending.validated or self.regs.rdi != pending.reader) return;

        const reader = pending.reader;
        const expected = pending.bytes[0..pending.length];
        const storage_length: u64 = @as(u64, pending.length) * @as(u64, TOML_CODEPOINT_STRIDE);
        const storage = self.guestMemory(reader + TOML_CODEPOINTS_OFFSET, storage_length) orelse {
            std.debug.print(
                "macho-processor: toml++ ASCII codepoint checkpoint FAILED: reader=0x{x} storage is not writable bytes={d}\n",
                .{ reader, storage_length },
            );
            self.libcxx_streams.dumpPatchTomlDiagnostics("codepoint block unavailable");
            if (self.toml_ascii_block) |*block| block.validated = true;
            return;
        };

        const guest_current = self.read64(reader + TOML_CODEPOINT_CURRENT_OFFSET);
        const guest_count = self.read64(reader + TOML_CODEPOINT_COUNT_OFFSET);
        const report = repairAsciiCodepointBlock(storage, expected);
        if (guest_count != pending.length) {
            self.write64(reader + TOML_CODEPOINT_COUNT_OFFSET, pending.length);
        }

        std.debug.print(
            "macho-processor: toml++ ASCII codepoint checkpoint: reader=0x{x} current={d} guest_count={d} expected_count={d} scalar_repairs={d} raw_repairs={d} first_bad_index={?d} first_bad_scalar=U+{x:0>4} first_bad_raw=0x{x:0>2} expected=0x{x:0>2}\n",
            .{ reader, guest_current, guest_count, pending.length, report.scalar_repairs, report.raw_repairs, report.first_bad_index, report.first_bad_scalar, report.first_bad_raw, report.first_expected },
        );
        if (guest_current > pending.length or guest_count != pending.length or report.scalar_repairs != 0 or report.raw_repairs != 0) {
            std.debug.print(
                "macho-processor: toml++ codepoint integrity mismatch repaired from host-validated ASCII bytes; current index was left unchanged\n",
                .{},
            );
            self.libcxx_streams.dumpPatchTomlDiagnostics("ASCII codepoint integrity mismatch");
        }
        if (self.toml_ascii_block) |*block| block.validated = true;
    }

    fn handlePatchDbEmptyPatchArray(self: *MachOState) bool {
        if (self.regs.rdi != 0 or !self.libcxx_streams.latestPatchSchemaHasEmptyPatchSet()) return false;
        const symbol = self.metadata.nearestSymbol(self.regs.rip) orelse return false;
        if (std.mem.indexOf(u8, symbol.name, "PatchDB13ReadPatchFile") == null or symbol.offset != 0x419) return false;
        const bytes = self.guestMemoryConst(self.regs.rip, 14) orelse return false;
        if (!isPatchDbNullIsArraySequence(bytes)) return false;

        self.patch_db_empty_array_recoveries +|= 1;
        self.libcxx_streams.logEmptyPatchCompatibility("empty-patch compatibility");
        std.debug.print(
            "macho-processor: PatchDB empty-patch compatibility #{d}: rip=0x{x} {s}+0x{x} patch_node=0x0; skipping null virtual is_array() call and selecting Xenia's existing non-array return path at 0x{x}\n",
            .{ self.patch_db_empty_array_recoveries, self.regs.rip, symbol.name, symbol.offset, self.regs.rip + 14 },
        );
        std.debug.print(
            "macho-processor: PatchDB compatibility semantics: equivalent source guard is if (!patch_array || !patch_array->is_array()) return patch_file; parser output and decoded instruction semantics were not modified\n",
            .{},
        );
        self.regs.rax = 0;
        self.setFlagsLogic(0, .bits8);
        self.regs.rip += 14;
        return true;
    }

    fn logStalledInstructionDetails(self: *MachOState) void {
        const bytes = self.guestMemoryConst(self.regs.rip, 16) orelse {
            std.debug.print("macho-processor: stuck-pc decode unavailable: rip=0x{x} instruction bytes are unreadable\n", .{self.regs.rip});
            return;
        };
        const decoded = decodeInsn(bytes);
        const symbol = self.metadata.nearestSymbol(self.regs.rip);
        self.stalled_instruction_reports +|= 1;
        std.debug.print(
            "macho-processor: stuck-pc decode #{d}: rip=0x{x} {s}+0x{x} op={s} len={d} bytes={any} regs(rax/rbx/rcx/rdx/rsi/rdi/rbp/rsp/rflags)=0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}\n",
            .{
                self.stalled_instruction_reports,
                self.regs.rip,
                if (symbol) |entry| entry.name else "<unknown>",
                if (symbol) |entry| entry.offset else 0,
                @tagName(decoded.op),
                decoded.len,
                bytes,
                self.regs.rax,
                self.regs.rbx,
                self.regs.rcx,
                self.regs.rdx,
                self.regs.rsi,
                self.regs.rdi,
                self.regs.rbp,
                self.regs.rsp,
                self.regs.rflags,
            },
        );
        self.dumpRecentTrace();
        std.debug.print(
            "macho-processor: unchanged execution-state capture complete; execution remains active and scheduler recovery is still permitted\n",
            .{},
        );
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

    fn step(self: *MachOState) bool {
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
            std.debug.print(
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
            std.debug.print("macho-processor: decode failed at rip=0x{x}\n", .{rip});
            if (self.fileOffsetForVaddr(rip)) |file_off| {
                const remaining = if (file_off < self.data.len) self.data.len - file_off else 0;
                const file_bytes = self.data[file_off..][0..@min(@as(usize, 16), remaining)];
                std.debug.print("macho-processor: decode failed file_offset=0x{x} bytes={any}\n", .{ file_off, file_bytes });
            } else {
                std.debug.print("macho-processor: decode failed at unmapped address\n", .{});
            }
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.decode_failed);
            self.terminated = true;
            return false;
        };
        if (decoded.op == .invalid) {
            const mem_off = self.addrToOffset(self.regs.rip) orelse 0;
            const mem_bytes = self.mem[mem_off..][0..@min(@as(usize, 16), self.mem.len - mem_off)];
            const rip = self.regs.rip;
            std.debug.print("macho-processor: invalid instruction at rip=0x{x}, mem_off=0x{x}, bytes: {any}\n", .{ rip, mem_off, mem_bytes });
            if (x64_decoder.capabilities.classifyRequirement(mem_bytes)) |requirement| {
                std.debug.print(
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
                std.debug.print("macho-processor: invalid instruction source-map: rip=0x{x} file_off=0x{x} file_bytes={any}\n", .{ rip, file_off, file_bytes });
            } else {
                std.debug.print("macho-processor: invalid instruction source-map: rip=0x{x} file_off=<unmapped>\n", .{rip});
            }
            self.dumpRecentTrace();
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_instruction);
            self.terminated = true;
            return false;
        }
        self.recordTrace(decoded);
        if (self.cooperative_bootstrap_trace_remaining != 0) {
            const symbol = self.metadata.nearestSymbol(self.regs.rip);
            std.debug.print(
                "macho-processor: GTK worker bootstrap: active=0x{x} rip=0x{x} {s}+0x{x} op={s} len={d}\n",
                .{
                    self.active_guest_thread,
                    self.regs.rip,
                    if (symbol) |resolved| resolved.name else "<unknown>",
                    if (symbol) |resolved| resolved.offset else 0,
                    @tagName(decoded.op),
                    decoded.len,
                },
            );
            self.cooperative_bootstrap_trace_remaining -= 1;
        }
        if (self.verbose_trace) log.debug("rip=0x{x} op={s} len={d}", .{ self.regs.rip, @tagName(decoded.op), decoded.len });
        if (self.shouldTraceRIP(self.regs.rip)) {
            const mem_off = self.addrToOffset(self.regs.rip) orelse 0;
            const trace_bytes = self.mem[mem_off..][0..@min(@as(usize, 16), self.mem.len - mem_off)];
            log.info("target-trace: rip=0x{x} op={s} len={d} rsp=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x}", .{
                self.regs.rip,
                @tagName(decoded.op),
                decoded.len,
                self.regs.rsp,
                self.regs.rax,
                self.regs.rcx,
                self.regs.rdx,
            });
            log.info("target-trace-bytes: rip=0x{x} bytes={any}", .{ self.regs.rip, trace_bytes });
        }
        const old_rip = self.regs.rip;
        x64_interpreter.execute(self, decoded);
        if (!self.terminated and self.regs.rip == old_rip) {
            self.regs.rip +%= decoded.len;
        }
        return !self.terminated;
    }

    fn beginGtkMainLoop(self: *MachOState) bool {
        if (self.cooperative_ui_context != null) return false;
        const deferred = self.pthreads.takeNewestDeferred() orelse return false;
        self.cooperative_ui_context = .{
            .regs = self.regs,
            .xmm = self.xmm,
            .ymm_hi = self.ymm_hi,
            .x87 = self.x87,
        };
        self.foreign_objects.main_loop_entries +|= 1;
        self.foreign_objects.main_loop_depth +|= 1;
        if (!self.startDeferredGuestThread(deferred)) {
            self.cooperative_ui_context = null;
            self.foreign_objects.main_loop_depth -|= 1;
            return false;
        }
        self.startup.enter(.gtk_init, self.executed_steps);
        self.startup.enter(.main_loop, self.executed_steps);
        std.debug.print(
            "macho-processor: GTK cooperative main loop entered: guest_thread=0x{x} start=0x{x} deferred_remaining={d}\n",
            .{ deferred.handle, deferred.start_routine, self.pthreads.deferred_threads },
        );
        self.logThreadTable("GTK main loop entered");
        return true;
    }

    fn startDeferredGuestThread(self: *MachOState, deferred: pthread_runtime.DeferredThread) bool {
        if (!self.isExecutableAddress(deferred.start_routine)) {
            std.debug.print("macho-processor: deferred guest thread rejected: start=0x{x} is not executable\n", .{deferred.start_routine});
            return false;
        }
        const requested_stack = if (deferred.stack_size == 0) DEFAULT_GUEST_THREAD_STACK_SIZE else deferred.stack_size;
        const stack_size = std.math.clamp(requested_stack, @as(u64, 64 * 1024), @as(u64, 32 * 1024 * 1024));
        const stack_base = self.guestAlloc(stack_size, 16) orelse return false;

        // Create thread creation context for scheduler
        // const symbol = self.metadata.nearestSymbol(deferred.start_routine);
        // const creation_context = scheduler.ThreadCreationContext{
        //     .level = scheduler.ThreadCreationLevel.pthread,
        //     .thread_type = scheduler.ThreadType.worker, // Default to worker type
        //     .start_routine = deferred.start_routine,
        //     .argument = deferred.argument,
        //     .stack_size = stack_size,
        //     .creator_handle = self.active_guest_thread,
        //     .creation_step = self.executed_steps,
        //     .start_symbol = if (symbol) |s| s.name else "",
        // };

        // Handle thread creation through scheduler
        // const scheduler_handle = self.thread_scheduler.handleThreadCreation(creation_context, stack_base, stack_size) catch |err| {
        //     std.debug.print("macho-processor: scheduler rejected thread creation: {s}\n", .{@errorName(err)});
        //     return false;
        // };

        self.regs = .{};
        self.xmm = [_][16]u8{[_]u8{0} ** 16} ** 16;
        self.ymm_hi = [_][16]u8{[_]u8{0} ** 16} ** 16;
        self.x87 = .{};
        self.cooperative_bootstrap_trace_remaining = 24;
        self.regs.rip = deferred.start_routine;
        self.regs.rdi = deferred.argument;
        self.regs.rsp = alignDown(stack_base + stack_size, 16);
        self.push(GUEST_THREAD_RETURN_SENTINEL);
        self.active_guest_thread = deferred.handle; // Use pthread handle for now
        self.pthreads.markRunning(deferred.handle);
        self.cooperative_thread_switches +|= 1;

        if (self.ui_handoff.isActive()) {
            self.ui_handoff.workerStarted(deferred.handle, self.regs.rip, self.executed_steps);
            self.logThreadTable("UI handoff worker started");
        }

        // Mark thread as started in scheduler
        // self.thread_scheduler.threadStarted(scheduler_handle);

        return true;
    }

    fn saveActiveGuestThread(self: *MachOState, reason: []const u8) bool {
        if (self.active_guest_thread == 0) return false;
        if (self.suspended_guest_thread_count >= self.suspended_guest_threads.len) return false;

        // Save thread state to local suspended guest threads (for compatibility)
        self.suspended_guest_threads[self.suspended_guest_thread_count] = .{
            .handle = self.active_guest_thread,
            .suspended_step = self.executed_steps,
            .reason = reason,
            .regs = self.regs,
            .xmm = self.xmm,
            .ymm_hi = self.ymm_hi,
            .x87 = self.x87,
        };
        self.suspended_guest_thread_count += 1;
        self.pthreads.markContextSuspended(self.active_guest_thread);
        self.scheduler_log.emit(.{
            .kind = .thread_blocked,
            .step = self.executed_steps,
            .thread = self.active_guest_thread,
            .runnable = self.pthreads.activeCount(),
            .blocked = self.pthreads.blocked_threads,
            .reason = reason,
        });

        if (self.ui_handoff.ownsCallbackHandle(self.active_guest_thread)) {
            self.ui_handoff.callbackSuspended(self.executed_steps);
        }

        // Also suspend thread in scheduler
        // _ = self.thread_scheduler.suspendThread(self.active_guest_thread, "cooperative_yield", self.regs.rip);

        self.active_guest_thread = 0;
        return true;
    }

    // Suspended workers are a FIFO queue.  A LIFO pop would immediately resume
    // the same worker that just yielded once all deferred threads had started.
    fn resumeSuspendedGuestThread(self: *MachOState) bool {
        if (self.suspended_guest_thread_count == 0) return false;
        const completed_handoff_thread = self.ui_handoff.completionResumeHandle();
        var attempts = self.suspended_guest_thread_count;
        while (attempts > 0) : (attempts -= 1) {
            var selected_index: usize = 0;
            if (attempts == self.suspended_guest_thread_count) {
                if (completed_handoff_thread != 0) {
                    for (self.suspended_guest_threads[0..self.suspended_guest_thread_count], 0..) |candidate, index| {
                        if (candidate.handle != completed_handoff_thread) continue;
                        selected_index = index;
                        std.debug.print(
                            "scheduler: UI handoff completion-affinity resume: generation={d} scheduling_thread=0x{x} skipped_fifo_entries={d} callback_completed_step={d} step={d}\n",
                            .{ self.ui_handoff.generation, candidate.handle, index, self.ui_handoff.completed_step, self.executed_steps },
                        );
                        break;
                    }
                } else if (self.ui_handoff.shouldPreferCallback(self.executed_steps, COOPERATIVE_THREAD_QUANTUM_STEPS)) {
                    for (self.suspended_guest_threads[0..self.suspended_guest_thread_count], 0..) |candidate, index| {
                        if (!self.ui_handoff.ownsCallbackHandle(candidate.handle)) continue;
                        selected_index = index;
                        const resume_ordinal = self.ui_handoff.callback_resumptions +| 1;
                        if (resume_ordinal <= 8 or resume_ordinal % 1000 == 0) {
                            std.debug.print(
                                "scheduler: UI handoff priority resume: generation={d} callback_handle=0x{x} skipped_fifo_entries={d} step={d} resume={d}\n",
                                .{ self.ui_handoff.generation, candidate.handle, index, self.executed_steps, resume_ordinal },
                            );
                        }
                        break;
                    }
                }
            }
            const context = self.suspended_guest_threads[selected_index];
            if (selected_index + 1 < self.suspended_guest_thread_count) {
                std.mem.copyForwards(
                    SuspendedGuestThread,
                    self.suspended_guest_threads[selected_index .. self.suspended_guest_thread_count - 1],
                    self.suspended_guest_threads[selected_index + 1 .. self.suspended_guest_thread_count],
                );
            }
            self.suspended_guest_thread_count -= 1;
            self.suspended_guest_threads[self.suspended_guest_thread_count] = .{};

            const resume_decision = self.pthreads.resumeCooperativeContext(context.handle, self.guest_time.now());
            if (resume_decision == null) {
                // An unsignaled ordinary condvar wait must stay blocked. Put
                // it at the back of the FIFO and allow another runnable
                // worker or a timed wait to make progress.
                self.suspended_guest_threads[self.suspended_guest_thread_count] = context;
                self.suspended_guest_thread_count += 1;
                continue;
            }

            // Resume thread in scheduler
            // _ = self.thread_scheduler.resumeThread(context.handle);

            self.regs = context.regs;
            self.xmm = context.xmm;
            self.ymm_hi = context.ymm_hi;
            self.x87 = context.x87;
            const saved_rax = self.regs.rax;
            self.regs.rax = resume_decision.?.restoredRax(saved_rax);
            if (resume_decision.?.cancel_deadline_sequence != 0) {
                _ = self.guest_time.cancel(resume_decision.?.cancel_deadline_sequence);
            }
            if (resume_decision.?.rax_override != null) {
                self.cooperative_wait_result_resumes +|= 1;
            } else {
                self.cooperative_preserved_register_resumes +|= 1;
            }
            self.active_guest_thread = context.handle;
            self.pthreads.markRunning(context.handle);
            self.cooperative_thread_switches +|= 1;
            self.scheduler_log.emit(.{
                .kind = .thread_resumed,
                .step = self.executed_steps,
                .thread = context.handle,
                .runnable = self.pthreads.activeCount(),
                .blocked = self.pthreads.blocked_threads,
                .reason = context.reason,
            });
            const resume_count = self.cooperative_preserved_register_resumes + self.cooperative_wait_result_resumes;
            if (resume_count <= 16 or resume_count % 1000 == 0) {
                std.debug.print(
                    "scheduler: guest context resume #{d}: thread=0x{x} reason={s} suspended_step={d} rip=0x{x} rsp=0x{x} rax(saved/restored)=0x{x}/0x{x} policy={s}\n",
                    .{ resume_count, context.handle, context.reason, context.suspended_step, self.regs.rip, self.regs.rsp, saved_rax, self.regs.rax, if (resume_decision.?.rax_override != null) "wait_result_override" else "preserve_all_registers" },
                );
            }
            if (context.handle == completed_handoff_thread and self.ui_handoff.completionResumed(context.handle, self.executed_steps)) {
                std.debug.print(
                    "scheduler: UI handoff dependency resolved: resumed scheduling_thread=0x{x} after callback cleanup; FIFO fallback remains available for unrelated workers\n",
                    .{context.handle},
                );
                self.logThreadTable("UI handoff scheduling thread resumed");
            } else if (self.ui_handoff.ownsCallbackHandle(context.handle)) {
                self.ui_handoff.callbackResumed(self.regs.rip, self.executed_steps);
                if (self.ui_handoff.callback_resumptions <= 8 or self.ui_handoff.callback_resumptions % 1000 == 0) {
                    self.logThreadTable("UI callback resumed");
                }
            } else if (self.ui_handoff.isActive()) {
                self.ui_handoff.workerStarted(context.handle, self.regs.rip, self.executed_steps);
            }
            return true;
        }
        return false;
    }

    fn yieldActiveGuestThreadForWait(self: *MachOState, reason: []const u8) bool {
        if (self.cooperative_ui_context == null or self.active_guest_thread == 0) return false;
        if (self.pthreads.deferred_threads == 0 and self.suspended_guest_thread_count == 0 and self.pendingGtkIdleCallbackCount() == 0) return false;
        const waiter = self.active_guest_thread;
        if (!self.saveActiveGuestThread(reason)) return false;
        var worker: u64 = 0;
        if (self.active_gtk_idle_source == 0 and self.startNextGtkIdleCallback(reason, true)) {
            worker = self.active_guest_thread;
        } else if (self.pthreads.takeNewestDeferred()) |next| {
            if (!self.startDeferredGuestThread(next)) {
                _ = self.resumeSuspendedGuestThread();
                return false;
            }
            worker = next.handle;
        } else {
            if (!self.resumeSuspendedGuestThread()) {
                // If every modeled context is blocked and the only remaining
                // dependency is a timed condition wait, advance virtual time
                // to the earliest deadline. Never do this while another
                // runnable worker can still deliver the real notification.
                var recovered_quiescence = false;
                const deadline = self.pthreads.earliestWaitDeadline() orelse quiescent: {
                    const preferred = if (self.ui_handoff.isActive()) self.ui_handoff.scheduling_thread else 0;
                    if (self.pthreads.wakeOldestCondvarForQuiescence(preferred, self.executed_steps)) |woken| {
                        self.cooperative_quiescence_recoveries +|= 1;
                        const advanced_now = self.guest_time.advanceForQuiescence();
                        if (self.cooperative_quiescence_recoveries <= 8 or self.cooperative_quiescence_recoveries % 100 == 0) {
                            std.debug.print(
                                "scheduler: global quiescence recovery #{d}: POSIX spurious wake thread=0x{x} preferred=0x{x} blocked={d} virtual_now_ns={d} reason={s}; advanced one bounded idle tick because no runnable producer or finite deadline remained\n",
                                .{ self.cooperative_quiescence_recoveries, woken, preferred, self.pthreads.blocked_threads, advanced_now, reason },
                            );
                        }
                        if (self.resumeSuspendedGuestThread()) {
                            recovered_quiescence = true;
                            break :quiescent self.guest_time.now();
                        }
                    }
                    self.scheduler_log.emit(.{
                        .kind = .deadlock,
                        .step = self.executed_steps,
                        .thread = waiter,
                        .runnable = 0,
                        .blocked = self.pthreads.blocked_threads,
                        .reason = reason,
                    });
                    return false;
                };
                if (!recovered_quiescence) {
                    _ = self.guest_time.advanceTo(deadline);
                    var emitted_deadline = false;
                    while (self.guest_time.popDue()) |timer| {
                        emitted_deadline = true;
                        self.scheduler_log.emit(.{
                            .kind = .timer_due,
                            .step = self.executed_steps,
                            .thread = timer.thread,
                            .object = timer.wait_object,
                            .generation = timer.wait_generation,
                            .deadline_ns = timer.deadline_ns,
                            .blocked = self.pthreads.blocked_threads,
                            .reason = "idle_advance_to_deadline",
                        });
                    }
                    if (!emitted_deadline) {
                        self.scheduler_log.emit(.{
                            .kind = .timer_due,
                            .step = self.executed_steps,
                            .thread = waiter,
                            .deadline_ns = deadline,
                            .blocked = self.pthreads.blocked_threads,
                            .reason = "unregistered_wait_deadline",
                        });
                    }
                    if (!self.resumeSuspendedGuestThread()) return false;
                }
            }
            worker = self.active_guest_thread;
        }
        if (worker == waiter) {
            self.cooperative_self_resumes +|= 1;
            if (self.cooperative_self_resumes <= 8 or self.cooperative_self_resumes % 1000 == 0) {
                std.debug.print(
                    "scheduler: cooperative yield found no alternate runnable context: thread=0x{x} reason={s} suspended={d} deferred={d} self_resumes={d}\n",
                    .{ waiter, reason, self.suspended_guest_thread_count, self.pthreads.deferred_threads, self.cooperative_self_resumes },
                );
            }
            return false;
        }
        self.cooperative_wait_yields +|= 1;
        self.scheduler_log.emit(.{
            .kind = .context_switch,
            .step = self.executed_steps,
            .thread = waiter,
            .peer = worker,
            .runnable = self.pthreads.activeCount(),
            .blocked = self.pthreads.blocked_threads,
            .reason = reason,
        });
        if (self.cooperative_wait_yields <= 16 or self.cooperative_wait_yields % 100 == 0) {
            std.debug.print(
                "macho-processor: cooperative wait yield #{d}: waiter=0x{x} -> worker=0x{x} reason={s} deferred_remaining={d} suspended={d} gtk_idle_pending={d}\n",
                .{ self.cooperative_wait_yields, waiter, worker, reason, self.pthreads.deferred_threads, self.suspended_guest_thread_count, self.pendingGtkIdleCallbackCount() },
            );
        }
        if (self.ui_handoff.isActive() or self.cooperative_wait_yields <= 8) {
            self.logThreadTable(reason);
        }
        return true;
    }

    // GTK idle scheduling is a wake-up, not merely queue bookkeeping. Dispatch
    // newly queued UI work at the first safe interpreter boundary even after
    // every pthread worker has started. This is the path used by Xenia's
    // CallInUIThread presenter creation handoff.
    //
    // Guest startup code may also wait by spinning on atomics before it reaches
    // a pthread or libc++ condition-variable call. Give not-yet-started workers
    // a bounded execution slice so one spinner cannot starve their producers.
    fn maybeYieldActiveGuestThreadForQuantum(self: *MachOState) void {
        if (self.cooperative_ui_context == null or self.active_guest_thread == 0) return;
        const pending_idle = self.pendingGtkIdleCallbackCount();
        const idle_callback_inflight = self.active_gtk_idle_source != 0;
        const idle_callback_running = idle_callback_inflight and
            self.isGtkIdleCallbackHandle(self.active_guest_thread);
        const suspended = self.runnableSuspendedSnapshot();

        // A UI callback normally keeps ownership, but it cannot monopolize the
        // only host interpreter while a worker capable of satisfying its
        // dependency is waiting for a slice. Preempt only at a full quantum;
        // the callback context remains stored and retains handoff ownership.
        if (idle_callback_running) {
            if (self.ui_handoff.callbackQuantumAction(self.pthreads.deferred_threads, suspended.runnable) == .rendezvous_worker) {
                self.cooperative_quantum_steps +|= 1;
                if (self.cooperative_quantum_steps >= COOPERATIVE_THREAD_QUANTUM_STEPS) {
                    self.cooperative_quantum_steps = 0;
                    self.ui_callback_retained_quanta +|= 1;
                    const callback = self.active_guest_thread;
                    if (self.yieldActiveGuestThreadForWait("UI callback worker rendezvous")) {
                        self.cooperative_quantum_yields +|= 1;
                        if (self.ui_callback_retained_quanta <= 8 or self.ui_callback_retained_quanta % 1000 == 0) {
                            std.debug.print(
                                "scheduler: UI callback rendezvous: quantum={d} callback=0x{x} -> worker=0x{x} deferred={d} runnable_suspended={d}; callback ownership retained\n",
                                .{ self.ui_callback_retained_quanta, callback, self.active_guest_thread, self.pthreads.deferred_threads, suspended.runnable },
                            );
                        }
                    } else if (self.ui_callback_retained_quanta <= 8 or self.ui_callback_retained_quanta % 1000 == 0) {
                        std.debug.print(
                            "scheduler: retained active UI callback: quantum={d} callback_handle=0x{x} rip=0x{x} deferred_workers={d} runnable_suspended={d}; no eligible rendezvous target\n",
                            .{ self.ui_callback_retained_quanta, self.active_guest_thread, self.regs.rip, self.pthreads.deferred_threads, suspended.runnable },
                        );
                    }
                }
            }
            return;
        }

        const work = scheduler.chooseCooperativeWork(.{
            .pending_idle = pending_idle,
            // An in-flight callback may be suspended on a real dependency.
            // Preserve its UI ownership, but keep rotating runnable workers
            // until the callback itself is selected again. Starting another
            // idle callback here would overwrite the in-flight callback's
            // source and handoff state.
            .callback_inflight = idle_callback_inflight,
            .idle_callback_running = idle_callback_running,
            .deferred_threads = self.pthreads.deferred_threads,
            .suspended_threads = suspended.runnable,
        });
        if (work == .gtk_idle) {
            const scheduling_thread = self.active_guest_thread;
            self.cooperative_quantum_steps = 0;
            if (!self.yieldActiveGuestThreadForWait("GTK idle wake")) {
                self.gtk_idle_dispatch_failures +|= 1;
                const block = self.gtkIdleDispatchBlock();
                if (self.gtk_idle_dispatch_failures <= 8 or self.gtk_idle_dispatch_failures % 100 == 0) {
                    std.debug.print(
                        "macho-processor: GTK idle wake blocked: failure={d} reason={s} active=0x{x} pending={d} suspended={d}/{d}\n",
                        .{ self.gtk_idle_dispatch_failures, @tagName(block), scheduling_thread, pending_idle, self.suspended_guest_thread_count, self.suspended_guest_threads.len },
                    );
                }
                return;
            }
            self.gtk_idle_wakeups +|= 1;
            std.debug.print(
                "macho-processor: GTK idle wake dispatched: wake={d} from_thread=0x{x} source={d} pending={d}\n",
                .{ self.gtk_idle_wakeups, scheduling_thread, self.active_gtk_idle_source, self.pendingGtkIdleCallbackCount() },
            );
            return;
        }
        if (work != .deferred_thread and work != .suspended_thread) return;
        self.cooperative_quantum_steps +|= 1;
        if (self.cooperative_quantum_steps < COOPERATIVE_THREAD_QUANTUM_STEPS) return;
        self.cooperative_quantum_steps = 0;
        const previous_thread = self.active_guest_thread;
        const reason = if (work == .suspended_thread) "runnable rotation quantum" else "deferred thread quantum";
        self.scheduler_log.emit(.{
            .kind = .quantum_expired,
            .step = self.executed_steps,
            .thread = previous_thread,
            .runnable = self.pthreads.activeCount(),
            .blocked = self.pthreads.blocked_threads,
            .reason = reason,
        });
        if (!self.yieldActiveGuestThreadForWait(reason)) return;
        self.cooperative_quantum_yields +|= 1;
        if (work == .suspended_thread) self.cooperative_rotation_yields +|= 1;
        if (self.cooperative_quantum_yields <= 8 or self.cooperative_quantum_yields % 100 == 0) {
            std.debug.print(
                "macho-processor: cooperative quantum yield #{d}: work={s} from=0x{x} to=0x{x} deferred={d} suspended={d} runnable_rotations={d}\n",
                .{ self.cooperative_quantum_yields, @tagName(work), previous_thread, self.active_guest_thread, self.pthreads.deferred_threads, self.suspended_guest_thread_count, self.cooperative_rotation_yields },
            );
        }
    }

    fn finishActiveGuestThread(self: *MachOState) void {
        if (self.active_guest_thread != 0) {
            if (self.isGtkIdleCallbackHandle(self.active_guest_thread)) {
                const source = self.active_gtk_idle_source;
                const callback = self.active_gtk_idle_callback;
                const duration = self.executed_steps -| self.active_gtk_idle_started_step;
                self.gtk_idle_completed +|= 1;
                self.ui_handoff.completed(self.executed_steps);
                std.debug.print(
                    "macho-processor: GTK idle callback completed: source={d} callback=0x{x} duration_steps={d} completed={d} pending={d}\n",
                    .{ source, callback, duration, self.gtk_idle_completed, self.pendingGtkIdleCallbackCount() },
                );
                self.logThreadTable("GTK idle callback completed");
                self.active_guest_thread = 0;
                self.active_gtk_idle_source = 0;
                self.active_gtk_idle_callback = 0;
                self.active_gtk_idle_started_step = 0;
            } else {
                self.pthreads.markCompleted(self.active_guest_thread);
                self.cooperative_thread_returns +|= 1;
                std.debug.print("macho-processor: cooperative guest thread returned: handle=0x{x}\n", .{self.active_guest_thread});
                self.active_guest_thread = 0;
            }
        }
        if (self.startNextGtkIdleCallback("idle-return", false)) return;
        if (self.pthreads.takeNewestDeferred()) |next| {
            if (self.startDeferredGuestThread(next)) return;
        }
        if (self.resumeSuspendedGuestThread()) return;
        self.restoreGtkMainLoopCaller("all cooperative guest threads returned");
    }

    fn scheduleGtkIdleCallback(self: *MachOState, function: u64, data: u64, tag: []const u8) u64 {
        if (function == 0 or !self.isExecutableAddress(function)) {
            std.debug.print(
                "macho-processor: GTK idle rejected: callback=0x{x} executable={} tag={s}\n",
                .{ function, self.isExecutableAddress(function), tag },
            );
            return 0;
        }
        for (&self.gtk_idle_callbacks) |*entry| {
            if (entry.active) continue;
            const source = self.gtk_idle_next_source;
            self.gtk_idle_next_source +|= 1;
            entry.* = .{
                .source_id = source,
                .function = function,
                .data = data,
                .active = true,
                .tag = tag,
                .scheduled_step = self.executed_steps,
                .scheduling_thread = self.active_guest_thread,
                .scheduling_rip = self.regs.rip,
            };
            self.gtk_idle_scheduled +|= 1;
            self.ui_handoff.queued(source, function, self.active_guest_thread, self.regs.rip, self.executed_steps);
            std.debug.print(
                "macho-processor: GTK idle scheduled: source={d} callback=0x{x} data=0x{x} tag={s} step={d} scheduling_thread=0x{x} scheduling_rip=0x{x} ui_context={} pending={d}\n",
                .{ source, function, data, tag, self.executed_steps, self.active_guest_thread, self.regs.rip, self.cooperative_ui_context != null, self.pendingGtkIdleCallbackCount() },
            );
            self.logThreadTable("GTK idle scheduled");
            return source;
        }
        std.debug.print(
            "macho-processor: GTK idle rejected: queue full callback=0x{x} data=0x{x} tag={s}\n",
            .{ function, data, tag },
        );
        return 0;
    }

    fn pendingGtkIdleCallbackCount(self: *const MachOState) usize {
        var count: usize = 0;
        for (&self.gtk_idle_callbacks) |*entry| {
            if (entry.active) count += 1;
        }
        return count;
    }

    fn gtkIdleQueueSnapshot(self: *const MachOState) GtkIdleQueueSnapshot {
        return gtkIdleQueueSnapshotFor(&self.gtk_idle_callbacks);
    }

    fn gtkIdleDispatchBlock(self: *const MachOState) GtkIdleDispatchBlock {
        if (self.cooperative_ui_context == null) return .no_ui_context;
        if (self.active_guest_thread == 0) return .no_active_guest_thread;
        if (self.active_gtk_idle_source != 0) return .callback_already_running;
        if (self.suspended_guest_thread_count >= self.suspended_guest_threads.len) return .suspended_queue_full;
        return .ready;
    }

    fn removeGtkIdleSource(self: *MachOState, source: u64) bool {
        for (&self.gtk_idle_callbacks) |*entry| {
            if (!entry.active or entry.source_id != source) continue;
            entry.* = .{};
            self.gtk_idle_removed +|= 1;
            std.debug.print("macho-processor: GTK idle removed: source={d} pending={d}\n", .{ source, self.pendingGtkIdleCallbackCount() });
            return true;
        }
        return false;
    }

    fn startNextGtkIdleCallback(self: *MachOState, reason: []const u8, active_already_saved: bool) bool {
        self.pumpNativeWindowEvents();
        const context = self.cooperative_ui_context orelse return false;
        for (&self.gtk_idle_callbacks) |*entry| {
            if (!entry.active) continue;
            if (!self.isExecutableAddress(entry.function)) {
                std.debug.print(
                    "macho-processor: GTK idle dropped non-executable callback: source={d} callback=0x{x} tag={s}\n",
                    .{ entry.source_id, entry.function, entry.tag },
                );
                entry.* = .{};
                continue;
            }
            if (!active_already_saved and self.active_guest_thread != 0 and !self.saveActiveGuestThread("GTK idle dispatch")) return false;
            const source = entry.source_id;
            const function = entry.function;
            const data = entry.data;
            const tag = entry.tag;
            const scheduled_step = entry.scheduled_step;
            const scheduling_thread = entry.scheduling_thread;
            const scheduling_rip = entry.scheduling_rip;
            entry.* = .{};
            self.regs = context.regs;
            self.xmm = context.xmm;
            self.ymm_hi = context.ymm_hi;
            self.x87 = context.x87;
            self.regs.rip = function;
            self.regs.rdi = data;
            self.regs.rsp = alignDown(context.regs.rsp, 16);
            self.push(GUEST_THREAD_RETURN_SENTINEL);
            self.active_guest_thread = GTK_IDLE_CALLBACK_HANDLE_BASE + source;
            self.active_gtk_idle_source = source;
            self.active_gtk_idle_callback = function;
            self.active_gtk_idle_started_step = self.executed_steps;
            self.gtk_idle_started +|= 1;
            self.ui_handoff.callbackStarted(self.active_guest_thread, self.regs.rip, self.executed_steps);
            self.cooperative_thread_switches +|= 1;
            std.debug.print(
                "macho-processor: GTK idle dispatch start: source={d} callback=0x{x} data=0x{x} tag={s} reason={s} queue_age_steps={d} scheduling_thread=0x{x} scheduling_rip=0x{x} pending={d}\n",
                .{ source, function, data, tag, reason, self.executed_steps -| scheduled_step, scheduling_thread, scheduling_rip, self.pendingGtkIdleCallbackCount() },
            );
            self.logThreadTable("GTK idle callback started");
            return true;
        }
        return false;
    }

    fn isGtkIdleCallbackHandle(self: *const MachOState, handle: u64) bool {
        _ = self;
        return handle >= GTK_IDLE_CALLBACK_HANDLE_BASE and handle < GTK_IDLE_CALLBACK_HANDLE_BASE + MAX_GTK_IDLE_CALLBACKS + 1024;
    }

    pub fn currentCooperativeThreadHandle(self: *const MachOState) u64 {
        if (self.active_guest_thread == 0 or self.isGtkIdleCallbackHandle(self.active_guest_thread)) {
            return self.pthreads.main_thread_handle;
        }
        return self.active_guest_thread;
    }

    fn threadNumericId(self: *const MachOState, handle: u64) u64 {
        if (handle == 0 or handle == self.pthreads.main_thread_handle or self.isGtkIdleCallbackHandle(handle)) return 1;
        if (self.pthreads.snapshotForHandle(handle)) |snapshot| return snapshot.numeric_id;
        return 0;
    }

    fn threadRole(self: *const MachOState, handle: u64, address: u64) []const u8 {
        if (self.isGtkIdleCallbackHandle(handle)) return "ui_callback";
        if (handle == self.pthreads.main_thread_handle) return "main_ui";
        const symbol = self.metadata.nearestSymbol(address) orelse return "worker";
        if (std.mem.indexOf(u8, symbol.name, "WindowedAppContext") != null or
            std.mem.indexOf(u8, symbol.name, "CallInUIThread") != null or
            std.mem.indexOf(u8, symbol.name, "gtk") != null or
            std.mem.indexOf(u8, symbol.name, "GTK") != null)
        {
            return "ui_worker";
        }
        if (std.mem.indexOf(u8, symbol.name, "Timer") != null or std.mem.indexOf(u8, symbol.name, "timer") != null) return "timer";
        if (std.mem.indexOf(u8, symbol.name, "logging") != null or std.mem.indexOf(u8, symbol.name, "Logger") != null) return "logging";
        if (std.mem.indexOf(u8, symbol.name, "io") != null or std.mem.indexOf(u8, symbol.name, "IO") != null) return "io";
        return "worker";
    }

    fn contextContainsHandle(self: *const MachOState, handle: u64) bool {
        if (self.active_guest_thread == handle) return true;
        for (self.suspended_guest_threads[0..self.suspended_guest_thread_count]) |context| {
            if (context.handle == handle) return true;
        }
        return false;
    }

    fn runnableSuspendedSnapshot(self: *const MachOState) RunnableSuspendedSnapshot {
        var result = RunnableSuspendedSnapshot{};
        for (self.suspended_guest_threads[0..self.suspended_guest_thread_count]) |context| {
            const thread = self.pthreads.snapshotForHandle(context.handle);
            const runnable = if (thread) |snapshot| switch (snapshot.state) {
                .runnable => true,
                .waiting_condvar => snapshot.spurious_wake_pending or
                    snapshot.notified_generation > snapshot.wait_generation or
                    (snapshot.wait_deadline_nanoseconds != 0 and snapshot.wait_deadline_nanoseconds <= self.guest_time.now()),
                .sleeping_until_deadline => snapshot.wait_deadline_nanoseconds != 0 and snapshot.wait_deadline_nanoseconds <= self.guest_time.now(),
                else => false,
            } else true;
            if (!runnable) {
                result.blocked += 1;
                continue;
            }
            result.runnable += 1;
            if (result.oldest_handle != 0 and context.suspended_step >= result.oldest_step) continue;
            result.oldest_handle = context.handle;
            result.oldest_rip = context.regs.rip;
            result.oldest_step = context.suspended_step;
            result.oldest_reason = context.reason;
        }
        return result;
    }

    fn logThreadTable(self: *const MachOState, reason: []const u8) void {
        std.debug.print(
            "scheduler: THREAD TABLE BEGIN reason={s} step={d} active=0x{x} contexts(active/suspended)={d}/{d} pthread_entries={d} deferred={d} ui_phase={s}\n",
            .{ reason, self.executed_steps, self.active_guest_thread, @intFromBool(self.active_guest_thread != 0), self.suspended_guest_thread_count, self.pthreads.created_threads, self.pthreads.deferred_threads, @tagName(self.ui_handoff.phase) },
        );
        std.debug.print("scheduler: CTX  slot handle             tid role         state      age_steps rip                symbol/reason\n", .{});
        if (self.active_guest_thread != 0) {
            const symbol = self.metadata.nearestSymbol(self.regs.rip);
            std.debug.print(
                "scheduler: CTX  run  0x{x:0>16} {d: >3} {s: <12} running    {d: >9} 0x{x:0>16} {s}\n",
                .{ self.active_guest_thread, self.threadNumericId(self.active_guest_thread), self.threadRole(self.active_guest_thread, self.regs.rip), 0, self.regs.rip, if (symbol) |resolved| resolved.name else "<unknown>" },
            );
        }
        for (self.suspended_guest_threads[0..self.suspended_guest_thread_count], 0..) |context, index| {
            const symbol = self.metadata.nearestSymbol(context.regs.rip);
            std.debug.print(
                "scheduler: CTX  q{d:0>2}  0x{x:0>16} {d: >3} {s: <12} suspended  {d: >9} 0x{x:0>16} {s} | {s}\n",
                .{ index, context.handle, self.threadNumericId(context.handle), self.threadRole(context.handle, context.regs.rip), self.executed_steps -| context.suspended_step, context.regs.rip, if (symbol) |resolved| resolved.name else "<unknown>", context.reason },
            );
        }
        std.debug.print("scheduler: REG  slot handle             tid role         pthread_state context stored start              blocked_for wait\n", .{});
        for (0..self.pthreads.tableCapacity()) |slot| {
            const snapshot = self.pthreads.snapshotAt(slot) orelse continue;
            const start_symbol = self.metadata.nearestSymbol(snapshot.start_routine);
            std.debug.print(
                "scheduler: REG  {d:0>2}   0x{x:0>16} {d: >3} {s: <12} {s: <13} {s: <7} {s: <6} 0x{x:0>16} {d: >11} {s}\n",
                .{
                    slot,
                    snapshot.handle,
                    snapshot.numeric_id,
                    self.threadRole(snapshot.handle, snapshot.start_routine),
                    @tagName(snapshot.state),
                    if (snapshot.handle == self.active_guest_thread) "active" else if (self.contextContainsHandle(snapshot.handle)) "queue" else "none",
                    if (snapshot.started) "yes" else "no",
                    snapshot.start_routine,
                    if (snapshot.state == .runnable or snapshot.blocked_since_step == 0) 0 else self.executed_steps -| snapshot.blocked_since_step,
                    if (snapshot.blocked_reason.len != 0) snapshot.blocked_reason else if (start_symbol) |resolved| resolved.name else "<unknown>",
                },
            );
        }
        std.debug.print("scheduler: THREAD TABLE END reason={s}\n", .{reason});
    }

    fn restoreGtkMainLoopCaller(self: *MachOState, reason: []const u8) void {
        const context = self.cooperative_ui_context orelse return;
        self.regs = context.regs;
        self.xmm = context.xmm;
        self.ymm_hi = context.ymm_hi;
        self.x87 = context.x87;
        self.cooperative_ui_context = null;
        self.active_guest_thread = 0;
        self.active_gtk_idle_source = 0;
        self.active_gtk_idle_callback = 0;
        self.active_gtk_idle_started_step = 0;
        self.ui_handoff.reset();
        // The GTK loop returning does not terminate worker threads. Preserve
        // their saved contexts so a later scheduler entry can resume a real
        // notification, cancellation, or finite deadline. Clearing this FIFO
        // orphaned pthread records and made correctly indefinite sleepers look
        // like live threads whose machine contexts had vanished.
        self.foreign_objects.main_loop_depth -|= 1;
        const return_address = self.pop();
        if (return_address == 0 or !self.isExecutableAddress(return_address)) {
            self.terminateForInvalidControlTransfer(.{
                .kind = "gtk_main cooperative return",
                .instruction_address = self.regs.rip,
                .target_address = return_address,
            });
            return;
        }
        self.regs.rip = return_address;
        std.debug.print("macho-processor: GTK cooperative main loop exited: {s}\n", .{reason});
    }

    fn logCooperativeSchedulerSummary(self: *const MachOState) void {
        if (self.cooperative_thread_switches == 0 and self.cooperative_wait_yields == 0) return;
        std.debug.print(
            "macho-processor: cooperative scheduler: switches={d} returns={d} wait_yields={d} sleep_yields={d} quantum_yields={d} runnable_rotations={d} resumes(preserved/wait_override)={d}/{d} self_resumes={d} quiescence(recoveries/clock_ticks/advanced_ns)={d}/{d}/{d} runnable_starvation_warnings={d} suspended={d} active=0x{x} gtk_idle(scheduled/started/completed/removed/pending/wakeups/dispatch_failures/starvation_warnings)={d}/{d}/{d}/{d}/{d}/{d}/{d}/{d}\n",
            .{ self.cooperative_thread_switches, self.cooperative_thread_returns, self.cooperative_wait_yields, self.cooperative_sleep_yields, self.cooperative_quantum_yields, self.cooperative_rotation_yields, self.cooperative_preserved_register_resumes, self.cooperative_wait_result_resumes, self.cooperative_self_resumes, self.cooperative_quiescence_recoveries, self.guest_time.quiescence_advances, self.guest_time.quiescence_advanced_ns, self.cooperative_starvation_warnings, self.suspended_guest_thread_count, self.active_guest_thread, self.gtk_idle_scheduled, self.gtk_idle_started, self.gtk_idle_completed, self.gtk_idle_removed, self.pendingGtkIdleCallbackCount(), self.gtk_idle_wakeups, self.gtk_idle_dispatch_failures, self.gtk_idle_starvation_warnings },
        );
    }

    fn logCooperativeHeartbeat(self: *MachOState) void {
        if (self.cooperative_ui_context == null) return;
        const symbol = self.metadata.nearestSymbol(self.regs.rip);
        const idle = self.gtkIdleQueueSnapshot();
        const idle_age = if (idle.pending != 0) self.executed_steps -| idle.oldest_scheduled_step else 0;
        const suspended = self.runnableSuspendedSnapshot();
        const suspended_age = if (suspended.oldest_handle != 0) self.executed_steps -| suspended.oldest_step else 0;
        const dispatch_block = self.gtkIdleDispatchBlock();
        std.debug.print(
            "macho-processor: GTK cooperative heartbeat: step={d} active=0x{x} rip=0x{x} at {s}+0x{x} deferred={d} suspended(total/runnable/blocked)={d}/{d}/{d} oldest_runnable(handle/rip/age/reason)=0x{x}/0x{x}/{d}/{s} switches={d} wait_yields={d} quantum_yields={d} runnable_rotations={d} waits={d} gtk_idle(scheduled/started/completed/pending)={d}/{d}/{d}/{d} active_idle(source/callback/age)={d}/0x{x}/{d} oldest_pending(source/callback/age/thread/rip/tag)={d}/0x{x}/{d}/0x{x}/0x{x}/{s} dispatch={s}\n",
            .{
                self.executed_steps,
                self.active_guest_thread,
                self.regs.rip,
                if (symbol) |resolved| resolved.name else "<unknown>",
                if (symbol) |resolved| resolved.offset else 0,
                self.pthreads.deferred_threads,
                self.suspended_guest_thread_count,
                suspended.runnable,
                suspended.blocked,
                suspended.oldest_handle,
                suspended.oldest_rip,
                suspended_age,
                suspended.oldest_reason,
                self.cooperative_thread_switches,
                self.cooperative_wait_yields,
                self.cooperative_quantum_yields,
                self.cooperative_rotation_yields,
                self.pthreads.collapsed_waits,
                self.gtk_idle_scheduled,
                self.gtk_idle_started,
                self.gtk_idle_completed,
                idle.pending,
                self.active_gtk_idle_source,
                self.active_gtk_idle_callback,
                if (self.active_gtk_idle_source != 0) self.executed_steps -| self.active_gtk_idle_started_step else 0,
                idle.oldest_source,
                idle.oldest_callback,
                idle_age,
                idle.oldest_scheduling_thread,
                idle.oldest_scheduling_rip,
                idle.oldest_tag,
                @tagName(dispatch_block),
            },
        );
        if (suspended.runnable != 0 and suspended_age >= GTK_IDLE_STARVATION_STEPS and
            self.executed_steps -| self.last_cooperative_starvation_step >= GTK_IDLE_STARVATION_STEPS)
        {
            self.last_cooperative_starvation_step = self.executed_steps;
            self.cooperative_starvation_warnings +|= 1;
            const oldest_symbol = self.metadata.nearestSymbol(suspended.oldest_rip);
            std.debug.print(
                "scheduler: RUNNABLE CONTEXT STARVATION: warning={d} handle=0x{x} rip=0x{x} {s}+0x{x} age={d} reason={s} active=0x{x} runnable/blocked={d}/{d}; round-robin quantum rotation should cap this near {d} steps\n",
                .{ self.cooperative_starvation_warnings, suspended.oldest_handle, suspended.oldest_rip, if (oldest_symbol) |resolved| resolved.name else "<unknown>", if (oldest_symbol) |resolved| resolved.offset else 0, suspended_age, suspended.oldest_reason, self.active_guest_thread, suspended.runnable, suspended.blocked, COOPERATIVE_THREAD_QUANTUM_STEPS * @as(u64, @intCast(suspended.runnable + 1)) },
            );
            self.logThreadTable("runnable context starvation");
        }
        if (idle.pending != 0 and idle_age >= GTK_IDLE_STARVATION_STEPS and dispatch_block != .callback_already_running) {
            self.gtk_idle_starvation_warnings +|= 1;
            std.debug.print(
                "macho-processor: GTK IDLE STARVATION: warning={d} source={d} callback=0x{x} tag={s} queued_for={d} steps scheduling_thread=0x{x} scheduling_rip=0x{x} active=0x{x} block={s} suspended={d}/{d}\n",
                .{ self.gtk_idle_starvation_warnings, idle.oldest_source, idle.oldest_callback, idle.oldest_tag, idle_age, idle.oldest_scheduling_thread, idle.oldest_scheduling_rip, self.active_guest_thread, @tagName(dispatch_block), self.suspended_guest_thread_count, self.suspended_guest_threads.len },
            );
        }
        if (self.ui_handoff.isActive()) {
            std.debug.print(
                "scheduler: UI handoff heartbeat: generation={d} phase={s} source={d} callback_handle=0x{x} callback_rip=0x{x} worker=0x{x} worker_rip=0x{x} no_progress={d} suspend/resume/worker_slices={d}/{d}/{d}\n",
                .{
                    self.ui_handoff.generation,
                    @tagName(self.ui_handoff.phase),
                    self.ui_handoff.source_id,
                    self.ui_handoff.callback_handle,
                    self.ui_handoff.callback_rip,
                    self.ui_handoff.worker_handle,
                    self.ui_handoff.worker_rip,
                    self.executed_steps -| self.ui_handoff.last_progress_step,
                    self.ui_handoff.callback_suspensions,
                    self.ui_handoff.callback_resumptions,
                    self.ui_handoff.worker_slices,
                },
            );
        }
        self.ui_handoff.diagnose(self.executed_steps, GTK_IDLE_STARVATION_STEPS, self.active_guest_thread, self.regs.rip, self.suspended_guest_thread_count);
    }

    // Once the Xenia PageEntry tables have been allocated, setup can spend a
    // long time in memory-manager code without crossing another import
    // boundary. Keep a compact, high-frequency checkpoint so a stalled
    // backing-map or heap pass is observable in the next external run.
    fn logMemoryInitializationProgress(self: *const MachOState, steps: u64) void {
        const symbol = self.metadata.nearestSymbol(self.regs.rip);
        const frame_return_slot = self.regs.rbp +| 8;
        const has_frame_return = self.regs.rbp != 0 and self.guestMemoryConst(frame_return_slot, 8) != null;
        const return_address = if (has_frame_return)
            self.read64(frame_return_slot)
        else if (self.guestMemoryConst(self.regs.rsp, 8) != null)
            self.read64(self.regs.rsp)
        else
            0;
        const return_source = if (has_frame_return) "rbp+8" else "rsp";
        const return_symbol = if (return_address != 0) self.metadata.nearestSymbol(return_address) else null;
        std.debug.print(
            "macho-processor: memory initialization progress: step={d} active=0x{x} rip=0x{x} at {s}+0x{x} return[{s}]=0x{x} {s}+0x{x} page_entry(runs/bytes)={d}/{d} sparse(reserved/mappings/activations)={d}/{d}/{d} heap=0x{x} coop(deferred/suspended/quantum_yields/wait_yields)={d}/{d}/{d}/{d}\n",
            .{
                steps,
                self.active_guest_thread,
                self.regs.rip,
                if (symbol) |resolved| resolved.name else "<unknown>",
                if (symbol) |resolved| resolved.offset else 0,
                return_source,
                return_address,
                if (return_symbol) |resolved| resolved.name else "<unknown>",
                if (return_symbol) |resolved| resolved.offset else 0,
                self.page_entry_bulk_initializations,
                self.page_entry_bulk_bytes,
                self.sparse_memory.total_reserved,
                self.sparse_memory.mappings.items.len,
                self.sparse_memory.activations.items.len,
                self.heap_next,
                self.pthreads.deferred_threads,
                self.suspended_guest_thread_count,
                self.cooperative_quantum_yields,
                self.cooperative_wait_yields,
            },
        );
    }

    fn handleSyntheticRuntimeThunk(self: *MachOState) bool {
        const thunk = compat_runtime.syntheticThunk(self.regs.rip) orelse return false;
        const source_begin = self.regs.rsi;
        const source_end = self.regs.rdx;

        switch (thunk) {
            .ctype_toupper_char => self.regs.rax = std.ascii.toUpper(@as(u8, @truncate(self.regs.rsi))),
            .ctype_tolower_char => self.regs.rax = std.ascii.toLower(@as(u8, @truncate(self.regs.rsi))),
            .ctype_toupper_range, .ctype_tolower_range => {
                if (source_end < source_begin) {
                    self.regs.rax = source_begin;
                } else if (self.guestMemory(source_begin, source_end - source_begin)) |bytes| {
                    for (bytes) |*byte| {
                        byte.* = if (thunk == .ctype_toupper_range) std.ascii.toUpper(byte.*) else std.ascii.toLower(byte.*);
                    }
                    self.regs.rax = source_end;
                } else {
                    self.regs.rax = source_begin;
                }
            },
            .ctype_widen_char, .ctype_narrow_char => self.regs.rax = self.regs.rsi & 0xFF,
            .ctype_widen_range => {
                const count = source_end -| source_begin;
                const source = self.guestMemoryConst(source_begin, count);
                const destination = self.guestMemory(self.regs.rcx, count);
                if (source != null and destination != null) std.mem.copyForwards(u8, destination.?, source.?);
                self.regs.rax = source_end;
            },
            .ctype_narrow_range => {
                const count = source_end -| source_begin;
                const source = self.guestMemoryConst(source_begin, count);
                const destination = self.guestMemory(self.regs.r8, count);
                if (source != null and destination != null) std.mem.copyForwards(u8, destination.?, source.?);
                self.regs.rax = source_end;
            },
        }

        const return_address = self.pop();
        if (self.verbose_trace) std.debug.print("    [synthetic runtime] {s} -> rax=0x{x} return=0x{x}\n", .{ @tagName(thunk), self.regs.rax, return_address });
        if (return_address == 0) {
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
            self.terminated = true;
        } else {
            self.regs.rip = return_address;
        }
        return true;
    }

    fn handleTlvBootstrap(self: *MachOState) bool {
        if (!tlv_runtime.Runtime.handles(self.regs.rip)) return false;
        const descriptor = self.regs.rdi;
        self.regs.rax = self.tlv.resolve(self, descriptor, self.active_guest_thread) orelse 0;
        const return_address = self.pop();
        if (self.regs.rax == 0 or return_address == 0 or !self.isExecutableAddress(return_address)) {
            self.terminateForInvalidControlTransfer(.{
                .kind = "Darwin TLV bootstrap return",
                .instruction_address = tlv_runtime.bootstrap_thunk,
                .operand_address = descriptor,
                .target_address = return_address,
            });
        } else {
            self.regs.rip = return_address;
        }
        return true;
    }

    fn handleBoundImportThunk(self: *MachOState) bool {
        if (self.regs.rip < BOUND_IMPORT_THUNK_BASE) return false;
        for (self.bound_import_thunks) |thunk| {
            if (thunk.address != self.regs.rip) continue;
            self.handleDirectImportCall(.{
                .name = thunk.name,
                .dylib = thunk.dylib,
                .stub_address = thunk.address,
                .lazy_pointer_address = 0,
                .symbol_index = 0,
            });
            return true;
        }
        return false;
    }

    fn handleDynamicLibraryThunk(self: *MachOState) bool {
        const thunk_address = self.regs.rip;
        const virtual_sleep_calls_before = self.dynamic_forwarder.virtualSleepCallCount();
        if (!self.dynamic_forwarder.dispatchGuestSymbol(self, thunk_address)) return false;
        const return_address = self.pop();
        if (self.verbose_trace) {
            std.debug.print(
                "    [dynamic loader thunk] address=0x{x} -> rax=0x{x} return=0x{x}\n",
                .{ thunk_address, self.regs.rax, return_address },
            );
        }
        if (return_address == 0 or !self.isExecutableAddress(return_address)) {
            self.terminateForInvalidControlTransfer(.{
                .kind = "dynamic-library thunk return",
                .instruction_address = thunk_address,
                .target_address = return_address,
            });
        } else {
            self.regs.rip = return_address;
            if (self.dynamic_forwarder.virtualSleepCallCount() != virtual_sleep_calls_before) {
                _ = self.handleVirtualSleepSchedulingBoundary("libc++ virtual sleep thunk");
            }
        }
        return true;
    }

    pub fn run(self: *MachOState) void {
        var steps: u64 = 0;
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
                    std.debug.print(
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
                    std.debug.print(
                        "info(macho): step={d} rip=0x{x} at {s}+0x{x}\n",
                        .{ steps, self.regs.rip, snapshot.symbol, snapshot.symbol_offset },
                    );
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
                self.pthreads.diagnoseStuck(steps, self.regs.rip);
                self.pumpNativeWindowEvents();
                self.logCooperativeHeartbeat();
                self.pthreads.profileThreadStates(&self.wait_profiler, steps, self.active_guest_thread);
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
            std.debug.print(
                "macho-processor: diagnostics invariant repaired: reason={s} faulted={} reclassified={s}\n",
                .{ @tagName(recorded_reason), self.faulted, @tagName(normalized_reason) },
            );
            self.termination_reason = @intFromEnum(normalized_reason);
        }
        if (self.terminated and (self.exit_code != 0 or self.unresolved_import_count != 0)) {
            self.logExitDiagnostics();
        }
    }

    fn logDecodeCacheSummary(self: *const MachOState) void {
        const total = self.decode_cache_hits + self.decode_cache_misses;
        const hit_percent = if (total == 0) 0 else self.decode_cache_hits * 100 / total;
        std.debug.print(
            "macho-processor: decode cache: entries={d} hits={d} misses={d} hit_rate={d}% code_generation={d}\n",
            .{ self.decode_cache.len, self.decode_cache_hits, self.decode_cache_misses, hit_percent, self.code_generation },
        );
    }

    fn logPerformanceAccelerationSummary(self: *const MachOState) void {
        const total = self.import_route_cache_hits + self.import_route_cache_misses;
        const hit_percent = if (total == 0) 0 else self.import_route_cache_hits * 100 / total;
        std.debug.print(
            "macho-processor: import route cache: entries={d} hits={d} misses={d} hit_rate={d}% collisions={d} fallbacks={d}\n",
            .{ IMPORT_ROUTE_CACHE_SIZE, self.import_route_cache_hits, self.import_route_cache_misses, hit_percent, self.import_route_cache_collisions, self.import_route_cache_fallbacks },
        );
        std.debug.print(
            "macho-processor: bulk construction acceleration: page_entry_runs={d} bytes={d}\n",
            .{ self.page_entry_bulk_initializations, self.page_entry_bulk_bytes },
        );
        if (self.lazy_import_direct_dispatches != 0) {
            std.debug.print(
                "macho-processor: lazy import safety: typed_direct_dispatches={d} dyld_stub_binder_entries=0\n",
                .{self.lazy_import_direct_dispatches},
            );
        }
        if (self.patch_db_empty_array_recoveries != 0) {
            std.debug.print(
                "macho-processor: PatchDB empty-patch compatibility: recoveries={d}\n",
                .{self.patch_db_empty_array_recoveries},
            );
        }
        if (self.libcxx_string_substr_fast_paths != 0 or self.profile_host_preflight_checks != 0) {
            std.debug.print(
                "macho-processor: libc++ path slicing: substr_fast_paths={d} profile_host_preflights={d}\n",
                .{ self.libcxx_string_substr_fast_paths, self.profile_host_preflight_checks },
            );
        }
        if (self.opaque_destructor_quarantines != 0) {
            std.debug.print(
                "macho-processor: opaque lifetime safety: destructor_quarantines={d}; only registered opaque identities with validated caller frames were skipped\n",
                .{self.opaque_destructor_quarantines},
            );
        }
        if (self.profile_account_flow.attempts != 0) {
            std.debug.print(
                "macho-processor: profile Account lifecycle: attempts={d} successes={d} failures={d} active={} final_stage={s} last_xuid={x:0>16} last_bytes_read={d}/{d}\n",
                .{ self.profile_account_flow.attempts, self.profile_account_flow.successes, self.profile_account_flow.failures, self.profile_account_flow.active, @tagName(self.profile_account_flow.stage), self.profile_account_flow.xuid, self.profile_account_flow.bytes_read, self.profile_account_flow.requested_bytes },
            );
        }
        if (self.atomic_cmpxchg8.operations != 0 or self.classified_ud2_recoveries != 0 or self.breakpoint_cleanup_recoveries != 0) {
            std.debug.print(
                "macho-processor: atomic/UD2 robustness: cmpxchg8(operations/successes/failures)={d}/{d}/{d} classified_ud2_recoveries={d} timer_recovery(allowed/quarantined)={d}/{d} breakpoint_cleanup_recoveries={d} ownership={s}\n",
                .{ self.atomic_cmpxchg8.operations, self.atomic_cmpxchg8.successes, self.atomic_cmpxchg8.failures, self.classified_ud2_recoveries, self.timer_recovery_tracker.allowed, self.timer_recovery_tracker.quarantined, self.breakpoint_cleanup_recoveries, if (self.atomic_cmpxchg8.indicatesDecoderGap(self.classified_ud2_recoveries)) "rosette_decoder_gap" else "no_decoder_gap_observed" },
            );
        }
        self.diagnostic_throttler.logSummary();
        self.logSharedControlBlockSummary();
    }

    fn logSharedControlBlockSummary(self: *const MachOState) void {
        if (self.libcpp_shared_control_blocks.candidates == 0) return;
        std.debug.print(
            "macho-processor: libc++ shared control-block robustness: candidates={d} verified_vptr_restorations={d} rejected={d}\n",
            .{
                self.libcpp_shared_control_blocks.candidates,
                self.libcpp_shared_control_blocks.recoveries,
                self.libcpp_shared_control_blocks.rejected,
            },
        );
    }

    fn logExitDiagnostics(self: *MachOState) void {
        const reason: exit_diagnostics.TerminationReason = exit_diagnostics.reasonFromValue(self.termination_reason);
        const attribution = exit_diagnostics.attribute(.{
            .reason = reason,
            .faulted = self.faulted,
            .unresolved_import_calls = self.unresolved_import_count,
        });
        var report = exit_diagnostics.ExitReport{
            .exit_code = self.exit_code,
            .reason = reason,
            .faulted = self.faulted,
            .rip = self.regs.rip,
            .regs = .{
                .rax = self.regs.rax,
                .rbx = self.regs.rbx,
                .rcx = self.regs.rcx,
                .rdx = self.regs.rdx,
                .rsi = self.regs.rsi,
                .rdi = self.regs.rdi,
                .rbp = self.regs.rbp,
                .rsp = self.regs.rsp,
                .r8 = self.regs.r8,
                .r9 = self.regs.r9,
                .r10 = self.regs.r10,
                .r11 = self.regs.r11,
                .r12 = self.regs.r12,
                .r13 = self.regs.r13,
                .r14 = self.regs.r14,
                .r15 = self.regs.r15,
            },
            .unresolved_import_calls = self.unresolved_import_count,
            .attribution = attribution,
            .execution_authoritative = attribution.authority == .authoritative,
            .control_transfer_failure = self.terminal_control_transfer,
            .memory_access_failure = self.terminal_memory_failure,
            .runtime_context = .{
                .phase = @tagName(self.startup.phase),
                .steps = self.executed_steps,
                .phase_start_step = self.startup.phase_start_step,
                .initializer = if (self.initializer_resolver.current()) |initializer| initializer.symbol else "",
            },
        };

        if (self.isExecutableAddress(self.regs.rip)) {
            if (self.metadata.nearestSymbol(self.regs.rip)) |symbol| {
                report.terminal_symbol = .{
                    .address = symbol.address,
                    .symbol = symbol.name,
                    .symbol_offset = symbol.offset,
                };
            }
        }

        if (self.terminal_memory_failure) |failure| {
            const terminal_symbol = self.metadata.nearestSymbol(failure.instruction_address);
            const symbol_name = if (terminal_symbol) |symbol| symbol.name else "";
            const fault_policy = self.pointer_firewall.policyAt(failure.address);
            var vtable_header_mapped = true;
            var typeinfo_mapped = true;
            if (self.guestMemoryConst(self.regs.rdi, 8) != null) {
                const vptr = self.read64(self.regs.rdi);
                if (vptr == 0 or vptr < 16 or self.guestMemoryConst(vptr - 16, 16) == null) {
                    vtable_header_mapped = false;
                } else {
                    const typeinfo = self.read64(vptr - 8);
                    typeinfo_mapped = typeinfo != 0 and self.guestMemoryConst(typeinfo, 16) != null;
                }
            }
            const classification = semantic_fault_classifier.classify(.{
                .instruction = failure.instruction,
                .symbol = symbol_name,
                .address = failure.address,
                .rdi = self.regs.rdi,
                .rsi = self.regs.rsi,
                .rdx = self.regs.rdx,
                .rsp = self.regs.rsp,
                .rbp = self.regs.rbp,
                .rdi_mapped = self.guestMemoryConst(self.regs.rdi, 1) != null,
                .rsi_mapped = self.guestMemoryConst(self.regs.rsi, 1) != null,
                .rdx_mapped = self.guestMemoryConst(self.regs.rdx, 1) != null,
                .stack_mapped = self.guestMemoryConst(self.regs.rsp, 1) != null and
                    (self.regs.rbp == 0 or self.guestMemoryConst(self.regs.rbp, 1) != null),
                .pointer_opaque = if (fault_policy) |policy| policy.kind == .opaque_identity and !policy.may_dereference else false,
                .pointer_owner = if (fault_policy) |policy| policy.owner else "",
                .vtable_header_mapped = vtable_header_mapped,
                .typeinfo_mapped = typeinfo_mapped,
            });
            report.semantic_fault = .{
                .class = @tagName(classification.class),
                .reason = classification.reason,
                .next_subsystem = classification.next_subsystem,
                .current_symbol = symbol_name,
                .instruction = failure.instruction,
                .effective_address = failure.address,
            };
            var provenance = self.memory_regions.find(failure.address, @as(u64, failure.bytes));
            if (provenance == null) provenance = self.memory_regions.find(self.regs.rdi, 1);
            if (provenance == null) provenance = self.memory_regions.find(self.regs.rsi, 1);
            if (provenance) |region| {
                report.semantic_fault.?.region_kind = @tagName(region.kind);
                report.semantic_fault.?.region_owner = region.owner;
                report.semantic_fault.?.region_start = region.start;
                report.semantic_fault.?.region_end = region.end;
                report.semantic_fault.?.region_readable = region.permissions.read;
                report.semantic_fault.?.region_writable = region.permissions.write;
                report.semantic_fault.?.region_executable = region.permissions.execute;
                report.semantic_fault.?.region_synthetic = region.isSynthetic();
            }
            var diagnostic_policy = fault_policy;
            if (diagnostic_policy == null) diagnostic_policy = self.pointer_firewall.policyAt(self.regs.rdi);
            if (diagnostic_policy == null) diagnostic_policy = self.pointer_firewall.policyAt(self.regs.rsi);
            if (diagnostic_policy) |policy| {
                report.semantic_fault.?.pointer_kind = @tagName(policy.kind);
                report.semantic_fault.?.pointer_owner = policy.owner;
                report.semantic_fault.?.pointer_may_dereference = policy.may_dereference;
                report.semantic_fault.?.pointer_may_execute = policy.may_execute;
            }
            if (symbol_name.len != 0) self.import_resolver.markCrashNearby(symbol_name);
        } else if (self.terminal_control_transfer) |failure| {
            const terminal_symbol = self.metadata.nearestSymbol(failure.instruction_address);
            const symbol_name = if (terminal_symbol) |symbol| symbol.name else "";
            const target_policy = self.pointer_firewall.policyAt(failure.target_address);
            const classification = semantic_fault_classifier.classify(.{
                .instruction = failure.kind,
                .symbol = symbol_name,
                .address = failure.target_address,
                .rdi = self.regs.rdi,
                .rsi = self.regs.rsi,
                .rdx = self.regs.rdx,
                .rsp = self.regs.rsp,
                .rbp = self.regs.rbp,
                .rdi_mapped = self.guestMemoryConst(self.regs.rdi, 1) != null,
                .rsi_mapped = self.guestMemoryConst(self.regs.rsi, 1) != null,
                .rdx_mapped = self.guestMemoryConst(self.regs.rdx, 1) != null,
                .stack_mapped = self.guestMemoryConst(self.regs.rsp, 1) != null,
                .pointer_opaque = if (target_policy) |policy| policy.kind == .opaque_identity and !policy.may_execute else false,
                .pointer_owner = if (target_policy) |policy| policy.owner else "",
            });
            report.semantic_fault = .{
                .class = @tagName(classification.class),
                .reason = classification.reason,
                .next_subsystem = classification.next_subsystem,
                .current_symbol = symbol_name,
                .instruction = failure.kind,
                .effective_address = failure.target_address,
            };
            if (self.memory_regions.find(failure.target_address, 1)) |region| {
                report.semantic_fault.?.region_kind = @tagName(region.kind);
                report.semantic_fault.?.region_owner = region.owner;
                report.semantic_fault.?.region_start = region.start;
                report.semantic_fault.?.region_end = region.end;
                report.semantic_fault.?.region_readable = region.permissions.read;
                report.semantic_fault.?.region_writable = region.permissions.write;
                report.semantic_fault.?.region_executable = region.permissions.execute;
                report.semantic_fault.?.region_synthetic = region.isSynthetic();
            }
            if (target_policy) |policy| {
                report.semantic_fault.?.pointer_kind = @tagName(policy.kind);
                report.semantic_fault.?.pointer_owner = policy.owner;
                report.semantic_fault.?.pointer_may_dereference = policy.may_dereference;
                report.semantic_fault.?.pointer_may_execute = policy.may_execute;
            }
        } else if (self.faulted) {
            report.semantic_fault = .{
                .class = @tagName(reason),
                .reason = attribution.evidence,
                .next_subsystem = attribution.next_action,
                .current_symbol = if (report.terminal_symbol) |symbol| symbol.symbol else "",
                .instruction = if (report.terminal_instruction) |instruction| instruction.op else "",
                .effective_address = self.regs.rip,
            };
        }

        const terminal_trace_count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
        if (terminal_trace_count > 0) {
            const latest_index = if (self.trace_index == 0) TRACE_BUFFER_LEN - 1 else self.trace_index - 1;
            const latest = self.trace_entries[latest_index];
            var terminal = exit_diagnostics.TerminalInstruction{
                .address = latest.rip,
                .op = @tagName(latest.op),
                .length = latest.len,
            };
            if (self.guestMemoryConst(latest.rip, terminal.bytes.len)) |bytes| {
                terminal.byte_count = @intCast(@min(bytes.len, terminal.bytes.len));
                @memcpy(terminal.bytes[0..terminal.byte_count], bytes[0..terminal.byte_count]);
            }
            report.terminal_instruction = terminal;
            if (report.semantic_fault) |*semantic| {
                if (semantic.instruction.len == 0) semantic.instruction = terminal.op;
            }
        }

        var stack_buf: [16]exit_diagnostics.StackEntry = undefined;
        var stack_count: usize = 0;
        var stack_address = self.regs.rsp;
        while (stack_count < stack_buf.len) : (stack_address +%= 8) {
            const offset = self.addrToOffset(stack_address) orelse break;
            if (offset + 8 > self.mem.len) break;
            const value = self.read64(stack_address);
            stack_buf[stack_count] = .{ .slot_address = stack_address, .value = value };
            if (self.metadata.nearestSymbol(value)) |symbol| {
                stack_buf[stack_count].symbol = symbol.name;
                stack_buf[stack_count].symbol_offset = symbol.offset;
            }
            stack_count += 1;
        }
        report.stack_entries = stack_buf[0..stack_count];

        if (self.cxx_exceptions.last_throw) |thrown| {
            var exception_report = exit_diagnostics.CxxExceptionReport{
                .object_address = thrown.object_address,
                .type_info_address = thrown.type_info_address,
                .type_name = self.cxxExceptionTypeName(thrown.type_info_address) orelse "",
                .type_symbol = self.diagnosticSymbol(thrown.type_info_address),
                .destructor_address = thrown.destructor_address,
                .destructor_symbol = self.diagnosticSymbol(thrown.destructor_address),
                .throw_site = self.diagnosticSymbol(thrown.caller_address),
                .message = self.cxxExceptionMessage(thrown.object_address) orelse "",
                .catch_completed = self.cxx_exceptions.last_throw_caught,
                .active_catches = self.cxx_exceptions.active_catch_count,
                .classification = if (self.spirv_cross.last_classification != .unrelated)
                    self.spirv_cross.lastLabel()
                else
                    "general_cxx_exception",
            };
            if (thrown.allocation) |allocation| {
                exception_report.allocation_matched = true;
                exception_report.allocation_size = allocation.object_size;
                exception_report.allocation_site = self.diagnosticSymbol(allocation.caller_address);
            }
            if (self.last_unwind_inspection) |inspection| {
                exception_report.unwinder_available = inspection.metadata_frames != 0;
                exception_report.unwind_frames = inspection.frame_count;
                exception_report.cleanup_frames = inspection.cleanup_frames;
                exception_report.frame_chain_valid = inspection.frame_chain_valid;
                if (inspection.handler) |handler| {
                    exception_report.handler_found = true;
                    exception_report.handler_address = handler.landing_pad;
                }
                exception_report.phase_two_supported = inspection.phase_two_supported;
                exception_report.phase_two_installed = inspection.phase_two_installed;
                exception_report.cleanups_exhausted_without_handler = self.unwinder.exhaustedWithoutHandler();
            }
            report.cxx_exception = exception_report;
            // Don't flag as unresolved if this is a recognized SPIRV-Cross dummy probe
            const is_expected_probe = std.mem.eql(u8, exception_report.classification, "expected_dummy_probe_unwinding") or
                std.mem.eql(u8, exception_report.classification, "expected_dummy_probe_caught");

            if (!exception_report.catch_completed and !is_expected_probe) {
                report.detail = if (exception_report.cleanups_exhausted_without_handler)
                    "Rosette executed every verified Itanium cleanup landing pad, but the active LSDA route contains no matching catch handler."
                else if (exception_report.phase_two_supported)
                    "Rosette installed a verified Itanium phase-two landing-pad context before the later diagnostic stop."
                else
                    "Rosette completed Itanium phase-one frame and catch inspection; this frame was not safe for phase-two context installation.";
            }
        }

        const memory_trace_count: usize = if (self.memory_trace_filled) MEMORY_TRACE_BUFFER_LEN else self.memory_trace_index;
        var memory_trace_buf: [MEMORY_TRACE_BUFFER_LEN]exit_diagnostics.MemoryAccessEvent = undefined;
        for (0..memory_trace_count) |i| {
            const index = if (self.memory_trace_filled)
                (self.memory_trace_index + i) % MEMORY_TRACE_BUFFER_LEN
            else
                i;
            memory_trace_buf[i] = self.memory_trace_entries[index];
        }
        report.recent_memory_accesses = memory_trace_buf[0..memory_trace_count];

        const import_trace_count: usize = if (self.import_trace_filled) IMPORT_TRACE_BUFFER_LEN else self.import_trace_index;
        if (import_trace_count > 0) {
            var import_trace_buf: [IMPORT_TRACE_BUFFER_LEN]exit_diagnostics.DependencyCall = undefined;
            for (0..import_trace_count) |i| {
                const idx = if (self.import_trace_filled)
                    (self.import_trace_index + i) % IMPORT_TRACE_BUFFER_LEN
                else
                    i;
                const entry = self.import_trace_entries[idx];
                import_trace_buf[i] = .{
                    .symbol = entry.symbol,
                    .image = entry.dylib,
                    .stub_address = entry.stub_address,
                    .return_address = entry.return_address,
                    .synthetic_result = entry.synthetic_result,
                    .caller_symbol = entry.caller_symbol,
                    .caller_offset = entry.caller_offset,
                };
            }
            report.dependency_calls = import_trace_buf[0..import_trace_count];
            report.detail = "The interpreter did not execute these dynamic-library functions; the guest exit code is not authoritative.";
        }

        const trace_count: usize = terminal_trace_count;
        if (trace_count > 0) {
            var trace_buf: [TRACE_BUFFER_LEN]exit_diagnostics.TraceEntry = undefined;
            for (0..trace_count) |i| {
                const idx = if (self.trace_filled)
                    (self.trace_index + i) % TRACE_BUFFER_LEN
                else
                    i;
                const entry = self.trace_entries[idx];
                trace_buf[i] = .{
                    .thread_handle = entry.thread_handle,
                    .rip = entry.rip,
                    .op = @tagName(entry.op),
                    .len = entry.len,
                    .rsp = entry.rsp,
                    .rax = entry.rax,
                    .rbx = entry.rbx,
                    .rcx = entry.rcx,
                    .rdx = entry.rdx,
                    .rsi = entry.rsi,
                    .rdi = entry.rdi,
                    .rbp = entry.rbp,
                    .r8 = entry.r8,
                    .r9 = entry.r9,
                    .r10 = entry.r10,
                    .r11 = entry.r11,
                    .r12 = entry.r12,
                    .r13 = entry.r13,
                    .r14 = entry.r14,
                    .r15 = entry.r15,
                };
            }
            report.last_instructions = trace_buf[0..trace_count];
        }

        exit_diagnostics.logExitReport(report);
    }

    pub fn execute(self: *MachOState, initial_d: DecodedInsn) void {
        var d = initial_d;
        // Detect LOCK prefix (0xF0) from raw instruction bytes at RIP.
        // The LOCK prefix is consumed here rather than threaded through the
        // decoder's 20+ sub-decode functions. This is reliable because 0xF0
        // must be the first byte when present (Intel Vol.2 §2.1.1: LOCK
        // precedes all other prefixes including REX and segment overrides).
        if (self.guestMemoryConst(self.regs.rip, 1)) |bytes| {
            if (bytes[0] == 0xF0) d.lock = true;
        }
        if (d.lock) {
            // Full sequential-consistency barrier (host-native instruction):
            // ensures all prior loads/stores complete before the LOCK-prefixed
            // RMW executes, matching x86 LOCK# signal semantics.
            if (comptime @import("builtin").target.cpu.arch == .aarch64) {
                asm volatile ("dmb ish" ::: .{ .memory = true });
            } else {
                asm volatile ("mfence" ::: .{ .memory = true });
            }
            if (self.verbose_trace) {
                std.debug.print("macho-processor: LOCK prefix consumed at rip=0x{x} op={s}\n", .{ self.regs.rip, @tagName(d.op) });
            }
        }
        switch (d.op) {
            .invalid => {
                std.debug.print("macho-processor: undecoded instruction at rip=0x{x} opcode_prefix=0x{x}\n", .{ self.regs.rip, self.readMemVal(self.regs.rip, .bits8) });
                self.faulted = true;
                self.exit_code = 1;
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_instruction);
                self.terminated = true;
                return;
            },
            .nop => {},
            .cmc => self.regs.rflags ^= RFL_CF,
            .clc => self.regs.rflags &= ~RFL_CF,
            .stc => self.regs.rflags |= RFL_CF,

            .fild_mem16 => _ = self.x87.push(@floatFromInt(@as(i16, @bitCast(@as(u16, @truncate(self.readMemVal(d.addr, .bits16))))))),
            .fild_mem32 => _ = self.x87.push(@floatFromInt(@as(i32, @bitCast(@as(u32, @truncate(self.readMemVal(d.addr, .bits32))))))),
            .fild_mem64 => _ = self.x87.push(@floatFromInt(@as(i64, @bitCast(self.readMemVal(d.addr, .bits64))))),
            .fld_mem32 => _ = self.x87.push(@as(f64, @floatCast(@as(f32, @bitCast(@as(u32, @truncate(self.readMemVal(d.addr, .bits32)))))))),
            .fld_mem64 => _ = self.x87.push(@bitCast(self.readMemVal(d.addr, .bits64))),
            .fstp_mem80 => {
                const output = self.guestMemory(d.addr, 10) orelse {
                    self.terminateForGuestAccess(d.addr, 10, .write, "fstp_mem80");
                    return;
                };
                if (self.x87.pop()) |value| writeExtendedFloat80(output, value) else @memset(output[0..10], 0);
            },
            .fstp_mem32 => {
                if (self.x87.pop()) |value| {
                    self.writeMemVal(d.addr, .bits32, @as(u64, @as(u32, @bitCast(@as(f32, @floatCast(value))))));
                }
            },
            .fstp_mem64 => {
                if (self.x87.pop()) |value| self.writeMemVal(d.addr, .bits64, @as(u64, @bitCast(value)));
            },
            .fld_st => {
                if (self.x87.get(@truncate(d.imm))) |value| _ = self.x87.push(value);
            },
            .fstp_st => {
                if (self.x87.get(0)) |value| {
                    _ = self.x87.set(@truncate(d.imm), value);
                    _ = self.x87.pop();
                }
            },
            .fxch_st => _ = self.x87.exchange(@truncate(d.imm)),
            .ffree_st => self.x87.free(@truncate(d.imm)),
            .fninit => self.x87.reset(),
            .fnstsw_ax => self.setReg(.al_ax_eax_rax, .bits16, self.x87.statusWord()),
            .fnstcw_mem16 => self.writeMemVal(d.addr, .bits16, self.x87.control),
            .fldcw_mem16 => self.x87.control = @truncate(self.readMemVal(d.addr, .bits16)),
            .x87_binary => self.x87.binary(
                @truncate((d.imm >> 3) & 7),
                @truncate((d.imm >> 6) & 7),
                @truncate(d.imm),
                (d.imm & (1 << 9)) != 0,
            ),
            .fucomip_st => self.executeFucomip(@truncate(d.imm)),

            .mov_reg8_mem8 => {
                self.setReg(d.dst_reg, .bits8, self.readMemVal(d.addr, .bits8));
            },
            .mov_reg16_mem16 => {
                self.setReg(d.dst_reg, .bits16, self.readMemVal(d.addr, .bits16));
            },
            .mov_reg32_mem32 => {
                self.setReg(d.dst_reg, .bits32, self.readMemVal(d.addr, .bits32));
            },
            .mov_reg64_mem64 => {
                self.setReg(d.dst_reg, .bits64, self.readMemVal(d.addr, .bits64));
            },

            .mov_mem8_reg8 => {
                self.writeMemVal(d.addr, .bits8, self.regVal(d.src_reg, .bits8));
            },
            .mov_mem16_reg16 => {
                self.writeMemVal(d.addr, .bits16, self.regVal(d.src_reg, .bits16));
            },
            .mov_mem32_reg32 => {
                self.writeMemVal(d.addr, .bits32, self.regVal(d.src_reg, .bits32));
            },
            .mov_mem64_reg64 => {
                self.writeMemVal(d.addr, .bits64, self.regVal(d.src_reg, .bits64));
            },

            .mov_reg_imm => {
                self.setReg(d.dst_reg, d.size, d.imm);
            },

            .mov_mem8_imm8 => {
                self.writeMemVal(d.addr, .bits8, d.imm);
            },
            .mov_mem16_imm16 => {
                self.writeMemVal(d.addr, .bits16, d.imm);
            },
            .mov_mem32_imm32 => {
                self.writeMemVal(d.addr, .bits32, d.imm);
            },
            .mov_mem64_imm32 => {
                self.writeMemVal(d.addr, .bits64, d.imm);
            },

            .mov_reg8_reg8 => {
                self.setReg(d.dst_reg, .bits8, self.regVal(d.src_reg, .bits8));
            },
            .mov_reg16_reg16 => {
                self.setReg(d.dst_reg, .bits16, self.regVal(d.src_reg, .bits16));
            },
            .mov_reg32_reg32 => {
                self.setReg(d.dst_reg, .bits32, self.regVal(d.src_reg, .bits32));
            },
            .mov_reg64_reg64 => {
                self.setReg(d.dst_reg, .bits64, self.regVal(d.src_reg, .bits64));
            },

            .add_accum_imm => self.executeAddRegImm(d, d.size),
            .or_accum_imm => {
                const result = self.regVal(.al_ax_eax_rax, d.size) | d.imm;
                self.setReg(.al_ax_eax_rax, d.size, result);
                self.setFlagsLogic(result, d.size);
            },
            .adc_accum_imm => {
                const input = self.regVal(.al_ax_eax_rax, d.size);
                const carry: u64 = @intFromBool((self.regs.rflags & RFL_CF) != 0);
                const addend = d.imm +% carry;
                const result = input +% addend;
                self.setReg(.al_ax_eax_rax, d.size, result);
                self.setFlagsAdd(input, addend, result, d.size);
            },
            .sbb_accum_imm => {
                const input = self.regVal(.al_ax_eax_rax, d.size);
                const carry: u64 = @intFromBool((self.regs.rflags & RFL_CF) != 0);
                const subtrahend = d.imm +% carry;
                const result = input -% subtrahend;
                self.setReg(.al_ax_eax_rax, d.size, result);
                self.setFlagsSub(input, subtrahend, result, d.size);
            },
            .and_accum_imm => {
                const result = self.regVal(.al_ax_eax_rax, d.size) & d.imm;
                self.setReg(.al_ax_eax_rax, d.size, result);
                self.setFlagsLogic(result, d.size);
            },
            .sub_accum_imm => self.executeSubRegImm(d, d.size),
            .xor_accum_imm => {
                const result = self.regVal(.al_ax_eax_rax, d.size) ^ d.imm;
                self.setReg(.al_ax_eax_rax, d.size, result);
                self.setFlagsLogic(result, d.size);
            },
            .cmp_accum_imm => {
                const input = self.regVal(.al_ax_eax_rax, d.size);
                self.setFlagsSub(input, d.imm, input -% d.imm, d.size);
            },

            .add_reg8_reg8, .add_reg16_reg16, .add_reg32_reg32, .add_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.add_reg8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayRegisterBinary(d, .add, sz);
            },
            .add_reg8_mem8, .add_reg16_mem16, .add_reg32_mem32, .add_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.add_reg8_mem8) + @intFromEnum(Size.bits8));
                self.executeHighwayMemoryBinary(d, .add, sz, .memory_to_register);
            },
            .add_mem8_reg8, .add_mem16_reg16, .add_mem32_reg32, .add_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.add_mem8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayMemoryBinary(d, .add, sz, .register_to_memory);
            },

            .add_reg8_imm8 => self.executeAddRegImm(d, .bits8),
            .add_reg16_imm8 => self.executeAddRegImm(d, .bits16),
            .add_reg32_imm8 => self.executeAddRegImm(d, .bits32),
            .add_reg64_imm8 => self.executeAddRegImm(d, .bits64),
            .add_reg16_imm32 => self.executeAddRegImm(d, .bits16),
            .add_reg32_imm32 => self.executeAddRegImm(d, .bits32),
            .add_reg64_imm32 => self.executeAddRegImm(d, .bits64),

            .sub_reg8_reg8, .sub_reg16_reg16, .sub_reg32_reg32, .sub_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_reg8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayRegisterBinary(d, .sub, sz);
            },
            .sub_reg8_mem8, .sub_reg16_mem16, .sub_reg32_mem32, .sub_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_reg8_mem8) + @intFromEnum(Size.bits8));
                self.executeHighwayMemoryBinary(d, .sub, sz, .memory_to_register);
            },
            .sub_mem8_reg8, .sub_mem16_reg16, .sub_mem32_reg32, .sub_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_mem8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayMemoryBinary(d, .sub, sz, .register_to_memory);
            },
            .sbb_reg8_reg8, .sbb_reg16_reg16, .sbb_reg32_reg32, .sbb_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sbb_reg8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayRegisterBinary(d, .sbb, sz);
            },
            .sub_reg8_imm8, .sub_reg16_imm8, .sub_reg32_imm8, .sub_reg64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_reg8_imm8) + @intFromEnum(Size.bits8));
                self.executeSubRegImm(d, sz);
            },
            .sbb_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = d.imm;
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a -% b -% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },
            .adc_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = d.imm;
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a +% b +% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsAdd(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },
            .adc_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a +% b +% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsAdd(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },
            .sbb_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a -% b -% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },

            .and_reg8_reg8, .and_reg16_reg16, .and_reg32_reg32, .and_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.and_reg8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayRegisterBinary(d, .bit_and, sz);
            },
            .and_reg8_mem8, .and_reg16_mem16, .and_reg32_mem32, .and_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.and_reg8_mem8) + @intFromEnum(Size.bits8));
                self.executeHighwayMemoryBinary(d, .bit_and, sz, .memory_to_register);
            },
            .and_mem8_reg8, .and_mem16_reg16, .and_mem32_reg32, .and_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.and_mem8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayMemoryBinary(d, .bit_and, sz, .register_to_memory);
            },
            .and_reg8_imm8, .and_reg16_imm8, .and_reg32_imm8, .and_reg64_imm8 => self.executeAndRegImm(d),
            .and_reg16_imm32, .and_reg32_imm32, .and_reg64_imm32 => self.executeAndRegImm(d),

            .or_reg8_reg8, .or_reg16_reg16, .or_reg32_reg32, .or_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_reg8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayRegisterBinary(d, .bit_or, sz);
            },
            .or_reg8_mem8, .or_reg16_mem16, .or_reg32_mem32, .or_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_reg8_mem8) + @intFromEnum(Size.bits8));
                self.executeHighwayMemoryBinary(d, .bit_or, sz, .memory_to_register);
            },
            .or_mem8_reg8, .or_mem16_reg16, .or_mem32_reg32, .or_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_mem8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayMemoryBinary(d, .bit_or, sz, .register_to_memory);
            },
            .or_reg8_imm8, .or_reg16_imm8, .or_reg32_imm8, .or_reg64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_reg8_imm8) + @intFromEnum(Size.bits8));
                self.executeHighwayImmediate(d, .bit_or, sz, false);
            },
            .or_mem8_imm8,
            .or_mem16_imm8,
            .or_mem32_imm8,
            .or_mem64_imm8,
            .or_mem16_imm32,
            .or_mem32_imm32,
            .or_mem64_imm32,
            => {
                self.executeHighwayImmediate(d, .bit_or, d.size, true);
            },

            .xor_reg8_reg8, .xor_reg16_reg16, .xor_reg32_reg32, .xor_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_reg8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayRegisterBinary(d, .bit_xor, sz);
            },
            .xor_reg8_mem8, .xor_reg16_mem16, .xor_reg32_mem32, .xor_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_reg8_mem8) + @intFromEnum(Size.bits8));
                self.executeHighwayMemoryBinary(d, .bit_xor, sz, .memory_to_register);
            },
            .xor_mem8_reg8, .xor_mem16_reg16, .xor_mem32_reg32, .xor_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_mem8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayMemoryBinary(d, .bit_xor, sz, .register_to_memory);
            },
            .xor_reg8_imm8, .xor_reg16_imm8, .xor_reg32_imm8, .xor_reg64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_reg8_imm8) + @intFromEnum(Size.bits8));
                self.executeHighwayImmediate(d, .bit_xor, sz, false);
            },

            .cmp_reg8_reg8, .cmp_reg16_reg16, .cmp_reg32_reg32, .cmp_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_reg8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayRegisterBinary(d, .cmp, sz);
            },
            .cmp_reg8_mem8, .cmp_reg16_mem16, .cmp_reg32_mem32, .cmp_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_reg8_mem8) + @intFromEnum(Size.bits8));
                self.executeHighwayMemoryBinary(d, .cmp, sz, .memory_to_register);
            },
            .cmp_mem8_reg8, .cmp_mem16_reg16, .cmp_mem32_reg32, .cmp_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_mem8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayMemoryBinary(d, .cmp, sz, .register_to_memory);
            },
            .cmp_reg8_imm8, .cmp_reg16_imm8, .cmp_reg32_imm8, .cmp_reg64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_reg8_imm8) + @intFromEnum(Size.bits8));
                self.executeHighwayImmediate(d, .cmp, sz, false);
            },
            .cmp_mem8_imm8, .cmp_mem16_imm8, .cmp_mem32_imm8, .cmp_mem64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_mem8_imm8) + @intFromEnum(Size.bits8));
                self.executeHighwayImmediate(d, .cmp, sz, true);
            },

            .test_reg8_reg8, .test_reg16_reg16, .test_reg32_reg32, .test_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.test_reg8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayRegisterBinary(d, .test_bits, sz);
            },
            .test_mem8_reg8, .test_mem16_reg16, .test_mem32_reg32, .test_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.test_mem8_reg8) + @intFromEnum(Size.bits8));
                self.executeHighwayMemoryBinary(d, .test_bits, sz, .register_to_memory);
            },
            .test_reg8_imm8, .test_reg16_imm16, .test_reg32_imm32, .test_reg64_imm32 => self.executeHighwayImmediate(d, .test_bits, d.size, false),
            .test_mem8_imm8, .test_mem16_imm16, .test_mem32_imm32, .test_mem64_imm32 => self.executeHighwayImmediate(d, .test_bits, d.size, true),

            .inc_mem8, .inc_mem16, .inc_mem32, .inc_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.inc_mem8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const r = a +% 1;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsIncDec(a, r, sz, true);
            },
            .inc_reg8, .inc_reg16, .inc_reg32, .inc_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.inc_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const r = a +% 1;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsIncDec(a, r, sz, true);
            },
            .dec_mem8, .dec_mem16, .dec_mem32, .dec_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.dec_mem8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const r = a -% 1;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsIncDec(a, r, sz, false);
            },
            .dec_reg8, .dec_reg16, .dec_reg32, .dec_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.dec_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const r = a -% 1;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsIncDec(a, r, sz, false);
            },

            .neg_reg8, .neg_reg16, .neg_reg32, .neg_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.neg_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const r = (~a +% 1) & maskForSize(sz);
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsSub(0, a, r, sz);
            },
            .neg_mem8, .neg_mem16, .neg_mem32, .neg_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.neg_mem8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const r = (~a +% 1) & maskForSize(sz);
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsSub(0, a, r, sz);
            },
            .not_reg8, .not_reg16, .not_reg32, .not_reg64 => {
                self.setReg(d.dst_reg, d.size, ~self.regVal(d.dst_reg, d.size));
            },
            .not_mem8, .not_mem16, .not_mem32, .not_mem64 => {
                self.writeMemVal(d.addr, d.size, ~self.readMemVal(d.addr, d.size));
            },

            .btr_reg_reg => self.executeBtrRegister(d),
            .btr_mem_reg => self.executeBtrMemory(d),

            .push_reg => {
                self.push(self.regVal(d.dst_reg, .bits64));
            },
            .push_mem64 => {
                self.push(self.readMemVal(d.addr, .bits64));
            },
            .push_imm => {
                self.push(d.imm);
            },

            .pop_reg => {
                self.setReg(d.dst_reg, .bits64, self.pop());
            },
            .pop_mem64 => {
                self.writeMemVal(d.addr, .bits64, self.pop());
            },

            .lods => {
                const src_addr = self.regs.rsi;
                switch (d.size) {
                    .bits8 => self.setReg(.al_ax_eax_rax, .bits8, self.readMemVal(src_addr, .bits8)),
                    .bits16 => self.setReg(.al_ax_eax_rax, .bits16, self.readMemVal(src_addr, .bits16)),
                    .bits32 => self.setReg(.al_ax_eax_rax, .bits32, self.readMemVal(src_addr, .bits32)),
                    .bits64 => self.setReg(.al_ax_eax_rax, .bits64, self.readMemVal(src_addr, .bits64)),
                }
                const stride: u64 = switch (d.size) {
                    .bits8 => 1,
                    .bits16 => 2,
                    .bits32 => 4,
                    .bits64 => 8,
                };
                if ((self.regs.rflags & RFL_DF) != 0) {
                    self.regs.rsi -|= stride;
                } else {
                    self.regs.rsi +|= stride;
                }
            },

            .call_rel32 => {
                const from_rip = self.regs.rip;
                const transfer = x64_decoder.highway.directControl(.call, from_rip, d.len, d.addr, true);
                const target = transfer.target;
                const return_addr = transfer.return_address.?;
                self.pending_control_transfer = .{
                    .kind = "call_rel32",
                    .instruction_address = from_rip,
                    .target_address = target,
                    .return_address = return_addr,
                };
                self.push(return_addr);
                self.regs.rip = target;
                self.logControlFlow("call_rel32", from_rip, target, d.len, return_addr);
            },
            .call_reg64 => {
                const from_rip = self.regs.rip;
                const target = self.regVal(d.dst_reg, .bits64);
                const return_addr = self.regs.rip + d.len;
                if (target == 0) {
                    self.logControlFlow("call_reg64_null", from_rip, target, d.len, return_addr);
                    self.terminateForInvalidControlTransfer(.{
                        .kind = "call_reg64_null",
                        .instruction_address = from_rip,
                        .target_address = target,
                        .return_address = return_addr,
                    });
                } else {
                    self.pending_control_transfer = .{
                        .kind = "call_reg64",
                        .instruction_address = from_rip,
                        .target_address = target,
                        .return_address = return_addr,
                    };
                    self.push(return_addr);
                    self.regs.rip = target;
                    self.logControlFlow("call_reg64", from_rip, target, d.len, return_addr);
                }
            },
            .call_mem64 => {
                const from_rip = self.regs.rip;
                const return_addr = self.regs.rip + d.len;
                // Do not record a terminal page-zero read before a narrowly
                // verified virtual-dispatch recovery has inspected the real
                // C++ object. readMemVal() is intentionally terminal on an
                // unmapped operand, so recovery must precede that side effect.
                const operand_mapped = self.guestMemoryConst(d.addr, @sizeOf(u64)) != null;
                var target: u64 = if (operand_mapped) self.readMemVal(d.addr, .bits64) else 0;
                if (target == 0) {
                    target = self.recoverLibcppSharedControlBlockCall(from_rip, d.addr) orelse 0;
                }
                if (target == 0) {
                    if (!operand_mapped) {
                        self.terminateForGuestAccess(d.addr, @sizeOf(u64), .read, "call_mem64");
                        return;
                    }
                    self.logControlFlow("call_mem64_null", from_rip, target, d.len, return_addr);
                    self.terminateForInvalidControlTransfer(.{
                        .kind = "call_mem64_null",
                        .instruction_address = from_rip,
                        .operand_address = d.addr,
                        .target_address = target,
                        .return_address = return_addr,
                    });
                } else {
                    self.pending_control_transfer = .{
                        .kind = "call_mem64",
                        .instruction_address = from_rip,
                        .operand_address = d.addr,
                        .target_address = target,
                        .return_address = return_addr,
                    };
                    self.push(return_addr);
                    self.regs.rip = target;
                    self.logControlFlow("call_mem64", from_rip, target, d.len, return_addr);
                }
            },

            .ret => {
                if (d.imm > 0) {
                    self.regs.rsp +|= d.imm;
                }
                const ret_addr = self.pop();
                if (ret_addr == 0) {
                    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.ret_stack_empty);
                    self.terminated = true;
                    self.exit_code = self.regs.rax;
                    return;
                }
                self.logControlFlow("ret", self.regs.rip, ret_addr, d.len, null);
                self.regs.rip = ret_addr;
            },

            .jmp_rel8 => {
                const transfer = x64_decoder.highway.directControl(.jump, self.regs.rip, d.len, d.addr, true);
                self.pending_control_transfer = .{
                    .kind = "jmp_rel8",
                    .instruction_address = self.regs.rip,
                    .target_address = transfer.target,
                };
                self.logControlFlow("jmp", self.regs.rip, transfer.target, d.len, null);
                self.regs.rip = transfer.target;
            },
            .jmp_reg64 => {
                const target = self.regVal(d.dst_reg, .bits64);
                if (target == 0) {
                    self.logControlFlow("jmp_reg64_null", self.regs.rip, target, d.len, null);
                    self.terminateForInvalidControlTransfer(.{
                        .kind = "jmp_reg64_null",
                        .instruction_address = self.regs.rip,
                        .target_address = target,
                    });
                } else {
                    self.pending_control_transfer = .{
                        .kind = "jmp_reg64",
                        .instruction_address = self.regs.rip,
                        .target_address = target,
                    };
                    self.logControlFlow("jmp_reg64", self.regs.rip, target, d.len, null);
                    self.regs.rip = target;
                }
            },
            .jmp_mem64 => {
                const stub_rip = self.regs.rip;
                const target = self.readMemVal(d.addr, .bits64);
                const imported = self.metadata.importAtStub(stub_rip);
                if (imported != null and isCooperativeYieldImport(imported.?.name)) {
                    self.pending_import_stub_rip = null;
                    self.lazy_import_direct_dispatches +|= 1;
                    const import = imported.?;
                    self.handleDirectImportCall(import);
                    return;
                }
                const target_is_lazy_helper = target >= self.stub_helper_start and target < self.stub_helper_end;
                switch (lazy_import_stub.chooseDispatch(imported != null, target, target_is_lazy_helper)) {
                    .typed_import => {
                        self.pending_import_stub_rip = null;
                        self.lazy_import_direct_dispatches +|= 1;
                        const import = imported.?;
                        const observation = self.diagnostic_throttler.observe(
                            .lazy_import_dispatch,
                            stub_rip,
                            target,
                        );
                        if (observation.disposition == .detail) {
                            std.debug.print(
                                "macho-processor: lazy import direct dispatch #{d}: thread=0x{x} stub=0x{x} pointer=0x{x} pointer_value=0x{x} import={s} return=0x{x} step={d}; dyld_stub_binder bypassed=true\n",
                                .{ self.lazy_import_direct_dispatches, self.active_guest_thread, stub_rip, d.addr, target, import.name, self.read64(self.regs.rsp), self.executed_steps },
                            );
                            if (target != 0) {
                                if (self.metadata.nearestSymbol(target)) |symbol| {
                                    std.debug.print(
                                        "macho-processor: lazy import pointer classification: target=0x{x} symbol={s}+0x{x} action=typed_import\n",
                                        .{ target, symbol.name, symbol.offset },
                                    );
                                }
                            }
                        } else if (observation.disposition == .checkpoint) {
                            std.debug.print(
                                "macho-processor: repeated lazy import checkpoint: import={s} stub=0x{x} occurrence={d} suppressed_since_previous={d} total_direct_dispatches={d}\n",
                                .{ import.name, stub_rip, observation.occurrence, observation.suppressed_since_emit, self.lazy_import_direct_dispatches },
                            );
                        }
                        self.handleDirectImportCall(import);
                    },
                    .invalid_null_target => {
                        self.logControlFlow("jmp_mem64_null", stub_rip, target, d.len, null);
                        self.terminateForInvalidControlTransfer(.{
                            .kind = "jmp_mem64_null",
                            .instruction_address = stub_rip,
                            .operand_address = d.addr,
                            .target_address = target,
                        });
                    },
                    .follow_target => {
                        self.pending_import_stub_rip = null;
                        self.pending_control_transfer = .{
                            .kind = "jmp_mem64",
                            .instruction_address = stub_rip,
                            .operand_address = d.addr,
                            .target_address = target,
                        };
                        self.logControlFlow("jmp_mem64", stub_rip, target, d.len, null);
                        self.regs.rip = target;
                    },
                }
            },

            .jcc_rel8, .jcc_rel32 => {
                const condMet = x64_decoder.evalCond(self.regs.rflags, d.cond);
                const transfer = x64_decoder.highway.directControl(.conditional_jump, self.regs.rip, d.len, d.addr, condMet);
                if (condMet) {
                    self.logControlFlow("jcc_taken", self.regs.rip, transfer.target, d.len, null);
                    self.regs.rip = transfer.target;
                }
            },

            .bsf_reg_reg,
            .bsf_reg_mem,
            .bsr_reg_reg,
            .bsr_reg_mem,
            .tzcnt_reg_reg,
            .tzcnt_reg_mem,
            .lzcnt_reg_reg,
            .lzcnt_reg_mem,
            => self.executeBitScan(d),

            .popcnt_reg_reg, .popcnt_reg_mem => {
                const source = if (d.op == .popcnt_reg_mem)
                    self.readMemVal(d.addr, d.size)
                else
                    self.regVal(d.src_reg, d.size);
                const result = populationCount(d.size, source, self.regs.rflags);
                self.setReg(d.dst_reg, d.size, result.value);
                self.regs.rflags = result.rflags;
            },

            .bswap_reg => self.setReg(d.dst_reg, d.size, x64_decoder.byteSwap(d.size, self.regVal(d.dst_reg, d.size))),

            .crc32_reg_reg, .crc32_reg_mem => {
                const source = if (d.op == .crc32_reg_mem)
                    self.readMemVal(d.addr, d.size)
                else
                    self.regVal(d.src_reg, d.size);
                const crc = crc32cAccumulator(@truncate(self.regVal(d.dst_reg, .bits32)), source, d.size);
                self.setReg(d.dst_reg, d.dst_size, crc);
            },

            .rol_reg_cl,
            .rol_mem_cl,
            .ror_reg_cl,
            .ror_mem_cl,
            .rol_reg_imm,
            .rol_mem_imm,
            .ror_reg_imm,
            .ror_mem_imm,
            => self.executeRotate(d),

            .shl_reg_cl, .shl_mem_cl => {
                const sz = d.size;
                const is_mem = d.op == .shl_mem_cl;
                const count = self.regVal(.cl_cx_ecx_rcx, .bits8) & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = (a & maskForSize(sz)) << @as(u6, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .shr_reg_cl, .shr_mem_cl => {
                const sz = d.size;
                const is_mem = d.op == .shr_mem_cl;
                const count = self.regVal(.cl_cx_ecx_rcx, .bits8) & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = (a & maskForSize(sz)) >> @as(u6, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .sar_reg_cl, .sar_mem_cl => {
                const sz = d.size;
                const is_mem = d.op == .sar_mem_cl;
                const count = self.regVal(.cl_cx_ecx_rcx, .bits8) & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = arithmeticShiftRight(a, sz, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .shr_reg_imm, .shr_mem_imm => {
                const sz = d.size;
                const is_mem = d.op == .shr_mem_imm;
                const count = d.imm & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = (a & maskForSize(sz)) >> @as(u6, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .shl_reg_imm, .shl_mem_imm => {
                const sz = d.size;
                const is_mem = d.op == .shl_mem_imm;
                const count = d.imm & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = (a & maskForSize(sz)) << @as(u6, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .sar_reg_imm, .sar_mem_imm => {
                const sz = d.size;
                const is_mem = d.op == .sar_mem_imm;
                const count = d.imm & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = arithmeticShiftRight(a, sz, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },

            .mul_reg8 => {
                const a = self.regVal(.al_ax_eax_rax, .bits8);
                const b = self.regVal(d.dst_reg, .bits8);
                const r = a * b;
                self.setReg(.al_ax_eax_rax, .bits16, r);
                self.setFlag(RFL_CF, r >> 8 != 0);
                self.setFlag(RFL_OF, r >> 8 != 0);
            },
            .mul_reg16 => {
                const a = self.regVal(.al_ax_eax_rax, .bits16);
                const b = self.regVal(d.dst_reg, .bits16);
                const r: u32 = @as(u32, @truncate(a)) * @as(u32, @truncate(b));
                self.setReg(.al_ax_eax_rax, .bits16, @truncate(r));
                self.setReg(.dl_dx_edx_rdx, .bits16, @truncate(r >> 16));
                self.setFlag(RFL_CF, r >> 16 != 0);
                self.setFlag(RFL_OF, r >> 16 != 0);
            },
            .mul_reg32 => {
                const a = self.regVal(.al_ax_eax_rax, .bits32);
                const b = self.regVal(d.dst_reg, .bits32);
                const r: u64 = @as(u64, a) * @as(u64, b);
                self.setReg(.al_ax_eax_rax, .bits32, @truncate(r));
                self.setReg(.dl_dx_edx_rdx, .bits32, @truncate(r >> 32));
                self.setFlag(RFL_CF, r >> 32 != 0);
                self.setFlag(RFL_OF, r >> 32 != 0);
            },
            .mul_reg64 => {
                const a = self.regs.rax;
                const b = self.regVal(d.dst_reg, .bits64);
                @setRuntimeSafety(false);
                const r = @as(u128, a) * @as(u128, b);
                self.regs.rax = @truncate(r);
                self.regs.rdx = @truncate(r >> 64);
                self.setFlag(RFL_CF, self.regs.rdx != 0);
                self.setFlag(RFL_OF, self.regs.rdx != 0);
            },

            .div_mem16, .div_reg16 => {
                const divisor: u16 = @truncate(if (d.op == .div_mem16) self.readMemVal(d.addr, .bits16) else self.regVal(d.dst_reg, .bits16));
                if (divisor == 0) return self.raiseDivideError();
                const dividend = (@as(u32, @truncate(self.regs.rdx)) << 16) | @as(u16, @truncate(self.regs.rax));
                const quotient = dividend / divisor;
                if (quotient > std.math.maxInt(u16)) return self.raiseDivideError();
                self.setReg(.al_ax_eax_rax, .bits16, quotient);
                self.setReg(.dl_dx_edx_rdx, .bits16, dividend % divisor);
            },
            .div_mem32, .div_reg32 => {
                const divisor: u32 = @truncate(if (d.op == .div_mem32) self.readMemVal(d.addr, .bits32) else self.regVal(d.dst_reg, .bits32));
                if (divisor == 0) return self.raiseDivideError();
                const dividend = (@as(u64, @truncate(self.regs.rdx)) << 32) | @as(u32, @truncate(self.regs.rax));
                const quotient = dividend / divisor;
                if (quotient > std.math.maxInt(u32)) return self.raiseDivideError();
                self.setReg(.al_ax_eax_rax, .bits32, quotient);
                self.setReg(.dl_dx_edx_rdx, .bits32, dividend % divisor);
            },
            .div_mem64, .div_reg64 => {
                const divisor = if (d.op == .div_mem64) self.readMemVal(d.addr, .bits64) else self.regVal(d.dst_reg, .bits64);
                if (divisor == 0) return self.raiseDivideError();
                const dividend = (@as(u128, self.regs.rdx) << 64) | self.regs.rax;
                const quotient = dividend / divisor;
                if (quotient > std.math.maxInt(u64)) return self.raiseDivideError();
                self.regs.rax = @truncate(quotient);
                self.regs.rdx = @truncate(dividend % divisor);
            },
            .idiv_mem16, .idiv_reg16 => {
                const raw_divisor = if (d.op == .idiv_mem16) self.readMemVal(d.addr, .bits16) else self.regVal(d.dst_reg, .bits16);
                const divisor: i16 = @bitCast(@as(u16, @truncate(raw_divisor)));
                if (divisor == 0) return self.raiseDivideError();
                const dividend_bits = (@as(u32, @truncate(self.regs.rdx)) << 16) | @as(u16, @truncate(self.regs.rax));
                const dividend: i32 = @bitCast(dividend_bits);
                const quotient = @divTrunc(dividend, @as(i32, divisor));
                if (quotient < std.math.minInt(i16) or quotient > std.math.maxInt(i16)) return self.raiseDivideError();
                const remainder = @rem(dividend, @as(i32, divisor));
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(@as(i16, @intCast(quotient)))));
                self.setReg(.dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(@as(i16, @intCast(remainder)))));
            },
            .idiv_mem32, .idiv_reg32 => {
                const raw_divisor = if (d.op == .idiv_mem32) self.readMemVal(d.addr, .bits32) else self.regVal(d.dst_reg, .bits32);
                const divisor: i32 = @bitCast(@as(u32, @truncate(raw_divisor)));
                if (divisor == 0) return self.raiseDivideError();
                const dividend_bits = (@as(u64, @truncate(self.regs.rdx)) << 32) | @as(u32, @truncate(self.regs.rax));
                const dividend: i64 = @bitCast(dividend_bits);
                const quotient = @divTrunc(dividend, @as(i64, divisor));
                if (quotient < std.math.minInt(i32) or quotient > std.math.maxInt(i32)) return self.raiseDivideError();
                const remainder = @rem(dividend, @as(i64, divisor));
                self.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(@as(i32, @intCast(quotient)))));
                self.setReg(.dl_dx_edx_rdx, .bits32, @as(u32, @bitCast(@as(i32, @intCast(remainder)))));
            },
            .idiv_mem64, .idiv_reg64 => {
                const raw_divisor = if (d.op == .idiv_mem64) self.readMemVal(d.addr, .bits64) else self.regVal(d.dst_reg, .bits64);
                const divisor: i64 = @bitCast(raw_divisor);
                if (divisor == 0) return self.raiseDivideError();
                const dividend_bits = (@as(u128, self.regs.rdx) << 64) | self.regs.rax;
                const dividend: i128 = @bitCast(dividend_bits);
                const quotient = @divTrunc(dividend, @as(i128, divisor));
                if (quotient < std.math.minInt(i64) or quotient > std.math.maxInt(i64)) return self.raiseDivideError();
                const remainder = @rem(dividend, @as(i128, divisor));
                self.regs.rax = @bitCast(@as(i64, @intCast(quotient)));
                self.regs.rdx = @bitCast(@as(i64, @intCast(remainder)));
            },
            .imul_reg64_reg64, .imul_reg32_reg32 => {
                const sz = if (d.op == .imul_reg64_reg64) Size.bits64 else Size.bits32;
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a *% b;
                self.setReg(d.dst_reg, sz, r);
            },
            .imul_reg64_mem64, .imul_reg32_mem32 => {
                const sz = if (d.op == .imul_reg64_mem64) Size.bits64 else Size.bits32;
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a *% b;
                self.setReg(d.dst_reg, sz, r);
            },
            .imul_reg64_reg64_imm8, .imul_reg32_reg32_imm8 => {
                const sz = if (d.op == .imul_reg64_reg64_imm8) Size.bits64 else Size.bits32;
                // Three-operand IMUL reads r/m as its source and does not use
                // the old destination value. Using dst here corrupts pointer
                // and index scaling whenever source and destination differ.
                const r = threeOperandImulResult(&self.regs, d, sz);
                self.setReg(d.dst_reg, sz, r);
            },
            .imul_reg64_mem64_imm8, .imul_reg32_mem32_imm8 => {
                const sz = if (d.op == .imul_reg64_mem64_imm8) Size.bits64 else Size.bits32;
                const a = self.readMemVal(d.addr, sz);
                const r = a *% d.imm;
                self.setReg(d.dst_reg, sz, r);
            },

            .lea_reg_mem => {
                self.setReg(d.dst_reg, d.size, d.addr);
            },

            .movzx_reg32_mem8 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits8)
                else
                    self.readMemVal(d.addr, .bits8);
                self.setReg(d.dst_reg, d.size, val);
            },
            .movzx_reg32_mem16 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits16)
                else
                    self.readMemVal(d.addr, .bits16);
                self.setReg(d.dst_reg, d.size, val);
            },
            .movsx_reg32_mem8 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits8)
                else
                    self.readMemVal(d.addr, .bits8);
                const signed_val = @as(u32, @bitCast(@as(i32, @as(i8, @bitCast(@as(u8, @truncate(val)))))));
                self.setReg(d.dst_reg, d.size, signed_val);
            },
            .movsx_reg32_mem16 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits16)
                else
                    self.readMemVal(d.addr, .bits16);
                const signed_val = @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(val)))))));
                self.setReg(d.dst_reg, d.size, signed_val);
            },
            .movsxd_reg64_reg32 => {
                const val = self.regVal(d.src_reg, .bits32);
                const signed_val = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(val)))))));
                self.setReg(d.dst_reg, .bits64, signed_val);
            },
            .movsxd_reg64_mem32 => {
                const val = self.readMemVal(d.addr, .bits32);
                const signed_val = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(val)))))));
                self.setReg(d.dst_reg, .bits64, signed_val);
            },

            .cbw => {
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(@as(u8, @truncate(self.regs.rax))))))));
            },
            .cwde => {
                self.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(self.regs.rax))))))));
            },
            .cdqe => {
                self.regs.rax = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(self.regs.rax)))))));
            },
            .cwd => {
                const val = self.regVal(.al_ax_eax_rax, .bits16);
                const sign = @as(u16, @bitCast(@as(i16, @intCast(val)))) >> 15;
                self.setReg(.dl_dx_edx_rdx, .bits16, if (sign != 0) 0xFFFF else 0);
            },
            .cdq => {
                const val = self.regVal(.al_ax_eax_rax, .bits32);
                const sign = @as(u32, @bitCast(@as(i32, @intCast(val)))) >> 31;
                self.setReg(.dl_dx_edx_rdx, .bits32, if (sign != 0) 0xFFFF_FFFF else 0);
            },
            .cqo => {
                const val = self.regs.rax;
                const sign = (val & 0x8000_0000_0000_0000) != 0;
                self.regs.rdx = if (sign) 0xFFFF_FFFF_FFFF_FFFF else 0;
            },

            .cmovcc_reg_reg => {
                if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                    self.setReg(d.dst_reg, d.size, self.regVal(d.src_reg, d.size));
                }
            },
            .cmovcc_reg_mem => {
                if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                    self.setReg(d.dst_reg, d.size, self.readMemVal(d.addr, d.size));
                }
            },

            .setcc_reg8 => {
                if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                    self.setReg(d.dst_reg, .bits8, 1);
                } else {
                    self.setReg(d.dst_reg, .bits8, 0);
                }
            },
            .setcc_mem8 => {
                if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                    self.writeMemVal(d.addr, .bits8, 1);
                } else {
                    self.writeMemVal(d.addr, .bits8, 0);
                }
            },

            .cmpxchg_mem8_reg8,
            .cmpxchg_mem16_reg16,
            .cmpxchg_mem32_reg32,
            .cmpxchg_mem64_reg64,
            .cmpxchg_reg8_reg8,
            .cmpxchg_reg16_reg16,
            .cmpxchg_reg32_reg32,
            .cmpxchg_reg64_reg64,
            => {
                const size = d.size;
                const expected = self.regVal(.al_ax_eax_rax, size);
                const actual = if (d.is_reg_form)
                    self.regVal(d.dst_reg, size)
                else
                    self.readMemVal(d.addr, size);
                const replacement = self.regVal(d.src_reg, size);
                const outcome = atomic_compare_exchange.evaluate(expected, actual, replacement);
                const matched = outcome.matched;
                if (size == .bits8) {
                    self.atomic_cmpxchg8.record(matched);
                    if (self.atomic_cmpxchg8.operations <= 16 or (!matched and self.atomic_cmpxchg8.failures <= 16)) {
                        const symbol = self.metadata.nearestSymbol(self.regs.rip);
                        const adjacent = if (!d.is_reg_form) self.guestMemoryConst(d.addr, 4) else null;
                        const adjacent_value = if (adjacent) |bytes| std.mem.readInt(u32, bytes[0..4], .little) else 0;
                        std.debug.print(
                            "macho-processor: atomic cmpxchg8 #{d}: rip=0x{x} {s}+0x{x} target={s}0x{x} expected=0x{x:0>2} actual=0x{x:0>2} replacement=0x{x:0>2} matched={} adjacent32_mapped={} adjacent32=0x{x:0>8}\n",
                            .{ self.atomic_cmpxchg8.operations, self.regs.rip, if (symbol) |entry| entry.name else "<unknown>", if (symbol) |entry| entry.offset else 0, if (d.is_reg_form) "register:" else "memory:", if (d.is_reg_form) @intFromEnum(d.dst_reg) else d.addr, expected, actual, replacement, matched, adjacent != null, adjacent_value },
                        );
                    }
                }
                self.regs.rflags &= ~(RFL_ZF | RFL_CF);
                self.regs.rflags |= if (matched) RFL_ZF else RFL_CF;
                if (matched) {
                    if (d.is_reg_form) {
                        self.setReg(d.dst_reg, size, outcome.destination);
                    } else {
                        self.writeMemVal(d.addr, size, outcome.destination);
                    }
                } else {
                    self.setReg(.al_ax_eax_rax, size, outcome.accumulator);
                }
            },

            .cmpxchg8b_mem, .cmpxchg16b_mem => {
                const is_16b = d.op == .cmpxchg16b_mem;
                // CMPXCHG8B compares EDX:EAX with m64; CMPXCHG16B compares RDX:RAX with m128
                const expected_lo = self.regVal(.al_ax_eax_rax, .bits32);
                const expected_hi = self.regVal(.dl_dx_edx_rdx, if (is_16b) .bits64 else .bits32);
                const replacement_lo = self.regVal(.cl_cx_ecx_rcx, if (is_16b) .bits64 else .bits32);
                const replacement_hi = self.regVal(.bl_bx_ebx_rbx, if (is_16b) .bits64 else .bits32);

                const total_bytes: usize = if (is_16b) 16 else 8;
                const actual_lo = self.readMemVal(d.addr, if (is_16b) .bits64 else .bits32);
                const actual_hi = if (is_16b) self.readMemVal(d.addr + 8, .bits64) else 0;

                const matched = expected_lo == actual_lo and expected_hi == actual_hi;

                if (matched) {
                    self.writeMemVal(d.addr, if (is_16b) .bits64 else .bits32, replacement_lo);
                    if (is_16b) self.writeMemVal(d.addr + 8, .bits64, replacement_hi);
                } else {
                    self.setReg(.al_ax_eax_rax, if (is_16b) .bits64 else .bits32, actual_lo);
                    self.setReg(.dl_dx_edx_rdx, if (is_16b) .bits64 else .bits32, actual_hi);
                }

                self.regs.rflags &= ~RFL_ZF;
                self.regs.rflags |= if (matched) RFL_ZF else 0;

                if (total_bytes == 8) {
                    self.atomic_cmpxchg8.record(matched);
                    if (self.atomic_cmpxchg8.operations <= 16 or (!matched and self.atomic_cmpxchg8.failures <= 16)) {
                        const symbol = self.metadata.nearestSymbol(self.regs.rip);
                        std.debug.print(
                            "macho-processor: atomic cmpxchg8b #{d}: rip=0x{x} {s}+0x{x} target=0x{x} expected=0x{x:0>8}:0x{x:0>8} actual=0x{x:0>8}:0x{x:0>8} replacement=0x{x:0>8}:0x{x:0>8} matched={}\n",
                            .{ self.atomic_cmpxchg8.operations, self.regs.rip, if (symbol) |entry| entry.name else "<unknown>", if (symbol) |entry| entry.offset else 0, d.addr, expected_hi, expected_lo, actual_hi, actual_lo, replacement_hi, replacement_lo, matched },
                        );
                    }
                }
            },

            .xchg_mem32_reg32 => {
                // XCHG with memory is architecturally always atomic (implicit LOCK#)
                if (comptime @import("builtin").target.cpu.arch == .aarch64) {
                    asm volatile ("dmb ish" ::: .{ .memory = true });
                } else {
                    asm volatile ("mfence" ::: .{ .memory = true });
                }
                const a = self.readMemVal(d.addr, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                self.writeMemVal(d.addr, .bits32, b);
                self.setReg(d.src_reg, .bits32, a);
            },
            .xchg_mem64_reg64 => {
                // XCHG with memory is architecturally always atomic (implicit LOCK#)
                if (comptime @import("builtin").target.cpu.arch == .aarch64) {
                    asm volatile ("dmb ish" ::: .{ .memory = true });
                } else {
                    asm volatile ("mfence" ::: .{ .memory = true });
                }
                const a = self.readMemVal(d.addr, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                self.writeMemVal(d.addr, .bits64, b);
                self.setReg(d.src_reg, .bits64, a);
            },
            .xchg_reg32_reg32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                self.setReg(d.dst_reg, .bits32, b);
                self.setReg(d.src_reg, .bits32, a);
            },
            .xchg_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                self.setReg(d.dst_reg, .bits64, b);
                self.setReg(d.src_reg, .bits64, a);
            },
            .xadd_mem32_reg32, .xadd_mem64_reg64 => {
                const sz: Size = if (d.op == .xadd_mem64_reg64) .bits64 else .bits32;
                const old_mem = self.readMemVal(d.addr, sz);
                const old_reg = self.regVal(d.src_reg, sz);
                const result = old_mem +% old_reg;
                self.writeMemVal(d.addr, sz, result);
                self.setReg(d.src_reg, sz, old_mem);
                self.setFlagsAdd(old_mem, old_reg, result, sz);
            },

            .xorps_xmm_xmm => {
                const dst = d.xmm_dst;
                const src = d.xmm_src;
                for (&self.xmm[dst], self.xmm[src]) |*d8, s8| d8.* = d8.* ^ s8;
            },
            .movups_xmm_xmm, .movaps_xmm_xmm => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            },
            .movups_xmm_mem, .movaps_xmm_mem => {
                self.xmm[d.xmm_dst] = self.readMem128(d.addr);
            },
            .movups_mem_xmm, .movaps_mem_xmm => {
                self.writeMem128(d.addr, self.xmm[d.xmm_src]);
            },
            .vmovd_xmm_reg32, .vmovd_xmm_mem32 => {
                const value: u32 = @truncate(if (d.op == .vmovd_xmm_reg32)
                    self.regVal(d.src_reg, .bits32)
                else
                    self.readMemVal(d.addr, .bits32));
                @memset(&self.xmm[d.xmm_dst], 0);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
                std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], value, .little);
            },
            .vmovq_xmm_reg64, .vmovq_xmm_mem64 => {
                const value = if (d.op == .vmovq_xmm_reg64)
                    self.regVal(d.src_reg, .bits64)
                else
                    self.readMemVal(d.addr, .bits64);
                @memset(&self.xmm[d.xmm_dst], 0);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], value, .little);
            },
            .vmovq_reg64_xmm, .vmovq_mem64_xmm => {
                const value = std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little);
                if (d.op == .vmovq_reg64_xmm) {
                    self.setReg(d.dst_reg, .bits64, value);
                } else {
                    self.writeMemVal(d.addr, .bits64, value);
                }
            },
            .vpinsrb_xmm_xmm_reg32, .vpinsrb_xmm_xmm_mem8 => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                const value: u8 = @truncate(if (d.op == .vpinsrb_xmm_xmm_reg32)
                    self.regVal(d.src_reg, .bits32)
                else
                    self.readMemVal(d.addr, .bits8));
                self.xmm[d.xmm_dst][@intCast(d.imm & 0x0F)] = value;
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .vpshufb => {
                const source_low = self.xmm[d.xmm_src];
                const mask_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = shuffleBytes(source_low, mask_low);
                if (d.vector_256) {
                    const source_high = self.ymm_hi[d.xmm_src];
                    const mask_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = shuffleBytes(source_high, mask_high);
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vpcmpeqb, .vpcmpeqw, .vpcmpeqd, .vpcmpeqq, .vpcmpgtb, .vpcmpgtw, .vpcmpgtd, .vpcmpgtq => {
                const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = applyVexCompare(self.xmm[d.xmm_src], rhs_low, d.op);
                if (d.vector_256) {
                    const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = applyVexCompare(self.ymm_hi[d.xmm_src], rhs_high, d.op);
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vptest => {
                const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                const low_zf = bitwiseAndAllZero(self.xmm[d.xmm_src], rhs_low);
                const low_cf = bitwiseAndNotAllZero(self.xmm[d.xmm_src], rhs_low);
                if (d.vector_256) {
                    const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.regs.rflags &= ~(RFL_OF | RFL_SF | RFL_ZF | RFL_AF | RFL_PF | RFL_CF);
                    if (low_zf and bitwiseAndAllZero(self.ymm_hi[d.xmm_src], rhs_high)) self.regs.rflags |= RFL_ZF;
                    if (low_cf and bitwiseAndNotAllZero(self.ymm_hi[d.xmm_src], rhs_high)) self.regs.rflags |= RFL_CF;
                } else {
                    self.regs.rflags &= ~(RFL_OF | RFL_SF | RFL_ZF | RFL_AF | RFL_PF | RFL_CF);
                    if (low_zf) self.regs.rflags |= RFL_ZF;
                    if (low_cf) self.regs.rflags |= RFL_CF;
                }
            },
            .vpunpckldq => {
                const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = unpackLowDwords(self.xmm[d.xmm_src], rhs_low);
                if (d.vector_256) {
                    const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = unpackLowDwords(self.ymm_hi[d.xmm_src], rhs_high);
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vpunpcklqdq => {
                const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = unpackLowQwords(self.xmm[d.xmm_src], rhs_low);
                if (d.vector_256) {
                    const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = unpackLowQwords(self.ymm_hi[d.xmm_src], rhs_high);
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vpermilpd => {
                const source_low = if (d.is_reg_form) self.xmm[d.xmm_src] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = permutePackedDoubles(source_low, @truncate(d.imm));
                if (d.vector_256) {
                    const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = permutePackedDoubles(source_high, @truncate(d.imm >> 2));
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vmovdqu_xmm_xmm, .vmovdqa_xmm_xmm, .vmovups_xmm_xmm, .vmovaps_xmm_xmm, .vmovupd_xmm_xmm, .vmovapd_xmm_xmm => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .vmovdqu_xmm_mem, .vmovdqa_xmm_mem, .vmovups_xmm_mem, .vmovaps_xmm_mem, .vmovupd_xmm_mem, .vmovapd_xmm_mem => {
                self.xmm[d.xmm_dst] = self.readMem128(d.addr);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .vmovdqu_mem_xmm, .vmovdqa_mem_xmm, .vmovups_mem_xmm, .vmovaps_mem_xmm, .vmovupd_mem_xmm, .vmovapd_mem_xmm => {
                self.writeMem128(d.addr, self.xmm[d.xmm_src]);
            },
            .vmovdqu_ymm_ymm, .vmovdqa_ymm_ymm, .vmovups_ymm_ymm, .vmovaps_ymm_ymm, .vmovupd_ymm_ymm, .vmovapd_ymm_ymm => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                self.ymm_hi[d.xmm_dst] = self.ymm_hi[d.xmm_src];
            },
            .vmovdqu_ymm_mem, .vmovdqa_ymm_mem, .vmovups_ymm_mem, .vmovaps_ymm_mem, .vmovupd_ymm_mem, .vmovapd_ymm_mem => {
                self.xmm[d.xmm_dst] = self.readMem128(d.addr);
                self.ymm_hi[d.xmm_dst] = self.readMem128(d.addr + 16);
            },
            .vmovdqu_mem_ymm, .vmovdqa_mem_ymm, .vmovups_mem_ymm, .vmovaps_mem_ymm, .vmovupd_mem_ymm, .vmovapd_mem_ymm => {
                self.writeMem128(d.addr, self.xmm[d.xmm_src]);
                self.writeMem128(d.addr + 16, self.ymm_hi[d.xmm_src]);
            },
            .vmovss_xmm_mem => {
                @memset(&self.xmm[d.xmm_dst], 0);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
                std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @truncate(self.readMemVal(d.addr, .bits32)), .little);
            },
            .vmovss_mem_xmm => {
                self.writeMemVal(d.addr, .bits32, std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little));
            },
            .vmovsd_xmm_mem => {
                @memset(&self.xmm[d.xmm_dst], 0);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], self.readMemVal(d.addr, .bits64), .little);
            },
            .vmovsd_mem_xmm => {
                self.writeMemVal(d.addr, .bits64, std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little));
            },
            .vmovlps_xmm_xmm_mem64, .vmovlpd_xmm_xmm_mem64 => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], self.readMemVal(d.addr, .bits64), .little);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .vmovlps_mem64_xmm, .vmovlpd_mem64_xmm => {
                self.writeMemVal(d.addr, .bits64, std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little));
            },
            .vmovhps_xmm_xmm_mem64, .vmovhpd_xmm_xmm_mem64 => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][8..16], self.readMemVal(d.addr, .bits64), .little);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .vmovhps_mem64_xmm, .vmovhpd_mem64_xmm => {
                self.writeMemVal(d.addr, .bits64, std.mem.readInt(u64, self.xmm[d.xmm_src][8..16], .little));
            },
            .vmovshdup, .vmovsldup, .vmovddup => {
                const source_low = if (d.is_reg_form) self.xmm[d.xmm_src] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = duplicateVectorElements(d.op, source_low);
                if (d.vector_256) {
                    const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = duplicateVectorElements(d.op, source_high);
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vzeroupper => {
                for (&self.ymm_hi) |*upper| @memset(upper, 0);
            },
            .vcvtsi2ss_xmm_reg, .vcvtsi2ss_xmm_mem => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                @memset(&self.ymm_hi[d.xmm_dst], 0);
                const integer: i64 = if (d.size == .bits64)
                    @bitCast(if (d.op == .vcvtsi2ss_xmm_reg) self.regVal(d.src_reg, .bits64) else self.readMemVal(d.addr, .bits64))
                else
                    @as(i32, @bitCast(@as(u32, @truncate(if (d.op == .vcvtsi2ss_xmm_reg) self.regVal(d.src_reg, .bits32) else self.readMemVal(d.addr, .bits32)))));
                const converted: f32 = @floatFromInt(integer);
                std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(converted), .little);
            },
            .vcvtsi2sd_xmm_reg, .vcvtsi2sd_xmm_mem => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                @memset(&self.ymm_hi[d.xmm_dst], 0);
                const integer: i64 = if (d.size == .bits64)
                    @bitCast(if (d.op == .vcvtsi2sd_xmm_reg) self.regVal(d.src_reg, .bits64) else self.readMemVal(d.addr, .bits64))
                else
                    @as(i32, @bitCast(@as(u32, @truncate(if (d.op == .vcvtsi2sd_xmm_reg) self.regVal(d.src_reg, .bits32) else self.readMemVal(d.addr, .bits32)))));
                const converted: f64 = @floatFromInt(integer);
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(converted), .little);
            },
            .vcvtss2sd => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                @memset(&self.ymm_hi[d.xmm_dst], 0);
                const source_bits = if (d.is_reg_form)
                    std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
                else
                    @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
                const converted: f64 = @floatCast(@as(f32, @bitCast(source_bits)));
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(converted), .little);
            },
            .vaddss, .vmulss, .vsubss, .vdivss => {
                self.executeVexScalarF32(d, vexArithmeticForOp(d.op));
            },
            .vaddsd, .vmulsd, .vsubsd, .vdivsd => {
                self.executeVexScalarF64(d, vexArithmeticForOp(d.op));
            },
            .vaddps, .vmulps, .vsubps, .vdivps => {
                self.executeVexPackedF32(d, vexArithmeticForOp(d.op));
            },
            .vaddpd, .vmulpd, .vsubpd, .vdivpd => {
                self.executeVexPackedF64(d, vexArithmeticForOp(d.op));
            },
            .vucomiss => {
                const lhs: f32 = @bitCast(std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little));
                const rhs_bits = if (d.is_reg_form)
                    std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
                else
                    @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
                self.setVexComparisonFlags(lhs, @as(f32, @bitCast(rhs_bits)));
            },
            .vucomisd => {
                const lhs: f64 = @bitCast(std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little));
                const rhs_bits = if (d.is_reg_form)
                    std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
                else
                    self.readMemVal(d.addr, .bits64);
                self.setVexComparisonFlags(lhs, @as(f64, @bitCast(rhs_bits)));
            },
            .vroundss => {
                const source1 = self.xmm[d.xmm_src];
                const source2_bits = if (d.is_reg_form)
                    std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
                else
                    @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
                self.xmm[d.xmm_dst] = source1;
                std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(roundVexFloat(f32, @bitCast(source2_bits), @truncate(d.imm))), .little);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .vroundsd => {
                const source1 = self.xmm[d.xmm_src];
                const source2_bits = if (d.is_reg_form)
                    std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
                else
                    self.readMemVal(d.addr, .bits64);
                self.xmm[d.xmm_dst] = source1;
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(roundVexFloat(f64, @bitCast(source2_bits), @truncate(d.imm))), .little);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .vroundps => {
                const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = roundVexPackedF32(source_low, @truncate(d.imm));
                if (d.vector_256) {
                    const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = roundVexPackedF32(source_high, @truncate(d.imm));
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vroundpd => {
                const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = roundVexPackedF64(source_low, @truncate(d.imm));
                if (d.vector_256) {
                    const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = roundVexPackedF64(source_high, @truncate(d.imm));
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vcvttss2si, .vcvtss2si => {
                const source_bits = if (d.is_reg_form)
                    std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little)
                else
                    @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
                const source: f32 = @bitCast(source_bits);
                self.setReg(d.dst_reg, d.size, convertVexFloatToSigned(f32, source, d.size, d.op == .vcvttss2si));
            },
            .vcvttsd2si, .vcvtsd2si => {
                const source_bits = if (d.is_reg_form)
                    std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little)
                else
                    self.readMemVal(d.addr, .bits64);
                const source: f64 = @bitCast(source_bits);
                self.setReg(d.dst_reg, d.size, convertVexFloatToSigned(f64, source, d.size, d.op == .vcvttsd2si));
            },
            .pmovmskb, .vpmovmskb => {
                var mask: u32 = 0;
                for (self.xmm[d.xmm_src], 0..) |byte, i| {
                    if (byte & 0x80 != 0) mask |= @as(u32, 1) << @intCast(i);
                }
                self.setReg(d.dst_reg, .bits32, mask);
            },
            .vpmovmskb_ymm => {
                var mask: u32 = 0;
                for (self.xmm[d.xmm_src], 0..) |byte, i| {
                    if (byte & 0x80 != 0) mask |= @as(u32, 1) << @intCast(i);
                }
                for (self.ymm_hi[d.xmm_src], 0..) |byte, i| {
                    if (byte & 0x80 != 0) mask |= @as(u32, 1) << @intCast(i + 16);
                }
                self.setReg(d.dst_reg, .bits32, mask);
            },
            .vandps, .vandpd, .vandnps, .vandnpd, .vorps, .vorpd, .vxorps, .vxorpd, .vpor, .vpand, .vpandn, .vpxor => {
                self.executeVexBitwise(d, vexBitwiseForOp(d.op));
            },
            .vpshufd => {
                const control: u8 = @truncate(d.imm);
                const source_low = if (d.is_reg_form) self.xmm[d.xmm_src] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = shufflePackedDwords(source_low, control);
                if (d.vector_256) {
                    const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = shufflePackedDwords(source_high, control);
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vpmuludq => {
                const source1_low = self.xmm[d.xmm_src];
                const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = multiplyUnsignedEvenDwords(source1_low, source2_low);
                if (d.vector_256) {
                    const source1_high = self.ymm_hi[d.xmm_src];
                    const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = multiplyUnsignedEvenDwords(source1_high, source2_high);
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vpblendw => {
                const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = blendPackedWords(self.xmm[d.xmm_src], rhs_low, @truncate(d.imm));
                if (d.vector_256) {
                    const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = blendPackedWords(self.ymm_hi[d.xmm_src], rhs_high, @truncate(d.imm));
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vpunpckhbw, .vpunpckhwd, .vpunpckhdq, .vpunpcklbw, .vpunpcklwd => {
                // VPUNPCK unpack operations - no-op for now
                // TODO: Implement actual unpack semantics
                if (d.is_reg_form) {
                    self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                } else {
                    self.xmm[d.xmm_dst] = self.readMem128(d.addr);
                }
                if (d.vector_256) {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vpslld, .vpsllq, .vpsllw, .vpslldq, .vpsrld, .vpsrlq, .vpsrlw, .vpsrldq => {
                const source_low = if (d.uses_imm and !d.is_reg_form) self.readMem128(d.addr) else self.xmm[d.xmm_src];
                const count = if (d.uses_imm)
                    d.imm
                else blk: {
                    const count_source = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                    break :blk std.mem.readInt(u64, count_source[0..8], .little);
                };
                const left = d.op == .vpsllw or d.op == .vpslld or d.op == .vpsllq or d.op == .vpslldq;
                if (d.op == .vpslldq or d.op == .vpsrldq) {
                    self.xmm[d.xmm_dst] = shiftPackedBytes(source_low, count, left);
                } else {
                    self.xmm[d.xmm_dst] = shiftPackedElements(source_low, packedShiftLaneBits(d.op), count, left);
                }
                if (d.vector_256) {
                    const source_high = if (d.uses_imm and !d.is_reg_form) self.readMem128(d.addr + 16) else self.ymm_hi[d.xmm_src];
                    if (d.op == .vpslldq or d.op == .vpsrldq) {
                        self.ymm_hi[d.xmm_dst] = shiftPackedBytes(source_high, count, left);
                    } else {
                        self.ymm_hi[d.xmm_dst] = shiftPackedElements(source_high, packedShiftLaneBits(d.op), count, left);
                    }
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vpsubb, .vpsubd, .vpsubq, .vpsubw, .vpaddb, .vpaddd, .vpaddq, .vpaddw, .vpmullw => {
                const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = packedIntegerBinary(
                    self.xmm[d.xmm_src],
                    rhs_low,
                    packedIntegerLaneBits(d.op),
                    packedIntegerOperation(d.op),
                );
                if (d.vector_256) {
                    const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = packedIntegerBinary(
                        self.ymm_hi[d.xmm_src],
                        rhs_high,
                        packedIntegerLaneBits(d.op),
                        packedIntegerOperation(d.op),
                    );
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },

            .syscall => {
                const boundary = x64_decoder.highway.systemBoundary(.macho64, .syscall, self.regs.rax, "");
                if (boundary.disposition != .forward) {
                    self.faulted = true;
                    self.terminated = true;
                    self.exit_code = 126;
                    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.system_policy_rejected);
                    return;
                }
                self.dispatchMacOSSyscall(
                    self.regs.rdi,
                    self.regs.rsi,
                    self.regs.rdx,
                    self.regs.r10,
                    self.regs.r8,
                    self.regs.r9,
                );
            },

            .ud2 => {
                if (self.tryRecoverClassifiedAssertionUd2(d.len)) return;
                const symbol = self.metadata.nearestSymbol(self.regs.rip);
                const assertion_age = self.executed_steps -| self.last_guest_assertion_step;
                std.debug.print(
                    "macho-processor: UD2 encounter: rip=0x{x} {s}+0x{x} active=0x{x} signal_depth={d} assertion={s} assertion_age={d} assertion_return=0x{x} bytes=0f0b\n",
                    .{ self.regs.rip, if (symbol) |entry| entry.name else "<unknown>", if (symbol) |entry| entry.offset else 0, self.active_guest_thread, self.signal_frame_count, @tagName(self.last_guest_assertion_class), assertion_age, self.last_guest_assertion_return },
                );
                if (self.deliverGuestSignal(GUEST_SIGILL, self.regs.rip, d.len)) return;
                std.debug.print("macho-processor: UD2 instruction at rip=0x{x} — unhandled guest SIGILL\n", .{self.regs.rip});
                self.faulted = true;
                self.terminated = true;
                self.exit_code = 128 + GUEST_SIGILL;
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unhandled_guest_signal);
                return;
            },

            .cpuid => {
                const leaf: u32 = @truncate(self.regs.rax);
                const subleaf: u32 = @truncate(self.regs.rcx);
                const result = x64_decoder.capabilities.cpuid(self.cpu_profile, leaf, subleaf);
                log.info(
                    "cpuid: leaf=0x{x} subleaf=0x{x} -> eax=0x{x} ebx=0x{x} ecx=0x{x} edx=0x{x}",
                    .{ leaf, subleaf, result.eax, result.ebx, result.ecx, result.edx },
                );
                self.setReg(.al_ax_eax_rax, .bits32, result.eax);
                self.setReg(.bl_bx_ebx_rbx, .bits32, result.ebx);
                self.setReg(.cl_cx_ecx_rcx, .bits32, result.ecx);
                self.setReg(.dl_dx_edx_rdx, .bits32, result.edx);
            },

            .xgetbv => {
                const xcr0 = if (@as(u32, @truncate(self.regs.rcx)) == 0)
                    x64_decoder.capabilities.xcr0(self.cpu_profile)
                else
                    0;
                log.info("xgetbv: xcr=0x{x} -> xcr0=0x{x} profile={s}", .{ self.regs.rcx, xcr0, self.cpu_profile.label() });
                self.setReg(.al_ax_eax_rax, .bits32, @truncate(xcr0));
                self.setReg(.dl_dx_edx_rdx, .bits32, @truncate(xcr0 >> 32));
            },

            .hlt => {
                const boundary = x64_decoder.highway.systemBoundary(.macho64, .process_exit, self.regs.rax, "HLT");
                if (boundary.disposition != .emulate) unreachable;
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.hlt);
                self.terminated = true;
                self.exit_code = self.regs.rax;
            },

            else => {
                log.warn("unimplemented instruction: {s} at rip=0x{x}", .{ @tagName(d.op), self.regs.rip });
                self.faulted = true;
                self.exit_code = 127;
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unimplemented_instruction);
                self.terminated = true;
            },
        }
    }

    fn executeFucomip(self: *MachOState, source: u3) void {
        const lhs = self.x87.get(0) orelse return;
        const rhs = self.x87.get(source) orelse return;
        self.regs.rflags &= ~(RFL_ZF | RFL_PF | RFL_CF);
        if (std.math.isNan(lhs) or std.math.isNan(rhs)) {
            self.regs.rflags |= RFL_ZF | RFL_PF | RFL_CF;
        } else if (lhs < rhs) {
            self.regs.rflags |= RFL_CF;
        } else if (lhs == rhs) {
            self.regs.rflags |= RFL_ZF;
        }
        _ = self.x87.pop();
    }

    fn executeBitScan(self: *MachOState, d: DecodedInsn) void {
        const is_memory = switch (d.op) {
            .bsf_reg_mem, .bsr_reg_mem, .tzcnt_reg_mem, .lzcnt_reg_mem => true,
            else => false,
        };
        const kind: BitScanKind = switch (d.op) {
            .bsf_reg_reg, .bsf_reg_mem => .bsf,
            .bsr_reg_reg, .bsr_reg_mem => .bsr,
            .tzcnt_reg_reg, .tzcnt_reg_mem => .tzcnt,
            .lzcnt_reg_reg, .lzcnt_reg_mem => .lzcnt,
            else => unreachable,
        };
        const source = if (is_memory) self.readMemVal(d.addr, d.size) else self.regVal(d.src_reg, d.size);
        const result = bitScan(d.size, kind, source);

        if (result.write_destination) self.setReg(d.dst_reg, d.size, result.value);
        self.setFlag(RFL_ZF, result.zero_flag);
        if (result.carry_flag) |carry| self.setFlag(RFL_CF, carry);
    }

    fn executeRotate(self: *MachOState, d: DecodedInsn) void {
        const is_mem = switch (d.op) {
            .rol_mem_cl, .ror_mem_cl, .rol_mem_imm, .ror_mem_imm => true,
            else => false,
        };
        const rotate_left = switch (d.op) {
            .rol_reg_cl, .rol_mem_cl, .rol_reg_imm, .rol_mem_imm => true,
            else => false,
        };
        const uses_cl = switch (d.op) {
            .rol_reg_cl, .rol_mem_cl, .ror_reg_cl, .ror_mem_cl => true,
            else => false,
        };
        const raw_count = if (uses_cl) self.regVal(.cl_cx_ecx_rcx, .bits8) else d.imm;
        const masked_count = raw_count & @as(u64, if (d.size == .bits64) 0x3F else 0x1F);
        const width: u64 = bitWidth(d.size);
        const count: u6 = @intCast(masked_count % width);
        if (count == 0) return;

        const mask = maskForSize(d.size);
        const old = (if (is_mem) self.readMemVal(d.addr, d.size) else self.regVal(d.dst_reg, d.size)) & mask;
        const inverse: u6 = @intCast(width - count);
        const result = if (rotate_left)
            ((old << count) | (old >> inverse)) & mask
        else
            ((old >> count) | (old << inverse)) & mask;

        if (is_mem) self.writeMemVal(d.addr, d.size, result) else self.setReg(d.dst_reg, d.size, result);
        if (rotate_left) {
            const carry = (result & 1) != 0;
            self.setFlag(RFL_CF, carry);
            if (count == 1) self.setFlag(RFL_OF, ((result & signBitForSize(d.size)) != 0) != carry);
        } else {
            const carry = (result & signBitForSize(d.size)) != 0;
            self.setFlag(RFL_CF, carry);
            if (count == 1) {
                const next_sign = (result & (signBitForSize(d.size) >> 1)) != 0;
                self.setFlag(RFL_OF, carry != next_sign);
            }
        }
    }

    fn executeVexScalarF32(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        const source1 = self.xmm[d.xmm_src];
        const source2_bits = if (d.is_reg_form)
            std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
        else
            @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
        const source1_value: f32 = @bitCast(std.mem.readInt(u32, source1[0..4], .little));
        const source2_value: f32 = @bitCast(source2_bits);

        self.xmm[d.xmm_dst] = source1;
        std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(applyVexArithmetic(f32, source1_value, source2_value, operation)), .little);
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }

    fn executeVexScalarF64(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        const source1 = self.xmm[d.xmm_src];
        const source2_bits = if (d.is_reg_form)
            std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
        else
            self.readMemVal(d.addr, .bits64);
        const source1_value: f64 = @bitCast(std.mem.readInt(u64, source1[0..8], .little));
        const source2_value: f64 = @bitCast(source2_bits);

        self.xmm[d.xmm_dst] = source1;
        std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(applyVexArithmetic(f64, source1_value, source2_value, operation)), .little);
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }

    fn executeVexPackedF32(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        const source1_low = self.xmm[d.xmm_src];
        const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
        self.xmm[d.xmm_dst] = applyVexPackedF32(source1_low, source2_low, operation);

        if (d.vector_256) {
            const source1_high = self.ymm_hi[d.xmm_src];
            const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
            self.ymm_hi[d.xmm_dst] = applyVexPackedF32(source1_high, source2_high, operation);
        } else {
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        }
    }

    fn executeVexPackedF64(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        const source1_low = self.xmm[d.xmm_src];
        const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
        self.xmm[d.xmm_dst] = applyVexPackedF64(source1_low, source2_low, operation);

        if (d.vector_256) {
            const source1_high = self.ymm_hi[d.xmm_src];
            const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
            self.ymm_hi[d.xmm_dst] = applyVexPackedF64(source1_high, source2_high, operation);
        } else {
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        }
    }

    fn setVexComparisonFlags(self: *MachOState, lhs: anytype, rhs: @TypeOf(lhs)) void {
        self.regs.rflags &= ~(RFL_OF | RFL_SF | RFL_ZF | RFL_AF | RFL_PF | RFL_CF);
        if (std.math.isNan(lhs) or std.math.isNan(rhs)) {
            self.regs.rflags |= RFL_ZF | RFL_PF | RFL_CF;
        } else if (lhs < rhs) {
            self.regs.rflags |= RFL_CF;
        } else if (lhs == rhs) {
            self.regs.rflags |= RFL_ZF;
        }
    }

    fn executeVexBitwise(self: *MachOState, d: DecodedInsn, operation: VexBitwise) void {
        const source1_low = self.xmm[d.xmm_src];
        const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
        self.xmm[d.xmm_dst] = applyVexBitwise(source1_low, source2_low, operation);

        if (d.vector_256) {
            const source1_high = self.ymm_hi[d.xmm_src];
            const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
            self.ymm_hi[d.xmm_dst] = applyVexBitwise(source1_high, source2_high, operation);
        } else {
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        }
    }

    fn executeAddRegImm(self: *MachOState, d: DecodedInsn, sz: Size) void {
        self.executeHighwayImmediate(d, .add, sz, false);
    }

    fn raiseDivideError(self: *MachOState) void {
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 136;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.divide_by_zero);
    }

    fn executeSubRegImm(self: *MachOState, d: DecodedInsn, sz: Size) void {
        self.executeHighwayImmediate(d, .sub, sz, false);
    }

    fn executeAndRegImm(self: *MachOState, d: DecodedInsn) void {
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

    fn dispatchMacOSSyscall(self: *MachOState, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64, arg6: u64) void {
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
                        std.debug.print(
                            "macho-processor: x64 backend sparse mmap FAILED: route=syscall address=0x0 length={d} prot=0x{x} flags=0x{x}\n",
                            .{ length, prot, raw_flags },
                        );
                        self.noteBackendMmapResult(false, 0, "syscall_backend_sparse_anywhere");
                        self.regs.rax = std.math.maxInt(u64);
                        return;
                    };
                    std.debug.print(
                        "macho-processor: x64 backend sparse mmap succeeded: route=syscall guest_base=0x{x} length={d} prot=0x{x} flags=0x{x} heap_bypassed=true\n",
                        .{ mapped, length, prot, raw_flags },
                    );
                    self.noteBackendMmapResult(true, mapped, "syscall_backend_sparse_anywhere");
                    self.regs.rax = mapped;
                    return;
                }

                if (length >= 1024 * 1024 * 1024) {
                    std.debug.print(
                        "macho-processor: large mmap entry: route=syscall addr=0x{x} length={d} aligned_length={d} prot=0x{x} flags=0x{x} fixed={} anonymous={} guest_fd=0x{x} offset={d}\n",
                        .{ addr, length, aligned_length, prot, raw_flags, map_flags.FIXED, map_flags.ANONYMOUS, arg5, offset },
                    );
                }

                if (addr == 0 and prot == 0 and length >= 1024 * 1024 * 1024) {
                    const host_fd: std.posix.fd_t = if (map_flags.ANONYMOUS)
                        -1
                    else
                        self.fs_forwarder.fd_manager.hostFd(arg5) orelse {
                            std.debug.print("macho-processor: large mmap FAILED: route=syscall stage=fd_translation guest_fd=0x{x}\n", .{arg5});
                            self.noteBackendMmapResult(false, 0, "syscall_large_fd_translation");
                            self.regs.rax = std.math.maxInt(u64);
                            return;
                        };
                    const reserved = self.guestReserveAddressSpaceWithBacking(aligned_length, raw_flags, host_fd, @bitCast(offset)) orelse {
                        std.debug.print("macho-processor: large mmap FAILED: route=syscall stage=sparse_reserve\n", .{});
                        self.noteBackendMmapResult(false, 0, "syscall_sparse_reserve");
                        self.regs.rax = std.math.maxInt(u64);
                        return;
                    };
                    std.debug.print("macho-processor: large mmap succeeded: route=syscall guest_base=0x{x} length={d}\n", .{ reserved, aligned_length });
                    self.noteBackendMmapResult(true, reserved, "syscall_sparse_reserve");
                    self.regs.rax = reserved;
                    return;
                }

                if (addr != 0 and map_flags.FIXED) {
                    const host_fd: std.posix.fd_t = if (map_flags.ANONYMOUS)
                        -1
                    else
                        self.fs_forwarder.fd_manager.hostFd(arg5) orelse {
                            std.debug.print("macho-processor: fixed mmap FAILED: route=syscall stage=fd_translation guest_fd=0x{x}\n", .{arg5});
                            self.noteBackendMmapResult(false, 0, "syscall_fixed_fd_translation");
                            self.regs.rax = std.math.maxInt(u64);
                            return;
                        };
                    if (!self.guestMapFile(addr, aligned_length, @truncate(prot), raw_flags, host_fd, @bitCast(offset))) {
                        std.debug.print("macho-processor: fixed mmap FAILED: route=syscall stage=sparse_map addr=0x{x} length={d}\n", .{ addr, aligned_length });
                        self.noteBackendMmapResult(false, 0, "syscall_fixed_sparse_map");
                        self.regs.rax = std.math.maxInt(u64);
                        return;
                    }
                    self.noteBackendMmapResult(true, addr, "syscall_fixed_sparse_map");
                    self.regs.rax = addr;
                    return;
                }

                const mapped = if (addr != 0) addr else self.guestAlloc(aligned_length, alignment) orelse {
                    std.debug.print("macho-processor: mmap FAILED: route=syscall stage=guest_heap length={d} alignment={d}\n", .{ aligned_length, alignment });
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
                    std.debug.print("macho-processor: sparse mprotect succeeded: route=syscall address=0x{x} length={d} prot=0x{x}\n", .{ address, length, prot });
                    self.noteBackendMprotect("syscall", address, length, prot, true);
                    self.regs.rax = 0;
                    return;
                }
                if (mappedOffset(self.mem_base, self.mem_size, self.mapped_min, address) == null) {
                    std.debug.print("macho-processor: mprotect FAILED: route=syscall reason=address_not_mapped address=0x{x} length={d} prot=0x{x}\n", .{ address, length, prot });
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
                    std.debug.print("macho-processor: sparse munmap succeeded: route=syscall address=0x{x} length={d}\n", .{ address, length });
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
const parseFopenFlags = utils.parseFopenFlags;
const guestSignalIndex = utils.guestSignalIndex;
const signalFailureResult = utils.signalFailureResult;
const signalHandlerMadeProgress = utils.signalHandlerMadeProgress;
const isAsciiBytes = utils.isAsciiBytes;
const profileIdFromUserDevice = utils.profileIdFromUserDevice;
const classifyProfileDismountCaller = utils.classifyProfileDismountCaller;
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
        std.debug.print("macho-processor: not a valid x86_64 Mach-O binary: {s}\n", .{@errorName(err)});
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

    std.debug.print("macho-processor: {s}\n", .{options.path});
    std.debug.print("ROSETTE: Loading MachO binary: '{s}'\n", .{options.path});
    if (std.mem.endsWith(u8, options.path, ".iso")) {
        std.debug.print("ROSETTE: WARNING: .iso file detected - this may indicate incorrect routing\n", .{});
    }
    const image_fingerprint = std.hash.Wyhash.hash(0, slice);
    const has_xbdm_diagnostics = std.mem.indexOf(
        u8,
        slice,
        "[XBDM export diagnostics] table initialized:",
    ) != null;
    std.debug.print(
        "macho-processor: image identity: bytes={d} wyhash64={x:0>16} xbdm_diagnostics={} bundle_executable={}\n",
        .{
            slice.len,
            image_fingerprint,
            has_xbdm_diagnostics,
            std.mem.indexOf(u8, options.path, ".app/Contents/MacOS/") != null,
        },
    );
    std.debug.print("  filetype: 0x{x}", .{temp_state.header.filetype});
    switch (temp_state.header.filetype) {
        2 => std.debug.print(" (MH_EXECUTE)\n", .{}),
        6 => std.debug.print(" (MH_DYLIB)\n", .{}),
        8 => std.debug.print(" (MH_BUNDLE)\n", .{}),
        else => std.debug.print("\n", .{}),
    }
    std.debug.print("  cputype:  0x{x}", .{temp_state.header.cputype});
    if (temp_state.header.cputype == macho.CPU_TYPE_X86_64) std.debug.print(" (x86_64)\n", .{}) else std.debug.print("\n", .{});
    std.debug.print("  ncmds:    {d}\n", .{temp_state.header.ncmds});
    std.debug.print("  segments: {d}\n", .{temp_state.segments.len});
    std.debug.print("  entry:    0x{x}\n", .{temp_state.entry_point});
    std.debug.print("  stack:    0x{x}\n", .{temp_state.stack_size});
    std.debug.print("  mem_base: 0x{x}\n", .{state.mem_base});
    std.debug.print("  entry_vaddr: 0x{x}\n", .{state.entry_point_vaddr});
    std.debug.print("  dylibs:    {d}\n", .{state.metadata.dylibs.len});
    std.debug.print("  imports:   {d}\n", .{state.metadata.imports.len});
    std.debug.print("  initializers: {d}\n", .{state.metadata.initializer_count});
    std.debug.print("  strict initializers: {}\n", .{state.strict_initializers});
    std.debug.print("  strict imports: {}\n", .{state.strict_imports});
    std.debug.print("  x64 cpu profile: {s}\n", .{state.cpu_profile.label()});
    std.debug.print(
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
    std.debug.print(
        "  decoder ISA verification: VEX baseline={d}/{d} ready={} AVX advertised={}\n",
        .{ vex_audit.passed, vex_audit.total, vex_audit.ready(), avx_advertised },
    );
    if (avx_advertised and !vex_audit.ready()) {
        std.debug.print(
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
        std.debug.print("  entry_symbol: {s}+0x{x}\n", .{ entry_symbol.name, entry_symbol.offset });
    }

    for (temp_state.segments, 0..) |seg, i| {
        const prot_str = switch (seg.initprot) {
            7 => "rwx",
            5 => "r-x",
            3 => "rw-",
            1 => "r--",
            else => "???",
        };
        std.debug.print("    [{d}] {s: <12}  vm=0x{x:0>8}  size=0x{x:0>8}  file=0x{x:0>8}  ({s})\n", .{
            i, seg.name, seg.vmaddr, seg.vmsize, seg.fileoff, prot_str,
        });
    }

    if (temp_state.entry_point == 0) {
        std.debug.print("macho-processor: no entry point found\n", .{});
        return 1;
    }

    state.guest_fds[0] = 0;
    state.guest_fds[1] = 1;
    state.guest_fds[2] = 2;

    std.debug.print("ROSETTE: About to setup MachO state for path: '{s}'\n", .{options.path});
    std.debug.print("ROSETTE: This confirms Rosetta is routing Xenia through compatibility layer\n", .{});
    output.human("Initializing pthread runtime...\n", .{});
    state.setupMachOState(options.path, options.args);
    state.launch_options.logConfiguration(state.internal_targets.cvar_add_to_launch_options_count);
    std.debug.print("ROSETTE: MachO state setup completed successfully\n", .{});

    state.startup.enter(.static_init, state.executed_steps);
    output.human("Initializing guest runtime...\n", .{});
    std.debug.print("macho-processor: running {d} pre-main initializer(s)\n", .{state.metadata.initializer_addresses.len});
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
        std.debug.print("macho-processor: initializer phase failed: exit_code={d}\n", .{state.exit_code});
        return state.exit_code;
    }

    state.startup.enter(.main_enter, state.executed_steps);
    output.human("Loading guest program...\n", .{});
    std.debug.print("macho-processor: starting execution at 0x{x}, rsp=0x{x}\n", .{ state.regs.rip, state.regs.rsp });

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

    std.debug.print("macho-processor: execution finished: exit_code={d}, faulted={}, terminated={}\n", .{ state.exit_code, state.faulted, state.terminated });
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
        std.debug.print(
            "macho-processor: synchronous guest log bridge: mirrored_lines={d}\n",
            .{state.guest_log_line_count},
        );
    }
    if (state.guest_stdio_write_count != 0) {
        std.debug.print(
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
        std.debug.print(
            "macho-processor: guest stdio input: reads={d} bytes={d} seeks={d} failures={d}\n",
            .{ state.guest_stdio_read_count, state.guest_stdio_read_bytes, state.guest_stdio_seek_count, state.guest_stdio_failures },
        );
    }

    if (state.unresolved_import_count != 0) {
        const end = if (state.import_trace_filled) IMPORT_TRACE_BUFFER_LEN else state.import_trace_index;
        for (0..end) |i| {
            const entry = state.import_trace_entries[i];
            if (entry.caller_symbol.len != 0) {
                std.debug.print(
                    "macho-processor: unresolved import #{d}: {s} from {s}; stub=0x{x} return=0x{x} caller={s}+0x{x} synthesized_rax=0x{x}\n",
                    .{ i, entry.symbol, entry.dylib, entry.stub_address, entry.return_address, entry.caller_symbol, entry.caller_offset, entry.synthetic_result },
                );
            } else {
                std.debug.print(
                    "macho-processor: unresolved import #{d}: {s} from {s}; stub=0x{x} return=0x{x} synthesized_rax=0x{x}\n",
                    .{ i, entry.symbol, entry.dylib, entry.stub_address, entry.return_address, entry.synthetic_result },
                );
            }
        }
    }

    if (state.unresolved_import_count != 0 and !state.faulted) {
        std.debug.print(
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
            std.debug.print("macho-processor: no x86_64 slice found in fat binary\n", .{});
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
    var result = [_]u8{0} ** 16;
    for (0..2) |lane| {
        const source_offset = lane * 8;
        const destination_offset = lane * 8;
        const left = std.mem.readInt(u32, lhs[source_offset..][0..4], .little);
        const right = std.mem.readInt(u32, rhs[source_offset..][0..4], .little);
        std.mem.writeInt(u64, result[destination_offset..][0..8], @as(u64, left) * @as(u64, right), .little);
    }
    return result;
}

fn shufflePackedDwords(source: [16]u8, control: u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |destination_lane| {
        const shift: u3 = @intCast(destination_lane * 2);
        const source_lane = (control >> shift) & 0x03;
        const destination_offset = destination_lane * 4;
        const source_offset = @as(usize, source_lane) * 4;
        @memcpy(result[destination_offset..][0..4], source[source_offset..][0..4]);
    }
    return result;
}

fn unpackLowQwords(lhs: [16]u8, rhs: [16]u8) [16]u8 {
    var result: [16]u8 = undefined;
    @memcpy(result[0..8], lhs[0..8]);
    @memcpy(result[8..16], rhs[0..8]);
    return result;
}

fn blendPackedWords(lhs: [16]u8, rhs: [16]u8, control: u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..8) |lane| {
        const offset = lane * 2;
        const source = if (control & (@as(u8, 1) << @intCast(lane)) != 0) rhs else lhs;
        @memcpy(result[offset..][0..2], source[offset..][0..2]);
    }
    return result;
}

const PackedIntegerOperation = enum { add, sub, mul_low };

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
    var result: [16]u8 = undefined;
    switch (lane_bits) {
        8 => for (0..16) |lane| {
            result[lane] = switch (operation) {
                .add => lhs[lane] +% rhs[lane],
                .sub => lhs[lane] -% rhs[lane],
                .mul_low => lhs[lane] *% rhs[lane],
            };
        },
        16 => for (0..8) |lane| {
            const offset = lane * 2;
            const left = std.mem.readInt(u16, lhs[offset..][0..2], .little);
            const right = std.mem.readInt(u16, rhs[offset..][0..2], .little);
            const value = switch (operation) {
                .add => left +% right,
                .sub => left -% right,
                .mul_low => left *% right,
            };
            std.mem.writeInt(u16, result[offset..][0..2], value, .little);
        },
        32 => for (0..4) |lane| {
            const offset = lane * 4;
            const left = std.mem.readInt(u32, lhs[offset..][0..4], .little);
            const right = std.mem.readInt(u32, rhs[offset..][0..4], .little);
            const value = switch (operation) {
                .add => left +% right,
                .sub => left -% right,
                .mul_low => left *% right,
            };
            std.mem.writeInt(u32, result[offset..][0..4], value, .little);
        },
        64 => for (0..2) |lane| {
            const offset = lane * 8;
            const left = std.mem.readInt(u64, lhs[offset..][0..8], .little);
            const right = std.mem.readInt(u64, rhs[offset..][0..8], .little);
            const value = switch (operation) {
                .add => left +% right,
                .sub => left -% right,
                .mul_low => left *% right,
            };
            std.mem.writeInt(u64, result[offset..][0..8], value, .little);
        },
        else => unreachable,
    }
    return result;
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
    var result = [_]u8{0} ** 16;
    if (count >= lane_bits) return result;
    switch (lane_bits) {
        16 => for (0..8) |lane| {
            const offset = lane * 2;
            const value = std.mem.readInt(u16, source[offset..][0..2], .little);
            std.mem.writeInt(u16, result[offset..][0..2], if (left) value << @intCast(count) else value >> @intCast(count), .little);
        },
        32 => for (0..4) |lane| {
            const offset = lane * 4;
            const value = std.mem.readInt(u32, source[offset..][0..4], .little);
            std.mem.writeInt(u32, result[offset..][0..4], if (left) value << @intCast(count) else value >> @intCast(count), .little);
        },
        64 => for (0..2) |lane| {
            const offset = lane * 8;
            const value = std.mem.readInt(u64, source[offset..][0..8], .little);
            std.mem.writeInt(u64, result[offset..][0..8], if (left) value << @intCast(count) else value >> @intCast(count), .little);
        },
        else => unreachable,
    }
    return result;
}

fn shiftPackedBytes(source: [16]u8, count: u64, left: bool) [16]u8 {
    var result = [_]u8{0} ** 16;
    if (count >= 16) return result;
    const amount: usize = @intCast(count);
    if (left) {
        @memcpy(result[amount..], source[0 .. 16 - amount]);
    } else {
        @memcpy(result[0 .. 16 - amount], source[amount..]);
    }
    return result;
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

test "decode x87 integer load and extended store used by chrono timeout path" {
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
        std.debug.print(
            "scheduler: runtime integration active version=ui-handoff-v2 optimize={s} executable={s}\n",
            .{ @tagName(builtin.mode), if (executable_path) |path| path else "<unavailable>" },
        );
    }

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    if (args.len < 2) {
        std.debug.print("usage: macho_processor <binary> [args...]\n", .{});
        std.process.exit(1);
    }

    const exit_code = try loadAndRun(init.io, allocator, .{
        .path = args[1],
        .args = args[2..],
    });
    const process_status: u8 = if (exit_code <= std.math.maxInt(u8)) @intCast(exit_code) else UNSUPPORTED_RUNTIME_EXIT_CODE;
    if (process_status != exit_code) {
        std.debug.print("macho-processor: normalized non-status exit value 0x{x} to {d}\n", .{ exit_code, process_status });
    }
    std.process.exit(process_status);
}
