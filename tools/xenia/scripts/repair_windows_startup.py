#!/usr/bin/env python3
"""Validate and repair the Rosetta Windows capsule's MinGW startup order.

The selected Xenia checkout is never modified.  This tool operates only on
the executable already copied into the Rosetta-owned bundle.  MinGW's
``__do_global_ctors`` walks ``__CTOR_LIST__`` backwards, so the constructor
that creates Xenia's x64 sequence table must appear after the other x64
backend constructors in the list.  Some lld/ThinLTO combinations emit that
order in the opposite direction and the first sequence registration then
divides by a zero bucket count.
"""

from __future__ import annotations

import argparse
import os
import struct
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


COFF_SYMBOL_SIZE = 18
MAX_CONSTRUCTORS = 1 << 20
UINT64_MAX = (1 << 64) - 1
SEQUENCE_TABLE_INITIALIZER = "_GLOBAL__sub_I_x64_sequences.cc"
X64_CONSTRUCTOR_PREFIX = "_GLOBAL__sub_I_x64_"


@dataclass(frozen=True)
class Section:
    name: str
    virtual_address: int
    virtual_size: int
    raw_pointer: int
    raw_size: int


class PeError(ValueError):
    """A PE startup contract could not be proven safe to rewrite."""


def section_file_offset(
    sections: list[Section], rva: int, size: int, data_size: int
) -> int:
    for section in sections:
        span = max(section.virtual_size, section.raw_size)
        if section.virtual_address <= rva and rva + size <= section.virtual_address + span:
            offset = section.raw_pointer + (rva - section.virtual_address)
            if offset < 0 or offset + size > data_size:
                break
            return offset
    raise PeError(f"RVA 0x{rva:x} is not backed by a file section")


def parse_pe(data: bytes) -> tuple[int, list[Section], int, int, int]:
    if len(data) < 0x40 or data[:2] != b"MZ":
        raise PeError("input is not an MZ executable")
    pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
    if pe_offset + 4 + 20 > len(data) or data[pe_offset : pe_offset + 4] != b"PE\0\0":
        raise PeError("PE signature is missing")

    coff_offset = pe_offset + 4
    (
        machine,
        section_count,
        _timestamp,
        symbol_pointer,
        symbol_count,
        optional_size,
        _characteristics,
    ) = struct.unpack_from("<HHIIIHH", data, coff_offset)
    if machine != 0x8664:
        raise PeError(f"expected AMD64 PE, found machine 0x{machine:04x}")

    optional_offset = coff_offset + 20
    if optional_offset + optional_size > len(data) or optional_size < 32:
        raise PeError("optional PE header is truncated")
    optional_magic = struct.unpack_from("<H", data, optional_offset)[0]
    if optional_magic != 0x20B:
        raise PeError(f"expected PE32+, found optional magic 0x{optional_magic:04x}")
    image_base = struct.unpack_from("<Q", data, optional_offset + 24)[0]

    section_offset = optional_offset + optional_size
    sections: list[Section] = []
    for index in range(section_count):
        offset = section_offset + index * 40
        if offset + 40 > len(data):
            raise PeError("section table is truncated")
        raw_name = data[offset : offset + 8].split(b"\0", 1)[0]
        name = raw_name.decode("ascii", errors="replace")
        virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from(
            "<IIII", data, offset + 8
        )
        if raw_pointer + raw_size > len(data):
            raise PeError(f"section {name!r} extends past the file")
        sections.append(
            Section(name, virtual_address, virtual_size, raw_pointer, raw_size)
        )

    return image_base, sections, symbol_pointer, symbol_count, section_offset


def symbol_name(raw_name: bytes, string_table: bytes) -> str:
    if raw_name[:4] != b"\0\0\0\0":
        return raw_name.split(b"\0", 1)[0].decode("utf-8", errors="replace")
    string_offset = struct.unpack_from("<I", raw_name, 4)[0]
    if string_offset < 4 or string_offset >= len(string_table):
        return ""
    return string_table[string_offset:].split(b"\0", 1)[0].decode(
        "utf-8", errors="replace"
    )


def parse_symbols(
    data: bytes,
    image_base: int,
    sections: list[Section],
    symbol_pointer: int,
    symbol_count: int,
) -> dict[str, int]:
    if symbol_pointer == 0 or symbol_count == 0:
        raise PeError("the PE has no COFF symbol table; constructor order cannot be proven")
    symbol_end = symbol_pointer + symbol_count * COFF_SYMBOL_SIZE
    if symbol_end + 4 > len(data):
        raise PeError("COFF symbol table is truncated")
    string_size = struct.unpack_from("<I", data, symbol_end)[0]
    if string_size < 4 or symbol_end + string_size > len(data):
        raise PeError("COFF string table is truncated")
    string_table = data[symbol_end : symbol_end + string_size]

    symbols: dict[str, int] = {}
    index = 0
    while index < symbol_count:
        offset = symbol_pointer + index * COFF_SYMBOL_SIZE
        raw = data[offset : offset + COFF_SYMBOL_SIZE]
        name = symbol_name(raw[:8], string_table)
        value = struct.unpack_from("<I", raw, 8)[0]
        section_number = struct.unpack_from("<h", raw, 12)[0]
        auxiliary_count = raw[17]
        if 1 <= section_number <= len(sections):
            section = sections[section_number - 1]
            address = image_base + section.virtual_address + value
            if name and name not in symbols:
                symbols[name] = address
        elif section_number == -1 and name and name not in symbols:
            symbols[name] = value
        index += 1 + auxiliary_count
    return symbols


