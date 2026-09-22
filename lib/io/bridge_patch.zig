const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;
const types = @import("bridge_types.zig");
const PATCH_TOML_TRACE_CAPACITY = types.PATCH_TOML_TRACE_CAPACITY;
const PatchTomlSchema = types.PatchTomlSchema;
const PatchTomlSchemaScanner = types.PatchTomlSchemaScanner;
const Stream = types.Stream;
const Utf8Invalid = types.Utf8Invalid;
const Utf8Scanner = types.Utf8Scanner;

pub fn recordPatchTomlOp(self: anytype, stream: *Stream, operation: []const u8, offset: i64, bytes: []const u8) void {
    self.io_sequence +|= 1;
    stream.last_io_sequence = self.io_sequence;
    const op_idx = stream.patch_toml_trace_next;
    const op = &stream.patch_toml_trace[op_idx];
    const op_len = @min(operation.len, op.operation.len);
    @memset(&op.operation, 0);
    @memcpy(op.operation[0..op_len], operation[0..op_len]);
    op.op_len = @intCast(op_len);
    op.offset = offset;
    op.size = bytes.len;
    op.sequence = self.io_sequence;
    if (bytes.len > 0) {
        const copy_len = @min(bytes.len, 4);
        @memcpy(op.content_first[0..copy_len], bytes[0..copy_len]);
        var hash: u64 = 0;
        for (bytes[0..@min(bytes.len, 64)]) |b| hash = hash ^ @as(u64, b);
        op.content_hash = hash;
    }
    stream.patch_toml_trace_next = (stream.patch_toml_trace_next + 1) % PATCH_TOML_TRACE_CAPACITY;
    if (stream.patch_toml_trace_next == 0) stream.patch_toml_trace_full = true;
}

pub fn tracePatchRead(self: anytype, stream: *Stream, operation: []const u8, offset: i64, bytes: []const u8) void {
    if (!stream.patch_toml or bytes.len == 0) return;

    self.recordPatchTomlOp(stream, operation, offset, bytes);

    var scanner = Utf8Scanner{};
    for (bytes, 0..) |byte, index| {
        if (scanner.feed(byte, @as(u64, @intCast(@max(offset, 0))) + index)) |issue| {
            machoCapturePrint(
                "macho-processor: libc++ patch stream invalid UTF-8 chunk: path={s} operation={s} byte_offset={d} reason={s} byte=0x{x:0>2}\n",
                .{ stream.path[0..stream.path_length], operation, issue.offset, issue.reason, issue.byte },
            );
            self.tracePatchContext(stream.fd, stream.path[0..stream.path_length], issue.offset, "chunk-invalid");
            break;
        }
    }
    if (scanner.finish()) |issue| {
        machoCapturePrint(
            "macho-processor: libc++ patch stream truncated UTF-8 chunk: path={s} operation={s} byte_offset={d} reason={s}\n",
            .{ stream.path[0..stream.path_length], operation, issue.offset, issue.reason },
        );
    }

    // Stream operation is recorded in the trace ring buffer above.
    // The verbose machoCapturePrint for each read/peek is intentionally
    // suppressed during normal operation; dumpPatchTomlDiagnostics
    // emits the full trace on fault.
}

pub fn tracePatchSeek(self: anytype, stream: *Stream, operation: []const u8, offset: i64, direction: std.c.whence_t, result: i64) void {
    if (!stream.patch_toml) return;
    _ = direction; // recorded in trace ring buffer below
    _ = result;
    const empty: [0]u8 = undefined;
    self.recordPatchTomlOp(stream, operation, offset, &empty);
}

pub fn tracePatchTell(self: anytype, stream: *Stream, result: i64) void {
    if (!stream.patch_toml) return;
    _ = result; // recorded in trace ring buffer
    const empty: [0]u8 = undefined;
    self.recordPatchTomlOp(stream, "tellg", 0, &empty);
}

