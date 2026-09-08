//! EVEX/AVX-512 execution shared by the Mach-O and ELF interpreters.
//!
//! The Windows Xenia binary uses EVEX for its optimized integer and memory
//! helpers.  Keeping the implementation here prevents the two processor
//! backends from slowly acquiring different register-extension or masking
//! rules.  The state object is intentionally `anytype`: both backends expose
//! the same architectural vector/memory surface, while their fault handling
//! remains backend-specific.

const std = @import("std");
const x64_decoder = @import("x64_decoder");
const exit_diagnostics = @import("exit_diagnostics");

const Op = x64_decoder.Op;
const DecodedInsn = x64_decoder.DecodedInsn;
const Size = x64_decoder.OperandSize;

fn vectorBytes(d: DecodedInsn) usize {
    return if (d.vector_512) 64 else if (d.vector_256) 32 else 16;
}

fn elementBytes(d: DecodedInsn) usize {
    if (d.evex_element_bytes != 0) return d.evex_element_bytes;
    return switch (d.op) {
        .vpcmpb, .vpshufb, .vpalignr => 1,
        .vpmaddubsw => 2,
        .vpsadbw => 8,
        .vpaddd, .vpmaddwd, .vpdpbusd, .vpslld, .vpshufd => 4,
        .vpshuflw, .vpshufhw => 2,
        .vpmovqd => 4,
        .vextracti32x4 => 4,
        .vextracti64x4 => 8,
        else => 1,
    };
}

fn readVectorRegister(self: anytype, index: u8) [64]u8 {
    var result = [_]u8{0} ** 64;
    @memcpy(result[0..16], self.xmm[index][0..16]);
    @memcpy(result[16..32], self.ymm_hi[index][0..16]);
    @memcpy(result[32..64], self.zmm_hi[index][0..32]);
    return result;
}

fn writeVectorRegister(self: anytype, index: u8, value: [64]u8, count: usize) void {
    // EVEX instructions always zero the part of the architectural ZMM
    // register above their encoded vector length.  Clearing all three backing
    // pieces first also makes scalar VMOVD and narrow VPMOV forms correct.
    @memset(&self.xmm[index], 0);
    @memset(&self.ymm_hi[index], 0);
    @memset(&self.zmm_hi[index], 0);
    const low = @min(count, 16);
    @memcpy(self.xmm[index][0..low], value[0..low]);
    if (count > 16) {
        const high = @min(count - 16, 16);
        @memcpy(self.ymm_hi[index][0..high], value[16 .. 16 + high]);
    }
    if (count > 32) {
        const top = @min(count - 32, 32);
        @memcpy(self.zmm_hi[index][0..top], value[32 .. 32 + top]);
    }
}

fn readVectorMemory(self: anytype, d: DecodedInsn, count: usize) [64]u8 {
    var result = [_]u8{0} ** 64;
    var offset: usize = 0;
    while (offset < count) : (offset += 16) {
        const width = @min(@as(usize, 16), count - offset);
        const chunk = self.readMem128(d.addr +| offset);
        @memcpy(result[offset .. offset + width], chunk[0..width]);
        if (self.terminated) return result;
    }
    return result;
}

fn scalarSize(byte_count: usize) Size {
    return switch (byte_count) {
        1 => .bits8,
        2 => .bits16,
        4 => .bits32,
        8 => .bits64,
        else => unreachable,
    };
}

/// Read only the memory lanes enabled by an EVEX mask. A masked-off source
/// lane is architecturally not accessed, which is important when a vector
/// operation crosses a guard page or a lazily materialized guest mapping.
fn readMaskedVectorMemory(self: anytype, d: DecodedInsn, count: usize, mask_bytes: usize) [64]u8 {
    var result = [_]u8{0} ** 64;
    for (0..count / mask_bytes) |lane| {
        if (!maskActive(self, d, lane)) continue;
        const offset = lane * mask_bytes;
        const value = self.readMemVal(d.addr +| offset, scalarSize(mask_bytes));
        if (self.terminated) return result;
        var encoded = [_]u8{0} ** 8;
        std.mem.writeInt(u64, @ptrCast(&encoded[0]), value, .little);
        @memcpy(result[offset .. offset + mask_bytes], encoded[0..mask_bytes]);
    }
    return result;
}

fn readBroadcast(
    self: anytype,
    d: DecodedInsn,
    count: usize,
    scalar_width: usize,
    mask_bytes: usize,
) [64]u8 {
    var result = [_]u8{0} ** 64;
    const scalar = self.readMemVal(d.addr, scalarSize(scalar_width));
    if (self.terminated) return result;
    var encoded = [_]u8{0} ** 8;
    std.mem.writeInt(u64, @ptrCast(&encoded[0]), scalar, .little);
    for (0..count / mask_bytes) |lane| {
        if (d.opmask != 0 and !maskActive(self, d, lane)) continue;
        const offset = lane * mask_bytes;
        for (0..mask_bytes) |byte| {
            result[offset + byte] = encoded[byte % scalar_width];
        }
    }
    return result;
}

fn readRmOperand(
    self: anytype,
    d: DecodedInsn,
    count: usize,
    source_bytes: usize,
    mask_bytes: usize,
) [64]u8 {
    if (d.is_reg_form) return readVectorRegister(self, d.xmm_src2);
    if (d.evex_broadcast) return readBroadcast(self, d, count, source_bytes, mask_bytes);
    if (d.opmask != 0) return readMaskedVectorMemory(self, d, count, mask_bytes);
    return readVectorMemory(self, d, count);
}

fn maskActive(self: anytype, d: DecodedInsn, lane: usize) bool {
    if (d.opmask == 0) return true;
    return ((self.k[d.opmask] >> @as(u6, @intCast(lane))) & 1) != 0;
}

fn maskedVector(
    self: anytype,
    d: DecodedInsn,
    computed: [64]u8,
    old: [64]u8,
    count: usize,
    bytes_per_element: usize,
) [64]u8 {
    var result = old;
    const lane_count = count / bytes_per_element;
    for (0..lane_count) |lane| {
        const offset = lane * bytes_per_element;
        if (maskActive(self, d, lane)) {
            @memcpy(result[offset .. offset + bytes_per_element], computed[offset .. offset + bytes_per_element]);
        } else if (d.zero_mask) {
            @memset(result[offset .. offset + bytes_per_element], 0);
        }
    }
    return result;
}

