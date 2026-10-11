#!/usr/bin/env python3
"""Read an Xbox 360 title's PowerPC code: extract, disassemble, cross-reference.

A stall that Rosette's forensics localise to "the render thread polls guest
0x8294CAA8" only becomes a diagnosis when someone reads the title code around
that address. This tool gets that code out of the user's own disc image and
makes it readable:

    extract MEDIA --out DIR [--file default.xex]
        MEDIA is an XISO image or a loose .xex. Finds the XEX on the disc,
        decrypts its basefile (retail AES key, the public constant every Xbox
        360 emulator carries) and expands "basic" compression into the image
        as the title sees it at its load address. Writes DIR/image.bin and
        DIR/summary.json (load address, entry point, sections, .pdata function
        count and every import thunk with its library and ordinal). LZX
        ("normal") compression is reported, not implemented.

    dis DIR ADDR [COUNT]          COUNT words from ADDR
    dis DIR --function ADDR       the .pdata function containing ADDR
        Disassembles with llvm-mc (PowerPC, big-endian). Branch targets are
        resolved, calls name the function they enter, and calls into import
        thunks name the kernel export (with --xenia-root or XENIA_ROOT, by
        name from Xenia's export tables; otherwise by ordinal).

    xref DIR --calls ADDR         every direct bl/b to ADDR
    xref DIR --address ADDR       every lis/addi-style reference to ADDR

    self-test                     checks the pure pieces on synthetic data

Requires Python 3, the `openssl` CLI (for AES) and llvm-mc (Homebrew llvm;
set LLVM_MC to override). Nothing from the disc is stored outside --out.
"""

from __future__ import annotations

import argparse
import bisect
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path
from typing import Optional

SECTOR = 2048
XISO_MAGIC = b"MICROSOFT*XBOX*MEDIA"
XEX2_MAGIC = 0x58455832
RETAIL_KEY = bytes.fromhex("20B185A59D28FDC340583FBB0896BF91")
DEVKIT_KEY = bytes(16)

HEADER_FILE_FORMAT = 0x000003FF
HEADER_ENTRY_POINT = 0x00010100
HEADER_IMAGE_BASE = 0x00010201
HEADER_IMPORT_LIBRARIES = 0x000103FF


class CodeError(Exception):
    pass


# ---------------------------------------------------------------- XISO


def xiso_partition_offset(stream) -> int:
    """The byte offset of the game partition: 0 for a rebuilt XISO, or one
    of the redump/XGD layouts' fixed offsets."""
    for base in (0, 0xFD90000, 0x2080000, 0x18300000):
        stream.seek(base + 0x10000)
        if stream.read(len(XISO_MAGIC)) == XISO_MAGIC:
            return base
    raise CodeError("no XDVDFS volume descriptor (MICROSOFT*XBOX*MEDIA) at any known partition offset")


def xiso_entries(data: bytes) -> list[tuple[str, int, int, int]]:
    """One directory table's entries: (name, sector, size, attributes).
    The table is a binary tree of 4-byte-aligned nodes."""
    out: list[tuple[str, int, int, int]] = []
    pending = [0]
    seen = set()
    while pending:
        node = pending.pop()
        offset = node * 4
        if node in seen or offset + 14 > len(data):
            continue
        seen.add(node)
        left, right, sector, size, attributes, name_len = struct.unpack_from("<HHIIBB", data, offset)
        if left == 0xFFFF:
            continue
        name = data[offset + 14: offset + 14 + name_len].decode("latin1")
        out.append((name, sector, size, attributes))
        if left:
            pending.append(left)
        if right:
            pending.append(right)
    return out


def xiso_find(path: Path, wanted: str) -> bytes:
    """Read the file at slash-separated `wanted` (case-insensitive)."""
    with path.open("rb") as stream:
        base = xiso_partition_offset(stream)
        stream.seek(base + 0x10000 + len(XISO_MAGIC))
        root_sector, root_size = struct.unpack("<II", stream.read(8))
        sector, size = root_sector, root_size
        parts = [part for part in wanted.replace("\\", "/").split("/") if part]
        for depth, part in enumerate(parts):
            stream.seek(base + sector * SECTOR)
            table = stream.read(size)
            match = [entry for entry in xiso_entries(table) if entry[0].lower() == part.lower()]
            if not match:
                raise CodeError(f"{wanted}: '{part}' is not on the disc")
            _, sector, size, attributes = match[0]
            if depth < len(parts) - 1 and not attributes & 0x10:
                raise CodeError(f"{wanted}: '{part}' is not a directory")
        stream.seek(base + sector * SECTOR)
        data = stream.read(size)
        if len(data) != size:
            raise CodeError(f"{wanted}: the disc ends inside the file")
        return data


