const std = @import("std");
const testing = std.testing;

/// Zig 0.16 moved blocking synchronization behind `std.Io`, and these
/// runtime locks are reached without an Io context. They are the parking
/// mutex and condition of `lib/concurrency`: a waiter sleeps in the kernel
/// after a short spin, records itself for the stall watchdog, and on the host
/// main thread keeps serving AppKit's queue while it sleeps. They used to be
/// a bare spin lock and a yield loop, which burned a core per waiter for as
/// long as the holder took - including while the holder was itself asleep.
const HostMutex = struct {
    inner: concurrency.Mutex = .{},

    pub fn init(label: [*:0]const u8) HostMutex {
        return .{ .inner = concurrency.Mutex.init(label) };
    }

    pub fn lock(self: *const HostMutex) void {
        @constCast(&self.inner).lock();
    }

    pub fn tryLock(self: *const HostMutex) bool {
        return @constCast(&self.inner).tryLock();
    }

    pub fn unlock(self: *const HostMutex) void {
        @constCast(&self.inner).unlock();
    }
};

const HostCondition = struct {
    inner: concurrency.Condition = .{},

    fn wait(self: *HostCondition, mutex: *HostMutex) void {
        self.inner.wait(&mutex.inner);
    }

    fn signal(self: *HostCondition) void {
        self.inner.signal();
    }

    fn broadcast(self: *HostCondition) void {
        self.inner.broadcast();
    }
};

/// Error and warning lines are also kept for the exit report; see
/// `diagnostics/recent_log.zig`.
const log = recent_log.Scoped(.elf);
const recent_log = @import("diagnostics/recent_log.zig");
/// Host-thread parking, locks, the stop-the-world gate and the stall
/// watchdog: `lib/concurrency`.
const concurrency = @import("concurrency");
const terminal_event = @import("diagnostics/terminal_event.zig");
const guest_backtrace = @import("diagnostics/guest_backtrace.zig");
const guest_spin = @import("diagnostics/guest_spin.zig");
const gpu_stall = @import("diagnostics/gpu_stall.zig");
const block_verify = @import("diagnostics/block_verify_journal.zig");
const parallel_fault = @import("diagnostics/parallel_fault.zig");
const kuser_shared = @import("windows_guest/kuser_shared.zig");
const heap_address_cache = @import("windows_guest/heap_address_cache.zig");
const srw_lock_index = @import("windows_guest/srw_lock_index.zig");
const xmutant_release_compat = @import("windows_guest/xmutant_release_compat.zig");
const xmutant_teardown_compat = @import("windows_guest/xmutant_teardown_compat.zig");
const unmapped_reads = @import("diagnostics/unmapped_reads.zig");
const exit_context = @import("diagnostics/exit_context.zig");
const context_integrity = @import("diagnostics/context_integrity.zig");
const heap_guard = @import("diagnostics/heap_guard.zig");
const call_probe = @import("diagnostics/call_probe.zig");
const parallel_diagnostics = @import("diagnostics/parallel.zig");
const elf_loader = @import("elf_loader.zig");
const result_dump = @import("result_dump.zig");
const x64_guest_abi = @import("x64_guest_abi");
const x64_decoder = @import("x64_decoder");
const x64_interpreter = @import("x64_interpreter");
const evex = @import("evex_runtime");
const x64_linux_runtime = @import("x64_linux_runtime");
const x64_syscalls = @import("x64_syscalls");
const exit_diagnostics = @import("exit_diagnostics");
const cleo_routing = @import("cleo_routing");
const execution_history = @import("execution_history");
const vector_helpers = @import("x86_vector_helpers");
const xenia_accelerator = @import("xenia_accelerator.zig");
const xenia_fatal_condition_map = @import("xenia_fatal_condition_map");
const xenia_guest_frontier_map = @import("xenia_guest_frontier_map");
const xenia_warning_severity_map = @import("xenia_warning_severity_map");
const xenia_guest_milestone_map = @import("xenia_guest_milestone_map");
const xenia_guest_address_map = @import("xenia_guest_address_map");
const frame_content_contract = @import("frame_content_contract");
const screen_validity = @import("screen_validity");
/// What a guest address is when no symbol names it. The subsystem lives in
/// its own file; this module only holds the map and asks it questions.
const guest_address_space = @import("guest_address_space.zig");
/// Where a thread has been executing, whether it is getting anywhere, and if
/// not what its loop reads. Also its own file.
const spin_anatomy = @import("spin_anatomy.zig");
const host_profile = @import("host_profile.zig");
const host_fp_control = @import("host_fp_control.zig");
const frame_attribution = @import("frame_attribution.zig");
const windows_ui_ledger = @import("windows_ui/pipeline_ledger.zig");
const windows_guest_abi = @import("windows_guest/abi.zig");
const xenia_event_audit = @import("windows_guest/event_audit.zig");
const xbox_critical_section = @import("windows_guest/xbox_critical_section.zig");
const parallelism = @import("parallelism");
const translated_memory_contract = parallelism.translated_memory_contract;
const tlb_diagnostics = @import("parallelism/tlb_diagnostics.zig");

/// Which guest pages fault on access. See `guest_page_protection.zig`.
const guest_page_protection = @import("guest_page_protection.zig");
const tso_memory = @import("tso_memory");
const tso_memory_policy = tso_memory.memory_policy;
const worker_local_decode = @import("decode_cache/worker_local.zig");
const tso_execution_gate = parallelism.execution_gate;
const GuestExecutionGate = tso_execution_gate.GuestExecutionGate;
const GuestExecutionGateTls = tso_execution_gate.OwnerDepthStack;
const parallel_workers = parallelism.worker;
const parallel_metrics = parallelism.metrics;
const windows_message_queue = parallelism.ui_message_queue;
const windows_message_wait = @import("windows_ui/message_wait.zig");
/// Bounds what a guest's standard output can write to the host disk. See
/// `guest_output_governor.zig`.
const guest_output_governor = @import("guest_output_governor.zig");
/// The registry a PE guest owns. See `windows_registry.zig`.
const windows_registry_model = @import("windows_registry.zig");
const mapped_ranges = @import("mapped_ranges.zig");
const import_histogram = @import("import_histogram.zig");
const xenia_clock_probe = @import("xenia_clock_probe.zig");
const ui_draw_evidence = @import("ui_draw_evidence.zig");

/// Keep the Xenia presenter chain's table lookups in one bounded comptime
/// pass. The milestone map is intentionally growing as new boundaries become
/// observable, and rescanning it from several hot-path predicates eventually
/// exceeds Zig's default evaluation quota.
const xenia_presenter_attach_milestones = blk: {
    @setEvalBranchQuota(400_000);
    break :blk .{
        .emulator_thread = xenia_guest_milestone_map.indexOf("_ZN2xe3app11EmulatorApp14EmulatorThreadEv").?,
        .emulator_setup = xenia_guest_milestone_map.indexOf("_ZN2xe8Emulator5SetupEPNS_2ui6WindowEPNS1_11ImGuiDrawerEbSt8functionIFSt10unique_ptrINS_3apu11AudioSystemESt14default_deleteIS9_EEPNS_3cpu9ProcessorEEES6_IFS7_INS_3gpu14GraphicsSystemESA_ISJ_EEvEES6_IFSt6vectorIS7_INS_3hid11InputDriverESA_ISQ_EESaISS_EES3_EE").?,
        .call_in_ui_thread = xenia_guest_milestone_map.indexOf("_ZN2xe2ui18WindowedAppContext14CallInUIThreadESt8functionIFvvEE").?,
        .call_in_ui_thread_deferred = xenia_guest_milestone_map.indexOf("_ZN2xe2ui18WindowedAppContext22CallInUIThreadDeferredESt8functionIFvvEE").?,
        .setup = xenia_guest_milestone_map.indexOf("_ZN2xe3app14EmulatorWindow36SetupGraphicsSystemPresenterPaintingEv").?,
        .get_presenter = xenia_guest_milestone_map.indexOf("_ZNK2xe3app14EmulatorWindow26GetGraphicsSystemPresenterEv").?,
        .set_presenter = xenia_guest_milestone_map.indexOf("_ZN2xe2ui6Window12SetPresenterEPNS0_9PresenterE").?,
        .create_surface = xenia_guest_milestone_map.indexOf("_ZN2xe2ui11Win32Window17CreateSurfaceImplEj").?,
        .attach_surface = xenia_guest_milestone_map.indexOf("_ZN2xe2ui9Presenter28SetWindowSurfaceFromUIThreadEPNS0_6WindowEPNS0_7SurfaceE").?,
        .vulkan_connect = xenia_guest_milestone_map.indexOf("_ZN2xe2ui6vulkan15VulkanPresenter47ConnectOrReconnectPaintingToSurfaceFromUIThreadERNS0_7SurfaceEjjbRb").?,
        .font_rgba = xenia_guest_milestone_map.indexOf(ui_draw_evidence.font_rgba_symbol).?,
        .lists = xenia_guest_milestone_map.indexOf(ui_draw_evidence.lists_symbol).?,
        .draw = xenia_guest_milestone_map.indexOf(ui_draw_evidence.draw_symbol).?,
        .scissor = xenia_guest_milestone_map.indexOf(ui_draw_evidence.scissor_symbol).?,
        .pipelines = xenia_guest_milestone_map.indexOf(ui_draw_evidence.pipelines_symbol).?,
    };
};

test {
    _ = mapped_ranges;
    _ = import_histogram;
    _ = tlb_diagnostics;
    _ = worker_local_decode;
    _ = xenia_clock_probe;
    _ = ui_draw_evidence;
    // Sibling files' tests only run when something roots them.
    _ = guest_page_protection;
    _ = guest_output_governor;
    _ = windows_registry_model;
    _ = tso_execution_gate;
    _ = parallel_workers;
    _ = parallel_metrics;
    _ = parallelism;
    _ = host_profile;
    _ = recent_log;
    _ = terminal_event;
    _ = guest_backtrace;
    _ = exit_context;
    _ = context_integrity;
    _ = heap_guard;
    _ = call_probe;
    _ = parallel_diagnostics;
    _ = parallel_fault;
    _ = xmutant_release_compat;
    _ = xmutant_teardown_compat;
    _ = block_lifetime;
    _ = xbox_critical_section;
    _ = windows_guest_abi;
}

/// The armed set of Xenia kernel export shims, and what the title called.
/// See `kernel_call_census.zig`.
const kernel_call_census = @import("kernel_call_census.zig");
const xenia_kernel_shim_map = @import("xenia_kernel_shim_map");
/// The performance counter Rosette publishes to the guest, and what it counts.
const guest_clock = @import("guest_clock.zig");
const wait_cost = @import("wait_cost.zig");

/// One resolved guest symbol. `name` points into a buffer the caller owns for
/// the duration of the call and is never retained.
pub const GuestSymbol = struct {
    name: []const u8,
    offset: u64,
};

/// How this state turns a guest address into a name.
///
/// The symbol table lives with the image loader, which is a `src/tooling`
/// component that already imports this module; installing a resolver rather
/// than the table itself keeps the dependency pointing one way. A state with
/// no resolver reports every address as unnamed, which is the honest answer
/// for a stripped image and never blocks a run.
pub const GuestSymbolResolver = struct {
    context: *const anyopaque,
    resolve: *const fn (context: *const anyopaque, address: u64, buffer: []u8) ?GuestSymbol,
    /// The inverse: the loaded address of an exactly-named symbol.
    ///
    /// Optional because a stripped image, or a loader that has not been
    /// taught to supply it, must still install a working `resolve`. A state
    /// whose resolver has no `address_of` arms no milestone tracepoints and
    /// reports them all as unresolved, which is the honest answer.
    address_of: ?*const fn (context: *const anyopaque, name: []const u8) ?u64 = null,
};

/// The largest symbol text a diagnostic will render. Long enough for a fully
/// qualified Xenia name plus its offset.
pub const guest_symbol_text_bytes: usize = 224;

/// One precondition in an ordered chain, with the owner who has to satisfy it.
///
/// Shared by the first-frame and audio chains because a reader learns one
/// shape: stages in dependency order, and only the earliest unmet one is a
/// finding. Everything after it is a consequence.
pub const ChainStage = struct {
    name: []const u8,
    owner: []const u8,
    met: bool,
    /// The counter that decides `met`, named so a reader can check the
    /// verdict against the raw number rather than trusting it.
    evidence: []const u8,
    value: u64,
    /// Whether this run can see the stage at all.
    ///
    /// A stage whose evidence is an entry count on a guest symbol the image
    /// does not contain reads zero whether or not the guest reached it.
    /// Calling that `unmet` would make a stripped binary look like a title
    /// that never started, and would put the wall on an owner who did
    /// nothing wrong - so an unobservable stage is skipped by the wall
    /// search and printed as its own state. Defaults to true, because every
    /// stage whose evidence is one of Rosette's own counters always is.
    observable: bool = true,
    /// Why the stage is unobservable, when it is. Two very different causes
    /// print the same `unobservable` otherwise: an image with no symbol for
    /// it, and an image whose optimizer inlined the symbol's body into its
    /// callers so the out-of-line copy can never be entered. The second is
    /// the one that misled the 2026-09-12 run.
    unobservable_reason: []const u8 = "this image does not name the symbol",
    /// A second witness for the same stage, from the other side of the guest
    /// boundary, and how many times it fired.
    ///
    /// Every guest-owned stage's primary evidence is an entry count on a
    /// Xenia function, and a Xenia function can be inlined into its caller,
    /// devirtualised, or reached from somewhere that is not the title. The
    /// kernel export shim the title actually calls has none of those failure
    /// modes: nothing inside the image branches to it, so its count is the
    /// title's own act and only that.
    ///
    /// A stage is met when either witness fired. The two counts are printed
    /// side by side because they disagree in informative ways - a shim
    /// entered whose implementation reads zero is an inlined call, and an
    /// implementation entered whose shim reads zero is Xenia calling itself.
    witness: []const u8 = "",
    witness_value: u64 = 0,
    /// Whether this run could see the witness at all, so a zero from an
    /// unarmed shim is never read as a title that did not call it.
    witness_armed: bool = false,
    /// What a reader should do when this stage is the wall.
    ///
    /// The chain printed `unmet (downstream of the wall)` against nine stages
    /// for several runs, which tells a reader nothing the stage above had not
    /// already said. This is the sentence that names where to look next, and
    /// it is written per stage because the answer is different for each.
    when_unmet: []const u8 = "",
};

/// How a `VirtualAlloc` request relates to what already backs its address.
///
/// Windows draws a hard line here: `MEM_COMMIT` against an address inside a
/// reservation succeeds, and against an address inside nothing it fails with
/// ERROR_INVALID_ADDRESS. Rosetta used to record one flat "this range is
/// backed" fact for both operations, so the line was not drawn at all - and
/// the run log's `fixed_reservation=false` next to a successful commit was
/// the visible edge of that.
///
/// Xenia's own `BaseHeap::AllocFixed` prints
/// `attempting commit on unreserved page` when *its* page table disagrees the
/// same way, then promotes the request and carries on. Both sides silently
/// repairing the same thing is how a memory model drifts, so Rosetta names
/// which backing actually covered each commit instead.
pub const WindowsAllocationDisposition = enum {
    /// A new reservation of previously unbacked address space.
    reserved_new,
    /// A commit inside a range this run reserved.
    committed_in_reservation,
    /// A commit inside a file-mapping view - which is how Xenia backs the
    /// whole 32-bit guest aperture, so this is the common healthy case.
    committed_in_mapped_view,
    /// A commit inside the loaded image or its flat guest heap.
    committed_in_image,
    /// A commit against an address nothing had reserved. Windows fails this;
    /// Rosetta serves it and says so, because refusing would end a run over a
    /// distinction the guest has already lost track of itself.
    committed_unbacked,
    /// A reserve over a range that is already reserved. Windows fails this
    /// and the generic caller is expected to advance. Xenia's known CPU
    /// context allocator is handled by the relocation policy below.
    reserve_over_existing,
    /// A known fixed-address allocator was given the next valid candidate in
    /// its own address contract, so no guest allocation was left refused.
    relocated,
    /// The request could not be served at all.
    refused,

    pub fn label(self: WindowsAllocationDisposition) []const u8 {
        return switch (self) {
            .reserved_new => "reserved_new",
            .committed_in_reservation => "committed_in_reservation",
            .committed_in_mapped_view => "committed_in_mapped_view",
            .committed_in_image => "committed_in_image",
            .committed_unbacked => "committed_unbacked",
            .reserve_over_existing => "reserve_over_existing",
            .relocated => "relocated",
            .refused => "refused",
        };
    }

    /// Whether this disposition is one Windows would have failed.
    pub fn divergesFromWindows(self: WindowsAllocationDisposition) bool {
        return self == .committed_unbacked;
    }
};

pub const MAX_WINDOWS_UNBACKED_COMMITS: usize = 16;

/// One commit Rosetta served against address space nothing had reserved.
pub const WindowsUnbackedCommit = struct {
    base: u64 = 0,
    length: u64 = 0,
    caller_rip: u64 = 0,
    step: u64 = 0,
    occurrences: u64 = 0,
};

pub const WindowsAllocationRefusalReason = enum {
    reserve_over_existing,
    allocation_backend_refused,

    pub fn label(self: WindowsAllocationRefusalReason) []const u8 {
        return switch (self) {
            .reserve_over_existing => "reserve_over_existing",
            .allocation_backend_refused => "allocation_backend_refused",
        };
    }
};

pub const MAX_WINDOWS_ALLOCATION_REFUSALS: usize = 16;

/// One fixed VirtualAlloc request Rosette rejected, retained separately from
/// commits it served against an unreserved address.  A refusal can be the
/// correct Windows result (for example, a second MEM_RESERVE over an existing
/// range); the distinction still needs to be visible instead of collapsing
/// six different request sites into one counter.
pub const WindowsAllocationRefusal = struct {
    base: u64 = 0,
    length: u64 = 0,
    caller_rip: u64 = 0,
    step: u64 = 0,
    occurrences: u64 = 0,
    reason: WindowsAllocationRefusalReason = .allocation_backend_refused,
    reserve_requested: bool = false,
    commit_requested: bool = false,
};

/// Fixed-address PE arenas normally have fewer than twenty relocation sites.
/// Sixteen made the report silently lose distinct call sites in the observed
/// run, so leave enough room for the complete bootstrap and retain a small
/// digest for pathological images beyond this bound.
pub const MAX_WINDOWS_ALLOCATION_RELOCATIONS: usize = 64;
pub const MAX_WINDOWS_ALLOCATION_RELOCATION_OVERFLOW_SAMPLES: usize = 8;

/// One fixed allocation Rosetta moved to the next candidate in Xenia's own
/// deterministic context arena. The guest receives `actual_base`; the
/// requested occupied range is never aliased or overwritten.
pub const WindowsAllocationRelocation = struct {
    requested_base: u64 = 0,
    actual_base: u64 = 0,
    length: u64 = 0,
    caller_rip: u64 = 0,
    step: u64 = 0,
    last_step: u64 = 0,
    occurrences: u64 = 0,
};

pub const FIRST_FRAME_STAGE_COUNT: usize = 14;
pub const AUDIO_STAGE_COUNT: usize = 11;

/// Stages between "a window can carry a frame" and "the title's picture is
/// on it".
///
/// The first-frame chain measures transport, and every one of its fourteen
/// stages can be met by a window that shows one flat colour - which is
/// exactly what the 2026-09-12 run produced while reporting 14/14 met. This
/// chain measures production, and none of its evidence comes from Rosette's
/// own surface: it is entry counts on Xenia's own functions, because nothing
/// on Rosette's side of the boundary can tell a frame with a picture in it
/// from a frame without one.
pub const GUEST_OUTPUT_STAGE_COUNT: usize = 15;

/// One entry per row of the milestone table.
pub const GUEST_MILESTONE_COUNT: usize = xenia_guest_milestone_map.count();

/// How many recorded entries make a milestone established. After that, a
/// milestone that is only an observation stops costing its callers an
/// interpreter round trip: on 2026-09-23 `VulkanCommandProcessor::
/// ExecutePacket` alone took 26.6 million of them, one per PM4 packet, about
/// 54 of the run's 574 seconds.
const GUEST_MILESTONE_TRANSLATOR_SATURATION: u64 = 4096;

/// Whether a milestone may saturate: true unless recording it does more than
/// count - reads arguments, repairs a wake, marks a thread or times a frame.
/// Every index `recordGuestMilestone` and `noteGuestMilestoneArguments`
/// special-case is listed here, and a test holds the two in step.
fn guestMilestoneSaturable(index: usize) bool {
    const map = xenia_guest_milestone_map;
    const functional = comptime blk: {
        @setEvalBranchQuota(400_000);
        break :blk [_]?usize{
            map.indexOf("_ZN2xe3apu11AudioSystem11SubmitFrameEyPf"),
            map.indexOf("_ZN2xe3gpu14GraphicsSystem17ReadRegisterThunkEPvPS1_j"),
            map.indexOf("_ZN2xe3gpu14GraphicsSystem18WriteRegisterThunkEPvPS1_jj"),
            map.indexOf("_ZN2xe3gpu14GraphicsSystem20InitializeRingBufferEjj"),
            map.indexOf("_ZN2xe3gpu14GraphicsSystem26EnableReadPointerWriteBackEjj"),
            map.indexOf("_ZN2xe3gpu16CommandProcessor18UpdateWritePointerEj"),
            map.indexOf("_ZN2xe3vfs17VirtualFileSystem11ResolvePathESt17basic_string_viewIcSt11char_traitsIcEE"),
            map.indexOf(ui_draw_evidence.draw_symbol),
            map.indexOf(ui_draw_evidence.font_rgba_symbol),
            map.indexOf(ui_draw_evidence.lists_symbol),
            map.indexOf(ui_draw_evidence.pipelines_symbol),
            map.indexOf(ui_draw_evidence.scissor_symbol),
            map.indexOf("_ZN2xe3gpu6vulkan22VulkanCommandProcessor9IssueSwapEjjj"),
            map.indexOf("_ZN2xe6kernel7XThread7ExecuteEv"),
        };
    };
    inline for (functional) |entry| {
        if (entry) |functional_index| {
            if (index == functional_index) return false;
        }
    }
    return true;
}

/// Callers tracked per milestone. Four, because the point is to separate a
/// witness's two or three producers, not to build a profiler: a row with more
/// callers than this reports the overflow and stops splitting.
const GUEST_MILESTONE_CALLER_SLOTS: usize = 4;

/// `name+0x1f` without its offset, so samples anywhere in one function rank
/// together. A name with no offset is returned whole.
fn trimAddressOffset(described: []const u8) []const u8 {
    const plus = std.mem.lastIndexOf(u8, described, "+0x") orelse return described;
    if (plus == 0) return described;
    for (described[plus + 3 ..]) |c| {
        if (!std.ascii.isHex(c)) return described;
    }
    return described[0..plus];
}

/// Host monotonic nanoseconds, or zero when the clock cannot be read.
///
/// Zero is the "do not report" value everywhere it is used: a rate computed
/// from a clock that failed is worse than no rate at all.
const monotonicNanoseconds = @import("diagnostics/monotonic_clock.zig").monotonicNanoseconds;

extern "c" fn pthread_main_np() c_int;
/// `pthread_set_qos_class_self_np(qos_class_t, int)` from <pthread/qos.h>.
extern "c" fn pthread_set_qos_class_self_np(qos_class: c_uint, relative_priority: c_int) c_int;

/// Whether the calling host thread is the process's main thread - the one
/// AppKit must be touched from.
fn isHostMainThread() bool {
    if (comptime @import("builtin").os.tag.isDarwin()) return pthread_main_np() != 0;
    return false;
}

/// The AppKit bridge calls this around every request it `dispatch_sync`s to
/// the main thread from another one: phase 0 before, 1 after. Before, it
/// cuts the main thread's current park short, so a main thread asleep on a
/// lock the requester holds drains the request at once; and it marks the
/// requester as blocked for the stall watchdog, which is the only record a
/// hang would otherwise leave of who waits on whom.
pub fn mainThreadRequestHook(phase: c_int) callconv(.c) void {
    if (phase == 0) {
        concurrency.watch.beginBlocking("AppKit request dispatched to the main thread");
        concurrency.park.requestService();
    } else {
        concurrency.watch.endBlocking();
    }
}

/// How many guest instructions a parallel worker retires between publishing
/// its count to the shared totals. The totals feed checkpoints, heartbeats
/// and the stall watchdog, none of which need a fresher number; publishing
/// after every instruction made three shared cache lines bounce between every
/// worker's core.
const PARALLEL_WORKER_STEP_BATCH: u64 = 4096;

/// The shortest slice a yielding worker is given before the switch happens.
///
/// A yield means "run someone else", and honouring it on the very next
/// instruction would pay two register-file copies per handful of guest
/// instructions. Two hundred and fifty-six is two orders of magnitude below
/// the ordinary slice and two orders above the cost of the switch.
const WINDOWS_GUEST_YIELD_MINIMUM_SLICE: u64 = 256;

/// Owner steps between two host event-queue drains.
///
/// The guest's message loop asks far more often than a window has events. At
/// the ~1.5M instructions/s this route sustains, a stride of a thousand puts
/// the pump in the hundreds of hertz - well above any rate a person can
/// generate window events at, and four orders of magnitude below what Xenia's
/// loop was asking for.
const WINDOWS_EVENT_PUMP_STRIDE = @import("windows_ui/graphics_state.zig").WINDOWS_EVENT_PUMP_STRIDE;

/// Which bit of the membership filter an address claims.
///
/// Function entries are aligned, so the low four bits carry almost no
/// information; folding two higher slices together keeps a dozen addresses
/// from piling onto the same bit. A collision only costs the comparison loop
/// it was meant to avoid, never a wrong answer.
/// A filter bit two armed addresses landed on; that bit falls back to a scan.
const milestone_slot_collision: u8 = 0xFF;

/// Slots in the milestone dispatch table.
///
/// It was a 64-bit Bloom filter, which is the right structure for a handful
/// of addresses and the wrong one as soon as the table grows: twenty-two
/// milestones set roughly a third of the bits, so a third of every call the
/// interpreter made passed the filter and paid for a comparison that could
/// not succeed - 33 million of them on the 2026-09-12 run. A direct-mapped
/// table of 256 slots costs the same single load and, at the twenty-six rows
/// the table now carries, almost never lets a non-milestone through.
const GUEST_MILESTONE_SLOTS: usize = 256;

/// Fibonacci hashing rather than a shift-xor of the address bits. Entry
/// points in this image are 16-byte aligned, so the low four bits carry no
/// information and a mask alone would throw away the ones that do.
fn guestMilestoneFilterBit(address: u64) u8 {
    const mixed = address *% 0x9E3779B97F4A7C15;
    return @truncate(mixed >> 32);
}

/// Below this many remaining bytes the feed loop is not worth intercepting:
/// the guest finishes it in microseconds and the interception is pure risk.
const XENIA_SHA1_FEED_MINIMUM: u64 = 4096;

const WORKLOAD_COUNT: usize = @typeInfo(xenia_guest_frontier_map.Workload).@"enum".fields.len;
const WINDOWS_ALLOCATION_DISPOSITION_COUNT: usize = @typeInfo(WindowsAllocationDisposition).@"enum".fields.len;

/// Bounded because a run must not be able to grow this by calling
/// `LoadLibrary` in a loop; a guest with more distinct modules than this is
/// reported as overflowing rather than silently losing the tail.
pub const MAX_WINDOWS_LOADED_MODULES: usize = 64;
pub const MAX_WINDOWS_DYNAMIC_REFUSALS: usize = 32;
const WINDOWS_MODULE_NAME_BYTES: usize = 64;
const WINDOWS_EXPORT_NAME_BYTES: usize = 96;