/// Returns the most recent block size read by an active patch stream.
/// tracked_pos is cumulative and must never be used as a block length.
pub fn findPatchTomlByteCount(self: anytype) ?u64 {
    var newest_sequence: u64 = 0;
    var count: ?u64 = null;
    for (&self.streams) |*stream| {
        if (!stream.active) continue;
        if (stream.fd < 0) continue;
        const path = stream.path[0..stream.path_length];
        if (std.mem.endsWith(u8, path, ".patch.toml")) {
            if (stream.last_io_sequence >= newest_sequence and stream.last_read_count >= 0) {
                newest_sequence = stream.last_io_sequence;
                count = @intCast(stream.last_read_count);
            }
        }
    }
    return count;
}

pub fn isActivePatchTomlIstream(self: anytype, object: u64) bool {
    const stream = self.findFlexible(object) orelse return false;
    return stream.active and stream.fd >= 0 and stream.patch_toml;
}

pub fn dumpPatchTomlDiagnostics(self: anytype, reason: []const u8) void {
    var found = false;
    for (&self.streams) |*stream| {
        if (!stream.active or !stream.patch_toml) continue;
        found = true;
        const path = stream.path[0..stream.path_length];
        const current: i64 = @intCast(stream.tracked_pos);
        machoCapturePrint(
            "macho-processor: TOML diagnostics ({s}): path={s} object=0x{x} fd={d} generation={d} io_sequence={d} current_offset={d} last_read_offset={d} last_read_size={d} last_gcount={d} eof={} failed={}\n",
            .{ reason, path, stream.object, stream.fd, stream.generation, stream.last_io_sequence, current, stream.last_read_offset, stream.last_read_size, stream.last_read_count, stream.eof, stream.failed },
        );
        self.logPatchSchema(stream, "active-stream");

        const trace_count = if (stream.patch_toml_trace_full) PATCH_TOML_TRACE_CAPACITY else stream.patch_toml_trace_next;
        if (trace_count > 0) {
            machoCapturePrint("macho-processor: libc++ patch I/O trace (last {d} operations):\n", .{trace_count});
            if (stream.patch_toml_trace_full) {
                const start = stream.patch_toml_trace_next;
                for (0..PATCH_TOML_TRACE_CAPACITY) |i| {
                    const idx = (start + i) % PATCH_TOML_TRACE_CAPACITY;
                    const op = &stream.patch_toml_trace[idx];
                    if (op.op_len == 0) continue;
                    const op_str = op.operation[0..op.op_len];
                    if (std.mem.eql(u8, op_str, "tellg")) continue;
                    const hex_byte = &[_]u8{
                        "0123456789abcdef"[op.content_first[0] >> 4],
                        "0123456789abcdef"[op.content_first[0] & 0x0f],
                        "0123456789abcdef"[op.content_first[1] >> 4],
                        "0123456789abcdef"[op.content_first[1] & 0x0f],
                        "0123456789abcdef"[op.content_first[2] >> 4],
                        "0123456789abcdef"[op.content_first[2] & 0x0f],
                        "0123456789abcdef"[op.content_first[3] >> 4],
                        "0123456789abcdef"[op.content_first[3] & 0x0f],
                    };
                    machoCapturePrint("  seq={d} {s} offset={d} size={d} first={s} hash=0x{x}\n", .{ op.sequence, op_str, op.offset, op.size, hex_byte[0..8], op.content_hash });
                }
            } else {
                for (0..stream.patch_toml_trace_next) |i| {
                    const op = &stream.patch_toml_trace[i];
                    if (op.op_len == 0) continue;
                    const op_str = op.operation[0..op.op_len];
                    if (std.mem.eql(u8, op_str, "tellg")) continue;
                    const hex_byte = &[_]u8{
                        "0123456789abcdef"[op.content_first[0] >> 4],
                        "0123456789abcdef"[op.content_first[0] & 0x0f],
                        "0123456789abcdef"[op.content_first[1] >> 4],
                        "0123456789abcdef"[op.content_first[1] & 0x0f],
                        "0123456789abcdef"[op.content_first[2] >> 4],
                        "0123456789abcdef"[op.content_first[2] & 0x0f],
                        "0123456789abcdef"[op.content_first[3] >> 4],
                        "0123456789abcdef"[op.content_first[3] & 0x0f],
                    };
                    machoCapturePrint("  seq={d} {s} offset={d} size={d} first={s} hash=0x{x}\n", .{ op.sequence, op_str, op.offset, op.size, hex_byte[0..8], op.content_hash });
                }
            }
        }

        // Detect offset regression: check if offset went backwards
        // (peek operations do NOT advance the position and are excluded)
        var last_offset: i64 = -1;
        var regression_found = false;
        const iteration_count = if (stream.patch_toml_trace_full) PATCH_TOML_TRACE_CAPACITY else stream.patch_toml_trace_next;
        const trace_start = if (stream.patch_toml_trace_full) stream.patch_toml_trace_next else @as(u16, 0);
        for (0..iteration_count) |i| {
            const idx = (trace_start +% @as(u16, @intCast(i))) % PATCH_TOML_TRACE_CAPACITY;
            const op = &stream.patch_toml_trace[idx];
            const op_str = op.operation[0..op.op_len];
            if (op.op_len == 0) continue;
            if (std.mem.eql(u8, op_str, "tellg")) continue;
            // seek sets an absolute offset; track it without regression check
            if (std.mem.eql(u8, op_str, "seek")) {
                last_offset = op.offset;
                // peek does NOT advance the file position – skip it
            } else if (std.mem.eql(u8, op_str, "peek")) {
                continue;
            } else if (op.size > 0) {
                if (last_offset >= 0 and op.offset < last_offset) {
                    machoCapturePrint("macho-processor: *** OFFSET REGRESSION DETECTED: was offset={d}, now offset={d} (went backwards! fd may have been reopened/reset!)\n", .{ last_offset, op.offset });
                    regression_found = true;
                }
                if (op.offset >= 0) last_offset = op.offset + @as(i64, @intCast(op.size));
            }
        }
        if (!regression_found and last_offset >= 0) {
            machoCapturePrint("macho-processor: I/O trace monotonic: no offset regression detected (last tracked end offset = {d})\n", .{last_offset});
        }

        if (stream.fd >= 0) {
            self.tracePatchTomlOpen(stream, path);
            const center: u64 = if (stream.last_read_offset >= 0)
                @intCast(stream.last_read_offset)
            else if (current >= 0)
                @intCast(current)
            else
                0;
            self.tracePatchContext(stream.fd, path, center, "active-stream");

            // Expected vs actual content check at current offset
            if (current >= 0) {
                var expected: [64]u8 = undefined;
                const eread = std.c.pread(stream.fd, &expected, expected.len, @intCast(current));
                if (eread > 0) {
                    const ebytes = expected[0..@intCast(eread)];
                    var ehex: [128]u8 = undefined;
                    for (ebytes, 0..) |b, j| {
                        ehex[j * 2] = "0123456789abcdef"[b >> 4];
                        ehex[j * 2 + 1] = "0123456789abcdef"[b & 0x0f];
                    }
                    machoCapturePrint(
                        "macho-processor: pread at current_offset={d} ({d} bytes): first={s}\n",
                        .{ current, ebytes.len, ehex[0..@min(ebytes.len * 2, 64)] },
                    );
                }
            }

            // fd integrity check: verify file size via lseek to end
            if (stream.fd >= 0) {
                const saved = std.c.lseek(stream.fd, 0, std.c.SEEK.CUR);
                const fsize = std.c.lseek(stream.fd, 0, std.c.SEEK.END);
                if (saved >= 0 and fsize >= 0) {
                    _ = std.c.lseek(stream.fd, saved, std.c.SEEK.SET);
                    machoCapturePrint(
                        "macho-processor: fd integrity: fd={d} file_size={d}\n",
                        .{ stream.fd, fsize },
                    );
                }
            }

            // Check for other streams sharing the same fd
            var shared_fd_count: u32 = 0;
            for (&self.streams) |other| {
                if (other.active and other.fd == stream.fd and other.object != stream.object) shared_fd_count += 1;
            }
            if (shared_fd_count > 0) {
                machoCapturePrint("macho-processor: *** WARNING: {d} other stream(s) share fd={d}! Possible fd aliasing\n", .{ shared_fd_count, stream.fd });
                machoCapturePrint("macho-processor: fd aliasing detail: primary object=0x{x} tracked_pos={d} path={s}\n", .{ stream.object, stream.tracked_pos, path });
                for (&self.streams) |other| {
                    if (other.active and other.fd == stream.fd and other.object != stream.object) {
                        const other_path = other.path[0..other.path_length];
                        machoCapturePrint("macho-processor: fd aliasing detail: aliased object=0x{x} tracked_pos={d} path={s}\n", .{ other.object, other.tracked_pos, other_path });
                    }
                }
            }
        }
    }
    if (!found) {
        machoCapturePrint("macho-processor: TOML diagnostics ({s}): no active .patch.toml stream tracked by libc++ bridge\n", .{reason});
        if (self.last_patch_schema_valid) {
            self.logPatchSchemaValues(
                self.last_patch_path[0..self.last_patch_path_length],
                self.last_patch_schema,
                "archived-after-stream-destruction",
            );
        }
    }
}

