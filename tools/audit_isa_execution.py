#!/usr/bin/env python3
"""Refuse a decode that nothing can execute.

The failure this exists for
---------------------------
2026-09-08. A correct decoder fix gave `0x81 /5` its own `sub_reg*_imm32`
opcodes instead of mislabelling them as the imm8 family. Nothing added the
matching arm to the Mach-O executor, so `sub rsp, imm32` -- the second
instruction of a standard C++ prologue -- became `unimplemented_instruction`,
and the first of 724 pre-main initializers terminated two steps in.

Nothing caught it. The decoder compiled, the executor compiled, every test
passed, and the defect was only visible by running a guest. A decoder that can
name an instruction the interpreter cannot run is a build-time fact, so it is
checked at build time.

What it does not claim
----------------------
This is a *textual* audit, the same kind as `audit_pkg_boundary.py`: it reads
which opcodes the decoding tables mention and which ones the execution path
mentions. It cannot prove an implementation is correct, only that one exists.
A dispatch that computes an opcode arithmetically rather than naming it is
invisible here, which is why the declared-gap list is the authority on what is
knowingly missing rather than an inferred set.
"""

import argparse
import pathlib
import re
import sys

OP_ENUM_RE = re.compile(r"pub const Op = enum\(u16\) \{(.*?)\n\};", re.S)
MEMBER_RE = re.compile(r"^([a-z_][A-Za-z0-9_]*),")
REFERENCE_RE = re.compile(r"\.([a-z_][A-Za-z0-9_]*)\b")

DECODER_DIR = "ISA/decoding"
OP_DEFINITION = "ISA/decoding/types.zig"

# Every file that can satisfy an opcode on the Mach-O execution path.
EXECUTION_SOURCES = (
    "lib/runtime/process-core/execute.zig",
    "lib/runtime/process-core/evex.zig",
    "lib/runtime/process-core/memory_access.zig",
    "lib/runtime/process-core/scheduling.zig",
    "lib/Mach-O/process.zig",
    "lib/Mach-O/execution_helpers.zig",
    "lib/Mach-O/packed_ops.zig",
)

# Opcodes the decoder names and the Mach-O interpreter knowingly cannot run.
#
# Every entry is owed an implementation. They are listed so that the gap is a
# declared quantity rather than something a run discovers one guest
# instruction at a time, and so that adding a *new* unexecutable decode fails
# here instead of in an initializer.
#
# All of these are AVX/AVX2/FMA/AVX-512 vector forms and all predate the
# 2026-09-08 audit; none of them is reachable from integer or scalar guest
# code. Implementing one means deleting its line.
DECLARED_GAPS = {
    # AVX-512 lane alignment.
    "valignd", "valignq",
    # FMA3, all three operand orders x {ps,pd} x {add,sub,addsub,subadd}.
    "vfmadd132pd", "vfmadd132ps", "vfmadd213pd", "vfmadd213ps",
    "vfmadd231pd", "vfmadd231ps",
    "vfmaddsub132pd", "vfmaddsub132ps", "vfmaddsub213pd", "vfmaddsub213ps",
    "vfmaddsub231pd", "vfmaddsub231ps",
    "vfmsub132pd", "vfmsub132ps", "vfmsub213pd", "vfmsub213ps",
    "vfmsub231pd", "vfmsub231ps",
    "vfmsubadd132pd", "vfmsubadd132ps", "vfmsubadd213pd", "vfmsubadd213ps",
    "vfmsubadd231pd", "vfmsubadd231ps",
    # Horizontal float arithmetic.
    "vhaddpd", "vhaddps", "vhsubpd", "vhsubps",
    # Horizontal integer arithmetic.
    "vphaddd", "vphaddsw", "vphaddw", "vphsubd", "vphsubsw", "vphsubw",
    # Insert / permute.
    "vinsertps", "vpermps",
    # Per-element variable shifts.
    "vpsllvd", "vpsllvw", "vpsravd", "vpsravw", "vpsrlvd", "vpsrlvw",
    # AVX-512 ternary logic.
    "vpternlogd", "vpternlogq",
    # Float unpack.
}


FAST_PATH_FILE = "lib/runtime/process-core/execute.zig"
FAST_PATH_FUNCTION = "pub fn execute("
FAST_PATH_MARKER = "    switch (d.op) {"
ARM_RE = re.compile(r"^        (\.[A-Za-z_0-9, .]*?)\s*=>\s*(.*)$")


