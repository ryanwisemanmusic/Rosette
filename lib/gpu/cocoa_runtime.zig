//! Runtime reconciliation for the Cocoa graphics control contract.
//!
//! This module is the process-independent join point between AppKit objects,
//! Rosette's presenter, Xenia's Vulkan objects, Xenos work, callback domains,
//! and completed frame descriptors.  It deliberately accepts snapshots rather
//! than pointers to any of those implementations.  The reconciliation layer
//! can therefore say that two reports describe the same object, or quarantine
//! them when they do not, without becoming another owner of either system.
//!
//! Counters are treated as observations.  Work is credited only when a stable
//! `(run, producer, stream, generation, sequence, kind)` identity advances.
//! Re-reading one 24-draw PM4 batch on 148 heartbeats still describes 24 draws.

const std = @import("std");
const contract = @import("cocoa_graphics_control_contract");
const control_plane = @import("cocoa_control_plane.zig");
const frame_handoff = @import("frame_handoff.zig");
const graphics_intent = @import("graphics_intent.zig");
const work_credit = @import("work_credit.zig");

pub const Domain = contract.Domain;
pub const Resource = contract.Resource;
pub const Stage = contract.Stage;
pub const Route = contract.Route;
pub const RoutePolicy = contract.RoutePolicy;
pub const schema_version = contract.schema_version;
pub const PixelFormat = frame_handoff.PixelFormat;
pub const Orientation = frame_handoff.Orientation;
pub const Fit = frame_handoff.Fit;

pub const NativeSnapshot = struct {
    application: u64 = 0,
    window: u64 = 0,
    content_view: u64 = 0,
    metal_layer: u64 = 0,
    metal_device: u64 = 0,
    application_ready: bool = false,
    window_ready: bool = false,
    layer_attached: bool = false,
    diagnostic_frames: u64 = 0,
    guest_frames: u64 = 0,
    /// The drawable Rosette's own presentations land on. Custody needs an
    /// extent and a format for every frame it holds, including the ones the
    /// host drew, and inventing them at the custody boundary would make the
    /// ledger describe a surface nobody looked at.
    drawable_width: u32 = 0,
    drawable_height: u32 = 0,
    drawable_format: u32 = 0,
};

pub const SdlSnapshot = struct {
    event_loop: u64 = 0,
    window_binding: u64 = 0,
    binding_generation: u64 = 1,
    /// Host identities from the canonical AppKit snapshot. These are present
    /// only after the SDL ABI adapter returned the matching native tokens.
    cocoa_window: u64 = 0,
    cocoa_content_view: u64 = 0,
    initialized: bool = false,
    window_bound: bool = false,
};

/// Rosette's presenter and Xenia's real Vulkan path intentionally use the same
/// shape but are never merged.  `metal_layer` is meaningful for Rosette because
/// it can be compared with AppKit's canonical layer; a zero value means no
/// implementation supplied enough evidence to make that comparison.
pub const VulkanSnapshot = struct {
    metal_layer: u64 = 0,
    instance: u64 = 0,
    surface: u64 = 0,
    device: u64 = 0,
    queue: u64 = 0,
    swapchain: u64 = 0,
    generation: u64 = 1,
    ready: bool = false,
    submissions: u64 = 0,
    presents: u64 = 0,
    diagnostic_frames: u64 = 0,
    host_frames: u64 = 0,
    guest_output_frames: u64 = 0,

    pub fn presenterReady(self: VulkanSnapshot) bool {
        return self.surface != 0 and self.device != 0 and self.queue != 0 and
            self.swapchain != 0 and self.ready;
    }
};

pub const XenosSnapshot = struct {
    ring: u64 = 0,
    ring_generation: u64 = 1,
    ring_publications: u64 = 0,
    command_stream: u64 = 0,
    command_generation: u64 = 1,
    batches: u64 = 0,
    packets: u64 = 0,
    draws: u64 = 0,
    completion_signals: u64 = 0,
    render_target: u64 = 0,
    render_target_state: bool = false,
    render_target_memory: bool = false,
    front_buffer: u64 = 0,
    guest_vdswap_entries: u64 = 0,
    guest_xe_swap_encoded: bool = false,
    authentic_xe_swap_consumed: u64 = 0,
    issue_swap_entries: u64 = 0,
};

pub const CallbackSnapshot = struct {
    powerpc_address: u64 = 0,
    powerpc_registrations: u64 = 0,
    powerpc_returns: u64 = 0,
    translated_x86_address: u64 = 0,
    translated_x86_registrations: u64 = 0,
    translated_x86_dispatches: u64 = 0,
};

pub const FrameOrigin = enum(u8) {
    diagnostic,
    xenia_host,
    guest_title,

    pub fn domain(self: FrameOrigin) Domain {
        return switch (self) {
            .diagnostic => .rosette_runtime,
            .xenia_host => .xenia_host,
            .guest_title => .guest_title,
        };
    }

    pub fn resource(self: FrameOrigin) contract.Resource {
        return switch (self) {
            .diagnostic => .diagnostic_frame,
            .xenia_host => .xenia_host_frame,
            .guest_title => .guest_frame,
        };
    }

    pub fn offeredStage(self: FrameOrigin) ?contract.Stage {
        return switch (self) {
            .diagnostic => null,
            .xenia_host => .xenia_host_frame_offered,
            .guest_title => .guest_frame_offered,
        };
    }

    pub fn carriesGuestPixels(self: FrameOrigin) bool {
        return self != .diagnostic;
    }

    /// A diagnostic frame has no source buffer: it is a clear the host drew on
    /// the window's own drawable. Deriving this from the origin rather than
    /// accepting it as a field means the pair cannot be set inconsistently.
    pub fn payload(self: FrameOrigin) frame_handoff.Payload {
        return switch (self) {
            .diagnostic => .host_generated,
            .xenia_host, .guest_title => .guest_memory,
        };
    }
};

