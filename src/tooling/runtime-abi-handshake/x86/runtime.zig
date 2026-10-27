const std = @import("std");
const common = @import("../common.zig");
const code_text = @import("entrypoint_code_text_segment");

pub const AccessKind = enum { fetch, read, write };
pub const ArithmeticKind = enum { add, sub, inc, dec, cmp, test_and, logical, mul, imul, div, shift };
pub const SegmentState = struct {
    selector: u32,
    base: u32,
    limit: u32,
    privilege: u8,
    operand_bits: u8,
    address_bits: u8,
};

pub const ExtendedState = struct {
    flags_raw: u32,
    direction_flag: u1,
    interrupt_flag: u1,
    iopl: u2,
    cs: SegmentState,
    ds: SegmentState,
    es: SegmentState,
    fs: SegmentState,
    gs: SegmentState,
    ss: SegmentState,
    mxcsr: u32,
    fpu_control: u16,
    fpu_status: u16,
    fpu_tag: u16,
    x87_top: u8,
    lazy_fpu: bool,
    pending_exception: u32,
    dr6: u32,
    dr7: u32,
};

pub const CodeTextSegment = code_text.Segment;
pub const CodeTextGuard = code_text.Guard;

pub fn init() void {
    common.acquire();
}

pub fn deinit() void {
    common.release();
}

pub fn validateTitleSpec(memory_size: u32, stack_top: u32, grid_offset: u32, grid_width: u32, grid_height: u32, active_type_offset: u32) void {
    common.noteValidation();
    if (memory_size == 0) common.violation("x86-title", "memory_size", "memory size is zero", .{});
    if (stack_top > memory_size)
        common.violation("x86-title", "stack_top", "stack top 0x{x} exceeds memory size 0x{x}", .{ stack_top, memory_size });
    if (grid_width > 0 and grid_height > 0) {
        const bytes = @as(u64, grid_width) * @as(u64, grid_height);
        if (grid_offset >= memory_size or grid_offset + bytes > memory_size)
            common.violation("x86-title", "grid_bounds", "grid offset 0x{x} size {d}x{d} exceeds memory 0x{x}", .{ grid_offset, grid_width, grid_height, memory_size });
        if (active_type_offset < grid_offset or active_type_offset >= memory_size)
            common.violation("x86-title", "active_piece_offset", "active piece offset 0x{x} invalid for grid offset 0x{x}", .{ active_type_offset, grid_offset });
    }
}

pub fn validateExecutorState(phase: []const u8, mem_base: u32, mem_len: usize, eip: u32, esp: u32, ebp: u32, flags_raw: u32) void {
    // EBP is a general-purpose x86 register. Frame-pointer conventions do not
    // constrain its value, and optimized code commonly uses it as a counter.
    _ = ebp;
    common.noteValidation();
    if (mem_len == 0) {
        common.violation("x86", "empty_memory", "{s}: executor memory is empty", .{phase});
        return;
    }
    const mem_end = @as(u64, mem_base) + mem_len;
    if (@as(u64, eip) < mem_base or @as(u64, eip) > mem_end)
        common.trapViolation(.BadInstructionPointer, "x86", "eip_range", "{s}: EIP 0x{x} outside [0x{x}, 0x{x}]", .{ phase, eip, mem_base, mem_end });
    if (@as(u64, esp) < mem_base or @as(u64, esp) > mem_end)
        common.trapViolation(.StackMismatch, "x86", "esp_range", "{s}: ESP 0x{x} outside [0x{x}, 0x{x}]", .{ phase, esp, mem_base, mem_end });
    if ((flags_raw & 0x2) == 0)
        common.trapViolation(.FlagMismatch, "x86", "eflags_reserved1", "{s}: EFLAGS bit1 cleared (raw=0x{x})", .{ phase, flags_raw });
}

