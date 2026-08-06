const std = @import("std");

/// Zero-allocation finite-state transducer for the narrow Xenia generated-code
/// failure in which a CALL_POSSIBLE_RETURN comparison was missed and execution
/// reached `67 8B 03` (`mov eax, dword ptr [ebx]`) with EBX == 0.
///
/// This is deliberately not a pointer-guessing engine.  Anything ambiguous is
/// rejected, so an invalid guest address is never manufactured into a RIP.
///
/// There are two provable outcomes, distinguished by whether the comparison
/// read the same register as the faulting load:
///
///   * `.host_frame_return` — the comparison read a different register, whose
///     live value survived the fault and matches the guest return slot. The
///     abandoned generated frame is returned to its host caller.
///
///   * `.guest_return_predicate_edge` — the comparison read the null base
///     itself, so no live value can testify. The runtime instead recovers what
///     that register held before it was cleared, from retained execution
///     history; when that value is the guest return address, the predicate
///     provably should have been taken, and the machine takes the guest's own
///     `je` edge. No address is synthesised: the target is the branch the
///     runtime already decoded and proved lands at the epilogue, and the stack
///     is left alone because that epilogue performs its own teardown.
pub const Machine = struct {
    observations: u64 = 0,
    redirects: u64 = 0,
    rejections: u64 = 0,

    pub const State = enum(u8) {
        idle,
        xenia_generated_scope,
        null_base_load,
        guest_return_match,
        tail_shape,
        host_frame,
        redirect,
        reject,
    };

    pub const RejectReason = enum(u8) {
        none,
        outside_xenia_generated_code,
        not_address32_eax_from_ebx,
        base_not_exactly_zero,
        guest_target_not_proven,
        guest_return_not_proven,
        guest_target_not_return,
        tail_transfer_not_proven,
        dead_epilogue_not_proven,
        branch_target_not_epilogue,
        host_frame_not_proven,
        cleared_target_not_retained,
        cleared_target_not_guest_return,
    };

    /// Which provable continuation the machine emitted. Callers must consult
    /// this before touching the stack registers: only a host frame return
    /// rewrites RSP/RBP, because only that path replaces a frame teardown that
    /// will never run.
    pub const Redirect = enum(u8) {
        host_frame_return,
        guest_return_predicate_edge,
    };

    /// Where testimony about the cleared base register came from.
    ///
    /// `retained_history` is the per-thread instruction ring. It can only speak
    /// about values inside a window that is shared with every other guest
    /// thread, so on a first-observation fault it usually cannot speak at all.
    ///
    /// `definition_reread` is the generated code itself: the instruction that
    /// defined the register, recovered by decoding backwards from a known
    /// boundary, with its memory source re-read at fault time. This is
    /// available on the first execution and does not depend on ring retention.
    pub const ClearedTargetSource = enum(u8) {
        none,
        retained_history,
        definition_reread,
    };

    pub const Input = struct {
        xenia_compat: bool,
        generated_executable: bool,
        address32_eax_from_ebx: bool,
        base_value32: u32,
        /// True when the CALL_POSSIBLE_RETURN comparison read the *same*
        /// register that this machine has separately proven is exactly zero
        /// (Xenia's usual emission: `cmp ebx, [rsp+GUEST_RET_ADDR]` followed by
        /// `mov eax, [ebx]`). In that case `guest_target` is not an unproven
        /// value — it is a proven zero, and no evidence about it can ever
        /// arrive. See `evaluate`.
        guest_target_aliases_null_base: bool,
        guest_target: u64,
        guest_return: u64,
        guest_target_valid: bool,
        guest_return_valid: bool,
        /// Set when the aliasing case above holds and *some* admissible source
        /// yielded the value the base register was supposed to carry. Both
        /// sources are external testimony about a register the fault itself
        /// defines as zero; neither is the live register file.
        cleared_target_retained: bool,
        cleared_target: u64,
        /// Which source spoke. Reporting only — the decision below is the same
        /// either way, because the admissibility test is equality with an
        /// independently read guest return slot, not the provenance of the
        /// claim.
        cleared_target_source: ClearedTargetSource,
        /// Absolute target of the CALL_POSSIBLE_RETURN `je`, as decoded by the
        /// runtime — an edge that already exists in the generated code, not a
        /// value this machine composes.
        predicate_edge_target: u64,
        tail_jmp_rax_found: bool,
        dead_epilogue_found: bool,
        branch_targets_dead_epilogue: bool,
        host_return_not_guest: bool,
        frame_pointer: u64,
        saved_frame_pointer: u64,
        saved_frame_pointer_valid: bool,
        host_return: u64,
        host_return_executable: bool,
    };

    pub const Output = struct {
        state: State,
        reason: RejectReason = .none,
        redirect: Redirect = .host_frame_return,
        cleared_target_source: ClearedTargetSource = .none,
        host_rip: u64 = 0,
        host_rsp: u64 = 0,
        host_rbp: u64 = 0,

        pub fn redirects(self: Output) bool {
            return self.state == .redirect;
        }

        /// Only the host frame return substitutes for a teardown that will not
        /// run. The guest predicate edge leads into an epilogue that performs
        /// its own, so rewriting RSP/RBP there would tear the frame down twice.
        pub fn rewritesStack(self: Output) bool {
            return self.redirects() and self.redirect == .host_frame_return;
        }
    };

    pub fn evaluate(self: *Machine, input: Input) Output {
        self.observations +|= 1;

        if (!input.xenia_compat or !input.generated_executable) {
            return self.reject(.outside_xenia_generated_code);
        }
        if (!input.address32_eax_from_ebx) {
            return self.reject(.not_address32_eax_from_ebx);
        }
        if (input.base_value32 != 0) {
            return self.reject(.base_not_exactly_zero);
        }
        if (!input.tail_jmp_rax_found) {
            return self.reject(.tail_transfer_not_proven);
        }
        if (!input.dead_epilogue_found) {
            return self.reject(.dead_epilogue_not_proven);
        }
        if (!input.branch_targets_dead_epilogue) {
            return self.reject(.branch_target_not_epilogue);
        }

        // Xenia's usual emission compares the base register itself
        // (`cmp ebx,[rsp+GUEST_RET_ADDR]; je epilogue; mov eax,[ebx]`), so the
        // value the predicate tested is the same zero this machine already
        // proved. Asking for a "valid guest target" there is unsatisfiable by
        // construction — one observation cannot be both exactly zero and a
        // guest module address — and the shape gates above are the only ones
        // that can speak. The admissible testimony is what the register held
        // before it was cleared, recovered from retained execution history.
        //
        // When that value is the guest return address, the predicate provably
        // should have been taken, and the correct continuation is the guest's
        // own `je` edge: no address is composed, the stack is untouched, and
        // the epilogue then runs exactly as the unclobbered guest would have
        // run it. Anything less than that proof still fails closed.
        if (input.guest_target_aliases_null_base) {
            if (!input.guest_return_valid) {
                return self.reject(.guest_return_not_proven);
            }
            if (!input.cleared_target_retained) {
                return self.reject(.cleared_target_not_retained);
            }
            if (@as(u32, @truncate(input.cleared_target)) !=
                @as(u32, @truncate(input.guest_return)))
            {
                return self.reject(.cleared_target_not_guest_return);
            }
            if (input.predicate_edge_target == 0) {
                return self.reject(.branch_target_not_epilogue);
            }
            self.redirects +|= 1;
            return .{
                .state = .redirect,
                .redirect = .guest_return_predicate_edge,
                .cleared_target_source = input.cleared_target_source,
                .host_rip = input.predicate_edge_target,
            };
        }

        if (input.frame_pointer == 0 or
            input.frame_pointer > std.math.maxInt(u64) - 16 or
            input.frame_pointer & 7 != 0 or
            !input.saved_frame_pointer_valid or input.host_return == 0 or
            !input.host_return_executable or !input.host_return_not_guest)
        {
            return self.reject(.host_frame_not_proven);
        } // Both guest-side values are required. A host frame by itself is not
        // enough evidence: returning to GuestFunction::Call when the
        // CALL_POSSIBLE_RETURN predicate was not proven makes Xenia believe
        // that guest execution completed and can suppress the real failure
        // (including the GPU callback that the guest was supposed to signal).
        if (!input.guest_target_valid) {
            return self.reject(.guest_target_not_proven);
        }
        if (!input.guest_return_valid) {
            return self.reject(.guest_return_not_proven);
        }
        if (@as(u32, @truncate(input.guest_target)) !=
            @as(u32, @truncate(input.guest_return)))
        {
            return self.reject(.guest_target_not_return);
        }

        self.redirects +|= 1;
        return .{
            .state = .redirect,
            .redirect = .host_frame_return,
            .host_rip = input.host_return,
            .host_rsp = input.frame_pointer +| 16,
            .host_rbp = input.saved_frame_pointer,
        };
    }

    fn reject(self: *Machine, reason: RejectReason) Output {
        self.rejections +|= 1;
        return .{ .state = .reject, .reason = reason };
    }
};

