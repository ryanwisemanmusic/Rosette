// Kept in the Metal source directory so Zig's module boundary owns its inputs.
pub const source = @embedFile("block_formats.h") ++ "\n" ++ @embedFile("live_xenia.metal");