fn validateSegmentState(phase: []const u8, name: []const u8, seg: SegmentState) void {
    if (seg.privilege > 3)
        common.violation("x86", "segment_privilege", "{s}: {s} privilege {d} invalid", .{ phase, name, seg.privilege });
    if (!(seg.operand_bits == 16 or seg.operand_bits == 32))
        common.violation("x86", "segment_operand_size", "{s}: {s} operand size {d} invalid", .{ phase, name, seg.operand_bits });
    if (!(seg.address_bits == 16 or seg.address_bits == 32))
        common.violation("x86", "segment_address_size", "{s}: {s} address size {d} invalid", .{ phase, name, seg.address_bits });
    const seg_end = @as(u64, seg.base) + @as(u64, seg.limit);
    if (seg_end < seg.base)
        common.violation("x86", "segment_overflow", "{s}: {s} base 0x{x} + limit 0x{x} overflowed", .{ phase, name, seg.base, seg.limit });
    // A segment descriptor is not an allocation reservation. In flat 32-bit
    // PE processes, CS/DS/SS commonly have base 0 and limit 0xFFFFFFFF even
    // though the guest image and stack are mapped at nonzero addresses. FS may
    // also name a TEB outside the image allocation. Check the *current* CS:EIP
    // and SS:ESP below, and validate each actual memory access at its
    // execution site; comparing the whole descriptor range with this one
    // backing allocation rejects valid flat-segment state before guest code
    // runs (and does not prove that the mapping is safe).
}

pub fn validateExtendedState(phase: []const u8, mem_base: u32, mem_len: usize, eip: u32, esp: u32, ebp: u32, state: ExtendedState) void {
    // EBP is not inherently a frame pointer; actual memory accesses are checked
    // at their execution sites.
    common.noteValidation();
    validateExecutorState(phase, mem_base, mem_len, eip, esp, ebp, state.flags_raw);

    if (state.direction_flag != @as(u1, @truncate((state.flags_raw >> 10) & 1)))
        common.trapViolation(.FlagMismatch, "x86", "df_mismatch", "{s}: DF field {d} does not match EFLAGS raw 0x{x}", .{ phase, state.direction_flag, state.flags_raw });
    if (state.interrupt_flag != @as(u1, @truncate((state.flags_raw >> 9) & 1)))
        common.trapViolation(.FlagMismatch, "x86", "if_mismatch", "{s}: IF field {d} does not match EFLAGS raw 0x{x}", .{ phase, state.interrupt_flag, state.flags_raw });
    if (state.iopl != @as(u2, @truncate((state.flags_raw >> 12) & 0x3)))
        common.trapViolation(.FlagMismatch, "x86", "iopl_mismatch", "{s}: IOPL field {d} does not match EFLAGS raw 0x{x}", .{ phase, state.iopl, state.flags_raw });

    validateSegmentState(phase, "CS", state.cs);
    validateSegmentState(phase, "DS", state.ds);
    validateSegmentState(phase, "ES", state.es);
    validateSegmentState(phase, "FS", state.fs);
    validateSegmentState(phase, "GS", state.gs);
    validateSegmentState(phase, "SS", state.ss);

    if (@as(u64, eip) < state.cs.base or @as(u64, eip) > @as(u64, state.cs.base) + state.cs.limit)
        common.trapViolation(.BadInstructionPointer, "x86", "cs_eip_range", "{s}: EIP 0x{x} outside CS range [0x{x}..0x{x}]", .{ phase, eip, state.cs.base, @as(u64, state.cs.base) + state.cs.limit });
    if (@as(u64, esp) < state.ss.base or @as(u64, esp) > @as(u64, state.ss.base) + state.ss.limit)
        common.trapViolation(.StackMismatch, "x86", "ss_esp_range", "{s}: ESP 0x{x} outside SS range [0x{x}..0x{x}]", .{ phase, esp, state.ss.base, @as(u64, state.ss.base) + state.ss.limit });
    if ((state.mxcsr & 0xFFBF_0000) != 0)
        common.violation("x86", "mxcsr_reserved", "{s}: MXCSR reserved bits set: 0x{x}", .{ phase, state.mxcsr });
    if ((state.fpu_control & 0xE080) != 0)
        common.violation("x86", "fpu_control_reserved", "{s}: x87 control reserved bits set: 0x{x}", .{ phase, state.fpu_control });
    if (state.x87_top > 7)
        common.violation("x86", "x87_top_range", "{s}: x87 TOP out of range: {d}", .{ phase, state.x87_top });
    if (state.lazy_fpu and ((state.fpu_status != 0) or (state.pending_exception != 0)))
        common.violation("x86", "lazy_fpu_state", "{s}: lazy FPU active with live status/exception state status=0x{x} pending=0x{x}", .{ phase, state.fpu_status, state.pending_exception });
    if ((state.dr6 & 0xFFFF_0FF0) != 0)
        common.violation("x86", "dr6_reserved", "{s}: DR6 reserved bits set: 0x{x}", .{ phase, state.dr6 });
    if ((state.dr7 & 0xFFFF_0000) != 0)
        common.violation("x86", "dr7_reserved", "{s}: DR7 high reserved bits set: 0x{x}", .{ phase, state.dr7 });
}