pub const FrameSnapshot = struct {
    source_address: u64 = 0,
    source_length: u64 = 0,
    width: u32 = 0,
    height: u32 = 0,
    row_pitch: u64 = 0,
    format: PixelFormat = .unknown,
    orientation: Orientation = .top_down,
    fit: Fit = .letterbox,
    origin: FrameOrigin = .xenia_host,
    generation: u64 = 1,
    serial: u64 = 0,
    content_digest: u64 = 0,
    guest_swap_observed: bool = false,
    consumed: bool = false,
    /// Presentations this one snapshot stands for. Greater than one when the
    /// presenter put several frames up between two reconciles.
    presentations_covered: u64 = 1,

    pub fn identity(self: FrameSnapshot, run: u64) frame_handoff.Identity {
        return .{
            .run = run,
            .source = self.source_address,
            .generation = nonzero(self.generation),
            .serial = self.serial,
        };
    }

    pub fn descriptor(self: FrameSnapshot, run: u64) frame_handoff.Descriptor {
        return .{
            .identity = self.identity(run),
            .payload = self.origin.payload(),
            .source_address = self.source_address,
            .source_length = self.source_length,
            .width = self.width,
            .height = self.height,
            .row_pitch = self.row_pitch,
            .format = self.format,
            .orientation = self.orientation,
            .fit = self.fit,
            .producer = self.origin.domain(),
            .content_digest = self.content_digest,
            .guest_pixels = self.origin.carriesGuestPixels(),
            .guest_requested_present = self.guest_swap_observed,
            .presentations_covered = @max(self.presentations_covered, 1),
        };
    }

    pub fn verified(self: FrameSnapshot, run: u64) bool {
        return frame_handoff.validate(self.descriptor(run)) == .none;
    }
};

pub const Snapshot = struct {
    run: u64 = 1,
    step: u64 = 0,
    native: NativeSnapshot = .{},
    sdl: SdlSnapshot = .{},
    rosette_vulkan: VulkanSnapshot = .{},
    xenia_vulkan: VulkanSnapshot = .{},
    xenos: XenosSnapshot = .{},
    callbacks: CallbackSnapshot = .{},
    latest_frame: ?FrameSnapshot = null,
    diagnostic_requested: bool = false,
    /// True only when the native bridge has a real Cocoa/Metal guest-buffer
    /// copy implementation and its canonical window/layer/device are ready.
    /// Merely observing a CAMetalLayer is not sufficient evidence.
    metal_guest_copy_ready: bool = false,
};

pub const Outcome = struct {
    route: Route = .wait,
    ownership_conflict: bool = false,
    frame_observed: bool = false,
    frame_offer: frame_handoff.OfferResult = .overflow,
    frame_class: contract.FrameClass = .none,
    frame_identity: frame_handoff.Identity = .{},
    /// True when the frame taken into custody this reconcile was Rosette's own
    /// diagnostic presentation rather than anything the emulator produced.
    diagnostic_custody: bool = false,
    /// True only while the selected direct Metal route owns a validated,
    /// submitted frame that the native bridge has not completed. Keeping this
    /// separate from `route` lets the route remain observable after completion
    /// without retrying one retained descriptor on every heartbeat.
    frame_delivery_pending: bool = false,
    new_work_claims: u64 = 0,
    duplicate_work_observations: u64 = 0,
};

