const common = @import("../common.zig");

pub const X86TableShape = struct {
    name: []const u8,
    category: []const u8,
    handler: []const u8,
    jit_lowering: []const u8,
    source_path: []const u8,
    encoding_count: usize,
    has_semantic: bool,
    has_flags: bool,
};

pub const NeonMirrorShape = struct {
    x86_path: []const u8,
    neon_path: []const u8,
    declared_x86_table: []const u8,
    x86_name: []const u8,
    neon_name: []const u8,
    x86_lowering: []const u8,
    neon_lowering: []const u8,
    x86_encoding_count: usize,
    neon_encoding_count: usize,
    x86_has_semantic: bool,
    neon_has_semantic: bool,
    x86_has_flags: bool,
    neon_has_flags: bool,
    neon_has_register_model: bool,
    neon_has_flag_model: bool,
    neon_has_assembly: bool,
};

pub const PpcTableShape = struct {
    name: []const u8,
    mnemonic: []const u8,
    category: []const u8,
    form: []const u8,
    handler: []const u8,
    jit_lowering: []const u8,
    source_path: []const u8,
    encoding_count: usize,
    primary_opcode: u8,
    has_semantic: bool,
    has_registers: bool,
    has_condition_model: bool,
};

pub const PpcNeonMirrorShape = struct {
    ppc_path: []const u8,
    neon_path: []const u8,
    declared_ppc_table: []const u8,
    ppc_name: []const u8,
    neon_name: []const u8,
    ppc_lowering: []const u8,
    neon_lowering: []const u8,
    ppc_encoding_count: usize,
    neon_encoding_count: usize,
    ppc_has_semantic: bool,
    neon_has_semantic: bool,
    ppc_has_registers: bool,
    neon_has_registers: bool,
    ppc_has_condition_model: bool,
    neon_has_condition_model: bool,
    neon_has_register_model: bool,
    neon_has_flag_model: bool,
    neon_has_assembly: bool,
};

pub const NeonLoweringShape = struct {
    name: []const u8,
    jit_lowering: []const u8,
    kind: []const u8,
    assembly: []const u8,
    can_lower: bool,
};

pub const MathSpecShape = struct {
    target_isa: []const u8,
    instruction_name: []const u8,
    path: []const u8,
    source_table_path: []const u8,
    operation: []const u8,
    register_model: []const u8,
    flag_model: []const u8,
    edge_case_count: usize,
    validates_registers: bool,
    validates_flags: bool,
    validates_overflow: bool,
    validates_traps: bool,
};

pub const MathMirrorShape = struct {
    x86_path: []const u8,
    neon_path: []const u8,
    neon_source_table_path: []const u8,
    x86_name: []const u8,
    neon_name: []const u8,
    x86_operation: []const u8,
    neon_operation: []const u8,
    x86_register_model: []const u8,
    neon_register_model: []const u8,
    x86_flag_model: []const u8,
    neon_flag_model: []const u8,
    x86_edge_case_count: usize,
    neon_edge_case_count: usize,
};

pub const MathProofSetShape = struct {
    target_isa: []const u8,
    instruction_name: []const u8,
    path: []const u8,
    operation: []const u8,
    proof_case_count: usize,
};

pub fn init() void {
    common.acquire();
}

pub fn deinit() void {
    common.release();
}

pub fn validateX86Table(shape: X86TableShape) void {
    common.noteValidation();
    if (shape.name.len == 0)
        common.violation("isa-x86", "missing_name", "table={s} has no instruction name", .{shape.source_path});
    if (shape.category.len == 0 or isPlaceholder(shape.category))
        common.violation("isa-x86", "missing_category", "table={s} name={s} has no category", .{ shape.source_path, shape.name });
    if (shape.handler.len == 0)
        common.violation("isa-x86", "missing_handler", "table={s} name={s} has no x86 handler", .{ shape.source_path, shape.name });
    if (shape.jit_lowering.len == 0)
        common.violation("isa-x86", "missing_lowering", "table={s} name={s} has no jit_lowering", .{ shape.source_path, shape.name });
    if (shape.encoding_count == 0)
        common.violation("isa-x86", "missing_encodings", "table={s} name={s} has no encodings", .{ shape.source_path, shape.name });
    if (!shape.has_semantic)
        common.violation("isa-x86", "missing_semantic", "table={s} name={s} has no semantic block", .{ shape.source_path, shape.name });
    if (!shape.has_flags)
        common.violation("isa-x86", "missing_flags", "table={s} name={s} has no flag contract", .{ shape.source_path, shape.name });
}