pub fn validateInstructionPointer(phase: []const u8, guard: CodeTextGuard, eip: u32, width: usize) void {
    common.noteValidation();
    const check = code_text.checkInstructionPointer(guard, eip, width);
    if (check.isValid()) return;

    if (code_text.rvaToVaIfInImage(guard, eip)) |va| {
        common.trapViolation(
            .BadInstructionPointer,
            "x86",
            "eip_text_segment",
            "{s}: EIP 0x{x} invalid status={s} reason=\"{s}\" width={d} image=[0x{x}..0x{x}] rva_hint_va=0x{x}",
            .{ phase, eip, @tagName(check.status), code_text.statusDescription(check.status), check.width, guard.image_base, guard.imageEnd(), va },
        );
        return;
    }

    common.trapViolation(
        .BadInstructionPointer,
        "x86",
        "eip_text_segment",
        "{s}: EIP 0x{x} invalid status={s} reason=\"{s}\" width={d} image=[0x{x}..0x{x}]",
        .{ phase, eip, @tagName(check.status), code_text.statusDescription(check.status), check.width, guard.image_base, guard.imageEnd() },
    );
}

pub fn validateInstructionFetch(start_eip: u32, mem_base: u32, mem_len: usize, instruction_size: usize) void {
    common.noteValidation();
    if (start_eip < mem_base) {
        common.trapViolation(.BadInstructionPointer, "x86", "fetch_underflow", "instruction fetch at 0x{x} below base 0x{x}", .{ start_eip, mem_base });
        return;
    }
    const offset = @as(usize, @intCast(start_eip - mem_base));
    if (offset + instruction_size > mem_len)
        common.trapViolation(.BadInstructionPointer, "x86", "fetch_overflow", "instruction fetch at 0x{x} width {d} exceeds memory length {d}", .{ start_eip, instruction_size, mem_len });
}

pub fn validateFlatMemoryAccess(kind: AccessKind, base: u32, mem_len: usize, addr: u32, width: usize) void {
    common.noteValidation();
    if (addr < base) {
        common.trapViolation(.BadMemoryAccess, "x86", "memory_underflow", "{s} at 0x{x} below base 0x{x}", .{ @tagName(kind), addr, base });
        return;
    }
    const offset = @as(usize, @intCast(addr - base));
    if (offset + width > mem_len)
        common.trapViolation(.BadMemoryAccess, "x86", "memory_overflow", "{s} at 0x{x} width {d} exceeds memory length {d}", .{ @tagName(kind), addr, width, mem_len });
}