/// A module this run gave a handle to.
pub const WindowsLoadedModule = struct {
    handle: u64 = 0,
    name: [WINDOWS_MODULE_NAME_BYTES]u8 = [_]u8{0} ** WINDOWS_MODULE_NAME_BYTES,
    name_len: u8 = 0,

    pub fn moduleName(self: *const WindowsLoadedModule) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// A module or export Rosetta reported absent, kept so the run can say which
/// optional subsystem the guest was told it did not have.
pub const WindowsDynamicRefusal = struct {
    scope: [WINDOWS_MODULE_NAME_BYTES]u8 = [_]u8{0} ** WINDOWS_MODULE_NAME_BYTES,
    scope_len: u8 = 0,
    name: [WINDOWS_EXPORT_NAME_BYTES]u8 = [_]u8{0} ** WINDOWS_EXPORT_NAME_BYTES,
    name_len: u8 = 0,
    occurrences: u64 = 0,
    /// Whether this refusal is a hole in Rosetta's coverage rather than a
    /// policy decision. Only the first kind is a finding.
    is_gap: bool = false,
    first_caller_rip: u64 = 0,

    pub fn scopeText(self: *const WindowsDynamicRefusal) []const u8 {
        return self.scope[0..self.scope_len];
    }

    pub fn nameText(self: *const WindowsDynamicRefusal) []const u8 {
        return self.name[0..self.name_len];
    }
};

fn copyBoundedName(destination: []u8, source: []const u8) u8 {
    const copied = @min(source.len, destination.len);
    @memcpy(destination[0..copied], source[0..copied]);
    return @intCast(copied);
}

const SYS_read = x64_syscalls.SYS_read; // 0
const SYS_write = x64_syscalls.SYS_write; // 1
const SYS_open = x64_syscalls.SYS_open; // 2
const SYS_close = x64_syscalls.SYS_close; // 3
const SYS_stat = x64_syscalls.SYS_stat; // 4
const SYS_fstat = x64_syscalls.SYS_fstat; // 5
const SYS_lstat = x64_syscalls.SYS_lstat; // 6
const SYS_poll = x64_syscalls.SYS_poll; // 7
const SYS_lseek = x64_syscalls.SYS_lseek; // 8
const SYS_mmap = x64_syscalls.SYS_mmap; // 9
const SYS_mprotect = x64_syscalls.SYS_mprotect; // 10
const SYS_munmap = x64_syscalls.SYS_munmap; // 11
const SYS_brk = x64_syscalls.SYS_brk; // 12
const SYS_rt_sigaction = x64_syscalls.SYS_rt_sigaction; // 13
const SYS_rt_sigprocmask = x64_syscalls.SYS_rt_sigprocmask; // 14
const SYS_rt_sigreturn = x64_syscalls.SYS_rt_sigreturn; // 15
const SYS_ioctl = x64_syscalls.SYS_ioctl; // 16
const SYS_pread64 = x64_syscalls.SYS_pread64; // 17
const SYS_pwrite64 = x64_syscalls.SYS_pwrite64; // 18
const SYS_readv = x64_syscalls.SYS_readv; // 19
const SYS_writev = x64_syscalls.SYS_writev; // 20
const SYS_access = x64_syscalls.SYS_access; // 21
const SYS_pipe = x64_syscalls.SYS_pipe; // 22
const SYS_select = x64_syscalls.SYS_select; // 23
const SYS_sched_yield = x64_syscalls.SYS_sched_yield; // 24
const SYS_mremap = x64_syscalls.SYS_mremap; // 25
const SYS_msync = x64_syscalls.SYS_msync; // 26
const SYS_mincore = x64_syscalls.SYS_mincore; // 27
const SYS_madvise = x64_syscalls.SYS_madvise; // 28
const SYS_shmget = x64_syscalls.SYS_shmget; // 29
const SYS_shmat = x64_syscalls.SYS_shmat; // 30
const SYS_shmctl = x64_syscalls.SYS_shmctl; // 31
const SYS_dup = x64_syscalls.SYS_dup; // 32
const SYS_dup2 = x64_syscalls.SYS_dup2; // 33
const SYS_pause = x64_syscalls.SYS_pause; // 34
const SYS_nanosleep = x64_syscalls.SYS_nanosleep; // 35
const SYS_getitimer = x64_syscalls.SYS_getitimer; // 36
const SYS_alarm = x64_syscalls.SYS_alarm; // 37
const SYS_setitimer = x64_syscalls.SYS_setitimer; // 38
const SYS_getpid = x64_syscalls.SYS_getpid; // 39
const SYS_sendfile = x64_syscalls.SYS_sendfile; // 40
const SYS_socket = x64_syscalls.SYS_socket; // 41
const SYS_connect = x64_syscalls.SYS_connect; // 42
const SYS_accept = x64_syscalls.SYS_accept; // 43
const SYS_sendto = x64_syscalls.SYS_sendto; // 44
const SYS_recvfrom = x64_syscalls.SYS_recvfrom; // 45
const SYS_sendmsg = x64_syscalls.SYS_sendmsg; // 46
const SYS_recvmsg = x64_syscalls.SYS_recvmsg; // 47
const SYS_shutdown = x64_syscalls.SYS_shutdown; // 48
const SYS_bind = x64_syscalls.SYS_bind; // 49
const SYS_listen = x64_syscalls.SYS_listen; // 50
const SYS_getsockname = x64_syscalls.SYS_getsockname; // 51
const SYS_getpeername = x64_syscalls.SYS_getpeername; // 52
const SYS_socketpair = x64_syscalls.SYS_socketpair; // 53
const SYS_setsockopt = x64_syscalls.SYS_setsockopt; // 54
const SYS_getsockopt = x64_syscalls.SYS_getsockopt; // 55
const SYS_clone = x64_syscalls.SYS_clone; // 56
const SYS_fork = x64_syscalls.SYS_fork; // 57
const SYS_vfork = x64_syscalls.SYS_vfork; // 58
const SYS_execve = x64_syscalls.SYS_execve; // 59
const SYS_exit = x64_syscalls.SYS_exit; // 60
const SYS_wait4 = x64_syscalls.SYS_wait4; // 61
const SYS_kill = x64_syscalls.SYS_kill; // 62
const SYS_uname = x64_syscalls.SYS_uname; // 63
const SYS_semget = x64_syscalls.SYS_semget; // 64
const SYS_semop = x64_syscalls.SYS_semop; // 65
const SYS_semctl = x64_syscalls.SYS_semctl; // 66
const SYS_shmdt = x64_syscalls.SYS_shmdt; // 67
const SYS_msgget = x64_syscalls.SYS_msgget; // 68
const SYS_msgsnd = x64_syscalls.SYS_msgsnd; // 69
const SYS_msgrcv = x64_syscalls.SYS_msgrcv; // 70
const SYS_msgctl = x64_syscalls.SYS_msgctl; // 71
const SYS_fcntl = x64_syscalls.SYS_fcntl; // 72
const SYS_flock = x64_syscalls.SYS_flock; // 73
const SYS_fsync = x64_syscalls.SYS_fsync; // 74
const SYS_fdatasync = x64_syscalls.SYS_fdatasync; // 75
const SYS_truncate = x64_syscalls.SYS_truncate; // 76
const SYS_ftruncate = x64_syscalls.SYS_ftruncate; // 77
const SYS_getdents = x64_syscalls.SYS_getdents; // 78
const SYS_getcwd = x64_syscalls.SYS_getcwd; // 79
const SYS_chdir = x64_syscalls.SYS_chdir; // 80
const SYS_fchdir = x64_syscalls.SYS_fchdir; // 81
const SYS_rename = x64_syscalls.SYS_rename; // 82
const SYS_mkdir = x64_syscalls.SYS_mkdir; // 83
const SYS_rmdir = x64_syscalls.SYS_rmdir; // 84
const SYS_creat = x64_syscalls.SYS_creat; // 85
const SYS_link = x64_syscalls.SYS_link; // 86
const SYS_unlink = x64_syscalls.SYS_unlink; // 87
const SYS_symlink = x64_syscalls.SYS_symlink; // 88
const SYS_readlink = x64_syscalls.SYS_readlink; // 89
const SYS_chmod = x64_syscalls.SYS_chmod; // 90
const SYS_fchmod = x64_syscalls.SYS_fchmod; // 91
const SYS_chown = x64_syscalls.SYS_chown; // 92
const SYS_fchown = x64_syscalls.SYS_fchown; // 93
const SYS_lchown = x64_syscalls.SYS_lchown; // 94
const SYS_umask = x64_syscalls.SYS_umask; // 95
const SYS_gettimeofday = x64_syscalls.SYS_gettimeofday; // 96
const SYS_getrlimit = x64_syscalls.SYS_getrlimit; // 97
const SYS_getrusage = x64_syscalls.SYS_getrusage; // 98
const SYS_sysinfo = x64_syscalls.SYS_sysinfo; // 99
const SYS_times = x64_syscalls.SYS_times; // 100
const SYS_ptrace = x64_syscalls.SYS_ptrace; // 101
const SYS_getuid = x64_syscalls.SYS_getuid; // 102
const SYS_syslog = x64_syscalls.SYS_syslog; // 103
const SYS_getgid = x64_syscalls.SYS_getgid; // 104
const SYS_setuid = x64_syscalls.SYS_setuid; // 105
const SYS_setgid = x64_syscalls.SYS_setgid; // 106
const SYS_geteuid = x64_syscalls.SYS_geteuid; // 107
const SYS_getegid = x64_syscalls.SYS_getegid; // 108
const SYS_setpgid = x64_syscalls.SYS_setpgid; // 109
const SYS_getppid = x64_syscalls.SYS_getppid; // 110
const SYS_getpgrp = x64_syscalls.SYS_getpgrp; // 111
const SYS_setsid = x64_syscalls.SYS_setsid; // 112
const SYS_setreuid = x64_syscalls.SYS_setreuid; // 113
const SYS_setregid = x64_syscalls.SYS_setregid; // 114
const SYS_getgroups = x64_syscalls.SYS_getgroups; // 115
const SYS_setgroups = x64_syscalls.SYS_setgroups; // 116
const SYS_setresuid = x64_syscalls.SYS_setresuid; // 117
const SYS_getresuid = x64_syscalls.SYS_getresuid; // 118
const SYS_setresgid = x64_syscalls.SYS_setresgid; // 119
const SYS_getresgid = x64_syscalls.SYS_getresgid; // 120
const SYS_getpgid = x64_syscalls.SYS_getpgid; // 121
const SYS_setfsuid = x64_syscalls.SYS_setfsuid; // 122
const SYS_setfsgid = x64_syscalls.SYS_setfsgid; // 123
const SYS_getsid = x64_syscalls.SYS_getsid; // 124
const SYS_capget = x64_syscalls.SYS_capget; // 125
const SYS_capset = x64_syscalls.SYS_capset; // 126
const SYS_rt_sigpending = x64_syscalls.SYS_rt_sigpending; // 127
const SYS_rt_sigtimedwait = x64_syscalls.SYS_rt_sigtimedwait; // 128
const SYS_rt_sigqueueinfo = x64_syscalls.SYS_rt_sigqueueinfo; // 129
const SYS_rt_sigsuspend = x64_syscalls.SYS_rt_sigsuspend; // 130
const SYS_sigaltstack = x64_syscalls.SYS_sigaltstack; // 131
const SYS_utime = x64_syscalls.SYS_utime; // 132
const SYS_mknod = x64_syscalls.SYS_mknod; // 133
const SYS_uselib = x64_syscalls.SYS_uselib; // 134
const SYS_personality = x64_syscalls.SYS_personality; // 135
const SYS_ustat = x64_syscalls.SYS_ustat; // 136
const SYS_statfs = x64_syscalls.SYS_statfs; // 137
const SYS_fstatfs = x64_syscalls.SYS_fstatfs; // 138
const SYS_sysfs = x64_syscalls.SYS_sysfs; // 139
const SYS_getpriority = x64_syscalls.SYS_getpriority; // 140
const SYS_setpriority = x64_syscalls.SYS_setpriority; // 141
const SYS_sched_setparam = x64_syscalls.SYS_sched_setparam; // 142
const SYS_sched_getparam = x64_syscalls.SYS_sched_getparam; // 143
const SYS_sched_setscheduler = x64_syscalls.SYS_sched_setscheduler; // 144
const SYS_sched_getscheduler = x64_syscalls.SYS_sched_getscheduler; // 145
const SYS_sched_get_priority_max = x64_syscalls.SYS_sched_get_priority_max; // 146
const SYS_sched_get_priority_min = x64_syscalls.SYS_sched_get_priority_min; // 147
const SYS_sched_rr_get_interval = x64_syscalls.SYS_sched_rr_get_interval; // 148
const SYS_mlock = x64_syscalls.SYS_mlock; // 149
const SYS_munlock = x64_syscalls.SYS_munlock; // 150
const SYS_mlockall = x64_syscalls.SYS_mlockall; // 151
const SYS_munlockall = x64_syscalls.SYS_munlockall; // 152
const SYS_vhangup = x64_syscalls.SYS_vhangup; // 153
const SYS_modify_ldt = x64_syscalls.SYS_modify_ldt; // 154
const SYS_pivot_root = x64_syscalls.SYS_pivot_root; // 155
const SYS__sysctl = x64_syscalls.SYS__sysctl; // 156
const SYS_prctl = x64_syscalls.SYS_prctl; // 157
const SYS_arch_prctl = x64_syscalls.SYS_arch_prctl; // 158
const SYS_adjtimex = x64_syscalls.SYS_adjtimex; // 159
const SYS_setrlimit = x64_syscalls.SYS_setrlimit; // 160
const SYS_chroot = x64_syscalls.SYS_chroot; // 161
const SYS_sync = x64_syscalls.SYS_sync; // 162
const SYS_acct = x64_syscalls.SYS_acct; // 163
const SYS_settimeofday = x64_syscalls.SYS_settimeofday; // 164
const SYS_mount = x64_syscalls.SYS_mount; // 165
const SYS_umount2 = x64_syscalls.SYS_umount2; // 166
const SYS_swapon = x64_syscalls.SYS_swapon; // 167
const SYS_swapoff = x64_syscalls.SYS_swapoff; // 168
const SYS_reboot = x64_syscalls.SYS_reboot; // 169
const SYS_sethostname = x64_syscalls.SYS_sethostname; // 170
const SYS_setdomainname = x64_syscalls.SYS_setdomainname; // 171
const SYS_iopl = x64_syscalls.SYS_iopl; // 172
const SYS_ioperm = x64_syscalls.SYS_ioperm; // 173
const SYS_create_module = x64_syscalls.SYS_create_module; // 174
const SYS_init_module = x64_syscalls.SYS_init_module; // 175
const SYS_delete_module = x64_syscalls.SYS_delete_module; // 176
const SYS_get_kernel_syms = x64_syscalls.SYS_get_kernel_syms; // 177
const SYS_query_module = x64_syscalls.SYS_query_module; // 178
const SYS_quotactl = x64_syscalls.SYS_quotactl; // 179
const SYS_nfsservctl = x64_syscalls.SYS_nfsservctl; // 180
const SYS_getpmsg = x64_syscalls.SYS_getpmsg; // 181
const SYS_putpmsg = x64_syscalls.SYS_putpmsg; // 182
const SYS_afs_syscall = x64_syscalls.SYS_afs_syscall; // 183
const SYS_tuxcall = x64_syscalls.SYS_tuxcall; // 184
const SYS_security = x64_syscalls.SYS_security; // 185
const SYS_gettid = x64_syscalls.SYS_gettid; // 186
const SYS_readahead = x64_syscalls.SYS_readahead; // 187
const SYS_setxattr = x64_syscalls.SYS_setxattr; // 188
const SYS_lsetxattr = x64_syscalls.SYS_lsetxattr; // 189
const SYS_fsetxattr = x64_syscalls.SYS_fsetxattr; // 190
const SYS_getxattr = x64_syscalls.SYS_getxattr; // 191
const SYS_lgetxattr = x64_syscalls.SYS_lgetxattr; // 192
const SYS_fgetxattr = x64_syscalls.SYS_fgetxattr; // 193
const SYS_listxattr = x64_syscalls.SYS_listxattr; // 194
const SYS_llistxattr = x64_syscalls.SYS_llistxattr; // 195
const SYS_flistxattr = x64_syscalls.SYS_flistxattr; // 196
const SYS_removexattr = x64_syscalls.SYS_removexattr; // 197
const SYS_lremovexattr = x64_syscalls.SYS_lremovexattr; // 198
const SYS_fremovexattr = x64_syscalls.SYS_fremovexattr; // 199
const SYS_tkill = x64_syscalls.SYS_tkill; // 200
const SYS_time = x64_syscalls.SYS_time; // 201
const SYS_futex = x64_syscalls.SYS_futex; // 202
const SYS_sched_setaffinity = x64_syscalls.SYS_sched_setaffinity; // 203
const SYS_sched_getaffinity = x64_syscalls.SYS_sched_getaffinity; // 204
const SYS_set_thread_area = x64_syscalls.SYS_set_thread_area; // 205
const SYS_io_setup = x64_syscalls.SYS_io_setup; // 206
const SYS_io_destroy = x64_syscalls.SYS_io_destroy; // 207
const SYS_io_getevents = x64_syscalls.SYS_io_getevents; // 208
const SYS_io_submit = x64_syscalls.SYS_io_submit; // 209
const SYS_io_cancel = x64_syscalls.SYS_io_cancel; // 210
const SYS_get_thread_area = x64_syscalls.SYS_get_thread_area; // 211
const SYS_lookup_dcookie = x64_syscalls.SYS_lookup_dcookie; // 212
const SYS_epoll_create = x64_syscalls.SYS_epoll_create; // 213
const SYS_epoll_ctl_old = x64_syscalls.SYS_epoll_ctl_old; // 214
const SYS_epoll_wait_old = x64_syscalls.SYS_epoll_wait_old; // 215
const SYS_remap_file_pages = x64_syscalls.SYS_remap_file_pages; // 216
const SYS_getdents64 = x64_syscalls.SYS_getdents64; // 217
const SYS_set_tid_address = x64_syscalls.SYS_set_tid_address; // 218
const SYS_restart_syscall = x64_syscalls.SYS_restart_syscall; // 219
const SYS_semtimedop = x64_syscalls.SYS_semtimedop; // 220
const SYS_fadvise64 = x64_syscalls.SYS_fadvise64; // 221
const SYS_timer_create = x64_syscalls.SYS_timer_create; // 222
const SYS_timer_settime = x64_syscalls.SYS_timer_settime; // 223
const SYS_timer_gettime = x64_syscalls.SYS_timer_gettime; // 224
const SYS_timer_getoverrun = x64_syscalls.SYS_timer_getoverrun; // 225
const SYS_timer_delete = x64_syscalls.SYS_timer_delete; // 226
const SYS_clock_settime = x64_syscalls.SYS_clock_settime; // 227
const SYS_clock_gettime = x64_syscalls.SYS_clock_gettime; // 228
const SYS_clock_getres = x64_syscalls.SYS_clock_getres; // 229
const SYS_clock_nanosleep = x64_syscalls.SYS_clock_nanosleep; // 230
const SYS_exit_group = x64_syscalls.SYS_exit_group; // 231
const SYS_epoll_wait = x64_syscalls.SYS_epoll_wait; // 232
const SYS_epoll_ctl = x64_syscalls.SYS_epoll_ctl; // 233
const SYS_tgkill = x64_syscalls.SYS_tgkill; // 234
const SYS_utimes = x64_syscalls.SYS_utimes; // 235
const SYS_vserver = x64_syscalls.SYS_vserver; // 236
const SYS_mbind = x64_syscalls.SYS_mbind; // 237
const SYS_set_mempolicy = x64_syscalls.SYS_set_mempolicy; // 238
const SYS_get_mempolicy = x64_syscalls.SYS_get_mempolicy; // 239
const SYS_mq_open = x64_syscalls.SYS_mq_open; // 240
const SYS_mq_unlink = x64_syscalls.SYS_mq_unlink; // 241
const SYS_mq_timedsend = x64_syscalls.SYS_mq_timedsend; // 242
const SYS_mq_timedreceive = x64_syscalls.SYS_mq_timedreceive; // 243
const SYS_mq_notify = x64_syscalls.SYS_mq_notify; // 244
const SYS_mq_getsetattr = x64_syscalls.SYS_mq_getsetattr; // 245
const SYS_kexec_load = x64_syscalls.SYS_kexec_load; // 246
const SYS_waitid = x64_syscalls.SYS_waitid; // 247
const SYS_add_key = x64_syscalls.SYS_add_key; // 248
const SYS_request_key = x64_syscalls.SYS_request_key; // 249
const SYS_keyctl = x64_syscalls.SYS_keyctl; // 250
const SYS_ioprio_set = x64_syscalls.SYS_ioprio_set; // 251
const SYS_ioprio_get = x64_syscalls.SYS_ioprio_get; // 252
const SYS_inotify_init = x64_syscalls.SYS_inotify_init; // 253
const SYS_inotify_add_watch = x64_syscalls.SYS_inotify_add_watch; // 254
const SYS_inotify_rm_watch = x64_syscalls.SYS_inotify_rm_watch; // 255
const SYS_migrate_pages = x64_syscalls.SYS_migrate_pages; // 256
const SYS_openat = x64_syscalls.SYS_openat; // 257
const SYS_mkdirat = x64_syscalls.SYS_mkdirat; // 258
const SYS_mknodat = x64_syscalls.SYS_mknodat; // 259
const SYS_fchownat = x64_syscalls.SYS_fchownat; // 260
const SYS_futimesat = x64_syscalls.SYS_futimesat; // 261
const SYS_newfstatat = x64_syscalls.SYS_newfstatat; // 262
const SYS_unlinkat = x64_syscalls.SYS_unlinkat; // 263
const SYS_renameat = x64_syscalls.SYS_renameat; // 264
const SYS_linkat = x64_syscalls.SYS_linkat; // 265
const SYS_symlinkat = x64_syscalls.SYS_symlinkat; // 266
const SYS_readlinkat = x64_syscalls.SYS_readlinkat; // 267
const SYS_fchmodat = x64_syscalls.SYS_fchmodat; // 268
const SYS_faccessat = x64_syscalls.SYS_faccessat; // 269
const SYS_pselect6 = x64_syscalls.SYS_pselect6; // 270
const SYS_ppoll = x64_syscalls.SYS_ppoll; // 271
const SYS_unshare = x64_syscalls.SYS_unshare; // 272
const SYS_set_robust_list = x64_syscalls.SYS_set_robust_list; // 273
const SYS_get_robust_list = x64_syscalls.SYS_get_robust_list; // 274
const SYS_splice = x64_syscalls.SYS_splice; // 275
const SYS_tee = x64_syscalls.SYS_tee; // 276
const SYS_sync_file_range = x64_syscalls.SYS_sync_file_range; // 277
const SYS_vmsplice = x64_syscalls.SYS_vmsplice; // 278
const SYS_move_pages = x64_syscalls.SYS_move_pages; // 279
const SYS_utimensat = x64_syscalls.SYS_utimensat; // 280
const SYS_epoll_pwait = x64_syscalls.SYS_epoll_pwait; // 281
const SYS_signalfd = x64_syscalls.SYS_signalfd; // 282
const SYS_timerfd_create = x64_syscalls.SYS_timerfd_create; // 283
const SYS_eventfd = x64_syscalls.SYS_eventfd; // 284
const SYS_fallocate = x64_syscalls.SYS_fallocate; // 285
const SYS_timerfd_settime = x64_syscalls.SYS_timerfd_settime; // 286
const SYS_timerfd_gettime = x64_syscalls.SYS_timerfd_gettime; // 287
const SYS_accept4 = x64_syscalls.SYS_accept4; // 288
const SYS_signalfd4 = x64_syscalls.SYS_signalfd4; // 289
const SYS_eventfd2 = x64_syscalls.SYS_eventfd2; // 290
const SYS_epoll_create1 = x64_syscalls.SYS_epoll_create1; // 291
const SYS_dup3 = x64_syscalls.SYS_dup3; // 292
const SYS_pipe2 = x64_syscalls.SYS_pipe2; // 293
const SYS_inotify_init1 = x64_syscalls.SYS_inotify_init1; // 294
const SYS_preadv = x64_syscalls.SYS_preadv; // 295
const SYS_pwritev = x64_syscalls.SYS_pwritev; // 296
const SYS_rt_tgsigqueueinfo = x64_syscalls.SYS_rt_tgsigqueueinfo; // 297
const SYS_perf_event_open = x64_syscalls.SYS_perf_event_open; // 298
const SYS_recvmmsg = x64_syscalls.SYS_recvmmsg; // 299
const SYS_fanotify_init = x64_syscalls.SYS_fanotify_init; // 300
const SYS_fanotify_mark = x64_syscalls.SYS_fanotify_mark; // 301
const SYS_prlimit64 = x64_syscalls.SYS_prlimit64; // 302
const SYS_name_to_handle_at = x64_syscalls.SYS_name_to_handle_at; // 303
const SYS_open_by_handle_at = x64_syscalls.SYS_open_by_handle_at; // 304
const SYS_clock_adjtime = x64_syscalls.SYS_clock_adjtime; // 305
const SYS_syncfs = x64_syscalls.SYS_syncfs; // 306
const SYS_sendmmsg = x64_syscalls.SYS_sendmmsg; // 307
const SYS_setns = x64_syscalls.SYS_setns; // 308
const SYS_getcpu = x64_syscalls.SYS_getcpu; // 309
const SYS_process_vm_readv = x64_syscalls.SYS_process_vm_readv; // 310
const SYS_process_vm_writev = x64_syscalls.SYS_process_vm_writev; // 311
const SYS_kcmp = x64_syscalls.SYS_kcmp; // 312
const SYS_finit_module = x64_syscalls.SYS_finit_module; // 313
const SYS_sched_setattr = x64_syscalls.SYS_sched_setattr; // 314
const SYS_sched_getattr = x64_syscalls.SYS_sched_getattr; // 315
const SYS_renameat2 = x64_syscalls.SYS_renameat2; // 316
const SYS_seccomp = x64_syscalls.SYS_seccomp; // 317
const SYS_getrandom = x64_syscalls.SYS_getrandom; // 318
const SYS_memfd_create = x64_syscalls.SYS_memfd_create; // 319
const SYS_kexec_file_load = x64_syscalls.SYS_kexec_file_load; // 320
const SYS_bpf = x64_syscalls.SYS_bpf; // 321
const SYS_execveat = x64_syscalls.SYS_execveat; // 322
const SYS_userfaultfd = x64_syscalls.SYS_userfaultfd; // 323
const SYS_membarrier = x64_syscalls.SYS_membarrier; // 324
const SYS_mlock2 = x64_syscalls.SYS_mlock2; // 325
const SYS_copy_file_range = x64_syscalls.SYS_copy_file_range; // 326
const SYS_preadv2 = x64_syscalls.SYS_preadv2; // 327
const SYS_pwritev2 = x64_syscalls.SYS_pwritev2; // 328
const SYS_pkey_mprotect = x64_syscalls.SYS_pkey_mprotect; // 329
const SYS_pkey_alloc = x64_syscalls.SYS_pkey_alloc; // 330
const SYS_pkey_free = x64_syscalls.SYS_pkey_free; // 331
const SYS_statx = x64_syscalls.SYS_statx; // 332
const SYS_io_pgetevents = x64_syscalls.SYS_io_pgetevents; // 333
const SYS_rseq = x64_syscalls.SYS_rseq; // 334
const SYS_pidfd_send_signal = x64_syscalls.SYS_pidfd_send_signal; // 424
const SYS_io_uring_setup = x64_syscalls.SYS_io_uring_setup; // 425
const SYS_io_uring_enter = x64_syscalls.SYS_io_uring_enter; // 426
const SYS_io_uring_register = x64_syscalls.SYS_io_uring_register; // 427
const SYS_open_tree = x64_syscalls.SYS_open_tree; // 428
const SYS_move_mount = x64_syscalls.SYS_move_mount; // 429
const SYS_fsopen = x64_syscalls.SYS_fsopen; // 430
const SYS_fsconfig = x64_syscalls.SYS_fsconfig; // 431
const SYS_fsmount = x64_syscalls.SYS_fsmount; // 432
const SYS_fspick = x64_syscalls.SYS_fspick; // 433
const SYS_pidfd_open = x64_syscalls.SYS_pidfd_open; // 434
const SYS_clone3 = x64_syscalls.SYS_clone3; // 435
const SYS_close_range = x64_syscalls.SYS_close_range; // 436
const SYS_openat2 = x64_syscalls.SYS_openat2; // 437
const SYS_pidfd_getfd = x64_syscalls.SYS_pidfd_getfd; // 438
const SYS_faccessat2 = x64_syscalls.SYS_faccessat2; // 439
const SYS_process_madvise = x64_syscalls.SYS_process_madvise; // 440
const SYS_epoll_pwait2 = x64_syscalls.SYS_epoll_pwait2; // 441
const SYS_mount_setattr = x64_syscalls.SYS_mount_setattr; // 442
const SYS_quotactl_fd = x64_syscalls.SYS_quotactl_fd; // 443
const SYS_landlock_create_ruleset = x64_syscalls.SYS_landlock_create_ruleset; // 444
const SYS_landlock_add_rule = x64_syscalls.SYS_landlock_add_rule; // 445
const SYS_landlock_restrict_self = x64_syscalls.SYS_landlock_restrict_self; // 446
const SYS_memfd_secret = x64_syscalls.SYS_memfd_secret; // 447
const SYS_process_mrelease = x64_syscalls.SYS_process_mrelease; // 448
const SYS_futex_waitv = x64_syscalls.SYS_futex_waitv; // 449
const SYS_set_mempolicy_home_node = x64_syscalls.SYS_set_mempolicy_home_node; // 450
const SYS_cachestat = x64_syscalls.SYS_cachestat; // 451
const SYS_fchmodat2 = x64_syscalls.SYS_fchmodat2; // 452
const SYS_map_shadow_stack = x64_syscalls.SYS_map_shadow_stack; // 453
const SYS_futex_wake = x64_syscalls.SYS_futex_wake; // 454
const SYS_futex_wait = x64_syscalls.SYS_futex_wait; // 455
const SYS_futex_requeue = x64_syscalls.SYS_futex_requeue; // 456
const SYS_statmount = x64_syscalls.SYS_statmount; // 457
const SYS_listmount = x64_syscalls.SYS_listmount; // 458
const SYS_lsm_get_self_attr = x64_syscalls.SYS_lsm_get_self_attr; // 459
const SYS_lsm_set_self_attr = x64_syscalls.SYS_lsm_set_self_attr; // 460
const SYS_lsm_list_modules = x64_syscalls.SYS_lsm_list_modules; // 461
const SYS_mseal = x64_syscalls.SYS_mseal; // 462
const SYS_setxattrat = x64_syscalls.SYS_setxattrat; // 463
const SYS_getxattrat = x64_syscalls.SYS_getxattrat; // 464
const SYS_listxattrat = x64_syscalls.SYS_listxattrat; // 465
const SYS_removexattrat = x64_syscalls.SYS_removexattrat; // 466

// ─── RFLAGS bit positions ───
const RFL_CF = x64_decoder.RFL_CF;
const RFL_PF = x64_decoder.RFL_PF;
const RFL_AF = x64_decoder.RFL_AF;
const RFL_ZF = x64_decoder.RFL_ZF;
const RFL_SF = x64_decoder.RFL_SF;
const RFL_OF = x64_decoder.RFL_OF;
const RFL_DF: u32 = 1 << 10;

const STACK_SIZE: u64 = 1024 * 1024; // 1 MB stack
const MEM_SIZE: u64 = 64 * 1024 * 1024; // 64 MB total address space
const MEM_BASE: u64 = 0x1000000;
const SYNTHETIC_INIT_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF00;
const SYNTHETIC_MAIN_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF08;
const TRACE_BUFFER_LEN: usize = 256;
const MAX_WINDOWS_IMPORT_STUBS: usize = 8192;
const MAX_WINDOWS_FILE_HANDLES: usize = 256;
const MAX_WINDOWS_FIND_HANDLES: usize = 64;
const MAX_WINDOWS_VOLUME_HANDLES: usize = 8;
const MAX_WINDOWS_FILE_MAPPINGS: usize = 16;
const MAX_WINDOWS_MEMORY_VIEWS: usize = 64;
const MAX_WINDOWS_VIRTUAL_ALLOCATIONS: usize = 64;
pub const WINDOWS_EXECUTABLE_RANGE_CAPACITY: usize = 96;
const MAX_WINDOWS_EXECUTABLE_RANGES: usize = WINDOWS_EXECUTABLE_RANGE_CAPACITY;
// The table starts large enough to keep the common PE bootstrap allocation
// path cheap, but it must not be a correctness limit.  The PE heap itself is
// a monotonic guest range and can outlive this initial bookkeeping capacity
// by many frame iterations.
const INITIAL_WINDOWS_HEAP_ALLOCATIONS: usize = 65536;
/// A freed PE heap block waits this long before it can be handed out again.
/// Windows' heap does not hand a block straight back to the next caller of
/// the same size and zero it, and a stale pointer's late read or a second
/// free lands on the old contents there. Immediate LIFO reuse made both land
/// on a live object instead (2026-09-22: a render-pass bucket array held 1,
/// a waited XObject's vtable pointer pointed into the heap).
const WINDOWS_HEAP_QUARANTINE_BLOCKS: usize = 262144;
const WINDOWS_HEAP_QUARANTINE_BYTES: u64 = 192 * 1024 * 1024;
/// Candidates a reuse inspects in one size bin before bumping instead, so an
/// alignment the bin's blocks do not meet cannot make an allocation linear.
const WINDOWS_HEAP_BIN_SCAN: usize = 8;
const WINDOWS_HEAP_ANOMALY_LOG_LIMIT: u64 = 16;

/// Exact-size free blocks, oldest first. `head` advances as blocks are
/// taken; the consumed prefix is dropped once it is half the list.
const WindowsHeapBin = struct {
    indices: std.ArrayListUnmanaged(usize) = .empty,
    head: usize = 0,

    fn available(self: *const WindowsHeapBin) usize {
        return self.indices.items.len - self.head;
    }

    pub fn compact(self: *WindowsHeapBin) void {
        if (self.head == 0 or self.head * 2 < self.indices.items.len) return;
        const remaining = self.indices.items.len - self.head;
        std.mem.copyForwards(usize, self.indices.items[0..remaining], self.indices.items[self.head..]);
        self.indices.shrinkRetainingCapacity(remaining);
        self.head = 0;
    }
};
const MAX_WINDOWS_INITTERM_FRAMES: usize = 16;
const MAX_WINDOWS_INITTERM_ENTRIES: u64 = 1 << 20;
// Xenia's UCRT bootstrap registers one callback for many of its C++ runtime
// objects before the title reaches its first frame.  128 was an accidental
// implementation limit: the observed PE image registers 746 normal
// callbacks, so the limit turned valid guest function addresses into
// `errno_t` failures and a warning storm.  Keep the table bounded, but leave
// enough room for a large PE's static-destructor set without using host
// pointers or allocator-backed callback state in the hot import path.
const MAX_WINDOWS_CRT_ATEXIT_CALLBACKS: usize = 4096;
const MAX_WINDOWS_QSORT_FRAMES: usize = 8;
const MAX_WINDOWS_QSORT_ELEMENT_BYTES: usize = 4096;
const MAX_WINDOWS_QSORT_ELEMENTS: u64 = 1 << 20;
const MAX_WINDOWS_BSEARCH_FRAMES: usize = 8;
const MAX_WINDOWS_BSEARCH_ELEMENTS: u64 = 1 << 20;
/// Threads Rosette holds at once. When the table is full, a new thread takes
/// the slot of a finished one, so this bounds how many threads are alive
/// together, not how many a run can create.
const MAX_WINDOWS_GUEST_THREADS: usize = 64;
const MAX_WINDOWS_SRW_LOCKS: usize = 256;
/// Critical sections held or waited on at once. A record exists only while
/// its section is held or contended; a free, uncontended section has none.
const MAX_WINDOWS_CRITICAL_SECTIONS: usize = 256;
/// Events, mutexes, semaphores and thread handles alive at once. CloseHandle
/// frees a slot, so this bounds what a title holds, not what it creates.
const MAX_WINDOWS_WAIT_OBJECTS: usize = 2048;
/// MinGW's ETIMEDOUT: what its pthread_cond_timedwait returns on expiry.
const WINDOWS_PTHREAD_ETIMEDOUT: u64 = 138;
/// Distinct call sites of timed condition waits a run keeps.
const WINDOWS_TIMED_WAIT_SITE_CAPACITY: usize = 16;
/// The first few deadline expiries carry the full wait context. After that the
/// aggregate/site counters remain active, but the recurring poll cannot turn
/// the log into one line per half-second.
const WINDOWS_TIMED_CONDITION_TIMEOUT_SAMPLE_LIMIT: u8 = 10;

/// One place in the guest that makes timed condition waits, and how they end.
const WindowsTimedWaitSite = struct {
    caller: u64 = 0,
    first_thread_slot_plus_one: u8 = 0,
    waits: u64 = 0,
    timeouts: u64 = 0,
    signalled: u64 = 0,
    immediate: u64 = 0,
    last_milliseconds: u64 = 0,
    last_condition: u64 = 0,
    last_mutex: u64 = 0,
    last_thread_handle: u64 = 0,
    last_thread_id: u64 = 0,
};

const WindowsTimedWaitClassification = enum {
    no_timeout,
    short_periodic_poll_candidate,
    possible_lost_wakeup,
    mixed_timeout_signal,

    pub fn label(self: WindowsTimedWaitClassification) []const u8 {
        return switch (self) {
            .no_timeout => "no_timeout",
            .short_periodic_poll_candidate => "short_periodic_poll_candidate",
            .possible_lost_wakeup => "possible_lost_wakeup",
            .mixed_timeout_signal => "mixed_timeout_signal",
        };
    }

    pub fn action(self: WindowsTimedWaitClassification) []const u8 {
        return switch (self) {
            .no_timeout => "no timeout evidence yet",
            .short_periodic_poll_candidate => "correlate the caller with the optional-service poll; this is not a graphics blocker unless a producer depends on this condition",
            .possible_lost_wakeup => "find the missing signal or broadcast before changing the timeout",
            .mixed_timeout_signal => "inspect signal ordering and the condition owner for a race or an intentionally periodic wait",
        };
    }
};

fn classifyWindowsTimedWaitSite(site: WindowsTimedWaitSite) WindowsTimedWaitClassification {
    if (site.timeouts == 0) return .no_timeout;
    const timeout_dominates = site.timeouts >= 8 and
        (site.signalled == 0 or site.timeouts >= site.signalled +| site.signalled +| site.signalled +| site.signalled);
    if (site.last_milliseconds != 0 and site.last_milliseconds <= 2_000 and timeout_dominates) {
        return .short_periodic_poll_candidate;
    }
    if (site.signalled == 0) return .possible_lost_wakeup;
    return .mixed_timeout_signal;
}

fn windowsTimedWaitPercent(part: u64, total: u64) u8 {
    if (total == 0) return 0;
    return @intCast(@min(@as(u64, 100), (part *| 100) / total));
}

fn instructionRate(count: u64, elapsed_ns: u64) u64 {
    if (elapsed_ns == 0) return 0;
    return @intCast(@min(@as(u128, std.math.maxInt(u64)), @as(u128, count) * 1_000_000_000 / elapsed_ns));
}

test "instruction-rate reporting does not saturate on multi-billion-instruction runs" {
    try testing.expectEqual(@as(u64, 14_249_303), instructionRate(25_762_741_519, 1_808_000_000_000));
    try testing.expectEqual(@as(u64, 1), instructionRate(1, 1_000_000_000));
    try testing.expectEqual(@as(u64, 0), instructionRate(1, 0));
}
/// Clock reads inside one worker slice that make the slice a poll.
const WINDOWS_CLOCK_POLL_YIELD_READS: u32 = 16;
/// Instructions, owner and workers together, between two run heartbeats.
const WINDOWS_RUN_HEARTBEAT_INSTRUCTIONS: u64 = 1_000_000_000;
/// The guest's wall clock starts at 2026-01-01T00:00:00Z, as a FILETIME.
/// windows_runtime answers GetSystemTimeAsFileTime from `windowsGuestFileTime`.
const WINDOWS_GUEST_FILETIME_BASE: u64 = 134_116_992_000_000_000;
/// 1970-01-01 as a FILETIME: the offset MinGW subtracts to get Unix time.
const WINDOWS_FILETIME_UNIX_EPOCH: u64 = 116_444_736_000_000_000;
const WINDOWS_TLS_SLOT_COUNT: usize = 512;
const WINDOWS_GUEST_THREAD_STACK_SIZE: u64 = 1024 * 1024;
/// Xenia asks for a 16 MiB host stack for every guest thread (`XThread`:
/// "Allocate a big host stack"): the x64 backend turns guest branches into
/// host calls, so guest code that tail-chains between functions grows the
/// host stack. An 8 MiB cap gave those threads half of what they asked for,
/// and a worker stack is a heap block with other heap blocks below it.
const WINDOWS_GUEST_THREAD_MAX_STACK_SIZE: u64 = 64 * 1024 * 1024;
/// No-access pages under every worker stack. Without them an overflow wrote
/// silently into whatever heap object sat below the stack; with them the
/// first touch stops the run as a named stack overflow, as Windows would.
const WINDOWS_GUEST_THREAD_STACK_GUARD: u64 = 256 * 1024;
const WINDOWS_PAGE_SIZE: u64 = 0x1000;
const WINDOWS_TEB_BYTES: u64 = 0x2000;
const WINDOWS_TLS_BLOCK_BYTES: u64 = 0x11000;
const WINDOWS_TEB_STACK_BASE_OFFSET: u64 = 0x08;
const WINDOWS_TEB_STACK_LIMIT_OFFSET: u64 = 0x10;
const WINDOWS_TEB_SELF_OFFSET: u64 = 0x30;
const WINDOWS_TEB_CLIENT_ID_PROCESS_OFFSET: u64 = 0x40;
const WINDOWS_TEB_CLIENT_ID_THREAD_OFFSET: u64 = 0x48;
const WINDOWS_TEB_TLS_POINTER_OFFSET: u64 = 0x58;
const WINDOWS_TEB_PEB_OFFSET: u64 = 0x60;
const WINDOWS_TEB_LAST_ERROR_OFFSET: u64 = 0x68;
// Keep a worker slice short enough that a startup worker cannot monopolize
// the single interpreter while the owner thread is waiting for it to publish
// state. This is a scheduling bound, not a correctness timeout: the worker
// context is saved and resumed at the next explicit cooperative point.
const WINDOWS_GUEST_THREAD_SERVICE_SLICE: u64 = 10_000;
/// Where in a worker slice the spin probe records the machine state, and how
/// many instructions after it a repeat of that exact state is looked for. A
/// poll loop returns to the same instruction with the same registers every
/// iteration; a compute loop advances a pointer or a count and never does.
const WINDOWS_GUEST_SPIN_PROBE_AT: u64 = 1024;
const WINDOWS_GUEST_SPIN_PROBE_SPAN: u64 = 256;
/// The most turns a spinning thread gives away in a row.
const WINDOWS_GUEST_SPIN_MAX_BACKOFF: u8 = 8;
const WINDOWS_GUEST_THREAD_SERVICE_OWNER_STRIDE: u64 = 1_000;
// A PE title can spend millions of owner-thread instructions in a compute
// routine that contains no PAUSE, wait, or message-pump call.  Keep worker
// service bounded, but do not wait for the progress watchdog to classify the
// whole process as stalled before giving a queued worker a turn.
const WINDOWS_GUEST_THREAD_SCHEDULER_QUANTUM: u64 = 1_000_000;

/// The frequency Rosetta publishes to the guest from
/// `QueryPerformanceFrequency`. Re-exported from `guest_clock.zig`, which
/// owns the counter and the reasoning behind what it counts.
pub const WINDOWS_GUEST_CLOCK_HZ: u64 = guest_clock.hz;
const WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE: u64 = guest_clock.sample_stride;

/// Translated instructions that count as one interpreted step on a parallel
/// executor's private clock cadence, so a translated thread samples the host
/// clock about every 16K instructions instead of at every exit from
/// translated code. That exit took the shared clock mutex every time, and the
/// stride it filled was shared by every thread, so nearly every exit also
/// read the host clock under the lock: on 2026-09-30 `Mutex.lock` and
/// `mach_absolute_time` were 7.3% and 5.7% of Halo 3's main thread.
const WINDOWS_GUEST_CLOCK_TRANSLATED_PER_STEP: u64 = 32;

/// A condition wait is ordinary immediately after it is entered: its
/// predicate may be about to become true.  Escalate only after a meaningful
/// amount of guest work or guest time has passed, so the forensic trigger
/// describes a sustained absence of notification rather than startup noise.
const WINDOWS_WAIT_ESCALATION_MIN_AGE_STEPS: u64 = 1_000_000;
const WINDOWS_WAIT_ESCALATION_MIN_AGE_TICKS: u64 = WINDOWS_GUEST_CLOCK_HZ / 10;

/// Guest clock ticks in one guest millisecond, which is the unit every Win32
/// timeout is expressed in.
///
/// This used to be `WINDOWS_GUEST_THREAD_SCHEDULER_QUANTUM`, so a timeout of
/// one millisecond became a deadline a million *owner* steps away. Rosetta
/// was telling the guest its performance counter ran at a megahertz while
/// charging it a gigahertz to sleep - a factor of a thousand, against a
/// counter that measures a different thing.
///
/// On the 2026-09-12 run the owner advanced about 262,000 steps a second, so
/// Xenia's frame limiter asking for a 100 ms sleep was parked for a hundred
/// million owner steps, roughly six minutes of real time. It managed about
/// four loop iterations in a twenty-nine minute run and never reached
/// `MarkVblank` at all, which is why the guest-output chain's wall was a
/// display clock that had never ticked.
pub const WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND: u64 = guest_clock.ticks_per_millisecond;
// A Windows x64 callee receives a return address at [RSP] and owns the
// caller-provided 32-byte home area immediately above it.  The synthetic
// thread entry used to put RSP at the very end of the allocated stack, which
// made a legal store to [RBP+0x10] land in the next guest heap allocation.
// Keep a small entry cushion inside the allocation so the home area and the
// first stack arguments never cross the stack/heap boundary.
const WINDOWS_GUEST_THREAD_ENTRY_RESERVE: u64 = 0x100;
const SYNTHETIC_WINDOWS_THREAD_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF28;
const SYNTHETIC_WINDOWS_MESSAGE_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF30;
const SYNTHETIC_WINDOWS_AUDIO_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF40;
const SYNTHETIC_WINDOWS_CRT_EXIT_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF58;
/// Where a guest vectored exception handler returns to. See
/// `enterWindowsExceptionDispatch`: the frame it returns through is carried
/// on the faulting thread's own stack, so a thread switch mid-handler cannot
/// hand one thread's exception to another.
const SYNTHETIC_WINDOWS_EXCEPTION_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF50;

/// Every synthetic return address the PE route recognises sits in the top
/// 256 bytes of the address space. `step` asks one comparison against this
/// floor before paying for `handleSyntheticRip`'s chain of eleven; the
/// comptime check below is what keeps a new synthetic address from being
/// added below the floor and silently never handled.
const SYNTHETIC_RIP_FLOOR: u64 = 0xFFFF_FFFF_FFFF_FF00;
/// The return address of a user APC routine Rosette is running inside an
/// alertable wait. The executor either starts the next queued APC or
/// completes the wait with WAIT_IO_COMPLETION.
const SYNTHETIC_WINDOWS_APC_RETURN: u64 = 0xFFFF_FFFF_FFFF_FF60;
const WINDOWS_APC_QUEUE_CAPACITY: usize = 16;
const WINDOWS_WAIT_IO_COMPLETION: u64 = 0xC0;

/// User APCs queued to one thread (`QueueUserAPC`), and the frame of the
/// delivery in progress. Windows runs them only inside an alertable wait,
/// on the thread they were queued to, oldest first, and the wait then
/// returns WAIT_IO_COMPLETION.
const WindowsApcQueue = struct {
    routines: [WINDOWS_APC_QUEUE_CAPACITY]u64 = @splat(0),
    parameters: [WINDOWS_APC_QUEUE_CAPACITY]u64 = @splat(0),
    head: u8 = 0,
    count: u8 = 0,
    delivering: bool = false,
    saved_rsp: u64 = 0,
    continuation: u64 = 0,
    continuation_direct: bool = false,

    pub fn push(self: *WindowsApcQueue, routine: u64, parameter: u64) bool {
        if (self.count >= WINDOWS_APC_QUEUE_CAPACITY) return false;
        const slot = (@as(usize, self.head) + self.count) % WINDOWS_APC_QUEUE_CAPACITY;
        self.routines[slot] = routine;
        self.parameters[slot] = parameter;
        self.count += 1;
        return true;
    }

    pub fn pop(self: *WindowsApcQueue) ?struct { routine: u64, parameter: u64 } {
        if (self.count == 0) return null;
        const slot = self.head;
        self.head = @intCast((@as(usize, self.head) + 1) % WINDOWS_APC_QUEUE_CAPACITY);
        self.count -= 1;
        return .{ .routine = self.routines[slot], .parameter = self.parameters[slot] };
    }
};

comptime {
    const synthetic_addresses = [_]u64{
        SYNTHETIC_WINDOWS_APC_RETURN,
        SYNTHETIC_INIT_RETURN,
        SYNTHETIC_MAIN_RETURN,
        SYNTHETIC_WINDOWS_THREAD_RETURN,
        SYNTHETIC_WINDOWS_MESSAGE_RETURN,
        SYNTHETIC_WINDOWS_AUDIO_RETURN,
        SYNTHETIC_WINDOWS_CRT_EXIT_RETURN,
        SYNTHETIC_WINDOWS_EXCEPTION_RETURN,
        x64_linux_runtime.SYNTHETIC_PTHREAD_ONCE_RETURN,
        x64_linux_runtime.SYNTHETIC_INITTERM_RETURN,
        x64_linux_runtime.SYNTHETIC_QSORT_RETURN,
        x64_linux_runtime.SYNTHETIC_BSEARCH_RETURN,
    };
    for (synthetic_addresses, 0..) |address, index| {
        if (address < SYNTHETIC_RIP_FLOOR) @compileError("a synthetic return address sits below SYNTHETIC_RIP_FLOOR, so step would never reach its handler");
        for (synthetic_addresses[0..index]) |prior| {
            if (address == prior) @compileError("synthetic return addresses must be unique");
        }
    }
}

/// A half-open address box `[low, low + span)` kept as two words so that
/// membership is one wrapping subtraction and one compare on the
/// per-instruction path. `span == 0` is the empty box.
const HookBox = struct {
    low: u64 = 0,
    span: u64 = 0,

    pub inline fn contains(self: HookBox, address: u64) bool {
        return address -% self.low < self.span;
    }

    pub fn widen(self: *HookBox, address: u64) void {
        if (self.span == 0) {
            self.low = address;
            self.span = 1;
            return;
        }
        const old_high = self.low +| self.span;
        const new_low = @min(self.low, address);
        const new_high = @max(old_high, address +| 1);
        self.low = new_low;
        self.span = new_high -| new_low;
    }

    pub fn widenRange(self: *HookBox, base: u64, length: u64) void {
        if (length == 0) return;
        self.widen(base);
        self.widen(base +| (length - 1));
    }

    /// Whether `[address, address + count)` shares any byte with the box.
    pub inline fn overlaps(self: HookBox, address: u64, count: u64) bool {
        return address < self.low +| self.span and address +| count > self.low;
    }
};

/// A small exact-address set for sparse hooks.  A HookBox is the right
/// representation for an executable range, but it is a very poor fit for a
/// handful of entry points that live far apart: widening the box turns every
/// instruction between the first and last entry point into a false positive.
/// Keep this bounded because the compatibility layer deliberately exposes a
/// fixed, audited set of entry points.
const HookPoints = struct {
    addresses: [7]u64 = @splat(0),
    count: u8 = 0,

    pub inline fn contains(self: HookPoints, address: u64) bool {
        return (self.count >= 1 and self.addresses[0] == address) or
            (self.count >= 2 and self.addresses[1] == address) or
            (self.count >= 3 and self.addresses[2] == address) or
            (self.count >= 4 and self.addresses[3] == address) or
            (self.count >= 5 and self.addresses[4] == address) or
            (self.count >= 6 and self.addresses[5] == address) or
            (self.count >= 7 and self.addresses[6] == address);
    }

    pub fn add(self: *HookPoints, address: u64) void {
        if (address == 0 or self.contains(address)) return;
        if (@as(usize, self.count) >= self.addresses.len) return;
        self.addresses[@as(usize, self.count)] = address;
        self.count += 1;
    }
};

test "hook boxes admit every recorded address and reject the rest cheaply" {
    var box: HookBox = .{};
    try std.testing.expect(!box.contains(0));
    try std.testing.expect(!box.overlaps(0, 16));
    box.widen(0x1000);
    try std.testing.expect(box.contains(0x1000));
    try std.testing.expect(!box.contains(0x0fff));
    try std.testing.expect(!box.contains(0x1001));
    box.widen(0x0800);
    box.widen(0x2000);
    try std.testing.expect(box.contains(0x0800) and box.contains(0x1000) and box.contains(0x2000));
    try std.testing.expect(box.contains(0x1234));
    try std.testing.expect(!box.contains(0x2001) and !box.contains(0x07ff));
    var ranges: HookBox = .{};
    ranges.widenRange(0x14000_1000, 0x1000);
    ranges.widenRange(0x14001_0000, 0x2000);
    try std.testing.expect(ranges.overlaps(0x14000_0ff8, 16));
    try std.testing.expect(ranges.overlaps(0x14001_1fff, 8));
    try std.testing.expect(!ranges.overlaps(0x14001_2000, 8));
    try std.testing.expect(!ranges.overlaps(0x14000_0000, 0x1000));
    // A store wider than the whole box still overlaps it.
    try std.testing.expect(ranges.overlaps(0x14000_0000, 0x10_0000));
    try std.testing.expect(ranges.widenRange(0, 0) == {});
    try std.testing.expect(!ranges.contains(0));
}

test "sparse hook points do not admit the space between entries" {
    var points: HookPoints = .{};
    points.add(0x14011b6f0);
    points.add(0x140513a10);
    points.add(0x140513914);
    points.add(0x140513b07);
    points.add(0x140513b07);
    try std.testing.expectEqual(@as(u8, 4), points.count);
    try std.testing.expect(points.contains(0x14011b6f0));
    try std.testing.expect(points.contains(0x140513a10));
    try std.testing.expect(points.contains(0x140513914));
    try std.testing.expect(points.contains(0x140513b07));
    try std.testing.expect(!points.contains(0x140300000));
    try std.testing.expect(!points.contains(0));
}

const GUEST_ACCESS_VIOLATION_SITE_CAPACITY: usize = 32;

/// The first protected access an instruction made, held until the
/// instruction finishes so the fault is raised at an instruction boundary.
const GuestAccessViolation = struct {
    address: u64 = 0,
    instruction_rip: u64 = 0,
    /// For a store: the value the instruction tried to write, replayed if
    /// no handler takes the fault.
    value: u64 = 0,
    /// The whole value of a 16-byte vector store (`value` holds its low
    /// eight bytes).
    wide_value: [16]u8 = @splat(0),
    width: u8 = 0,
    is_write: bool = false,
    protection: guest_page_protection.Protection = .accessible,
};

/// One protected page that has faulted, and what became of its faults.
const GuestAccessViolationSite = struct {
    page: u64 = 0,
    protection: guest_page_protection.Protection = .accessible,
    reads: u64 = 0,
    writes: u64 = 0,
    handled: u64 = 0,
    unhandled: u64 = 0,
    first_step: u64 = 0,
    last_rip: u64 = 0,
    last_offset: u64 = 0,
    last_value: u64 = 0,
};
/// Which XMA (APU) registers the title touched, read from the faults its
/// stores to Xenia's no-access aperture at guest 0x7FEA0000 raise.
///
/// Xenia serves the audio decoder's registers the same way as the GPU's:
/// the page is committed no-access, the store faults, and the vectored
/// handler decodes the instruction and calls `XmaDecoder::WriteRegister`.
/// Rosette raises that fault, so it sees every register write with its value
/// before Xenia does - which makes this census independent of whether the
/// build inlined `WriteRegister` into its MMIO thunk. A `Kick` register write
/// is the title asking the decoder for work; without one, no XMA context ever
/// decodes and the mixer has only silence to submit.
const GuestXmaRegisterCensus = struct {
    const capacity: usize = 24;
    const Entry = struct {
        index: u16 = 0,
        writes: u64 = 0,
        reads: u64 = 0,
        first_step: u64 = 0,
        last_step: u64 = 0,
        /// The last value written, byte-swapped to the decoder's view.
        last_value: u32 = 0,
        /// Bits set across every value written to a kick/lock/clear
        /// register: each bit is one hardware context.
        value_union: u32 = 0,
    };
    entries: [capacity]Entry = @splat(.{}),
    count: usize = 0,
    overflow: u64 = 0,
    faults: u64 = 0,
    /// Writes to a `ContextN_Kick` register with at least one bit set.
    kicks: u64 = 0,
    /// Distinct hardware contexts kicked, from the union of kick bits.
    kicked_contexts: u32 = 0,
    locks: u64 = 0,
    clears: u64 = 0,
    context_array_address: u32 = 0,

    /// Register indices from Xenia's `xma_register_table.inc`, dword units.
    pub const context_array_address_index: u16 = 0x0600;
    pub const current_context_index: u16 = 0x0606;
    pub const next_context_index: u16 = 0x0607;
    pub const kick_first: u16 = 0x0650;
    pub const lock_first: u16 = 0x0690;
    pub const clear_first: u16 = 0x06A0;
    pub const contexts_per_register: u32 = 32;

    pub fn registerName(index: u16) []const u8 {
        return switch (index) {
            context_array_address_index => "ContextArrayAddress",
            current_context_index => "CurrentContextIndex",
            next_context_index => "NextContextIndex",
            0x0610...0x0619 => "Unknown610",
            0x0620...0x0629 => "Unknown620",
            kick_first...kick_first + 9 => "Kick",
            0x0660...0x0669 => "Unknown660",
            lock_first...lock_first + 9 => "Lock",
            clear_first...clear_first + 9 => "Clear",
            else => "unnamed",
        };
    }

    /// Record one faulting access. `value` is the raw little-endian dword the
    /// guest stored; the decoder byte-swaps it, so this does too.
    pub fn note(self: *GuestXmaRegisterCensus, index: u16, is_write: bool, value: u32, step: u64) void {
        self.faults +|= 1;
        const swapped = @byteSwap(value);
        if (is_write) {
            if (index >= kick_first and index < kick_first + 10) {
                if (swapped != 0) self.kicks +|= 1;
            } else if (index >= lock_first and index < lock_first + 10) {
                self.locks +|= 1;
            } else if (index >= clear_first and index < clear_first + 10) {
                self.clears +|= 1;
            } else if (index == context_array_address_index) {
                self.context_array_address = swapped;
            }
        }
        var slot: ?*Entry = null;
        for (self.entries[0..self.count]) |*entry| {
            if (entry.index == index) {
                slot = entry;
                break;
            }
        }
        if (slot == null) {
            if (self.count == capacity) {
                self.overflow +|= 1;
                return;
            }
            self.entries[self.count] = .{ .index = index, .first_step = step };
            slot = &self.entries[self.count];
            self.count += 1;
        }
        const entry = slot.?;
        entry.last_step = step;
        if (is_write) {
            entry.writes +|= 1;
            entry.last_value = swapped;
            entry.value_union |= swapped;
            if (index >= kick_first and index < kick_first + 10) {
                self.kicked_contexts = self.countKickedContexts();
            }
        } else {
            entry.reads +|= 1;
        }
    }

    fn countKickedContexts(self: *const GuestXmaRegisterCensus) u32 {
        var total: u32 = 0;
        for (self.entries[0..self.count]) |entry| {
            if (entry.index >= kick_first and entry.index < kick_first + 10) total += @popCount(entry.value_union);
        }
        return total;
    }
};

const FrameHostSampleCategory = enum { translated_guest, rosette, vulkan_driver, metal, system, other, unknown };

const FrameHostSampleCounts = struct {
    translated_guest: u64 = 0,
    rosette: u64 = 0,
    vulkan_driver: u64 = 0,
    metal: u64 = 0,
    system: u64 = 0,
    other: u64 = 0,
    unknown: u64 = 0,

    pub fn add(self: *FrameHostSampleCounts, category: FrameHostSampleCategory, amount: u64) void {
        switch (category) {
            .translated_guest => self.translated_guest +|= amount,
            .rosette => self.rosette +|= amount,
            .vulkan_driver => self.vulkan_driver +|= amount,
            .metal => self.metal +|= amount,
            .system => self.system +|= amount,
            .other => self.other +|= amount,
            .unknown => self.unknown +|= amount,
        }
    }
};

/// What a presented frame costs in interpreted instructions, and who spends
/// them, sampled at each `VulkanCommandProcessor::IssueSwap`.
///
/// The frame rate this route reaches is the interpreter's rate divided by
/// this number. Neither half was reported before: the STEP BUDGET line gives
/// the rate, the present chain gives frames per second, and the reader was
/// left to divide. The per-thread split is what says whether the cost is the
/// title's own frame or work running beside it - on 2026-09-17 a third of
/// every frame's budget went to the audio path mixing silence at wall-clock
/// rate while the picture advanced at a third of a frame per second.
const GuestFrameCost = struct {
    pub const window: usize = 32;
    const Thread = struct {
        handle: u64 = 0,
        /// The thread's step counter when it was last sampled.
        snapshot: u64 = 0,
        /// Instructions the thread ran between the first swap and the last.
        since_first_swap: u64 = 0,
    };
    swaps: u64 = 0,
    first_swap_step: u64 = 0,
    last_swap_step: u64 = 0,
    /// Owner-loop steps at the last swap, so the owner's share is measured
    /// on the same edges as the workers'.
    owner_snapshot: u64 = 0,
    owner_since_first_swap: u64 = 0,
    audio_frames_snapshot: u64 = 0,
    recent: [window]u64 = @splat(0),
    recent_count: usize = 0,
    recent_next: usize = 0,
    min_interval: u64 = std.math.maxInt(u64),
    max_interval: u64 = 0,
    audio_frames_since_first_swap: u64 = 0,
    threads: [MAX_WINDOWS_GUEST_THREADS]Thread = @splat(.{}),

    pub fn noteInterval(self: *GuestFrameCost, interval: u64) void {
        self.recent[self.recent_next] = interval;
        self.recent_next = (self.recent_next + 1) % window;
        if (self.recent_count < window) self.recent_count += 1;
        self.min_interval = @min(self.min_interval, interval);
        self.max_interval = @max(self.max_interval, interval);
    }

    pub fn meanRecentInterval(self: *const GuestFrameCost) u64 {
        if (self.recent_count == 0) return 0;
        var total: u64 = 0;
        for (self.recent[0..self.recent_count]) |interval| total +|= interval;
        return total / self.recent_count;
    }

    pub fn totalSinceFirstSwap(self: *const GuestFrameCost) u64 {
        return self.last_swap_step -| self.first_swap_step;
    }
};

/// The front buffer the title asks Xenia to show, as `VdSwap` describes it.
///
/// `VdSwap` copies the Direct3D texture header's fetch constant into the ring
/// as a type-0 write to SHADER_CONSTANT_FETCH_00_0 and follows it with the
/// XE_SWAP packet; `IssueSwap` reads that constant back to pick the front
/// buffer's format, and the format decides which gamma ramp the swap applies:
/// the 256-entry table for 8-bit-per-channel buffers, the piecewise-linear
/// ramp for 10-bit ones. A 10-bit front buffer whose title draws its final
/// pass as 7e3 floating point relies on that ramp to turn bit patterns into
/// intensities, and the ramp is programmed through the DC_LUT registers -
/// which Xenia applies only from type-0 packets, never from the MMIO
/// aperture. So this record answers, from the title's own words, whether the
/// swap is on the ramp-dependent path and whether any ramp write it made
/// could have been applied.
const GuestFrontBuffer = struct {
    pub const dc_lut_first: u32 = 0x1921; // DC_LUT_RW_MODE
    pub const dc_lut_last: u32 = 0x1930; // DC_LUTA_CONTROL
    swaps: u64 = 0,
    fetch: [6]u32 = @splat(0),
    frontbuffer: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    /// Distinct fetch formats seen, as a bitmask over the 6-bit field.
    formats_seen: u64 = 0,
    dc_lut_type0_writes: u64 = 0,

    pub fn note(self: *GuestFrontBuffer, window: *const GpuRingWindow) void {
        self.dc_lut_type0_writes +|= window.dc_lut_type0_writes;
        if (!window.swap_fetch_seen) return;
        self.swaps +|= 1;
        self.fetch = window.swap_fetch;
        if (window.swap_packets != 0) {
            self.frontbuffer = window.swap_frontbuffer;
            self.width = window.swap_width;
            self.height = window.swap_height;
        }
        self.formats_seen |= @as(u64, 1) << @intCast(self.format());
    }

    /// `xe_gpu_texture_fetch_t.format`, dword 1 bits 0-5.
    pub fn format(self: *const GuestFrontBuffer) u6 {
        return @truncate(self.fetch[1]);
    }
    pub fn endianness(self: *const GuestFrontBuffer) u2 {
        return @truncate(self.fetch[1] >> 6);
    }
    pub fn baseAddress(self: *const GuestFrontBuffer) u32 {
        return (self.fetch[1] >> 12) << 12;
    }
    pub fn tiled(self: *const GuestFrontBuffer) bool {
        return (self.fetch[0] >> 31) != 0;
    }
    pub fn pitch(self: *const GuestFrontBuffer) u32 {
        return (self.fetch[0] >> 22) & 0x1FF;
    }
    pub fn fetchWidth(self: *const GuestFrontBuffer) u32 {
        return (self.fetch[2] & 0x1FFF) + 1;
    }
    pub fn fetchHeight(self: *const GuestFrontBuffer) u32 {
        return ((self.fetch[2] >> 13) & 0x1FFF) + 1;
    }

    pub fn formatName(value: u6) []const u8 {
        return switch (value) {
            6 => "k_8_8_8_8",
            7 => "k_2_10_10_10",
            50 => "k_8_8_8_8_AS_16_16_16_16",
            54 => "k_2_10_10_10_AS_16_16_16_16",
            else => "other",
        };
    }

    /// Whether `IssueSwap` takes the piecewise-linear ramp for this format.
    pub fn usesPwlRamp(value: u6) bool {
        return value == 7 or value == 54;
    }
};

const MAX_WINDOWS_WINDOW_CLASSES: usize = 64;
const MAX_WINDOWS_WINDOWS: usize = 128;
const MAX_WINDOWS_MESSAGE_DISPATCH_FRAMES: usize = 8;
const MAX_WINDOWS_AUDIO_CALLBACK_FRAMES: usize = 8;
const MAX_WINDOWS_WAVE_OUT_DEVICES: usize = 4;
const MAX_WINDOWS_WAVE_HEADERS: usize = 16;
pub const WINDOWS_UNRESOLVED_IMPORT_CAPACITY: usize = 32;
/// Win32 WM_PAINT.  The pump synthesizes it from a window's update region
/// instead of holding it in the posted-message ring, matching Win32.
const WINDOWS_WM_PAINT: u32 = 0x000F;

const WINDOWS_GWLP_USERDATA: i64 = -21;
const WINDOWS_GWL_STYLE: i64 = -16;
const WINDOWS_GWL_EXSTYLE: i64 = -20;
const WINDOWS_GCLP_WNDPROC: i64 = -24;

/// Rosette-owned targets returned by a PE import or proc-address query. The
/// target is kept in the emulated state so an indirect call can be routed back
/// to the Windows ABI without modifying the inspected executable.
pub const WindowsImportStub = struct {
    address: u64,
    dll_name: []const u8,
    function_name: []const u8,
    /// The direct PE IAT slot that should contain `address`. Dynamic proc
    /// lookups have no single owning slot and leave this zero.
    iat_address: u64 = 0,
    /// Dynamic GetProcAddress results are kept distinct from the PE's direct
    /// IAT descriptors.  The distinction is diagnostic only; both paths use
    /// the same ABI dispatcher and fallback policy.
    is_dynamic: bool = false,
};

const WindowsImportStubInterior = struct {
    stub: WindowsImportStub,
    offset: u8,
};

const WindowsImportCallsite = struct {
    rip: u64,
    decoded: DecodedInsn,
};

/// A bounded, value-only record for an import Rosetta could not resolve.
///
/// These records deliberately own their text.  The PE parser and dynamic
/// import table are allocator-backed state that is torn down immediately
/// after `RunResult` is produced, while the detailed runner log is written
/// afterwards.  Keeping the first context and the latest repetition context
/// here lets the log explain both the missing symbol and the guest edge that
/// requested it without enabling noisy ABI tracing for every successful call.
pub const WindowsUnresolvedImport = struct {
    dll_name: [128]u8 = [_]u8{0} ** 128,
    dll_name_len: usize = 0,
    function_name: [256]u8 = [_]u8{0} ** 256,
    function_name_len: usize = 0,
    is_dynamic: bool = false,
    stub_address: u64 = 0,
    first_return_rip: u64 = 0,
    first_caller_rip: u64 = 0,
    first_step: u64 = 0,
    first_rsp: u64 = 0,
    first_rcx: u64 = 0,
    first_rdx: u64 = 0,
    first_r8: u64 = 0,
    first_r9: u64 = 0,
    last_return_rip: u64 = 0,
    last_caller_rip: u64 = 0,
    last_step: u64 = 0,
    occurrences: u64 = 0,

    pub fn dllName(self: *const WindowsUnresolvedImport) []const u8 {
        return self.dll_name[0..self.dll_name_len];
    }

    pub fn functionName(self: *const WindowsUnresolvedImport) []const u8 {
        return self.function_name[0..self.function_name_len];
    }
};

const WINDOWS_GUEST_OUTPUT_LINE_CAPACITY: usize = 4096;
const WINDOWS_GUEST_FAILURE_POINT_CAPACITY: usize = 32;
const WINDOWS_GUEST_WARNING_POINT_CAPACITY: usize = 25;
// The old 32-site cap saturated on long PE runs, leaving millions of misses
// in `overflow` with no representative address.  This is still bounded (the
// state grows by only a few dozen KiB) but gives an overnight run enough
// room to distinguish one hot conflict from many unrelated cold fills.
const DECODE_CACHE_MISS_SITE_CAPACITY: usize = 256;
const GPU_DRAW_FAILURE_CAPACITY: usize = 64;

/// A bounded copy of an emulator warning that crossed the PE stdout/stderr
/// boundary. Xenia owns the original logger, so Rosette cannot assume that a
/// std.log observer will see it; the Windows stdio bridge feeds these records
/// explicitly. Keeping the first and latest locations makes a repeated line
/// useful without allowing a noisy title to grow the host log without bound.
const WindowsGuestFailurePoint = struct {
    label: [64:0]u8 = [_:0]u8{0} ** 64,
    owner: [32:0]u8 = [_:0]u8{0} ** 32,
    line: [WINDOWS_GUEST_OUTPUT_LINE_CAPACITY:0]u8 = [_:0]u8{0} ** WINDOWS_GUEST_OUTPUT_LINE_CAPACITY,
    label_len: usize = 0,
    owner_len: usize = 0,
    line_len: usize = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    first_rip: u64 = 0,
    last_rip: u64 = 0,
    occurrences: u64 = 0,

    pub fn labelText(self: *const WindowsGuestFailurePoint) []const u8 {
        return self.label[0..self.label_len];
    }

    pub fn ownerText(self: *const WindowsGuestFailurePoint) []const u8 {
        return self.owner[0..self.owner_len];
    }

    pub fn lineText(self: *const WindowsGuestFailurePoint) []const u8 {
        return self.line[0..self.line_len];
    }
};

const WindowsGuestWarningPoint = struct {
    line: [WINDOWS_GUEST_OUTPUT_LINE_CAPACITY:0]u8 = [_:0]u8{0} ** WINDOWS_GUEST_OUTPUT_LINE_CAPACITY,
    line_len: usize = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    occurrences: u64 = 0,
    /// A known degradation the run survives, rather than an unclassified
    /// warning. Retained on the record so the end-of-run summary can separate
    /// the two instead of quoting one number for both.
    advisory: bool = false,

    pub fn lineText(self: *const WindowsGuestWarningPoint) []const u8 {
        return self.line[0..self.line_len];
    }
};

/// A bounded attribution for one PM4_DRAW_INDX refusal.  Xenia's warning
/// names the packet tuple but not the state that made IssueDraw reject it;
/// retaining the tuple and the execution frontier turns a repeated rendering
/// symptom into a reproducible class instead of one generic warning string.
const GpuDrawFailure = struct {
    index_count: u32 = 0,
    primitive_type: u32 = 0,
    source_select: u32 = 0,
    occurrences: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    first_rip: u64 = 0,
    last_rip: u64 = 0,
};

const GpuDrawTuple = struct {
    index_count: u32,
    primitive_type: u32,
    source_select: u32,
};

/// The PM4 warning only prints the numeric primitive field.  Keep the Xenia
/// names and the first useful next question beside the ledger so a run does
/// not collapse every IssueDraw refusal into "backend unexplained".  The
/// values intentionally mirror `lib/gpu/xenos_registers.zig` and Xenia's
/// `PrimitiveType`; this parser may consume a native Xenia line before the
/// Rosetta PM4 executor has seen the corresponding packet.
const GpuPrimitiveFinding = struct {
    name: []const u8,
    classification: []const u8,
    action: []const u8,
};

fn gpuPrimitiveFinding(raw: u32) GpuPrimitiveFinding {
    return switch (raw) {
        0x00 => .{
            .name = "none",
            .classification = "invalid-or-empty-primitive",
            .action = "inspect the PM4 producer: a draw with PrimitiveType::kNone should not reach IssueDraw",
        },
        0x01 => .{
            .name = "point-list",
            .classification = "point-list-pipeline-or-geometry-shader",
            .action = "inspect the active vertex shader, point-list geometry expansion, host point topology, and pipeline creation result",
        },
        0x02 => .{
            .name = "line-list",
            .classification = "line-list-pipeline-or-shader",
            .action = "inspect the active vertex shader, line-list host topology, index/vertex bindings, and pipeline creation result",
        },
        0x03 => .{
            .name = "line-strip",
            .classification = "line-strip-pipeline-or-shader",
            .action = "inspect the active vertex shader, line-strip host topology, index/vertex bindings, and pipeline creation result",
        },
        0x04 => .{
            .name = "triangle-list",
            .classification = "triangle-list-pipeline-or-resource",
            .action = "capture the active shaders, index/vertex bindings, render targets, and pipeline creation result",
        },
        0x05 => .{
            .name = "triangle-fan",
            .classification = "triangle-fan-pipeline-or-resource",
            .action = "inspect the triangle-fan lowering and the active shader/index/vertex bindings",
        },
        0x06 => .{
            .name = "triangle-strip",
            .classification = "triangle-strip-pipeline-or-resource",
            .action = "capture the active shaders, index/vertex bindings, render targets, and pipeline creation result",
        },
        0x07 => .{
            .name = "triangle-with-w-flags",
            .classification = "triangle-w-flags-lowering",
            .action = "inspect W-flag handling and whether the host pipeline has a supported lowering for this primitive",
        },
        0x08 => .{
            .name = "rectangle-list",
            .classification = "rectangle-list-geometry-shader-compatibility",
            .action = "inspect the rectangle-list fallback and geometry-shader/pipeline compatibility",
        },
        0x09, 0x0A, 0x0B => .{
            .name = "unused-primitive-value",
            .classification = "unsupported-or-corrupt-primitive",
            .action = "inspect the PM4 producer and packet decode: this primitive value is reserved by Xenos",
        },
        0x0C => .{
            .name = "line-loop",
            .classification = "line-loop-lowering",
            .action = "inspect line-loop lowering and the host topology selected for the draw",
        },
        0x0D => .{
            .name = "quad-list",
            .classification = "quad-list-lowering",
            .action = "inspect quad-list lowering and whether the host pipeline has a supported topology",
        },
        0x0E => .{
            .name = "quad-strip",
            .classification = "quad-strip-lowering",
            .action = "inspect quad-strip lowering and whether the host pipeline has a supported topology",
        },
        0x0F => .{
            .name = "polygon",
            .classification = "polygon-lowering",
            .action = "inspect polygon lowering and the active host topology/pipeline result",
        },
        0x10...0x13 => .{
            .name = "2d-copy-rect-list",
            .classification = "2d-copy-primitive-lowering",
            .action = "inspect the 2D copy-rectangle lowering, source/destination surfaces, and copy pipeline result",
        },
        0x14 => .{
            .name = "2d-fill-rect-list",
            .classification = "2d-fill-primitive-lowering",
            .action = "inspect the 2D fill-rectangle lowering, render target state, and pipeline result",
        },
        0x15 => .{
            .name = "2d-line-strip",
            .classification = "2d-line-primitive-lowering",
            .action = "inspect the 2D line lowering and the host line topology/pipeline result",
        },
        0x16 => .{
            .name = "2d-triangle-strip",
            .classification = "2d-triangle-primitive-lowering",
            .action = "inspect the 2D triangle lowering, render target state, and pipeline result",
        },
        else => .{
            .name = "unknown",
            .classification = "unsupported-or-corrupt-primitive",
            .action = "inspect the raw PM4 packet and Xenos primitive table before changing resource mappings",
        },
    };
}

/// Host file resources owned by a PE run. The guest sees only the synthetic
/// handle; the native descriptor remains behind the Rosetta boundary and is
/// closed with the execution state. Offsets are kept explicitly because
/// ReadFile/WriteFile use the Windows current-file-pointer contract.
pub const WindowsFileSlot = struct {
    guest_handle: u64 = 0,
    stdio_fd: u32 = 0,
    file: ?std.Io.File = null,
    offset: u64 = 0,
    readable: bool = false,
    writable: bool = false,
    media_authorized: bool = false,
    /// A CRT standard stream borrows the process's native descriptor.  It is
    /// still represented by a normal synthetic FILE* slot so f{read,write},
    /// fflush, and _fileno all share one ownership table, but deinit/fclose
    /// must never close the runner's own stdin/stdout/stderr descriptors.
    standard_stream: ?u8 = null,
    /// The host path this handle was opened on, so a failure on the handle
    /// can name its file: the 2026-09-14 run reported `fread x2
    /// error=5` and nothing that said which file refused the read.
    path: [160]u8 = [_]u8{0} ** 160,
    path_len: u8 = 0,

    pub fn setPath(self: *WindowsFileSlot, text: []const u8) void {
        const length = @min(text.len, self.path.len);
        @memcpy(self.path[0..length], text[0..length]);
        self.path_len = @intCast(length);
    }

    pub fn pathText(self: *const WindowsFileSlot) []const u8 {
        return self.path[0..self.path_len];
    }
};

/// A bounded record of guest buffers populated from host files. If a parser
/// later throws while walking one of those bytes, the exception report can
/// name the host file and its exact file offset without retaining guest or
/// host pointers.
pub const WINDOWS_FILE_READ_PROVENANCE_CAPACITY: usize = 32;
pub const WINDOWS_FILE_READ_PROVENANCE_PATH_BYTES: usize = 128;
pub const WINDOWS_FILE_READ_PROVENANCE_API_BYTES: usize = 16;

pub const WindowsFileReadProvenance = struct {
    guest_start: u64 = 0,
    byte_count: u64 = 0,
    file_offset: u64 = 0,
    step: u64 = 0,
    path: [WINDOWS_FILE_READ_PROVENANCE_PATH_BYTES]u8 = @splat(0),
    path_len: u8 = 0,
    api: [WINDOWS_FILE_READ_PROVENANCE_API_BYTES]u8 = @splat(0),
    api_len: u8 = 0,

    pub fn setPath(self: *WindowsFileReadProvenance, text: []const u8) void {
        const length = @min(text.len, self.path.len);
        @memcpy(self.path[0..length], text[0..length]);
        self.path_len = @intCast(length);
    }

    pub fn setApi(self: *WindowsFileReadProvenance, text: []const u8) void {
        const length = @min(text.len, self.api.len);
        @memcpy(self.api[0..length], text[0..length]);
        self.api_len = @intCast(length);
    }

    pub fn pathText(self: *const WindowsFileReadProvenance) []const u8 {
        return self.path[0..self.path_len];
    }

    pub fn apiText(self: *const WindowsFileReadProvenance) []const u8 {
        return self.api[0..self.api_len];
    }

    pub fn contains(self: WindowsFileReadProvenance, address: u64) bool {
        return self.byte_count != 0 and address >= self.guest_start and
            address - self.guest_start < self.byte_count;
    }

    pub fn fileOffsetAt(self: WindowsFileReadProvenance, address: u64) u64 {
        return self.file_offset +| (address - self.guest_start);
    }
};

/// A file- or page-file-backed mapping object created by a Windows PE import.
/// The guest receives only the synthetic handle; file mappings retain a host
/// descriptor-backed sparse view, while page-file mappings retain an
/// anonymous lazy mapping so Xenia's 4 GiB + physical aperture does not
/// require eagerly materializing every byte.
pub const WindowsFileMapping = struct {
    guest_handle: u64 = 0,
    length: u64 = 0,
    backing: ?[]align(std.heap.page_size_min) u8 = null,
    media_authorized: bool = false,
    closed: bool = false,
    /// Bumped whenever guest-visible bytes in this mapping are written.
    /// Generated-code decode entries key on it instead of re-reading and
    /// comparing their source bytes on every hit. A mapping-wide token is
    /// conservative for aliases, and a changed token still falls back to a
    /// byte comparison before the cached decode is reused.
    code_generation: u64 = 1,
    /// Instructions were fetched from this mapping at least once. Its pages
    /// are then never admitted to the translator's write TLB: a store into
    /// them must reach `bumpWindowsMappedCodeGeneration`. Parallel workers
    /// publish/read this monotonic state atomically because the first decode
    /// can race a write-TLB fill on another executor.
    code_fetched: bool = false,
};

/// One MapViewOfFile/MapViewOfFileEx alias.  Xenia deliberately maps several
/// disjoint guest ranges to different offsets of one mapping object, so a
/// single flat PE heap cannot represent this contract.  The interpreter
/// resolves these aliases only when an address is outside its ordinary PE
/// image/stack range.
pub const WindowsMemoryView = struct {
    guest_base: u64 = 0,
    length: u64 = 0,
    mapping_index: usize = 0,
    backing_offset: u64 = 0,
};

/// One executable range in the loaded PE image.  The PE loader supplies
/// section boundaries once, so ordinary image instruction fetches can use the
/// same generation proof as generated code instead of comparing up to fifteen
/// bytes on every cache hit.  The range is deliberately a value type: it
/// carries no parser-owned pointer into the image metadata.
pub const WindowsExecutableRange = struct {
    guest_base: u64 = 0,
    length: u64 = 0,
};

/// A fixed anonymous VirtualAlloc range.  Xenia uses these ranges for native
/// bookkeeping outside the page-file mapping, most importantly the code
/// cache indirection table at 0x80000000.  The host backing remains sparse;
/// the guest address and allocation lifetime are what the PE contract needs.
pub const WindowsVirtualAllocation = struct {
    guest_base: u64 = 0,
    length: u64 = 0,
    backing: ?[]align(std.heap.page_size_min) u8 = null,
    /// Same contract as WindowsFileMapping.code_generation for executable
    /// fixed allocations.
    code_generation: u64 = 1,
    /// Same contract as WindowsFileMapping.code_fetched.
    code_fetched: bool = false,
};

/// A driver-owned mapping, borrowed only until vkUnmapMemory/free/device
/// destruction. Do not copy it into a second CPU allocation: coherent Vulkan
/// memory must retain one identity for CPU stores, GPU stores and readback.
const NativeMemoryAlias = struct {
    guest_base: u64 = 0,
    bytes: ?[]u8 = null,
    reserved_span: u64 = 0,
    slot_base: u64 = 0,
};
const native_alias_address_base: u64 = 0x70_0000_0000;
const native_alias_address_limit: u64 = 0x400_0000_0000;
const native_alias_alignment: u64 = 0x1_0000_0000;

test "borrowed native memory is bounded, collision-safe, reused and never freed by ElfState" {
    var state = ElfState.init(std.testing.allocator);
    var bytes = [_]u8{ 1, 2, 3, 4 };
    const alias = state.borrowNativeMemory(&bytes).?;
    try std.testing.expectEqual(@as(u32, 0x04030201), state.read32(alias));
    state.write32(alias, 0x08070605);
    try std.testing.expectEqualSlices(u8, &.{ 5, 6, 7, 8 }, &bytes);
    // Bulk Windows CRT writes must use the same borrowed bytes, not just the
    // interpreter's scalar/vector store helpers.
    const source = state.mem_base + 0x2000;
    state.write32(source, 0x0c0b0a09);
    state.windows_runtime_enabled = true;
    state.regs.rcx = alias;
    state.regs.rdx = source;
    state.regs.r8 = 4;
    try std.testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "memcpy", state.mem_base + 0x1000));
    try std.testing.expectEqualSlices(u8, &.{ 9, 10, 11, 12 }, &bytes);
    try std.testing.expect(!state.createWindowsVirtualAllocation(alias, 4096));
    try std.testing.expect(!state.createWindowsVirtualAllocation(alias & ~@as(u64, 4095), 4096));
    try std.testing.expect(state.guestMemory(alias, 5) == null);
    try std.testing.expect(state.guestMemory(std.math.maxInt(u64), 2) == null);
    state.releaseNativeMemory(alias);
    try std.testing.expect(state.guestMemory(alias, 1) == null);
    try std.testing.expectEqual(alias, state.borrowNativeMemory(&bytes).?);
    state.deinit(); // Stack bytes still belong to this test, not munmap/free.
    bytes[0] = 9;
    try std.testing.expectEqual(@as(u8, 9), bytes[0]);
}

