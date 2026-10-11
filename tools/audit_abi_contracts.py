#!/usr/bin/env python3
"""Enumerate decoder Op values with no matching ISA ABI contract.

Mirrors the logic of `canonicalMnemonic` + the ABI contract test in
ISA/decoding/types.zig: for every Op, compute the canonical mnemonic
(stem before the first '_', with cmovcc/setcc/jcc/ud2 special cases),
then check the ISA x86 registry (name = / aliases =) for a match.

Usage: python3 tools/audit_abi_contracts.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TYPES = ROOT / "ISA/decoding/types.zig"
X86_INC = ROOT / "ISA/x86"

SPECIAL = {"cmovcc": "cmove", "setcc": "sete", "jcc": "je", "ud2": "UD2"}


def op_members() -> list[str]:
    text = TYPES.read_text()
    start = text.index("pub const Op = enum")
    body = text[start:].split("};", 1)[0]
    members = []
    for line in body.splitlines():
        m = re.match(r"\s*([a-z][a-z0-9_]*)", line)
        if not m:
            continue
        name = m.group(1)
        if name in ("pub", "const", "enum"):
            continue
        members.append(name)
    return members


def canonical(tag: str) -> str:
    if tag == "invalid":
        return None
    # These are executor-internal synthetic operations.  They dispatch the
    # D8/DA/DC/DE x87 families after decoding has already identified the
    # memory/register shape; there is no single ISA mnemonic whose contract
    # they could match.  Keep this in sync with ISA/decoding/types.zig's
    # canonicalMnemonic helper so the offline audit does not report a false
    # gap for a deliberately non-mnemonic Op value.
    if tag in {"x87_binary", "x87_memory"}:
        return None
    stem = tag.split("_", 1)[0] if "_" in tag else tag
    canonical = SPECIAL.get(stem, stem)
    return canonical.upper()


def registry_names() -> set[str]:
    names = set()
    for path in X86_INC.rglob("*.inc"):
        text = path.read_text(errors="replace")
        for m in re.finditer(r"^(?:name|instruction)\s*=\s*\"([^\"]+)\"", text, re.M):
            names.add(m.group(1).upper())
        for m in re.finditer(r"^aliases\s*=\s*\[([^\]]*)\]", text, re.M):
            for item in m.group(1).split(","):
                item = item.strip().strip('"').strip()
                if item:
                    names.add(item.upper())
    return names


def main() -> int:
    ops = op_members()
    names = registry_names()
    print(f"Op enum values: {len(ops)}  |  registry names/aliases: {len(names)}")
    missing = []
    for op in ops:
        mn = canonical(op)
        if mn is None:
            continue
        # The registry documents VEX-encoded forms under their non-V names
        # (e.g. ADDPS covers VEX.128/256/512 VADDPS); normalize for matching.
        candidates = {mn, mn[1:] if mn.startswith("V") else mn}
        if candidates.isdisjoint(names):
            missing.append((op, mn))
    print(f"Ops with a canonical mnemonic but NO registry match (after V-normalization): {len(missing)}")
    for op, mn in missing:
        print(f"  {op:40s} -> {mn}")
    return 0 if not missing else 1


if __name__ == "__main__":
    sys.exit(main())
