#!/usr/bin/env python3
"""Split the universal x86-64 decoder into ISA/decoding/ family files.

NOTE: one-shot migration tool.  The original src/x64-ASM/decoder.zig is no
longer in the tree, so this script cannot be re-run; it is kept as an exact
record of the family mapping (SEGMENTS/SYMBOLS/IMPORTS tables below) for
maintenance reference.

One-shot migration tool.  Reads src/x64-ASM/decoder.zig, extracts each
top-level declaration into one of the family files below (segments are
1-based inclusive line ranges taken from the current file), rewrites the
module imports, and generates ISA/decoding/root.zig as the re-export hub
so the public `x64_decoder` module surface is byte-for-byte unchanged.

Family files:
  types.zig      - core types, Op enum, register/flag re-exports, ISA ABI contract test
  prefix.zig     - legacy / VEX / EVEX prefix decoding
  addressing.zig - ModRM, SIB, segment selection, effective-address resolution
  cpu.zig        - bit scan, popcount, byte swap, CRC32C, emulated CPUID/XCR0
  legacy.zig     - legacy 1-byte opcodes: MOV family + main dispatch + accumulator immediates
  twobyte.zig    - 0F two-byte / three-byte opcodes + SSE byte decode
  vex.zig        - VEX / EVEX encoded families (VEX2/VEX3, half/duplicate moves)
  groups.zig     - ModRM-group opcode families (0x80-0xFF groups, movzx/movsx/...)
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src/x64-ASM/decoder.zig"
OUT = ROOT / "ISA/decoding"

# 1-based inclusive line ranges of every top-level declaration, keyed by family file.
SEGMENTS = {
    "types": [
        (7, 48),       # module re-exports (highway/isa_decode/capabilities), types, flags, bit-test re-exports
        (228, 254),    # RegisterOperand, MemoryOperand, RmOperand, DecodedModRm
        (410, 434),    # flag re-exports, regVal/setReg, BitScanKind, BitScanResult, PopulationCountResult
        (523, 1307),   # Op enum, canonicalMnemonic, ISA ABI contract test
        (1334, 1367),  # DecodedInsn
    ],
    "prefix": [
        (49, 227),     # LegacyPrefixes, VexPrefix, EvexPrefix, decode*Prefix
    ],
    "addressing": [
        (255, 409),    # registerId, decodeRegister, segments, memory operand, decodeModRm
        (2451, 2508),  # segment / effective-address tests
        (5051, 5159),  # hasModRM, mapReg, mapJccCond8/32, readModRM
    ],
    "cpu": [
        (435, 522),    # populationCount, bitScan, byteSwap, crc32cAccumulator
        (1308, 1333),  # CpuidResult, emulatedCpuid, emulatedXcr0 + tests
        (2327, 2330),  # CRC32C test
    ],
    "legacy": [
        (1368, 1453),  # registerOperandValue, setRegisterOperand, MOV-size/immediate helpers
        (2204, 2326),  # decodeLegacyMov
        (2331, 2339),  # decodeMovForTest
        (2340, 2450),  # MOV decoder tests (incl. legacy-prefix normalization test)

        (2509, 3125),  # decodeLegacyInstruction, x87BinaryOperation
        (4603, 4625),  # decodeAccumulatorImmediate
    ],
    "twobyte": [
        (4626, 5050),  # decodeTwoByte, decodeThreeByte, decodeSseBytes
    ],
    "vex": [
        (1454, 1602),  # decodeVexModRm, decodeEvexModRm
        (1603, 2203),  # decodeVexInstruction, decodeVexReturn*, decodeVexMap38/3A
        (3126, 4602),  # decodeVex2, decodeVex3, decodeVexHalfMove, decodeVexDuplicateMove
    ],
    "groups": [
        (5160, 6132),  # decodeArithRmReg ... decodeMovaps
    ],
}

# Every public symbol and the family file that defines it.
SYMBOLS = {
    "types": [
        "highway", "isa_decode", "capabilities",
        "OperandSize", "Condition", "Size", "Cond", "RegId", "Regs",
        "Segment", "SegmentState", "ExecutionMode", "MemoryReferenceKind",
        "RFL_CF", "RFL_PF", "RFL_AF", "RFL_ZF", "RFL_SF", "RFL_OF",
        "statusByteForLahf", "applySahf",
        "BitTestOperation", "bitTestRegister", "bitTestAndResetRegister",
        "bitTestMemoryOperand", "bitTestMemoryOperandImmediate",
        "RegisterOperand", "MemoryOperand", "RmOperand", "DecodedModRm",
        "applySub", "applySbb", "applyAdd", "applyIncDec", "applyLogic",
        "evalCond", "regVal", "setReg",
        "BitScanKind", "BitScanResult", "PopulationCountResult",
        "Op", "DecodedInsn",
    ],
    "prefix": [
        "LegacyPrefixes", "VexPrefix", "EvexPrefix",
        "decodeLegacyPrefixes", "decodeVexPrefix", "decodeEvexPrefix",
    ],
    "addressing": [
        "decodeRegister", "defaultSegment", "selectSegment", "segmentBase",
        "resolveMemoryAddress", "decodeMemoryOperand", "decodeModRm",
        "hasModRM", "mapReg", "mapJccCond8", "mapJccCond32", "readModRM",
    ],
    "cpu": [
        "populationCount", "bitScan", "byteSwap", "crc32cAccumulator",
        "CpuidResult", "emulatedCpuid", "emulatedXcr0",
    ],
    "legacy": [
        "registerOperandValue", "setRegisterOperand",
        "decodeLegacyMov", "decodeLegacyInstruction",
        "x87BinaryOperation", "decodeAccumulatorImmediate",
    ],
    "twobyte": [
        "decodeTwoByte", "decodeThreeByte", "decodeSseBytes",
    ],
    "vex": [
        "decodeVexInstruction", "decodeVex2", "decodeVex3",
        "decodeVexHalfMove", "decodeVexDuplicateMove",
    ],
    "groups": [
        "decodeArithRmReg", "decodeMovRmReg", "decodeLea", "decodePopRm",
        "decodeGroup1Imm", "decodeGroup2Shift", "decodeMovMemImm",
        "decodeGroup3", "decodeGroup4_5", "decodeTestRmReg",
        "decodeXchgRmReg", "decodeImulImm", "decodeImulTwoOp",
        "decodeCmpxchg", "decodeMovzx", "decodeMovsx", "decodeXadd",
        "decodeSetcc", "decodeMovupsMovss", "decodeMovaps",
    ],
}

# Import set per family file (acyclic dependency graph).
IMPORTS = {
    "prefix": ["types"],
    "addressing": ["types", "prefix"],
    "cpu": ["types"],
    "legacy": ["types", "addressing", "groups", "twobyte", "prefix", "vex"],
    "twobyte": ["types", "addressing", "groups"],
    "vex": ["types", "prefix", "addressing"],
    "groups": ["types", "addressing"],
}

# Files that additionally import the wired support modules (cpu_state, flags,
# bit_test, capabilities) directly by name.  Symbols with the same name are
# excluded from the generated alias block to avoid duplicate declarations.
DIRECT_MODULES = {
    "cpu": ["flags", "capabilities"],
}

DESCRIPTIONS = {
    "types": "core types, Op enum, register/flag re-exports, ISA ABI contract",
    "prefix": "legacy / VEX / EVEX prefix decoding",
    "addressing": "ModRM, SIB, segment selection, effective-address resolution",
    "cpu": "bit scan, popcount, byte swap, CRC32C, emulated CPUID/XCR0",
    "legacy": "legacy 1-byte opcodes: MOV family + main dispatch + accumulator immediates",
    "twobyte": "0F two-byte / three-byte opcodes + SSE byte decode",
    "vex": "VEX / EVEX encoded families (VEX2/VEX3, half/duplicate moves)",
    "groups": "ModRM-group opcode families (0x80-0xFF groups, movzx/movsx/...)",
}


def main() -> int:
    lines = SRC.read_text().split("\n")
    if lines and lines[-1] == "":
        lines.pop()  # trailing newline produces a spurious empty element
    if len(lines) < 6132:
        print(f"error: {SRC} has {len(lines)} lines, expected >= 6132", file=sys.stderr)
        return 1

    # Sanity check: segments must tile the range [7, len(lines)] contiguously.
    spans = sorted((s for segs in SEGMENTS.values() for s in segs))
    expected = 7
    for (a, b) in spans:
        if a != expected:
            print(f"error: segment {a}-{b} not contiguous (expected start {expected})", file=sys.stderr)
            return 1
        expected = b + 1
    if expected - 1 != len(lines):
        print(f"error: coverage ends at {expected - 1}, file has {len(lines)} lines", file=sys.stderr)
        return 1

    OUT.mkdir(parents=True, exist_ok=True)

    bodies = {}
    for family, segs in SEGMENTS.items():
        parts = []
        for (a, b) in segs:
            parts.append("\n".join(lines[a - 1:b]))
        bodies[family] = "\n\n".join(parts)

    # Fix the capabilities import in types.zig: it is now a wired module.
    bodies["types"] = bodies["types"].replace(
        '@import("capabilities.zig")',
        '@import("capabilities")',
    )

    # Module alias names.  `pref`/`vexmod` avoid shadowing the many local
    # `prefix`/`vex` variables inside the VEX and legacy decode bodies.
    MODULE_ALIAS = {"prefix": "pref", "vex": "vexmod"}

    def alias_block(family: str) -> str:
        """const X = <defining-file>.X; for every symbol this file may use."""
        entries = []
        direct = set(DIRECT_MODULES.get(family, []))
        for imp in IMPORTS[family]:
            alias = MODULE_ALIAS.get(imp, imp)
            for sym in SYMBOLS[imp]:
                if sym in direct:
                    continue  # imported directly by name below
                entries.append(f"const {sym} = {alias}.{sym};")
        return "\n".join(entries)

    headers = {
        "types": (
            "const std = @import(\"std\");\n"
            "const cpu_state = @import(\"cpu_state\");\n"
            "const flags = @import(\"flags\");\n"
            "const bit_test = @import(\"bit_test\");\n"
            "const isa_registry = @import(\"isa_registry\");\n"
            "const runtime_abi = @import(\"runtime_abi_handshake\");"
        ),
    }
    for family in IMPORTS:
        import_lines = ["const std = @import(\"std\");"]
        import_lines += [
            f"const {MODULE_ALIAS.get(imp, imp)} = @import(\"{imp}.zig\");"
            for imp in IMPORTS[family]
        ]
        import_lines += [
            f"const {dm} = @import(\"{dm}\");"
            for dm in DIRECT_MODULES.get(family, [])
        ]
        headers[family] = "\n".join(import_lines)

    for family, body in bodies.items():
        doc = (
            f"//! Family: {family} — {DESCRIPTIONS[family]}.\n"
            f"//! Extracted from the universal x86-64 decoder (formerly src/x64-ASM/decoder.zig).\n"
        )
        content = doc + "\n" + headers[family]
        if family in IMPORTS:
            content += "\n" + alias_block(family)
        content += "\n\n" + body + "\n"
        (OUT / f"{family}.zig").write_text(content)
        print(f"wrote ISA/decoding/{family}.zig ({len(body.splitlines())} body lines)")

    # root.zig: re-export every public symbol so the x64_decoder module
    # surface is unchanged for all consumers (ELF, Mach-O, process-core, ...).
    root = [
        "//! Universal x86-64 decoder — module entry point (formerly src/x64-ASM/decoder.zig).",
        "//!",
        "//! Split into instruction-family modules under ISA/decoding/. This hub",
        "//! re-exports the full public API so consumers keep using `x64_decoder.*`.",
        "//!",
        "//! Families:",
    ]
    for family in sorted(SEGMENTS):
        root.append(f"//!   - {family}: {DESCRIPTIONS[family]}")
    root.append("")
    for family in sorted(SEGMENTS):
        root.append(f"const {family} = @import(\"{family}.zig\");")
    root.append("")
    for family in sorted(SEGMENTS):
        for sym in SYMBOLS[family]:
            root.append(f"pub const {sym} = {family}.{sym};")
    root.append("")
    (OUT / "root.zig").write_text("\n".join(root))
    print("wrote ISA/decoding/root.zig")

    return 0


if __name__ == "__main__":
    sys.exit(main())