def fast_path_leaks(root: pathlib.Path) -> list[tuple[int, str]]:
    """Arms of the fast-path switch that fall through to the general switch.

    `execute` dispatches twice: a fast switch of hot opcodes, then the general
    one. The fast switch's arms must all `return`, because the general switch
    is reached otherwise -- and it will either run the same instruction a
    second time or, having no arm for it, terminate the run reporting an
    opcode that has in fact already executed. Both outcomes compile, and the
    second is what killed the 2026-09-08 run inside
    `xe::CpuFeatures::DetectFeatures`: `cmp_reg64_imm32` performed its
    comparison and was then declared unimplemented.
    """
    lines = (root / FAST_PATH_FILE).read_text(encoding="utf-8").split("\n")
    # Anchor inside `execute` itself. Helper functions in this file switch on
    # `d.op` too, and their arms are under no such obligation: the contract
    # belongs to the two-switch dispatch, not to every switch in the file.
    try:
        entry = next(
            index
            for index, line in enumerate(lines)
            if line.startswith(FAST_PATH_FUNCTION)
        )
    except StopIteration:
        raise SystemExit(f"{FAST_PATH_FILE}: could not locate `{FAST_PATH_FUNCTION}`")
    try:
        start = next(
            index
            for index in range(entry, len(lines))
            if lines[index] == FAST_PATH_MARKER
        )
    except StopIteration:
        raise SystemExit(f"{FAST_PATH_FILE}: could not locate the fast-path switch")

    depth = 0
    end = len(lines)
    for index in range(start, len(lines)):
        depth += lines[index].count("{") - lines[index].count("}")
        if depth == 0 and index > start:
            end = index
            break

    leaks: list[tuple[int, str]] = []
    index = start + 1
    while index < end:
        match = ARM_RE.match(lines[index])
        if match is None:
            index += 1
            continue
        head, rest = match.group(1).strip(), match.group(2)
        body = [rest]
        depth = rest.count("{") - rest.count("}")
        cursor = index
        while depth > 0 and cursor + 1 < end:
            cursor += 1
            body.append(lines[cursor])
            depth += lines[cursor].count("{") - lines[cursor].count("}")
        joined = " ".join(part.strip() for part in body)
        if not re.search(r"\breturn\b", joined) and "unreachable" not in joined:
            leaks.append((index + 1, head))
        index = cursor + 1
    return leaks


def opcode_names(root: pathlib.Path) -> list[str]:
    source = (root / OP_DEFINITION).read_text(encoding="utf-8")
    match = OP_ENUM_RE.search(source)
    if match is None:
        raise SystemExit(f"{OP_DEFINITION}: could not locate `pub const Op`")
    names = []
    for line in match.group(1).split("\n"):
        member = MEMBER_RE.match(line.split("//")[0].strip())
        if member is not None:
            names.append(member.group(1))
    return names


def referenced(paths, universe: set[str]) -> set[str]:
    found: set[str] = set()
    for path in paths:
        if not path.exists():
            continue
        for name in REFERENCE_RE.findall(path.read_text(encoding="utf-8")):
            if name in universe:
                found.add(name)
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="repository root")
    args = parser.parse_args()
    root = pathlib.Path(args.root).resolve()

    universe = set(opcode_names(root)) - {"invalid"}
    decoder_files = [
        path
        for path in sorted((root / DECODER_DIR).rglob("*.zig"))
        if path.name != "types.zig"
    ]
    decodable = referenced(decoder_files, universe)
    executable = referenced([root / name for name in EXECUTION_SOURCES], universe)

    gaps = decodable - executable
    undeclared = sorted(gaps - DECLARED_GAPS)
    stale = sorted(DECLARED_GAPS - gaps)
    leaks = fast_path_leaks(root)

    print(
        "isa execution: "
        f"opcodes={len(universe)} decodable={len(decodable)} "
        f"executable={len(decodable & executable)} declared_gaps={len(DECLARED_GAPS)} "
        f"undeclared={len(undeclared)} stale={len(stale)} fast_path_leaks={len(leaks)}"
    )

    for lineno, head in leaks:
        print(
            f"ERROR: {FAST_PATH_FILE}:{lineno}: fast-path arm {head} does not return, "
            "so control reaches the general switch with the same opcode. Add `return;` "
            "-- the instruction otherwise executes twice, or terminates the run as "
            "unimplemented after it has already run.",
            file=sys.stderr,
        )

    if undeclared:
        for name in undeclared:
            print(
                f"ERROR: {name}: the decoder can produce this opcode and the Mach-O "
                "execution path cannot run it. Implement it, or add it to "
                "DECLARED_GAPS with the reason.",
                file=sys.stderr,
            )
    if stale:
        for name in stale:
            print(
                f"ERROR: {name}: declared as unexecutable but the execution path now "
                "names it. Remove it from DECLARED_GAPS so the list stays true.",
                file=sys.stderr,
            )
    if undeclared or stale or leaks:
        print(
            f"isa execution: FAIL ({len(undeclared)} undeclared, {len(stale)} stale, "
            f"{len(leaks)} fast-path leak(s))",
            file=sys.stderr,
        )
        return 1

    print(
        "isa execution: PASS (every decodable opcode is either executable or a "
        "declared gap, and every fast-path arm returns)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
