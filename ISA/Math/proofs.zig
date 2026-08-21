const std = @import("std");
const runtime_abi = @import("runtime_abi_handshake");
const core = @import("core.zig");

pub const ExpectedFlags = struct {
    cf: ?core.FlagValue = null,
    pf: ?core.FlagValue = null,
    af: ?core.FlagValue = null,
    zf: ?core.FlagValue = null,
    sf: ?core.FlagValue = null,
    of: ?core.FlagValue = null,
};

pub const ExpectedInteger = struct {
    dest: ?u64 = null,
    high: ?u64 = null,
    quotient: ?u64 = null,
    remainder: ?u64 = null,
    flags: ExpectedFlags = .{},
    trap: ?core.Trap = null,
};

pub const ExpectedAscii = struct {
    ax: ?u16 = null,
    al: ?u8 = null,
    ah: ?u8 = null,
    flags: ExpectedFlags = .{},
    trap: ?core.Trap = null,
};

pub const BinaryIntCase = struct {
    width: core.Width,
    lhs: u64,
    rhs: u64,
    expected: ExpectedInteger,
};

pub const CarryIntCase = struct {
    width: core.Width,
    lhs: u64,
    rhs: u64,
    input: core.InputFlags = .{},
    expected: ExpectedInteger,
};

pub const UnaryIntCase = struct {
    width: core.Width,
    value: u64,
    input: core.InputFlags = .{},
    expected: ExpectedInteger,
};

pub const MovCase = struct {
    width: core.Width,
    src: u64,
    expected: ExpectedInteger,
};

pub const MulCase = struct {
    width: core.Width,
    lhs: u64,
    rhs: u64,
    expected: ExpectedInteger,
};

pub const DivCase = struct {
    width: core.Width,
    high: u64,
    low: u64,
    divisor: u64,
    expected: ExpectedInteger,
};

pub const AsciiAxCase = struct {
    ax: u16,
    input: core.InputFlags = .{},
    expected: ExpectedAscii,
};

pub const AamCase = struct {
    al: u8,
    immediate: u8,
    expected: ExpectedAscii,
};

pub const AadCase = struct {
    ah: u8,
    al: u8,
    immediate: u8,
    expected: ExpectedAscii,
};

pub const PackedF32Case = struct {
    lhs: [4]f32,
    rhs: [4]f32,
    expected: [4]f32,
};

pub const PackedF64Case = struct {
    lhs: [2]f64,
    rhs: [2]f64,
    expected: [2]f64,
};

pub const ScalarF32Case = struct {
    dest_or_src1: [4]f32,
    src: [4]f32,
    expected: [4]f32,
};

pub const ScalarF64Case = struct {
    dest_or_src1: [2]f64,
    src: [2]f64,
    expected: [2]f64,
};

pub const DocumentedContractCase = struct {
    name: []const u8,
    path: []const u8,
    encoding_count: usize,
    source_path_len: usize,
};

pub const ProofCase = union(enum) {
    add: BinaryIntCase,
    adc: CarryIntCase,
    adcx: CarryIntCase,
    adox: CarryIntCase,
    inc: UnaryIntCase,
    dec: UnaryIntCase,
    sub: BinaryIntCase,
    mov: MovCase,
    mul: MulCase,
    imul: MulCase,
    div: DivCase,
    idiv: DivCase,
    aaa: AsciiAxCase,
    aas: AsciiAxCase,
    aam: AamCase,
    aad: AadCase,
    addps: PackedF32Case,
    addpd: PackedF64Case,
    addss_legacy: ScalarF32Case,
    addss_vex: ScalarF32Case,
    addsd_legacy: ScalarF64Case,
    addsd_vex: ScalarF64Case,
    addsubps: PackedF32Case,
    addsubpd: PackedF64Case,
    subps: PackedF32Case,
    subpd: PackedF64Case,
    subss_legacy: ScalarF32Case,
    subss_vex: ScalarF32Case,
    subsd_legacy: ScalarF64Case,
    subsd_vex: ScalarF64Case,
    mulps: PackedF32Case,
    mulpd: PackedF64Case,
    mulss_legacy: ScalarF32Case,
    mulss_vex: ScalarF32Case,
    mulsd_legacy: ScalarF64Case,
    mulsd_vex: ScalarF64Case,
    mulx: MulCase,
    divps: PackedF32Case,
    divpd: PackedF64Case,
    divss_legacy: ScalarF32Case,
    divss_vex: ScalarF32Case,
    divsd_legacy: ScalarF64Case,
    divsd_vex: ScalarF64Case,
    documented_contract: DocumentedContractCase,
};