/// A bounded view into one fixed Windows VirtualAlloc range.  PE64 execution
/// normally fetches from the image, but Xenia's x64 backend emits guest
/// instructions into these Rosette-owned ranges and then dispatches to them.
/// Keep the range identity with the slice so the first transition can be
/// diagnosed without logging every generated instruction fetch.
const WindowsMappedCodeKind = mapped_ranges.Kind;

const WindowsMappedCodeSlice = struct {
    bytes: []const u8,
    guest_base: u64,
    length: u64,
    kind: WindowsMappedCodeKind,
    source_index: usize = 0,
    generation: u64 = 0,
    /// Where `bytes` starts in the source's backing, which is what a code
    /// page is keyed by: Xenia writes its code cache through one view and
    /// runs it through another.
    backing_offset: u64 = 0,
};

/// Provenance for one allocation returned by the PE guest heap.  The PE
/// runtime must implement realloc as a content-preserving operation, but a
/// bump allocator alone does not retain the old block's size.  Keep records
/// in allocation-address order so lookups are logarithmic even when a
/// startup path performs thousands of malloc/free calls.  Freed records keep
/// their address as tombstones; preserving order makes later lookups safe.
pub const WindowsHeapAllocation = struct {
    guest_base: u64 = 0,
    length: u64 = 0,
    active: bool = false,
    /// Guard bytes this block's backing holds past `length`; zero for a
    /// block allocated unguarded, whose next bytes belong to someone else.
    guard_bytes: u8 = 0,
    allocation_rip: u64 = 0,
    allocation_return: u64 = 0,
    allocation_step: u64 = 0,
    allocation_thread_slot: u8 = 0,
    allocation_import: []const u8 = &.{},
    free_rip: u64 = 0,
    free_return: u64 = 0,
    free_step: u64 = 0,
    free_thread_slot: u8 = 0,
    free_import: []const u8 = &.{},
};

