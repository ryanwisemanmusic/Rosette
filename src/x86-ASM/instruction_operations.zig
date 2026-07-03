const std = @import("std");
const testing = std.testing;
const reg_map = @import("register_mapping.zig");
const Register = reg_map.Register;
const RegisterFile = reg_map.RegisterFile;
const Memory = reg_map.Memory;
const runtime_abi = @import("runtime_abi_handshake");
const isa_registry = @import("isa_registry");
const isa_math = isa_registry.math.core;
const highway = isa_registry.highway;
const code_text = @import("entrypoint_code_text_segment");
const reg_trace = @import("register-tracing/runtime.zig");
const flag_trace = @import("flag-handling/runtime.zig");
const string_trace = @import("string-ops/runtime.zig");
const exception_trace = @import("exceptions/runtime.zig");

fn applyMathFlag(current: u1, value: isa_math.FlagValue) u1 {
    return switch (value) {
        .clear => 0,
        .set => 1,
        .preserve, .undefined => current,
    };
}

fn applyMathFlags(regs: *RegisterFile, flags: isa_math.Flags) void {
    regs.flags.cf = applyMathFlag(regs.flags.cf, flags.cf);
    regs.flags.pf = applyMathFlag(regs.flags.pf, flags.pf);
    regs.flags.af = applyMathFlag(regs.flags.af, flags.af);
    regs.flags.zf = applyMathFlag(regs.flags.zf, flags.zf);
    regs.flags.sf = applyMathFlag(regs.flags.sf, flags.sf);
    regs.flags.of = applyMathFlag(regs.flags.of, flags.of);
}

fn mathResult32(result: isa_math.IntegerResult) u32 {
    return @as(u32, @truncate(result.dest));
}

fn mathInputFlags(regs: *const RegisterFile) isa_math.InputFlags {
    return .{
        .cf = regs.flags.cf == 1,
        .of = regs.flags.of == 1,
        .af = regs.flags.af == 1,
    };
}

fn evaluateHighway32(regs: *RegisterFile, op: highway.BinaryOp, lhs: u32, rhs: u32) u32 {
    const evaluated = highway.evaluate(op, .bits32, lhs, rhs, regs.flags.raw());
    regs.flags = reg_map.Flags.fromRaw(evaluated.rflags);
    return @truncate(evaluated.value);
}

/// Operand types used by x86 instructions in this emulator.
pub const Operand = union(enum) {
    reg: Register,
    imm: u32,
    mem_direct: u32, // [address]
    mem_reg: Register, // [register]
    mem_index: struct { base: Register, index: u32 }, // [reg + offset]
    mem_reg2: struct { base: Register, index: Register }, // [base + index*4]
};

pub const ExecutionMode = enum {
    scripted,
    raw_x86_pe,
};

