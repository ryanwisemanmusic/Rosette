//! Textures.
//!
//! The cache, its guest-memory invalidation, the tiled-to-linear walk, format
//! conversion, and sampler state.
//!
//! Like `lib/gpu/render_target/`, everything here fails by producing a picture
//! rather than an error: a texture with its channels exchanged, its blocks
//! permuted, or one frame out of date all render perfectly. The two that cost
//! the most are worth naming, because they are the ones that survive review by
//! eye:
//!
//! * Red and blue exchanged, from applying the surface swizzle and the channel
//!   order in the wrong sequence (`format_convert`).
//! * A stale texture, from an invalidation range that is off by one at its
//!   boundary (`texture_cache`).
//!
//! The format table is `pkg/common/xenia/texture-contract`; the canonical
//! address swizzle stays in `lib/gpu/xenos_texture.zig` and is passed into the
//! untile walk rather than re-derived here.

pub const texture_cache = @import("texture_cache.zig");
pub const tiling = @import("tiling.zig");
pub const format_convert = @import("format_convert.zig");
pub const sampler = @import("sampler.zig");

pub const Cache = texture_cache.Cache;
pub const Key = texture_cache.Key;
pub const LevelLayout = tiling.LevelLayout;
pub const Sampler = sampler.Sampler;

// Re-exports do not root tests; without this block none of the above run.
test {
    _ = texture_cache;
    _ = tiling;
    _ = format_convert;
    _ = sampler;
}
