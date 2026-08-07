//! What a generated tail dispatch looks like.
//!
//! This is one coherent behaviour — "recognise the emitter's indirect-dispatch
//! shape" — that was previously spread across `boundedTailShape`,
//! `branchTargetsDeadDispatchEpilogue`, `isFunctionExitEpilogueBytes` and the
//! gating inside two transfer recoveries, in two files, with no single place
//! stating what the shape *is*. Each piece was individually correct and
//! collectively unstated, so a change to one had no obvious relationship to the
//! others.
//!
//! The shape being recognised:
//!
//! ```text
//!     cmp   target32, [rsp+disp]     ; CALL_POSSIBLE_RETURN predicate
//!     je    epilogue                 ; taken when the call is really a return
//!     mov   eax, dword [base]        ; indirection-table lookup  <- fault site
//!     ...                            ; argument reload, frame teardown
//!     jmp   rax                      ; tail transfer
//!   epilogue:
//!     add   rsp, imm                 ; function exit, reachable only via je
//!     [dec  dword [reg-imm]]         ; optional profiler decrement
//!     ret
//! ```
//!
//! The epilogue is *dead* on the fall-through path — the teardown has already
//! run before the transfer — so falling into it double-deallocates the frame
//! and `ret` pops a local. It is *live* on the `je` path. Same bytes, opposite
//! meanings, decided entirely by how they were reached. That distinction is the
//! reason this recognizer exists, and keeping it in one place is the reason it
//! stays correct.

const std = @import("std");

/// Byte-level recognizer for the function-exit epilogue: `add rsp, imm8/32`,
/// optional `dec dword [reg-imm8]` repetitions, then `ret`.
///
/// Pure so it is testable without a machine state. Length guards precede every
/// byte read, so a truncated mapping slice cannot index out of bounds.
pub fn isFunctionExitEpilogue(bytes: []const u8) bool {
    if (bytes.len < 4) return false;
    var offset: usize = 0;
    if (bytes[0] == 0x48 and bytes[1] == 0x83 and bytes[2] == 0xC4) {
        offset = 4; // add rsp, imm8
    } else if (bytes[0] == 0x48 and bytes[1] == 0x81 and bytes[2] == 0xC4) {
        // REX.W + 81 /0 id: 1 + 1 + 1 modrm + 4 imm32 = 7 bytes.
        //
        // This was 8 in the original, which skipped past the `ret` and made the
        // imm32 form permanently unrecognisable. Any generated function whose
        // frame exceeds an imm8 (>127 bytes) therefore failed the
        // `dead_epilogue` proof, and every recovery gated on it — the dispatch
        // transducer and both transfer recoveries — refused those frames for a
        // reason that had nothing to do with the guest. Found by writing the
        // encodings down as tests while extracting this recognizer.
        offset = 7; // add rsp, imm32
    } else {
        return false;
    }
    if (bytes.len <= offset) return false;
    var index = offset;
    while (index + 3 <= bytes.len) {
        if (index + 4 <= bytes.len and bytes[index] == 0x48 and
            bytes[index + 1] == 0xFF and bytes[index + 2] == 0x4E)
        {
            index += 4; // REX.W dec dword [rsi-imm8]
            continue;
        }
        if (bytes[index] == 0xFF and bytes[index + 1] == 0x4E) {
            index += 3; // dec dword [rsi-imm8]
            continue;
        }
        break;
    }
    return index < bytes.len and bytes[index] == 0xC3;
}

/// Does the predicate's conditional branch land exactly on the first byte after
/// the tail transfer — i.e. on the epilogue this shape identified?
///
/// Requiring *exact* equality is what keeps this a recognizer rather than a
/// guess: a branch that lands anywhere else is a different control-flow edge,
/// and authorising a transfer on it would be inventing one.
pub fn branchTargetsEpilogue(branch_target: u64, transfer_rip: u64, transfer_len: u8) bool {
    return branch_target != 0 and transfer_rip != 0 and transfer_len != 0 and
        branch_target == transfer_rip +| transfer_len;
}

