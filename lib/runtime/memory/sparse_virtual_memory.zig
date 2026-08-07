const std = @import("std");
const builtin = @import("builtin");
const guest_memory_geometry = @import("dyld").guest_memory_geometry;
const machoCapturePrint = @import("event_log").machoCapturePrint;

extern "c" fn mprotect(addr: [*]align(std.heap.page_size_min) u8, len: usize, prot: c_int) c_int;

pub const PAGE_64K: u64 = 64 * 1024;
pub const PAGE_4K: u64 = guest_memory_geometry.guest_page_size;
pub const LARGE_PAGE: u64 = 2 * 1024 * 1024;

// R1 (perf audit): page-granular classification cache for sparse lookups.
// Every guest load/store and the per-instruction executable check used to
// walk every activation + mapping linearly. This direct-mapped cache
// classifies whole 4K pages; any mapping/activation mutation bumps
// `page_cache_generation`, which invalidates every entry at once (map/
// protect/unmap are rare; accesses are not). Entries are only filled for
// pages that are either entirely uncovered by sparse records or fully
// covered by one record; partial-page coverage is deliberately not cached
// (the exact linear scan stays the fallback for those pages).
pub const PAGE_CACHE_ENTRIES: usize = 1 << 12;
const PAGE_CACHE_HASH_SHIFT: u6 = 52; // 64 - log2(PAGE_CACHE_ENTRIES)
const PAGE_CACHE_HASH_MULTIPLIER: u64 = 0x9E37_79B9_7F4A_7C15;

const PageCacheState = enum(u8) { empty, none, covered };

const PageCacheEntry = struct {
    /// `page + 1` where page = address >> 12; 0 marks an unused slot.
    tag: u64 = 0,
    /// Manager.page_cache_generation at fill time; a mismatch means a
    /// mapping/activation mutation happened since the entry was filled.
    generation: u64 = 0,
    state: PageCacheState = .empty,
    is_activation: bool = false,
    is_reservation: bool = false,
    /// Index into activations.items (is_activation) or mappings.items.
    index: u32 = 0,
};

/// Fast-path classification for a single-page sparse lookup. `partial` means
/// the page has partial coverage or overlapping mappings, so the caller must
/// run the exact linear scan.
const PageCacheResult = union(enum) {
    none,
    covered: PageCacheEntry,
    partial,
};

const PROT_READ: u32 = 0x1;
const PROT_WRITE: u32 = 0x2;
const PROT_EXEC: u32 = 0x4;
const DARWIN_MAP_JIT: u32 = 0x800;

/// Sparse guest mappings are interpreter backing, not host-native code. Keep
/// guest execute permission in Mapping metadata while making the host pages
/// readable for instruction decoding. Granting host PROT_EXEC would opt the
/// processor into macOS JIT write-protection rules and can raise SIGBUS when
/// the interpreted guest writes generated x86 code.
fn hostBackingProtection(guest_prot: u32) u32 {
    var host_prot = guest_prot & (PROT_READ | PROT_WRITE);
    if (guest_prot & PROT_EXEC != 0) host_prot |= PROT_READ;
    return host_prot;
}

fn hostBackingFlags(guest_flags: u32) u32 {
    if (comptime builtin.os.tag == .macos) return guest_flags & ~DARWIN_MAP_JIT;
    return guest_flags;
}

fn fileOffsetIsHostAligned(offset: u64) bool {
    return offset % guest_memory_geometry.host_vm_page_size == 0;
}

pub fn pageRoundedLength(length: u64) ?u64 {
    if (length == 0) return null;
    const page_size: u64 = std.heap.page_size_min;
    const with_padding = std.math.add(u64, length, page_size - 1) catch return null;
    return with_padding & ~(page_size - 1);
}

/// Returns the effective interval covered by a guest mprotect request.
///
/// Darwin rounds the end of an mprotect interval up to a VM page. Rosette
/// must mirror that behavior in its permission metadata as well as in the
/// host syscall. The metadata is deliberately rounded to the x86 guest page
/// (4 KiB), not the Apple Silicon host page (16 KiB), so a legitimate tail
/// access is admitted without consuming an adjacent guest guard page.
pub fn guestProtectionRoundedLength(guest_base: u64, length: u64) ?u64 {
    if (length == 0) return null;
    const end = std.math.add(u64, guest_base, length) catch return null;
    const padded_end = std.math.add(u64, end, PAGE_4K - 1) catch return null;
    const rounded_end = padded_end & ~(PAGE_4K - 1);
    if (rounded_end <= guest_base) return null;
    return rounded_end - guest_base;
}

const HostPageSpan = struct {
    offset: usize,
    length: usize,
};

/// Converts an exact guest protection range into the containing host-page
/// span. On Apple Silicon a valid 4 KiB x86 guest page often begins inside a
/// 16 KiB host page; only the host syscall span is widened.
fn hostPageSpan(offset: usize, length: usize, capacity: usize) ?HostPageSpan {
    if (length == 0) return null;
    const page_size = std.heap.page_size_min;
    const end = std.math.add(usize, offset, length) catch return null;
    const rounded_end_input = std.math.add(usize, end, page_size - 1) catch return null;
    const aligned_offset = offset & ~(page_size - 1);
    const aligned_end = rounded_end_input & ~(page_size - 1);
    if (aligned_end > capacity or aligned_end <= aligned_offset) return null;
    return .{ .offset = aligned_offset, .length = aligned_end - aligned_offset };
}

const Mapping = struct {
    guest_base: u64,
    memory: []align(std.heap.page_size_min) u8,
    readable: bool,
    writable: bool,
    executable: bool,
    is_fixed: bool,
    is_reservation: bool,
};