pub const Runtime = struct {
    control: control_plane.ControlPlane = .{},
    frames: frame_handoff.Ledger = .{},
    intents: graphics_intent.Ledger = .{},
    credits: work_credit.Ledger = .{},
    run: u64 = 0,
    configured: bool = false,
    reconciliations: u64 = 0,
    run_resets: u64 = 0,
    last_ring_publications: u64 = 0,
    last_powerpc_returns: u64 = 0,
    last_x86_dispatches: u64 = 0,
    last_guest_vdswap_entries: u64 = 0,
    last_rosette_diagnostic_frames: u64 = 0,
    last_rosette_host_frames: u64 = 0,
    last_rosette_guest_frames: u64 = 0,
    last_cocoa_diagnostic_frames: u64 = 0,
    last_cocoa_guest_frames: u64 = 0,
    /// Serial of the newest diagnostic presentation already in custody. Frames
    /// are credited on advance, so re-reading the same counter on a hundred
    /// heartbeats still describes the frames that were actually drawn.
    last_diagnostic_custody: u64 = 0,
    last_xenia_submissions: u64 = 0,
    last_xenia_presents: u64 = 0,
    last_frame_serial: u64 = 0,

    pub fn configure(self: *Runtime, policy: RoutePolicy) void {
        self.control.policy = policy;
        self.configured = true;
    }

    pub fn reconcile(self: *Runtime, source: Snapshot) Outcome {
        const run = nonzero(source.run);
        self.ensureRun(run);
        self.reconciliations +|= 1;

        self.observeNative(source.native, source.step);
        self.observeSdl(source.sdl, source.step);
        self.observeRosetteVulkan(source.rosette_vulkan, source.step);
        self.observeXeniaVulkan(source.xenia_vulkan, source.step);
        self.observeXenos(source.xenos, source.step);
        self.observeCallbacks(source.callbacks, source.step);
        self.observeAggregateWork(source, run);
        self.updatePresenterLease(source, source.step);

        const verified_frame = if (source.latest_frame) |frame| frame.verified(run) else false;
        const supported_frame = if (source.latest_frame) |frame| frame.format != .unknown else false;
        const xenia_presenter_ready = source.xenia_vulkan.presenterReady();
        const route = self.control.chooseRoute(.{
            .xenia_presenter_ready = xenia_presenter_ready,
            .xenia_present_seen = source.xenia_vulkan.presents != 0,
            .verified_guest_frame = verified_frame and source.latest_frame.?.origin.carriesGuestPixels(),
            .guest_frame_format_supported = supported_frame,
            .metal_guest_copy_ready = source.metal_guest_copy_ready,
            .diagnostic_requested = source.diagnostic_requested,
        });

        var result = Outcome{
            .route = route,
            .ownership_conflict = self.control.hasConflict(),
        };
        if (source.latest_frame) |frame| {
            result.frame_observed = true;
            result.frame_identity = frame.identity(run);
            result.frame_offer = self.reconcileFrame(frame, run, route, source.step, &result.frame_class);
            if (self.frames.lookup(result.frame_identity)) |record| {
                result.frame_delivery_pending = route == .cocoa_metal_guest_copy and
                    !frame.consumed and record.state == .submitted;
            }
        } else if (self.diagnosticFrame(source)) |frame| {
            // Rosette's own presentations are the only pixels on this window
            // for the whole of a run where the title never swaps, and they used
            // to reach the drawable without any custody record at all. A window
            // that shows pixels nothing took custody of cannot answer who put
            // them there. They enter as `host_generated`, so they are counted,
            // classified `diagnostic-host`, and can never be mistaken for guest
            // output.
            result.frame_observed = true;
            result.diagnostic_custody = true;
            result.frame_identity = frame.identity(run);
            result.frame_offer = self.reconcileFrame(frame, run, route, source.step, &result.frame_class);
        }
        const credit_summary = self.credits.summary();
        result.new_work_claims = credit_summary.unique_claims;
        result.duplicate_work_observations = credit_summary.duplicates;
        return result;
    }

    /// Claim work at the point it actually executes.  The process uses this
    /// for retained PM4 batches, where an aggregate heartbeat counter cannot
    /// preserve the payload digest or root-batch identity.
    pub fn claimExecutedWork(self: *Runtime, claim: work_credit.Claim) work_credit.Result {
        self.ensureRun(nonzero(claim.key.run));
        return self.credits.claim(claim);
    }

    /// Admit or reject graphics meaning at a typed runtime boundary. This is
    /// deliberately separate from work credit: an operation may be recognized
    /// once and carry 24 units of work, and neither fact should inflate the
    /// other when the same checkpoint is observed again.
    pub fn observeIntent(self: *Runtime, request: graphics_intent.Request) graphics_intent.ObserveResult {
        self.ensureRun(nonzero(request.run));
        return self.intents.observe(request);
    }

    pub fn fingerprint(self: *const Runtime) u64 {
        var hash = self.control.fingerprint();
        const frame_summary = self.frames.summary();
        hash = mix(hash, frame_summary.offered);
        hash = mix(hash, frame_summary.rejected);
        hash = mix(hash, frame_summary.conflicts);
        hash = mix(hash, frame_summary.presented);
        hash = mix(hash, @intFromEnum(frame_summary.last_class));
        hash = mix(hash, self.intents.fingerprint());
        hash = mix(hash, self.credits.fingerprint());
        hash = mix(hash, self.run);
        return hash;
    }

    fn ensureRun(self: *Runtime, requested_run: u64) void {
        if (self.run == requested_run) return;
        const selected_policy = self.control.policy;
        const was_configured = self.configured;
        const resets = self.run_resets +| @intFromBool(self.run != 0);
        self.* = .{};
        self.run = requested_run;
        self.run_resets = resets;
        self.configured = was_configured;
        self.control.policy = selected_policy;
    }

    fn observeNative(self: *Runtime, native: NativeSnapshot, step: u64) void {
        observeOwned(&self.control, .appkit_application, native.application, 1, .cocoa_appkit, .observed_state, step);
        observeOwned(&self.control, .appkit_window, native.window, 1, .cocoa_appkit, .observed_state, step);
        observeOwned(&self.control, .appkit_content_view, native.content_view, 1, .cocoa_appkit, .observed_state, step);
        observeOwned(&self.control, .metal_layer, native.metal_layer, 1, .cocoa_appkit, .observed_state, step);
        observeOwned(&self.control, .presentation_sink, native.metal_layer, 1, .cocoa_appkit, .observed_state, step);
        observeOwned(&self.control, .metal_device, native.metal_device, 1, .metal_driver, .observed_state, step);

        observeStage(&self.control, .application_ready, native.application != 0, native.application_ready, native.application, 1, .observed_state, step);
        observeStage(&self.control, .window_ready, native.window != 0, native.window_ready, native.window, 1, .observed_state, step);
        observeStage(&self.control, .content_view_ready, native.content_view != 0, native.window_ready and native.content_view != 0, native.content_view, 1, .observed_state, step);
        observeStage(&self.control, .metal_layer_ready, native.metal_layer != 0, native.layer_attached and native.metal_layer != 0, native.metal_layer, 1, .observed_state, step);
        observeStage(&self.control, .metal_device_ready, native.metal_device != 0, native.metal_device != 0, native.metal_device, 1, .observed_state, step);
    }

    fn observeSdl(self: *Runtime, sdl: SdlSnapshot, step: u64) void {
        const generation = nonzero(sdl.binding_generation);
        if (sdl.event_loop != 0) {
            observeOwned(&self.control, .sdl_event_loop, sdl.event_loop, 1, .sdl, .observed_state, step);
            observeStage(&self.control, .sdl_ready, true, sdl.initialized, sdl.event_loop, 1, .intercepted_call, step);
        }
        if (sdl.window_binding != 0) {
            observeOwned(&self.control, .sdl_window_binding, sdl.window_binding, generation, .sdl, .intercepted_call, step);
            observeStage(&self.control, .sdl_window_bound, true, sdl.window_bound, sdl.window_binding, generation, .intercepted_call, step);
        }
        if (sdl.window_bound and sdl.cocoa_window != 0) {
            _ = self.control.observeResource(.{
                .resource = .appkit_window,
                .identity = sdl.cocoa_window,
                .generation = 1,
                .actor = .sdl,
                .authority = .borrower,
                .evidence = .completed_call,
                .step = step,
            });
        }
        if (sdl.window_bound and sdl.cocoa_content_view != 0) {
            _ = self.control.observeResource(.{
                .resource = .appkit_content_view,
                .identity = sdl.cocoa_content_view,
                .generation = 1,
                .actor = .sdl,
                .authority = .borrower,
                .evidence = .completed_call,
                .step = step,
            });
        }
    }

    fn observeRosetteVulkan(self: *Runtime, vk: VulkanSnapshot, step: u64) void {
        const generation = nonzero(vk.generation);
        observeOwned(&self.control, .rosette_vulkan_instance, vk.instance, generation, .rosette_runtime, .completed_call, step);
        observeOwned(&self.control, .rosette_vulkan_surface, vk.surface, generation, .rosette_runtime, .completed_call, step);
        observeOwned(&self.control, .rosette_vulkan_device, vk.device, generation, .rosette_runtime, .completed_call, step);
        observeOwned(&self.control, .rosette_vulkan_queue, vk.queue, generation, .rosette_runtime, .completed_call, step);
        observeOwned(&self.control, .rosette_vulkan_swapchain, vk.swapchain, generation, .rosette_runtime, .completed_call, step);
        if (vk.metal_layer != 0) {
            _ = self.control.observeResource(.{
                .resource = .metal_layer,
                .identity = vk.metal_layer,
                .generation = generation,
                .actor = .rosette_runtime,
                .authority = .borrower,
                .evidence = .completed_call,
                .step = step,
            });
        }
        observeVulkanStages(&self.control, vk, .rosette_runtime, step);
    }

    fn observeXeniaVulkan(self: *Runtime, vk: VulkanSnapshot, step: u64) void {
        const generation = nonzero(vk.generation);
        observeOwned(&self.control, .xenia_vulkan_instance, vk.instance, generation, .xenia_vulkan, .completed_call, step);
        observeOwned(&self.control, .xenia_vulkan_surface, vk.surface, generation, .xenia_vulkan, .completed_call, step);
        observeOwned(&self.control, .xenia_vulkan_device, vk.device, generation, .xenia_vulkan, .completed_call, step);
        observeOwned(&self.control, .xenia_vulkan_queue, vk.queue, generation, .xenia_vulkan, .completed_call, step);
        observeOwned(&self.control, .xenia_vulkan_swapchain, vk.swapchain, generation, .xenia_vulkan, .completed_call, step);
        observeVulkanStages(&self.control, vk, .xenia_vulkan, step);
        observeStage(&self.control, .xenia_vulkan_submission_seen, vk.submissions != 0, vk.submissions != 0, vk.queue, generation, .completed_call, step);
        observeStage(&self.control, .xenia_vulkan_present_seen, vk.presents != 0, vk.presents != 0, vk.swapchain, generation, .completed_call, step);
    }

    fn observeXenos(self: *Runtime, xenos: XenosSnapshot, step: u64) void {
        const ring_generation = nonzero(xenos.ring_generation);
        observeOwned(&self.control, .xenos_ring, xenos.ring, ring_generation, .guest_title, .intercepted_call, step);
        observeStage(&self.control, .xenos_ring_ready, xenos.ring != 0, xenos.ring != 0, xenos.ring, ring_generation, .intercepted_call, step);
        observeOwned(&self.control, .xenos_command_stream, xenos.command_stream, nonzero(xenos.command_generation), .xenia_host, .observed_state, step);
        observeOwned(&self.control, .xenos_render_target, xenos.render_target, nonzero(xenos.command_generation), .xenia_host, .observed_state, step);
        observeOwned(&self.control, .xenos_front_buffer, xenos.front_buffer, nonzero(xenos.command_generation), .guest_title, .observed_state, step);
        observeStage(
            &self.control,
            .xenos_render_target_ready,
            xenos.render_target_state,
            xenos.render_target_state and xenos.render_target_memory,
            xenos.render_target,
            nonzero(xenos.command_generation),
            .observed_state,
            step,
        );
        observeStage(&self.control, .guest_vdswap_entered, xenos.guest_vdswap_entries != 0, xenos.guest_vdswap_entries != 0, xenos.ring, ring_generation, .intercepted_call, step);
        observeStage(&self.control, .guest_xe_swap_encoded, xenos.guest_xe_swap_encoded, xenos.guest_xe_swap_encoded, xenos.command_stream, nonzero(xenos.command_generation), .observed_state, step);
        observeStage(&self.control, .authentic_xe_swap_consumed, xenos.authentic_xe_swap_consumed != 0, xenos.authentic_xe_swap_consumed != 0, xenos.command_stream, nonzero(xenos.command_generation), .completed_call, step);
        observeStage(&self.control, .issue_swap_entered, xenos.issue_swap_entries != 0, xenos.issue_swap_entries != 0, xenos.front_buffer, nonzero(xenos.command_generation), .intercepted_call, step);
    }

    fn observeCallbacks(self: *Runtime, callbacks: CallbackSnapshot, step: u64) void {
        if (callbacks.powerpc_address != 0) {
            observeOwned(&self.control, .powerpc_interrupt_callback, callbacks.powerpc_address, 1, .xenia_powerpc, .intercepted_call, step);
            observeStage(&self.control, .powerpc_callback_registered, true, callbacks.powerpc_registrations != 0, callbacks.powerpc_address, 1, .intercepted_call, step);
            observeStage(&self.control, .powerpc_callback_returned, callbacks.powerpc_returns != 0, callbacks.powerpc_returns != 0, callbacks.powerpc_address, 1, .completed_call, step);
        }
        if (callbacks.translated_x86_address != 0) {
            observeOwned(&self.control, .translated_x86_callback, callbacks.translated_x86_address, 1, .rosette_runtime, .intercepted_call, step);
        }
    }

    fn observeAggregateWork(self: *Runtime, source: Snapshot, run: u64) void {
        const xenos = source.xenos;
        self.claimDelta(
            &self.last_ring_publications,
            xenos.ring_publications,
            run,
            .guest_title,
            xenos.ring,
            nonzero(xenos.ring_generation),
            .ring_publication,
            source.step,
        );
        self.claimDelta(
            &self.last_powerpc_returns,
            source.callbacks.powerpc_returns,
            run,
            .xenia_powerpc,
            source.callbacks.powerpc_address,
            1,
            .callback_dispatch,
            source.step,
        );
        self.claimDelta(
            &self.last_x86_dispatches,
            source.callbacks.translated_x86_dispatches,
            run,
            .rosette_runtime,
            source.callbacks.translated_x86_address,
            1,
            .callback_dispatch,
            source.step,
        );
        self.claimDelta(
            &self.last_guest_vdswap_entries,
            xenos.guest_vdswap_entries,
            run,
            .guest_title,
            nonzero(xenos.ring),
            nonzero(xenos.ring_generation),
            .guest_swap_request,
            source.step,
        );
        self.claimDelta(
            &self.last_rosette_diagnostic_frames,
            source.rosette_vulkan.diagnostic_frames,
            run,
            .rosette_runtime,
            nonzero(source.rosette_vulkan.swapchain),
            nonzero(source.rosette_vulkan.generation),
            .native_present,
            source.step,
        );
        self.claimDelta(
            &self.last_rosette_host_frames,
            source.rosette_vulkan.host_frames,
            run,
            .xenia_host,
            nonzero(source.native.metal_layer),
            nonzero(source.rosette_vulkan.generation),
            .native_present,
            source.step,
        );
        self.claimDelta(
            &self.last_cocoa_diagnostic_frames,
            source.native.diagnostic_frames,
            run,
            .rosette_runtime,
            nonzero(source.native.metal_layer),
            1,
            .native_present,
            source.step,
        );
        self.claimDelta(
            &self.last_cocoa_guest_frames,
            source.native.guest_frames,
            run,
            .rosette_runtime,
            nonzero(source.native.metal_layer),
            2,
            .native_present,
            source.step,
        );
        self.claimDelta(
            &self.last_rosette_guest_frames,
            source.rosette_vulkan.guest_output_frames,
            run,
            .guest_title,
            nonzero(source.native.metal_layer),
            nonzero(source.rosette_vulkan.generation),
            .native_present,
            source.step,
        );
        self.claimDelta(
            &self.last_xenia_submissions,
            source.xenia_vulkan.submissions,
            run,
            .xenia_vulkan,
            source.xenia_vulkan.queue,
            nonzero(source.xenia_vulkan.generation),
            .pm4_batch,
            source.step,
        );
        self.claimDelta(
            &self.last_xenia_presents,
            source.xenia_vulkan.presents,
            run,
            .xenia_vulkan,
            source.xenia_vulkan.swapchain,
            nonzero(source.xenia_vulkan.generation),
            .native_present,
            source.step,
        );

        const diagnostic_frames = source.rosette_vulkan.diagnostic_frames +| source.native.diagnostic_frames;
        if (diagnostic_frames != 0) {
            const identity = syntheticIdentity(source.native.metal_layer, diagnostic_frames, 0xD1A6_0001);
            _ = self.control.observeResource(.{
                .resource = .diagnostic_frame,
                .identity = identity,
                .generation = diagnostic_frames,
                .actor = .rosette_runtime,
                .authority = .diagnostic_substitute,
                .evidence = .completed_call,
                .step = source.step,
            });
            _ = self.control.recordStage(
                .diagnostic_frame_presented,
                .ready,
                .rosette_runtime,
                .completed_call,
                identity,
                diagnostic_frames,
                source.step,
            );
        }
    }

    fn updatePresenterLease(self: *Runtime, source: Snapshot, step: u64) void {
        const xenia_ready = source.xenia_vulkan.presenterReady() and source.xenia_vulkan.presents != 0;
        const requested_holder: Domain = if (xenia_ready)
            .xenia_vulkan
        else if (source.rosette_vulkan.presenterReady())
            .rosette_runtime
        else if (self.control.policy == .verified_guest_fallback and
            source.metal_guest_copy_ready and source.latest_frame != null)
            .rosette_runtime
        else
            .unknown;
        const requested_generation = if (requested_holder == .xenia_vulkan)
            nonzero(source.xenia_vulkan.generation)
        else if (!source.rosette_vulkan.presenterReady() and source.latest_frame != null)
            nonzero(source.latest_frame.?.generation)
        else
            nonzero(source.rosette_vulkan.generation);

        if (requested_holder == .unknown) return;
        if (self.control.presenter.active and
            (self.control.presenter.holder != requested_holder or self.control.presenter.generation != requested_generation))
        {
            _ = self.control.releasePresenter(self.control.presenter.holder, self.control.presenter.generation);
        }
        _ = self.control.acquirePresenter(requested_holder, requested_generation, step);
    }

    /// Rosette's newest diagnostic presentation, once, at the moment its
    /// counter advances.
    ///
    /// Returns null when nothing new was presented, when the window has no
    /// drawable facts to describe the frame with, or when a guest frame is
    /// available — a guest frame always takes the custody slot, because that is
    /// the frame anybody reading the ledger is looking for.
    fn diagnosticFrame(self: *Runtime, source: Snapshot) ?FrameSnapshot {
        const presented = source.rosette_vulkan.diagnostic_frames +| source.native.diagnostic_frames;
        if (presented == 0 or presented <= self.last_diagnostic_custody) return null;
        if (source.native.drawable_width == 0 or source.native.drawable_height == 0) return null;
        const format = PixelFormat.fromVulkan(source.native.drawable_format);
        if (format == .unknown) return null;
        // Whichever presenter drew it names the sink. A zero swapchain means the
        // Vulkan presenter never came up and the clear went through Metal.
        const through_vulkan = source.rosette_vulkan.diagnostic_frames != 0 and
            source.rosette_vulkan.swapchain != 0;
        const sink = if (through_vulkan) source.rosette_vulkan.swapchain else source.native.metal_layer;
        if (sink == 0) return null;
        // Every presentation since the last reconcile, not just the newest one.
        // Crediting one frame per checkpoint left the window ahead of custody
        // by however many clears the presenter fitted in between, and a window
        // that is ahead of custody by even one frame has shown a picture nobody
        // can attribute.
        const covered = presented - self.last_diagnostic_custody;
        self.last_diagnostic_custody = presented;
        return .{
            .source_address = sink,
            .source_length = 0,
            .width = source.native.drawable_width,
            .height = source.native.drawable_height,
            .row_pitch = 0,
            .format = format,
            .origin = .diagnostic,
            .generation = if (through_vulkan) nonzero(source.rosette_vulkan.generation) else 1,
            .serial = presented,
            .content_digest = 0,
            .guest_swap_observed = false,
            // The counter only advances when a present completed, so the frame
            // is consumed by construction.
            .consumed = true,
            .presentations_covered = covered,
        };
    }

    fn reconcileFrame(
        self: *Runtime,
        frame: FrameSnapshot,
        run: u64,
        route: Route,
        step: u64,
        frame_class: *contract.FrameClass,
    ) frame_handoff.OfferResult {
        const descriptor = frame.descriptor(run);
        const identity = descriptor.identity;
        const resource = frame.origin.resource();
        const producer = frame.origin.domain();
        const authority: contract.Authority = if (frame.origin == .diagnostic) .diagnostic_substitute else .canonical_owner;
        _ = self.control.observeResource(.{
            .resource = resource,
            .identity = identity.source,
            .generation = identity.serial,
            .actor = producer,
            .authority = authority,
            .evidence = .completed_call,
            .step = step,
        });
        if (frame.origin.offeredStage()) |stage| {
            _ = self.control.recordStage(stage, .ready, producer, .completed_call, identity.source, identity.serial, step);
        }

        const offered = self.frames.offer(descriptor, step);
        if (offered == .accepted) {
            self.claimFrame(descriptor, step);
        }
        const entry = self.frames.lookup(identity) orelse return offered;
        frame_class.* = entry.frame_class;
        if (entry.state == .offered) _ = self.frames.validateFrame(identity, .rosette_runtime, step);

        if (entry.state == .validated) {
            const custody = self.control.resource(resource).custodian;
            if (custody != .rosette_runtime) {
                if (self.control.beginHandoff(resource, identity.source, identity.serial, producer, .rosette_runtime, step)) |token| {
                    _ = self.control.acceptHandoff(token, .rosette_runtime, step);
                    _ = self.control.completeHandoff(token, .rosette_runtime, step);
                }
            }
            if (self.control.resource(resource).custodian == .rosette_runtime)
                _ = self.frames.acquire(identity, .rosette_runtime, step);
        }
        if (entry.state == .acquired) _ = self.frames.submit(identity, .rosette_runtime, step);
        if (entry.state == .submitted and frame.consumed) {
            frame_class.* = self.frames.present(identity, .rosette_runtime, true, step);
            const presentation_stage: ?contract.Stage = switch (frame_class.*) {
                .diagnostic_host => .diagnostic_frame_presented,
                .guest_pixels_host_cadence, .authentic_guest_present => switch (route) {
                    .cocoa_metal_guest_copy => .guest_frame_presented_metal,
                    .rosette_vulkan_guest_copy => .guest_frame_presented_vulkan,
                    else => null,
                },
                else => null,
            };
            if (presentation_stage) |stage| {
                _ = self.control.recordStage(stage, .ready, .rosette_runtime, .completed_call, identity.source, identity.serial, step);
            }
        }
        if (entry.state == .presented) {
            _ = self.frames.release(identity, .rosette_runtime);
            if (producer != .rosette_runtime and self.control.resource(resource).custodian == .rosette_runtime) {
                if (self.control.beginHandoff(resource, identity.source, identity.serial, .rosette_runtime, producer, step)) |token| {
                    _ = self.control.acceptHandoff(token, producer, step);
                    _ = self.control.completeHandoff(token, producer, step);
                }
            }
        }
        return offered;
    }

    fn claimFrame(self: *Runtime, descriptor: frame_handoff.Descriptor, step: u64) void {
        // `guest_frame` credit means the guest produced a frame. A host clear
        // taking custody is a fact about the window, not about the title, and
        // crediting it here would put Rosette's own output into the counter a
        // reader consults to find out whether the title ever drew anything.
        // The native-present counter already accounts for it.
        if (!descriptor.guest_pixels) return;
        const digest = if (descriptor.content_digest != 0)
            descriptor.content_digest
        else
            syntheticIdentity(
                descriptor.source_address,
                descriptor.source_length ^ @as(u64, descriptor.width) << 32 ^ descriptor.height,
                descriptor.identity.serial,
            );
        _ = self.credits.claim(.{
            .key = .{
                .run = descriptor.identity.run,
                .producer = descriptor.producer,
                .stream = descriptor.source_address,
                .generation = descriptor.identity.generation,
                .sequence = descriptor.identity.serial,
                .kind = .guest_frame,
            },
            .units = 1,
            .payload_digest = nonzero(digest),
            .step = step,
        });
        self.last_frame_serial = @max(self.last_frame_serial, descriptor.identity.serial);
    }

    fn claimDelta(
        self: *Runtime,
        previous: *u64,
        current: u64,
        run: u64,
        producer: Domain,
        stream: u64,
        generation: u64,
        kind: work_credit.Kind,
        step: u64,
    ) void {
        if (current < previous.*) previous.* = 0;
        if (current == previous.*) return;
        const units = current - previous.*;
        previous.* = current;
        if (stream == 0 or units == 0) return;
        const digest = syntheticIdentity(stream, current, @intFromEnum(kind) + 1);
        _ = self.credits.claim(.{
            .key = .{
                .run = run,
                .producer = producer,
                .stream = stream,
                .generation = nonzero(generation),
                .sequence = current,
                .kind = kind,
            },
            .units = units,
            .payload_digest = nonzero(digest),
            .step = step,
        });
    }
};

