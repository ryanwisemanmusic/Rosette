//! A crash-tolerant binary envelope for the structured run journal.
//!
//! Text is still useful to a person at a terminal, but it cannot be the
//! authority for a killed run: a line can be half written, reordered by two
//! producers, or emitted without the state it describes.  This format keeps a
//! small fixed header, fixed-size causal records, and a footer written only
//! after the producer has stopped.  Recovery therefore has a deliberately
//! small answer: complete, incomplete, corrupt, or unsupported.
//!
//! The writer is append-only and does not allocate or lock in the hot path.
//! The in-memory image is used by tests and offline tools; the fd writer uses
//! the same codec, so a recovered file cannot acquire a different meaning.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const Record = bridge.event.Record;
pub const schema_version: u16 = bridge.contract.schema_version;
pub const record_wire_size: usize = 224;
pub const record_frame_size: usize = 232;
pub const header_size: usize = 64;
pub const footer_size: usize = 64;
pub const max_image_bytes: usize = 512 * 1024;

const header_magic = "R3JNL\x00\x03";
const footer_magic = "R3END\x00\x03";

pub const Header = struct {
    run_id: u64 = 0,
    manifest_hash: u64 = 0,
    schema_hash: u64 = 0,
    profile: u8 = 0,
    source_policy: u8 = 0,
    host_monotonic_ns: u64 = 0,
};

pub const Footer = struct {
    run_id: u64 = 0,
    record_count: u64 = 0,
    last_event_id: u64 = 0,
    declared_drops: u64 = 0,
    journal_hash: u64 = 0,
    complete: bool = false,
};

pub const RecoveryStatus = enum(u8) {
    empty,
    incomplete,
    complete,
    corrupt,
    unsupported,

    pub fn label(self: RecoveryStatus) []const u8 {
        return switch (self) {
            .empty => "empty",
            .incomplete => "incomplete",
            .complete => "complete",
            .corrupt => "corrupt",
            .unsupported => "unsupported",
        };
    }
};

pub const Recovery = struct {
    status: RecoveryStatus = .empty,
    run_id: u64 = 0,
    manifest_hash: u64 = 0,
    records: u64 = 0,
    declared_drops: u64 = 0,
    last_event_id: u64 = 0,
    bytes_consumed: usize = 0,
    footer_valid: bool = false,
    /// Byte recovery cannot prove that an fsync reached stable storage. The
    /// fd writer supplies this bit from its own terminal state; a recovered
    /// byte slice therefore remains valid evidence but is not by itself a
    /// durability certificate.
    durable_footer: bool = false,
    reason: []const u8 = "",

    pub fn admissible(self: Recovery) bool {
        return self.status == .complete and self.footer_valid and self.declared_drops == 0;
    }

    pub fn durableAdmissible(self: Recovery) bool {
        return self.admissible() and self.durable_footer;
    }
};

pub const AppendOutcome = enum(u8) {
    accepted,
    not_started,
    full,
    write_failed,
};

/// A fixed-size image useful for tests, crash-recovery tools, and callers that
/// want to assemble an artifact before publishing it. It intentionally does
/// not overwrite old records when full.
pub const Image = struct {
    bytes: [max_image_bytes]u8 = [_]u8{0} ** max_image_bytes,
    length: usize = 0,
    record_count: u64 = 0,
    last_event_id: u64 = 0,
    rolling_hash: u64 = 0,
    started: bool = false,
    finished: bool = false,
    header: Header = .{},

    pub fn begin(self: *Image, header: Header) bool {
        if (header.run_id == 0 or self.started) return false;
        self.* = .{ .started = true, .header = header };
        var encoded: [header_size]u8 = [_]u8{0} ** header_size;
        encodeHeader(&encoded, header);
        @memcpy(self.bytes[0..header_size], encoded[0..]);
        self.length = header_size;
        self.rolling_hash = hashBytes(encoded[0..]);
        return true;
    }

    pub fn append(self: *Image, record: Record) AppendOutcome {
        if (!self.started or self.finished) return .not_started;
        if (self.length + record_frame_size + footer_size > self.bytes.len) return .full;
        var frame: [record_frame_size]u8 = [_]u8{0} ** record_frame_size;
        encodeRecord(&frame, record);
        @memcpy(self.bytes[self.length .. self.length + record_frame_size], frame[0..]);
        self.length += record_frame_size;
        self.record_count +|= 1;
        self.last_event_id = record.event_id;
        self.rolling_hash = hashBytesSeed(frame[0..], self.rolling_hash);
        return .accepted;
    }

    pub fn finish(self: *Image, declared_drops: u64) bool {
        if (!self.started or self.finished) return false;
        if (self.length + footer_size > self.bytes.len) return false;
        const footer = Footer{
            .run_id = self.header.run_id,
            .record_count = self.record_count,
            .last_event_id = self.last_event_id,
            .declared_drops = declared_drops,
            .journal_hash = self.rolling_hash,
            .complete = true,
        };
        var encoded: [footer_size]u8 = [_]u8{0} ** footer_size;
        encodeFooter(&encoded, footer);
        @memcpy(self.bytes[self.length .. self.length + footer_size], encoded[0..]);
        self.length += footer_size;
        self.finished = true;
        return true;
    }

    pub fn view(self: *const Image) []const u8 {
        return self.bytes[0..self.length];
    }

    pub fn recover(self: *const Image) Recovery {
        return recoverBytes(self.view());
    }
};

