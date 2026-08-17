//! Evidence ledger for the first authentic Xenia GPU submission handoff.
//!
//! This deliberately observes Xenia's existing log boundary instead of the
//! translated-instruction hot path.  A PM4 decoder message proves that a
//! packet was consumed, but it does not by itself prove that the packet's
//! completion write became visible to the guest thread that owns the next
//! startup transition.  Likewise, an event wait does not identify the lock
//! owner that must signal it.  Keeping those facts separate makes the first
//! missing transition explicit without synthesizing any of them.

const std = @import("std");
const event_log = @import("event_log");

const machoCapturePrint = event_log.machoCapturePrint;

pub const Phase = enum(u8) {
    none,
    ring_published,
    pm4_consumed,
    shader_completion_packet,
    shader_completion_committed,
    critical_section_wait,
    critical_section_owner_known,
    critical_section_released,
    waiter_resumed,
    guest_vdswap_entered,
    guest_swap_packet_encoded,
    guest_vdswap_completed,
    guest_swap_published,
    authentic_swap_consumed,
    authentic_refresh_succeeded,
    authentic_native_presented,
};

pub const Observation = struct {
    previous: Phase,
    current: Phase,
    advanced: bool,
};

pub const DiagnosticProbePhase = enum(u8) {
    none,
    queued,
    host_packet_injected,
    swap_packet_consumed,
    refresh_attempted,
    refresh_succeeded,
    authentic_swap_superseded_probe,
    exhausted,
};

