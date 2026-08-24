//! Route-independent: what a near-null address *is*, before anyone decides what
//! to do about it.
//!
//! Three kinds of fact live here, and all three are settled before a process
//! starts:
//!
//!   1. **The address-space bound.** On x86-64 Darwin the first page is
//!      unmapped by construction, so no object can begin below it. That is what
//!      makes a small pointer diagnosable at all rather than merely unusual.
//!   2. **The Itanium mangling rule** that identifies a non-static C++ member
//!      function, and therefore identifies when RDI is `this`.
//!   3. **The layout of the libc++ types Rosette actually sees at a fault**, and
//!      the arithmetic those layouts imply. This is the part that turns a bare
//!      "RDI was 0" into a structural statement.
//!
//! ## The arithmetic, because it is the point of the package
//!
//! `std::vector` is `{begin, end, capacity}`, so `data()` is the word at offset
//! zero and `&v[i]` is `data() + i * sizeof(T)`. When the vector is empty,
//! `data()` is null and `&v[i]` is **exactly** `i * sizeof(T)` — a small
//! constant, not a corrupted pointer. `unique_ptr` stores its pointer at offset
//! zero, so `operator->()` on `&v[i]` loads from that same small constant.
//!
//! A run that dies with `receiver=0x0 member_offset=0x0` inside
//! `unique_ptr<T>::operator->()` is therefore not reporting a pointer that got
//! zeroed. It is reporting `&container[0]` where the container is **empty**, and
//! the question to ask is which code failed to fill it — not which code
//! clobbered a pointer. Those are different investigations, and the run above
//! spent its evidence on the wrong one.
//!
//! ## What this package is not
//!
//! * It is not policy. Whether a near-null dereference may be tolerated, and
//!   whether Rosette may manufacture storage for it, stays in
//!   `lib/runtime/process-core/near_null_contract.zig`. This package only says
//!   what the address looks like.
//! * It never claims to know the container's element type. It reports which
//!   element sizes are *consistent* with an observed offset, and an offset
//!   consistent with several is reported as consistent with several.
//! * It reads no memory. Every function here is arithmetic on values the caller
//!   already has.

const std = @import("std");

pub const guest_abi = "sysv-x86_64";
pub const host_platform = "darwin";

/// The first address at which a real object may begin.
///
/// Darwin maps no page at zero and the x86-64 page size is 4 KiB, so any
/// address below this is either a null pointer, a small integer that reached a
/// pointer register, or a field/element displacement applied to a null base.
/// Rosette used to spell this bound `0x1000` separately in the predictor, the
/// causality engine and the memory views; a single definition is what stops
/// three copies from disagreeing about what counts as near-null.
pub const page_size: u64 = 0x1000;
pub const near_null_limit: u64 = page_size;

/// Whether an address is too low to be the start of any mapped object.
pub fn isNearNull(address: u64) bool {
    return address < near_null_limit;
}

/// Element sizes that a displacement is checked against.
///
/// Deliberately short and deliberately ordered small-first. These are the
/// widths that dominate the containers Rosette sees at a fault: pointers and
/// `unique_ptr` (8), `shared_ptr` and small pairs (16), `std::string` (24), and
/// the 32-byte aggregates Xenia builds out of a flags word plus a vector. A
/// longer list would make almost every offset "consistent with something",
/// which is the same as saying nothing.
pub const candidate_element_sizes = [_]u64{ 8, 16, 24, 32 };

/// What a near-null receiver value looks like structurally.
///
/// This is a statement about arithmetic, not about blame. Two different bugs
/// can produce the same shape, and the shape narrows which one to look for
/// rather than deciding it.
pub const ReceiverShape = enum(u8) {
    /// Exactly zero. Consistent with a null pointer that was stored, returned,
    /// or never assigned — and equally with `&container[0]` on an **empty**
    /// container, because indexing element zero of an empty container adds
    /// nothing to a null base.
    exact_zero,
    /// A small non-zero value that is an exact multiple of a plausible element
    /// size. Consistent with `&container[n]` on an empty container: the index
    /// scaled by the element width, applied to a null base.
    element_displacement,
    /// A small non-zero value that is not a clean element multiple. Consistent
    /// with a member access on a null object pointer — `this->field` where
    /// `this` is null — which lands at the field's own offset.
    member_displacement,
    /// Not near-null at all.
    mapped,

    pub fn label(self: ReceiverShape) []const u8 {
        return switch (self) {
            .exact_zero => "exact-zero",
            .element_displacement => "element-displacement",
            .member_displacement => "member-displacement",
            .mapped => "mapped",
        };
    }

    /// Whether an empty-container reading is among the shapes consistent with
    /// this value.
    ///
    /// True for both near-null non-mapped shapes that indexing can produce.
    /// It is never a conclusion on its own: `exact_zero` is equally consistent
    /// with a plain null pointer, and the caller must say so.
    pub fn admitsEmptyContainer(self: ReceiverShape) bool {
        return self == .exact_zero or self == .element_displacement;
    }
};

