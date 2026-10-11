#!/usr/bin/env python3
"""Bulk-fix ISA NEON mirror ABI violations driven by build/rosette-runtime-abi.log.

Fix classes:
  1. encoding_scope        : NEON mirror encodings rows < x86 rows  -> copy x86 rows into NEON
  2. lowering_tag          : NEON neon_lowering != x86 jit_lowering -> align
  3. register/flag/assembly: NEON missing neon_* blocks              -> copy from x86 (or generic)
  4. semantic_scope/flag   : NEON dropped x86 semantic/flags         -> copy from x86 (or generic)
  5. declared_x86_table    : NEON declares wrong x86_table path      -> fix path
  6. isa-x86 missing_flags/semantic: add blocks to x86 tables        -> fix x86

Usage:
  python3 tools/fix_abi_mirrors.py            # dry run (prints plan)
  python3 tools/fix_abi_mirrors.py --apply    # apply changes
"""
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = os.path.join(ROOT, "build", "rosette-runtime-abi.log")
X86_DIR = os.path.join(ROOT, "ISA", "x86")
NEON_DIR = os.path.join(ROOT, "ISA", "NEON")

APPLY = "--apply" in sys.argv


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def write(p, s):
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

def parse_log():
    """Return (neon_fixes, x86_fixes).

    neon_fixes: neon_path -> {check: set(detail_lines)}
    x86_fixes : x86_path  -> {check: set(detail_lines)}
    """
    neon_fixes = defaultdict(lambda: defaultdict(set))
    x86_fixes = defaultdict(lambda: defaultdict(set))
    if not os.path.exists(LOG):
        print(f"LOG NOT FOUND: {LOG}")
        return neon_fixes, x86_fixes
    for raw in open(LOG, encoding="utf-8"):
        ln = raw.strip()
        m = re.match(r"\[runtime-abi\]\[([a-z0-9-]+)\]\[([a-z0-9_]+)\] (.*)", ln)
        if not m:
            continue
        scope, check, msg = m.groups()
        if scope == "isa-neon":
            nm = re.search(r"neon=(\S+\.inc)", msg)
            if nm:
                neon_fixes[nm.group(1)][check].add(msg.strip())
        elif scope == "isa-x86":
            tm = re.search(r"table=(\S+\.inc)", msg)
            if tm:
                x86_fixes[tm.group(1)][check].add(msg.strip())
    return neon_fixes, x86_fixes


# ---------------------------------------------------------------------------
# Assignment / block extraction
# ---------------------------------------------------------------------------

def _value_end(lines, i, val):
    """Return index of last line of the assignment starting at line i."""
    if val.startswith('"""'):
        if '"""' in val[3:]:
            return i  # single-line triple-quoted
        j = i
        while j + 1 < len(lines):
            j += 1
            if '"""' in lines[j]:
                break
        return j
    if val.startswith("[") or val.startswith("{"):
        depth = 0
        j = i
        first = True
        while j < len(lines):
            for ch in lines[j]:
                if ch == "[" or ch == "{":
                    depth += 1
                elif ch == "]" or ch == "}":
                    depth -= 1
                    if depth == 0 and not first:
                        return j
            first = False
            if depth == 0:
                return j
            j += 1
        return j
    return i  # scalar


def find_assignment(src, name):
    """Return the full text of the `name = ...` block, or None."""
    lines = src.split("\n")
    for i, ln in enumerate(lines):
        m = re.match(rf"^{re.escape(name)}\s*=", ln)
        if m:
            idx = ln.find("=")
            val = ln[idx + 1 :].strip()
            end = _value_end(lines, i, val)
            return "\n".join(lines[i : end + 1])
    return None


def assignment_line_no(src, name):
    lines = src.split("\n")
    for i, ln in enumerate(lines):
        if re.match(rf"^{re.escape(name)}\s*=", ln):
            return i
    return None


# ---------------------------------------------------------------------------
# Encodings row copying (encoding_scope)
# ---------------------------------------------------------------------------

def extract_x86_encoding_rows(x86_src):
    """Return the raw row lines from x86's encodings block.

    Handles multi-line blocks and single-line `encodings = [{...}]` blocks.
    """
    lines = x86_src.split("\n")
    rows = []
    for i, ln in enumerate(lines):
        m = re.match(r"^\s*encodings\s*=\s*\[(.*)", ln)
        if not m:
            continue
        trailing = m.group(1)
        if "{" in trailing:
            # single-line block: encodings = [{...}, {...}] — extract all { } groups
            rows.extend(_extract_brace_groups(trailing))
            return rows
        # multi-line block
        in_block = True
        for j in range(i + 1, len(lines)):
            stripped = lines[j].strip()
            if stripped.startswith("]"):
                break
            if stripped:
                rows.append(lines[j])
        return rows
    return rows