test "bounded dispatch redirects only a fully proven missed guest return" {
    var machine = Machine{};
    const output = machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target_aliases_null_base = false,
        .cleared_target_retained = false,
        .cleared_target = 0,
        .cleared_target_source = .retained_history,
        .predicate_edge_target = 0xA0059878,
        .guest_target = 0x82582CC8,
        .guest_return = 0x82582CC8,
        .guest_target_valid = true,
        .guest_return_valid = true,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .branch_targets_dead_epilogue = true,
        .host_return_not_guest = true,
        .frame_pointer = 0x1A2D0BD0,
        .saved_frame_pointer = 0x1A2D1020,
        .saved_frame_pointer_valid = true,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expect(output.redirects());
    try std.testing.expectEqual(@as(u64, 0x27879C), output.host_rip);
    try std.testing.expectEqual(@as(u64, 0x1A2D0BE0), output.host_rsp);
    try std.testing.expectEqual(@as(u64, 0x1A2D1020), output.host_rbp);
    try std.testing.expectEqual(@as(u64, 1), machine.redirects);
}

test "bounded dispatch rejects a guest target that differs from the return" {
    var machine = Machine{};
    const output = machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target_aliases_null_base = false,
        .cleared_target_retained = false,
        .cleared_target = 0,
        .cleared_target_source = .retained_history,
        .predicate_edge_target = 0xA0059878,
        .guest_target = 0x82580000,
        .guest_return = 0x82582CC8,
        .guest_target_valid = true,
        .guest_return_valid = true,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .branch_targets_dead_epilogue = true,
        .host_return_not_guest = true,
        .frame_pointer = 0x1A2D0BD0,
        .saved_frame_pointer = 0x1A2D1020,
        .saved_frame_pointer_valid = true,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expectEqual(Machine.State.reject, output.state);
    try std.testing.expectEqual(Machine.RejectReason.guest_target_not_return, output.reason);
}

