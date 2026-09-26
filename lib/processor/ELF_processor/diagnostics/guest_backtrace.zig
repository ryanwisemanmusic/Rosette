//! A guest call chain recovered from the stack alone.
//!
//! The PE runner keeps no shadow call stack in a normal run (the ABI tracer
//! that does is off by default), and MinGW code does not keep frame
//! pointers, so the only record of how a guest thread reached its terminal
//! instruction is the return addresses its calls left on its stack. This
//! scans the stack from `rsp` upward and keeps a word only when it is a
//! plausible return address: it points into executable guest code, and the
//! bytes just before it decode as a `call` that ends exactly there. Stale
//! return addresses of calls that have already returned can still pass that
//! test, so a frame is evidence of a call site, not proof it is live; the
//! nearest frames to `rsp` are the ones to trust first.

const std = @import("std");

pub const CallForm = enum(u8) {
    /// `E8 rel32`.
    direct,
    /// `FF /2` with a register operand.
    indirect_register,
    /// `FF /2` with a memory operand, `[rip+disp]` included.
    indirect_memory,
};

pub const Frame = struct {
    /// Where on the stack the return address was found.
    slot_address: u64,
    return_address: u64,
    /// The first byte of the call instruction.
    call_site: u64,
    form: CallForm,
    /// For a direct call, where it went; zero otherwise.
    direct_target: u64 = 0,
};

/// The call instruction, if any, that ends exactly at the end of `before`.
/// `before` holds the bytes immediately preceding a candidate return address,
/// oldest first.
pub fn callEndingAt(before: []const u8) ?struct { length: u8, form: CallForm, rel32: i32 } {
    if (before.len >= 5 and before[before.len - 5] == 0xE8) {
        const rel = std.mem.readInt(i32, before[before.len - 4 ..][0..4], .little);
        return .{ .length = 5, .form = .direct, .rel32 = rel };
    }
    // FF /2 is 2 to 7 bytes, plus an optional REX prefix.
    var length: usize = 2;
    while (length <= 8 and length <= before.len) : (length += 1) {
        const start = before.len - length;
        var cursor = start;
        if (before[cursor] >= 0x40 and before[cursor] <= 0x4F) cursor += 1;
        if (cursor + 2 > before.len or before[cursor] != 0xFF) continue;
        const modrm = before[cursor + 1];
        if ((modrm >> 3) & 7 != 2) continue;
        const mode = modrm >> 6;
        const rm = modrm & 7;
        var encoded: usize = (cursor - start) + 2;
        if (mode != 3) {
            if (rm == 4) {
                if (cursor + 3 > before.len) continue;
                const sib = before[cursor + 2];
                encoded += 1;
                if (mode == 0 and (sib & 7) == 5) encoded += 4;
            } else if (mode == 0 and rm == 5) {
                encoded += 4; // [rip+disp32]
            }
            if (mode == 1) encoded += 1;
            if (mode == 2) encoded += 4;
        }
        if (encoded != length) continue;
        // `FF D3` is `call rbx` and `41 FF D3` is `call r11`; both end here.
        // A REX byte just before an unprefixed match is taken as its prefix,
        // which is how every call through r8-r15 is encoded.
        var total = length;
        if (cursor == start and start > 0 and before[start - 1] >= 0x40 and before[start - 1] <= 0x4F) total += 1;
        return .{ .length = @intCast(total), .form = if (mode == 3) .indirect_register else .indirect_memory, .rel32 = 0 };
    }
    return null;
}

/// Scan `words`, the stack contents from `rsp` upward, for return
/// addresses. `probe` answers `isCode(address) bool` and
/// `bytesBefore(address, *[8]u8) ?[]const u8` (the up-to-eight bytes that end
/// at `address`). Returns the number of frames written.
pub fn scan(probe: anytype, rsp: u64, words: []const u64, frames: []Frame) usize {
    var found: usize = 0;
    for (words, 0..) |word, index| {
        if (found == frames.len) break;
        if (word < 8 or !probe.isCode(word)) continue;
        var storage: [8]u8 = undefined;
        const before = probe.bytesBefore(word, &storage) orelse continue;
        const call = callEndingAt(before) orelse continue;
        const call_site = word - call.length;
        if (!probe.isCode(call_site)) continue;
        var frame = Frame{
            .slot_address = rsp +% @as(u64, @intCast(index)) *% 8,
            .return_address = word,
            .call_site = call_site,
            .form = call.form,
        };
        if (call.form == .direct) {
            const target = @as(i64, @bitCast(word)) +% call.rel32;
            frame.direct_target = @bitCast(target);
            // A direct call into data is not a call this code made.
            if (!probe.isCode(frame.direct_target)) continue;
        }
        frames[found] = frame;
        found += 1;
    }
    return found;
}