fn writeVectorMemory(self: anytype, d: DecodedInsn, value: [64]u8, count: usize, bytes_per_element: usize) void {
    if (d.opmask != 0) {
        // Do not read or rewrite masked-off lanes. Besides matching x86
        // masked-store semantics, this avoids turning a harmless masked store
        // into a fault on an inaccessible destination lane.
        for (0..count / bytes_per_element) |lane| {
            if (!maskActive(self, d, lane)) continue;
            const offset = lane * bytes_per_element;
            const val = switch (bytes_per_element) {
                1 => value[offset],
                2 => std.mem.readInt(u16, @ptrCast(&value[offset]), .little),
                4 => std.mem.readInt(u32, @ptrCast(&value[offset]), .little),
                8 => std.mem.readInt(u64, @ptrCast(&value[offset]), .little),
                else => unreachable,
            };
            self.writeMemVal(d.addr +| offset, scalarSize(bytes_per_element), val);
            if (self.terminated) return;
        }
        return;
    }
    var offset: usize = 0;
    while (offset < count) : (offset += 16) {
        const width = @min(@as(usize, 16), count - offset);
        var chunk = [_]u8{0} ** 16;
        @memcpy(chunk[0..width], value[offset .. offset + width]);
        self.writeMem128(d.addr +| offset, chunk);
        if (self.terminated) return;
    }
}

fn isMoveLoad(op: Op) bool {
    return switch (op) {
        .vmovdqu_ymm_mem, .vmovdqa_ymm_mem, .vmovups_ymm_mem => true,
        else => false,
    };
}

fn isMoveStore(op: Op) bool {
    return switch (op) {
        .vmovdqu_mem_ymm, .vmovdqa_mem_ymm, .vmovups_mem_ymm => true,
        else => false,
    };
}

fn executeMove(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const bytes_per_element = elementBytes(d);
    if (isMoveLoad(d.op)) {
        const loaded = if (d.opmask == 0)
            readVectorMemory(self, d, count)
        else
            readMaskedVectorMemory(self, d, count, bytes_per_element);
        if (self.terminated) return;
        const old = readVectorRegister(self, d.xmm_dst);
        writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, loaded, old, count, bytes_per_element), count);
        return;
    }
    if (d.is_reg_form) {
        const source = readVectorRegister(self, d.xmm_src2);
        const old = readVectorRegister(self, d.xmm_dst);
        writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, source, old, count, bytes_per_element), count);
        return;
    }
    if (isMoveStore(d.op)) {
        const source = readVectorRegister(self, d.xmm_dst);
        writeVectorMemory(self, d, source, count, bytes_per_element);
    }
}

fn executeVpxor(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const lhs = readVectorRegister(self, d.xmm_src);
    const rhs = readRmOperand(self, d, count, 1, 1);
    var computed = [_]u8{0} ** 64;
    for (0..count) |i| computed[i] = lhs[i] ^ rhs[i];
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 1), count);
}

fn executeVpaddd(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const lhs = readVectorRegister(self, d.xmm_src);
    const rhs = readRmOperand(self, d, count, 4, 4);
    var computed = [_]u8{0} ** 64;
    for (0..count / 4) |lane| {
        const offset = lane * 4;
        const result = std.mem.readInt(u32, @ptrCast(&lhs[offset]), .little) +%
            std.mem.readInt(u32, @ptrCast(&rhs[offset]), .little);
        std.mem.writeInt(u32, @ptrCast(&computed[offset]), result, .little);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 4), count);
}

fn readUnaryOperand(self: anytype, d: DecodedInsn, count: usize, mask_bytes: usize) [64]u8 {
    if (d.is_reg_form) return readVectorRegister(self, d.xmm_src);
    if (d.opmask != 0) return readMaskedVectorMemory(self, d, count, mask_bytes);
    return readVectorMemory(self, d, count);
}

fn clampI64(value: i64, minimum: i64, maximum: i64) i64 {
    return if (value < minimum) minimum else if (value > maximum) maximum else value;
}

fn writePackedValue(buffer: *[64]u8, offset: usize, width: usize, value: i64, signed: bool) void {
    switch (width) {
        1 => {
            if (signed) {
                buffer[offset] = @bitCast(@as(i8, @intCast(value)));
            } else {
                buffer[offset] = @intCast(value);
            }
        },
        2 => {
            if (signed) {
                std.mem.writeInt(u16, @ptrCast(&buffer[offset]), @bitCast(@as(i16, @intCast(value))), .little);
            } else {
                std.mem.writeInt(u16, @ptrCast(&buffer[offset]), @intCast(value), .little);
            }
        },
        4 => {
            if (signed) {
                std.mem.writeInt(u32, @ptrCast(&buffer[offset]), @bitCast(@as(i32, @intCast(value))), .little);
            } else {
                std.mem.writeInt(u32, @ptrCast(&buffer[offset]), @intCast(value), .little);
            }
        },
        8 => std.mem.writeInt(u64, @ptrCast(&buffer[offset]), @bitCast(value), .little),
        else => unreachable,
    }
}

fn packedValue(source: [64]u8, offset: usize, width: usize, signed: bool) i64 {
    return switch (width) {
        1 => if (signed) @as(i64, @as(i8, @bitCast(source[offset]))) else @as(i64, source[offset]),
        2 => if (signed)
            @as(i64, std.mem.readInt(i16, @ptrCast(&source[offset]), .little))
        else
            @as(i64, std.mem.readInt(u16, @ptrCast(&source[offset]), .little)),
        4 => if (signed)
            @as(i64, std.mem.readInt(i32, @ptrCast(&source[offset]), .little))
        else
            @as(i64, std.mem.readInt(u32, @ptrCast(&source[offset]), .little)),
        8 => @bitCast(std.mem.readInt(u64, @ptrCast(&source[offset]), .little)),
        else => unreachable,
    };
}