/// Operations executor — holds the machine state and runs instructions.
pub const Executor = struct {
    regs: RegisterFile = .{},
    mem: Memory,
    execution_mode: ExecutionMode = .scripted,
    // Label positions for control-flow resolution (name → address)
    labels: std.StringHashMap(u32),
    // Import handler table — maps external symbol name to handler
    import_table: std.StringHashMap(*const fn (ctx: *Executor) void),
    // Interrupt vector table (256 vectors, for future x86 interrupt dispatch)
    interrupt_vector: [256]?*const fn (*Executor) void = [_]?*const fn (*Executor) void{null} ** 256,
    loaded_image_size: u32 = 0,
    code_text_segments: [code_text.max_segments]code_text.Segment = [_]code_text.Segment{code_text.Segment.init(0, 0, false, "")} ** code_text.max_segments,
    code_text_count: usize = 0,
    terminated: bool = false,
    exit_code: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, mem_size: u32) Executor {
        return .{
            .mem = Memory.init(allocator, mem_size),
            .labels = std.StringHashMap(u32).init(allocator),
            .import_table = std.StringHashMap(*const fn (ctx: *Executor) void).init(allocator),
        };
    }

    pub fn setRawX86PeMode(self: *Executor) void {
        self.execution_mode = .raw_x86_pe;
    }

    pub fn setLoadedImageSize(self: *Executor, image_size: u32) void {
        self.loaded_image_size = image_size;
    }

    pub fn terminate(self: *Executor, code: u32) void {
        self.terminated = true;
        self.exit_code = code;
        self.regs.eax = code;
    }

    pub fn clearCodeTextSegments(self: *Executor) void {
        self.code_text_count = 0;
    }

    pub fn addCodeTextSegment(self: *Executor, segment: code_text.Segment) void {
        if (self.code_text_count >= self.code_text_segments.len) return;
        self.code_text_segments[self.code_text_count] = segment;
        self.code_text_count += 1;
    }

    pub fn codeTextGuard(self: *const Executor) code_text.Guard {
        const image_size = if (self.loaded_image_size != 0)
            self.loaded_image_size
        else
            @as(u32, @intCast(self.mem.data.len));
        return .{
            .image_base = self.mem.base,
            .image_size = image_size,
            .segments = self.code_text_segments[0..self.code_text_count],
        };
    }

    pub fn deinit(self: *Executor) void {
        self.mem.deinit();
        self.labels.deinit();
        self.import_table.deinit();
    }

    // ---- Data movement ----

    pub fn mov_reg_imm(self: *Executor, dst: Register, imm: u32) void {
        self.regs.set(dst, mathResult32(isa_math.mov(.bits32, imm)));
    }

    pub fn mov_reg_reg(self: *Executor, dst: Register, src: Register) void {
        self.regs.set(dst, mathResult32(isa_math.mov(.bits32, self.regs.get(src))));
    }

    pub fn mov_reg_mem(self: *Executor, dst: Register, addr: u32) void {
        self.regs.set(dst, mathResult32(isa_math.mov(.bits32, self.mem.read32(addr))));
    }

    pub fn mov_mem_reg(self: *Executor, addr: u32, src: Register) void {
        self.mem.write32(addr, mathResult32(isa_math.mov(.bits32, self.regs.get(src))));
    }

    pub fn mov_mem_imm(self: *Executor, addr: u32, imm: u32) void {
        self.mem.write32(addr, mathResult32(isa_math.mov(.bits32, imm)));
    }

    pub fn movzx_reg_mem(self: *Executor, dst: Register, addr: u32) void {
        self.regs.set(dst, self.mem.read8(addr));
    }

    /// movzx reg, reg (zero-extend from low 16 bits)
    pub fn movzx_reg_reg16(self: *Executor, dst: Register, src: Register) void {
        self.regs.set(dst, self.regs.get16(src));
    }

    pub fn lea_reg_mem(self: *Executor, dst: Register, addr: u32) void {
        self.regs.set(dst, addr);
    }

    // ---- Stack operations ----

    pub fn push(self: *Executor, value: u32) void {
        self.regs.push(&self.mem, value);
    }

    pub fn pop(self: *Executor, dst: Register) void {
        self.regs.set(dst, self.regs.pop(&self.mem));
    }

    // ---- Arithmetic ----

    pub fn add_reg_reg(self: *Executor, dst: Register, src: Register) void {
        const a = self.regs.get(dst);
        const b = self.regs.get(src);
        const flags_before = self.regs.flags.raw();
        const result = evaluateHighway32(&self.regs, .add, a, b);
        self.regs.set(dst, result);
        runtime_abi.x86.validateArithmetic32(.add, a, b, result, self.regs.flags.zf, self.regs.flags.sf, self.regs.flags.cf, self.regs.flags.of);
        flag_trace.validateArithmeticFlags("add_reg_reg", flags_before, &self.regs, a, b, result, .{
            .updated_mask = flag_trace.arithmeticMask(),
            .preserved_mask = flag_trace.preservedControlMask(),
        }, false);
        reg_trace.logOperation("add_reg_reg", "add", a, b, result, 32, flags_before, self.regs.flags.raw());
    }

    pub fn add_reg_imm(self: *Executor, dst: Register, imm: u32) void {
        const a = self.regs.get(dst);
        const flags_before = self.regs.flags.raw();
        const result = evaluateHighway32(&self.regs, .add, a, imm);
        self.regs.set(dst, result);
        runtime_abi.x86.validateArithmetic32(.add, a, imm, result, self.regs.flags.zf, self.regs.flags.sf, self.regs.flags.cf, self.regs.flags.of);
        flag_trace.validateArithmeticFlags("add_reg_imm", flags_before, &self.regs, a, imm, result, .{
            .updated_mask = flag_trace.arithmeticMask(),
            .preserved_mask = flag_trace.preservedControlMask(),
        }, false);
        reg_trace.logOperation("add_reg_imm", "add", a, imm, result, 32, flags_before, self.regs.flags.raw());
    }

    pub fn sub_reg_reg(self: *Executor, dst: Register, src: Register) void {
        const a = self.regs.get(dst);
        const b = self.regs.get(src);
        const flags_before = self.regs.flags.raw();
        const result = evaluateHighway32(&self.regs, .sub, a, b);
        self.regs.set(dst, result);
        runtime_abi.x86.validateArithmetic32(.sub, a, b, result, self.regs.flags.zf, self.regs.flags.sf, self.regs.flags.cf, self.regs.flags.of);
        flag_trace.validateArithmeticFlags("sub_reg_reg", flags_before, &self.regs, a, b, result, .{
            .updated_mask = flag_trace.arithmeticMask(),
            .preserved_mask = flag_trace.preservedControlMask(),
        }, true);
        reg_trace.logOperation("sub_reg_reg", "sub", a, b, result, 32, flags_before, self.regs.flags.raw());
    }

    pub fn sub_reg_imm(self: *Executor, dst: Register, imm: u32) void {
        const a = self.regs.get(dst);
        const flags_before = self.regs.flags.raw();
        const result = evaluateHighway32(&self.regs, .sub, a, imm);
        self.regs.set(dst, result);
        runtime_abi.x86.validateArithmetic32(.sub, a, imm, result, self.regs.flags.zf, self.regs.flags.sf, self.regs.flags.cf, self.regs.flags.of);
        flag_trace.validateArithmeticFlags("sub_reg_imm", flags_before, &self.regs, a, imm, result, .{
            .updated_mask = flag_trace.arithmeticMask(),
            .preserved_mask = flag_trace.preservedControlMask(),
        }, true);
        reg_trace.logOperation("sub_reg_imm", "sub", a, imm, result, 32, flags_before, self.regs.flags.raw());
    }

    pub fn inc(self: *Executor, dst: Register) void {
        const val = self.regs.get(dst);
        const flags_before = self.regs.flags.raw();
        const math = isa_math.inc(.bits32, val, mathInputFlags(&self.regs));
        const result = mathResult32(math);
        applyMathFlags(&self.regs, math.flags);
        self.regs.set(dst, result);
        runtime_abi.x86.validateArithmetic32(.inc, val, 1, result, self.regs.flags.zf, self.regs.flags.sf, self.regs.flags.cf, self.regs.flags.of);
        flag_trace.validateArithmeticFlags("inc", flags_before, &self.regs, val, 1, result, .{
            .updated_mask = flag_trace.incDecMask(),
            .preserved_mask = flag_trace.preservedControlMask() | flag_trace.arithmeticMask() & (1 << 0),
        }, false);
        reg_trace.logOperation("inc", "inc", val, 1, result, 32, flags_before, self.regs.flags.raw());
    }

    pub fn dec(self: *Executor, dst: Register) void {
        const val = self.regs.get(dst);
        const flags_before = self.regs.flags.raw();
        const math = isa_math.dec(.bits32, val, mathInputFlags(&self.regs));
        const result = mathResult32(math);
        applyMathFlags(&self.regs, math.flags);
        self.regs.set(dst, result);
        runtime_abi.x86.validateArithmetic32(.dec, val, 1, result, self.regs.flags.zf, self.regs.flags.sf, self.regs.flags.cf, self.regs.flags.of);
        flag_trace.validateArithmeticFlags("dec", flags_before, &self.regs, val, 1, result, .{
            .updated_mask = flag_trace.incDecMask(),
            .preserved_mask = flag_trace.preservedControlMask() | flag_trace.arithmeticMask() & (1 << 0),
        }, true);
        reg_trace.logOperation("dec", "dec", val, 1, result, 32, flags_before, self.regs.flags.raw());
    }

    pub fn mul_reg(self: *Executor, src: Register) void {
        // unsigned mul: EDX:EAX = EAX * src
        const a = self.regs.eax;
        const b = self.regs.get(src);
        const flags_before = self.regs.flags.raw();
        const math = isa_math.mul(.bits32, a, b);
        const result = (@as(u64, math.high) << 32) | math.dest;
        self.regs.eax = mathResult32(math);
        self.regs.edx = @as(u32, @truncate(math.high));
        applyMathFlags(&self.regs, math.flags);
        runtime_abi.x86.validateMul32(false, a, b, self.regs.eax, self.regs.edx, self.regs.flags.cf, self.regs.flags.of);
        reg_trace.logOperation("mul_reg", "mul", a, b, result, 64, flags_before, self.regs.flags.raw());
    }

    pub fn imul_reg(self: *Executor, src: Register) void {
        // signed mul: EDX:EAX = EAX * src
        const a = @as(i32, @bitCast(self.regs.eax));
        const b = @as(i32, @bitCast(self.regs.get(src)));
        const flags_before = self.regs.flags.raw();
        const math = isa_math.imul(.bits32, @as(u32, @bitCast(a)), @as(u32, @bitCast(b)));
        const result = (@as(u64, math.high) << 32) | math.dest;
        self.regs.eax = mathResult32(math);
        self.regs.edx = @as(u32, @truncate(math.high));
        applyMathFlags(&self.regs, math.flags);
        runtime_abi.x86.validateMul32(true, @bitCast(a), @bitCast(b), self.regs.eax, self.regs.edx, self.regs.flags.cf, self.regs.flags.of);
        reg_trace.logOperation(
            "imul_reg",
            "imul",
            @as(u64, @as(u32, @bitCast(a))),
            @as(u64, @as(u32, @bitCast(b))),
            result,
            64,
            flags_before,
            self.regs.flags.raw(),
        );
    }

    pub fn div_reg(self: *Executor, src: Register) void {
        // unsigned div: EAX = EDX:EAX / src, EDX = remainder
        const divisor = self.regs.get(src);
        const edx_before = self.regs.edx;
        const eax_before = self.regs.eax;
        const flags_before = self.regs.flags.raw();
        const dividend = (@as(u64, edx_before) << 32) | eax_before;
        const math = isa_math.divUnsigned(.bits32, edx_before, eax_before, divisor);
        if (math.trap == .divide_error) {
            self.regs.pending_exception = 0;
            exception_trace.logFault("div_reg", .divide_error, 0, 0, self.regs.eip, self.regs.eip, &self.regs);
            if (divisor == 0)
                runtime_abi.x86.validateDiv32(edx_before, eax_before, divisor, self.regs.eax, self.regs.edx);
            reg_trace.logOperation("div_reg", "div", dividend, divisor, 0, 64, flags_before, self.regs.flags.raw());
            return;
        }
        self.regs.eax = @as(u32, @truncate(math.quotient));
        self.regs.edx = @as(u32, @truncate(math.remainder));
        applyMathFlags(&self.regs, math.flags);
        runtime_abi.x86.validateDiv32(edx_before, eax_before, divisor, self.regs.eax, self.regs.edx);
        reg_trace.logOperation("div_reg", "div", dividend, divisor, self.regs.eax, 32, flags_before, self.regs.flags.raw());
    }

    pub fn xor_reg_reg(self: *Executor, dst: Register, src: Register) void {
        const lhs = self.regs.get(dst);
        const rhs = self.regs.get(src);
        const flags_before = self.regs.flags.raw();
        const result = evaluateHighway32(&self.regs, .bit_xor, lhs, rhs);
        self.regs.set(dst, result);
        runtime_abi.x86.validateArithmetic32(.logical, lhs, rhs, result, self.regs.flags.zf, self.regs.flags.sf, self.regs.flags.cf, self.regs.flags.of);
        flag_trace.validateLogicalFlags("xor_reg_reg", flags_before, &self.regs, result, .{
            .updated_mask = flag_trace.logicalMask(),
            .preserved_mask = flag_trace.preservedControlMask(),
            .undefined_mask = 1 << 4,
        });
        reg_trace.logOperation("xor_reg_reg", "xor", lhs, rhs, result, 32, flags_before, self.regs.flags.raw());
    }

    pub fn and_reg_reg(self: *Executor, dst: Register, src: Register) void {
        const lhs = self.regs.get(dst);
        const rhs = self.regs.get(src);
        const flags_before = self.regs.flags.raw();
        const result = evaluateHighway32(&self.regs, .bit_and, lhs, rhs);
        self.regs.set(dst, result);
        runtime_abi.x86.validateArithmetic32(.test_and, lhs, rhs, result, self.regs.flags.zf, self.regs.flags.sf, self.regs.flags.cf, self.regs.flags.of);
        flag_trace.validateLogicalFlags("and_reg_reg", flags_before, &self.regs, result, .{
            .updated_mask = flag_trace.logicalMask(),
            .preserved_mask = flag_trace.preservedControlMask(),
            .undefined_mask = 1 << 4,
        });
        reg_trace.logOperation("and_reg_reg", "and", lhs, rhs, result, 32, flags_before, self.regs.flags.raw());
    }

    pub fn or_reg_reg(self: *Executor, dst: Register, src: Register) void {
        const lhs = self.regs.get(dst);
        const rhs = self.regs.get(src);
        const flags_before = self.regs.flags.raw();
        const result = evaluateHighway32(&self.regs, .bit_or, lhs, rhs);
        self.regs.set(dst, result);
        runtime_abi.x86.validateArithmetic32(.logical, lhs, rhs, result, self.regs.flags.zf, self.regs.flags.sf, self.regs.flags.cf, self.regs.flags.of);
        flag_trace.validateLogicalFlags("or_reg_reg", flags_before, &self.regs, result, .{
            .updated_mask = flag_trace.logicalMask(),
            .preserved_mask = flag_trace.preservedControlMask(),
            .undefined_mask = 1 << 4,
        });
        reg_trace.logOperation("or_reg_reg", "or", lhs, rhs, result, 32, flags_before, self.regs.flags.raw());
    }

    pub fn not_reg(self: *Executor, dst: Register) void {
        const lhs = self.regs.get(dst);
        const flags_before = self.regs.flags.raw();
        const result = ~lhs;
        self.regs.set(dst, result);
        flag_trace.validatePreservedFlags("not_reg", flags_before, self.regs.flags.raw(), ~@as(u64, 0) & (flag_trace.preservedControlMask() | flag_trace.arithmeticMask()), &self.regs);
        reg_trace.logOperation("not_reg", "not", lhs, 0, result, 32, self.regs.flags.raw(), self.regs.flags.raw());
    }

    pub fn neg_reg(self: *Executor, dst: Register) void {
        const val = self.regs.get(dst);
        const flags_before = self.regs.flags.raw();
        const result = (~val) +% 1;
        self.regs.update_zsco(val, 1, result, true);
        self.regs.set(dst, result);
        flag_trace.validateArithmeticFlags("neg_reg", flags_before, &self.regs, 0, val, result, .{
            .updated_mask = flag_trace.arithmeticMask(),
            .preserved_mask = flag_trace.preservedControlMask(),
        }, true);
        reg_trace.logOperation("neg_reg", "neg", val, 0, result, 32, flags_before, self.regs.flags.raw());
    }

    pub fn shl_reg_cl(self: *Executor, dst: Register) void {
        const cnt: u5 = @truncate(self.regs.ecx & 0x1F);
        if (cnt == 0) return;
        const val = self.regs.get(dst);
        const flags_before = self.regs.flags.raw();
        self.regs.set(dst, val << cnt);
        const shift_back: u5 = @truncate(@as(u6, 32) - cnt);
        self.regs.flags.cf = @intCast((val >> shift_back) & 1);
        self.regs.update_zs(self.regs.get(dst));
        flag_trace.validateLogicalFlags("shl_reg_cl", flags_before, &self.regs, self.regs.get(dst), .{
            .updated_mask = flag_trace.shiftMask(),
            .preserved_mask = flag_trace.preservedControlMask(),
            .undefined_mask = (1 << 4),
        });
        reg_trace.logOperation("shl_reg_cl", "shl", val, cnt, self.regs.get(dst), 32, flags_before, self.regs.flags.raw());
    }

    pub fn shr_reg_cl(self: *Executor, dst: Register) void {
        const cnt: u5 = @truncate(self.regs.ecx & 0x1F);
        if (cnt == 0) return;
        const val = self.regs.get(dst);
        const flags_before = self.regs.flags.raw();
        self.regs.flags.cf = @intCast((val >> (cnt - 1)) & 1);
        self.regs.set(dst, val >> cnt);
        self.regs.update_zs(self.regs.get(dst));
        flag_trace.validateLogicalFlags("shr_reg_cl", flags_before, &self.regs, self.regs.get(dst), .{
            .updated_mask = flag_trace.shiftMask(),
            .preserved_mask = flag_trace.preservedControlMask(),
            .undefined_mask = (1 << 4),
        });
        reg_trace.logOperation("shr_reg_cl", "shr", val, cnt, self.regs.get(dst), 32, flags_before, self.regs.flags.raw());
    }

    pub fn ror_reg_cl(self: *Executor, dst: Register) void {
        const count = self.regs.ecx & 0x1F;
        if (count == 0) return;
        const val = self.regs.get(dst);
        self.regs.set(dst, std.math.rotr(u32, val, count));
        self.regs.flags.cf = @intCast((self.regs.get(dst) >> 31) & 1);
    }

    pub fn shl_reg_imm(self: *Executor, dst: Register, count: u5) void {
        if (count == 0) return;
        const val = self.regs.get(dst);
        self.regs.set(dst, val << count);
        const shift_back: u5 = @truncate(@as(u6, 32) - count);
        self.regs.flags.cf = @intCast((val >> shift_back) & 1);
        self.regs.update_zs(self.regs.get(dst));
    }

    // ---- Comparison and test ----

    pub fn cmp_reg_reg(self: *Executor, a: Register, b: Register) void {
        const lhs = self.regs.get(a);
        const rhs = self.regs.get(b);
        const flags_before = self.regs.flags.raw();
        const result = evaluateHighway32(&self.regs, .cmp, lhs, rhs);
        runtime_abi.x86.validateArithmetic32(.cmp, lhs, rhs, result, self.regs.flags.zf, self.regs.flags.sf, self.regs.flags.cf, self.regs.flags.of);
        flag_trace.validateArithmeticFlags("cmp_reg_reg", flags_before, &self.regs, lhs, rhs, result, .{
            .updated_mask = flag_trace.arithmeticMask(),
            .preserved_mask = flag_trace.preservedControlMask(),
        }, true);
        reg_trace.logOperation("cmp_reg_reg", "cmp", lhs, rhs, result, 32, flags_before, self.regs.flags.raw());
    }

    pub fn cmp_reg_imm(self: *Executor, a: Register, imm: u32) void {
        const lhs = self.regs.get(a);
        const flags_before = self.regs.flags.raw();
        const result = evaluateHighway32(&self.regs, .cmp, lhs, imm);
        runtime_abi.x86.validateArithmetic32(.cmp, lhs, imm, result, self.regs.flags.zf, self.regs.flags.sf, self.regs.flags.cf, self.regs.flags.of);
        flag_trace.validateArithmeticFlags("cmp_reg_imm", flags_before, &self.regs, lhs, imm, result, .{
            .updated_mask = flag_trace.arithmeticMask(),
            .preserved_mask = flag_trace.preservedControlMask(),
        }, true);
        reg_trace.logOperation("cmp_reg_imm", "cmp", lhs, imm, result, 32, flags_before, self.regs.flags.raw());
    }

    pub fn cmp_mem_imm(self: *Executor, addr: u32, imm: u32) void {
        const lhs = self.mem.read32(addr);
        const result = evaluateHighway32(&self.regs, .cmp, lhs, imm);
        runtime_abi.x86.validateArithmetic32(.cmp, lhs, imm, result, self.regs.flags.zf, self.regs.flags.sf, self.regs.flags.cf, self.regs.flags.of);
    }

    pub fn test_reg_reg(self: *Executor, a: Register, b: Register) void {
        const lhs = self.regs.get(a);
        const rhs = self.regs.get(b);
        const flags_before = self.regs.flags.raw();
        const result = evaluateHighway32(&self.regs, .test_bits, lhs, rhs);
        runtime_abi.x86.validateArithmetic32(.test_and, lhs, rhs, result, self.regs.flags.zf, self.regs.flags.sf, self.regs.flags.cf, self.regs.flags.of);
        flag_trace.validateLogicalFlags("test_reg_reg", flags_before, &self.regs, result, .{
            .updated_mask = flag_trace.logicalMask(),
            .preserved_mask = flag_trace.preservedControlMask(),
            .undefined_mask = 1 << 4,
        });
        reg_trace.logOperation("test_reg_reg", "test", lhs, rhs, result, 32, flags_before, self.regs.flags.raw());
    }

    // ---- Control flow ----

    pub fn jmp(self: *Executor, target: u32) void {
        self.regs.eip = target;
    }

    pub fn jz(self: *Executor, target: u32) void {
        if (self.regs.flags.zf == 1) self.regs.eip = target;
    }

    pub fn jnz(self: *Executor, target: u32) void {
        if (self.regs.flags.zf == 0) self.regs.eip = target;
    }

    pub fn jne(self: *Executor, target: u32) void {
        self.jnz(target);
    }

    pub fn je(self: *Executor, target: u32) void {
        self.jz(target);
    }

    pub fn jl(self: *Executor, target: u32) void {
        // signed less-than: SF != OF
        if (self.regs.flags.sf != self.regs.flags.of) self.regs.eip = target;
    }

    pub fn jge(self: *Executor, target: u32) void {
        // signed greater-or-equal: SF == OF
        if (self.regs.flags.sf == self.regs.flags.of) self.regs.eip = target;
    }

    pub fn jle(self: *Executor, target: u32) void {
        // signed less-or-equal: ZF=1 or SF != OF
        if (self.regs.flags.zf == 1 or self.regs.flags.sf != self.regs.flags.of)
            self.regs.eip = target;
    }

    pub fn jg(self: *Executor, target: u32) void {
        // signed greater: ZF=0 and SF == OF
        if (self.regs.flags.zf == 0 and self.regs.flags.sf == self.regs.flags.of)
            self.regs.eip = target;
    }

    /// Call a procedure by address (push return address, jump to target).
    pub fn call(self: *Executor, target: u32) void {
        self.push(self.regs.eip);
        self.regs.eip = target;
    }

    /// Return from procedure (pop return address and jump).
    pub fn ret(self: *Executor) void {
        self.regs.eip = self.regs.pop(&self.mem);
    }

    /// Return with immediate pop (pop return address, then pop N additional bytes).
    pub fn ret_imm(self: *Executor, bytes: u16) void {
        self.regs.eip = self.regs.pop(&self.mem);
        self.regs.esp +|= bytes;
    }

    // ---- REPNE SCASB ----
    // repne scasb: compare AL with byte at [EDI], set flags, inc/dec EDI, dec ECX, loop if ECX>0
    pub fn repne_scasb(self: *Executor) void {
        const count_before = self.regs.ecx;
        const dst_before = self.regs.edi;
        var terminated_on_match = false;
        if (count_before == 0) {
            string_trace.validateStringOp("repne_scasb", .scas, .repne, &self.regs, count_before, self.regs.ecx, self.regs.esi, self.regs.esi, dst_before, self.regs.edi, 1, false, false);
            return;
        }
        while (self.regs.ecx != 0) {
            const before_edi = self.regs.edi;
            const lhs = self.regs.eax & 0xFF;
            const rhs = self.mem.read8(self.regs.edi);
            applyMathFlags(&self.regs, isa_math.sub(.bits8, lhs, rhs).flags);
            if (self.regs.flags.df == 0)
                self.regs.edi +|= 1
            else
                self.regs.edi -|= 1;
            flag_trace.validateStringDirection("repne_scasb", before_edi, self.regs.edi, 1, &self.regs);
            self.regs.ecx -|= 1;
            if (self.regs.flags.zf == 1) {
                terminated_on_match = true;
                break;
            }
        }
        string_trace.validateStringOp("repne_scasb", .scas, .repne, &self.regs, count_before, self.regs.ecx, self.regs.esi, self.regs.esi, dst_before, self.regs.edi, 1, terminated_on_match, false);
    }

    // ---- Import dispatch ----
    // Look up an external symbol in the import table and call its handler.

    pub fn dispatch_import(self: *Executor, name: []const u8) void {
        if (self.import_table.get(name)) |handler| {
            handler(self);
        }
    }

    // ---- Interrupt dispatch ----
    // Reserved for future x86 interrupt handling (int 0x80, etc.)

    pub fn raise_interrupt(self: *Executor, vector: u8) void {
        if (self.interrupt_vector[vector]) |handler| {
            handler(self);
        }
    }
};