pub fn validateMemorySemantics(kind: AccessKind, addr: u32, width: usize, permissions: u8, aligned: bool, null_page: bool, guard_page: bool, stack_access: bool, stack_grows_down: bool, self_modified_code: bool, cache_invalidate: bool, translated_block_invalidate: bool) void {
    common.noteValidation();
    if (null_page)
        common.violation("x86", "null_page", "{s} at 0x{x} touched null page", .{ @tagName(kind), addr });
    if (guard_page)
        common.violation("x86", "guard_page", "{s} at 0x{x} touched guard page", .{ @tagName(kind), addr });
    // Scalar x86 loads and stores are valid at unaligned addresses unless
    // CR0.AM and EFLAGS.AC jointly request #AC. This flat PE model does not
    // enable alignment checking, so ordinary unaligned accesses are expected
    // guest behavior rather than an ABI violation.
    _ = aligned;
    const need_bit: u8 = switch (kind) {
        .read => 1 << 0,
        .write => 1 << 1,
        .fetch => 1 << 2,
    };
    if ((permissions & need_bit) == 0)
        common.violation("x86", "page_permissions", "{s} at 0x{x} width {d} denied by perms 0x{x}", .{ @tagName(kind), addr, width, permissions });
    if (kind == .write and self_modified_code and !cache_invalidate)
        common.violation("x86", "self_modifying_code", "write at 0x{x} modified executable memory without code-cache invalidation", .{addr});
    if (kind == .write and self_modified_code and !translated_block_invalidate)
        common.violation("x86", "translated_block_invalidate", "write at 0x{x} modified executable memory without translated-block invalidation", .{addr});
    _ = stack_access;
    _ = stack_grows_down;
}

pub fn validateArithmetic32(kind: ArithmeticKind, lhs: u32, rhs: u32, result: u32, zf: u1, sf: u1, cf: u1, of: u1) void {
    common.noteValidation();
    switch (kind) {
        .add => {
            const wide = @as(u64, lhs) + @as(u64, rhs);
            const expected_cf: u1 = @intFromBool(wide > std.math.maxInt(u32));
            const lhs_sign = (lhs >> 31) & 1;
            const rhs_sign = (rhs >> 31) & 1;
            const res_sign = (result >> 31) & 1;
            const expected_of: u1 = @intCast((~lhs_sign & ~rhs_sign & res_sign) | (lhs_sign & rhs_sign & ~res_sign));
            if (cf != expected_cf)
                common.violation("x86", "carry_mismatch", "add carry mismatch lhs=0x{x} rhs=0x{x} result=0x{x} got={d} expected={d}", .{ lhs, rhs, result, cf, expected_cf });
            if (of != expected_of)
                common.violation("x86", "overflow_mismatch", "add overflow mismatch lhs=0x{x} rhs=0x{x} result=0x{x} got={d} expected={d}", .{ lhs, rhs, result, of, expected_of });
        },
        .sub, .cmp => {
            const expected_cf: u1 = @intFromBool(lhs < rhs);
            const lhs_sign = (lhs >> 31) & 1;
            const rhs_sign = (rhs >> 31) & 1;
            const res_sign = (result >> 31) & 1;
            const expected_of: u1 = @intCast((lhs_sign ^ rhs_sign) & (lhs_sign ^ res_sign));
            if (cf != expected_cf)
                common.violation("x86", "borrow_mismatch", "{s} borrow mismatch lhs=0x{x} rhs=0x{x} result=0x{x} got={d} expected={d}", .{ @tagName(kind), lhs, rhs, result, cf, expected_cf });
            if (of != expected_of)
                common.violation("x86", "overflow_mismatch", "{s} overflow mismatch lhs=0x{x} rhs=0x{x} result=0x{x} got={d} expected={d}", .{ @tagName(kind), lhs, rhs, result, of, expected_of });
        },
        .dec => {
            const expected_of: u1 = @intFromBool(lhs == 0x8000_0000);
            if (of != expected_of)
                common.violation("x86", "overflow_mismatch", "dec overflow mismatch value=0x{x} result=0x{x} got={d} expected={d}", .{ lhs, result, of, expected_of });
        },
        .inc => {
            const expected_of: u1 = @intFromBool(lhs == 0x7FFF_FFFF);
            if (of != expected_of)
                common.violation("x86", "overflow_mismatch", "inc overflow mismatch value=0x{x} result=0x{x} got={d} expected={d}", .{ lhs, result, of, expected_of });
        },
        .logical, .test_and => {
            if (cf != 0 or of != 0)
                common.violation("x86", "logical_flags", "{s}: logical op produced CF={d} OF={d}", .{ @tagName(kind), cf, of });
        },
        else => {},
    }
    const expected_zf: u1 = @intFromBool(result == 0);
    const expected_sf: u1 = @intCast((result >> 31) & 1);
    if (zf != expected_zf)
        common.violation("x86", "zero_flag", "{s}: zero flag mismatch result=0x{x} got={d} expected={d}", .{ @tagName(kind), result, zf, expected_zf });
    if (sf != expected_sf)
        common.violation("x86", "sign_flag", "{s}: sign flag mismatch result=0x{x} got={d} expected={d}", .{ @tagName(kind), result, sf, expected_sf });
}

