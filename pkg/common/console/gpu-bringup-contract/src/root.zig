//! Every code boundary a title must cross between asking the kernel for a
//! display and a frame reaching the host surface, named once, in order, with
//! the owner who is supposed to cross it.
//!
//! ## Why this package exists
//!
//! The graphics investigation has been reading zeroes for three weeks, and the
//! zeroes were never the problem. The problem is that a zero has four causes
//! and the reports could not tell them apart:
//!
//! 1. the title never made the call,
//! 2. the title made the call and nothing was watching the address,
//! 3. the call happened before the observer was armed,
//! 4. an upstream boundary never ran, so this one was never eligible.
//!
//! Only (1) is information about the title. (2) and (3) are defects in the
//! observer that *masquerade* as information about the title, and (4) is noise
//! that makes twenty rows look like twenty findings.
//!
//! A run on 2026-08-30 spent its whole length reporting `VdInitializeEngines`
//! ABSENT and `bootstrap failed: ring init handshake never completed`, while
//! an instruction-pointer tracepoint recorded `VdInitializeRingBuffer_entry`
//! entered at step 3_035_380_401. Both statements were emitted by the same
//! run. The ring really was initialised; the report that said otherwise was
//! reading a snapshot taken before the title got there, and no rung in any
//! ladder could contradict it because no rung knew what "watched" meant.
//!
//! So the surface is declared here as data, and every boundary carries the
//! three things that make its zero readable: who owns it, what must precede
//! it, and what its absence licenses a reader to conclude.
//!
//! ## What a boundary is
//!
//! A boundary is a **function entry**, not a log line and not a counter. The
//! distinction is the whole point: a counter can be incremented by a harness,
//! a log line can be filtered or printed by a code path that did no work, and
//! a memory scan can find a pattern that resembles the fact it is looking for.
//! An instruction pointer arriving at a resolved symbol cannot be any of those
//! things.
//!
//! `fragment` is the symbol substring to resolve against the emulator's own
//! symbol table. It is deliberately not an address: addresses change with
//! every emulator build, and a contract pinned to one is a contract that
//! silently stops observing.
//!
//! ## What this package must never become
//!
//! It holds no state, performs no I/O, and never decides that a boundary was
//! crossed. It is the vocabulary and the ordering; the live ledger that
//! records crossings lives in lib and is the only thing allowed to say YES.

const std = @import("std");

/// Who is supposed to cross a boundary. This is the single most useful field
/// in the table, because it decides whether an absence is work for the harness
/// or information about the title, and those call for opposite responses.
pub const Owner = enum(u8) {
    /// The title's own decision. An absence here is a fact about the title and
    /// nothing the harness supplies will move it. Supplying it anyway is how a
    /// run reports progress that never happened.
    guest_title,
    /// The emulator's kernel shim layer — the `_entry` function that the guest
    /// export dispatch lands in. Distinct from `guest_title` because the title
    /// reaching the thunk and the shim body running are different facts when a
    /// binding is wrong.
    emulator_kernel,
    /// The emulator's command processor. Consumes what the title publishes.
    emulator_command_processor,
    /// The emulator's graphics system: vblank, interrupt dispatch, the pump
    /// that tells the title its frame is done.
    emulator_graphics_system,
    /// The emulator's presenter and the host surface behind it.
    emulator_presenter,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .guest_title => "guest:title",
            .emulator_kernel => "emulator:kernel-shim",
            .emulator_command_processor => "emulator:command-processor",
            .emulator_graphics_system => "emulator:graphics-system",
            .emulator_presenter => "emulator:presenter",
        };
    }

    /// Whether an absence at this boundary is something a harness could ever
    /// legitimately act on. Only the emulator's own layers qualify, and even
    /// then only by observation — the answer here gates advice, never writes.
    pub fn absenceIsHarnessActionable(self: Owner) bool {
        return self != .guest_title;
    }
};

/// The stage of the pipeline a boundary belongs to. Progress is reported per
/// phase because a run that has crossed every bring-up boundary and no
/// submission boundary is in a completely different situation from one that
/// has crossed none, and a single percentage hides that.
pub const Phase = enum(u8) {
    /// The title negotiating a display and turning the GPU on.
    bringup,
    /// The title placing work in the ring and telling the GPU about it.
    submission,
    /// The command processor draining the ring and decoding what is in it.
    consumption,
    /// The GPU telling the title its work finished. Without this the title
    /// submits once and waits forever, which looks exactly like a GPU stall
    /// and is not one.
    completion,
    /// A finished frame reaching a host surface.
    presentation,

    pub fn label(self: Phase) []const u8 {
        return switch (self) {
            .bringup => "bringup",
            .submission => "submission",
            .consumption => "consumption",
            .completion => "completion",
            .presentation => "presentation",
        };
    }
};

/// How much a missing boundary means. A title is allowed to skip parts of the
/// video surface; treating every unentered export as a finding is how a report
/// grows twenty rows that name nothing.
pub const Requirement = enum(u8) {
    /// No frame can exist without this. Its absence is always the finding.
    required,
    /// Titles that render normally cross this. Absence is a strong signal but
    /// not proof on its own.
    expected,
    /// Legitimately optional. Recorded for the timeline, never a finding.
    optional,

    pub fn label(self: Requirement) []const u8 {
        return switch (self) {
            .required => "required",
            .expected => "expected",
            .optional => "optional",
        };
    }
};