test "bounded dispatch rejects an unproven host continuation" {
    var machine = Machine{};
    const output = machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target_aliases_null_base = false,
        .cleared_target_retained = false,
        .cleared_target = 0,
        .cleared_target_source = .retained_history,
        .predicate_edge_target = 0xA0059878,
        .guest_target = 0x82582CC8,
        .guest_return = 0x82582CC8,
        .guest_target_valid = true,
        .guest_return_valid = true,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .branch_targets_dead_epilogue = true,
        .host_return_not_guest = true,
        .frame_pointer = 0x1A2D0BD0,
        .saved_frame_pointer = 0xDEAD,
        .saved_frame_pointer_valid = false,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expectEqual(Machine.State.reject, output.state);
    try std.testing.expectEqual(Machine.RejectReason.host_frame_not_proven, output.reason);
}

test "bounded dispatch rejects an unproven guest return even with a valid host frame" {
    var machine = Machine{};
    const output = machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target_aliases_null_base = false,
        .cleared_target_retained = false,
        .cleared_target = 0,
        .cleared_target_source = .retained_history,
        .predicate_edge_target = 0xA0059878,
        .guest_target = 0,
        .guest_return = 0x8467F0,
        .guest_target_valid = false,
        .guest_return_valid = false,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .branch_targets_dead_epilogue = true,
        .host_return_not_guest = true,
        .frame_pointer = 0x1A2D0BD0,
        .saved_frame_pointer = 0x1A2D1020,
        .saved_frame_pointer_valid = true,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expectEqual(Machine.State.reject, output.state);
    try std.testing.expectEqual(Machine.RejectReason.guest_target_not_proven, output.reason);
    try std.testing.expectEqual(@as(u64, 0), machine.redirects);
}

