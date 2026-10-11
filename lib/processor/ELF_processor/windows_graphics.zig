//! Graphics contract package. Can be checked independently of the executor.
pub const state = @import("windows_ui/graphics_state.zig");
pub const interfaces = @import("windows_guest/host_interfaces.zig");

test {
    @import("std").testing.refAllDecls(state);
    @import("std").testing.refAllDecls(interfaces);
}
