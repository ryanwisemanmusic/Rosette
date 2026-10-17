#!/usr/bin/env python3
"""Fail-closed audit of Rosette's Windows import surface.

Three facts have to agree, and until now nothing compared them:

  1. the names the guest image imports, read from its PE import directory;
  2. the names each `pkg/dll/win32/<dll>` package declares, with the ABI each
     return value follows;
  3. the names `src/x64-ASM/windows_runtime.zig` actually handles.

Each pair can drift on its own. A name in the image that no package declares
is a call Rosette answers without having written down what the answer means -
which is how `VirtualProtect` returned FALSE on every call for the life of the
project without anybody noticing. A package that claims `served` for a name
the dispatcher stopped handling is a declaration that has gone stale, and a
stale declaration is worse than none: the refusal report trusts it.

The audit reports the surface's coverage as well as its errors, because
"seventy-one percent of what the guest imports is implemented" is the number
this work exists to move, and a number nobody prints does not move.
"""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "dll"))
from dispatcher import handled_names, policy_refused_names  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
IMAGE = ROOT / "build" / "xenia-windows-clean" / "bundle" / "xenia_canary.exe"
DISPATCHER = ROOT / "src" / "x64-ASM" / "windows_runtime.zig"
PACKAGES = ROOT / "pkg" / "dll" / "win32"

ROW = re.compile(
    r'\.\{\s*\.name = "([^"]+)"(?P<rest>[^}]*)\},'
)


def read_imports(path: Path) -> dict[str, list[str]]:
    data = path.read_bytes()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    section_count = struct.unpack_from("<H", data, pe + 6)[0]
    optional = pe + 24
    import_rva = struct.unpack_from("<I", data, optional + 112 + 8)[0]
    sections = []
    table = pe + 24 + optional_size
    for index in range(section_count):
        offset = table + index * 40
        virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from("<IIII", data, offset + 8)
        sections.append((virtual_address, max(virtual_size, raw_size), raw_offset))

    def to_offset(rva):
        for virtual_address, span, raw_offset in sections:
            if virtual_address <= rva < virtual_address + span:
                return raw_offset + (rva - virtual_address)
        return None

    def cstring(offset):
        return data[offset : data.index(b"\0", offset)].decode("latin1")

    imports = {}
    cursor = to_offset(import_rva)
    while True:
        lookup, _, _, name_rva, thunk = struct.unpack_from("<IIIII", data, cursor)
        if lookup == 0 and name_rva == 0 and thunk == 0:
            break
        names = []
        entry = to_offset(lookup or thunk)
        while True:
            value = struct.unpack_from("<Q", data, entry)[0]
            if value == 0:
                break
            if not value & (1 << 63):
                names.append(cstring(to_offset(value & 0x7FFFFFFF) + 2))
            entry += 8
        imports[cstring(to_offset(name_rva))] = names
        cursor += 20
    return imports




def declared() -> dict[str, dict[str, dict]]:
    """{package stem: {name: {behaviour, reviewed}}} from each surface."""
    surfaces = {}
    for directory in sorted(PACKAGES.iterdir()):
        source = directory / "src" / "root.zig"
        if not source.exists():
            continue
        text = source.read_text(encoding="utf-8")
        marker = text.find("pub const exports = [_]export_contract.Export{")
        if marker < 0:
            continue
        body = text[marker : text.find("\n};", marker)]
        rows = {}
        for match in ROW.finditer(body):
            rest = match.group("rest")
            behaviour = re.search(r"\.behaviour = \.(\w+)", rest)
            note = re.search(r'\.note = "([^"]*)"', rest)
            rows[match.group(1)] = {
                "behaviour": behaviour.group(1) if behaviour else "not_implemented",
                "reviewed": ".reviewed = true" in rest,
                "note": note.group(1) if note else "",
            }
        surfaces[directory.name] = rows
    return surfaces


def main() -> int:
    if not IMAGE.exists():
        print(f"dll coverage: SKIP (no image at {IMAGE})")
        return 0
    imports = read_imports(IMAGE)
    handled = handled_names(DISPATCHER) | policy_refused_names(DISPATCHER)
    surfaces = declared()
    everything = {}
    for rows in surfaces.values():
        everything.update(rows)

    errors: list[str] = []
    imported = [name for names in imports.values() for name in names]
    unique = sorted(set(imported))

    for name in unique:
        if name not in everything:
            errors.append(f"{name} is imported by the guest and no package declares it")

    # A declaration that says Rosette answers a name the dispatcher no longer
    # handles is worse than no declaration: the refusal report trusts it.
    for name, row in sorted(everything.items()):
        satisfied = row["behaviour"] in ("served", "modelled")
        owned_refusal = row["behaviour"] == "refused_by_policy"
        if (satisfied or owned_refusal) and name not in handled:
            errors.append(
                f"{name} is declared {row['behaviour']} but the dispatcher has no handler for it"
            )
        if owned_refusal and not row["reviewed"]:
            errors.append(f"{name} is refused_by_policy but is not marked reviewed")
        if owned_refusal and not row.get("note", "").strip():
            errors.append(f"{name} is refused_by_policy but has no policy note")
        if row["behaviour"] == "not_implemented" and name in handled and name in everything:
            errors.append(
                f"{name} is declared {row['behaviour']} but the dispatcher does handle it"
            )

    reviewed = sum(1 for name in unique if everything.get(name, {}).get("reviewed"))
    implemented = sum(
        1
        for name in unique
        if everything.get(name, {}).get("behaviour") in ("served", "modelled")
    )
    declined = sum(
        1 for name in unique if everything.get(name, {}).get("behaviour") == "refused_by_policy"
    )
    missing = len(unique) - implemented - declined

    print(
        f"dll coverage: libraries={len(imports)} imported_names={len(unique)} "
        f"declared={len([n for n in unique if n in everything])} reviewed={reviewed}"
    )
    print(
        f"dll coverage: implemented={implemented} ({implemented * 100 // len(unique)}%) "
        f"declined_by_policy={declined} not_implemented={missing}"
    )
    for library, names in sorted(imports.items()):
        rows = [everything.get(name, {}) for name in set(names)]
        served = sum(1 for row in rows if row.get("behaviour") in ("served", "modelled"))
        if served != len(rows):
            print(f"dll coverage:   {library}: {served}/{len(rows)} implemented")

    if errors:
        for error in errors[:40]:
            print(f"dll coverage: FAIL {error}")
        if len(errors) > 40:
            print(f"dll coverage: FAIL ... and {len(errors) - 40} more")
        print(f"dll coverage: FAIL ({len(errors)} disagreement(s))")
        return 1
    print("dll coverage: PASS (every imported name is declared, and every declaration matches the dispatcher)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
