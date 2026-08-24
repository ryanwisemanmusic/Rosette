//! Human interface devices.
//!
//! "The controller does not work" is a symptom with at least four independent
//! causes, and they are invisible to each other. This library is arranged so
//! each one is separately reportable, in the order the input travels:
//!
//! * `cocoa_hid_driver` — did the host framework discover a device at all?
//! * `controller_map` — is the host reading being translated correctly?
//! * `input_system` — is state being published, and is the title reading it?
//! * `rumble_forwarder` — the return path, and the one motor that must never
//!   be left running.
//!
//! Each stage's verdict names the earliest failure it can see, so the first
//! stage that reports a problem owns it.
//!
//! The console-side layout is `pkg/common/xenia/input-contract`; the route's
//! atomic publish width is `pkg/{x86,ARM64}/xenia/input-driver`.

pub const controller_map = @import("controller_map.zig");
pub const input_system = @import("input_system.zig");
pub const cocoa_hid_driver = @import("cocoa_hid_driver.zig");
pub const rumble_forwarder = @import("rumble_forwarder.zig");

pub const InputSystem = input_system.InputSystem;
pub const Port = input_system.Port;
pub const HostState = controller_map.HostState;
pub const Discovery = cocoa_hid_driver.Discovery;
pub const Device = cocoa_hid_driver.Device;
pub const Forwarder = rumble_forwarder.Forwarder;

// Re-exports do not root tests; without this block none of the above run.
test {
    _ = controller_map;
    _ = input_system;
    _ = cocoa_hid_driver;
    _ = rumble_forwarder;
}
