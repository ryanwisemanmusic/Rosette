//! Cache decoded CALL candidates, never their resolved target. Live bytes,
//! register operands and memory targets are checked on every request.
const process = @import("../../process.zig");
const I = process.__ProcessInternals;
const std = I._std;
const memory = @import("guest_memory.zig");
const instructions = @import("instruction_decode.zig");
const execution = @import("execution.zig");
const life = @import("lifecycle.zig");
const jit = @import("block_jit.zig");
const metadata = @import("import_metadata.zig");
const Site = I._WindowsImportCallsite;
const Entry = struct {
    owner: usize = 0,
    return_rip: u64 = 0,
    bytes: [15]u8 = undefined,
    candidates: [3]Site = undefined,
    count: usize = 0,
    through: u8 = 0,
};
threadlocal var entries: [64]Entry = @splat(.{});
pub const retained_bytes = @sizeOf(@TypeOf(entries));
pub threadlocal var enabled = true; // differential fixture control only

fn matches(self: *process.ElfState, site: Site, target: u64) bool {
    const d = site.decoded;
    if (d.op == .call_reg64) return execution.regVal(self, d.dst_reg, .bits64) == target;
    const regs = life.guestContextField(self, "regs").*;
    const operand = I._x64_decoder.resolveMemoryAddress(&regs, .{
        .displacement = d.addr,
        .has_index = d.sib_has_index,
        .index_reg = d.sib_index_reg,
        .scale = d.sib_scale,
        .has_base = d.sib_has_base,
        .base_reg = d.sib_base_reg,
        .rip_relative = d.rip_relative,
        .segment = d.segment,
    }, site.rip +| d.len, if (d.has_0x67) .bits32 else .bits64, .long64, true);
    return memory.read64(self, operand) == target;
}

pub fn find(self: *process.ElfState, return_rip: u64, target: u64) ?Site {
    const stats = metadata.forState(self);
    stats.callsites +|= 1;
    if (!enabled or return_rip < 15 or self.diagnose_abi or self.block_jit_verify_memory or
        self.trace_calls or self.trace_write_address != null or self.windowsMemoryTraceLive() or jit.blockJitTracingActive(self))
    {
        stats.callsite_fallbacks +|= 1;
        return legacy(self, return_rip, target);
    }
    var source: [16]u8 = undefined;
    const available = instructions.guestInstructionBytes(self, return_rip - 15, &source);
    if (available.len < 15) {
        stats.callsite_fallbacks +|= 1;
        return legacy(self, return_rip, target);
    }
    const bytes = available[0..15];
    const owner = @intFromPtr(self);
    const hash = (return_rip ^ (@as(u64, @intCast(owner)) >> 4)) *% 0x9E3779B97F4A7C15;
    const entry = &entries[@intCast(hash >> 58)];
    if (entry.owner == owner and entry.return_rip == return_rip and std.mem.eql(u8, &entry.bytes, bytes)) {
        stats.callsite_hits +|= 1;
        for (entry.candidates[0..entry.count]) |site| if (matches(self, site, target)) return site;
        if (entry.through == 15) return null;
    } else {
        entry.owner = owner;
        entry.return_rip = return_rip;
        @memcpy(&entry.bytes, bytes);
        entry.count = 0;
        entry.through = 0;
    }
    stats.callsite_rebuilds +|= 1;
    var length = entry.through + 1;
    var cacheable = true;
    while (length <= 15) : (length += 1) {
        const d = I._decodeInsn(bytes[15 - length .. 15]);
        entry.through = length;
        if (d.len != length or (d.op != .call_reg64 and d.op != .call_mem64)) continue;
        const site: Site = .{ .rip = return_rip - length, .decoded = d };
        if (entry.count < entry.candidates.len) {
            entry.candidates[entry.count] = site;
            entry.count += 1;
        } else {
            // Unusual prefix nesting keeps the exact scan result but cannot
            // leave a truncated candidate set for the next target value.
            cacheable = false;
            entry.owner = 0;
        }
        if (matches(self, site, target)) return site;
    }
    if (!cacheable) entry.owner = 0;
    return null;
}

pub fn legacy(self: *process.ElfState, return_rip: u64, target: u64) ?Site {
    // Import telemetry used `last_instruction_rip`, which translated
    // blocks do not necessarily refresh for every native transfer. Read
    // backwards from the architectural return address and accept only a
    // decoded CALL whose operand currently resolves to this exact stub.
    // The bounded scan covers every x86-64 instruction encoding length.
    var length: u8 = 1;
    while (length <= 15) : (length += 1) {
        if (return_rip < length) continue;
        const rip = return_rip - length;
        var bytes: [16]u8 = undefined;
        const available = instructions.guestInstructionBytes(self, rip, &bytes);
        if (available.len < length) continue;
        const decoded = I._decodeInsn(available);
        if (decoded.len != length) continue;
        switch (decoded.op) {
            .call_reg64 => {
                if (execution.regVal(self, decoded.dst_reg, .bits64) == target) return .{ .rip = rip, .decoded = decoded };
            },
            .call_mem64 => {
                const regs = life.guestContextField(self, "regs").*;
                const operand = I._x64_decoder.resolveMemoryAddress(&regs, .{
                    .displacement = decoded.addr,
                    .has_index = decoded.sib_has_index,
                    .index_reg = decoded.sib_index_reg,
                    .scale = decoded.sib_scale,
                    .has_base = decoded.sib_has_base,
                    .base_reg = decoded.sib_base_reg,
                    .rip_relative = decoded.rip_relative,
                    .segment = decoded.segment,
                }, rip +| decoded.len, if (decoded.has_0x67) .bits32 else .bits64, .long64, true);
                if (memory.read64(self, operand) == target) return .{ .rip = rip, .decoded = decoded };
            },
            else => {},
        }
    }
    return null;
}
