const std = @import("std");

/// Ownership of the state that selected an invalid instruction pointer.
/// This is deliberately separate from the process that happened to stop:
/// Rosette always detects the failure, but it does not always produce it.
pub const Owner = enum {
    rosette_runtime,
    translated_program,
    dynamic_linker,
    indeterminate,
};

pub const FaultClass = enum {
    synthetic_vtable_slot_contains_data,
    synthetic_vtable_slot_unimplemented,
    synthetic_callable_rejected,
    import_slot_invalid,
    translated_function_pointer_invalid,
    return_address_invalid,
    indirect_operand_unmapped,
    invalid_target,
};

pub const Context = struct {
    kind: []const u8,
    caller_symbol: []const u8 = "",
    operand_address: u64 = 0,
    operand_value: u64 = 0,
    operand_mapped: bool = false,
    operand_region_synthetic: bool = false,
    operand_region_owner: []const u8 = "",
    target_address: u64,
    target_mapped: bool = false,
    target_executable: bool = false,
    candidate_import: []const u8 = "",
    object_address: u64 = 0,
    object_mapped: bool = false,
    object_vptr: u64 = 0,
    vptr_region_synthetic: bool = false,
    vptr_region_owner: []const u8 = "",
};

pub const Classification = struct {
    owner: Owner,
    class: FaultClass,
    evidence: []const u8,
    next_subsystem: []const u8,
    virtual_slot_offset: u64 = 0,
    target_looks_ascii: bool = false,
};

pub fn classify(context: Context) Classification {
    const slot_offset = virtualSlotOffset(context);
    const target_looks_ascii = looksLikeAsciiData(context.target_address);
    const synthetic_vtable_dispatch =
        context.vptr_region_synthetic and slot_offset != null;

    if (synthetic_vtable_dispatch) {
        if (target_looks_ascii) {
            return .{
                .owner = .rosette_runtime,
                .class = .synthetic_vtable_slot_contains_data,
                .evidence = "Rosette supplied the object vptr, and the selected synthetic virtual slot contains printable data rather than a callable address",
                .next_subsystem = "cxx_object_model / itanium_vtable_builder / synthetic thunk registry",
                .virtual_slot_offset = slot_offset.?,
                .target_looks_ascii = true,
            };
        }
        return .{
            .owner = .rosette_runtime,
            .class = .synthetic_vtable_slot_unimplemented,
            .evidence = "Rosette supplied the object vptr, but the selected synthetic virtual slot is not callable",
            .next_subsystem = "cxx_object_model / itanium_vtable_builder / synthetic thunk registry",
            .virtual_slot_offset = slot_offset.?,
        };
    }

    if (context.operand_region_synthetic) {
        return .{
            .owner = .rosette_runtime,
            .class = .synthetic_callable_rejected,
            .evidence = "the invalid target was loaded from Rosette-owned synthetic memory",
            .next_subsystem = if (context.operand_region_owner.len != 0)
                context.operand_region_owner
            else
                "synthetic ABI materialization",
            .target_looks_ascii = target_looks_ascii,
        };
    }

    if (context.candidate_import.len != 0) {
        return .{
            .owner = .dynamic_linker,
            .class = .import_slot_invalid,
            .evidence = "a Mach-O import slot resolved to a non-callable target",
            .next_subsystem = "dyld binding / import resolver / typed import contract",
            .target_looks_ascii = target_looks_ascii,
        };
    }

    if (std.mem.startsWith(u8, context.kind, "ret")) {
        return .{
            .owner = .indeterminate,
            .class = .return_address_invalid,
            .evidence = "a return selected a non-executable address; stack corruption and Rosette unwind/call modeling must be distinguished",
            .next_subsystem = "call stack provenance / Itanium unwinder / scheduler context",
            .target_looks_ascii = target_looks_ascii,
        };
    }

    if (context.operand_address != 0 and !context.operand_mapped) {
        return .{
            .owner = .indeterminate,
            .class = .indirect_operand_unmapped,
            .evidence = "the indirect pointer slot itself is unmapped, so no stored function pointer can be attributed safely",
            .next_subsystem = "pointer provenance / decoder effective-address calculation",
        };
    }

    if (context.operand_mapped or context.operand_address == 0) {
        return .{
            .owner = .translated_program,
            .class = .translated_function_pointer_invalid,
            .evidence = if (target_looks_ascii)
                "translated program state used printable data as a function pointer, with no Rosette synthetic-vtable or import ownership evidence"
            else
                "translated program state selected a non-executable function pointer, with no Rosette synthetic-vtable or import ownership evidence",
            .next_subsystem = if (context.caller_symbol.len != 0)
                "Xenia call-site object/function-pointer lifetime"
            else
                "translated program function-pointer lifetime",
            .target_looks_ascii = target_looks_ascii,
        };
    }

    return .{
        .owner = .indeterminate,
        .class = .invalid_target,
        .evidence = "the invalid target lacks enough provenance to assign ownership",
        .next_subsystem = "control-transfer provenance",
        .target_looks_ascii = target_looks_ascii,
    };
}