const WindowsHeapCallSite = struct {
    rip: u64,
    return_address: u64,
    step: u64,
    thread_slot: u8,
    import: []const u8,
};

const WindowsHeapStackSnapshot = struct {
    words: [6]u64 = [_]u64{0} ** 6,
    readable_mask: u8 = 0,
};

const WindowsHeapCodeSnapshot = struct {
    bytes: [16]u8 = [_]u8{0} ** 16,
    readable: bool = false,
};

/// State for a bounded FindFirstFile/FindNextFile enumeration. The iterator
/// owns a host directory handle, while the wildcard is copied into fixed
/// storage so no guest pointer survives an import call.
pub const WindowsFindSlot = struct {
    guest_handle: u64 = 0,
    dir: ?std.Io.Dir = null,
    iterator: ?std.Io.Dir.Iterator = null,
    directory: [std.fs.max_path_bytes]u8 = [_]u8{0} ** std.fs.max_path_bytes,
    directory_len: usize = 0,
    pattern: [256]u8 = [_]u8{0} ** 256,
    pattern_len: usize = 0,
    wide: bool = false,
};

/// One guest-visible volume-enumeration handle.  Rosetta exposes its
/// confined `C:\\xenia` mount as a deterministic virtual volume; no host
/// mount table or host handle is ever passed into the PE.  The API's iterator
/// is intentionally one-entry: the guest has one mounted volume, and the
/// second `FindNextVolumeW` therefore returns the normal end-of-enumeration
/// result rather than an invalid-handle placeholder.
const WindowsVolumeFindSlot = struct {
    guest_handle: u64 = 0,
    first_volume_returned: bool = false,
};

/// State for one active Microsoft CRT initializer-table walk. Initializers
/// are guest functions, not host callbacks: a synthetic guest return marker
/// lets the normal instruction executor run each callback and then resume the
/// table walk. Keeping frames in the guest state also makes nested `_initterm`
/// calls safe (some C++ runtime setup paths initialize another subsystem).
const WindowsInitTermFrame = struct {
    begin: u64,
    end: u64,
    return_rip: u64,
    return_is_direct: bool,
    returns_error: bool,
    callback_count: u64 = 0,
};

const WindowsCrtExitMode = enum(u8) {
    none,
    normal,
    quick,
};

const WindowsCrtCallback = struct {
    function: u64 = 0,
};

/// Guest-owned process CRT state for the PE runner.
///
/// The UCRT's process path, exit tables, and termination flags are not host
/// libc state: a PE callback is a guest address with a guest lifetime, and
/// the callback must run through the same interpreter as every other guest
/// function. Keeping this state in one bounded block prevents a successful
/// CRT probe from quietly becoming a null pointer or an unsequenced exit.
///
/// `owner_errno_storage` is only the owner-thread copy. Windows errno is
/// thread-local, so worker copies remain in `WindowsGuestThreadContext` and
/// are saved/restored with the rest of that guest thread's state.
const WindowsCrtProcessGlobals = struct {
    module_path_a: u64 = 0,
    module_path_w: u64 = 0,
    owner_errno_storage: u64 = 0,
    normal_callbacks: [MAX_WINDOWS_CRT_ATEXIT_CALLBACKS]WindowsCrtCallback = [_]WindowsCrtCallback{.{}} ** MAX_WINDOWS_CRT_ATEXIT_CALLBACKS,
    normal_count: usize = 0,
    quick_callbacks: [MAX_WINDOWS_CRT_ATEXIT_CALLBACKS]WindowsCrtCallback = [_]WindowsCrtCallback{.{}} ** MAX_WINDOWS_CRT_ATEXIT_CALLBACKS,
    quick_count: usize = 0,
    thread_local_callback: u64 = 0,
    exit_mode: WindowsCrtExitMode = .none,
    exit_running: bool = false,
    exit_return_to_caller: bool = false,
    exit_return_is_direct: bool = false,
    exit_return_rip: u64 = 0,
    exit_return_rsp: u64 = 0,
    pending_exit_code: u64 = 0,
    thread_local_pending: bool = false,
    termination_complete: bool = false,
    callback_registrations: u64 = 0,
    callback_invocations: u64 = 0,
    callback_rejections: u64 = 0,
};

/// State for one guest-side `qsort` walk. The comparator is guest code, so a
/// host-side sort cannot be substituted without violating the PE ABI. Rosetta
/// performs a bounded insertion sort and re-enters the comparator through a
/// synthetic return marker after each comparison. The fixed scratch buffer
/// keeps the callback protocol allocation-free and prevents a malformed PE
/// from turning a diagnostic import into unbounded host memory.
const WindowsQsortFrame = struct {
    base: u64 = 0,
    nmemb: u64 = 0,
    element_size: u64 = 0,
    comparator: u64 = 0,
    return_rip: u64 = 0,
    return_is_direct: bool = false,
    i: u64 = 1,
    j: u64 = 1,
    callback_count: u64 = 0,
    awaiting_comparison: bool = false,
    scratch: [MAX_WINDOWS_QSORT_ELEMENT_BYTES]u8 = [_]u8{0} ** MAX_WINDOWS_QSORT_ELEMENT_BYTES,
};

/// Continuation for one Windows CRT `bsearch`. The comparator is guest code,
/// so each probe yields through a synthetic return marker and resumes this
/// bounded binary-search state machine after the callback returns.
const WindowsBsearchFrame = struct {
    key: u64 = 0,
    base: u64 = 0,
    nmemb: u64 = 0,
    element_size: u64 = 0,
    comparator: u64 = 0,
    low: u64 = 0,
    high: u64 = 0,
    pending_index: u64 = 0,
    return_rsp: u64 = 0,
    return_rip: u64 = 0,
    return_is_direct: bool = false,
    callback_count: u64 = 0,
    awaiting_comparison: bool = false,
};

/// A Windows thread is guest execution state, not merely a successful handle
/// returned by CreateThread. In production PE runs, each runnable context owns
/// a persistent host executor; cooperative service remains for tests and the
/// explicitly serial path. Keep the complete architectural state here:
/// Xenia's thread wrapper uses AVX registers and x87 state while constructing
/// graphics workers, and dropping either set breaks context isolation.
const WindowsGuestThreadContext = struct {
    regs: ElfRegs = .{},
    xmm: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    ymm_hi: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    zmm_hi: [32][32]u8 = [_][32]u8{[_]u8{0} ** 32} ** 32,
    k: [8]u64 = [_]u64{0xFFFF_FFFF_FFFF_FFFF} ** 8,
    x87_stack: [8]X87Raw = [_]X87Raw{[_]u8{0} ** 10} ** 8,
    x87_tags: [8]bool = [_]bool{false} ** 8,
    x87_top: u3 = 0,
    x87_status: u16 = 0,
    x87_control: u16 = 0x037F,
    windows_last_error: u32 = 0,
    windows_errno_storage: u64 = 0,
    /// Import attribution is observable state too: the next fault or CRT
    /// diagnostic must describe the import issued by this thread, not the
    /// most recent import issued by whichever worker ran before it.
    windows_current_import: []const u8 = &.{},
    /// Where the import being dispatched returns to: the caller's next
    /// instruction for an import reached straight from `call [iat]`, which
    /// pushes no return address, or the word at [rsp] for one reached
    /// through a stub.
    windows_current_import_return: u64 = 0,
    /// The currently pending instruction fault belongs to the CPU context
    /// that raised it, just like its RIP and register file.
    guest_access_violation_pending: bool = false,
    guest_access_violation: GuestAccessViolation = .{},
    /// Guest callbacks yield into the scheduler and resume at synthetic
    /// return markers. These continuation stacks belong to the guest context
    /// that entered them.
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
    windows_bsearch_frames: [MAX_WINDOWS_BSEARCH_FRAMES]WindowsBsearchFrame = [_]WindowsBsearchFrame{.{}} ** MAX_WINDOWS_BSEARCH_FRAMES,
    windows_bsearch_frame_count: usize = 0,
    windows_message_dispatch_frames: [MAX_WINDOWS_MESSAGE_DISPATCH_FRAMES]WindowsMessageDispatchFrame = [_]WindowsMessageDispatchFrame{.{}} ** MAX_WINDOWS_MESSAGE_DISPATCH_FRAMES,
    windows_message_dispatch_frame_count: usize = 0,
    windows_audio_callback_frames: [MAX_WINDOWS_AUDIO_CALLBACK_FRAMES]WindowsAudioCallbackFrame = [_]WindowsAudioCallbackFrame{.{}} ** MAX_WINDOWS_AUDIO_CALLBACK_FRAMES,
    windows_audio_callback_frame_count: usize = 0,
    /// Translator bookkeeping is consumed by helpers running on this guest
    /// context; do not let a worker's helper overwrite the owner's record.
    block_jit_scratch: block_jit.Scratch = .{},
    step_retired: u32 = 1,
    /// Sampling cadence belongs to this guest executor. The code profile is
    /// updated while its step lease is held, so a stop-the-world report can
    /// never race a worker writing the same thread record.
    parallel_code_sample_steps: u6 = 0,
    /// Private host-clock sampling cadence for this guest executor. A shared
    /// counter would bounce a cache line between every native worker.
    guest_clock_sample_steps: u64 = 0,
    /// Cooperative scheduling requests are execution-local. Keeping them
    /// beside the saved register file prevents one host executor's yield or
    /// wait handoff from ending another guest thread's slice.
    windows_guest_slice_yield_requested: bool = false,
    windows_slice_pause_yield: bool = false,
    windows_guest_handoff_requested: bool = false,
    windows_slice_clock_reads: u32 = 0,
    active_guest_thread: u64 = 0,
    /// Scheduler slot is execution-local, like the register file it names.
    windows_active_guest_thread_slot: ?usize = null,
    /// Bound while the memory-aware cross-check interprets a block: stores
    /// land in it instead of memory (`diagnostics/block_verify_journal.zig`).
    verify_journal: ?*block_verify.Journal = null,
    windows_thread_id: u64 = 1,
    active_idle_source: u64 = 0,
    last_decoded_op: Op = .invalid,
    last_decoded_len: u8 = 0,
    last_instruction_rip: u64 = 0,
    decode_failure_is_invalid_control_target: bool = false,
    /// The translated memory probe for this execution context. Thread-local
    /// so a guest worker cannot evict its peer's page translations.
    block_jit_tlb: ?*block_jit.Tlb = null,
};

/// A host executor binds one guest execution context while it interprets
/// guest instructions. Register/vector/fault state and the active scheduler
/// slot are selected from this binding rather than borrowed from the process
/// owner's live context.
const WindowsGuestExecutionBinding = struct {
    owner: *anyopaque,
    context: *WindowsGuestThreadContext,
};

threadlocal var windows_guest_execution_binding: ?WindowsGuestExecutionBinding = null;

/// `guestContextField` with the thread-local binding read once.
///
/// Every `guestContextField` call reads `windows_guest_execution_binding`,
/// and on macOS each read of a `threadlocal` is a call through
/// `tlv_get_addr`: 4% of Halo 3's main thread and 2.4% of its render thread
/// on 2026-09-30, most of it from the translated-code dispatch loop, which
/// reads a dozen context fields per block it runs. A hot path takes one of
/// these and takes it again after anything that can rebind the executor:
/// a translated block's helpers can run a nested slice of another thread.
const GuestContextRef = struct {
    bound: ?*WindowsGuestThreadContext,
    state: *ElfState,

    pub inline fn field(self: GuestContextRef, comptime name: []const u8) *@FieldType(WindowsGuestThreadContext, name) {
        if (self.bound) |context| return &@field(context.*, name);
        return &@field(self.state.*, name);
    }
};

/// Import shims mutate process-wide Win32 objects (handle tables, mappings,
/// wait queues, graphics records and counters). Guest CPU contexts may run on
/// separate host threads, so shim entry points take this mutex and rendezvous
/// through the instruction-boundary gate before touching shared runtime state.
const WindowsRuntimeLockGuard = struct {
    mutex: *HostMutex,
    gate_guard: ?GuestExecutionGate.MutationGuard = null,
    owner: *anyopaque,
    stack_index: usize,
    reentrant: bool,
    /// False for a dispatch level (`lockWindowsRuntimeForDispatch`): one that
    /// only routes a call into its handler, so a blocking wait inside the
    /// handler may release the lock. See `OwnerDepthStack`.
    pinned: bool = true,
    flush_tso_on_unlock: bool = false,
    /// The guest store buffer the caller had bound, restored at unlock. The
    /// runtime call itself runs with none bound; see `enterRuntimeStoreScope`.
    prior_store_buffer: ?*tso_memory.StoreBuffer = null,
    /// `windows_thread_wake_epoch` when the lock was taken. A call that made
    /// a parked guest thread runnable moved it, and only such a call wakes
    /// the parked workers.
    wake_epoch_at_lock: u64 = 0,

    pub fn unlock(self: *WindowsRuntimeLockGuard) void {
        const state: *ElfState = @ptrCast(@alignCast(self.owner));
        // A stop-the-world taken on top of this lock ends first: the lock
        // order is the runtime mutex, then a mutation.
        if (self.gate_guard) |*guard| guard.unlock();
        self.gate_guard = null;
        if (self.reentrant) {
            windows_runtime_locks.pop(self.stack_index, self.owner, self.pinned);
            _ = tso_memory.setActiveStoreBuffer(self.prior_store_buffer);
            return;
        }
        std.debug.assert(windows_runtime_locks.depth(self.owner) == 1);
        if (self.flush_tso_on_unlock) {
            state.flushAllGuestStoreBuffers(.runtime_call);
        }
        // Every runtime call used to notify the workers' wake hub. With
        // parked workers really asleep that would be a kernel wake of every
        // blocked guest thread per import - hundreds of thousands a second
        // from Xenia's message loop alone. Only a call that changed some
        // thread's runnability wakes them.
        const woke_threads = state.windows_thread_wake_epoch != self.wake_epoch_at_lock;
        self.mutex.unlock();
        windows_runtime_locks.pop(self.stack_index, self.owner, self.pinned);
        _ = tso_memory.setActiveStoreBuffer(self.prior_store_buffer);
        if (woke_threads and state.parallel_guest_execution) state.parallel_guest_wake_hub.notify();
    }
};

/// A runtime call (import, shim, hook) is a serializing boundary for the
/// guest context that makes it, as a system call is on real hardware: its
/// buffered stores are published first, and the call runs with no buffer
/// bound, so every store the runtime makes on the guest's behalf reaches
/// memory at once and in the order the runtime made it - the same way as the
/// direct host slices most runtime code already writes through. Without this,
/// a handler that stored an out-parameter through the buffer and then
/// returned into a translated block left the block reading the old value:
/// on 2026-09-24 that turned `SHGetKnownFolderPath`'s result into a stale
/// stack slot and `LoadWindowsFont` freed the previous call's block again.
/// Reentrant calls take this step too, because a worker serviced inside the
/// owner's wait makes its own imports under the owner's lock.
fn enterRuntimeStoreScope() ?*tso_memory.StoreBuffer {
    const prior = tso_memory.setActiveStoreBuffer(null);
    if (prior) |buffer| tso_memory.boundary_ledger.noteFlush(.runtime_call, buffer.drain());
    return prior;
}

threadlocal var windows_runtime_locks: GuestExecutionGateTls = .{};

/// When this thread asked for the runtime lock for the import it is about to
/// run (parallel mode), for `PE64 RUNTIME LOCK HOLDS`' wait column; zero when
/// the lock was taken some other way.
threadlocal var import_lock_requested_ns: u64 = 0;
/// Time this thread has spent with the runtime lock released inside a call
/// that holds it - a blocked `GetMessage` - so the ledger's held time is the
/// time the lock was really held.
threadlocal var runtime_lock_released_ns: u64 = 0;

const WindowsGuestThreadEnvironment = struct {
    teb: u64,
    tls_block: u64,
};

const WindowsGuestThreadStatus = enum(u8) {
    vacant,
    pending,
    runnable,
    running,
    blocked,
    completed,
    failed,
};

/// A non-vacant slot is not necessarily a living worker.  Completed
/// one-shot workers remain in the table until their handle can be retired, so
/// counting occupancy as liveness makes a normal exit look like a missing
/// thread.  Keep this predicate beside the status enum so every diagnostic
/// uses the same lifecycle definition.
fn isLiveWindowsGuestThread(status: WindowsGuestThreadStatus) bool {
    return switch (status) {
        .pending, .runnable, .running, .blocked => true,
        .vacant, .completed, .failed => false,
    };
}

/// The lock a native CONDITION_VARIABLE wait releases and retakes.
const NativeConditionLock = enum(u8) { none, critical_section, srw };

const WindowsSrwLock = struct {
    address: u64 = 0,
    owner_thread_id: u64 = 0,
    contentions: u64 = 0,
    handoffs: u64 = 0,
    acquire_calls: u64 = 0,
    release_calls: u64 = 0,
    release_mismatches: u64 = 0,
    owner_acquired_step: u64 = 0,
    last_acquire_step: u64 = 0,
    last_release_step: u64 = 0,
    last_acquire_thread_id: u64 = 0,
    last_release_thread_id: u64 = 0,
    /// The owner context has no worker slot to block, so it waits by
    /// retrying at the call site. It still queues, or a pair of workers
    /// trading the lock could starve it indefinitely.
    owner_waiting: bool = false,
    owner_wait_sequence: u64 = 0,
    /// A critical section rather than an SRW lock. Win32 and Xbox 360 use
    /// different guest layouts; both share this owner/waiter state machine.
    /// Zero recursion with an owner is a handoff the new owner has not yet
    /// collected.
    critical_section_layout: ?xbox_critical_section.Layout = null,
    recursion: u32 = 0,
    /// Image return addresses on the owner's stack when it took the lock
    /// (directly or by handoff), innermost first. A lock held for good names
    /// the frame that took it, even after that frame has returned.
    owner_stack: [windows_srw_owner_stack_depth]u64 = @splat(0),
    owner_stack_sampled: bool = false,
};

const windows_srw_owner_stack_depth = 8;
const WindowsSrwLockIndex = srw_lock_index.Index(MAX_WINDOWS_SRW_LOCKS);

/// A bounded guest-side record for the Win32 objects that can be waited on.
/// The PE executor cannot hand a host semaphore to a guest thread: doing so
/// would block the one interpreter that must continue servicing the other
/// guest workers.  Keeping the signal state here lets the scheduler park a
/// worker at WaitForSingleObject and wake it only when SetEvent, a release,
/// or thread completion actually makes the object ready.
const WindowsWaitObjectKind = enum(u8) {
    event,
    mutex,
    semaphore,
    thread,
    generic,
    /// A Win32 waitable timer: signalled when its due tick passes.
    timer,
};

const WindowsWaitObject = struct {
    handle: u64 = 0,
    kind: WindowsWaitObjectKind = .generic,
    signaled: bool = false,
    manual_reset: bool = false,
    count: u32 = 0,
    maximum: u32 = 0,
    /// Timers only: the guest-clock tick the timer next fires at (zero when
    /// not armed) and the period in ticks (zero for a one-shot).
    due_ticks: u64 = 0,
    period_ticks: u64 = 0,
    creator_rip: u64 = 0,
    creator_thread: u64 = 0,
    created_step: u64 = 0,
    signal_count: u64 = 0,
    last_signal_rip: u64 = 0,
    last_signal_thread: u64 = 0,
    last_signal_step: u64 = 0,
    /// Mutexes only: the Win32 thread id that owns it (zero when it is
    /// free) and how many times that thread has acquired it. A Win32 mutex
    /// is recursive and owned; Xenia's XMutant hands the Xbox 360's
    /// recursive mutants straight to it (`xe::threading::Mutant`).
    owner_thread_id: u64 = 0,
    recursion: u32 = 0,
    /// Mutexes only (`impl/windows_mutex.zig`): waits its owner satisfied
    /// again at once, releases refused to a thread that did not own it, last
    /// releases handed straight to a parked waiter, and releases made because
    /// the owning thread exited.
    recursive_acquisitions: u32 = 0,
    release_refusals: u32 = 0,
    handoffs: u32 = 0,
    abandoned: u32 = 0,
};

/// The longest guest thread name a report keeps. Xenia's are short and
/// descriptive ("GPU Frame limiter", "Audio Worker", "GPU Commands"); a
/// program with longer ones is truncated rather than allocated for.
const WINDOWS_GUEST_THREAD_NAME_BYTES: usize = 40;

/// What `xe_global_mutex` recorded for a thread whose lock was lent out:
/// `owner_thread_` (+8) and `recursion_count_` (+12).
const XeniaGlobalLend = struct { owner: u32, recursion: u32 };

/// Xenia's `xe_global_mutex` on Windows: the SRW lock word, then the
/// recursive owner's thread id and depth (src/xenia/base/mutex.h).
const XENIA_GLOBAL_MUTEX_SYMBOL = "_ZZN2xe22global_critical_region5mutexEvE12global_mutex";
const XENIA_GLOBAL_MUTEX_OWNER_OFFSET: u64 = 8;
const XENIA_GLOBAL_MUTEX_RECURSION_OFFSET: u64 = 12;

/// One pulse's reading of every time source the guest can see.
const TimeAuditSample = struct {
    elapsed_ns: u64 = 0,
    guest_clock_us: u64 = 0,
    kuser_interrupt_100ns: u64 = 0,
    bundle_interrupt_100ns: u64 = 0,
    bundle_system_filetime: u64 = 0,
    bundle_tick_ms: u32 = 0,
};

const WindowsGuestThread = struct {
    status: WindowsGuestThreadStatus = .vacant,
    handle: u64 = 0,
    /// The name the guest gave this thread through `SetThreadDescription`.
    ///
    /// Rosette used to answer that call with S_OK and discard the string, so
    /// every thread in a report was a hexadecimal handle and a symbol, and
    /// deciding which of fifteen was the GPU frame limiter meant
    /// disassembling the image. The guest is telling Rosette the answer; the
    /// only work is to keep it.
    name: [WINDOWS_GUEST_THREAD_NAME_BYTES]u8 = [_]u8{0} ** WINDOWS_GUEST_THREAD_NAME_BYTES,
    name_len: u8 = 0,
    start_routine: u64 = 0,
    argument: u64 = 0,
    thread_id: u64 = 0,
    stack_base: u64 = 0,
    stack_size: u64 = 0,
    /// The guard allocation's base: `stack_base - WINDOWS_GUEST_THREAD_STACK_GUARD`
    /// when the stack has one, zero otherwise.
    stack_guard_base: u64 = 0,
    synthetic_return_slot: u64 = 0,
    teb: u64 = 0,
    tls_block: u64 = 0,
    preferred: bool = false,
    priority: i32 = 0,
    suspend_count: u32 = 0,
    executed_steps: u64 = 0,
    /// Raw translated x86 PAUSE instructions reached by this guest thread.
    /// This is per-thread because the process-wide serial counter is not
    /// updated by parallel executors.
    pause_hints: u64 = 0,
    /// Host yield requests caused by PAUSE, counted at the parallel worker
    /// boundary where the per-thread slice flag is consumed.
    pause_host_yields: u64 = 0,
    /// The spin streak and read capture behind `PE64 GUEST SPIN FORENSICS`
    /// (`diagnostics/guest_spin.zig`). Written only by the host thread
    /// executing this guest thread.
    spin: guest_spin.ThreadSpin = .{},
    blocked_srw_lock: u64 = 0,
    /// When this thread started waiting for `blocked_srw_lock`, as a
    /// monotonic sequence. The oldest waiter is the one a release hands the
    /// lock to.
    srw_wait_sequence: u64 = 0,
    /// Xenia's global critical region, lent out while this thread backs
    /// off still holding it (`yieldXeniaGlobalMutexForBackoff`): the owner
    /// and recursion depth its own fields held, restored when it takes the
    /// lock back.
    xenia_global_lend: ?XeniaGlobalLend = null,
    /// Bumped whenever the guest names this thread, so its host thread can
    /// re-derive its quality of service from the new name
    /// (`applyParallelWorkerQos`).
    name_generation: u32 = 0,
    blocked_condition: u64 = 0,
    // A pthread condition wait atomically releases its associated mutex and
    // reacquires it before returning.  Keep the mutex address across the
    // cooperative park; without it a resumed worker would return to guest
    // code while the mutex remained owned by nobody (or, worse, by the
    // waiter that is supposed to be asleep).
    blocked_condition_mutex: u64 = 0,
    /// A native CONDITION_VARIABLE wait (`SleepConditionVariableCS/SRW`):
    /// the lock it released and must retake before it returns, which kind of
    /// lock that is, and a critical section's recursion to restore.
    native_condition_lock: u64 = 0,
    native_condition_kind: NativeConditionLock = .none,
    native_condition_recursion: u32 = 0,
    blocked_wait_handle: u64 = 0,
    // Finite Win32 waits are measured in guest milliseconds.  The PE route
    // has no host clock per guest worker, so translate the timeout into a
    // bounded owner-step deadline and wake it cooperatively when that
    // deadline expires.  Zero means an infinite wait or a non-Wait boundary.
    blocked_wait_timeout: u64 = 0,
    blocked_wait_deadline: u64 = 0,
    /// Monotonic age of the current park. The wait fields above are cleared
    /// as soon as a producer wakes a worker, so these survive until the
    /// resumed import consumes the one-shot result and closes the wait-cost
    /// record.
    blocked_since_total_steps: u64 = 0,
    blocked_since_guest_ticks: u64 = 0,
    wait_cost_site: u8 = 0,
    wait_cost_start_step: u64 = 0,
    wait_cost_start_ticks: u64 = 0,
    wait_cost_deadline: u64 = 0,
    /// The last Windows import this thread called, and when.
    ///
    /// The question that follows every spin: what was the thread doing
    /// immediately before it stopped getting anywhere. A thread's rip says
    /// where it is now; the last boundary it crossed says what it was in the
    /// middle of, and for a guest whose own code Rosette cannot read - a
    /// translator's output - it is the only narrative available.
    last_import: [WINDOWS_GUEST_THREAD_NAME_BYTES]u8 = [_]u8{0} ** WINDOWS_GUEST_THREAD_NAME_BYTES,
    last_import_len: u8 = 0,
    last_import_step: u64 = 0,
    import_calls: u64 = 0,
    /// The last milestone this thread entered, by table index plus one, and
    /// the step it happened at.
    entered_xenia_title: bool = false,
    last_milestone: u8 = 0,
    last_milestone_step: u64 = 0,
    /// The last kernel export shim this thread entered, by census slot plus
    /// one, and the step it happened at.
    ///
    /// A milestone is one of twenty-two hand-picked functions; a kernel shim
    /// is any of the 692 the guest can reach. For the title's own thread the
    /// second is the only narrative there is, because everything it executes
    /// between two of them is translated PowerPC that Rosette cannot name.
    last_kernel_slot: u32 = 0,
    last_kernel_step: u64 = 0,
    kernel_calls: u64 = 0,
    /// Last Ke*Event export boundary for this executor. Capturing this before
    /// Xenia enters GetNativeObject lets a later null virtual dispatch report
    /// the exact guest event header/handle that selected its native object.
    last_xenia_event_call: xenia_event_audit.CallSnapshot = .{},
    /// The critical section this thread last asked `RtlEnterCriticalSection`
    /// for, and the membase that reaches it. A thread blocked there is
    /// waiting on whoever the section names as its owner, and that owner is
    /// the next link of the wait graph, which a handle-only report cannot see.
    critical_section: u32 = 0,
    critical_section_membase: u64 = 0,
    /// Emit one live creator/signal snapshot when an Xbox critical-section
    /// event first parks this thread. A process stopped before exit still
    /// retains the evidence needed to distinguish a missing producer from a
    /// lost auto-reset wake.
    xbox_cs_wait_provenance_handle: u64 = 0,
    /// The Xbox critical section (host address) this thread has counted
    /// itself into and waits for, and whether a release granted it. A counted
    /// waiter re-runs its RtlEnterCriticalSection call when it wakes; these
    /// make that call collect the grant instead of counting itself again.
    xbox_cs_wait: u64 = 0,
    xbox_cs_granted: bool = false,
    /// This thread's X_KTHREAD, read once from its PCR, and the PPCContext
    /// it was read through: the owner value Xenia writes into a section.
    xbox_kthread: u32 = 0,
    xbox_kthread_context: u64 = 0,
    /// Turns this thread still gives away, and the size of its current
    /// backoff; see `noteWindowsGuestSliceShape`.
    spin_skip_remaining: u8 = 0,
    spin_backoff: u8 = 0,
    /// A call on this thread whose return value is wanted. See
    /// `GuestReturnCapture`.
    return_capture: GuestReturnCapture = .{},
    /// The file request this thread made last, for an empty resolve to cite.
    file_request: GuestFileRequest = .{},
    /// When and from where this thread was created. A thread that faults
    /// while its creator is still inside the creating call read something
    /// the creator had not stored yet.
    created_step: u64 = 0,
    creator_rip: u64 = 0,
    /// The creator's slot plus one; zero is the owner context.
    creator_slot: u8 = 0,

    /// Where this thread has been executing, and whether that is moving.
    ///
    /// A thread's rip at one instant says where it is; it cannot say whether
    /// it is getting anywhere. `Main XThread` sat at a JIT address holding a
    /// fifth of the 2026-09-12 run and the report could not distinguish a
    /// title working through its start-up from a title spinning on one
    /// branch - which is the entire question once the wall belongs to the
    /// title. Sampled every 64 instructions rather than every one: a loop
    /// shorter than that is still caught, because slices begin at different
    /// offsets, and the cost stays a predictable branch. See
    /// `spin_anatomy.zig`.
    code: spin_anatomy.Window = .{},
    condition_resume: bool = false,
    wait_resume: bool = false,
    wait_resume_handle: u64 = 0,
    wait_resume_timeout: bool = false,
    /// A `WaitForMultipleObjects` park: the handles, how many, and whether
    /// every one is needed. `blocked_wait_handle` keeps the first, so every
    /// report that names one handle still names a real one.
    blocked_wait_handles: [WINDOWS_WAIT_MULTIPLE_CAPACITY]u64 = [_]u64{0} ** WINDOWS_WAIT_MULTIPLE_CAPACITY,
    blocked_wait_handle_count: u8 = 0,
    blocked_wait_all: bool = false,
    /// A wait-all waiter is woken to look again, never handed an object.
    wait_resume_recheck: bool = false,
    /// The deadline a multi-object wait keeps across a wait-all recheck.
    multi_wait_deadline: u64 = 0,
    /// A timed condition wait whose deadline passed before a signal came. The
    /// waiter still retakes its mutex before it returns; this is what makes
    /// that return ETIMEDOUT instead of zero.
    condition_resume_timeout: bool = false,
    /// This waiter has already parked on its mutex's event while retaking it
    /// after a condition wake, so it must retake it the way the image's
    /// contended lock path does - see `acquireWindowsGuestPthreadMutex`.
    condition_mutex_contended: bool = false,
    /// User APCs for this thread, and whether its current block is an
    /// alertable wait an APC may end.
    apc: WindowsApcQueue = .{},
    blocked_alertable: bool = false,
    /// The timed-wait site of the wait this thread is in, plus one.
    timed_wait_site: u8 = 0,
    /// The requested interval retained for timeout diagnostics. The generic
    /// blocked-wait field is intentionally cleared for condition waits, so
    /// keep this separate until the waiter has actually returned.
    timed_wait_milliseconds: u64 = 0,
    /// ABI call tracing is guest-thread local. Sharing the owner's dynamic
    /// array made a cooperative thread switch truncate or overwrite another
    /// thread's diagnostic stack.
    call_stack: x64_guest_abi.CallStack = .{},
    context: WindowsGuestThreadContext = .{},
    /// Present only after this slot has been dispatched to its persistent
    /// host executor. The worker borrows this stable slot and is joined before
    /// the slot is recycled or the process state is destroyed.
    parallel_worker: parallel_workers.Worker = .{},
    /// This thread's own translator state while it runs on its own host
    /// thread (parallel mode); null until one of its blocks gets hot. Freed
    /// when the slot is recycled and at teardown.
    parallel_block_jit: ?*BlockJitState = null,
    /// Its translator could not be created (executable memory refused): this
    /// thread stays interpreted, and the others keep theirs.
    parallel_block_jit_refused: bool = false,

    /// Whether a signal on `handle` concerns this thread's wait.
    pub fn waitsOnHandle(self: *const WindowsGuestThread, handle: u64) bool {
        if (self.blocked_wait_handle == handle) return true;
        if (self.blocked_wait_handle_count == 0) return false;
        return std.mem.indexOfScalar(u64, self.blocked_wait_handles[0..self.blocked_wait_handle_count], handle) != null;
    }

    /// The guest's own name for this thread, or an empty slice.
    pub fn nameText(self: *const WindowsGuestThread) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn lastImportText(self: *const WindowsGuestThread) []const u8 {
        return self.last_import[0..self.last_import_len];
    }

    pub fn codeSpan(self: *const WindowsGuestThread) u64 {
        return self.code.span();
    }

    /// Distinct 4 KiB pages entered in the current window and the one before
    /// it. Two windows because a thread that has just been resumed has a
    /// nearly empty current one, and a report at exit would call it stuck.
    pub fn codePages(self: *const WindowsGuestThread) u32 {
        return self.code.pageCount();
    }
};

