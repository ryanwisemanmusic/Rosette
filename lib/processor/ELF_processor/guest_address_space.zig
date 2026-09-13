//! Rosette's record of what occupies each part of the guest's address space.
//!
//! A thin layer over `address_region_map`: the package holds the lookup and
//! knows nothing about PE files, import stubs or Win32 page protections, and
//! this file is where those become regions. Split out of `process.zig`
//! deliberately - the interpreter is eighteen thousand lines and every
//! self-contained subsystem that stays out of it is one a reader can open on
//! its own.
//!
//! ## What this is for
//!
//! `pe_symbols` answers "which function covers this address" and correctly
//! declines for anything the image does not contain. That is most of a
//! running process. The 2026-09-12 run printed `at=<unnamed>` for the busiest
//! worker in the process and for the one thread that had become the whole
//! investigation, and in both cases Rosette knew exactly what the memory was.

const std = @import("std");
const region_map = @import("address_region_map");

pub const RegionKind = region_map.RegionKind;
pub const Map = region_map.Map;

/// Granule the discovered code regions grow by.
///
/// A JIT emits a function at a time; recording each one would fill a
/// sixty-four entry table in the first second. Sixty-four kilobytes is the
/// Windows allocation granularity, which is also the unit a guest gets back
/// from `VirtualAlloc` with no base address, so a region grown this way lines
/// up with what the guest actually asked for.
pub const discovered_code_granule: u64 = 0x10000;

/// Win32 page-protection constants that permit execution.
///
/// Kept here rather than in the package because they are a Win32 fact and the
/// package is not about Windows. The four `EXECUTE` protections are the only
/// ones that make a block a candidate for generated code.
pub const page_execute: u32 = 0x10;
pub const page_execute_read: u32 = 0x20;
pub const page_execute_readwrite: u32 = 0x40;
pub const page_execute_writecopy: u32 = 0x80;

pub fn protectionAllowsExecute(protection: u32) bool {
    return (protection & (page_execute | page_execute_read | page_execute_readwrite | page_execute_writecopy)) != 0;
}

/// Record an allocation the guest made, classified by whether it may execute.
///
/// This is the whole mechanism behind naming a JIT. Rosette does not need to
/// know that Xenia has a PowerPC translator: it needs to notice that the
/// guest asked for memory it is allowed to run, and then say so when a thread
/// turns up executing there. Any program that generates code produces the
/// same shape.
pub fn noteGuestAllocation(
    map: *Map,
    address: u64,
    length: u64,
    protection: u32,
) void {
    if (address == 0 or length == 0) return;
    if (!protectionAllowsExecute(protection)) return;
    // Rounded up to the granule so a region covers the whole request, and
    // extended rather than inserted so a translator emitting into a growing
    // buffer does not consume the table.
    var covered: u64 = 0;
    while (covered < length) : (covered +|= discovered_code_granule) {
        if (!map.extend(address +| covered, discovered_code_granule, .generated_code, "guest-allocated executable memory")) return;
    }
}

/// Describe an address for a report, preferring a symbol and falling back to
/// the region.
///
/// The order matters. A symbol is a better answer than a region whenever
/// there is one, and a region is a better answer than `<unnamed>` always.
/// `symbol` is whatever the caller's resolver produced, empty when it had
/// nothing.
pub fn describe(map: *const Map, address: u64, symbol: []const u8, buffer: []u8) []const u8 {
    if (symbol.len != 0) return symbol;
    const described = map.describe(address, buffer);
    if (described.len != 0) return described;
    return "";
}

test "an executable allocation becomes a named region; a data one does not" {
    var map = Map{};
    // Xenia's code cache: a large RWX block the translator emits into.
    noteGuestAllocation(&map, 0xA0000000, 0x100000, page_execute_readwrite);
    var buffer: [96]u8 = undefined;
    const described = map.describe(0xA000044B, &buffer);
    try std.testing.expect(std.mem.startsWith(u8, described, "generated-code:"));
    try std.testing.expect(map.isExecutable(0xA000044B));

    // A plain heap block is not code and must not be labelled as if it were:
    // a rip there is a control-flow escape, and calling it "generated code"
    // would hide the one finding that matters.
    noteGuestAllocation(&map, 0x280D00000, 0x10000, 0x04); // PAGE_READWRITE
    try std.testing.expectEqualStrings("", map.describe(0x280D00000, &buffer));
    try std.testing.expect(!map.isExecutable(0x280D00000));
}

test "every executing protection counts, and nothing else does" {
    for ([_]u32{ page_execute, page_execute_read, page_execute_readwrite, page_execute_writecopy }) |protection| {
        try std.testing.expect(protectionAllowsExecute(protection));
        // Combined with a guard or no-cache bit, as a real request often is.
        try std.testing.expect(protectionAllowsExecute(protection | 0x100));
    }
    for ([_]u32{ 0x00, 0x01, 0x02, 0x04, 0x08 }) |protection| {
        try std.testing.expect(!protectionAllowsExecute(protection));
    }
}

test "a symbol beats a region, and a region beats nothing" {
    var map = Map{};
    _ = map.insert(0x1430b2000, 0x200000, .import_thunk, "win32-import-stubs");
    var buffer: [96]u8 = undefined;

    // With a symbol, the symbol.
    try std.testing.expectEqualStrings(
        "xe::gpu::GraphicsSystem::MarkVblank+0x4",
        describe(&map, 0x1401b7384, "xe::gpu::GraphicsSystem::MarkVblank+0x4", &buffer),
    );
    // Without one, the region - which is the answer the 2026-09-12 report
    // was missing for its busiest thread.
    try std.testing.expectEqualStrings(
        "import-thunk:win32-import-stubs+0x5b0",
        describe(&map, 0x1430b25b0, "", &buffer),
    );
    // With neither, empty, so the caller prints its own marker rather than
    // this file inventing one.
    try std.testing.expectEqualStrings("", describe(&map, 0x900000000, "", &buffer));
}

test "a huge allocation does not consume the region table" {
    var map = Map{};
    // Sixteen megabytes of executable memory, in one request.
    noteGuestAllocation(&map, 0xA0000000, 0x1000000, page_execute_readwrite);
    // Adjacent granules merge, so this is one region and not two hundred.
    try std.testing.expect(map.count <= 2);
    try std.testing.expect(map.isExecutable(0xA0000000));
    try std.testing.expect(map.isExecutable(0xA0FFF000));
}
