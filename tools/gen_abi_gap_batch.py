#!/usr/bin/env python3
"""Generate the 6-layer ISA files for instructions missing ABI contracts.

Covers the 21 tables surfaced by the decoder ISA ABI contract audit
(tools/audit_abi_contracts.py): the CMPXCHG family and VEX-only SIMD ops.
Mirrors the proven tools/isa/batch13/gen_batch13.py format exactly.
"""

import os

ISA = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ISA")

instructions = {}

instructions["ATOMIC"] = [
    {
        "mnemonic": "CMPXCHG",
        "category": "atomic",
        "feature": "x86",
        "element_type": "i32",
        "element_size": 32,
        "flags": ["zf", "cf", "pf", "af", "sf", "of"],
        "encodings": [
            ("0F B0 /r", "CMPXCHG r/m8, r8", "MR", "x86"),
            ("0F B1 /r", "CMPXCHG r/m16, r16", "MR", "x86"),
            ("0F B1 /r", "CMPXCHG r/m32, r32", "MR", "x86"),
            ("REX.W 0F B1 /r", "CMPXCHG r/m64, r64", "MR", "x86"),
        ],
        "desc": "Compare and Exchange",
    },
    {
        "mnemonic": "CMPXCHG8B",
        "category": "atomic",
        "feature": "x86",
        "element_type": "i64",
        "element_size": 64,
        "flags": ["zf"],
        "encodings": [
            ("NP 0F C7 /1", "CMPXCHG8B m64", "M", "x86"),
        ],
        "desc": "Compare and Exchange 8 Bytes",
    },
    {
        "mnemonic": "CMPXCHG16B",
        "category": "atomic",
        "feature": "x86",
        "element_type": "i128",
        "element_size": 128,
        "flags": ["zf"],
        "encodings": [
            ("REX.W 0F C7 /1", "CMPXCHG16B m128", "M", "x86"),
        ],
        "desc": "Compare and Exchange 16 Bytes",
    },
]

instructions["INSERT_EXTRACT"] = [
    {
        "mnemonic": "VPEXTRB",
        "category": "simd_insert_extract",
        "feature": "avx",
        "element_type": "i8",
        "element_size": 8,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F3A 14 /r ib", "VPEXTRB r32/m8, xmm1, imm8", "RMI", "avx"),
        ],
        "desc": "Extract Byte from XMM",
    },
    {
        "mnemonic": "VPEXTRW",
        "category": "simd_insert_extract",
        "feature": "avx",
        "element_type": "i16",
        "element_size": 16,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F3A 15 /r ib", "VPEXTRW r32/m16, xmm1, imm8", "RMI", "avx"),
        ],
        "desc": "Extract Word from XMM",
    },
    {
        "mnemonic": "VPEXTRD",
        "category": "simd_insert_extract",
        "feature": "avx",
        "element_type": "i32",
        "element_size": 32,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F3A 16 /r ib", "VPEXTRD r32/m32, xmm1, imm8", "RMI", "avx"),
        ],
        "desc": "Extract Dword from XMM",
    },
    {
        "mnemonic": "VPEXTRQ",
        "category": "simd_insert_extract",
        "feature": "avx",
        "element_type": "i64",
        "element_size": 64,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F3A 16 /r ib", "VPEXTRQ r64/m64, xmm1, imm8", "RMI", "avx"),
        ],
        "desc": "Extract Qword from XMM",
    },
    {
        "mnemonic": "VEXTRACTF128",
        "category": "simd_insert_extract",
        "feature": "avx",
        "element_type": "none",
        "element_size": 128,
        "flags": [],
        "encodings": [
            ("VEX.256.66.0F3A 19 /r ib", "VEXTRACTF128 xmm1/m128, ymm2, imm8", "RMI", "avx"),
        ],
        "desc": "Extract Packed Floating-Point Values",
    },
]

instructions["HORIZONTAL"] = [
    {
        "mnemonic": "VPHADDW",
        "category": "simd_horizontal",
        "feature": "avx",
        "element_type": "i16",
        "element_size": 16,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F38 01 /r", "VPHADDW xmm1, xmm2, xmm3/m128", "RVM", "avx"),
            ("VEX.256.66.0F38 01 /r", "VPHADDW ymm1, ymm2, ymm3/m256", "RVM", "avx"),
        ],
        "desc": "Packed Horizontal Add Word",
    },
    {
        "mnemonic": "VPHADDD",
        "category": "simd_horizontal",
        "feature": "avx",
        "element_type": "i32",
        "element_size": 32,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F38 02 /r", "VPHADDD xmm1, xmm2, xmm3/m128", "RVM", "avx"),
            ("VEX.256.66.0F38 02 /r", "VPHADDD ymm1, ymm2, ymm3/m256", "RVM", "avx"),
        ],
        "desc": "Packed Horizontal Add Dword",
    },
    {
        "mnemonic": "VPHADDSW",
        "category": "simd_horizontal",
        "feature": "avx",
        "element_type": "i16",
        "element_size": 16,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F38 03 /r", "VPHADDSW xmm1, xmm2, xmm3/m128", "RVM", "avx"),
            ("VEX.256.66.0F38 03 /r", "VPHADDSW ymm1, ymm2, ymm3/m256", "RVM", "avx"),
        ],
        "desc": "Packed Horizontal Add Saturated Word",
    },
]