fn observeOwned(
    plane: *control_plane.ControlPlane,
    resource: contract.Resource,
    identity: u64,
    generation: u64,
    actor: Domain,
    evidence: contract.Evidence,
    step: u64,
) void {
    if (identity == 0) return;
    _ = plane.observeResource(.{
        .resource = resource,
        .identity = identity,
        .generation = nonzero(generation),
        .actor = actor,
        .authority = .canonical_owner,
        .evidence = evidence,
        .ready = true,
        .step = step,
    });
}

fn observeStage(
    plane: *control_plane.ControlPlane,
    stage: contract.Stage,
    observed: bool,
    ready: bool,
    identity: u64,
    generation: u64,
    evidence: contract.Evidence,
    step: u64,
) void {
    if (!observed) return;
    _ = plane.recordStage(
        stage,
        if (ready) .ready else .observed,
        stage.expectedOwner(),
        evidence,
        identity,
        nonzero(generation),
        step,
    );
}

fn observeVulkanStages(
    plane: *control_plane.ControlPlane,
    vk: VulkanSnapshot,
    owner: Domain,
    step: u64,
) void {
    const generation = nonzero(vk.generation);
    const stages = if (owner == .rosette_runtime)
        [_]contract.Stage{
            .rosette_vulkan_instance_ready,
            .rosette_vulkan_surface_ready,
            .rosette_vulkan_device_ready,
            .rosette_vulkan_queue_ready,
            .rosette_vulkan_swapchain_ready,
        }
    else
        [_]contract.Stage{
            .xenia_vulkan_instance_ready,
            .xenia_vulkan_surface_ready,
            .xenia_vulkan_device_ready,
            .xenia_vulkan_queue_ready,
            .xenia_vulkan_swapchain_ready,
        };
    const identities = [_]u64{ vk.instance, vk.surface, vk.device, vk.queue, vk.swapchain };
    for (stages, identities) |stage, identity| {
        if (identity == 0) continue;
        _ = plane.recordStage(stage, .ready, owner, .completed_call, identity, generation, step);
    }
}

