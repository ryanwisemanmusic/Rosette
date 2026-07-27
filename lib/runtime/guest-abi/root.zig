//! guest-abi — Guest ABI runtime support library.
//!
//! Provides runtime components for guest binary compatibility:
//!   - Foreign object dispatch (GTK/GLib main-loop handoff)
//!   - Native window/Metal surface integration
//!   - Guest assertion recovery and classification
//!   - Thread-Local Storage (TLV) descriptor management
//!
//! Module-level dependencies (provided via build.zig addImport):
//!   - event_log  (shared logging)

pub const foreign_object_runtime = @import("foreign_object_runtime.zig");
pub const native_window_runtime = @import("native_window_runtime.zig");
pub const guest_assertion_recovery = @import("guest_assertion_recovery.zig");
pub const tlv_runtime = @import("tlv_runtime.zig");

test {
    _ = foreign_object_runtime;
    _ = native_window_runtime;
    _ = guest_assertion_recovery;
    _ = tlv_runtime;
}
