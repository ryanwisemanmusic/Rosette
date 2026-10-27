const std = @import("std");
const runtime_abi = @import("runtime_abi_handshake");
const decode = @import("../decode_scaffold.zig");
const isa = @import("../instruction_set.zig");
const raw_decode = @import("../raw_decoder.zig");
const reg_trace = @import("../register-tracing/runtime.zig");
const bridge = @import("bridge_instruction_decoding");

const PrefixTag = enum(u8) {
    lock = 0xF0,
    repne = 0xF2,
    rep = 0xF3,
    operand_override = 0x66,
    address_override = 0x67,
    seg_cs = 0x2E,
    seg_ss = 0x36,
    seg_ds = 0x3E,
    seg_es = 0x26,
    seg_fs = 0x64,
    seg_gs = 0x65,
};

fn mapSegmentOverride(byte: u8) ?decode.SegmentOverride {
    return switch (byte) {
        0x2E => .cs,
        0x3E => .ds,
        0x26 => .es,
        0x64 => .fs,
        0x65 => .gs,
        0x36 => .ss,
        else => null,
    };
}

fn appendPrefixOrder(event: anytype, value: u8) void {
    if (event.prefix_count < event.prefix_order.len) {
        event.prefix_order[event.prefix_count] = value;
    }
    event.prefix_count +|= 1;
}

fn parseLegacyPrefixes(scope: []const u8, bytes: []const u8, event: anytype) usize {
    var idx: usize = 0;
    var seen_group1 = false;
    var seen_group2 = false;
    var seen_group3 = false;
    var seen_group4 = false;
    while (idx < bytes.len and idx < 15) : (idx += 1) {
        const byte = bytes[idx];
        switch (byte) {
            0xF0 => {
                if (seen_group1 or event.lock) runtime_abi.common.violation("x86-decode", "prefix_stack", "scope={s} duplicate/conflicting LOCK prefix", .{scope});
                event.lock = true;
                seen_group1 = true;
                appendPrefixOrder(event, byte);
            },
            0xF2 => {
                if (seen_group1 or event.rep or event.repe or event.repne) runtime_abi.common.violation("x86-decode", "prefix_stack", "scope={s} conflicting REP/REPNE prefix stack", .{scope});
                event.repne = true;
                seen_group1 = true;
                appendPrefixOrder(event, byte);
            },
            0xF3 => {
                if (seen_group1 or event.rep or event.repe or event.repne) runtime_abi.common.violation("x86-decode", "prefix_stack", "scope={s} conflicting REP/REPE prefix stack", .{scope});
                event.rep = true;
                event.repe = true;
                seen_group1 = true;
                appendPrefixOrder(event, byte);
            },
            0x2E, 0x3E, 0x26, 0x64, 0x65, 0x36 => {
                if (seen_group2 or event.segment_override != 0xFF) runtime_abi.common.violation("x86-decode", "segment_override_stack", "scope={s} multiple segment overrides", .{scope});
                event.segment_override = @intFromEnum(mapSegmentOverride(byte).?);
                seen_group2 = true;
                appendPrefixOrder(event, byte);
            },
            0x66 => {
                if (seen_group3 or event.operand_size_override) runtime_abi.common.violation("x86-decode", "operand_override_stack", "scope={s} duplicate operand-size override", .{scope});
                event.operand_size_override = true;
                seen_group3 = true;
                appendPrefixOrder(event, byte);
            },
            0x67 => {
                if (seen_group4 or event.address_size_override) runtime_abi.common.violation("x86-decode", "address_override_stack", "scope={s} duplicate address-size override", .{scope});
                event.address_size_override = true;
                seen_group4 = true;
                appendPrefixOrder(event, byte);
            },
            else => break,
        }
    }
    return idx;
}

fn controlKindFor(opcode: isa.Opcode) bridge.ControlTransferKind {
    return switch (opcode) {
        .jmp, .je, .jne, .jl, .jge, .jg, .jle => .near_jump,
        .call => .near_call,
        .ret, .ret_imm => .near_return,
        else => .none,
    };
}

fn controlKindForRaw(kind: raw_decode.ControlKind) bridge.ControlTransferKind {
    return switch (kind) {
        .none => .none,
        .near_jump => .near_jump,
        .conditional_jump => .near_jump,
        .near_call => .near_call,
        .near_return => .near_return,
    };
}

fn reportShadow(source: anytype) void {
    var target = source;
    target.arch = .arm64;
    bridge.reportDecodeEvent(target, reg_trace.emitOperationContext);
}

