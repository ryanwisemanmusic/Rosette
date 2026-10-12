const process = @import("../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const AUDIO_STAGE_COUNT = process.AUDIO_STAGE_COUNT;
const BLOCK_JIT_DEFAULT_HOT_THRESHOLD = __ProcessInternals._BLOCK_JIT_DEFAULT_HOT_THRESHOLD;
const BLOCK_JIT_HOOK_FILTER_BYTES = __ProcessInternals._BLOCK_JIT_HOOK_FILTER_BYTES;
const BlockHotness = __ProcessInternals._BlockHotness;
const BlockJitCallRefusal = __ProcessInternals._BlockJitCallRefusal;
const BlockJitState = __ProcessInternals._BlockJitState;
const ChainStage = process.ChainStage;
const Cond = process.Cond;
const DECODE_CACHE_MISS_SITE_CAPACITY = __ProcessInternals._DECODE_CACHE_MISS_SITE_CAPACITY;
const DecodeCacheCounters = __ProcessInternals._DecodeCacheCounters;
const DecodeCacheEntry = __ProcessInternals._DecodeCacheEntry;
const DecodeCacheMissCause = __ProcessInternals._DecodeCacheMissCause;
const DecodeCacheMissSite = __ProcessInternals._DecodeCacheMissSite;
const DecodeCacheShard = __ProcessInternals._DecodeCacheShard;
const DecodedInsn = process.DecodedInsn;
const DynamicRelocation = process.DynamicRelocation;
const ElfRegs = process.ElfRegs;
const ElfTraceEntry = __ProcessInternals._ElfTraceEntry;
const FIRST_FRAME_STAGE_COUNT = process.FIRST_FRAME_STAGE_COUNT;
const FrameHostSampleCategory = __ProcessInternals._FrameHostSampleCategory;
const GPU_DRAW_FAILURE_CAPACITY = __ProcessInternals._GPU_DRAW_FAILURE_CAPACITY;
const GPU_INDIRECT_BUFFER_CAPACITY = __ProcessInternals._GPU_INDIRECT_BUFFER_CAPACITY;
const GPU_REGISTER_TRAFFIC_CAPACITY = __ProcessInternals._GPU_REGISTER_TRAFFIC_CAPACITY;
const GPU_RING_WINDOW_CAPACITY = __ProcessInternals._GPU_RING_WINDOW_CAPACITY;
const GUEST_ACCESS_VIOLATION_SITE_CAPACITY = __ProcessInternals._GUEST_ACCESS_VIOLATION_SITE_CAPACITY;
const GUEST_MILESTONE_CALLER_SLOTS = __ProcessInternals._GUEST_MILESTONE_CALLER_SLOTS;
const GUEST_MILESTONE_COUNT = process.GUEST_MILESTONE_COUNT;
const GUEST_MILESTONE_SLOTS = __ProcessInternals._GUEST_MILESTONE_SLOTS;
const GUEST_MILESTONE_TRANSLATOR_SATURATION = __ProcessInternals._GUEST_MILESTONE_TRANSLATOR_SATURATION;
const GUEST_MODULE_LOOKUP_CAPACITY = __ProcessInternals._GUEST_MODULE_LOOKUP_CAPACITY;
const GUEST_OUTPUT_STAGE_COUNT = process.GUEST_OUTPUT_STAGE_COUNT;
const GUEST_VFS_RESOLVE_CAPACITY = __ProcessInternals._GUEST_VFS_RESOLVE_CAPACITY;
const GpuDrawFailure = __ProcessInternals._GpuDrawFailure;
const GpuDrawTuple = __ProcessInternals._GpuDrawTuple;
const GpuRegisterTraffic = __ProcessInternals._GpuRegisterTraffic;
const GpuRingWindow = __ProcessInternals._GpuRingWindow;
const GuestAccessViolation = __ProcessInternals._GuestAccessViolation;
const GuestAccessViolationSite = __ProcessInternals._GuestAccessViolationSite;
const GuestContextRef = __ProcessInternals._GuestContextRef;
const GuestExecutionGate = __ProcessInternals._GuestExecutionGate;
const GuestFileNameShape = __ProcessInternals._GuestFileNameShape;
const GuestFileRequest = __ProcessInternals._GuestFileRequest;
const GuestFrameCost = __ProcessInternals._GuestFrameCost;
const GuestFrontBuffer = __ProcessInternals._GuestFrontBuffer;
const GuestMilestoneActivity = __ProcessInternals._GuestMilestoneActivity;
const GuestModuleLookup = __ProcessInternals._GuestModuleLookup;
const GuestReturnCapture = __ProcessInternals._GuestReturnCapture;
const GuestReturnCaptureKind = __ProcessInternals._GuestReturnCaptureKind;
const GuestSymbol = process.GuestSymbol;
const GuestSymbolResolver = process.GuestSymbolResolver;
const GuestVfsResolve = __ProcessInternals._GuestVfsResolve;
const GuestVfsResolveSummary = __ProcessInternals._GuestVfsResolveSummary;
const GuestXmaRegisterCensus = __ProcessInternals._GuestXmaRegisterCensus;
const HookBox = __ProcessInternals._HookBox;
const HookPoints = __ProcessInternals._HookPoints;
const HostMutex = __ProcessInternals._HostMutex;
const INITIAL_WINDOWS_HEAP_ALLOCATIONS = __ProcessInternals._INITIAL_WINDOWS_HEAP_ALLOCATIONS;
const MAX_WINDOWS_ALLOCATION_REFUSALS = process.MAX_WINDOWS_ALLOCATION_REFUSALS;
const MAX_WINDOWS_ALLOCATION_RELOCATIONS = process.MAX_WINDOWS_ALLOCATION_RELOCATIONS;
const MAX_WINDOWS_ALLOCATION_RELOCATION_OVERFLOW_SAMPLES = process.MAX_WINDOWS_ALLOCATION_RELOCATION_OVERFLOW_SAMPLES;
const MAX_WINDOWS_AUDIO_CALLBACK_FRAMES = __ProcessInternals._MAX_WINDOWS_AUDIO_CALLBACK_FRAMES;
const MAX_WINDOWS_CRITICAL_SECTIONS = __ProcessInternals._MAX_WINDOWS_CRITICAL_SECTIONS;
const MAX_WINDOWS_DYNAMIC_REFUSALS = process.MAX_WINDOWS_DYNAMIC_REFUSALS;
const MAX_WINDOWS_EXECUTABLE_RANGES = __ProcessInternals._MAX_WINDOWS_EXECUTABLE_RANGES;
const MAX_WINDOWS_FILE_HANDLES = __ProcessInternals._MAX_WINDOWS_FILE_HANDLES;
const MAX_WINDOWS_FILE_MAPPINGS = __ProcessInternals._MAX_WINDOWS_FILE_MAPPINGS;
const MAX_WINDOWS_FIND_HANDLES = __ProcessInternals._MAX_WINDOWS_FIND_HANDLES;
const MAX_WINDOWS_GUEST_THREADS = __ProcessInternals._MAX_WINDOWS_GUEST_THREADS;
const MAX_WINDOWS_IMPORT_STUBS = __ProcessInternals._MAX_WINDOWS_IMPORT_STUBS;
const MAX_WINDOWS_INITTERM_FRAMES = __ProcessInternals._MAX_WINDOWS_INITTERM_FRAMES;
const MAX_WINDOWS_LOADED_MODULES = process.MAX_WINDOWS_LOADED_MODULES;
const MAX_WINDOWS_MEMORY_VIEWS = __ProcessInternals._MAX_WINDOWS_MEMORY_VIEWS;
const MAX_WINDOWS_MESSAGE_DISPATCH_FRAMES = __ProcessInternals._MAX_WINDOWS_MESSAGE_DISPATCH_FRAMES;
const MAX_WINDOWS_QSORT_FRAMES = __ProcessInternals._MAX_WINDOWS_QSORT_FRAMES;
const MAX_WINDOWS_SRW_LOCKS = __ProcessInternals._MAX_WINDOWS_SRW_LOCKS;
const MAX_WINDOWS_UNBACKED_COMMITS = process.MAX_WINDOWS_UNBACKED_COMMITS;
const MAX_WINDOWS_VIRTUAL_ALLOCATIONS = __ProcessInternals._MAX_WINDOWS_VIRTUAL_ALLOCATIONS;
const MAX_WINDOWS_VOLUME_HANDLES = __ProcessInternals._MAX_WINDOWS_VOLUME_HANDLES;
const MAX_WINDOWS_WAIT_OBJECTS = __ProcessInternals._MAX_WINDOWS_WAIT_OBJECTS;
const MAX_WINDOWS_WAVE_OUT_DEVICES = __ProcessInternals._MAX_WINDOWS_WAVE_OUT_DEVICES;
const MAX_WINDOWS_WINDOWS = __ProcessInternals._MAX_WINDOWS_WINDOWS;
const MAX_WINDOWS_WINDOW_CLASSES = __ProcessInternals._MAX_WINDOWS_WINDOW_CLASSES;
const MEM_BASE = __ProcessInternals._MEM_BASE;
const MEM_SIZE = __ProcessInternals._MEM_SIZE;
const NativeConditionLock = __ProcessInternals._NativeConditionLock;
const NativeMemoryAlias = __ProcessInternals._NativeMemoryAlias;
const Op = process.Op;
const PARALLEL_WORKER_STEP_BATCH = __ProcessInternals._PARALLEL_WORKER_STEP_BATCH;
const PE_DECODE_CACHE_ENTRIES = __ProcessInternals._PE_DECODE_CACHE_ENTRIES;
const PE_DECODE_CACHE_VICTIM_ENTRIES = __ProcessInternals._PE_DECODE_CACHE_VICTIM_ENTRIES;
const PE_DECODE_CACHE_WAYS = __ProcessInternals._PE_DECODE_CACHE_WAYS;
const PE_MAX_INSTRUCTION_LENGTH = __ProcessInternals._PE_MAX_INSTRUCTION_LENGTH;
const ParallelFaultSnapshot = __ProcessInternals._ParallelFaultSnapshot;
const RegId = process.RegId;
const STACK_SIZE = __ProcessInternals._STACK_SIZE;
const Size = process.Size;
const TRACE_BUFFER_LEN = __ProcessInternals._TRACE_BUFFER_LEN;
const TimeAuditSample = __ProcessInternals._TimeAuditSample;
const WINDOWS_ALLOCATION_DISPOSITION_COUNT = __ProcessInternals._WINDOWS_ALLOCATION_DISPOSITION_COUNT;
const WINDOWS_FATAL_POINT_ALLOW_BYTES = __ProcessInternals._WINDOWS_FATAL_POINT_ALLOW_BYTES;
const WINDOWS_FILE_READ_PROVENANCE_CAPACITY = process.WINDOWS_FILE_READ_PROVENANCE_CAPACITY;
const WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE = __ProcessInternals._WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE;
const WINDOWS_GUEST_FAILURE_POINT_CAPACITY = __ProcessInternals._WINDOWS_GUEST_FAILURE_POINT_CAPACITY;
const WINDOWS_GUEST_OUTPUT_LINE_CAPACITY = __ProcessInternals._WINDOWS_GUEST_OUTPUT_LINE_CAPACITY;
const WINDOWS_GUEST_SPIN_MAX_BACKOFF = __ProcessInternals._WINDOWS_GUEST_SPIN_MAX_BACKOFF;
const WINDOWS_GUEST_WARNING_POINT_CAPACITY = __ProcessInternals._WINDOWS_GUEST_WARNING_POINT_CAPACITY;
const WINDOWS_HEAP_QUARANTINE_BLOCKS = __ProcessInternals._WINDOWS_HEAP_QUARANTINE_BLOCKS;
const WINDOWS_HEAP_QUARANTINE_BYTES = __ProcessInternals._WINDOWS_HEAP_QUARANTINE_BYTES;
const WINDOWS_RUN_HEARTBEAT_INSTRUCTIONS = __ProcessInternals._WINDOWS_RUN_HEARTBEAT_INSTRUCTIONS;
const WINDOWS_TIMED_WAIT_SITE_CAPACITY = __ProcessInternals._WINDOWS_TIMED_WAIT_SITE_CAPACITY;
const WINDOWS_TLS_BLOCK_BYTES = __ProcessInternals._WINDOWS_TLS_BLOCK_BYTES;
const WINDOWS_UNRESOLVED_IMPORT_CAPACITY = process.WINDOWS_UNRESOLVED_IMPORT_CAPACITY;
const WORKLOAD_COUNT = __ProcessInternals._WORKLOAD_COUNT;
const WindowsAllocationDisposition = process.WindowsAllocationDisposition;
const WindowsAllocationRefusal = process.WindowsAllocationRefusal;
const WindowsAllocationRelocation = process.WindowsAllocationRelocation;
const WindowsApcQueue = __ProcessInternals._WindowsApcQueue;
const WindowsAudioCallbackFrame = __ProcessInternals._WindowsAudioCallbackFrame;
const WindowsAudioHooks = process.WindowsAudioHooks;
const WindowsCrtProcessGlobals = __ProcessInternals._WindowsCrtProcessGlobals;
const WindowsDynamicRefusal = process.WindowsDynamicRefusal;
const WindowsExecutableRange = process.WindowsExecutableRange;
const WindowsFileFailureLedger = __ProcessInternals._WindowsFileFailureLedger;
const WindowsFileMapping = process.WindowsFileMapping;
const WindowsFileReadProvenance = process.WindowsFileReadProvenance;
const WindowsFileSlot = process.WindowsFileSlot;
const WindowsFindSlot = process.WindowsFindSlot;
const WindowsGraphicsState = process.WindowsGraphicsState;
const WindowsGuestFailurePoint = __ProcessInternals._WindowsGuestFailurePoint;
const WindowsGuestSchedulerPolicy = __ProcessInternals._WindowsGuestSchedulerPolicy;
const WindowsGuestThread = __ProcessInternals._WindowsGuestThread;
const WindowsGuestThreadContext = __ProcessInternals._WindowsGuestThreadContext;
const WindowsGuestThreadEnvironment = __ProcessInternals._WindowsGuestThreadEnvironment;
const WindowsGuestThreadStatus = __ProcessInternals._WindowsGuestThreadStatus;
const WindowsGuestWarningPoint = __ProcessInternals._WindowsGuestWarningPoint;
const WindowsHeapAllocation = process.WindowsHeapAllocation;
const WindowsHeapBin = __ProcessInternals._WindowsHeapBin;
const WindowsHeapCallSite = __ProcessInternals._WindowsHeapCallSite;
const WindowsHeapCodeSnapshot = __ProcessInternals._WindowsHeapCodeSnapshot;
const WindowsHeapStackSnapshot = __ProcessInternals._WindowsHeapStackSnapshot;
const WindowsImportCallsite = __ProcessInternals._WindowsImportCallsite;
const WindowsImportStub = process.WindowsImportStub;
const WindowsImportStubInterior = __ProcessInternals._WindowsImportStubInterior;
const WindowsInitTermFrame = __ProcessInternals._WindowsInitTermFrame;
const WindowsInputHooks = process.WindowsInputHooks;
const WindowsInputState = process.WindowsInputState;
const WindowsLoadedModule = process.WindowsLoadedModule;
const WindowsMappedCodeSlice = __ProcessInternals._WindowsMappedCodeSlice;
const WindowsMemoryView = process.WindowsMemoryView;
const WindowsMessage = process.WindowsMessage;
const WindowsMessageDispatchFrame = __ProcessInternals._WindowsMessageDispatchFrame;
const WindowsMultiWaitResult = __ProcessInternals._WindowsMultiWaitResult;
const WindowsProgressSample = __ProcessInternals._WindowsProgressSample;
const WindowsProgressWatchdog = __ProcessInternals._WindowsProgressWatchdog;
const WindowsQsortFrame = __ProcessInternals._WindowsQsortFrame;
const WindowsRuntimeLockGuard = __ProcessInternals._WindowsRuntimeLockGuard;
const WindowsSrwLock = __ProcessInternals._WindowsSrwLock;
const WindowsSrwLockIndex = __ProcessInternals._WindowsSrwLockIndex;
const WindowsTimedWaitSite = __ProcessInternals._WindowsTimedWaitSite;
const WindowsUnbackedCommit = process.WindowsUnbackedCommit;
const WindowsUnresolvedImport = process.WindowsUnresolvedImport;
const WindowsVirtualAllocation = process.WindowsVirtualAllocation;
const WindowsVolumeFindSlot = __ProcessInternals._WindowsVolumeFindSlot;
const WindowsWaitObject = __ProcessInternals._WindowsWaitObject;
const WindowsWaveOutDevice = __ProcessInternals._WindowsWaveOutDevice;
const WindowsWindow = __ProcessInternals._WindowsWindow;
const WindowsWindowClass = __ProcessInternals._WindowsWindowClass;
const WorkerLocalDecodeCache = __ProcessInternals._WorkerLocalDecodeCache;
const X87Raw = __ProcessInternals._X87Raw;
const XeniaGlobalLend = __ProcessInternals._XeniaGlobalLend;
const XeniaSetupTrace = __ProcessInternals._XeniaSetupTrace;
const blockJitRead = __ProcessInternals._blockJitRead;
const blockJitWrite = __ProcessInternals._blockJitWrite;
const block_jit = __ProcessInternals._block_jit;
const block_verify = __ProcessInternals._block_verify;
const call_probe = __ProcessInternals._call_probe;
const cleo_routing = __ProcessInternals._cleo_routing;
const concurrency = __ProcessInternals._concurrency;
const context_integrity = __ProcessInternals._context_integrity;
const decode_cache_miss_mutex = __ProcessInternals._decode_cache_miss_mutex;
const decode_cache_set_lock_count = __ProcessInternals._decode_cache_set_lock_count;
const elf_loader = __ProcessInternals._elf_loader;
const evex = __ProcessInternals._evex;
const execution_history = __ProcessInternals._execution_history;
const exit_context = __ProcessInternals._exit_context;
const exit_diagnostics = __ProcessInternals._exit_diagnostics;
const frame_attribution = __ProcessInternals._frame_attribution;
const gpu_stall = __ProcessInternals._gpu_stall;
const guest_address_space = __ProcessInternals._guest_address_space;
const guest_backtrace = __ProcessInternals._guest_backtrace;
const guest_clock = __ProcessInternals._guest_clock;
const guest_output_governor = __ProcessInternals._guest_output_governor;
const guest_page_protection = __ProcessInternals._guest_page_protection;
const guest_spin = __ProcessInternals._guest_spin;
const heap_guard = __ProcessInternals._heap_guard;
const host_profile = __ProcessInternals._host_profile;
const import_histogram = __ProcessInternals._import_histogram;
const kernel_call_census = __ProcessInternals._kernel_call_census;
const kuser_shared = __ProcessInternals._kuser_shared;
const log = __ProcessInternals._log;
const mapped_ranges = __ProcessInternals._mapped_ranges;
const milestone_slot_collision = __ProcessInternals._milestone_slot_collision;
const native_alias_address_base = __ProcessInternals._native_alias_address_base;
const parallel_diagnostics = __ProcessInternals._parallel_diagnostics;
const parallel_workers = __ProcessInternals._parallel_workers;
const process_impl_block_jit = __ProcessInternals._process_impl_block_jit;
const process_impl_execution = __ProcessInternals._process_impl_execution;
const process_impl_guest_diagnostics = __ProcessInternals._process_impl_guest_diagnostics;
const process_impl_guest_heap = __ProcessInternals._process_impl_guest_heap;
const process_impl_guest_memory = __ProcessInternals._process_impl_guest_memory;
const process_impl_instruction_decode = __ProcessInternals._process_impl_instruction_decode;
const process_impl_kernel_services = __ProcessInternals._process_impl_kernel_services;
const process_impl_lifecycle = __ProcessInternals._process_impl_lifecycle;
const process_impl_run_reporting = __ProcessInternals._process_impl_run_reporting;
const process_impl_syscalls = __ProcessInternals._process_impl_syscalls;
const process_impl_windows_audio = __ProcessInternals._process_impl_windows_audio;
const process_impl_windows_sync = __ProcessInternals._process_impl_windows_sync;
const process_impl_windows_ui = __ProcessInternals._process_impl_windows_ui;
const screen_validity = __ProcessInternals._screen_validity;
const std = __ProcessInternals._std;
const terminal_event = __ProcessInternals._terminal_event;
const tlb_diagnostics = __ProcessInternals._tlb_diagnostics;
const tso_memory = __ProcessInternals._tso_memory;
const tso_memory_policy = __ProcessInternals._tso_memory_policy;
const ui_draw_evidence = __ProcessInternals._ui_draw_evidence;
const unmapped_reads = __ProcessInternals._unmapped_reads;
const vector_helpers = __ProcessInternals._vector_helpers;
const wait_cost = __ProcessInternals._wait_cost;
const windows_guest_abi = __ProcessInternals._windows_guest_abi;
const windows_message_queue = __ProcessInternals._windows_message_queue;
const windows_registry_model = __ProcessInternals._windows_registry_model;
const windows_srw_owner_stack_depth = __ProcessInternals._windows_srw_owner_stack_depth;
const windows_ui_ledger = __ProcessInternals._windows_ui_ledger;
const x64_decoder = __ProcessInternals._x64_decoder;
const x64_guest_abi = __ProcessInternals._x64_guest_abi;
const x64_linux_runtime = __ProcessInternals._x64_linux_runtime;
const xbox_critical_section = __ProcessInternals._xbox_critical_section;
const xenia_clock_probe = __ProcessInternals._xenia_clock_probe;
const xenia_event_audit = __ProcessInternals._xenia_event_audit;
const xenia_fatal_condition_map = __ProcessInternals._xenia_fatal_condition_map;
const xenia_guest_frontier_map = __ProcessInternals._xenia_guest_frontier_map;
const xenia_guest_milestone_map = __ProcessInternals._xenia_guest_milestone_map;
const xenia_warning_severity_map = __ProcessInternals._xenia_warning_severity_map;
const envEquals = __ProcessInternals._envEquals;
const envFlag = __ProcessInternals._envFlag;
const envPresentAndFalse = __ProcessInternals._envPresentAndFalse;
const envText = __ProcessInternals._envText;
const envU64 = __ProcessInternals._envU64;

pub const ElfState = struct {
    allocator: std.mem.Allocator,
    mem: []u8,
    mem_base: u64,
    mem_size: u64,
    image_low: u64 = 0,
    image_high: u64 = 0,
    regs: ElfRegs = .{},
    // Full EVEX register addressing reaches zmm16-zmm31. Keep the extended
    // vector state even though the legacy VEX executor only uses the lower
    // sixteen registers.
    xmm: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    ymm_hi: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    zmm_hi: [32][32]u8 = [_][32]u8{[_]u8{0} ** 32} ** 32,
    // AVX-512 opmask registers (k0-k7). k0 is always all-1s when read as
    // a mask operand; k1-k7 hold actual mask values for predicated operations.
    k: [8]u64 = [_]u64{0xFFFF_FFFF_FFFF_FFFF} ** 8,
    x87_stack: [8]X87Raw = [_]X87Raw{[_]u8{0} ** 10} ** 8,
    x87_tags: [8]bool = [_]bool{false} ** 8,
    x87_top: u3 = 0,
    x87_status: u16 = 0,
    x87_control: u16 = 0x037F,
    terminated: bool = false,
    exit_code: u64 = 0,
    faulted: bool = false,
    termination_reason: exit_diagnostics.TerminationReason = .unknown,
    /// What ended the run, recorded where it was decided (first wins), and
    /// the notable events before it. See `diagnostics/terminal_event.zig`.
    terminal_event: terminal_event.TerminalEvent = .{},
    notable_events: terminal_event.NotableRing(16) = .{},
    executed_steps: u64 = 0,
    // The Windows PE route has one cooperative owner loop and several guest
    // worker slices. QueryPerformanceCounter must advance for both: Xenia's
    // frame limiter runs in a worker and otherwise sees a frozen clock while
    // that worker is being serviced.
    /// The performance counter the guest reads, and where its value comes
    /// from. See `guest_clock.zig`.
    guest_clock: guest_clock.Clock = .{},
    /// Atomic publication for APIs that only need the clock's scalar tick
    /// value. Writers update it while holding `guest_clock_mutex`.
    guest_clock_published_ticks: guest_clock.PublishedTicks = .{},
    /// Parallel guest contexts may advance the same multi-field clock. Keep
    /// tick, stride, and host-base changes coherent with the snapshots
    /// returned to wait and timer code.
    guest_clock_mutex: HostMutex = HostMutex.init("guest clock"),
    /// Private sampling cadence for the owner context. Worker contexts carry
    /// their own copy so parallel instructions do not contend on a shared
    /// cache line just to decide whether the clock needs a fresh sample.
    guest_clock_sample_steps: u64 = 0,
    /// A yield boundary asked for the active worker's slice to end.
    ///
    /// `YieldProcessor`, `SwitchToThread` and `Sleep(0)` all mean the same
    /// thing - "I have nothing to do; run someone else" - and all three used
    /// to return without doing it, so a guest spin-wait ran its whole
    /// ten-thousand-step slice spinning. Xenia's logger uses
    /// `disruptorplus::spin_wait_strategy`, whose consumer spins on an empty
    /// ring forever; on the 2026-09-12 run five such threads held about
    /// seventy percent of the interpreter.
    windows_guest_slice_yield_requested: bool = false,
    windows_guest_slice_yields: u64 = 0,
    /// Worker slices ended early at a PAUSE spin hint.
    windows_guest_pause_yields: u64 = 0,
    /// The running slice asked to end at a PAUSE. Such a slice is a spin for
    /// `noteWindowsGuestSliceShape`: it ends before the spin probe is ever
    /// taken, so without this a pause-spinner never earned a backoff and
    /// took an equal turn every round - 101 million slice switches on
    /// 2026-09-21, most of them XThread001A and RENDER waiting on MAIN.
    windows_slice_pause_yield: bool = false,
    windows_pause_spin_slices: u64 = 0,
    /// A worker signalled an object the owner is waiting on. The worker's
    /// slice ends at the next step, before any minimum-slice floor, so the
    /// owner takes the object before the worker can take it back.
    ///
    /// Without this the owner's wait on a winpthreads mutex event was lost
    /// 16384 times in a row on 2026-09-19: the worker unlocked (SetEvent),
    /// kept its slice, and relocked; the owner - Xenia's UI thread - never
    /// painted. A real kernel would have run the woken waiter on another
    /// core; on one cooperative interpreter the handoff has to be explicit.
    windows_guest_handoff_requested: bool = false,
    windows_owner_wait_handoffs: u64 = 0,
    /// The handles the owner's current (yielded) wait is on, valid while a
    /// worker slice runs on the owner's behalf.
    windows_owner_wait_handles: [8]u64 = @splat(0),
    windows_owner_wait_handle_count: u8 = 0,
    windows_guest_sleep_parks: u64 = 0,
    // The ring implementation is shared with the other execution paths. Its
    // backing storage is heap-owned so returning this state by value cannot
    // leave `trace_ring` pointing at a pre-return stack field.
    trace_storage: []ElfTraceEntry = &.{},
    trace_ring: execution_history.Ring(ElfTraceEntry) = execution_history.Ring(ElfTraceEntry).init(&.{}),
    trace_ring_mutex: HostMutex = HostMutex.init("trace ring"),
    /// The PE route normally retains only `last_instruction_rip`; a full
    /// instruction ring is an exit-diagnostics aid and costs several stores
    /// on every interpreted instruction. ELF keeps the historical ring on,
    /// while PE enables it only when explicitly requested.
    trace_ring_enabled: bool = false,
    // Stable heap storage avoids multiplying this cache across value-return
    // initialization temporaries and guest exception frames.
    decode_cache: []DecodeCacheEntry = &.{},
    decode_cache_victims: []DecodeCacheEntry = &.{},
    decode_cache_shards: []DecodeCacheShard = &.{},
    /// Hits served by the private worker cache. Atomic because several host
    /// workers may update it, but one counter per process keeps its cost below
    /// the shared cache's mutex and four-way probe that it replaces.
    decode_cache_worker_local_hits: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Global only for the small victim-bank updates, all serialized by
    /// `decode_cache_miss_mutex`. Primary hits use their set shard's clock.
    decode_cache_clock: u64 = 0,
    decode_cache_miss_sites: [DECODE_CACHE_MISS_SITE_CAPACITY]DecodeCacheMissSite = [_]DecodeCacheMissSite{.{}} ** DECODE_CACHE_MISS_SITE_CAPACITY,
    decode_cache_miss_site_count: usize = 0,
    decode_cache_miss_site_overflow: u64 = 0,
    /// Misses per cause across every shard, for the report throttle only.
    /// `noteDecodeCacheMiss` is serialized (the miss mutex in parallel mode),
    /// so plain counters are exact. The sharded counters stay the totals.
    decode_cache_miss_reports: [std.enums.values(DecodeCacheMissCause).len]u64 = @splat(0),
    /// The addresses `step` must intercept before decoding, as boxes so the
    /// per-instruction question is a compare, not a call. The 2026-09-17
    /// profile of the PE64 route put `windowsImportStubAt` alone at 3.6% of
    /// the run, called on every instruction to say "not a stub".
    ///
    /// Stubs: every address `registerWindowsImportStubAt` recorded, which is
    /// the only way an address becomes a stub (both branches of
    /// `windowsImportStubAt` require `stub.address == address`).
    windows_stub_box: HookBox = .{},
    /// Compatibility hooks: PE-local pthread condition entries, UTF-8
    /// find_any_of and codecvt entries, and a diagnostic-only utf8::count
    /// observer; the only addresses
    /// `tryWindowsGuestCompatibility` acts on. This is an exact sparse set;
    /// using a range here admitted millions of unrelated instructions between
    /// the far-apart Xenia entry points.
    windows_compat_hook_points: HookPoints = .{},
    /// Aggregate and per-hook-class false positives. The aggregate remains
    /// for compatibility with existing reports; the split counters identify
    /// which admission structure needs attention on the next run.
    step_hook_box_false_positives: u64 = 0,
    step_synthetic_hook_false_positives: u64 = 0,
    step_windows_stub_false_positives: u64 = 0,
    step_windows_compat_hook_false_positives: u64 = 0,
    /// The executable PE ranges as one box, asked before the per-write scan
    /// in `bumpWindowsImageCodeGeneration`; and the range that answered the
    /// last fetch-generation query, asked first in
    /// `windowsImageCodeGenerationFor` (straight-line code stays in one
    /// section).
    windows_executable_box: HookBox = .{},
    windows_executable_range_hint: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    /// The block translator, created at the first step when enabled; null
    /// while disabled or after executable memory was refused.
    block_jit: ?*BlockJitState = null,
    block_jit_enabled: bool = true,
    block_jit_unavailable: bool = false,
    block_jit_disabled_reason: []const u8 = "",
    block_jit_hot_threshold: u16 = BLOCK_JIT_DEFAULT_HOT_THRESHOLD,
    /// Shared with the emitted code; see `block_jit.Scratch`.
    block_jit_scratch: block_jit.Scratch = .{},
    /// The software TLB the emitted code probes before calling a memory
    /// helper (`block_jit.Tlb`). The helpers admit pages after serving a
    /// plain access; every protection and mapping change invalidates every
    /// live context's table. This inline table belongs to the owner context.
    /// Heap-owned because each entry is 16 bytes and the TLB is per
    /// executor. Keeping the owner table inline made ElfState's return-by-
    /// value initializer hundreds of KiB larger when the table grew.
    block_jit_tlb: ?*block_jit.Tlb = null,
    /// Active TLB pointer consumed by translated code. Null means the owner
    /// table above; guest workers select their own table at each cooperative
    /// context switch.
    block_jit_tlb_active: ?*block_jit.Tlb = null,
    block_jit_tlb_enabled: bool = true,
    block_jit_streaming_stores_enabled: bool = true,
    parallel_pause_batches_enabled: bool = true,
    parallel_pause_batched_instructions: std.atomic.Value(u64) = .init(0),
    /// Whether guest threads run on their own host threads (see
    /// `parallelDirectTlbActive` for how their translated code reaches
    /// memory).
    parallel_guest_execution: bool = false,
    /// Parallel mode admits each executor's translated accesses to its own
    /// software TLB: a hit is one LDAR or STLR on the host page, which is
    /// x86-TSO on ARM64 by itself. Without it every translated load and
    /// store of every thread went through `blockJitRead`/`blockJitWrite`
    /// and two contended stripe-lock atomics - the 2026-09-26 run's workers
    /// never filled a TLB entry. `ROSETTE_PE64_PARALLEL_TLB=0` restores the
    /// helper-only route for an A/B run.
    parallel_direct_tlb: bool = true,
    /// Moved before every cross-thread TLB invalidation. A parallel fill
    /// judged against older protection or mapping state sees it move and
    /// retires the entry it just wrote (`blockJitTlbConsider`).
    block_jit_tlb_epoch: std.atomic.Value(u64) = .init(0),
    parallel_tlb_cross_invalidations: std.atomic.Value(u64) = .init(0),
    parallel_tlb_raced_fills: std.atomic.Value(u64) = .init(0),
    parallel_tlb_invalidation_work: tlb_diagnostics.InvalidationWork = .{},
    /// Parallel `guestMemory` borrows refused because the range may hold
    /// fetched instructions. Nonzero names a runtime path that writes code
    /// through a raw view instead of the ordered write API.
    parallel_code_borrow_refusals: std.atomic.Value(u64) = .init(0),
    /// How many times a helper offered the TLB a page. The 2026-09-19
    /// run reported zero fills *and* zero refusals, which the admission
    /// rules cannot both produce: every path past the first four guards
    /// counts one or the other. This says whether the helper is reached
    /// at all, so the next run distinguishes "emitted code never takes
    /// the slow path" from "a guard refuses everything silently".
    block_jit_tlb_considers: u64 = 0,
    /// The three guards that used to return without counting, so a run whose
    /// fills and refusals are both zero says which one answered.
    block_jit_tlb_bail_traced: u64 = 0,
    block_jit_tlb_bail_straddle: u64 = 0,
    block_jit_tlb_bail_null_page: u64 = 0,
    /// Blocks run on from the RIP the previous block left
    /// (ROSETTE_X64_BLOCK_JIT_CHAIN=0 interprets a `step` between blocks).
    block_jit_chain_enabled: bool = true,
    /// VEX.128 vector templates are compiled (ROSETTE_X64_BLOCK_JIT_VECTOR=0
    /// hands every vector instruction to the interpreter).
    block_jit_vectors_enabled: bool = true,
    /// Forward branches may stay inside a block (ROSETTE_X64_BLOCK_JIT_INTERNAL_EDGES=0 turns it off).
    block_jit_internal_edges_enabled: bool = true,
    /// 16-byte vector loads and stores consult the page-protection table,
    /// so a write watch sees `vmovaps` stores (ROSETTE_X64_WIDE_ACCESS_WATCH=0
    /// turns it off).
    ///
    /// On by default since `NtProtectVirtualMemory` became real. Xenia's
    /// PowerPC backend emits an SSE store for every VMX128 `stvx` and its CRT
    /// copies vector-sized blocks, so with wide accesses unwatched most of
    /// what a title writes into a watched texture or vertex buffer would
    /// still pass without a fault and the watch would be half dead. The cost
    /// is two O(1) table lookups per 128-bit access, and only while some page
    /// is actually restricted.
    ///
    /// It was off before that: the first run with it on (2026-09-19 18:27)
    /// refreshed one guest frame and then starved the GPU thread. That run
    /// had no read-only page in it at all - nothing had ever recorded one -
    /// so the watch could not have been what fired. It stays a bisect switch.
    wide_access_watch_enabled: bool = true,
    /// How many guest instructions the last `step` retired: one for an
    /// interpreted instruction, a block's completed count otherwise. The
    /// two execution loops add it to every per-instruction counter.
    step_retired: u32 = 1,
    libc_start_main_trampolined: bool = false,
    dynamic_relocations: []const elf_loader.DynamicRelocation = &.{},
    dynamic_relocation_lookup: x64_linux_runtime.DynamicRelocationLookup = .{},
    local_symbols: []const elf_loader.Symbol = &.{},
    init_functions: []const u64 = &.{},
    init_index: usize = 0,
    pending_main_addr: u64 = 0,
    pending_argc: u64 = 0,
    pending_argv: u64 = 0,
    heap_next: u64 = MEM_BASE + (MEM_SIZE / 2),
    // PE32+ supplies an explicit heap/stack split. Keep it separate from the
    // historical ELF cutoff: using STACK_SIZE for a PE run allows the bump
    // heap to consume the lower part of the PE's reserved main stack.
    guest_heap_limit: u64 = 0,
    trace_syscalls: bool = false,
    trace_syscall_bytes: bool = false,
    trace_fd_filter: ?u64 = null,
    trace_calls: bool = false,
    /// `trace_windows_messages or trace_windows_threads`, kept by
    /// `refreshBlockJitTransferTraced`. The translated `call` template reads
    /// this one byte instead of both fields.
    block_jit_transfer_traced: bool = false,
    /// Compile-time `call_rel32` refusals by reason (`blockJitCallRefusal`).
    block_jit_call_refusals: [@typeInfo(BlockJitCallRefusal).@"enum".fields.len]u64 = @splat(0),
    // Resolve the optional RIP trace range once at state construction.  The
    // PE interpreter checks this on every instruction; consulting the host
    // environment in that hot path turns an opt-in diagnostic into a default
    // startup tax even when tracing is disabled.
    trace_rip_start: ?u64 = null,
    trace_rip_end: ?u64 = null,
    /// Optional cap for the existing RIP trace. A generated-code address can
    /// be a hot loop, so a range-only trace must be bounded before it is safe
    /// to use during a long PE run.
    trace_rip_limit: ?u64 = null,
    trace_rip_events: u64 = 0,
    // Optional exact guest-memory watch used while diagnosing pointer
    // corruption in the PE route.  The watch is intentionally opt-in and
    // records overlapping writes to an eight-byte slot, so a mistaken 32-bit
    // store cannot disappear from the evidence.
    trace_write_address: ?u64 = null,
    /// Guest ranges a spin report armed: every later write to them is logged
    /// (`PE64 GUEST SPIN WATCH WRITE`), and their pages stay off the write TLB.
    spin_watch: guest_spin.WatchSet = .{},
    /// Guest threads currently interpreted with a read capture. Zero keeps the
    /// read path and the dispatcher at one relaxed load.
    spin_capture_threads: std.atomic.Value(u32) = .init(0),
    /// `ROSETTE_BLOCK_JIT_VERIFY_MEMORY=1`: cross-check every translated
    /// block that reaches memory against the interpreter before trusting it.
    block_jit_verify_memory: bool = false,
    /// Contexts with a verify journal bound; zero keeps every guest memory
    /// access at one relaxed load.
    verify_journal_users: std.atomic.Value(u32) = .init(0),
    /// GetCurrentThreadId/GetCurrentThread/GetCurrentProcess(Id) answered
    /// without the runtime lock.
    windows_fast_identity_imports: std.atomic.Value(u64) = .init(0),
    /// Xenia's CommandProcessor, as its UpdateWritePointer milestone last
    /// named it: the stall assist wakes its worker through the same event.
    xenia_command_processor_seen: std.atomic.Value(u64) = .init(0),
    stall_assists: std.atomic.Value(u64) = .init(0),
    /// Reads served from the synthesised KUSER_SHARED_DATA page.
    kuser_shared_reads: std.atomic.Value(u64) = .init(0),
    /// Every other read nothing maps, by page (`diagnostics/unmapped_reads.zig`).
    unmapped_read_census: unmapped_reads.Census = .{},
    /// The guest-visible time sources at the previous pulse, for deltas.
    time_audit_last: TimeAuditSample = .{},
    /// Which `ROSETTE_XENIA_DUMP_GUEST_CODE` functions have been logged.
    xenia_guest_code_dumped: [8]bool = @splat(false),
    stall_assist_gpu_wakes: std.atomic.Value(u64) = .init(0),
    // Optional allocation provenance for the Windows PE route. The PE image
    // has its own pthread pool as well as Rosetta-owned heap-backed imports,
    // so an address-only write watch cannot identify which lifetime supplied
    // a bad pointer. Keep this diagnostic off the hot path unless requested.
    trace_allocations: bool = false,
    // Record formatter object provenance once per call without enabling the
    // instruction-wide RIP tracer.
    trace_formatter: bool = false,
    trace_formatter_address: ?u64 = null,
    // Optional byte snapshots around the PE StringBuffer append imports. This
    // is deliberately narrower than ABI tracing: it answers whether a bad
    // formatted value was already present in the source temporary or was
    // introduced while copying it into Xenia's config buffer.
    trace_string_memory: bool = false,
    // These two traces are checked around every interpreted instruction when
    // enabled. Resolve their environment policy once at state construction;
    // getenv is a host call and must never sit in the PE hot path.
    trace_vector: bool = false,
    trace_utf8: bool = false,
    // Boundary-only scheduler tracing. Unlike ABI diagnostics this emits no
    // per-import records, so it can identify a worker that repeatedly yields
    // at one guest lock without changing the hot instruction path materially.
    trace_windows_threads: bool = false,
    // Message-boundary tracing is intentionally separate from full ABI
    // diagnostics: it records class registration, PostMessage, GetMessage,
    // and guest WndProc dispatch without printing every Windows import.
    trace_windows_messages: bool = false,
    // WinMM audio tracing is similarly boundary-only.  It reports format
    // negotiation, buffer completion, and callback failures without dumping
    // every sample or every successful semaphore release.
    trace_windows_audio: bool = false,
    // Bounded path tracing for the confined PE filesystem. This is narrower
    // than ABI diagnostics and is useful when a Windows title is rejected
    // before its first XISO/XEX signature read.
    trace_windows_paths: bool = false,
    windows_path_trace_events: u32 = 0,
    windows_media_path_trace_events: u32 = 0,
    windows_media_io_trace_events: u32 = 0,
    windows_media_mapping_trace_events: u32 = 0,
    // Wait-boundary tracing records only wait calls that actually service a
    // queued guest worker. It is useful for diagnosing cooperative mutex
    // stalls without enabling per-import ABI tracing.
    trace_windows_waits: bool = false,
    // Condition tracing is narrower than worker tracing: it records only the
    // PE-local pthread condition hooks, not every ordinary wait boundary.
    trace_windows_conditions: bool = false,
    // Fixed Windows allocations and their first writes are normally silent.
    // Xenia's native backend context lives in one of these ranges, so keep a
    // bounded opt-in trace for proving that its guest-visible storage exists
    // and is populated without enabling the per-import ABI log.
    trace_windows_memory: bool = false,
    windows_memory_trace_events: std.atomic.Value(u32) = .init(0),
    windows_memory_trace_step_closed: std.atomic.Value(bool) = .init(false),
    // The Xenia x64 code cache maps one page-file mapping twice: an
    // executable view at 0xA0000000 and a writable view at 0xB0000000. Keep
    // the alias and copy diagnostics separate from ordinary Windows-memory
    // tracing so a generated-code failure can be explained without enabling
    // per-import ABI output.
    trace_windows_mappings: bool = false,
    windows_mapping_trace_events: u32 = 0,
    windows_code_copy_trace_events: u32 = 0,
    // Xenia's PE loader decrypts every 16-byte XEX block through a retained
    // pure Rijndael helper.  The accelerator is opt-in and symbol-gated: it
    // can shorten a deterministic bootstrap bottleneck without changing the
    // generic PE execution contract or touching Xenia's source.
    xenia_rijndael_accelerator_enabled: bool = false,
    xenia_rijndael_target_checked: bool = false,
    xenia_rijndael_target: ?u64 = null,
    xenia_rijndael_accelerated_calls: u64 = 0,
    xenia_rijndael_accelerator_failures: u64 = 0,
    // Xenia's PE loader hashes the fully materialized XEX with TinySHA1
    // before title code can run.  On the ARM64 host, interpreting its
    // 80-round x86-64 compression loop can consume hundreds of millions of
    // guest steps while the graphics bridge is otherwise healthy.  Keep the
    // host implementation opt-in and signature-gated like the Rijndael
    // accelerator above.
    xenia_sha1_accelerator_enabled: bool = false,
    xenia_sha1_feed_enabled: bool = true,
    xenia_sha1_target_checked: bool = false,
    xenia_sha1_target: ?u64 = null,
    xenia_sha1_accelerated_blocks: u64 = 0,
    xenia_sha1_accelerator_failures: u64 = 0,
    xenia_sha1_feed_spans: u64 = 0,
    xenia_sha1_feed_bytes: u64 = 0,
    xenia_sha1_feed_declines: u64 = 0,
    xenia_sha1_kernel_feed_spans: u64 = 0,
    xenia_sha1_kernel_feed_bytes: u64 = 0,
    // Xenia's optional diagnostic tables are built before title launch. Keep
    // the host-side tabulate formatter out of the PE hot path while retaining
    // its normal ownership and empty-string return contract.
    xenia_tabulate_accelerator_enabled: bool = false,
    xenia_tabulate_target_checked: bool = false,
    xenia_tabulate_target: ?u64 = null,
    xenia_tabulate_accelerated_strings: u64 = 0,
    xenia_tabulate_accelerator_failures: u64 = 0,
    // Graphics progress tracing is deliberately separate from the ordinary
    // 50M-step register sample. It adds worker and Vulkan state needed to
    // distinguish a guest wait, a completed process, and a native bridge
    // that stopped receiving calls.
    trace_graphics_progress: bool = false,
    diagnose_abi: bool = false,
    call_stack: x64_guest_abi.CallStack = .{},
    interactive_output_path: ?[]u8 = null,
    interactive_summary_printed: bool = false,
    windows_runtime_enabled: bool = false,
    guest_execution_gate: GuestExecutionGate = .{},
    parallel_guest_wake_hub: parallel_workers.WakeHub = .{},
    /// Bumped (under the runtime lock) whenever a guest thread becomes
    /// runnable or a wait object is signalled; see `WindowsRuntimeLockGuard`.
    windows_thread_wake_epoch: u64 = 0,
    parallel_guest_termination: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    parallel_owner_executed_steps: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    windows_runtime_mutex: HostMutex = HostMutex.init("Windows runtime mutex"),
    /// The process owner's x86 store queue and a stable queue for each
    /// Windows guest worker slot (`lib/processor/ELF_processor/tso/`).
    /// Buffers stay outside copied CPU contexts so a scheduler snapshot never
    /// duplicates pending memory operations.
    guest_store_buffers: tso_memory.GuestStoreBuffers = .{},
    windows_unknown_imports_fatal: bool = true,
    windows_unresolved_imports: [WINDOWS_UNRESOLVED_IMPORT_CAPACITY]WindowsUnresolvedImport = [_]WindowsUnresolvedImport{.{}} ** WINDOWS_UNRESOLVED_IMPORT_CAPACITY,
    windows_unresolved_import_count: usize = 0,
    /// Xenia's logger writes directly through the guest CRT. Keep a bounded
    /// line assembler at that boundary so warnings are observed even though
    /// they never pass Rosette's own std.log funnel.
    windows_guest_output_line: [WINDOWS_GUEST_OUTPUT_LINE_CAPACITY]u8 = [_]u8{0} ** WINDOWS_GUEST_OUTPUT_LINE_CAPACITY,
    windows_guest_output_line_len: usize = 0,
    windows_guest_output_line_truncated: bool = false,
    windows_guest_output_truncated_lines: u64 = 0,
    windows_guest_failure_points: [WINDOWS_GUEST_FAILURE_POINT_CAPACITY]WindowsGuestFailurePoint = [_]WindowsGuestFailurePoint{.{}} ** WINDOWS_GUEST_FAILURE_POINT_CAPACITY,
    windows_guest_failure_point_count: usize = 0,
    windows_guest_failure_point_overflow: u64 = 0,
    windows_guest_warning_points: [WINDOWS_GUEST_WARNING_POINT_CAPACITY]WindowsGuestWarningPoint = [_]WindowsGuestWarningPoint{.{}} ** WINDOWS_GUEST_WARNING_POINT_CAPACITY,
    windows_guest_warning_point_count: usize = 0,
    windows_guest_warning_point_overflow: u64 = 0,
    windows_guest_warning_lines: u64 = 0,
    gpu_draw_failures: [GPU_DRAW_FAILURE_CAPACITY]GpuDrawFailure = [_]GpuDrawFailure{.{}} ** GPU_DRAW_FAILURE_CAPACITY,
    gpu_draw_failure_count: usize = 0,
    gpu_draw_failure_overflow: u64 = 0,
    /// Warning-level lines Xenia prints while nothing is wrong.
    windows_guest_informational_lines: u64 = 0,
    /// Bare module names Xenia's module lookup printed `device not found`
    /// for, by name. See `xenia_warning_severity_map.bareModuleLookupName`.
    windows_guest_module_lookups: [GUEST_MODULE_LOOKUP_CAPACITY]GuestModuleLookup = [_]GuestModuleLookup{.{}} ** GUEST_MODULE_LOOKUP_CAPACITY,
    windows_guest_module_lookup_count: usize = 0,
    windows_guest_module_lookup_lines: u64 = 0,
    windows_guest_module_lookup_overflow: u64 = 0,
    /// Xenia's `an import variable was not resolved` warnings: the line that
    /// turns a bare-name lookup into a real failure.
    windows_guest_unresolved_import_lines: u64 = 0,
    /// Stdout and stderr governors, allocated on the first guest write so a
    /// state that never writes carries neither.
    windows_guest_output_governors: ?*[2]guest_output_governor.Governor = null,
    windows_guest_output_host_fds: [2]std.posix.fd_t = .{ -1, -1 },
    windows_guest_output_host_write_failures: u64 = 0,
    /// Warning-level lines that name a real degradation the run survives.
    windows_guest_advisory_lines: u64 = 0,
    /// Whether a fatal point stops the run. The runtime arms this by default
    /// - a warning is an error until something proves otherwise - and
    /// `ROSETTE_XENIA_FATAL_POINT_TERMINATE=0` returns to recording only.
    /// A test constructs the state with it off, so a stop is asserted
    /// deliberately.
    windows_fatal_point_terminate: bool = false,
    windows_fatal_point_events: u64 = 0,
    /// Labels `ROSETTE_XENIA_FATAL_POINT_ALLOW` names: a fatal point with one
    /// of these is reported and stepped past instead of stopping the run.
    windows_fatal_point_allow: [WINDOWS_FATAL_POINT_ALLOW_BYTES]u8 = [_]u8{0} ** WINDOWS_FATAL_POINT_ALLOW_BYTES,
    windows_fatal_point_allow_len: usize = 0,
    windows_fatal_point_allowed_events: u64 = 0,
    /// Interpreted guest accesses inside the null page. Windows never maps
    /// the first 64 KiB, so each is an access violation on the real OS;
    /// Rosette used to answer them with zero.
    guest_null_page_accesses: u64 = 0,
    guest_null_page_fatal: bool = false,
    /// Threads created with CREATE_SUSPENDED, and the calls that move a count.
    windows_thread_suspended_creations: u64 = 0,
    windows_thread_suspend_calls: u64 = 0,
    windows_thread_resume_calls: u64 = 0,
    /// `NtCreateFile`/`NtOpenFile` requests read at the export trampoline.
    guest_file_requests_captured: u64 = 0,
    guest_file_requests_unreadable: u64 = 0,
    owner_file_request: GuestFileRequest = .{},
    /// Empty paths `ResolvePath` failed on; each is a fatal point.
    guest_vfs_empty_name_faults: u64 = 0,
    /// Indirect buffers the ring pointed at, decoded the way the ring is.
    gpu_indirect_buffers: [GPU_INDIRECT_BUFFER_CAPACITY]GpuRingWindow = [_]GpuRingWindow{.{}} ** GPU_INDIRECT_BUFFER_CAPACITY,
    gpu_indirect_buffer_count: usize = 0,
    gpu_indirect_buffers_seen: u64 = 0,
    gpu_indirect_buffers_unreadable: u64 = 0,
    gpu_indirect_type3_packets: u64 = 0,
    gpu_indirect_draw_packets: u64 = 0,
    gpu_indirect_swap_packets: u64 = 0,
    gpu_ring_draw_packets: u64 = 0,
    gpu_ring_swap_packets: u64 = 0,
    // Optional PE guest-function semantic correction discovered by the PE
    // loader. Rosetta does not rewrite the Windows image; it can instead
    // complete a recognized standard-library boundary when the image's own
    // implementation exposes a provably empty character set.
    windows_utf8_find_any_of_entry: ?u64 = null,
    /// Exact Xenia UTF-8 counter entry. Rosetta observes its string_view for
    /// malformed bytes, then lets the original guest body run unchanged.
    windows_utf8_count_entry: ?u64 = null,
    windows_utf8_count_events: u64 = 0,
    windows_utf8_count_invalid_events: u64 = 0,
    /// Diagnostic-only probes for the exact fmt::vformat chain that builds
    /// SaveConfig's generated TOML line. The probes snapshot inputs at the
    /// two formatter boundaries and outputs on return; they never consume or
    /// rewrite guest execution.
    windows_fmt_vformat_entry: ?u64 = null,
    windows_fmt_vformat_to_entry: ?u64 = null,
    windows_fmt_probe_active: bool = false,
    windows_fmt_probe_calls: u64 = 0,
    windows_fmt_probe_current_call: u64 = 0,
    windows_fmt_vformat_return: ?u64 = null,
    windows_fmt_vformat_result: u64 = 0,
    windows_fmt_vformat_to_return: ?u64 = null,
    windows_fmt_vformat_to_buffer: u64 = 0,
    /// Exact Itanium C++ throw entry. This is a diagnostic observer used to
    /// attribute `utf8::invalid_utf8` to its throw-site and source buffer.
    windows_cxa_throw_entry: ?u64 = null,
    windows_cxa_throw_events: u64 = 0,
    windows_invalid_utf8_throw_events: u64 = 0,
    windows_invalid_utf8_source_matches: u64 = 0,
    windows_invalid_utf8_last_source_address: u64 = 0,
    windows_invalid_utf8_last_source_byte: u8 = 0,
    windows_invalid_utf8_last_source_byte_matches_exception: bool = false,
    windows_invalid_utf8_last_iterator_ref_consistent: bool = false,
    windows_invalid_utf8_last_saved_cursor_matches_exception: bool = false,
    windows_invalid_utf8_last_live_cursor_matches_exception: bool = false,
    windows_invalid_utf8_last_consumer: u64 = 0,
    windows_invalid_utf8_last_file_offset: ?u64 = null,
    // Exact libstdc++/MinGW codecvt boundary for UTF-8 to Windows UTF-16.
    // The loader arms this by mangled COFF symbol; Rosetta does not patch the
    // guest image or accept a caller-selected address.
    windows_codecvt_in_entry: ?u64 = null,
    windows_codecvt_in_events: u64 = 0,
    // MinGW's pthread condition-variable routines are linked into some PE
    // images instead of being imported.  The PE runner discovers their
    // executable entry points from the image bytes and the compatibility
    // boundary intercepts them before their host-oriented semaphore loop can
    // spin forever on the single cooperative executor.
    windows_pthread_cond_wait_entry: ?u64 = null,
    windows_pthread_cond_signal_entry: ?u64 = null,
    windows_pthread_cond_broadcast_entry: ?u64 = null,
    /// The image's `pthread_mutex_lock_intern(mutex, milliseconds)`, which
    /// `pthread_mutex_lock` tail-jumps to with INFINITE. A signalled
    /// condition waiter retakes its mutex by calling it, so every
    /// acquisition of a guest mutex follows the image's own protocol.
    windows_pthread_mutex_lock_intern_entry: ?u64 = null,
    windows_condition_relocks: u64 = 0,
    /// Reports written by `noteStackPointerCollapse`, capped.
    stack_collapse_reports: u32 = 0,
    /// A bloom filter over every address an interpreter call/jump arm has a
    /// hook for inside the image: kernel-export entries, milestones, the
    /// pthread condition entries and the accelerators. The native indirect
    /// templates test a target inside the image against it and hand the
    /// instruction to the interpreter on a hit, so a C++ vtable call or a
    /// switch table jump into Xenia's own code runs natively unless its
    /// exact target is hooked. A false positive only costs a fallback.
    block_jit_hook_filter: [BLOCK_JIT_HOOK_FILTER_BYTES]u8 = @splat(0),
    /// Serializes `publishBlockJitHookFilter`: a census export can saturate
    /// on any guest thread.
    block_jit_hook_filter_mutex: HostMutex = HostMutex.init("hook filter"),
    /// Nonzero until the filter is built, and whenever something hooks
    /// image targets the filter cannot name (a local-function shim table,
    /// an unresolved accelerator, the thread-call trace): every indirect
    /// transfer into the image then takes the interpreter, as it always did.
    block_jit_image_targets_hooked: u8 = 1,
    /// Whether `startHostProfile` started the wall-time sampler; the exit
    /// report stops it and attributes what it saw.
    host_profile_started: bool = false,
    /// Diagnostic-only input counters and the bounded frame-aligned guest
    /// ledger. These remain inert while ROSETTE_HOST_PROFILE is disabled.
    frame_input_activity: frame_attribution.InputActivity = .{},
    frame_attribution_ledger: frame_attribution.Ledger = .{},
    /// Set while `rebuildBlockJitHookFilter` runs, so an accelerator it
    /// resolves does not ask for the rebuild already in progress.
    block_jit_hook_filter_rebuilding: bool = false,
    /// The import address table, whose slots the dynamic-function shim keys
    /// an indirect call on. Zero when unknown: the image range is used.
    windows_iat_low: u64 = 0,
    /// IAT slot -> direct stub position + 1 (`indexWindowsIatStubs`).
    windows_iat_stub_index: []u32 = &.{},
    /// `call [IAT]`/`jmp [IAT]` answered on a lock-free lane straight from
    /// translated code or the interpreter's jump arm.
    windows_import_slot_fast_transfers: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    windows_iat_high: u64 = 0,
    // Enable Rosetta's cooperative completion of the image-linked MinGW
    // condition functions when requested. The image's semaphore/
    // critical-section sequence is host-oriented and cannot be allowed to
    // return spuriously on the single interpreter; Rosetta owns the wait,
    // signal, mutex-release, and mutex-reacquire contract at this boundary.
    windows_pthread_cond_native: bool = false,
    windows_condition_wait_calls: u64 = 0,
    windows_condition_wait_blocks: u64 = 0,
    windows_condition_wait_resumes: u64 = 0,
    windows_condition_signal_calls: u64 = 0,
    windows_condition_broadcast_calls: u64 = 0,
    windows_condition_unblocks: u64 = 0,
    windows_condition_mutex_releases: u64 = 0,
    windows_condition_mutex_release_failures: u64 = 0,
    windows_condition_mutex_reacquires: u64 = 0,
    windows_condition_mutex_reacquire_blocks: u64 = 0,
    windows_condition_hook_events: u64 = 0,
    windows_guest_compatibility_events: u64 = 0,
    windows_last_error: u32 = 0,
    windows_unhandled_exception_filter: u64 = 0,
    windows_symbol_options: u32 = 0,
    windows_symbol_services_initialized: bool = false,
    /// Which libraries this run handed a handle to, so a later
    /// `GetProcAddress` can be answered against the right per-DLL contract
    /// instead of against an anonymous name.
    windows_loaded_modules: [MAX_WINDOWS_LOADED_MODULES]WindowsLoadedModule =
        [_]WindowsLoadedModule{.{}} ** MAX_WINDOWS_LOADED_MODULES,
    windows_loaded_module_count: u32 = 0,
    windows_loaded_module_overflow: u32 = 0,
    /// Modules and exports Rosetta reported absent, with the first few named.
    /// A refusal is the honest answer and is not a defect, but a run that
    /// took a different code path because of one has to be able to say so.
    windows_module_refusals: [MAX_WINDOWS_DYNAMIC_REFUSALS]WindowsDynamicRefusal =
        [_]WindowsDynamicRefusal{.{}} ** MAX_WINDOWS_DYNAMIC_REFUSALS,
    windows_module_refusal_count: u32 = 0,
    windows_module_refusal_events: u64 = 0,
    windows_module_refusal_gaps: u64 = 0,
    /// The verdicts last written, so a checkpoint says nothing when nothing
    /// moved. Slices point at string literals owned by the stage tables.
    reported_first_frame_wall: []const u8 = "",
    reported_audio_wall: []const u8 = "",
    reported_guest_output_wall: []const u8 = "",
    /// When the first checkpoint was reached, and the checkpoint before this
    /// one. A cumulative rate hides a run that is getting slower, which is
    /// the shape every table that grows without bound produces, so the
    /// per-window rate is reported next to it.
    run_first_checkpoint_nanos: u64 = 0,
    xenia_clock: xenia_clock_probe.Probe = .{},
    run_last_checkpoint_nanos: u64 = 0,
    run_last_checkpoint_steps: u64 = 0,
    reported_refusal_events: u64 = 0,
    reported_proc_refusal_events: u64 = 0,
    run_chains_reported: bool = false,
    windows_unreadable_module_names: u64 = 0,
    /// How every fixed VirtualAlloc related to what already backed it.
    /// Indexed by `WindowsAllocationDisposition`.
    windows_allocation_dispositions: [WINDOWS_ALLOCATION_DISPOSITION_COUNT]u64 =
        [_]u64{0} ** WINDOWS_ALLOCATION_DISPOSITION_COUNT,
    windows_unbacked_commits: [MAX_WINDOWS_UNBACKED_COMMITS]WindowsUnbackedCommit =
        [_]WindowsUnbackedCommit{.{}} ** MAX_WINDOWS_UNBACKED_COMMITS,
    windows_unbacked_commit_count: u32 = 0,
    windows_unbacked_commit_overflow: u64 = 0,
    windows_allocation_refusals: [MAX_WINDOWS_ALLOCATION_REFUSALS]WindowsAllocationRefusal =
        [_]WindowsAllocationRefusal{.{}} ** MAX_WINDOWS_ALLOCATION_REFUSALS,
    windows_allocation_refusal_count: u32 = 0,
    windows_allocation_refusal_overflow: u64 = 0,
    windows_allocation_relocations: [MAX_WINDOWS_ALLOCATION_RELOCATIONS]WindowsAllocationRelocation =
        [_]WindowsAllocationRelocation{.{}} ** MAX_WINDOWS_ALLOCATION_RELOCATIONS,
    windows_allocation_relocation_count: u32 = 0,
    windows_allocation_relocation_overflow: u64 = 0,
    windows_allocation_relocation_overflow_records: [MAX_WINDOWS_ALLOCATION_RELOCATION_OVERFLOW_SAMPLES]WindowsAllocationRelocation =
        [_]WindowsAllocationRelocation{.{}} ** MAX_WINDOWS_ALLOCATION_RELOCATION_OVERFLOW_SAMPLES,
    windows_allocation_relocation_overflow_record_count: u32 = 0,
    windows_proc_refusals: [MAX_WINDOWS_DYNAMIC_REFUSALS]WindowsDynamicRefusal =
        [_]WindowsDynamicRefusal{.{}} ** MAX_WINDOWS_DYNAMIC_REFUSALS,
    windows_proc_refusal_count: u32 = 0,
    windows_proc_refusal_events: u64 = 0,
    /// Names guest addresses for every diagnostic in this file. Installed by
    /// the PE loader when the image kept its COFF symbol table.
    guest_symbol_resolver: ?GuestSymbolResolver = null,
    /// Which part of the address space each guest address belongs to.
    ///
    /// The symbol resolver answers for the loaded image and declines for
    /// everything else, which is most of a running process. Three of the most
    /// important lines in the 2026-08-12 report were `at=<unnamed>` for
    /// addresses Rosette had itself laid down or watched the guest allocate.
    /// See `guest_address_space.zig`.
    guest_regions: guest_address_space.Map = .{},
    /// Resolved entry addresses for the milestone table, parallel to
    /// `xenia_guest_milestone_map.milestones`. Zero means the image does not
    /// contain that symbol, which is reported as `unresolved` rather than as
    /// "never reached".
    guest_milestone_addresses: [GUEST_MILESTONE_COUNT]u64 = [_]u64{0} ** GUEST_MILESTONE_COUNT,
    guest_milestone_hits: [GUEST_MILESTONE_COUNT]u64 = [_]u64{0} ** GUEST_MILESTONE_COUNT,
    /// Nonzero once a milestone has been recorded
    /// `GUEST_MILESTONE_TRANSLATOR_SATURATION` times and carries no hook
    /// beyond its record. Translated direct calls to it then stop leaving
    /// for the interpreter and only bump `guest_milestone_hits` in place, so
    /// the count stays exact while the caller, step and thread fields freeze
    /// at the call that saturated it.
    guest_milestone_saturated: [GUEST_MILESTONE_COUNT]u8 = [_]u8{0} ** GUEST_MILESTONE_COUNT,
    /// The step each milestone was first entered at, so a report can order
    /// them by when they actually happened rather than by table position.
    guest_milestone_first_step: [GUEST_MILESTONE_COUNT]u64 = [_]u64{0} ** GUEST_MILESTONE_COUNT,
    /// The step each milestone was last entered at.
    ///
    /// A first step says when something started; only the last one says
    /// whether it is still happening. `PPCFrontend::DefineFunction` is the
    /// case that needs it: a title translating new functions is walking
    /// through its own program, and the same count with a last step half a
    /// run ago is a title looping inside code it already has. Those are
    /// opposite conclusions from one number.
    guest_milestone_last_step: [GUEST_MILESTONE_COUNT]u64 = [_]u64{0} ** GUEST_MILESTONE_COUNT,
    /// Direct `call`/`jmp` sites in the image that branch to each milestone's
    /// entry, counted once at load by the PE reader.
    ///
    /// This is what separates "the guest never got here" from "the compiler
    /// left nothing to get to". An armed address with zero hits *and* zero
    /// call sites is an out-of-line body the optimizer inlined into its
    /// callers: unreachable by construction, so its zero is a fact about the
    /// build, not about the run. Without this column the 2026-09-12 run
    /// reported `display_clock_ticking` as the wall of the whole guest-output
    /// chain because `MarkVblank` had been inlined into the frame limiter.
    ///
    /// Zero also covers a symbol reached only indirectly - a virtual call, a
    /// `std::function` - so the caller pairs it with the hit count before
    /// concluding anything.
    guest_milestone_call_sites: [GUEST_MILESTONE_COUNT]u32 = [_]u32{0} ** GUEST_MILESTONE_COUNT,
    /// Places in the image's initialized data that store each milestone's
    /// address as a pointer - a vtable slot, a dispatch table, a callback
    /// registration.
    ///
    /// Without this column the call-site count means the wrong thing. A C++
    /// virtual function has no direct call site, so it looks identical to a
    /// body the optimizer deleted. The 2026-09-12 run made exactly that
    /// mistake about three symbols and turned two real chain findings into
    /// `unobservable`. Unreachable is *neither* branched to nor stored.
    guest_milestone_data_refs: [GUEST_MILESTONE_COUNT]u32 = [_]u32{0} ** GUEST_MILESTONE_COUNT,
    /// Who called each milestone, bounded to four callers per row.
    ///
    /// A witness row counts a superset of what it stands for.
    /// `EmulateCPInterruptDPC` is reached from four places in the image - the
    /// frame limiter's inlined vblank is one of them - so reading its total
    /// as a vblank count overstates the display rate, which is exactly what
    /// made the 2026-09-12 run appear to tick at 95 Hz against a limiter
    /// written for 60. Splitting by caller makes the row say which part of it
    /// is the vblank.
    guest_milestone_callers: [GUEST_MILESTONE_COUNT][GUEST_MILESTONE_CALLER_SLOTS]u64 =
        [_][GUEST_MILESTONE_CALLER_SLOTS]u64{[_]u64{0} ** GUEST_MILESTONE_CALLER_SLOTS} ** GUEST_MILESTONE_COUNT,
    guest_milestone_caller_hits: [GUEST_MILESTONE_COUNT][GUEST_MILESTONE_CALLER_SLOTS]u64 =
        [_][GUEST_MILESTONE_CALLER_SLOTS]u64{[_]u64{0} ** GUEST_MILESTONE_CALLER_SLOTS} ** GUEST_MILESTONE_COUNT,
    /// Entries whose caller did not fit the four slots, so a split that is
    /// incomplete never looks whole.
    guest_milestone_caller_overflow: [GUEST_MILESTONE_COUNT]u64 = [_]u64{0} ** GUEST_MILESTONE_COUNT,
    /// Whether the call-site census ran at all. A route that never calls
    /// `noteGuestMilestoneCallSites` has an all-zero column that must not be
    /// read as "every milestone was inlined away".
    guest_milestone_call_sites_counted: bool = false,
    /// A 64-bit membership filter over the armed addresses. Every guest call
    /// tests one bit; only a hit pays for the comparison loop. Without it
    /// this would be a linear scan on a path taken tens of millions of times
    /// per run, which is the mistake `rosette-hot-path-scan-rule` records.
    guest_milestone_filter_populated: bool = false,
    /// Filter bit -> milestone index + 1, or zero for empty and
    /// `milestone_slot_collision` when two armed addresses share a bit.
    ///
    /// The filter alone still cost a linear scan on every collision, and a
    /// run made about fifteen million of those. One byte per bit turns the
    /// common hit into a single comparison.
    guest_milestone_slot: [GUEST_MILESTONE_SLOTS]u8 = [_]u8{0} ** GUEST_MILESTONE_SLOTS,
    /// Every `xe::kernel::<module>::<Export>_entry` this image names, and how
    /// many times the guest entered each. See `kernel_call_census.zig`.
    guest_kernel_calls: kernel_call_census.Census = .{},
    /// Symbols offered to the census, so a run where the arming pass never
    /// ran is distinguishable from an image with no shims in it.
    guest_kernel_symbols_offered: u64 = 0,
    guest_milestones_armed: bool = false,
    guest_milestones_resolved: u32 = 0,
    /// Calls whose address passed the filter but matched no milestone. A
    /// filter that is mostly false positives is a filter worth rebuilding,
    /// and this is the number that says so.
    guest_milestone_filter_misses: u64 = 0,
    /// How much of the executable image the resolver can actually name, in
    /// percent. Reported so a run says whether "unnamed" means "no symbols"
    /// or "this one address".
    guest_symbol_coverage_percent: u32 = 0,
    guest_symbol_count: u32 = 0,
    /// Where the guest frontier has been, sampled at the graphics
    /// checkpoints. A single frontier reading says what the guest is doing
    /// now; the histogram says what it has spent the run doing, which is the
    /// difference between "it paused here" and "it has been here all along".
    guest_frontier_samples: u64 = 0,
    guest_frontier_workload_samples: [WORKLOAD_COUNT]u64 = [_]u64{0} ** WORKLOAD_COUNT,
    /// One owner-thread copy of the CRT's thread-local errno pointer. Worker
    /// copies live in `WindowsGuestThreadContext`; process-global CRT state
    /// lives in this bounded block so the path and exit tables have one
    /// authority.
    windows_crt_globals: WindowsCrtProcessGlobals = .{},
    /// A true unresolved export is a runtime contract violation. The switch
    /// exists only for controlled compatibility experiments; it never makes
    /// the host process fault or dereference a guest pointer.
    windows_capability_gaps_fatal: bool = true,
    windows_capability_gap_events: u64 = 0,
    windows_fmode_storage: u64 = 0,
    windows_commode_storage: u64 = 0,
    windows_acrt_iob_storage: [3]u64 = [_]u64{0} ** 3,
    windows_new_mode: u32 = 0,
    windows_invalid_parameter_handler: u64 = 0,
    windows_signal_handlers: [32]u64 = [_]u64{0} ** 32,
    windows_com_mta_cookie: u64 = 0,
    windows_com_mta_refcount: u32 = 0,
    windows_raw_input_registered: bool = false,
    windows_raw_input_device_count: u32 = 0,
    /// The processors the guest is told it has. One while every guest
    /// thread shares this host thread; the host's processors once the
    /// parallel executor gives each guest thread its own
    /// (`guestProcessorMask`). winpthreads counts the process mask for
    /// `std::thread::hardware_concurrency`, from which Xenia sizes its
    /// Vulkan pipeline-creation and shader-translation pools (3/4 of it).
    windows_process_affinity_mask: u64 = 1,
    windows_system_affinity_mask: u64 = 1,
    /// Lock-free published copies for read-only GetProcessAffinityMask calls.
    /// Writers publish after SetProcessAffinityMask and before guest workers
    /// enter parallel mode.
    windows_process_affinity_published: std.atomic.Value(u64) = .init(1),
    windows_system_affinity_published: std.atomic.Value(u64) = .init(1),
    windows_focus_window: u64 = 0,
    windows_vectored_exception_handler: u64 = 0,
    windows_vectored_exception_token: u64 = 0,
    // The PE C runtime asks for the active locale while parsing numeric
    // metadata (including the XEX container reached by Xenia's media path).
    // Keep the C-locale name, decimal point, empty fields, and lconv record
    // in guest memory so localeconv never returns a host pointer or a null
    // record that the CRT immediately dereferences.
    windows_locale_name: u64 = 0,
    windows_locale_decimal_point: u64 = 0,
    windows_locale_empty_string: u64 = 0,
    windows_localeconv_storage: u64 = 0,
    // UCRT time helpers return pointers to process/thread-local records and
    // strings. Keep those objects in guest memory; returning a host pointer
    // or a zero fallback makes the formatter dereference null and abort.
    windows_tm_storage: u64 = 0,
    windows_asctime_storage: u64 = 0,
    windows_import_calls: u64 = 0,
    /// A direct, pure time query can bypass the shared runtime lock in
    /// parallel execution. Keep its count separate and atomic so the lock's
    /// diagnostics remain honest and progress accounting still sees it.
    windows_fast_time_import_calls: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// memcpy, memmove and memset served on the lock-free C runtime lane
    /// (`fast_imports.tryCrtMemory`), by operation.
    windows_fast_crt_import_calls: [3]std.atomic.Value(u64) = @splat(std.atomic.Value(u64).init(0)),
    /// Read-only memcmp, strlen and strcmp calls answered from coordinated
    /// guest snapshots without entering the serialized import dispatcher.
    windows_fast_crt_string_import_calls: [4]std.atomic.Value(u64) = @splat(std.atomic.Value(u64).init(0)),
    /// CRT heap imports routed around general import lookup. Allocation
    /// metadata remains protected by the existing runtime mutation lock.
    windows_fast_heap_import_calls: [3]std.atomic.Value(u64) = @splat(std.atomic.Value(u64).init(0)),
    windows_heap_address_cache_hits: std.atomic.Value(u64) = .init(0),
    windows_heap_address_cache_misses: std.atomic.Value(u64) = .init(0),
    windows_fast_affinity_import_calls: std.atomic.Value(u64) = .init(0),
    windows_fast_sleep_zero_import_calls: std.atomic.Value(u64) = .init(0),
    /// QueryPerformanceCounter and QueryPerformanceFrequency served on the
    /// lock-free time lane, in that order.
    windows_fast_counter_import_calls: [2]std.atomic.Value(u64) = @splat(std.atomic.Value(u64).init(0)),
    windows_fast_time_imports_reported: u64 = 0,
    windows_unknown_import_calls: u64 = 0,
    windows_import_contract_calls: u64 = 0,
    windows_degraded_import_calls: u64 = 0,
    windows_import_abi_calls: u64 = 0,
    windows_import_abi_normal_returns: u64 = 0,
    windows_import_abi_nonlocal_returns: u64 = 0,
    windows_import_abi_clobber_calls: u64 = 0,
    windows_import_abi_gpr_clobbers: u64 = 0,
    windows_import_abi_xmm_clobbers: u64 = 0,
    windows_import_abi_repairs: u64 = 0,
    windows_vulkan_misaligned_stub_calls: u64 = 0,
    windows_vulkan_stub_repairs: u64 = 0,
    windows_callback_abi_calls: u64 = 0,
    windows_callback_abi_clobber_calls: u64 = 0,
    windows_callback_abi_gpr_clobbers: u64 = 0,
    windows_callback_abi_xmm_clobbers: u64 = 0,
    windows_callback_abi_repairs: u64 = 0,
    windows_iat_mismatches_at_fault: u64 = 0,
    // Which recognized-but-unimplemented imports this run actually took the
    // deterministic fallback for.  The preflight inventory can only list the
    // names that are *eligible*; this is the far smaller set the run depends
    // on, and it is what a degraded-import report is built from.
    windows_import_fallbacks: x64_linux_runtime.ImportFallbackLedger = .{},
    /// Every import whose *returned value* spelled failure in its own ABI,
    /// whoever produced it.
    ///
    /// `windows_import_fallbacks` records only the names that fell through to
    /// the generic contract path - the ones Rosette has not implemented. Most
    /// imports are answered by a hand-written handler, and a hand-written
    /// refusal was invisible unless someone remembered to record it. On the
    /// 2026-09-12 run that ledger held one line while roughly ninety thousand
    /// imports were answered, and when the guest reported a failure the log
    /// could not say what Rosette had told it.
    ///
    /// A refusal is a property of the value against the convention, not of
    /// the code path, so this is filled by classifying every answer.
    windows_import_refusals: x64_linux_runtime.ImportFallbackLedger = .{},
    /// Per-name convention lookups, cached by name pointer. Deriving a
    /// convention walks dozens of string comparisons; at ninety thousand
    /// calls that is the difference between free and measurable.
    windows_import_answer_cache: x64_linux_runtime.ImportAnswerCache = .{},
    /// Import answers classified, so a report can state its own coverage
    /// rather than implying the ledger is the whole story.
    /// A zero from a BOOL- or handle-returning import that reported no error
    /// code with it.
    ///
    /// Windows' own convention is that a failing BOOL sets `GetLastError`.
    /// A handler that answers FALSE and sets nothing is either giving an
    /// ordinary negative answer - `IsDebuggerPresent`, a search that found
    /// nothing - or refusing without saying why, and the two are
    /// indistinguishable from the value alone. That makes this list an audit
    /// rather than a finding, which is why it is kept apart from the
    /// refusals: mixing them would put `VirtualProtect` returning FALSE, a
    /// real defect, in the same paragraph as three hundred honest noes.
    windows_import_unexplained_zeros: x64_linux_runtime.ImportFallbackLedger = .{},
    windows_import_unexplained_events: u64 = 0,
    windows_import_answers_classified: u64 = 0,
    /// Answers whose name a per-DLL package declares. The rest are answered
    /// for libraries whose ABI nobody has written down, and the report says
    /// so rather than implying the whole surface is covered.
    windows_import_answers_declared: u64 = 0,
    /// State for `rand_s`, which the CRT requires to be non-deterministic.
    /// Seeded from the guest clock at first use rather than from a constant,
    /// because a fixed sequence is exactly what a caller of `rand_s` is
    /// trying to avoid.
    windows_random_state: u64 = 0x9E3779B97F4A7C15,
    /// The process error mode `SetErrorMode` reports back. Remembered
    /// because the API returns the previous value, and a caller that saves
    /// and restores it corrupts its own state if the save reads a constant.
    windows_error_mode: u32 = 0,
    windows_debug_strings: u64 = 0,
    /// Guest memory backing the CRT's timezone globals and `gmtime`'s static
    /// result. Allocated on first use rather than at start-up, so a run that
    /// never asks for a calendar pays nothing for one.
    windows_timezone_block: u64 = 0,
    windows_static_tm: u64 = 0,
    /// Counter behind `RegisterWindowMessage`, so two different strings never
    /// get the same private message id.
    windows_next_window_message: u64 = 0,
    /// Answers whose convention the contract assigns by a name-shaped guess
    /// rather than an explicit rule, so the value cannot be judged. Counted
    /// and stated, because a report that silently skipped them would imply a
    /// coverage it does not have.
    windows_import_answers_unjudged: u64 = 0,
    windows_import_refusal_events: u64 = 0,
    windows_next_handle: u64 = 0xFFFF_F000_0000_0001,
    // The one virtual display Rosetta presents.  Allocated lazily so it uses
    // the same handle space as every other Win32 object, and then stable: a
    // guest comparing "the monitor my window is on" against a cached value
    // must not see it change on every query.
    windows_primary_monitor: u64 = 0,
    windows_next_stdio_fd: u32 = 3,
    windows_next_tls: u32 = 0,
    windows_main_teb: u64 = 0,
    windows_process_peb: u64 = 0,
    windows_next_thread_id: u64 = 2,
    windows_file_mappings: [MAX_WINDOWS_FILE_MAPPINGS]WindowsFileMapping = [_]WindowsFileMapping{.{}} ** MAX_WINDOWS_FILE_MAPPINGS,
    /// High-water marks for the bounded Windows tables. The arrays remain
    /// fixed-size so guest handles and view indexes stay deterministic, but
    /// ordinary lookup paths need not scan the unused tail of each table.
    windows_file_mapping_count: usize = 0,
    windows_memory_views: [MAX_WINDOWS_MEMORY_VIEWS]WindowsMemoryView = [_]WindowsMemoryView{.{}} ** MAX_WINDOWS_MEMORY_VIEWS,
    windows_memory_view_count: usize = 0,
    windows_virtual_allocations: [MAX_WINDOWS_VIRTUAL_ALLOCATIONS]WindowsVirtualAllocation = [_]WindowsVirtualAllocation{.{}} ** MAX_WINDOWS_VIRTUAL_ALLOCATIONS,
    windows_virtual_allocation_count: usize = 0,
    windows_mapped_ranges: mapped_ranges.Index = .{},
    native_memory_aliases: [256]NativeMemoryAlias = @splat(.{}),
    native_memory_alias_count: usize = 0,
    native_memory_alias_next: u64 = native_alias_address_base,
    /// Executable PE sections and a generation invalidated only by writes
    /// that overlap one of them.  Data writes therefore do not evict the
    /// image's decode cache, while self-modifying code still does.
    windows_executable_ranges: [MAX_WINDOWS_EXECUTABLE_RANGES]WindowsExecutableRange = [_]WindowsExecutableRange{.{}} ** MAX_WINDOWS_EXECUTABLE_RANGES,
    windows_executable_range_count: usize = 0,
    windows_image_code_generation: u64 = 1,
    /// One generation word per page of mapped code, keyed by the page's
    /// position in its mapping's backing (Xenia writes its code cache
    /// through one view and runs it through another). A translated block
    /// of mapped code checks the word of the page it starts on; a write
    /// bumps the words of the pages it touches and of the page before the
    /// first, where a block may start and run onto it. The mapping-wide
    /// `code_generation` still moves for the decode cache, but it no longer
    /// invalidates every translated block and chain link in the code
    /// cache on each store Xenia makes to place one new function: 1.6
    /// million of those on 2026-10-01. Hashed, so two pages can share a
    /// word, which costs only a spurious revalidation. Empty until the
    /// first mapped block compiles in serial mode or the PE loader
    /// allocates it before workers start.
    code_page_generations: []u64 = &.{},
    /// Every Windows import call by name, for the exit report: allocated at
    /// PE load, before any worker can count into it.
    windows_import_histogram: ?*import_histogram.Histogram = null,
    /// Bounded bring-up witness for unexpected writes to PE executable
    /// sections. A changed call opcode must be tied to its writer before we
    /// can safely decide whether it is a TSO visibility or memory-corruption
    /// defect.
    windows_executable_image_write_events: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    /// Xenia's x64 code cache is always published at 0xA0000000. Remember
    /// its view so instruction fetches do not walk every ordinary mapping on
    /// each interpreter step.
    windows_code_cache_view: ?usize = null,
    /// Published bounds for the dedicated Xenia generated-code mapping.
    /// `block_jit.zig` checks these inline for indirect transfers, avoiding
    /// a C callback on the common case while preserving that callback for
    /// every other external target.
    block_jit_code_cache_guest_low: u64 = 0,
    block_jit_code_cache_guest_high: u64 = 0,
    windows_generated_code_fetches: u64 = 0,
    windows_title_code_fetches: u64 = 0,
    windows_heap_allocations: []WindowsHeapAllocation = &.{},
    windows_heap_allocation_count: usize = 0,
    windows_heap_free_indices: []usize = &.{},
    windows_heap_free_count: usize = 0,
    /// Records whose block is currently live.
    ///
    /// The record count grows monotonically because a freed record remains a
    /// tombstone for address-ordered lookup, while exact freed blocks are
    /// available through `windows_heap_free_indices`. This is the number that
    /// answers the live-object question.
    windows_heap_allocations_live: usize = 0,
    // Allocation records remain address ordered, including freed tombstones,
    // because realloc/free validation uses a binary search. The separate free
    // index list permits exact physical reuse without changing that ordering.
    windows_heap_provenance_growth_failures: u64 = 0,
    windows_heap_provenance_untracked_allocations: u64 = 0,
    windows_heap_reused_allocations: u64 = 0,
    windows_heap_free_list_growth_failures: u64 = 0,
    /// Freed blocks not yet reusable, as a ring of record indices.
    windows_heap_quarantine: []usize = &.{},
    windows_heap_quarantine_head: usize = 0,
    windows_heap_quarantine_len: usize = 0,
    windows_heap_quarantine_bytes: u64 = 0,
    windows_heap_quarantine_limit_blocks: usize = WINDOWS_HEAP_QUARANTINE_BLOCKS,
    windows_heap_quarantine_limit_bytes: u64 = WINDOWS_HEAP_QUARANTINE_BYTES,
    /// Reusable blocks by exact length.
    windows_heap_bins: std.AutoHashMapUnmanaged(u64, WindowsHeapBin) = .empty,
    windows_heap_binned: usize = 0,
    /// A free of a block that is already free: the second free is refused,
    /// which is what keeps it from releasing the next owner's block.
    windows_heap_double_frees: u64 = 0,
    /// Guard bytes after every guest heap block (`diagnostics/heap_guard.zig`);
    /// `ROSETTE_PE64_HEAP_GUARD=0` turns them off.
    windows_heap_guard_bytes: u64 = heap_guard.default_guard_bytes,
    /// Blocks found written past their end when freed.
    windows_heap_overruns: u64 = 0,
    /// `ROSETTE_PE64_CALL_PROBE`: named functions whose calls are logged
    /// with their arguments and results (`diagnostics/call_probe.zig`).
    call_probes: call_probe.ProbeSet = .{},
    /// A free of an address no allocation starts at.
    windows_heap_unknown_frees: u64 = 0,
    windows_heap_bytes_live: u64 = 0,
    windows_heap_bytes_peak: u64 = 0,
    /// Bytes deliberately left uninitialized for the CRT's malloc family.
    /// C malloc does not promise zero-filled storage; calloc and Rosette's
    /// internal guestAlloc contract still do.
    windows_heap_zero_fill_bytes: u64 = 0,
    windows_heap_zero_fill_avoided_bytes: u64 = 0,
    /// User APCs queued to the owner context (the process's first thread).
    windows_owner_apc: WindowsApcQueue = .{},
    windows_apcs_queued: u64 = 0,
    windows_apcs_delivered: u64 = 0,
    windows_apc_wakes: u64 = 0,
    windows_apc_refusals: u64 = 0,
    windows_stack_overflows: u64 = 0,
    // MapViewOfFile without an address hint gets a deterministic guest-only
    // placement outside the PE image.  Fixed Xenia views retain their exact
    // requested address and never consume this cursor.
    windows_next_memory_view_base: u64 = 0x0000_4000_0000_0000,
    // PE static TLS and Win32 dynamic TLS share the TEB vector but are not
    // the same namespace in the image contract.  Keep the module slot and
    // its initialized template separate from TlsAlloc's next dynamic slot so
    // the CRT's pthread record can never be mistaken for static TLS storage.
    windows_static_tls_index: ?u32 = null,
    windows_static_tls_template_start: u64 = 0,
    windows_static_tls_template_length: u64 = 0,
    windows_static_tls_block_bytes: u64 = WINDOWS_TLS_BLOCK_BYTES,
    windows_command_line_a: u64 = 0,
    windows_command_line_w: u64 = 0,
    // Command-line arguments are supplied by the PE runner as host-owned
    // byte slices, then materialized into guest memory by the Windows ABI
    // bridge. Keeping the source slices here avoids manufacturing a second
    // argv authority inside the executor.
    windows_launch_arguments: []const []const u8 = &.{},
    windows_host_media_path: ?[]const u8 = null,
    // The MinGW startup helpers return pointers to CRT-owned globals rather
    // than the strings themselves. Keep both levels in guest memory so
    // __wgetmainargs/__getmainargs can publish a real argc/argv/environ
    // contract to wmain without exposing a host pointer.
    windows_argc_storage: u64 = 0,
    windows_argv_a: u64 = 0,
    windows_argv_w: u64 = 0,
    windows_argv_a_storage: u64 = 0,
    windows_argv_w_storage: u64 = 0,
    windows_environ_a: u64 = 0,
    windows_environ_w: u64 = 0,
    windows_environ_a_storage: u64 = 0,
    windows_environ_w_storage: u64 = 0,
    windows_wcmdln_storage: u64 = 0,
    windows_entry_point: u64 = 0,
    windows_window_handle: u64 = 0,
    windows_host_io: ?std.Io = null,
    windows_host_working_directory: ?[]const u8 = null,
    windows_files: [MAX_WINDOWS_FILE_HANDLES]WindowsFileSlot = [_]WindowsFileSlot{.{}} ** MAX_WINDOWS_FILE_HANDLES,
    windows_finds: [MAX_WINDOWS_FIND_HANDLES]WindowsFindSlot = [_]WindowsFindSlot{.{}} ** MAX_WINDOWS_FIND_HANDLES,
    windows_volume_finds: [MAX_WINDOWS_VOLUME_HANDLES]WindowsVolumeFindSlot = [_]WindowsVolumeFindSlot{.{}} ** MAX_WINDOWS_VOLUME_HANDLES,
    windows_initterm_frames: [MAX_WINDOWS_INITTERM_FRAMES]WindowsInitTermFrame = [_]WindowsInitTermFrame{.{
        .begin = 0,
        .end = 0,
        .return_rip = 0,
        .return_is_direct = false,
        .returns_error = false,
    }} ** MAX_WINDOWS_INITTERM_FRAMES,
    windows_initterm_frame_count: usize = 0,
    windows_qsort_frames: [MAX_WINDOWS_QSORT_FRAMES]WindowsQsortFrame = [_]WindowsQsortFrame{.{}} ** MAX_WINDOWS_QSORT_FRAMES,
    windows_qsort_frame_count: usize = 0,
    // Windows PE execution is hosted by one interpreter thread, but the
    // image may create real worker entry points before the UI loop starts.
    // These slots are the bounded guest scheduler for those entry points.
    windows_guest_threads: []WindowsGuestThread = &.{},
    xbox_critical_section_hooks: xbox_critical_section.Hooks = .{},
    /// Stable per-slot TLB ownership, kept separate from mutable guest
    /// thread records so slot recycling cannot lose a host allocation.
    windows_guest_thread_tlbs: [MAX_WINDOWS_GUEST_THREADS]?*block_jit.Tlb = @splat(null),
    windows_srw_locks: [MAX_WINDOWS_SRW_LOCKS]WindowsSrwLock = [_]WindowsSrwLock{.{}} ** MAX_WINDOWS_SRW_LOCKS,
    windows_srw_lock_index: WindowsSrwLockIndex = .{},
    /// Diagnostic stack scans are sampled; lock ownership is always tracked.
    windows_srw_stack_capture_all: bool = false,
    windows_srw_stack_captures: u64 = 0,
    windows_srw_stack_skipped: u64 = 0,
    windows_srw_import_lane: bool = true,
    windows_srw_fast_acquires: std.atomic.Value(u64) = .init(0),
    windows_srw_fast_releases: std.atomic.Value(u64) = .init(0),
    /// Held or contended CRITICAL_SECTIONs (`enterWindowsCriticalSection`).
    windows_critical_sections: [MAX_WINDOWS_CRITICAL_SECTIONS]WindowsSrwLock = [_]WindowsSrwLock{.{}} ** MAX_WINDOWS_CRITICAL_SECTIONS,
    windows_critical_section_enters: u64 = 0,
    windows_critical_section_contentions: u64 = 0,
    windows_critical_section_handoffs: u64 = 0,
    windows_critical_section_high_water: usize = 0,
    /// Enters that got no record - a full table or an unreadable section -
    /// and so ran without exclusion, as every enter used to.
    windows_critical_section_untracked: u64 = 0,
    windows_critical_section_release_mismatches: u64 = 0,
    /// The Xbox critical-section bridge (`handleXboxCriticalSectionExport`).
    /// Its fast paths run without the runtime lock; every counter is atomic.
    xbox_critical_section_stats: xbox_critical_section.Stats = .{},
    /// The owner context's counted Xbox critical-section wait, across the
    /// retries of its call; see `WindowsGuestThread.xbox_cs_wait`.
    owner_xbox_cs_wait: u64 = 0,
    owner_xbox_cs_granted: bool = false,
    owner_xbox_cs_sequence: u64 = 0,
    /// Native CONDITION_VARIABLE waits (`SleepConditionVariableCS/SRW`) that
    /// released their lock and slept, resumed with it retaken, timed out,
    /// and those left to the old immediate-FALSE answer.
    windows_native_condition_waits: u64 = 0,
    windows_native_condition_resumes: u64 = 0,
    windows_native_condition_timeouts: u64 = 0,
    windows_native_condition_unmodelled: u64 = 0,
    /// The owner's native condition wait (parallel mode), across the
    /// retries of its call.
    owner_native_condition: u64 = 0,
    owner_native_condition_lock: u64 = 0,
    owner_native_condition_kind: NativeConditionLock = .none,
    owner_native_condition_recursion: u32 = 0,
    owner_native_condition_deadline_ns: u64 = 0,
    owner_native_condition_signaled: bool = false,
    owner_native_condition_timed_out: bool = false,
    /// The owner's winpthreads condition wait (parallel mode), across the
    /// retries of its call: the condition, the mutex it gave up, the guest
    /// clock deadline, and how it ended.
    owner_pthread_condition: u64 = 0,
    owner_pthread_condition_mutex: u64 = 0,
    owner_pthread_condition_deadline: u64 = 0,
    owner_pthread_condition_signaled: bool = false,
    owner_pthread_condition_timed_out: bool = false,
    owner_pthread_condition_mutex_contended: bool = false,
    windows_owner_condition_waits: u64 = 0,
    /// The handle the owner's current handle wait is on, for the pulse.
    owner_wait_handle: u64 = 0,
    windows_srw_wait_sequence: u64 = 0,
    /// Releases that handed the lock straight to a waiter. See
    /// `handOffWindowsSrwLock`.
    windows_srw_handoffs: u64 = 0,
    /// Xenia's global critical region, resolved from the image's symbols.
    xenia_global_mutex_address: ?u64 = null,
    /// Back-offs that lent the global mutex out, and the lends taken back.
    xenia_global_mutex_lends: u64 = 0,
    xenia_global_mutex_lend_returns: u64 = 0,
    /// Census exports whose hook left the translator's filter.
    guest_kernel_census_saturations: u32 = 0,
    /// Guest-thread names mapped to host QoS classes (`hostQosForGuestThread`).
    host_thread_qos_enabled: bool = true,
    host_thread_qos_applied: u32 = 0,
    /// Protection the guest asked for, enforced on interpreted memory
    /// operands. See `guest_page_protection.zig`.
    guest_page_protection: guest_page_protection.Table = .{},
    guest_page_protection_guard_requests: u64 = 0,
    guest_page_protection_unmodelled_values: u64 = 0,
    guest_page_protection_restrict_events: u32 = 0,
    guest_access_violation_pending: bool = false,
    guest_access_violation: GuestAccessViolation = .{},
    guest_exception_dispatches_in_flight: u32 = 0,
    guest_access_violations_raised: u64 = 0,
    /// Host-side mutable borrows of guest memory that overlapped a protected
    /// page (see `noteProtectedBulkBorrow`).
    guest_protected_bulk_borrows: u64 = 0,
    guest_protected_bulk_borrow_bytes: u64 = 0,
    guest_protected_bulk_borrow_reports: u8 = 0,
    guest_access_violation_reads: u64 = 0,
    guest_access_violation_writes: u64 = 0,
    guest_access_violations_dispatched: u64 = 0,
    guest_access_violations_handled: u64 = 0,
    guest_access_violations_unhandled: u64 = 0,
    guest_access_violations_without_handler: u64 = 0,
    guest_access_violations_frame_refused: u64 = 0,
    guest_access_violations_nesting_refused: u64 = 0,
    guest_access_violation_sites: [GUEST_ACCESS_VIOLATION_SITE_CAPACITY]GuestAccessViolationSite = [_]GuestAccessViolationSite{.{}} ** GUEST_ACCESS_VIOLATION_SITE_CAPACITY,
    guest_access_violation_site_count: usize = 0,
    guest_access_violation_site_overflow: u64 = 0,
    /// Faults the guest handler said to retry without clearing the protection
    /// that caused them. Each one would have been an unbreakable loop.
    guest_access_violation_unresolved_retries: u64 = 0,
    xma_registers: GuestXmaRegisterCensus = .{},
    frame_cost: GuestFrameCost = .{},
    gpu_front_buffer: GuestFrontBuffer = .{},
    /// The ring and the VdSwap shim are observed on separate guest edges.  A
    /// swap can therefore be entered before the indirect buffer containing its
    /// fetch constant is readable.  Keep the last successful handoff so the
    /// checkpoint retry is cheap and a single swap cannot repaint forever.
    guest_frontbuffer_last_handoff_swap: u64 = 0,
    guest_frontbuffer_last_handoff_attempt_swap: u64 = 0,
    guest_frontbuffer_last_handoff_attempt_step: u64 = 0,
    guest_frontbuffer_handoff_attempts: u64 = 0,
    guest_frontbuffer_handoff_successes: u64 = 0,
    guest_frontbuffer_handoff_failures: u64 = 0,
    windows_wait_objects: [MAX_WINDOWS_WAIT_OBJECTS]WindowsWaitObject = [_]WindowsWaitObject{.{}} ** MAX_WINDOWS_WAIT_OBJECTS,
    windows_active_guest_thread_slot: ?usize = null,
    /// Bound while the memory-aware cross-check interprets a block: stores
    /// land in it instead of memory (`diagnostics/block_verify_journal.zig`).
    verify_journal: ?*block_verify.Journal = null,
    windows_last_serviced_guest_thread_slot: ?usize = null,
    windows_last_service_owner_step: ?u64 = null,
    // The owner context can also enter an infinite Win32 wait.  Keep the
    // import RIP in place and let the outer cooperative loop service workers
    // until the object becomes ready, just as it does for a blocked worker.
    windows_main_wait_handle: u64 = 0,
    windows_thread_service_calls: u64 = 0,
    windows_thread_service_steps: u64 = 0,
    windows_thread_yields: u64 = 0,
    windows_thread_blocks: u64 = 0,
    windows_thread_unblocks: u64 = 0,
    windows_thread_completions: u64 = 0,
    windows_thread_failures: u64 = 0,
    /// Worker slices that changed the process owner's register file; see
    /// `diagnostics/context_integrity.zig`. Must stay zero.
    owner_context_violations: u64 = 0,
    /// `ROSETTE_PE64_CONTEXT_AUDIT=step`: compare the owner's register file
    /// after every worker instruction, so the first violation names the
    /// instruction that caused it rather than only its slice.
    owner_context_audit_steps: bool = false,
    owner_context_step_violations: u64 = 0,
    windows_gpu_write_pointer_wake_repairs: u64 = 0,
    windows_gpu_write_pointer_wake_repair_misses: u64 = 0,
    /// Return-value captures outstanding across every thread. The `ret` arm
    /// tests this first, so it costs one comparison when nothing is armed.
    guest_return_captures_armed: u32 = 0,
    owner_return_capture: GuestReturnCapture = .{},
    guest_return_captures_completed: u64 = 0,
    guest_return_captures_replaced: u64 = 0,
    xenia_setup_trace: XeniaSetupTrace = .{},
    xenia_ui_deferred_returns: u64 = 0,
    xenia_ui_deferred_last_accepted: bool = false,
    ui_evidence: ui_draw_evidence.Evidence = .{},
    /// Xenos registers the title reached through Xenia's MMIO thunks.
    gpu_register_traffic: [GPU_REGISTER_TRAFFIC_CAPACITY]GpuRegisterTraffic = [_]GpuRegisterTraffic{.{}} ** GPU_REGISTER_TRAFFIC_CAPACITY,
    gpu_register_traffic_count: usize = 0,
    gpu_register_traffic_overflow: u64 = 0,
    gpu_register_last_slot: usize = 0,
    gpu_register_reads: u64 = 0,
    gpu_register_writes: u64 = 0,
    /// The command ring, as the title described it to `VdInitializeRingBuffer`.
    gpu_ring_base: u32 = 0,
    gpu_ring_size_log2: u32 = 0,
    gpu_ring_initialized: bool = false,
    gpu_ring_rptr_writeback: u32 = 0,
    gpu_ring_last_write_index: u32 = 0,
    gpu_ring_updates: u64 = 0,
    gpu_stall_last_snapshot: ?gpu_stall.Snapshot = null,
    gpu_ring_windows: [GPU_RING_WINDOW_CAPACITY]GpuRingWindow = [_]GpuRingWindow{.{}} ** GPU_RING_WINDOW_CAPACITY,
    gpu_ring_window_count: usize = 0,
    gpu_ring_unreadable_updates: u64 = 0,
    gpu_ring_dwords_decoded: u64 = 0,
    gpu_ring_zero_dwords: u64 = 0,
    gpu_ring_type0_packets: u64 = 0,
    gpu_ring_type3_packets: u64 = 0,
    gpu_ring_alias_mismatches: u64 = 0,
    /// Paths Xenia's virtual file system was asked to resolve.
    guest_vfs_resolves: [GUEST_VFS_RESOLVE_CAPACITY]GuestVfsResolve = [_]GuestVfsResolve{.{}} ** GUEST_VFS_RESOLVE_CAPACITY,
    guest_vfs_resolve_count: usize = 0,
    guest_vfs_resolve_calls: u64 = 0,
    guest_vfs_resolve_not_found: u64 = 0,
    guest_vfs_resolve_overflow: u64 = 0,
    guest_vfs_resolve_unreadable: u64 = 0,
    /// Whether the PCM the title hands `AudioSystem::SubmitFrame` is silence.
    audio_title_frames_seen: u64 = 0,
    audio_title_frames_checked: u64 = 0,
    audio_title_frames_nonzero: u64 = 0,
    audio_title_first_nonzero_step: u64 = 0,
    /// SRW releases whose new owner was scheduled next.
    windows_srw_directed_handoffs: u64 = 0,
    windows_preferred_next_guest_thread: ?usize = null,
    windows_audio_pacing_waits: u64 = 0,
    windows_audio_pacing_wait_ms: u64 = 0,
    /// The registry the guest owns. See `windows_registry.zig`.
    windows_registry: windows_registry_model.Registry = .{},
    windows_srw_lock_contentions: u64 = 0,
    windows_srw_lock_release_mismatches: u64 = 0,
    windows_wait_calls: u64 = 0,
    windows_wait_blocks: u64 = 0,
    windows_wait_resumes: u64 = 0,
    windows_wait_unblocks: u64 = 0,
    windows_wait_timeouts: u64 = 0,
    /// Per-wait duration, timeout overshoot, and signal accounting. The
    /// legacy counters above remain cheap scheduler counters; this ledger is
    /// the bounded evidence needed to identify a poll that consumed the run.
    windows_wait_cost: wait_cost.Ledger = .{},
    /// One-shot forensic triggers emitted from the bounded wait ledger. They
    /// are counters rather than booleans because a condition can be resolved
    /// and later become a new episode, while a timeout hotspot is reported
    /// once for the lifetime of the run.
    windows_wait_unsignalled_escalations: u64 = 0,
    windows_wait_timeout_hotspot_escalations: u64 = 0,
    windows_wait_unknown_objects: u64 = 0,
    windows_wait_trace_events: u64 = 0,
    windows_wait_registration_trace_events: u64 = 0,
    windows_thread_queue_trace_events: u64 = 0,
    windows_wait_last_owner_service_steps: u64 = 0,
    windows_wait_signal_trace_events: u64 = 0,
    windows_wait_owner_yields: u64 = 0,
    /// `WaitForMultipleObjects` calls, parks, and owner-context turns.
    windows_wait_multiple_calls: u64 = 0,
    windows_wait_multiple_blocks: u64 = 0,
    windows_wait_multiple_owner_yields: u64 = 0,
    /// Waits on a handle with no object behind it; each is a fatal point.
    windows_wait_unknown_faults: u64 = 0,
    /// C runtime imports handed a pointer Rosette could not read.
    windows_crt_unreadable_pointers: u64 = 0,
    /// Worker turns an idle `GetMessage` served, and their steps.
    windows_get_message_idle_turns: u64 = 0,
    /// Moves whenever a message is queued, a window gains a pending paint or
    /// a quit is requested: what a blocked GetMessage sleeps on.
    windows_message_event: concurrency.EpochEvent = concurrency.EpochEvent.init("GetMessage: waiting for a message"),
    /// GetMessage calls that blocked (parallel mode), and for how long.
    windows_get_message_blocks: u64 = 0,
    windows_get_message_block_ns: u64 = 0,
    /// How an empty GetMessage resumed: a guest notification or the bounded
    /// poll that services native host-window events and guest wait deadlines.
    windows_get_message_event_wakes: u64 = 0,
    windows_get_message_host_polls: u64 = 0,
    /// Empty GetMessage calls that could not block because the calling
    /// thread held the runtime lock in a pinned critical section (or not at
    /// all), with the lock depths the first one saw. Every one of these is
    /// a WM_NULL lap of the guest's message loop.
    /// When `runWithLimit` began (monotonic ns), for `t_ms=` timestamps.
    run_started_ns: u64 = 0,
    /// Parallel-mode sleeps of guest waits (`parkForGuestWait`), their total
    /// time, and the ones refused because a pinned lock level was held.
    windows_guest_wait_parks: u64 = 0,
    windows_guest_wait_park_ns: u64 = 0,
    windows_guest_wait_park_refusals: u64 = 0,
    /// The owner's parallel-mode handle waits (`ownerParallelWait`): how many,
    /// their slices, and their total and longest time.
    windows_owner_waits: u64 = 0,
    /// Owner `Sleep(n)` calls that really slept (parallel mode).
    windows_owner_sleeps: u64 = 0,
    windows_owner_wait_retries: u64 = 0,
    windows_owner_wait_ns: u64 = 0,
    windows_owner_wait_longest_ns: u64 = 0,
    /// The wait the owner is in the middle of, across its retries.
    owner_wait_key: u64 = 0,
    owner_wait_deadline_ns: u64 = 0,
    owner_wait_started_ns: u64 = 0,
    windows_get_message_unreleasable: u64 = 0,
    windows_get_message_unreleasable_depth: usize = 0,
    windows_get_message_unreleasable_pinned: usize = 0,
    /// Long native Vulkan pipeline compilation can monopolize the shared
    /// Windows runtime lock even though its complete create-info graph has
    /// already been copied into host-owned scratch. These counters record
    /// dispatch-only lock yields around those driver calls.
    runtime_lock_native_pipeline_yields: u64 = 0,
    runtime_lock_native_pipeline_yield_ns: u64 = 0,
    runtime_lock_native_pipeline_yield_refusals: u64 = 0,
    /// Vulkan fence waits block until GPU completion (or timeout/device loss).
    /// When this path yields a dispatch-only runtime lock, other guest CPU
    /// contexts can continue while the host driver waits for the device.
    runtime_lock_gpu_fence_wait_yields: u64 = 0,
    runtime_lock_gpu_fence_wait_yield_ns: u64 = 0,
    runtime_lock_gpu_fence_wait_yield_refusals: u64 = 0,
    runtime_lock_gpu_queue_wait_yields: u64 = 0,
    runtime_lock_gpu_queue_wait_yield_ns: u64 = 0,
    runtime_lock_gpu_queue_wait_yield_refusals: u64 = 0,
    windows_get_message_idle_steps: u64 = 0,
    /// Which runtime calls held the runtime lock, and for how long (parallel
    /// mode; updated under the lock). `PE64 RUNTIME LOCK HOLDS`.
    runtime_lock_ledger: parallel_diagnostics.lock_holds.Ledger = .{},
    /// The process owner's registers as it left its last step, compared as
    /// it begins the next (parallel mode, owner thread only).
    owner_register_tripwire: parallel_diagnostics.register_tripwire.Tripwire = .{},
    /// Register-file writes some other host thread made to a guest thread's
    /// context between two of its steps, owner and workers together, and
    /// the first one's details for the exit summary. `PE64 CONTEXT RACE`.
    context_race_findings: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    context_race_first_thread: u64 = 0,
    context_race_first_expected_rip: u64 = 0,
    context_race_first_found_rip: u64 = 0,
    context_race_first_holder: u64 = 0,
    /// The watchdog thread's own state for `PE64 THREAD PULSE`: nothing
    /// else reads or writes these.
    thread_pulse_memory: parallel_diagnostics.thread_pulse.Memory = .{},
    thread_pulse_policy: parallel_diagnostics.thread_pulse.Policy = .{},
    thread_pulse_lines: u64 = 0,
    thread_pulse_guest_steps: [MAX_WINDOWS_GUEST_THREADS]u64 = @splat(0),
    /// Where timed condition waits come from. `deadline_timeouts=1411` said
    /// how many timed out and nothing about whose they were.
    windows_timed_wait_sites: [WINDOWS_TIMED_WAIT_SITE_CAPACITY]WindowsTimedWaitSite = [_]WindowsTimedWaitSite{.{}} ** WINDOWS_TIMED_WAIT_SITE_CAPACITY,
    windows_timed_wait_site_count: usize = 0,
    windows_timed_wait_site_overflow: u64 = 0,
    windows_file_table_full: u64 = 0,
    windows_file_mapping_table_full: u64 = 0,
    /// The registers of the worker that faulted, captured before the
    /// scheduler restores the owner context. EXIT DIAGNOSTICS used to print
    /// the owner's state beside the worker's decode result: on 2026-09-14 it
    /// named `mov ebx, eax` in the message loop for a fault in JIT code.
    exit_fault_regs: ?ElfRegs = null,
    exit_fault_thread_slot: ?usize = null,
    exit_fault_op: ?Op = null,
    exit_fault_len: ?u8 = null,
    parallel_fault_snapshot: ParallelFaultSnapshot = .{},
    windows_xmutant_release_compat_calls: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    windows_xmutant_stale_backing_deletes_skipped: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Worker instructions, counted as each one executes. The per-thread
    /// counters go when a finished thread's slot is reused, and the
    /// scheduler's slice totals miss every turn served from a wait, a sleep or
    /// an idle GetMessage; this is the denominator every share is taken from.
    windows_worker_executed_steps: u64 = 0,
    /// `pthread_cond_timedwait_impl`, found by signature like the untimed
    /// condition entries.
    windows_pthread_cond_timedwait_entry: ?u64 = null,
    windows_condition_timed_waits: u64 = 0,
    windows_condition_timed_immediate: u64 = 0,
    windows_condition_timeouts: u64 = 0,
    windows_condition_timeout_samples: u8 = 0,
    /// Waitable timers. CreateWaitableTimer used to hand back a handle no
    /// wait table knew, so every wait on it answered STATUS_INVALID_HANDLE
    /// at once: the 2026-09-14 run made 36,978 of them from
    /// xe::threading::Wait, which is how a title's KeSetTimer reaches Win32.
    windows_timers_created: u64 = 0,
    windows_timer_sets: u64 = 0,
    windows_timer_fires: u64 = 0,
    windows_timer_completion_routines: u64 = 0,
    windows_armed_timers: u32 = 0,
    windows_next_timer_due: u64 = std.math.maxInt(u64),
    /// Stacks returned to the guest heap when their thread finished, not
    /// when its slot was next reused.
    windows_thread_stacks_released: u64 = 0,
    /// Worker slices that repeated an exact machine state with no kernel call,
    /// and the scheduling turns spinning threads gave away because of it.
    windows_spin_slices: u64 = 0,
    windows_spin_turns_given: u64 = 0,
    windows_nt_delay_parks: u64 = 0,
    windows_nt_delay_yields: u64 = 0,
    windows_slice_clock_reads: u32 = 0,
    windows_clock_poll_yields: u64 = 0,
    /// One past the highest wait-object slot in use: lookups scan this far.
    windows_wait_object_high_water: usize = 0,
    windows_wait_objects_freed: u64 = 0,
    windows_wait_object_table_full: u64 = 0,
    windows_thread_slots_recycled: u64 = 0,
    windows_thread_table_full: u64 = 0,
    run_next_heartbeat_instructions: u64 = WINDOWS_RUN_HEARTBEAT_INSTRUCTIONS,
    run_heartbeats: u64 = 0,
    // Some Xenia startup workers use Win32 waits as a scheduling boundary,
    // not as a dependency on a host-side resource. The compatibility mode
    // preserves the historical cooperative behavior for those boundaries;
    // strict signal/deadline waits remain available for diagnosis.
    windows_guest_wait_compatibility: bool = false,
    windows_wait_compatibility_yields: u64 = 0,
    windows_srw_compatibility_acquires: u64 = 0,
    windows_nt_sync_trace_events: u64 = 0,
    windows_ui_quit_requested: bool = false,
    windows_ui_quit_code: u64 = 0,
    windows_scheduler: WindowsGuestSchedulerPolicy = .{},
    windows_progress: WindowsProgressWatchdog = .{},
    // Win32 class/window/message state is guest-owned and bounded.  These
    // records are enough for Xenia's UI shell while keeping message delivery
    // deterministic and preventing a malformed PE from growing host memory.
    windows_window_classes: [MAX_WINDOWS_WINDOW_CLASSES]WindowsWindowClass = [_]WindowsWindowClass{.{}} ** MAX_WINDOWS_WINDOW_CLASSES,
    windows_next_window_class_atom: u16 = 1,
    windows_windows: [MAX_WINDOWS_WINDOWS]WindowsWindow = [_]WindowsWindow{.{}} ** MAX_WINDOWS_WINDOWS,
    windows_message_window_handle: u64 = 0,
    windows_message_queue: windows_message_queue.Queue = .{},
    windows_paint_requests: u64 = 0,
    windows_paint_deliveries: u64 = 0,
    windows_ui_pipeline: windows_ui_ledger.Ledger = .{},
    /// The PE may terminate through ExitProcess, which runs the loader's
    /// atexit summary without returning through runWithLimit's epilogue. Keep
    /// the final host-side Vulkan snapshot idempotent so both exits publish
    /// the terminal frame state and neither duplicates it.
    windows_present_chain_final_reported: bool = false,
    windows_message_dispatch_frames: [MAX_WINDOWS_MESSAGE_DISPATCH_FRAMES]WindowsMessageDispatchFrame = [_]WindowsMessageDispatchFrame{.{}} ** MAX_WINDOWS_MESSAGE_DISPATCH_FRAMES,
    windows_message_dispatch_frame_count: usize = 0,
    windows_audio_callback_frames: [MAX_WINDOWS_AUDIO_CALLBACK_FRAMES]WindowsAudioCallbackFrame = [_]WindowsAudioCallbackFrame{.{}} ** MAX_WINDOWS_AUDIO_CALLBACK_FRAMES,
    windows_audio_callback_frame_count: usize = 0,
    windows_wave_out_devices: [MAX_WINDOWS_WAVE_OUT_DEVICES]WindowsWaveOutDevice = [_]WindowsWaveOutDevice{.{}} ** MAX_WINDOWS_WAVE_OUT_DEVICES,
    /// The host device, when the runner installed one. Absent means the wave
    /// path still runs, on the clocked null sink.
    windows_audio_hooks: WindowsAudioHooks = .{},
    windows_audio_host_open_attempts: u64 = 0,
    windows_audio_host_open_failures: u64 = 0,
    windows_audio_host_bytes_accepted: u64 = 0,
    windows_audio_host_bytes_dropped: u64 = 0,
    windows_audio_host_connected: bool = false,
    /// PROCESS_DPI_AWARENESS as the guest last set it. Retained because a
    /// guest that sets awareness and reads it back must see what it set;
    /// answering the read with a constant zero says "unaware" to a process
    /// that just declared itself per-monitor aware.
    windows_process_dpi_awareness: u32 = 0,
    windows_cjk_font_decision_reported: bool = false,
    windows_cjk_font_granted: bool = false,
    windows_audio_import_calls: u64 = 0,
    // SDL selects its Windows audio backend through the guest CRT's
    // SDL_AUDIODRIVER lookup. Keep the lookup separate from WinMM calls so a
    // run can distinguish "the audio worker never initialized SDL" from
    // "SDL initialized but never crossed the WinMM boundary".
    windows_audio_environment_queries: u64 = 0,
    windows_audio_environment_policy_reported: bool = false,
    windows_audio_environment_driver: []const u8 = "",
    windows_audio_format_queries: u64 = 0,
    windows_audio_open_calls: u64 = 0,
    windows_audio_open_successes: u64 = 0,
    windows_audio_format_rejections: u64 = 0,
    windows_audio_prepare_calls: u64 = 0,
    windows_audio_unprepare_calls: u64 = 0,
    windows_audio_reset_calls: u64 = 0,
    windows_audio_write_calls: u64 = 0,
    windows_audio_close_calls: u64 = 0,
    windows_audio_buffers_submitted: u64 = 0,
    windows_audio_buffers_completed: u64 = 0,
    windows_audio_callback_dispatches: u64 = 0,
    windows_audio_callback_failures: u64 = 0,
    windows_audio_bytes_submitted: u64 = 0,
    windows_audio_nonzero_buffers: u64 = 0,
    windows_audio_last_checksum: u64 = 0,
    windows_audio_last_data: u64 = 0,
    windows_audio_last_bytes: u32 = 0,
    windows_file_open_calls: u64 = 0,
    windows_file_read_calls: u64 = 0,
    windows_file_write_calls: u64 = 0,
    windows_file_failures: u64 = 0,
    windows_file_read_provenance: [WINDOWS_FILE_READ_PROVENANCE_CAPACITY]WindowsFileReadProvenance = @splat(.{}),
    windows_file_read_provenance_next: usize = 0,
    windows_file_read_provenance_count: usize = 0,
    windows_file_read_provenance_total: u64 = 0,
    windows_file_failure_ledger: WindowsFileFailureLedger = .{},
    /// The import currently being dispatched. Set once per import call so a
    /// failure raised deep inside a handler can be attributed without every
    /// one of the sixty-nine failure sites having to carry its own name.
    /// The slice points at the import stub's own storage, which outlives the
    /// call, or at a string literal.
    windows_current_import: []const u8 = &.{},
    windows_current_import_return: u64 = 0,
    windows_rtl_capture_calls: u64 = 0,
    windows_rtl_unwind_calls: u64 = 0,
    windows_stub_storage: [MAX_WINDOWS_IMPORT_STUBS]WindowsImportStub = undefined,
    windows_stub_owned_names: [MAX_WINDOWS_IMPORT_STUBS]bool = @splat(false),
    windows_stub_count: usize = 0,
    // PE IAT thunks are materialized as one contiguous, fixed-stride range
    // before execution starts. Keep its geometry separate from the optional
    // GetProcAddress stubs so the instruction hot path can reject ordinary
    // image addresses with two comparisons instead of scanning every import.
    windows_direct_stub_base: u64 = 0,
    windows_direct_stub_count: usize = 0,
    windows_dynamic_stub_start: usize = 0,
    windows_graphics: WindowsGraphicsState = .{},
    windows_input_hooks: WindowsInputHooks = .{},
    windows_input_polls: u64 = 0,
    windows_input_bridged_polls: u64 = 0,
    windows_input_invalid_polls: u64 = 0,
    windows_input_last_packet: u32 = 0,
    windows_input_last_buttons: u16 = 0,
    windows_input_last_focused: bool = false,
    windows_input_key_down_events: u64 = 0,
    windows_input_key_up_events: u64 = 0,
    windows_input_snapshot_reads: u64 = 0,
    windows_input_nonzero_samples: u64 = 0,
    windows_input_focused_zero_samples: u64 = 0,
    windows_input_left_stick_deliveries: u64 = 0,
    windows_input_last_left_stick: [2]i16 = .{ 0, 0 },
    windows_input_last_left_stick_packet: u32 = 0,
    windows_input_focus_gains: u64 = 0,
    windows_input_focus_losses: u64 = 0,
    windows_input_rejected_events: u64 = 0,
    windows_input_last_key_code: u32 = 0,
    windows_input_contract_version: u32 = 0,
    windows_input_physical_connected: bool = false,
    windows_input_physical_events: u64 = 0,
    windows_input_physical_name: [64]u8 = [_]u8{0} ** 64,
    windows_input_xinput_successes: u64 = 0,
    windows_input_xam_shims: u64 = 0,
    windows_input_xam_refusals: u64 = 0,
    /// Rosetta's local screen verdict is deliberately stricter than a
    /// successful Vulkan call. The native bridge may have richer pixel
    /// evidence, but this state must never call transport-only traffic a
    /// valid picture when that evidence has not crossed the seam.
    windows_screen_validity: screen_validity.Ledger = .{},
    windows_present_no_work_checkpoints: u32 = 0,
    windows_present_no_work_reported: bool = false,
    /// Said once that the no-presents verdict is being held because the guest
    /// frontier is inside work that terminates. Repeating it every checkpoint
    /// would bury the reason in the noise it is explaining.
    windows_present_bounded_work_reported: bool = false,
    windows_present_no_submit_checkpoints: u32 = 0,
    windows_present_no_submit_reported: bool = false,
    // The native Vulkan forwarder records these lightweight execution facts
    // for diagnostics. They are intentionally inert for the PE scheduler;
    // there is no UI-thread ownership to infer from a plain guest state.
    active_guest_thread: u64 = 0x7FFF_2020,
    /// Current Windows guest identity, retained with the CPU context so a
    /// host executor does not need a shared scheduler-slot lookup.
    windows_thread_id: u64 = 1,
    active_idle_source: u64 = 1,
    last_decoded_op: Op = .invalid,
    last_decoded_len: u8 = 0,
    last_instruction_rip: u64 = 0,
    decode_failure_is_invalid_control_target: bool = false,

    pub const __StateInternals = struct {
        pub const _BlockJitFallbackView = BlockJitFallbackView;
        pub const _DecodeCacheVictimHit = DecodeCacheVictimHit;
        pub const _ExitContextSource = ExitContextSource;
        pub const _FoundBlock = FoundBlock;
        pub const _GpuRingSource = GpuRingSource;
        pub const _GuestOutputHostSink = GuestOutputHostSink;
        pub const _GuestWaitPark = GuestWaitPark;
        pub const _HostQos = HostQos;
        pub const _InstructionSource = InstructionSource;
        pub const _MilestoneReach = MilestoneReach;
        pub const _NativeConditionResult = NativeConditionResult;
        pub const _OpBitset = OpBitset;
        pub const _OwnerWaitOutcome = OwnerWaitOutcome;
        pub const _RuntimeLockHolder = RuntimeLockHolder;
        pub const _TimedWaitOutcome = TimedWaitOutcome;
        pub const _WindowsBlockedCause = WindowsBlockedCause;
        pub const _WindowsBlockedFinding = WindowsBlockedFinding;
        pub const _WindowsConditionWaitResult = WindowsConditionWaitResult;
        pub const _WindowsPthreadMutexAcquireResult = WindowsPthreadMutexAcquireResult;
        pub const _WindowsPthreadMutexReleaseResult = WindowsPthreadMutexReleaseResult;
        pub const _WindowsSrwAcquireResult = WindowsSrwAcquireResult;
        pub const _WindowsWaitResult = WindowsWaitResult;
        pub const _XboxCriticalSectionCall = XboxCriticalSectionCall;
        pub const _XboxSectionAccess = XboxSectionAccess;
        pub const _XboxWait = XboxWait;
        pub const _block_jit_layout = block_jit_layout;
        pub const _evex_handled_bits = evex_handled_bits;
        pub const _guest_wait_slice_ns = guest_wait_slice_ns;
        pub const _op_names = op_names;
        pub const _op_value_limit = op_value_limit;
        pub const _vector_operation_bits = vector_operation_bits;
        pub const _windows_context_bytes = windows_context_bytes;
        pub const _windows_exception_continue_execution = windows_exception_continue_execution;
        pub const _windows_exception_frame_magic = windows_exception_frame_magic;
        pub const _windows_exception_header_bytes = windows_exception_header_bytes;
        pub const _windows_exception_nesting_limit = windows_exception_nesting_limit;
        pub const _windows_exception_record_bytes = windows_exception_record_bytes;
        pub const _windows_memory_trace_budget = windows_memory_trace_budget;
        pub const _windows_memory_trace_floor = windows_memory_trace_floor;
        pub const _windows_memory_trace_step_budget = windows_memory_trace_step_budget;
        pub const _windows_status_access_violation = windows_status_access_violation;
    };
    pub fn init(allocator: std.mem.Allocator) ElfState {
        return initWithMemory(allocator, MEM_SIZE);
    }

    /// Construct an x86-64 state with an address-space size chosen by the
    /// loader.  ELF keeps the historical 64 MiB default, while PE32+ images
    /// commonly have a much larger image and must not be truncated into it.
    pub fn initWithMemory(allocator: std.mem.Allocator, memory_size: u64) ElfState {
        const decode_cache = allocator.alloc(DecodeCacheEntry, PE_DECODE_CACHE_ENTRIES) catch unreachable;
        @memset(decode_cache, .{});
        const decode_cache_victims = allocator.alloc(DecodeCacheEntry, PE_DECODE_CACHE_VICTIM_ENTRIES) catch unreachable;
        @memset(decode_cache_victims, .{});
        const decode_cache_shards = allocator.alloc(DecodeCacheShard, decode_cache_set_lock_count) catch unreachable;
        @memset(decode_cache_shards, .{});
        const memory_len: usize = @intCast(memory_size);
        const mem = allocator.alloc(u8, memory_len) catch unreachable;
        const trace_storage = allocator.alloc(ElfTraceEntry, TRACE_BUFFER_LEN) catch unreachable;
        const heap_allocations = allocator.alloc(WindowsHeapAllocation, INITIAL_WINDOWS_HEAP_ALLOCATIONS) catch unreachable;
        const heap_free_indices = allocator.alloc(usize, INITIAL_WINDOWS_HEAP_ALLOCATIONS) catch unreachable;
        var guest_store_buffers = tso_memory.GuestStoreBuffers.init(allocator, MAX_WINDOWS_GUEST_THREADS) catch unreachable;
        // `ROSETTE_TSO_STORE_BUFFERS=0` sends every guest store straight to
        // memory: an A/B switch for a run that behaves differently with the
        // store buffers on, which points at a missing tier-boundary drain.
        guest_store_buffers.enabled = !envPresentAndFalse("ROSETTE_TSO_STORE_BUFFERS");
        const heap_guard_bytes: u64 = if (envPresentAndFalse("ROSETTE_PE64_HEAP_GUARD")) 0 else heap_guard.default_guard_bytes;
        const owner_context_audit_steps = if (std.c.getenv("ROSETTE_PE64_CONTEXT_AUDIT")) |raw|
            std.mem.eql(u8, std.mem.sliceTo(raw, 0), "step")
        else
            false;
        const windows_guest_threads = allocator.alloc(WindowsGuestThread, MAX_WINDOWS_GUEST_THREADS) catch unreachable;
        const owner_tlb = allocator.create(block_jit.Tlb) catch unreachable;
        owner_tlb.* = block_jit.Tlb.empty;
        @memset(windows_guest_threads, .{});
        @memset(trace_storage, .{});
        @memset(heap_allocations, .{});
        @memset(heap_free_indices, 0);
        @memset(mem, 0);
        var state: ElfState = .{
            .allocator = allocator,
            .decode_cache = decode_cache,
            .decode_cache_victims = decode_cache_victims,
            .decode_cache_shards = decode_cache_shards,
            .mem = mem,
            .mem_base = MEM_BASE,
            .mem_size = memory_size,
            .trace_storage = trace_storage,
            .windows_heap_allocations = heap_allocations,
            .windows_heap_free_indices = heap_free_indices,
            .guest_store_buffers = guest_store_buffers,
            .owner_context_audit_steps = owner_context_audit_steps,
            .windows_heap_guard_bytes = heap_guard_bytes,
            .windows_guest_threads = windows_guest_threads,
            .block_jit_tlb = owner_tlb,
            .trace_syscalls = envFlag("ROSETTE_ELF_TRACE_SYSCALLS"),
            .trace_syscall_bytes = envFlag("ROSETTE_ELF_TRACE_SYSCALL_BYTES"),
            .trace_fd_filter = envU64("ROSETTE_ELF_TRACE_FD"),
            .trace_calls = envFlag("ROSETTE_ELF_TRACE_CALLS"),
            .trace_rip_start = envU64("ROSETTE_ELF_TRACE_START"),
            .trace_rip_end = envU64("ROSETTE_ELF_TRACE_END"),
            .trace_rip_limit = envU64("ROSETTE_ELF_TRACE_LIMIT"),
            .trace_write_address = envU64("ROSETTE_ELF_TRACE_WRITE_ADDRESS"),
            .block_jit_verify_memory = envFlag("ROSETTE_BLOCK_JIT_VERIFY_MEMORY"),
            .diagnose_abi = envFlag("ROSETTE_ELF_DIAGNOSE_ABI") or envFlag("ROSETTE_ELF_INTERACTIVE_BRIDGE") or envFlag("ROSETTE_ELF_EDU_BRIDGE"),
        };
        state.trace_allocations = envFlag("ROSETTA_ELF_TRACE_ALLOCATIONS");
        state.trace_formatter = envFlag("ROSETTA_ELF_TRACE_FORMATTER");
        state.trace_formatter_address = envU64("ROSETTA_ELF_TRACE_FORMATTER_ADDRESS");
        state.trace_string_memory = envFlag("ROSETTA_ELF_TRACE_STRING_MEMORY") or envFlag("ROSETTE_ELF_TRACE_STRING_MEMORY");
        state.trace_vector = envFlag("ROSETTE_ELF_TRACE_VECTOR");
        state.trace_utf8 = envFlag("ROSETTE_ELF_TRACE_UTF8");
        state.trace_windows_threads = envFlag("ROSETTA_ELF_TRACE_WINDOWS_THREADS");
        state.trace_windows_messages = envFlag("ROSETTA_ELF_TRACE_WINDOWS_MESSAGES");
        state.refreshBlockJitTransferTraced();
        state.trace_windows_audio = envFlag("ROSETTE_ELF_TRACE_WINDOWS_AUDIO") or envFlag("ROSETTA_ELF_TRACE_WINDOWS_AUDIO");
        state.trace_windows_paths = envFlag("ROSETTE_ELF_TRACE_WINDOWS_PATHS");
        state.trace_windows_waits = envFlag("ROSETTE_ELF_TRACE_WINDOWS_WAITS") or envFlag("ROSETTA_ELF_TRACE_WINDOWS_WAITS");
        state.trace_windows_conditions = envFlag("ROSETTE_ELF_TRACE_WINDOWS_CONDITIONS") or envFlag("ROSETTA_ELF_TRACE_WINDOWS_CONDITIONS");
        state.trace_windows_memory = envFlag("ROSETTE_ELF_TRACE_WINDOWS_MEMORY") or envFlag("ROSETTA_ELF_TRACE_WINDOWS_MEMORY");
        state.trace_windows_mappings = envFlag("ROSETTE_ELF_TRACE_WINDOWS_MAPPINGS") or envFlag("ROSETTA_ELF_TRACE_WINDOWS_MAPPINGS");
        state.trace_graphics_progress = envFlag("ROSETTE_ELF_GRAPHICS_PROGRESS_TRACE");
        // A fatal point stops the run by default: a warning is an error until
        // something proves otherwise. `=0` records every one without
        // stopping, and ROSETTE_XENIA_FATAL_POINT_ALLOW=<labels> steps past
        // named ones.
        state.windows_fatal_point_terminate = !envPresentAndFalse("ROSETTE_XENIA_FATAL_POINT_TERMINATE");
        state.configureWindowsFatalPointAllow(envText("ROSETTE_XENIA_FATAL_POINT_ALLOW"));
        state.guest_null_page_fatal = !envPresentAndFalse("ROSETTE_PE64_NULL_PAGE_FATAL");
        log.info("PE64 FATAL POINTS: terminate={} null_page_fatal={} allow=[{s}]; a fatal point stops the run where it was decided. ROSETTE_XENIA_FATAL_POINT_ALLOW=<label,...> steps past named ones, ROSETTE_XENIA_FATAL_POINT_TERMINATE=0 records without stopping, ROSETTE_PE64_NULL_PAGE_FATAL=0 lets a null-page access read zero again", .{
            state.windows_fatal_point_terminate,
            state.guest_null_page_fatal,
            state.windows_fatal_point_allow[0..state.windows_fatal_point_allow_len],
        });
        state.windows_capability_gaps_fatal = !envPresentAndFalse("ROSETTE_PE64_CAPABILITY_GAP_FATAL");
        state.windows_pthread_cond_native = envFlag("ROSETTE_PE64_NATIVE_PTHREAD_COND") or envFlag("ROSETTA_PE64_NATIVE_PTHREAD_COND");
        state.windows_guest_wait_compatibility = envFlag("ROSETTE_PE64_GUEST_WAIT_COMPAT") or envFlag("ROSETTA_PE64_GUEST_WAIT_COMPAT");
        state.host_thread_qos_enabled = !envPresentAndFalse("ROSETTE_PE64_THREAD_QOS");
        state.xenia_rijndael_accelerator_enabled = envFlag("ROSETTE_PE64_XENIA_RIJNDAEL_ACCELERATOR");
        state.xenia_sha1_accelerator_enabled = envFlag("ROSETTE_PE64_XENIA_SHA1_ACCELERATOR");
        state.xenia_sha1_feed_enabled = !envPresentAndFalse("ROSETTE_PE64_XENIA_SHA1_FEED_ACCELERATOR");
        state.xenia_tabulate_accelerator_enabled = envFlag("ROSETTE_PE64_XENIA_TABULATE_ACCELERATOR");
        state.windows_scheduler.enabled = !envPresentAndFalse("ROSETTE_PE64_GUEST_SCHEDULER");
        // The block translator is on unless refused by name. The threshold
        // is how many times a start address runs before it is compiled.
        state.block_jit_enabled = !envPresentAndFalse("ROSETTE_X64_BLOCK_JIT");
        state.block_jit_tlb_enabled = !envPresentAndFalse("ROSETTE_X64_BLOCK_JIT_TLB");
        state.block_jit_streaming_stores_enabled = !envPresentAndFalse("ROSETTE_X64_STREAMING_STORES");
        state.parallel_pause_batches_enabled = !envPresentAndFalse("ROSETTE_PE64_PAUSE_BATCHES");
        state.windows_srw_stack_capture_all = envEquals("ROSETTE_SRW_STACK_CAPTURE", "all");
        state.windows_srw_import_lane = !envPresentAndFalse("ROSETTE_SRW_IMPORT_LANE");
        state.parallel_direct_tlb = !envPresentAndFalse("ROSETTE_PE64_PARALLEL_TLB");
        state.block_jit_chain_enabled = !envPresentAndFalse("ROSETTE_X64_BLOCK_JIT_CHAIN");
        state.block_jit_vectors_enabled = !envPresentAndFalse("ROSETTE_X64_BLOCK_JIT_VECTOR");
        state.block_jit_internal_edges_enabled = !envPresentAndFalse("ROSETTE_X64_BLOCK_JIT_INTERNAL_EDGES");
        state.wide_access_watch_enabled = !envPresentAndFalse("ROSETTE_X64_WIDE_ACCESS_WATCH");
        if (envU64("ROSETTE_X64_BLOCK_JIT_HOT_THRESHOLD")) |threshold| {
            if (threshold != 0 and threshold <= std.math.maxInt(u16)) state.block_jit_hot_threshold = @intCast(threshold);
        }
        if (envU64("ROSETTE_PE64_GUEST_SCHEDULER_QUANTUM")) |quantum| {
            if (quantum != 0) state.windows_scheduler.quantum = quantum;
        }
        if (envU64("ROSETTE_PE64_GUEST_SCHEDULER_SLICE")) |slice| {
            if (slice != 0) state.windows_scheduler.slice = slice;
        }
        if (envU64("ROSETTE_PE64_GUEST_SCHEDULER_EXPLICIT_STRIDE")) |stride| {
            if (stride != 0) state.windows_scheduler.explicit_stride = stride;
        }
        // The progress watchdog is on by default because it is silent unless
        // every observable axis freezes at once; a healthy run pays two
        // comparisons per step and prints nothing.
        state.windows_progress.enabled = !envPresentAndFalse("ROSETTE_PE64_STALL_WATCHDOG");
        // The guest clock's source. Default is the host monotonic clock; the
        // instruction-derived rate published a one-MIPS machine and made
        // every guest timer fire three thousand times too often per unit of
        // work. See `WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE`.
        state.guest_clock.source = if (envEquals("ROSETTE_GUEST_CLOCK", "instructions")) .retired_instructions else .host_monotonic;
        // How many interpreted instructions one microsecond of guest time
        // costs under the instruction-derived source. One reproduces the
        // 1-MIPS machine; a few thousand describes the console, and dilates
        // guest time to the interpreter's pace so audio pumps, frame limiters
        // and fades advance per unit of work rather than per wall second.
        if (envU64("ROSETTE_GUEST_CLOCK_INSTRUCTIONS_PER_TICK")) |ratio| {
            if (ratio != 0) state.guest_clock.instructions_per_tick = ratio;
        }
        if (envU64("ROSETTE_PE64_STALL_SAMPLE_STEPS")) |interval| {
            if (interval != 0) state.windows_progress.interval = interval;
        }
        if (envU64("ROSETTE_PE64_STALL_SAMPLES")) |samples| {
            if (samples != 0 and samples <= std.math.maxInt(u32)) {
                state.windows_progress.threshold = @intCast(samples);
            }
        }
        state.heap_next = MEM_BASE + (memory_size / 2);
        // Bind the ring to stable heap storage. The state is returned by value,
        // but the storage address remains valid until `deinit`.
        state.trace_ring = execution_history.Ring(ElfTraceEntry).init(trace_storage);
        return state;
    }

    pub fn deinit(self: *ElfState) void {
        return process_impl_lifecycle.deinit(self);
    }

    fn stopParallelGuestWorkers(self: *ElfState) void {
        return process_impl_lifecycle.stopParallelGuestWorkers(self);
    }

    pub fn windowsWorkerSteps(self: *const ElfState) u64 {
        return process_impl_lifecycle.windowsWorkerSteps(self);
    }

    fn windowsThreadServiceSteps(self: *const ElfState) u64 {
        return process_impl_lifecycle.windowsThreadServiceSteps(self);
    }

    fn windowsGuestThreadSteps(self: *const ElfState, thread: *const WindowsGuestThread) u64 {
        return process_impl_lifecycle.windowsGuestThreadSteps(self, thread);
    }

    /// `executed_steps` remains the owner loop's local count for the existing
    /// public result shape. Guest events and diagnostics need one coherent
    /// process-wide number while workers run, so they use this atomic view.
    fn observedExecutionSteps(self: *const ElfState) u64 {
        return process_impl_lifecycle.observedExecutionSteps(self);
    }

    /// Wall milliseconds since `runWithLimit` began, for lines that join a
    /// cross-thread timeline.
    fn runElapsedMilliseconds(self: *const ElfState) u64 {
        return process_impl_lifecycle.runElapsedMilliseconds(self);
    }

    /// The process owner's own instructions. In parallel mode that is its
    /// loop's count alone; `observedExecutionSteps` there is every thread's,
    /// and the 2026-09-26 step budget printed it as the owner's and the
    /// workers' share as zero.
    fn ownerExecutedSteps(self: *const ElfState) u64 {
        return process_impl_lifecycle.ownerExecutedSteps(self);
    }

    pub fn isTerminated(self: *const ElfState) bool {
        return process_impl_lifecycle.isTerminated(self);
    }

    /// Capture a worker's first fault before the owner observes the global
    /// termination flag and restores its own guest context. This record is
    /// immutable after publication; later workers cannot replace the
    /// original cause with their shutdown state.
    fn markFaulted(self: *ElfState) void {
        return process_impl_lifecycle.markFaulted(self);
    }

    pub fn markTerminated(self: *ElfState) void {
        return process_impl_lifecycle.markTerminated(self);
    }

    fn parallelTerminationRequested(self: *const ElfState) bool {
        return process_impl_lifecycle.parallelTerminationRequested(self);
    }

    /// Everything a thread switch has to carry that is not already the
    /// thread's own guest memory. TLS is: every thread has its own TEB and
    /// its own slot vector inside it (`teb + 0x1000`, pointed to by
    /// `teb + 0x58`), so the 512 slots are not copied. They used to be, out
    /// on every capture and back on every restore - 1,024 guest accesses and
    /// 4 KiB of context per switch - which is most of why `write64` and
    /// `memmove` were 18% of the emulation thread on 2026-09-23.
    /// The executing context, resolved once. See `GuestContextRef`.
    fn guestContextRef(self: *ElfState) GuestContextRef {
        return process_impl_lifecycle.guestContextRef(self);
    }

    pub fn guestContextField(
        self: anytype,
        comptime field: []const u8,
    ) if (@typeInfo(@TypeOf(self)).pointer.is_const)
        *const @FieldType(WindowsGuestThreadContext, field)
    else
        *@FieldType(WindowsGuestThreadContext, field) {
        return process_impl_lifecycle.guestContextField(self, field);
    }

    /// Runtime shims are generic over their state type; expose the same
    /// context selector they need for architectural register and thread-local
    /// runtime state.
    pub fn windowsGuestContextField(
        self: anytype,
        comptime field: []const u8,
    ) if (@typeInfo(@TypeOf(self)).pointer.is_const)
        *const @FieldType(WindowsGuestThreadContext, field)
    else
        *@FieldType(WindowsGuestThreadContext, field) {
        return process_impl_lifecycle.windowsGuestContextField(self, field);
    }

    pub fn windowsGuestErrnoStorage(self: anytype) if (@typeInfo(@TypeOf(self)).pointer.is_const) *const u64 else *u64 {
        return process_impl_lifecycle.windowsGuestErrnoStorage(self);
    }

    /// Take the runtime lock for a critical section of the runtime's tables.
    pub fn lockWindowsRuntime(self: *ElfState) WindowsRuntimeLockGuard {
        return process_impl_lifecycle.lockWindowsRuntime(self);
    }

    /// Take the runtime lock to route one call into its handler: the step
    /// loop's import and hook dispatch, and the Windows runtime's entry
    /// wrappers. Such a level holds nothing half-changed of its own, so a
    /// handler that must block - `GetMessage` with nothing to deliver - may
    /// release the lock while every level this thread holds is one of these.
    pub fn lockWindowsRuntimeForDispatch(self: *ElfState) WindowsRuntimeLockGuard {
        return process_impl_lifecycle.lockWindowsRuntimeForDispatch(self);
    }

    /// Run a host-only call with the runtime mutex yielded when every held
    /// lock level is dispatch-only. The callback must use only host-owned
    /// arguments prepared before this call; it must not read or mutate guest
    /// state while the mutex is released. Pipeline creation meets that
    /// contract: its Vulkan structs, arrays, names, and specialization data
    /// are copied to stack scratch before the driver is entered, and Vulkan
    /// object lifetimes remain governed by Xenia's host API synchronization.
    ///
    /// Yielding here lets other guest contexts continue CPU work during slow
    /// Metal shader/pipeline compilation. A pinned runtime critical section
    /// is never released. The dispatch guard's TLS entry stays in place, and
    /// the lock is reacquired before this function returns to any code that
    /// touches the forwarder or guest state.
    pub fn withWindowsRuntimeLockReleased(self: *ElfState, context: anytype, callback: anytype) @TypeOf(callback(context)) {
        return process_impl_lifecycle.withWindowsRuntimeLockReleased(self, context, callback);
    }

    /// `vkWaitForFences` receives a copied host fence array and scalar
    /// arguments. Its potentially long wait can therefore yield a
    /// dispatch-only runtime lock, then safely reacquire before the caller
    /// updates guest and Rosetta bookkeeping. The pinned-lock rule is shared
    /// with pipeline creation.
    pub fn withWindowsRuntimeLockReleasedForGpuFenceWait(self: *ElfState, context: anytype, callback: anytype) @TypeOf(callback(context)) {
        return process_impl_lifecycle.withWindowsRuntimeLockReleasedForGpuFenceWait(self, context, callback);
    }

    /// Wait on Rosette-owned Vulkan queue admission or FSI monitor state
    /// without holding the shared guest-runtime mutex. The callback may use
    /// only host-owned synchronization state; the Vulkan queue gate keeps
    /// queue calls serialized until the blocked operation resumes.
    /// Returns false instead of blocking under a pinned runtime critical
    /// section, where doing so could prevent the active queue owner from
    /// reacquiring the mutex and releasing its gate lease.
    pub fn tryWithWindowsRuntimeLockReleasedForVulkanQueueWait(self: *ElfState, context: anytype, callback: anytype) bool {
        return process_impl_lifecycle.tryWithWindowsRuntimeLockReleasedForVulkanQueueWait(self, context, callback);
    }

    fn withWindowsRuntimeLockReleasedFor(
        self: *ElfState,
        purpose: enum { native_pipeline, gpu_fence_wait, gpu_queue_wait },
        context: anytype,
        callback: anytype,
    ) @TypeOf(callback(context)) {
        return process_impl_lifecycle.withWindowsRuntimeLockReleasedFor(self, purpose, context, callback);
    }

    fn lockWindowsRuntimeKind(self: *ElfState, pinned: bool) WindowsRuntimeLockGuard {
        return process_impl_lifecycle.lockWindowsRuntimeKind(self, pinned);
    }

    /// Most interpreted transfers only inspect call targets. Acquire the
    /// runtime boundary only after a shim has proved it owns the target, so
    /// ordinary guest calls avoid a host mutex cost.
    fn lockGuestRuntimeMutationIfParallel(self: *ElfState) ?WindowsRuntimeLockGuard {
        return process_impl_lifecycle.lockGuestRuntimeMutationIfParallel(self);
    }

    /// Changing what guest memory *is* - mapping, unmapping, protecting,
    /// releasing it - races every executor's in-flight access and every
    /// queued store's host address, so it stops the world on top of the
    /// runtime lock (runtime mutex first; lib/concurrency/README.md) and
    /// publishes every executor's queue. These are the only runtime
    /// operations that stop the world.
    pub fn lockGuestAddressSpaceIfParallel(self: *ElfState) ?WindowsRuntimeLockGuard {
        return process_impl_lifecycle.lockGuestAddressSpaceIfParallel(self);
    }

    /// Record that the runtime just made a parked guest thread runnable
    /// (or signalled something the owner may wait on). Called with the
    /// runtime lock held; the lock's release wakes the workers.
    fn noteWindowsThreadWake(self: *ElfState) void {
        return process_impl_lifecycle.noteWindowsThreadWake(self);
    }

    /// The runtime changed something a sleeping guest thread may be waiting
    /// for without making any thread runnable itself (an `InitOnceComplete`):
    /// wake the sleepers so they look again.
    pub fn wakeGuestWaiters(self: *ElfState) void {
        return process_impl_lifecycle.wakeGuestWaiters(self);
    }

    pub fn captureWindowsGuestContext(self: *const ElfState) WindowsGuestThreadContext {
        return process_impl_lifecycle.captureWindowsGuestContext(self);
    }

    pub fn restoreWindowsGuestContext(self: *ElfState, context: *const WindowsGuestThreadContext) void {
        return process_impl_lifecycle.restoreWindowsGuestContext(self, context);
    }

    /// Return the Windows-visible thread identifier for the currently
    /// executing cooperative context.  The PE executor has one host thread,
    /// but Xenia still uses GetCurrentThreadId to implement recursive mutex
    /// ownership.  Returning one constant for every guest worker makes every
    /// worker look recursive and lets it enter another thread's critical
    /// region.
    /// One identity query answered by the lock-free lane
    /// (`fast_imports.tryIdentityQuery`).
    pub fn noteWindowsFastIdentityImport(self: *ElfState) void {
        return process_impl_lifecycle.noteWindowsFastIdentityImport(self);
    }

    pub fn noteWindowsFastAffinityImport(self: *ElfState, return_rip: u64) void {
        return process_impl_lifecycle.noteWindowsFastAffinityImport(self, return_rip);
    }

    pub fn windowsFastAffinityMasks(self: *const ElfState) [2]u64 {
        return process_impl_lifecycle.windowsFastAffinityMasks(self);
    }

    pub fn noteWindowsFastSleepZeroImport(self: *ElfState, return_rip: u64) void {
        return process_impl_lifecycle.noteWindowsFastSleepZeroImport(self, return_rip);
    }

    /// A zero-duration Sleep may use the fast import lane only when the
    /// calling guest worker does not own Xenia's global mutex. That mutex's
    /// special back-off path updates the shared SRW/waiter ledger and must
    /// stay in the locked dispatcher; the ordinary fast yield is correct for
    /// every other call site.
    pub fn windowsFastSleepZeroImportAllowed(self: *ElfState) bool {
        return process_impl_lifecycle.windowsFastSleepZeroImportAllowed(self);
    }

    pub fn currentWindowsThreadId(self: *const ElfState) u64 {
        return process_impl_lifecycle.currentWindowsThreadId(self);
    }

    /// Monotonic guest time shared by the owner and every cooperative worker
    /// slice. It is deliberately separate from `executed_steps`, which is the
    /// owner-loop progress counter used by scheduling and checkpoint output.
    pub fn windowsGuestClockTicks(self: *const ElfState) u64 {
        return process_impl_lifecycle.windowsGuestClockTicks(self);
    }

    /// The FILETIME fast import reads a single published counter rather than
    /// taking the mutex protecting the clock's multi-field state. The value
    /// is published from the same clock update path as `windowsGuestClockTicks`.
    pub fn windowsGuestFastFileTime(self: *ElfState) u64 {
        return process_impl_lifecycle.windowsGuestFastFileTime(self);
    }

    /// The FILETIME of the published tick count, without sampling the clock.
    pub fn windowsGuestPublishedFileTime(self: *const ElfState) u64 {
        return process_impl_lifecycle.windowsGuestPublishedFileTime(self);
    }

    /// The tick count the lock-free QueryPerformanceCounter answers: the same
    /// value `windowsGuestClockTicks` returns, read without the clock mutex.
    pub fn windowsGuestFastClockTicks(self: *ElfState) u64 {
        return process_impl_lifecycle.windowsGuestFastClockTicks(self);
    }

    /// The precise-time import may bypass the shared runtime lock only when
    /// it can read the published host-clock snapshot and is not already
    /// inside a runtime dispatch. Retired-instruction clock mode stays on the
    /// ordinary path because its coherent snapshot currently uses the
    /// guest-clock mutex.
    pub fn windowsFastImportMayBypassRuntimeLock(self: *const ElfState) bool {
        return process_impl_lifecycle.windowsFastImportMayBypassRuntimeLock(self);
    }

    /// Begin/end the small set of fast runtime imports that write guest
    /// memory but do not mutate process-wide Windows tables. This retains
    /// the ordinary import's store-buffer boundary without taking its mutex.
    pub fn beginWindowsFastImportStoreScope(_: *ElfState) ?*tso_memory.StoreBuffer {
        return process_impl_lifecycle.beginWindowsFastImportStoreScope(undefined);
    }

    pub fn endWindowsFastImportStoreScope(_: *ElfState, prior: ?*tso_memory.StoreBuffer) void {
        return process_impl_lifecycle.endWindowsFastImportStoreScope(undefined, prior);
    }

    /// The C runtime's memcpy/memmove/memset lane needs only what every fast
    /// import needs: parallel execution, and no runtime dispatch already
    /// held by this thread. It reads no clock, so the precise-time query's
    /// clock-source condition does not apply to it.
    pub fn windowsFastCrtImportMayBypassRuntimeLock(self: *const ElfState) bool {
        return process_impl_lifecycle.windowsFastCrtImportMayBypassRuntimeLock(self);
    }

    pub fn noteWindowsFastCrtImport(self: *ElfState, op: anytype) void {
        return process_impl_lifecycle.noteWindowsFastCrtImport(self, op);
    }

    pub fn noteWindowsFastCrtStringImport(self: *ElfState, op: anytype) void {
        return process_impl_lifecycle.noteWindowsFastCrtStringImport(self, op);
    }

    pub fn noteWindowsFastHeapImport(self: *ElfState, op: anytype) void {
        return process_impl_lifecycle.noteWindowsFastHeapImport(self, op);
    }

    pub fn windowsFastCrtImportCalls(self: *const ElfState) u64 {
        return process_impl_lifecycle.windowsFastCrtImportCalls(self);
    }

    pub fn noteWindowsFastTimeImport(self: *ElfState, return_rip: u64, query: anytype) void {
        return process_impl_lifecycle.noteWindowsFastTimeImport(self, return_rip, query);
    }

    fn windowsFastImportCalls(self: *const ElfState) u64 {
        return process_impl_lifecycle.windowsFastImportCalls(self);
    }

    pub fn windowsImportCallCount(self: *const ElfState) u64 {
        return process_impl_lifecycle.windowsImportCallCount(self);
    }

    pub fn clearWindowsFastTimeImportReturn(self: *ElfState) void {
        return process_impl_lifecycle.clearWindowsFastTimeImportReturn(self);
    }

    fn publishWindowsGuestClockTicks(self: *ElfState) void {
        return process_impl_lifecycle.publishWindowsGuestClockTicks(self);
    }

    fn windowsGuestClockSnapshot(self: *const ElfState) guest_clock.Clock {
        return process_impl_lifecycle.windowsGuestClockSnapshot(self);
    }

    /// The frequency the guest is told its performance counter runs at.
    /// Shared with the wait deadlines so the two cannot disagree.
    pub fn windowsGuestClockHz(_: *const ElfState) u64 {
        return process_impl_lifecycle.windowsGuestClockHz(undefined);
    }

    /// The guest's wall clock as a FILETIME: the fixed base plus the guest
    /// clock. GetSystemTimeAsFileTime answers from here, and so does every
    /// deadline Rosette derives from a guest wall-clock time, so the two
    /// cannot disagree about when "now" is.
    pub fn windowsGuestFileTime(self: *const ElfState) u64 {
        return process_impl_lifecycle.windowsGuestFileTime(self);
    }

    /// End the active worker's slice at a yield boundary.
    ///
    /// This is the whole meaning of `YieldProcessor`, `SwitchToThread` and
    /// `Sleep(0)`: the caller has nothing to do and another thread should
    /// run. Rosetta answered all three by returning, so a spin-wait kept the
    /// interpreter for the rest of its slice and the threads that could make
    /// progress waited on a thread that could not.
    ///
    /// Deliberately a request rather than an immediate switch: the service
    /// loop has to save the worker's context and restore the owner's, and
    /// tearing that down from inside an import handler would leave the
    /// register file half-swapped.
    pub fn requestWindowsGuestSliceYield(self: *ElfState) void {
        return process_impl_lifecycle.requestWindowsGuestSliceYield(self);
    }

    /// A worker reached PAUSE.
    ///
    /// PAUSE is a spin-wait, and under one interpreter the value a spinner
    /// polls can only change once some other thread runs. Xenia compiles the
    /// PowerPC spin hint `db16cyc` to exactly this instruction, so a title's
    /// hardware-thread spin loop used to keep its whole slice: Halo 3's idle
    /// job worker spent 13% of a run going round two instructions. The
    /// service loop's floor still lets it spin a few hundred instructions
    /// before the switch. The owner is serviced at PAUSE separately.
    pub fn noteWindowsGuestPause(self: *ElfState) void {
        return process_impl_lifecycle.noteWindowsGuestPause(self);
    }

    /// Retire at most seven additional, consecutive PAUSEs in one executor
    /// step. Xenia's PPC spin hint emits eight of them. Each hint still runs
    /// its scheduler/forensics hook at its own RIP; the first yield, a capture,
    /// trace or hook ends the batch immediately. Cooperative execution and
    /// instruction-derived clocks keep their single-instruction boundary.
    fn retireParallelPauseTail(self: *ElfState) void {
        return process_impl_lifecycle.retireParallelPauseTail(self);
    }

    /// RENDER and MAIN can spend a stalled frame in a tight loop with no
    /// PAUSE. Probe them at a coarse step cadence already paid for by the
    /// code profiler, then reuse the bounded interpreted read capture.
    fn noteGuestProgressStall(self: *ElfState, slot: usize) void {
        return process_impl_lifecycle.noteGuestProgressStall(self, slot);
    }

    // ─── Guest spin forensics (`diagnostics/guest_spin.zig`) ───

    /// Diagnostic guest read: a copy, never a fault, from any thread.
    fn spinRead(self: *const ElfState, comptime T: type, address: u64) ?T {
        return process_impl_lifecycle.spinRead(self, T, address);
    }

    /// Whether `rip` is in Xenia's JIT code, where rsi is the PPC context.
    fn spinInGeneratedCode(self: *const ElfState, rip: u64) bool {
        return process_impl_lifecycle.spinInGeneratedCode(self, rip);
    }

    /// The pages read that nothing maps, most-read first, with the first
    /// reader. Each is a structure the guest expects the OS to provide.
    fn reportUnmappedReads(self: *const ElfState) void {
        return process_impl_lifecycle.reportUnmappedReads(self);
    }

    /// `ROSETTE_XENIA_DUMP_GUEST_CODE=0x82169ec8,0x82169f28`: once each named
    /// PowerPC function is compiled, log the x86-64 code Xenia generated for
    /// it, so a title-level miscomputation can be replayed offline through
    /// both executors. Xenia's indirection table keeps, at host address G,
    /// the 32-bit host address of guest address G's code; an uncompiled
    /// address still points at the shared resolve thunk, which the entry for
    /// G+4 (never a function start in practice) also names.
    fn reportXeniaGuestCode(self: *ElfState) void {
        return process_impl_lifecycle.reportXeniaGuestCode(self);
    }

    /// Every guest-visible time source at this pulse, with how far each
    /// moved since the last: the guest clock (QueryPerformanceCounter's), the
    /// KUSER_SHARED_DATA interrupt time Xenia reads, and the title's own
    /// KeTimeStampBundle (interrupt time, system time, tick count) at guest
    /// 0x80240EE0, which Xenia rewrites every millisecond. A source that
    /// stands still while host time passes starves every guest wait or
    /// timeout built on it; until 2026-10-02 the bundle's interrupt time was
    /// zero in every run.
    fn reportGuestTimeSources(self: *ElfState, elapsed_ns: u64) void {
        return process_impl_lifecycle.reportGuestTimeSources(self, elapsed_ns);
    }

    /// Snapshot the ring before assisting it. Waking an idle command worker
    /// cannot produce a fence whose packet was never submitted; that case
    /// needs a producer-side diagnosis rather than repeated spurious wakes.
    fn runStallAssist(self: *ElfState, slot: usize, swaps: u64, now_ns: u64) void {
        return process_impl_lifecycle.runStallAssist(self, slot, swaps, now_ns);
    }

    /// Snapshot under the runtime lock that serializes MMIO write-pointer
    /// updates. Xenia writes the fence natively, outside Rosette's store
    /// hooks, so read the value rather than relying on the watch hit count.
    fn gpuStallSnapshot(self: *ElfState, command_processor: u64) ?gpu_stall.Snapshot {
        return process_impl_lifecycle.gpuStallSnapshot(self, command_processor);
    }

    fn reportGpuStallState(self: *ElfState, snapshot: ?gpu_stall.Snapshot) void {
        return process_impl_lifecycle.reportGpuStallState(self, snapshot);
    }

    /// The first report of a stalled spin: the spinner's registers, its
    /// PowerPC context and guest call stack, and every guest thread's JIT
    /// frames with the PowerPC return address each call stored.
    fn reportGuestSpinTrigger(self: *ElfState, slot: usize, swaps: u64, cause: []const u8) void {
        return process_impl_lifecycle.reportGuestSpinTrigger(self, slot, swaps, cause);
    }

    /// The read-only signature is from the user's Halo 3 XEX: at PPC
    /// 0x821A858C-0x821A85BC the RENDER thread selects a 16-byte slot from
    /// queue+0x0C using index queue+0x4C modulo capacity queue+0x6C, then
    /// waits for its flag. This snapshot distinguishes an empty title queue
    /// from a GPU ring stall without fabricating an item or a fence. Both
    /// register guards must match so other titles and XEX revisions do not
    /// get a misleading queue report.
    fn reportHalo3WorkQueueAtRenderWait(self: *const ElfState, context: u64, swaps: u64) void {
        return process_impl_lifecycle.reportHalo3WorkQueueAtRenderWait(self, context, swaps);
    }

    /// Xenia's PPCContext at `ctx`: r[n] at +40+8n, the link register at
    /// +0x130, the condition-register bytes at +0, and the guest stack its
    /// JIT keeps at `[ctx-40]` with its depth at `[ctx-20]`.
    fn reportSpinPowerPcContext(self: *const ElfState, ctx: u64) void {
        return process_impl_lifecycle.reportSpinPowerPcContext(self, ctx);
    }

    /// One guest thread's call frames from its stack, and for each call made
    /// from Xenia's JIT code the PowerPC return address it stored.
    fn reportSpinThreadFrames(self: *const ElfState, index: usize, rip: u64, rsp: u64, rsi: u64) void {
        return process_impl_lifecycle.reportSpinThreadFrames(self, index, rip, rsp, rsi);
    }

    /// Count one step of a running capture and say whether it must be
    /// interpreted; the last one reports what was read and arms the watches.
    fn spinCaptureStep(self: *ElfState) bool {
        return process_impl_lifecycle.spinCaptureStep(self);
    }

    fn noteSpinCaptureRead(self: *ElfState, addr: u64, size: Size, value: u64) void {
        return process_impl_lifecycle.noteSpinCaptureRead(self, addr, size, value);
    }

    /// The captured reads, and a watch on each that is guest memory outside
    /// the spinner's own context and stack frame.
    fn finishSpinCapture(self: *ElfState, slot: usize) void {
        return process_impl_lifecycle.finishSpinCapture(self, slot);
    }

    /// The guest memory around each polled address, as the big-endian words
    /// the PowerPC code reads: the indexes, owners and sibling slots that say
    /// what a flag means.
    fn reportSpinNeighborhoods(self: *const ElfState, windows: *const guest_spin.Neighborhoods, membase: u64) void {
        return process_impl_lifecycle.reportSpinNeighborhoods(self, windows, membase);
    }

    /// A store reached a watched range: who, from where, and with what.
    fn noteSpinWatchWrite(self: *const ElfState, vaddr: u64, width: u64, value: u64, kind: []const u8) void {
        return process_impl_lifecycle.noteSpinWatchWrite(self, vaddr, width, value, kind);
    }

    fn noteSpinWatchBulkWrite(self: *const ElfState, addr: u64, count: u64, kind: []const u8) void {
        return process_impl_lifecycle.noteSpinWatchBulkWrite(self, addr, count, kind);
    }

    /// Every armed watch at a pulse: what it held when armed, what it holds
    /// now, and how many writes reached it.
    fn reportSpinWatchSummary(self: *const ElfState) void {
        return process_impl_lifecycle.reportSpinWatchSummary(self);
    }

    /// A worker read the clock.
    ///
    /// Reads piling up inside one slice are a poll: the thread is waiting for
    /// time to pass, and under one interpreter spinning cannot make time pass,
    /// only keep every other thread from running while it does. Xenia's GPU
    /// frame limiter spins between vblanks by design and its TimerQueue
    /// spin-waits on steady_clock; both now end their slice here instead of
    /// at its limit.
    pub fn noteWindowsGuestClockRead(self: *ElfState) void {
        return process_impl_windows_sync.noteWindowsGuestClockRead(self);
    }

    fn beginWindowsWaitAccounting(
        self: *ElfState,
        thread: *WindowsGuestThread,
        key: u64,
        kind: wait_cost.WaitKind,
        timeout_milliseconds: u64,
        deadline: u64,
    ) void {
        return process_impl_windows_sync.beginWindowsWaitAccounting(self, thread, key, kind, timeout_milliseconds, deadline);
    }

    fn endWindowsWaitAccounting(self: *ElfState, thread: *WindowsGuestThread, outcome: wait_cost.Outcome) void {
        return process_impl_windows_sync.endWindowsWaitAccounting(self, thread, outcome);
    }

    fn endWindowsWaitAccountingIfKind(
        self: *ElfState,
        thread: *WindowsGuestThread,
        kind: wait_cost.WaitKind,
        outcome: wait_cost.Outcome,
    ) void {
        return process_impl_windows_sync.endWindowsWaitAccountingIfKind(self, thread, kind, outcome);
    }

    fn endWindowsHandleWaitAccounting(self: *ElfState, thread: *WindowsGuestThread, outcome: wait_cost.Outcome) void {
        return process_impl_windows_sync.endWindowsHandleWaitAccounting(self, thread, outcome);
    }

    fn noteWindowsWaitSignal(self: *ElfState, key: u64) void {
        return process_impl_windows_sync.noteWindowsWaitSignal(self, key);
    }

    fn endActiveWindowsSrwWaitAccounting(self: *ElfState) void {
        return process_impl_windows_sync.endActiveWindowsSrwWaitAccounting(self);
    }

    /// Park the active worker for a guest-millisecond interval.
    ///
    /// `Sleep(n)` used to return immediately, which turns every timed back-off
    /// in the guest into a busy-wait - including the one Xenia's frame limiter
    /// uses while it waits for a title to open. Returns whether the caller was
    /// a worker that could be parked; the owner has no context to park and
    /// falls back to servicing workers.
    fn activeWindowsApcQueue(self: *ElfState) *WindowsApcQueue {
        return process_impl_windows_sync.activeWindowsApcQueue(self);
    }

    /// `QueueUserAPC(routine, thread, parameter)`. The APC runs the next time
    /// that thread is in an alertable wait; a thread already blocked in one
    /// is made runnable now, so it re-enters the wait and runs it. Xenia's
    /// Win32Thread::QueueUserCallback wakes a guest thread this way so it
    /// delivers the guest APCs NtQueueApcThread just queued; refusing it left
    /// every such thread asleep until its wait ended for another reason.
    pub fn queueWindowsApc(self: *ElfState, handle: u64, routine: u64, parameter: u64) bool {
        return process_impl_windows_sync.queueWindowsApc(self, handle, routine, parameter);
    }

    /// Record whether the wait the active thread is about to block in is
    /// alertable, so a later QueueUserAPC knows whether it may end it.
    pub fn setWindowsWaitAlertable(self: *ElfState, alertable: bool) void {
        return process_impl_windows_sync.setWindowsWaitAlertable(self, alertable);
    }

    /// At an alertable wait's entry: when the thread has APCs queued, run
    /// them here instead of waiting. True when delivery began; the guest is
    /// then at the first routine, and the wait completes with
    /// WAIT_IO_COMPLETION once the last one returns.
    pub fn beginWindowsApcDelivery(self: *ElfState, direct_return_rip: ?u64) bool {
        return process_impl_windows_sync.beginWindowsApcDelivery(self, direct_return_rip);
    }

    /// Call one APC routine below the wait's frame: 64 bytes of room for the
    /// callee's home area, 16-byte alignment, then the return address, so
    /// the routine is entered with rsp at 8 mod 16 as the Windows ABI says.
    fn startNextWindowsApc(self: *ElfState, queue: *WindowsApcQueue) void {
        return process_impl_windows_sync.startNextWindowsApc(self, queue);
    }

    fn continueWindowsApcDelivery(self: *ElfState) void {
        return process_impl_windows_sync.continueWindowsApcDelivery(self);
    }

    pub fn parkWindowsGuestSleep(self: *ElfState, milliseconds: u64) bool {
        return process_impl_windows_sync.parkWindowsGuestSleep(self, milliseconds);
    }

    /// Park the active worker for `ticks` of the guest clock, the precision
    /// `NtDelayExecution` asks in: 100 ns at a time, which a millisecond
    /// `Sleep` would round away. Zero is a yield.
    pub fn parkWindowsGuestDelayTicks(self: *ElfState, ticks: u64) bool {
        return process_impl_windows_sync.parkWindowsGuestDelayTicks(self, ticks);
    }

    /// MinGW's PE pthread implementation stores a pointer to its real mutex
    /// record in the first word of pthread_mutex_t.  The record is guest
    /// memory, not a Rosetta wait-object handle, and the condition-variable
    /// entry point reaches us before the image's own unlock/relock sequence.
    /// Resolve only a guest-backed, sufficiently sized record so an
    /// uninitialized/static sentinel cannot be mistaken for a pointer.
    fn windowsPthreadMutexImpl(self: *const ElfState, address: u64) ?u64 {
        return process_impl_windows_sync.windowsPthreadMutexImpl(self, address);
    }

    pub const WindowsPthreadMutexReleaseResult = enum {
        invalid,
        released,
        already_unlocked,
    };

    pub const WindowsPthreadMutexAcquireResult = union(enum) {
        invalid,
        acquired,
        contended: u64,
    };

    /// Release one MinGW pthread mutex ownership level as the first half of
    /// pthread_cond_wait.  The layout mirrors the PE image's own
    /// pthread_mutex_unlock implementation: state at +0, attributes at +4,
    /// event at +8, recursion depth at +0x10, and owner ID at +0x14.
    /// Rosetta owns the transition while the guest is parked so no host
    /// blocking primitive can strand the single interpreter.
    pub fn releaseWindowsGuestPthreadMutex(self: *ElfState, address: u64) WindowsPthreadMutexReleaseResult {
        return process_impl_windows_sync.releaseWindowsGuestPthreadMutex(self, address);
    }

    /// Try to reacquire the mutex before a condition waiter returns to guest
    /// code.  A contended result carries the mutex's own event handle so the
    /// worker can park on exactly the same object that the image's lock path
    /// would wait on.
    ///
    /// `after_contention` is whether this caller has already parked on the
    /// mutex's event. The image's `pthread_mutex_lock` takes a free mutex
    /// with `xchg state, 1` on its first attempt but with `xchg state, 2`
    /// on every attempt after it has waited, because other waiters may still
    /// be parked on the same auto-reset event and the unlock only calls
    /// `SetEvent` when it swaps a 2 out. Taking it with 1 here erased that
    /// marker: the next unlock saw 1, signalled nobody, and a thread parked
    /// in the image's own lock slept forever. On 2026-09-21 that was Xenia's
    /// GPU thread on the shader-storage mutex, with the Shader Storage
    /// Writer as the condition waiter, and Halo 3 never swapped again.
    pub fn acquireWindowsGuestPthreadMutex(self: *ElfState, address: u64, after_contention: bool) WindowsPthreadMutexAcquireResult {
        return process_impl_windows_sync.acquireWindowsGuestPthreadMutex(self, address, after_contention);
    }

    pub fn windowsSrwLockIndex(self: *const ElfState, address: u64) ?usize {
        return process_impl_windows_sync.windowsSrwLockIndex(self, address);
    }

    fn ensureWindowsSrwLock(self: *ElfState, address: u64) ?*WindowsSrwLock {
        return process_impl_windows_sync.ensureWindowsSrwLock(self, address);
    }

    pub const WindowsSrwAcquireResult = enum {
        invalid,
        acquired,
        contended,
    };

    pub const WindowsConditionWaitResult = enum {
        invalid,
        resumed,
        blocked,
        /// Signalled; the caller hands the mutex back to the image's own
        /// lock (`completeWindowsPthreadConditionRelock`).
        relock,
    };

    pub const WindowsWaitResult = enum {
        invalid,
        signaled,
        yielded,
        blocked,
        timeout,
        unknown,
        /// Parallel mode, the owner: not satisfied yet, and the owner has
        /// already slept for a slice of the wait. The import stays at its
        /// call site and the next step asks again; a finite wait keeps its
        /// original deadline across the retries.
        retry,
    };

    pub fn windowsWaitObjectIndex(self: *const ElfState, handle: u64) ?usize {
        return process_impl_windows_sync.windowsWaitObjectIndex(self, handle);
    }

    fn ensureWindowsWaitObject(self: *ElfState, handle: u64) ?*WindowsWaitObject {
        return process_impl_windows_sync.ensureWindowsWaitObject(self, handle);
    }

    fn noteWindowsWaitObjectCreated(self: *ElfState, object: *WindowsWaitObject) void {
        return process_impl_windows_sync.noteWindowsWaitObjectCreated(self, object);
    }

    fn noteWindowsWaitObjectSignaled(self: *ElfState, object: *WindowsWaitObject) void {
        return process_impl_windows_sync.noteWindowsWaitObjectSignaled(self, object);
    }

    /// `CloseHandle` on an event, mutex, semaphore or thread handle.
    ///
    /// Nothing freed these, so every object a guest ever created held its
    /// slot for the rest of the run: 416 events were registered on
    /// 2026-09-14 before the title drew anything, against a table of 512,
    /// and the object after a full table had no wait model at all. A handle
    /// a parked thread is still waiting on keeps its object until the thread
    /// leaves, as Windows keeps an object alive while a wait holds it.
    /// Returns whether the handle was a wait object.
    pub fn closeWindowsWaitObject(self: *ElfState, handle: u64) bool {
        return process_impl_windows_sync.closeWindowsWaitObject(self, handle);
    }

    /// CreateFile with every file slot in use.
    pub fn noteWindowsFileTableFull(self: *ElfState) void {
        return process_impl_windows_sync.noteWindowsFileTableFull(self);
    }

    /// CreateFileMapping with every mapping slot in use.
    pub fn noteWindowsFileMappingTableFull(self: *ElfState, handle: u64) void {
        return process_impl_windows_sync.noteWindowsFileMappingTableFull(self, handle);
    }

    /// A kernel object with no slot to hold its wait model.
    fn noteWindowsWaitObjectTableFull(self: *ElfState, handle: u64) void {
        return process_impl_windows_sync.noteWindowsWaitObjectTableFull(self, handle);
    }

    pub fn registerWindowsTimer(self: *ElfState, handle: u64, manual_reset: bool) void {
        return process_impl_windows_sync.registerWindowsTimer(self, handle, manual_reset);
    }

    /// SetWaitableTimer. `due` is the guest's LARGE_INTEGER: negative is a
    /// relative interval in 100 ns, positive an absolute FILETIME, which is
    /// measured against `now_filetime` - the same clock the guest's
    /// GetSystemTimePreciseAsFileTime reads, so Xenia's `SetOnceAt` (an
    /// absolute time it computed from that call) lands where it meant.
    pub fn setWindowsTimer(self: *ElfState, handle: u64, due: i64, period_ms: u64, now_filetime: u64, completion_routine: u64) bool {
        return process_impl_windows_sync.setWindowsTimer(self, handle, due, period_ms, now_filetime, completion_routine);
    }

    /// CancelWaitableTimer disarms without changing the signalled state.
    pub fn cancelWindowsTimer(self: *ElfState, handle: u64) bool {
        return process_impl_windows_sync.cancelWindowsTimer(self, handle);
    }

    /// Fire a timer whose due tick has passed: signal it and re-arm a
    /// periodic one past `now` (missed periods are skipped, not replayed as
    /// a burst).
    fn advanceWindowsTimer(self: *ElfState, object: *WindowsWaitObject, now: u64) void {
        return process_impl_windows_sync.advanceWindowsTimer(self, object, now);
    }

    pub fn fireDueWindowsTimers(self: *ElfState, now: u64) u64 {
        return process_impl_windows_sync.fireDueWindowsTimers(self, now);
    }

    pub fn registerWindowsEvent(self: *ElfState, handle: u64, manual_reset: bool, initial_state: bool) void {
        return process_impl_windows_sync.registerWindowsEvent(self, handle, manual_reset, initial_state);
    }

    pub fn registerWindowsMutex(self: *ElfState, handle: u64, initially_owned: bool) void {
        return process_impl_windows_sync.registerWindowsMutex(self, handle, initially_owned);
    }

    pub fn registerWindowsSemaphore(self: *ElfState, handle: u64, initial_count: u64, maximum_count: u64) void {
        return process_impl_windows_sync.registerWindowsSemaphore(self, handle, initial_count, maximum_count);
    }

    pub fn registerWindowsThreadWaitObject(self: *ElfState, handle: u64) void {
        return process_impl_windows_sync.registerWindowsThreadWaitObject(self, handle);
    }

    pub fn windowsWaitObjectReady(self: *const ElfState, handle: u64) ?bool {
        return process_impl_windows_sync.windowsWaitObjectReady(self, handle);
    }

    /// Emit the Xbox event and guest lock snapshot at the moment a thread
    /// parks on the event Xenia's own RtlEnterCriticalSection waits on. With
    /// the bridge armed (parallel mode) that path is not taken for a readable
    /// section; this names the cooperative-mode wait, and any wait the bridge
    /// had to leave to Xenia.
    pub fn noteXboxCriticalSectionWaitProvenance(
        self: *ElfState,
        thread: *WindowsGuestThread,
        handle: u64,
        timeout: u64,
    ) void {
        return process_impl_windows_sync.noteXboxCriticalSectionWaitProvenance(self, thread, handle, timeout);
    }

    fn windowsWaitObjectKindName(self: *const ElfState, handle: u64) []const u8 {
        return process_impl_windows_sync.windowsWaitObjectKindName(self, handle);
    }

    pub fn windowsGuestWaitServiceSlice(self: *const ElfState) u64 {
        return process_impl_windows_sync.windowsGuestWaitServiceSlice(self);
    }

    /// Service a worker from an explicit owner-side wait/message/lock
    /// boundary subject to the scheduler's separate owner stride.  A real
    /// blocked owner still uses `serviceWindowsGuestThreads` directly from
    /// the outer wait loop; this gate is only for boundaries that return
    /// immediately and can therefore be hit thousands of times in a tight
    /// guest UI loop.
    pub fn serviceWindowsGuestBoundary(self: *ElfState, max_steps: u64) u64 {
        return process_impl_windows_sync.serviceWindowsGuestBoundary(self, max_steps);
    }

    fn traceWindowsWaitDecision(self: *ElfState, handle: u64, timeout: u64, result: WindowsWaitResult) void {
        return process_impl_windows_sync.traceWindowsWaitDecision(self, handle, timeout, result);
    }

    pub fn windowsWaitObjectSignaled(self: *const ElfState, handle: u64) bool {
        return process_impl_windows_sync.windowsWaitObjectSignaled(self, handle);
    }

    /// Report whether a handle belongs to Rosetta's synthetic Windows wait
    /// table.  NT synchronization calls need to distinguish an unsignaled
    /// known object from an invalid handle; treating both as STATUS_SUCCESS
    /// lets a guest walk past the kernel contract and leaves the real waiter
    /// permanently disconnected from its signaler.
    pub fn windowsWaitObjectKnown(self: *const ElfState, handle: u64) bool {
        return process_impl_windows_sync.windowsWaitObjectKnown(self, handle);
    }

    /// Return the current semaphore count for the NT previous-count ABI.
    /// Other wait-object kinds intentionally return null rather than exposing
    /// their signaled bit as a count.
    pub fn windowsWaitObjectSemaphoreCount(self: *const ElfState, handle: u64) ?u32 {
        return process_impl_windows_sync.windowsWaitObjectSemaphoreCount(self, handle);
    }

    pub fn consumeWindowsWaitObject(self: *ElfState, handle: u64) void {
        return process_impl_windows_sync.consumeWindowsWaitObject(self, handle);
    }

    fn wakeWindowsGuestThreadsForWait(self: *ElfState, handle: u64, wake_all: bool) u64 {
        return process_impl_windows_sync.wakeWindowsGuestThreadsForWait(self, handle, wake_all);
    }

    /// Wake one matching worker while retaining the handle and one-shot
    /// result long enough for its original wait import to return correctly.
    /// Null means this thread did not wait on the object; true means a
    /// wait-all recheck rather than a consumed signal.
    fn wakeWindowsGuestWaiterForHandle(self: *ElfState, thread: *WindowsGuestThread, handle: u64) ?bool {
        return process_impl_windows_sync.wakeWindowsGuestWaiterForHandle(self, thread, handle);
    }

    /// Wake finite waits whose guest-clock deadline has elapsed.
    ///
    /// The deadline is in the same ticks Rosetta hands the guest from
    /// `QueryPerformanceCounter`, so a thread that sleeps for a millisecond
    /// and a thread that measures a millisecond agree. It is deliberately not
    /// the owner's step counter: that counter stops advancing whenever the
    /// scheduler is running workers, which is most of the run, so a deadline
    /// expressed in it stretches by however much other work the process is
    /// doing.
    pub fn wakeExpiredWindowsGuestWaits(self: *ElfState) u64 {
        return process_impl_windows_sync.wakeExpiredWindowsGuestWaits(self);
    }

    /// Make a synthetic event/mutex/semaphore ready and release any workers
    /// parked on it.  The worker retains a one-shot resume marker so its next
    /// turn retries the original wait and receives WAIT_OBJECT_0 naturally.
    pub fn signalWindowsWaitObject(self: *ElfState, handle: u64, pulse: bool) u64 {
        return process_impl_windows_sync.signalWindowsWaitObject(self, handle, pulse);
    }

    /// End the running worker's slice now if the owner is waiting on
    /// `handle`, so the owner's next instruction (which re-enters the wait)
    /// finds it signalled before the worker can consume it again.
    fn handOffToWaitingOwner(self: *ElfState, handle: u64) void {
        return process_impl_windows_sync.handOffToWaitingOwner(self, handle);
    }

    pub fn setOwnerWaitHandles(self: *ElfState, handles: []const u64) void {
        return process_impl_windows_sync.setOwnerWaitHandles(self, handles);
    }

    pub fn resetWindowsWaitObject(self: *ElfState, handle: u64) bool {
        return process_impl_windows_sync.resetWindowsWaitObject(self, handle);
    }

    pub fn releaseWindowsMutex(self: *ElfState, handle: u64) bool {
        return process_impl_windows_sync.releaseWindowsMutex(self, handle);
    }

    pub fn releaseWindowsSemaphore(self: *ElfState, handle: u64, release_count: u64) bool {
        return process_impl_windows_sync.releaseWindowsSemaphore(self, handle, release_count);
    }

    /// Apply Win32 wait semantics at the cooperative boundary.  A worker
    /// that waits on a known unsignaled object is parked at the import stub;
    /// it is resumed by the object's signal/completion instead of receiving a
    /// fabricated success and spinning through the same wait forever.
    pub fn waitWindowsGuestObject(self: *ElfState, handle: u64, timeout: u64) WindowsWaitResult {
        return process_impl_windows_sync.waitWindowsGuestObject(self, handle, timeout);
    }

    /// `WaitForMultipleObjects` with Win32's semantics at the cooperative
    /// boundary.
    ///
    /// A wait-any takes the first ready object and answers its index; a
    /// wait-all takes every object at once or none. A worker with nothing
    /// ready parks on all its handles, and whichever is signalled first
    /// hands itself over as it wakes the thread, the way a single wait does.
    pub fn waitWindowsGuestObjects(self: *ElfState, handles: []const u64, wait_all: bool, timeout: u64) WindowsMultiWaitResult {
        return process_impl_windows_sync.waitWindowsGuestObjects(self, handles, wait_all, timeout);
    }

    /// Take the objects a multi-object wait is satisfied by, or null.
    fn takeReadyWindowsWaitObjects(self: *ElfState, handles: []const u64, wait_all: bool) ?WindowsMultiWaitResult {
        return process_impl_windows_sync.takeReadyWindowsWaitObjects(self, handles, wait_all);
    }

    fn clearActiveMultiWaitDeadline(self: *ElfState) void {
        return process_impl_windows_sync.clearActiveMultiWaitDeadline(self);
    }

    /// A wait on a handle with no event, mutex, semaphore or thread behind it.
    ///
    /// Any answer is invented: WAIT_OBJECT_0 claims an object was acquired
    /// that does not exist, and WAIT_TIMEOUT claims time passed for nothing.
    pub fn faultWindowsWaitUnknownHandle(self: *ElfState, handle: u64, api: []const u8) void {
        return process_impl_windows_sync.faultWindowsWaitUnknownHandle(self, handle, api);
    }

    /// The site a timed wait comes from, by the address it returns to, plus
    /// one; zero when the table is full.
    pub fn noteWindowsTimedWaitSite(self: *ElfState, caller: u64, slot: usize, milliseconds: u64) u8 {
        return process_impl_windows_sync.noteWindowsTimedWaitSite(self, caller, slot, milliseconds);
    }

    const TimedWaitOutcome = enum { timeout, signalled, immediate };

    pub fn countWindowsTimedWaitOutcome(self: *ElfState, site: u8, outcome: TimedWaitOutcome) void {
        return process_impl_windows_sync.countWindowsTimedWaitOutcome(self, site, outcome);
    }

    /// Keep the last concrete wait identity beside the site aggregate. The
    /// first ten expiry records already carry this information, but retaining
    /// it here makes the final site line actionable even when the run is too
    /// long for a reader to scroll back to those samples.
    fn rememberWindowsTimedWaitContext(
        self: *ElfState,
        site: u8,
        slot: usize,
        condition: u64,
        mutex: u64,
    ) void {
        return process_impl_windows_sync.rememberWindowsTimedWaitContext(self, site, slot, condition, mutex);
    }

    /// Emit the first ten deadline expiries with enough context to identify
    /// the waiter, not merely the fact that a periodic wait happened. The
    /// aggregate counters remain unbounded; only this detailed sample is
    /// bounded so a 500 ms poll cannot dominate a long Xenia run's log.
    pub fn noteWindowsTimedConditionTimeout(self: *ElfState, thread: *const WindowsGuestThread, slot: usize, now: u64) void {
        return process_impl_windows_sync.noteWindowsTimedConditionTimeout(self, thread, slot, now);
    }

    /// Where timed condition waits come from and how they end, busiest first
    /// up to `limit` sites.
    fn reportWindowsTimedWaitSites(self: *const ElfState, limit: usize) void {
        return process_impl_windows_sync.reportWindowsTimedWaitSites(self, limit);
    }

    /// Publish MinGW's `pthread_cond_timedwait_impl`: the body that both
    /// `pthread_cond_timedwait` and `pthread_cond_timedwait_relative_np`
    /// tail-jump into, with a fourth argument saying which of them it is.
    pub fn configureWindowsTimedConditionEntry(self: *ElfState, entry: ?u64) void {
        return process_impl_windows_sync.configureWindowsTimedConditionEntry(self, entry);
    }

    /// The milliseconds a winpthreads timed wait asks for, computed as the
    /// image computes them: seconds times 1000 plus the nanoseconds rounded
    /// up, and for an absolute time, less the wall clock the guest reads
    /// through GetSystemTimeAsFileTime. A time already past is zero. Null
    /// for an unreadable timespec, which is left to the image's own code.
    pub fn windowsPthreadTimespecMilliseconds(self: *const ElfState, timespec: u64, relative: bool) ?u64 {
        return process_impl_windows_sync.windowsPthreadTimespecMilliseconds(self, timespec, relative);
    }

    /// `pthread_cond_timedwait` on Rosette's condition model.
    ///
    /// Untimed waits, signals and broadcasts were already Rosette's; timed
    /// waits ran the image's own semaphore code, which no Rosette signal ever
    /// reaches. A notified timed waiter slept out its whole timeout, and that
    /// semaphore and cancel-event path is where discord-rpc's IO thread spent
    /// 27% of the 2026-09-14 run.
    fn shimWindowsPthreadTimedCondition(self: *ElfState, return_rip: ?u64) bool {
        return process_impl_windows_sync.shimWindowsPthreadTimedCondition(self, return_rip);
    }

    /// Publish the utf8 find_any_of entry the loader found. A setter rather
    /// than a bare field store because the address also has to enter the box
    /// `step` consults before calling `tryWindowsGuestCompatibility`.
    pub fn configureWindowsUtf8FindAnyOfEntry(self: *ElfState, entry: ?u64) void {
        return process_impl_windows_sync.configureWindowsUtf8FindAnyOfEntry(self, entry);
    }

    /// Publish Xenia's exact UTF-8 count entry for diagnostics. This hook only
    /// inspects the input view; the guest implementation still executes.
    pub fn configureWindowsUtf8CountEntry(self: *ElfState, entry: ?u64) void {
        return process_impl_windows_sync.configureWindowsUtf8CountEntry(self, entry);
    }

    pub fn noteWindowsUtf8CountObserved(self: *ElfState) u64 {
        return process_impl_windows_sync.noteWindowsUtf8CountObserved(self);
    }

    /// Publish fmt's exact formatter boundaries from the PE's COFF symbols.
    /// The symbols are diagnostic-only; original guest instructions still
    /// execute at both addresses.
    pub fn configureWindowsFmtEntries(self: *ElfState, vformat: ?u64, vformat_to: ?u64) void {
        return process_impl_windows_sync.configureWindowsFmtEntries(self, vformat, vformat_to);
    }

    /// Read-only probe called at formatter entries, their returns, and for
    /// the short interval between them. It is armed only for fmt::vformat
    /// invoked from Xenia's config::SaveConfig, which is the malformed TOML
    /// line observed at xe::utf8::count.
    pub fn noteWindowsFmtProbeInstruction(self: *ElfState) void {
        return process_impl_windows_sync.noteWindowsFmtProbeInstruction(self);
    }

    fn logWindowsFmtArguments(self: *ElfState, stage: []const u8, view_address: u64, args_address: u64, output_address: u64) void {
        return process_impl_windows_sync.logWindowsFmtArguments(self, stage, view_address, args_address, output_address);
    }

    fn logWindowsFmtBuffer(self: *ElfState, stage: []const u8, buffer_address: u64) void {
        return process_impl_windows_sync.logWindowsFmtBuffer(self, stage, buffer_address);
    }

    fn logWindowsFmtString(self: *ElfState, stage: []const u8, string_address: u64) void {
        return process_impl_windows_sync.logWindowsFmtString(self, stage, string_address);
    }

    pub fn reportWindowsFmtProbeDiagnostics(self: *const ElfState) void {
        return process_impl_windows_sync.reportWindowsFmtProbeDiagnostics(self);
    }

    /// Publish the exact Itanium C++ `__cxa_throw` boundary. The observer is
    /// diagnostic-only and lets the original exception implementation run.
    pub fn configureWindowsCxaThrowEntry(self: *ElfState, entry: ?u64) void {
        return process_impl_windows_sync.configureWindowsCxaThrowEntry(self, entry);
    }

    pub fn noteWindowsCxaThrowObserved(self: *ElfState) void {
        return process_impl_windows_sync.noteWindowsCxaThrowObserved(self);
    }

    /// Retain a bounded guest-address to host-file mapping for successful
    /// reads. A later exception can then identify the file offset that
    /// supplied the offending byte without keeping any borrowed pointers.
    pub fn noteWindowsFileReadProvenance(
        self: *ElfState,
        guest_start: u64,
        byte_count: u64,
        file_offset: u64,
        api: []const u8,
        path: []const u8,
    ) void {
        return process_impl_windows_sync.noteWindowsFileReadProvenance(self, guest_start, byte_count, file_offset, api, path);
    }

    /// Return the newest read record covering an address. Newer records take
    /// precedence because guest allocators can reuse the same virtual range.
    pub fn windowsFileReadProvenanceAt(self: *const ElfState, address: u64) ?WindowsFileReadProvenance {
        return process_impl_windows_sync.windowsFileReadProvenanceAt(self, address);
    }

    /// If a parser failure cannot be tied to one read buffer, preserve the
    /// bounded read history as candidates. This lets a later run identify the
    /// input file even when the parser's cursor was copied out of the original
    /// ReadFile destination before it reached utf8::next.
    pub fn reportWindowsFileReadCandidates(self: *const ElfState) void {
        return process_impl_windows_sync.reportWindowsFileReadCandidates(self);
    }

    /// Report an invalid UTF-8 exception and, when the observed frame matches
    /// `utf8::next`, the source cursor and its owning consumer. Stack offsets
    /// are interpreted by the caller only after checking the resolved symbol
    /// and saved RSI value.
    pub fn noteWindowsInvalidUtf8Throw(
        self: *ElfState,
        thrown_object: u64,
        type_name: []const u8,
        invalid_octet: u8,
        throw_site: u64,
        iterator_ref: u64,
        source_address: u64,
        source_readable: bool,
        source_byte: u8,
        source_byte_matches_exception: bool,
        consumer: u64,
        iterator_ref_consistent: bool,
        live_rsi: u64,
        saved_rsi_slot: u64,
        saved_rsi_readable: bool,
        saved_rsi: u64,
        saved_source_address: u64,
        saved_source_readable: bool,
        saved_source_byte: u8,
        saved_source_matches_exception: bool,
        live_source_address: u64,
        live_source_readable: bool,
        live_source_byte: u8,
        live_source_matches_exception: bool,
    ) void {
        return process_impl_windows_sync.noteWindowsInvalidUtf8Throw(self, thrown_object, type_name, invalid_octet, throw_site, iterator_ref, source_address, source_readable, source_byte, source_byte_matches_exception, consumer, iterator_ref_consistent, live_rsi, saved_rsi_slot, saved_rsi_readable, saved_rsi, saved_source_address, saved_source_readable, saved_source_byte, saved_source_matches_exception, live_source_address, live_source_readable, live_source_byte, live_source_matches_exception);
    }

    pub fn reportWindowsCxaThrowDiagnostics(self: *const ElfState) void {
        return process_impl_windows_sync.reportWindowsCxaThrowDiagnostics(self);
    }

    /// Called by the diagnostic observer only when the guest string_view is
    /// malformed. The sample is bounded and copied through the TSO-aware
    /// guest-memory path so the report reflects the bytes the guest sees.
    pub fn noteWindowsUtf8CountInvalidInput(
        self: *ElfState,
        call_number: u64,
        view_address: u64,
        view_word0: u64,
        view_word1: u64,
        data_address: u64,
        length: u64,
        byte_offset: u64,
        invalid_byte: u8,
        caller: u64,
        caller_rsp: u64,
    ) void {
        return process_impl_windows_sync.noteWindowsUtf8CountInvalidInput(self, call_number, view_address, view_word0, view_word1, data_address, length, byte_offset, invalid_byte, caller, caller_rsp);
    }

    pub fn reportWindowsUtf8CountDiagnostics(self: *const ElfState) void {
        return process_impl_windows_sync.reportWindowsUtf8CountDiagnostics(self);
    }

    /// Publish the exact guest `codecvt_utf8_utf16<wchar_t>::do_in` entry
    /// found in the PE's COFF symbol table.
    pub fn configureWindowsCodecvtInEntry(self: *ElfState, entry: ?u64) void {
        return process_impl_windows_sync.configureWindowsCodecvtInEntry(self, entry);
    }

    /// Recompute the compatibility-hook set from every address
    /// `tryWindowsGuestCompatibility` compares RIP against. Called by the
    /// setters that assign those fields; a field assigned any other way
    /// would leave its hook unreachable, which is why there are setters.
    fn rebuildWindowsCompatHookBox(self: *ElfState) void {
        return process_impl_windows_sync.rebuildWindowsCompatHookBox(self);
    }

    /// Publish the PE-local pthread condition-variable entry points that the
    /// loader found in executable bytes.  Keeping discovery in the PE intake
    /// and policy in the executor means a rebuilt Xenia image can move these
    /// routines without requiring a Rosetta or Xenia address edit.
    pub fn configureWindowsMutexLockEntry(self: *ElfState, entry: ?u64) void {
        return process_impl_windows_sync.configureWindowsMutexLockEntry(self, entry);
    }

    pub fn configureWindowsConditionEntries(
        self: *ElfState,
        wait_entry: ?u64,
        signal_entry: ?u64,
        broadcast_entry: ?u64,
    ) void {
        return process_impl_windows_sync.configureWindowsConditionEntries(self, wait_entry, signal_entry, broadcast_entry);
    }

    /// Complete the PE-local MinGW pthread condition functions at their
    /// executable entry points when the cooperative policy is enabled.
    ///
    /// Xenia links these routines into the image instead of importing them,
    /// so the ordinary import dispatcher never sees the wait. Returning
    /// success from the underlying Win32 wait is not equivalent here: the
    /// caller is commonly a predicate loop that assumes the condition wait
    /// only returned after a matching signal. In particular, KernelState's
    /// dispatch worker would otherwise wake on an empty queue and invoke the
    /// list sentinel as a std::function.
    ///
    /// The call boundary deliberately remains at the caller's RIP while a
    /// worker is blocked. The worker context is therefore resumed at the
    /// same direct call, observes the one-shot condition-resume marker, and
    /// this shim completes the call without entering the image's
    /// host-oriented semaphore implementation.
    /// Leave a signalled `pthread_cond_wait` by calling the image's
    /// `pthread_mutex_lock_intern(mutex, INFINITE)` in its place. Its return
    /// value (0) is `pthread_cond_wait`'s, and it returns to the same caller:
    /// a tail-jumped wait already has that caller's return address at
    /// [rsp]; a called one gets it pushed, exactly as the call would have.
    fn completeWindowsPthreadConditionRelock(self: *ElfState, mutex: u64, return_rip: ?u64) void {
        return process_impl_windows_sync.completeWindowsPthreadConditionRelock(self, mutex, return_rip);
    }

    fn completeWindowsPthreadConditionReturn(self: *ElfState, return_rip: ?u64) void {
        return process_impl_windows_sync.completeWindowsPthreadConditionReturn(self, return_rip);
    }

    pub fn tryWindowsPthreadConditionShim(self: *ElfState, target: u64, return_rip: ?u64) bool {
        return process_impl_windows_sync.tryWindowsPthreadConditionShim(self, target, return_rip);
    }

    /// Initialize the Rosetta-side ownership record and the guest SRW word.
    /// The guest word remains present because Xenia also uses the native
    /// layout as a cheap state check around its recursive mutex wrapper.
    pub fn initializeWindowsSrwLock(self: *ElfState, address: u64) bool {
        return process_impl_windows_sync.initializeWindowsSrwLock(self, address);
    }

    /// Acquire an SRW lock without pretending that a void-returning Win32
    /// API is always immediately successful.  A contended result is handled
    /// by the import layer: worker contexts block and the owner continues.
    /// Image code addresses on a guest stack, innermost first: the return
    /// addresses of the frames above `rsp`, plus whatever stale code
    /// pointers share the scanned words. For naming a lock's owner frame,
    /// not for unwinding.
    fn windowsGuestStackCodeAddresses(self: *const ElfState, rsp: u64, out: *[windows_srw_owner_stack_depth]u64) void {
        return process_impl_windows_sync.windowsGuestStackCodeAddresses(self, rsp, out);
    }

    fn captureWindowsSrwOwnerStack(self: *ElfState, lock: *WindowsSrwLock, rsp: u64) void {
        return process_impl_windows_sync.captureWindowsSrwOwnerStack(self, lock, rsp);
    }

    /// Complete the common IAT SRW calls directly from translated code,
    /// retaining the same runtime lock and owner/waiter implementation.
    /// Contended acquisition declines before mutation, so the ordinary import
    /// path still owns its parking and retry protocol.
    pub fn tryWindowsSrwImport(self: *ElfState, name: []const u8, return_rip: ?u64) bool {
        return process_impl_windows_sync.tryWindowsSrwImport(self, name, return_rip);
    }

    pub fn acquireWindowsSrwLock(self: *ElfState, address: u64) WindowsSrwAcquireResult {
        return process_impl_windows_sync.acquireWindowsSrwLock(self, address);
    }

    /// Queue the owner context behind an SRW lock it could not take.
    pub fn noteWindowsOwnerSrwWait(self: *ElfState, address: u64) void {
        return process_impl_windows_sync.noteWindowsOwnerSrwWait(self, address);
    }

    pub fn windowsCriticalSectionIndex(self: *const ElfState, address: u64) ?usize {
        return process_impl_windows_sync.windowsCriticalSectionIndex(self, address);
    }

    /// The record of a Win32 section being entered: the existing record, or a
    /// new one. Null for an unreadable object or a full table, where the
    /// enter runs unexcluded, as every enter used to.
    fn ensureCriticalSection(self: *ElfState, address: u64, layout: xbox_critical_section.Layout) ?*WindowsSrwLock {
        return process_impl_windows_sync.ensureCriticalSection(self, address, layout);
    }

    fn ensureWindowsCriticalSection(self: *ElfState, address: u64) ?*WindowsSrwLock {
        return process_impl_windows_sync.ensureWindowsCriticalSection(self, address);
    }

    /// Mirror the shared owner/waiter record into the guest's
    /// CRITICAL_SECTION. Xbox sections never have a record: their state is
    /// the guest structure itself (`handleXboxCriticalSectionExport`).
    fn publishCriticalSection(self: *ElfState, section: *const WindowsSrwLock) void {
        return process_impl_windows_sync.publishCriticalSection(self, section);
    }

    /// A section nobody holds, waits on or has been handed: its record goes
    /// back, so the table holds only the sections in use right now.
    fn retireIdleWindowsCriticalSection(self: *ElfState, section: *WindowsSrwLock) void {
        return process_impl_windows_sync.retireIdleWindowsCriticalSection(self, section);
    }

    /// `EnterCriticalSection`, with real mutual exclusion: recursive for its
    /// owner, contended for everyone else, and handed to the longest waiter
    /// on release through the SRW machinery (`handOffWindowsSrwLock`).
    ///
    /// Every Enter/Leave used to answer at once and change nothing - which
    /// was harmless while one host thread ran every guest thread, and no
    /// exclusion at all once they ran in parallel. Xenia's image enters
    /// critical sections in libusb (its event lists and transfer locks),
    /// SDL's Windows mutexes, winpthreads' condition variables, MinGW's
    /// atexit and TLS-destructor lists and the gdtoa lock `printf` takes.
    pub fn enterWindowsCriticalSection(self: *ElfState, address: u64) WindowsSrwAcquireResult {
        return process_impl_windows_sync.enterWindowsCriticalSection(self, address);
    }

    /// `TryEnterCriticalSection`: enter only if nobody else holds it.
    pub fn tryEnterWindowsCriticalSection(self: *ElfState, address: u64) bool {
        return process_impl_windows_sync.tryEnterWindowsCriticalSection(self, address);
    }

    /// Queue the owner context behind a critical section it could not
    /// enter (see `noteWindowsOwnerSrwWait`).
    pub fn noteWindowsOwnerCriticalSectionWait(self: *ElfState, address: u64) void {
        return process_impl_windows_sync.noteWindowsOwnerCriticalSectionWait(self, address);
    }

    /// `LeaveCriticalSection`: one level down, and at zero the section goes
    /// to its longest waiter, or back to free.
    pub fn leaveWindowsCriticalSection(self: *ElfState, address: u64) void {
        return process_impl_windows_sync.leaveWindowsCriticalSection(self, address);
    }

    /// One Xbox Rtl critical-section export call, decoded from the caller's
    /// PPCContext the way Xenia's `Trampoline(PPCContext*)` decodes it.
    const XboxCriticalSectionCall = struct {
        /// The PPCContext: `rcx` at the trampoline.
        context: u64,
        membase: u64,
        /// r3, the section's guest address. Zero is a null section.
        guest: u32,
        /// r4, the spin count of `...AndSpinCount`.
        argument: u32,
        /// The 28-byte structure's host address; zero for a null section.
        section: u64,
    };

    /// One section, reached through the same coordinated scalar accessors
    /// guest loads and stores use, so the bridge and translated code agree on
    /// every byte and every ordering.
    pub const XboxSectionAccess = struct {
        state: *ElfState,
        section: u64,

        pub fn fence(_: XboxSectionAccess) void {
            tso_memory.memoryFence();
        }
        pub fn loadByte(self: XboxSectionAccess, offset: u8) u8 {
            return self.state.read8(self.section + offset);
        }
        pub fn storeByte(self: XboxSectionAccess, offset: u8, value: u8) void {
            self.state.write8(self.section + offset, value);
        }
        pub fn loadBig(self: XboxSectionAccess, offset: u8) u32 {
            return @byteSwap(self.state.read32(self.section + offset));
        }
        pub fn storeBig(self: XboxSectionAccess, offset: u8, value: u32) void {
            self.state.write32(self.section + offset, @byteSwap(value));
        }
        pub fn loadLock(self: XboxSectionAccess) i32 {
            return @bitCast(self.state.read32(self.section + xbox_critical_section.Offset.lock_count));
        }
        pub fn storeLock(self: XboxSectionAccess, value: i32) void {
            self.state.write32(self.section + xbox_critical_section.Offset.lock_count, @bitCast(value));
        }
        pub fn lockFetchAdd(self: XboxSectionAccess, delta: i32) i32 {
            return self.state.xboxLockFetchAdd(self.section, delta);
        }
        pub fn lockCompareExchange(self: XboxSectionAccess, expected: i32, desired: i32) bool {
            return self.state.xboxLockCompareExchange(self.section, expected, desired);
        }
    };

    /// Whether `count` bytes at `address` have a host backing.
    fn xboxHostBacked(self: *ElfState, address: u64, count: u64) bool {
        return process_impl_windows_sync.xboxHostBacked(self, address, count);
    }

    /// The lock word's host backing. Unlike `atomicMemoryOperand` this does
    /// not consult the software page protection: a section has one authority
    /// whatever Xenia does to protect the page around it, and the host page
    /// itself is never protected.
    fn xboxLockWord(self: *ElfState, section: u64) ?[]u8 {
        return process_impl_windows_sync.xboxLockWord(self, section);
    }

    /// LOCK XADD on lock_count; returns the value before the add.
    fn xboxLockFetchAdd(self: *ElfState, section: u64, delta: i32) i32 {
        return process_impl_windows_sync.xboxLockFetchAdd(self, section, delta);
    }

    /// LOCK CMPXCHG on lock_count.
    fn xboxLockCompareExchange(self: *ElfState, section: u64, expected: i32, desired: i32) bool {
        return process_impl_windows_sync.xboxLockCompareExchange(self, section, expected, desired);
    }

    /// Read one call's arguments where Xenia's trampoline reads them. Null
    /// when the context or a non-null section has no backing: Xenia's own
    /// code then runs and faults exactly as it would have.
    pub fn decodeXboxCriticalSectionCall(self: *ElfState) ?XboxCriticalSectionCall {
        return process_impl_windows_sync.decodeXboxCriticalSectionCall(self);
    }

    /// The caller's X_KTHREAD: what Xenia's own implementation writes as a
    /// section's owner (`XThread::guest_object()`), kept in the PCR's
    /// `prcb_data.current_thread`, with the PCR in r13. A worker reads it
    /// once per PPCContext.
    fn xboxCurrentKthread(self: *ElfState, call: XboxCriticalSectionCall) u32 {
        return process_impl_windows_sync.xboxCurrentKthread(self, call);
    }

    /// The section this context has counted itself into, if any.
    fn xboxPendingWait(self: *ElfState) u64 {
        return process_impl_windows_sync.xboxPendingWait(self);
    }

    /// Xenia's `Result::Store`: `r[3] = uint64_t(int32_t(value))`.
    fn storeXboxCallResult(self: *ElfState, call: XboxCriticalSectionCall, value: u32) void {
        return process_impl_windows_sync.storeXboxCallResult(self, call, value);
    }

    pub const XboxWait = enum { acquired, parked, owner_parked, unparkable };

    /// A counted waiter's turn, under the runtime lock: collect a release's
    /// grant or the event's pending wake, or park until a release grants one.
    pub fn awaitXboxCriticalSection(self: *ElfState, call: XboxCriticalSectionCall, me: u32) XboxWait {
        return process_impl_windows_sync.awaitXboxCriticalSection(self, call, me);
    }

    /// A release left a counted waiter: hand the section to the longest
    /// parked one, or set the embedded event for a waiter that has counted
    /// itself and not parked yet - the one wake an auto-reset event holds.
    /// Runs under the runtime lock, as every wait decision does.
    fn releaseXboxCriticalSectionWaiter(self: *ElfState, section: u64) void {
        return process_impl_windows_sync.releaseXboxCriticalSectionWaiter(self, section);
    }

    fn completeXboxCriticalSectionCall(self: *ElfState, api: xbox_critical_section.Export, return_rip: u64) bool {
        return process_impl_windows_sync.completeXboxCriticalSectionCall(self, api, return_rip);
    }

    /// Complete an Xbox kernel critical-section trampoline without entering
    /// Xenia, at its first instruction and before any lock. Uncontended
    /// calls are a few atomic operations on the guest structure; only a
    /// counted waiter, or a release that finds one, takes the runtime lock.
    /// False only for a call Xenia must run itself: an unreadable PPCContext
    /// or section, or a null section being initialized.
    pub fn handleXboxCriticalSectionExport(self: *ElfState, api: xbox_critical_section.Export) bool {
        return process_impl_windows_sync.handleXboxCriticalSectionExport(self, api);
    }

    /// Which thread a guest KTHREAD is, for a report: the worker whose PCR
    /// named it.
    fn windowsThreadForXboxKthread(self: *const ElfState, kthread: u32) ?*const WindowsGuestThread {
        return process_impl_windows_sync.windowsThreadForXboxKthread(self, kthread);
    }

    /// `InitializeCriticalSection*`: a section starts free. A record left by
    /// a previous life of the same memory is dropped unless someone waits on
    /// it.
    pub fn initializeWindowsCriticalSection(self: *ElfState, address: u64) void {
        return process_impl_windows_sync.initializeWindowsCriticalSection(self, address);
    }

    /// `DeleteCriticalSection`: its record goes, unless a thread still waits
    /// on it - that waiter is woken to find the section free.
    pub fn deleteWindowsCriticalSection(self: *ElfState, address: u64) void {
        return process_impl_windows_sync.deleteWindowsCriticalSection(self, address);
    }

    /// Give a released SRW lock directly to its longest waiter.
    ///
    /// Waking every waiter and letting them race is fair on a preemptive
    /// scheduler and starvation on this one. On the 2026-09-13 run Xenia's
    /// global mutex took 235,910 contentions: one thread held it in
    /// `EntryTable::GetOrCreate`'s "entry still compiling" loop - unlock,
    /// yield, relock - while the thread doing that compile waited for the
    /// same lock. Each release woke the compiler, and the looping thread
    /// relocked before the compiler was ever scheduled. The title's main
    /// thread was waiting on the compiler, so the whole title stopped.
    ///
    /// Ownership is assigned here, before anyone runs. The waiter retries
    /// `AcquireSRWLockExclusive` at its own call site, finds itself the
    /// owner, and proceeds; the thread that released it finds the lock taken
    /// and blocks behind it. That is the order Windows produces when the
    /// released thread really yields.
    fn handOffWindowsSrwLock(self: *ElfState, lock: *WindowsSrwLock, address: u64) void {
        return process_impl_windows_sync.handOffWindowsSrwLock(self, lock, address);
    }

    fn noteWindowsLockHandoff(self: *ElfState, lock: *const WindowsSrwLock, directed: bool) void {
        return process_impl_windows_sync.noteWindowsLockHandoff(self, lock, directed);
    }

    /// Who holds an SRW lock, in words a report can print.
    fn describeWindowsSrwOwner(self: *const ElfState, owner_thread_id: u64, buffer: []u8) []const u8 {
        return process_impl_windows_sync.describeWindowsSrwOwner(self, owner_thread_id, buffer);
    }

    fn windowsSrwWaiterCount(self: *const ElfState, lock: WindowsSrwLock) u32 {
        return process_impl_windows_sync.windowsSrwWaiterCount(self, lock);
    }

    /// Release the owner record before waking blocked workers.  Xenia's
    /// xe_global_mutex clears its recursive owner word immediately before
    /// calling ReleaseSRWLockExclusive, so the SRW record is the authority
    /// that prevents a different worker from entering during the handoff.
    pub fn releaseWindowsSrwLock(self: *ElfState, address: u64) void {
        return process_impl_windows_sync.releaseWindowsSrwLock(self, address);
    }

    /// A worker backing off - `Sleep`, `SleepEx`, `NtDelayExecution`,
    /// `NtYieldExecution` - while it still owns Xenia's global critical
    /// region, with other threads queued on it: lend the lock out for the
    /// back-off, then take it back before the call returns.
    ///
    /// Xenia's wait loops (`EntryTable::GetOrCreate`, `Module::LookupSymbol`,
    /// `DeclareSymbol`, `DefineSymbol`) unlock, sleep and relock while another
    /// thread finishes the work they wait for. That release is real only at
    /// recursion depth one. This fork's `KeInsertQueueDpc_entry` holds the
    /// lock while it runs the title's DPC routine inline, so a routine that
    /// calls a function another thread is compiling waits in `GetOrCreate`
    /// at depth two: its unlock only decrements, and the compiling thread
    /// needs the lock for `LookupModule` and `MarkReady`.
    ///
    /// Lending is the release the loop meant to make. The depth Xenia
    /// recorded is saved here and restored when the lock comes back, so
    /// every frame that thinks it holds the lock holds it again before it
    /// runs. It only ever happens when the sleeper owns the SRW lock in
    /// both Rosette's record and Xenia's own fields with waiters queued, and
    /// its stack returns into one of those wait loops; a loop at depth one
    /// has already released it, so ordinary back-offs never lend, and a
    /// critical section that sleeps for its own reasons keeps its lock.
    ///
    /// True means the call is not complete: the worker is queued for the
    /// lock and retries the same import when it is handed back. False means
    /// the caller handles the back-off as usual.
    pub fn yieldXeniaGlobalMutexForBackoff(self: *ElfState) bool {
        return process_impl_windows_sync.yieldXeniaGlobalMutexForBackoff(self);
    }

    /// Whether the guest stack at `rsp` returns into one of Xenia's wait
    /// loops that unlock the global mutex, sleep and relock while another
    /// thread finishes what they wait for. Without a symbol resolver (the
    /// unit tests) there is nothing to name a frame with, and the caller's
    /// other conditions decide alone.
    fn xeniaWaitLoopOnStack(self: *const ElfState, rsp: u64) bool {
        return process_impl_windows_sync.xeniaWaitLoopOnStack(self, rsp);
    }

    /// Take a lent global mutex back, or queue for it. See
    /// `yieldXeniaGlobalMutexForBackoff`.
    fn collectXeniaGlobalMutex(self: *ElfState, address: u64, thread: *WindowsGuestThread, lend: XeniaGlobalLend) bool {
        return process_impl_windows_sync.collectXeniaGlobalMutex(self, address, thread, lend);
    }

    /// Mark the active worker as waiting for an SRW lock.  The import handler
    /// leaves RIP at the call site, so waking the context retries the acquire
    /// naturally; no synthetic return or guest stack mutation is needed.
    pub fn blockWindowsGuestThreadOnSrwLock(self: *ElfState, address: u64) bool {
        return process_impl_windows_sync.blockWindowsGuestThreadOnSrwLock(self, address);
    }

    /// Park a worker at pthread_cond_wait until the matching signal or
    /// broadcast arrives.  Returning success immediately is not a harmless
    /// degraded import here: libstdc++ assumes that a condition wait only
    /// returns after its predicate may have changed, and Xenia consequently
    /// dereferences its condition-variable list sentinel as a callback.
    pub fn waitWindowsGuestCondition(self: *ElfState, address: u64, mutex_address: u64) WindowsConditionWaitResult {
        return process_impl_windows_sync.waitWindowsGuestCondition(self, address, mutex_address);
    }

    /// A condition wait that also ends when the guest clock reaches
    /// `deadline`, in guest ticks; zero waits for a signal alone. However it
    /// ends, the waiter retakes its mutex before it returns, and which way it
    /// ended is left in `condition_resume_timeout`.
    pub fn waitWindowsGuestConditionUntil(self: *ElfState, address: u64, mutex_address: u64, deadline: u64) WindowsConditionWaitResult {
        return process_impl_windows_sync.waitWindowsGuestConditionUntil(self, address, mutex_address, deadline);
    }

    /// The native pthread shim's wait: the same, except a signalled waiter on
    /// a normal MinGW mutex is answered `.relock` (see
    /// `completeWindowsPthreadConditionRelock`). Only this caller knows
    /// `mutex_address` is a `pthread_mutex_t` and not, say, a critical
    /// section, so only it may be told to call the image's mutex lock.
    pub fn waitWindowsGuestPthreadCondition(self: *ElfState, address: u64, mutex_address: u64, deadline: u64) WindowsConditionWaitResult {
        return process_impl_windows_sync.waitWindowsGuestPthreadCondition(self, address, mutex_address, deadline);
    }

    fn waitWindowsGuestConditionFor(self: *ElfState, address: u64, mutex_address: u64, deadline: u64, allow_relock: bool) WindowsConditionWaitResult {
        return process_impl_windows_sync.waitWindowsGuestConditionFor(self, address, mutex_address, deadline, allow_relock);
    }

    pub const NativeConditionResult = enum {
        /// Not modelled here (bad arguments, a lock this thread does not
        /// hold, the cooperative owner): the caller keeps its old answer.
        invalid,
        /// A worker parked; the call stays at its call site.
        blocked,
        /// The owner slept for a slice; the call stays at its call site.
        retry,
        /// Signalled, and the lock is held again: TRUE.
        woken,
        /// The timeout passed, and the lock is held again: FALSE with
        /// ERROR_TIMEOUT.
        timed_out,
    };

    /// `SleepConditionVariableCS/SRW(condition, lock, milliseconds)`: release
    /// the lock, sleep until `WakeConditionVariable`/`WakeAll` or the
    /// timeout, retake the lock, return.
    ///
    /// Both used to answer FALSE at once without releasing anything. With
    /// real locks that is a livelock waiting to happen: `while (!ready)
    /// SleepConditionVariableSRW(...)` - FFmpeg's frame threads, libusb's
    /// event waiters - spins holding the lock the thread that would set
    /// `ready` needs.
    pub fn sleepWindowsNativeCondition(self: *ElfState, condition: u64, lock: u64, kind: NativeConditionLock, milliseconds: u64) NativeConditionResult {
        return process_impl_windows_sync.sleepWindowsNativeCondition(self, condition, lock, kind, milliseconds);
    }

    fn sleepWorkerOnNativeCondition(self: *ElfState, index: usize, condition: u64, lock: u64, kind: NativeConditionLock, milliseconds: u64) NativeConditionResult {
        return process_impl_windows_sync.sleepWorkerOnNativeCondition(self, index, condition, lock, kind, milliseconds);
    }

    /// Parallel mode only: the cooperative owner cannot sleep, and keeps the
    /// old immediate answer.
    fn sleepOwnerOnNativeCondition(self: *ElfState, condition: u64, lock: u64, kind: NativeConditionLock, milliseconds: u64) NativeConditionResult {
        return process_impl_windows_sync.sleepOwnerOnNativeCondition(self, condition, lock, kind, milliseconds);
    }

    /// Release the lock a native condition wait gives up, returning the
    /// recursion to restore; null when the calling thread does not hold it.
    fn releaseNativeConditionLock(self: *ElfState, lock: u64, kind: NativeConditionLock) ?u32 {
        return process_impl_windows_sync.releaseNativeConditionLock(self, lock, kind);
    }

    fn retakeNativeConditionLock(self: *ElfState, lock: u64, kind: NativeConditionLock, recursion: u32) WindowsSrwAcquireResult {
        return process_impl_windows_sync.retakeNativeConditionLock(self, lock, kind, recursion);
    }

    /// Parallel mode: the owner waits on a winpthreads condition in Rosette's
    /// model, the way a worker does. `pthread_cond_signal` and `_broadcast`
    /// are always Rosette's (`signalWindowsGuestCondition`), so an owner that
    /// ran the image's own wait - the cooperative owner's only option - would
    /// sleep on a semaphore no signal ever releases. `.blocked` here means the
    /// owner slept for a slice and its call stays at its call site.
    fn waitOwnerOnPthreadCondition(self: *ElfState, address: u64, mutex_address: u64, deadline: u64, allow_relock: bool) WindowsConditionWaitResult {
        return process_impl_windows_sync.waitOwnerOnPthreadCondition(self, address, mutex_address, deadline, allow_relock);
    }

    fn finishOwnerPthreadCondition(self: *ElfState) void {
        return process_impl_windows_sync.finishOwnerPthreadCondition(self);
    }

    /// Wake one waiter for pthread_cond_signal or all waiters for
    /// pthread_cond_broadcast.  The waiter retains a one-shot resume marker;
    /// on its next turn the import completes instead of parking again.
    pub fn signalWindowsGuestCondition(self: *ElfState, address: u64, broadcast: bool) u64 {
        return process_impl_windows_sync.signalWindowsGuestCondition(self, address, broadcast);
    }

    fn wakeWindowsGuestThreadsForSrwLock(self: *ElfState, address: u64) void {
        return process_impl_windows_sync.wakeWindowsGuestThreadsForSrwLock(self, address);
    }

    /// Install the PE loader's static TLS contract before any CRT code runs.
    /// Static TLS uses the image-provided module slot, while TlsAlloc/FlsAlloc
    /// use the remaining dynamic slots.  Keeping the two authorities explicit
    /// prevents a non-null static block from being interpreted as a pthread
    /// object by __pthread_self_lite.
    pub fn configureWindowsStaticTls(
        self: *ElfState,
        module_index: u32,
        template_start: u64,
        template_length: u64,
        block_bytes: u64,
    ) bool {
        return process_impl_windows_sync.configureWindowsStaticTls(self, module_index, template_start, template_length, block_bytes);
    }

    fn allocateWindowsGuestThreadEnvironment(
        self: *ElfState,
        stack_base: u64,
        stack_limit: u64,
        thread_id: u64,
    ) ?WindowsGuestThreadEnvironment {
        return process_impl_windows_sync.allocateWindowsGuestThreadEnvironment(self, stack_base, stack_limit, thread_id);
    }

    /// Queue a Windows thread entry point for cooperative execution.  A
    /// successful Win32 handle is not enough here: the start routine must be
    /// retained and eventually run with a private guest stack, otherwise
    /// Xenia's graphics setup thread never reaches Vulkan initialization.
    pub fn enqueueWindowsGuestThread(
        self: *ElfState,
        handle: u64,
        start_routine: u64,
        argument: u64,
        requested_stack_size: u64,
        preferred: bool,
    ) bool {
        return process_impl_windows_sync.enqueueWindowsGuestThread(self, handle, start_routine, argument, requested_stack_size, preferred);
    }

    /// Empty the slot of the earliest-created finished thread for a new one.
    ///
    /// A finished thread kept its slot for the rest of the run, so the
    /// thirty-third CreateThread of a run failed however many of the first
    /// thirty-two had exited, and a title loading its content starts and
    /// finishes threads continuously. What a finished thread's handle still
    /// owes a waiter, that it reads as signalled, lives on in its wait
    /// object; its stack, TEB and TLS block go back to the guest heap, which
    /// zeroes a block before handing it out again.
    fn recycleFinishedWindowsGuestThreadSlot(self: *ElfState) ?usize {
        return process_impl_windows_sync.recycleFinishedWindowsGuestThreadSlot(self);
    }

    /// CreateThread with every slot holding a thread that has not finished.
    fn noteWindowsGuestThreadTableFull(self: *ElfState, start_routine: u64, argument: u64, handle: u64) void {
        return process_impl_windows_sync.noteWindowsGuestThreadTableFull(self, start_routine, argument, handle);
    }

    /// Hold a freshly queued thread at a suspend count of one, as
    /// `CREATE_SUSPENDED` asks: it is not scheduled until `ResumeThread`.
    pub fn suspendWindowsGuestThreadAtCreation(self: *ElfState, handle: u64) void {
        return process_impl_windows_sync.suspendWindowsGuestThreadAtCreation(self, handle);
    }

    /// The thread id Rosette assigned a handle, for `lpThreadId`.
    pub fn windowsGuestThreadId(self: *const ElfState, handle: u64) ?u64 {
        return process_impl_windows_sync.windowsGuestThreadId(self, handle);
    }

    pub fn windowsGuestThreadIndex(self: *const ElfState, handle: u64) ?usize {
        return process_impl_windows_sync.windowsGuestThreadIndex(self, handle);
    }

    /// `SuspendThread` and `ResumeThread`: the previous count, or (DWORD)-1.
    ///
    /// A thread that suspends itself yields at once; the scheduler does not
    /// choose it again until another thread brings its count back to zero.
    pub fn changeWindowsGuestThreadSuspension(self: *ElfState, handle: u64, suspending: bool) u64 {
        return process_impl_windows_sync.changeWindowsGuestThreadSuspension(self, handle, suspending);
    }

    fn windowsGuestRegisterDigest(self: *const ElfState) u64 {
        return process_impl_windows_sync.windowsGuestRegisterDigest(self);
    }

    /// A slice that came back to the same instruction with every register the
    /// same, and made no kernel call, is a user-mode spin: the title polling a
    /// flag another thread sets. Under cooperative scheduling it takes an
    /// equal turn from the threads that would set it; on 2026-09-16
    /// XThread001A spent 19% of the run in one 256-byte loop. Each spinning
    /// slice doubles the turns the thread gives away, up to
    /// WINDOWS_GUEST_SPIN_MAX_BACKOFF; any other slice resets it.
    pub fn noteWindowsGuestSliceShape(self: *ElfState, index: usize, repeated_state: bool, kernel_calls_before: u64) void {
        return process_impl_windows_sync.noteWindowsGuestSliceShape(self, index, repeated_state, kernel_calls_before);
    }

    pub fn nextWindowsGuestThread(self: *const ElfState) ?usize {
        return process_impl_windows_sync.nextWindowsGuestThread(self);
    }

    /// Return a thread's stack block to the heap: the guard's protection is
    /// cleared first, because the next owner of those bytes is ordinary heap.
    fn releaseWindowsGuestThreadStack(self: *ElfState, thread: *WindowsGuestThread) bool {
        return process_impl_windows_sync.releaseWindowsGuestThreadStack(self, thread);
    }

    /// The worker whose stack guard holds `address`, when it is one.
    fn windowsStackGuardOwner(self: *const ElfState, address: u64) ?usize {
        return process_impl_windows_sync.windowsStackGuardOwner(self, address);
    }

    fn finishWindowsGuestThread(self: *ElfState) void {
        return process_impl_windows_sync.finishWindowsGuestThread(self);
    }

    /// Complete the currently serviced Windows worker when a noreturn thread
    /// API such as `_endthreadex` is reached.  The API must not be modelled as
    /// an ordinary zero-returning import: returning to its next instruction
    /// falls through into the next PE symbol because the wrapper has no
    /// epilogue after the real Windows runtime terminates the thread.
    pub fn terminateActiveWindowsGuestThread(self: *ElfState, exit_code: u64) bool {
        return process_impl_windows_sync.terminateActiveWindowsGuestThread(self, exit_code);
    }

    /// A worker's slice must leave the owner's register file exactly as it
    /// found it. `snapshot` was taken before the slice; `self`'s own fields
    /// are the owner's registers even while the worker is bound.
    fn auditOwnerContextAfterSlice(self: *ElfState, snapshot: *const WindowsGuestThreadContext, slot: usize) void {
        return process_impl_windows_sync.auditOwnerContextAfterSlice(self, snapshot, slot);
    }

    /// The same check after one worker instruction, when the step audit is
    /// on. The snapshot follows the owner's file after a report, so each
    /// instruction that writes it is reported once, not every step after.
    fn auditOwnerContextAfterStep(self: *ElfState, snapshot: *WindowsGuestThreadContext, slot: usize) void {
        return process_impl_windows_sync.auditOwnerContextAfterStep(self, snapshot, slot);
    }

    fn reportOwnerContextViolation(self: *ElfState, difference: context_integrity.Difference, slot: usize, scope: []const u8) void {
        return process_impl_windows_sync.reportOwnerContextViolation(self, difference, slot, scope);
    }

    /// Run one queued Windows thread for a bounded slice. The worker executes
    /// directly against its saved context; the owner's live register state is
    /// no longer replaced and copied back around each slice. Shared process
    /// services remain serialized until their tables and lifetime rules are
    /// concurrency-safe.
    pub fn serviceWindowsGuestThreads(self: *ElfState, max_steps: u64) u64 {
        return process_impl_windows_sync.serviceWindowsGuestThreads(self, max_steps);
    }

    fn nextUnstartedWindowsGuestThread(self: *ElfState) ?usize {
        return process_impl_windows_sync.nextUnstartedWindowsGuestThread(self);
    }

    fn parallelWindowsGuestThreadEntry(raw: *anyopaque, worker: *parallel_workers.Worker) void {
        return process_impl_windows_sync.parallelWindowsGuestThreadEntry(raw, worker);
    }

    /// A persistent host executor for one Windows guest thread. CPU state,
    /// block-JIT scratch and the store buffer are selected through the
    /// thread-local context binding. Runtime calls take the runtime mutex,
    /// only address-space changes stop the world, and ordinary guest scalar
    /// accesses use the TSO coordinator. The worker keeps coordination
    /// enabled between steps too, because a blocked context may drain its
    /// buffer outside a step.
    ///
    /// Per instruction this loop writes no memory another thread writes: its
    /// status is one acquire load of its own slot, its step counts reach the
    /// shared totals every `PARALLEL_WORKER_STEP_BATCH` instructions, and the
    /// step lease in `step` writes only this thread's own gate record. It
    /// used to take a gate lease to read its status, a second in `step`, and
    /// three compare-and-swap loops on counters every worker shared - which
    /// on 2026-09-25 held Xenia's Emulator thread to 0.28M instructions a
    /// second.
    fn runParallelWindowsGuestThread(self: *ElfState, slot: usize, worker: *parallel_workers.Worker) void {
        return process_impl_windows_sync.runParallelWindowsGuestThread(self, slot, worker);
    }

    /// The name a worker host thread carries in the stall watchdog's
    /// registry: its guest thread's name when it has one.
    fn parallelWorkerWatchName(self: *const ElfState, slot: usize, buffer: []u8) []const u8 {
        return process_impl_windows_sync.parallelWorkerWatchName(self, slot, buffer);
    }

    /// Publish a worker's batched step count to the shared totals and its
    /// watchdog record.
    fn publishParallelWorkerSteps(self: *ElfState, pending: *u64) void {
        return process_impl_windows_sync.publishParallelWorkerSteps(self, pending);
    }

    /// Sleep until this worker's guest thread may run again.
    ///
    /// Its queued stores were published when it blocked - the blocking
    /// import drained them on entry - and anything left is drained under a
    /// step lease. The old path stopped the world here on every wakeup, and
    /// woke every millisecond to look. The wake epoch is sampled before the
    /// status is re-checked, so a wake that lands in between is not lost. A
    /// wait with a timeout sleeps until its deadline and expires itself; one
    /// without sleeps until a notify, re-checked at the safety-net interval,
    /// and a re-check that finds the thread runnable counts a lost wakeup.
    pub fn parkParallelWorker(self: *ElfState, slot: usize, worker: *parallel_workers.Worker) void {
        return process_impl_windows_sync.parkParallelWorker(self, slot, worker);
    }

    /// The host monotonic time at which the guest clock reads `ticks`, when
    /// the clock is the host's. Null under an instruction-derived clock,
    /// whose deadlines only the owner's sweep can decide.
    fn windowsGuestTicksToHostNanoseconds(self: *const ElfState, ticks: u64) ?u64 {
        return process_impl_windows_sync.windowsGuestTicksToHostNanoseconds(self, ticks);
    }

    /// A worker can reach a wait outside any step. Only this worker drains
    /// its own queue, and a step lease is enough to keep a concurrent remap
    /// from invalidating the raw backing addresses its stores retain. This
    /// used to stop the world, every time a blocked worker woke.
    fn drainParallelWorkerStoreBuffer(self: *ElfState, slot: usize, boundary: tso_memory.Boundary) void {
        return process_impl_windows_sync.drainParallelWorkerStoreBuffer(self, slot, boundary);
    }

    /// Give one queued Windows worker a bounded turn while the owner thread
    /// is inside a long compute region.  The explicit PAUSE/wait/message
    /// boundaries remain the low-latency path; this policy is the fallback for
    /// code such as Xenia's image hashing that can run for millions of guest
    /// instructions without crossing one.  It never nests because the worker
    /// context makes `windows_active_guest_thread_slot` non-null while its
    /// slice is executing.
    fn maybeRunWindowsGuestScheduler(self: *ElfState) void {
        return process_impl_windows_sync.maybeRunWindowsGuestScheduler(self);
    }

    pub fn requestWindowsUiQuit(self: *ElfState) void {
        return process_impl_windows_ui.requestWindowsUiQuit(self);
    }

    fn captureWindowsClassName(self: *const ElfState, record: *WindowsWindowClass, name_ptr: u64, wide: bool) void {
        return process_impl_windows_ui.captureWindowsClassName(self, record, name_ptr, wide);
    }

    fn windowsClassMatches(self: *const ElfState, record: *const WindowsWindowClass, class_name: u64, wide: bool) bool {
        return process_impl_windows_ui.windowsClassMatches(self, record, class_name, wide);
    }

    fn windowsClassIndex(self: *const ElfState, class_name: u64, wide: bool) ?usize {
        return process_impl_windows_ui.windowsClassIndex(self, class_name, wide);
    }

    /// Register the guest WndProc carried by a WNDCLASS/WNDCLASSEX record.
    /// The structure layout is the same through `lpfnWndProc` and
    /// `lpszClassName` for the A/W and Ex/non-Ex variants on Win64.
    pub fn registerWindowsWindowClass(self: *ElfState, class_info: u64, wide: bool) u64 {
        return process_impl_windows_ui.registerWindowsWindowClass(self, class_info, wide);
    }

    /// Install a synthetic HWND and retain the guest `lpParam` as its
    /// GWLP_USERDATA.  Real Win32 sends WM_NCCREATE during CreateWindowEx;
    /// recording that result here gives the guest WndProc the same state
    /// without recursively running creation messages before the import has
    /// returned its HWND.
    pub fn createWindowsWindow(
        self: *ElfState,
        handle: u64,
        class_name: u64,
        user_data: u64,
        message_only: bool,
        style: u64,
        ex_style: u64,
        wide: bool,
    ) bool {
        return process_impl_windows_ui.createWindowsWindow(self, handle, class_name, user_data, message_only, style, ex_style, wide);
    }

    fn windowsWindowIndex(self: *const ElfState, handle: u64) ?usize {
        return process_impl_windows_ui.windowsWindowIndex(self, handle);
    }

    pub fn isWindowsWindowHandle(self: *const ElfState, handle: u64) bool {
        return process_impl_windows_ui.isWindowsWindowHandle(self, handle);
    }

    pub fn windowsWindowProc(self: *const ElfState, handle: u64) ?u64 {
        return process_impl_windows_ui.windowsWindowProc(self, handle);
    }

    pub fn windowsWindowLong(self: *const ElfState, handle: u64, index: i64) ?u64 {
        return process_impl_windows_ui.windowsWindowLong(self, handle, index);
    }

    pub fn setWindowsWindowLong(self: *ElfState, handle: u64, index: i64, value: u64) ?u64 {
        return process_impl_windows_ui.setWindowsWindowLong(self, handle, index, value);
    }

    pub fn destroyWindowsWindow(self: *ElfState, handle: u64) bool {
        return process_impl_windows_ui.destroyWindowsWindow(self, handle);
    }

    /// Mark a window's update region non-empty.  This is the model behind
    /// InvalidateRect/InvalidateRgn/RedrawWindow: Win32 records the request
    /// and defers WM_PAINT generation to the message pump.  A null HWND
    /// invalidates every drawable window, matching the Win32 contract for a
    /// null window handle.
    pub fn invalidateWindowsWindow(self: *ElfState, handle: u64) bool {
        return process_impl_windows_ui.invalidateWindowsWindow(self, handle);
    }

    /// Clear a window's update region.  ValidateRect/ValidateRgn and the
    /// BeginPaint/EndPaint pair all end the pending paint; without this the
    /// pump would keep regenerating WM_PAINT forever, exactly as real Win32
    /// does for a WndProc that never validates.
    pub fn validateWindowsWindow(self: *ElfState, handle: u64) bool {
        return process_impl_windows_ui.validateWindowsWindow(self, handle);
    }

    pub fn windowsWindowHasPendingPaint(self: *const ElfState, handle: u64) bool {
        return process_impl_windows_ui.windowsWindowHasPendingPaint(self, handle);
    }

    pub fn windowsPendingPaintCount(self: *const ElfState) usize {
        return process_impl_windows_ui.windowsPendingPaintCount(self);
    }

    /// Produce the WM_PAINT a pump call should return, if any window still
    /// has a non-empty update region and the caller's filter accepts it.
    /// WM_PAINT is generated rather than dequeued, so the region stays set
    /// until the guest validates it; a PeekMessage without PM_REMOVE and a
    /// GetMessage therefore observe the same pending paint.
    pub fn pendingWindowsPaintMessage(
        self: *ElfState,
        filter_hwnd: u64,
        minimum: u64,
        maximum: u64,
    ) ?WindowsMessage {
        return process_impl_windows_ui.pendingWindowsPaintMessage(self, filter_hwnd, minimum, maximum);
    }

    pub fn enqueueWindowsMessage(self: *ElfState, message: WindowsMessage) bool {
        return process_impl_windows_ui.enqueueWindowsMessage(self, message);
    }

    pub fn windowsMessageCount(self: *const ElfState) usize {
        return process_impl_windows_ui.windowsMessageCount(self);
    }

    pub fn windowsMessageDeliveryCount(self: *const ElfState) u64 {
        return process_impl_windows_ui.windowsMessageDeliveryCount(self);
    }

    pub fn windowsMessagePostCount(self: *const ElfState) u64 {
        return process_impl_windows_ui.windowsMessagePostCount(self);
    }

    pub fn windowsMessageAffinitySkipCount(self: *const ElfState) u64 {
        return process_impl_windows_ui.windowsMessageAffinitySkipCount(self);
    }

    pub fn postWindowsMessage(self: *ElfState, hwnd: u64, message: u32, wparam: u64, lparam: u64, caller_return_rip: u64) bool {
        return process_impl_windows_ui.postWindowsMessage(self, hwnd, message, wparam, lparam, caller_return_rip);
    }

    /// One leg of a Xenia pending-function handoff (`CallInUIThread`): who,
    /// when, and how long the previous leg took. The first 32 of each leg
    /// are logged, then only powers of two; the totals are in PE64 WINDOWS UI
    /// HANDOFF.
    fn logUiCall(self: *const ElfState, sequence: u64, leg: []const u8, comptime detail: []const u8, args: anytype) void {
        return process_impl_windows_ui.logUiCall(self, sequence, leg, detail, args);
    }

    pub fn postWindowsQuit(self: *ElfState, exit_code: u64) void {
        return process_impl_windows_ui.postWindowsQuit(self, exit_code);
    }

    /// Block a GetMessage whose queue is empty until something is
    /// deliverable, as a real GetMessage does. Parallel mode only.
    ///
    /// The cooperative executor could not block the host - the owner was the
    /// only thread that ran workers - so GetMessage returned WM_NULL at once
    /// and the guest's loop asked again. With workers on their own threads
    /// that loop became a spinner: on 2026-09-25 Xenia's UI thread called
    /// GetMessage and TranslateMessage seven million times in a minute, 83%
    /// of every instruction the run retired, and each call stopped the
    /// world. Here the call releases the runtime lock and sleeps in a safe
    /// region (still serving the main queue when it is the main thread)
    /// until a message is queued, a paint is requested or a quit posted. It
    /// wakes at the bounded host-event poll cadence to pump native events - which
    /// is how keyboard and window events become messages - and to run the
    /// dispatcher, which expires due guest waits and starts new threads.
    /// It stays blocked until something is deliverable or the process is
    /// terminating, matching Win32 GetMessage instead of manufacturing a
    /// periodic WM_NULL. Returns the time blocked.
    pub fn waitForWindowsMessage(self: *ElfState, filter_hwnd: u64, minimum: u64, maximum: u64) u64 {
        return process_impl_windows_ui.waitForWindowsMessage(self, filter_hwnd, minimum, maximum);
    }

    pub const GuestWaitPark = enum {
        /// Wake at the first change in any guest thread's runnability - a
        /// signal, a release, a handoff all move the wake hub - at the
        /// deadline, or after one slice, whichever comes first.
        wake,
        /// Sleep until the deadline whatever else happens: `Sleep(n)`.
        until_deadline,
    };

    /// The longest one sleep of a waiting guest thread lasts before it looks
    /// again. A signal wakes it at once through the wake hub; the slice only
    /// bounds what a state change that forgot to notify can cost, and keeps
    /// the retry - which also runs the scheduler's sweep - to a few hundred
    /// a second instead of millions.
    const guest_wait_slice_ns: u64 = 5 * std.time.ns_per_ms;

    /// Parallel mode: sleep the calling thread for part of a guest wait with
    /// the runtime lock released, then take it back. For the owner (the UI
    /// thread, on the host main thread) the park keeps serving the main
    /// queue. Returns false without sleeping outside parallel mode, or when
    /// a pinned critical section holds the runtime lock on this thread (the
    /// caller keeps its old retry then).
    ///
    /// Before parallel mode no guest wait on the owner could sleep - the
    /// owner was the only host thread, and the one that ran every worker -
    /// so a finite wait there answered WAIT_TIMEOUT at once, an infinite one
    /// was retried as fast as the interpreter could go, and `Sleep(n)`
    /// returned immediately.
    pub fn parkForGuestWait(self: *ElfState, deadline_ns: ?u64, mode: GuestWaitPark) bool {
        return process_impl_windows_ui.parkForGuestWait(self, deadline_ns, mode);
    }

    /// Parallel mode: sleep the calling thread for a guest `Sleep(ms)` it has
    /// no worker slot to park for (the owner). INFINITE is capped at a minute
    /// per call; the guest's own loop decides after that.
    pub fn sleepForGuestWait(self: *ElfState, milliseconds: u64) bool {
        return process_impl_windows_ui.sleepForGuestWait(self, milliseconds);
    }

    /// Parallel mode: sleep the calling thread to the next 60 Hz boundary of
    /// the host clock, as `IDXGIOutput::WaitForVBlank` blocks to the next
    /// vertical blank.
    pub fn sleepUntilNextVblank(self: *ElfState) bool {
        return process_impl_windows_ui.sleepUntilNextVblank(self);
    }

    const OwnerWaitOutcome = enum { signaled, timeout, retry };

    /// Parallel mode: one slice of the owner's wait on `handles`. Null when
    /// the owner cannot sleep here (a pinned lock level) and must fall back
    /// to the cooperative rule. Otherwise the wait is satisfied (the caller
    /// consumes the objects), has reached the deadline its *first* attempt
    /// set, or should retry at its call site. The owner re-enters the same
    /// import for every slice, so its deadline is kept under a key made of
    /// the handles, the timeout and the stack frame.
    fn ownerParallelWait(self: *ElfState, handles: []const u64, wait_all: bool, timeout: u64) ?OwnerWaitOutcome {
        return process_impl_windows_ui.ownerParallelWait(self, handles, wait_all, timeout);
    }

    fn finishOwnerWait(self: *ElfState, outcome: OwnerWaitOutcome) OwnerWaitOutcome {
        return process_impl_windows_ui.finishOwnerWait(self, outcome);
    }

    fn ownerWaitSatisfied(self: *ElfState, handles: []const u64, wait_all: bool) bool {
        return process_impl_windows_ui.ownerWaitSatisfied(self, handles, wait_all);
    }

    fn ownerWaitKey(handles: []const u64, wait_all: bool, timeout: u64, frame: u64) u64 {
        return process_impl_windows_ui.ownerWaitKey(handles, wait_all, timeout, frame);
    }

    fn windowsMessageDeliverable(self: *ElfState, filter_hwnd: u64, minimum: u64, maximum: u64) bool {
        return process_impl_windows_ui.windowsMessageDeliverable(self, filter_hwnd, minimum, maximum);
    }

    /// Parallel mode: whether a window's messages are the calling thread's
    /// to receive. Win32 queues them to the thread that created the window,
    /// and Rosette's one queue used to hand them to whichever thread asked
    /// first - harmless while one host thread ran every guest thread, and in
    /// parallel mode a way for any thread with a message loop to take the
    /// UI thread's WM_USER, the message that asks it to create the
    /// presenter. The cooperative executor keeps the old any-thread rule.
    fn windowBelongsToCaller(self: *const ElfState, record: WindowsWindow) bool {
        return process_impl_windows_ui.windowBelongsToCaller(self, record);
    }

    pub fn dequeueWindowsMessage(self: *ElfState, filter_hwnd: u64, minimum: u64, maximum: u64, remove: bool) ?WindowsMessage {
        return process_impl_windows_ui.dequeueWindowsMessage(self, filter_hwnd, minimum, maximum, remove);
    }

    /// Reserve a properly aligned nested Windows callback frame.  The
    /// original DispatchMessage return address stays above the callback's
    /// 32-byte home area, so a WndProc can use the normal Microsoft x64 ABI.
    pub fn noteWindowsMessageDispatch(self: *ElfState, hwnd: u64, message: u32, wparam: u64, lparam: u64, wndproc: u64) bool {
        return process_impl_windows_ui.noteWindowsMessageDispatch(self, hwnd, message, wparam, lparam, wndproc);
    }

    pub fn beginWindowsMessageDispatch(self: *ElfState, return_rip: u64, return_is_direct: bool) bool {
        return process_impl_windows_ui.beginWindowsMessageDispatch(self, return_rip, return_is_direct);
    }

    pub fn beginWindowsMessageDispatchWithKind(self: *ElfState, return_rip: u64, return_is_direct: bool, pending_function: bool) bool {
        return process_impl_windows_ui.beginWindowsMessageDispatchWithKind(self, return_rip, return_is_direct, pending_function);
    }

    pub fn finishWindowsMessageDispatch(self: *ElfState) bool {
        return process_impl_windows_ui.finishWindowsMessageDispatch(self);
    }

    /// Enter a WinMM CALLBACK_FUNCTION callback using a guest-only nested
    /// frame.  The callback has the normal 32-byte Microsoft home area plus
    /// one stack argument, while the original waveOutWrite continuation stays
    /// above it.  This mirrors the message-dispatch protocol but uses its own
    /// marker and frame stack so an audio completion can never consume a UI
    /// callback frame.
    pub fn beginWindowsAudioCallback(self: *ElfState, return_rip: u64, return_is_direct: bool) bool {
        return process_impl_windows_ui.beginWindowsAudioCallback(self, return_rip, return_is_direct);
    }

    pub fn finishWindowsAudioCallback(self: *ElfState) bool {
        return process_impl_windows_ui.finishWindowsAudioCallback(self);
    }

    const windows_exception_frame_magic: u64 = 0x3148_4556_4553_4F52; // "ROSEVEH1"
    const windows_status_access_violation: u32 = 0xC000_0005;
    const windows_exception_continue_execution: u32 = 0xFFFF_FFFF;
    const windows_context_bytes: u64 = 0x4D0;
    const windows_exception_record_bytes: u64 = 0xA0;
    const windows_exception_header_bytes: u64 = 0x40;
    /// A handler that faults inside itself is dispatched again, as on
    /// Windows; past this depth Rosette stops and performs the access.
    const windows_exception_nesting_limit: u32 = 8;

    /// Record the protection a guest applied to a range.
    pub fn noteGuestPageProtection(
        self: *ElfState,
        address: u64,
        length: u64,
        protect: u32,
        api: []const u8,
        caller_rip: u64,
    ) void {
        return process_impl_guest_memory.noteGuestPageProtection(self, address, length, protect, api, caller_rip);
    }

    pub fn clearGuestPageProtection(self: *ElfState, address: u64, length: u64) void {
        return process_impl_guest_memory.clearGuestPageProtection(self, address, length);
    }

    /// Clear one guest protection range and say whether that changed the
    /// protection table enough to invalidate the TLB already. Release paths
    /// use the result to avoid immediately invalidating the same range twice.
    pub fn clearGuestPageProtectionAndReportInvalidation(self: *ElfState, address: u64, length: u64) bool {
        return process_impl_guest_memory.clearGuestPageProtectionAndReportInvalidation(self, address, length);
    }

    /// The Windows `PAGE_*` value recorded for an address.
    pub fn guestPageProtectionFlags(self: *const ElfState, address: u64) u32 {
        return process_impl_guest_memory.guestPageProtectionFlags(self, address);
    }

    /// Note an interpreted access to a protected page, returning whether a
    /// store must be withheld.
    ///
    /// Only the first violation in an instruction is raised, as a CPU stops
    /// at its first faulting access.
    fn noteGuestOperandAccess(self: *ElfState, address: u64, size: Size, is_write: bool, value: u64) bool {
        return process_impl_guest_memory.noteGuestOperandAccess(self, address, size, is_write, value);
    }

    /// A host-side mutable borrow of guest memory (an import shim, a CRT
    /// copy, a file read, an exception frame) that overlaps a page the guest
    /// protected. Windows would have faulted inside the shim and let the
    /// vectored handler see the write; Rosette writes without a fault, so a
    /// write watch on that page never fires. Counted, and the first few
    /// named, so the next run says how much watched memory is written this
    /// way. This is a measurement, not yet the fault.
    fn noteProtectedBulkBorrow(self: *ElfState, addr: u64, count: u64) void {
        return process_impl_guest_memory.noteProtectedBulkBorrow(self, addr, count);
    }

    fn guestAccessViolationSite(self: *ElfState, page: u64) ?*GuestAccessViolationSite {
        return process_impl_guest_memory.guestAccessViolationSite(self, page);
    }

    /// Raise the pending access violation through the guest's vectored
    /// exception handler, or perform the access if nobody can take it.
    ///
    /// The fallback is the behaviour Rosette always had, so a process with
    /// protected pages and no handler - or a handler that declines - runs
    /// exactly as before and is merely counted.
    pub fn raiseGuestAccessViolation(self: *ElfState) void {
        return process_impl_guest_memory.raiseGuestAccessViolation(self);
    }

    fn completeSuppressedGuestAccess(self: *ElfState, address: u64, width: u8, is_write: bool, value: u64, wide_value: [16]u8) void {
        return process_impl_guest_memory.completeSuppressedGuestAccess(self, address, width, is_write, value, wide_value);
    }

    /// A 16-byte vector access against the protection table, with
    /// `noteGuestOperandAccess`'s rules. Vector loads and stores skipped
    /// this check before 2026-09-19: a write watch (Xenia protects
    /// physical-heap pages read-only to learn what the guest changed, and
    /// re-uploads only what faulted) never saw a `vmovaps` store, so the
    /// GPU could be fed the previous contents of a buffer the title had
    /// just rewritten with vector instructions.
    fn noteGuestWideAccess(self: *ElfState, address: u64, is_write: bool, value: [16]u8) bool {
        return process_impl_guest_memory.noteGuestWideAccess(self, address, is_write, value);
    }

    /// Call the guest's vectored exception handler with an access violation.
    ///
    /// The frame is built on the faulting thread's stack, below its current
    /// stack pointer, in the order `KiUserExceptionDispatcher` leaves it:
    ///
    ///   call_rsp        synthetic return address
    ///   +0x08..+0x28    home space for the handler's one argument
    ///   +0x28           Rosette header: magic, fault, post-instruction rip,
    ///                   withheld value, width and direction
    ///   +0x58           EXCEPTION_POINTERS
    ///   +0x68           EXCEPTION_RECORD
    ///   +0x108          CONTEXT (x64, 0x4D0 bytes)
    ///
    /// `call_rsp` is 8 modulo 16, as it is on entry to any function, so the
    /// header, the record and the CONTEXT are all 16-byte aligned. Nothing is
    /// kept on the host side: the return path reads the header back from the
    /// stack, so the frame belongs to the thread by construction.
    fn enterWindowsExceptionDispatch(self: *ElfState, fault: GuestAccessViolation) bool {
        return process_impl_guest_memory.enterWindowsExceptionDispatch(self, fault);
    }

    /// The x64 CONTEXT a Windows exception handler reads and rewrites.
    fn writeGuestExceptionContext(self: *ElfState, context: u64, rip: u64) void {
        return process_impl_guest_memory.writeGuestExceptionContext(self, context, rip);
    }

    /// The handler returned. Take its verdict and its CONTEXT.
    fn finishWindowsExceptionDispatch(self: *ElfState) void {
        return process_impl_guest_memory.finishWindowsExceptionDispatch(self);
    }

    pub fn addrToOffset(self: *const ElfState, vaddr: u64) ?u64 {
        return process_impl_guest_memory.addrToOffset(self, vaddr);
    }

    /// Classify one fixed `VirtualAlloc` against what already backs it, and
    /// record the answer.
    ///
    /// This is the reservation-versus-commit distinction the
    /// `guest-heap-commit-unreserved` failure point asks Rosetta not to
    /// lose. It changes no behaviour: the allocation still succeeds, because
    /// refusing a commit the guest has already convinced itself it may make
    /// would end a run over bookkeeping. It changes what the run can say.
    pub fn noteWindowsAllocationDisposition(
        self: *ElfState,
        requested_base: u64,
        length: u64,
        reserve_requested: bool,
        commit_requested: bool,
        served: bool,
        caller_rip: u64,
    ) WindowsAllocationDisposition {
        return process_impl_guest_memory.noteWindowsAllocationDisposition(self, requested_base, length, reserve_requested, commit_requested, served, caller_rip);
    }

    /// Move only the known Xenia CPU-context allocator to its next contract
    /// candidate. Generic fixed-address callers still receive the normal
    /// Windows failure on an occupied range; silently relocating those would
    /// change their pointer semantics. The ThreadState allocator, by contrast,
    /// explicitly walks this candidate sequence and only needs a unique slot.
    pub fn relocateWindowsThreadContextAllocation(
        self: *ElfState,
        requested_base: u64,
        length: u64,
        caller_rip: u64,
    ) ?u64 {
        return process_impl_guest_memory.relocateWindowsThreadContextAllocation(self, requested_base, length, caller_rip);
    }

    pub fn noteWindowsAllocationRelocation(
        self: *ElfState,
        requested_base: u64,
        actual_base: u64,
        length: u64,
        caller_rip: u64,
    ) WindowsAllocationDisposition {
        return process_impl_guest_memory.noteWindowsAllocationRelocation(self, requested_base, actual_base, length, caller_rip);
    }

    fn noteWindowsUnbackedCommit(self: *ElfState, base: u64, length: u64, caller_rip: u64) void {
        return process_impl_guest_memory.noteWindowsUnbackedCommit(self, base, length, caller_rip);
    }

    fn noteWindowsAllocationRefusal(
        self: *ElfState,
        requested_base: u64,
        length: u64,
        reserve_requested: bool,
        commit_requested: bool,
        caller_rip: u64,
    ) void {
        return process_impl_guest_memory.noteWindowsAllocationRefusal(self, requested_base, length, reserve_requested, commit_requested, caller_rip);
    }

    /// What every fixed allocation this run made was, relative to its backing.
    pub fn reportWindowsMemoryContract(self: *const ElfState) void {
        return process_impl_guest_memory.reportWindowsMemoryContract(self);
    }

    fn trimWindowsFileMappingCount(self: *ElfState) void {
        return process_impl_guest_memory.trimWindowsFileMappingCount(self);
    }

    fn trimWindowsMemoryViewCount(self: *ElfState) void {
        return process_impl_guest_memory.trimWindowsMemoryViewCount(self);
    }

    fn trimWindowsVirtualAllocationCount(self: *ElfState) void {
        return process_impl_guest_memory.trimWindowsVirtualAllocationCount(self);
    }

    /// The PE runner switches this on only for an explicitly requested full
    /// instruction-ring capture. The always-useful last RIP remains updated
    /// even when the ring is disabled.
    pub fn configureWindowsTraceRing(self: *ElfState) void {
        return process_impl_guest_memory.configureWindowsTraceRing(self);
    }

    /// Install the PE loader's executable section map before the image starts
    /// executing.  A missing range is a conservative fallback: decodeAt
    /// keeps its byte comparison whenever this table is empty, so an image
    /// route can never trade correctness for a cache hit.
    pub fn configureWindowsExecutableRanges(
        self: *ElfState,
        ranges: []const WindowsExecutableRange,
    ) void {
        return process_impl_guest_memory.configureWindowsExecutableRanges(self, ranges);
    }

    pub fn windowsVirtualAllocationContains(self: *const ElfState, address: u64, count: u64) bool {
        return process_impl_guest_memory.windowsVirtualAllocationContains(self, address, count);
    }

    fn windowsMappedRangeContains(self: *const ElfState, address: u64, count: u64) bool {
        return process_impl_guest_memory.windowsMappedRangeContains(self, address, count);
    }

    pub fn windowsGuestRangeContains(self: *const ElfState, address: u64, count: u64) bool {
        return process_impl_guest_memory.windowsGuestRangeContains(self, address, count);
    }

    fn nativeMemoryAlias(self: *const ElfState, address: u64, count: u64) ?[]u8 {
        return process_impl_guest_memory.nativeMemoryAlias(self, address, count);
    }

    pub fn borrowNativeMemory(self: *ElfState, bytes: []u8) ?u64 {
        return process_impl_guest_memory.borrowNativeMemory(self, bytes);
    }

    pub fn releaseNativeMemory(self: *ElfState, guest_base: u64) void {
        return process_impl_guest_memory.releaseNativeMemory(self, guest_base);
    }

    pub fn windowsMappingIndex(self: *const ElfState, handle: u64) ?usize {
        return process_impl_guest_memory.windowsMappingIndex(self, handle);
    }

    fn windowsViewRangeIsFree(self: *const ElfState, guest_base: u64, length: u64) bool {
        return process_impl_guest_memory.windowsViewRangeIsFree(self, guest_base, length);
    }

    fn windowsMappingHasViews(self: *const ElfState, mapping_index: usize) bool {
        return process_impl_guest_memory.windowsMappingHasViews(self, mapping_index);
    }

    fn releaseClosedWindowsMapping(self: *ElfState, mapping_index: usize) void {
        return process_impl_guest_memory.releaseClosedWindowsMapping(self, mapping_index);
    }

    /// Create the Rosetta backing for a Windows file mapping.  When the
    /// Win32 handle names an authorized guest file, preserve that file's
    /// contents through a host `mmap` rather than silently replacing it with
    /// anonymous zero pages.  A zero maximum size means "the current file
    /// size" for CreateFileMapping; this is the path used by Xenia's
    /// `MappedMemory::Open` for an XISO.
    pub fn createWindowsMemoryMapping(
        self: *ElfState,
        handle: u64,
        requested_length: u64,
        source_handle: u64,
    ) bool {
        return process_impl_guest_memory.createWindowsMemoryMapping(self, handle, requested_length, source_handle);
    }

    /// Reserve/commit a fixed anonymous Windows range.  The native Xenia
    /// build uses VirtualAlloc for memory outside its file mapping (the code
    /// cache's 0x80000000 indirection table is the first such allocation),
    /// so returning a normal Rosetta heap address would silently corrupt the
    /// pointer contract.  A sparse host mapping gives those exact guest
    /// addresses real storage without reserving the range in the host VM.
    pub fn createWindowsVirtualAllocation(self: *ElfState, guest_base: u64, requested_length: u64) bool {
        return process_impl_guest_memory.createWindowsVirtualAllocation(self, guest_base, requested_length);
    }

    pub fn releaseWindowsVirtualAllocation(self: *ElfState, guest_base: u64, requested_length: u64, allocation_type: u64) bool {
        return process_impl_guest_memory.releaseWindowsVirtualAllocation(self, guest_base, requested_length, allocation_type);
    }

    /// Publish one guest view of a Windows mapping.  The returned value is a
    /// guest address, never the host backing pointer.  A fixed view that
    /// overlaps the PE's ordinary address range is rejected just as the real
    /// Windows VM would reject Xenia's first candidate; Xenia then retries at
    /// its next 8 GiB placement.
    pub fn mapWindowsMemoryView(
        self: *ElfState,
        handle: u64,
        requested_base: u64,
        requested_length: u64,
        backing_offset: u64,
    ) ?u64 {
        return process_impl_guest_memory.mapWindowsMemoryView(self, handle, requested_base, requested_length, backing_offset);
    }

    pub fn unmapWindowsMemoryView(self: *ElfState, guest_base: u64) bool {
        return process_impl_guest_memory.unmapWindowsMemoryView(self, guest_base);
    }

    pub fn closeWindowsMemoryMapping(self: *ElfState, handle: u64) bool {
        return process_impl_guest_memory.closeWindowsMemoryMapping(self, handle);
    }

    pub fn windowsMappedMemoryConst(self: *const ElfState, address: u64, count: u64) ?[]const u8 {
        return process_impl_guest_memory.windowsMappedMemoryConst(self, address, count);
    }

    /// Resolve instruction bytes from a Rosette-owned Windows mapping. Xenia's
    /// JIT code cache lives outside the PE image (commonly at
    /// 0xa0000000), so treating every non-image RIP as a decode failure stops
    /// immediately after the first native Vulkan frame is submitted.
    pub fn windowsMappedCodeMemoryConst(self: *const ElfState, address: u64, count: u64) ?WindowsMappedCodeSlice {
        return process_impl_guest_memory.windowsMappedCodeMemoryConst(self, address, count);
    }

    fn windowsMappedMemory(self: *ElfState, address: u64, count: u64) ?[]u8 {
        return process_impl_guest_memory.windowsMappedMemory(self, address, count);
    }

    /// Invalidate decode entries after a guest write through a mapped
    /// allocation. Xenia aliases the code-cache mapping at multiple guest
    /// addresses, so the token belongs to the backing mapping rather than to
    /// one view. The decode path still compares bytes when it observes a new
    /// token; this helper only makes the fast path safe.
    fn bumpWindowsMappedCodeGeneration(self: *ElfState, address: u64, count: u64) void {
        return process_impl_guest_memory.bumpWindowsMappedCodeGeneration(self, address, count);
    }

    /// The word in `code_page_generations` for one page of one mapping's
    /// backing. Pages of one mapping take consecutive words from a start
    /// the mapping's identity scatters, so a mapping never collides with
    /// itself below a gigabyte.
    fn codePageGenerationSlot(kind: mapped_ranges.Kind, source_index: usize, page: u64) usize {
        return process_impl_guest_memory.codePageGenerationSlot(kind, source_index, page);
    }

    /// The generation word for the code page holding `backing_offset`, or
    /// null before the table exists.
    pub fn codePageGenerationWord(self: *ElfState, kind: mapped_ranges.Kind, source_index: usize, backing_offset: u64) ?*u64 {
        return process_impl_guest_memory.codePageGenerationWord(self, kind, source_index, backing_offset);
    }

    /// Allocate the page-generation table. Never under parallel execution:
    /// workers read and bump its words from their own threads, so it has to
    /// exist before the first of them starts or not at all.
    /// Allocate the import histogram; like the page table, only before
    /// workers run.
    /// The PE route's memory-aware block cross-check, opt-in with
    /// `ROSETTE_BLOCK_JIT_VERIFY_MEMORY=1`: a block is checked once, before
    /// it is trusted, and a translation that disagrees with the interpreter
    /// is replaced by it and named (`PE64 BLOCK JIT MISMATCH kind=memory_block`).
    /// It was on by default for two Halo 3 runs on 2026-10-02 and found no
    /// translation defect, while its interpreted pass met side effects a
    /// discarded pass must not have (branches into the condition shim,
    /// traps); those are now refused, and it stays a diagnostic to ask for.
    pub fn configureBlockJitMemoryVerify(self: *ElfState) void {
        return process_impl_guest_memory.configureBlockJitMemoryVerify(self);
    }

    pub fn ensureImportHistogram(self: *ElfState) void {
        return process_impl_guest_memory.ensureImportHistogram(self);
    }

    /// The busiest imports by call count, with a sampled time per call.
    fn reportImportHistogram(self: *const ElfState) void {
        return process_impl_guest_memory.reportImportHistogram(self);
    }

    pub fn ensureCodePageGenerations(self: *ElfState) void {
        return process_impl_guest_memory.ensureCodePageGenerations(self);
    }

    /// Move the words of every page `count` bytes at `backing_offset`
    /// touch, and the page before the first, after the bytes were written.
    fn bumpCodePageGenerations(self: *ElfState, kind: mapped_ranges.Kind, source_index: usize, backing_offset: u64, count: u64) void {
        return process_impl_guest_memory.bumpCodePageGenerations(self, kind, source_index, backing_offset, count);
    }

    fn bumpCodePageWord(self: *const ElfState, word: *u64) void {
        return process_impl_guest_memory.bumpCodePageWord(self, word);
    }

    /// A code-generation counter under parallel execution: guest threads on
    /// several host threads write code and every executor's decode cache and
    /// translated blocks read these, so the bump is atomic and releases the
    /// store it follows. Parallel mode used to leave these counters frozen
    /// and compare bytes instead - but a translated block's native chain
    /// link trusts the counter alone, so once guest workers ran translated
    /// code, a thread rewriting its code would have left another jumping
    /// into the stale translation. Saturation (2^64 writes) stays a serial
    /// concern; the flush it needs stops the world.
    fn bumpCodeGenerationShared(self: *const ElfState, generation: *u64) void {
        return process_impl_guest_memory.bumpCodeGenerationShared(self, generation);
    }

    pub fn loadCodeGeneration(generation: *const u64) u64 {
        return process_impl_guest_memory.loadCodeGeneration(generation);
    }

    /// Retire the mapped-source decodes when a mapping lifetime ends.
    ///
    /// A recreated mapping may reuse both a table slot and generation 1, and
    /// a serial executor trusts a matching generation without comparing
    /// bytes, so the old lifetime's decodes must go - from the primary sets
    /// and from the victim bank, which this used to miss. A parallel
    /// executor compares bytes on every hit, in all three tiers, and the
    /// switch back to serial execution clears them all, so parallel mode
    /// skips the sweep.
    ///
    /// The translator's blocks are dropped per mapping at the removal sites
    /// (`blockJitDropMappedSource`), not here: dropping every mapped block on
    /// every map and unmap threw away the whole translated code cache each
    /// time a thread stack came or went. Nor are the TLBs flushed here: each
    /// removal retires its own range first (`blockJitTlbInvalidate`), and a
    /// range being created cannot be resident in any TLB. A million-entry
    /// sweep plus every executor's TLB flush on each map and unmap, with the
    /// world stopped, was 7% of the 2026-09-30 Emulator thread's wall time.
    fn invalidateMappedDecodeCache(self: *ElfState) void {
        return process_impl_guest_memory.invalidateMappedDecodeCache(self);
    }

    /// Publish a new mapped range. Nothing is invalidated: its addresses
    /// were unmapped until now, so no decode or TLB entry can name them
    /// (every removal retired its own), and the old lifetime of a reused
    /// slot was swept when it ended.
    fn indexWindowsMappedRange(self: *ElfState, range: mapped_ranges.Range) bool {
        return process_impl_guest_memory.indexWindowsMappedRange(self, range);
    }

    fn windowsIndexedMemory(self: *const ElfState, address: u64, count: u64) ?WindowsMappedCodeSlice {
        return process_impl_guest_memory.windowsIndexedMemory(self, address, count);
    }

    /// Invalidate image decode entries only when a write overlaps an
    /// executable PE section.  Writes to `.data`, TLS and runtime bookkeeping
    /// are common during bootstrap and must not force every hot image loop to
    /// re-read and compare its instruction bytes.
    fn bumpWindowsImageCodeGeneration(self: *ElfState, address: u64, count: u64) void {
        return process_impl_guest_memory.bumpWindowsImageCodeGeneration(self, address, count);
    }

    /// Whether a guest range overlaps an executable PE section. Every guest
    /// store asks through `bumpWindowsImageCodeGeneration`; the bounding box
    /// answers nearly all of them before the per-range scan.
    inline fn windowsImageRangeOverlapsCode(self: *const ElfState, address: u64, count: u64) bool {
        return process_impl_guest_memory.windowsImageRangeOverlapsCode(self, address, count);
    }

    fn traceWindowsExecutableImageWrite(self: *ElfState, address: u64, count: u64) void {
        return process_impl_guest_memory.traceWindowsExecutableImageWrite(self, address, count);
    }

    /// Return the current image-code generation only when the complete
    /// instruction lies in an executable PE section. A malformed control
    /// transfer into `.data` remains on the conservative byte-checked path;
    /// the generation proof must never turn an invalid/non-executable fetch
    /// into a stale decode.
    pub fn windowsImageCodeGenerationFor(self: *ElfState, address: u64, count: usize) ?u64 {
        return process_impl_guest_memory.windowsImageCodeGenerationFor(self, address, count);
    }

    fn loadGuestScalar(self: *const ElfState, comptime T: type, bytes: []const u8) T {
        return process_impl_guest_memory.loadGuestScalar(self, T, bytes);
    }

    fn storeGuestScalar(self: *const ElfState, comptime T: type, bytes: []u8, value: T) void {
        return process_impl_guest_memory.storeGuestScalar(self, T, bytes, value);
    }

    pub fn guestMemoryClass(self: *const ElfState, address: u64, width: u8, is_write: bool) tso_memory_policy.MemoryClass {
        return process_impl_guest_memory.guestMemoryClass(self, address, width, is_write);
    }

    /// Classify a bulk access without collapsing protected/device pages into
    /// the ordinary-RAM store queue. MMIO is represented by Xenia's
    /// no-access pages and reaches the vectored fault path; protected write-
    /// watch pages use the same fault-routed ordering boundary.
    pub fn guestMemoryRangeClass(self: *const ElfState, address: u64, count: u64, is_write: bool) tso_memory_policy.MemoryClass {
        return process_impl_guest_memory.guestMemoryRangeClass(self, address, count, is_write);
    }

    fn memoryClassBoundary(class: tso_memory_policy.MemoryClass) tso_memory.Boundary {
        return process_impl_guest_memory.memoryClassBoundary(class);
    }

    fn loadGuestScalarAt(self: *const ElfState, comptime T: type, address: u64, bytes: []const u8) T {
        return process_impl_guest_memory.loadGuestScalarAt(self, T, address, bytes);
    }

    fn storeGuestScalarAt(self: *const ElfState, comptime T: type, address: u64, bytes: []u8, value: T, non_temporal: bool) void {
        return process_impl_guest_memory.storeGuestScalarAt(self, T, address, bytes, value, non_temporal);
    }

    fn fillGuestBacking(self: *const ElfState, destination: []u8, byte: u8) void {
        return process_impl_guest_memory.fillGuestBacking(self, destination, byte);
    }

    fn copyGuestBacking(self: *const ElfState, destination: []u8, source: []const u8) void {
        return process_impl_guest_memory.copyGuestBacking(self, destination, source);
    }

    /// Runtime bulk writes into device or protected pages are synchronous
    /// boundaries. Drain ordinary queued stores first, then temporarily
    /// detach that queue so the copy itself cannot be re-buffered as RAM.
    fn copyGuestBackingForClass(
        self: *const ElfState,
        destination: []u8,
        source: []const u8,
        class: tso_memory_policy.MemoryClass,
    ) void {
        return process_impl_guest_memory.copyGuestBackingForClass(self, destination, source, class);
    }

    fn fillGuestBackingForClass(
        self: *const ElfState,
        destination: []u8,
        byte: u8,
        class: tso_memory_policy.MemoryClass,
    ) void {
        return process_impl_guest_memory.fillGuestBackingForClass(self, destination, byte, class);
    }

    fn snapshotGuestBacking(self: *const ElfState, destination: []u8, source: []const u8) void {
        return process_impl_guest_memory.snapshotGuestBacking(self, destination, source);
    }

    pub fn read8(self: *const ElfState, vaddr: u64) u8 {
        return process_impl_guest_memory.read8(self, vaddr);
    }

    fn read8Backing(self: *const ElfState, vaddr: u64) u8 {
        return process_impl_guest_memory.read8Backing(self, vaddr);
    }

    /// A read nothing maps. Only KUSER_SHARED_DATA answers: Windows gives
    /// every process that page, and Xenia's Windows build takes the guest's
    /// interrupt time from it (`windows_guest/kuser_shared.zig`).
    fn unmappedGuestRead(self: *const ElfState, comptime T: type, vaddr: u64) T {
        return process_impl_guest_memory.unmappedGuestRead(self, T, vaddr);
    }

    /// The KUSER_SHARED_DATA clock, from the same guest clock that answers
    /// QueryPerformanceCounter and FILETIME.
    fn kuserClock(self: *const ElfState) kuser_shared.Clock {
        return process_impl_guest_memory.kuserClock(self);
    }

    pub fn read16(self: *const ElfState, vaddr: u64) u16 {
        return process_impl_guest_memory.read16(self, vaddr);
    }

    fn read16Backing(self: *const ElfState, vaddr: u64) u16 {
        return process_impl_guest_memory.read16Backing(self, vaddr);
    }

    pub fn read32(self: *const ElfState, vaddr: u64) u32 {
        return process_impl_guest_memory.read32(self, vaddr);
    }

    fn read32Backing(self: *const ElfState, vaddr: u64) u32 {
        return process_impl_guest_memory.read32Backing(self, vaddr);
    }

    pub fn read64(self: *const ElfState, vaddr: u64) u64 {
        return process_impl_guest_memory.read64(self, vaddr);
    }

    fn read64Backing(self: *const ElfState, vaddr: u64) u64 {
        return process_impl_guest_memory.read64Backing(self, vaddr);
    }

    pub fn write8(self: *ElfState, vaddr: u64, val: u8) void {
        return process_impl_guest_memory.write8(self, vaddr, val);
    }

    pub fn write16(self: *ElfState, vaddr: u64, val: u16) void {
        return process_impl_guest_memory.write16(self, vaddr, val);
    }

    pub fn write32(self: *ElfState, vaddr: u64, val: u32) void {
        return process_impl_guest_memory.write32(self, vaddr, val);
    }

    pub fn write64(self: *ElfState, vaddr: u64, val: u64) void {
        return process_impl_guest_memory.write64(self, vaddr, val);
    }

    /// The mapped-write trace is a bring-up diagnostic with a fixed budget
    /// and a floor, and it observes *stores* only. Both are named because
    /// `blockJitTlbConsider` withholds the write TLB while the trace can
    /// still fire, and a guard that outlived the trace it protects cost the
    /// 2026-09-19 run every one of its 35.7 billion memory accesses.
    pub const windows_memory_trace_budget: u32 = 64;
    pub const windows_memory_trace_floor: u64 = 0x40_0000_0000;
    // Bound the trace by guest progress as well as its event count. The
    // latest run logged all 19 eligible writes by 53.25M instructions, then
    // withheld write-TLB admission for millions of unrelated fills.
    pub const windows_memory_trace_step_budget: u64 = 100_000_000;

    inline fn traceWindowsMappedWrite(self: *ElfState, address: u64, width: u8, value: u64) void {
        return process_impl_guest_memory.traceWindowsMappedWrite(self, address, width, value);
    }

    /// Whether the mapped-write trace can still record anything. A spent
    /// trace must stop costing: a path it withholds (the lock-free time
    /// import, the write TLB) is judged by this, never by the flag.
    pub fn windowsMemoryTraceLive(self: *ElfState) bool {
        return process_impl_guest_memory.windowsMemoryTraceLive(self);
    }

    /// Reserve a bounded trace slot across all guest workers. A plain read
    /// followed by an increment races and can exceed the advertised budget.
    pub fn claimWindowsMemoryTraceEvent(self: *ElfState) bool {
        return process_impl_guest_memory.claimWindowsMemoryTraceEvent(self);
    }

    fn traceWindowsMappedWriteEnabled(self: *ElfState, address: u64, width: u8, value: u64) void {
        return process_impl_guest_memory.traceWindowsMappedWriteEnabled(self, address, width, value);
    }

    fn reportWindowsMemoryTrace(self: *ElfState) void {
        return process_impl_guest_memory.reportWindowsMemoryTrace(self);
    }

    /// Every guest store passes through here. The gate is inline so the
    /// common case (no watch address) is a load and a branch at the store
    /// site, and the formatting stays out of line.
    pub inline fn traceGuestWrite(self: *const ElfState, vaddr: u64, width: u8, value: u64) void {
        return process_impl_guest_memory.traceGuestWrite(self, vaddr, width, value);
    }

    fn traceGuestWriteWatched(self: *const ElfState, vaddr: u64, width: u8, value: u64) void {
        return process_impl_guest_memory.traceGuestWriteWatched(self, vaddr, width, value);
    }

    pub fn push(self: *ElfState, val: u64) void {
        return process_impl_guest_memory.push(self, val);
    }

    pub fn pop(self: *ElfState) u64 {
        return process_impl_guest_memory.pop(self);
    }

    fn completeWindowsQsortWithoutFrame(self: *ElfState, direct_return_rip: ?u64) void {
        return process_impl_guest_memory.completeWindowsQsortWithoutFrame(self, direct_return_rip);
    }

    fn failWindowsQsort(self: *ElfState, direct_return_rip: ?u64, detail: []const u8) void {
        return process_impl_guest_memory.failWindowsQsort(self, direct_return_rip, detail);
    }

    fn finishWindowsQsort(self: *ElfState) void {
        return process_impl_guest_memory.finishWindowsQsort(self);
    }

    fn continueWindowsQsort(self: *ElfState) void {
        return process_impl_guest_memory.continueWindowsQsort(self);
    }

    /// Start a guest-side insertion sort for the Microsoft CRT `qsort`
    /// import. The import handler has already identified the PE ABI; this
    /// method owns the callback stack and resumes the original caller only
    /// after every comparator call has returned.
    pub fn beginWindowsQsort(
        self: *ElfState,
        base: u64,
        nmemb: u64,
        element_size: u64,
        comparator: u64,
        direct_return_rip: ?u64,
    ) bool {
        return process_impl_guest_memory.beginWindowsQsort(self, base, nmemb, element_size, comparator, direct_return_rip);
    }

    /// Register one guest CRT termination callback without exposing a host
    /// function pointer. The ordinary and quick-exit tables are bounded and
    /// LIFO, matching the C runtime contract; the executable TLS callback is
    /// a separate one-slot callback with the Windows DLL_PROCESS_DETACH ABI.
    pub fn registerWindowsCrtAtexit(self: *ElfState, function: u64, quick: bool, is_thread_local: bool) bool {
        return process_impl_guest_memory.registerWindowsCrtAtexit(self, function, quick, is_thread_local);
    }

    fn returnFromWindowsCrtImport(self: *ElfState, direct_return_rip: ?u64) void {
        return process_impl_guest_memory.returnFromWindowsCrtImport(self, direct_return_rip);
    }

    fn failWindowsCrtExit(self: *ElfState, detail: []const u8) void {
        return process_impl_guest_memory.failWindowsCrtExit(self, detail);
    }

    fn finishWindowsCrtExit(self: *ElfState) void {
        return process_impl_guest_memory.finishWindowsCrtExit(self);
    }

    fn continueWindowsCrtExit(self: *ElfState) void {
        return process_impl_guest_memory.continueWindowsCrtExit(self);
    }

    /// Begin the guest-owned CRT exit protocol. `run_callbacks` distinguishes
    /// `exit`/`quick_exit`/`_cexit` from `_exit`/`_c_exit`; the latter skip all
    /// cleanup by contract. A non-returning exit terminates the emulated
    /// guest, while cexit-style calls return through their original ABI
    /// continuation after the callbacks drain.
    pub fn beginWindowsCrtExit(
        self: *ElfState,
        code: u64,
        quick: bool,
        run_callbacks: bool,
        return_to_caller: bool,
        direct_return_rip: ?u64,
    ) bool {
        return process_impl_guest_memory.beginWindowsCrtExit(self, code, quick, run_callbacks, return_to_caller, direct_return_rip);
    }

    fn failWindowsInitTerm(self: *ElfState, begin: u64, end: u64, detail: []const u8) void {
        return process_impl_guest_memory.failWindowsInitTerm(self, begin, end, detail);
    }

    fn finishWindowsInitTerm(self: *ElfState, result: u64) void {
        return process_impl_guest_memory.finishWindowsInitTerm(self, result);
    }

    fn continueWindowsInitTerm(self: *ElfState) void {
        return process_impl_guest_memory.continueWindowsInitTerm(self);
    }

    /// Start a guest-side walk of a Microsoft CRT `_initterm` table. The PE
    /// import stub has already placed its original return address on the guest
    /// stack, while the direct-call shortcut supplies the continuation here;
    /// both are preserved until every non-null initializer has returned.
    pub fn beginWindowsInitTerm(
        self: *ElfState,
        begin: u64,
        end: u64,
        direct_return_rip: ?u64,
        returns_error: bool,
    ) bool {
        return process_impl_guest_memory.beginWindowsInitTerm(self, begin, end, direct_return_rip, returns_error);
    }

    pub fn loadElf(self: *ElfState, elf_bytes: []const u8) !void {
        return process_impl_guest_diagnostics.loadElf(self, elf_bytes);
    }

    pub fn startLibcMain(self: *ElfState, main_addr: u64, argc: u64, argv: u64) void {
        return process_impl_guest_diagnostics.startLibcMain(self, main_addr, argc, argv);
    }

    fn scheduleNextInitOrMain(self: *ElfState) void {
        return process_impl_guest_diagnostics.scheduleNextInitOrMain(self);
    }

    fn startMainAfterInit(self: *ElfState) void {
        return process_impl_guest_diagnostics.startMainAfterInit(self);
    }

    pub fn handleSyntheticRip(self: *ElfState) bool {
        return process_impl_guest_diagnostics.handleSyntheticRip(self);
    }

    fn copyUnresolvedImportName(destination: []u8, source: []const u8) usize {
        return process_impl_guest_diagnostics.copyUnresolvedImportName(destination, source);
    }

    fn shouldReportWindowsPointOccurrence(occurrences: u64) bool {
        return process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrences);
    }

    pub fn terminateForWindowsFatalPoint(self: *ElfState, label: []const u8) void {
        return process_impl_guest_diagnostics.terminateForWindowsFatalPoint(self, label);
    }

    /// Stop the run at a fatal point, unless the operator allowed its label.
    fn terminateForWindowsFatalPointWith(
        self: *ElfState,
        label: []const u8,
        reason: exit_diagnostics.TerminationReason,
        exit_code: u64,
    ) void {
        return process_impl_guest_diagnostics.terminateForWindowsFatalPointWith(self, label, reason, exit_code);
    }

    /// Keep the operator's allow-list: labels separated by commas, spaces or
    /// semicolons.
    pub fn configureWindowsFatalPointAllow(self: *ElfState, text: ?[]const u8) void {
        return process_impl_guest_diagnostics.configureWindowsFatalPointAllow(self, text);
    }

    fn windowsFatalPointAllowed(self: *const ElfState, label: []const u8) bool {
        return process_impl_guest_diagnostics.windowsFatalPointAllowed(self, label);
    }

    /// Make a genuine unimplemented PE64 export an explicit emulated-guest
    /// failure. This is intentionally not a host crash: the caller gets a
    /// deterministic termination record, the source-of-truth log names the
    /// exact DLL/export, and the host remains available for the next run.
    /// Setting `ROSETTE_PE64_CAPABILITY_GAP_FATAL=0` is reserved for a
    /// deliberate compatibility experiment and still leaves a warning in
    /// the log; the default is fail-closed.
    pub fn terminateForWindowsCapabilityGap(self: *ElfState, dll_name: []const u8, function_name: []const u8) bool {
        return process_impl_guest_diagnostics.terminateForWindowsCapabilityGap(self, dll_name, function_name);
    }

    fn noteWindowsGuestCondition(self: *ElfState, condition: xenia_fatal_condition_map.Condition, line: []const u8) void {
        return process_impl_guest_diagnostics.noteWindowsGuestCondition(self, condition, line);
    }

    /// Print what Rosette knows about a guest line that reports a failure.
    ///
    /// A guest failure line is a claim about a conclusion, not about a cause.
    /// `Presenter: Failed to create a DXGI factory` is Xenia saying what it
    /// decided; it cannot say what Rosette answered that made it decide so,
    /// and the 2026-09-12 run printed exactly that line and nothing else -
    /// while Rosette itself held the export, the HRESULT it chose, the guest
    /// address that called it and the step it happened at.
    ///
    /// This is the other half. Each line's row in the warning table names
    /// which of Rosette's own ledgers is the counterpart, and this walks it.
    /// Nothing is printed for a line with no counterpart: "Rosette has no
    /// record of taking part in this" is a different and equally useful
    /// finding from "Rosette refused something", and inventing a cause for
    /// the first is how a log stops being evidence.
    fn substantiateGuestAdvisory(self: *const ElfState, line: []const u8) void {
        return process_impl_guest_diagnostics.substantiateGuestAdvisory(self, line);
    }

    /// The refusal ledger rows for one DLL whose export names start with a
    /// prefix, printed under the guest line they explain.
    fn substantiateFromImportLedger(
        self: *const ElfState,
        dll_name: []const u8,
        name_prefix: []const u8,
        consequence: []const u8,
    ) void {
        return process_impl_guest_diagnostics.substantiateFromImportLedger(self, dll_name, name_prefix, consequence);
    }

    /// What Rosette's Vulkan bridge saw around a guest shader-creation
    /// failure. The bridge forwards these to the real driver, so the counters
    /// say whether the refusal was Rosette's or MoltenVK's.
    pub fn substantiateVulkanShaderCreation(self: *const ElfState) void {
        return process_impl_guest_diagnostics.substantiateVulkanShaderCreation(self);
    }

    /// The eight-hex-digit XThread id Xenia prints after a log level marker
    /// (`!> F8000014 ...`), or null.
    pub fn guestLogLineThreadToken(line: []const u8) ?[]const u8 {
        return process_impl_guest_diagnostics.guestLogLineThreadToken(line);
    }

    /// Which guest thread wrote a log line, and the kernel export it last
    /// entered.
    ///
    /// Xenia names every guest thread `<name> (<id>)` and prefixes every log
    /// line with that id, and the kernel census records each thread's most
    /// recent export. Joining the two turns "ResolvePath() failed" into the
    /// call that asked for the path. Xenia's logger is asynchronous, so this
    /// is the last export the thread had entered when the line arrived - an
    /// attribution, stated as one.
    fn describeGuestLogLineOrigin(self: *const ElfState, line: []const u8, buffer: []u8) []const u8 {
        return process_impl_guest_diagnostics.describeGuestLogLineOrigin(self, line, buffer);
    }

    /// The empty `ResolvePath()` form is only an expected optional-probe
    /// advisory when the asynchronous Xenia log can be joined to the kernel
    /// census. The XEX header metadata path can issue the same optional empty
    /// object-name probe as the file/status path. Without one of those origins,
    /// the same text stays a fault: a new VFS failure must not become quiet
    /// merely because it happens to have empty parentheses.
    pub fn isConfirmedEmptyResolvePathProbe(line: []const u8, origin: []const u8) bool {
        return process_impl_guest_diagnostics.isConfirmedEmptyResolvePathProbe(line, origin);
    }

    fn parsePm4DrawFailure(line: []const u8) ?GpuDrawTuple {
        return process_impl_guest_diagnostics.parsePm4DrawFailure(line);
    }

    fn noteGpuDrawFailure(self: *ElfState, tuple: GpuDrawTuple) void {
        return process_impl_guest_diagnostics.noteGpuDrawFailure(self, tuple);
    }

    fn reportGpuDrawFailures(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGpuDrawFailures(self);
    }

    pub fn noteWindowsGuestWarning(self: *ElfState, line: []const u8) void {
        return process_impl_guest_diagnostics.noteWindowsGuestWarning(self, line);
    }

    /// Where governed guest output goes: straight to the host descriptor.
    const GuestOutputHostSink = struct {
        fd: std.posix.fd_t,
        failures: *u64,

        pub fn emit(self: GuestOutputHostSink, bytes: []const u8) void {
            var written: usize = 0;
            while (written < bytes.len) {
                const result = std.c.write(self.fd, bytes.ptr + written, bytes.len - written);
                if (result <= 0) {
                    self.failures.* +|= 1;
                    return;
                }
                written += @intCast(result);
            }
        }
    };

    /// Write guest stdout/stderr bytes to the host through the flood
    /// governor, and return the count the guest is told was written.
    ///
    /// The guest's write always succeeds in full: a log sink that throttles is
    /// Rosette's decision, and a guest that retried a short write would turn
    /// the throttle into a spin. Rosette's classifier is fed separately by
    /// the caller, so it still sees every byte.
    pub fn writeWindowsGuestStandardOutput(self: *ElfState, host_fd: std.posix.fd_t, stream_fd: u64, bytes: []const u8) usize {
        return process_impl_guest_diagnostics.writeWindowsGuestStandardOutput(self, host_fd, stream_fd, bytes);
    }

    fn flushWindowsGuestOutputGovernors(self: *ElfState) void {
        return process_impl_guest_diagnostics.flushWindowsGuestOutputGovernors(self);
    }

    /// What the guest output governor admitted and withheld.
    pub fn reportWindowsGuestOutputGovernor(self: *ElfState) void {
        return process_impl_guest_diagnostics.reportWindowsGuestOutputGovernor(self);
    }

    /// Count one `device not found` line for a bare module name, by name.
    fn noteGuestModuleLookupLine(self: *ElfState, module: []const u8) u64 {
        return process_impl_guest_diagnostics.noteGuestModuleLookupLine(self, module);
    }

    /// Every bare module name Xenia's lookups printed, joined to the VFS
    /// ledger and to Xenia's own unresolved-import warnings.
    fn reportGuestModuleLookups(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGuestModuleLookups(self);
    }

    fn processWindowsGuestOutputLine(self: *ElfState, line: []const u8, truncated: bool) void {
        return process_impl_guest_diagnostics.processWindowsGuestOutputLine(self, line, truncated);
    }

    /// Observe bytes written by the PE guest to stdout/stderr. This is the
    /// Rosette-side equivalent of a logger hook: no Xenia source change is
    /// needed, and partial writes are reassembled before matching phrases.
    pub fn noteWindowsGuestOutput(self: *ElfState, bytes: []const u8) void {
        return process_impl_guest_diagnostics.noteWindowsGuestOutput(self, bytes);
    }

    fn flushWindowsGuestOutput(self: *ElfState) void {
        return process_impl_guest_diagnostics.flushWindowsGuestOutput(self);
    }

    fn logWindowsGuestFailurePointSummary(self: *const ElfState) void {
        return process_impl_guest_diagnostics.logWindowsGuestFailurePointSummary(self);
    }

    /// Record one unresolved import without putting an instruction-wide trace
    /// on the successful path.  Repeated calls to the same symbol are folded
    /// into one record so a bad polling loop cannot flood the terminal or the
    /// detailed `.rosette` log.
    pub fn recordUnresolvedWindowsImport(self: *ElfState, stub: WindowsImportStub) bool {
        return process_impl_guest_diagnostics.recordUnresolvedWindowsImport(self, stub);
    }

    /// Record the library a module handle names.
    pub fn noteWindowsLoadedModule(self: *ElfState, handle: u64, module_name: []const u8) void {
        return process_impl_guest_diagnostics.noteWindowsLoadedModule(self, handle, module_name);
    }

    /// The library a module handle names, or an empty slice when this run did
    /// not issue the handle. Empty is not "kernel32": a lookup against an
    /// unknown handle has to stay attributable to nothing.
    pub fn windowsLoadedModuleName(self: *const ElfState, handle: u64) []const u8 {
        return process_impl_guest_diagnostics.windowsLoadedModuleName(self, handle);
    }

    fn recordDynamicRefusal(
        records: []WindowsDynamicRefusal,
        count: *u32,
        scope: []const u8,
        name: []const u8,
        is_gap: bool,
        caller_rip: u64,
    ) bool {
        return process_impl_guest_diagnostics.recordDynamicRefusal(records, count, scope, name, is_gap, caller_rip);
    }

    /// A `LoadLibrary` Rosetta answered with ERROR_MOD_NOT_FOUND.
    ///
    /// `is_gap` separates a decision from a hole: Direct3D is refused on
    /// purpose and every caller has a fallback, while a library nobody has
    /// written a package for is a finding. A log that spells them the same
    /// way buries the second in the first.
    pub fn noteWindowsModuleRefusal(
        self: *ElfState,
        api: []const u8,
        module_path: []const u8,
        reason: []const u8,
        is_gap: bool,
        fallback: []const u8,
        caller_rip: u64,
    ) void {
        return process_impl_guest_diagnostics.noteWindowsModuleRefusal(self, api, module_path, reason, is_gap, fallback, caller_rip);
    }

    /// A `GetProcAddress` Rosetta answered with NULL.
    pub fn noteWindowsProcAddressRefusal(
        self: *ElfState,
        dll_name: []const u8,
        function_name: []const u8,
        caller_rip: u64,
    ) void {
        return process_impl_guest_diagnostics.noteWindowsProcAddressRefusal(self, dll_name, function_name, caller_rip);
    }

    /// A `GetProcAddress` refused on purpose: an optional export whose caller
    /// has a documented path for NULL.
    ///
    /// Reported apart from a gap, and with the path named. The same
    /// `GAP-name-not-in-Rosette's-import-inventory` wording used to cover
    /// `WaitOnAddress`, which the catalogue already refuses by decision because
    /// SDL builds its semaphores on kernel objects without it.
    pub fn noteWindowsProcAddressPolicyRefusal(
        self: *ElfState,
        dll_name: []const u8,
        function_name: []const u8,
        caller_rip: u64,
        fallback: []const u8,
        api_set_host: []const u8,
    ) void {
        return process_impl_guest_diagnostics.noteWindowsProcAddressPolicyRefusal(self, dll_name, function_name, caller_rip, fallback, api_set_host);
    }

    /// A C runtime import handed a pointer Rosette could not read.
    ///
    /// The CRT dereferences its arguments; on Windows an unmapped or null
    /// pointer here is an access violation in the caller, never an empty
    /// string. Rosette's reader used to know only the PE image, so `strlen`
    /// answered 0 for every string in Xenia's guest address space and
    /// `RtlInitAnsiString` built every name the title opened with Length 0.
    pub fn noteWindowsCrtUnreadable(self: *ElfState, address: u64, length: u64) void {
        return process_impl_guest_diagnostics.noteWindowsCrtUnreadable(self, address, length);
    }

    /// A C-runtime string or memory function handed a pointer Rosette cannot
    /// read. `return_rip` is where the import returns to, or zero if unknown.
    ///
    /// The first report named only the import thunk as the caller, and the
    /// 2026-09-14 occurrences (a memcpy of 0xFFFFFFFF00000000 bytes, then one
    /// from 0xFFFFFFFF00000001) could not be traced to the code that built
    /// those arguments. The return address and the argument registers can.
    pub fn noteWindowsCrtUnreadableFrom(self: *ElfState, address: u64, length: u64, return_rip: u64) void {
        return process_impl_guest_diagnostics.noteWindowsCrtUnreadableFrom(self, address, length, return_rip);
    }

    /// One worker turn served from inside an idle `GetMessage`.
    pub fn noteGetMessageIdleTurn(self: *ElfState, steps: u64) void {
        return process_impl_guest_diagnostics.noteGetMessageIdleTurn(self, steps);
    }

    /// A module-name pointer Rosetta could not read as a name.
    ///
    /// Deliberately not a refusal. Deciding a library is absent from bytes
    /// that are not a library name reports a loadable library as missing and
    /// sends a reader after a package that already exists, so the load is
    /// allowed and the *read* is what gets reported.
    pub fn noteWindowsUnreadableModuleName(
        self: *ElfState,
        api: []const u8,
        raw: []const u8,
        pointer: u64,
        caller_rip: u64,
    ) void {
        return process_impl_guest_diagnostics.noteWindowsUnreadableModuleName(self, api, raw, pointer, caller_rip);
    }

    /// The ordered set of things that must happen before a Xenia frame can
    /// reach the screen, and which of them this run reached.
    ///
    /// The presentation chain already answers "did anything present?" This
    /// answers the question a reader actually has next: *what is the first
    /// thing that has not happened, and whose job is it?* Every stage names
    /// an owner, because the fix for a Rosette stage and the fix for a Xenia
    /// stage are in different repositories - and because a stage owned by the
    /// title is not a defect at all until the title has been given a chance
    /// to reach it.
    ///
    /// Stages are ordered by dependency. Reporting anything past the first
    /// unmet one as a problem would be reporting a consequence.
    pub fn firstFrameChainStages(self: *const ElfState) [FIRST_FRAME_STAGE_COUNT]ChainStage {
        return process_impl_guest_diagnostics.firstFrameChainStages(self);
    }

    /// The earliest unmet precondition, or null when a frame could be shown.
    ///
    /// Separate from the report so the verdict can be asserted rather than
    /// read out of a log. A chain whose ordering is wrong still prints a
    /// plausible-looking answer; it just blames the wrong owner.
    pub fn firstFrameWall(self: *const ElfState) ?ChainStage {
        return process_impl_guest_diagnostics.firstFrameWall(self);
    }

    pub fn reportFirstFrameChain(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportFirstFrameChain(self);
    }

    fn reportUiDrawEvidence(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportUiDrawEvidence(self);
    }

    /// The export shims whose entry proves a milestone, joined into a label.
    ///
    /// Comptime, because the witness table is comptime and the answer is one
    /// fixed string per stage. A stage with no shim witness gets an empty
    /// label, which the report prints as nothing rather than as a witness
    /// that read zero - an absent witness and a silent one are not the same
    /// claim, and only one of them is about the title.
    fn witnessLabel(comptime milestone: []const u8) []const u8 {
        return process_impl_guest_diagnostics.witnessLabel(milestone);
    }

    /// Whether either of a stage's witnesses fired.
    ///
    /// The implementation and the shim answer the same question and fail
    /// differently: an optimiser can inline the first out of existence, and
    /// nothing can reach the second except the guest. Requiring both would
    /// make an inlined build look like a stalled title, which is the exact
    /// mistake `GraphicsSystem::MarkVblank` cost this project two runs ago.
    fn guestStageMet(self: *const ElfState, comptime milestone: []const u8) bool {
        return process_impl_guest_diagnostics.guestStageMet(self, milestone);
    }

    /// A virtual Xenia function can be entered through the base symbol or
    /// through the implementation selected by the object's vtable. Both
    /// entries answer the same chain question, so the stage must observe the
    /// pair rather than treating a zero in the base row as a stalled GPU.
    fn guestMilestoneStageHitsAny(
        self: *const ElfState,
        comptime primary: []const u8,
        comptime alternate: []const u8,
    ) u64 {
        return process_impl_guest_diagnostics.guestMilestoneStageHitsAny(self, primary, alternate);
    }

    fn guestStageMetAny(
        self: *const ElfState,
        comptime primary: []const u8,
        comptime alternate: []const u8,
    ) bool {
        return process_impl_guest_diagnostics.guestStageMetAny(self, primary, alternate);
    }

    fn guestMilestoneStageObservableAny(
        self: *const ElfState,
        comptime primary: []const u8,
        comptime alternate: []const u8,
    ) bool {
        return process_impl_guest_diagnostics.guestMilestoneStageObservableAny(self, primary, alternate);
    }

    fn guestMilestoneStageUnobservableReasonAny(
        self: *const ElfState,
        comptime primary: []const u8,
        comptime alternate: []const u8,
    ) []const u8 {
        return process_impl_guest_diagnostics.guestMilestoneStageUnobservableReasonAny(self, primary, alternate);
    }

    /// The stages between a window that can carry a frame and a window that
    /// carries the title's picture.
    ///
    /// Every stage's evidence is an entry count on one of Xenia's own
    /// functions, except the last two, which are Rosette's. That split is the
    /// point: the transport chain is built entirely from what Rosette can
    /// see, and what Rosette can see cannot distinguish a frame with a
    /// picture from a frame without one. Both look like acquire, clear,
    /// submit, present.
    ///
    /// A row whose symbol the image does not contain reports `unresolved`
    /// rather than `unmet`. Those are different claims: one says Rosette
    /// cannot see the stage, the other says the guest did not reach it, and
    /// reading the first as the second would blame a title for a stripped
    /// binary.
    pub fn guestOutputChainStages(self: *const ElfState) [GUEST_OUTPUT_STAGE_COUNT]ChainStage {
        return process_impl_guest_diagnostics.guestOutputChainStages(self);
    }

    /// The earliest guest-output stage the run has not reached.
    pub fn guestOutputWall(self: *const ElfState) ?ChainStage {
        return process_impl_guest_diagnostics.guestOutputWall(self);
    }

    pub fn reportGuestOutputChain(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGuestOutputChain(self);
    }

    /// Where a worker thread is right now: its live RIP when it is the one
    /// executing, its parked RIP otherwise.
    /// Which symbol the vblank count came from in this image.
    ///
    /// `MarkVblank` when the build kept it out of line, its witness when the
    /// build inlined it, and a marker when neither can be seen. Printing the
    /// number without the source is how `MarkVblank_entries=0` was read for
    /// two runs as a stopped display clock.
    fn vblankWitnessName(self: *const ElfState) []const u8 {
        return process_impl_guest_diagnostics.vblankWitnessName(self);
    }

    /// Describe a wait handle that turns out to be another guest thread.
    ///
    /// Returns an empty slice when the handle names something else - an
    /// event, a mutant, an object Rosette does not track as a thread - so the
    /// caller's line is unchanged in that case. Naming only what is certain
    /// keeps the annotation from becoming a guess.
    pub fn describeWindowsWaitTarget(self: *const ElfState, handle: u64, buffer: []u8) []const u8 {
        return process_impl_guest_diagnostics.describeWindowsWaitTarget(self, handle, buffer);
    }

    /// Distinguish a real wait cycle from a join chain whose target is still
    /// runnable. A bare blocked handle cannot answer that question: the main
    /// thread in the observed run waited on a live XThread, and the live
    /// XThread was itself the one doing useful work. Follow only the bounded
    /// guest-thread edges and keep non-thread objects as a separate verdict.
    fn windowsJoinVerdict(self: *const ElfState, handle: u64) []const u8 {
        return process_impl_guest_diagnostics.windowsJoinVerdict(self, handle);
    }

    /// Read guest bytes for the spin disassembler.
    ///
    /// Routed through the same two sources `decodeAt` uses, so a loop in a
    /// JIT buffer disassembles exactly as one in the image does. A separate
    /// path here would be a second answer to "what bytes are at this
    /// address", and the two would drift.
    fn readGuestCodeForSpin(context: *const anyopaque, address: u64, out: []u8) usize {
        return process_impl_guest_diagnostics.readGuestCodeForSpin(context, address, out);
    }

    /// Where a Rosette address sits in Xenia's guest memory, as a log suffix.
    ///
    /// Xenia's translated code addresses guest memory as membase plus the
    /// guest address. A spin in its code cache that reads `[rdi+0x7fc80714]`
    /// is a title polling a GPU register, and the symbolizer can only call
    /// that address "guest heap".
    pub fn describeXeniaGuestAddress(self: *const ElfState, address: u64, buffer: []u8) []const u8 {
        return process_impl_guest_diagnostics.describeXeniaGuestAddress(self, address, buffer);
    }

    /// Disassemble the loop a thread is going round in, and name what it
    /// reads.
    ///
    /// The report a run needs once the wall belongs to the guest. "A thread
    /// is busy at an address" is not a finding - a thread rasterizing a font
    /// atlas looks the same. What separates them is whether the addresses
    /// move, and if they do not, what the unmoving code reads and who is
    /// supposed to write it.
    fn reportGuestThreadSpin(self: *const ElfState, index: usize) void {
        return process_impl_guest_diagnostics.reportGuestThreadSpin(self, index);
    }

    /// Record a region of the guest's address space.
    ///
    /// Called by the loader for the image's sections and the thunk area, and
    /// by the Win32 surface for allocations. Bounded and silent on overflow;
    /// the report states the overflow count rather than each drop.
    pub fn noteGuestRegion(
        self: *ElfState,
        address: u64,
        length: u64,
        kind: guest_address_space.RegionKind,
        label: []const u8,
    ) void {
        return process_impl_guest_diagnostics.noteGuestRegion(self, address, length, kind, label);
    }

    /// Record an allocation the guest made, so a thread later found executing
    /// inside it can be told what it is running.
    pub fn noteGuestExecutableAllocation(self: *ElfState, address: u64, length: u64, protection: u32) void {
        return process_impl_guest_diagnostics.noteGuestExecutableAllocation(self, address, length, protection);
    }

    /// The same, labelled with the code that asked for it.
    ///
    /// A region reading `generated-code+0x44b` says the thread is in memory
    /// the guest generated. A region reading
    /// `generated-code:X64CodeCache::AllocateCode+0x44b` says which part of
    /// the guest generated it, and that is usually the whole answer: a
    /// translator's first page holds its dispatch thunks, and a thread going
    /// round inside those is not running the title's code at all.
    pub fn noteGuestExecutableAllocationFrom(
        self: *ElfState,
        address: u64,
        length: u64,
        protection: u32,
        caller_rip: u64,
    ) void {
        return process_impl_guest_diagnostics.noteGuestExecutableAllocationFrom(self, address, length, protection, caller_rip);
    }

    /// Every region Rosette recorded, and how much of the run asked about it.
    pub fn reportGuestAddressSpace(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGuestAddressSpace(self);
    }

    /// The address of one of the CRT's timezone globals.
    ///
    /// `__daylight`, `__timezone` and `__tzname` are accessor *functions* that
    /// return pointers the caller dereferences without checking. A stub
    /// returning zero is therefore not a wrong timezone - it is a null
    /// dereference in the guest, which is why these three are handled here
    /// rather than left to the ABI fallback.
    ///
    /// One block holds all three: an `int` daylight flag, a `long` offset,
    /// and a two-entry array of `char *` pointing at the names. Rosette
    /// reports UTC, so the flag is zero, the offset is zero, and both names
    /// are "UTC".
    pub fn windowsTimezoneGlobal(self: *ElfState, name: []const u8) u64 {
        return process_impl_guest_diagnostics.windowsTimezoneGlobal(self, name);
    }

    /// The static `struct tm` `gmtime` returns a pointer into.
    ///
    /// The C library's contract is that the result points at storage the
    /// library owns and the next call overwrites. Allocating per call would
    /// leak; returning null would be a guest crash.
    pub fn windowsStaticTmBuffer(self: *ElfState) u64 {
        return process_impl_guest_diagnostics.windowsStaticTmBuffer(self);
    }

    /// Carry an `OutputDebugString` into Rosette's own log.
    ///
    /// Rosette is the debugger this call is addressed to. Discarding the text
    /// would throw away the one channel a guest has for saying something no
    /// counter can express, and the first few are usually the interesting
    /// ones - so they are logged, then counted.
    pub fn noteWindowsDebugString(self: *ElfState, text: []const u8) void {
        return process_impl_guest_diagnostics.noteWindowsDebugString(self, text);
    }

    /// Record the name the guest gave one of its threads.
    ///
    /// `handle` is the Win32 thread handle, or the `GetCurrentThread`
    /// pseudo-handle, in which case the name lands on whichever worker is
    /// executing - which is what `xe::threading::set_name(name)` means.
    ///
    /// Returns whether a slot took the name. A false is not an error: a guest
    /// can name a thread Rosette runs on the owner loop rather than in a
    /// worker slot, and a report that says nothing about that thread is
    /// better than one that labels the wrong one.
    pub fn setWindowsGuestThreadName(self: *ElfState, handle: u64, name: []const u8) bool {
        return process_impl_guest_diagnostics.setWindowsGuestThreadName(self, handle, name);
    }

    fn windowsGuestThreadSlotForName(self: *const ElfState, handle: u64) ?usize {
        return process_impl_guest_diagnostics.windowsGuestThreadSlotForName(self, handle);
    }

    fn windowsGuestThreadRip(self: *const ElfState, index: usize) u64 {
        return process_impl_guest_diagnostics.windowsGuestThreadRip(self, index);
    }

    /// The live worker holding the largest share of the run, if any. A
    /// completed worker may retain historical instruction steps in its table
    /// slot, but it cannot be the source of current starvation or slowdown.
    pub fn busiestWindowsGuestThread(self: *const ElfState) ?usize {
        return process_impl_guest_diagnostics.busiestWindowsGuestThread(self);
    }

    /// One line naming the thread that is spending the run.
    ///
    /// The frontier sampler reads `self.guestContextField("regs").*.rip`, which at a checkpoint is
    /// always the owner - so on a run where the workers hold ninety percent
    /// of the budget the frontier histogram describes the one thread that is
    /// doing the least. This is the line that says who the other ninety
    /// percent belongs to.
    /// Roll each thread's code-page fingerprint into the previous window and
    /// start a new one. Called once per checkpoint, so the report reads
    /// "where this thread has been lately" rather than "everywhere it has
    /// ever been", which saturates and says nothing.
    pub fn rollGuestThreadCodeWindows(self: *ElfState) void {
        return process_impl_guest_diagnostics.rollGuestThreadCodeWindows(self);
    }

    fn logGuestThreadShare(self: *const ElfState) void {
        return process_impl_guest_diagnostics.logGuestThreadShare(self);
    }

    /// Report the hidden-window message route Xenia needs before it can
    /// attach its presenter or launch the requested target.
    pub fn reportWindowsUiPipeline(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportWindowsUiPipeline(self);
    }

    /// Every guest worker, what it has spent, and where it is.
    ///
    /// Nothing else in the run reports this. The checkpoint's `workers(...)`
    /// tuple counts statuses, the frontier samples only the owner, and the
    /// scheduler line totals the slices without saying who took them - so a
    /// run in which one thread spins and thirteen starve looks exactly like a
    /// run in which the work is shared.
    pub fn reportGuestThreads(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGuestThreads(self);
    }

    const WindowsBlockedCause = enum {
        timed_condition,
        condition,
        finite_handle,
        infinite_handle,
        srw_lock,
        deadline,
        unknown,

        pub fn label(self: WindowsBlockedCause) []const u8 {
            return switch (self) {
                .timed_condition => "timed_condition",
                .condition => "condition",
                .finite_handle => "finite_handle",
                .infinite_handle => "infinite_handle",
                .srw_lock => "srw_lock",
                .deadline => "deadline",
                .unknown => "unknown",
            };
        }

        pub fn action(self: WindowsBlockedCause) []const u8 {
            return switch (self) {
                .timed_condition => "ETIMEDOUT is returned at the guest-clock deadline; do not synthesize a signal, and inspect signal/broadcast only if this condition carries graphics work",
                .condition => "find the signal or broadcast owner; Rosette wakes a waiter only after a real guest notification",
                .finite_handle => "allow the guest-clock timeout to expire; inspect the producer if output depends on this wait and it keeps expiring",
                .infinite_handle => "find SetEvent, ReleaseSemaphore, or thread completion for this handle; a runnable producer makes this a legitimate wait, not a Rosette deadlock",
                .srw_lock => "find the releasing owner; Rosette directs the oldest waiter during the handoff",
                .deadline => "this is an expected deadline park, not an object wait; verify the guest clock reaches the stored deadline",
                .unknown => "the blocked state has no recognized wait model; add the missing Rosette wait boundary before changing wake policy",
            };
        }
    };

    fn classifyWindowsBlockedThread(thread: *const WindowsGuestThread) WindowsBlockedCause {
        return process_impl_guest_diagnostics.classifyWindowsBlockedThread(thread);
    }

    /// The finding is the thing a run can act on; the blocked cause above is
    /// only the shape of the wait.  In particular, an infinite wait on a
    /// thread that is itself active is a live join chain, while an infinite
    /// wait on a thread that is not ready is a real upstream dependency.  The
    /// same distinction is made for condition and finite-handle waits by
    /// consulting the duration ledger for this live waiter.
    const WindowsBlockedFinding = enum {
        expected_deadline,
        periodic_timeout_poll,
        active_join_chain,
        join_target_not_ready,
        join_cycle,
        unsignalled_condition,
        condition_producer_pending,
        timeout_hotspot,
        producer_not_ready,
        active_wait_with_history,
        lock_owner_pending,
        ready_but_blocked,
        missing_wait_model,

        pub fn label(self: WindowsBlockedFinding) []const u8 {
            return switch (self) {
                .expected_deadline => "expected_deadline",
                .periodic_timeout_poll => "periodic_timeout_poll",
                .active_join_chain => "active_join_chain",
                .join_target_not_ready => "join_target_not_ready",
                .join_cycle => "join_cycle",
                .unsignalled_condition => "unsignalled_condition",
                .condition_producer_pending => "condition_producer_pending",
                .timeout_hotspot => "timeout_hotspot",
                .producer_not_ready => "producer_not_ready",
                .active_wait_with_history => "active_wait_with_history",
                .lock_owner_pending => "lock_owner_pending",
                .ready_but_blocked => "ready_but_blocked",
                .missing_wait_model => "missing_wait_model",
            };
        }

        pub fn priority(self: WindowsBlockedFinding) u8 {
            return switch (self) {
                .expected_deadline => 10,
                .periodic_timeout_poll => 20,
                .active_join_chain => 25,
                .timeout_hotspot => 60,
                .producer_not_ready, .condition_producer_pending => 70,
                .active_wait_with_history => 5,
                .lock_owner_pending, .unsignalled_condition => 80,
                .join_target_not_ready => 85,
                .join_cycle => 95,
                .missing_wait_model, .ready_but_blocked => 100,
            };
        }

        pub fn isLivenessFinding(self: WindowsBlockedFinding) bool {
            return switch (self) {
                .expected_deadline, .periodic_timeout_poll, .active_join_chain, .timeout_hotspot, .active_wait_with_history => false,
                else => true,
            };
        }

        pub fn isExpected(self: WindowsBlockedFinding) bool {
            return self == .expected_deadline or self == .active_join_chain;
        }

        pub fn action(self: WindowsBlockedFinding) []const u8 {
            return switch (self) {
                .expected_deadline => "verify guest-clock advancement to the stored deadline; this park is expected pacing",
                .periodic_timeout_poll => "correlate the timed caller with its optional-service producer; repeated expiry is cost, not a missing signal by itself",
                .active_join_chain => "the join chain reaches an active target; monitor target progress before calling this a deadlock",
                .join_target_not_ready => "inspect the target thread's last import/status and the event that completes it; this join is upstream of screen output",
                .join_cycle => "break the join cycle or repair the thread-completion edge; no timeout can resolve an infinite cycle",
                .unsignalled_condition => "find the signal/broadcast owner for this condition; no notification is recorded for the active waiter",
                .condition_producer_pending => "inspect the condition producer and signal ordering; prior signals exist but this waiter remains active",
                .timeout_hotspot => "inspect the finite-handle producer and decide whether repeated expiry is intentional polling or missing work",
                .producer_not_ready => "find SetEvent, ReleaseSemaphore, thread completion, or the producer for this handle; do not synthesize readiness",
                .active_wait_with_history => "signals or completions have occurred for this active handle; retain it as producer context, not as an unresolved blocker",
                .lock_owner_pending => "find the releasing SRW owner and its last progress point; the oldest waiter should be handed off on release",
                .ready_but_blocked => "the object is ready while the thread is still blocked; audit wake consumption and scheduler state before continuing",
                .missing_wait_model => "add the missing Rosette wait boundary; answering this wait would invent progress",
            };
        }
    };

    fn windowsWaitCostSiteForThread(self: *const ElfState, thread: *const WindowsGuestThread) ?*const wait_cost.Site {
        return process_impl_guest_diagnostics.windowsWaitCostSiteForThread(self, thread);
    }

    /// Find the oldest currently blocked thread represented by a ledger site.
    /// The wait token is the authoritative join; the field-based fallback is
    /// for a site whose token could not be allocated because the bounded
    /// ledger was full. A diagnostic must be able to say that no waiter was
    /// found instead of borrowing an unrelated thread with a similar handle.
    fn windowsWaiterSlotForSite(self: *const ElfState, site_index: usize, site: wait_cost.Site) ?usize {
        return process_impl_guest_diagnostics.windowsWaiterSlotForSite(self, site_index, site);
    }

    /// Emit the causal snapshot behind a newly material liveness/cost
    /// finding. The ordinary ranked report is intentionally repeatable; this
    /// path is a bounded trigger that preserves the state at the first
    /// actionable observation, including the producer-side evidence needed
    /// to decide whether the problem is in the guest or in Rosetta's wake
    /// model.
    fn reportWindowsWaitEscalation(
        self: *ElfState,
        site_index: usize,
        site: *const wait_cost.Site,
        classification: wait_cost.Classification,
    ) void {
        return process_impl_guest_diagnostics.reportWindowsWaitEscalation(self, site_index, site, classification);
    }

    /// Turn repeated ledger classifications into bounded events. The
    /// periodic report remains the durable summary; these events are the
    /// handoff a human can use to inspect the next run without reconstructing
    /// the cause from several heartbeats.
    fn reportWindowsWaitEscalations(self: *ElfState) void {
        return process_impl_guest_diagnostics.reportWindowsWaitEscalations(self);
    }

    fn classifyWindowsBlockedFinding(self: *const ElfState, thread: *const WindowsGuestThread) WindowsBlockedFinding {
        return process_impl_guest_diagnostics.classifyWindowsBlockedFinding(self, thread);
    }

    /// Print the bounded wait graph that sits underneath the thread report.
    ///
    /// A timed condition timeout is not a lost wakeup by itself: the guest
    /// requested a deadline and the correct Rosette action is to return
    /// ETIMEDOUT. Likewise, an infinite join on a runnable thread is not a
    /// deadlock. This report names the cause, the object state, and the
    /// producer status so the next run can target the actual missing signal
    /// instead of shortening every wait.
    fn reportWindowsBlockedDiagnostics(self: *const ElfState, limit: usize) void {
        return process_impl_guest_diagnostics.reportWindowsBlockedDiagnostics(self, limit);
    }

    /// Turn the raw wait graph and duration ledger into a short ranked action
    /// list.  The full reports remain the audit trail; this report is the
    /// answer to "what do I inspect first?" and is emitted at heartbeats and
    /// at exit so a long run does not require reconstructing a finding from
    /// lines written hours apart.
    fn reportWindowsWaitFindings(self: *ElfState) void {
        return process_impl_guest_diagnostics.reportWindowsWaitFindings(self);
    }

    /// Put wait evidence ahead of the last-mile screen verdict.  A screen
    /// chain can be perfectly instrumented and still be downstream of a
    /// worker that never reaches its producer, a join whose target never
    /// completes, or a wait model Rosette does not understand.  This compact
    /// precedence line makes that causal order explicit at exit without
    /// asking the reader to reconstruct it from the full blocked-thread
    /// sample above.
    fn reportWindowsUpstreamWaitPriority(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportWindowsUpstreamWaitPriority(self);
    }

    /// Report the cost of synchronization separately from its correctness
    /// counters. A timeout count alone cannot tell a harmless one-shot delay
    /// from a 99%-timeout poll that consumed the interpreter; duration and
    /// overshoot make that distinction explicit and keep producer evidence
    /// beside the consumer that waited for it.
    fn reportWindowsWaitCost(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportWindowsWaitCost(self);
    }

    /// Every armed milestone, its entry count, and the step it was first
    /// reached at.
    ///
    /// A chain collapses a count to a boolean, and the counts carry the rest
    /// of the story: one entry into `PaintFromUIThread` and one thousand are
    /// the same `met`. Written at exit rather than at every checkpoint,
    /// because the chain rows already carry each stage's own count and
    /// sixteen mostly-unchanged lines per wall move is how a log stops being
    /// read.
    /// Name the thread that owns a guest-title wall, and say what it is doing.
    ///
    /// A verdict that ends at "this belongs to the title" leaves a reader to
    /// find the title's thread in a list of fifteen and work out for
    /// themselves whether it is running, blocked, or going round in a loop.
    /// The thread is identified by having entered `XThread::Execute`, which
    /// is the only thing in the table that means "translated PowerPC ran on
    /// this thread".
    fn reportGuestTitleThreadForWall(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGuestTitleThreadForWall(self);
    }

    /// Entries into a milestone, and the step it last happened at.
    pub fn guestMilestoneActivity(self: *const ElfState, mangled: []const u8) GuestMilestoneActivity {
        return process_impl_guest_diagnostics.guestMilestoneActivity(self, mangled);
    }

    /// Combine the base and Vulkan override rows for a virtual GPU method.
    /// Unlike an inline proxy these are alternative implementations, so both
    /// counts represent real work and are added rather than maxed.
    fn guestMilestoneActivityAny(
        self: *const ElfState,
        comptime primary: []const u8,
        comptime alternate: []const u8,
    ) struct { hits: u64, last_step: u64, armed: bool } {
        return process_impl_guest_diagnostics.guestMilestoneActivityAny(self, primary, alternate);
    }

    /// Whether the title is walking through its own program or looping inside
    /// code it already has.
    ///
    /// The one question the guest output chain cannot ask. Between two kernel
    /// calls a title executes translated PowerPC, and Rosette has no name for
    /// any of it: the 2026-09-12 run had `Main XThread` holding 22% of the
    /// interpreter at an address inside Xenia's JIT cache, and every report
    /// that looked at it could say only that it was busy.
    ///
    /// Xenia translates a guest function the first time control reaches it,
    /// so the count of translations is a progress axis a spin cannot advance
    /// - which is exactly the property `rosette-external-progress-axis`
    /// demands and no counter in this file had.
    pub fn reportGuestCodeProgress(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGuestCodeProgress(self);
    }

    /// Whether guest page protection is being enforced, and whether a
    /// protected access reached the guest's handler.
    ///
    /// The last row is the one the ring wall needs: a title's write to the
    /// ring write pointer travels fault -> vectored handler -> MMIO handler
    /// -> register callback -> `UpdateWritePointer` -> `ExecutePrimaryBuffer`,
    /// and every hop has a count. The first zero is where it stopped.
    pub fn reportGuestAccessViolations(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGuestAccessViolations(self);
    }

    /// Which SRW locks threads fought over, who holds each, and who waits.
    pub fn reportGuestLockContention(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGuestLockContention(self);
    }

    /// Where a contended lock's owner took it, and where that owner is now:
    /// the code addresses on its stack at the acquisition and at this report.
    /// A recursive lock that is never released (Xenia's global mutex spinning
    /// in `EntryTable::GetOrCreate` on 2026-09-30) is held by a frame that
    /// only these name.
    fn reportWindowsSrwOwnerStacks(self: *const ElfState, lock: WindowsSrwLock) void {
        return process_impl_guest_diagnostics.reportWindowsSrwOwnerStacks(self, lock);
    }

    /// Every kernel export the title called, in the order it first called
    /// them, with the boot phase they place it in.
    ///
    /// This is the report the guest output chain has needed since it was
    /// written. The chain can say `title_queried_video_mode` is the wall; it
    /// cannot say what the title asked for *instead*, because until the
    /// export shims were armed nothing in Rosette could see a single act of
    /// the translated PowerPC. A stage reading zero is the absence of a
    /// diagnosis. This is the diagnosis.
    pub fn reportGuestKernelCalls(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGuestKernelCalls(self);
    }

    /// What the console publishes that this Xenia build does not implement.
    ///
    /// Static: it is a join between the Xbox 360's own export tables and the
    /// shims this image carries, and it says nothing about the run. It is
    /// here because "what is missing" had no answer at all before it, in any
    /// form - a title that calls an export Xenia does not implement reaches
    /// the unimplemented-export path, and no counter anywhere in Rosette
    /// could name what it had asked for.
    fn reportGuestKernelCoverage(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGuestKernelCoverage(self);
    }

    pub fn reportGuestMilestones(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGuestMilestones(self);
    }

    /// Split a milestone's entries by the call site they came from.
    ///
    /// Silent for a row with one caller, which is most of them. A witness row
    /// is the case this exists for: `EmulateCPInterruptDPC` stands in for the
    /// inlined `MarkVblank`, and three other places in the image also call
    /// it, so its total is a superset of the vblank count and reading it as
    /// the display rate overstates it.
    fn reportGuestMilestoneCallers(self: *const ElfState, index: usize) void {
        return process_impl_guest_diagnostics.reportGuestMilestoneCallers(self, index);
    }

    /// Re-emit the first-frame and audio chains when their verdict moves.
    ///
    /// A full block at every checkpoint would repeat a dozen unchanged lines
    /// every fifty million steps and bury the checkpoint that mattered; a
    /// block only at exit is lost to every killed run. Emitting on change is
    /// the only version that is both readable and durable, and the "wall has
    /// moved" line is itself the progress signal a reader wants.
    pub fn reportRunChainsIfChanged(self: *ElfState, steps: u64) void {
        return process_impl_guest_diagnostics.reportRunChainsIfChanged(self, steps);
    }

    /// Everything this run told the guest it did not have, in one block.
    ///
    /// Split by whether Rosetta *chose* the refusal or simply has no answer,
    /// because those are different work items: the first needs nothing, the
    /// second names a package somebody has to write.
    pub fn reportWindowsDynamicRefusals(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportWindowsDynamicRefusals(self);
    }

    /// Say once whether the guest was given a CJK font, and what it costs.
    ///
    /// This is a Rosette policy decision that lands squarely on the guest's
    /// time-to-first-frame, so it belongs in the log next to the graphics
    /// evidence rather than in a source comment nobody reads during a run.
    pub fn noteGuestCjkFontDecision(self: *ElfState, granted: bool, detail: []const u8) void {
        return process_impl_guest_diagnostics.noteGuestCjkFontDecision(self, granted, detail);
    }

    /// Install the guest symbol resolver. Called once, by the image loader.
    pub fn installGuestSymbolResolver(
        self: *ElfState,
        resolver: GuestSymbolResolver,
        symbol_count: u32,
        coverage_percent: u32,
    ) void {
        return process_impl_guest_diagnostics.installGuestSymbolResolver(self, resolver, symbol_count, coverage_percent);
    }

    /// Arm `ROSETTE_PE64_CALL_PROBE` against this image's symbols.
    fn armCallProbes(self: *ElfState) void {
        return process_impl_guest_diagnostics.armCallProbes(self);
    }

    /// A `call` is about to transfer to `target`. When it is a probed
    /// function, log the arguments and arm the thread's return capture.
    fn noteCallProbeEntry(self: *ElfState, target: u64, return_rip: u64) void {
        return process_impl_guest_diagnostics.noteCallProbeEntry(self, target, return_rip);
    }

    /// Resolve the milestone table against this image and build the filter.
    ///
    /// Called once, from `installGuestSymbolResolver`, because a milestone
    /// can only be armed after there is something to resolve names with. A
    /// resolver with no `address_of` arms nothing and leaves every row
    /// unresolved, which the report states rather than hides.
    fn armGuestMilestones(self: *ElfState) void {
        return process_impl_guest_diagnostics.armGuestMilestones(self);
    }

    /// Record that the guest called the entry point of a milestone.
    ///
    /// Placed on the call paths rather than on every step: a C++ member
    /// function is reached by `call`, direct or indirect, and paying a bit
    /// test per instruction to also catch a tail jump would cost more than
    /// the answer is worth.
    /// Whether `target` is an armed milestone - exactly, not by filter bit.
    /// The filter alone answered yes for about one address in twelve (22
    /// milestones over 256 bits), and every call site it answered yes for
    /// stayed on the interpreter for good: most of 15,162 "hooked" direct
    /// calls and 210 million fallbacks on 2026-09-21 were such collisions.
    fn guestMilestoneIndexOf(self: *const ElfState, target: u64) ?usize {
        return process_impl_guest_diagnostics.guestMilestoneIndexOf(self, target);
    }

    fn isGuestMilestoneAddress(self: *const ElfState, target: u64) bool {
        return process_impl_guest_diagnostics.isGuestMilestoneAddress(self, target);
    }

    pub fn noteGuestMilestoneEntry(self: *ElfState, target: u64) void {
        return process_impl_guest_diagnostics.noteGuestMilestoneEntry(self, target);
    }

    /// Arm a separate call/return witness for the outer setup function. A
    /// nested subsystem call may use the generic one-slot return capture, so
    /// setup completion must not depend on that replaceable slot.
    fn noteXeniaEmulatorSetupCall(self: *ElfState, target: u64, return_rip: u64) void {
        return process_impl_guest_diagnostics.noteXeniaEmulatorSetupCall(self, target, return_rip);
    }

    /// Complete the setup witness only when the recorded emulator thread
    /// returns through the exact callsite observed at entry.
    fn noteXeniaEmulatorSetupReturn(self: *ElfState, return_rip: u64) void {
        return process_impl_guest_diagnostics.noteXeniaEmulatorSetupReturn(self, return_rip);
    }

    /// Xenia's `CommandProcessor::UpdateWritePointer` publishes the ring
    /// pointer and then calls `Win32Event::SetBoostPriority` through its
    /// vtable.  The PE image's indirect host/dynamic-import edge is not
    /// observable in every execution route, so keep a narrowly scoped repair
    /// at the proven milestone: follow only the command-processor event
    /// fields established by Xenia, verify the handle belongs to Rosetta's
    /// wait table, and signal that exact object.  The milestone hook runs
    /// before the function body, so it also publishes the exact write-pointer
    /// argument before waking the worker; otherwise the worker observes the
    /// old empty ring and sleeps again.  This is intentionally not a general
    /// GPU wake or a handle guess.
    pub fn repairXeniaGpuWritePointerWake(self: *ElfState) void {
        return process_impl_guest_diagnostics.repairXeniaGpuWritePointerWake(self);
    }

    pub fn recordGuestMilestone(self: *ElfState, index: usize, target: u64) void {
        return process_impl_guest_diagnostics.recordGuestMilestone(self, index, target);
    }

    /// Read the arguments of the milestones whose arguments are the evidence.
    ///
    /// Called at the `call`, before the return address is pushed, so the
    /// Windows x64 argument registers still hold what the caller passed:
    /// `rcx` is `this` for a member function, then `rdx`, `r8`, `r9`.
    pub fn noteGuestMilestoneArguments(self: *ElfState, index: usize) void {
        return process_impl_guest_diagnostics.noteGuestMilestoneArguments(self, index);
    }

    /// Capture only the small UI-to-Vulkan handoff surface that can explain
    /// `PRESENT CHAIN: no_surface`. The counts are live in
    /// `reportWindowsUiPipeline`; these bounded argument rows say whether
    /// Xenia passed a null presenter or surface at the boundary.
    fn noteXeniaPresenterAttachArguments(self: *ElfState, index: usize) void {
        return process_impl_guest_diagnostics.noteXeniaPresenterAttachArguments(self, index);
    }

    /// Snapshot the first ImDrawList's public buffers at RenderDrawLists.
    /// ImDrawData only exposes the aggregate counts; following the documented
    /// ImVector pointers lets the report distinguish a command whose clip was
    /// born degenerate from one whose vertices were already outside the
    /// viewport. Counts are used only as labels; the reads remain bounded to
    /// one command and one vertex.
    fn noteUiDrawDataBuffers(self: *ElfState, draw_data: u64) void {
        return process_impl_guest_diagnostics.noteUiDrawDataBuffers(self, draw_data);
    }

    fn activeReturnCapture(self: *ElfState) *GuestReturnCapture {
        return process_impl_guest_diagnostics.activeReturnCapture(self);
    }

    fn armGuestReturnCapture(self: *ElfState, kind: GuestReturnCaptureKind, tag: u32) void {
        return process_impl_guest_diagnostics.armGuestReturnCapture(self, kind, tag);
    }

    /// The scratch record's transfer guards, from the run's traces and the
    /// executing thread's own return capture.
    pub fn refreshBlockJitGuards(self: *ElfState, record: *block_jit.Scratch) void {
        return process_impl_guest_diagnostics.refreshBlockJitGuards(self, record);
    }

    /// Called from the `ret` arm, after the pop, while any capture is armed.
    fn noteCallProbeReturn(self: *ElfState, capture: GuestReturnCapture) void {
        return process_impl_guest_diagnostics.noteCallProbeReturn(self, capture);
    }

    pub fn completeGuestReturnCapture(self: *ElfState) void {
        return process_impl_guest_diagnostics.completeGuestReturnCapture(self);
    }

    /// Count one register access by Xenos index, returning its ledger slot.
    fn noteGpuRegisterAccess(self: *ElfState, address: u32, is_write: bool, value: u32) ?usize {
        return process_impl_guest_diagnostics.noteGpuRegisterAccess(self, address, is_write, value);
    }

    /// The Rosette address of Xenia's guest address zero, found from the
    /// views Xenia mapped: the 1 GiB view of mapping offset 0 whose mapping
    /// also has the physical view 4 GiB above it at offset 0x100000000.
    pub fn xeniaVirtualMembase(self: *const ElfState) ?u64 {
        return process_impl_guest_diagnostics.xeniaVirtualMembase(self);
    }

    /// Hand Xenia's console front buffer to the host presenter once the guest
    /// has both named it and crossed VdSwap.
    ///
    /// The two observations are intentionally joined here instead of in the
    /// Vulkan forwarder. The PE route knows how Xenia's physical view is
    /// projected into Rosette memory; the presenter must only receive a
    /// readable host address plus the fetch description. A VdSwap can arrive
    /// before its indirect buffer is decoded, so callers invoke this on the
    /// kernel edge, on ring decode, and at checkpoints. Failed attempts are
    /// retried with a bounded cadence rather than turning a temporary ordering
    /// difference into a permanent no-frame verdict.
    fn offerGuestFrontBufferToNativePresenter(self: *ElfState) bool {
        return process_impl_guest_diagnostics.offerGuestFrontBufferToNativePresenter(self);
    }

    /// Reads ring dwords through Xenia's physical view, and checks them
    /// against the title's virtual aliases of the same pages.
    const GpuRingSource = struct {
        state: *const ElfState,
        membase: u64,
        base: u32,

        fn physicalAddress(self: GpuRingSource, ring_index: u64) u64 {
            return (@as(u64, self.base) & 0x1FFF_FFFF) + ring_index * 4;
        }

        pub fn readDword(self: GpuRingSource, ring_index: u64) ?u32 {
            // This is a scalar guest load, not a borrowed snapshot. Resolve
            // backing directly so the active executor can forward its own
            // queued stores instead of draining the queue once per ring
            // dword; the scalar helper supplies the required TSO ordering.
            const bytes = self.state.guestMemorySourceConst(self.membase + 0x1_0000_0000 + self.physicalAddress(ring_index), 4) orelse return null;
            return @byteSwap(self.state.loadGuestScalar(u32, bytes));
        }

        /// How many aliases were readable, and how many disagreed.
        pub fn aliasCheck(self: GpuRingSource, ring_index: u64, physical_value: u32) struct { checked: u16, mismatched: u16 } {
            var checked: u16 = 0;
            var mismatched: u16 = 0;
            // Xenia maps its 4 KiB and 64 KiB physical heaps at 0xA0000000
            // and 0xC0000000 onto the same mapping offsets as the physical
            // view; a title writes its ring through one of them.
            for ([_]u64{ 0xA000_0000, 0xC000_0000 }) |alias| {
                const bytes = self.state.guestMemorySourceConst(self.membase + alias + self.physicalAddress(ring_index), 4) orelse continue;
                checked += 1;
                if (@byteSwap(self.state.loadGuestScalar(u32, bytes)) != physical_value) mismatched += 1;
            }
            return .{ .checked = checked, .mismatched = mismatched };
        }
    };

    /// Decode the dwords between two write-pointer values the way Xenia's
    /// `ExecutePacket` walks them: a header of 0, 0x0BADF00D or 0xCDCDCDCD is
    /// skipped, a type 0 or type 3 header carries `count + 1` payload dwords,
    /// a type 1 header two.
    pub fn decodeGpuRingWindow(source: anytype, window: *GpuRingWindow, from: u64, span: u64, ring_dwords: u64) void {
        return process_impl_guest_diagnostics.decodeGpuRingWindow(source, window, from, span, ring_dwords);
    }

    fn noteGpuRingWritePointer(self: *ElfState, write_index: u32) void {
        return process_impl_guest_diagnostics.noteGpuRingWritePointer(self, write_index);
    }

    /// Decode one indirect buffer the ring pointed at.
    ///
    /// A Direct3D title's primary ring is mostly ME_INIT and INDIRECT_BUFFER;
    /// the state, the draws and the swap live in the buffers those packets
    /// name. A decode that stops at the ring can say the title submitted work
    /// and never what the work was.
    fn decodeGpuIndirectBuffer(self: *ElfState, membase: u64, address: u32, dwords: u32) void {
        return process_impl_guest_diagnostics.decodeGpuIndirectBuffer(self, membase, address, dwords);
    }

    /// Record the path `VirtualFileSystem::ResolvePath` was given.
    ///
    /// `ResolvePath(this, std::string_view path)`: a 16-byte aggregate, which
    /// the Windows x64 convention passes by reference, so `rdx` points at
    /// libstdc++'s `{ size_t length; const char* data; }`.
    pub fn noteGuestVfsResolveEntry(self: *ElfState) void {
        return process_impl_guest_diagnostics.noteGuestVfsResolveEntry(self);
    }

    /// Whether `path` is a module name rather than a path into a guest device.
    fn guestVfsPathIsBareModuleName(path: []const u8) bool {
        return process_impl_guest_diagnostics.guestVfsPathIsBareModuleName(path);
    }

    fn guestVfsPathBasename(path: []const u8) []const u8 {
        return process_impl_guest_diagnostics.guestVfsPathBasename(path);
    }

    fn guestVfsModuleStem(path: []const u8) []const u8 {
        return process_impl_guest_diagnostics.guestVfsModuleStem(path);
    }

    fn guestVfsModuleNamesEqual(lhs: []const u8, rhs: []const u8) bool {
        return process_impl_guest_diagnostics.guestVfsModuleNamesEqual(lhs, rhs);
    }

    /// Return the explicit, found device path that proves a bare module-name
    /// miss was only the first half of Xenia's loaded-module lookup. Only DLL
    /// paths qualify: a bare name matching `\\Device\\Harddisk0`, for
    /// example, would be a false reconciliation rather than module evidence.
    pub fn guestVfsMatchedDevicePath(self: *const ElfState, module_name: []const u8) []const u8 {
        return process_impl_guest_diagnostics.guestVfsMatchedDevicePath(self, module_name);
    }

    pub fn classifyGuestVfsResolves(self: *const ElfState) GuestVfsResolveSummary {
        return process_impl_guest_diagnostics.classifyGuestVfsResolves(self);
    }

    /// The VFS ledger's record of `path`, as a suffix for a log line, or an
    /// empty slice when Xenia was never seen resolving it.
    pub fn describeVfsResolveFor(self: *const ElfState, path: []const u8, buffer: []u8) []const u8 {
        return process_impl_guest_diagnostics.describeVfsResolveFor(self, path, buffer);
    }

    /// A report's name for a thread slot recorded as slot plus one.
    fn guestThreadLabel(self: *const ElfState, slot_plus_one: u8) []const u8 {
        return process_impl_guest_diagnostics.guestThreadLabel(self, slot_plus_one);
    }

    /// A faulting access that landed in Xenia's XMA register aperture.
    fn noteApuRegisterFault(self: *ElfState, fault: GuestAccessViolation) void {
        return process_impl_guest_diagnostics.noteApuRegisterFault(self, fault);
    }

    fn reportXmaRegisters(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportXmaRegisters(self);
    }

    /// Sample every thread's step counter at a swap so the cost of the frame
    /// just presented can be split by who spent it.
    pub fn noteFrameCostSwap(self: *ElfState, swap_step: u64) void {
        return process_impl_guest_diagnostics.noteFrameCostSwap(self, swap_step);
    }

    /// The quality of service a guest thread's host thread runs at.
    ///
    /// macOS places threads on the performance or efficiency cores by their
    /// QoS class, and a pthread created without one runs at the default,
    /// which the scheduler may put on an efficiency core. On 2026-09-30
    /// Xenia's TimerQueue retired 682 million spin steps and two more title
    /// threads spun in `swtch_pri` beside the three threads the frame rate
    /// is made of. The frame's threads ask for user-interactive, the
    /// pollers for utility, and everything else keeps the default.
    /// `ROSETTE_PE64_THREAD_QOS=0` leaves every thread at the default.
    pub const HostQos = enum(c_uint) {
        user_interactive = 0x21,
        default = 0x15,
        utility = 0x11,

        pub fn label(self: HostQos) []const u8 {
            return switch (self) {
                .user_interactive => "user-interactive",
                .default => "default",
                .utility => "utility",
            };
        }
    };

    pub fn hostQosForGuestThread(name: []const u8) HostQos {
        return process_impl_guest_diagnostics.hostQosForGuestThread(name);
    }

    /// Set the calling host thread's QoS from its guest thread's name. Called
    /// by the worker itself: macOS only lets a thread change its own class.
    fn applyParallelWorkerQos(self: *ElfState, thread: *const WindowsGuestThread) void {
        return process_impl_guest_diagnostics.applyParallelWorkerQos(self, thread);
    }

    fn frameCostRole(name: []const u8) []const u8 {
        return process_impl_guest_diagnostics.frameCostRole(name);
    }

    /// The front buffer the title presents, from the fetch constant VdSwap
    /// put in the ring, and whether the gamma ramp that path depends on could
    /// have been programmed.
    fn reportFrontBuffer(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportFrontBuffer(self);
    }

    /// Instructions per presented frame and who spent them, with the frame
    /// rate that cost implies at this run's interpreter rate.
    fn reportFrameCost(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportFrameCost(self);
    }

    /// Whether the PCM the title submits is silence.
    ///
    /// `AudioSystem::SubmitFrame(index, samples)` receives the title's frame
    /// already translated to a host pointer: six channels of 256 big-endian
    /// float samples. Every call is checked for the first few thousand, and
    /// one in sixteen after, which is enough to see a title start producing
    /// sound and cheap enough to leave on.
    fn noteAudioTitleFrame(self: *ElfState, samples: u64) void {
        return process_impl_guest_diagnostics.noteAudioTitleFrame(self, samples);
    }

    /// A Xenos register index's name, for the registers a title touches
    /// before it draws. Anything else is printed by index.
    /// The value Xenia's `GraphicsSystem::ReadRegister` returns for a
    /// register it answers without consulting the register file, or null.
    pub fn xeniaConstantRegisterRead(index: u16) ?u32 {
        return process_impl_guest_diagnostics.xeniaConstantRegisterRead(index);
    }

    /// A type 3 opcode's name, from the values in `lib/gpu/pm4.zig`.
    pub fn pm4OpcodeLabel(opcode: u8) []const u8 {
        return process_impl_guest_diagnostics.pm4OpcodeLabel(opcode);
    }

    /// Entries into Xenia's type 3 opcode handlers, and into the
    /// indirect-buffer walk only a type 3 packet reaches.
    ///
    /// `ExecutePacketType3` is inlined into `ExecutePacket` in this build, so
    /// its own tracepoint reads zero while the handlers it dispatches to run.
    /// On 2026-09-13 ME_INIT=1 and ExecuteIndirectBuffer=5 with the
    /// dispatcher at 0, and the chain called the ring its wall.
    pub fn gpuType3HandlerEntries(self: *const ElfState) u64 {
        return process_impl_guest_diagnostics.gpuType3HandlerEntries(self);
    }

    pub fn xenosRegisterName(index: u16) []const u8 {
        return process_impl_guest_diagnostics.xenosRegisterName(index);
    }

    /// Every Xenos register the title read or wrote, with what it read back.
    pub fn reportGpuRegisterTraffic(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGpuRegisterTraffic(self);
    }

    fn reportGpuEventWrites(window: *const GpuRingWindow, source: []const u8) void {
        return process_impl_guest_diagnostics.reportGpuEventWrites(window, source);
    }

    /// What each write-pointer update moved the ring over.
    pub fn reportGpuRing(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGpuRing(self);
    }

    /// Every path Xenia's VFS was asked to resolve, with who asked.
    pub fn reportGuestVfsResolves(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportGuestVfsResolves(self);
    }

    /// Hold a WinMM writer to its stream's real-time rate.
    ///
    /// Returns the milliseconds the writer must wait before this buffer is
    /// accepted, or zero to accept it now. `waveOutWrite` completes a buffer
    /// the moment it is accepted, because SDL's worker waits for WOM_DONE
    /// before it writes again; with nothing else holding it back, SDL's audio
    /// thread wrote 3.4 million buffers in the 2026-09-13 run, 6.7 GB of
    /// them dropped by the device, and held a tenth of the interpreter the
    /// title needed. A real device completes a buffer when it has played it.
    /// This lets the accepted audio run at most a device queue's depth ahead
    /// of the host clock, and parks the writer - retrying the same call - for
    /// the rest. A writer slower than real time never waits.
    pub fn paceWindowsWaveOutWrite(self: *ElfState, device: *WindowsWaveOutDevice, length: u32) u64 {
        return process_impl_guest_diagnostics.paceWindowsWaveOutWrite(self, device, length);
    }

    pub fn windowsRegistryOpen(self: *ElfState, parent: u64, subkey: []const u8, create: bool) windows_registry_model.OpenResult {
        return process_impl_guest_diagnostics.windowsRegistryOpen(self, parent, subkey, create);
    }

    pub fn windowsRegistryClose(self: *ElfState, handle: u64) u32 {
        return process_impl_guest_diagnostics.windowsRegistryClose(self, handle);
    }

    pub fn windowsRegistryIsHandle(self: *const ElfState, handle: u64) bool {
        return process_impl_guest_diagnostics.windowsRegistryIsHandle(self, handle);
    }

    pub fn windowsRegistrySet(self: *ElfState, handle: u64, name: []const u8, value_type: u32, data: []const u8) u32 {
        return process_impl_guest_diagnostics.windowsRegistrySet(self, handle, name, value_type, data);
    }

    pub fn windowsRegistryQuery(self: *ElfState, handle: u64, name: []const u8) windows_registry_model.QueryResult {
        return process_impl_guest_diagnostics.windowsRegistryQuery(self, handle, name);
    }

    pub fn windowsRegistryGet(self: *ElfState, handle: u64, subkey: []const u8, name: []const u8) windows_registry_model.QueryResult {
        return process_impl_guest_diagnostics.windowsRegistryGet(self, handle, subkey, name);
    }

    pub fn windowsRegistryDeleteValue(self: *ElfState, handle: u64, name: []const u8) u32 {
        return process_impl_guest_diagnostics.windowsRegistryDeleteValue(self, handle, name);
    }

    pub fn windowsRegistryFit(value_size: usize, has_buffer: bool, has_size: bool, capacity: u32) windows_registry_model.Fit {
        return process_impl_guest_diagnostics.windowsRegistryFit(value_size, has_buffer, has_size, capacity);
    }

    pub fn windowsRegistryTypeAllowed(value_type: u32, flags: u32) bool {
        return process_impl_guest_diagnostics.windowsRegistryTypeAllowed(value_type, flags);
    }

    pub fn reportWindowsRegistry(self: *const ElfState) void {
        return process_impl_guest_diagnostics.reportWindowsRegistry(self);
    }

    /// Offer one image symbol to the kernel-call census.
    ///
    /// Called once per symbol at load time, from whichever loader holds the
    /// symbol table. Most symbols are not shims and are rejected in a few
    /// instructions; the ones that are keep a borrowed slice of the image's
    /// string table, which outlives this state in every caller.
    pub fn armGuestKernelShim(self: *ElfState, mangled: []const u8, address: u64) void {
        return process_impl_kernel_services.armGuestKernelShim(self, mangled, address);
    }

    /// Report what the arming pass found, once, so a run whose image has no
    /// shims says so rather than printing an empty census later.
    pub fn reportGuestKernelShimArming(self: *const ElfState) void {
        return process_impl_kernel_services.reportGuestKernelShimArming(self);
    }

    /// Record that the guest entered a kernel export shim.
    ///
    /// On the interpreter's call path, next to `noteGuestMilestoneEntry`. The
    /// census rejects an address outside the armed range in two comparisons,
    /// which is what almost every call is.
    pub fn noteGuestKernelCall(self: *ElfState, target: u64) void {
        return process_impl_kernel_services.noteGuestKernelCall(self, target);
    }

    /// The same, for a tail jump. Kept apart in the count because which
    /// instruction a translator reaches its handler with is a property of the
    /// translator; a census that could not tell them apart would read zero
    /// for a title that was calling constantly.
    pub fn noteGuestKernelTailJump(self: *ElfState, target: u64) void {
        return process_impl_kernel_services.noteGuestKernelTailJump(self, target);
    }

    fn noteGuestKernelEntry(self: *ElfState, target: u64, via_jump: bool) void {
        return process_impl_kernel_services.noteGuestKernelEntry(self, target, via_jump);
    }

    /// A census export counted `kernel_call_census.saturation_calls` times:
    /// drop its hook from the translator's filter, unless something other
    /// than the count acts on it, in which case it stays hooked for good.
    fn decideGuestKernelSaturation(self: *ElfState, slot_index: u32) void {
        return process_impl_kernel_services.decideGuestKernelSaturation(self, slot_index);
    }

    /// Whether anything but the census acts on calls to this export: the
    /// Xbox critical-section bridge, the Xam input shim, the presenter's
    /// VdSwap boundary, the file-request capture. Those exports keep their
    /// hook however often they are called.
    fn guestKernelExportPinned(self: *const ElfState, slot: *const kernel_call_census.Slot) bool {
        return process_impl_kernel_services.guestKernelExportPinned(self, slot);
    }

    /// The kernel exports whose object name an empty `ResolvePath` can come from.
    fn isGuestFileRequestExport(export_name: []const u8) bool {
        return process_impl_kernel_services.isGuestFileRequestExport(export_name);
    }

    fn activeGuestFileRequest(self: *ElfState) *GuestFileRequest {
        return process_impl_kernel_services.activeGuestFileRequest(self);
    }

    /// Guest memory the way Xenia's `TranslateVirtual` reaches it: membase
    /// plus the address, and one host page further for the 0xE0000000 heap.
    fn xeniaGuestBytes(self: *const ElfState, membase: u64, guest_address: u32, count: u64) ?[]const u8 {
        return process_impl_kernel_services.xeniaGuestBytes(self, membase, guest_address, count);
    }

    fn xeniaGuestVirtualAddress(membase: u64, guest_address: u32) u64 {
        return process_impl_kernel_services.xeniaGuestVirtualAddress(membase, guest_address);
    }

    /// Capture the arguments Xenia's Xbox export trampoline will use to
    /// resolve a guest dispatcher event. This is read-only and bounded to
    /// four event exports; it does not replace or alter Xenia's object path.
    fn captureXeniaEventCall(self: *ElfState, slot: *const kernel_call_census.Slot, accounting_step: u64) ?xenia_event_audit.CallSnapshot {
        return process_impl_kernel_services.captureXeniaEventCall(self, slot, accounting_step);
    }

    pub fn readHostU64(self: *const ElfState, address: u64) ?u64 {
        return process_impl_kernel_services.readHostU64(self, address);
    }

    /// Report the first moments a worker's stack pointer falls into the null
    /// page - where no thread's stack ever is. On 2026-09-21 Halo 3's RENDER
    /// thread reached a function epilogue with rsp=0, "returned" through a
    /// null return address, and was retired as finished while it still held
    /// the critical section MAIN_THREAD then waited on for ten minutes. The
    /// corruption itself left no trace; this names the code that did it.
    fn noteStackPointerCollapse(self: *ElfState, via: []const u8, rsp_before: u64, rip_before: u64, detail: []const u8) void {
        return process_impl_kernel_services.noteStackPointerCollapse(self, via, rsp_before, rip_before, detail);
    }

    /// The translated-code form: the block the chain left from and the one
    /// that hopped to it, because the collapse is in one of them.
    fn noteStackPointerCollapseInBlocks(self: *ElfState, rsp_before: u64, rip_before: u64, last: *block_jit.Block, completed: u32) void {
        return process_impl_kernel_services.noteStackPointerCollapseInBlocks(self, rsp_before, rip_before, last, completed);
    }

    /// Name the owner of the critical section a blocked thread entered.
    ///
    /// Xenia's `X_RTL_CRITICAL_SECTION` is a 16-byte dispatcher header, then
    /// `lock_count` in host byte order (Xenia updates it with host atomics),
    /// then a big-endian `recursion_count` and `owning_thread` (a guest
    /// KTHREAD). An owner of zero with `lock_count` at or above zero means
    /// the section was released while a waiter was counted, and the
    /// release's `KeSetEvent` never reached the waiter: a lost wake, not a
    /// holder.
    fn logCriticalSectionWait(self: *const ElfState, thread: *const WindowsGuestThread) void {
        return process_impl_kernel_services.logCriticalSectionWait(self, thread);
    }

    /// What an Xbox section a bridged waiter is parked on says, for the
    /// blocked-thread report: its owner and whether that owner is a thread
    /// Rosette can name.
    fn describeXboxCriticalSectionWait(self: *const ElfState, section: u64, buffer: []u8) []const u8 {
        return process_impl_kernel_services.describeXboxCriticalSectionWait(self, section, buffer);
    }

    fn readWindowsInputState(self: *ElfState) ?WindowsInputState {
        return process_impl_kernel_services.readWindowsInputState(self);
    }

    /// Complete the little-endian Windows XInput state when a native virtual
    /// controller is available. Returning false keeps the old explicit
    /// ERROR_DEVICE_NOT_CONNECTED path for tests and non-macOS runners with
    /// no input hook.
    pub fn writeWindowsXInputState(self: *ElfState, output: u64) bool {
        return process_impl_kernel_services.writeWindowsXInputState(self, output);
    }

    /// Xenia's Xam input exports receive a PPC context, not the Win32 XInput
    /// ABI. Complete the small input contract at the export trampoline when
    /// the macOS virtual controller is installed. This keeps keyboard input
    /// usable even when Xenia's optional Win32 keyboard HID driver is absent.
    fn tryXeniaKeyboardInputShim(self: *ElfState, target: u64, next_rip: u64) bool {
        return process_impl_kernel_services.tryXeniaKeyboardInputShim(self, target, next_rip);
    }

    /// Read `NtCreateFile`/`NtOpenFile`'s object name from the PPC context.
    ///
    /// Both take `(handle_out, desired_access, object_attributes, ...)` in
    /// r3, r4 and r5. `X_OBJECT_ATTRIBUTES` is `{root_directory, name_ptr,
    /// attributes}` and `X_ANSI_STRING` is `{length, maximum_length,
    /// pointer}`, all big-endian. The trampoline's only argument is the
    /// context, in rcx at the moment the guest reaches it.
    pub fn captureGuestFileRequest(self: *ElfState, kernel_slot: u32) void {
        return process_impl_kernel_services.captureGuestFileRequest(self, kernel_slot);
    }

    fn captureGuestFileRequestFields(self: *const ElfState, request: *GuestFileRequest, context: u64) error{Unreadable}!void {
        return process_impl_kernel_services.captureGuestFileRequestFields(self, request, context);
    }

    pub fn classifyGuestFileRequestName(request: *const GuestFileRequest) GuestFileNameShape {
        return process_impl_kernel_services.classifyGuestFileRequestName(request);
    }

    /// `ResolvePath` failed on an empty path: stop, citing the request behind it.
    pub fn faultGuestVfsEmptyName(self: *ElfState, resolve: *const GuestVfsResolve) void {
        return process_impl_kernel_services.faultGuestVfsEmptyName(self, resolve);
    }

    fn reportGuestVfsEmptyName(self: *ElfState, resolve: *const GuestVfsResolve, occurrence: u64) void {
        return process_impl_kernel_services.reportGuestVfsEmptyName(self, resolve, occurrence);
    }

    /// How many times the guest entered a milestone, by its table row.
    pub fn guestMilestoneHits(self: *const ElfState, index: usize) u64 {
        return process_impl_kernel_services.guestMilestoneHits(self, index);
    }

    /// The same, by mangled name, for a caller that knows what it wants
    /// rather than where it sits.
    pub fn guestMilestoneHitsNamed(self: *const ElfState, mangled: []const u8) u64 {
        return process_impl_kernel_services.guestMilestoneHitsNamed(self, mangled);
    }

    /// The armed milestone entry addresses, in table order, for the image
    /// reader to scan the executable sections against. Zero where the image
    /// did not name the symbol; the census skips those.
    pub fn guestMilestoneAddresses(self: *const ElfState) []const u64 {
        return process_impl_kernel_services.guestMilestoneAddresses(self);
    }

    /// Record the call-site census the image reader produced.
    ///
    /// Supplied by the PE route rather than computed here: the count needs
    /// the image's executable sections and their file offsets, which are the
    /// loader's business and not the interpreter's.
    pub fn noteGuestMilestoneCallSites(self: *ElfState, counts: []const u32) void {
        return process_impl_kernel_services.noteGuestMilestoneCallSites(self, counts);
    }

    /// Record how many stored pointers to each milestone the image contains.
    ///
    /// Supplied alongside the call-site census and read with it: the two
    /// together decide whether an armed address is reachable at all.
    pub fn noteGuestMilestoneDataReferences(self: *ElfState, counts: []const u32) void {
        return process_impl_kernel_services.noteGuestMilestoneDataReferences(self, counts);
    }

    /// How a milestone's entry can be reached in this image.
    pub const MilestoneReach = enum {
        /// The image does not name the symbol.
        unresolved,
        /// At least one direct `call`/`jmp` branches to it.
        direct,
        /// No direct branch, but its address is stored somewhere: a vtable
        /// slot, a dispatch table, a callback registration. A virtual
        /// function looks like this, and a zero entry count on one is real
        /// evidence about the guest.
        indirect,
        /// Neither branched to nor stored, and never entered. The compiler
        /// inlined the body into its callers and left the out-of-line copy
        /// behind; the address cannot be reached and its zero says nothing.
        unreachable_inlined,
        /// The census did not run on this route, so nothing can be said.
        uncounted,

        pub fn label(self: MilestoneReach) []const u8 {
            return switch (self) {
                .unresolved => "unresolved",
                .direct => "direct",
                .indirect => "indirect",
                .unreachable_inlined => "inlined-away",
                .uncounted => "uncounted",
            };
        }
    };

    /// Why a milestone-backed stage cannot be observed, in the words that
    /// send a reader to the right place. The two causes are unrelated: an
    /// image that does not carry the symbol, and an image whose optimizer
    /// left the symbol unreachable.
    pub fn guestMilestoneUnobservableReason(self: *const ElfState, mangled: []const u8) []const u8 {
        return process_impl_kernel_services.guestMilestoneUnobservableReason(self, mangled);
    }

    pub fn guestMilestoneReach(self: *const ElfState, mangled: []const u8) MilestoneReach {
        return process_impl_kernel_services.guestMilestoneReach(self, mangled);
    }

    /// Whether an armed milestone cannot be reached at all in this image, so
    /// a zero entry count measures the build and not the run.
    ///
    /// The strict reading of `.unreachable_inlined`: no direct branch, no
    /// stored pointer, never entered. Anything weaker was the 2026-09-12
    /// mistake - three virtual functions have no call site either, and
    /// calling those inlined threw away three real findings.
    pub fn guestMilestoneInlinedAway(self: *const ElfState, mangled: []const u8) bool {
        return process_impl_kernel_services.guestMilestoneInlinedAway(self, mangled);
    }

    /// The count a chain stage should read for a milestone.
    ///
    /// `@max` of the row's own entries and its inline proxy's, never the sum:
    /// when the body was *not* inlined the proxy is called by it, so adding
    /// them would double every vblank. When it was, the row reads zero and
    /// the proxy carries the whole count.
    pub fn guestMilestoneStageHits(self: *const ElfState, mangled: []const u8) u64 {
        return process_impl_kernel_services.guestMilestoneStageHits(self, mangled);
    }

    /// Whether this run can observe a stage at all.
    ///
    /// Armed is not enough. A symbol the optimizer inlined away can never be
    /// entered, so reporting its zero as an unmet stage - and letting it
    /// become the wall the whole chain is read against - states a fact about
    /// the guest that no evidence supports. Such a row is observable only
    /// through its proxy, if it declared one.
    pub fn guestMilestoneStageObservable(self: *const ElfState, mangled: []const u8) bool {
        return process_impl_kernel_services.guestMilestoneStageObservable(self, mangled);
    }

    /// Whether the image contained the symbol at all. A milestone that could
    /// not be armed reads as zero hits, and zero hits from an unarmed row
    /// says nothing about the guest.
    pub fn guestMilestoneArmed(self: *const ElfState, mangled: []const u8) bool {
        return process_impl_kernel_services.guestMilestoneArmed(self, mangled);
    }

    /// The bare symbol name covering an address, written into `buffer`.
    ///
    /// Separate from `describeGuestAddress` because the frontier classifier
    /// matches on the name alone: appending `+0x1f0` first and stripping it
    /// again would be a round trip through text for no reason.
    pub fn guestSymbolAt(self: *const ElfState, address: u64, buffer: []u8) ?GuestSymbol {
        return process_impl_kernel_services.guestSymbolAt(self, address, buffer);
    }

    /// Xenia's native XMutant initializer leaves its backing object null. At
    /// the one observed ReleaseMutant call site, its caller tests AL and
    /// converts false into X_STATUS_MUTANT_NOT_OWNED. Skip only that exact
    /// null virtual call and return the false value; never turn general null
    /// calls into successful control flow.
    fn tryXeniaMissingNativeMutantRelease(self: *ElfState, d: DecodedInsn, next_rip: u64) bool {
        return process_impl_kernel_services.tryXeniaMissingNativeMutantRelease(self, d, next_rip);
    }

    /// Xenia's XMutant deleting destructor must not dispatch a second
    /// deleting destructor through Win32Handle<Mutant>'s intentional UD2
    /// after the backing object's base-destructor state is visible. The
    /// instruction immediately after the call clears mutant_, so skipping
    /// only this exact duplicate teardown completes the parent destructor.
    fn tryXeniaStaleMutantBackingDelete(self: *ElfState, d: DecodedInsn, next_rip: u64) bool {
        return process_impl_kernel_services.tryXeniaStaleMutantBackingDelete(self, d, next_rip);
    }

    /// `name+0xoffset` for an address, or an empty slice when the image does
    /// not name it. An empty return is a fact about the image, never a
    /// failure: a caller prints `symbol=<unnamed>` and moves on.
    pub fn describeGuestAddress(self: *const ElfState, address: u64, buffer: []u8) []const u8 {
        return process_impl_kernel_services.describeGuestAddress(self, address, buffer);
    }

    /// The same text, but never empty: unnamed addresses render as a marker a
    /// log reader can grep for.
    pub fn describeGuestAddressOrUnnamed(self: *const ElfState, address: u64, buffer: []u8) []const u8 {
        return process_impl_kernel_services.describeGuestAddressOrUnnamed(self, address, buffer);
    }

    /// What the guest is doing at an address, from its symbol.
    pub fn classifyGuestFrontier(self: *const ElfState, address: u64) xenia_guest_frontier_map.Classification {
        return process_impl_kernel_services.classifyGuestFrontier(self, address);
    }

    /// Whether the current guest frontier sits in work that finishes on its
    /// own given more steps.
    ///
    /// This is the suppression gate for every "nothing downstream happened"
    /// predictor in this file. A font atlas being rasterized, a shader being
    /// translated, or a XEX being decrypted all look identical to a stall
    /// from a downstream counter, and accusing the downstream subsystem for
    /// them sends a reader to the wrong place - which is exactly what the
    /// 2026-09-11 `present-chain-no-presents` verdict did.
    pub fn guestFrontierIsBoundedComputation(self: *const ElfState) bool {
        return process_impl_kernel_services.guestFrontierIsBoundedComputation(self);
    }

    /// Add the current frontier to the workload histogram. Called only at the
    /// graphics checkpoints, so the cost is per-checkpoint and not per-step.
    pub fn sampleGuestFrontier(self: *ElfState) void {
        return process_impl_kernel_services.sampleGuestFrontier(self);
    }

    pub fn frontierSamplesFor(self: *const ElfState, workload: xenia_guest_frontier_map.Workload) u64 {
        return process_impl_kernel_services.frontierSamplesFor(self, workload);
    }

    /// Samples spent anywhere in the ImGui font atlas build.
    pub fn fontAtlasFrontierSamples(self: *const ElfState) u64 {
        return process_impl_kernel_services.fontAtlasFrontierSamples(self);
    }

    /// One line describing where the guest is and what it is doing there.
    /// Written into `buffer`; always non-empty.
    pub fn describeGuestFrontier(self: *const ElfState, address: u64, buffer: []u8) []const u8 {
        return process_impl_kernel_services.describeGuestFrontier(self, address, buffer);
    }

    /// Ask the Vulkan forwarder to describe the presentation chain, if this
    /// state has one. A PE run reaches the forwarder through the graphics
    /// hooks; a state with no forwarder simply has nothing to say.
    fn notePresentChainFailurePoint(self: *ElfState, steps: u64) void {
        return process_impl_kernel_services.notePresentChainFailurePoint(self, steps);
    }

    fn reportPresentChainCheckpoint(self: *ElfState) void {
        return process_impl_kernel_services.reportPresentChainCheckpoint(self);
    }

    pub fn reportPresentChainFinal(self: *ElfState) void {
        return process_impl_kernel_services.reportPresentChainFinal(self);
    }

    fn windowsScreenValiditySnapshot(self: *const ElfState) screen_validity.Snapshot {
        return process_impl_kernel_services.windowsScreenValiditySnapshot(self);
    }

    /// Emit a Rosetta-owned, fail-closed screen verdict. A successful guest
    /// present or native diagnostic frame proves transport only. Without a
    /// bounded pixel readback and source provenance this report must never
    /// say that a detailed picture reached the user.
    pub fn reportWindowsScreenValidity(self: *ElfState) void {
        return process_impl_kernel_services.reportWindowsScreenValidity(self);
    }

    pub fn reportWindowsInputBridge(self: *const ElfState) void {
        return process_impl_kernel_services.reportWindowsInputBridge(self);
    }

    /// Record which import raised a file failure and with what error.
    pub fn noteWindowsFileFailure(self: *ElfState, error_code: u32) void {
        return process_impl_kernel_services.noteWindowsFileFailure(self, error_code);
    }

    /// The same, with the path or file it concerned and where it came from.
    pub fn noteWindowsFileFailureDetail(self: *ElfState, error_code: u32, subject: []const u8, caller: u64) void {
        return process_impl_kernel_services.noteWindowsFileFailureDetail(self, error_code, subject, caller);
    }

    /// Report the Windows file operations this run could not serve.
    ///
    /// Silent when nothing failed. Expected answers - a pipe with no server,
    /// the end of an enumeration, a probe for an optional file - are
    /// informational; a missing path on an open, and any I/O failure on an
    /// open handle, warn, each with the first path it concerned and the
    /// caller. A run whose only failures are expected prints no warning.
    pub fn reportWindowsFileFailures(self: *const ElfState) void {
        return process_impl_kernel_services.reportWindowsFileFailures(self);
    }

    /// Record that an import completed through the deterministic ABI
    /// fallback.  Called from the Win32 surface, which does not know how the
    /// executor wants to keep evidence.
    pub fn noteWindowsImportFallback(
        self: *ElfState,
        dll_name: []const u8,
        name: []const u8,
        fallback: x64_linux_runtime.ImportFallback,
    ) void {
        return process_impl_kernel_services.noteWindowsImportFallback(self, dll_name, name, fallback);
    }

    /// Classify one import answer and keep it if it spelled failure.
    ///
    /// Called once per import, from the single point every dispatch returns
    /// through. Cheap on the common path: a cached convention lookup and one
    /// comparison. The conventions where zero is an ordinary answer - a count
    /// of none, a void return - can never produce a refusal, so a report of
    /// these is not diluted by calls that did nothing wrong.
    pub fn noteWindowsImportAnswer(
        self: *ElfState,
        dll_name: []const u8,
        name: []const u8,
        value: u64,
        last_error_before: u32,
    ) void {
        return process_impl_kernel_services.noteWindowsImportAnswer(self, dll_name, name, value, last_error_before);
    }

    /// Remember, per thread, the last import it called.
    ///
    /// One bounded copy per import - about ninety thousand in a Xenia run -
    /// against a question no other instrument answers.
    pub fn noteWindowsThreadImport(self: *ElfState, name: []const u8) void {
        return process_impl_kernel_services.noteWindowsThreadImport(self, name);
    }

    fn recordWindowsImportRefusal(
        self: *ElfState,
        ledger: *x64_linux_runtime.ImportFallbackLedger,
        dll_name: []const u8,
        name: []const u8,
        convention: x64_linux_runtime.ImportReturnConvention,
        value: u64,
    ) void {
        return process_impl_kernel_services.recordWindowsImportRefusal(self, ledger, dll_name, name, convention, value);
    }

    /// Every import answer this run gave that the guest reads as a failure.
    ///
    /// The point of the block is that a guest failure message can be matched
    /// against it. Xenia says "Failed to create a DXGI factory"; the reader
    /// needs the export, the value, the caller and the step, and needs them
    /// for every such answer rather than for the one name somebody wired by
    /// hand. Hard refusals first - an HRESULT or NTSTATUS failure is a branch
    /// the guest takes, while a NULL handle is very often a probe whose
    /// absence the guest expects - then by how often it happened.
    pub fn reportWindowsImportRefusals(self: *const ElfState) void {
        return process_impl_kernel_services.reportWindowsImportRefusals(self);
    }

    /// For each library this run was refused by, what Rosette would have to
    /// Report the actual guest-owned CRT state, including the callback and
    /// termination tables. A count of zero is meaningful here: it says the
    /// run did not register or consume a callback, not that the CRT pointers
    /// were silently left null.
    pub fn reportWindowsCrtState(self: *const ElfState) void {
        return process_impl_kernel_services.reportWindowsCrtState(self);
    }

    /// Report only capability work that actually fell through the runtime
    /// contract, rather than every deliberate refusal value.
    ///
    /// A hand-written handler can return an ABI refusal because an optional
    /// host service is absent; that is evidence of a decision, not a missing
    /// library. The inventory remains useful for a true generic fallback, but
    /// it must never be selected from the value-classified refusal ledger.
    fn reportCapabilityGaps(self: *const ElfState) void {
        return process_impl_kernel_services.reportCapabilityGaps(self);
    }

    /// The BOOL and handle returns that were zero and said nothing about why.
    ///
    /// Deliberately its own block. Windows' rule is that a failing BOOL sets
    /// `GetLastError`, so a handler that returns FALSE and sets nothing is
    /// either answering an honest no or refusing silently - and the value
    /// alone cannot say which. Reported as an audit list rather than as
    /// findings, because most of it is honest and the few that are not are
    /// worth reading every line for. `VirtualProtect` returning FALSE on
    /// every call for the whole life of this project was one of them.
    pub fn reportWindowsUnexplainedZeros(self: *const ElfState) void {
        return process_impl_kernel_services.reportWindowsUnexplainedZeros(self);
    }

    /// Whether this name reached the generic contract fallback, meaning
    /// Rosette has no handler for it.
    fn windowsImportIsUnimplemented(self: *const ElfState, dll_name: []const u8, name: []const u8) bool {
        return process_impl_kernel_services.windowsImportIsUnimplemented(self, dll_name, name);
    }

    /// Report the imports this run completed through the ABI fallback.
    ///
    /// A healthy run says nothing here: the report is emitted only when a
    /// fallback has been taken that has not been described yet.  `full` asks
    /// for every entry (the end-of-run summary); otherwise only the entries
    /// added since the last report are printed, so a long run does not repeat
    /// what it already said.
    ///
    /// Detail is spent only where there is something to decide.  An import
    /// that was refused, or that answered something it had not earned, gets
    /// a line; the rest -- calls with no observable result -- collapse into
    /// one line naming them, because a screen of "safe to leave
    /// unimplemented" buries the few that are not.
    pub fn reportWindowsImportFallbacks(self: *ElfState, full: bool) void {
        return process_impl_kernel_services.reportWindowsImportFallbacks(self, full);
    }

    pub fn windowsImportCallsite(self: *ElfState, return_rip: u64, target: u64) ?WindowsImportCallsite {
        return process_impl_kernel_services.windowsImportCallsite(self, return_rip, target);
    }

    /// An import reached through IAT slot `slot`, answered on a narrow fast
    /// lane (`windows_runtime.tryWindowsFastFunction`): a call, whose return
    /// address is `call_return`, or a thunk's tail jump (`call_return` zero),
    /// whose return address is on the guest stack and is popped on success.
    /// False leaves every register as it was, for the interpreter's import
    /// path to run the instruction.
    pub fn tryImportSlotFastTransfer(self: *ElfState, slot: u64, call_return: u64) bool {
        return process_impl_kernel_services.tryImportSlotFastTransfer(self, slot, call_return);
    }

    /// Index every direct import stub by its IAT slot, so finding the stub for
    /// a `call [IAT]`/`jmp [IAT]` is one array read rather than a scan of
    /// every import. Called once the loader has bound every slot.
    pub fn indexWindowsIatStubs(self: *ElfState) void {
        return process_impl_kernel_services.indexWindowsIatStubs(self);
    }

    pub fn windowsImportStubForIat(self: *const ElfState, iat_address: u64) ?WindowsImportStub {
        return process_impl_kernel_services.windowsImportStubForIat(self, iat_address);
    }

    fn verifyWindowsImportIatAtDispatch(self: *ElfState, stub: WindowsImportStub) void {
        return process_impl_kernel_services.verifyWindowsImportIatAtDispatch(self, stub);
    }

    pub fn recordWindowsImportAbiReturn(
        self: *ElfState,
        stub: WindowsImportStub,
        saved: *const windows_guest_abi.Snapshot,
        entry_regs: *ElfRegs,
        entry_rsp: u64,
        return_rip: u64,
        stack_pop_bytes: u64,
        entry_slot: ?usize,
        callsite_rip: u64,
    ) void {
        return process_impl_kernel_services.recordWindowsImportAbiReturn(self, stub, saved, entry_regs, entry_rsp, return_rip, stack_pop_bytes, entry_slot, callsite_rip);
    }

    fn windowsVulkanImportStubInterior(self: *const ElfState, address: u64) ?WindowsImportStubInterior {
        return process_impl_kernel_services.windowsVulkanImportStubInterior(self, address);
    }

    fn recoverMisalignedVulkanImportStub(
        self: *ElfState,
        address: u64,
        return_rip: u64,
    ) ?WindowsImportStub {
        return process_impl_kernel_services.recoverMisalignedVulkanImportStub(self, address, return_rip);
    }

    /// Narrow time/CRT/identity and serialized SRW lanes may handle exact
    /// Windows import stubs before general runtime dispatch. Static imports require a matching IAT binding; dynamic
    /// imports require an exact registered GetProcAddress stub. Traced runs
    /// and diagnostic clock modes use the ordinary path.
    pub fn tryWindowsFastImportStub(self: *ElfState, stub_address: u64) bool {
        return process_impl_kernel_services.tryWindowsFastImportStub(self, stub_address);
    }

    fn handleWindowsImportStub(self: *ElfState) bool {
        return process_impl_kernel_services.handleWindowsImportStub(self);
    }

    pub fn localSymbolAddress(self: *const ElfState, name: []const u8) ?u64 {
        return process_impl_kernel_services.localSymbolAddress(self, name);
    }

    pub fn localSymbolNameAt(self: *const ElfState, address: u64) ?[]const u8 {
        return process_impl_kernel_services.localSymbolNameAt(self, address);
    }

    fn nearestLocalSymbol(self: *const ElfState, address: u64) ?exit_diagnostics.SymbolizedAddress {
        return process_impl_kernel_services.nearestLocalSymbol(self, address);
    }

    fn windowsHeapCallSite(self: *ElfState) WindowsHeapCallSite {
        return process_impl_kernel_services.windowsHeapCallSite(self);
    }

    fn windowsHeapStackSnapshot(self: *ElfState, rsp: u64) WindowsHeapStackSnapshot {
        return process_impl_kernel_services.windowsHeapStackSnapshot(self, rsp);
    }

    fn windowsHeapCodeSnapshot(self: *ElfState, address: u64) WindowsHeapCodeSnapshot {
        return process_impl_kernel_services.windowsHeapCodeSnapshot(self, address);
    }

    fn logWindowsHeapFailureDetail(
        self: *ElfState,
        event: []const u8,
        address: u64,
        requested_size: u64,
        alignment: u64,
        record_index: ?usize,
    ) void {
        return process_impl_kernel_services.logWindowsHeapFailureDetail(self, event, address, requested_size, alignment, record_index);
    }

    fn recordTrace(self: *ElfState, decoded: DecodedInsn) void {
        return process_impl_kernel_services.recordTrace(self, decoded);
    }

    /// Keep the Win32 callback investigation local to a real guest callback
    /// frame. The pending-function WndProc is the hand-off from Xenia's UI
    /// loop to its graphics setup queue; tracing every PE call would drown the
    /// useful edge in CRT noise, while tracing only this frame exposes both
    /// the direct queue dispatcher and its std::function target.
    fn traceWindowsCallbackCall(self: *const ElfState, kind: []const u8, target: u64, operand: u64, next_rip: u64) void {
        return process_impl_kernel_services.traceWindowsCallbackCall(self, kind, target, operand, next_rip);
    }

    /// Allocate a guest-owned zero-filled block. This is Rosette's existing
    /// internal allocation contract and remains the default for Win32 object
    /// storage and calloc-style APIs.
    pub fn guestAlloc(self: *ElfState, requested_size: u64, requested_alignment: u64) ?u64 {
        return process_impl_guest_heap.guestAlloc(self, requested_size, requested_alignment);
    }

    /// Allocate storage with C `malloc` semantics: the returned bytes are
    /// unspecified. This avoids clearing large transient CRT allocations and
    /// is intentionally not used by calloc, recalloc, or Rosette-owned state.
    pub fn guestAllocUninitialized(self: *ElfState, requested_size: u64, requested_alignment: u64) ?u64 {
        return process_impl_guest_heap.guestAllocUninitialized(self, requested_size, requested_alignment);
    }

    fn guestAllocWithInitialization(self: *ElfState, requested_size: u64, requested_alignment: u64, zero_fill: bool) ?u64 {
        return process_impl_guest_heap.guestAllocWithInitialization(self, requested_size, requested_alignment, zero_fill);
    }

    /// How much of the PE heap the guest is using and how it is being freed.
    /// `double_frees` and `unknown_frees` are defects of the caller named on
    /// their own lines; a nonzero count is where a use-after-free starts.
    fn reportGuestHeapUse(self: *const ElfState) void {
        return process_impl_guest_heap.reportGuestHeapUse(self);
    }

    fn noteGuestHeapBytes(self: *ElfState, length: u64, live: bool) void {
        return process_impl_guest_heap.noteGuestHeapBytes(self, length, live);
    }

    /// A released block enters quarantine; the oldest quarantined blocks
    /// leave it for their size bin once either limit is passed.
    fn rememberGuestHeapFreeIndex(self: *ElfState, allocation_index: usize) void {
        return process_impl_guest_heap.rememberGuestHeapFreeIndex(self, allocation_index);
    }

    fn releaseOldestGuestHeapQuarantine(self: *ElfState) void {
        return process_impl_guest_heap.releaseOldestGuestHeapQuarantine(self);
    }

    fn binGuestHeapBlock(self: *ElfState, allocation_index: usize) void {
        return process_impl_guest_heap.binGuestHeapBlock(self, allocation_index);
    }

    /// Reuse a released block without changing the address-ordered
    /// provenance table.  Only exact logical lengths are eligible: splitting
    /// a tombstone would require recording a new address-range remainder and
    /// would make the binary-search lifetime table ambiguous.  A reused block
    /// is cleared before it is published to the guest, matching fresh
    /// `guestAlloc` storage and preventing stale contents from crossing CRT
    /// object lifetimes. The oldest block in the bin goes first, and only a
    /// block that has served its quarantine is in a bin at all.
    fn reuseGuestHeapAllocation(self: *ElfState, size: u64, alignment: u64, zero_fill: bool) ?u64 {
        return process_impl_guest_heap.reuseGuestHeapAllocation(self, size, alignment, zero_fill);
    }

    fn takeGuestHeapBinEntry(self: *ElfState, bin: *WindowsHeapBin, position: usize) void {
        return process_impl_guest_heap.takeGuestHeapBinEntry(self, bin, position);
    }

    fn noteGuestHeapFreeAnomaly(self: *ElfState, guest_base: u64, double_free: bool) void {
        return process_impl_guest_heap.noteGuestHeapFreeAnomaly(self, guest_base, double_free);
    }

    /// Grow the address-ordered PE allocation-provenance table.
    ///
    /// Freed records remain as tombstones so the binary-search lookup keeps
    /// its address ordering.  Their exact block indices are tracked separately
    /// by `windows_heap_free_indices`, allowing physical storage reuse without
    /// changing the table's sorted address invariant.
    fn growGuestHeapProvenance(self: *ElfState) bool {
        return process_impl_guest_heap.growGuestHeapProvenance(self);
    }

    /// The guard bytes past `record`'s logical end, when it was allocated
    /// with any.
    fn guestHeapGuardSlice(self: *const ElfState, record: WindowsHeapAllocation) ?[]u8 {
        return process_impl_guest_heap.guestHeapGuardSlice(self, record);
    }

    fn armGuestHeapGuard(self: *ElfState, record: WindowsHeapAllocation) void {
        return process_impl_guest_heap.armGuestHeapGuard(self, record);
    }

    /// Report a block whose guard changed: the guest - or Rosette executing
    /// it - wrote past the block's end into whatever lies after it.
    fn checkGuestHeapGuard(self: *ElfState, index: usize, when: []const u8) void {
        return process_impl_guest_heap.checkGuestHeapGuard(self, index, when);
    }

    fn reportGuestHeapOverrun(self: *ElfState, record: WindowsHeapAllocation, damage: heap_guard.Damage, when: []const u8, occurrence: u64) void {
        return process_impl_guest_heap.reportGuestHeapOverrun(self, record, damage, when, occurrence);
    }

    /// Live blocks whose guard has changed, counted for the report.
    fn countDamagedLiveGuestHeapGuards(self: *const ElfState) u64 {
        return process_impl_guest_heap.countDamagedLiveGuestHeapGuards(self);
    }

    fn findGuestHeapAllocation(self: *ElfState, guest_base: u64) ?usize {
        return process_impl_guest_heap.findGuestHeapAllocation(self, guest_base);
    }

    /// Release the logical ownership of a PE heap block.  The backing bytes
    /// remain in flat guest memory until an exact-size allocation reuses them;
    /// the active bit makes a later realloc/free of a stale pointer
    /// diagnosable instead of silently valid.  The old logical length is
    /// retained so the free-list path can match the block safely.
    pub fn releaseGuestAllocation(self: *ElfState, guest_base: u64) bool {
        return process_impl_guest_heap.releaseGuestAllocation(self, guest_base);
    }

    /// Implement the content-preserving realloc contract used by the PE CRT
    /// and Win32 heap APIs.  `guestAlloc` intentionally zeroes fresh blocks;
    /// that gives `_recalloc` and the newly grown tail the required zero-fill
    /// behavior, while the old bytes are copied before the old record is
    /// retired.  Shrinks stay in place and only reduce the logical extent.
    pub fn reallocateGuest(
        self: *ElfState,
        old_guest_base: u64,
        requested_size: u64,
        requested_alignment: u64,
    ) ?u64 {
        return process_impl_guest_heap.reallocateGuest(self, old_guest_base, requested_size, requested_alignment);
    }

    /// Register a Rosetta-owned address for a Windows function obtained
    /// through GetProcAddress or a Vulkan proc-address query. The executable
    /// only sees a guest address; the state intercepts that address before it
    /// attempts to decode synthetic bytes.
    pub fn registerWindowsImportStub(self: *ElfState, dll_name: []const u8, function_name: []const u8) ?u64 {
        return process_impl_guest_heap.registerWindowsImportStub(self, dll_name, function_name);
    }

    /// Attach a Windows import descriptor to an already materialised PE IAT
    /// thunk. Direct imports and GetProcAddress results must converge on the
    /// same dispatcher; a byte stub that merely returns zero would bypass the
    /// ABI/runtime and make Vulkan initialization appear to succeed while no
    /// host call occurred.
    pub fn registerWindowsImportStubAt(self: *ElfState, address: u64, dll_name: []const u8, function_name: []const u8) bool {
        return process_impl_guest_heap.registerWindowsImportStubAt(self, address, dll_name, function_name);
    }

    /// The PE loader supplies the source IAT slot for direct imports. Keeping
    /// that relationship lets a fault report distinguish a slot overwritten
    /// with a native handle from a callee-saved register corrupted later.
    pub fn registerWindowsImportStubAtIat(self: *ElfState, address: u64, dll_name: []const u8, function_name: []const u8, iat_address: u64) bool {
        return process_impl_guest_heap.registerWindowsImportStubAtIat(self, address, dll_name, function_name, iat_address);
    }

    pub fn windowsImportStubAt(self: *const ElfState, address: u64) ?WindowsImportStub {
        return process_impl_guest_heap.windowsImportStubAt(self, address);
    }

    /// Compatibility hook used by the shared Mach-O Vulkan forwarder when it
    /// publishes a proc-address token. The Windows route intentionally keeps
    /// proc queries on Microsoft-ABI import stubs, so no SysV token is exposed
    /// to the PE instruction loop; retaining the hook lets the generic
    /// forwarder compile against the same state interface without fabricating
    /// an executable guest address.
    pub fn registerSyntheticThunk(_: *ElfState, _: u64, _: u64, _: []const u8) void {
        return process_impl_guest_heap.registerSyntheticThunk(undefined, undefined, undefined, undefined);
    }

    pub fn terminateForUnresolvedWindowsImport(self: *ElfState, dll_name: []const u8, function_name: []const u8) void {
        return process_impl_guest_heap.terminateForUnresolvedWindowsImport(self, dll_name, function_name);
    }

    /// Give the host-side Windows route one opportunity to own a Vulkan
    /// import. The callback receives this state opaquely so the executor does
    /// not depend on the host forwarder's module graph; a missing callback is
    /// an ordinary fallback to the explicit modelled Windows runtime.
    pub fn tryNativeWindowsVulkan(self: *ElfState, name: []const u8, direct_return_rip: ?u64) bool {
        return process_impl_guest_heap.tryNativeWindowsVulkan(self, name, direct_return_rip);
    }

    /// Host CAMetalLayer lookup for the native Vulkan adapter. The callback is
    /// intentionally a host-only pointer-returning seam; no caller may write
    /// this value into guest memory.
    pub fn nativeMetalLayerHostPointer(self: *const ElfState) usize {
        return process_impl_guest_heap.nativeMetalLayerHostPointer(self);
    }

    /// Hand the layer's `drawableSize` to the Vulkan driver, or take it back.
    ///
    /// The bridge sizes the layer from the view until a swapchain exists,
    /// because something has to. After that the property is MoltenVK's: it
    /// writes `drawableSize` from the swapchain's `imageExtent` and reads a
    /// change it did not make as the swapchain going out of date. The window
    /// bridge used to write it from every event pump, which the guest's
    /// message loop calls once per `GetMessage`.
    ///
    /// Returns whether the ownership actually moved, so the caller can log
    /// the transition once rather than on every swapchain create. The move
    /// is one way for the life of the run: the bridge only needed the
    /// property before the first swapchain existed, and a resize is handled
    /// by the swapchain being recreated, which sets it again.
    pub fn setNativeMetalDrawableOwner(self: *const ElfState, owned_by_swapchain: bool) bool {
        return process_impl_guest_heap.setNativeMetalDrawableOwner(self, owned_by_swapchain);
    }

    /// Set the host layer extent before a real Vulkan swapchain is created.
    /// Returning false means the host could not prove that the layer now has
    /// the requested pixels; the caller must not silently create a swapchain
    /// whose images and drawable disagree.
    pub fn prepareNativeMetalDrawable(self: *const ElfState, width: u32, height: u32) bool {
        return process_impl_guest_heap.prepareNativeMetalDrawable(self, width, height);
    }

    pub fn validateNativeMetalLayerToken(_: *const ElfState, token: u64) bool {
        return process_impl_guest_heap.validateNativeMetalLayerToken(undefined, token);
    }

    pub fn nativeWindowWidth(self: *const ElfState) u32 {
        return process_impl_guest_heap.nativeWindowWidth(self);
    }

    pub fn nativeWindowHeight(self: *const ElfState) u32 {
        return process_impl_guest_heap.nativeWindowHeight(self);
    }

    /// Called by the real Vulkan forwarder once its guest surface is bound to
    /// the host layer. Keep this observation separate from the synthetic
    /// Windows ledger; the latter still records the guest ABI transition.
    pub fn noteNativeVulkanSurfaceBound(self: *ElfState, _: u64, _: u64, _: u64) void {
        return process_impl_guest_heap.noteNativeVulkanSurfaceBound(self, undefined, undefined, undefined);
    }

    pub fn terminateUnimplemented(self: *ElfState, d: DecodedInsn) void {
        return process_impl_instruction_decode.terminateUnimplemented(self, d);
    }

    fn raiseDivideError(self: *ElfState) void {
        return process_impl_instruction_decode.raiseDivideError(self);
    }

    pub fn sibAddr(self: *const ElfState, d: *DecodedInsn) void {
        return process_impl_instruction_decode.sibAddr(self, d);
    }

    /// Worker execution is invisible to the owner's checkpoint histogram.
    /// Require both XThread::Execute on this worker and a fetch inside the
    /// tracked Xenia code-cache view; heap trampolines and other workers do
    /// not establish this stage. This proves entry into translated execution,
    /// not a swap or a picture (those retain independent evidence).
    pub fn noteWindowsTitleCodeFetch(self: *ElfState, address: u64) void {
        return process_impl_instruction_decode.noteWindowsTitleCodeFetch(self, address);
    }

    /// The same for `count` instructions fetched from one place, which is
    /// how a translated block reports its run.
    fn noteWindowsTitleCodeFetches(self: *ElfState, address: u64, count: u64) void {
        return process_impl_instruction_decode.noteWindowsTitleCodeFetches(self, address, count);
    }

    fn noteWindowsTitleCodeFetchesIn(self: *ElfState, ctx: GuestContextRef, address: u64, count: u64) void {
        return process_impl_instruction_decode.noteWindowsTitleCodeFetchesIn(self, ctx, address, count);
    }

    /// Up to sixteen instruction bytes at `address`, from the image or from a
    /// Rosette-owned code mapping.
    fn guestInstructionBytes(self: *const ElfState, address: u64, buffer: *[16]u8) []const u8 {
        return process_impl_instruction_decode.guestInstructionBytes(self, address, buffer);
    }

    /// Worker-local decode hits, with the calling thread's unpublished
    /// remainder (`WorkerLocalDecodeCache.noteHit` publishes in batches).
    pub fn decodeCacheWorkerLocalHits(self: *const ElfState) u64 {
        return process_impl_instruction_decode.decodeCacheWorkerLocalHits(self);
    }

    pub fn decodeCacheCounts(self: *const ElfState) DecodeCacheCounters {
        return process_impl_instruction_decode.decodeCacheCounts(self);
    }

    fn logWorkerLocalDecodeCache(self: *const ElfState, counts: DecodeCacheCounters, lookups: u64) void {
        return process_impl_instruction_decode.logWorkerLocalDecodeCache(self, counts, lookups);
    }

    fn touchDecodeCachePrimaryEntry(entry: *DecodeCacheEntry, shard: *DecodeCacheShard) void {
        return process_impl_instruction_decode.touchDecodeCachePrimaryEntry(entry, shard);
    }

    fn touchDecodeCacheVictimEntry(self: *ElfState, entry: *DecodeCacheEntry) void {
        return process_impl_instruction_decode.touchDecodeCacheVictimEntry(self, entry);
    }

    fn decodeCacheEntryHasIdentity(
        entry: *const DecodeCacheEntry,
        fetch_address: u64,
        mapped_code: ?WindowsMappedCodeSlice,
    ) bool {
        return process_impl_instruction_decode.decodeCacheEntryHasIdentity(entry, fetch_address, mapped_code);
    }

    /// Save a displaced primary entry in the bounded victim neighborhood for
    /// its address. This is deliberately independent from the fatal primary
    /// cache contract: the seventeenth live address still records (and, in a
    /// strict PE run, terminates on) a capacity conflict. The victim bank only
    /// makes a later return to an evicted address cheap when the policy is in
    /// diagnostic/continue mode or when a caller explicitly allows recovery.
    fn saveDecodeCacheVictim(self: *ElfState, evicted: *const DecodeCacheEntry, shard: *DecodeCacheShard) void {
        return process_impl_instruction_decode.saveDecodeCacheVictim(self, evicted, shard);
    }

    const DecodeCacheVictimHit = struct {
        entry: *DecodeCacheEntry,
        rearmed: bool,
    };

    /// Probe only the four victim ways selected by the address hash. A victim
    /// is still generation/byte checked; it is a cache tier, not a permission
    /// to execute stale generated code. Stale victims are invalidated here so
    /// repeated returns do not pay for the same dead entry forever.
    fn findDecodeCacheVictim(
        self: *ElfState,
        fetch_address: u64,
        bytes: []const u8,
        remaining: usize,
        mapped_code: ?WindowsMappedCodeSlice,
        shard: *DecodeCacheShard,
    ) ?DecodeCacheVictimHit {
        return process_impl_instruction_decode.findDecodeCacheVictim(self, fetch_address, bytes, remaining, mapped_code, shard);
    }

    fn noteDecodeCacheMiss(
        self: *ElfState,
        cause: DecodeCacheMissCause,
        fetch_address: u64,
        set_index: usize,
        resident_addresses: [PE_DECODE_CACHE_WAYS]u64,
        resident_count: usize,
        mapped_code: ?WindowsMappedCodeSlice,
        shard: *DecodeCacheShard,
    ) void {
        return process_impl_instruction_decode.noteDecodeCacheMiss(self, cause, fetch_address, set_index, resident_addresses, resident_count, mapped_code, shard);
    }

    fn reportDecodeCacheMissSites(self: *const ElfState) void {
        return process_impl_instruction_decode.reportDecodeCacheMissSites(self);
    }

    pub fn reportInvalidWindowsControlTarget(self: *ElfState, fetch_address: u64) bool {
        return process_impl_instruction_decode.reportInvalidWindowsControlTarget(self, fetch_address);
    }

    inline fn resolveDecodedAddress(
        self: *ElfState,
        decoded: DecodedInsn,
        decoded_segment: x64_decoder.Segment,
    ) DecodedInsn {
        return process_impl_instruction_decode.resolveDecodedAddress(self, decoded, decoded_segment);
    }

    pub fn decodeAt(self: *ElfState) ?DecodedInsn {
        return process_impl_instruction_decode.decodeAt(self);
    }

    /// Move the guest performance counter forward.
    ///
    /// Called from `step`, which is the one boundary the owner loop and every
    /// cooperative worker share, so the counter advances for whichever thread
    /// is running. See `WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE` for why the source
    /// is the host's monotonic clock rather than the instruction count.
    ///
    /// Never decreases. A performance counter that goes backwards makes a
    /// guest computing `now - then` see an enormous unsigned interval, and
    /// every deadline in the run is computed that way.
    pub fn advanceWindowsGuestClock(self: *ElfState) void {
        return process_impl_instruction_decode.advanceWindowsGuestClock(self);
    }

    fn advanceWindowsGuestClockIn(self: *ElfState, ctx: GuestContextRef) void {
        return process_impl_instruction_decode.advanceWindowsGuestClockIn(self, ctx);
    }

    /// A parallel executor's strided host-clock sample. It never waits: an
    /// executor that finds the clock held skips this sample and takes its
    /// next one a stride later, because the holder is sampling the clock or
    /// reading a snapshot of it. Deadline decisions still use
    /// `refreshWindowsGuestClock`, which waits.
    fn sampleWindowsGuestClockIfFree(self: *ElfState) void {
        return process_impl_instruction_decode.sampleWindowsGuestClockIfFree(self);
    }

    /// Sample the host clock now, whatever the stride says.
    ///
    /// The stride exists to keep the read off the per-instruction path. A
    /// caller that is about to decide something *because* of the time has to
    /// ask for the current answer instead.
    pub fn refreshWindowsGuestClock(self: *ElfState) void {
        return process_impl_instruction_decode.refreshWindowsGuestClock(self);
    }

    /// `advanceWindowsGuestClock` for `count` instructions retired at once by
    /// a translated block; `step` already counted the first.
    pub fn advanceWindowsGuestClockBy(self: *ElfState, count: u64) void {
        return process_impl_instruction_decode.advanceWindowsGuestClockBy(self, count);
    }

    // ─── Block translation glue ───

    // The register files, the scratch record and the TLB are the executing
    // guest context's, reached through the scratch record the entry receives
    // (`.pointers_in_scratch`): translated code on several host threads at
    // once never shares a binding. The offsets below are process-wide state,
    // which every executor reads alike.
    const block_jit_layout = block_jit.Layout{
        .regs_offset = 0,
        .scratch_offset = 0,
        .tlb_offset = 0,
        .xmm_offset = 0,
        .ymm_hi_offset = 0,
        .zmm_hi_offset = 0,
        .register_files = .pointers_in_scratch,
        .trace_calls_offset = @offsetOf(ElfState, "trace_calls"),
        .return_captures_offset = @offsetOf(ElfState, "guest_return_captures_armed"),
        .trace_transfers_offset = @offsetOf(ElfState, "block_jit_transfer_traced"),
        .image_low_offset = @offsetOf(ElfState, "image_low"),
        .image_high_offset = @offsetOf(ElfState, "image_high"),
        .code_cache_low_offset = @offsetOf(ElfState, "block_jit_code_cache_guest_low"),
        .code_cache_high_offset = @offsetOf(ElfState, "block_jit_code_cache_guest_high"),
        .iat_low_offset = @offsetOf(ElfState, "windows_iat_low"),
        .iat_high_offset = @offsetOf(ElfState, "windows_iat_high"),
        .hook_filter_offset = @offsetOf(ElfState, "block_jit_hook_filter"),
        .xbox_critical_section_enter_offset = @intCast(@offsetOf(ElfState, "xbox_critical_section_hooks") + @offsetOf(xbox_critical_section.Hooks, "addresses") + @as(usize, @intFromEnum(xbox_critical_section.Export.enter)) * @sizeOf(u64)),
        .xbox_critical_section_leave_offset = @intCast(@offsetOf(ElfState, "xbox_critical_section_hooks") + @offsetOf(xbox_critical_section.Hooks, "addresses") + @as(usize, @intFromEnum(xbox_critical_section.Export.leave)) * @sizeOf(u64)),
        .image_targets_hooked_offset = @offsetOf(ElfState, "block_jit_image_targets_hooked"),
        .milestone_saturated_offset = @offsetOf(ElfState, "guest_milestone_saturated"),
        .milestone_hits_offset = @offsetOf(ElfState, "guest_milestone_hits"),
    };

    /// Keep the translator's one-load view of the transfer traces in step
    /// with the two fields it stands for. Called wherever either is set;
    /// translated `call` sites read it on every execution, so a trace turned
    /// on after a block was compiled still reaches the interpreter's arm.
    fn refreshBlockJitTransferTraced(self: *ElfState) void {
        return process_impl_block_jit.refreshBlockJitTransferTraced(self);
    }

    /// Per-instruction tracing reads state the translator does not write
    /// between instructions; the translator stays off while any of it is on.
    fn blockJitTracingActive(self: *const ElfState) bool {
        return process_impl_block_jit.blockJitTracingActive(self);
    }

    /// The translator, created on first use so a state that never steps
    /// (most tests) never maps executable memory.
    /// The slot of the guest thread this host thread is executing, when it is
    /// a worker running on its own host thread (parallel mode). Cooperative
    /// workers run on the owner's host thread and share the owner's state.
    fn parallelWorkerSlot(self: *ElfState) ?usize {
        return process_impl_block_jit.parallelWorkerSlot(self);
    }

    /// The translator state the executing guest context uses, if it has one.
    pub fn currentBlockJit(self: *ElfState) ?*BlockJitState {
        return process_impl_block_jit.currentBlockJit(self);
    }

    /// Every translator state in the process: the owner's and each parallel
    /// worker's. For drops that must reach every cache - a mapping going away
    /// - which run with the world stopped.
    fn forEachBlockJitState(self: *ElfState, context: anytype, comptime visit: fn (@TypeOf(context), *ElfState, *BlockJitState) void) void {
        return process_impl_block_jit.forEachBlockJitState(self, context, visit);
    }

    pub fn blockJitActive(self: *ElfState) ?*BlockJitState {
        return process_impl_block_jit.blockJitActive(self);
    }

    /// A parallel worker's own translator state, created the first time one
    /// of its blocks gets hot. Guest threads on different host threads each
    /// translate into their own cache, so translated code runs on every core
    /// with nothing shared but read-only process state. Until 2026-09-25
    /// every worker was interpreted: the one block table had no owner but
    /// the process's first thread.
    pub fn parallelWorkerBlockJit(self: *ElfState, slot: usize) ?*BlockJitState {
        return process_impl_block_jit.parallelWorkerBlockJit(self, slot);
    }

    /// Fill `block_jit_hook_filter` from every call-arm hook the image has,
    /// and clear the master switch only when nothing hooks an image target
    /// the filter cannot see.
    ///
    /// The accelerators used to resolve their targets on the first call that
    /// reached the interpreter's arm, which is after this filter is first
    /// built, and nothing rebuilt it. The master switch therefore stayed on
    /// for the whole of the 2026-09-22 Custom Games run: every virtual call,
    /// register call and jump-table dispatch into Xenia's own code - about
    /// 510 million of them, more than half of all interpreter fallbacks -
    /// left translated code for the interpreter and broke its chain. The
    /// indirect arms never consult an accelerator at all; only `call_rel32`
    /// does. They are resolved here instead, before anything is decided.
    pub fn rebuildBlockJitHookFilter(self: *ElfState) void {
        return process_impl_block_jit.rebuildBlockJitHookFilter(self);
    }

    /// Compute the hook filter from every hook source and publish it a byte
    /// at a time. Translated code on other host threads reads it while this
    /// runs, which is why it is never cleared first: each byte goes straight
    /// from its old value to its new one. Members only ever leave it (a
    /// saturated census export), so every byte a reader can see - old or new
    /// - still has the bits of every hook that remains.
    pub fn publishBlockJitHookFilter(self: *ElfState) void {
        return process_impl_block_jit.publishBlockJitHookFilter(self);
    }

    pub fn blockJitRequestAbort(self: *ElfState) void {
        return process_impl_block_jit.blockJitRequestAbort(self);
    }

    /// Set the diagnostic RIP and op to the instruction the emitted code
    /// named before calling a helper, so a fault raised inside the helper
    /// carries the same `instruction_rip` the interpreter would have.
    pub fn blockJitNameCurrentInstruction(self: *ElfState) void {
        return process_impl_block_jit.blockJitNameCurrentInstruction(self);
    }

    /// Run instruction `index` of `block` through the interpreter: the same
    /// address resolution `decodeAt` performs, then `execute`.
    pub fn blockJitExecuteInsn(self: *ElfState, block: *const block_jit.Block, index: u32) void {
        return process_impl_block_jit.blockJitExecuteInsn(self, block, index);
    }

    const InstructionSource = struct {
        storage: [PE_MAX_INSTRUCTION_LENGTH]u8 = undefined,
        len: usize = 0,
        mapped: ?WindowsMappedCodeSlice,

        pub fn contents(self: *const InstructionSource) []const u8 {
            return self.storage[0..self.len];
        }
    };

    /// Up to fifteen instruction bytes at `address`, from the image or a
    /// code mapping, with the mapping's identity when it came from one.
    fn fetchInstructionSource(self: *ElfState, address: u64) ?InstructionSource {
        return process_impl_block_jit.fetchInstructionSource(self, address);
    }

    /// The bytes a compiled block covers, as they are now.
    fn fetchCodeRange(self: *const ElfState, address: u64, count: usize) ?[]const u8 {
        return process_impl_block_jit.fetchCodeRange(self, address, count);
    }

    fn copyGuestCode(self: *const ElfState, destination: []u8, source: []const u8) void {
        return process_impl_block_jit.copyGuestCode(self, destination, source);
    }

    pub fn guestCodeRangeMatches(self: *const ElfState, address: u64, expected: []const u8) bool {
        return process_impl_block_jit.guestCodeRangeMatches(self, address, expected);
    }

    /// Whether a jump to `target` is one the interpreter intercepts (a
    /// compatibility shim, import stub, or synthetic return).
    pub fn blockJitTargetHooked(self: *const ElfState, target: u64) bool {
        return process_impl_block_jit.blockJitTargetHooked(self, target);
    }

    /// Exact membership for every source published into `block_jit_hook_filter`.
    /// This is only called after the emitted fast path sees a Bloom hit, so
    /// the less common linear milestone probes are kept off ordinary calls.
    pub fn blockJitIndirectTargetHooked(self: *const ElfState, target: u64) bool {
        return process_impl_block_jit.blockJitIndirectTargetHooked(self, target);
    }

    /// A stable pointer to the live generation word for a block's source.
    ///
    /// `windows_file_mappings` and `windows_virtual_allocations` are fixed
    /// arrays inside the state, so a pointer into one stays valid for the
    /// life of the run - which is what lets translated code check a
    /// successor's generation with a load instead of a call back into here.
    /// Null when the source has no generation word; such a block is never
    /// chained into.
    fn blockJitGenerationPointer(self: *ElfState, mapped: bool, kind: u8, index: usize) ?*const u64 {
        return process_impl_block_jit.blockJitGenerationPointer(self, mapped, kind, index);
    }

    /// The generation the block's source currently carries, or null when the
    /// source has no generation and bytes must be compared.
    pub fn blockJitSourceGeneration(self: *ElfState, block: *const block_jit.Block) ?u64 {
        return process_impl_block_jit.blockJitSourceGeneration(self, block);
    }

    /// A block-entry generation check cannot protect a block that rewrites
    /// its own *upcoming* instructions. Retire the completed store, then
    /// resume at the next RIP through the authoritative decode path. Writes
    /// to ordinary data or already-consumed instructions don't force an exit.
    pub fn blockJitContinuationChanged(self: *ElfState) bool {
        return process_impl_block_jit.blockJitContinuationChanged(self);
    }

    /// A block stays valid while its source generation is unchanged; when
    /// the generation moved (Xenia's code cache is written constantly) the
    /// bytes decide, exactly as the decode cache's rearm path does.
    fn blockJitValidate(self: *ElfState, jit: *BlockJitState, block: *block_jit.Block) bool {
        return process_impl_block_jit.blockJitValidate(self, jit, block);
    }

    fn dropBlockJitSlot(self: *ElfState, jit: *BlockJitState, index: usize) void {
        return process_impl_block_jit.dropBlockJitSlot(self, jit, index);
    }

    /// The outermost translated execution's return is the first point where
    /// nothing translated is on the host stack: the lifetime frees what
    /// nesting retired, and a reset a nested compilation asked for runs.
    pub fn leaveBlockJitExecution(self: *ElfState, jit: *BlockJitState) void {
        return process_impl_block_jit.leaveBlockJitExecution(self, jit);
    }

    /// The valid block compiled for `rip`, if one is in its set.
    pub fn blockJitFind(self: *ElfState, rip: u64) ?*block_jit.Block {
        return process_impl_block_jit.blockJitFind(self, rip);
    }

    /// The hotness entry for `rip`: its own when it has one, otherwise the
    /// set's empty or coldest entry, reset to this address.
    pub fn blockJitHotness(jit: *BlockJitState, rip: u64) *BlockHotness {
        return process_impl_block_jit.blockJitHotness(jit, rip);
    }

    /// Never compile `rip` again.
    fn blockJitRefuse(jit: *BlockJitState, rip: u64) void {
        return process_impl_block_jit.blockJitRefuse(jit, rip);
    }

    /// One worker's refused compilations: how many of each reason, how
    /// many retries, and the first addresses with the instruction each
    /// began with.
    fn reportBlockJitRefusals(self: *const ElfState, slot: usize, jit: *const BlockJitState) void {
        return process_impl_block_jit.reportBlockJitRefusals(self, slot, jit);
    }

    /// Count a refused compilation by reason, and name the first few.
    fn noteBlockJitRefusal(jit: *BlockJitState, rip: u64, retries: u8) void {
        return process_impl_block_jit.noteBlockJitRefusal(jit, rip, retries);
    }

    /// Drop every block; the code memory starts over. The hotness table is
    /// kept: every address that had a block is still hot, and recompiling
    /// it at its next execution rather than after another sixteen
    /// interpreted runs is what keeps a reset from being a second cold
    /// start.
    pub fn resetBlockJit(self: *ElfState, jit: *BlockJitState) void {
        return process_impl_block_jit.resetBlockJit(self, jit);
    }

    /// One mapping was unmapped or released: the blocks compiled from it
    /// must not outlive the backing, whatever their generation says (a
    /// recreated mapping can reuse both slot and generation 1).
    /// Every executor's cache, not only the caller's: the mapping is gone
    /// for all of them. In parallel mode this runs under the address-space
    /// lock, so no other executor is inside a step; one parked mid-block in
    /// a safe region keeps its live block, which its lifetime retires.
    fn blockJitDropMappedSource(self: *ElfState, kind: mapped_ranges.Kind, source_index: usize) void {
        return process_impl_block_jit.blockJitDropMappedSource(self, kind, source_index);
    }

    /// Every mapped block, for the generation-saturation boundary.
    fn blockJitDropAllMapped(self: *ElfState) void {
        return process_impl_block_jit.blockJitDropAllMapped(self);
    }

    pub fn blockJitDropAll(self: *ElfState) void {
        return process_impl_block_jit.blockJitDropAll(self);
    }

    // -- the software TLB -----------------------------------------------------

    /// After a helper served a plain access, decide whether emitted code
    /// may touch the page directly from now on. Admission requires: no
    /// trace watch on stores; the access inside one page; the page backed
    /// by the image or an indexed mapping; not restricted
    /// for that direction; and, for writes, neither executable image bytes
    /// nor a mapping instructions were ever fetched from, because a store
    /// into those must bump the decode generation. Native aliases stay
    /// helper-only so their device boundary is preserved. Everything refused
    /// here keeps taking the interpreter's own path.
    /// Whether a live store trace still needs to see every write, which the
    /// write TLB would hide by letting translated code store directly.
    ///
    /// Only for a page the trace could actually print. The mapped-write trace
    /// observes stores above its floor and outside the process image, and a
    /// watched address only its own bytes; withholding every page instead
    /// kept the write TLB off until the 64-event budget was spent, which in
    /// a run that never makes such stores is the whole run (2026-09-24:
    /// 3,991,907 of 3,997,545 translated stores took the helper).
    pub fn traceWithholdsWriteTlb(self: *ElfState, page: u64) bool {
        return process_impl_block_jit.traceWithholdsWriteTlb(self, page);
    }

    fn noteBlockJitTlbRefusal(
        jit: *BlockJitState,
        reason: tlb_diagnostics.RefusalReason,
        page: u64,
        is_write: bool,
        epoch: u64,
        cacheable: bool,
    ) void {
        return process_impl_block_jit.noteBlockJitTlbRefusal(jit, reason, page, is_write, epoch, cacheable);
    }

    pub fn blockJitTlbConsider(self: *ElfState, address: u64, width: u8, is_write: bool) void {
        return process_impl_block_jit.blockJitTlbConsider(self, address, width, is_write);
    }

    pub fn activeBlockJitTlb(self: *ElfState) *block_jit.Tlb {
        return process_impl_block_jit.activeBlockJitTlb(self);
    }

    pub fn ownerBlockJitTlb(self: *ElfState) *block_jit.Tlb {
        return process_impl_block_jit.ownerBlockJitTlb(self);
    }

    /// The affinity mask the parallel executor reports: one bit per host
    /// processor, at most 64. `ROSETTE_PE64_GUEST_CPUS=N` overrides it (1
    /// restores the cooperative answer for an A/B run). With one processor
    /// reported, Xenia created one Vulkan pipeline-creation thread however
    /// many cores the executor could have run them on.
    pub fn guestProcessorMask() u64 {
        return process_impl_block_jit.guestProcessorMask();
    }

    /// Whether PE launches run guest threads on their own host threads.
    /// `ROSETTE_PE64_PARALLEL=0` selects the cooperative executor instead.
    fn parallelGuestExecutionRequested() bool {
        return process_impl_block_jit.parallelGuestExecutionRequested();
    }

    /// How long guest progress may stand still before the stall watchdog
    /// reports every thread's state: `ROSETTE_PE64_STALL_SECONDS`, ten by
    /// default, zero to disable.
    fn parallelStallThresholdNanoseconds() u64 {
        return process_impl_block_jit.parallelStallThresholdNanoseconds();
    }

    /// `ROSETTE_PE64_THREAD_PULSE_SECONDS` (default 5, 0 = off): how often the
    /// watchdog writes `PE64 THREAD PULSE`.
    fn parallelThreadPulseNanoseconds() u64 {
        return process_impl_block_jit.parallelThreadPulseNanoseconds();
    }

    /// `ROSETTE_PE64_LOCK_HOLD_SECONDS` (default 3, 0 = off): one holder
    /// keeping the runtime lock this long without a release is reported as a
    /// `runtime_lock_held` stall, naming the holder and the call it is in.
    fn parallelLockHoldThresholdNanoseconds() u64 {
        return process_impl_block_jit.parallelLockHoldThresholdNanoseconds();
    }

    /// On the host main thread, make every wait serve the AppKit requests
    /// guest workers `dispatch_sync` to it (lib/concurrency/park.zig). The
    /// owner guest thread runs on the main thread; before this, a worker that
    /// held the runtime gate while waiting on such a request, and the main
    /// thread waiting on that gate, deadlocked (2026-09-25). Returns the
    /// service to restore.
    fn installMainThreadParkService(self: *ElfState) ?concurrency.Service {
        return process_impl_block_jit.installMainThreadParkService(self);
    }

    fn serviceMainThreadFromPark(context: ?*anyopaque) void {
        return process_impl_block_jit.serviceMainThreadFromPark(context);
    }

    /// The stall watchdog's measure of progress: guest instructions retired
    /// by every executor. Lock-free.
    fn concurrencyProgress(context: ?*anyopaque) u64 {
        return process_impl_block_jit.concurrencyProgress(context);
    }

    /// Runs on the watchdog's own thread when guest progress stood still for
    /// the threshold, or a stop-the-world was held that long. Reads only
    /// lock-free state - the process may be deadlocked - and names every
    /// thread's wait, so a hang reads as a graph instead of a last line.
    fn reportConcurrencyStall(context: ?*anyopaque, finding: *const concurrency.stall.Report) void {
        return process_impl_block_jit.reportConcurrencyStall(context, finding);
    }

    const RuntimeLockHolder = struct {
        name: []const u8 = "nobody",
        activity: []const u8 = "",
    };

    /// Who holds the runtime lock, by the holder's watch record: its thread
    /// name and the call it is in. Lock-free, for the watchdog thread.
    fn runtimeLockHolderDescription(holder_id: u64, activity_buffer: []u8) RuntimeLockHolder {
        return process_impl_block_jit.runtimeLockHolderDescription(holder_id, activity_buffer);
    }

    /// The watchdog's periodic look at every host thread (`ROSETTE_PE64_THREAD_PULSE_SECONDS`,
    /// default 5, 0 = off): dense for the first minute of the run, then every
    /// thirty seconds. Runs on the watchdog thread and reads only lock-free
    /// state, so it keeps reporting while every guest thread is stuck.
    fn reportConcurrencyPulse(context: ?*anyopaque, pulse: *const concurrency.stall.Pulse) void {
        return process_impl_block_jit.reportConcurrencyPulse(context, pulse);
    }

    /// A guest thread's registers changed between two of its own steps
    /// (`register_tripwire`). Called by that thread's own executor.
    fn noteContextRace(self: *ElfState, thread: u64, slot: ?usize, finding: parallel_diagnostics.register_tripwire.Finding) void {
        return process_impl_block_jit.noteContextRace(self, thread, slot, finding);
    }

    /// One line naming every parallel-mode hazard this run tripped, with a
    /// verdict, so the first question about a parallel run - did the
    /// executor itself misbehave? - has a one-line answer at the end of the
    /// log. Each count has its own detailed line earlier.
    fn reportParallelHazards(self: *ElfState) void {
        return process_impl_block_jit.reportParallelHazards(self);
    }

    /// The calls that held the runtime lock longest (parallel mode).
    fn reportRuntimeLockHolds(self: *ElfState) void {
        return process_impl_block_jit.reportRuntimeLockHolds(self);
    }

    /// Every lock-free import lane, at each checkpoint where one moved and at
    /// the end. Checkpoints matter: a run that ends in ExitProcess never
    /// reaches the final report, which is how the 2026-09-30 run printed no
    /// C runtime line at all.
    fn reportWindowsFastImports(self: *ElfState, final: bool) void {
        return process_impl_block_jit.reportWindowsFastImports(self, final);
    }

    /// Where parallel execution's time went: stop-the-worlds, lock
    /// contention, parks, wakeups. Emitted at checkpoints and at the end of
    /// the run, so a slow run says whether it was the guest or the executor.
    fn reportConcurrency(self: *ElfState) void {
        return process_impl_block_jit.reportConcurrency(self);
    }

    /// Enter or leave the access-coordinated mode used while guest contexts
    /// overlap across host threads. The executor must quiesce all other guest
    /// workers before changing this switch; it is a memory-path contract, not
    /// a substitute for stopping workers before map/protection mutations.
    pub fn setParallelGuestExecution(self: *ElfState, enabled: bool) void {
        return process_impl_block_jit.setParallelGuestExecution(self, enabled);
    }

    pub fn activeGuestTsoStoreBuffer(self: *ElfState) ?*tso_memory.StoreBuffer {
        return process_impl_block_jit.activeGuestTsoStoreBuffer(self);
    }

    /// Whether translated code of overlapping executors takes the direct
    /// TLB route (see `parallel_direct_tlb`).
    pub fn parallelDirectTlbActive(self: *const ElfState) bool {
        return process_impl_block_jit.parallelDirectTlbActive(self);
    }

    /// The translator whose counters a TLB fill charges: the executing
    /// worker's own, or the owner's.
    pub fn tlbFillBlockJit(self: *ElfState) ?*BlockJitState {
        return process_impl_block_jit.tlbFillBlockJit(self);
    }

    /// A process-wide TLB counter: plain in serial mode, atomic once
    /// executors overlap.
    fn bumpTlbCounter(self: *const ElfState, counter: *u64) void {
        return process_impl_block_jit.bumpTlbCounter(self, counter);
    }

    /// Called only with the execution gate held exclusively. Pending entries
    /// contain host addresses, so every executor must publish its queue before
    /// runtime mutation can recycle or remap guest storage.
    pub fn flushAllGuestStoreBuffers(self: *ElfState, boundary: tso_memory.Boundary) void {
        return process_impl_block_jit.flushAllGuestStoreBuffers(self, boundary);
    }

    /// Allocate one software TLB per cooperative guest worker. The execution
    /// is still single-host-threaded, but separate replacement state prevents
    /// a worker's working set from evicting the owner's entries at every
    /// switch and gives a future executor an owned TLB to carry with it.
    pub fn ensureWindowsGuestThreadTlb(self: *ElfState, index: usize) ?*block_jit.Tlb {
        return process_impl_block_jit.ensureWindowsGuestThreadTlb(self, index);
    }

    pub fn invalidateAllBlockJitTlbs(self: *ElfState, base: u64, length: u64) void {
        return process_impl_block_jit.invalidateAllBlockJitTlbs(self, base, length);
    }

    /// `invalidateAllBlockJitTlbs` for the read table, the write table, both
    /// or neither. Neither still moves the parallel epoch, which is what
    /// drops every executor's cached refusals for the range.
    fn invalidateAllBlockJitTlbTables(self: *ElfState, base: u64, length: u64, reads: bool, writes: bool) void {
        return process_impl_block_jit.invalidateAllBlockJitTlbTables(self, base, length, reads, writes);
    }

    pub fn flushAllBlockJitTlbs(self: *ElfState, reads: bool, writes: bool) void {
        return process_impl_block_jit.flushAllBlockJitTlbs(self, reads, writes);
    }

    fn blockJitTlbInvalidate(self: *ElfState, base: u64, length: u64) void {
        return process_impl_block_jit.blockJitTlbInvalidate(self, base, length);
    }

    fn blockJitTlbFlush(self: *ElfState, reads: bool, writes: bool) void {
        return process_impl_block_jit.blockJitTlbFlush(self, reads, writes);
    }

    /// Remember that instructions were fetched from a mapping: from then on
    /// its pages are never admitted to the write TLB, and any already
    /// admitted are dropped.
    pub fn noteMappedCodeFetched(self: *ElfState, slice: WindowsMappedCodeSlice) void {
        return process_impl_block_jit.noteMappedCodeFetched(self, slice);
    }

    fn mappedCodeWasFetched(self: *const ElfState, flag: *const bool) bool {
        return process_impl_block_jit.mappedCodeWasFetched(self, flag);
    }

    pub fn mappedRangeCodeFetched(self: *const ElfState, range: mapped_ranges.Range) bool {
        return process_impl_block_jit.mappedRangeCodeFetched(self, range);
    }

    /// Whether a `call` to `target` would fall all the way through the
    /// interpreter's `.call_rel32` arm to its last two lines - push the
    /// return address, set RIP - with every hook on the way declining.
    ///
    /// That arm is the one place Rosette dispatches the guest milestone
    /// tracepoints, the kernel-call census, the SHA-1/Rijndael/tabulate
    /// accelerators, the pthread condition shim, the keyboard shim and the
    /// local-function shims. A native template that skipped any of them
    /// would not be a translation - it would silently disarm the
    /// instruments this project diagnoses with, and an accelerator that
    /// stops firing is a boot that stops finishing.
    ///
    /// So the predicate is deliberately conservative rather than exhaustive:
    /// **a target inside the guest image is always refused.** Every hook
    /// above is an address in Xenia's own code - resolved from one of its
    /// symbols, or armed as one of its kernel exports - so a target outside
    /// the image cannot be one, whatever hooks exist now or later. That
    /// admits exactly the hot case, Xenia's generated PowerPC code, which
    /// lives outside the image and carries no symbols, and leaves every call
    /// into the image on the interpreter where the hooks are.
    ///
    /// The range test also has to be the one that carries this, because it
    /// is O(1). An earlier version asked `localSymbolNameAt`, which is a
    /// linear scan of the roughly ninety-six thousand symbols Xenia's MinGW
    /// binary keeps: once per call site across 6.96 million block compiles,
    /// that alone would have cost more than the fallbacks it removes. Every
    /// remaining check below is a range test, an array index or a hash
    /// probe; none of them may become a scan.
    pub fn blockJitCallTargetPlain(self: *ElfState, target: u64) bool {
        return process_impl_block_jit.blockJitCallTargetPlain(self, target);
    }

    /// Every other hook `blockJitCallTargetPlain` rules out; a milestone
    /// target that passes this can be gated rather than refused.
    fn blockJitCallTargetPlainIgnoringMilestones(self: *ElfState, target: u64) bool {
        return process_impl_block_jit.blockJitCallTargetPlainIgnoringMilestones(self, target);
    }

    /// Why a direct call's target must stay the interpreter's, or null when
    /// the translated `call` may push and jump by itself. A refusal is
    /// permanent for the block compiled with it, so the reason is counted
    /// (`PE64 BLOCK JIT CALL REFUSALS`): on 2026-09-26 one call site inside
    /// XexModule::ReadImageBasicCompressed fell back 548,651 times on the
    /// UI thread during CompleteLaunch, and nothing said which rule refused it.
    pub fn blockJitCallRefusal(self: *ElfState, target: u64) ?BlockJitCallRefusal {
        return process_impl_block_jit.blockJitCallRefusal(self, target);
    }

    /// Count one compile-time call refusal, and name the first few sites.
    fn noteBlockJitCallRefusal(self: *ElfState, site: u64, target: u64, refusal: BlockJitCallRefusal) void {
        return process_impl_block_jit.noteBlockJitCallRefusal(self, site, target, refusal);
    }

    /// Decode the straight-line run at `rip` and compile it. Null when there
    /// is nothing worth compiling there; the caller records the refusal.
    pub fn compileBlockJit(self: *ElfState, jit: *BlockJitState, rip: u64) ?*block_jit.Block {
        return process_impl_block_jit.compileBlockJit(self, jit, rip);
    }

    /// Account one block's execution the way `step` and its loops account
    /// an interpreted instruction, and return how many instructions it
    /// retired. The caller owns `step_retired` and the clock, because one
    /// step may run a chain of blocks.
    fn accountBlockJit(self: *ElfState, jit: *BlockJitState, block: *block_jit.Block, completed: u32) u32 {
        return process_impl_block_jit.accountBlockJit(self, jit, block, completed);
    }

    fn accountBlockJitIn(self: *ElfState, ctx: GuestContextRef, jit: *BlockJitState, block: *block_jit.Block, completed: u32) u32 {
        return process_impl_block_jit.accountBlockJitIn(self, ctx, jit, block, completed);
    }

    /// `accountBlockJit` over a whole native chain, from the counters the
    /// chain kept as it ran: how many blocks and instructions, the share
    /// image blocks and mapped blocks outside the code cache retired, the
    /// first block, and the last with what it retired. The totals,
    /// `last_instruction_rip` and both code-fetch ledgers read exactly as if
    /// each block had been accounted on its own - the lockstep tests compare
    /// them against the interpreter. The per-block counters see the first
    /// and last block only; a chain used to log every block for them, and
    /// the log's 64 entries were what bounded the chain.
    fn accountBlockJitRun(self: *ElfState, ctx: GuestContextRef, jit: *BlockJitState, first: *block_jit.Block, last: *block_jit.Block, completed: u32, record: *const block_jit.Scratch) u32 {
        return process_impl_block_jit.accountBlockJitRun(self, ctx, jit, first, last, completed, record);
    }

    /// The code-fetch ledger a block's instructions count to, decided as it
    /// is compiled.
    fn blockJitLedger(self: *const ElfState, source_mapped: bool, rip: u64) block_jit.Ledger {
        return process_impl_block_jit.blockJitLedger(self, source_mapped, rip);
    }

    /// Let native hops enter `block` once its bytes are proven at a
    /// generation and, for a register-only block, once the interpreter has
    /// cross-checked it. A block outside every executable range has no
    /// generation of its own and is armed at the word's current value, as
    /// its links always were.
    fn blockJitArmChain(block: *block_jit.Block) void {
        return process_impl_block_jit.blockJitArmChain(block);
    }

    const FoundBlock = struct { block: *block_jit.Block, slot: usize };

    /// `blockJitFindValid`, also saying which slot it came from, because a
    /// native chain link has to name the slot it expects its successor to
    /// still occupy.
    pub fn blockJitFindValidSlot(self: *ElfState, jit: *BlockJitState, rip: u64) ?FoundBlock {
        return process_impl_block_jit.blockJitFindValidSlot(self, jit, rip);
    }

    /// Record the hop `from` just took so translated code can take it again
    /// without returning here.
    ///
    /// Everything the emitted check will compare is captured now: the guest
    /// address, the successor's entry past its prologue, its helper table,
    /// the table slot with the pointer that slot must still hold, and its
    /// source generation. A block that is evicted leaves a different pointer
    /// in its slot, and a source that is rewritten moves its generation, so
    /// either makes the link fail its check and fall back here - no list of
    /// back-pointers to unlink, and nothing to get wrong at eviction time.
    fn blockJitLink(self: *ElfState, jit: *BlockJitState, from: *block_jit.Block, rip: u64, to: *block_jit.Block, slot: usize) void {
        return process_impl_block_jit.blockJitLink(self, jit, from, rip, to, slot);
    }

    /// The bytes of a thread's hottest region, so it can be disassembled and
    /// called work or a wait.
    ///
    /// The region's name alone cannot say. On 2026-09-20 the GPU thread's
    /// hotspot was named `Queue::Acquisition`, a lock, because that symbol
    /// starts the region - and the bytes, disassembled from the image, run
    /// on through a `deque::emplace_back` into
    /// `VulkanCommandProcessor::WriteRegister`, which is the command stream
    /// doing real work. Code in Xenia's JIT cache has no bytes on disk to
    /// check that way, and it is where the title's own hottest region is,
    /// so it is logged here while it still exists.
    fn logHotspotBytes(self: *const ElfState, handle: u64, address: u64) void {
        return process_impl_block_jit.logHotspotBytes(self, handle, address);
    }

    /// The valid block for `rip` in its set, dropping a stale one.
    fn blockJitFindValid(self: *ElfState, jit: *BlockJitState, rip: u64) ?*block_jit.Block {
        return process_impl_block_jit.blockJitFindValid(self, jit, rip);
    }

    /// Execute a valid block from the current RIP, then keep going: while
    /// the RIP a block leaves has a valid, verified block of its own that no
    /// hook owns, and nothing asked the step to end (a pending fault, the
    /// run ending, a thread switch or a slice yield from an interpreted
    /// instruction), that block runs too. One `step` thus retires a chain of
    /// blocks; the chain is bounded so the loops' per-step services keep
    /// their cadence. Returns `step`'s result.
    /// Point translated code at the executing guest context's register
    /// files - the owner's own fields, or the bound worker's context - by
    /// writing them into that context's own scratch record, which the block
    /// receives at entry. The binding used to be one field of the shared
    /// state, rebound on every entry and saved around nested ones; with
    /// translated code on several host threads that field would be rewritten
    /// under a running block by another thread's entry. Returns the record to
    /// pass to the block.
    fn bindBlockJitRegisterFile(self: *ElfState) *block_jit.Scratch {
        return process_impl_block_jit.bindBlockJitRegisterFile(self);
    }

    /// The first translated-code entry of the run that found its executor
    /// still holding buffered stores. The entry drained them, so this run is
    /// not affected from here on, but some tier boundary before it is missing
    /// its drain and every run that reaches it reads stale memory there.
    fn logTranslatedEntryViolation(self: *ElfState, block: *const block_jit.Block, pending: usize, route: []const u8) void {
        return process_impl_block_jit.logTranslatedEntryViolation(self, block, pending, route);
    }

    fn executeBlockJit(self: *ElfState, jit: *BlockJitState, first: *block_jit.Block, first_slot: usize) bool {
        return process_impl_block_jit.executeBlockJit(self, jit, first, first_slot);
    }

    /// Where a cross-check following the interpreter continues in `block`
    /// once RIP is `rip`, `cursor` being the instruction after the one just
    /// run: `cursor` itself when RIP is there; when that instruction is one
    /// of the block's internal edges (`internal_sources`), the instruction
    /// its taken edge jumps to, found by the translator's own search - the
    /// first later instruction at RIP; otherwise null, because RIP has left
    /// the block, as the translation does.
    fn blockJitResumeIndex(block: *const block_jit.Block, cursor: u32, rip: u64) ?u32 {
        return process_impl_block_jit.blockJitResumeIndex(block, cursor, rip);
    }

    /// Run a register-only block through the interpreter and through its
    /// translation from the same register file, and compare every register,
    /// RIP and the flags. On agreement the block is trusted from then on; on
    /// disagreement the interpreter's result stands, the block is dropped,
    /// its address is never compiled again, and the run says so.
    fn verifyBlockJit(self: *ElfState, jit: *BlockJitState, block: *block_jit.Block, slot_index: usize) bool {
        return process_impl_block_jit.verifyBlockJit(self, jit, block, slot_index);
    }

    /// The journal bound to the executing context, while one is.
    inline fn activeVerifyJournal(self: anytype) ?*block_verify.Journal {
        return process_impl_block_jit.activeVerifyJournal(self);
    }

    /// Whether every instruction of `block` reaches memory only through the
    /// paths the journal models, and leaves no state the check does not
    /// restore.
    fn memoryBlockJournalSafe(block: *const block_jit.Block) bool {
        return process_impl_block_jit.memoryBlockJournalSafe(block);
    }

    /// Whether interpreting `block` would run a hook or shim: it starts at a
    /// hooked address or branches or calls into one. The interpreter's jump
    /// and call arms run the condition-variable shim - a real wait or notify
    /// - and a cross-check's interpreted pass is discarded, so it would run
    /// the shim once for nothing and the translation would run it again. On
    /// 2026-10-02 that hit `std::condition_variable::wait` and
    /// `pthread_cond_timedwait` on the Vulkan Pipelines and Shader Storage
    /// Writer threads, the workers Xenia builds its GPU pipelines on.
    fn blockVerifyReachesHook(self: *const ElfState, block: *const block_jit.Block) bool {
        return process_impl_block_jit.blockVerifyReachesHook(self, block);
    }

    /// `verifyBlockJit` for a block that reaches memory: the interpreter
    /// runs it first against a write journal, so nothing it stores reaches
    /// memory, then the translation runs for real, and its registers, flags,
    /// vector registers and the final bytes at every address the interpreter
    /// stored are compared. True when the block was executed here; false
    /// when it could not be checked (it is then trusted and runs as usual).
    pub fn verifyMemoryBlockJit(self: *ElfState, jit: *BlockJitState, block: *block_jit.Block, slot_index: usize) bool {
        return process_impl_block_jit.verifyMemoryBlockJit(self, jit, block, slot_index);
    }

    fn logMemoryBlockMismatch(self: *ElfState, block: *const block_jit.Block, what: []const u8, address: u64, interpreter: u64, translated: u64, interpreted: u32, completed: u32, stored: usize, count: u64) void {
        return process_impl_block_jit.logMemoryBlockMismatch(self, block, what, address, interpreter, translated, interpreted, completed, stored, count);
    }

    /// The translator's entry from `step`: run the block for the current RIP
    /// when there is a valid one, otherwise count the address towards
    /// compilation. Null means "interpret this instruction".
    fn runBlockJit(self: *ElfState) ?bool {
        return process_impl_block_jit.runBlockJit(self);
    }

    fn blockJitSetFull(jit: *const BlockJitState, base: usize) bool {
        return process_impl_block_jit.blockJitSetFull(jit, base);
    }

    fn reportBlockJit(self: *ElfState) void {
        return process_impl_block_jit.reportBlockJit(self);
    }

    /// The worker threads' own translators, summed: whether the title's
    /// threads - not only the process owner - are running native code.
    fn reportParallelWorkerBlockJits(self: *ElfState) void {
        return process_impl_block_jit.reportParallelWorkerBlockJits(self);
    }

    /// Each busy worker's translator on its own line: how big its table
    /// grew, how hard it was pressed, and why its interpreted steps were
    /// interpreted, with where they land. The totals above cannot say which
    /// thread is still on the interpreter; on 2026-09-30 it was the title's
    /// main thread, at 84% of its wall time in Rosette.
    fn reportParallelWorkerBlockJitThreads(self: *ElfState) void {
        return process_impl_block_jit.reportParallelWorkerBlockJitThreads(self);
    }

    /// The mnemonic of the instruction at `address`, for a report naming why
    /// the translator refused a region.
    fn describeGuestOpAt(self: *ElfState, address: u64, buffer: []u8) []const u8 {
        return process_impl_block_jit.describeGuestOpAt(self, address, buffer);
    }

    fn reportBlockJitTlbRefusalReasons(self: *ElfState, label: []const u8, stats: tlb_diagnostics.RefusalStats) void {
        return process_impl_block_jit.reportBlockJitTlbRefusalReasons(self, label, stats);
    }

    fn reportParallelTlbInvalidationWork(self: *const ElfState) void {
        return process_impl_block_jit.reportParallelTlbInvalidationWork(self);
    }

    /// The workers' interpreted instructions, summed by op. In a parallel
    /// run the title's threads are workers, so this - not the owner's list -
    /// is the template work that decides the frame rate.
    fn reportParallelWorkerFallbackOps(self: *ElfState) void {
        return process_impl_block_jit.reportParallelWorkerFallbackOps(self);
    }

    /// The interpreter's share of the translated lane, by instruction: the
    /// twelve most frequent fallbacks and their share of all fallback
    /// calls. This is the list of templates the next version should add.
    /// The fallback counters one report reads: one translator's, or the
    /// workers' summed.
    const BlockJitFallbackView = struct {
        /// "" for the owner's translator, "WORKER " for the workers' sum.
        label: []const u8,
        calls: u64,
        ops: *const [ElfState.op_value_limit]u64,
        samples: *const [ElfState.op_value_limit]u64,
        nanos: *const [ElfState.op_value_limit]u64,
        reasons: *const [@typeInfo(block_jit.FallbackReason).@"enum".fields.len]u64,
    };

    fn reportBlockJitFallbackOps(self: *ElfState, jit: *const BlockJitState) void {
        return process_impl_block_jit.reportBlockJitFallbackOps(self, jit);
    }

    /// The interpreter's share of a translated lane, by instruction: the
    /// twelve most frequent fallbacks and their share of all fallback calls.
    /// This is the list of templates the next version should add.
    fn reportBlockJitFallbackView(view: BlockJitFallbackView) void {
        return process_impl_block_jit.reportBlockJitFallbackView(view);
    }

    /// Where the interpreted transfers went. An import has to be
    /// interpreted; a hooked target is interpreted by design; a plain one is
    /// a template that declined for a reason its site did not need.
    fn reportBlockJitTransferFallbacks(self: *ElfState, jit: *const BlockJitState) void {
        return process_impl_block_jit.reportBlockJitTransferFallbacks(self, jit);
    }

    fn reportBlockJitCallRefusals(self: *ElfState) void {
        return process_impl_block_jit.reportBlockJitCallRefusals(self);
    }

    fn reportBlockJitTransferFallbackSummary(
        self: *ElfState,
        label: []const u8,
        imports: u64,
        hooked: u64,
        plain: u64,
        targets: *const [BlockJitState.transfer_target_slots]BlockJitState.TransferTarget,
        target_overflow: u64,
    ) void {
        return process_impl_block_jit.reportBlockJitTransferFallbackSummary(self, label, imports, hooked, plain, targets, target_overflow);
    }

    pub fn step(self: *ElfState) bool {
        return process_impl_block_jit.step(self);
    }

    pub fn run(self: *ElfState) void {
        return process_impl_run_reporting.run(self);
    }

    fn sampleWindowsProgress(self: *const ElfState) WindowsProgressSample {
        return process_impl_run_reporting.sampleWindowsProgress(self);
    }

    fn countWindowsWorkers(self: *const ElfState, status: WindowsGuestThreadStatus) usize {
        return process_impl_run_reporting.countWindowsWorkers(self, status);
    }

    /// One bounded, actionable block describing a run that has stopped making
    /// observable progress.  Emitted at most once per escalation step of a
    /// stall episode, and never at all while any axis is still moving.
    fn reportWindowsStall(self: *ElfState, sample: WindowsProgressSample) void {
        return process_impl_run_reporting.reportWindowsStall(self, sample);
    }

    /// A guest can run its message loop briskly -- so no progress axis looks
    /// frozen -- while every frame it paints stops before the screen.  That is
    /// invisible to the freeze detector by construction, so it gets its own
    /// check: Rosetta has handed the guest N paints and the guest has
    /// presented none of them.
    ///
    /// The claim is only made once there are enough paints for it to mean
    /// something, and then only on an escalating schedule, so a startup that
    /// legitimately paints nothing yet stays silent.
    pub fn checkWindowsPaintReachesScreen(self: *ElfState) void {
        return process_impl_run_reporting.checkWindowsPaintReachesScreen(self);
    }

    /// Sample the progress axes and, when every one of them has been frozen
    /// for long enough, report it once and unblock any starved worker.
    pub fn checkWindowsProgress(self: *ElfState) void {
        return process_impl_run_reporting.checkWindowsProgress(self);
    }

    /// Return the work charged to one invocation of `runWithLimit`.
    ///
    /// `runWithLimit` may be called more than once on a state by tests and by
    /// diagnostic harnesses. The worker counter is state-lifetime cumulative,
    /// while the owner's local `steps` counter starts at zero for each run, so
    /// a per-run deadline must subtract the worker baseline captured at entry.
    pub fn runBudgetSteps(owner_steps: u64, worker_steps_at_start: u64, worker_steps: u64) u64 {
        return process_impl_run_reporting.runBudgetSteps(owner_steps, worker_steps_at_start, worker_steps);
    }

    /// Every guest instruction this run has interpreted, owner and workers.
    ///
    /// `runWithLimit` counts its own loop iterations, and every worker step
    /// runs inside a `serviceWindowsGuestThreads` call nested in one of them.
    /// So the checkpoint's `steps=` is the *owner's* share, not the run's
    /// work, and once the cooperative scheduler starts giving workers most of
    /// the budget the two diverge by an order of magnitude.
    pub fn totalInterpretedSteps(self: *const ElfState) u64 {
        return process_impl_run_reporting.totalInterpretedSteps(self);
    }

    /// What the run bought for its wall clock, and where it went.
    ///
    /// Every other counter in the checkpoint measures the guest. None of them
    /// can tell "the title needs more instructions than this run executed"
    /// from "the title is stuck", and those are the two readings a black
    /// window is always between. This line is the denominator.
    ///
    /// It reports the *total* rate, because the first version of it reported
    /// the owner loop's rate and nothing else. On the 2026-09-12 run that
    /// read as a fall from 2.5M to 140K steps/s and looked like a runaway
    /// table; the real rate was a steady 1.5M instructions/s, and what had
    /// actually changed was that the workers went from ~0% of the budget to
    /// ~90% of it. A denominator that measures one thread of a cooperative
    /// scheduler is not a denominator.
    fn logStepBudget(self: *ElfState, steps: u64) void {
        return process_impl_run_reporting.logStepBudget(self, steps);
    }

    fn printStepBudget(self: *ElfState, steps: u64, include_jit: bool) void {
        return process_impl_run_reporting.printStepBudget(self, steps, include_jit);
    }

    fn reportXeniaClock(self: *ElfState, now: u64) void {
        return process_impl_run_reporting.reportXeniaClock(self, now);
    }

    /// The run's pulse, taken on every instruction executed, not the owner's.
    ///
    /// Every periodic report was keyed to the owner's step counter. Once a
    /// title runs, the owner is mostly the scheduler serving workers: on
    /// 2026-09-14 it advanced 24M steps in the last seven minutes while the
    /// workers ran 6.8B, so the log fell silent at owner step 200M and a run
    /// executing sixteen million instructions a second read as one that had
    /// stopped.
    fn logRunHeartbeat(self: *ElfState, steps: u64) void {
        return process_impl_run_reporting.logRunHeartbeat(self, steps);
    }

    /// Start the wall-time sampler on the calling thread - the one host
    /// thread every guest thread of a PE run executes on. See
    /// `host_profile.zig`. Sampling suspends the owner and each registered
    /// worker to read host PCs, so it is opt-in: set `ROSETTE_HOST_PROFILE=1`
    /// for a diagnostic profile. `ROSETTE_HOST_PROFILE_US` sets the interval
    /// (default 1000).
    pub fn startHostProfile(self: *ElfState) void {
        return process_impl_run_reporting.startHostProfile(self);
    }

    pub fn beginHostProfileSampling(self: *ElfState) void {
        return process_impl_run_reporting.beginHostProfileSampling(self);
    }

    /// Where the emulation thread's wall time went, from the sampler.
    ///
    /// Three views, all shares of the same samples. The owner split says how
    /// much was translated code (the title's, from Xenia's code cache, or
    /// Xenia's own, from the image), Rosette's own functions, the Vulkan
    /// driver, Metal, or the system - the last includes every wait the
    /// thread blocked in. The host ranking names Rosette and library
    /// functions; the guest ranking names what the translated samples were
    /// executing, by function for Xenia's code and by block for the title's.
    pub fn reportHostProfile(self: *ElfState) void {
        return process_impl_run_reporting.reportHostProfile(self);
    }

    /// Correlate recent VdSwap intervals with per-thread guest instruction
    /// deltas, host-PC samples, and keyboard/controller activity. Sampling is
    /// opt-in because it suspends threads; normal performance runs do not
    /// populate this ledger.
    fn reportFrameHostAttribution(self: *ElfState) void {
        return process_impl_run_reporting.reportFrameHostAttribution(self);
    }

    fn reportFrameHostThread(
        self: *ElfState,
        record: *const frame_attribution.Record,
        slot: usize,
        name: []const u8,
        role: []const u8,
        guest_instructions: u64,
        own_image: []const u8,
    ) void {
        return process_impl_run_reporting.reportFrameHostThread(self, record, slot, name, role, guest_instructions, own_image);
    }

    fn frameHostSampleCategory(self: *ElfState, slot: usize, pc: u64, own_image: []const u8) FrameHostSampleCategory {
        return process_impl_run_reporting.frameHostSampleCategory(self, slot, pc, own_image);
    }

    /// Attribute one sampled thread's program counters: the owner split,
    /// then the host and guest rankings (`ranked_lines` each).
    fn reportHostProfileSamples(
        self: *ElfState,
        label: []const u8,
        whose: []const u8,
        entries: []const host_profile.Entry,
        summary: host_profile.Totals,
        translator: ?*BlockJitState,
        ranked_lines: usize,
    ) void {
        return process_impl_run_reporting.reportHostProfileSamples(self, label, whose, entries, summary, translator, ranked_lines);
    }

    /// The translated blocks a thread's samples landed in most, with what
    /// each one is made of. A guest symbol says where the time went; this
    /// says what the translator turned it into - how many ARM64 words per
    /// x86 instruction, which instructions touch memory (each one a TLB
    /// probe) and which went back to the interpreter - which is what the
    /// next change to the translator has to be chosen from.
    fn reportHostProfileHotBlocks(self: *ElfState, label: []const u8, blocks: *const std.AutoHashMapUnmanaged(usize, u64), counted: u64) void {
        return process_impl_run_reporting.reportHostProfileHotBlocks(self, label, blocks, counted);
    }

    /// The denominator and the scheduler's health at exit. The periodic
    /// copies stop at the last checkpoint, and a run ended from its window
    /// never reaches another one.
    pub fn reportRunThroughput(self: *ElfState) void {
        return process_impl_run_reporting.reportRunThroughput(self);
    }

    /// The boundaries that decide whether a worker's turn is work or waste,
    /// and the tables that bound how many threads and kernel objects a title
    /// can hold.
    fn logGuestSchedulingHealth(self: *const ElfState) void {
        return process_impl_run_reporting.logGuestSchedulingHealth(self);
    }

    fn logGraphicsProgress(self: *ElfState, steps: u64) void {
        return process_impl_run_reporting.logGraphicsProgress(self, steps);
    }

    fn logGraphicsStop(self: *ElfState) void {
        return process_impl_run_reporting.logGraphicsStop(self);
    }

    /// Open the host output device for a guest wave format.
    ///
    /// A refusal is not an error the caller escalates: the guest's wave device
    /// stays open on the clocked null sink and the audio report says which
    /// sink is in use. Claiming the open failed would stop a guest that can
    /// run perfectly well without a speaker.
    pub fn openWindowsHostAudio(self: *ElfState, sample_rate: u32, channels: u32, bits_per_sample: u32, is_float: bool) bool {
        return process_impl_windows_audio.openWindowsHostAudio(self, sample_rate, channels, bits_per_sample, is_float);
    }

    /// Copy one guest wave buffer into the host device.
    pub fn submitWindowsHostAudio(self: *ElfState, data: u64, length: u32) void {
        return process_impl_windows_audio.submitWindowsHostAudio(self, data, length);
    }

    pub fn closeWindowsHostAudio(self: *ElfState) void {
        return process_impl_windows_audio.closeWindowsHostAudio(self);
    }

    /// What is consuming the guest's frames, proved rather than assumed.
    ///
    /// A device that was opened and has never served a callback is not a host
    /// device: from every counter the guest can see it is indistinguishable
    /// from the null sink, and only the callback count separates them.
    pub fn windowsAudioSinkLabel(self: *const ElfState) []const u8 {
        return process_impl_windows_audio.windowsAudioSinkLabel(self);
    }

    /// The ordered set of things that must happen before a guest frame is
    /// audible, and which of them this run reached.
    ///
    /// Silence is the least legible failure in the runtime: every stage
    /// produces silence when it breaks, and silence when the stage above it
    /// breaks, so the symptom carries no information. This is the same
    /// earliest-broken-stage rule `lib/audio` applies to the modelled mixer,
    /// applied to the path a Windows guest actually takes.
    fn audioChainStages(self: *const ElfState) [AUDIO_STAGE_COUNT]ChainStage {
        return process_impl_windows_audio.audioChainStages(self);
    }

    /// The earliest unmet audio stage, or null when frames reached a device
    /// that consumed them.
    pub fn audioChainWall(self: *const ElfState) ?ChainStage {
        return process_impl_windows_audio.audioChainWall(self);
    }

    pub fn reportAudioChain(self: *const ElfState) void {
        return process_impl_windows_audio.reportAudioChain(self);
    }

    fn logWindowsAudioStop(self: *const ElfState) void {
        return process_impl_windows_audio.logWindowsAudioStop(self);
    }

    /// Execute with a caller-selected bound.  The ELF command keeps its
    /// historical limit, while PE32+ launch sessions need a visible and
    /// bounded policy of their own so a Windows image cannot silently run
    /// forever during bring-up.
    pub fn runWithLimit(self: *ElfState, max_steps: u64) void {
        return process_impl_execution.runWithLimit(self, max_steps);
    }

    /// Where the current guest context is, for an event record.
    fn eventSite(self: *const ElfState, return_address: u64) terminal_event.Site {
        return process_impl_execution.eventSite(self, return_address);
    }

    /// Capture the faulting worker's context at UD2, before the owner context
    /// takes over final reporting. This matters in parallel mode: the final
    /// process snapshot may be on the UI thread even though a guest worker's
    /// invalid instruction caused the stop.
    fn reportGuestUd2(self: *ElfState) void {
        return process_impl_execution.reportGuestUd2(self);
    }

    /// Record what ended the run, at the site that decided it. The first
    /// call of a run wins; see `diagnostics/terminal_event.zig`.
    pub fn recordTerminalEvent(self: *ElfState, kind: terminal_event.Kind, label: []const u8, return_address: u64, comptime format: []const u8, args: anytype) void {
        return process_impl_execution.recordTerminalEvent(self, kind, label, return_address, format, args);
    }

    /// Remember a notable event for the exit report's causal context.
    pub fn noteNotableEvent(self: *ElfState, kind: terminal_event.NotableKind, return_address: u64, comptime format: []const u8, args: anytype) void {
        return process_impl_execution.noteNotableEvent(self, kind, return_address, format, args);
    }

    fn lastNotableEventText(self: *const ElfState, buffer: []u8) []const u8 {
        return process_impl_execution.lastNotableEventText(self, buffer);
    }

    /// The Win32 layer reached a noreturn runtime call that ends the run:
    /// abort, std::terminate, a pure virtual call, or a call it cannot model.
    pub fn recordWindowsFatalRuntimeCall(self: *ElfState, name: []const u8, return_address: u64) void {
        return process_impl_execution.recordWindowsFatalRuntimeCall(self, name, return_address);
    }

    /// Whether `address` is guest code: an executable image section or a
    /// mapping Rosette serves code from.
    fn guestAddressIsCode(self: *const ElfState, address: u64) bool {
        return process_impl_execution.guestAddressIsCode(self, address);
    }

    /// A short guest call chain for a log line, nearest frame first:
    /// `0x1411dec3c (operator new+0x1c) <- 0x140...`. See
    /// `diagnostics/guest_backtrace.zig` for what makes a frame.
    fn formatGuestBacktrace(self: *const ElfState, rsp: u64, max_frames: usize, buffer: []u8) []const u8 {
        return process_impl_execution.formatGuestBacktrace(self, rsp, max_frames, buffer);
    }

    /// What `diagnostics/exit_context.zig` reads the stopped state through.
    const ExitContextSource = struct {
        state: *const ElfState,

        pub fn describe(self: ExitContextSource, address: u64, buffer: []u8) []const u8 {
            return self.state.describeGuestAddressOrUnnamed(address, buffer);
        }

        pub fn threadLabel(self: ExitContextSource, slot: ?u16) []const u8 {
            const index = slot orelse return self.state.guestThreadLabel(0);
            if (index >= self.state.windows_guest_threads.len) return "<unknown thread>";
            return self.state.guestThreadLabel(@intCast(@min(@as(usize, index) + 1, 255)));
        }

        pub fn isCode(self: ExitContextSource, address: u64) bool {
            return self.state.guestAddressIsCode(address);
        }

        pub fn bytesBefore(self: ExitContextSource, address: u64, storage: *[8]u8) ?[]const u8 {
            if (address < 8) return null;
            var buffer: [16]u8 = undefined;
            const bytes = self.state.guestInstructionBytes(address - 8, &buffer);
            if (bytes.len < 8) return null;
            @memcpy(storage, bytes[0..8]);
            return storage[0..8];
        }

        pub fn stackWord(self: ExitContextSource, address: u64) ?u64 {
            if (self.state.addrToOffset(address) == null) return null;
            return self.state.read64(address);
        }
    };

    /// The guest memory model's exit record: how much the store buffers
    /// carried, why they drained, and the invariant translated code relies
    /// on. Read `translated_entry_violations` first; it must be zero.
    fn reportGuestStoreBuffers(self: *const ElfState) void {
        return process_impl_execution.reportGuestStoreBuffers(self);
    }

    fn logExitDiagnostics(self: *const ElfState) void {
        return process_impl_execution.logExitDiagnostics(self);
    }

    fn logRegs(self: *ElfState) void {
        return process_impl_execution.logRegs(self);
    }

    pub fn regVal(self: *const ElfState, id: RegId, size: Size) u64 {
        return process_impl_execution.regVal(self, id, size);
    }

    pub fn setReg(self: *ElfState, id: RegId, size: Size, val: u64) void {
        return process_impl_execution.setReg(self, id, size, val);
    }

    fn decodedRegVal(self: *const ElfState, id: RegId, high8: bool, size: Size) u64 {
        return process_impl_execution.decodedRegVal(self, id, high8, size);
    }

    fn setDecodedReg(self: *ElfState, id: RegId, high8: bool, size: Size, val: u64) void {
        return process_impl_execution.setDecodedReg(self, id, high8, size, val);
    }

    /// Record an interpreted access inside the null page and stop the run.
    ///
    /// Windows never maps the first 64 KiB of a process, so the real OS
    /// raises EXCEPTION_ACCESS_VIOLATION here and Xenia's vectored handler
    /// claims only its MMIO pages. Rosette answered these with zero, which
    /// let a null vtable load succeed and moved the failure one instruction
    /// on, to an indirect call through 0x20 that no longer said which
    /// pointer was null or who should have stored it.
    fn noteGuestNullPageAccess(self: *ElfState, address: u64, size: Size, is_write: bool) void {
        return process_impl_execution.noteGuestNullPageAccess(self, address, size, is_write);
    }

    fn reportGuestNullPageAccess(self: *const ElfState, address: u64, size: Size, is_write: bool, occurrence: u64) void {
        return process_impl_execution.reportGuestNullPageAccess(self, address, size, is_write, occurrence);
    }

    fn reportXeniaEventCall(self: *const ElfState, thread: *const WindowsGuestThread) void {
        return process_impl_execution.reportXeniaEventCall(self, thread);
    }

    /// Compare the address passed to the memory helper with the EA rebuilt
    /// from the currently saved guest registers. This is especially useful
    /// for block-JIT helper calls: cached guest registers can be newer than
    /// the register file, so a mismatch is evidence to inspect the translated
    /// operands, not proof that the saved register values were live.
    fn reportGuestNullPageAddressCheck(self: *const ElfState, supplied_address: u64) void {
        return process_impl_execution.reportGuestNullPageAddressCheck(self, supplied_address);
    }

    /// For a faulting operand based on a register, look backward for the
    /// immediately preceding MOV that filled that register. This recovers
    /// common null-vtable chains such as `mov rcx,[this+offset]; mov rax,[rcx]`
    /// without treating stale post-block registers as the executed state.
    fn reportNullPagePrecedingLoad(self: *const ElfState, instruction_rip: u64, decoded: DecodedInsn, helper_address: u64) void {
        return process_impl_execution.reportNullPagePrecedingLoad(self, instruction_rip, decoded, helper_address);
    }

    pub fn readMemVal(self: *ElfState, addr: u64, size: Size) u64 {
        return process_impl_execution.readMemVal(self, addr, size);
    }

    /// Get a writable host view for a locked scalar operation without
    /// publishing a code-generation change until the operation actually
    /// stores. Page-watch paths deliberately stay on the existing fault-aware
    /// interpreter route; the host-parallel guest scheduler remains disabled
    /// until it can rendezvous all executors for those operations.
    pub fn atomicMemoryOperand(self: *ElfState, address: u64, size: Size) ?[]u8 {
        return process_impl_execution.atomicMemoryOperand(self, address, size);
    }

    /// A failed direct atomic is uncommon (protected memory, an unavailable
    /// mapping, or a host pointer that cannot support the requested width).
    /// In parallel guest mode, keep the legacy fault-aware operation but
    /// rendezvous every executor around its read/modify/write sequence. This
    /// is the slow path that makes the ordinary helpers an atomic fallback,
    /// rather than allowing a LOCK instruction to degrade into a racy pair
    /// of guest loads and stores.
    fn beginSerializedAtomicFallback(self: *ElfState) ?GuestExecutionGate.MutationGuard {
        return process_impl_execution.beginSerializedAtomicFallback(self);
    }

    fn fallbackAtomicUpdate(
        self: *ElfState,
        address: u64,
        size: Size,
        operation: tso_memory.UpdateOp,
        operand: u64,
        carry_in: bool,
    ) tso_memory.UpdateResult {
        return process_impl_execution.fallbackAtomicUpdate(self, address, size, operation, operand, carry_in);
    }

    fn noteAtomicMemoryWrite(self: *ElfState, address: u64, size: Size, value: u64) void {
        return process_impl_execution.noteAtomicMemoryWrite(self, address, size, value);
    }

    fn noteAtomicMemoryWrite128(self: *ElfState, address: u64, value_low: u64) void {
        return process_impl_execution.noteAtomicMemoryWrite128(self, address, value_low);
    }

    fn atomicMemoryUpdate(
        self: *ElfState,
        address: u64,
        size: Size,
        operation: tso_memory.UpdateOp,
        operand: u64,
        carry_in: bool,
    ) ?tso_memory.UpdateResult {
        return process_impl_execution.atomicMemoryUpdate(self, address, size, operation, operand, carry_in);
    }

    fn atomicMemoryExchange(self: *ElfState, address: u64, size: Size, value: u64) ?u64 {
        return process_impl_execution.atomicMemoryExchange(self, address, size, value);
    }

    fn atomicMemoryCompareExchange(
        self: *ElfState,
        address: u64,
        size: Size,
        expected: u64,
        desired: u64,
    ) ?tso_memory.CompareExchangeResult {
        return process_impl_execution.atomicMemoryCompareExchange(self, address, size, expected, desired);
    }

    pub fn atomicMemoryCompareExchange128(
        self: *ElfState,
        address: u64,
        expected: u128,
        desired: u128,
    ) ?tso_memory.CompareExchange128Result {
        return process_impl_execution.atomicMemoryCompareExchange128(self, address, expected, desired);
    }

    fn atomicMemoryFetchAdd(self: *ElfState, address: u64, size: Size, value: u64) ?u64 {
        return process_impl_execution.atomicMemoryFetchAdd(self, address, size, value);
    }

    fn invalidAtomicAlignment(self: *ElfState, address: u64, alignment: u8, op: Op) void {
        return process_impl_execution.invalidAtomicAlignment(self, address, alignment, op);
    }

    fn executeCmpxchg8b(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeCmpxchg8b(self, d);
    }

    fn executeCmpxchg16b(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeCmpxchg16b(self, d);
    }

    fn executeAtomicIncDec(self: *ElfState, d: DecodedInsn, is_inc: bool) bool {
        return process_impl_execution.executeAtomicIncDec(self, d, is_inc);
    }

    fn executeAtomicNeg(self: *ElfState, d: DecodedInsn) bool {
        return process_impl_execution.executeAtomicNeg(self, d);
    }

    fn executeAtomicNot(self: *ElfState, d: DecodedInsn) bool {
        return process_impl_execution.executeAtomicNot(self, d);
    }

    pub fn writeMemVal(self: *ElfState, addr: u64, size: Size, val: u64) void {
        return process_impl_execution.writeMemVal(self, addr, size, val);
    }

    fn writeExtendedInt80(destination: []u8, value: i64) void {
        return process_impl_execution.writeExtendedInt80(destination, value);
    }

    /// Encode an IEEE-754 binary64 value in the little-endian x87 80-bit
    /// memory format.  The PE runner does not need host floating-point state
    /// to survive across instructions, so values are converted at the
    /// operation boundary and the guest stack retains the exact ten bytes in
    /// between.
    fn writeExtendedFloat80(destination: []u8, value: f64) void {
        return process_impl_execution.writeExtendedFloat80(destination, value);
    }

    /// Decode the x87 80-bit memory format to the binary64 precision used by
    /// the arithmetic fallback.  This is deliberately separate from the raw
    /// stack accessors: FLD/FSTP m80 use the raw path, while arithmetic and
    /// comparisons need a numerical view of the same value.
    pub fn readExtendedFloat80(source: []const u8) f64 {
        return process_impl_execution.readExtendedFloat80(source);
    }

    fn x87RawFromInt(value: i64) X87Raw {
        return process_impl_execution.x87RawFromInt(value);
    }

    pub fn x87RawFromFloat(value: f64) X87Raw {
        return process_impl_execution.x87RawFromFloat(value);
    }

    fn x87Physical(self: *const ElfState, logical: u3) u3 {
        return process_impl_execution.x87Physical(self, logical);
    }

    fn x87StackFault(self: *ElfState, overflow: bool) void {
        return process_impl_execution.x87StackFault(self, overflow);
    }

    pub fn x87PushRaw(self: *ElfState, value: X87Raw) bool {
        return process_impl_execution.x87PushRaw(self, value);
    }

    pub fn x87GetRaw(self: *ElfState, logical: u3) ?X87Raw {
        return process_impl_execution.x87GetRaw(self, logical);
    }

    pub fn x87SetRaw(self: *ElfState, logical: u3, value: X87Raw) bool {
        return process_impl_execution.x87SetRaw(self, logical, value);
    }

    pub fn x87PopRaw(self: *ElfState) ?X87Raw {
        return process_impl_execution.x87PopRaw(self);
    }

    fn x87StatusWord(self: *const ElfState) u16 {
        return process_impl_execution.x87StatusWord(self);
    }

    fn x87Reset(self: *ElfState) void {
        return process_impl_execution.x87Reset(self);
    }

    fn x87Exchange(self: *ElfState, logical: u3) void {
        return process_impl_execution.x87Exchange(self, logical);
    }

    fn x87Free(self: *ElfState, logical: u3) void {
        return process_impl_execution.x87Free(self, logical);
    }

    fn x87Cos(self: *ElfState) void {
        return process_impl_execution.x87Cos(self);
    }

    fn x87Sin(self: *ElfState) void {
        return process_impl_execution.x87Sin(self);
    }

    fn x87Fchs(self: *ElfState) void {
        return process_impl_execution.x87Fchs(self);
    }

    fn x87Fabs(self: *ElfState) void {
        return process_impl_execution.x87Fabs(self);
    }

    fn x87Test(self: *ElfState) void {
        return process_impl_execution.x87Test(self);
    }

    fn x87CompareStatus(self: *ElfState, lhs: f64, rhs: f64, pop_result: bool) void {
        return process_impl_execution.x87CompareStatus(self, lhs, rhs, pop_result);
    }

    fn x87F2xm1(self: *ElfState) void {
        return process_impl_execution.x87F2xm1(self);
    }

    fn x87Fyl2x(self: *ElfState, add_one: bool) void {
        return process_impl_execution.x87Fyl2x(self, add_one);
    }

    fn x87Fptan(self: *ElfState) void {
        return process_impl_execution.x87Fptan(self);
    }

    fn x87Fpatan(self: *ElfState) void {
        return process_impl_execution.x87Fpatan(self);
    }

    fn x87Fxtract(self: *ElfState) void {
        return process_impl_execution.x87Fxtract(self);
    }

    fn x87PartialRemainder(self: *ElfState, nearest: bool) void {
        return process_impl_execution.x87PartialRemainder(self, nearest);
    }

    fn x87PartialRemainderNearest(self: *ElfState) void {
        return process_impl_execution.x87PartialRemainderNearest(self);
    }

    fn x87PartialRemainderTrunc(self: *ElfState) void {
        return process_impl_execution.x87PartialRemainderTrunc(self);
    }

    fn x87Fsincos(self: *ElfState) void {
        return process_impl_execution.x87Fsincos(self);
    }

    fn x87Frndint(self: *ElfState) void {
        return process_impl_execution.x87Frndint(self);
    }

    fn x87Fscale(self: *ElfState) void {
        return process_impl_execution.x87Fscale(self);
    }

    fn x87Fclex(self: *ElfState) void {
        return process_impl_execution.x87Fclex(self);
    }

    fn x87WriteRawMemory(self: *ElfState, addr: u64, raw: X87Raw) void {
        return process_impl_execution.x87WriteRawMemory(self, addr, raw);
    }

    fn x87Compare(self: *ElfState, source: u3, pop_result: bool) void {
        return process_impl_execution.x87Compare(self, source, pop_result);
    }

    fn x87Divide(numerator: f64, denominator: f64, status: *u16) f64 {
        return process_impl_execution.x87Divide(numerator, denominator, status);
    }

    fn x87MemoryValue(self: *ElfState, d: DecodedInsn, integer: bool) f64 {
        return process_impl_execution.x87MemoryValue(self, d, integer);
    }

    pub fn x87Memory(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.x87Memory(self, d);
    }

    fn x87Binary(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.x87Binary(self, d);
    }

    pub fn readMem128(self: *ElfState, addr: u64) [16]u8 {
        return process_impl_execution.readMem128(self, addr);
    }

    pub fn writeMem128(self: *ElfState, addr: u64, value: [16]u8) void {
        return process_impl_execution.writeMem128(self, addr, value);
    }

    pub fn writeMem128NonTemporal(self: *ElfState, addr: u64, value: [16]u8) void {
        return process_impl_execution.writeMem128NonTemporal(self, addr, value);
    }

    fn writeMem128WithPolicy(self: *ElfState, addr: u64, value: [16]u8, non_temporal: bool) void {
        return process_impl_execution.writeMem128WithPolicy(self, addr, value, non_temporal);
    }

    fn traceGuestVectorWrite(self: *const ElfState, addr: u64, value: [16]u8) void {
        return process_impl_execution.traceGuestVectorWrite(self, addr, value);
    }

    /// Return a raw mutable view of guest memory for a synchronous runtime
    /// path: an import shim or a bridge filling its caller's out-parameters.
    ///
    /// Parallel mode hands out the same view for data. The bytes written
    /// through it are ordinary stores by the executing guest thread, made in
    /// its program order after `storeFence` drained its queue, and published
    /// to the other executors by that thread's next ordered guest store (an
    /// STLR on the direct route, a stripe release on the helper route). That
    /// is the x86-TSO contract of a Windows API writing a caller's buffer; a
    /// peer reading the buffer without synchronizing races on hardware too.
    ///
    /// A range that may hold fetched instructions is still refused in
    /// parallel mode. Its generation has to move after its bytes do, or a
    /// peer could translate the old bytes under the new generation and keep
    /// running them. Code writers use `copyToGuest`, `fillGuestMemory` or
    /// scalar stores, which end in `finishGuestMemoryTsoWrite`.
    ///
    /// On 2026-09-30 every parallel view was refused while 219 runtime
    /// callers still asked for one. `vkGetPhysicalDeviceProperties` and
    /// `vkGetPhysicalDeviceFeatures` then wrote nothing: Xenia read an empty
    /// adapter name and no independentBlend, rejected the Apple GPU, and its
    /// GPU thread faulted on the null device in
    /// `VulkanCommandProcessor::SetupContext`. The same refusal answered
    /// SHGetKnownFolderPath with E_INVALIDARG (no fonts directory) and
    /// refused every registry open.
    pub fn guestMemory(self: *ElfState, addr: u64, count: u64) ?[]u8 {
        return process_impl_execution.guestMemory(self, addr, count);
    }

    /// Whether a guest range may hold instructions an executor fetched: an
    /// executable PE section, or a mapping some executor has decoded from.
    /// The write TLB refuses admission on the same two predicates.
    fn guestRangeMayHoldFetchedCode(self: *const ElfState, addr: u64, count: u64) bool {
        return process_impl_execution.guestRangeMayHoldFetchedCode(self, addr, count);
    }

    fn noteParallelCodeBorrowRefused(self: *ElfState, addr: u64, count: u64) void {
        return process_impl_execution.noteParallelCodeBorrowRefused(self, addr, count);
    }

    /// Resolve a guest write target for an operation that will write through
    /// the TSO access API rather than mutate this slice directly. Unlike
    /// `guestMemory`, this does not drain the active store buffer. Call
    /// `finishGuestMemoryTsoWrite` after the ordered write so executable-code
    /// generations advance only after the written bytes are visible.
    fn guestMemoryTsoWriteTarget(self: *ElfState, addr: u64, count: u64) ?[]u8 {
        return process_impl_execution.guestMemoryTsoWriteTarget(self, addr, count);
    }

    /// Complete a TSO-aware bulk write. Code-generation helpers drain the
    /// active queue before publishing a new generation when the destination
    /// can contain executable bytes; ordinary data writes stay buffered.
    fn finishGuestMemoryTsoWrite(self: *ElfState, addr: u64, count: u64) void {
        return process_impl_execution.finishGuestMemoryTsoWrite(self, addr, count);
    }

    /// Copy a byte sequence into guest memory through the executor's TSO
    /// route. Ordinary RAM preserves the current context's store forwarding;
    /// device-backed and fault-routed ranges drain that queue and publish
    /// synchronously. Executable-code generations move after the bytes are
    /// visible, never before.
    pub fn copyToGuest(self: *ElfState, addr: u64, source: []const u8) bool {
        return process_impl_execution.copyToGuest(self, addr, source);
    }

    /// Copy between guest addresses without exposing mutable guest slices to
    /// parallel callers. This is the CRT memcpy/memmove route: mapping checks,
    /// alias-aware overlap direction, device/fault boundaries, TSO
    /// coordination, and executable-write generations all stay in one place.
    pub fn copyGuestRange(self: *ElfState, destination_address: u64, source_address: u64, count: u64) bool {
        return process_impl_execution.copyGuestRange(self, destination_address, source_address, count);
    }

    /// Fill guest memory with ordered byte/word stores. This keeps runtime
    /// zero-initialization on the same TSO path as ordinary guest writes.
    pub fn fillGuestMemory(self: *ElfState, addr: u64, count: u64, byte: u8) bool {
        return process_impl_execution.fillGuestMemory(self, addr, count, byte);
    }

    /// Snapshot guest bytes into executor-owned storage. In coordinated mode
    /// this works even for a diagnostic caller outside the guest worker's
    /// thread-local access scope. Unlike a borrowed raw view, this path can
    /// forward the current executor's queued stores without publishing them.
    pub fn copyFromGuest(self: *const ElfState, destination: []u8, addr: u64) bool {
        return process_impl_execution.copyFromGuest(self, destination, addr);
    }

    /// Direct guest-memory snapshots leave the current executor's scalar
    /// store buffer, if any. Outside an executor scope, publish this process's
    /// queues before returning a borrowed host slice so callers observe the
    /// same bytes as guest loads.
    fn flushGuestMemorySnapshotStores(self: *const ElfState) void {
        return process_impl_execution.flushGuestMemorySnapshotStores(self);
    }

    /// Return a borrowed view into guest backing. In parallel mode, use
    /// `copyFromGuest` before parsing or retaining multi-byte contents: this
    /// slice has no lifetime-long read lock and a peer executor can update it
    /// after this function returns. Scalar `read*` helpers remain the right
    /// choice for one value at a time.
    pub fn guestMemoryConst(self: *const ElfState, addr: u64, count: u64) ?[]const u8 {
        return process_impl_execution.guestMemoryConst(self, addr, count);
    }

    /// Resolve a bounded guest-memory source without publishing the active
    /// store buffer. Snapshot callers must copy through `snapshotGuestBacking`
    /// so this executor's buffered bytes are forwarded into owned storage.
    fn guestMemorySourceConst(self: *const ElfState, addr: u64, count: u64) ?[]const u8 {
        return process_impl_execution.guestMemorySourceConst(self, addr, count);
    }

    /// The readable bytes from `addr` to `maximum` or to the end of the
    /// region that holds it, whichever comes first.
    ///
    /// A C string's length is not known before it is read, so a fixed-size
    /// `guestMemoryConst` cannot fetch one; this is the region-aware version
    /// the C runtime's string imports need.
    pub fn guestMemoryTailConst(self: *const ElfState, addr: u64, maximum: usize) ?[]const u8 {
        return process_impl_execution.guestMemoryTailConst(self, addr, maximum);
    }

    /// Resolve a tail view without publishing the active executor's store
    /// buffer. Callers that need contents must immediately snapshot the bytes
    /// into their own storage before parsing them.
    fn guestMemorySourceTailConst(self: *const ElfState, addr: u64, maximum: usize) ?[]const u8 {
        return process_impl_execution.guestMemorySourceTailConst(self, addr, maximum);
    }

    /// A NUL-terminated string anywhere Rosette serves guest memory.
    pub fn guestCStringConst(self: *const ElfState, addr: u64, maximum: usize) ?[]const u8 {
        return process_impl_execution.guestCStringConst(self, addr, maximum);
    }

    /// Copy a bounded guest C string into executor-owned storage. Runtime
    /// diagnostics and bridges use this instead of returning a borrowed guest
    /// slice that could race a peer guest store during parallel execution.
    pub fn copyGuestCString(self: *const ElfState, addr: u64, maximum: usize, destination: []u8) ?usize {
        return process_impl_execution.copyGuestCString(self, addr, maximum, destination);
    }

    pub fn writeHostFd(self: *ElfState, fd: u64, data: []const u8) u64 {
        return process_impl_execution.writeHostFd(self, fd, data);
    }

    pub fn traceGuestIo(self: *const ElfState, operation: []const u8, fd: u64, addr: u64, count: u64, result: u64) void {
        return process_impl_execution.traceGuestIo(self, operation, fd, addr, count, result);
    }

    fn traceSyscall(self: *const ElfState, comptime fmt: []const u8, args: anytype) void {
        return process_impl_execution.traceSyscall(self, fmt, args);
    }

    fn traceOpenResult(self: *const ElfState, path: []const u8, flags_raw: u64, mode_raw: u64, result: u64) void {
        return process_impl_execution.traceOpenResult(self, path, flags_raw, mode_raw, result);
    }

    fn traceCreatResult(self: *const ElfState, path: []const u8, mode_raw: u64, result: u64) void {
        return process_impl_execution.traceCreatResult(self, path, mode_raw, result);
    }

    fn shouldTraceFd(self: *const ElfState, fd: u64) bool {
        return process_impl_execution.shouldTraceFd(self, fd);
    }

    fn shouldTraceResultFd(self: *const ElfState, result: u64) bool {
        return process_impl_execution.shouldTraceResultFd(self, result);
    }

    fn traceDataPreview(self: *const ElfState, operation: []const u8, fd: u64, data: []const u8, total_length: u64) void {
        return process_impl_execution.traceDataPreview(self, operation, fd, data, total_length);
    }

    fn abiTraceConfig(self: *const ElfState) x64_guest_abi.TraceConfig {
        return process_impl_execution.abiTraceConfig(self);
    }

    fn activeCallStack(self: *ElfState) *x64_guest_abi.CallStack {
        return process_impl_execution.activeCallStack(self);
    }

    pub fn noteGuestCall(self: *ElfState, kind: x64_guest_abi.CallKind, target: u64, return_rip: u64) void {
        return process_impl_execution.noteGuestCall(self, kind, target, return_rip);
    }

    pub fn noteGuestReturn(self: *ElfState, return_rip: u64) void {
        return process_impl_execution.noteGuestReturn(self, return_rip);
    }

    fn setFlagsSub(self: *ElfState, a: u64, b: u64, result: u64, size: Size) void {
        return process_impl_execution.setFlagsSub(self, a, b, result, size);
    }

    fn setFlagsAdd(self: *ElfState, a: u64, b: u64, result: u64, size: Size) void {
        return process_impl_execution.setFlagsAdd(self, a, b, result, size);
    }

    fn setFlagsIncDec(self: *ElfState, input: u64, result: u64, size: Size, is_inc: bool) void {
        return process_impl_execution.setFlagsIncDec(self, input, result, size, is_inc);
    }

    fn setFlagsLogic(self: *ElfState, result: u64, size: Size) void {
        return process_impl_execution.setFlagsLogic(self, result, size);
    }

    fn bmiSource(self: *ElfState, d: DecodedInsn) u64 {
        return process_impl_execution.bmiSource(self, d);
    }

    fn executeBmi(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeBmi(self, d);
    }

    pub fn executeVectorTest(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeVectorTest(self, d);
    }

    fn executeVpshufd(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeVpshufd(self, d);
    }

    fn vpdpbusdBlock(accumulator: [16]u8, unsigned_source: [16]u8, signed_source: [16]u8) [16]u8 {
        return process_impl_execution.vpdpbusdBlock(accumulator, unsigned_source, signed_source);
    }

    fn executeVpdpbusd(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeVpdpbusd(self, d);
    }

    fn executeVexLane128(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeVexLane128(self, d);
    }

    fn executeVexPermute2x128(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeVexPermute2x128(self, d);
    }

    fn executeVphminposuw(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeVphminposuw(self, d);
    }

    fn executeVexInsertElement(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeVexInsertElement(self, d);
    }

    fn executeVexExtractElement(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeVexExtractElement(self, d);
    }

    fn executeVinsertps(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeVinsertps(self, d);
    }

    fn executeVectorSpecial(self: *ElfState, d: DecodedInsn) bool {
        return process_impl_execution.executeVectorSpecial(self, d);
    }

    /// The vector routing chain, in its original order. Returns true when
    /// the instruction was handled (or the run was terminated for an
    /// unimplemented vector form) and false when the op is a legacy
    /// vector transfer that the main switch executes.
    fn executeVectorRouted(self: *ElfState, d: DecodedInsn) bool {
        return process_impl_execution.executeVectorRouted(self, d);
    }

    /// One bit per `Op`, indexed by the enum's integer value.
    const OpBitset = [(op_value_limit + 63) / 64]u64;
    pub const op_value_limit: usize = blk: {
        var limit: usize = 0;
        for (@typeInfo(Op).@"enum".fields) |field| limit = @max(limit, @as(usize, field.value) + 1);
        break :blk limit;
    };

    /// `@tagName` by integer value, for tables indexed like `fallback_ops`;
    /// null where the enum has no member.
    pub const op_names: [op_value_limit]?[]const u8 = blk: {
        @setEvalBranchQuota(200_000);
        var names: [op_value_limit]?[]const u8 = @splat(null);
        for (@typeInfo(Op).@"enum".fields) |field| names[field.value] = field.name;
        break :blk names;
    };

    /// Evaluate a pure predicate over every `Op` once, at compile time, so
    /// the per-instruction question becomes a shift and a mask.
    fn opBitsetFrom(comptime predicate: fn (Op) bool) OpBitset {
        return process_impl_execution.opBitsetFrom(predicate);
    }

    inline fn opBitsetHas(comptime bits: *const OpBitset, op: Op) bool {
        return process_impl_execution.opBitsetHas(bits, op);
    }

    /// The name-based rule, evaluated at compile time only: the mnemonic
    /// starts with `v`, or the op is `pmovmskb`.
    fn vectorOperationByName(op: Op) bool {
        return process_impl_execution.vectorOperationByName(op);
    }

    const vector_operation_bits: OpBitset = opBitsetFrom(vectorOperationByName);
    const evex_handled_bits: OpBitset = opBitsetFrom(evex.handles);

    fn isVectorOperationRuntime(op: Op) bool {
        return process_impl_execution.isVectorOperationRuntime(op);
    }

    fn evexHandles(op: Op) bool {
        return process_impl_execution.evexHandles(op);
    }

    fn isLegacyVectorTransfer(op: Op) bool {
        return process_impl_execution.isLegacyVectorTransfer(op);
    }

    fn cleoVectorFromSource(self: *ElfState, d: DecodedInsn, index: u8, memory: bool, comptime bits: usize) cleo_routing.wide.Wide(bits) {
        return process_impl_execution.cleoVectorFromSource(self, d, index, memory, bits);
    }

    fn writeCleoVector(self: *ElfState, d: DecodedInsn, comptime bits: usize, value: cleo_routing.wide.Wide(bits)) void {
        return process_impl_execution.writeCleoVector(self, d, bits, value);
    }

    fn cleoIsFma(operation: cleo_routing.types.Operation) bool {
        return process_impl_execution.cleoIsFma(operation);
    }

    fn cleoIsUnary(operation: cleo_routing.types.Operation) bool {
        return process_impl_execution.cleoIsUnary(operation);
    }

    fn cleoIsImmediate(operation: cleo_routing.types.Operation) bool {
        return process_impl_execution.cleoIsImmediate(operation);
    }

    fn cleoIsBinary(operation: cleo_routing.types.Operation) bool {
        return process_impl_execution.cleoIsBinary(operation);
    }

    fn executeCleoAtWidth(self: *ElfState, d: DecodedInsn, meta: cleo_routing.types.InstructionMeta, features: cleo_routing.types.FeatureSet, comptime bits: usize) ?cleo_routing.wide.Wide(bits) {
        return process_impl_execution.executeCleoAtWidth(self, d, meta, features, bits);
    }

    fn executeCleoVectorMove(self: *ElfState, d: DecodedInsn) bool {
        return process_impl_execution.executeCleoVectorMove(self, d);
    }

    fn tryExecuteCleo(self: *ElfState, d: DecodedInsn) bool {
        return process_impl_execution.tryExecuteCleo(self, d);
    }

    fn vexArithmeticForOp(op: Op) vector_helpers.VexArithmetic {
        return process_impl_execution.vexArithmeticForOp(op);
    }

    fn vexBitwiseForOp(op: Op) vector_helpers.VexBitwise {
        return process_impl_execution.vexBitwiseForOp(op);
    }

    fn executeVexShufflePd(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeVexShufflePd(self, d);
    }

    /// Execute the VEX floating-point/bitwise subset shared with Mach-O.
    /// Keeping this before the fallback switch is important: the fallback is
    /// intentionally conservative and must never turn an arithmetic vector
    /// instruction into a flags-only operation.
    fn executeSharedVex(self: *ElfState, d: DecodedInsn) bool {
        return process_impl_execution.executeSharedVex(self, d);
    }

    fn executeHighwayRegisterBinary(self: *ElfState, d: DecodedInsn, op: x64_decoder.highway.BinaryOp) void {
        return process_impl_execution.executeHighwayRegisterBinary(self, d, op);
    }

    fn terminateForMemoryAccess(self: *ElfState, d: DecodedInsn, check: x64_decoder.highway.MemoryCheck) void {
        return process_impl_execution.terminateForMemoryAccess(self, d, check);
    }

    fn validateGuestMemoryRange(
        self: *const ElfState,
        address: u64,
        width: x64_decoder.highway.Width,
        access: x64_decoder.highway.MemoryAccess,
        permitted: bool,
    ) x64_decoder.highway.MemoryCheck {
        return process_impl_execution.validateGuestMemoryRange(self, address, width, access, permitted);
    }

    fn executeHighwayMemoryBinary(
        self: *ElfState,
        d: DecodedInsn,
        op: x64_decoder.highway.BinaryOp,
        direction: x64_decoder.highway.MemoryDirection,
    ) void {
        return process_impl_execution.executeHighwayMemoryBinary(self, d, op, direction);
    }

    fn executeHighwayImmediate(self: *ElfState, d: DecodedInsn, op: x64_decoder.highway.BinaryOp, memory: bool, immediate: u64) void {
        return process_impl_execution.executeHighwayImmediate(self, d, op, memory, immediate);
    }

    fn executeAccumulatorImmediate(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeAccumulatorImmediate(self, d);
    }

    fn isAccumulatorImmediate(op: Op) bool {
        return process_impl_execution.isAccumulatorImmediate(op);
    }

    fn setFlag(self: *ElfState, flag: u32, enabled: bool) void {
        return process_impl_execution.setFlag(self, flag, enabled);
    }

    fn executeBitTestRegister(
        self: *ElfState,
        d: DecodedInsn,
        operation: x64_decoder.BitTestOperation,
        immediate_index: bool,
    ) void {
        return process_impl_execution.executeBitTestRegister(self, d, operation, immediate_index);
    }

    fn executeBitTestMemory(
        self: *ElfState,
        d: DecodedInsn,
        operation: x64_decoder.BitTestOperation,
        immediate_index: bool,
    ) void {
        return process_impl_execution.executeBitTestMemory(self, d, operation, immediate_index);
    }

    fn bitWidth(size: Size) u7 {
        return process_impl_execution.bitWidth(size);
    }

    fn maskForSize(size: Size) u64 {
        return process_impl_execution.maskForSize(size);
    }

    fn signBitForSize(size: Size) u64 {
        return process_impl_execution.signBitForSize(size);
    }

    fn signedInteger(value: u64, size: Size) i128 {
        return process_impl_execution.signedInteger(value, size);
    }

    fn imulImmediateSize(op: Op) Size {
        return process_impl_execution.imulImmediateSize(op);
    }

    fn signedImulImmediate(instruction: DecodedInsn) i128 {
        return process_impl_execution.signedImulImmediate(instruction);
    }

    fn writeImulNarrowResult(self: *ElfState, destination: RegId, size: Size, product: i128) void {
        return process_impl_execution.writeImulNarrowResult(self, destination, size, product);
    }

    fn shlCount(self: *ElfState, size: Size) u6 {
        return process_impl_execution.shlCount(self, size);
    }

    fn shlValue(self: *ElfState, input: u64, size: Size, count: u6) u64 {
        return process_impl_execution.shlValue(self, input, size, count);
    }

    fn setFlagsShl(self: *ElfState, input: u64, result: u64, size: Size, count: u6) void {
        return process_impl_execution.setFlagsShl(self, input, result, size, count);
    }

    fn immShiftCount(imm: u64, size: Size) u6 {
        return process_impl_execution.immShiftCount(imm, size);
    }

    fn executeRotate(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeRotate(self, d);
    }

    fn shrValue(self: *ElfState, input: u64, size: Size, count: u6) u64 {
        return process_impl_execution.shrValue(self, input, size, count);
    }

    fn setFlagsShr(self: *ElfState, input: u64, result: u64, size: Size, count: u6) void {
        return process_impl_execution.setFlagsShr(self, input, result, size, count);
    }

    fn sarValue(self: *ElfState, input: u64, size: Size, count: u6) u64 {
        return process_impl_execution.sarValue(self, input, size, count);
    }

    fn setFlagsSar(self: *ElfState, input: u64, result: u64, size: Size, count: u6) void {
        return process_impl_execution.setFlagsSar(self, input, result, size, count);
    }

    pub fn evalCond(rflags: u32, cond: Cond) bool {
        return process_impl_execution.evalCond(rflags, cond);
    }

    fn executeBitScan(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeBitScan(self, d);
    }

    fn stringAddress(self: *const ElfState, index: RegId, address_size: Size, segment: x64_decoder.Segment) u64 {
        return process_impl_execution.stringAddress(self, index, address_size, segment);
    }

    fn executeStringOperation(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.executeStringOperation(self, d);
    }

    fn advanceAfterHandled(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.advanceAfterHandled(self, d);
    }

    fn discoverXeniaRijndaelTarget(self: *const ElfState) ?u64 {
        return process_impl_execution.discoverXeniaRijndaelTarget(self);
    }

    fn discoverXeniaSha1Target(self: *const ElfState) ?u64 {
        return process_impl_execution.discoverXeniaSha1Target(self);
    }

    fn discoverXeniaTabulateTarget(self: *const ElfState) ?u64 {
        return process_impl_execution.discoverXeniaTabulateTarget(self);
    }

    /// Find the Rijndael accelerator's target once. Idempotent; the first
    /// caller is normally `rebuildBlockJitHookFilter`, before any guest call.
    fn resolveXeniaRijndaelTarget(self: *ElfState) void {
        return process_impl_execution.resolveXeniaRijndaelTarget(self);
    }

    fn tryXeniaRijndaelAccelerator(self: *ElfState, target: u64, return_rip: u64) bool {
        return process_impl_execution.tryXeniaRijndaelAccelerator(self, target, return_rip);
    }

    /// Find the SHA1 accelerator's target once. Idempotent; see
    /// `resolveXeniaRijndaelTarget`.
    fn resolveXeniaSha1Target(self: *ElfState) void {
        return process_impl_execution.resolveXeniaSha1Target(self);
    }

    fn tryXeniaSha1Accelerator(self: *ElfState, target: u64, return_rip: u64) bool {
        return process_impl_execution.tryXeniaSha1Accelerator(self, target, return_rip);
    }

    /// The byte-feed loop around an accelerated `processBlock`.
    ///
    /// Accelerating the compression alone leaves the expensive half
    /// interpreted: the compiler inlines TinySHA1's `processBytes` into its
    /// caller as eleven instructions per byte, so a twenty-megabyte guest
    /// image costs a couple of hundred million steps to hash. On 2026-09-11
    /// that was the whole visible frontier - `XexModule::Precompile+0x283` -
    /// when the run was killed.
    ///
    /// This is recognized by the loop's own instruction bytes rather than by
    /// an address, and the exit target is read out of the matched branch, so
    /// it is not tied to one Xenia link. It runs only from inside an already
    /// signature-gated `processBlock`, and it deliberately stops one byte
    /// short of the end: the guest executes the final iteration itself, which
    /// leaves every register the loop wrote holding the value the guest's own
    /// code would have left there. Nothing here has to reason about which of
    /// `rax`, `rcx` and `rdx` is live after the branch.
    pub fn tryXeniaSha1FeedLoop(self: *ElfState, return_rip: u64) void {
        return process_impl_execution.tryXeniaSha1FeedLoop(self, return_rip);
    }

    /// Find the metadata-table accelerator's target once. Idempotent; see
    /// `resolveXeniaRijndaelTarget`.
    fn resolveXeniaTabulateTarget(self: *ElfState) void {
        return process_impl_execution.resolveXeniaTabulateTarget(self);
    }

    /// A target resolved after the translator was created must reach the
    /// hook filter, or the filter would admit a call the accelerator owns.
    /// `rebuildBlockJitHookFilter` resolves every accelerator first, so this
    /// only matters for a resolution that reaches here some other way.
    fn noteXeniaAcceleratorTargetResolved(self: *ElfState) void {
        return process_impl_execution.noteXeniaAcceleratorTargetResolved(self);
    }

    /// Resolve every accelerator that can act in this run. Each one keys a
    /// call-arm hook on an image address, and until its address is known
    /// the translator has to treat every image target as possibly its.
    fn resolveXeniaAcceleratorTargets(self: *ElfState) void {
        return process_impl_execution.resolveXeniaAcceleratorTargets(self);
    }

    fn tryXeniaTabulateAccelerator(self: *ElfState, target: u64, return_rip: u64) bool {
        return process_impl_execution.tryXeniaTabulateAccelerator(self, target, return_rip);
    }

    pub fn execute(self: *ElfState, d: DecodedInsn) void {
        return process_impl_execution.execute(self, d);
    }

    pub fn invokeLinuxSyscall(self: *ElfState, number: u64, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64, arg6: u64) void {
        return process_impl_syscalls.invokeLinuxSyscall(self, number, arg1, arg2, arg3, arg4, arg5, arg6);
    }

    fn dispatchLinuxSyscall(self: *ElfState) void {
        return process_impl_syscalls.dispatchLinuxSyscall(self);
    }

    pub fn guestCString(self: *ElfState, addr: u64, maximum: usize) ?[]const u8 {
        return process_impl_syscalls.guestCString(self, addr, maximum);
    }

    fn handleArchPrctlSyscall(self: *ElfState) void {
        return process_impl_syscalls.handleArchPrctlSyscall(self);
    }

    fn handleOpenSyscall(self: *ElfState) void {
        return process_impl_syscalls.handleOpenSyscall(self);
    }

    fn handleCreatSyscall(self: *ElfState) void {
        return process_impl_syscalls.handleCreatSyscall(self);
    }

    fn rememberInteractiveOutputPath(self: *ElfState, path: []const u8) void {
        return process_impl_syscalls.rememberInteractiveOutputPath(self, path);
    }

    fn handleReadSyscall(self: *ElfState) void {
        return process_impl_syscalls.handleReadSyscall(self);
    }

    fn handleCloseSyscall(self: *ElfState) void {
        return process_impl_syscalls.handleCloseSyscall(self);
    }

    fn handleWriteSyscall(self: *ElfState) void {
        return process_impl_syscalls.handleWriteSyscall(self);
    }
};
