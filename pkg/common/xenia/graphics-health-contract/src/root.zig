//! Immutable cross-layer graphics health facts.
//!
//! This package is the vocabulary for the entire route from a translated
//! title to a visible frame.  It deliberately contains no pointers, handles,
//! driver calls or mutable counters.  Those belong to `lib`; this package
//! answers the compile-time questions that must not be re-invented by each
//! observer:
//!
//! * which stages exist;
//! * which owner is allowed to make a stage true;
//! * which stages form an alternative path to a frame; and
//! * what a missing stage means.
//!
//! The paths are alternatives, not one giant linear chain.  Xenia may produce
//! a console frame through Xenos/PM4/VdSwap, while Rosette's own Vulkan
//! presenter may be alive at the same time.  Treating those as one chain is
//! how a diagnostic clear gets mistaken for game output.

const std = @import("std");

pub const schema_version: u16 = 1;

pub const Owner = enum(u8) {
    rosette_harness,
    xenia_host,
    guest_title,
    host_driver,
    observer,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .rosette_harness => "rosette_harness",
            .xenia_host => "xenia_host",
            .guest_title => "guest_title",
            .host_driver => "host_driver",
            .observer => "observer",
        };
    }

    pub fn canBeDrivenByRosette(self: Owner) bool {
        return self == .rosette_harness;
    }
};

pub const Layer = enum(u8) {
    process,
    kernel,
    scheduling,
    host_window,
    host_vulkan,
    xenos,
    pm4,
    vdswap,
    presentation,

    pub fn label(self: Layer) []const u8 {
        return switch (self) {
            .process => "process",
            .kernel => "kernel",
            .scheduling => "scheduling",
            .host_window => "host_window",
            .host_vulkan => "host_vulkan",
            .xenos => "xenos",
            .pm4 => "pm4",
            .vdswap => "vdswap",
            .presentation => "presentation",
        };
    }
};

