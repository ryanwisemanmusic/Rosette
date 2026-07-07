const std = @import("std");

pub const FaultClass = enum {
    opaque_identity_dereference,
    cxx_invalid_vtt,
    cxx_object_model_null_vtable,
    bad_this_pointer,
    bad_vtable_header,
    bad_streambuf_pointer,
    bad_typeinfo_pointer,
    bad_return_address,
    bad_import_thunk,
    bad_guest_stack,
    generic_memory,
};

pub const Context = struct {
    instruction: []const u8,
    symbol: []const u8,
    address: u64,
    rdi: u64,
    rsi: u64,
    rsp: u64,
    rbp: u64,
    rdx: u64 = 0,
    rdi_mapped: bool,
    rsi_mapped: bool,
    rdx_mapped: bool = false,
    stack_mapped: bool,
    pointer_opaque: bool = false,
    pointer_owner: []const u8 = "",
    vtable_header_mapped: bool = true,
    typeinfo_mapped: bool = true,
};

pub const Classification = struct {
    class: FaultClass,
    reason: []const u8,
    next_subsystem: []const u8,
};

pub fn classify(context: Context) Classification {
    if (context.pointer_opaque) {
        return .{
            .class = .opaque_identity_dereference,
            .reason = "an opaque identity token was used as memory; it may only be compared or passed back to its modeled API",
            .next_subsystem = context.pointer_owner,
        };
    }
    const near_null = context.address < 0x1000 or context.address >= std.math.maxInt(u64) - 0x1000;
    const stream_symbol = std.mem.indexOf(u8, context.symbol, "basic_ostream") != null or
        std.mem.indexOf(u8, context.symbol, "basic_ostringstream") != null or
        std.mem.indexOf(u8, context.symbol, "basic_istream") != null or
        std.mem.indexOf(u8, context.symbol, "basic_istringstream") != null or
        std.mem.indexOf(u8, context.symbol, "basic_ios") != null;
    // Missing vtable/typeinfo evidence is meaningful only while executing an
    // object-model operation. A generic mangled C++ function may use RDI for
    // any value at all (cpuid does), so treating every __ZN symbol as an object
    // method produces confident but unrelated diagnoses.
    const cxx_object_symbol = stream_symbol or
        std.mem.indexOf(u8, context.symbol, "dynamic_cast") != null or
        std.mem.indexOf(u8, context.symbol, "__dynamic_cast") != null or
        std.mem.indexOf(u8, context.symbol, "vtable") != null or
        std.mem.indexOf(u8, context.symbol, "type_info") != null;
    if (stream_symbol and near_null and context.rsi < 0x1000 and context.rdx_mapped) {
        return .{
            .class = .cxx_invalid_vtt,
            .reason = "libc++ basic_ostream base construction received a null/low hidden VTT while the declared streambuf remained valid in RDX",
            .next_subsystem = "libcpp_stream_bridge / cxx_object_model / itanium_vtable_builder",
        };
    }
    if (stream_symbol and near_null) {
        return .{
            .class = .cxx_object_model_null_vtable,
            .reason = "C++ stream code dereferenced a null/low vtable-derived address; the instruction is likely valid but object initialization is incomplete",
            .next_subsystem = "cxx_object_model / itanium_vtable_builder / libcpp_stream_bridge",
        };
    }
    if (stream_symbol and (!context.rsi_mapped or context.rsi < 0x1000)) {
        return .{ .class = .bad_streambuf_pointer, .reason = "stream constructor received an invalid streambuf pointer", .next_subsystem = "cxx_object_model / libcpp_stream_bridge" };
    }
    if (cxx_object_symbol and !context.vtable_header_mapped) {
        return .{ .class = .bad_vtable_header, .reason = "object vptr exists but its Itanium negative header is not readable", .next_subsystem = "itanium_vtable_builder" };
    }
    if (cxx_object_symbol and !context.typeinfo_mapped) {
        return .{ .class = .bad_typeinfo_pointer, .reason = "dynamic typeinfo pointer is not guest-backed", .next_subsystem = "itanium_dynamic_cast / itanium_vtable_builder" };
    }
    if (std.mem.eql(u8, context.instruction, "ret") and near_null) {
        return .{ .class = .bad_return_address, .reason = "RET selected an unmapped return address", .next_subsystem = "call stack / unwind runtime" };
    }
    if ((std.mem.indexOf(u8, context.instruction, "jmp") != null or std.mem.indexOf(u8, context.instruction, "call") != null) and near_null) {
        return .{ .class = .bad_import_thunk, .reason = "indirect import control transfer resolved to zero or a low address", .next_subsystem = "import resolver / dyld bindings" };
    }
    if (!context.stack_mapped) {
        return .{ .class = .bad_guest_stack, .reason = "RSP/RBP escaped the registered guest stack", .next_subsystem = "guest scheduler / stack allocator" };
    }
    if ((!context.rdi_mapped and context.rdi != 0) or (!context.rsi_mapped and context.rsi != 0)) {
        return .{ .class = .bad_this_pointer, .reason = "pointer-like argument is outside all guest mappings", .next_subsystem = "pointer_firewall / calling convention bridge" };
    }
    return .{ .class = .generic_memory, .reason = "memory access is outside the active guest mapping", .next_subsystem = "memory provenance / decoder" };
}

