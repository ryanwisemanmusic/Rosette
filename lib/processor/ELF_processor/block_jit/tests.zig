const core = @import("core.zig");
const std = @import("std");
const a64 = core._test_api._a64;
const host_fp_control = core._test_api._host_fp_control;
const x64_decoder = core._test_api._x64_decoder;
const Assembler = core._test_api._Assembler;
const Label = core._test_api._Label;
const CodeMemory = core._test_api._CodeMemory;
const CodeMemoryError = core._test_api._CodeMemoryError;
const DecodedInsn = core._test_api._DecodedInsn;
const Op = core._test_api._Op;
const RegId = core._test_api._RegId;
const Size = core._test_api._Size;
const Cond = core._test_api._Cond;
const Segment = core._test_api._Segment;
const Regs = core._test_api._Regs;
const Error = core._test_api._Error;
const Helpers = core._test_api._Helpers;
const helper_read_offset = core._test_api._helper_read_offset;
const helper_write_offset = core._test_api._helper_write_offset;
const helper_read128_offset = core._test_api._helper_read128_offset;
const helper_write128_offset = core._test_api._helper_write128_offset;
const helper_write128_non_temporal_offset = core._test_api._helper_write128_non_temporal_offset;
const helper_mapped_transfer_offset = core._test_api._helper_mapped_transfer_offset;
const helper_hooked_transfer_offset = core._test_api._helper_hooked_transfer_offset;
const helper_import_transfer_offset = core._test_api._helper_import_transfer_offset;
const helper_x87_raw_transfer_offset = core._test_api._helper_x87_raw_transfer_offset;
const helper_x87_memory_offset = core._test_api._helper_x87_memory_offset;
const helper_interpret_offset = core._test_api._helper_interpret_offset;
const helper_block_offset = core._test_api._helper_block_offset;
const helper_flags_offset = core._test_api._helper_flags_offset;
const Scratch = core._test_api._Scratch;
const chain_count_shift = core._test_api._chain_count_shift;
const chain_count_blocks_mask = core._test_api._chain_count_blocks_mask;
const hoist_hosts = core._test_api._hoist_hosts;
const hoist_max_span = core._test_api._hoist_max_span;
const hoist_disp_bias = core._test_api._hoist_disp_bias;
const HoistCandidate = core._test_api._HoistCandidate;
const Hoist = core._test_api._Hoist;
const HoistedOffset = core._test_api._HoistedOffset;
const FusedExit = core._test_api._FusedExit;
const ColdAccess = core._test_api._ColdAccess;
const ColdAbortExit = core._test_api._ColdAbortExit;
const ColdMemory = core._test_api._ColdMemory;
const hoistCandidate = core._test_api._hoistCandidate;
const mayStoreMemoryOperand = core._test_api._mayStoreMemoryOperand;
const tlbProbeSpanProven = core._test_api._tlbProbeSpanProven;
const FlagKind = core._test_api._FlagKind;
const Tlb = core._test_api._Tlb;
const armConditionHolds = core._test_api._armConditionHolds;
const tlb_write_offset = core._test_api._tlb_write_offset;
const Layout = core._test_api._Layout;
const RegisterFiles = core._test_api._RegisterFiles;
const hook_filter_bytes = core._test_api._hook_filter_bytes;
const hook_filter_shift = core._test_api._hook_filter_shift;
const hook_filter_multiplier = core._test_api._hook_filter_multiplier;
const hookFilterBit = core._test_api._hookFilterBit;
const hookFilterAdd = core._test_api._hookFilterAdd;
const hookFilterHas = core._test_api._hookFilterHas;
const scratch_abort_offset = core._test_api._scratch_abort_offset;
const scratch_call_guard_offset = core._test_api._scratch_call_guard_offset;
const scratch_jmp_guard_offset = core._test_api._scratch_jmp_guard_offset;
const scratch_ret_guard_offset = core._test_api._scratch_ret_guard_offset;
const scratch_direct_non_temporal_offset = core._test_api._scratch_direct_non_temporal_offset;
const scratch_regs_file_offset = core._test_api._scratch_regs_file_offset;
const scratch_xmm_file_offset = core._test_api._scratch_xmm_file_offset;
const scratch_ymm_hi_file_offset = core._test_api._scratch_ymm_hi_file_offset;
const scratch_zmm_hi_file_offset = core._test_api._scratch_zmm_hi_file_offset;
const scratch_tlb_file_offset = core._test_api._scratch_tlb_file_offset;
const scratch_transfer_target_offset = core._test_api._scratch_transfer_target_offset;
const scratch_index_offset = core._test_api._scratch_index_offset;
const scratch_vector_offset = core._test_api._scratch_vector_offset;
const scratch_flag_kind_offset = core._test_api._scratch_flag_kind_offset;
const scratch_flag_size_offset = core._test_api._scratch_flag_size_offset;
const scratch_flag_a_offset = core._test_api._scratch_flag_a_offset;
const scratch_flag_b_offset = core._test_api._scratch_flag_b_offset;
const scratch_flag_r_offset = core._test_api._scratch_flag_r_offset;
const scratch_chain_break_offset = core._test_api._scratch_chain_break_offset;
const scratch_chain_count_offset = core._test_api._scratch_chain_count_offset;
const scratch_chain_budget_offset = core._test_api._scratch_chain_budget_offset;
const scratch_chain_retired_image_offset = core._test_api._scratch_chain_retired_image_offset;
const scratch_chain_retired_other_mapped_offset = core._test_api._scratch_chain_retired_other_mapped_offset;
const scratch_chain_previous_offset = core._test_api._scratch_chain_previous_offset;
const scratch_jump_cache_offset = core._test_api._scratch_jump_cache_offset;
const scratch_fused_a_offset = core._test_api._scratch_fused_a_offset;
const scratch_fused_b_offset = core._test_api._scratch_fused_b_offset;
const scratch_fused_r_offset = core._test_api._scratch_fused_r_offset;
const scratch_saved_nzcv_offset = core._test_api._scratch_saved_nzcv_offset;
const scratch_skip_spill_offset = core._test_api._scratch_skip_spill_offset;
const scratch_fpcr_writes_offset = core._test_api._scratch_fpcr_writes_offset;
const scratch_block_offset = core._test_api._scratch_block_offset;
const FallbackReason = core._test_api._FallbackReason;
const Insn = core._test_api._Insn;
const BlockFn = core._test_api._BlockFn;
const Block = core._test_api._Block;
const link_ways = core._test_api._link_ways;
const Link = core._test_api._Link;
const jump_cache_entries = core._test_api._jump_cache_entries;
const jump_cache_shift = core._test_api._jump_cache_shift;
const jumpCacheIndex = core._test_api._jumpCacheIndex;
const Compiled = core._test_api._Compiled;
const isNative = core._test_api._isNative;
const isX87RawTransfer = core._test_api._isX87RawTransfer;
const isTerminator = core._test_api._isTerminator;
const isConditionalBranch = core._test_api._isConditionalBranch;
const isFallbackTerminator = core._test_api._isFallbackTerminator;
const endsBlockBefore = core._test_api._endsBlockBefore;
const memoryOperandSupported = core._test_api._memoryOperandSupported;
const r_state = core._test_api._r_state;
const r_regs = core._test_api._r_regs;
const r_helpers = core._test_api._r_helpers;
const r_scratch = core._test_api._r_scratch;
const r_tlb = core._test_api._r_tlb;
const r_spare = core._test_api._r_spare;
const cache_host_regs = core._test_api._cache_host_regs;
const cache_callee_saved = core._test_api._cache_callee_saved;
const cache_min_uses = core._test_api._cache_min_uses;
const skip_reg = core._test_api._skip_reg;
const t0 = core._test_api._t0;
const t1 = core._test_api._t1;
const t2 = core._test_api._t2;
const t3 = core._test_api._t3;
const t4 = core._test_api._t4;
const t5 = core._test_api._t5;
const t6 = core._test_api._t6;
const rip_offset = core._test_api._rip_offset;
const rflags_offset = core._test_api._rflags_offset;
const mxcsr_offset = core._test_api._mxcsr_offset;
const SegmentStateType = core._test_api._SegmentStateType;
const fs_base_offset = core._test_api._fs_base_offset;
const gs_base_offset = core._test_api._gs_base_offset;
const RFL_CF = core._test_api._RFL_CF;
const RFL_PF = core._test_api._RFL_PF;
const RFL_AF = core._test_api._RFL_AF;
const RFL_ZF = core._test_api._RFL_ZF;
const RFL_SF = core._test_api._RFL_SF;
const RFL_OF = core._test_api._RFL_OF;
const bits = core._test_api._bits;
const maskFor = core._test_api._maskFor;
const arm = core._test_api._arm;
const memSize = core._test_api._memSize;
const gprOffset = core._test_api._gprOffset;
const signExtendImm8 = core._test_api._signExtendImm8;
const immForSize = core._test_api._immForSize;
const ArithKind = core._test_api._ArithKind;
const defer_flags = core._test_api._defer_flags;
const BinaryOp = core._test_api._BinaryOp;
const BinaryShape = core._test_api._BinaryShape;
const binaryOpOf = core._test_api._binaryOpOf;
const binaryShapeOf = core._test_api._binaryShapeOf;
const binaryTouchesMemory = core._test_api._binaryTouchesMemory;
const ImmediateShape = core._test_api._ImmediateShape;
const immediateShapeOf = core._test_api._immediateShapeOf;
const immediateValue = core._test_api._immediateValue;
const isIncDec = core._test_api._isIncDec;
const incDecSize = core._test_api._incDecSize;
const F_CF = core._test_api._F_CF;
const F_PF = core._test_api._F_PF;
const F_AF = core._test_api._F_AF;
const F_ZF = core._test_api._F_ZF;
const F_SF = core._test_api._F_SF;
const F_OF = core._test_api._F_OF;
const F_ALL = core._test_api._F_ALL;
const conditionReads = core._test_api._conditionReads;
const liveFlagBits = core._test_api._liveFlagBits;
const FlagEffects = core._test_api._FlagEffects;
const shiftCount = core._test_api._shiftCount;
const flagEffects = core._test_api._flagEffects;
const flagWants = core._test_api._flagWants;
const flagLiveness = core._test_api._flagLiveness;
const flagLivenessToExit = core._test_api._flagLivenessToExit;
const flagLivenessToExitFall = core._test_api._flagLivenessToExitFall;
const FusedKind = core._test_api._FusedKind;
const Fused = core._test_api._Fused;
const fusedCondition = core._test_api._fusedCondition;
const flagLivenessFrom = core._test_api._flagLivenessFrom;
const v0 = core._test_api._v0;
const v1 = core._test_api._v1;
const v2 = core._test_api._v2;
const v3 = core._test_api._v3;
const v4 = core._test_api._v4;
const v5 = core._test_api._v5;
const v6 = core._test_api._v6;
const v7 = core._test_api._v7;
const evexRouted = core._test_api._evexRouted;
const VectorBinary = core._test_api._VectorBinary;
const packedIntegerForm = core._test_api._packedIntegerForm;
const FloatBinary = core._test_api._FloatBinary;
const PackedFloatForm = core._test_api._PackedFloatForm;
const packedFloatForm = core._test_api._packedFloatForm;
const scalarFloatForm = core._test_api._scalarFloatForm;
const VectorBitwise = core._test_api._VectorBitwise;
const bitwiseForm = core._test_api._bitwiseForm;
const unpackForm = core._test_api._unpackForm;
const ShiftKind = core._test_api._ShiftKind;
const shiftForm = core._test_api._shiftForm;
const extendForm = core._test_api._extendForm;
const ymmMoveForm = core._test_api._ymmMoveForm;
const AtomicForm = core._test_api._AtomicForm;
const atomicForm = core._test_api._atomicForm;
const lockPrefixAllowed = core._test_api._lockPrefixAllowed;
const isVectorNative = core._test_api._isVectorNative;
const ExitStub = core._test_api._ExitStub;
const r_exit_rip = core._test_api._r_exit_rip;
const Compiler = core._test_api._Compiler;
const Ledger = core._test_api._Ledger;
const Options = core._test_api._Options;
const isCallOrReturn = core._test_api._isCallOrReturn;
const isPureFlagWriter = core._test_api._isPureFlagWriter;
const isStackAdjustment = core._test_api._isStackAdjustment;
const returnFlagsLive = core._test_api._returnFlagsLive;
const exitFlagsLive = core._test_api._exitFlagsLive;
const compile = core._test_api._compile;
const compileWith = core._test_api._compileWith;
const EmittedBlock = core._test_api._EmittedBlock;
const emitBlock = core._test_api._emitBlock;
const testing = std.testing;

pub const TestState = struct {
    regs: Regs = .{},
    scratch: Scratch = .{},
    tlb: Tlb = Tlb.empty,
    xmm: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    ymm_hi: [32][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 32,
    zmm_hi: [32][32]u8 = [_][32]u8{[_]u8{0} ** 32} ** 32,
    reads: u32 = 0,
    writes: u32 = 0,
    non_temporal_writes: u32 = 0,
    interprets: u32 = 0,
    poison_upper_on_interpret: bool = false,
    x87_fast_helpers: u32 = 0,
    x87_memory_helpers: u32 = 0,
    flag_completions: u32 = 0,
    last_interpret_index: u32 = 0,
    last_helper_index: u32 = 0,
    interpret_result: u32 = 0,
    /// The flags the interpret helper saw, so a test can prove the writer
    /// before a fallback still materialised them.
    flags_at_interpret: u32 = 0,
    abort_on_access: bool = false,
    /// The two pieces of state the native transfer templates read before
    /// they will run, standing in for the glue's own fields.
    trace_calls: bool = false,
    trace_transfers: bool = false,
    return_captures: u32 = 0,
    image_low: u64 = 0,
    image_high: u64 = 0,
    code_cache_low: u64 = 0,
    code_cache_high: u64 = 0,
    iat_low: u64 = 0,
    iat_high: u64 = 0,
    mapped_transfer_allowed: bool = false,
    mapped_transfer_calls: u32 = 0,
    hooked_transfer_calls: u32 = 0,
    xbox_transfer_allowed: bool = false,
    xbox_transfer_calls: u32 = 0,
    xbox_transfer_target: u64 = 0,
    xbox_transfer_return_rip: u64 = 0,
    exact_hook_targets: [8]u64 = @splat(0),
    exact_hook_target_count: u8 = 0,
    /// Whether the import-lane stand-in answers an import slot, and what it
    /// was asked.
    import_lane_answers: bool = false,
    import_transfer_calls: u32 = 0,
    last_import_slot: u64 = 0,
    hook_filter: [hook_filter_bytes]u8 = @splat(0),
    xbox_critical_section_enter: u64 = 0,
    xbox_critical_section_leave: u64 = 0,
    image_targets_hooked: u8 = 1,
    memory: [4096]u8 align(16) = [_]u8{0} ** 4096,

    pub const layout = Layout{
        .regs_offset = @offsetOf(TestState, "regs"),
        .scratch_offset = @offsetOf(TestState, "scratch"),
        .tlb_offset = @offsetOf(TestState, "tlb"),
        .xmm_offset = @offsetOf(TestState, "xmm"),
        .ymm_hi_offset = @offsetOf(TestState, "ymm_hi"),
        .zmm_hi_offset = @offsetOf(TestState, "zmm_hi"),
        .trace_calls_offset = @offsetOf(TestState, "trace_calls"),
        .return_captures_offset = @offsetOf(TestState, "return_captures"),
        .trace_transfers_offset = @offsetOf(TestState, "trace_transfers"),
        .image_low_offset = @offsetOf(TestState, "image_low"),
        .image_high_offset = @offsetOf(TestState, "image_high"),
        .code_cache_low_offset = @offsetOf(TestState, "code_cache_low"),
        .code_cache_high_offset = @offsetOf(TestState, "code_cache_high"),
        .iat_low_offset = @offsetOf(TestState, "iat_low"),
        .iat_high_offset = @offsetOf(TestState, "iat_high"),
        .hook_filter_offset = @offsetOf(TestState, "hook_filter"),
        .xbox_critical_section_enter_offset = @offsetOf(TestState, "xbox_critical_section_enter"),
        .xbox_critical_section_leave_offset = @offsetOf(TestState, "xbox_critical_section_leave"),
        .image_targets_hooked_offset = @offsetOf(TestState, "image_targets_hooked"),
    };

    fn read(state_ptr: *anyopaque, address: u64, size: u8) callconv(.c) u64 {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.reads += 1;
        state.last_helper_index = state.scratch.index;
        if (state.abort_on_access) {
            state.scratch.abort = 1;
            state.scratch.chain_break = 1;
        }
        const width: usize = @as(usize, 1) << @intCast(size);
        if (address +| width > state.memory.len) return 0;
        var value: u64 = 0;
        for (0..width) |i| value |= @as(u64, state.memory[@intCast(address + i)]) << @intCast(i * 8);
        return value;
    }

    fn write(state_ptr: *anyopaque, address: u64, size: u8, value: u64) callconv(.c) void {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.writes += 1;
        state.last_helper_index = state.scratch.index;
        if (state.abort_on_access) {
            state.scratch.abort = 1;
            state.scratch.chain_break = 1;
        }
        const width: usize = @as(usize, 1) << @intCast(size);
        if (address +| width > state.memory.len) return;
        for (0..width) |i| state.memory[@intCast(address + i)] = @truncate(value >> @intCast(i * 8));
    }

    fn read128(state_ptr: *anyopaque, address: u64, out: *[16]u8) callconv(.c) void {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.reads += 1;
        state.last_helper_index = state.scratch.index;
        if (state.abort_on_access) {
            state.scratch.abort = 1;
            state.scratch.chain_break = 1;
        }
        out.* = @splat(0);
        if (address +| 16 > state.memory.len) return;
        @memcpy(out, state.memory[@intCast(address)..][0..16]);
    }

    fn write128(state_ptr: *anyopaque, address: u64, value: *const [16]u8) callconv(.c) void {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.writes += 1;
        state.last_helper_index = state.scratch.index;
        if (state.abort_on_access) {
            state.scratch.abort = 1;
            state.scratch.chain_break = 1;
        }
        if (address +| 16 > state.memory.len) return;
        @memcpy(state.memory[@intCast(address)..][0..16], value);
    }

    fn write128NonTemporal(state_ptr: *anyopaque, address: u64, value: *const [16]u8) callconv(.c) void {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.non_temporal_writes += 1;
        state.last_helper_index = state.scratch.index;
        if (state.abort_on_access) {
            state.scratch.abort = 1;
            state.scratch.chain_break = 1;
        }
        if (address +| 16 > state.memory.len) return;
        @memcpy(state.memory[@intCast(address)..][0..16], value);
    }

    fn mappedTransfer(state_ptr: *anyopaque, target: u64) callconv(.c) u8 {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.mapped_transfer_calls += 1;
        return @intFromBool(state.mapped_transfer_allowed and target >= 0xA000_0000 and target < 0xB000_0000);
    }

    /// The runtime's lock-free import lane, standing in: when it answers, a
    /// call returns to its next RIP and a thunk's jump pops its caller's
    /// return address, with RAX set to a marker.
    fn importTransfer(state_ptr: *anyopaque, slot: u64, call_return: u64) callconv(.c) u32 {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.import_transfer_calls += 1;
        state.last_import_slot = slot;
        if (!state.import_lane_answers) return 0;
        if (call_return != 0) {
            state.regs.rip = call_return;
        } else {
            const rsp: usize = @intCast(state.regs.rsp);
            state.regs.rip = std.mem.readInt(u64, state.memory[rsp..][0..8], .little);
            state.regs.rsp += 8;
        }
        state.regs.rax = 0x1A7E;
        return 1;
    }

    fn hookedTransfer(state_ptr: *anyopaque, target: u64) callconv(.c) u8 {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.hooked_transfer_calls += 1;
        for (state.exact_hook_targets[0..state.exact_hook_target_count]) |hook| {
            if (hook == target) return 1;
        }
        return 0;
    }

    fn xboxCriticalSectionTransfer(state_ptr: *anyopaque, target: u64, return_rip: u64) callconv(.c) u32 {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.xbox_transfer_calls += 1;
        state.xbox_transfer_target = target;
        state.xbox_transfer_return_rip = return_rip;
        return @intFromBool(state.xbox_transfer_allowed);
    }

    fn x87RawTransfer(state_ptr: *anyopaque, block: *const Block, index: u32) callconv(.c) u32 {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.x87_fast_helpers += 1;
        state.regs.rip = block.insns[index].rip;
        return 0;
    }

    fn x87Memory(state_ptr: *anyopaque, block: *const Block, index: u32) callconv(.c) u32 {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        state.x87_memory_helpers += 1;
        state.regs.rip = block.insns[index].rip;
        return 0;
    }

    /// Settle the deferred flag record exactly as the glue's helper does,
    /// so a test sees the flags the interpreter would have seen.
    fn flags(state_ptr: *anyopaque) callconv(.c) void {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        if (state.scratch.flag_kind == 0) return;
        state.flag_completions += 1;
        const size: Size = @enumFromInt(state.scratch.flag_size);
        switch (state.scratch.flag_kind) {
            @intFromEnum(FlagKind.add) => x64_decoder.applyAdd(&state.regs.rflags, state.scratch.flag_a, state.scratch.flag_b, state.scratch.flag_r, size),
            @intFromEnum(FlagKind.sub) => x64_decoder.applySub(&state.regs.rflags, state.scratch.flag_a, state.scratch.flag_b, state.scratch.flag_r, size),
            @intFromEnum(FlagKind.logic) => x64_decoder.applyLogic(&state.regs.rflags, state.scratch.flag_r, size),
            else => {},
        }
        state.scratch.flag_kind = 0;
    }

    fn interpret(state_ptr: *anyopaque, block: *const Block, index: u32) callconv(.c) u32 {
        const state: *TestState = @ptrCast(@alignCast(state_ptr));
        flags(state_ptr);
        state.interprets += 1;
        if (state.poison_upper_on_interpret) {
            state.ymm_hi[0] = @splat(0xA5);
            state.zmm_hi[0] = @splat(0xC7);
        }
        state.last_interpret_index = index;
        state.flags_at_interpret = state.regs.rflags;
        // The scratch index must agree with the argument.
        if (state.scratch.index != index) state.regs.r15 = 0xBAD_1DE7;
        // Pretend the instruction advanced RIP by its length, as `execute`
        // would for a non-branch.
        const insn = block.insns[index];
        state.regs.rip = insn.rip + insn.len;
        return state.interpret_result;
    }

    /// Admit the whole test memory (guest page 0) to the TLB.
    pub fn admitMemory(self: *TestState, reads: bool, writes: bool) void {
        if (reads) self.tlb.fill(false, 0, &self.memory);
        if (writes) self.tlb.fill(true, 0, &self.memory);
    }
};

pub const TestHarness = struct {
    memory: CodeMemory,
    block: Block,
    insns: std.ArrayList(Insn),
    flags_elided: u32 = 0,

    pub fn init() !TestHarness {
        if (!CodeMemory.available()) return error.SkipZigTest;
        return .{
            .memory = try CodeMemory.init(8 * 1024 * 1024),
            .block = undefined,
            .insns = .empty,
        };
    }

    pub fn deinit(self: *TestHarness) void {
        self.insns.deinit(testing.allocator);
        self.memory.deinit();
    }

    pub fn add(self: *TestHarness, rip: u64, len: u8, d: DecodedInsn) !void {
        var decoded = d;
        decoded.len = len;
        try self.insns.append(testing.allocator, .{ .rip = rip, .len = len, .decoded = decoded, .segment = .ds });
    }

    /// Compile the queued instructions and run them once on `state`.
    pub fn run(self: *TestHarness, state: *TestState) !u32 {
        return self.runWith(state, .{});
    }

    /// `run` with the compile options the glue passes, e.g. the Windows
    /// calling convention's `flags_dead_at_calls`.
    pub fn runWith(self: *TestHarness, state: *TestState, options: Options) !u32 {
        const insns = self.insns.items;
        const last = insns[insns.len - 1];
        const compiled = try compileWith(testing.allocator, &self.memory, TestState.layout, insns, last.rip + last.len, options);
        self.flags_elided = compiled.flags_elided;
        self.block = .{
            .helpers = undefined,
            .start_rip = insns[0].rip,
            .end_rip = last.rip + last.len,
            .insns = insns,
            .bytes = &.{},
            .code = compiled.code,
            .native_count = compiled.native_count,
            .fallback_count = compiled.fallback_count,
            .register_only = compiled.register_only,
        };
        self.block.helpers = .{
            .read = TestState.read,
            .write = TestState.write,
            .read128 = TestState.read128,
            .write128 = TestState.write128,
            .write128_non_temporal = TestState.write128NonTemporal,
            .mapped_transfer = TestState.mappedTransfer,
            .hooked_transfer = TestState.hookedTransfer,
            .xbox_critical_section_transfer = TestState.xboxCriticalSectionTransfer,
            .import_transfer = TestState.importTransfer,
            .x87_raw_transfer = TestState.x87RawTransfer,
            .x87_memory = TestState.x87Memory,
            .interpret = TestState.interpret,
            .block = &self.block,
            .flags = TestState.flags,
        };
        state.scratch.abort = 0;
        state.scratch.block = &self.block;
        // What the glue derives from the state at every entry.
        state.scratch.call_guard = @intFromBool(state.trace_calls or state.trace_transfers);
        state.scratch.jmp_guard = @intFromBool(state.trace_transfers);
        state.scratch.ret_guard = @intFromBool(state.trace_calls or state.return_captures != 0);
        return self.block.entry()(state, &self.block.helpers, &state.scratch);
    }
};

fn regReg(op: Op, size: Size, dst: RegId, src: RegId) DecodedInsn {
    return .{ .op = op, .size = size, .dst_reg = dst, .src_reg = src, .is_reg_form = true };
}

fn regImm(op: Op, size: Size, dst: RegId, imm: u64) DecodedInsn {
    return .{ .op = op, .size = size, .dst_reg = dst, .imm = imm, .is_reg_form = true, .uses_imm = true };
}

/// A memory operand `[rbx + disp]`.
fn baseDisp(op: Op, size: Size, reg: RegId, disp: u64) DecodedInsn {
    return .{ .op = op, .size = size, .dst_reg = reg, .src_reg = reg, .addr = disp, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx };
}

fn baseDispAt(op: Op, size: Size, base: RegId, disp: u64) DecodedInsn {
    return .{ .op = op, .size = size, .dst_reg = base, .src_reg = base, .addr = disp, .sib_has_base = true, .sib_base_reg = base };
}
test "register moves respect operand width and zero extension" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.regs.rax = 0x1122_3344_5566_7788;
    state.regs.rbx = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rcx = 0xAAAA_AAAA_AAAA_AAAA;
    // mov ebx, eax ; mov cl, al ; mov ch, al ; mov dx, ax ; mov r9, 0x123456789 ; mov r10d, 0xFFFFFFFF
    try h.add(0x1000, 2, regReg(.mov_reg32_reg32, .bits32, .bl_bx_ebx_rbx, .al_ax_eax_rax));
    try h.add(0x1002, 2, regReg(.mov_reg8_reg8, .bits8, .cl_cx_ecx_rcx, .al_ax_eax_rax));
    var high = regReg(.mov_reg8_reg8, .bits8, .cl_cx_ecx_rcx, .al_ax_eax_rax);
    high.dst_high8 = true;
    try h.add(0x1004, 2, high);
    try h.add(0x1006, 3, regReg(.mov_reg16_reg16, .bits16, .dl_dx_edx_rdx, .al_ax_eax_rax));
    try h.add(0x1009, 10, regImm(.mov_reg_imm, .bits64, .r9b_r9w_r9d_r9, 0x1_2345_6789));
    try h.add(0x1013, 6, regImm(.mov_reg_imm, .bits32, .r10b_r10w_r10d_r10, 0xFFFF_FFFF));
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 6), completed);
    try testing.expectEqual(@as(u64, 0x5566_7788), state.regs.rbx);
    try testing.expectEqual(@as(u64, 0xAAAA_AAAA_AAAA_8888), state.regs.rcx);
    try testing.expectEqual(@as(u64, 0x7788), state.regs.rdx);
    try testing.expectEqual(@as(u64, 0x1_2345_6789), state.regs.r9);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF), state.regs.r10);
    try testing.expectEqual(@as(u64, 0x1019), state.regs.rip);
    try testing.expect(h.block.register_only);
}

fn referenceBinary(op: BinaryOp, size: Size, a: u64, b: u64, rflags: *u32) u64 {
    const mask = maskFor(size);
    const r: u64 = switch (op) {
        .add => (a +% b) & mask,
        .sub, .cmp => (a -% b) & mask,
        .bit_and, .tst => (a & b) & mask,
        .bit_or => (a | b) & mask,
        .bit_xor => (a ^ b) & mask,
        .adc, .sbb => unreachable,
    };
    switch (op) {
        .add => x64_decoder.applyAdd(rflags, a, b, r, size),
        .sub, .cmp => x64_decoder.applySub(rflags, a, b, r, size),
        else => x64_decoder.applyLogic(rflags, r, size),
    }
    return r;
}
test "register arithmetic produces the interpreter's flags at every width" {
    var h = try TestHarness.init();
    defer h.deinit();
    var prng = std.Random.DefaultPrng.init(0x5EED_0001);
    const random = prng.random();
    const ops = [_]struct { op: Op, kind: BinaryOp, size: Size }{
        .{ .op = .add_reg64_reg64, .kind = .add, .size = .bits64 },
        .{ .op = .add_reg32_reg32, .kind = .add, .size = .bits32 },
        .{ .op = .add_reg16_reg16, .kind = .add, .size = .bits16 },
        .{ .op = .add_reg8_reg8, .kind = .add, .size = .bits8 },
        .{ .op = .sub_reg64_reg64, .kind = .sub, .size = .bits64 },
        .{ .op = .sub_reg32_reg32, .kind = .sub, .size = .bits32 },
        .{ .op = .sub_reg16_reg16, .kind = .sub, .size = .bits16 },
        .{ .op = .sub_reg8_reg8, .kind = .sub, .size = .bits8 },
        .{ .op = .and_reg64_reg64, .kind = .bit_and, .size = .bits64 },
        .{ .op = .or_reg32_reg32, .kind = .bit_or, .size = .bits32 },
        .{ .op = .xor_reg16_reg16, .kind = .bit_xor, .size = .bits16 },
        .{ .op = .cmp_reg64_reg64, .kind = .cmp, .size = .bits64 },
        .{ .op = .cmp_reg8_reg8, .kind = .cmp, .size = .bits8 },
        .{ .op = .test_reg32_reg32, .kind = .tst, .size = .bits32 },
    };
    for (ops) |entry| {
        for (0..64) |_| {
            var state = TestState{};
            const a = switch (random.uintLessThan(u8, 4)) {
                0 => random.int(u64),
                1 => maskFor(entry.size),
                2 => @as(u64, 1) << @intCast(bits(entry.size) - 1),
                else => random.int(u8),
            };
            const b = switch (random.uintLessThan(u8, 4)) {
                0 => random.int(u64),
                1 => maskFor(entry.size),
                2 => a,
                else => random.int(u8),
            };
            state.regs.rsi = a;
            state.regs.rdi = b;
            state.regs.rflags = (random.int(u32) & 0xFFF) | 0x2;
            var expected_flags = state.regs.rflags;
            const expected = referenceBinary(entry.kind, entry.size, a & maskFor(entry.size), b & maskFor(entry.size), &expected_flags);
            h.insns.clearRetainingCapacity();
            try h.add(0x2000, 3, regReg(entry.op, entry.size, .dh_si_esi_rsi, .bh_di_edi_rdi));
            _ = try h.run(&state);
            try testing.expectEqual(expected_flags, state.regs.rflags);
            const expected_reg: u64 = switch (entry.kind) {
                .cmp, .tst => a,
                else => switch (entry.size) {
                    .bits64, .bits32 => expected,
                    .bits16 => (a & ~@as(u64, 0xFFFF)) | expected,
                    .bits8 => (a & ~@as(u64, 0xFF)) | expected,
                },
            };
            try testing.expectEqual(expected_reg, state.regs.rsi);
            try testing.expectEqual(b, state.regs.rdi);
        }
    }
}

