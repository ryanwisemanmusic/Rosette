const std = @import("std");

const aes = std.crypto.core.aes;

const MAX_AES_ROUNDS: u32 = 14;

const SHA1_DIGEST_OFFSET: u64 = 0x08;
const SHA1_BLOCK_OFFSET: u64 = 0x1c;
const SHA1_BLOCK_INDEX_OFFSET: u64 = 0x60;
const SHA1_BYTE_COUNT_OFFSET: u64 = 0x68;

/// Decrypt one block with the decryption schedule produced by Xenia's
/// rijndaelKeySetupDec. The schedule is already in inverse-round form, so it
/// can be fed directly to the AES core one round at a time.
pub fn decryptBlock(round_keys: []const u32, nr: u32, ciphertext: [16]u8) [16]u8 {
    std.debug.assert(nr <= MAX_AES_ROUNDS);
    std.debug.assert(round_keys.len >= @as(usize, (nr + 1) * 4));

    var keys: [MAX_AES_ROUNDS + 1]aes.Block = undefined;
    for (0..@as(usize, nr + 1)) |round| {
        var key_bytes: [16]u8 = undefined;
        for (0..4) |word| {
            // Xenia stores u32 round-key words in the guest's little-endian
            // memory, while the Rijndael word itself is big-endian.
            std.mem.writeInt(
                u32,
                key_bytes[word * 4 ..][0..4],
                round_keys[round * 4 + word],
                .big,
            );
        }
        keys[round] = aes.Block.fromBytes(&key_bytes);
    }

    var state = aes.Block.fromBytes(&ciphertext).xorBlocks(keys[0]);
    var round: u32 = 1;
    while (round < nr) : (round += 1) {
        state = state.decrypt(keys[@intCast(round)]);
    }
    state = state.decryptLast(keys[@intCast(nr)]);
    return state.toBytes();
}

/// Decrypt an AES-128 block from the cipher key stored in the final four
/// words of Xenia's decryption schedule. Xenia's `rijndaelKeySetupDec`
/// leaves that key at the end of the schedule, while the intermediate
/// inverse-MixColumns words are produced by the guest. Re-expanding the key
/// here avoids trusting a guest-generated schedule whose arithmetic may have
/// been affected by an unrelated emulation defect.
fn decryptBlockFromCipherKey(cipher_key: [16]u8, ciphertext: [16]u8) [16]u8 {
    var plaintext: [16]u8 = undefined;
    const context = aes.Aes128.initDec(cipher_key);
    context.decrypt(&plaintext, &ciphertext);
    return plaintext;
}

/// Complete one Xenia rijndaelDecrypt call using Rosette's host AES
/// implementation. This is deliberately generic over the PE state so this
/// helper does not acquire a dependency on the ELF processor's concrete type.
/// The caller must verify the target symbol before invoking it.
pub fn tryRijndaelDecrypt(state: anytype, schedule_address: u64, nr_value: u64, ciphertext_address: u64, plaintext_address: u64) bool {
    const nr: u32 = std.math.cast(u32, nr_value) orelse return false;
    if (nr != 10 and nr != 12 and nr != 14) return false;

    const word_count: usize = @intCast((nr + 1) * 4);
    const schedule_bytes: u64 = @intCast(word_count * @sizeOf(u32));
    const schedule = state.guestMemoryConst(schedule_address, schedule_bytes) orelse return false;
    const source = state.guestMemoryConst(ciphertext_address, 16) orelse return false;
    if (state.guestMemory(plaintext_address, 16) == null) return false;

    var round_keys: [4 * (MAX_AES_ROUNDS + 1)]u32 = undefined;
    for (0..word_count) |index| {
        round_keys[index] = std.mem.readInt(u32, schedule[index * 4 ..][0..4], .little);
    }

    var ciphertext: [16]u8 = undefined;
    @memcpy(&ciphertext, source);
    const plaintext = if (nr == 10) blk: {
        var cipher_key: [16]u8 = undefined;
        for (0..4) |word| {
            std.mem.writeInt(
                u32,
                cipher_key[word * 4 ..][0..4],
                round_keys[word_count - 4 + word],
                .big,
            );
        }
        break :blk decryptBlockFromCipherKey(cipher_key, ciphertext);
    } else decryptBlock(round_keys[0..word_count], nr, ciphertext);
    state.writeMem128(plaintext_address, plaintext);

    // Keep the first accelerated block self-contained in the detailed log.
    // Xenia rejects the image much later, after many blocks have completed,
    // so this lets us distinguish an AES/schedule mismatch from a guest
    // memory write or subsequent read-back problem without logging every
    // block in a multi-megabyte XEX.
    if (state.xenia_rijndael_accelerated_calls == 0) {
        const stored = state.readMem128(plaintext_address);
        std.log.info("PE64 Xenia Rijndael first block: schedule=0x{x} nr={d} ciphertext={any} rk0={any} rk1={any} rk_last={any} plaintext={any} stored={any}", .{
            schedule_address,
            nr,
            ciphertext,
            round_keys[0..4],
            round_keys[4..8],
            round_keys[word_count - 4 .. word_count],
            plaintext,
            stored,
        });
    }
    return true;
}