# ---------------------------------------------------------------- XEX2


def openssl_aes(mode: str, key: bytes, data: bytes) -> bytes:
    if shutil.which("openssl") is None:
        raise CodeError("the openssl CLI is required for AES")
    args = ["openssl", "enc", "-d", f"-aes-128-{mode}", "-K", key.hex(), "-nopad"]
    if mode == "cbc":
        args += ["-iv", "00" * 16]
    result = subprocess.run(args, input=data, capture_output=True)
    if result.returncode != 0:
        raise CodeError(f"openssl failed: {result.stderr.decode(errors='replace').strip()}")
    return result.stdout


def xex_headers(xex: bytes) -> dict[int, int]:
    magic, _flags, _pe_offset, _reserved, _security, count = struct.unpack_from(">IIIIII", xex, 0)
    if magic != XEX2_MAGIC:
        raise CodeError("not an XEX2 file")
    return {key: value for key, value in (struct.unpack_from(">II", xex, 24 + 8 * index) for index in range(count))}


def expand_basic(decrypted: bytes, blocks: list[tuple[int, int]]) -> bytes:
    """Basic compression: (data, zero-fill) runs."""
    image = bytearray()
    cursor = 0
    for data_size, zero_size in blocks:
        image += decrypted[cursor: cursor + data_size]
        cursor += data_size
        image += bytes(zero_size)
    return bytes(image)