test "immediate forms sign-extend the way the interpreter does" {
    var h = try TestHarness.init();
    defer h.deinit();
    // add rax, -1 (imm8) ; and ecx, 0x80000000 (imm32) ; cmp rdx, -2 (imm32 sign-extended) ; test al, 0x80
    var state = TestState{};
    state.regs.rax = 5;
    state.regs.rcx = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rdx = 0xFFFF_FFFF_FFFF_FFFE;
    state.regs.rflags = 0x2;
    try h.add(0x3000, 4, regImm(.add_reg64_imm8, .bits64, .al_ax_eax_rax, 0xFF));
    try h.add(0x3004, 6, regImm(.and_reg32_imm32, .bits32, .cl_cx_ecx_rcx, 0x8000_0000));
    try h.add(0x300A, 7, regImm(.cmp_reg64_imm32, .bits64, .dl_dx_edx_rdx, 0xFFFF_FFFE));
    try h.add(0x3011, 2, regImm(.test_reg8_imm8, .bits8, .al_ax_eax_rax, 0x80));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 4), state.regs.rax);
    try testing.expectEqual(@as(u64, 0x8000_0000), state.regs.rcx);
    // cmp rdx, -2 with rdx == -2: ZF set. test al(4), 0x80: ZF set, SF clear, PF set (zero has even parity).
    try testing.expect(state.regs.rflags & RFL_ZF != 0);
    try testing.expect(state.regs.rflags & RFL_SF == 0);
    try testing.expect(state.regs.rflags & RFL_PF != 0);
    try testing.expect(state.regs.rflags & RFL_CF == 0);
}

test "locked exchange, compare-exchange and exchange-add are single host atomics with the interpreter's results" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    std.mem.writeInt(u64, state.memory[0x120..][0..8], 5, .little);

    // lock cmpxchg [rbx + 0x20], rcx with rax == [mem]: stored, ZF set.
    state.regs.rax = 5;
    state.regs.rcx = 0x77;
    var cas = baseDisp(.cmpxchg_mem64_reg64, .bits64, .cl_cx_ecx_rcx, 0x20);
    cas.lock = true;
    try h.add(0x1000, 5, cas);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 0x77), std.mem.readInt(u64, state.memory[0x120..][0..8], .little));
    try testing.expectEqual(@as(u64, 5), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_ZF != 0);

    // Again: now rax (5) != [mem] (0x77), so nothing is stored, rax takes
    // the old value, ZF is clear and CF is the borrow of 5 - 0x77.
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x77), std.mem.readInt(u64, state.memory[0x120..][0..8], .little));
    try testing.expectEqual(@as(u64, 0x77), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_ZF == 0);
    try testing.expect(state.regs.rflags & RFL_CF != 0);

    // xchg [rbx + 0x20], edx: a 32-bit swap, zero-extending edx.
    h.insns.clearRetainingCapacity();
    state.regs.rdx = 0xFFFF_FFFF_0000_0009;
    try h.add(0x1000, 3, baseDisp(.xchg_mem32_reg32, .bits32, .dl_dx_edx_rdx, 0x20));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x77), state.regs.rdx);
    try testing.expectEqual(@as(u32, 9), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));

    // lock xadd [rbx + 0x20], esi: memory gets the sum, esi the old value.
    h.insns.clearRetainingCapacity();
    state.regs.rsi = 3;
    var xadd = baseDisp(.xadd_mem32_reg32, .bits32, .dh_si_esi_rsi, 0x20);
    xadd.lock = true;
    try h.add(0x1000, 4, xadd);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 12), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));
    try testing.expectEqual(@as(u64, 9), state.regs.rsi);
    try testing.expect(state.regs.rflags & RFL_ZF == 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);

    // A misaligned address would fault as an LSE atomic: the interpreter
    // takes the whole instruction instead.
    h.insns.clearRetainingCapacity();
    state.regs.rbx = 0x101;
    try h.add(0x1000, 4, xadd);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.interprets);

    // Locked arithmetic/logic updates use the CAS loop at their decoded
    // width, including sub-word updates that must preserve neighbours.
    var native_add = baseDisp(.add_mem32_reg32, .bits32, .cl_cx_ecx_rcx, 0x20);
    native_add.lock = true;
    try testing.expect(isNative(native_add));
    var narrow_add = baseDisp(.add_mem16_reg16, .bits16, .cl_cx_ecx_rcx, 0x20);
    narrow_add.lock = true;
    try testing.expect(isNative(narrow_add));
    state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rcx = 3;
    std.mem.writeInt(u16, state.memory[0x120..][0..2], 0xFFFF, .little);
    state.memory[0x122] = 0xA5;
    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 4, narrow_add);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, state.memory[0x120..][0..2], .little));
    try testing.expectEqual(@as(u8, 0xA5), state.memory[0x122]);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "cmpxchg8b uses one native 64-bit CAS and changes only ZF" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    const address = 0x120;
    const original: u64 = 0x1122_3344_5566_7788;
    const replacement: u64 = 0xDDEE_FF00_99AA_BBCC;
    std.mem.writeInt(u64, state.memory[address..][0..8], original, .little);
    state.regs.rax = @truncate(original);
    state.regs.rdx = original >> 32;
    state.regs.rbx = 0x99AA_BBCC;
    state.regs.rcx = 0xDDEE_FF00;
    state.regs.rflags = RFL_CF | RFL_SF | 2;

    const cmpxchg: DecodedInsn = .{ .op = .cmpxchg8b_mem, .size = .bits32, .addr = address, .lock = true };
    try testing.expect(isNative(cmpxchg));
    try h.add(0x1000, 4, cmpxchg);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(replacement, std.mem.readInt(u64, state.memory[address..][0..8], .little));
    try testing.expectEqual(@as(u64, @truncate(original)), state.regs.rax);
    try testing.expectEqual(@as(u64, original >> 32), state.regs.rdx);
    try testing.expect(state.regs.rflags & RFL_ZF != 0);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_SF != 0);

    // A mismatch leaves memory alone and returns the observed low/high pair.
    h.insns.clearRetainingCapacity();
    state.regs.rax = 0;
    state.regs.rdx = 0;
    state.regs.rflags = RFL_ZF | RFL_CF | 2;
    try h.add(0x1000, 4, cmpxchg);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(replacement, std.mem.readInt(u64, state.memory[address..][0..8], .little));
    try testing.expectEqual(@as(u32, @truncate(replacement)), @as(u32, @truncate(state.regs.rax)));
    try testing.expectEqual(@as(u32, replacement >> 32), @as(u32, @truncate(state.regs.rdx)));
    try testing.expect(state.regs.rflags & RFL_ZF == 0);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
}

test "cmpxchg16b uses one native paired CAS and changes only ZF" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    const address = 0x120;
    const original_low: u64 = 0x1122_3344_5566_7788;
    const original_high: u64 = 0x99AA_BBCC_DDEE_FF00;
    const replacement_low: u64 = 0x2233_4455_6677_8899;
    const replacement_high: u64 = 0xAABB_CCDD_EEFF_0011;
    std.mem.writeInt(u64, state.memory[address..][0..8], original_low, .little);
    std.mem.writeInt(u64, state.memory[address + 8 ..][0..8], original_high, .little);
    state.regs.rax = original_low;
    state.regs.rdx = original_high;
    state.regs.rbx = replacement_low;
    state.regs.rcx = replacement_high;
    state.regs.rflags = RFL_CF | RFL_OF | 2;

    const cmpxchg: DecodedInsn = .{ .op = .cmpxchg16b_mem, .size = .bits64, .addr = address, .lock = true };
    try testing.expect(isNative(cmpxchg));
    try h.add(0x1000, 5, cmpxchg);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(replacement_low, std.mem.readInt(u64, state.memory[address..][0..8], .little));
    try testing.expectEqual(replacement_high, std.mem.readInt(u64, state.memory[address + 8 ..][0..8], .little));
    try testing.expectEqual(original_low, state.regs.rax);
    try testing.expectEqual(original_high, state.regs.rdx);
    try testing.expect(state.regs.rflags & RFL_ZF != 0);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);

    // A mismatch leaves memory unchanged and returns its observed 128-bit
    // value in RDX:RAX.
    h.insns.clearRetainingCapacity();
    state.regs.rax = 0;
    state.regs.rdx = 0;
    state.regs.rflags = RFL_ZF | RFL_CF | 2;
    try h.add(0x1000, 5, cmpxchg);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(replacement_low, std.mem.readInt(u64, state.memory[address..][0..8], .little));
    try testing.expectEqual(replacement_high, std.mem.readInt(u64, state.memory[address + 8 ..][0..8], .little));
    try testing.expectEqual(replacement_low, state.regs.rax);
    try testing.expectEqual(replacement_high, state.regs.rdx);
    try testing.expect(state.regs.rflags & RFL_ZF == 0);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
}

test "unlocked compare-exchange and exchange-add avoid unnecessary host atomics" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rax = 5;
    state.regs.rcx = 9;
    std.mem.writeInt(u64, state.memory[0x120..][0..8], 5, .little);

    const cas = baseDisp(.cmpxchg_mem64_reg64, .bits64, .cl_cx_ecx_rcx, 0x20);
    try h.add(0x1000, 4, cas);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 9), std.mem.readInt(u64, state.memory[0x120..][0..8], .little));
    try testing.expectEqual(@as(u64, 5), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_ZF != 0);

    h.insns.clearRetainingCapacity();
    state.regs.rsi = 3;
    const xadd = baseDisp(.xadd_mem32_reg32, .bits32, .dh_si_esi_rsi, 0x20);
    try h.add(0x1000, 3, xadd);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u32, 12), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));
    try testing.expectEqual(@as(u64, 9), state.regs.rsi);
}

test "locked byte and word operations do not widen into adjacent guest bytes" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rcx = 0x5678;
    std.mem.writeInt(u16, state.memory[0x120..][0..2], 0x1234, .little);
    state.memory[0x122] = 0xA5;
    var exchange = baseDisp(.xchg_mem32_reg32, .bits16, .cl_cx_ecx_rcx, 0x20);
    exchange.lock = true;
    try testing.expect(isNative(exchange));
    try h.add(0x1000, 3, exchange);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u16, 0x5678), std.mem.readInt(u16, state.memory[0x120..][0..2], .little));
    try testing.expectEqual(@as(u64, 0x1234), state.regs.rcx);
    try testing.expectEqual(@as(u8, 0xA5), state.memory[0x122]);
    try testing.expectEqual(@as(u32, 0), state.interprets);

    h.insns.clearRetainingCapacity();
    state.memory[0x130] = 5;
    state.memory[0x131] = 0xFE;
    state.memory[0x132] = 0xA5;
    state.regs.rax = 5;
    state.regs.rcx = 9;
    var compare_exchange = baseDisp(.cmpxchg_mem8_reg8, .bits8, .cl_cx_ecx_rcx, 0x30);
    compare_exchange.lock = true;
    try testing.expect(isNative(compare_exchange));
    try h.add(0x1000, 4, compare_exchange);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u8, 9), state.memory[0x130]);
    try testing.expectEqual(@as(u8, 0xFE), state.memory[0x131]);
    try testing.expect(state.regs.rflags & RFL_ZF != 0);

    h.insns.clearRetainingCapacity();
    state.regs.rdx = 4;
    var exchange_add = baseDisp(.xadd_mem8_reg8, .bits8, .dl_dx_edx_rdx, 0x31);
    exchange_add.lock = true;
    try testing.expect(isNative(exchange_add));
    try h.add(0x1000, 4, exchange_add);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u8, 2), state.memory[0x131]);
    try testing.expectEqual(@as(u8, 0xA5), state.memory[0x132]);
    try testing.expectEqual(@as(u64, 0xFE), state.regs.rdx);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "locked bit set reset and complement commit through compare-and-swap" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    std.mem.writeInt(u32, state.memory[0x120..][0..4], 0b10, .little);

    var bts = baseDisp(.bts_mem_imm, .bits32, .al_ax_eax_rax, 0x20);
    bts.imm = 5;
    bts.lock = true;
    try h.add(0x1000, 4, bts);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0b10_0010), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));
    try testing.expect(state.regs.rflags & RFL_CF == 0);

    h.insns.clearRetainingCapacity();
    var btr = bts;
    btr.op = .btr_mem_imm;
    try h.add(0x1000, 4, btr);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0b10), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));
    try testing.expect(state.regs.rflags & RFL_CF != 0);

    h.insns.clearRetainingCapacity();
    var btc = bts;
    btc.op = .btc_mem_imm;
    btc.imm = 1;
    try h.add(0x1000, 4, btc);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "register-indexed memory bit operations address signed adjacent elements" {
    var h = try TestHarness.init();
    defer h.deinit();

    inline for (.{ Size.bits16, Size.bits32, Size.bits64 }) |size| {
        const width = bits(size);
        const byte_count: usize = @intCast(width / 8);
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rflags |= RFL_CF;
        const base: usize = 0x200 + ((8 - (@intFromPtr(state.memory[0x200..].ptr) & 7)) & 7);
        state.regs.rbx = base;

        const selected = base + byte_count;
        @memset(state.memory[selected..][0..byte_count], 0);
        state.regs.rcx = width + 3;
        const set = DecodedInsn{
            .op = .bts_mem_reg,
            .size = size,
            .src_reg = .cl_cx_ecx_rcx,
            .sib_has_base = true,
            .sib_base_reg = .bl_bx_ebx_rbx,
        };
        try testing.expect(isNative(set));
        try h.add(0x1000, 4, set);
        _ = try h.run(&state);
        try testing.expectEqual(@as(u8, 0x08), state.memory[selected]);
        try testing.expect(state.regs.rflags & RFL_CF == 0);
        try testing.expectEqual(@as(u32, 0), state.interprets);
        try testing.expectEqual(@as(u32, 0), state.reads + state.writes);

        h.insns.clearRetainingCapacity();
        state.regs.rflags &= ~RFL_CF;
        const preceding = base - byte_count;
        @memset(state.memory[preceding..][0..byte_count], 0);
        state.memory[preceding + byte_count - 1] = 0x80;
        state.regs.rcx = std.math.maxInt(u64);
        var reset = set;
        reset.op = .btr_mem_reg;
        reset.lock = true;
        try testing.expect(isNative(reset));
        try h.add(0x2000, 4, reset);
        _ = try h.run(&state);
        try testing.expectEqual(@as(u8, 0), state.memory[preceding + byte_count - 1]);
        try testing.expect(state.regs.rflags & RFL_CF != 0);
        try testing.expectEqual(@as(u32, 0), state.interprets);
        try testing.expectEqual(@as(u32, 0), state.reads + state.writes);
    }
}

test "locked arithmetic and logic updates use an atomic CAS loop" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rcx = 0x20;
    std.mem.writeInt(u32, state.memory[0x120..][0..4], 0xFFFF_FFF0, .little);

    // lock add dword [rbx + 0x20], ecx: the result wraps and sets CF.
    var add = baseDisp(.add_mem32_reg32, .bits32, .cl_cx_ecx_rcx, 0x20);
    add.lock = true;
    try h.add(0x1000, 4, add);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0x10), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);

    // Group-1 imm8 is sign-extended to the destination width: subtracting
    // -1 adds one, then AND/OR/XOR exercise the other CAS computations.
    h.insns.clearRetainingCapacity();
    var sub = baseDisp(.sub_mem32_imm8, .bits32, .al_ax_eax_rax, 0x20);
    sub.imm = 0xFF;
    sub.lock = true;
    try h.add(0x1000, 4, sub);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0x11), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));

    h.insns.clearRetainingCapacity();
    state.regs.rcx = 0x07;
    var and_update = baseDisp(.and_mem32_reg32, .bits32, .cl_cx_ecx_rcx, 0x20);
    and_update.lock = true;
    try h.add(0x1000, 4, and_update);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0x01), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));

    h.insns.clearRetainingCapacity();
    var or_update = baseDisp(.or_mem32_imm8, .bits32, .al_ax_eax_rax, 0x20);
    or_update.imm = 0x10;
    or_update.lock = true;
    try h.add(0x1000, 4, or_update);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0x11), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));

    h.insns.clearRetainingCapacity();
    var xor_update = baseDisp(.xor_mem32_imm32, .bits32, .al_ax_eax_rax, 0x20);
    xor_update.imm = 0xFF;
    xor_update.lock = true;
    try h.add(0x1000, 6, xor_update);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0xEE), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));
    try testing.expectEqual(@as(u32, 0), state.interprets);

    // The 64-bit immediate forms retain x86's sign-extension semantics.
    h.insns.clearRetainingCapacity();
    std.mem.writeInt(u64, state.memory[0x128..][0..8], 0x100, .little);
    var sub64 = baseDisp(.sub_mem64_imm8, .bits64, .al_ax_eax_rax, 0x28);
    sub64.imm = 1;
    sub64.lock = true;
    try h.add(0x1000, 5, sub64);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFF), std.mem.readInt(u64, state.memory[0x128..][0..8], .little));
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "locked adc and sbb use a stable carry input across width-matched CAS updates" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;

    // LOCK ADC byte [rbx+0x20], cl: 0x7f + 0 + CF wraps the sign bit and
    // updates AF/OF/SF while leaving carry clear.
    state.memory[0x120] = 0x7f;
    state.regs.rcx = 0;
    state.regs.rflags = RFL_CF | 2;
    var adc8 = baseDisp(.adc_mem8_reg8, .bits8, .cl_cx_ecx_rcx, 0x20);
    adc8.lock = true;
    try testing.expect(isNative(adc8));
    try h.add(0x1000, 4, adc8);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u8, 0x80), state.memory[0x120]);
    try testing.expect(state.regs.rflags & RFL_CF == 0);
    try testing.expect(state.regs.rflags & RFL_AF != 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);
    try testing.expect(state.regs.rflags & RFL_SF != 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);

    // LOCK SBB word [rbx+0x20], 1 with CF set computes 0x8000-1-1. The
    // input CF must survive the update until the CAS commits.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rflags = RFL_CF | 2;
    std.mem.writeInt(u16, state.memory[0x120..][0..2], 0x8000, .little);
    var sbb16 = baseDisp(.sbb_mem16_imm8, .bits16, .al_ax_eax_rax, 0x20);
    sbb16.imm = 1;
    sbb16.lock = true;
    try testing.expect(isNative(sbb16));
    try h.add(0x1000, 4, sbb16);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u16, 0x7ffe), std.mem.readInt(u16, state.memory[0x120..][0..2], .little));
    try testing.expect(state.regs.rflags & RFL_CF == 0);
    try testing.expect(state.regs.rflags & RFL_AF != 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);

    // The 32-bit edge covers carry-out of the operand width. LOCK ADC with
    // both the operand and incoming carry set wraps UINT32_MAX to zero.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rflags = RFL_CF | 2;
    std.mem.writeInt(u32, state.memory[0x120..][0..4], 0xffff_ffff, .little);
    var adc32 = baseDisp(.adc_mem32_imm8, .bits32, .al_ax_eax_rax, 0x20);
    adc32.imm = 0;
    adc32.lock = true;
    try testing.expect(isNative(adc32));
    try h.add(0x1000, 4, adc32);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_ZF != 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);

    // For a 64-bit borrow, zero minus zero minus one wraps and sets CF/SF.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rflags = RFL_CF | 2;
    state.regs.rcx = 0;
    var sbb64 = baseDisp(.sbb_mem64_reg64, .bits64, .cl_cx_ecx_rcx, 0x20);
    sbb64.lock = true;
    try testing.expect(isNative(sbb64));
    try h.add(0x1000, 4, sbb64);
    _ = try h.run(&state);
    try testing.expectEqual(std.math.maxInt(u64), std.mem.readInt(u64, state.memory[0x120..][0..8], .little));
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_SF != 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "locked increment decrement negate and not use width-matched host atomics" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;

    // INC byte: OF and AF are recomputed, while CF survives the RMW.
    state.memory[0x120] = 0x7F;
    state.memory[0x121] = 0xA5;
    state.regs.rflags = RFL_CF | 2;
    var inc = baseDisp(.inc_mem8, .bits8, .al_ax_eax_rax, 0x20);
    inc.lock = true;
    try testing.expect(isNative(inc));
    try h.add(0x1000, 4, inc);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u8, 0x80), state.memory[0x120]);
    try testing.expectEqual(@as(u8, 0xA5), state.memory[0x121]);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);
    try testing.expect(state.regs.rflags & RFL_AF != 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);

    // DEC word: only the two addressed bytes change and CF remains clear.
    h.insns.clearRetainingCapacity();
    std.mem.writeInt(u16, state.memory[0x122..][0..2], 0x8000, .little);
    state.memory[0x124] = 0x5A;
    state.regs.rflags = 2;
    var dec = baseDisp(.dec_mem16, .bits16, .al_ax_eax_rax, 0x22);
    dec.lock = true;
    try testing.expect(isNative(dec));
    try h.add(0x1000, 4, dec);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u16, 0x7FFF), std.mem.readInt(u16, state.memory[0x122..][0..2], .little));
    try testing.expectEqual(@as(u8, 0x5A), state.memory[0x124]);
    try testing.expect(state.regs.rflags & RFL_CF == 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);

    // NEG dword at the signed minimum sets both CF and OF.
    h.insns.clearRetainingCapacity();
    std.mem.writeInt(u32, state.memory[0x128..][0..4], 0x8000_0000, .little);
    state.memory[0x12C] = 0xC3;
    var neg = baseDisp(.neg_mem32, .bits32, .al_ax_eax_rax, 0x28);
    neg.lock = true;
    try testing.expect(isNative(neg));
    try h.add(0x1000, 4, neg);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0x8000_0000), std.mem.readInt(u32, state.memory[0x128..][0..4], .little));
    try testing.expectEqual(@as(u8, 0xC3), state.memory[0x12C]);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);

    // NOT qword preserves the complete arithmetic flag word.
    h.insns.clearRetainingCapacity();
    const initial_flags = RFL_CF | RFL_ZF | RFL_SF | 2;
    const initial_value: u64 = 0x1122_3344_5566_7788;
    std.mem.writeInt(u64, state.memory[0x130..][0..8], initial_value, .little);
    var bitwise_not = baseDisp(.not_mem64, .bits64, .al_ax_eax_rax, 0x30);
    bitwise_not.lock = true;
    try testing.expect(isNative(bitwise_not));
    state.regs.rflags = initial_flags;
    try h.add(0x1000, 4, bitwise_not);
    _ = try h.run(&state);
    try testing.expectEqual(~initial_value, std.mem.readInt(u64, state.memory[0x130..][0..8], .little));
    try testing.expectEqual(initial_flags, state.regs.rflags);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "Xenia XObject release branches only when its locked reference count reaches zero" {
    var h = try TestHarness.init();
    defer h.deinit();
    // XObject::Release is `lock dec dword ptr [rcx+0x18]; jne +7`.
    // A wrong ZF here deletes a still referenced object, whose next virtual
    // destructor call reaches Win32Handle<Mutant>::D0 (an intentional UD2).
    const dec = x64_decoder.decodeLegacyInstruction(&.{ 0xf0, 0xff, 0x49, 0x18 }, .long64);
    try testing.expect(dec.lock);
    var jne: DecodedInsn = .{ .op = .jcc_rel8, .cond = .ne, .addr = 7 };
    jne.rip_relative = true;
    try h.add(0x6000, 4, dec);
    try h.add(0x6004, 2, jne);
    for ([_]struct { before: u32, after: u32, rip: u64 }{
        .{ .before = 3, .after = 2, .rip = 0x600d },
        .{ .before = 2, .after = 1, .rip = 0x600d },
        .{ .before = 1, .after = 0, .rip = 0x6006 },
    }) |case| {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rcx = 0x100;
        std.mem.writeInt(u32, state.memory[0x118..][0..4], case.before, .little);
        try testing.expectEqual(@as(u32, 2), try h.run(&state));
        try testing.expectEqual(case.after, std.mem.readInt(u32, state.memory[0x118..][0..4], .little));
        try testing.expectEqual(case.rip, state.regs.rip);
        try testing.expectEqual(case.after == 0, state.regs.rflags & RFL_ZF != 0);
        try testing.expectEqual(@as(u32, 0), state.interprets);
    }
}

test "bit tests on memory with an immediate, and narrow immediate shifts, are native" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    std.mem.writeInt(u32, state.memory[0x120..][0..4], 0x8000_0005, .little);
    state.regs.rbx = 0x100;
    state.regs.rflags = 0x2;
    // btr dword [rbx + 0x20], 31 ; bts dword [rbx + 0x20], 1
    var btr = baseDisp(.btr_mem_imm, .bits32, .al_ax_eax_rax, 0x20);
    btr.imm = 31;
    try h.add(0x1000, 5, btr);
    var bts = baseDisp(.bts_mem_imm, .bits32, .al_ax_eax_rax, 0x20);
    bts.imm = 1;
    try h.add(0x1005, 5, bts);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u32, 0x0000_0007), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));
    // CF is the bit `bts` found: bit 1 of 0x5 was clear.
    try testing.expect(state.regs.rflags & RFL_CF == 0);

    // bt only probes: CF from bit 2, memory untouched.
    h.insns.clearRetainingCapacity();
    var bt = baseDisp(.bt_mem_imm, .bits32, .al_ax_eax_rax, 0x20);
    bt.imm = 2;
    try h.add(0x1000, 5, bt);
    _ = try h.run(&state);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expectEqual(@as(u32, 0x0000_0007), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));

    // shr al, 3 leaves the rest of rax alone; CF is bit 2 of 0xF4.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x1234_56F4;
    try h.add(0x2000, 3, regImm(.shr_reg_imm, .bits8, .al_ax_eax_rax, 3));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 0x1234_561E), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_CF != 0);

    // sar bx, 4 brings the 16-bit sign down and sets SF; bit 3 of 0x8018 is
    // CF.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 0xAAAA_8018;
    try h.add(0x2000, 4, regImm(.sar_reg_imm, .bits16, .bl_bx_ebx_rbx, 4));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 0xAAAA_F801), state.regs.rbx);
    try testing.expect(state.regs.rflags & RFL_SF != 0);
    try testing.expect(state.regs.rflags & RFL_CF != 0);

    // A count past the operand stays with the interpreter.
    try testing.expect(!isNative(regImm(.shl_reg_imm, .bits8, .al_ax_eax_rax, 9)));

    // shr ah, 4: the high byte, with AL left exactly as it was.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x1234_F0A5;
    var high = regImm(.shr_reg_imm, .bits8, .al_ax_eax_rax, 4);
    high.dst_high8 = true;
    try h.add(0x2000, 3, high);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 0x1234_0FA5), state.regs.rax);

    // rol ax, 8 is a 16-bit byte swap; CF is the low bit of the result.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x1111_2233;
    try h.add(0x2000, 4, regImm(.rol_reg_imm, .bits16, .al_ax_eax_rax, 8));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 0x1111_3322), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_CF == 0);

    // ror bl, 1 from 1: 0x80, CF = the new msb, OF = CF ^ bit 6.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 0xFF01;
    try h.add(0x2000, 2, regImm(.ror_reg_imm, .bits8, .bl_bx_ebx_rbx, 1));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFF80), state.regs.rbx);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);
}