pub fn validateNoDuplicateInstruction(name: []const u8, lhs_path: []const u8, rhs_path: []const u8) void {
    common.noteValidation();
    common.violation("isa-x86", "duplicate_instruction", "name={s} appears in {s} and {s}", .{ name, lhs_path, rhs_path });
}

pub fn validateMirrorTableCounts(x86_count: usize, neon_count: usize) void {
    common.noteValidation();
    if (x86_count != neon_count)
        common.violation("isa-neon", "mirror_count", "x86 table count {d} differs from NEON mirror count {d}", .{ x86_count, neon_count });
}

pub fn validateMissingNeonMirror(x86_path: []const u8) void {
    common.noteValidation();
    common.violation("isa-neon", "missing_mirror", "x86 table {s} has no NEON mirror table", .{x86_path});
}

pub fn validateNeonMirror(shape: NeonMirrorShape) void {
    common.noteValidation();
    if (!samePathLeaf(shape.x86_path, shape.neon_path))
        common.violation("isa-neon", "mirror_path", "x86={s} neon={s} do not mirror the same instruction folder/name", .{ shape.x86_path, shape.neon_path });
    if (!samePathLeaf(shape.x86_path, shape.declared_x86_table))
        common.violation("isa-neon", "declared_x86_table", "neon={s} declares x86_table={s}, expected {s}", .{ shape.neon_path, shape.declared_x86_table, shape.x86_path });
    if (!asciiEql(shape.x86_name, shape.neon_name))
        common.violation("isa-neon", "mirror_name", "x86={s} neon={s} names differ ({s} vs {s})", .{ shape.x86_path, shape.neon_path, shape.x86_name, shape.neon_name });
    if (!asciiEql(shape.x86_lowering, shape.neon_lowering))
        common.violation("isa-neon", "lowering_tag", "x86={s} neon={s} lowering tags differ ({s} vs {s})", .{ shape.x86_path, shape.neon_path, shape.x86_lowering, shape.neon_lowering });
    if (shape.x86_encoding_count != shape.neon_encoding_count)
        common.violation("isa-neon", "encoding_scope", "x86={s} neon={s} encoding rows differ ({d} vs {d})", .{ shape.x86_path, shape.neon_path, shape.x86_encoding_count, shape.neon_encoding_count });
    if (shape.x86_has_semantic and !shape.neon_has_semantic)
        common.violation("isa-neon", "semantic_scope", "neon={s} dropped x86 semantic contract", .{shape.neon_path});
    if (shape.x86_has_flags and !shape.neon_has_flags)
        common.violation("isa-neon", "flag_scope", "neon={s} dropped x86 flag/MXCSR contract", .{shape.neon_path});
    if (!shape.neon_has_register_model)
        common.violation("isa-neon", "register_model", "neon={s} has no ARM64/NEON register model", .{shape.neon_path});
    if (!shape.neon_has_flag_model)
        common.violation("isa-neon", "flag_model", "neon={s} has no ARM64/NEON flag model", .{shape.neon_path});
    if (!shape.neon_has_assembly)
        common.violation("isa-neon", "assembly_contract", "neon={s} has no ARM64/NEON assembly contract", .{shape.neon_path});
}

pub fn validateNeonLowering(shape: NeonLoweringShape) void {
    common.noteValidation();
    if (shape.jit_lowering.len == 0)
        common.violation("isa-neon", "empty_lowering_tag", "name={s} has no lowering tag", .{shape.name});
    if (shape.kind.len == 0)
        common.violation("isa-neon", "empty_lowering_kind", "name={s} lowering={s} has no lowering kind", .{ shape.name, shape.jit_lowering });
    if (shape.can_lower and shape.assembly.len == 0)
        common.violation("isa-neon", "empty_assembly", "name={s} lowering={s} can_lower=true but has no assembly template", .{ shape.name, shape.jit_lowering });
    if (!shape.can_lower and shape.assembly.len == 0)
        common.violation("isa-neon", "empty_fallback", "name={s} lowering={s} fallback has no fallback call", .{ shape.name, shape.jit_lowering });
    if (shape.can_lower and !looksLikeArm64Assembly(shape.assembly))
        common.violation("isa-neon", "assembly_shape", "name={s} lowering={s} assembly template lacks ARM64/NEON opcodes", .{ shape.name, shape.jit_lowering });
}

