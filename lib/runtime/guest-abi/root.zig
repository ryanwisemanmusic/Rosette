//! guest-abi — Guest ABI runtime support library.
//!
//! Provides runtime components for guest binary compatibility:
//!   - Foreign object dispatch (GTK/GLib main-loop handoff)
//!   - Native window/Metal surface integration
//!   - Guest assertion recovery and classification
//!   - C++ allocation/deallocation ABI symbol classification
//!   - Thread-Local Storage (TLV) descriptor management
//!
//! Module-level dependencies (provided via build.zig addImport):
//!   - event_log  (shared logging)

pub const foreign_object_runtime = @import("foreign_object_runtime.zig");
pub const native_window_runtime = @import("native_window_runtime.zig");
pub const guest_assertion_recovery = @import("guest_assertion_recovery.zig");
pub const cpp_allocation = @import("cpp_allocation.zig");
pub const libcpp_thread = @import("libcpp_thread.zig");
pub const tlv_runtime = @import("tlv_runtime.zig");

test {
    _ = foreign_object_runtime;
    _ = native_window_runtime;
    _ = guest_assertion_recovery;
    _ = cpp_allocation;
    _ = libcpp_thread;
    _ = tlv_runtime;
}