// ---- Tests ----

fn expectMathFlag(expected: isa_math.FlagValue, actual: u1) !void {
    switch (expected) {
        .clear => try testing.expectEqual(@as(u1, 0), actual),
        .set => try testing.expectEqual(@as(u1, 1), actual),
        .preserve, .undefined => {},
    }
}

fn expectMathFlags(math: isa_math.IntegerResult, regs: *const RegisterFile) !void {
    try expectMathFlag(math.flags.cf, regs.flags.cf);
    try expectMathFlag(math.flags.pf, regs.flags.pf);
    try expectMathFlag(math.flags.af, regs.flags.af);
    try expectMathFlag(math.flags.zf, regs.flags.zf);
    try expectMathFlag(math.flags.sf, regs.flags.sf);
    try expectMathFlag(math.flags.of, regs.flags.of);
}

test "executor implemented math opcodes are covered by the global ISA registry" {
    const paths = [_][]const u8{
        "MOV/MOV.inc",
        "ADD/ADD.inc",
        "SUB/SUB.inc",
        "INC-DEC/INC.inc",
        "INC-DEC/DEC.inc",
        "MUL/MUL.inc",
        "MUL/IMUL.inc",
        "DIV/DIV.inc",
    };

    for (paths) |path| {
        try testing.expect(isa_registry.math.x86.findByPath(path) != null);
        try testing.expect(isa_registry.math.neon.findByPath(path) != null);
    }
}

