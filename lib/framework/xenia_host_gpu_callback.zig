//! Runtime ledger for the host-owned Xenia GPU callback seam.
//!
//! The package beside this file owns the ABI and admission predicate.  This
//! file owns mutable accounting: every query must be paired with the exact
//! response and an application report.  A successful report proves only that
//! Xenia installed its host callback; it does not upgrade any guest, PM4, ring,
//! VdSwap, or presentation fact.

const std = @import("std");
const contract = @import("xenia_host_gpu_callback_contract");

pub const Audit = struct {
    queries: u64 = 0,
    refusals: u64 = 0,
    approvals: u64 = 0,
    reports: u64 = 0,
    applied: u64 = 0,
    partial: u64 = 0,
    failed: u64 = 0,
    invalid_reports: u64 = 0,
    last_request: contract.Request = .{},
    last_response: contract.Response = .{},
    pending_report: bool = false,

    pub fn query(
        self: *Audit,
        request: contract.Request,
        host_control_enabled: bool,
        provider_enabled: bool,
    ) contract.Response {
        self.queries +|= 1;
        const response = contract.decide(
            request,
            host_control_enabled,
            provider_enabled,
        );
        if (response.decision == @intFromEnum(contract.Decision.allow)) {
            self.approvals +|= 1;
        } else {
            self.refusals +|= 1;
        }
        self.last_request = request;
        self.last_response = response;
        self.pending_report = true;
        return response;
    }

    /// A report is accepted only when it is bound to the most recent query,
    /// contains a known status, and applies no action Rosette did not grant.
    /// It is evidence about Xenia's adapter, never a second authorization.
    pub fn report(
        self: *Audit,
        request: contract.Request,
        response: contract.Response,
        applied_actions: u32,
        status: contract.ApplyStatus,
    ) bool {
        self.reports +|= 1;
        const bound_to_query = self.pending_report and
            requestEqual(request, self.last_request) and
            responseEqual(response, self.last_response);
        if (bound_to_query) self.pending_report = false;

        const coherent = bound_to_query and
            contract.requestIsCompatible(request) and
            contract.responseIsCompatibleForRequest(request, response) and
            applied_actions & ~response.actions == 0 and
            statusIsCoherent(response, applied_actions, status);
        if (!coherent) {
            self.invalid_reports +|= 1;
            return false;
        }

        switch (status) {
            .applied => self.applied +|= 1,
            .partially_applied => self.partial +|= 1,
            .failed, .not_applied => self.failed +|= 1,
        }
        return true;
    }

    pub fn snapshot(self: *const Audit) Snapshot {
        return .{
            .queries = self.queries,
            .refusals = self.refusals,
            .approvals = self.approvals,
            .reports = self.reports,
            .applied = self.applied,
            .partial = self.partial,
            .failed = self.failed,
            .invalid_reports = self.invalid_reports,
            .pending_report = self.pending_report,
            .last_request = self.last_request,
            .last_response = self.last_response,
        };
    }
};

pub const Snapshot = struct {
    queries: u64 = 0,
    refusals: u64 = 0,
    approvals: u64 = 0,
    reports: u64 = 0,
    applied: u64 = 0,
    partial: u64 = 0,
    failed: u64 = 0,
    invalid_reports: u64 = 0,
    pending_report: bool = false,
    last_request: contract.Request = .{},
    last_response: contract.Response = .{},
};

fn requestEqual(lhs: contract.Request, rhs: contract.Request) bool {
    return lhs.size == rhs.size and lhs.schema == rhs.schema and
        lhs.title_id == rhs.title_id and lhs.entry_point == rhs.entry_point and
        lhs.state_flags == rhs.state_flags and
        lhs.guest_callback_token == rhs.guest_callback_token and
        lhs.host_callback_token == rhs.host_callback_token and
        lhs.reserved == rhs.reserved and lhs.guest_step == rhs.guest_step and
        lhs.vblank_id == rhs.vblank_id and
        lhs.since_first_vblank_ms == rhs.since_first_vblank_ms;
}

