//! Vtable ownership library.
//!
//! Polls and classifies vtable values to answer the question:
//! "Is this vtable host-side (dyld-resolved `_ZTV` symbol) or guest-side
//! (written at runtime by guest constructor code)?"
//!
//! ## Capabilities
//!
//! 1. **`classifyOrigin(value, metadata)`** — classify a vtable VALUE by
//!    checking whether its nearest symbol is an Itanium `_ZTV` symbol.
//!    Returns `host_resolved` (from the binary) or `unknown`.
//!
//! 2. **`checkConsistency(object_address, vtable_value, this_pointer,
//!    writer_rip, metadata)`** — validate a vtable write BEFORE it happens.
//!    Catches null `this` pointers and invalid vtable values without
//!    modifying any state.
//!
//! ## Integration
//!
//! Call `classifyOrigin` from crash diagnostics (e.g. `near_null_causality.zig`)
//! to enrich terminal output with ownership context.  The library is purely
//! diagnostic — it never modifies guest memory or tracker state.

const std = @import("std");
const types = @import("types.zig");

/// Origin of a vtable value.  Separates host-side (dyld-resolved symbols
/// from the Mach-O binary) from guest-side (runtime constructor writes).
pub const VtableOrigin = enum {
    /// Value points into a `_ZTV` symbol resolved by Rosette's dyld binding
    /// system.  The vtable was compiled into Xenia's binary and linked at
    /// image load time.  This is the **host side**.
    host_resolved,

    /// Value was written at runtime by guest constructor code and tracked
    /// by the `VtableTracker`.  The vtable was established during execution
    /// (e.g. a heap-allocated object's constructor ran).  This is the
    /// **guest side**.
    guest_written,

    /// Could not determine origin.  The value may not be a vtable address
    /// point at all (small integer, non-ZTV symbol, unaligned, etc.).
    unknown,
};

/// Full ownership poll result for an object address.
pub const ObjectVtableState = struct {
    /// The object address that was polled.
    object_address: u64,

    /// The current vptr value at the object address (0 if unreadable).
    current_vptr: u64,

    /// Origin classification of the vptr value.
    origin: VtableOrigin = .unknown,

    // ---- host-resolved fields ----
    /// If host_resolved, the `_ZTV` symbol name.
    host_symbol: ?[]const u8 = null,

    /// If host_resolved, offset within the `_ZTV` symbol.
    host_offset: i64 = -1,

    // ---- guest-written fields ----
    /// If guest_written, the tracker generation.
    guest_generation: u64 = 0,

    /// If guest_written, who established this vtable.
    guest_established_by: types.Provenance = .{},

    /// If guest_written, the last write provenance.
    guest_last_write: types.Provenance = .{},

    /// If guest_written, number of valid transitions.
    guest_transitions: u64 = 0,

    /// If guest_written, number of recoveries.
    guest_recoveries: u64 = 0,
};

/// Result of a consistency check on a vtable write.
/// Distinguishes between host-side vtable issues, guest-side null-this
/// bugs, and unrecognized values.
pub const ConsistencyResult = union(enum) {
    /// Vtable write is valid and ownership is understood.  The vtable
    /// is a recognized Itanium address point and the `this` pointer
    /// is non-null.
    valid,

    /// The `this` pointer is null — the constructor was called on a
    /// null object.  This is a **guest-side** bug (Xenia's init ordering
    /// or a null pointer dereference in constructor code).
    null_this: struct {
        vtable_value: u64,
        origin: VtableOrigin,
        writer_rip: u64,
    },

    /// The vtable value is not recognized as a valid Itanium vtable.
    /// This could be a host-side issue (corrupted symbol) or a
    /// guest-side issue (wrong value written).
    invalid_vtable: struct {
        value: u64,
        writer_rip: u64,
    },
};

/// Classify the origin of a vtable VALUE.
///
/// Checks whether the value's nearest symbol is an Itanium `_ZTV` symbol
/// with a valid address point offset (>= 16, <= 0x1000).
///
/// - `host_resolved` — the value falls within a `_ZTV` symbol in the
///   Mach-O binary.  Rosette's dyld binding system resolved it.
/// - `unknown` — the value is not a recognized vtable address point.
///   It may be a small integer, a non-vtable symbol, or an unaligned value.
pub fn classifyOrigin(value: u64, metadata: anytype) VtableOrigin {
    if (value < 0x1000 or (value & 7) != 0) return .unknown;
    const symbol = metadata.nearestSymbol(value) orelse return .unknown;
    if (!types.isItaniumVtableSymbol(symbol.name)) return .unknown;
    if (symbol.offset < 16) return .unknown;
    if (symbol.offset > 0x1000) return .unknown;
    return .host_resolved;
}

/// Perform a consistency check BEFORE a vtable write.
///
/// Validates:
/// 1. The `this` pointer is non-null — constructor called on valid object
/// 2. The vtable value is a recognized Itanium address point
///
/// This is a **purely diagnostic** check.  It never modifies guest memory,
/// tracker state, or execution flow.  The caller decides what to do with
/// the result.
pub fn checkConsistency(
    object_address: u64,
    vtable_value: u64,
    this_pointer: u64,
    writer_rip: u64,
    metadata: anytype,
) ConsistencyResult {
    _ = object_address;

    // Check 1: null this pointer
    // The most common vtable-related crash in static init: a C++ global
    // constructor is called with `this=nullptr`.  This is a guest-side
    // bug (Xenia's init ordering).
    if (this_pointer == 0) {
        const origin = classifyOrigin(vtable_value, metadata);
        return .{ .null_this = .{
            .vtable_value = vtable_value,
            .origin = origin,
            .writer_rip = writer_rip,
        } };
    }

    // Check 2: validate vtable identity
    const origin = classifyOrigin(vtable_value, metadata);
    if (origin == .unknown) {
        return .{ .invalid_vtable = .{
            .value = vtable_value,
            .writer_rip = writer_rip,
        } };
    }

    return .valid;
}
