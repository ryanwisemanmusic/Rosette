"""Bounded XDVDFS and Halo 3 retail metadata readers. Never extract game data.

Layout facts are documented against pinned primary sources in the tool guide.
Tag instances, not inferred texture payloads or shader permutations, form the
inventory. Unknown map builds and malformed tables stay explicitly unparsed.
"""
from __future__ import annotations

from collections import Counter, deque
import hashlib
import json
from pathlib import Path
import struct

from . import POLICY

MAX_TABLE = 16 << 20
MAX_ENTRIES = 1_000_000
MAX_TAGS = 100_000
MAGIC = b"MICROSOFT*XBOX*MEDIA"


class InventoryError(ValueError):
    pass


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_at(stream, offset: int, length: int, limit: int) -> bytes:
    if offset < 0 or length < 0 or length > MAX_TABLE or offset + length > limit:
        raise InventoryError(f"Invalid bounded read: offset={offset}, bytes={length}, limit={limit}")
    stream.seek(offset)
    data = stream.read(length)
    if len(data) != length:
        raise InventoryError(f"Truncated read at {offset:#x}: {len(data)}/{length}")
    return data


def directory_entries(data: bytes):
    """Walk the reachable tree; reject cycles, overlapping nodes and bad names."""
    pending, seen, intervals, result = [0], set(), [], []
    while pending:
        offset = pending.pop() * 4
        if offset in seen:
            raise InventoryError("Cyclic or multiply linked XDVDFS directory node")
        seen.add(offset)
        if offset + 4 > len(data):
            raise InventoryError("Directory link is outside the table")
        if data[offset:offset + 4] == b"\xff" * 4:
            continue
        if offset + 14 > len(data):
            raise InventoryError("Truncated directory node")
        left, right, sector, length, attr, n = struct.unpack_from("<HHIIBB", data, offset)
        end = (offset + 14 + n + 3) & ~3
        if n == 0 or end > len(data) or offset // 2048 != (end - 1) // 2048:
            raise InventoryError("Malformed or sector-straddling directory name")
        name = data[offset + 14:offset + 14 + n].decode("latin1")
        if name in (".", "..") or any(c in name for c in ("/", "\\", "\0")):
            raise InventoryError("Unsafe directory component")
        intervals.append((offset, end))
        result.append((name, sector, length, attr))
        if left:
            pending.append(left)
        if right:
            pending.append(right)
        if len(result) > MAX_ENTRIES:
            raise InventoryError("Directory entry limit exceeded")
    ordered = sorted(intervals)
    if any(a[1] > b[0] for a, b in zip(ordered, ordered[1:])):
        raise InventoryError("Overlapping directory records")
    names = [item[0].casefold() for item in result]
    if len(names) != len(set(names)):
        raise InventoryError("Ambiguous duplicate directory names")
    return result


def xiso_files(stream, size: int):
    base = None
    for candidate in (0, 0xFD90000, 0x2080000, 0x18300000):
        if candidate + 0x10000 + 36 <= size and read_at(stream, candidate + 0x10000, 20, size) == MAGIC:
            base = candidate
            break
    if base is None:
        raise InventoryError("No XDVDFS descriptor at a known game partition offset")
    root, root_size = struct.unpack("<II", read_at(stream, base + 0x10014, 8, size))
    pending = deque([("", root, root_size)])
    seen, files = set(), []
    while pending:
        parent, sector, length = pending.popleft()
        if sector == 0 or length == 0 or (sector, length) in seen:
            raise InventoryError("Empty, cyclic or aliased XDVDFS directory extent")
        seen.add((sector, length))
        table = read_at(stream, base + sector * 2048, length, size)
        for name, sec, n, attr in directory_entries(table):
            path = f"{parent}/{name}".lstrip("/")
            offset = base + sec * 2048
            if offset + n > size or (n and sec == 0):
                raise InventoryError(f"File extent outside ISO: {path}")
            if attr & 16:
                pending.append((path, sec, n))
            else:
                files.append({"path": path, "offset": offset, "size": n})
            if len(files) + len(pending) + len(seen) > MAX_ENTRIES:
                raise InventoryError("ISO inventory limit exceeded")
    return base, sorted(files, key=lambda f: f["path"].casefold())


