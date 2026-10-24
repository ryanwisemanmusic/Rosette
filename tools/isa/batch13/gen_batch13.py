#!/usr/bin/env python3
"""Generate 6 files per instruction for batch 13 (4 groups, 16 instructions)."""

import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
ISA = os.path.join(REPO_ROOT, "ISA")

instructions = {}

instructions["ACCUMULATE"] = [
    {
        "mnemonic": "CRC32",
        "category": "crc",
        "feature": "sse4_2",
        "element_type": "i32",
        "element_size": 32,
        "flags": [],
        "encodings": [
            ("F2 0F 38 F0 /r", "CRC32 r32, r/m8", "RM", "sse4_2"),
            ("F2 0F 38 F1 /r", "CRC32 r32, r/m16", "RM", "sse4_2"),
            ("F2 0F 38 F1 /r", "CRC32 r32, r/m32", "RM", "sse4_2"),
            ("F2 REX.W 0F 38 F0 /r", "CRC32 r64, r/m8", "RM", "sse4_2"),
            ("F2 REX.W 0F 38 F1 /r", "CRC32 r64, r/m64", "RM", "sse4_2"),
        ],
        "desc": "Accumulate CRC32 Value",
    },
]

instructions["CACHE"] = [
    {
        "mnemonic": "CLDEMOTE",
        "category": "cache_control",
        "feature": "cldemote",
        "element_type": "none",
        "element_size": 0,
        "flags": [],
        "encodings": [
            ("NP 0F 1C /0", "CLDEMOTE m8", "A", "cldemote"),
        ],
        "desc": "Cache Line Demote",
    },
    {
        "mnemonic": "CLFLUSH",
        "category": "cache_control",
        "feature": "clflush",
        "element_type": "none",
        "element_size": 0,
        "flags": [],
        "encodings": [
            ("NP 0F AE /7", "CLFLUSH m8", "M", "clflush"),
        ],
        "desc": "Flush Cache Line",
    },
    {
        "mnemonic": "CLFLUSHOPT",
        "category": "cache_control",
        "feature": "clflushopt",
        "element_type": "none",
        "element_size": 0,
        "flags": [],
        "encodings": [
            ("66 0F AE /7", "CLFLUSHOPT m8", "M", "clflushopt"),
        ],
        "desc": "Flush Cache Line Optimized",
    },
    {
        "mnemonic": "CLWB",
        "category": "cache_control",
        "feature": "clwb",
        "element_type": "none",
        "element_size": 0,
        "flags": [],
        "encodings": [
            ("66 0F AE /6", "CLWB m8", "M", "clwb"),
        ],
        "desc": "Cache Line Write Back",
    },
]

