#!/usr/bin/env python3
"""Preserve compiler findings and assign concrete follow-ups, never waivers.

Reads build output only. Does not edit Xenia, execute its PE, fetch DLLs,
suppress warnings or replace the compiler/linker's exit status.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import unittest


DIAGNOSTIC = re.compile(
    r"^(?P<file>.+):(?P<line>\d+):(?P<column>\d+):\s+warning:\s+"
    r"(?P<message>.*?)(?:\s+\[(?P<option>-W[^\]]+)\])?$"
)
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def classify(option: str, message: str) -> tuple[str, str]:
    if option == "-Wformat":
        return "argument-width-contract", (
            "Fix the format/argument type mismatch in the owning source or a "
            "reviewed deterministic translation rule; verify LLP64 widths. "
            "A missing DLL cannot repair varargs types."
        )
    if option == "-Wtautological-pointer-compare":
        return "source-logic-contract", (
            "Check array/pointer identity and intended error handling. The "
            "reported array address cannot be null; do not invent a type definition."
        )
    if option == "-Wmicrosoft-cast":
        return "function-pointer-abi-contract", (
            "Verify the GetProcAddress/FARPROC conversion and Microsoft x64 "
            "calling convention. A reviewed explicit cast must retain the "
            "declared function signature; do not substitute an object-pointer stub."
        )
    if option == "-Wundefined-inline":
        return "cross-translation-unit-definition-contract", (
            "Inspect the named definition and COFF object/archive/link map. "
            "A successful link is not inline-contract proof, and this warning "
            "does not by itself establish a missing runtime DLL export."
        )
    if option == "-Wignored-pragmas" and "init_seg" in message:
        return "static-initializer-order-contract", (
            "Verify the selected Windows target's CRT initializer section "
            "ordering against the intended Microsoft startup contract. "
            "Ignored initialization order is not a harmless optimization warning."
        )
    if option == "-Wignored-pragmas" and "optimize" in message:
        return "optimization-contract", (
            "Inspect the function's intended optimization mode and generated "
            "code under the selected Clang target; retain this ignored directive."
        )
    if option == "-Wmultichar":
        return "packed-literal-contract", (
            "Verify the literal's numeric value and byte order on the actual "
            "compiler target (for the PE DOS signature, expected WORD 0x5a4d). "
            "Use an explicit constant only through an authorized source change."
        )
    return "unclassified", "New compiler finding: review ownership and behavior before classifying; no automatic waiver."


def audit(log: str) -> dict:
    records = []
    linked = []
    for index, raw in enumerate(log.splitlines(), 1):
        line = ANSI.sub("", raw)
        if "Linking" in line and "executable" in line:
            linked.append({"log_line": index, "text": line})
        if "warning:" not in line:
            continue
        match = DIAGNOSTIC.fullmatch(line)
        record = {"log_line": index, "original": raw, "suppressed": False, "resolved": False}
        if match:
            location = match.groupdict()
            location["line"] = int(location["line"])
            location["column"] = int(location["column"])
            location["option"] = location["option"] or ""
            record.update(location)
            category, action = classify(location["option"], location["message"])
        else:
            category, action = classify("", line)
        record.update(category=category, action=action)
        records.append(record)
    return {
        "schema": "rosette.compiler-warning-ledger.v1",
        "log_sha256": hashlib.sha256(log.encode()).hexdigest(),
        "warnings": len(records),
        "counts": dict(sorted(Counter(row["category"] for row in records).items())),
        "records": records,
        "link_messages": linked,
        "proof_limits": "Classification is not resolution, link correctness, runtime import coverage, GPU validation or pixel correctness. Compiler exit remains authoritative.",
        "xenia_source_modified": False,
    }


class ContractTests(unittest.TestCase):
    def test_location_with_spaces_and_windows_colon(self):
        report = audit("C:/Test Folder/thing.h:12:7: warning: inline function 'x' is not defined [-Wundefined-inline]")
        self.assertEqual(report["warnings"], 1)
        self.assertEqual(report["records"][0]["file"], "C:/Test Folder/thing.h")
        self.assertFalse(report["records"][0]["resolved"])

    def test_initialization_is_not_optimization(self):
        self.assertNotEqual(classify("-Wignored-pragmas", "#pragma init_seg unsupported")[0], classify("-Wignored-pragmas", "#pragma optimize ignored")[0])

    def test_unknown_and_unlocated_warnings_survive(self):
        report = audit("a.cc:1:2: warning: new [-Wnew]\nwarning: no location\n1 warning generated.")
        self.assertEqual(report["counts"], {"unclassified": 2})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", nargs="?", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests))
        return 0 if result.wasSuccessful() else 1
    if args.log is None or args.output is None:
        parser.error("log and --output are required")
    report = audit(args.log.read_text(errors="replace"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"compiler warning ledger: warnings={report['warnings']} unclassified={report['counts'].get('unclassified', 0)} suppressed=0 resolved=0 output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
