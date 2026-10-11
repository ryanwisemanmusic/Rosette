#!/usr/bin/env python3
"""Fail-closed audit for the lib/pkg boundary.

A package may describe immutable facts, schemas, pure classifiers, and source
mirrors. It must not retain process state or perform host I/O. Offline tools
may live beside a package, but their runtime implementation must be imported
from lib rather than copied into the package.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PKG = ROOT / "pkg"
LIB = (ROOT / "lib").resolve()
ALLOWED_ROLES = {"build-time", "source-mirror", "hybrid"}
IMPORT_RE = re.compile(r'@import\("([^"]+)"\)')
SCALAR_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]*)"$', re.MULTILINE)
STATE_RE = re.compile(
    r'\b(?:pub\s+)?const\s+'
    r'(?:Report|Ledger|WaitEvent|LabelLedger|CodegenStatus|Runtime)\s*='
)
TOP_LEVEL_VAR_RE = re.compile(r'^var\s+[A-Za-z_][A-Za-z0-9_]*\s*=', re.MULTILINE)
EFFECT_PATTERNS = (
    (re.compile(r'\bstd\.(?:fs|Io|process|Thread|time|posix|os|DynLib)\b'), "host I/O/process/thread/time API"),
    (re.compile(r'@(?:cImport|extern)\b'), "native effect/import boundary"),
)


def scalar(text: str, key: str) -> str | None:
    for name, value in SCALAR_RE.findall(text):
        if name == key:
            return value
    return None


def under(path: Path, parent: Path) -> bool:
    return path == parent or parent in path.parents


def source_is_tooling(source: Path, package_dir: Path, tooling: str | None) -> bool:
    return tooling is not None and source.resolve() == (package_dir / tooling).resolve()


def main() -> int:
    errors: list[str] = []
    package_count = 0
    source_count = 0
    role_counts: dict[str, int] = {}

    for manifest in sorted(PKG.rglob("package.toml")):
        package_count += 1
        package_dir = manifest.parent
        manifest_text = manifest.read_text(encoding="utf-8")
        role = scalar(manifest_text, "role")
        tooling = scalar(manifest_text, "tooling")

        if role not in ALLOWED_ROLES:
            errors.append(f"{manifest.relative_to(ROOT)}: missing or invalid role (expected one of {sorted(ALLOWED_ROLES)})")
            continue
        role_counts[role] = role_counts.get(role, 0) + 1

        tooling_sources: set[Path] = set()
        if tooling is not None:
            tooling_path = (package_dir / tooling).resolve()
            if not tooling_path.is_file():
                errors.append(f"{manifest.relative_to(ROOT)}: tooling file does not exist: {tooling}")
            else:
                tooling_sources.add(tooling_path)

        sources = sorted(package_dir.rglob("*.zig"))
        if not sources:
            errors.append(f"{manifest.relative_to(ROOT)}: package has no Zig source")
            continue

        for source in sources:
            source_count += 1
            source_text = source.read_text(encoding="utf-8")
            relative = source.relative_to(ROOT)

            for match in IMPORT_RE.finditer(source_text):
                import_name = match.group(1)
                if import_name.startswith("."):
                    resolved = (source.parent / import_name).resolve()
                    if under(resolved, LIB):
                        errors.append(f"{relative}: imports lib directly: {import_name}")
                elif import_name.startswith("lib/") or "/lib/" in import_name:
                    errors.append(f"{relative}: imports lib directly: {import_name}")

            # Tooling is allowed to read logs and allocate an output buffer,
            # but it must import the observer implemented in lib.
            if source.resolve() in tooling_sources:
                continue

            for pattern, description in EFFECT_PATTERNS:
                if pattern.search(source_text):
                    errors.append(f"{relative}: contains {description}; keep effects in lib")

            if role in {"build-time", "source-mirror"}:
                state_match = STATE_RE.search(source_text)
                if state_match:
                    errors.append(
                        f"{relative}: exports process-state holder {state_match.group(0).strip()}; "
                        "move mutable state to lib",
                    )
                if TOP_LEVEL_VAR_RE.search(source_text):
                    errors.append(f"{relative}: declares top-level mutable var; move it to lib")

    print(
        "pkg boundary: "
        f"packages={package_count} sources={source_count} "
        + " ".join(f"{role}={count}" for role, count in sorted(role_counts.items()))
    )
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"pkg boundary: FAIL ({len(errors)} violation(s))", file=sys.stderr)
        return 1

    print("pkg boundary: PASS (packages describe facts; live state/effects remain in lib)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