fn packShape(op: Op) struct { input_bytes: usize, output_bytes: usize, signed: bool } {
    return switch (op) {
        .vpacksswb => .{ .input_bytes = 2, .output_bytes = 1, .signed = true },
        .vpackuswb => .{ .input_bytes = 2, .output_bytes = 1, .signed = false },
        .vpackssdw => .{ .input_bytes = 4, .output_bytes = 2, .signed = true },
        .vpackusdw => .{ .input_bytes = 4, .output_bytes = 2, .signed = false },
        else => unreachable,
    };
}

fn executeVpack(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const shape = packShape(d.op);
    const lhs = readVectorRegister(self, d.xmm_src);
    const rhs = readRmOperand(self, d, count, shape.input_bytes, shape.output_bytes);
    var computed = [_]u8{0} ** 64;
    const minimum: i64 = if (shape.signed) switch (shape.output_bytes) {
        1 => -128,
        2 => -32768,
        else => unreachable,
    } else 0;
    const maximum: i64 = if (shape.signed) switch (shape.output_bytes) {
        1 => 127,
        2 => 32767,
        else => unreachable,
    } else switch (shape.output_bytes) {
        1 => 255,
        2 => 65535,
        else => unreachable,
    };
    for (0..count / 16) |block| {
        const source_offset = block * 16;
        const destination_offset = block * 16;
        const source_lanes = 16 / shape.input_bytes;
        for (0..source_lanes) |lane| {
            const first = packedValue(lhs, source_offset + lane * shape.input_bytes, shape.input_bytes, true);
            const second = packedValue(rhs, source_offset + lane * shape.input_bytes, shape.input_bytes, true);
            const first_offset = destination_offset + lane * shape.output_bytes;
            const second_offset = destination_offset + (source_lanes + lane) * shape.output_bytes;
            writePackedValue(&computed, first_offset, shape.output_bytes, clampI64(first, minimum, maximum), shape.signed);
            writePackedValue(&computed, second_offset, shape.output_bytes, clampI64(second, minimum, maximum), shape.signed);
        }
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, shape.output_bytes), count);
}

fn absShape(op: Op) struct { width: usize } {
    return switch (op) {
        .vpabsb => .{ .width = 1 },
        .vpabsw => .{ .width = 2 },
        .vpabsd => .{ .width = 4 },
        else => unreachable,
    };
}

fn executeVpackedAbs(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const width = absShape(d.op).width;
    const source = readUnaryOperand(self, d, count, width);
    var computed = [_]u8{0} ** 64;
    for (0..count / width) |lane| {
        const offset = lane * width;
        const value = packedValue(source, offset, width, true);
        writePackedValue(&computed, offset, width, if (value < 0) -%value else value, true);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, width), count);
}

fn signShape(op: Op) struct { width: usize } {
    return switch (op) {
        .vpsignb => .{ .width = 1 },
        .vpsignw => .{ .width = 2 },
        .vpsignd => .{ .width = 4 },
        else => unreachable,
    };
}

fn executeVpackedSign(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const width = signShape(d.op).width;
    const magnitude = readVectorRegister(self, d.xmm_src);
    const signs = readRmOperand(self, d, count, width, width);
    var computed = [_]u8{0} ** 64;
    for (0..count / width) |lane| {
        const offset = lane * width;
        const value = packedValue(magnitude, offset, width, true);
        const sign = packedValue(signs, offset, width, true);
        const result = if (sign < 0) -%value else if (sign == 0) 0 else value;
        writePackedValue(&computed, offset, width, result, true);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, width), count);
}

fn wideningShape(op: Op) struct { input_bytes: usize, output_bytes: usize, signed: bool } {
    return switch (op) {
        .vpmovsxbw => .{ .input_bytes = 1, .output_bytes = 2, .signed = true },
        .vpmovsxbd => .{ .input_bytes = 1, .output_bytes = 4, .signed = true },
        .vpmovsxbq => .{ .input_bytes = 1, .output_bytes = 8, .signed = true },
        .vpmovsxwd => .{ .input_bytes = 2, .output_bytes = 4, .signed = true },
        .vpmovsxwq => .{ .input_bytes = 2, .output_bytes = 8, .signed = true },
        .vpmovsxdq => .{ .input_bytes = 4, .output_bytes = 8, .signed = true },
        .vpmovzxbw => .{ .input_bytes = 1, .output_bytes = 2, .signed = false },
        .vpmovzxbd => .{ .input_bytes = 1, .output_bytes = 4, .signed = false },
        .vpmovzxbq => .{ .input_bytes = 1, .output_bytes = 8, .signed = false },
        .vpmovzxwd => .{ .input_bytes = 2, .output_bytes = 4, .signed = false },
        .vpmovzxwq => .{ .input_bytes = 2, .output_bytes = 8, .signed = false },
        .vpmovzxdq => .{ .input_bytes = 4, .output_bytes = 8, .signed = false },
        else => unreachable,
    };
}

fn executeVwiden(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const shape = wideningShape(d.op);
    const source = readUnaryOperand(self, d, count / 2, shape.input_bytes);
    var computed = [_]u8{0} ** 64;
    for (0..count / shape.output_bytes) |lane| {
        const value = packedValue(source, lane * shape.input_bytes, shape.input_bytes, shape.signed);
        writePackedValue(&computed, lane * shape.output_bytes, shape.output_bytes, value, shape.signed);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, shape.output_bytes), count);
}

fn executeVpmuldq(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const lhs = readVectorRegister(self, d.xmm_src);
    const rhs = readRmOperand(self, d, count, 4, 8);
    var computed = [_]u8{0} ** 64;
    for (0..count / 16) |block| {
        const base = block * 16;
        for (0..2) |lane| {
            const offset = base + lane * 8;
            const left: i64 = std.mem.readInt(i32, @ptrCast(&lhs[offset]), .little);
            const right: i64 = std.mem.readInt(i32, @ptrCast(&rhs[offset]), .little);
            std.mem.writeInt(u64, @ptrCast(&computed[offset]), @bitCast(left * right), .little);
        }
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 8), count);
}

fn executeVpermd(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const indexes = readVectorRegister(self, d.xmm_src);
    const values = readRmOperand(self, d, count, 4, 4);
    var computed = [_]u8{0} ** 64;
    const lane_count = count / 4;
    for (0..lane_count) |lane| {
        const index = std.mem.readInt(u32, @ptrCast(&indexes[lane * 4]), .little) % @as(u32, @intCast(lane_count));
        const source_offset = @as(usize, @intCast(index)) * 4;
        @memcpy(computed[lane * 4 ..][0..4], values[source_offset..][0..4]);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 4), count);
}