const Activation = struct {
    guest_base: u64,
    memory: []u8,
    readable: bool,
    writable: bool,
    executable: bool,
    sequence: u64,
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    mappings: std.ArrayList(Mapping) = .empty,
    activations: std.ArrayList(Activation) = .empty,
    total_reserved: u64 = 0,
    protection_sequence: u64 = 0,
    // R1 (perf audit): page-granular sparse classification cache (see the
    // PAGE_CACHE_* constants above). Bumped on every mapping/activation
    // mutation so a single bump invalidates all entries at once.
    page_cache: [PAGE_CACHE_ENTRIES]PageCacheEntry = [_]PageCacheEntry{.{}} ** PAGE_CACHE_ENTRIES,
    page_cache_generation: u64 = 1,

    pub fn init(allocator: std.mem.Allocator) Manager {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Manager) void {
        for (self.mappings.items) |mapping| {
            std.posix.munmap(mapping.memory);
        }
        self.mappings.deinit(self.allocator);
        self.activations.deinit(self.allocator);
    }

    pub fn mapFile(self: *Manager, guest_base: u64, length: u64, prot_raw: u32, flags_raw: u32, host_fd: std.posix.fd_t, offset: u64) bool {
        self.bumpPageCache();
        if (length == 0 or (guest_base % PAGE_4K != 0) or !fileOffsetIsHostAligned(offset)) return false;
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base < mapping_end and end > mapping.guest_base) return false;
        }
        const length_usize = std.math.cast(usize, length) orelse return false;
        var flags: std.posix.MAP = @bitCast(flags_raw);
        flags.FIXED = false;
        const prot: std.posix.PROT = @bitCast(prot_raw);
        const memory = std.posix.mmap(null, length_usize, prot, flags, host_fd, offset) catch return false;
        self.mappings.append(self.allocator, .{
            .guest_base = guest_base,
            .memory = memory,
            .readable = prot_raw & 1 != 0,
            .writable = prot_raw & 2 != 0,
            .executable = prot_raw & 4 != 0,
            .is_fixed = false,
            .is_reservation = false,
        }) catch {
            std.posix.munmap(memory);
            return false;
        };
        return true;
    }

    /// Creates a true mmap-style mapping whose host-selected address is also
    /// its guest address. This is required for large native-backend regions
    /// requested with a null address hint (for example Xenia's indirection
    /// table and MAP_JIT code cache). Serving those requests from the bounded
    /// C++ guest heap both exhausts the heap and loses mmap permissions.
    pub fn mapAnywhereWithBacking(self: *Manager, length: u64, prot_raw: u32, flags_raw: u32, host_fd: std.posix.fd_t, offset: u64) ?u64 {
        return self.mapAnywhereWithHintAndBacking(length, prot_raw, flags_raw, host_fd, offset, null, null);
    }

    /// Maps backend VM while retaining mmap's non-fixed hint semantics. If a
    /// maximum address is supplied, a host placement outside the required
    /// guest pointer window is rejected instead of allowing later truncation.
    pub fn mapAnywhereWithHintAndBacking(
        self: *Manager,
        length: u64,
        prot_raw: u32,
        flags_raw: u32,
        host_fd: std.posix.fd_t,
        offset: u64,
        preferred_base: ?u64,
        maximum_end_exclusive: ?u64,
    ) ?u64 {
        self.bumpPageCache();
        if (length == 0) return null;
        if (host_fd >= 0 and !fileOffsetIsHostAligned(offset)) return null;
        const effective_length = pageRoundedLength(length) orelse return null;
        const length_usize = std.math.cast(usize, effective_length) orelse return null;
        const host_prot_raw = hostBackingProtection(prot_raw);
        const host_flags_raw = hostBackingFlags(flags_raw);
        var flags: std.posix.MAP = @bitCast(host_flags_raw);
        flags.FIXED = false;
        const prot: std.posix.PROT = @bitCast(host_prot_raw);
        // The interpreter does not dereference guest pointers directly. For a
        // backend low-window contract, map backing wherever the host permits
        // and expose the preferred address only in the guest virtual model.
        // This avoids both destructive MAP_FIXED and macOS arm64's rejection
        // of low host VM allocations.
        const memory = std.posix.mmap(null, length_usize, prot, flags, host_fd, offset) catch |err| {
            machoCapturePrint(
                "macho-processor: sparse anywhere mmap FAILED: reason={s} requested_length={d} effective_length={d} page_tail={d} preferred_base=0x{x} maximum_end=0x{x} guest_prot=0x{x} host_prot=0x{x} guest_flags=0x{x} host_flags=0x{x} map_jit_emulated={} anonymous={} host_fd={d} offset=0x{x}\n",
                .{ @errorName(err), length, effective_length, effective_length - length, preferred_base orelse 0, maximum_end_exclusive orelse 0, prot_raw, host_prot_raw, flags_raw, host_flags_raw, flags_raw & DARWIN_MAP_JIT != 0, flags.ANONYMOUS, host_fd, offset },
            );
            return null;
        };
        const host_base = @intFromPtr(memory.ptr);
        const guest_base = preferred_base orelse host_base;
        const guest_end = std.math.add(u64, guest_base, effective_length) catch {
            std.posix.munmap(memory);
            return null;
        };
        if (maximum_end_exclusive) |maximum_end| {
            if (guest_end > maximum_end) {
                machoCapturePrint(
                    "macho-processor: sparse anywhere mmap rejected placement: guest_base=0x{x} guest_end=0x{x} requested_length={d} effective_length={d} preferred_base=0x{x} maximum_end=0x{x} reason=backend_pointer_window\n",
                    .{ guest_base, guest_end, length, effective_length, preferred_base orelse 0, maximum_end },
                );
                std.posix.munmap(memory);
                return null;
            }
        }
        for (self.mappings.items) |mapping| {
            const mapping_end = mapping.guest_base +| mapping.memory.len;
            if (guest_base < mapping_end and guest_end > mapping.guest_base) {
                std.posix.munmap(memory);
                return null;
            }
        }
        self.mappings.append(self.allocator, .{
            .guest_base = guest_base,
            .memory = memory,
            .readable = prot_raw & 1 != 0,
            .writable = prot_raw & 2 != 0,
            .executable = prot_raw & 4 != 0,
            .is_fixed = false,
            .is_reservation = false,
        }) catch {
            std.posix.munmap(memory);
            return null;
        };
        machoCapturePrint(
            "macho-processor: sparse anywhere mmap succeeded: guest_base=0x{x} guest_end=0x{x} host_base=0x{x} requested_length={d} effective_length={d} page_tail={d} preferred_base=0x{x} guest_address_contract_honored={} guest_host_alias={} low_window_required={} allocation_route=modeled_guest_alias guest_prot=0x{x} host_prot=0x{x} guest_flags=0x{x} host_flags=0x{x} map_jit_emulated={} host_execute=false anonymous={} host_fd={d}\n",
            .{ guest_base, guest_end, host_base, length, effective_length, effective_length - length, preferred_base orelse 0, preferred_base == null or preferred_base.? == guest_base, guest_base != host_base, maximum_end_exclusive != null, prot_raw, host_prot_raw, flags_raw, host_flags_raw, flags_raw & DARWIN_MAP_JIT != 0, flags.ANONYMOUS, host_fd },
        );
        return guest_base;
    }

    /// True when no mapping at all overlaps this guest range.
    ///
    /// This is the question POSIX asks for a non-MAP_FIXED request carrying an
    /// address hint: place it there if the range is free, choose elsewhere if
    /// it is not, and never replace anything. Reservations count as occupied —
    /// activating one is a MAP_FIXED decision, not a hint decision, and a hint
    /// must not make it.
    pub fn rangeIsFree(self: *const Manager, guest_base: u64, length: u64) bool {
        if (length == 0) return false;
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base < mapping_end and end > mapping.guest_base) return false;
        }
        return true;
    }

    /// True when a MAP_FIXED request for exactly this range would replace an
    /// existing mapping — unmapping its host pages and handing the guest fresh
    /// ones. Predicts the `mapFixed` exact-match rule below and must move with
    /// it.
    ///
    /// A pure query on purpose. The manager owns placement and lifetime; it has
    /// no business knowing which observers keep state keyed by guest address.
    /// Callers that do keep such state ask this first, so a discard retires
    /// their records instead of silently invalidating them.
    pub fn replacesExisting(self: *const Manager, guest_base: u64, length: u64) bool {
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |mapping| {
            if (mapping.is_reservation) continue;
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base == mapping.guest_base and end == mapping_end) return true;
        }
        return false;
    }

    pub fn mapFixed(self: *Manager, guest_base: u64, length: u64, prot_raw: u32, flags_raw: u32, host_fd: std.posix.fd_t, offset: u64) bool {
        self.bumpPageCache();
        if (length == 0 or guest_base % std.heap.page_size_min != 0) {
            machoCapturePrint("macho-processor: sparse fixed mmap rejected: reason=invalid_length_or_alignment guest_base=0x{x} length={d} required_alignment={d}\n", .{ guest_base, length, std.heap.page_size_min });
            return false;
        }
        if (host_fd >= 0 and !fileOffsetIsHostAligned(offset)) {
            machoCapturePrint(
                "macho-processor: sparse fixed mmap rejected: reason=file_offset_not_host_page_aligned offset=0x{x} host_page_size={d} guest_tracking_page={d}; verify getpagesize/sysconf use the Darwin VM contract\n",
                .{ offset, guest_memory_geometry.host_vm_page_size, guest_memory_geometry.guest_page_size },
            );
            return false;
        }
        const end = std.math.add(u64, guest_base, length) catch {
            machoCapturePrint("macho-processor: sparse fixed mmap rejected: reason=address_overflow guest_base=0x{x} length={d}\n", .{ guest_base, length });
            return false;
        };
        // Remove any exact-match non-reservation mappings (POSIX MAP_FIXED replaces
        // existing mappings at the same address, so the new mapping takes precedence).
        {
            var i: usize = 0;
            while (i < self.mappings.items.len) {
                const mapping = self.mappings.items[i];
                const mapping_end = mapping.guest_base + mapping.memory.len;
                if (guest_base == mapping.guest_base and end == mapping_end and !mapping.is_reservation) {
                    const removed = self.mappings.swapRemove(i);
                    self.removeActivationsWithin(guest_base, length);
                    std.posix.munmap(removed.memory);
                    machoCapturePrint(
                        "macho-processor: sparse fixed mmap replaced existing: guest_base=0x{x} length={d} prot=0x{x}\n",
                        .{ guest_base, length, prot_raw },
                    );
                } else {
                    i += 1;
                }
            }
        }

        var inside_reservation = false;
        for (self.mappings.items) |mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base < mapping_end and end > mapping.guest_base) {
                if (!mapping.is_reservation or guest_base < mapping.guest_base or end > mapping_end) {
                    machoCapturePrint(
                        "macho-processor: sparse fixed mmap rejected: reason=overlap guest=[0x{x},0x{x}) existing=[0x{x},0x{x}) existing_is_reservation={}\n",
                        .{ guest_base, end, mapping.guest_base, mapping_end, mapping.is_reservation },
                    );
                    return false;
                }
                inside_reservation = true;
            }
        }
        const length_usize = std.math.cast(usize, length) orelse return false;
        var flags: std.posix.MAP = @bitCast(flags_raw);
        flags.FIXED = true;
        const prot: std.posix.PROT = @bitCast(prot_raw);
        const ptr = @as(?[*]align(std.heap.page_size_min) u8, @ptrFromInt(guest_base));
        const memory = std.posix.mmap(ptr, length_usize, prot, flags, host_fd, offset) catch |err| {
            const anonymous_private = flags.ANONYMOUS and host_fd < 0;
            if (anonymous_private and inside_reservation) {
                if (self.activateReservationRange(guest_base, length, prot_raw)) {
                    machoCapturePrint(
                        "macho-processor: sparse fixed mmap activated reservation: primary={s} guest_base=0x{x} length={d} prot=0x{x} flags=0x{x}\n",
                        .{ @errorName(err), guest_base, length, prot_raw, flags_raw },
                    );
                    return true;
                }
                machoCapturePrint(
                    "macho-processor: sparse fixed mmap FAILED: reason={s} fallback_disallowed=reservation_activation_failed guest_base=0x{x} length={d}\n",
                    .{ @errorName(err), guest_base, length },
                );
                return false;
            }
            if (anonymous_private and isRecoverableFixedMmapFailure(err)) {
                flags.FIXED = false;
                const alt = std.posix.mmap(null, length_usize, prot, flags, -1, 0) catch |fallback_err| {
                    machoCapturePrint("macho-processor: sparse fixed mmap FAILED: primary={s} fallback={s} guest_base=0x{x} length={d} prot=0x{x} flags=0x{x} host_fd={d} offset=0x{x}\n", .{ @errorName(err), @errorName(fallback_err), guest_base, length, prot_raw, flags_raw, host_fd, offset });
                    return false;
                };
                self.mappings.append(self.allocator, .{
                    .guest_base = guest_base,
                    .memory = alt,
                    .readable = prot_raw & 1 != 0,
                    .writable = prot_raw & 2 != 0,
                    .executable = prot_raw & 4 != 0,
                    .is_fixed = false,
                    .is_reservation = false,
                }) catch {
                    std.posix.munmap(alt);
                    return false;
                };
                machoCapturePrint(
                    "macho-processor: sparse fixed mmap guest-alias recovery: host_fixed_result={s} guest_base=0x{x} length={d} model=anonymous_guest_backing host_base=0x{x} recovered=true system_memory_exhausted=false\n",
                    .{ @errorName(err), guest_base, length, @intFromPtr(alt.ptr) },
                );
                return true;
            }
            if (err == error.MemoryMappingNotSupported or err == error.PermissionDenied) {
                if (inside_reservation) {
                    machoCapturePrint("macho-processor: sparse fixed mmap FAILED: reason={s} fallback_disallowed=would_break_reserved_guest_address guest_base=0x{x} length={d}\n", .{ @errorName(err), guest_base, length });
                    return false;
                }
                flags.FIXED = false;
                const alt = std.posix.mmap(null, length_usize, prot, flags, host_fd, offset) catch |fallback_err| {
                    machoCapturePrint("macho-processor: sparse fixed mmap FAILED: primary={s} fallback={s} guest_base=0x{x} length={d} prot=0x{x} flags=0x{x} host_fd={d} offset=0x{x}\n", .{ @errorName(err), @errorName(fallback_err), guest_base, length, prot_raw, flags_raw, host_fd, offset });
                    return false;
                };
                self.mappings.append(self.allocator, .{
                    .guest_base = guest_base,
                    .memory = alt,
                    .readable = prot_raw & 1 != 0,
                    .writable = prot_raw & 2 != 0,
                    .executable = prot_raw & 4 != 0,
                    .is_fixed = false,
                    .is_reservation = false,
                }) catch {
                    std.posix.munmap(alt);
                    return false;
                };
                return true;
            }
            machoCapturePrint("macho-processor: sparse fixed mmap FAILED: reason={s} guest_base=0x{x} length={d} prot=0x{x} flags=0x{x} host_fd={d} offset=0x{x}\n", .{ @errorName(err), guest_base, length, prot_raw, flags_raw, host_fd, offset });
            return false;
        };
        if (inside_reservation) {
            self.appendActivation(guest_base, memory, prot_raw) catch return false;
            machoCapturePrint(
                "macho-processor: sparse fixed mmap attached backing: guest_base=0x{x} length={d} prot=0x{x} flags=0x{x} host_fd={d} offset=0x{x} activations={d}\n",
                .{ guest_base, length, prot_raw, flags_raw, host_fd, offset, self.activations.items.len },
            );
        } else {
            self.mappings.append(self.allocator, .{
                .guest_base = guest_base,
                .memory = memory,
                .readable = prot_raw & 1 != 0,
                .writable = prot_raw & 2 != 0,
                .executable = prot_raw & 4 != 0,
                .is_fixed = true,
                .is_reservation = false,
            }) catch {
                std.posix.munmap(memory);
                return false;
            };
        }
        return true;
    }

    pub fn reserveLarge(self: *Manager, guest_base: u64, length: u64) bool {
        self.bumpPageCache();
        if (length == 0 or (guest_base % PAGE_4K != 0)) return false;
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base < mapping_end and end > mapping.guest_base) return false;
        }
        const length_usize = std.math.cast(usize, length) orelse return false;
        const ptr = @as(?[*]align(std.heap.page_size_min) u8, @ptrFromInt(guest_base));
        const none_prot: std.posix.PROT = @bitCast(@as(u32, 0));
        const anon_private_fixed: std.posix.MAP = @bitCast(@as(u32, 0x1000 | 0x2 | 0x10));
        const memory = std.posix.mmap(ptr, length_usize, none_prot, anon_private_fixed, -1, 0) catch |err| {
            if (err == error.MemoryMappingNotSupported or err == error.PermissionDenied or err == error.ProcessFrozen) return false;
            const anon_private: std.posix.MAP = @bitCast(@as(u32, 0x1000 | 0x2));
            const alt = std.posix.mmap(null, length_usize, none_prot, anon_private, -1, 0) catch return false;
            self.mappings.append(self.allocator, .{
                .guest_base = guest_base,
                .memory = alt,
                .readable = false,
                .writable = false,
                .executable = false,
                .is_fixed = false,
                .is_reservation = true,
            }) catch {
                std.posix.munmap(alt);
                return false;
            };
            self.total_reserved +|= length;
            return true;
        };
        self.mappings.append(self.allocator, .{
            .guest_base = guest_base,
            .memory = memory,
            .readable = false,
            .writable = false,
            .executable = false,
            .is_fixed = true,
            .is_reservation = true,
        }) catch {
            std.posix.munmap(memory);
            return false;
        };
        self.total_reserved +|= length;
        return true;
    }

    /// Reserves address space without committing physical memory.  Returning
    /// the host mapping address as the guest address lets later mprotect calls
    /// activate pages in-place while keeping the 4 GiB reservation sparse.
    pub fn reserveAnywhere(self: *Manager, length: u64) ?u64 {
        const anon_private: u32 = 0x1000 | 0x2;
        return self.reserveAnywhereWithBacking(length, anon_private, -1, 0);
    }

    pub fn reserveAnywhereWithBacking(self: *Manager, length: u64, flags_raw: u32, host_fd: std.posix.fd_t, offset: u64) ?u64 {
        self.bumpPageCache();
        if (length == 0) {
            machoCapturePrint("macho-processor: sparse reserve rejected: reason=zero_length flags=0x{x} host_fd={d} offset=0x{x}\n", .{ flags_raw, host_fd, offset });
            return null;
        }
        const length_usize = std.math.cast(usize, length) orelse {
            machoCapturePrint("macho-processor: sparse reserve rejected: reason=length_exceeds_host_usize length={d} flags=0x{x} host_fd={d} offset=0x{x}\n", .{ length, flags_raw, host_fd, offset });
            return null;
        };
        const none_prot: std.posix.PROT = @bitCast(@as(u32, 0));
        var flags: std.posix.MAP = @bitCast(flags_raw);
        flags.FIXED = false;
        machoCapturePrint(
            "macho-processor: sparse reserve request: length={d} (0x{x}) prot=NONE flags=0x{x} fixed={} anonymous={} host_fd={d} offset=0x{x} existing_mappings={d}\n",
            .{ length, length, flags_raw, flags.FIXED, flags.ANONYMOUS, host_fd, offset, self.mappings.items.len },
        );
        const memory = if (!flags.ANONYMOUS and host_fd < 0) invalid_fd_fallback: {
            machoCapturePrint(
                "macho-processor: sparse reserve request has non-anonymous fd=-1; reserving anonymous PROT_NONE space instead length={d} flags=0x{x} offset=0x{x}\n",
                .{ length, flags_raw, offset },
            );
            const anon_private_raw: u32 = 0x1000 | 0x2;
            var anon_private: std.posix.MAP = @bitCast(anon_private_raw);
            anon_private.FIXED = false;
            break :invalid_fd_fallback std.posix.mmap(null, length_usize, none_prot, anon_private, -1, 0) catch |fallback_err| {
                machoCapturePrint(
                    "macho-processor: sparse reserve fallback FAILED: primary=invalid_fd fallback={s} length={d} requested_flags=0x{x} fallback_flags=0x{x}\n",
                    .{ @errorName(fallback_err), length, flags_raw, anon_private_raw },
                );
                return null;
            };
        } else std.posix.mmap(null, length_usize, none_prot, flags, host_fd, offset) catch |err| fallback: {
            machoCapturePrint(
                "macho-processor: sparse reserve FAILED: syscall=mmap reason={s} length={d} flags=0x{x} anonymous={} host_fd={d} offset=0x{x}\n",
                .{ @errorName(err), length, flags_raw, flags.ANONYMOUS, host_fd, offset },
            );
            if (flags.ANONYMOUS and host_fd < 0) return null;
            const anon_private_raw: u32 = 0x1000 | 0x2;
            var anon_private: std.posix.MAP = @bitCast(anon_private_raw);
            anon_private.FIXED = false;
            const fallback = std.posix.mmap(null, length_usize, none_prot, anon_private, -1, 0) catch |fallback_err| {
                machoCapturePrint(
                    "macho-processor: sparse reserve fallback FAILED: primary={s} fallback={s} length={d} requested_flags=0x{x} fallback_flags=0x{x}\n",
                    .{ @errorName(err), @errorName(fallback_err), length, flags_raw, anon_private_raw },
                );
                return null;
            };
            machoCapturePrint(
                "macho-processor: sparse reserve fallback: primary={s} requested_flags=0x{x} requested_fd={d}; reserved anonymous PROT_NONE space instead\n",
                .{ @errorName(err), flags_raw, host_fd },
            );
            break :fallback fallback;
        };
        const guest_base = @intFromPtr(memory.ptr);
        self.mappings.append(self.allocator, .{
            .guest_base = guest_base,
            .memory = memory,
            .readable = false,
            .writable = false,
            .executable = false,
            .is_fixed = false,
            .is_reservation = true,
        }) catch {
            std.posix.munmap(memory);
            return null;
        };
        self.total_reserved +|= length;
        machoCapturePrint(
            "macho-processor: sparse reserve succeeded: guest_base=0x{x} host_base=0x{x} length={d} host_page_size={d} total_reserved={d}\n",
            .{ guest_base, @intFromPtr(memory.ptr), length, std.heap.page_size_min, self.total_reserved },
        );
        return guest_base;
    }

    pub fn protect(self: *Manager, guest_base: u64, length: u64, prot_raw: u32) bool {
        self.bumpPageCache();
        const effective_length = guestProtectionRoundedLength(guest_base, length) orelse return false;
        const end = std.math.add(u64, guest_base, effective_length) catch return false;
        for (self.mappings.items) |*mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base >= mapping.guest_base and end <= mapping_end) {
                const offset = @as(usize, @intCast(guest_base - mapping.guest_base));
                const effective_length_usize = std.math.cast(usize, effective_length) orelse return false;
                const host_span = hostPageSpan(offset, effective_length_usize, mapping.memory.len) orelse return false;
                const page_aligned = @as([*]align(std.heap.page_size_min) u8, @ptrCast(@alignCast(mapping.memory.ptr + host_span.offset)));
                // The host permission is only the backing permission. Exact
                // guest permissions are enforced by the activation records
                // below. Preserve access required by neighboring guest ranges
                // sharing the same host page, including the mapping's original
                // permissions and earlier partial mprotect calls.
                var effective_guest_prot = prot_raw;
                if (mapping.readable) effective_guest_prot |= PROT_READ;
                if (mapping.writable) effective_guest_prot |= PROT_WRITE;
                if (mapping.executable) effective_guest_prot |= PROT_EXEC;
                const host_guest_start = mapping.guest_base + host_span.offset;
                const host_guest_end = host_guest_start + host_span.length;
                for (self.activations.items) |active| {
                    const active_end = active.guest_base +| active.memory.len;
                    if (active.guest_base >= host_guest_end or active_end <= host_guest_start) continue;
                    if (active.readable) effective_guest_prot |= PROT_READ;
                    if (active.writable) effective_guest_prot |= PROT_WRITE;
                    if (active.executable) effective_guest_prot |= PROT_EXEC;
                }
                const host_prot_raw = hostBackingProtection(effective_guest_prot);
                if (mprotect(page_aligned, host_span.length, @as(c_int, @intCast(host_prot_raw))) != 0) return false;
                if (effective_length != length or host_span.offset != offset or host_span.length != effective_length_usize) {
                    machoCapturePrint(
                        "macho-processor: sparse guest protection normalized: guest_base=0x{x} requested_guest_length={d} effective_guest_length={d} guest_page_tail={d} guest_page={d} host_offset=0x{x} host_length={d} host_page={d} prot=0x{x}; guest-page-granular permissions retained in metadata\n",
                        .{ guest_base, length, effective_length, effective_length - length, PAGE_4K, host_span.offset, host_span.length, std.heap.page_size_min, prot_raw },
                    );
                }
                // A protection request may cover only a stack guard or a JIT
                // subrange. Recording it against the entire non-reservation
                // mapping made an adjacent PROT_NONE guard revoke the usable
                // stack. Use the same ordered interval overlay for every
                // mapping kind.
                const active_memory = mapping.memory[offset..][0..effective_length_usize];
                self.appendActivation(guest_base, active_memory, prot_raw) catch return false;
                if (prot_raw & PROT_EXEC != 0) {
                    machoCapturePrint(
                        "macho-processor: sparse guest execute protection emulated: guest_base=0x{x} requested_length={d} effective_length={d} guest_prot=0x{x} host_prot=0x{x} host_execute=false\n",
                        .{ guest_base, length, effective_length, prot_raw, host_prot_raw },
                    );
                }
                return true;
            }
        }
        return false;
    }

    pub fn zeroFill(self: *Manager, guest_base: u64, length: u64) bool {
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |*mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base >= mapping.guest_base and end <= mapping_end) {
                const offset = @as(usize, @intCast(guest_base - mapping.guest_base));
                @memset(mapping.memory[offset..][0..@intCast(length)], 0);
                return true;
            }
        }
        return self.overwrite(guest_base, length, 0);
    }

    pub fn overwrite(self: *Manager, guest_base: u64, length: u64, value: u8) bool {
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |*mapping| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base >= mapping.guest_base and end <= mapping_end) {
                const offset = @as(usize, @intCast(guest_base - mapping.guest_base));
                @memset(mapping.memory[offset..][0..@intCast(length)], value);
                return true;
            }
        }
        return false;
    }

    fn pageCacheIndex(page: u64) usize {
        return @intCast((page *% PAGE_CACHE_HASH_MULTIPLIER) >> PAGE_CACHE_HASH_SHIFT);
    }

    fn pageCacheFill(self: *Manager, page: u64) void {
        const slot = &self.page_cache[pageCacheIndex(page)];
        slot.* = .{ .tag = page + 1, .generation = self.page_cache_generation, .state = .none };
        const page_start = page << 12;
        const page_end = page_start +| PAGE_4K;
        // The newest overlapping activation is authoritative (reverse scan,
        // mirroring the linear fallback). Only full-page coverage is cached;
        // partial coverage must stay on the exact linear path.
        var activation_index = self.activations.items.len;
        while (activation_index != 0) {
            activation_index -= 1;
            const active = &self.activations.items[activation_index];
            const active_end = active.guest_base +| active.memory.len;
            if (page_start >= active_end or page_end <= active.guest_base) continue;
            if (page_start < active.guest_base or page_end > active_end) {
                slot.state = .empty; // partial page coverage: not cacheable
                return;
            }
            slot.* = .{
                .tag = page + 1,
                .generation = self.page_cache_generation,
                .state = .covered,
                .is_activation = true,
                .is_reservation = false,
                .index = @intCast(activation_index),
            };
            return;
        }
        // Fallback: a single mapping covering the whole page. Multiple
        // overlapping mappings are not cacheable: bytes()/isExecutable use
        // find()/findConst() (first non-reservation, forward order) while
        // containsMapped() also accepts reservations, so the two disagree.
        var mapping_index: ?usize = null;
        for (self.mappings.items, 0..) |mapping, index| {
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (page_start >= mapping_end or page_end <= mapping.guest_base) continue;
            if (mapping_index != null) {
                slot.state = .empty; // overlapping mappings: not cacheable
                return;
            }
            mapping_index = index;
        }
        if (mapping_index) |index| {
            const mapping = &self.mappings.items[index];
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (page_start < mapping.guest_base or page_end > mapping_end) {
                slot.state = .empty; // partial page coverage: not cacheable
                return;
            }
            slot.* = .{
                .tag = page + 1,
                .generation = self.page_cache_generation,
                .state = .covered,
                .is_activation = false,
                .is_reservation = mapping.is_reservation,
                .index = @intCast(index),
            };
            return;
        }
        // No sparse record overlaps this page.
        slot.state = .none;
    }

    fn pageCacheProbe(self: *Manager, page: u64) PageCacheResult {
        const slot = &self.page_cache[pageCacheIndex(page)];
        if (slot.tag != page + 1 or slot.generation != self.page_cache_generation) {
            self.pageCacheFill(page);
        }
        return switch (slot.state) {
            .none => .none,
            .covered => .{ .covered = slot.* },
            .empty => .partial,
        };
    }

    /// The Manager always lives in mutable storage (a MachOState field or a
    /// test local). Const callers (the generic MemoryState read path) reach
    /// it through a const view of that same object, so the lazy cache fill
    /// below is defined behavior — the same @constCast pattern already used
    /// in manager.zig for `bytes`.
    fn pageCacheProbeConst(self: *const Manager, page: u64) PageCacheResult {
        return @constCast(self).pageCacheProbe(page);
    }

    fn bumpPageCache(self: *Manager) void {
        self.page_cache_generation +%= 1;
        if (self.page_cache_generation == 0) self.page_cache_generation = 1;
    }

    pub fn bytes(self: *Manager, address: u64, length: u64, write: bool) ?[]u8 {
        const end = std.math.add(u64, address, length) catch return null;
        if (length != 0) {
            const page = address >> 12;
            if ((end - 1) >> 12 == page) {
                switch (self.pageCacheProbe(page)) {
                    .none => return null,
                    .partial => {},
                    .covered => |entry| {
                        if (entry.is_activation) {
                            const active = &self.activations.items[entry.index];
                            if (write and !active.writable) return null;
                            if (!write and !active.readable) return null;
                            const offset: usize = @intCast(address - active.guest_base);
                            return active.memory[offset..][0..@intCast(length)];
                        }
                        if (entry.is_reservation) return null;
                        const mapping = &self.mappings.items[entry.index];
                        if (write and !mapping.writable) return null;
                        if (!write and !mapping.readable) return null;
                        const offset: usize = @intCast(address - mapping.guest_base);
                        return mapping.memory[offset..][0..@intCast(length)];
                    },
                }
            }
        }
        var activation_index = self.activations.items.len;
        while (activation_index != 0) {
            activation_index -= 1;
            const active = &self.activations.items[activation_index];
            const active_end = active.guest_base +| active.memory.len;
            if (address >= active_end or end <= active.guest_base) continue;
            // The newest overlapping interval is authoritative. A denied
            // activation must not fall through to the mapping's older base
            // permission.
            if (address < active.guest_base or end > active_end) return null;
            if (write and !active.writable) return null;
            if (!write and !active.readable) return null;
            const offset: usize = @intCast(address - active.guest_base);
            return active.memory[offset..][0..@intCast(length)];
        }
        const found = self.find(address, length) orelse return null;
        if (write and !found.mapping.writable) return null;
        if (!write and !found.mapping.readable) return null;
        return found.mapping.memory[found.offset..][0..@intCast(length)];
    }

    pub fn bytesConst(self: *const Manager, address: u64, length: u64) ?[]const u8 {
        // Read semantics are exactly bytes(address, length, false); the cache
        // fill happens through the same mutable path (see pageCacheProbeConst).
        return @constCast(self).bytes(address, length, false);
    }

    pub fn contains(self: *const Manager, address: u64, length: u64) bool {
        return self.bytesConst(address, length) != null;
    }

    pub fn containsMapped(self: *const Manager, address: u64, length: u64) bool {
        const end = std.math.add(u64, address, length) catch return false;
        if (length != 0) {
            const page = address >> 12;
            if ((end - 1) >> 12 == page) {
                switch (self.pageCacheProbeConst(page)) {
                    .none => return false,
                    .partial => {},
                    .covered => return true,
                }
            }
        }
        var activation_index = self.activations.items.len;
        while (activation_index != 0) {
            activation_index -= 1;
            const active = &self.activations.items[activation_index];
            const active_end = active.guest_base +| active.memory.len;
            if (address >= active.guest_base and end <= active_end) return true;
        }
        for (self.mappings.items) |mapping| {
            const mapping_end = mapping.guest_base +| mapping.memory.len;
            if (address >= mapping.guest_base and end <= mapping_end) return true;
        }
        return false;
    }

    /// Emits the exact sparse permission records involved in a denied access.
    /// This stays silent on successful accesses so it is safe in the hot path,
    /// while making an unexpected protection fault actionable in one run.
    pub fn logAccessFailure(self: *const Manager, address: u64, length: u64, write: bool) void {
        const end = std.math.add(u64, address, length) catch std.math.maxInt(u64);
        var containing_mappings: usize = 0;
        for (self.mappings.items) |mapping| {
            const mapping_end = mapping.guest_base +| mapping.memory.len;
            if (address >= mapping.guest_base and end <= mapping_end) containing_mappings += 1;
        }

        var overlap_count: usize = 0;
        var newest_overlap_sequence: u64 = 0;
        var newest_overlap_allows = false;
        var activation_index = self.activations.items.len;
        while (activation_index != 0) {
            activation_index -= 1;
            const active = self.activations.items[activation_index];
            const active_end = active.guest_base +| active.memory.len;
            if (address >= active_end or end <= active.guest_base) continue;
            overlap_count += 1;
            if (newest_overlap_sequence == 0) {
                newest_overlap_sequence = active.sequence;
                newest_overlap_allows = address >= active.guest_base and end <= active_end and
                    (if (write) active.writable else active.readable);
            }
        }

        machoCapturePrint(
            "macho-processor: sparse access contract FAILED: address=0x{x} end=0x{x} length={d} access={s} containing_mappings={d} overlapping_activations={d} newest_sequence={d} newest_allows={} total_activations={d}\n",
            .{ address, end, length, if (write) "write" else "read", containing_mappings, overlap_count, newest_overlap_sequence, newest_overlap_allows, self.activations.items.len },
        );

        var printed: usize = 0;
        activation_index = self.activations.items.len;
        while (activation_index != 0 and printed < 12) {
            activation_index -= 1;
            const active = self.activations.items[activation_index];
            const active_end = active.guest_base +| active.memory.len;
            if (address >= active_end or end <= active.guest_base) continue;
            const contains_request = address >= active.guest_base and end <= active_end;
            machoCapturePrint(
                "macho-processor:   sparse activation sequence={d} index={d} range=[0x{x},0x{x}) permissions={c}{c}{c} relation={s} requested_access_allowed={}\n",
                .{ active.sequence, activation_index, active.guest_base, active_end, @as(u8, if (active.readable) 'r' else '-'), @as(u8, if (active.writable) 'w' else '-'), @as(u8, if (active.executable) 'x' else '-'), if (contains_request) "contains" else "partial_overlap", contains_request and (if (write) active.writable else active.readable) },
            );
            printed += 1;
        }
        if (overlap_count > printed) {
            machoCapturePrint(
                "macho-processor:   sparse activation diagnostics truncated: printed={d} omitted={d}\n",
                .{ printed, overlap_count - printed },
            );
        }
    }

    pub fn isExecutable(self: *const Manager, address: u64, length: u64) bool {
        return @constCast(self).isExecutableInner(address, length);
    }

    fn isExecutableInner(self: *Manager, address: u64, length: u64) bool {
        const end = std.math.add(u64, address, length) catch return false;
        if (length != 0) {
            const page = address >> 12;
            if ((end - 1) >> 12 == page) {
                switch (self.pageCacheProbe(page)) {
                    .none => return false,
                    .partial => {},
                    .covered => |entry| {
                        if (entry.is_reservation) return false;
                        if (entry.is_activation) return self.activations.items[entry.index].executable;
                        return self.mappings.items[entry.index].executable;
                    },
                }
            }
        }
        var activation_index = self.activations.items.len;
        while (activation_index != 0) {
            activation_index -= 1;
            const active = &self.activations.items[activation_index];
            const active_end = active.guest_base +| active.memory.len;
            if (address >= active_end or end <= active.guest_base) continue;
            return address >= active.guest_base and end <= active_end and active.executable;
        }
        const found = self.findConst(address, length) orelse return false;
        return found.mapping.executable;
    }

    pub fn executableBytesConst(self: *const Manager, address: u64, length: u64) ?[]const u8 {
        return @constCast(self).executableBytesConstInner(address, length);
    }

    fn executableBytesConstInner(self: *Manager, address: u64, length: u64) ?[]const u8 {
        if (!self.isExecutableInner(address, length)) return null;
        const end = std.math.add(u64, address, length) catch return null;
        if (length != 0) {
            const page = address >> 12;
            if ((end - 1) >> 12 == page) {
                switch (self.pageCacheProbe(page)) {
                    .none => return null,
                    .partial => {},
                    .covered => |entry| {
                        if (entry.is_activation) {
                            const active = &self.activations.items[entry.index];
                            const offset: usize = @intCast(address - active.guest_base);
                            return active.memory[offset..][0..@intCast(length)];
                        }
                        if (entry.is_reservation) return null;
                        const mapping = &self.mappings.items[entry.index];
                        const offset: usize = @intCast(address - mapping.guest_base);
                        return mapping.memory[offset..][0..@intCast(length)];
                    },
                }
            }
        }
        var activation_index = self.activations.items.len;
        while (activation_index != 0) {
            activation_index -= 1;
            const active = &self.activations.items[activation_index];
            const active_end = active.guest_base +| active.memory.len;
            if (address < active.guest_base or end > active_end or !active.executable) continue;
            const offset: usize = @intCast(address - active.guest_base);
            return active.memory[offset..][0..@intCast(length)];
        }
        const found = self.findConst(address, length) orelse return null;
        return found.mapping.memory[found.offset..][0..@intCast(length)];
    }

    pub fn unmap(self: *Manager, guest_base: u64, length: u64) bool {
        self.bumpPageCache();
        for (self.mappings.items, 0..) |mapping, index| {
            if (mapping.guest_base != guest_base or mapping.memory.len != length) continue;
            const removed = self.mappings.swapRemove(index);
            self.removeActivationsWithin(guest_base, length);
            std.posix.munmap(removed.memory);
            if (removed.is_reservation) self.total_reserved -|= removed.memory.len;
            return true;
        }
        for (self.mappings.items) |mapping| {
            if (!mapping.is_reservation) continue;
            const mapping_end = mapping.guest_base + mapping.memory.len;
            const end = std.math.add(u64, guest_base, length) catch return false;
            if (guest_base < mapping.guest_base or end > mapping_end) continue;
            var found_exact = false;
            for (self.activations.items) |active| {
                if (active.guest_base == guest_base and active.memory.len == length) {
                    found_exact = true;
                    break;
                }
            }
            if (!found_exact) return false;
            const offset: usize = @intCast(guest_base - mapping.guest_base);
            const requested_length = std.math.cast(usize, length) orelse return false;
            const host_span = hostPageSpan(offset, requested_length, mapping.memory.len) orelse return false;
            const host_guest_start = mapping.guest_base + host_span.offset;
            const host_guest_end = host_guest_start + host_span.length;
            var remaining_guest_prot: u32 = 0;
            for (self.activations.items) |active| {
                const active_end = active.guest_base +| active.memory.len;
                if (active.guest_base >= guest_base and active_end <= end) continue;
                if (active.guest_base >= host_guest_end or active_end <= host_guest_start) continue;
                if (active.readable) remaining_guest_prot |= PROT_READ;
                if (active.writable) remaining_guest_prot |= PROT_WRITE;
                if (active.executable) remaining_guest_prot |= PROT_EXEC;
            }
            const host_memory = @as([]align(std.heap.page_size_min) u8, @alignCast(mapping.memory[host_span.offset..][0..host_span.length]));
            if (mprotect(host_memory.ptr, host_memory.len, @intCast(hostBackingProtection(remaining_guest_prot))) != 0) return false;
            self.removeActivationsWithin(guest_base, length);
            return true;
        }
        return false;
    }

    pub fn logSummary(self: *const Manager) void {
        var map_count: usize = 0;
        var fixed_count: usize = 0;
        var reserved_count: usize = 0;
        for (self.mappings.items) |m| {
            if (m.is_reservation) reserved_count += 1;
            if (m.is_fixed) fixed_count += 1;
            map_count += 1;
        }
        machoCapturePrint(
            "macho-processor: sparse memory: mappings={d} fixed={d} reservations={d} activations={d} reserved_bytes={d}\n",
            .{ map_count, fixed_count, reserved_count, self.activations.items.len, self.total_reserved },
        );
    }

    /// Render the Linux-compatible process map view used by Xenia's generic
    /// POSIX protection query. Addresses are Rosette guest addresses because
    /// those are the pointer values observed by the interpreted x86 process.
    ///
    /// Activations are emitted newest-first so a narrow mprotect update takes
    /// precedence over its containing PROT_NONE reservation when Xenia scans
    /// for the first range containing an address.
    pub fn renderProcSelfMaps(self: *const Manager, output: []u8) []const u8 {
        var used: usize = 0;
        var activation_index = self.activations.items.len;
        while (activation_index != 0) {
            activation_index -= 1;
            const activation = self.activations.items[activation_index];
            if (!appendProcMapLine(
                output,
                &used,
                activation.guest_base,
                activation.guest_base +| activation.memory.len,
                activation.readable,
                activation.writable,
                activation.executable,
                "[rosette-activation]",
            )) break;
        }
        for (self.mappings.items) |mapping| {
            if (!appendProcMapLine(
                output,
                &used,
                mapping.guest_base,
                mapping.guest_base +| mapping.memory.len,
                mapping.readable,
                mapping.writable,
                mapping.executable,
                if (mapping.is_reservation) "[rosette-reservation]" else "[rosette-mapping]",
            )) break;
        }
        return output[0..used];
    }

    test "file-backed PROT_NONE reservation falls back to anonymous address space" {
        var manager = Manager.init(std.testing.allocator);
        defer manager.deinit();

        const impossible_file_backed: u32 = 0x0001;
        const base = manager.reserveAnywhereWithBacking(PAGE_64K, impossible_file_backed, -1, 0) orelse return error.TestUnexpectedResult;
        try std.testing.expect(base != 0);
        try std.testing.expectEqual(@as(u64, PAGE_64K), manager.total_reserved);
        try std.testing.expect(manager.bytes(base, 1, false) == null);
        try std.testing.expect(manager.protect(base, std.heap.page_size_min, 3));
        try std.testing.expect(manager.bytes(base, 1, true) != null);
    }

    fn find(self: *Manager, address: u64, length: u64) ?struct { mapping: *Mapping, offset: usize } {
        const end = std.math.add(u64, address, length) catch return null;
        for (self.mappings.items) |*mapping| {
            if (mapping.is_reservation) continue;
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (address >= mapping.guest_base and end <= mapping_end)
                return .{ .mapping = mapping, .offset = @intCast(address - mapping.guest_base) };
        }
        return null;
    }

    fn appendActivation(self: *Manager, guest_base: u64, memory: []u8, prot_raw: u32) !void {
        // Newer mprotect calls supersede older permission records for the same
        // exact span. Reverse lookup below also handles contained updates.
        self.protection_sequence +%= 1;
        if (self.protection_sequence == 0) self.protection_sequence = 1;
        try self.activations.append(self.allocator, .{
            .guest_base = guest_base,
            .memory = memory,
            .readable = prot_raw & 1 != 0,
            .writable = prot_raw & 2 != 0,
            .executable = prot_raw & 4 != 0,
            .sequence = self.protection_sequence,
        });
    }

    pub fn activeBytes(self: *Manager, address: u64, length: u64, write: bool) ?[]u8 {
        const end = std.math.add(u64, address, length) catch return null;
        var index = self.activations.items.len;
        while (index != 0) {
            index -= 1;
            const active = &self.activations.items[index];
            const active_end = active.guest_base + active.memory.len;
            if (address >= active_end or end <= active.guest_base) continue;
            if (address < active.guest_base or end > active_end) return null;
            if (write and !active.writable) return null;
            if (!write and !active.readable) return null;
            const offset: usize = @intCast(address - active.guest_base);
            return active.memory[offset..][0..@intCast(length)];
        }
        return null;
    }

    fn activeBytesConst(self: *const Manager, address: u64, length: u64) ?[]const u8 {
        const end = std.math.add(u64, address, length) catch return null;
        var index = self.activations.items.len;
        while (index != 0) {
            index -= 1;
            const active = &self.activations.items[index];
            const active_end = active.guest_base + active.memory.len;
            if (address >= active_end or end <= active.guest_base) continue;
            if (address < active.guest_base or end > active_end or !active.readable) return null;
            const offset: usize = @intCast(address - active.guest_base);
            return active.memory[offset..][0..@intCast(length)];
        }
        return null;
    }

    fn removeActivationsWithin(self: *Manager, guest_base: u64, length: u64) void {
        const end = guest_base +| length;
        var index = self.activations.items.len;
        while (index != 0) {
            index -= 1;
            const active = self.activations.items[index];
            const active_end = active.guest_base +| active.memory.len;
            if (active.guest_base >= guest_base and active_end <= end) _ = self.activations.swapRemove(index);
        }
    }

    fn activateReservationRange(self: *Manager, guest_base: u64, length: u64, prot_raw: u32) bool {
        const end = std.math.add(u64, guest_base, length) catch return false;
        for (self.mappings.items) |mapping| {
            if (!mapping.is_reservation) continue;
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (guest_base < mapping.guest_base or end > mapping_end) continue;
            const offset: usize = @intCast(guest_base - mapping.guest_base);
            const requested_length = std.math.cast(usize, length) orelse return false;
            const host_span = hostPageSpan(offset, requested_length, mapping.memory.len) orelse return false;
            const host_memory = @as([]align(std.heap.page_size_min) u8, @alignCast(mapping.memory[host_span.offset..][0..host_span.length]));
            if (mprotect(host_memory.ptr, host_memory.len, @as(c_int, @intCast(hostBackingProtection(prot_raw)))) != 0) return false;
            const memory = mapping.memory[offset..][0..requested_length];
            self.appendActivation(guest_base, memory, prot_raw) catch return false;
            return true;
        }
        return false;
    }

    fn findConst(self: *const Manager, address: u64, length: u64) ?struct { mapping: *const Mapping, offset: usize } {
        const end = std.math.add(u64, address, length) catch return null;
        for (self.mappings.items) |*mapping| {
            if (mapping.is_reservation) continue;
            const mapping_end = mapping.guest_base + mapping.memory.len;
            if (address >= mapping.guest_base and end <= mapping_end)
                return .{ .mapping = mapping, .offset = @intCast(address - mapping.guest_base) };
        }
        return null;
    }
};

