//! Rosetta-only compatibility patch for Xenia's Vulkan rectangle fallback.
//!
//! Xenia's PrimitiveProcessor already lowers Xenos rectangle lists to the
//! vertex-shader/indexed fallback when geometry shaders are unavailable.  The
//! Vulkan command processor then rejects that prepared result in one guard in
//! IssueDraw: it admits the ordinary, point-sprite, and tessellation shader
//! types, but omits kRectangleListAsTriangleStrip.  This module repairs that
//! admission in the *loaded guest image* without touching the Xenia source or
//! the bundle on disk.  Once admitted, the original Xenia function continues
//! through its own shader translation, render-target, descriptor, built-in
//! index-buffer, and vkCmdDrawIndexed code.
//!
//! The patch is deliberately conservative:
//! - it requires the exact IssueDraw symbol and a byte-level guard signature;
//! - it preserves rejection of kMemExportCompute (7), the reserved value (8),
//!   and values greater than kRectangleListAsTriangleStrip (10);
//! - it writes the detour body only into an executable run of 0x90/0xCC
//!   padding, outside the target function and all exact COFF symbol starts;
//! - it is idempotent and reports an already-patched image rather than
//!   stacking a second detour.
//!
//! No host machine code is called by the cave.  It contains only x86-64
//! compare and relative-branch instructions that Rosetta's guest decoder
//! already executes.

const std = @import("std");
const pe_symbols = @import("pe_symbols.zig");

/// The raw COFF spelling used by Xenia's current PE image.  Keep the full
/// signature because IssueDraw is overloaded in the command-processor base
/// and D3D12 classes.
pub const issue_draw_symbol = "_ZN2xe3gpu6vulkan22VulkanCommandProcessor9IssueDrawENS0_5xenos13PrimitiveTypeEjPNS0_16CommandProcessor15IndexBufferInfoEb";

const guard_bytes: usize = 27;
const guard_bytes_u64: u64 = guard_bytes;
const detour_bytes: usize = 6;
const cave_bytes: usize = 23;
const default_scan_limit: usize = 0x4000;
const default_target_exclusion_distance: u64 = 0x10000;

pub const AddressRange = struct {
    base: u64,
    length: u64,
};

pub const Status = enum {
    missing_symbol,
    target_not_executable,
    guard_not_found,
    ambiguous_guard,
    no_code_cave,
    relative_branch_out_of_range,
    applied,
    already_applied,
};

pub const Options = struct {
    /// The symbol resolver owns this fact.  Passing null is intentional for a
    /// stripped image and produces a visible no-patch result.
    issue_draw_address: ?u64,
    /// Optional symbol table used only to avoid exact symbol entry points in
    /// the padding scanner.
    symbol_index: ?*const pe_symbols.Index = null,
    scan_limit: usize = default_scan_limit,
    /// Kept configurable for small synthetic unit-test images.  Production
    /// uses a generous exclusion around IssueDraw so a cave cannot land in a
    /// nearby basic block or the function's cold tail.
    target_exclusion_distance: u64 = default_target_exclusion_distance,
};

pub const Result = struct {
    status: Status,
    target_address: u64 = 0,
    guard_address: u64 = 0,
    cave_address: u64 = 0,
    allow_address: u64 = 0,
    failure_address: u64 = 0,
};

const GuardMatch = struct {
    address: u64,
    allow_address: u64,
    failure_address: u64,
};

fn memoryAt(memory: []u8, image_base: u64, address: u64, length: usize) ?[]u8 {
    if (address < image_base) return null;
    const offset_u64 = address - image_base;
    if (offset_u64 > @as(u64, @intCast(memory.len))) return null;
    const offset: usize = @intCast(offset_u64);
    if (offset > memory.len or length > memory.len - offset) return null;
    return memory[offset .. offset + length];
}

fn memoryRemainder(memory: []u8, image_base: u64, address: u64) ?[]u8 {
    if (address < image_base) return null;
    const offset_u64 = address - image_base;
    if (offset_u64 >= @as(u64, @intCast(memory.len))) return null;
    const offset: usize = @intCast(offset_u64);
    return memory[offset..];
}

fn contains(range: AddressRange, address: u64, length: u64) bool {
    if (address < range.base) return false;
    const offset = address - range.base;
    if (offset > range.length) return false;
    return length <= range.length - offset;
}

fn executableAt(ranges: []const AddressRange, address: u64, length: u64) bool {
    for (ranges) |range| {
        if (contains(range, address, length)) return true;
    }
    return false;
}