fn syntheticIdentity(first: u64, second: u64, discriminator: u64) u64 {
    var hash: u64 = 14_695_981_039_346_656_037;
    hash = mix(hash, first);
    hash = mix(hash, second);
    hash = mix(hash, discriminator);
    return nonzero(hash);
}

fn mix(hash: u64, value: u64) u64 {
    return (hash ^ value) *% 1_099_511_628_211;
}

fn nonzero(value: u64) u64 {
    return if (value == 0) 1 else value;
}

fn completeSnapshot() Snapshot {
    return .{
        .run = 7,
        .step = 100,
        .native = .{
            .application = 0x100,
            .window = 0x200,
            .content_view = 0x300,
            .metal_layer = 0x400,
            .metal_device = 0x500,
            .application_ready = true,
            .window_ready = true,
            .layer_attached = true,
            .drawable_width = 1280,
            .drawable_height = 720,
            .drawable_format = 44,
        },
        .sdl = .{
            .event_loop = 0x600,
            .window_binding = 0x601,
            .binding_generation = 2,
            .cocoa_window = 0x200,
            .cocoa_content_view = 0x300,
            .initialized = true,
            .window_bound = true,
        },
        .rosette_vulkan = .{
            .metal_layer = 0x400,
            .instance = 0x701,
            .surface = 0x702,
            .device = 0x703,
            .queue = 0x704,
            .swapchain = 0x705,
            .generation = 3,
            .ready = true,
        },
        .xenos = .{
            .ring = 0x1FC0_0000,
            .ring_generation = 2,
            .ring_publications = 1,
            .command_stream = 0xABCD,
            .command_generation = 2,
            .batches = 1,
            .draws = 24,
        },
    };
}