test "inc, dec, neg, not, shifts and imul follow the interpreter's flag rules" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    // inc eax from 0x7FFFFFFF: OF set, CF preserved (set beforehand).
    state.regs.rax = 0x7FFF_FFFF;
    state.regs.rflags = 0x2 | RFL_CF;
    try h.add(0x4000, 2, .{ .op = .inc_reg32, .size = .bits32, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x8000_0000), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_OF != 0);
    try testing.expect(state.regs.rflags & RFL_SF != 0);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_AF != 0);

    // dec rbx from 0: SF set, AF set (low nibble was zero), ZF clear.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 0;
    state.regs.rflags = 0x2;
    try h.add(0x4000, 3, .{ .op = .dec_reg64, .size = .bits64, .dst_reg = .bl_bx_ebx_rbx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_FFFF_FFFF), state.regs.rbx);
    try testing.expect(state.regs.rflags & RFL_SF != 0);
    try testing.expect(state.regs.rflags & RFL_AF != 0);
    try testing.expect(state.regs.rflags & RFL_ZF == 0);

    // neg ecx (5): result -5, CF set (nonzero), matches applySub(0, 5, r).
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rcx = 5;
    state.regs.rflags = 0x2;
    try h.add(0x4000, 2, .{ .op = .neg_reg32, .size = .bits32, .dst_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    _ = try h.run(&state);
    var reference: u32 = 0x2;
    _ = referenceBinary(.sub, .bits32, 0, 5, &reference);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFB), state.regs.rcx);
    try testing.expectEqual(reference, state.regs.rflags);

    // not rdx leaves flags alone.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rdx = 0x00FF;
    state.regs.rflags = 0x8D7;
    try h.add(0x4000, 3, .{ .op = .not_reg64, .size = .bits64, .dst_reg = .dl_dx_edx_rdx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_FFFF_FF00), state.regs.rdx);
    try testing.expectEqual(@as(u32, 0x8D7), state.regs.rflags);

    // shl rsi, 1 with the top bit set: CF set, OF = msb(result) != CF, PF untouched.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rsi = 0xC000_0000_0000_0001;
    state.regs.rflags = 0x2 | RFL_PF;
    try h.add(0x4000, 4, regImm(.shl_reg_imm, .bits64, .dh_si_esi_rsi, 1));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x8000_0000_0000_0002), state.regs.rsi);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_OF == 0);
    try testing.expect(state.regs.rflags & RFL_SF != 0);
    try testing.expect(state.regs.rflags & RFL_PF != 0);

    // shr edi, 4 on 0x1F: result 1, CF = bit 3 = 1, ZF clear; OF untouched (count != 1).
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rdi = 0xFFFF_FFFF_0000_001F;
    state.regs.rflags = 0x2 | RFL_OF;
    try h.add(0x4000, 3, regImm(.shr_reg_imm, .bits32, .bh_di_edi_rdi, 4));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 1), state.regs.rdi);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);
    try testing.expect(state.regs.rflags & RFL_ZF == 0);

    // sar r8, 63 on a negative value: all ones, CF = bit 62.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.r8 = 0x8000_0000_0000_0000;
    state.regs.rflags = 0x2;
    try h.add(0x4000, 4, regImm(.sar_reg_imm, .bits64, .r8b_r8w_r8d_r8, 63));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_FFFF_FFFF), state.regs.r8);
    try testing.expect(state.regs.rflags & RFL_CF == 0);
    try testing.expect(state.regs.rflags & RFL_SF != 0);

    // imul r9d, r10d overflowing: CF and OF set, low 32 bits kept.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.r9 = 0x7FFF_FFFF;
    state.regs.r10 = 2;
    state.regs.rflags = 0x2;
    try h.add(0x4000, 4, regReg(.imul_reg32_reg32, .bits32, .r9b_r9w_r9d_r9, .r10b_r10w_r10d_r10));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFE), state.regs.r9);
    try testing.expect(state.regs.rflags & RFL_CF != 0 and state.regs.rflags & RFL_OF != 0);

    // imul r11, r12, 3 fitting: flags clear.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.r12 = 7;
    state.regs.rflags = 0x2 | RFL_CF | RFL_OF;
    var imm_form = regReg(.imul_reg64_reg64_imm8, .bits64, .r11b_r11w_r11d_r11, .r12b_r12w_r12d_r12);
    imm_form.imm = 3;
    try h.add(0x4000, 4, imm_form);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 21), state.regs.r11);
    try testing.expect(state.regs.rflags & (RFL_CF | RFL_OF) == 0);
}

test "conditions, conditional moves and setcc evaluate every x86 condition" {
    var h = try TestHarness.init();
    defer h.deinit();
    const flag_values = [_]u32{ 0x2, RFL_CF, RFL_ZF, RFL_SF, RFL_OF, RFL_PF, RFL_SF | RFL_OF, RFL_ZF | RFL_CF, RFL_ZF | RFL_SF, 0x8D5 };
    for (flag_values) |flags| {
        for (0..16) |cond_index| {
            const cond: Cond = @enumFromInt(cond_index);
            var state = TestState{};
            state.regs.rflags = flags;
            state.regs.rax = 0x1111_1111_1111_1111;
            state.regs.rbx = 0x2222_2222_2222_2222;
            h.insns.clearRetainingCapacity();
            var setcc: DecodedInsn = .{ .op = .setcc_reg8, .size = .bits8, .dst_reg = .cl_cx_ecx_rcx, .cond = cond, .is_reg_form = true };
            setcc.dst_high8 = false;
            try h.add(0x5000, 3, setcc);
            var cmov = regReg(.cmovcc_reg_reg, .bits32, .al_ax_eax_rax, .bl_bx_ebx_rbx);
            cmov.cond = cond;
            try h.add(0x5003, 3, cmov);
            _ = try h.run(&state);
            const expected = x64_decoder.evalCond(flags, cond);
            try testing.expectEqual(@as(u64, @intFromBool(expected)), state.regs.rcx & 0xFF);
            // A 32-bit cmov zero-extends whether or not it moves.
            try testing.expectEqual(if (expected) @as(u64, 0x2222_2222) else @as(u64, 0x1111_1111), state.regs.rax);
        }
    }
}

test "a condition keeps only the flags it reads live" {
    try testing.expectEqual(F_ZF, conditionReads(.e));
    try testing.expectEqual(F_ZF, conditionReads(.ne));
    try testing.expectEqual(F_CF, conditionReads(.b));
    try testing.expectEqual(F_CF | F_ZF, conditionReads(.be));
    try testing.expectEqual(F_SF | F_OF, conditionReads(.l));
    try testing.expectEqual(F_SF | F_OF | F_ZF, conditionReads(.le));
    try testing.expectEqual(F_PF, conditionReads(.p));
    try testing.expectEqual(F_OF, conditionReads(.o));
    // The flags-register bits a liveness mask keeps.
    try testing.expectEqual(RFL_ZF, liveFlagBits(F_ZF));
    try testing.expectEqual(RFL_CF | RFL_OF, liveFlagBits(F_CF | F_OF));
    try testing.expectEqual(RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF, liveFlagBits(F_ALL));
}

test "flag liveness narrows a compare to the conditions that consume it" {
    // The shape Xenia's PowerPC backend emits for a condition-register
    // update: one compare, a run of `setcc` reading it, and the next compare
    // killing what is left. Only the flags those conditions read have to be
    // computed, so the parity fold, the auxiliary carry and the carry are
    // skipped on the hottest instruction in the translated stream.
    var insns: [3]Insn = undefined;
    var cmp = regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx);
    cmp.len = 3;
    insns[0] = .{ .rip = 0x1000, .len = 3, .decoded = cmp, .segment = .ds };
    var set: DecodedInsn = .{ .op = .setcc_reg8, .size = .bits8, .dst_reg = .cl_cx_ecx_rcx, .cond = .ne, .is_reg_form = true };
    set.len = 3;
    insns[1] = .{ .rip = 0x1003, .len = 3, .decoded = set, .segment = .ds };
    var cmp2 = regReg(.cmp_reg64_reg64, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx);
    cmp2.len = 3;
    insns[2] = .{ .rip = 0x1006, .len = 3, .decoded = cmp2, .segment = .ds };

    var wants: [3]bool = undefined;
    var live: [3]u8 = undefined;
    _ = flagLiveness(&insns, &wants, &live);
    try testing.expect(wants[0]);
    try testing.expectEqual(F_ZF, live[0]);
    try testing.expectEqual(@as(u8, 0), live[1]);
    // The last flag writer in the block computes everything: the next block
    // or the interpreter may read any flag.
    try testing.expectEqual(F_ALL, live[2]);
}

test "a branch that ends a block keeps every flag live across it" {
    // `jcc` reads its condition but kills nothing, so flags stay live past
    // it, and the block ends there with all of them live-out. This is the
    // honest limit of per-flag liveness: a compare feeding only a terminating
    // branch still materialises all six. Lifting it needs lazy flags, not a
    // better liveness pass.
    var insns: [2]Insn = undefined;
    var cmp = regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx);
    cmp.len = 3;
    insns[0] = .{ .rip = 0x1000, .len = 3, .decoded = cmp, .segment = .ds };
    var jcc: DecodedInsn = .{ .op = .jcc_rel8, .cond = .ne, .addr = 0x10 };
    jcc.len = 2;
    insns[1] = .{ .rip = 0x1003, .len = 2, .decoded = jcc, .segment = .ds };

    var wants: [2]bool = undefined;
    var live: [2]u8 = undefined;
    _ = flagLiveness(&insns, &wants, &live);
    try testing.expect(wants[0]);
    try testing.expectEqual(F_ALL, live[0]);
    try testing.expectEqual(F_ALL, live[1]);
}

test "flag liveness keeps a flag its writer does not kill" {
    // `and` leaves the auxiliary carry undefined, so it does not kill it and
    // the earlier `add` must still compute it.
    var insns: [2]Insn = undefined;
    var add_insn = regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx);
    add_insn.len = 3;
    insns[0] = .{ .rip = 0x2000, .len = 3, .decoded = add_insn, .segment = .ds };
    var and_insn = regReg(.and_reg64_reg64, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx);
    and_insn.len = 3;
    insns[1] = .{ .rip = 0x2003, .len = 3, .decoded = and_insn, .segment = .ds };

    var wants: [2]bool = undefined;
    var live: [2]u8 = undefined;
    _ = flagLiveness(&insns, &wants, &live);
    try testing.expectEqual(F_AF, live[0] & F_AF);
    try testing.expectEqual(F_ALL, live[1]);
}

test "setcc to memory and the fences are translated, not interpreted" {
    var h = try TestHarness.init();
    defer h.deinit();
    // `setcc [mem]` was 78% of every interpreter fallback the 2026-09-19
    // Halo 3 run made - 5.8 billion of 7.4 billion calls - because Xenia's
    // PowerPC backend writes each condition-register bit with one.
    const flag_values = [_]u32{ 0x2, RFL_CF, RFL_ZF, RFL_SF, RFL_OF, RFL_PF, RFL_SF | RFL_OF, RFL_ZF | RFL_CF, 0x8D5 };
    for (flag_values) |flags| {
        for (0..16) |cond_index| {
            const cond: Cond = @enumFromInt(cond_index);
            var state = TestState{};
            state.regs.rflags = flags;
            state.regs.rbx = 0x100;
            state.memory[0x140] = 0xA5;
            h.insns.clearRetainingCapacity();
            var set = baseDisp(.setcc_mem8, .bits8, .al_ax_eax_rax, 0x40);
            set.cond = cond;
            try h.add(0x7000, 7, set);
            try h.add(0x7007, 3, DecodedInsn{ .op = .mfence });
            const completed = try h.run(&state);
            try testing.expectEqual(@as(u32, 2), completed);
            const expected = x64_decoder.evalCond(flags, cond);
            try testing.expectEqual(@as(u8, @intFromBool(expected)), state.memory[0x140]);
            // One byte written, through the store helper, and nothing handed
            // to the interpreter.
            try testing.expectEqual(@as(u32, 1), state.writes);
            try testing.expectEqual(@as(u32, 0), state.interprets);
            try testing.expectEqual(@as(u64, 0x700A), state.regs.rip);
            // The condition is read, so the flags must survive the store.
            try testing.expectEqual(flags, state.regs.rflags);
        }
    }
}

test "MFENCE LFENCE and SFENCE each use a native block template" {
    var h = try TestHarness.init();
    defer h.deinit();

    for ([_]Op{ .mfence, .lfence, .sfence }) |op| {
        var state = TestState{};
        h.insns.clearRetainingCapacity();
        try h.add(0x7100, 3, .{ .op = op });
        try testing.expectEqual(@as(u32, 1), try h.run(&state));
        try testing.expectEqual(@as(u32, 0), state.interprets);
        try testing.expectEqual(@as(u32, 1), h.block.native_count);
        try testing.expectEqual(@as(u32, 0), h.block.fallback_count);
    }
}

test "setcc to memory writes exactly one byte and leaves its neighbours" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.regs.rflags = RFL_ZF;
    state.regs.rbx = 0x200;
    state.memory[0x20F] = 0x77;
    state.memory[0x210] = 0x55;
    state.memory[0x211] = 0x99;
    var set = baseDisp(.setcc_mem8, .bits8, .al_ax_eax_rax, 0x10);
    set.cond = .e;
    try h.add(0x8000, 7, set);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u8, 1), state.memory[0x210]);
    try testing.expectEqual(@as(u8, 0x77), state.memory[0x20F]);
    try testing.expectEqual(@as(u8, 0x99), state.memory[0x211]);
    // A register-form setcc must not reach the memory template.
    var reg_form: DecodedInsn = .{ .op = .setcc_mem8, .size = .bits8, .dst_reg = .cl_cx_ecx_rcx, .cond = .e, .is_reg_form = true };
    reg_form.len = 3;
    try testing.expect(!isNative(reg_form));
}

test "relative branches leave the right rip and count on both paths" {
    var h = try TestHarness.init();
    defer h.deinit();
    // cmp rax, rbx ; jne +0x20 (rel8 in `addr`)
    var jcc: DecodedInsn = .{ .op = .jcc_rel8, .cond = .ne, .addr = 0x20 };
    jcc.rip_relative = true;
    for ([_]bool{ true, false }) |equal| {
        var state = TestState{};
        state.regs.rax = 10;
        state.regs.rbx = if (equal) 10 else 11;
        h.insns.clearRetainingCapacity();
        try h.add(0x6000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        try h.add(0x6003, 2, jcc);
        const completed = try h.run(&state);
        try testing.expectEqual(@as(u32, 2), completed);
        try testing.expectEqual(if (equal) @as(u64, 0x6005) else @as(u64, 0x6025), state.regs.rip);
    }
    // jmp -0x10 (rel8 in `imm`), and a negative displacement wraps correctly.
    h.insns.clearRetainingCapacity();
    var state = TestState{};
    try h.add(0x7000, 2, .{ .op = .jmp_rel8, .imm = @bitCast(@as(i64, -0x10)) });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x6FF2), state.regs.rip);
    // A block that ends without a branch stores the fall-through rip.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    try h.add(0x8000, 1, .{ .op = .nop, .len = 1 });
    try h.add(0x8001, 3, regReg(.mov_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try testing.expectEqual(@as(u32, 2), try h.run(&state));
    try testing.expectEqual(@as(u64, 0x8004), state.regs.rip);
}

test "memory operands reach the helpers with the resolved address and an abort stops the block after the instruction" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    // mov rax, [rbx + rcx*8 + 0x10] with rbx=0x100 rcx=2 → address 0x120
    std.mem.writeInt(u64, state.memory[0x120..][0..8], 0xDEAD_BEEF_CAFE_F00D, .little);
    state.regs.rbx = 0x100;
    state.regs.rcx = 2;
    var load: DecodedInsn = .{ .op = .mov_reg64_mem64, .size = .bits64, .dst_reg = .al_ax_eax_rax, .addr = 0x10 };
    load.sib_has_base = true;
    load.sib_base_reg = .bl_bx_ebx_rbx;
    load.sib_has_index = true;
    load.sib_index_reg = .cl_cx_ecx_rcx;
    load.sib_scale = 3;
    try h.add(0x9000, 5, load);
    // mov [rip + 0x100], eax → address = 0x9005 + 0x100 = 0x9105, beyond the test memory: write is dropped but counted.
    var store: DecodedInsn = .{ .op = .mov_mem32_reg32, .size = .bits32, .src_reg = .al_ax_eax_rax, .addr = 0x100, .rip_relative = true };
    store.len = 6;
    try h.add(0x9005, 6, store);
    // lea rdx, [rbx + 0x40]
    var lea: DecodedInsn = .{ .op = .lea_reg_mem, .size = .bits64, .dst_reg = .dl_dx_edx_rdx, .addr = 0x40 };
    lea.sib_has_base = true;
    lea.sib_base_reg = .bl_bx_ebx_rbx;
    try h.add(0x900B, 4, lea);
    // push rax ; pop rsi
    state.regs.rsp = 0x800;
    try h.add(0x900F, 1, .{ .op = .push_reg, .src_reg = .al_ax_eax_rax });
    try h.add(0x9010, 1, .{ .op = .pop_reg, .dst_reg = .dh_si_esi_rsi });
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 5), completed);
    try testing.expectEqual(@as(u64, 0xDEAD_BEEF_CAFE_F00D), state.regs.rax);
    try testing.expectEqual(@as(u64, 0x140), state.regs.rdx);
    try testing.expectEqual(@as(u64, 0xDEAD_BEEF_CAFE_F00D), state.regs.rsi);
    try testing.expectEqual(@as(u64, 0x800), state.regs.rsp);
    try testing.expectEqual(@as(u64, 0xDEAD_BEEF_CAFE_F00D), std.mem.readInt(u64, state.memory[0x7F8..][0..8], .little));
    try testing.expectEqual(@as(u32, 2), state.reads);
    try testing.expectEqual(@as(u32, 2), state.writes);
    // The pop was instruction 4 and was the last helper caller.
    try testing.expectEqual(@as(u32, 4), state.last_helper_index);
    try testing.expect(!h.block.register_only);

    // The same block with a helper that raises the abort flag: the load
    // completes (rax written), then the block leaves with rip at the store.
    state = TestState{};
    std.mem.writeInt(u64, state.memory[0x120..][0..8], 0x1234, .little);
    state.regs.rbx = 0x100;
    state.regs.rcx = 2;
    state.regs.rsp = 0x800;
    state.abort_on_access = true;
    const aborted = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), aborted);
    try testing.expectEqual(@as(u64, 0x1234), state.regs.rax);
    try testing.expectEqual(@as(u64, 0x9005), state.regs.rip);
}

test "MOVZX byte load honors REX.X and cached RBX plus R9 SIB operands" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};

    // Exact instruction from fmt::v12::detail::copy_noinline in the stuck
    // Xenia run: 46 0F B6 1C 0B = movzx r11d, byte ptr [rbx + r9]. REX.X
    // extends the SIB index; dropping that prefix would accidentally test RCX
    // and miss the observed zero-page access. Keep RBX and R9 live in the
    // block register cache across the helper boundary.
    const decoded = x64_decoder.decodeLegacyInstruction(&.{ 0x46, 0x0F, 0xB6, 0x1C, 0x0B }, .long64);
    try testing.expectEqual(Op.movzx_reg32_mem8, decoded.op);
    try testing.expectEqual(RegId.r11b_r11w_r11d_r11, decoded.dst_reg);
    try testing.expect(decoded.sib_has_base);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, decoded.sib_base_reg);
    try testing.expect(decoded.sib_has_index);
    try testing.expectEqual(RegId.r9b_r9w_r9d_r9, decoded.sib_index_reg);
    try testing.expectEqual(@as(u2, 0), decoded.sib_scale);

    state.regs.rbx = 0x200;
    state.regs.r9 = 0;
    state.memory[0x200] = 'Z';
    try h.add(0x9000, decoded.len, decoded);
    // Keep both address registers hot across the helper boundary. The tail
    // makes the block allocator cache RBX and RCX, reproducing the situation
    // where the fault report's backing register snapshot can lag the values
    // that the generated block is actually using.
    for (0..3) |index| {
        const rip = @as(u64, 0x9005) + @as(u64, @intCast(index)) * 3;
        try h.add(rip, 3, regReg(.add_reg64_reg64, .bits64, .bl_bx_ebx_rbx, .r9b_r9w_r9d_r9));
    }
    const insns = h.insns.items;
    const last = insns[insns.len - 1];
    const compiled = try compile(testing.allocator, &h.memory, TestState.layout, insns, last.rip + last.len);
    try testing.expect(compiled.cached_registers >= 2);
    try testing.expectEqual(@as(u32, 4), try h.run(&state));
    try testing.expectEqual(@as(u64, 0x200), state.regs.rbx);
    try testing.expectEqual(@as(u64, 0), state.regs.r9);
    try testing.expectEqual(@as(u64, 'Z'), state.regs.r11);
    try testing.expectEqual(@as(u32, 1), state.reads);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "an unsupported instruction is handed to the interpreter helper and its exit request ends the block" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.regs.rax = 1;
    state.regs.rbx = 2;
    // add rax, rbx ; <unsupported: lahf> ; add rax, rbx
    try h.add(0xA000, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0xA003, 3, .{ .op = .lahf, .size = .bits64, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    try h.add(0xA006, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    var completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 3), completed);
    try testing.expectEqual(@as(u32, 1), state.interprets);
    try testing.expectEqual(@as(u32, 1), state.last_interpret_index);
    try testing.expectEqual(@as(u64, 5), state.regs.rax);
    try testing.expectEqual(@as(u64, 0xA009), state.regs.rip);
    try testing.expectEqual(@as(u32, 2), h.block.native_count);
    try testing.expectEqual(@as(u32, 1), h.block.fallback_count);

    // When the interpreter says the block must stop, it stops after that
    // instruction with the interpreter's rip untouched.
    state = TestState{};
    state.regs.rax = 1;
    state.regs.rbx = 2;
    state.interpret_result = 1;
    completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 2), completed);
    try testing.expectEqual(@as(u64, 3), state.regs.rax);
    try testing.expectEqual(@as(u64, 0xA006), state.regs.rip);
}

test "a return that carries its result in ZF keeps it under the Windows calling convention" {
    // Xenia's reserved-store helper - every PowerPC `stwcx.` the title
    // executes - ends `setz al ; setc ah ; cmp ax, 0x0101 ; ret`, and its
    // caller reads the result with `setz`. ZF is the helper's return value.
    // Treating flags as dead at the `ret` dropped the `cmp`, so a store that
    // never happened (another thread held the reservation: CF=0) reported
    // success whenever a stale ZF was set.
    var h = try TestHarness.init();
    defer h.deinit();
    const program = [_][]const u8{ &.{ 0x0F, 0x94, 0xC0 }, &.{ 0x0F, 0x92, 0xC4 }, &.{ 0x66, 0x3D, 0x01, 0x01 }, &.{0xC3} };
    const cases = [_]struct { zf: bool, cf: bool }{
        .{ .zf = true, .cf = false }, // no reservation, stale ZF: must fail
        .{ .zf = false, .cf = false },
        .{ .zf = false, .cf = true }, // the compare-exchange lost: must fail
        .{ .zf = true, .cf = true }, // stored: must succeed
    };
    for (cases) |case| {
        h.insns.clearRetainingCapacity();
        var rip: u64 = 0xB000;
        for (program) |bytes| {
            const decoded = x64_decoder.decodeLegacyInstruction(bytes, .long64);
            try h.add(rip, @intCast(bytes.len), decoded);
            rip += bytes.len;
        }
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = 0x200;
        std.mem.writeInt(u64, state.memory[0x200..][0..8], 0xFEED, .little);
        state.regs.rflags = 0x2 | (if (case.zf) RFL_ZF else 0) | (if (case.cf) RFL_CF else 0);
        _ = try h.runWith(&state, .{ .flags_dead_at_calls = true });
        TestState.flags(&state);
        try testing.expectEqual(@as(u64, 0xFEED), state.regs.rip);
        try testing.expectEqual(case.zf and case.cf, state.regs.rflags & RFL_ZF != 0);
    }
}

test "a return owes only the flags a helper can be returning" {
    const shapes = [_]struct { program: []const []const u8, image: u8, code_cache: u8 }{
        // Xenia's reserved-store helper: the compare is the return value.
        .{ .program = &.{ &.{ 0x0F, 0x94, 0xC0 }, &.{ 0x0F, 0x92, 0xC4 }, &.{ 0x66, 0x3D, 0x01, 0x01 }, &.{0xC3} }, .image = F_ALL, .code_cache = F_ALL },
        // cmp eax, ecx ; setl al ; ret - the compiler's setl consumed it.
        .{ .program = &.{ &.{ 0x39, 0xC8 }, &.{ 0x0F, 0x9C, 0xC0 }, &.{0xC3} }, .image = 0, .code_cache = F_ZF | F_CF },
        // sub eax, ecx ; ret
        .{ .program = &.{ &.{ 0x29, 0xC8 }, &.{0xC3} }, .image = 0, .code_cache = F_ZF | F_CF },
        // add rsp, 8 ; ret - an epilogue.
        .{ .program = &.{ &.{ 0x48, 0x83, 0xC4, 0x08 }, &.{0xC3} }, .image = 0, .code_cache = 0 },
        // mov eax, 1 ; ret - nothing written, nothing owed.
        .{ .program = &.{ &.{ 0xB8, 0x01, 0x00, 0x00, 0x00 }, &.{0xC3} }, .image = 0, .code_cache = 0 },
    };
    for (shapes) |shape| {
        var insns: [4]Insn = undefined;
        var rip: u64 = 0xB000;
        for (shape.program, 0..) |bytes, i| {
            var decoded = x64_decoder.decodeLegacyInstruction(bytes, .long64);
            decoded.len = @intCast(bytes.len);
            insns[i] = .{ .rip = rip, .len = @intCast(bytes.len), .decoded = decoded, .segment = .ds };
            rip += bytes.len;
        }
        const block = insns[0..shape.program.len];
        try testing.expectEqual(shape.image, returnFlagsLive(block, .image));
        try testing.expectEqual(shape.code_cache, returnFlagsLive(block, .code_cache));
        try testing.expectEqual(shape.code_cache, exitFlagsLive(block, .{ .flags_dead_at_calls = true, .ledger = .code_cache }));
        try testing.expectEqual(@as(u8, F_ALL), exitFlagsLive(block, .{}));
    }
}

test "outside the image a return carries ZF and CF, while a compiled epilogue stays free" {
    var h = try TestHarness.init();
    defer h.deinit();
    const returnsZf = struct {
        fn run(harness: *TestHarness, program: []const []const u8, ledger: Ledger, ecx: u64) !TestState {
            harness.insns.clearRetainingCapacity();
            var rip: u64 = 0xB000;
            for (program) |bytes| {
                try harness.add(rip, @intCast(bytes.len), x64_decoder.decodeLegacyInstruction(bytes, .long64));
                rip += bytes.len;
            }
            var state = TestState{};
            state.admitMemory(true, true);
            state.regs.rsp = 0x200;
            state.regs.rax = 7;
            state.regs.rcx = ecx;
            std.mem.writeInt(u64, state.memory[0x200..][0..8], 0xFEED, .little);
            std.mem.writeInt(u64, state.memory[0x208..][0..8], 0xFEED, .little);
            // A stale ZF the helper's own result has to replace.
            state.regs.rflags = 0x2 | RFL_ZF;
            _ = try harness.runWith(&state, .{ .flags_dead_at_calls = true, .ledger = ledger });
            TestState.flags(&state);
            return state;
        }
    };
    // sub eax, ecx ; ret - a JIT helper that returns "equal" in ZF.
    const sub_ret = [_][]const u8{ &.{ 0x29, 0xC8 }, &.{0xC3} };
    const differs = try returnsZf.run(&h, &sub_ret, .code_cache, 3);
    try testing.expect(differs.regs.rflags & RFL_ZF == 0);
    const equal = try returnsZf.run(&h, &sub_ret, .code_cache, 7);
    try testing.expect(equal.regs.rflags & RFL_ZF != 0);
    // add rsp, 8 ; ret in the image: the epilogue's flags are elided, as the
    // calling convention allows - the common return pays nothing.
    const epilogue = [_][]const u8{ &.{ 0x48, 0x83, 0xC4, 0x08 }, &.{0xC3} };
    _ = try returnsZf.run(&h, &epilogue, .image, 0);
    try testing.expectEqual(@as(u32, 1), h.flags_elided);
    // The same epilogue in the code cache owes nothing either.
    _ = try returnsZf.run(&h, &epilogue, .code_cache, 0);
    try testing.expectEqual(@as(u32, 1), h.flags_elided);
}

test "a block with nothing native to emit is refused" {
    var h = try TestHarness.init();
    defer h.deinit();
    try h.add(0xB000, 3, .{ .op = .lahf, .size = .bits64, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    var state = TestState{};
    try testing.expectError(Error.NothingToCompile, h.run(&state));
    // RIP-relative indirect calls now compile to the guarded memory-call
    // template. With unknown image/IAT bounds and an unreadable slot the
    // runtime guard still routes the call through the interpreter.
    h.insns.clearRetainingCapacity();
    try h.add(0xB000, 6, .{ .op = .call_mem64, .rip_relative = true });
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u32, 1), state.interprets);
    // A lone `ret` is not one of those any more. It compiles to a guarded
    // pop into RIP, which is worth a block on its own: the alternative is a
    // full interpreter step, whose hook gates, hotness probe and decode
    // cache lookup cost more than this block's prologue and epilogue.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    try h.add(0xB000, 1, .{ .op = .ret });
    state.admitMemory(true, true);
    state.regs.rsp = 0x200;
    std.mem.writeInt(u64, state.memory[0x200..][0..8], 0xFEED, .little);
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u64, 0xFEED), state.regs.rip);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "an import slot a lock-free lane answers stays in translated code, for a call and for a thunk's jump" {
    var h = try TestHarness.init();
    defer h.deinit();
    // call [rip+0x3E] at 0x100 reads the IAT slot at 0x144.
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rsp = 0x800;
    state.image_low = 0x100;
    state.image_high = 0x180;
    state.iat_low = 0x140;
    state.iat_high = 0x150;
    state.image_targets_hooked = 0;
    state.import_lane_answers = true;
    try h.add(0x100, 6, .{ .op = .call_mem64, .size = .bits64, .addr = 0x3E, .rip_relative = true });
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u32, 1), state.import_transfer_calls);
    try testing.expectEqual(@as(u64, 0x144), state.last_import_slot);
    // The call never pushed: the lane returned straight to the next RIP.
    try testing.expectEqual(@as(u64, 0x106), state.regs.rip);
    try testing.expectEqual(@as(u64, 0x800), state.regs.rsp);
    try testing.expectEqual(@as(u64, 0x1A7E), state.regs.rax);

    // jmp [rip+0x3E] - a memset thunk: the caller's return address is on the
    // stack, and the lane pops it.
    state = TestState{};
    state.admitMemory(true, true);
    state.regs.rsp = 0x7F8;
    std.mem.writeInt(u64, state.memory[0x7F8..][0..8], 0x4242, .little);
    state.image_low = 0x100;
    state.image_high = 0x180;
    state.iat_low = 0x140;
    state.iat_high = 0x150;
    state.image_targets_hooked = 0;
    state.import_lane_answers = true;
    h.insns.clearRetainingCapacity();
    try h.add(0x100, 6, .{ .op = .jmp_mem64, .size = .bits64, .addr = 0x3E, .rip_relative = true });
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 0x4242), state.regs.rip);
    try testing.expectEqual(@as(u64, 0x800), state.regs.rsp);
    try testing.expectEqual(@as(u64, 0x1A7E), state.regs.rax);

    // A lane that declines changes nothing, and the interpreter takes the
    // jump from the start.
    state.regs.rsp = 0x7F8;
    state.regs.rax = 0;
    state.import_lane_answers = false;
    state.import_transfer_calls = 0;
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u32, 1), state.import_transfer_calls);
    try testing.expectEqual(@as(u32, 1), state.interprets);
    try testing.expectEqual(@as(u64, 0x7F8), state.regs.rsp);
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
}