fn appendProcMapLine(
    output: []u8,
    used: *usize,
    begin: u64,
    end: u64,
    readable: bool,
    writable: bool,
    executable: bool,
    label: []const u8,
) bool {
    if (begin >= end or used.* >= output.len) return false;
    const protection = [4]u8{
        if (readable) 'r' else '-',
        if (writable) 'w' else '-',
        if (executable) 'x' else '-',
        'p',
    };
    const line = std.fmt.bufPrint(
        output[used.*..],
        "{x}-{x} {s} 00000000 00:00 0 {s}\n",
        .{ begin, end, protection[0..], label },
    ) catch return false;
    used.* += line.len;
    return true;
}

fn isRecoverableFixedMmapFailure(err: anyerror) bool {
    return err == error.MemoryMappingNotSupported or
        err == error.PermissionDenied or
        err == error.OutOfMemory or
        err == error.InvalidArgument;
}

test "64K guest mapping alignment is explicit" {
    try std.testing.expectEqual(@as(u64, 65536), PAGE_64K);
}

test "file-backed offsets use Darwin VM alignment rather than guest tracking alignment" {
    try std.testing.expect(fileOffsetIsHostAligned(guest_memory_geometry.host_vm_page_size));
    if (guest_memory_geometry.host_vm_page_size > PAGE_4K) {
        try std.testing.expect(!fileOffsetIsHostAligned(PAGE_4K));
    }
}

