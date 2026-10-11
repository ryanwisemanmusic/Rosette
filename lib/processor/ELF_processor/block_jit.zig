//! Public facade for the ARM64 block translator. Implementation and tests live
//! in separate files so callers keep the same API while the translator source
//! stays reviewable.
const core = @import("block_jit/core.zig");

pub const Assembler = core.Assembler;
pub const Label = core.Label;
pub const CodeMemory = core.CodeMemory;
pub const CodeMemoryError = core.CodeMemoryError;
pub const DecodedInsn = core.DecodedInsn;
pub const Op = core.Op;
pub const RegId = core.RegId;
pub const Size = core.Size;
pub const Cond = core.Cond;
pub const Segment = core.Segment;
pub const Regs = core.Regs;
pub const Error = core.Error;
pub const Helpers = core.Helpers;
pub const Scratch = core.Scratch;
pub const chain_count_shift = core.chain_count_shift;
pub const chain_count_blocks_mask = core.chain_count_blocks_mask;
pub const FlagKind = core.FlagKind;
pub const Tlb = core.Tlb;
pub const Layout = core.Layout;
pub const RegisterFiles = core.RegisterFiles;
pub const hook_filter_bytes = core.hook_filter_bytes;
pub const hookFilterBit = core.hookFilterBit;
pub const hookFilterAdd = core.hookFilterAdd;
pub const hookFilterHas = core.hookFilterHas;
pub const FallbackReason = core.FallbackReason;
pub const Insn = core.Insn;
pub const BlockFn = core.BlockFn;
pub const Block = core.Block;
pub const link_ways = core.link_ways;
pub const Link = core.Link;
pub const jump_cache_entries = core.jump_cache_entries;
pub const jump_cache_shift = core.jump_cache_shift;
pub const jumpCacheIndex = core.jumpCacheIndex;
pub const Compiled = core.Compiled;
pub const isNative = core.isNative;
pub const isTerminator = core.isTerminator;
pub const isConditionalBranch = core.isConditionalBranch;
pub const isFallbackTerminator = core.isFallbackTerminator;
pub const endsBlockBefore = core.endsBlockBefore;
pub const flagEffects = core.flagEffects;
pub const flagWants = core.flagWants;
pub const flagLiveness = core.flagLiveness;
pub const flagLivenessToExit = core.flagLivenessToExit;
pub const flagLivenessToExitFall = core.flagLivenessToExitFall;
pub const FusedKind = core.FusedKind;
pub const Fused = core.Fused;
pub const fusedCondition = core.fusedCondition;
pub const flagLivenessFrom = core.flagLivenessFrom;
pub const lockPrefixAllowed = core.lockPrefixAllowed;
pub const isVectorNative = core.isVectorNative;
pub const Ledger = core.Ledger;
pub const Options = core.Options;
pub const isCallOrReturn = core.isCallOrReturn;
pub const returnFlagsLive = core.returnFlagsLive;
pub const exitFlagsLive = core.exitFlagsLive;
pub const compile = core.compile;
pub const compileWith = core.compileWith;

test {
    _ = @import("block_jit/tests.zig");
}
