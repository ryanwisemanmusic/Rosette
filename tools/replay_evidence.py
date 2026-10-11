#!/usr/bin/env python3
"""Replay and integrity-check a Rosette ``.r3j`` evidence journal.

The verifier intentionally has no dependency on Rosette, Xenia, a window, or a
GPU.  It validates the fixed wire envelope, record checksums, rolling hash,
run identity, sequence continuity, parent references, and the explicit footer
that distinguishes a clean run from a killed prefix.  Text logs are not read.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path


SCHEMA_VERSION = 3
HEADER_SIZE = 64
RECORD_WIRE_SIZE = 224
RECORD_FRAME_SIZE = 232
FOOTER_SIZE = 64
HEADER_MAGIC = b"R3JNL\x00\x03"
FOOTER_MAGIC = b"R3END\x00\x03"
FNV64_OFFSET = 0xCBF29CE484222325
FNV64_PRIME = 0x0100000001B3
FNV32_OFFSET = 0x811C9DC5
FNV32_PRIME = 0x01000193


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def u64(data: bytes, offset: int) -> int:
    return struct.unpack_from("<Q", data, offset)[0]


def fnv64(data: bytes, seed: int = FNV64_OFFSET) -> int:
    value = seed or FNV64_OFFSET
    for byte in data:
        value ^= byte
        value = (value * FNV64_PRIME) & 0xFFFFFFFFFFFFFFFF
    return value


def identity_checksum(record: bytes) -> int:
    # This is the intentionally narrow identity checksum in bridge/event.zig.
    values = (
        u16(record, 0),
        u16(record, 2),
        record[4],
        u64(record, 12),
        u64(record, 20),
        u64(record, 44),
        u64(record, 116),
        u64(record, 124),
        u64(record, 156),
        u64(record, 164),
        u64(record, 172),
        u64(record, 180),
        u64(record, 188),
        u16(record, 10),
    )
    value = FNV32_OFFSET
    for part in values:
        for byte in struct.pack("<Q", part):
            value ^= byte
            value = (value * FNV32_PRIME) & 0xFFFFFFFF
    return value


def integrity_checksum(record: bytes) -> int:
    """Match bridge/event.zig Record.integrityChecksum exactly."""
    values = (
        u16(record, 0),
        u16(record, 2),
        record[4],
        record[5],
        record[6],
        record[7],
        record[8],
        record[9],
        u16(record, 10),
        u64(record, 12),
        u64(record, 20),
        u64(record, 28),
        u64(record, 36),
        u64(record, 44),
        u64(record, 52),
        u64(record, 60),
        u64(record, 68),
        u32(record, 76),
        u32(record, 80),
        u64(record, 84),
        u32(record, 92),
        record[96],
        record[97],
        u16(record, 98),
        u32(record, 100),
        u32(record, 104),
        u64(record, 108),
        u64(record, 116),
        u64(record, 124),
        u64(record, 132),
        u64(record, 140),
        u32(record, 148),
        u32(record, 152),
        u64(record, 156),
        u64(record, 164),
        u64(record, 172),
        u64(record, 180),
        u64(record, 188),
        u64(record, 196),
        u64(record, 204),
        u64(record, 212),
    )
    value = FNV32_OFFSET
    for part in values:
        for byte in struct.pack("<Q", part):
            value ^= byte
            value = (value * FNV32_PRIME) & 0xFFFFFFFF
    return value


def parse_header(data: bytes, issues: list[str]) -> dict | None:
    if len(data) < HEADER_SIZE:
        issues.append("truncated header")
        return None
    header = data[:HEADER_SIZE]
    if header[: len(HEADER_MAGIC)] != HEADER_MAGIC:
        issues.append("bad header magic")
        return None
    values = {
        "schema": u16(header, 8),
        "header_size": u16(header, 10),
        "record_wire_size": u32(header, 12),
        "run_id": u64(header, 16),
        "manifest_hash": u64(header, 24),
        "schema_hash": u64(header, 32),
        "profile": header[40],
        "source_policy": header[41],
        "host_monotonic_ns": u64(header, 44),
    }
    if values["schema"] != SCHEMA_VERSION:
        issues.append(f"unsupported schema {values['schema']}")
    if values["header_size"] != HEADER_SIZE:
        issues.append("header size mismatch")
    if values["record_wire_size"] != RECORD_WIRE_SIZE:
        issues.append("record wire size mismatch")
    if values["run_id"] == 0:
        issues.append("zero run identity")
    if values["schema_hash"] == 0:
        issues.append("missing schema hash")
    stored = u32(header, 52)
    computed = fnv64(header[:52]) & 0xFFFFFFFF
    if stored != computed:
        issues.append("header checksum mismatch")
    values["header_checksum"] = stored
    return values


def parse_record(frame: bytes, issues: list[str]) -> dict | None:
    if len(frame) != RECORD_FRAME_SIZE:
        issues.append("truncated record frame")
        return None
    if u16(frame, 0) != SCHEMA_VERSION:
        issues.append(f"unsupported record schema {u16(frame, 0)}")
        return None
    stored = u32(frame, 220)
    computed = integrity_checksum(frame[:RECORD_WIRE_SIZE])
    if stored != computed:
        issues.append("record integrity checksum mismatch")
        return None
    return {
        "schema": u16(frame, 0),
        "kind": u16(frame, 2),
        "domain": frame[4],
        "source_class": frame[5],
        "result_class": frame[6],
        "reason": frame[7],
        "provenance": frame[8],
        "contract_edge": u16(frame, 10),
        "run_id": u64(frame, 12),
        "domain_sequence": u64(frame, 20),
        "global_sequence": u64(frame, 28),
        "event_id": u64(frame, 36),
        "guest_step": u64(frame, 44),
        "host_monotonic_ns": u64(frame, 52),
        "guest_thread": u64(frame, 60),
        "host_thread": u64(frame, 68),
        "guest_pc": u32(frame, 76),
        "guest_lr": u32(frame, 80),
        "host_rip": u64(frame, 84),
        "module_id": u32(frame, 92),
        "location_provenance": frame[96],
        "location_quality": frame[97],
        "address_guest_virtual": u32(frame, 100),
        "address_guest_physical": u32(frame, 104),
        "address_host": u64(frame, 108),
        "subject_id": u64(frame, 116),
        "generation": u64(frame, 124),
        "expected_value": u64(frame, 132),
        "actual_value": u64(frame, 140),
        "payload_length": u32(frame, 148),
        "payload_crc": u32(frame, 152),
        "parent_event_id": u64(frame, 156),
        "correlation_id": u64(frame, 164),
        "module_epoch": u64(frame, 172),
        "callback_generation": u64(frame, 180),
        "ring_generation": u64(frame, 188),
        "state_hash": u64(frame, 196),
        "effect_mask": u64(frame, 204),
        "effect_hash": u64(frame, 212),
    }


def replay(path: Path) -> dict:
    data = path.read_bytes()
    issues: list[str] = []
    header = parse_header(data, issues)
    report = {
        "schema_version": 1,
        "path": str(path.resolve()),
        "bytes": len(data),
        "status": "empty" if not data else "unsupported" if any("unsupported" in issue for issue in issues) else "incomplete",
        "admissible": False,
        "issues": issues,
        "header": header,
        "records": 0,
        "domains": {},
        "result_classes": {},
        "parents_missing": 0,
        "footer": None,
    }
    if header is None:
        if data and not issues:
            report["status"] = "corrupt"
        return report

    offset = HEADER_SIZE
    rolling = fnv64(data[:HEADER_SIZE])
    seen_events: set[int] = set()
    parsed_records: list[dict] = []
    arrival_last_by_domain: dict[int, int] = {}
    domain_counts: Counter[str] = Counter()
    result_counts: Counter[str] = Counter()
    arrival_out_of_order = 0
    last_event_id = 0
    footer = None

    while offset < len(data):
        remaining = len(data) - offset
        if remaining >= FOOTER_SIZE and data[offset : offset + len(FOOTER_MAGIC)] == FOOTER_MAGIC:
            raw_footer = data[offset : offset + FOOTER_SIZE]
            footer = {
                "schema": u16(raw_footer, 8),
                "footer_size": u16(raw_footer, 10),
                "record_wire_size": u32(raw_footer, 12),
                "run_id": u64(raw_footer, 16),
                "record_count": u64(raw_footer, 24),
                "last_event_id": u64(raw_footer, 32),
                "declared_drops": u64(raw_footer, 40),
                "journal_hash": u64(raw_footer, 48),
                "complete": raw_footer[56] != 0,
                "checksum": u32(raw_footer, 57),
            }
            footer_hash = fnv64(raw_footer[:57]) & 0xFFFFFFFF
            if footer["schema"] != SCHEMA_VERSION:
                issues.append("unsupported footer schema")
            if footer["footer_size"] != FOOTER_SIZE:
                issues.append("footer size mismatch")
            if footer["record_wire_size"] != RECORD_WIRE_SIZE:
                issues.append("footer record wire size mismatch")
            if footer["checksum"] != footer_hash:
                issues.append("footer checksum mismatch")
            if footer["run_id"] != header["run_id"]:
                issues.append("footer run identity mismatch")
            if footer["record_count"] != report["records"]:
                issues.append("footer record count mismatch")
            if footer["last_event_id"] != last_event_id:
                issues.append("footer last event mismatch")
            if footer["journal_hash"] != rolling:
                issues.append("footer rolling hash mismatch")
            if not footer["complete"]:
                issues.append("footer is not complete")
            if footer["declared_drops"]:
                issues.append(
                    f"footer declares {footer['declared_drops']} dropped records"
                )
            if offset + FOOTER_SIZE != len(data):
                issues.append("bytes follow footer")
            offset += FOOTER_SIZE
            break

        if remaining < RECORD_FRAME_SIZE:
            issues.append("truncated record or missing footer")
            offset = len(data)
            break
        frame = data[offset : offset + RECORD_FRAME_SIZE]
        record = parse_record(frame, issues)
        if record is None:
            offset += RECORD_FRAME_SIZE
            break
        if record["run_id"] != header["run_id"]:
            issues.append("record run identity mismatch")
        event_id = record["event_id"]
        if event_id == 0:
            issues.append("record has zero event identity")
        elif event_id in seen_events:
            issues.append(f"duplicate event identity {event_id}")
        else:
            seen_events.add(event_id)
        last_event_id = event_id
        domain = str(record["domain"])
        domain_counts[domain] += 1
        result_counts[str(record["result_class"])] += 1
        previous = arrival_last_by_domain.get(record["domain"])
        if previous is not None and record["domain_sequence"] < previous:
            # A merged file can legitimately receive a child from another
            # thread before an earlier sequence from this domain. Preserve the
            # observation as a warning/report field; validate domain order in
            # the causal pass below instead of rejecting valid concurrency.
            arrival_out_of_order += 1
        arrival_last_by_domain[record["domain"]] = max(
            previous or 0, record["domain_sequence"]
        )
        parsed_records.append(record)
        rolling = fnv64(frame, rolling)
        report["records"] += 1
        offset += RECORD_FRAME_SIZE

    # Validate the domain streams independently of arrival order. This keeps
    # producer order, merged arrival order, and causal order as three distinct
    # facts. A missing sequence is still fatal; a merely late record is not.
    by_domain: defaultdict[int, list[int]] = defaultdict(list)
    for record in parsed_records:
        by_domain[record["domain"]].append(record["domain_sequence"])
    for domain_id, sequences in by_domain.items():
        ordered_sequences = sorted(sequences)
        if ordered_sequences and ordered_sequences[0] != 1:
            issues.append(
                f"domain {domain_id} sequence starts at {ordered_sequences[0]}, expected 1"
            )
        for previous, current in zip(ordered_sequences, ordered_sequences[1:]):
            if current <= previous:
                issues.append(f"domain {domain_id} sequence duplicated")
            elif current > previous + 1:
                issues.append(
                    f"domain {domain_id} sequence gap {previous + 1}..{current - 1}"
                )

    # Stable causal topological order. The original arrival list remains in
    # the report, while this order is what a semantic replay consumes. Parent
    # references and domain predecessor edges may point forward in the merged
    # stream, but they must be resolvable before signoff.
    by_event = {record["event_id"]: index for index, record in enumerate(parsed_records)}
    used: set[int] = set()
    causal_order: list[int] = []
    causal_missing = 0
    causal_cycles = 0
    while len(causal_order) < len(parsed_records):
        selected: int | None = None
        for index, record in enumerate(parsed_records):
            if index in used:
                continue
            parent = record["parent_event_id"]
            if parent and (parent not in by_event or by_event[parent] not in used):
                continue
            sequence = record["domain_sequence"]
            if sequence > 1:
                predecessor = next(
                    (
                        predecessor_index
                        for predecessor_index, candidate in enumerate(parsed_records)
                        if candidate["domain"] == record["domain"]
                        and candidate["domain_sequence"] == sequence - 1
                    ),
                    None,
                )
                if predecessor is not None and predecessor not in used:
                    continue
            selected = index
            break
        if selected is None:
            unresolved = [
                record
                for index, record in enumerate(parsed_records)
                if index not in used
            ]
            if any(
                record["parent_event_id"]
                and record["parent_event_id"] not in by_event
                for record in unresolved
            ):
                causal_missing = sum(
                    1
                    for record in unresolved
                    if record["parent_event_id"]
                    and record["parent_event_id"] not in by_event
                )
                issues.append(
                    f"{causal_missing} parent references are missing from the retained run"
                )
            else:
                causal_cycles = len(unresolved)
                issues.append(
                    f"causal dependency cycle or unresolved domain order ({causal_cycles} records)"
                )
            break
        used.add(selected)
        causal_order.append(parsed_records[selected]["event_id"])

    report["domains"] = dict(sorted(domain_counts.items()))
    report["result_classes"] = dict(sorted(result_counts.items()))
    report["parents_missing"] = causal_missing
    report["causal_cycles"] = causal_cycles
    report["arrival_out_of_order"] = arrival_out_of_order
    report["arrival_order"] = [record["event_id"] for record in parsed_records]
    report["causal_order"] = causal_order
    report["footer"] = footer
    report["bytes_consumed"] = offset

    if footer is None:
        report["status"] = "incomplete" if not issues or data else "corrupt"
    elif issues:
        report["status"] = "corrupt"
    else:
        report["status"] = "complete"
        report["admissible"] = True
    report["issues"] = issues
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("journal", type=Path)
    parser.add_argument("--json", action="store_true", help="emit the full report as JSON")
    args = parser.parse_args()
    report = replay(args.journal.resolve())
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(
            "evidence-replay: status={} admissible={} records={} bytes={} issues={} path={}".format(
                report["status"],
                report["admissible"],
                report["records"],
                report["bytes"],
                len(report["issues"]),
                report["path"],
            )
        )
        for issue in report["issues"]:
            print(f"  - {issue}")
    return 0 if report["admissible"] else 2


if __name__ == "__main__":
    sys.exit(main())