fn executeVblendps(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const lhs = readVectorRegister(self, d.xmm_src);
    const rhs = readRmOperand(self, d, count, 4, 4);
    var computed = [_]u8{0} ** 64;
    for (0..count / 4) |lane| {
        const source = if (((d.imm >> @as(u6, @intCast(lane))) & 1) != 0) rhs else lhs;
        @memcpy(computed[lane * 4 ..][0..4], source[lane * 4 ..][0..4]);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 4), count);
}

fn executeVshufpd(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const lhs = readVectorRegister(self, d.xmm_src);
    const rhs = readRmOperand(self, d, count, 8, 8);
    var computed = [_]u8{0} ** 64;
    for (0..count / 16) |block| {
        const base = block * 16;
        for (0..2) |lane| {
            const select_rhs = ((d.imm >> @as(u6, @intCast(block * 2 + lane))) & 1) != 0;
            const source = if (select_rhs) rhs else lhs;
            @memcpy(computed[base + lane * 8 ..][0..8], source[base + lane * 8 ..][0..8]);
        }
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 8), count);
}

fn executeVpermilps(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const values = if (d.uses_imm)
        readUnaryOperand(self, d, count, 4)
    else
        readRmOperand(self, d, count, 4, 4);
    const indexes = if (d.uses_imm) [_]u8{0} ** 64 else readVectorRegister(self, d.xmm_src);
    var computed = [_]u8{0} ** 64;
    for (0..count / 16) |block| {
        const base = block * 16;
        for (0..4) |lane| {
            const selector: usize = if (d.uses_imm)
                @as(usize, @intCast((d.imm >> @as(u6, @intCast(lane * 2))) & 3))
            else
                @as(usize, @intCast(std.mem.readInt(u32, @ptrCast(&indexes[base + lane * 4]), .little) & 3));
            @memcpy(computed[base + lane * 4 ..][0..4], values[base + selector * 4 ..][0..4]);
        }
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 4), count);
}

fn broadcastScalar(self: anytype, d: DecodedInsn, width: usize) u64 {
    if (d.is_reg_form) {
        const source = readVectorRegister(self, d.xmm_src);
        return switch (width) {
            2 => std.mem.readInt(u16, @ptrCast(&source[0]), .little),
            4 => std.mem.readInt(u32, @ptrCast(&source[0]), .little),
            8 => std.mem.readInt(u64, @ptrCast(&source[0]), .little),
            else => unreachable,
        };
    }
    return self.readMemVal(d.addr, scalarSize(width));
}

fn executeVpbroadcast(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const width: usize = switch (d.op) {
        .vpbroadcastw => 2,
        .vpbroadcastd => 4,
        .vpbroadcastq => 8,
        else => unreachable,
    };
    const scalar = broadcastScalar(self, d, width);
    if (self.terminated) return;
    var computed = [_]u8{0} ** 64;
    for (0..count / width) |lane| {
        writePackedValue(&computed, lane * width, width, @intCast(scalar), false);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, width), count);
}

fn executeVextractPs(self: anytype, d: DecodedInsn) void {
    const source = readVectorRegister(self, d.xmm_src);
    const offset = (@as(usize, @intCast(d.imm)) & 3) * 4;
    const value = std.mem.readInt(u32, @ptrCast(&source[offset]), .little);
    if (d.is_reg_form) {
        self.setReg(d.dst_reg, .bits32, value);
    } else {
        self.writeMemVal(d.addr, .bits32, value);
    }
}

fn executeVmovnt(self: anytype, d: DecodedInsn) void {
    if (d.is_reg_form) return;
    const source = readVectorRegister(self, d.xmm_src);
    writeVectorMemory(self, d, source, vectorBytes(d), 1);
}

fn executeVmovntdqa(self: anytype, d: DecodedInsn) void {
    if (d.is_reg_form) return;
    const count = vectorBytes(d);
    const loaded = readVectorMemory(self, d, count);
    if (self.terminated) return;
    writeVectorRegister(self, d.xmm_dst, loaded, count);
}

fn stringElement(bytes: [64]u8, index: usize, width: usize, signed: bool) i64 {
    const offset = index * width;
    return packedValue(bytes, offset, width, signed);
}

fn executeVpcmpistri(self: anytype, d: DecodedInsn) void {
    const lhs = readVectorRegister(self, d.xmm_src);
    const rhs = readRmOperand(self, d, 16, 1, 1);
    const control: u8 = @truncate(d.imm);
    const width: usize = if ((control & 1) != 0) 2 else 1;
    const signed = (control & 2) != 0;
    const aggregation: u2 = @truncate((control >> 2) & 3);
    const negate = (control & 0x10) != 0;
    const most_significant = (control & 0x40) != 0;
    const lane_count = 16 / width;
    var lhs_len: usize = lane_count;
    var rhs_len: usize = lane_count;
    for (0..lane_count) |lane| {
        if (stringElement(lhs, lane, width, false) == 0 and lhs_len == lane_count) lhs_len = lane;
        if (stringElement(rhs, lane, width, false) == 0 and rhs_len == lane_count) rhs_len = lane;
    }

    var result: u16 = 0;
    for (0..lhs_len) |left_index| {
        var matched = false;
        switch (aggregation) {
            0 => { // equal-any
                for (0..rhs_len) |right_index| {
                    if (stringElement(lhs, left_index, width, signed) == stringElement(rhs, right_index, width, signed)) {
                        matched = true;
                        break;
                    }
                }
            },
            1 => { // ranges: two adjacent RHS values delimit each range
                var right: usize = 0;
                while (right + 1 < rhs_len) : (right += 2) {
                    const value = stringElement(lhs, left_index, width, signed);
                    const low = stringElement(rhs, right, width, signed);
                    const high = stringElement(rhs, right + 1, width, signed);
                    if (value >= low and value <= high) {
                        matched = true;
                        break;
                    }
                }
            },
            2 => { // equal-each
                matched = left_index < rhs_len and stringElement(lhs, left_index, width, signed) == stringElement(rhs, left_index, width, signed);
            },
            3 => { // equal-ordered, with a conservative substring matcher
                if (left_index + rhs_len <= lhs_len) {
                    matched = true;
                    for (0..rhs_len) |right_index| {
                        if (stringElement(lhs, left_index + right_index, width, signed) != stringElement(rhs, right_index, width, signed)) {
                            matched = false;
                            break;
                        }
                    }
                }
            },
        }
        if (negate) matched = !matched;
        if (matched) result |= @as(u16, 1) << @as(u4, @intCast(left_index));
    }
    const selected: u32 = if (result == 0)
        @as(u32, @intCast(lane_count))
    else if (most_significant)
        @as(u32, @intCast(15 - @as(usize, @clz(result))))
    else
        @as(u32, @intCast(@ctz(result)));
    self.setReg(.cl_cx_ecx_rcx, .bits32, selected);
    const flags_mask = x64_decoder.RFL_CF | x64_decoder.RFL_ZF | x64_decoder.RFL_SF | x64_decoder.RFL_OF | x64_decoder.RFL_AF | x64_decoder.RFL_PF;
    var new_flags: u32 = 0;
    if (result != 0) new_flags |= x64_decoder.RFL_CF;
    if (rhs_len < lane_count) new_flags |= x64_decoder.RFL_ZF;
    if (lhs_len < lane_count) new_flags |= x64_decoder.RFL_SF;
    if ((result & 1) != 0) new_flags |= x64_decoder.RFL_OF;
    self.regs.rflags = (self.regs.rflags & ~flags_mask) | new_flags;
}

