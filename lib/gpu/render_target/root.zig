//! Render targets.
//!
//! EDRAM placement, the render target cache, MSAA resolve, and the mapping
//! between tiled EDRAM and linear textures.
//!
//! Everything in this subdirectory shares one property that shapes how it is
//! written: a mistake produces an *image*. Not a crash, not a log line, not a
//! zero counter — a picture that is sheared, or banded, or offset by a fraction
//! of a tile, and which therefore survives every automated check and most
//! review by eye. So the arithmetic is tested against known extents rather than
//! against itself, boundaries are half-open and tested at the boundary, and
//! every sum that could wrap a `u32` is done in `u64` with a test that would
//! catch the wrap.
//!
//! The geometry is `pkg/common/xenia/render-target-contract`.

pub const edram_surface = @import("edram_surface.zig");
pub const rt_cache = @import("rt_cache.zig");
pub const msaa_resolve = @import("msaa_resolve.zig");
pub const tile_mapper = @import("tile_mapper.zig");

pub const Surface = edram_surface.Surface;
pub const Binding = edram_surface.Binding;
pub const Cache = rt_cache.Cache;

// Re-exports do not root tests; without this block none of the above run.
test {
    _ = edram_surface;
    _ = rt_cache;
    _ = msaa_resolve;
    _ = tile_mapper;
}