test "a jump through a non-import slot transfers natively to a proven code-cache target" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rsp = 0x800;
    state.image_low = 0x100;
    state.image_high = 0x180;
    state.iat_low = 0x140;
    state.iat_high = 0x150;
    state.image_targets_hooked = 0;
    state.mapped_transfer_allowed = true;
    state.import_lane_answers = true;
    // jmp [rip+0x20] reads the jump-table slot at 0x126, outside the IAT.
    std.mem.writeInt(u64, state.memory[0x126..][0..8], 0xA000_5000, .little);
    try h.add(0x100, 6, .{ .op = .jmp_mem64, .size = .bits64, .addr = 0x20, .rip_relative = true });
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u32, 0), state.import_transfer_calls);
    try testing.expectEqual(@as(u64, 0xA000_5000), state.regs.rip);
    // A jump pushes nothing.
    try testing.expectEqual(@as(u64, 0x800), state.regs.rsp);
    try testing.expect(isNative(.{ .op = .jmp_mem64, .size = .bits64, .addr = 0x20, .rip_relative = true }));
}

test "raw x87 stack transfers use the focused helper, not the interpreter fallback" {
    var h = try TestHarness.init();
    defer h.deinit();
    try h.add(0xB100, 2, .{ .op = .fld_st, .imm = 1, .is_reg_form = true });
    var state = TestState{};
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u32, 1), state.x87_fast_helpers);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expect(!h.block.register_only);
}

test "x87 memory operations keep their block translated through the focused helper" {
    var h = try TestHarness.init();
    defer h.deinit();
    try h.add(0xB200, 2, .{ .op = .x87_memory, .size = .bits32, .addr = 0, .imm = 0 });
    var state = TestState{};
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u32, 1), state.x87_memory_helpers);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u32, 1), h.block.native_count);
    try testing.expectEqual(@as(u32, 0), h.block.fallback_count);
    try testing.expect(!h.block.register_only);
}

test "RIP-relative indirect calls keep non-IAT function pointers native" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rsp = 0x800;
    state.image_low = 0x100;
    state.image_high = 0x180;
    state.iat_low = 0x140;
    state.iat_high = 0x150;
    state.image_targets_hooked = 0;
    state.mapped_transfer_allowed = true;
    std.mem.writeInt(u64, state.memory[0x126..][0..8], 0xA000_3000, .little);
    try h.add(0x100, 6, .{ .op = .call_mem64, .size = .bits64, .addr = 0x20, .rip_relative = true });
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 0xA000_3000), state.regs.rip);
    try testing.expectEqual(@as(u64, 0x7F8), state.regs.rsp);
    try testing.expectEqual(@as(u64, 0x106), std.mem.readInt(u64, state.memory[0x7F8..][0..8], .little));

    // A real IAT slot must still take the interpreter's import path.
    state = TestState{};
    state.admitMemory(true, true);
    state.regs.rsp = 0x800;
    state.image_low = 0x100;
    state.image_high = 0x180;
    state.iat_low = 0x140;
    state.iat_high = 0x150;
    state.image_targets_hooked = 0;
    state.mapped_transfer_allowed = true;
    std.mem.writeInt(u64, state.memory[0x144..][0..8], 0xA000_3000, .little);
    h.insns.clearRetainingCapacity();
    try h.add(0x100, 6, .{ .op = .call_mem64, .size = .bits64, .addr = 0x3E, .rip_relative = true });
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u32, 1), state.interprets);
    try testing.expectEqual(@as(u64, 0x800), state.regs.rsp);

    // If IAT bounds are unavailable, image-local slots remain conservatively
    // interpreted so dynamic import shims retain their ownership.
    state = TestState{};
    state.admitMemory(true, true);
    state.regs.rsp = 0x800;
    state.image_low = 0x100;
    state.image_high = 0x180;
    state.image_targets_hooked = 0;
    state.mapped_transfer_allowed = true;
    std.mem.writeInt(u64, state.memory[0x126..][0..8], 0xA000_3000, .little);
    h.insns.clearRetainingCapacity();
    try h.add(0x100, 6, .{ .op = .call_mem64, .size = .bits64, .addr = 0x20, .rip_relative = true });
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u32, 1), state.interprets);
}

test "published code-cache bounds admit hot transfers without the mapped-transfer helper" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rsp = 0x800;
    state.regs.rbx = 0xA000_3000;
    state.image_low = 0x1_4000_0000;
    state.image_high = 0x1_5000_0000;
    state.code_cache_low = 0xA000_0000;
    state.code_cache_high = 0xB000_0000;
    state.image_targets_hooked = 0;
    // The callback deliberately refuses; the published range is the proof
    // for Xenia's dedicated mapping and should bypass it.
    try h.add(0xC000, 2, .{ .op = .call_reg64, .dst_reg = .bl_bx_ebx_rbx });
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u32, 0), state.mapped_transfer_calls);
    try testing.expectEqual(@as(u64, 0xA000_3000), state.regs.rip);
    try testing.expectEqual(@as(u64, 0x7F8), state.regs.rsp);

    // A published range proves that an out-of-range target cannot be in the
    // designated code-cache view, so it takes the interpreter path without a
    // callback that can only return false.
    state = TestState{};
    state.admitMemory(true, true);
    state.regs.rsp = 0x800;
    state.regs.rbx = 0xC000_3000;
    state.image_low = 0x1_4000_0000;
    state.image_high = 0x1_5000_0000;
    state.code_cache_low = 0xA000_0000;
    state.code_cache_high = 0xB000_0000;
    state.image_targets_hooked = 0;
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u32, 1), state.interprets);
    try testing.expectEqual(@as(u32, 0), state.mapped_transfer_calls);
}

test "the block boundary rules: host-reaching instructions end a block before themselves, control transfers end it as fallbacks" {
    try testing.expect(endsBlockBefore(.{ .op = .syscall }));
    try testing.expect(endsBlockBefore(.{ .op = .hlt }));
    try testing.expect(endsBlockBefore(.{ .op = .cpuid }));
    try testing.expect(endsBlockBefore(.{ .op = .nop, .len = 2 }));
    try testing.expect(!endsBlockBefore(.{ .op = .nop, .len = 1 }));
    try testing.expect(!endsBlockBefore(.{ .op = .call_rel32 }));
    try testing.expect(!endsBlockBefore(.{ .op = .ret }));
    try testing.expect(isFallbackTerminator(.call_rel32) and isFallbackTerminator(.ret) and isFallbackTerminator(.jmp_reg64) and isFallbackTerminator(.call_mem64) and isFallbackTerminator(.loop));
    try testing.expect(!isFallbackTerminator(.jcc_rel8) and !isFallbackTerminator(.add_reg64_reg64));
    try testing.expect(isTerminator(.jcc_rel32) and isTerminator(.jmp_rel8) and !isTerminator(.call_rel32));
    try testing.expect(!isNative(.{ .op = .add_reg64_reg64, .lock = true }));
    // A narrow shift is native while its count stays inside the operand.
    try testing.expect(isNative(.{ .op = .shl_reg_imm, .size = .bits16 }));
    try testing.expect(!isNative(.{ .op = .shl_reg_imm, .size = .bits16, .imm = 16 }));
    try testing.expect(isNative(.{ .op = .shl_reg_imm, .size = .bits32 }));
    try testing.expect(isNative(.{ .op = .shl_reg_cl, .size = .bits64 }));
    try testing.expect(isNative(.{ .op = .shl_mem_cl, .size = .bits64, .addr = 0x120 }));
    try testing.expect(isNative(.{ .op = .shr_mem_cl, .size = .bits32, .addr = 0x120 }));
    try testing.expect(isNative(.{ .op = .sar_mem_cl, .size = .bits16, .addr = 0x120 }));
    try testing.expect(isNative(.{ .op = .add_mem32_reg32, .size = .bits32 }));
    try testing.expect(isNative(.{ .op = .movbe_reg_mem, .size = .bits32 }));
    try testing.expect(!isNative(.{ .op = .movbe_reg_mem, .size = .bits8 }));
    // A direct call is native as far as this predicate is concerned; the
    // glue decides per call site, because whether the interpreter's arm has
    // a hook for it is a property of the target, not of the encoding.
    try testing.expect(isNative(.{ .op = .call_rel32 }));
    try testing.expect(isNative(.{ .op = .call_reg64, .dst_reg = .bl_bx_ebx_rbx }));
    try testing.expect(isNative(.{ .op = .call_reg64, .dst_reg = .ah_sp_esp_rsp }));
    try testing.expect(!isNative(.{ .op = .div_reg8, .size = .bits8 }));
    try testing.expect(isNative(.{ .op = .div_reg32, .size = .bits32 }));
}

test "LOCK prefix validation accepts only architecturally supported memory updates" {
    try testing.expect(lockPrefixAllowed(.{ .op = .add_mem32_reg32, .lock = true, .is_reg_form = false }));
    try testing.expect(lockPrefixAllowed(.{ .op = .adc_mem64_reg64, .lock = true, .is_reg_form = false }));
    try testing.expect(lockPrefixAllowed(.{ .op = .adc_mem64_imm8, .lock = true, .is_reg_form = false }));
    try testing.expect(lockPrefixAllowed(.{ .op = .xchg_mem64_reg64, .lock = true, .is_reg_form = false }));
    try testing.expect(lockPrefixAllowed(.{ .op = .bts_mem_reg, .lock = true, .is_reg_form = false }));
    try testing.expect(lockPrefixAllowed(.{ .op = .cmpxchg16b_mem, .lock = true, .is_reg_form = false }));
    try testing.expect(lockPrefixAllowed(.{ .op = .add_reg64_reg64, .lock = false, .is_reg_form = true }));

    try testing.expect(!lockPrefixAllowed(.{ .op = .nop, .lock = true, .is_reg_form = true }));
    try testing.expect(!lockPrefixAllowed(.{ .op = .add_reg64_reg64, .lock = true, .is_reg_form = true }));
    try testing.expect(!lockPrefixAllowed(.{ .op = .cmp_mem32_reg32, .lock = true, .is_reg_form = false }));
    try testing.expect(!lockPrefixAllowed(.{ .op = .bt_mem_reg, .lock = true, .is_reg_form = false }));
    try testing.expect(!isNative(.{ .op = .add_reg64_reg64, .lock = true, .is_reg_form = true }));
}

test "native byte xchg is an implicit atomic and preserves high-byte aliases" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rax = 0xAB00;
    state.memory[0x120] = 0x35;
    state.memory[0x121] = 0xCC;

    var xchg = baseDisp(.xchg_mem8_reg8, .bits8, .al_ax_eax_rax, 0x20);
    xchg.src_high8 = true;
    try h.add(0x1000, 3, xchg);
    _ = try h.run(&state);

    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u8, 0xAB), state.memory[0x120]);
    try testing.expectEqual(@as(u8, 0xCC), state.memory[0x121]);
    try testing.expectEqual(@as(u8, 0x35), @as(u8, @truncate(state.regs.rax >> 8)));
}

test "a control transfer is compiled as the block's last instruction and nothing after it is emitted" {
    var h = try TestHarness.init();
    defer h.deinit();
    // mov rax, rbx ; call [rip + slot] ; add rax, rbx (never part of the
    // block). The call is compiled with a runtime guard; an import-table
    // target still takes the interpreter-owned import path.
    try h.add(0xC000, 3, regReg(.mov_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0xC003, 5, .{ .op = .call_mem64, .rip_relative = true });
    try h.add(0xC008, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    var state = TestState{};
    state.regs.rbx = 7;
    state.interpret_result = 1;
    var completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 2), completed);
    try testing.expectEqual(@as(u32, 1), state.interprets);
    try testing.expectEqual(@as(u32, 1), state.last_interpret_index);
    try testing.expectEqual(@as(u64, 7), state.regs.rax);
    try testing.expectEqual(@as(u32, 2), h.block.native_count);
    try testing.expectEqual(@as(u32, 0), h.block.fallback_count);
    // A shim that consumed the call leaves RIP at the next instruction and
    // says "continue": the block still ends there.
    state = TestState{};
    state.regs.rbx = 9;
    state.interpret_result = 0;
    completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 2), completed);
    try testing.expectEqual(@as(u64, 0xC008), state.regs.rip);
    try testing.expectEqual(@as(u64, 9), state.regs.rax);
}

test "an effective address folds a small displacement and keeps negative and wide ones exact" {
    var h = try TestHarness.init();
    defer h.deinit();
    // mov rax, [rbx-8] ; mov rcx, [rdx+0x1010] ; mov r8, [rbx]
    try h.add(0x1000, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, @bitCast(@as(i64, -8))));
    try h.add(0x1004, 7, .{ .op = .mov_reg64_mem64, .size = .bits64, .dst_reg = .cl_cx_ecx_rcx, .src_reg = .cl_cx_ecx_rcx, .addr = 0x1010, .sib_has_base = true, .sib_base_reg = .dl_dx_edx_rdx });
    try h.add(0x100B, 3, baseDisp(.mov_reg64_mem64, .bits64, .r8b_r8w_r8d_r8, 0));
    for ([_]bool{ true, false }) |admitted| {
        var state = TestState{};
        state.admitMemory(admitted, admitted);
        state.regs.rbx = 0x800;
        // A base below the page whose displacement is too wide for an
        // immediate: the sum lands at 0x10.
        state.regs.rdx = 0 -% @as(u64, 0x1000);
        std.mem.writeInt(u64, state.memory[0x7F8..][0..8], 0x1111, .little);
        std.mem.writeInt(u64, state.memory[0x10..][0..8], 0x2222, .little);
        std.mem.writeInt(u64, state.memory[0x800..][0..8], 0x3333, .little);
        _ = try h.run(&state);
        try testing.expectEqual(@as(u64, 0x1111), state.regs.rax);
        try testing.expectEqual(@as(u64, 0x2222), state.regs.rcx);
        try testing.expectEqual(@as(u64, 0x3333), state.regs.r8);
    }
}

test "plain [base+disp] accesses share one hoisted page translation and stay correct when it cannot be made" {
    var h = try TestHarness.init();
    defer h.deinit();
    // mov rax, [rbx+0x20] ; mov [rbx+0x40], rcx ; mov edx, [rbx+0x24] ; add rax, [rbx+0x28]
    try h.add(0x1000, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, 0x20));
    try h.add(0x1004, 4, baseDisp(.mov_mem64_reg64, .bits64, .cl_cx_ecx_rcx, 0x40));
    try h.add(0x1008, 3, baseDisp(.mov_reg32_mem32, .bits32, .dl_dx_edx_rdx, 0x24));
    try h.add(0x100B, 4, baseDisp(.add_reg64_mem64, .bits64, .al_ax_eax_rax, 0x28));
    {
        const insns = h.insns.items;
        const last = insns[insns.len - 1];
        const compiled = try compile(testing.allocator, &h.memory, TestState.layout, insns, last.rip + last.len);
        try testing.expect(compiled.hoisted_accesses >= 3);
    }
    for ([_]bool{ true, false }) |admitted| {
        var state = TestState{};
        state.admitMemory(admitted, admitted);
        std.mem.writeInt(u64, state.memory[0x120..][0..8], 0x1111_2222_3333_4444, .little);
        std.mem.writeInt(u64, state.memory[0x128..][0..8], 5, .little);
        state.regs.rbx = 0x100;
        state.regs.rcx = 0xABCD;
        _ = try h.run(&state);
        try testing.expectEqual(@as(u64, 0x1111_2222_3333_4444 + 5), state.regs.rax);
        try testing.expectEqual(@as(u64, 0x1111_2222), state.regs.rdx);
        try testing.expectEqual(@as(u64, 0xABCD), std.mem.readInt(u64, state.memory[0x140..][0..8], .little));
        // Without admission every access took the ordinary probe's helper.
        if (!admitted) try testing.expect(state.reads >= 3 and state.writes >= 1);
    }

    // 128-bit moves through the same base share the hoisted pointer too:
    // vmovdqu xmm0, [rbx+0x40] ; vmovdqu [rbx+0x60], xmm0 ; mov rax, [rbx+0x20]
    {
        h.insns.clearRetainingCapacity();
        var load = baseDisp(.vmovdqu_xmm_mem, .bits64, .al_ax_eax_rax, 0x40);
        load.xmm_dst = 0;
        var store = baseDisp(.vmovdqu_mem_xmm, .bits64, .al_ax_eax_rax, 0x60);
        store.xmm_src = 0;
        try h.add(0x1000, 5, load);
        try h.add(0x1005, 5, store);
        try h.add(0x100A, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, 0x20));
        const insns = h.insns.items;
        const last = insns[insns.len - 1];
        const compiled = try compile(testing.allocator, &h.memory, TestState.layout, insns, last.rip + last.len);
        try testing.expect(compiled.hoisted_accesses >= 3);
        for ([_]bool{ true, false }) |admitted| {
            var vstate = TestState{};
            vstate.admitMemory(admitted, admitted);
            vstate.regs.rbx = 0x100;
            for (0..16) |i| vstate.memory[0x140 + i] = @intCast(0xA0 + i);
            std.mem.writeInt(u64, vstate.memory[0x120..][0..8], 9, .little);
            _ = try h.run(&vstate);
            try testing.expectEqualSlices(u8, vstate.memory[0x140..0x150], vstate.memory[0x160..0x170]);
            try testing.expectEqual(@as(u64, 9), vstate.regs.rax);
        }
    }

    // A new base mid-block is translated again before it is used.    // A new base mid-block is translated again before it is used.
    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, 0x20));
    try h.add(0x1004, 4, baseDisp(.mov_reg64_mem64, .bits64, .dl_dx_edx_rdx, 0x28));
    try h.add(0x1008, 3, regReg(.mov_reg64_reg64, .bits64, .bl_bx_ebx_rbx, .dh_si_esi_rsi));
    try h.add(0x100B, 4, baseDisp(.mov_reg64_mem64, .bits64, .cl_cx_ecx_rcx, 0x20));
    try h.add(0x100F, 4, baseDisp(.mov_reg64_mem64, .bits64, .r8b_r8w_r8d_r8, 0x28));
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rsi = 0x800;
    std.mem.writeInt(u64, state.memory[0x120..][0..8], 1, .little);
    std.mem.writeInt(u64, state.memory[0x128..][0..8], 2, .little);
    std.mem.writeInt(u64, state.memory[0x820..][0..8], 3, .little);
    std.mem.writeInt(u64, state.memory[0x828..][0..8], 4, .little);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u64, 2), state.regs.rdx);
    try testing.expectEqual(@as(u64, 3), state.regs.rcx);
    try testing.expectEqual(@as(u64, 4), state.regs.r8);
}

test "two hoisted pages survive helpers and independent base writes with separate read/write admissions" {
    var h = try TestHarness.init();
    defer h.deinit();
    // Context in rbx and another object in rsi. An indexed load between
    // them misses the page, calls C and overwrites x30's link register.
    for (0..3) |i| try h.add(0x1000 + i * 4, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, i * 8));
    var secondary = baseDispAt(.mov_reg64_mem64, .bits64, .dh_si_esi_rsi, 0);
    secondary.dst_reg = .dl_dx_edx_rdx;
    try h.add(0x100C, 4, secondary);
    var miss = baseDisp(.mov_reg64_mem64, .bits64, .r9b_r9w_r9d_r9, 0x3000);
    miss.sib_has_index = true;
    miss.sib_index_reg = .cl_cx_ecx_rcx;
    try h.add(0x1010, 4, miss);
    secondary.addr = 8;
    secondary.dst_reg = .r8b_r8w_r8d_r8;
    try h.add(0x1014, 4, secondary);
    // Updating only rsi must re-admit the second span.
    try h.add(0x1018, 4, regImm(.add_reg64_imm32, .bits64, .dh_si_esi_rsi, 0x100));
    secondary.addr = 0;
    secondary.dst_reg = .r10b_r10w_r10d_r10;
    try h.add(0x101C, 4, secondary);
    secondary = baseDispAt(.mov_mem64_reg64, .bits64, .dh_si_esi_rsi, 16);
    secondary.src_reg = .r8b_r8w_r8d_r8;
    try h.add(0x1020, 4, secondary);
    try h.add(0x1024, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, 16));
    const compiled = try compile(testing.allocator, &h.memory, TestState.layout, h.insns.items, 0x1028);
    try testing.expectEqual(@as(u32, 8), compiled.hoisted_accesses);
    for ([_]bool{ true, false }) |admitted| {
        var state = TestState{};
        // A read-only TLB admission cannot satisfy the secondary store.
        state.admitMemory(admitted, false);
        state.regs.rbx = 0x100;
        state.regs.rsi = 0x300;
        std.mem.writeInt(u64, state.memory[0x110..][0..8], 11, .little);
        std.mem.writeInt(u64, state.memory[0x300..][0..8], 22, .little);
        std.mem.writeInt(u64, state.memory[0x308..][0..8], 33, .little);
        std.mem.writeInt(u64, state.memory[0x400..][0..8], 44, .little);
        try testing.expectEqual(@as(u32, 10), try h.run(&state));
        try testing.expectEqual(@as(u64, 11), state.regs.rax);
        try testing.expectEqual(@as(u64, 22), state.regs.rdx);
        try testing.expectEqual(@as(u64, 33), state.regs.r8);
        try testing.expectEqual(@as(u64, 44), state.regs.r10);
        try testing.expectEqual(@as(u64, 33), std.mem.readInt(u64, state.memory[0x410..][0..8], .little));
        try testing.expectEqual(@as(u32, 1), state.writes);
    }
    // Both admitted: the helper still overwrites LR, but the next read
    // uses the saved pointer and the write needs no helper.
    var direct = TestState{};
    direct.admitMemory(true, true);
    direct.regs.rbx = 0x100;
    direct.regs.rsi = 0x300;
    std.mem.writeInt(u64, direct.memory[0x308..][0..8], 99, .little);
    _ = try h.run(&direct);
    try testing.expectEqual(@as(u64, 99), direct.regs.r8);
    try testing.expectEqual(@as(u32, 1), direct.reads);
    try testing.expectEqual(@as(u32, 0), direct.writes);
}

test "absolute and RIP-relative loads share a second hoisted span" {
    var h = try TestHarness.init();
    defer h.deinit();
    for (0..3) |i| try h.add(0x1000 + i * 4, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, i * 8));
    try h.add(0x100C, 8, .{ .op = .mov_reg64_mem64, .size = .bits64, .dst_reg = .dl_dx_edx_rdx, .addr = 0x300 });
    try h.add(0x1014, 7, .{ .op = .mov_reg64_mem64, .size = .bits64, .dst_reg = .r8b_r8w_r8d_r8, .rip_relative = true, .addr = 0x308 -% @as(u64, 0x101B) });
    try h.add(0x101B, 4, baseDisp(.mov_reg64_mem64, .bits64, .r12b_r12w_r12d_r12, 16));
    try h.add(0x101F, 8, .{ .op = .mov_reg64_mem64, .size = .bits64, .dst_reg = .r10b_r10w_r10d_r10, .addr = 0x300 });
    try h.add(0x1027, 8, .{ .op = .mov_reg64_mem64, .size = .bits64, .dst_reg = .r11b_r11w_r11d_r11, .addr = 0x308 });
    const compiled = try compile(testing.allocator, &h.memory, TestState.layout, h.insns.items, 0x102F);
    try testing.expectEqual(@as(u32, 8), compiled.hoisted_accesses);
    for ([_]bool{ true, false }) |admitted| {
        var state = TestState{};
        state.admitMemory(admitted, false);
        state.regs.rbx = 0x100;
        std.mem.writeInt(u64, state.memory[0x300..][0..8], 123, .little);
        std.mem.writeInt(u64, state.memory[0x308..][0..8], 456, .little);
        _ = try h.run(&state);
        try testing.expectEqual(@as(u64, 123), state.regs.rdx);
        try testing.expectEqual(@as(u64, 456), state.regs.r8);
        try testing.expectEqual(@as(u32, if (admitted) 0 else 8), state.reads);
    }
}

test "internal edges skipping the second hoist re-admit it at the target" {
    var h = try TestHarness.init();
    defer h.deinit();
    for (0..3) |i| try h.add(0x1000 + i * 4, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, i * 8));
    try h.add(0x100C, 3, regImm(.cmp_reg64_imm32, .bits64, .cl_cx_ecx_rcx, 0));
    try h.add(0x100F, 2, .{ .op = .jcc_rel8, .cond = .e, .addr = 4 });
    var load = baseDispAt(.mov_reg64_mem64, .bits64, .dh_si_esi_rsi, 0);
    load.dst_reg = .dl_dx_edx_rdx;
    try h.add(0x1011, 4, load);
    load.dst_reg = .r8b_r8w_r8d_r8;
    load.addr = 8;
    try h.add(0x1015, 4, load);
    try h.add(0x1019, 4, load);
    try h.add(0x101D, 4, load);
    try h.add(0x1021, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, 16));
    try h.add(0x1025, 4, regImm(.add_reg64_imm32, .bits64, .r8b_r8w_r8d_r8, 1));
    const compiled = try compile(testing.allocator, &h.memory, TestState.layout, h.insns.items, 0x1029);
    try testing.expectEqual(@as(u32, 1), compiled.internal_edges);
    for ([_]bool{ true, false }) |take| {
        var state = TestState{};
        state.admitMemory(true, false);
        state.regs.rbx = 0x100;
        state.regs.rsi = 0x300;
        state.regs.rcx = @intFromBool(!take);
        state.regs.rdx = 777;
        std.mem.writeInt(u64, state.memory[0x300..][0..8], 123, .little);
        std.mem.writeInt(u64, state.memory[0x308..][0..8], 456, .little);
        try testing.expectEqual(@as(u32, if (take) 10 else 11), try h.run(&state));
        try testing.expectEqual(@as(u64, if (take) 777 else 123), state.regs.rdx);
        try testing.expectEqual(@as(u64, 457), state.regs.r8);
    }
}

test "redundant upper clears are elided but a YMM write requires a fresh clear" {
    var h = try TestHarness.init();
    defer h.deinit();
    const narrow: DecodedInsn = .{ .op = .vmovups_xmm_xmm, .size = .bits64, .xmm_dst = 0, .xmm_src = 1, .is_reg_form = true };
    for (0..4) |i| try h.add(0x1000 + i * 4, 4, narrow);
    const wide: DecodedInsn = .{ .op = .vmovups_ymm_ymm, .size = .bits64, .xmm_dst = 0, .xmm_src = 2, .is_reg_form = true, .vector_256 = true };
    try h.add(0x1010, 4, wide);
    try h.add(0x1014, 4, narrow);
    try h.add(0x1018, 4, narrow);
    const compiled = try compile(testing.allocator, &h.memory, TestState.layout, h.insns.items, 0x101C);
    try testing.expectEqual(@as(u32, 4), compiled.upper_clears_elided);
    var state = TestState{};
    state.xmm[1] = @splat(0x11);
    state.ymm_hi[0] = @splat(0xA5);
    state.ymm_hi[2] = @splat(0xB6);
    state.zmm_hi[0] = @splat(0xC7);
    _ = try h.run(&state);
    try testing.expectEqualSlices(u8, &([_]u8{0x11} ** 16), &state.xmm[0]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[0]);
    // MOVUPS is not routed to EVEX: its existing ZMM preservation remains.
    try testing.expectEqualSlices(u8, &([_]u8{0xC7} ** 32), &state.zmm_hi[0]);
}

test "upper clear knowledge does not cross a conditional edge that skips its writer" {
    var h = try TestHarness.init();
    defer h.deinit();
    try h.add(0x1000, 3, regImm(.cmp_reg64_imm32, .bits64, .al_ax_eax_rax, 0));
    try h.add(0x1003, 2, .{ .op = .jcc_rel8, .cond = .e, .addr = 4 });
    const narrow: DecodedInsn = .{ .op = .vmovups_xmm_xmm, .size = .bits64, .xmm_dst = 0, .xmm_src = 1, .is_reg_form = true };
    try h.add(0x1005, 4, narrow);
    try h.add(0x1009, 4, narrow);
    try h.add(0x100D, 4, regImm(.add_reg64_imm32, .bits64, .cl_cx_ecx_rcx, 1));
    const compiled = try compile(testing.allocator, &h.memory, TestState.layout, h.insns.items, 0x1011);
    try testing.expectEqual(@as(u32, 1), compiled.internal_edges);
    for ([_]u64{ 0, 1 }) |condition| {
        var state = TestState{};
        state.regs.rax = condition;
        state.xmm[1] = @splat(0x11);
        state.ymm_hi[0] = @splat(0xA5);
        _ = try h.run(&state);
        try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[0]);
        try testing.expectEqualSlices(u8, &state.xmm[1], &state.xmm[0]);
    }
}

test "upper clears keep YMM and ZMM proofs separate and discard them after interpreter calls" {
    var h = try TestHarness.init();
    defer h.deinit();
    const move: DecodedInsn = .{ .op = .vmovups_xmm_xmm, .size = .bits64, .xmm_dst = 0, .xmm_src = 1, .is_reg_form = true };
    const add: DecodedInsn = .{ .op = .vpxor, .size = .bits32, .xmm_dst = 0, .xmm_src = 1, .xmm_src2 = 1, .is_reg_form = true };
    try h.add(0x1000, 4, move);
    try h.add(0x1004, 4, add);
    // A forced interpreter boundary must discard both proofs even when its
    // declared opcode is harmless: the helper owns the register file.
    try h.add(0x1008, 1, .{ .op = .nop, .is_reg_form = true });
    h.insns.items[2].force_fallback = true;
    try h.add(0x1009, 4, add);
    var state = TestState{};
    state.ymm_hi[0] = @splat(0xA5);
    state.zmm_hi[0] = @splat(0xC7);
    state.poison_upper_on_interpret = true;
    _ = try h.run(&state);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[0]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 32), &state.zmm_hi[0]);
}