fn truncateF64ToI32(value: f64) i32 {
    // CVTTPD2DQ returns the architectural integer indefinite value for NaN,
    // infinities, and values outside the signed dword range.
    if (std.math.isNan(value) or value < -2147483648.0 or value >= 2147483648.0) return std.math.minInt(i32);
    return @intFromFloat(@trunc(value));
}

fn executeVcvtdq2pd(self: anytype, d: DecodedInsn) void {
    const destination_count = vectorBytes(d);
    const source = readUnaryOperand(self, d, destination_count / 2, 4);
    if (self.terminated) return;
    var computed = [_]u8{0} ** 64;
    for (0..destination_count / 8) |lane| {
        const integer = std.mem.readInt(i32, @ptrCast(&source[lane * 4]), .little);
        const converted: f64 = @floatFromInt(integer);
        std.mem.writeInt(u64, @ptrCast(&computed[lane * 8]), @bitCast(converted), .little);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, destination_count, 8), destination_count);
}

fn executeVcvttpd2dq(self: anytype, d: DecodedInsn) void {
    const source_count = vectorBytes(d);
    const destination_count = source_count / 2;
    const source = readUnaryOperand(self, d, source_count, 8);
    if (self.terminated) return;
    var computed = [_]u8{0} ** 64;
    for (0..destination_count / 4) |lane| {
        const bits = std.mem.readInt(u64, @ptrCast(&source[lane * 8]), .little);
        const converted = truncateF64ToI32(@bitCast(bits));
        std.mem.writeInt(u32, @ptrCast(&computed[lane * 4]), @bitCast(converted), .little);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, destination_count, 4), destination_count);
}

fn executeVpmaxsw(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const lhs = readVectorRegister(self, d.xmm_src);
    const rhs = readRmOperand(self, d, count, 2, 2);
    var computed = [_]u8{0} ** 64;
    for (0..count / 2) |lane| {
        const offset = lane * 2;
        const left = std.mem.readInt(i16, @ptrCast(&lhs[offset]), .little);
        const right = std.mem.readInt(i16, @ptrCast(&rhs[offset]), .little);
        const result = if (left > right) left else right;
        std.mem.writeInt(u16, @ptrCast(&computed[offset]), @bitCast(result), .little);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 2), count);
}

/// Return true only for operations implemented by this shared vector engine.
/// Both processor backends use this predicate before dispatching a VEX
/// operation here, so an omitted case cannot silently consume an instruction.
pub fn handles(op: Op) bool {
    return switch (op) {
        .vmovdqu_ymm_ymm,
        .vmovdqu_ymm_mem,
        .vmovdqu_mem_ymm,
        .vmovdqa_ymm_ymm,
        .vmovdqa_ymm_mem,
        .vmovdqa_mem_ymm,
        .vmovups_ymm_ymm,
        .vmovups_ymm_mem,
        .vmovups_mem_ymm,
        .vpxor,
        .vpaddd,
        .vpsadbw,
        .vpmaddubsw,
        .vpmaddwd,
        .vpdpbusd,
        .vpslld,
        .vpshufd,
        .vpshuflw,
        .vpshufhw,
        .vpshufb,
        .vpalignr,
        .vmaskmovps_load,
        .vmaskmovps_store,
        .vmaskmovpd_load,
        .vmaskmovpd_store,
        .vpmovqd,
        .vextracti32x4,
        .vextracti64x4,
        .vpcmpb,
        .vmovd_xmm_reg32,
        .vmovd_xmm_mem32,
        .vmovd_reg32_xmm,
        .vmovd_mem32_xmm,
        .movdir64b,
        .vpackssdw,
        .vpacksswb,
        .vpackuswb,
        .vpackusdw,
        .vpabsb,
        .vpabsw,
        .vpabsd,
        .vpsignb,
        .vpsignw,
        .vpsignd,
        .vpmovsxbw,
        .vpmovsxbd,
        .vpmovsxbq,
        .vpmovsxwd,
        .vpmovsxwq,
        .vpmovsxdq,
        .vpmovzxbw,
        .vpmovzxbd,
        .vpmovzxbq,
        .vpmovzxwd,
        .vpmovzxwq,
        .vpmovzxdq,
        .vpmuldq,
        .vpermd,
        .vblendps,
        .vshufpd,
        .vpermilps,
        .vpbroadcastw,
        .vpbroadcastd,
        .vpbroadcastq,
        .vextractps,
        .vmovntdq,
        .vmovntps,
        .vmovntdqa,
        .vpcmpistri,
        .vpmaxsw,
        .vcvtdq2pd,
        .vcvttpd2dq,
        => true,
        else => false,
    };
}