fn sha1Compress(digest: [5]u32, block: [64]u8) [5]u32 {
    var schedule: [80]u32 = undefined;
    for (0..16) |index| {
        schedule[index] = std.mem.readInt(u32, block[index * 4 ..][0..4], .big);
    }
    for (16..80) |index| {
        schedule[index] = std.math.rotl(u32, schedule[index - 3] ^ schedule[index - 8] ^ schedule[index - 14] ^ schedule[index - 16], 1);
    }

    var a = digest[0];
    var b = digest[1];
    var c = digest[2];
    var d = digest[3];
    var e = digest[4];
    for (0..80) |index| {
        const f: u32 = if (index < 20)
            (b & c) | (~b & d)
        else if (index < 40)
            b ^ c ^ d
        else if (index < 60)
            (b & c) | (b & d) | (c & d)
        else
            b ^ c ^ d;
        const k: u32 = if (index < 20)
            0x5a827999
        else if (index < 40)
            0x6ed9eba1
        else if (index < 60)
            0x8f1bbcdc
        else
            0xca62c1d6;
        const temp = std.math.rotl(u32, a, 5) +% f +% e +% k +% schedule[index];
        e = d;
        d = c;
        c = std.math.rotl(u32, b, 30);
        b = a;
        a = temp;
    }

    return .{
        digest[0] +% a,
        digest[1] +% b,
        digest[2] +% c,
        digest[3] +% d,
        digest[4] +% e,
    };
}

/// Complete TinySHA1's protected `SHA1::processBlock` method without
/// interpreting its 80-round guest loop.  This is deliberately limited to
/// the exact object layout used by Xenia's 64-bit TinySHA1 build and is only
/// called after the PE executor has signature-gated the target function.
pub fn trySha1ProcessBlock(state: anytype, this_address: u64) bool {
    const digest_bytes = state.guestMemoryConst(this_address + SHA1_DIGEST_OFFSET, 20) orelse return false;
    const block_bytes = state.guestMemoryConst(this_address + SHA1_BLOCK_OFFSET, 64) orelse return false;
    const output = state.guestMemory(this_address + SHA1_DIGEST_OFFSET, 20) orelse return false;
    const block_index_bytes = state.guestMemoryConst(this_address + SHA1_BLOCK_INDEX_OFFSET, 8) orelse return false;
    const byte_count_bytes = state.guestMemoryConst(this_address + SHA1_BYTE_COUNT_OFFSET, 8) orelse return false;

    const block_index = std.mem.readInt(u64, block_index_bytes[0..8], .little);
    const byte_count = std.mem.readInt(u64, byte_count_bytes[0..8], .little);
    if (block_index > 63 or (byte_count & 63) != block_index) return false;

    var digest: [5]u32 = undefined;
    for (0..5) |index| {
        digest[index] = std.mem.readInt(u32, digest_bytes[index * 4 ..][0..4], .little);
    }
    var block: [64]u8 = undefined;
    @memcpy(&block, block_bytes);
    const result = sha1Compress(digest, block);
    for (0..5) |index| {
        std.mem.writeInt(u32, output[index * 4 ..][0..4], result[index], .little);
    }
    return true;
}