pub fn validatePpcTable(shape: PpcTableShape) void {
    common.noteValidation();
    if (shape.name.len == 0)
        common.violation("isa-ppc", "missing_name", "table={s} has no instruction name", .{shape.source_path});
    if (shape.mnemonic.len == 0)
        common.violation("isa-ppc", "missing_mnemonic", "table={s} name={s} has no assembler mnemonic", .{ shape.source_path, shape.name });
    if (shape.category.len == 0 or isPlaceholder(shape.category))
        common.violation("isa-ppc", "missing_category", "table={s} name={s} has no category", .{ shape.source_path, shape.name });
    if (shape.form.len == 0 or isPlaceholder(shape.form))
        common.violation("isa-ppc", "missing_form", "table={s} name={s} has no PowerPC instruction form", .{ shape.source_path, shape.name });
    if (shape.primary_opcode > 63)
        common.violation("isa-ppc", "bad_primary_opcode", "table={s} name={s} primary opcode {d} is outside 0..63", .{ shape.source_path, shape.name, shape.primary_opcode });
    if (shape.handler.len == 0)
        common.violation("isa-ppc", "missing_handler", "table={s} name={s} has no PPC handler", .{ shape.source_path, shape.name });
    if (shape.jit_lowering.len == 0)
        common.violation("isa-ppc", "missing_lowering", "table={s} name={s} has no jit_lowering", .{ shape.source_path, shape.name });
    if (shape.encoding_count == 0)
        common.violation("isa-ppc", "missing_encodings", "table={s} name={s} has no encodings", .{ shape.source_path, shape.name });
    if (!shape.has_semantic)
        common.violation("isa-ppc", "missing_semantic", "table={s} name={s} has no semantic block", .{ shape.source_path, shape.name });
    if (!shape.has_registers)
        common.violation("isa-ppc", "missing_registers", "table={s} name={s} has no read/write register contract", .{ shape.source_path, shape.name });
    if (!shape.has_condition_model)
        common.violation("isa-ppc", "missing_condition_model", "table={s} name={s} has no CR/XER/FPSCR/VSCR contract", .{ shape.source_path, shape.name });
}

pub fn validatePpcMirrorTableCounts(ppc_count: usize, neon_count: usize) void {
    common.noteValidation();
    if (ppc_count != neon_count)
        common.violation("isa-ppc-neon", "mirror_count", "PPC table count {d} differs from NEON mirror count {d}", .{ ppc_count, neon_count });
}

pub fn validateMissingPpcNeonMirror(ppc_path: []const u8) void {
    common.noteValidation();
    common.violation("isa-ppc-neon", "missing_mirror", "PPC table {s} has no ARM64/NEON mirror table", .{ppc_path});
}

