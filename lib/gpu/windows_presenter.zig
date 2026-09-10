//! Narrow module entry point for host-side callers that need the native Vulkan
//! presenter without importing the entire GPU aggregate.

pub const Presenter = @import("vulkan/presenter.zig").Presenter;
pub const Stage = @import("vulkan/presenter.zig").Stage;

test {
    _ = Presenter;
    _ = Stage;
}