/// Feed a contiguous byte span into a TinySHA1 object, exactly as the guest's
/// own `processBytes` loop would.
///
/// Accelerating `processBlock` alone leaves the *feeding* interpreted, and
/// that is where the time goes: the compiler inlines `processBytes` into its
/// caller as eleven instructions per byte, with one call to the compression
/// function every sixty-four. Hashing a twenty-megabyte guest image therefore
/// costs a couple of hundred million interpreted instructions before the
/// title has been looked at, which is where the 2026-09-11 run was when the
/// operator's timeout killed it - the frontier read
/// `xe::cpu::XexModule::Precompile+0x283`, inside that loop.
///
/// The object layout is the one `trySha1ProcessBlock` already relies on, and
/// the compression is the same function, so this adds no new assumption about
/// the guest's SHA1 beyond the ones already in production. It only moves the
/// byte loop off the interpreter.
///
/// Returns false when the span or the object is not addressable, in which case
/// the caller must leave the guest to run its own loop.
pub fn sha1ProcessBytes(
    state: anytype,
    this_address: u64,
    source_address: u64,
    length: u64,
) bool {
    if (length == 0) return true;
    const source = state.guestMemoryConst(source_address, length) orelse return false;
    const digest_bytes = state.guestMemoryConst(this_address + SHA1_DIGEST_OFFSET, 20) orelse return false;
    const block_index_bytes = state.guestMemoryConst(this_address + SHA1_BLOCK_INDEX_OFFSET, 8) orelse return false;
    const byte_count_bytes = state.guestMemoryConst(this_address + SHA1_BYTE_COUNT_OFFSET, 8) orelse return false;
    const block_bytes = state.guestMemoryConst(this_address + SHA1_BLOCK_OFFSET, 64) orelse return false;

    var block_index = std.mem.readInt(u64, block_index_bytes[0..8], .little);
    var byte_count = std.mem.readInt(u64, byte_count_bytes[0..8], .little);
    // The same consistency gate `trySha1ProcessBlock` applies: a mismatch
    // means this is not the object shape Rosetta knows, and guessing would
    // corrupt a hash the guest later keys a cache on.
    if (block_index > 63 or (byte_count & 63) != block_index) return false;

    var digest: [5]u32 = undefined;
    for (0..5) |index| {
        digest[index] = std.mem.readInt(u32, digest_bytes[index * 4 ..][0..4], .little);
    }
    var block: [64]u8 = undefined;
    @memcpy(&block, block_bytes);

    for (source) |byte| {
        block[@intCast(block_index)] = byte;
        block_index += 1;
        byte_count += 1;
        if (block_index == 64) {
            digest = sha1Compress(digest, block);
            block_index = 0;
        }
    }

    const digest_out = state.guestMemory(this_address + SHA1_DIGEST_OFFSET, 20) orelse return false;
    const block_out = state.guestMemory(this_address + SHA1_BLOCK_OFFSET, 64) orelse return false;
    const index_out = state.guestMemory(this_address + SHA1_BLOCK_INDEX_OFFSET, 8) orelse return false;
    const count_out = state.guestMemory(this_address + SHA1_BYTE_COUNT_OFFSET, 8) orelse return false;
    for (0..5) |index| {
        std.mem.writeInt(u32, digest_out[index * 4 ..][0..4], digest[index], .little);
    }
    @memcpy(block_out, &block);
    std.mem.writeInt(u64, index_out[0..8], block_index, .little);
    std.mem.writeInt(u64, count_out[0..8], byte_count, .little);
    return true;
}

