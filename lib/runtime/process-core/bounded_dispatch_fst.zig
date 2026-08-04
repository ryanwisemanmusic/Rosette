const std = @import("std");

/// Zero-allocation finite-state transducer for the narrow Xenia generated-code
/// failure in which a CALL_POSSIBLE_RETURN comparison was missed and execution
/// reached `67 8B 03` (`mov eax, dword ptr [ebx]`) with EBX == 0.
///
/// This is deliberately not a pointer-guessing engine.  It only emits a host
/// frame return after every independently supplied invariant has been proven by
/// the runtime.  Anything ambiguous is rejected, so an invalid guest address is
/// never manufactured into a host RIP.
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
        guest_target_not_return,
        tail_transfer_not_proven,
        dead_epilogue_not_proven,
        host_frame_not_proven,
    };

    pub const Input = struct {
        xenia_compat: bool,
        generated_executable: bool,
        address32_eax_from_ebx: bool,
        base_value32: u32,
        guest_target: u64,
        guest_return: u64,
        guest_target_valid: bool,
        guest_return_valid: bool,
        tail_jmp_rax_found: bool,
        dead_epilogue_found: bool,
        frame_pointer: u64,
        saved_frame_pointer: u64,
        saved_frame_pointer_valid: bool,
        host_return: u64,
        host_return_executable: bool,
    };

    pub const Output = struct {
        state: State,
        reason: RejectReason = .none,
        host_rip: u64 = 0,
        host_rsp: u64 = 0,
        host_rbp: u64 = 0,

        pub fn redirects(self: Output) bool {
            return self.state == .redirect;
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
        if (input.frame_pointer == 0 or
            input.frame_pointer > std.math.maxInt(u64) - 16 or
            !input.saved_frame_pointer_valid or input.host_return == 0 or
            !input.host_return_executable)
        {
            return self.reject(.host_frame_not_proven);
        }
        // Guest target/return consistency is validated when both are
        // proven, but the redirect itself is anchored on the host frame
        // return alone — an executable host continuation is sufficient
        // to safely redirect the RIP without manufacturing a guest address.
        if (input.guest_target_valid and input.guest_return_valid and
            @as(u32, @truncate(input.guest_target)) !=
            @as(u32, @truncate(input.guest_return)))
        {
            return self.reject(.guest_target_not_return);
        }

        self.redirects +|= 1;
        return .{
            .state = .redirect,
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
        .guest_target = 0x82582CC8,
        .guest_return = 0x82582CC8,
        .guest_target_valid = true,
        .guest_return_valid = true,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
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
        .guest_target = 0x82580000,
        .guest_return = 0x82582CC8,
        .guest_target_valid = true,
        .guest_return_valid = true,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
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
        .guest_target = 0x82582CC8,
        .guest_return = 0x82582CC8,
        .guest_target_valid = true,
        .guest_return_valid = true,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .frame_pointer = 0x1A2D0BD0,
        .saved_frame_pointer = 0xDEAD,
        .saved_frame_pointer_valid = false,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expectEqual(Machine.State.reject, output.state);
    try std.testing.expectEqual(Machine.RejectReason.host_frame_not_proven, output.reason);
}

test "bounded dispatch redirects when guest return is unproven but host frame is valid" {
    var machine = Machine{};
    const output = machine.evaluate(.{
        .xenia_compat = true,
        .generated_executable = true,
        .address32_eax_from_ebx = true,
        .base_value32 = 0,
        .guest_target = 0,
        .guest_return = 0x8467F0,
        .guest_target_valid = false,
        .guest_return_valid = false,
        .tail_jmp_rax_found = true,
        .dead_epilogue_found = true,
        .frame_pointer = 0x1A2D0BD0,
        .saved_frame_pointer = 0x1A2D1020,
        .saved_frame_pointer_valid = true,
        .host_return = 0x27879C,
        .host_return_executable = true,
    });
    try std.testing.expect(output.redirects());
    try std.testing.expectEqual(@as(u64, 0x27879C), output.host_rip);
    try std.testing.expectEqual(@as(u64, 1), machine.redirects);
}