pub fn validatePpcNeonMirror(shape: PpcNeonMirrorShape) void {
    common.noteValidation();
    if (!samePathLeaf(shape.ppc_path, shape.neon_path))
        common.violation("isa-ppc-neon", "mirror_path", "ppc={s} neon={s} do not mirror the same instruction folder/name", .{ shape.ppc_path, shape.neon_path });
    if (!samePathLeaf(shape.ppc_path, shape.declared_ppc_table))
        common.violation("isa-ppc-neon", "declared_ppc_table", "neon={s} declares ppc_table={s}, expected {s}", .{ shape.neon_path, shape.declared_ppc_table, shape.ppc_path });
    if (!asciiEql(shape.ppc_name, shape.neon_name))
        common.violation("isa-ppc-neon", "mirror_name", "ppc={s} neon={s} names differ ({s} vs {s})", .{ shape.ppc_path, shape.neon_path, shape.ppc_name, shape.neon_name });
    if (!asciiEql(shape.ppc_lowering, shape.neon_lowering))
        common.violation("isa-ppc-neon", "lowering_tag", "ppc={s} neon={s} lowering tags differ ({s} vs {s})", .{ shape.ppc_path, shape.neon_path, shape.ppc_lowering, shape.neon_lowering });
    if (shape.ppc_encoding_count != shape.neon_encoding_count)
        common.violation("isa-ppc-neon", "encoding_scope", "ppc={s} neon={s} encoding rows differ ({d} vs {d})", .{ shape.ppc_path, shape.neon_path, shape.ppc_encoding_count, shape.neon_encoding_count });
    if (shape.ppc_has_semantic and !shape.neon_has_semantic)
        common.violation("isa-ppc-neon", "semantic_scope", "neon={s} dropped the PPC semantic contract", .{shape.neon_path});
    if (shape.ppc_has_registers and !shape.neon_has_registers)
        common.violation("isa-ppc-neon", "register_scope", "neon={s} dropped the PPC read/write register contract", .{shape.neon_path});
    if (shape.ppc_has_condition_model and !shape.neon_has_condition_model)
        common.violation("isa-ppc-neon", "condition_scope", "neon={s} dropped the PPC CR/XER/FPSCR/VSCR contract", .{shape.neon_path});
    if (!shape.neon_has_register_model)
        common.violation("isa-ppc-neon", "register_model", "neon={s} has no ARM64/NEON register model", .{shape.neon_path});
    if (!shape.neon_has_flag_model)
        common.violation("isa-ppc-neon", "flag_model", "neon={s} has no ARM64/NEON condition model", .{shape.neon_path});
    if (!shape.neon_has_assembly)
        common.violation("isa-ppc-neon", "assembly_contract", "neon={s} has no ARM64/NEON assembly contract", .{shape.neon_path});
}

pub fn validatePpcNeonLowering(shape: NeonLoweringShape) void {
    common.noteValidation();
    if (shape.jit_lowering.len == 0)
        common.violation("isa-ppc-neon", "empty_lowering_tag", "name={s} has no lowering tag", .{shape.name});
    if (shape.kind.len == 0)
        common.violation("isa-ppc-neon", "empty_lowering_kind", "name={s} lowering={s} has no lowering kind", .{ shape.name, shape.jit_lowering });
    if (shape.assembly.len == 0)
        common.violation("isa-ppc-neon", "empty_assembly", "name={s} lowering={s} has no assembly or fallback body", .{ shape.name, shape.jit_lowering });
    if (shape.can_lower and !looksLikePpcArm64Assembly(shape.assembly))
        common.violation("isa-ppc-neon", "assembly_shape", "name={s} lowering={s} assembly template lacks ARM64/NEON opcodes", .{ shape.name, shape.jit_lowering });
    if (!shape.can_lower and !contains(shape.assembly, "bl "))
        common.violation("isa-ppc-neon", "empty_fallback", "name={s} lowering={s} fallback does not call a Rosette helper", .{ shape.name, shape.jit_lowering });
}

pub fn validateMathSpec(shape: MathSpecShape) void {
    common.noteValidation();
    if (shape.target_isa.len == 0)
        common.violation("isa-math", "missing_target", "path={s} has no target ISA", .{shape.path});
    if (shape.instruction_name.len == 0)
        common.violation("isa-math", "missing_name", "path={s} has no instruction name", .{shape.path});
    if (shape.path.len == 0)
        common.violation("isa-math", "missing_path", "name={s} has no math path", .{shape.instruction_name});
    if (shape.source_table_path.len == 0)
        common.violation("isa-math", "missing_source_table", "name={s} path={s} has no source ISA table path", .{ shape.instruction_name, shape.path });
    if (shape.operation.len == 0)
        common.violation("isa-math", "missing_operation", "name={s} path={s} has no operation", .{ shape.instruction_name, shape.path });
    if (shape.register_model.len == 0)
        common.violation("isa-math", "missing_register_model", "name={s} path={s} has no register model", .{ shape.instruction_name, shape.path });
    if (shape.flag_model.len == 0)
        common.violation("isa-math", "missing_flag_model", "name={s} path={s} has no flag model", .{ shape.instruction_name, shape.path });
    if (shape.edge_case_count == 0)
        common.violation("isa-math", "missing_edge_cases", "name={s} path={s} has no edge-case cases", .{ shape.instruction_name, shape.path });
    if (!shape.validates_registers)
        common.violation("isa-math", "register_coverage", "name={s} path={s} does not validate register effects", .{ shape.instruction_name, shape.path });
    if (!shape.validates_flags)
        common.violation("isa-math", "flag_coverage", "name={s} path={s} does not validate flag effects", .{ shape.instruction_name, shape.path });
    if (requiresOverflowCoverage(shape.operation) and !shape.validates_overflow)
        common.violation("isa-math", "overflow_coverage", "name={s} operation={s} lacks overflow/underflow coverage", .{ shape.instruction_name, shape.operation });
    if (requiresTrapCoverage(shape.operation) and !shape.validates_traps)
        common.violation("isa-math", "trap_coverage", "name={s} operation={s} lacks trap/#DE coverage", .{ shape.instruction_name, shape.operation });
}