/// How often a boundary is expected to be crossed once the run is healthy.
///
/// This is the field that separates "never started" from "started and died",
/// and nothing in the previous reports could tell them apart. A vblank pump
/// that fired four times in a seventeen-minute run reads as `crossed=YES` on
/// any once-only ledger, and `crossed=YES` is exactly what sends the next hour
/// downstream of a pump that stopped.
pub const Cadence = enum(u8) {
    /// Crossed once during bring-up and never again. A second crossing is
    /// unusual but not wrong.
    once,
    /// Crossed only when upstream work arrives. Silence after the work has
    /// drained is normal and is not a pump failure. A publication, packet,
    /// register write, draw, swap, refresh, notification routine or Cocoa
    /// paint belongs here; none owns an autonomous clock.
    event_driven,
    /// Crossed for every frame, or faster. Silence after a first crossing is a
    /// finding in its own right, and a stronger one than never having started.
    repeating,

    pub fn label(self: Cadence) []const u8 {
        return switch (self) {
            .once => "once",
            .event_driven => "event-driven",
            .repeating => "repeating",
        };
    }
};

/// Every boundary on the path from "title asks for a display" to "pixels".
///
/// The order of this enum is the order the console crosses them, and
/// `prerequisite` records the causal edge. Both are needed: the total order
/// makes "first not reached" cheap to compute, and the sparse prerequisite
/// edges are what stop a downstream zero from being reported as a finding.
pub const Boundary = enum(u8) {
    // ---- bringup -----------------------------------------------------------
    query_video_mode,
    query_display_information,
    initialize_engines,
    graphics_asic_id,
    hsio_training_query,
    retrain_edram,
    set_interrupt_callback,
    initialize_ring_buffer,
    enable_rptr_write_back,
    system_command_buffer_query,
    system_command_buffer_identifier,
    scaler_command_buffer,
    persist_display,

    // ---- submission --------------------------------------------------------
    write_pointer_updated,
    command_processor_worker_running,
    execute_primary_buffer,

    // ---- consumption -------------------------------------------------------
    execute_packet_type3,
    write_register,
    register_range_from_ring,
    make_coherent,
    issue_draw,
    render_target_update,
    xe_swap_decoded,

    // ---- completion --------------------------------------------------------
    mark_vblank,
    dispatch_interrupt_callback,
    emulate_cp_interrupt_dpc,
    graphics_notification_routines,
    read_pointer_write_back_store,

    // ---- presentation ------------------------------------------------------
    guest_swap_requested,
    swap_notified_to_graphics_system,
    issue_swap,
    refresh_guest_output,
    refresh_guest_output_impl,
    host_paint,

    pub fn label(self: Boundary) []const u8 {
        return switch (self) {
            .query_video_mode => "VdQueryVideoMode",
            .query_display_information => "VdGetCurrentDisplayInformation",
            .initialize_engines => "VdInitializeEngines",
            .graphics_asic_id => "VdGetGraphicsAsicID",
            .hsio_training_query => "VdIsHSIOTrainingSucceeded",
            .retrain_edram => "VdRetrainEDRAM",
            .set_interrupt_callback => "VdSetGraphicsInterruptCallback",
            .initialize_ring_buffer => "VdInitializeRingBuffer",
            .enable_rptr_write_back => "VdEnableRingBufferRPtrWriteBack",
            .system_command_buffer_query => "VdGetSystemCommandBuffer",
            .system_command_buffer_identifier => "VdSetSystemCommandBufferGpuIdentifierAddress",
            .scaler_command_buffer => "VdInitializeScalerCommandBuffer",
            .persist_display => "VdPersistDisplay",
            .write_pointer_updated => "CommandProcessor::UpdateWritePointer",
            .command_processor_worker_running => "CommandProcessor::WorkerThreadMain",
            .execute_primary_buffer => "CommandProcessor::ExecutePrimaryBuffer",
            .execute_packet_type3 => "CommandProcessor::ExecutePacketType3",
            .write_register => "CommandProcessor::WriteRegister",
            .register_range_from_ring => "CommandProcessor::WriteRegisterRangeFromRing",
            .make_coherent => "CommandProcessor::MakeCoherent",
            .issue_draw => "CommandProcessor::IssueDraw",
            .render_target_update => "RenderTargetCache::Update",
            .xe_swap_decoded => "CommandProcessor::ExecutePacketType3_XE_SWAP",
            .mark_vblank => "GraphicsSystem::MarkVblank",
            .dispatch_interrupt_callback => "GraphicsSystem::DispatchInterruptCallback",
            .emulate_cp_interrupt_dpc => "KernelState::EmulateCPInterruptDPC",
            .graphics_notification_routines => "VdCallGraphicsNotificationRoutines",
            .read_pointer_write_back_store => "CommandProcessor::EnableReadPointerWriteBack",
            .guest_swap_requested => "VdSwap",
            .swap_notified_to_graphics_system => "GraphicsSystem::NotifyVdSwapCall",
            .issue_swap => "CommandProcessor::IssueSwap",
            .refresh_guest_output => "Presenter::RefreshGuestOutput",
            .refresh_guest_output_impl => "Presenter::RefreshGuestOutputImpl",
            .host_paint => "Presenter::PaintFromUIThread",
        };
    }

    /// The symbol substring the observer resolves against the emulator's
    /// symbol table. `_entry` suffixes are used wherever the export shim
    /// defines one: that is the function the guest export dispatch calls, so
    /// arming it proves the guest arrived rather than proving a registration
    /// helper was linked.
    pub fn fragment(self: Boundary) []const u8 {
        return switch (self) {
            .query_video_mode => "VdQueryVideoMode_entry",
            .query_display_information => "VdGetCurrentDisplayInformation_entry",
            .initialize_engines => "VdInitializeEngines_entry",
            .graphics_asic_id => "VdGetGraphicsAsicID_entry",
            .hsio_training_query => "VdIsHSIOTrainingSucceeded_entry",
            .retrain_edram => "VdRetrainEDRAM_entry",
            .set_interrupt_callback => "VdSetGraphicsInterruptCallback_entry",
            .initialize_ring_buffer => "VdInitializeRingBuffer_entry",
            .enable_rptr_write_back => "VdEnableRingBufferRPtrWriteBack_entry",
            .system_command_buffer_query => "VdGetSystemCommandBuffer_entry",
            .system_command_buffer_identifier => "VdSetSystemCommandBufferGpuIdentifierAddress_entry",
            .scaler_command_buffer => "VdInitializeScalerCommandBuffer_entry",
            .persist_display => "VdPersistDisplay_entry",
            .write_pointer_updated => "UpdateWritePointer",
            .command_processor_worker_running => "WorkerThreadMain",
            .execute_primary_buffer => "ExecutePrimaryBuffer",
            .execute_packet_type3 => "ExecutePacketType3",
            .write_register => "WriteRegister",
            .register_range_from_ring => "WriteRegisterRangeFromRing",
            .make_coherent => "MakeCoherent",
            .issue_draw => "IssueDraw",
            .render_target_update => "RenderTargetCache",
            .xe_swap_decoded => "ExecutePacketType3_XE_SWAP",
            .mark_vblank => "MarkVblank",
            .dispatch_interrupt_callback => "DispatchInterruptCallback",
            .emulate_cp_interrupt_dpc => "EmulateCPInterruptDPC",
            .graphics_notification_routines => "VdCallGraphicsNotificationRoutines_entry",
            .read_pointer_write_back_store => "EnableReadPointerWriteBack",
            .guest_swap_requested => "VdSwap_entry",
            .swap_notified_to_graphics_system => "NotifyVdSwapCall",
            .issue_swap => "IssueSwap",
            .refresh_guest_output => "RefreshGuestOutput",
            .refresh_guest_output_impl => "RefreshGuestOutputImpl",
            .host_paint => "PaintFromUIThread",
        };
    }

    /// Additional substrings a candidate symbol must also contain.
    ///
    /// `fragment` alone is enough for the export shims, whose names are
    /// unique. It is not enough for a method on a class that has many: the
    /// mangled name of every member of `RenderTargetCache` contains
    /// `RenderTargetCache`, and ranking by name length would arm a destructor.
    /// Requiring a second substring is mangling-agnostic in a way that
    /// splicing the Itanium length prefix into the fragment is not.
    pub fn alsoRequires(self: Boundary) []const []const u8 {
        return switch (self) {
            .render_target_update => &.{"Update"},
            .write_pointer_updated => &.{"CommandProcessor"},
            .command_processor_worker_running => &.{"CommandProcessor"},
            .write_register => &.{"CommandProcessor"},
            .make_coherent => &.{"CommandProcessor"},
            else => &.{},
        };
    }

    /// Symbol fragments that contain this boundary's fragment but are a
    /// different provenance boundary, and must not be armed for it.
    ///
    /// `IssueSwap` is a substring of `DebugIssueSwapFromHost`, and arming the
    /// host diagnostic probe for the authentic role is how a forced host swap
    /// gets reported as the title presenting a frame. `ExecutePacketType3` is
    /// a substring of every `ExecutePacketType3_*` handler, and the generic
    /// dispatcher entering is a different fact from any one handler running.
    pub fn exclusions(self: Boundary) []const []const u8 {
        return switch (self) {
            .issue_swap => &.{ "DebugIssueSwapFromHost", "NotifyVdSwapCall" },
            .execute_packet_type3 => &.{"ExecutePacketType3_"},
            .write_register => &.{ "WriteRegisterRange", "WriteRegistersFrom", "WriteRegisterSet" },
            .refresh_guest_output => &.{"RefreshGuestOutputImpl"},
            else => &.{},
        };
    }

    pub fn cadence(self: Boundary) Cadence {
        return switch (self) {
            .write_pointer_updated,
            .command_processor_worker_running,
            .execute_primary_buffer,
            .execute_packet_type3,
            .write_register,
            .register_range_from_ring,
            .make_coherent,
            .issue_draw,
            .render_target_update,
            .xe_swap_decoded,
            .graphics_notification_routines,
            .read_pointer_write_back_store,
            .guest_swap_requested,
            .swap_notified_to_graphics_system,
            .issue_swap,
            .refresh_guest_output,
            .refresh_guest_output_impl,
            .host_paint,
            => .event_driven,
            .mark_vblank,
            .dispatch_interrupt_callback,
            .emulate_cp_interrupt_dpc,
            => .repeating,
            else => .once,
        };
    }

    /// What this boundary having been crossed and then gone quiet tells a
    /// reader. Only autonomous `repeating` boundaries turn silence into a
    /// finding. Event-driven descriptions remain available as context but are
    /// never promoted without a separately proven outstanding demand.
    pub fn silenceMeans(self: Boundary) []const u8 {
        return switch (self) {
            .write_pointer_updated => "the title published once and stopped. It is waiting for something, and the thing it waits for is a completion the emulator owes it — find which object the publishing thread parked on before looking at the command processor",
            .command_processor_worker_running => "the command processor's worker loop stopped iterating. Either it is blocked inside a packet or its wake source died",
            .execute_primary_buffer => "the command processor drained the ring once and was never woken again. Either nothing further was published or the wake path from the write pointer to the worker is broken",
            .execute_packet_type3 => "packet dispatch stopped. The batch that was there was consumed and no more arrived",
            .write_register => "register programming stopped",
            .register_range_from_ring => "register ranges stopped arriving from the ring",
            .make_coherent => "coherency operations stopped",
            .issue_draw => "draws stopped being issued. Work was rendered and then the producer went quiet",
            .render_target_update => "the render target cache stopped updating",
            .xe_swap_decoded => "swap packets stopped being decoded",
            .mark_vblank => "the vblank pump stopped. Everything the title waits on for timing is now frozen, and every downstream silence is a consequence of this one",
            .dispatch_interrupt_callback => "graphics interrupt dispatch stopped",
            .emulate_cp_interrupt_dpc => "the graphics interrupt stopped entering the guest. The title's frame loop has no clock, so it will wait forever no matter what the GPU does",
            .graphics_notification_routines => "the title stopped running its notification routines",
            .guest_swap_requested => "the title presented and then stopped presenting",
            .swap_notified_to_graphics_system => "swap notifications stopped reaching the graphics system",
            .issue_swap => "the command processor stopped issuing swaps",
            .refresh_guest_output => "guest output stopped being refreshed, so the window now holds a stale frame",
            .refresh_guest_output_impl => "the backend refresh stopped",
            .host_paint => "the host surface stopped being painted",
            else => "this boundary is crossed once during bring-up, so silence after it is the normal shape and carries no finding",
        };
    }

    pub fn phase(self: Boundary) Phase {
        return switch (self) {
            .query_video_mode,
            .query_display_information,
            .initialize_engines,
            .graphics_asic_id,
            .hsio_training_query,
            .retrain_edram,
            .set_interrupt_callback,
            .initialize_ring_buffer,
            .enable_rptr_write_back,
            .system_command_buffer_query,
            .system_command_buffer_identifier,
            .scaler_command_buffer,
            .persist_display,
            => .bringup,

            .write_pointer_updated,
            .command_processor_worker_running,
            .execute_primary_buffer,
            => .submission,

            .execute_packet_type3,
            .write_register,
            .register_range_from_ring,
            .make_coherent,
            .issue_draw,
            .render_target_update,
            .xe_swap_decoded,
            => .consumption,

            .mark_vblank,
            .dispatch_interrupt_callback,
            .emulate_cp_interrupt_dpc,
            .graphics_notification_routines,
            .read_pointer_write_back_store,
            => .completion,

            .guest_swap_requested,
            .swap_notified_to_graphics_system,
            .issue_swap,
            .refresh_guest_output,
            .refresh_guest_output_impl,
            .host_paint,
            => .presentation,
        };
    }

    pub fn owner(self: Boundary) Owner {
        return switch (self) {
            // The Vd* shims are reached only because the title's export
            // dispatch jumped into them, so their absence is the title's.
            .query_video_mode,
            .query_display_information,
            .initialize_engines,
            .graphics_asic_id,
            .hsio_training_query,
            .retrain_edram,
            .set_interrupt_callback,
            .initialize_ring_buffer,
            .enable_rptr_write_back,
            .system_command_buffer_query,
            .system_command_buffer_identifier,
            .scaler_command_buffer,
            .persist_display,
            .graphics_notification_routines,
            .guest_swap_requested,
            => .guest_title,

            .write_pointer_updated => .guest_title,

            .command_processor_worker_running,
            .execute_primary_buffer,
            .execute_packet_type3,
            .write_register,
            .register_range_from_ring,
            .make_coherent,
            .issue_draw,
            .render_target_update,
            .xe_swap_decoded,
            .read_pointer_write_back_store,
            .issue_swap,
            => .emulator_command_processor,

            .mark_vblank,
            .dispatch_interrupt_callback,
            .emulate_cp_interrupt_dpc,
            .swap_notified_to_graphics_system,
            => .emulator_graphics_system,

            .refresh_guest_output,
            .refresh_guest_output_impl,
            .host_paint,
            => .emulator_presenter,
        };
    }

    pub fn requirement(self: Boundary) Requirement {
        return switch (self) {
            .initialize_engines,
            .set_interrupt_callback,
            .initialize_ring_buffer,
            .write_pointer_updated,
            .command_processor_worker_running,
            .execute_primary_buffer,
            .execute_packet_type3,
            .issue_draw,
            .guest_swap_requested,
            .issue_swap,
            .refresh_guest_output,
            => .required,

            .query_video_mode,
            .enable_rptr_write_back,
            .system_command_buffer_query,
            .write_register,
            .register_range_from_ring,
            .render_target_update,
            .xe_swap_decoded,
            .mark_vblank,
            .dispatch_interrupt_callback,
            .emulate_cp_interrupt_dpc,
            .read_pointer_write_back_store,
            .swap_notified_to_graphics_system,
            .refresh_guest_output_impl,
            .host_paint,
            => .expected,

            .query_display_information,
            .graphics_asic_id,
            .hsio_training_query,
            .retrain_edram,
            .system_command_buffer_identifier,
            .scaler_command_buffer,
            .persist_display,
            .make_coherent,
            .graphics_notification_routines,
            => .optional,
        };
    }

    /// The boundary that must be crossed before this one is eligible.
    ///
    /// Sparse on purpose. Most of the bring-up surface has no prerequisite at
    /// all: a title may query its video mode, ask for an ASIC ID and never
    /// initialise engines, in any order it likes. Inventing edges here would
    /// mark real findings "blocked upstream" and hide them.
    ///
    /// `host_paint` deliberately has none, and the reason is worth keeping.
    /// It was given `refresh_guest_output` as a prerequisite on the first
    /// pass, which is wrong: the presenter paints the window whether or not a
    /// guest frame was ever refreshed into it — that is how a diagnostic frame
    /// reaches the screen. The 2026-08-30 20:08 run painted five times at step
    /// 652 933 741 with no guest output, the gate read that as an inversion,
    /// and because an inversion outranks every other finding it reported the
    /// same benign fact at every checkpoint for the rest of the run while the
    /// real frontier went unnamed. An edge that does not hold on hardware
    /// costs more than a missing one.
    pub fn prerequisite(self: Boundary) ?Boundary {
        return switch (self) {
            .initialize_ring_buffer => .initialize_engines,
            .enable_rptr_write_back => .initialize_ring_buffer,
            .write_pointer_updated => .initialize_ring_buffer,
            .execute_primary_buffer => .write_pointer_updated,
            .execute_packet_type3 => .execute_primary_buffer,
            .register_range_from_ring => .execute_packet_type3,
            .issue_draw => .execute_packet_type3,
            .render_target_update => .issue_draw,
            .xe_swap_decoded => .execute_packet_type3,
            .issue_swap => .xe_swap_decoded,
            .refresh_guest_output => .issue_swap,
            .refresh_guest_output_impl => .refresh_guest_output,
            .swap_notified_to_graphics_system => .guest_swap_requested,
            .emulate_cp_interrupt_dpc => .dispatch_interrupt_callback,
            .dispatch_interrupt_callback => .mark_vblank,
            .read_pointer_write_back_store => .enable_rptr_write_back,
            else => null,
        };
    }

    /// What this boundary never having been entered actually tells a reader,
    /// assuming its prerequisite was crossed and a tracepoint was armed.
    ///
    /// These sentences are the deliverable. A table of `state=NO` rows sends
    /// the next hour to whichever row was read first; a sentence that names the
    /// consequence sends it to the one that matters.
    pub fn absenceMeans(self: Boundary) []const u8 {
        return switch (self) {
            .query_video_mode => "the title has not asked what display it has, so it has not begun graphics bring-up at all. Look at what it is doing instead, not at the GPU",
            .query_display_information => "the title did not read display information. Titles that hard-code a mode skip this; it carries no finding on its own",
            .initialize_engines => "the title never turned the GPU on. Every graphics zero below this is a consequence and none of them is a separate finding",
            .graphics_asic_id => "the title did not read the ASIC identifier. Optional; carries no finding",
            .hsio_training_query => "the title did not query HSIO training. Optional; carries no finding",
            .retrain_edram => "the title did not retrain EDRAM. Optional; carries no finding",
            .set_interrupt_callback => "the title registered no graphics interrupt callback, so the emulator has nowhere to report a finished frame. A title that submits once and then waits forever is showing exactly this: the submission worked and the completion has no route back",
            .initialize_ring_buffer => "the title never handed the emulator a command ring. The command processor has not been asked to do anything, so its counters reading zero are correct and say nothing",
            .enable_rptr_write_back => "the title did not ask for read-pointer write-back, so it is not learning how far the GPU has drained from memory. It must therefore be using the interrupt callback or a fence; check which",
            .system_command_buffer_query => "the title never asked for the system command buffer",
            .system_command_buffer_identifier => "the title did not set a system command buffer identifier address. Optional",
            .scaler_command_buffer => "the title did not initialise a scaler command buffer. Optional",
            .persist_display => "the title did not persist the display. Optional",
            .write_pointer_updated => "no ring write pointer store reached the command processor. The title has produced no work, whatever a memory scan of the ring appears to show — bytes that resemble packets in an unpublished ring are uninitialised memory, not a submission",
            .command_processor_worker_running => "the command processor's worker loop never ran. This is the emulator's own thread and its absence is an emulator defect, not a title one",
            .execute_primary_buffer => "the command processor never began draining the ring, so nothing the title published has been read",
            .execute_packet_type3 => "no PM4 type-3 packet was dispatched. The ring was drained and contained no command packets, or the drain stopped before reaching one",
            .write_register => "no register write reached the command processor, so no GPU state was programmed",
            .register_range_from_ring => "no register range was written from the ring",
            .make_coherent => "the command processor never made memory coherent. Optional on this path",
            .issue_draw => "no draw was issued. State may have been programmed, but nothing was rendered",
            .render_target_update => "the render target cache never updated, so no surface was bound for a draw to land in",
            .xe_swap_decoded => "no XE_SWAP packet was decoded. The title has submitted work but never a present request",
            .mark_vblank => "the emulator's vblank never fired. Nothing is pumping the display clock, so a title waiting on vblank waits forever",
            .dispatch_interrupt_callback => "the emulator never dispatched a graphics interrupt. The vblank source is not reaching the callback path",
            .emulate_cp_interrupt_dpc => "the graphics interrupt never entered the guest. The emulator's own dispatch may be running and returning early because no callback is registered — check the registration boundary before blaming the pump",
            .graphics_notification_routines => "the title did not run its graphics notification routines. Optional",
            .read_pointer_write_back_store => "read-pointer write-back was requested and the command processor never enabled it, so the title's view of GPU progress is frozen at its initial value",
            .guest_swap_requested => "the title never asked to present. Everything downstream is waiting on a request that was never made, and the question is what the title is doing instead",
            .swap_notified_to_graphics_system => "the swap request never reached the graphics system",
            .issue_swap => "the command processor never issued a swap, so no frame was handed to the presenter",
            .refresh_guest_output => "the presenter was never given guest output to refresh, so everything on screen is the host's own drawing",
            .refresh_guest_output_impl => "the backend presenter refresh never ran",
            .host_paint => "the host surface was never painted from a guest frame",
        };
    }
};

