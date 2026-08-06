const std = @import("std");
const model = @import("abi/model.zig");
const validate = @import("abi/validate.zig");
const runtime_abi = @import("runtime_abi_handshake");

pub const JwasmAbiHandshake = struct {
    allocator: std.mem.Allocator,
    validator: validate.AssemblerValidator,
    sequence: u64 = 0,
    event_log: std.ArrayListUnmanaged(model.AssemblerEventRecord) = .{ .items = &.{}, .capacity = 0 },

    pub fn init(allocator: std.mem.Allocator) JwasmAbiHandshake {
        runtime_abi.common.writeLine("[jwasm][abi-handshake] init\n", .{});
        return JwasmAbiHandshake{
            .allocator = allocator,
            .validator = validate.AssemblerValidator.init(allocator),
        };
    }

    pub fn deinit(self: *JwasmAbiHandshake) void {
        for (self.event_log.items) |ev| self.allocator.free(ev.detail);
        self.event_log.deinit(self.allocator);
        runtime_abi.common.writeLine("[jwasm][abi-handshake] deinit violations={d}\n", .{self.validator.error_count});
    }

    pub fn onEvent(self: *JwasmAbiHandshake, event: model.AssemblerEvent, domain: model.ValidationDomain, address: u64, detail: []const u8) !void {
        self.sequence += 1;
        const ev = model.AssemblerEventRecord{
            .event = event,
            .domain = domain,
            .pass = 1,
            .address = address,
            .detail = try self.allocator.dupe(u8, detail),
        };
        try self.event_log.append(self.allocator, ev);
    }

    pub fn validateOutput(self: *JwasmAbiHandshake, bytes: []const u8) void {
        self.validator.validateOutputSize(bytes.len, 1024 * 1024 * 16, "jwasm output");
        if (bytes.len > 0) {
            self.validator.validateInstruction(bytes, 0);
        }
        if (self.validator.error_count > 0) {
            runtime_abi.common.violation("jwasm-abivalidate", "output_validation_failed", "errors={d}", .{self.validator.error_count});
        }
    }

    pub fn flushEventLog(self: *JwasmAbiHandshake) void {
        for (self.event_log.items) |ev| {
            runtime_abi.common.writeLine(
                "[jwasm][abi][{s}] seq={d} pass={d} addr=0x{x} size={d} {s}\n",
                .{ @tagName(ev.domain), self.sequence, ev.pass, ev.address, ev.size, ev.detail },
            );
        }
    }
};

test "abi handshake init deinit" {
    var h = JwasmAbiHandshake.init(std.testing.allocator);
    defer h.deinit();
    h.validateOutput(&[_]u8{ 0x90, 0x90 });
}

test "abi handshake event logging" {
    var h = JwasmAbiHandshake.init(std.testing.allocator);
    defer h.deinit();
    try h.onEvent(.assembly_start, .instruction_encoding, 0, "starting");
    try h.onEvent(.instruction_encoded, .instruction_encoding, 0x100, "mov eax, 1");
    try std.testing.expectEqual(@as(usize, 2), h.event_log.items.len);
}