/// One sample of everything a PE run can be observed making progress on.
///
/// Nothing here is title-specific: these are the boundaries Rosetta itself
/// owns, so a guest that is doing anything Rosetta can see moves at least one
/// of them.  A stall is declared only when every axis is frozen together --
/// a single frozen axis is a phase, not a defect.
const WindowsProgressSample = struct {
    import_calls: u64 = 0,
    graphics_calls: u64 = 0,
    graphics_frames: u64 = 0,
    /// Guest-initiated only.  Rosetta's own idle WM_NULL and its synthesized
    /// WM_PAINT free-run for as long as the pump is called, so counting them
    /// would let a guest that is asking for the same thing forever look like
    /// a guest that is getting somewhere.
    message_traffic: u64 = 0,
    paint_traffic: u64 = 0,
    worker_traffic: u64 = 0,
    file_traffic: u64 = 0,
    /// Packed count of workers in each state, so a thread starting or ending
    /// counts as progress even when it does no instrumented work.
    worker_states: u64 = 0,
    /// The lowest and highest RIP the run visited during the sample window.
    /// A guest looping over a handful of addresses has a tiny span; one that
    /// is genuinely working walks the image.
    rip_low: u64 = 0,
    rip_high: u64 = 0,

    pub fn matches(self: WindowsProgressSample, other: WindowsProgressSample) bool {
        return self.import_calls == other.import_calls and
            self.graphics_calls == other.graphics_calls and
            self.graphics_frames == other.graphics_frames and
            self.message_traffic == other.message_traffic and
            self.paint_traffic == other.paint_traffic and
            self.worker_traffic == other.worker_traffic and
            self.file_traffic == other.file_traffic and
            self.worker_states == other.worker_states and
            self.rip_low == other.rip_low and
            self.rip_high == other.rip_high;
    }
};

/// Watchdog state for the progress sampler.  Default-off numbers are chosen
/// so a healthy run never reaches the reporting path: the sampler only costs
/// two comparisons per step and one counter comparison per window.
const WindowsProgressWatchdog = struct {
    enabled: bool = true,
    /// Steps between samples.
    interval: u64 = 2_000_000,
    /// Consecutive identical samples before a stall is declared.  Long enough
    /// that an ordinary compute phase -- decryption, decompression, a hash
    /// over a large buffer -- finishes inside one window rather than being
    /// reported as a stall.
    threshold: u32 = 16,
    next_sample_step: u64 = 0,
    previous: WindowsProgressSample = .{},
    have_previous: bool = false,
    frozen_samples: u32 = 0,
    /// Frozen-sample count at which the next report is emitted.  Doubles
    /// after each report so a long stall leaves a heartbeat instead of a
    /// flood.
    next_report_at: u32 = 0,
    reported: bool = false,
    episodes: u64 = 0,
    /// RIP extremes for the window currently being accumulated.
    window_rip_low: u64 = std.math.maxInt(u64),
    window_rip_high: u64 = 0,
    /// Workers unblocked by the starvation backstop.
    backstop_services: u64 = 0,
    /// Escalation point for the paint-without-present predictor, which is
    /// independent of the freeze detector: a guest can be busily running its
    /// message loop -- so nothing looks frozen -- while nothing it paints ever
    /// reaches the screen.
    paint_without_present_reported_at: u64 = 0,
};

/// Rosette-owned preemption policy for the single-interpreter Windows route.
/// This is deliberately separate from the progress watchdog: the scheduler
/// makes forward progress possible, while the watchdog remains responsible
/// for diagnosing a run whose observable axes still do not move.
const WindowsGuestSchedulerPolicy = struct {
    enabled: bool = true,
    quantum: u64 = WINDOWS_GUEST_THREAD_SCHEDULER_QUANTUM,
    slice: u64 = WINDOWS_GUEST_THREAD_SERVICE_SLICE,
    // Explicit wait/message/lock boundaries are still serviced promptly,
    // but a guest UI loop can call GetMessage once every few instructions.
    // Keep those boundaries on their own owner-step stride so one worker
    // cannot consume the entire host after the first frame is presented.
    explicit_stride: u64 = WINDOWS_GUEST_THREAD_SERVICE_OWNER_STRIDE,
    next_service_step: u64 = 0,
    next_explicit_service_step: u64 = 0,
    service_calls: u64 = 0,
    serviced_steps: u64 = 0,
    explicit_service_calls: u64 = 0,
    explicit_serviced_steps: u64 = 0,
    explicit_service_skips: u64 = 0,
};

/// Paints Rosetta must have delivered before "the guest is painting but never
/// presenting" is a claim rather than a startup phase.
const WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD: u64 = 64;

/// The common Win32 file error codes, named so a report does not make the
/// reader look them up.
fn windowsFileErrorLabel(code: u32) []const u8 {
    return switch (code) {
        0 => "ERROR_SUCCESS",
        2 => "ERROR_FILE_NOT_FOUND",
        3 => "ERROR_PATH_NOT_FOUND",
        5 => "ERROR_ACCESS_DENIED",
        6 => "ERROR_INVALID_HANDLE",
        15 => "ERROR_INVALID_DRIVE",
        18 => "ERROR_NO_MORE_FILES",
        22 => "EINVAL",
        32 => "ERROR_SHARING_VIOLATION",
        87 => "ERROR_INVALID_PARAMETER",
        112 => "ERROR_DISK_FULL",
        123 => "ERROR_INVALID_NAME",
        183 => "ERROR_ALREADY_EXISTS",
        else => "unnamed",
    };
}

/// Which Windows file operations failed, and how.
///
/// A run that ends with `file_failures=5004` and no other detail says
/// something is wrong five thousand times without saying what. The count on
/// its own cannot distinguish a guest probing for optional files -- which is
/// normal and expensive-looking -- from a path Rosetta cannot serve that the
/// guest needs. Naming the API and the error code separates the two.
/// What a failed Windows file call most likely means.
///
/// The ledger used to print every failure as a warning, so a run reported
/// 14123 `CreateFileW` failures in the same voice as a read that failed on an
/// open file. Most were discord-rpc looking for a Discord client's pipe - the
/// answer Windows gives too - and the one warning worth reading was lost in
/// them. A class says which kind each is; only the actionable kinds warn, so
/// a run with nothing Rosette failed to serve prints no file warning at all.
const WindowsFileFailureClass = enum {
    named_pipe_without_server,
    end_of_enumeration,
    optional_path_probe,
    missing_path_open,
    io_failure,
    other,

    pub fn expected(self: WindowsFileFailureClass) bool {
        return switch (self) {
            .named_pipe_without_server, .end_of_enumeration, .optional_path_probe => true,
            .missing_path_open, .io_failure, .other => false,
        };
    }

    pub fn meaning(self: WindowsFileFailureClass) []const u8 {
        return switch (self) {
            .named_pipe_without_server => "no server is listening on this named pipe, and Windows answers ERROR_FILE_NOT_FOUND the same way. discord-rpc probes discord-ipc-0 through 9 for a running Discord client on every reconnect; ten calls a reconnect, and a count that grows every 500 ms means its backoff is not growing toward its 60 s cap",
            .end_of_enumeration => "the normal end of a directory enumeration",
            .optional_path_probe => "a lookup for a file that may not exist; the guest takes its absent branch",
            .missing_path_open => "an open of a path that does not exist on the host; if the guest needs this file, the path or its translation is the problem",
            .io_failure => "a read, write or seek on a handle that is open; Rosette could not serve it, and the subject names the file",
            .other => "unclassified; read the error against the subject",
        };
    }
};

fn windowsFileFailureApiIn(api: []const u8, names: []const []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, api, name)) return true;
    }
    return false;
}

fn classifyWindowsFileFailure(api: []const u8, error_code: u32, subject: []const u8) WindowsFileFailureClass {
    const lookups = [_][]const u8{ "_wstat64", "_wstat", "_stat64", "_stat", "stat", "GetFileAttributesA", "GetFileAttributesW", "GetFileAttributesExA", "GetFileAttributesExW", "FindFirstFileA", "FindFirstFileW", "FindFirstFileExA", "FindFirstFileExW", "PathFileExistsA", "PathFileExistsW" };
    const opens = [_][]const u8{ "CreateFileA", "CreateFileW", "_wfopen", "_wfsopen", "fopen", "fopen64", "_wopen", "_open", "_wfopen_s", "fopen_s" };
    const io = [_][]const u8{ "fread", "fwrite", "ReadFile", "WriteFile", "_read", "_write", "read", "write", "SetFilePointer", "SetFilePointerEx", "fseek", "_fseeki64", "ftell", "_ftelli64", "_lseeki64", "lseek64", "GetFileSize", "GetFileSizeEx", "FlushFileBuffers", "SetEndOfFile", "fflush", "fputs", "fputc", "putc" };
    const not_found = error_code == 2 or error_code == 3;
    if (not_found and (std.mem.startsWith(u8, subject, "\\\\?\\pipe\\") or std.mem.startsWith(u8, subject, "\\\\.\\pipe\\"))) return .named_pipe_without_server;
    if (error_code == 18) return .end_of_enumeration;
    if (not_found and windowsFileFailureApiIn(api, &lookups)) return .optional_path_probe;
    if (not_found and windowsFileFailureApiIn(api, &opens)) return .missing_path_open;
    if (windowsFileFailureApiIn(api, &io)) return .io_failure;
    return .other;
}

const WindowsFileFailureLedger = struct {
    const capacity: usize = 24;
    const name_capacity: usize = 48;
    const subject_capacity: usize = 160;

    const Entry = struct {
        name_buffer: [name_capacity]u8 = [_]u8{0} ** name_capacity,
        name_length: usize = 0,
        error_code: u32 = 0,
        class: WindowsFileFailureClass = .other,
        count: u64 = 0,
        /// The path or file the first failure of this kind named, and where
        /// the call came from (zero when the handler could not say).
        subject_buffer: [subject_capacity]u8 = [_]u8{0} ** subject_capacity,
        subject_length: usize = 0,
        first_caller: u64 = 0,

        pub fn name(self: *const Entry) []const u8 {
            return self.name_buffer[0..self.name_length];
        }

        pub fn subject(self: *const Entry) []const u8 {
            return self.subject_buffer[0..self.subject_length];
        }
    };

    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    count: usize = 0,
    total: u64 = 0,
    overflow: u64 = 0,

    pub fn note(self: *WindowsFileFailureLedger, api: []const u8, error_code: u32, subject: []const u8, caller: u64) void {
        self.total +|= 1;
        const bounded = api[0..@min(api.len, name_capacity)];
        const class = classifyWindowsFileFailure(api, error_code, subject);
        for (self.entries[0..self.count]) |*entry| {
            if (entry.error_code != error_code or entry.class != class) continue;
            if (!std.mem.eql(u8, entry.name(), bounded)) continue;
            entry.count +|= 1;
            if (entry.first_caller == 0) entry.first_caller = caller;
            return;
        }
        if (self.count == capacity) {
            self.overflow +|= 1;
            return;
        }
        var entry = Entry{ .error_code = error_code, .class = class, .count = 1, .first_caller = caller };
        @memcpy(entry.name_buffer[0..bounded.len], bounded);
        entry.name_length = bounded.len;
        const subject_length = @min(subject.len, subject_capacity);
        @memcpy(entry.subject_buffer[0..subject_length], subject[0..subject_length]);
        entry.subject_length = subject_length;
        self.entries[self.count] = entry;
        self.count += 1;
    }

    pub fn isEmpty(self: *const WindowsFileFailureLedger) bool {
        return self.count == 0;
    }
};

/// Message representation owned by the parallelism package's bounded,
/// thread-affine queue.
pub const WindowsMessage = windows_message_queue.Message;

const WindowsWindowClass = struct {
    valid: bool = false,
    atom: u16 = 0,
    wnd_proc: u64 = 0,
    name_ptr: u64 = 0,
    name_len: usize = 0,
    name: [128]u8 = [_]u8{0} ** 128,
    wide: bool = false,
};

const WindowsWindow = struct {
    valid: bool = false,
    handle: u64 = 0,
    class_atom: u16 = 0,
    wnd_proc: u64 = 0,
    user_data: u64 = 0,
    style: u32 = 0,
    ex_style: u32 = 0,
    message_only: bool = false,
    /// The guest thread that created the window. Win32 queues a window's
    /// messages to that thread, and only its GetMessage/PeekMessage sees
    /// them; see `windowsMessageBelongsToCaller`.
    creator_thread_id: u64 = 0,
    /// Win32 does not queue WM_PAINT.  It keeps a per-window update region
    /// and synthesizes WM_PAINT inside GetMessage/PeekMessage for as long as
    /// that region is non-empty.  A guest that paints through
    /// InvalidateRect + WM_PAINT (the normal Win32 idiom) never repaints if
    /// the update region is not modelled, so retain it here.
    update_region_pending: bool = false,
};

const WindowsMessageDispatchFrame = struct {
    return_rip: u64 = 0,
    return_rsp: u64 = 0,
    return_is_direct: bool = false,
    pending_function: bool = false,
    saved_abi: ?windows_guest_abi.Snapshot = null,
    hwnd: u64 = 0,
    message: u32 = 0,
    wndproc: u64 = 0,
};

const WindowsAudioCallbackFrame = struct {
    return_rip: u64 = 0,
    return_rsp: u64 = 0,
    return_is_direct: bool = false,
};

/// The PE Xenia build reaches audio through SDL's WinMM backend.  Rosetta
/// keeps the device virtual and guest-owned: the device records the format,
/// completes prepared buffers deterministically, and can re-enter the guest
/// callback that releases SDL's semaphore without exposing a host pointer.
/// What a pending return-value capture is for.
const GuestReturnCaptureKind = enum(u8) {
    none,
    gpu_register_read,
    vfs_resolve,
    ui_font_rgba,
    ui_scissor,
    ui_pipelines,
    xenia_presenter_getter,
    xenia_ui_deferred,
    /// `ROSETTE_PE64_CALL_PROBE`; tag = probe index, outputs = call number
    /// and entry step.
    call_probe,
};

/// A call whose return value Rosette wants, recorded at the call and
/// completed by the `ret` that leaves it. The callee's final `ret` leaves the
/// stack pointer exactly where it was before the `call` pushed its return
/// address, so that value identifies the matching `ret` without a table of
/// return addresses or a per-instruction check.
const GuestReturnCapture = struct {
    kind: GuestReturnCaptureKind = .none,
    return_rsp: u64 = 0,
    tag: u32 = 0,
    /// Guest output references. Kept in the thread's capture, not a shared
    /// pending record that a cooperative worker could overwrite.
    outputs: [4]u64 = .{ 0, 0, 0, 0 },
};

/// A dedicated outer-scope witness for Xenia::Emulator::Setup. The ordinary
/// return-capture slot can be replaced by a nested instrumented call during
/// setup, so this small record tracks only the setup call's thread and exact
/// return address and cannot be displaced by subsystem probes.
const XeniaSetupTrace = struct {
    pending: bool = false,
    thread: u64 = 0,
    return_rip: u64 = 0,
    entry_step: u64 = 0,
    emulator: u64 = 0,
    window: u64 = 0,
    imgui_drawer: u64 = 0,
    returns: u64 = 0,
    last_status: u32 = 0,
    last_return_step: u64 = 0,
};

const GPU_REGISTER_TRAFFIC_CAPACITY: usize = 64;

/// One Xenos register the title read or wrote through Xenia's MMIO
/// callbacks, by index.
const GpuRegisterTraffic = struct {
    index: u16 = 0,
    reads: u64 = 0,
    writes: u64 = 0,
    read_returns: u64 = 0,
    read_value_changes: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    last_read_value: u32 = 0,
    last_write_value: u32 = 0,
    /// Guest thread slot plus one; zero is the owner context.
    last_thread_slot: u8 = 0,
};

/// How many indirect buffers one decoded window remembers the target of.
const GPU_RING_WINDOW_INDIRECT_BUFFERS: usize = 4;
/// Indirect buffers decoded and kept for the exit report.
const GPU_INDIRECT_BUFFER_CAPACITY: usize = 8;

/// Offsets into Xenia's `PPCContext`, read from this image rather than the
/// header's comments, which are stale: the export trampolines load r3 from
/// +0x40 and r5 from +0x50, `PPCHIRBuilder::LoadLR` and `LoadCTR` use 0x130
/// and 0x128, and every trampoline adds +0xA98 as the virtual membase.
const PPC_CONTEXT_GPR_BASE: u64 = 0x28;
const PPC_CONTEXT_LINK_REGISTER: u64 = 0x130;
const PPC_CONTEXT_VIRTUAL_MEMBASE: u64 = 0xA98;
/// Below this no thread's stack can be: it is the guest's null page.
const STACK_COLLAPSE_FLOOR: u64 = 0x10000;
const BLOCK_JIT_HOOK_FILTER_BYTES: usize = block_jit.hook_filter_bytes;

fn ppcContextGpr(index: u6) u64 {
    return PPC_CONTEXT_GPR_BASE + @as(u64, index) * 8;
}

/// Windows never maps the first 64 KiB of a process.
const WINDOWS_NULL_PAGE_LIMIT: u64 = 0x1_0000;
/// `GetCurrentThread()`'s pseudo-handle, `(HANDLE)-2`.
const WINDOWS_CURRENT_THREAD_PSEUDO_HANDLE: u64 = 0xFFFF_FFFF_FFFF_FFFE;
/// `MAXIMUM_SUSPEND_COUNT`: SuspendThread fails past it.
const WINDOWS_MAXIMUM_SUSPEND_COUNT: u32 = 127;
/// Bytes of `ROSETTE_XENIA_FATAL_POINT_ALLOW` kept.
const WINDOWS_FATAL_POINT_ALLOW_BYTES: usize = 512;

const GUEST_FILE_REQUEST_PREVIEW_BYTES: usize = 48;

/// The object name one `NtCreateFile`/`NtOpenFile` call carried, read from
/// the PPC context at the export trampoline before Xenia touches it.
const GuestFileRequest = struct {
    captured: bool = false,
    step: u64 = 0,
    kernel_slot: u32 = 0,
    context: u64 = 0,
    link_register: u32 = 0,
    desired_access: u32 = 0,
    object_attributes: u32 = 0,
    root_directory: u32 = 0,
    name_pointer: u32 = 0,
    name_length: u16 = 0,
    name_maximum: u16 = 0,
    name_buffer: u32 = 0,
    /// How far the capture read: 0 the context, 1 OBJECT_ATTRIBUTES, 2 the
    /// ANSI_STRING, 3 its buffer.
    depth: u8 = 0,
    unreadable: bool = false,
    preview: [GUEST_FILE_REQUEST_PREVIEW_BYTES]u8 = [_]u8{0} ** GUEST_FILE_REQUEST_PREVIEW_BYTES,
    preview_len: u8 = 0,

    pub fn previewText(self: *const GuestFileRequest) []const u8 {
        return self.preview[0..self.preview_len];
    }
};

/// What the name behind an empty `ResolvePath` looked like when it was passed.
const GuestFileNameShape = enum {
    unattributed,
    unreadable,
    no_object_attributes,
    no_name,
    zero_length_with_text,
    zero_length_empty,
    blank_text,
    named,

    pub fn owner(self: GuestFileNameShape) []const u8 {
        return switch (self) {
            .unattributed, .named => "xenia:vfs",
            .unreadable => "rosette:capture",
            .zero_length_with_text => "rosette:crt-or-interpreter",
            .no_object_attributes, .no_name, .zero_length_empty, .blank_text => "guest:title",
        };
    }

    pub fn meaning(self: GuestFileNameShape) []const u8 {
        return switch (self) {
            .unattributed => "no NtCreateFile or NtOpenFile was captured on this thread before the resolve, so the empty path reached ResolvePath from another caller; resolve_caller names it",
            .unreadable => "Rosette could not read the request's guest memory through the context's membase, so the name's shape is unknown; that is Rosette's capture failing, not a finding about the title",
            .no_object_attributes => "the title passed no OBJECT_ATTRIBUTES at all",
            .no_name => "OBJECT_ATTRIBUTES.ObjectName is null, so Xenia read an ANSI_STRING from guest address 0",
            .zero_length_with_text => "the ANSI_STRING's Length is 0 while its buffer holds text: the name exists and its length was lost before the call. On 2026-09-13 all 68 carried MaximumLength=1, which is RtlInitAnsiString's strlen+1 with strlen answering 0: Rosette's strlen import could not read Xenia's guest address space. That reader is fixed and an unreadable CRT pointer is now its own fatal point (crt-pointer-unreadable), so this shape recurring means some other length computation lost the name; title_lr names the title code that built it and the preview is the path it meant",
            .zero_length_empty => "the ANSI_STRING's Length is 0 and its buffer is empty: the title asked for a file whose name is an empty string. The name came from data the title read or built, and a title reading its file table from unreadable media gets empty names, so the ISO read failures and PE64 AUDIT INPUTS before this step are the next evidence",
            .blank_text => "the name is only whitespace, which Xenia's TranslateAnsiPath trims to nothing",
            .named => "the request carried a real name, so the empty path was produced inside Xenia between the export and ResolvePath",
        };
    }
};

/// Win32's MAXIMUM_WAIT_OBJECTS.
const WINDOWS_WAIT_MULTIPLE_CAPACITY: usize = 64;

/// What `WaitForMultipleObjects` decided at the cooperative boundary.
const WindowsMultiWaitResult = union(enum) {
    /// The worker is parked; the import finishes when it resumes.
    blocked,
    /// WAIT_OBJECT_0 plus this index.
    signaled: u32,
    timeout,
    invalid,
    /// A handle Rosette has no object behind.
    unknown: u64,
    /// The owner context took a worker turn instead of parking.
    yielded,
    /// Parallel mode, the owner: slept for a slice and not satisfied yet;
    /// the import stays at its call site (see `WindowsWaitResult.retry`).
    retry,
};

const GPU_RING_WINDOW_CAPACITY: usize = 8;
const GPU_RING_WINDOW_FIRST_DWORDS: usize = 8;
const GPU_RING_WINDOW_OPCODES: usize = 12;
/// The most dwords one write-pointer update is decoded for. A title's first
/// submissions are tens of dwords; this only bounds a pathological jump.
const GPU_RING_WINDOW_DECODE_LIMIT: u64 = 4096;
/// How many dwords of a window are also read through the title's virtual
/// aliases of the same physical page.
const GPU_RING_WINDOW_ALIAS_CHECKS: u64 = 64;

/// What one write-pointer update moved the ring over, decoded the way Xenia's
/// `ExecutePacket` reads it.
const GpuRingWindow = struct {
    const EventWrite = struct { initiator: u32 = 0, address: u32 = 0, value: u32 = 0 };
    step: u64 = 0,
    from_index: u32 = 0,
    to_index: u32 = 0,
    dwords: u32 = 0,
    decoded: u32 = 0,
    readable: bool = false,
    zero_dwords: u32 = 0,
    marker_dwords: u32 = 0,
    type0: u32 = 0,
    type1: u32 = 0,
    type2: u32 = 0,
    type3: u32 = 0,
    type3_opcodes: [GPU_RING_WINDOW_OPCODES]u8 = [_]u8{0} ** GPU_RING_WINDOW_OPCODES,
    type3_opcode_count: u8 = 0,
    event_write_count: u32 = 0,
    last_event_writes: [4]EventWrite = [_]EventWrite{.{}} ** 4,
    first_dwords: [GPU_RING_WINDOW_FIRST_DWORDS]u32 = [_]u32{0} ** GPU_RING_WINDOW_FIRST_DWORDS,
    first_dword_count: u8 = 0,
    alias_checks: u16 = 0,
    alias_mismatches: u16 = 0,
    /// DRAW_INDX, DRAW_INDX_2 and their binned forms.
    draw_packets: u32 = 0,
    /// XE_SWAP, the packet Xenia's own swap path writes for a frame.
    swap_packets: u32 = 0,
    /// The front-buffer texture fetch constant `VdSwap` writes as a type-0
    /// packet to SHADER_CONSTANT_FETCH_00_0 immediately before XE_SWAP, and
    /// the XE_SWAP payload itself. This is the title's own description of
    /// what it is asking to be shown: format, tiling, endianness and size.
    swap_fetch_seen: bool = false,
    swap_fetch: [6]u32 = @splat(0),
    /// A fetch written to the conventional texture slot is not necessarily
    /// the front buffer. Titles reuse that register for ordinary textures,
    /// so keep a candidate pending until the following packet proves that it
    /// is the fetch VdSwap paired with the swap packet.
    pending_swap_fetch_valid: bool = false,
    pending_swap_fetch: [6]u32 = @splat(0),
    swap_frontbuffer: u32 = 0,
    swap_width: u32 = 0,
    swap_height: u32 = 0,
    /// Type-0 writes that land in the DC_LUT register range. These are the
    /// only gamma-ramp writes Xenia's command processor applies; the same
    /// registers written through the MMIO aperture are stored and ignored.
    dc_lut_type0_writes: u32 = 0,
    /// INDIRECT_BUFFER and INDIRECT_BUFFER_PFD targets as Xenia reads them:
    /// the address through GpuToCpu and the length masked to 20 bits.
    indirect_buffers: u8 = 0,
    indirect_addresses: [GPU_RING_WINDOW_INDIRECT_BUFFERS]u32 = [_]u32{0} ** GPU_RING_WINDOW_INDIRECT_BUFFERS,
    indirect_dwords: [GPU_RING_WINDOW_INDIRECT_BUFFERS]u32 = [_]u32{0} ** GPU_RING_WINDOW_INDIRECT_BUFFERS,
};

const GUEST_VFS_RESOLVE_CAPACITY: usize = 32;
const GUEST_VFS_PATH_BYTES: usize = 96;

/// One path Xenia's virtual file system was asked to resolve.
const GuestVfsResolve = struct {
    path: [GUEST_VFS_PATH_BYTES]u8 = [_]u8{0} ** GUEST_VFS_PATH_BYTES,
    path_len: u8 = 0,
    truncated: bool = false,
    calls: u64 = 0,
    found: u64 = 0,
    not_found: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    caller_rip: u64 = 0,
    kernel_slot: u32 = 0,
    thread_slot: u8 = 0,

    pub fn pathText(self: *const GuestVfsResolve) []const u8 {
        return self.path[0..self.path_len];
    }
};

const GuestVfsResolveSummary = struct {
    bare_module_calls: u64 = 0,
    bare_module_not_found: u64 = 0,
    bare_module_paths: u64 = 0,
    bare_module_paths_reconciled: u64 = 0,
    bare_module_unmatched_not_found: u64 = 0,
    empty_path_not_found: u64 = 0,
    device_path_not_found: u64 = 0,
};

const GUEST_MODULE_LOOKUP_CAPACITY: usize = 8;
const GUEST_MODULE_NAME_BYTES: usize = 64;