pub fn dumpPatchPostParseDiagnosis(self: anytype, reason: []const u8) void {
    var newest: ?*Stream = null;
    for (&self.streams) |*stream| {
        if (!stream.active or !stream.patch_toml) continue;
        if (newest == null or stream.generation > newest.?.generation) newest = stream;
    }
    var schema: PatchTomlSchema = undefined;
    var path: []const u8 = undefined;
    if (newest) |stream| {
        schema = stream.patch_toml_schema;
        path = stream.path[0..stream.path_length];
    } else if (self.last_patch_schema_valid) {
        schema = self.last_patch_schema;
        path = self.last_patch_path[0..self.last_patch_path_length];
    } else {
        machoCapturePrint("macho-processor: PatchDB post-parse diagnosis ({s}): no active or archived patch TOML schema is available\n", .{reason});
        return;
    }
    self.logPatchSchemaValues(path, schema, reason);
    if (schema.patch_array_headers == 0) {
        machoCapturePrint(
            "macho-processor: PatchDB null-dereference correlation: the parsed file contains zero [[patch]] arrays; Xenia PatchDB::ReadPatchFile obtains patch_toml_fields.get(\"patch\") and calls patch_array->is_array() without first checking patch_array for null\n",
            .{},
        );
        machoCapturePrint(
            "macho-processor: PatchDB null-dereference verdict: normal EOF and successful TOML parsing are compatible with this crash; the missing optional patch node is the immediate null source, not fd reuse or stream corruption\n",
            .{},
        );
    }
}

