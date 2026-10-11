#!/usr/bin/env python3
"""Write each `pkg/dll/win32/<dll>` package's declared export table.

The table is generated because its *content* is a mechanical join of three
things a person already established elsewhere:

  * which names the guest imports  - read from the PE's import directory
  * what each name's ABI is        - `tools/dll/export_abi.py`, hand-written
  * whether Rosette handles it     - read from the dispatcher's own source

Generating the join keeps those three from drifting silently, which is the
failure this replaces: a package listed names, the dispatcher handled a
different set, and nothing compared them.

The output goes between markers so the hand-written parts of each package -
its doc comment, its identity, its own tests - survive a regeneration.
`tools/audit_dll_coverage.py` checks the result rather than trusting it.
"""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_abi  # noqa: E402
from dispatcher import handled_names, policy_refused_names  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
IMAGE = ROOT / ".rosette" / "xenia-windows-clean" / "bundle" / "xenia_canary.exe"
DISPATCHER = ROOT / "src" / "x64-ASM" / "windows_runtime.zig"
PACKAGES = ROOT / "pkg" / "dll" / "win32"

BEGIN = "// --- generated export table: tools/dll/generate_export_tables.py ---"
END = "// --- end generated export table ---"


def read_imports(path: Path) -> dict[str, list[str]]:
    """The PE import directory, as {dll: [name, ...]}."""
    data = path.read_bytes()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe : pe + 4] != b"PE\0\0":
        raise SystemExit(f"{path} is not a PE image")
    section_count = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    optional = pe + 24
    if struct.unpack_from("<H", data, optional)[0] != 0x20B:
        raise SystemExit("only PE32+ is supported")
    directories = optional + 112
    import_rva = struct.unpack_from("<I", data, directories + 8)[0]

    sections = []
    table = pe + 24 + optional_size
    for index in range(section_count):
        offset = table + index * 40
        virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from(
            "<IIII", data, offset + 8
        )
        sections.append((virtual_address, max(virtual_size, raw_size), raw_offset))

    def to_offset(rva: int) -> int | None:
        for virtual_address, span, raw_offset in sections:
            if virtual_address <= rva < virtual_address + span:
                return raw_offset + (rva - virtual_address)
        return None

    def cstring(offset: int) -> str:
        end = data.index(b"\0", offset)
        return data[offset:end].decode("latin1")

    imports: dict[str, list[str]] = {}
    cursor = to_offset(import_rva)
    while True:
        lookup, _, _, name_rva, thunk = struct.unpack_from("<IIIII", data, cursor)
        if lookup == 0 and name_rva == 0 and thunk == 0:
            break
        names: list[str] = []
        entry = to_offset(lookup or thunk)
        while True:
            value = struct.unpack_from("<Q", data, entry)[0]
            if value == 0:
                break
            if value & (1 << 63):
                names.append("#%d" % (value & 0xFFFF))
            else:
                names.append(cstring(to_offset(value & 0x7FFFFFFF) + 2))
            entry += 8
        imports[cstring(to_offset(name_rva))] = names
        cursor += 20
    return imports




def package_directory(dll: str) -> Path | None:
    stem = dll[:-4] if dll.lower().endswith(".dll") else dll
    for candidate in (stem.lower(), stem):
        directory = PACKAGES / candidate
        if (directory / "src" / "root.zig").exists():
            return directory
    return None


def zig_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


# Non-greedy to the array's own closing brace. The earlier version anchored
# on a newline before `};`, which does not match the single-line empty form
# `[_][]const u8{};` - so on bcrypt and dwmapi it ran on to the next `};` in
# the file and swallowed the package's test body into the surface.
DEGRADED = re.compile(r"pub const degraded_imports = \[_\]\[\]const u8\{(.*?)\};", re.S)


def owned_names(source: Path) -> list[str]:
    """Names a package already claims, beyond whatever the image imports.

    A package owns every name Rosette answers for that library, and the import
    table is only the part the linker bound statically. hidapi and libusb
    resolve several setupapi entry points through `GetProcAddress` after
    loading the library themselves, and those are exactly as reachable as an
    IAT entry - so a surface built from the import table alone would leave
    them undeclared while the package went on listing them.
    """
    text = source.read_text(encoding="utf-8")
    match = DEGRADED.search(text)
    if match is None:
        return []
    return re.findall(r'"([^"]+)"', match.group(1))


