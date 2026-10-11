//! Metal-specific preparation that can coexist with the current Vulkan path.
//!
//! Offline artifacts and allocation policies coexist with a narrow native MSL
//! texture route inside the Vulkan command stream. The texture route is pinned
//! to a tested driver ABI; it is not a complete replacement for MoltenVK/FSI.

pub const artifact_cache = @import("artifact_cache.zig");
pub const backend_health = @import("backend_health.zig");
pub const command_buffer_policy = @import("command_buffer_policy.zig");
pub const unified_memory = @import("unified_memory.zig");
pub const live_texture = @import("live_texture.zig");

test {
    _ = artifact_cache;
    _ = backend_health;
    _ = command_buffer_policy;
    _ = unified_memory;
    _ = live_texture;
}