def category(code: str, parents: tuple[str, str]) -> str | None:
    if code == "bitm":
        return "texture_tags"
    if code in ("pixl", "vtsh", "glps", "glvs"):
        return "shader_tags"
    if code in ("rmdf", "rmt2", "rmop", "rm  ") or "rm  " in parents:
        return "material_tags"
    if code in ("mode", "sbsp", "decs", "pmdf"):
        return "geometry_tags"
    if code in ("ligh", "lens", "sLdT", "ltmp", "skya", "fog "):
        return "lighting_tags"
    if code in ("effe", "prt3", "beam", "cntl", "cfxs", "sefc"):
        return "effect_tags"
    return None


def halo3_map(stream, entry: dict, iso_size: int, iso_sha: str):
    start, length = entry["offset"], entry["size"]

    def read(offset, n):
        if offset < 0 or offset + n > length:
            raise InventoryError("Cache pointer outside this map extent")
        return read_at(stream, start + offset, n, iso_size)

    header = read(0, 12288)
    if header[:4] != b"head":
        raise InventoryError("Unknown cache header signature")
    version = struct.unpack_from(">I", header, 4)[0]
    build = header[284:316].split(b"\0")[0].decode("ascii", "replace")
    if version != 11 or build != "11855.07.08.20.2317.halo3_ship":
        raise InventoryError(f"Unsupported cache build {version}: {build}")
    index_pointer = struct.unpack_from(">I", header, 16)[0]
    info = {"path": entry["path"], "build": build, "size": length, "status": "parsed", "tags": 0}
    if index_pointer == 0:
        info["status"] = "resource_container"
        info["note"] = "Shared resource cache; payloads are not decoded by the tag inventory"
        return info, []
    virtual_base = struct.unpack_from(">I", header, 744)[0]
    section2 = struct.unpack_from(">I", header, 1164)[0]
    section2_adjust = struct.unpack_from(">i", header, 1140)[0]
    tag_magic = virtual_base - ((section2 + section2_adjust) & 0xffffffff)
    header_adjust = struct.unpack_from(">i", header, 1132)[0]
    class_count, class_pointer, count, tag_pointer = struct.unpack_from(">4I", read(index_pointer - tag_magic, 16))
    if not 0 < class_count <= 512 or not 0 < count <= MAX_TAGS:
        raise InventoryError("Implausible Halo tag/class count")
    classes_data = read(class_pointer - tag_magic, class_count * 16)
    classes = [tuple(classes_data[i:i + 12][j:j + 4].decode("latin1") for j in (0, 4, 8))
               for i in range(0, len(classes_data), 16)]
    tags = read(tag_pointer - tag_magic, count * 8)
    name_count, name_pointer, name_size, name_index = struct.unpack_from(">4I", header, 692)
    if name_count != count:
        raise InventoryError("Halo tag/name table counts differ")
    names = read((name_pointer + header_adjust) & 0xffffffff, name_size)
    indices = struct.unpack(f">{count}i", read((name_index + header_adjust) & 0xffffffff, count * 4))
    assets, counts = [], Counter()
    for index in range(count):
        cls, _salt, pointer = struct.unpack_from(">hHI", tags, index * 8)
        if cls == -1:
            continue
        if cls < 0 or cls >= class_count:
            raise InventoryError("Halo class index out of range")
        code, parent, ancestor = classes[cls]
        counts[code] += 1
        group = category(code, (parent, ancestor))
        if group is None:
            continue
        name_offset = indices[index]
        if name_offset == -1:
            name = f"unnamed_{index}"
        elif 0 <= name_offset < len(names):
            end = names.find(b"\0", name_offset)
            if end < 0:
                raise InventoryError("Unterminated Halo tag name")
            name = names[name_offset:end].decode("utf8", "replace")
        else:
            raise InventoryError("Halo tag name index outside table")
        asset = {"id": f"{iso_sha}:{entry['path']}:{index:04x}:{code}", "map": entry["path"],
                 "tag_index": index, "class": code, "name": name, "category": group,
                 "metadata_offset": pointer - tag_magic, "metadata_status": "indexed",
                 "status": "unknown", "proofs": []}
        if code == "bitm":
            try:
                root = pointer - tag_magic

                def tagblock(offset, count_limit, element_size, label):
                    count, block_pointer = struct.unpack(">II", read(root + offset, 8))
                    if count > count_limit:
                        raise InventoryError(f"Implausible bitmap {label} count")
                    if not count:
                        return []
                    if not block_pointer:
                        raise InventoryError(f"Null bitmap {label} pointer with nonzero count")
                    block_offset = block_pointer - tag_magic
                    raw = read(block_offset, count * element_size)
                    return [raw[n * element_size:(n + 1) * element_size] for n in range(count)]

                image_blocks = tagblock(0x60, 8192, 48, "subimage")
                subimages = []
                for n, block in enumerate(image_blocks):
                    width, height = struct.unpack_from(">HH", block, 4)
                    texture_type, texture_format = struct.unpack_from(">HH", block, 10)
                    texture_flags = struct.unpack_from(">H", block, 14)[0]
                    pixel_offset, pixel_size, high_res_offset, high_res_size, hardware_format = struct.unpack_from(
                        ">5i", block, 24)
                    xbox_flags = block[9]
                    interop_index, pair_index = struct.unpack_from(">2b", block, 22)
                    subimages.append({
                        "index": n, "width": width, "height": height, "depth": block[8],
                        "xbox_flags": xbox_flags, "type": texture_type, "format": texture_format,
                        "format_flags": texture_flags,
                        "registration_point": list(struct.unpack_from(">2h", block, 16)),
                        "mip_count": block[20], "curve": block[21],
                        "interleaved_interop_index": interop_index,
                        "interleaved_texture_index": pair_index,
                        "pixel_data_offset": pixel_offset, "pixel_data_size": pixel_size,
                        "high_res_pixels_offset": high_res_offset, "high_res_pixels_size": high_res_size,
                        "hardware_format": hardware_format,
                        "resource_reference": None,
                        "payload_status": "unresolved_resource_pages",
                    })
                asset["subimages"] = subimages
                resource_errors = []
                for block_offset, label, key in ((0x8c, "hardware texture", "hardware_textures"),
                                                  (0x98, "interleaved hardware texture", "interleaved_hardware_textures")):
                    try:
                        blocks = tagblock(block_offset, 8192, 8, label)
                        refs = [{"slot": n, "datum_raw": struct.unpack_from(">I", block)[0],
                                 "padding": struct.unpack_from(">I", block, 4)[0]}
                                for n, block in enumerate(blocks)]
                        asset[key] = refs
                    except InventoryError as error:
                        resource_errors.append(str(error))
                for image in subimages:
                    interleaved = bool(image["xbox_flags"] & (1 << 6))
                    reference_slot = image["interleaved_interop_index"] if interleaved else image["index"]
                    key = "interleaved_hardware_textures" if interleaved else "hardware_textures"
                    references = asset.get(key, [])
                    if 0 <= reference_slot < len(references):
                        image["resource_reference"] = {"kind": "interleaved" if interleaved else "ordinary",
                                                        "slot": reference_slot,
                                                        "datum_raw": references[reference_slot]["datum_raw"]}
                        image["resource_reference_status"] = "indexed"
                    else:
                        image["resource_reference_status"] = "not_present_in_tag_block"
                if resource_errors:
                    asset["metadata_errors"] = resource_errors
                    asset["resource_reference_status"] = "partial"
                    asset["metadata_status"] = "partial"
                else:
                    asset["resource_reference_status"] = "indexed"
                    asset["metadata_status"] = "parsed"
            except InventoryError as error:
                asset.setdefault("metadata_errors", []).append(str(error))
                asset["metadata_status"] = "partial" if asset.get("subimages") else "unparsed"
        assets.append(asset)
    info.update(tags=sum(counts.values()), classes=dict(sorted(counts.items())), graphics_tags=len(assets))
    return info, assets


