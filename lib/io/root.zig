//! io — Guest I/O forwarding library.
//!
//! Consolidates filesystem operations, libc++ stream bridging, FD management,
//! path translation, and libc++ filesystem support.
//!
//! Module-level dependencies (provided via build.zig addImport):
//!   - macho_compat_runtime  (used by libcpp_filesystem, libcpp_stream_bridge)
//!   - cxx_abi               (used by libcpp_stream_bridge for cxx_object_model)
//!   - event_log             (shared logging)

pub const fs_io_forwarder = @import("fs_io_forwarder.zig");
pub const libcpp_filesystem = @import("libcpp_filesystem.zig");
pub const libcpp_stream_bridge = @import("libcpp_stream_bridge.zig");
pub const fd_management = @import("fd_management.zig");
pub const path_translation = @import("path_translation.zig");
