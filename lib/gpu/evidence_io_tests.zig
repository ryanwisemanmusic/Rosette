//! Small CPU-only root with the Vulkan module boundary for evidence tests.
test {
    _ = @import("vulkan/fsi/evidence_async_tests.zig");
}