/// Everything the recognizer concluded about one candidate dispatch.
pub const Shape = struct {
    /// Address of the tail transfer instruction.
    transfer_rip: u64 = 0,
    transfer_len: u8 = 0,
    /// Distance in bytes from the faulting load to the transfer.
    transfer_distance: u8 = 0,
    /// The transfer is `jmp rax`, the emitter's indirection dispatch.
    jmp_rax: bool = false,
    /// The bytes after the transfer are a function-exit epilogue.
    dead_epilogue: bool = false,
    /// A `mov r64,[rsp+disp]` was seen between the load and the transfer: the
    /// guest return being reloaded for the callee. Independent confirmation of
    /// the stack displacement the predicate compared against.
    return_slot_reload_seen: bool = false,
    return_slot_reload_offset: u64 = 0,

    /// The full tail shape was recognised. Anything less is not this pattern
    /// and must not be treated as one.
    pub fn recognised(self: Shape) bool {
        return self.transfer_rip != 0 and self.jmp_rax and self.dead_epilogue;
    }

    /// The predicate branch lands on the epilogue this shape found.
    pub fn confirms(self: Shape, branch_target: u64) bool {
        return branchTargetsEpilogue(branch_target, self.transfer_rip, self.transfer_len);
    }
};

test "the canonical epilogue forms are recognised" {
    // add rsp, 0x68 ; ret
    try std.testing.expect(isFunctionExitEpilogue(&[_]u8{ 0x48, 0x83, 0xC4, 0x68, 0xC3 }));
    // add rsp, 0x68 ; dec dword [rsi-0x14] ; ret  (the form in the live trace)
    try std.testing.expect(isFunctionExitEpilogue(&[_]u8{ 0x48, 0x83, 0xC4, 0x68, 0xFF, 0x4E, 0xEC, 0xC3 }));
    // REX.W profiler decrement
    try std.testing.expect(isFunctionExitEpilogue(&[_]u8{ 0x48, 0x83, 0xC4, 0x68, 0x48, 0xFF, 0x4E, 0xEC, 0xC3 }));
    // add rsp, imm32 ; ret
    try std.testing.expect(isFunctionExitEpilogue(&[_]u8{ 0x48, 0x81, 0xC4, 0x00, 0x01, 0x00, 0x00, 0xC3 }));
}

test "non-epilogues and truncated slices are rejected without reading past the end" {
    try std.testing.expect(!isFunctionExitEpilogue(&[_]u8{}));
    try std.testing.expect(!isFunctionExitEpilogue(&[_]u8{ 0x48, 0x83, 0xC4 }));
    // add rsp with no ret in the slice
    try std.testing.expect(!isFunctionExitEpilogue(&[_]u8{ 0x48, 0x83, 0xC4, 0x68 }));
    // jmp rax is not an epilogue
    try std.testing.expect(!isFunctionExitEpilogue(&[_]u8{ 0xFF, 0xE0, 0x00, 0x00 }));
}

test "the branch must land exactly after the transfer" {
    // Live trace: jmp rax at 0xa0059876 (2 bytes), epilogue at 0xa0059878.
    try std.testing.expect(branchTargetsEpilogue(0xa0059878, 0xa0059876, 2));
    try std.testing.expect(!branchTargetsEpilogue(0xa0059879, 0xa0059876, 2));
    try std.testing.expect(!branchTargetsEpilogue(0xa0059878, 0, 2));
    try std.testing.expect(!branchTargetsEpilogue(0, 0xa0059876, 2));
    try std.testing.expect(!branchTargetsEpilogue(0xa0059878, 0xa0059876, 0));
}

test "a shape missing any component is not recognised" {
    const complete = Shape{
        .transfer_rip = 0xa0059876,
        .transfer_len = 2,
        .jmp_rax = true,
        .dead_epilogue = true,
    };
    try std.testing.expect(complete.recognised());
    try std.testing.expect(complete.confirms(0xa0059878));

    var no_epilogue = complete;
    no_epilogue.dead_epilogue = false;
    try std.testing.expect(!no_epilogue.recognised());

    var indirect_other_reg = complete;
    indirect_other_reg.jmp_rax = false;
    try std.testing.expect(!indirect_other_reg.recognised());
}