test "vector moves and arithmetic forward only dominating XMM values" {
    var h = try TestHarness.init();
    defer h.deinit();
    var prng = std.Random.DefaultPrng.init(0xF04A_4D46);
    const random = prng.random();
    for (0..64) |_| {
        h.insns.clearRetainingCapacity();
        var state = TestState{};
        random.bytes(std.mem.asBytes(&state.xmm));
        random.bytes(std.mem.asBytes(&state.ymm_hi));
        random.bytes(std.mem.asBytes(&state.zmm_hi));
        var expected = state.xmm;
        var expected_ymm = state.ymm_hi;
        var expected_zmm = state.zmm_hi;
        var last: u8 = 0;
        for (0..24) |i| {
            const dst = random.uintLessThan(u8, 4);
            const rhs = random.uintLessThan(u8, 4);
            const op = ([_]Op{ .vpaddd, .vpsubd, .vpxor })[random.uintLessThan(usize, 3)];
            const a = expected[last];
            const b = expected[rhs];
            for (0..4) |lane| {
                const x = std.mem.readInt(u32, a[lane * 4 ..][0..4], .little);
                const y = std.mem.readInt(u32, b[lane * 4 ..][0..4], .little);
                const result = switch (op) {
                    .vpaddd => x +% y,
                    .vpsubd => x -% y,
                    .vpxor => x ^ y,
                    else => unreachable,
                };
                std.mem.writeInt(u32, expected[dst][lane * 4 ..][0..4], result, .little);
            }
            expected_ymm[dst] = @splat(0);
            if (op == .vpaddd or op == .vpxor) expected_zmm[dst] = @splat(0);
            try h.add(0x1000 + i * 4, 4, .{ .op = op, .size = .bits32, .xmm_dst = dst, .xmm_src = last, .xmm_src2 = rhs, .is_reg_form = true });
            last = dst;
        }
        const compiled = try compile(testing.allocator, &h.memory, TestState.layout, h.insns.items, 0x1060);
        try testing.expect(compiled.xmm_loads_forwarded >= 23);
        _ = try h.run(&state);
        try testing.expectEqualSlices(u8, std.mem.asBytes(&expected), std.mem.asBytes(&state.xmm));
        try testing.expectEqualSlices(u8, std.mem.asBytes(&expected_ymm), std.mem.asBytes(&state.ymm_hi));
        try testing.expectEqualSlices(u8, std.mem.asBytes(&expected_zmm), std.mem.asBytes(&state.zmm_hi));
    }
}

test "vector moves discard forwarding at an internal branch target" {
    var h = try TestHarness.init();
    defer h.deinit();
    try h.add(0x1000, 3, regImm(.cmp_reg64_imm32, .bits64, .al_ax_eax_rax, 0));
    try h.add(0x1003, 2, .{ .op = .jcc_rel8, .cond = .e, .addr = 4 });
    const add: DecodedInsn = .{ .op = .vpaddd, .size = .bits32, .xmm_dst = 0, .xmm_src = 0, .xmm_src2 = 1, .is_reg_form = true };
    try h.add(0x1005, 4, add);
    try h.add(0x1009, 4, add);
    try h.add(0x100D, 4, regImm(.add_reg64_imm32, .bits64, .cl_cx_ecx_rcx, 1));
    for ([_]bool{ true, false }) |taken| {
        var state = TestState{};
        state.regs.rax = @intFromBool(!taken);
        for (0..4) |lane| {
            std.mem.writeInt(u32, state.xmm[0][lane * 4 ..][0..4], 2, .little);
            std.mem.writeInt(u32, state.xmm[1][lane * 4 ..][0..4], 1, .little);
        }
        _ = try h.run(&state);
        for (0..4) |lane| try testing.expectEqual(@as(u32, if (taken) 3 else 4), std.mem.readInt(u32, state.xmm[0][lane * 4 ..][0..4], .little));
    }
}

test "constructor vptr stores preserve RIP-relative image addresses with cached registers" {
    var h = try TestHarness.init();
    defer h.deinit();

    // This is the memory shape used by XObject/XThread constructors: a
    // RIP-relative LEA materialises an image vtable address, then a cached
    // register is stored at the object's base followed by ordinary scalar
    // and vector field stores.  Exercise both TLB modes because the live PE
    // path uses the direct page when it has been admitted.
    var lea: DecodedInsn = .{ .op = .lea_reg_mem, .size = .bits64, .dst_reg = .al_ax_eax_rax, .addr = 0x1200, .rip_relative = true };
    lea.len = 7;
    const vptr_store = baseDisp(.mov_mem64_reg64, .bits64, .al_ax_eax_rax, 0);
    var type_store = baseDisp(.mov_mem32_imm32, .bits32, .al_ax_eax_rax, 0x10);
    type_store.imm = 3;
    var vector_store = baseDisp(.vmovups_mem_xmm, .bits64, .al_ax_eax_rax, 0x20);
    vector_store.xmm_src = 0;
    try h.add(0x1000, 7, lea);
    try h.add(0x1007, 4, vptr_store);
    try h.add(0x100B, 5, type_store);
    try h.add(0x1010, 5, vector_store);

    for ([_]bool{ true, false }) |admitted| {
        var state = TestState{};
        if (admitted) state.admitMemory(true, true);
        state.regs.rcx = 0x200;
        state.regs.rbx = 0x200;
        state.regs.rdx = 0xAABB_CCDD_EEFF_0011;
        state.xmm[0] = @splat(0x5A);
        _ = try h.run(&state);
        try testing.expectEqual(@as(u64, 0x1000 + 7 + 0x1200), std.mem.readInt(u64, state.memory[0x200..][0..8], .little));
        try testing.expectEqual(@as(u32, 3), std.mem.readInt(u32, state.memory[0x210..][0..4], .little));
        try testing.expectEqualSlices(u8, &([_]u8{0x5A} ** 16), state.memory[0x220..0x230]);
    }
}

test "XThread constructor stores keep its vptr through cached base and YMM fields" {
    var h = try TestHarness.init();
    defer h.deinit();

    // This is the straight-line portion of XThread::XThread after its base
    // constructors return.  It is deliberately kept close to the PE bytes:
    // the constructor's vptr LEA, a VEX zeroing fallback, three 256-bit
    // stores, scalar fields, and the final base-register adjustment.
    var lea: DecodedInsn = .{ .op = .lea_reg_mem, .size = .bits64, .dst_reg = .al_ax_eax_rax, .addr = 0x10124F1, .rip_relative = true };
    lea.len = 7;
    try h.add(0x140231C10, 7, lea);
    var vptr_store = baseDispAt(.mov_mem64_reg64, .bits64, .dh_si_esi_rsi, 0);
    vptr_store.src_reg = .al_ax_eax_rax;
    try h.add(0x140231C17, 3, vptr_store);
    try h.add(0x140231C1A, 4, .{ .op = .vxorps, .size = .bits32, .xmm_dst = 0, .xmm_src = 0, .xmm_src2 = 0, .is_reg_form = true });
    for ([_]struct { rip: u64, disp: u64 }{
        .{ .rip = 0x140231C1E, .disp = 0x98 },
        .{ .rip = 0x140231C26, .disp = 0xB8 },
        .{ .rip = 0x140231C2E, .disp = 0xCC },
    }) |store| {
        var ymm_store = baseDispAt(.vmovups_mem_ymm, .bits64, .dh_si_esi_rsi, store.disp);
        ymm_store.vector_256 = true;
        ymm_store.xmm_src = 0;
        try h.add(store.rip, 8, ymm_store);
    }
    var word_store = baseDispAt(.mov_mem16_imm16, .bits16, .dh_si_esi_rsi, 0xEC);
    word_store.imm = 1;
    try h.add(0x140231C36, 9, word_store);
    const byte_store = baseDispAt(.mov_mem8_imm8, .bits8, .dh_si_esi_rsi, 0xEE);
    try h.add(0x140231C3F, 7, byte_store);
    try h.add(0x140231C46, 11, baseDispAt(.mov_mem64_imm32, .bits64, .dh_si_esi_rsi, 0xF0));
    try h.add(0x140231C51, 10, baseDispAt(.mov_mem32_imm32, .bits32, .dh_si_esi_rsi, 0xF8));
    try h.add(0x140231C5B, 11, baseDispAt(.mov_mem64_imm32, .bits64, .dh_si_esi_rsi, 0x100));
    try h.add(0x140231C66, 10, baseDispAt(.mov_mem32_imm32, .bits32, .dh_si_esi_rsi, 0x210));
    try h.add(0x140231C70, 7, regImm(.add_reg64_imm32, .bits64, .dh_si_esi_rsi, 0x218));
    try h.add(0x140231C77, 3, regReg(.mov_reg64_reg64, .bits64, .cl_cx_ecx_rcx, .dh_si_esi_rsi));
    try h.add(0x140231C7A, 2, regReg(.xor_reg32_reg32, .bits32, .dl_dx_edx_rdx, .dl_dx_edx_rdx));
    try h.add(0x140231C7C, 3, .{ .op = .vzeroupper, .size = .bits32, .is_reg_form = true });

    for ([_]bool{ true, false }) |admitted| {
        var state = TestState{};
        if (admitted) state.admitMemory(true, true);
        state.regs.rsi = 0x200;
        _ = try h.run(&state);
        try testing.expectEqual(@as(u64, 0x141244108), std.mem.readInt(u64, state.memory[0x200..][0..8], .little));
        try testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, state.memory[0x2EC..][0..2], .little));
        try testing.expectEqual(@as(u8, 0), state.memory[0x2EE]);
        try testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, state.memory[0x2F0..][0..8], .little));
        try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, state.memory[0x2F8..][0..4], .little));
        try testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, state.memory[0x300..][0..8], .little));
        try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, state.memory[0x410..][0..4], .little));
        try testing.expectEqual(@as(u64, 0x418), state.regs.rsi);
        try testing.expectEqual(@as(u64, 0x418), state.regs.rcx);
        try testing.expectEqual(@as(u64, 0), state.regs.rdx);
        try testing.expectEqualSlices(u8, &([_]u8{0} ** 32), state.memory[0x298..0x2B8]);
        try testing.expectEqualSlices(u8, &([_]u8{0} ** 32), state.memory[0x2B8..0x2D8]);
        try testing.expectEqualSlices(u8, &([_]u8{0} ** 32), state.memory[0x2CC..0x2EC]);
    }
}

test "admitted pages are read and written through the TLB without a helper call, and a page-crossing access is not" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    std.mem.writeInt(u64, state.memory[0x120..][0..8], 0x0102_0304_0506_0708, .little);
    state.regs.rbx = 0x100;
    state.regs.rcx = 0xAABB_CCDD_EEFF_0011;
    // mov rax, [rbx + 0x20] ; mov [rbx + 0x40], rcx ; mov dx, [rbx + 0x22] ; mov byte [rbx + 0x50], 0x7F
    try h.add(0x1000, 4, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, 0x20));
    try h.add(0x1004, 4, baseDisp(.mov_mem64_reg64, .bits64, .cl_cx_ecx_rcx, 0x40));
    try h.add(0x1008, 5, baseDisp(.mov_reg16_mem16, .bits16, .dl_dx_edx_rdx, 0x22));
    var imm_store = baseDisp(.mov_mem8_imm8, .bits8, .al_ax_eax_rax, 0x50);
    imm_store.imm = 0x7F;
    try h.add(0x100D, 4, imm_store);
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 4), completed);
    try testing.expectEqual(@as(u32, 0), state.reads);
    try testing.expectEqual(@as(u32, 0), state.writes);
    try testing.expectEqual(@as(u64, 0x0102_0304_0506_0708), state.regs.rax);
    try testing.expectEqual(@as(u64, 0x0506), state.regs.rdx);
    try testing.expectEqual(@as(u64, 0xAABB_CCDD_EEFF_0011), std.mem.readInt(u64, state.memory[0x140..][0..8], .little));
    try testing.expectEqual(@as(u8, 0x7F), state.memory[0x150]);
    try testing.expect(!h.block.register_only);

    // Only the read side admitted: the store goes to the helper.
    state = TestState{};
    state.admitMemory(true, false);
    state.regs.rbx = 0x100;
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.reads);
    try testing.expectEqual(@as(u32, 2), state.writes);

    // An eight-byte load at the last four bytes of the page leaves the
    // page: the helper is called although the page is admitted.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0xFFC;
    try h.add(0x2000, 3, baseDisp(.mov_reg64_mem64, .bits64, .al_ax_eax_rax, 0));
    try h.add(0x2003, 3, baseDisp(.mov_reg32_mem32, .bits32, .cl_cx_ecx_rcx, 0));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.reads);
    // A different page than the admitted one misses.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x1000;
    try h.add(0x2000, 3, baseDisp(.mov_reg32_mem32, .bits32, .cl_cx_ecx_rcx, 0x10));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.reads);
}

test "the TLB admits, looks up and invalidates by page" {
    var tlb = Tlb.empty;
    var bytes: [8192]u8 align(4096) = undefined;
    tlb.fill(false, 0x1_0000_0000, &bytes);
    tlb.fill(true, 0x1_0000_1000, bytes[4096..].ptr);
    try testing.expectEqual(@intFromPtr(&bytes) + 0x123, @intFromPtr(tlb.lookup(false, 0x1_0000_0123).?));
    try testing.expect(tlb.lookup(true, 0x1_0000_0123) == null);
    try testing.expectEqual(@intFromPtr(&bytes) + 4096 + 8, @intFromPtr(tlb.lookup(true, 0x1_0000_1008).?));
    // An aliasing page (same index, other tag) misses rather than lies.
    try testing.expect(tlb.lookup(false, 0x1_0040_0123) == null);
    tlb.invalidateRange(0x1_0000_0800, 0x10);
    try testing.expect(tlb.lookup(false, 0x1_0000_0123) == null);
    try testing.expect(tlb.lookup(true, 0x1_0000_1008) != null);
    tlb.invalidateRange(0, std.math.maxInt(u64));
    try testing.expect(tlb.lookup(true, 0x1_0000_1008) == null);
    tlb.fill(false, 0x2000, &bytes);
    tlb.flush(false, true);
    try testing.expect(tlb.lookup(false, 0x2004) != null);
    tlb.flush(true, false);
    try testing.expect(tlb.lookup(false, 0x2004) == null);
}

test "ordered scalar TLB accesses preserve aligned and unaligned guest values" {
    var h = try TestHarness.init();
    defer h.deinit();
    const cases = [_]struct { size: Size, store: Op, load: Op, mask: u64 }{
        .{ .size = .bits8, .store = .mov_mem8_reg8, .load = .mov_reg8_mem8, .mask = 0xFF },
        .{ .size = .bits16, .store = .mov_mem16_reg16, .load = .mov_reg16_mem16, .mask = 0xFFFF },
        .{ .size = .bits32, .store = .mov_mem32_reg32, .load = .mov_reg32_mem32, .mask = 0xFFFF_FFFF },
        .{ .size = .bits64, .store = .mov_mem64_reg64, .load = .mov_reg64_mem64, .mask = std.math.maxInt(u64) },
    };
    for (cases) |case| {
        for ([_]u64{ 0, 1 }) |misalignment| {
            var state = TestState{};
            state.admitMemory(true, true);
            const backing_alignment: u64 = @intCast(@intFromPtr(&state.memory) & 7);
            const offset: u64 = 0x100 + ((8 - backing_alignment) & 7) + misalignment;
            state.regs.rbx = offset;
            state.regs.rcx = 0x8877_6655_4433_2211;
            h.insns.clearRetainingCapacity();
            try h.add(0x1000, 3, baseDisp(case.store, case.size, .cl_cx_ecx_rcx, 0));
            try h.add(0x1003, 3, baseDisp(case.load, case.size, .al_ax_eax_rax, 0));
            try testing.expectEqual(@as(u32, 2), try h.run(&state));
            const helper_accesses: u32 = 0;
            try testing.expectEqual(helper_accesses, state.reads);
            try testing.expectEqual(helper_accesses, state.writes);
            try testing.expectEqual(state.regs.rcx & case.mask, state.regs.rax & case.mask);

            // A single operand cannot share a hoisted translation with
            // another instruction, so this also exercises the ordinary
            // per-access TLB probe.
            h.insns.clearRetainingCapacity();
            state.regs.rax = 0;
            try h.add(0x2000, 3, baseDisp(case.load, case.size, .al_ax_eax_rax, 0));
            try testing.expectEqual(@as(u32, 1), try h.run(&state));
            try testing.expectEqual(helper_accesses * 2, state.reads);
            try testing.expectEqual(helper_accesses, state.writes);
            try testing.expectEqual(state.regs.rcx & case.mask, state.regs.rax & case.mask);
        }
    }
}

test "ordered vector TLB accesses keep every alignment in the admitted page" {
    var h = try TestHarness.init();
    defer h.deinit();
    for (0..8) |misalignment| {
        for ([_]bool{ false, true }) |hoisted| {
            for ([_]bool{ false, true }) |admitted| {
                var state = TestState{};
                state.admitMemory(admitted, admitted);
                state.regs.rbx = 0x100 + misalignment;
                state.regs.rflags = 0x8D5;
                @memset(&state.memory, 0xA5);
                for (0..16) |i| state.memory[0x100 + misalignment + i] = @intCast(0x20 + i);
                h.insns.clearRetainingCapacity();
                var load = baseDisp(.vmovdqu_xmm_mem, .bits64, .al_ax_eax_rax, 0);
                load.xmm_dst = 3;
                try h.add(0x1000, 5, load);
                if (hoisted) {
                    var store = baseDisp(.vmovdqu_mem_xmm, .bits64, .al_ax_eax_rax, 0x80);
                    store.xmm_src = 3;
                    try h.add(0x1005, 5, store);
                }
                _ = try h.run(&state);
                try testing.expectEqual(@as(u32, 0x8D5), state.regs.rflags);
                var expected: [16]u8 = undefined;
                for (&expected, 0..) |*byte, i| byte.* = @intCast(0x20 + i);
                try testing.expectEqualSlices(u8, &expected, &state.xmm[3]);
                if (hoisted) {
                    try testing.expectEqualSlices(u8, &expected, state.memory[0x180 + misalignment ..][0..16]);
                    try testing.expectEqual(@as(u8, 0xA5), state.memory[0x17F + misalignment]);
                    try testing.expectEqual(@as(u8, 0xA5), state.memory[0x190 + misalignment]);
                }
                if (admitted) {
                    try testing.expectEqual(@as(u32, 0), state.reads);
                    try testing.expectEqual(@as(u32, 0), state.writes);
                } else {
                    try testing.expectEqual(@as(u32, 1), state.reads);
                    try testing.expectEqual(@as(u32, @intFromBool(hoisted)), state.writes);
                }
            }
        }
    }
}

test "ordered vector TLB wide operands respect page boundaries and write admission" {
    var h = try TestHarness.init();
    defer h.deinit();
    for ([_]u64{ 0x104, 0x101, 0xFF0, 0xFF8 }) |address| {
        var state = TestState{};
        state.admitMemory(true, false);
        state.regs.rbx = address;
        state.regs.rflags = 0x8D5;
        @memset(&state.memory, 0x5A);
        var load = baseDisp(.vmovdqu_ymm_mem, .bits64, .al_ax_eax_rax, 0);
        load.xmm_dst = 3;
        load.vector_256 = true;
        h.insns.clearRetainingCapacity();
        try h.add(0x1000, 5, load);
        _ = try h.run(&state);
        const lower_valid = address + 16 <= state.memory.len;
        const upper_valid = address + 32 <= state.memory.len;
        try testing.expectEqualSlices(u8, &(@as([16]u8, @splat(if (lower_valid) 0x5A else 0))), &state.xmm[3]);
        try testing.expectEqualSlices(u8, &(@as([16]u8, @splat(if (upper_valid) 0x5A else 0))), &state.ymm_hi[3]);
        try testing.expectEqual(@as(u32, @intFromBool(!lower_valid) + @as(u32, @intFromBool(!upper_valid))), state.reads);
        try testing.expectEqual(@as(u32, 0x8D5), state.regs.rflags);
        if (upper_valid) {
            // Read admission must never grant a write to the same page.
            h.insns.clearRetainingCapacity();
            var store = baseDisp(.vmovdqu_mem_ymm, .bits64, .al_ax_eax_rax, 0x80);
            store.vector_256 = true;
            store.xmm_src = 3;
            try h.add(0x2000, 5, store);
            _ = try h.run(&state);
            try testing.expectEqual(@as(u32, 2), state.writes);
            try testing.expectEqualSlices(u8, &(@as([32]u8, @splat(0x5A))), state.memory[@intCast(address + 0x80)..][0..32]);
        }
    }
}

test "ordered vector TLB benchmark (ROSETTE_VECTOR_BENCH=1)" {
    if (std.c.getenv("ROSETTE_VECTOR_BENCH") == null) return error.SkipZigTest;
    var h = try TestHarness.init();
    defer h.deinit();
    // Tiny helpers are a deliberately cheap reference. This measures the
    // memory template, not Halo FPS or production memory-helper overhead.
    for ([_]u64{ 0, 4, 1 }) |alignment| {
        for ([_]bool{ false, true }) |admitted| {
            var state = TestState{};
            state.admitMemory(admitted, admitted);
            state.regs.rbx = 0x100 + alignment;
            @memset(&state.memory, 0x5A);
            h.insns.clearRetainingCapacity();
            for (0..4) |i| {
                var load = baseDisp(.vmovdqu_xmm_mem, .bits64, .al_ax_eax_rax, i * 16);
                load.xmm_dst = 3;
                var store = baseDisp(.vmovdqu_mem_xmm, .bits64, .al_ax_eax_rax, 0x80 + i * 16);
                store.xmm_src = 3;
                try h.add(0x1000 + i * 10, 5, load);
                try h.add(0x1005 + i * 10, 5, store);
            }
            _ = try h.run(&state);
            var best: u64 = std.math.maxInt(u64);
            const iterations = 100_000;
            for (0..3) |_| {
                var start: std.c.timespec = undefined;
                var finish: std.c.timespec = undefined;
                try testing.expectEqual(@as(c_int, 0), std.c.clock_gettime(.MONOTONIC, &start));
                for (0..iterations) |_| _ = h.block.entry()(&state, &h.block.helpers, &state.scratch);
                try testing.expectEqual(@as(c_int, 0), std.c.clock_gettime(.MONOTONIC, &finish));
                const elapsed: u64 = @intCast((finish.sec - start.sec) * std.time.ns_per_s + finish.nsec - start.nsec);
                best = @min(best, elapsed);
            }
            std.debug.print("VECTOR TEMPLATE BENCH: alignment={d} admitted={} ns_per_128bit_access={d:.2} helpers={d}\n", .{ alignment, admitted, @as(f64, @floatFromInt(best)) / (iterations * 8), state.reads + state.writes });
            try testing.expectEqualSlices(u8, state.memory[0x100 + alignment ..][0..64], state.memory[0x180 + alignment ..][0..64]);
        }
    }
}

test "flag computation is elided only for writers no reader can observe" {
    var h = try TestHarness.init();
    defer h.deinit();
    // add rax, rbx ; add rcx, rdx: the first writer's flags are dead.
    var state = TestState{};
    state.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rbx = 1;
    state.regs.rcx = 5;
    state.regs.rdx = 3;
    state.regs.rflags = 0x2;
    try h.add(0x1000, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x1003, 3, regReg(.add_reg64_reg64, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), h.flags_elided);
    var expected: u32 = 0x2;
    _ = referenceBinary(.add, .bits64, 5, 3, &expected);
    try testing.expectEqual(expected, state.regs.rflags);
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u64, 8), state.regs.rcx);

    // A fallback between them reads every flag: nothing is elided, and the
    // interpret helper sees the first add's flags (CF, ZF, PF, AF).
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rbx = 1;
    state.regs.rflags = 0x2;
    try h.add(0x1000, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x1003, 1, .{ .op = .lahf });
    try h.add(0x1004, 3, regReg(.add_reg64_reg64, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), h.flags_elided);
    expected = 0x2;
    _ = referenceBinary(.add, .bits64, 0xFFFF_FFFF_FFFF_FFFF, 1, &expected);
    try testing.expectEqual(expected, state.flags_at_interpret);

    // inc leaves CF alone, so an add before it keeps its flags (CF is
    // live), while an inc before an add is dead.
    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x1003, 3, .{ .op = .inc_reg64, .size = .bits64, .dst_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    state = TestState{};
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), h.flags_elided);
    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 3, .{ .op = .inc_reg64, .size = .bits64, .dst_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    try h.add(0x1003, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    state = TestState{};
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), h.flags_elided);

    // A conditional branch reads the flags of the writer before it, and a
    // shift by cl may write nothing, so it kills nothing.
    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x1003, 3, .{ .op = .shl_reg_cl, .size = .bits64, .dst_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    try h.add(0x1006, 2, .{ .op = .jcc_rel8, .cond = .e, .addr = 0x10 });
    state = TestState{};
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), h.flags_elided);
}

test "shifts by cl and rotates follow the interpreter's count and flag rules" {
    var h = try TestHarness.init();
    defer h.deinit();
    // shl rax, cl with cl = 1 on 0x8000...1: result 2, CF set, OF set (msb 0 != CF 1).
    var state = TestState{};
    state.regs.rax = 0x8000_0000_0000_0001;
    state.regs.rcx = 0x41; // masked to 1
    state.regs.rflags = 0x2 | RFL_PF;
    try h.add(0x1000, 3, .{ .op = .shl_reg_cl, .size = .bits64, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 2), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_CF != 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);
    try testing.expect(state.regs.rflags & RFL_PF != 0);
    try testing.expect(state.regs.rflags & (RFL_ZF | RFL_SF) == 0);

    // shl eax, cl with a zero count: flags untouched, the register is
    // rewritten at 32 bits (zero-extended).
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0xFFFF_FFFF_0000_0001;
    state.regs.rcx = 0x20; // masked to 0 at 32 bits
    state.regs.rflags = 0x8D5;
    try h.add(0x1000, 2, .{ .op = .shl_reg_cl, .size = .bits32, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u32, 0x8D5), state.regs.rflags);

    // shr edx, cl (31) on 0x80000000: 1, CF = bit 30 = 0, OF untouched.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rdx = 0x8000_0000;
    state.regs.rcx = 31;
    state.regs.rflags = 0x2 | RFL_OF | RFL_CF;
    try h.add(0x1000, 2, .{ .op = .shr_reg_cl, .size = .bits32, .dst_reg = .dl_dx_edx_rdx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 1), state.regs.rdx);
    try testing.expect(state.regs.rflags & RFL_CF == 0);
    try testing.expect(state.regs.rflags & RFL_OF != 0);

    // sar rsi, cl (2) on -8: -2, CF = bit 1 = 0, SF set.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rsi = @bitCast(@as(i64, -8));
    state.regs.rcx = 2;
    state.regs.rflags = 0x2;
    try h.add(0x1000, 3, .{ .op = .sar_reg_cl, .size = .bits64, .dst_reg = .dh_si_esi_rsi, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -2))), state.regs.rsi);
    try testing.expect(state.regs.rflags & RFL_CF == 0);
    try testing.expect(state.regs.rflags & RFL_SF != 0);

    // rol eax, 1 on 0x80000001: 3, CF 1, OF = msb(result) 0 != CF → set.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x8000_0001;
    state.regs.rflags = 0x2;
    try h.add(0x1000, 3, regImm(.rol_reg_imm, .bits32, .al_ax_eax_rax, 1));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 3), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_CF != 0 and state.regs.rflags & RFL_OF != 0);

    // ror rbx, cl (1) on 1: 0x8000..., CF 1, OF = CF != bit 62 → set.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 1;
    state.regs.rcx = 1;
    state.regs.rflags = 0x2;
    try h.add(0x1000, 3, .{ .op = .ror_reg_cl, .size = .bits64, .dst_reg = .bl_bx_ebx_rbx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x8000_0000_0000_0000), state.regs.rbx);
    try testing.expect(state.regs.rflags & RFL_CF != 0 and state.regs.rflags & RFL_OF != 0);

    // rol rbx, 8 on 0x0102...: rotated, CF = low bit of result, OF untouched.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 0x0102_0304_0506_0781;
    state.regs.rflags = 0x2 | RFL_OF;
    try h.add(0x1000, 4, regImm(.rol_reg_imm, .bits64, .bl_bx_ebx_rbx, 8));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x0203_0405_0607_8101), state.regs.rbx);
    try testing.expect(state.regs.rflags & RFL_CF != 0 and state.regs.rflags & RFL_OF != 0);

    // A zero rotate count does nothing, not even a rewrite.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 0xFFFF_FFFF_0000_0001;
    state.regs.rcx = 32;
    state.regs.rflags = 0x8D5;
    try h.add(0x1000, 2, .{ .op = .rol_reg_cl, .size = .bits32, .dst_reg = .bl_bx_ebx_rbx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_0000_0001), state.regs.rbx);
    try testing.expectEqual(@as(u32, 0x8D5), state.regs.rflags);
}

test "narrow cl shifts run natively for in-range counts and guard wide counts" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.regs.rax = 0x80;
    state.regs.rcx = 2;
    state.regs.rflags = 0x2 | RFL_OF | RFL_PF;
    try h.add(0x1000, 2, .{ .op = .shl_reg_cl, .size = .bits8, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_ZF != 0);
    try testing.expect(state.regs.rflags & (RFL_CF | RFL_SF) == 0);
    try testing.expect(state.regs.rflags & (RFL_OF | RFL_PF) == (RFL_OF | RFL_PF));
    try testing.expectEqual(@as(u32, 0), state.interprets);

    // `sar ax, cl` sign-extends the 16-bit value before the host shift.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x8000;
    state.regs.rcx = 3;
    try h.add(0x1000, 3, .{ .op = .sar_reg_cl, .size = .bits16, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xF000), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_SF != 0);
    try testing.expectEqual(@as(u32, 0), state.interprets);

    // A masked count at or beyond an 8-bit operand's width takes the
    // interpreter escape, which owns the model's undefined-flag behavior.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x80;
    state.regs.rcx = 8;
    try h.add(0x1000, 2, .{ .op = .shl_reg_cl, .size = .bits8, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.interprets);
}

test "memory shifts by cl use guarded native loads and writes" {
    var h = try TestHarness.init();
    defer h.deinit();
    try h.add(0x1000, 5, .{ .op = .shl_mem_cl, .size = .bits64, .addr = 0x120 });

    for ([_]bool{ true, false }) |admitted| {
        var state = TestState{};
        if (admitted) state.admitMemory(true, true);
        state.regs.rcx = 0x41; // masked to one for a 64-bit operand
        state.regs.rflags = 0x2 | RFL_PF;
        std.mem.writeInt(u64, state.memory[0x120..][0..8], 0x8000_0000_0000_0001, .little);
        _ = try h.run(&state);

        try testing.expectEqual(@as(u64, 2), std.mem.readInt(u64, state.memory[0x120..][0..8], .little));
        try testing.expect(state.regs.rflags & (RFL_CF | RFL_OF) == (RFL_CF | RFL_OF));
        try testing.expect(state.regs.rflags & (RFL_ZF | RFL_SF) == 0);
        try testing.expect(state.regs.rflags & RFL_PF != 0);
        try testing.expectEqual(@as(u32, 0), state.interprets);
    }

    // A zero count reads the memory operand but leaves both the bytes and
    // every arithmetic flag untouched.
    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 5, .{ .op = .shl_mem_cl, .size = .bits64, .addr = 0x120 });
    var zero_state = TestState{};
    zero_state.admitMemory(true, true);
    zero_state.regs.rcx = 0x40;
    zero_state.regs.rflags = 0x8D5;
    std.mem.writeInt(u64, zero_state.memory[0x120..][0..8], 0x8000_0000_0000_0001, .little);
    _ = try h.run(&zero_state);
    try testing.expectEqual(@as(u64, 0x8000_0000_0000_0001), std.mem.readInt(u64, zero_state.memory[0x120..][0..8], .little));
    try testing.expectEqual(@as(u32, 0x8D5), zero_state.regs.rflags);

    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 4, .{ .op = .shr_mem_cl, .size = .bits32, .addr = 0x120 });
    var shr_state = TestState{};
    shr_state.admitMemory(true, true);
    shr_state.regs.rcx = 1;
    shr_state.regs.rflags = 0x2;
    std.mem.writeInt(u32, shr_state.memory[0x120..][0..4], 0x8000_0001, .little);
    _ = try h.run(&shr_state);
    try testing.expectEqual(@as(u32, 0x4000_0000), std.mem.readInt(u32, shr_state.memory[0x120..][0..4], .little));
    try testing.expect(shr_state.regs.rflags & (RFL_CF | RFL_OF) == (RFL_CF | RFL_OF));
    try testing.expectEqual(@as(u32, 0), shr_state.interprets);

    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 4, .{ .op = .sar_mem_cl, .size = .bits64, .addr = 0x120 });
    var sar_state = TestState{};
    sar_state.admitMemory(true, true);
    sar_state.regs.rcx = 2;
    sar_state.regs.rflags = 0x2 | RFL_OF;
    std.mem.writeInt(u64, sar_state.memory[0x120..][0..8], @bitCast(@as(i64, -8)), .little);
    _ = try h.run(&sar_state);
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -2))), std.mem.readInt(u64, sar_state.memory[0x120..][0..8], .little));
    try testing.expect(sar_state.regs.rflags & RFL_CF == 0);
    try testing.expect(sar_state.regs.rflags & RFL_SF != 0);
    try testing.expect(sar_state.regs.rflags & RFL_OF != 0);
    try testing.expectEqual(@as(u32, 0), sar_state.interprets);
}