/// A stage is an observable fact, not an optimistic capability.  For
/// example, `guest_vulkan_commands_forwarded` means that a real guest call
/// reached a native driver entry point; the existence of a plausible handle
/// does not satisfy it.
pub const Stage = enum(u8) {
    application_started,
    guest_image_mapped,
    guest_scheduler_running,
    kernel_graphics_exports_resolved,
    kernel_graphics_variables_populated,

    native_application_ready,
    native_window_ready,
    native_layer_attached,
    vulkan_loader_resolved,
    vulkan_instance_ready,
    vulkan_surface_ready,
    physical_adapter_ready,
    logical_device_ready,
    graphics_queue_ready,
    swapchain_ready,
    frame_resources_ready,

    guest_vulkan_activity_observed,
    guest_vulkan_commands_forwarded,
    guest_vulkan_submission_forwarded,

    xenos_engines_initialized,
    xenos_interrupt_callback_registered,
    xenos_ring_initialized,
    ring_publication_observed,
    ring_geometry_observed,
    pm4_stream_observed,
    pm4_stream_validated,
    pm4_indirects_resolved,
    pm4_state_programmed,
    draw_submitted,
    draw_consumed,
    render_target_state_observed,
    render_target_memory_observed,
    draw_completion_signaled,
    draw_completion_dispatched,

    guest_wait_progressed,
    guest_producer_progressed,
    guest_vdswap_entered,
    guest_swap_encoded,
    authentic_swap_consumed,
    issue_swap_entered,
    guest_output_refreshed,
    native_present_completed,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .application_started => "application started",
            .guest_image_mapped => "guest image mapped",
            .guest_scheduler_running => "guest scheduler running",
            .kernel_graphics_exports_resolved => "kernel graphics exports resolved",
            .kernel_graphics_variables_populated => "kernel graphics variables populated",
            .native_application_ready => "native NSApplication ready",
            .native_window_ready => "native NSWindow ready",
            .native_layer_attached => "CAMetalLayer attached",
            .vulkan_loader_resolved => "Vulkan loader resolved",
            .vulkan_instance_ready => "Vulkan instance ready",
            .vulkan_surface_ready => "Vulkan surface ready",
            .physical_adapter_ready => "physical adapter selected",
            .logical_device_ready => "logical device ready",
            .graphics_queue_ready => "graphics queue ready",
            .swapchain_ready => "swapchain ready",
            .frame_resources_ready => "frame resources ready",
            .guest_vulkan_activity_observed => "guest Vulkan activity observed",
            .guest_vulkan_commands_forwarded => "guest Vulkan commands forwarded",
            .guest_vulkan_submission_forwarded => "guest Vulkan submission forwarded",
            .xenos_engines_initialized => "Xenos engines initialized",
            .xenos_interrupt_callback_registered => "Xenos interrupt callback registered",
            .xenos_ring_initialized => "Xenos ring initialized",
            .ring_publication_observed => "ring publication observed",
            .ring_geometry_observed => "ring geometry observed",
            .pm4_stream_observed => "PM4 stream observed",
            .pm4_stream_validated => "PM4 stream validated",
            .pm4_indirects_resolved => "PM4 indirect buffers resolved",
            .pm4_state_programmed => "PM4 state programmed",
            .draw_submitted => "draw submitted",
            .draw_consumed => "draw consumed",
            .render_target_state_observed => "render-target state observed",
            .render_target_memory_observed => "render-target memory observed",
            .draw_completion_signaled => "draw completion signaled",
            .draw_completion_dispatched => "draw completion dispatched",
            .guest_wait_progressed => "guest wait/signal progressed",
            .guest_producer_progressed => "guest producer progressed",
            .guest_vdswap_entered => "guest VdSwap entered",
            .guest_swap_encoded => "guest XE_SWAP encoded",
            .authentic_swap_consumed => "authentic XE_SWAP consumed",
            .issue_swap_entered => "IssueSwap entered",
            .guest_output_refreshed => "guest output refreshed",
            .native_present_completed => "native presentation completed",
        };
    }

    pub fn owner(self: Stage) Owner {
        return switch (self) {
            .application_started,
            .guest_image_mapped,
            .guest_scheduler_running,
            => .observer,
            .kernel_graphics_exports_resolved,
            .kernel_graphics_variables_populated,
            => .xenia_host,
            .native_application_ready,
            .native_window_ready,
            .native_layer_attached,
            .vulkan_loader_resolved,
            .vulkan_instance_ready,
            .vulkan_surface_ready,
            => .rosette_harness,
            .physical_adapter_ready,
            .logical_device_ready,
            .graphics_queue_ready,
            .swapchain_ready,
            .frame_resources_ready,
            .guest_vulkan_commands_forwarded,
            .guest_vulkan_submission_forwarded,
            .native_present_completed,
            => .host_driver,
            .guest_vulkan_activity_observed,
            .xenos_engines_initialized,
            .xenos_interrupt_callback_registered,
            .xenos_ring_initialized,
            .ring_publication_observed,
            .ring_geometry_observed,
            .pm4_stream_observed,
            .pm4_stream_validated,
            .pm4_indirects_resolved,
            .pm4_state_programmed,
            .draw_submitted,
            .draw_consumed,
            .render_target_state_observed,
            .render_target_memory_observed,
            .draw_completion_signaled,
            .draw_completion_dispatched,
            => .xenia_host,
            .guest_wait_progressed,
            .guest_producer_progressed,
            .guest_vdswap_entered,
            .guest_swap_encoded,
            .authentic_swap_consumed,
            .issue_swap_entered,
            .guest_output_refreshed,
            => .guest_title,
        };
    }

    pub fn layer(self: Stage) Layer {
        return switch (self) {
            .application_started, .guest_image_mapped => .process,
            .guest_scheduler_running, .guest_wait_progressed, .guest_producer_progressed => .scheduling,
            .kernel_graphics_exports_resolved, .kernel_graphics_variables_populated => .kernel,
            .native_application_ready, .native_window_ready, .native_layer_attached => .host_window,
            .vulkan_loader_resolved,
            .vulkan_instance_ready,
            .vulkan_surface_ready,
            .physical_adapter_ready,
            .logical_device_ready,
            .graphics_queue_ready,
            .swapchain_ready,
            .frame_resources_ready,
            .guest_vulkan_activity_observed,
            .guest_vulkan_commands_forwarded,
            .guest_vulkan_submission_forwarded,
            => .host_vulkan,
            .xenos_engines_initialized,
            .xenos_interrupt_callback_registered,
            .xenos_ring_initialized,
            .ring_publication_observed,
            .ring_geometry_observed,
            => .xenos,
            .pm4_stream_observed,
            .pm4_stream_validated,
            .pm4_indirects_resolved,
            .pm4_state_programmed,
            .draw_submitted,
            .draw_consumed,
            .render_target_state_observed,
            .render_target_memory_observed,
            .draw_completion_signaled,
            .draw_completion_dispatched,
            => .pm4,
            .guest_vdswap_entered,
            .guest_swap_encoded,
            .authentic_swap_consumed,
            .issue_swap_entered,
            => .vdswap,
            .guest_output_refreshed, .native_present_completed => .presentation,
        };
    }

    pub fn guidance(self: Stage) []const u8 {
        return switch (self) {
            .application_started => "the process has not established a run identity",
            .guest_image_mapped => "the translated guest image is not mapped or has not executed",
            .guest_scheduler_running => "no guest scheduling evidence exists; inspect the thread runtime before GPU code",
            .kernel_graphics_exports_resolved => "the Xenia graphics export surface is incomplete or not bound",
            .kernel_graphics_variables_populated => "a graphics kernel variable is unresolved through its slot and storage",
            .native_application_ready => "Rosette has not established the Cocoa application before presenting",
            .native_window_ready => "Rosette has no native window to receive a surface",
            .native_layer_attached => "the window has no CAMetalLayer attachment",
            .vulkan_loader_resolved => "the Vulkan loader entry point is unavailable",
            .vulkan_instance_ready => "the native Vulkan instance was not created",
            .vulkan_surface_ready => "the CAMetalLayer could not become a Vulkan surface",
            .physical_adapter_ready => "no physical adapter was proven for this surface",
            .logical_device_ready => "the host rejected or never created a logical device",
            .graphics_queue_ready => "no native graphics queue was selected",
            .swapchain_ready => "surface capabilities did not produce a usable swapchain",
            .frame_resources_ready => "command buffers, semaphores or fences are incomplete",
            .guest_vulkan_activity_observed => "the title has not exercised its Vulkan path",
            .guest_vulkan_commands_forwarded => "Vulkan calls were observed without a native command mapping",
            .guest_vulkan_submission_forwarded => "guest commands did not reach a native queue submission",
            .xenos_engines_initialized => "the title/emulator has not initialized the Xenos engines",
            .xenos_interrupt_callback_registered => "the guest callback boundary is absent",
            .xenos_ring_initialized => "the Xenos ring geometry is not established",
            .ring_publication_observed => "no guest-owned ring publication has been proven",
            .ring_geometry_observed => "a publication exists without a trusted read/write geometry",
            .pm4_stream_observed => "no PM4 dword stream is readable in the selected projection",
            .pm4_stream_validated => "PM4 framing or bounds validation has not succeeded",
            .pm4_indirects_resolved => "an indirect buffer is unresolved, truncated or cyclic",
            .pm4_state_programmed => "the command processor consumed no state-programming evidence",
            .draw_submitted => "no draw packet was found in the submitted stream",
            .draw_consumed => "the command processor did not consume a draw",
            .render_target_state_observed => "no color/depth target register state is known",
            .render_target_memory_observed => "target registers exist without readable EDRAM/resolved memory",
            .draw_completion_signaled => "draw completion was not queued by the Xenos runtime",
            .draw_completion_dispatched => "completion was queued but did not reach the guest callback",
            .guest_wait_progressed => "wait/signal activity exists without forward progress",
            .guest_producer_progressed => "the producer stopped advancing after its last graphics boundary",
            .guest_vdswap_entered => "the title has not entered VdSwap; do not synthesize the guest decision",
            .guest_swap_encoded => "VdSwap did not encode a guest-origin XE_SWAP packet",
            .authentic_swap_consumed => "a readable packet is not yet authentic command-processor consumption",
            .issue_swap_entered => "Xenia did not enter its IssueSwap boundary",
            .guest_output_refreshed => "the consumed frame did not refresh guest output",
            .native_present_completed => "guest output did not complete a native presentation",
        };
    }
};