test "one AppKit layer is borrowed by Rosette without changing owner" {
    var runtime = Runtime{};
    runtime.configure(.observe_only);
    const result = runtime.reconcile(completeSnapshot());
    try std.testing.expect(!result.ownership_conflict);
    const layer = runtime.control.resource(.metal_layer);
    try std.testing.expectEqual(Domain.cocoa_appkit, layer.canonical_owner);
    try std.testing.expect(layer.borrowedBy(.rosette_runtime));
    try std.testing.expectEqual(@as(u64, 0x400), layer.identity);
    const window = runtime.control.resource(.appkit_window);
    const view = runtime.control.resource(.appkit_content_view);
    try std.testing.expectEqual(Domain.cocoa_appkit, window.canonical_owner);
    try std.testing.expect(window.borrowedBy(.sdl));
    try std.testing.expect(view.borrowedBy(.sdl));
}

test "SDL binding to a different Cocoa window is quarantined" {
    var runtime = Runtime{};
    var snapshot = completeSnapshot();
    snapshot.sdl.cocoa_window = 0xBAD;
    const result = runtime.reconcile(snapshot);
    try std.testing.expect(result.ownership_conflict);
    try std.testing.expectEqual(Route.quarantine_conflict, result.route);
}

test "a conflicting presenter layer quarantines routing" {
    var runtime = Runtime{};
    var snapshot = completeSnapshot();
    snapshot.rosette_vulkan.metal_layer = 0xBAD;
    const result = runtime.reconcile(snapshot);
    try std.testing.expect(result.ownership_conflict);
    try std.testing.expectEqual(Route.quarantine_conflict, result.route);
}