fn addSigned(base: u64, displacement: i64) ?u64 {
    if (displacement >= 0) {
        return std.math.add(u64, base, @as(u64, @intCast(displacement))) catch null;
    }
    return std.math.sub(u64, base, @as(u64, @intCast(-displacement))) catch null;
}

fn rel8Target(address: u64, displacement: u8) ?u64 {
    const signed: i8 = @bitCast(displacement);
    return addSigned(address +| 2, signed);
}

fn rel32Target(address: u64, displacement: i32) ?u64 {
    return addSigned(address +| 5, displacement);
}

fn relativeTarget(after_instruction: u64, displacement: i32) ?u64 {
    return addSigned(after_instruction, displacement);
}

fn relative32(after_instruction: u64, target: u64) ?i32 {
    if (target >= after_instruction) {
        const distance = target - after_instruction;
        if (distance > 0x7fff_ffff) return null;
        return @intCast(distance);
    }
    const distance = after_instruction - target;
    if (distance > 0x8000_0000) return null;
    const signed_distance: i64 = -@as(i64, @intCast(distance));
    return @intCast(signed_distance);
}

fn prefixMatches(bytes: []const u8, address: u64) bool {
    if (bytes.len < guard_bytes) return false;
    // mov eax, dword ptr [rsp+0xf0].  The stack displacement is part of the
    // ABI shape we are repairing; accepting a different frame offset could
    // patch an unrelated compare sequence in a rebuilt image.
    if (!std.mem.eql(u8, bytes[0..3], &.{ 0x8B, 0x84, 0x24 })) return false;
    if (std.mem.readInt(i32, bytes[3..7], .little) != 0xF0) return false;
    if (!std.mem.eql(u8, bytes[7..9], &.{ 0x85, 0xC0 })) return false;
    if (bytes[9] != 0x74 or bytes[14] != 0x74) return false;
    if (!std.mem.eql(u8, bytes[11..14], &.{ 0x83, 0xF8, 0x09 })) return false;
    if (!std.mem.eql(u8, bytes[16..18], &.{ 0xFF, 0xC8 })) return false;
    if (!std.mem.eql(u8, bytes[18..21], &.{ 0x83, 0xF8, 0x05 })) return false;
    const first_target = rel8Target(address + 9, bytes[10]);
    const second_target = rel8Target(address + 14, bytes[15]);
    const expected_allow = address +| guard_bytes_u64;
    return first_target == expected_allow and second_target == expected_allow;
}

fn originalGuardAt(
    memory: []u8,
    image_base: u64,
    ranges: []const AddressRange,
    address: u64,
) ?GuardMatch {
    if (!executableAt(ranges, address, guard_bytes)) return null;
    const bytes = memoryAt(memory, image_base, address, guard_bytes) orelse return null;
    if (!prefixMatches(bytes, address)) return null;
    if (!std.mem.eql(u8, bytes[21..23], &.{ 0x0F, 0x87 })) return null;
    // 0F 87 rel32 is six bytes, so its displacement starts at +22 and is
    // relative to +27.  rel32Target models a five-byte E9-style branch.
    const failure = rel32Target(address + 22, std.mem.readInt(i32, bytes[23..27], .little)) orelse return null;
    const allow = address +| guard_bytes_u64;
    if (!executableAt(ranges, allow, 1) or !executableAt(ranges, failure, 1)) return null;
    if (failure == allow) return null;
    return .{ .address = address, .allow_address = allow, .failure_address = failure };
}

const PatchedCave = struct {
    allow_address: u64,
    failure_address: u64,
};

fn patchedCaveTargets(
    memory: []u8,
    image_base: u64,
    ranges: []const AddressRange,
    address: u64,
) ?PatchedCave {
    if (!executableAt(ranges, address, cave_bytes)) return null;
    const bytes = memoryAt(memory, image_base, address, cave_bytes) orelse return null;
    if (!std.mem.eql(u8, bytes[0..5], &.{ 0x83, 0xF8, 0x05, 0x0F, 0x86 })) return null;
    if (!std.mem.eql(u8, bytes[9..14], &.{ 0x83, 0xF8, 0x09, 0x0F, 0x84 })) return null;
    if (bytes[18] != 0xE9) return null;

    // Unlike the original guard, the cave uses six-byte 0F 8x branches. The
    // displacement is therefore relative to +9 and +18 respectively, not
    // to the opcode address plus the five bytes used by an E9 branch.
    const allow_from_jbe = relativeTarget(address +| 9, std.mem.readInt(i32, bytes[5..9], .little)) orelse return null;
    const allow_from_je = relativeTarget(address +| 18, std.mem.readInt(i32, bytes[14..18], .little)) orelse return null;
    const failure = relativeTarget(address +| 23, std.mem.readInt(i32, bytes[19..23], .little)) orelse return null;
    if (allow_from_jbe != allow_from_je) return null;
    if (!executableAt(ranges, allow_from_jbe, 1) or !executableAt(ranges, failure, 1)) return null;
    if (allow_from_jbe == failure) return null;
    return .{ .allow_address = allow_from_jbe, .failure_address = failure };
}

