const std = @import("std");

const aes = std.crypto.core.aes;

const MAX_AES_ROUNDS: u32 = 14;

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
    const plaintext = decryptBlock(round_keys[0..word_count], nr, ciphertext);
    state.writeMem128(plaintext_address, plaintext);
    return true;
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
