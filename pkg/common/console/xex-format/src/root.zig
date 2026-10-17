//! Route-independent: the XEX2 module container's header format.
//!
//! A title ships as a XEX: a big-endian container wrapping an encrypted,
//! compressed PE image plus a table of optional headers. Rosette's
//! `user_module_loaded` stage depends on reading it, and the import-library
//! header inside it is where the kernel ordinals a title needs come from.
//!
//! ## The optional-header key encodes how to read its own value
//!
//! This is the fact that makes the format survivable. A key's **low byte** says
//! where the value lives:
//!
//! * `0x00` — the value *is* the 32 bits in the table entry.
//! * `0x01` — the entry holds a pointer to a single dword.
//! * anything else — the entry holds a file offset to a structure.
//!
//! So `XEX_HEADER_ENTRY_POINT` (`0x00010100`) is read inline, while
//! `XEX_HEADER_IMAGE_BASE_ADDRESS` (`0x00010201`) is one indirection away, and
//! `XEX_HEADER_IMPORT_LIBRARIES` (`0x000103FF`) is a file offset. A loader that
//! treats them uniformly gets an entry point that is actually a pointer, jumps
//! to it, and faults somewhere with no relationship to the loader.
//!
//! ## Everything is big-endian
//!
//! The container is console-native. On a little-endian host every field needs
//! swapping, and a field read without swapping is not obviously wrong — a
//! base address of `0x00000082` instead of `0x82000000` looks like a small
//! number rather than a byte-order mistake.
//!
//! ## What this package is not
//!
//! * It is not a loader. It maps nothing, decrypts nothing and decompresses
//!   nothing.
//! * It holds no module. Base address, entry point and import bindings for a
//!   loaded title are live state.
//! * It does not decrypt. The key selection and AES work belong in lib.

const std = @import("std");

/// "XEX2", big-endian.
pub const xex2_magic: u32 = 0x58455832;

/// The container is big-endian throughout.
pub const is_big_endian: bool = true;

/// How an optional header's value is reached.
pub const ValueLocation = enum {
    /// The table entry's 32 bits are the value.
    inline_value,
    /// The entry holds a pointer to one dword.
    pointer_to_dword,
    /// The entry holds a file offset to a structure.
    offset_to_struct,
};

/// Where a key's value lives, from its low byte.
///
/// The single most consequential decode in the format. Getting it wrong for
/// the entry point yields a pointer that is then jumped to.
pub fn valueLocationOf(key: u32) ValueLocation {
    return switch (key & 0xFF) {
        0x00 => .inline_value,
        0x01 => .pointer_to_dword,
        else => .offset_to_struct,
    };
}

/// The optional header keys Xenia reads.
pub const HeaderKey = enum(u32) {
    resource_info = 0x0000_02FF,
    file_format_info = 0x0000_03FF,
    delta_patch_descriptor = 0x0000_05FF,
    base_reference = 0x0000_0405,
    bounding_path = 0x0000_80FF,
    device_id = 0x0000_8105,
    original_base_address = 0x0001_0001,
    entry_point = 0x0001_0100,
    image_base_address = 0x0001_0201,
    import_libraries = 0x0001_03FF,
    checksum_timestamp = 0x0001_8002,
    enabled_for_callcap = 0x0001_8102,
    enabled_for_fastcap = 0x0001_8200,
    original_pe_name = 0x0001_83FF,
    static_libraries = 0x0002_00FF,
    tls_info = 0x0002_0104,
    default_stack_size = 0x0002_0200,
    default_filesystem_cache_size = 0x0002_0301,
    default_heap_size = 0x0002_0401,
    page_heap_size_and_flags = 0x0002_8002,
    system_flags = 0x0003_0000,
    execution_info = 0x0004_0006,
    title_workspace_size = 0x0004_0201,
    game_ratings = 0x0004_0310,
    lan_key = 0x0004_0404,
    xbox360_logo = 0x0004_05FF,
    multidisc_media_ids = 0x0004_06FF,
    alternate_title_ids = 0x0004_07FF,
    additional_title_memory = 0x0004_0801,
    exports_by_name = 0x00E1_0402,
    _,

    pub fn key(self: HeaderKey) u32 {
        return @intFromEnum(self);
    }

    pub fn valueLocation(self: HeaderKey) ValueLocation {
        return valueLocationOf(@intFromEnum(self));
    }
};

