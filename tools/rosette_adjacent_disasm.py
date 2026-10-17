#!/usr/bin/env python3
"""Read-only bounded disassembly adjacent to a guest or generated address.

The tool deliberately does not attach to a process or change an image.  It
maps PE32+, Mach-O 64, and ELF64 file addresses to their on-disk bytes, then
asks an installed LLVM/GNU disassembler for a small window.  Addresses in
Rosetta's generated-code cache are reported as runtime-owned instead: there
are no file bytes to decode, so the honest next source is an opt-in Rosetta
instruction trace.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


GENERATED_CODE_START = 0xA0000000
GENERATED_CODE_END = 0xB0000000


def llvm_tool_candidates(name: str, env_name: str) -> list[str | None]:
    candidates = [os.environ.get(env_name), shutil.which(name)]
    brew = shutil.which("brew")
    if brew:
        for formula in ("llvm@19", "llvm@18", "llvm"):
            try:
                result = subprocess.run([brew, "--prefix", formula], capture_output=True, text=True, check=False, timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                continue
            if result.returncode == 0 and result.stdout.strip():
                candidates.append(str(Path(result.stdout.strip()) / "bin" / name))
    return candidates


@dataclass(frozen=True)
class Mapping:
    image_format: str
    segment: str
    runtime_start: int
    runtime_end: int
    file_offset: int | None
    executable: bool
    readable: bool
    writable: bool
    provenance: str


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def u64(data: bytes, offset: int) -> int:
    return struct.unpack_from("<Q", data, offset)[0]


def image_format(data: bytes) -> str:
    if data.startswith(b"\x7fELF") and len(data) > 5 and data[4] == 2:
        return "elf64"
    if data.startswith(b"MZ") and len(data) > 0x40:
        pe = u32(data, 0x3C)
        if pe + 24 <= len(data) and data[pe : pe + 4] == b"PE\0\0":
            optional = pe + 24
            if optional + 2 <= len(data) and u16(data, optional) == 0x20B:
                return "pe32+"
    if len(data) >= 4 and data[:4] in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
        return "macho64"
    return "unknown"


def pe_mappings(data: bytes) -> list[Mapping]:
    pe = u32(data, 0x3C)
    section_count = u16(data, pe + 6)
    optional_size = u16(data, pe + 20)
    optional = pe + 24
    image_base = u64(data, optional + 24)
    table = optional + optional_size
    result: list[Mapping] = []
    for index in range(section_count):
        offset = table + index * 40
        name = data[offset : offset + 8].split(b"\0", 1)[0].decode("latin1", "replace")
        virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from(
            "<IIII", data, offset + 8
        )
        characteristics = u32(data, offset + 36)
        span = max(virtual_size, raw_size)
        if span == 0:
            continue
        result.append(
            Mapping(
                "pe32+",
                name or f"section-{index}",
                image_base + virtual_address,
                image_base + virtual_address + span,
                raw_offset,
                bool(characteristics & 0x20000000),
                bool(characteristics & 0x40000000),
                bool(characteristics & 0x80000000),
                "PE section",
            )
        )
    return result


def macho_mappings(data: bytes) -> list[Mapping]:
    little = data[:4] == b"\xcf\xfa\xed\xfe"
    endian = "<" if little else ">"
    read32 = lambda offset: struct.unpack_from(endian + "I", data, offset)[0]
    read64 = lambda offset: struct.unpack_from(endian + "Q", data, offset)[0]
    ncmds = read32(16)
    cursor = 32
    result: list[Mapping] = []
    for index in range(ncmds):
        if cursor + 8 > len(data):
            break
        command = read32(cursor)
        command_size = read32(cursor + 4)
        if command_size < 8 or cursor + command_size > len(data):
            break
        if command == 0x19 and command_size >= 72:
            name = data[cursor + 8 : cursor + 24].split(b"\0", 1)[0].decode("latin1", "replace")
            vmaddr = read64(cursor + 24)
            vmsize = read64(cursor + 32)
            fileoff = read64(cursor + 40)
            filesize = read64(cursor + 48)
            maxprot = read32(cursor + 56)
            initprot = read32(cursor + 60)
            if vmsize:
                result.append(
                    Mapping(
                        "macho64",
                        name or f"segment-{index}",
                        vmaddr,
                        vmaddr + vmsize,
                        fileoff,
                        bool((maxprot | initprot) & 4),
                        bool((maxprot | initprot) & 1),
                        bool((maxprot | initprot) & 2),
                        "Mach-O segment",
                    )
                )
        cursor += command_size
    return result


def elf_mappings(data: bytes) -> list[Mapping]:
    if data[5] != 1:
        return []
    endian = "<" if data[5] == 1 else ">"
    read16 = lambda offset: struct.unpack_from(endian + "H", data, offset)[0]
    read64 = lambda offset: struct.unpack_from(endian + "Q", data, offset)[0]
    phoff = read64(32)
    phentsize = read16(54)
    phnum = read16(56)
    result: list[Mapping] = []
    for index in range(phnum):
        offset = phoff + index * phentsize
        if offset + 56 > len(data):
            break
        p_type = struct.unpack_from(endian + "I", data, offset)[0]
        if p_type != 1:
            continue
        flags = struct.unpack_from(endian + "I", data, offset + 4)[0]
        fileoff = read64(offset + 8)
        vaddr = read64(offset + 16)
        filesz = read64(offset + 32)
        memsz = read64(offset + 40)
        if memsz:
            result.append(
                Mapping(
                    "elf64",
                    f"PT_LOAD[{index}]",
                    vaddr,
                    vaddr + max(memsz, filesz),
                    fileoff,
                    bool(flags & 1),
                    bool(flags & 4),
                    bool(flags & 2),
                    "ELF load segment",
                )
            )
    return result


def mappings(data: bytes) -> list[Mapping]:
    kind = image_format(data)
    if kind == "pe32+":
        return pe_mappings(data)
    if kind == "macho64":
        return macho_mappings(data)
    if kind == "elf64":
        return elf_mappings(data)
    return []


def mapping_for(data: bytes, address: int) -> Mapping | None:
    for item in mappings(data):
        if item.runtime_start <= address < item.runtime_end:
            relative = address - item.runtime_start
            file_offset = None
            if item.file_offset is not None:
                candidate = item.file_offset + relative
                if candidate < len(data):
                    file_offset = candidate
            return Mapping(
                item.image_format,
                item.segment,
                item.runtime_start,
                item.runtime_end,
                file_offset,
                item.executable,
                item.readable,
                item.writable,
                item.provenance,
            )
    return None


def generated_mapping(address: int) -> Mapping | None:
    if GENERATED_CODE_START <= address < GENERATED_CODE_END:
        return Mapping(
            "runtime",
            "Rosette generated-code cache",
            GENERATED_CODE_START,
            GENERATED_CODE_END,
            None,
            True,
            True,
            False,
            "runtime-owned generated code",
        )
    return None


def disassembler_candidates() -> list[tuple[str, str]]:
    paths = [*llvm_tool_candidates("llvm-objdump", "LLVM_OBJDUMP"), shutil.which("objdump")]
    result: list[tuple[str, str]] = []
    for path in paths:
        if path and Path(path).exists() and all(path != existing for _, existing in result):
            result.append(("llvm-objdump" if "llvm-objdump" in path else "objdump", path))
    return result


def decoded_lines(output: str) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    for line in output.splitlines():
        match = re.match(r"^\s*([0-9a-fA-F]+):\s*(.*)$", line)
        if match:
            result.append({"address": "0x" + match.group(1), "instruction": match.group(2).strip()})
    return result


def run_disassembler(path: Path, start: int, stop: int) -> tuple[str | None, str, list[dict[str, str]], str]:
    errors: list[str] = []
    for kind, tool in disassembler_candidates():
        if kind == "llvm-objdump":
            command = [
                tool,
                "-d",
                "--no-show-raw-insn",
                "--x86-asm-syntax=intel",
                f"--start-address=0x{start:x}",
                f"--stop-address=0x{stop:x}",
                str(path),
            ]
        else:
            command = [
                tool,
                "-d",
                "-Mintel",
                f"--start-address=0x{start:x}",
                f"--stop-address=0x{stop:x}",
                str(path),
            ]
        try:
            completed = subprocess.run(command, capture_output=True, text=True, check=False, timeout=15)
        except (OSError, subprocess.TimeoutExpired) as exc:
            errors.append(f"{tool}: {exc}")
            continue
        if completed.returncode == 0:
            return tool, completed.stdout, decoded_lines(completed.stdout), ""
        errors.append(f"{tool}: exit {completed.returncode}: {completed.stderr.strip()[:240]}")
    return None, "", [], "; ".join(errors) or "no disassembler found"


def nearest_symbol(path: Path, address: int) -> str | None:
    candidates = [*llvm_tool_candidates("llvm-nm", "LLVM_NM"), shutil.which("nm")]
    best: tuple[int, str] | None = None
    for tool in candidates:
        if not tool or not Path(tool).exists():
            continue
        try:
            completed = subprocess.run([tool, "-n", str(path)], capture_output=True, text=True, check=False, timeout=10)
        except (OSError, subprocess.TimeoutExpired):
            continue
        for line in completed.stdout.splitlines():
            match = re.match(r"^\s*([0-9a-fA-F]+)\s+\S\s+(.+?)\s*$", line)
            if not match:
                continue
            symbol_address = int(match.group(1), 16)
            if symbol_address <= address and (best is None or symbol_address > best[0]):
                best = (symbol_address, match.group(2))
        if best is not None:
            break
    if best is None:
        return None
    delta = address - best[0]
    return f"{best[1]}+0x{delta:x}" if delta else best[1]


def inspect(path: Path, address: int, before: int, after: int) -> dict:
    data = path.read_bytes()
    kind = image_format(data)
    mapping = mapping_for(data, address)
    generated = generated_mapping(address)
    start = max(0, address - before)
    stop = address + after
    base = {
        "image": str(path),
        "image_format": kind,
        "target": f"0x{address:x}",
        "window": {"start": f"0x{start:x}", "stop": f"0x{stop:x}", "before": before, "after": after},
        "mapping": asdict(mapping) if mapping else None,
        "nearest_symbol": nearest_symbol(path, address) if mapping else None,
        "decoder": None,
        "decoded_instructions": [],
        "bytes": None,
        "provenance": "unmapped",
        "reason": "address is not mapped by the image",
    }
    if generated is not None and mapping is None:
        base["mapping"] = asdict(generated)
        base["provenance"] = generated.provenance
        base["reason"] = (
            "generated code is runtime-owned and has no file bytes; rerun with "
            "ROSETTE_ELF_TRACE_START/END/LIMIT to capture the decoded transition"
        )
        return base
    if mapping is None:
        return base
    base["provenance"] = mapping.provenance
    base["reason"] = "mapped file address"
    if mapping.file_offset is not None:
        relative = address - mapping.runtime_start
        byte_start = mapping.file_offset - min(relative, before)
        byte_start = max(0, byte_start)
        base["bytes"] = data[byte_start : min(len(data), byte_start + before + after)].hex()
    tool, output, instructions, error = run_disassembler(path, start, stop)
    base["decoder"] = tool
    base["decoded_instructions"] = instructions
    if error:
        base["reason"] = f"mapped file address, but bounded disassembly failed: {error}"
    return base


def self_test() -> int:
    assert image_format(b"\x7fELF" + bytes([2, 1]) + bytes(58)) == "elf64"
    assert image_format(b"\xcf\xfa\xed\xfe" + bytes(60)) == "macho64"
    assert generated_mapping(GENERATED_CODE_START + 4) is not None
    assert generated_mapping(GENERATED_CODE_END) is None
    assert decoded_lines("  401000:\tmov eax, ebx\n") == [
        {"address": "0x401000", "instruction": "mov eax, ebx"}
    ]
    print("adjacent disassembly: self-test PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path)
    parser.add_argument("--address", required=False, help="runtime address, for example 0x140001000")
    parser.add_argument("--before", type=lambda value: int(value, 0), default=32)
    parser.add_argument("--after", type=lambda value: int(value, 0), default=96)
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.image is None or args.address is None:
        parser.error("--image and --address are required unless --self-test is used")
    address = int(args.address, 0)
    result = inspect(args.image, address, args.before, args.after)
    if args.format == "json":
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(f"image: {result['image']}")
        print(f"format: {result['image_format']}")
        print(f"target: {result['target']}")
        print(f"provenance: {result['provenance']}")
        print(f"mapping: {result['mapping']}")
        print(f"nearest_symbol: {result['nearest_symbol'] or 'unresolved'}")
        print(f"reason: {result['reason']}")
        print(f"decoder: {result['decoder'] or 'none'}")
        for item in result["decoded_instructions"]:
            print(f"  {item['address']}: {item['instruction']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