pub const Ledger = struct {
    phase: Phase = .none,
    last_progress_step: u64 = 0,
    ring_write_pointer_updates: u64 = 0,
    pm4_packets: u64 = 0,
    shader_completion_packets: u64 = 0,
    shader_completion_commits: u64 = 0,
    callback_completions: u64 = 0,
    critical_section_contentions: u64 = 0,
    critical_section_waits: u64 = 0,
    critical_section_releases: u64 = 0,
    critical_section_resumes: u64 = 0,
    guest_vdswap_calls: u64 = 0,
    guest_vdswap_completions: u64 = 0,
    guest_swap_packet_encodes: u64 = 0,
    guest_swap_publications: u64 = 0,
    authentic_swap_consumptions: u64 = 0,
    authentic_refreshes: u64 = 0,
    authentic_native_presents: u64 = 0,
    last_completion_address: u32 = 0,
    last_completion_requested: u32 = 0,
    last_completion_physical: u32 = 0,
    last_completion_alias: u32 = 0,
    completion_alias_matches: bool = false,
    completion_alias_valid: bool = false,
    last_lock_address: u32 = 0,
    last_waiter_thread: u32 = 0,
    last_owner_thread: u32 = 0,
    last_lock_count: i32 = 0,
    last_recursion_count: i32 = 0,
    self_contention: bool = false,
    critical_section_acquisitions: u64 = 0,
    critical_section_history_dumps: u64 = 0,
    diagnostic_probe_phase: DiagnosticProbePhase = .none,
    diagnostic_probe_id: u64 = 0,
    diagnostic_probe_transitions: u64 = 0,
    unresolved_extern_calls: u64 = 0,
    last_unresolved_extern_address: u32 = 0,
    guest_execution_faults: u64 = 0,
    last_guest_pc: u32 = 0,
    last_guest_fault_address: u64 = 0,

    pub fn observeLine(self: *Ledger, line: []const u8, step: u64) ?Observation {
        const previous = self.phase;
        var observed = false;

        if (contains(line, "DEBUG: REGISTER WRITE: CP_RB_WPTR")) {
            self.ring_write_pointer_updates +|= 1;
            self.advance(.ring_published, step);
            observed = true;
        }

        if (contains(line, "CP - PM4_") or
            contains(line, "PM4 AUTHENTIC MILESTONE: first guest-published command batch consumed") or
            contains(line, "RING BUFFER: first authentic PM4 packet consumed"))
        {
            self.pm4_packets +|= 1;
            self.advance(.pm4_consumed, step);
            observed = true;
        }

        if (contains(line, "CP - PM4_EVENT_WRITE_SHD")) {
            self.shader_completion_packets +|= 1;
            self.advance(.shader_completion_packet, step);
            observed = true;
        }

        if (contains(line, "GPU COMPLETION: EVENT_WRITE_SHD committed")) {
            // A committed EVENT_WRITE_SHD proves both decoding and execution.
            // Compact packet logging may intentionally omit the verbose
            // decoder line, so preserve the stronger evidence without making
            // the ledger look as though the prerequisite never happened.
            if (self.pm4_packets == 0) self.pm4_packets = 1;
            if (self.shader_completion_packets == 0) self.shader_completion_packets = 1;
            self.shader_completion_commits +|= 1;
            self.last_completion_address = parseHexField(line, "address=") orelse 0;
            self.last_completion_requested = parseHexField(line, "requested=") orelse 0;
            self.last_completion_physical = parseHexField(line, "physical=") orelse 0;
            self.last_completion_alias = parseHexField(line, "alias=") orelse 0;
            self.completion_alias_valid = contains(line, "alias_valid=YES");
            self.completion_alias_matches = contains(line, "alias_match=YES");
            self.advance(.shader_completion_committed, step);
            observed = true;
        }

        if (contains(line, "GPU callback dispatch completed:")) {
            self.callback_completions +|= 1;
            observed = true;
        }

        if (contains(line, "GPU CRITICAL SECTION: contention")) {
            self.critical_section_contentions +|= 1;
            self.last_lock_address = parseHexField(line, "cs=") orelse 0;
            self.last_waiter_thread = parseHexField(line, "current=") orelse 0;
            self.last_owner_thread = parseHexField(line, "owner=") orelse 0;
            self.last_lock_count = parseSignedField(line, "lock_count=") orelse 0;
            self.last_recursion_count = parseSignedField(line, "recursion=") orelse 0;
            self.self_contention = self.last_waiter_thread != 0 and
                self.last_waiter_thread == self.last_owner_thread;
            self.advance(if (self.last_owner_thread != 0)
                .critical_section_owner_known
            else
                .critical_section_wait, step);
            observed = true;
        }

        if (contains(line, "GPU CRITICAL SECTION: transition") and
            (contains(line, "action=acquire_spin") or
                contains(line, "action=acquire_recursive") or
                contains(line, "action=acquire_after_wait") or
                contains(line, "action=try_acquire") or
                contains(line, "action=try_recursive")))
        {
            self.critical_section_acquisitions +|= 1;
            self.last_lock_address = parseHexField(line, "cs=") orelse self.last_lock_address;
            self.last_owner_thread = parseSecondHexAfterArrow(line, "owner=") orelse self.last_owner_thread;
            if (self.last_owner_thread != 0) self.advance(.critical_section_owner_known, step);
            observed = true;
        }

        if (contains(line, "GPU CRITICAL SECTION: history reason=")) {
            self.critical_section_history_dumps +|= 1;
            observed = true;
        }

        if (contains(line, "GPU CRITICAL SECTION: wait begin")) {
            self.critical_section_waits +|= 1;
            self.last_lock_address = parseHexField(line, "cs=") orelse self.last_lock_address;
            self.last_waiter_thread = parseHexField(line, "current=") orelse self.last_waiter_thread;
            self.last_owner_thread = parseHexField(line, "owner=") orelse self.last_owner_thread;
            self.advance(if (self.last_owner_thread != 0)
                .critical_section_owner_known
            else
                .critical_section_wait, step);
            observed = true;
        }

        if (contains(line, "GPU CRITICAL SECTION: released waiter")) {
            self.critical_section_releases +|= 1;
            self.last_lock_address = parseHexField(line, "cs=") orelse self.last_lock_address;
            self.advance(.critical_section_released, step);
            observed = true;
        }

        if (contains(line, "GPU CRITICAL SECTION: wait resumed")) {
            self.critical_section_resumes +|= 1;
            self.advance(.waiter_resumed, step);
            observed = true;
        }

        if (contains(line, "VDSWAP PATH: stage=entered") or contains(line, "] d> VdSwap(")) {
            self.guest_vdswap_calls +|= 1;
            self.advance(.guest_vdswap_entered, step);
            observed = true;
        }

        if (contains(line, "VDSWAP PATH: stage=packet_encoded")) {
            self.guest_swap_packet_encodes +|= 1;
            self.advance(.guest_swap_packet_encoded, step);
            observed = true;
        }

        if (contains(line, "VDSWAP PATH: stage=completed")) {
            self.guest_vdswap_completions +|= 1;
            self.advance(.guest_vdswap_completed, step);
            observed = true;
        }

        if (contains(line, "VDSWAP PATH: stage=packet_published")) {
            self.guest_swap_publications +|= 1;
            self.advance(.guest_swap_published, step);
            observed = true;
        }

        if (contains(line, "PM4 AUTHENTIC MILESTONE:") and contains(line, "PM4_XE_SWAP")) {
            // Consumption of a guest-origin packet is stronger proof than a
            // producer-side publication log, so fill both facts exactly once.
            if (self.guest_swap_publications == 0) self.guest_swap_publications = 1;
            self.authentic_swap_consumptions +|= 1;
            self.advance(.authentic_swap_consumed, step);
            observed = true;
        }

        if ((parseUnsignedField(line, "authentic_swaps=") orelse 0) != 0 and
            (parseUnsignedField(line, "refresh=") orelse 0) != 0)
        {
            self.authentic_refreshes +|= 1;
            self.advance(.authentic_refresh_succeeded, step);
            observed = true;
        }

        if (contains(line, "authority=native") and contains(line, "provenance=AUTHENTIC")) {
            self.authentic_native_presents +|= 1;
            self.advance(.authentic_native_presented, step);
            observed = true;
        }

        if (contains(line, "GPU FALLBACK PROBE: transition")) {
            self.diagnostic_probe_transitions +|= 1;
            self.diagnostic_probe_id = parseUnsignedField(line, "probe_id=") orelse self.diagnostic_probe_id;
            self.diagnostic_probe_phase = parseDiagnosticProbePhase(line);
            observed = true;
        }

        if (contains(line, "undefined extern call:")) {
            self.unresolved_extern_calls +|= 1;
            self.last_unresolved_extern_address = parseHexField(line, "address=") orelse 0;
            observed = true;
        }

        if (contains(line, "GUEST FAULT FRONTIER:")) {
            self.guest_execution_faults +|= 1;
            self.last_guest_pc = parseHexField(line, "guest_pc=") orelse 0;
            self.last_guest_fault_address = parseHexField64(line, "fault_address=") orelse 0;
            observed = true;
        }

        if (!observed) return null;
        return .{ .previous = previous, .current = self.phase, .advanced = previous != self.phase };
    }

    pub fn verdict(self: *const Ledger) []const u8 {
        if (self.authentic_native_presents != 0) {
            return "an authentic guest-derived frame reached native presentation";
        }
        if (self.authentic_refreshes != 0) {
            return "authentic XE_SWAP reached guest-output refresh; native presentation is the next unproven transition";
        }
        if (self.authentic_swap_consumptions != 0) {
            return "the command processor consumed authentic PM4_XE_SWAP; inspect IssueSwap and guest-output refresh";
        }
        if (self.guest_swap_publications != 0) {
            return "the guest published PM4_XE_SWAP, but command-processor consumption is unproven";
        }
        if (self.guest_vdswap_completions != 0) {
            return "VdSwap returned after encoding, but the caller-owned command buffer was not authentically published";
        }
        if (self.guest_swap_packet_encodes != 0) {
            return "VdSwap encoded PM4_XE_SWAP, but export completion and caller publication are unproven";
        }
        if (self.guest_vdswap_calls != 0) {
            return "guest entered VdSwap, but PM4_XE_SWAP encoding has not been observed";
        }
        if (self.guest_execution_faults != 0) {
            if (self.unresolved_extern_calls != 0) {
                return "the authentic guest GPU producer was halted by a guest fault after unresolved import thunks; repair the import binding before diagnosing the downstream swap path";
            }
            return "the authentic guest GPU producer was halted by a guest execution fault before VdSwap";
        }
        if (self.critical_section_resumes != 0) {
            return "the GPU critical-section waiter resumed; inspect the next guest producer transition and write-pointer publication";
        }
        if (self.critical_section_releases != 0) {
            return "the lock owner released a waiter, but waiter resumption is unproven; inspect the event/condition wake bridge";
        }
        if (self.critical_section_waits != 0 or self.critical_section_contentions != 0) {
            if (self.self_contention) {
                return "the same guest thread is recorded as lock owner and waiter; inspect guest-thread identity/TLS restoration before treating this as ordinary contention";
            }
            if (self.last_owner_thread != 0) {
                return "the first missing transition is release of the contended GPU critical section by its recorded guest owner";
            }
            if (self.critical_section_history_dumps != 0) {
                return "the guest is parked on a zero-owner GPU critical section; the bounded transition history names the last authentic acquisition/release before this invalid state";
            }
            return "the guest is parked on the GPU critical section, but the acquisition that produced its zero-owner state was not yet captured";
        }
        if (self.shader_completion_commits != 0) {
            if (!self.completion_alias_valid) {
                return "the shader completion write executed, but the 4 KiB physical alias could not be inverted and validated";
            }
            if (!self.completion_alias_matches) {
                return "the shader completion write executed, but physical/virtual alias agreement is unproven";
            }
            return "the shader completion is visible through both guest aliases; the next missing transition is in the guest synchronization path";
        }
        if (self.shader_completion_packets != 0) {
            return "PM4_EVENT_WRITE_SHD was decoded, but its guest-memory completion commit is unproven";
        }
        if (self.pm4_packets != 0) {
            return "authentic PM4 is being consumed; the first shader-completion packet has not been observed";
        }
        if (self.ring_write_pointer_updates != 0) {
            return "the guest published a ring write pointer; authentic PM4 consumption is not yet proven";
        }
        return "no authentic guest GPU handoff evidence was observed";
    }

    pub fn logSummary(self: *const Ledger, current_step: u64) void {
        if (self.phase == .none and self.callback_completions == 0) return;
        machoCapturePrint(
            "macho-processor: Xenia GPU handoff summary: phase={s} wptr={d} pm4={d} shader_packets={d} shader_commits={d} callbacks={d} contentions={d} waits={d} releases={d} resumes={d} vdswap(entry/encoded/completed)={d}/{d}/{d} guest_swap(published/consumed/refresh/native_present)={d}/{d}/{d}/{d} producer_faults(extern/guest)={d}/{d} last_progress_step={d} idle_steps={d}; {s}\n",
            .{
                @tagName(self.phase),
                self.ring_write_pointer_updates,
                self.pm4_packets,
                self.shader_completion_packets,
                self.shader_completion_commits,
                self.callback_completions,
                self.critical_section_contentions,
                self.critical_section_waits,
                self.critical_section_releases,
                self.critical_section_resumes,
                self.guest_vdswap_calls,
                self.guest_swap_packet_encodes,
                self.guest_vdswap_completions,
                self.guest_swap_publications,
                self.authentic_swap_consumptions,
                self.authentic_refreshes,
                self.authentic_native_presents,
                self.unresolved_extern_calls,
                self.guest_execution_faults,
                self.last_progress_step,
                current_step -| self.last_progress_step,
                self.verdict(),
            },
        );
        if (self.critical_section_waits != 0 or self.critical_section_contentions != 0) {
            machoCapturePrint(
                "macho-processor: Xenia GPU dependency chain: completion_address=0x{x:0>8} requested=0x{x:0>8} physical=0x{x:0>8} alias=0x{x:0>8} alias_match={} -> lock=0x{x:0>8} lock_count={d} recursion={d} owner=0x{x:0>8} waiter=0x{x:0>8} self_contention={} -> release_observed={} -> resume_observed={}\n",
                .{
                    self.last_completion_address,
                    self.last_completion_requested,
                    self.last_completion_physical,
                    self.last_completion_alias,
                    self.completion_alias_matches,
                    self.last_lock_address,
                    self.last_lock_count,
                    self.last_recursion_count,
                    self.last_owner_thread,
                    self.last_waiter_thread,
                    self.self_contention,
                    self.critical_section_releases != 0,
                    self.critical_section_resumes != 0,
                },
            );
        }
        if (self.diagnostic_probe_phase != .none) {
            machoCapturePrint(
                "macho-processor: Xenia GPU diagnostic fallback: probe_id={d} phase={s} transitions={d} provenance=host_diagnostic_only; authentic frontier remains {s}\n",
                .{
                    self.diagnostic_probe_id,
                    @tagName(self.diagnostic_probe_phase),
                    self.diagnostic_probe_transitions,
                    if (self.authentic_swap_consumptions != 0)
                        "authentic PM4_XE_SWAP consumed"
                    else if (self.guest_swap_publications != 0)
                        "guest PM4_XE_SWAP published"
                    else if (self.guest_vdswap_completions != 0)
                        "VdSwap completed; caller publication missing"
                    else if (self.guest_vdswap_calls != 0)
                        "VdSwap entered; packet encoding missing"
                    else
                        "guest VdSwap entry missing",
                },
            );
        }
        if (self.guest_execution_faults != 0) {
            machoCapturePrint(
                "macho-processor: Xenia GPU producer halt: guest_pc=0x{x:0>8} fault_address=0x{x} unresolved_externs={d} last_extern=0x{x:0>8}; this is upstream of guest VdSwap and no swap fallback may count as authentic progress\n",
                .{
                    self.last_guest_pc,
                    self.last_guest_fault_address,
                    self.unresolved_extern_calls,
                    self.last_unresolved_extern_address,
                },
            );
        }
    }

    fn advance(self: *Ledger, next: Phase, step: u64) void {
        if (@intFromEnum(next) <= @intFromEnum(self.phase)) return;
        self.phase = next;
        self.last_progress_step = step;
    }
};

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