/// A bare module name Xenia printed `device not found` for.
const GuestModuleLookup = struct {
    name: [GUEST_MODULE_NAME_BYTES]u8 = [_]u8{0} ** GUEST_MODULE_NAME_BYTES,
    name_len: u8 = 0,
    lines: u64 = 0,
    first_step: u64 = 0,

    pub fn nameText(self: *const GuestModuleLookup) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// How far ahead of the host clock a WinMM stream may run before its writer
/// waits. Enough for a device's queue; small enough that the writer's loop
/// runs at the stream's rate rather than the interpreter's.
const WINDOWS_WAVE_OUT_PACING_LEAD_NS: u64 = 60 * std.time.ns_per_ms;

const WindowsWaveOutDevice = struct {
    guest_handle: u64 = 0,
    callback: u64 = 0,
    instance: u64 = 0,
    open_flags: u64 = 0,
    format_tag: u16 = 0,
    channels: u16 = 0,
    sample_rate: u32 = 0,
    block_align: u16 = 0,
    bits_per_sample: u16 = 0,
    opened: bool = false,
    paused: bool = true,
    prepared_headers: u32 = 0,
    prepared_header_ptrs: [MAX_WINDOWS_WAVE_HEADERS]u64 = [_]u64{0} ** MAX_WINDOWS_WAVE_HEADERS,
    submitted_buffers: u64 = 0,
    /// Host monotonic time at which the audio this device has accepted will
    /// have played. See `paceWindowsWaveOutWrite`.
    paced_until_ns: u64 = 0,
    pacing_waits: u64 = 0,
};

/// Host operations the PE runner may use while translating a Windows UI.
///
const host_interfaces = @import("windows_guest/host_interfaces.zig");
pub const WindowsGraphicsHooks = host_interfaces.WindowsGraphicsHooks;
pub const WindowsInputState = host_interfaces.WindowsInputState;
pub const WindowsInputHooks = host_interfaces.WindowsInputHooks;
pub const WindowsAudioHooks = host_interfaces.WindowsAudioHooks;

const graphics_state = @import("windows_ui/graphics_state.zig");
pub const WindowsGraphicsPhase = graphics_state.WindowsGraphicsPhase;
pub const WindowsGraphicsSnapshot = graphics_state.WindowsGraphicsSnapshot;
pub const WindowsGraphicsState = graphics_state.WindowsGraphicsState;
pub const WINDOWS_CW_USEDEFAULT = graphics_state.WINDOWS_CW_USEDEFAULT;
pub const WINDOWS_DEFAULT_WIDTH = graphics_state.WINDOWS_DEFAULT_WIDTH;
pub const WINDOWS_DEFAULT_HEIGHT = graphics_state.WINDOWS_DEFAULT_HEIGHT;
pub const WINDOWS_MAX_DIMENSION = graphics_state.WINDOWS_MAX_DIMENSION;

const ElfTraceEntry = struct {
    rip: u64 = 0,
    op: Op = .invalid,
    len: u8 = 0,
    rsp: u64 = 0,
    rax: u64 = 0,
    rcx: u64 = 0,
    rdx: u64 = 0,
};

// ─── Shared x64 execution types ───

pub const ElfRegs = x64_decoder.Regs;
pub const Size = x64_decoder.OperandSize;
pub const RegId = x64_decoder.RegId;
pub const Cond = x64_decoder.Condition;
pub const Op = x64_decoder.Op;
pub const DecodedInsn = x64_decoder.DecodedInsn;
pub const DynamicRelocation = elf_loader.DynamicRelocation;
pub const LocalSymbol = elf_loader.Symbol;
const BitScanKind = x64_decoder.BitScanKind;

const ParallelFaultRecord = struct {
    regs: ElfRegs,
    thread_slot: ?usize,
    op: Op,
    len: u8,
};
const ParallelFaultSnapshot = parallel_fault.First(ParallelFaultRecord);

/// The x87 register file is an eight-entry circular stack of 80-bit values.
/// Keeping the bytes, rather than only an f64 approximation, matters for
/// code that uses x87 as a transport for opaque data.  MinGW's formatter does
/// exactly that while copying a 16-byte custom-format record: FLD/FSTP m80
/// must preserve every byte or a function pointer loses its low bits.
const X87Raw = [10]u8;

const PE_MAX_INSTRUCTION_LENGTH: usize = 15;
/// The PE route used to use one direct-mapped slot per hash bucket. That made
/// two unrelated Xenia code-cache addresses sharing a bucket evict each other
/// on every return, so a cache *collision* looked like an ordinary miss and
/// could burn a large part of the interpreter. Keep the number of buckets at
/// 65,536 (the old table's lookup spread) and then expanded to four ways
/// across 262,144 sets. A first-touch fill remains normal; a full set is a
/// correctness/performance failure and is reported separately.
///
/// The first expanded layout's four-way geometry gave a large address-space
/// spread, but a normal ~188K-instruction working set still had a measurable
/// Poisson tail of five-address sets. The eight-way follow-up pushed that tail
/// out, but a longer font-atlas run eventually filled one set at step 50M.
/// Keep the same one-million-entry memory budget and move two more bits of
/// capacity from the set index into associativity: sixteen ways across 65,536
/// sets. This preserves the bounded allocation while making the observed
/// instruction working set robust over a long run; a seventeenth resident is
/// still an explicit fatal contract violation.
const PE_DECODE_CACHE_WAYS: usize = 16;
const PE_DECODE_CACHE_SETS: usize = 1 << 16;
const PE_DECODE_CACHE_ENTRIES: usize = PE_DECODE_CACHE_SETS * PE_DECODE_CACHE_WAYS;
const PE_DECODE_CACHE_LOCAL_ENTRIES: usize = worker_local_decode.default_capacity;
/// A small, set-associative victim bank catches the short-lived eviction
/// bursts that still occur in a long Xenia run without weakening the primary
/// cache's full-set diagnostic. Four ways keeps a victim probe bounded: a
/// linear 4096-entry scan would cost more than the decode it is meant to save.
const PE_DECODE_CACHE_VICTIM_WAYS: usize = 4;
const PE_DECODE_CACHE_VICTIM_SETS: usize = 1 << 10;
const PE_DECODE_CACHE_VICTIM_ENTRIES: usize =
    PE_DECODE_CACHE_VICTIM_SETS * PE_DECODE_CACHE_VICTIM_WAYS;

/// The PE decode tables are shared by the cooperative owner and its worker
/// snapshots. Parallel guest mode takes this lock around decode-cache
/// replacement; ordinary execution remains lock-free. Code writes in that
/// mode bypass generation fast paths and invalidate the tables when the mode
/// is left, so the generation words themselves do not become racy metadata.
var coordinated_decode_cache_mutex = HostMutex.init("decode cache (parallel)");
/// Parallel executors' decode-cache locks. The old 1024 stripes made 64
/// unrelated sets serialize on each lock; the 2026-09-27 profile showed the
/// shared decode path dominating worker time. 4096 stripes cut those false
/// lock collisions by four while keeping the cache-line-aligned lock table
/// bounded to roughly half a megabyte.
const decode_cache_set_lock_count = 4096;
var decode_cache_set_locks: [decode_cache_set_lock_count]concurrency.mutex.LeanMutex = [_]concurrency.mutex.LeanMutex{.{}} ** decode_cache_set_lock_count;
/// The victim bank and miss diagnostics span sets; taken after a set lock.
var decode_cache_miss_mutex = HostMutex.init("decode cache victims and findings");

/// Hot decode-cache counters and primary LRU clocks, sharded by the same
/// stripe as the corresponding set. Updating one process-wide `hits` counter
/// and clock on every interpreted instruction made the cache line itself a
/// coherence bottleneck across workers, and the plain shared writes raced.
/// Every primary resident in one set shares its shard, so its timestamps stay
/// directly comparable for replacement.
const DecodeCacheCounters = struct {
    hits: u64 = 0,
    worker_local_hits: u64 = 0,
    rearms: u64 = 0,
    misses: u64 = 0,
    collisions: u64 = 0,
    vacant_fills: u64 = 0,
    conflict_fills: u64 = 0,
    generated_conflict_fills: u64 = 0,
    image_conflict_fills: u64 = 0,
    stale_refills: u64 = 0,
    replacements: u64 = 0,
    victim_hits: u64 = 0,
    victim_fills: u64 = 0,
    victim_stale_rejections: u64 = 0,

    pub fn accumulate(self: *DecodeCacheCounters, other: DecodeCacheCounters) void {
        inline for (.{
            "hits",
            "rearms",
            "misses",
            "collisions",
            "vacant_fills",
            "conflict_fills",
            "generated_conflict_fills",
            "image_conflict_fills",
            "stale_refills",
            "replacements",
            "victim_hits",
            "victim_fills",
            "victim_stale_rejections",
        }) |field| {
            @field(self, field) +|= @field(other, field);
        }
    }
};

const DecodeCacheShard = struct {
    counters: DecodeCacheCounters = .{},
    age_clock: u64 align(128) = 0,
};

fn peDecodeCacheSetIndex(address: u64) usize {
    // Instruction starts are not necessarily aligned: a valid x86
    // instruction may begin at the byte immediately after another one. Keep
    // the low address bit in the set hash; dropping it aliases adjacent
    // instructions and turns ordinary sequential execution into artificial
    // set pressure. A multiplicative mix folded with its high half spreads
    // both nearby bytes and high image/JIT bits; the older XOR folds let
    // unrelated Xenia functions cancel into one set. The full address
    // remains the cache identity check.
    const mixed = address *% 0x9E3779B97F4A7C15;
    return @intCast((mixed ^ (mixed >> 32)) & (PE_DECODE_CACHE_SETS - 1));
}

/// Return the first way of a cache set. Keeping this as the public indexing
/// helper for the local tests makes the flat allocation layout explicit:
/// `peDecodeCacheIndex(address) .. + PE_DECODE_CACHE_WAYS` is one set.
fn peDecodeCacheIndex(address: u64) usize {
    return peDecodeCacheSetIndex(address) * PE_DECODE_CACHE_WAYS;
}

fn peDecodeCacheVictimIndex(address: u64) usize {
    // Use the primary set hash here as well: every displaced resident from a
    // primary set has a bounded, predictable victim neighborhood. The victim
    // bank has fewer sets, so fold the high set bits rather than simply
    // truncating the primary index.
    const primary = peDecodeCacheSetIndex(address);
    const mixed = primary ^ (primary >> 10) ^ (primary >> 20);
    return (mixed & (PE_DECODE_CACHE_VICTIM_SETS - 1)) * PE_DECODE_CACHE_VICTIM_WAYS;
}

// Relocations are limited to the final CALL displacement. All stack-object
// offsets and both loop branches are fixed by this byte-level admission.
const xenia_sha1_kernel_feed_body = [_]u8{
    0x49, 0xff, 0xc7, 0x4d, 0x39, 0xfc, 0x74, 0x46,
    0x42, 0x0f, 0xb6, 0x04, 0x3b, 0x48, 0x8b, 0x8c,
    0x24, 0x80, 0,    0,    0,    0x48, 0x8d, 0x51,
    0x01, 0x48, 0x89, 0x94, 0x24, 0x80, 0,    0,
    0,    0x88, 0x44, 0x0c, 0x3c, 0x48, 0xff, 0x84,
    0x24, 0x88, 0,    0,    0,    0x48, 0x83, 0xbc,
    0x24, 0x80, 0,    0,    0,    0x40, 0x75, 0xc8,
    0x48, 0xc7, 0x84, 0x24, 0x80, 0,    0,    0,
    0,    0,    0,    0,    0x48, 0x89, 0xf9, 0xe8,
};

/// A small set-associative cache for the raw instruction decode used by the
/// PE64 runner. The resolved effective address is deliberately not cached:
/// it depends on the live register file, while the opcode/prefix/operand
/// description does not. A validated executable-image or backing-mapping
/// generation admits a hit; otherwise source bytes are compared. Data writes
/// outside executable image ranges do not invalidate image decodes.
const DecodeCacheEntry = struct {
    valid: bool = false,
    fetch_address: u64 = 0,
    /// Mapped instructions carry the backing identity and generation; image
    /// instructions carry an executable-range generation when available.
    /// Unproven image fetches remain byte-checked.
    mapped_source: bool = false,
    source_kind: mapped_ranges.Kind = .memory_view,
    source_index: usize = 0,
    source_generation: u64 = 0,
    /// Monotonic replacement age. This is only consulted after every way in
    /// the set is occupied; it keeps a hot instruction from being evicted by
    /// a short-lived generated-code burst.
    last_used: u64 = 0,
    bytes: [PE_MAX_INSTRUCTION_LENGTH]u8 = [_]u8{0} ** PE_MAX_INSTRUCTION_LENGTH,
    /// Segment selection depends only on the decoded prefix and addressing
    /// form, not on live register values. Retain it with the decode so cache
    /// hits do not rescan legacy prefixes before every effective-address
    /// calculation.
    segment: x64_decoder.Segment = .ds,
    decoded: DecodedInsn = .{},
};

/// Repeated instructions may be served from a host thread's private working
/// set before touching the shared set-associative cache. The entry is still
/// checked against coordinated live bytes in parallel mode; this tier skips
/// shared-cache locking, not self-modifying-code validation.
const WorkerLocalDecodeCache = worker_local_decode.Cache(DecodeCacheEntry, PE_DECODE_CACHE_LOCAL_ENTRIES);

const DecodeCacheMissCause = enum {
    vacant_fill,
    capacity_conflict,
    stale_bytes,

    pub fn label(self: DecodeCacheMissCause) []const u8 {
        return switch (self) {
            .vacant_fill => "vacant-fill",
            .capacity_conflict => "capacity-conflict",
            .stale_bytes => "stale-bytes",
        };
    }

    pub fn fatalLabel(self: DecodeCacheMissCause) []const u8 {
        return switch (self) {
            .vacant_fill => "",
            .capacity_conflict => "decode-cache-conflict",
            .stale_bytes => "decode-cache-stale-bytes",
        };
    }
};

/// One bounded cache-miss site.  The hot path only increments the aggregate
/// counters and records a site when a miss occurs; cache hits never touch this
/// table.  `mapped_source` distinguishes image code from Xenia-generated code
/// so a capacity conflict in the JIT working set cannot be mistaken for a
/// self-modifying image write.
const DecodeCacheMissSite = struct {
    cause: DecodeCacheMissCause = .vacant_fill,
    fetch_address: u64 = 0,
    set_index: usize = 0,
    mapped_source: bool = false,
    source_kind: WindowsMappedCodeKind = .memory_view,
    source_index: usize = 0,
    source_generation: u64 = 0,
    resident_addresses: [PE_DECODE_CACHE_WAYS]u64 = @splat(0),
    resident_count: usize = 0,
    occurrences: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    first_rip: u64 = 0,
    last_rip: u64 = 0,
};

/// One remembered CLEO routing decision per (op, operand width). The router's
/// answer is a pure function of the mnemonic, the host's constant feature
/// set and the width, so a module-level memo is correct for every state
/// sharing this binary; it is filled lazily and idempotently.
const CleoRoutingDecision = @typeInfo(@TypeOf(cleo_routing.CleoRouter.route)).@"fn".return_type.?;
const CleoRouteMemo = struct {
    decided: bool = false,
    decision: CleoRoutingDecision = .{ .can_route = false, .meta = null, .features = undefined },
};
var cleo_route_memo: [ElfState.op_value_limit][2]CleoRouteMemo = [_][2]CleoRouteMemo{[_]CleoRouteMemo{.{}} ** 2} ** ElfState.op_value_limit;
var cleo_route_memo_mutex = HostMutex.init("CLEO route memo");

fn cleoRouteFor(op: Op, vector_256: bool, synchronize: bool) CleoRoutingDecision {
    const memo = &cleo_route_memo[@intFromEnum(op)][@intFromBool(vector_256)];
    if (synchronize) {
        cleo_route_memo_mutex.lock();
        defer cleo_route_memo_mutex.unlock();
        if (!memo.decided) {
            memo.decision = cleo_routing.CleoRouter.route(
                @tagName(op),
                cleo_routing.types.FeatureSet.cleoEmulated(),
                if (vector_256) 256 else 128,
            );
            memo.decided = true;
        }
        return memo.decision;
    }
    if (!memo.decided) {
        memo.decision = cleo_routing.CleoRouter.route(
            @tagName(op),
            cleo_routing.types.FeatureSet.cleoEmulated(),
            if (vector_256) 256 else 128,
        );
        memo.decided = true;
    }
    return memo.decision;
}

// ─── Block translation ───
//
// The second execution tier. `block_jit.zig` turns a straight-line run of
// guest instructions into one ARM64 function; this section owns discovery
// (which addresses are hot), the block cache and its invalidation, the
// helpers the emitted code calls back into, the accounting that keeps every
// per-instruction counter honest, and the cross-check that runs a
// register-only block through the interpreter once before trusting it.

const block_jit = @import("block_jit.zig");
/// When a dropped block may be freed and a full code memory reset: never
/// while an outer translated block is still on the host stack.
const block_lifetime = @import("block_jit/lifetime.zig");

/// Direct-mapped block and hotness tables, indexed by a hash of the RIP.
/// The 64K table produced millions of slot evictions in long PE runs while
/// only a small fraction of the slots were live at exit.  Four times the
/// slots keeps the same lookup semantics and sharply lowers address aliasing
/// without making the code cache itself unbounded.
// 2026-09-21: 338,808 evictions against 561,989 compiles - 60% of all
// compiles were recompiles of evicted blocks - with the table only 21%
// live at exit. Xenia keeps generating code for the whole run, so the
// working set of start addresses is far larger than what is live at any
// moment. A million slots in four ways is 8 MiB of pointers.
const BLOCK_JIT_TABLE_ENTRIES: usize = 1 << 20;
/// Slots per set. A direct-mapped table evicts whenever two hot addresses
/// share an index; the 2026-09-19 run evicted 1.75M blocks over 3.35M
/// compiles. Two candidates per index keep the same memory and the same
/// probe cost, and turn most of those evictions into second-way fills.
const BLOCK_JIT_WAYS: usize = 4;
/// Executions of a start address before it is compiled. Most addresses run
/// once; compiling on first sight would spend more on cold code than the
/// interpreter would have.
const BLOCK_JIT_DEFAULT_HOT_THRESHOLD: u16 = 16;
/// The most guest instructions one block covers.
const BLOCK_JIT_MAX_INSTRUCTIONS: usize = 128;
/// Code pages for `code_page_generations`. A block's bytes fit in one page,
/// so a block covers at most the page it starts on and the next.
const CODE_PAGE_SHIFT: u6 = 12;
const CODE_PAGE_GENERATION_BITS: u6 = 18;
const CODE_PAGE_GENERATION_SLOTS: usize = 1 << CODE_PAGE_GENERATION_BITS;
comptime {
    std.debug.assert(BLOCK_JIT_MAX_INSTRUCTIONS * PE_MAX_INSTRUCTION_LENGTH <= @as(usize, 1) << CODE_PAGE_SHIFT);
}
/// How many conditional branches one block may continue across.
///
/// Every one adds an exit stub and, because the code after it can also be
/// reached by a jump from elsewhere, may duplicate that code into a second
/// block. Both cost translation-cache space, which is already the thing 12
/// resets a run were about. Eight buys most of the block-length increase -
/// x86 branches roughly every seven instructions, so eight conditionals is
/// already the 48-instruction ceiling - while keeping the exit stubs per
/// block bounded.
// 2026-09-20: the first run with traces on averaged 2.97 conditionals per
// compiled block against a limit of 8, so this was not what ended most
// blocks - unconditional transfers were. Raised with the instruction
// ceiling because the two together decide how long a hot loop body may
// become; `conditionals_followed` against `compiled` says if either binds.
const BLOCK_JIT_MAX_CONDITIONALS: u32 = 24;
/// Executable memory for translated code. Exhaustion drops every block and
/// starts over; it is counted, not hidden. 64 MiB filled 24 times in the
/// 2026-09-19 run and each reset recompiled some 50,000 live blocks after
/// sixteen interpreted runs apiece; the reservation is virtual, so four
/// times that costs nothing until it is written.
// 2026-09-20: traces took `code_bytes(used)` from 40% of 256 MiB to 72%
// with 7 resets still in the run, which makes this number - not the
// guest's control flow - the thing capping how long a trace is worth
// making. The mapping is reserved, not committed.
// 2026-09-21: 603 MiB of 768 used with 2 resets, most of it code for
// blocks later evicted. The reservation is virtual until written.
const BLOCK_JIT_CODE_BYTES: usize = 1536 << 20;
/// How far one `step` may follow blocks into each other before returning to
/// the run loop. Every block boundary used to cost a full `step` (the three
/// hook gates, the hotness probe, the loop's own per-step bookkeeping) and
/// call-heavy code makes a block every four to six instructions. The bound
/// keeps the scheduler, the clock and the spin probes at their cadence.
const BLOCK_JIT_CHAIN_BLOCKS: u32 = 64;
const BLOCK_JIT_CHAIN_INSTRUCTIONS: u32 = 2048;
/// The same bound for a parallel executor, which runs one guest thread on a
/// host thread of its own: nothing the cooperative bound protects is shared
/// there. The clock counts this thread's own retirement, a yield, handoff or
/// thread switch still ends the chain at the next block, and a
/// stop-the-world waits at most one chain. What a return through `step`
/// costs is real: the execution gate, the store-buffer and thread-local
/// setup, the hook gates and the table probe, about a third of a
/// microsecond, which at the cooperative bound was at least 36 million
/// round trips for Halo 3's main thread in a 188 s run.
const BLOCK_JIT_PARALLEL_CHAIN_BLOCKS: u32 = 256;
const BLOCK_JIT_PARALLEL_CHAIN_INSTRUCTIONS: u32 = 16384;
/// Sample each operation's interpreted cost once, then once per this many
/// fallbacks. The estimate is cumulative wall time, while the sampler adds
/// only two monotonic-clock reads per sample rather than timing every guest
/// instruction.
const BLOCK_JIT_FALLBACK_COST_SAMPLE_PERIOD: u64 = 1024;

/// A guest thread that runs on its own host thread (parallel mode) gets its
/// own translator state, so no two threads ever share a block table, a code
/// arena, a chain link or a block's lifetime. Its table starts at a
/// sixteenth of the owner's, because a run creates dozens of threads and
/// most never get a block hot, and grows fourfold under eviction pressure
/// up to the owner's size (`BlockJitState.growIfPressed`).
// 2026-09-30: every worker was capped at the starting size. Halo 3's main
// thread ran its simulation through 64K slots against a working set the
// owner-sized table had been grown to hold on 2026-09-21: it spent 84% of
// its wall time in Rosette, 37% of it in `decodeAt`, re-interpreting
// evicted code sixteen times before each recompile.
const BLOCK_JIT_WORKER_TABLE_ENTRIES: usize = 1 << 16;
const BLOCK_JIT_WORKER_MAX_TABLE_ENTRIES: usize = BLOCK_JIT_TABLE_ENTRIES;
/// A worker's code reservation. Virtual until written, like the owner's; a
/// busy thread at 1.6 KiB of code per block filled 256 MiB and reset.
const BLOCK_JIT_WORKER_CODE_BYTES: usize = 1024 << 20;

const BlockHotness = struct {
    rip: u64 = 0,
    count: u16 = 0,
    /// Compilation was tried and produced nothing worth running, or a
    /// cross-check failed: stay with the interpreter for this address.
    refused: bool = false,
    /// Compilations retried after a refusal. A refusal used to be forever,
    /// so one that came from a passing state - the code not yet complete,
    /// a hook armed for a while - left a hot address interpreted for the
    /// rest of the run: Halo 3's RENDER thread interpreted one function
    /// entry 358 million times on 2026-10-02. `block_jit_refusal_retry_limit`
    /// marks one that may never be retried (a failed cross-check).
    retries: u8 = 0,
    /// Interpreted runs since the last refusal, for the retry: `count` stays
    /// where compilation was tried, so a refused entry is no candidate for
    /// another address to take over.
    refused_runs: u16 = 0,
};

/// Why a compilation produced no block.
const BlockJitRefusal = enum(u8) {
    /// No instruction bytes at the address.
    empty_fetch,
    /// The bytes do not decode.
    decode_failed,
    /// The first instruction is one the interpreter must run at a step
    /// boundary of its own (`block_jit.endsBlockBefore`): pause, cpuid,
    /// rdtsc and the like.
    ends_before,
    /// The mapping changed between the page probe and the first fetch.
    page_identity,
    /// Every instruction in the run is an interpreter fallback.
    nothing_to_compile,
    /// The emitter or the code memory refused.
    compile_error,
    allocation,
};

/// Refused addresses are retried after this many interpreted runs, doubling
/// each time, until `block_jit_refusal_retry_limit` retries.
const block_jit_refusal_retry_base: u16 = 1024;
const block_jit_refusal_retry_limit: u8 = 6;

/// Why a translated direct call was left to the interpreter.
const BlockJitCallRefusal = enum(u8) {
    milestone,
    hooked_target,
    no_image_bounds,
    image_local_symbols,
    call_trace,
    transfer_trace,
    kernel_census,
    accelerator_unresolved,
    accelerator_target,
    pthread_condition_entry,
};

const BlockJitState = struct {
    memory: block_jit.CodeMemory,
    blocks: []?*block_jit.Block,
    hotness: []BlockHotness,
    /// The successors this thread's blocks hopped to, by guest address,
    /// for the native chain (`block_jit.jumpCacheIndex`). Its entries name
    /// slots, never blocks, so growth, eviction and resets need not touch
    /// it: a slot that no longer holds a block for the address fails the
    /// hop's proof.
    jump_cache: []block_jit.Link = &.{},
    /// Sets in `blocks` minus one; the table's own size, since a worker's
    /// table is smaller than the owner's.
    set_mask: usize,
    /// The size `growIfPressed` may take `blocks` to.
    max_entries: usize = BLOCK_JIT_TABLE_ENTRIES,
    /// Slot arrays a growth replaced. A chain link records the address of
    /// the slot its successor sat in; a replaced array is emptied, not
    /// freed, so such a link reads null, fails its check, and is re-armed
    /// against the new table the next time the hop is taken.
    retired_tables: std.ArrayListUnmanaged([]?*block_jit.Block) = .empty,
    /// Capacity pressure since the table last grew: live blocks evicted to
    /// seat a new one, and warming hotness entries a new address took over.
    pressure: u64 = 0,
    growths: u32 = 0,
    hotness_replacements: u64 = 0,
    /// Why `runBlockJit` handed a step to the interpreter: the address had
    /// not run often enough yet, compiling it was refused, or a reset was
    /// waiting for the outermost execution. One interpreted step is about a
    /// hundred times a translated one, so these are the frame-rate counters.
    interpreted_cold: u64 = 0,
    interpreted_refused: u64 = 0,
    interpreted_reset_pending: u64 = 0,
    /// Where interpreted steps land, one in `interpreted_heat_stride`.
    interpreted_heat: spin_anatomy.Heat = .{},
    /// The same for steps at addresses the translator refused to compile.
    /// RENDER took 135 million of those on 2026-09-30 with nothing saying
    /// whether they were its spin-wait or real work in an untranslatable
    /// instruction.
    refused_heat: spin_anatomy.Heat = .{},
    hot_threshold: u16 = BLOCK_JIT_DEFAULT_HOT_THRESHOLD,
    compiled: u64 = 0,
    compile_refusals: u64 = 0,
    /// Why, and the first few addresses, with the instruction each began
    /// with: a refused address is interpreted at every execution.
    refusal_reasons: [@typeInfo(BlockJitRefusal).@"enum".fields.len]u64 = @splat(0),
    refusal_sites: [8]RefusalSite = @splat(.{}),
    refusal_site_count: u8 = 0,
    refusal_retries: u64 = 0,
    last_refusal: BlockJitRefusal = .empty_fetch,
    last_refusal_op: Op = .invalid,
    compile_failures: u64 = 0,
    native_instructions_compiled: u64 = 0,
    fallback_instructions_compiled: u64 = 0,
    executions: u64 = 0,
    instructions_retired: u64 = 0,
    fallback_calls: u64 = 0,
    aborts: u64 = 0,
    continuation_write_aborts: u64 = 0,
    revalidations: u64 = 0,
    invalidations: u64 = 0,
    /// Why blocks were dropped: their bytes changed under them, their
    /// mapping went away, the code memory was reset, or a cross-check
    /// disagreed. Together with `slot_evictions` these sum to
    /// `invalidations`.
    dropped_stale: u64 = 0,
    dropped_unmapped: u64 = 0,
    dropped_reset: u64 = 0,
    dropped_mismatch: u64 = 0,
    slot_evictions: u64 = 0,
    resets: u64 = 0,
    /// Which dropped blocks must outlive a live translated execution, and
    /// whether a reset is waiting for the outermost one to return
    /// (`block_jit/lifetime.zig`).
    lifetime: BlockLifetime = .{},
    verified: u64 = 0,
    mismatches: u64 = 0,
    /// The memory-aware cross-check: blocks it compared, found different,
    /// left unchecked because an op is not journal-safe, and whose
    /// interpreted pass reached something the journal cannot model.
    verify_memory_checked: u64 = 0,
    verify_memory_mismatches: u64 = 0,
    verify_memory_unsafe: u64 = 0,
    verify_memory_failed: u64 = 0,
    /// Checks compared at the boundary where the translation left early.
    verify_memory_early_exits: u64 = 0,
    /// Register-only blocks left unchecked because they reach a hook.
    verify_skipped_hooked: u64 = 0,
    /// Instructions whose flag computation the liveness pass removed.
    flags_elided: u64 = 0,
    flags_narrowed: u64 = 0,
    /// Compiled blocks whose `ret` hands flags back to the caller: helpers
    /// that return a result in a flag, such as Xenia's stwcx. helper.
    returns_owing_flags: u64 = 0,
    /// Compiled conditional branches that test NZCV from the flag writer
    /// before them instead of reading `rflags`.
    fused_branches: u64 = 0,
    /// Compiled flag writers whose conditional readers test NZCV.
    fused_runs: u64 = 0,
    /// Blocks entered directly from the block before them, without a `step`.
    chained: u64 = 0,
    /// Direct calls whose target carries no hook, so the translator emitted
    /// a push and a jump, against those left on the interpreter's arm.
    call_targets_plain: u64 = 0,
    call_targets_hooked: u64 = 0,
    /// Dynamic indirect targets outside the PE image which reached the
    /// generated-code proof helper, and those admitted to the dedicated
    /// Xenia code-cache view.
    mapped_transfer_checks: u64 = 0,
    mapped_transfer_native: u64 = 0,
    hooked_transfer_exact_checks: u64 = 0,
    hooked_transfer_exact_claims: u64 = 0,
    hooked_transfer_filter_false_positives: u64 = 0,
    /// Exact raw x87 moves handled by the focused helper rather than the
    /// generic block-JIT interpreter boundary.
    x87_fast_helpers: u64 = 0,
    /// x87 memory arithmetic/compare instructions handled by the focused
    /// helper while the surrounding block remains translated.
    x87_memory_helpers: u64 = 0,
    /// Conditional branches a block continued across rather than ending at.
    conditionals_followed: u64 = 0,
    /// Deferred flag records actually materialised.
    flag_completions: u64 = 0,
    /// Block-to-block hops taken inside translated code, and links armed.
    native_chain_hops: u64 = 0,
    /// `executeBlockJit` calls - each one a return through `step` and its
    /// hook gates - and the links its loop made in Zig rather than in
    /// translated code. Beside `native_chain_hops` they say how much of a
    /// thread's translated work came back to the dispatcher.
    dispatch_entries: u64 = 0,
    dispatch_relinks: u64 = 0,
    /// Why each native chain came back to the glue: the step's instruction
    /// budget was spent, a helper asked for the glue (`chain_break`), or
    /// the next block was not found from translated code - no way and no
    /// jump-cache entry named it, or the one that did failed its proof.
    chain_exits_budget: u64 = 0,
    chain_exits_break: u64 = 0,
    chain_exits_miss: u64 = 0,
    links_armed: u64 = 0,
    /// Guest registers held in host registers, summed over compiled blocks.
    cached_registers: u64 = 0,
    /// Memory accesses compiled to go through a hoisted base pointer.
    hoisted_accesses: u64 = 0,
    /// The software TLB: pages admitted, refused at the helper, and the
    /// invalidations protection and mapping changes caused.
    tlb_fills: u64 = 0,
    /// FPCR writes translated `ldmxcsr` made (loads that changed FZ or
    /// RMode), harvested from the scratch record after every entry.
    fpcr_writes: u64 = 0,
    tlb_fill_refusals: u64 = 0,
    tlb_refusal_stats: tlb_diagnostics.RefusalStats = .{},
    tlb_refusal_cache: tlb_diagnostics.RefusalCache = .{},
    tlb_invalidations: u64 = 0,
    tlb_flushes: u64 = 0,
    /// Fallback calls by instruction, so the next run says which templates
    /// are missing rather than only how many calls there were.
    fallback_ops: [ElfState.op_value_limit]u64 = @splat(0),
    fallback_reason_counts: [@typeInfo(block_jit.FallbackReason).@"enum".fields.len]u64 = @splat(0),
    fallback_cost_sample_count: [ElfState.op_value_limit]u64 = @splat(0),
    fallback_cost_sampled_nanos: [ElfState.op_value_limit]u64 = @splat(0),
    /// Indirect and relative transfers the interpreter ran, by why: an
    /// import (the IAT shim owns it), a hooked target (a shim, milestone or
    /// census entry may claim it), or neither - a transfer that could have
    /// stayed native. The busiest targets are kept, so the report names the
    /// function behind each class.
    transfer_fallback_imports: u64 = 0,
    transfer_fallback_hooked: u64 = 0,
    transfer_fallback_plain: u64 = 0,
    transfer_targets: [transfer_target_slots]TransferTarget = @splat(.{}),
    transfer_target_overflow: u64 = 0,

    const RefusalSite = struct {
        rip: u64 = 0,
        reason: BlockJitRefusal = .empty_fetch,
        op: Op = .invalid,
        retries: u8 = 0,
    };

    pub const transfer_target_slots = 256;
    pub const TransferTarget = struct {
        target: u64 = 0,
        op: u16 = 0,
        hooked: bool = false,
        count: u64 = 0,
    };

    fn noteTransferTarget(self: *BlockJitState, target: u64, op: u16, hooked: bool) void {
        var slot: usize = @intCast(((target ^ (target >> 12)) *% 0x9E37_79B9) % transfer_target_slots);
        var probes: usize = 0;
        while (probes < 16) : (probes += 1) {
            const entry = &self.transfer_targets[slot];
            if (entry.count != 0 and entry.target == target and entry.op == op) {
                entry.count +|= 1;
                return;
            }
            if (entry.count == 0) {
                entry.* = .{ .target = target, .op = op, .hooked = hooked, .count = 1 };
                return;
            }
            slot = (slot + 1) % transfer_target_slots;
        }
        self.transfer_target_overflow +|= 1;
    }

    /// The first slot of the set `rip` hashes to; the set is
    /// `BLOCK_JIT_WAYS` consecutive slots.
    pub fn firstSlot(self: *const BlockJitState, rip: u64) usize {
        return @as(usize, @intCast(((rip >> 1) ^ (rip >> 17) ^ (rip >> 29)) & self.set_mask)) * BLOCK_JIT_WAYS;
    }

    pub fn create(allocator: std.mem.Allocator) ?*BlockJitState {
        return createSized(allocator, BLOCK_JIT_TABLE_ENTRIES, BLOCK_JIT_CODE_BYTES);
    }

    pub fn createSized(allocator: std.mem.Allocator, table_entries: usize, code_bytes: usize) ?*BlockJitState {
        std.debug.assert(std.math.isPowerOfTwo(table_entries / BLOCK_JIT_WAYS));
        // Ask for the full reservation, then step down rather than give up.
        // A refused `MAP_JIT` is not a small loss: `blockJitActive` records
        // the translator as unavailable for the whole run and every guest
        // instruction goes back to the interpreter, which is several times
        // slower than the lane it replaces. A smaller cache only means more
        // resets, so any of these is better than none of them.
        var memory: block_jit.CodeMemory = undefined;
        var reserved: usize = 0;
        for ([_]usize{ code_bytes, 1024 << 20, 768 << 20, 512 << 20, 256 << 20, 128 << 20, 64 << 20 }) |bytes| {
            if (bytes > code_bytes) continue;
            memory = block_jit.CodeMemory.init(bytes) catch continue;
            reserved = bytes;
            break;
        }
        if (reserved == 0) return null;
        if (reserved != code_bytes) log.info("PE64 BLOCK JIT: translation cache reserved {d} MiB of the {d} MiB asked for; expect more resets", .{ reserved >> 20, code_bytes >> 20 });
        const self = allocator.create(BlockJitState) catch return null;
        const blocks = allocator.alloc(?*block_jit.Block, table_entries) catch {
            allocator.destroy(self);
            return null;
        };
        const hotness = allocator.alloc(BlockHotness, table_entries) catch {
            allocator.free(blocks);
            allocator.destroy(self);
            return null;
        };
        // Without its jump cache the thread still chains, through its ways.
        var jump_cache: []block_jit.Link = &.{};
        if (allocator.alloc(block_jit.Link, block_jit.jump_cache_entries)) |table| {
            @memset(table, .{});
            jump_cache = table;
        } else |_| {}
        @memset(blocks, null);
        @memset(hotness, .{});
        self.* = .{ .memory = memory, .blocks = blocks, .hotness = hotness, .jump_cache = jump_cache, .set_mask = table_entries / BLOCK_JIT_WAYS - 1 };
        return self;
    }

    pub fn destroy(self: *BlockJitState, allocator: std.mem.Allocator) void {
        for (self.blocks) |*slot| {
            if (slot.*) |block| freeBlock(allocator, block);
            slot.* = null;
        }
        self.lifetime.deinit(allocator);
        allocator.free(self.blocks);
        allocator.free(self.hotness);
        if (self.jump_cache.len != 0) allocator.free(self.jump_cache);
        for (self.retired_tables.items) |table| allocator.free(table);
        self.retired_tables.deinit(allocator);
        self.memory.deinit();
        allocator.destroy(self);
    }

    pub const interpreted_heat_stride: u64 = 64;

    /// Grow the table fourfold once capacity pressure since the last growth
    /// reaches an eighth of its slots, up to `max_entries`. Only between
    /// executions: a live one may hold a slot index into this table.
    pub fn growIfPressed(self: *BlockJitState, allocator: std.mem.Allocator) bool {
        if (self.blocks.len >= self.max_entries or self.lifetime.live()) return false;
        if (self.pressure *| 8 < self.blocks.len) return false;
        return self.grow(allocator, @min(self.blocks.len * 4, self.max_entries));
    }

    /// Move every block and hotness entry into a table of `entries` slots.
    ///
    /// `firstSlot` keeps its hash and only widens the mask, so the new set
    /// of an address has the old set's index in its low bits: one old set
    /// feeds each new set, and no more than `BLOCK_JIT_WAYS` entries can
    /// arrive in any of them. Nothing is evicted by a growth.
    fn grow(self: *BlockJitState, allocator: std.mem.Allocator, entries: usize) bool {
        std.debug.assert(std.math.isPowerOfTwo(entries / BLOCK_JIT_WAYS) and entries > self.blocks.len);
        const blocks = allocator.alloc(?*block_jit.Block, entries) catch return false;
        const hotness = allocator.alloc(BlockHotness, entries) catch {
            allocator.free(blocks);
            return false;
        };
        self.retired_tables.ensureUnusedCapacity(allocator, 1) catch {
            allocator.free(hotness);
            allocator.free(blocks);
            return false;
        };
        @memset(blocks, null);
        @memset(hotness, .{});
        const old_blocks = self.blocks;
        const old_hotness = self.hotness;
        self.blocks = blocks;
        self.hotness = hotness;
        self.set_mask = entries / BLOCK_JIT_WAYS - 1;
        for (old_blocks) |maybe| {
            const block = maybe orelse continue;
            const base = self.firstSlot(block.start_rip);
            for (self.blocks[base .. base + BLOCK_JIT_WAYS]) |*slot| {
                if (slot.* == null) {
                    slot.* = block;
                    break;
                }
            } else unreachable;
        }
        for (old_hotness) |entry| {
            if (entry.rip == 0) continue;
            const base = self.firstSlot(entry.rip);
            for (self.hotness[base .. base + BLOCK_JIT_WAYS]) |*slot| {
                if (slot.rip == 0) {
                    slot.* = entry;
                    break;
                }
            } else unreachable;
        }
        // Every link into the old table now reads null and falls back to the
        // dispatcher, which re-arms it against the new slot.
        @memset(old_blocks, null);
        self.retired_tables.appendAssumeCapacity(old_blocks);
        allocator.free(old_hotness);
        self.pressure = 0;
        self.growths += 1;
        return true;
    }

    pub fn liveBlocks(self: *const BlockJitState) usize {
        var count: usize = 0;
        for (self.blocks) |slot| {
            if (slot != null) count += 1;
        }
        return count;
    }

    pub const freeBlock = freeTranslatedBlock;
};

fn freeTranslatedBlock(allocator: std.mem.Allocator, block: *block_jit.Block) void {
    allocator.free(block.insns);
    allocator.free(block.bytes);
    allocator.destroy(block);
}

const BlockLifetime = block_lifetime.Lifetime(block_jit.Block, freeTranslatedBlock);

/// `readMemVal` for emitted code. The scratch record names the instruction
/// so faults and diagnostics see the same RIP the interpreter would have set.
fn blockJitRead(state_ptr: *anyopaque, address: u64, size: u8) callconv(.c) u64 {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    self.blockJitNameCurrentInstruction();
    // In cooperative mode, a TLB miss resumes into direct accesses that must
    // see older buffered stores. Parallel mode binds no queue while its
    // direct TLB is live, and without it this helper's coordinated load
    // already forwards from the thread's queue, so that mode does not drain
    // on every memory operation (`translated_memory_contract.zig`).
    const boundary_policy = translated_memory_contract.policy(if (self.parallel_guest_execution)
        .parallel_coordinated_helpers
    else
        .cooperative_direct_tlb);
    if (boundary_policy.drain_before_read) tso_memory.flushActiveStoreBufferFor(.jit_helper);
    const value = self.readMemVal(address, @enumFromInt(size));
    if (self.guestContextField("guest_access_violation_pending").* or self.isTerminated()) {
        self.blockJitRequestAbort();
        return value;
    }
    self.blockJitTlbConsider(address, @as(u8, 1) << @intCast(size), false);
    return value;
}

fn blockJitWrite(state_ptr: *anyopaque, address: u64, size: u8, value: u64) callconv(.c) void {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    self.blockJitNameCurrentInstruction();
    const boundary_policy = translated_memory_contract.policy(if (self.parallel_guest_execution)
        .parallel_coordinated_helpers
    else
        .cooperative_direct_tlb);
    if (boundary_policy.drain_before_write) tso_memory.flushActiveStoreBufferFor(.jit_helper);
    self.writeMemVal(address, @enumFromInt(size), value);
    // Cooperative generated code may resume into direct TLB loads; publish
    // the store first. A parallel store was never queued.
    if (boundary_policy.drain_after_write) tso_memory.flushActiveStoreBufferFor(.jit_helper);
    if (self.guestContextField("guest_access_violation_pending").* or self.isTerminated() or self.blockJitContinuationChanged()) {
        self.blockJitRequestAbort();
        return;
    }
    self.blockJitTlbConsider(address, @as(u8, 1) << @intCast(size), true);
}

/// `readMem128` for emitted code: into the scratch vector slot.
fn blockJitRead128(state_ptr: *anyopaque, address: u64, out: *[16]u8) callconv(.c) void {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    self.blockJitNameCurrentInstruction();
    const boundary_policy = translated_memory_contract.policy(if (self.parallel_guest_execution)
        .parallel_coordinated_helpers
    else
        .cooperative_direct_tlb);
    if (boundary_policy.drain_before_read) tso_memory.flushActiveStoreBufferFor(.jit_helper);
    out.* = self.readMem128(address);
    if (self.guestContextField("guest_access_violation_pending").* or self.isTerminated()) {
        self.blockJitRequestAbort();
        return;
    }
    self.blockJitTlbConsider(address, 16, false);
}

/// `writeMem128` for emitted code, from the scratch vector slot.
fn blockJitWrite128(state_ptr: *anyopaque, address: u64, value: *const [16]u8) callconv(.c) void {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    self.blockJitNameCurrentInstruction();
    const boundary_policy = translated_memory_contract.policy(if (self.parallel_guest_execution)
        .parallel_coordinated_helpers
    else
        .cooperative_direct_tlb);
    if (boundary_policy.drain_before_vector_write) tso_memory.flushActiveStoreBufferFor(.jit_helper);
    self.writeMem128(address, value.*);
    if (boundary_policy.drain_after_write) tso_memory.flushActiveStoreBufferFor(.jit_helper);
    if (self.guestContextField("guest_access_violation_pending").* or self.isTerminated() or self.blockJitContinuationChanged()) {
        self.blockJitRequestAbort();
        return;
    }
    self.blockJitTlbConsider(address, 16, true);
}

/// `vmovntps`/`vmovntdq` for translated code. The native vector-store template
/// has no access to the executor's store buffer and would silently treat a
/// special backing as ordinary RAM. Reuse the interpreter's explicit
/// non-temporal policy, then offer an ordinary writable page to the TLB for
/// subsequent temporal stores.
fn blockJitWrite128NonTemporal(state_ptr: *anyopaque, address: u64, value: *const [16]u8) callconv(.c) void {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    self.blockJitNameCurrentInstruction();
    self.writeMem128NonTemporal(address, value.*);
    if (self.guestContextField("guest_access_violation_pending").* or self.isTerminated() or self.blockJitContinuationChanged()) {
        self.blockJitRequestAbort();
        return;
    }
    self.blockJitTlbConsider(address, 16, true);
}

/// An indirect block-JIT transfer may bypass the interpreter only when the
/// address is inside Xenia's dedicated code-cache view. This is the same
/// backing that `decodeAt` accepts for generated instructions; arbitrary
/// mappings, import thunks, synthetic entries, and invalid external values
/// stay on the interpreter path. The executing step holds the guest address
/// space read gate, so view/unmap operations cannot change this metadata while
/// it is inspected.
fn blockJitMappedTransferAllowed(state_ptr: *anyopaque, target: u64) callconv(.c) u8 {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    const jit = self.currentBlockJit();
    if (jit) |active| active.mapped_transfer_checks +|= 1;
    if (self.blockJitTargetHooked(target)) return 0;
    const view_index = self.windows_code_cache_view orelse return 0;
    if (view_index >= self.windows_memory_view_count) return 0;
    const view = self.windows_memory_views[view_index];
    if (view.length == 0 or target < view.guest_base or target - view.guest_base >= view.length) return 0;
    const generated = self.windowsMappedCodeMemoryConst(target, PE_MAX_INSTRUCTION_LENGTH) orelse return 0;
    if (generated.kind != .memory_view or generated.source_index != view.mapping_index) return 0;
    if (jit) |active| active.mapped_transfer_native +|= 1;
    return 1;
}

/// A translated `call [slot]` or `jmp [slot]` through an import address
/// table slot, answered on a narrow fast import lane
/// (`ElfState.tryImportSlotFastTransfer`). Xenia reaches memcpy and memset
/// through one-instruction `jmp [IAT]` thunks; before this, the translator
/// refused those thunks and every call took two interpreter steps and the
/// runtime lock - 5 million memsets on Halo 3's main thread and 7 million on
/// the GPU thread in the 2026-10-02 run.
fn blockJitImportTransfer(state_ptr: *anyopaque, slot: u64, call_return: u64) callconv(.c) u32 {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    return @intFromBool(self.tryImportSlotFastTransfer(slot, call_return));
}

/// Resolve a positive indirect-target Bloom bit against the live exact hook
/// sources. The Bloom filter is intentionally compact; after a census export
/// saturates, its bit can remain set because another address collides with it.
/// Such a collision used to send every call through the interpreter even
/// though the exact census had retired that hook.
fn blockJitHookedTransfer(state_ptr: *anyopaque, target: u64) callconv(.c) u8 {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    const jit = self.currentBlockJit();
    if (jit) |active| active.hooked_transfer_exact_checks +|= 1;
    const hooked = self.blockJitIndirectTargetHooked(target);
    if (jit) |active| {
        if (hooked) {
            active.hooked_transfer_exact_claims +|= 1;
        } else {
            active.hooked_transfer_filter_false_positives +|= 1;
        }
    }
    return @intFromBool(hooked);
}

/// One instruction through the interpreter, in the middle of a block.
/// Returns nonzero when the block must stop: the interpreter moved RIP
/// somewhere other than the next instruction, ended the run, left a fault
/// pending, switched guest threads, or asked for the slice to end.
/// Apply the deferred flag record to `rflags` and clear it.
///
/// Translated arithmetic computes only the flags a later instruction in its
/// own block reads, and records `a op b = r` for the rest: materialising all
/// six costs about thirty ARM instructions and a block otherwise pays that
/// at every arithmetic instruction. This is where the rest is paid - once,
/// on the way out of the block, and only when a record is pending.
fn blockJitFlags(state_ptr: *anyopaque) callconv(.c) void {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    const record = &self.guestContextField("block_jit_scratch").*;
    if (record.flag_kind == 0) return;
    const size: Size = @enumFromInt(record.flag_size);
    switch (record.flag_kind) {
        @intFromEnum(block_jit.FlagKind.add) => x64_decoder.applyAdd(&self.guestContextField("regs").*.rflags, record.flag_a, record.flag_b, record.flag_r, size),
        @intFromEnum(block_jit.FlagKind.sub) => x64_decoder.applySub(&self.guestContextField("regs").*.rflags, record.flag_a, record.flag_b, record.flag_r, size),
        @intFromEnum(block_jit.FlagKind.logic) => x64_decoder.applyLogic(&self.guestContextField("regs").*.rflags, record.flag_r, size),
        else => {},
    }
    record.flag_kind = 0;
    if (self.currentBlockJit()) |jit| jit.flag_completions +|= 1;
}

/// Fast path for the four raw x87 transfers whose observable behavior is
/// stack bookkeeping plus byte-preserving movement. This deliberately avoids
/// converting the 80-bit payload through f64: Xenia's CRT also uses m80 as an
/// opaque ten-byte transport. Memory permissions, access faults, trace writes,
/// and the store-buffer boundary remain the same as the interpreter path.
fn blockJitX87RawTransfer(state_ptr: *anyopaque, block: *const block_jit.Block, index: u32) callconv(.c) u32 {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    const insn = block.insns[index];
    self.guestContextField("regs").*.rip = insn.rip;
    self.guestContextField("last_decoded_op").* = insn.decoded.op;
    self.guestContextField("last_decoded_len").* = insn.len;
    self.guestContextField("last_instruction_rip").* = insn.rip;
    if (self.currentBlockJit()) |jit| jit.x87_fast_helpers +|= 1;

    var d = insn.decoded;
    d.segment = insn.segment;
    if (d.op == .fld_mem80 or d.op == .fstp_mem80) {
        d.addr = x64_decoder.resolveMemoryAddress(&self.guestContextField("regs").*, .{
            .displacement = d.addr,
            .has_index = d.sib_has_index,
            .index_reg = d.sib_index_reg,
            .scale = d.sib_scale,
            .has_base = d.sib_has_base,
            .base_reg = d.sib_base_reg,
            .rip_relative = d.rip_relative,
            .segment = d.segment,
        }, self.guestContextField("regs").*.rip +% d.len, if (d.has_0x67) .bits32 else .bits64, .long64, true);
    }

    // Match the interpreter fallback boundary. A memory load must see stores
    // the translated stream retired before it; a memory store must be visible
    // before the translated stream resumes.
    tso_memory.flushActiveStoreBufferFor(.jit_helper);
    defer tso_memory.flushActiveStoreBufferFor(.jit_fallback);
    switch (d.op) {
        .fld_st => if (self.x87GetRaw(@truncate(d.imm))) |raw| {
            _ = self.x87PushRaw(raw);
        },
        .fstp_st => if (self.x87GetRaw(0)) |raw| {
            if (self.x87SetRaw(@truncate(d.imm), raw)) _ = self.x87PopRaw();
        },
        .fld_mem80 => {
            var raw: X87Raw = undefined;
            if (!self.copyFromGuest(&raw, d.addr)) {
                self.blockJitRequestAbort();
                return 1;
            }
            _ = self.x87PushRaw(raw);
        },
        .fstp_mem80 => {
            if (self.x87PopRaw()) |raw| {
                self.traceGuestWrite(d.addr, 10, std.mem.readInt(u64, raw[0..8], .little));
                if (!self.copyToGuest(d.addr, &raw)) {
                    self.blockJitRequestAbort();
                    return 1;
                }
            } else if (!self.fillGuestMemory(d.addr, 10, 0)) {
                self.blockJitRequestAbort();
                return 1;
            }
        },
        else => unreachable,
    }

    if (self.isTerminated() or self.guestContextField("guest_access_violation_pending").*) return 1;
    if (self.blockJitContinuationChanged()) {
        self.blockJitRequestAbort();
        return 1;
    }
    return 0;
}

/// x87 memory arithmetic still uses Rosette's shared x87 model, but it does
/// not need the general instruction dispatcher. This helper resolves the
/// guest effective address, drains prior translated stores before the load,
/// and leaves the existing fault/continuation checks intact.
fn blockJitX87Memory(state_ptr: *anyopaque, block: *const block_jit.Block, index: u32) callconv(.c) u32 {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    const insn = block.insns[index];
    self.guestContextField("regs").*.rip = insn.rip;
    self.guestContextField("last_decoded_op").* = insn.decoded.op;
    self.guestContextField("last_decoded_len").* = insn.len;
    self.guestContextField("last_instruction_rip").* = insn.rip;
    if (self.currentBlockJit()) |jit| jit.x87_memory_helpers +|= 1;

    var d = insn.decoded;
    d.segment = insn.segment;
    d.addr = x64_decoder.resolveMemoryAddress(&self.guestContextField("regs").*, .{
        .displacement = d.addr,
        .has_index = d.sib_has_index,
        .index_reg = d.sib_index_reg,
        .scale = d.sib_scale,
        .has_base = d.sib_has_base,
        .base_reg = d.sib_base_reg,
        .rip_relative = d.rip_relative,
        .segment = d.segment,
    }, insn.rip +% insn.len, if (d.has_0x67) .bits32 else .bits64, .long64, true);

    tso_memory.flushActiveStoreBufferFor(.jit_helper);
    defer tso_memory.flushActiveStoreBufferFor(.jit_fallback);
    self.x87Memory(d);

    if (self.isTerminated() or self.guestContextField("guest_access_violation_pending").*) return 1;
    if (self.blockJitContinuationChanged()) {
        self.blockJitRequestAbort();
        return 1;
    }
    return 0;
}

fn blockJitAtomicMemoryWidth(d: DecodedInsn) ?u8 {
    return switch (d.op) {
        .xchg_mem8_reg8, .cmpxchg_mem8_reg8, .xadd_mem8_reg8 => 1,
        .cmpxchg_mem16_reg16 => 2,
        .bt_mem_imm,
        .bts_mem_imm,
        .btr_mem_imm,
        .btc_mem_imm,
        .bt_mem_reg,
        .bts_mem_reg,
        .btr_mem_reg,
        .btc_mem_reg,
        => switch (d.size) {
            .bits16 => 2,
            .bits32 => 4,
            .bits64 => 8,
            else => null,
        },
        .xchg_mem32_reg32, .cmpxchg_mem32_reg32, .xadd_mem32_reg32, .xchg_mem64_reg64, .cmpxchg_mem64_reg64, .xadd_mem64_reg64 => switch (d.size) {
            .bits16 => 2,
            .bits32 => 4,
            .bits64 => 8,
            else => null,
        },
        else => null,
    };
}

fn blockJitAtomicAlwaysWrites(op: Op) bool {
    return switch (op) {
        .xchg_mem8_reg8, .xchg_mem32_reg32, .xchg_mem64_reg64, .xadd_mem8_reg8, .xadd_mem32_reg32, .xadd_mem64_reg64 => true,
        .bts_mem_imm, .btr_mem_imm, .btc_mem_imm, .bts_mem_reg, .btr_mem_reg, .btc_mem_reg => true,
        else => false,
    };
}

fn blockJitCompareExchangeWriteCommitted(op: Op, rflags: u64) bool {
    return switch (op) {
        .cmpxchg_mem8_reg8, .cmpxchg_mem16_reg16, .cmpxchg_mem32_reg32, .cmpxchg_mem64_reg64 => (rflags & RFL_ZF) != 0,
        else => false,
    };
}

fn blockJitRuntimeFallbackReason(insn: block_jit.Insn) block_jit.FallbackReason {
    // Native templates can deliberately escape to the interpreter for a
    // guarded boundary: a TLB miss, watched/protected memory, call tracing,
    // an import slot, or a transfer target that lacks executable proof.
    // Attribute those escapes separately so the ledger does not present
    // them as absent templates.
    if (!insn.force_fallback and block_jit.isNative(insn.decoded)) return .native_slow_path;
    return insn.fallback_reason;
}

fn blockJitInterpret(state_ptr: *anyopaque, block: *const block_jit.Block, index: u32) callconv(.c) u32 {
    const self: *ElfState = @ptrCast(@alignCast(state_ptr));
    const insn = block.insns[index];
    const atomic_width = blockJitAtomicMemoryWidth(insn.decoded);
    const resolved_atomic_base = if (atomic_width != null) x64_decoder.resolveMemoryAddress(&self.guestContextField("regs").*, .{
        .displacement = insn.decoded.addr,
        .has_index = insn.decoded.sib_has_index,
        .index_reg = insn.decoded.sib_index_reg,
        .scale = insn.decoded.sib_scale,
        .has_base = insn.decoded.sib_has_base,
        .base_reg = insn.decoded.sib_base_reg,
        .rip_relative = insn.decoded.rip_relative,
        .segment = insn.segment,
    }, insn.rip +% insn.len, if (insn.decoded.has_0x67) .bits32 else .bits64, .long64, true) else 0;
    const is_bit_test_memory = switch (insn.decoded.op) {
        .bt_mem_imm,
        .bts_mem_imm,
        .btr_mem_imm,
        .btc_mem_imm,
        .bt_mem_reg,
        .bts_mem_reg,
        .btr_mem_reg,
        .btc_mem_reg,
        => true,
        else => false,
    };
    const atomic_address = if (!is_bit_test_memory) resolved_atomic_base else blk: {
        const operand = if (insn.decoded.op == .bt_mem_imm or insn.decoded.op == .bts_mem_imm or
            insn.decoded.op == .btr_mem_imm or insn.decoded.op == .btc_mem_imm)
            x64_decoder.bitTestMemoryOperandImmediate(insn.decoded.size, resolved_atomic_base, insn.decoded.imm)
        else
            x64_decoder.bitTestMemoryOperand(insn.decoded.size, resolved_atomic_base, self.regVal(insn.decoded.src_reg, insn.decoded.size));
        break :blk if (operand) |resolved| resolved.address else 0;
    };
    const op_index: usize = @intFromEnum(insn.decoded.op);
    var sample_fallback_cost = false;
    if (self.currentBlockJit()) |jit| {
        jit.fallback_calls +|= 1;
        jit.fallback_ops[op_index] +|= 1;
        const fallback_reason = blockJitRuntimeFallbackReason(insn);
        jit.fallback_reason_counts[@intFromEnum(fallback_reason)] +|= 1;
        const op_calls = jit.fallback_ops[op_index];
        sample_fallback_cost = op_calls == 1 or op_calls % BLOCK_JIT_FALLBACK_COST_SAMPLE_PERIOD == 0;
    }
    const sample_started = if (sample_fallback_cost) monotonicNanoseconds() else 0;
    // The interpreter reads `rflags` directly, so a record the translated
    // code left pending has to be settled before it runs rather than on the
    // way out of the block.
    blockJitFlags(state_ptr);
    const slot_before = self.guestContextField("windows_active_guest_thread_slot").*;
    const imports_before = self.windowsImportCallCount();
    self.blockJitExecuteInsn(block, index);
    // The interpreter queued this instruction's stores in the executor's
    // buffer, and the translated code that resumes reads and writes guest
    // memory directly: it must see them, and its own later stores must not
    // be overwritten when they drain. On 2026-09-24 this drain was missing,
    // so every store an interpreted `movaps`, `fstp m80` or `call [mem]`
    // made inside a block was invisible to the rest of the block.
    tso_memory.flushActiveStoreBufferFor(.jit_fallback);
    // A native atomic instruction that misses its worker TLB takes the full
    // interpreter path above. Admit the page after a successful write so the
    // next execution reaches the inline acquire/release or LSE template
    // instead of repeating the same interpreter round-trip forever.
    if (atomic_width) |width| {
        if (!self.isTerminated() and !self.guestContextField("guest_access_violation_pending").*) {
            const wrote = blockJitAtomicAlwaysWrites(insn.decoded.op) or
                blockJitCompareExchangeWriteCommitted(insn.decoded.op, self.guestContextField("regs").*.rflags);
            if (wrote) self.blockJitTlbConsider(atomic_address, width, true);
        }
    }
    if (sample_fallback_cost and sample_started != 0) {
        const sample_finished = monotonicNanoseconds();
        if (sample_finished > sample_started) {
            if (self.currentBlockJit()) |jit| {
                jit.fallback_cost_sample_count[op_index] +|= 1;
                jit.fallback_cost_sampled_nanos[op_index] +|= sample_finished - sample_started;
            }
        }
    }
    switch (insn.decoded.op) {
        .call_rel32, .call_mem64, .call_reg64, .jmp_mem64, .jmp_reg64 => if (self.currentBlockJit()) |jit| {
            if (self.windowsImportCallCount() != imports_before) {
                jit.transfer_fallback_imports +|= 1;
            } else {
                const hooked = self.blockJitTargetHooked(self.guestContextField("regs").*.rip);
                if (hooked) jit.transfer_fallback_hooked +|= 1 else jit.transfer_fallback_plain +|= 1;
                jit.noteTransferTarget(self.guestContextField("regs").*.rip, @intFromEnum(insn.decoded.op), hooked);
            }
        },
        else => {},
    }
    // A shim reached from here is the only way the run can end, a thread can
    // switch or the scheduler can be asked for mid-block, and translated
    // code cannot see any of that - so stop the native chain on exactly the
    // conditions the glue's own loop stops on. This used to stop it
    // whenever the interpreter ran at all: on 2026-09-21 that was 658
    // million fallbacks, each ending a chain that had nothing to hand over,
    // and native chains averaged 4.6 blocks.
    // A shim can also park the running worker - the condition shim does,
    // from inside a translated jump - and a parked thread must not execute
    // one more instruction: re-entering the shim while blocked is refused,
    // and the refusal falls through into the image's own implementation.
    const parked = if (slot_before) |slot| self.windows_guest_threads[slot].status != .running else false;
    if (self.isTerminated() or self.guestContextField("guest_access_violation_pending").* or parked or
        self.guestContextField("windows_active_guest_thread_slot").* != slot_before or
        self.guestContextField("windows_guest_slice_yield_requested").* or
        self.guestContextField("windows_guest_handoff_requested").* or
        self.blockJitTargetHooked(self.guestContextField("regs").*.rip))
    {
        self.guestContextField("block_jit_scratch").*.chain_break = 1;
    }
    if (self.isTerminated() or self.guestContextField("guest_access_violation_pending").* or parked) return 1;
    if (self.guestContextField("regs").*.rip != insn.rip +% insn.len) return 1;
    if (self.guestContextField("windows_active_guest_thread_slot").* != slot_before) return 1;
    if (self.guestContextField("windows_guest_slice_yield_requested").* or
        self.guestContextField("windows_guest_handoff_requested").*) return 1;
    // A vector/string fallback can write executable bytes just as the native
    // scalar write helper can. Never execute the old decoded continuation.
    if (self.blockJitContinuationChanged()) {
        self.blockJitRequestAbort();
        return 1;
    }
    return 0;
}

const process_impl_lifecycle = @import("process/impl/lifecycle.zig");
const process_impl_windows_sync = @import("process/impl/windows_sync.zig");
const process_impl_windows_ui = @import("process/impl/windows_ui.zig");
const process_impl_guest_memory = @import("process/impl/guest_memory.zig");
const process_impl_guest_diagnostics = @import("process/impl/guest_diagnostics.zig");
const process_impl_kernel_services = @import("process/impl/kernel_services.zig");
const process_impl_guest_heap = @import("process/impl/guest_heap.zig");
const process_impl_instruction_decode = @import("process/impl/instruction_decode.zig");
const process_impl_block_jit = @import("process/impl/block_jit.zig");
const process_impl_run_reporting = @import("process/impl/run_reporting.zig");
const process_impl_windows_audio = @import("process/impl/windows_audio.zig");
const process_impl_execution = @import("process/impl/execution.zig");
const process_impl_syscalls = @import("process/impl/syscalls.zig");

/// Shared identity for the per-run guest milestone activity result.
const GuestMilestoneActivity = struct { hits: u64, last_step: u64, armed: bool };

/// Narrow bridge for the split process implementation modules.
pub const __ProcessInternals = struct {
    pub const _AUDIO_STAGE_COUNT = AUDIO_STAGE_COUNT;
    pub const _BLOCK_JIT_CHAIN_BLOCKS = BLOCK_JIT_CHAIN_BLOCKS;
    pub const _BLOCK_JIT_CHAIN_INSTRUCTIONS = BLOCK_JIT_CHAIN_INSTRUCTIONS;
    pub const _BLOCK_JIT_FALLBACK_COST_SAMPLE_PERIOD = BLOCK_JIT_FALLBACK_COST_SAMPLE_PERIOD;
    pub const _BLOCK_JIT_HOOK_FILTER_BYTES = BLOCK_JIT_HOOK_FILTER_BYTES;
    pub const _BLOCK_JIT_MAX_CONDITIONALS = BLOCK_JIT_MAX_CONDITIONALS;
    pub const _BLOCK_JIT_MAX_INSTRUCTIONS = BLOCK_JIT_MAX_INSTRUCTIONS;
    pub const _BLOCK_JIT_PARALLEL_CHAIN_BLOCKS = BLOCK_JIT_PARALLEL_CHAIN_BLOCKS;
    pub const _BLOCK_JIT_PARALLEL_CHAIN_INSTRUCTIONS = BLOCK_JIT_PARALLEL_CHAIN_INSTRUCTIONS;
    pub const _BLOCK_JIT_WAYS = BLOCK_JIT_WAYS;
    pub const _BLOCK_JIT_WORKER_CODE_BYTES = BLOCK_JIT_WORKER_CODE_BYTES;
    pub const _BLOCK_JIT_WORKER_MAX_TABLE_ENTRIES = BLOCK_JIT_WORKER_MAX_TABLE_ENTRIES;
    pub const _BLOCK_JIT_WORKER_TABLE_ENTRIES = BLOCK_JIT_WORKER_TABLE_ENTRIES;
    pub const _BitScanKind = BitScanKind;
    pub const _BlockHotness = BlockHotness;
    pub const _BlockJitCallRefusal = BlockJitCallRefusal;
    pub const _BlockJitState = BlockJitState;
    pub const _CODE_PAGE_GENERATION_BITS = CODE_PAGE_GENERATION_BITS;
    pub const _CODE_PAGE_GENERATION_SLOTS = CODE_PAGE_GENERATION_SLOTS;
    pub const _CODE_PAGE_SHIFT = CODE_PAGE_SHIFT;
    pub const _ChainStage = ChainStage;
    pub const _Cond = Cond;
    pub const _DecodeCacheCounters = DecodeCacheCounters;
    pub const _DecodeCacheEntry = DecodeCacheEntry;
    pub const _DecodeCacheMissCause = DecodeCacheMissCause;
    pub const _DecodeCacheMissSite = DecodeCacheMissSite;
    pub const _DecodeCacheShard = DecodeCacheShard;
    pub const _DecodedInsn = DecodedInsn;
    pub const _ElfRegs = ElfRegs;
    pub const _ElfTraceEntry = ElfTraceEntry;
    pub const _FIRST_FRAME_STAGE_COUNT = FIRST_FRAME_STAGE_COUNT;
    pub const _FrameHostSampleCategory = FrameHostSampleCategory;
    pub const _FrameHostSampleCounts = FrameHostSampleCounts;
    pub const _GPU_INDIRECT_BUFFER_CAPACITY = GPU_INDIRECT_BUFFER_CAPACITY;
    pub const _GPU_REGISTER_TRAFFIC_CAPACITY = GPU_REGISTER_TRAFFIC_CAPACITY;
    pub const _GPU_RING_WINDOW_ALIAS_CHECKS = GPU_RING_WINDOW_ALIAS_CHECKS;
    pub const _GPU_RING_WINDOW_CAPACITY = GPU_RING_WINDOW_CAPACITY;
    pub const _GPU_RING_WINDOW_DECODE_LIMIT = GPU_RING_WINDOW_DECODE_LIMIT;
    pub const _GPU_RING_WINDOW_FIRST_DWORDS = GPU_RING_WINDOW_FIRST_DWORDS;
    pub const _GPU_RING_WINDOW_INDIRECT_BUFFERS = GPU_RING_WINDOW_INDIRECT_BUFFERS;
    pub const _GPU_RING_WINDOW_OPCODES = GPU_RING_WINDOW_OPCODES;
    pub const _GUEST_FILE_REQUEST_PREVIEW_BYTES = GUEST_FILE_REQUEST_PREVIEW_BYTES;
    pub const _GUEST_MILESTONE_COUNT = GUEST_MILESTONE_COUNT;
    pub const _GUEST_MILESTONE_TRANSLATOR_SATURATION = GUEST_MILESTONE_TRANSLATOR_SATURATION;
    pub const _GUEST_MODULE_LOOKUP_CAPACITY = GUEST_MODULE_LOOKUP_CAPACITY;
    pub const _GUEST_MODULE_NAME_BYTES = GUEST_MODULE_NAME_BYTES;
    pub const _GUEST_OUTPUT_STAGE_COUNT = GUEST_OUTPUT_STAGE_COUNT;
    pub const _GUEST_VFS_PATH_BYTES = GUEST_VFS_PATH_BYTES;
    pub const _GUEST_VFS_RESOLVE_CAPACITY = GUEST_VFS_RESOLVE_CAPACITY;
    pub const _GpuDrawFailure = GpuDrawFailure;
    pub const _GpuDrawTuple = GpuDrawTuple;
    pub const _GpuRingWindow = GpuRingWindow;
    pub const _GuestAccessViolation = GuestAccessViolation;
    pub const _GuestAccessViolationSite = GuestAccessViolationSite;
    pub const _GuestContextRef = GuestContextRef;
    pub const _GuestExecutionGate = GuestExecutionGate;
    pub const _GuestFileNameShape = GuestFileNameShape;
    pub const _GuestFileRequest = GuestFileRequest;
    pub const _GuestFrameCost = GuestFrameCost;
    pub const _GuestFrontBuffer = GuestFrontBuffer;
    pub const _GuestMilestoneActivity = GuestMilestoneActivity;
    pub const _GuestReturnCapture = GuestReturnCapture;
    pub const _GuestReturnCaptureKind = GuestReturnCaptureKind;
    pub const _GuestSymbol = GuestSymbol;
    pub const _GuestSymbolResolver = GuestSymbolResolver;
    pub const _GuestVfsResolve = GuestVfsResolve;
    pub const _GuestVfsResolveSummary = GuestVfsResolveSummary;
    pub const _GuestXmaRegisterCensus = GuestXmaRegisterCensus;
    pub const _HookBox = HookBox;
    pub const _HookPoints = HookPoints;
    pub const _INITIAL_WINDOWS_HEAP_ALLOCATIONS = INITIAL_WINDOWS_HEAP_ALLOCATIONS;
    pub const _MAX_WINDOWS_GUEST_THREADS = MAX_WINDOWS_GUEST_THREADS;
    pub const _MAX_WINDOWS_INITTERM_ENTRIES = MAX_WINDOWS_INITTERM_ENTRIES;
    pub const _MAX_WINDOWS_QSORT_ELEMENTS = MAX_WINDOWS_QSORT_ELEMENTS;
    pub const _MAX_WINDOWS_QSORT_ELEMENT_BYTES = MAX_WINDOWS_QSORT_ELEMENT_BYTES;
    pub const _MAX_WINDOWS_BSEARCH_FRAMES = MAX_WINDOWS_BSEARCH_FRAMES;
    pub const _MAX_WINDOWS_BSEARCH_ELEMENTS = MAX_WINDOWS_BSEARCH_ELEMENTS;
    pub const _MEM_BASE = MEM_BASE;
    pub const _MEM_SIZE = MEM_SIZE;
    pub const _NativeConditionLock = NativeConditionLock;
    pub const _Op = Op;
    pub const _PARALLEL_WORKER_STEP_BATCH = PARALLEL_WORKER_STEP_BATCH;
    pub const _PE_DECODE_CACHE_ENTRIES = PE_DECODE_CACHE_ENTRIES;
    pub const _PE_DECODE_CACHE_LOCAL_ENTRIES = PE_DECODE_CACHE_LOCAL_ENTRIES;
    pub const _PE_DECODE_CACHE_SETS = PE_DECODE_CACHE_SETS;
    pub const _PE_DECODE_CACHE_VICTIM_ENTRIES = PE_DECODE_CACHE_VICTIM_ENTRIES;
    pub const _PE_DECODE_CACHE_VICTIM_SETS = PE_DECODE_CACHE_VICTIM_SETS;
    pub const _PE_DECODE_CACHE_VICTIM_WAYS = PE_DECODE_CACHE_VICTIM_WAYS;
    pub const _PE_DECODE_CACHE_WAYS = PE_DECODE_CACHE_WAYS;
    pub const _PE_MAX_INSTRUCTION_LENGTH = PE_MAX_INSTRUCTION_LENGTH;
    pub const _PPC_CONTEXT_LINK_REGISTER = PPC_CONTEXT_LINK_REGISTER;
    pub const _PPC_CONTEXT_VIRTUAL_MEMBASE = PPC_CONTEXT_VIRTUAL_MEMBASE;
    pub const _RFL_AF = RFL_AF;
    pub const _RFL_CF = RFL_CF;
    pub const _RFL_DF = RFL_DF;
    pub const _RFL_OF = RFL_OF;
    pub const _RFL_PF = RFL_PF;
    pub const _RFL_SF = RFL_SF;
    pub const _RFL_ZF = RFL_ZF;
    pub const _RegId = RegId;
    pub const _STACK_COLLAPSE_FLOOR = STACK_COLLAPSE_FLOOR;
    pub const _STACK_SIZE = STACK_SIZE;
    pub const _SYNTHETIC_INIT_RETURN = SYNTHETIC_INIT_RETURN;
    pub const _SYNTHETIC_MAIN_RETURN = SYNTHETIC_MAIN_RETURN;
    pub const _SYNTHETIC_RIP_FLOOR = SYNTHETIC_RIP_FLOOR;
    pub const _SYNTHETIC_WINDOWS_APC_RETURN = SYNTHETIC_WINDOWS_APC_RETURN;
    pub const _SYNTHETIC_WINDOWS_AUDIO_RETURN = SYNTHETIC_WINDOWS_AUDIO_RETURN;
    pub const _SYNTHETIC_WINDOWS_CRT_EXIT_RETURN = SYNTHETIC_WINDOWS_CRT_EXIT_RETURN;
    pub const _SYNTHETIC_WINDOWS_EXCEPTION_RETURN = SYNTHETIC_WINDOWS_EXCEPTION_RETURN;
    pub const _SYNTHETIC_WINDOWS_MESSAGE_RETURN = SYNTHETIC_WINDOWS_MESSAGE_RETURN;
    pub const _SYNTHETIC_WINDOWS_THREAD_RETURN = SYNTHETIC_WINDOWS_THREAD_RETURN;
    pub const _SYS_arch_prctl = SYS_arch_prctl;
    pub const _SYS_close = SYS_close;
    pub const _SYS_creat = SYS_creat;
    pub const _SYS_exit = SYS_exit;
    pub const _SYS_gettid = SYS_gettid;
    pub const _SYS_open = SYS_open;
    pub const _SYS_read = SYS_read;
    pub const _SYS_write = SYS_write;
    pub const _Size = Size;
    pub const _TRACE_BUFFER_LEN = TRACE_BUFFER_LEN;
    pub const _TimeAuditSample = TimeAuditSample;
    pub const _WINDOWS_CLOCK_POLL_YIELD_READS = WINDOWS_CLOCK_POLL_YIELD_READS;
    pub const _WINDOWS_CURRENT_THREAD_PSEUDO_HANDLE = WINDOWS_CURRENT_THREAD_PSEUDO_HANDLE;
    pub const _WINDOWS_FILETIME_UNIX_EPOCH = WINDOWS_FILETIME_UNIX_EPOCH;
    pub const _WINDOWS_FILE_READ_PROVENANCE_CAPACITY = WINDOWS_FILE_READ_PROVENANCE_CAPACITY;
    pub const _WINDOWS_GCLP_WNDPROC = WINDOWS_GCLP_WNDPROC;
    pub const _WINDOWS_GUEST_CLOCK_HZ = WINDOWS_GUEST_CLOCK_HZ;
    pub const _WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE = WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE;
    pub const _WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND = WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND;
    pub const _WINDOWS_GUEST_CLOCK_TRANSLATED_PER_STEP = WINDOWS_GUEST_CLOCK_TRANSLATED_PER_STEP;
    pub const _WINDOWS_GUEST_FILETIME_BASE = WINDOWS_GUEST_FILETIME_BASE;
    pub const _WINDOWS_GUEST_SPIN_MAX_BACKOFF = WINDOWS_GUEST_SPIN_MAX_BACKOFF;
    pub const _WINDOWS_GUEST_SPIN_PROBE_AT = WINDOWS_GUEST_SPIN_PROBE_AT;
    pub const _WINDOWS_GUEST_SPIN_PROBE_SPAN = WINDOWS_GUEST_SPIN_PROBE_SPAN;
    pub const _WINDOWS_GUEST_THREAD_ENTRY_RESERVE = WINDOWS_GUEST_THREAD_ENTRY_RESERVE;
    pub const _WINDOWS_GUEST_THREAD_MAX_STACK_SIZE = WINDOWS_GUEST_THREAD_MAX_STACK_SIZE;
    pub const _WINDOWS_GUEST_THREAD_NAME_BYTES = WINDOWS_GUEST_THREAD_NAME_BYTES;
    pub const _WINDOWS_GUEST_THREAD_SERVICE_OWNER_STRIDE = WINDOWS_GUEST_THREAD_SERVICE_OWNER_STRIDE;
    pub const _WINDOWS_GUEST_THREAD_SERVICE_SLICE = WINDOWS_GUEST_THREAD_SERVICE_SLICE;
    pub const _WINDOWS_GUEST_THREAD_STACK_GUARD = WINDOWS_GUEST_THREAD_STACK_GUARD;
    pub const _WINDOWS_GUEST_THREAD_STACK_SIZE = WINDOWS_GUEST_THREAD_STACK_SIZE;
    pub const _WINDOWS_GUEST_YIELD_MINIMUM_SLICE = WINDOWS_GUEST_YIELD_MINIMUM_SLICE;
    pub const _WINDOWS_GWLP_USERDATA = WINDOWS_GWLP_USERDATA;
    pub const _WINDOWS_GWL_EXSTYLE = WINDOWS_GWL_EXSTYLE;
    pub const _WINDOWS_GWL_STYLE = WINDOWS_GWL_STYLE;
    pub const _WINDOWS_HEAP_ANOMALY_LOG_LIMIT = WINDOWS_HEAP_ANOMALY_LOG_LIMIT;
    pub const _WINDOWS_HEAP_BIN_SCAN = WINDOWS_HEAP_BIN_SCAN;
    pub const _WINDOWS_MAXIMUM_SUSPEND_COUNT = WINDOWS_MAXIMUM_SUSPEND_COUNT;
    pub const _WINDOWS_NULL_PAGE_LIMIT = WINDOWS_NULL_PAGE_LIMIT;
    pub const _WINDOWS_PAGE_SIZE = WINDOWS_PAGE_SIZE;
    pub const _WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD = WINDOWS_PAINT_WITHOUT_PRESENT_THRESHOLD;
    pub const _WINDOWS_PTHREAD_ETIMEDOUT = WINDOWS_PTHREAD_ETIMEDOUT;
    pub const _WINDOWS_RUN_HEARTBEAT_INSTRUCTIONS = WINDOWS_RUN_HEARTBEAT_INSTRUCTIONS;
    pub const _WINDOWS_TEB_BYTES = WINDOWS_TEB_BYTES;
    pub const _WINDOWS_TEB_CLIENT_ID_PROCESS_OFFSET = WINDOWS_TEB_CLIENT_ID_PROCESS_OFFSET;
    pub const _WINDOWS_TEB_CLIENT_ID_THREAD_OFFSET = WINDOWS_TEB_CLIENT_ID_THREAD_OFFSET;
    pub const _WINDOWS_TEB_LAST_ERROR_OFFSET = WINDOWS_TEB_LAST_ERROR_OFFSET;
    pub const _WINDOWS_TEB_PEB_OFFSET = WINDOWS_TEB_PEB_OFFSET;
    pub const _WINDOWS_TEB_SELF_OFFSET = WINDOWS_TEB_SELF_OFFSET;
    pub const _WINDOWS_TEB_STACK_BASE_OFFSET = WINDOWS_TEB_STACK_BASE_OFFSET;
    pub const _WINDOWS_TEB_STACK_LIMIT_OFFSET = WINDOWS_TEB_STACK_LIMIT_OFFSET;
    pub const _WINDOWS_TEB_TLS_POINTER_OFFSET = WINDOWS_TEB_TLS_POINTER_OFFSET;
    pub const _WINDOWS_TIMED_CONDITION_TIMEOUT_SAMPLE_LIMIT = WINDOWS_TIMED_CONDITION_TIMEOUT_SAMPLE_LIMIT;
    pub const _WINDOWS_TIMED_WAIT_SITE_CAPACITY = WINDOWS_TIMED_WAIT_SITE_CAPACITY;
    pub const _WINDOWS_TLS_BLOCK_BYTES = WINDOWS_TLS_BLOCK_BYTES;
    pub const _WINDOWS_TLS_SLOT_COUNT = WINDOWS_TLS_SLOT_COUNT;
    pub const _WINDOWS_WAIT_ESCALATION_MIN_AGE_STEPS = WINDOWS_WAIT_ESCALATION_MIN_AGE_STEPS;
    pub const _WINDOWS_WAIT_ESCALATION_MIN_AGE_TICKS = WINDOWS_WAIT_ESCALATION_MIN_AGE_TICKS;
    pub const _WINDOWS_WAIT_IO_COMPLETION = WINDOWS_WAIT_IO_COMPLETION;
    pub const _WINDOWS_WAIT_MULTIPLE_CAPACITY = WINDOWS_WAIT_MULTIPLE_CAPACITY;
    pub const _WINDOWS_WAVE_OUT_PACING_LEAD_NS = WINDOWS_WAVE_OUT_PACING_LEAD_NS;
    pub const _WINDOWS_WM_PAINT = WINDOWS_WM_PAINT;
    pub const _WindowsAllocationDisposition = WindowsAllocationDisposition;
    pub const _WindowsAllocationRefusalReason = WindowsAllocationRefusalReason;
    pub const _WindowsApcQueue = WindowsApcQueue;
    pub const _WindowsDynamicRefusal = WindowsDynamicRefusal;
    pub const _WindowsExecutableRange = WindowsExecutableRange;
    pub const _WindowsFileReadProvenance = WindowsFileReadProvenance;
    pub const _WindowsGuestFailurePoint = WindowsGuestFailurePoint;
    pub const _WindowsGuestThread = WindowsGuestThread;
    pub const _WindowsGuestThreadContext = WindowsGuestThreadContext;
    pub const _WindowsGuestThreadEnvironment = WindowsGuestThreadEnvironment;
    pub const _WindowsGuestThreadStatus = WindowsGuestThreadStatus;
    pub const _WindowsHeapAllocation = WindowsHeapAllocation;
    pub const _WindowsHeapBin = WindowsHeapBin;
    pub const _WindowsHeapCallSite = WindowsHeapCallSite;
    pub const _WindowsHeapCodeSnapshot = WindowsHeapCodeSnapshot;
    pub const _WindowsHeapStackSnapshot = WindowsHeapStackSnapshot;
    pub const _WindowsImportCallsite = WindowsImportCallsite;
    pub const _WindowsImportStub = WindowsImportStub;
    pub const _WindowsImportStubInterior = WindowsImportStubInterior;
    pub const _WindowsInputState = WindowsInputState;
    pub const _WindowsMappedCodeSlice = WindowsMappedCodeSlice;
    pub const _WindowsMessage = WindowsMessage;
    pub const _WindowsMultiWaitResult = WindowsMultiWaitResult;
    pub const _WindowsProgressSample = WindowsProgressSample;
    pub const _WindowsRuntimeLockGuard = WindowsRuntimeLockGuard;
    pub const _WindowsSrwLock = WindowsSrwLock;
    pub const _WindowsWaitObject = WindowsWaitObject;
    pub const _WindowsWaveOutDevice = WindowsWaveOutDevice;
    pub const _WindowsWindow = WindowsWindow;
    pub const _WindowsWindowClass = WindowsWindowClass;
    pub const _WorkerLocalDecodeCache = WorkerLocalDecodeCache;
    pub const _X87Raw = X87Raw;
    pub const _XENIA_GLOBAL_MUTEX_OWNER_OFFSET = XENIA_GLOBAL_MUTEX_OWNER_OFFSET;
    pub const _XENIA_GLOBAL_MUTEX_RECURSION_OFFSET = XENIA_GLOBAL_MUTEX_RECURSION_OFFSET;
    pub const _XENIA_GLOBAL_MUTEX_SYMBOL = XENIA_GLOBAL_MUTEX_SYMBOL;
    pub const _XENIA_SHA1_FEED_MINIMUM = XENIA_SHA1_FEED_MINIMUM;
    pub const _XeniaGlobalLend = XeniaGlobalLend;
    pub const _blockJitFlags = blockJitFlags;
    pub const _blockJitHookedTransfer = blockJitHookedTransfer;
    pub const _blockJitImportTransfer = blockJitImportTransfer;
    pub const _blockJitInterpret = blockJitInterpret;
    pub const _blockJitMappedTransferAllowed = blockJitMappedTransferAllowed;
    pub const _blockJitRead = blockJitRead;
    pub const _blockJitRead128 = blockJitRead128;
    pub const _blockJitWrite = blockJitWrite;
    pub const _blockJitWrite128 = blockJitWrite128;
    pub const _blockJitWrite128NonTemporal = blockJitWrite128NonTemporal;
    pub const _blockJitX87Memory = blockJitX87Memory;
    pub const _blockJitX87RawTransfer = blockJitX87RawTransfer;
    pub const _block_jit = block_jit;
    pub const _block_jit_refusal_retry_base = block_jit_refusal_retry_base;
    pub const _block_jit_refusal_retry_limit = block_jit_refusal_retry_limit;
    pub const _block_verify = block_verify;
    pub const _call_probe = call_probe;
    pub const _classifyWindowsTimedWaitSite = classifyWindowsTimedWaitSite;
    pub const _cleoRouteFor = cleoRouteFor;
    pub const _cleo_routing = cleo_routing;
    pub const _concurrency = concurrency;
    pub const _context_integrity = context_integrity;
    pub fn _coordinated_decode_cache_mutex() *@TypeOf(coordinated_decode_cache_mutex) {
        return &coordinated_decode_cache_mutex;
    }
    pub const _copyBoundedName = copyBoundedName;
    pub const _decodeInsn = decodeInsn;
    pub fn _decode_cache_miss_mutex() *@TypeOf(decode_cache_miss_mutex) {
        return &decode_cache_miss_mutex;
    }
    pub const _decode_cache_set_lock_count = decode_cache_set_lock_count;
    pub fn _decode_cache_set_locks() *@TypeOf(decode_cache_set_locks) {
        return &decode_cache_set_locks;
    }
    pub const _elf_loader = elf_loader;
    pub const _enterRuntimeStoreScope = enterRuntimeStoreScope;
    pub const _envEquals = envEquals;
    pub const _envFlag = envFlag;
    pub const _envPresentAndFalse = envPresentAndFalse;
    pub const _envText = envText;
    pub const _envU64 = envU64;
    pub const _evex = evex;
    pub const _execution_history = execution_history;
    pub const _exit_context = exit_context;
    pub const _exit_diagnostics = exit_diagnostics;
    pub const _frame_attribution = frame_attribution;
    pub const _gpuPrimitiveFinding = gpuPrimitiveFinding;
    pub const _gpu_stall = gpu_stall;
    pub const _guestMilestoneFilterBit = guestMilestoneFilterBit;
    pub const _guestMilestoneSaturable = guestMilestoneSaturable;
    pub const _guest_address_space = guest_address_space;
    pub const _guest_backtrace = guest_backtrace;
    pub const _guest_clock = guest_clock;
    pub const _guest_output_governor = guest_output_governor;
    pub const _guest_page_protection = guest_page_protection;
    pub const _guest_spin = guest_spin;
    pub const _guest_symbol_text_bytes = guest_symbol_text_bytes;
    pub const _heap_address_cache = heap_address_cache;
    pub const _heap_guard = heap_guard;
    pub const _hostFdFromGuest = hostFdFromGuest;
    pub const _host_fp_control = host_fp_control;
    pub const _host_profile = host_profile;
    pub const _import_histogram = import_histogram;
    pub fn _import_lock_requested_ns() *@TypeOf(import_lock_requested_ns) {
        return &import_lock_requested_ns;
    }
    pub const _instructionRate = instructionRate;
    pub const _isHostMainThread = isHostMainThread;
    pub const _isLiveWindowsGuestThread = isLiveWindowsGuestThread;
    pub const _kernel_call_census = kernel_call_census;
    pub const _kuser_shared = kuser_shared;
    pub const _linuxOpenFlagsToHost = linuxOpenFlagsToHost;
    pub const _log = log;
    pub const _mapped_ranges = mapped_ranges;
    pub const _milestone_slot_collision = milestone_slot_collision;
    pub const _monotonicNanoseconds = monotonicNanoseconds;
    pub const _native_alias_address_base = native_alias_address_base;
    pub const _native_alias_address_limit = native_alias_address_limit;
    pub const _native_alias_alignment = native_alias_alignment;
    pub const _parallel_diagnostics = parallel_diagnostics;
    pub const _parallel_metrics = parallel_metrics;
    pub const _parallel_workers = parallel_workers;
    pub const _peDecodeCacheIndex = peDecodeCacheIndex;
    pub const _peDecodeCacheSetIndex = peDecodeCacheSetIndex;
    pub const _peDecodeCacheVictimIndex = peDecodeCacheVictimIndex;
    pub const _ppcContextGpr = ppcContextGpr;
    pub const _pthread_set_qos_class_self_np = pthread_set_qos_class_self_np;
    pub fn _runtime_lock_released_ns() *@TypeOf(runtime_lock_released_ns) {
        return &runtime_lock_released_ns;
    }
    pub const _screen_validity = screen_validity;
    pub const _shouldTraceRip = shouldTraceRip;
    pub const _shuffleBytes = shuffleBytes;
    pub const _shufflePackedDoublesLane = shufflePackedDoublesLane;
    pub const _shufflePackedSinglesLane = shufflePackedSinglesLane;
    pub const _signExtendImm8 = signExtendImm8;
    pub const _spin_anatomy = spin_anatomy;
    pub const _std = std;
    pub const _syscallResult = syscallResult;
    pub const _terminal_event = terminal_event;
    pub const _testImmForSize = testImmForSize;
    pub const _tlb_diagnostics = tlb_diagnostics;
    pub const _trimAddressOffset = trimAddressOffset;
    pub const _tso_memory = tso_memory;
    pub const _tso_memory_policy = tso_memory_policy;
    pub const _ui_draw_evidence = ui_draw_evidence;
    pub const _unmapped_reads = unmapped_reads;
    pub const _vector_helpers = vector_helpers;
    pub const _wait_cost = wait_cost;
    pub const _windowsFileErrorLabel = windowsFileErrorLabel;
    pub const _windowsTimedWaitPercent = windowsTimedWaitPercent;
    pub const _windows_guest_abi = windows_guest_abi;
    pub fn _windows_guest_execution_binding() *@TypeOf(windows_guest_execution_binding) {
        return &windows_guest_execution_binding;
    }
    pub const _windows_message_queue = windows_message_queue;
    pub const _windows_message_wait = windows_message_wait;
    pub const _windows_registry_model = windows_registry_model;
    pub fn _windows_runtime_locks() *@TypeOf(windows_runtime_locks) {
        return &windows_runtime_locks;
    }
    pub const _windows_srw_owner_stack_depth = windows_srw_owner_stack_depth;
    pub const _windows_ui_ledger = windows_ui_ledger;
    pub const _x64_decoder = x64_decoder;
    pub const _x64_guest_abi = x64_guest_abi;
    pub const _x64_interpreter = x64_interpreter;
    pub const _x64_linux_runtime = x64_linux_runtime;
    pub const _x64_syscalls = x64_syscalls;
    pub const _xbox_critical_section = xbox_critical_section;
    pub const _xenia_accelerator = xenia_accelerator;
    pub const _xenia_clock_probe = xenia_clock_probe;
    pub const _xenia_event_audit = xenia_event_audit;
    pub const _xenia_fatal_condition_map = xenia_fatal_condition_map;
    pub const _xenia_guest_address_map = xenia_guest_address_map;
    pub const _xenia_guest_frontier_map = xenia_guest_frontier_map;
    pub const _xenia_guest_milestone_map = xenia_guest_milestone_map;
    pub const _xenia_kernel_shim_map = xenia_kernel_shim_map;
    pub const _xenia_presenter_attach_milestones = xenia_presenter_attach_milestones;
    pub const _xenia_sha1_kernel_feed_body = xenia_sha1_kernel_feed_body;
    pub const _xenia_warning_severity_map = xenia_warning_severity_map;
    pub const _xmutant_release_compat = xmutant_release_compat;
    pub const _xmutant_teardown_compat = xmutant_teardown_compat;
    pub const _BLOCK_JIT_DEFAULT_HOT_THRESHOLD = BLOCK_JIT_DEFAULT_HOT_THRESHOLD;
    pub const _DECODE_CACHE_MISS_SITE_CAPACITY = DECODE_CACHE_MISS_SITE_CAPACITY;
    pub const _GPU_DRAW_FAILURE_CAPACITY = GPU_DRAW_FAILURE_CAPACITY;
    pub const _GUEST_ACCESS_VIOLATION_SITE_CAPACITY = GUEST_ACCESS_VIOLATION_SITE_CAPACITY;
    pub const _GUEST_MILESTONE_CALLER_SLOTS = GUEST_MILESTONE_CALLER_SLOTS;
    pub const _GUEST_MILESTONE_SLOTS = GUEST_MILESTONE_SLOTS;
    pub const _GpuRegisterTraffic = GpuRegisterTraffic;
    pub const _GuestModuleLookup = GuestModuleLookup;
    pub const _HostMutex = HostMutex;
    pub const _MAX_WINDOWS_AUDIO_CALLBACK_FRAMES = MAX_WINDOWS_AUDIO_CALLBACK_FRAMES;
    pub const _MAX_WINDOWS_CRITICAL_SECTIONS = MAX_WINDOWS_CRITICAL_SECTIONS;
    pub const _MAX_WINDOWS_EXECUTABLE_RANGES = MAX_WINDOWS_EXECUTABLE_RANGES;
    pub const _MAX_WINDOWS_FILE_HANDLES = MAX_WINDOWS_FILE_HANDLES;
    pub const _MAX_WINDOWS_FILE_MAPPINGS = MAX_WINDOWS_FILE_MAPPINGS;
    pub const _MAX_WINDOWS_FIND_HANDLES = MAX_WINDOWS_FIND_HANDLES;
    pub const _MAX_WINDOWS_IMPORT_STUBS = MAX_WINDOWS_IMPORT_STUBS;
    pub const _MAX_WINDOWS_INITTERM_FRAMES = MAX_WINDOWS_INITTERM_FRAMES;
    pub const _MAX_WINDOWS_MEMORY_VIEWS = MAX_WINDOWS_MEMORY_VIEWS;
    pub const _MAX_WINDOWS_MESSAGE_DISPATCH_FRAMES = MAX_WINDOWS_MESSAGE_DISPATCH_FRAMES;
    pub const _MAX_WINDOWS_QSORT_FRAMES = MAX_WINDOWS_QSORT_FRAMES;
    pub const _MAX_WINDOWS_SRW_LOCKS = MAX_WINDOWS_SRW_LOCKS;
    pub const _MAX_WINDOWS_VIRTUAL_ALLOCATIONS = MAX_WINDOWS_VIRTUAL_ALLOCATIONS;
    pub const _MAX_WINDOWS_VOLUME_HANDLES = MAX_WINDOWS_VOLUME_HANDLES;
    pub const _MAX_WINDOWS_WAIT_OBJECTS = MAX_WINDOWS_WAIT_OBJECTS;
    pub const _MAX_WINDOWS_WAVE_OUT_DEVICES = MAX_WINDOWS_WAVE_OUT_DEVICES;
    pub const _MAX_WINDOWS_WINDOWS = MAX_WINDOWS_WINDOWS;
    pub const _MAX_WINDOWS_WINDOW_CLASSES = MAX_WINDOWS_WINDOW_CLASSES;
    pub const _NativeMemoryAlias = NativeMemoryAlias;
    pub const _ParallelFaultSnapshot = ParallelFaultSnapshot;
    pub const _WINDOWS_ALLOCATION_DISPOSITION_COUNT = WINDOWS_ALLOCATION_DISPOSITION_COUNT;
    pub const _WINDOWS_EVENT_PUMP_STRIDE = WINDOWS_EVENT_PUMP_STRIDE;
    pub const _WINDOWS_FATAL_POINT_ALLOW_BYTES = WINDOWS_FATAL_POINT_ALLOW_BYTES;
    pub const _WINDOWS_GUEST_FAILURE_POINT_CAPACITY = WINDOWS_GUEST_FAILURE_POINT_CAPACITY;
    pub const _WINDOWS_GUEST_OUTPUT_LINE_CAPACITY = WINDOWS_GUEST_OUTPUT_LINE_CAPACITY;
    pub const _WINDOWS_GUEST_THREAD_SCHEDULER_QUANTUM = WINDOWS_GUEST_THREAD_SCHEDULER_QUANTUM;
    pub const _WINDOWS_GUEST_WARNING_POINT_CAPACITY = WINDOWS_GUEST_WARNING_POINT_CAPACITY;
    pub const _WINDOWS_HEAP_QUARANTINE_BLOCKS = WINDOWS_HEAP_QUARANTINE_BLOCKS;
    pub const _WINDOWS_HEAP_QUARANTINE_BYTES = WINDOWS_HEAP_QUARANTINE_BYTES;
    pub const _WORKLOAD_COUNT = WORKLOAD_COUNT;
    pub const _WindowsAudioCallbackFrame = WindowsAudioCallbackFrame;
    pub const _WindowsCrtProcessGlobals = WindowsCrtProcessGlobals;
    pub const _WindowsFileFailureClass = WindowsFileFailureClass;
    pub const _WindowsFileFailureLedger = WindowsFileFailureLedger;
    pub const _WindowsGuestSchedulerPolicy = WindowsGuestSchedulerPolicy;
    pub const _WindowsGuestWarningPoint = WindowsGuestWarningPoint;
    pub const _WindowsInitTermFrame = WindowsInitTermFrame;
    pub const _WindowsMessageDispatchFrame = WindowsMessageDispatchFrame;
    pub const _WindowsProgressWatchdog = WindowsProgressWatchdog;
    pub const _WindowsQsortFrame = WindowsQsortFrame;
    pub const _WindowsBsearchFrame = WindowsBsearchFrame;
    pub const _WindowsSrwLockIndex = WindowsSrwLockIndex;
    pub const _WindowsTimedWaitClassification = WindowsTimedWaitClassification;
    pub const _WindowsTimedWaitSite = WindowsTimedWaitSite;
    pub const _WindowsVolumeFindSlot = WindowsVolumeFindSlot;
    pub const _XeniaSetupTrace = XeniaSetupTrace;
    pub const _blockJitRuntimeFallbackReason = blockJitRuntimeFallbackReason;
    pub const _classifyWindowsFileFailure = classifyWindowsFileFailure;
    pub const _freeTranslatedBlock = freeTranslatedBlock;
    pub const _process_impl_block_jit = process_impl_block_jit;
    pub const _process_impl_execution = process_impl_execution;
    pub const _process_impl_guest_diagnostics = process_impl_guest_diagnostics;
    pub const _process_impl_guest_heap = process_impl_guest_heap;
    pub const _process_impl_guest_memory = process_impl_guest_memory;
    pub const _process_impl_instruction_decode = process_impl_instruction_decode;
    pub const _process_impl_kernel_services = process_impl_kernel_services;
    pub const _process_impl_lifecycle = process_impl_lifecycle;
    pub const _process_impl_run_reporting = process_impl_run_reporting;
    pub const _process_impl_syscalls = process_impl_syscalls;
    pub const _process_impl_windows_audio = process_impl_windows_audio;
    pub const _process_impl_windows_sync = process_impl_windows_sync;
    pub const _process_impl_windows_ui = process_impl_windows_ui;
};
// ─── ELF state ───

const process_state = @import("process/state.zig");
pub const ElfState = process_state.ElfState;

fn syscallResult(value: u64) i64 {
    return @bitCast(value);
}

fn hostFdFromGuest(fd: u64) ?std.c.fd_t {
    if (fd > std.math.maxInt(std.c.fd_t)) return null;
    return @intCast(fd);
}

fn linuxOpenFlagsToHost(flags_raw: u64) std.c.O {
    var flags: std.c.O = .{};
    flags.ACCMODE = switch (flags_raw & 0x3) {
        1 => .WRONLY,
        2 => .RDWR,
        else => .RDONLY,
    };
    flags.CREAT = (flags_raw & 0o100) != 0;
    flags.TRUNC = (flags_raw & 0o1000) != 0;
    flags.APPEND = (flags_raw & 0o2000) != 0;
    return flags;
}

/// Asked on every instruction and on every traced arm; the absent-window
/// answer is one load at the call site.
inline fn shouldTraceRip(self: *ElfState, rip: u64) bool {
    if (self.trace_rip_start == null) return false;
    return shouldTraceRipInWindow(self, rip);
}

fn shouldTraceRipInWindow(self: *ElfState, rip: u64) bool {
    const start = self.trace_rip_start orelse return false;
    const end = self.trace_rip_end orelse start;
    if (rip < start or rip > end) return false;
    if (self.trace_rip_limit) |limit| {
        if (self.trace_rip_events >= limit) return false;
        self.trace_rip_events += 1;
    }
    return true;
}

fn parseEnvU64(text: []const u8) ?u64 {
    if (text.len >= 2 and text[0] == '0' and (text[1] == 'x' or text[1] == 'X')) {
        return std.fmt.parseUnsigned(u64, text[2..], 16) catch null;
    }
    return std.fmt.parseUnsigned(u64, text, 10) catch null;
}

// ─── Decoder ───

fn signExtendImm8(imm: u64) u64 {
    const signed: i8 = @bitCast(@as(u8, @truncate(imm)));
    return @as(u64, @bitCast(@as(i64, signed)));
}

fn shuffleBytes(source: [16]u8, mask: [16]u8) [16]u8 {
    var result = [_]u8{0} ** 16;
    for (mask, 0..) |selector, index| {
        if (selector & 0x80 == 0) result[index] = source[selector & 0x0F];
    }
    return result;
}

fn testImmForSize(imm: u64, size: Size) u64 {
    return switch (size) {
        .bits8 => imm & 0xFF,
        .bits16 => imm & 0xFFFF,
        .bits32 => imm & 0xFFFF_FFFF,
        .bits64 => @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(imm))))))),
    };
}