test "a consumed Xenia host frame records custody without authentic swap" {
    var runtime = Runtime{};
    runtime.configure(.verified_guest_fallback);
    var snapshot = completeSnapshot();
    snapshot.latest_frame = .{
        .source_address = 0x8000,
        .source_length = 640 * 480 * 4,
        .width = 640,
        .height = 480,
        .row_pitch = 640 * 4,
        .format = .bgra8_unorm,
        .origin = .xenia_host,
        .generation = 2,
        .serial = 1,
        .content_digest = 0xA11C_E001,
        .consumed = true,
    };
    const result = runtime.reconcile(snapshot);
    try std.testing.expectEqual(Route.rosette_vulkan_guest_copy, result.route);
    try std.testing.expectEqual(contract.FrameClass.guest_pixels_host_cadence, result.frame_class);
    try std.testing.expect(!result.frame_class.closesAuthenticSwap());
    try std.testing.expectEqual(@as(u64, 1), runtime.frames.summary().presented);
    try std.testing.expect(runtime.control.handoffs_completed >= 2);
}

test "direct Metal delivery is pending once and remains classified after completion" {
    var runtime = Runtime{};
    runtime.configure(.verified_guest_fallback);
    var snapshot = completeSnapshot();
    snapshot.rosette_vulkan = .{};
    snapshot.metal_guest_copy_ready = true;
    snapshot.latest_frame = .{
        .source_address = 0x9000,
        .source_length = 320 * 240 * 4,
        .width = 320,
        .height = 240,
        .row_pitch = 320 * 4,
        .format = .bgra8_unorm,
        .origin = .xenia_host,
        .generation = 4,
        .serial = 9,
        .content_digest = 0xC0C0_A001,
    };

    const offered = runtime.reconcile(snapshot);
    try std.testing.expectEqual(Route.cocoa_metal_guest_copy, offered.route);
    try std.testing.expect(offered.frame_delivery_pending);
    try std.testing.expectEqual(contract.FrameClass.none, offered.frame_class);

    snapshot.latest_frame.?.consumed = true;
    const completed = runtime.reconcile(snapshot);
    try std.testing.expectEqual(Route.cocoa_metal_guest_copy, completed.route);
    try std.testing.expect(!completed.frame_delivery_pending);
    try std.testing.expectEqual(contract.FrameClass.guest_pixels_host_cadence, completed.frame_class);

    const retained = runtime.reconcile(snapshot);
    try std.testing.expect(!retained.frame_delivery_pending);
    try std.testing.expectEqual(contract.FrameClass.guest_pixels_host_cadence, retained.frame_class);
    try std.testing.expectEqual(@as(u64, 1), runtime.frames.presented);
}

test "reconciling one snapshot repeatedly does not invent new work" {
    var runtime = Runtime{};
    const snapshot = completeSnapshot();
    _ = runtime.reconcile(snapshot);
    const first = runtime.credits.summary();
    var index: usize = 0;
    while (index < 147) : (index += 1) _ = runtime.reconcile(snapshot);
    const repeated = runtime.credits.summary();
    try std.testing.expectEqual(first.unique_claims, repeated.unique_claims);
    try std.testing.expectEqual(first.credited_units, repeated.credited_units);
    try std.testing.expectEqual(@as(u64, 1), repeated.units(.ring_publication));
}

test "a real Xenia present takes the presenter lease explicitly" {
    var runtime = Runtime{};
    var snapshot = completeSnapshot();
    _ = runtime.reconcile(snapshot);
    try std.testing.expectEqual(Domain.rosette_runtime, runtime.control.presenter.holder);
    snapshot.xenia_vulkan = .{
        .instance = 0x901,
        .surface = 0x902,
        .device = 0x903,
        .queue = 0x904,
        .swapchain = 0x905,
        .generation = 4,
        .ready = true,
        .submissions = 1,
        .presents = 1,
    };
    const result = runtime.reconcile(snapshot);
    try std.testing.expectEqual(Route.xenia_native, result.route);
    try std.testing.expectEqual(Domain.xenia_vulkan, runtime.control.presenter.holder);
    try std.testing.expectEqual(@as(u64, 1), runtime.control.presenter.releases);
    try std.testing.expect(!runtime.control.hasConflict());
}