/// An append-only fd sink. `begin` must be called before any guest work, and
/// `finish` is the only operation that can make recovery report `complete`.
/// A process killed between records has a valid prefix and an incomplete
/// status, never a falsely clean run.
pub const Writer = struct {
    mutex: std.Io.Mutex = .init,
    fd: i32 = -1,
    header: Header = .{},
    record_count: u64 = 0,
    last_event_id: u64 = 0,
    rolling_hash: u64 = 0,
    started: bool = false,
    finished: bool = false,
    write_failures: u64 = 0,
    partial_writes: u64 = 0,
    footer_written: bool = false,
    durable_footer: bool = false,
    last_failure: AppendOutcome = .accepted,

    pub fn begin(self: *Writer, fd: i32, header: Header) bool {
        std.Io.Threaded.mutexLock(&self.mutex);
        defer std.Io.Threaded.mutexUnlock(&self.mutex);
        if (fd < 0 or header.run_id == 0 or self.started) return false;
        var bytes: [header_size]u8 = [_]u8{0} ** header_size;
        encodeHeader(&bytes, header);
        switch (writeAll(fd, bytes[0..])) {
            .complete => {},
            .partial => {
                self.partial_writes +|= 1;
                self.write_failures +|= 1;
                self.last_failure = .write_failed;
                return false;
            },
            .failed => {
                self.write_failures +|= 1;
                self.last_failure = .write_failed;
                return false;
            },
        }
        self.fd = fd;
        self.header = header;
        self.started = true;
        self.finished = false;
        self.footer_written = false;
        self.durable_footer = false;
        self.rolling_hash = hashBytes(bytes[0..]);
        self.last_failure = .accepted;
        return true;
    }

    pub fn append(self: *Writer, record: Record) AppendOutcome {
        std.Io.Threaded.mutexLock(&self.mutex);
        defer std.Io.Threaded.mutexUnlock(&self.mutex);
        if (!self.started or self.finished) return .not_started;
        var frame: [record_frame_size]u8 = [_]u8{0} ** record_frame_size;
        encodeRecord(&frame, record);
        switch (writeAll(self.fd, frame[0..])) {
            .complete => {},
            .partial => {
                self.partial_writes +|= 1;
                self.write_failures +|= 1;
                self.last_failure = .write_failed;
                return .write_failed;
            },
            .failed => {
                self.write_failures +|= 1;
                self.last_failure = .write_failed;
                return .write_failed;
            },
        }
        self.record_count +|= 1;
        self.last_event_id = record.event_id;
        self.rolling_hash = hashBytesSeed(frame[0..], self.rolling_hash);
        self.last_failure = .accepted;
        return .accepted;
    }

    pub fn finish(self: *Writer, declared_drops: u64) bool {
        std.Io.Threaded.mutexLock(&self.mutex);
        defer std.Io.Threaded.mutexUnlock(&self.mutex);
        if (!self.started or self.finished) return false;
        const footer = Footer{
            .run_id = self.header.run_id,
            .record_count = self.record_count,
            .last_event_id = self.last_event_id,
            .declared_drops = declared_drops,
            .journal_hash = self.rolling_hash,
            .complete = true,
        };
        var bytes: [footer_size]u8 = [_]u8{0} ** footer_size;
        encodeFooter(&bytes, footer);
        switch (writeAll(self.fd, bytes[0..])) {
            .complete => {},
            .partial => {
                self.partial_writes +|= 1;
                self.write_failures +|= 1;
                self.last_failure = .write_failed;
                return false;
            },
            .failed => {
                self.write_failures +|= 1;
                self.last_failure = .write_failed;
                return false;
            },
        }
        self.footer_written = true;
        // A footer in the byte stream is not enough. The final fsync is the
        // only point at which the writer can claim a durable footer, and a
        // failure keeps `finished` false even though recovery may see bytes.
        if (std.c.fsync(self.fd) != 0) {
            self.write_failures +|= 1;
            self.last_failure = .write_failed;
            return false;
        }
        self.finished = true;
        self.durable_footer = true;
        self.last_failure = .accepted;
        return true;
    }

    pub fn recovery(self: *const Writer) Recovery {
        return .{
            .status = if (self.finished) .complete else if (self.footer_written) .complete else if (self.started) .incomplete else .empty,
            .run_id = self.header.run_id,
            .manifest_hash = self.header.manifest_hash,
            .records = self.record_count,
            .last_event_id = self.last_event_id,
            .footer_valid = self.footer_written,
            .durable_footer = self.durable_footer,
            .reason = if (self.last_failure == .accepted) "writer state" else "writer failure",
        };
    }
};

