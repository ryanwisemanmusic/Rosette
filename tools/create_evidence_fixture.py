#!/usr/bin/env python3
"""Create the deterministic no-Xenia journal used by the replay gate.

The fixture is intentionally small and semantic rather than a captured run:
it exercises the durable envelope, two causal records, domain continuity, and
the terminal footer.  A real journal is never replaced by the Makefile gate;
this script is only used when the default replay artifact is absent.
"""

from __future__ import annotations

import argparse
import struct
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

RUN_ID = 0x524F53455454455E
MANIFEST_HASH = 0x5048415345303031
SCHEMA_HASH = 0x524F534554544533


def fnv64(data: bytes, seed: int = FNV64_OFFSET) -> int:
    value = seed or FNV64_OFFSET
    for byte in data:
        value ^= byte
        value = (value * FNV64_PRIME) & 0xFFFFFFFFFFFFFFFF
    return value


def fnv32_parts(parts: list[int]) -> int:
    value = FNV32_OFFSET
    for part in parts:
        for byte in struct.pack("<Q", part):
            value ^= byte
            value = (value * FNV32_PRIME) & 0xFFFFFFFF
    return value


def header() -> bytes:
    data = bytearray(HEADER_SIZE)
    data[: len(HEADER_MAGIC)] = HEADER_MAGIC
    struct.pack_into("<HHIQQQBBHQ", data, 8, SCHEMA_VERSION, HEADER_SIZE, RECORD_WIRE_SIZE, RUN_ID, MANIFEST_HASH, SCHEMA_HASH, 1, 1, 0, 0)
    struct.pack_into("<I", data, 52, fnv64(data[:52]) & 0xFFFFFFFF)
    return bytes(data)


def record(domain_sequence: int, global_sequence: int, event_id: int, parent_event_id: int) -> bytes:
    fields = {
        "schema": SCHEMA_VERSION,
        "kind": 1,
        "domain": 1,
        "source_class": 1,
        "result_class": 1,
        "reason": 0,
        "provenance": 1,
        "reserved0": 0,
        "contract_edge": 1,
        "run_id": RUN_ID,
        "domain_sequence": domain_sequence,
        "global_sequence": global_sequence,
        "event_id": event_id,
        "guest_step": (domain_sequence - 1) * 100,
        "host_monotonic_ns": (domain_sequence - 1) * 1_000_000,
        "guest_thread": 0x1001,
        "host_thread": 0x2001,
        "guest_pc": 0x82582A98 + (domain_sequence - 1) * 4,
        "guest_lr": 0,
        "host_rip": 0x100000000 + (domain_sequence - 1) * 16,
        "module_id": 1,
        "location_provenance": 1,
        "location_quality": 1,
        "location_reserved": 0,
        "address_guest_virtual": 0,
        "address_guest_physical": 0,
        "address_host": 0,
        "subject_id": 0x3001,
        "generation": 1,
        "expected_value": 1,
        "actual_value": 1,
        "payload_length": 0,
        "payload_crc": 0,
        "parent_event_id": parent_event_id,
        "correlation_id": 0x4001,
        "module_epoch": 1,
        "callback_generation": 1,
        "ring_generation": 1,
        "state_hash": 0xA11CE,
        "effect_mask": 1,
        "effect_hash": 0xE71D,
    }
    checksum_parts = [
        fields["schema"],
        fields["kind"],
        fields["domain"],
        fields["source_class"],
        fields["result_class"],
        fields["reason"],
        fields["provenance"],
        fields["reserved0"],
        fields["contract_edge"],
        fields["run_id"],
        fields["domain_sequence"],
        fields["global_sequence"],
        fields["event_id"],
        fields["guest_step"],
        fields["host_monotonic_ns"],
        fields["guest_thread"],
        fields["host_thread"],
        fields["guest_pc"],
        fields["guest_lr"],
        fields["host_rip"],
        fields["module_id"],
        fields["location_provenance"],
        fields["location_quality"],
        fields["location_reserved"],
        fields["address_guest_virtual"],
        fields["address_guest_physical"],
        fields["address_host"],
        fields["subject_id"],
        fields["generation"],
        fields["expected_value"],
        fields["actual_value"],
        fields["payload_length"],
        fields["payload_crc"],
        fields["parent_event_id"],
        fields["correlation_id"],
        fields["module_epoch"],
        fields["callback_generation"],
        fields["ring_generation"],
        fields["state_hash"],
        fields["effect_mask"],
        fields["effect_hash"],
    ]
    data = bytearray(RECORD_FRAME_SIZE)
    offset = 0

    def put(fmt: str, value: int) -> None:
        nonlocal offset
        struct.pack_into(fmt, data, offset, value)
        offset += struct.calcsize(fmt)

    put("<H", fields["schema"])
    put("<H", fields["kind"])
    for name in ("domain", "source_class", "result_class", "reason", "provenance", "reserved0"):
        put("<B", fields[name])
    put("<H", fields["contract_edge"])
    for name in (
        "run_id", "domain_sequence", "global_sequence", "event_id", "guest_step",
        "host_monotonic_ns", "guest_thread", "host_thread",
    ):
        put("<Q", fields[name])
    for name in ("guest_pc", "guest_lr"):
        put("<I", fields[name])
    put("<Q", fields["host_rip"])
    put("<I", fields["module_id"])
    for name in ("location_provenance", "location_quality"):
        put("<B", fields[name])
    put("<H", fields["location_reserved"])
    for name in ("address_guest_virtual", "address_guest_physical"):
        put("<I", fields[name])
    put("<Q", fields["address_host"])
    for name in ("subject_id", "generation", "expected_value", "actual_value"):
        put("<Q", fields[name])
    for name in ("payload_length", "payload_crc"):
        put("<I", fields[name])
    for name in (
        "parent_event_id", "correlation_id", "module_epoch", "callback_generation",
        "ring_generation", "state_hash", "effect_mask", "effect_hash",
    ):
        put("<Q", fields[name])
    if offset != 220:
        raise RuntimeError(f"record layout ended at {offset}, expected 220")
    put("<I", fnv32_parts(checksum_parts))
    if offset != RECORD_WIRE_SIZE:
        raise RuntimeError(f"record wire layout ended at {offset}, expected {RECORD_WIRE_SIZE}")
    return bytes(data)


def footer(rolling_hash: int, record_count: int, last_event_id: int) -> bytes:
    data = bytearray(FOOTER_SIZE)
    data[: len(FOOTER_MAGIC)] = FOOTER_MAGIC
    struct.pack_into("<HHIQQQQQB", data, 8, SCHEMA_VERSION, FOOTER_SIZE, RECORD_WIRE_SIZE, RUN_ID, record_count, last_event_id, 0, rolling_hash, 1)
    struct.pack_into("<I", data, 57, fnv64(data[:57]) & 0xFFFFFFFF)
    return bytes(data)


def build() -> bytes:
    data = bytearray(header())
    rolling = fnv64(data)
    for values in ((1, 1, 1, 0), (2, 2, 2, 1)):
        frame = record(*values)
        data.extend(frame)
        rolling = fnv64(frame, rolling)
    data.extend(footer(rolling, 2, 2))
    return bytes(data)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(build())
    print(f"evidence-fixture: wrote {output} bytes={output.stat().st_size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