fn parseHexField(line: []const u8, marker: []const u8) ?u32 {
    const marker_index = std.mem.indexOf(u8, line, marker) orelse return null;
    var text = line[marker_index + marker.len ..];
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) text = text[2..];
    var length: usize = 0;
    while (length < text.len and std.ascii.isHex(text[length])) : (length += 1) {}
    if (length == 0) return null;
    return std.fmt.parseInt(u32, text[0..length], 16) catch null;
}

fn parseHexField64(line: []const u8, marker: []const u8) ?u64 {
    const marker_index = std.mem.indexOf(u8, line, marker) orelse return null;
    var text = line[marker_index + marker.len ..];
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) text = text[2..];
    var length: usize = 0;
    while (length < text.len and std.ascii.isHex(text[length])) : (length += 1) {}
    if (length == 0) return null;
    return std.fmt.parseInt(u64, text[0..length], 16) catch null;
}

fn parseSignedField(line: []const u8, marker: []const u8) ?i32 {
    const marker_index = std.mem.indexOf(u8, line, marker) orelse return null;
    const text = line[marker_index + marker.len ..];
    var length: usize = 0;
    if (length < text.len and text[length] == '-') length += 1;
    while (length < text.len and std.ascii.isDigit(text[length])) : (length += 1) {}
    if (length == 0 or (length == 1 and text[0] == '-')) return null;
    return std.fmt.parseInt(i32, text[0..length], 10) catch null;
}

