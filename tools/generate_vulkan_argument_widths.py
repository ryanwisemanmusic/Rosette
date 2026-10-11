#!/usr/bin/env python3
"""Print/check Windows Vulkan scalar-width facts from the vendored registry.

This reads Rosette's explicit forwarding inventory, not Xenia, and never
changes the registry or creates/launches a Vulkan device. --print emits source
for an apply_patch update; --check is a read-only drift gate.
"""
import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "pkg/vendor/sources/vulkan-headers/1.4.313/registry/vk.xml"
OUTPUT = ROOT / "pkg/dll/win32/vulkan-1/src/argument_widths.zig"


def generate():
    registry = ET.parse(REGISTRY).getroot()
    types = {}
    for node in registry.findall("types/type"):
        name = node.get("name") or node.findtext("name")
        if name:
            types[name] = node

    def width(name):
        if name in ("uint32_t", "int32_t"):
            return 32
        if name in ("uint64_t", "int64_t", "size_t", "void", "float", "double"):
            return 64
        node = types[name]
        if node.get("alias"):
            return width(node.get("alias"))
        category = node.get("category")
        if category == "enum":
            return 32
        if category in ("handle", "funcpointer", "struct", "union"):
            return 64
        underlying = node.findtext("type")
        if underlying:
            return width(underlying)
        raise ValueError(f"unclassified scalar type: {name}")

    commands = {}
    for node in registry.findall("commands/command"):
        name = node.get("name") or node.findtext("proto/name")
        commands[name] = node

    def signature(name):
        node = commands[name]
        if node.get("alias"):
            return signature(node.get("alias"))
        params = node.findall("param")
        mask = 0
        for index, param in enumerate(params):
            text = "".join(param.itertext())
            type_name = param.findtext("type")
            # C arrays decay to pointers; pointer-to-u32 is not a scalar u32.
            if "*" not in text and "[" not in text and width(type_name) == 32:
                mask |= 1 << index
        return len(params), mask

    source = (ROOT / "lib/linker/dyld/dynamic_library_forwarder.zig").read_text()
    inventory = source.split("fn guestSymbolKind(", 1)[1].split("fn isXeniaFrameworkSymbol(", 1)[0]
    names = set(re.findall(r'"(vk\w+)"', inventory))
    names.discard("vkCmd")  # startsWith prefix, not an entry point
    names.add("vkCreateWin32SurfaceKHR")
    entries = []
    for name in sorted(names):
        count, mask = signature(name)
        # The SysV view has six register arguments plus sixteen stack slots.
        if count > 22:
            raise ValueError(f"{name} exceeds the adapter's argument capacity")
        entries.append(f'    .{{ "{name}", Signature{{ .argument_count = {count}, .scalar32_mask = 0x{mask:x} }} }},')
    body = "\n".join(entries)
    return f'''//! Generated from Vulkan-Headers 1.4.313 registry/vk.xml.
//! Regenerate/check with tools/generate_vulkan_argument_widths.py.
//! These are ABI facts, not permission to advertise native support.
const std = @import("std");

pub const Signature = struct {{
    argument_count: u8,
    scalar32_mask: u32,

    /// Windows' eight-byte argument slots do not widen their declared types.
    /// Preserve full pointers, handles, sizes and timeouts; only DWORD scalar
    /// values discard their unspecified upper half (including signed bits).
    pub fn normalize(self: Signature, index: usize, raw: u64) u64 {{
        if (index < self.argument_count and
            self.scalar32_mask & (@as(u32, 1) << @as(u5, @intCast(index))) != 0)
        {{
            return @as(u32, @truncate(raw));
        }}
        return raw;
    }}
}};

pub const signatures = std.StaticStringMap(Signature).initComptime(.{{
{body}
}});

pub fn lookup(name: []const u8) ?Signature {{
    return signatures.get(name);
}}

test "descriptor and barrier scalars have their declared DWORD widths" {{
    const bind = lookup("vkCmdBindDescriptorSets").?;
    try std.testing.expectEqual(@as(u8, 8), bind.argument_count);
    try std.testing.expectEqual(@as(u32, 0x5a), bind.scalar32_mask);
    try std.testing.expectEqual(@as(u64, 2), bind.normalize(4, 0x0000_0001_0000_0002));
    try std.testing.expectEqual(@as(u64, 0), bind.normalize(6, 0x0000_0800_0000_0000));
    const barrier = lookup("vkCmdPipelineBarrier").?;
    try std.testing.expectEqual(@as(u32, 0x15e), barrier.scalar32_mask);
}}

test "pointer handle timeout and size arguments retain all 64 bits" {{
    const raw: u64 = 0xffff_f500_1234_5678;
    const bind = lookup("vkCmdBindDescriptorSets").?;
    for ([_]usize{{ 0, 2, 5, 7 }}) |index| {{
        try std.testing.expectEqual(raw, bind.normalize(index, raw));
    }}
    const map = lookup("vkMapMemory").?;
    for ([_]usize{{ 1, 2, 3, 5 }}) |index| {{
        try std.testing.expectEqual(raw, map.normalize(index, raw));
    }}
    try std.testing.expectEqual(raw, lookup("vkWaitForFences").?.normalize(4, raw));
}}

test "promoted aliases and signed DWORD values use the same width contract" {{
    try std.testing.expectEqualDeep(lookup("vkCmdSetStencilOp").?, lookup("vkCmdSetStencilOpEXT").?);
    try std.testing.expectEqual(@as(u64, 0xffff_fffd), lookup("vkCmdDrawIndexed").?.normalize(4, 0xCAFE_BEEF_FFFF_FFFD));
    try std.testing.expect(lookup("vkCmdUnknownRosetteCommand") == null);
}}
''', len(entries)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--print", action="store_true")
    group.add_argument("--check", action="store_true")
    args = parser.parse_args()
    source, count = generate()
    if args.print:
        print(source, end="")
    elif not OUTPUT.exists() or OUTPUT.read_text() != source:
        raise SystemExit("Vulkan argument widths: FAIL (registry/forwarding inventory drift)")
    else:
        print(f"Vulkan argument widths: PASS ({count} signatures from the vendored registry)")


if __name__ == "__main__":
    main()