pub const boundary_count: usize = @typeInfo(Boundary).@"enum".fields.len;

/// Every boundary in declaration order, which is console order.
pub fn allBoundaries() [boundary_count]Boundary {
    var out: [boundary_count]Boundary = undefined;
    for (&out, 0..) |*slot, index| slot.* = @enumFromInt(index);
    return out;
}

/// The boundaries in one phase, in order.
pub fn phaseBoundaries(comptime which: Phase) []const Boundary {
    const held = comptime blk: {
        var buffer: [boundary_count]Boundary = undefined;
        var length: usize = 0;
        for (allBoundaries()) |boundary| {
            if (boundary.phase() != which) continue;
            buffer[length] = boundary;
            length += 1;
        }
        const frozen: [length]Boundary = buffer[0..length].*;
        break :blk frozen;
    };
    return &held;
}

/// A bitset over boundaries. Thirty-four boundaries fit in a u64 with room to
/// grow, which keeps a whole pipeline state in one register and makes the
/// "crossed" test a single shift.
pub const Mask = u64;

pub fn bit(boundary: Boundary) Mask {
    return @as(Mask, 1) << @intCast(@intFromEnum(boundary));
}

pub fn isSet(mask: Mask, boundary: Boundary) bool {
    return mask & bit(boundary) != 0;
}