def inventory(path: Path) -> dict:
    path = path.resolve(strict=True)
    before = path.stat()
    sha = hash_file(path)
    maps, assets = [], []
    with path.open("rb") as stream:
        base, files = xiso_files(stream, before.st_size)
        for entry in files:
            if not entry["path"].casefold().endswith(".map"):
                continue
            try:
                info, items = halo3_map(stream, entry, before.st_size, sha)
            except InventoryError as error:
                info, items = {"path": entry["path"], "status": "unparsed", "error": str(error)}, []
            maps.append(info)
            assets.extend(items)
    after = path.stat()
    if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
        raise InventoryError("ISO changed during inventory; retry with a stable image")
    denominator = denominator_hash(assets)
    return {"path": str(path), "sha256": sha, "size": before.st_size, "partition_offset": base,
            "policy": POLICY, "denominator_sha256": denominator, "files": files, "maps": maps, "assets": assets,
            "complete_graphics_payload_inventory": False,
            "scope": "Classified Halo 3 retail graphics tag instances; shader permutations, external resource payloads and other graphics classes are not enumerated"}


def denominator_hash(assets):
    ids = sorted(a["id"] for a in assets)
    if len(ids) != len(set(ids)):
        raise InventoryError("Duplicate asset identity in inventory")
    return hashlib.sha256(json.dumps(ids, ensure_ascii=True, separators=(",", ":")).encode()).hexdigest()