pub fn validateMul32(signed_mode: bool, lhs: u32, rhs: u32, eax: u32, edx: u32, cf: u1, of: u1) void {
    common.noteValidation();
    if (!signed_mode) {
        const wide = @as(u64, lhs) * @as(u64, rhs);
        const expected_eax: u32 = @truncate(wide);
        const expected_edx: u32 = @truncate(wide >> 32);
        const expected_flag: u1 = @intFromBool(expected_edx != 0);
        if (eax != expected_eax or edx != expected_edx)
            common.violation("x86", "mul_result", "mul mismatch lhs=0x{x} rhs=0x{x} got edx:eax=0x{x}:0x{x} expected 0x{x}:0x{x}", .{ lhs, rhs, edx, eax, expected_edx, expected_eax });
        if (cf != expected_flag or of != expected_flag)
            common.violation("x86", "mul_flags", "mul flags mismatch got CF={d} OF={d} expected={d}", .{ cf, of, expected_flag });
        return;
    }
    const a = @as(i32, @bitCast(lhs));
    const b = @as(i32, @bitCast(rhs));
    const wide = @as(i64, a) * @as(i64, b);
    const wide_bits: u64 = @bitCast(wide);
    const expected_eax: u32 = @truncate(wide_bits);
    const expected_edx: u32 = @truncate(wide_bits >> 32);
    const sign_ext: u32 = if ((expected_eax & 0x8000_0000) != 0) 0xFFFF_FFFF else 0;
    const expected_flag: u1 = @intFromBool(expected_edx != sign_ext);
    if (eax != expected_eax or edx != expected_edx)
        common.violation("x86", "imul_result", "imul mismatch lhs=0x{x} rhs=0x{x} got edx:eax=0x{x}:0x{x} expected 0x{x}:0x{x}", .{ lhs, rhs, edx, eax, expected_edx, expected_eax });
    if (cf != expected_flag or of != expected_flag)
        common.violation("x86", "imul_flags", "imul flags mismatch got CF={d} OF={d} expected={d}", .{ cf, of, expected_flag });
}

pub fn validateDiv32(edx_before: u32, eax_before: u32, divisor: u32, eax_after: u32, edx_after: u32) void {
    common.noteValidation();
    if (divisor == 0) {
        common.violation("x86", "divide_by_zero", "division attempted with EDX:EAX=0x{x}:0x{x} divisor=0", .{ edx_before, eax_before });
        return;
    }
    const dividend = (@as(u64, edx_before) << 32) | eax_before;
    const expected_q: u32 = @truncate(dividend / divisor);
    const expected_r: u32 = @truncate(dividend % divisor);
    if (eax_after != expected_q or edx_after != expected_r)
        common.violation("x86", "div_result", "div mismatch dividend=0x{x} divisor=0x{x} got q=0x{x} r=0x{x} expected q=0x{x} r=0x{x}", .{ dividend, divisor, eax_after, edx_after, expected_q, expected_r });
}