test "plain C++ namespace functions do not imply a typeinfo fault" {
    const result = classify(.{
        .instruction = "xchg_mem64_reg64",
        .symbol = "__ZN2xe12_GLOBAL__N_15cpuidEjjPj",
        .address = 0,
        .rdi = 0x1000,
        .rsi = 0,
        .rsp = 0x8000,
        .rbp = 0x8000,
        .rdi_mapped = true,
        .rsi_mapped = false,
        .stack_mapped = true,
        .vtable_header_mapped = false,
        .typeinfo_mapped = false,
    });
    try std.testing.expectEqual(FaultClass.generic_memory, result.class);
}

test "stream near-null faults identify object model rather than arithmetic" {
    const result = classify(.{
        .instruction = "add_reg64_mem64",
        .symbol = "__ZNSt3__113basic_ostreamIcEEC2EPNS_15basic_streambufIcEE",
        .address = std.math.maxInt(u64) - 23,
        .rdi = 0x1000,
        .rsi = 8,
        .rsp = 0x8000,
        .rbp = 0x8100,
        .rdi_mapped = true,
        .rsi_mapped = false,
        .stack_mapped = true,
    });
    try std.testing.expectEqual(FaultClass.cxx_object_model_null_vtable, result.class);
}

test "basic ostream C2 fault identifies invalid hidden VTT" {
    const result = classify(.{
        .instruction = "add_reg64_mem64",
        .symbol = "__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEEC2B7v160006EPNS_15basic_streambufIcS2_EE",
        .address = std.math.maxInt(u64) - 23,
        .rdi = 0x1ffffa98,
        .rsi = 8,
        .rdx = 0x1ffffaa0,
        .rsp = 0x1ffff8d0,
        .rbp = 0x1ffff8f0,
        .rdi_mapped = true,
        .rsi_mapped = false,
        .rdx_mapped = true,
        .stack_mapped = true,
    });
    try std.testing.expectEqual(FaultClass.cxx_invalid_vtt, result.class);
}

test "opaque identities are never classified as generic memory" {
    const result = classify(.{
        .instruction = "mov_reg64_mem64",
        .symbol = "caller",
        .address = 0xfffffe0000000010,
        .rdi = 0xfffffe0000000010,
        .rsi = 0,
        .rsp = 0x8000,
        .rbp = 0,
        .rdi_mapped = false,
        .rsi_mapped = false,
        .stack_mapped = true,
        .pointer_opaque = true,
        .pointer_owner = "Objective-C selector identity",
    });
    try std.testing.expectEqual(FaultClass.opaque_identity_dereference, result.class);
}