pub fn logPatchSchema(_: anytype, stream: *const Stream, label: []const u8) void {
    logPatchSchemaValuesStatic(stream.path[0..stream.path_length], stream.patch_toml_schema, label);
}

pub fn logPatchSchemaValues(_: anytype, path: []const u8, schema: PatchTomlSchema, label: []const u8) void {
    logPatchSchemaValuesStatic(path, schema, label);
}

pub fn rememberPatchSchema(self: anytype, stream: *const Stream) void {
    self.last_patch_schema_valid = stream.patch_toml_schema.complete;
    self.last_patch_schema_generation = stream.generation;
    self.last_patch_schema = stream.patch_toml_schema;
    self.last_patch_path_length = stream.path_length;
    @memcpy(self.last_patch_path[0..self.last_patch_path_length], stream.path[0..stream.path_length]);
}

pub fn latestPatchSchemaHasEmptyPatchSet(self: anytype) bool {
    if (!self.last_patch_schema_valid) return false;
    const schema = self.last_patch_schema;
    return schema.complete and
        schema.title_name_assignments != 0 and
        schema.title_id_assignments != 0 and
        schema.hash_assignments != 0 and
        schema.patch_array_headers == 0;
}

pub fn logEmptyPatchCompatibility(self: anytype, action: []const u8) void {
    if (!self.last_patch_schema_valid) return;
    logPatchSchemaValuesStatic(
        self.last_patch_path[0..self.last_patch_path_length],
        self.last_patch_schema,
        action,
    );
}

pub fn logPatchSchemaValuesStatic(path: []const u8, schema: PatchTomlSchema, label: []const u8) void {
    machoCapturePrint(
        "macho-processor: patch TOML schema[{s}]: path={s} bytes={d} lines={d} assignments(title_name/title_id/hash)={d}/{d}/{d} patch_array_headers={d} truncated_lines={d} complete={}\n",
        .{ label, path, schema.bytes, schema.lines, schema.title_name_assignments, schema.title_id_assignments, schema.hash_assignments, schema.patch_array_headers, schema.truncated_lines, schema.complete },
    );
}