pub const EncryptionType = enum(u16) {
    none = 0,
    normal = 1,
    _,
};

pub const CompressionType = enum(u16) {
    none = 0,
    basic = 1,
    normal = 2,
    delta = 3,
    _,

    /// Whether the image must be decompressed before it can be mapped.
    pub fn requiresDecompression(self: CompressionType) bool {
        return self != .none;
    }
};

/// A XEX import library descriptor, as it appears in the container.
///
/// The structure a title's kernel ordinals come from. `count` names how many
/// ordinals follow; the version fields let a title require a minimum kernel.
pub const ImportLibraryHeader = extern struct {
    unused: u32 = 0,
    /// Version of the library this title was built against.
    version: u32 = 0,
    min_version: u32 = 0,
    name_index: u16 = 0,
    count: u16 = 0,
};

/// The import record's high byte selects what kind of binding it is.
pub const ImportType = enum(u8) {
    /// A thunk the loader patches with a jump.
    function = 1,
    /// A slot the loader writes an address into.
    variable = 0,
    _,
};

/// Decompose an import record.
///
/// The record packs its type in the high byte and the ordinal in the low 16
/// bits. Reading the whole dword as an ordinal produces values in the millions,
/// which then miss every export table lookup — and the resulting "no exports
/// resolved" is easy to misread as a missing export table.
pub fn importOrdinalOf(record: u32) u16 {
    return @truncate(record & 0xFFFF);
}

pub fn importTypeOf(record: u32) ImportType {
    return @enumFromInt(@as(u8, @truncate(record >> 24)));
}

/// The guest address a retail title is based at.
///
/// Halo 3 and every other retail title load at 0x82000000. A base that is not
/// in this neighbourhood usually means the field was read without a byte swap.
pub const typical_image_base: u32 = 0x8200_0000;

/// Whether an address looks like a guest module base rather than a byte-swapped
/// one.
pub fn isPlausibleImageBase(address: u32) bool {
    return address >= 0x8000_0000 and address < 0x9000_0000;
}

/// Swap a big-endian dword read from the container.
pub fn swapDword(value: u32) u32 {
    return @byteSwap(value);
}