test "executor arithmetic uses ISA math core results and flags" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.mov_reg_imm(.eax, 0xffff_ffff);
    ex.mov_reg_imm(.ebx, 1);
    const add_math = isa_math.add(.bits32, 0xffff_ffff, 1);
    ex.add_reg_reg(.eax, .ebx);
    try testing.expectEqual(mathResult32(add_math), ex.regs.eax);
    try expectMathFlags(add_math, &ex.regs);

    ex.mov_reg_imm(.eax, 0);
    ex.mov_reg_imm(.ecx, 1);
    const sub_math = isa_math.sub(.bits32, 0, 1);
    ex.sub_reg_reg(.eax, .ecx);
    try testing.expectEqual(mathResult32(sub_math), ex.regs.eax);
    try expectMathFlags(sub_math, &ex.regs);
}

test "executor inc dec preserve carry through ISA math core" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.flags.cf = 1;
    ex.mov_reg_imm(.eax, 0x7fff_ffff);
    const inc_math = isa_math.inc(.bits32, 0x7fff_ffff, .{ .cf = true });
    ex.inc(.eax);
    try testing.expectEqual(mathResult32(inc_math), ex.regs.eax);
    try expectMathFlags(inc_math, &ex.regs);

    ex.regs.flags.cf = 1;
    ex.mov_reg_imm(.eax, 0x8000_0000);
    const dec_math = isa_math.dec(.bits32, 0x8000_0000, .{ .cf = true });
    ex.dec(.eax);
    try testing.expectEqual(mathResult32(dec_math), ex.regs.eax);
    try expectMathFlags(dec_math, &ex.regs);
}