fn parseUnsignedField(line: []const u8, marker: []const u8) ?u64 {
    const marker_index = std.mem.indexOf(u8, line, marker) orelse return null;
    const text = line[marker_index + marker.len ..];
    var length: usize = 0;
    while (length < text.len and std.ascii.isDigit(text[length])) : (length += 1) {}
    if (length == 0) return null;
    return std.fmt.parseInt(u64, text[0..length], 10) catch null;
}

fn parseSecondHexAfterArrow(line: []const u8, marker: []const u8) ?u32 {
    const marker_index = std.mem.indexOf(u8, line, marker) orelse return null;
    const arrow_index = std.mem.indexOfPos(u8, line, marker_index + marker.len, "->") orelse return null;
    var text = line[arrow_index + 2 ..];
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) text = text[2..];
    var length: usize = 0;
    while (length < text.len and std.ascii.isHex(text[length])) : (length += 1) {}
    if (length == 0) return null;
    return std.fmt.parseInt(u32, text[0..length], 16) catch null;
}

fn parseDiagnosticProbePhase(line: []const u8) DiagnosticProbePhase {
    if (contains(line, "-> refresh_succeeded")) return .refresh_succeeded;
    if (contains(line, "-> refresh_attempted")) return .refresh_attempted;
    if (contains(line, "-> swap_packet_consumed")) return .swap_packet_consumed;
    if (contains(line, "-> host_packet_injected")) return .host_packet_injected;
    if (contains(line, "-> queued")) return .queued;
    if (contains(line, "-> authentic_swap_superseded_probe")) return .authentic_swap_superseded_probe;
    if (contains(line, "-> exhausted")) return .exhausted;
    return .none;
}