pub fn validateMathMirror(shape: MathMirrorShape) void {
    common.noteValidation();
    if (!samePathLeaf(shape.x86_path, shape.neon_path))
        common.violation("isa-math", "mirror_path", "x86={s} neon={s} math specs do not mirror the same instruction", .{ shape.x86_path, shape.neon_path });
    if (!samePathLeaf(shape.x86_path, shape.neon_source_table_path))
        common.violation("isa-math", "source_table_path", "neon={s} declares source_table_path={s}, expected {s}", .{ shape.neon_path, shape.neon_source_table_path, shape.x86_path });
    if (!asciiEql(shape.x86_name, shape.neon_name))
        common.violation("isa-math", "mirror_name", "x86={s} neon={s} names differ ({s} vs {s})", .{ shape.x86_path, shape.neon_path, shape.x86_name, shape.neon_name });
    if (!asciiEql(shape.x86_operation, shape.neon_operation))
        common.violation("isa-math", "mirror_operation", "x86={s} neon={s} operations differ ({s} vs {s})", .{ shape.x86_path, shape.neon_path, shape.x86_operation, shape.neon_operation });
    if (!asciiEql(shape.x86_register_model, shape.neon_register_model))
        common.violation("isa-math", "mirror_register_model", "x86={s} neon={s} register models differ ({s} vs {s})", .{ shape.x86_path, shape.neon_path, shape.x86_register_model, shape.neon_register_model });
    if (!asciiEql(shape.x86_flag_model, shape.neon_flag_model))
        common.violation("isa-math", "mirror_flag_model", "x86={s} neon={s} flag models differ ({s} vs {s})", .{ shape.x86_path, shape.neon_path, shape.x86_flag_model, shape.neon_flag_model });
    if (shape.x86_edge_case_count != shape.neon_edge_case_count)
        common.violation("isa-math", "mirror_edge_cases", "x86={s} neon={s} edge-case counts differ ({d} vs {d})", .{ shape.x86_path, shape.neon_path, shape.x86_edge_case_count, shape.neon_edge_case_count });
}

pub fn validateMathProofSet(shape: MathProofSetShape) void {
    common.noteValidation();
    if (shape.target_isa.len == 0)
        common.violation("isa-math-proof", "missing_target", "path={s} has no target ISA for proof set", .{shape.path});
    if (shape.instruction_name.len == 0)
        common.violation("isa-math-proof", "missing_name", "path={s} has no instruction name for proof set", .{shape.path});
    if (shape.path.len == 0)
        common.violation("isa-math-proof", "missing_path", "instruction={s} has no proof-set path", .{shape.instruction_name});
    if (shape.operation.len == 0)
        common.violation("isa-math-proof", "missing_operation", "instruction={s} path={s} has no proof-set operation", .{ shape.instruction_name, shape.path });
    if (shape.proof_case_count < 2)
        common.violation("isa-math-proof", "thin_proof_set", "instruction={s} path={s} has only {d} hardcoded proof cases", .{ shape.instruction_name, shape.path, shape.proof_case_count });
}