test "bit tests, bit scans and zero counts follow bit_test and cpu.bitScan" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.regs.rax = 0x20;
    state.regs.r8 = 0;
    state.regs.r9 = 65; // bit 1 modulo 64
    state.regs.rcx = 0xF;
    state.regs.rflags = 0x2;
    // bt eax, 5 ; bts r8, r9 ; btr rcx, 3
    try h.add(0x1000, 4, regImm(.bt_reg_imm, .bits32, .al_ax_eax_rax, 5));
    try h.add(0x1004, 4, regReg(.bts_reg_reg, .bits64, .r8b_r8w_r8d_r8, .r9b_r9w_r9d_r9));
    try h.add(0x1008, 4, regImm(.btr_reg_imm, .bits64, .cl_cx_ecx_rcx, 3));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 2), state.regs.r8);
    try testing.expectEqual(@as(u64, 7), state.regs.rcx);
    try testing.expect(state.regs.rflags & RFL_CF != 0); // the last one: bit 3 of 0xF
    // bt alone reports CF and writes nothing.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x20;
    state.regs.rflags = 0x2 | RFL_CF;
    try h.add(0x1000, 4, regImm(.bt_reg_imm, .bits32, .al_ax_eax_rax, 4));
    _ = try h.run(&state);
    try testing.expect(state.regs.rflags & RFL_CF == 0);
    try testing.expectEqual(@as(u64, 0x20), state.regs.rax);

    // bsf eax, ebx (0x100) → 8, ZF clear; bsf with zero → destination kept, ZF set.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0x1111;
    state.regs.rbx = 0x100;
    state.regs.rflags = 0x2 | RFL_ZF;
    try h.add(0x1000, 3, regReg(.bsf_reg_reg, .bits32, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 8), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_ZF == 0);
    state = TestState{};
    state.regs.rax = 0x1111;
    state.regs.rbx = 0;
    state.regs.rflags = 0x2;
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x1111), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_ZF != 0);
    // bsr rcx, rdx (top bit) → 63; bsr ax, bx (0x400) → 10.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rdx = 0x8000_0000_0000_0000;
    state.regs.rbx = 0x0400;
    try h.add(0x1000, 4, regReg(.bsr_reg_reg, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx));
    try h.add(0x1004, 4, regReg(.bsr_reg_reg, .bits16, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 63), state.regs.rcx);
    try testing.expectEqual(@as(u64, 10), state.regs.rax);

    // tzcnt eax, ebx (0) → 32, CF set, ZF clear; lzcnt rcx, rdx (1) → 63.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 0;
    state.regs.rdx = 1;
    try h.add(0x1000, 4, regReg(.tzcnt_reg_reg, .bits32, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 32), state.regs.rax);
    try testing.expect(state.regs.rflags & RFL_CF != 0 and state.regs.rflags & RFL_ZF == 0);
    h.insns.clearRetainingCapacity();
    try h.add(0x1000, 5, regReg(.lzcnt_reg_reg, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 63), state.regs.rcx);
    try testing.expect(state.regs.rflags & (RFL_CF | RFL_ZF) == 0);
    // tzcnt of 1 → 0: ZF set, CF clear.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rdx = 1;
    try h.add(0x1000, 5, regReg(.tzcnt_reg_reg, .bits64, .cl_cx_ecx_rcx, .dl_dx_edx_rdx));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0), state.regs.rcx);
    try testing.expect(state.regs.rflags & RFL_ZF != 0 and state.regs.rflags & RFL_CF == 0);
}

test "native byte multiply and population count match x86 register semantics" {
    var h = try TestHarness.init();
    defer h.deinit();

    // MUL r/m8 writes the product to AX and sets CF/OF iff the high byte is
    // nonzero. All other status bits remain unchanged.
    var multiply = TestState{};
    multiply.regs.rax = 0x1122_3344_5566_77FF;
    multiply.regs.rcx = 0xAABB_CCDD_EEFF_FFFF;
    multiply.regs.rflags = 0x2 | 0x600 | RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF;
    try h.add(0x1000, 2, regReg(.mul_reg8, .bits8, .cl_cx_ecx_rcx, .cl_cx_ecx_rcx));
    _ = try h.run(&multiply);
    try testing.expectEqual(@as(u64, 0x1122_3344_5566_FE01), multiply.regs.rax);
    try testing.expectEqual(@as(u64, (0x2 | 0x600 | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_CF | RFL_OF)), multiply.regs.rflags);
    try testing.expectEqual(@as(u32, 0), multiply.interprets);

    h.insns.clearRetainingCapacity();
    var no_overflow = TestState{};
    no_overflow.regs.rax = 0x1122_3344_5566_7703;
    no_overflow.regs.rcx = 4;
    no_overflow.regs.rflags = 0x2 | 0x600 | RFL_CF | RFL_OF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF;
    try h.add(0x1000, 2, regReg(.mul_reg8, .bits8, .cl_cx_ecx_rcx, .cl_cx_ecx_rcx));
    _ = try h.run(&no_overflow);
    try testing.expectEqual(@as(u64, 0x1122_3344_5566_000C), no_overflow.regs.rax);
    try testing.expectEqual(@as(u64, 0x2 | 0x600 | RFL_PF | RFL_AF | RFL_ZF | RFL_SF), no_overflow.regs.rflags);
    try testing.expectEqual(@as(u32, 0), no_overflow.interprets);

    // POPCNT zero-extends its input width, preserves upper destination bits
    // for a word result, and clears all six arithmetic status flags except
    // for ZF, which reports whether the source is zero.
    const popcnt_cases = [_]struct { size: Size, source: u64 }{
        .{ .size = .bits16, .source = 0xA5A5 },
        .{ .size = .bits32, .source = 0xF0F0_1234 },
        .{ .size = .bits64, .source = 0xF0F0_F0F0_1234_5678 },
        .{ .size = .bits64, .source = 0 },
    };
    const status_flags = RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF;
    for (popcnt_cases) |case| {
        h.insns.clearRetainingCapacity();
        var state = TestState{};
        state.regs.rbx = 0x1122_3344_5566_7788;
        state.regs.rcx = case.source;
        state.regs.rflags = 0x2 | 0x600 | status_flags;
        try h.add(0x2000, 4, regReg(.popcnt_reg_reg, case.size, .bl_bx_ebx_rbx, .cl_cx_ecx_rcx));
        _ = try h.run(&state);

        const expected_count: u64 = @popCount(case.source & maskFor(case.size));
        const expected_destination = switch (case.size) {
            .bits16 => (0x1122_3344_5566_7788 & ~@as(u64, 0xFFFF)) | expected_count,
            .bits32 => expected_count,
            .bits64 => expected_count,
            .bits8 => unreachable,
        };
        try testing.expectEqual(expected_destination, state.regs.rbx);
        const expected_flags = (0x2 | 0x600) | (if ((case.source & maskFor(case.size)) == 0) RFL_ZF else 0);
        try testing.expectEqual(@as(u64, expected_flags), state.regs.rflags);
        try testing.expectEqual(@as(u32, 0), state.interprets);
    }
}

test "adc and sbb produce highway.addCarry and subBorrow's results at every width" {
    var h = try TestHarness.init();
    defer h.deinit();
    var prng = std.Random.DefaultPrng.init(0xADC_5BB);
    const random = prng.random();
    const forms = [_]struct { op: Op, size: Size, adc: bool }{
        .{ .op = .adc_reg64_reg64, .size = .bits64, .adc = true },
        .{ .op = .adc_reg32_reg32, .size = .bits32, .adc = true },
        .{ .op = .adc_reg16_reg16, .size = .bits16, .adc = true },
        .{ .op = .adc_reg8_reg8, .size = .bits8, .adc = true },
        .{ .op = .sbb_reg64_reg64, .size = .bits64, .adc = false },
        .{ .op = .sbb_reg32_reg32, .size = .bits32, .adc = false },
        .{ .op = .sbb_reg16_reg16, .size = .bits16, .adc = false },
        .{ .op = .sbb_reg8_reg8, .size = .bits8, .adc = false },
    };
    for (forms) |form| {
        for (0..48) |_| {
            var state = TestState{};
            const a = switch (random.uintLessThan(u8, 3)) {
                0 => random.int(u64),
                1 => maskFor(form.size),
                else => random.int(u8),
            };
            const b = switch (random.uintLessThan(u8, 3)) {
                0 => random.int(u64),
                1 => maskFor(form.size),
                else => 0,
            };
            state.regs.rsi = a;
            state.regs.rdi = b;
            state.regs.rflags = (random.int(u32) & 0xFFF) | 0x2;
            const width: x64_decoder.highway.Width = switch (form.size) {
                .bits8 => .bits8,
                .bits16 => .bits16,
                .bits32 => .bits32,
                .bits64 => .bits64,
            };
            const reference = x64_decoder.highway.evaluate(if (form.adc) .adc else .sbb, width, a & maskFor(form.size), b & maskFor(form.size), state.regs.rflags);
            h.insns.clearRetainingCapacity();
            try h.add(0x2000, 3, regReg(form.op, form.size, .dh_si_esi_rsi, .bh_di_edi_rdi));
            _ = try h.run(&state);
            try testing.expectEqual(reference.rflags, state.regs.rflags);
            const expected_reg: u64 = switch (form.size) {
                .bits64, .bits32 => reference.value,
                .bits16 => (a & ~@as(u64, 0xFFFF)) | reference.value,
                .bits8 => (a & ~@as(u64, 0xFF)) | reference.value,
            };
            try testing.expectEqual(expected_reg, state.regs.rsi);
        }
    }
}

test "256-bit moves carry both halves and leave the upper one alone" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.regs.rbx = 0x100;
    for (0..16) |byte| {
        state.memory[0x120 + byte] = @intCast(0x10 + byte);
        state.memory[0x130 + byte] = @intCast(0xA0 + byte);
    }
    // A 256-bit load fills the low half from the operand and the upper half
    // from sixteen bytes further along - and must not clear the upper half
    // the way every VEX.128 write does.
    var load = vecMem(.vmovdqa_ymm_mem, 3, 0, 0x20);
    load.vector_256 = true;
    try h.add(0x9000, 7, load);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u8, 0x10), state.xmm[3][0]);
    try testing.expectEqual(@as(u8, 0x1F), state.xmm[3][15]);
    try testing.expectEqual(@as(u8, 0xA0), state.ymm_hi[3][0]);
    try testing.expectEqual(@as(u8, 0xAF), state.ymm_hi[3][15]);
    // Both halves came from memory, so both reached the store helper.
    try testing.expectEqual(@as(u32, 2), state.reads);

    // A 256-bit store writes both halves back, sixteen bytes apart.
    h.insns.clearRetainingCapacity();
    state.reads = 0;
    state.writes = 0;
    for (0..16) |byte| {
        state.xmm[5][byte] = @intCast(0x40 + byte);
        state.ymm_hi[5][byte] = @intCast(0x80 + byte);
    }
    var store = vecMem(.vmovdqa_mem_ymm, 0, 5, 0x40);
    store.vector_256 = true;
    try h.add(0x9100, 7, store);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u8, 0x40), state.memory[0x140]);
    try testing.expectEqual(@as(u8, 0x4F), state.memory[0x14F]);
    try testing.expectEqual(@as(u8, 0x80), state.memory[0x150]);
    try testing.expectEqual(@as(u8, 0x8F), state.memory[0x15F]);
    try testing.expectEqual(@as(u32, 2), state.writes);

    // Register to register moves both halves and asks the interpreter for
    // nothing.
    h.insns.clearRetainingCapacity();
    state.interprets = 0;
    var move: DecodedInsn = .{ .op = .vmovdqa_ymm_ymm, .size = .bits32, .xmm_dst = 9, .xmm_src = 5, .is_reg_form = true };
    move.vector_256 = true;
    try h.add(0x9200, 4, move);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u8, 0x40), state.xmm[9][0]);
    try testing.expectEqual(@as(u8, 0x80), state.ymm_hi[9][0]);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "256-bit vector support is limited to implemented lane templates" {
    var arithmetic: DecodedInsn = .{ .op = .vpaddd, .size = .bits32, .xmm_dst = 1, .xmm_src = 2, .xmm_src2 = 3, .is_reg_form = true };
    arithmetic.vector_256 = true;
    try testing.expect(!isVectorNative(arithmetic));
    var narrow = arithmetic;
    narrow.vector_256 = false;
    try testing.expect(isVectorNative(narrow));
    arithmetic.op = .vmulpd;
    try testing.expect(isVectorNative(arithmetic));
    arithmetic.op = .vxorps;
    try testing.expect(isVectorNative(arithmetic));
    arithmetic.op = .vptest;
    try testing.expect(isVectorNative(arithmetic));
    arithmetic.op = .vextractf128;
    try testing.expect(isVectorNative(arithmetic));
}

test "256-bit packed float and bitwise instructions update both halves" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.xmm[1] = doubles64(.{ 2.0, 3.0 });
    state.ymm_hi[1] = doubles64(.{ 6.0, 7.0 });
    state.xmm[2] = doubles64(.{ 4.0, 5.0 });
    state.ymm_hi[2] = doubles64(.{ 8.0, 9.0 });
    var mul: DecodedInsn = .{ .op = .vmulpd, .size = .bits32, .xmm_dst = 4, .xmm_src = 1, .xmm_src2 = 2, .is_reg_form = true };
    mul.vector_256 = true;
    try h.add(0x1000, 4, mul);
    _ = try h.run(&state);
    try testing.expectEqualSlices(u8, &doubles64(.{ 8.0, 15.0 }), &state.xmm[4]);
    try testing.expectEqualSlices(u8, &doubles64(.{ 48.0, 63.0 }), &state.ymm_hi[4]);

    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.xmm[1] = @splat(0xAA);
    state.ymm_hi[1] = @splat(0x5A);
    state.xmm[2] = @splat(0x0F);
    state.ymm_hi[2] = @splat(0xF0);
    var xor: DecodedInsn = .{ .op = .vxorps, .size = .bits32, .xmm_dst = 3, .xmm_src = 1, .xmm_src2 = 2, .is_reg_form = true };
    xor.vector_256 = true;
    try h.add(0x1000, 4, xor);
    _ = try h.run(&state);
    try testing.expectEqualSlices(u8, &([_]u8{0xA5} ** 16), &state.xmm[3]);
    try testing.expectEqualSlices(u8, &([_]u8{0xAA} ** 16), &state.ymm_hi[3]);
}

test "vptest reduces both YMM halves and writes only its defined flags" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.xmm[1] = @splat(0xFF);
    state.xmm[2] = @splat(0x0F);
    state.ymm_hi[1] = @splat(0x00);
    state.ymm_hi[2] = @splat(0x01);
    state.regs.rflags = 0x2 | RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF;
    var test_vec: DecodedInsn = .{ .op = .vptest, .size = .bits32, .xmm_src = 1, .xmm_src2 = 2, .is_reg_form = true };
    test_vec.vector_256 = true;
    try h.add(0x1000, 4, test_vec);
    _ = try h.run(&state);
    try testing.expect(state.regs.rflags & (RFL_CF | RFL_ZF) == 0);
    try testing.expect(state.regs.rflags & (RFL_PF | RFL_AF | RFL_SF | RFL_OF) == 0);

    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rflags = 0x2;
    test_vec.vector_256 = false;
    test_vec.op = .vtestps;
    try h.add(0x1000, 4, test_vec);
    _ = try h.run(&state);
    try testing.expect(state.regs.rflags & (RFL_CF | RFL_ZF) == (RFL_CF | RFL_ZF));
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "VTEST sign flags agree with x86 for payloads, both halves and memory" {
    var h = try TestHarness.init();
    defer h.deinit();
    for ([_]Op{ .vptest, .vtestps, .vtestpd }) |op| {
        for ([_]bool{ false, true }) |wide| {
            for ([_]bool{ false, true }) |memory| {
                for (0..3) |case| {
                    var state = TestState{};
                    state.admitMemory(true, true);
                    state.regs.rbx = 0x100;
                    state.regs.rflags = 0x202 | RFL_CF | RFL_ZF | RFL_OF | RFL_SF | RFL_AF | RFL_PF;
                    // All payload bits are nonzero, with initially no sign bit.
                    state.xmm[1] = @splat(1);
                    state.xmm[2] = @splat(1);
                    state.ymm_hi[1] = @splat(1);
                    state.ymm_hi[2] = @splat(1);
                    const sign_byte: usize = if (op == .vtestpd) 7 else 3;
                    const lhs = if (wide) &state.ymm_hi[1] else &state.xmm[1];
                    const rhs = if (wide) &state.ymm_hi[2] else &state.xmm[2];
                    if (case != 0) rhs[sign_byte] = 0x81;
                    if (case == 2) lhs[sign_byte] = 0x81;
                    @memcpy(state.memory[0x100..0x110], &state.xmm[2]);
                    @memcpy(state.memory[0x110..0x120], &state.ymm_hi[2]);
                    var d = DecodedInsn{ .op = op, .size = .bits32, .xmm_src = 1, .xmm_src2 = 2, .is_reg_form = !memory, .vector_256 = wide };
                    if (memory) {
                        d.sib_has_base = true;
                        d.sib_base_reg = .bl_bx_ebx_rbx;
                    }
                    h.insns.clearRetainingCapacity();
                    try h.add(0x1000, 5, d);
                    _ = try h.run(&state);
                    const expected_zf = op != .vptest and case != 2;
                    const expected_cf = case != 1;
                    const expected: u32 = 0x202 | (if (expected_zf) RFL_ZF else @as(u32, 0)) | (if (expected_cf) RFL_CF else @as(u32, 0));
                    try testing.expectEqual(expected, state.regs.rflags);
                    try testing.expectEqual(@as(u32, 0), state.interprets);
                }
            }
        }
    }
}

test "vextractf128 selects the upper lane for register and memory destinations" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.xmm[1] = lanes32(.{ 1, 2, 3, 4 });
    state.ymm_hi[1] = lanes32(.{ 5, 6, 7, 8 });
    var reg_extract = vecRegs(.vextractf128, 4, 1, 0);
    reg_extract.vector_256 = true;
    reg_extract.imm = 1;
    try h.add(0x1000, 5, reg_extract);
    _ = try h.run(&state);
    try testing.expectEqualSlices(u8, &lanes32(.{ 5, 6, 7, 8 }), &state.xmm[4]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[4]);

    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rbx = 0x100;
    state.ymm_hi[1] = lanes32(.{ 9, 10, 11, 12 });
    var mem_extract = vecMem(.vextractf128, 0, 1, 0x20);
    mem_extract.vector_256 = true;
    mem_extract.imm = 1;
    try h.add(0x1000, 6, mem_extract);
    _ = try h.run(&state);
    try testing.expectEqualSlices(u8, &lanes32(.{ 9, 10, 11, 12 }), state.memory[0x120..0x130]);
    try testing.expectEqual(@as(u32, 1), state.writes);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "movbe, xchg, one-operand multiply and guarded divide" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rcx = 0x1122_3344_5566_7788;
    state.memory[0x100] = 0x01;
    state.memory[0x101] = 0x02;
    state.memory[0x102] = 0x03;
    state.memory[0x103] = 0x04;
    // movbe eax, [rbx] ; movbe [rbx + 8], rcx ; movbe dx, [rbx]
    try h.add(0x1000, 4, baseDisp(.movbe_reg_mem, .bits32, .al_ax_eax_rax, 0));
    try h.add(0x1004, 5, baseDisp(.movbe_mem_reg, .bits64, .cl_cx_ecx_rcx, 8));
    try h.add(0x1009, 5, baseDisp(.movbe_reg_mem, .bits16, .dl_dx_edx_rdx, 0));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x0102_0304), state.regs.rax);
    try testing.expectEqualSlices(u8, &.{ 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88 }, state.memory[0x108..0x110]);
    try testing.expectEqual(@as(u64, 0x0102), state.regs.rdx);

    // xchg rax, rbx ; xchg eax, ecx (accumulator form)
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 1;
    state.regs.rbx = 2;
    state.regs.rcx = 0xFFFF_FFFF_0000_0003;
    try h.add(0x1000, 3, regReg(.xchg_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x1003, 1, .{ .op = .xchg_accum_reg, .size = .bits32, .src_reg = .cl_cx_ecx_rcx });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 3), state.regs.rax);
    try testing.expectEqual(@as(u64, 1), state.regs.rbx);
    try testing.expectEqual(@as(u64, 2), state.regs.rcx);

    // mul rbx: 2^64-1 * 2 = 0x1_FFFF_FFFF_FFFF_FFFE ; imul ebx (-3 * 4).
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rbx = 2;
    try h.add(0x1000, 3, .{ .op = .mul_reg64, .size = .bits64, .src_reg = .bl_bx_ebx_rbx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_FFFF_FFFE), state.regs.rax);
    try testing.expectEqual(@as(u64, 1), state.regs.rdx);
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 0xFFFF_FFFD;
    state.regs.rbx = 4;
    try h.add(0x1000, 2, .{ .op = .imul_reg32, .size = .bits32, .src_reg = .bl_bx_ebx_rbx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0xFFFF_FFF4), state.regs.rax);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF), state.regs.rdx);

    // div ecx (100 / 7) natively; idiv rcx (-100 / 7) natively.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 100;
    state.regs.rdx = 0;
    state.regs.rcx = 7;
    try h.add(0x1000, 2, .{ .op = .div_reg32, .size = .bits32, .src_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 14), state.regs.rax);
    try testing.expectEqual(@as(u64, 2), state.regs.rdx);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = @bitCast(@as(i64, -100));
    state.regs.rdx = @bitCast(@as(i64, -1));
    state.regs.rcx = 7;
    try h.add(0x1000, 3, .{ .op = .idiv_reg64, .size = .bits64, .src_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -14))), state.regs.rax);
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -2))), state.regs.rdx);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    // A high half that would overflow, a zero divisor and a divisor of -1
    // all go to the interpreter.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 100;
    state.regs.rdx = 1;
    state.regs.rcx = 7;
    try h.add(0x1000, 2, .{ .op = .div_reg32, .size = .bits32, .src_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.interprets);
    try testing.expectEqual(@as(u64, 100), state.regs.rax);
    state = TestState{};
    state.regs.rcx = 0;
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.interprets);
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.regs.rax = 5;
    state.regs.rdx = 0;
    state.regs.rcx = 0xFFFF_FFFF;
    try h.add(0x1000, 2, .{ .op = .idiv_reg32, .size = .bits32, .src_reg = .cl_cx_ecx_rcx, .is_reg_form = true });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.interprets);
}

test "Group-1 memory forms, inc/dec/neg/not on memory, imul and cmov from memory" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x200;
    state.regs.rax = 10;
    state.regs.rcx = 0xFFFF_FFFF_FFFF_FFFF;
    std.mem.writeInt(u64, state.memory[0x210..][0..8], 5, .little);
    std.mem.writeInt(u32, state.memory[0x200..][0..4], 3, .little);
    std.mem.writeInt(u32, state.memory[0x204..][0..4], 0xFFFF_FFFF, .little);
    std.mem.writeInt(u64, state.memory[0x208..][0..8], 6, .little);
    state.memory[0x218] = 0x0F;
    std.mem.writeInt(u64, state.memory[0x220..][0..8], 7, .little);
    std.mem.writeInt(u32, state.memory[0x230..][0..4], 99, .little);
    // add [rbx+0x10], rax        → 15
    // sub eax, [rbx]             → 7
    // cmp dword [rbx], 5         → 3 - 5: CF set
    // inc dword [rbx+4]          → 0 (ZF), CF kept from cmp
    // neg qword [rbx+8]          → -6
    // not byte [rbx+0x18]        → 0xF0
    // imul rax, [rbx+0x20]       → 49
    // cmovne ecx, [rbx+0x30]     → ZF was cleared by neg (-6 is nonzero), so the move happens: ecx = 99
    var add_mem = baseDisp(.add_mem64_reg64, .bits64, .al_ax_eax_rax, 0x10);
    add_mem.src_reg = .al_ax_eax_rax;
    try h.add(0x1000, 4, add_mem);
    try h.add(0x1004, 2, baseDisp(.sub_reg32_mem32, .bits32, .al_ax_eax_rax, 0));
    var cmp_imm = baseDisp(.cmp_mem32_imm8, .bits32, .al_ax_eax_rax, 0);
    cmp_imm.imm = 5;
    try h.add(0x1006, 3, cmp_imm);
    try h.add(0x1009, 3, baseDisp(.inc_mem32, .bits32, .al_ax_eax_rax, 4));
    try h.add(0x100C, 4, baseDisp(.neg_mem64, .bits64, .al_ax_eax_rax, 8));
    try h.add(0x1010, 3, baseDisp(.not_mem8, .bits8, .al_ax_eax_rax, 0x18));
    try h.add(0x1013, 5, baseDisp(.imul_reg64_mem64, .bits64, .al_ax_eax_rax, 0x20));
    var cmov = baseDisp(.cmovcc_reg_mem, .bits32, .cl_cx_ecx_rcx, 0x30);
    cmov.cond = .ne;
    try h.add(0x1018, 4, cmov);
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 8), completed);
    try testing.expectEqual(@as(u64, 15), std.mem.readInt(u64, state.memory[0x210..][0..8], .little));
    try testing.expectEqual(@as(u64, 49), state.regs.rax);
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, state.memory[0x204..][0..4], .little));
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -6))), std.mem.readInt(u64, state.memory[0x208..][0..8], .little));
    try testing.expectEqual(@as(u8, 0xF0), state.memory[0x218]);
    try testing.expectEqual(@as(u64, 99), state.regs.rcx);
    try testing.expect(state.regs.rflags & RFL_ZF == 0);
    try testing.expect(state.regs.rflags & (RFL_CF | RFL_OF) == 0); // imul's product fits
    try testing.expectEqual(@as(u32, 0), state.reads + state.writes);
}

fn vecRegs(op: Op, dst: u8, src: u8, src2: u8) DecodedInsn {
    return .{ .op = op, .size = .bits32, .xmm_dst = dst, .xmm_src = src, .xmm_src2 = src2, .is_reg_form = true };
}

fn vecMem(op: Op, dst: u8, src: u8, disp: u64) DecodedInsn {
    return .{ .op = op, .size = .bits32, .xmm_dst = dst, .xmm_src = src, .addr = disp, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx };
}

fn lanes32(values: [4]u32) [16]u8 {
    var bytes: [16]u8 = undefined;
    for (values, 0..) |value, lane| std.mem.writeInt(u32, bytes[lane * 4 ..][0..4], value, .little);
    return bytes;
}

fn floats32(values: [4]f32) [16]u8 {
    var bytes: [16]u8 = undefined;
    for (values, 0..) |value, lane| std.mem.writeInt(u32, bytes[lane * 4 ..][0..4], @bitCast(value), .little);
    return bytes;
}

test "vector moves, logic and integer arithmetic follow the lane rules and clear the upper halves" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    const a = lanes32(.{ 0x0000_0001, 0x8000_0000, 0xFFFF_FFFF, 0x1234_5678 });
    const b = lanes32(.{ 0x0000_0002, 0x7FFF_FFFF, 0x0000_0001, 0x1234_5678 });
    state.xmm[1] = a;
    state.xmm[2] = b;
    state.ymm_hi[0] = @splat(0xAA);
    state.ymm_hi[3] = @splat(0xAA);
    state.zmm_hi[0] = @splat(0xBB);
    state.zmm_hi[3] = @splat(0xBB);
    // vmovaps xmm0, xmm1 ; vpxor xmm3, xmm1, xmm2 ; vpaddd xmm4, xmm1, xmm2 ; vpcmpgtd xmm5, xmm1, xmm2 ; vpminub xmm6, xmm1, xmm2 ; vpaddusw xmm7, xmm1, xmm2
    try h.add(0x1000, 4, vecRegs(.vmovaps_xmm_xmm, 0, 1, 0));
    try h.add(0x1004, 4, vecRegs(.vpxor, 3, 1, 2));
    try h.add(0x1008, 4, vecRegs(.vpaddd, 4, 1, 2));
    try h.add(0x100C, 4, vecRegs(.vpcmpgtd, 5, 1, 2));
    try h.add(0x1010, 4, vecRegs(.vpminub, 6, 1, 2));
    try h.add(0x1014, 4, vecRegs(.vpaddusw, 7, 1, 2));
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 6), completed);
    try testing.expectEqualSlices(u8, &a, &state.xmm[0]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[0]);
    try testing.expectEqualSlices(u8, &([_]u8{0xBB} ** 32), &state.zmm_hi[0]); // not an EVEX-routed form
    try testing.expectEqualSlices(u8, &lanes32(.{ 3, 0xFFFF_FFFF, 0xFFFF_FFFE, 0 }), &state.xmm[3]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[3]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 32), &state.zmm_hi[3]); // vpxor is EVEX-routed
    try testing.expectEqualSlices(u8, &lanes32(.{ 3, 0xFFFF_FFFF, 0, 0x2468_ACF0 }), &state.xmm[4]);
    // signed: 1 > 2 no; INT_MIN > INT_MAX no; -1 > 1 no; equal no.
    try testing.expectEqualSlices(u8, &lanes32(.{ 0, 0, 0, 0 }), &state.xmm[5]);
    // unsigned byte minimum: lane 1 is 00 00 00 80 against FF FF FF 7F.
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x0000_0001, 0x7F00_0000, 0x0000_0001, 0x1234_5678 }), &state.xmm[6]);
    // unsigned saturating word add: 0x0001+0x0002, 0x8000+0x7FFF=0xFFFF, 0xFFFF+0x0001 saturates, 0xFFFF+0x0000...
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x0000_0003, 0xFFFF_FFFF, 0xFFFF_FFFF, 0x2468_ACF0 }), &state.xmm[7]);
    // Vector state is outside the glue's register-only cross-check, so a
    // block of vector ops is not offered for it.
    try testing.expect(!h.block.register_only);
}

