//! The native Vulkan presentation path.
//!
//! Split into four parts along the line that decides what can be tested. `abi`
//! is the structure layouts the host driver reads; `selection` is every choice
//! made from what the driver reported; `frame` is the ownership and health
//! bookkeeping between frames; `presenter` is the thin remainder that actually
//! calls the driver. The first three run anywhere — no window, no runloop, no
//! MoltenVK — which is where the arithmetic that silently corrupts a frame is
//! allowed to be wrong only once.

pub const abi = @import("abi.zig");
pub const async_command_worker = @import("async_command_worker.zig");
pub const handle_set = @import("handle_set.zig");
pub const handle_map_registry = @import("handle_map_registry.zig");
pub const marshal = @import("marshal.zig");
pub const rect_list_expand = @import("rect_list_expand.zig");
/// Vulkan robustBufferAccess for Metal: every dynamic shader index clamped.
pub const robust_access = @import("robust_access.zig");
pub const hdr_resolve = @import("hdr_resolve.zig");
pub const tier_consistency = @import("tier_consistency.zig");
pub const guest_state = @import("guest_state.zig");
pub const selection = @import("selection.zig");
pub const frame = @import("frame.zig");
pub const frame_capture = @import("frame_capture.zig");
/// Xenia's fragment-shader-interlock render backend: contract, descriptor
/// repair, identity tracking, the GPU watchdog budget, command-buffer
/// chunking and GPU timing (`fsi/root.zig`).
pub const fsi = @import("fsi/root.zig");
pub const fsi_diagnostics = fsi.tracker;
pub const fsi_descriptor_repair = fsi.descriptor_repair;
pub const device_loss_diagnostics = @import("device_loss_diagnostics.zig");
pub const transport_timing = @import("transport_timing.zig");
pub const present_pacing = @import("present_pacing.zig");
pub const queue_api_gate = @import("queue_api_gate.zig");
pub const texel_custody = @import("texel_custody.zig");
pub const presenter = @import("presenter.zig");
pub const spirv_stage = @import("spirv_stage.zig");
pub const capture_plan = @import("capture_plan.zig");
pub const driver_identity = @import("driver_identity.zig");

pub const Presenter = presenter.Presenter;
pub const Stage = presenter.Stage;
pub const Source = presenter.Source;
pub const CpuImage = presenter.CpuImage;
pub const FrameReport = presenter.FrameReport;
pub const Report = presenter.Report;
pub const SymbolResolver = presenter.SymbolResolver;
pub const Health = frame.Health;

test {
    _ = abi;
    _ = async_command_worker;
    _ = handle_set;
    _ = handle_map_registry;
    _ = marshal;
    _ = rect_list_expand;
    _ = robust_access;
    _ = hdr_resolve;
    _ = tier_consistency;
    _ = guest_state;
    _ = selection;
    _ = frame;
    _ = frame_capture;
    _ = fsi;
    _ = device_loss_diagnostics;
    _ = transport_timing;
    _ = present_pacing;
    _ = queue_api_gate;
    _ = texel_custody;
    _ = presenter;
    _ = spirv_stage;
    _ = capture_plan;
    _ = driver_identity;
}