fn patchedGuardAt(
    memory: []u8,
    image_base: u64,
    ranges: []const AddressRange,
    address: u64,
) ?GuardMatch {
    if (!executableAt(ranges, address, guard_bytes)) return null;
    const bytes = memoryAt(memory, image_base, address, guard_bytes) orelse return null;
    if (!prefixMatches(bytes, address)) return null;
    if (bytes[21] != 0xE9 or bytes[26] != 0x90) return null;
    const cave = rel32Target(address + 21, std.mem.readInt(i32, bytes[22..26], .little)) orelse return null;
    const cave_targets = patchedCaveTargets(memory, image_base, ranges, cave) orelse return null;
    const allow = address +| guard_bytes_u64;
    if (cave_targets.allow_address != allow) return null;
    return .{ .address = address, .allow_address = allow, .failure_address = cave_targets.failure_address };
}

fn symbolInRange(index: ?*const pe_symbols.Index, address: u64, length: usize) bool {
    const symbols = index orelse return false;
    for (0..length) |offset| {
        if (symbols.hasExactAddress(address +| @as(u64, @intCast(offset)))) return true;
    }
    return false;
}

fn tooNearTarget(address: u64, target: u64, distance: u64) bool {
    const low = target -| distance;
    const high = target +| distance;
    return address >= low and address < high;
}

fn findOriginalGuard(
    memory: []u8,
    image_base: u64,
    ranges: []const AddressRange,
    target: u64,
    scan_limit: usize,
) struct { match: ?GuardMatch, count: usize } {
    const remaining = memoryRemainder(memory, image_base, target) orelse return .{ .match = null, .count = 0 };
    const scan_bytes = remaining[0..@min(scan_limit, remaining.len)];
    var found: ?GuardMatch = null;
    var count: usize = 0;
    if (scan_bytes.len < guard_bytes) return .{ .match = null, .count = 0 };
    for (0..scan_bytes.len - guard_bytes + 1) |offset| {
        const address = target +| @as(u64, @intCast(offset));
        if (originalGuardAt(memory, image_base, ranges, address)) |candidate| {
            found = candidate;
            count += 1;
        }
    }
    return .{ .match = found, .count = count };
}

fn findPatchedGuard(
    memory: []u8,
    image_base: u64,
    ranges: []const AddressRange,
    target: u64,
    scan_limit: usize,
) ?GuardMatch {
    const remaining = memoryRemainder(memory, image_base, target) orelse return null;
    const scan_bytes = remaining[0..@min(scan_limit, remaining.len)];
    if (scan_bytes.len < guard_bytes) return null;
    for (0..scan_bytes.len - guard_bytes + 1) |offset| {
        if (patchedGuardAt(memory, image_base, ranges, target +| @as(u64, @intCast(offset)))) |candidate| return candidate;
    }
    return null;
}

fn findCodeCave(
    memory: []u8,
    image_base: u64,
    ranges: []const AddressRange,
    target: u64,
    options: Options,
) ?u64 {
    for (ranges) |range| {
        const max_usize_as_u64: u64 = @intCast(std.math.maxInt(usize));
        const range_length: usize = @intCast(@min(range.length, max_usize_as_u64));
        const bytes = memoryAt(memory, image_base, range.base, range_length) orelse continue;
        var run_start: usize = 0;
        var run_length: usize = 0;
        for (bytes, 0..) |byte, offset| {
            if (byte == 0x90 or byte == 0xCC) {
                if (run_length == 0) run_start = offset;
                run_length += 1;
            } else {
                run_start = offset + 1;
                run_length = 0;
            }
            if (run_length < cave_bytes) continue;
            const first_candidate = run_start;
            const last_candidate = offset + 1 - cave_bytes;
            var candidate = first_candidate;
            while (candidate <= last_candidate) : (candidate += 1) {
                const address = range.base +| @as(u64, @intCast(candidate));
                if (tooNearTarget(address, target, options.target_exclusion_distance)) continue;
                if (symbolInRange(options.symbol_index, address, cave_bytes)) continue;
                return address;
            }
        }
    }
    return null;
}