fn executeVpsadbw(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const lhs = readVectorRegister(self, d.xmm_src);
    const rhs = readRmOperand(self, d, count, 1, 8);
    var computed = [_]u8{0} ** 64;
    var offset: usize = 0;
    while (offset < count) : (offset += 8) {
        var sum: u64 = 0;
        for (0..8) |i| {
            const a = lhs[offset + i];
            const b = rhs[offset + i];
            sum += if (a >= b) a - b else b - a;
        }
        std.mem.writeInt(u64, @ptrCast(&computed[offset]), sum, .little);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 8), count);
}

fn executeVpmaddubsw(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const unsigned_source = readVectorRegister(self, d.xmm_src);
    const signed_source = readRmOperand(self, d, count, 1, 2);
    var computed = [_]u8{0} ** 64;
    for (0..count / 2) |lane| {
        const offset = lane * 2;
        const a0: i32 = unsigned_source[offset];
        const a1: i32 = unsigned_source[offset + 1];
        const b0: i32 = @as(i8, @bitCast(signed_source[offset]));
        const b1: i32 = @as(i8, @bitCast(signed_source[offset + 1]));
        const sum = std.math.clamp(a0 * b0 + a1 * b1, -32768, 32767);
        std.mem.writeInt(i16, @ptrCast(&computed[offset]), @intCast(sum), .little);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 2), count);
}

fn executeVpmaddwd(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const lhs = readVectorRegister(self, d.xmm_src);
    const rhs = readRmOperand(self, d, count, 2, 4);
    var computed = [_]u8{0} ** 64;
    for (0..count / 4) |lane| {
        const offset = lane * 4;
        const a0: i32 = std.mem.readInt(i16, @ptrCast(&lhs[offset]), .little);
        const a1: i32 = std.mem.readInt(i16, @ptrCast(&lhs[offset + 2]), .little);
        const b0: i32 = std.mem.readInt(i16, @ptrCast(&rhs[offset]), .little);
        const b1: i32 = std.mem.readInt(i16, @ptrCast(&rhs[offset + 2]), .little);
        const result: i32 = a0 * b0 + a1 * b1;
        std.mem.writeInt(i32, @ptrCast(&computed[offset]), result, .little);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 4), count);
}

fn executeVpdpbusd(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const accumulator = readVectorRegister(self, d.xmm_dst);
    const unsigned_source = readVectorRegister(self, d.xmm_src);
    const signed_source = readRmOperand(self, d, count, 1, 4);
    var computed = accumulator;
    for (0..count / 4) |lane| {
        const offset = lane * 4;
        var total: i64 = std.mem.readInt(i32, @ptrCast(&accumulator[offset]), .little);
        for (0..4) |byte_index| {
            const a: i64 = unsigned_source[offset + byte_index];
            const b: i64 = @as(i8, @bitCast(signed_source[offset + byte_index]));
            total += a * b;
        }
        std.mem.writeInt(u32, @ptrCast(&computed[offset]), @truncate(@as(u64, @bitCast(total))), .little);
    }
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, accumulator, count, 4), count);
}

fn executeVpslld(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const source = if (d.is_reg_form)
        readVectorRegister(self, d.xmm_src)
    else
        readRmOperand(self, d, count, 4, 4);
    var computed = [_]u8{0} ** 64;
    const shift = @as(u8, @truncate(d.imm));
    for (0..count / 4) |lane| {
        const offset = lane * 4;
        const value = std.mem.readInt(u32, @ptrCast(&source[offset]), .little);
        const result: u32 = if (shift >= 32) 0 else value << @as(u5, @intCast(shift));
        std.mem.writeInt(u32, @ptrCast(&computed[offset]), result, .little);
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 4), count);
}

fn executeVpshufd(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const source = if (d.is_reg_form)
        readVectorRegister(self, d.xmm_src)
    else
        readRmOperand(self, d, count, 4, 4);
    var computed = [_]u8{0} ** 64;
    const control: u8 = @truncate(d.imm);
    for (0..count / 16) |lane| {
        const base = lane * 16;
        for (0..4) |dword| {
            const selected = @as(usize, (control >> @as(u3, @intCast(dword * 2))) & 3);
            @memcpy(computed[base + dword * 4 ..][0..4], source[base + selected * 4 ..][0..4]);
        }
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 4), count);
}

/// Shuffle the low or high four 16-bit words in each 128-bit lane. Unlike
/// VPSHUFD, the non-selected half of each lane is preserved, and the same
/// eight-bit control is applied independently to every lane. This is shared
/// by VEX and EVEX forms so their upper-lane and masking behavior follows the
/// same architectural register helpers.
fn executeVpshufWords(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const source = readUnaryOperand(self, d, count, 2);
    if (self.terminated) return;
    var computed = source;
    const high = d.op == .vpshufhw;
    for (0..count / 16) |block| {
        const base = block * 16 + if (high) @as(usize, 8) else 0;
        for (0..4) |destination_lane| {
            const shift: u3 = @intCast(destination_lane * 2);
            const selected_lane = @as(usize, (d.imm >> shift) & 3);
            @memcpy(
                computed[base + destination_lane * 2 ..][0..2],
                source[base + selected_lane * 2 ..][0..2],
            );
        }
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 2), count);
}

fn executeVpshufb(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const source = readVectorRegister(self, d.xmm_src);
    const control = readRmOperand(self, d, count, 1, 1);
    var computed = [_]u8{0} ** 64;
    for (0..count / 16) |lane| {
        const base = lane * 16;
        for (0..16) |i| {
            const selector = control[base + i];
            computed[base + i] = if ((selector & 0x80) != 0)
                0
            else
                source[base + (selector & 0x0F)];
        }
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 1), count);
}

/// Execute VPALIGNR independently in each 128-bit lane. The VEX NDS
/// operands are concatenated with VEX.vvvv (SRC1) in the low half and
/// ModR/M.r/m (SRC2) in the high half, matching the legacy PALIGNR
/// destructive-destination ordering. EVEX masking applies to the result;
/// the source operand itself remains an ordinary vector load.
fn executeVpalignr(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const first = readVectorRegister(self, d.xmm_src);
    const second = readRmOperand(self, d, count, 1, 1);
    if (self.terminated) return;
    const shift: usize = @min(@as(usize, @intCast(d.imm)), 32);
    var computed = [_]u8{0} ** 64;
    for (0..count / 16) |block| {
        const base = block * 16;
        for (0..16) |byte| {
            const selected = shift + byte;
            computed[base + byte] = if (selected < 16)
                first[base + selected]
            else if (selected < 32)
                second[base + selected - 16]
            else
                0;
        }
    }
    const old = readVectorRegister(self, d.xmm_dst);
    writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, count, 1), count);
}