test "GPU handoff identifies a contended owner after authentic completion" {
    var ledger = Ledger{};
    _ = ledger.observeLine("DEBUG: REGISTER WRITE: CP_RB_WPTR = 00000019", 10).?;
    _ = ledger.observeLine("CP - PM4_EVENT_WRITE_SHD, count 4", 20).?;
    _ = ledger.observeLine("GPU COMPLETION: EVENT_WRITE_SHD committed address=1FC9A002 virtual_alias=FFC99000 alias_physical=1FC9A000 alias_valid=YES requested=00000003 physical=00000003 alias=00000003 alias_match=YES", 30).?;
    _ = ledger.observeLine("GPU CRITICAL SECTION: contention cs=FFCAB000 current=3002A018 owner=3005C018 lock_count=1 recursion=1", 40).?;
    _ = ledger.observeLine("GPU CRITICAL SECTION: wait begin cs=FFCAB000 current=3002A018 owner=3005C018", 41).?;

    try std.testing.expectEqual(Phase.critical_section_owner_known, ledger.phase);
    try std.testing.expectEqual(@as(u32, 0x3005C018), ledger.last_owner_thread);
    try std.testing.expect(!ledger.self_contention);
    try std.testing.expectEqualStrings(
        "the first missing transition is release of the contended GPU critical section by its recorded guest owner",
        ledger.verdict(),
    );
}