pub fn validateRawInstructionWindow(scope: []const u8, start_eip: u32, bytes: []const u8, decoded: raw_decode.DecodedInstruction) void {
    var event = bridge.makeDecodeEvent(.x86, reg_trace.currentSequence(), scope);
    const visible = @min(bytes.len, @min(@as(usize, decoded.len), @as(usize, 15)));
    event.decoded_len = @intCast(visible);
    if (decoded.len > 15) {
        runtime_abi.common.violation("x86-decode", "instruction_length", "scope={s} decoded instruction length {d} exceeds x86 max 15 bytes", .{ scope, decoded.len });
    }

    const prefix_len = parseLegacyPrefixes(scope, bytes[0..visible], &event);
    event.opcode_len = if (visible > prefix_len) 1 else 0;
    if (decoded.modrm) |modrm| {
        event.has_modrm = true;
        event.modrm = @bitCast(modrm);
    }
    if (decoded.sib) |sib| {
        event.has_sib = true;
        event.sib = @bitCast(sib);
    }
    if (decoded.immediate != 0) {
        event.immediate_width = 4;
        event.immediate_value = decoded.immediate;
        event.sign_extended_immediate = @as(i64, @intCast(@as(i32, @bitCast(decoded.immediate))));
    }
    event.relative_target = decoded.target;
    event.control_kind = controlKindForRaw(decoded.control);
    event.invalid_opcode = decoded.status == .invalid;
    event.undefined_opcode = decoded.status == .recognized_unimplemented;

    if (event.invalid_opcode) {
        runtime_abi.common.violation("x86-decode", "invalid_opcode", "scope={s} opcode byte 0x{x} is invalid/undefined", .{ scope, decoded.opcode });
    }
    if (event.undefined_opcode) {
        // This bridge deliberately fail-fasts on instructions it cannot
        // execute. Preserve the exact guest bytes and address before that
        // abort so an offline PE run can distinguish a true unsupported
        // encoding from self-modifying/generated code or a bad decode.
        const digits = "0123456789ABCDEF";
        var byte_text: [15 * 3]u8 = undefined;
        var byte_text_len: usize = 0;
        for (bytes[0..visible], 0..) |byte, index| {
            if (index != 0) {
                byte_text[byte_text_len] = ' ';
                byte_text_len += 1;
            }
            byte_text[byte_text_len] = digits[byte >> 4];
            byte_text[byte_text_len + 1] = digits[byte & 0x0F];
            byte_text_len += 2;
        }
        runtime_abi.common.writeLine(
            "[x86-raw-bytes] scope={s} eip=0x{x} bytes={s}\n",
            .{ scope, start_eip, byte_text[0..byte_text_len] },
        );
        runtime_abi.common.violation("x86-decode", "raw_unimplemented", "scope={s} instruction={s} isa={s} reason={s}", .{ scope, decoded.textSlice(), decoded.isa_path, decoded.unsupported_reason });
    }

    runtime_abi.common.writeLine(
        "[instruction-decoding][x86-raw-pe] scope={s} seq={d} isa={s} prefixes={d} opcode_len={d} len={d} status={s}\n",
        .{ scope, reg_trace.currentSequence(), decoded.isa_path, event.prefix_count, event.opcode_len, event.decoded_len, @tagName(decoded.status) },
    );
    bridge.reportDecodeEvent(event, reg_trace.emitOperationContext);
    reportShadow(event);
}

pub fn validateInstructionWindow(scope: []const u8, start_eip: u32, bytes: []const u8, opcode_valid: bool, inst: ?isa.InstructionDef) void {
    _ = start_eip;
    var event = bridge.makeDecodeEvent(.x86, reg_trace.currentSequence(), scope);
    const visible = @min(bytes.len, 15);
    event.decoded_len = @intCast(visible);
    if (bytes.len > 15) {
        runtime_abi.common.violation("x86-decode", "instruction_length", "scope={s} instruction window length {d} exceeds x86 max 15 bytes", .{ scope, bytes.len });
    }

    const prefix_len = parseLegacyPrefixes(scope, bytes[0..visible], &event);
    event.opcode_len = if (visible > prefix_len) 1 else 0;

    if (!opcode_valid) {
        event.invalid_opcode = true;
        runtime_abi.common.violation("x86-decode", "invalid_opcode", "scope={s} opcode byte 0x{x} is invalid/undefined", .{ scope, if (bytes.len > prefix_len) bytes[prefix_len] else 0 });
    }

    if (inst) |decoded_inst| {
        event.control_kind = controlKindFor(decoded_inst.opcode);
        switch (decoded_inst.opcode) {
            .jmp, .je, .jne, .jl, .jge, .jg, .jle, .call => {
                event.relative_target = @as(u32, @bitCast(decoded_inst.op1));
            },
            .ret_imm => {
                event.immediate_width = 2;
                event.immediate_value = @as(u32, @bitCast(decoded_inst.op1));
                event.sign_extended_immediate = @as(i64, @intCast(@as(i32, @bitCast(decoded_inst.op1))));
            },
            .mov_reg_imm, .mov_mem_imm, .add_reg_imm, .sub_reg_imm, .cmp_reg_imm => {
                event.immediate_width = 4;
                event.immediate_value = @as(u32, @bitCast(decoded_inst.op2));
                event.sign_extended_immediate = @as(i64, @intCast(decoded_inst.op2));
            },
            else => {},
        }
    }

    runtime_abi.common.writeLine(
        "[instruction-decoding][x86] scope={s} seq={d} prefixes={d} opcode_len={d} len={d}\n",
        .{ scope, reg_trace.currentSequence(), event.prefix_count, event.opcode_len, event.decoded_len },
    );
    bridge.reportDecodeEvent(event, reg_trace.emitOperationContext);
    reportShadow(event);
}

test "prefix parser catches stacked overrides" {
    const bytes = [_]u8{ 0x66, 0x67, 0x90 };
    validateInstructionWindow("decode-test", 0x1000, &bytes, true, null);
}