def xex_image(xex: bytes) -> tuple[bytes, dict]:
    headers = xex_headers(xex)
    pe_offset = struct.unpack_from(">I", xex, 8)[0]
    security = struct.unpack_from(">I", xex, 16)[0]
    image_size = struct.unpack_from(">I", xex, security + 4)[0]
    load_address = struct.unpack_from(">I", xex, security + 0x110)[0]
    session_key_encrypted = xex[security + 0x150: security + 0x160]
    info = headers.get(HEADER_FILE_FORMAT)
    if info is None:
        raise CodeError("no file-format header")
    info_size, encryption, compression = struct.unpack_from(">IHH", xex, info)
    payload = xex[pe_offset:]
    image: Optional[bytes] = None
    used_key = "none"
    keys = [("retail", RETAIL_KEY), ("devkit", DEVKIT_KEY)] if encryption == 1 else [("none", None)]
    if compression not in (0, 1):
        raise CodeError(f"compression type {compression} (LZX/delta) is not implemented; only none and basic are")
    blocks: list[tuple[int, int]]
    if compression == 1:
        blocks = [struct.unpack_from(">II", xex, info + 8 + 8 * index) for index in range((info_size - 8) // 8)]
    else:
        blocks = [(len(payload) - len(payload) % 16, 0)]
    total = sum(size for size, _ in blocks)
    for name, key in keys:
        body = payload[:total]
        if key is not None:
            session = openssl_aes("ecb", key, session_key_encrypted)
            body = openssl_aes("cbc", session, body)
        candidate = expand_basic(body, blocks)
        if candidate[:2] == b"MZ":
            image, used_key = candidate, name
            break
    if image is None:
        raise CodeError("no key produced a PE image (not MZ after decryption)")
    entry = headers.get(HEADER_ENTRY_POINT, 0)
    summary = {
        "load_address": load_address,
        "image_size": image_size,
        "entry_point": entry,
        "encryption": encryption,
        "compression": compression,
        "key": used_key,
        "sections": pe_sections(image, load_address),
        "imports": xex_imports(xex, headers, image, load_address),
    }
    return image, summary


def pe_sections(image: bytes, load_address: int) -> list[dict]:
    pe = struct.unpack_from("<I", image, 0x3C)[0]
    count, optional_size = struct.unpack_from("<H", image, pe + 6)[0], struct.unpack_from("<H", image, pe + 20)[0]
    table = pe + 24 + optional_size
    sections = []
    for index in range(count):
        entry = table + 40 * index
        name = image[entry: entry + 8].rstrip(b"\0").decode("latin1")
        virtual_size, virtual_address = struct.unpack_from("<II", image, entry + 8)
        flags = struct.unpack_from("<I", image, entry + 36)[0]
        sections.append({"name": name, "address": load_address + virtual_address, "size": virtual_size, "flags": flags})
    return sections


def xex_imports(xex: bytes, headers: dict[int, int], image: bytes, load_address: int) -> list[dict]:
    offset = headers.get(HEADER_IMPORT_LIBRARIES)
    if offset is None:
        return []
    _size, string_size, count = struct.unpack_from(">III", xex, offset)
    names = [name.decode("latin1") for name in xex[offset + 12: offset + 12 + string_size].split(b"\0") if name]
    cursor = offset + 12 + string_size
    imports = []
    for _ in range(count):
        library_size = struct.unpack_from(">I", xex, cursor)[0]
        name_index, record_count = struct.unpack_from(">HH", xex, cursor + 36)
        for index in range(record_count):
            record = struct.unpack_from(">I", xex, cursor + 40 + 4 * index)[0]
            if not load_address <= record < load_address + len(image) - 4:
                continue
            value = struct.unpack_from(">I", image, record - load_address)[0]
            imports.append({
                "address": record,
                "library": names[name_index] if name_index < len(names) else f"#{name_index}",
                "kind": "thunk" if value >> 24 == 1 else "variable",
                "ordinal": value & 0xFFFF,
            })
        cursor += library_size
    return imports


# ---------------------------------------------------------------- code


class Image:
    def __init__(self, directory: Path, xenia_root: Optional[Path] = None):
        self.bytes = (directory / "image.bin").read_bytes()
        self.summary = json.loads((directory / "summary.json").read_text())
        self.base = self.summary["load_address"]
        self.functions = self._pdata()
        self.starts = [start for start, _ in self.functions]
        self.thunks = {entry["address"]: entry for entry in self.summary["imports"] if entry["kind"] == "thunk"}
        self.export_names = load_export_names(xenia_root)

    def word(self, address: int) -> int:
        return struct.unpack_from(">I", self.bytes, address - self.base)[0]

    def section(self, name: str) -> Optional[dict]:
        return next((section for section in self.summary["sections"] if section["name"] == name), None)

    def _pdata(self) -> list[tuple[int, int]]:
        pdata = self.section(".pdata")
        if pdata is None:
            return []
        functions = []
        for offset in range(0, pdata["size"] - 7, 8):
            begin = self.word(pdata["address"] + offset)
            packed = self.word(pdata["address"] + offset + 4)
            if begin:
                functions.append((begin, begin + 4 * ((packed >> 8) & 0x3FFFFF)))
        functions.sort()
        return functions

    def function_of(self, address: int) -> Optional[tuple[int, int]]:
        index = bisect.bisect_right(self.starts, address) - 1
        if index >= 0 and self.functions[index][0] <= address < self.functions[index][1]:
            return self.functions[index]
        return None

    def thunk_name(self, address: int) -> Optional[str]:
        entry = self.thunks.get(address)
        if entry is None:
            return None
        name = self.export_names.get((entry["library"].lower(), entry["ordinal"]))
        return f"{entry['library']}!{name}" if name else f"{entry['library']}!ordinal_{entry['ordinal']:#x}"

    def text_range(self) -> tuple[int, int]:
        text = self.section(".text")
        if text is None:
            raise CodeError("no .text section")
        return text["address"], text["address"] + text["size"]


def load_export_names(xenia_root: Optional[Path]) -> dict[tuple[str, int], str]:
    names: dict[tuple[str, int], str] = {}
    if xenia_root is None:
        return names
    pattern = re.compile(r"XE_EXPORT\(\s*(\w+)\s*,\s*(0x[0-9A-Fa-f]+)\s*,\s*(\w+)")
    for module, library in (("xboxkrnl", "xboxkrnl.exe"), ("xam", "xam.xex")):
        table = xenia_root / "src" / "xenia" / "kernel" / module / f"{module}_table.inc"
        if not table.exists():
            continue
        for line in table.read_text(errors="replace").splitlines():
            match = pattern.search(line)
            if match:
                names[(library, int(match.group(2), 16))] = match.group(3)
    return names


def branch_target(address: int, word: int) -> Optional[int]:
    opcode = word >> 26
    if opcode == 18:
        offset = word & 0x03FFFFFC
        if offset & 0x02000000:
            offset -= 0x04000000
        return (offset if word & 2 else address + offset) & 0xFFFFFFFF
    if opcode == 16:
        offset = word & 0xFFFC
        if offset & 0x8000:
            offset -= 0x10000
        return (offset if word & 2 else address + offset) & 0xFFFFFFFF
    return None


def llvm_mc() -> str:
    candidates = [os.environ.get("LLVM_MC"), shutil.which("llvm-mc")]
    for prefix in ("/opt/homebrew/opt/llvm/bin", "/opt/homebrew/opt/llvm@19/bin", "/opt/homebrew/opt/llvm@18/bin", "/usr/local/opt/llvm/bin"):
        candidates.append(os.path.join(prefix, "llvm-mc"))
    for candidate in candidates:
        if candidate and os.path.exists(candidate):
            return candidate
    raise CodeError("llvm-mc not found; install Homebrew llvm or set LLVM_MC")


def disassemble(image: Image, address: int, count: int) -> list[str]:
    words = [image.word(address + 4 * index) for index in range(count)]
    text = "\n".join(" ".join(f"0x{(word >> shift) & 0xFF:02x}" for shift in (24, 16, 8, 0)) for word in words)
    result = subprocess.run([llvm_mc(), "--disassemble", "-show-encoding", "-triple=powerpc64-unknown-linux-gnu", "-mcpu=pwr7"],
                            input=text, capture_output=True, text=True)
    decoded: dict[bytes, str] = {}
    for line in result.stdout.splitlines():
        if "# encoding:" not in line:
            continue
        instruction, encoding = line.split("# encoding:")
        decoded.setdefault(bytes(int(byte, 16) for byte in encoding.strip().strip("[]").split(",")), instruction.strip())
    lines = []
    for index, word in enumerate(words):
        at = address + 4 * index
        text_form = decoded.get(word.to_bytes(4, "big"), f".long 0x{word:08x}")
        note = ""
        target = branch_target(at, word)
        if target is not None:
            note = f"  -> {target:#x}"
            if word >> 26 == 18:
                name = image.thunk_name(target)
                if name:
                    note += f" [{name}]"
                elif word & 1:
                    function = image.function_of(target)
                    if function:
                        note += f" [fn {function[0]:#x}]"
        lines.append(f"{at:#010x}: {word:08x}  {text_form}{note}")
    return lines


def direct_callers(image: Image, target: int) -> list[tuple[int, str]]:
    low, high = image.text_range()
    found = []
    for address in range(low, high - 3, 4):
        word = image.word(address)
        if word >> 26 == 18 and branch_target(address, word) == target:
            found.append((address, "bl" if word & 1 else "b"))
    return found


def address_references(image: Image, target: int) -> list[tuple[int, int]]:
    """`lis rX, hi` followed within 16 words by a D-form use of rX with lo."""
    low, high = image.text_range()
    hi, lo = ((target + 0x8000) >> 16) & 0xFFFF, target & 0xFFFF
    d_forms = {14, 32, 34, 36, 38, 40, 42, 44, 48, 50, 52, 54, 58, 62}
    found = []
    for address in range(low, high - 3, 4):
        word = image.word(address)
        if word >> 26 != 15 or (word >> 16) & 31 != 0 or word & 0xFFFF != hi:
            continue
        register = (word >> 21) & 31
        for use in range(address + 4, min(address + 64, high), 4):
            following = image.word(use)
            if following >> 26 in d_forms and (following >> 16) & 31 == register and following & 0xFFFF == lo:
                found.append((use, following >> 26))
    return found


# ---------------------------------------------------------------- CLI


def number(text: str) -> int:
    return int(text, 0)


def command_extract(args) -> int:
    media = Path(args.media)
    with media.open("rb") as stream:
        head = stream.read(4)
    xex = media.read_bytes() if head == b"XEX2" else xiso_find(media, args.file)
    image, summary = xex_image(xex)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "image.bin").write_bytes(image)
    (out / "summary.json").write_text(json.dumps(summary, indent=2))
    text = next((section for section in summary["sections"] if section["name"] == ".text"), None)
    print(f"image {len(image):#x} bytes at {summary['load_address']:#x}, entry {summary['entry_point']:#x}, "
          f"key={summary['key']}, {len(summary['imports'])} imports"
          + (f", .text {text['address']:#x}+{text['size']:#x}" if text else ""))
    return 0


def xenia_root(args) -> Optional[Path]:
    root = args.xenia_root or os.environ.get("XENIA_ROOT")
    return Path(root) if root else None


def command_dis(args) -> int:
    image = Image(Path(args.dir), xenia_root(args))
    if args.function is not None:
        function = image.function_of(args.function)
        if function is None:
            raise CodeError(f"{args.function:#x} is in no .pdata function")
        print(f"; function {function[0]:#x}..{function[1]:#x} ({(function[1] - function[0]) // 4} words)")
        lines = disassemble(image, function[0], (function[1] - function[0]) // 4)
    else:
        function = image.function_of(args.address)
        if function:
            print(f"; in function {function[0]:#x}..{function[1]:#x}")
        lines = disassemble(image, args.address, args.count)
    print("\n".join(lines))
    return 0


def command_xref(args) -> int:
    image = Image(Path(args.dir), xenia_root(args))
    if args.calls is not None:
        for address, kind in direct_callers(image, args.calls):
            function = image.function_of(address)
            print(f"{address:#x} {kind}" + (f" (in fn {function[0]:#x})" if function else ""))
    else:
        for address, opcode in address_references(image, args.address):
            function = image.function_of(address)
            print(f"{address:#x} opcode={opcode}" + (f" (in fn {function[0]:#x})" if function else ""))
    return 0


def command_self_test(_args) -> int:
    # Branch decoding: bl -0x5EC from 0x821a8ff4, and a bcl-style forward branch.
    assert branch_target(0x821A8FF4, 0x4BFFFA15) == 0x821A8A08
    assert branch_target(0x821D59CC, 0x4082FFEC) == 0x821D59B8
    assert branch_target(0x821A8500, 0x483E5AC5) == 0x8258DFC4
    # Basic compression: data then zero fill, run by run.
    assert expand_basic(b"ABCDEF", [(2, 3), (4, 1)]) == b"AB\0\0\0CDEF\0"
    # An XDVDFS table: root node "a" with a right child "b".
    table = bytearray(64)
    struct.pack_into("<HHIIBB", table, 0, 0, 4, 10, 20, 0x80, 1)
    table[14:15] = b"a"
    struct.pack_into("<HHIIBB", table, 16, 0, 0, 11, 21, 0x10, 1)
    table[30:31] = b"b"
    assert sorted(xiso_entries(bytes(table))) == [("a", 10, 20, 0x80), ("b", 11, 21, 0x10)]
    print("xbox360_code self-test: ok")
    return 0


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    extract = commands.add_parser("extract", help="decrypt a title's XEX into its load-address image")
    extract.add_argument("media")
    extract.add_argument("--out", required=True)
    extract.add_argument("--file", default="default.xex")
    extract.set_defaults(run=command_extract)
    dis = commands.add_parser("dis", help="disassemble PowerPC code from an extracted image")
    dis.add_argument("dir")
    dis.add_argument("address", type=number, nargs="?")
    dis.add_argument("count", type=number, nargs="?", default=64)
    dis.add_argument("--function", type=number)
    dis.add_argument("--xenia-root")
    dis.set_defaults(run=command_dis)
    xref = commands.add_parser("xref", help="find callers of, or references to, an address")
    xref.add_argument("dir")
    group = xref.add_mutually_exclusive_group(required=True)
    group.add_argument("--calls", type=number)
    group.add_argument("--address", type=number)
    xref.add_argument("--xenia-root")
    xref.set_defaults(run=command_xref)
    test = commands.add_parser("self-test", help="check the pure pieces on synthetic data")
    test.set_defaults(run=command_self_test)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = make_parser().parse_args(argv)
    if args.command == "dis" and args.address is None and args.function is None:
        print("dis: give an ADDR or --function ADDR", file=sys.stderr)
        return 2
    try:
        return args.run(args)
    except CodeError as error:
        print(f"xbox360_code: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