pub fn tracePatchTomlOpen(self: anytype, stream: *Stream, path: []const u8) void {
    const fd = stream.fd;
    const original = std.c.lseek(fd, 0, std.c.SEEK.CUR);
    if (original < 0) return;
    _ = std.c.lseek(fd, 0, std.c.SEEK.SET);
    var buffer: [4096]u8 = undefined;
    var scanner = Utf8Scanner{};
    var schema_scanner = PatchTomlSchemaScanner{};
    var total: u64 = 0;
    var ascii = true;
    var invalid: ?Utf8Invalid = null;
    while (true) {
        const result = std.c.read(fd, &buffer, buffer.len);
        if (result < 0) {
            machoCapturePrint("macho-processor: libc++ patch TOML preflight failed: {s} errno={s}\n", .{ path, @tagName(std.c.errno(result)) });
            _ = std.c.lseek(fd, original, std.c.SEEK.SET);
            return;
        }
        if (result == 0) break;
        const bytes = buffer[0..@intCast(result)];
        schema_scanner.feed(bytes);
        for (bytes, 0..) |byte, index| {
            if (byte >= 0x80) ascii = false;
            if (invalid == null) invalid = scanner.feed(byte, total + index);
        }
        total += bytes.len;
    }
    _ = std.c.lseek(fd, original, std.c.SEEK.SET);
    stream.patch_toml_schema = schema_scanner.finish();
    self.rememberPatchSchema(stream);
    if (invalid == null) invalid = scanner.finish();
    machoCapturePrint(
        "macho-processor: libc++ patch TOML preflight: path={s} bytes={d} ascii={} utf8={} full_scan=true\n",
        .{ path, total, ascii, invalid == null },
    );
    self.logPatchSchema(stream, "preflight");
    if (invalid) |issue| {
        const context_start: u64 = issue.offset -| 8;
        var context: [24]u8 = undefined;
        const context_read = std.c.pread(fd, &context, context.len, @intCast(context_start));
        const context_len: usize = if (context_read > 0) @intCast(context_read) else 0;
        var hex: [48]u8 = undefined;
        const alphabet = "0123456789abcdef";
        for (context[0..context_len], 0..) |byte, index| {
            hex[index * 2] = alphabet[byte >> 4];
            hex[index * 2 + 1] = alphabet[byte & 0x0f];
        }
        machoCapturePrint(
            "macho-processor: libc++ patch TOML invalid UTF-8: path={s} byte_offset={d} reason={s} byte=0x{x:0>2} context_start={d} context_hex={s}\n",
            .{ path, issue.offset, issue.reason, issue.byte, context_start, hex[0 .. context_len * 2] },
        );
    } else {
        // Host bytes validated; detailed UTF-8 diagnostics are suppressed
        // during normal operation. dumpPatchTomlDiagnostics shows full
        // I/O trace and schema information on fault.
    }
}

pub fn tracePatchContext(_: anytype, fd: std.c.fd_t, path: []const u8, center: u64, label: []const u8) void {
    if (fd < 0) return;
    const start = center -| 32;
    var context: [96]u8 = undefined;
    const context_read = std.c.pread(fd, &context, context.len, @intCast(start));
    if (context_read <= 0) return;
    const context_len: usize = @intCast(context_read);
    var hex: [192]u8 = undefined;
    var ascii: [96]u8 = undefined;
    const alphabet = "0123456789abcdef";
    for (context[0..context_len], 0..) |byte, index| {
        hex[index * 2] = alphabet[byte >> 4];
        hex[index * 2 + 1] = alphabet[byte & 0x0f];
        ascii[index] = if (byte >= 0x20 and byte < 0x7f) byte else '.';
    }
    machoCapturePrint(
        "macho-processor: libc++ patch TOML context[{s}]: path={s} center={d} start={d} bytes={d} hex={s} ascii='{s}'\n",
        .{ label, path, center, start, context_len, hex[0 .. context_len * 2], ascii[0..context_len] },
    );
}