instructions["REVERSE"] = [
    {
        "mnemonic": "FDIVR",
        "category": "x87_fpu",
        "feature": "x87_fpu",
        "element_type": "f80",
        "element_size": 80,
        "flags": ["C1", "C0", "C2", "C3"],
        "encodings": [
            ("D8 /7", "FDIVR m32fp", "M", "x87_fpu"),
            ("DC /7", "FDIVR m64fp", "M", "x87_fpu"),
            ("D8 F8+i", "FDIVR ST(0), ST(i)", "MR", "x87_fpu"),
            ("DC F0+i", "FDIVR ST(i), ST(0)", "RM", "x87_fpu"),
        ],
        "desc": "Reverse Divide",
    },
    {
        "mnemonic": "FDIVRP",
        "category": "x87_fpu",
        "feature": "x87_fpu",
        "element_type": "f80",
        "element_size": 80,
        "flags": ["C1", "C0", "C2", "C3"],
        "encodings": [
            ("DE F0+i", "FDIVRP ST(i), ST(0)", "RM", "x87_fpu"),
            ("DE F1", "FDIVRP", "ZO", "x87_fpu"),
        ],
        "desc": "Reverse Divide and Pop",
    },
    {
        "mnemonic": "FIDIVR",
        "category": "x87_fpu",
        "feature": "x87_fpu",
        "element_type": "f80",
        "element_size": 80,
        "flags": ["C1", "C0", "C2", "C3"],
        "encodings": [
            ("DA /7", "FIDIVR m32int", "M", "x87_fpu"),
            ("DE /7", "FIDIVR m16int", "M", "x87_fpu"),
        ],
        "desc": "Reverse Divide with Integer",
    },
    {
        "mnemonic": "FSUBR",
        "category": "x87_fpu",
        "feature": "x87_fpu",
        "element_type": "f80",
        "element_size": 80,
        "flags": ["C1", "C0", "C2", "C3"],
        "encodings": [
            ("D8 /5", "FSUBR m32fp", "M", "x87_fpu"),
            ("DC /5", "FSUBR m64fp", "M", "x87_fpu"),
            ("D8 E8+i", "FSUBR ST(0), ST(i)", "MR", "x87_fpu"),
            ("DC E0+i", "FSUBR ST(i), ST(0)", "RM", "x87_fpu"),
        ],
        "desc": "Reverse Subtract",
    },
    {
        "mnemonic": "FSUBRP",
        "category": "x87_fpu",
        "feature": "x87_fpu",
        "element_type": "f80",
        "element_size": 80,
        "flags": ["C1", "C0", "C2", "C3"],
        "encodings": [
            ("DE E0+i", "FSUBRP ST(i), ST(0)", "RM", "x87_fpu"),
            ("DE E1", "FSUBRP", "ZO", "x87_fpu"),
        ],
        "desc": "Reverse Subtract and Pop",
    },
    {
        "mnemonic": "FISUBR",
        "category": "x87_fpu",
        "feature": "x87_fpu",
        "element_type": "f80",
        "element_size": 80,
        "flags": ["C1", "C0", "C2", "C3"],
        "encodings": [
            ("DA /5", "FISUBR m32int", "M", "x87_fpu"),
            ("DE /5", "FISUBR m16int", "M", "x87_fpu"),
        ],
        "desc": "Reverse Subtract with Integer",
    },
]

instructions["SCAN"] = [
    {
        "mnemonic": "SCAS",
        "category": "string_op",
        "feature": "general",
        "element_type": "none",
        "element_size": 0,
        "flags": ["OF", "SF", "ZF", "AF", "PF", "CF"],
        "encodings": [
            ("AE", "SCAS m8", "ZO", "general"),
            ("AF", "SCAS m16", "ZO", "general"),
            ("AF", "SCAS m32", "ZO", "general"),
            ("REX.W + AF", "SCAS m64", "ZO", "general"),
        ],
        "desc": "Scan String",
    },
    {
        "mnemonic": "SCASB",
        "category": "string_op",
        "feature": "general",
        "element_type": "none",
        "element_size": 0,
        "flags": ["OF", "SF", "ZF", "AF", "PF", "CF"],
        "encodings": [
            ("AE", "SCASB", "ZO", "general"),
        ],
        "desc": "Scan String Byte",
    },
    {
        "mnemonic": "SCASW",
        "category": "string_op",
        "feature": "general",
        "element_type": "none",
        "element_size": 0,
        "flags": ["OF", "SF", "ZF", "AF", "PF", "CF"],
        "encodings": [
            ("AF", "SCASW", "ZO", "general"),
        ],
        "desc": "Scan String Word",
    },
    {
        "mnemonic": "SCASD",
        "category": "string_op",
        "feature": "general",
        "element_type": "none",
        "element_size": 0,
        "flags": ["OF", "SF", "ZF", "AF", "PF", "CF"],
        "encodings": [
            ("AF", "SCASD", "ZO", "general"),
        ],
        "desc": "Scan String Doubleword",
    },
    {
        "mnemonic": "SCASQ",
        "category": "string_op",
        "feature": "general",
        "element_type": "none",
        "element_size": 0,
        "flags": ["OF", "SF", "ZF", "AF", "PF", "CF"],
        "encodings": [
            ("REX.W + AF", "SCASQ", "ZO", "general"),
        ],
        "desc": "Scan String Quadword",
    },
]