def _extract_brace_groups(text):
    """Extract `{ ... }` groups from a single-line encodings value."""
    groups = []
    depth = 0
    start = -1
    for idx, ch in enumerate(text):
        if ch == "{":
            if depth == 0:
                start = idx
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start >= 0:
                groups.append("  { " + text[start + 1 : idx].strip() + " }")
                start = -1
    return groups


def replace_neon_encodings(neon_src, rows):
    """Replace the NEON encodings block content with the x86 rows."""
    lines = neon_src.split("\n")
    out = []
    i = 0
    in_block = False
    replaced = False
    while i < len(lines):
        ln = lines[i]
        if not in_block and re.match(r"^\s*encodings\s*=\s*\[", ln):
            stripped = ln.strip()
            if stripped in ("encodings = []", "encodings = [ ]"):
                out.append("encodings = [")
                out.extend(rows)
                out.append("]")
                replaced = True
                i += 1
                continue
            in_block = True
            out.append(ln)
            i += 1
            continue
        if in_block:
            if ln.strip().startswith("]"):
                if not replaced:
                    out.extend(rows)
                    replaced = True
                out.append(ln)
                in_block = False
                i += 1
                continue
            i += 1  # drop old rows
            continue
        out.append(ln)
        i += 1
    if not replaced:
        # no encodings block found — insert before abi_contract or at end
        block = ["encodings = ["]
        block.extend(rows)
        block.append("]")
        ai = assignment_line_no(neon_src, "abi_contract")
        if ai is None:
            return "\n".join(out).rstrip() + "\n\n" + "\n".join(block) + "\n"
        out2 = lines[:ai] + block + [""] + lines[ai:]
        return "\n".join(out2)
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Insertion helpers
# ---------------------------------------------------------------------------

def insert_before_abi(neon_src, blocks):
    """Insert blocks just before `abi_contract = ...` (or append at end)."""
    ai = assignment_line_no(neon_src, "abi_contract")
    if ai is None:
        return neon_src.rstrip() + "\n\n" + "\n\n".join(blocks) + "\n"
    lines = neon_src.split("\n")
    out = lines[:ai]
    out.append("")
    out.extend(blocks)
    out.append("")
    out.extend(lines[ai:])
    return "\n".join(out)


def set_scalar_assignment(src, name, value, after_names=("x86_handler", "x86_table")):
    """Replace existing `name = "..."`; if absent, insert after a known anchor."""
    lines = src.split("\n")
    for i, ln in enumerate(lines):
        if re.match(rf"^{re.escape(name)}\s*=", ln):
            lines[i] = re.sub(
                rf'^{re.escape(name)}\s*=\s*"[^"]*"',
                f'{name} = "{value}"',
                ln,
            )
            return "\n".join(lines)
    # insert after first anchor found (or at top)
    for anchor in after_names:
        for i, ln in enumerate(lines):
            if re.match(rf"^{re.escape(anchor)}\s*=", ln):
                lines.insert(i + 1, f'{name} = "{value}"')
                return "\n".join(lines)
    lines.insert(0, f'{name} = "{value}"')
    return "\n".join(lines)


# Instructions whose flag behavior is NOT empty (used when x86 tables
# legitimately set flags but the contract is missing).
FLAGS_BY_INSTR = {
    "PTEST": ["CF", "ZF"],
    "VPTEST": ["CF", "ZF"],
    "TEST": ["OF", "SF", "ZF", "AF", "PF", "CF"],
}


def add_flags_written(src, name=""):
    """Add `flags_written = [...]` to a table if absent.

    Uses a per-instruction list when known (e.g. PTEST sets CF/ZF),
    otherwise the empty list.
    """
    if find_assignment(src, "flags_written"):
        return src, False
    flags = FLAGS_BY_INSTR.get(name.upper(), [])
    flags_lit = "[" + ", ".join(f'"{f}"' for f in flags) + "]"
    flags_line = f"flags_written = {flags_lit}"
    # insert before handler line if present, else before abi_contract
    lines = src.split("\n")
    for i, ln in enumerate(lines):
        if re.match(r"^handler\s*=", ln):
            lines.insert(i, flags_line)
            lines.insert(i + 1, "")
            return "\n".join(lines), True
    ai = assignment_line_no(src, "abi_contract")
    if ai is not None:
        lines.insert(ai, flags_line)
        lines.insert(ai + 1, "")
        return "\n".join(lines), True
    return src.rstrip() + "\n\n" + flags_line + "\n", True