pub fn recover(bytes: []const u8) Recovery {
    return recoverBytes(bytes);
}

fn recoverBytes(bytes: []const u8) Recovery {
    if (bytes.len == 0) return .{ .status = .empty, .reason = "no bytes" };
    if (bytes.len < header_size) return .{ .status = .incomplete, .reason = "truncated header" };
    const header = decodeHeader(bytes[0..header_size]) orelse return .{ .status = .corrupt, .reason = "bad header" };
    if (header.schema_hash == 0) return .{ .status = .unsupported, .run_id = header.run_id, .reason = "missing schema hash" };

    var result = Recovery{ .status = .incomplete, .run_id = header.run_id, .manifest_hash = header.manifest_hash };
    var offset: usize = header_size;
    var rolling = hashBytes(bytes[0..header_size]);
    while (offset < bytes.len) {
        const remaining = bytes.len - offset;
        if (remaining >= footer_size and std.mem.eql(u8, bytes[offset .. offset + footer_magic.len], footer_magic)) {
            const footer = decodeFooter(bytes[offset .. offset + footer_size]) orelse {
                result.status = .corrupt;
                result.reason = "bad footer";
                return result;
            };
            if (offset + footer_size != bytes.len) {
                result.status = .corrupt;
                result.reason = "bytes follow footer";
                result.bytes_consumed = offset + footer_size;
                return result;
            }
            if (!footer.complete or footer.run_id != header.run_id or
                footer.record_count != result.records or footer.last_event_id != result.last_event_id or
                footer.journal_hash != rolling)
            {
                result.status = .corrupt;
                result.reason = "footer does not match prefix";
                result.bytes_consumed = offset + footer_size;
                return result;
            }
            result.status = .complete;
            result.footer_valid = true;
            result.declared_drops = footer.declared_drops;
            result.last_event_id = footer.last_event_id;
            result.bytes_consumed = offset + footer_size;
            return result;
        }
        if (remaining < record_frame_size) {
            result.reason = "truncated record or missing footer";
            result.bytes_consumed = offset;
            return result;
        }
        const frame = bytes[offset .. offset + record_frame_size];
        const record = decodeRecord(frame) orelse {
            result.status = .corrupt;
            result.reason = "bad record checksum or schema";
            result.bytes_consumed = offset;
            return result;
        };
        result.records +|= 1;
        result.last_event_id = record.event_id;
        rolling = hashBytesSeed(frame, rolling);
        offset += record_frame_size;
    }
    result.bytes_consumed = offset;
    result.reason = "footer not present";
    return result;
}

const WriteStatus = enum { complete, partial, failed };

fn writeAll(fd: i32, bytes: []const u8) WriteStatus {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const written = std.c.write(fd, bytes.ptr + offset, bytes.len - offset);
        if (written <= 0) return if (offset == 0) .failed else .partial;
        offset += @intCast(written);
    }
    return .complete;
}

fn hashBytes(bytes: []const u8) u64 {
    return hashBytesSeed(bytes, 0xcbf2_9ce4_8422_2325);
}

fn hashBytesSeed(bytes: []const u8, seed: u64) u64 {
    var hash = if (seed == 0) 0xcbf2_9ce4_8422_2325 else seed;
    for (bytes) |byte| {
        hash ^= byte;
        hash *%= 0x0100_0000_01B3;
    }
    return hash;
}

