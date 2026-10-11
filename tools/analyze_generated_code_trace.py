#!/usr/bin/env python3
"""Analyze Rosetta's bounded generated-code transition trace.

`ROSETTE_ELF_TRACE_START`, `ROSETTE_ELF_TRACE_END`, and
`ROSETTE_ELF_TRACE_LIMIT` make the interpreter emit a bounded, read-only
instruction trace.  This companion turns that trace into evidence about
instruction progress, branch decisions, memory operands, thread ownership,
indirect transfers, generation changes, and repeating cycles.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path


TRANSITION = re.compile(
    r"trace transition rip=0x(?P<rip>[0-9a-fA-F]+) "
    r"next_rip=0x(?P<next>[0-9a-fA-F]+) op=(?P<op>\S+) len=(?P<len>\d+) "
    r"thread=0x(?P<thread>[0-9a-fA-F]+) addr=0x(?P<addr>[0-9a-fA-F]+) "
    r"cond=(?P<cond>\S+) flags_before=0x(?P<before>[0-9a-fA-F]+) "
    r"flags_after=0x(?P<after>[0-9a-fA-F]+)"
)
BEFORE = re.compile(
    r"trace before rip=0x(?P<rip>[0-9a-fA-F]+)(?: thread=0x(?P<thread>[0-9a-fA-F]+))? "
    r"op=(?P<op>\S+) len=(?P<len>\d+) addr=0x(?P<addr>[0-9a-fA-F]+).*?"
    r"cond=(?P<cond>\S+).*?flags=0x(?P<flags>[0-9a-fA-F]+)"
)
AFTER = re.compile(r"trace after\s+rip=0x(?P<next>[0-9a-fA-F]+).*?flags=0x(?P<flags>[0-9a-fA-F]+)")
GENERATION = re.compile(r"(?:code_generation|generation)=0x([0-9a-fA-F]+)")


@dataclass(frozen=True)
class Record:
    rip: int
    next_rip: int
    op: str
    length: int
    thread: int
    address: int
    condition: str
    flags_before: int
    flags_after: int


def parse(path: Path, limit: int | None = None) -> tuple[list[Record], int, list[int]]:
    records: list[Record] = []
    parse_errors = 0
    generations: list[int] = []
    pending: Record | None = None
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        transition = TRANSITION.search(raw)
        if transition:
            values = transition.groupdict()
            records.append(
                Record(
                    int(values["rip"], 16),
                    int(values["next"], 16),
                    values["op"],
                    int(values["len"]),
                    int(values["thread"], 16),
                    int(values["addr"], 16),
                    values["cond"],
                    int(values["before"], 16),
                    int(values["after"], 16),
                )
            )
            pending = None
        elif "trace transition" in raw:
            parse_errors += 1
        else:
            before = BEFORE.search(raw)
            if before:
                values = before.groupdict()
                pending = Record(
                    int(values["rip"], 16),
                    0,
                    values["op"],
                    int(values["len"]),
                    int(values["thread"] or "0", 16),
                    int(values["addr"], 16),
                    values["cond"],
                    int(values["flags"], 16),
                    int(values["flags"], 16),
                )
            else:
                after = AFTER.search(raw)
                if after and pending is not None:
                    values = after.groupdict()
                    records.append(
                        Record(
                            pending.rip,
                            int(values["next"], 16),
                            pending.op,
                            pending.length,
                            pending.thread,
                            pending.address,
                            pending.condition,
                            pending.flags_before,
                            int(values["flags"], 16),
                        )
                    )
                    pending = None
        generation = GENERATION.search(raw)
        if generation:
            generations.append(int(generation.group(1), 16))
        if limit is not None and len(records) >= limit:
            break
    return records, parse_errors, generations


def repeated_cycles(records: list[Record]) -> list[dict[str, int]]:
    keys = [(record.rip, record.next_rip, record.op) for record in records]
    result: list[dict[str, int]] = []
    for period in range(1, min(128, len(keys) // 2) + 1):
        repeats = 1
        while (repeats + 1) * period <= len(keys):
            left = len(keys) - (repeats + 1) * period
            right = len(keys) - repeats * period
            if keys[left:right] != keys[right : right + period]:
                break
            repeats += 1
        if repeats >= 4:
            result.append({"period": period, "repeats": repeats})
    return result


def analyze(path: Path, limit: int | None = None) -> dict:
    records, parse_errors, generations = parse(path, limit)
    indirect = sum(
        1
        for record in records
        if any(token in record.op for token in ("call_reg", "call_mem", "jmp_reg", "jmp_mem", "ret"))
    )
    changes = sum(1 for before, after in zip(generations, generations[1:]) if before != after)
    operations = Counter(record.op for record in records)
    cycles = repeated_cycles(records)
    return {
        "log": str(path),
        "records": len(records),
        "unique_rips": len({record.rip for record in records}),
        "operations": dict(sorted(operations.items())),
        "indirect_transfers": indirect,
        "generation_samples": len(generations),
        "generation_changes": changes,
        "repeat_cycles": cycles,
        "parse_errors": parse_errors,
        "status": "PASS" if parse_errors == 0 else "FAIL",
        "samples": [asdict(record) for record in records],
    }


def self_test() -> int:
    sample = "trace transition rip=0x100 next_rip=0x102 op=jcc_rel8 len=2 thread=0x44 addr=0x0 cond=nz flags_before=0x40 flags_after=0x0"
    match = TRANSITION.search(sample)
    assert match and match.group("op") == "jcc_rel8"
    assert repeated_cycles(
        [Record(1, 2, "nop", 1, 1, 0, "none", 0, 0)] * 4
    ) == [{"period": 1, "repeats": 4}]
    print("generated-code trace: self-test PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.log is None:
        parser.error("--log is required unless --self-test is used")
    if not args.log.exists():
        print(f"generated-code trace: FAIL log does not exist: {args.log}")
        return 1
    result = analyze(args.log, args.limit)
    if args.format == "json":
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(
            f"generated-code trace: records={result['records']} unique_rips={result['unique_rips']} "
            f"indirect_transfers={result['indirect_transfers']} generation_changes={result['generation_changes']} "
            f"parse_errors={result['parse_errors']} cycles={result['repeat_cycles']}"
        )
        print(f"generated-code trace: {result['status']}")
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