test "fixed anonymous guest range uses independent host backing" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();

    const darwin_map_private_anonymous_fixed: u32 = 0x0002 | 0x1000 | 0x0010;
    try std.testing.expect(manager.mapFile(0x8000_0000, PAGE_64K, 3, darwin_map_private_anonymous_fixed, -1, 0));
    const bytes = manager.bytes(0x8000_0000, 16, true) orelse return error.TestUnexpectedResult;
    bytes[0] = 0xA5;
    try std.testing.expectEqual(@as(u8, 0xA5), manager.bytesConst(0x8000_0000, 1).?[0]);
}

test "OS-selected sparse mapping preserves permissions outside the guest heap" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();

    const anonymous_private: u32 = 0x1000 | 0x2;
    const base = manager.mapAnywhereWithBacking(PAGE_64K, 3, anonymous_private, -1, 0) orelse return error.TestUnexpectedResult;
    try std.testing.expect(base != 0);
    try std.testing.expect(manager.contains(base, PAGE_64K));
    try std.testing.expect(!manager.isExecutable(base, 1));
    const bytes = manager.bytes(base, 1, true) orelse return error.TestUnexpectedResult;
    bytes[0] = 0xC3;
    try std.testing.expectEqual(@as(u8, 0xC3), manager.bytesConst(base, 1).?[0]);
    try std.testing.expect(manager.protect(base, PAGE_64K, 5));
    try std.testing.expect(manager.isExecutable(base, 1));
    try std.testing.expectEqual(@as(u8, 0xC3), manager.executableBytesConst(base, 1).?[0]);
}

