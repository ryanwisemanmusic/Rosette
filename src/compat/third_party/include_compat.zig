const source_include_compat = @import("../source/include_compat.zig");
const source_build_helper = @import("../source/build_helper.zig");
const source_narrow = @import("../source/narrow.zig");
const source_c_tokenizer = @import("../../../lib/transpiler/c_tokenizer.zig");

pub const discoverIncludeDirs = source_include_compat.discoverIncludeDirs;
pub const hasHeaderExtension = source_include_compat.hasHeaderExtension;
pub const isStandardHeaderShadowName = source_include_compat.isStandardHeaderShadowName;
pub const isSimdBridgeDir = source_include_compat.isSimdBridgeDir;
pub const pathContainsSimdBridgeDir = source_include_compat.pathContainsSimdBridgeDir;

pub const isX86IntrinsicShadowHeaderName = source_include_compat.isX86IntrinsicShadowHeaderName;
pub const containsX86IntrinsicShadow = source_include_compat.containsX86IntrinsicShadow;
pub const scanForEndianHeaderUsage = source_include_compat.scanForEndianHeaderUsage;
pub const scanForAsmKeyword = source_include_compat.scanForAsmKeyword;
pub const scanForAngleBracketLocalIncludes = source_include_compat.scanForAngleBracketLocalIncludes;
pub const scanForShorten64To32Risk = source_include_compat.scanForShorten64To32Risk;
pub const detectCapstoneUsage = source_include_compat.detectCapstoneUsage;
pub const detectBitcodeParserUsage = source_include_compat.detectBitcodeParserUsage;

pub const addMacOSCompatIncludePath = source_build_helper.addMacOSCompatIncludePath;
pub const compatCFlags = source_build_helper.compatCFlags;
pub const stbCompatCFlag = source_build_helper.stbCompatCFlag;
pub const posixCompatCFlag = source_build_helper.posixCompatCFlag;

pub const scanForStbAssertUsage = source_include_compat.scanForStbAssertUsage;
pub const scanForSecureGetenvUsage = source_include_compat.scanForSecureGetenvUsage;
pub const scanForAtomicVarInitUsage = source_include_compat.scanForAtomicVarInitUsage;

pub const narrow = source_narrow;
pub const c_tokenizer = source_c_tokenizer;
