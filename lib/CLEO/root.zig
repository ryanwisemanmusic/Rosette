const std = @import("std");

pub const types = @import("types.zig");
pub const wide = @import("wide.zig");
pub const neon = @import("NEON/root.zig");
pub const cpu = @import("cpu.zig");
pub const ops = @import("ops.zig");
pub const registry = @import("registry.zig");
pub const SSE = @import("SSE/root.zig");
pub const AVX = registry.AVX;
pub const AVX2 = registry.AVX2;
pub const AVX512F = registry.AVX512F;
pub const AVX512DQ = registry.AVX512DQ;
pub const AVX512BW = registry.AVX512BW;
pub const AVX512BF16 = registry.AVX512BF16;
pub const VAES = registry.VAES;
pub const SYSTEM = registry.SYSTEM;

pub fn validateAll() void {
    registry.validateAll() catch unreachable;
}

pub fn validateRuntimeAbi(runtime_abi: anytype) void {
    registry.validateRuntimeAbi(runtime_abi);
}

pub fn exerciseAll() !void {
    try registry.validateAll();
    try exerciseAvx256();
    try exerciseAvx512();
    try exerciseAvx2Moves();
    try exerciseMinMaxDotAndCrypto();
    try exerciseSystemWidths();
}

fn exerciseAvx256() !void {
    const features = types.FeatureSet.cleoEmulated();
    const lhs = wide.fromArray(256, f32, .{ 1, 2, 3, 4, 5, 6, 7, 8 });
    const rhs = wide.fromArray(256, f32, .{ 10, 20, 30, 40, 50, 60, 70, 80 });
    const add = try AVX.ADDPS.execute(256, lhs, rhs, features);
    const add_lanes = wide.toArray(256, f32, add);
    try std.testing.expectEqual(@as(f32, 11), add_lanes[0]);
    try std.testing.expectEqual(@as(f32, 88), add_lanes[7]);

    const addsub = try AVX.ADDSUBPS.execute(256, lhs, rhs, features);
    const addsub_lanes = wide.toArray(256, f32, addsub);
    try std.testing.expectEqual(@as(f32, -9), addsub_lanes[0]);
    try std.testing.expectEqual(@as(f32, 22), addsub_lanes[1]);

    const blend = try AVX.BLENDPS.executeImmediate(256, lhs, rhs, 0b10101010, features);
    const blend_lanes = wide.toArray(256, f32, blend);
    try std.testing.expectEqual(@as(f32, 1), blend_lanes[0]);
    try std.testing.expectEqual(@as(f32, 20), blend_lanes[1]);

    const selector = wide.fromArray(256, u32, .{ 0x80000000, 0, 0, 0x80000000, 0, 0, 0x80000000, 0 });
    const blendv = try AVX.BLENDVPS.executeVariable(256, lhs, rhs, selector, features);
    const blendv_lanes = wide.toArray(256, f32, blendv);
    try std.testing.expectEqual(@as(f32, 10), blendv_lanes[0]);
    try std.testing.expectEqual(@as(f32, 40), blendv_lanes[3]);

    const shuffle = try AVX.SHUFPS.executeImmediate(256, lhs, rhs, 0b01_00_11_10, features);
    const shuffle_lanes = wide.toArray(256, f32, shuffle);
    try std.testing.expectEqual(@as(f32, 3), shuffle_lanes[0]);
    try std.testing.expectEqual(@as(f32, 50), shuffle_lanes[6]);

    const dot = try AVX.DPPS.executeImmediate(256, lhs, rhs, 0b1111_0001, features);
    const dot_lanes = wide.toArray(256, f32, dot);
    try std.testing.expectEqual(@as(f32, 300), dot_lanes[0]);
    try std.testing.expectEqual(@as(f32, 1740), dot_lanes[4]);
}

fn exerciseAvx512() !void {
    const features = types.FeatureSet.cleoEmulated();
    const lhs = wide.fromArray(512, f64, .{ 1, 2, 3, 4, 5, 6, 7, 8 });
    const rhs = wide.fromArray(512, f64, .{ 8, 7, 6, 5, 4, 3, 2, 1 });
    const sum = try AVX512F.ADDPD.execute(512, lhs, rhs, features);
    try neon.block128.validateRoundTrip(512, sum);
    const lanes = wide.toArray(512, f64, sum);
    try std.testing.expectEqual(@as(f64, 9), lanes[0]);
    try std.testing.expectEqual(@as(f64, 9), lanes[7]);

    const merge = wide.fromArray(512, f64, .{ 100, 100, 100, 100, 100, 100, 100, 100 });
    const masked = try AVX512F.ADDPD.executeMasked(512, merge, lhs, rhs, 0b01010101, .merge, features);
    const masked_lanes = wide.toArray(512, f64, masked);
    try std.testing.expectEqual(@as(f64, 9), masked_lanes[0]);
    try std.testing.expectEqual(@as(f64, 100), masked_lanes[1]);

    const shuffled = try AVX512F.SHUFPD.executeMaskedImmediate(512, merge, lhs, rhs, 0b10_01_10_01, 0b01010101, .merge, features);
    const shuffled_lanes = wide.toArray(512, f64, shuffled);
    try std.testing.expectEqual(@as(f64, 2), shuffled_lanes[0]);
    try std.testing.expectEqual(@as(f64, 100), shuffled_lanes[1]);
    try std.testing.expectEqual(@as(f64, 7), shuffled_lanes[6]);

    const a = wide.fromArray(512, u32, .{ 0x80000000, 0, 0xFFFFFFFF, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 });
    const b = wide.fromArray(512, u32, .{ 0, 0x80000000, 1, 1, 2, 3, 4, 5, 0x80000000, 7, 8, 9, 10, 11, 12, 13 });
    const x = try AVX512DQ.XORPS.execute(512, a, b, features);
    const mask = wide.movMaskPS(512, x);
    try std.testing.expect((mask & 0b11) == 0b11);
}