fn put16(bytes: []u8, offset: *usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset.*..][0..2], value, .little);
    offset.* += 2;
}

fn put32(bytes: []u8, offset: *usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset.*..][0..4], value, .little);
    offset.* += 4;
}

fn put64(bytes: []u8, offset: *usize, value: u64) void {
    std.mem.writeInt(u64, bytes[offset.*..][0..8], value, .little);
    offset.* += 8;
}

fn put8(bytes: []u8, offset: *usize, value: u8) void {
    bytes[offset.*] = value;
    offset.* += 1;
}

fn get16(bytes: []const u8, offset: *usize) u16 {
    const value = std.mem.readInt(u16, bytes[offset.*..][0..2], .little);
    offset.* += 2;
    return value;
}

fn get32(bytes: []const u8, offset: *usize) u32 {
    const value = std.mem.readInt(u32, bytes[offset.*..][0..4], .little);
    offset.* += 4;
    return value;
}

fn get64(bytes: []const u8, offset: *usize) u64 {
    const value = std.mem.readInt(u64, bytes[offset.*..][0..8], .little);
    offset.* += 8;
    return value;
}

fn get8(bytes: []const u8, offset: *usize) u8 {
    const value = bytes[offset.*];
    offset.* += 1;
    return value;
}

fn encodeHeader(bytes: *[header_size]u8, header: Header) void {
    @memset(bytes, 0);
    @memcpy(bytes[0..header_magic.len], header_magic);
    var offset: usize = 8;
    put16(bytes[0..], &offset, schema_version);
    put16(bytes[0..], &offset, header_size);
    put32(bytes[0..], &offset, @intCast(record_wire_size));
    put64(bytes[0..], &offset, header.run_id);
    put64(bytes[0..], &offset, header.manifest_hash);
    put64(bytes[0..], &offset, header.schema_hash);
    put8(bytes[0..], &offset, header.profile);
    put8(bytes[0..], &offset, header.source_policy);
    put16(bytes[0..], &offset, 0);
    put64(bytes[0..], &offset, header.host_monotonic_ns);
    put32(bytes[0..], &offset, @truncate(hashBytes(bytes[0..offset])));
}

fn decodeHeader(bytes: []const u8) ?Header {
    if (bytes.len < header_size or !std.mem.eql(u8, bytes[0..header_magic.len], header_magic)) return null;
    var offset: usize = 8;
    if (get16(bytes, &offset) != schema_version or get16(bytes, &offset) != header_size or get32(bytes, &offset) != record_wire_size) return null;
    const header = Header{
        .run_id = get64(bytes, &offset),
        .manifest_hash = get64(bytes, &offset),
        .schema_hash = get64(bytes, &offset),
        .profile = get8(bytes, &offset),
        .source_policy = get8(bytes, &offset),
    };
    _ = get16(bytes, &offset);
    const host_ns = get64(bytes, &offset);
    const stored_hash = get32(bytes, &offset);
    if (stored_hash != @as(u32, @truncate(hashBytes(bytes[0 .. offset - 4])))) return null;
    var result = header;
    result.host_monotonic_ns = host_ns;
    return result;
}

fn encodeFooter(bytes: *[footer_size]u8, footer: Footer) void {
    @memset(bytes, 0);
    @memcpy(bytes[0..footer_magic.len], footer_magic);
    var offset: usize = 8;
    put16(bytes[0..], &offset, schema_version);
    put16(bytes[0..], &offset, footer_size);
    put32(bytes[0..], &offset, @intCast(record_wire_size));
    put64(bytes[0..], &offset, footer.run_id);
    put64(bytes[0..], &offset, footer.record_count);
    put64(bytes[0..], &offset, footer.last_event_id);
    put64(bytes[0..], &offset, footer.declared_drops);
    put64(bytes[0..], &offset, footer.journal_hash);
    put8(bytes[0..], &offset, @intFromBool(footer.complete));
    put32(bytes[0..], &offset, @truncate(hashBytes(bytes[0..offset])));
}