test "bounded dispatch requires guest return proof independently" {
    var machine = Machine{};
    const output = machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target_aliases_null_base = false,
        .cleared_target_retained = false,
        .cleared_target = 0,
        .cleared_target_source = .retained_history,
        .predicate_edge_target = 0xA0059878,
        .guest_target = 0x82582CC8,
        .guest_return = 0x82582CC8,
        .guest_target_valid = true,
        .guest_return_valid = false,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .branch_targets_dead_epilogue = true,
        .host_return_not_guest = true,
        .frame_pointer = 0x1A2D0BD0,
        .saved_frame_pointer = 0x1A2D1020,
        .saved_frame_pointer_valid = true,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expectEqual(Machine.State.reject, output.state);
    try std.testing.expectEqual(Machine.RejectReason.guest_return_not_proven, output.reason);
}

test "bounded dispatch requires a matching candidate independently" {
    var machine = Machine{};
    const output = machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target_aliases_null_base = false,
        .cleared_target_retained = false,
        .cleared_target = 0,
        .cleared_target_source = .retained_history,
        .predicate_edge_target = 0xA0059878,
        .guest_target = 0x82582CC8,
        .guest_return = 0x82582CC8,
        .guest_target_valid = false,
        .guest_return_valid = true,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .branch_targets_dead_epilogue = true,
        .host_return_not_guest = true,
        .frame_pointer = 0x1A2D0BD0,
        .saved_frame_pointer = 0x1A2D1020,
        .saved_frame_pointer_valid = true,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expectEqual(Machine.State.reject, output.state);
    try std.testing.expectEqual(Machine.RejectReason.guest_target_not_proven, output.reason);
}

// The state the runtime actually produces, reproduced field-for-field from the
// reported trace. Xenia emits `cmp ebx,[rsp+0x58]; je epilogue; mov eax,[ebx]`,
// so the comparison operand and the null base are the same register: no live
// value can testify about the target, and asking for a "valid guest target"
// made the redirect branch unreachable in its own layout. Retained history
// supplies the testimony instead, and the machine takes the guest's own edge.
test "null-base aliasing redirects along the guest predicate edge on retained proof" {
    var machine = Machine{};
    const output = machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target_aliases_null_base = true,
        .guest_target = 0,
        .guest_return = 0x82582CC8,
        .guest_target_valid = false,
        .guest_return_valid = true,
        .cleared_target_retained = true,
        .cleared_target = 0x82582CC8,
        .cleared_target_source = .retained_history,
        .predicate_edge_target = 0xA0059878,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .branch_targets_dead_epilogue = true,
        .host_return_not_guest = true,
        .frame_pointer = 0x1A2D08F0,
        .saved_frame_pointer = 0x1A2D0C90,
        .saved_frame_pointer_valid = true,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expect(output.redirects());
    try std.testing.expectEqual(Machine.Redirect.guest_return_predicate_edge, output.redirect);
    try std.testing.expectEqual(@as(u64, 0xA0059878), output.host_rip);
    try std.testing.expectEqual(@as(u64, 1), machine.redirects);
}

// The epilogue reached through the predicate edge performs its own teardown.
// Rewriting RSP/RBP on that path would deallocate the frame twice, so the
// caller must be told not to — and the host-frame path must still say yes.
test "only the host frame return rewrites the stack registers" {
    var machine = Machine{};
    const edge = machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target_aliases_null_base = true,
        .guest_target = 0,
        .guest_return = 0x82582CC8,
        .guest_target_valid = false,
        .guest_return_valid = true,
        .cleared_target_retained = true,
        .cleared_target = 0x82582CC8,
        .cleared_target_source = .retained_history,
        .predicate_edge_target = 0xA0059878,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .branch_targets_dead_epilogue = true,
        .host_return_not_guest = true,
        .frame_pointer = 0x1A2D08F0,
        .saved_frame_pointer = 0x1A2D0C90,
        .saved_frame_pointer_valid = true,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expect(edge.redirects());
    try std.testing.expect(!edge.rewritesStack());
    try std.testing.expectEqual(@as(u64, 0), edge.host_rsp);
    try std.testing.expectEqual(@as(u64, 0), edge.host_rbp);

    var host_machine = Machine{};
    const host = host_machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target_aliases_null_base = false,
        .guest_target = 0x82582CC8,
        .guest_return = 0x82582CC8,
        .guest_target_valid = true,
        .guest_return_valid = true,
        .cleared_target_retained = false,
        .cleared_target = 0,
        .cleared_target_source = .retained_history,
        .predicate_edge_target = 0xA0059878,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .branch_targets_dead_epilogue = true,
        .host_return_not_guest = true,
        .frame_pointer = 0x1A2D0BD0,
        .saved_frame_pointer = 0x1A2D1020,
        .saved_frame_pointer_valid = true,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expect(host.rewritesStack());
    try std.testing.expectEqual(@as(u64, 0x1A2D0BE0), host.host_rsp);
}