fn exerciseAvx2Moves() !void {
    const features = types.FeatureSet.cleoEmulated();
    const value = wide.Wide(256).splatByte(0xA5);
    const moved = try AVX2.MOVDQU.move(256, value, features);
    try std.testing.expect(value.equal(moved));

    var aligned: [64]u8 align(64) = [_]u8{0x55} ** 64;
    const loaded = try ops.loadForInstruction(256, AVX2.MOVDQA.meta, aligned[0..], features);
    try std.testing.expectEqual(@as(u8, 0x55), loaded.bytes[0]);
}

fn exerciseMinMaxDotAndCrypto() !void {
    const features = types.FeatureSet.cleoEmulated();

    const signed_lhs = wide.fromArray(256, i8, .{ -3, 4, -1, 8, 12, -9, 0, 7, 1, 2, 3, 4, -5, -6, 7, 8, 9, -10, 11, 12, 13, 14, -15, 16, 17, 18, 19, -20, 21, 22, 23, 24 });
    const signed_rhs = wide.fromArray(256, i8, .{ 3, -4, 2, 7, -12, 9, 1, -7, 2, 1, 4, 3, 5, -7, 8, 7, -9, 10, 10, 13, 12, 15, 15, -16, 16, 19, 18, 20, -21, 21, 24, 23 });
    const mins = try AVX2.PMINSB.execute(256, signed_lhs, signed_rhs, features);
    const min_lanes = wide.toArray(256, i8, mins);
    try std.testing.expectEqual(@as(i8, -3), min_lanes[0]);
    try std.testing.expectEqual(@as(i8, -4), min_lanes[1]);

    const unsigned_lhs = wide.fromArray(512, u32, .{ 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160 });
    const unsigned_rhs = wide.fromArray(512, u32, .{ 11, 19, 31, 39, 51, 59, 71, 79, 91, 99, 111, 119, 131, 139, 151, 159 });
    const max_merge = wide.Wide(512).splatByte(0xAA);
    const maxed = try AVX512F.PMAXUD.executeMasked(512, max_merge, unsigned_lhs, unsigned_rhs, 0b01010101, .merge, features);
    const max_lanes = wide.toArray(512, u32, maxed);
    try std.testing.expectEqual(@as(u32, 11), max_lanes[0]);
    try std.testing.expectEqual(@as(u32, 0xAAAAAAAA), max_lanes[1]);

    const acc = wide.fromArray(512, f32, .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 });
    const ones = [_]u16{0x3f80} ** 32;
    const twos = [_]u16{0x4000} ** 32;
    const bf16 = try AVX512BF16.VDPBF16PS.executeAccumulate(512, acc, wide.fromArray(512, u16, ones), wide.fromArray(512, u16, twos), features);
    const bf16_lanes = wide.toArray(512, f32, bf16);
    try std.testing.expectEqual(@as(f32, 5), bf16_lanes[0]);
    try std.testing.expectEqual(@as(f32, 20), bf16_lanes[15]);

    const aes_state = wide.Wide(512).zero();
    const aes_key = wide.Wide(512).zero();
    const aes = try VAES.AESENCLAST.execute(512, aes_state, aes_key, features);
    const aes_lanes = wide.toArray(512, u8, aes);
    try std.testing.expectEqual(@as(u8, 0x63), aes_lanes[0]);
    try std.testing.expectEqual(@as(u8, 0x63), aes_lanes[48]);
}

fn exerciseSystemWidths() !void {
    const features = types.FeatureSet.cleoEmulated();
    const key = wide.Wide(256).splatByte(0xCC);
    const moved_key = try SYSTEM.LOADIWKEY.move(256, key, features);
    try std.testing.expect(key.equal(moved_key));

    const line = wide.Wide(512).splatByte(0x11);
    const copied = try SYSTEM.MOVDIR64B.move(512, line, features);
    try std.testing.expect(line.equal(copied));

    var lanes: [32]u32 = undefined;
    for (0..lanes.len) |i| lanes[i] = @intCast(i);
    const thousand_twenty_four = wide.fromArray(1024, u32, lanes);
    try neon.block128.validateRoundTrip(1024, thousand_twenty_four);
}

pub export fn cleo_host_feature_mask() u64 {
    return cpu.hostFeatureMask();
}

pub export fn cleo_emulated_feature_mask() u64 {
    return cpu.emulatedFeatureMask();
}

pub export fn cleo_wide_instruction_count() usize {
    return registry.tableCount();
}

pub export fn cleo_validate_registry() c_int {
    registry.validateAll() catch return -1;
    return 0;
}

test "CLEO root validates wide AVX lowering layer" {
    try std.testing.expectEqual(@as(usize, 127), registry.tableCount());
    validateAll();
    try exerciseAll();
}
