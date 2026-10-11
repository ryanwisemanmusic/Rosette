#!/usr/bin/env python3
"""Validate, rebuild, and install Xbox 360 GOD/XISO media.

This is intentionally a Rosetta-side tool.  It does not depend on Xenia and
does not try to make a damaged byte range look valid.  A GOD package contains
the 44 KiB package header plus a ``.data`` directory whose DataNNNN members
carry the XISO bytes with the package hash/stripe bytes interleaved.  The
layout and transform implemented here are the same layout used by the
open-source GOD2ISO 1.0.5 converter, with stricter input and output checks.

Commands:

    inspect PATH
        Inspect a GOD package or an already-built XISO without reading all
        media bytes.

    pack PATH --output IMAGE
        Rebuild an XISO from the GOD package into a new path.

    repair PATH --output IMAGE
        Alias for pack, named to make recovery workflows explicit.  Repair is
        reconstruction from a complete source package; it never zero-fills a
        missing range and calls that repair.

    install PATH --target IMAGE --replace
        Build and verify a new image, then move an existing target to a
        timestamped backup before atomically installing the new image.

    verify IMAGE [--full]
        Validate XISO headers and every reachable directory table.  ``--full``
        also reads and hashes the complete image, which is the authoritative
        test for an external volume that may fail only during a long read.

The implementation uses only Python's standard library so it can run from a
Rosetta checkout on a clean macOS installation.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import sys
import tempfile
import time
from collections import deque
from typing import BinaryIO, Iterable, Iterator, Optional


TOOL_NAME = "rosette-xbox360-media"
TOOL_VERSION = "1.0"

# GOD2ISO's DataNNNN members begin with 0x2000 bytes of package/hash material.
# The converter emits 0xcc000 bytes and consumes (discards) the following
# 0x1000 bytes on every complete output block.
DATA_PREFIX_BYTES = 0x2000
OUTPUT_CHUNK_BYTES = 0xCC000
DISCARD_CHUNK_BYTES = 0x1000

# XSFHeader.bin used by GOD2ISO is exactly 64 KiB.  XISO's volume descriptor
# therefore lands at byte 0x10000 in the output image.
XSF_HEADER_BYTES = 0x10000
XSF_MAGIC = b"XSF\x1a"
XISO_MAGIC = b"MICROSOFT*XBOX*MEDIA"
XISO_DESCRIPTOR_OFFSET = 0x10000
XISO_SECTOR_BYTES = 2048

# XISO directory records.  These are not ISO-9660 records: the first four
# bytes are the left/right tree links, followed by a sector, byte length,
# attributes, name length, and a name padded to four bytes.
DIRECTORY_ENTRY_SECTOR_OFFSET = 4
DIRECTORY_ENTRY_LENGTH_OFFSET = 8
DIRECTORY_ENTRY_ATTRIBUTES_OFFSET = 12
DIRECTORY_ENTRY_NAME_LENGTH_OFFSET = 13
DIRECTORY_ENTRY_NAME_OFFSET = 14
DIRECTORY_ATTRIBUTE = 0x10

MAX_DIRECTORY_TABLE_BYTES = 128 * 1024 * 1024
MAX_DIRECTORY_TABLES = 1_000_000
MAX_MANIFEST_BYTES = 16 * 1024 * 1024
DATA_FILE_RE = re.compile(r"^Data([0-9]{4})$")


class MediaError(Exception):
    """A user-actionable media validation or conversion failure."""


@dataclasses.dataclass(frozen=True)
class PackageInfo:
    """Validated layout facts for one extracted GOD package."""

    header: Path
    data_dir: Path
    data_files: tuple[Path, ...]
    header_size: int
    signature: bytes
    header_sha256: str
    data_bytes: int
    data_sha256: Optional[str]
    has_xsf_header: bool
    output_size: int
    offset_field: Optional[int]
    sector_correction: int
    raw_root_sector: int
    corrected_root_sector: int
    root_size: int


@dataclasses.dataclass(frozen=True)
class ImageVerification:
    path: Path
    size: int
    xiso_offset: int
    root_sector: int
    root_size: int
    directories: int
    entries: int
    patched_entries: int
    sha256: Optional[str]


def _fail(message: str) -> "NoReturn":
    raise MediaError(message)


def _read_up_to(stream: BinaryIO, length: int) -> bytes:
    """Read up to length bytes, handling short regular-file reads."""

    if length < 0:
        _fail(f"negative read length: {length}")
    chunks: list[bytes] = []
    remaining = length
    while remaining:
        chunk = stream.read(remaining)
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def _read_exact(stream: BinaryIO, length: int, description: str) -> bytes:
    data = _read_up_to(stream, length)
    if len(data) != length:
        _fail(
            f"{description}: expected {length} bytes, received {len(data)} "
            f"at offset {stream.tell() - len(data):#x}"
        )
    return data


def _read_at(stream: BinaryIO, offset: int, length: int, description: str) -> bytes:
    if offset < 0:
        _fail(f"{description}: negative offset {offset}")
    stream.seek(offset)
    return _read_exact(stream, length, description)


def _sha256_file(path: Path, progress: Optional[callable] = None) -> str:
    digest = hashlib.sha256()
    total = 0
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(8 * 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            total += len(chunk)
            if progress is not None:
                progress(total)
    return digest.hexdigest()


def _unique_path(path: Path, suffix: str) -> Path:
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    candidate = path.with_name(f"{path.name}.{suffix}-{stamp}-{os.getpid()}")
    serial = 1
    while candidate.exists():
        candidate = path.with_name(
            f"{path.name}.{suffix}-{stamp}-{os.getpid()}-{serial}"
        )
        serial += 1
    return candidate


def _fsync_directory(path: Path) -> None:
    """Make a completed same-directory rename durable when supported."""

    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return
    try:
        try:
            os.fsync(fd)
        except OSError:
            # Some mounted filesystems reject fsync on a directory.  The file
            # itself was already fsynced; this is a durability optimization.
            pass
    finally:
        os.close(fd)


def _atomic_write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = _unique_path(path, "partial")
    try:
        with temporary.open("x", encoding="utf-8") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        _fsync_directory(path.parent)
    except Exception:
        # Keep an incomplete artifact for forensic recovery rather than
        # silently deleting evidence from a failed media operation.
        raise


def _candidate_from_data_dir(data_dir: Path) -> Optional[tuple[Path, Path]]:
    if not data_dir.is_dir() or not data_dir.name.lower().endswith(".data"):
        return None
    header = data_dir.parent / data_dir.name[: -len(".data")]
    if not header.is_file():
        return None
    return header, data_dir


def _discover_package(path: Path) -> tuple[Path, Path]:
    """Resolve a header + sibling .data directory from common dump paths."""

    path = path.expanduser()
    if not path.exists():
        _fail(f"package path does not exist: {path}")

    if path.is_file():
        data_dir = Path(f"{path}.data")
        if not data_dir.is_dir():
            _fail(f"GOD header has no sibling data directory: {data_dir}")
        return path, data_dir

    if path.is_dir() and path.name.lower().endswith(".data"):
        found = _candidate_from_data_dir(path)
        if found is None:
            _fail(f"data directory has no matching GOD header: {path}")
        return found

    candidates: list[tuple[Path, Path]] = []

    def consider(directory: Path) -> None:
        try:
            children = list(directory.iterdir())
        except OSError as exc:
            _fail(f"cannot enumerate package directory {directory}: {exc}")
        for child in children:
            found = _candidate_from_data_dir(child)
            if found is not None:
                candidates.append(found)

    # The normal extracted layout is either PATH/{header,header.data} or
    # PATH/00004000/{header,header.data}.  Scan only this small depth so a
    # broad game library cannot accidentally select an unrelated title.
    consider(path)
    try:
        children = list(path.iterdir())
    except OSError as exc:
        _fail(f"cannot enumerate package directory {path}: {exc}")
    for child in children:
        if child.is_dir():
            consider(child)

    unique = {(header.resolve(), data.resolve()): (header, data) for header, data in candidates}
    if len(unique) == 1:
        return next(iter(unique.values()))
    if not unique:
        _fail(
            f"could not find a GOD header + .data pair below {path}; "
            "select the 44 KiB file without an extension or its .data directory"
        )
    listing = ", ".join(str(header) for header, _ in unique.values())
    _fail(f"multiple GOD packages found below {path}; select one explicitly: {listing}")


def _collect_data_files(data_dir: Path) -> tuple[Path, ...]:
    try:
        children = list(data_dir.iterdir())
    except OSError as exc:
        _fail(f"cannot enumerate GOD data directory {data_dir}: {exc}")

    numbered: dict[int, Path] = {}
    suspicious: list[str] = []
    for child in children:
        match = DATA_FILE_RE.fullmatch(child.name)
        if match is None:
            if child.name.lower().startswith("data"):
                suspicious.append(child.name)
            continue
        if not child.is_file():
            _fail(f"GOD data member is not a regular file: {child}")
        index = int(match.group(1))
        if index in numbered:
            _fail(f"duplicate GOD data member index {index:04d} in {data_dir}")
        numbered[index] = child

    if suspicious:
        _fail(
            f"unrecognized Data members in {data_dir}: {', '.join(sorted(suspicious))}; "
            "expected exactly Data0000, Data0001, ... with no gaps"
        )
    if not numbered:
        _fail(f"GOD data directory contains no DataNNNN members: {data_dir}")

    expected = set(range(len(numbered)))
    actual = set(numbered)
    if actual != expected:
        missing = sorted(expected - actual)
        if missing:
            # If a later member exists, report the first concrete gap instead
            # of hiding it behind a generic count error.
            _fail(f"GOD data members have a gap; missing Data{missing[0]:04d}")
        _fail("GOD data member indices are not contiguous from Data0000")

    return tuple(numbered[index] for index in range(len(numbered)))


def _transform_length(size: int, path: Path) -> int:
    if size < DATA_PREFIX_BYTES:
        _fail(
            f"{path}: size {size} is shorter than the GOD data prefix "
            f"({DATA_PREFIX_BYTES} bytes)"
        )
    remaining = size - DATA_PREFIX_BYTES
    output = 0
    while remaining:
        emitted = min(OUTPUT_CHUNK_BYTES, remaining)
        output += emitted
        remaining -= emitted
        if emitted < OUTPUT_CHUNK_BYTES:
            break
        discarded = min(DISCARD_CHUNK_BYTES, remaining)
        remaining -= discarded
        if discarded < DISCARD_CHUNK_BYTES:
            break
    if remaining != 0:
        _fail(f"{path}: GOD stripe layout leaves {remaining} unconsumed bytes")
    return output


def _make_xsf_header() -> bytes:
    """Create the standard GOD2ISO 64 KiB XSF header without a binary asset."""

    header = bytearray(XSF_HEADER_BYTES)
    header[0:4] = XSF_MAGIC
    header[5] = 0x04
    header[8:16] = b"SIZE-64L"
    header[0x10] = 0x02
    header[0x7A69 : 0x7A69 + len(b"Tool Name")] = b"Tool Name"

    # Primary volume descriptor template.
    header[0x8000 : 0x8000 + 7] = b"\x01CD001\x01"
    header[0x8050 : 0x8050 + 8] = b"SecLSecB"
    header[0x8078] = 0x01
    header[0x807B : 0x807D] = b"\x01\x01"
    header[0x807F] = 0x01
    header[0x8081 : 0x8083] = b"\x08\x08"

    # The XSF template's volume identifier is space-padded and carries three
    # 16-character zero identifiers separated by NULs.
    header[0x80BE:0x832D] = b" " * (0x832D - 0x80BE)
    for offset in (0x832D, 0x833E, 0x834F, 0x8360):
        header[offset : offset + 16] = b"0" * 16
    header[0x8371] = 0x01

    # Set terminator descriptor.
    header[0x8800 : 0x8800 + 7] = b"\xffCD001\x01"
    return bytes(header)


def _read_package_header(header_path: Path) -> tuple[bytes, bytes, int, Optional[int], int]:
    try:
        header_size = header_path.stat().st_size
    except OSError as exc:
        _fail(f"cannot stat GOD header {header_path}: {exc}")
    if header_size < 0x399:
        _fail(f"GOD header is too short ({header_size} bytes): {header_path}")
    if header_size > MAX_MANIFEST_BYTES:
        _fail(
            f"GOD header is implausibly large ({header_size} bytes): {header_path}"
        )

    with header_path.open("rb") as stream:
        raw = _read_exact(stream, header_size, f"reading GOD header {header_path}")
    signature = raw[:4]
    if signature[:3] not in {b"CON", b"PIR", b"LIV"}:
        _fail(
            f"unsupported GOD/STFS header signature {signature!r} in {header_path}; "
            "expected CON, PIRS, or LIVE"
        )

    flag = raw[0x391]
    if flag & 0x40:
        offset_field = struct.unpack_from("<I", raw, 0x395)[0]
        correction = offset_field * 2 - 34
        if correction < 0:
            _fail(
                f"invalid GOD sector correction field {offset_field} in {header_path}"
            )
    else:
        offset_field = None
        correction = 0
    return raw, signature, header_size, offset_field, correction


def _read_xiso_source_facts(
    data_file: Path, has_xsf: bool
) -> tuple[int, int]:
    source_xiso_offset = DATA_PREFIX_BYTES + (XSF_HEADER_BYTES if has_xsf else 0)
    with data_file.open("rb") as stream:
        magic = _read_at(
            stream,
            source_xiso_offset,
            len(XISO_MAGIC),
            f"reading XISO magic from {data_file}",
        )
        if magic != XISO_MAGIC:
            _fail(
                f"{data_file}: expected XISO magic at source offset "
                f"{source_xiso_offset:#x}, got {magic!r}"
            )
        fields = _read_at(
            stream,
            source_xiso_offset + 20,
            8,
            f"reading XISO root fields from {data_file}",
        )
    raw_root_sector, root_size = struct.unpack("<II", fields)
    if raw_root_sector == 0:
        _fail(f"{data_file}: XISO root sector is zero")
    if root_size == 0 or root_size > MAX_DIRECTORY_TABLE_BYTES:
        _fail(f"{data_file}: implausible XISO root table size {root_size}")
    return raw_root_sector, root_size


def inspect_package(path: Path, *, hash_data: bool = False) -> PackageInfo:
    header, data_dir = _discover_package(path)
    data_files = _collect_data_files(data_dir)
    raw_header, signature, header_size, offset_field, correction = _read_package_header(header)

    data_bytes = 0
    output_body_bytes = 0
    for data_file in data_files:
        try:
            size = data_file.stat().st_size
        except OSError as exc:
            _fail(f"cannot stat GOD data member {data_file}: {exc}")
        data_bytes += size
        output_body_bytes += _transform_length(size, data_file)

    try:
        data0_size = data_files[0].stat().st_size
    except OSError as exc:
        _fail(f"cannot stat {data_files[0]}: {exc}")
    if data0_size < DATA_PREFIX_BYTES + len(XISO_MAGIC):
        _fail(f"{data_files[0]} is too short to contain an XISO header")
    with data_files[0].open("rb") as stream:
        data0_marker = _read_at(stream, DATA_PREFIX_BYTES, 4, f"reading {data_files[0]}")
    has_xsf = data0_marker == XSF_MAGIC
    raw_root_sector, root_size = _read_xiso_source_facts(data_files[0], has_xsf)

    output_size = output_body_bytes if has_xsf else XSF_HEADER_BYTES + output_body_bytes
    if output_size % XISO_SECTOR_BYTES != 0:
        _fail(f"reconstructed XISO length is not sector-aligned: {output_size}")
    corrected_root_sector = raw_root_sector
    if correction:
        if raw_root_sector <= correction:
            _fail(
                f"GOD root sector {raw_root_sector:#x} is not above correction "
                f"{correction:#x}"
            )
        corrected_root_sector -= correction
    root_end = corrected_root_sector * XISO_SECTOR_BYTES + root_size
    if root_end > output_size:
        _fail(
            f"reconstructed root table ends at {root_end:#x}, beyond output "
            f"length {output_size:#x}"
        )

    data_sha256: Optional[str] = None
    if hash_data:
        digest = hashlib.sha256()
        for data_file in data_files:
            with data_file.open("rb") as stream:
                while True:
                    chunk = stream.read(8 * 1024 * 1024)
                    if not chunk:
                        break
                    digest.update(chunk)
        data_sha256 = digest.hexdigest()

    return PackageInfo(
        header=header,
        data_dir=data_dir,
        data_files=data_files,
        header_size=header_size,
        signature=signature,
        header_sha256=hashlib.sha256(raw_header).hexdigest(),
        data_bytes=data_bytes,
        data_sha256=data_sha256,
        has_xsf_header=has_xsf,
        output_size=output_size,
        offset_field=offset_field,
        sector_correction=correction,
        raw_root_sector=raw_root_sector,
        corrected_root_sector=corrected_root_sector,
        root_size=root_size,
    )


def _format_bytes(value: int) -> str:
    units = ("B", "KiB", "MiB", "GiB", "TiB")
    number = float(value)
    for unit in units:
        if abs(number) < 1024.0 or unit == units[-1]:
            if unit == "B":
                return f"{value} {unit}"
            return f"{number:.2f} {unit} ({value} bytes)"
        number /= 1024.0
    return f"{value} bytes"


def print_package_info(info: PackageInfo, *, as_json: bool = False) -> None:
    record = {
        "kind": "god-package",
        "header": str(info.header),
        "data_directory": str(info.data_dir),
        "signature": info.signature.decode("ascii", errors="replace"),
        "header_bytes": info.header_size,
        "header_sha256": info.header_sha256,
        "data_members": len(info.data_files),
        "data_bytes": info.data_bytes,
        "data_sha256": info.data_sha256,
        "has_xsf_header": info.has_xsf_header,
        "reconstructed_bytes": info.output_size,
        "reconstructed_sectors": info.output_size // XISO_SECTOR_BYTES,
        "offset_field": info.offset_field,
        "sector_correction": info.sector_correction,
        "raw_root_sector": info.raw_root_sector,
        "corrected_root_sector": info.corrected_root_sector,
        "root_size": info.root_size,
        "xiso_descriptor_offset": XISO_DESCRIPTOR_OFFSET,
        "transform": {
            "data_prefix_bytes": DATA_PREFIX_BYTES,
            "output_chunk_bytes": OUTPUT_CHUNK_BYTES,
            "discard_chunk_bytes": DISCARD_CHUNK_BYTES,
        },
    }
    if as_json:
        print(json.dumps(record, indent=2, sort_keys=True))
        return
    print(f"GOD package:       {info.header}")
    print(f"Data directory:    {info.data_dir}")
    print(f"Signature:         {record['signature']}")
    print(f"Header:            {_format_bytes(info.header_size)}")
    print(f"Data members:      {len(info.data_files)}")
    print(f"Data bytes:        {_format_bytes(info.data_bytes)}")
    print(f"Reconstructed:     {_format_bytes(info.output_size)}")
    print(f"XSF header:        {'present' if info.has_xsf_header else 'generated (64 KiB)'}")
    if info.offset_field is None:
        print("Sector correction: 0 (header flag is not set)")
    else:
        print(
            f"Sector correction: {info.sector_correction} sectors "
            f"(header field {info.offset_field})"
        )
    print(
        f"Root directory:    raw sector {info.raw_root_sector:#x} -> "
        f"{info.corrected_root_sector:#x}, {info.root_size} bytes"
    )
    print(
        "Result:             source layout is complete and can be rebuilt; "
        "full output hashing remains required for storage verification"
    )


def _correct_sector(raw_sector: int, correction: int, context: str) -> int:
    if raw_sector == 0:
        return 0
    if raw_sector <= correction:
        _fail(
            f"{context}: raw sector {raw_sector:#x} cannot be corrected by "
            f"{correction:#x} without underflow"
        )
    return raw_sector - correction


def _validate_extent(
    sector: int, length: int, image_size: int, context: str, *, directory: bool
) -> None:
    if length < 0:
        _fail(f"{context}: negative extent length")
    if directory and (length == 0 or length > MAX_DIRECTORY_TABLE_BYTES):
        _fail(f"{context}: implausible directory length {length}")
    if sector == 0:
        if directory:
            _fail(f"{context}: directory extent has zero sector")
        return
    start = sector * XISO_SECTOR_BYTES
    end = start + length
    if start >= image_size or end > image_size:
        _fail(
            f"{context}: extent [{start:#x}, {end:#x}) exceeds image "
            f"length {image_size:#x}"
        )


def _walk_and_patch_directories(
    stream: BinaryIO,
    image_size: int,
    root_sector: int,
    root_size: int,
    correction: int,
    *,
    write_changes: bool,
) -> tuple[int, int, int]:
    """Walk all reachable XISO directory tables and correct entry sectors."""

    _validate_extent(root_sector, root_size, image_size, "XISO root", directory=True)
    queue: deque[tuple[int, int]] = deque([(root_sector, root_size)])
    visited: set[tuple[int, int]] = set()
    directories = 0
    entries = 0
    patched_entries = 0

    while queue:
        sector, table_size = queue.popleft()
        key = (sector, table_size)
        if key in visited:
            continue
        visited.add(key)
        directories += 1
        if directories > MAX_DIRECTORY_TABLES:
            _fail(
                f"XISO directory graph exceeds {MAX_DIRECTORY_TABLES} tables; "
                "refusing an unbounded traversal"
            )

        table_start = sector * XISO_SECTOR_BYTES
        _validate_extent(sector, table_size, image_size, "XISO directory", directory=True)
        stream.seek(table_start)
        table = bytearray(_read_exact(stream, table_size, f"reading XISO directory at {table_start:#x}"))
        changed = False
        position = 0

        while position + 4 <= len(table):
            # Records never straddle an XISO sector.  A sector boundary can
            # contain either padding or the ffffffff tree sentinel.
            sector_end = ((position // XISO_SECTOR_BYTES) + 1) * XISO_SECTOR_BYTES
            if position + 4 > sector_end:
                position = sector_end
                continue

            link_word = struct.unpack_from("<I", table, position)[0]
            if link_word == 0xFFFFFFFF:
                if len(table) - position > XISO_SECTOR_BYTES:
                    position = sector_end
                    continue
                break

            if position + DIRECTORY_ENTRY_NAME_OFFSET > len(table):
                _fail(
                    f"XISO directory at {table_start:#x}: truncated entry header "
                    f"at +{position:#x}"
                )
            raw_sector = struct.unpack_from(
                "<I", table, position + DIRECTORY_ENTRY_SECTOR_OFFSET
            )[0]
            extent_length = struct.unpack_from(
                "<I", table, position + DIRECTORY_ENTRY_LENGTH_OFFSET
            )[0]
            attributes = table[position + DIRECTORY_ENTRY_ATTRIBUTES_OFFSET]
            name_length = table[position + DIRECTORY_ENTRY_NAME_LENGTH_OFFSET]
            raw_record_length = DIRECTORY_ENTRY_NAME_OFFSET + name_length
            record_length = (raw_record_length + 3) & ~3
            if record_length < DIRECTORY_ENTRY_NAME_OFFSET:
                _fail("XISO directory record length overflow")
            if position + record_length > len(table):
                _fail(
                    f"XISO directory at {table_start:#x}: record at +{position:#x} "
                    f"extends beyond table"
                )

            entries += 1
            is_directory = bool(attributes & DIRECTORY_ATTRIBUTE)
            context = f"XISO entry at {table_start + position:#x}"
            if raw_sector:
                corrected_sector = _correct_sector(raw_sector, correction, context)
                _validate_extent(
                    corrected_sector,
                    extent_length,
                    image_size,
                    context,
                    directory=is_directory,
                )
                if corrected_sector != raw_sector:
                    struct.pack_into(
                        "<I",
                        table,
                        position + DIRECTORY_ENTRY_SECTOR_OFFSET,
                        corrected_sector,
                    )
                    changed = True
                    patched_entries += 1
                if is_directory:
                    queue.append((corrected_sector, extent_length))
            elif is_directory:
                _fail(f"{context}: directory entry has zero sector")

            position += record_length

        if changed and write_changes:
            stream.seek(table_start)
            written = stream.write(table)
            if written != len(table):
                _fail(
                    f"short write while patching XISO directory at {table_start:#x}: "
                    f"{written}/{len(table)}"
                )

    return directories, entries, patched_entries


def _patch_xsf_header(stream: BinaryIO, image_size: int) -> None:
    marker = _read_at(stream, 0, 4, "reading XSF header")
    if marker != XSF_MAGIC:
        _fail(f"output does not start with an XSF header: {marker!r}")
    if image_size < XSF_HEADER_BYTES:
        _fail(f"image is shorter than XSF header: {image_size} bytes")
    if image_size % XISO_SECTOR_BYTES:
        _fail("XISO image length is not sector-aligned")
    stream.seek(8)
    stream.write(struct.pack("<Q", image_size - 0x400))
    sector_count = image_size // XISO_SECTOR_BYTES
    stream.seek(0x8050)
    stream.write(struct.pack("<I", sector_count))
    stream.write(struct.pack(">I", sector_count))
    stream.seek(0x7A69)
    stream.write(b"Rosette Xbox 360 media")


def _patch_directory_offsets(
    stream: BinaryIO, image_size: int, correction: int
) -> tuple[int, int, int, int, int]:
    descriptor = _read_at(stream, XISO_DESCRIPTOR_OFFSET, 32, "reading XISO descriptor")
    if descriptor[: len(XISO_MAGIC)] != XISO_MAGIC:
        _fail(
            f"XISO magic missing at output offset {XISO_DESCRIPTOR_OFFSET:#x}: "
            f"{descriptor[:len(XISO_MAGIC)]!r}"
        )
    raw_root_sector, root_size = struct.unpack_from("<II", descriptor, 20)
    if raw_root_sector == 0:
        _fail("XISO root sector is zero")
    corrected_root_sector = _correct_sector(raw_root_sector, correction, "XISO root")
    _validate_extent(
        corrected_root_sector, root_size, image_size, "XISO root", directory=True
    )
    if corrected_root_sector != raw_root_sector:
        stream.seek(XISO_DESCRIPTOR_OFFSET + 20)
        stream.write(struct.pack("<I", corrected_root_sector))
    directories, entries, patched = _walk_and_patch_directories(
        stream,
        image_size,
        corrected_root_sector,
        root_size,
        correction,
        write_changes=True,
    )
    return corrected_root_sector, root_size, directories, entries, patched


def _verify_xiso_structure(
    path: Path, *, full_hash: bool = False, progress: Optional[callable] = None
) -> ImageVerification:
    try:
        image_size = path.stat().st_size
    except OSError as exc:
        _fail(f"cannot stat XISO {path}: {exc}")
    if image_size < XISO_DESCRIPTOR_OFFSET + len(XISO_MAGIC) + 8:
        _fail(f"XISO is too short: {image_size} bytes")
    with path.open("rb") as stream:
        descriptor = _read_at(stream, XISO_DESCRIPTOR_OFFSET, 32, "reading XISO descriptor")
        if descriptor[: len(XISO_MAGIC)] != XISO_MAGIC:
            _fail(f"XISO magic missing at {XISO_DESCRIPTOR_OFFSET:#x} in {path}")
        root_sector, root_size = struct.unpack_from("<II", descriptor, 20)
        _validate_extent(root_sector, root_size, image_size, "XISO root", directory=True)
        directories, entries, _ = _walk_and_patch_directories(
            stream,
            image_size,
            root_sector,
            root_size,
            0,
            write_changes=False,
        )

    digest = _sha256_file(path, progress=progress) if full_hash else None
    return ImageVerification(
        path=path,
        size=image_size,
        xiso_offset=XISO_DESCRIPTOR_OFFSET,
        root_sector=root_sector,
        root_size=root_size,
        directories=directories,
        entries=entries,
        patched_entries=0,
        sha256=digest,
    )


def _copy_transformed_data(
    info: PackageInfo,
    output: BinaryIO,
    *,
    progress: Optional[callable] = None,
) -> tuple[dict[str, str], int]:
    """Emit the XISO body and return source member hashes and bytes written."""

    hashes: dict[str, str] = {}
    output_bytes = 0
    for index, data_file in enumerate(info.data_files):
        member_digest = hashlib.sha256()
        try:
            size = data_file.stat().st_size
        except OSError as exc:
            _fail(f"cannot stat {data_file}: {exc}")
        with data_file.open("rb") as source:
            prefix = _read_exact(
                source,
                DATA_PREFIX_BYTES,
                f"reading GOD prefix from {data_file}",
            )
            member_digest.update(prefix)
            while True:
                emitted = _read_up_to(source, OUTPUT_CHUNK_BYTES)
                if not emitted:
                    break
                member_digest.update(emitted)
                output.write(emitted)
                output_bytes += len(emitted)
                if progress is not None:
                    progress(output_bytes)
                if len(emitted) < OUTPUT_CHUNK_BYTES:
                    break
                # The final emitted block may end exactly at the end of a
                # member, in which case there is no trailing 0x1000-byte
                # stripe to consume.  GOD2ISO treats that EOF as normal; a
                # non-empty short stripe is the malformed case.
                if source.tell() == size:
                    break
                discarded = _read_up_to(source, DISCARD_CHUNK_BYTES)
                if len(discarded) != DISCARD_CHUNK_BYTES:
                    _fail(
                        f"{data_file}: short GOD stripe after output block; "
                        f"expected {DISCARD_CHUNK_BYTES}, received {len(discarded)}"
                    )
                member_digest.update(discarded)
            if source.tell() != size:
                _fail(
                    f"{data_file}: transform consumed {source.tell()} of {size} bytes; "
                    "the GOD member has an unsupported trailing layout"
                )
        hashes[f"Data{index:04d}"] = member_digest.hexdigest()
    return hashes, output_bytes


def _progress_printer(label: str, total: int) -> callable:
    next_report = 0

    def report(done: int) -> None:
        nonlocal next_report
        if done < total and done < next_report:
            return
        next_report = done + max(64 * 1024 * 1024, total // 100)
        percent = (done * 100) // total if total else 100
        print(
            f"{label}: progress bytes={done}/{total} ({percent}%)",
            file=sys.stderr,
            flush=True,
        )

    return report


def _write_manifest(
    manifest_path: Path,
    info: PackageInfo,
    output_path: Path,
    verification: ImageVerification,
    source_member_hashes: dict[str, str],
    *,
    operation: str,
    backup: Optional[Path] = None,
) -> None:
    manifest = {
        "schema": 1,
        "tool": TOOL_NAME,
        "version": TOOL_VERSION,
        "operation": operation,
        "source": {
            "header": str(info.header),
            "data_directory": str(info.data_dir),
            "signature": info.signature.decode("ascii", errors="replace"),
            "header_bytes": info.header_size,
            "header_sha256": info.header_sha256,
            "data_members": len(info.data_files),
            "data_bytes": info.data_bytes,
            "data_member_sha256": source_member_hashes,
        },
        "transform": {
            "data_prefix_bytes": DATA_PREFIX_BYTES,
            "output_chunk_bytes": OUTPUT_CHUNK_BYTES,
            "discard_chunk_bytes": DISCARD_CHUNK_BYTES,
            "generated_xsf_header": not info.has_xsf_header,
            "sector_correction": info.sector_correction,
        },
        "output": {
            "path": str(output_path),
            "bytes": verification.size,
            "sha256": verification.sha256,
            "xiso_descriptor_offset": verification.xiso_offset,
            "root_sector": verification.root_sector,
            "root_size": verification.root_size,
            "directories": verification.directories,
            "entries": verification.entries,
        },
        "backup": str(backup) if backup is not None else None,
        "verified": verification.sha256 is not None,
    }
    encoded = json.dumps(manifest, indent=2, sort_keys=True).encode("utf-8")
    if len(encoded) > MAX_MANIFEST_BYTES:
        _fail(f"media manifest exceeds {MAX_MANIFEST_BYTES} bytes")
    _atomic_write_json(manifest_path, manifest)


def build_image(
    info: PackageInfo,
    output_path: Path,
    *,
    full_hash: bool,
    operation: str,
) -> tuple[ImageVerification, dict[str, str], Path]:
    output_path = output_path.expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        _fail(
            f"output already exists: {output_path}; choose a new path or use "
            "install --replace for a recoverable replacement"
        )
    temporary = _unique_path(output_path, "partial")
    source_hashes: dict[str, str] = {}
    try:
        with temporary.open("xb") as stream:
            if info.has_xsf_header:
                # A package that already carries XSF begins with it after the
                # 0x2000 member prefix, so the transformed body supplies the
                # output header itself.
                pass
            else:
                stream.write(_make_xsf_header())
            source_hashes, body_bytes = _copy_transformed_data(
                info,
                stream,
                progress=_progress_printer("pack", info.output_size),
            )
            expected_body = info.output_size if info.has_xsf_header else info.output_size - XSF_HEADER_BYTES
            if body_bytes != expected_body:
                _fail(
                    f"transform output length mismatch: wrote {body_bytes}, "
                    f"expected {expected_body}"
                )
            stream.flush()
            os.fsync(stream.fileno())

        with temporary.open("r+b") as stream:
            image_size = temporary.stat().st_size
            if not info.has_xsf_header:
                _patch_xsf_header(stream, image_size)
            else:
                # Existing XSF packages still need their size fields checked;
                # updating them is safe and makes the result self-describing.
                _patch_xsf_header(stream, image_size)
            _patch_directory_offsets(stream, image_size, info.sector_correction)
            stream.flush()
            os.fsync(stream.fileno())

        verification = _verify_xiso_structure(
            temporary,
            full_hash=full_hash,
            progress=_progress_printer("verify", info.output_size) if full_hash else None,
        )
        if verification.size != info.output_size:
            _fail(
                f"verified output size {verification.size} differs from planned "
                f"size {info.output_size}"
            )
        os.replace(temporary, output_path)
        _fsync_directory(output_path.parent)
        return dataclasses.replace(verification, path=output_path), source_hashes, output_path
    except Exception:
        print(
            f"media conversion did not complete; partial output retained at {temporary}",
            file=sys.stderr,
        )
        raise


def _print_verification(result: ImageVerification) -> None:
    print(f"XISO:               {result.path}")
    print(f"Size:               {_format_bytes(result.size)}")
    print(f"Descriptor:         {result.xiso_offset:#x}")
    print(f"Root directory:     sector {result.root_sector:#x}, {result.root_size} bytes")
    print(f"Directory tables:   {result.directories}")
    print(f"Directory entries:   {result.entries}")
    if result.sha256 is None:
        print("Full content hash:  not requested")
    else:
        print(f"Full content hash:  sha256:{result.sha256}")
    print("Result:             PASS")


def command_inspect(args: argparse.Namespace) -> int:
    path = Path(args.path)
    # A package path can be a directory, a header, or a .data directory.  If
    # resolution fails and the path looks like an image, report image facts.
    try:
        info = inspect_package(path, hash_data=args.hash_data)
    except MediaError as package_error:
        if path.is_file() and path.suffix.lower() in {".iso", ".xiso"}:
            result = _verify_xiso_structure(path, full_hash=args.hash_data)
            _print_verification(result)
            return 0
        raise package_error
    print_package_info(info, as_json=args.json)
    return 0


def command_pack(args: argparse.Namespace) -> int:
    info = inspect_package(Path(args.path), hash_data=False)
    if args.json:
        print_package_info(info, as_json=True)
    verification, source_hashes, output = build_image(
        info,
        Path(args.output),
        full_hash=not args.skip_full_hash,
        operation=args.operation,
    )
    manifest_path = Path(f"{output}.rosette-media.json")
    _write_manifest(
        manifest_path,
        info,
        output,
        verification,
        source_hashes,
        operation=args.operation,
    )
    _print_verification(verification)
    print(f"Manifest:           {manifest_path}")
    return 0


def command_install(args: argparse.Namespace) -> int:
    info = inspect_package(Path(args.path), hash_data=False)
    target = Path(args.target).expanduser()
    if target.exists() and not args.replace:
        _fail(
            f"target already exists: {target}; install requires --replace so the "
            "old image is moved to a recoverable backup"
        )
    if target.exists() and (not target.is_file() or target.is_symlink()):
        _fail(f"install target is not a regular file: {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary_target = _unique_path(target, "installing")
    backup: Optional[Path] = None
    source_hashes: dict[str, str] = {}
    try:
        verification, source_hashes, built_path = build_image(
            info,
            temporary_target,
            full_hash=not args.skip_full_hash,
            operation="install",
        )
        if target.exists():
            backup = _unique_path(target, "backup")
            os.replace(target, backup)
            _fsync_directory(target.parent)
        try:
            os.replace(built_path, target)
            _fsync_directory(target.parent)
        except Exception:
            if backup is not None and not target.exists():
                os.replace(backup, target)
                _fsync_directory(target.parent)
            raise
    except Exception:
        print(
            f"media install did not complete; any retained staging file is near {temporary_target}",
            file=sys.stderr,
        )
        raise

    manifest_path = Path(f"{target}.rosette-media.json")
    _write_manifest(
        manifest_path,
        info,
        target,
        verification,
        source_hashes,
        operation="install",
        backup=backup,
    )
    _print_verification(verification)
    if backup is None:
        print("Backup:             none (target did not previously exist)")
    else:
        print(f"Backup:             {backup}")
    print(f"Installed:          {target}")
    print(f"Manifest:           {manifest_path}")
    return 0


def command_promote(args: argparse.Namespace) -> int:
    """Promote an already verified staging image without rebuilding it."""

    source = Path(args.path).expanduser()
    target = Path(args.target).expanduser()
    if not source.is_file() or source.is_symlink():
        _fail(f"staged image is not a regular file: {source}")
    if source.resolve() == target.resolve():
        _fail("staged image and install target are the same path")
    if target.exists() and not args.replace:
        _fail(
            f"target already exists: {target}; promote requires --replace so the "
            "old image is moved to a recoverable backup"
        )
    if target.exists() and (not target.is_file() or target.is_symlink()):
        _fail(f"install target is not a regular file: {target}")
    target.parent.mkdir(parents=True, exist_ok=True)

    verification = _verify_xiso_structure(
        source,
        full_hash=not args.skip_full_hash,
        progress=_progress_printer("promote", source.stat().st_size)
        if not args.skip_full_hash
        else None,
    )
    backup: Optional[Path] = None
    if target.exists():
        backup = _unique_path(target, "backup")
        os.replace(target, backup)
        _fsync_directory(target.parent)
    try:
        os.replace(source, target)
        _fsync_directory(target.parent)
    except Exception:
        if backup is not None and not target.exists():
            os.replace(backup, target)
            _fsync_directory(target.parent)
        raise

    verification = dataclasses.replace(verification, path=target)
    manifest_path = Path(f"{target}.rosette-media.json")
    manifest = {
        "schema": 1,
        "tool": TOOL_NAME,
        "version": TOOL_VERSION,
        "operation": "promote",
        "source_staging_path": str(source),
        "output": {
            "path": str(target),
            "bytes": verification.size,
            "sha256": verification.sha256,
            "xiso_descriptor_offset": verification.xiso_offset,
            "root_sector": verification.root_sector,
            "root_size": verification.root_size,
            "directories": verification.directories,
            "entries": verification.entries,
        },
        "backup": str(backup) if backup is not None else None,
        "verified": verification.sha256 is not None,
    }
    _atomic_write_json(manifest_path, manifest)
    _print_verification(verification)
    if backup is None:
        print("Backup:             none (target did not previously exist)")
    else:
        print(f"Backup:             {backup}")
    print(f"Installed:          {target}")
    print(f"Manifest:           {manifest_path}")
    return 0


def command_verify(args: argparse.Namespace) -> int:
    result = _verify_xiso_structure(
        Path(args.path),
        full_hash=args.full,
        progress=_progress_printer("verify", Path(args.path).stat().st_size)
        if args.full
        else None,
    )
    _print_verification(result)
    return 0


def _self_test() -> None:
    """Exercise the transform, offset repair, traversal, and full hash."""

    with tempfile.TemporaryDirectory(prefix="rosette-xbox360-media-") as temp:
        root = Path(temp)
        package_dir = root / "00004000"
        package_dir.mkdir()
        header = package_dir / "TESTPACKAGE"
        data_dir = package_dir / "TESTPACKAGE.data"
        data_dir.mkdir()

        # The package correction is 10 sectors: (22 * 2) - 34.
        header_bytes = bytearray(0xB000)
        header_bytes[0:4] = b"CON "
        header_bytes[0x391] = 0x40
        struct.pack_into("<I", header_bytes, 0x395, 22)
        header.write_bytes(header_bytes)

        # Build a small raw XISO body.  The source root is deliberately ten
        # sectors above the final location so directory and file records both
        # exercise the correction path.
        # Keep this fixture below one output block so the directory locations
        # remain easy to express while the separate transform-length checks
        # still cover the stripe rule in the real package.
        body_size = 0xB0000
        body = bytearray(body_size)
        body[: len(XISO_MAGIC)] = XISO_MAGIC
        raw_root = 0x5A
        struct.pack_into("<II", body, 20, raw_root, XISO_SECTOR_BYTES)
        output_root_offset = 0x50 * XISO_SECTOR_BYTES
        body_root_offset = output_root_offset - XSF_HEADER_BYTES
        entry = bytearray(20)
        struct.pack_into("<I", entry, 4, 0x7A)
        struct.pack_into("<I", entry, 8, XISO_SECTOR_BYTES)
        entry[12] = 0
        entry[13] = 4
        entry[14:18] = b"test"
        body[body_root_offset : body_root_offset + len(entry)] = entry
        body[
            body_root_offset + len(entry) : body_root_offset + XISO_SECTOR_BYTES
        ] = b"\xff" * (XISO_SECTOR_BYTES - len(entry))
        source = bytearray(DATA_PREFIX_BYTES) + body
        (data_dir / "Data0000").write_bytes(source)

        info = inspect_package(package_dir)
        if info.output_size != XSF_HEADER_BYTES + body_size:
            _fail("self-test: unexpected transformed size")
        output = root / "TESTPACKAGE.iso"
        verification, _, _ = build_image(
            info, output, full_hash=True, operation="self-test"
        )
        if verification.root_sector != 0x50:
            _fail("self-test: root sector correction failed")
        if verification.entries != 1:
            _fail(f"self-test: expected one directory entry, got {verification.entries}")
        if verification.sha256 is None:
            _fail("self-test: full hash was not produced")
        if _make_xsf_header()[:4] != XSF_MAGIC:
            _fail("self-test: XSF header generation failed")
        if _transform_length(DATA_PREFIX_BYTES + OUTPUT_CHUNK_BYTES, header) != OUTPUT_CHUNK_BYTES:
            _fail("self-test: exact-final-block stripe handling failed")


def command_self_test(_: argparse.Namespace) -> int:
    _self_test()
    print("rosette-xbox360-media: self-test PASS")
    return 0


def _add_full_hash_option(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--skip-full-hash",
        action="store_true",
        help="skip the final full-image SHA-256 read (diagnostic use only)",
    )


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="xbox360_media.py",
        description="Rosetta-side Xbox 360 GOD/XISO validation and recovery tool",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect_parser = subparsers.add_parser(
        "inspect", help="inspect a GOD package or XISO structure"
    )
    inspect_parser.add_argument("path")
    inspect_parser.add_argument("--json", action="store_true")
    inspect_parser.add_argument(
        "--hash-data",
        action="store_true",
        help="hash all GOD data members during inspection",
    )
    inspect_parser.set_defaults(handler=command_inspect)

    for name, help_text, operation in (
        ("pack", "rebuild an XISO from a complete GOD package", "pack"),
        ("repair", "rebuild an XISO from GOD source without fabricating data", "repair"),
    ):
        pack_parser = subparsers.add_parser(name, help=help_text)
        pack_parser.add_argument("path", help="GOD header, .data directory, or package directory")
        pack_parser.add_argument("--output", "-o", required=True)
        pack_parser.add_argument("--json", action="store_true")
        _add_full_hash_option(pack_parser)
        pack_parser.set_defaults(handler=command_pack, operation=operation)

    install_parser = subparsers.add_parser(
        "install", help="verify and atomically install a rebuilt XISO"
    )
    install_parser.add_argument("path", help="GOD header, .data directory, or package directory")
    install_parser.add_argument("--target", "-t", required=True)
    install_parser.add_argument(
        "--replace",
        action="store_true",
        help="move an existing target to a timestamped backup before install",
    )
    _add_full_hash_option(install_parser)
    install_parser.set_defaults(handler=command_install)

    promote_parser = subparsers.add_parser(
        "promote", help="verify and install an existing staged XISO without rebuilding"
    )
    promote_parser.add_argument("path", help="staged XISO image")
    promote_parser.add_argument("--target", "-t", required=True)
    promote_parser.add_argument(
        "--replace",
        action="store_true",
        help="move an existing target to a timestamped backup before install",
    )
    _add_full_hash_option(promote_parser)
    promote_parser.set_defaults(handler=command_promote)

    verify_parser = subparsers.add_parser(
        "verify", help="verify an existing XISO directory graph"
    )
    verify_parser.add_argument("path")
    verify_parser.add_argument(
        "--full",
        action="store_true",
        help="read and SHA-256 the complete image",
    )
    verify_parser.set_defaults(handler=command_verify)

    self_test_parser = subparsers.add_parser("self-test", help="run the offline tool self-test")
    self_test_parser.set_defaults(handler=command_self_test)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    parser = make_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.handler(args))
    except MediaError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    except (OSError, struct.error) as exc:
        print(f"ERROR: media operation failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
