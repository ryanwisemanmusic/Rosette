#!/usr/bin/env python3
"""Repair Xenia's object_ref copy constructors in a Rosette-owned source mirror.

Both constructors call reset(), which swaps with the destination's value_.
Without a member initializer that destination is indeterminate, and the
temporary may Release() an unrelated object during its destructor.
"""

from __future__ import annotations

import argparse
from pathlib import Path


TARGET = Path("src/xenia/kernel/xobject.h")
CONSTRUCTORS = (
    (
        "explicit object_ref(const object_ref& right) noexcept {",
        "explicit object_ref(const object_ref& right) noexcept : value_(nullptr) {",
    ),
    (
        "object_ref(const object_ref<V>& right) noexcept {",
        "object_ref(const object_ref<V>& right) noexcept : value_(nullptr) {",
    ),
)


def repair(source_root: Path, mirror_root: Path) -> bool:
    if source_root.resolve() == mirror_root.resolve():
        raise ValueError("the Xenia checkout is read-only; repair only its isolated mirror")
    header = mirror_root / TARGET
    original = header.read_text(encoding="utf-8")
    updated = original
    for before, after in CONSTRUCTORS:
        if updated.count(after) == 1 and updated.count(before) == 0:
            continue
        if updated.count(before) != 1 or updated.count(after) != 0:
            raise ValueError(f"unexpected object_ref constructor in {header}: {before}")
        updated = updated.replace(before, after, 1)
    if updated != original:
        header.write_text(updated, encoding="utf-8")
    return updated != original


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--mirror-root", required=True, type=Path)
    arguments = parser.parse_args()
    changed = repair(arguments.source_root, arguments.mirror_root)
    print(f"Xenia object_ref mirror repair: {'applied' if changed else 'already present'}")


if __name__ == "__main__":
    main()