test "GPU handoff distinguishes self-contention from a missing producer" {
    var ledger = Ledger{};
    _ = ledger.observeLine("GPU CRITICAL SECTION: contention cs=FFCAB000 current=3002A018 owner=3002A018 lock_count=2 recursion=1", 50).?;
    try std.testing.expect(ledger.self_contention);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "identity/TLS") != null);
}

test "GPU handoff advances through release resume and swap" {
    var ledger = Ledger{};
    _ = ledger.observeLine("GPU CRITICAL SECTION: wait begin cs=FFCAB000 current=3002A018 owner=3005C018", 10).?;
    _ = ledger.observeLine("GPU CRITICAL SECTION: released waiter cs=FFCAB000 owner=3005C018", 20).?;
    _ = ledger.observeLine("GPU CRITICAL SECTION: wait resumed cs=FFCAB000 current=3002A018 result=00000000", 30).?;
    _ = ledger.observeLine("[xenia] i> VDSWAP PATH: stage=entered call=1", 40).?;
    _ = ledger.observeLine("[xenia] i> VDSWAP PATH: stage=packet_encoded storage=external_command_buffer", 50).?;
    _ = ledger.observeLine("[xenia] i> VDSWAP PATH: stage=completed call=1", 60).?;
    try std.testing.expectEqual(Phase.guest_vdswap_completed, ledger.phase);
    try std.testing.expectEqual(@as(u64, 1), ledger.guest_vdswap_calls);
    try std.testing.expectEqual(@as(u64, 1), ledger.guest_swap_packet_encodes);
    try std.testing.expectEqual(@as(u64, 1), ledger.guest_vdswap_completions);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "caller-owned") != null);
}

test "GPU handoff retains authentic frontier separately from forced presentation" {
    var ledger = Ledger{};
    _ = ledger.observeLine("DEBUG: REGISTER WRITE: CP_RB_WPTR = 00000019", 10).?;
    _ = ledger.observeLine("GPU FALLBACK PROBE: transition probe_id=1 observing -> queued provenance=DIAGNOSTIC_ONLY", 20).?;
    _ = ledger.observeLine("GPU FALLBACK PROBE: transition probe_id=1 queued -> refresh_succeeded provenance=DIAGNOSTIC_ONLY", 30).?;

    try std.testing.expectEqual(Phase.ring_published, ledger.phase);
    try std.testing.expectEqual(DiagnosticProbePhase.refresh_succeeded, ledger.diagnostic_probe_phase);
    try std.testing.expectEqual(@as(u64, 1), ledger.diagnostic_probe_id);
    try std.testing.expectEqual(@as(u64, 0), ledger.guest_vdswap_calls);
    try std.testing.expectEqual(@as(u64, 0), ledger.authentic_swap_consumptions);
}