test "PowerPC and translated x86 callback credits remain separate" {
    var runtime = Runtime{};
    var snapshot = completeSnapshot();
    snapshot.callbacks = .{
        .powerpc_address = 0x8219_51F8,
        .powerpc_registrations = 1,
        .powerpc_returns = 4,
        .translated_x86_address = 0x1234,
        .translated_x86_registrations = 1,
        .translated_x86_dispatches = 2,
    };
    _ = runtime.reconcile(snapshot);
    try std.testing.expectEqual(@as(u64, 6), runtime.credits.units(.callback_dispatch));
    try std.testing.expect(!contract.canInvoke(.translated_x86, .{
        .address = snapshot.callbacks.powerpc_address,
        .space = .xenia_powerpc,
        .owner = .xenia_powerpc,
        .evidence = .completed_call,
    }));
}

test "Rosette's own diagnostic presentations take custody" {
    var runtime = Runtime{};
    runtime.configure(.verified_guest_fallback);
    var snapshot = completeSnapshot();
    snapshot.rosette_vulkan.diagnostic_frames = 3;
    const result = runtime.reconcile(snapshot);
    try std.testing.expect(result.diagnostic_custody);
    try std.testing.expectEqual(frame_handoff.OfferResult.accepted, result.frame_offer);
    try std.testing.expectEqual(contract.FrameClass.diagnostic_host, result.frame_class);
    const summary = runtime.frames.summary();
    try std.testing.expectEqual(@as(u64, 1), summary.offered);
    try std.testing.expectEqual(@as(u64, 1), summary.presented);
    try std.testing.expectEqual(@as(u64, 1), summary.diagnostic);
    try std.testing.expectEqual(@as(u64, 0), summary.authentic_guest);
    try std.testing.expectEqual(@as(u64, 0), summary.guest_pixels_host_cadence);
    try std.testing.expectEqual(@as(u64, 0), summary.rejected);
}

test "a diagnostic frame is credited once however often the counter is re-read" {
    var runtime = Runtime{};
    runtime.configure(.verified_guest_fallback);
    var snapshot = completeSnapshot();
    snapshot.rosette_vulkan.diagnostic_frames = 5;
    _ = runtime.reconcile(snapshot);
    var repeat: usize = 0;
    while (repeat < 8) : (repeat += 1) {
        const result = runtime.reconcile(snapshot);
        try std.testing.expect(!result.diagnostic_custody);
    }
    try std.testing.expectEqual(@as(u64, 1), runtime.frames.summary().presented);
    snapshot.rosette_vulkan.diagnostic_frames = 6;
    _ = runtime.reconcile(snapshot);
    try std.testing.expectEqual(@as(u64, 2), runtime.frames.summary().presented);
}

test "a diagnostic frame never earns guest-frame work credit" {
    var runtime = Runtime{};
    runtime.configure(.verified_guest_fallback);
    var snapshot = completeSnapshot();
    snapshot.rosette_vulkan.diagnostic_frames = 2;
    _ = runtime.reconcile(snapshot);
    try std.testing.expectEqual(@as(u64, 0), runtime.credits.units(.guest_frame));
    try std.testing.expectEqual(@as(u64, 1), runtime.frames.summary().diagnostic);
}

test "a guest frame always takes the custody slot over a diagnostic one" {
    var runtime = Runtime{};
    runtime.configure(.verified_guest_fallback);
    var snapshot = completeSnapshot();
    snapshot.rosette_vulkan.diagnostic_frames = 4;
    snapshot.latest_frame = .{
        .source_address = 0x8000,
        .source_length = 640 * 480 * 4,
        .width = 640,
        .height = 480,
        .row_pitch = 640 * 4,
        .format = .bgra8_unorm,
        .origin = .xenia_host,
        .serial = 11,
        .content_digest = 0xFEED,
        .consumed = true,
    };
    const result = runtime.reconcile(snapshot);
    try std.testing.expect(!result.diagnostic_custody);
    try std.testing.expectEqual(@as(u64, 1), runtime.frames.summary().guest_pixels_host_cadence);
    try std.testing.expectEqual(@as(u64, 0), runtime.frames.summary().diagnostic);
}

test "a window with no drawable facts refuses custody rather than inventing them" {
    var runtime = Runtime{};
    runtime.configure(.verified_guest_fallback);
    var snapshot = completeSnapshot();
    snapshot.rosette_vulkan.diagnostic_frames = 3;
    snapshot.native.drawable_format = 0;
    try std.testing.expect(!runtime.reconcile(snapshot).diagnostic_custody);
    snapshot.native.drawable_format = 44;
    snapshot.native.drawable_width = 0;
    try std.testing.expect(!runtime.reconcile(snapshot).diagnostic_custody);
    try std.testing.expectEqual(@as(u64, 0), runtime.frames.summary().offered);
}

test "custody accounts for every presentation, not one per checkpoint" {
    var runtime = Runtime{};
    runtime.configure(.verified_guest_fallback);
    var snapshot = completeSnapshot();
    // Three frames went up between this reconcile and the last.
    snapshot.rosette_vulkan.diagnostic_frames = 3;
    _ = runtime.reconcile(snapshot);
    try std.testing.expectEqual(@as(u64, 1), runtime.frames.summary().presented);
    try std.testing.expectEqual(@as(u64, 3), runtime.frames.summary().presentations_covered);
    // Four more before the next one.
    snapshot.rosette_vulkan.diagnostic_frames = 7;
    _ = runtime.reconcile(snapshot);
    try std.testing.expectEqual(@as(u64, 2), runtime.frames.summary().presented);
    try std.testing.expectEqual(@as(u64, 7), runtime.frames.summary().presentations_covered);
}

test "coverage never runs behind what the window showed" {
    var runtime = Runtime{};
    runtime.configure(.verified_guest_fallback);
    var snapshot = completeSnapshot();
    var presented: u64 = 0;
    var checkpoint: u64 = 0;
    while (checkpoint < 20) : (checkpoint += 1) {
        // An irregular cadence, exactly as a real presenter produces.
        presented += 1 + (checkpoint % 3);
        snapshot.rosette_vulkan.diagnostic_frames = presented;
        snapshot.step = checkpoint * 1000;
        _ = runtime.reconcile(snapshot);
        try std.testing.expectEqual(presented, runtime.frames.summary().presentations_covered);
    }
}