test "proc maps view reports newest guest protection before its reservation" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();

    const base = manager.reserveAnywhere(PAGE_64K) orelse return error.TestUnexpectedResult;
    try std.testing.expect(manager.protect(base, PAGE_4K, 0));
    try std.testing.expect(manager.protect(base, PAGE_4K, PROT_READ | PROT_WRITE));

    var output: [4096]u8 = undefined;
    const maps = manager.renderProcSelfMaps(&output);
    var expected_buffer: [128]u8 = undefined;
    const expected = try std.fmt.bufPrint(
        &expected_buffer,
        "{x}-{x} rw-p",
        .{ base, base + PAGE_4K },
    );
    try std.testing.expect(std.mem.startsWith(u8, maps, expected));
    try std.testing.expect(std.mem.indexOf(u8, maps, "[rosette-reservation]") != null);
}

test "guest MAP_JIT execute permission uses non-executable host backing" {
    try std.testing.expectEqual(@as(u32, PROT_READ | PROT_WRITE), hostBackingProtection(PROT_READ | PROT_WRITE | PROT_EXEC));
    try std.testing.expectEqual(@as(u32, PROT_READ), hostBackingProtection(PROT_READ | PROT_EXEC));
    if (comptime builtin.os.tag == .macos) {
        try std.testing.expectEqual(@as(u32, 0x1002), hostBackingFlags(0x1802));
    }
}