fn responseEqual(lhs: contract.Response, rhs: contract.Response) bool {
    return lhs.size == rhs.size and lhs.schema == rhs.schema and
        lhs.decision == rhs.decision and lhs.reserved0 == rhs.reserved0 and
        lhs.reason == rhs.reason and lhs.actions == rhs.actions and
        lhs.proof_mask == rhs.proof_mask and
        lhs.authorization_id == rhs.authorization_id;
}

fn statusIsCoherent(
    response: contract.Response,
    applied_actions: u32,
    status: contract.ApplyStatus,
) bool {
    if (response.decision == @intFromEnum(contract.Decision.refuse)) {
        return status == .not_applied and applied_actions == 0;
    }

    return switch (status) {
        .not_applied, .failed => applied_actions == 0,
        .applied => applied_actions == response.actions,
        .partially_applied => applied_actions != 0 and
            applied_actions != response.actions,
    };
}

fn readyFlags() u32 {
    return contract.state_module_present | contract.state_entry_resolved |
        contract.state_load_idle | contract.state_graphics_ready |
        contract.state_command_processor_ready | contract.state_guest_main_running |
        contract.state_guest_callback_missing | contract.state_host_callback_missing |
        contract.state_ring_not_ready | contract.state_bootstrap_activity_absent |
        contract.state_cadence_ready;
}

test "audit accepts an exact applied host callback report" {
    var audit: Audit = .{};
    const request = contract.Request.init(1, 2, readyFlags(), 0, 0, 3, 4, 16);
    const response = audit.query(request, true, true);
    try std.testing.expect(contract.actionAllowed(
        response,
        .install_host_interrupt_callback,
    ));
    try std.testing.expect(audit.report(
        request,
        response,
        response.actions,
        .applied,
    ));
    try std.testing.expectEqual(@as(u64, 1), audit.applied);
    try std.testing.expectEqual(@as(u64, 0), audit.invalid_reports);
}

test "audit rejects a report that invents an action" {
    var audit: Audit = .{};
    const request = contract.Request.init(1, 2, readyFlags(), 0, 0, 3, 4, 16);
    const response = audit.query(request, true, true);
    try std.testing.expect(!audit.report(
        request,
        response,
        response.actions | 0x8000,
        .applied,
    ));
    try std.testing.expectEqual(@as(u64, 1), audit.invalid_reports);
}

test "a refused query has a coherent not-applied report" {
    var audit: Audit = .{};
    const request = contract.Request.init(1, 2, readyFlags(), 0, 0, 3, 4, 16);
    const response = audit.query(request, true, false);
    try std.testing.expectEqual(
        contract.Decision.refuse,
        @as(contract.Decision, @enumFromInt(response.decision)),
    );
    try std.testing.expect(audit.report(request, response, 0, .not_applied));
}

test "a callback report cannot be replayed or rebound" {
    var audit: Audit = .{};
    const request = contract.Request.init(1, 2, readyFlags(), 0, 0, 3, 4, 16);
    const response = audit.query(request, true, true);
    try std.testing.expect(audit.report(request, response, response.actions, .applied));
    try std.testing.expect(!audit.report(request, response, response.actions, .applied));

    const rebound = contract.Request.init(2, 2, readyFlags(), 0, 0, 3, 5, 16);
    const rebound_response = audit.query(rebound, true, true);
    try std.testing.expect(!audit.report(
        request,
        rebound_response,
        rebound_response.actions,
        .applied,
    ));
}

test "an authorization cannot cross vblank observations" {
    var audit: Audit = .{};
    const request = contract.Request.init(1, 2, readyFlags(), 0, 0, 3, 4, 16);
    const response = audit.query(request, true, true);
    var stale = response;
    stale.authorization_id = 5;
    try std.testing.expect(!audit.report(request, stale, stale.actions, .applied));
}