/// The mask of boundaries whose prerequisite is satisfied but which have not
/// themselves been crossed. This is the actionable set: everything outside it
/// is either done or waiting on something else, and reporting the difference is
/// what turns thirty rows into one finding.
pub fn actionable(crossed: Mask, watched: Mask) Mask {
    var out: Mask = 0;
    for (allBoundaries()) |boundary| {
        if (isSet(crossed, boundary)) continue;
        if (!isSet(watched, boundary)) continue;
        if (boundary.prerequisite()) |earlier| {
            if (!isSet(crossed, earlier)) continue;
        }
        out |= bit(boundary);
    }
    return out;
}

/// The first boundary in console order that was watched, is eligible, and was
/// never crossed. This is the frontier, and it is the one line a reader needs.
///
/// `watched` is not optional. A boundary nothing was observing must never be
/// reported as a frontier: that is the difference between "the title did not
/// do this" and "Rosette did not look", and confusing the two is what sent
/// three passes of this investigation downstream of a boundary nobody had
/// confirmed.
pub fn frontier(crossed: Mask, watched: Mask) ?Boundary {
    for (allBoundaries()) |boundary| {
        if (boundary.requirement() == .optional) continue;
        if (isSet(crossed, boundary)) continue;
        if (!isSet(watched, boundary)) continue;
        if (boundary.prerequisite()) |earlier| {
            if (!isSet(crossed, earlier)) continue;
        }
        return boundary;
    }
    return null;
}