/// VMASKMOVPS/PD use the sign bit of each mask element, rather than the
/// EVEX k-register bit numbering used by masked vector instructions. Reading
/// the complete vector here also handles the YMM form and keeps the mask's
/// upper half independent from the destination register.
fn vectorMaskLaneActive(mask: [64]u8, lane: usize, bytes_per_element: usize) bool {
    const offset = lane * bytes_per_element;
    return switch (bytes_per_element) {
        4 => (std.mem.readInt(u32, @ptrCast(&mask[offset]), .little) & 0x8000_0000) != 0,
        8 => (std.mem.readInt(u64, @ptrCast(&mask[offset]), .little) & 0x8000_0000_0000_0000) != 0,
        else => unreachable,
    };
}

/// Execute the legacy AVX masked vector memory operations. Masked-off loads
/// produce zero without touching memory; masked-off stores leave memory
/// unchanged. This per-lane implementation is intentional: a vector-wide
/// read/write would incorrectly fault on an inactive lane and would make the
/// x86 memory contract observably different from the Windows binary.
fn executeVmaskmov(self: anytype, d: DecodedInsn) void {
    const bytes_per_element: usize = switch (d.op) {
        .vmaskmovps_load, .vmaskmovps_store => 4,
        .vmaskmovpd_load, .vmaskmovpd_store => 8,
        else => unreachable,
    };
    const count = vectorBytes(d);
    const mask_index: u8 = switch (d.op) {
        .vmaskmovps_load, .vmaskmovpd_load => d.xmm_src,
        .vmaskmovps_store, .vmaskmovpd_store => d.xmm_src2,
        else => unreachable,
    };
    const mask = readVectorRegister(self, mask_index);

    switch (d.op) {
        .vmaskmovps_load, .vmaskmovpd_load => {
            var loaded = [_]u8{0} ** 64;
            for (0..count / bytes_per_element) |lane| {
                if (!vectorMaskLaneActive(mask, lane, bytes_per_element)) continue;
                const offset = lane * bytes_per_element;
                const value = self.readMemVal(d.addr +| offset, scalarSize(bytes_per_element));
                if (self.terminated) return;
                switch (bytes_per_element) {
                    4 => std.mem.writeInt(u32, @ptrCast(&loaded[offset]), @truncate(value), .little),
                    8 => std.mem.writeInt(u64, @ptrCast(&loaded[offset]), value, .little),
                    else => unreachable,
                }
            }
            writeVectorRegister(self, d.xmm_dst, loaded, count);
        },
        .vmaskmovps_store, .vmaskmovpd_store => {
            const source = readVectorRegister(self, d.xmm_src);
            for (0..count / bytes_per_element) |lane| {
                if (!vectorMaskLaneActive(mask, lane, bytes_per_element)) continue;
                const offset = lane * bytes_per_element;
                const value: u64 = switch (bytes_per_element) {
                    4 => std.mem.readInt(u32, @ptrCast(&source[offset]), .little),
                    8 => std.mem.readInt(u64, @ptrCast(&source[offset]), .little),
                    else => unreachable,
                };
                self.writeMemVal(d.addr +| offset, scalarSize(bytes_per_element), value);
                if (self.terminated) return;
            }
        },
        else => unreachable,
    }
}

fn executeVpmovqd(self: anytype, d: DecodedInsn) void {
    const source_count = vectorBytes(d);
    const destination_count = source_count / 2;
    const source = readVectorRegister(self, d.xmm_src);
    var computed = [_]u8{0} ** 64;
    for (0..destination_count / 4) |lane| {
        const source_offset = lane * 8;
        const destination_offset = lane * 4;
        const value = std.mem.readInt(u64, @ptrCast(&source[source_offset]), .little);
        std.mem.writeInt(u32, @ptrCast(&computed[destination_offset]), @truncate(value), .little);
    }
    if (d.is_reg_form) {
        const old = readVectorRegister(self, d.xmm_dst);
        writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, destination_count, 4), destination_count);
    } else {
        writeVectorMemory(self, d, computed, destination_count, 4);
    }
}

fn executeVextract(self: anytype, d: DecodedInsn) void {
    const source_count = vectorBytes(d);
    const destination_count: usize = if (d.op == .vextracti32x4) 16 else 32;
    const lane_bytes: usize = if (d.op == .vextracti32x4) 4 else 8;
    const source = readVectorRegister(self, d.xmm_src);
    const chunk_count = source_count / destination_count;
    const selected = @as(usize, @truncate(d.imm)) & (chunk_count - 1);
    var computed = [_]u8{0} ** 64;
    @memcpy(computed[0..destination_count], source[selected * destination_count ..][0..destination_count]);

    if (d.is_reg_form) {
        const old = readVectorRegister(self, d.xmm_dst);
        writeVectorRegister(self, d.xmm_dst, maskedVector(self, d, computed, old, destination_count, lane_bytes), destination_count);
    } else {
        writeVectorMemory(self, d, computed, destination_count, lane_bytes);
    }
}

fn executeVpcmpb(self: anytype, d: DecodedInsn) void {
    const count = vectorBytes(d);
    const lhs = readVectorRegister(self, d.xmm_src);
    const rhs = readRmOperand(self, d, count, 1, 1);
    const predicate: u3 = @truncate(d.imm);
    var result = if (d.opmask == 0 or d.zero_mask) 0 else self.k[d.dst_k];
    const lane_count = @min(count, 64);
    for (0..lane_count) |lane| {
        const a: i8 = @bitCast(lhs[lane]);
        const b: i8 = @bitCast(rhs[lane]);
        const compare = switch (predicate) {
            0 => a == b,
            1 => a < b,
            2 => a <= b,
            3 => false,
            4 => a != b,
            5 => a >= b,
            6 => a > b,
            7 => true,
        };
        if (maskActive(self, d, lane)) {
            if (compare) result |= @as(u64, 1) << @as(u6, @intCast(lane)) else result &= ~(@as(u64, 1) << @as(u6, @intCast(lane)));
        } else if (d.zero_mask) {
            result &= ~(@as(u64, 1) << @as(u6, @intCast(lane)));
        }
    }
    if (lane_count < 64) result &= (@as(u64, 1) << @as(u6, @intCast(lane_count))) - 1;
    self.k[d.dst_k] = result;
}

