#!/usr/bin/env python3
"""Fail-closed audit that every route can build the ELF processor.

Rosette builds `lib/processor/ELF_processor/process.zig` three times, from
three files that each name its modules independently:

  * ``build/build.zig``        - the check/test route (``elf_processor_mod``)
  * ``app/bundling/build.zig`` - the shipped runner and the .app
                                 (``pe_elf_state_module``)
  * ``build/Makefile``         - one ``zig build-exe`` command line

A module added to the source and wired into one route compiles for the author
who ran that route and fails in the others. That has now happened three times.
On 2026-09-12 it left ``app/bundling/zig-out/bin/rosette_exe_runner`` - the
binary the Xenia launcher actually executes - unbuildable, while the check
route and the Makefile route were both green, so a run used a stale runner and
nothing said so.

The invariant is exact and needs no judgement: **every non-relative
``@import`` in `process.zig` must be provided by all three routes.** The audit
reads what each file says rather than what a build would resolve, because the
whole failure mode is one file saying something the others do not.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SOURCE = ROOT / "lib" / "processor" / "ELF_processor" / "process.zig"
BUILD_ZIG = ROOT / "build" / "build.zig"
BUNDLE_ZIG = ROOT / "app" / "bundling" / "build.zig"
MAKEFILE = ROOT / "build" / "Makefile"

IMPORT = re.compile(r'@import\("([^"]+)"\)')
ADD_IMPORT = re.compile(r'(?:^|\W)([A-Za-z_][A-Za-z0-9_]*)\.addImport\("([^"]+)"')
MAKEFILE_DEFINE = re.compile(r"-M([A-Za-z_][A-Za-z0-9_]*)=")


def source_imports() -> set[str]:
    """Module names `process.zig` imports, excluding sibling `.zig` files."""
    text = SOURCE.read_text(encoding="utf-8")
    return {
        name
        for name in IMPORT.findall(text)
        if not name.endswith(".zig") and name not in ("std", "builtin", "root")
    }


def zig_route(path: Path, module_variable: str) -> set[str]:
    text = path.read_text(encoding="utf-8")
    return {
        import_name
        for variable, import_name in ADD_IMPORT.findall(text)
        if variable == module_variable
    }


def makefile_route() -> set[str]:
    """Every module the Makefile's build-exe line defines.

    The command line is one long string, so a defined module is available to
    whichever module declared it as a dependency; defining it is the part that
    is forgotten, and the part this audit is for.
    """
    text = MAKEFILE.read_text(encoding="utf-8")
    return set(MAKEFILE_DEFINE.findall(text))


def main() -> int:
    required = source_imports()
    routes = {
        "build/build.zig": zig_route(BUILD_ZIG, "elf_processor_mod"),
        "app/bundling/build.zig": zig_route(BUNDLE_ZIG, "pe_elf_state_module"),
        "build/Makefile": makefile_route(),
    }

    errors: list[str] = []
    for route, provided in routes.items():
        for name in sorted(required - provided):
            errors.append(f"{route} does not provide '{name}', which process.zig imports")

    # The test module in the check route builds the same source, so it has to
    # carry the same set or the gate compiles something the runner does not.
    test_route = zig_route(BUILD_ZIG, "elf_processor_test_mod")
    for name in sorted(required - test_route):
        errors.append(
            f"build/build.zig's elf_processor_test_mod does not provide '{name}', "
            f"so the gate does not compile what the runner does"
        )

    print(
        "build routes: process.zig imports {n} module(s); ".format(n=len(required))
        + " ".join(f"{route}={len(provided & required)}" for route, provided in routes.items())
    )
    if errors:
        for error in errors:
            print(f"build routes: FAIL {error}")
        print(f"build routes: FAIL ({len(errors)} route(s) cannot build the ELF processor)")
        return 1
    print("build routes: PASS (all three routes provide every module the ELF processor imports)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