test "vector loads and stores go through the TLB when admitted and through the 128-bit helpers otherwise" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    const pattern = lanes32(.{ 0x11111111, 0x22222222, 0x33333333, 0x44444444 });
    @memcpy(state.memory[0x120..0x130], &pattern);
    state.xmm[1] = lanes32(.{ 5, 6, 7, 8 });
    // vmovdqu xmm0, [rbx + 0x20] ; vmovaps [rbx + 0x40], xmm1 ; vpaddd xmm2, xmm1, [rbx + 0x20]
    try h.add(0x1000, 5, vecMem(.vmovdqu_xmm_mem, 0, 0, 0x20));
    try h.add(0x1005, 5, vecMem(.vmovaps_mem_xmm, 0, 1, 0x40));
    var add_mem = vecMem(.vpaddd, 2, 1, 0x20);
    add_mem.xmm_src2 = 0;
    try h.add(0x100A, 5, add_mem);
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.reads + state.writes);
    try testing.expectEqualSlices(u8, &pattern, &state.xmm[0]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 5, 6, 7, 8 }), state.memory[0x140..0x150]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x11111116, 0x22222228, 0x3333333A, 0x4444444C }), &state.xmm[2]);
    // Nothing admitted: the same block calls the helpers.
    state = TestState{};
    state.regs.rbx = 0x100;
    @memcpy(state.memory[0x120..0x130], &pattern);
    state.xmm[1] = lanes32(.{ 5, 6, 7, 8 });
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 2), state.reads);
    try testing.expectEqual(@as(u32, 1), state.writes);
    try testing.expectEqualSlices(u8, &pattern, &state.xmm[0]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 5, 6, 7, 8 }), state.memory[0x140..0x150]);
}

test "legacy MOVUPS memory forms are native and preserve YMM upper state" {
    var h = try TestHarness.init();
    defer h.deinit();

    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    const input = [_]u8{0x5A} ** 16;
    @memcpy(state.memory[0x120..0x130], &input);
    state.xmm[1] = [_]u8{0xA5} ** 16;
    state.ymm_hi[0] = [_]u8{0xC3} ** 16;
    state.ymm_hi[1] = [_]u8{0xD4} ** 16;

    var load = vecMem(.movups_xmm_mem, 0, 0, 0x20);
    load.legacy_sse = true;
    var store = vecMem(.movups_mem_xmm, 0, 1, 0x40);
    store.legacy_sse = true;
    try testing.expect(isNative(load));
    try testing.expect(isNative(store));
    try h.add(0x1000, 5, load);
    try h.add(0x1005, 5, store);

    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqualSlices(u8, &input, &state.xmm[0]);
    try testing.expectEqualSlices(u8, &([_]u8{0xA5} ** 16), state.memory[0x140..0x150]);
    try testing.expectEqualSlices(u8, &([_]u8{0xC3} ** 16), &state.ymm_hi[0]);
    try testing.expectEqualSlices(u8, &([_]u8{0xD4} ** 16), &state.ymm_hi[1]);
}

test "legacy scalar MOVSS and MOVSD memory forms preserve YMM upper state" {
    var h = try TestHarness.init();
    defer h.deinit();

    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    std.mem.writeInt(u64, state.memory[0x120..][0..8], 0x1122_3344_5566_7788, .little);
    state.xmm[1] = [_]u8{0xE1} ** 16;
    state.ymm_hi[0] = [_]u8{0xC3} ** 16;
    state.ymm_hi[1] = [_]u8{0xD4} ** 16;

    var load = vecMem(.vmovsd_xmm_mem, 0, 0, 0x20);
    load.legacy_sse = true;
    var store = vecMem(.vmovss_mem_xmm, 0, 1, 0x40);
    store.legacy_sse = true;
    try testing.expect(isNative(load));
    try testing.expect(isNative(store));
    try h.add(0x2000, 5, load);
    try h.add(0x2005, 5, store);

    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqual(@as(u64, 0x1122_3344_5566_7788), std.mem.readInt(u64, state.xmm[0][0..8], .little));
    try testing.expectEqual(@as(u32, 0xE1E1_E1E1), std.mem.readInt(u32, state.memory[0x140..][0..4], .little));
    try testing.expectEqualSlices(u8, &([_]u8{0xC3} ** 16), &state.ymm_hi[0]);
    try testing.expectEqualSlices(u8, &([_]u8{0xD4} ** 16), &state.ymm_hi[1]);
}

test "legacy PUNPCKLQDQ interleaves low qwords without clearing YMM upper state" {
    var h = try TestHarness.init();
    defer h.deinit();

    var state = TestState{};
    state.xmm[1] = [_]u8{0x11} ** 16;
    state.xmm[2] = [_]u8{0x22} ** 16;
    state.ymm_hi[0] = [_]u8{0xC3} ** 16;
    var unpack = vecRegs(.vpunpcklqdq, 0, 1, 2);
    unpack.legacy_sse = true;
    try testing.expect(isNative(unpack));
    try h.add(0x3000, 4, unpack);

    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), state.interprets);
    try testing.expectEqualSlices(u8, &([_]u8{0x11} ** 8 ++ [_]u8{0x22} ** 8), &state.xmm[0]);
    try testing.expectEqualSlices(u8, &([_]u8{0xC3} ** 16), &state.ymm_hi[0]);
}

test "non-temporal vector stores use the class-aware helper even with a write TLB hit" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    const payload = lanes32(.{ 0x0123_4567, 0x89AB_CDEF, 0xA5A5_5A5A, 0xDEAD_BEEF });
    state.xmm[3] = payload;
    try h.add(0x1000, 5, vecMem(.vmovntps, 0, 3, 0x20));

    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u32, 1), state.non_temporal_writes);
    try testing.expectEqual(@as(u32, 0), state.writes);
    try testing.expectEqualSlices(u8, &payload, state.memory[0x120..0x130]);
}

test "non-temporal vector stores use admitted pages only with a queue-free runtime guard" {
    for ([_]Op{ .vmovntps, .vmovntdq }) |op| {
        for ([_]bool{ false, true }) |wide| {
            var h = try TestHarness.init();
            defer h.deinit();
            var state = TestState{};
            state.admitMemory(true, true);
            state.regs.rbx = 0x100;
            state.regs.rflags = 0xAD7;
            state.xmm[3] = @splat(0xA5);
            state.ymm_hi[3] = @splat(0x5A);
            state.scratch.direct_non_temporal = 1;
            var store = vecMem(op, 0, 3, 0x20);
            store.vector_256 = wide;
            try h.add(0x1000, 5, store);
            _ = try h.run(&state);
            try testing.expectEqual(@as(u32, 0), state.non_temporal_writes);
            try testing.expectEqualSlices(u8, &state.xmm[3], state.memory[0x120..0x130]);
            if (wide) try testing.expectEqualSlices(u8, &state.ymm_hi[3], state.memory[0x130..0x140]);
            try testing.expectEqual(@as(u32, 0xAD7), state.regs.rflags);
            try testing.expectEqual(@as(u8, 0), state.memory[0x11F]);
            try testing.expectEqual(@as(u8, 0), state.memory[if (wide) 0x140 else 0x130]);

            // Reuse exactly the same machine code after a mode/queue change.
            state.scratch.direct_non_temporal = 0;
            _ = h.block.entry()(&state, &h.block.helpers, &state.scratch);
            try testing.expectEqual(@as(u32, if (wide) 2 else 1), state.non_temporal_writes);
            state.scratch.direct_non_temporal = 1;
            state.tlb.flush(false, true); // withheld write admission
            _ = h.block.entry()(&state, &h.block.helpers, &state.scratch);
            try testing.expectEqual(@as(u32, if (wide) 4 else 2), state.non_temporal_writes);
        }
    }
}

test "non-temporal vector stores keep page-straddling accesses on the helper" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.scratch.direct_non_temporal = 1;
    state.regs.rbx = Tlb.page_bytes - 8;
    state.xmm[3] = @splat(0xA5);
    try h.add(0x1000, 5, vecMem(.vmovntps, 0, 3, 0));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 1), state.non_temporal_writes);
}

fn doubles64(values: [2]f64) [16]u8 {
    var bytes: [16]u8 = undefined;
    for (values, 0..) |value, lane| std.mem.writeInt(u64, bytes[lane * 8 ..][0..8], @bitCast(value), .little);
    return bytes;
}

test "Xenia's hot vector and MXCSR forms run natively with the interpreter's lane rules" {
    // The translated ldmxcsr moves this thread's FPCR; give it back.
    defer host_fp_control.restoreDefault();
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.xmm[1] = lanes32(.{ 0xFFFF_FFFF, 0xDEAD_BEEF, 3, 0x1234_5678 });
    state.xmm[2] = lanes32(.{ 2, 0xCAFE_BABE, 0x8000_0000, 7 });
    state.xmm[7] = floats32(.{ 1.5, -2.0, 3.25, 1.0e30 });
    for ([_]usize{ 0, 3, 4, 5, 6, 8 }) |dst| state.ymm_hi[dst] = @splat(0xAA);
    std.mem.writeInt(u32, state.memory[0x110..][0..4], 0x0000_9FC0, .little);
    std.mem.writeInt(u32, state.memory[0x130..][0..4], 0x4242_4242, .little);
    // vpmuludq xmm0, xmm1, xmm2
    try h.add(0x1000, 4, vecRegs(.vpmuludq, 0, 1, 2));
    // vpblendw xmm3, xmm1, xmm2, 0xA5
    var blend = vecRegs(.vpblendw, 3, 1, 2);
    blend.imm = 0xA5;
    try h.add(0x1004, 6, blend);
    // vshufpd xmm4, xmm1, xmm2, 1
    var shuf = vecRegs(.vshufpd, 4, 1, 2);
    shuf.imm = 1;
    try h.add(0x100A, 5, shuf);
    // vinsertps xmm5, xmm1, xmm2, (2 << 6) | (1 << 4) | 0b1000
    var insert = vecRegs(.vinsertps, 5, 1, 2);
    insert.imm = (2 << 6) | (1 << 4) | 0b1000;
    try h.add(0x100F, 6, insert);
    // vcvtps2pd ymm6, xmm7
    var widen = vecRegs(.vcvtps2pd, 6, 0, 7);
    widen.vector_256 = true;
    try h.add(0x1015, 4, widen);
    // vinsertps xmm8, xmm1, [rbx+0x30], (3 << 6) | (2 << 4) | 0b0001 - a memory
    // source ignores the source-lane bits.
    var insert_mem = vecMem(.vinsertps, 8, 1, 0x30);
    insert_mem.imm = (3 << 6) | (2 << 4) | 0b0001;
    try h.add(0x1019, 7, insert_mem);
    // ldmxcsr [rbx+0x10] ; stmxcsr [rbx+0x20]
    try h.add(0x1020, 4, baseDisp(.ldmxcsr_mem32, .bits32, .al_ax_eax_rax, 0x10));
    try h.add(0x1024, 4, baseDisp(.stmxcsr_mem32, .bits32, .al_ax_eax_rax, 0x20));
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 8), completed);
    // The arithmetic after a translated ldmxcsr obeys it: FPCR now flushes.
    try testing.expect(host_fp_control.matchesGuestMxcsr(0x9FC0));
    var products: [16]u8 = undefined;
    std.mem.writeInt(u64, products[0..8], 0xFFFF_FFFF * 2, .little);
    std.mem.writeInt(u64, products[8..16], 3 * 0x8000_0000, .little);
    try testing.expectEqualSlices(u8, &products, &state.xmm[0]);
    var blended: [16]u8 = undefined;
    for (0..8) |lane| {
        const from = if ((@as(u8, 0xA5) >> @intCast(lane)) & 1 != 0) state.xmm[2] else state.xmm[1];
        @memcpy(blended[lane * 2 ..][0..2], from[lane * 2 ..][0..2]);
    }
    try testing.expectEqualSlices(u8, &blended, &state.xmm[3]);
    try testing.expectEqualSlices(u8, state.xmm[1][8..16], state.xmm[4][0..8]);
    try testing.expectEqualSlices(u8, state.xmm[2][0..8], state.xmm[4][8..16]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0xFFFF_FFFF, 0x8000_0000, 3, 0 }), &state.xmm[5]);
    try testing.expectEqualSlices(u8, &doubles64(.{ 1.5, -2.0 }), &state.xmm[6]);
    try testing.expectEqualSlices(u8, &doubles64(.{ 3.25, @as(f64, @as(f32, 1.0e30)) }), &state.ymm_hi[6]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0, 0xDEAD_BEEF, 0x4242_4242, 0x1234_5678 }), &state.xmm[8]);
    for ([_]usize{ 0, 3, 4, 5, 8 }) |dst| try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[dst]);
    try testing.expectEqual(@as(u32, 0x9FC0), state.regs.mxcsr);
    try testing.expectEqual(@as(u32, 0x9FC0), std.mem.readInt(u32, state.memory[0x120..][0..4], .little));
    try testing.expectEqual(@as(u32, 0), state.reads + state.writes);
    try testing.expectEqual(@as(@TypeOf(h.block.fallback_count), 0), h.block.fallback_count);
}

test "shuffles, blends, packs, extends and shifts follow the interpreter's lane rules" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.xmm[1] = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    state.xmm[2] = .{ 15, 0x80, 1, 0x8F, 3, 3, 3, 3, 0, 0, 0, 0, 14, 13, 12, 11 };
    state.xmm[3] = lanes32(.{ 0x0000_9000, 0xFFFF_7000, 0x8000_0000, 0x7FFF_FFFF });
    state.xmm[4] = lanes32(.{ 0x8000_0000, 0x0000_0001, 0x8000_0000, 0x0000_0002 });
    // vpshufb xmm0, xmm1, xmm2 ; vpshufd xmm5, xmm1, 0x1B ; vpunpcklbw xmm6, xmm1, xmm2 ; vpblendvb xmm7, xmm1, xmm2 (mask xmm4)
    try h.add(0x1000, 5, vecRegs(.vpshufb, 0, 1, 2));
    var shufd = vecRegs(.vpshufd, 5, 1, 0);
    shufd.imm = 0x1B;
    try h.add(0x1005, 5, shufd);
    try h.add(0x100A, 4, vecRegs(.vpunpcklbw, 6, 1, 2));
    var blend = vecRegs(.vpblendvb, 7, 1, 2);
    blend.xmm_mask = 4;
    try h.add(0x100E, 5, blend);
    // vpackssdw xmm8, xmm3, xmm4 ; vpmovzxbw xmm9, xmm2 ; vpslld xmm10, xmm3, 33 ; vpsrad xmm11, xmm3, 40 ; vpsrldq xmm12, xmm1, 4 ; vpalignr xmm13, xmm1, xmm2, 4
    try h.add(0x1013, 4, vecRegs(.vpackssdw, 8, 3, 4));
    try h.add(0x1017, 5, vecRegs(.vpmovzxbw, 9, 2, 0));
    // The immediate forms, as the decoder gives them (`uses_imm`); without
    // it a shift is the xmm-count form.
    var shl = vecRegs(.vpslld, 10, 3, 0);
    shl.imm = 33;
    shl.uses_imm = true;
    try h.add(0x101C, 5, shl);
    var sra = vecRegs(.vpsrad, 11, 3, 0);
    sra.imm = 40;
    sra.uses_imm = true;
    try h.add(0x1021, 5, sra);
    var srldq = vecRegs(.vpsrldq, 12, 1, 0);
    srldq.imm = 4;
    srldq.uses_imm = true;
    try h.add(0x1026, 5, srldq);
    var alignr = vecRegs(.vpalignr, 13, 1, 2);
    alignr.imm = 4;
    try h.add(0x102B, 6, alignr);
    const completed = try h.run(&state);
    try testing.expectEqual(@as(u32, 10), completed);
    try testing.expectEqualSlices(u8, &.{ 15, 0, 1, 0, 3, 3, 3, 3, 0, 0, 0, 0, 14, 13, 12, 11 }, &state.xmm[0]);
    try testing.expectEqualSlices(u8, &.{ 12, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3 }, &state.xmm[5]);
    try testing.expectEqualSlices(u8, &.{ 0, 15, 1, 0x80, 2, 1, 3, 0x8F, 4, 3, 5, 3, 6, 3, 7, 3 }, &state.xmm[6]);
    // Mask sign bytes: bytes 3 and 11 of xmm4 are 0x80: those lanes take xmm2.
    try testing.expectEqualSlices(u8, &.{ 0, 1, 2, 0x8F, 4, 5, 6, 7, 8, 9, 10, 0, 12, 13, 14, 15 }, &state.xmm[7]);
    // packssdw: 0x9000 -> 0x7FFF, 0xFFFF7000 (-36864) -> 0x8000, INT_MIN -> 0x8000, INT_MAX -> 0x7FFF; then xmm4's lanes.
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x8000_7FFF, 0x7FFF_8000, 0x0001_8000, 0x0002_8000 }), &state.xmm[8]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x0080_000F, 0x008F_0001, 0x0003_0003, 0x0003_0003 }), &state.xmm[9]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0, 0, 0, 0 }), &state.xmm[10]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0, 0xFFFF_FFFF, 0xFFFF_FFFF, 0 }), &state.xmm[11]);
    try testing.expectEqualSlices(u8, &.{ 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0, 0, 0, 0 }, &state.xmm[12]);
    // vpalignr shifts xmm1:xmm2 (vvvv high, r/m low) right by 4 bytes.
    try testing.expectEqualSlices(u8, &.{ 3, 3, 3, 3, 0, 0, 0, 0, 14, 13, 12, 11, 0, 1, 2, 3 }, &state.xmm[13]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 32), &state.zmm_hi[0]); // vpshufb is EVEX-routed: cleared (was zero anyway)
}

test "VRCpss is native and preserves its VEX source-one upper lanes" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.xmm[1] = .{ 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 11, 12, 13, 14, 15, 16 };
    state.xmm[2] = floats32(.{ 4.0, 99.0, 99.0, 99.0 });
    state.ymm_hi[0] = @splat(0xCC);
    try h.add(0x1800, 4, vecRegs(.vrcpss, 0, 1, 2));
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    var expected = state.xmm[1];
    std.mem.writeInt(u32, expected[0..4], @bitCast(@as(f32, 0.25)), .little);
    try testing.expectEqualSlices(u8, &expected, &state.xmm[0]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[0]);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "legacy MOVQ into XMM preserves the YMM upper half" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.regs.rcx = 0x1234_5678_9ABC_DEF0;
    state.ymm_hi[3] = @splat(0xA5);
    var movq: DecodedInsn = .{
        .op = .vmovq_xmm_reg64,
        .size = .bits64,
        .src_reg = .cl_cx_ecx_rcx,
        .xmm_dst = 3,
        .is_reg_form = true,
        .legacy_sse = true,
    };
    movq.len = 4;
    try h.add(0x1900, 4, movq);
    try testing.expectEqual(@as(u32, 1), try h.run(&state));
    try testing.expectEqual(@as(u64, 0x1234_5678_9ABC_DEF0), std.mem.readInt(u64, state.xmm[3][0..8], .little));
    try testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, state.xmm[3][8..16], .little));
    try testing.expectEqualSlices(u8, &([_]u8{0xA5} ** 16), &state.ymm_hi[3]);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "float templates: min and max ordering, compare predicates, conversions, rounding and compare flags" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    const nan: f32 = @bitCast(@as(u32, 0x7FC0_0000));
    state.xmm[1] = floats32(.{ 1.0, nan, -0.0, 2.5 });
    state.xmm[2] = floats32(.{ 2.0, 3.0, 0.0, 2.5 });
    state.xmm[3] = floats32(.{ 3.0e9, -3.0e9, 1.5, nan });
    state.xmm[4] = floats32(.{ 2.5, 3.5, -2.5, 1.0 });
    // vminps xmm0, xmm1, xmm2 ; vmaxps xmm5, xmm1, xmm2 ; vcmpps xmm6, xmm1, xmm2, 1 (lt) ; vcvttps2dq xmm7, xmm3 ; vcvtps2dq xmm8, xmm4 ; vroundps xmm9, xmm4, 0
    try h.add(0x1000, 4, vecRegs(.vminps, 0, 1, 2));
    try h.add(0x1004, 4, vecRegs(.vmaxps, 5, 1, 2));
    var cmp = vecRegs(.vcmpps, 6, 1, 2);
    cmp.imm = 1;
    try h.add(0x1008, 5, cmp);
    try h.add(0x100D, 4, vecRegs(.vcvttps2dq, 7, 0, 3));
    try h.add(0x1011, 4, vecRegs(.vcvtps2dq, 8, 0, 4));
    var round = vecRegs(.vroundps, 9, 0, 4);
    round.imm = 0;
    try h.add(0x1015, 6, round);
    _ = try h.run(&state);
    // min: 1<2 -> 1 ; NaN<3 false -> 3 ; -0<0 false -> 0 ; 2.5<2.5 false -> 2.5
    try testing.expectEqualSlices(u8, &floats32(.{ 1.0, 3.0, 0.0, 2.5 }), &state.xmm[0]);
    // max: 1>2 false -> 2 ; NaN -> 3 ; -0>0 false -> 0 ; -> 2.5
    try testing.expectEqualSlices(u8, &floats32(.{ 2.0, 3.0, 0.0, 2.5 }), &state.xmm[5]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0xFFFF_FFFF, 0, 0, 0 }), &state.xmm[6]);
    // truncating: 3e9 and -3e9 out of range, NaN -> indefinite; 1.5 -> 1
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x8000_0000, 0x8000_0000, 1, 0x8000_0000 }), &state.xmm[7]);
    // MXCSR's default rounding, nearest with ties to even (as native SSE
    // gives): 2.5 -> 2, 3.5 -> 4, -2.5 -> -2, 1
    try testing.expectEqualSlices(u8, &lanes32(.{ 2, 4, 0xFFFF_FFFE, 1 }), &state.xmm[8]);
    // round to nearest even: 2.5 -> 2, 3.5 -> 4, -2.5 -> -2, 1
    try testing.expectEqualSlices(u8, &floats32(.{ 2.0, 4.0, -2.0, 1.0 }), &state.xmm[9]);

    // A signalling NaN survives vroundps unchanged; vucomiss sets ZF|PF|CF
    // for an unordered pair, CF for less, ZF for equal.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    state.xmm[1] = lanes32(.{ 0x7F80_0001, 0x3F80_0000, 0, 0 });
    state.xmm[2] = floats32(.{ 1.0, 2.0, 0, 0 });
    state.xmm[3] = floats32(.{ 1.0, 0, 0, 0 });
    state.regs.rflags = 0x2 | RFL_OF | RFL_SF;
    round = vecRegs(.vroundps, 0, 0, 1);
    round.imm = 3;
    try h.add(0x1000, 6, round);
    try h.add(0x1006, 4, vecRegs(.vucomiss, 0, 1, 2)); // SNaN vs 1.0: unordered
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0x7F80_0001), std.mem.readInt(u32, state.xmm[0][0..4], .little));
    try testing.expectEqual(@as(u32, 0x2 | RFL_ZF | RFL_PF | RFL_CF), state.regs.rflags);
    h.insns.clearRetainingCapacity();
    state.regs.rflags = 0x2;
    try h.add(0x1000, 4, vecRegs(.vucomiss, 0, 3, 2)); // 1.0 vs 1.0: equal
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0x2 | RFL_ZF), state.regs.rflags);
    h.insns.clearRetainingCapacity();
    state.regs.rflags = 0x2;
    try h.add(0x1000, 4, vecRegs(.vucomiss, 0, 2, 1)); // 1.0 (lane 0 of xmm2) vs SNaN: unordered again
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0x2 | RFL_ZF | RFL_PF | RFL_CF), state.regs.rflags);

    // Scalar conversions: NaN and 2^31 give the indefinite value, a
    // double just under 2^31 rounds to a legitimate INT_MAX, negatives
    // saturate to INT_MIN, and vcvtsi2sd / vcvtsd2ss merge into lane 0.
    h.insns.clearRetainingCapacity();
    state = TestState{};
    var doubles: [16]u8 = undefined;
    std.mem.writeInt(u64, doubles[0..8], @bitCast(@as(f64, 2147483647.4)), .little);
    std.mem.writeInt(u64, doubles[8..16], @bitCast(@as(f64, 2147483648.0)), .little);
    state.xmm[1] = doubles;
    var big: [16]u8 = undefined;
    std.mem.writeInt(u64, big[0..8], @bitCast(@as(f64, 2147483648.0)), .little);
    std.mem.writeInt(u64, big[8..16], @bitCast(@as(f64, -1.0e12)), .little);
    state.xmm[2] = big;
    state.xmm[3] = floats32(.{ nan, 0, 0, 0 });
    state.regs.r8 = @bitCast(@as(i64, -7));
    var cvt1: DecodedInsn = .{ .op = .vcvtsd2si, .size = .bits32, .dst_reg = .al_ax_eax_rax, .xmm_src = 1, .is_reg_form = true };
    try h.add(0x1000, 5, cvt1);
    var cvt2: DecodedInsn = .{ .op = .vcvttsd2si, .size = .bits32, .dst_reg = .cl_cx_ecx_rcx, .xmm_src = 2, .is_reg_form = true };
    try h.add(0x1005, 5, cvt2);
    var cvt3: DecodedInsn = .{ .op = .vcvttss2si, .size = .bits64, .dst_reg = .dl_dx_edx_rdx, .xmm_src = 3, .is_reg_form = true };
    try h.add(0x100A, 5, cvt3);
    var cvt4: DecodedInsn = .{ .op = .vcvtsi2sd_xmm_reg, .size = .bits64, .src_reg = .r8b_r8w_r8d_r8, .xmm_dst = 4, .xmm_src = 1, .is_reg_form = true };
    try h.add(0x100F, 5, cvt4);
    try h.add(0x1014, 4, vecRegs(.vcvtsd2ss, 5, 3, 4));
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 0x7FFF_FFFF), state.regs.rax);
    try testing.expectEqual(@as(u64, 0x8000_0000), state.regs.rcx);
    try testing.expectEqual(@as(u64, 0x8000_0000_0000_0000), state.regs.rdx);
    try testing.expectEqual(@as(u64, @bitCast(@as(f64, -7.0))), std.mem.readInt(u64, state.xmm[4][0..8], .little));
    try testing.expectEqual(@as(u64, @bitCast(@as(f64, 2147483648.0))), std.mem.readInt(u64, state.xmm[4][8..16], .little));
    try testing.expectEqual(@as(u32, @bitCast(@as(f32, -7.0))), std.mem.readInt(u32, state.xmm[5][0..4], .little));
    try testing.expectEqualSlices(u8, state.xmm[3][4..16], state.xmm[5][4..16]);
    _ = &cvt1;
    _ = &cvt2;
    _ = &cvt3;
    _ = &cvt4;
}

test "general-register transfers, extract, insert and broadcast" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.regs.rax = 0xFFFF_FFFF_1234_5678;
    state.regs.rcx = 0x0102_0304_0506_0708;
    state.xmm[1] = lanes32(.{ 0xAAAA_AAAA, 0xBBBB_BBBB, 0xCCCC_CCCC, 0xDDDD_DDDD });
    state.ymm_hi[2] = @splat(0x11);
    std.mem.writeInt(u32, state.memory[0x130..][0..4], 0x3F80_0000, .little);
    // vmovd xmm2, eax ; vmovq xmm3, rcx ; vmovd edx, xmm1 ; vmovq rsi, xmm1 ; vpextrd edi, xmm1, 2 ; vpinsrd xmm4, xmm1, eax, 1 ; vbroadcastss xmm5, [rbx + 0x30]
    var movd: DecodedInsn = .{ .op = .vmovd_xmm_reg32, .size = .bits32, .src_reg = .al_ax_eax_rax, .xmm_dst = 2, .is_reg_form = true };
    try h.add(0x1000, 4, movd);
    var movq: DecodedInsn = .{ .op = .vmovq_xmm_reg64, .size = .bits64, .src_reg = .cl_cx_ecx_rcx, .xmm_dst = 3, .is_reg_form = true };
    try h.add(0x1004, 5, movq);
    var movd_out: DecodedInsn = .{ .op = .vmovd_reg32_xmm, .size = .bits32, .dst_reg = .dl_dx_edx_rdx, .xmm_src = 1, .is_reg_form = true };
    try h.add(0x1009, 4, movd_out);
    var movq_out: DecodedInsn = .{ .op = .vmovq_reg64_xmm, .size = .bits64, .dst_reg = .dh_si_esi_rsi, .xmm_src = 1, .is_reg_form = true };
    try h.add(0x100D, 5, movq_out);
    var extract: DecodedInsn = .{ .op = .vpextrd, .size = .bits32, .dst_reg = .bh_di_edi_rdi, .xmm_src = 1, .imm = 2, .is_reg_form = true };
    try h.add(0x1012, 6, extract);
    var insert: DecodedInsn = .{ .op = .vpinsrd, .size = .bits32, .src_reg = .al_ax_eax_rax, .xmm_dst = 4, .xmm_src = 1, .imm = 1, .is_reg_form = true };
    try h.add(0x1018, 6, insert);
    try h.add(0x101E, 5, vecMem(.vbroadcastss, 5, 0, 0x30));
    _ = try h.run(&state);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0x1234_5678, 0, 0, 0 }), &state.xmm[2]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[2]);
    try testing.expectEqual(@as(u64, 0x0102_0304_0506_0708), std.mem.readInt(u64, state.xmm[3][0..8], .little));
    try testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, state.xmm[3][8..16], .little));
    try testing.expectEqual(@as(u64, 0xAAAA_AAAA), state.regs.rdx);
    try testing.expectEqual(@as(u64, 0xBBBB_BBBB_AAAA_AAAA), state.regs.rsi);
    try testing.expectEqual(@as(u64, 0xCCCC_CCCC), state.regs.rdi);
    try testing.expectEqualSlices(u8, &lanes32(.{ 0xAAAA_AAAA, 0x1234_5678, 0xCCCC_CCCC, 0xDDDD_DDDD }), &state.xmm[4]);
    try testing.expectEqualSlices(u8, &floats32(.{ 1.0, 1.0, 1.0, 1.0 }), &state.xmm[5]);
    try testing.expectEqual(@as(u32, 0), state.reads);
    _ = &movd;
    _ = &movq;
    _ = &movd_out;
    _ = &movq_out;
    _ = &extract;
    _ = &insert;
}