def read_constructor_list(
    data: bytes, sections: list[Section], list_address: int, image_base: int
) -> tuple[int, list[int]]:
    if list_address < image_base:
        raise PeError("__CTOR_LIST__ is not an image address")
    list_rva = list_address - image_base
    list_offset = section_file_offset(sections, list_rva, 8, len(data))
    values: list[int] = []
    for index in range(MAX_CONSTRUCTORS):
        offset = list_offset + index * 8
        if offset + 8 > len(data):
            raise PeError("__CTOR_LIST__ has no terminator within the file")
        value = struct.unpack_from("<Q", data, offset)[0]
        if index == 0 and value != UINT64_MAX:
            raise PeError(
                f"__CTOR_LIST__ does not start with the MinGW sentinel: 0x{value:x}"
            )
        if index > 0 and value == 0:
            return list_offset, values
        values.append(value)
    raise PeError(f"__CTOR_LIST__ exceeds {MAX_CONSTRUCTORS} entries")


def atomic_replace(path: Path, data: bytes) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
    except Exception:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def repair(path: Path, check_only: bool) -> int:
    data = path.read_bytes()
    image_base, sections, symbol_pointer, symbol_count, _ = parse_pe(data)
    symbols = parse_symbols(
        data, image_base, sections, symbol_pointer, symbol_count
    )
    list_address = symbols.get("__CTOR_LIST__")
    initializer_address = symbols.get(SEQUENCE_TABLE_INITIALIZER)
    if list_address is None:
        raise PeError("__CTOR_LIST__ symbol is missing")
    if initializer_address is None:
        raise PeError(f"{SEQUENCE_TABLE_INITIALIZER} symbol is missing")

    list_offset, values = read_constructor_list(
        data, sections, list_address, image_base
    )
    initializer_indices = [
        index for index, value in enumerate(values) if value == initializer_address
    ]
    if len(initializer_indices) != 1:
        raise PeError(
            f"{SEQUENCE_TABLE_INITIALIZER} appears {len(initializer_indices)} times in __CTOR_LIST__"
        )
    initializer_index = initializer_indices[0]

    x64_constructors = sorted(
        (name, address)
        for name, address in symbols.items()
        if name.startswith(X64_CONSTRUCTOR_PREFIX)
    )
    anchor_indices: list[tuple[int, str]] = []
    for name, address in x64_constructors:
        if name == SEQUENCE_TABLE_INITIALIZER:
            continue
        indices = [index for index, value in enumerate(values) if value == address]
        if len(indices) == 1:
            anchor_indices.append((indices[0], name))
        elif len(indices) > 1:
            raise PeError(f"x64 constructor {name} appears multiple times")
    if not anchor_indices:
        raise PeError("no x64 constructor anchors were found in __CTOR_LIST__")

    last_anchor_index = max(index for index, _ in anchor_indices)
    if initializer_index > last_anchor_index:
        print(
            "windows-startup-repair: rule=x64-sequence-table "
            f"status=already-correct initializer_index={initializer_index} "
            f"last_x64_anchor_index={last_anchor_index}"
        )
        return 0

    reordered = values.copy()
    initializer = reordered.pop(initializer_index)
    reordered.insert(last_anchor_index, initializer)
    new_index = reordered.index(initializer_address)
    if new_index <= max(
        index - (1 if index > initializer_index else 0) for index, _ in anchor_indices
    ):
        raise PeError("constructor reorder did not place the sequence initializer last")

    if check_only:
        print(
            "windows-startup-repair: rule=x64-sequence-table "
            f"status=needs-repair initializer_index={initializer_index} "
            f"required_index={new_index} anchors={len(anchor_indices)}"
        )
        return 2

    rewritten = bytearray(data)
    for index, value in enumerate(reordered):
        struct.pack_into("<Q", rewritten, list_offset + index * 8, value)
    # The terminator is intentionally left in place immediately after the
    # reordered entries; the list length never changes.
    atomic_replace(path, bytes(rewritten))
    print(
        "windows-startup-repair: rule=x64-sequence-table status=changed "
        f"initializer_index={initializer_index} new_index={new_index} "
        f"anchors={len(anchor_indices)} last_anchor={max(anchor_indices)[1]}"
    )
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate the ordering without modifying the executable",
    )
    args = parser.parse_args(argv)
    try:
        return repair(args.executable.resolve(), args.check)
    except (OSError, PeError, struct.error) as error:
        print(f"windows-startup-repair: status=refused reason={error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
