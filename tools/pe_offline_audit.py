#!/usr/bin/env python3
"""Read-only static PE and Visual C++ project compatibility audit.

This tool never loads or executes an input image. It inventories PE headers,
sections, static imports, project configurations, and Rosette's currently
registered PE32 import-thunk names. It is an intake/preflight aid, not a proof
that an executable's instructions or runtime behavior are supported.

Usage:
    python3 tools/pe_offline_audit.py /path/to/project
    make pe-offline-audit AUDIT_PATH=/path/to/project
    python3 tools/pe_offline_audit.py --disassemble /path/to/output /path/to/project

The optional disassembly uses llvm-objdump, if installed, and writes text
disassemblies only to the requested output directory.
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import shutil
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass


PE32_I386 = 0x014C
PE32_PLUS_AMD64 = 0x8664
PE32_MAGIC = 0x010B
PE32_PLUS_MAGIC = 0x020B
SUBSYSTEMS = {2: "Windows GUI", 3: "Windows console"}
PROJECT_TYPES = {1: "application", 2: "dynamic library", 4: "static library"}
MACHINES = {1: "x86", 17: "x64"}
EXPECTED_MAZE_SHA256 = "78852d8d5404fdbdcf9d785c9c0393c85de64efed4bd66cca02050bbf3608eaf"
REMOTE_PROCESS_APIS = {
    "CreateProcessA", "CreateProcessW", "VirtualAllocEx", "WriteProcessMemory",
    "CreateRemoteThread", "WaitForSingleObject", "GetExitCodeThread", "ResumeThread",
}
LEGACY_GRAPHICS_DLLS = {"opengl32.dll", "glu32.dll"}
SKIP_DIRS = {".git", ".vs", "debug", "ipch"}
IMAGE_SUFFIXES = {".exe", ".dll", ".scr"}
PROJECT_SUFFIXES = {".vcproj", ".vcxproj"}


class AuditError(Exception):
    pass


def u16(data: bytes, offset: int) -> int:
    if offset < 0 or offset + 2 > len(data):
        raise AuditError(f"truncated 16-bit field at file offset 0x{offset:X}")
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    if offset < 0 or offset + 4 > len(data):
        raise AuditError(f"truncated 32-bit field at file offset 0x{offset:X}")
    return struct.unpack_from("<I", data, offset)[0]


@dataclass(frozen=True)
class Section:
    name: str
    virtual_address: int
    virtual_size: int
    raw_size: int
    raw_offset: int


@dataclass(frozen=True)
class Import:
    library: str
    name: str
    ordinal: int | None = None


@dataclass
class PEImage:
    path: pathlib.Path
    data: bytes
    machine: int
    magic: int
    entry_rva: int
    image_base: int
    subsystem: int
    major_os: int
    minor_os: int
    major_subsystem: int
    minor_subsystem: int
    size_of_image: int
    size_of_headers: int
    characteristics: int
    sections: list[Section]
    import_directory: tuple[int, int]
    delay_import_directory: tuple[int, int]
    clr_directory: tuple[int, int]

    @classmethod
    def parse(cls, path: pathlib.Path) -> "PEImage":
        data = path.read_bytes()
        if len(data) < 0x40 or u16(data, 0) != 0x5A4D:
            raise AuditError("missing DOS MZ header")
        pe = u32(data, 0x3C)
        if pe + 24 > len(data) or u32(data, pe) != 0x00004550:
            raise AuditError("missing or truncated PE signature / COFF header")
        coff = pe + 4
        machine = u16(data, coff)
        section_count = u16(data, coff + 2)
        optional_size = u16(data, coff + 16)
        characteristics = u16(data, coff + 18)
        optional = coff + 20
        if optional + optional_size > len(data) or optional_size < 2:
            raise AuditError("truncated optional header")
        magic = u16(data, optional)
        if magic == PE32_MAGIC:
            min_size, dir_offset, image_base_offset, ptr_size = 96, 96, 28, 4
        elif magic == PE32_PLUS_MAGIC:
            min_size, dir_offset, image_base_offset, ptr_size = 112, 112, 24, 8
        else:
            raise AuditError(f"unsupported optional-header magic 0x{magic:04X}")
        if optional_size < min_size:
            raise AuditError("optional header is shorter than the PE data-directory prefix")
        if (machine, magic) not in {(PE32_I386, PE32_MAGIC), (PE32_PLUS_AMD64, PE32_PLUS_MAGIC)}:
            raise AuditError(f"machine 0x{machine:04X} and optional-header magic 0x{magic:04X} disagree or are unsupported")

        entry_rva = u32(data, optional + 16)
        image_base = u32(data, optional + image_base_offset) if ptr_size == 4 else struct.unpack_from("<Q", data, optional + image_base_offset)[0]
        major_os, minor_os = u16(data, optional + 40), u16(data, optional + 42)
        major_subsystem, minor_subsystem = u16(data, optional + 48), u16(data, optional + 50)
        size_of_image, size_of_headers = u32(data, optional + 56), u32(data, optional + 60)
        subsystem = u16(data, optional + 68)
        directory_count = u32(data, optional + (92 if ptr_size == 4 else 108))
        available_dirs = min(directory_count, max(0, (optional_size - dir_offset) // 8))

        def directory(index: int) -> tuple[int, int]:
            if index >= available_dirs:
                return (0, 0)
            return struct.unpack_from("<II", data, optional + dir_offset + index * 8)

        section_table = optional + optional_size
        if section_table + section_count * 40 > len(data):
            raise AuditError("truncated PE section table")
        sections: list[Section] = []
        for index in range(section_count):
            off = section_table + index * 40
            raw_name = data[off:off + 8].split(b"\0", 1)[0]
            name = raw_name.decode("ascii", errors="replace")
            virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from("<IIII", data, off + 8)
            if raw_size and (raw_offset > len(data) or raw_size > len(data) - raw_offset):
                raise AuditError(f"section {name!r} points beyond the file")
            sections.append(Section(name, virtual_address, virtual_size, raw_size, raw_offset))

        return cls(
            path=path,
            data=data,
            machine=machine,
            magic=magic,
            entry_rva=entry_rva,
            image_base=image_base,
            subsystem=subsystem,
            major_os=major_os,
            minor_os=minor_os,
            major_subsystem=major_subsystem,
            minor_subsystem=minor_subsystem,
            size_of_image=size_of_image,
            size_of_headers=size_of_headers,
            characteristics=characteristics,
            sections=sections,
            import_directory=directory(1),
            delay_import_directory=directory(13),
            clr_directory=directory(14),
        )

    @property
    def bitness(self) -> int:
        return 32 if self.magic == PE32_MAGIC else 64

    @property
    def machine_name(self) -> str:
        return {PE32_I386: "i386", PE32_PLUS_AMD64: "amd64"}.get(self.machine, f"unknown-0x{self.machine:04X}")

    @property
    def is_dll(self) -> bool:
        return bool(self.characteristics & 0x2000)

    def rva_to_offset(self, rva: int, size: int = 1) -> int:
        if rva < self.size_of_headers and rva + size <= min(self.size_of_headers, len(self.data)):
            return rva
        for section in self.sections:
            delta = rva - section.virtual_address
            if delta >= 0 and delta + size <= section.raw_size:
                offset = section.raw_offset + delta
                if offset + size <= len(self.data):
                    return offset
        raise AuditError(f"RVA 0x{rva:X} (size 0x{size:X}) is not file-backed")

    def c_string_at_rva(self, rva: int) -> str:
        offset = self.rva_to_offset(rva)
        end = self.data.find(b"\0", offset, min(len(self.data), offset + 4096))
        if end < 0:
            raise AuditError(f"unterminated string at RVA 0x{rva:X}")
        return self.data[offset:end].decode("ascii", errors="replace")

    def imports(self) -> list[Import]:
        rva, size = self.import_directory
        if not rva or not size:
            return []
        result: list[Import] = []
        pointer_size = self.bitness // 8
        descriptor_limit = min(size // 20, 10000)
        for descriptor_index in range(descriptor_limit):
            descriptor_rva = rva + descriptor_index * 20
            off = self.rva_to_offset(descriptor_rva, 20)
            original_thunk, _, _, name_rva, first_thunk = struct.unpack_from("<IIIII", self.data, off)
            if not any((original_thunk, name_rva, first_thunk)):
                return result
            if not name_rva or not first_thunk:
                raise AuditError(f"invalid import descriptor at RVA 0x{descriptor_rva:X}")
            library = self.c_string_at_rva(name_rva)
            thunk_rva = original_thunk or first_thunk
            ordinal_flag = 1 << (pointer_size * 8 - 1)
            for thunk_index in range(65536):
                item_rva = thunk_rva + thunk_index * pointer_size
                item_off = self.rva_to_offset(item_rva, pointer_size)
                thunk = int.from_bytes(self.data[item_off:item_off + pointer_size], "little")
                if thunk == 0:
                    break
                if thunk & ordinal_flag:
                    result.append(Import(library, f"#{thunk & 0xFFFF}", thunk & 0xFFFF))
                else:
                    hint_name_rva = thunk & (0x7FFFFFFF if pointer_size == 4 else 0x7FFFFFFFFFFFFFFF)
                    name_off = self.rva_to_offset(hint_name_rva, 3)
                    name_start = name_off + 2
                    name_end = self.data.find(b"\0", name_start, min(len(self.data), name_start + 4096))
                    if name_end < 0:
                        raise AuditError(f"unterminated imported symbol at RVA 0x{hint_name_rva:X}")
                    function = self.data[name_start:name_end].decode("ascii", errors="replace")
                    result.append(Import(library, function))
            else:
                raise AuditError(f"import thunk table for {library} exceeded the safety bound")
        raise AuditError("import descriptor table exceeded its declared size or lacked a terminator")


@dataclass(frozen=True)
class ProjectConfiguration:
    name: str
    kind: str
    platform: str
    runtime_library: str | None
    machine: str | None
    subsystem: str | None


def read_project(path: pathlib.Path) -> tuple[str, str, list[str], list[ProjectConfiguration]]:
    root = ET.parse(path).getroot()
    version = root.attrib.get("Version", "unknown")
    name = root.attrib.get("Name", path.stem)
    platforms = sorted({node.attrib.get("Name", "") for node in root.findall(".//Platforms/Platform") if node.attrib.get("Name")})
    configs: list[ProjectConfiguration] = []
    for node in root.findall(".//Configurations/Configuration"):
        full_name = node.attrib.get("Name", "unnamed")
        config_name, _, platform = full_name.partition("|")
        try:
            kind_value = int(node.attrib.get("ConfigurationType", "0"))
        except ValueError:
            kind_value = 0
        compiler = next((tool for tool in node.findall("Tool") if tool.attrib.get("Name") == "VCCLCompilerTool"), None)
        linker = next((tool for tool in node.findall("Tool") if tool.attrib.get("Name") == "VCLinkerTool"), None)
        runtime = compiler.attrib.get("RuntimeLibrary") if compiler is not None else None
        machine_value = linker.attrib.get("TargetMachine") if linker is not None else None
        subsystem_value = linker.attrib.get("SubSystem") if linker is not None else None
        configs.append(ProjectConfiguration(
            config_name,
            PROJECT_TYPES.get(kind_value, f"unknown({kind_value})"),
            platform or "unspecified",
            {"0": "static CRT", "1": "single-threaded debug CRT", "2": "DLL CRT", "3": "debug DLL CRT"}.get(runtime, runtime),
            MACHINES.get(int(machine_value), f"unknown({machine_value})") if machine_value and machine_value.isdigit() else machine_value,
            {"1": "console", "2": "GUI"}.get(subsystem_value, subsystem_value),
        ))
    return name, version, platforms, configs


def registered_x86_thunks(repo_root: pathlib.Path) -> set[str]:
    """Extract the actual PE32 runner registrations instead of duplicating an API list."""
    names: set[str] = set()
    for relative in ("src/x86-ASM/win32_thunks.zig", "src/x86-ASM/mscoree_thunks.zig"):
        source = repo_root / relative
        try:
            text = source.read_text(encoding="utf-8")
        except OSError:
            continue
        names.update(re.findall(r'map\.put\("([^"\n]+)"', text))
    return names


def canonical_thunk_name(name: str) -> str:
    value = name.removeprefix("_")
    return re.sub(r"@\d+$", "", value)


def classify_library(name: str) -> str:
    folded = name.lower()
    if folded in LEGACY_GRAPHICS_DLLS:
        return "legacy OpenGL/GLU (known name; Rosette has no backend)"
    if folded in {"kernel32.dll", "user32.dll", "advapi32.dll", "gdi32.dll", "comdlg32.dll", "comctl32.dll"}:
        return "Win32 system library (name known; export/ABI implementation still needs validation)"
    return "unclassified by this audit"


def discover(root: pathlib.Path) -> tuple[list[pathlib.Path], list[pathlib.Path]]:
    images: list[pathlib.Path] = []
    projects: list[pathlib.Path] = []
    if root.is_file():
        return ([root] if root.suffix.lower() in IMAGE_SUFFIXES else [], [root] if root.suffix.lower() in PROJECT_SUFFIXES else [])
    for path in root.rglob("*"):
        if any(part.lower() in SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        if not path.is_file():
            continue
        if path.suffix.lower() in IMAGE_SUFFIXES:
            images.append(path)
        elif path.suffix.lower() in PROJECT_SUFFIXES:
            projects.append(path)
    return sorted(images), sorted(projects)


def disassemble(image: PEImage, output_dir: pathlib.Path) -> str | None:
    objdump = shutil.which("llvm-objdump")
    if not objdump:
        return "llvm-objdump unavailable; skipped disassembly"
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / f"{image.path.name}.disassembly.txt"
    try:
        result = subprocess.run(
            [objdump, "-d", "--no-show-raw-insn", str(image.path)],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=90,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f"disassembly unavailable: {exc}"
    output.write_text(result.stdout, encoding="utf-8")
    if result.returncode:
        return f"llvm-objdump exit={result.returncode}; partial output: {output}"
    return f"wrote static disassembly: {output}"


def audit(root: pathlib.Path, disassembly_dir: pathlib.Path | None) -> int:
    repo_root = pathlib.Path(__file__).resolve().parents[1]
    thunk_names = registered_x86_thunks(repo_root)
    normalized_thunks = {canonical_thunk_name(name).casefold() for name in thunk_names}
    images, projects = discover(root)
    if not images and not projects:
        print(f"error: no PE image or Visual C++ project found under {root}", file=sys.stderr)
        return 2

    print("ROSETTE OFFLINE PE COMPATIBILITY AUDIT")
    print(f"input: {root}")
    print("execution: none (inputs were read as files only)")
    print("scope: PE headers, file-backed sections, static import tables, and Visual C++ project settings")
    print("instruction/runtime guarantee: not established by metadata inspection")
    print()

    for project in projects:
        print(f"PROJECT {project}")
        try:
            name, version, platforms, configs = read_project(project)
            print(f"  name={name} format={version} platforms={', '.join(platforms) or 'none'}")
            for config in configs:
                print(f"  config={config.name}|{config.platform} kind={config.kind} machine={config.machine or 'unspecified'} subsystem={config.subsystem or 'unspecified'} CRT={config.runtime_library or 'unspecified'}")
        except (ET.ParseError, OSError, ValueError) as exc:
            print(f"  parse_error={exc}")
        print()

    launch_blockers: list[str] = []
    for path in images:
        try:
            image = PEImage.parse(path)
            imports = image.imports()
        except (OSError, AuditError) as exc:
            print(f"IMAGE {path}\n  parse_error={exc}\n")
            launch_blockers.append(f"could not statically parse {path.name}")
            continue
        image_kind = "DLL" if image.is_dll else path.suffix.lstrip(".").upper() or "PE image"
        print(f"IMAGE {path} ({image_kind})")
        print(f"  format=PE{image.bitness} machine={image.machine_name} entry_rva=0x{image.entry_rva:08X} image_base=0x{image.image_base:X}")
        print(f"  subsystem={SUBSYSTEMS.get(image.subsystem, f'unknown({image.subsystem})')} Windows-version={image.major_os}.{image.minor_os} subsystem-version={image.major_subsystem}.{image.minor_subsystem}")
        print(f"  image_bytes={len(image.data)} mapped_image_bytes={image.size_of_image} sections={len(image.sections)} imports={len(imports)} delay_imports={'present (not decoded)' if any(image.delay_import_directory) else 'none'} CLR={'present' if any(image.clr_directory) else 'none'}")
        for section in image.sections:
            print(f"  section={section.name or '<unnamed>'} RVA=0x{section.virtual_address:08X} virtual=0x{section.virtual_size:X} raw=0x{section.raw_size:X}")

        grouped: dict[str, list[Import]] = {}
        for item in imports:
            grouped.setdefault(item.library, []).append(item)
        for library in sorted(grouped, key=str.casefold):
            entries = grouped[library]
            classification = classify_library(library)
            print(f"  import-library={library} symbols={len(entries)} classification={classification}")
            for item in entries:
                print(f"    {item.name}")

        if image.bitness == 32:
            print("  execution-route=legacy PE32 raw x86 interpreter (not the bounded PE64 loader/preflight)")
            supported = [imp for imp in imports if canonical_thunk_name(imp.name).casefold() in normalized_thunks]
            missing = [imp for imp in imports if canonical_thunk_name(imp.name).casefold() not in normalized_thunks]
            print(f"  PE32-registered-thunk-name-matches={len(supported)}/{len(imports)} (registration-name comparison only; not an ABI/runtime proof)")
            for item in missing:
                print(f"  PE32-import-without-registered-thunk={item.library}!{item.name}")
            if missing:
                launch_blockers.append(f"{path.name}: {len(missing)} imported names have no registration in the current PE32 thunk tables")
            launch_blockers.append(f"{path.name}: PE32 static import audit does not prove instruction coverage or loader semantics")

        imported_libraries = {item.library.lower() for item in imports}
        if imported_libraries & LEGACY_GRAPHICS_DLLS:
            graphics = sorted(imported_libraries & LEGACY_GRAPHICS_DLLS)
            print(f"  legacy-graphics-backend=missing ({', '.join(graphics)}; OpenGL32 is not interchangeable with the Vulkan forwarder)")
            launch_blockers.append(f"{path.name}: requires legacy OpenGL/GLU runtime backends")
        imported_functions = {item.name for item in imports}
        remote_apis = sorted(imported_functions & REMOTE_PROCESS_APIS)
        if remote_apis:
            print(f"  remote-process-operations={', '.join(remote_apis)}")
            print("  remote-process-backend=not established (needs process, address-space, thread, and DLL-load semantics)")
            launch_blockers.append(f"{path.name}: requires remote-process/DLL-injection semantics")

        if path.name.lower() == "ssmaze.scr":
            digest = hashlib.sha256(image.data).hexdigest()
            print(f"  SHA256={digest}")
            if digest == EXPECTED_MAZE_SHA256:
                print("  hardcoded-patch-target-hash=matches upstream README")
            else:
                print("  hardcoded-patch-target-hash=does-not-match upstream README; the patch DLL may target different offsets")
                launch_blockers.append("ssmaze.scr hash differs from the exact image expected by the patch DLL")
        if disassembly_dir is not None:
            print(f"  {disassemble(image, disassembly_dir)}")
        print()

    image_names = {path.name.lower() for path in images}
    required_set = {"playable3dmazeloader.exe", "playable3dmaze.dll", "ssmaze.scr"}
    if required_set <= image_names:
        print("BUNDLE CHECK: loader, patch DLL, and original screen saver are all present.")
    elif "playable3dmazeloader.exe" in image_names or "ssmaze.scr" in image_names:
        absent = sorted(required_set - image_names)
        print(f"BUNDLE CHECK: incomplete; missing {', '.join(absent)}")
        launch_blockers.append("the loader, patch DLL, and screen saver are not all present in the audited tree")
    else:
        print("BUNDLE CHECK: no Playable3DMaze-specific bundle names detected.")

    print()
    if launch_blockers:
        print(f"READINESS: BLOCKED / NOT PROVEN ({len(launch_blockers)} findings)")
        for blocker in dict.fromkeys(launch_blockers):
            print(f"  - {blocker}")
        print("This is an offline static result; it does not attempt to run or load any input image.")
        return 1
    print("READINESS: no known blockers found by this limited static audit; runtime support is still not proven.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disassemble", metavar="OUTPUT_DIR", type=pathlib.Path, help="write llvm-objdump disassemblies here when llvm-objdump is installed")
    parser.add_argument("path", type=pathlib.Path, help="a PE image, VC project, or directory to audit")
    args = parser.parse_args()
    if not args.path.exists():
        parser.error(f"input does not exist: {args.path}")
    return audit(args.path, args.disassemble)


if __name__ == "__main__":
    raise SystemExit(main())