pub const stage_count: usize = @typeInfo(Stage).@"enum".fields.len;

pub const Path = enum(u8) {
    host_presenter,
    guest_vulkan,
    xenos_pm4,
    vdswap,
    scheduler,

    pub fn label(self: Path) []const u8 {
        return switch (self) {
            .host_presenter => "host_presenter",
            .guest_vulkan => "guest_vulkan",
            .xenos_pm4 => "xenos_pm4",
            .vdswap => "vdswap",
            .scheduler => "scheduler",
        };
    }
};

pub const host_presenter_path = [_]Stage{
    .application_started,
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

pub const guest_vulkan_path = [_]Stage{
    .guest_image_mapped,
    .guest_vulkan_activity_observed,
    .guest_vulkan_commands_forwarded,
    .guest_vulkan_submission_forwarded,
};

pub const xenos_pm4_path = [_]Stage{
    .guest_image_mapped,
    .kernel_graphics_exports_resolved,
    .kernel_graphics_variables_populated,
    .xenos_engines_initialized,
    .xenos_interrupt_callback_registered,
    .xenos_ring_initialized,
    .ring_publication_observed,
    .ring_geometry_observed,
    .pm4_stream_observed,
    .pm4_stream_validated,
    .pm4_indirects_resolved,
    .pm4_state_programmed,
    .draw_submitted,
    .draw_consumed,
    .render_target_state_observed,
    .render_target_memory_observed,
    .draw_completion_signaled,
    .draw_completion_dispatched,
    .guest_output_refreshed,
};

pub const vdswap_path = [_]Stage{
    .guest_image_mapped,
    .kernel_graphics_exports_resolved,
    .xenos_engines_initialized,
    .xenos_ring_initialized,
    .ring_publication_observed,
    .pm4_stream_validated,
    .guest_vdswap_entered,
    .guest_swap_encoded,
    .authentic_swap_consumed,
    .issue_swap_entered,
    .guest_output_refreshed,
    .native_present_completed,
};

pub const scheduler_path = [_]Stage{
    .application_started,
    .guest_scheduler_running,
    .guest_wait_progressed,
    .guest_producer_progressed,
};

pub fn stagesFor(path: Path) []const Stage {
    return switch (path) {
        .host_presenter => &host_presenter_path,
        .guest_vulkan => &guest_vulkan_path,
        .xenos_pm4 => &xenos_pm4_path,
        .vdswap => &vdswap_path,
        .scheduler => &scheduler_path,
    };
}

pub fn stageBit(stage: Stage) u64 {
    return @as(u64, 1) << @as(u6, @intCast(@intFromEnum(stage)));
}

pub const all_stages_mask: u64 = (@as(u64, 1) << @as(u6, @intCast(stage_count))) - 1;

pub fn pathMask(path: Path) u64 {
    var mask: u64 = 0;
    for (stagesFor(path)) |stage| mask |= stageBit(stage);
    return mask;
}

pub fn firstMissing(observed_mask: u64, path: Path) ?Stage {
    for (stagesFor(path)) |stage| {
        if (observed_mask & stageBit(stage) == 0) return stage;
    }
    return null;
}

pub fn pathSatisfied(observed_mask: u64, path: Path) bool {
    return firstMissing(observed_mask, path) == null;
}

pub fn countObserved(observed_mask: u64, path: Path) usize {
    var count: usize = 0;
    for (stagesFor(path)) |stage| {
        if (observed_mask & stageBit(stage) != 0) count += 1;
    }
    return count;
}

fn pathHasDuplicate(stages: []const Stage) bool {
    for (stages, 0..) |stage, index| {
        for (stages[index + 1 ..]) |later| {
            if (stage == later) return true;
        }
    }
    return false;
}

pub fn contractIsWellFormed() bool {
    if (stage_count == 0 or stage_count > 64) return false;
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        const stage: Stage = @enumFromInt(field.value);
        if (stage.label().len == 0 or stage.guidance().len == 0 or stage.owner().label().len == 0) return false;
        if (stage.layer().label().len == 0) return false;
    }
    const paths = .{ host_presenter_path, guest_vulkan_path, xenos_pm4_path, vdswap_path, scheduler_path };
    inline for (paths) |path| {
        if (path.len == 0 or pathHasDuplicate(&path)) return false;
        for (path) |stage| {
            if (@intFromEnum(stage) >= stage_count) return false;
        }
    }
    // Every stage is reachable from at least one declared path.  A stage that
    // exists only in the enum but in no path is a silent diagnostic blind spot.
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        const stage: Stage = @enumFromInt(field.value);
        var reachable = false;
        inline for (paths) |path| {
            for (path) |candidate| {
                if (candidate == stage) reachable = true;
            }
        }
        if (!reachable) return false;
    }
    return true;
}

test "the health schema is complete and every stage has a path" {
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expect(stage_count < 64);
    try std.testing.expect(pathMask(.host_presenter) != 0);
    try std.testing.expect(pathMask(.xenos_pm4) != 0);
}

test "alternative paths do not pretend to satisfy each other" {
    var host_only = pathMask(.host_presenter);
    try std.testing.expect(pathSatisfied(host_only, .host_presenter));
    try std.testing.expect(!pathSatisfied(host_only, .vdswap));

    host_only &= ~stageBit(.native_present_completed);
    try std.testing.expectEqual(Stage.native_present_completed, firstMissing(host_only, .host_presenter).?);
}

test "stage ownership keeps guest decisions outside Rosette's control" {
    try std.testing.expect(!Stage.guest_vdswap_entered.owner().canBeDrivenByRosette());
    try std.testing.expect(Stage.native_window_ready.owner().canBeDrivenByRosette());
    try std.testing.expectEqual(Layer.pm4, Stage.render_target_memory_observed.layer());
}

test "the schema has explicit labels and guidance for the full surface" {
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        const stage: Stage = @enumFromInt(field.value);
        try std.testing.expect(stage.label().len > 3);
        try std.testing.expect(stage.guidance().len > 8);
    }
}