/// The first boundary that is eligible and that *nothing is watching*. A run
/// with one of these cannot make a negative claim below it, and saying so is
/// more useful than any of the zeroes underneath.
pub fn firstUnwatched(crossed: Mask, watched: Mask) ?Boundary {
    for (allBoundaries()) |boundary| {
        if (boundary.requirement() == .optional) continue;
        if (isSet(crossed, boundary)) continue;
        if (isSet(watched, boundary)) continue;
        if (boundary.prerequisite()) |earlier| {
            if (!isSet(crossed, earlier)) continue;
        }
        return boundary;
    }
    return null;
}

/// A boundary crossed while its prerequisite never was. On real hardware this
/// cannot happen, so it always means one of the two observations is wrong —
/// and it is nearly always the negative one, because a crossing is proof and an
/// absence is only ever the absence of proof.
pub fn inversions(crossed: Mask) Mask {
    var out: Mask = 0;
    for (allBoundaries()) |boundary| {
        if (!isSet(crossed, boundary)) continue;
        const earlier = boundary.prerequisite() orelse continue;
        if (!isSet(crossed, earlier)) out |= bit(boundary);
    }
    return out;
}

/// How many boundaries in a phase were crossed, out of how many were watched.
/// Reported as a pair rather than a percentage: `0/0` and `0/9` look identical
/// as a percentage and mean opposite things.
pub const PhaseProgress = struct {
    crossed: u8 = 0,
    watched: u8 = 0,
    total: u8 = 0,

    /// True when nothing in the phase was ever observable, so its zero is
    /// Rosette's and not the title's.
    pub fn blind(self: PhaseProgress) bool {
        return self.watched == 0;
    }
};