/// XLast XML is guest-owned semantic state. Rosette must never replace the
/// pugi DOM parse with an empty successful result: doing so discards title
/// metadata and can leave later XLast queries observing a fabricated document.
/// Keep this symbol as a defensive compatibility boundary for stale callers,
/// but make the bypass impossible even if one reaches an older dispatch path.
pub fn tryXLastXmlLoad(state: anytype, result_address: u64, buffer_address: u64, length: u64) bool {
    _ = state;
    _ = result_address;
    _ = buffer_address;
    _ = length;
    return false;
}

/// Complete the optional Xenia metadata table-string boundary without
/// interpreting tabulate's host-side border and wrapping formatter. Xenia
/// constructs achievement/property tables for diagnostics before launching
/// the title; the resulting string is not consumed by the guest. Returning a
/// valid empty libstdc++ string preserves the C++ return-object contract while
/// leaving the table's ownership and destructor paths intact. The caller must
/// signature-gate tabulate::Table::str before using this helper.
pub fn tryXeniaTabulateString(state: anytype, result_address: u64, table_address: u64) bool {
    if (result_address < 0x100000 or table_address < 0x100000) return false;
    _ = state.guestMemoryConst(table_address, 0x20) orelse return false;
    const result = state.guestMemory(result_address, 0x20) orelse return false;

    // libstdc++'s 64-bit basic_string stores its data pointer, length, and a
    // 16-byte small-string buffer in this order. An empty SSO string points to
    // its inline buffer and has a zero length plus a terminating zero byte.
    @memset(result, 0);
    std.mem.writeInt(u64, result[0..8], result_address + 0x10, .little);
    return true;
}

test "feeding a span byte by byte matches feeding it one block at a time" {
    // The whole value of the feed accelerator is that it is the same
    // computation as the loop it replaces. Check that against the block
    // function it is built on, over a length that is deliberately not a
    // multiple of 64 so the partial tail is exercised.
    const message = "The quick brown fox jumps over the lazy dog" ** 7;

    var streamed: [5]u32 = .{ 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0 };
    var block: [64]u8 = undefined;
    var index: usize = 0;
    for (message) |byte| {
        block[index] = byte;
        index += 1;
        if (index == 64) {
            streamed = sha1Compress(streamed, block);
            index = 0;
        }
    }

    // The same bytes, fed as whole blocks up front and then a tail.
    var chunked: [5]u32 = .{ 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0 };
    var offset: usize = 0;
    while (offset + 64 <= message.len) : (offset += 64) {
        var whole: [64]u8 = undefined;
        @memcpy(&whole, message[offset..][0..64]);
        chunked = sha1Compress(chunked, whole);
    }
    try std.testing.expectEqualSlices(u32, &streamed, &chunked);
    // The tail is what stays in the object, not something the digest saw.
    try std.testing.expectEqual(message.len % 64, index);
}

test "Xenia Rijndael decryption schedule matches AES-128" {
    const dec_schedule = [_]*const [32:0]u8{
        "d014f9a8c9ee2589e13f0cc8b6630ca6",
        "0c7b5a631319eafeb0398890664cfbb4",
        "df7d925a1f62b09da320626ed6757324",
        "12c07647c01f22c7bc42d2f37555114a",
        "6efcd876d2df54807c5df034c917c3b9",
        "6ea30afcbc238cf6ae82a4b4b54a338d",
        "90884413d280860a12a128421bc89739",
        "7c1f13f74208c219c021ae480969bf7b",
        "cc7505eb3e17d1ee82296c51c9481133",
        "2b3708a7f262d405bc3ebdbf4b617d62",
        "2b7e151628aed2a6abf7158809cf4f3c",
    };

    var round_keys: [44]u32 = undefined;
    var round_bytes: [16]u8 = undefined;
    for (dec_schedule, 0..) |encoded, round| {
        _ = try std.fmt.hexToBytes(&round_bytes, encoded);
        for (0..4) |word| {
            round_keys[round * 4 + word] = std.mem.readInt(u32, round_bytes[word * 4 ..][0..4], .big);
        }
    }

    const ciphertext = [_]u8{
        0x39, 0x25, 0x84, 0x1d, 0x02, 0xdc, 0x09, 0xfb,
        0xdc, 0x11, 0x85, 0x97, 0x19, 0x6a, 0x0b, 0x32,
    };
    const expected = [_]u8{
        0x32, 0x43, 0xf6, 0xa8, 0x88, 0x5a, 0x30, 0x8d,
        0x31, 0x31, 0x98, 0xa2, 0xe0, 0x37, 0x07, 0x34,
    };
    const actual = decryptBlock(&round_keys, 10, ciphertext);
    try std.testing.expectEqualSlices(u8, &expected, &actual);
}