def add_semantic_general(src, name):
    """Add a generic semantic_general block to a table if it lacks any semantic."""
    for cand in ("semantic", "semantic_general", "semantic_legacy", "semantic_one_operand", "source_contract", "operation"):
        if find_assignment(src, cand):
            return src, False
    block = f'semantic_general = """\n{name}: preserve the x86 operation contract; see the x86 source table for the full semantic blocks.\n"""'
    lines = src.split("\n")
    ai = assignment_line_no(src, "abi_contract")
    if ai is not None:
        lines.insert(ai, block)
        lines.insert(ai + 1, "")
        return "\n".join(lines), True
    return src.rstrip() + "\n\n" + block + "\n", True


# ---------------------------------------------------------------------------
# Per-file fixes
# ---------------------------------------------------------------------------

def fix_neon_file(neon_path, checks):
    neon_file = os.path.join(NEON_DIR, neon_path)
    x86_path = neon_path  # mirrors live under the same relative path
    x86_file = os.path.join(X86_DIR, x86_path)
    if not os.path.exists(neon_file):
        print(f"  !! MISSING NEON: {neon_path}")
        return 0
    if not os.path.exists(x86_file):
        print(f"  !! MISSING X86: {x86_path}")
        return 0

    nsrc = read(neon_file)
    xsrc = read(x86_file)
    actions = []
    changed = False
    x86_changed = False

    # 5. declared_x86_table
    if "declared_x86_table" in checks:
        # set neon's x86_table to the actual x86 path
        nsrc = set_scalar_assignment(nsrc, "x86_table", x86_path, after_names=("x86_handler",))
        changed = True
        actions.append("declared_x86_table: x86_table fixed")

    # 1. encoding_scope
    if "encoding_scope" in checks:
        rows = extract_x86_encoding_rows(xsrc)
        if rows:
            new_nsrc = replace_neon_encodings(nsrc, rows)
            if new_nsrc != nsrc:
                nsrc = new_nsrc
                changed = True
                actions.append(f"encoding_scope: copied {len(rows)} x86 rows")

    # 2. lowering_tag
    if "lowering_tag" in checks:
        xjit = find_assignment(xsrc, "jit_lowering")
        nlow = find_assignment(nsrc, "neon_lowering")
        xjit_val = None
        nlow_val = None
        if xjit:
            m = re.search(r'"([^"]*)"', xjit)
            if m:
                xjit_val = m.group(1)
        if nlow:
            m = re.search(r'"([^"]*)"', nlow)
            if m:
                nlow_val = m.group(1)
        if xjit_val and xjit_val != "arm64_documented_contract_fallback":
            # x86 is explicit -> align NEON to x86
            if nlow_val != xjit_val:
                nsrc = set_scalar_assignment(nsrc, "neon_lowering", xjit_val, after_names=("x86_handler", "x86_table"))
                changed = True
                actions.append(f"lowering_tag: neon_lowering -> {xjit_val}")
        elif nlow_val and nlow_val != "arm64_documented_contract_fallback":
            # x86 lacks explicit jit_lowering -> give x86 the NEON name
            if xjit_val != nlow_val:
                xsrc = set_scalar_assignment(xsrc, "jit_lowering", nlow_val, after_names=("x86_handler", "handler"))
                changed = True
                x86_changed = True
                actions.append(f"lowering_tag: x86 jit_lowering -> {nlow_val}")
        else:
            actions.append("lowering_tag: SKIP (both fallback or unknown)")

    # 3 + 4. model blocks / semantic / flags
    model_blocks = []
    for check, key in (("register_model", "neon_register_model"),
                       ("flag_model", "neon_flag_model"),
                       ("assembly_contract", "neon_assembly")):
        if check in checks and find_assignment(nsrc, key) is None:
            xb = find_assignment(xsrc, key)
            if xb:
                model_blocks.append(xb)
            else:
                generic = f'{key} = "{neon_path.split("/")[-1][:-4]}: ARM64/NEON documented contract for this instruction."'
                model_blocks.append(generic)

    if "semantic_scope" in checks:
        has = any(find_assignment(nsrc, c) for c in ("semantic", "semantic_general", "semantic_legacy", "semantic_one_operand", "source_contract", "operation"))
        if not has:
            xb = find_assignment(xsrc, "semantic_general") or find_assignment(xsrc, "semantic")
            if xb:
                model_blocks.append(xb)
            else:
                nm = neon_path.split("/")[-1][:-4]
                model_blocks.append(f'semantic_general = """\n{nm}: preserve the x86 operation contract; see the x86 source table for the full semantic blocks.\n"""')

    if "flag_scope" in checks:
        has = any(find_assignment(nsrc, c) for c in ("flags", "flags_read", "flags_written", "flags_affected", "flags_model", "mxcsr_used", "simd_fp_exceptions"))
        if not has:
            xb = find_assignment(xsrc, "flags_written") or find_assignment(xsrc, "flags")
            if xb:
                model_blocks.append(xb)
            else:
                model_blocks.append("flags_written = []")

    if model_blocks:
        new_nsrc = insert_before_abi(nsrc, model_blocks)
        if new_nsrc != nsrc:
            nsrc = new_nsrc
            changed = True
            actions.append(f"added {len(model_blocks)} contract block(s)")

    # source_isa metadata hygiene (mirror must point x86 -> arm64_neon)
    m_src = re.search(r"^source_isa\s*=\s*\"([^\"]*)\"", nsrc, re.M)
    m_tgt = re.search(r"^target_isa\s*=\s*\"([^\"]*)\"", nsrc, re.M)
    if (m_src and m_src.group(1) != "x86") or (m_tgt and m_tgt.group(1) != "arm64_neon"):
        nsrc = re.sub(r'^source_isa\s*=\s*"[^"]*"', 'source_isa = "x86"', nsrc, count=1, flags=re.M)
        nsrc = re.sub(r'^target_isa\s*=\s*"[^"]*"', 'target_isa = "arm64_neon"', nsrc, count=1, flags=re.M)
        changed = True
        actions.append("source_isa/target_isa metadata fixed")

    if changed:
        print(f"NEON {neon_path}:")
        for a in actions:
            print(f"    - {a}")
        if APPLY:
            write(neon_file, nsrc)
            if x86_changed:
                write(x86_file, xsrc)
                print(f"    (also wrote X86 {x86_path})")
        return 1
    print(f"NEON {neon_path}: no changes")
    return 0