test "executor mul imul use ISA math core accumulator semantics" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.mov_reg_imm(.eax, 0xffff_ffff);
    ex.mov_reg_imm(.ebx, 2);
    const mul_math = isa_math.mul(.bits32, 0xffff_ffff, 2);
    ex.mul_reg(.ebx);
    try testing.expectEqual(mathResult32(mul_math), ex.regs.eax);
    try testing.expectEqual(@as(u32, @truncate(mul_math.high)), ex.regs.edx);
    try expectMathFlags(mul_math, &ex.regs);

    ex.mov_reg_imm(.eax, 0x8000_0000);
    ex.mov_reg_imm(.ecx, 2);
    const imul_math = isa_math.imul(.bits32, 0x8000_0000, 2);
    ex.imul_reg(.ecx);
    try testing.expectEqual(mathResult32(imul_math), ex.regs.eax);
    try testing.expectEqual(@as(u32, @truncate(imul_math.high)), ex.regs.edx);
    try expectMathFlags(imul_math, &ex.regs);
}

test "executor div uses ISA math core quotient remainder and traps" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.edx = 1;
    ex.regs.eax = 0;
    ex.mov_reg_imm(.ecx, 2);
    const div_math = isa_math.divUnsigned(.bits32, 1, 0, 2);
    ex.div_reg(.ecx);
    try testing.expectEqual(@as(u32, @truncate(div_math.quotient)), ex.regs.eax);
    try testing.expectEqual(@as(u32, @truncate(div_math.remainder)), ex.regs.edx);

    ex.regs.edx = 1;
    ex.regs.eax = 0;
    ex.mov_reg_imm(.ecx, 1);
    const trap_math = isa_math.divUnsigned(.bits32, 1, 0, 1);
    try testing.expectEqual(isa_math.Trap.divide_error, trap_math.trap.?);
    ex.div_reg(.ecx);
    try testing.expectEqual(@as(u32, 0), ex.regs.eax);
    try testing.expectEqual(@as(u32, 1), ex.regs.edx);
}