pub const ProofReport = struct {
    meta: core.InstructionMathMeta,
    cases: []const ProofCase,

    pub fn caseCount(self: ProofReport) usize {
        return self.cases.len;
    }
};

pub fn verify(meta: core.InstructionMathMeta, cases: []const ProofCase) !void {
    try verifyReport(.{ .meta = meta, .cases = cases });
}

/// Whether every case in a report is a documented-contract restatement.
///
/// A documented-contract case carries no values to check: it names the table
/// the instruction came from and nothing else. Two of them are worth no more
/// than one, and in this tree the second is a verbatim copy of the first — so
/// a "at least two cases per table" rule says nothing about these, and
/// everything about the instructions that do model arithmetic.
pub fn isDocumentedContractOnly(report: ProofReport) bool {
    for (report.cases) |proof_case| {
        if (proof_case != .documented_contract) return false;
    }
    return true;
}

pub fn verifyReport(report: ProofReport) !void {
    runtime_abi.isa.validateMathProofSet(.{
        .target_isa = @tagName(report.meta.target_isa),
        .instruction_name = report.meta.name,
        .path = report.meta.path,
        .operation = @tagName(report.meta.operation),
        .proof_case_count = report.caseCount(),
    });

    for (report.cases) |proof_case| {
        try std.testing.expectEqual(report.meta.operation, caseOperation(proof_case));
        // A documented-contract case restates the instruction its own meta
        // already names. On its own that restatement proves nothing — both
        // literals live in the same generated file — so tie the two together:
        // a case copied from a neighbouring instruction then fails here rather
        // than passing as a proof about the wrong opcode.
        if (proof_case == .documented_contract) {
            const case = proof_case.documented_contract;
            try std.testing.expectEqualStrings(report.meta.name, case.name);
            try std.testing.expectEqualStrings(report.meta.path, case.path);
            try std.testing.expectEqualStrings(report.meta.path, report.meta.source_table_path);
        }
        try verifyCase(proof_case);
    }
}

fn caseOperation(proof_case: ProofCase) core.Operation {
    return switch (proof_case) {
        .add => .add,
        .adc => .adc,
        .adcx => .adcx,
        .adox => .adox,
        .inc => .inc,
        .dec => .dec,
        .sub => .sub,
        .mov => .mov,
        .mul => .mul,
        .imul => .imul,
        .div => .div,
        .idiv => .idiv,
        .aaa => .aaa,
        .aas => .aas,
        .aam => .aam,
        .aad => .aad,
        .addps => .addps,
        .addpd => .addpd,
        .addss_legacy, .addss_vex => .addss,
        .addsd_legacy, .addsd_vex => .addsd,
        .addsubps => .addsubps,
        .addsubpd => .addsubpd,
        .subps => .subps,
        .subpd => .subpd,
        .subss_legacy, .subss_vex => .subss,
        .subsd_legacy, .subsd_vex => .subsd,
        .mulps => .mulps,
        .mulpd => .mulpd,
        .mulss_legacy, .mulss_vex => .mulss,
        .mulsd_legacy, .mulsd_vex => .mulsd,
        .mulx => .mulx,
        .divps => .divps,
        .divpd => .divpd,
        .divss_legacy, .divss_vex => .divss,
        .divsd_legacy, .divsd_vex => .divsd,
        .documented_contract => .documented_contract,
    };
}

