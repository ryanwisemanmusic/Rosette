//! Runtime bookkeeping for the Xenia launch-assist boundary.
//!
//! The package next to this file owns the decision predicate. This file owns
//! only mutable per-process accounting so a policy approval can be separated
//! from the host adapter's report that it actually applied the requested
//! operation.

const std = @import("std");
const contract = @import("xenia_launch_assist_contract");

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

    pub fn query(self: *Audit, request: contract.Request, host_control_enabled: bool) contract.Response {
        self.queries +|= 1;
        const response = contract.decide(request, host_control_enabled);
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

    /// Returns false when the adapter reports work Rosette did not authorize,
    /// or claims complete application without applying every authorized bit.
    /// A report is evidence about the adapter, never a new authorization.
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

        const authorized = response.actions;
        const unauthorized = applied_actions & ~authorized;
        const coherent = bound_to_query and
            contract.requestIsCompatible(request) and
            contract.responseIsCompatible(response) and
            unauthorized == 0 and
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
};

fn requestEqual(lhs: contract.Request, rhs: contract.Request) bool {
    return lhs.size == rhs.size and lhs.schema == rhs.schema and
        lhs.title_id == rhs.title_id and lhs.entry_point == rhs.entry_point and
        lhs.state_flags == rhs.state_flags and lhs.reserved == rhs.reserved and
        lhs.guest_step == rhs.guest_step;
}

fn responseEqual(lhs: contract.Response, rhs: contract.Response) bool {
    return lhs.size == rhs.size and lhs.schema == rhs.schema and
        lhs.decision == rhs.decision and lhs.reserved0 == rhs.reserved0 and
        lhs.reason == rhs.reason and lhs.actions == rhs.actions and
        lhs.proof_mask == rhs.proof_mask;
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

test "audit accepts only an exact authorized application" {
    var audit: Audit = .{};
    const request = contract.Request.init(
        1,
        2,
        contract.state_module_present | contract.state_entry_resolved |
            contract.state_load_idle | contract.state_graphics_ready |
            contract.state_command_processor_ready |
            contract.state_metadata_optional |
            contract.state_guest_main_not_started | contract.state_guest_gpu_idle |
            contract.state_ring_not_ready |
            contract.state_dispatch_worker_not_running,
        4,
    );
    const response = audit.query(request, true);
    try @import("std").testing.expect(audit.report(
        request,
        response,
        response.actions,
        .applied,
    ));
    try @import("std").testing.expectEqual(@as(u64, 1), audit.applied);
}

test "audit rejects an adapter that invents an action" {
    var audit: Audit = .{};
    const request = contract.Request.init(
        1,
        2,
        contract.state_module_present | contract.state_entry_resolved |
            contract.state_load_idle,
        4,
    );
    const response = audit.query(request, true);
    try @import("std").testing.expect(!audit.report(
        request,
        response,
        contract.action_defer_optional_title_metadata,
        .applied,
    ));
    try @import("std").testing.expectEqual(@as(u64, 1), audit.invalid_reports);
}

test "a refused query has a coherent not-applied report" {
    var audit: Audit = .{};
    const request = contract.Request.init(1, 0, contract.state_module_present, 4);
    const response = audit.query(request, true);
    try std.testing.expectEqual(
        contract.Decision.refuse,
        @as(contract.Decision, @enumFromInt(response.decision)),
    );
    try std.testing.expect(audit.report(request, response, 0, .not_applied));
    try std.testing.expectEqual(@as(u64, 0), audit.invalid_reports);
}

test "a report cannot be replayed or rebound to another request" {
    var audit: Audit = .{};
    const request = contract.Request.init(
        1,
        2,
        contract.state_module_present | contract.state_entry_resolved |
            contract.state_load_idle | contract.state_graphics_ready |
            contract.state_command_processor_ready |
            contract.state_metadata_optional | contract.state_guest_main_not_started |
            contract.state_guest_gpu_idle | contract.state_ring_not_ready,
        4,
    );
    const response = audit.query(request, true);
    try std.testing.expect(audit.report(request, response, response.actions, .applied));
    try std.testing.expect(!audit.report(request, response, response.actions, .applied));

    const rebound = contract.Request.init(
        2,
        request.entry_point,
        contract.state_module_present | contract.state_entry_resolved,
        request.guest_step,
    );
    _ = audit.query(rebound, true);
    try std.testing.expect(!audit.report(rebound, response, response.actions, .applied));
}