test "executor cmp derives branch flags from ISA sub math" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.mov_reg_imm(.eax, 5);
    const cmp_math = isa_math.sub(.bits32, 5, 10);
    ex.cmp_reg_imm(.eax, 10);
    try expectMathFlags(cmp_math, &ex.regs);
    try testing.expectEqual(@as(u32, 5), ex.regs.eax);
}

test "mov and arithmetic" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.mov_reg_imm(.eax, 42);
    try testing.expectEqual(@as(u32, 42), ex.regs.eax);

    ex.mov_reg_reg(.ebx, .eax);
    try testing.expectEqual(@as(u32, 42), ex.regs.ebx);

    ex.add_reg_imm(.eax, 10);
    try testing.expectEqual(@as(u32, 52), ex.regs.eax);

    ex.sub_reg_imm(.eax, 2);
    try testing.expectEqual(@as(u32, 50), ex.regs.eax);
}

test "push/pop" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 2048;
    ex.mov_reg_imm(.eax, 0xCAFEBABE);
    ex.push(ex.regs.eax);
    ex.mov_reg_imm(.eax, 0);
    ex.pop(.eax);
    try testing.expectEqual(@as(u32, 0xCAFEBABE), ex.regs.eax);
}

test "conditional jumps" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.mov_reg_imm(.eax, 10);
    ex.mov_reg_imm(.ebx, 10);
    ex.cmp_reg_reg(.eax, .ebx);
    try testing.expectEqual(@as(u1, 1), ex.regs.flags.zf);

    ex.mov_reg_imm(.eax, 5);
    ex.mov_reg_imm(.ebx, 10);
    ex.cmp_reg_reg(.eax, .ebx);
    try testing.expectEqual(@as(u1, 1), ex.regs.flags.cf); // borrow for 5-10
}

test "imul" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.mov_reg_imm(.eax, 7);
    ex.mov_reg_imm(.ecx, 6);
    ex.imul_reg(.ecx);
    try testing.expectEqual(@as(u32, 42), ex.regs.eax);
}

test "repne scasb" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    const str = "Hello\x00world";
    for (str, 0..) |ch, i| {
        ex.mem.write8(@intCast(100 + i), ch);
    }
    ex.mov_reg_imm(.edi, 100);
    ex.mov_reg_imm(.eax, 'o'); // searching for 'o'
    ex.mov_reg_imm(.ecx, 20);
    ex.repne_scasb();
    try testing.expectEqual(@as(u1, 1), ex.regs.flags.zf); // found
    try expectMathFlags(isa_math.sub(.bits8, 'o', 'o'), &ex.regs);
}

test "call/ret" {
    var ex = Executor.init(std.testing.allocator, 4096);
    defer ex.deinit();

    ex.regs.esp = 2048;
    ex.regs.eip = 100;
    ex.call(200);
    try testing.expectEqual(@as(u32, 200), ex.regs.eip);
    // return address should be 100 on stack
    const ret_addr = ex.regs.pop(&ex.mem);
    try testing.expectEqual(@as(u32, 100), ret_addr);
}