fn verifyCase(proof_case: ProofCase) !void {
    switch (proof_case) {
        .add => |case| try expectInteger(core.add(case.width, case.lhs, case.rhs), case.expected),
        .adc => |case| try expectInteger(core.adc(case.width, case.lhs, case.rhs, case.input.cf), case.expected),
        .adcx => |case| try expectInteger(core.adcx(case.width, case.lhs, case.rhs, case.input), case.expected),
        .adox => |case| try expectInteger(core.adox(case.width, case.lhs, case.rhs, case.input), case.expected),
        .inc => |case| try expectInteger(core.inc(case.width, case.value, case.input), case.expected),
        .dec => |case| try expectInteger(core.dec(case.width, case.value, case.input), case.expected),
        .sub => |case| try expectInteger(core.sub(case.width, case.lhs, case.rhs), case.expected),
        .mov => |case| try expectInteger(core.mov(case.width, case.src), case.expected),
        .mul => |case| try expectInteger(core.mul(case.width, case.lhs, case.rhs), case.expected),
        .imul => |case| try expectInteger(core.imul(case.width, case.lhs, case.rhs), case.expected),
        .div => |case| try expectInteger(core.divUnsigned(case.width, case.high, case.low, case.divisor), case.expected),
        .idiv => |case| try expectInteger(core.divSigned(case.width, case.high, case.low, case.divisor), case.expected),
        .aaa => |case| try expectAscii(core.aaa(case.ax, case.input), case.expected),
        .aas => |case| try expectAscii(core.aas(case.ax, case.input), case.expected),
        .aam => |case| try expectAscii(core.aam(case.al, case.immediate), case.expected),
        .aad => |case| try expectAscii(core.aad(case.ah, case.al, case.immediate), case.expected),
        .addps => |case| try expectF32x4(core.addps(case.lhs, case.rhs), case.expected),
        .addpd => |case| try expectF64x2(core.addpd(case.lhs, case.rhs), case.expected),
        .addss_legacy => |case| try expectF32x4(core.addss(case.dest_or_src1, case.src), case.expected),
        .addss_vex => |case| try expectF32x4(core.addssVex(case.dest_or_src1, case.src), case.expected),
        .addsd_legacy => |case| try expectF64x2(core.addsd(case.dest_or_src1, case.src), case.expected),
        .addsd_vex => |case| try expectF64x2(core.addsdVex(case.dest_or_src1, case.src), case.expected),
        .addsubps => |case| try expectF32x4(core.addsubps(case.lhs, case.rhs), case.expected),
        .addsubpd => |case| try expectF64x2(core.addsubpd(case.lhs, case.rhs), case.expected),
        .subps => |case| try expectF32x4(core.subps(case.lhs, case.rhs), case.expected),
        .subpd => |case| try expectF64x2(core.subpd(case.lhs, case.rhs), case.expected),
        .subss_legacy => |case| try expectF32x4(core.subss(case.dest_or_src1, case.src), case.expected),
        .subss_vex => |case| try expectF32x4(core.subssVex(case.dest_or_src1, case.src), case.expected),
        .subsd_legacy => |case| try expectF64x2(core.subsd(case.dest_or_src1, case.src), case.expected),
        .subsd_vex => |case| try expectF64x2(core.subsdVex(case.dest_or_src1, case.src), case.expected),
        .mulps => |case| try expectF32x4(core.mulps(case.lhs, case.rhs), case.expected),
        .mulpd => |case| try expectF64x2(core.mulpd(case.lhs, case.rhs), case.expected),
        .mulss_legacy => |case| try expectF32x4(core.mulss(case.dest_or_src1, case.src), case.expected),
        .mulss_vex => |case| try expectF32x4(core.mulssVex(case.dest_or_src1, case.src), case.expected),
        .mulsd_legacy => |case| try expectF64x2(core.mulsd(case.dest_or_src1, case.src), case.expected),
        .mulsd_vex => |case| try expectF64x2(core.mulsdVex(case.dest_or_src1, case.src), case.expected),
        .mulx => |case| try expectInteger(core.mulx(case.width, case.lhs, case.rhs), case.expected),
        .divps => |case| try expectF32x4(core.divps(case.lhs, case.rhs), case.expected),
        .divpd => |case| try expectF64x2(core.divpd(case.lhs, case.rhs), case.expected),
        .divss_legacy => |case| try expectF32x4(core.divss(case.dest_or_src1, case.src), case.expected),
        .divss_vex => |case| try expectF32x4(core.divssVex(case.dest_or_src1, case.src), case.expected),
        .divsd_legacy => |case| try expectF64x2(core.divsd(case.dest_or_src1, case.src), case.expected),
        .divsd_vex => |case| try expectF64x2(core.divsdVex(case.dest_or_src1, case.src), case.expected),
        .documented_contract => |case| try expectDocumentedContract(case),
    }
}