fn executeVmovd(self: anytype, d: DecodedInsn) void {
    switch (d.op) {
        .vmovd_xmm_reg32 => {
            var value = [_]u8{0} ** 64;
            std.mem.writeInt(u32, @ptrCast(&value[0]), @truncate(self.regVal(d.src_reg, .bits32)), .little);
            writeVectorRegister(self, d.xmm_dst, value, 16);
        },
        .vmovd_xmm_mem32 => {
            var value = [_]u8{0} ** 64;
            std.mem.writeInt(u32, @ptrCast(&value[0]), @truncate(self.readMemVal(d.addr, .bits32)), .little);
            if (self.terminated) return;
            writeVectorRegister(self, d.xmm_dst, value, 16);
        },
        .vmovd_reg32_xmm => {
            const source = readVectorRegister(self, d.xmm_src);
            self.setReg(d.dst_reg, .bits32, std.mem.readInt(u32, @ptrCast(&source[0]), .little));
        },
        .vmovd_mem32_xmm => {
            const source = readVectorRegister(self, d.xmm_src);
            self.writeMemVal(d.addr, .bits32, std.mem.readInt(u32, @ptrCast(&source[0]), .little));
        },
        else => unreachable,
    }
}

fn executeMovdir64b(self: anytype, d: DecodedInsn) void {
    const destination = self.regVal(d.dst_reg, .bits64);
    var value = [_]u8{0} ** 64;
    for (0..4) |chunk_index| {
        const chunk = self.readMem128(d.addr +| chunk_index * 16);
        @memcpy(value[chunk_index * 16 ..][0..16], chunk[0..16]);
        if (self.terminated) return;
    }
    for (0..4) |chunk_index| {
        var chunk = [_]u8{0} ** 16;
        @memcpy(chunk[0..16], value[chunk_index * 16 ..][0..16]);
        self.writeMem128(destination +| chunk_index * 16, chunk);
        if (self.terminated) return;
    }
}

fn terminateUnsupported(self: anytype, d: DecodedInsn) void {
    std.log.err("unimplemented vector instruction: {s} at rip=0x{x}", .{ @tagName(d.op), self.regs.rip });
    self.faulted = true;
    self.exit_code = 127;
    self.terminated = true;
    if (comptime @TypeOf(self.termination_reason) == exit_diagnostics.TerminationReason) {
        self.termination_reason = exit_diagnostics.TerminationReason.unimplemented_instruction;
    } else {
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unimplemented_instruction);
    }
}

pub fn execute(self: anytype, d: DecodedInsn) void {
    switch (d.op) {
        .vmovdqu_ymm_ymm,
        .vmovdqu_ymm_mem,
        .vmovdqu_mem_ymm,
        .vmovdqa_ymm_ymm,
        .vmovdqa_ymm_mem,
        .vmovdqa_mem_ymm,
        .vmovups_ymm_ymm,
        .vmovups_ymm_mem,
        .vmovups_mem_ymm,
        => executeMove(self, d),
        .vpxor => executeVpxor(self, d),
        .vpaddd => executeVpaddd(self, d),
        .vpsadbw => executeVpsadbw(self, d),
        .vpmaddubsw => executeVpmaddubsw(self, d),
        .vpmaddwd => executeVpmaddwd(self, d),
        .vpdpbusd => executeVpdpbusd(self, d),
        .vpslld => executeVpslld(self, d),
        .vpshufd => executeVpshufd(self, d),
        .vpshuflw, .vpshufhw => executeVpshufWords(self, d),
        .vpshufb => executeVpshufb(self, d),
        .vpalignr => executeVpalignr(self, d),
        .vmaskmovps_load, .vmaskmovps_store, .vmaskmovpd_load, .vmaskmovpd_store => executeVmaskmov(self, d),
        .vpmovqd => executeVpmovqd(self, d),
        .vextracti32x4, .vextracti64x4 => executeVextract(self, d),
        .vpcmpb => executeVpcmpb(self, d),
        .vmovd_xmm_reg32, .vmovd_xmm_mem32, .vmovd_reg32_xmm, .vmovd_mem32_xmm => executeVmovd(self, d),
        .movdir64b => executeMovdir64b(self, d),
        .vpackssdw, .vpacksswb, .vpackuswb, .vpackusdw => executeVpack(self, d),
        .vpabsb, .vpabsw, .vpabsd => executeVpackedAbs(self, d),
        .vpsignb, .vpsignw, .vpsignd => executeVpackedSign(self, d),
        .vpmovsxbw,
        .vpmovsxbd,
        .vpmovsxbq,
        .vpmovsxwd,
        .vpmovsxwq,
        .vpmovsxdq,
        .vpmovzxbw,
        .vpmovzxbd,
        .vpmovzxbq,
        .vpmovzxwd,
        .vpmovzxwq,
        .vpmovzxdq,
        => executeVwiden(self, d),
        .vpmuldq => executeVpmuldq(self, d),
        .vpermd => executeVpermd(self, d),
        .vblendps => executeVblendps(self, d),
        .vshufpd => executeVshufpd(self, d),
        .vpermilps => executeVpermilps(self, d),
        .vpbroadcastw, .vpbroadcastd, .vpbroadcastq => executeVpbroadcast(self, d),
        .vextractps => executeVextractPs(self, d),
        .vmovntdq, .vmovntps => executeVmovnt(self, d),
        .vmovntdqa => executeVmovntdqa(self, d),
        .vpcmpistri => executeVpcmpistri(self, d),
        .vpmaxsw => executeVpmaxsw(self, d),
        .vcvtdq2pd => executeVcvtdq2pd(self, d),
        .vcvttpd2dq => executeVcvttpd2dq(self, d),
        else => terminateUnsupported(self, d),
    }
}