fn buildCave(cave_address: u64, allow_address: u64, failure_address: u64) ?[cave_bytes]u8 {
    var result: [cave_bytes]u8 = undefined;
    @memset(&result, 0xCC);
    result[0..3].* = .{ 0x83, 0xF8, 0x05 }; // cmp eax, 5
    result[3..5].* = .{ 0x0F, 0x86 }; // jbe allow
    const allow_disp = relative32(cave_address + 9, allow_address) orelse return null;
    std.mem.writeInt(i32, result[5..9], allow_disp, .little);
    result[9..12].* = .{ 0x83, 0xF8, 0x09 }; // cmp eax, 9
    result[12..14].* = .{ 0x0F, 0x84 }; // je allow
    const rectangle_disp = relative32(cave_address + 18, allow_address) orelse return null;
    std.mem.writeInt(i32, result[14..18], rectangle_disp, .little);
    result[18] = 0xE9; // jmp original failure path
    const failure_disp = relative32(cave_address + 23, failure_address) orelse return null;
    std.mem.writeInt(i32, result[19..23], failure_disp, .little);
    return result;
}

/// Return whether the value in Xenia's `host_vertex_shader_type` guard should
/// be admitted after this patch.  This is also the semantic test oracle for
/// the machine-code cave: ordinary values 0..6, point expansion 9, and
/// rectangle expansion 10 are accepted; the mem-export compute value 7, the
/// reserved value 8, and all values above 10 remain rejected.
pub fn admitsHostVertexShaderType(value: u32) bool {
    return value <= 6 or value == 9 or value == 10;
}

/// Apply the narrowly scoped IssueDraw admission repair to a loaded PE image.
/// The caller must invoke this after copying the PE sections and before the
/// first guest instruction is decoded.
pub fn apply(
    memory: []u8,
    image_base: u64,
    executable_ranges: []const AddressRange,
    options: Options,
) Result {
    const target = options.issue_draw_address orelse return .{ .status = .missing_symbol };
    if (!executableAt(executable_ranges, target, guard_bytes)) {
        return .{ .status = .target_not_executable, .target_address = target };
    }

    if (findPatchedGuard(memory, image_base, executable_ranges, target, options.scan_limit)) |patched| {
        return .{
            .status = .already_applied,
            .target_address = target,
            .guard_address = patched.address,
            .allow_address = patched.allow_address,
            .failure_address = patched.failure_address,
        };
    }

    const found = findOriginalGuard(memory, image_base, executable_ranges, target, options.scan_limit);
    if (found.count == 0 or found.match == null) {
        return .{ .status = .guard_not_found, .target_address = target };
    }
    if (found.count != 1) {
        return .{ .status = .ambiguous_guard, .target_address = target };
    }
    const guard = found.match.?;
    const cave_address = findCodeCave(memory, image_base, executable_ranges, target, options) orelse {
        return .{
            .status = .no_code_cave,
            .target_address = target,
            .guard_address = guard.address,
            .allow_address = guard.allow_address,
            .failure_address = guard.failure_address,
        };
    };
    const detour_disp = relative32(guard.address + 21 +| @as(u64, @intCast(detour_bytes - 1)), cave_address) orelse {
        return .{
            .status = .relative_branch_out_of_range,
            .target_address = target,
            .guard_address = guard.address,
            .cave_address = cave_address,
            .allow_address = guard.allow_address,
            .failure_address = guard.failure_address,
        };
    };
    const cave = buildCave(cave_address, guard.allow_address, guard.failure_address) orelse {
        return .{
            .status = .relative_branch_out_of_range,
            .target_address = target,
            .guard_address = guard.address,
            .cave_address = cave_address,
            .allow_address = guard.allow_address,
            .failure_address = guard.failure_address,
        };
    };
    const cave_memory = memoryAt(memory, image_base, cave_address, cave_bytes) orelse unreachable;
    @memcpy(cave_memory, cave[0..]);

    var detour: [detour_bytes]u8 = .{ 0xE9, 0, 0, 0, 0, 0x90 };
    std.mem.writeInt(i32, detour[1..5], detour_disp, .little);
    const detour_memory = memoryAt(memory, image_base, guard.address + 21, detour_bytes) orelse unreachable;
    @memcpy(detour_memory, detour[0..]);
    return .{
        .status = .applied,
        .target_address = target,
        .guard_address = guard.address,
        .cave_address = cave_address,
        .allow_address = guard.allow_address,
        .failure_address = guard.failure_address,
    };
}