// History that never held the target is not evidence. Without it the aliasing
// case fails closed exactly as before, and no edge is taken.
test "null-base aliasing without retained history fails closed" {
    var machine = Machine{};
    const output = machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target_aliases_null_base = true,
        .guest_target = 0,
        .guest_return = 0x82582CC8,
        .guest_target_valid = false,
        .guest_return_valid = true,
        .cleared_target_retained = false,
        .cleared_target = 0,
        .cleared_target_source = .retained_history,
        .predicate_edge_target = 0xA0059878,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .branch_targets_dead_epilogue = true,
        .host_return_not_guest = true,
        .frame_pointer = 0x1A2D08F0,
        .saved_frame_pointer = 0x1A2D0C90,
        .saved_frame_pointer_valid = true,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expectEqual(Machine.State.reject, output.state);
    try std.testing.expectEqual(Machine.RejectReason.cleared_target_not_retained, output.reason);
    try std.testing.expectEqual(@as(u64, 0), machine.redirects);
}

// A register that held some other value before being cleared says nothing
// about a missed return. Recovering *a* value is not recovering *the* value.
test "null-base aliasing rejects a retained value that is not the guest return" {
    var machine = Machine{};
    const output = machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target_aliases_null_base = true,
        .guest_target = 0,
        .guest_return = 0x82582CC8,
        .guest_target_valid = false,
        .guest_return_valid = true,
        .cleared_target_retained = true,
        .cleared_target = 0x40,
        .cleared_target_source = .retained_history,
        .predicate_edge_target = 0xA0059878,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .branch_targets_dead_epilogue = true,
        .host_return_not_guest = true,
        .frame_pointer = 0x1A2D08F0,
        .saved_frame_pointer = 0x1A2D0C90,
        .saved_frame_pointer_valid = true,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expectEqual(Machine.State.reject, output.state);
    try std.testing.expectEqual(Machine.RejectReason.cleared_target_not_guest_return, output.reason);
}

// The shape gates still run first: a run with no proven tail dispatch is not
// in this layout at all, and the retained-history route must not rescue it.
test "null-base aliasing still requires the dispatch shape" {
    var machine = Machine{};
    const output = machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target_aliases_null_base = true,
        .guest_target = 0,
        .guest_return = 0x82582CC8,
        .guest_target_valid = false,
        .guest_return_valid = true,
        .cleared_target_retained = true,
        .cleared_target = 0x82582CC8,
        .cleared_target_source = .retained_history,
        .predicate_edge_target = 0xA0059878,
        .tail_jmp_rax_found = false,
        .dead_epilogue_found = false,
        .branch_targets_dead_epilogue = false,
        .host_return_not_guest = true,
        .frame_pointer = 0x1A2D08F0,
        .saved_frame_pointer = 0x1A2D0C90,
        .saved_frame_pointer_valid = true,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expectEqual(Machine.State.reject, output.state);
    try std.testing.expectEqual(Machine.RejectReason.tail_transfer_not_proven, output.reason);
    try std.testing.expectEqual(@as(u64, 0), machine.redirects);
}

// A non-aliasing layout (Xenia moved the target into the base register from a
// different one, so the comparison operand survives the fault) still reaches
// the redirect. This is the case the machine exists for, and it must not
// regress when the aliasing gate is added ahead of it.
test "bounded dispatch still redirects when the compared target is a distinct register" {
    var machine = Machine{};
    const output = machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target_aliases_null_base = false,
        .cleared_target_retained = false,
        .cleared_target = 0,
        .cleared_target_source = .retained_history,
        .predicate_edge_target = 0xA0059878,
        .guest_target = 0x82582CC8,
        .guest_return = 0x82582CC8,
        .guest_target_valid = true,
        .guest_return_valid = true,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .branch_targets_dead_epilogue = true,
        .host_return_not_guest = true,
        .frame_pointer = 0x1A2D0BD0,
        .saved_frame_pointer = 0x1A2D1020,
        .saved_frame_pointer_valid = true,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expect(output.redirects());
    try std.testing.expectEqual(@as(u64, 1), machine.redirects);
}