const TestImage = struct {
    base: u64,
    bytes: []const u8,

    fn isCode(self: TestImage, address: u64) bool {
        return address >= self.base and address < self.base + self.bytes.len;
    }

    fn bytesBefore(self: TestImage, address: u64, storage: *[8]u8) ?[]const u8 {
        if (!self.isCode(address) and address != self.base + self.bytes.len) return null;
        const offset: usize = @intCast(address - self.base);
        const count = @min(offset, storage.len);
        @memcpy(storage[0..count], self.bytes[offset - count .. offset]);
        return storage[0..count];
    }
};

test "call encodings are recognised by the instruction that ends at the return address" {
    // call rel32
    try std.testing.expectEqual(CallForm.direct, callEndingAt(&.{ 0x90, 0xE8, 0x10, 0x00, 0x00, 0x00 }).?.form);
    // call rax / call r11
    try std.testing.expectEqual(CallForm.indirect_register, callEndingAt(&.{ 0x90, 0xFF, 0xD0 }).?.form);
    try std.testing.expectEqual(@as(u8, 3), callEndingAt(&.{ 0x90, 0x41, 0xFF, 0xD3 }).?.length);
    // call [rip+disp32]
    try std.testing.expectEqual(@as(u8, 6), callEndingAt(&.{ 0x90, 0xFF, 0x15, 0x11, 0x22, 0x33, 0x44 }).?.length);
    // call [rax+0x18]
    try std.testing.expectEqual(CallForm.indirect_memory, callEndingAt(&.{ 0x90, 0xFF, 0x50, 0x18 }).?.form);
    // call [rsp+8] (SIB, disp8)
    try std.testing.expectEqual(@as(u8, 4), callEndingAt(&.{ 0x90, 0xFF, 0x54, 0x24, 0x08 }).?.length);
    // jmp rax (FF /4) is not a call
    try std.testing.expect(callEndingAt(&.{ 0x90, 0xFF, 0xE0 }) == null);
    try std.testing.expect(callEndingAt(&.{ 0x90, 0x90, 0x90 }) == null);
}

test "a stack scan keeps return addresses after real calls and skips data" {
    // 0x1000: call 0x1010 ; 0x1005: nop ... ; 0x1010: call [rax+0x18] ; 0x1013: ret
    var code = [_]u8{0x90} ** 0x20;
    code[0] = 0xE8;
    std.mem.writeInt(i32, code[1..5], 0x0B, .little); // 0x1005 + 0x0B = 0x1010
    code[0x10] = 0xFF;
    code[0x11] = 0x50;
    code[0x12] = 0x18;
    const image = TestImage{ .base = 0x1000, .bytes = &code };
    const stack = [_]u64{
        0xDEAD_BEEF, // not code
        0x1013, // after call [rax+0x18]
        0x1008, // code, but no call ends there
        0x1005, // after call rel32
        0x0,
    };
    var frames: [4]Frame = undefined;
    const count = scan(image, 0x7000, &stack, &frames);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(@as(u64, 0x1013), frames[0].return_address);
    try std.testing.expectEqual(@as(u64, 0x1010), frames[0].call_site);
    try std.testing.expectEqual(CallForm.indirect_memory, frames[0].form);
    try std.testing.expectEqual(@as(u64, 0x7008), frames[0].slot_address);
    try std.testing.expectEqual(@as(u64, 0x1005), frames[1].return_address);
    try std.testing.expectEqual(@as(u64, 0x1010), frames[1].direct_target);
}
