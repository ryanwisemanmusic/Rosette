const source_include_compat = @import("../source/include_compat.zig");

pub const discoverIncludeDirs = source_include_compat.discoverIncludeDirs;
pub const hasHeaderExtension = source_include_compat.hasHeaderExtension;
pub const isStandardHeaderShadowName = source_include_compat.isStandardHeaderShadowName;
pub const isSimdBridgeDir = source_include_compat.isSimdBridgeDir;
pub const pathContainsSimdBridgeDir = source_include_compat.pathContainsSimdBridgeDir;