test "mmap length is rounded to the Darwin host page" {
    try std.testing.expectEqual(@as(?u64, std.heap.page_size_min), pageRoundedLength(std.heap.page_size_min - 1));
    try std.testing.expectEqual(@as(?u64, 0x2000_0000), pageRoundedLength(0x1FFF_FFFF));
    try std.testing.expectEqual(@as(?u64, 0x1000_0000), pageRoundedLength(0x0FFF_FFFF));
}

test "guest protection range is widened only at the host syscall boundary" {
    const host_page = std.heap.page_size_min;
    const guest_page: usize = @intCast(PAGE_4K);
    const guest_offset: usize = if (host_page > guest_page) guest_page else 0;
    const span = hostPageSpan(guest_offset, guest_page, host_page * 2) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 0), span.offset);
    try std.testing.expectEqual(host_page, span.length);
}

test "guest protection rounds a partial final guest page" {
    try std.testing.expectEqual(@as(?u64, PAGE_64K), guestProtectionRoundedLength(0x9FFF_0000, PAGE_64K - 1));
    try std.testing.expectEqual(@as(?u64, PAGE_4K), guestProtectionRoundedLength(0x9FFF_0000, PAGE_4K));
    try std.testing.expectEqual(@as(?u64, null), guestProtectionRoundedLength(0x9FFF_0000, 0));
    try std.testing.expectEqual(@as(?u64, null), guestProtectionRoundedLength(std.math.maxInt(u64) - PAGE_4K, PAGE_64K));
}