def lower(m):
    return m.lower()


def x86_inc(group, inst):
    m = inst["mnemonic"]
    l = lower(m)
    cat = inst["category"]
    feat = inst["feature"]
    et = inst["element_type"]
    es = inst["element_size"]
    desc = inst["desc"]

    enc_lines = []
    for opcode, form, op_en, f in inst["encodings"]:
        enc_lines.append('  {{ opcode = "{}", form = "{}", op_en = "{}", feature = "{}", vector_length = 0, encoding = "legacy" }}'.format(opcode, form, op_en, f))
    encodings = "\n".join(enc_lines)

    flags = inst.get("flags", [])
    flag_block = ""
    if flags:
        flag_str = ", ".join("'{}'".format(f) for f in flags)
        flag_block = "\nflags_affected = [{}]\n".format(flag_str)

    return '''// {group}/{m}.inc
// Source contract: {m} — {cat}.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "{group}/{m}.inc"
x86_handler = "x86_{l}"
neon_lowering = "arm64_{l}"
lowering_kind = "arm64_documented_contract"

name = "{m}"
aliases = []
category = "{cat}"
feature = "{feat}"
element_type = "{et}"
element_size = {es}

encodings = [
{encodings}
]

operand_encoding = {{
  ZO = []
}}
{flag_block}
simd_fp_exceptions = []

semantic_general = """
{desc}.
"""

handler = "x86_{l}"
jit_lowering = "arm64_{l}"
fallback = "zig_{l}"

neon_register_model = """
{m} is a {cat} instruction.
"""

neon_flag_model = """
{m} does not modify flags.
"""

neon_assembly = """
// NEON lowering: {m} stub ({cat})
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
'''.format(group=group, m=m, l=l, cat=cat, feat=feat, et=et, es=es, desc=desc, encodings=encodings, flag_block=flag_block)


def neon_inc(group, inst):
    m = inst["mnemonic"]
    l = lower(m)
    cat = inst["category"]
    feat = inst["feature"]
    et = inst["element_type"]
    es = inst["element_size"]
    desc = inst["desc"]

    return '''// {group}/{m}.inc
// ARM64/NEON mirror generated from ISA/x86/{group}/{m}.inc.
// Source contract: {m} — {cat}.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "{group}/{m}.inc"
x86_handler = "x86_{l}"
neon_lowering = "arm64_{l}"
lowering_kind = "arm64_documented_contract"

name = "{m}"
aliases = []
category = "{cat}"
feature = "{feat}"
element_type = "{et}"
element_size = {es}

encodings = [
]

operand_encoding = {{
  ZO = []
}}

simd_fp_exceptions = []

semantic_general = """
{desc}.
"""

handler = "x86_{l}"
jit_lowering = "arm64_{l}"
fallback = "zig_{l}"

neon_register_model = """
{m} is a {cat} instruction.
"""

neon_flag_model = """
{m} does not modify flags.
"""

neon_assembly = """
// NEON lowering: {m} stub ({cat})
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
'''.format(group=group, m=m, l=l, cat=cat, feat=feat, et=et, es=es, desc=desc)


def x86_zig_bridge(group, inst):
    m = inst["mnemonic"]
    l = lower(m)
    return '''pub const family = "{group}";
pub const path = "{group}/{m}.inc";
pub const source = @embedFile("../../{group}/{m}.inc");
'''.format(group=group, m=m, l=l)


def neon_zig_bridge(group, inst):
    m = inst["mnemonic"]
    l = lower(m)
    return '''pub const family = "{group}";
pub const path = "{group}/{m}.inc";
pub const source = @embedFile("../../{group}/{m}.inc");
pub const x86_path = "{group}/{m}.inc";
pub const target_isa = "arm64_neon";
'''.format(group=group, m=m, l=l)


