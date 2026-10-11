#!/usr/bin/env python3
"""Classify every warning in a Rosette/Xenia source-of-truth log.

The logger's severity is not the same thing as ownership.  A guest advisory,
a deliberate Rosetta policy refusal, and a native provider failure all need a
different follow-up.  This ledger makes that ownership explicit and fails when
a new warning cannot be classified.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path


CATEGORIES = (
    "guest-advisory",
    "scheduling-finding",
    "rosette-capability-gap",
    "rosette-policy",
    "rosette-diagnostic",
    "provider-failure",
    "unresolved-runtime-finding",
    "unclassified",
)


@dataclass(frozen=True)
class WarningRecord:
    line: int
    text: str
    category: str
    reason: str


def classify(text: str) -> tuple[str, str]:
    lower = text.lower()
    # This is Rosetta's own per-call-site log governor reporting that it has
    # suppressed repeated diagnostics after the configured site budget. It is
    # useful evidence of log volume, but it does not describe a guest or host
    # capability failure. Match the governor's explicit power-of-two notice
    # narrowly so new log-governor wording remains subject to review.
    if (
        "warning(log_governor):" in lower
        and "call site above has written" in lower
        and "only power-of-two occurrences reach this log" in lower
    ):
        return "rosette-diagnostic", "Rosetta's log governor throttled repeated output from one call site after its configured budget"

    # These are Rosette's typed wait diagnostics, not proof of a guest defect,
    # a missing scheduler implementation, or harmless idle work. The producer
    # is explicitly unresolved: keep the warning and its action/severity in
    # a neutral finding category rather than claiming a policy waiver. Match
    # only the two emitted classes and their context rows; new classes still
    # fail this taxonomy gate until reviewed.
    if re.search(
        r"\bpe64 wait escalation:\s+(?:class|context)=(?:unsignalled_condition|timeout_hotspot)\b",
        lower,
    ):
        return "scheduling-finding", "a typed active-wait diagnostic; producer ownership is unresolved and the original severity/action require investigation, not a manufactured notification"

    # Xenia's recursive global-mutex bridge reports both its own owner state
    # and Rosetta's owner record. The line is a diagnostic snapshot: a bridge
    # owner with zero Xenia recursion can indicate a missed release, while
    # nonzero Xenia fields can be a live recursive unlock. It identifies a
    # scheduler/ownership question, not by itself a deadlock or guest fault.
    # The translator's cross-check found a block whose translation disagreed
    # with the interpreter (ROSETTE_BLOCK_JIT_VERIFY_MEMORY, or a register-only
    # block). The interpreter's result was kept and the address stays
    # interpreted; the line's ops and bytes locate a translation defect that
    # has not been fixed yet.
    if "pe64 block jit mismatch:" in lower:
        return "unresolved-runtime-finding", "a translated block disagreed with the interpreter; the interpreter's result was kept and the block stays interpreted, and its ops and bytes locate the translation defect"

    # The native SHA1 accelerator rejected an input block and left execution
    # to the guest implementation. This is a Rosetta optimization coverage gap,
    # not a guest or provider failure; keep it visible without making a safe
    # fallback look like an unclassified warning.
    if "pe64 xenia sha1 accelerator declined a block:" in lower and "falling back to guest implementation" in lower:
        return "rosette-capability-gap", "Rosetta declined this block in its SHA1 accelerator and preserved guest execution through the fallback"

    if "pe64 xenia global mutex:" in lower:
        return "scheduling-finding", "a sampled Xenia/Rosetta global-mutex ownership state; use the paired owner and recursion fields to distinguish a bridge release gap from an in-progress recursive unlock"

    # Decode-cache diagnostics are Rosette-owned runtime evidence. A vacant
    # fill is the expected first touch of an instruction; a full-set conflict
    # or stale-byte refill is a bounded-cache/invalidation failure and is
    # fatal under the strict PE policy. Keep both visible without allowing the
    # warning ledger to mistake the new structured line for an unclassified
    # Xenia warning.
    # The runtime renamed the line from MISS to FINDING on 2026-09-18 and
    # added a `classification=` field; the cause vocabulary is unchanged.
    if "pe64 decode cache miss:" in lower or "pe64 decode cache finding:" in lower:
        cause = re.search(r"\bcause=([a-z-]+)\b", lower)
        if cause is not None and cause.group(1) == "vacant-fill":
            return "rosette-policy", "a compulsory first-touch decode fill; it is expected and distinct from a capacity conflict or stale-byte refill"
        if cause is not None and cause.group(1) in {"capacity-conflict", "stale-bytes"}:
            return "rosette-capability-gap", "Rosette's bounded decode-cache or executable-byte invalidation contract found a non-reusable entry; strict PE runs stop at the exact set and resident list"
        # Preserve the audit's fail-closed behavior if the producer adds a
        # new miss cause without updating this taxonomy.

    # A parallel raw view is refused only for executable bytes, whose code
    # generation has to move after the write. The line names a Rosette
    # runtime path that still writes code through a borrowed slice instead
    # of copyToGuest/fillGuestMemory: Rosette's defect, never the guest's.
    if "pe64 parallel code borrow refused:" in lower:
        return "rosette-capability-gap", "a Rosette runtime path asked for a mutable view of executable bytes during parallel execution; it must use the ordered write API so the code generation moves after the bytes"

    # The executable-image write trace is a bounded Rosetta-owned observer.
    # It records the guest instruction, address and bytes around a code-write
    # invalidation; it does not change guest memory or execution. Historical
    # logs may contain events emitted before the address was confirmed to
    # overlap an exact executable section, so keep those auditable while the
    # runtime now filters the section gaps before tracing.
    if "pe64 executable image write trace:" in lower:
        return "rosette-diagnostic", "a bounded Rosetta-owned executable-write trace; it records evidence without changing guest execution"

    # These paired diagnostics establish which byte is rejected and the exact
    # string_view span presented to Xenia's parser. They still do not identify
    # the owner/source of that generated span, so classify both as unresolved
    # runtime evidence rather than guessing whether it is a Rosetta ABI issue
    # or malformed Xenia-owned config state.
    if (
        "pe64 xenia utf-8 input:" in lower
        and "captured before the original guest counter executes" in lower
    ):
        return "unresolved-runtime-finding", "Rosetta captured the malformed UTF-8 string_view and byte offset, but the span's producer and owner remain unproven"
    if "pe64 xenia utf-8 caller frame:" in lower:
        return "unresolved-runtime-finding", "Rosetta captured the caller's bounded SaveConfig stack frame to identify where the malformed formatted line was assembled"

    # The SaveConfig formatter probe uses warning severity in older runtime
    # builds, but these rows are bounded diagnostic snapshots rather than
    # guest warnings. Keep historical logs auditable while the current
    # runtime emits them at info level.
    if "pe64 fmt " in lower:
        return "rosette-policy", "a Rosetta-owned, read-only SaveConfig formatter diagnostic; the snapshot records inputs or output and does not alter guest state"

    # The PE throw observer has established that Xenia raised
    # std::invalid_utf8, but ownership remains unknown until its cursor is
    # tied to the buffer and the guest file/read that supplied it. Keep this
    # startup failure visible as an explicitly unresolved runtime finding;
    # do not guess that the malformed byte belongs to either Xenia or Rosetta.
    if (
        "pe64 c++ invalid utf-8 provenance:" in lower
        and "diagnostic observer leaves __cxa_throw and guest control flow unchanged" in lower
    ):
        return "unresolved-runtime-finding", "Xenia threw on malformed UTF-8; the observer has not yet tied the offending byte to its source or owner"

    # Historical parallel PE runs rejected valid output addresses because
    # guestMemory deliberately denies mutable borrows there. Keep the
    # _setjmp refusal and the resulting CRT read EFAULT attributed to the
    # Rosette boundary after the output probes have been corrected.
    if "windows _setjmp rejected environment=" in lower:
        return "rosette-capability-gap", "the PE setjmp boundary rejected a valid parallel guest output because mutable guest borrows are unavailable"
    if "pe64 c++ throw capture:" in lower:
        return "unresolved-runtime-finding", "the guest raised a C++ exception; inspect its type and throw site together with preceding file and memory failures"
    if "windows file failure:" in lower and re.search(r"\b_read x\d+ error=14\b", lower):
        return "rosette-capability-gap", "the parallel CRT descriptor read returned EFAULT after probing a valid destination through the forbidden mutable-borrow API"

    # A bounded diagnostic run is deliberately terminated by the requested
    # owner-step ceiling.  Keep that fact visible in the source log, but do
    # not mistake the harness boundary for a Rosetta execution or provider
    # failure.
    if "reached max steps" in lower:
        return "rosette-policy", "the bounded diagnostic run reached its requested step ceiling"

    # An accessible high-address VirtualAlloc request has no page-fault
    # semantics to enforce.  Older runners narrated that bookkeeping as a
    # warning even though only restrictive PAGE_NOACCESS/PAGE_READONLY
    # requests can lose observable behavior outside the bounded table.  Keep
    # the historical line classified until the refreshed runner stops
    # emitting it; a restrictive request must still be classified as a new
    # finding rather than swept into this rule.
    # Xenia's own race check on its write watch: `TriggerCallbacks` finds no
    # watch on the faulting page (another thread cleared it between the fault
    # and the lock) and returns "retry" on the strength of its page table,
    # without clearing Rosette's protection. Retrying would fault on the same
    # instruction forever, and a fault loop retires instructions, so no
    # liveness gate would ever call it a stall. Rosette performs the withheld
    # access once and says so. It is a Rosette policy decision about a benign
    # race, not a capability gap; `unresolved_retries=` on PE64 GPU WRITE
    # WATCH is the count to watch, and a large one means the two page tables
    # disagree systematically rather than occasionally.
    if (
        "pe64 guest access violation:" in lower
        and "asked for a retry" in lower
        and "rosette performed the access" in lower
    ):
        return "rosette-policy", "a benign race on Xenia's write watch; Rosette performed the withheld access instead of retrying it forever"

    if (
        "pe64 guest page protection:" in lower
        and "asked for accessible" in lower
        and "above the" in lower
        and "not enforced" in lower
    ):
        return "rosette-policy", "the PE context allocator requested an accessible range outside the protection table; no guest fault restriction was being dropped"

    # The PE runtime keeps a typed filesystem ledger.  The aggregate row is
    # intentionally a warning because it explains why optional-path probes
    # are not silently discarded.  Individual rows are classified narrowly:
    # an unknown API/error pair must still fail closed and receive a new
    # ownership decision rather than being swept into this rule.
    # Xenia's Vulkan IssueDraw refused a draw. Logs before 2026-09-14 carry it
    # as an unclassified fatal-point summary; the warning-severity map now
    # names it (vulkan-draw-failed-in-backend): a rectangle list with no host
    # geometry shaders gets a vertex-shader expansion IssueDraw does not take.
    if "failed in backend" in lower and "pm4_draw_indx" in lower:
        return "guest-advisory", "Xenia's Vulkan backend refused the draw; primitive type 8 is a rectangle list, which this IssueDraw rejects when the host has no geometry shaders"

    # Xenia records these presenter/command-processor setup failures as
    # fatal-point summary warnings. The Oct 4 run traced the MSL compile
    # failures to Rosette's rectangle-list SPIR-V rewrite exposing a
    # CullDistance output that MoltenVK omits. Keep all three linked setup
    # outcomes classified as a Rosetta capability gap until a subsequent run
    # proves the pipeline path recovers; the original run must remain visible
    # as a failed renderer initialization, not disappear from the ledger.
    if "failed to create the guest output painting pipeline" in lower:
        return "rosette-capability-gap", "the transformed vertex shader reached MoltenVK with an unsupported CullDistance output; Rosette now leaves that shader unmodified"
    if "failed to create the gamma ramp application pipelines" in lower:
        return "rosette-capability-gap", "the gamma-ramp graphics pipelines failed after MoltenVK rejected the generated MSL vertex shader"
    if "unable to setup command processor internal state" in lower:
        return "rosette-capability-gap", "command-processor initialization stopped after its required Vulkan pipeline creation failed"

    # Xenia's own shader translator could not read a memexport stream constant
    # out of a guest shader's ALU instructions. It is the guest's microcode and
    # the guest's translator on both sides of that failure - Rosette supplies
    # neither - so the effect is a shader that exports nothing, not a host gap.
    # Watch it if a title's rendering depends on memexport; it is otherwise a
    # capability note from the guest about the guest.
    if (
        "shadertranslator::gatheraluinstructioninformation" in lower
        and "memexport stream constant" in lower
    ):
        return "guest-advisory", "Xenia's shader translator could not extract a memexport stream constant from guest microcode; both sides of that are the guest's"

    # xboxkrnl's NtQueueApcThread could not find an XThread for the handle
    # the title passed (xboxkrnl_threading.cc); it returns
    # X_STATUS_INVALID_HANDLE and queues nothing. The handle is a guest
    # value, so this line is the guest's. Its "Might cause crash" is Xenia
    # warning that a completion routine the title expected will never run;
    # compare its step with any later crash before calling that crash Rosette's.
    # ROSETTE_PE64_CALL_PROBE names a function the operator asked to trace.
    # A name that resolves to nothing in this image is a mistyped request,
    # not a runtime finding: the run is unaffected and the probe is inert.
    if "pe64 call probe unresolved:" in lower:
        return "rosette-policy", "an operator-requested call probe named no symbol in this image; the probe is inert and the run is unaffected"

    if "ntqueueapcthread" in lower and "incorrect thread handle" in lower:
        return "guest-advisory", "Xenia's NtQueueApcThread found no XThread for the title's handle and queued nothing; a completion the title expected never runs"

    # Xenia's texture cache found a texture fetch slot holding something that
    # is not a texture fetch constant (type bits != 2, typically a vertex
    # fetch constant the title left in a shared slot). Both the constants and
    # the refusal are the guest's; Xenia skips the fetch.
    if "texture fetch constant" in lower and "is completely invalid" in lower:
        return "guest-advisory", "Xenia's texture cache refused a fetch slot that holds no texture fetch constant; the constants are the title's"

    # Rosetta's XMutant compatibility path observes a virtual ReleaseMutant
    # call with no native object and deliberately returns false so Xenia can
    # produce its own STATUS_MUTANT_NOT_OWNED result. The aggregate row is the
    # same bounded policy report, not evidence that the mutant was released.
    if (
        "pe64 xenia compat: xmutant::releasemutant" in lower
        and "has no native backing object" in lower
        and "returned false" in lower
    ):
        return "rosette-policy", "Rosetta preserved Xenia's native not-owned result for a ReleaseMutant call without a backing object"
    if (
        "pe64 xenia compat summary:" in lower
        and "missing-native-mutant release calls handled=" in lower
        and "returned false" in lower
    ):
        return "rosette-diagnostic", "the summary counts Rosetta's bounded XMutant not-owned compatibility path"

    # Xenia's pure-virtual handler is an actual fatal runtime outcome, but the
    # summary line alone does not identify the object or caller that reached
    # it. Keep it actionable and unresolved instead of treating it as an
    # expected shutdown or assigning blame to Rosetta or the guest.
    if "pure virtual method called" in lower:
        return "unresolved-runtime-finding", "Xenia reached its pure-virtual failure boundary; this record has no caller/object provenance to identify the invalid dispatch"

    # Xenia reports this as a fatal startup point after its Vulkan instance
    # extension count query returns an error. Historical parallel runs
    # refused every mutable guestMemory borrow, so the bridge could not write
    # the count; since 2026-09-30 a data borrow is served in parallel mode
    # and only executable bytes are refused. The fatal-point summary repeats
    # this line, so classify both forms as one bridge finding.
    if "failed to get the vulkan instance extension count" in lower:
        return "rosette-capability-gap", "Xenia's required Vulkan extension-count query failed; verify parallel guest-range validation and coordinated count/property writes before instance creation"

    # Historical parallel runs denied every mutable guestMemory borrow, and
    # vkCreateInstance's pInstance check went through one. Data borrows are
    # served again since 2026-09-30.
    if "failed to create a vulkan instance: errorinitializationfailed" in lower:
        return "rosette-capability-gap", "vkCreateInstance rejected its mapped parallel guest output because the bridge checked it through the forbidden mutable-borrow API"

    # Xenia emits this after NtProtectVirtualMemory returns failure while
    # setting up its physical-heap write watch. Historical parallel runs
    # refused the mutable borrow its in/out pointers were checked through.
    # Keep the failure visible as a Rosetta capability finding after the
    # runtime path is corrected.
    if "baseheap::protect failed due to host virtualprotect failure" in lower:
        return "rosette-capability-gap", "Xenia's page-protection request failed because Rosetta rejected valid parallel guest in/out pointers; the NtProtectVirtualMemory bridge must use address-based validation"

    # Xenia rejects every physical device it is offered. An empty adapter
    # name means Rosette's vkGetPhysicalDeviceProperties/Features wrote
    # nothing: on 2026-09-30 every parallel raw view was refused, the Apple
    # GPU read as '' without independentBlend, and the GPU thread faulted on
    # the null device. A named device that lacks the feature is the
    # provider's. The follow-on "couldn't choose" line has no name of its
    # own; on this host it has only ever followed the bridge's failure.
    if "doesn't support the independentblend feature required for gpu emulation" in lower:
        if "vulkan device ''" in lower:
            return "rosette-capability-gap", "Xenia read an empty adapter name and no features: the Vulkan bridge's physical-device property and feature writes were dropped"
        return "provider-failure", "the named host Vulkan device lacks independentBlend, which Xenia's GPU emulation requires"
    if "couldn't choose a compatible vulkan physical device or initialize a vulkan logical device" in lower:
        return "rosette-capability-gap", "Xenia found no usable Vulkan device; read the preceding 'Vulkan device' line - an empty name means the bridge dropped the adapter's properties"

    # Xenia's own device-loss report: the host driver killed a command buffer
    # (on Apple GPUs a watchdog hang or timeout reported through MoltenVK) and
    # Xenia treats a lost device as fatal. The provider is the failing side;
    # the draw that caused it is found from the MoltenVK line before it.
    # A fatal-point summary may wrap the later fence and presenter failures
    # instead of repeating the original "graphics device lost" wording.
    if "errordevicelost" in lower and ("vulkan" in lower or "presenter" in lower):
        return "provider-failure", "the Vulkan provider has already reported device loss; fence reset/create or presenter submission can no longer proceed"
    if "vulkanpresenter: failed to reset a command buffer for drawing to the swapchain" in lower:
        return "provider-failure", "the swapchain command buffer could not be reset after the run's Vulkan device-loss errors; inspect the first driver timeout/device-loss event as the initiating failure"
    if "graphics device lost" in lower:
        return "provider-failure", "the host GPU driver killed a command buffer and Xenia exited on the lost device"

    # A waitable timer armed with a completion routine: the timer signals,
    # but the routine is an APC and Rosette delivers none.
    if "waitable timer completion routine not delivered" in lower:
        return "rosette-capability-gap", "a SetWaitableTimer completion routine is an APC and Rosette has no APC delivery; the timer still signals its waiters"

    if "windows file failures:" in lower and "a large not-found count" in lower:
        return "guest-advisory", "the runtime is reporting its guest filesystem ledger; this run contains only typed probe/mode failures"
    if "windows file failure:" in lower:
        if re.search(r"(?:_wstat64|createfilew|findfirstfilew|findnextfilew|_wfopen) .*error=(?:2|18)\b", lower):
            return "guest-advisory", "the guest probed an absent path or exhausted a directory enumeration"
        if re.search(r"\bfread .*error=5\b", lower):
            # Until 2026-09-14 this was Rosette's: _wfopen's wide mode was
            # read as a narrow string, so L"a+b" opened write-only. A new
            # occurrence is a guest reading a stream it opened write-only.
            return "guest-advisory", "a read on a FILE stream opened without read access (historically Rosette misreading _wfopen's wide mode, fixed 2026-09-14)"

    # Older source-of-truth logs may contain the CRT table's former 128-entry
    # limit. Keep that historical defect attributable while the refreshed
    # runner replaces it with the larger guest-owned table; otherwise a
    # shell-update after a diagnostic run fails merely because it is auditing
    # evidence from before the fix.
    if "pe64 crt callback registration rejected" in lower:
        return "rosette-capability-gap", "the prior PE runner exhausted its bounded guest CRT callback table; the refreshed runner accepts the observed registration set"

    # A declared fatal condition that has not yet reached its decisive
    # threshold. The line names its owner and threshold itself; below the
    # threshold it is the design the condition documents (Xenia's XamState
    # commits three unreserved pages on every start), and the decisive
    # occurrence is logged as an error, not as this warning.
    if "pe64 guest condition:" in lower and "that make it decisive" in lower:
        return "guest-advisory", "a declared fatal condition below its decisive threshold; the decisive occurrence is an error line"
    # The PE heap model refused a second free of an already-free block. The
    # guest passed a bad free (often a garbage return address); refusing it
    # keeps the freed block from releasing whatever it holds next. Match all
    # three markers so a new heap-anomaly wording still fails closed.
    if (
        "pe64 guest heap double free:" in lower
        and "already free" in lower
        and "second free is refused" in lower
    ):
        return "guest-advisory", "the title freed an already-free block and Rosetta refused the second free; the heap record is intact"
    # The PE heap model ignored a free for an address with no allocation
    # record (observed callers pass small integers and destructors' scratch
    # rather than heap pointers). Ignoring it changes nothing observable.
    if (
        "pe64 guest heap unknown free:" in lower
        and "no allocation starts at this address" in lower
        and "free is ignored" in lower
    ):
        return "guest-advisory", "the title freed an untracked address and Rosetta ignored the free; no allocation record was touched"
    # An operator stepped past a named fatal point with
    # ROSETTE_XENIA_FATAL_POINT_ALLOW. The stop was decided and deliberately
    # waived, which is a harness policy, not a new defect.
    if "pe64 fatal point allowed:" in lower:
        return "rosette-policy", "the operator's fatal-point allow-list stepped past a named fatal point"

    if "native_vk_failures=" in lower:
        match = re.search(r"native_vk_failures=(\d+)", lower)
        if match and int(match.group(1)) > 0:
            return "provider-failure", "native Vulkan failure counter is nonzero"
    if any(token in lower for token in ("provider failure", "vulkan error", "moltenvk error", "vk_error")):
        return "provider-failure", "native graphics provider reported an error"
    # A few PE advisories are emitted with logger severity `warning` even
    # though their inline classification names Rosetta as the owner.  The
    # explicit classification is stronger evidence than the logger prefix.
    if "classification=" in lower or "substantiation:" in lower:
        if any(token in lower for token in ("rosetta", "font policy", "refused", "abi contract")):
            return "rosette-policy", "the warning's explicit classification assigns ownership to Rosetta"
        if "capability loss" in lower:
            return "rosette-capability-gap", "the warning's explicit classification names a capability loss"
    if any(token in lower for token in ("guest advisory", "guest-only", "advisory_only=yes", "title advisory")):
        return "guest-advisory", "warning is explicitly owned by the guest/title"
    if "capability gap" in lower or "not implemented" in lower or "no host backend" in lower:
        return "rosette-capability-gap", "Rosetta names a missing host-backed capability"
    if any(
        token in lower
        for token in (
            "import refusal",
            "import refusals",
            "import contract",
            "abi refusal",
            "dynamic refusal",
            "policy decision",
            "deliberate",
            "deliberately",
            "abi contract's refusal",
            "rosette does not implement",
            "font policy",
        )
    ):
        return "rosette-policy", "Rosetta deliberately completed an unavailable contract"
    return "unclassified", "no ownership rule matched this warning"


def read_ledger(path: Path) -> list[WarningRecord]:
    records: list[WarningRecord] = []
    for number, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if not re.search(r"\bwarning(?:\(|:)", raw, flags=re.IGNORECASE):
            continue
        category, reason = classify(raw)
        records.append(WarningRecord(number, raw, category, reason))
    return records


def self_test() -> int:
    assert classify("warning(elf): PE64 CAPABILITY GAP: dxgi.dll")[0] == "rosette-capability-gap"
    assert classify("warning(elf): PE64 BLOCK JIT MISMATCH: kind=memory_block block=0xa06b8200 differs_in=memory")[0] == "unresolved-runtime-finding"
    assert classify(
        "warning(elf): PE64 Xenia SHA1 accelerator declined a block: target=0x1400fd540 this=0x160bd93c8 step=1; falling back to guest implementation"
    )[0] == "rosette-capability-gap"
    assert classify(
        "warning(log_governor): the call site above has written 32768 lines; past 20000 per call site only power-of-two occurrences reach this log"
    )[0] == "rosette-diagnostic"
    assert classify("warning(elf): IMPORT REFUSAL: policy decision")[0] == "rosette-policy"
    assert classify("warning(elf): guest advisory: title chose a fallback")[0] == "guest-advisory"
    assert classify("warning(elf): native Vulkan provider failure")[0] == "provider-failure"
    assert classify("warning(elf): PE64 waitable timer completion routine not delivered: handle=0x1 routine=f step=1")[0] == "rosette-capability-gap"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=2 line=!> 0100000C PM4_DRAW_INDX_2(3, 8, 2): Failed in backend")[0] == "guest-advisory"
    assert classify("warning(elf): reached max steps (2000000000)")[0] == "rosette-policy"
    assert classify("warning(windows_runtime): Windows _setjmp rejected environment=0x1000 return=0x2000 rsp=0x3000")[0] == "rosette-capability-gap"
    assert classify("warning(windows_runtime): PE64 C++ THROW CAPTURE: event=1 type=St13__ios_failure")[0] == "unresolved-runtime-finding"
    assert classify("warning(elf): WINDOWS FILE FAILURE:   _read x1 error=14 (unnamed) class=io_failure")[0] == "rosette-capability-gap"
    assert classify(
        "warning(elf): PE64 GUEST PAGE PROTECTION: VirtualAlloc asked for accessible at 0x40dfff0000, above the 0x1000000000 window the table models; it is counted and not enforced"
    )[0] == "rosette-policy"
    assert classify(
        "warning(elf): WINDOWS FILE FAILURES: distinct=1 calls=2; a large not-found count against a lookup API is a guest probing for optional files"
    )[0] == "guest-advisory"
    assert classify("warning(elf): WINDOWS FILE FAILURE:   CreateFileW x2 error=2 (ERROR_FILE_NOT_FOUND)")[0] == "guest-advisory"
    assert classify("warning(elf): WINDOWS FILE FAILURE:   fread x2 error=5 (ERROR_ACCESS_DENIED)")[0] == "guest-advisory"
    assert classify("warning(elf): WINDOWS FILE FAILURE:   FindNextFileW x1 error=18 (ERROR_NO_MORE_FILES)")[0] == "guest-advisory"
    # The classified form: only actionable classes still warn, each naming its first subject and caller.
    assert classify("warning(elf): WINDOWS FILE FAILURE:   _wfopen x2 error=2 (ERROR_FILE_NOT_FOUND) class=missing_path_open first_subject='C:\\xenia\\cache.bin' first_caller=<not recorded>; an open of a path that does not exist on the host")[0] == "guest-advisory"
    assert classify("warning(elf): WINDOWS FILE FAILURES: distinct=7 calls=14147 actionable=2 in 4 call(s); a large not-found count against a lookup API is a guest probing for optional files")[0] == "guest-advisory"
    assert classify("warning(elf): PE64 guest condition: label=guest-heap-commit-unreserved owner=emulator:build occurrence=1 of the 4 that make it decisive step=39115251")[0] == "guest-advisory"
    assert classify("warning(elf): PE64 FATAL POINT ALLOWED: label=vulkan-tessellation-unavailable step=41197285")[0] == "rosette-policy"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: line=!> VulkanPresenter: Failed to create the guest output painting pipeline for effect 2")[0] == "rosette-capability-gap"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: line=!> Failed to create the gamma ramp application pipelines")[0] == "rosette-capability-gap"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: line=x> Unable to setup command processor internal state")[0] == "rosette-capability-gap"
    assert classify(
        "warning(elf): PE64 GUEST ACCESS VIOLATION: the handler asked for a retry at rip=0xa00d45fa "
        "but left [0x2a53aef20,+4) read-only; a retry would fault forever, so Rosette performed the "
        "access. Xenia's page flags and Rosette's protection table disagree about this page"
    )[0] == "rosette-policy"
    assert classify(
        "error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=6 line=!> 0100000C "
        "ShaderTranslator::GatherAluInstructionInformation: Couldn't extract memexport stream constant index"
    )[0] == "guest-advisory"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=1 first_step=1 last_step=1 line=w> 0100000C Texture fetch constant (0517D143 1000001A 00000000 00000000 00000000 00000000) is completely invalid!")[0] == "guest-advisory"
    assert classify("warning(elf): PE64 XENIA COMPAT: XMutant::ReleaseMutant has no native backing object at its exact null virtual call; returned false so the guest code produces X_STATUS_MUTANT_NOT_OWNED")[0] == "rosette-policy"
    assert classify("warning(elf): PE64 XENIA COMPAT SUMMARY: missing-native-mutant release calls handled=702; each returned false and let Xenia produce X_STATUS_MUTANT_NOT_OWNED at its own call site")[0] == "rosette-diagnostic"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=1 line=!> 0100000C Failed to reset a Vulkan fence: ErrorDeviceLost")[0] == "provider-failure"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=1 line=!> 0100000C Failed to create a Vulkan fence: ErrorDeviceLost")[0] == "provider-failure"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=1 line=!> 0100000C VulkanPresenter: Failed to submit the guest output image refresh fence signal: ErrorDeviceLost")[0] == "provider-failure"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=1 first_step=332746933353 last_step=332746933353 line=!> 0100000C VulkanPresenter: Failed to reset a command buffer for drawing to the swapchain")[0] == "provider-failure"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=1 line=!> F8000014 pure virtual method called")[0] == "unresolved-runtime-finding"
    assert classify("    [133] err: PE64 FATAL POINT SUMMARY WARNING: occurrences=1 line=!> F8000014 pure virtual method called")[0] == "unresolved-runtime-finding"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=1 first_step=1 last_step=1 line=w> 00000005 Failed to get the Vulkan instance extension count")[0] == "rosette-capability-gap"
    assert classify("    [25] err: PE64 FATAL POINT SUMMARY WARNING: occurrences=1 first_step=1 last_step=1 line=w> 00000005 Failed to get the Vulkan instance extension count")[0] == "rosette-capability-gap"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=1 first_step=53014472 last_step=53014472 line=!> 00000005 Failed to create a Vulkan instance: ErrorInitializationFailed")[0] == "rosette-capability-gap"
    assert classify("    [32] err: PE64 FATAL POINT SUMMARY WARNING: occurrences=1 first_step=53014472 last_step=53014472 line=!> 00000005 Failed to create a Vulkan instance: ErrorInitializationFailed")[0] == "rosette-capability-gap"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=4 first_step=53077021 last_step=53102660 line=!> 00000005 BaseHeap::Protect failed due to host VirtualProtect failure")[0] == "rosette-capability-gap"
    assert classify("    [40] err: PE64 FATAL POINT SUMMARY WARNING: occurrences=4 first_step=53077021 last_step=53102660 line=!> 00000005 BaseHeap::Protect failed due to host VirtualProtect failure")[0] == "rosette-capability-gap"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=2 first_step=1 last_step=2 line=!> F8000064 NtQueueApcThread: Incorrect thread handle! Might cause crash")[0] == "guest-advisory"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=1 first_step=1 last_step=1 line=x> 0100000C Graphics device lost (probably due to an internal error)")[0] == "provider-failure"
    assert classify("warning(elf): something new")[0] == "unclassified"
    assert classify(
        "warning(elf): PE64 GUEST HEAP DOUBLE FREE: address=0x1440bba50 occurrence=1 "
        "caller=0x3f8000003f800000 (<unmapped>) thread=owner-context step=30455578; "
        "the block was already free; the second free is refused, so it cannot release "
        "whatever the block holds next"
    )[0] == "guest-advisory"
    assert classify(
        "warning(elf): PE64 GUEST HEAP UNKNOWN FREE: address=0x14c1ef000 occurrence=1 "
        "caller=0x140ab19a2 (_ZNSt7__cxx1112basic_stringIwSt11char_traitsIwESaIwEE7reserveEy+0x62) "
        "thread=GPU Commands (0100000C) step=249308431; no allocation starts at this address; "
        "the free is ignored"
    )[0] == "guest-advisory"
    # A new heap-anomaly wording must still fail closed and receive its own
    # ownership decision rather than being swept into the free rules above.
    assert classify("warning(elf): PE64 GUEST HEAP CORRUPTION: address=0x1 occurrence=1")[0] == "unclassified"
    for finding in ("unsignalled_condition", "timeout_hotspot"):
        for row in ("class", "context"):
            assert classify(f"warning(elf): PE64 WAIT ESCALATION:   {row}={finding} severity=critical action=inspect_producer")[0] == "scheduling-finding"
    assert classify("warning(elf): PE64 WAIT ESCALATION: class=unknown_wait_failure severity=critical")[0] == "unclassified"
    assert classify("warning(elf): PE64 WAIT ESCALATION: class=timeout_hotspot_other")[0] == "unclassified"
    assert classify("warning(elf): PE64 XENIA GLOBAL MUTEX: srw_word=0x0 bridge_owner_thread=0x0 xenia_owner_thread=0x0 xenia_recursion=0 waiters=0")[0] == "scheduling-finding"
    assert classify("warning(elf): PE64 CRT callback registration rejected: callback=0x140c3d790")[0] == "rosette-capability-gap"
    assert classify("warning(elf): PE64 DECODE CACHE MISS: cause=vacant-fill step=1 set=4 ways=16 residents=")[0] == "rosette-policy"
    assert classify("warning(elf): PE64 DECODE CACHE MISS: cause=capacity-conflict step=2 set=4 ways=16 residents=16:0x1")[0] == "rosette-capability-gap"
    assert classify("warning(elf): PE64 DECODE CACHE MISS: cause=stale-bytes step=3 set=4 ways=16 residents=16:0x1")[0] == "rosette-capability-gap"
    assert classify("warning(elf): PE64 DECODE CACHE MISS: cause=new-cause step=4 set=4 ways=16 residents=")[0] == "unclassified"
    assert classify("warning(elf): PE64 DECODE CACHE FINDING: cause=vacant-fill classification=compulsory-first-touch source=image-code kind=memory_view source_index=0 generation=0 step=0 rip=0x140001302 fetch=0x140001302 set=21973 ways=16 residents= policy=record-only action=no action unless the same address repeats unexpectedly")[0] == "rosette-policy"
    assert classify("warning(elf): PE64 DECODE CACHE FINDING: cause=capacity-conflict classification=capacity-conflict-generated-code source=generated-code kind=memory_view source_index=1 generation=7 step=9 rip=0xa0000010 fetch=0xa0000010 set=5 ways=16 residents=16:0xa0 policy=record-only action=none")[0] == "rosette-capability-gap"
    assert classify("warning(elf): PE64 DECODE CACHE FINDING: cause=new-cause classification=x step=4 set=4 ways=16 residents=")[0] == "unclassified"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=1 first_step=52960621 last_step=52960621 line=w> 00000005 Vulkan device '' doesn't support the independentBlend feature required for GPU emulation")[0] == "rosette-capability-gap"
    assert classify("    [37] err: PE64 FATAL POINT SUMMARY WARNING: occurrences=1 first_step=52960621 last_step=52960621 line=w> 00000005 Vulkan device '' doesn't support the independentBlend feature required for GPU emulation")[0] == "rosette-capability-gap"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=1 first_step=1 last_step=1 line=w> 00000005 Vulkan device 'Some GPU' doesn't support the independentBlend feature required for GPU emulation")[0] == "provider-failure"
    assert classify("error(elf): PE64 FATAL POINT SUMMARY WARNING: occurrences=1 first_step=52960621 last_step=52960621 line=w> 00000005 Couldn't choose a compatible Vulkan physical device or initialize a Vulkan logical device")[0] == "rosette-capability-gap"
    assert classify("warning(elf): PE64 PARALLEL CODE BORROW REFUSED: address=0x140001010 count=4 occurrence=1 rip=0x140002000 thread=0x10; a runtime path asked for a mutable view of executable bytes while guest threads run in parallel; it has to write through copyToGuest or fillGuestMemory so the code generation moves after the bytes")[0] == "rosette-capability-gap"
    assert classify("warning(elf): PE64 EXECUTABLE IMAGE WRITE TRACE: event=1 address=0x14198b010 width=8")[0] == "rosette-diagnostic"
    assert classify("warning(elf): PE64 FMT VFORMAT ENTRY: call=1 entry=0x140405530 return=0x14017de3d config::SaveConfig")[0] == "rosette-policy"
    assert classify("warning(elf): PE64 FMT ARGUMENT SNAPSHOT: stage=vformat entry descriptor=0xdd step=1")[0] == "rosette-policy"
    assert classify(
        "warning(elf): PE64 C++ invalid UTF-8 provenance: type=N4utf812invalid_utf8E "
        "invalid_octet=0x90 source_byte=0x0 source_readable=false source=0x0 "
        "iterator_ref=0x0 iterator_ref_consistent=false throw_site=0x14011f999 "
        "(utf8::next+0x69) consumer=0x0 (<not recovered>) "
        "file=<no matching recent guest file read> diagnostic observer leaves "
        "__cxa_throw and guest control flow unchanged"
    )[0] == "unresolved-runtime-finding"
    assert classify(
        "warning(elf): PE64 XENIA UTF-8 INPUT: call=2 function=xe::utf8::count "
        "layout=length-data view=0x1c40b3b40 raw_words=[0x11,0x1440932f0] "
        "data=0x1440932f0 length=17 invalid_byte=0x90 byte_offset=8 "
        "caller=0x14017deb4 (config::SaveConfig+0x724) "
        "captured before the original guest counter executes"
    )[0] == "unresolved-runtime-finding"
    assert classify(
        "warning(elf): PE64 XENIA UTF-8 CALLER FRAME: caller_rsp=0x1c40b39e8 "
        "caller_frame_rsp=0x1c40b39f0 line_object=0x1c40b3a90"
    )[0] == "unresolved-runtime-finding"
    assert classify(
        "warning(elf): PE64 CALL PROBE unresolved: '_ZN3fooEv' names no symbol in this image"
    )[0] == "rosette-policy"
    print("warning ledger: self-test PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.log is None:
        parser.error("--log is required unless --self-test is used")
    if not args.log.exists():
        print(f"warning ledger: FAIL log does not exist: {args.log}")
        return 1
    records = read_ledger(args.log)
    counts = Counter(record.category for record in records)
    result = {
        "log": str(args.log),
        "warnings": len(records),
        "counts": {category: counts.get(category, 0) for category in CATEGORIES},
        "unclassified": [asdict(record) for record in records if record.category == "unclassified"],
        "records": [asdict(record) for record in records],
        "status": "PASS" if counts.get("unclassified", 0) == 0 else "FAIL",
    }
    if args.format == "json":
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(
            "warning ledger: "
            + " ".join(f"{category}={counts.get(category, 0)}" for category in CATEGORIES)
            + f" total={len(records)}"
        )
        for record in records:
            print(f"warning ledger: line={record.line} category={record.category} {record.text}")
        print(f"warning ledger: {result['status']}")
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