test "GPU handoff never promotes a diagnostic refresh to authentic" {
    var ledger = Ledger{};
    _ = ledger.observeLine("GPU FALLBACK PROBE: transition probe_id=1 observing -> queued provenance=DIAGNOSTIC_ONLY authentic_swaps=0 refresh=0/0", 10).?;
    _ = ledger.observeLine("GPU FALLBACK PROBE: transition probe_id=1 queued -> refresh_succeeded provenance=DIAGNOSTIC_ONLY authentic_swaps=0 refresh=1/1", 20).?;

    try std.testing.expectEqual(Phase.none, ledger.phase);
    try std.testing.expectEqual(@as(u64, 0), ledger.authentic_refreshes);
    try std.testing.expectEqual(DiagnosticProbePhase.refresh_succeeded, ledger.diagnostic_probe_phase);
}

test "GPU handoff proves authentic publication consumption refresh and present separately" {
    var ledger = Ledger{};
    _ = ledger.observeLine("PM4 AUTHENTIC MILESTONE: first guest-published PM4_XE_SWAP consumed", 10).?;
    _ = ledger.observeLine("GPU STARTUP ORDER: authentic_swaps=1 refresh=1/1", 20).?;
    _ = ledger.observeLine("presentation authority=native provenance=AUTHENTIC", 30).?;

    try std.testing.expectEqual(Phase.authentic_native_presented, ledger.phase);
    try std.testing.expectEqual(@as(u64, 1), ledger.guest_swap_publications);
    try std.testing.expectEqual(@as(u64, 1), ledger.authentic_swap_consumptions);
    try std.testing.expectEqual(@as(u64, 1), ledger.authentic_refreshes);
    try std.testing.expectEqual(@as(u64, 1), ledger.authentic_native_presents);
}

test "GPU critical-section acquisition transition recovers owner history" {
    var ledger = Ledger{};
    _ = ledger.observeLine("GPU CRITICAL SECTION: transition seq=2 action=acquire_spin cs=FFCAB000 thread=3005C018 owner=00000000->3005C018 lock=-1->0 recursion=0->1 wait_result=00000000", 10).?;
    _ = ledger.observeLine("GPU CRITICAL SECTION: contention cs=FFCAB000 current=3002A018 owner=00000000 lock_count=1 recursion=0", 20).?;
    _ = ledger.observeLine("GPU CRITICAL SECTION: history reason=contention_with_zero_owner entries=3", 21).?;

    try std.testing.expectEqual(@as(u64, 1), ledger.critical_section_acquisitions);
    try std.testing.expectEqual(@as(u64, 1), ledger.critical_section_history_dumps);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "bounded transition history") != null);
}

test "GPU handoff accepts compact authentic PM4 and inferred shader packet evidence" {
    var ledger = Ledger{};
    _ = ledger.observeLine("PM4 AUTHENTIC MILESTONE: first guest-published command batch consumed dwords=22 provenance=guest_wptr", 10).?;
    _ = ledger.observeLine("GPU COMPLETION: EVENT_WRITE_SHD committed address=1FC9A000 requested=00000003 physical=00000003 alias=00000003 alias_valid=YES alias_match=YES", 20).?;

    try std.testing.expectEqual(Phase.shader_completion_committed, ledger.phase);
    try std.testing.expectEqual(@as(u64, 1), ledger.pm4_packets);
    try std.testing.expectEqual(@as(u64, 1), ledger.shader_completion_packets);
    try std.testing.expectEqual(@as(u64, 1), ledger.shader_completion_commits);
}

test "GPU handoff names an unresolved import as the producer halt upstream of VdSwap" {
    var ledger = Ledger{};
    _ = ledger.observeLine("undefined extern call: address=8A0A7C1C name= export=<none> ordinal=0x000", 10).?;
    _ = ledger.observeLine("GUEST FAULT FRONTIER: guest_pc=89415B00 fault_address=34D841A40 thread=6", 20).?;

    try std.testing.expectEqual(@as(u64, 1), ledger.unresolved_extern_calls);
    try std.testing.expectEqual(@as(u32, 0x8A0A_7C1C), ledger.last_unresolved_extern_address);
    try std.testing.expectEqual(@as(u32, 0x8941_5B00), ledger.last_guest_pc);
    try std.testing.expectEqual(@as(u64, 0x34D84_1A40), ledger.last_guest_fault_address);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "import binding") != null);
}
