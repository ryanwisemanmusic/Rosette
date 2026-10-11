//! Narrow recovery for Xenia's XMutant destructor re-entering a
//! Win32Mutant backing allocation whose base destructor has already begun.
//!
//! The shim is admitted only when the exact XMutant deleting-destructor call
//! would dispatch to Win32Handle<Mutant>'s intentional UD2, the parent still
//! contains that exact pointer, and the allocation is exactly the 16-byte
//! backing object with a null handle and intact guard. Either its heap
//! tombstone records an earlier XMutant deleting-destructor free, or the
//! allocation is still active because another destructor is between the
//! base-vtable transition and operator delete. The instruction immediately
//! after the call clears the unique_ptr member, so leaving RSP and registers
//! untouched completes the duplicate teardown without issuing another delete.

const std = @import("std");

const xmutant_symbol = "xe::kernel::XMutant";
const xmutant_d0_mangled = "_ZN2xe6kernel7XMutantD0Ev";
const xmutant_d1_mangled = "_ZN2xe6kernel7XMutantD1Ev";
const win32_handle_symbol = "xe::threading::Win32Handle";
const win32_handle_d0_mangled = "_ZN2xe9threading11Win32HandleINS0_6MutantEED0Ev";

pub const destructor_call_offset: u64 = 0x1e;
pub const destructor_return_offset: u64 = 0x21;
pub const backing_member_offset: u64 = 0x60;

const call_bytes = [_]u8{ 0xff, 0x50, 0x08 }; // call qword ptr [rax + 8]
const continuation_bytes = [_]u8{ 0x48, 0xc7, 0x46, 0x60, 0, 0, 0, 0 }; // mov qword ptr [rsi + 0x60], 0
const ud2_bytes = [_]u8{ 0x0f, 0x0b };

pub const Evidence = struct {
    callsite_symbol: []const u8,
    callsite_offset: u64,
    call_instruction: []const u8,
    continuation_instruction: []const u8,
    owner_member_matches_backing: bool,
    object_vtable_matches_loaded_vtable: bool,
    target_symbol: []const u8,
    target_offset: u64,
    target_instruction: []const u8,
    vtable_slot_matches_target: bool,
    allocation_active: bool,
    allocation_length: u64,
    backing_handle_is_null: bool,
    allocation_guard_intact: bool,
    prior_free_symbol: []const u8,
    prior_free_offset: u64,
};

fn isXMutantSymbol(name: []const u8) bool {
    return std.mem.eql(u8, name, xmutant_symbol) or
        std.mem.eql(u8, name, xmutant_d0_mangled) or
        std.mem.eql(u8, name, xmutant_d1_mangled);
}

fn isWin32HandleMutantDeletingDestructor(name: []const u8) bool {
    return std.mem.eql(u8, name, win32_handle_symbol) or
        std.mem.eql(u8, name, win32_handle_d0_mangled);
}

/// Cheaply reject ordinary indirect calls before touching guest heap memory
/// or taking the runtime metadata lock.
pub fn matchesDestructorCallsite(
    callsite_symbol: []const u8,
    callsite_offset: u64,
    call_instruction: []const u8,
    continuation_instruction: []const u8,
) bool {
    return isXMutantSymbol(callsite_symbol) and
        callsite_offset == destructor_call_offset and
        call_instruction.len >= call_bytes.len and
        std.mem.eql(u8, call_instruction[0..call_bytes.len], &call_bytes) and
        continuation_instruction.len >= continuation_bytes.len and
        std.mem.eql(u8, continuation_instruction[0..continuation_bytes.len], &continuation_bytes);
}

pub fn shouldSkipRepeatedBackingDelete(evidence: Evidence) bool {
    const exact_callsite = matchesDestructorCallsite(
        evidence.callsite_symbol,
        evidence.callsite_offset,
        evidence.call_instruction,
        evidence.continuation_instruction,
    );
    const freed_by_xmutant_dtor = !evidence.allocation_active and
        isXMutantSymbol(evidence.prior_free_symbol) and
        evidence.prior_free_offset == destructor_return_offset;
    const destructor_in_progress = evidence.allocation_active;
    return exact_callsite and
        evidence.owner_member_matches_backing and
        evidence.object_vtable_matches_loaded_vtable and
        isWin32HandleMutantDeletingDestructor(evidence.target_symbol) and
        evidence.target_offset == 0 and
        evidence.target_instruction.len >= ud2_bytes.len and
        std.mem.eql(u8, evidence.target_instruction[0..ud2_bytes.len], &ud2_bytes) and
        evidence.vtable_slot_matches_target and
        evidence.allocation_length == 0x10 and
        evidence.backing_handle_is_null and
        evidence.allocation_guard_intact and
        (freed_by_xmutant_dtor or destructor_in_progress);
}

test "only an exact repeat XMutant delete in a verified base-destructor state is skipped" {
    const valid = Evidence{
        .callsite_symbol = xmutant_symbol,
        .callsite_offset = destructor_call_offset,
        .call_instruction = &call_bytes,
        .continuation_instruction = &continuation_bytes,
        .owner_member_matches_backing = true,
        .object_vtable_matches_loaded_vtable = true,
        .target_symbol = win32_handle_symbol,
        .target_offset = 0,
        .target_instruction = &ud2_bytes,
        .vtable_slot_matches_target = true,
        .allocation_active = false,
        .allocation_length = 0x10,
        .backing_handle_is_null = true,
        .allocation_guard_intact = true,
        .prior_free_symbol = xmutant_symbol,
        .prior_free_offset = destructor_return_offset,
    };
    try std.testing.expect(shouldSkipRepeatedBackingDelete(valid));

    var changed = valid;
    changed.callsite_offset += 1;
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.call_instruction = &.{ 0xff, 0x50, 0x10 };
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.continuation_instruction = &.{ 0x48, 0xc7, 0x46, 0x68, 0, 0, 0, 0 };
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.owner_member_matches_backing = false;
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.object_vtable_matches_loaded_vtable = false;
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.target_symbol = "xe::threading::Win32Handle<xe::threading::Event>";
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.target_offset = 1;
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.target_instruction = &.{ 0x90, 0x90 };
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.vtable_slot_matches_target = false;
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.allocation_active = true;
    try std.testing.expect(shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.allocation_length = 8;
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.backing_handle_is_null = false;
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.allocation_guard_intact = false;
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.prior_free_offset -= 1;
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
    changed = valid;
    changed.prior_free_symbol = "xe::kernel::XEvent";
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));

    // A second destructor can arrive while the first is still running. The
    // object is still allocated then, but its base vtable and cleared handle
    // prove the native teardown has already entered its terminal phase.
    changed = valid;
    changed.allocation_active = true;
    changed.prior_free_symbol = "";
    changed.prior_free_offset = 0;
    try std.testing.expect(shouldSkipRepeatedBackingDelete(changed));
    changed.backing_handle_is_null = false;
    try std.testing.expect(!shouldSkipRepeatedBackingDelete(changed));
}