test "partial final guest page remains accessible after protect" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const anonymous_private: u32 = 0x1000 | 0x2;
    const base = manager.mapAnywhereWithBacking(
        PAGE_64K,
        0,
        anonymous_private,
        -1,
        0,
    ) orelse return error.TestUnexpectedResult;

    try std.testing.expect(manager.protect(base, PAGE_64K - 1, PROT_READ | PROT_WRITE));
    const tail = manager.bytes(base + PAGE_64K - 4, 4, true) orelse return error.TestUnexpectedResult;
    tail[0] = 0xA5;
    try std.testing.expectEqual(@as(u8, 0xA5), manager.bytesConst(base + PAGE_64K - 4, 1).?[0]);
    try std.testing.expectEqual(@as(usize, PAGE_64K), manager.activations.items[manager.activations.items.len - 1].memory.len);
}

test "backend hint mapping enforces a low 32-bit result window" {
    if (comptime builtin.os.tag != .macos) return;
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();

    const anonymous_private: u32 = 0x1000 | 0x2;
    const base = manager.mapAnywhereWithHintAndBacking(
        PAGE_64K,
        PROT_READ | PROT_WRITE | PROT_EXEC,
        anonymous_private | DARWIN_MAP_JIT,
        -1,
        0,
        0xA000_0000,
        0x1_0000_0000,
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expect(base + PAGE_64K <= 0x1_0000_0000);
    try std.testing.expect(manager.isExecutable(base, 1));
    try std.testing.expect(manager.bytes(base, 1, true) != null);
}

test "reserve large address space region" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const ok = manager.reserveLarge(0x100000000, 1024 * 1024 * 1024);
    try std.testing.expect(ok);
    try std.testing.expectEqual(@as(u64, 1024 * 1024 * 1024), manager.total_reserved);
}

test "reserve 4 GiB anywhere without guest heap backing" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const four_gib: u64 = 4 * 1024 * 1024 * 1024;
    const base = manager.reserveAnywhere(four_gib) orelse return error.TestUnexpectedResult;
    try std.testing.expect(base != 0);
    try std.testing.expectEqual(four_gib, manager.total_reserved);
    try std.testing.expect(manager.contains(base, 1) == false);
    try std.testing.expect(manager.protect(base, PAGE_64K, 3));
    try std.testing.expect(manager.contains(base, 1));
}

test "partial activation and fixed mapping preserve surrounding reservation" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const base = manager.reserveAnywhere(2 * PAGE_64K) orelse return error.TestUnexpectedResult;
    try std.testing.expect(manager.protect(base, PAGE_64K, 3));
    try std.testing.expect(manager.bytes(base, 1, true) != null);
    try std.testing.expect(manager.bytes(base + PAGE_64K, 1, false) == null);

    const fixed_anon_private: u32 = 0x0010 | 0x1000 | 0x0002;
    try std.testing.expect(manager.mapFixed(base + PAGE_64K, PAGE_64K, 3, fixed_anon_private, -1, 0));
    try std.testing.expect(manager.bytes(base, 1, true) != null);
    try std.testing.expect(manager.bytes(base + PAGE_64K, 1, true) != null);
    try std.testing.expectEqual(@as(u64, 2 * PAGE_64K), manager.total_reserved);
    try std.testing.expect(manager.unmap(base + PAGE_64K, PAGE_64K));
    try std.testing.expect(manager.bytes(base, 1, true) != null);
    try std.testing.expect(manager.bytes(base + PAGE_64K, 1, false) == null);
}