/// Classify a receiver value by arithmetic alone.
pub fn classifyReceiver(receiver: u64) ReceiverShape {
    if (!isNearNull(receiver)) return .mapped;
    if (receiver == 0) return .exact_zero;
    for (candidate_element_sizes) |size| {
        if (receiver % size == 0) return .element_displacement;
    }
    return .member_displacement;
}

/// The element sizes an `element_displacement` is consistent with, written into
/// `buffer` and returned as a slice.
///
/// Plural on purpose. An offset of 0x40 divides by 8, 16 and 32, and a reader
/// deciding which container they are looking at needs to see that it is
/// ambiguous rather than be handed the first match as though it were the
/// answer.
pub fn consistentElementSizes(receiver: u64, buffer: []u64) []const u64 {
    var count: usize = 0;
    if (receiver == 0 or !isNearNull(receiver)) return buffer[0..0];
    for (candidate_element_sizes) |size| {
        if (receiver % size != 0) continue;
        if (count >= buffer.len) break;
        buffer[count] = size;
        count += 1;
    }
    return buffer[0..count];
}

/// The index an empty-container reading implies for a given element size.
///
/// `&v[i]` on an empty vector is `i * sizeof(T)`, so the index is the exact
/// quotient. Returns null when the value is not a clean multiple, which is the
/// same condition that makes the reading inapplicable.
pub fn impliedContainerIndex(receiver: u64, element_size: u64) ?u64 {
    if (element_size == 0) return null;
    if (!isNearNull(receiver)) return null;
    if (receiver % element_size != 0) return null;
    return receiver / element_size;
}

/// libc++ layout facts that make the arithmetic above readable.
///
/// Each entry is a member offset that is zero in the libc++ ABI, which is why
/// a fault on such an access reports the container's own address rather than a
/// displaced one. These are ABI-stable: changing them would break every
/// compiled library on the system, so they are exactly as fixed as the mangling
/// rules beside them.
pub const zero_offset_accessors = [_][]const u8{
    // `unique_ptr::operator->` and `::get` load the stored pointer, which is
    // the first member of the compressed pair.
    "10unique_ptr",
    // `vector::data`/`operator[]` start from `__begin_`, the first member.
    "6vectorI",
    // `__wrap_iter` holds only its pointer.
    "11__wrap_iter",
};

/// Whether a callee is one whose receiver is the container/pointer itself, so
/// a near-null receiver is the container's address and not a displaced field.
///
/// Used to decide whether the empty-container reading is worth printing beside
/// a shape, not to decide the shape.
pub fn isZeroOffsetAccessor(symbol_name: []const u8) bool {
    for (zero_offset_accessors) |fragment| {
        if (std.mem.indexOf(u8, symbol_name, fragment) != null) return true;
    }
    return false;
}

/// Whether an Itanium-mangled name is a non-static C++ member function, and so
/// whether RDI is `this`.
///
/// Mach-O's assembler prepends one underscore to a C symbol and the C++ mangler
/// already begins with `_Z`, which is why the observed spelling carries up to
/// two. `ZN` introduces a nested name; `ZNK` is its const-qualified form and is
/// covered by the same prefix test.
pub fn looksLikeCppMember(symbol: []const u8) bool {
    var start: usize = 0;
    while (start < symbol.len and start < 2 and symbol[start] == '_') : (start += 1) {}
    return std.mem.startsWith(u8, symbol[start..], "ZN");
}

/// Whether the member is const-qualified (`ZNK`). A const member cannot be the
/// code that zeroed its own object, which narrows a clobber hunt by one frame.
pub fn isConstCppMember(symbol: []const u8) bool {
    var start: usize = 0;
    while (start < symbol.len and start < 2 and symbol[start] == '_') : (start += 1) {}
    return std.mem.startsWith(u8, symbol[start..], "ZNK");
}

/// One sentence naming what the observed receiver is consistent with.
///
/// Returned as a fixed set of strings rather than formatted text so the caller
/// owns its own log line format, and so this package allocates nothing.
pub fn shapeExplanation(shape: ReceiverShape, zero_offset_accessor: bool) []const u8 {
    return switch (shape) {
        .exact_zero => if (zero_offset_accessor)
            "the receiver is exactly zero at a zero-offset accessor: consistent with a null stored pointer, and equally with &container[0] where the container is empty — an empty container is the reading that does not require anything to have been clobbered"
        else
            "the receiver is exactly zero: a null pointer was stored, returned, or never assigned",
        .element_displacement => "the receiver is a small exact multiple of a plausible element size: consistent with &container[n] where the container is empty, the index scaled by the element width over a null base",
        .member_displacement => "the receiver is a small value that is not a clean element multiple: consistent with a member access through a null object pointer, landing at the field's own offset",
        .mapped => "the address is mapped and is not a near-null observation",
    };
}