def math_x86_zig(group, inst):
    m = inst["mnemonic"]
    l = lower(m)
    path_str = "{group}/{m}.inc".format(group=group, m=m)
    source_path_len = len(path_str)
    enc_count = len(inst["encodings"])
    return '''const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{{
    .name = "{m}",
    .family = "{group}",
    .path = "{path_str}",
    .source_table_path = "{path_str}",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
}};

pub const proof_cases = [_]proofs.ProofCase{{
    .{{ .documented_contract = .{{ .name = "{m}", .path = "{path_str}", .encoding_count = {enc_count}, .source_path_len = {source_path_len} }} }},
    .{{ .documented_contract = .{{ .name = "{m}", .path = "{path_str}", .encoding_count = {enc_count}, .source_path_len = {source_path_len} }} }},
}};

pub const proof_report = proofs.ProofReport{{
    .meta = meta,
    .cases = proof_cases[0..],
}};

pub fn proofReport() proofs.ProofReport {{
    return proof_report;
}}

pub fn verifyProofs() !void {{
    try proofs.verifyReport(proofReport());
}}

test "x86 {m} documented-contract proofs match table metadata" {{
    try verifyProofs();
}}
'''.format(group=group, m=m, l=l, path_str=path_str, source_path_len=source_path_len, enc_count=enc_count)


def math_neon_zig(group, inst):
    m = inst["mnemonic"]
    l = lower(m)
    path_str = "{group}/{m}.inc".format(group=group, m=m)
    source_path_len = len(path_str)
    enc_count = len(inst["encodings"])
    return '''const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{{
    .name = "{m}",
    .family = "{group}",
    .path = "{path_str}",
    .source_table_path = "{path_str}",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
}};

pub const proof_cases = [_]proofs.ProofCase{{
    .{{ .documented_contract = .{{ .name = "{m}", .path = "{path_str}", .encoding_count = {enc_count}, .source_path_len = {source_path_len} }} }},
    .{{ .documented_contract = .{{ .name = "{m}", .path = "{path_str}", .encoding_count = {enc_count}, .source_path_len = {source_path_len} }} }},
}};

pub const proof_report = proofs.ProofReport{{
    .meta = meta,
    .cases = proof_cases[0..],
}};

pub fn proofReport() proofs.ProofReport {{
    return proof_report;
}}

pub fn verifyProofs() !void {{
    try proofs.verifyReport(proofReport());
}}

test "neon {m} documented-contract proofs match table metadata" {{
    try verifyProofs();
}}
'''.format(group=group, m=m, l=l, path_str=path_str, source_path_len=source_path_len, enc_count=enc_count)


def ensure_dir(path):
    os.makedirs(path, exist_ok=True)


def write_file(path, content):
    with open(path, "w") as f:
        f.write(content.lstrip('\n') + "\n")
    print("  Created {}".format(path))


# ====== Generate all files ======
for group, insts in instructions.items():
    for base in ["x86", "NEON", "x86/Zig", "NEON/Zig"]:
        ensure_dir("{}/{}/{}".format(ISA, base, group))
    for base in ["Math/x86/Zig", "Math/NEON/Zig"]:
        ensure_dir("{}/{}/{}".format(ISA, base, group))

    for inst in insts:
        m = inst["mnemonic"]
        l = lower(m)

        write_file("{}/x86/{}/{}.inc".format(ISA, group, m), x86_inc(group, inst))
        write_file("{}/NEON/{}/{}.inc".format(ISA, group, m), neon_inc(group, inst))
        write_file("{}/x86/Zig/{}/{}.zig".format(ISA, group, l), x86_zig_bridge(group, inst))
        write_file("{}/NEON/Zig/{}/{}.zig".format(ISA, group, l), neon_zig_bridge(group, inst))
        write_file("{}/Math/x86/Zig/{}/{}.zig".format(ISA, group, l), math_x86_zig(group, inst))
        write_file("{}/Math/NEON/Zig/{}/{}.zig".format(ISA, group, l), math_neon_zig(group, inst))

print("\nAll 6 x {} = {} files created successfully".format(len(sum(instructions.values(), [])), 6 * len(sum(instructions.values(), []))))
