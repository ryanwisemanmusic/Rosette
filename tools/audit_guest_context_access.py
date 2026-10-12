#!/usr/bin/env python3
"""Fail-closed audit: code that runs on a guest thread's behalf never touches
the PE state's own execution-local fields.

Rosette runs guest threads on several host threads at once. The PE state's
`regs`, `xmm`, `windows_last_error` and the other fields of
`WindowsGuestThreadContext` are the *process owner's* live context - Xenia's
UI thread. An import handler, a shim or the Vulkan forwarder runs on the host
thread of whichever guest thread made the call, so it must reach those fields
through `guest_context` (lib/guest_context/root.zig) or the state's own
`guestContextField`/`windowsGuestContextField`. A direct `state.regs` there
reads another thread's arguments and writes another thread's results while
that thread runs.

On 2026-09-26 the Windows Vulkan adapter did exactly that: it copied the
Emulator thread's registers over the UI thread's for each Vulkan call, and the
UI thread jumped into the Emulator thread's stack three seconds into the run.
The dyld forwarder it called read `state.regs` at 838 sites.

The audit reads the files that run on a guest's behalf, skips `test` blocks
(single-threaded fixtures), and fails on any direct access to an
execution-local field of `state` or `self`. A deliberate owner-only access
carries the comment `guest_context: owner` on its line.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# The fields of WindowsGuestThreadContext (lib/processor/ELF_processor/process.zig).
# `audit_context_fields_match` below fails the audit if this list and the
# struct drift apart.
EXECUTION_LOCAL_FIELDS = (
    "regs xmm ymm_hi zmm_hi k x87_stack x87_tags x87_top x87_status x87_control "
    "windows_last_error windows_errno_storage windows_current_import "
    "windows_current_import_return guest_access_violation_pending "
    "guest_access_violation windows_initterm_frames windows_initterm_frame_count "
    "windows_qsort_frames windows_qsort_frame_count windows_message_dispatch_frames "
    "windows_message_dispatch_frame_count windows_audio_callback_frames "
    "windows_audio_callback_frame_count block_jit_scratch step_retired "
    "parallel_code_sample_steps guest_clock_sample_steps "
    "windows_guest_slice_yield_requested windows_slice_pause_yield "
    "windows_guest_handoff_requested windows_slice_clock_reads active_guest_thread "
    "windows_active_guest_thread_slot verify_journal windows_thread_id active_idle_source "
    "windows_bsearch_frames windows_bsearch_frame_count "
    "last_decoded_op last_decoded_len last_instruction_rip "
    "decode_failure_is_invalid_control_target block_jit_tlb"
).split()

# Code that runs on the host thread of whichever guest thread called it.
SCANNED = (
    "lib/linker/dyld/dynamic_library_forwarder.zig",
    "lib/linker/dyld/vulkan/*.zig",
    "lib/gpu/vulkan/windows_guest_forwarder.zig",
    "lib/gpu/vulkan/windows_guest_forwarder/**/*.zig",
    "src/x64-ASM/windows_runtime.zig",
    "src/x64-ASM/windows_runtime/**/*.zig",
    "src/x64-ASM/linux_runtime.zig",
    "src/x64-ASM/interactive_bridge.zig",
    "src/tooling/exe_parser/native_windows_graphics.zig",
    "src/tooling/exe_parser/native_windows_graphics/**/*.zig",
    "lib/runtime/process-core/evex.zig",
    "lib/Mach-O/execution_helpers.zig",
)

ALLOW_MARKER = "guest_context: owner"
ACCESS = re.compile(r"\b(state|self)\.(" + "|".join(EXECUTION_LOCAL_FIELDS) + r")\b")
CONTEXT_STRUCT = re.compile(r"^const WindowsGuestThreadContext = struct \{$")
FIELD_LINE = re.compile(r"^    ([a-z_0-9]+): ")


def lines_outside_tests(text: str):
    """(number, line) pairs outside top-level `test` blocks."""
    inside_test = False
    for number, line in enumerate(text.split("\n"), start=1):
        if not inside_test and (line.startswith('test "') or line.startswith("test {")):
            inside_test = True
        if inside_test:
            if line == "}":
                inside_test = False
            continue
        yield number, line


def violations_in(text: str):
    found = []
    for number, line in lines_outside_tests(text):
        stripped = line.strip()
        if stripped.startswith("//") or ALLOW_MARKER in line:
            continue
        for match in ACCESS.finditer(line):
            found.append((number, match.group(0), stripped))
    return found


def context_fields() -> list[str]:
    source = (ROOT / "lib" / "processor" / "ELF_processor" / "process.zig").read_text(encoding="utf-8")
    fields = []
    inside = False
    for line in source.split("\n"):
        if CONTEXT_STRUCT.match(line):
            inside = True
            continue
        if inside:
            if line == "};":
                break
            match = FIELD_LINE.match(line)
            if match:
                fields.append(match.group(1))
    return fields


def self_test() -> None:
    sample = "\n".join(
        [
            "fn call(state: anytype) void {",
            "    const a = state.regs.rdi;",
            "    const b = guest_context.registers(state).rsi;",
            "    const c = &self.regs; // guest_context: owner",
            "    // state.regs.rax in a comment is not code",
            "    const d = state.regs_file;",
            "}",
            'test "fixtures may use the owner file" {',
            "    state.regs.rax = 1;",
            "}",
            "fn later(self: *S) void {",
            "    self.windows_last_error = 5;",
            "}",
        ]
    )
    found = violations_in(sample)
    assert [(number, access) for number, access, _ in found] == [
        (2, "state.regs"),
        (12, "self.windows_last_error"),
    ], found


def main() -> int:
    self_test()
    declared = context_fields()
    if not declared:
        print("guest-context audit: could not find WindowsGuestThreadContext in process.zig", file=sys.stderr)
        return 1
    missing = sorted(set(declared) - set(EXECUTION_LOCAL_FIELDS))
    if missing:
        print(
            "guest-context audit: WindowsGuestThreadContext has fields this audit does not check: "
            + ", ".join(missing)
            + " - add them to EXECUTION_LOCAL_FIELDS",
            file=sys.stderr,
        )
        return 1
    files = []
    for pattern in SCANNED:
        matches = sorted(ROOT.glob(pattern))
        if not matches:
            print(f"guest-context audit: {pattern} matches nothing; update SCANNED", file=sys.stderr)
            return 1
        files.extend(matches)
    failures = 0
    for path in files:
        for number, access, line in violations_in(path.read_text(encoding="utf-8")):
            failures += 1
            print(f"{path.relative_to(ROOT)}:{number}: {access} - {line}", file=sys.stderr)
    if failures:
        print(
            f"guest-context audit: {failures} direct access(es) to execution-local fields in code that runs on a "
            "guest thread's behalf. Use guest_context.field/registers/vectors (lib/guest_context/README.md), or mark "
            f"a deliberate owner-only access with '{ALLOW_MARKER}'.",
            file=sys.stderr,
        )
        return 1
    print(f"guest-context audit: {len(files)} file(s), {len(EXECUTION_LOCAL_FIELDS)} execution-local fields, no direct access")
    return 0


if __name__ == "__main__":
    sys.exit(main())
