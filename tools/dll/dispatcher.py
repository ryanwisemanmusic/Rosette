"""Which import names `src/x64-ASM/windows_runtime.zig` actually handles.

Shared by the generator and the audit on purpose. They previously each had
their own copy of this scraper, and the first time a handler was written in a
shape only one of them recognised, the generated tables said `not_implemented`
for twenty-two functions that had just been implemented - while the audit,
using the same blind spot, agreed with them. Two wrong answers that match are
worse than one that does not, because nothing reports a disagreement.
"""

from __future__ import annotations

import re
from pathlib import Path

PATTERNS = (
    # if (std.mem.eql(u8, name, "GetLastError")) { ... }
    re.compile(r'std\.mem\.eql\(u8,\s*name,\s*"([^"]+)"\)'),
    re.compile(r'std\.ascii\.eqlIgnoreCase\(name,\s*"([^"]+)"\)'),
    # A table-driven handler: .{ .name = "acos", .apply = ... }
    re.compile(r'\.name = "([A-Za-z_][A-Za-z0-9_@]*)"'),
    # The known-import name lists.
    re.compile(r'^\s{4,}"([A-Za-z_][A-Za-z0-9_@]*)",\s*$', re.M),
)

# A cohesive handler can live beside the dispatcher when it needs substantial
# state of its own. Include modules that the dispatcher calls through the
# explicit `tryFunction` contract, even when they are outside the conventional
# `windows_runtime/` directory (for example, `windows_bsearch.zig`).
DISPATCHED_HANDLER_IMPORT = re.compile(
    r'@import\("([^"]+)"\)\.tryFunction\s*\('
)

POLICY_BLOCK = re.compile(
    r"(?:const|pub const)\s+(?:WINDOWS_POLICY_REFUSALS|refusals)\s*=\s*\[_\]\[\]const u8\{(.*?)\};",
    re.S,
)
POLICY_NAMES = re.compile(r'^\s{4,}"([A-Za-z_][A-Za-z0-9_@]*)",\s*$', re.M)


def handled_names(source: Path) -> set[str]:
    # The main runtime owns the dispatch chain, while cohesive handler families
    # may live in its adjacent module directory (for example
    # windows_runtime/crt_math.zig). Include those direct modules so the export
    # generator and the coverage audit follow source moves instead of treating
    # an extracted handler as a missing implementation.
    sources = [source]
    module_dir = source.parent / source.stem
    if module_dir.is_dir():
        sources.extend(sorted(module_dir.glob("*.zig")))

    # Resolve direct, local handler modules referenced from the dispatch chain.
    # Zig's build module names omit `.zig`, while path imports usually include
    # it; try both forms and ignore non-local build modules such as `std`.
    source_text = source.read_text(encoding="utf-8")
    for module_name in DISPATCHED_HANDLER_IMPORT.findall(source_text):
        module_path = source.parent / module_name
        candidates = [module_path]
        if not module_path.suffix:
            candidates.append(module_path.with_suffix(".zig"))
        for candidate in candidates:
            if candidate.is_file():
                sources.append(candidate)
                break

    names: set[str] = set()
    for source_file in sources:
        text = source_file.read_text(encoding="utf-8")
        for pattern in PATTERNS:
            names.update(pattern.findall(text))
    return names


def policy_refused_names(source: Path) -> set[str]:
    """Names completed by an explicit capability refusal in the dispatcher."""
    # The catalogue is deliberately extracted from the PE runtime God file.
    # Keep the source-file form as a compatibility fallback for old worktrees,
    # while allowing the policy module to be the single source of truth.
    names: set[str] = set()
    for candidate in (source, source.with_name("windows_policy.zig")):
        if not candidate.exists():
            continue
        text = candidate.read_text(encoding="utf-8")
        for block in POLICY_BLOCK.finditer(text):
            names.update(POLICY_NAMES.findall(block.group(1)))
    return names