pub fn phaseProgress(which: Phase, crossed: Mask, watched: Mask) PhaseProgress {
    var out = PhaseProgress{};
    for (allBoundaries()) |boundary| {
        if (boundary.phase() != which) continue;
        out.total += 1;
        if (isSet(watched, boundary)) out.watched += 1;
        if (isSet(crossed, boundary)) out.crossed += 1;
    }
    return out;
}

/// The phase the run is actually stuck in: the earliest phase that has been
/// entered and not completed for its required boundaries. Named separately
/// from `frontier` because a reader wants both "which call" and "which layer".
pub fn stuckPhase(crossed: Mask, watched: Mask) ?Phase {
    const first = frontier(crossed, watched) orelse return null;
    return first.phase();
}

test "a broad class fragment is narrowed by a second required substring" {
    try std.testing.expect(Boundary.render_target_update.alsoRequires().len != 0);
    try std.testing.expect(Boundary.query_video_mode.alsoRequires().len == 0);
}

test "every boundary has a distinct label and a non-empty fragment" {
    for (allBoundaries()) |boundary| {
        try std.testing.expect(boundary.label().len != 0);
        try std.testing.expect(boundary.fragment().len != 0);
        try std.testing.expect(boundary.absenceMeans().len != 0);
        for (allBoundaries()) |other| {
            if (boundary == other) continue;
            try std.testing.expect(!std.mem.eql(u8, boundary.label(), other.label()));
        }
    }
}