fn expectDocumentedContract(case: DocumentedContractCase) !void {
    try std.testing.expect(case.name.len != 0);
    try std.testing.expect(case.path.len != 0);
    try std.testing.expect(case.encoding_count != 0);
    try std.testing.expectEqual(case.path.len, case.source_path_len);
    try std.testing.expect(std.mem.endsWith(u8, case.path, ".inc"));
}

fn expectInteger(actual: core.IntegerResult, expected: ExpectedInteger) !void {
    if (expected.trap) |trap| {
        try std.testing.expectEqual(trap, actual.trap.?);
        return;
    }
    try std.testing.expectEqual(@as(?core.Trap, null), actual.trap);
    if (expected.dest) |value| try std.testing.expectEqual(value, actual.dest);
    if (expected.high) |value| try std.testing.expectEqual(value, actual.high);
    if (expected.quotient) |value| try std.testing.expectEqual(value, actual.quotient);
    if (expected.remainder) |value| try std.testing.expectEqual(value, actual.remainder);
    try expectFlags(actual.flags, expected.flags);
}

fn expectAscii(actual: core.AsciiAdjustResult, expected: ExpectedAscii) !void {
    if (expected.trap) |trap| {
        try std.testing.expectEqual(trap, actual.trap.?);
        return;
    }
    try std.testing.expectEqual(@as(?core.Trap, null), actual.trap);
    if (expected.ax) |value| try std.testing.expectEqual(value, actual.ax);
    if (expected.al) |value| try std.testing.expectEqual(value, actual.al);
    if (expected.ah) |value| try std.testing.expectEqual(value, actual.ah);
    try expectFlags(actual.flags, expected.flags);
}

fn expectFlags(actual: core.Flags, expected: ExpectedFlags) !void {
    if (expected.cf) |value| try std.testing.expectEqual(value, actual.cf);
    if (expected.pf) |value| try std.testing.expectEqual(value, actual.pf);
    if (expected.af) |value| try std.testing.expectEqual(value, actual.af);
    if (expected.zf) |value| try std.testing.expectEqual(value, actual.zf);
    if (expected.sf) |value| try std.testing.expectEqual(value, actual.sf);
    if (expected.of) |value| try std.testing.expectEqual(value, actual.of);
}

fn expectF32x4(actual: [4]f32, expected: [4]f32) !void {
    for (actual, expected) |actual_lane, expected_lane| {
        try expectF32(actual_lane, expected_lane);
    }
}

fn expectF64x2(actual: [2]f64, expected: [2]f64) !void {
    for (actual, expected) |actual_lane, expected_lane| {
        try expectF64(actual_lane, expected_lane);
    }
}

fn expectF32(actual: f32, expected: f32) !void {
    if (std.math.isNan(expected)) {
        try std.testing.expect(std.math.isNan(actual));
        return;
    }
    try std.testing.expectEqual(@as(u32, @bitCast(expected)), @as(u32, @bitCast(actual)));
}

fn expectF64(actual: f64, expected: f64) !void {
    if (std.math.isNan(expected)) {
        try std.testing.expect(std.math.isNan(actual));
        return;
    }
    try std.testing.expectEqual(@as(u64, @bitCast(expected)), @as(u64, @bitCast(actual)));
}