/// One 128-bit lane of (V)SHUFPD: element 0 from SRC1, element 1 from SRC2,
/// each picked by one control bit.
fn shufflePackedDoublesLane(source1: [16]u8, source2: [16]u8, control: u8) [16]u8 {
    var result: [16]u8 = undefined;
    const first: usize = if ((control & 0x01) != 0) 8 else 0;
    const second: usize = if ((control & 0x02) != 0) 8 else 0;
    @memcpy(result[0..8], source1[first..][0..8]);
    @memcpy(result[8..16], source2[second..][0..8]);
    return result;
}

/// One 128-bit lane of (V)SHUFPS: two elements from SRC1, two from SRC2,
/// each picked by two control bits.
fn shufflePackedSinglesLane(source1: [16]u8, source2: [16]u8, control: u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |destination| {
        const shift: u3 = @intCast(destination * 2);
        const element: usize = (control >> shift) & 0x03;
        const source = if (destination < 2) source1 else source2;
        @memcpy(result[destination * 4 ..][0..4], source[element * 4 ..][0..4]);
    }
    return result;
}

fn decodeInsn(bytes: []const u8) DecodedInsn {
    return x64_decoder.decodeLegacyInstruction(bytes, .long64);
}

// ─── High-level API ───

pub fn loadAndRunElf(allocator: std.mem.Allocator, elf_bytes: []const u8) !u64 {
    return loadRunElf(allocator, elf_bytes, .{});
}