test "the enum fits the mask" {
    try std.testing.expect(boundary_count <= @bitSizeOf(Mask));
}

// A prerequisite that came later in the enum than its dependant would make
// `frontier` report a boundary whose predecessor it had not yet examined.
test "every prerequisite precedes its dependant in console order" {
    for (allBoundaries()) |boundary| {
        const earlier = boundary.prerequisite() orelse continue;
        try std.testing.expect(@intFromEnum(earlier) < @intFromEnum(boundary));
    }
}

// The distinction the whole package exists for.
test "an unwatched boundary is never reported as the frontier" {
    const watched = bit(.query_video_mode) | bit(.initialize_ring_buffer);
    const crossed = bit(.query_video_mode);
    // `initialize_engines` is unwatched, so it cannot be the frontier even
    // though it is required and uncrossed.
    try std.testing.expect(frontier(crossed, watched) == null);
    try std.testing.expectEqual(Boundary.initialize_engines, firstUnwatched(crossed, watched).?);
}

test "the frontier is the first eligible watched boundary that never ran" {
    var watched: Mask = 0;
    for (allBoundaries()) |boundary| watched |= bit(boundary);
    const crossed = bit(.query_video_mode) | bit(.initialize_engines);
    try std.testing.expectEqual(Boundary.set_interrupt_callback, frontier(crossed, watched).?);
    try std.testing.expectEqual(Phase.bringup, stuckPhase(crossed, watched).?);
}

// The 2026-08-30 Halo 3 reading: the ring was initialised and drained once,
// no interrupt callback was ever registered, and nothing presented.
test "the observed Halo 3 shape names the registration, not the presenter" {
    var watched: Mask = 0;
    for (allBoundaries()) |boundary| watched |= bit(boundary);
    const crossed =
        bit(.query_video_mode) |
        bit(.initialize_engines) |
        bit(.initialize_ring_buffer) |
        bit(.enable_rptr_write_back) |
        bit(.write_pointer_updated) |
        bit(.command_processor_worker_running) |
        bit(.execute_primary_buffer) |
        bit(.execute_packet_type3) |
        bit(.issue_draw);
    try std.testing.expectEqual(Boundary.set_interrupt_callback, frontier(crossed, watched).?);
    // And the presenter's zeroes are not findings: they are blocked upstream.
    const live = actionable(crossed, watched);
    try std.testing.expect(!isSet(live, .refresh_guest_output));
    try std.testing.expect(!isSet(live, .issue_swap));
}

test "a crossing without its prerequisite is reported as an inversion" {
    const crossed = bit(.initialize_ring_buffer) | bit(.write_pointer_updated);
    const found = inversions(crossed);
    try std.testing.expect(isSet(found, .initialize_ring_buffer));
    try std.testing.expect(!isSet(found, .write_pointer_updated));
}