test "4K guest protection succeeds inside a larger host page" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const host_page = std.heap.page_size_min;
    const base = manager.reserveAnywhere(host_page * 2) orelse return error.TestUnexpectedResult;
    const guest_offset: u64 = if (host_page > @as(usize, @intCast(PAGE_4K))) PAGE_4K else 0;
    const guest_base = base + guest_offset;

    try std.testing.expect(manager.protect(guest_base, PAGE_4K, PROT_READ | PROT_WRITE));
    const bytes = manager.bytes(guest_base, PAGE_4K, true) orelse return error.TestUnexpectedResult;
    bytes[0] = 0xA5;
    try std.testing.expectEqual(@as(u8, 0xA5), manager.bytesConst(guest_base, 1).?[0]);
    if (guest_offset != 0) try std.testing.expect(manager.bytes(base, 1, false) == null);
}

test "high fixed anonymous mapping falls back to guest modeled backing" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();

    const fixed_anon_private: u32 = 0x0010 | 0x1000 | 0x0002;
    const guest_base: u64 = 0x40dfffc000;
    try std.testing.expect(manager.mapFixed(guest_base, 19136, 3, fixed_anon_private, -1, 0));
    const bytes = manager.bytes(guest_base, 8, true) orelse return error.TestUnexpectedResult;
    bytes[0] = 0x5A;
    try std.testing.expectEqual(@as(u8, 0x5A), manager.bytesConst(guest_base, 1).?[0]);
}

// The shape observed under Xenia: the same guest range is MAP_FIXED once per
// guest thread. Each request replaces the previous mapping, so bytes the guest
// stored through the earlier lifetime are gone — and every observer keyed by
// guest address still believes its records describe live memory. The query has
// to answer *before* the map, because afterwards the evidence is already lost.
test "a repeated fixed mapping is predicted as a replacement before it happens" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();

    const fixed_anon_private: u32 = 0x0010 | 0x1000 | 0x0002;
    const guest_base: u64 = 0x40dfffc000;
    const length: u64 = 19136;

    try std.testing.expect(!manager.replacesExisting(guest_base, length));
    try std.testing.expect(manager.mapFixed(guest_base, length, 3, fixed_anon_private, -1, 0));

    const bytes = manager.bytes(guest_base, 8, true) orelse return error.TestUnexpectedResult;
    bytes[0] = 0x5A;

    // Same base, same length: the exact-match rule fires and the contents go.
    try std.testing.expect(manager.replacesExisting(guest_base, length));
    // A different length at the same base is not an exact match, so it is a
    // rejected overlap rather than a replacement, and must not be predicted as
    // one.
    try std.testing.expect(!manager.replacesExisting(guest_base, length + PAGE_4K));

    try std.testing.expect(manager.mapFixed(guest_base, length, 3, fixed_anon_private, -1, 0));
    try std.testing.expectEqual(@as(u8, 0), manager.bytesConst(guest_base, 1).?[0]);
}

// The scan a guest runs to find a free slot: ask for an address, check what it
// got, move on if it is not what it asked for. The hint must be honoured when
// the range is free and refused — not silently replaced — when it is not.
test "an address hint is honoured while free and refused once taken" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();

    const fixed_anon_private: u32 = 0x0010 | 0x1000 | 0x0002;
    const slot0: u64 = 0x40dfffc000;
    const slot1: u64 = 0x41dfffc000;
    const length: u64 = 19136;
    const rounded = pageRoundedLength(length).?;

    try std.testing.expect(manager.rangeIsFree(slot0, rounded));
    try std.testing.expect(manager.mapFixed(slot0, length, 3, fixed_anon_private, -1, 0));

    const bytes = manager.bytes(slot0, 8, true) orelse return error.TestUnexpectedResult;
    bytes[0] = 0x5A;

    // Occupied: the caller must be told to look elsewhere rather than have the
    // live mapping replaced under it.
    try std.testing.expect(!manager.rangeIsFree(slot0, rounded));
    // Partial overlap is still occupied.
    try std.testing.expect(!manager.rangeIsFree(slot0 + PAGE_4K, rounded));
    // The next slot the scan would try is free.
    try std.testing.expect(manager.rangeIsFree(slot1, rounded));
    try std.testing.expect(manager.mapFixed(slot1, length, 3, fixed_anon_private, -1, 0));

    // The first slot's contents survived the second placement.
    try std.testing.expectEqual(@as(u8, 0x5A), manager.bytesConst(slot0, 1).?[0]);
}

test "new protection overrides an older broad activation" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const base = manager.reserveAnywhere(PAGE_64K) orelse return error.TestUnexpectedResult;
    try std.testing.expect(manager.protect(base, PAGE_64K, 3));
    try std.testing.expect(manager.protect(base, std.heap.page_size_min, 0));
    try std.testing.expect(manager.bytes(base, 1, false) == null);
    try std.testing.expect(manager.bytes(base + std.heap.page_size_min, 1, true) != null);
}

test "writable stack interior survives adjacent guard activations" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const base = manager.reserveAnywhere(3 * PAGE_64K) orelse return error.TestUnexpectedResult;
    try std.testing.expect(manager.protect(base, 3 * PAGE_64K, PROT_READ | PROT_WRITE));
    try std.testing.expect(manager.protect(base, PAGE_64K, 0));
    try std.testing.expect(manager.protect(base + 2 * PAGE_64K, PAGE_64K, 0));
    // Reassert the usable interval after both guards, matching Xenia's stack
    // allocation contract on translated hosts with larger VM pages.
    try std.testing.expect(manager.protect(base + PAGE_64K, PAGE_64K, PROT_READ | PROT_WRITE));

    try std.testing.expect(manager.bytes(base, 1, true) == null);
    try std.testing.expect(manager.bytes(base + PAGE_64K + PAGE_64K - 0xD8, 8, true) != null);
    try std.testing.expect(manager.bytes(base + 2 * PAGE_64K, 1, true) == null);
}

test "partial guards do not revoke a normal sparse mapping interior" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const anonymous_private: u32 = 0x1000 | 0x2;
    const base = manager.mapAnywhereWithBacking(
        3 * PAGE_64K,
        PROT_READ | PROT_WRITE,
        anonymous_private,
        -1,
        0,
    ) orelse return error.TestUnexpectedResult;

    try std.testing.expect(manager.protect(base, PAGE_64K, 0));
    try std.testing.expect(manager.protect(base + 2 * PAGE_64K, PAGE_64K, 0));

    try std.testing.expect(manager.bytes(base, 1, true) == null);
    try std.testing.expect(manager.bytes(base + 2 * PAGE_64K - 0xD8, 8, true) != null);
    try std.testing.expect(manager.bytes(base + 2 * PAGE_64K, 1, true) == null);
}

test "protect changes mapping permissions" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const base: u64 = 0x100000000;
    _ = manager.reserveLarge(base, 64 * 1024);
    const ok = manager.protect(base, 64 * 1024, 3);
    _ = ok;
}

test "zero fill mapped region" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const base: u64 = 0x100000000;
    _ = manager.reserveLarge(base, 64 * 1024);
    _ = manager.protect(base, 64 * 1024, 3);
    const region = manager.bytes(base, 64, true) orelse return error.SkipZigTest;
    region[0] = 0xFF;
    try std.testing.expectEqual(@as(u8, 0xFF), region[0]);
    _ = manager.zeroFill(base, 64);
    try std.testing.expectEqual(@as(u8, 0), region[0]);
}

test "page cache invalidates on unmap" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const anonymous_private: u32 = 0x1000 | 0x2;
    const base = manager.mapAnywhereWithBacking(PAGE_64K, PROT_READ | PROT_WRITE, anonymous_private, -1, 0) orelse return error.TestUnexpectedResult;
    // Prime the page cache with a .covered entry for the first page.
    try std.testing.expect(manager.contains(base, 1));
    try std.testing.expect(manager.bytes(base, 1, false) != null);
    // Unmap must bump the generation so the stale .covered entry is ignored.
    try std.testing.expect(manager.unmap(base, PAGE_64K));
    try std.testing.expect(!manager.contains(base, 1));
    try std.testing.expect(manager.bytes(base, 1, false) == null);
}

test "page cache invalidates on protect permission change" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const anonymous_private: u32 = 0x1000 | 0x2;
    const base = manager.mapAnywhereWithBacking(PAGE_64K, PROT_READ | PROT_WRITE, anonymous_private, -1, 0) orelse return error.TestUnexpectedResult;
    // Prime the cache while the page is read-only (not executable).
    try std.testing.expect(!manager.isExecutable(base, 1));
    try std.testing.expect(manager.bytes(base, 1, true) != null);
    // protect to R+X must invalidate the cached non-executable classification.
    try std.testing.expect(manager.protect(base, PAGE_64K, PROT_READ | PROT_EXEC));
    try std.testing.expect(manager.isExecutable(base, 1));
}

test "page cache invalidates when a new mapping appears at a none page" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const anonymous_private: u32 = 0x1000 | 0x2;
    const base: u64 = 0x1_0000_0000;
    // Prime the cache with a .none entry (nothing mapped here).
    try std.testing.expect(!manager.contains(base, 1));
    try std.testing.expect(manager.mapFixed(base, PAGE_64K, PROT_READ | PROT_WRITE, anonymous_private, -1, 0));
    try std.testing.expect(manager.contains(base, 1));
    try std.testing.expect(manager.bytes(base, 1, false) != null);
}
