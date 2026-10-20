//! Exit-edge flag records (`block_jit/exit_flags.zig`) through the production
//! translator and glue: a `cmp ; jl` leaves a record on both of its exit
//! edges, the blocks it reaches read those flags first (`setl`, `setge`) and
//! settle the record at their entry, a block that writes every flag first
//! clears it, and everything ends exactly as interpreted - with the
//! deferral on and off.
const P = @import("../../process.zig");
const I = P.__ProcessInternals;
const std = I._std;
const t = std.testing;
const ElfState = P.ElfState;
const MEM_BASE = I._MEM_BASE;
const block_jit = I._block_jit;

const code: usize = 0x100000;
const data: usize = 0x20000;
const stack_top: usize = 0x7f000;

/// L: mov eax,[rsi+4*rcx] ; cmp eax,edx ; jl B ; jmp C
/// B: setl r9b ; movzx r9d,r9b ; add r10,r9 ; mov [rsi+4*rcx],edx ; jmp N
/// C: setge r9b ; mov ebx,[rsi] ; movzx r9d,r9b ; add r11,r9 ; test eax,1 ;
///    jnz N2 ; jmp N
/// N2: mov [rsi+4*rcx],eax ; add r12,rax
/// N: inc ecx ; and ecx,63 ; add edx,37 ; and edx,255 ; dec r8 ; jnz L ;
///    cmp rsp,rsp ; D: jmp D           (llvm-mc, Intel syntax)
const program = [_]u8{
    0x8b, 0x04, 0x8e, 0x39, 0xd0, 0x7c, 0x02, 0xeb, 0x10, 0x41, 0x0f, 0x9c, 0xc1, 0x45, 0x0f, 0xb6,
    0xc9, 0x4d, 0x01, 0xca, 0x89, 0x14, 0x8e, 0xeb, 0x1c, 0x41, 0x0f, 0x9d, 0xc1, 0x8b, 0x1e, 0x45,
    0x0f, 0xb6, 0xc9, 0x4d, 0x01, 0xcb, 0xa9, 0x01, 0x00, 0x00, 0x00, 0x75, 0x02, 0xeb, 0x06, 0x89,
    0x04, 0x8e, 0x49, 0x01, 0xc4, 0xff, 0xc1, 0x83, 0xe1, 0x3f, 0x83, 0xc2, 0x25, 0x81, 0xe2, 0xff,
    0x00, 0x00, 0x00, 0x49, 0xff, 0xc8, 0x75, 0xb8, 0x48, 0x39, 0xe4, 0xeb, 0xfe,
};
const done_offset = 0x4b;

const Result = struct {
    regs: [8]u64,
    rflags: u64,
    memory: u64,
    records: u64 = 0,
    completions: u64 = 0,
    hops: u64 = 0,
};

fn run(translate: bool, deferral: bool, passes: u64) !Result {
    const saved = block_jit.exit_flags.enabled;
    defer block_jit.exit_flags.enabled = saved;
    block_jit.exit_flags.enabled = deferral;
    const records_before = block_jit.exit_flags.compiled_records;
    var state = ElfState.init(t.allocator);
    defer state.deinit();
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    state.windows_runtime_enabled = true;
    state.image_low = MEM_BASE + code;
    state.image_high = MEM_BASE + code + 0x100;
    state.configureWindowsExecutableRanges(&[_]I._WindowsExecutableRange{.{ .guest_base = MEM_BASE + code, .length = 0x100 }});
    @memcpy(state.mem[code..][0..program.len], &program);
    var prng = std.Random.DefaultPrng.init(0xf1a9);
    for (0..64) |i| std.mem.writeInt(u32, state.mem[data + 4 * i ..][0..4], prng.random().int(u8), .little);
    state.block_jit_enabled = translate;
    state.block_jit_hot_threshold = 1;
    state.regs = .{ .rip = MEM_BASE + code, .rsp = MEM_BASE + stack_top, .rsi = MEM_BASE + data, .r8 = passes, .rdx = 100, .rflags = 0x2 };
    var steps: usize = 0;
    while (state.regs.rip != MEM_BASE + code + done_offset and !state.terminated) : (steps += 1) {
        _ = state.step();
        try t.expect(steps < 50_000_000);
    }
    try t.expectEqual(@as(u64, MEM_BASE + code + done_offset), state.regs.rip);
    var hash: u64 = 0xcbf29ce484222325;
    for (state.mem[data..][0 .. 64 * 4]) |byte| hash = (hash ^ byte) *% 0x100000001b3;
    var result: Result = .{
        .regs = .{ state.regs.rax, state.regs.rbx, state.regs.rcx, state.regs.rdx, state.regs.r9, state.regs.r10, state.regs.r11, state.regs.r12 },
        .rflags = state.regs.rflags & 0x8D5,
        .memory = hash,
        .records = block_jit.exit_flags.compiled_records -% records_before,
    };
    if (state.block_jit) |jit| {
        result.completions = jit.flag_completions;
        result.hops = jit.native_chain_hops;
    }
    return result;
}

test "exit flags: records left on exit edges are settled or cleared by the next block, exactly as interpreted" {
    if (!block_jit.CodeMemory.available()) return error.SkipZigTest;
    const passes: u64 = 3000;
    const reference = try run(false, true, passes);
    const deferred = try run(true, true, passes);
    const eager = try run(true, false, passes);
    for ([_]Result{ deferred, eager }) |translated| {
        try t.expectEqualSlices(u64, &reference.regs, &translated.regs);
        try t.expectEqual(reference.rflags, translated.rflags);
        try t.expectEqual(reference.memory, translated.memory);
        try t.expect(translated.hops > passes);
    }
    // Both exits of `cmp ; jl` and `test ; jnz` leave records, and B and C,
    // which read the flags first, settled them at their entry.
    try t.expect(deferred.records >= 2);
    try t.expect(deferred.completions > passes / 2);
    try t.expectEqual(@as(u64, 0), eager.records);
    // The program took both edges of each branch.
    try t.expect(reference.regs[5] > 0 and reference.regs[6] > 0 and reference.regs[7] > 0);
}