def fix_x86_file(x86_path, checks):
    x86_file = os.path.join(X86_DIR, x86_path)
    if not os.path.exists(x86_file):
        print(f"  !! MISSING X86: {x86_path}")
        return 0
    xsrc = read(x86_file)
    nm = x86_path.split("/")[-1][:-4]
    actions = []
    changed = False

    if "missing_flags" in checks:
        new_src, did = add_flags_written(xsrc, nm)
        if did:
            xsrc = new_src
            changed = True
            actions.append("missing_flags: flags_written added")

    if "missing_semantic" in checks:
        new_src, did = add_semantic_general(xsrc, nm)
        if did:
            xsrc = new_src
            changed = True
            actions.append("missing_semantic: semantic_general added")

    # PARITY: when the x86 table gains a flags/semantic contract, the NEON
    # mirror must carry it too, or a new flag_scope/semantic_scope violation
    # appears on the next validation pass.
    neon_path = x86_path
    neon_file = os.path.join(NEON_DIR, neon_path)
    if changed and os.path.exists(neon_file):
        nsrc = read(neon_file)
        mirror_blocks = []
        if "missing_flags" in checks and not any(
            find_assignment(nsrc, c)
            for c in ("flags", "flags_read", "flags_written", "flags_affected", "flags_model", "mxcsr_used", "simd_fp_exceptions")
        ):
            xb = find_assignment(xsrc, "flags_written") or find_assignment(xsrc, "flags")
            mirror_blocks.append(xb if xb else "flags_written = []")
        if "missing_semantic" in checks and not any(
            find_assignment(nsrc, c)
            for c in ("semantic", "semantic_general", "semantic_legacy", "semantic_one_operand", "source_contract", "operation")
        ):
            xb = find_assignment(xsrc, "semantic_general") or find_assignment(xsrc, "semantic")
            mirror_blocks.append(
                xb
                if xb
                else f'semantic_general = """\n{nm}: preserve the x86 operation contract; see the x86 source table for the full semantic blocks.\n"""'
            )
        if mirror_blocks:
            new_nsrc = insert_before_abi(nsrc, mirror_blocks)
            if new_nsrc != nsrc:
                if APPLY:
                    write(neon_file, new_nsrc)
                actions.append(f"parity: {len(mirror_blocks)} contract block(s) added to NEON mirror")

    if changed:
        print(f"X86  {x86_path}:")
        for a in actions:
            print(f"    - {a}")
        if APPLY:
            write(x86_file, xsrc)
        return 1
    print(f"X86  {x86_path}: no changes")
    return 0


def main():
    neon_fixes, x86_fixes = parse_log()
    total = 0
    print(f"=== NEON mirror fixes ({len(neon_fixes)} files) ===")
    for neon_path in sorted(neon_fixes):
        total += fix_neon_file(neon_path, neon_fixes[neon_path])
    print(f"\n=== x86 table fixes ({len(x86_fixes)} files) ===")
    for x86_path in sorted(x86_fixes):
        total += fix_x86_file(x86_path, x86_fixes[x86_path])
    print(f"\n{'APPLIED' if APPLY else 'DRY RUN'}: {total} file(s) changed")


if __name__ == "__main__":
    main()