pub const ElfRunOptions = struct {
    dump_results: bool = false,
    dump_all_results: bool = false,
    source_text: ?[]const u8 = null,
    argv: []const []const u8 = &.{},
};

fn loadRunElf(allocator: std.mem.Allocator, elf_bytes: []const u8, options: ElfRunOptions) !u64 {
    var state = ElfState.init(allocator);
    defer state.deinit();

    try state.loadElf(elf_bytes);

    var local_symbols = elf_loader.collectSymbols(allocator, elf_bytes) catch |err| blk: {
        log.warn("local symbols unavailable: {s}", .{@errorName(err)});
        const empty_symbols: std.ArrayList(elf_loader.Symbol) = .empty;
        break :blk empty_symbols;
    };
    defer local_symbols.deinit(allocator);
    state.local_symbols = local_symbols.items;

    var dynamic_relocations = elf_loader.collectDynamicRelocations(allocator, elf_bytes) catch |err| blk: {
        log.warn("dynamic relocations unavailable: {s}", .{@errorName(err)});
        const empty_relocations: std.ArrayList(elf_loader.DynamicRelocation) = .empty;
        break :blk empty_relocations;
    };
    defer dynamic_relocations.deinit(allocator);
    state.dynamic_relocations = dynamic_relocations.items;
    state.dynamic_relocation_lookup.clear();

    var init_functions = elf_loader.collectInitArray(allocator, elf_bytes) catch |err| blk: {
        log.warn("ELF init array unavailable: {s}", .{@errorName(err)});
        const empty_init: std.ArrayList(u64) = .empty;
        break :blk empty_init;
    };
    defer init_functions.deinit(allocator);
    state.init_functions = init_functions.items;

    var result_symbols: std.ArrayList(result_dump.DumpSymbol) = .empty;
    defer result_dump.deinitSymbols(allocator, &result_symbols);
    if (options.dump_results) {
        result_symbols = result_dump.collect(allocator, &state, elf_bytes, options.source_text) catch |err| blk: {
            log.warn("result symbols unavailable: {s}", .{@errorName(err)});
            break :blk .empty;
        };
    }

    try x64_linux_runtime.setupInitialStack(&state, options.argv);

    state.run();

    if (options.dump_results) {
        result_dump.dump(allocator, &state, result_symbols.items, .{
            .dump_all_results = options.dump_all_results,
            .source_text = options.source_text,
        }) catch |err| {
            log.warn("result dump skipped: {s}", .{@errorName(err)});
        };
    }

    return state.exit_code;
}

/// CLI entry point: `elf_processor <path-to-elf>`
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) {
        log.err("usage: elf_processor [--dump-results] [--dump-all-results] <elf-path>", .{});
        return;
    }

    var arg_index: usize = 1;
    var dump_results = envFlag("ROSETTE_ELF_DUMP_RESULTS");
    var dump_all_results = envFlag("ROSETTE_ELF_DUMP_ALL") or envFlag("ROSETTE_ELF_DUMP_ALL_RESULTS");
    while (arg_index < args.len and std.mem.startsWith(u8, args[arg_index], "--")) : (arg_index += 1) {
        if (std.mem.eql(u8, args[arg_index], "--dump-results")) {
            dump_results = true;
        } else if (std.mem.eql(u8, args[arg_index], "--dump-all-results")) {
            dump_results = true;
            dump_all_results = true;
        } else {
            log.err("unknown option: {s}", .{args[arg_index]});
            std.process.exit(126);
        }
    }
    if (arg_index >= args.len) {
        log.err("usage: elf_processor [--dump-results] [--dump-all-results] <elf-path>", .{});
        std.process.exit(126);
    }
    const elf_path = args[arg_index];

    const elf_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, elf_path, init.arena.allocator(), .unlimited);
    const source_text = if (dump_results)
        try readSiblingAsmSource(init.io, init.arena.allocator(), elf_path)
    else
        null;

    const exit_code = loadRunElf(init.arena.allocator(), elf_bytes, .{
        .dump_results = dump_results,
        .dump_all_results = dump_all_results,
        .source_text = source_text,
        .argv = args[arg_index..],
    }) catch |err| {
        log.err("failed to run ELF: {s}", .{@errorName(err)});
        std.process.exit(126);
    };

    if (envFlag("ROSETTE_ELF_VERBOSE")) {
        log.info("exit_code={d}", .{exit_code});
    }
    std.process.exit(@as(u8, @truncate(exit_code)));
}

fn envFlag(name: [:0]const u8) bool {
    const raw = std.c.getenv(name) orelse return false;
    const value = std.mem.sliceTo(raw, 0);
    if (value.len == 0) return false;
    if (std.mem.eql(u8, value, "0")) return false;
    if (std.ascii.eqlIgnoreCase(value, "false")) return false;
    if (std.ascii.eqlIgnoreCase(value, "no")) return false;
    return true;
}

/// True only when the variable is set *and* set to a false value.  A default
/// -on diagnostic uses this so an unset variable keeps the default rather
/// than reading as "off".
fn envPresentAndTrue(name: [:0]const u8) bool {
    const raw = std.c.getenv(name) orelse return false;
    const value = std.mem.sliceTo(raw, 0);
    if (value.len == 0) return false;
    return std.mem.eql(u8, value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.ascii.eqlIgnoreCase(value, "on");
}

fn envPresentAndFalse(name: [:0]const u8) bool {
    const raw = std.c.getenv(name) orelse return false;
    const value = std.mem.sliceTo(raw, 0);
    if (value.len == 0) return false;
    return std.mem.eql(u8, value, "0") or
        std.ascii.eqlIgnoreCase(value, "false") or
        std.ascii.eqlIgnoreCase(value, "no") or
        std.ascii.eqlIgnoreCase(value, "off");
}

/// The variable's text, or null when it is unset.
fn envText(name: [:0]const u8) ?[]const u8 {
    const raw = std.c.getenv(name) orelse return null;
    return std.mem.sliceTo(raw, 0);
}

/// True when the variable is set to exactly this value, case-insensitively.
/// Used where a setting is a choice between named modes rather than a switch.
fn envEquals(name: [:0]const u8, expected: []const u8) bool {
    const raw = std.c.getenv(name) orelse return false;
    return std.ascii.eqlIgnoreCase(std.mem.sliceTo(raw, 0), expected);
}

fn envU64(name: [:0]const u8) ?u64 {
    const raw = std.c.getenv(name) orelse return null;
    return parseEnvU64(std.mem.sliceTo(raw, 0));
}

fn readSiblingAsmSource(io: std.Io, allocator: std.mem.Allocator, elf_path: []const u8) !?[]const u8 {
    const direct = try std.mem.concat(allocator, u8, &.{ elf_path, ".asm" });
    if (std.Io.Dir.cwd().readFileAlloc(io, direct, allocator, .limited(512 * 1024))) |source| return source else |_| {}

    const dir = std.fs.path.dirname(elf_path) orelse ".";
    const base = std.fs.path.basename(elf_path);
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| {
        const stem_path = try std.fs.path.join(allocator, &.{ dir, base[0..dot] });
        const candidate = try std.mem.concat(allocator, u8, &.{ stem_path, ".asm" });
        if (std.Io.Dir.cwd().readFileAlloc(io, candidate, allocator, .limited(512 * 1024))) |source| return source else |_| {}
    }

    return null;
}

// ─── Tests ───

test {
    _ = @import("process/tests/decode.zig");
    _ = @import("process/tests/guest_observation.zig");
    _ = @import("process/tests/native_graphics.zig");
    _ = @import("process/tests/windows_runtime.zig");
    _ = @import("process/tests/cpu_oracles.zig");
    _ = @import("process/tests/parallel_runtime.zig");
    _ = @import("process/tests/stall_watch.zig");
    _ = @import("process/tests/windows_mutex.zig");
    _ = @import("process/tests/windows_mutex_contract.zig");
    _ = @import("block_jit/tests.zig");
}