fn decodeFooter(bytes: []const u8) ?Footer {
    if (bytes.len < footer_size or !std.mem.eql(u8, bytes[0..footer_magic.len], footer_magic)) return null;
    var offset: usize = 8;
    if (get16(bytes, &offset) != schema_version or get16(bytes, &offset) != footer_size or get32(bytes, &offset) != record_wire_size) return null;
    const footer = Footer{
        .run_id = get64(bytes, &offset),
        .record_count = get64(bytes, &offset),
        .last_event_id = get64(bytes, &offset),
        .declared_drops = get64(bytes, &offset),
        .journal_hash = get64(bytes, &offset),
        .complete = get8(bytes, &offset) != 0,
    };
    const stored_hash = get32(bytes, &offset);
    if (stored_hash != @as(u32, @truncate(hashBytes(bytes[0 .. offset - 4])))) return null;
    return footer;
}

fn encodeRecord(bytes: *[record_frame_size]u8, record: Record) void {
    @memset(bytes, 0);
    var offset: usize = 0;
    put16(bytes[0..], &offset, record.schema);
    put16(bytes[0..], &offset, record.kind);
    put8(bytes[0..], &offset, record.domain);
    put8(bytes[0..], &offset, record.source_class);
    put8(bytes[0..], &offset, record.result_class);
    put8(bytes[0..], &offset, record.reason);
    put8(bytes[0..], &offset, record.provenance);
    put8(bytes[0..], &offset, record.reserved0);
    put16(bytes[0..], &offset, record.contract_edge);
    inline for ([_]u64{ record.run_id, record.domain_sequence, record.global_sequence, record.event_id, record.guest_step, record.host_monotonic_ns, record.guest_thread, record.host_thread }) |value| put64(bytes[0..], &offset, value);
    put32(bytes[0..], &offset, record.location.guest_pc);
    put32(bytes[0..], &offset, record.location.guest_lr);
    put64(bytes[0..], &offset, record.location.host_rip);
    put32(bytes[0..], &offset, record.location.module_id);
    put8(bytes[0..], &offset, record.location.provenance);
    put8(bytes[0..], &offset, record.location.quality);
    put16(bytes[0..], &offset, record.location.reserved);
    put32(bytes[0..], &offset, record.address.guest_virtual);
    put32(bytes[0..], &offset, record.address.guest_physical);
    put64(bytes[0..], &offset, record.address.host);
    inline for ([_]u64{ record.subject_id, record.generation, record.expected_value, record.actual_value }) |value| put64(bytes[0..], &offset, value);
    put32(bytes[0..], &offset, record.payload_length);
    put32(bytes[0..], &offset, record.payload_crc);
    inline for ([_]u64{ record.parent_event_id, record.correlation_id, record.module_epoch, record.callback_generation, record.ring_generation, record.state_hash, record.effect_mask, record.effect_hash }) |value| put64(bytes[0..], &offset, value);
    put32(bytes[0..], &offset, record.integrityChecksum());
}

fn decodeRecord(bytes: []const u8) ?Record {
    if (bytes.len < record_frame_size) return null;
    var offset: usize = 0;
    var record = Record{
        .schema = get16(bytes, &offset),
        .kind = get16(bytes, &offset),
        .domain = get8(bytes, &offset),
        .source_class = get8(bytes, &offset),
        .result_class = get8(bytes, &offset),
        .reason = get8(bytes, &offset),
        .provenance = get8(bytes, &offset),
        .reserved0 = get8(bytes, &offset),
        .contract_edge = get16(bytes, &offset),
    };
    if (record.schema != schema_version) return null;
    const sequence_fields = [_]u64{ get64(bytes, &offset), get64(bytes, &offset), get64(bytes, &offset), get64(bytes, &offset), get64(bytes, &offset), get64(bytes, &offset), get64(bytes, &offset), get64(bytes, &offset) };
    record.run_id = sequence_fields[0];
    record.domain_sequence = sequence_fields[1];
    record.global_sequence = sequence_fields[2];
    record.event_id = sequence_fields[3];
    record.guest_step = sequence_fields[4];
    record.host_monotonic_ns = sequence_fields[5];
    record.guest_thread = sequence_fields[6];
    record.host_thread = sequence_fields[7];
    record.location = .{
        .guest_pc = get32(bytes, &offset),
        .guest_lr = get32(bytes, &offset),
        .host_rip = get64(bytes, &offset),
        .module_id = get32(bytes, &offset),
        .provenance = get8(bytes, &offset),
        .quality = get8(bytes, &offset),
        .reserved = get16(bytes, &offset),
    };
    record.address = .{ .guest_virtual = get32(bytes, &offset), .guest_physical = get32(bytes, &offset), .host = get64(bytes, &offset) };
    record.subject_id = get64(bytes, &offset);
    record.generation = get64(bytes, &offset);
    record.expected_value = get64(bytes, &offset);
    record.actual_value = get64(bytes, &offset);
    record.payload_length = get32(bytes, &offset);
    record.payload_crc = get32(bytes, &offset);
    record.parent_event_id = get64(bytes, &offset);
    record.correlation_id = get64(bytes, &offset);
    record.module_epoch = get64(bytes, &offset);
    record.callback_generation = get64(bytes, &offset);
    record.ring_generation = get64(bytes, &offset);
    record.state_hash = get64(bytes, &offset);
    record.effect_mask = get64(bytes, &offset);
    record.effect_hash = get64(bytes, &offset);
    const checksum = get32(bytes, &offset);
    if (checksum != record.integrityChecksum()) return null;
    return record;
}