test "IssueDraw patch admits rectangle fallback without admitting reserved types" {
    var memory: [0x1000]u8 = [_]u8{0x41} ** 0x1000;
    const image_base = 0x1000;
    const target = 0x1100;
    const failure = 0x1300;
    const cave = 0x1800;
    const target_range = AddressRange{ .base = 0x1000, .length = 0x500 };
    const cave_range = AddressRange{ .base = cave, .length = 0x100 };
    @memset(memory[0x800..0x900], 0xCC);
    const bytes = memory[0x100..0x11b];
    bytes[0..7].* = .{ 0x8B, 0x84, 0x24, 0xF0, 0x00, 0x00, 0x00 };
    bytes[7..9].* = .{ 0x85, 0xC0 };
    bytes[9..11].* = .{ 0x74, 0x10 };
    bytes[11..14].* = .{ 0x83, 0xF8, 0x09 };
    bytes[14..16].* = .{ 0x74, 0x0B };
    bytes[16..18].* = .{ 0xFF, 0xC8 };
    bytes[18..21].* = .{ 0x83, 0xF8, 0x05 };
    bytes[21..23].* = .{ 0x0F, 0x87 };
    const failure_disp: i32 = @intCast(@as(i64, failure) - @as(i64, target + guard_bytes));
    std.mem.writeInt(i32, bytes[23..27], failure_disp, .little);
    memory[0x11b..0x11e].* = .{ 0x4C, 0x89, 0xE9 };

    const ranges = [_]AddressRange{ target_range, cave_range };
    const result = apply(&memory, image_base, &ranges, .{
        .issue_draw_address = target,
        .target_exclusion_distance = 0,
    });
    try std.testing.expectEqual(Status.applied, result.status);
    try std.testing.expectEqual(cave, result.cave_address);
    try std.testing.expect(admitsHostVertexShaderType(0));
    try std.testing.expect(admitsHostVertexShaderType(6));
    try std.testing.expect(!admitsHostVertexShaderType(7));
    try std.testing.expect(!admitsHostVertexShaderType(8));
    try std.testing.expect(admitsHostVertexShaderType(9));
    try std.testing.expect(admitsHostVertexShaderType(10));
    try std.testing.expect(!admitsHostVertexShaderType(11));

    const second = apply(&memory, image_base, &ranges, .{
        .issue_draw_address = target,
        .target_exclusion_distance = 0,
    });
    try std.testing.expectEqual(Status.already_applied, second.status);
    try std.testing.expectEqual(failure, second.failure_address);
    const patched = patchedGuardAt(&memory, image_base, &ranges, target) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(target + guard_bytes, patched.allow_address);
    try std.testing.expectEqual(failure, patched.failure_address);
}

test "IssueDraw patch refuses an unrecognized guard" {
    var memory: [0x400]u8 = [_]u8{0x41} ** 0x400;
    memory[0x100..0x11b].* = [_]u8{0x90} ** 0x1b;
    const ranges = [_]AddressRange{.{ .base = 0x1000, .length = memory.len }};
    const result = apply(&memory, 0x1000, &ranges, .{ .issue_draw_address = 0x1100 });
    try std.testing.expectEqual(Status.guard_not_found, result.status);
}

test "IssueDraw patch refuses an image without executable padding" {
    var memory: [0x400]u8 = [_]u8{0x41} ** 0x400;
    const target: u64 = 0x1100;
    const bytes = memory[0x100..0x11b];
    bytes[0..7].* = .{ 0x8B, 0x84, 0x24, 0xF0, 0x00, 0x00, 0x00 };
    bytes[7..9].* = .{ 0x85, 0xC0 };
    bytes[9..11].* = .{ 0x74, 0x10 };
    bytes[11..14].* = .{ 0x83, 0xF8, 0x09 };
    bytes[14..16].* = .{ 0x74, 0x0B };
    bytes[16..18].* = .{ 0xFF, 0xC8 };
    bytes[18..21].* = .{ 0x83, 0xF8, 0x05 };
    bytes[21..23].* = .{ 0x0F, 0x87 };
    std.mem.writeInt(i32, bytes[23..27], 0x100, .little);
    const ranges = [_]AddressRange{.{ .base = 0x1000, .length = memory.len }};
    const result = apply(&memory, 0x1000, &ranges, .{ .issue_draw_address = target });
    try std.testing.expectEqual(Status.no_code_cave, result.status);
}