/// No fact here may contradict another.
pub fn contractIsWellFormed() bool {
    if (near_null_limit != page_size) return false;
    if (candidate_element_sizes.len == 0) return false;
    var previous: u64 = 0;
    for (candidate_element_sizes) |size| {
        // Ascending and non-zero: `classifyReceiver` returns on the first
        // match, so an unsorted table would report the wrong smallest size.
        if (size == 0 or size <= previous) return false;
        previous = size;
    }
    if (zero_offset_accessors.len == 0) return false;
    for (zero_offset_accessors) |fragment| {
        if (fragment.len == 0) return false;
    }
    return true;
}

test "exact zero is the empty-container shape, not only a null pointer" {
    // The finding from the 2026-08-24 run: `receiver=0x0 member_offset=0x0`
    // inside `unique_ptr<VulkanDevice::Queue>::operator->()`. Read as a
    // clobbered pointer it sends the reader hunting a writer; read as
    // `&queues[0]` on an empty vector it sends them to whoever failed to fill
    // `queues`, which is the investigation that finds something.
    try std.testing.expectEqual(ReceiverShape.exact_zero, classifyReceiver(0));
    try std.testing.expect(ReceiverShape.exact_zero.admitsEmptyContainer());
    const callee = "__ZNKSt3__110unique_ptrIN2xe2ui6vulkan12VulkanDevice5QueueENS_14default_deleteIS5_EEEptB7v160006Ev";
    try std.testing.expect(isZeroOffsetAccessor(callee));
    try std.testing.expect(looksLikeCppMember(callee));
    try std.testing.expect(isConstCppMember(callee));
    const text = shapeExplanation(.exact_zero, true);
    try std.testing.expect(std.mem.indexOf(u8, text, "empty") != null);
}

test "a small multiple reads as an index into an empty container" {
    try std.testing.expectEqual(ReceiverShape.element_displacement, classifyReceiver(8));
    try std.testing.expectEqual(ReceiverShape.element_displacement, classifyReceiver(0x40));
    // `&v[8]` on an empty vector of 8-byte elements.
    try std.testing.expectEqual(@as(?u64, 8), impliedContainerIndex(0x40, 8));
    try std.testing.expectEqual(@as(?u64, 2), impliedContainerIndex(0x40, 32));
    try std.testing.expectEqual(@as(?u64, null), impliedContainerIndex(0x40, 24));

    // Ambiguity is reported, never resolved by picking the first match.
    var buffer: [candidate_element_sizes.len]u64 = undefined;
    const sizes = consistentElementSizes(0x40, buffer[0..]);
    try std.testing.expectEqual(@as(usize, 3), sizes.len);
    try std.testing.expectEqual(@as(u64, 8), sizes[0]);
}

test "an unaligned small value is a field, not an element" {
    try std.testing.expectEqual(ReceiverShape.member_displacement, classifyReceiver(0x1c));
    try std.testing.expectEqual(ReceiverShape.member_displacement, classifyReceiver(0x5));
    try std.testing.expect(!ReceiverShape.member_displacement.admitsEmptyContainer());
}

test "the page bound is the only definition of near-null" {
    try std.testing.expect(contractIsWellFormed());
    try std.testing.expect(isNearNull(0));
    try std.testing.expect(isNearNull(0xfff));
    try std.testing.expect(!isNearNull(0x1000));
    try std.testing.expectEqual(ReceiverShape.mapped, classifyReceiver(0x1000));
    // A mapped address yields no container reading at all.
    var buffer: [candidate_element_sizes.len]u64 = undefined;
    try std.testing.expectEqual(@as(usize, 0), consistentElementSizes(0x2000, buffer[0..]).len);
    try std.testing.expectEqual(@as(?u64, null), impliedContainerIndex(0x2000, 8));
}

test "Mach-O's double-underscore member symbol is recognised" {
    try std.testing.expect(looksLikeCppMember("__ZNK2xe6kernel11KernelState6memoryEv"));
    try std.testing.expect(looksLikeCppMember("_ZN2xe7Example3runEv"));
    try std.testing.expect(looksLikeCppMember("ZN2xe7Example3runEv"));
    try std.testing.expect(!looksLikeCppMember("___ZN2xe7Example3runEv"));
    try std.testing.expect(!looksLikeCppMember("_some_c_api"));
    // Const-qualification is a narrower claim than membership.
    try std.testing.expect(isConstCppMember("__ZNK2xe6kernel11KernelState6memoryEv"));
    try std.testing.expect(!isConstCppMember("_ZN2xe7Example3runEv"));
}