test "a footer is the only thing that upgrades a prefix to complete" {
    var image = Image{};
    try std.testing.expect(image.begin(.{ .run_id = 1, .manifest_hash = 2, .schema_hash = 3 }));
    const event = Record{ .run_id = 1, .event_id = 7, .kind = 1 };
    try std.testing.expectEqual(AppendOutcome.accepted, image.append(event));
    const open = image.recover();
    try std.testing.expectEqual(RecoveryStatus.incomplete, open.status);
    try std.testing.expectEqual(@as(u64, 1), open.records);
    try std.testing.expect(image.finish(0));
    const complete = image.recover();
    try std.testing.expectEqual(RecoveryStatus.complete, complete.status);
    try std.testing.expect(complete.admissible());
    try std.testing.expectEqual(@as(u64, 7), complete.last_event_id);
}

test "a truncated record is incomplete and a changed record is corrupt" {
    var image = Image{};
    _ = image.begin(.{ .run_id = 9, .manifest_hash = 8, .schema_hash = 7 });
    _ = image.append(.{ .run_id = 9, .event_id = 1, .kind = 12 });
    const prefix = image.view()[0 .. image.view().len - 1];
    try std.testing.expectEqual(RecoveryStatus.incomplete, recover(prefix).status);
    _ = image.finish(0);
    var corrupted = image.bytes;
    corrupted[header_size + 20] ^= 0x80;
    try std.testing.expectEqual(RecoveryStatus.corrupt, recover(corrupted[0..image.length]).status);
}

test "the codec retains causal identity and uses explicit little endian fields" {
    var image = Image{};
    _ = image.begin(.{ .run_id = 0x1122, .manifest_hash = 2, .schema_hash = 3, .profile = 1 });
    const event = Record{
        .run_id = 0x1122,
        .domain_sequence = 4,
        .global_sequence = 5,
        .event_id = 6,
        .parent_event_id = 7,
        .correlation_id = 8,
        .callback_generation = 9,
        .effect_mask = 0x100,
        .location = .{ .guest_pc = 0x8258_A470, .host_rip = 0x1234 },
    };
    _ = image.append(event);
    _ = image.finish(0);
    const recovered = recover(image.view());
    try std.testing.expectEqual(RecoveryStatus.complete, recovered.status);
    const decoded = decodeRecord(image.view()[header_size .. header_size + record_frame_size]).?;
    try std.testing.expectEqual(event.event_id, decoded.event_id);
    try std.testing.expectEqual(event.parent_event_id, decoded.parent_event_id);
    try std.testing.expectEqual(event.location.guest_pc, decoded.location.guest_pc);
    try std.testing.expect(image.view()[header_size + 1] == 0);
}

test "a footer must be terminal and must name the final event" {
    var image = Image{};
    _ = image.begin(.{ .run_id = 22, .manifest_hash = 2, .schema_hash = 3 });
    _ = image.append(.{ .run_id = 22, .event_id = 8, .kind = 12 });
    _ = image.finish(0);

    var with_trailer: [max_image_bytes]u8 = image.bytes;
    with_trailer[image.length] = 0xA5;
    try std.testing.expectEqual(RecoveryStatus.corrupt, recover(with_trailer[0 .. image.length + 1]).status);

    var changed_footer = image.bytes;
    const last_event_offset = image.length - footer_size + 24;
    std.mem.writeInt(u64, changed_footer[last_event_offset..][0..8], 9, .little);
    try std.testing.expectEqual(RecoveryStatus.corrupt, recover(changed_footer[0..image.length]).status);
}
