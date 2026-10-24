#!/usr/bin/env python3
"""Update all 4 root.zig files with new batch 13 instructions."""

import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
ISA = os.path.join(REPO_ROOT, "ISA")

all_instructions = [
    ("ACCUMULATE", "CRC32"),
    ("CACHE", "CLDEMOTE"),
    ("CACHE", "CLFLUSH"),
    ("CACHE", "CLFLUSHOPT"),
    ("CACHE", "CLWB"),
    ("REVERSE", "FDIVR"),
    ("REVERSE", "FDIVRP"),
    ("REVERSE", "FIDIVR"),
    ("REVERSE", "FSUBR"),
    ("REVERSE", "FSUBRP"),
    ("REVERSE", "FISUBR"),
    ("SCAN", "SCAS"),
    ("SCAN", "SCASB"),
    ("SCAN", "SCASW"),
    ("SCAN", "SCASD"),
    ("SCAN", "SCASQ"),
]


def make_var(group, mnemonic):
    return group.lower() + "_" + mnemonic.lower()


def make_path(group, mnemonic):
    return group + "/" + mnemonic.lower() + ".zig"


# Helper: build import lines
def build_import_lines():
    lines = []
    for group, mnemonic in all_instructions:
        var = make_var(group, mnemonic)
        path = make_path(group, mnemonic)
        lines.append("const {} = @import(\"{}\");".format(var, path))
    return "\n".join(lines)


def build_entry_lines(pattern):
    lines = []
    for group, mnemonic in all_instructions:
        var = make_var(group, mnemonic)
        lines.append(pattern.format(v=var))
    return "\n".join(lines)


# ====== 1. x86 root.zig ======
x86_root = ISA + "/x86/Zig/root.zig"
with open(x86_root) as f:
    content = f.read()

# Find and replace after wait_mwait import
content = content.replace(
    "const wait_mwait = @import(\"WAIT/mwait.zig\");",
    "const wait_mwait = @import(\"WAIT/mwait.zig\");\n" + build_import_lines()
)

# Find and replace after wait_mwait entry
content = content.replace(
    "    entry(wait_mwait.family, wait_mwait.path, wait_mwait.source),",
    "    entry(wait_mwait.family, wait_mwait.path, wait_mwait.source),\n" + build_entry_lines("    entry({v}.family, {v}.path, {v}.source),")
)

with open(x86_root, "w") as f:
    f.write(content)
print("Updated " + x86_root)


# ====== 2. NEON root.zig ======
neon_root = ISA + "/NEON/Zig/root.zig"
with open(neon_root) as f:
    content = f.read()

content = content.replace(
    "const wait_mwait = @import(\"WAIT/mwait.zig\");",
    "const wait_mwait = @import(\"WAIT/mwait.zig\");\n" + build_import_lines()
)

content = content.replace(
    "    mirror(wait_mwait.family, wait_mwait.path, wait_mwait.source),",
    "    mirror(wait_mwait.family, wait_mwait.path, wait_mwait.source),\n" + build_entry_lines("    mirror({v}.family, {v}.path, {v}.source),")
)

with open(neon_root, "w") as f:
    f.write(content)
print("Updated " + neon_root)


# ====== 3. Math x86 root.zig ======
math_x86_root = ISA + "/Math/x86/Zig/root.zig"
with open(math_x86_root) as f:
    content = f.read()

content = content.replace(
    "const wait_mwait = @import(\"WAIT/mwait.zig\");",
    "const wait_mwait = @import(\"WAIT/mwait.zig\");\n" + build_import_lines()
)

content = content.replace(
    "    spec(wait_mwait.meta),",
    "    spec(wait_mwait.meta),\n" + build_entry_lines("    spec({v}.meta),")
)

content = content.replace(
    "    wait_mwait.proof_report,",
    "    wait_mwait.proof_report,\n" + build_entry_lines("    {v}.proof_report,")
)

with open(math_x86_root, "w") as f:
    f.write(content)
print("Updated " + math_x86_root)


# ====== 4. Math NEON root.zig ======
math_neon_root = ISA + "/Math/NEON/Zig/root.zig"
with open(math_neon_root) as f:
    content = f.read()

content = content.replace(
    "const wait_mwait = @import(\"WAIT/mwait.zig\");",
    "const wait_mwait = @import(\"WAIT/mwait.zig\");\n" + build_import_lines()
)

content = content.replace(
    "    spec(wait_mwait.meta),",
    "    spec(wait_mwait.meta),\n" + build_entry_lines("    spec({v}.meta),")
)

content = content.replace(
    "    wait_mwait.proof_report,",
    "    wait_mwait.proof_report,\n" + build_entry_lines("    {v}.proof_report,")
)

with open(math_neon_root, "w") as f:
    f.write(content)
print("Updated " + math_neon_root)

print("\nAll 4 root.zig files updated successfully")