fn looksLikePpcArm64Assembly(assembly: []const u8) bool {
    const opcodes = [_][]const u8{
        "add",     "adc",   "sub",     "sbc",   "neg",    "mul",    "smull", "umull",
        "smulh",   "umulh", "sdiv",    "udiv",  "and",    "orr",    "orn",   "eor",
        "eon",     "bic",   "mvn",     "lsl",   "lsr",    "asr",    "ror",   "bfi",
        "ubfx",    "sxt",   "clz",     "rev",   "cmp",    "cset",   "csel",  "ldr",
        "str",     "ldax",  "stlx",    "prfm",  "dmb",    "dsb",    "isb",   "dc ",
        "ic ",     "fadd",  "fsub",    "fmul",  "fdiv",   "fsqrt",  "fmadd", "fmsub",
        "fneg",    "fabs",  "fmov",    "fcvt",  "fcmp",   "fcsel",  "frint", "frecpe",
        "frsqrte", "scvtf", "ucvtf",   "movi",  "dup",    "ext",    "tbl",   "zip",
        "xtn",     "sqxtn", "uqxtn",   "sshll", "cmeq",   "cmhi",   "cmgt",  "cmhs",
        "cmge",    "bsl",   "fmla",    "fmls",  "fmax",   "fmin",   "smax",  "smin",
        "umax",    "umin",  "ushl",    "sshl",  "urhadd", "srhadd", "uqadd", "sqadd",
        "uqsub",   "sqsub", "sqdmulh", "ld1",   "st1",    "mrs",    "msr",   "b.",
        "br ",     "blr",   "b #",     "mov",
    };
    for (opcodes) |opcode| {
        if (contains(assembly, opcode)) return true;
    }
    return false;
}

fn isPlaceholder(value: []const u8) bool {
    return asciiEql(value, "uncategorized") or asciiEql(value, "unknown");
}

fn asciiEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |lhs, rhs| {
        const l = if (lhs >= 'A' and lhs <= 'Z') lhs + 32 else lhs;
        const r = if (rhs >= 'A' and rhs <= 'Z') rhs + 32 else rhs;
        if (l != r) return false;
    }
    return true;
}

fn samePathLeaf(a: []const u8, b: []const u8) bool {
    return asciiEql(a, b);
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (asciiEql(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn looksLikeArm64Assembly(assembly: []const u8) bool {
    const opcodes = [_][]const u8{
        "adds",
        "adcs",
        "subs",
        "fadd",
        "fsub",
        "mul",
        "umulh",
        "smull",
        "udiv",
        "sdiv",
        "ldr",
        "str",
        "bsl",
        "msub",
        "msr",
        "mrs",
    };
    for (opcodes) |opcode| {
        if (contains(assembly, opcode)) return true;
    }
    return false;
}

fn requiresOverflowCoverage(operation: []const u8) bool {
    return contains(operation, "add") or
        contains(operation, "adc") or
        contains(operation, "sub") or
        contains(operation, "inc") or
        contains(operation, "dec") or
        contains(operation, "mul") or
        contains(operation, "div") or
        contains(operation, "float");
}

fn requiresTrapCoverage(operation: []const u8) bool {
    return contains(operation, "divide") or contains(operation, "aam");
}

test "ISA ABI lowering validator accepts ARM64 skeleton" {
    validateNeonLowering(.{
        .name = "ADDPS",
        .jit_lowering = "arm64_neon_fadd_ps",
        .kind = "neon_vector",
        .assembly = "fadd vD.4s, vN.4s, vM.4s",
        .can_lower = true,
    });
}

test "ISA ABI PPC validator accepts a scalar lowering" {
    validatePpcNeonLowering(.{
        .name = "addx",
        .jit_lowering = "arm64_ppc_addx",
        .kind = "arm64_scalar",
        .assembly = "add xD, xA, xB",
        .can_lower = true,
    });
}

test "ISA ABI PPC validator accepts a helper fallback" {
    validatePpcNeonLowering(.{
        .name = "vmsumubm",
        .jit_lowering = "arm64_ppc_vmsumubm_helper",
        .kind = "fallback",
        .assembly = "bl rosette_ppc_vmsum",
        .can_lower = false,
    });
}