test "phase progress distinguishes blind from unreached" {
    const nothing_watched = phaseProgress(.presentation, 0, 0);
    try std.testing.expect(nothing_watched.blind());
    var watched: Mask = 0;
    for (phaseBoundaries(.presentation)) |boundary| watched |= bit(boundary);
    const watched_and_zero = phaseProgress(.presentation, 0, watched);
    try std.testing.expect(!watched_and_zero.blind());
    try std.testing.expectEqual(@as(u8, 0), watched_and_zero.crossed);
}

test "optional boundaries never become the frontier" {
    var watched: Mask = 0;
    for (allBoundaries()) |boundary| watched |= bit(boundary);
    var crossed: Mask = 0;
    for (allBoundaries()) |boundary| {
        if (boundary.requirement() != .optional) crossed |= bit(boundary);
    }
    try std.testing.expect(frontier(crossed, watched) == null);
}

test "phase membership partitions the surface" {
    var seen: usize = 0;
    inline for (@typeInfo(Phase).@"enum".fields) |field| {
        seen += phaseBoundaries(@enumFromInt(field.value)).len;
    }
    try std.testing.expectEqual(boundary_count, seen);
}

// An exclusion that matches the boundary's own mangled name disarms the very
// tracepoint it was meant to protect, and the resulting zero is indistinguishable
// from the title never calling the function. `VdSwap_entryE` was written as an
// exclusion for `guest_swap_requested` and it is a substring of
// `__ZN2xe6kernel8xboxkrnl12VdSwap_entryERKNS0_...` — the shim itself.
test "no exclusion can reject its own boundary's mangled name" {
    for (allBoundaries()) |boundary| {
        const fragment = boundary.fragment();
        for (boundary.exclusions()) |excluded| {
            const at = std.mem.indexOf(u8, excluded, fragment) orelse continue;
            // An exclusion is allowed to extend the fragment — that is how
            // `ExecutePacketType3_` separates the generic dispatcher from its
            // handlers. What it must never do is extend it with the character
            // Itanium mangling itself puts there. A nested function name is
            // always terminated by `E` before the parameter list, so an
            // exclusion of `VdSwap_entryE` matches
            // `__ZN2xe6kernel8xboxkrnl12VdSwap_entryERKNS0_...` — the shim it
            // was meant to protect — and disarms the tracepoint entirely. The
            // resulting zero is indistinguishable from the title never calling
            // `VdSwap`, which is the single fact this whole investigation has
            // been trying to establish.
            const tail = excluded[at + fragment.len ..];
            if (tail.len == 0) continue;
            try std.testing.expect(tail[0] != 'E');
        }
    }
}

test "the swap-provenance exclusions are present" {
    var found_debug = false;
    for (Boundary.issue_swap.exclusions()) |excluded| {
        if (std.mem.eql(u8, excluded, "DebugIssueSwapFromHost")) found_debug = true;
    }
    try std.testing.expect(found_debug);
}

test "guest-owned absences are not harness actionable" {
    try std.testing.expect(!Boundary.initialize_engines.owner().absenceIsHarnessActionable());
    try std.testing.expect(Boundary.mark_vblank.owner().absenceIsHarnessActionable());
}

test "only autonomous pumps repeat and work-triggered boundaries are event driven" {
    try std.testing.expectEqual(Cadence.repeating, Boundary.mark_vblank.cadence());
    try std.testing.expectEqual(Cadence.repeating, Boundary.dispatch_interrupt_callback.cadence());
    try std.testing.expectEqual(Cadence.repeating, Boundary.emulate_cp_interrupt_dpc.cadence());
    try std.testing.expectEqual(Cadence.event_driven, Boundary.write_pointer_updated.cadence());
    try std.testing.expectEqual(Cadence.event_driven, Boundary.execute_packet_type3.cadence());
    try std.testing.expectEqual(Cadence.event_driven, Boundary.issue_draw.cadence());
    try std.testing.expectEqual(Cadence.event_driven, Boundary.host_paint.cadence());
    try std.testing.expectEqual(Cadence.once, Boundary.initialize_ring_buffer.cadence());
    try std.testing.expectEqual(Cadence.once, Boundary.set_interrupt_callback.cadence());
}

test "every repeating boundary explains its own silence" {
    const shared = Boundary.initialize_ring_buffer.silenceMeans();
    for (allBoundaries()) |boundary| {
        if (boundary.cadence() != .repeating) continue;
        try std.testing.expect(boundary.silenceMeans().len != 0);
        // A repeating boundary that fell through to the once-only sentence
        // would report its own stall as normal, which is the exact reading
        // that hid a vblank pump firing four times in seventeen minutes.
        try std.testing.expect(!std.mem.eql(u8, boundary.silenceMeans(), shared));
    }
}

// The regression the 2026-08-30 20:08 run produced. The presenter painting
// without guest output is normal — it is how a diagnostic frame is shown — and
// modelling it as an ordering violation made a benign fact outrank every real
// finding for the rest of the run.
test "painting the host surface without guest output is not an inversion" {
    const crossed = bit(.host_paint);
    try std.testing.expectEqual(@as(Mask, 0), inversions(crossed));
    try std.testing.expect(Boundary.host_paint.prerequisite() == null);
}