test "hot vector fallbacks use native moves, permutes, inserts, and movemasks" {
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.admitMemory(true, true);
    state.regs.rbx = 0x100;
    state.xmm[1] = lanes32(.{ 1, 2, 3, 4 });
    state.ymm_hi[0] = @splat(0xAA);
    state.xmm[2] = lanes32(.{ 0x89AB_CDEF, 0x0123_4567, 0, 0 });
    state.xmm[3] = lanes32(.{ 10, 20, 30, 40 });
    state.xmm[4] = lanes32(.{ 1, 2, 3, 4 });
    state.xmm[5] = lanes32(.{ 3, 2, 1, 0 });
    state.ymm_hi[4] = lanes32(.{ 5, 6, 7, 8 });
    state.ymm_hi[5] = lanes32(.{ 0, 1, 2, 3 });
    state.xmm[8] = lanes32(.{ 81, 82, 83, 84 });
    state.ymm_hi[8] = lanes32(.{ 85, 86, 87, 88 });
    state.xmm[10] = lanes32(.{ 101, 102, 103, 104 });
    state.ymm_hi[12] = [_]u8{0} ** 16;
    std.mem.writeInt(u64, state.xmm[12][0..8], 0x8000_0000_0000_0000, .little);
    std.mem.writeInt(u64, state.xmm[12][8..16], 0, .little);
    std.mem.writeInt(u64, state.ymm_hi[12][0..8], 0, .little);
    std.mem.writeInt(u64, state.ymm_hi[12][8..16], 0x8000_0000_0000_0000, .little);
    state.xmm[15] = lanes32(.{ 11, 12, 13, 14 });
    state.ymm_hi[15] = lanes32(.{ 15, 16, 17, 18 });
    @memcpy(state.memory[0x120..0x130], &lanes32(.{ 21, 22, 23, 24 }));
    @memcpy(state.memory[0x140..0x150], &lanes32(.{ 31, 32, 33, 34 }));

    try h.add(0x1000, 3, .{ .op = .movaps_xmm_xmm, .legacy_sse = true, .xmm_dst = 0, .xmm_src = 1, .is_reg_form = true });
    try h.add(0x1003, 4, .{ .op = .vmovq_reg64_xmm, .legacy_sse = true, .size = .bits64, .dst_reg = .dh_si_esi_rsi, .xmm_src = 2, .is_reg_form = true });
    try h.add(0x1007, 5, .{ .op = .vpermilps, .uses_imm = true, .imm = 0x1B, .xmm_dst = 6, .xmm_src = 3, .is_reg_form = true });
    try h.add(0x100C, 5, .{ .op = .vpermilps, .xmm_dst = 7, .xmm_src = 4, .xmm_src2 = 5, .is_reg_form = true });
    try h.add(0x1011, 6, .{ .op = .vinsertf128, .vector_256 = true, .imm = 1, .xmm_dst = 11, .xmm_src = 8, .xmm_src2 = 10, .is_reg_form = true });
    try h.add(0x1017, 4, .{ .op = .vmovmskpd, .vector_256 = true, .size = .bits32, .dst_reg = .al_ax_eax_rax, .xmm_src = 12, .is_reg_form = true });
    try h.add(0x101B, 5, .{ .op = .vpermilps, .vector_256 = true, .xmm_dst = 9, .xmm_src = 4, .xmm_src2 = 5, .is_reg_form = true });
    try h.add(0x1020, 6, .{ .op = .vpermilps, .uses_imm = true, .vector_256 = true, .imm = 0x1B, .xmm_dst = 16, .xmm_src = 15, .is_reg_form = true });
    try h.add(0x1026, 6, .{ .op = .vpermilps, .uses_imm = true, .imm = 0x1B, .xmm_dst = 13, .addr = 0x20, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx });
    try h.add(0x102C, 7, .{ .op = .vinsertf128, .vector_256 = true, .imm = 0, .xmm_dst = 14, .xmm_src = 8, .addr = 0x40, .sib_has_base = true, .sib_base_reg = .bl_bx_ebx_rbx });
    _ = try h.run(&state);

    try testing.expectEqualSlices(u8, &state.xmm[1], &state.xmm[0]);
    try testing.expectEqualSlices(u8, &([_]u8{0xAA} ** 16), &state.ymm_hi[0]);
    try testing.expectEqual(@as(u64, 0x0123_4567_89AB_CDEF), state.regs.rsi);
    try testing.expectEqualSlices(u8, &lanes32(.{ 40, 30, 20, 10 }), &state.xmm[6]);
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &state.ymm_hi[6]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 4, 3, 2, 1 }), &state.xmm[7]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 4, 3, 2, 1 }), &state.xmm[9]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 5, 6, 7, 8 }), &state.ymm_hi[9]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 14, 13, 12, 11 }), &state.xmm[16]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 18, 17, 16, 15 }), &state.ymm_hi[16]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 24, 23, 22, 21 }), &state.xmm[13]);
    try testing.expectEqualSlices(u8, &state.xmm[8], &state.xmm[11]);
    try testing.expectEqualSlices(u8, &state.xmm[10], &state.ymm_hi[11]);
    try testing.expectEqualSlices(u8, &lanes32(.{ 31, 32, 33, 34 }), &state.xmm[14]);
    try testing.expectEqualSlices(u8, &state.ymm_hi[8], &state.ymm_hi[14]);
    try testing.expectEqual(@as(u64, 0b1001), state.regs.rax);
    try testing.expectEqual(@as(u32, 0), state.interprets);
}

test "ret is native, and every instrument its interpreter arm carries still stops it" {
    var h = try TestHarness.init();
    defer h.deinit();

    // A return address sitting at rsp inside the harness's guest page.
    const stack: u64 = 0x100;
    const return_rip: u64 = 0x1234_5678;

    // The plain case: pop into RIP, rsp += 8, and the interpreter is never
    // asked. This is the 2,162,247,062-call path.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        std.mem.writeInt(u64, state.memory[stack..][0..8], return_rip, .little);
        h.insns.clearRetainingCapacity();
        try h.add(0xB000, 1, .{ .op = .ret });
        const completed = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), completed);
        try testing.expectEqual(return_rip, state.regs.rip);
        try testing.expectEqual(stack + 8, state.regs.rsp);
        try testing.expectEqual(@as(u32, 0), state.interprets);
    }

    // `ret imm16` pops the return address and then discards the caller's
    // argument area. The stack adjustment is applied by the native template.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        std.mem.writeInt(u64, state.memory[stack..][0..8], return_rip, .little);
        h.insns.clearRetainingCapacity();
        try h.add(0xB000, 3, .{ .op = .ret, .imm = 0x1234 });
        const completed = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), completed);
        try testing.expectEqual(return_rip, state.regs.rip);
        try testing.expectEqual(stack + 8 + 0x1234, state.regs.rsp);
        try testing.expectEqual(@as(u32, 0), state.interprets);
    }

    // Each guard hands the instruction back with nothing mutated, so the
    // interpreter sees exactly the machine the instruction started on.
    const Guard = struct { trace_calls: bool, captures: u32, value: u64 };
    for ([_]Guard{
        // The ABI call stack is fed from the interpreter's arm.
        .{ .trace_calls = true, .captures = 0, .value = return_rip },
        // A return capture completes on this boundary.
        .{ .trace_calls = false, .captures = 1, .value = return_rip },
        // A zero return address is the cooperative worker's completion
        // marker, which the interpreter recognises and reports.
        .{ .trace_calls = false, .captures = 0, .value = 0 },
    }) |guard| {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.trace_calls = guard.trace_calls;
        state.return_captures = guard.captures;
        std.mem.writeInt(u64, state.memory[stack..][0..8], guard.value, .little);
        h.insns.clearRetainingCapacity();
        try h.add(0xB000, 1, .{ .op = .ret });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), state.interprets);
        try testing.expectEqual(@as(u32, 0), state.last_interpret_index);
        // Nothing was committed before the hand-back: rsp is untouched, and
        // RIP is where the harness's interpreter stub put it rather than
        // anywhere this template chose.
        try testing.expectEqual(stack, state.regs.rsp);
    }

    try testing.expect(isNative(.{ .op = .ret, .imm = 4 }));
    try testing.expect(isNative(.{ .op = .ret, .imm = 0 }));

    // A faulting pop leaves through the abort path with the instruction not
    // retired, and never reaches the commit.
    {
        var state = TestState{};
        state.regs.rsp = stack;
        state.abort_on_access = true;
        std.mem.writeInt(u64, state.memory[stack..][0..8], return_rip, .little);
        h.insns.clearRetainingCapacity();
        try h.add(0xB000, 1, .{ .op = .ret });
        _ = try h.run(&state);
        try testing.expectEqual(stack, state.regs.rsp);
        try testing.expectEqual(@as(u64, 0xB001), state.regs.rip);
    }
}

test "indirect transfers outside the image and hooked image targets use the interpreter" {
    var h = try TestHarness.init();
    defer h.deinit();
    const stack: u64 = 0x200;
    // An external function pointer is classified by the interpreter. This
    // includes import thunks and mapped generated code, and keeps an invalid
    // data value from being installed as RIP by native translated code.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = 0xA000_1000;
        state.image_low = 0x1_4000_0000;
        state.image_high = 0x1_5000_0000;
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = .call_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), state.interprets);
        try testing.expectEqual(@as(u64, 0xC002), state.regs.rip);
        try testing.expectEqual(stack, state.regs.rsp);
    }
    // The same call into the image, and a jump to zero: handed back with
    // the stack untouched.
    for ([_]u64{ 0x1_4000_2000, 0 }) |target| {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = target;
        state.image_low = 0x1_4000_0000;
        state.image_high = 0x1_5000_0000;
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = if (target == 0) .jmp_reg64 else .call_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), state.interprets);
        try testing.expectEqual(stack, state.regs.rsp);
    }
    // With the filter built, an image target the filter does not name is
    // native, one it names is the interpreter's.
    for ([_]bool{ false, true }) |hooked| {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = 0x1_4000_2000;
        state.image_low = 0x1_4000_0000;
        state.image_high = 0x1_5000_0000;
        state.image_targets_hooked = 0;
        if (hooked) {
            hookFilterAdd(&state.hook_filter, 0x1_4000_2000);
            state.exact_hook_targets[0] = 0x1_4000_2000;
            state.exact_hook_target_count = 1;
        }
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = .call_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, if (hooked) 1 else 0), state.interprets);
        try testing.expectEqual(@as(u32, if (hooked) 1 else 0), state.hooked_transfer_calls);
        try testing.expectEqual(if (hooked) stack else stack - 8, state.regs.rsp);
    }
    // A stale/colliding Bloom bit must not turn an ordinary Xenia image call
    // into a permanent interpreter exit. The exact hook callback rejects it,
    // then the native template retains the normal call/stack behavior.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = 0x1_4000_2000;
        state.image_low = 0x1_4000_0000;
        state.image_high = 0x1_5000_0000;
        state.image_targets_hooked = 0;
        hookFilterAdd(&state.hook_filter, 0x1_4000_2000);
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = .call_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), state.hooked_transfer_calls);
        try testing.expectEqual(@as(u32, 0), state.interprets);
        try testing.expectEqual(@as(u64, 0x1_4000_2000), state.regs.rip);
        try testing.expectEqual(stack - 8, state.regs.rsp);
    }
    // call [rbx + 0x20]: IAT operands and external function pointers both
    // reach the interpreter, which owns the import and mapped-code routes.
    for ([_]bool{ true, false }) |in_iat| {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = 0x100;
        std.mem.writeInt(u64, state.memory[0x120..][0..8], 0xA000_3000, .little);
        state.image_targets_hooked = 0;
        state.iat_low = if (in_iat) 0x100 else 0x800;
        state.iat_high = if (in_iat) 0x200 else 0x900;
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 3, baseDisp(.call_mem64, .bits64, .al_ax_eax_rax, 0x20));
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), state.interprets);
        try testing.expectEqual(stack, state.regs.rsp);
    }
    // An external jmp rbx also reaches the interpreter and leaves RSP alone.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = 0xA000_2000;
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = .jmp_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), state.interprets);
        try testing.expectEqual(stack, state.regs.rsp);
    }

    // The glue can prove the dedicated Xenia code-cache mapping. In that
    // case both indirect register and memory calls use the already-compiled
    // transfer templates and preserve the normal guest stack contract.
    for ([_]Op{ .call_reg64, .call_mem64 }) |op| {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.regs.rbx = if (op == .call_mem64) 0x100 else 0xA000_1000;
        if (op == .call_mem64) std.mem.writeInt(u64, state.memory[0x120..][0..8], 0xA000_3000, .little);
        state.image_low = 0x1_4000_0000;
        state.image_high = 0x1_5000_0000;
        state.mapped_transfer_allowed = true;
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, if (op == .call_mem64) 3 else 2, if (op == .call_mem64)
            baseDisp(.call_mem64, .bits64, .al_ax_eax_rax, 0x20)
        else
            .{ .op = .call_reg64, .dst_reg = .bl_bx_ebx_rbx });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 0), state.interprets);
        try testing.expectEqual(if (op == .call_mem64) @as(u64, 0xA000_3000) else @as(u64, 0xA000_1000), state.regs.rip);
        try testing.expectEqual(stack - 8, state.regs.rsp);
        try testing.expectEqual(if (op == .call_mem64) @as(u64, 0xC003) else @as(u64, 0xC002), std.mem.readInt(u64, state.memory[stack - 8 ..][0..8], .little));
    }

    // The emitter reads a register or [rsp] target before pushing the
    // return address. Prove both RSP forms use the same mapped-code proof
    // and preserve the old stack value as the call target/source address.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.code_cache_low = stack;
        state.code_cache_high = stack + 0x100;
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 2, .{ .op = .call_reg64, .dst_reg = .ah_sp_esp_rsp });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 0), state.interprets);
        try testing.expectEqual(stack, state.regs.rip);
        try testing.expectEqual(stack - 8, state.regs.rsp);
        try testing.expectEqual(@as(u64, 0xC002), std.mem.readInt(u64, state.memory[stack - 8 ..][0..8], .little));
    }
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.code_cache_low = 0xA000_0000;
        state.code_cache_high = 0xA001_0000;
        std.mem.writeInt(u64, state.memory[stack..][0..8], 0xA000_3000, .little);
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 3, baseDispAt(.call_mem64, .bits64, .ah_sp_esp_rsp, 0));
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 0), state.interprets);
        try testing.expectEqual(@as(u64, 0xA000_3000), state.regs.rip);
        try testing.expectEqual(stack - 8, state.regs.rsp);
        try testing.expectEqual(@as(u64, 0xC003), std.mem.readInt(u64, state.memory[stack - 8 ..][0..8], .little));
    }
}

test "a direct call pushes its return address natively and still ends the block" {
    var h = try TestHarness.init();
    defer h.deinit();
    const stack: u64 = 0x200;

    // mov rax, rbx ; call +0x100. The call is the block's last instruction
    // whether or not it is native, and the pushed value is the address of
    // the instruction after it.
    {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rbx = 7;
        state.regs.rsp = stack;
        h.insns.clearRetainingCapacity();
        try h.add(0xC000, 3, regReg(.mov_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        try h.add(0xC003, 5, .{ .op = .call_rel32, .imm = 0x100 });
        const completed = try h.run(&state);
        try testing.expectEqual(@as(u32, 2), completed);
        try testing.expectEqual(@as(u64, 0xC008 + 0x100), state.regs.rip);
        try testing.expectEqual(stack - 8, state.regs.rsp);
        try testing.expectEqual(@as(u64, 0xC008), std.mem.readInt(u64, state.memory[stack - 8 ..][0..8], .little));
        try testing.expectEqual(@as(u64, 7), state.regs.rax);
        try testing.expectEqual(@as(u32, 0), state.interprets);
        try testing.expectEqual(@as(u32, 2), h.block.native_count);
    }

    // Either transfer trace hands the instruction back with the stack
    // untouched, so the interpreter's arm sees the machine it expects.
    for ([_]bool{ true, false }) |messages| {
        var state = TestState{};
        state.admitMemory(true, true);
        state.regs.rsp = stack;
        state.trace_transfers = messages;
        state.trace_calls = !messages;
        h.insns.clearRetainingCapacity();
        try h.add(0xC003, 5, .{ .op = .call_rel32, .imm = 0x100 });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u32, 1), state.interprets);
        try testing.expectEqual(stack, state.regs.rsp);
        try testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, state.memory[stack - 8 ..][0..8], .little));
    }

    // A push that faults leaves through the abort path: the block stops at
    // the call without retiring it, and RIP is the call's own address plus
    // its length rather than the target.
    {
        var state = TestState{};
        state.regs.rsp = stack;
        state.abort_on_access = true;
        h.insns.clearRetainingCapacity();
        try h.add(0xC003, 5, .{ .op = .call_rel32, .imm = 0x100 });
        _ = try h.run(&state);
        try testing.expectEqual(@as(u64, 0xC008), state.regs.rip);
    }
}

test "emitted code writes the scratch index and vector slot before any helper reads them" {
    // The glue resets only `abort` and `block` between executions, because
    // the state escapes into the helpers and zeroing the rest is a store it
    // cannot optimise away. That is sound only while every helper that reads
    // `index` or the vector slot is preceded by emitted code writing it.
    // Poison both and prove the helpers never see the poison.
    var h = try TestHarness.init();
    defer h.deinit();
    var state = TestState{};
    state.scratch.index = 0xDEAD;
    state.scratch.vector = @splat(0xA5);
    state.regs.rbx = 0x100;
    std.mem.writeInt(u64, state.memory[0x100..][0..8], 0x1122_3344_5566_7788, .little);

    // A load through the helper (the TLB is empty, so the slow path runs),
    // then an instruction with no template at all.
    var load: DecodedInsn = .{ .op = .mov_reg64_mem64, .size = .bits64, .dst_reg = .al_ax_eax_rax };
    load.sib_has_base = true;
    load.sib_base_reg = .bl_bx_ebx_rbx;
    try h.add(0x9000, 3, load);
    try h.add(0x9003, 1, .{ .op = .lahf, .size = .bits64, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    state.interpret_result = 1;
    _ = try h.run(&state);

    // The read helper was told instruction 0 and the interpreter helper
    // instruction 1; neither saw 0xDEAD. `interpret` itself cross-checks the
    // scratch index against its argument and pokes r15 when they disagree.
    try testing.expectEqual(@as(u32, 1), state.reads);
    try testing.expectEqual(@as(u32, 1), state.interprets);
    try testing.expectEqual(@as(u32, 1), state.last_interpret_index);
    try testing.expect(state.regs.r15 != 0xBAD_1DE7);
    try testing.expectEqual(@as(u64, 0x1122_3344_5566_7788), state.regs.rax);

    // A 128-bit store fills the vector slot from the register file first, so
    // a poisoned slot never reaches the write helper either.
    var state2 = TestState{};
    state2.scratch.vector = @splat(0xA5);
    state2.xmm[1] = @splat(0x3C);
    state2.regs.rbx = 0x200;
    h.insns.clearRetainingCapacity();
    const vstore = vecMem(.vmovups_mem_xmm, 0, 1, 0);
    try testing.expect(isNative(vstore));
    try h.add(0x9000, 4, vstore);
    _ = try h.run(&state2);
    try testing.expectEqual(@as(u32, 1), state2.writes);
    try testing.expectEqualSlices(u8, &[_]u8{0x3C} ** 16, state2.memory[0x200..][0..16]);
}

test "emitted code size per instruction, and a trace costing less than its basic blocks" {
    // A census rather than an exact check: these are the numbers that decide
    // what is worth optimising, and a silent regression in any of them is a
    // silent regression in the whole translated lane. Bounds are generous
    // enough that an unrelated encoding change does not fail, and tight
    // enough that a doubling does.
    var h = try TestHarness.init();
    defer h.deinit();
    const Sizes = struct {
        fn of(hh: *TestHarness) !usize {
            const insns = hh.insns.items;
            const last = insns[insns.len - 1];
            const compiled = try compile(testing.allocator, &hh.memory, TestState.layout, insns, last.rip + last.len);
            return compiled.code.len;
        }
        fn single(hh: *TestHarness, rip: u64, len: u8, d: DecodedInsn) !usize {
            hh.insns.clearRetainingCapacity();
            try hh.add(rip, len, d);
            return of(hh);
        }
    };

    // The fixed cost of being a block at all: prologue, exit stub, epilogue.
    // `mov r64,r64` is two instructions of actual work on top of it, so this
    // is what every additional block execution pays for nothing.
    const overhead = try Sizes.single(&h, 0x1000, 3, regReg(.mov_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx)) - 2;
    // The chain attempt lives here too: a block's exit records what it ran
    // and decides whether to jump straight into its successor. Four link
    // ways cost five words each before the one shared proof.
    try testing.expect(overhead >= 15 and overhead <= 110);

    // Flags dominate arithmetic: an `add` is one instruction of arithmetic
    // and about thirty of flag materialisation. This is the largest single
    // item left in the translated lane and the reason lazy flags is the next
    // structural change worth making.
    const add_cost = try Sizes.single(&h, 0x1000, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx)) - overhead;
    // Was 32 before the deferred record: an `add` is one instruction of
    // arithmetic, a handful of stores, and only the flags a later
    // instruction in the same block actually reads.
    try testing.expect(add_cost >= 20 and add_cost <= 44);

    // A guest memory access is a TLB probe plus an out-of-line helper call.
    var load: DecodedInsn = .{ .op = .mov_reg64_mem64, .size = .bits64, .dst_reg = .al_ax_eax_rax };
    load.sib_has_base = true;
    load.sib_base_reg = .bl_bx_ebx_rbx;
    const load_cost = try Sizes.single(&h, 0x1000, 3, load) - overhead;
    // The TSO path includes an out-of-line helper branch for legal unaligned
    // accesses, even though aligned loads take the short LDAR path. Count
    // both paths in code size, not just the hot path.
    try testing.expect(load_cost >= 12 and load_cost <= 80);

    // Three basic blocks of `cmp; jcc; add` as one trace, against what the
    // same nine instructions cost as three separate blocks. The words saved
    // are the smaller half of the win: the larger half is two block
    // executions that never happen, each of which is an indirect call into
    // the translation cache and a probe of a two-megabyte table.
    var jcc: DecodedInsn = .{ .op = .jcc_rel8, .cond = .ne, .addr = 0x20 };
    jcc.rip_relative = true;
    h.insns.clearRetainingCapacity();
    var rip: u64 = 0x6000;
    for (0..3) |_| {
        try h.add(rip, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        rip += 3;
        try h.add(rip, 2, jcc);
        rip += 2;
        try h.add(rip, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        rip += 3;
    }
    const trace_words = try Sizes.of(&h);
    const cmp_cost = try Sizes.single(&h, 0x1000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx)) - overhead;
    const jcc_cost = try Sizes.single(&h, 0x1000, 2, jcc) - overhead;
    const separate = 3 * overhead + 3 * cmp_cost + 3 * jcc_cost + 3 * add_cost;
    try testing.expect(trace_words < separate);
}

test "a block continues across a conditional branch and its taken edge still leaves" {
    var h = try TestHarness.init();
    defer h.deinit();
    // cmp rax, rbx ; jne +0x20 ; add rax, rbx
    var jcc: DecodedInsn = .{ .op = .jcc_rel8, .cond = .ne, .addr = 0x20 };
    jcc.rip_relative = true;

    for ([_]bool{ true, false }) |equal| {
        var state = TestState{};
        state.regs.rax = 10;
        state.regs.rbx = if (equal) 10 else 11;
        h.insns.clearRetainingCapacity();
        try h.add(0x6000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        try h.add(0x6003, 2, jcc);
        try h.add(0x6005, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        const completed = try h.run(&state);
        if (equal) {
            // Not taken: the trace runs straight on into the add, which is
            // the whole point - no exit, no second block, no hash probe.
            try testing.expectEqual(@as(u32, 3), completed);
            try testing.expectEqual(@as(u64, 20), state.regs.rax);
            try testing.expectEqual(@as(u64, 0x6008), state.regs.rip);
        } else {
            // Taken: the edge leaves through its stub, with the two
            // instructions before it retired and the add untouched.
            try testing.expectEqual(@as(u32, 2), completed);
            try testing.expectEqual(@as(u64, 10), state.regs.rax);
            try testing.expectEqual(@as(u64, 0x6025), state.regs.rip);
        }
        // All three were compiled into one block either way.
        try testing.expectEqual(@as(u32, 3), h.block.native_count);
    }

    // The branch's taken edge is a block exit, so the flags of the compare
    // before it are live even though the add after it overwrites them.
    // Without that, the taken edge would leave holding stale flags.
    h.insns.clearRetainingCapacity();
    try h.add(0x6000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x6003, 2, jcc);
    try h.add(0x6005, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    var state = TestState{};
    _ = try h.run(&state);
    try testing.expectEqual(@as(u32, 0), h.flags_elided);

    // Take the branch out and the compare's flags are dead, because the add
    // overwrites every one of them before anything can read them.
    h.insns.clearRetainingCapacity();
    try h.add(0x6000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x6003, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    var state2 = TestState{};
    _ = try h.run(&state2);
    try testing.expectEqual(@as(u32, 1), h.flags_elided);

    // A conditional branch that is the block's last instruction still emits
    // both edges, because there is no next instruction to fall into.
    h.insns.clearRetainingCapacity();
    try h.add(0x6000, 3, regReg(.cmp_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    try h.add(0x6003, 2, jcc);
    var state3 = TestState{};
    state3.regs.rax = 1;
    state3.regs.rbx = 1;
    try testing.expectEqual(@as(u32, 2), try h.run(&state3));
    try testing.expectEqual(@as(u64, 0x6005), state3.regs.rip);
}

test "busy guest registers live in host registers for a whole block, and meet memory at every boundary" {
    var h = try TestHarness.init();
    defer h.deinit();

    // rax is read and written by every instruction, rbx read by every one:
    // both cross the threshold and are cached.
    h.insns.clearRetainingCapacity();
    var rip: u64 = 0x8000;
    for (0..4) |_| {
        try h.add(rip, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        rip += 3;
    }
    const insns = h.insns.items;
    const last = insns[insns.len - 1];
    const compiled = try compile(testing.allocator, &h.memory, TestState.layout, insns, last.rip + last.len);
    try testing.expect(compiled.cached_registers >= 2);

    // Executed, the cached arithmetic retires exactly what memory would have.
    var state = TestState{};
    state.regs.rax = 1;
    state.regs.rbx = 10;
    _ = try h.run(&state);
    try testing.expectEqual(@as(u64, 41), state.regs.rax);
    try testing.expectEqual(@as(u64, 10), state.regs.rbx);

    // Every sub-register width merges into the cached copy exactly as x86
    // writes it: 32 zero-extends, 16 and both 8-bit halves merge.
    h.insns.clearRetainingCapacity();
    rip = 0x8100;
    for (0..3) |_| {
        try h.add(rip, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        rip += 3;
    }
    try h.add(rip, 2, regReg(.mov_reg32_reg32, .bits32, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    rip += 2;
    var state2 = TestState{};
    state2.regs.rax = 0xFFFF_FFFF_0000_0000;
    state2.regs.rbx = 0x1111_1111_2222_2222;
    _ = try h.run(&state2);
    // mov eax, ebx: the upper half of rax is cleared, not kept.
    try testing.expectEqual(@as(u64, 0x2222_2222), state2.regs.rax);

    var high8: DecodedInsn = regReg(.mov_reg8_reg8, .bits8, .al_ax_eax_rax, .bl_bx_ebx_rbx);
    high8.dst_high8 = true; // mov ah, bl
    h.insns.clearRetainingCapacity();
    rip = 0x8200;
    for (0..3) |_| {
        try h.add(rip, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        rip += 3;
    }
    try h.add(rip, 2, high8);
    var state3 = TestState{};
    state3.regs.rax = 0x1122_3344_5566_7700;
    state3.regs.rbx = 0x01;
    _ = try h.run(&state3);
    // Three adds of 1, then bl (0x01) into ah only.
    try testing.expectEqual(@as(u64, 0x1122_3344_5566_0103), state3.regs.rax);

    // An instruction with no template in the middle: the interpreter sees
    // the cache's values in memory, and whatever it writes comes back.
    h.insns.clearRetainingCapacity();
    rip = 0x8300;
    for (0..3) |_| {
        try h.add(rip, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
        rip += 3;
    }
    try h.add(rip, 1, .{ .op = .lahf, .size = .bits64, .dst_reg = .al_ax_eax_rax, .is_reg_form = true });
    rip += 1;
    try h.add(rip, 3, regReg(.add_reg64_reg64, .bits64, .al_ax_eax_rax, .bl_bx_ebx_rbx));
    var state4 = TestState{};
    state4.regs.rax = 5;
    state4.regs.rbx = 2;
    state4.interpret_result = 0;
    _ = try h.run(&state4);
    // 5 + 2*3 = 11 in memory before the interpreter; its stub advances RIP
    // and leaves rax alone, so the add after it reads 11 back, not 5.
    try testing.expectEqual(@as(u32, 1), state4.interprets);
    try testing.expectEqual(@as(u64, 13), state4.regs.rax);
}

test {
    _ = @import("atomic_throughput_tests.zig");
    _ = @import("packed_madd.zig");
    _ = @import("completion_tests.zig");
    _ = @import("scalar_residency_tests.zig");
    _ = @import("rearrangement_residency_tests.zig");
}
