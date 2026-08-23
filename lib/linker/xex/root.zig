//! Xbox 360 XEX2 image loading.
//!
//! Xenia owns module loading when Rosette runs as its CPU backend: the backend
//! consumes an address space that is already mapped. This exists for the other
//! direction - running an Xbox 360 image against the PowerPC runtime without
//! Xenia, which is what makes the direct path testable end to end and is the
//! foundation for a Rosette-native Xbox 360 mode.
//!
//! What it covers is stated precisely in image.zig: headers, the security
//! block, imports, and mapping a plaintext basefile. Decryption and the LZX
//! compression are reported by name rather than approximated.

const std = @import("std");

pub const image = @import("image.zig");

pub const Image = image.Image;
pub const Error = image.Error;
pub const HeaderKey = image.HeaderKey;
pub const ModuleFlags = image.ModuleFlags;
pub const Encryption = image.Encryption;
pub const Compression = image.Compression;
pub const SectionType = image.SectionType;
pub const OptionalHeader = image.OptionalHeader;
pub const PageDescriptor = image.PageDescriptor;
pub const ImportLibrary = image.ImportLibrary;
pub const ExecutionInfo = image.ExecutionInfo;
pub const BasefileFormat = image.BasefileFormat;

pub const parse = Image.parse;

test {
    std.testing.refAllDecls(@This());
    _ = image;
}
