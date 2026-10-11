//! FSI: Rosette's support layer for Xenia's fragment-shader-interlock render
//! backend (`render_target_path_vulkan = "fsi"`).
//!
//! Under FSI Xenia does not use host render targets at all. Every pixel
//! shader reads and writes the emulated EDRAM, a storage buffer, inside a
//! fragment-shader-interlock critical section: depth/stencil testing,
//! blending and format packing all happen in software, exactly as the Xbox
//! 360's EDRAM did them. It is Xenia's most accurate path and the one its
//! compatibility data recommends for Halo 3 (`requires_render_target_rov_fsi`),
//! but it moves the whole render backend into shaders that MoltenVK runs with
//! Metal raster order groups, and it makes a frame's GPU cost follow overdraw.
//!
//! What this layer owns, each piece in its own file:
//!   contract           what Xenia's FSI path requires and creates, recognised
//!                      as the objects are made
//!   descriptor_repair  the dead-local ZPD counter descriptor in Xenia's
//!                      SetupContext, repaired so the EDRAM gets bound
//!   tracker            FSI shader, pipeline, draw and submission identity
//!   rasterization      stable attachment-less sample counts on MoltenVK
//!   budget             how much FSI work one Metal command buffer may carry
//!                      before the macOS GPU watchdog becomes a risk
//!   chain              splitting a guest command buffer into bounded chunks,
//!                      with the bound state replayed into each new chunk
//!   timing             GPU time of every chunk, measured by a watcher thread
//!
//! The forwarder (`lib/linker/dyld/dynamic_library_forwarder.zig`) calls into
//! these and prints their state as `VULKAN FSI ...` lines. Rasterization restores
//! the sample coverage Xenia requested; the chain bounds command-buffer work.
//! Both preserve the guest shaders, EDRAM contents and ordering.
pub const contract = @import("contract.zig");
pub const descriptor_repair = @import("descriptor_repair.zig");
pub const tracker = @import("tracker.zig");
pub const rasterization = @import("rasterization.zig");
pub const budget = @import("budget.zig");
pub const chain = @import("chain.zig");
pub const timing = @import("timing.zig");
pub const evidence = @import("evidence.zig");
pub const pixel_frequency = @import("pixel_frequency.zig");

test {
    _ = contract;
    _ = descriptor_repair;
    _ = tracker;
    _ = rasterization;
    _ = budget;
    _ = chain;
    _ = timing;
    _ = evidence;
    _ = pixel_frequency;
}