pub fn ownerLabel(owner: Owner) []const u8 {
    return switch (owner) {
        .rosette_runtime => "Rosette runtime",
        .translated_program => "translated guest program",
        .dynamic_linker => "Rosette dyld/import bridge",
        .indeterminate => "indeterminate",
    };
}

fn virtualSlotOffset(context: Context) ?u64 {
    if (!context.object_mapped or context.object_vptr == 0) return null;
    if (context.operand_address < context.object_vptr) return null;
    const offset = context.operand_address - context.object_vptr;
    if (offset >= 0x400 or offset % @sizeOf(u64) != 0) return null;
    return offset;
}

fn looksLikeAsciiData(value: u64) bool {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    var printable: usize = 0;
    var terminated = false;
    for (bytes) |byte| {
        if (byte == 0) {
            terminated = true;
            continue;
        }
        if (terminated or byte < 0x20 or byte > 0x7E) return false;
        printable += 1;
    }
    return printable >= 3;
}

test "synthetic streambuf slot containing a type name belongs to Rosette" {
    const result = classify(.{
        .kind = "call_mem64",
        .caller_symbol = "__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE8pubimbueB7v160006ERKNS_6localeE",
        .operand_address = 0x68CBB48,
        .operand_value = 0x6D6165727473,
        .operand_mapped = true,
        .target_address = 0x6D6165727473,
        .object_address = 0x7FFFDEA0,
        .object_mapped = true,
        .object_vptr = 0x68CBB38,
        .vptr_region_synthetic = true,
        .vptr_region_owner = "basic_streambuf",
    });
    try std.testing.expectEqual(Owner.rosette_runtime, result.owner);
    try std.testing.expectEqual(FaultClass.synthetic_vtable_slot_contains_data, result.class);
    try std.testing.expectEqual(@as(u64, 0x10), result.virtual_slot_offset);
    try std.testing.expect(result.target_looks_ascii);
}

test "native mapped function pointer without bridge ownership belongs to translated program" {
    const result = classify(.{
        .kind = "call_mem64",
        .caller_symbol = "__ZN2xe3gpu16CommandProcessor16WorkerThreadMainEv",
        .operand_address = 0x4761EE8,
        .operand_value = 0xDEADBEEF,
        .operand_mapped = true,
        .target_address = 0xDEADBEEF,
        .object_address = 0x4761E80,
        .object_mapped = true,
        .object_vptr = 0x194D288,
    });
    try std.testing.expectEqual(Owner.translated_program, result.owner);
    try std.testing.expectEqual(FaultClass.translated_function_pointer_invalid, result.class);
}

test "invalid import target remains bridge-owned" {
    const result = classify(.{
        .kind = "jmp_mem64",
        .operand_address = 0x1984000,
        .operand_value = 0,
        .operand_mapped = true,
        .target_address = 0,
        .candidate_import = "_pthread_create",
    });
    try std.testing.expectEqual(Owner.dynamic_linker, result.owner);
    try std.testing.expectEqual(FaultClass.import_slot_invalid, result.class);
}