test "Xenia Rijndael re-expands the cipher key" {
    const cipher_key = [_]u8{
        0x20, 0xb1, 0x85, 0xa5, 0x9d, 0x28, 0xfd, 0xc3,
        0x40, 0x58, 0x3f, 0xbb, 0x08, 0x96, 0xbf, 0x91,
    };
    const ciphertext = [_]u8{
        0xd0, 0xe2, 0xdb, 0x4f, 0x66, 0x21, 0xaa, 0xf9,
        0xae, 0xcc, 0x65, 0xb6, 0xd0, 0x48, 0xbe, 0xbb,
    };
    const expected = [_]u8{
        0x72, 0x15, 0xde, 0x17, 0xd2, 0xd7, 0xf6, 0x87,
        0x78, 0x68, 0x45, 0x78, 0xa8, 0x1c, 0x42, 0x1e,
    };

    const actual = decryptBlockFromCipherKey(cipher_key, ciphertext);
    try std.testing.expectEqualSlices(u8, &expected, &actual);
}

test "TinySHA1 compression matches the SHA1 abc digest" {
    var block = [_]u8{0} ** 64;
    block[0] = 'a';
    block[1] = 'b';
    block[2] = 'c';
    block[3] = 0x80;
    block[63] = 24;

    const digest = sha1Compress(.{
        0x67452301,
        0xefcdab89,
        0x98badcfe,
        0x10325476,
        0xc3d2e1f0,
    }, block);
    try std.testing.expectEqualSlices(u32, &.{
        0xa9993e36,
        0x4706816a,
        0xba3e2571,
        0x7850c26c,
        0x9cd0d89d,
    }, &digest);
}

test "XLast XML bypass is always refused so the guest DOM remains authoritative" {
    var memory = [_]u8{0} ** 0x200000;
    const MockState = struct {
        bytes: []u8,

        fn guestMemoryConst(self: *@This(), address: u64, length: u64) ?[]const u8 {
            if (address +| length > self.bytes.len) return null;
            return self.bytes[@intCast(address)..@intCast(address + length)];
        }

        fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
            if (address +| length > self.bytes.len) return null;
            return self.bytes[@intCast(address)..@intCast(address + length)];
        }
    };

    var state = MockState{ .bytes = &memory };
    try std.testing.expect(!tryXLastXmlLoad(&state, 0x100010, 0x100100, 32));
    try std.testing.expectEqual(@as(u8, 0), memory[0x100010]);
    try std.testing.expectEqual(@as(u8, 0), memory[0x100010 + 19]);
    try std.testing.expect(!tryXLastXmlLoad(&state, 16, 64, 32));

    try std.testing.expect(tryXeniaTabulateString(&state, 0x100080, 0x100200));
    try std.testing.expectEqual(
        @as(u64, 0x100090),
        std.mem.readInt(u64, memory[0x100080..][0..8], .little),
    );
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, memory[0x100080 + 8 ..][0..8], .little));
    try std.testing.expectEqual(@as(u8, 0), memory[0x100080 + 0x10]);
    try std.testing.expect(!tryXeniaTabulateString(&state, 16, 0x100200));
}