def render(dll: str, names: list[str], handled: set[str], policy_refused: set[str]) -> str:
    seen: set[str] = set()
    rows: list[str] = []
    for name in names:
        if name in seen:
            continue
        seen.add(name)
        known = export_abi.OVERRIDES.get(name)
        if known is None:
            convention, zero, arity, note = "zero_count", True, None, ""
            reviewed = False
        else:
            convention, zero, arity, note = known
            reviewed = True
        if name in policy_refused:
            behaviour = "refused_by_policy"
        elif name in export_abi.SERVED:
            behaviour = "served"
        elif name in handled:
            behaviour = "modelled"
        else:
            behaviour = "not_implemented"
        fields = [f".name = {zig_string(name)}"]
        if arity is not None:
            fields.append(f".arity = {arity}")
        fields.append(f".convention = .{convention}")
        fields.append(f".behaviour = .{behaviour}")
        if zero:
            fields.append(".zero_is_an_answer = true")
        if reviewed:
            fields.append(".reviewed = true")
        if behaviour == "refused_by_policy" and not note:
            note = "Rosetta owns this ABI and returns the documented unavailable-capability value on macOS."
            reviewed = True
        if note:
            fields.append(f".note = {zig_string(note)}")
        rows.append("    .{ " + ", ".join(fields) + " },")
    body = "\n".join(rows)
    return f"""{BEGIN}
/// Every name this image imports from {dll}, with the ABI each return value
/// follows and what Rosette does when the guest calls it.
///
/// Regenerate with `python3 tools/dll/generate_export_tables.py`; check with
/// `python3 tools/audit_dll_coverage.py`, which fails when this table and the
/// dispatcher disagree about what is handled.
pub const exports = [_]export_contract.Export{{
{body}
}};

pub const surface = export_contract.Surface{{
    .dll_name = dll_name,
    .stem = stem,
    .exports = &exports,
}};

/// What this library's ABI says about one export, or null when the image does
/// not import it. Null is a real answer: it means the guest cannot reach this
/// name through the import table, whatever else it might do.
pub fn findExport(function_name: []const u8) ?export_contract.Export {{
    return surface.find(function_name);
}}

test "the declared surface is complete, unique, and agrees with itself" {{
    try std.testing.expect(exports.len != 0);
    try std.testing.expect(!export_contract.hasDuplicate(&exports));
    for (exports) |entry| {{
        try std.testing.expect(entry.name.len != 0);
        if (entry.arity) |arity| try std.testing.expect(arity <= export_contract.max_declared_arity);
        // A name declared here must also be findable, or `findExport` and the
        // table would disagree about the same library.
        try std.testing.expect(findExport(entry.name) != null);
    }}
    try std.testing.expectEqual(@as(?export_contract.Export, null), findExport("__not_in_this_dll__"));
    // Every degraded name is part of the surface: the two lists described the
    // same library and nothing compared them.
    for (degraded_imports) |name| {{
        try std.testing.expect(findExport(name) != null);
    }}
}}
{END}"""


def main() -> int:
    imports = read_imports(IMAGE)
    handled = handled_names(DISPATCHER)
    policy_refused = policy_refused_names(DISPATCHER)
    written = 0
    total_rows = 0
    for dll, names in imports.items():
        directory = package_directory(dll)
        if directory is None:
            print(f"generate: no package for {dll}", file=sys.stderr)
            return 1
        source = directory / "src" / "root.zig"
        text = source.read_text(encoding="utf-8")
        block = render(dll, names + owned_names(source), handled, policy_refused)
        if BEGIN in text:
            start = text.index(BEGIN)
            finish = text.index(END) + len(END)
            text = text[:start] + block + text[finish:]
        else:
            if 'const export_contract = @import("dll_win32_export_contract");' not in text:
                text = text.replace(
                    'const std = @import("std");',
                    'const std = @import("std");\nconst export_contract = @import("dll_win32_export_contract");',
                    1,
                )
            text = text.rstrip("\n") + "\n\n" + block + "\n"
        source.write_text(text, encoding="utf-8")
        written += 1
        total_rows += len(set(names))
    print(f"generate: {written} package(s), {total_rows} declared export(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