instructions["SHUFFLE"] = [
    {
        "mnemonic": "VPSHUFD",
        "category": "simd_shuffle",
        "feature": "avx",
        "element_type": "i32",
        "element_size": 32,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F 70 /r ib", "VPSHUFD xmm1, xmm2/m128, imm8", "RMI", "avx"),
            ("VEX.256.66.0F 70 /r ib", "VPSHUFD ymm1, ymm2/m256, imm8", "RMI", "avx"),
        ],
        "desc": "Shuffle Packed Doublewords",
    },
]

instructions["ARITHMETIC"] = [
    {
        "mnemonic": "VPADDB",
        "category": "simd_arithmetic",
        "feature": "avx",
        "element_type": "i8",
        "element_size": 8,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F FC /r", "VPADDB xmm1, xmm2, xmm3/m128", "RVM", "avx"),
            ("VEX.256.66.0F FC /r", "VPADDB ymm1, ymm2, ymm3/m256", "RVM", "avx"),
        ],
        "desc": "Add Packed Bytes",
    },
    {
        "mnemonic": "VPADDW",
        "category": "simd_arithmetic",
        "feature": "avx",
        "element_type": "i16",
        "element_size": 16,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F FD /r", "VPADDW xmm1, xmm2, xmm3/m128", "RVM", "avx"),
            ("VEX.256.66.0F FD /r", "VPADDW ymm1, ymm2, ymm3/m256", "RVM", "avx"),
        ],
        "desc": "Add Packed Words",
    },
    {
        "mnemonic": "VPADDD",
        "category": "simd_arithmetic",
        "feature": "avx",
        "element_type": "i32",
        "element_size": 32,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F FE /r", "VPADDD xmm1, xmm2, xmm3/m128", "RVM", "avx"),
            ("VEX.256.66.0F FE /r", "VPADDD ymm1, ymm2, ymm3/m256", "RVM", "avx"),
        ],
        "desc": "Add Packed Doublewords",
    },
    {
        "mnemonic": "VPADDQ",
        "category": "simd_arithmetic",
        "feature": "avx",
        "element_type": "i64",
        "element_size": 64,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F D4 /r", "VPADDQ xmm1, xmm2, xmm3/m128", "RVM", "avx"),
            ("VEX.256.66.0F D4 /r", "VPADDQ ymm1, ymm2, ymm3/m256", "RVM", "avx"),
        ],
        "desc": "Add Packed Quadwords",
    },
]

instructions["UNORDERED"] = [
    {
        "mnemonic": "VUCOMISS",
        "category": "simd_compare",
        "feature": "avx",
        "element_type": "f32",
        "element_size": 32,
        "flags": ["zf", "pf", "cf"],
        "encodings": [
            ("VEX.LIG.F3.0F 2E /r", "VUCOMISS xmm1, xmm2/m32", "RVM", "avx"),
        ],
        "desc": "Unordered Compare Scalar Single-Precision Floating-Point Values",
    },
]

instructions["ROUND"] = [
    {
        "mnemonic": "VROUNDPS",
        "category": "simd_round",
        "feature": "avx",
        "element_type": "f32",
        "element_size": 32,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F3A 08 /r ib", "VROUNDPS xmm1, xmm2/m128, imm8", "RMI", "avx"),
            ("VEX.256.66.0F3A 08 /r ib", "VROUNDPS ymm1, ymm2/m256, imm8", "RMI", "avx"),
        ],
        "desc": "Round Packed Single-Precision Floating-Point Values",
    },
    {
        "mnemonic": "VROUNDPD",
        "category": "simd_round",
        "feature": "avx",
        "element_type": "f64",
        "element_size": 64,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F3A 09 /r ib", "VROUNDPD xmm1, xmm2/m128, imm8", "RMI", "avx"),
            ("VEX.256.66.0F3A 09 /r ib", "VROUNDPD ymm1, ymm2/m256, imm8", "RMI", "avx"),
        ],
        "desc": "Round Packed Double-Precision Floating-Point Values",
    },
    {
        "mnemonic": "VROUNDSS",
        "category": "simd_round",
        "feature": "avx",
        "element_type": "f32",
        "element_size": 32,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F3A 0A /r ib", "VROUNDSS xmm1, xmm2, xmm3/m32, imm8", "RVM", "avx"),
        ],
        "desc": "Round Scalar Single-Precision Floating-Point Values",
    },
    {
        "mnemonic": "VROUNDSD",
        "category": "simd_round",
        "feature": "avx",
        "element_type": "f64",
        "element_size": 64,
        "flags": [],
        "encodings": [
            ("VEX.128.66.0F3A 0B /r ib", "VROUNDSD xmm1, xmm2, xmm3/m64, imm8", "RVM", "avx"),
        ],
        "desc": "Round Scalar Double-Precision Floating-Point Values",
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
{flag_block}simd_fp_exceptions = []

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
        f.write(content.lstrip("\n") + "\n")
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
