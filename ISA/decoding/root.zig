//! Universal x86-64 decoder — module entry point (formerly src/x64-ASM/decoder.zig).
//!
//! Split into instruction-family modules under ISA/decoding/. This hub
//! re-exports the full public API so consumers keep using `x64_decoder.*`.
//!
//! Families:
//!   - addressing: ModRM, SIB, segment selection, effective-address resolution
//!   - cpu: bit scan, popcount, byte swap, CRC32C, emulated CPUID/XCR0
//!   - groups: ModRM-group opcode families (0x80-0xFF groups, movzx/movsx/...)
//!   - legacy: legacy 1-byte opcodes: MOV family + main dispatch + accumulator immediates
//!   - prefix: legacy / VEX / EVEX prefix decoding
//!   - twobyte: 0F two-byte / three-byte opcodes + SSE byte decode
//!   - types: core types, Op enum, register/flag re-exports, ISA ABI contract
//!   - vex: VEX / EVEX encoded families (VEX2/VEX3, half/duplicate moves)

const addressing = @import("addressing.zig");
const cpu = @import("cpu.zig");
const groups = @import("groups.zig");
const legacy = @import("legacy.zig");
const prefix = @import("prefix.zig");
const twobyte = @import("twobyte.zig");
const types = @import("types.zig");
const vex = @import("vex.zig");

pub const decodeRegister = addressing.decodeRegister;
pub const defaultSegment = addressing.defaultSegment;
pub const selectSegment = addressing.selectSegment;
pub const segmentBase = addressing.segmentBase;
pub const resolveMemoryAddress = addressing.resolveMemoryAddress;
pub const decodeMemoryOperand = addressing.decodeMemoryOperand;
pub const decodeModRm = addressing.decodeModRm;
pub const hasModRM = addressing.hasModRM;
pub const mapReg = addressing.mapReg;
pub const mapJccCond8 = addressing.mapJccCond8;
pub const mapJccCond32 = addressing.mapJccCond32;
pub const readModRM = addressing.readModRM;
pub const populationCount = cpu.populationCount;
pub const bitScan = cpu.bitScan;
pub const byteSwap = cpu.byteSwap;
pub const crc32cAccumulator = cpu.crc32cAccumulator;
pub const CpuidResult = cpu.CpuidResult;
pub const emulatedCpuid = cpu.emulatedCpuid;
pub const emulatedXcr0 = cpu.emulatedXcr0;
pub const decodeArithRmReg = groups.decodeArithRmReg;
pub const decodeMovRmReg = groups.decodeMovRmReg;
pub const decodeLea = groups.decodeLea;
pub const decodePopRm = groups.decodePopRm;
pub const decodeGroup1Imm = groups.decodeGroup1Imm;
pub const decodeGroup2Shift = groups.decodeGroup2Shift;
pub const decodeMovMemImm = groups.decodeMovMemImm;
pub const decodeGroup3 = groups.decodeGroup3;
pub const decodeGroup4_5 = groups.decodeGroup4_5;
pub const decodeTestRmReg = groups.decodeTestRmReg;
pub const decodeXchgRmReg = groups.decodeXchgRmReg;
pub const decodeImulImm = groups.decodeImulImm;
pub const decodeImulTwoOp = groups.decodeImulTwoOp;
pub const decodeCmpxchg = groups.decodeCmpxchg;
pub const decodeMovzx = groups.decodeMovzx;
pub const decodeMovsx = groups.decodeMovsx;
pub const decodeXadd = groups.decodeXadd;
pub const decodeSetcc = groups.decodeSetcc;
pub const decodeMovupsMovss = groups.decodeMovupsMovss;
pub const decodeMovaps = groups.decodeMovaps;
pub const registerOperandValue = legacy.registerOperandValue;
pub const setRegisterOperand = legacy.setRegisterOperand;
pub const decodeLegacyMov = legacy.decodeLegacyMov;
pub const decodeLegacyInstruction = legacy.decodeLegacyInstruction;
pub const x87BinaryOperation = legacy.x87BinaryOperation;
pub const decodeAccumulatorImmediate = legacy.decodeAccumulatorImmediate;
pub const LegacyPrefixes = prefix.LegacyPrefixes;
pub const VexPrefix = prefix.VexPrefix;
pub const EvexPrefix = prefix.EvexPrefix;
pub const decodeLegacyPrefixes = prefix.decodeLegacyPrefixes;
pub const decodeVexPrefix = prefix.decodeVexPrefix;
pub const decodeEvexPrefix = prefix.decodeEvexPrefix;
pub const decodeTwoByte = twobyte.decodeTwoByte;
pub const decodeThreeByte = twobyte.decodeThreeByte;
pub const decodeSseBytes = twobyte.decodeSseBytes;
pub const highway = types.highway;
pub const isa_decode = types.isa_decode;
pub const capabilities = types.capabilities;
pub const OperandSize = types.OperandSize;
pub const Condition = types.Condition;
pub const Size = types.Size;
pub const Cond = types.Cond;
pub const RegId = types.RegId;
pub const Regs = types.Regs;
pub const Segment = types.Segment;
pub const SegmentState = types.SegmentState;
pub const ExecutionMode = types.ExecutionMode;
pub const MemoryReferenceKind = types.MemoryReferenceKind;
pub const RFL_CF = types.RFL_CF;
pub const RFL_PF = types.RFL_PF;
pub const RFL_AF = types.RFL_AF;
pub const RFL_ZF = types.RFL_ZF;
pub const RFL_SF = types.RFL_SF;
pub const RFL_OF = types.RFL_OF;
pub const statusByteForLahf = types.statusByteForLahf;
pub const applySahf = types.applySahf;
pub const BitTestOperation = types.BitTestOperation;
pub const bitTestRegister = types.bitTestRegister;
pub const bitTestAndResetRegister = types.bitTestAndResetRegister;
pub const bitTestMemoryOperand = types.bitTestMemoryOperand;
pub const bitTestMemoryOperandImmediate = types.bitTestMemoryOperandImmediate;
pub const RegisterOperand = types.RegisterOperand;
pub const MemoryOperand = types.MemoryOperand;
pub const RmOperand = types.RmOperand;
pub const DecodedModRm = types.DecodedModRm;
pub const applySub = types.applySub;
pub const applySbb = types.applySbb;
pub const applyAdd = types.applyAdd;
pub const applyIncDec = types.applyIncDec;
pub const applyLogic = types.applyLogic;
pub const evalCond = types.evalCond;
pub const regVal = types.regVal;
pub const setReg = types.setReg;
pub const BitScanKind = types.BitScanKind;
pub const BitScanResult = types.BitScanResult;
pub const PopulationCountResult = types.PopulationCountResult;
pub const Op = types.Op;
pub const DecodedInsn = types.DecodedInsn;
pub const decodeVexInstruction = vex.decodeVexInstruction;
pub const decodeVex2 = vex.decodeVex2;
pub const decodeVex3 = vex.decodeVex3;
pub const decodeVexHalfMove = vex.decodeVexHalfMove;
pub const decodeVexDuplicateMove = vex.decodeVexDuplicateMove;