pub fn contractIsWellFormed() bool {
    if (valueLocationOf(0x0001_0100) != .inline_value) return false;
    if (valueLocationOf(0x0001_0201) != .pointer_to_dword) return false;
    if (valueLocationOf(0x0001_03FF) != .offset_to_struct) return false;
    if (!isPlausibleImageBase(typical_image_base)) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "the key's low byte says where its value lives" {
    // The decode that matters most: an entry point read as a pointer is then
    // jumped to, and the fault has no relationship to the loader.
    try std.testing.expectEqual(ValueLocation.inline_value, HeaderKey.entry_point.valueLocation());
    try std.testing.expectEqual(ValueLocation.pointer_to_dword, HeaderKey.image_base_address.valueLocation());
    try std.testing.expectEqual(ValueLocation.offset_to_struct, HeaderKey.import_libraries.valueLocation());
    try std.testing.expectEqual(ValueLocation.offset_to_struct, HeaderKey.resource_info.valueLocation());
}

test "stack size and heap size are read differently" {
    // The sharpest example in the table: two keys that describe the same kind
    // of quantity, eight apart, with different reading rules. Stack size is
    // inline (0x...00); heap size is a pointer (0x...01). Treating them
    // uniformly yields a heap size that is actually an address — a plausible
    // large number that then sizes an allocation.
    try std.testing.expectEqual(ValueLocation.inline_value, HeaderKey.default_stack_size.valueLocation());
    try std.testing.expectEqual(ValueLocation.pointer_to_dword, HeaderKey.default_heap_size.valueLocation());
    try std.testing.expectEqual(ValueLocation.pointer_to_dword, HeaderKey.default_filesystem_cache_size.valueLocation());
    // System flags are inline too.
    try std.testing.expectEqual(ValueLocation.inline_value, HeaderKey.system_flags.valueLocation());
}

test "0xFF keys are always structures" {
    // Every variable-length header uses 0xFF, so the rule is checkable across
    // the whole table rather than key by key.
    const variable_keys = [_]HeaderKey{
        .resource_info,
        .file_format_info,
        .delta_patch_descriptor,
        .bounding_path,
        .import_libraries,
        .original_pe_name,
        .static_libraries,
        .xbox360_logo,
        .multidisc_media_ids,
        .alternate_title_ids,
    };
    for (variable_keys) |header_key| {
        try std.testing.expectEqual(@as(u32, 0xFF), header_key.key() & 0xFF);
        try std.testing.expectEqual(ValueLocation.offset_to_struct, header_key.valueLocation());
    }
}

test "the magic is XEX2 in big-endian byte order" {
    try std.testing.expectEqual(@as(u32, 0x58455832), xex2_magic);
    // Spelled out: 'X' 'E' 'X' '2'.
    try std.testing.expectEqual(@as(u8, 'X'), @as(u8, @truncate(xex2_magic >> 24)));
    try std.testing.expectEqual(@as(u8, 'E'), @as(u8, @truncate(xex2_magic >> 16)));
    try std.testing.expectEqual(@as(u8, 'X'), @as(u8, @truncate(xex2_magic >> 8)));
    try std.testing.expectEqual(@as(u8, '2'), @as(u8, @truncate(xex2_magic)));
    // Byte-swapped it is not the magic, which is what a host-order read yields.
    try std.testing.expect(swapDword(xex2_magic) != xex2_magic);
}

test "an import record's ordinal is its low sixteen bits" {
    // Reading the whole dword as an ordinal gives values in the millions that
    // miss every export lookup, and the resulting "no exports resolved" reads
    // as a missing export table rather than a decode mistake.
    const record: u32 = 0x0100_01C3;
    try std.testing.expectEqual(@as(u16, 0x01C3), importOrdinalOf(record));
    try std.testing.expectEqual(ImportType.function, importTypeOf(record));

    const variable_record: u32 = 0x0000_01BE;
    try std.testing.expectEqual(@as(u16, 0x01BE), importOrdinalOf(variable_record));
    try std.testing.expectEqual(ImportType.variable, importTypeOf(variable_record));
}

test "a retail image base is recognisable from a byte-swapped one" {
    // 0x82000000 swapped is 0x00000082, which looks like a small number
    // rather than an obviously wrong address.
    try std.testing.expect(isPlausibleImageBase(typical_image_base));
    try std.testing.expect(!isPlausibleImageBase(swapDword(typical_image_base)));
    try std.testing.expectEqual(@as(u32, 0x0000_0082), swapDword(typical_image_base));
    try std.testing.expect(!isPlausibleImageBase(0));
}

test "compression types other than none need work before mapping" {
    try std.testing.expect(!CompressionType.none.requiresDecompression());
    try std.testing.expect(CompressionType.basic.requiresDecompression());
    try std.testing.expect(CompressionType.normal.requiresDecompression());
    try std.testing.expect(CompressionType.delta.requiresDecompression());
}

test "unknown encryption and compression values are carried, not trapped" {
    // A container from an unusual toolchain must be reportable rather than
    // crash the loader on a checked cast.
    const unknown_encryption: EncryptionType = @enumFromInt(9);
    try std.testing.expectEqual(@as(u16, 9), @intFromEnum(unknown_encryption));
    const unknown_compression: CompressionType = @enumFromInt(9);
    try std.testing.expect(unknown_compression.requiresDecompression());
}

test "the import library header keeps its container layout" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(ImportLibraryHeader, "unused"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(ImportLibraryHeader, "version"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(ImportLibraryHeader, "min_version"));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(ImportLibraryHeader, "name_index"));
    try std.testing.expectEqual(@as(usize, 14), @offsetOf(ImportLibraryHeader, "count"));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(ImportLibraryHeader));
}

test "an unnamed header key still decodes its value location" {
    // The table is non-exhaustive; a key Xenia does not name still follows
    // the low-byte rule, so a loader can read it without knowing what it is.
    const unnamed: HeaderKey = @enumFromInt(0x0009_00FF);
    try std.testing.expectEqual(ValueLocation.offset_to_struct, unnamed.valueLocation());
    const unnamed_inline: HeaderKey = @enumFromInt(0x0009_0000);
    try std.testing.expectEqual(ValueLocation.inline_value, unnamed_inline.valueLocation());
}
